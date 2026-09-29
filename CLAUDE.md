# Personal Agent Harness

대답은 무조건 한글로 한다.

AI 코딩 에이전트를 프로젝트에 붙이는 **방법론 저장소**다. 특정 프로젝트의 코드가 아니라,
여러 앱 프로젝트에 얹을 수 있는 오케스트레이션 골격을 담는다.

**대상은 화면이 있는 앱, 지금은 안드로이드와 웹이다.** (2026-09-29 결정)
"프로젝트 이름을 지우면 말이 되는가" 는 이 범위 안에서 묻는다.
범용성을 넓히는 방향은 스택(gradle, npm) 축이지 프로젝트 유형(라이브러리, CLI) 축이 아니다.
대상 밖 프로젝트 하나를 위해 core 의 게이트 구조를 넓히지 않는다.

---

# 절대 원칙: 프로젝트 이름이 들어가면 안 된다

무언가를 이 저장소에 넣기 전에 반드시 물어본다:

> **"프로젝트 이름을 지우면 말이 되는가?"**

| 답 | 어디로 |
|---|---|
| 된다 | `core/` — 상태기계, 역할 분리, 게이트 루프, 실패 분류, 종료값 정의 |
| 값만 다르다 | `project.json` 빈칸 — 도메인 목록, 빌드 명령, appId, 금지 글롭 |
| 구조가 다르다 | `adapters/` — gradle vs npm, maestro vs playwright |
| 안 된다 | **여기 넣지 않는다.** 대상 프로젝트의 CLAUDE.md 로 간다 |

## 반입 금지 (회사 자산 경계)

특정 회사/제품 코드베이스에서 파생된 것은 넣지 않는다.

- 도메인 문서, 화면 설명, 프로토콜/패킷 구조
- Maestro flow 등 그 제품의 동작을 기술한 테스트
- 실계정 ID, 사내 URL, 사내 위키/NAS 주소, appId 같은 식별자
- 특정 제품에서만 의미 있는 스크립트 (i18n 스캔의 리소스 경로 규칙 등)

방법론은 내 것이고 그 위에 채운 내용은 그 회사 것이다. 처음부터 갈라두면 나중에 판단할 일이 없다.

---

# 구조

```
core/           프로젝트 무관. 대상 프로젝트의 .claude/ 로 복사되는 것
  commands/     오케스트레이터 파이프라인 (fix / feature / modernize / study / deep / log)
  agents/       역할별 서브에이전트 13개 (explorer / implementer / builder / verifier / triage / ...)
  scripts/      결정적 셸 단계 (설정 로더, 런타임 게이트, 도메인 매핑, DoD 검사, 메트릭)

adapters/       스택별 명령 묶음 (android-gradle-maestro, node-vite-playwright, python-pytest)
templates/      project.json 템플릿과 키 설명
tools/          파이프라인 밖 QA 도구 (i18n 검사, 크래시 헌트). 대상 프로젝트로 복사되지 않는다
install.sh      대상 프로젝트에 설치. 덮으면 사라지는 것을 먼저 알린다
check.sh        저장소 자기 검사. core 에 고유어가 다시 들어오면 여기서 걸린다
bin/            설치·갱신·진단 CLI (아직 없음)
```

## 세 층이 답하는 질문

| 층 | 답하는 질문 | 바뀌는 주기 |
|---|---|---|
| `core/` | 어떤 순서로 무엇을 판정하는가 | 방법론이 바뀔 때만 |
| `adapters/<스택>.json` | 그 일을 **어떤 명령**으로 하는가 | 스택을 바꿀 때 |
| `.claude/project.json` | 그 명령의 **빈칸에 무엇을 넣는가** | 프로젝트마다 |

이 경계가 무너지는 순간을 알아채는 법은 간단하다.
`core/` 안에 특정 도구 이름이나 특정 제품 용어가 보이면 잘못 들어온 것이다. `check.sh` 가 그것을 센다.

## 설계 원칙 (core 에 담긴 것)

1. **상태기계** — `orchestrator.json` 이 유일한 권위. step_id / attempt_count / same_error_count /
   allowed_to_modify / forbidden_rules / human_gate_required / termination_reason
2. **역할별 도구 제한** — 프롬프트로 "하지 마" 라고 쓰는 대신 `tools:` 프론트매터로 물리적으로 막는다.
   explorer 는 읽기만, implementer 는 허가 목록 안에서만 쓰기, builder 는 수정 안 함
