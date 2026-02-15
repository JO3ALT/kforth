#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

RUN_STRINGS=0
if [[ "${1:-}" == "--strings" ]]; then
  RUN_STRINGS=1
fi

pass_count=0
fail_count=0

build() {
  cmake -S . -B build >/dev/null
  cmake --build build >/dev/null
}

run_with_bootstrap() {
  local payload="$1"
  local out_file="$2"
  local err_file="$3"
  { cat bootstrap.fth; printf "%s" "$payload"; } | ./build/kforth >"$out_file" 2>"$err_file"
}

assert_contains() {
  local file="$1"
  local needle="$2"
  local label="$3"
  if grep -Fq -- "$needle" "$file"; then
    echo "PASS: $label"
    pass_count=$((pass_count + 1))
  else
    echo "FAIL: $label"
    echo "  expected to find: $needle"
    echo "  in file: $file"
    fail_count=$((fail_count + 1))
  fi
}

core_suite() {
  local out err
  out="$(mktemp)"
  err="$(mktemp)"

  run_with_bootstrap "" "$out" "$err"
  assert_contains "$out" "ok " "bootstrap prints prompt"

  run_with_bootstrap $'1 2 + .\n' "$out" "$err"
  assert_contains "$out" "3 " "basic arithmetic"

  run_with_bootstrap $'2147483647 1 + .\n-2147483648 1 - .\n-2147483648 -1 * .\n' "$out" "$err"
  assert_contains "$out" "-2147483648 " "32-bit add wrap at max"
  assert_contains "$out" "2147483647 " "32-bit sub wrap at min"
  assert_contains "$out" "-2147483648 " "32-bit mul wrap at min*-1"

  run_with_bootstrap $'.\n1 2 + .\n' "$out" "$err"
  assert_contains "$out" "? data stack underflow" "underflow is reported"
  assert_contains "$out" "3 " "recovery continues after underflow"

  run_with_bootstrap $'bye\n1 2 + .\n' "$out" "$err"
  assert_contains "$out" "? bye" "lowercase bye is unknown"
  assert_contains "$out" "3 " "execution continues after unknown word"

  rm -f "$out" "$err"
}

string_suite() {
  local out err
  out="$(mktemp)"
  err="$(mktemp)"

  run_with_bootstrap $'S" HI" TYPE\n' "$out" "$err"
  assert_contains "$out" "HI" "S\" and TYPE"

  run_with_bootstrap $'.\" hello\"\n' "$out" "$err"
  assert_contains "$out" "hello" ".\" prints string"

  run_with_bootstrap $'0 ABORT" no"\n1 2 + .\n' "$out" "$err"
  assert_contains "$out" "3 " "ABORT\" false does not abort"

  run_with_bootstrap $'1 ABORT" stop"\n1 2 + .\n' "$out" "$err"
  assert_contains "$out" "stop" "ABORT\" true reports message"
  assert_contains "$out" "3 " "ABORT\" true recovers and continues"

  rm -f "$out" "$err"
}

build
core_suite

if [[ "$RUN_STRINGS" -eq 1 ]]; then
  string_suite
else
  echo "INFO: string suite skipped (run with --strings)"
fi

echo "Summary: PASS=$pass_count FAIL=$fail_count"
if [[ "$fail_count" -ne 0 ]]; then
  exit 1
fi
