# adapters

스택별 명령 묶음. `core/` 는 여기서 명령을 읽어 쓰므로 스택이 바뀌어도 로직은 그대로다.

어댑터 하나가 답하는 질문은 넷이다.

| 키 | 뜻 |
|---|---|
| `build` | 어떻게 컴파일하나 |
| `deploy` | 어디에 올리나 (없으면 생략) |
| `smoke` | 켜지는지만 어떻게 확인하나 |
| `e2e` | 동작을 어떻게 재생하나 |

`e2e` 안에서 스택마다 문법이 갈리는 곳:

| 키 | 뜻 | 예 |
|---|---|---|
| `command` | 재생 명령. `{REPORT_XML}` 자리에 JUnit 리포트를 **파일로** 남겨야 한다. 화면에만 찍으면 게이트는 결과를 못 읽는다 | playwright 는 `PLAYWRIGHT_JUNIT_OUTPUT_NAME` 으로 경로를 준다 |
| `tag_option` | 태그로 좁힐 때 붙는 옵션. `{TAGS}` 자리에 태그가 들어간다 | `--include-tags={TAGS}` |
| `tag_join` | 태그 여러 개를 잇는 구분자. 생략하면 콤마 | playwright 는 정규식이라 `\|`, pytest 는 ` or ` |
| `tag_scan` | 시나리오 파일에서 태그를 읽는 규칙. import 경로 같은 것이 태그로 잡히지 않게 한다 | `@playwright/test` 가 도메인 `playwright` 로 잡히면 안 된다 |

| 어댑터 | 대상 | 상태 |
|---|---|---|
| `android-gradle-maestro.json` | 안드로이드 앱 | 실제 프로젝트에서 검증됨 |
| `node-vite-playwright.json` | 웹 앱 | 스키마만 맞춤. 실전 완주 전 |
| `python-pytest.json` | 대상 밖 | 스키마가 다른 스택에도 맞는지 확인용. 정식 지원 아님 |

지원 범위는 안드로이드와 웹이다 (저장소 README 의 대상 범위 참고).
