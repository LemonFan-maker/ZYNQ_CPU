#!/usr/bin/env python3
from __future__ import annotations

import pathlib
import struct
import sys


DTB_WORDS = {
    0: 0xEDFE0DD0,
    1: 0x00010000,
    2: 0x38000000,
    3: 0xA0000000,
    4: 0x28000000,
    5: 0x11000000,
    6: 0x10000000,
    7: 0x00000000,
    8: 0x40000000,
    9: 0x5C000000,
    14: 0x01000000,
    15: 0x00000000,
    16: 0x03000000,
    17: 0x04000000,
    18: 0x00000000,
    19: 0x01000000,
    20: 0x03000000,
    21: 0x04000000,
    22: 0x0F000000,
    23: 0x01000000,
    24: 0x01000000,
    25: 0x6F6D656D,
    26: 0x38407972,
    27: 0x30303030,
    28: 0x00303030,
    29: 0x03000000,
    30: 0x08000000,
    31: 0x1B000000,
    32: 0x00000080,
    33: 0x00000040,
    34: 0x02000000,
    35: 0x02000000,
    36: 0x09000000,
    40: 0x64646123,
    41: 0x73736572,
    42: 0x6C65632D,
    43: 0x2300736C,
    44: 0x657A6973,
    45: 0x6C65632D,
    46: 0x7200736C,
    47: 0x00006765,
}


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print(f"usage: {argv[0]} OUTPUT", file=sys.stderr)
        return 2
    output = pathlib.Path(argv[1])
    words = [0] * 64
    for idx, value in DTB_WORDS.items():
        words[idx] = value
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(b"".join(struct.pack("<I", word & 0xFFFFFFFF) for word in words))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
