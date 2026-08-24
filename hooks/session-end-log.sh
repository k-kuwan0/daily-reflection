#!/bin/bash
# SessionEnd hook: Extract conversation essentials and append to daily log
# Input: JSON via stdin with session_id, transcript_path, reason, cwd
#
# 抽出ロジック本体は extract-session.py（同ディレクトリ）に分離している。
# フックは任意の cwd から実行されるため、スクリプトパスは絶対パスで解決する。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXTRACT_SCRIPT="$SCRIPT_DIR/extract-session.py"

INPUT=$(cat)
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty')
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')

# Skip if no transcript
if [ -z "$TRANSCRIPT_PATH" ] || [ ! -f "$TRANSCRIPT_PATH" ]; then
  exit 0
fi

# Output directory: daily-logs/YYYY-MM-DD/HH-MM-SS.jsonl
TODAY=$(date +%Y-%m-%d)
TIMESTAMP=$(date +%H-%M-%S)
LOG_DIR="$HOME/.claude/daily-logs/$TODAY"

# 標準出力: JSONL本体 / 標準エラー: __SESSION_DATE__:YYYY-MM-DD（あれば）
STDERR_FILE=$(mktemp)
CONTENT=$(python3 "$EXTRACT_SCRIPT" "$TRANSCRIPT_PATH" "$SESSION_ID" "$CWD" 2>"$STDERR_FILE") || {
  rm -f "$STDERR_FILE"
  exit 0
}
SESSION_DATE=$(grep -o '__SESSION_DATE__:.*' "$STDERR_FILE" | cut -d: -f2- || true)
rm -f "$STDERR_FILE"

# Skip if no content extracted
if [ -z "$CONTENT" ]; then
  exit 0
fi

# Use session's actual start date for directory (not export date)
if [ -n "$SESSION_DATE" ]; then
  LOG_DIR="$HOME/.claude/daily-logs/$SESSION_DATE"
fi

mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/$TIMESTAMP.jsonl"

printf '%s' "$CONTENT" > "$LOG_FILE"

exit 0
