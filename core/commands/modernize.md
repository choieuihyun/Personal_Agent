# /modernize - 마이그레이션 파이프라인

레거시 스택에서 목표 스택으로의 전환을 수행한다.
무엇에서 무엇으로 가는지는 project.json 의 `stack` 이 정한다.

```
stack.legacy_language -> stack.language
stack.legacy_ui       -> stack.ui
```

**언어만 바꾸고 UI 는 두는 식의 반쪽 전환은 하지 않는다.** 두 축이 함께 설정돼 있으면 함께 옮긴다.
반쪽으로 끝내면 같은 화면을 두 번 만지게 되고, 두 번째 전환 때 첫 번째 결과를 다시 검증해야 한다.

기준 구조(참조 구현)는 `docs.conventions` 문서가 지정한다.
그 문서가 없으면 이미 전환이 끝난 화면 중 가장 최근 것을 기준으로 삼고, 무엇을 기준으로 삼았는지 보고한다.

explorer 는 기준 구조가 요구하는 파일들을 proposed_allowed_to_modify 에 포함시킨다.
researcher 는 목표 스택의 API 레퍼런스를 조사한다.
implementer-modernize 는 기준 구조를 참조한다.

explorer + researcher 를 병렬로 실행하고, 수정 전 baseline 시나리오를 확보한 뒤
implementer → (verifier + builder) → 런타임 게이트(E2E 재생) 루프를 돈다.
런타임 게이트 통과 후 반드시 문서화(documenter)로 마무리한다.
빌드 통과만으로는 끝내지 않는다. 실제 화면 동작(런타임 게이트)까지 검증해야 SUCCESS 다.

---

## 세션 초기화 (필수)

매 호출마다 고유 세션 디렉토리를 생성하여 동시 실행 격리를 보장한다.

Bash로 다음을 실행한다:

```bash
SESSION_ID="modernize-$(date +%Y%m%d-%H%M%S)-$(openssl rand -hex 2)"
SESSION_DIR=".claude/state/sessions/${SESSION_ID}"
mkdir -p "${SESSION_DIR}"
echo "[/modernize] SESSION_ID=${SESSION_ID}"
echo "[/modernize] SESSION_DIR=${SESSION_DIR}"
```

이후 본 문서의 `${SESSION_DIR}` 는 위에서 생성된 절대 경로다.
모든 상태 파일은 `${SESSION_DIR}` 하위에만 작성한다.

---

## 시작 전 준비

`${SESSION_DIR}/orchestrator.json`:

```json
{
  "version": 2,
  "session_id": "<SESSION_ID>",
  "session_dir": "<SESSION_DIR>",
  "command": "modernize",
  "step_id": 1,
  "updated_at": "<현재 시각 ISO 8601>",
  "status": "INIT",
  "attempt_count": 0,
  "allowed_to_modify": [],
  "forbidden_rules": [
    {"type": "glob", "value": "<project.json 의 forbidden_globs 를 그대로 옮긴다>"}
  ],
  "risk_flags": [],
  "risk_level": "LOW",
  "human_gate_required": false,
  "last_error_hash": null,
  "same_error_count": 0,
  "last_explorer_step": 0,
  "termination_reason": null,
  "runtime_attempt_count": 0,
  "flaky_retry_count": 0,
  "flow_fix_count": 0,
  "last_triage_category": null
}
```

`${SESSION_DIR}/implementer.json`: `{"recent_patches": []}`
`${SESSION_DIR}/builder.json`: `{"build_success": null, "error_hash": null, "error_files": [], "error_confidence": null}`
`${SESSION_DIR}/verifier.json`: `{"verification_passed": null, "findings": [], "summary": {"total": 0, "high": 0, "medium": 0, "low": 0}}`
`${SESSION_DIR}/runner.json`: `{"skipped": null, "no_flow": null, "install_success": null, "replay_success": null, "failed_flow": null, "screenshot_path": null, "gate_error": null}`
`${SESSION_DIR}/triage.json`: `{"category": null, "confidence": null, "next_action": null, "suspected_files": []}`

