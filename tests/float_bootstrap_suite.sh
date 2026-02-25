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

run_with_bootstrap() {
  local payload="$1"
  local out_file="$2"
  local err_file="$3"
  { cat bootstrap.fth; printf "%s" "$payload"; } | ./build/kforth >"$out_file" 2>"$err_file"
}

expect_contains() {
  local label="$1"
  local payload="$2"
  local needle="$3"
  local out err
  out="$(mktemp)"
  err="$(mktemp)"
  run_with_bootstrap "$payload" "$out" "$err"
  if grep -Fq -- "$needle" "$out"; then
    echo "PASS: $label"
    pass_count=$((pass_count + 1))
  else
    echo "FAIL: $label"
    echo "  expected: $needle"
    echo "  --- stdout ---"
    cat "$out"
    echo "  --- stderr ---"
    cat "$err"
    fail_count=$((fail_count + 1))
  fi
  rm -f "$out" "$err"
}

build

expect_contains "bootstrap loads" "" "ok "
expect_contains "built-in float selftest" $'FTEST-RUN\nBYE\n' "FTEST PASS"
expect_contains "S>F 1.0 bits" $'1 S>F .\nBYE\n' "1065353216 "
expect_contains "FADD integer path" $'7 S>F 5 S>F FADD F>S .\nBYE\n' "12 "
expect_contains "FSUB integer path" $'7 S>F 5 S>F FSUB F>S .\nBYE\n' "2 "
expect_contains "FMUL q16.16" $'3 65536 * Q16.16>F 2 65536 * Q16.16>F FMUL F>Q16.16 .\nBYE\n' "393216 "
expect_contains "FDIV q16.16" $'3 65536 * Q16.16>F 2 65536 * Q16.16>F FDIV F>Q16.16 .\nBYE\n' "98304 "
expect_contains "float comparisons" $'1 S>F 2 S>F F< . 2 S>F 2 S>F F<= . 0 S>F 0 S>F F= .\nBYE\n' "-1 -1 -1 "
expect_contains "special constants and predicates" $'F+INF FINF? . F-INF FINF? . FNAN FNAN? .\nBYE\n' "-1 -1 -1 "
expect_contains "special constants hex bits" $'F+INF FHEX. F-INF FHEX. FNAN FHEX.\nBYE\n' "7F800000 FF800000 7FC00000 "
expect_contains "max finite bits and predicates" $'2139095039 FHEX. 2139095039 FFINITE? . 2139095039 FINF? . 2139095039 FNAN? .\nBYE\n' "7F7FFFFF -1 0 0 "
expect_contains "min normal bits and finite predicate" $'8388608 FHEX. 8388608 FFINITE? .\nBYE\n' "00800000 -1 "
expect_contains "subnormal bits are finite but unsupported in conversion" $'1 FHEX. 1 FFINITE? . 1 FNAN? . 1 FINF? .\nBYE\n' "00000001 -1 0 0 "
expect_contains "subnormal conversion reports error" $'1 F>S\n1 2 + .\nBYE\n' "float subnormal unsupported"
expect_contains "subnormal conversion recovers" $'1 F>S\n1 2 + .\nBYE\n' "3 "
expect_contains "NaN comparisons false" $'FNAN FNAN F= . FNAN 1 S>F F< .\nBYE\n' "0 0 "
expect_contains "FDIV zero and inf cases" $'1 S>F 0 S>F FDIV FINF? . 0 S>F 0 S>F FDIV FNAN? .\nBYE\n' "-1 -1 "
expect_contains "FADD/FMUL special propagation" $'F+INF F-INF FADD FNAN? . F+INF 0 S>F FMUL FNAN? .\nBYE\n' "-1 -1 "
expect_contains "F. special formatting" $'F+INF F. SPACE F-INF F. SPACE FNAN F.\nBYE\n' "inf -inf nan"
expect_contains "F. fixed decimal output" $'3 65536 * Q16.16>F 2 65536 * Q16.16>F FDIV F.\nBYE\n' "1.5000"
expect_contains "FROUND-I32 rounds half away from zero" $'2 65536 * Q16.16>F 32768 Q16.16>F FADD FROUND-I32 . -2 65536 * Q16.16>F 32768 Q16.16>F FSUB FROUND-I32 .\nBYE\n' "3 -3 "
expect_contains "WRITE-F32 alias" $'3 65536 * Q16.16>F WRITE-F32\nBYE\n' "3.0000"
expect_contains "PWRITE-F32 alias" $'5 65536 * Q16.16>F PWRITE-F32\nBYE\n' "5.0000"
expect_contains "FNUMBER? decimal string" $': TFNUM S" -12.25" FNUMBER? IF F. ELSE 999 . THEN ; TFNUM\nBYE\n' "-12.2500"
expect_contains "FNUMBER? exponent string" $': TFEXP S" 1.25e-1" FNUMBER? IF F. ELSE 999 . THEN ; TFEXP\nBYE\n' "0.1250"
expect_contains "FNUMBER? special strings" $': TFSPEC S" inf" FNUMBER? IF FINF? . THEN S" nan" FNUMBER? IF FNAN? . THEN ; TFSPEC\nBYE\n' "-1 -1 "
expect_contains "PREAD-F32 next token" $'PREAD-F32 0.125 F.\nBYE\n' "0.1250"
expect_contains "PREAD-F32 exponent token" $'PREAD-F32 2.5E+1 F.\nBYE\n' "25.0000"
expect_contains "PREAD-F32 special tokens" $'PREAD-F32 -inf FINF? . PREAD-F32 nan FNAN? .\nBYE\n' "-1 -1 "
expect_contains "READ-F32 string success" $': TRF32OK S" 1.25e-1" READ-F32 IF F. ELSE 999 . THEN ; TRF32OK\nBYE\n' "0.1250"
expect_contains "READ-F32 string failure" $': TRF32BAD S" xyz" READ-F32 IF 111 . ELSE 222 . THEN ; TRF32BAD\nBYE\n' "222 "

echo "Summary: PASS=$pass_count FAIL=$fail_count"
if [[ "$fail_count" -ne 0 ]]; then
  exit 1
fi
