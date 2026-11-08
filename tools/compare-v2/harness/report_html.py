"""Self-contained HTML report (no JS, no external assets): per-step strip plots of every round, medians, CIs, verdicts,
detail tables and the final screens of both apps side by side."""
from html import escape as e

from .stats import METRICS, PRIMARY
from .report_term import NOTES, num

HEX = {"cyan": "#0e8fa8", "magenta": "#b620c9", "blue": "#3b6fe0", "green": "#1f9d55", "yellow": "#b8860b", "red": "#d03a3a", "white": "#667"}

CSS = """
:root{--bg:#fafaf9;--fg:#1c1b1a;--mute:#6b6a67;--line:#e4e2de;--card:#fff;--good:#14803f;--warn:#a15c00;--bad:#c0292b}
@media (prefers-color-scheme:dark){:root:not([data-theme=light]){--bg:#14130f;--fg:#ecebe6;--mute:#9a988f;--line:#2c2a25;--card:#1c1b17;--good:#4ec07a;--warn:#e0a53c;--bad:#f07a7a;color-scheme:dark}}
:root[data-theme=dark]{--bg:#14130f;--fg:#ecebe6;--mute:#9a988f;--line:#2c2a25;--card:#1c1b17;--good:#4ec07a;--warn:#e0a53c;--bad:#f07a7a;color-scheme:dark}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--fg);font:14px/1.45 system-ui,sans-serif;padding-inline:max(16px,4vw)}
main{max-width:1200px;margin:auto;padding-block:24px 64px}
h1{font-size:22px;margin:0 0 4px}h2{font-size:15px;margin:32px 0 10px;text-transform:uppercase;letter-spacing:.06em;color:var(--mute)}
.sub{color:var(--mute)}.chips{display:flex;gap:8px;flex-wrap:wrap;margin:12px 0}
.chip{border:1px solid var(--line);background:var(--card);border-radius:999px;padding:3px 12px;font-size:13px}.dot{display:inline-block;width:9px;height:9px;border-radius:50%;margin-right:6px}
.cards{display:grid;grid-template-columns:repeat(auto-fit,minmax(260px,1fr));gap:12px}
.card{background:var(--card);border:1px solid var(--line);border-radius:10px;padding:14px 16px}.card b.big{font-size:26px;display:block;font-variant-numeric:tabular-nums}
.warn{background:var(--card);border-left:3px solid var(--warn);padding:8px 12px;margin:8px 0;border-radius:4px}
.grid{display:grid;grid-template-columns:minmax(120px,170px) minmax(200px,1fr) minmax(150px,230px);gap:2px 16px;align-items:center;background:var(--card);border:1px solid var(--line);border-radius:10px;padding:8px 16px}
.step{font-weight:600;padding-top:10px}.rowsep{grid-column:1/-1;border-top:1px solid var(--line);margin-top:6px}
.lane{position:relative;height:18px}.lane .rail{position:absolute;inset:8px 0 8px 0;border-radius:2px;background:var(--line);opacity:.5}
.lane .ci{position:absolute;top:7px;height:4px;border-radius:2px;opacity:.35}.lane .med{position:absolute;top:2px;width:3px;height:14px;border-radius:1px;margin-left:-1px}
.lane .pt{position:absolute;top:6px;width:6px;height:6px;border-radius:50%;margin-left:-3px;opacity:.75}
.val{font-variant-numeric:tabular-nums;font-size:13px}.val small{color:var(--mute)}.v{font-size:13px}.good{color:var(--good);font-weight:600}.mute{color:var(--mute)}.unclear{color:var(--warn)}.bad{color:var(--bad);font-weight:600}
table{border-collapse:collapse;width:100%;font-variant-numeric:tabular-nums;font-size:13px}th,td{text-align:right;padding:4px 10px;border-bottom:1px solid var(--line);white-space:nowrap}th:first-child,td:first-child,th:nth-child(2),td:nth-child(2){text-align:left}
.scroll{overflow-x:auto;background:var(--card);border:1px solid var(--line);border-radius:10px}
details{margin:10px 0}summary{cursor:pointer;color:var(--mute)}pre{background:var(--card);border:1px solid var(--line);border-radius:8px;padding:8px;overflow-x:auto;font-size:11px;line-height:1.2;margin:4px 0}
.cols{display:grid;grid-template-columns:repeat(auto-fit,minmax(380px,1fr));gap:12px}.notes{white-space:pre-wrap;font:12px/1.5 ui-monospace,monospace;color:var(--mute)}
.skew{background:var(--card);border:2px solid var(--bad);border-radius:8px;padding:12px 16px;margin:16px 0}.skew b{color:var(--bad);display:block;margin-bottom:4px}.skew ul{margin:0;padding-left:20px}
@media (max-width:640px){.grid{grid-template-columns:1fr}}
"""


