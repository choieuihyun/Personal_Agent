#!/usr/bin/env python3
# 다국어 노출 검사기
# 역할: 화면 계층 덤프에서 한글 UI 문자열을 찾아 "미번역" 과 "데이터" 로 가른다.
# 성격: 결정적. 판단 근거는 values-ko/strings.xml 대조 하나뿐이다.
#
# 왜 대조가 필요한가:
#   "영어 로케일인데 한글이 보이면 버그" 는 틀린 규칙이다.
#   사람 이름, 부서명, 쪽지 제목은 로케일과 무관하게 한글이라 오탐이 쏟아진다.
#   화면에 뜬 한글이 values-ko 의 값과 같으면 그것은 UI 문자열이 한국어로 나온 것이고,
#   다르면 데이터이거나 코드에 하드코딩된 문자열이다.
#
# 사용법: i18n_report.py <hierarchy.json> [<hierarchy.json> ...]

import json
import os
import re
import sys

KOR = re.compile(r'[가-힣]')
# 우리 앱이 아닌 곳에서 온 한글. 계층에는 들어오지만 검사 대상이 아니다.
# Maestro 가 자기 테스트 APK 를 설치할 때 안드로이드가 띄우는 토스트가 덤프에 잡힌다(실측)
NOISE = ("[dev.mobile.maestro", "dev.mobile.maestro")
# 계층에 늘 섞여 들어오는 남의 앱. 검사 대상이 아니다
FOREIGN = ("systemui", "launcher", "honeyboard", "com.google", "com.samsung")

# 서버/사용자 데이터를 그리는 행의 testTag 접두사.
# 이 안의 텍스트는 로케일과 무관하게 한글일 수 있으므로 검사 대상이 아니다.
# 이 구분이 없으면 부서명 "조직도", 그룹명 "테스트용" 같은 데이터가 미번역으로 잡힌다(실측).
DATA_TAG_PREFIXES = (
    "org_group_", "org_person_",
    "buddy_group_", "buddy_subgroup_", "buddy_person_",
    "item_message_", "recipient_chip_",
    # 대화 목록 행. 방 이름/참여자/마지막 메시지가 전부 데이터다.
    # 대화방과 멤버추가 화면은 목록 위에 얹히므로 이 데이터가 그쪽 덤프에도 그대로 섞인다
    "chat_room_",
    "member_search_person_", "member_search_group_",
    "note_view_subject", "note_view_sender",
)

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
KO_XML = os.path.join(REPO, "app/src/main/res/values-ko/strings.xml")


def load_ko_strings():
    # values-ko 의 값 -> 키 역인덱스. 화면 텍스트를 값으로 조회하기 위함이다
    if not os.path.exists(KO_XML):
        return {}
    src = open(KO_XML, encoding="utf-8").read()
    out = {}
    for key, val in re.findall(r'<string name="([^"]+)"[^>]*>(.*?)</string>', src, re.S):
        v = val.strip()
        # 포맷 인자(%1$s)가 든 문자열은 화면에서 치환돼 나오므로 그대로 대조되지 않는다
        if not v or "%" in v:
            continue
        out.setdefault(v, key)
    return out


def texts_of(path):
    # 덤프에서 우리 앱 소유 텍스트를 모으되, 데이터 행 안의 것은 따로 표시한다.
    # 조상을 따라가는 이유: testTag 는 행 컨테이너에 붙고 글자는 그 자식이라
    # 텍스트 노드 자신에는 태그가 없다.
    with open(path, encoding="utf-8") as f:
        raw = f.read().strip()
    if not raw:
        # 덤프가 중간에 끊겨 빈 파일이 남을 수 있다. 검사 대상에서 조용히 뺀다
        return []
    root = json.loads(raw)
    found = []

    def walk(node, in_data):
        attrs = node.get("attributes", {})
        rid = attrs.get("resource-id", "") or ""
        if any(f in rid for f in FOREIGN):
            return
        if rid.startswith(DATA_TAG_PREFIXES):
            in_data = True
        text = (attrs.get("text", "") or "").strip()
        if text:
            found.append((text, in_data))
        for child in node.get("children", []) or []:
            walk(child, in_data)

    walk(root, False)
    return found


def main():
    if len(sys.argv) < 2:
        print("사용법: i18n_report.py <hierarchy.json> ...")
        return 2

    ko = load_ko_strings()
    if not ko:
        print("경고: values-ko/strings.xml 을 읽지 못했다. 대조 없이 한글만 나열한다.")

    untranslated = {}   # 문자열 -> (키, 화면들)
    unknown = {}        # 문자열 -> 화면들
    skipped = 0         # 데이터 행이라 제외한 건수

    for path in sys.argv[1:]:
        screen = os.path.splitext(os.path.basename(path))[0]
        for text, in_data in texts_of(path):
            if not KOR.search(text):
                continue
            if any(n in text for n in NOISE):
                continue
            if in_data:
                skipped += 1
                continue
            key = ko.get(text)
            bucket = untranslated if key else unknown
            entry = bucket.setdefault(text, [key, []])
            if screen not in entry[1]:
                entry[1].append(screen)

    print("=" * 60)
    print("미번역 의심 (values-ko 값과 일치하는 한글이 노출됨)")
    print("=" * 60)
    if not untranslated:
        print("  없음")
    for text, (key, screens) in sorted(untranslated.items()):
        print(f"  [{key}] {text!r}")
        print(f"      화면: {', '.join(screens)}")

    print()
    print("=" * 60)
    print("하드코딩 의심 (리소스에 없는 한글이 노출됨)")
    print("=" * 60)
    if not unknown:
        print("  없음")
    for text, (_, screens) in sorted(unknown.items()):
        print(f"  {text!r}  ({', '.join(screens)})")

    print()
    print(f"요약: 미번역 의심 {len(untranslated)}건 / 하드코딩 의심 {len(unknown)}건"
          f" / 데이터로 제외 {skipped}건")
    print("주의: 두 통 모두 '의심'이다. 데이터가 UI 문자열과 우연히 같으면 미번역으로 잡히고,")
    print("      데이터 행 태그가 없는 화면은 데이터가 하드코딩으로 잡힌다. 사람이 확인한다.")
    # 미번역이 하나라도 있으면 실패로 본다. 판정필요는 사람이 봐야 하므로 실패로 세지 않는다
    return 1 if untranslated else 0


if __name__ == "__main__":
    sys.exit(main())
