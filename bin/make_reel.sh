#!/usr/bin/env bash
# make_reel.sh — 원본 영상에서 세로 릴스 1개를 굽는다.
#
# 에이전트는 이 스크립트의 "인자만" 채운다. ffmpeg 명령을 직접 쓰지 않는다.
#
# 사용법:
#   bin/make_reel.sh <원본영상> <시작초> <끝초> <자막.tsv> <출력.mp4>
#
# 예:
#   bin/make_reel.sh ~/reels/work/source.mp4 132 161 ~/reels/work/sub.tsv ~/reels/work/EP01.mp4
#
# 자막.tsv 형식 — 탭으로 구분, 시간은 "클립 시작을 0초로 본" 상대 시간(초):
#   0.0<TAB>3.5<TAB>It's just a tool though, isn't it?<TAB>그냥 도구일 뿐이잖아요?
#   3.5<TAB>7.0<TAB>No, it's not.<TAB>아니요.
#
# 환경변수(선택):
#   FIT=crop|pad   기본 crop. 좌우를 잘라 꽉 채움. pad 는 위아래 검은 여백.
#   STYLE=dual|mono  기본 dual. EN 흰색 위 / KR 노랑(#e3df6b) 아래. mono 는 둘 다 흰색.
#   FONT="..."     기본은 OS별 자동. 예: FONT="Pretendard"
#   SOURCE="..."   화면 상단에 구울 출처. 예: SOURCE="Ted Chiang · DeMott Lecture 2025"
#   MARGIN_V=320   자막을 바닥에서 띄우는 px. 기본 320 (인스타 UI 안전영역).
#                  유튜브 쇼츠만 쓸 거면 200 정도로 낮춰도 됩니다.

set -euo pipefail

die() { printf '\n[중단] %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------- 0. 사전 점검
# ── ass 필터가 있는 ffmpeg 고르기 ───────────────────────────────────────────
# Homebrew 코어의 ffmpeg 에는 libass 가 없습니다. libass 가 들어간 ffmpeg-full 은
# keg-only 라 PATH 에 안 걸리므로, 여기서 직접 찾습니다.
# 직접 지정하려면:  FFMPEG=/경로/ffmpeg bin/스크립트
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
FFPROBE="${FFMPEG%/ffmpeg}/ffprobe"
[ -x "$FFPROBE" ] || FFPROBE="$(command -v ffprobe)"

[ -x "$FFMPEG" ]  || die "ffmpeg 이 없습니다.  맥: brew install ffmpeg-full"
[ -x "$FFPROBE" ] || die "ffprobe 가 없습니다. 맥: brew install ffmpeg-full"

# pipefail 때문에 grep -q 로 조기 종료하면 오탐이 난다. awk 하나로 끝낸다.
if ! "$FFMPEG" -hide_banner -filters 2>/dev/null | awk '$2=="ass"{f=1} END{exit !f}'; then
  die "이 ffmpeg 은 자막을 못 굽습니다 (libass 없이 빌드됨).
     확인:  "$FFMPEG" -filters | grep -E ' ass | subtitles '
     해결:  brew install ffmpeg-full      (코어 ffmpeg 에는 libass 가 없습니다)
     ※ 여기서 우회하지 마세요. PNG 를 겹치거나 moviepy 를 까는 길로 새면
        더 오래 걸리고 결과도 나쁩니다. ffmpeg 부터 고치는 게 정답입니다."
fi

[ $# -eq 5 ] || die "인자 5개가 필요합니다.
     사용법: bin/make_reel.sh <원본영상> <시작초> <끝초> <자막.tsv> <출력.mp4>"

SRC="$1"; START="$2"; END="$3"; SUBS="$4"; OUT="$5"
FIT="${FIT:-crop}"
STYLE="${STYLE:-dual}"

[ -f "$SRC" ]  || die "원본 영상이 없습니다: $SRC"
[ -f "$SUBS" ] || die "자막 파일이 없습니다: $SUBS"

DUR=$(awk -v a="$START" -v b="$END" 'BEGIN{ printf "%.3f", b-a }')
awk -v d="$DUR" 'BEGIN{ exit !(d>0) }' || die "끝초가 시작초보다 커야 합니다. ($START → $END)"

# 폰트 자동 선택
if [ -z "${FONT:-}" ]; then
  case "$(uname -s)" in
    Darwin) FONT="Apple SD Gothic Neo" ;;
    *)      FONT="Noto Sans CJK KR" ;;
  esac
fi

# ------------------------------------------------------------- 1. .ass 자막 생성
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
ASS="$WORK/sub.ass"

# 자막을 화면 바닥에서 얼마나 띄울지(px). 인스타 릴스·틱톡은 하단 250~320px 를
# 캡션과 버튼 UI 가 덮습니다. 150 이면 한국어 줄이 거기 걸립니다.
MARGIN_V="${MARGIN_V:-320}"

# 화면에 구울 출처 한 줄. 상단에 작게 들어갑니다.
# 수익화하지 않고 원본을 홍보하는 채널에서 출처는 선택이 아니라 조건입니다
# (PIPELINE.md "이 채널의 입장"). 비워두면 경고만 하고 넘어갑니다.
SOURCE="${SOURCE:-}"

# ASS 색상은 &HBBGGRR. #e3df6b → &H6BDFE3
KR_COLOR='&H006BDFE3'
[ "$STYLE" = "mono" ] && KR_COLOR='&H00FFFFFF'

