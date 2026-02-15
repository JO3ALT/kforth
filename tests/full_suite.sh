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
  local out err file
  out="$(mktemp)"
  err="$(mktemp)"
  run_with_bootstrap "$payload" "$out" "$err"
  if [[ "$stream" == "out" ]]; then
    file="$out"
  else
    file="$err"
  fi
  if grep -Fq -- "$needle" "$file"; then
    report_pass "$label"
  else
    report_fail "$label" "$out" "$err" "expected '$needle' in $stream"
  fi
  rm -f "$out" "$err"
}

expect_not_contains() {
  local label="$1"
  local payload="$2"
  local stream="$3"
  local needle="$4"
  local out err file
  out="$(mktemp)"
  err="$(mktemp)"
  run_with_bootstrap "$payload" "$out" "$err"
  if [[ "$stream" == "out" ]]; then
    file="$out"
  else
    file="$err"
  fi
  if grep -Fq -- "$needle" "$file"; then
    report_fail "$label" "$out" "$err" "did not expect '$needle' in $stream"
  else
    report_pass "$label"
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
  { cat bootstrap.fth; printf "%s" "$payload"; } | ./build/kforth >"$out" 2>"$err"
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

expect_bootstrap_words_present() {
  local label="$1"
  shift
  local out err words_blob w
  out="$(mktemp)"
  err="$(mktemp)"
  run_with_bootstrap $'WORDS\n' "$out" "$err"
  words_blob=" $(tr '\n' ' ' < "$out") "
  for w in "$@"; do
    if [[ "$words_blob" == *" $w "* ]]; then
      report_pass "$label: $w"
    else
      report_fail "$label: $w" "$out" "$err" "word '$w' not found in WORDS output"
    fi
  done
  rm -f "$out" "$err"
}

core_suite() {
  expect_contains "bootstrap prompt" $'' out "ok "

  expect_contains "add" $'1 2 + .\n' out "3 "
  expect_contains "sub" $'9 4 - .\n' out "5 "
  expect_contains "mul" $'6 7 * .\n' out "42 "
  expect_contains "/MOD" $'7 3 /MOD . .\n' out "2 1 "
  expect_contains "32bit add wrap max+1" $'2147483647 1 + .\n' out "-2147483648 "
  expect_contains "32bit sub wrap min-1" $'-2147483648 1 - .\n' out "2147483647 "
  expect_contains "32bit add cancel -1+1" $'-1 1 + .\n' out "0 "
  expect_contains "32bit mul wrap min*-1" $'-2147483648 -1 * .\n' out "-2147483648 "
  expect_contains "32bit /MOD min/1" $'-2147483648 1 /MOD . .\n' out "-2147483648 0 "
  expect_contains "32bit /MOD min/-1 wrap" $'-2147483648 -1 /MOD . .\n' out "-2147483648 0 "
  expect_contains "32bit /MOD -7/3" $'-7 3 /MOD . .\n' out "-2 -1 "
  expect_contains "32bit /MOD 7/-3" $'7 -3 /MOD . .\n' out "-2 1 "
  expect_contains "32bit /MOD -7/-3" $'-7 -3 /MOD . .\n' out "2 -1 "

  expect_contains "AND" $'6 3 AND .\n' out "2 "
  expect_contains "OR" $'6 3 OR .\n' out "7 "
  expect_contains "XOR" $'6 3 XOR .\n' out "5 "
  expect_contains "LSHIFT" $'3 2 LSHIFT .\n' out "12 "
  expect_contains "RSHIFT" $'12 2 RSHIFT .\n' out "3 "

  expect_contains "0=" $'0 0= .\n' out "-1 "
  expect_contains "0<" $'-1 0< .\n' out "-1 "

  expect_contains "DUP" $'11 DUP + .\n' out "22 "
  expect_contains "SWAP" $'1 2 SWAP . .\n' out "1 2 "
  expect_contains "OVER" $'5 9 OVER + . .\n' out "14 5 "
  expect_contains "return stack" $'10 >R R> .\n' out "10 "
  expect_contains "R@" $'10 >R R@ . R> .\n' out "10 10 "

  expect_contains "BEGIN UNTIL" $': CNT 3 BEGIN DUP . 1- DUP 0= UNTIL DROP ; CNT\n' out "3 2 1 "
  expect_contains "nested J" $': JTEST 0 3 0 DO 5 8 5 DO J + LOOP LOOP ; JTEST .\n' out "11 "
  expect_contains "+LOOP step" $': STEP2 0 10 0 DO I + 2 +LOOP ; STEP2 .\n' out "20 "
  expect_contains "+LOOP negative step" $': DOWN 0 0 10 DO I + -2 +LOOP ; DOWN .\n' out "30 "

  expect_contains "CREATE + @ !" $'CREATE T 0 , 123 T ! T @ .\n' out "123 "
  expect_contains "HERE @ !" $'HERE DUP 123 SWAP ! @ .\n' out "123 "
  expect_contains "HEREC CODE! CODE@" $'HEREC DUP 777 SWAP CODE! CODE@ .\n' out "777 "
  expect_contains "paren comment" $'( comment ) 4 5 + .\n' out "9 "
  expect_contains "WORDS contains BYE" $'WORDS\n' out "BYE"
  expect_contains "EMIT" $'65 EMIT\n' out "A"
  expect_contains "KEY" $': KTEST KEY . ;\nKTEST\nZ\n' out "90 "

  expect_contains "unknown word recovery" $'NOPE\n1 2 + .\n' out "? NOPE"
  expect_contains "unknown word continues" $'NOPE\n1 2 + .\n' out "3 "

  expect_contains "underflow recovery" $'.\n1 2 + .\n' out "? data stack underflow"
  expect_contains "underflow continues" $'.\n1 2 + .\n' out "3 "
  expect_contains "ABORT recovers" $'ABORT\n1 2 + .\n' out "3 "
  expect_contains "/MOD divide by zero recovery" $'10 0 /MOD\n1 2 + .\n' out "? /MOD divide by zero"
  expect_contains "/MOD divide by zero continues" $'10 0 /MOD\n1 2 + .\n' out "3 "

  expect_contains "BYE exits" $'BYE\n' out "ok "
  expect_not_contains "BYE no trailing eval" $'BYE\n1 2 + .\n' out "3 "
  expect_contains "lowercase bye rejected" $'bye\n' out "? bye"

  expect_contains "wrapper =" $'5 5 = .\n' out "-1 "
  expect_contains "wrapper <" $'3 7 < .\n' out "-1 "
  expect_contains "wrapper >" $'9 2 > .\n' out "-1 "
  expect_contains "wrapper <=" $'7 7 <= . 9 2 <= .\n' out "-1 0 "
  expect_contains "wrapper >=" $'7 7 >= . 2 9 >= .\n' out "-1 0 "
  expect_contains "wrapper /" $'7 3 / .\n' out "2 "
  expect_contains "wrapper MOD" $'7 3 MOD .\n' out "1 "
  expect_contains "WITHIN true" $'5 1 10 WITHIN .\n' out "-1 "
  expect_contains "/STRING + TYPE" $'S" HELLO" 2 /STRING TYPE\n' out "LLO"
  expect_contains "colon definition literal" $': INC 1+ ; 41 INC .\n' out "42 "
  expect_contains "IF THEN definition" $': ABS DUP 0< IF NEGATE THEN ; -5 ABS .\n' out "5 "
  expect_contains "DO LOOP + I" $': SUM10 0 11 1 DO I + LOOP ; SUM10 .\n' out "55 "

  expect_contains "ALLOT moves HERE" $'HERE DUP 3 ALLOT HERE SWAP - .\n' out "3 "
  expect_contains "C! C@" $'HERE 1 ALLOT DUP 65 SWAP C! C@ .\n' out "65 "
  expect_contains ",C stores to code" $'HEREC DUP >R 88 ,C R> CODE@ .\n' out "88 "

  expect_contains "DEPTH" $'DEPTH . 1 2 DEPTH .\n' out "0 2 "
  expect_contains ".S" $'1 2 .S\n' out "<2> 1 2 "

  expect_contains "tick + EXECUTE" $'1 2 \' + EXECUTE .\n' out "3 "
  expect_contains "FIND found" $': STAR 42 ; S" STAR" FIND . .\n' out "1 "
  expect_contains "FIND immediate flag" $': IMW 7 ; IMMEDIATE S" IMW" FIND . .\n' out "-1 "
  expect_contains "FIND missing" $'S" NOPE" FIND .\n' out "0 "
  expect_contains "['] + EXECUTE" $': STAR 42 ; : XTSTAR [\'] STAR ; XTSTAR EXECUTE .\n' out "42 "

  expect_contains "UNLOOP + EXIT" $': UTEST 0 5 0 DO I 2 = IF UNLOOP EXIT THEN 1 + LOOP ; UTEST .\n' out "2 "
  expect_contains "IMMEDIATE sees compile state" $': SSTATE STATE @ . ; IMMEDIATE : TST SSTATE ;\n' out "1 "

  expect_contains "BASE set/get" $'16 BASE ! BASE @ . 10 BASE ! BASE @ .\n' out "16 10 "
  expect_contains ">IN starts at 0" $'>IN @ .\n' out "0 "
  expect_contains "SOURCE length equals #TIB" $'SOURCE NIP #TIB @ = .\n' out "-1 "
  expect_contains "SOURCE addr equals TIB" $'SOURCE DROP TIB = .\n' out "-1 "
  expect_contains "REFILL in word" $': RTEST REFILL . ;\nRTEST\n123 DROP\n' out "1 "

  expect_contains ">NUMBER full parse" $'10 BASE ! 0 S" 123" >NUMBER NIP 0= . .\n' out "-1 123 "
  expect_contains ">NUMBER partial parse" $'10 BASE ! 0 S" 12X" >NUMBER NIP . .\n' out "1 12 "
  expect_contains ">NUMBER hex partial" $'16 BASE ! 0 S" FFZ" >NUMBER NIP . .\n10 BASE !\n' out "1 255 "
  expect_contains ">NUMBER base low fallback" $'1 BASE ! 0 S" 19" >NUMBER NIP 0= . .\n10 BASE !\n' out "-1 19 "
  expect_contains ">NUMBER base high fallback" $'37 BASE ! 0 S" 19" >NUMBER NIP 0= . .\n10 BASE !\n' out "-1 19 "
  expect_contains "NUMBER? 2147483647" $'S" 2147483647" NUMBER? . .\n' out "-1 2147483647 "
  expect_contains "NUMBER? 2147483648 wraps" $'S" 2147483648" NUMBER? . .\n' out "-1 -2147483648 "
  expect_contains "NUMBER? -2147483648" $'S" -2147483648" NUMBER? . .\n' out "-1 -2147483648 "
  expect_contains "NUMBER? -2147483649 wraps" $'S" -2147483649" NUMBER? . .\n' out "-1 2147483647 "
  expect_contains "LSHIFT 0" $'1 0 LSHIFT .\n' out "1 "
  expect_contains "LSHIFT 31" $'1 31 LSHIFT .\n' out "-2147483648 "
  expect_contains "RSHIFT 0" $'-1 0 RSHIFT .\n' out "-1 "
  expect_contains "RSHIFT 31" $'-1 31 RSHIFT .\n' out "1 "
  expect_contains "LSHIFT >= 32" $'1 32 LSHIFT .\n' out "0 "
  expect_contains "RSHIFT >= 32" $'-1 32 RSHIFT .\n' out "0 "
}

advanced_suite() {
  expect_contains "semicolon outside compile" $';\n1 2 + .\n' out "? ; outside"
  expect_contains "semicolon outside compile continues" $';\n1 2 + .\n' out "3 "
  expect_contains "bracktick outside compile" $'[\']\n1 2 + .\n' out "? ['] outside compile"
  expect_contains "bracktick outside compile continues" $'[\']\n1 2 + .\n' out "3 "
  expect_contains "POSTPONE outside compile" $'POSTPONE +\n1 2 + .\n' out "? POSTPONE outside compile"
  expect_contains "POSTPONE outside compile continues" $'POSTPONE +\n1 2 + .\n' out "3 "
  expect_contains "DOES> only during compile" $'DOES>\n1 2 + .\n' out "? DOES> only during compile"
  expect_contains "DOES> only during compile continues" $'DOES>\n1 2 + .\n' out "3 "
  expect_contains "colon needs name" $':' out "? : needs name"
  expect_contains "CREATE needs name" $'CREATE' out "? CREATE needs name"

  expect_contains "POSTPONE in immediate helper" \
    $': ADD2 POSTPONE 1+ POSTPONE 1+ ; IMMEDIATE\n: INC2 ADD2 ;\n40 INC2 .\n' out "42 "
  expect_contains "bracket eval in interpret state" $'[ 1 2 + ] .\n' out "3 "
  expect_contains "PARSE consumes rest of line" $': PTEST BL PARSE NIP . ;\nPTEST ABC\n' out "3 "
  expect_contains "PARSE skips repeated delimiter" $': P2 44 PARSE NIP . ;\nP2 ,,ABC\n' out "3 "
  expect_contains "PARSE delimiter absent" $': PEND 44 PARSE NIP . ;\nPEND ABC\n' out "3 "
  expect_contains "PARSE delimiter-only" $': PEMP 44 PARSE NIP . ;\nPEMP ,,\n' out "0 "
  expect_contains "DOES> created word runtime" $': MAKER CREATE , DOES> @ ;\n123 MAKER X\nX .\n' out "123 "
  expect_contains "DOES> multiple instances" $': MAKER CREATE , DOES> @ ;\n111 MAKER A\n222 MAKER B\nA . B .\n' out "111 222 "
}

internal_primitive_suite() {
  expect_contains "internal LIT cell in colon" \
    $'CREATE A 0 ,\nHEREC A ! : C1 123 ;\nA @ CODE@ \' LIT = .\n' out "-1 "
  expect_contains "internal EXIT cell in colon" \
    $'CREATE A 0 ,\nHEREC A ! : C1 123 ;\nA @ 2 + CODE@ 0= .\n' out "-1 "
  expect_contains "internal 0BRANCH cell" \
    $'CREATE B 0 ,\nHEREC B ! : C2 IF 1 THEN ;\nB @ CODE@ \' 0BRANCH = .\n' out "-1 "
  expect_contains "internal BRANCH cell" \
    $'CREATE C 0 ,\nHEREC C ! : C3 IF 1 ELSE 2 THEN ;\nC @ 4 + CODE@ \' BRANCH = .\n' out "-1 "
  expect_contains "internal (ABORT\") cell" \
    $'CREATE D 0 ,\nHEREC D ! : C4 1 ABORT" X" ;\nD @ 6 + CODE@ \' (ABORT") = .\n' out "-1 "
}

bootstrap_behavior_suite() {
  expect_contains "BL constant" $'BL .\n' out "32 "
  expect_contains "1+" $'41 1+ .\n' out "42 "
  expect_contains "1-" $'41 1- .\n' out "40 "
  expect_contains "NIP" $'1 2 NIP .\n' out "2 "
  expect_contains "TUCK" $'1 2 TUCK .S\n' out "<3> 2 1 2 "
  expect_contains "2DUP" $'7 8 2DUP .S\n' out "<4> 7 8 7 8 "
  expect_contains "-ROT" $'1 2 3 -ROT .S\n' out "<3> 3 1 2 "
  expect_contains "TRUE FALSE" $'TRUE . FALSE .\n' out "-1 0 "
  expect_contains "NEGATE" $'5 NEGATE .\n' out "-5 "
  expect_contains "CR output" $'1 . CR 2 .\n' out $'1 \n2 '
  expect_contains "SPACE output" $'65 EMIT SPACE 66 EMIT\n' out "A B"
  expect_contains "0>" $'5 0> . 0 0> .\n' out "-1 0 "
  expect_contains "(UNSIGNED) valid" $'S" 123" (UNSIGNED) . .\n' out "-1 123 "
  expect_contains "(UNSIGNED) invalid" $'S" 12X" (UNSIGNED) .\n' out "0 "
  expect_contains "NUMBER? positive" $'S" 123" NUMBER? . .\n' out "-1 123 "
  expect_contains "NUMBER? negative" $'S" -123" NUMBER? . .\n' out "-1 -123 "
  expect_contains "NUMBER? invalid" $'S" X" NUMBER? .\n' out "0 "
  expect_contains "NUMBER? empty" $'S" " NUMBER? .\n' out "0 "
  expect_contains "2DROP" $'1 2 2DROP DEPTH .\n' out "0 "
  expect_contains "CONSTANT" $'123 CONSTANT K K .\n' out "123 "
  expect_contains ">CS CS>" $'123 >CS CS> .\n' out "123 "
  expect_contains "PATCH" $'HEREC DUP >R 0 ,C 0 ,C R> PATCH CODE@ .\n' out "1 "
  expect_contains "AGAIN compile path" $': ATEST 123 EXIT BEGIN 1 AGAIN ; ATEST .\n' out "123 "
  expect_contains "WHILE REPEAT runtime" $'0 CSP ! : WREP 0 BEGIN DUP 3 < WHILE 1+ REPEAT ; WREP .\n' out "3 "
  expect_contains "LITERAL" $': LT [ 42 ] LITERAL ; LT .\n' out "42 "
  expect_contains "PARSE-NAME" $': PN PARSE-NAME NIP . ;\nPN ABC\n' out "3 "
  expect_contains "INTERPRET direct" $'INTERPRET\n' out "ok "
  expect_contains ".OK word" $'.OK\n' out "ok "
  expect_contains "QUIT word" $'QUIT\nBYE\n' out "ok "
}

bootstrap_presence_suite() {
  expect_bootstrap_words_present "bootstrap words" \
    "BL" "CONSTANT" "1+" "1-" "=" "NIP" "TUCK" "2DUP" "-ROT" "TRUE" "FALSE" "NEGATE" \
    "CR" "SPACE" "<" ">" "<=" ">=" "0>" "WITHIN" "/STRING" "TYPE" "2DROP" "/" "MOD" \
    "CSP" "CSTACK" ">CS" "CS>" "PATCH" "0BR," "BR," "IF" "THEN" "ELSE" \
    "BEGIN" "AGAIN" "UNTIL" "WHILE" "REPEAT" "LITERAL" "PARSE-NAME" \
    "(UNSIGNED)" "NUMBER?" "INTERPRET" ".OK" "QUIT"
}

fatal_suite() {
  expect_fatal_contains "@ bad address" $'-1 @\n' out "? @ bad -1"
  expect_fatal_contains "! bad address" $'0 -1 !\n' out "? ! bad -1"
  expect_fatal_contains "C@ bad address" $'-1 C@\n' out "? C@ bad -1"
  expect_fatal_contains "C! bad address" $'0 -1 C!\n' out "? C! bad -1"
  expect_fatal_contains "CODE@ bad address" $'-1 CODE@\n' out "? CODE@ bad -1"
  expect_fatal_contains "CODE! bad address" $'0 -1 CODE!\n' out "? CODE! bad -1"
  expect_fatal_contains "ALLOT negative" $'-1 ALLOT\n' out "? ALLOT neg"
  expect_fatal_contains "EXECUTE bad xt" $'9999 EXECUTE\n' out "? EXECUTE bad xt"
  expect_fatal_contains "R@ underflow fatal" $'R@\n' out "? R@ underflow"
  expect_fatal_contains "I underflow fatal" $'I\n' out "? I RS underflow"
  expect_fatal_contains "J underflow fatal" $'J\n' out "? J needs nested DO"
  expect_fatal_contains "UNLOOP underflow fatal" $'UNLOOP\n' out "? UNLOOP RS underflow"
  expect_fatal_contains "(ABORT\") bad len fatal" $'1 0 -1 (ABORT")\n' out "? ABORT\" bad len"
}

string_suite() {
  expect_contains "S\" TYPE" $'S" HI" TYPE\n' out "HI"
  expect_contains ".\"" $'.\" hello\"\n' out "hello"
  expect_contains "ABORT\" false continues" $'0 ABORT" no"\n1 2 + .\n' out "3 "
  expect_contains "ABORT\" true message" $'1 ABORT" stop"\n' out "stop"
  expect_contains "KEY sequence" $': K2 KEY . KEY . ;\nK2\nAB\n' out "65 66 "
  expect_contains "KEY EOF returns 0" $': KEOF KEY . ;\nKEOF\n' out "0 "
}

build
core_suite
advanced_suite
internal_primitive_suite
bootstrap_behavior_suite
bootstrap_presence_suite
fatal_suite

if [[ "$RUN_STRINGS" -eq 1 ]]; then
  string_suite
else
  echo "INFO: string suite skipped (run with --strings)"
fi

echo "Summary: PASS=$pass_count FAIL=$fail_count"
if [[ "$fail_count" -ne 0 ]]; then
  exit 1
fi
