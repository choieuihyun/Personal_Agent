#!/bin/bash
# 다국어 전 로케일 순회 검사
# 역할: 지원 로케일 전부에 대해 i18n_scan.sh 를 돌리고 결과를 한 번에 요약한다.
#
# 로케일마다 무엇이 다른가:
#   - 코드에 하드코딩된 한글은 리터럴이라 어느 로케일에서든 똑같이 나온다.
#   - 리소스 키가 누락된 자리는 영어로 폴백되므로 한글 검출기에 안 잡힌다(정적 검사 영역).
#   - 리소스 값에 한국어가 그대로 남은 자리만 로케일별로 갈린다. 이걸 찾는 것이 이 순회의 실익이다.
#
# 사용법: i18n_scan_all.sh [로케일...]   (기본: en ja zh ru vi)

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCALES=("$@")
[ ${#LOCALES[@]} -eq 0 ] && LOCALES=(en ja zh ru vi)

declare -a SUMMARY
for loc in "${LOCALES[@]}"; do
    echo
    echo "############################################################"
    echo "# 로케일: $loc"
    echo "############################################################"
    out=$(bash "$SCRIPT_DIR/i18n_scan.sh" "$loc" 2>&1)
    echo "$out"
    line=$(echo "$out" | grep "^요약:" | head -1)
    SUMMARY+=("$(printf '  %-4s %s' "$loc" "${line:-실행 실패}")")
done

echo
echo "############################################################"
echo "# 전체 요약"
echo "############################################################"
for row in "${SUMMARY[@]}"; do echo "$row"; done