cat > "$ASS" <<ASS_HEADER
[Script Info]
ScriptType: v4.00+
PlayResX: 1080
PlayResY: 1920
WrapStyle: 2
ScaledBorderAndShadow: yes

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, OutlineColour, BackColour, Bold, Italic, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Reel,$FONT,54,&H00FFFFFF,&H00000000,&H00000000,0,0,1,3,0,2,60,60,$MARGIN_V,1
Style: Source,$FONT,32,&H30FFFFFF,&H90000000,&H00000000,0,0,1,2,0,8,50,50,110,1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
ASS_HEADER

awk -F'\t' -v kr="$KR_COLOR" '
function ts(s,   h,m,sec) {
  h = int(s/3600); s -= h*3600
  m = int(s/60);   s -= m*60
  return sprintf("%d:%02d:%05.2f", h, m, s)
}
/^[[:space:]]*$/ { next }
/^[[:space:]]*#/ { next }
NF < 4 {
  printf("[중단] 자막 %d번째 줄의 칸이 4개가 아닙니다. 탭으로 구분했는지 확인하세요.\n", NR) > "/dev/stderr"
  exit 1
}
{
  en = $3; ko = $4
  gsub(/\r/, "", en); gsub(/\r/, "", ko)
  # ASS 는 { } 를 서식 명령으로 읽는다. 본문에 들어오면 깨지므로 치환한다.
  gsub(/[{}]/, "", en); gsub(/[{}]/, "", ko)
  printf("Dialogue: 0,%s,%s,Reel,,0,0,0,,%s\\N{\\c%s}%s\n", ts($1), ts($2), en, kr, ko)
}
' "$SUBS" >> "$ASS" || die "자막 파일을 읽지 못했습니다."

# 출처 한 줄을 클립 전체에 깐다. ASS 의 { } 는 서식 명령이라 본문에서 지운다.
if [ -n "$SOURCE" ]; then
  SRC_TXT=$(printf '%s' "$SOURCE" | tr -d '{}' | tr '\n' ' ')
  SRC_END=$(awk -v d="$DUR" 'BEGIN{
    h=int(d/3600); d-=h*3600; m=int(d/60); d-=m*60
    printf "%d:%02d:%05.2f", h, m, d }')
  printf 'Dialogue: 0,0:00:00.00,%s,Source,,0,0,0,,%s\n' "$SRC_END" "$SRC_TXT" >> "$ASS"
else
  echo "  ⚠ 출처 표기 없음. SOURCE=\"채널 · 제목\" 로 넣으세요 (발행 조건입니다)." >&2
fi

CUES=$(grep -c '^Dialogue:' "$ASS" || true)
[ "$CUES" -gt 0 ] || die "자막 큐가 0개입니다. TSV 가 비었거나 탭이 아니라 공백으로 구분됐습니다."

# ------------------------------------------------------------------ 2. 렌더링
case "$FIT" in
  crop) GEO="scale=1080:1920:force_original_aspect_ratio=increase,crop=1080:1920" ;;
  pad)  GEO="scale=1080:1920:force_original_aspect_ratio=decrease,pad=1080:1920:(ow-iw)/2:(oh-ih)/2:black" ;;
  *)    die "FIT 은 crop 또는 pad 만 됩니다. (받은 값: $FIT)" ;;
esac

SRC_ABS="$(cd "$(dirname "$SRC")" && pwd)/$(basename "$SRC")"
mkdir -p "$(dirname "$OUT")"
OUT_ABS="$(cd "$(dirname "$OUT")" && pwd)/$(basename "$OUT")"

echo "→ 자르는 중: ${START}s 부터 ${DUR}s   (자막 ${CUES}개, ${FIT}, ${STYLE}, ${FONT})"

# 필터에 넣는 자막 경로는 따옴표·콜론 문제를 피하려고 항상 작업폴더 안에서 상대경로로 쓴다
( cd "$WORK" && "$FFMPEG" -hide_banner -loglevel error -stats -y \
    -ss "$START" -i "$SRC_ABS" -t "$DUR" \
    -vf "$GEO,ass=sub.ass" \
    -c:v libx264 -preset medium -crf 20 -pix_fmt yuv420p \
    -c:a aac -b:a 128k -ac 2 \
    -movflags +faststart \
    "$OUT_ABS" ) || die "렌더링 실패. 위 에러를 그대로 읽고, 추측으로 다른 도구를 깔지 마세요."

# ------------------------------------------------------------------ 3. 검증
REAL=$("$FFPROBE" -v error -show_entries format=duration -of csv=p=0 "$OUT_ABS")
SIZE=$("$FFPROBE" -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0:s=x "$OUT_ABS")

echo
echo "완료: $OUT_ABS"
echo "  길이: ${REAL}초"
echo "  해상도: ${SIZE}"
echo
echo "발행 전 사람이 확인할 것"
awk -v d="$REAL" 'BEGIN{ printf "  [%s] 25~35초 안인가\n", (d>=25 && d<=35 ? "O" : "X") }'
[ "$SIZE" = "1080x1920" ] && echo "  [O] 세로 1080x1920 인가" || echo "  [X] 세로 1080x1920 인가"
cat <<'CHECK'
  [ ] 첫 컷과 마지막 컷이 문장 경계에서 시작/끝나는가
  [ ] 마지막 문장이 잘리지 않고 닫히는가
  [ ] 자막이 인물 얼굴을 가리지 않는가
  [ ] 음악 구간이 안 들어갔는가
  [ ] 화면에 출처를 표기했는가
  [ ] 발언이 원래 맥락과 다르게 읽히지 않는가
CHECK
