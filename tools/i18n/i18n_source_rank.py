#!/usr/bin/env python3
# 화면 코드의 한글 리터럴 순위표
# 역할: 동적 검사(i18n_scan.sh)를 어느 화면부터 붙일지 정하는 우선순위를 뽑는다.
# 성격: 힌트다. 게이트가 아니다. 정상 한글과 버그를 못 가른다.
#
# 제외 규칙 (실측으로 필요성이 드러난 것들):
#   1. @Preview 함수 본문 - 더미 데이터라 사용자에게 안 보인다.
#      이걸 안 빼면 MoreScreen 이 19건으로 2위에 오는데 실제 화면엔 문제가 없다(2026-08-24 확인).
#   2. 한국어 자체를 다루는 파일 - 날짜 파서, 한글 별명 생성기 등은 한글이 있어야 정상이다.
#   3. 주석과 로그 - 프로젝트 규칙상 한글로 쓴다.
#
# 사용법: i18n_source_rank.py [상위N]

import os
import re
import sys

REPO = os.environ.get("I18N_REPO") or os.path.dirname(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
# 소스 루트는 환경변수로 받는다. 프로젝트마다 다르므로 경로를 코드에 박지 않는다.
SRC = os.environ.get("I18N_SRC") or os.path.join(REPO, "src")
if not os.path.isdir(SRC):
    print("소스 루트를 찾지 못했다: %s (I18N_SRC 로 지정한다)" % SRC)
    sys.exit(2)

LITERAL = re.compile(r'"([^"\\]*[가-힣][^"\\]*)"')
# 한국어 처리가 목적이라 한글이 있어야 정상인 파일
SKIP_FILES = ("KoDateTimeDetector", "ChatCaptureAnonymizer", "RoomAvatarText", "LoginDebugMenu")


def korean_literals(path):
    # @Preview 함수 본문을 중괄호 깊이로 추적해 건너뛴다
    lines = open(path, encoding="utf-8", errors="ignore").read().split("\n")
    out = []
    preview_pending = False   # @Preview 를 봤고 함수 시작을 기다리는 중
    preview_depth = None      # 스킵 중인 함수의 시작 깊이
    depth = 0

    for no, line in enumerate(lines, 1):
        stripped = line.strip()

        if preview_depth is None and stripped.startswith("@Preview"):
            preview_pending = True

        opens = line.count("{")
        closes = line.count("}")

        if preview_pending and opens > 0:
            preview_depth = depth
            preview_pending = False

        skipping = preview_depth is not None

        if not skipping and not stripped.startswith(("//", "*", "/*")) \
                and "Log." not in stripped and "TAG" not in stripped:
            for hit in LITERAL.findall(line):
                out.append((no, hit))

        depth += opens - closes
        if preview_depth is not None and depth <= preview_depth:
            preview_depth = None

    return out


def main():
    top = int(sys.argv[1]) if len(sys.argv) > 1 else 15
    counts = {}
    for root, _, files in os.walk(SRC):
        for fn in files:
            if not fn.endswith(".kt") or any(s in fn for s in SKIP_FILES):
                continue
            path = os.path.join(root, fn)
            hits = korean_literals(path)
            if hits:
                counts[path] = hits

    total = sum(len(v) for v in counts.values())
    print("화면 코드의 한글 리터럴: 총 %d건 / %d파일 (@Preview 제외)" % (total, len(counts)))
    print("동적 검사를 붙일 우선순위다. 게이트가 아니라 힌트다.\n")
    for i, (path, hits) in enumerate(sorted(counts.items(), key=lambda kv: -len(kv[1]))[:top], 1):
        rel = os.path.relpath(path, SRC)
        print("  %2d. %3d건  %s" % (i, len(hits), rel))
        for no, text in hits[:2]:
            print("            %d: \"%s\"" % (no, text[:34]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