3. **컨텍스트 격리** — 각 에이전트는 독립 컨텍스트에서 돌고 오케스트레이터에는 결론(json)만 반환한다.
   파이프라인이 길어져도 컨텍스트가 안 부푼다
4. **baseline before modify** — 회귀 검증용 테스트는 수정 **전에** 뜬다. 수정 후 작성하면 자기충족 함정
5. **무의미 diff 검사 4종** — LLM 이 "고쳤다" 면서 아무것도 안 바꾸거나 같은 자리를 맴도는 실패를 막는다
6. **실패 4분류 + 재시도 상한** — REAL_BUG / FLAKY / TEST_ERROR / ENV. 각각 상한 초과 시 Human Gate
7. **종료값 정의** — 지어낸 상태값을 쓰지 않는다. 이름이 갈리면 집계가 깨진다
8. **측정은 셸에서** — 메트릭 기록을 커맨드 문서 마지막 단계에 맡기면 LLM 이 거기까지 도달해야만 남는다.
   결정적으로 도는 셸 쪽에 두어야 실제로 쌓인다

---

# 현재 상태 (2026-08-31, 5단계까지 완료)

회사 안드로이드 프로젝트에서 쓰던 것을 **있는 그대로 반입**한 뒤 1~5단계를 실행했다.
원본은 첫 커밋에 그대로 남아 있으므로 언제든 되돌릴 수 있다.

`core/` 는 이제 위 절대 원칙을 **실제로 지킨다.** 눈으로 센 것이 아니라 `check.sh` 로 확인한다.

```
bash check.sh
```

| 검사 | 기준 |
|---|---|
| 금지어 (제품명, 사내 문서 경로, 공유 이벤트 클래스명, 앱 식별자) | 저장소 전체 0건 |
| 하드코딩된 스택 명령과 개인 경로 | `core/` 안 0건 |
| 에이전트 이름 | 제품 접두사 0개, 디렉토리명과 frontmatter 일치 |
| 어댑터/템플릿 json | 문법 통과 |
| 설정이 없을 때의 동작 | 도메인 매핑은 ALL, 게이트는 exit 3, DoD 검사는 exit 2 |

금지어 목록은 `check.sh` 안에 없다. `.denylist` 파일에 적고 그 파일은 커밋하지 않는다.
금지어가 곧 그 회사의 제품명과 식별자라서, 검사 스크립트에 적으면
고유어를 지우면서 검사기에 고유어를 남기는 꼴이 된다.
`.denylist` 가 없으면 그 검사만 SKIP 으로 표시된다. 통과로 세지 않는다.
형식은 `.denylist.example` 에 있다.

마지막 줄이 핵심이다. **설정이 없을 때 무엇이 안전인지는 스크립트마다 다르다.**
도메인 매핑은 모르면 넓게 도는 것이 안전하고(ALL), 런타임 게이트는 모르면 멈추는 것이 안전하다(exit 3).
이 둘을 한 곳에서 통일하면 게이트가 조용히 SKIP 되어 초록불이 켜진다. 그래서 로더는 성패만 알리고 판단은 각자 한다.

## 반입 시점의 잔재 (이제 없음, 기록용)

| 파일 | 반입 시 고유어 | 어떻게 없앴나 |
|---|---|---|
| `core/commands/feature.md` | 24곳 | UI 식별자/시나리오 용어로 일반화, 앱 식별자는 설정으로 |
| `core/commands/fix.md` | 22곳 | 크래시 인테이크를 `crash_provider` 바인딩으로, 미설정이면 멈춤 |
| `core/scripts/runtime_gate.sh` | 16곳 | 명령 전부를 어댑터로. 이 파일은 순서와 판정만 한다 |
| `core/agents/spec/AGENT.md` | 12곳 | 로그인 우회 절차를 `docs.e2e_guide` 참조로 |
| `core/commands/modernize.md` | 11곳 | 전환 방향을 `stack` 설정으로 |
| 에이전트 12개 | 1~7곳 | 이름과 예시 치환, 위험 축 이름 고정 |
| `core/scripts/domains_for.py` | 1곳 + 도메인 표 | 표 전체를 `domains` 규칙으로 |

## 2단계 정리 결과 (실행 완료)

각 파일을 실제로 읽고 내린 판정대로 실행했다.