---

## 1단계: 탐색 + 리서치 (EXPLORING)

orchestrator.json status를 "EXPLORING"으로 업데이트한다.

**explorer와 researcher를 병렬로 호출한다.**
각 호출 프롬프트 상단에 반드시 다음을 명시한다:

```
session_dir: <SESSION_DIR>
```

explorer에게 전달:
- 마이그레이션 대상 파일/클래스 정보
- 현재 step_id

researcher에게 전달:
- 마이그레이션 종류: project.json 의 `stack` 값 (레거시 -> 목표, 언어와 UI 동시)
- 대상 클래스/화면 이름
- 사용할 라이브러리 또는 API 이름
- `docs.conventions` 가 가리키는 전환 절차 문서 (있으면)

두 에이전트 모두 완료될 때까지 기다린다.

### Orchestrator 판단

`${SESSION_DIR}/explorer-proposal.json` 을 읽어서:
1. forbidden_rules 필터링 적용
2. risk_level HIGH → Human Gate
3. orchestrator.json 업데이트

researcher 결과를 정리하여 implementer에게 전달할 레퍼런스로 준비한다.

---

## 1.5단계: baseline 시나리오 확보 (BASELINE)

마이그레이션으로 깨질 수 있는 사용자 동작을 수정 전에 시나리오로 박아둔다.
회귀를 잡으려면 시나리오가 수정 전 동작 기준이어야 한다 (수정 후 작성 시 자기충족 함정).
상세 절차는 project.json 의 `docs.e2e_guide` 를 따른다.

orchestrator.json status 를 "BASELINE" 으로 업데이트한다.

실행 대상 미연결 시 이 단계를 건너뛰고 사용자에게 보고한다 (이후 런타임 게이트도 SKIP 된다).

절차:
1. 대상 화면의 시나리오가 `e2e.dir` 에 이미 있으면 재사용하고 이 단계를 건너뛴다.
2. 없으면 현재(수정 전) 빌드가 올라간 상태에서 실제 화면을 조사해 셀렉터를 확인한다 (셀렉터 추측 금지).
3. 보존돼야 할 핵심 동작 1~3개를 텍스트 셀렉터로 작성한다 (수정 전엔 UI 식별자가 없다).
4. 현재 빌드에 1회 재생해 통과하는지 확인한다 (baseline 유효성 증명).
5. `<e2e.dir>/<화면명>` 으로 저장한다.

작성한 시나리오는 마이그레이션 후 런타임 게이트가 동작 보존을 검증하는 기준이 된다.

---

## 2단계: 마이그레이션 수정 (IMPLEMENTING)

orchestrator.json status를 "IMPLEMENTING"으로 업데이트한다.
attempt_count 1 증가.

**implementer-modernize 에이전트를 호출한다.**
호출 프롬프트 상단에 다음을 명시한다:

```
session_dir: <SESSION_DIR>
```

추가 전달 정보:
- 마이그레이션 작업 내용
- researcher가 조회한 API 레퍼런스 요약
- `docs.conventions` 의 전환 절차 (있으면)

**코드 출력 금지 규칙 (필수):**
- 변경 코드를 응답 텍스트에 출력하지 않는다
- 모든 코드 변경은 Write/Edit 도구로 파일에 직접 반영한다
- 대용량 파일은 500줄 이하 단위로 나눠 여러 번의 Write/Edit로 작성한다

컨벤션 준수 필수:
- 색상/테마 규칙은 `docs.conventions` 를 따른다
- 인터랙티브 요소(버튼/입력/주요 목록)에 의미 기반 snake_case 로 `ui_test_id` 식별자를 부여한다
- 식별자 부여는 동작 중립이므로 1:1 동작 보존 원칙의 예외 (원본에 없어도 추가)
- 기계 확정 항목은 수정을 마치기 전에 스스로 돌려 본다:
  `python3 .claude/scripts/dod_check.py <바꾼 파일들>`

