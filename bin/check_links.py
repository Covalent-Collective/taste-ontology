#!/usr/bin/env python3
"""볼트의 끊긴 위키링크를 찾습니다.

    python3 bin/check_links.py .              # 볼트 루트에서
    python3 bin/check_links.py ~/ontology

설치할 건 없습니다. 맥·리눅스에는 python3 가 들어 있고, 윈도우는 python.org 에서
한 번 설치하면 됩니다.

왜 grep 으로 하면 안 되나
-------------------------
`grep '\\[\\[...\\]\\]'` 로 세면 **거짓 양성이 쏟아집니다.** 옵시디언은 아래 세 자리의
위키링크를 링크로 만들지 않는데, 단순 정규식은 그걸 구분하지 못하기 때문입니다.

    ```                        ← 펜스 코드블록 안
    [[A]] -[관계]-> [[B]]
    ```
    `[[이렇게]]`                ← 인라인 코드 안
    <!-- 예: [[제작 윤리]] -->   ← HTML 주석 안

이 키트의 가이드와 예시 노트에는 관계 지도 예시가 코드블록으로 들어 있습니다.
그걸 안 걸러내면 멀쩡한 볼트가 "끊긴 링크 10종" 으로 보입니다. 실제로 그렇게
보고됐다가 다시 재서 5종으로 정정된 적이 있습니다. 숫자가 두 배로 틀립니다.

맥은 파일명을 NFD 로 저장하는 경우가 있어, 비교 전에 NFC 로 정규화합니다.
한글 파일명이 멀쩡해 보이는데 링크만 끊겨 보인다면 대개 이것 때문입니다.

끊긴 링크가 늘 문제는 아닙니다
------------------------------
- 아직 안 만든 개념 노드라면 **만들라는 신호**입니다 (가이드 2·3단계)
- `.mp4` 처럼 볼트 밖에 두는 파일이면 그대로 둬도 됩니다
- `[[  ]]` 같은 빈칸은 템플릿 자리표시자라 세지 않습니다
"""

import os
import re
import sys
import unicodedata
from collections import defaultdict

FENCE = re.compile(r'^(\s*)(```+|~~~+)')
LINK = re.compile(r'\[\[([^\]\[]+)\]\]')


def nfc(s):
    return unicodedata.normalize('NFC', s)


def strip_noise(text):
    """옵시디언이 링크로 만들지 않는 구간을 비웁니다."""
    out, in_fence, mark = [], False, None
    for line in text.split('\n'):
        m = FENCE.match(line)
        if m:
            token = m.group(2)
            if not in_fence:
                in_fence, mark = True, token[:3]
            elif token.startswith(mark):
                in_fence = False
            out.append('')
            continue
        out.append('' if in_fence else line)
    s = '\n'.join(out)
    s = re.sub(r'<!--.*?-->', '', s, flags=re.S)   # HTML 주석
    s = re.sub(r'%%.*?%%', '', s, flags=re.S)      # 옵시디언 주석
    s = re.sub(r'`[^`\n]*`', '', s)                # 인라인 코드
    return s


def walk(root):
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if not d.startswith('.')]
        for fn in filenames:
            if fn.endswith('.md'):
                yield os.path.join(dirpath, fn)


def main():
    root = os.path.expanduser(sys.argv[1] if len(sys.argv) > 1 else '.')
    if not os.path.isdir(root):
        sys.exit(f'폴더가 아닙니다: {root}')

    notes = {
        nfc(os.path.splitext(os.path.basename(p))[0]): os.path.relpath(p, root)
        for p in walk(root)
    }
    if not notes:
        sys.exit(f'.md 파일이 없습니다. 볼트 폴더가 맞나요? {root}')

    dangling, total = defaultdict(list), 0
    for p in walk(root):
        rel = os.path.relpath(p, root)
        with open(p, encoding='utf-8') as f:
            body = strip_noise(f.read())
        for m in LINK.finditer(body):
            # [[대상|별칭]] 과 표 안의 [[대상\|별칭]] 둘 다 처리
            target = re.split(r'\\?\|', m.group(1))[0].split('#')[0].strip()
            if not target:
                continue          # [[  ]] 빈칸은 템플릿 자리표시자
            total += 1
            if nfc(target) not in notes:
                dangling[nfc(target)].append(rel)

    print(f'노트 {len(notes)}개 · 실제 링크 {total}개')
    print(f'끊긴 링크 {len(dangling)}종')

    if not dangling:
        print('\n전부 연결돼 있습니다.')
        return 0

    print()
    for target, sources in sorted(dangling.items(), key=lambda kv: -len(kv[1])):
        where = ', '.join(sorted(set(sources)))
        print(f'  [[{target}]]  ← {where}')

    print('\n끊긴 링크가 늘 문제인 것은 아닙니다 —')
    print('  · 아직 안 만든 개념 노드라면 만들라는 신호입니다')
    print('  · .mp4 처럼 볼트 밖 파일이면 그대로 둬도 됩니다')
    return 0


if __name__ == '__main__':
    sys.exit(main())
