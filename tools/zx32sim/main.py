from __future__ import annotations

import argparse
import bisect
import dataclasses
import os
import pathlib
import select
import sys
import termios
import tty
from typing import TextIO

from .block import BlockDevice
from .cpu import Cpu, StopReason, TraceConfig
from .elf import load_elf
from .memory import Memory
from .virtio import VirtioMmioBlockDevice


DEFAULT_CONSOLE_RING_BASE = 0x20010000
DEFAULT_CONSOLE_RING_HEAD = 0x20010100
DEFAULT_CONSOLE_RING_TOTAL = 0x20010104
DEFAULT_CONSOLE_RING_BYTES = 256
DEFAULT_CONSOLE_INPUT_BASE = 0x20010110
DEFAULT_CONSOLE_INPUT_HEAD = 0x20010190
DEFAULT_CONSOLE_INPUT_TOTAL = 0x20010194
DEFAULT_CONSOLE_INPUT_BYTES = 128


Symbol = tuple[int, str]


@dataclasses.dataclass
class ConsoleSend:
    needle: str
    data: bytes
    sent: bool = False


class Symbols:
    def __init__(self, entries: list[Symbol]) -> None:
        self.entries = sorted(entries, key=lambda item: item[0])
        self.addrs = [item[0] for item in self.entries]


def parse_assignment(text: str) -> tuple[int, int]:
    if "=" not in text:
        raise argparse.ArgumentTypeError("expected ADDR=VALUE")
    left, right = text.split("=", 1)
    return int(left, 0), int(right, 0)


def parse_file_assignment(text: str) -> tuple[int, pathlib.Path]:
    if "=" not in text:
        raise argparse.ArgumentTypeError("expected ADDR=FILE")
    left, right = text.split("=", 1)
    return int(left, 0), pathlib.Path(right)


def parse_console_send(text: str) -> ConsoleSend:
    if "=" not in text:
        raise argparse.ArgumentTypeError("expected NEEDLE=TEXT")
    needle, data = text.split("=", 1)
    return ConsoleSend(needle=needle, data=data.encode("utf-8"))


def load_console_script(path: pathlib.Path) -> list[ConsoleSend]:
    sends: list[ConsoleSend] = []
    for lineno, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        line = raw.strip()
        if not line:
            continue
        if line.startswith("#") and "\t" not in raw:
            continue
        if "\t" not in raw:
            raise ValueError(f"{path}:{lineno}: expected NEEDLE<TAB>TEXT")
        needle, data = raw.split("\t", 1)
        decoded = data.encode("utf-8").decode("unicode_escape").encode("utf-8")
        sends.append(ConsoleSend(needle=needle, data=decoded))
    return sends


def load_symbols(path: pathlib.Path) -> Symbols:
    symbols: list[Symbol] = []
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        parts = line.split()
        if len(parts) < 3:
            continue
        try:
            addr = int(parts[0], 16)
        except ValueError:
            continue
        symbols.append((addr & 0xFFFFFFFF, parts[2]))
    return Symbols(symbols)


def format_symbol(symbols: Symbols | None, addr: int) -> str:
    if symbols is None or not symbols.entries:
        return ""
    idx = bisect.bisect_right(symbols.addrs, addr & 0xFFFFFFFF) - 1
    if idx < 0:
        return ""
    sym_addr, name = symbols.entries[idx]
    off = (addr - sym_addr) & 0xFFFFFFFF
    if off == 0:
        return f" <{name}>"
    return f" <{name}+0x{off:x}>"


def read_console_ring(mem: Memory, base: int, total_addr: int, ring_bytes: int) -> tuple[int, str]:
    total = mem.read_u32(total_addr)
    count = min(total, ring_bytes)
    first = (total - count) & 0xFFFFFFFF
    chars: list[str] = []
    for off in range(count):
        idx = (first + off) & (ring_bytes - 1)
        word = mem.read_u32(base + (idx & ~3))
        byte = (word >> ((idx & 3) * 8)) & 0xFF
        chars.append(chr(byte) if byte else "\\0")
    return total, "".join(chars)


