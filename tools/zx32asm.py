#!/usr/bin/env python3
from __future__ import annotations

import argparse
import dataclasses
import pathlib
import re
import sys
from typing import Iterable, Sequence


class AssemblerError(RuntimeError):
    pass


REG_ALIASES = {
    "zero": 0,
    "ra": 1,
    "sp": 2,
    "gp": 3,
    "tp": 4,
    "t0": 5,
    "t1": 6,
    "t2": 7,
    "s0": 8,
    "fp": 8,
    "s1": 9,
    "a0": 10,
    "a1": 11,
    "a2": 12,
    "a3": 13,
    "a4": 14,
    "a5": 15,
    "a6": 16,
    "a7": 17,
    "s2": 18,
    "s3": 19,
    "s4": 20,
    "s5": 21,
    "s6": 22,
    "s7": 23,
    "s8": 24,
    "s9": 25,
    "s10": 26,
    "s11": 27,
    "t3": 28,
    "t4": 29,
    "t5": 30,
    "t6": 31,
}

CSR_ALIASES = {
    "ustatus": 0x000,
    "fflags": 0x001,
    "frm": 0x002,
    "fcsr": 0x003,
    "uie": 0x004,
    "utvec": 0x005,
    "uscratch": 0x040,
    "uepc": 0x041,
    "ucause": 0x042,
    "utval": 0x043,
    "uip": 0x044,
    "sstatus": 0x100,
    "sie": 0x104,
    "stvec": 0x105,
    "scounteren": 0x106,
    "senvcfg": 0x10A,
    "sstateen0": 0x10C,
    "sstateen1": 0x10D,
    "sstateen2": 0x10E,
    "sstateen3": 0x10F,
    "scountinhibit": 0x120,
    "sscratch": 0x140,
    "sepc": 0x141,
    "scause": 0x142,
    "stval": 0x143,
    "sip": 0x144,
    "stimecmp": 0x14D,
    "sctrctl": 0x14E,
    "sctrstatus": 0x14F,
    "siselect": 0x150,
    "sireg": 0x151,
    "sireg2": 0x152,
    "sireg3": 0x153,
    "sireg4": 0x155,
    "sireg5": 0x156,
    "sireg6": 0x157,
    "stimecmph": 0x15D,
    "sctrdepth": 0x15F,
    "satp": 0x180,
    "srmcfg": 0x181,
    "scontext": 0x5A8,
    "scountovf": 0xDA0,
    "mstatus": 0x300,
    "misa": 0x301,
    "medeleg": 0x302,
    "mideleg": 0x303,
    "mie": 0x304,
    "mtvec": 0x305,
    "mcounteren": 0x306,
    "mscratch": 0x340,
    "mepc": 0x341,
    "mcause": 0x342,
    "mtval": 0x343,
    "mip": 0x344,
    "mcycle": 0xB00,
    "minstret": 0xB02,
    "mcycleh": 0xB80,
    "minstreth": 0xB82,
    "cycle": 0xC00,
    "time": 0xC01,
    "instret": 0xC02,
    "cycleh": 0xC80,
    "timeh": 0xC81,
    "instreth": 0xC82,
    "mvendorid": 0xF11,
    "marchid": 0xF12,
    "mimpid": 0xF13,
    "mhartid": 0xF14,
}


def strip_comment(line: str) -> str:
    for marker in ("//", "#", ";"):
        idx = line.find(marker)
        if idx != -1:
            line = line[:idx]
    return line.strip()


def split_operands(text: str) -> list[str]:
    return [part.strip() for part in text.split(",") if part.strip()]


def parse_reg(token: str) -> int:
    token = token.strip().lower()
    if token.startswith("x") and token[1:].isdigit():
        reg = int(token[1:])
        if 0 <= reg <= 31:
            return reg
    if token in REG_ALIASES:
        return REG_ALIASES[token]
    raise AssemblerError(f"bad register: {token}")


def parse_csr(token: str) -> int:
    token = token.strip().lower()
    if token in CSR_ALIASES:
        return CSR_ALIASES[token]
    return parse_int(token)


def parse_int(token: str) -> int:
    try:
        return int(token, 0)
    except ValueError as exc:
        raise AssemblerError(f"bad integer: {token}") from exc


