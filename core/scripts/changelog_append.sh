#!/usr/bin/env bash
# CHANGELOG 자동 한 줄 기록 (Stop 훅용)
# 역할: 세션이 끝날 때 변경된 소스 파일 목록을 CHANGELOG.md 에 한 줄 남긴다.
#
# WHY 스크립트로 뺐나: settings.json 인라인 한 줄로는 중복 억제 조건을 넣기 어렵다.
#
# 중복 억제가 핵심이다. 기준이 `git diff HEAD` (미커밋 변경 전체)라서, 커밋하기 전까지는
# 매 Stop 마다 같은 목록이 나온다. 억제가 없으면 같은 줄이 수십 번 쌓인다
# (실제로 600줄 중 고유 52줄, 최다 중복 51회까지 갔다).
# 그래서 마지막 줄과 같으면 쓰지 않는다.

set -u

REPO="${CLAUDE_PROJECT_DIR:-}"
[ -z "$REPO" ] && exit 0
[ -d "$REPO/.git" ] || [ -f "$REPO/.git" ] || exit 0

CHANGELOG="$REPO/CHANGELOG.md"
DATE=$(date +%Y-%m-%d)

# 변경된 소스 파일 (경로 제거, 파일명만)
# 확장자로 거르지 않는다. 스택마다 소스 확장자가 달라서 목록을 박으면 그 스택 밖에서는 아무것도 안 남는다.
# 하네스 자신의 파일(.claude/)과 문서(.md)만 뺀다.
FILES=$(git -C "$REPO" diff --name-only HEAD 2>/dev/null | grep -vE '^\.claude/|\.md$' | sed 's|.*/||' | sort -u)
[ -z "$FILES" ] && exit 0

TOTAL=$(printf '%s\n' "$FILES" | wc -l | tr -d ' ')
SHOWN=$(printf '%s\n' "$FILES" | head -3 | paste -sd ',' -)

# 3개를 넘으면 잘린 사실을 남긴다. 잘린 줄을 그냥 두면 나중에 "이때 3개만 고쳤구나" 로 잘못 읽힌다.
if [ "$TOTAL" -gt 3 ]; then
  LINE="[$DATE] [auto] [수정: ${SHOWN} 외 $((TOTAL - 3))개]"
else
  LINE="[$DATE] [auto] [수정: ${SHOWN}]"
fi

# 마지막 줄과 동일하면 기록하지 않는다 (커밋 전 반복 Stop 억제)
if [ -f "$CHANGELOG" ]; then
  LAST=$(tail -1 "$CHANGELOG" 2>/dev/null)
  [ "$LAST" = "$LINE" ] && exit 0
fi

echo "$LINE" >> "$CHANGELOG" 2>/dev/null || true
exit 0
