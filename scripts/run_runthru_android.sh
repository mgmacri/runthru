#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AVD_NAME="${RUNTHRU_AVD_NAME:-runthru_api36}"
DEVICE_ID="${RUNTHRU_DEVICE_ID:-emulator-5554}"
ENV_FILE="${RUNTHRU_ENV_FILE:-$HOME/.bashrc}"
EMULATOR_LOG="${RUNTHRU_EMULATOR_LOG:-/tmp/runthru-android-emulator.log}"
# swiftshader_indirect forces software rendering on the CPU and can cause thermal shutdown.
# Override with: ANDROID_EMULATOR_GPU=swiftshader_indirect ./run_runthru_android.sh
ANDROID_EMULATOR_GPU="${ANDROID_EMULATOR_GPU:-host}"

if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
fi

required_vars=(
  INSTAPAPER_CONSUMER_KEY
  INSTAPAPER_CONSUMER_SECRET
  GOOGLE_SIGN_IN_CLIENT_ID
  GOOGLE_SIGN_IN_SERVER_CLIENT_ID
)

for var_name in "${required_vars[@]}"; do
  if [[ -z "${!var_name:-}" ]]; then
    echo "Missing required environment variable: $var_name" >&2
    echo "Set it in $ENV_FILE or export it before running this script." >&2
    exit 1
  fi
done

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
exec flutter run -d "$DEVICE_ID" \
  --dart-define="INSTAPAPER_CONSUMER_KEY=$INSTAPAPER_CONSUMER_KEY" \
  --dart-define="INSTAPAPER_CONSUMER_SECRET=$INSTAPAPER_CONSUMER_SECRET" \
  --dart-define="GOOGLE_SIGN_IN_CLIENT_ID=$GOOGLE_SIGN_IN_CLIENT_ID" \
  --dart-define="GOOGLE_SIGN_IN_SERVER_CLIENT_ID=$GOOGLE_SIGN_IN_SERVER_CLIENT_ID" \
  "$@"
