#!/usr/bin/env python3
# 하네스 세팅 화면 (결정적, LLM 미개입)
# 역할: 이 프로젝트에 하네스가 어떻게 세팅돼 있는지 HTML 한 장으로 그린다. 보기 전용이다.
#
# 무엇을 읽나 (설치된 파일만 읽고 아무것도 고치지 않는다):
#   .claude/project.json 과 어댑터       설정값
#   .claude/agents/*/AGENT.md             에이전트의 도구 (tools, /setup 이 붙인 tools_extra)
#   .claude/setup/*.md                    에이전트 소개와 질문 표. 질문 표의 "저장 위치" 를 실제 값과 맞대
#                                         무엇이 채워졌고 무엇이 비었는지, 비면 어떻게 되는지를 낸다
#   .claude/project/agents/*.md           /setup 이 채운 에이전트별 보충
#   <docs.domain_map>/*/DOMAIN.md         도메인 문서의 절별 채움 상태
#   .claude/.harness-manifest             설치된 하네스 버전
#
# 왜 LLM 이 아니라 스크립트로 그리나: 보여 주는 값이 실제 파일과 한 글자도 달라서는 안 된다.
# 파일 밖으로 아무것도 보내지 않는다. 결과는 .claude/state/harness-view.html 이다 (커밋 대상 아님).
#
# 사용법: harness_view.py [--open] [project_dir]

import html
import json
import os
import re
import subprocess
import sys
import webbrowser

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import harness_config
import harness_manifest

# 파이프라인 순서는 뼈대가 정한다 (core/commands). 여기서는 그림으로 옮길 뿐이다.
PIPELINES = [
    ("/fix", "버그 수정", ["explorer", "implementer", "builder", "@gate", "triage", "documenter"]),
    ("/feature", "신규 기능", ["discuss", "spec", "planner", "plan-checker", "@approve", "explorer",
                            "implementer", "verifier", "builder", "@gate", "triage", "documenter"]),
    ("/study", "학습", ["tutor"]),
]
STEPS = {"@gate": ("런타임 게이트", "셸이 올리기, 시나리오 재생, 내리기를 하고 JUnit 결과로 판정한다. LLM 미개입"),
         "@approve": ("사람 승인", "명세와 설계를 보고 사용자가 승인해야 구현이 시작된다")}


def read(path):
    try:
        with open(path, encoding="utf-8") as f:
            return f.read()
    except OSError:
        return ""


def frontmatter(text):
    m = re.match(r"^---\n(.*?)\n---\n", text, re.S)
    out = {}
    if m:
        for line in m.group(1).split("\n"):
            k, _, v = line.partition(":")
            if v:
                out[k.strip()] = v.strip()
    return out, text[m.end():] if m else text


def section(body, title):
    m = re.search(r"^## %s\s*\n(.*?)(?=^## |\Z)" % re.escape(title), body, re.S | re.M)
    return m.group(1).strip() if m else ""


def filled(v):
    return v is not None and v != "" and v != [] and v != {}


def lookup(cfg, ad, key):
    # 저장 위치 한 칸이 채워졌는지. 반환: (채움 여부, 보여 줄 값)
    if key == "adapter":
        name = cfg.get("adapter") or ("inline: " + (cfg.get("adapter_inline") or {}).get("name", "")
                                      if cfg.get("adapter_inline") else "")
        return filled(name), name
    if key.startswith("adapter_override") or key == "adapter_inline":
        sub = key.split(".", 1)[1] if "." in key else None
        if sub:
            v = (ad or {}).get(sub)
            return filled(v), v
        v = cfg.get(key)
        return filled(v), v
    cur = cfg
    for part in key.split("."):
        cur = cur.get(part) if isinstance(cur, dict) else None
    return filled(cur), cur


def cell(row, i):
    c = [x.strip() for x in row.strip().strip("|").split("|")]
    return c[i] if len(c) > i else ""


