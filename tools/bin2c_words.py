#!/usr/bin/env python3
from __future__ import annotations

import argparse
import pathlib
from typing import Sequence


def render(data: bytes, array_name: str) -> str:
    if len(data) % 4 != 0:
        raise ValueError(f"{array_name}: input size is not 32-bit aligned")

    lines = [f"static const u32 {array_name}[] = {{"]
    for offset in range(0, len(data), 16):
        chunk = data[offset : offset + 16]
        values = []
        for word_off in range(0, len(chunk), 4):
            word = int.from_bytes(chunk[word_off : word_off + 4], "little")
            values.append(f"0x{word:08x}u")
        lines.append(f"    {', '.join(values)},")
    lines.append("};")
    lines.append(f"static const u32 {array_name}_words = {len(data) // 4}u;")
    return "\n".join(lines) + "\n"


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="convert a little-endian binary to a u32 C array")
    parser.add_argument("input", type=pathlib.Path)
    parser.add_argument("--array-name", required=True)
    args = parser.parse_args(argv)

    print(render(args.input.read_bytes(), args.array_name), end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
