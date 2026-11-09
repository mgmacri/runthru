---
description: "Infra I1.5: Tier 2 build script, Tier 3 device run script, and unified ci.sh entry point. Produces build-ios.sh, run-device.sh, ci.sh."
mode: agent
---

# Infra Step I1.5 — CI Loop Scripts

> **Milestone**: I1.5 | **Backlog**: `doc/infra-backlog.json`
> **Depends on**: I1.2 (toolchain), I1.3 (sync)
> **Produces**: `scripts/infra/build-ios.sh`, `scripts/infra/run-device.sh`, `scripts/infra/ci.sh`

Load shared context first: [infra-osx-kvm-context](./../instructions/infra-osx-kvm-context.instructions.md)

---

## Task

### TI1.5.1.1 — scripts/infra/build-ios.sh (Tier 2)

```bash
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
START=$(date +%s)

echo "=== Tier 2: iOS Build ==="

# Step 1: sync
echo "--- Syncing to VM ---"
bash "$SCRIPT_DIR/sync.sh"

# Step 2: build in VM (stream output in real time)
echo "--- flutter build ios --no-codesign ---"
ssh mac-vm 'cd ~/runthru && flutter build ios --no-codesign'
EXIT=$?

ELAPSED=$(( $(date +%s) - START ))
if [[ $EXIT -eq 0 ]]; then
  echo "BUILD PASS (${ELAPSED}s)"
else
  echo "BUILD FAIL (${ELAPSED}s)"
fi
exit $EXIT
```

Requirements:
- Real-time streaming: `ssh mac-vm` inherits stdout/stderr — no buffering
- Exit code matches flutter build exit code

### TI1.5.2.1 — scripts/infra/run-device.sh (Tier 3)

```bash
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== Tier 3: Device Run ==="

# Step 1: sync
bash "$SCRIPT_DIR/sync.sh"

# Step 2: detect device ID
echo "--- Detecting iOS device ---"
DEVICE_LINE=$(ssh mac-vm 'flutter devices 2>/dev/null | grep ios' || true)
if [[ -z "$DEVICE_LINE" ]]; then
  echo "ERROR: No iOS device found in VM."
  echo "  1. Is iPhone connected and VM started with --usb-passthrough?"
  echo "  2. Did you tap 'Trust This Computer' on the iPhone?"
  echo "  3. Run: ssh mac-vm 'flutter devices' to debug"
  exit 1
fi

DEVICE_ID=$(echo "$DEVICE_LINE" | grep -oP '(?<=• )[a-f0-9-]+(?= •)' | head -1)
echo "Found device: $DEVICE_ID"

# Step 3: flutter run with interactive TTY (hot reload works)
echo "--- flutter run (hot reload: r, quit: q) ---"
ssh -t mac-vm "cd ~/runthru && flutter run -d '$DEVICE_ID'"
```

### TI1.5.3.1 — scripts/infra/ci.sh (unified entry point)

```bash
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

usage() {
  cat <<EOF
Usage: ci.sh <command>

Commands:
  --tier 1        dart analyze + flutter test on Linux host
  --tier 2        sync + flutter build ios in VM
  --tier 3        sync + flutter run on iPhone via VM
  --watch         start watch daemon (Tier 1 on every save, Tier 2 on 'b')
  --watch --build start watch daemon with auto Tier 2 on every save
  --status        show VM status, iPhone connection, last build result
  --help          show this message
EOF
}

PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

tier1() {
  echo "=== Tier 1: analyze + test (host) ==="
  dart analyze --fatal-infos "$PROJECT_ROOT" && flutter test --no-pub "$PROJECT_ROOT"
}

status() {
  echo "=== CI Status ==="
  if [[ -f /tmp/osx-kvm.pid ]] && kill -0 "$(cat /tmp/osx-kvm.pid)" 2>/dev/null; then
    echo "VM: running (PID $(cat /tmp/osx-kvm.pid))"
    # SSH check
    ssh -o ConnectTimeout=3 mac-vm 'echo "SSH: ok"' 2>/dev/null || echo "SSH: unreachable (VM may be booting)"
    # iPhone check
    IPHONE=$(ssh -o ConnectTimeout=3 mac-vm 'flutter devices 2>/dev/null | grep ios' 2>/dev/null || true)
    [[ -n "$IPHONE" ]] && echo "iPhone: connected" || echo "iPhone: not detected"
  else
    echo "VM: stopped"
  fi
}

case "${1:-}" in
  --tier)
    case "${2:-}" in
      1) tier1 ;;
      2) bash "$SCRIPT_DIR/build-ios.sh" ;;
      3) bash "$SCRIPT_DIR/run-device.sh" ;;
      *) echo "Unknown tier: $2"; usage; exit 1 ;;
    esac ;;
  --watch)
    [[ "${2:-}" == "--build" ]] && bash "$SCRIPT_DIR/watch.sh" --build || bash "$SCRIPT_DIR/watch.sh" ;;
  --status) status ;;
  --help|"") usage ;;
  *) echo "Unknown command: $1"; usage; exit 1 ;;
esac
```

---

## Verification

```bash
bash -n scripts/infra/build-ios.sh  && echo build-ios SYNTAX_OK
bash -n scripts/infra/run-device.sh && echo run-device SYNTAX_OK
bash -n scripts/infra/ci.sh         && echo ci SYNTAX_OK

bash scripts/infra/ci.sh --help | grep -q tier && echo HELP_OK
bash scripts/infra/ci.sh --status
bash scripts/infra/ci.sh --tier 1   # runs locally, no VM needed
```
