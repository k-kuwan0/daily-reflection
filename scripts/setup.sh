#!/bin/bash
# daily-reflection / yojitsu-csv セットアップ
#
# このリポジトリを開いている間は .claude/skills/ が自動で読まれるため、
# セットアップ無しで /daily-reflection や /yojitsu-csv が使える。
# このスクリプトが行うのは「他のディレクトリでも使えるようにする」ことだけ。
#
#   1. ~/.claude/skills/daily-reflection, ~/.claude/skills/yojitsu-csv
#      → リポジトリの .claude/skills/... へのリンク
#   2. ~/.claude/settings.json の SessionEnd フックにこのリポジトリの絶対パスを登録
#   3. config/config.jsonc が無ければ config.example.jsonc からコピー
#
# 既存のファイル・設定は ~/.claude/backups/ に退避してから置き換える。
# 何度実行しても同じ結果になる（冪等）。
#
# settings.json への影響:
#   SessionEnd に「エントリを1つ追加する」だけで、他のフックや他イベントの設定は残す。
#   同じイベントに複数のフックを登録でき、並列に実行されるため共存できる。
#   このリポジトリ由来の古い登録（旧配置・別クローン）のみ、二重実行を避けるため取り除く。

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLAUDE_DIR="$HOME/.claude"
SKILLS_DIR="$CLAUDE_DIR/skills"
SETTINGS="$CLAUDE_DIR/settings.json"
HOOK_PATH="$REPO_ROOT/hooks/session-end-log.sh"
LINK_PATH="$SKILLS_DIR/daily-reflection"
# スキルの実体。Claude Code の標準の場所（.claude/skills/）に置く。
SKILL_SRC="$REPO_ROOT/.claude/skills/daily-reflection"
# config は daily-reflection / yojitsu-csv 両スキルから共有されるため、リポジトリ直下に置く。
CONFIG_DIR="$REPO_ROOT/config"
# 予実管理CSV生成スキル。daily-reflection の config.jsonc を共有する。
YOJITSU_LINK_PATH="$SKILLS_DIR/yojitsu-csv"
YOJITSU_SKILL_SRC="$REPO_ROOT/.claude/skills/yojitsu-csv"
BACKUP_DIR="$CLAUDE_DIR/backups/setup-$(date +%Y%m%d-%H%M%S)"

ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; }
info() { printf '  \033[34m·\033[0m %s\n' "$1"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$1"; }
die()  { printf '  \033[31m✗\033[0m %s\n' "$1" >&2; exit 1; }

echo
echo "daily-reflection セットアップ"
echo "  リポジトリ: $REPO_ROOT"
echo

# ---------------------------------------------------------------
# 事前チェック
# ---------------------------------------------------------------
echo "[1/4] 前提コマンドの確認"

command -v jq >/dev/null 2>&1 || die "jq が必要です。'brew install jq' でインストールしてください"
ok "jq"
command -v python3 >/dev/null 2>&1 || die "python3 が必要です（フックのログ整形に使用）"
ok "python3"
[ -f "$HOOK_PATH" ] || die "フックが見つかりません: $HOOK_PATH"
ok "フックスクリプト"
echo

# ---------------------------------------------------------------
# シンボリックリンク
# ---------------------------------------------------------------
echo "[2/4] スキルのリンク"

mkdir -p "$SKILLS_DIR"

# $1: リンク先パス（~/.claude/skills/<name>）  $2: リポジトリ内の実体パス  $3: バックアップ時のファイル名
link_skill() {
  local link_path="$1" skill_src="$2" backup_name="$3"

  if [ -L "$link_path" ]; then
    local current
    current="$(readlink "$link_path")"
    if [ "$current" = "$skill_src" ]; then
      ok "リンク済み（変更なし）: $link_path"
    else
      info "既存リンクの向き先を変更: $current"
      rm "$link_path"
      ln -s "$skill_src" "$link_path"
      ok "リンクを張り替えました: $link_path"
    fi
  elif [ -e "$link_path" ]; then
    # 実ディレクトリが存在する = 移行前の状態。退避してからリンクに置き換える
    mkdir -p "$BACKUP_DIR"
    mv "$link_path" "$BACKUP_DIR/$backup_name"
    warn "既存の実ディレクトリを退避: $BACKUP_DIR/$backup_name"
    ln -s "$skill_src" "$link_path"
    ok "リンクを作成しました: $link_path"
  else
    ln -s "$skill_src" "$link_path"
    ok "リンクを作成しました: $link_path"
  fi
}

link_skill "$LINK_PATH" "$SKILL_SRC" "skills-daily-reflection"
link_skill "$YOJITSU_LINK_PATH" "$YOJITSU_SKILL_SRC" "skills-yojitsu-csv"
echo

# ---------------------------------------------------------------
# config
# ---------------------------------------------------------------
echo "[3/4] 設定ファイル"

NEEDS_EDIT=0
target="$CONFIG_DIR/config.jsonc"
sample="$CONFIG_DIR/config.example.jsonc"
if [ -f "$target" ]; then
  ok "config.jsonc（既存を維持）"
elif [ -f "$sample" ]; then
  cp "$sample" "$target"
  warn "config.jsonc を雛形から作成しました → 実際の値に編集してください"
  NEEDS_EDIT=1
else
  die "雛形が見つかりません: $sample"
fi

# config.jsonc の構文検証（JSONC = // 行コメント付きJSON）。
# 文字列リテラル内の // (URL等) を誤って除去しないよう、python3側で
# 文字列を考慮したコメント除去を行ってから json.loads する。
(
python3 - "$target" <<'PYEOF'
import json, sys

def strip_jsonc_comments(text):
    result = []
    in_string = False
    escape = False
    i = 0
    n = len(text)
    while i < n:
        c = text[i]
        if in_string:
            result.append(c)
            if escape:
                escape = False
            elif c == '\\':
                escape = True
            elif c == '"':
                in_string = False
            i += 1
            continue
        if c == '"':
            in_string = True
            result.append(c)
            i += 1
            continue
        if c == '/' and i + 1 < n and text[i + 1] == '/':
            while i < n and text[i] != '\n':
                i += 1
            continue
        result.append(c)
        i += 1
    return ''.join(result)

with open(sys.argv[1], encoding='utf-8') as f:
    text = f.read()
try:
    cfg = json.loads(strip_jsonc_comments(text))
except json.JSONDecodeError as e:
    print(f"設定ファイルのJSON構文エラー: {sys.argv[1]}: {e}", file=sys.stderr)
    sys.exit(1)

# パス記法の検証。
# スキル側は {REPO_ROOT}/... | ~/... | /... の3種類しか解決しない。
# それ以外（"./..." 等の裸の相対パス）は実行時にエラーになるため、
# 日報を書き始めてから気付くのではなくセットアップ時点で弾く。
def bad_path(v):
    return not (isinstance(v, str) and
                (v.startswith('{REPO_ROOT}') or v.startswith('~') or v.startswith('/')))

errors = []
for key, val in (cfg.get('output_dirs') or {}).items():
    if bad_path(val):
        errors.append(f'  output_dirs.{key}: "{val}"')

export_path = (cfg.get('export') or {}).get('output_path')
if export_path is not None and bad_path(export_path):
    errors.append(f'  export.output_path: "{export_path}"')

# projects のキーは cwd と突き合わせるため絶対パスか ~ 始まりである必要がある
for key in (cfg.get('projects') or {}):
    if not (key.startswith('~') or key.startswith('/')):
        errors.append(f'  projects のキー: "{key}"（絶対パスか ~/... で書く）')

if errors:
    print('設定ファイルのパス指定が不正です:', file=sys.stderr)
    print('\n'.join(errors), file=sys.stderr)
    print('', file=sys.stderr)
    print('  パスは {REPO_ROOT}/... | ~/... | /... のいずれかで書いてください。', file=sys.stderr)
    print('  「./」始まりの相対パスは、実行するディレクトリによって指す先が変わるため使えません。', file=sys.stderr)
    sys.exit(1)
PYEOF
) || die "config.jsonc を修正してください: $target"
ok "config.jsonc の検証（構文・パス記法）"
echo

# ---------------------------------------------------------------
# SessionEnd フックの登録
# ---------------------------------------------------------------
echo "[4/4] SessionEnd フックの登録"

# フックは全 cwd で発火させる必要があるため、必ずグローバル settings.json に登録する。
# プロジェクト側の .claude/settings.json に書くと、そのプロジェクトを開いた時しか発火しない。

chmod +x "$HOOK_PATH"

if [ ! -f "$SETTINGS" ]; then
  echo '{}' > "$SETTINGS"
  info "settings.json を新規作成しました"
fi

jq empty "$SETTINGS" 2>/dev/null || die "settings.json が不正な JSON です。手動で修正してください: $SETTINGS"

ALREADY="$(jq -r --arg p "$HOOK_PATH" '
  [.hooks.SessionEnd // [] | .[] | .hooks // [] | .[] | select(.command == $p)] | length
' "$SETTINGS")"

if [ "$ALREADY" -gt 0 ]; then
  ok "登録済み（変更なし）"
else
  mkdir -p "$BACKUP_DIR"
  cp "$SETTINGS" "$BACKUP_DIR/settings.json"
  info "settings.json をバックアップ: $BACKUP_DIR/settings.json"

  # このリポジトリが過去に登録したフックが残っていれば取り除いてから追加する。
  # 残したままだと同じログが二重に書き出される。
  #
  # 除去するのは以下の2つだけで、他人が登録した SessionEnd フックには触らない:
  #   - 旧配置（~/.claude/hooks/session-end-log.sh）… このリポジトリへ移行する前の登録
  #   - このリポジトリの別クローンからの登録（$REPO_ROOT 配下）
  # 「session-end-log.sh で終わるパス」で判定すると、無関係な同名フックまで
  # 巻き込んで消してしまうため、パスを明示して照合する。
  OLD_HOOK_PATH="$CLAUDE_DIR/hooks/session-end-log.sh"
  TMP="$(mktemp)"
  jq --arg new "$HOOK_PATH" --arg old "$OLD_HOOK_PATH" --arg repo "$REPO_ROOT/" '
    .hooks //= {}
    | .hooks.SessionEnd //= []
    # このリポジトリ由来の登録のみを除去（他のフックは温存する）
    | .hooks.SessionEnd = (
        .hooks.SessionEnd
        | map(.hooks = ((.hooks // []) | map(select(
            ((.command // "") as $c
             | ($c == $new) or ($c == $old) or ($c | startswith($repo)))
            | not
          ))))
        | map(select((.hooks | length) > 0))
      )
    | .hooks.SessionEnd += [{
        "hooks": [{
          "type": "command",
          "command": $new,
          "timeout": 30
        }]
      }]
  ' "$SETTINGS" > "$TMP"

  jq empty "$TMP" 2>/dev/null || die "settings.json の生成に失敗しました。バックアップから復元してください: $BACKUP_DIR/settings.json"
  mv "$TMP" "$SETTINGS"
  ok "フックを登録しました"
fi
echo

# ---------------------------------------------------------------
echo "完了"
echo
echo "  スキル : $LINK_PATH → $SKILL_SRC"
echo "  スキル : $YOJITSU_LINK_PATH → $YOJITSU_SKILL_SRC"
echo "  フック : $HOOK_PATH"
echo
if [ "$NEEDS_EDIT" -eq 1 ]; then
  echo "  次にやること:"
  echo "    1. $CONFIG_DIR/config.jsonc を編集"
fi
echo
echo "  ※ フックの登録変更は次回セッションから有効になります"
echo
