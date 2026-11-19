#!/usr/bin/env bash
# doctor.sh — 영상 편집을 시작하기 전에 딱 한 번 돌린다.
# 여기서 X 가 하나라도 나오면, 그걸 고치기 전에는 편집을 시도하지 마세요.

echo "== 취향 에이전트 · 영상 편집 환경 점검 =="
echo

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

ok=0; ng=0
chk() { if eval "$2" >/dev/null 2>&1; then echo "  [O] $1"; ok=$((ok+1)); else echo "  [X] $1"; ng=$((ng+1)); fi; }

echo "  사용할 ffmpeg: ${FFMPEG:-(없음)}"
echo

chk "ffmpeg 있음"              "[ -x \"$FFMPEG\" ]"
chk "ffprobe 있음"             "[ -x \"$FFPROBE\" ]"
chk "자막 필터(ass) 있음"       "\"$FFMPEG\" -hide_banner -filters 2>/dev/null | awk '\$2==\"ass\"{f=1} END{exit !f}'"
chk "자막 필터(subtitles) 있음" "\"$FFMPEG\" -hide_banner -filters 2>/dev/null | awk '\$2==\"subtitles\"{f=1} END{exit !f}'"
chk "yt-dlp 있음"              "command -v yt-dlp"
chk "한글 폰트 있음"            "fc-list 2>/dev/null | grep -qiE 'CJK|Gothic|Pretendard' || ls '/System/Library/Fonts/AppleSDGothicNeo.ttc'"
chk "작업 경로에 한글/공백 없음" "printf '%s' \"\$PWD\" | grep -qE '^[A-Za-z0-9/._-]+\$'"

echo
if [ "$ng" -eq 0 ]; then
  echo "전부 통과. bin/get_subs.sh 로 자막을 받고 bin/make_reel.sh 로 구우면 됩니다."
  exit 0
fi

cat <<'FIX'
고치는 법
─────────────────────────────────────────────
ffmpeg 없음 / 자막 필터 없음
    맥:      brew install ffmpeg-full
             ※ brew reinstall ffmpeg 은 소용없습니다 — 코어 포뮬러에는 libass 가
               아예 없습니다. ffmpeg-full 이 libass 를 포함한 병(bottle)이라
               컴파일 없이 몇 분에 끝납니다. keg-only 라서 PATH 에는 안 걸리는데,
               이 스크립트가 알아서 찾아 씁니다.
    우분투:  sudo apt install ffmpeg
    확인:    "$FFMPEG" -filters | grep -E ' ass | subtitles '
    ※ 필터가 없는 ffmpeg 은 자막을 못 굽습니다. PNG 를 겹치거나
      moviepy 를 까는 우회로로 가지 마세요. 그게 대부분의 실패 원인입니다.

yt-dlp 없음
    맥:      brew install yt-dlp
    우분투:  sudo apt install yt-dlp
    ※ 유튜브 자막의 진짜 타임코드를 받는 데 씁니다. 이게 없으면 bin/get_subs.sh 가
      멈추고, 타임코드를 눈대중으로 때우게 됩니다. 그게 자막이 밀리는 원인입니다.

한글 폰트 없음
    맥은 기본 탑재(Apple SD Gothic Neo). 우분투: sudo apt install fonts-noto-cjk

작업 경로에 한글/공백 있음
    한글·공백·괄호가 든 경로는 셸에서 계속 깨집니다. 영문 경로로 옮기세요.
        mkdir -p ~/reels/work
    원본 영상도 여기로 복사하고, 파일명은 source.mp4 처럼 단순하게.
FIX
exit 1
