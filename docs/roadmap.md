# Roadmap

The project goal is a custom PL CPU that can run a useful Linux environment.

The RV32 line reached that goal first: the board boots a mainline RV32 kernel into an embedded Buildroot/BusyBox initramfs, starts the standard init scripts, reaches `buildroot login:`, and accepts interactive `hvc0` input.

The active work now happens on the `riscv64gc` branch and has two tracks:

1. **ZX32 (RV32)** — stabilize the board-proven Buildroot userspace, HDMI/VRAM display path, and the MMIO GPU.
2. **ZX64 (RV64GC)** — a new 5-stage RV64GC SoC with PLIC and PS-backed virtio-blk/virtio-input, with a complete mainline RV64 Linux (v7.1.3) boot chain using an ext4 rootfs on `/dev/vda`. So far this is validated in Icarus simulation, Vivado implementation (timing met with the FPU disabled; the full-FPU build does not fit the part), and scripted boot-contract checks; the first board boot has not been run yet.

## Completed Bring-Up Milestones

These are already represented in code, tests, or board logs:

- local RV32-style core execution in simulation
- assembler and minimal ELF generation flow
- PS-loadable PL CPU programs
- AXI-Lite PS-to-PL register probe
- DataMover loopback through PS DDR
- PL CPU initiated DataMover transfers
- ELF loading and reset-vector selection
- M-mode trap smoke
- S-mode trap smoke
- timer interrupt delegation to S-mode
- boot payload handoff with `a0=hartid`, `a1=dtb`
- S-mode counter CSR access
- direct DDR load/store from PL CPU
- instruction fetch and execution from the DDR window
- high-address DDR load/store, instruction fetch, and AMO smokes
- SBI-style firmware and timer smoke tests
- Linux boot contract smoke
- Linux SBI compatibility smoke
- Linux image layout smoke
- PS-side real Linux Image/DTB loader
- local SBI shim with console and TIME services sufficient for kernel boot
- mainline RV32 Linux reaches `Run /init as init process`
- embedded Buildroot rootfs starts syslogd, klogd, sysctl, network setup, crond, and getty
- interactive login over `hvc0` works through the PS/SBI console bridge
- Python functional simulator boots the same Linux Image/DTB/SBI firmware to `buildroot login:`
- simulator live console supports `root` login and BusyBox shell commands through the scratch SBI console path
- simulator expect/send console scripts support repeatable login and command-output checks
- simulator virtio-mmio block model and simulator-only DTB exist for disk experiments
- simulator WFI/timer fast-forward keeps Linux idle runs practical
- Vivado 2025.2 bitstream generation with timing met at the current 75 MHz target
- DDR read-side I-cache/D-cache behavior is active in the SoC, including stream-gated D-cache next-line prefetch for sequential read misses
- GPU renderer v0 exists as an MMIO device for framebuffer clear, fill-rectangle, draw-line, and four-entry FIFO DDR writeback tests
- Linux userspace GPU smoke test exists as `zx32_gpu_smoke`, using `/dev/mem` and the reserved `0xbc00_0000` framebuffer region
- Linux userspace GPU demo and image viewer can write simple graphics or XRGB8888 images into the reserved VRAM region
- Linux userspace monitoring tools include GPU utilization/VRAM reporting and a PS-published Zynq XADC temperature readout
- host-side image conversion, XSCT/JTAG VRAM download, and PPM dump helpers exist for offline framebuffer preview


## Completed ZX64 (RV64) Milestones

Represented in RTL, testbenches, scripts, or the RV64 Vivado build (`build/vivado_hw_rv64`):

