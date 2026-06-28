#!/usr/bin/env python3
import argparse
import struct
import sys


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


def parse_rgb(value):
    text = value.strip()
    if text.startswith("#"):
        text = text[1:]
    if text.startswith("0x"):
        text = text[2:]
    if len(text) != 6:
        raise argparse.ArgumentTypeError("expected RRGGBB")
    try:
        raw = int(text, 16)
    except ValueError as exc:
        raise argparse.ArgumentTypeError("invalid RGB value") from exc
    return (raw >> 16) & 0xFF, (raw >> 8) & 0xFF, raw & 0xFF


def resize_image(image, size, mode, background):
    if size is None:
        return image.convert("RGBA")

    width, height = size
    if mode == "stretch":
        return image.convert("RGBA").resize((width, height))

    src = image.convert("RGBA")
    src_w, src_h = src.size
    if mode == "contain":
        scale = min(width / src_w, height / src_h)
    elif mode == "cover":
        scale = max(width / src_w, height / src_h)
    else:
        raise ValueError(f"unknown resize mode: {mode}")

    new_w = max(1, int(round(src_w * scale)))
    new_h = max(1, int(round(src_h * scale)))
    resized = src.resize((new_w, new_h))
    canvas = Image.new("RGBA", (width, height), (*background, 255))
    x = (width - new_w) // 2
    y = (height - new_h) // 2
    canvas.alpha_composite(resized, (x, y))
    if mode == "cover":
        left = max(0, (new_w - width) // 2)
        top = max(0, (new_h - height) // 2)
        canvas = resized.crop((left, top, left + width, top + height))
    return canvas


def main():
    parser = argparse.ArgumentParser(
        description="Convert an image to ZX32 little-endian XRGB8888 raw pixels."
    )
    parser.add_argument("input", help="input image, supported by Pillow")
    parser.add_argument("output", help="output .raw file")
    parser.add_argument("--size", type=parse_size, help="resize to WIDTHxHEIGHT")
    parser.add_argument(
        "--fit",
        choices=("contain", "cover", "stretch"),
        default="contain",
        help="resize policy when --size is used",
    )
    parser.add_argument(
        "--background",
        type=parse_rgb,
        default=(0, 0, 0),
        help="RRGGBB background for transparent/letterboxed pixels",
    )
    args = parser.parse_args()

    try:
        global Image
        from PIL import Image
    except ModuleNotFoundError:
        print("Pillow is required: python3 -m pip install Pillow", file=sys.stderr)
        return 2

    image = Image.open(args.input)
    image = resize_image(image, args.size, args.fit, args.background)
    rgb = image.convert("RGB")

    with open(args.output, "wb") as fp:
        for r, g, b in rgb.getdata():
            fp.write(struct.pack("<I", (r << 16) | (g << 8) | b))

    width, height = rgb.size
    print(f"wrote {args.output}: {width}x{height} XRGB8888 ({width * height * 4} bytes)")


if __name__ == "__main__":
    raise SystemExit(main())