수정 내용 검증 (/fix와 동일):
- changed_lines == 0 → FAILED_MEANINGLESS_DIFF
- 동일 패치 반복 → FAILED_MEANINGLESS_DIFF

---

## 3단계: 검증 + 빌드 (VERIFYING + BUILDING)

orchestrator.json status를 "VERIFYING"으로 업데이트한다.

**verifier와 builder를 병렬로 호출한다.**
각 호출 프롬프트 상단에 반드시 다음을 명시한다:

```
session_dir: <SESSION_DIR>
```

verifier에게 전달:
- 원본(레거시) 파일 경로
- 신규 파일 경로
- 완료 게이트: project.json 의 `dod_checks` 와 `docs.conventions` 의 완료 기준 전 항목을 검증한다.
  하나라도 누락 시 FAIL 로 처리한다.

builder에게 추가 전달 정보 없음 (session_dir만 있으면 충분).

두 에이전트 모두 완료될 때까지 기다린다.

### Orchestrator 판단

`${SESSION_DIR}/verifier.json` 과 `${SESSION_DIR}/builder.json` 을 모두 읽어서 판단한다:

| verifier | builder | 판단 |
|---|---|---|
| PASS | 성공 | 4단계로 |
| PASS | 실패 | implementer 재호출 (빌드 에러 수정) |
| FAIL | 성공 | implementer 재호출 (검증 실패 항목 수정) |
| FAIL | 실패 | implementer 재호출 (양쪽 결과 모두 전달) |

implementer 재호출 시 verifier.json의 findings와 builder.json의 에러를 함께 전달한다.
수정 후 다시 3단계(verifier + builder 병렬)로 돌아온다.

---

## 3.5단계: 런타임 게이트 (RUNTIME)

verifier PASS + builder 성공 후 실행한다. 컴파일 통과를 실제 화면 동작으로 검증한다.
이 단계가 없으면 빌드만 통과해도 동작 보존이 깨진 채 문서화로 넘어간다.

orchestrator.json status 를 "RUNTIME" 으로 업데이트한다.

선택적 재생: 먼저 바뀐 파일(allowed_to_modify)로부터 도메인 태그를 산출한다.
orchestrator.json 의 allowed_to_modify 경로들을 domains_for.py 에 넘기면 도메인 태그가 나온다.
공유 코드(common 등) 변경이면 ALL 이 나와 flows 전체를 회귀한다.

셸로 런타임 게이트를 실행한다 (LLM 미개입, 결정적, 토큰 0):

```bash
TAGS=$(python3 .claude/scripts/domains_for.py <allowed_to_modify 의 파일 경로들>)
bash .claude/scripts/runtime_gate.sh "${SESSION_DIR}" "" "$TAGS"
```

해당 도메인 태그 시나리오만 재생하므로, 시나리오가 쌓여도 바뀐 화면만 빠르게 검증한다.
완료 후 `${SESSION_DIR}/runner.json` 을 읽는다.

### Orchestrator 판단

| runner.json | 판단 |
|---|---|
| gate_error != null | 게이트 자체가 못 돎 (경로 오설정/install 실패). 통과 아님. 즉시 Human Gate |
| skipped=true | 게이트 SKIP. 사용자에게 보고 후 4단계로 (기기 미연결) |
| no_flow=true | baseline 미작성. 통과로 처리하지 않고 1.5단계로 복귀해 시나리오 작성 |
| replay_success=true | 4단계로 (동작 보존 검증됨) |
| replay_success=false | triage 호출 (아래) |

핵심: skipped/no_flow/gate_error 는 통과가 아니다. replay_success=true 일 때만 통과로 처리한다.

### replay 실패 시 triage 호출

runtime_attempt_count 를 1 증가시킨다.
**triage 에이전트를 호출한다** (프롬프트 상단에 session_dir 명시).
완료 후 `${SESSION_DIR}/triage.json` 을 읽고 category 에 따라 분기한다:

