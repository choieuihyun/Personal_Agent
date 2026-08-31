#!/usr/bin/env bash
# 크래시 사냥 (monkey 무작위 탐색 + logcat 이상 수집)
# 역할: flow 커버리지와 무관하게 앱을 무작위로 두들겨 크래시/ANR/예외를 찾고 hunt.json 에 기록한다.
# 성격: 결정적 셸 단계. LLM 미개입 (토큰 0). 원인 분석은 하지 않는다.
#
# 런타임 게이트(runtime_gate.sh)와의 차이:
#   게이트는 flow 에 적어둔 동작만 본다. 이 스크립트는 아무도 안 본 화면을 뒤진다.
#   즉 게이트는 "어제 되던 게 오늘도 되나", 이건 "죽는 데가 있나" 를 묻는다.
#
# ⚠ 위험: 이 스크립트는 실기기에 무작위 입력을 쏟아붓는다.
#   기기에 실제 계정으로 로그인된 상태라면 랜덤 터치가 쪽지를 보내거나 삭제하거나 설정을 바꿀 수 있다.
#   되돌릴 수 없는 동작이므로 기본적으로 실행을 막고, 명시적 동의가 있을 때만 돈다.
#   실행하려면 HUNT_CONFIRM=1 을 환경변수로 준다.
#   테스트 계정 기기에서 돌리는 것이 원칙이다. 실계정 기기에서는 사용자에게 먼저 확인받는다.
#
# 사용법: HUNT_CONFIRM=1 HUNT_PKG=<앱 패키지> crash_hunt.sh <session_dir> [event_count] [project_dir]
#   HUNT_PKG: 두들길 앱의 패키지 이름. 필수다. 기본값을 두지 않는다 -
#             엉뚱한 앱에 무작위 입력을 쏟는 사고가 조용히 일어나면 안 된다.
#   HUNT_SRC_PREFIX: 우리 코드로 인정할 스택트레이스 접두사 (선택).
#             주면 "우리 코드에서 난 예외" 를 따로 분류한다. 없으면 그 항목만 건너뛴다.
#   event_count: monkey 이벤트 수 (기본 2000). 늘릴수록 깊이 들어가지만 오래 걸린다.
#
# 종료 코드:
#   0  사냥 정상 수행 (크래시 유무와 무관. 결과는 hunt.json 을 본다)
#   2  기기 미연결 또는 앱 미설치
#   3  인자/환경 오류
#
# 어떤 경우든 hunt.json 은 항상 기록한다.

set -u

SESSION_DIR="${1:-}"
if [ -z "$SESSION_DIR" ]; then
  echo "ERROR: session_dir 인자 누락. 사용법: crash_hunt.sh <session_dir> [event_count] [project_dir]"
  exit 3
fi

# 동의 가드. 실계정 기기에 무작위 입력을 넣는 것은 되돌릴 수 없으므로 기본 차단한다.
if [ "${HUNT_CONFIRM:-}" != "1" ]; then
  echo "차단: 크래시 사냥은 실기기에 무작위 입력을 보낸다(쪽지 전송/삭제/설정 변경 가능)."
  echo "      테스트 계정 기기인지 확인한 뒤 HUNT_CONFIRM=1 을 주고 다시 실행한다."
  exit 3
fi

EVENT_COUNT="${2:-2000}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PROJECT_DIR="${3:-}"
[ -z "$PROJECT_DIR" ] && PROJECT_DIR="$REPO_ROOT"

if ! mkdir -p "$SESSION_DIR" 2>/dev/null; then
  echo "ERROR: session_dir 생성 실패: $SESSION_DIR"
  exit 3
fi
SESSION_DIR="$(cd "$SESSION_DIR" && pwd)"

export ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
export PATH="$ANDROID_HOME/platform-tools:$PATH"

# 대상 앱은 환경변수로 받는다. 기본값을 박아두면 다른 프로젝트에서 그대로 돌아간다.
PKG="${HUNT_PKG:-}"
if [ -z "$PKG" ]; then
  echo "ERROR: HUNT_PKG 미지정. 두들길 앱 패키지를 환경변수로 준다."
  exit 3
fi
RAW_LOG="$SESSION_DIR/hunt-logcat.txt"
MONKEY_LOG="$SESSION_DIR/hunt-monkey.txt"

write_hunt() {
  HT_DEVICE="$1" HT_MONKEY_EXIT="$2" HT_EVENTS="$3" HT_SESSION="$SESSION_DIR" \
  HT_RAWLOG="$RAW_LOG" HT_MONKEYLOG="$MONKEY_LOG" HT_PKG="$PKG" \
  HT_SRC_PREFIX="${HUNT_SRC_PREFIX:-}" \
  python3 "$SCRIPT_DIR/parse_hunt.py"
}

# 1. 기기 연결 확인
DEVICE_COUNT=$(adb devices 2>/dev/null | awk 'NR>1 && $2=="device"' | wc -l | tr -d ' ')
if [ "$DEVICE_COUNT" = "0" ]; then
  echo "SKIP: 실기기 미연결. 크래시 사냥 건너뜀."
  write_hunt "false" "null" "0"
  exit 2
fi

# 2. 앱 설치 확인 (게이트와 달리 여기서는 빌드하지 않는다. 설치된 것을 두들긴다)
if ! adb shell pm list packages 2>/dev/null | grep -q "package:$PKG"; then
  echo "SKIP: $PKG 미설치. 먼저 앱을 설치한 뒤 다시 실행한다."
  write_hunt "true" "null" "0"
  exit 2
fi

# 3. logcat 버퍼를 비우고 시작한다. 이전 실행 흔적이 섞이면 이번 사냥 결과가 오염된다.
adb logcat -c 2>/dev/null || true

# 4. 앱을 깨끗이 재시작
adb shell am force-stop "$PKG" 2>/dev/null || true
adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
sleep 3

# 5. monkey 무작위 탐색
# --throttle 200: 이벤트 간 200ms. 너무 빠르면 앱이 따라오지 못해 의미 없는 입력이 된다.
# --pct-syskeys 0: 시스템 키(홈/뒤로 등) 비율 0. 앱 밖으로 나가버리면 사냥이 끊긴다.
# --ignore-crashes 등을 쓰지 않는다. 크래시가 나면 거기서 멈추고 그 사실을 기록한다.
echo "monkey 탐색 시작: ${EVENT_COUNT} 이벤트 (throttle 200ms)"
adb shell monkey -p "$PKG" \
  --throttle 200 \
  --pct-syskeys 0 \
  --pct-touch 60 --pct-motion 25 --pct-nav 10 --pct-majornav 5 \
  -v -v "$EVENT_COUNT" > "$MONKEY_LOG" 2>&1
MONKEY_EXIT=$?
echo "monkey 종료 (exit=$MONKEY_EXIT)"

# 6. logcat 덤프 (사냥 구간 전체)
adb logcat -d > "$RAW_LOG" 2>/dev/null || true

# 7. 결과 기록 (python 이 로그를 훑어 이상 신호를 분류)
write_hunt "true" "$MONKEY_EXIT" "$EVENT_COUNT"
exit 0
