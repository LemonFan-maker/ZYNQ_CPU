#!/usr/bin/env bash
set -euo pipefail

scripts/run_zx32_toolchain_tests.sh
scripts/run_iverilog_tests.sh all