- RV64 single-cycle core (`zx64_core`) and 5-stage pipeline core (`zx64_core5`): rv64gc_zicsr_zifencei, Sv39, M/S/U, RV64A doubleword atomics, FPU with `ENABLE_FPU`, compressed fetch
- `zx64_soc`/`zx64_soc_bd`: 32 KiB `simple_ram64` IMEM, ZX32-compatible UART/timer/scratch, `mmio_plic_min` (2 sources), `mmio_virtio_blk_regs`, `mmio_virtio_input_regs`, cached AXI4 DDR bridge
- Icarus regressions: `core64`, `core64-5stage`, `soc64*` (host/ddr/sv39/sbi/real-sbi/linux handoff), `plic`, `virtio-blk-regs`, `virtio-input-regs`, `zx64-fw`, `zx64-boot-chain`
- RV64 boot artifacts: `linux/zx64.dts` + effective-DTS generator (`virtio-blk` + `simple-framebuffer` + PLIC enabled), `zx64_rv64.config` kernel fragment, mainline Linux v7.1.3 RV64 Image (6.5 MB), Buildroot-zx64 rootfs cpio, 64 MiB ext4 rootfs image
- RV64 S-mode boot firmware (`linux_boot_firmware.rv64.S`) with the same scratch-ring SBI console/timer contract as RV32
- RV64 Vivado bring-up build timing-clean at 75 MHz with `ZYNQ_CPU_RV64_ENABLE_FPU=0`; the FPU-enabled RV64GC build over-utilizes the XC7Z020 and is an open blocker (`docs/synthesis_status.md`); `scripts/check_zx64_vivado_bitstream.sh` and `check_zx64_linux_boot_chain.sh` gate the contract
- ArchLinux-readiness analysis recorded in `scripts/check_zx64_archlinux_readiness.sh` (standard-kernel contract checks)

## Current Development Stage

The active stage is:

```text
run the ZX64 RV64 Linux boot chain on the board
```

Success signature for that run:

```text
Linux version 7.1.3 ... riscv64
...
VFS: Mounted root (ext4 filesystem) on device 254:0
...
Welcome to Buildroot
buildroot login:
```

The parallel standing stage for RV32 remains:

```text
stabilize the board-proven Buildroot userspace and platform ABI
```

The RV32 regression baseline that must keep reproducing (same Image/DTB/firmware layout) is:

```text
Saving 2048 bits of non-creditable seed for next boot
Starting syslogd: OK
Starting klogd: OK
Running sysctl: OK
Starting network: OK
Starting crond: OK
Welcome to Buildroot
buildroot login:
```

Do not treat later RV32 Linux regressions as userspace or kernel bugs until this signature still reproduces.


## Current Linux Artifacts

Source-of-truth files (RV32):

- `docs/linux_bringup.md`
- `docs/linux_boot_layout.md`
- `docs/simulator.md`
- `linux/zynq_cpu.dts`
- `linux/zx32sim_virtio.dts`
- `linux/zx32_rv32.config`
- `hw_bringup/ps_linux_boot.c`
- `hw_bringup/programs/linux_boot_firmware.zx32.s`
- `hw_bringup/download_zynq_cpu_linux_boot.xsbl`
- `tools/zx32sim/`
- `tools/test_zx32sim.py`
- `scripts/run_zx32sim_linux_early.sh`
- `scripts/run_zx32sim_smokes.sh`

Source-of-truth files (RV64 / ZX64):

- `rtl/core64/`, `rtl/soc/zx64_soc.sv`, `rtl/soc/zx64_soc_bd.v`, `rtl/periph/mmio_plic_min.sv`, `rtl/periph/mmio_virtio_blk_regs.sv`, `rtl/periph/mmio_virtio_input_regs.sv`, `rtl/periph/simple_ram64.sv`
- `linux/zx64.dts`, `linux/zx64_rv64.config`
- `hw_bringup/programs/linux_boot_firmware.rv64.S`
- `hw_bringup/download_zynq_cpu_rv64_linux_boot.xsbl`
- `scripts/prepare_mainline_rv64_linux.sh`, `scripts/prepare_zx64_linux_boot_artifacts.sh`, `scripts/build_ps_linux_boot_rv64.sh`
- `scripts/check_zx64_linux_boot_chain.sh`, `scripts/check_zx64_linux_boot_firmware.sh`, `scripts/check_zx64_standard_kernel_contract.sh`, `scripts/check_zx64_vivado_bitstream.sh`, `scripts/check_zx64_archlinux_readiness.sh`
- `vivado/build_hw_bringup.tcl` (`ZYNQ_CPU_SOC=rv32|rv64`)
- `tb/tb_zx64_*.sv`, `tb/tb_mmio_plic_min.sv`, `tb/tb_mmio_virtio_*_regs.sv`

