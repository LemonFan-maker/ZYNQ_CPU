from __future__ import annotations

import dataclasses
import enum
import sys
from typing import TextIO

from .block import BLOCK_DEVICE_BASE, BLOCK_DEVICE_SIZE, BlockDevice
from .memory import MASK32, Memory, s32, sext
from .plic import PLIC_BASE, PLIC_SIZE, Plic
from .virtio import VIRTIO_MMIO_BASE, VIRTIO_MMIO_SIZE, VirtioMmioBlockDevice


SSTATUS_SIE = 1 << 1
SSTATUS_SPIE = 1 << 5
SSTATUS_SPP = 1 << 8
SSTATUS_SUM = 1 << 18
SSTATUS_MXR = 1 << 19
SIP_STIP = 1 << 5
SIP_SEIP = 1 << 9
MSTATUS_MIE = 1 << 3
MSTATUS_MPIE = 1 << 7
MSTATUS_MPP_SHIFT = 11
MSTATUS_MPP_MASK = 0x3 << MSTATUS_MPP_SHIFT
MIP_MTIP = 1 << 7
MIP_MEIP = 1 << 11
ACCESS_FETCH = 0
ACCESS_LOAD = 1
ACCESS_STORE = 2
ACCESS_CAUSES = (12, 13, 15)
DecodedInst = tuple[int, int, int, int, int, int, int, int, int, int, int, int, int]


class StopReason(enum.Enum):
    RUNNING = "running"
    MAX_STEPS = "max-steps"
    WFI = "wfi"
    BREAKPOINT = "breakpoint"
    ERROR = "error"


class SimError(RuntimeError):
    pass


class PageFault(SimError):
    def __init__(self, cause: int, vaddr: int) -> None:
        self.cause = cause
        self.vaddr = vaddr & MASK32
        super().__init__(f"page fault cause={cause} vaddr=0x{self.vaddr:08x}")


@dataclasses.dataclass
class TraceConfig:
    pc: bool = False
    trap: bool = False
    mem: bool = False
    csr: bool = False


