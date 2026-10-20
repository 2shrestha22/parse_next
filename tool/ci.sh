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

step "generated code is current"
# freezed's output differs between the versions pub resolves on the lower
# bound and on stable; only stable's matches the committed files.
generated=(-name '*.parse.dart')
[ "${PUB_RESOLVE:-}" = "1" ] || generated+=(-o -name '*.freezed.dart')
generators=(packages/parse_next_it packages/parse_next packages/parse_next_generator)
sums() {
  find packages/parse_next_it/lib packages/parse_next/example packages/parse_next_generator/example \
    "${generated[@]}" | sort | xargs cksum
}
before=$(sums)
for dir in "${generators[@]}"; do
  (cd "$dir" && dart run build_runner build --delete-conflicting-outputs)
done
[ "$before" = "$(sums)" ] || fail "generated code is stale; run build_runner in ${generators[*]}"

step "G3 analyze"
dart analyze --fatal-infos

step "G4 format"
dart format --output=none --set-exit-if-changed .

step "G5 unit tests"
(cd packages/parse_next && dart test -p vm,chrome)
# The generator runs the analyzer, which needs dart:io.
(cd packages/parse_next_generator && dart test -p vm)

step "integration tests"
"${compose[@]}" down -v
trap '"${compose[@]}" down -v' EXIT
"${compose[@]}" up -d --wait
# live_test.dart restarts the servers, so the live files run one at a time,
# after the rest.
(cd packages/parse_next_it && dart test -p vm -x live && dart test -p vm -t live -j 1)

step "all gates passed"
