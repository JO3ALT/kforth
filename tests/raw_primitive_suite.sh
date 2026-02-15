#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

pass_count=0
fail_count=0

build() {
  cmake -S . -B build >/dev/null
  cmake --build build >/dev/null
}

run_raw() {
  local payload="$1"
  local out_file="$2"
  local err_file="$3"
  printf "%s" "$payload" | ./build/kforth >"$out_file" 2>"$err_file"
}

report_pass() {
  local label="$1"
  echo "PASS: $label"
  pass_count=$((pass_count + 1))
}

report_fail() {
  local label="$1"
  local out_file="$2"
  local err_file="$3"
  local note="$4"
  echo "FAIL: $label"
  echo "  $note"
  echo "  --- stdout ---"
  cat "$out_file"
  echo "  --- stderr ---"
  cat "$err_file"
  fail_count=$((fail_count + 1))
}

expect_contains() {
  local label="$1"
  local payload="$2"
  local stream="$3"
  local needle="$4"
  local out err file status
  out="$(mktemp)"
  err="$(mktemp)"
  set +e
  run_raw "$payload" "$out" "$err"
  status=$?
  set -e
  if [[ "$stream" == "out" ]]; then
    file="$out"
  else
    file="$err"
  fi
  if [[ "$status" -ne 0 ]]; then
    report_fail "$label" "$out" "$err" "expected zero exit status, got $status"
  elif grep -Fq -- "$needle" "$file"; then
    report_pass "$label"
  else
    report_fail "$label" "$out" "$err" "expected '$needle' in $stream"
  fi
  rm -f "$out" "$err"
}

expect_fatal_contains() {
  local label="$1"
  local payload="$2"
  local stream="$3"
  local needle="$4"
  local out err file status
  out="$(mktemp)"
  err="$(mktemp)"
  set +e
  run_raw "$payload" "$out" "$err"
  status=$?
  set -e
  if [[ "$stream" == "out" ]]; then
    file="$out"
  else
    file="$err"
  fi
  if [[ "$status" -eq 0 ]]; then
    report_fail "$label" "$out" "$err" "expected non-zero exit status"
  elif grep -Fq -- "$needle" "$file"; then
    report_pass "$label"
  else
    report_fail "$label" "$out" "$err" "expected '$needle' in $stream"
  fi
  rm -f "$out" "$err"
}

raw_suite() {
  expect_contains "raw arithmetic works" $'1 2 + .\n' out "3 "
  expect_contains "raw unknown word recovery" $'NOPE\n1 2 + .\n' out "? NOPE"
  expect_contains "raw unknown word continues" $'NOPE\n1 2 + .\n' out "3 "

  expect_fatal_contains "TYPE bad len fatal" $'0 -1 TYPE\n' out "? TYPE bad len"

  expect_contains "unterminated string" $'S\" ABC\n' out "? unterminated string"

  local long
  long="$(printf 'A%.0s' $(seq 1 1100))"
  expect_contains "string too long" "S\" ${long}\""$'\n' out "? string too long"
}

build
raw_suite

echo "Summary: PASS=$pass_count FAIL=$fail_count"
if [[ "$fail_count" -ne 0 ]]; then
  exit 1
fi
