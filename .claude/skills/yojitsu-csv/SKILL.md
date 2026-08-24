---
name: yojitsu-csv
description: >-
  稼働実績JSON（daily-reflectionスキルが出力するJSON）を予実管理システム向けのCSVに変換する。
  「予実CSV」「工数CSV」「予実管理」「CSV生成」などの依頼時に使用する。
---
# 予実管理CSV生成スキル

稼働実績JSON（`daily-reflection` スキルが `{output_dirs.timesheet}/YYYY/MM/YYYY-MM-DD.json` に保存するデータ）を、
予実管理システムへ登録するCSVファイルに変換する。

## 設定ファイル

このスキルはリポジトリ直下の共有 `config/config.jsonc` を参照する
（`daily-reflection` スキルとの共有物であり、設定を二重管理しない）。

このスキル自身は2つの経路のいずれかから呼ばれる（実体は同じ）:

- **リポジトリを開いている場合**: `<リポジトリ>/.claude/skills/yojitsu-csv/`
- **他のディレクトリの場合**: `~/.claude/skills/yojitsu-csv/`（リポジトリへのシンボリックリンク）

スキルディレクトリの特定には `SKILL.md` の存在を使う。どちらから呼ばれても動くよう、**存在する方を使う**:

```bash
for d in ./.claude/skills/yojitsu-csv ~/.claude/skills/yojitsu-csv; do
  [ -f "$d/SKILL.md" ] && SKILL_DIR="$d" && break
done
SKILL_DIR_REAL="$(cd "$SKILL_DIR" && pwd -P)"
REPO_ROOT="$(cd "$SKILL_DIR_REAL/../../.." && pwd -P)"
cat "$REPO_ROOT/config/config.jsonc"
```

⚠️ `config.jsonc` は JSONC（コメント付きJSON）。`//` で始まる行はコメントなので、値として解釈しないこと。

以降このドキュメントで `{skill_dir}` と書いた箇所は、ここで解決したパスを指す。

`config.jsonc` から以下の値を取得して使用する:
- `output_dirs.timesheet`: 稼働実績JSONの保存先ディレクトリ
- `work_codes`: 案件番号・作業コード・作業名称・顧客名の一覧。CSV行の検証と作業名称の変換に使用する
- `export`: CSV出力の設定一式（下記「CSVフォーマット」参照）

### 出力先パス（`output_dirs.timesheet` / `export.output_path`）の解決ルール

`daily-reflection` の `SKILL.md` の「設定ファイル」節にある `resolve_output_dir()` と同じ考え方を使う。

- `{REPO_ROOT}` で始まる場合: このリポジトリのルート基準で解決する
- `~` で始まる場合: ホームディレクトリに展開する
- `/` で始まる絶対パスの場合: そのまま使う

**上記3種類以外の書き方はエラーにする**（`./` 始まりの裸の相対パスは受け付けない）。
リポジトリ内に出力したい場合は `{REPO_ROOT}/outputs/...` と明示的に書く。
**cwd基準では絶対に解決しない。**

`REPO_ROOT` は上の「設定ファイル」節で既に求めているので、ここでは再度求めない。

```bash
# プレースホルダはパターンとしても除去対象としても使うため変数に入れる
# （case のパターン中で '{REPO_ROOT}' をクォートすると展開されないため）
REPO_ROOT_PH='{REPO_ROOT}'

resolve_output_dir() {
  local raw="$1"
  case "$raw" in
    "$REPO_ROOT_PH"*) echo "$REPO_ROOT${raw#"$REPO_ROOT_PH"}" ;;  # リポジトリルート基準
    ~*)               eval echo "$raw" ;;                          # ホームディレクトリに展開
    /*)               echo "$raw" ;;                               # 絶対パスはそのまま
    *)
      echo "ERROR: 出力先パスは {REPO_ROOT}/... | ~/... | /... のいずれかで書く: $raw" >&2
      return 1
      ;;
  esac
}

# コマンド置換への代入は関数が return 1 しても失敗扱いにならないため、
# 空の出力先で処理を続けないよう明示的に止める。
TIMESHEET_DIR="$(resolve_output_dir "<config.output_dirs.timesheet>")" || exit 1
EXPORT_PATH="$(resolve_output_dir "<config.export.output_path>")" || exit 1
```

`export.output_path` も同じ `resolve_output_dir()` で解決する。デフォルトが
`{REPO_ROOT}/outputs/exports/...` とリポジトリ内を指すため、解決を通さないと
実行したディレクトリにCSVが散らばる。

Google Drive 等リポジトリ外へ出す設定にしている場合は `~` 始まりか絶対パスになるので、この解決を通しても影響はない。

> `{REPO_ROOT}` は**パス解決時に展開するプレースホルダ**で、`{YYYY-MM}` 等の日付プレースホルダとは展開の
> タイミングが違う。`{REPO_ROOT}` を先に解決し、その後に日付プレースホルダを対象日で展開する。

