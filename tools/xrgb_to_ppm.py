#!/usr/bin/env python3
import argparse
import mmap
import struct


def parse_size(value):
    if "x" not in value:
        raise argparse.ArgumentTypeError("expected WIDTHxHEIGHT")
    width_s, height_s = value.lower().split("x", 1)
    try:
        width = int(width_s, 0)
        height = int(height_s, 0)
    except ValueError as exc:
        raise argparse.ArgumentTypeError("invalid size") from exc
    if width <= 0 or height <= 0:
        raise argparse.ArgumentTypeError("size must be positive")
    return width, height


def pixel_at(raw, width, x, y):
    off = ((y * width) + x) * 4
    (px,) = struct.unpack_from("<I", raw, off)
    return bytes(((px >> 16) & 0xFF, (px >> 8) & 0xFF, px & 0xFF))


def main():
    parser = argparse.ArgumentParser(
        description="Convert little-endian XRGB8888 raw pixels to PPM."
    )
    parser.add_argument("input", help="input .xrgb raw file")
    parser.add_argument("output", help="output .ppm file")
    parser.add_argument("width", type=int)
    parser.add_argument("height", type=int)
    parser.add_argument("--out-size", type=parse_size, help="nearest-neighbor output size")
    args = parser.parse_args()

    if args.width <= 0 or args.height <= 0:
        raise SystemExit("width and height must be positive")

    out_width, out_height = args.out_size or (args.width, args.height)
    expected = args.width * args.height * 4

    with open(args.input, "rb") as fp:
        raw = mmap.mmap(fp.fileno(), 0, access=mmap.ACCESS_READ)
        if len(raw) != expected:
            raise SystemExit(f"{args.input}: expected {expected} bytes, got {len(raw)}")
        with open(args.output, "wb") as out:
            out.write(f"P6\n{out_width} {out_height}\n255\n".encode())
            for y in range(out_height):
                src_y = min(args.height - 1, (y * args.height) // out_height)
                row = bytearray()
                for x in range(out_width):
                    src_x = min(args.width - 1, (x * args.width) // out_width)
                    row.extend(pixel_at(raw, args.width, src_x, src_y))
                out.write(row)
        raw.close()

    print(f"wrote {args.output}: {out_width}x{out_height} PPM")


if __name__ == "__main__":
    raise SystemExit(main())
