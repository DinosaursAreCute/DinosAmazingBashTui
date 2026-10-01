"""Self-contained HTML report: same story as the terminal one, plus an interactive flame graph."""
import json

from .analyze import LAYERS, layer_of

LAYER_HEX = {
    "input": "#61afef", "loop": "#7d869c", "focus": "#f082b4", "scroll": "#50c8aa", "markup": "#c678dd",
    "cache": "#e89658", "style": "#ebc86e", "layout": "#56d6dc", "render": "#7ed382", "flush": "#3fb5a0",
    "widgets": "#e06fa8", "chrome": "#5b8def", "term": "#d98a4a", "plugin": "#a985e0", "config": "#c9b458",
    "core": "#6a7288", "app": "#e6ebf5", "diag": "#56607a", "process": "#f05f6e",
}


def _annotate(node, files):
    n = node["n"]
    node["l"] = "process" if n.startswith("⟨") else "loop" if n == "…small" or n == "all" else layer_of(n, files.get(n, ""))
    for c in node["c"]:
        _annotate(c, files)


def render(rep):
    files = rep["attr"]["files"]
    for t in rep["trees"].values():
        _annotate(t, files)
    data = dict(rep)
    data["attr"] = dict(rep["attr"])
    data["attr"].pop("files", None)
    data["layers"] = {k: {"title": v[0], "desc": v[1], "color": LAYER_HEX.get(k, "#888")} for k, v in LAYERS.items()}
    blob = json.dumps(data, default=str).replace("</", "<\\/")
    return TEMPLATE.replace("__DATA__", blob)


