# daily-reflection

Claude Code のセッションログから、その日の振り返り日報を作る Claude Code スキル集。

一日の終わりに `/daily-reflection` と打つと、その日どのプロジェクトで何をしていたかを
セッションログから再構成し、Google カレンダー・Slack・Git log で補強した日報を生成する。
稼働時間の記録（timesheet）も同時に出力し、工数管理システム向けのCSVに変換できる。

**特徴**

- **事実ベース** — ソースに無いことは書かない。推測で埋めず `_（言及なし）_` と明示する
- **チャンク確認** — 1〜2時間単位で「この時間帯はこうでしたよね？」と時系列に確認していく
- **記録が残る** — 意思決定・捨てた選択肢・その背景まで残すので、後から経緯を追える

## 動作要件

- [Claude Code](https://code.claude.com/)
- Python 3 / `jq`（セッションログ保存フックが使用）
- 任意: Google カレンダー・Slack の MCP 連携（日報の補強に使う。無くても動く）

## クイックスタート

```bash
git clone <このリポジトリのURL>
cd daily-reflection
./scripts/setup.sh
```

`setup.sh` が行うこと:

1. 前提コマンド（`jq` / `python3`）の確認
2. `~/.claude/skills/` に各スキルへのシンボリックリンクを作成
3. `config/config.jsonc` が無ければ `config.example.jsonc` からコピーし、**内容を検証**
   （JSON構文と、パス指定が `{REPO_ROOT}/...` / `~/...` / `/...` のいずれかであること）
4. `~/.claude/settings.json` の SessionEnd フックにこのリポジトリの絶対パスを登録

セットアップ後、`config/config.jsonc` を自分の値に編集する（[設定](#設定)を参照）。
最低限 `sources`（カレンダーID等）だけ設定すれば日報は書ける。

> **既存の設定への影響**
>
> `~/.claude/settings.json` の SessionEnd に**エントリを1つ追加する**だけで、
> 既にある他のフックは残る（同じイベントに複数のフックを登録でき、並列に実行される）。
> 他のイベント（PreToolUse 等）の設定にも触れない。
>
> ただし**このリポジトリ由来の古い登録は取り除く**（同じログが二重に書かれるため）。
> 対象は「旧配置 `~/.claude/hooks/session-end-log.sh`」と「このリポジトリの別クローンからの登録」の2つだけで、
> 無関係な同名スクリプトは消さない。
>
> 変更前に `~/.claude/backups/setup-<日時>/settings.json` へバックアップを取る。
> 既存のスキルディレクトリを置き換える場合も同様に退避する。
> 何度実行しても結果は同じ（冪等）。
>
> ⚠️ **SessionEnd フックは全体で 1.5 秒の実行予算を共有する**（`timeout` 指定で最大60秒まで拡張）。
> このフックは `timeout: 30` を指定しているが、他に重い SessionEnd フックがある環境では
> ログ保存が間に合わない可能性がある。ログが残らない場合はここを疑う。

> **フックの登録はグローバルに行われる。**
> 日報は案件をまたいで書くものなので、どのディレクトリで作業してもログが残る必要がある。
> プロジェクト側の `.claude/settings.json` に書くとそのプロジェクトを開いている時しか発火しない
> （[公式ドキュメント](https://code.claude.com/docs/en/hooks.md)）。
> グローバル領域に置かれるのは**リンクと settings.json の1行だけ**で、実体はすべてこのリポジトリにある。

### setup.sh を実行しない場合

このリポジトリを開いて Claude Code を起動すれば、`.claude/skills/` が自動で読まれるため
**スキル自体はそのまま使える**（`config/config.jsonc` は手動でコピーする）。

ただし SessionEnd フックが登録されないので**セッションログが残らない**。
ログは日報の一次情報なので、実運用するなら `setup.sh` の実行が必要。

## 使い方

日常の流れは **日報を書く → 月末にCSVへ変換** の2ステップ。
前段が稼働実績JSONを残し、後段がそれを読むので**順番は入れ替えられない**。

### 1日の終わりに: `/daily-reflection`

```
/daily-reflection
```

対象日は当日。過去日を書きたい場合は `/daily-reflection 先週の金曜日` のように日付を添える
（明文化された手順ではないので、対象日が合っているかは最初の確認で見ておく）。

進み方は**1〜2時間のチャンク単位**。全部を一括で見せるのではなく、時系列順に確認していく。
一括収集ではなくチャンクに割っているのは、コンテキスト圧縮による読み直しを防ぐためと、
確認を軽くするため。

終わると2つのファイルを保存する。

| ファイル | 保存先（デフォルト） | 中身 |
|---|---|---|
| 日報 | `outputs/report/YYYY/MM/YYYY-MM-DD.md` | 事実の記録。保存後は基本触らない |
| 稼働実績 | `outputs/timesheets/YYYY/MM/YYYY-MM-DD.json` | 工数入力用の申告値。機械可読JSON |

保存後、稼働実績JSONをテーブルに整形して画面に提示するので、**数字がおかしければその場で伝える**
（ファイルを直接編集するより早い）。

### 工数を登録するとき: `/yojitsu-csv`

```
/yojitsu-csv
```

稼働実績JSONを読み、`config.jsonc` の `export` 定義に従って工数管理CSVを生成する。

| 指定 | 例 | 動作 |
|---|---|---|
| 指定なし | `/yojitsu-csv` | 今日の分 |
| 日付 | `/yojitsu-csv 8/7` | その日の分 |
| 期間 | `/yojitsu-csv 8/1-8/10`、`/yojitsu-csv 今月` | 該当する全日の分 |

> ⚠️ 対象日の稼働実績JSONが無いと変換できない。先に `/daily-reflection` を実行しておくこと。

## 設定

`config/config.jsonc` に書く。顧客名や案件番号を含みうるため、実データは
`.gitignore` で除外される（テンプレートの `config.example.jsonc` のみコミットされる）。

主要な項目は3つで、役割が分かれている。

| 項目 | 何を決めるか | 使うスキル |
|---|---|---|
| `sources` | カレンダーID・SlackユーザーID・Gitのauthor | daily-reflection |
| `projects` | 作業ディレクトリ(cwd) → プロジェクト名 | daily-reflection |
| `work_codes` | 案件番号・作業コードの原簿 | 両方 |
| `export` | CSVの列構成と出力先 | yojitsu-csv |

工数管理を使わないなら `work_codes` と `export` は空でよい。日報だけなら `sources` で足りる。

### `projects` — どのディレクトリが何の活動か

セッションログには作業した `cwd` が記録される。この対応表があると、そのセッションが
どの活動だったかを推定できる。未登録の cwd は日報作成時に確認され、承認されると自動追記される。

```jsonc
"projects": {
  "~/work/acme-portal": "ACMEポータル刷新",
  "~/work/internal-tools": "社内ツール整備",
  "~/work/acme-infra": "ACMEポータル刷新"   // 複数ディレクトリ→同一プロジェクトも可
}
```

**キーは絶対パスか `~/...`。** `./` 始まりや裸の相対パスは、実行時の cwd によって
指す先が変わるため受け付けない。

1ディレクトリには1つの活動を対応させる。ただしこれは**推定の既定値**であって厳密な制約ではなく、
実際の作業内容が明らかに違えば日報作成時に個別に判断される。そのリポジトリに関係する作業
（開発環境の整備なども含む）は同じ活動として扱い、全く別の作業やグローバル設定の変更は
別の活動として切り分ける。

### `work_codes` — 案件と作業コードの原簿

工数管理システム側から与えられる情報。`work_name` は正式名称なので長くなりがちで、
日報の見出しには向かない。そこで `display_name` を別に持たせる。

```jsonc
{
  "case_number": "0000009901",
  "code": "P990000009901001",
  "work_name": "株式会社ACME_会員ポータル刷新（2026年4-9月）",  // CSV用（正式名称）
  "display_name": "ACMEポータル刷新",                          // 日報用
  "customer": "株式会社ACME"
}
```

日報では**見出しに `display_name`、その直下に `work_name` を引用で併記**する。

```markdown
## プロジェクト: ACMEポータル刷新
> 株式会社ACME_会員ポータル刷新（2026年4-9月）
```

見出しを短くするのは、タイムラインの表と frontmatter の `projects` に同じ文字列が入るため
（正式名称は40文字を超えることがあり、表が崩れる）。正式名称を併記するのは、CSVに出るのが
`work_name` なので日報とCSVを突合できるようにするため。

案件名には契約期間（`（2026年4-9月）` 等）が含まれることがあり、更新で変わりうる。
見出しを `display_name` で固定しておけば、期間が変わっても過去日報と同じ名前で追える。

`display_name` は任意だが、**設定しないと日によって表記が揺れる**（同じコードなのに
「ACMEポータル刷新」「ACME刷新」のように別名で記録されてしまう）。
全件に設定する必要はなく、実際に使うコードだけ埋めれば足りる
（未設定のコードは見出しにも `work_name` が使われ、併記は省略される）。

### 出力先パスの書き方

`output_dirs.*` と `export.output_path` は、先頭の書き方で基準が決まる。

| 書き方 | 基準 | 例 |
|---|---|---|
| `{REPO_ROOT}/...` | このリポジトリのルート | `{REPO_ROOT}/outputs/timesheets` |
| `~/...` | ホームディレクトリ | `~/Obsidian/daily-reports` |
| `/...` | 絶対パス | `/Volumes/Share/reports` |

**この3種類以外はエラーになる。** `./outputs/...` のような裸の相対パスは受け付けない。
`./` は一般に「実行時の cwd 基準」を意味するが、このスキルは cwd 基準では解決しない
（`setup.sh` 後は任意のディレクトリから実行されるため、cwd 基準にすると出力先が散らばる）。

黙って解決せずエラーにするのは、設定ミスを「出力先の事故」ではなく「実行時のエラー」として
気付けるようにするため。

デフォルトはリポジトリ内の `outputs/`（gitignore 対象）。Obsidian などの Vault を
指定することもできるが、**特定のノートアプリを前提にはしていない**。

## 出力されるデータの形式

扱うデータは4種類。**セッションログ**（フックが機械的に保存する一次情報）、
**日報**（人間が読む記録）、**稼働実績**（機械が読む申告値）、**CSV**（工数管理システム向け）。

| データ | 形式 | 保存先 | 生成するもの |
|---|---|---|---|
| セッションログ | JSONL | `~/.claude/daily-logs/YYYY-MM-DD/HH-MM-SS.jsonl` | SessionEnd フック |
| 日報 | Markdown | `{output_dirs.report}/YYYY/MM/YYYY-MM-DD.md` | `/daily-reflection` |
| 稼働実績 | JSON | `{output_dirs.timesheet}/YYYY/MM/YYYY-MM-DD.json` | `/daily-reflection` |
| 工数管理CSV | CSV | `export.output_path`（月次1ファイル） | `/yojitsu-csv` |

### セッションログ（JSONL）

セッション終了時にフックが `~/.claude/daily-logs/<セッション開始日>/<終了時刻>.jsonl` に保存する。
ディレクトリは**セッション開始日**、ファイル名は**エクスポート時刻**。

1行1エントリの JSONL。**1行目がセッションのメタ情報**、2行目以降が時系列のエントリ。

```jsonl
{"type": "session", "id": "bbf3f5ca-...", "cwd": "/Users/you/work/acme-portal", "started": "2026-08-13T12:58:39+09:00"}
{"ts": "2026-08-13T12:58:39+09:00", "role": "user", "text": "ダッシュボードにデータが表示されません"}
{"ts": "2026-08-13T12:58:41+09:00", "role": "assistant", "text": "設定を確認します。"}
{"ts": "2026-08-13T12:58:42+09:00", "role": "assistant", "tool": "Read", "target": "/Users/you/work/acme-portal/dashboard.tf"}
{"ts": "2026-08-13T13:02:10+09:00", "role": "assistant", "tool": "Bash", "target": "terraform plan"}
```

1行目（`type: "session"`）:

| フィールド | 内容 |
|---|---|
| `type` | 常に `"session"`（メタ行の識別子） |
| `id` | セッションID |
| `cwd` | セッションを実行していたディレクトリ。**どの案件の作業かの手がかり** |
| `started` | 最初のエントリの時刻（ISO 8601 / JST） |

2行目以降（発言 or ツール呼び出し）:

| フィールド | 内容 |
|---|---|
| `ts` | 発生時刻（ISO 8601 / JST）。全エントリに必ず入る |
| `role` | `user` または `assistant` |
| `text` | 発言本文。**最大1000文字**で、超過分は `...(truncated)` に切り詰められる |
| `tool` | ツール名（`Read` / `Bash` / `Grep` など）。ツール呼び出しの行のみ |
| `target` | ツールの対象。`file_path` → パス、`command` → コマンド（先頭100文字）、`pattern` → 検索パターン |

`text` と `tool` は排他（どちらか一方だけを持つ）。`target` は対象が取れないツールでは省略される。

抽出時に落としているもの:

- **ツールの実行結果**（`tool_result`）— 冗長なため記録しない。「何をしたか」は残るが「結果どうだったか」は残らない
- `<ide_opened_file>` / `<system-reminder>` で始まるシステム注入テキスト
- スラッシュコマンドのラッパー（`<command-args>` の中身＝ユーザーの実引数だけを残す）
- スキル起動時に注入される SKILL.md 全文

意味のある発言が1件も残らなかったセッションは、ファイル自体を作らない。

抽出ロジックは [hooks/extract-session.py](hooks/extract-session.py) にあり、単体でも実行できる:

```bash
python3 hooks/extract-session.py <transcript_path> <session_id> <cwd>
```

### 日報（Markdown）

frontmatter + セクション構成。frontmatter は後から機械的に集計・検索するために付けている。

```markdown
---
date: 2026-08-12
day: 水曜日
office: remote          # remote | office | hybrid | unknown
projects: [ACMEポータル刷新, 社内ツール整備]
meetings_count: 2
---

# 2026-08-12（水曜日）の日報

## タイムライン

| 時間 | プロジェクト | 内容 |
|------|------------|------|
| 09:30-10:00 | 社内ツール整備 | タスク整理 |
| 10:00-11:00 | 🔀 並行 | 週次定例 ／ 設計メモ作成 |

## 持ち越しTODO（前日分）
- API 設計レビューの依頼（**着手したが未完了**）

## プロジェクト: ACMEポータル刷新
> 株式会社ACME_会員ポータル刷新（2026年4-9月）

### 認証方式の見直し
- **やったこと**: OIDC への移行案を2パターン作成
- **決めたこと**: パターンAを本線に、Bは比較用に残す
- **捨てた選択肢**: _（言及なし）_
- **背景**: _（言及なし）_

### 明日やること
- パターンBのレビュー依頼（根拠: セッション中のTODO）

## 打ち合わせ
- 10:00-11:00 週次定例（参加者: _参加者要確認_）

## Slackでの注目やり取り
- _確認範囲では指摘なし_

## 総評
- **明日の予定**: 10:00-11:00 定例（それ以外は（カレンダー登録なし））
- **改善点**: ...

## 自由記述
> ここに感想・意気込み・雑感を自分で書く
```

構成上のポイント:

- **`_（言及なし）_` はバグではなく仕様**。ソースに無いことを推測で埋めない設計のため、
  埋まらない欄は明示的に「無い」と書く
- **`🔀 並行`** — 同じ時間帯に打ち合わせと作業が重なった場合、隠さず1行で両方書く
- **タイムラインの時刻は5分単位**に丸める
- **「自由記述」はスキルが埋めない**。人間が書くための空欄として残す

全セクションの定義は [format.md](.claude/skills/daily-reflection/format.md) を参照。

### 稼働実績（JSON）

工数管理システムと `/yojitsu-csv` が読むため JSON。
人間向けの確認は、保存後に画面上でテーブルに整形して提示することで行う。

```json
{
  "date": "2026-08-12",
  "day": "水曜日",
  "total_minutes": 450,
  "entries": [
    {
      "case_number": "0000009901",
      "customer": "株式会社ACME",
      "code": "P990000009901001",
      "work_name": "株式会社ACME_会員ポータル刷新（2026年4-9月）",
      "project": "ACMEポータル刷新",
      "minutes": 285,
      "breakdown": [
        { "activity": "認証方式の比較検討・設計メモ作成", "minutes": 135 },
        { "activity": "既存コード調査・移行方針の整理", "minutes": 150 }
      ]
    },
    {
      "case_number": "0000009902",
      "customer": "自社",
      "code": "P990000009902000",
      "work_name": "社内共通:ツール整備",
      "project": "社内ツール整備",
      "minutes": 165,
      "breakdown": [
        { "activity": "タスク整理", "minutes": 30 },
        { "activity": "週次定例", "minutes": 60 },
        { "activity": "CI設定の更新", "minutes": 75 }
      ]
    }
  ]
}
```

| フィールド | 内容 |
|---|---|
| `date` / `day` | 日報と同じ日付・曜日。**日報との突合はこの `date`（＝ファイル名）で行う** |
| `total_minutes` | その日の合計。分単位の整数 |
| `entries[]` | プロジェクト（≒作業コード）単位の行 |
| `entries[].case_number` / `code` / `work_name` / `customer` | `work_codes` から埋める |
| `entries[].project` | 日報上のプロジェクト名（`work_codes[].display_name`） |
| `entries[].minutes` | そのプロジェクトの稼働時間。分単位の整数 |
| `entries[].breakdown[]` | 内訳。`activity` と `minutes` のペア。**CSVはこの要素ごとに1行**になる |

時間は**すべて分単位の整数**（`"1h30m"` ではなく `90`）。計算と検証を機械的に行えるようにするため。

保存前に満たしている必要がある制約:

- `total_minutes` = 勤務終了 − 勤務開始 − 1h（固定昼休憩） − 追加休憩
- `entries[].minutes` の合計 = `total_minutes`
- `entries[].breakdown[].minutes` の合計 = その entry の `minutes`
- `entries[].minutes` と `breakdown[].minutes` は**15の倍数**（タイムラインは5分単位で構わない）

丸めの単位が2つあるのは、タイムラインは事実の記録なので細かく、
稼働実績は申告値なので15分刻みに揃える、という役割の違いから。

### 工数管理CSV

`/yojitsu-csv` が稼働実績JSONから生成する。列構成は固定ではなく
`export.columns` で定義する（下記はデフォルト設定での例）。

```csv
日付,プロジェクト番号,作業オーダ番号,作業名称,実績時間,備考
2026-08-12,09901,P990000009901001,株式会社ACME_会員ポータル刷新（2026年4-9月）,2.25,認証方式の比較検討・設計メモ作成(2.25)
2026-08-12,09901,P990000009901001,株式会社ACME_会員ポータル刷新（2026年4-9月）,2.50,既存コード調査・移行方針の整理(2.50)
2026-08-12,09902,P990000009902000,社内共通:ツール整備,0.50,タスク整理(0.50)
```

**`entries[].breakdown` の要素ごとに1行**。1つの案件で複数の活動をした日はその分だけ行が増える。

#### 列のカスタマイズ

**列の増減・順序・ヘッダ名はすべて `export.columns` で変えられる**（列構成はハードコードされていない）。
配列の並び順がそのままCSVの列順になり、`name` がヘッダ行に出る。

```jsonc
"columns": [
  { "name": "顧客名",  "source": "customer" },
  { "name": "日付",    "source": "date" },
  { "name": "コード",  "source": "code" },
  { "name": "工数",    "source": "minutes", "format": "decimal_hours2" }
]
```

`source` に指定できるのは**稼働実績JSONに存在するフィールド**のみ。

| 階層 | 使えるフィールド |
|---|---|
| 日単位 | `date` / `day` / `total_minutes` |
| `entries[]` | `case_number` / `customer` / `code` / `work_name` / `project` / `minutes` / `breakdown` |

`transform` / `format` は**あらかじめ決められた語彙のみ**を使う（任意の式は書けない）。

| 変換 | 指定 | 例 |
|---|---|---|
| 下5桁を取る | `transform: "last5"` | `0000009901` → `09901` |
| 作業名称の表記ルール適用 | `transform: "work_name_rule"` | `export.work_name_rules` の定義に従う |
| 分 → 小数時間（2桁） | `format: "decimal_hours2"` | `90` → `1.50`、`15` → `0.25` |
| 内訳の連結 | `format: "activity"` | `活動名(時間)` の形式 |

語彙を限定しているのは、CSVが工数管理システムへ登録するデータであり、
**毎回同じ結果になる再現性**が重要だから。テンプレート言語や自由記述を許すと解釈が揺れる。
語彙が足りない場合は `transform` / `format` にキーワードを追加して拡張する。

#### 出力先と追記の挙動

`export.output_path` は `{YYYY-MM}` 等のプレースホルダを対象日で展開する。
デフォルトは月次1ファイルへの**追記**（`on_existing: "append"`）なので、
日を分けて何度実行しても同じ月のCSVに積まれる（`overwrite` にすれば毎回上書き）。

同じ日付のデータが既にファイルに含まれている場合は、重複を防ぐため確認が入る。

## うまく動かないとき

### 特定のリポジトリだけセッションログが残らない

日報は残っているログから組み立てるので、**ログが無い時間帯は日報から丸ごと抜け落ちる**。
「特定の案件の作業だけ日報に出てこない」場合はこれを疑う。

まず、どの作業ディレクトリのログが記録されているかを確認する。

```bash
for f in ~/.claude/daily-logs/*/*.jsonl; do head -1 "$f" | jq -r .cwd; done | sort | uniq -c
```

目的のリポジトリが出てこない場合、原因は主に以下。

**1. プロジェクト側の Claude 設定が影響している**

`.claude/settings.json` を持つリポジトリでは、その設定が原因で
Claude Code の挙動が変わることがある（プラグイン、`model` 指定、権限モードなど）。

フック自体は設定ファイル間で**マージ**されるので、プロジェクト側に `SessionEnd` が
無くてもグローバルの登録は効くはず。それでも記録されない場合は、プロジェクト設定を
一時的に退避して切り分ける。

```bash
mv .claude/settings.json .claude/settings.json.bak   # 一時退避して再現するか確認
```

なお `.claude` ディレクトリごとリネームして無効化する運用をしている場合、
そのリポジトリでは**プロジェクト固有のスキルやフックも一切読まれない**点に注意
（グローバル側の設定は引き続き有効なので、セッションログ自体は残る）。

**2. フックがエラーで落ちている**

登録されているパスを確認し、手動で実行してみる。

```bash
# 登録されているフックのパスを確認
jq -r '.hooks.SessionEnd[].hooks[].command' ~/.claude/settings.json

# 直近の transcript を渡して手動実行（<repo> はこのリポジトリのパス）
TRANSCRIPT=$(ls -t ~/.claude/projects/*/*.jsonl | head -1)
echo "{\"transcript_path\":\"$TRANSCRIPT\",\"session_id\":\"test\",\"cwd\":\"$PWD\"}" \
  | <repo>/hooks/session-end-log.sh
```

成功すれば `~/.claude/daily-logs/` 配下にファイルができる。

`jq` / `python3` が見つからず失敗することがある。フックはログインシェルとは別の環境で
動くため、`.zshrc` などでしか PATH を通していないツールは解決されない。

**3. SessionEnd の実行予算を超えている**

SessionEnd フックは全体で 1.5 秒の予算を共有する（`timeout` 指定で最大60秒まで拡張）。
他に重い SessionEnd フックがあると、こちらの保存が間に合わないことがある。

```bash
jq '.hooks.SessionEnd' ~/.claude/settings.json   # 他に登録されているフックを確認
```

**4. 記録に値する発言が無かった**

意味のある発言が1件も無いセッションは、**ファイル自体が作られない**。
短い確認だけで終えたセッションが記録されないのはこのため（仕様）。

### 日報の一部が `_（言及なし）_` ばかりになる

不具合ではなく仕様。ソースに書かれていないことを推測で埋めない設計のため、
材料が無い欄はそう表示される（[設計上の原則](#設計上の原則)）。

意思決定の背景まで残したい場合は、セッション中に「なぜそうするか」を
会話に残しておくと日報に反映される。

### 出力先パスでエラーになる

`{REPO_ROOT}/...` / `~/...` / `/...` のいずれかで書く必要がある。
`./outputs/...` のような相対パスは受け付けない（[出力先パスの書き方](#出力先パスの書き方)）。

## 設計上の原則

このスキルの最重要原則は **事実ベースで書くこと**。

ソースに無いことは書かない。推測で埋めない。
`_（言及なし）_` と明示するか、書かないかの二択で、穴埋めはしない。

詳細は [SKILL.md](.claude/skills/daily-reflection/SKILL.md) を参照。

## リポジトリ構成

```
daily-reflection/
├── .claude/
│   └── skills/
│       ├── daily-reflection/              Claude Code が読む標準の場所
│       │   ├── SKILL.md                   手順（いつ何をするか）
│       │   └── format.md                  出力仕様（何をどう書くか）
│       └── yojitsu-csv/
│           └── SKILL.md                   稼働実績JSON→CSV変換の手順
├── config/
│   ├── config.example.jsonc               テンプレート（コミット対象）
│   └── config.jsonc                       実データ（gitignore）
├── hooks/
│   ├── session-end-log.sh                 セッション終了時にログを保存（呼び出し側）
│   └── extract-session.py                 transcriptからのログ抽出ロジック本体
├── scripts/
│   └── setup.sh                           他ディレクトリでも使えるようにする
└── outputs/                               デフォルト出力先（gitignore、実行時に自動作成）
    ├── report/YYYY/MM/YYYY-MM-DD.md
    ├── timesheets/YYYY/MM/YYYY-MM-DD.json
    └── exports/YYYY-MM/YYYY-MM.csv
```

セッションログだけはリポジトリ外（`~/.claude/daily-logs/`）に溜まる。
フックは全 cwd で発火するため、どのプロジェクトのログも1か所に集まる。

`config/` を両スキルの共有物としてリポジトリ直下に置いているのは、
設定を二重管理しないため。

スキルの実体を `.claude/skills/` に置いているのがポイントで、Claude Code は
プロジェクト直下の `.claude/skills/` を自動で読む。**このリポジトリを開いている間は
セットアップ無しでスキルが使える**（開発と実運用で場所が分かれない）。

### データフロー

```
[SessionEnd フック]  ※ 全プロジェクト横断で発火
   ~/.claude/daily-logs/YYYY-MM-DD/HH-MM-SS.jsonl
        ↓
[/daily-reflection]
   一次情報: セッションログ
   補強    : カレンダー / Slack / Git log / 前日の日報
        ↓
   日報（Markdown） + 稼働実績（JSON）
        ↓
[/yojitsu-csv]
        ↓
   工数管理CSV
```

## メンテナンス

| やりたいこと | 触る場所 |
|---|---|
| 日報の**手順**を変える（情報収集の順序、確認の粒度） | `.claude/skills/daily-reflection/SKILL.md` |
| 日報・稼働実績の**出力形式**を変える（セクション構成、JSONスキーマ） | `.claude/skills/daily-reflection/format.md` |
| **保存先**を変える | `config.jsonc` の `output_dirs`（[書き方](#出力先パスの書き方)） |
| プロジェクト名を追加・変更する | `config.jsonc` の `projects`（値は `work_codes[].display_name` と揃える） |
| 作業コードを追加する | `config.jsonc` の `work_codes` |
| **CSVの列構成・出力先**を変える | `config.jsonc` の `export` |
| ログの保存形式を変える | `hooks/session-end-log.sh` / `hooks/extract-session.py` |

編集はこのリポジトリ側で行う。シンボリックリンク経由なので**保存した瞬間に反映される**。