def drain_console_ring(mem: Memory, base: int, head_addr: int, total_addr: int, ring_bytes: int) -> str:
    head = mem.read_u32(head_addr)
    total = mem.read_u32(total_addr)
    count = min((total - head) & 0xFFFFFFFF, ring_bytes)
    chars: list[str] = []
    for off in range(count):
        idx = (head + off) & (ring_bytes - 1)
        word = mem.read_u32(base + (idx & ~3))
        byte = (word >> ((idx & 3) * 8)) & 0xFF
        chars.append(chr(byte) if byte else "\\0")
    if count:
        mem.write_u32(head_addr, total)
    return "".join(chars)


def write_console_input(
    mem: Memory,
    data: bytes,
    base: int = DEFAULT_CONSOLE_INPUT_BASE,
    head_addr: int = DEFAULT_CONSOLE_INPUT_HEAD,
    total_addr: int = DEFAULT_CONSOLE_INPUT_TOTAL,
    ring_bytes: int = DEFAULT_CONSOLE_INPUT_BYTES,
) -> None:
    head = mem.read_u32(head_addr)
    total = mem.read_u32(total_addr)
    used = (total - head) & 0xFFFFFFFF
    if used + len(data) > ring_bytes:
        raise ValueError(f"console input ring overflow: {used}+{len(data)}>{ring_bytes}")
    for off, byte in enumerate(data):
        idx = (total + off) & (ring_bytes - 1)
        addr = base + (idx & ~3)
        word = mem.read_u32(addr)
        shift = (idx & 3) * 8
        word = (word & ~(0xFF << shift)) | (byte << shift)
        mem.write_u32(addr, word)
    mem.write_u32(total_addr, (total + len(data)) & 0xFFFFFFFF)


def print_checkpoint(cpu: Cpu, mem: Memory, symbols: Symbols | None, words: list[int]) -> None:
    pc_sym = format_symbol(symbols, cpu.pc)
    print(
        f"checkpoint steps={cpu.steps} pc=0x{cpu.pc:08x}{pc_sym} priv={cpu.priv} "
        f"satp=0x{cpu.csr_read(0x180):08x} mcause=0x{cpu.csr_read(0x342):08x} "
        f"scause=0x{cpu.csr_read(0x142):08x}",
        file=sys.stderr,
    )
    for addr in words:
        print(f"  word[0x{addr:08x}]=0x{mem.read_u32(addr):08x}", file=sys.stderr)


