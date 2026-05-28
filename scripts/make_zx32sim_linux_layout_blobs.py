#!/usr/bin/env python3
from __future__ import annotations

import pathlib
import struct
import sys


def put_u32(buf: bytearray, offset: int, value: int) -> None:
    struct.pack_into("<I", buf, offset, value & 0xFFFFFFFF)


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print(f"usage: {argv[0]} IMAGE_OUT DTB_OUT", file=sys.stderr)
        return 2
    image_out = pathlib.Path(argv[1])
    dtb_out = pathlib.Path(argv[2])

    image = bytearray(64)
    put_u32(image, 0, 0x0000106F)
    put_u32(image, 8, 0x00400000)
    put_u32(image, 12, 0x00000000)
    put_u32(image, 16, 0x00100000)
    put_u32(image, 20, 0x00000000)
    put_u32(image, 48, 0x43534952)
    put_u32(image, 52, 0x00000056)
    put_u32(image, 56, 0x05435352)

    image_out.parent.mkdir(parents=True, exist_ok=True)
    image_out.write_bytes(image)

    dtb_out.parent.mkdir(parents=True, exist_ok=True)
    dtb_out.write_bytes(struct.pack("<I", 0xEDFE0DD0))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
