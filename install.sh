#!/usr/bin/env bash
# 하네스 설치기 (결정적)
# 역할: core/ 와 adapters/ 를 대상 프로젝트의 .claude/ 로 복사한다.
#
# cp -r 를 대신 쳐 주는 것이 목적이 아니다. cp 가 말해 주지 않는 두 가지를 말하는 것이 목적이다.
#   1. 대상에서 고친 파일을 덮으려 하는가 (역수출 안 한 수정이 조용히 사라지는 것을 막는다)
#   2. project.json 을 덮으려 하는가 (채워 둔 설정이 날아가면 게이트가 통째로 멈춘다)
# 둘 다 되돌릴 수 없으므로 기본적으로 막고, 무엇이 걸렸는지 보여준 뒤 사람이 결정하게 한다.
#
# 사용법: install.sh <대상 프로젝트> [--force] [--dry-run]
#   --force    대상에서 고친 파일을 덮어쓴다 (사라질 목록을 먼저 보고 결정할 것)
#   --dry-run  무엇이 일어날지만 보여주고 아무것도 쓰지 않는다
#
# 종료 코드:
#   0  설치 완료 (또는 dry-run 정상)
#   1  대상에서 고친 파일이 있어 멈춤 (--force 로 진행 가능)
#   3  인자/경로 오류

set -u

HARNESS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET=""
FORCE=0
DRY=0

for a in "$@"; do
  case "$a" in
    --force)   FORCE=1 ;;
    --dry-run) DRY=1 ;;
    -*)        echo "모르는 옵션: $a"; exit 3 ;;
    *)         TARGET="$a" ;;
  esac
done

if [ -z "$TARGET" ]; then
  echo "ERROR: 대상 프로젝트 경로 누락. 사용법: install.sh <대상 프로젝트> [--force] [--dry-run]"
  exit 3
fi
if [ ! -d "$TARGET" ]; then
  echo "ERROR: 대상 경로가 없다: $TARGET"
  exit 3
fi
TARGET="$(cd "$TARGET" && pwd)"
if [ "$TARGET" = "$HARNESS" ]; then
  echo "ERROR: 하네스 저장소 자신에는 설치하지 않는다."
  exit 3
fi

DEST="$TARGET/.claude"
say() { [ "$DRY" = "1" ] && echo "  (dry-run) $*" || echo "  $*"; }

# 옮길 것: <원본> <대상 하위 경로>
# setup 은 /setup 이 읽는 에이전트별 세팅 설명서, templates 는 선택지 목록과 문서 뼈대다.
PAIRS="core/agents:agents core/commands:commands core/scripts:scripts core/setup:setup adapters:adapters templates:templates"

# 1. 대상에서 고친 파일 찾기 (덮으면 사라지는 것)
CHANGED=""
for pair in $PAIRS; do
  src="$HARNESS/${pair%%:*}"
  dst="$DEST/${pair##*:}"
  [ -d "$dst" ] || continue
  while IFS= read -r f; do
    rel="${f#$dst/}"
    [ -f "$src/$rel" ] || { CHANGED="$CHANGED\n  ${pair##*:}/$rel (하네스에 없는 파일)"; continue; }
    # 에이전트의 tools 줄은 /setup 이 붙인 외부 도구(agent_tools)가 반영된 자리라 비교에서 뺀다.
    # 설치 뒤 apply_agent_tools.py 가 다시 반영하므로 사라지지 않는다.
    if [[ "$rel" == */AGENT.md ]]; then
      diff -q <(grep -vE '^tools(_extra)?:' "$f") <(grep -vE '^tools(_extra)?:' "$src/$rel") >/dev/null \
        || CHANGED="$CHANGED\n  ${pair##*:}/$rel"
    else
      cmp -s "$f" "$src/$rel" || CHANGED="$CHANGED\n  ${pair##*:}/$rel"
    fi
  done < <(find "$dst" -type f \( -name '*.md' -o -name '*.py' -o -name '*.sh' -o -name '*.json' -o -name '*.tmpl' \) 2>/dev/null)
done

