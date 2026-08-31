#!/usr/bin/env bash
# 저장소 자기 검사 (결정적)
# 역할: core/ 가 이 저장소의 절대 원칙을 지키고 있는지 명령으로 확인한다.
#
# 왜 스크립트인가: "고유어를 지웠다" 는 눈으로 세면 매번 다르게 센다.
# 통과 기준을 명령으로 고정해 두면 다음 사람이 같은 기준으로 확인할 수 있고,
# 고유어가 다시 들어오는 순간 여기서 걸린다.
#
# 금지어 목록은 이 파일에 적지 않는다.
# 금지어가 곧 그 회사의 제품명과 식별자라서, 검사 스크립트에 적으면
# "고유어를 지웠다" 면서 검사기에 고유어를 남기는 꼴이 된다.
# .denylist 파일에 한 줄에 하나씩 적고 그 파일은 커밋하지 않는다 (.gitignore).
# 파일이 없으면 그 검사만 건너뛴다. 건너뛴 사실을 SKIP 으로 출력한다 - 통과로 세지 않는다.
#
# 사용법: bash check.sh   (종료코드 0 통과 / 1 실패)
cd "$(dirname "$0")"
REPO="$(pwd)"

fail=0
skipped=0
chk() { # 이름 기대 실제
  if [ "$2" = "$3" ]; then printf "  OK   %-46s %s\n" "$1" "$3"
  else printf "  FAIL %-46s 기대=%s 실제=%s\n" "$1" "$2" "$3"; fail=1; fi
}
skip() { printf "  SKIP %-46s %s\n" "$1" "$2"; skipped=$((skipped+1)); }

# .denylist 를 정규식 하나로 합친다 (빈 줄과 # 주석 무시)
DENY=""
if [ -f .denylist ]; then
  DENY=$(grep -vE '^\s*(#|$)' .denylist | paste -sd'|' -)
fi

echo "[1] core 에 회사 식별자"
if [ -n "$DENY" ]; then
  chk "금지어 건수" 0 "$(grep -rEoiI "$DENY" core tools adapters templates docs 2>/dev/null | wc -l | tr -d ' ')"
else
  skip "금지어 검사" ".denylist 없음 (.denylist.example 참고)"
fi
echo "[2] core 에 하드코딩된 스택 명령/개인 경로"
chk "스택 명령 건수" 0 "$(grep -rEoI 'gradlew |maestro test|adb (devices|logcat)|/Users/[a-z]+/' core | wc -l | tr -d ' ')"
echo "[3] 에이전트 개명"
if [ -n "$DENY" ]; then
  chk "이름에 금지어가 든 에이전트" 0 "$(ls core/agents | grep -EciI "$DENY" | tr -d ' ')"
else
  skip "에이전트 이름 검사" ".denylist 없음"
fi
chk "에이전트 개수" 13 "$(ls core/agents | wc -l | tr -d ' ')"
chk "frontmatter name 불일치" 0 "$(for d in core/agents/*/; do n=$(basename $d); m=$(grep -m1 '^name:' $d/AGENT.md | sed 's/name: *//'); [ "$n" = "$m" ] || echo x; done | wc -l | tr -d ' ')"
echo "[4] 폐기된 키 이름 재발 (생산자와 소비자가 갈리면 집계와 분기가 조용히 깨진다)"
# 제품 용어가 든 구 키(공유 이벤트 관련)는 여기 적지 않는다. [1] 의 금지어 검사가 이미 잡는다.
chk "구 키 잔존" 0 "$(grep -rEoI 'new_compose_screen|testtag_map|MISSING_TESTTAG|COMPOSE_DOD|COMPOSE_RULE|JAVA_COMPAT|maestro_exit_code' core | wc -l | tr -d ' ')"
echo "[5] 설정 파일 문법"
for f in adapters/*.json templates/project.json.tmpl; do
  python3 -c "import json;json.load(open('$f'))" 2>/dev/null && printf "  OK   %-46s json\n" "$f" || { printf "  FAIL %-46s json 깨짐\n" "$f"; fail=1; }
done
echo "[6] 설정 없을 때의 안전 기본값"
chk "domains_for.py 출력" "ALL" "$(cd /tmp && python3 "$REPO/core/scripts/domains_for.py" a/b/c.txt)"
chk "domains_for.py 종료코드" 0 "$(cd /tmp && python3 "$REPO/core/scripts/domains_for.py" a/b/c.txt >/dev/null 2>&1; echo $?)"
# 안 채운 템플릿을 그대로 쓰면 규칙이 있는 것처럼 보인다. 그때도 ALL 이어야 한다.
chk "빈 템플릿으로도 ALL" "ALL" "$(HARNESS_PROJECT_JSON="$REPO/templates/project.json.tmpl" python3 "$REPO/core/scripts/domains_for.py" src/features/chat/A.ts)"
PROBE="$(mktemp -d)"
( unset HARNESS_PROJECT_JSON; bash core/scripts/runtime_gate.sh "$PROBE/s" "$PROBE" >/dev/null 2>&1 )
chk "runtime_gate.sh 종료코드(설정없음)" 3 "$?"
chk "runner.json gate_error" "bad_config" "$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['gate_error'])" "$PROBE/s/runner.json" 2>/dev/null)"
chk "dod_check.py 종료코드(규칙없음)" 2 "$(python3 core/scripts/dod_check.py x >/dev/null 2>&1; echo $?)"
echo "[7] 셸/파이썬 문법"
for f in core/scripts/*.sh; do bash -n "$f" 2>/dev/null || { echo "  FAIL $f"; fail=1; }; done
for f in core/scripts/*.py; do python3 -c "import ast,io;ast.parse(io.open('$f',encoding='utf-8').read())" 2>/dev/null || { echo "  FAIL $f"; fail=1; }; done
[ $fail = 0 ] && echo "  OK   전 스크립트 문법"
echo
rm -rf "$PROBE"
if [ $fail != 0 ]; then
  echo "실패 있음"
elif [ $skipped != 0 ]; then
  echo "통과 (단 검사 $skipped 건을 건너뛰었다. .denylist 를 만들면 전부 확인한다)"
else
  echo "전체 통과"
fi
exit $fail
