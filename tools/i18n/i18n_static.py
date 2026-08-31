#!/usr/bin/env python3
# 다국어 리소스 정적 검사기
# 역할: strings.xml 만 보고 로케일별 키 누락과 번역 안 된 한글 잔존을 찾는다.
# 성격: 결정적. 기기가 필요 없다.
#
# 한계: 코드에 하드코딩된 한글은 못 잡는다(strings.xml 에 없으므로).
#       그쪽은 i18n_scan.sh 의 동적 검사가 담당한다.
#
# 사용법: i18n_static.py
# 종료코드: 0 = 문제 없음, 1 = 발견

import os
import re
import sys

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
RES = os.path.join(REPO, "app/src/main/res")
LOCALES = ["ko", "ja", "zh", "ru", "vi"]
KOR = re.compile(r'[가-힣]')


def load(path):
    if not os.path.exists(path):
        return None
    src = open(path, encoding="utf-8").read()
    return dict(re.findall(r'<string name="([^"]+)"[^>]*>(.*?)</string>', src, re.S))


def untranslatable(path):
    # translatable="false" 로 표시된 키. 브랜드명처럼 로케일별 값을 두지 않는 것들이다.
    # 표시해 두면 누락 검사가 매번 지적하지 않고, 로케일 파일에 다시 복사되는 것도 막는다
    if not os.path.exists(path):
        return set()
    src = open(path, encoding="utf-8").read()
    return set(re.findall(r'<string name="([^"]+)"[^>]*translatable="false"', src))


def main():
    base = load(os.path.join(RES, "values/strings.xml"))
    if base is None:
        print("기본 strings.xml 을 찾지 못했다:", RES)
        return 2

    found = False

    print("=" * 60)
    print("1) 기본(영어)에 있는데 해당 로케일에 없는 키")
    print("   누락된 키는 영어로 폴백돼 화면에 두 언어가 섞인다")
    print("=" * 60)
    for loc in LOCALES:
        d = load(os.path.join(RES, "values-%s/strings.xml" % loc))
        if d is None:
            print("  %-3s 리소스 폴더 없음" % loc)
            continue
        # 기본값이 빈 문자열인 키는 번역 대상이 아니다.
        # 값이 없으니 폴백돼도 화면에 아무것도 안 나오고, 빈 문자열을 로케일마다
        # 복사해 두는 것은 관리 대상만 늘린다 (예: upgradeList)
        skip = untranslatable(os.path.join(RES, "values/strings.xml"))
        translatable = {k for k, v in base.items() if v.strip() and k not in skip}
        miss = sorted(translatable - set(d))
        mark = "" if not miss else "  <-- 확인 필요"
        print("  %-3s 누락 %4d개%s" % (loc, len(miss), mark))
        if miss:
            found = True
            print("       예: %s" % ", ".join(miss[:8]))

    print()
    print("=" * 60)
    print("2) 한국어가 아닌 로케일 파일에 한글이 그대로 남은 값")
    print("   번역하지 않고 한국어를 복사해 둔 자리다")
    print("=" * 60)
    targets = [l for l in LOCALES if l != "ko"] + ["기본(en)"]
    for loc in targets:
        path = os.path.join(RES, "values/strings.xml") if loc.startswith("기본") \
            else os.path.join(RES, "values-%s/strings.xml" % loc)
        d = load(path)
        if d is None:
            continue
        bad = sorted(k for k, v in d.items() if KOR.search(v))
        print("  %-8s %4d개" % (loc, len(bad)))
        if bad:
            found = True
            print("       %s" % ", ".join(bad[:8]))

    print()
    print("요약: %s" % ("문제 발견" if found else "문제 없음"))
    return 1 if found else 0


if __name__ == "__main__":
    sys.exit(main())
