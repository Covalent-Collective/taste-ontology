#!/usr/bin/env bash
# transcribe.sh — 자막이 없는 영상(직접 찍은 것)을 전사해서 full.tsv 로 만든다.
#
# 유튜브 영상은 bin/get_subs.sh 를 쓴다. 이 스크립트는 자막이 아예 없을 때만 쓴다.
# 에이전트는 이 스크립트의 "인자만" 채운다. whisper 명령을 직접 쓰지 않는다.
#
# 사용법:
#   bin/transcribe.sh <영상 또는 오디오> [출력.tsv]
#
# 예:
#   bin/transcribe.sh ~/reels/work/love-garden.mov
#   LANG_CODE=ko bin/transcribe.sh ~/reels/work/diary.m4a ~/reels/work/full.tsv
#
# 기본 출력: ~/reels/work/full.tsv
# 형식(탭 3칸):  시작초 <TAB> 끝초 <TAB> 원문   ← get_subs.sh 와 같은 형식
#
# 환경변수(선택):
#   MODEL=...       기본 ~/reels/models/ggml-large-v3-turbo.bin
#   LANG_CODE=ko    기본 auto. 한국어만 나오는 영상은 ko 로 못 박는 게 더 정확하다.
#   THREADS=8       기본은 코어 수

set -euo pipefail

die() { printf '\n[중단] %s\n' "$*" >&2; exit 1; }

command -v whisper-cli >/dev/null 2>&1 || die "whisper-cli 가 없습니다.  맥: brew install whisper.cpp"

# ── ass 필터가 있는 ffmpeg 고르기 (다른 스크립트와 동일) ───────────────────
_has_ass() { [ -x "$1" ] && "$1" -hide_banner -filters 2>/dev/null | awk '$2=="ass"{f=1} END{exit !f}'; }
_pick_ffmpeg() {
  local c
  for c in "${FFMPEG:-}" "$(command -v ffmpeg)" \
           /opt/homebrew/opt/ffmpeg-full/bin/ffmpeg /usr/local/opt/ffmpeg-full/bin/ffmpeg; do
    [ -n "$c" ] && _has_ass "$c" && { printf '%s' "$c"; return 0; }
  done
  printf '%s' "${FFMPEG:-$(command -v ffmpeg)}"
}
FFMPEG="$(_pick_ffmpeg)"
[ -x "$FFMPEG" ] || die "ffmpeg 이 없습니다.  맥: brew install ffmpeg-full"

[ $# -ge 1 ] || die "사용법: bin/transcribe.sh <영상 또는 오디오> [출력.tsv]"

SRC="$1"
[ -f "$SRC" ] || die "파일이 없습니다: $SRC"

OUT="${2:-$HOME/reels/work/full.tsv}"
MODEL="${MODEL:-$HOME/reels/models/ggml-large-v3-turbo.bin}"
LANG_CODE="${LANG_CODE:-auto}"
THREADS="${THREADS:-$(sysctl -n hw.ncpu 2>/dev/null || echo 4)}"

if [ ! -f "$MODEL" ]; then
  die "모델이 없습니다: $MODEL

받는 법 (1.6GB, 한 번만):
    mkdir -p ~/reels/models && cd ~/reels/models
    curl -fL -O https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin

※ brew 로 깔리는 whisper.cpp 에는 모델이 들어 있지 않습니다.
※ ggml-base.en 같은 .en 모델은 영어 전용이라 한국어에는 쓸 수 없습니다."
fi

mkdir -p "$(dirname "$OUT")"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# ── 1. whisper 가 먹는 형식으로 변환 (16kHz 모노 WAV) ──────────────────────
echo "  오디오 변환 중..."
"$FFMPEG" -v error -i "$SRC" -vn -ac 1 -ar 16000 -c:a pcm_s16le -y "$TMP/a.wav"

# ── 2. 전사 ────────────────────────────────────────────────────────────────
echo "  전사 중 (언어: $LANG_CODE, 스레드: $THREADS)... 영상 길이만큼 걸립니다."
whisper-cli -m "$MODEL" -f "$TMP/a.wav" -l "$LANG_CODE" -t "$THREADS" \
            -ocsv -of "$TMP/out" >/dev/null 2>&1 \
  || die "전사에 실패했습니다. 모델과 오디오를 확인하세요."

[ -f "$TMP/out.csv" ] || die "전사 결과가 비었습니다."

# ── 3. CSV(밀리초) → TSV(초) ───────────────────────────────────────────────
python3 -I - "$TMP/out.csv" "$OUT" <<'PY'
import csv, sys

src, dst = sys.argv[1], sys.argv[2]
rows = []
with open(src, encoding="utf-8") as f:
    for i, row in enumerate(csv.reader(f)):
        if i == 0 or len(row) < 3:      # 헤더 건너뛰기
            continue
        try:
            start, end = int(row[0]) / 1000, int(row[1]) / 1000
        except ValueError:
            continue
        text = ",".join(row[2:]).strip()
        if text:
            rows.append((round(start, 2), round(end, 2), text))

with open(dst, "w", encoding="utf-8") as f:
    for start, end, text in rows:
        f.write(f"{start}\t{end}\t{text}\n")

print(f"  구간 {len(rows)}개")
PY

LAST="$(tail -1 "$OUT" | cut -f2)"
echo "  저장: $OUT"
echo "  길이: ${LAST}초 지점까지"
echo
echo "주의: 전사는 받아쓰기지 자막이 아닙니다. 고유명사와 숫자는 반드시 눈으로 확인하세요."
echo "다음: 이 파일에서 25~35초 후보를 5개 뽑아 채점하세요 (P5 3단계)."