def fits_signed(value: int, bits: int) -> bool:
    lo = -(1 << (bits - 1))
    hi = (1 << (bits - 1)) - 1
    return lo <= value <= hi


def sign_extend(value: int, bits: int) -> int:
    mask = (1 << bits) - 1
    value &= mask
    sign = 1 << (bits - 1)
    return (value ^ sign) - sign


def encode_r(funct7: int, rs2: int, rs1: int, funct3: int, rd: int, opcode: int) -> int:
    return ((funct7 & 0x7F) << 25) | ((rs2 & 0x1F) << 20) | ((rs1 & 0x1F) << 15) | ((funct3 & 0x7) << 12) | ((rd & 0x1F) << 7) | (opcode & 0x7F)


def encode_i(imm: int, rs1: int, funct3: int, rd: int, opcode: int) -> int:
    imm &= 0xFFF
    return (imm << 20) | ((rs1 & 0x1F) << 15) | ((funct3 & 0x7) << 12) | ((rd & 0x1F) << 7) | (opcode & 0x7F)


def encode_s(imm: int, rs2: int, rs1: int, funct3: int, opcode: int) -> int:
    imm &= 0xFFF
    return ((imm >> 5) << 25) | ((rs2 & 0x1F) << 20) | ((rs1 & 0x1F) << 15) | ((funct3 & 0x7) << 12) | ((imm & 0x1F) << 7) | (opcode & 0x7F)


def encode_b(imm: int, rs2: int, rs1: int, funct3: int, opcode: int) -> int:
    if imm % 2 != 0:
        raise AssemblerError("branch offset must be 2-byte aligned")
    imm &= 0x1FFF
    return (
        ((imm >> 12) & 0x1) << 31
        | ((imm >> 5) & 0x3F) << 25
        | ((rs2 & 0x1F) << 20)
        | ((rs1 & 0x1F) << 15)
        | ((funct3 & 0x7) << 12)
        | ((imm >> 1) & 0xF) << 8
        | ((imm >> 11) & 0x1) << 7
        | (opcode & 0x7F)
    )


def encode_u(imm: int, rd: int, opcode: int) -> int:
    return ((imm & 0xFFFFF) << 12) | ((rd & 0x1F) << 7) | (opcode & 0x7F)


def encode_j(imm: int, rd: int, opcode: int) -> int:
    if imm % 2 != 0:
        raise AssemblerError("jump offset must be 2-byte aligned")
    imm &= 0x1FFFFF
    return (
        ((imm >> 20) & 0x1) << 31
        | ((imm >> 1) & 0x3FF) << 21
        | ((imm >> 11) & 0x1) << 20
        | ((imm >> 12) & 0xFF) << 12
        | ((rd & 0x1F) << 7)
        | (opcode & 0x7F)
    )


def encode_custom(funct3: int, rd: int, rs1: int, rs2: int) -> int:
    return encode_r(0, rs2, rs1, funct3, rd, 0x0B)


def encode_amo(funct5: int, rd: int, rs1: int, rs2: int, aq: int = 0, rl: int = 0) -> int:
    return (
        ((funct5 & 0x1F) << 27)
        | ((aq & 0x1) << 26)
        | ((rl & 0x1) << 25)
        | ((rs2 & 0x1F) << 20)
        | ((rs1 & 0x1F) << 15)
        | (0x2 << 12)
        | ((rd & 0x1F) << 7)
        | 0x2F
    )


@dataclasses.dataclass
class Item:
    kind: str
    line_no: int
    text: str
    name: str | None = None
    operands: list[str] = dataclasses.field(default_factory=list)


