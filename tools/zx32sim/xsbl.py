from __future__ import annotations

import argparse
import dataclasses
import pathlib
import shlex
import sys

from .main import main as sim_main


DDR_CPU_BASE = 0x80000000
DDR_PS_BASE = 0x00000000
LINUX_KERNEL_CPU_ADDR = 0x80400000
LINUX_DTB_CPU_ADDR = 0x82000000
CPU_LINUX_ENTRY = 0x20010300
CPU_LINUX_DTB = 0x20010304
DEFAULT_LINUX_FIRMWARE = pathlib.Path("hw_bringup/build/elf/linux_boot_firmware.elf")


@dataclasses.dataclass(frozen=True)
class DataDownload:
    path: pathlib.Path
    ps_addr: int
    cpu_addr: int


@dataclasses.dataclass(frozen=True)
class XsblPlan:
    script: pathlib.Path
    firmware: pathlib.Path
    data_downloads: list[DataDownload]
    launcher: pathlib.Path
    ignored_commands: list[str]

    def sim_argv(self) -> list[str]:
        argv = [str(self.firmware)]
        for download in self.data_downloads:
            argv.extend(["--load-raw", f"0x{download.cpu_addr:08x}={download.path}"])
        argv.extend(
            [
                "--poke-word",
                f"0x{CPU_LINUX_ENTRY:08x}=0x{LINUX_KERNEL_CPU_ADDR:08x}",
                "--poke-word",
                f"0x{CPU_LINUX_DTB:08x}=0x{LINUX_DTB_CPU_ADDR:08x}",
            ]
        )
        return argv


def ps_to_cpu_addr(ps_addr: int) -> int:
    if ps_addr < DDR_PS_BASE:
        raise ValueError(f"PS address 0x{ps_addr:08x} is below the ZX32 DDR window")
    return ((ps_addr - DDR_PS_BASE) + DDR_CPU_BASE) & 0xFFFFFFFF


def _strip_tcl_comment(line: str) -> str:
    in_quote = False
    escaped = False
    for idx, ch in enumerate(line):
        if escaped:
            escaped = False
            continue
        if ch == "\\":
            escaped = True
            continue
        if ch == '"':
            in_quote = not in_quote
            continue
        if ch == "#" and not in_quote:
            return line[:idx]
    return line


def _split_command(line: str) -> list[str]:
    normalized = line.replace("{", "'").replace("}", "'")
    return shlex.split(normalized, comments=False, posix=True)


def _resolve_path(repo_dir: pathlib.Path, raw: str) -> pathlib.Path:
    path = pathlib.Path(raw)
    if path.is_absolute():
        return path
    return repo_dir / path


def load_xsbl_plan(script: pathlib.Path, repo_dir: pathlib.Path, firmware: pathlib.Path) -> XsblPlan:
    script = script.resolve()
    repo_dir = repo_dir.resolve()
    firmware = firmware if firmware.is_absolute() else repo_dir / firmware
    data_downloads: list[DataDownload] = []
    launcher: pathlib.Path | None = None
    ignored: list[str] = []

    for lineno, raw in enumerate(script.read_text(encoding="utf-8").splitlines(), start=1):
        line = _strip_tcl_comment(raw).strip()
        if not line:
            continue
        try:
            parts = _split_command(line)
        except ValueError as exc:
            raise ValueError(f"{script}:{lineno}: cannot parse command: {exc}") from exc
        if not parts:
            continue

        cmd = parts[0]
        if cmd == "dow":
            if len(parts) >= 4 and parts[1] == "-data":
                path = _resolve_path(repo_dir, parts[2])
                ps_addr = int(parts[3], 0)
                data_downloads.append(DataDownload(path=path, ps_addr=ps_addr, cpu_addr=ps_to_cpu_addr(ps_addr)))
                continue
            if len(parts) == 2:
                launcher = _resolve_path(repo_dir, parts[1])
                continue
            raise ValueError(f"{script}:{lineno}: unsupported dow form: {line}")

        if cmd in {"connect", "targets", "rst", "fpga", "source", "ps7_init", "ps7_post_config", "con"}:
            ignored.append(line)
            continue

        raise ValueError(f"{script}:{lineno}: unsupported XSBL command: {line}")

    if launcher is None:
        raise ValueError(f"{script}: no ARM launcher ELF found; expected a 'dow <launcher>.elf' command")
    if launcher.name != "ps_linux_boot.elf":
        raise ValueError(
            f"{script}: launcher {launcher.name!r} is not emulated yet; "
            "currently only ps_linux_boot.elf is mapped to a ZX32 simulator boot plan"
        )
    if not firmware.exists():
        raise FileNotFoundError(f"ZX32 Linux firmware ELF not found: {firmware}")
    missing = [download.path for download in data_downloads if not download.path.exists()]
    if missing:
        raise FileNotFoundError("download data file not found: " + ", ".join(str(path) for path in missing))

    return XsblPlan(
        script=script,
        firmware=firmware,
        data_downloads=data_downloads,
        launcher=launcher,
        ignored_commands=ignored,
    )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Run the ZX32 simulator from a board-style XSCT/XSBL download script"
    )
    parser.add_argument("--repo-dir", type=pathlib.Path, default=pathlib.Path.cwd())
    parser.add_argument("--firmware", type=pathlib.Path, default=DEFAULT_LINUX_FIRMWARE)
    parser.add_argument("--print-plan", action="store_true", help="print the derived simulator loads before running")
    parser.add_argument("script", type=pathlib.Path)
    parser.add_argument("sim_args", nargs=argparse.REMAINDER, help="extra arguments passed to tools.zx32sim.main")
    args = parser.parse_args(argv)

    sim_args = args.sim_args
    if sim_args and sim_args[0] == "--":
        sim_args = sim_args[1:]

    try:
        plan = load_xsbl_plan(args.script, args.repo_dir, args.firmware)
    except (OSError, ValueError) as exc:
        print(f"zx32sim-xsbl: {exc}", file=sys.stderr)
        return 2

    if args.print_plan:
        print(f"xsbl: {plan.script}", file=sys.stderr)
        print(f"launcher: {plan.launcher}", file=sys.stderr)
        print(f"firmware: {plan.firmware}", file=sys.stderr)
        for download in plan.data_downloads:
            print(
                f"dow -data {download.path} PS=0x{download.ps_addr:08x} CPU=0x{download.cpu_addr:08x}",
                file=sys.stderr,
            )
        for command in plan.ignored_commands:
            print(f"ignored: {command}", file=sys.stderr)

    return sim_main(plan.sim_argv() + sim_args)


if __name__ == "__main__":
    raise SystemExit(main())
