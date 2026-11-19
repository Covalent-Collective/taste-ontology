#!/usr/bin/env bash
# get_subs.sh — 유튜브 영상의 진짜 타임코드 자막을 full.tsv 로 받는다.
#
# 에이전트는 이 스크립트의 "인자만" 채운다. VTT 파서를 직접 쓰지 않는다.
#
# 사용법:
#   bin/get_subs.sh <영상URL 또는 영상ID> [출력.tsv]
#
# 예:
#   bin/get_subs.sh https://www.youtube.com/watch?v=qn5WkeSTxwA
#   bin/get_subs.sh qn5WkeSTxwA ~/reels/work/full.tsv
#
# 기본 출력: ~/reels/work/full.tsv
# 형식(탭 3칸):  시작초 <TAB> 끝초 <TAB> 원문
#
# 환경변수(선택):
#   LANGS="en.*,ko.*"   받을 자막 언어. 앞에 쓴 것이 우선.
#
# 사람이 만든 자막이 있으면 그걸 먼저 씁니다. 없을 때만 자동생성으로 내려갑니다.
# 자동생성은 같은 줄이 굴러가며 중복되므로 여기서 합쳐서 내보냅니다.

set -euo pipefail

die() { printf '\n[중단] %s\n' "$*" >&2; exit 1; }

command -v yt-dlp >/dev/null 2>&1 || die "yt-dlp 가 없습니다.  맥: brew install yt-dlp"
command -v python3 >/dev/null 2>&1 || die "python3 가 없습니다."

[ $# -ge 1 ] || die "사용법: bin/get_subs.sh <영상URL 또는 영상ID> [출력.tsv]"

INPUT="$1"
OUT="${2:-$HOME/reels/work/full.tsv}"
LANGS="${LANGS:-en.*,ko.*}"

case "$INPUT" in
  http*) URL="$INPUT" ;;
  *)     URL="https://www.youtube.com/watch?v=$INPUT" ;;
esac

OUTDIR="$(dirname "$OUT")"
mkdir -p "$OUTDIR"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# ── 1. 사람이 만든 자막 먼저, 없으면 자동생성 ──────────────────────────────
KIND=""
yt-dlp --skip-download --write-subs --sub-langs "$LANGS" --sub-format vtt \
       --no-warnings -o "$TMP/s.%(ext)s" "$URL" >/dev/null 2>&1 || true
if ls "$TMP"/s.*.vtt >/dev/null 2>&1; then
  KIND="사람이 만든 자막"
else
  yt-dlp --skip-download --write-auto-subs --sub-langs "$LANGS" --sub-format vtt \
         --no-warnings -o "$TMP/s.%(ext)s" "$URL" >/dev/null 2>&1 || true
  ls "$TMP"/s.*.vtt >/dev/null 2>&1 && KIND="자동생성 자막"
fi

[ -n "$KIND" ] || die "이 영상에는 자막이 없습니다.
타임코드를 지어내지 마세요. 다른 영상을 고르거나, 직접 찍은 영상이면
whisper 로 전사하세요:  brew install whisper.cpp"

VTT="$(ls -S "$TMP"/s.*.vtt | head -1)"   # 가장 큰 것 = 가장 내용이 많은 트랙

# ── 2. VTT → TSV (중복 합치기) ─────────────────────────────────────────────
python3 -I - "$VTT" "$OUT" <<'PY'
import re, sys

src, dst = sys.argv[1], sys.argv[2]

def secs(s):
    h, m, rest = s.split(":")
    sec, ms = rest.split(".")
    return round(int(h) * 3600 + int(m) * 60 + int(sec) + int(ms) / 1000, 2)

TIME = re.compile(r"^(\d\d:\d\d:\d\d\.\d\d\d) --> (\d\d:\d\d:\d\d\.\d\d\d)")
cues, cur, buf = [], None, []

def flush():
    """사람이 만든 자막은 한 큐가 두 줄 이상인 경우가 많다.
    첫 줄만 담으면 문장이 조용히 잘린다 — 큐의 모든 줄을 이어 붙인다."""
    if cur is not None and buf:
        cues.append((cur[0], cur[1], " ".join(buf)))
    buf.clear()

for line in open(src, encoding="utf-8"):
    line = line.rstrip("\n")
    m = TIME.match(line)
    if m:
        flush()
        cur = [secs(m.group(1)), secs(m.group(2))]
        continue
    if cur is None:
        continue
    if not line.strip():
        flush()
        cur = None
        continue
    text = re.sub(r"<[^>]+>", "", line).strip()
    if text:
        buf.append(text)
flush()

# 자동생성 자막은 같은 줄이 굴러간다: 같거나 앞부분이 겹치면 하나로 합친다.
merged = []
for start, end, text in cues:
    if merged:
        ps, pe, pt = merged[-1]
        if text == pt:
            merged[-1] = (ps, max(pe, end), pt)
            continue
        if text.startswith(pt):
            merged[-1] = (ps, max(pe, end), text)
            continue
        if pt.startswith(text):
            merged[-1] = (ps, max(pe, end), pt)
            continue
    merged.append((start, end, text))

with open(dst, "w", encoding="utf-8") as f:
    for start, end, text in merged:
        f.write(f"{start}\t{end}\t{text}\n")

print(f"  원본 큐 {len(cues)} → 합친 뒤 {len(merged)}")
PY

LAST="$(tail -1 "$OUT" | cut -f2)"
echo "  출처: $KIND  ($(basename "$VTT"))"
echo "  저장: $OUT"
echo "  길이: ${LAST}초 지점까지"
echo
echo "다음: 이 파일에서 25~35초 후보를 5개 뽑아 채점하세요 (P5 3단계)."
