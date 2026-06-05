#!/usr/bin/env python3
from __future__ import annotations

import pathlib
import tempfile
import unittest
from contextlib import redirect_stdout
from io import StringIO

from zx32elf import build_elf, assemble_source
from zx32sim.cpu import (
    MSTATUS_MIE,
    MSTATUS_MPIE,
    MSTATUS_MPP_MASK,
    MSTATUS_MPP_SHIFT,
    PageFault,
    SSTATUS_MXR,
    SSTATUS_SIE,
    SSTATUS_SPIE,
    SSTATUS_SPP,
    SSTATUS_SUM,
    Cpu,
    StopReason,
)
from zx32sim.plic import PLIC_BASE, PLIC_VIRTIO_BLK_IRQ
from zx32sim.block import (
    BLOCK_SECTOR_SIZE,
    CMD_READ,
    CMD_WRITE,
    REG_CAPACITY_LO,
    REG_COMMAND,
    REG_LBA_LO,
    REG_MEM_ADDR,
    REG_SECTOR_COUNT,
    REG_STATUS,
    STATUS_DONE,
    STATUS_ERROR,
    BlockDevice,
    BLOCK_DEVICE_BASE,
)
from zx32sim.elf import load_elf
from zx32sim.main import ConsoleSend, drain_console_ring, load_console_script, main as sim_main, read_console_ring, run_with_cli_stops, write_console_input
from zx32sim.memory import Memory
from zx32sim.virtio import VIRTIO_MMIO_BASE, VirtioMmioBlockDevice
from zx32sim.xsbl import CPU_LINUX_DTB, CPU_LINUX_ENTRY, load_xsbl_plan, ps_to_cpu_addr


