#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PYTHONPATH="$repo_dir/tools${PYTHONPATH:+:$PYTHONPATH}" python3 "$repo_dir/tools/test_zx32asm.py"
PYTHONPATH="$repo_dir/tools${PYTHONPATH:+:$PYTHONPATH}" python3 "$repo_dir/tools/test_zx32elf.py"
