# adapters

스택별 명령 묶음. `core/` 는 여기서 명령을 읽어 쓰므로 스택이 바뀌어도 로직은 그대로다.

어댑터 하나가 답하는 질문은 넷이다.

| 키 | 뜻 |
|---|---|
| `build` | 어떻게 컴파일하나 |
| `deploy` | 어디에 올리나 (없으면 생략) |
| `smoke` | 켜지는지만 어떻게 확인하나 |
| `e2e` | 동작을 어떻게 재생하나 |

예정: `android-gradle-maestro.json` / `node-vite-playwright.json` / `python-pytest.json`

4단계에서 `runtime_gate.sh` 에 박혀 있는 명령 5줄을 여기로 뺀다.