def color(app):
    return HEX.get(app["color"], app["color"])


def verdict(c, base, other, key="settled_ms"):
    if not c:
        return '<span class="mute">–</span>'
    if c["verdict"] == "tie":
        return '<span class="mute">≈ same</span>'
    if c["verdict"] == "unclear":
        return f'<span class="unclear">unclear ({c["ratio"]:.2f}×, CI spans 1)</span>' if c["ratio"] else '<span class="unclear">unclear</span>'
    w = base if c["verdict"] == "a" else other
    f = c["ratio"] if c["verdict"] == "a" else 1 / c["ratio"]
    lo, hi = c["ci"] if c["verdict"] == "a" else (1 / c["ci"][1], 1 / c["ci"][0])
    return f'<span style="color:{color(w)};font-weight:700">{e(w["label"])} {f:.2f}× {'faster' if METRICS[key][1] == 'ms' else 'lower'}</span> <span class="mute">[{lo:.2f}–{hi:.2f}]</span>'


def lanes(an, apps, steps, key):
    out = ['<div class="grid">']
    for st in steps:
        sums = [st["apps"][n]["metrics"][key] for n in an["apps"]]
        vmax = max([v for s in sums for v in s["vals"]] + [x["sum"]["ci"][1] for x in sums if x["sum"]] + [1e-9]) * 1.05
        out.append(f'<div class="rowsep"></div><div class="step">{e(st["name"])}</div><div></div><div></div>')
        for i, n in enumerate(an["apps"]):
            m, app = st["apps"][n]["metrics"][key], apps[n]
            s, c = m["sum"], color(apps[n])
            pos = lambda v: f"{max(0, min(100, v / vmax * 100)):.2f}%"
            lane = '<div class="lane"><div class="rail"></div>'
            if s:
                lane += f'<div class="ci" style="background:{c};left:{pos(s["ci"][0])};width:calc({pos(s["ci"][1])} - {pos(s["ci"][0])})"></div>'
                lane += "".join(f'<div class="pt" style="background:{c};left:{pos(v)}"></div>' for v in m["vals"])
                lane += f'<div class="med" style="background:{c};left:{pos(s["median"])}"></div>'
            lane += "</div>"
            ok = st["apps"][n]["ok"]
            bad = f' <span class="bad">{ok[0]}/{ok[1]} ok</span>' if ok[1] and ok[0] < ok[1] else ""
            val = f'<span style="color:{c}">●</span> {e(app["label"])} <b>{num(s["median"], key) if s else "-"}</b>' + (f' <small>±{num((s["ci"][1] - s["ci"][0]) / 2, key)}</small>' if s and s["n"] > 2 else "") + bad
            out.append(f'<div class="val">{val}</div>{lane}<div class="v">{verdict(st["cmp"].get(n, {}).get(key), apps[an["base"]], app, key) if i else "<span class=mute>baseline</span>"}</div>')
    out.append("</div>")
    return "".join(out)


def detail_table(an, apps, steps, keys):
    h = "".join(f"<th>{METRICS[k][0]}</th>" for k in keys)
    rows = []
    for st in steps:
        for n in an["apps"]:
            tds = "".join(f'<td>{num((st["apps"][n]["metrics"][k]["sum"] or {}).get("median"), k)}</td>' for k in keys)
            rows.append(f'<tr><td>{e(st["name"]) if n == an["apps"][0] else ""}</td><td style="color:{color(apps[n])}">{e(apps[n]["label"])}</td>{tds}</tr>')
    return f'<div class="scroll"><table><tr><th>step</th><th>app</th>{h}</tr>{"".join(rows)}</table></div>'