def questions(body, cfg, ad, root, agent, domains_filled, tools_extra):
    out = []
    for row in body.split("\n"):
        if not re.match(r"^\| \d+ \|", row):
            continue
        where_raw = cell(row, 3)
        keys = re.findall(r"`([^`]+)`", where_raw)
        state, value = False, None
        for k in keys:
            if k.startswith(".claude/project/agents/"):
                p = os.path.join(root, k)
                ok = os.path.isfile(p)
                state, value = state or ok, ("있음" if ok else None)
            elif k == "DOMAIN.md":
                state, value = state or domains_filled, ("도메인 문서 있음" if domains_filled else None)
            elif k == "tools:":
                state, value = state or bool(tools_extra), (", ".join(tools_extra) or None)
            else:
                ok, v = lookup(cfg, ad, k)
                if ok:
                    state, value = True, v
        out.append({"q": cell(row, 1), "where": ", ".join(keys) or where_raw, "filled": state,
                    "value": value if not isinstance(value, (dict, list)) else json.dumps(value, ensure_ascii=False)[:300],
                    "ifempty": cell(row, 4)})
    return out


def domain_docs(root, cfg):
    base = ((cfg.get("docs") or {}).get("domain_map") or "").strip()
    out = []
    if not base:
        return out, base
    d = os.path.join(root, base)
    if not os.path.isdir(d):
        return out, base
    for name in sorted(os.listdir(d)):
        text = read(os.path.join(d, name, "DOMAIN.md"))
        if not text:
            continue
        secs = []
        for m in re.finditer(r"^## (.+?)\s*\n(.*?)(?=^## |\Z)", text, re.S | re.M):
            body = re.sub(r"<!--.*?-->", "", m.group(2), flags=re.S)
            lines = [l for l in body.split("\n") if l.strip() and not re.match(r"^\s*\|?[\s|:-]*\|?\s*$", l)
                     and l.strip() not in ("-",) and not re.match(r"^\|[^|]*(용어|파일|축|날짜)[^|]*\|", l)]
            lines = [l for l in lines if not re.fullmatch(r"\s*(-\s*)?(태그|위치):\s*(`<[^>]*>`)?\s*", l)]
            secs.append({"name": m.group(1), "filled": bool(lines)})
        out.append({"name": name, "sections": secs})
    return out, base


def run(args, cwd):
    try:
        r = subprocess.run(args, cwd=cwd, capture_output=True, text=True, timeout=10)
        return r.stdout.strip()
    except (OSError, subprocess.TimeoutExpired):
        return ""


