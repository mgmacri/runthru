#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AVD_NAME="runthru_api36"
DEVICE_ID="emulator-5554"
DART_DEFINES_FILE="dart_defines/development.json"
EMULATOR_LOG="/tmp/runthru-android-emulator.log"
ANDROID_EMULATOR_GPU="host"

required_vars=(
  INSTAPAPER_CONSUMER_KEY
  INSTAPAPER_CONSUMER_SECRET
  GOOGLE_WEB_CLIENT_ID
)

load_json_var_from_dart_defines_file() {
  local var_name="$1"
  jq -er --arg var_name "$var_name" '.[$var_name] // empty' "$ROOT_DIR/$DART_DEFINES_FILE"
}

if [[ ! -f "$ROOT_DIR/$DART_DEFINES_FILE" ]]; then
  echo "Missing dart defines file: $DART_DEFINES_FILE" >&2
  echo "Create it from dart_defines/development.json.example." >&2
  exit 1
fi

if command -v jq >/dev/null; then
  for var_name in "${required_vars[@]}"; do
    if ! load_json_var_from_dart_defines_file "$var_name" >/dev/null; then
      echo "Missing required dart define in $DART_DEFINES_FILE: $var_name" >&2
      exit 1
    fi
  done
fi

device_state() {
  adb -s "$DEVICE_ID" get-state 2>/dev/null || true
}

boot_completed() {
  adb -s "$DEVICE_ID" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r' || true
}

if [[ "$(device_state)" != "device" ]]; then
  echo "Starting $AVD_NAME on $DEVICE_ID..."
  nohup emulator -avd "$AVD_NAME" -gpu "$ANDROID_EMULATOR_GPU" -no-snapshot \
    >"$EMULATOR_LOG" 2>&1 &
  echo "Emulator log: $EMULATOR_LOG"
fi

echo "Waiting for Android to finish booting..."
for _ in $(seq 1 90); do
  if [[ "$(device_state)" == "device" && "$(boot_completed)" == "1" ]]; then
    break
  fi
  sleep 2
done

if [[ "$(device_state)" != "device" || "$(boot_completed)" != "1" ]]; then
  echo "Timed out waiting for $DEVICE_ID to boot." >&2
  echo "Check emulator log: $EMULATOR_LOG" >&2
  exit 1
fi

adb -s "$DEVICE_ID" shell true >/dev/null
if ! adb -s "$DEVICE_ID" shell pidof system_server >/dev/null; then
  echo "Android system_server is not healthy on $DEVICE_ID." >&2
  exit 1
fi

cd "$ROOT_DIR"
echo "Launching Flutter with normative configuration: $DART_DEFINES_FILE"
exec flutter run -d "$DEVICE_ID" \
  --dart-define-from-file="$DART_DEFINES_FILE" \
  "$@"
