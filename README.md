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
```

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