def run_with_cli_stops(
    cpu: Cpu,
    mem: Memory,
    max_steps: int,
    stop_pc: int | None,
    stop_words: list[tuple[int, int]],
    stop_nonzero: list[int],
    stop_change: list[int],
    stop_console: list[str],
    console_sends: list[ConsoleSend],
    console_ring_base: int,
    console_ring_head: int,
    console_ring_total: int,
    console_ring_bytes: int,
    checkpoint_interval: int | None,
    checkpoint_words: list[int],
    symbols: Symbols | None,
    stop_check_interval: int = 1,
    event_out: TextIO = sys.stderr,
    interactive_console: bool = False,
    interactive_in_fd: int | None = None,
    interactive_out: TextIO = sys.stdout,
) -> StopReason:
    if (
        stop_pc is not None
        and not stop_words
        and not stop_nonzero
        and not stop_change
        and not stop_console
        and not console_sends
        and not interactive_console
        and checkpoint_interval is None
    ):
        return cpu.run(max_steps, stop_pc=stop_pc)
    if (
        stop_pc is None
        and not stop_words
        and not stop_nonzero
        and not stop_change
        and not stop_console
        and not console_sends
        and not interactive_console
        and checkpoint_interval is None
    ):
        return cpu.run(max_steps)

    initial_words = {addr: mem.read_u32(addr) for addr in stop_change}
    stop_check_interval = max(1, stop_check_interval)
    console_text = ""
    printed_console_len = 0
    while cpu.steps < max_steps:
        if stop_pc is not None and cpu.pc == stop_pc:
            return StopReason.BREAKPOINT
        for addr, expected in stop_words:
            if mem.read_u32(addr) == (expected & 0xFFFFFFFF):
                print(f"stop-word 0x{addr:08x}=0x{expected & 0xFFFFFFFF:08x}", file=event_out)
                return StopReason.BREAKPOINT
        for addr in stop_nonzero:
            actual = mem.read_u32(addr)
            if actual != 0:
                print(f"stop-nonzero 0x{addr:08x}=0x{actual:08x}", file=event_out)
                return StopReason.BREAKPOINT
        for addr, initial in initial_words.items():
            actual = mem.read_u32(addr)
            if actual != initial:
                print(f"stop-change 0x{addr:08x}: 0x{initial:08x}->0x{actual:08x}", file=event_out)
                return StopReason.BREAKPOINT
        if interactive_console and interactive_in_fd is not None:
            while True:
                readable, _writable, _errors = select.select([interactive_in_fd], [], [], 0)
                if not readable:
                    break
                data = os.read(interactive_in_fd, 4096)
                if not data:
                    break
                try:
                    write_console_input(mem, data)
                except ValueError as exc:
                    cpu.last_error = str(exc)
                    return StopReason.ERROR

        if stop_console or console_sends or interactive_console:
            console_text += drain_console_ring(
                mem,
                console_ring_base,
                console_ring_head,
                console_ring_total,
                console_ring_bytes,
            )
            if len(console_text) > 8192:
                dropped = len(console_text) - 8192
                console_text = console_text[-8192:]
                printed_console_len = max(0, printed_console_len - dropped)
            if interactive_console and console_text:
                if len(console_text) > printed_console_len:
                    interactive_out.write(console_text[printed_console_len:])
                    interactive_out.flush()
                    printed_console_len = len(console_text)
            for send in console_sends:
                if not send.sent and send.needle in console_text:
                    try:
                        write_console_input(mem, send.data)
                    except ValueError as exc:
                        cpu.last_error = str(exc)
                        return StopReason.ERROR
                    send.sent = True
                    print(f"console-send after {send.needle!r}: {len(send.data)} bytes", file=event_out)
            for needle in stop_console:
                if needle in console_text:
                    print(f"stop-console {needle!r}", file=event_out)
                    return StopReason.BREAKPOINT
        if checkpoint_interval and cpu.steps and cpu.steps % checkpoint_interval == 0:
            print_checkpoint(cpu, mem, symbols, checkpoint_words)
        next_stop = min(max_steps, cpu.steps + stop_check_interval)
        if checkpoint_interval:
            until_checkpoint = checkpoint_interval - (cpu.steps % checkpoint_interval)
            if until_checkpoint != checkpoint_interval or cpu.steps == 0:
                next_stop = min(next_stop, cpu.steps + until_checkpoint)
        reason = cpu.run(next_stop, stop_pc=stop_pc)
        if reason is not StopReason.RUNNING:
            if reason is StopReason.MAX_STEPS and cpu.steps < max_steps:
                continue
            return reason
    return StopReason.MAX_STEPS


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="ZX32 functional simulator")
    parser.add_argument("image", type=pathlib.Path, help="RV32 ELF image")
    parser.add_argument("--load-elf", action="append", type=pathlib.Path, default=[], help="additional RV32 ELF image to load")
    parser.add_argument("--load-raw", action="append", type=parse_file_assignment, default=[], help="load a raw binary blob at ADDR=FILE")
    parser.add_argument("--block-image", type=pathlib.Path, help="attach a raw 512-byte-sector block image at MMIO 0x10050000")
    parser.add_argument("--block-readonly", action="store_true", help="reject simulator block-device writes")
    parser.add_argument("--virtio-block-image", type=pathlib.Path, help="attach a virtio-mmio block image at MMIO 0x10060000")
    parser.add_argument("--virtio-block-readonly", action="store_true", help="advertise a read-only virtio block image and reject writes")
    parser.add_argument("--max-steps", type=int, default=100000)
    parser.add_argument("--entry", type=lambda x: int(x, 0))
    parser.add_argument("--stop-pc", type=lambda x: int(x, 0))
    parser.add_argument("--stop-word", action="append", type=parse_assignment, default=[], help="stop when ADDR contains VALUE")
    parser.add_argument("--stop-nonzero", action="append", type=lambda x: int(x, 0), default=[], help="stop when ADDR becomes non-zero")
    parser.add_argument("--stop-change", action="append", type=lambda x: int(x, 0), default=[], help="stop when ADDR changes from its post-load value")
    parser.add_argument("--stop-console", action="append", default=[], help="stop when the decoded console ring contains TEXT")
    parser.add_argument("--stop-check-interval", type=int, default=1, help="poll memory stop conditions every N steps")
    parser.add_argument("--continue-on-wfi", action="store_true", help="treat WFI as an idle step instead of a simulator stop")
    parser.add_argument("--poke-word", action="append", type=parse_assignment, default=[])
    parser.add_argument("--expect-word", action="append", type=parse_assignment, default=[])
    parser.add_argument("--dump-word", action="append", type=lambda x: int(x, 0), default=[])
    parser.add_argument("--checkpoint-interval", type=int, help="print simulator state every N steps")
    parser.add_argument("--checkpoint-word", action="append", type=lambda x: int(x, 0), default=[], help="word to include in checkpoint output")
    parser.add_argument("--symbols", type=pathlib.Path, help="System.map-style symbol file for PC annotation")
    parser.add_argument("--dump-console-ring", action="store_true", help="decode the Linux SBI scratch console ring after execution")
    parser.add_argument("--console-ring-base", type=lambda x: int(x, 0), default=DEFAULT_CONSOLE_RING_BASE)
    parser.add_argument("--console-ring-head", type=lambda x: int(x, 0), default=DEFAULT_CONSOLE_RING_HEAD)
    parser.add_argument("--console-ring-total", type=lambda x: int(x, 0), default=DEFAULT_CONSOLE_RING_TOTAL)
    parser.add_argument("--console-ring-bytes", type=int, default=DEFAULT_CONSOLE_RING_BYTES)
    parser.add_argument("--console-input", action="append", default=[], help="preload bytes for SBI console getchar")
    parser.add_argument("--console-input-file", action="append", type=pathlib.Path, default=[], help="preload stdin bytes from FILE")
    parser.add_argument("--console-send-after", action="append", type=parse_console_send, default=[], help="send TEXT once console ring contains NEEDLE")
    parser.add_argument("--console-script", action="append", type=pathlib.Path, default=[], help="load expect/send rows as NEEDLE<TAB>TEXT, with \\n escapes in TEXT")
    parser.add_argument("--console-input-base", type=lambda x: int(x, 0), default=DEFAULT_CONSOLE_INPUT_BASE)
    parser.add_argument("--console-input-head", type=lambda x: int(x, 0), default=DEFAULT_CONSOLE_INPUT_HEAD)
    parser.add_argument("--console-input-total", type=lambda x: int(x, 0), default=DEFAULT_CONSOLE_INPUT_TOTAL)
    parser.add_argument("--console-input-bytes", type=int, default=DEFAULT_CONSOLE_INPUT_BYTES)
    parser.add_argument("--interactive-console", action="store_true", help="bridge SBI console output to stdout and stdin to getchar")
    parser.add_argument("--trace-pc", action="store_true")
    parser.add_argument("--trace-trap", action="store_true")
    parser.add_argument("--trace-mem", action="store_true")
    parser.add_argument("--trace-csr", action="store_true")
    args = parser.parse_args(argv)

    mem = Memory()
    image = load_elf(args.image)
    images = [image] + [load_elf(path) for path in args.load_elf]
    for loaded in images:
        for segment in loaded.segments:
            mem.load(segment.addr, segment.data)
    for addr, path in args.load_raw:
        mem.load(addr, path.read_bytes())
    for addr, value in args.poke_word:
        mem.write_u32(addr, value)
    input_data = b"".join(text.encode("utf-8") for text in args.console_input)
    input_data += b"".join(path.read_bytes() for path in args.console_input_file)
    if input_data:
        try:
            write_console_input(
                mem,
                input_data,
                base=args.console_input_base,
                head_addr=args.console_input_head,
                total_addr=args.console_input_total,
                ring_bytes=args.console_input_bytes,
            )
        except ValueError as exc:
            print(str(exc), file=sys.stderr)
            return 2
    console_sends = list(args.console_send_after)
    for path in args.console_script:
        try:
            console_sends.extend(load_console_script(path))
        except ValueError as exc:
            print(str(exc), file=sys.stderr)
            return 2
    symbols = load_symbols(args.symbols) if args.symbols else None
    block = BlockDevice.from_file(args.block_image, readonly=args.block_readonly) if args.block_image else None
    virtio_blk = (
        VirtioMmioBlockDevice.from_file(args.virtio_block_image, readonly=args.virtio_block_readonly)
        if args.virtio_block_image
        else None
    )
    cpu = Cpu(
        mem=mem,
        pc=image.entry if args.entry is None else args.entry,
        trace=TraceConfig(pc=args.trace_pc, trap=args.trace_trap, mem=args.trace_mem, csr=args.trace_csr),
        block=block,
        virtio_blk=virtio_blk,
        stop_on_wfi=not args.continue_on_wfi,
    )
    old_term = None
    if args.interactive_console and sys.stdin.isatty():
        old_term = termios.tcgetattr(sys.stdin.fileno())
        tty.setcbreak(sys.stdin.fileno())
    try:
        reason = run_with_cli_stops(
            cpu=cpu,
            mem=mem,
            max_steps=args.max_steps,
            stop_pc=args.stop_pc,
            stop_words=args.stop_word,
            stop_nonzero=args.stop_nonzero,
            stop_change=args.stop_change,
            stop_console=args.stop_console,
            console_sends=console_sends,
            console_ring_base=args.console_ring_base,
            console_ring_head=args.console_ring_head,
            console_ring_total=args.console_ring_total,
            console_ring_bytes=args.console_ring_bytes,
            checkpoint_interval=args.checkpoint_interval,
            checkpoint_words=args.checkpoint_word,
            symbols=symbols,
            stop_check_interval=args.stop_check_interval,
            interactive_console=args.interactive_console,
            interactive_in_fd=sys.stdin.fileno() if args.interactive_console else None,
            interactive_out=sys.stdout,
        )
    finally:
        if old_term is not None:
            termios.tcsetattr(sys.stdin.fileno(), termios.TCSADRAIN, old_term)

    for addr in args.dump_word:
        print(f"0x{addr:08x}=0x{mem.read_u32(addr):08x}")

    if args.dump_console_ring:
        total, text = read_console_ring(mem, args.console_ring_base, args.console_ring_total, args.console_ring_bytes)
        head = mem.read_u32(args.console_ring_head)
        skipped = max(0, total - args.console_ring_bytes)
        print(
            f"console-ring total={total} head={head} bytes={args.console_ring_bytes} "
            f"captured={min(total, args.console_ring_bytes)} skipped={skipped}"
        )
        if text:
            print("console-ring text:")
            print(text, end="" if text.endswith("\n") else "\n")

    if block is not None and args.block_image and not args.block_readonly:
        block.write_file(args.block_image)
    if virtio_blk is not None and args.virtio_block_image and not args.virtio_block_readonly:
        virtio_blk.write_file(args.virtio_block_image)

    failed = False
    for addr, expected in args.expect_word:
        actual = mem.read_u32(addr)
        if actual != (expected & 0xFFFFFFFF):
            print(
                f"expect-word failed at 0x{addr:08x}: got 0x{actual:08x}, expected 0x{expected & 0xFFFFFFFF:08x}",
                file=sys.stderr,
            )
            failed = True

    if reason is StopReason.ERROR:
        print(f"simulation error: {cpu.last_error}", file=sys.stderr)
        return 1
    if failed:
        return 1
    print(f"stop={reason.value} steps={cpu.steps} pc=0x{cpu.pc:08x}{format_symbol(symbols, cpu.pc)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
