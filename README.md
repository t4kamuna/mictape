# mictape

日本語 | [English](README.en.md)

Mac のマイクの音を、コマンドラインから `.m4a` ファイルに録音するツールです。授業や会議のような長時間の録音を、手間なく確実に残すことを目的にしています。

- **落ちても残る。** 音声は fragmented MP4 として1秒ごとに書き出します。プロセスが強制終了しても、電池が切れても、直前の1秒までは再生できます。
- **好きな場所に、好きな名前で保存できる。** 保存先は glob で指定したフォルダの中から名前で選び（`mictape start physics 3`）、ファイル名はテンプレートで決めます。
- **裏で録音できる。** `start` / `stop` / `status` があるので、Raycast などのランチャーから操作できます。
- **録音中は Mac をスリープさせません**（アイドル時のスリープのみ）。
- **プライバシーに配慮しています。** 通信は一切せず、テレメトリもアカウントもありません。要求する権限はマイクだけです。

形式は AAC、48 kHz、モノラル、128 kbps です（90分で約 86 MB）。

Raycast 拡張は [`raycast/`](raycast/) にあります。

## 動作環境

- macOS 14 以降
- Swift 6（Xcode 16、または Command Line Tools だけでも可: `xcode-select --install`）

## Homebrew でのインストール

```sh
brew install t4kamuna/tap/mictape
```

インストール時にソースからビルドします。

## ソースからのインストール

```sh
git clone https://github.com/t4kamuna/mictape.git
cd mictape
swift build -c release
mkdir -p ~/.local/bin
install -m 755 .build/release/mictape ~/.local/bin/mictape
```

`~/.local/bin` が PATH に入っていなければ、シェルの設定（`~/.zshrc` など）に `export PATH="$HOME/.local/bin:$PATH"` を足してください。

初めて録音するときに、マイクへのアクセス許可を求められます。許可は `mictape` を実行したアプリ（ターミナルや Raycast）に付きます。

## 使い方

```sh
mictape test                    # 10秒録って入力レベルを確認する
mictape record                  # 前面で録音する。q か Ctrl+C で止める
mictape start physics 3         # 裏で録音する。保存先は "physics"、ラベルは "3"
mictape status
mictape stop
mictape devices                 # 入力機器の一覧
mictape destinations            # 設定した保存先の一覧
```

`start`、`stop`、`status`、`devices`、`destinations`、`test` は `--json` に対応しています。

録音中は蓋を閉じないでください。閉じると Mac がスリープし、録音はそこで止まります（それまでに録った分は残ります）。

## 設定

任意です。`~/.config/mictape/config.json`（`$XDG_CONFIG_HOME/mictape/config.json`、または `$MICTAPE_CONFIG` で指定したパス）に置きます。

```json
{
  "destinations": [
    { "path": "~/Recordings" },
    { "path": "~/Documents/Classes/[0-9]*-?*", "subdirectory": "audio" }
  ],
  "filename": "{label}-{date:yyyyMMdd}.m4a",
  "device": "MacBook Air Microphone"
}
```

- `destinations`: フォルダのパスか glob。glob に一致したフォルダがそれぞれ保存先になり、名前の一部（大文字小文字は区別しない）で選びます。`subdirectory` は一致したフォルダの下に付け足され、録音開始時に作られます。ワイルドカードを含まないパスは、まだ存在しなくてもそのまま使います。既定は `~/Recordings` です。
- `filename`: 使えるトークンは `{label}` と `{date:FORMAT}`（[日付の書式](https://unicode.org/reports/tr35/tr35-dates.html#Date_Field_Symbol_Table)）です。同じ名前のファイルがあれば `-2`、`-3` … を付けます。既定は `{date:yyyyMMdd-HHmmss}.m4a` です。
- `device`: 入力機器の名前（の一部）か、`mictape devices` で表示される ID。既定はシステムの入力機器です。

ファイルを直接編集する代わりに、コマンドでも変更できます（Raycast 拡張の Recording Settings もこれを使います）。設定ファイルがシンボリックリンクの場合は、リンク先のファイルを書き換えます。

```sh
mictape config add-destination "~/Documents/Classes/[0-9]*-?*" --subdirectory audio
mictape config remove-destination "~/Recordings"
mictape config set-filename "{label}-{date:yyyyMMdd}.m4a"
mictape config preview-filename "{label}-{date:yyyyMMdd}.m4a"   # 3-20261006.m4a のような例を表示
```

## ファイル

- 録音: 設定した保存先にだけ書き込みます。
- 状態: `~/Library/Application Support/mictape/`（録音中の情報と、裏で動く録音プロセスのログ）。

## ライセンス

MIT
