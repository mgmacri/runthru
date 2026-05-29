---
description: "Infra I1.3: rsync + inotifywait watch loop. Tier 1 (analyze/test) on Linux host; Tier 2 (build) in VM on demand. Produces scripts/infra/sync.sh and watch.sh."
mode: agent
---

# Infra Step I1.3 — Code Sync Pipeline

> **Milestone**: I1.3 | **Backlog**: `doc/infra-backlog.json`
> **Depends on**: I1.1 (SSH configured); I1.2 can run in parallel
> **Produces**: `scripts/infra/sync.sh`, `scripts/infra/watch.sh`

Load shared context first: [infra-osx-kvm-context](./../instructions/infra-osx-kvm-context.instructions.md)

---

## Task

### TI1.3.1.1 — scripts/infra/sync.sh

Write an incremental rsync script:

```bash
#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
VM_TARGET="mac-vm:~/runthru/"
START=$(date +%s)

rsync -avz --delete \
  --exclude='.dart_tool/' \
  --exclude='build/' \
  --exclude='.git/' \
  --exclude='.fvm/' \
  --exclude='ios/Pods/' \
  --exclude='ios/.symlinks/' \
  --exclude='android/.gradle/' \
  --exclude='android/build/' \
  "$PROJECT_ROOT/" "$VM_TARGET"

ELAPSED=$(( $(date +%s) - START ))
echo "Synced in ${ELAPSED}s"
```

Requirements:
- Exits non-zero if `ssh mac-vm echo ok` fails (VM not running) — print actionable error
- `--stats` flag: appends rsync `--stats` for verbose transfer summary
- Must create `~/runthru/` on VM if it does not exist (rsync does this by default)

### TI1.3.2.1 — scripts/infra/watch.sh

Write a file-watch daemon. Key design:

```bash
#!/usr/bin/env bash
set -euo pipefail

# Flags
BUILD_ON_CHANGE=false
while [[ $# -gt 0 ]]; do
  case $1 in
    --build) BUILD_ON_CHANGE=true ;;
    --help)  echo "Usage: watch.sh [--build]"; exit 0 ;;
  esac; shift
done

# Dependency check
command -v inotifywait || { echo "Install inotify-tools: sudo pacman -S inotify-tools"; exit 1; }
command -v dart        || { echo "Flutter/Dart not in PATH on host"; exit 1; }

PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "Watching $PROJECT_ROOT (Tier 1 on host; Tier 2 in VM with --build)"
echo "Press 'b' + Enter to trigger a VM build manually."

# Background: read single keypress 'b' to trigger manual build
manual_build() {
  while IFS= read -r line; do
    [[ "$line" == "b" ]] && trigger_build
  done
}
manual_build &
INPUT_PID=$!
trap 'kill $INPUT_PID 2>/dev/null; exit' INT TERM

trigger_build() {
  echo "--- Tier 2: syncing + building in VM ---"
  bash "$SCRIPT_DIR/build-ios.sh" && echo "BUILD PASS" || echo "BUILD FAIL"
}

# Watch loop with 1s debounce
while true; do
  inotifywait -r -q -e modify,create,delete \
    --exclude '(\.dart_tool|build|\.git|\.fvm|ios/Pods)' \
    "$PROJECT_ROOT/lib" "$PROJECT_ROOT/test" "$PROJECT_ROOT/pubspec.yaml" \
    2>/dev/null

  # Debounce: drain any rapid follow-up events
  sleep 1

  echo ""
  echo "=== $(date '+%H:%M:%S') — change detected ==="

  # Tier 1: analyze on host
  echo "--- Tier 1: dart analyze ---"
  if dart analyze --fatal-infos "$PROJECT_ROOT" 2>&1; then
    echo "ANALYZE PASS"
    # Tier 1: tests on host
    echo "--- Tier 1: flutter test ---"
    flutter test --no-pub "$PROJECT_ROOT" && echo "TEST PASS" || echo "TEST FAIL"
  else
    echo "ANALYZE FAIL — skipping tests"
  fi

  # Tier 2: VM build if --build flag
  if $BUILD_ON_CHANGE; then
    trigger_build
  fi
done
```

---

## Verification

```bash
bash -n scripts/infra/sync.sh  && echo sync SYNTAX_OK
bash -n scripts/infra/watch.sh && echo watch SYNTAX_OK

# Live sync test (VM must be running):
bash scripts/infra/sync.sh
ssh mac-vm 'ls ~/runthru/pubspec.yaml' && echo SYNC_PASS
```

Confirm incremental sync (second run) transfers near-zero bytes when no files changed.