Generated artifacts:

- `linux/kernel/`, `linux/kernel-v7.1.3/`
- `build/linux-mainline-rv32/`, `build/buildroot-zx32/`, `build/linux/`
- `build/linux-mainline-rv64/`, `build/buildroot-zx64/`, `build/zx64-buildroot/`, `build/linux-rv64/`
- `build/vivado_hw/`, `build/vivado_hw_rv64/`
- `hw_bringup/build/`

These generated paths are ignored and should not become source-of-truth.

## Next Milestone: RV64 Board Boot

Goal: make the ZX64 RV64 Linux boot chain real on hardware, not only in simulation.

Required work:

```text
Linux version 7.1.3 ... riscv64
VFS: Mounted root (ext4 filesystem) on device 254:0
Welcome to Buildroot
buildroot login:
```

- build the RV64 bitstream with the default build dir (`ZYNQ_CPU_SOC=rv64`) and program the board
- run `download_zynq_cpu_rv64_linux_boot.xsbl` and capture the full PS UART log into `docs/hardware_uart_test.md`
- confirm virtio-blk enumeration, ext4 mount, and `hvc0` login over the shared scratch console
- re-verify timer behavior on the 5-stage core (`lpj=10000` still sane, SBI TIME events firing)
- if any step fails, fall back to the simulator-side scripts (`tb_zx64_soc_real_sbi.sv`, `tb_zx64_soc_linux_handoff.sv`) before touching userspace

## Next Milestone: Stable Buildroot Regression

Goal: make the current Linux boot and login path easy to rerun and compare.

Required work:

- keep the final success condition as `Welcome to Buildroot` followed by `buildroot login:`
- keep the simulator success condition aligned with the board success condition
- keep one scripted simulator login test that runs `uname -a`, `hostname`, and a marker command
- keep the PS launcher quiet by default and gate noisy periodic monitor samples
- keep a compact expected-log section in `docs/hardware_uart_test.md`
- record the exact Image/DTB addresses through `build/linux/boot_artifacts.env`
- make all Linux boot diagnostics explainable from `docs/linux_boot_layout.md`

## Next Milestone: Better Interactive Console

Goal: make the interactive terminal path feel usable instead of merely functional.

Required work:

- reduce input latency in the PS UART to SBI getchar path
- keep the scratch-ring overflow behavior explicit and observable
- decide whether `hvc0` remains the primary console or becomes only an early-console path
- validate repeated login shell commands, line editing, and long input bursts
- decide whether the simulator should add terminal raw-mode support for character-at-a-time line editing tests

## Next Milestone: Simulator as a Software Debug Target

Goal: make software/debug workflows possible without a board while keeping board behavior as the final authority.

Required work:

- keep `docs/simulator.md` synchronized with CLI flags and runner environment variables
- add regression coverage for interactive console scripts that compare expected shell output
- add optional larger simulator-only memory DTB once Linux/rootfs experiments need more RAM
- define whether simulator-only devices live permanently in `zx32sim_virtio.dts` or move to separate DTB variants
- add enough tracing around traps, page faults, and SBI calls to debug Linux failures without noisy default output
- keep Python simulator behavior as the reference model if a faster Rust/C/C++ core is introduced later

## Next Milestone: Buildroot Platform Cleanup

Goal: remove remaining bring-up assumptions from the Buildroot/Linux configuration.

Required work:

- keep rootfs size within the current Image/DTB placement constraints
- remove or explain init scripts for Linux features the platform does not implement yet
- verify POSIX timer, sysctl, network setup, crond, getty, and shell behavior after kernel config changes
- decide which Buildroot packages are useful enough to keep in the default rootfs

## Next Milestone: Firmware and Platform ABI Cleanup

Goal: replace bring-up assumptions with a stable platform contract.

Required work:

- decide whether to keep the local SBI shim or move toward OpenSBI
- document the permanent relationship between CSR `time` and MMIO `mtime`
- clean up the current timer offset bridge if the clocks can be made identical
- define which devices Linux should see directly and which should be hidden behind SBI
- keep the DTB synchronized with real hardware and with any Linux-visible drivers
- document reserved memory needs for firmware, DTB, and future initramfs growth