class ZX32SimTests(unittest.TestCase):
    def run_source(self, source: str, max_steps: int = 1000) -> tuple[Cpu, Memory, StopReason]:
        words, symbols = assemble_source(source)
        entry = symbols.get("_start", 0)
        with tempfile.TemporaryDirectory() as tmp:
            path = pathlib.Path(tmp) / "test.elf"
            path.write_bytes(build_elf(words, 0, entry))
            image = load_elf(path)
        mem = Memory()
        for segment in image.segments:
            mem.load(segment.addr, segment.data)
        cpu = Cpu(mem=mem, pc=image.entry)
        reason = cpu.run(max_steps)
        return cpu, mem, reason

    def run_images(
        self,
        images: list[tuple[str, int]],
        entry: int,
        pokes: dict[int, int] | None = None,
        max_steps: int = 1000,
        stop_pc: int | None = None,
    ) -> tuple[Cpu, Memory, StopReason]:
        mem = Memory()
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = pathlib.Path(tmp)
            for idx, (source, load_addr) in enumerate(images):
                words, symbols = assemble_source(source)
                path = tmp_path / f"image{idx}.elf"
                path.write_bytes(build_elf(words, load_addr, load_addr + symbols.get("_start", 0)))
                image = load_elf(path)
                for segment in image.segments:
                    mem.load(segment.addr, segment.data)
        for addr, value in (pokes or {}).items():
            mem.write_u32(addr, value)
        cpu = Cpu(mem=mem, pc=entry)
        reason = cpu.run(max_steps, stop_pc=stop_pc)
        return cpu, mem, reason

    def test_entry_smoke_style_store(self) -> None:
        _cpu, mem, reason = self.run_source(
            """
            j fail
            _start:
                lui t0, 0x20010
                jal ra, main
                sw a0, 1008(t0)
                wfi
            main:
                lui a0, 0xabcd1
                addi a0, a0, 0x234
                ret
            fail:
                j fail
            """
        )
        self.assertEqual(reason, StopReason.WFI)
        self.assertEqual(mem.read_u32(0x200103F0), 0xABCD1234)

    def test_machine_ecall_trap_and_mret(self) -> None:
        _cpu, mem, reason = self.run_source(
            """
            addi t0, x0, 0x20
            addi t1, x0, 0
            csrw mtvec, t0
            ecall
            addi t2, x0, 0x99
            sw t2, 84(x0)
            wfi
            .org 0x20
            trap:
            csrr t3, mepc
            sw t3, 80(x0)
            csrr t4, mcause
            sw t4, 88(x0)
            addi t3, t3, 4
            csrw mepc, t3
            mret
            """
        )
        self.assertEqual(reason, StopReason.WFI)
        self.assertEqual(mem.read_u32(80), 12)
        self.assertEqual(mem.read_u32(84), 0x99)
        self.assertEqual(mem.read_u32(88), 11)

    def test_continue_on_wfi_keeps_running_until_interrupt(self) -> None:
        cpu = Cpu(mem=Memory(), pc=0x40, stop_on_wfi=False)
        cpu.mem.write_u32(0x40, 0x10500073)
        cpu.mem.write_u32(0x44, 0x10500073)
        cpu.priv = 1
        cpu.mtimecmp = 2
        cpu.csr_write(0x105, 0x100)
        cpu.csr_write(0x104, 0x20)
        cpu.csr_write(0x303, 0x20)
        cpu.csr_write(0x100, SSTATUS_SIE)

        reason = cpu.run(3)

        self.assertEqual(reason, StopReason.MAX_STEPS)
        self.assertEqual(cpu.priv, 1)
        self.assertEqual(cpu.pc, 0x100)
        self.assertEqual(cpu.csr_read(0x142), 0x80000005)

    def test_continue_on_wfi_fast_forwards_to_timer(self) -> None:
        cpu = Cpu(mem=Memory(), pc=0x40, stop_on_wfi=False)
        cpu.mem.write_u32(0x40, 0x10500073)
        cpu.priv = 1
        cpu.mtimecmp = 1000
        cpu.csr_write(0x104, 0x20)
        cpu.csr_write(0x303, 0x20)

        reason = cpu.step()

        self.assertEqual(reason, StopReason.RUNNING)
        self.assertEqual(cpu.steps, 1000)
        self.assertEqual(cpu.pc, 0x44)

    def test_xsbl_plan_maps_linux_downloads_to_simulator_loads(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            repo = pathlib.Path(tmp)
            (repo / "build/linux-mainline-rv32/arch/riscv/boot").mkdir(parents=True)
            (repo / "build/linux").mkdir(parents=True)
            (repo / "hw_bringup/build/elf").mkdir(parents=True)
            (repo / "hw_bringup/build").mkdir(parents=True, exist_ok=True)
            (repo / "build/vivado_hw/zynq_cpu_hw.runs/impl_1").mkdir(parents=True)
            image = repo / "build/linux-mainline-rv32/arch/riscv/boot/Image"
            dtb = repo / "build/linux/zynq_cpu.dtb"
            firmware = repo / "hw_bringup/build/elf/linux_boot_firmware.elf"
            launcher = repo / "hw_bringup/build/ps_linux_boot.elf"
            bit = repo / "build/vivado_hw/zynq_cpu_hw.runs/impl_1/zynq_cpu_system_wrapper.bit"
            for path in (image, dtb, firmware, launcher, bit):
                path.write_bytes(b"x")
            xsbl = repo / "hw_bringup/download_zynq_cpu_linux_boot.xsbl"
            xsbl.parent.mkdir(parents=True, exist_ok=True)
            xsbl.write_text(
                "\n".join(
                    [
                        "connect",
                        "targets -set -filter {name =~ \"ARM*#0\"}",
                        "rst -system",
                        "fpga -f ./build/vivado_hw/zynq_cpu_hw.runs/impl_1/zynq_cpu_system_wrapper.bit",
                        "source ./build/vivado_hw/zynq_cpu_hw.gen/sources_1/bd/zynq_cpu_system/ip/zynq_cpu_system_processing_system7_0_0/ps7_init.tcl",
                        "ps7_init",
                        "ps7_post_config",
                        "dow -data ./build/linux-mainline-rv32/arch/riscv/boot/Image 0x00500000",
                        "dow -data ./build/linux/zynq_cpu.dtb 0x01700000",
                        "dow ./hw_bringup/build/ps_linux_boot.elf",
                        "con",
                    ]
                ),
                encoding="utf-8",
            )

            plan = load_xsbl_plan(xsbl, repo, firmware)

        self.assertEqual(ps_to_cpu_addr(0x00500000), 0x80400000)
        self.assertEqual(ps_to_cpu_addr(0x01700000), 0x81600000)
        self.assertEqual([download.cpu_addr for download in plan.data_downloads], [0x80400000, 0x81600000])
        self.assertIn("--load-raw", plan.sim_argv())
        self.assertIn(f"0x{CPU_LINUX_ENTRY:08x}=0x80400000", plan.sim_argv())
        self.assertIn(f"0x{CPU_LINUX_DTB:08x}=0x81600000", plan.sim_argv())

    def test_supervisor_ecall_delegation(self) -> None:
        _cpu, mem, reason = self.run_source(
            pathlib.Path("hw_bringup/programs/supervisor_smoke.zx32.s").read_text(encoding="utf-8"),
            max_steps=1000,
        )
        self.assertEqual(reason, StopReason.MAX_STEPS)
        self.assertEqual(mem.read_u32(0x200103E0), 0x38)
        self.assertEqual(mem.read_u32(0x200103E4), 9)
        self.assertEqual(mem.read_u32(0x200103E8), 0x5A)
        self.assertEqual(mem.read_u32(0x200103F0), 0x222)

    def test_supervisor_timer_delegation(self) -> None:
        _cpu, mem, reason = self.run_source(
            pathlib.Path("hw_bringup/programs/supervisor_timer_smoke.zx32.s").read_text(encoding="utf-8"),
            max_steps=1000,
        )
        self.assertEqual(reason, StopReason.MAX_STEPS)
        self.assertEqual(mem.read_u32(0x200103E4), 0x80000005)
        self.assertEqual(mem.read_u32(0x200103E8), 0x5A)
        self.assertEqual(mem.read_u32(0x200103F0), 0x222)

    def test_sbi_timer_smoke_pair(self) -> None:
        firmware = pathlib.Path("hw_bringup/programs/sbi_timer_firmware_smoke.zx32.s").read_text(encoding="utf-8")
        payload = pathlib.Path("hw_bringup/programs/sbi_timer_payload_smoke.zx32.s").read_text(encoding="utf-8")
        _cpu, mem, reason = self.run_images(
            [(firmware, 0), (payload, 0x80000000)],
            entry=0,
            pokes={0x20010340: 0x80000000, 0x20010344: 0x80001000},
            max_steps=10000,
            stop_pc=0x80000098,
        )
        self.assertEqual(reason, StopReason.BREAKPOINT)
        self.assertEqual(mem.read_u32(0x2001034C), 9)
        self.assertEqual(mem.read_u32(0x20010354), 0x54494D45)
        self.assertEqual(mem.read_u32(0x20010358), 0)
        self.assertEqual(mem.read_u32(0x20010380), 0)
        self.assertEqual(mem.read_u32(0x20010384), 0x80001000)
        self.assertEqual(mem.read_u32(0x20010388), 0)
        self.assertEqual(mem.read_u32(0x2001038C), 0x80000005)
        self.assertEqual(mem.read_u32(0x200103F0), 0x222)

    def test_uart_status_is_ready(self) -> None:
        cpu = Cpu(mem=Memory())
        self.assertEqual(cpu.load(0x10000004, 4, signed=False), 1)
        cpu.store(0x10000000, 4, 0x5A)
        self.assertEqual(cpu.mem.read_u32(0x10000000), 0x5A)

    def test_block_device_reads_and_writes_sectors(self) -> None:
        disk = bytearray(BLOCK_SECTOR_SIZE * 2)
        disk[BLOCK_SECTOR_SIZE : BLOCK_SECTOR_SIZE + 8] = b"ZX32SIM!"
        cpu = Cpu(mem=Memory(), block=BlockDevice(disk))
        base = BLOCK_DEVICE_BASE

        self.assertEqual(cpu.load(base + REG_CAPACITY_LO, 4, signed=False), 2)
        cpu.store(base + REG_LBA_LO, 4, 1)
        cpu.store(base + REG_MEM_ADDR, 4, 0x2000)
        cpu.store(base + REG_SECTOR_COUNT, 4, 1)
        cpu.store(base + REG_COMMAND, 4, CMD_READ)
        self.assertEqual(cpu.load(base + REG_STATUS, 4, signed=False) & STATUS_DONE, STATUS_DONE)
        self.assertEqual(cpu.mem.read_bytes(0x2000, 8), b"ZX32SIM!")

        cpu.mem.load(0x3000, b"SDWRITE!" + b"\0" * (BLOCK_SECTOR_SIZE - 8))
        cpu.store(base + REG_LBA_LO, 4, 0)
        cpu.store(base + REG_MEM_ADDR, 4, 0x3000)
        cpu.store(base + REG_SECTOR_COUNT, 4, 1)
        cpu.store(base + REG_COMMAND, 4, CMD_WRITE)
        self.assertEqual(cpu.block.image[:8], b"SDWRITE!")

    def test_block_device_reports_readonly_write_error(self) -> None:
        cpu = Cpu(mem=Memory(), block=BlockDevice(bytearray(BLOCK_SECTOR_SIZE), readonly=True))
        base = BLOCK_DEVICE_BASE
        cpu.mem.load(0x2000, b"blocked" + b"\0" * (BLOCK_SECTOR_SIZE - 7))
        cpu.store(base + REG_MEM_ADDR, 4, 0x2000)
        cpu.store(base + REG_SECTOR_COUNT, 4, 1)
        cpu.store(base + REG_COMMAND, 4, CMD_WRITE)
        status = cpu.load(base + REG_STATUS, 4, signed=False)
        self.assertEqual(status & STATUS_ERROR, STATUS_ERROR)
        self.assertEqual(status & STATUS_DONE, STATUS_DONE)

    def test_virtio_block_reads_sector_and_interrupts(self) -> None:
        disk = bytearray(BLOCK_SECTOR_SIZE * 2)
        disk[BLOCK_SECTOR_SIZE : BLOCK_SECTOR_SIZE + 8] = b"VIRTIO!!"
        cpu = Cpu(mem=Memory(), virtio_blk=VirtioMmioBlockDevice(disk))
        self._setup_virtio_queue(cpu)
        self._write_virtio_blk_request(cpu.mem, request_type=0, sector=1, data_flags=2)

        cpu.store(VIRTIO_MMIO_BASE + 0x050, 4, 0)

        self.assertEqual(cpu.mem.read_bytes(0x2400, 8), b"VIRTIO!!")
        self.assertEqual(cpu.mem.read_u8(0x2500), 0)
        self.assertEqual(cpu.mem.read_u16(0x2202), 1)
        self.assertEqual(cpu.mem.read_u32(0x2204), 0)
        self.assertEqual(cpu.mem.read_u32(0x2208), BLOCK_SECTOR_SIZE + 1)

        cpu.store(PLIC_BASE + PLIC_VIRTIO_BLK_IRQ * 4, 4, 1)
        cpu.store(PLIC_BASE + 0x2000, 4, 1 << PLIC_VIRTIO_BLK_IRQ)
        cpu.store(PLIC_BASE + 0x200000, 4, 0)
        cpu.priv = 1
        cpu.pc = 0x80
        cpu.csr_write(0x105, 0x100)
        cpu.csr_write(0x104, 1 << 9)
        cpu.csr_write(0x303, 1 << 9)
        cpu.csr_write(0x100, SSTATUS_SIE)
        reason = cpu.step()
        self.assertEqual(reason, StopReason.RUNNING)
        self.assertEqual(cpu.pc, 0x100)
        self.assertEqual(cpu.csr_read(0x142), 0x80000009)
        self.assertEqual(cpu.load(PLIC_BASE + 0x200004, 4, signed=False), PLIC_VIRTIO_BLK_IRQ)
        cpu.store(VIRTIO_MMIO_BASE + 0x064, 4, 1)
        self.assertEqual(cpu.load(PLIC_BASE + 0x200004, 4, signed=False), 0)

    def test_virtio_block_writes_sector(self) -> None:
        cpu = Cpu(mem=Memory(), virtio_blk=VirtioMmioBlockDevice(bytearray(BLOCK_SECTOR_SIZE)))
        self._setup_virtio_queue(cpu)
        cpu.mem.load(0x2400, b"VIRTIO-WRITE" + b"\0" * (BLOCK_SECTOR_SIZE - 12))
        self._write_virtio_blk_request(cpu.mem, request_type=1, sector=0, data_flags=0)

        cpu.store(VIRTIO_MMIO_BASE + 0x050, 4, 0)

        self.assertEqual(cpu.virtio_blk.image[:12], b"VIRTIO-WRITE")
        self.assertEqual(cpu.mem.read_u8(0x2500), 0)

    def test_cli_virtio_block_image_is_written_back(self) -> None:
        source = """
            li t0, 0x10060000
            li s3, 0x2000
            li t4, 0x2300
            sw t4, 0(s3)
            sw x0, 4(s3)
            li t4, 16
            sw t4, 8(s3)
            li t4, 0x00010001
            sw t4, 12(s3)
            li t4, 0x2400
            sw t4, 16(s3)
            sw x0, 20(s3)
            li t4, 512
            sw t4, 24(s3)
            li t4, 0x00020001
            sw t4, 28(s3)
            li t4, 0x2500
            sw t4, 32(s3)
            sw x0, 36(s3)
            li t4, 1
            sw t4, 40(s3)
            li t4, 2
            sw t4, 44(s3)
            li t4, 1
            li s0, 0x2300
            sw t4, 0(s0)
            sw x0, 4(s0)
            sw x0, 8(s0)
            sw x0, 12(s0)
            li s1, 0x2400
            li t4, 0x5a5a1234
            sw t4, 0(s1)
            li s2, 0x2500
            sw x0, 0(s2)
            li t4, 0x00010000
            li s4, 0x2100
            sw t4, 0(s4)
            li t4, 8
            sw x0, 0x30(t0)
            sw t4, 0x38(t0)
            li t4, 0x2000
            sw t4, 0x80(t0)
            sw x0, 0x84(t0)
            li t4, 0x2100
            sw t4, 0x90(t0)
            sw x0, 0x94(t0)
            li t4, 0x2200
            sw t4, 0xa0(t0)
            sw x0, 0xa4(t0)
            li t4, 1
            sw t4, 0x44(t0)
            sw x0, 0x50(t0)
            lbu t4, 0(s2)
            li s4, 0x3e0
            sw t4, 0(s4)
            wfi
        """
        words, symbols = assemble_source(source)
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = pathlib.Path(tmp)
            elf = tmp_path / "virtio-writer.elf"
            disk = tmp_path / "sd.img"
            elf.write_bytes(build_elf(words, 0, symbols.get("_start", 0)))
            disk.write_bytes(b"\0" * BLOCK_SECTOR_SIZE)
            with redirect_stdout(StringIO()):
                rc = sim_main(
                    [
                        str(elf),
                        "--virtio-block-image",
                        str(disk),
                        "--max-steps",
                        "300",
                        "--poke-word",
                        "0x3e0=0xffffffff",
                        "--stop-word",
                        "0x3e0=0",
                        "--expect-word",
                        "0x3e0=0",
                    ]
                )
            self.assertEqual(rc, 0)
            self.assertEqual(disk.read_bytes()[:4], bytes.fromhex("34125a5a"))

    def test_cli_block_image_is_written_back(self) -> None:
        source = """
            li t0, 0x10050000
            li t1, 0x2000
            li t2, 0x5a5a1234
            sw t2, 0(t1)
            sw x0, 8(t0)
            sw t1, 16(t0)
            li t2, 1
            sw t2, 20(t0)
            li t2, 2
            sw t2, 4(t0)
            wfi
        """
        words, symbols = assemble_source(source)
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = pathlib.Path(tmp)
            elf = tmp_path / "writer.elf"
            disk = tmp_path / "sd.img"
            elf.write_bytes(build_elf(words, 0, symbols.get("_start", 0)))
            disk.write_bytes(b"\0" * BLOCK_SECTOR_SIZE)
            with redirect_stdout(StringIO()):
                rc = sim_main([str(elf), "--block-image", str(disk), "--max-steps", "100"])
            self.assertEqual(rc, 0)
            self.assertEqual(disk.read_bytes()[:4], bytes.fromhex("34125a5a"))

    def _setup_virtio_queue(self, cpu: Cpu) -> None:
        base = VIRTIO_MMIO_BASE
        self.assertEqual(cpu.load(base + 0x000, 4, signed=False), 0x74726976)
        self.assertEqual(cpu.load(base + 0x004, 4, signed=False), 2)
        self.assertEqual(cpu.load(base + 0x008, 4, signed=False), 2)
        self.assertEqual(cpu.load(base + 0x100, 4, signed=False), len(cpu.virtio_blk.image) // BLOCK_SECTOR_SIZE)
        cpu.store(base + 0x030, 4, 0)
        cpu.store(base + 0x038, 4, 8)
        cpu.store(base + 0x080, 4, 0x2000)
        cpu.store(base + 0x084, 4, 0)
        cpu.store(base + 0x090, 4, 0x2100)
        cpu.store(base + 0x094, 4, 0)
        cpu.store(base + 0x0A0, 4, 0x2200)
        cpu.store(base + 0x0A4, 4, 0)
        cpu.store(base + 0x044, 4, 1)

    def _write_virtio_blk_request(self, mem: Memory, request_type: int, sector: int, data_flags: int) -> None:
        desc = 0x2000
        mem.write_u32(desc + 0, 0x2300)
        mem.write_u32(desc + 4, 0)
        mem.write_u32(desc + 8, 16)
        mem.write_u32(desc + 12, (1 << 16) | 1)
        mem.write_u32(desc + 16, 0x2400)
        mem.write_u32(desc + 20, 0)
        mem.write_u32(desc + 24, BLOCK_SECTOR_SIZE)
        mem.write_u32(desc + 28, (2 << 16) | 1 | data_flags)
        mem.write_u32(desc + 32, 0x2500)
        mem.write_u32(desc + 36, 0)
        mem.write_u32(desc + 40, 1)
        mem.write_u32(desc + 44, 2)
        mem.write_u32(0x2300, request_type)
        mem.write_u32(0x2304, 0)
        mem.write_u32(0x2308, sector & 0xFFFFFFFF)
        mem.write_u32(0x230C, (sector >> 32) & 0xFFFFFFFF)
        mem.write_u8(0x2500, 0xFF)
        mem.write_u32(0x2100, 0x00010000)

    def test_sparse_memory_cross_page_access(self) -> None:
        mem = Memory()
        mem.write_u32(0x0FFE, 0xAABBCCDD)
        self.assertEqual(mem.read_u16(0x0FFE), 0xCCDD)
        self.assertEqual(mem.read_u32(0x0FFE), 0xAABBCCDD)
        mem.load(0x1FFE, b"wxyz")
        self.assertEqual(mem.read_u32(0x1FFE), 0x7A797877)

    def test_sv32_load_store_sets_access_dirty(self) -> None:
        mem = Memory()
        root = 0x1000
        leaf = 0x2000
        data = 0x3000
        va = 0x40000000
        vpn1 = (va >> 22) & 0x3FF
        vpn0 = (va >> 12) & 0x3FF
        mem.write_u32(root + vpn1 * 4, ((leaf >> 12) << 10) | 0x1)
        mem.write_u32(leaf + vpn0 * 4, ((data >> 12) << 10) | 0x7)
        cpu = Cpu(mem=mem)
        cpu.priv = 1
        cpu.csr_write(0x180, 0x80000000 | (root >> 12))
        cpu.store(va, 4, 0x12345678)
        self.assertEqual(mem.read_u32(data), 0x12345678)
        self.assertEqual(mem.read_u32(leaf + vpn0 * 4) & 0xC0, 0xC0)
        self.assertEqual(cpu.load(va, 4, signed=False), 0x12345678)

    def test_sv32_load_page_fault_delegates_to_smode(self) -> None:
        source = """
            addi t0, x0, trap
            csrw stvec, t0
            li t0, 0x2000
            srli t0, t0, 12
            li t1, 0x80000000
            or t0, t0, t1
            csrw satp, t0
            li t0, 0x00400000
            lw t1, 0(t0)
            li t2, 0x333
            sw t2, 0x3f0(x0)
            j done
        trap:
            csrr t3, scause
            sw t3, 0x3e4(x0)
            csrr t4, stval
            sw t4, 0x3e8(x0)
            li t5, 0x222
            sw t5, 0x3f0(x0)
        done:
            j done
        """
        words, symbols = assemble_source(source)
        mem = Memory()
        for idx, word in enumerate(words):
            mem.write_u32(idx * 4, word)
        root = 0x2000
        va = 0x00400000
        mem.write_u32(root, 0x0F)
        mem.write_u32(root + 4, 0)
        cpu = Cpu(mem=mem)
        cpu.priv = 1
        cpu.csr_write(0x302, 1 << 13)
        reason = cpu.run(100, stop_pc=symbols["done"])
        self.assertEqual(reason, StopReason.BREAKPOINT)
        self.assertEqual(mem.read_u32(0x3E4), 13)
        self.assertEqual(mem.read_u32(0x3E8), va)
        self.assertEqual(mem.read_u32(0x3F0), 0x222)

    def test_sret_restores_sie_and_returns_to_u_mode(self) -> None:
        cpu = Cpu(mem=Memory())
        cpu.priv = 1
        cpu.csr_write(0x141, 0x1234)
        cpu.csr_write(0x100, SSTATUS_SPIE)
        cpu.sret()
        self.assertEqual(cpu.priv, 0)
        self.assertEqual(cpu.pc, 0x1234)
        self.assertEqual(cpu.csr_read(0x100) & SSTATUS_SIE, SSTATUS_SIE)
        self.assertEqual(cpu.csr_read(0x100) & SSTATUS_SPIE, SSTATUS_SPIE)
        self.assertEqual(cpu.csr_read(0x100) & SSTATUS_SPP, 0)

    def test_mret_restores_mie_and_returns_to_s_mode(self) -> None:
        cpu = Cpu(mem=Memory())
        cpu.priv = 3
        cpu.csr_write(0x341, 0x80)
        cpu.csr_write(0x300, MSTATUS_MPIE | (1 << MSTATUS_MPP_SHIFT))
        cpu.mret()
        self.assertEqual(cpu.priv, 1)
        self.assertEqual(cpu.pc, 0x80)
        self.assertEqual(cpu.csr_read(0x300) & MSTATUS_MIE, MSTATUS_MIE)
        self.assertEqual(cpu.csr_read(0x300) & MSTATUS_MPIE, MSTATUS_MPIE)
        self.assertEqual(cpu.csr_read(0x300) & MSTATUS_MPP_MASK, 0)

    def test_u_mode_supervisor_timer_interrupt_delegates(self) -> None:
        cpu = Cpu(mem=Memory(), pc=0x40)
        cpu.priv = 0
        cpu.steps = 10
        cpu.mtimecmp = 5
        cpu.csr_write(0x105, 0x100)
        cpu.csr_write(0x104, 0x20)
        cpu.csr_write(0x303, 0x20)
        reason = cpu.step()
        self.assertEqual(reason, StopReason.RUNNING)
        self.assertEqual(cpu.priv, 1)
        self.assertEqual(cpu.pc, 0x100)
        self.assertEqual(cpu.csr_read(0x141), 0x40)
        self.assertEqual(cpu.csr_read(0x142), 0x80000005)
        self.assertEqual(cpu.csr_read(0x100) & SSTATUS_SPP, 0)

    def test_sv32_sum_and_mxr_permission_bits(self) -> None:
        mem = Memory()
        root = 0x1000
        leaf = 0x2000
        user_data = 0x3000
        exec_data = 0x4000
        user_va = 0x40000000
        exec_va = 0x40001000
        vpn1 = (user_va >> 22) & 0x3FF
        mem.write_u32(root + vpn1 * 4, ((leaf >> 12) << 10) | 0x1)
        mem.write_u32(leaf + (((user_va >> 12) & 0x3FF) * 4), ((user_data >> 12) << 10) | 0x17)
        mem.write_u32(leaf + (((exec_va >> 12) & 0x3FF) * 4), ((exec_data >> 12) << 10) | 0x19)
        mem.write_u32(user_data, 0x12345678)
        mem.write_u32(exec_data, 0xAABBCCDD)
        cpu = Cpu(mem=mem)
        cpu.priv = 1
        cpu.csr_write(0x180, 0x80000000 | (root >> 12))

        with self.assertRaises(PageFault):
            cpu.load(user_va, 4, signed=False)
        cpu.csr_write(0x100, SSTATUS_SUM)
        self.assertEqual(cpu.load(user_va, 4, signed=False), 0x12345678)
        with self.assertRaises(PageFault):
            cpu.load(exec_va, 4, signed=False)
        cpu.csr_write(0x100, SSTATUS_SUM | SSTATUS_MXR)
        self.assertEqual(cpu.load(exec_va, 4, signed=False), 0xAABBCCDD)

    def test_cli_stop_word_breaks_when_memory_matches(self) -> None:
        words, symbols = assemble_source(
            """
            li t0, 0x20010000
            li t1, 0x5a5a1234
            sw t1, 0(t0)
        done:
            j done
            """
        )
        mem = Memory()
        for idx, word in enumerate(words):
            mem.write_u32(idx * 4, word)
        cpu = Cpu(mem=mem, pc=symbols.get("_start", 0))
        reason = run_with_cli_stops(
            cpu=cpu,
            mem=mem,
            max_steps=20,
            stop_pc=None,
            stop_words=[(0x20010000, 0x5A5A1234)],
            stop_nonzero=[],
            stop_change=[],
            stop_console=[],
            console_sends=[],
            console_ring_base=0x20010000,
            console_ring_head=0x20010100,
            console_ring_total=0x20010104,
            console_ring_bytes=256,
            checkpoint_interval=None,
            checkpoint_words=[],
            symbols=None,
            event_out=StringIO(),
        )
        self.assertEqual(reason, StopReason.BREAKPOINT)
        self.assertEqual(mem.read_u32(0x20010000), 0x5A5A1234)

    def test_console_ring_dump_wraps_to_latest_bytes(self) -> None:
        mem = Memory()
        base = 0x20010000
        total_addr = 0x20010104
        text = b"abcdef"
        ring_bytes = 4
        for pos, byte in enumerate(text):
            idx = pos & (ring_bytes - 1)
            addr = base + (idx & ~3)
            word = mem.read_u32(addr)
            shift = (idx & 3) * 8
            word = (word & ~(0xFF << shift)) | (byte << shift)
            mem.write_u32(addr, word)
        mem.write_u32(total_addr, len(text))
        total, captured = read_console_ring(mem, base, total_addr, ring_bytes)
        self.assertEqual(total, len(text))
        self.assertEqual(captured, "cdef")

    def test_console_ring_drain_advances_head(self) -> None:
        mem = Memory()
        base = 0x20010000
        head_addr = 0x20010100
        total_addr = 0x20010104
        for pos, byte in enumerate(b"abc"):
            idx = pos & 0xFF
            addr = base + (idx & ~3)
            word = mem.read_u32(addr)
            shift = (idx & 3) * 8
            word = (word & ~(0xFF << shift)) | (byte << shift)
            mem.write_u32(addr, word)
        mem.write_u32(total_addr, 3)

        self.assertEqual(drain_console_ring(mem, base, head_addr, total_addr, 256), "abc")
        self.assertEqual(mem.read_u32(head_addr), 3)

    def test_console_input_preloads_getchar_ring(self) -> None:
        mem = Memory()
        write_console_input(mem, b"root\n")

        self.assertEqual(mem.read_u32(0x20010190), 0)
        self.assertEqual(mem.read_u32(0x20010194), 5)
        self.assertEqual(mem.read_bytes(0x20010110, 5), b"root\n")

    def test_console_input_rejects_overflow(self) -> None:
        mem = Memory()
        with self.assertRaises(ValueError):
            write_console_input(mem, b"x" * 129)

    def test_console_script_allows_shell_prompt_trigger(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = pathlib.Path(tmp) / "console.script"
            path.write_text("# comment\n# \tuname -a\\n\n", encoding="utf-8")
            sends = load_console_script(path)

        self.assertEqual(len(sends), 1)
        self.assertEqual(sends[0].needle, "# ")
        self.assertEqual(sends[0].data, b"uname -a\n")

    def test_cli_stop_console_breaks_when_ring_contains_text(self) -> None:
        mem = Memory()
        base = 0x20010000
        total_addr = 0x20010104
        text = b"Welcome to Buildroot\nbuildroot login: "
        for pos, byte in enumerate(text):
            idx = pos & 0xFF
            addr = base + (idx & ~3)
            word = mem.read_u32(addr)
            shift = (idx & 3) * 8
            word = (word & ~(0xFF << shift)) | (byte << shift)
            mem.write_u32(addr, word)
        mem.write_u32(total_addr, len(text))
        cpu = Cpu(mem=mem)

        reason = run_with_cli_stops(
            cpu=cpu,
            mem=mem,
            max_steps=20,
            stop_pc=None,
            stop_words=[],
            stop_nonzero=[],
            stop_change=[],
            stop_console=["buildroot login:"],
            console_sends=[],
            console_ring_base=base,
            console_ring_head=0x20010100,
            console_ring_total=total_addr,
            console_ring_bytes=256,
            checkpoint_interval=None,
            checkpoint_words=[],
            symbols=None,
            event_out=StringIO(),
        )

        self.assertEqual(reason, StopReason.BREAKPOINT)

    def test_cli_console_send_after_writes_input_ring(self) -> None:
        mem = Memory()
        base = 0x20010000
        total_addr = 0x20010104
        text = b"buildroot login: "
        for pos, byte in enumerate(text):
            idx = pos & 0xFF
            addr = base + (idx & ~3)
            word = mem.read_u32(addr)
            shift = (idx & 3) * 8
            word = (word & ~(0xFF << shift)) | (byte << shift)
            mem.write_u32(addr, word)
        mem.write_u32(total_addr, len(text))
        cpu = Cpu(mem=mem)

        reason = run_with_cli_stops(
            cpu=cpu,
            mem=mem,
            max_steps=20,
            stop_pc=None,
            stop_words=[],
            stop_nonzero=[],
            stop_change=[],
            stop_console=["buildroot login:"],
            console_sends=[ConsoleSend("buildroot login:", b"root\n")],
            console_ring_base=base,
            console_ring_head=0x20010100,
            console_ring_total=total_addr,
            console_ring_bytes=256,
            checkpoint_interval=None,
            checkpoint_words=[],
            symbols=None,
            event_out=StringIO(),
        )

        self.assertEqual(reason, StopReason.BREAKPOINT)
        self.assertEqual(mem.read_bytes(0x20010110, 5), b"root\n")
        self.assertEqual(mem.read_u32(0x20010194), 5)


if __name__ == "__main__":
    unittest.main()
