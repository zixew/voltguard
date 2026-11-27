#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

echo "==> Running unit tests (including weak deallocation & CrashReporter tests)..."
swift test

echo "==> Building dev binary..."
swift build -c debug
BIN_DIR="$(swift build -c debug --show-bin-path)"
DEV_BIN="$BIN_DIR/VoltGuard"

echo "==> Launching isolated dev instance for /usr/bin/leaks inspection..."
"$DEV_BIN" --dev-isolated >/tmp/voltguard-dev-leaks.log 2>&1 &
DEV_PID=$!
trap 'kill -TERM "$DEV_PID" 2>/dev/null || true' EXIT

sleep 2
if ! kill -0 "$DEV_PID" 2>/dev/null; then
    echo "ERROR: Dev binary exited unexpectedly."
    cat /tmp/voltguard-dev-leaks.log || true
    exit 1
fi

echo "==> Running leaks on PID $DEV_PID..."
leaks "$DEV_PID" | tail -n 20

echo "==> Sending SIGTERM for clean exit..."
kill -TERM "$DEV_PID"
wait "$DEV_PID" 2>/dev/null || true
trap - EXIT
echo "==> Leak & dev-connection check passed."
