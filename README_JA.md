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
```

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
