#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


def glyph_rows(font: ImageFont.FreeTypeFont, ch: str, width: int, height: int) -> list[int]:
    image = Image.new("L", (width, height), 0)
    draw = ImageDraw.Draw(image)
    bbox = draw.textbbox((0, 0), ch, font=font)
    glyph_w = bbox[2] - bbox[0]
    glyph_h = bbox[3] - bbox[1]
    x = -bbox[0] + max(0, (width - glyph_w) // 2)
    y = -bbox[1] + max(0, (height - glyph_h) // 2)
    draw.text((x, y), ch, font=font, fill=255)

    rows: list[int] = []
    for row in range(height):
        bits = 0
        for col in range(width):
            if image.getpixel((col, row)) >= 96:
                bits |= 1 << (7 - col)
        rows.append(bits)
    return rows


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--font", default="/usr/local/share/fonts/c/CascadiaMono_Regular.otf")
    parser.add_argument("--size", type=int, default=13)
    parser.add_argument("--width", type=int, default=8)
    parser.add_argument("--height", type=int, default=16)
    parser.add_argument("--output", default="hw_bringup/ps_font8x16_cascadia.h")
    args = parser.parse_args()

    font = ImageFont.truetype(args.font, args.size)
    words: list[int] = []
    for codepoint in range(128):
        rows = glyph_rows(font, chr(codepoint), args.width, args.height)
        for idx in range(0, args.height, 4):
            word = 0
            for lane in range(4):
                word |= rows[idx + lane] << (lane * 8)
            words.append(word)

    out = Path(args.output)
    out.parent.mkdir(parents=True, exist_ok=True)
    with out.open("w", encoding="ascii") as f:
        f.write("#ifndef PS_FONT8X16_CASCADIA_H\n")
        f.write("#define PS_FONT8X16_CASCADIA_H\n\n")
        f.write('#include "xil_types.h"\n\n')
        f.write("#define ZX32_CONSOLE_FONT8X16_WORDS 512U\n\n")
        f.write("static const u32 zx32_console_font8x16_words[ZX32_CONSOLE_FONT8X16_WORDS] = {\n")
        for i in range(0, len(words), 4):
            chunk = words[i:i + 4]
            suffix = "," if i + 4 < len(words) else ""
            f.write("    " + ", ".join(f"0x{word:08x}U" for word in chunk) + suffix + "\n")
        f.write("};\n\n")
        f.write("#endif\n")


if __name__ == "__main__":
    main()
