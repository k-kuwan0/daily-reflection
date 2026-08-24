#!/usr/bin/env python3
"""SessionEnd フック用: transcript (JSONL) からセッションログを抽出する。

hooks/session-end-log.sh から呼ばれる。単体でも実行できる:

    python3 extract-session.py <transcript_path> <session_id> <cwd>

標準出力に JSONL を書く。1行目がセッションメタ情報（type: "session"）、
2行目以降が時系列のユーザー発言・assistant発言・ツール呼び出し。

抽出結果が空（意味のある発言が無い）場合は何も出力せず終了する。
呼び出し元（bash）はこの出力の有無で保存要否を判断する。
"""
import json
import sys
from datetime import datetime, timezone, timedelta

JST = timezone(timedelta(hours=9))

MAX_TEXT_LEN = 1000
TRUNCATE_SUFFIX = "...(truncated)"


def parse_ts(ts_str):
    """timestamp文字列 -> (ISO8601+JSTの文字列, date文字列) のタプル。失敗時は (None, None)。"""
    if not ts_str:
        return None, None
    try:
        dt = datetime.fromisoformat(ts_str.replace("Z", "+00:00")).astimezone(JST)
    except (ValueError, OSError):
        return None, None
    return dt.isoformat(timespec="seconds"), dt.strftime("%Y-%m-%d")


def truncate(text):
    if len(text) <= MAX_TEXT_LEN:
        return text
    # サフィックス分を差し引いた上で切り詰める
    cut = MAX_TEXT_LEN - len(TRUNCATE_SUFFIX)
    if cut < 0:
        cut = 0
    return text[:cut] + TRUNCATE_SUFFIX


def strip_command_wrapper(text):
    """スラッシュコマンド実行時のラッパーからユーザーの実意図だけを取り出す。

    観測される2パターン:

    1. 組み込みコマンド（例: /model）:
       <command-message>...</command-message>
       <command-name>...</command-name>
       <command-args>実際の引数</command-args>
       → <command-args> の中身だけを残す（無ければ空文字 = 破棄）。

    2. カスタムスキルのスラッシュコマンド:
       "Base directory for this skill: ...\n\n<SKILL.md 全文>\n\nARGUMENTS: 実際の引数"
       → 全体を破棄（None を返す）。

       このエントリは transcript 上で isMeta=true として記録される、
       パターン1のラッパーと同一タイムスタンプの「双子」である。
       Claude Code はスキル起動時に「ラッパー」と「SKILL.md本文を注入した
       isMeta エントリ」の2件を書くため、ARGUMENTS: 以降を残すと
       パターン1と同じ引数文字列が2行できて重複する。
       ユーザーの実意図はパターン1の <command-args> 側で拾えているので、
       こちらは捨てる。

    どちらにも該当しなければ text をそのまま返す。
    """
    if "<command-message>" in text and "<command-name>" in text:
        start_tag = "<command-args>"
        end_tag = "</command-args>"
        start = text.find(start_tag)
        end = text.find(end_tag)
        if start != -1 and end != -1:
            inner = text[start + len(start_tag):end].strip()
            return inner if inner else None
        return None

    if text.startswith("Base directory for this skill:"):
        return None

    return text


def is_noise(text):
    if text.startswith("<ide_opened_file>"):
        return True
    if text.startswith("<system-reminder>"):
        return True
    return False


def tool_target(tool_input):
    """ツール呼び出しの対象を1つだけ選んで返す。無ければ None。"""
    if "file_path" in tool_input:
        return str(tool_input["file_path"])
    if "command" in tool_input:
        return str(tool_input["command"])[:100]
    if "pattern" in tool_input:
        return str(tool_input["pattern"])
    return None


def extract_entries(transcript_path):
    entries = []
    with open(transcript_path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                d = json.loads(line)
            except json.JSONDecodeError:
                continue

            msg_type = d.get("type")
            if msg_type not in ("user", "assistant"):
                continue

            ts_iso, ts_date = parse_ts(d.get("timestamp", ""))

            message = d.get("message", {})
            if isinstance(message, str):
                try:
                    message = json.loads(message)
                except json.JSONDecodeError:
                    continue

            role = message.get("role", msg_type)
            content = message.get("content", "")

            blocks = []
            if isinstance(content, list):
                for block in content:
                    if not isinstance(block, dict):
                        continue
                    block_type = block.get("type", "")
                    if block_type == "text":
                        text = block.get("text", "")
                        if is_noise(text):
                            continue
                        text = strip_command_wrapper(text)
                        if not text:
                            continue
                        blocks.append({"role": role, "text": truncate(text)})
                    elif block_type == "tool_use":
                        tool_name = block.get("name", "unknown")
                        tool_input = block.get("input", {}) or {}
                        target = tool_target(tool_input)
                        entry = {"role": role, "tool": tool_name}
                        if target is not None:
                            entry["target"] = target
                        blocks.append(entry)
                    # tool_result は冗長なため記録しない
            elif isinstance(content, str) and content:
                text = content
                if not is_noise(text):
                    text = strip_command_wrapper(text)
                    if text:
                        blocks.append({"role": role, "text": truncate(text)})

            for b in blocks:
                b["ts"] = ts_iso
                b["date"] = ts_date
                entries.append(b)

    return [e for e in entries if e.get("ts")]


def build_jsonl(entries, session_id, cwd):
    """entries（ts昇順を仮定）から JSONL 文字列を組み立てる。空なら None。"""
    if not entries:
        return None

    started = entries[0]["ts"]
    lines = []
    session_meta = {
        "type": "session",
        "id": session_id,
        "cwd": cwd,
        "started": started,
    }
    lines.append(json.dumps(session_meta, ensure_ascii=False))

    for e in entries:
        row = {"ts": e["ts"], "role": e["role"]}
        if "tool" in e:
            row["tool"] = e["tool"]
            if "target" in e:
                row["target"] = e["target"]
        else:
            row["text"] = e["text"]
        lines.append(json.dumps(row, ensure_ascii=False))

    return "\n".join(lines) + "\n"


def main():
    if len(sys.argv) < 4:
        print("usage: extract-session.py <transcript_path> <session_id> <cwd>", file=sys.stderr)
        sys.exit(1)

    transcript_path, session_id, cwd = sys.argv[1], sys.argv[2], sys.argv[3]

    entries = extract_entries(transcript_path)
    output = build_jsonl(entries, session_id, cwd)
    if output is None:
        sys.exit(0)

    sys.stdout.write(output)

    # 呼び出し元がセッション開始日でディレクトリを決められるよう、
    # 標準エラーに __SESSION_DATE__ を出力する（標準出力のJSONLを汚さないため）。
    first_date = entries[0].get("date", "")
    if first_date:
        print(f"__SESSION_DATE__:{first_date}", file=sys.stderr)


if __name__ == "__main__":
    main()