TEMPLATE = r"""<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>DABT Profile</title>
<style>
:root{--bg:#0f1219;--panel:#171b25;--panel2:#1d2230;--line:#2a3142;--text:#d5dbe8;--dim:#8892a8;--faint:#586178;
--good:#7ed382;--ok:#ebc86e;--slow:#f05f6e;--accent:#56d6dc;--purple:#c678dd;--blue:#61afef;--orange:#e89658;--shadow:0 1px 0 #0006,0 8px 24px #0004}
@media (prefers-color-scheme:light){:root{--bg:#f4f6fa;--panel:#fff;--panel2:#eef1f6;--line:#d8deea;--text:#1c2333;--dim:#5a647c;--faint:#8a93a8;
--good:#1f9d57;--ok:#b7791f;--slow:#d43d51;--accent:#0a8fa0;--purple:#8e44ad;--blue:#2b6cd4;--orange:#c4661f;--shadow:0 1px 2px #0001,0 8px 24px #0001}}
*{box-sizing:border-box}html{background:var(--bg)}
body{margin:0;background:var(--bg);color:var(--text);font:14px/1.5 ui-sans-serif,system-ui,-apple-system,"Segoe UI",Roboto,sans-serif}
.wrap{max-width:1240px;margin:0 auto;padding:0 16px 64px}
header{display:flex;flex-wrap:wrap;gap:8px 20px;align-items:baseline;padding:28px 0 16px;border-bottom:1px solid var(--line)}
h1{margin:0;font-size:22px;letter-spacing:.04em}h1 b{color:var(--accent)}
.meta{color:var(--dim);font-size:13px;display:flex;gap:14px;flex-wrap:wrap}.meta .c{color:var(--purple);font-family:ui-monospace,monospace}
h2{font-size:12px;letter-spacing:.14em;text-transform:uppercase;color:var(--dim);margin:0 0 12px;font-weight:600}
section{background:var(--panel);border:1px solid var(--line);border-radius:12px;padding:18px 20px;margin-top:18px;box-shadow:var(--shadow)}
.tiles{display:grid;grid-template-columns:repeat(auto-fit,minmax(200px,1fr));gap:14px;margin-top:20px}
.tile{background:var(--panel);border:1px solid var(--line);border-radius:12px;padding:14px 16px;box-shadow:var(--shadow)}
.tile .t{font-size:11px;letter-spacing:.12em;color:var(--dim)}.tile .v{font-size:30px;font-weight:700;margin:2px 0 6px;font-variant-numeric:tabular-nums}
.tile .s{font-size:12px;color:var(--faint)}.meter{height:6px;border-radius:3px;background:var(--panel2);overflow:hidden;position:relative}
.meter i{display:block;height:100%;border-radius:3px}.meter u{position:absolute;left:50%;top:-2px;bottom:-2px;width:1px;background:var(--faint)}
.good{color:var(--good)}.ok{color:var(--ok)}.slow{color:var(--slow)}.na{color:var(--dim)}
.bg-good{background:var(--good)}.bg-ok{background:var(--ok)}.bg-slow{background:var(--slow)}.bg-na{background:var(--faint)}
table{width:100%;border-collapse:collapse;font-variant-numeric:tabular-nums}
th{font-size:11px;letter-spacing:.08em;text-transform:uppercase;color:var(--dim);font-weight:600;text-align:right;padding:6px 8px;border-bottom:1px solid var(--line);white-space:nowrap}
td{padding:6px 8px;border-bottom:1px solid color-mix(in srgb,var(--line) 55%,transparent);text-align:right;white-space:nowrap}
th:first-child,td:first-child{text-align:left}td.l,th.l{text-align:left}
tr:hover td{background:var(--panel2)}.mono{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:12.5px}
.scroll{overflow-x:auto}
.dot{display:inline-block;width:9px;height:9px;border-radius:50%;margin-right:8px}
.bar{display:inline-block;height:8px;border-radius:2px;vertical-align:middle}
.stack{display:flex;height:22px;border-radius:6px;overflow:hidden;margin:4px 0 10px}.stack i{display:block;height:100%}
.legend{display:flex;flex-wrap:wrap;gap:6px 16px;font-size:12px;color:var(--dim);margin-bottom:14px}.legend b{color:var(--text);font-weight:600}
.legend i{display:inline-block;width:10px;height:10px;border-radius:2px;margin-right:6px;vertical-align:-1px}
.heat td{padding:5px 8px}.heat td.h{border-radius:4px;border:2px solid var(--panel);color:#10131a;font-weight:600}
.flow{display:grid;grid-template-columns:150px 28px 150px 1fr 80px;gap:4px 10px;align-items:center;font-size:13px}
.flow .a{text-align:right;font-weight:600}.flow .ar{color:var(--faint);text-align:center}
.find{display:grid;grid-template-columns:62px 1fr;gap:4px 14px;padding:12px 0;border-bottom:1px solid var(--line)}.find:last-child{border:0}
.chip{font-size:10.5px;font-weight:700;letter-spacing:.08em;padding:2px 8px;border-radius:5px;height:20px;text-align:center;color:#10131a}
.chip.crit{background:var(--slow)}.chip.warn{background:var(--ok)}.chip.info{background:var(--blue)}.chip.good{background:var(--good)}
.find .ti{font-weight:600}.find .de{color:var(--dim);margin-top:2px}.find .wh{font-family:ui-monospace,monospace;font-size:12px;color:var(--accent);margin-top:4px;opacity:.85}
.deep{margin-top:40px;color:var(--faint);letter-spacing:.14em;text-transform:uppercase;font-size:12px;display:flex;gap:14px;align-items:center}.deep:after{content:"";flex:1;height:1px;background:var(--line)}
.deepsec{background:var(--panel);opacity:.98}
select,input[type=search],button{background:var(--panel2);color:var(--text);border:1px solid var(--line);border-radius:8px;padding:6px 10px;font:inherit}
button{cursor:pointer}button:hover{border-color:var(--accent)}
.tools{display:flex;gap:10px;flex-wrap:wrap;align-items:center;margin-bottom:10px}.crumb{color:var(--dim);font-size:12px}
svg text{font:11px ui-monospace,monospace;pointer-events:none}svg rect{cursor:pointer}svg rect:hover{stroke:var(--text);stroke-width:1}
.gantt{display:grid;grid-template-columns:190px 80px 1fr;gap:4px 12px;align-items:center;font-size:13px;margin-bottom:6px}
.gantt .tr{position:relative;height:14px;background:var(--panel2);border-radius:3px}.gantt .tr i{position:absolute;top:0;bottom:0;border-radius:3px}
.note{color:var(--faint);font-size:12px;margin-top:10px}
th.sort{cursor:pointer}th.sort:hover{color:var(--text)}
.two{display:grid;grid-template-columns:1fr 1fr;gap:18px}@media(max-width:900px){.two{grid-template-columns:1fr}.flow{grid-template-columns:110px 20px 110px 1fr 70px}}
</style></head><body><div class="wrap" id="app"></div>
<script id="data" type="application/json">__DATA__</script>
<script>
const R=JSON.parse(document.getElementById('data').textContent);
const $=(s,r=document)=>r.querySelector(s);
const esc=s=>String(s).replace(/[&<>"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]));
const ms=v=>v==null?'–':v>=10000?(v/1000).toFixed(1)+' s':v>=1000?(v/1000).toFixed(2)+' s':v>=100?v.toFixed(0)+' ms':v>=10?v.toFixed(1)+' ms':v>=0.1?v.toFixed(2)+' ms':(v*1000).toFixed(0)+' µs';
const num=v=>v==null?'–':v>=1e6?(v/1e6).toFixed(1)+'M':v>=1e4?(v/1e3).toFixed(0)+'k':v>=100?v.toFixed(0):v>=10?v.toFixed(1):(+v.toFixed(2))+'';
const kb=v=>v==null?'–':v>=1048576?(v/1048576).toFixed(1)+' MB':v>=1024?(v/1024).toFixed(1)+' KB':Math.round(v)+' B';
const L=R.layers, col=l=>(L[l]||{color:'#888'}).color, lt=l=>(L[l]||{title:l}).title;
const heat=f=>{f=Math.max(0,Math.min(1,f));const s=[[0,[58,70,96]],[.25,[90,140,190]],[.5,[230,200,110]],[.75,[238,150,90]],[1,[240,95,110]]];
 for(let i=0;i<4;i++){const[a,ca]=s[i],[b,cb]=s[i+1];if(f<=b){const t=(f-a)/(b-a);return`rgb(${ca.map((x,k)=>Math.round(x+(cb[k]-x)*t)).join(',')})`}}return'rgb(240,95,110)'};
const lat={};R.latency.forEach(g=>lat[g.id]=g);
const meter=(v,b)=>{if(v==null||!b)return'';const r=v<=b?'good':v<=2*b?'ok':'slow';return`<div class="meter" style="width:140px"><i class="bg-${r}" style="width:${Math.min(100,v/(2*b)*100)}%"></i><u></u></div>`};
const M=R.meta;let h='';
h+=`<header><h1><b>◆</b> DABT PROFILE</h1><div class="meta"><span class="c">${esc(M.commit||'')}</span><span>${esc(M.branch||'')}${M.dirty?' · local changes':''}</span>${M.scenario&&M.scenario!=='full'?`<span class="c">scenario ${esc(M.scenario)}</span>`:''}<span>${M.cols}×${M.rows} terminal</span><span>${M.rounds} round${M.rounds==1?'':'s'}</span><span>${Math.round(M.duration_s)} s</span><span>${esc(M.when)}</span></div></header>`;
// tiles
const tile=(t,g)=>{if(!g)return'';const r=g.rating;return`<div class="tile"><div class="t">${t}</div><div class="v ${r}">${ms(g.value)}</div>${meter(g.value,g.budget_ms).replace('width:140px','width:100%')}<div class="s" style="margin-top:6px">budget ${ms(g.budget_ms)}</div></div>`};
h+='<div class="tiles">'+tile('WARM START',lat['startup.warm'])+tile('PAGE SWITCH',lat['nav.revisit'])+tile('HOVER FEEDBACK',lat['hover.move'])+tile('FOCUS FEEDBACK',lat['focus.next']);
const idle=(lat.idle||{}).idle;if(idle){const c=idle.frames_per_s<2?'good':idle.frames_per_s<10?'ok':'slow';h+=`<div class="tile"><div class="t">IDLE REPAINTS</div><div class="v ${c}">${idle.frames_per_s.toFixed(0)} fr/s</div><div class="meter"><i class="bg-${c}" style="width:${Math.min(100,idle.frames_per_s/20*100)}%"></i></div><div class="s" style="margin-top:6px">${(idle.bytes_per_s/1024).toFixed(1)} KB/s · ${idle.cpu_pct.toFixed(1)}% cpu</div></div>`}
h+='</div>';
// scorecard
h+=`<section><h2>How it feels</h2><div class="scroll"><table><tr><th>Interaction</th><th>n</th><th>Typical</th><th>Worst</th><th class="l">vs budget</th><th>Budget</th><th>Frames</th><th>Bytes</th></tr>`;
R.latency.filter(g=>g.id!=='idle').forEach(g=>{const m=g[g.metric]||g.settle;h+=`<tr><td><span class="dot bg-${g.rating}"></span>${esc(g.title)}</td><td>${g.n}</td><td class="${g.rating}"><b>${ms(g.value)}</b></td><td>${ms(m&&m.max)}</td><td class="l">${meter(g.value,g.budget_ms)}</td><td>${ms(g.budget_ms)}</td><td>${g.frames?num(g.frames.med):''}</td><td>${g.bytes?kb(g.bytes.med):''}</td></tr>`});
h+=`</table></div><div class="note">Typical = median. "Page switch" and start/resize are measured to the last frame; input interactions to the first painted feedback. Budgets are perceived-instant thresholds.</div></section>`;
// where time goes
const A=R.attr,groups=Object.entries(A.groups).map(([id,v])=>[id,id==='idle'?v.a:v.w]).filter(([id,v])=>v&&v.total_ms>0);
if(groups.length){const order=R.latency.map(g=>g.id);groups.sort((a,b)=>order.indexOf(a[0])-order.indexOf(b[0]));
 const tot={};groups.forEach(([id,v])=>{if(id.startsWith('startup')||id==='idle')return;for(const[l,m]of Object.entries(v.layers))tot[l]=(tot[l]||0)+m});
 const sum=Object.values(tot).reduce((a,b)=>a+b,0)||1,ls=Object.keys(tot).sort((a,b)=>tot[b]-tot[a]),cols=ls.slice(0,10);
 h+=`<section><h2>Where the time goes</h2><div class="stack">${ls.map(l=>`<i title="${lt(l)} ${(tot[l]/sum*100).toFixed(1)}%" style="width:${tot[l]/sum*100}%;background:${col(l)}"></i>`).join('')}</div><div class="legend">${ls.map(l=>`<span><i style="background:${col(l)}"></i><b>${lt(l)}</b> ${(tot[l]/sum*100).toFixed(0)}%</span>`).join('')}</div>`;
 h+=`<div class="scroll"><table class="heat"><tr><th>ms per action</th>${cols.map(l=>`<th style="color:${col(l)}">${lt(l)}</th>`).join('')}<th>Total</th></tr>`;
 groups.forEach(([id,v])=>{const t=v.total_ms,name=id==='idle'?'Idle tick work (per 3 s)':(lat[id]||{title:id}).title;h+=`<tr><td>${esc(name)}</td>${cols.map(l=>{const m=v.layers[l]||0;return m>=0.05?`<td class="h" style="background:${heat(m/t)}">${m.toFixed(1)}</td>`:'<td style="color:var(--faint)">·</td>'}).join('')}<td><b>${ms(t)}</b></td></tr>`});
 h+=`</table></div><div class="note">Cell colour = that layer's share of the row. Times are calibrated to untraced speed (in-shell time ×${A.global_k.toFixed(2)}; forks and external programs are real time).</div></section>`;
 // flows
 const fl=A.flow.slice(0,10);if(fl.length){h+=`<section><h2>How work flows</h2><div class="flow">${fl.map(f=>`<div class="a" style="color:${col(f.from)}">${lt(f.from)}</div><div class="ar">▶</div><div style="color:${col(f.to)};font-weight:600">${lt(f.to)}</div><div><span class="bar" style="width:${f.ms/fl[0].ms*100}%;background:${col(f.to)}"></span></div><div class="mono">${ms(f.ms)}</div>`).join('')}</div><div class="note">Time handed from one layer into the next down the call stack (one pass of all interactions). Heaviest call chain per scenario:</div>`;
  h+='<div style="margin-top:10px">'+['nav.revisit','nav.first','hover.move','focus.next','click','palette.open','resize','scroll.burst'].filter(g=>R.paths[g]).map(g=>{const p=R.paths[g].filter(x=>!['main','source','⟨main⟩','tui.start_cached','tui.run'].includes(x[0]));return`<div style="margin:4px 0"><span style="display:inline-block;width:210px;color:var(--dim)">${esc((lat[g]||{title:g}).title)}</span><span class="mono">${p.slice(0,6).map(x=>esc(x[0])).join(' <span style="color:var(--faint)">›</span> ')}</span> <span style="color:var(--faint)">${p[0]?ms(p[0][1]):''}</span></div>`}).join('')+'</div></section>'}
}
// findings
h+=`<section><h2>Findings <span style="color:var(--faint)">· ${R.insights.length}</span></h2>${R.insights.map(i=>`<div class="find"><div class="chip ${i.sev}">${i.sev.toUpperCase()}</div><div><div class="ti">${esc(i.title)}</div>${i.detail?`<div class="de">${esc(i.detail)}</div>`:''}${i.where?`<div class="wh">↳ ${esc(i.where)}</div>`:''}</div></div>`).join('')}</section>`;
if(R.compare&&R.compare.rows.length)h+=`<section><h2>Against previous run ${esc(R.compare.commit||'')}</h2><table><tr><th>Interaction</th><th>Before</th><th>Now</th><th>Change</th></tr>${R.compare.rows.map(r=>`<tr><td>${esc(r.title)}</td><td>${ms(r.old)}</td><td>${ms(r.new)}</td><td class="${Math.abs(r.new-r.old)<2?'na':r.delta_pct<=-5?'good':r.delta_pct>=15?'slow':'na'}"><b>${r.delta_pct>0?'+':''}${r.delta_pct.toFixed(0)}%</b></td></tr>`).join('')}</table></section>`;
h+='<div class="deep">Deep dive</div>';
// startup
const su=R.startup;let g='';for(const w of['warm','cold']){const s=su[w];if(!s)continue;g+=`<div style="margin:6px 0 8px"><b>${w.toUpperCase()} START</b> <span style="color:var(--dim)">ready in</span> <b style="color:var(--accent)">${ms(s.ready_ms)}</b>${s.first_output_ms?` <span style="color:var(--faint)">· first output ${ms(s.first_output_ms)}</span>`:''}</div>`+s.spans.map(sp=>`<div class="gantt"><div>${esc(sp.label)}</div><div class="mono" style="text-align:right">${ms(sp.end-sp.start)}</div><div class="tr"><i style="left:${sp.start/s.ready_ms*100}%;width:${Math.max(.4,(sp.end-sp.start)/s.ready_ms*100)}%;background:${(sp.end-sp.start)>s.ready_ms*.4?'var(--orange)':'var(--accent)'}"></i></div></div>`).join('')+'<div style="height:12px"></div>'}
if(g)h+=`<section class="deepsec"><h2>Startup timeline</h2>${g}</section>`;
// flame
const tk=Object.keys(R.trees);if(tk.length){h+=`<section class="deepsec"><h2>Flame graph</h2><div class="tools"><select id="fsel">${tk.map(k=>`<option value="${esc(k)}">${esc((lat[k]||{title:k}).title)}</option>`).join('')}</select><input id="fsearch" type="search" placeholder="highlight function…"><button id="freset">reset zoom</button><span class="crumb" id="fcrumb"></span></div><div id="flame"></div><div class="note">Width = time (ms per action). Click a frame to zoom. ⟨cmd⟩ frames are external programs, ⟨fork⟩ is subshell creation. Colour = layer.</div></section>`}
// tables
const fn=A.functions.slice(0,30),fmax=fn[0]?fn[0].self_ms:1;
h+=`<section class="deepsec"><h2>Hot functions</h2><div class="scroll"><table id="tfn"><tr><th class="l">Function</th><th class="sort" data-k="self_ms">Self</th><th class="sort" data-k="incl_ms">Total</th><th class="sort" data-k="calls">Calls</th><th class="sort" data-k="per_call_us">Per call</th><th class="l">Layer</th><th class="l">File</th><th class="l">Self share</th></tr></table></div></section>`;
h+=`<section class="deepsec"><h2>Hot source lines</h2><div class="scroll"><table><tr><th class="l">Line</th><th>Time</th><th>Hits</th><th class="l">Code</th></tr>${A.hot_lines.slice(0,20).map(r=>`<tr><td class="l mono" style="color:var(--accent)">${esc(r.src)}</td><td><b>${ms(r.ms)}</b></td><td>×${num(r.hits)}</td><td class="l mono" style="color:var(--dim);white-space:pre;max-width:640px;overflow:hidden;text-overflow:ellipsis">${esc(r.code)}${r.ex_ms>r.ms*.5?' <span class="slow">⟨program⟩</span>':r.fk_ms>r.ms*.5?' <span class="slow">⟨fork⟩</span>':''}</td></tr>`).join('')}</table></div></section>`;
h+=`<div class="two"><section class="deepsec"><h2>Call graph · heaviest edges</h2><div class="scroll"><table><tr><th class="l">Caller</th><th class="l">Callee</th><th>Time</th></tr>${A.edges.slice(0,18).map(e=>`<tr><td class="l mono">${esc(e.from)}</td><td class="l mono">${esc(e.to)}</td><td>${ms(e.ms)}</td></tr>`).join('')}</table></div></section>`;
h+=`<section class="deepsec"><h2>Subprocesses</h2><div class="scroll"><table><tr><th class="l">Program</th><th>Runs</th><th>Time</th><th class="l">Spawned by</th></tr>${A.execs.slice(0,10).map(e=>`<tr><td class="l mono slow">${esc(e.cmd)}</td><td>${num(e.count)}</td><td>${ms(e.ms)}</td><td class="l mono">${esc(e.caller)}</td></tr>`).join('')}</table><table style="margin-top:14px"><tr><th class="l">Fork site</th><th>Forks</th></tr>${A.forks.slice(0,8).map(f=>`<tr><td class="l mono">${esc(f.func)} <span style="color:var(--faint)">${esc(f.src)}</span></td><td>${num(f.count)}</td></tr>`).join('')}</table></div></section></div>`;
const sl=[];R.latency.forEach(g=>(g.details||[]).forEach(d=>{if(d.settle!=null&&g.id!=='idle'&&g.id!=='shutdown')sl.push([d.settle,g,d])}));sl.sort((a,b)=>b[0]-a[0]);
h+=`<section class="deepsec"><h2>Slowest individual actions</h2><table><tr><th class="l">Action</th><th>Done</th><th>Busy</th><th>Frames</th><th>Bytes</th></tr>${sl.slice(0,14).map(([s,g,d])=>`<tr><td class="l">${esc(g.id)} · ${esc(d.detail)}</td><td class="${g.rating}"><b>${ms(s)}</b></td><td>${ms(d.busy)}</td><td>${num(d.frames)}</td><td>${kb(d.bytes)}</td></tr>`).join('')}</table></section>`;
const FO=A.focus||{},fg=['nav.floor','nav.revisit','nav.first','nav.key'].filter(k=>FO[k]);
if(fg.length){let t='';fg.forEach(k=>{t+=`<h3>${esc((lat[k]||{title:k}).title)} · per switch</h3>`;Object.entries(FO[k]).sort((a,b)=>b[1].incl-a[1].incl).forEach(([root,v])=>{t+=`<div style="margin:10px 0 2px"><b class="mono" style="color:var(--accent)">${esc(root)}</b> <b>${ms(v.incl)}</b> <span style="color:var(--dim)">inclusive</span></div><div class="mono" style="color:var(--dim)">into: ${v.children.slice(0,8).map(x=>esc(x.name)+' '+ms(x.ms)).join(' · ')}</div><div class="mono" style="color:var(--dim)">run by: ${v.leaves.slice(0,8).map(x=>esc(x.name)+' '+ms(x.ms)).join(' · ')}</div><table>${v.lines.slice(0,6).map(r=>`<tr><td class="l mono" style="color:var(--accent)">${esc(r.src)}</td><td>${ms(r.ms)}</td><td>${num(r.hits)}</td><td class="l mono">${esc(r.code)}</td></tr>`).join('')}</table>`})});h+=`<section class="deepsec"><h2>Page-switch floor</h2>${t}</section>`}
const cal=R.calibration;if(cal&&cal.rows.length){const ec=e=>e==null?'na':Math.abs(e)<=15?'good':Math.abs(e)<=30?'ok':'slow';h+=`<section class="deepsec"><h2>Calibration check</h2><div style="margin-bottom:8px">Mean error <b class="${ec(cal.mae_pct)}">${cal.mae_pct==null?'–':cal.mae_pct.toFixed(0)+'%'}</b> · bias <b>${cal.bias_pct==null?'–':(cal.bias_pct>0?'+':'')+cal.bias_pct.toFixed(0)+'%'}</b> over ${cal.n} functions ≥ 2 ms</div><div class="scroll"><table><tr><th class="l">Scenario</th><th class="l">Function</th><th>Real (untraced)</th><th>Trace (rescaled)</th><th>Error</th></tr>${cal.rows.slice(0,20).map(x=>`<tr><td class="l">${esc(x.group)}</td><td class="l mono">${esc(x.func)}</td><td>${ms(x.real_ms)}</td><td>${ms(x.est_ms)}</td><td class="${ec(x.err_pct)}"><b>${x.err_pct==null?'–':(x.err_pct>0?'+':'')+x.err_pct.toFixed(0)+'%'}</b></td></tr>`).join('')}</table></div><div class="note">Real = probe-measured wall time of the function in the untraced run. Trace = its inclusive time in the xtrace after rescaling. Large errors mean the shell-time factor does not fit that code.</div></section>`}
h+=`<div class="note">Method: the real app runs in a pty and a scripted user drives it. Latency comes from probes inside the app (untraced). Attribution comes from a bash xtrace of the same session; in-shell time is rescaled to the untraced busy time per scenario, forks and external programs are taken as measured.</div>`;
$('#app').innerHTML=h;
// sortable function table
let fsort='self_ms';const rows=()=>A.functions.slice(0,60).sort((a,b)=>(b[fsort]||0)-(a[fsort]||0)).slice(0,30);
function fdraw(){const t=$('#tfn');if(!t)return;[...t.querySelectorAll('tr.r')].forEach(r=>r.remove());const mx=Math.max(...A.functions.map(f=>f.self_ms),1e-9);
 t.insertAdjacentHTML('beforeend',rows().map(f=>`<tr class="r"><td class="l mono" style="color:${col(f.layer)}">${esc(f.name)}</td><td><b>${ms(f.self_ms)}</b></td><td>${ms(f.incl_ms)}</td><td>${f.calls?num(f.calls):'–'}</td><td>${f.per_call_us?ms(f.per_call_us/1000):'–'}</td><td class="l" style="color:${col(f.layer)}">${lt(f.layer)}</td><td class="l mono" style="color:var(--faint)">${esc(f.file)}</td><td class="l"><span class="bar" style="width:${f.self_ms/mx*120}px;background:${col(f.layer)}"></span></td></tr>`).join(''))}
document.querySelectorAll('#tfn th.sort').forEach(th=>th.onclick=()=>{fsort=th.dataset.k;fdraw()});fdraw();
// flame graph
if(tk.length){let cur,root,q='';const W=()=>Math.max(600,$('#flame').clientWidth),H=19;
 function draw(node){cur=node;const w=W(),rowsL=[];(function walk(n,x0,x1,d){if(x1-x0<0.8)return;(rowsL[d]=rowsL[d]||[]).push([n,x0,x1]);let x=x0;for(const c of n.c){const cw=(x1-x0)*c.v/n.v;walk(c,x,x+cw,d+1);x+=cw}})(node,0,w,0);
  let s=`<svg width="${w}" height="${rowsL.length*(H+1)+2}">`;rowsL.forEach((r,d)=>r.forEach(([n,x0,x1])=>{const hit=q&&n.n.toLowerCase().includes(q);const dim=q&&!hit;
   s+=`<g data-p="${n._p}"><rect x="${x0}" y="${d*(H+1)}" width="${Math.max(0.5,x1-x0-1)}" height="${H}" rx="2" fill="${col(n.l)}" opacity="${dim?.25:.92}" ${hit?'stroke="#fff" stroke-width="1.5"':''}><title>${esc(n.n)}\n${ms(n.v)} (${(n.v/root.v*100).toFixed(1)}%)</title></rect>${x1-x0>46?`<text x="${x0+4}" y="${d*(H+1)+13}" fill="#10131a">${esc(n.n).slice(0,Math.floor((x1-x0)/6.4))}</text>`:''}</g>`}));
  $('#flame').innerHTML=s+'</svg>';$('#fcrumb').textContent=node===root?`${ms(root.v)} total`:`${node.n} · ${ms(node.v)} · ${(node.v/root.v*100).toFixed(1)}% of total`;
  $('#flame').querySelectorAll('g').forEach(g=>g.onclick=()=>{const n=idx[g.dataset.p];if(n)draw(n)})}
 let idx=[];function index(n){n._p=idx.length;idx.push(n);n.c.forEach(index)}
 function load(k){root=R.trees[k];idx=[];index(root);draw(root)}
 $('#fsel').onchange=e=>load(e.target.value);$('#freset').onclick=()=>draw(root);$('#fsearch').oninput=e=>{q=e.target.value.toLowerCase();draw(cur)};
 load(R.trees['*all interactions']?'*all interactions':tk[0]);$('#fsel').value=R.trees['*all interactions']?'*all interactions':tk[0];window.addEventListener('resize',()=>draw(cur))}
</script></body></html>
"""