def collect(root):
    dest = os.path.join(root, ".claude")
    cfg = harness_config.load(root) or {}
    ad = harness_config.adapter(cfg) or {}
    agents_cfg = cfg.get("agent_tools") or {}
    docs, domain_map = domain_docs(root, cfg)
    domains_filled = bool(docs)
    agents = {}
    for name in sorted(os.listdir(os.path.join(dest, "agents"))) if os.path.isdir(os.path.join(dest, "agents")) else []:
        fm, _ = frontmatter(read(os.path.join(dest, "agents", name, "AGENT.md")))
        gfm, gbody = frontmatter(read(os.path.join(dest, "setup", name + ".md")))
        extra = [t.strip() for t in fm.get("tools_extra", "").split(",") if t.strip()] or agents_cfg.get(name, [])
        base_tools = [t.strip() for t in fm.get("tools", "").split(",") if t.strip() and t.strip() not in extra]
        title = re.search(r"^# (.+)$", gbody, re.M)
        qs = questions(gbody, cfg, ad, root, name, domains_filled, extra)
        sup = read(os.path.join(dest, "project", "agents", name + ".md"))
        agents[name] = {
            "title": title.group(1) if title else name,
            "what": section(gbody, "무엇을 하나"),
            "cannot": section(gbody, "못 하는 것"),
            "gives": section(gbody, "넘겨주는 것"),
            "tools": base_tools, "mcp": extra, "mcp_hint": gfm.get("mcp", ""),
            "questions": qs, "supplement": sup,
        }
    m = harness_manifest.meta(dest)
    update = run([sys.executable, os.path.join(dest, "scripts", "harness_version.py"), root], root)
    selfcheck = run([sys.executable, os.path.join(dest, "scripts", "domains_for.py"), "--self-check"], root)
    e2e_dir = (cfg.get("e2e") or {}).get("dir") or ((ad.get("e2e") or {}).get("dir_default") or "")
    coverage = run([sys.executable, os.path.join(dest, "scripts", "e2e_tags.py"), "--coverage",
                    os.path.join(root, e2e_dir)], root) if e2e_dir else ""
    known = []
    for r in ((cfg.get("domains") or {}).get("dir_rules") or []):
        known += r.get("known") or []
    return {
        "project": (cfg.get("project") or {}).get("name") or os.path.basename(os.path.abspath(root)),
        "config_found": bool(cfg),
        "has_ui": (cfg.get("project") or {}).get("has_ui"),
        "adapter": cfg.get("adapter") or ("inline: " + (cfg.get("adapter_inline") or {}).get("name", "") if cfg.get("adapter_inline") else ""),
        "runtime_gate": cfg.get("runtime_gate", True),
        "build": ad.get("build") or "", "deploy": ad.get("deploy") or "", "teardown": ad.get("teardown") or "",
        "e2e_dir": e2e_dir, "coverage": [c for c in coverage.split(",") if c], "known_domains": known,
        "selfcheck": selfcheck, "domain_map": domain_map, "domains": docs,
        "commit": m.get("harness_commit", "")[:7], "installed_at": m.get("installed_at", ""), "update": update,
        "agents": agents, "pipelines": PIPELINES, "steps": STEPS,
    }


