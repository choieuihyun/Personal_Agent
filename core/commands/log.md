# /log Command

현재 대화 컨텍스트만 사용한다. 파일 스캔 금지.

## 동작 순서

1. CHANGELOG.md 파일을 읽는다.
2. 기존 내용 하단에 새 항목을 추가한다.
3. CHANGELOG.md에 저장한다.

## 형식

[YYYY-MM-DD] [Feature] [Change]

예시: [2026-04-17] [message] [목록 전체 갱신 제거하고 부분 갱신 적용]

## 규칙

- 키워드만 사용한다. 긴 문장 금지.
- 대화 컨텍스트에서 변경 내용을 파악한다.
- Feature 는 도메인명으로 쓴다 (project.json 의 domains 규칙이 아는 이름)
- Change는 무엇을 왜 바꿨는지 간결하게
