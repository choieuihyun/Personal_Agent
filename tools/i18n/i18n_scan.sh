#!/bin/bash
# 다국어 노출 검사 드라이버
# 역할: 앱 로케일을 바꾸고 flows/i18n 의 이동 flow 로 화면을 돌며 계층을 덤프한 뒤
#       i18n_report.py 로 한글 UI 문자열을 찾아낸다.
#
# 왜 앱 단위 로케일인가:
#   기기 설정을 바꾸면 다른 앱과 알림까지 영향을 받고 되돌리기도 사람 손이 필요하다.
#   Android 13+ 의 앱별 언어(cmd locale set-app-locales)는 이 앱만 바꾸고 원복도 한 줄이다.
#
# 사용법: i18n_scan.sh [로케일]   (기본 en)
# 종료코드: 0 = 미번역 없음, 1 = 미번역 발견, 2 = 환경 문제

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LOCALE="${1:-en}"
OUT_DIR="$REPO_ROOT/.claude/state/i18n/$LOCALE"
# 대상 앱은 환경변수로 받는다. 기본값을 박아두면 다른 프로젝트에서 엉뚱한 앱을 연다.
PKG="${I18N_PKG:-}"
[ -n "$PKG" ] || { echo "I18N_PKG 미지정. 검사할 앱 패키지를 환경변수로 준다."; exit 3; }

command -v adb >/dev/null 2>&1 || { echo "adb 를 찾을 수 없다. PATH 를 확인한다."; exit 2; }
command -v maestro >/dev/null 2>&1 || { echo "maestro 를 찾을 수 없다. PATH 를 확인한다."; exit 2; }
[ -n "$(adb devices | sed -n '2p')" ] || { echo "기기가 연결되지 않았다."; exit 2; }

mkdir -p "$OUT_DIR"
rm -f "$OUT_DIR"/*.json

# 원래 로케일을 기억해 뒀다 끝에 되돌린다. 검사가 기기 상태를 바꾼 채 끝나면 안 된다
BEFORE=$(adb shell cmd locale get-app-locales "$PKG" 2>/dev/null | sed 's/.*\[//;s/\].*//' | tr -d '\r')
echo "원래 로케일: [${BEFORE}]  ->  검사 로케일: [$LOCALE]"
adb shell cmd locale set-app-locales "$PKG" --locales "$LOCALE" >/dev/null 2>&1

restore() {
    if [ -z "$BEFORE" ]; then
        adb shell cmd locale set-app-locales "$PKG" --locales "" >/dev/null 2>&1
    else
        adb shell cmd locale set-app-locales "$PKG" --locales "$BEFORE" >/dev/null 2>&1
    fi
    echo "로케일 원복 완료: [${BEFORE}]"
}
trap restore EXIT

count=0
for flow in "$REPO_ROOT"/flows/i18n/goto_*.yaml; do
    [ -e "$flow" ] || continue
    name=$(basename "$flow" .yaml)
    name=${name#goto_}
    printf '  %-16s ' "$name"
    if maestro test "$flow" >/dev/null 2>&1; then
        maestro hierarchy > "$OUT_DIR/$name.json" 2>/dev/null
        if [ -s "$OUT_DIR/$name.json" ]; then
            echo "덤프 완료"
            count=$((count + 1))
        else
            echo "덤프 실패"
            rm -f "$OUT_DIR/$name.json"
        fi
    else
        # 이동 자체가 실패한 화면은 검사 대상에서 빠진다. 조용히 넘어가면 커버리지를 착각한다
        echo "이동 실패 (검사 제외)"
    fi
done

echo
echo "덤프한 화면: $count 개"
[ "$count" -eq 0 ] && { echo "검사할 화면이 없다."; exit 2; }

python3 "$SCRIPT_DIR/i18n_report.py" "$OUT_DIR"/*.json
