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
# 러너가 리포트를 쓰기 전에 죽은 경우. testcase 0개라고 no_flow 로 덮으면 비-UI 경로에서 SUCCESS 가 된다.
mkdir -p "$PROBE/r"
RG_SESSION="$PROBE/r" RG_REPORT="$PROBE/r/none.xml" RG_INSTALL=null RG_REPLAY=false RG_SKIPPED=false \
  RG_NOFLOW=false RG_EEXIT=1 python3 core/scripts/parse_runner.py >/dev/null 2>&1
chk "리포트 없는 재생 실패는 실패로 남는다" "False False" "$(python3 -c "import json,sys;r=json.load(open(sys.argv[1]));print(r['replay_success'],r['no_flow'])" "$PROBE/r/runner.json" 2>/dev/null)"
chk "리포트 없음 표시 (report_found)" "False" "$(python3 -c "import json,sys;print(json.load(open(sys.argv[1])).get('report_found'))" "$PROBE/r/runner.json" 2>/dev/null)"
# 게이트를 끈 프로젝트도 builder 는 빌드 명령을 받아야 한다. 게이트 쪽은 여전히 SKIP 이어야 한다.
mkdir -p "$PROBE/off"
printf '{"runtime_gate": false, "adapter_inline": {"name": "probe", "build": "true"}}' > "$PROBE/off/p.json"
chk "게이트 꺼도 빌드 명령 전달" "2 true" "$(eval "$(HARNESS_PROJECT_JSON="$PROBE/off/p.json" python3 core/scripts/harness_config.py --export)"; echo "${HC_OK:-} ${HC_BUILD_CMD:-}")"
( export HARNESS_PROJECT_JSON="$PROBE/off/p.json"; bash core/scripts/runtime_gate.sh "$PROBE/off/s" "$PROBE" >/dev/null 2>&1 )
chk "게이트 꺼짐은 SKIP (exit 0)" 0 "$?"
chk "게이트 꺼짐 skip_reason" "gate_disabled" "$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['skip_reason'])" "$PROBE/off/s/runner.json" 2>/dev/null)"
# 어댑터가 깨져 있어도 끄기로 한 게이트는 SKIP 이다. 여기서 exit 3 이 나면 끈 프로젝트가 매번 멈춘다.
printf '{"runtime_gate": false, "adapter": "없는어댑터"}' > "$PROBE/off/bad.json"
chk "게이트 꺼짐 + 어댑터 없음도 HC_OK=2" 2 "$(eval "$(HARNESS_PROJECT_JSON="$PROBE/off/bad.json" python3 core/scripts/harness_config.py --export)"; echo "${HC_OK:-}")"
# 웹 어댑터를 실제 게이트로 돌린다. 러너는 인자를 기록하고 리포트만 쓰는 가짜로 바꾼다.
# 원래 어댑터는 리포트를 파일로 안 남겨 항상 0/0 이었고, 태그를 콤마로 넘겨 아무것도 안 골랐고,
# import 경로 '@playwright/test' 를 도메인으로 읽었다.
W="$PROBE/web"; mkdir -p "$W/.claude" "$W/tests" "$PROBE/bin"
cp -r adapters "$W/.claude/"
printf '{"adapter": "node-vite-playwright", "e2e": {"dir": "tests"}}' > "$W/.claude/project.json"
printf '{"name": "probe"}' > "$W/package.json"
printf "import { test } from '@playwright/test'\ntest('a', { tag: '@auth' }, async () => {})\ntest('b', { tag: ['@cart'] }, async () => {})\n" > "$W/tests/a.spec.ts"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$@" > "%s/npx.args"\nprintf "<testsuites><testsuite><testcase name=\\"a\\"/></testsuite></testsuites>" > "$PLAYWRIGHT_JUNIT_OUTPUT_NAME"\n' "$PROBE" > "$PROBE/bin/npx"
chmod +x "$PROBE/bin/npx"
chk "웹 태그 판독 (import 경로 제외)" "auth,cart" "$(HARNESS_PROJECT_JSON="$W/.claude/project.json" python3 core/scripts/e2e_tags.py --coverage "$W/tests")"
( export HARNESS_PROJECT_JSON="$W/.claude/project.json" PATH="$PROBE/bin:$PATH"; bash core/scripts/runtime_gate.sh "$PROBE/web/s" "$W" "auth,cart" >/dev/null 2>&1 )
chk "웹 게이트 종료코드" 0 "$?"
chk "웹 태그 여러 개는 정규식 | 로" 1 "$(grep -c '^--grep=@(auth|cart)' "$PROBE/npx.args" 2>/dev/null)"
chk "웹 리포트가 파일로 남는다" "True 1" "$(python3 -c "import json,sys;r=json.load(open(sys.argv[1]));print(r.get('report_found'),r.get('flows_total'))" "$PROBE/web/s/runner.json" 2>/dev/null)"
# 올린 것은 어느 경로로 끝나든 내린다. 서버를 띄운 채 끝나면 다음 게이트가 포트 충돌로 죽는다.
# 배포 실패는 exit 2 여야 한다. 예전에는 tail 의 종료값을 읽어 설치 실패가 성공으로 기록됐다.
T="$PROBE/td"; mkdir -p "$T/tests"; printf '{}' > "$T/package.json"; printf "test('a', { tag: '@x' })\n" > "$T/tests/a.spec.ts"
td_case() {  # 인자: 이름 배포명령 재생명령
  printf '{"adapter_inline": {"name": "td", "detect": ["package.json"], "build": "true", "deploy": "%s", "teardown": "touch down_%s", "e2e": {"dir_default": "tests", "file_globs": ["*.spec.ts"], "command": "%s", "tag_option": "", "report_format": "junit-xml"}}}' "$2" "$1" "$3" > "$T/p_$1.json"
  ( export HARNESS_PROJECT_JSON="$T/p_$1.json"; bash core/scripts/runtime_gate.sh "$T/s_$1" "$T" >/dev/null 2>&1 ); echo "$? $([ -e "$T/down_$1" ] && echo down || echo up)"
}
chk "내리기: 재생 통과" "0 down" "$(td_case ok true true)"
chk "내리기: 재생 실패" "1 down" "$(td_case rf true false)"
chk "내리기: 배포 실패도 exit 2 와 내리기" "2 down" "$(td_case df false true)"
# 읽기 전용 에이전트는 json 을 반환만 한다. 저장기가 깨진 반환과 필수 키 누락을 막아야 한다.
printf 'x\n```json\n{"step_id": 1, "build_success": true}\n```\n' | python3 core/scripts/save_result.py "$PROBE/b.json" step_id,build_success >/dev/null
chk "결과 저장: 정상 반환" 0 "$?"
printf '```json\n{"step_id": 1}\n```\n' | python3 core/scripts/save_result.py "$PROBE/c.json" step_id,build_success >/dev/null
chk "결과 저장: 필수 키 누락은 거부" 1 "$?"
chk "결과 저장: 거부하면 파일을 안 남긴다" "no" "$([ -e "$PROBE/c.json" ] && echo yes || echo no)"
# 도구에 쓰기 권한이 없는 에이전트가 결과를 파일로 쓰라는 지시를 받으면 권한과 지시가 모순된다
chk "쓰기 권한 없는 에이전트의 파일 저장 지시" 0 "$(for a in explorer builder verifier; do grep -lE 'Write 도구로 저장|json. 에 저장|\.json` 에 (성공 )?기록|json` 업데이트' core/agents/$a/AGENT.md; done 2>/dev/null | wc -l | tr -d ' ')"
# core 는 어느 스택도 전제하지 않는다. 걷어 낸 스택 전용 표현이 다시 들어오면 잡는다.
# 예시로 여러 스택을 나란히 드는 것은 괜찮다. 여기 적은 것은 한 스택을 전제로 한 문장에만 나오던 말이다.
# 선택지로 보여 줄 것은 templates/choices.md 에 둔다.
STACK_RESIDUE='MVVM|context7|패킷|주 스레드|fully qualified|app/src/main/java|github\.com/android|android-refs|Obsidian|PC-?Mobile|공유 이벤트|앱 실행|탭:|ui_observable|tap_element|주소록'
chk "core 안 스택 전제 잔재" 0 "$(grep -rEo "$STACK_RESIDUE" core 2>/dev/null | wc -l | tr -d ' ')"
echo "[7] 셸/파이썬 문법"
for f in core/scripts/*.sh tools/*/*.sh ./*.sh; do bash -n "$f" 2>/dev/null || { echo "  FAIL $f"; fail=1; }; done
# 셸에서 $VAR 뒤에 한글이 바로 붙으면 변수명의 일부로 파싱된다 ($n개 -> n개).
# 한글 주석을 쓰는 저장소라서 반드시 걸린다. 중괄호로 감싸야 한다.
chk "\$변수 뒤 한글 (중괄호 누락)" 0 "$(grep -rlP '\$[A-Za-z_][A-Za-z0-9_]*[가-힣]' --include='*.sh' . 2>/dev/null | wc -l | tr -d ' ')"
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
