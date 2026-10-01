#!/usr/bin/env bash
# Runs integration_test/two_device_test.dart on two devices at once.
#
#   ./run_two_devices.sh <host-device-id> <client-device-id> [websocket|firebase]
#
# Optional: HOST_IP=192.168.1.20 ./run_two_devices.sh ...   (override auto-detected IP)
#
# Why the host is started first: both runs build into the same build/ folder,
# so the client build must not start until the host app is installed and running.

set -u

HOST_DEV="${1:?usage: $0 <host-device-id> <client-device-id> [websocket|firebase]}"
CLIENT_DEV="${2:?usage: $0 <host-device-id> <client-device-id> [websocket|firebase]}"
MODE="${3:-websocket}"

TEST="integration_test/two_device_test.dart"
ROOM="it_room_$(date +%s)"
LOG_DIR="$(mktemp -d)"
HOST_LOG="$LOG_DIR/host.log"
CLIENT_LOG="$LOG_DIR/client.log"

echo ">> mode=$MODE host=$HOST_DEV client=$CLIENT_DEV room=$ROOM"
echo ">> logs: $LOG_DIR"

# 1) Start the HOST in the background.
flutter test "$TEST" -d "$HOST_DEV" \
  --dart-define=ROLE=host \
  --dart-define=MODE="$MODE" \
  --dart-define=ROOM="$ROOM" \
  > >(tee "$HOST_LOG" | awk '{print "[host]   " $0; fflush()}') 2>&1 &
HOST_PID=$!

# 2) Wait until the host app is installed and has printed HOST_READY.
echo ">> waiting for the host app to be ready (first build can take minutes)..."
READY=0
for _ in $(seq 1 900); do
  if grep -q "HOST_READY" "$HOST_LOG" 2>/dev/null; then READY=1; break; fi
  if ! kill -0 "$HOST_PID" 2>/dev/null; then
    echo "!! host test exited before it became ready"
    exit 1
  fi
  sleep 1
done
if [ "$READY" -ne 1 ]; then
  echo "!! timed out waiting for HOST_READY"
  kill "$HOST_PID" 2>/dev/null
  exit 1
fi

# 3) Work out the host IP (websocket mode only).
HOST_IP="${HOST_IP:-}"
if [ "$MODE" = "websocket" ] && [ -z "$HOST_IP" ]; then
  HOST_IP="$(grep -o 'HOST_READY ip=[0-9.]*' "$HOST_LOG" | head -1 | sed 's/.*ip=//')"
  if [ -z "$HOST_IP" ]; then
    echo "!! could not read the host IP from the log; re-run with HOST_IP=<ip>"
    kill "$HOST_PID" 2>/dev/null
    exit 1
  fi
fi
echo ">> host ready (HOST_IP=${HOST_IP:-n/a}) - starting client"

# 4) Run the CLIENT in the foreground.
flutter test "$TEST" -d "$CLIENT_DEV" \
  --dart-define=ROLE=client \
  --dart-define=MODE="$MODE" \
  --dart-define=ROOM="$ROOM" \
  --dart-define=HOST_IP="$HOST_IP" \
  2>&1 | tee "$CLIENT_LOG" | awk '{print "[client] " $0; fflush()}'
CLIENT_RC=${PIPESTATUS[0]}

# 5) Collect the host result (if the client failed, don't wait for host timeouts).
if [ "$CLIENT_RC" -ne 0 ]; then
  kill "$HOST_PID" 2>/dev/null
  HOST_RC=1
  wait "$HOST_PID" 2>/dev/null
else
  wait "$HOST_PID"
  HOST_RC=$?
fi

echo
echo "================ RESULT ================"
echo "host   : $([ "$HOST_RC" -eq 0 ] && echo PASSED || echo FAILED)"
echo "client : $([ "$CLIENT_RC" -eq 0 ] && echo PASSED || echo FAILED)"
echo "logs   : $LOG_DIR"
[ "$HOST_RC" -eq 0 ] && [ "$CLIENT_RC" -eq 0 ]