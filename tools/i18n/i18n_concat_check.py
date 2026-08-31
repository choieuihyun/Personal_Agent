#!/usr/bin/env python3
# 다국어 조립 안티패턴 검사기
# 역할: 문자열을 코드에서 이어 붙이는 자리를 찾는다. 조각이 각각 번역돼 있어도
#       조립하면 어순이 다른 언어에서 깨진다. 동적 검사(화면 덤프)로는 못 잡는 사각이다.
#
# 왜 필요한가:
#   렌더된 최종 텍스트만 보는 스캐너는 "하드코딩된 한글"은 잡아도 "조립" 자체는 못 잡는다.
#   조각이 전부 stringResource 면 영어 화면에선 전부 영어라 통과하는데, 러시아어/베트남어는
#   숫자·수식어 위치가 달라 조립이 깨진다. 정답은 %s 포맷 문자열로 위치를 번역자에게 넘기는 것.
#
# 사용법: i18n_concat_check.py
# 종료코드: 0 = 없음, 1 = 발견

import os, re, sys
# 소스 루트는 환경변수로 받는다. 프로젝트마다 다르므로 경로를 코드에 박지 않는다.
_REPO = os.environ.get("I18N_REPO") or os.path.dirname(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC = os.environ.get("I18N_SRC") or os.path.join(_REPO, "src")
if not os.path.isdir(SRC):
    print("소스 루트를 찾지 못했다: %s (I18N_SRC 로 지정한다)" % SRC)
    sys.exit(2)

# 1) stringResource / getString 를 + 로 잇기
CONCAT = re.compile(r'(stringResource\([^)]*\)\s*\+|\+\s*stringResource\(|getString\([^)]*\)\s*\+|\+\s*getString\()')
# 2) 문자열 템플릿 안에서 변수 뒤/앞에 한글 리터럴 (예: "$name 검색", "${n}명")
TEMPLATE = re.compile(r'"[^"]*\$\{?[A-Za-z_][^"]*[가-힣][^"]*"')
# 치수 계산 등 오탐 제외
SKIP = ("Modifier", ".dp", ".sp", "toPx", "Log.", "// ", "* ")

def main():
    hits = []
    for root, _, files in os.walk(SRC):
        for fn in files:
            if not fn.endswith(".kt"): continue
            p = os.path.join(root, fn)
            for i, line in enumerate(open(p, encoding="utf-8", errors="ignore"), 1):
                st = line.strip()
                if st.startswith(("//", "*", "/*")): continue
                if any(s in st for s in SKIP): continue
                if CONCAT.search(line) or TEMPLATE.search(line):
                    hits.append((os.path.relpath(p, SRC), i, st[:90]))
    print("문자열 조립 후보 %d건 (조각이 번역돼 있어도 어순이 깨질 수 있다)\n" % len(hits))
    for rel, i, txt in hits:
        print("  %s:%d\n      %s" % (rel, i, txt))
    print("\n주의: 후보다. 날짜 포맷처럼 의도적으로 조립하는 것도 섞인다. 사람이 판정한다.")
    return 1 if hits else 0

if __name__ == "__main__":
    sys.exit(main())
