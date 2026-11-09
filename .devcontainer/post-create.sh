#!/usr/bin/env bash
# Runs once after the container is created.
set -euo pipefail
cd /workspace

flutter --version
flutter pub get

# Keep an example dart-defines file so `flutter run --dart-define-from-file`
# works without secrets. Real values come from the host env or CI.
if [ ! -f dart_defines/development.json ]; then
  cp dart_defines/development.json.example dart_defines/development.json
  echo "dart_defines/development.json created from example (placeholder values)."
fi

chmod +x scripts/*.sh 2>/dev/null || true
echo "Ready. Gate: scripts/verify_release_readiness.sh   Swarm: scripts/swarm.sh --help"
