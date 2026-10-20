#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

[ $# -gt 0 ] || { echo "usage: tool/smoke.sh <device-id>..." >&2; exit 2; }

compose=(docker compose -f docker/compose.yaml)
"${compose[@]}" up -d --wait
trap '"${compose[@]}" down -v' EXIT

cd examples/flutter_smoke
flutter pub get
for device in "$@"; do
  flutter test integration_test -d "$device"
done
