#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

PS_UART_PROBE_CFLAGS="${PS_UART_PROBE_CFLAGS:-} -DZYNQ_CPU_RV64_BOOT=1" \
    "$repo_dir/scripts/build_ps_uart_probe.sh"
