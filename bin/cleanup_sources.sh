#!/usr/bin/env bash
# cleanup_sources.sh — 발행이 끝난 원본 영상을 지운다. 자막과 완성본은 남긴다.
#
# 원본은 작업용이지 보관용이 아닙니다. 한 편에 수백 MB~1GB라 금방 디스크가 찹니다.
# 원본은 언제든 다시 받을 수 있지만, "내가 왜 이 구간을 골랐나"는 다시 못 만듭니다.
# 그래서 가벼운 자막 TSV 는 남기고 무거운 원본만 지웁니다.
#
# 사용법:
#   bin/cleanup_sources.sh              # 지울 후보만 보여줍니다 (아무것도 안 지움)
#   bin/cleanup_sources.sh --apply      # 실제로 지웁니다
#   bin/cleanup_sources.sh --dir ~/다른폴더 --apply
#
# 판별 방법: **세로 영상은 완성본, 가로 영상은 원본.**
# 이 공정의 결과물은 항상 1080x1920 세로입니다. 가로 영상은 받아온 소스입니다.
#
# 안전장치: 완성본(세로)이 하나도 없으면 "아직 아무것도 굽지 않았다"는 뜻이므로
# 기본적으로 거부합니다. 그래도 지우려면 --force 를 붙이세요.

set -uo pipefail

die() { printf '\n[중단] %s\n' "$*" >&2; exit 1; }

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
[ -x "$FFPROBE" ] || die "ffprobe 가 없습니다.  맥: brew install ffmpeg-full"

DIR="$HOME/reels/work"
APPLY=0
FORCE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --apply) APPLY=1; shift ;;
    --force) FORCE=1; shift ;;
    --dir)   DIR="${2:?--dir 뒤에 경로가 필요합니다}"; shift 2 ;;
    *) die "모르는 인자: $1" ;;
  esac
done

[ -d "$DIR" ] || die "폴더가 없습니다: $DIR"

shopt -s nullglob 2>/dev/null || true

sources=(); outputs=(); scraps=()
total=0

for f in "$DIR"/*.mp4 "$DIR"/*.mkv "$DIR"/*.webm "$DIR"/*.mov "$DIR"/*.MOV; do
  [ -f "$f" ] || continue
  wh=$("$FFPROBE" -v error -select_streams v:0 -show_entries stream=width,height \
       -of csv=p=0:s=x "$f" 2>/dev/null | head -1)
  w="${wh%x*}"; h="${wh#*x}"
  [ -n "$w" ] && [ -n "$h" ] || continue
  if [ "$h" -gt "$w" ]; then
    outputs+=("$f")
  else
    sources+=("$f")
    total=$((total + $(stat -f%z "$f" 2>/dev/null || stat -c%s "$f" 2>/dev/null || echo 0)))
  fi
done

# 중간 산출물 — 다만 "지금 받는 중"인 것은 건드리면 안 됩니다.
# 최근 10분 안에 커진 파일은 진행 중인 다운로드로 보고 건너뜁니다.
FRESH_SECS=600
now=$(date +%s)
busy=()
for f in "$DIR"/*.part "$DIR"/*.ytdl "$DIR"/*.wav "$DIR"/*.f[0-9]*.mp4 "$DIR"/*.f[0-9]*.webm; do
  [ -f "$f" ] || continue
  mt=$(stat -f%m "$f" 2>/dev/null || stat -c%Y "$f" 2>/dev/null || echo 0)
  if [ $((now - mt)) -lt "$FRESH_SECS" ]; then
    busy+=("$f")
    continue
  fi
  scraps+=("$f")
  total=$((total + $(stat -f%z "$f" 2>/dev/null || stat -c%s "$f" 2>/dev/null || echo 0)))
done

human() { awk -v b="$1" 'BEGIN{ s="B KB MB GB"; split(s,u," "); i=1;
  while (b>=1024 && i<4) { b/=1024; i++ } printf "%.1f%s", b, u[i] }'; }

echo "폴더: $DIR"
echo
echo "남깁니다 — 완성본(세로) ${#outputs[@]}개"
for f in "${outputs[@]}"; do echo "  ✓ $(basename "$f")"; done
tsv=("$DIR"/*.tsv)
echo "남깁니다 — 자막 ${#tsv[@]}개 (무엇을 썼는지의 기록)"
echo
echo "지웁니다 — 원본(가로) ${#sources[@]}개"
for f in "${sources[@]}"; do
  echo "  ✗ $(basename "$f")  $(human "$(stat -f%z "$f" 2>/dev/null || echo 0)")"
done
if [ "${#scraps[@]}" -gt 0 ]; then
  echo "지웁니다 — 중간 산출물 ${#scraps[@]}개"
  for f in "${scraps[@]}"; do echo "  ✗ $(basename "$f")"; done
fi
if [ "${#busy[@]}" -gt 0 ]; then
  echo "건드리지 않습니다 — 지금 받는 중으로 보이는 것 ${#busy[@]}개"
  for f in "${busy[@]}"; do echo "  … $(basename "$f")"; done
fi
echo
echo "확보되는 공간: $(human "$total")"

if [ "${#sources[@]}" -eq 0 ] && [ "${#scraps[@]}" -eq 0 ]; then
  echo
  echo "지울 게 없습니다."
  exit 0
fi

if [ "${#outputs[@]}" -eq 0 ] && [ "$FORCE" -eq 0 ]; then
  echo
  die "완성본(세로 영상)이 하나도 없습니다. 아직 굽지 않은 것 같습니다.
원본을 지우면 다시 받아야 합니다. 정말 지우려면 --force 를 붙이세요."
fi

if [ "$APPLY" -eq 0 ]; then
  echo
  echo "아무것도 지우지 않았습니다. 실제로 지우려면 --apply 를 붙이세요."
  exit 0
fi

for f in "${sources[@]}" "${scraps[@]}"; do rm -f "$f"; done
echo
echo "지웠습니다. 확보: $(human "$total")"
df -h "$DIR" | tail -1 | awk '{print "디스크 여유: "$4}'