@dataclasses.dataclass
class Cpu:
    mem: Memory
    pc: int = 0
    trace: TraceConfig = dataclasses.field(default_factory=TraceConfig)
    trace_out: TextIO = sys.stderr
    block: BlockDevice | None = None
    virtio_blk: VirtioMmioBlockDevice | None = None
    plic: Plic | None = None
    stop_on_wfi: bool = True

    def __post_init__(self) -> None:
        self.x = [0] * 32
        self.csrs: dict[int, int] = {
            0x300: 0x00001800,
            0x301: 0x40001105,  # misa: RV32 IMA
            0x305: 0,
            0x341: 0,
            0x342: 0,
            0x343: 0,
            0x344: 0,
            0xF14: 0,  # mhartid
        }
        self.priv = 3
        self.steps = 0
        self.last_error: str | None = None
        self.mtimecmp: int = 0
        self._satp = 0
        self._sstatus = 0
        self._mstatus = self.csrs[0x300]
        self._tlb_4k: dict[int, int] = {}
        self._tlb_4m: dict[int, int] = {}
        self._tlb_4k_last_key = -1
        self._tlb_4k_last_pbase = 0
        self._tlb_4m_last_key = -1
        self._tlb_4m_last_pbase = 0
        self._decode_cache: dict[int, DecodedInst] = {}
        self._run_max_steps: int | None = None
        if self.plic is None and self.virtio_blk is not None:
            self.plic = Plic(self.virtio_blk)

    def decode(self, inst: int) -> DecodedInst:
        decoded = self._decode_cache.get(inst)
        if decoded is not None:
            return decoded
        opcode = inst & 0x7F
        rd = (inst >> 7) & 0x1F
        funct3 = (inst >> 12) & 0x7
        rs1 = (inst >> 15) & 0x1F
        rs2 = (inst >> 20) & 0x1F
        funct7 = (inst >> 25) & 0x7F
        imm_i = sext(inst >> 20, 12)
        imm_s_raw = ((inst >> 7) & 0x1F) | (((inst >> 25) & 0x7F) << 5)
        imm_b_raw = (
            ((inst >> 31) & 0x1) << 12
            | ((inst >> 7) & 0x1) << 11
            | ((inst >> 25) & 0x3F) << 5
            | ((inst >> 8) & 0xF) << 1
        )
        imm_j_raw = (
            ((inst >> 31) & 0x1) << 20
            | ((inst >> 21) & 0x3FF) << 1
            | ((inst >> 20) & 0x1) << 11
            | ((inst >> 12) & 0xFF) << 12
        )
        decoded = (
            opcode,
            rd,
            funct3,
            rs1,
            rs2,
            funct7,
            imm_i,
            sext(imm_s_raw, 12),
            sext(imm_b_raw, 13),
            sext(imm_j_raw, 21),
            inst & 0xFFFFF000,
            (inst >> 20) & 0xFFF,
            (inst >> 27) & 0x1F,
        )
        self._decode_cache[inst] = decoded
        return decoded

    def _sv32_active(self) -> bool:
        return self.priv != 3 and ((self._satp >> 31) & 1) != 0

    def translate(self, vaddr: int, access: int) -> int:
        vaddr &= MASK32
        satp = self._satp
        if self.priv == 3 or ((satp >> 31) & 1) == 0:
            return vaddr
        cause = ACCESS_CAUSES[access]
        key_4k = (access << 21) | (self.priv << 20) | (vaddr >> 12)
        if key_4k == self._tlb_4k_last_key:
            return (self._tlb_4k_last_pbase | (vaddr & 0xFFF)) & MASK32
        cached = self._tlb_4k.get(key_4k)
        if cached is not None:
            self._tlb_4k_last_key = key_4k
            self._tlb_4k_last_pbase = cached
            return (cached | (vaddr & 0xFFF)) & MASK32
        key_4m = (access << 11) | (self.priv << 10) | (vaddr >> 22)
        if key_4m == self._tlb_4m_last_key:
            return (self._tlb_4m_last_pbase | (vaddr & 0x3FFFFF)) & MASK32
        cached = self._tlb_4m.get(key_4m)
        if cached is not None:
            self._tlb_4m_last_key = key_4m
            self._tlb_4m_last_pbase = cached
            return (cached | (vaddr & 0x3FFFFF)) & MASK32

        root = (satp & 0x003FFFFF) << 12
        vpn1 = (vaddr >> 22) & 0x3FF
        vpn0 = (vaddr >> 12) & 0x3FF
        off = vaddr & 0xFFF

        pte1_addr = root + vpn1 * 4
        pte1 = self.mem.read_u32(pte1_addr)
        if self._pte_invalid(pte1):
            raise PageFault(cause, vaddr)
        if self._pte_leaf(pte1):
            if ((pte1 >> 10) & 0x3FF) != 0:
                raise PageFault(cause, vaddr)
            self._check_pte_access(pte1, access, cause, vaddr)
            new_pte = self._pte_with_ad(pte1, access == ACCESS_STORE)
            if new_pte != pte1:
                self.mem.write_u32(pte1_addr, new_pte)
                pte1 = new_pte
            ppn1 = (pte1 >> 20) & 0xFFF
            pbase = (ppn1 << 22) & MASK32
            self._tlb_4m[key_4m] = pbase
            self._tlb_4m_last_key = key_4m
            self._tlb_4m_last_pbase = pbase
            return (pbase | (vpn0 << 12) | off) & MASK32

        pte0_addr = ((pte1 >> 10) << 12) + vpn0 * 4
        pte0 = self.mem.read_u32(pte0_addr)
        if self._pte_invalid(pte0) or not self._pte_leaf(pte0):
            raise PageFault(cause, vaddr)
        self._check_pte_access(pte0, access, cause, vaddr)
        new_pte = self._pte_with_ad(pte0, access == ACCESS_STORE)
        if new_pte != pte0:
            self.mem.write_u32(pte0_addr, new_pte)
            pte0 = new_pte
        pbase = ((pte0 >> 10) << 12) & MASK32
        self._tlb_4k[key_4k] = pbase
        self._tlb_4k_last_key = key_4k
        self._tlb_4k_last_pbase = pbase
        return (pbase | off) & MASK32

    def flush_tlb(self) -> None:
        self._tlb_4k.clear()
        self._tlb_4m.clear()
        self._tlb_4k_last_key = -1
        self._tlb_4m_last_key = -1

    @staticmethod
    def _pte_invalid(pte: int) -> bool:
        return (pte & 0x1) == 0 or ((pte & 0x4) != 0 and (pte & 0x2) == 0)

    @staticmethod
    def _pte_leaf(pte: int) -> bool:
        return (pte & 0xA) != 0

    @staticmethod
    def _pte_with_ad(pte: int, is_store: bool) -> int:
        return pte | 0x40 | (0x80 if is_store else 0)

    def _check_pte_access(self, pte: int, access: int, cause: int, vaddr: int) -> None:
        readable = (pte & 0x2) != 0
        writable = (pte & 0x4) != 0
        executable = (pte & 0x8) != 0
        user = (pte & 0x10) != 0
        sstatus = self._sstatus
        if access == ACCESS_LOAD and (sstatus & SSTATUS_MXR) != 0:
            readable = readable or executable
        if access == ACCESS_FETCH and not executable:
            raise PageFault(cause, vaddr)
        if access == ACCESS_LOAD and not readable:
            raise PageFault(cause, vaddr)
        if access == ACCESS_STORE and not writable:
            raise PageFault(cause, vaddr)
        if self.priv == 0 and not user:
            raise PageFault(cause, vaddr)
        if self.priv == 1 and access == ACCESS_FETCH and user:
            raise PageFault(cause, vaddr)
        if self.priv == 1 and access != ACCESS_FETCH and user and (sstatus & SSTATUS_SUM) == 0:
            raise PageFault(cause, vaddr)

    def reg(self, idx: int) -> int:
        return 0 if idx == 0 else self.x[idx]

    def set_reg(self, idx: int, value: int) -> None:
        if idx != 0:
            self.x[idx] = value & MASK32

    def csr_read(self, csr: int) -> int:
        if csr in (0xC00, 0xB00):  # cycle/mcycle
            return self.steps & MASK32
        if csr in (0xC80, 0xB80):  # cycleh/mcycleh
            return (self.steps >> 32) & MASK32
        if csr in (0xC01,):  # time
            return self.steps & MASK32
        if csr in (0xC81,):  # timeh
            return (self.steps >> 32) & MASK32
        if csr in (0xC02, 0xB02):  # instret/minstret
            return self.steps & MASK32
        if csr in (0xC82, 0xB82):
            return (self.steps >> 32) & MASK32
        if csr == 0x344:  # mip
            return self.csrs.get(csr, 0) | self._pending_mip_bits()
        if csr == 0x144:  # sip
            return (self.csrs.get(csr, 0) | self._pending_sip_bits()) & self.csr_read(0x303)
        return self.csrs.get(csr, 0)

    def csr_write(self, csr: int, value: int) -> None:
        value &= MASK32
        if csr in (0xC00, 0xC01, 0xC02, 0xC80, 0xC81, 0xC82):
            return
        self.csrs[csr] = value
        if csr == 0x100:
            self._sstatus = value
            self.flush_tlb()
        elif csr == 0x180:
            self._satp = value
            self.flush_tlb()
        elif csr == 0x300:
            self._mstatus = value
            self.flush_tlb()
        if self.trace.csr:
            print(f"csr[{csr:03x}] <- {value:08x}", file=self.trace_out)

    def load(self, addr: int, size: int, signed: bool) -> int:
        addr = self.translate(addr, ACCESS_LOAD)
        if 0x10000000 <= addr <= 0x10000007:
            if size != 4 or addr & 3:
                raise SimError(f"bad UART load at 0x{addr:08x}")
            if addr == 0x10000004:
                return 1
            return self.mem.read_u32(addr)
        if 0x10010000 <= addr <= 0x1001000F:
            if size != 4 or addr & 3:
                raise SimError(f"bad timer load at 0x{addr:08x}")
            if addr == 0x10010000:
                return self.steps & MASK32
            if addr == 0x10010004:
                return (self.steps >> 32) & MASK32
            if addr == 0x10010008:
                return self.mtimecmp & MASK32
            if addr == 0x1001000C:
                return (self.mtimecmp >> 32) & MASK32
        if self.block is not None and BLOCK_DEVICE_BASE <= addr < BLOCK_DEVICE_BASE + BLOCK_DEVICE_SIZE:
            if size != 4 or addr & 3:
                raise SimError(f"bad block-device load at 0x{addr:08x}")
            return self.block.read_u32(addr)
        if self.virtio_blk is not None and VIRTIO_MMIO_BASE <= addr < VIRTIO_MMIO_BASE + VIRTIO_MMIO_SIZE:
            try:
                return self.virtio_blk.read(addr, size)
            except ValueError as exc:
                raise SimError(str(exc)) from exc
        if self.plic is not None and PLIC_BASE <= addr < PLIC_BASE + PLIC_SIZE:
            if size != 4 or addr & 3:
                raise SimError(f"bad PLIC load at 0x{addr:08x}")
            return self.plic.read_u32(addr)
        if size == 1:
            value = self.mem.read_u8(addr)
            return sext(value, 8) & MASK32 if signed else value
        if size == 2:
            if addr & 1:
                raise SimError(f"misaligned lh at 0x{addr:08x}")
            value = self.mem.read_u16(addr)
            return sext(value, 16) & MASK32 if signed else value
        if size == 4:
            if addr & 3:
                raise SimError(f"misaligned lw at 0x{addr:08x}")
            return self.mem.read_u32(addr)
        raise AssertionError(size)

    def store(self, addr: int, size: int, value: int) -> None:
        addr = self.translate(addr, ACCESS_STORE)
        if self.trace.mem:
            print(f"mem[{addr:08x}]/{size} <- {value & MASK32:08x}", file=self.trace_out)
        if self.virtio_blk is not None and VIRTIO_MMIO_BASE <= addr < VIRTIO_MMIO_BASE + VIRTIO_MMIO_SIZE:
            try:
                self.virtio_blk.write(addr, size, value, self.mem)
            except ValueError as exc:
                raise SimError(str(exc)) from exc
            return
        if self.plic is not None and PLIC_BASE <= addr < PLIC_BASE + PLIC_SIZE:
            if size != 4 or addr & 3:
                raise SimError(f"bad PLIC store at 0x{addr:08x}")
            self.plic.write_u32(addr, value)
            return
        if size == 1:
            self.mem.write_u8(addr, value)
            return
        if size == 2:
            if addr & 1:
                raise SimError(f"misaligned sh at 0x{addr:08x}")
            self.mem.write_u16(addr, value)
            return
        if size == 4:
            if addr & 3:
                raise SimError(f"misaligned sw at 0x{addr:08x}")
            if 0x10010000 <= addr <= 0x1001000F:
                if addr == 0x10010008:
                    self.mtimecmp = (self.mtimecmp & 0xFFFFFFFF00000000) | (value & MASK32)
                    return
                if addr == 0x1001000C:
                    self.mtimecmp = ((value & MASK32) << 32) | (self.mtimecmp & MASK32)
                    return
                return
            if 0x10000000 <= addr <= 0x10000007:
                self.mem.write_u32(addr, value)
                return
            if self.block is not None and BLOCK_DEVICE_BASE <= addr < BLOCK_DEVICE_BASE + BLOCK_DEVICE_SIZE:
                self.block.write_u32(addr, value, self.mem)
                return
            self.mem.write_u32(addr, value)
            return
        raise AssertionError(size)

    def trap(self, cause: int, tval: int = 0, interrupt: bool = False) -> None:
        if self.trace.trap:
            print(f"trap cause={cause} pc={self.pc:08x} tval={tval:08x}", file=self.trace_out)
        delegated = False
        cause_bit = cause & 0x1F
        if self.priv <= 1:
            if interrupt:
                delegated = ((self.csr_read(0x303) >> cause_bit) & 1) != 0
            else:
                delegated = ((self.csr_read(0x302) >> cause_bit) & 1) != 0
        if delegated:
            self.csr_write(0x141, self.pc)
            self.csr_write(0x142, cause)
            self.csr_write(0x143, tval)
            sstatus = self.csr_read(0x100)
            sie = sstatus & SSTATUS_SIE
            sstatus = (sstatus & ~SSTATUS_SPP) | ((self.priv & 1) << 8)
            if sie:
                sstatus |= SSTATUS_SPIE
            else:
                sstatus &= ~SSTATUS_SPIE
            self.csr_write(0x100, sstatus & ~SSTATUS_SIE)
            self.priv = 1
            self.pc = self.csr_read(0x105) & ~0x3
            return
        self.csr_write(0x341, self.pc)
        self.csr_write(0x342, cause)
        self.csr_write(0x343, tval)
        mstatus = self.csr_read(0x300)
        mie = mstatus & MSTATUS_MIE
        mstatus = (mstatus & ~MSTATUS_MPP_MASK) | ((self.priv & 0x3) << MSTATUS_MPP_SHIFT)
        if mie:
            mstatus |= MSTATUS_MPIE
        else:
            mstatus &= ~MSTATUS_MPIE
        self.csr_write(0x300, mstatus & ~MSTATUS_MIE)
        self.priv = 3
        self.pc = self.csr_read(0x305) & ~0x3

    def mret(self) -> None:
        mstatus = self.csr_read(0x300)
        self.priv = (mstatus >> MSTATUS_MPP_SHIFT) & 0x3
        if mstatus & MSTATUS_MPIE:
            mstatus |= MSTATUS_MIE
        else:
            mstatus &= ~MSTATUS_MIE
        mstatus |= MSTATUS_MPIE
        mstatus &= ~MSTATUS_MPP_MASK
        self.csr_write(0x300, mstatus)
        self.pc = self.csr_read(0x341) & MASK32

    def sret(self) -> None:
        sstatus = self.csr_read(0x100)
        self.priv = 1 if (sstatus & SSTATUS_SPP) else 0
        if sstatus & SSTATUS_SPIE:
            sstatus |= SSTATUS_SIE
        else:
            sstatus &= ~SSTATUS_SIE
        sstatus |= SSTATUS_SPIE
        sstatus &= ~SSTATUS_SPP
        self.csr_write(0x100, sstatus)
        self.pc = self.csr_read(0x141) & MASK32

    def _check_interrupt(self) -> bool:
        if self._supervisor_interrupt_enabled():
            if self._timer_pending() and (self.csr_read(0x303) & SIP_STIP) != 0 and (self.csr_read(0x104) & SIP_STIP) != 0:
                self.trap(0x80000005, interrupt=True)
                return True
            if self._external_irq_pending() and (self.csr_read(0x303) & SIP_SEIP) != 0 and (self.csr_read(0x104) & SIP_SEIP) != 0:
                self.trap(0x80000009, interrupt=True)
                return True
        if self.priv == 3:
            if (self._mstatus & MSTATUS_MIE) == 0:
                return False
            if self._timer_pending() and (self.csr_read(0x304) & MIP_MTIP) != 0:
                self.trap(0x80000007, interrupt=True)
                return True
            if self._external_irq_pending() and (self.csr_read(0x304) & MIP_MEIP) != 0:
                self.trap(0x8000000B, interrupt=True)
                return True
        return False

    def _timer_pending(self) -> bool:
        return self.mtimecmp != 0 and self.steps >= self.mtimecmp

    def _external_irq_pending(self) -> bool:
        if self.plic is not None:
            return self.plic.irq_pending
        return self.virtio_blk is not None and self.virtio_blk.irq_pending

    def _pending_sip_bits(self) -> int:
        bits = 0
        if self._timer_pending():
            bits |= SIP_STIP
        if self._external_irq_pending():
            bits |= SIP_SEIP
        return bits

    def _pending_mip_bits(self) -> int:
        bits = 0
        if self._timer_pending():
            bits |= MIP_MTIP
        if self._external_irq_pending():
            bits |= SIP_SEIP | MIP_MEIP
        return bits

    def _supervisor_interrupt_enabled(self) -> bool:
        if self.priv > 1:
            return False
        return self.priv == 0 or (self._sstatus & SSTATUS_SIE) != 0

    def _timer_wfi_wait_enabled(self) -> bool:
        # WFI can resume for locally enabled interrupts even when global xIE is clear.
        if self.priv <= 1:
            return (
                (self.csr_read(0x303) & SIP_STIP) != 0
                and (self.csr_read(0x104) & SIP_STIP) != 0
            )
        return (self.csr_read(0x304) & MIP_MTIP) != 0

    def _fast_forward_wfi(self) -> None:
        if self.mtimecmp == 0 or self.steps >= self.mtimecmp:
            return
        if self._external_irq_pending() or not self._timer_wfi_wait_enabled():
            return
        target = self.mtimecmp
        if self._run_max_steps is not None:
            target = min(target, self._run_max_steps)
        if target > self.steps + 1:
            self.steps = target - 1

    def step(self) -> StopReason:
        if self._check_interrupt():
            self.steps += 1
            return StopReason.RUNNING
        try:
            inst_addr = self.translate(self.pc, ACCESS_FETCH)
            inst = self.mem.read_u32(inst_addr)
        except PageFault as exc:
            self.trap(exc.cause, exc.vaddr)
            self.steps += 1
            return StopReason.RUNNING
        old_pc = self.pc
        next_pc = (self.pc + 4) & MASK32
        if self.trace.pc:
            print(f"{self.steps:08d} pc={self.pc:08x} inst={inst:08x}", file=self.trace_out)

        opcode, rd, funct3, rs1, rs2, funct7, imm_i, imm_s, imm_b, imm_j, imm_u, csr, amo_funct5 = self.decode(inst)
        x = self.x

        try:
            if opcode == 0x37:  # LUI
                x[rd] = imm_u
            elif opcode == 0x17:  # AUIPC
                x[rd] = (old_pc + imm_u) & MASK32
            elif opcode == 0x6F:  # JAL
                x[rd] = next_pc
                next_pc = (old_pc + imm_j) & MASK32
            elif opcode == 0x67:  # JALR
                target = (x[rs1] + imm_i) & ~1
                x[rd] = next_pc
                next_pc = target & MASK32
            elif opcode == 0x63:  # branch
                a = x[rs1]
                b = x[rs2]
                if funct3 == 0:
                    take = a == b
                elif funct3 == 1:
                    take = a != b
                elif funct3 == 4:
                    take = (a if a < 0x80000000 else a - 0x100000000) < (b if b < 0x80000000 else b - 0x100000000)
                elif funct3 == 5:
                    take = (a if a < 0x80000000 else a - 0x100000000) >= (b if b < 0x80000000 else b - 0x100000000)
                elif funct3 == 6:
                    take = a < b
                elif funct3 == 7:
                    take = a >= b
                else:
                    raise SimError(f"illegal branch funct3 {funct3}")
                if take:
                    next_pc = (old_pc + imm_b) & MASK32
            elif opcode == 0x03:  # load
                addr = (x[rs1] + imm_i) & MASK32
                if funct3 == 0:
                    size, signed = 1, True
                elif funct3 == 1:
                    size, signed = 2, True
                elif funct3 == 2:
                    size, signed = 4, False
                elif funct3 == 4:
                    size, signed = 1, False
                elif funct3 == 5:
                    size, signed = 2, False
                else:
                    raise SimError(f"illegal load funct3 {funct3}")
                x[rd] = self.load(addr, size, signed)
            elif opcode == 0x23:  # store
                addr = (x[rs1] + imm_s) & MASK32
                if funct3 == 0:
                    size = 1
                elif funct3 == 1:
                    size = 2
                elif funct3 == 2:
                    size = 4
                else:
                    raise SimError(f"illegal store funct3 {funct3}")
                self.store(addr, size, x[rs2])
            elif opcode == 0x13:  # OP-IMM
                a = x[rs1]
                if funct3 == 0:
                    x[rd] = (a + imm_i) & MASK32
                elif funct3 == 1 and funct7 == 0:
                    x[rd] = (a << rs2) & MASK32
                elif funct3 == 2:
                    x[rd] = 1 if (a if a < 0x80000000 else a - 0x100000000) < imm_i else 0
                elif funct3 == 3:
                    x[rd] = 1 if a < (imm_i & MASK32) else 0
                elif funct3 == 4:
                    x[rd] = (a ^ imm_i) & MASK32
                elif funct3 == 5 and funct7 == 0:
                    x[rd] = a >> rs2
                elif funct3 == 5 and funct7 == 0x20:
                    x[rd] = ((a if a < 0x80000000 else a - 0x100000000) >> rs2) & MASK32
                elif funct3 == 6:
                    x[rd] = (a | imm_i) & MASK32
                elif funct3 == 7:
                    x[rd] = a & imm_i
                else:
                    raise SimError(f"illegal op-imm inst {inst:08x}")
            elif opcode == 0x33:  # OP
                a = x[rs1]
                b = x[rs2]
                if funct7 == 0x01:
                    self._exec_m(rd, funct3, a, b)
                elif funct3 == 0 and funct7 == 0:
                    x[rd] = (a + b) & MASK32
                elif funct3 == 0 and funct7 == 0x20:
                    x[rd] = (a - b) & MASK32
                elif funct3 == 1 and funct7 == 0:
                    x[rd] = (a << (b & 0x1F)) & MASK32
                elif funct3 == 2 and funct7 == 0:
                    x[rd] = 1 if (a if a < 0x80000000 else a - 0x100000000) < (b if b < 0x80000000 else b - 0x100000000) else 0
                elif funct3 == 3 and funct7 == 0:
                    x[rd] = 1 if a < b else 0
                elif funct3 == 4 and funct7 == 0:
                    x[rd] = a ^ b
                elif funct3 == 5 and funct7 == 0:
                    x[rd] = a >> (b & 0x1F)
                elif funct3 == 5 and funct7 == 0x20:
                    x[rd] = ((a if a < 0x80000000 else a - 0x100000000) >> (b & 0x1F)) & MASK32
                elif funct3 == 6 and funct7 == 0:
                    x[rd] = a | b
                elif funct3 == 7 and funct7 == 0:
                    x[rd] = a & b
                else:
                    raise SimError(f"illegal op inst {inst:08x}")
            elif opcode == 0x0F:  # fence/fence.i
                pass
            elif opcode == 0x2F:  # AMO, functional single-hart model
                self._exec_amo(rd, rs1, rs2, funct3, amo_funct5)
            elif opcode == 0x73:  # SYSTEM
                reason = self._exec_system(inst, rd, rs1, funct3, csr)
                if reason is not StopReason.RUNNING:
                    return reason
                if self.pc != old_pc:
                    next_pc = self.pc
            else:
                raise SimError(f"illegal opcode {opcode:02x} at 0x{old_pc:08x}")
        except PageFault as exc:
            self.trap(exc.cause, exc.vaddr)
            self.steps += 1
            return StopReason.RUNNING
        except SimError as exc:
            self.last_error = str(exc)
            return StopReason.ERROR

        self.pc = next_pc
        self.x[0] = 0
        self.steps += 1
        return StopReason.RUNNING

    def _exec_m(self, rd: int, funct3: int, a: int, b: int) -> None:
        if funct3 == 0:
            self.set_reg(rd, a * b)
        elif funct3 == 1:
            self.set_reg(rd, (s32(a) * s32(b)) >> 32)
        elif funct3 == 2:
            self.set_reg(rd, (s32(a) * b) >> 32)
        elif funct3 == 3:
            self.set_reg(rd, (a * b) >> 32)
        elif funct3 == 4:
            if b == 0:
                self.set_reg(rd, MASK32)
            elif a == 0x80000000 and b == 0xFFFFFFFF:
                self.set_reg(rd, a)
            else:
                self.set_reg(rd, int(s32(a) / s32(b)))
        elif funct3 == 5:
            self.set_reg(rd, MASK32 if b == 0 else a // b)
        elif funct3 == 6:
            if b == 0:
                self.set_reg(rd, a)
            elif a == 0x80000000 and b == 0xFFFFFFFF:
                self.set_reg(rd, 0)
            else:
                self.set_reg(rd, s32(a) % s32(b))
        elif funct3 == 7:
            self.set_reg(rd, a if b == 0 else a % b)
        else:
            raise SimError(f"illegal M funct3 {funct3}")

    def _exec_amo(self, rd: int, rs1: int, rs2: int, funct3: int, funct5: int) -> None:
        if funct3 != 2:
            raise SimError("only word AMOs are supported")
        addr = self.reg(rs1)
        old = self.load(addr, 4, False)
        value = self.reg(rs2)
        if funct5 == 0b00010:  # lr.w
            self.set_reg(rd, old)
            return
        if funct5 == 0b00011:  # sc.w
            self.store(addr, 4, value)
            self.set_reg(rd, 0)
            return
        if funct5 == 0b00001:
            new = value
        elif funct5 == 0b00000:
            new = old + value
        elif funct5 == 0b00100:
            new = old ^ value
        elif funct5 == 0b01100:
            new = old & value
        elif funct5 == 0b01000:
            new = old | value
        elif funct5 == 0b10000:
            new = old if s32(old) < s32(value) else value
        elif funct5 == 0b10100:
            new = old if s32(old) > s32(value) else value
        elif funct5 == 0b11000:
            new = old if old < value else value
        elif funct5 == 0b11100:
            new = old if old > value else value
        else:
            raise SimError(f"illegal AMO funct5 {funct5}")
        self.store(addr, 4, new)
        self.set_reg(rd, old)

    def _exec_system(self, inst: int, rd: int, rs1: int, funct3: int, csr: int) -> StopReason:
        if funct3 == 0:
            if inst == 0x00000073:  # ecall
                cause = {0: 8, 1: 9, 3: 11}.get(self.priv, 11)
                self.trap(cause)
                return StopReason.RUNNING
            if inst == 0x00100073:  # ebreak
                self.trap(3)
                return StopReason.RUNNING
            if inst == 0x30200073:
                self.mret()
                return StopReason.RUNNING
            if inst == 0x10200073:
                self.sret()
                return StopReason.RUNNING
            if inst == 0x10500073:
                if self.stop_on_wfi:
                    return StopReason.WFI
                self._fast_forward_wfi()
                return StopReason.RUNNING
            if (inst & 0xFE007FFF) == 0x12000073:  # sfence.vma
                self.flush_tlb()
                return StopReason.RUNNING
            # Other currently side-effect-free system instructions.
            return StopReason.RUNNING

        old = self.csr_read(csr)
        zimm = rs1
        source = self.reg(rs1)
        if funct3 == 1:
            self.csr_write(csr, source)
        elif funct3 == 2:
            if rs1 != 0:
                self.csr_write(csr, old | source)
        elif funct3 == 3:
            if rs1 != 0:
                self.csr_write(csr, old & ~source)
        elif funct3 == 5:
            self.csr_write(csr, zimm)
        elif funct3 == 6:
            if zimm != 0:
                self.csr_write(csr, old | zimm)
        elif funct3 == 7:
            if zimm != 0:
                self.csr_write(csr, old & ~zimm)
        else:
            raise SimError(f"illegal system funct3 {funct3}")
        self.set_reg(rd, old)
        return StopReason.RUNNING

    def run(self, max_steps: int, stop_pc: int | None = None) -> StopReason:
        previous_limit = self._run_max_steps
        self._run_max_steps = max_steps
        try:
            while self.steps < max_steps:
                if stop_pc is not None and self.pc == stop_pc:
                    return StopReason.BREAKPOINT
                reason = self.step()
                if reason is not StopReason.RUNNING:
                    return reason
            return StopReason.MAX_STEPS
        finally:
            self._run_max_steps = previous_limit
