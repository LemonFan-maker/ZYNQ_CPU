from __future__ import annotations

import dataclasses
import pathlib
import struct


ELF_MAGIC = b"\x7fELF"
PT_LOAD = 1


@dataclasses.dataclass(frozen=True)
class LoadSegment:
    addr: int
    data: bytes
    mem_size: int


@dataclasses.dataclass(frozen=True)
class ElfImage:
    entry: int
    segments: list[LoadSegment]


def load_elf(path: pathlib.Path) -> ElfImage:
    blob = path.read_bytes()
    if len(blob) < 52 or blob[:4] != ELF_MAGIC:
        raise ValueError(f"not an ELF file: {path}")
    if blob[4] != 1 or blob[5] != 1:
        raise ValueError("only 32-bit little-endian ELF files are supported")

    (
        _ident,
        _etype,
        machine,
        _version,
        entry,
        phoff,
        _shoff,
        _flags,
        _ehsize,
        phentsize,
        phnum,
        _shentsize,
        _shnum,
        _shstrndx,
    ) = struct.unpack_from("<16sHHIIIIIHHHHHH", blob, 0)
    if machine != 243:
        raise ValueError(f"unsupported ELF machine: {machine}")

    segments: list[LoadSegment] = []
    for idx in range(phnum):
        off = phoff + idx * phentsize
        if off + 32 > len(blob):
            raise ValueError("program header outside ELF file")
        p_type, p_offset, p_vaddr, _p_paddr, p_filesz, p_memsz, _p_flags, _p_align = struct.unpack_from(
            "<IIIIIIII", blob, off
        )
        if p_type != PT_LOAD:
            continue
        if p_offset + p_filesz > len(blob):
            raise ValueError("load segment outside ELF file")
        segments.append(LoadSegment(p_vaddr, blob[p_offset : p_offset + p_filesz], p_memsz))
    if not segments:
        raise ValueError("ELF has no PT_LOAD segments")
    return ElfImage(entry=entry, segments=segments)

