#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd -- "$SCRIPT_DIR/../.." && pwd)
TOOLS_DIR=${UART_TOOLS_DIR:-$(dirname -- "$REPO_ROOT")/.uart-tools}
mkdir -p "$TOOLS_DIR/logs"
TOOLS_DIR=$(cd -- "$TOOLS_DIR" && pwd)
python3 -m venv "$TOOLS_DIR/venv"
"$TOOLS_DIR/venv/bin/python" -m pip install --no-cache-dir pyslang==11.0.0
if [ ! -e "$TOOLS_DIR/uvm" ]; then
    git clone --depth 1 --branch UVM_1_2_RELEASE https://github.com/accellera/uvm.git "$TOOLS_DIR/uvm"
fi
if [ "$(git -C "$TOOLS_DIR/uvm" rev-parse HEAD)" != 71f30a7473118b3cea582d7673c3af8e161fce71 ]; then
    echo 'Unexpected UVM revision; use a separate UART_TOOLS_DIR.' >&2
    exit 1
fi
cd -- "$REPO_ROOT"
"$TOOLS_DIR/venv/bin/python" "$SCRIPT_DIR/check_uart.py" --tools-dir "$TOOLS_DIR" --prerequisites