if [ -n "$CHANGED" ] && [ "$FORCE" = "0" ]; then
  echo "멈춤: 대상에서 하네스 원본과 다른 파일이 있다. 덮으면 이 수정은 사라진다."
  printf "%b\n" "$CHANGED"
  echo
  echo "여기서 고친 것이면 하네스로 먼저 옮긴다 (역수출). 그 뒤에 다시 설치한다."
  echo "그냥 덮어도 되면 --force 를 준다."
  exit 1
fi

# 2. 복사
echo "설치: $HARNESS -> $DEST"
for pair in $PAIRS; do
  src="$HARNESS/${pair%%:*}"
  sub="${pair##*:}"
  n=$(find "$src" -type f | grep -v __pycache__ | wc -l | tr -d ' ')
  say "$sub/  (${n}개)"
  if [ "$DRY" = "0" ]; then
    mkdir -p "$DEST/$sub"
    (cd "$src" && find . -type f ! -path '*__pycache__*' -print0) \
      | (cd "$src" && xargs -0 -I{} sh -c 'mkdir -p "$1/$(dirname "{}")" && cp "{}" "$1/{}"' _ "$DEST/$sub")
  fi
done

# 3. project.json 은 있으면 절대 덮지 않는다. 채워 둔 설정이 날아가면 게이트가 통째로 멈춘다.
if [ -f "$DEST/project.json" ]; then
  say "project.json  이미 있음 -> 건드리지 않는다"
else
  say "project.json  템플릿에서 생성 (채워야 게이트가 돈다)"
  [ "$DRY" = "0" ] && cp "$HARNESS/templates/project.json.tmpl" "$DEST/project.json"
fi

# 4. 실행 상태는 커밋하지 않는다
GI="$TARGET/.gitignore"
# 실행 상태와, 하네스 파이썬 스크립트가 돌면서 남기는 바이트코드 캐시. 둘 다 커밋할 것이 아니다.
# 캐시를 빼 두지 않으면 대상 프로젝트 git 에 __pycache__ 가 뜬다.
# 마지막 줄에 개행이 없으면 붙여 쓴 패턴이 앞 줄과 합쳐진다
[ "$DRY" = "0" ] && [ -s "$GI" ] && [ -n "$(tail -c1 "$GI")" ] && echo >> "$GI"
for pat in '.claude/state/' '.claude/**/__pycache__/'; do
  if [ -f "$GI" ] && grep -qxF "$pat" "$GI" 2>/dev/null; then
    say ".gitignore  이미 $pat 있음"
  else
    say ".gitignore  $pat 추가"
    [ "$DRY" = "0" ] && printf '%s\n' "$pat" >> "$GI"
  fi
done

[ "$DRY" = "1" ] && { echo; echo "dry-run 이므로 아무것도 쓰지 않았다."; exit 0; }

# 세팅 때 붙인 외부 도구를 다시 반영한다. 복사가 tools 줄을 원본으로 되돌렸기 때문이다.
(cd "$TARGET" && python3 .claude/scripts/apply_agent_tools.py >/dev/null 2>&1) || echo "  주의: agent_tools 반영 실패 (python3 .claude/scripts/apply_agent_tools.py 로 확인)"

# 5. 설치 직후 상태를 스스로 확인해서 보여준다
echo
echo "확인:"
DOM=$(cd "$TARGET" && python3 .claude/scripts/domains_for.py src/x.txt 2>/dev/null)
echo "  도메인 매핑    $DOM $([ "$DOM" = "ALL" ] && echo '(아직 규칙 없음 = 매번 전체 회귀)')"
# 진짜 세션과 같은 깊이에 둔다. 메트릭 기록기가 세션 경로 기준으로 출력 위치를 잡기 때문에
# 얕은 경로로 재보면 .claude/ 에 파일이 흘러나온다.
(cd "$TARGET" && bash .claude/scripts/runtime_gate.sh .claude/state/sessions/_probe "" >/dev/null 2>&1)
case "$?" in
  0) echo "  런타임 게이트  통과 또는 SKIP" ;;
  3) echo "  런타임 게이트  exit 3 (설정 필요. 통과가 아니다)" ;;
  *) echo "  런타임 게이트  exit $?" ;;
esac
rm -rf "$TARGET/.claude/state/sessions/_probe"

echo
echo "다음: 이 프로젝트에서 Claude Code 를 열고 /setup 을 실행한다."
echo "      에이전트를 하나씩 소개하며 설정, 도메인 지식, 에이전트별 사정을 대화로 채운다."
