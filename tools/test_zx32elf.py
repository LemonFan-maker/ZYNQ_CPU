#!/usr/bin/env python3
from __future__ import annotations

import struct
import unittest

from zx32elf import assemble_source, build_elf
from zx32asm import Assembler


class ZX32ElfTests(unittest.TestCase):
    def test_minimal_elf_layout(self) -> None:
        words = Assembler("jal x0, 0\n").assemble()
        blob = build_elf(words, 0x0, 0x0)
        self.assertEqual(blob[:4], b"\x7fELF")
        self.assertEqual(blob[4], 1)
        self.assertEqual(blob[5], 1)
        self.assertEqual(struct.unpack_from("<H", blob, 16)[0], 2)
        self.assertEqual(struct.unpack_from("<H", blob, 18)[0], 243)
        self.assertEqual(struct.unpack_from("<I", blob, 24)[0], 0)
        self.assertEqual(struct.unpack_from("<I", blob, 28)[0], 52)
        self.assertEqual(struct.unpack_from("<I", blob, 32)[0], 0)
        self.assertEqual(struct.unpack_from("<I", blob, 36)[0], 0)
        self.assertEqual(struct.unpack_from("<H", blob, 40)[0], 52)
        self.assertEqual(struct.unpack_from("<H", blob, 42)[0], 32)
        self.assertEqual(struct.unpack_from("<H", blob, 44)[0], 1)
        self.assertEqual(blob[0x1000:0x1004], b"\x6f\x00\x00\x00")

    def test_entry_symbol_defaults_to_start(self) -> None:
        words, symbols = assemble_source(
            """
            j fail
            _start:
                jal x0, 0
            fail:
                jal x0, 0
            """
        )
        self.assertEqual(symbols["_start"], 4)
        blob = build_elf(words, 0x0, symbols["_start"])
        self.assertEqual(struct.unpack_from("<I", blob, 24)[0], 4)


if __name__ == "__main__":
    unittest.main()