class Assembler:
    def __init__(self, source: str) -> None:
        self.source = source.splitlines()
        self.items: list[Item] = []
        self.symbols: dict[str, int] = {}

    def parse(self) -> None:
        self.items = []
        self.symbols = {}
        for line_no, raw in enumerate(self.source, start=1):
            line = strip_comment(raw)
            if not line:
                continue

            while ":" in line:
                label, rest = line.split(":", 1)
                label = label.strip()
                if not label:
                    raise AssemblerError(f"line {line_no}: empty label")
                if label in self.symbols:
                    raise AssemblerError(f"line {line_no}: duplicate label {label}")
                self.symbols[label] = -1
                self.items.append(Item("label", line_no, raw, name=label))
                line = rest.strip()
                if not line:
                    break
            if not line:
                continue

            parts = line.split(None, 1)
            mnemonic = parts[0].lower()
            operands = split_operands(parts[1]) if len(parts) > 1 else []
            self.items.append(Item("stmt", line_no, raw, name=mnemonic, operands=operands))

    def estimate_words(self, stmt: Item) -> int:
        name = stmt.name or ""
        if name == ".word":
            return len(stmt.operands)
        if name in (".zero",):
            if len(stmt.operands) != 1:
                raise AssemblerError(f"line {stmt.line_no}: {name} expects one operand")
            count = parse_int(stmt.operands[0])
            if count < 0:
                raise AssemblerError(f"line {stmt.line_no}: {name} must be non-negative")
            return (count + 3) // 4
        if name == ".org":
            return 0
        if name == "li":
            if len(stmt.operands) != 2:
                raise AssemblerError(f"line {stmt.line_no}: li expects rd, imm")
            imm = parse_int(stmt.operands[1])
            return 1 if fits_signed(imm, 12) else 2
        return 1

    def first_pass(self) -> None:
        pc = 0
        for item in self.items:
            if item.kind == "label":
                self.symbols[item.name or ""] = pc
                continue
            name = item.name or ""
            if name == ".org":
                if len(item.operands) != 1:
                    raise AssemblerError(f"line {item.line_no}: .org expects one operand")
                new_pc = parse_int(item.operands[0])
                if new_pc < pc:
                    raise AssemblerError(f"line {item.line_no}: .org cannot move backwards")
                pc = new_pc
                continue
            pc += 4 * self.estimate_words(item)

    def resolve_symbol(self, token: str, line_no: int) -> int:
        if token in self.symbols and self.symbols[token] >= 0:
            return self.symbols[token]
        try:
            return parse_int(token)
        except AssemblerError as exc:
            raise AssemblerError(f"line {line_no}: unknown symbol {token}") from exc

    def resolve_branch_offset(self, token: str, pc: int, line_no: int) -> int:
        if token in self.symbols and self.symbols[token] >= 0:
            return self.symbols[token] - pc
        return parse_int(token)

    def encode_li(self, rd: int, imm: int) -> list[int]:
        imm &= 0xFFFFFFFF
        signed = imm if imm < 0x80000000 else imm - 0x100000000
        if fits_signed(signed, 12):
            return [encode_i(signed, 0, 0, rd, 0x13)]
        upper = (imm + 0x800) >> 12
        lower = sign_extend(imm - (upper << 12), 12)
        return [encode_u(upper, rd, 0x37), encode_i(lower, rd, 0, rd, 0x13)]

    def parse_mem_operand(self, token: str, line_no: int) -> tuple[int, int]:
        match = re.fullmatch(r"(.*)\((.+)\)", token.replace(" ", ""))
        if not match:
            raise AssemblerError(f"line {line_no}: bad memory operand {token}")
        imm_text, rs1_text = match.group(1), match.group(2)
        imm = 0 if imm_text == "" else self.resolve_symbol(imm_text, line_no)
        return imm, parse_reg(rs1_text)

    def encode_stmt(self, item: Item, pc: int) -> list[int]:
        name = item.name or ""
        ops = item.operands

        if name == ".word":
            return [self.resolve_symbol(op, item.line_no) & 0xFFFFFFFF for op in ops]
        if name == ".zero":
            count = parse_int(ops[0])
            words = (count + 3) // 4
            return [0] * words
        if name == ".org":
            return []

        if name == "li":
            rd = parse_reg(ops[0])
            imm = self.resolve_symbol(ops[1], item.line_no)
            return self.encode_li(rd, imm)
        if name == "mv":
            rd = parse_reg(ops[0])
            rs = parse_reg(ops[1])
            return [encode_i(0, rs, 0, rd, 0x13)]
        if name == "nop":
            return [encode_i(0, 0, 0, 0, 0x13)]
        if name == "j":
            offset = self.resolve_branch_offset(ops[0], pc, item.line_no)
            return [encode_j(offset, 0, 0x6F)]
        if name == "ret":
            return [encode_i(0, 1, 0, 0, 0x67)]
        if name == "beqz":
            rs1 = parse_reg(ops[0])
            offset = self.resolve_branch_offset(ops[1], pc, item.line_no)
            return [encode_b(offset, 0, rs1, 0, 0x63)]
        if name == "bnez":
            rs1 = parse_reg(ops[0])
            offset = self.resolve_branch_offset(ops[1], pc, item.line_no)
            return [encode_b(offset, 0, rs1, 1, 0x63)]
        if name == "fence":
            return [encode_i(0, 0, 0, 0, 0x0F)]
        if name == "fence.i":
            return [encode_i(0, 0, 1, 0, 0x0F)]
        if name == "sfence.vma":
            if len(ops) == 0:
                rs1 = 0
                rs2 = 0
            elif len(ops) == 2:
                rs1 = parse_reg(ops[0])
                rs2 = parse_reg(ops[1])
            else:
                raise AssemblerError(f"line {item.line_no}: sfence.vma expects zero or two operands")
            return [encode_r(0x09, rs2, rs1, 0, 0, 0x73)]
        if name == "ecall":
            return [0x00000073]
        if name == "ebreak":
            return [0x00100073]
        if name == "mret":
            return [0x30200073]
        if name == "sret":
            return [0x10200073]
        if name == "wfi":
            return [0x10500073]

        if name == "lui":
            rd = parse_reg(ops[0])
            imm = self.resolve_symbol(ops[1], item.line_no)
            return [encode_u(imm, rd, 0x37)]
        if name == "auipc":
            rd = parse_reg(ops[0])
            imm = self.resolve_symbol(ops[1], item.line_no)
            return [encode_u(imm, rd, 0x17)]
        if name == "jal":
            rd = parse_reg(ops[0])
            offset = self.resolve_branch_offset(ops[1], pc, item.line_no)
            return [encode_j(offset, rd, 0x6F)]
        if name == "jalr":
            rd = parse_reg(ops[0])
            imm, rs1 = self.parse_mem_operand(ops[1], item.line_no)
            return [encode_i(imm, rs1, 0, rd, 0x67)]
        if name in {"beq", "bne", "blt", "bge", "bltu", "bgeu"}:
            rs1 = parse_reg(ops[0])
            rs2 = parse_reg(ops[1])
            target = self.resolve_symbol(ops[2], item.line_no)
            funct3 = {"beq": 0, "bne": 1, "blt": 4, "bge": 5, "bltu": 6, "bgeu": 7}[name]
            return [encode_b(target - pc, rs2, rs1, funct3, 0x63)]
        if name in {"lb", "lh", "lw", "lbu", "lhu"}:
            rd = parse_reg(ops[0])
            imm, rs1 = self.parse_mem_operand(ops[1], item.line_no)
            funct3 = {"lb": 0, "lh": 1, "lw": 2, "lbu": 4, "lhu": 5}[name]
            return [encode_i(imm, rs1, funct3, rd, 0x03)]
        if name in {"sb", "sh", "sw"}:
            rs2 = parse_reg(ops[0])
            imm, rs1 = self.parse_mem_operand(ops[1], item.line_no)
            funct3 = {"sb": 0, "sh": 1, "sw": 2}[name]
            return [encode_s(imm, rs2, rs1, funct3, 0x23)]

        amo_name = name
        aq = 0
        rl = 0
        for suffix, flags in ((".aqrl", (1, 1)), (".aq", (1, 0)), (".rl", (0, 1))):
            if amo_name.endswith(suffix):
                aq, rl = flags
                amo_name = amo_name[: -len(suffix)]
                break
        amo_funct5 = {
            "lr.w": 0b00010,
            "sc.w": 0b00011,
            "amoswap.w": 0b00001,
            "amoadd.w": 0b00000,
            "amoxor.w": 0b00100,
            "amoand.w": 0b01100,
            "amoor.w": 0b01000,
            "amomin.w": 0b10000,
            "amomax.w": 0b10100,
            "amominu.w": 0b11000,
            "amomaxu.w": 0b11100,
        }
        if amo_name in amo_funct5:
            rd = parse_reg(ops[0])
            if amo_name == "lr.w":
                if len(ops) != 2:
                    raise AssemblerError(f"line {item.line_no}: lr.w expects rd, mem")
                imm, rs1 = self.parse_mem_operand(ops[1], item.line_no)
                if imm != 0:
                    raise AssemblerError(f"line {item.line_no}: lr.w requires zero offset")
                return [encode_amo(amo_funct5[amo_name], rd, rs1, 0, aq, rl)]
            if amo_name == "sc.w":
                if len(ops) != 3:
                    raise AssemblerError(f"line {item.line_no}: sc.w expects rd, rs2, mem")
                rs2 = parse_reg(ops[1])
                imm, rs1 = self.parse_mem_operand(ops[2], item.line_no)
                if imm != 0:
                    raise AssemblerError(f"line {item.line_no}: sc.w requires zero offset")
                return [encode_amo(amo_funct5[amo_name], rd, rs1, rs2, aq, rl)]
            if len(ops) != 3:
                raise AssemblerError(f"line {item.line_no}: {name} expects rd, rs2, mem")
            rs2 = parse_reg(ops[1])
            imm, rs1 = self.parse_mem_operand(ops[2], item.line_no)
            if imm != 0:
                raise AssemblerError(f"line {item.line_no}: {name} requires zero offset")
            return [encode_amo(amo_funct5[amo_name], rd, rs1, rs2, aq, rl)]

        if name in {"addi", "slti", "sltiu", "xori", "ori", "andi"}:
            rd = parse_reg(ops[0])
            rs1 = parse_reg(ops[1])
            imm = self.resolve_symbol(ops[2], item.line_no)
            funct3 = {"addi": 0, "slti": 2, "sltiu": 3, "xori": 4, "ori": 6, "andi": 7}[name]
            return [encode_i(imm, rs1, funct3, rd, 0x13)]
        if name in {"slli", "srli", "srai"}:
            rd = parse_reg(ops[0])
            rs1 = parse_reg(ops[1])
            shamt = self.resolve_symbol(ops[2], item.line_no)
            funct3 = {"slli": 1, "srli": 5, "srai": 5}[name]
            funct7 = 0x20 if name == "srai" else 0x00
            return [encode_r(funct7, shamt, rs1, funct3, rd, 0x13)]
        if name in {"mul", "mulh", "mulhsu", "mulhu", "div", "divu", "rem", "remu"}:
            rd = parse_reg(ops[0])
            rs1 = parse_reg(ops[1])
            rs2 = parse_reg(ops[2])
            funct3 = {
                "mul": 0,
                "mulh": 1,
                "mulhsu": 2,
                "mulhu": 3,
                "div": 4,
                "divu": 5,
                "rem": 6,
                "remu": 7,
            }[name]
            return [encode_r(0x01, rs2, rs1, funct3, rd, 0x33)]
        if name in {"add", "sub", "sll", "slt", "sltu", "xor", "srl", "sra", "or", "and"}:
            rd = parse_reg(ops[0])
            rs1 = parse_reg(ops[1])
            rs2 = parse_reg(ops[2])
            funct3_map = {"add": 0, "sub": 0, "sll": 1, "slt": 2, "sltu": 3, "xor": 4, "srl": 5, "sra": 5, "or": 6, "and": 7}
            funct7 = 0x20 if name in {"sub", "sra"} else 0x00
            return [encode_r(funct7, rs2, rs1, funct3_map[name], rd, 0x33)]

        if name == "xcpyw":
            rd = parse_reg(ops[0])
            rs1 = parse_reg(ops[1])
            rs2 = parse_reg(ops[2])
            return [encode_custom(0, rd, rs1, rs2)]
        if name == "xdm2s":
            rd = parse_reg(ops[0])
            rs1 = parse_reg(ops[1])
            rs2 = parse_reg(ops[2])
            return [encode_custom(1, rd, rs1, rs2)]
        if name == "xds2m":
            rd = parse_reg(ops[0])
            rs1 = parse_reg(ops[1])
            rs2 = parse_reg(ops[2])
            return [encode_custom(2, rd, rs1, rs2)]
        if name == "csrrw":
            rd = parse_reg(ops[0])
            csr = parse_csr(ops[1])
            rs1 = parse_reg(ops[2])
            return [encode_i(csr, rs1, 1, rd, 0x73)]
        if name == "csrrs":
            rd = parse_reg(ops[0])
            csr = parse_csr(ops[1])
            rs1 = parse_reg(ops[2])
            return [encode_i(csr, rs1, 2, rd, 0x73)]
        if name == "csrrc":
            rd = parse_reg(ops[0])
            csr = parse_csr(ops[1])
            rs1 = parse_reg(ops[2])
            return [encode_i(csr, rs1, 3, rd, 0x73)]
        if name == "csrrwi":
            rd = parse_reg(ops[0])
            csr = parse_csr(ops[1])
            zimm = parse_int(ops[2]) & 0x1F
            return [encode_i(csr, zimm, 5, rd, 0x73)]
        if name == "csrrsi":
            rd = parse_reg(ops[0])
            csr = parse_csr(ops[1])
            zimm = parse_int(ops[2]) & 0x1F
            return [encode_i(csr, zimm, 6, rd, 0x73)]
        if name == "csrrci":
            rd = parse_reg(ops[0])
            csr = parse_csr(ops[1])
            zimm = parse_int(ops[2]) & 0x1F
            return [encode_i(csr, zimm, 7, rd, 0x73)]
        if name == "csrr":
            rd = parse_reg(ops[0])
            csr = parse_csr(ops[1])
            return [encode_i(csr, 0, 2, rd, 0x73)]
        if name == "csrw":
            csr = parse_csr(ops[0])
            rs1 = parse_reg(ops[1])
            return [encode_i(csr, rs1, 1, 0, 0x73)]
        if name == "csrs":
            csr = parse_csr(ops[0])
            rs1 = parse_reg(ops[1])
            return [encode_i(csr, rs1, 2, 0, 0x73)]
        if name == "csrc":
            csr = parse_csr(ops[0])
            rs1 = parse_reg(ops[1])
            return [encode_i(csr, rs1, 3, 0, 0x73)]
        if name == "csrwi":
            csr = parse_csr(ops[0])
            zimm = parse_int(ops[1]) & 0x1F
            return [encode_i(csr, zimm, 5, 0, 0x73)]
        if name == "csrsi":
            csr = parse_csr(ops[0])
            zimm = parse_int(ops[1]) & 0x1F
            return [encode_i(csr, zimm, 6, 0, 0x73)]
        if name == "csrci":
            csr = parse_csr(ops[0])
            zimm = parse_int(ops[1]) & 0x1F
            return [encode_i(csr, zimm, 7, 0, 0x73)]

        raise AssemblerError(f"line {item.line_no}: unsupported mnemonic {name}")

    def assemble(self) -> list[int]:
        self.parse()
        self.first_pass()

        words: list[int] = []
        pc = 0
        for item in self.items:
            if item.kind == "label":
                continue
            if (item.name or "") == ".org":
                new_pc = parse_int(item.operands[0])
                if new_pc < pc:
                    raise AssemblerError(f"line {item.line_no}: .org cannot move backwards")
                while pc < new_pc:
                    words.append(0)
                    pc += 4
                continue
            encoded = self.encode_stmt(item, pc)
            words.extend(encoded)
            pc += 4 * len(encoded)
        return words

    def assemble_with_symbols(self) -> tuple[list[int], dict[str, int]]:
        words = self.assemble()
        return words, dict(self.symbols)


