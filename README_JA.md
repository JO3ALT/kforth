# kforth

English README: [README.md](README.md)

`kforth` は、**Linuxホスト環境** と **Arduino系マイコン環境** の両方を想定した、C11実装の小規模 FORTH 処理系です。

コアVM/インタプリタ（`kforth.c`）を共通で使い、I/O層だけを環境ごとに切り替える構成です。

## 対象環境

- Linux/macOS（CMakeでホストビルド）
- PlatformIO経由のArduino環境（ESP32 / Arduino Due / Teensy 4.1）

## 特徴

- 32bitセルのFORTH VMと辞書
- C実装プリミティブ + `bootstrap.fth` によるFORTH側拡張
- `bootstrap.fth` のみで実装した float32 ワード群（IEEE754 `binary32` のビット列を1セル保持。`FADD`, `FSUB`, `FMUL`, `FDIV`, `S>F`, `F>S`, `Q16.16>F`, `F>Q16.16`, `F.`, `WRITE-F32`, `PWRITE-F32`, `FNUMBER?`, `READ-F32`, `PREAD-F32`）
- bootstrap制御語（`IF`/`ELSE`/`THEN`, `BEGIN`/`UNTIL`/`AGAIN`, `WHILE`/`REPEAT`）
- Pascal向け補助語（出力/メモリ/入力: `PWRITE-*`（`PWRITE-HEX`含む）, `PVAR*`/`PFIELD*`, `PNEXT`, `PREAD-*`（`PREADLN`含む））
- `QUIT` ベースのREPL
- ホスト/ArduinoそれぞれのI/O抽象
- シェルベースのテストスクリプト

## Linuxでのビルドと実行

```bash
cmake -S . -B build
cmake --build build
cat bootstrap.fth - | ./build/kforth
```

bootstrap読込確認:

```bash
./build/kforth < bootstrap.fth
```

## Arduinoでのビルド（PlatformIO）

このリポジトリには、Arduino向けに同一コアをビルドするPlatformIO設定が含まれます。

```bash
pio run -e esp32dev
pio device monitor -b 115200
```

他の環境:

```bash
pio run -e due
pio run -e teensy41
```

## テスト（ホスト）

```bash
tests/run_tests.sh
tests/full_suite.sh
tests/raw_primitive_suite.sh
tests/float_bootstrap_suite.sh
```

REPL上の float self-test:

```bash
{ cat bootstrap.fth; printf 'FTEST-RUN\nBYE\n'; } | ./build/kforth
```

READ-F32 文字列パースのサンプル:

```bash
{ cat bootstrap.fth; cat samples/read_f32_demo.fth; } | ./build/kforth
```

## float32 bootstrap 実装メモ

- 浮動小数点値は IEEE754 `binary32` の生ビット列を 32bitセル1個に格納します（型タグなし）。
- 実装は `bootstrap.fth` のみで行っています。
- 公開ワード: `FADD`, `FSUB`, `FMUL`, `FDIV`, `FNEGATE`, `FABS`, `F=`, `F<`, `F<=`, `F0=`, `S>F`, `F>S`, `Q16.16>F`, `F>Q16.16`, `FHEX.`, `F.`, `WRITE-F32`, `PWRITE-F32`, `FNUMBER?`, `READ-F32`, `PREAD-F32`, `F+INF`, `F-INF`, `FNAN`, `FINF?`, `FNAN?`, `FFINITE?`。
- `F.` は現状 `Q16.16` へ変換して小数4桁（truncate）で表示する簡易表示です。完全精度の10進出力ではありません。
- 簡易的な NaN/Inf 対応を実装しています。`FNAN`（canonical quiet NaN）と `F+INF` / `F-INF` を持ち、`FADD` / `FSUB` / `FMUL` / `FDIV` で基本的な伝播を行います。
- 比較は簡易IEEE風の挙動で、NaN が絡む `F=` / `F<` / `F<=` は `FALSE` を返します。
- `FNUMBER?` / `READ-F32` / `PREAD-F32` は `inf`, `-inf`, `nan`（大文字小文字は区別しない）を受け付けます。
- 非正規化数は有限値の演算/変換経路では引き続き未対応で、`ABORT"` する場合があります。
- `1.5` のような裸の小数トークンをインタプリタが直接数値化する機能は未対応です。
- 10進入力はワード経由で可能です: `S" 1.5" FNUMBER?`（文字列パース）、`S" 1.5" READ-F32`（文字列から `f flag` へ変換）、または `PREAD-F32 1.5`（次トークン読取）。
- `FNUMBER?` / `READ-F32` / `PREAD-F32` は `e` / `E` 指数表記（例: `1e3`, `1.25e-1`, `2.5E+1`）にも対応します。

## WORD一覧スナップショット

現在の `bootstrap.fth` から利用可能ワード一覧を生成/更新:

```bash
printf 'WORDS CR BYE\n' | cat bootstrap.fth - | ./build/kforth \
  | tr -s '[:space:]' ' ' \
  | sed -E 's/^ *ok //; s/ *$//' \
  | tr ' ' '\n' \
  | sed '/^$/d' > AVAILABLE_WORDS.txt
```

## リポジトリ構成

- `kforth.c`: VM・辞書・プリミティブ・インタプリタ
- `bootstrap.fth`: bootstrap語・REPL拡張語
- `kf_io.c`, `kf_io.h`: ホスト側端末I/O
- `kf_dev.c`, `kf_dev.h`: ホスト側デバイスI/O抽象
- `src/main.cpp`: Arduinoエントリポイント
- `src/kf_io_arduino.cpp`: Arduino端末I/O
- `src/kf_dev_arduino.cpp`: ArduinoデバイスI/O
- `AVAILABLE_WORDS.txt`: 現在のWORD一覧スナップショット

## ドキュメント方針

`docs/manuals/` 以下のファイルは現時点で暫定ドラフトのため、当面 GitHub へのアップロード対象に含めません。

## ライセンス

このプロジェクトは MIT License で提供されます。`LICENSE` を参照してください。