| category | next_action | 동작 | 종료 조건 |
|---|---|---|---|
| REAL_BUG | REINVOKE_IMPLEMENTER | 2단계 재호출, suspected_files 전달, attempt_count++ | 같은 화면 3연속 실패 → Human Gate |
| FLAKY | RETRY_REPLAY | flaky_retry_count++ 후 3.5단계 게이트 재시도 | 2회 초과 → REAL_BUG 승격 또는 Human Gate |
| FLOW_ERROR | FIX_FLOW | flow_fix_count++ 후 시나리오 수정 → 게이트 재시도 | 2회 초과 → Human Gate |
| ENV_STATE | HUMAN_GATE | 미로그인/권한/기기 상태. 사람 개입 | 즉시 |

last_triage_category 를 기록한다.
REINVOKE_IMPLEMENTER 분기는 2단계로 돌아가며 기존 종료조건(attempt_count >= 5)이 동일하게 적용된다.
triage 의 confidence 가 LOW 이면 next_action 을 HUMAN_GATE 로 올린다.

### 메트릭 기록

기본 기록은 runtime_gate.sh 가 자동으로 한다. 게이트가 끝나는 모든 경로(통과 / 실패 / SKIP /
NO_FLOW / gate_error)에서 record_metric.py 가 호출되므로, 이 단계까지 못 와도 게이트 결과는 남는다.

여기서는 triage 결과를 채워 넣기 위해 한 번 더 호출한다. record_metric.py 는 멱등이라
(session_id, step_id, attempt) 가 같으면 줄을 추가하지 않고 기존 줄을 갱신한다.
triage 를 돌리지 않았다면 이 단계는 생략해도 된다. 추세는 metrics.py 로 언제든 집계한다.

```bash
python3 .claude/scripts/record_metric.py "${SESSION_DIR}" "$TAGS"
```

---

## 4단계: 문서화 (DOCUMENTING)

빌드 성공 후 반드시 실행한다.
마이그레이션은 항상 문서화 트리거 조건에 해당한다.

**documenter 에이전트를 호출한다.**
호출 프롬프트 상단에 다음을 명시한다:

```
session_dir: <SESSION_DIR>
```

추가 전달 정보:
- 변경된 파일 목록
- 마이그레이션 내용 요약 (레거시 -> 목표 스택, 무엇이 바뀌었는지)

### 시나리오 셀렉터 강화

런타임 게이트(replay_success=true)를 통과한 baseline 시나리오의 조작 셀렉터를
새로 박은 UI 식별자로 교체한다. 텍스트 셀렉터는 문구가 바뀌거나 다국어 빌드가 되면 깨진다.
결과 검증용 텍스트 assert 는 그대로 둔다. 그쪽은 사용자가 보는 내용 자체가 검증 대상이다.
시나리오가 skipped/no_flow 였던 경우 이 강화는 건너뛴다.

---

## 종료 처리

### 성공
- SESSION_ID 보고
- 마이그레이션된 파일 목록 보고
- 문서 갱신 완료 확인
- 외부 노트 앱 동기화 완료 확인 (설정된 경우)

### 실패
/fix와 동일한 종료 처리. 보고에 SESSION_ID를 반드시 포함한다.

---

## 마이그레이션 작업 시 추가 주의사항

- 기존 레거시 파일은 바로 삭제하지 않는다 (빌드 성공 확인 후 별도 처리).
  두 언어가 한동안 공존하므로, 지우는 순간 되돌릴 근거가 사라진다
- 두 언어를 섞어 쓰는 빌드 설정(어노테이션 처리기, 심볼 처리 도구 등)의 충돌에 주의한다
- 스택 버전과 도구 체인 요구사항은 project.json 의 `stack` 과 어댑터가 정한다.
  여기에 버전을 적어 두지 않는다. 적는 순간 낡는다
