#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo ">> Starting OpenOCD..."

openocd -f openocd.cfg > openocd.log 2>&1 &
OCD_PID=$!

cleanup() {
    echo ">> Stopping OpenOCD (pid $OCD_PID)..."
    kill "${OCD_PID}" 2>/dev/null || true
}
trap cleanup EXIT

echo ">> Waiting for OpenOCD to be ready (5 s timeout)..."

READY=0
for _i in $(seq 1 50); do
    if ! kill -0 "${OCD_PID}" 2>/dev/null; then
        echo "ERROR: OpenOCD exited unexpectedly. Log:"
        cat openocd.log >&2
        exit 1
    fi
    if grep -q "Listening on port 3333" openocd.log 2>/dev/null; then
        READY=1
        echo ">> OpenOCD ready"
        break
    fi
    sleep 0.1
done

if [[ "$READY" -eq 0 ]]; then
    echo "ERROR: OpenOCD did not become ready within 5 s. Log:"
    cat openocd.log >&2
    exit 1
fi

echo ">> Starting GDB..."

arm-none-eabi-gdb "$SCRIPT_DIR/build/main.elf" -q \
    -ex "set auto-load safe-path $SCRIPT_DIR" \
    -x "$SCRIPT_DIR/debug/gdb-dashboard.gdb" \
    -x "$SCRIPT_DIR/debug/debug.gdb"
