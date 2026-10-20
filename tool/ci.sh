#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

compose=(docker compose -f docker/compose.yaml)

step() { printf '\n== %s\n' "$*"; }
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

# grep exits 1 for "no match" and 2 for an error; only 1 means the gate passed.
no_match() {
  local status=0
  grep "$@" || status=$?
  [ "$status" -eq 1 ]
}

# pubspec.lock is resolved on current stable and needs a newer SDK than the
# lower bound, so only the lower-bound job may re-resolve.
if [ "${PUB_RESOLVE:-}" = "1" ]; then
  dart pub get
else
  dart pub get --enforce-lockfile
fi

step "G1 dependency allowlist"
deps=$(awk '/^dependencies:/ {in_deps=1; next} /^[^ #]/ {in_deps=0}
  in_deps && /^  [a-z0-9_]+:/ {sub(":.*", ""); sub("^ +", ""); print}' \
  packages/parse_next/pubspec.yaml)
for dep in $deps; do
  case "$dep" in
    http | web_socket_channel) ;;
    *) fail "parse_next depends on '$dep'" ;;
  esac
done

step "G2 no dynamic in lib/"
no_match -rnw --include='*.dart' dynamic packages/*/lib || fail "dynamic found in lib/"

step "G9 no skip without a reason"
no_match -rnE 'skip:[[:space:]]*true|@Skip\([[:space:]]*\)' packages/*/test ||
  fail "skip without a reason string"

step "embedded fixtures are current"
dart run packages/parse_next/tool/embed_fixtures.dart --check

step "G3 analyze"
dart analyze --fatal-infos

step "G4 format"
dart format --output=none --set-exit-if-changed .

step "G5 unit tests"
for pkg in packages/parse_next packages/parse_next_generator; do
  [ -d "$pkg/test" ] || continue
  (cd "$pkg" && dart test -p vm,chrome)
done

step "integration tests"
"${compose[@]}" down -v
trap '"${compose[@]}" down -v' EXIT
"${compose[@]}" up -d --wait
(cd packages/parse_next_it && dart test -p vm)

step "all gates passed"
