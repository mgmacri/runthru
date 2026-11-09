#!/usr/bin/env bash
# RunThru release gate. Exit 0 means a TRIAGE row may be marked done.
#
#   scripts/verify_release_readiness.sh            # analyze + test + hygiene
#   scripts/verify_release_readiness.sh --quick    # skip flutter test
#
# Picks ~/.flutter-sdk/bin when present (the maintainer's host has a broken
# system Flutter); otherwise uses flutter/dart from PATH.
set -uo pipefail
cd "$(dirname "$0")/.."

if [ -z "${FLUTTER_BIN:-}" ]; then
  if [ -x "$HOME/.flutter-sdk/bin/flutter" ]; then FLUTTER_BIN="$HOME/.flutter-sdk/bin"; else FLUTTER_BIN="$(dirname "$(command -v flutter)")"; fi
fi
FLUTTER="$FLUTTER_BIN/flutter"; DART="$FLUTTER_BIN/dart"
QUICK=0; [ "${1:-}" = "--quick" ] && QUICK=1
FAIL=0
# Per-run temp files so parallel gates in swarm worktrees never overwrite each other.
ANALYZE_LOG="$(mktemp -t runthru_analyze.XXXXXX)"; TEST_LOG="$(mktemp -t runthru_test.XXXXXX)"
trap 'rm -f "$ANALYZE_LOG" "$TEST_LOG"' EXIT
ok()   { printf '  ok    %s\n' "$1"; }
bad()  { printf '  FAIL  %s\n' "$1"; FAIL=1; }

echo "RunThru gate — $("$FLUTTER" --version 2>/dev/null | head -1)"

echo "[1/6] dart analyze --fatal-infos"
if "$DART" analyze --fatal-infos >"$ANALYZE_LOG" 2>&1; then ok "0 issues"; else bad "analyzer"; tail -20 "$ANALYZE_LOG"; fi

echo "[2/6] flutter test"
if [ $QUICK -eq 1 ]; then echo "  skip  (--quick)"; else
  if "$FLUTTER" test >"$TEST_LOG" 2>&1; then ok "$(grep -oE '\+[0-9]+' "$TEST_LOG" | tail -1 | tr -d +) tests passed"; else bad "tests"; grep -E '\[E\]|Some tests failed' "$TEST_LOG" | sed 's/^[0-9:+ -]*//' | sort -u | head -20; fi
fi

echo "[3/6] no print/debugPrint outside logger"
if grep -rnE '\b(print|debugPrint)\(' lib --include='*.dart' | grep -v 'lib/core/logger.dart' | grep -q .; then bad "print() found"; grep -rnE '\b(print|debugPrint)\(' lib --include='*.dart' | grep -v 'lib/core/logger.dart' | head; else ok "clean"; fi

echo "[4/6] no hardcoded secrets"
if grep -rnEi '(consumer_key|consumer_secret|client_secret|api_key|apikey|access_token)[A-Za-z_]*\s*[:=]\s*["'"'"'][A-Za-z0-9_\-]{16,}["'"'"']' lib --include='*.dart' | grep -q .; then bad "secret-like literal"; grep -rnEi '(consumer_key|consumer_secret|client_secret|api_key|apikey|access_token)[A-Za-z_]*\s*[:=]\s*["'"'"'][A-Za-z0-9_\-]{16,}["'"'"']' lib --include='*.dart' | head; else ok "clean"; fi

echo "[5/6] no key material or secret files tracked"
TRACKED=$(git ls-files | grep -E '(\.p8|\.p12|\.jks|\.keystore|\.pem|android/key\.properties|dart_defines/[^/]*\.json)$' | grep -v '\.example\.json$' || true)
if [ -n "$TRACKED" ]; then bad "tracked secrets"; echo "$TRACKED"; else ok "clean"; fi

echo "[6/6] legacy name in product surfaces"
if grep -rniE 'speedy[ _-]?boy' lib pubspec.yaml android/app/src/main ios/Runner/Info.plist 2>/dev/null | grep -q .; then bad "'Speedy Boy' still present"; grep -rniE 'speedy[ _-]?boy' lib pubspec.yaml android/app/src/main ios/Runner/Info.plist 2>/dev/null | head; else ok "RunThru only"; fi

if [ $FAIL -eq 0 ]; then echo "GATE: PASS"; else echo "GATE: FAIL"; fi
exit $FAIL
