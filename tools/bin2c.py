#!/usr/bin/env python3
from __future__ import annotations

import argparse
import pathlib
from typing import Sequence


def render(data: bytes, array_name: str, c_type: str) -> str:
    lines = [f"static const {c_type} {array_name}[] = {{"]
    for offset in range(0, len(data), 12):
        chunk = data[offset : offset + 12]
        values = ", ".join(f"0x{byte:02x}u" for byte in chunk)
        lines.append(f"    {values},")
    lines.append("};")
    lines.append(f"static const u32 {array_name}_size = {len(data)}u;")
    return "\n".join(lines) + "\n"


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="convert binary data to a C array")
    parser.add_argument("input", type=pathlib.Path)
    parser.add_argument("--array-name", required=True)
    parser.add_argument("--c-type", default="u8")
    args = parser.parse_args(argv)

    print(render(args.input.read_bytes(), args.array_name, args.c_type), end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