### tools/ 로 이동 (8개) - 버리지 않는다

오케스트레이션이 아니라 **QA 도구**다. `core/` 는 대상 프로젝트에 설치되는 것인데 성격이 다르다.

```
core/scripts/i18n_concat_check.py   ->  tools/i18n/
core/scripts/i18n_report.py         ->  tools/i18n/
core/scripts/i18n_scan.sh           ->  tools/i18n/
core/scripts/i18n_scan_all.sh       ->  tools/i18n/
core/scripts/i18n_source_rank.py    ->  tools/i18n/
core/scripts/i18n_static.py         ->  tools/i18n/
core/scripts/crash_hunt.sh          ->  tools/crash-hunt/
core/scripts/parse_hunt.py          ->  tools/crash-hunt/
```

왜 버리지 않나 (같은 내용을 `tools/README.md` 에도 적어 뒀다):
- `i18n_concat_check.py` - "문자열을 코드에서 이어 붙이면 어순이 다른 언어에서 깨진다.
  동적 검사로는 못 잡는 사각이다" 는 스택 무관한 통찰이다. 나중에 일반화 가치 있음
- `i18n_static.py` - "리소스 파일 간 키 누락 검사" 는 모든 i18n 스택 공통 개념
- `crash_hunt.sh` - 게이트와 상보적인 두 번째 검증 축이다.
  게이트는 "어제 되던 게 오늘도 되나", 이건 "죽는 데가 있나" 를 묻는다.
  무작위 입력이 실계정 기기에서 되돌릴 수 없는 동작을 일으키는 것을 막는 동의 게이트도 이식 가치가 있다

나머지 i18n 4개(`scan` `scan_all` `report` `source_rank`)는 flows 자산과 adb 에 묶여 있어
현 상태로는 이식 불가. 같이 옮겨 두고 일반화는 나중에 판단한다.

### 삭제 (5개)

```
core/commands/opsx/apply.md      OpenSpec 플러그인 것. 내가 만든 게 아니고
core/commands/opsx/archive.md    플러그인으로 이미 설치돼 있어 사본은 낡은 포크가 된다
core/commands/opsx/explore.md
core/commands/opsx/propose.md
core/commands/scenarioStudy.md   13줄 전부가 메신저 도메인 전제
                                 ("PC Mobile 동시 접속 충돌", "메신저 도메인 지식과 결합")
```

### core/ 유지 - 판정 정정

`core/commands/log.md` 는 처음에 제외 후보로 봤으나 **읽어보니 완전히 일반적이다.**
CHANGELOG 에 한 줄 추가하는 것뿐이고 제품 언급이 도메인명 예시 한 줄뿐이다.
이미 `core/` 에 있는 `changelog_append.sh`(결합 0%)와 짝이다. 남긴다.

### 5단계로 보류 (2개, 이후 처리 완료)

지금은 안드로이드 전용이지만 **개념이 일반적**이라 지우지 않고 개명/일반화 때 같이 처리했다.

| 파일 | 살릴 개념 | 결과 |
|---|---|---|
| `core/commands/deep.md` | 이론 설명 금지, 실행 가능한 코드만. 내부동작 -> 메모리 -> 실행 -> 코드 순서 | 그대로 유지, 예시만 중립화 |
| `core/commands/androidStudy.md` | 공식 문서와 이 저장소의 실제 사용을 대조한다. 문서만 요약하면 블로그 글과 같다 | `study.md` 로 개명 + `learning` 설정화 |

### 실행 결과

```
core/commands/  11 -> 6   (fix, feature, modernize, log, deep, androidStudy)
                          (androidStudy 는 5단계에서 study 로 개명)
core/scripts/   14 -> 6   (changelog_append, domains_for, metrics,
                           parse_runner, record_metric, runtime_gate)
```

남는 스크립트 6개가 정확히 오케스트레이션 골격이다.

**계획에는 `14 -> 5` 로 적혀 있었는데 실제로는 6이다.** 목록에서 `metrics.py` 가 빠져 있었다.
`runtime_metrics.jsonl` 집계기라 제품 결합이 0이고 `record_metric.py` 와 짝이므로 `core/` 에 남는 게 맞다.
계획의 산수 실수였지 판정이 바뀐 것이 아니다.

`docs/architecture.html` 11장(현재 상태)의 파일 표와 개수도 같은 작업에서 갱신했다.

