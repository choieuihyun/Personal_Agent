#!/usr/bin/env python3
# hunt.json 작성기
# 역할: crash_hunt.sh 가 남긴 monkey 출력과 logcat 을 훑어 이상 신호를 분류하고 hunt.json 에 기록한다.
# 성격: 결정적. 패턴 매칭만 한다. 원인 판단은 하지 않는다 (판단은 사람 또는 triage).

import os
import re
import json
import datetime

# 우리 코드로 인정할 패키지/모듈 접두사. 환경변수로 받는다.
# 스택트레이스의 어느 줄이 우리 것인지는 프로젝트마다 다르므로 여기 박아두지 않는다.
# 비어 있으면 "우리 코드 예외" 항목만 건너뛴다. 나머지 신호(크래시/ANR/성능)는 그대로 잡는다.
SRC_PREFIX = os.environ.get("HT_SRC_PREFIX", "")

# 이상 신호 분류. 심각도 순.
# severity CRASH  : 앱이 죽었다. 무조건 고쳐야 한다.
# severity ANR    : 응답 없음. 사용자에게 크래시만큼 나쁘다.
# severity ERROR  : 크래시는 안 났지만 예외가 났다. 조용히 기능이 죽었을 수 있다.
# severity WARN   : 성능/규약 위반. 당장 안 죽지만 쌓이면 문제다.
PATTERNS = [
    ("CRASH", "FATAL_EXCEPTION", re.compile(r"FATAL EXCEPTION")),
    ("CRASH", "NATIVE_CRASH", re.compile(r"\bbacktrace:|signal \d+ \(SIG")),
    ("ANR", "ANR", re.compile(r"\bANR in\b|Reason:.*Input dispatching timed out")),
    ("ERROR", "UNCAUGHT_IN_LOG", re.compile(r"AndroidRuntime.*(Exception|Error)")),
    ("WARN", "STRICTMODE", re.compile(r"StrictMode policy violation")),
    ("WARN", "SKIPPED_FRAMES", re.compile(r"Skipped (\d+) frames")),
    ("WARN", "CHOREOGRAPHER_JANK", re.compile(r"Davey! duration=(\d+)ms")),
    ("WARN", "WINDOW_LEAK", re.compile(r"WindowLeaked|has leaked window")),
]

# 우리 코드 스택 라인은 접두사를 알 때만 잡는다.
# 접두사 없이 "at " 만 보면 라이브러리 프레임까지 전부 걸려 잡음이 된다.
if SRC_PREFIX:
    PATTERNS.append(
        ("ERROR", "EXCEPTION_TRACE", re.compile(r"^\s*at " + re.escape(SRC_PREFIX)))
    )

# 프레임 드랍은 흔해서 임계값을 둔다. 이 아래는 잡음이다.
SKIPPED_FRAMES_MIN = 60
DAVEY_MS_MIN = 1000


def env(name, default=""):
    v = os.environ.get(name, default)
    return v if v != "" else default


def read_lines(path):
    if not path or not os.path.exists(path):
        return []
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        return f.read().splitlines()


def scan_logcat(lines, pkg):
    """logcat 을 훑어 이상 신호를 모은다. 같은 종류는 대표 1건 + 건수로 접는다."""
    found = {}
    crash_traces = []
    capture = 0
    trace = []

    for line in lines:
        # FATAL EXCEPTION 이후 몇 줄은 스택이므로 함께 담는다 (원인 파악에 필수)
        if capture > 0:
            trace.append(line.strip())
            capture -= 1
            if capture == 0:
                crash_traces.append("\n".join(trace))
                trace = []

        for severity, kind, rx in PATTERNS:
            m = rx.search(line)
            if not m:
                continue

            # 임계값 필터 (잡음 제거)
            if kind == "SKIPPED_FRAMES":
                try:
                    if int(m.group(1)) < SKIPPED_FRAMES_MIN:
                        continue
                except Exception:
                    continue
            if kind == "CHOREOGRAPHER_JANK":
                try:
                    if int(m.group(1)) < DAVEY_MS_MIN:
                        continue
                except Exception:
                    continue

            entry = found.setdefault(kind, {
                "severity": severity,
                "kind": kind,
                "count": 0,
                "sample": line.strip()[:300],
            })
            entry["count"] += 1

            if kind == "FATAL_EXCEPTION" and capture == 0:
                trace = [line.strip()]
                capture = 20
            break

    return list(found.values()), crash_traces


def scan_monkey(lines):
    """monkey 출력에서 자체 보고한 크래시/ANR 을 찾는다."""
    signals = []
    for line in lines:
        if "// CRASH" in line:
            signals.append({"kind": "MONKEY_CRASH", "line": line.strip()[:300]})
        elif "// NOT RESPONDING" in line:
            signals.append({"kind": "MONKEY_ANR", "line": line.strip()[:300]})
    return signals


def main():
    session_dir = env("HT_SESSION", ".")
    raw_log = env("HT_RAWLOG")
    monkey_log = env("HT_MONKEYLOG")
    pkg = env("HT_PKG", "")
    device = env("HT_DEVICE", "false") == "true"
    events = env("HT_EVENTS", "0")
    monkey_exit_raw = env("HT_MONKEY_EXIT", "null")

    try:
        monkey_exit = int(monkey_exit_raw)
    except Exception:
        monkey_exit = None

    findings, crash_traces = scan_logcat(read_lines(raw_log), pkg)
    monkey_signals = scan_monkey(read_lines(monkey_log))

    by_sev = {"CRASH": 0, "ANR": 0, "ERROR": 0, "WARN": 0}
    for f in findings:
        by_sev[f["severity"]] = by_sev.get(f["severity"], 0) + f["count"]

    # monkey 가 스스로 크래시를 보고했으면 로그 패턴과 무관하게 크래시로 친다
    if monkey_signals:
        for s in monkey_signals:
            if s["kind"] == "MONKEY_CRASH":
                by_sev["CRASH"] += 1
            else:
                by_sev["ANR"] += 1

    # 사냥 성립 여부. 기기가 없거나 이벤트를 못 돌렸으면 "이상 없음" 이 아니라 "확인 못 함" 이다.
    executed = device and monkey_exit is not None

    hunt = {
        "updated_at": datetime.datetime.now().astimezone().isoformat(),
        "package": pkg,
        "device_connected": device,
        "executed": executed,
        "events_requested": int(events) if str(events).isdigit() else 0,
        "monkey_exit_code": monkey_exit,
        "clean": executed and by_sev["CRASH"] == 0 and by_sev["ANR"] == 0,
        "counts": by_sev,
        "findings": sorted(findings, key=lambda f: ["CRASH", "ANR", "ERROR", "WARN"].index(f["severity"])),
        "monkey_signals": monkey_signals,
        "crash_traces": crash_traces[:3],
        "logcat_path": raw_log,
        "monkey_log_path": monkey_log,
    }

    out_path = os.path.join(session_dir, "hunt.json")
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(hunt, f, ensure_ascii=False, indent=2)

    print("hunt.json 기록 완료: " + out_path)
    if not executed:
        print("  사냥 미수행 (기기 미연결 또는 monkey 실행 실패). 이상 없음이 아니라 확인 못 함이다.")
    else:
        print("  CRASH=%d ANR=%d ERROR=%d WARN=%d (clean=%s)" % (
            by_sev["CRASH"], by_sev["ANR"], by_sev["ERROR"], by_sev["WARN"], hunt["clean"]))
        for f in hunt["findings"]:
            print("   [%s] %s x%d" % (f["severity"], f["kind"], f["count"]))


if __name__ == "__main__":
    main()