PAGE = r"""<!doctype html>
<html lang="ko"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>하네스 세팅: __PROJECT__</title>
<style>
:root{--bg:#f7f7f5;--card:#fff;--ink:#1d1d1f;--muted:#6b6b70;--rule:#e2e2df;--ok:#2e7d32;--okbg:#e8f5e9;--warn:#b26a00;--warnbg:#fff4e0;
--empty:#9a9aa0;--llm:#5e35b1;--llmbg:#ede7f6;--sh:#2e7d32;--shbg:#e8f5e9;--human:#ef6c00;--humanbg:#fff3e0;--sel:#1565c0}
@media (prefers-color-scheme:dark){:root{--bg:#161618;--card:#1f1f22;--ink:#ececef;--muted:#9a9aa3;--rule:#34343a;--okbg:#1b2e1d;--warnbg:#33260f;
--llmbg:#2a2238;--shbg:#1b2e1d;--humanbg:#33240f;--sel:#64b5f6}}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--ink);font:14px/1.55 -apple-system,BlinkMacSystemFont,"Apple SD Gothic Neo","Noto Sans KR",sans-serif}
main{max-width:1200px;margin:0 auto;padding:24px 16px 64px}h1{font-size:22px;margin:0 0 4px}h2{font-size:16px;margin:32px 0 10px}
.sub{color:var(--muted)}.cards{display:grid;grid-template-columns:repeat(auto-fit,minmax(200px,1fr));gap:10px;margin-top:16px}
.card{background:var(--card);border:1px solid var(--rule);border-radius:8px;padding:10px 12px}.card b{display:block;font-size:12px;color:var(--muted);font-weight:500}
.card span{word-break:break-all}.banner{margin-top:12px;padding:10px 12px;border-radius:8px;background:var(--warnbg);color:var(--warn)}
.pipe{background:var(--card);border:1px solid var(--rule);border-radius:8px;padding:12px;margin-bottom:10px}
.pipe h3{margin:0 0 8px;font-size:14px}.flow{display:flex;flex-wrap:wrap;align-items:center;gap:6px}
.node{border:1.5px solid var(--llm);background:var(--llmbg);border-radius:6px;padding:6px 10px;cursor:pointer;font-size:13px;position:relative}
.node.step{border-color:var(--sh);background:var(--shbg);cursor:default}.node.human{border-color:var(--human);background:var(--humanbg)}
.node.sel{outline:2px solid var(--sel);outline-offset:2px}.node small{display:block;font-size:11px;color:var(--muted)}
.arrow{color:var(--muted)}.dot{display:inline-block;width:8px;height:8px;border-radius:50%;margin-right:5px;vertical-align:1px}
.d-ok{background:var(--ok)}.d-part{background:var(--warn)}.d-none{background:var(--empty)}
.layout{display:grid;grid-template-columns:1fr;gap:12px}@media(min-width:900px){.layout{grid-template-columns:minmax(0,1fr) minmax(0,1.3fr)}}
.panel{background:var(--card);border:1px solid var(--rule);border-radius:8px;padding:14px 16px;min-height:200px}
.panel h3{margin:0 0 2px;font-size:16px}.panel h4{margin:16px 0 6px;font-size:13px;color:var(--muted)}
.panel p{margin:4px 0;white-space:pre-wrap}.tag{display:inline-block;border:1px solid var(--rule);border-radius:4px;padding:1px 6px;margin:2px;font-size:12px}
.tag.mcp{border-color:var(--sel);color:var(--sel)}
table{width:100%;border-collapse:collapse;font-size:13px}th,td{text-align:left;padding:6px 6px;border-bottom:1px solid var(--rule);vertical-align:top}
th{color:var(--muted);font-weight:500}.st-ok{color:var(--ok);white-space:nowrap}.st-no{color:var(--warn);white-space:nowrap}
code,.mono{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:12px}pre{white-space:pre-wrap;margin:4px 0;font-size:12px;background:var(--bg);padding:8px;border-radius:6px}
.legend{font-size:12px;color:var(--muted);margin:6px 0 10px}.sec{display:inline-block;margin:2px 8px 2px 0;font-size:12px}
.hint{font-size:12px;color:var(--muted)}
</style></head><body><main>
<h1>하네스 세팅: __PROJECT__</h1>
<div class="sub">보기 전용 화면이다. 바꾸려면 Claude Code 에서 <code>/setup</code> 을 부른다. 다시 그리려면 <code>/harness-view</code>.</div>
<div id="top"></div>
<h2>파이프라인</h2>
<div class="legend"><span class="dot d-ok"></span>물어볼 것 다 채움 <span class="dot d-part"></span>일부 비어 있음 <span class="dot d-none"></span>하나도 안 채움 · 에이전트를 누르면 오른쪽에 자세히 나온다</div>
<div class="layout"><div id="pipes"></div><div class="panel" id="panel"><div class="hint">에이전트를 누르면 역할, 도구, 설정 상태, 보충 칸이 여기 나온다.</div></div></div>
<h2>도메인</h2><div id="domains"></div>
<h2>비어 있는 설정</h2><div id="empties"></div>
</main>
<script>
const D = __DATA__;
const esc = s => String(s ?? "").replace(/[&<>"]/g, c => ({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;"}[c]));
function state(a){const q=a.questions; if(!q.length) return "ok"; const f=q.filter(x=>x.filled).length; return f===q.length?"ok":(f?"part":"none");}
function renderTop(){
  let h=`<div class="cards">`;
  const c=(k,v)=>h+=`<div class="card"><b>${k}</b><span>${v}</span></div>`;
  c("화면이 있나 (has_ui)", D.has_ui===null||D.has_ui===undefined?"<span class='st-no'>모름 (화면이 있는 것으로 본다)</span>":(D.has_ui?"있음":"없음"));
  c("어댑터", D.adapter?esc(D.adapter):"<span class='st-no'>없음 (게이트 exit 3)</span>");
  c("런타임 게이트", D.runtime_gate===false?"꺼짐":"켜짐");
  c("빌드", `<code>${esc(D.build)||"-"}</code>`);
  c("올리기 / 내리기", `<code>${esc(D.deploy)||"없음"}</code><br><code>${esc(D.teardown)||"없음"}</code>`);
  c("시나리오", `<code>${esc(D.e2e_dir)||"-"}</code><br>덮는 도메인: ${D.coverage.length?esc(D.coverage.join(", ")):"<span class='st-no'>알 수 없음</span>"}`);
  c("도메인 규칙", esc(D.selfcheck)||"-");
  c("하네스 버전", `${esc(D.commit)||"기록 없음"} <span class="sub">${esc(D.installed_at)}</span>`);
  h+=`</div>`;
  if(!D.config_found) h+=`<div class="banner">.claude/project.json 을 찾지 못했다. install.sh 로 설치한 뒤 /setup 을 부른다.</div>`;
  if(D.update) h+=`<div class="banner">${esc(D.update)}</div>`;
  const uncovered=D.known_domains.filter(d=>!D.coverage.includes(d));
  if(D.coverage.length&&uncovered.length) h+=`<div class="banner">시나리오가 없는 도메인: ${esc(uncovered.join(", "))}. 이 도메인만 고치면 런타임 검증이 없다.</div>`;
  document.getElementById("top").innerHTML=h;
}
function renderPipes(){
  let h="";
  for(const [cmd,label,seq] of D.pipelines){
    h+=`<div class="pipe"><h3>${esc(cmd)} <span class="sub">${esc(label)}</span></h3><div class="flow">`;
    seq.forEach((n,i)=>{
      if(i) h+=`<span class="arrow">→</span>`;
      if(n.startsWith("@")){const [t,d]=D.steps[n]; h+=`<div class="node step ${n==="@approve"?"human":""}" title="${esc(d)}">${esc(t)}</div>`;}
      else{const a=D.agents[n]; if(!a){h+=`<div class="node step">${esc(n)} (없음)</div>`;return;}
        const f=a.questions.filter(x=>x.filled).length;
        h+=`<div class="node" data-a="${esc(n)}"><span class="dot d-${state(a)}"></span>${esc(n)}<small>${f}/${a.questions.length} 채움${a.mcp.length?" · MCP "+a.mcp.length:""}${a.supplement?" · 보충":""}</small></div>`;}
    });
    h+=`</div></div>`;
  }
  const el=document.getElementById("pipes"); el.innerHTML=h;
  el.querySelectorAll(".node[data-a]").forEach(n=>n.onclick=()=>show(n.dataset.a));
}
function show(name){
  document.querySelectorAll(".node").forEach(n=>n.classList.toggle("sel",n.dataset.a===name));
  const a=D.agents[name];
  let h=`<h3>${esc(a.title)}</h3>`;
  if(a.what) h+=`<h4>무엇을 하나</h4><p>${esc(a.what)}</p>`;
  h+=`<h4>도구</h4>${a.tools.map(t=>`<span class="tag">${esc(t)}</span>`).join("")}${a.mcp.map(t=>`<span class="tag mcp">${esc(t)}</span>`).join("")}`;
  h+=`<div class="hint">MCP: ${a.mcp.length?"위 파란 태그":"붙인 것 없음"} · 권장: ${esc(a.mcp_hint)||"-"}</div>`;
  if(a.cannot) h+=`<h4>못 하는 것</h4><p>${esc(a.cannot)}</p>`;
  if(a.gives) h+=`<h4>넘겨주는 것</h4><p>${esc(a.gives)}</p>`;
  h+=`<h4>이 에이전트를 위한 설정</h4><table><tr><th>상태</th><th>무엇</th><th>현재 값 / 비면</th></tr>`;
  for(const q of a.questions) h+=`<tr><td class="${q.filled?"st-ok":"st-no"}">${q.filled?"채움":"비어 있음"}</td><td>${esc(q.q)}<br><code>${esc(q.where)}</code></td><td>${q.filled?`<code>${esc(q.value)}</code>`:esc(q.ifempty)}</td></tr>`;
  h+=`</table>`;
  h+=`<h4>보충 칸 <code>.claude/project/agents/${esc(name)}.md</code></h4>${a.supplement?`<pre>${esc(a.supplement)}</pre>`:`<div class="hint">없음. /setup 에서 이 에이전트에게 따로 당부할 것을 적을 수 있다.</div>`}`;
  document.getElementById("panel").innerHTML=h;
}
function renderDomains(){
  let h="";
  if(!D.domain_map) h=`<div class="hint">docs.domain_map 이 비어 있다. 도메인 지식을 적을 곳이 없어 에이전트가 코드만 보고 판단한다.</div>`;
  else if(!D.domains.length) h=`<div class="hint"><code>${esc(D.domain_map)}</code> 아래에 DOMAIN.md 가 아직 없다.</div>`;
  else{h=`<table><tr><th>도메인</th><th>절 (채움 / 빈칸)</th><th>시나리오</th></tr>`;
    for(const d of D.domains) h+=`<tr><td><b>${esc(d.name)}</b></td><td>${d.sections.map(s=>`<span class="sec"><span class="dot d-${s.filled?"ok":"none"}"></span>${esc(s.name)}</span>`).join("")}</td><td>${D.coverage.includes(d.name)?"<span class='st-ok'>있음</span>":"<span class='st-no'>없음</span>"}</td></tr>`;
    h+=`</table>`;}
  const missing=D.known_domains.filter(k=>!D.domains.some(d=>d.name===k));
  if(D.domain_map&&missing.length) h+=`<div class="hint">문서가 없는 도메인: ${esc(missing.join(", "))}</div>`;
  document.getElementById("domains").innerHTML=h;
}
function renderEmpties(){
  const seen=new Map();
  for(const [n,a] of Object.entries(D.agents)) for(const q of a.questions) if(!q.filled){
    const k=q.where; if(!seen.has(k)) seen.set(k,{where:k,ifempty:q.ifempty,agents:[]}); if(!seen.get(k).agents.includes(n)) seen.get(k).agents.push(n);}
  if(!seen.size){document.getElementById("empties").innerHTML=`<div class="hint">비어 있는 설정이 없다.</div>`;return;}
  let h=`<table><tr><th>설정</th><th>쓰는 에이전트</th><th>안 채우면</th></tr>`;
  for(const e of seen.values()) h+=`<tr><td><code>${esc(e.where)}</code></td><td>${esc(e.agents.join(", "))}</td><td>${esc(e.ifempty)}</td></tr>`;
  h+=`</table><div class="hint">채우려면 /setup 을 부르고 "비운 것만 채우기" 를 고른다.</div>`;
  document.getElementById("empties").innerHTML=h;
}
renderTop();renderPipes();renderDomains();renderEmpties();
const first=document.querySelector(".node[data-a]"); if(first) show(first.dataset.a);
</script></body></html>
"""


def main():
    args = [a for a in sys.argv[1:] if a != "--open"]
    root = os.path.abspath(args[0] if args else os.getcwd())
    data = collect(root)
    out_dir = os.path.join(root, ".claude", "state")
    os.makedirs(out_dir, exist_ok=True)
    out = os.path.join(out_dir, "harness-view.html")
    page = PAGE.replace("__PROJECT__", html.escape(data["project"])).replace(
        "__DATA__", json.dumps(data, ensure_ascii=False).replace("</", "<\\/"))
    with open(out, "w", encoding="utf-8") as f:
        f.write(page)
    empty = sum(1 for a in data["agents"].values() for q in a["questions"] if not q["filled"])
    total = sum(len(a["questions"]) for a in data["agents"].values())
    print(out)
    print("에이전트 %d개, 설정 %d칸 중 %d칸 채움, 도메인 문서 %d개%s" % (
        len(data["agents"]), total, total - empty, len(data["domains"]),
        (". " + data["update"]) if data["update"] else ""))
    if "--open" in sys.argv:
        webbrowser.open("file://" + out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
