#!/usr/bin/env bash
# get_video.sh — 원본 영상을 내려받는다. 자막은 bin/get_subs.sh 가 따로 받는다.
#
# 에이전트는 이 스크립트의 "인자만" 채운다. yt-dlp 옵션을 직접 쓰지 않는다.
#
# 사용법:
#   bin/get_video.sh <영상URL 또는 영상ID>
#
# 예:
#   bin/get_video.sh https://www.youtube.com/watch?v=pwQroU94seA
#   bin/get_video.sh pwQroU94seA
#
# 기본 저장 위치: ~/reels/work/<영상ID>.<확장자>
#
# 환경변수(선택):
#   OUTDIR=~/reels/work   저장 폴더
#   HEIGHT=1080           최대 세로 해상도. 릴스는 1080x1920 이라 1080 아래로 받으면
#                         세로로 자를 때 확대돼서 흐려집니다.
#
# ※ 받기 전에 PIPELINE.md 의 "이 채널의 입장"을 읽으세요.
#   DRM 이 걸린 것(넷플릭스·디즈니+ 등)은 받지 않습니다. 보고 메모만 하세요.

set -uo pipefail

die() { printf '\n[중단] %s\n' "$*" >&2; exit 1; }

command -v yt-dlp >/dev/null 2>&1 || die "yt-dlp 가 없습니다.  맥: brew install yt-dlp"

[ $# -ge 1 ] || die "사용법: bin/get_video.sh <영상URL 또는 영상ID>"

INPUT="$1"
OUTDIR="${OUTDIR:-$HOME/reels/work}"
HEIGHT="${HEIGHT:-1080}"

case "$INPUT" in
  http*) URL="$INPUT" ;;
  *)     URL="https://www.youtube.com/watch?v=$INPUT" ;;
esac

mkdir -p "$OUTDIR"

# yt-dlp 가 오래되면 유튜브가 403 으로 막습니다. 제일 흔한 실패 원인입니다.
VER=$(yt-dlp --version 2>/dev/null)
echo "  yt-dlp $VER"

echo "  받는 중... (길이에 따라 몇 분 걸립니다)"
yt-dlp -f "bv*[height<=$HEIGHT]+ba/b[height<=$HEIGHT]" \
       --no-warnings --no-progress \
       -o "$OUTDIR/%(id)s.%(ext)s" "$URL"
rc=$?

if [ "$rc" -ne 0 ]; then
  die "받지 못했습니다.

제일 흔한 원인은 yt-dlp 가 오래된 것입니다 (유튜브가 자주 바꿉니다).
    brew upgrade yt-dlp

그래도 안 되면 그 영상이 DRM 이 걸렸거나 지역 제한일 수 있습니다.
DRM 이 걸린 것은 받지 않습니다 — 보고 메모만 하세요."
fi

ID=$(yt-dlp --skip-download --no-warnings --print "%(id)s" "$URL" 2>/dev/null | head -1)
FILE=$(ls -S "$OUTDIR/$ID".* 2>/dev/null | grep -vE '\.(tsv|vtt|part)$' | head -1)

if [ -n "$FILE" ]; then
  echo "  저장: $FILE  ($(du -h "$FILE" | cut -f1))"
  echo
  echo "다음: bin/get_subs.sh $ID    ← 자막을 같은 폴더에 받습니다"
  echo "      자막이 없는 영상이면 bin/transcribe.sh \"$FILE\""
else
  echo "  저장은 됐는데 파일을 못 찾았습니다. $OUTDIR 을 직접 확인하세요." >&2
fi
