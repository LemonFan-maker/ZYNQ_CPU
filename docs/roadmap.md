# Roadmap

The project goal is a custom PL CPU that can run a useful riscv32 Linux environment. 

The first useful Linux milestone is now complete: the board boots a mainline RV32 kernel into an embedded Buildroot/BusyBox initramfs, starts the standard init scripts, reaches `buildroot login:`, and accepts interactive `hvc0` input.

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
- host-side image conversion, XSCT/JTAG VRAM download, and PPM dump helpers exist for offline framebuffer preview

## Current Development Stage

The active stage is:

```text
stabilize the board-proven Buildroot userspace and platform ABI
```

The immediate success signature to preserve is:

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

Do not treat later Linux regressions as userspace or kernel bugs until this signature still reproduces with the same Image/DTB/firmware layout.

## Current Linux Artifacts

Source-of-truth files:

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

Generated artifacts:

- `linux/kernel/`
- `build/linux-mainline-rv32/`
- `build/buildroot-zx32/`
- `build/linux/`
- `hw_bringup/build/`

These generated paths are ignored and should not become source-of-truth.

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
- validate the 640x480 test-pattern output before attaching framebuffer scanout
- keep EDID, audio, CEC, and dynamic mode selection out of the first board test
- add HPD and HDMI output-enable pins once their exact AX7020 pins are confirmed in the board constraints
- rerun Vivado implementation and check timing before treating the HDMI bitstream as board-ready

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
- add blit/scale-blit/alpha blend before triangle rasterization

## Later Performance Work

Performance is intentionally not the first priority. 

After Linux reaches a reliable small userspace, consider:

- simulator basic-block execution or a Rust/C/C++ hot core while retaining the Python model as reference
- broader cache policy work beyond the current small direct-mapped I-cache/D-cache
- burst-capable DDR bridge
- prefetch for instruction fetch from DDR
- larger local memories
- pipelining the core

Do not start with these unless a correctness milestone is blocked by current performance.