## 3~5단계 정리 결과 (실행 완료)

순서를 바꿔 실행했다. **개명(5단계의 기계적 절반)을 먼저 했다.**
에이전트 이름은 커맨드 문서 세 개(1265줄)에 흩어져 있어서, 나중에 하면 같은 줄을 두 번 고치게 된다.

### 5-1. 에이전트 개명 13개

`<제품명>-explorer` -> `explorer` 식으로 접두사를 전부 벗겼다.
`<제품명>-android-tutor` 만 예외로 `tutor` 가 됐다. 스택 이름도 접두사와 같은 이유로 뺀다.
`/androidStudy` 도 같은 이유로 `/study` 가 됐다.

### 3단계. project.json 도입

`core/scripts/harness_config.py` 하나가 설정을 찾는 유일한 곳이다.
찾는 순서는 환경변수 -> `.claude/project.json` -> `<프로젝트>/.claude/project.json`.

옮긴 것:

| 무엇이 | 어디에서 | 어디로 |
|---|---|---|
| 도메인 폴더 22개와 접두사 표 34줄 | `domains_for.py` 코드 안 | `domains.dir_rules` / `domains.prefix_rules` |
| 완료 기준 grep 게이트 | `verifier/AGENT.md` 본문 | `dod_checks` + `core/scripts/dod_check.py` |
| 크래시 앱 ID 와 MCP 도구 이름 | `fix.md` 본문 | `crash_provider` |
| 사내 문서 경로 6종 | 에이전트 본문 곳곳 | `docs.*` |
| 마이그레이션 방향 | `modernize.md` 제목과 본문 | `stack` |
| 학습 레퍼런스 저장소 | `tutor/AGENT.md` 표 | `learning` |

도메인 매핑은 규칙 **종류**만 코드에 남겼다. 폴더 이름이 도메인인 경우와 파일명 접두사가 도메인인 경우 둘뿐이다.
안드로이드 패키지 구조에서 뽑았지만 `src/features/<이름>` 이나 `pages/<이름>` 에도 그대로 맞는다.

### 4단계. adapters 분리

`runtime_gate.sh` 에 있던 명령 다섯 줄(빌드, 설치, 재생, 기기 확인, 로그)이 어댑터로 나갔다.
게이트는 이제 순서와 판정만 한다.

- `android-gradle-maestro.json` — 반입 원본의 명령을 그대로 옮긴 것
- `node-vite-playwright.json`, `python-pytest.json` — 같은 스키마가 다른 스택에 맞는지 확인용

가장 손이 많이 간 부분은 **커버리지 태그 판독**이다.
게이트는 "시나리오가 실제로 덮는 도메인" 을 재서 보고에 남기는데, 원래는 yaml 의 `tags:` 를 awk 로 긁고 있었다.
이건 스택이 바뀌면 못 쓴다. 그래서 `e2e_tags.py` 로 빼고 판독 방식을 어댑터의 `tag_scan` 이 정하게 했다.
규칙을 모르면 커버리지는 빈 값이 되는데, 이 빈 값은 "덮는 도메인 없음" 이 아니라 **"알 수 없음"** 이고 게이트가 그렇게 보고한다.

검증은 스텁 어댑터로 실제로 돌려서 했다. 안드로이드 도구 없이 게이트가 완주하고
`runner.json` 에 `install_success` / `replay_success` / `coverage_domains` 가 정상적으로 찍혔다.
NO_FLOW, 워크트리 표식 없음, 설정 없음 세 경로도 각각 exit 0 / 3 / 3 으로 확인했다.

### 5-2. 문장 일반화

에이전트 13개와 커맨드 6개의 본문에서 제품 용어를 걷어냈다.
단순 치환이 아니라, 무엇이 방법론이고 무엇이 그 제품 사정인지 매번 갈랐다. 예를 들어:

- explorer 의 위험 축은 `SYNC` / `EVENT` / `THREAD` / `DB` / `LIST` 로 **이름을 고정**했다.
  뒤 단계가 이 값으로 규칙을 고르기 때문에 프로젝트마다 이름이 달라지면 그 선택이 깨진다.
  각 축에 무엇이 해당하는지는 프로젝트가 정하고, 축 이름은 코어가 정한다
