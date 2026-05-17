#!/usr/bin/env python3
from __future__ import annotations

import argparse
import pathlib
import struct
import sys
from typing import Sequence

from zx32asm import Assembler, AssemblerError


ELF_MAGIC = b"\x7fELF"
ELFCLASS32 = 1
ELFDATA2LSB = 1
EV_CURRENT = 1
ET_EXEC = 2
EM_RISCV = 243
PT_LOAD = 1
PF_X = 1
PF_R = 4
PAGE_SIZE = 0x1000
EHDR_SIZE = 52
PHDR_SIZE = 32


def build_elf(words: Sequence[int], load_addr: int, entry: int) -> bytes:
    text = b"".join(struct.pack("<I", word & 0xFFFFFFFF) for word in words)
    phoff = EHDR_SIZE
    text_offset = PAGE_SIZE
    phdr = struct.pack(
        "<IIIIIIII",
        PT_LOAD,
        text_offset,
        load_addr,
        load_addr,
        len(text),
        len(text),
        PF_R | PF_X,
        PAGE_SIZE,
    )
    ident = bytearray(16)
    ident[:4] = ELF_MAGIC
    ident[4] = ELFCLASS32
    ident[5] = ELFDATA2LSB
    ident[6] = EV_CURRENT
    elf_header = struct.pack(
        "<16sHHIIIIIHHHHHH",
        bytes(ident),
        ET_EXEC,
        EM_RISCV,
        EV_CURRENT,
        entry,
        phoff,
        0,
        0,
        EHDR_SIZE,
        PHDR_SIZE,
        1,
        0,
        0,
        0,
    )
    padding = b"\x00" * (text_offset - len(elf_header) - len(phdr))
    return elf_header + phdr + padding + text


def assemble_source(source: str) -> tuple[list[int], dict[str, int]]:
    assembler = Assembler(source)
    return assembler.assemble_with_symbols()


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="ZX32 ELF packer")
    parser.add_argument("input", help="assembly input file, or '-' for stdin")
    parser.add_argument("-o", "--output", type=pathlib.Path, required=True)
    parser.add_argument("--load-addr", type=lambda x: int(x, 0), default=0x0)
    parser.add_argument("--entry", type=lambda x: int(x, 0))
    parser.add_argument("--entry-symbol", default="_start")
    args = parser.parse_args(argv)

    if args.input == "-":
        source = sys.stdin.read()
    else:
        source = pathlib.Path(args.input).read_text(encoding="utf-8")

    try:
        words, symbols = assemble_source(source)
    except AssemblerError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1

    if args.entry is not None:
        entry = args.entry
    elif args.entry_symbol in symbols:
        entry = args.load_addr + symbols[args.entry_symbol]
    else:
        entry = args.load_addr
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(build_elf(words, args.load_addr, entry))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
