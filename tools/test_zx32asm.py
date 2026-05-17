#!/usr/bin/env python3
from __future__ import annotations

import tempfile
import textwrap
import unittest
from pathlib import Path

from zx32asm import Assembler


class ZX32AssemblerTests(unittest.TestCase):
    def assemble(self, source: str) -> list[int]:
        return Assembler(textwrap.dedent(source)).assemble()

    def test_custom_encodings_match_bringup_program(self) -> None:
        words = self.assemble(
            """
            addi x1, x0, 64
            addi x2, x0, 68
            xcpyw x4, x1, x2
            lui x5, 0x20010
            lui x6, 0xabcd1
            addi x6, x6, 0x234
            sw x6, 1008(x5)
            jal x0, 0
            """
        )
        self.assertEqual(
            words,
            [
                0x04000093,
                0x04400113,
                0x0020820B,
                0x200102B7,
                0xABCD1337,
                0x23430313,
                0x3E62A823,
                0x0000006F,
            ],
        )

    def test_custom_datamover_encodings_match_bringup_program(self) -> None:
        words = self.assemble(
            """
            addi x1, x0, 64
            addi x2, x0, 68
            addi x3, x0, 72
            xdm2s x9, x6, x8
            xds2m x9, x7, x8
            """
        )
        self.assertEqual(words[3], 0x0083148B)
        self.assertEqual(words[4], 0x0083A48B)

    def test_branch_labels(self) -> None:
        words = self.assemble(
            """
            loop:
                addi x1, x1, -1
                bnez x1, loop
            """
        )
        self.assertEqual(words[0], 0xFFF08093)
        self.assertEqual(words[1], 0xFE009EE3)

    def test_numeric_jal_offset_is_relative(self) -> None:
        words = self.assemble(
            """
            jal x0, 0
            """
        )
        self.assertEqual(words, [0x0000006F])

    def test_li_expands_when_needed(self) -> None:
        words = self.assemble(
            """
            li x10, 0x12345678
            """
        )
        self.assertEqual(words, [0x12345537, 0x67850513])

    def test_system_and_csr_encodings(self) -> None:
        words = self.assemble(
            """
            ecall
            ebreak
            mret
            sret
            wfi
            csrw mtvec, x1
            csrr x2, mepc
            csrrw x3, mscratch, x4
            csrrsi x5, mstatus, 8
            fence
            fence.i
            sfence.vma
            sfence.vma x1, x2
            """
        )
        self.assertEqual(
            words,
            [
                0x00000073,
                0x00100073,
                0x30200073,
                0x10200073,
                0x10500073,
                0x30509073,
                0x34102173,
                0x340211F3,
                0x300462F3,
                0x0000000F,
                0x0000100F,
                0x12000073,
                0x12208073,
            ],
        )

    def test_supervisor_csr_alias_encodings(self) -> None:
        words = self.assemble(
            """
            csrw stvec, x1
            csrr x2, sepc
            csrrw x3, sscratch, x4
            csrrsi x5, senvcfg, 8
            csrr x6, stimecmp
            csrr x7, stimecmph
            csrr x8, siselect
            csrr x9, sireg
            csrr x10, sireg2
            csrr x11, sireg3
            csrr x12, sireg4
            csrr x13, sireg5
            csrr x14, sireg6
            csrr x15, scountinhibit
            csrr x16, scountovf
            csrr x17, sstateen0
            csrr x18, sstateen3
            csrr x19, scontext
            csrw mcounteren, x20
            csrw scounteren, x21
            csrr x22, cycle
            csrr x23, time
            csrr x24, instret
            csrr x25, cycleh
            csrr x26, timeh
            csrr x27, instreth
            csrr x28, mcycle
            csrr x29, minstret
            """
        )
        self.assertEqual(
            words,
            [
                0x10509073,
                0x14102173,
                0x140211F3,
                0x10A462F3,
                0x14D02373,
                0x15D023F3,
                0x15002473,
                0x151024F3,
                0x15202573,
                0x153025F3,
                0x15502673,
                0x156026F3,
                0x15702773,
                0x120027F3,
                0xDA002873,
                0x10C028F3,
                0x10F02973,
                0x5A8029F3,
                0x306A1073,
                0x106A9073,
                0xC0002B73,
                0xC0102BF3,
                0xC0202C73,
                0xC8002CF3,
                0xC8102D73,
                0xC8202DF3,
                0xB0002E73,
                0xB0202EF3,
            ],
        )

    def test_amo_encodings(self) -> None:
        words = self.assemble(
            """
            lr.w x5, 0(x1)
            sc.w x6, x7, 0(x1)
            amoadd.w x8, x9, 0(x10)
            amoswap.w x11, x12, 0(x13)
            amoxor.w x14, x15, 0(x16)
            amoand.w x17, x18, 0(x19)
            amoor.w x20, x21, 0(x22)
            amomin.w x23, x24, 0(x25)
            amomax.w x26, x27, 0(x28)
            amominu.w x29, x30, 0(x31)
            amomaxu.w x1, x2, 0(x3)
            """
        )
        self.assertEqual(
            words,
            [
                0x1000A2AF,
                0x1870A32F,
                0x0095242F,
                0x08C6A5AF,
                0x20F8272F,
                0x6129A8AF,
                0x415B2A2F,
                0x818CABAF,
                0xA1BE2D2F,
                0xC1EFAEAF,
                0xE021A0AF,
            ],
        )

    def test_rv32m_encodings(self) -> None:
        words = self.assemble(
            """
            mul x3, x1, x2
            mulh x4, x1, x2
            mulhsu x5, x1, x2
            mulhu x6, x1, x2
            div x7, x1, x2
            divu x8, x1, x2
            rem x9, x1, x2
            remu x10, x1, x2
            """
        )
        self.assertEqual(
            words,
            [
                0x022081B3,
                0x02209233,
                0x0220A2B3,
                0x0220B333,
                0x0220C3B3,
                0x0220D433,
                0x0220E4B3,
                0x0220F533,
            ],
        )


if __name__ == "__main__":
    unittest.main()
