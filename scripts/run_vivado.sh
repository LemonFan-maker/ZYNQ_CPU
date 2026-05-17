#!/usr/bin/env bash
set -euo pipefail

if [[ $# -eq 0 ]]; then
  echo "usage: $0 <vivado arguments>" >&2
  exit 2
fi

cmd="source /home/orionisli/.zshrc >/dev/null 2>&1 && vi25 && vivado"
for arg in "$@"; do
  printf -v quoted_arg '%q' "$arg"
  cmd+=" ${quoted_arg}"
done

exec zsh -lc "$cmd"
