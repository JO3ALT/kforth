# Repository Guidelines

## Project Structure & Module Organization
This repository contains a small C11 Forth implementation.
- `kforth.c`: VM, dictionary, primitives, interpreter loop.
- `kf_io.c` / `kf_io.h`: terminal I/O abstraction (`mf_key`, `mf_emit`).
- `bootstrap.fth`: Forth bootstrap script loaded at startup.
- `CMakeLists.txt`: build definition for the `kforth` executable.
- `build/` and `CMakeFiles/`: generated artifacts; do not edit manually.

Keep new runtime code in C files at the repo root unless a clear module split is introduced.

## Build, Test, and Development Commands
- Configure: `cmake -S . -B build`
  - Generates build files for the local toolchain.
- Build: `cmake --build build`
  - Compiles `build/kforth` with `-Wall -Wextra -O2`.
- Run bootstrap + REPL: `cat bootstrap.fth - | ./build/kforth`
  - Loads core words, then continues interactive input from stdin.
- Quick smoke run: `./build/kforth < bootstrap.fth`
  - Verifies bootstrap parses without immediate failure.

## Coding Style & Naming Conventions
- Language: C11 (`CMAKE_C_STANDARD 11`).
- Indentation: 2 spaces; no tabs.
- Braces: opening brace on the same line for functions/blocks.
- Naming:
  - Internal helpers: `snake_case` (`find_word_cstr`).
  - Primitive handlers: `p_UPPERCASE` style (`p_EXIT`, `p_LIT`).
  - Constants/macros: `UPPER_SNAKE_CASE`.
- Prefer small, single-purpose static functions and explicit bounds checks.

## Testing Guidelines
No formal test framework is currently configured. Use repeatable command-line smoke tests:
- Build cleanly with zero warnings.
- Run bootstrap flow (`cat bootstrap.fth - | ./build/kforth`) and validate `ok` prompt behavior.
- For bug fixes, add a minimal reproducible Forth snippet in the PR description (input + expected output/state).

## Commit & Pull Request Guidelines
Git history is not available in this workspace snapshot, so use a consistent convention:
- Commit messages: imperative mood, concise scope first (example: `vm: fix return stack underflow guard`).
- Keep commits focused (one logical change each).
- PRs should include:
  - What changed and why.
  - How to validate (exact commands run).
  - Behavioral impact on VM/interpreter semantics.
  - Related issue links, if any.
