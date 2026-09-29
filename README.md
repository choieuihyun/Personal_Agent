# Personal Agent Harness

AI 코딩 에이전트를 프로젝트에 붙이는 방법론 저장소.
특정 프로젝트의 코드가 아니라, 어떤 프로젝트에든 얹을 수 있는 오케스트레이션을 담는다.

## 대상 범위

**모든 프로젝트가 대상이다.** 앱, 웹, 서버, 라이브러리, CLI 를 가리지 않는다.

런타임 게이트의 모양은 하나다.

```
빌드 → (있으면) 실행 대상에 올리기 → 도메인 태그로 시나리오를 골라 재생 → JUnit 결과로 판정
```

유형마다 다른 것은 "시나리오가 무엇인가" 와 "올리기가 있는가" 뿐이고, 둘 다 어댑터가 정한다.

| 유형 | 올리기 | 시나리오 예 |
|---|---|---|
| 모바일 앱 | 기기에 설치 | 화면 조작 (maestro 등) |
| 웹 앱 | 미리보기 서버 | 브라우저 조작 (playwright 등) |
| 서버 | 서버 기동 (프로세스, 컨테이너) | API 호출 |
| 라이브러리, CLI | 없음 | 통합 테스트 |

테스트 도구는 무엇이든 된다. 결과를 JUnit XML 로 남길 수만 있으면 된다. 거의 모든 도구가 직접 또는 리포터 하나로 지원한다.

| 어댑터 | 상태 |
|---|---|
| `android-gradle-maestro` | 실제 프로젝트에서 사용하며 검증됨 |
| `node-vite-playwright` | 결함 3개를 고치고 가짜 러너로 게이트 완주 확인. 실제 프로젝트 `/fix` 완주 전 |
| `python-pytest` | 스키마만 맞춤. 실전 완주 전 |

목록에 없는 스택은 어댑터를 새로 쓴다. 형식은 `adapters/README.md` 에 있다.

## 무엇인가

`/fix` 같은 슬래시 커맨드 하나가 서브에이전트 여러 개를 순서대로 몰아서
탐색 → 수정 → 빌드 → 런타임 검증 → 문서화까지 돌리고, 실패하면 분류해서
재시도하거나 사람에게 넘긴다.

```
인테이크 → explorer → implementer → builder → 런타임 게이트 → triage → documenter
           (읽기만)   (허가된 파일만) (수정안함)  (셸, LLM 미개입)  (분류만)
```

- 상태는 `orchestrator.json` 하나가 갖는다 (유일한 권위)
- 각 에이전트는 독립 컨텍스트에서 돌고 결론 json 만 반환한다 (컨텍스트 격리)
- 도구 권한을 프론트매터로 물리적으로 제한한다 (프롬프트로 부탁하지 않는다)
- 무한 루프는 상한으로 끊는다 (attempt 5회 / 같은 에러 3회 / 무의미 diff 4종 검사)

## 구조

| 디렉터리 | 내용 |
|---|---|
| `core/commands/` | 오케스트레이터 파이프라인 |
| `core/agents/` | 역할별 서브에이전트 정의 |
| `core/scripts/` | 결정적 셸 단계 (설정 로더, 런타임 게이트, 도메인 매핑, DoD 검사, 메트릭) |
| `adapters/` | 스택별 명령 묶음 (gradle/maestro, npm/playwright. pytest 는 스키마 확인용) |
| `templates/` | project.json 템플릿과 키 설명 |
| `tools/` | 파이프라인 밖 QA 도구. 대상 프로젝트로 복사되지 않는다 |

## 얹는 법

```bash
bash install.sh <대상 프로젝트>            # 무엇이 일어날지만 보려면 --dry-run
```

`cp -r` 를 대신 쳐 주는 것이 목적이 아니다. `cp` 가 말해 주지 않는 것을 말하는 게 목적이다.

- **대상에서 고친 파일이 있으면 멈춘다.** 목록을 보여주고 `--force` 를 요구한다.
  대상에서 고친 것은 하네스로 먼저 옮긴다 (역수출). 안 그러면 조용히 사라진다
- **`project.json` 은 이미 있으면 절대 덮지 않는다.** 채워 둔 설정이 날아가면 게이트가 통째로 멈춘다
- 대상 전용 파일은 지우지 않는다. 복사는 덧쓰기지 미러링이 아니다
- `.claude/state/` 를 `.gitignore` 에 넣고, 설치 직후 도메인 매핑과 게이트 상태를 확인해서 보여준다

에이전트는 `.claude/agents/<이름>/AGENT.md` 형태 그대로 로드된다.
Claude Code 는 `.claude/agents/*.md` 를 하위 디렉토리까지 훑고, 식별자는 파일명이 아니라
frontmatter 의 `name` 이다. 같은 디렉토리 안에서 `name` 이 겹치면 하나가 조용히 버려지므로
에이전트마다 폴더를 따로 둔다.

### project.json 채우기

전부 채울 필요는 없다. 이 순서로 하면 단계마다 확인하면서 갈 수 있다.

1. `adapter` — `adapters/` 의 파일명. E2E 개념이 없는 프로젝트면 `"runtime_gate": false` 로 끄고 넘어간다
2. `e2e.dir` 과 `vars` — 어댑터 명령의 빈칸. 안 채우면 게이트가 실행 전에 멈춘다 (반쪽 명령을 돌리지 않는다)
3. `domains` — 여기서부터 재생이 좁아진다. 안 채우면 매번 전체 회귀다
4. `forbidden_globs`, `ui_test_id`, `docs.*` — 게이트 밖 규칙들

확인은 이렇게 한다.

```bash
python3 .claude/scripts/domains_for.py --self-check          # 도메인 목록이 실제 폴더와 맞나
python3 .claude/scripts/domains_for.py src/features/chat/A.ts # 태그가 제대로 나오나
python3 .claude/scripts/e2e_tags.py --coverage e2e            # 시나리오가 덮는 도메인
bash .claude/scripts/runtime_gate.sh .claude/state/probe ""   # 게이트가 도나
```

### 안 채웠을 때 무엇이 일어나는가

설정이 비어 있어도 파이프라인은 돈다. 다만 **모르는 것을 아는 척하지 않는다.**

| 상황 | 결과 | 왜 |
|---|---|---|
| `domains` 없음 | 전부 `ALL` (전체 회귀) | 좁혀서 회귀를 놓치는 것보다 느린 게 낫다 |
| `adapter` 없음 | 게이트 `exit 3`, `gate_error: bad_config` | 통과가 아니다. 조용히 SKIP 되면 초록불로 오인된다 |
| `runtime_gate: false` | `skipped`, `exit 0` | 안 쓰기로 한 것은 정상이다. 보고에 SKIP 으로 남는다 |
| `vars` 빈칸 | 게이트 `exit 3`, `unfilled_vars` | 반쪽 명령을 실행하지 않는다 |
| `dod_checks` 없음 | `exit 2` (`DOD_NO_RULES`) | 검사하지 않은 것과 통과한 것은 다르다 |

채우는 만큼 좁고 빨라지는 구조다.


