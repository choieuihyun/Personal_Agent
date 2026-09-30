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

# 은퇴한 파일: 하네스에서 없앤 것. 예전에 설치된 대상에 남아 있으면 복사 전에 지운다.
# 남겨 두면 없는 에이전트를 부르는 커맨드가 남는다. 은퇴한 것은 하네스가 더 이상 책임지지 않으므로
# 대상에서 고친 흔적이 있어도 지우고, 지운 목록은 보여 준다.
RETIRED="commands/modernize.md commands/log.md scripts/changelog_append.sh agents/implementer-modernize agents/researcher setup/implementer-modernize.md setup/researcher.md"

# 1. 대상에서 고친 파일 찾기 (덮으면 사라지는 것)
# 기준은 "지금의 하네스 원본" 이 아니라 "그때 설치한 것" 이다 (.claude/.harness-manifest).
# 원본과 비교하면 하네스가 갱신된 파일까지 고친 파일로 잡혀, 업그레이드할 때마다 멈춘다.
# 기록이 없는 예전 설치본만 원본과 비교한다.
CHANGED=""
NO_MANIFEST=0
if [ -d "$DEST" ]; then
  while IFS= read -r line; do
    [ "$line" = "#NO_MANIFEST" ] && { NO_MANIFEST=1; continue; }
    skip=0
    for r in $RETIRED; do case "$line" in "$r"|"$r"/*|"$r "*) skip=1 ;; esac; done
    [ "$skip" = "1" ] || CHANGED="$CHANGED\n  $line"
  done < <(python3 "$HARNESS/core/scripts/harness_manifest.py" changed "$DEST" "$HARNESS" $PAIRS)
fi

if [ -n "$CHANGED" ] && [ "$FORCE" = "0" ]; then
  echo "멈춤: 설치한 뒤 대상에서 고친 파일이 있다. 덮으면 이 수정은 사라진다."
  printf "%b\n" "$CHANGED"
  echo
  if [ "$NO_MANIFEST" = "1" ]; then
    echo "주의: 설치 기록(.claude/.harness-manifest)이 없는 예전 설치본이라 지금의 하네스 원본과 비교했다."
    echo "      하네스가 갱신한 파일도 위에 섞여 있다. 대상에서 직접 고친 적이 없으면 --force 로 진행해도 된다."
    echo "      이번 설치부터 기록이 남아 다음에는 실제로 고친 파일만 보인다."
  else
    echo "여기서 고친 것이면 하네스로 먼저 옮긴다 (역수출). 그 뒤에 다시 설치한다."
    echo "그냥 덮어도 되면 --force 를 준다."
  fi
  exit 1
fi

for r in $RETIRED; do
  if [ -e "$DEST/$r" ]; then
    say "은퇴: $r 제거"
    [ "$DRY" = "0" ] && rm -rf "${DEST:?}/$r"
  fi
done

# 버전: 어느 하네스 커밋에서 어느 커밋으로 올라가는지, 그 사이 무엇이 바뀌었는지 보여 준다.
NEW_COMMIT=$(git -C "$HARNESS" rev-parse HEAD 2>/dev/null || true)
OLD_COMMIT=$(python3 "$HARNESS/core/scripts/harness_manifest.py" meta "$DEST" harness_commit 2>/dev/null || true)
DIRTY=$(git -C "$HARNESS" status --porcelain -- core adapters templates 2>/dev/null | head -1)
if [ -n "$NEW_COMMIT" ]; then
  if [ -n "$OLD_COMMIT" ] && [ "$OLD_COMMIT" != "$NEW_COMMIT" ]; then
    N=$(git -C "$HARNESS" rev-list --count "$OLD_COMMIT..$NEW_COMMIT" 2>/dev/null || echo "?")
    echo "하네스 ${OLD_COMMIT:0:7} -> ${NEW_COMMIT:0:7} (그 사이 ${N}건)"
    git -C "$HARNESS" log --oneline "$OLD_COMMIT..$NEW_COMMIT" 2>/dev/null | head -15 | sed 's/^/  /'
  elif [ -z "$OLD_COMMIT" ]; then
    echo "하네스 ${NEW_COMMIT:0:7} 설치"
  else
    echo "하네스 ${NEW_COMMIT:0:7} (이미 이 버전)"
  fi
  [ -n "$DIRTY" ] && echo "  주의: 하네스 저장소에 커밋 안 된 변경이 있다. 설치 기록의 커밋과 실제 내용이 다를 수 있다"
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

# 예전 설치본에서 바이트코드 캐시가 이미 커밋돼 있으면 .gitignore 로는 안 빠진다. 알리기만 한다.
# 대상의 git 기록을 설치기가 바꾸지 않는다.
TRACKED=$(cd "$TARGET" && git ls-files .claude 2>/dev/null | grep -c '__pycache__/' || true)
if [ "${TRACKED:-0}" != "0" ]; then
  echo "  주의: .claude 아래 __pycache__ 파일 ${TRACKED}개가 git 에 올라가 있다. 스크립트가 돌 때마다 변경으로 뜬다."
  echo "        빼려면: git rm -r --cached \$(git ls-files .claude | grep __pycache__/)"
fi

# 설치 기록. 다음 재설치 때 "대상에서 고친 파일" 을 가리는 기준이다.
HM_HARNESS_COMMIT="$NEW_COMMIT" HM_HARNESS_PATH="$HARNESS" HM_HARNESS_REMOTE="$(git -C "$HARNESS" remote get-url origin 2>/dev/null || true)" \
  HM_INSTALLED_AT="$(date +%Y-%m-%dT%H:%M:%S)" \
  python3 "$HARNESS/core/scripts/harness_manifest.py" write "$DEST" $(for p in $PAIRS; do printf '%s ' "${p##*:}"; done)

# 세팅 때 붙인 외부 도구를 다시 반영한다. 복사가 tools 줄을 원본으로 되돌렸기 때문이다.
(cd "$TARGET" && python3 .claude/scripts/apply_agent_tools.py >/dev/null 2>&1) || echo "  주의: agent_tools 반영 실패 (python3 .claude/scripts/apply_agent_tools.py 로 확인)"

# 5. 설치 직후 상태를 스스로 확인해서 보여준다
# 설정을 읽을 수 있는지만 본다. 게이트를 실제로 돌리지 않는다.
# 설정이 채워진 프로젝트에서 게이트를 돌리면 서버를 띄우고 테스트를 실행한다. 설치가 할 일이 아니다.
echo
echo "확인:"
CFG=$(cd "$TARGET" && python3 .claude/scripts/harness_config.py --export 2>/dev/null)
HC_OK=$(printf '%s\n' "$CFG" | sed -n 's/^HC_OK=//p' | tr -d "'")
MISS=$(printf '%s\n' "$CFG" | sed -n 's/^HC_MISSING=//p' | tr -d "'")
case "$HC_OK" in
  1) echo "  설정           읽힘 (게이트 사용)${MISS:+. 안 채운 빈칸: $MISS}" ;;
  2) echo "  설정           읽힘 (게이트 끔)" ;;
  *) echo "  설정           아직 비어 있음. /setup 으로 채운다 (이 상태로는 게이트가 exit 3 으로 멈춘다)" ;;
esac
DOM=$(cd "$TARGET" && python3 .claude/scripts/domains_for.py --self-check 2>/dev/null | head -1)
echo "  도메인 규칙    ${DOM:-확인 불가}"
# 하네스에 새로 생긴 설정 키. project.json 은 덮지 않으므로 새 키는 저절로 들어가지 않는다.
NEWKEYS=$(python3 - "$HARNESS/templates/project.json.tmpl" "$DEST/project.json" <<'PYK' 2>/dev/null
import json, sys
t, p = (json.load(open(f)) for f in sys.argv[1:3])
miss = [k for k in t if k not in p]
miss += ["%s.%s" % (k, s) for k in t if isinstance(t[k], dict) and isinstance(p.get(k), dict) for s in t[k] if s not in p[k]]
print(" ".join(miss))
PYK
)
if [ -n "$NEWKEYS" ]; then
  echo "  새 설정 키     $NEWKEYS"
  echo "                 이 프로젝트 project.json 에 아직 없다. /setup 을 다시 돌려 '비운 것만 채우기' 를 고른다"
fi

echo
if [ "$HC_OK" = "1" ] || [ "$HC_OK" = "2" ]; then
  echo "다음: 바로 /fix, /feature 를 쓸 수 있다. 세팅을 바꾸거나 빈칸을 채우려면 /setup."
else
  echo "다음: 이 프로젝트에서 Claude Code 를 열고 /setup 을 실행한다."
  echo "      에이전트를 하나씩 소개하며 설정, 도메인 지식, 에이전트별 사정을 대화로 채운다."
fi