def render(res, an):
    meta, env = res["meta"], res["meta"]["env"]
    apps = {a["name"]: a for a in meta["apps"]}
    base = apps[an["base"]]
    steps = an["steps"]
    lat = [s for s in steps if s["kind"] == "latency"]
    startup, inter = [s for s in lat if s["name"].startswith("startup")], [s for s in lat if not s["name"].startswith("startup")]
    cards = []
    for n, s in an["score"].items():
        o = apps[n]
        if s["geomean"]:
            g = s["geomean"]
            fast, f = (base, g) if g > 1 else (o, 1 / g)
            cards.append(f'<div class="card"><b class="big" style="color:{color(fast)}">{f:.2f}× faster</b>{e(fast["label"])} vs {e((o if fast is base else base)["label"])}<br><span class="sub">geometric mean over {s["n"]} interaction steps · {e(base["label"])} better in {s["base_better"]}, {e(o["label"])} in {s["other_better"]}, no clear gap in {s["tie"]}</span></div>')
        w = next((r for r in steps if r["name"] == "startup.warm"), None)
        if w:
            cards.append(f'<div class="card"><b class="big" style="font-size:18px">warm startup</b>{verdict(w["cmp"].get(n, {}).get("settled_ms"), base, o)}</div>')
    chips = "".join(f'<span class="chip"><span class="dot" style="background:{color(a)}"></span>{e(a["label"])} <span class="sub">{e(a["version"])}{" · keys: " + e(a["keyboard"]) if a.get("keyboard") else ""}</span></span>' for a in meta["apps"])
    warns = "".join(f'<div class="warn">⚠ {e(w)}</div>' for w in meta.get("warnings", []))
    errs = "".join(f'<div class="warn" style="border-color:var(--bad)">✗ {e(x["app"])} round {x["round"]}: {e(x["error"].strip().splitlines()[-1])}</div>' for x in meta.get("errors", []))
    snaps = ""
    labels = [l for a in an["apps"] for l in res["snapshots"].get(a, {})]
    for label in dict.fromkeys(labels):
        cols = "".join(f'<div><span style="color:{color(apps[a])}">●</span> {e(apps[a]["label"])}<pre>{e(res["snapshots"].get(a, {}).get(label, ""))}</pre></div>' for a in an["apps"])
        snaps += f"<details><summary>{e(label)}</summary><div class='cols'>{cols}</div></details>"
    idle = [s for s in steps if s["kind"] == "idle"]
    mem = [s for s in steps if s["kind"] == "memory"]
    sk = ("<div class=\"skew\" role=\"alert\"><b>SKEWED RUN: do not quote these timings as real.</b><ul>" + "".join(f"<li>{e(r)}</li>" for r in meta.get("skew", [])) + "</ul></div>") if meta.get("skew") else ""
    body = f"""{sk}<h1>{e(meta['scenario'])}</h1><div class="sub">{e(meta['title'])}</div><div class="chips">{chips}</div>
<div class="sub">{meta['rounds']} rounds (+{meta['warmup']} warm-up) · {meta['cols']}×{meta['rows']} · {meta['duration_s']} s · {e(meta['started'])} · {e(env['cpu'])} · kernel {e(env['kernel'])} · governor {e(str(env['governor']))} · app CPUs {env['pinned_app'] or 'any'} · harness CPUs {env['pinned_harness'] or 'any'} · repo {e(env['git'])}</div>
{warns}{errs}<h2>Summary</h2><div class="cards">{''.join(cards)}</div>
<h2>Startup · spawn → last visible change (ms)</h2>{lanes(an, apps, startup, 'settled_ms')}
<h2>Interaction · input → last visible change (ms)</h2><p class="sub">Each dot is one round (median of that round's samples), the thick tick the median, the faint band its 95% bootstrap CI. Shorter is better.</p>{lanes(an, apps, inter, 'settled_ms')}
<h2>Latency detail</h2>{detail_table(an, apps, lat, ['settled_ms', 'ready_ms', 'first_paint_ms', 'cpu_ms', 'bytes', 'paints'])}
{'<h2>Idle</h2>' + detail_table(an, apps, idle, ['cpu_pct', 'wakeups_s', 'bytes_s']) if idle else ''}
{'<h2>Memory</h2>' + detail_table(an, apps, mem, ['pss_kb', 'rss_kb', 'procs', 'threads']) if mem else ''}
{'<h2>Screens (did both do the same work?)</h2>' + snaps if snaps else ''}
<h2>Method</h2><div class="notes">{e(NOTES)}</div>{sk}"""
    return f'<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>compare-v2 · {e(meta["scenario"])}</title><style>{CSS}</style></head><body><main>{body}</main></body></html>'