- verifier 의 "Java 호환성" 은 **상호운용성** 이 됐다. 살릴 통찰은
  "마이그레이션 중에는 두 언어가 공존하므로 레거시에서 신규를 못 부르면 컴파일이 통과해도 런타임에 죽는다" 다
- tutor 의 "이 저장소의 전제" 블록은 제품 실측 수치였다. 방법론은 수치가 아니라
  "문서의 스냅샷과 grep 결과가 다르면 grep 을 믿고 문서가 낡았다고 보고한다" 쪽이다

### 남긴 것

`tools/` 는 그대로 뒀다. 거기 있는 제품 결합은 의도된 것이다 (2단계 판정).
`core/` 밖이므로 대상 프로젝트에 설치되지 않는다.

---

---

## 정리 순서

1. ~~**원본 커밋** - 되돌릴 기준선 확보~~ **완료**
2. ~~**제외 대상 정리** + `docs/architecture.html` 갱신~~ **완료**
3. ~~`project.json` 도입 - 도메인 표와 빌드 명령을 코드 밖으로~~ **완료**
4. ~~`adapters/` 분리 - 빌드/설치/스모크/E2E 명령을 어댑터 파일로~~ **완료**
5. ~~에이전트 개명 13개 + 보류 2개 일반화~~ **완료** (3~4단계보다 먼저 실행했다)
6. **(다음)** `bin/harness` CLI - init / scan / doctor / diff / pull
   (install 은 `install.sh` 로 먼저 나왔다. 복사 한 줄은 배포 도구가 아니라서
   두 번째 프로젝트를 기다릴 이유가 없었다. 나머지 다섯은 여전히 이르다)

**두 번째 프로젝트가 생기기 전까지 6번은 이르다.** 프로젝트가 하나뿐인데 배포 도구부터 만들지 않는다.
지금 상태로 이미 "복사해서 project.json 채우면 도는" 상태다. CLI 는 그 복사가 귀찮아진 다음에 만든다.

### 다음에 할 만한 것 (6번보다 먼저)

- **실제로 한 번 얹어 보기.** 이 저장소는 아직 대상 프로젝트에서 재검증되지 않았다.
  `.claude/` 로 복사하고 `project.json` 을 채워 `/fix` 를 한 번 완주시키는 것이 가장 값싼 검증이다
- `templates/CLAUDE.md.tmpl`, `DOMAIN.md.tmpl` 채우기 (지금은 이름만 있다)
- 첫 커밋 히스토리에 남은 고유어 처리 (공개 저장소에 푸시하기 전에 판단할 것)

## 결론 난 것 (다시 논의하지 않는다)

- `/modernize` 와 `/feature` 를 `/fix` 에 합치지 않는다.
  **인테이크가 다른 건 합치고, 제어 흐름이 다른 건 나눈다.**
  마이그레이션은 수정 전에 테스트를 뜨고, 신규 기능은 승인에서 멈춘다. 순서 자체가 다르다
- 규칙 문서를 스킬로 쪼개지 않는다. 스킬은 안 불리면 규칙이 아예 없는 것이라 위험이 이득보다 크다

---

# 작업 규칙

- 이 저장소를 고칠 때는 대상 프로젝트를 건드리지 않는다. 반대도 마찬가지다.
  한 세션에서 둘을 동시에 하면 어느 쪽이 정본인지 흐려진다
- 대상 프로젝트에서 실행하다 발견한 버그는 거기서 고치고, 나중에 여기로 옮긴다 (역수출)
- git commit / push 는 **이 저장소에서만** 에이전트가 직접 한다 (2026-08-31 사용자 위임).
  작업 하나에 커밋 하나로 끊고, 되돌리기 어려운 것(force push, reset --hard, 히스토리 재작성)은 하지 않는다.
  대상 프로젝트에는 이 위임이 적용되지 않는다
- 리모트(`github.com/choieuihyun/Personal_Agent`)는 **공개 저장소**다.
  아직 제품 고유어(appId, 패키지 경로, 제품명)가 남아 있으므로 5단계 개명이 끝날 때까지는
  무엇을 공개하는지 알고 푸시한다
- 주석은 한글로 쓰고 특수문자는 넣지 않는다
- 커밋 메시지에 공동 작성자 트레일러를 넣지 않는다. 이 저장소의 작성자는 한 명이다
- 회사 자산 경계는 `check.sh` 가 지킨다. 새 금지어가 생기면 `.denylist` 에 추가한다