## Next Milestone: CPU/Memory Correctness Around Linux

Goal: expand regressions around behavior Linux actually exercises.

Required work:

- add MMU-focused simulation tests for valid/invalid PTE cases
- add accessed/dirty and permission behavior tests around Linux page-table use
- add interrupt priority/delegation tests
- expand AMO/LR/SC and memory-ordering tests
- test direct DDR load/store with wider address and alignment cases
- decide whether scratchpad memories should become explicit block RAMs

## Next Milestone: HDMI Test Pattern Bring-Up

Goal: move from offline VRAM dumps to a real monitor-lockable HDMI signal.

Required work:

- use AX7020 HDMI OUT on PL BANK34 as the physical display path
- validate the 1920x1080@60 boot-console/test-pattern output before attaching framebuffer scanout
- keep EDID, audio, CEC, and dynamic mode selection out of the first board test
- add HPD and HDMI output-enable pins once their exact AX7020 pins are confirmed in the board constraints
- rerun Vivado implementation and check timing before treating the HDMI bitstream as board-ready

## Completed: J20 LCD Console Mirror (Display2)

Goal: keep a working text console available even when the HDMI sink is absent.

Delivered:

- second text console on the J20 480x272 DE-mode LCD (60x17 cells), always
  mirroring the HDMI console's stream (PS fans every console byte into both
  parsers)
- `lcd_text_console_core.sv` / `mmio_lcd_display_ctrl.sv` /
  `lcd_console_top_xilinx.v` + `constraints/ax7020_lcd_j20.xdc`
- display2 MMIO window at PL `0x1009_0000` (PS alias `0x43c2_0000+0x10000`,
  128K zx32_soc aperture); rv64 builds keep the LCD cell idle
- iverilog TB (`tb_lcd_console.sv`, `lcd-console` target) covering clear scan,
  DE/HS/VS geometry, palette pixels, and the PS host-bus write path
- board test pending: LCD should show the same boot text as HDMI after
  `./scripts/run_xsct.sh hw_bringup/download_zynq_cpu_linux_boot.xsbl`

## Next Milestone: Framebuffer Scanout

Goal: continuously scan the reserved VRAM framebuffer to HDMI.

Required work:

- keep the default framebuffer at `0xbc00_0000` in little-endian XRGB8888
- add an independent burst display-DMA read master instead of reusing the current serialized GPU write path
- add at least double line buffering between AXI/DDR and pixel clock domains
- bring modes up in order: 640x480@60, then 1280x720@60, then 1920x1080@60
- expose underflow count, scan position, mode status, and framebuffer address through `0x1008_0000`
- validate 1080p60 only when `underflow_count == 0` over a sustained board run

## Next Milestone: GPU Renderer Bring-Up

Goal: turn the current RTL-level fill renderer into a useful Linux-visible rendering experiment.

Required work:

- run `zx32_gpu_smoke` on board Linux and capture the PASS/fail signature
- run `zx32_gpu_demo` while HDMI scanout is enabled and confirm that the display updates from shared VRAM
- keep the reserved `0xbc00_0000` framebuffer smoke region until a real allocator contract is needed
- keep the GPU path polling-based until the interrupt contract is needed
- rerun Vivado implementation before treating the renderer as board-ready
- blit, color-key blit, scale-blit, and alpha-blit are implemented; the next renderer steps are triangle rasterization and a VRAM allocator contract

## Later Performance Work

Performance is intentionally not the first priority. 

After Linux reaches a reliable small userspace, consider:

- an RV64 Python/Rust functional model mirroring `zx32_core5` (currently RV64 has no simulator)
- broader cache policy work beyond the current small direct-mapped I-cache/D-cache
- burst-capable DDR bridge
- prefetch for instruction fetch from DDR
- larger local memories
- (pipelining is done in the RV64 line: `zx64_core5`; the RV32 core stays multi-cycle)

Do not start with these unless a correctness milestone is blocked by current performance.
