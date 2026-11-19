# 사전 준비 — 모임 전에 보낼 것

> **1회차(온톨로지 90분)는 설치가 거의 없습니다.** 브라우저와 옵시디언만 있으면 됩니다.
> **2회차(영상 제작)는 설치가 오래 걸립니다 — 맥은 최대 90분.** 당일에 시작하면 늦습니다.

---

## 1. 참가자에게 보낼 공지 (그대로 복사)

### 1회차 공지

```
[1회차 준비물]
1. 노트북 (맥/윈도우 상관없음)
2. 옵시디언 설치 — https://obsidian.md
3. AI 창 하나 (Claude 또는 ChatGPT, 무료 계정도 됩니다)
4. 파고 싶은 주제 하나 — 지금 당장 30분 떠들 수 있는 것으로

설치는 옵시디언 하나뿐입니다. 나머지는 현장에서 같이 합니다.
```

### 2회차 공지 — **최소 3일 전에 보내세요**

```
[2회차 준비물 — 설치에 시간이 걸립니다. 전날 밤까지 끝내주세요]

★ 맥: ffmpeg 재설치가 필요합니다. 컴파일이라 30~90분 걸립니다.
   터미널(Cmd+Space → "터미널")에 아래를 한 줄씩 붙여넣으세요.

   brew uninstall ffmpeg
   brew install homebrew-ffmpeg/ffmpeg/ffmpeg

   ※ "brew: command not found" 가 나오면 Homebrew 부터:
   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

★ 윈도우: WSL2 를 먼저 설치하세요 (재부팅 포함 20~30분).
   관리자 PowerShell 에서:  wsl --install
   재부팅 후 우분투 창에서:  sudo apt update && sudo apt install ffmpeg fonts-noto-cjk

★ 공통
   - 디스크 여유 10GB 이상 확보
   - 인터뷰 영상 1개 준비 (자막/트랜스크립트가 있는 것)
   - 다 끝나면 아래 한 줄을 붙여넣고, 나온 결과를 캡처해서 보내주세요

   ffmpeg -filters | grep -E ' ass | subtitles '

   두 줄이 나오면 준비 완료입니다. 아무것도 안 나오면 알려주세요.
```

---

## 2. 왜 맥이 오래 걸리나 (진행자용 배경)

Homebrew 코어의 ffmpeg 포뮬러는 **libass(자막 굽기)를 의존성에 포함하지 않습니다.**
그래서 그냥 깔린 ffmpeg 으로는 자막이 절대 안 들어갑니다.

```bash
brew info ffmpeg | grep -A1 Required     # libass 가 없으면 그 ffmpeg 로는 못 굽습니다
```

libass 가 기본으로 들어간 포뮬러는 `homebrew-ffmpeg` 탭에 있는데, **병에 담긴 빌드(bottle)가
없어서 소스 컴파일**을 합니다. 그래서 30~90분입니다.

### 실제로 걸린 함정 두 개

**① `brew reinstall ffmpeg` 은 해결이 아닙니다.** 같은(libass 없는) 걸 다시 깝니다.

**② `brew unlink` 로는 부족합니다.** 탭 설치를 시도하면 이렇게 막힙니다.

```
Error: ffmpeg was installed from the homebrew/core tap
but you are trying to install it from the homebrew-ffmpeg/ffmpeg tap.
```

**`uninstall` 을 해야 합니다.** 그리고 uninstall 한 순간부터 설치가 끝날 때까지는
`ffmpeg` 명령이 아예 없습니다 — 다른 작업에 ffmpeg 를 쓰는 사람은 그 시간을 피해서 하세요.

> 되돌리려면 `brew install ffmpeg` 로 코어 버전이 다시 옵니다 (자막은 못 굽는 그 버전).

---

## 3. 환경 점검 프롬프트 (참가자가 AI에게 붙여넣기)

설치가 끝났는지 스스로 확인하게 할 때 씁니다. 터미널 결과를 읽고 다음 할 일을 알려줍니다.

```text
내 컴퓨터가 영상 자막 굽기를 할 수 있는 상태인지 확인해줘.
아래 네 줄을 터미널에 하나씩 돌리고, 결과를 내가 붙여줄게.
결과를 보고 "준비 완료" 또는 "무엇을 더 해야 하는지"만 알려줘. 설명은 짧게.

  ffmpeg -version | head -1
  ffmpeg -filters | grep -E ' ass | subtitles '
  df -h / | tail -1
  fc-list | grep -ci -E "noto|pretendard|applegothic"

판정 기준:
- 2번에서 ass 와 subtitles 두 줄이 나와야 함. 안 나오면 ffmpeg 재설치 필요
- 3번에서 여유 공간이 10GB 미만이면 공간 확보 필요
- 4번이 0 이면 한글 폰트 설치 필요
```

볼트를 이미 내려받았으면 이게 더 빠릅니다.

```bash
bash bin/doctor.sh
```

`[X]` 가 하나라도 있으면 그걸 고치기 전에는 편집이 안 됩니다.

---

## 4. 진행자 체크리스트

### 2회차 3일 전
- [ ] 위 2회차 공지 발송
- [ ] 맥 사용자 수 파악 — 전원이 90분 컴파일을 돌려야 합니다

### 2회차 전날
- [ ] 참가자별 `ffmpeg -filters` 결과 수거 — **안 보낸 사람이 당일에 막힙니다**
- [ ] 못 한 사람에게는 **같이 돌릴 시간**을 잡아주거나, 2회차에서 짝을 지어주세요

### 2회차 당일
- [ ] 여유 디스크 10GB 확인
- [ ] 영문 작업 폴더 만들기 — `mkdir -p ~/reels/work`
- [ ] 원본 영상 이름을 `source.mp4` 처럼 단순하게

> 설치를 못 끝낸 사람이 절반이면 2회차를 **온톨로지 보강 + 클립 선정(P3)** 으로 바꾸세요.
> 그 둘은 ffmpeg 없이 됩니다. 굽기는 3회차로 미루는 게 낫습니다.