def render_hex(words: Sequence[int]) -> str:
    return "\n".join(f"{word & 0xFFFFFFFF:08x}" for word in words) + ("\n" if words else "")


def render_c(words: Sequence[int], array_name: str) -> str:
    body = ",\n    ".join(f"0x{word & 0xFFFFFFFF:08x}u" for word in words)
    if body:
        body = "    " + body
    return (
        "#include <stdint.h>\n\n"
        f"static const uint32_t {array_name}[] = {{\n"
        f"{body}\n"
        "};\n"
    )


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="ZX32 assembler")
    parser.add_argument("input", help="assembly input file, or '-' for stdin")
    parser.add_argument("-o", "--output", type=pathlib.Path)
    parser.add_argument("--format", choices=("hex", "c"), default="hex")
    parser.add_argument("--array-name", default="zx32_image")
    parser.add_argument("--c-type", default="uint32_t")
    args = parser.parse_args(argv)

    if args.input == "-":
        source = sys.stdin.read()
    else:
        source = pathlib.Path(args.input).read_text(encoding="utf-8")
    assembler = Assembler(source)
    try:
        words = assembler.assemble()
    except AssemblerError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1

    if args.format == "hex":
        text = render_hex(words)
    else:
        text = render_c(words, args.array_name).replace("uint32_t", args.c_type)

    if args.output:
        args.output.write_text(text, encoding="utf-8")
    else:
        sys.stdout.write(text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
