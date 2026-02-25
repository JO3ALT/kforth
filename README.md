# kforth

Japanese README: [README_JA.md](README_JA.md)

`kforth` is a small Forth implementation in C11 for **Linux hosts** and **Arduino-class microcontrollers**.

It provides the same core VM/interpreter (`kforth.c`) across both targets, with platform-specific I/O backends.

## Target Environments

- Linux/macOS (host build with CMake)
- Arduino environments via PlatformIO (ESP32, Arduino Due, Teensy 4.1)

## Features

- 32-bit cell Forth VM and dictionary
- Primitive words in C + bootstrap extensions in Forth (`bootstrap.fth`)
- Float32 words implemented in `bootstrap.fth` with raw IEEE754 `binary32` bit-patterns stored in one cell (`FADD`, `FSUB`, `FMUL`, `FDIV`, `S>F`, `F>S`, `Q16.16>F`, `F>Q16.16`, `F.`, `WRITE-F32`, `PWRITE-F32`, `FNUMBER?`, `READ-F32`, `PREAD-F32`)
- Bootstrap control-flow words (`IF`/`ELSE`/`THEN`, `BEGIN`/`UNTIL`/`AGAIN`, `WHILE`/`REPEAT`)
- Pascal-oriented helper words for output/memory/input (`PWRITE-*` incl. `PWRITE-HEX`, `PVAR*`/`PFIELD*`, `PNEXT`, `PREAD-*` incl. `PREADLN`)
- REPL flow based on `QUIT`
- Host and Arduino I/O abstraction layers
- Shell-based test scripts

## Linux Build and Run

```bash
cmake -S . -B build
cmake --build build
cat bootstrap.fth - | ./build/kforth
```

Bootstrap smoke check:

```bash
./build/kforth < bootstrap.fth
```

## Arduino Build (PlatformIO)

This repository includes PlatformIO settings to build the same core for Arduino targets.

```bash
pio run -e esp32dev
pio device monitor -b 115200
```

Other provided environments:

```bash
pio run -e due
pio run -e teensy41
```

## Tests (Host)

```bash
tests/run_tests.sh
tests/full_suite.sh
tests/raw_primitive_suite.sh
tests/float_bootstrap_suite.sh
```

Float bootstrap self-test from the REPL:

```bash
{ cat bootstrap.fth; printf 'FTEST-RUN\nBYE\n'; } | ./build/kforth
```

READ-F32 string-parse demo:

```bash
{ cat bootstrap.fth; cat samples/read_f32_demo.fth; } | ./build/kforth
```

## Float32 Bootstrap Notes

- Float values are stored as raw IEEE754 `binary32` bit patterns in a single 32-bit cell (no runtime type tag).
- The float implementation is written in `bootstrap.fth` only.
- Public words include `FADD`, `FSUB`, `FMUL`, `FDIV`, `FNEGATE`, `FABS`, `F=`, `F<`, `F<=`, `F0=`, `S>F`, `F>S`, `Q16.16>F`, `F>Q16.16`, `FHEX.`, `F.`, `WRITE-F32`, `PWRITE-F32`, `FNUMBER?`, `READ-F32`, `PREAD-F32`, `F+INF`, `F-INF`, `FNAN`, `FINF?`, `FNAN?`, `FFINITE?`.
- `F.` currently formats via `Q16.16` conversion with 4 fractional digits (truncate), so it is a convenient display helper, not a full-precision printer.
- Simplified NaN/Inf support is implemented: canonical quiet NaN (`FNAN`) and signed infinities (`F+INF`, `F-INF`) with basic propagation in `FADD`/`FSUB`/`FMUL`/`FDIV`.
- Comparisons follow simplified IEEE-like behavior for NaN (`F=`, `F<`, `F<=` return false when NaN is involved).
- `FNUMBER?` / `READ-F32` / `PREAD-F32` accept `inf`, `-inf`, and `nan` (case-insensitive).
- Subnormal values are still unsupported in finite arithmetic/conversion paths and may abort.
- Direct interpreter support for bare float literals (e.g. typing just `1.5`) is not added.
- Decimal float input is available via words: `S" 1.5" FNUMBER?` (string parse), `S" 1.5" READ-F32` (string parse to `f flag`), and `PREAD-F32 1.5` (consume next token).
- `FNUMBER?` / `READ-F32` / `PREAD-F32` also accept `e` / `E` exponent notation (examples: `1e3`, `1.25e-1`, `2.5E+1`).

## Word List Snapshot

Generate/update available words from the current `bootstrap.fth`:

```bash
printf 'WORDS CR BYE\n' | cat bootstrap.fth - | ./build/kforth \
  | tr -s '[:space:]' ' ' \
  | sed -E 's/^ *ok //; s/ *$//' \
  | tr ' ' '\n' \
  | sed '/^$/d' > AVAILABLE_WORDS.txt
```

## Repository Layout

- `kforth.c`: VM, dictionary, primitives, interpreter
- `bootstrap.fth`: bootstrap words and REPL extensions
- `kf_io.c`, `kf_io.h`: host terminal I/O
- `kf_dev.c`, `kf_dev.h`: host device I/O abstraction
- `src/main.cpp`: Arduino entry point
- `src/kf_io_arduino.cpp`: Arduino terminal I/O backend
- `src/kf_dev_arduino.cpp`: Arduino device I/O backend
- `AVAILABLE_WORDS.txt`: current WORD list snapshot

## Documentation Policy

Files under `docs/manuals/` are currently provisional drafts and are **not included** in the GitHub upload set for now.

## License

This project is licensed under the MIT License. See `LICENSE`.