以降このドキュメントで `{output_dirs.timesheet}` と書いた箇所は `$TIMESHEET_DIR` を指す。

## CSVフォーマット

列構成は `config.jsonc` の `export.columns` に従う（ハードコードしない）。デフォルトの列構成:

```
日付,プロジェクト番号,作業オーダ番号,作業名称,実績時間,備考
```

| カラム | source | transform / format | 例 |
|--------|--------|---------------------|-----|
| 日付 | `date` | - | `2026-06-29` |
| プロジェクト番号 | `case_number` | `last5`（下5桁） | `09901`（元: `0000009901`） |
| 作業オーダ番号 | `code` | - | `P990000009901001` |
| 作業名称 | `work_name` | `work_name_rule` | `株式会社ACME_会員ポータル刷新（2026年4-9月）` |
| 実績時間 | `minutes` | `decimal_hours2`（小数時間・小数点以下2桁） | `1.00`、`0.25`、`3.75` |
| 備考 | `breakdown` | `activity`（`活動名(時間)` 連結） | `定例MTG(1h)` |

列定義・変換語彙の詳細は `config.jsonc` の `export` セクションのコメントを参照する（`config.example.jsonc` にも同じ語彙表がある）。

備考欄には活動名をそのまま書く。どの案件の活動かは同じ行のプロジェクト番号・作業オーダ番号・作業名称で判別できるため、
案件を示すプレフィックスは付けない。

### 備考フィールドの禁止文字

**備考フィールドにカンマ（`,`）を含めてはならない。** カンマはCSVの区切り文字として誤認識されフィールドがずれる
（これはCSVの一般的性質であり config 化しない）。

`breakdown[].activity` にカンマが含まれる場合は半角スペースに置換する:
- `,` → ` `
- 例: `日報作成(7/10, 7/13)` → `日報作成(7/10 7/13)`

### 作業名称の表記ルール（`work_name_rule`）

`config.jsonc` の `export.work_name_rules` を参照する。entry の `case_number` が一致するルールがあれば、
そのルールの `format` に従って `work_name` を変換する（`{customer}` は `work_codes[].customer`、
`{work_name_after_colon}` は `work_name` の最初の `:` 以降に展開される）。一致するルールが無ければ `work_name` をそのまま使う。

## 実行手順

### 1. 対象日の特定

引数から対象日を特定する。
- 日付指定: その日の稼働実績JSONを読む
- 期間指定（例: `6/1-6/29`, `今月`）: 該当する全日の稼働実績JSONを読む
- 指定なし: 今日の稼働実績JSONを読む

### 2. 稼働実績JSONの読み込み

```
{output_dirs.timesheet}/YYYY/MM/YYYY-MM-DD.json
```

各ファイルから `date` / `day` / `total_minutes` / `entries[]`（`case_number`, `customer`, `code`, `work_name`,
`project`, `minutes`, `breakdown[]`）を取得する。

### 3. CSV行の生成

**`entries[].breakdown` の各要素を1行にする。**

各 entry の `breakdown[]` を走査し、要素ごとに1行のCSVレコードを生成する:

1. `entries[].breakdown[]` の各要素（`activity`, `minutes`）を取り出す
2. `minutes` を `decimal_hours2` で小数時間に変換する（`90` → `1.50`、`15` → `0.25`）
3. **`breakdown[].minutes` の合計が entry の `minutes` と一致することを検証する**（daily-reflection側の整合性チェック済みのはずだが、念のため再検証する）。不一致ならユーザーに確認する
4. 作業名称は「作業名称の表記ルール」に従って変換する
5. 備考フィールドのカンマは半角スペースに置換する

### 4. 出力

CSVファイルを `$EXPORT_PATH`（`export.output_path` を上の解決ルールで解決したもの）に保存する
（`{YYYY}` `{MM}` `{YYYY-MM}` 等のプレースホルダを対象日で展開する）。

- ディレクトリが存在しない場合は `mkdir -p` で作成する
- `export.on_existing` が `append` の場合: 既存ファイルに追記する。ただし**同じ日付のデータが既に含まれている場合はユーザーに確認する**（重複防止）
- `export.on_existing` が `overwrite` の場合: 既存ファイルを上書きする
- 既存ファイルが無い場合はヘッダ行（`export.columns[].name` を順に並べたもの）から書き出す
- 文字コードは `export.encoding`（デフォルト `utf-8`）

### 5. 検証

出力前に以下を確認する:
- 各日の全CSV行の実績時間合計 = その日の稼働実績JSONの `total_minutes`（分から小数時間への変換を含めて一致すること）
- 各行の `case_number`（変換前の値）・`code` が `config.jsonc` の `work_codes` に存在すること
- 日付形式が `YYYY-MM-DD`

検証結果をユーザーに提示し、問題がなければ保存する。
