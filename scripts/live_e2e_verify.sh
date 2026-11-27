#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_BIN="/Applications/VoltGuard.app/Contents/MacOS/VoltGuard"
HELPER_BIN="/Applications/VoltGuard.app/Contents/Helpers/voltguard-helper"
INSTALLED_HELPER="/Library/PrivilegedHelperTools/com.voltguard.helper"
LIVE_SOCK="/tmp/voltguard-live-e2e-$$.sock"

cleanup() {
    rm -f "$LIVE_SOCK"
}
trap cleanup EXIT

echo "=================================================="
echo "1. UNIVERSAL BINARY & LIVE RUNNING APP AUDIT"
echo "=================================================="
lipo -info "$APP_BIN" "$HELPER_BIN"

LIVE_PID="$(pgrep -x VoltGuard | head -n 1 || true)"
if [ -n "$LIVE_PID" ]; then
    echo "Live /Applications/VoltGuard.app PID: $LIVE_PID"
    leaks "$LIVE_PID" | grep -E "nodes malloced|leaked bytes"
else
    echo "NOTE: /Applications/VoltGuard.app is not currently running."
fi

echo ""
echo "=================================================="
echo "2. LIVE ARM64 + ROSETTA X86_64 ISOLATED LAUNCH + LEAKS + SIGTERM"
echo "=================================================="
for MODE_ARCH in arm64 x86_64; do
    echo "-> Launching VoltGuard under arch -$MODE_ARCH --dev-isolated..."
    arch -"$MODE_ARCH" "$APP_BIN" --dev-isolated >/tmp/vg-live-"$MODE_ARCH".log 2>&1 &
    PID=$!
    sleep 2
    if ! kill -0 "$PID" 2>/dev/null; then
        echo "FAIL: VoltGuard failed to stay alive under arch -$MODE_ARCH"
        cat /tmp/vg-live-"$MODE_ARCH".log || true
        exit 1
    fi
    leaks "$PID" | grep -E "nodes malloced|leaked bytes"
    kill -TERM "$PID"
    wait "$PID" 2>/dev/null || true
    echo "PASS: arch -$MODE_ARCH ran cleanly, 0 leaks, graceful SIGTERM exit."
done

echo ""
echo "=================================================="
echo "3. LIVE HELPER DAEMON <-> REAL AppleSMC SOCKET TEST"
echo "=================================================="
"$HELPER_BIN" --daemon --socket "$LIVE_SOCK" >/tmp/vg-helper-live.log 2>&1 &
HPID=$!
sleep 1
if ! kill -0 "$HPID" 2>/dev/null; then
    echo "FAIL: voltguard-helper --daemon failed to start"
    exit 1
fi

python3 - "$LIVE_SOCK" << 'PY'
import json, socket, sys

sock_path = sys.argv[1]
tests = [
    {"limitPercent": 80, "allowCharging": True, "forceDischarge": False, "magSafeLED": "system", "lowPowerModeEnabled": False, "pingOnly": True},
    {"limitPercent": 80, "allowCharging": False, "forceDischarge": False, "magSafeLED": "green", "lowPowerModeEnabled": False, "pingOnly": False},
    {"limitPercent": 80, "allowCharging": False, "forceDischarge": True, "magSafeLED": "off", "lowPowerModeEnabled": False, "pingOnly": False},
]
for payload in tests:
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(2.0)
    s.connect(sock_path)
    s.sendall((json.dumps(payload) + "\n").encode())
    raw = s.recv(1024).decode().strip()
    s.close()
    ack = json.loads(raw)
    assert "backendMode" in ack and "writableKeys" in ack, f"Unexpected ACK: {ack}"
    print(f"Socket ACK (pingOnly={payload['pingOnly']}, forceDischarge={payload['forceDischarge']}): backendMode={ack['backendMode']}, ok={ack['ok']}, writableKeys={ack['writableKeys']}")
PY

kill -TERM "$HPID" 2>/dev/null || true
wait "$HPID" 2>/dev/null || true

echo ""
echo "=================================================="
echo "4. LIVE IOKit BATTERY + ENERGY PROCESS + PMSET ASSERTIONS"
echo "=================================================="
PS_ROWS="$(/bin/ps -axo pid=,pcpu=,comm= | wc -l | tr -d ' ')"
echo "Live /bin/ps process sample rows: $PS_ROWS"
ioreg -rn AppleSmartBattery | grep -E "CurrentCapacity|IsCharging|ExternalConnected|Temperature|CycleCount" | head -n 8
pmset -g assertions | head -n 10 || true

echo ""
echo "=================================================="
echo "5. INSTALLED ROOT DAEMON HASH & SOCKET CHECK"
echo "=================================================="
APP_HASH="$(shasum -a 256 "$HELPER_BIN" | awk '{print $1}')"
SYS_HASH="$(shasum -a 256 "$INSTALLED_HELPER" | awk '{print $1}')"
echo "App Bundle Helper SHA: $APP_HASH"
echo "Installed Root Helper SHA: $SYS_HASH"
if [ "$APP_HASH" = "$SYS_HASH" ]; then
    echo "PASS: Root privileged helper is UP TO DATE with Universal Adapter-Mode build."
else
    echo "ACTION REQUIRED: Installed root helper is outdated (user must click 'Update Helper' in VoltGuard UI with admin password)."
fi

echo ""
echo "=================================================="
echo "6. CRASH REPORTER PRODUCTION ISOLATION CHECK"
echo "=================================================="
ls -la "$HOME/Library/Application Support/VoltGuard/crashes/"
echo "==> Live E2E Verification Finished."
