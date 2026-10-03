'use strict';
/* DABT Profile Explorer. Data: ../reports/index.js (summary of every run) and ../reports/<id>/report.js (one run, loaded on demand).
   Both are written by tools/profiler/explore.py, which profile.py runs after every run. Without them the page asks for the reports folder. */

const DPROF = window.DPROF = {
  runs: {}, waiting: {},
  run(id, data) { this.runs[id] = data; (this.waiting[id] || []).forEach((f) => f(data)); delete this.waiting[id]; },
};
let INDEX = [];
const view = $('#view'), crumb = $('#crumb'), status = $('#status');
const store = {
  get(k, d) { try { return JSON.parse(localStorage.getItem('dprof.' + k)) ?? d; } catch (e) { return d; } },
  set(k, v) { try { localStorage.setItem('dprof.' + k, JSON.stringify(v)); } catch (e) { /* private window */ } },
};

// ── data ─────────────────────────────────────────────────────────────────────
function loadScript(src) {
  return new Promise((res, rej) => { const s = document.createElement('script'); s.src = src; s.onload = res; s.onerror = () => rej(new Error('cannot load ' + src)); document.head.append(s); });
}
function loadRun(id) {
  if (DPROF.runs[id]) return Promise.resolve(DPROF.runs[id]);
  return new Promise((res, rej) => {
    (DPROF.waiting[id] = DPROF.waiting[id] || []).push(res);
    if (DPROF.waiting[id].length === 1) loadScript(`../reports/${id}/report.js`).catch((e) => { delete DPROF.waiting[id]; rej(e); });
  });
}
const loadRuns = (ids) => Promise.all(ids.map(loadRun));
const entry = (id) => INDEX.find((r) => r.id === id);
const label = (id) => { const e = entry(id); return fmt.when(id) + (e ? ` · ${e.meta.commit || '?'}${e.meta.dirty ? '*' : ''}` : ''); };

async function boot() {
  $('#theme').onclick = () => { const t = document.documentElement.dataset.theme === 'light' ? 'dark' : 'light'; document.documentElement.dataset.theme = t; store.set('theme', t); };
  if (store.get('theme')) document.documentElement.dataset.theme = store.get('theme');
  try { await loadScript('../reports/index.js'); INDEX = window.DPROF_INDEX || []; } catch (e) { INDEX = []; }
  if (!INDEX.length) return pickFolder();
  INDEX.sort((a, b) => a.id < b.id ? -1 : 1);
  status.textContent = `${INDEX.length} runs`;
  addEventListener('hashchange', route);
  route();
}

/** No generated data (or none yet): read report.json files straight from a folder the user picks, or drops. */
function pickFolder() {
  const ingest = async (files) => {
    const list = [...files].filter((f) => /(^|\/)report\.json$/.test(f.webkitRelativePath || f.name));
    if (!list.length) return alert('no report.json found in that selection');
    INDEX = [];
    for (const f of list) {
      const d = JSON.parse(await f.text());
      const id = (f.webkitRelativePath || '').split('/').slice(-2, -1)[0] || (d.meta && d.meta.when) || f.name;
      DPROF.runs[id] = d;
      const m = d.machine || (d.meta && d.meta.machine);
      INDEX.push({ id, meta: Object.fromEntries(Object.entries(d.meta || {}).filter(([k]) => k !== 'machine' && k !== 'warnings')), machine: m || null, warnings: (d.warnings || []).length, insights: {},
        groups: Object.fromEntries((d.latency || []).map((g) => [g.id, [g.value, g.rating, g.n, g.budget_ms, g.failed || 0]])), startup: Object.fromEntries(Object.entries(d.startup || {}).map(([k, v]) => [k, v && v.ready_ms])),
        traced: !!(d.attr && Object.keys(d.attr.groups || {}).length) });
      (d.insights || []).forEach((i) => { const e = INDEX[INDEX.length - 1]; e.insights[i.sev] = (e.insights[i.sev] || 0) + 1; });
    }
    INDEX.sort((a, b) => a.id < b.id ? -1 : 1);
    status.textContent = `${INDEX.length} runs (from folder)`;
    addEventListener('hashchange', route);
    location.hash = '#/'; route();
  };
  view.replaceChildren(h('div.panel.drop', h('h1', 'No explorer data found yet'),
    h('p', 'Run ', h('code', 'python3 tools/profiler/explore.py'), ' (profile.py does this after every run), then reload. Or pick the reports folder here:'),
    h('input', { type: 'file', webkitdirectory: true, multiple: true, onchange: (e) => ingest(e.target.files) }),
    h('p.dim', 'or drop report.json files onto this page')));
  addEventListener('dragover', (e) => e.preventDefault());
  addEventListener('drop', (e) => { e.preventDefault(); ingest(e.dataTransfer.files); });
}

// ── router ───────────────────────────────────────────────────────────────────
function route() {
  tooltip.hide();
  const parts = location.hash.replace(/^#\/?/, '').split('/').filter(Boolean).map(decodeURIComponent);
  const [kind, a, b0] = parts;
  const b = b0 && b0.split('?')[0];
  crumb.replaceChildren();
  window.scrollTo(0, 0);
  document.querySelectorAll('#nav a').forEach((l) => l.classList.toggle('on', l.getAttribute('href') === (kind === 'runs' || kind === 'run' ? '#/runs' : kind === 'compare' ? '#/compare' : '#/') ));
  if (kind === 'run' && a) { crumb.append('› ', h('a', { href: '#/runs' }, 'Runs'), ' › ', h('a', { href: '#/run/' + a }, label(a))); return runPage(a, b || 'summary').catch(fail); }
  if (kind === 'compare' && a) { crumb.append('› compare'); return comparePage(a.split(','), b || 'latency').catch(fail); }
  if (kind === 'runs') return runsPage();
  overviewPage();
}
const fail = (e) => view.replaceChildren(h('div.panel', h('h1', 'Could not load'), h('p.slow', e.message), h('p.dim', 'The run may have been deleted. Run explore.py again.')));
const go = (hash) => { location.hash = hash; };


// ── overview ─────────────────────────────────────────────────────────────────
/** First page: where every measured group stands now and how all of them moved over the runs, on one chart. */
function overviewPage() {
  const newest = INDEX[INDEX.length - 1];
  const f = Object.assign({ machine: '', mode: '', last: 0, y: 'budget', hidden: [], solo: '', retired: false }, store.get('ov', {}));
  const save = () => store.set('ov', f);
  const machines = [...new Set(INDEX.map((r) => (r.machine && r.machine.id) || '?'))];
  const modes = [...new Set(INDEX.map((r) => r.meta.mode).filter(Boolean))];
  const root = h('div'), top = h('div.row'), stats = h('div'), chartBox = h('div.panel'), legendBox = h('div');
  const sel = (key, opts, render) => h('select', { onchange: (e) => { f[key] = e.target.value; f.solo = ''; save(); draw(); } }, opts.map(([v, t]) => h('option', { value: v, selected: String(f[key]) === String(v) }, t)));
  top.append(
    h('label.dim', 'machine '), sel('machine', [['', 'all machines'], ['latest', 'same as newest run'], ...machines.map((m) => [m, m])]),
    h('label.dim', 'mode '), sel('mode', [['', 'any'], ...modes.map((m) => [m, m])]),
    h('label.dim', 'window '), sel('last', [[0, 'all runs'], [50, 'last 50'], [20, 'last 20'], [10, 'last 10']]),
    h('label.dim', 'scale '), sel('y', [['budget', '× budget, log (all groups comparable)'], ['index', '% of first run, log'], ['abs', 'absolute ms, log']]),
    h('label', h('input', { type: 'checkbox', checked: f.retired, onchange: (e) => { f.retired = e.target.checked; save(); draw(); } }), ' include groups that no longer exist'),
    h('span.grow'), h('a', { href: '#/runs' }, 'all runs ›'));
  root.append(h('div.row', h('h1', { style: { margin: 0 } }, 'Overview')), top, chartBox, legendBox, stats);
  view.replaceChildren(root);

  function draw() {
    const mach = f.machine === 'latest' ? ((newest.machine && newest.machine.id) || '?') : f.machine;
    let runs = INDEX.filter((r) => (!mach || ((r.machine && r.machine.id) || '?') === mach) && (!f.mode || r.meta.mode === f.mode));
    if (+f.last) runs = runs.slice(-f.last);
    if (!runs.length) { stats.replaceChildren(h('p.dim', 'no runs match')); chartBox.replaceChildren(); legendBox.replaceChildren(); return; }
    const ids = [...new Set(runs.flatMap((r) => Object.keys(r.groups)))].filter((g) => f.retired || runs[runs.length - 1].groups[g]).sort();
    // a failed group's number is not a measurement
    const val = (r, g) => { const x = r.groups[g]; return x && x[0] != null && !x[4] ? x[0] : null; };
    const series = ids.map((g) => runs.map((r) => val(r, g)));
    const budgetOf = (g) => { for (let i = runs.length - 1; i >= 0; i--) if (runs[i].groups[g]) return runs[i].groups[g][3]; return null; };
    const last = runs[runs.length - 1];

    // current statistics
    const fam = {}; ids.forEach((g) => (fam[g.split('.')[0]] = fam[g.split('.')[0]] || []).push(g));
    stats.replaceChildren(
      h('div.panel', h('div.row', h('b', 'Newest run in view '), h('a', { href: '#/run/' + last.id }, label(last.id)), h('span.dim', `${last.meta.scenario || ''} · ${last.meta.mode || ''} · ${runs.length} runs in view`),
        last.machine ? h('span.dim', last.machine.cpu_model) : null, h('span.grow'),
        h('span', 'crit ', h('b.' + (last.insights.crit ? 'slow' : 'good'), last.insights.crit || 0)), h('span', 'slow groups ', h('b.' + (Object.values(last.groups).some((x) => x[1] === 'slow') ? 'slow' : 'good'), Object.values(last.groups).filter((x) => x[1] === 'slow').length)),
        runs.length > 1 ? h('a', { href: `#/compare/${runs[runs.length - 2].id},${last.id}` }, 'vs previous ›') : null),
        h('p.dim', { style: { margin: '2px 0 8px' } }, 'Each tile: latest value of the group, change against the previous run and against the first run in view, and its history. Click a tile to isolate it on the chart.'),
        Object.entries(fam).map(([p, gs]) => h('div', h('h3', p), h('div.tiles.dense', gs.map((g) => {
          const vs = series[ids.indexOf(g)]; let li = vs.length - 1; while (li >= 0 && vs[li] == null) li--;
          const cur = vs[li]; let pi = li - 1; while (pi >= 0 && vs[pi] == null) pi--;
          const first = vs.find((x) => x != null), b = budgetOf(g), rt = ratingOf(cur, b);
          const dp = pi >= 0 ? delta(vs[pi], cur) : null, df = delta(first, cur);
          return h('div.tile' + (f.solo === g ? '.on' : ''), { onclick: () => { f.solo = f.solo === g ? '' : g; save(); draw(); }, title: `${g}\nlatest in ${label(runs[li]?.id || '')}` },
            h('div.t', g, li < vs.length - 1 ? h('span.dim', ' (not in newest run)') : null), h('div.v.' + rt, cur == null ? '–' : fmt.ms(cur)),
            h('div.t', b ? [meter(cur, b), ' ', (cur / b).toFixed(2) + '× of ' + fmt.ms(b)] : ''),
            h('div.t', h('span', { class: deltaClass(dp) }, dp == null ? '' : 'prev ' + fmt.pct(dp)), ' ', h('span', { class: deltaClass(df) }, df == null || pi < 0 && df === 0 ? '' : 'first ' + fmt.pct(df))),
            spark(vs.slice(-40), b, 'var(--' + (rt === 'na' ? 'accent' : rt) + ')'));
        }))))));

    // progression of every group at once
    const visible = ids.filter((g) => !f.hidden.includes(g) && (!f.solo || f.solo === g));
    const xs = runs.map((r) => fmt.when(r.id));
    const yv = (g, i) => { const v = series[ids.indexOf(g)][i]; if (v == null) return null; const first = series[ids.indexOf(g)].find((x) => x != null);
      return f.y === 'budget' ? (budgetOf(g) ? v / budgetOf(g) : null) : f.y === 'index' ? v / first * 100 : v; };
    const chart = lineChart(visible.map((g) => ({ name: g, color: layerColor(g), pts: runs.map((r, i) => ({ x: i, id: r.id, y: yv(g, i), raw: series[ids.indexOf(g)][i], label: label(r.id), cls: 'r-' + (r.groups[g] ? r.groups[g][1] : '') })) })), xs,
      { h: 430, budget: f.y === 'budget' ? 1 : f.y === 'index' ? 100 : null, budgetLabel: f.y === 'budget' ? 'budget' : 'first run', log: true, thin: visible.length > 6,
        yfmt: f.y === 'budget' ? (v) => v.toFixed(2) + '×' : f.y === 'index' ? (v) => v.toFixed(0) + '%' : fmt.ms, onclick: (p) => go('#/run/' + p.id) });
    chartBox.replaceChildren(h('h2', { style: { marginTop: 0 } }, f.solo ? `Progression · ${f.solo}` : `Progression · ${visible.length} groups`), chart);

    // legend: one chip per group, a checkbox per family; hover isolates the line
    const hl = (g) => chart.querySelectorAll('g.ser').forEach((el) => { el.style.opacity = !g || el.dataset.s === g ? 1 : 0.1; });
    legendBox.replaceChildren(h('div.panel', h('div.row', h('b', 'Groups on the chart '), h('button', { onclick: () => { f.hidden = []; f.solo = ''; save(); draw(); } }, 'all'), h('button', { onclick: () => { f.hidden = ids.slice(); save(); draw(); } }, 'none'), h('small', 'hover a name to find its line; click to hide or show')),
      Object.entries(fam).map(([p, gs]) => h('div.row', h('label.fam', h('input', { type: 'checkbox', checked: gs.some((g) => !f.hidden.includes(g)), onchange: (e) => { f.hidden = e.target.checked ? f.hidden.filter((g) => !gs.includes(g)) : [...new Set(f.hidden.concat(gs))]; save(); draw(); } }), ' ', p),
        gs.map((g) => h('span.chipg' + (f.hidden.includes(g) ? '.off' : ''), { style: { '--c': layerColor(g) }, onmouseenter: () => hl(g), onmouseleave: () => hl(null), onclick: () => { f.hidden = f.hidden.includes(g) ? f.hidden.filter((x) => x !== g) : f.hidden.concat(g); save(); draw(); } }, g.slice(p.length + 1) || g))))));
  }
  draw();
}

// ── runs page ────────────────────────────────────────────────────────────────
function runsPage() {
  const sel = new Set(store.get('sel', []).filter((id) => entry(id)));
  const f = Object.assign({ q: '', machine: '', mode: '', branch: '', scenario: '', traced: false }, store.get('filter', {}));
  const uniq = (fn) => [...new Set(INDEX.map(fn).filter(Boolean))].sort();
  const root = h('div');
  const body = h('div');
  const bar = h('div.row');
  const input = (key, opts, ph) => h('select', { onchange: (e) => { f[key] = e.target.value; store.set('filter', f); redraw(); } }, h('option', { value: '' }, ph), opts.map((o) => h('option', { value: o, selected: f[key] === o }, o)));
  bar.append(
    h('input', { placeholder: 'filter: id, commit, scenario…', value: f.q, oninput: (e) => { f.q = e.target.value; store.set('filter', f); redraw(); } }),
    input('machine', uniq((r) => r.machine && r.machine.id), 'any machine'), input('branch', uniq((r) => r.meta.branch), 'any branch'),
    input('mode', uniq((r) => r.meta.mode), 'any mode'), input('scenario', uniq((r) => r.meta.scenario), 'any scenario'),
    h('label', h('input', { type: 'checkbox', checked: f.traced, onchange: (e) => { f.traced = e.target.checked; store.set('filter', f); redraw(); } }), ' with trace'),
    h('span.grow'),
    h('button', { onclick: () => { const ids = [...sel].sort(); ids.length >= 2 ? go('#/compare/' + ids.join(',')) : alert('tick at least two runs'); } }, 'Compare ticked'),
    h('button', { onclick: () => { sel.clear(); store.set('sel', []); redraw(); } }, 'Clear'));
  root.append(h('h1', 'All runs'), bar, body);
  view.replaceChildren(root);

  const filtered = () => INDEX.filter((r) => (!f.q || JSON.stringify([r.id, r.meta.commit, r.meta.branch, r.meta.scenario, r.meta.mode]).toLowerCase().includes(f.q.toLowerCase()))
    && (!f.machine || (r.machine && r.machine.id === f.machine)) && (!f.branch || r.meta.branch === f.branch) && (!f.mode || r.meta.mode === f.mode)
    && (!f.scenario || r.meta.scenario === f.scenario) && (!f.traced || r.traced));

  function redraw() {
    const runs = filtered();
    const cols = [
      { key: 'sel', label: '', get: (r) => sel.has(r.id) ? 0 : 1, render: (r) => h('input', { type: 'checkbox', checked: sel.has(r.id), onclick: (e) => e.stopPropagation(), onchange: (e) => { e.target.checked ? sel.add(r.id) : sel.delete(r.id); store.set('sel', [...sel]); } }) },
      { key: 'id', label: 'Run', get: (r) => r.id, render: (r) => h('a', { href: '#/run/' + r.id }, fmt.when(r.id)) },
      { key: 'commit', label: 'Commit', get: (r) => r.meta.commit, render: (r) => (r.meta.commit || '?') + (r.meta.dirty ? ' *' : '') },
      { key: 'branch', label: 'Branch', get: (r) => r.meta.branch },
      { key: 'scenario', label: 'Scenario', get: (r) => r.meta.scenario },
      { key: 'mode', label: 'Mode', get: (r) => r.meta.mode },
      { key: 'machine', label: 'Machine', get: (r) => r.machine && r.machine.id, render: (r) => r.machine ? tip(h('span.mono', r.machine.id), esc(`${r.machine.cpu_model} · ${r.machine.logical_cpus} threads · ${r.machine.ram_gb} GB`)) : h('span.dim', 'unknown') },
      { key: 'jobs', label: 'Jobs', num: true, get: (r) => r.meta.jobs ?? 1 },
      { key: 'rounds', label: 'Rounds', num: true, get: (r) => r.meta.rounds },
      { key: 'groups', label: 'Groups', num: true, get: (r) => Object.keys(r.groups).length },
      { key: 'failed', label: 'Failed', num: true, get: (r) => Object.values(r.groups).reduce((a, g) => a + (g[4] || 0), 0), cls: (r) => Object.values(r.groups).some((g) => g[4]) ? 'slow' : '' },
      { key: 'crit', label: 'Crit', num: true, get: (r) => r.insights.crit || 0, cls: (r) => r.insights.crit ? 'slow' : '' },
      { key: 'slow', label: 'Slow', num: true, get: (r) => Object.values(r.groups).filter((g) => g[1] === 'slow').length, cls: (r) => Object.values(r.groups).some((g) => g[1] === 'slow') ? 'slow' : '' },
      { key: 'warm', label: 'Warm start', num: true, get: (r) => r.startup.warm, render: (r) => fmt.ms(r.startup.warm) },
      { key: 'cold', label: 'Cold start', num: true, get: (r) => r.startup.cold, render: (r) => fmt.ms(r.startup.cold) },
      { key: 'dur', label: 'Took', num: true, get: (r) => r.meta.duration_s, render: (r) => fmt.dur(r.meta.duration_s) },
    ];
    body.replaceChildren(h('div.panel', h('div.dim', `${runs.length} of ${INDEX.length} runs`), table(cols, runs, { sort: 'id', dir: -1, onrow: (r) => go('#/run/' + r.id) })));
  }
  redraw();
}

// ── run page ─────────────────────────────────────────────────────────────────
const RUN_TABS = [['summary', 'Summary'], ['latency', 'Latency'], ['startup', 'Startup'], ['setup', 'Setup'], ['resources', 'Machine & resources'], ['functions', 'Functions'], ['layers', 'Layers'],
  ['graph', 'Calls & flow'], ['processes', 'Processes'], ['flame', 'Flame'], ['calibration', 'Calibration'], ['insights', 'Findings'], ['raw', 'Raw data']];

async function runPage(id, tab) {
  view.replaceChildren(h('p.dim', 'loading run…'));
  const d = await loadRun(id);
  const e = entry(id);
  const idx = INDEX.findIndex((r) => r.id === id);
  const content = h('div');
  const tabs = h('div.tabs', RUN_TABS.map(([k, t]) => h('a', { class: k === tab ? 'on' : '', href: `#/run/${id}/${k}` }, t)));
  const prev = INDEX[idx - 1], next = INDEX[idx + 1];
  view.replaceChildren(h('div.row', h('h1', { style: { margin: 0 } }, 'Run ' + label(id)), h('span.grow'),
    prev && h('a', { href: `#/run/${prev.id}/${tab}` }, '‹ previous'), next && h('a', { href: `#/run/${next.id}/${tab}` }, 'next ›'),
    prev && h('button', { onclick: () => go(`#/compare/${prev.id},${id}`) }, 'vs previous'),
    h('button', { onclick: () => go(`#/compare/${id}`) }, 'compare…')), tabs, content);
  const fn = RUN_VIEWS[tab] || RUN_VIEWS.summary;
  content.append(fn(d, e, id));
}

const kv = (obj, skip = []) => h('dl.kv', Object.entries(obj).filter(([k, v]) => v != null && typeof v !== 'object' && !skip.includes(k)).flatMap(([k, v]) => [h('dt', k), h('dd', String(v))]));
const sev = (i) => h('div.panel', h('span.chip.' + i.sev, i.sev.toUpperCase()), ' ', h('b', i.title), h('div.dim', i.detail), i.where && h('div.mono', String(i.where)), i.group && h('a', { href: '#/run/' + (location.hash.split('/')[2]) + '/latency' }, ' → ' + i.group));

const RUN_VIEWS = {
  summary(d, e) {
    const m = d.machine || (d.meta && d.meta.machine);
    return h('div',
      h('div.cols2', h('div.panel', h('h3', 'Run'), kv(d.meta, ['machine'])), h('div.panel', h('h3', 'Machine'), m ? kv(m) : h('p.dim', 'not recorded (run made before the profiler captured specs)'))),
      (d.warnings || []).length ? h('div.panel', h('h3.slow', 'Warnings'), h('ul', d.warnings.map((w) => h('li', w)))) : null,
      h('h2', 'Scorecard'), h('div.tiles', (d.latency || []).map((g) => h('div.tile', { onclick: () => go(`#/run/${e.id}/latency?${g.id}`), title: g.title },
        h('div.t', g.id), h('div.v.' + g.rating, g.value == null ? '–' : fmt.ms(g.value)), meter(g.value, g.budget_ms), h('div.t', `${g.n}× · budget ${fmt.ms(g.budget_ms)}${g.failed ? ' · ' + g.failed + ' failed' : ''}`)))),
      h('h2', 'Findings'), ...(d.insights || []).slice(0, 8).map(sev), (d.insights || []).length > 8 ? h('a', { href: `#/run/${e.id}/insights` }, `all ${d.insights.length} findings`) : null);
  },

  latency(d, e) {
    const groups = d.latency || [];
    const filter = h('input', { placeholder: 'filter groups…', oninput: () => redraw() });
    const holder = h('div'), detail = h('div');
    const st = (g, k, p) => g[k] && g[k][p];
    const cols = [
      { key: 'id', label: 'Group', get: (g) => g.id }, { key: 'title', label: 'What', get: (g) => g.title }, { key: 'kind', label: 'Kind', get: (g) => g.kind },
      { key: 'n', label: 'N', num: true, get: (g) => g.n }, { key: 'metric', label: 'Metric', get: (g) => g.metric },
      { key: 'value', label: 'Value', num: true, get: (g) => g.value, render: (g) => fmt.ms(g.value), cls: (g) => g.rating },
      { key: 'budget', label: 'Budget', num: true, get: (g) => g.budget_ms, render: (g) => fmt.ms(g.budget_ms) },
      { key: 'ratio', label: '× budget', num: true, get: (g) => g.budget_ms ? g.value / g.budget_ms : null, render: (g) => g.budget_ms ? h('span', g.value == null ? '–' : (g.value / g.budget_ms).toFixed(2) + ' ', meter(g.value, g.budget_ms)) : '–' },
      { key: 'paint', label: 'Paint med', num: true, get: (g) => st(g, 'paint', 'med'), render: (g) => fmt.ms(st(g, 'paint', 'med')) },
      { key: 'settle', label: 'Settle med', num: true, get: (g) => st(g, 'settle', 'med'), render: (g) => fmt.ms(st(g, 'settle', 'med')) },
      { key: 'p95', label: 'Settle p95', num: true, get: (g) => st(g, 'settle', 'p95'), render: (g) => fmt.ms(st(g, 'settle', 'p95')) },
      { key: 'max', label: 'Settle max', num: true, get: (g) => st(g, 'settle', 'max'), render: (g) => fmt.ms(st(g, 'settle', 'max')) },
      { key: 'busy', label: 'Busy', num: true, get: (g) => st(g, 'busy', 'med'), render: (g) => fmt.ms(st(g, 'busy', 'med')) },
      { key: 'queue', label: 'Queue', num: true, get: (g) => st(g, 'queue', 'med'), render: (g) => fmt.ms(st(g, 'queue', 'med')) },
      { key: 'cpu', label: 'CPU', num: true, get: (g) => st(g, 'cpu', 'med'), render: (g) => fmt.ms(st(g, 'cpu', 'med')) },
      { key: 'frames', label: 'Frames', num: true, get: (g) => st(g, 'frames', 'med'), render: (g) => fmt.n(st(g, 'frames', 'med'), 1) },
      { key: 'bytes', label: 'Bytes', num: true, get: (g) => st(g, 'bytes', 'med'), render: (g) => fmt.bytes(st(g, 'bytes', 'med')) },
      { key: 'failed', label: 'Failed', num: true, get: (g) => g.failed || 0, cls: (g) => g.failed ? 'slow' : '' },
      { key: 'rating', label: 'Rating', get: (g) => g.rating, cls: (g) => g.rating },
    ];
    function redraw() {
      const q = filter.value.toLowerCase();
      holder.replaceChildren(table(cols, groups.filter((g) => !q || (g.id + g.title).toLowerCase().includes(q)), { sort: 'ratio', onrow: (g) => { detail.replaceChildren(groupDetail(g)); detail.scrollIntoView({ behavior: 'smooth' }); } }));
    }
    redraw();
    const pre = decodeURIComponent((location.hash.split('?')[1] || ''));
    if (pre) { const g = groups.find((x) => x.id === pre); if (g) detail.append(groupDetail(g)); }
    return h('div', h('div.row', filter, h('small', 'click a row for samples, per-detail timings, frame sources, panes and spans')), h('div.panel', holder), detail);
  },

  startup(d) {
    const out = [];
    for (const k of ['cold', 'warm']) {
      const s = d.startup && d.startup[k];
      if (!s) continue;
      out.push(h('div.panel', h('h3', `${k} start`), h('div.row', h('span', 'ready ', h('b', fmt.ms(s.ready_ms))), h('span', 'first output ', h('b', fmt.ms(s.first_output_ms))), h('span', 'rss ', h('b', fmt.n(s.rss_kb) + ' KB')), s.cpu_ms ? h('span', 'cpu ', h('b', fmt.ms(s.cpu_ms))) : null),
        (s.spans || []).length ? gantt(s.spans.map((x, i) => ({ label: x.label || x[0], start: x.start ?? x[1], end: x.end ?? x[2], color: runColor(i) }))) : h('p.dim', 'no phase data')));
    }
    return h('div', out.length ? out : h('p.dim', 'no startup data'));
  },

  setup(d) {
    const rows = d.setup || [];
    if (!rows.length) return h('p.dim', 'this run has no setup data (made before setup steps were timed)');
    return h('div', h('p.dim', 'Getting from the default page to where each test begins. Profiled, but not part of any measured group.'),
      rows.map((u) => h('div.panel', h('h3', `${u.unit} · ${fmt.ms(u.total_ms)}${u.failed ? ' · ' + u.failed + ' failed' : ''}`),
        bars(u.steps.map((s) => ({ label: s.detail, value: s.ms, color: s.ok ? undefined : 'var(--slow)' }))))));
  },

  resources(d) {
    const m = d.machine || (d.meta && d.meta.machine);
    const rs = d.resources || [];
    return h('div', h('div.panel', h('h3', 'Machine'), m ? kv(m) : h('p.dim', 'not recorded')),
      d.meta && d.meta.load ? h('div.panel', h('h3', 'Whole run'), kv(d.meta.load)) : null,
      rs.length ? h('div.panel', h('h3', 'Per unit while it ran'), table([
        { key: 'unit', label: 'Unit' }, { key: 'rounds', label: 'Rounds', num: true }, { key: 'jobs', label: 'Jobs', num: true },
        { key: 'wall_s', label: 'Wall', num: true, render: (r) => fmt.n(r.wall_s, 1) + ' s' },
        { key: 'app_cores', label: 'App cores', num: true, render: (r) => fmt.n(r.app_cores, 2) },
        { key: 'app_rss_mb_max', label: 'App RSS', num: true, render: (r) => fmt.n(r.app_rss_mb_max, 0) + ' MB' },
        { key: 'sys_cpu_pct_mean', label: 'Machine CPU %', num: true, render: (r) => fmt.n(r.sys_cpu_pct_mean, 1) }, { key: 'sys_cpu_pct_p95', label: 'p95', num: true, render: (r) => fmt.n(r.sys_cpu_pct_p95, 1) },
        { key: 'sys_cpu_pct_max', label: 'max', num: true, render: (r) => fmt.n(r.sys_cpu_pct_max, 1) }, { key: 'busy_cores', label: 'Busy cores', num: true, render: (r) => fmt.n(r.busy_cores, 2) },
        { key: 'other_cores', label: 'Other work (cores)', num: true, render: (r) => fmt.n(r.other_cores, 2), cls: (r) => (r.jobs || 1) === 1 && r.other_cores >= 0.5 ? 'slow' : '' },
        { key: 'freq_mhz_mean', label: 'MHz', num: true, render: (r) => fmt.n(r.freq_mhz_mean, 0) }, { key: 'mem_used_mb_max', label: 'Mem used max', num: true, render: (r) => fmt.n(r.mem_used_mb_max, 0) + ' MB' },
      ], rs, { sort: 'unit', dir: 1 })) : h('p.dim', 'no resource data in this run'));
  },

  functions(d) {
    const fns = (d.attr && d.attr.functions) || [];
    if (!fns.length) return h('p.dim', 'no trace in this run (made with --no-trace)');
    const layers = [...new Set(fns.map((f) => f.layer))].sort();
    const q = h('input', { placeholder: 'filter by function or file…', oninput: () => redraw() });
    const ls = h('select', { onchange: () => redraw() }, h('option', { value: '' }, 'all layers'), layers.map((l) => h('option', l)));
    const holder = h('div');
    const redraw = () => {
      const s = q.value.toLowerCase();
      holder.replaceChildren(table([
        { key: 'name', label: 'Function', render: (f) => h('span.mono', f.name) }, { key: 'file', label: 'File' },
        { key: 'layer', label: 'Layer', render: (f) => h('span', { style: { color: layerColor(f.layer) } }, f.layer) },
        { key: 'self_ms', label: 'Self', num: true, render: (f) => fmt.ms(f.self_ms) }, { key: 'incl_ms', label: 'Inclusive', num: true, render: (f) => fmt.ms(f.incl_ms) },
        { key: 'calls', label: 'Calls', num: true, render: (f) => fmt.n(f.calls) }, { key: 'per_call_us', label: 'µs / call', num: true, render: (f) => fmt.n(f.per_call_us, 1) },
        { key: 'groups', label: 'Top groups', get: (f) => Object.keys(f.groups || {}).length, render: (f) => Object.entries(f.groups || {}).sort((a, b) => b[1] - a[1]).slice(0, 3).map(([g, v]) => `${g} ${fmt.ms(v)}`).join(' · ') },
      ], fns.filter((f) => (!s || (f.name + f.file).toLowerCase().includes(s)) && (!ls.value || f.layer === ls.value)), { sort: 'self_ms' }));
    };
    redraw();
    return h('div', h('div.row', q, ls, h('small', 'times are per pass of all interactions (after calibration)')), h('div.panel', holder));
  },

  layers(d) {
    const gs = (d.attr && d.attr.groups) || {};
    const ids = Object.keys(gs);
    if (!ids.length) return h('p.dim', 'no trace in this run');
    const kinds = [...new Set(ids.flatMap((g) => Object.keys(gs[g])))];
    const k = h('select', { onchange: () => redraw() }, kinds.map((x) => h('option', { value: x }, x === 'w' ? 'w · work' : x === 'a' ? 'a · all activity' : x)));
    const holder = h('div');
    const redraw = () => {
      const kind = k.value;
      const all = new Set(); ids.forEach((g) => Object.keys((gs[g][kind] || {}).layers || {}).forEach((l) => all.add(l)));
      holder.replaceChildren(h('div', h('div.legend', [...all].sort().map((l) => h('span', { style: { '--c': layerColor(l) } }, l))),
        ids.sort().map((g) => { const o = gs[g][kind]; if (!o || !o.layers) return null; const total = Object.values(o.layers).reduce((a, b) => a + b, 0);
          return h('div.bar', h('span.bl', g), stack(Object.entries(o.layers).sort((a, b) => b[1] - a[1]).map(([l, v]) => ({ label: l, value: v, color: layerColor(l) })), total), h('span.bv', fmt.ms(total), h('small', ` k=${(o.k ?? 0).toFixed(2)}`))); })));
    };
    redraw();
    return h('div', h('div.row', k, h('small', `global calibration k = ${(d.attr.global_k ?? 0).toFixed(3)}`)), h('div.panel', holder));
  },

  graph(d) {
    const a = d.attr || {};
    const t = (title, rows, cols) => rows && rows.length ? h('div.panel', h('h3', title), table(cols, rows, { sort: cols.find((c) => c.num)?.key })) : null;
    return h('div',
      t('Heaviest call edges', a.edges, [{ key: 'from', label: 'Caller' }, { key: 'to', label: 'Callee' }, { key: 'ms', label: 'Time', num: true, render: (r) => fmt.ms(r.ms) }]),
      t('Layer flow', a.flow, [{ key: 'from', label: 'From layer' }, { key: 'to', label: 'To layer' }, { key: 'ms', label: 'Time', num: true, render: (r) => fmt.ms(r.ms) }]),
      t('Hot source lines', a.hot_lines, [{ key: 'src', label: 'Line' }, { key: 'ms', label: 'Time', num: true, render: (r) => fmt.ms(r.ms) }, { key: 'hits', label: 'Hits', num: true, render: (r) => fmt.n(r.hits) },
        { key: 'ex_ms', label: 'Programs', num: true, render: (r) => fmt.ms(r.ex_ms) }, { key: 'fk_ms', label: 'Forks', num: true, render: (r) => fmt.ms(r.fk_ms) }, { key: 'code', label: 'Code', render: (r) => h('span.mono', r.code) }]),
      !a.edges ? h('p.dim', 'no trace in this run') : null);
  },

  processes(d) {
    const a = d.attr || {};
    return h('div',
      (a.execs || []).length ? h('div.panel', h('h3', 'External programs'), table([{ key: 'cmd', label: 'Program' }, { key: 'count', label: 'Runs', num: true, render: (r) => fmt.n(r.count, 1) }, { key: 'ms', label: 'Time', num: true, render: (r) => fmt.ms(r.ms) },
        { key: 'caller', label: 'Spawned by' }, { key: 'layer', label: 'Layer' }, { key: 'groups', label: 'Groups', get: (r) => Object.keys(r.groups || {}).length, render: (r) => Object.keys(r.groups || {}).join(', ') }], a.execs, { sort: 'ms' })) : null,
      (a.forks || []).length ? h('div.panel', h('h3', 'Subshell fork sites'), table([{ key: 'func', label: 'Function' }, { key: 'src', label: 'Source' }, { key: 'count', label: 'Forks', num: true, render: (r) => fmt.n(r.count, 1) },
        { key: 'layer', label: 'Layer' }, { key: 'groups', label: 'Groups', get: (r) => Object.keys(r.groups || {}).length, render: (r) => Object.keys(r.groups || {}).join(', ') }], a.forks, { sort: 'count' })) : null,
      !(a.execs || a.forks) ? h('p.dim', 'no trace in this run') : null);
  },

  flame(d) {
    const trees = d.trees || {};
    const ids = Object.keys(trees);
    if (!ids.length) return h('p.dim', 'no trace in this run');
    const pick = h('select', { onchange: () => draw() }, ids.map((g) => h('option', g)));
    const q = h('input', { placeholder: 'highlight function…', oninput: () => holder.firstChild && holder.firstChild.redraw() });
    const holder = h('div.panel');
    const draw = () => holder.replaceChildren(flame(trees[pick.value], { query: () => q.value.toLowerCase() }));
    draw();
    return h('div', h('div.row', pick, q, h('small', 'click a frame to zoom, a breadcrumb to go back; width = time (calibrated)')), holder);
  },

  calibration(d) {
    const c = d.calibration;
    if (!c) return h('p.dim', 'no calibration data');
    return h('div', h('div.row', h('span', 'mean error ', h('b', fmt.n(c.mae_pct, 0) + '%')), h('span', 'bias ', h('b', fmt.pct(c.bias_pct))), h('span', c.n + ' functions')),
      h('div.panel', table([{ key: 'group', label: 'Group' }, { key: 'func', label: 'Function', render: (r) => h('span.mono', r.func) }, { key: 'real_ms', label: 'Real', num: true, render: (r) => fmt.ms(r.real_ms) },
        { key: 'est_ms', label: 'Trace (rescaled)', num: true, render: (r) => fmt.ms(r.est_ms) }, { key: 'err_pct', label: 'Error', num: true, render: (r) => fmt.pct(r.err_pct), cls: (r) => Math.abs(r.err_pct) <= 15 ? 'good' : Math.abs(r.err_pct) <= 30 ? 'ok' : 'slow' }], c.rows, { sort: 'real_ms' })));
  },

  insights(d, e) { return h('div', (d.insights || []).length ? d.insights.map((i) => { const p = sev(i); return p; }) : h('p.dim', 'no findings')); },

  raw(d) { return h('div.panel', jsonTree(d, 'report', true)); },
};

function groupDetail(g) {
  const sts = ['paint', 'settle', 'busy', 'queue', 'cpu', 'frames', 'bytes', 'lag_med', 'lag_max', 'tail', 'frame_gap'].filter((k) => g[k]);
  const dts = g.details || [];
  const tl = h('div');
  return h('div.panel', h('h3', `${g.id} · ${g.title}`),
    h('div.row', h('span', 'metric ', h('b', g.metric), ' = ', h('b.' + g.rating, fmt.ms(g.value))), h('span', 'budget ', h('b', fmt.ms(g.budget_ms))), g.note ? h('span.slow', g.note) : null,
      g.no_effect ? h('span.slow', g.no_effect + ' had no effect') : null, g.went_false ? h('span.dim', g.went_false + ' of ' + g.n + ' without a page switch (tui.goto)') : null),
    (g.samples || []).length ? h('div', h('small', 'samples (settle ms), line = median, dashed = budget'), dots(g.samples, { budget: g.budget_ms })) : null,
    h('div.cols2', h('div', h('h3', 'All statistics'), table([{ key: 'k', label: 'Stat' }, { key: 'n', label: 'n', num: true }, ...['min', 'med', 'p95', 'max', 'mean'].map((p) => ({ key: p, label: p, num: true, render: (r) => r.f(r[p]) }))],
      sts.map((k) => Object.assign({ k, f: k === 'frames' ? (x) => fmt.n(x, 1) : k === 'bytes' ? fmt.bytes : fmt.ms }, g[k])), {})),
      (g.frame_src || []).length ? h('div', h('h3', 'Who flushes the frames'), table([{ key: 'chain', label: 'Caller chain', render: (r) => h('span.mono', r.chain) }, { key: 'frames', label: 'Frames', num: true, render: (r) => fmt.n(r.frames, 2) }, { key: 'bytes', label: 'Bytes', num: true, render: (r) => fmt.bytes(r.bytes) }], g.frame_src, {})) : null),
    h('div.cols2', (g.panes || []).length ? h('div', h('h3', 'Pane drawing'), bars(g.panes.map((p) => ({ label: p.pane, value: p.ms, sub: '×' + fmt.n(p.draws, 1) })))) : null,
      (g.spans || []).length ? h('div', h('h3', 'Wall time per probed function'), bars(g.spans.map((s) => ({ label: s.func, value: s.ms })))) : null),
    dts.length ? h('div', h('h3', 'Per detail (each step of the group)'), table([{ key: 'detail', label: 'Detail' }, { key: 'settle', label: 'Settle', num: true, render: (r) => fmt.ms(r.settle) }, { key: 'busy', label: 'Busy', num: true, render: (r) => fmt.ms(r.busy) },
      { key: 'queue', label: 'Queue', num: true, render: (r) => fmt.ms(r.queue) }, { key: 'frames', label: 'Frames', num: true, render: (r) => fmt.n(r.frames, 1) }, { key: 'bytes', label: 'Bytes', num: true, render: (r) => fmt.bytes(r.bytes) }],
      dts, { sort: 'settle', onrow: (r) => { tl.replaceChildren(h('h3', `Timeline · ${r.detail}`), (r.timeline || []).length ? gantt(r.timeline.map((t, i) => ({ label: t[0], start: t[1], end: t[1] + t[2], color: layerColor(t[0].replace(/^_?tui[._]?/, '').split(/[._]/)[0]) })).sort((a, b) => a.start - b.start), { left: 230 }) : h('p.dim', 'no timeline'), kv(r.spans || {})); } }), tl) : null);
}

// ── compare page ─────────────────────────────────────────────────────────────
const CMP_TABS = [['latency', 'Latency'], ['startup', 'Startup'], ['functions', 'Functions'], ['layers', 'Layers'], ['setup', 'Setup'], ['resources', 'Resources'], ['context', 'Context']];

async function comparePage(ids, tab) {
  ids = ids.filter((i) => entry(i));
  view.replaceChildren(h('p.dim', 'loading runs…'));
  const runs = await loadRuns(ids);
  const content = h('div');
  const pills = h('div.row', ids.map((id, i) => h('span.pill', h('b', { style: { background: runColor(i) } }), label(id) + (i === 0 ? ' (base)' : ''),
    h('button', { title: 'remove', onclick: () => go('#/compare/' + ids.filter((x) => x !== id).join(',') + '/' + tab) }, '×'))),
    h('select', { onchange: (e) => e.target.value && go('#/compare/' + ids.concat(e.target.value).join(',') + '/' + tab) }, h('option', { value: '' }, '+ add run'),
      INDEX.filter((r) => !ids.includes(r.id)).reverse().map((r) => h('option', { value: r.id }, label(r.id) + ' ' + (r.meta.scenario || '')))),
    ids.length > 1 ? h('button', { onclick: () => go('#/compare/' + ids.slice().reverse().join(',') + '/' + tab) }, 'reverse') : null);
  view.replaceChildren(h('h1', 'Compare'), pills, h('div.tabs', CMP_TABS.map(([k, t]) => h('a', { class: k === tab ? 'on' : '', href: `#/compare/${ids.join(',')}/${k}` }, t))), content);
  if (ids.length < 2) return content.append(h('p.dim', 'add at least one more run'));
  content.append((CMP_VIEWS[tab] || CMP_VIEWS.latency)(runs, ids));
}

/** Per-run cells with a change against the first run. get(run) -> number. */
function cmpCells(runs, get, f = fmt.ms) {
  const base = get(runs[0]);
  return runs.map((r, i) => { const v = get(r); const dl = i ? delta(base, v) : null;
    return h('td.r', { class: i ? deltaClass(dl) : '' }, f(v), i && dl != null ? h('small', ' ' + fmt.pct(dl)) : null); });
}
function cmpTable(head, rows, runs, { firstCols = 1 } = {}) {
  return h('table.data', h('thead', h('tr', head.map((x) => h('th', x)), runs.map((r, i) => h('th.r', { style: { color: runColor(i) } }, fmt.when(r.__id))))), h('tbody', rows));
}

const CMP_VIEWS = {
  latency(runs, ids) {
    runs.forEach((r, i) => { r.__id = ids[i]; });
    const gs = [...new Set(runs.flatMap((r) => (r.latency || []).map((g) => g.id)))];
    const pick = (r, id) => (r.latency || []).find((g) => g.id === id);
    const q = h('input', { placeholder: 'filter groups…', oninput: () => redraw() });
    const sortSel = h('select', { onchange: () => redraw() }, ...[['change', 'largest change vs base'], ['name', 'name'], ['value', 'base value']].map(([v, t]) => h('option', { value: v }, t)));
    const holder = h('div'), detail = h('div');
    const redraw = () => {
      const s = q.value.toLowerCase();
      const rows = gs.filter((g) => !s || g.includes(s)).map((id) => { const vals = runs.map((r) => pick(r, id)?.value); const worst = Math.max(0, ...vals.slice(1).map((v) => Math.abs(delta(vals[0], v) ?? 0))); return { id, vals, worst }; });
      rows.sort(sortSel.value === 'name' ? (a, b) => a.id < b.id ? -1 : 1 : sortSel.value === 'value' ? (a, b) => (b.vals[0] ?? 0) - (a.vals[0] ?? 0) : (a, b) => b.worst - a.worst);
      holder.replaceChildren(cmpTable(['Group', 'Budget'], rows.map((r) => {
        const g0 = runs.map((x) => pick(x, r.id)).find(Boolean);
        const tr = h('tr.click', { onclick: () => { detail.replaceChildren(groupCompare(r.id, runs, ids)); detail.scrollIntoView({ behavior: 'smooth' }); } }, h('td', r.id), h('td.r', fmt.ms(g0 && g0.budget_ms)), ...cmpCells(runs, (x) => pick(x, r.id)?.value));
        return tr; }), runs));
    };
    redraw();
    return h('div', h('div.row', q, sortSel, h('small', 'change vs the first run, green = faster; click a row for distributions')), h('div.panel', holder), detail);
  },

  startup(runs, ids) {
    runs.forEach((r, i) => { r.__id = ids[i]; });
    const rows = [];
    for (const k of ['cold', 'warm']) {
      rows.push(h('tr', h('td', `${k} ready`), ...cmpCells(runs, (r) => r.startup?.[k]?.ready_ms)), h('tr', h('td', `${k} first output`), ...cmpCells(runs, (r) => r.startup?.[k]?.first_output_ms)),
        h('tr', h('td', `${k} rss`), ...cmpCells(runs, (r) => r.startup?.[k]?.rss_kb, (v) => fmt.n(v) + ' KB')));
      const labels = [...new Set(runs.flatMap((r) => (r.startup?.[k]?.spans || []).map((s) => s.label || s[0])))];
      labels.forEach((l) => rows.push(h('tr', h('td.dim', `   ${k}: ${l}`), ...cmpCells(runs, (r) => { const s = (r.startup?.[k]?.spans || []).find((x) => (x.label || x[0]) === l); return s ? (s.end ?? s[2]) - (s.start ?? s[1]) : null; }))));
    }
    return h('div.panel', cmpTable(['Phase'], rows, runs));
  },

  functions(runs, ids) {
    runs.forEach((r, i) => { r.__id = ids[i]; });
    const maps = runs.map((r) => new Map(((r.attr && r.attr.functions) || []).map((f) => [f.name, f])));
    if (!maps.some((m) => m.size)) return h('p.dim', 'none of these runs has a trace');
    const names = [...new Set(maps.flatMap((m) => [...m.keys()]))];
    const q = h('input', { placeholder: 'filter by function…', oninput: () => redraw() });
    const metric = h('select', { onchange: () => redraw() }, h('option', { value: 'self_ms' }, 'self time'), h('option', { value: 'incl_ms' }, 'inclusive time'), h('option', { value: 'calls' }, 'calls'));
    const holder = h('div');
    const redraw = () => {
      const m = metric.value, s = q.value.toLowerCase();
      const val = (i, n) => maps[i].get(n)?.[m] ?? null;
      const rows = names.filter((n) => !s || n.toLowerCase().includes(s)).map((n) => ({ n, v: runs.map((_, i) => val(i, n)) }))
        .map((r) => Object.assign(r, { d: Math.max(0, ...r.v.slice(1).map((x) => Math.abs((x ?? 0) - (r.v[0] ?? 0)))) })).sort((a, b) => b.d - a.d).slice(0, 300);
      holder.replaceChildren(cmpTable(['Function', 'Layer'], rows.map((r) => h('tr', h('td.mono', r.n), h('td', maps.map((x) => x.get(r.n)?.layer).find(Boolean) || ''), ...runs.map((_, i) => { const base = r.v[0], v = r.v[i]; const dl = i ? delta(base, v) : null;
        return h('td.r', { class: i ? deltaClass(dl) : '' }, m === 'calls' ? fmt.n(v, 0) : fmt.ms(v), i && dl != null ? h('small', ' ' + fmt.pct(dl)) : null); }))), runs));
    };
    redraw();
    return h('div', h('div.row', q, metric, h('small', 'sorted by absolute change vs the first run, top 300')), h('div.panel', holder));
  },

  layers(runs, ids) {
    const withTrace = runs.map((r, i) => ({ r, i })).filter((x) => x.r.attr && x.r.attr.groups && Object.keys(x.r.attr.groups).length);
    if (withTrace.length < 1) return h('p.dim', 'none of these runs has a trace');
    const gset = [...new Set(withTrace.flatMap((x) => Object.keys(x.r.attr.groups)))].sort();
    const pick = h('select', { onchange: () => redraw() }, gset.map((g) => h('option', g)));
    const holder = h('div');
    const redraw = () => {
      const g = pick.value;
      const all = new Set(); withTrace.forEach((x) => Object.keys(x.r.attr.groups[g]?.w?.layers || {}).forEach((l) => all.add(l)));
      const max = Math.max(...withTrace.map((x) => Object.values(x.r.attr.groups[g]?.w?.layers || {}).reduce((a, b) => a + b, 0)), 1);
      holder.replaceChildren(h('div', h('div.legend', [...all].sort().map((l) => h('span', { style: { '--c': layerColor(l) } }, l))),
        withTrace.map((x) => { const L = x.r.attr.groups[g]?.w?.layers || {}; const total = Object.values(L).reduce((a, b) => a + b, 0);
          return h('div.bar', h('span.bl', { style: { color: runColor(x.i) } }, label(ids[x.i])), stack(Object.entries(L).sort((a, b) => b[1] - a[1]).map(([l, v]) => ({ label: l, value: v, color: layerColor(l) })), max), h('span.bv', fmt.ms(total))); }),
        h('h3', 'Layer by run'), table([{ key: 'l', label: 'Layer' }, ...withTrace.map((x) => ({ key: 'r' + x.i, label: fmt.when(ids[x.i]), num: true, render: (row) => fmt.ms(row['r' + x.i]) }))],
          [...all].map((l) => Object.assign({ l }, ...withTrace.map((x) => ({ ['r' + x.i]: x.r.attr.groups[g]?.w?.layers?.[l] ?? null })))))));
    };
    redraw();
    return h('div', h('div.row', pick, h('small', 'bars share one scale: wall ms per action, by layer')), h('div.panel', holder));
  },

  setup(runs, ids) {
    runs.forEach((r, i) => { r.__id = ids[i]; });
    const units = [...new Set(runs.flatMap((r) => (r.setup || []).map((u) => u.unit)))];
    if (!units.length) return h('p.dim', 'none of these runs has setup data');
    const rows = [];
    units.forEach((u) => {
      rows.push(h('tr', h('td', h('b', u)), ...cmpCells(runs, (r) => (r.setup || []).find((x) => x.unit === u)?.total_ms)));
      const steps = [...new Set(runs.flatMap((r) => ((r.setup || []).find((x) => x.unit === u)?.steps || []).map((s) => s.detail)))];
      steps.forEach((s) => rows.push(h('tr', h('td.dim', '   ' + s), ...cmpCells(runs, (r) => (r.setup || []).find((x) => x.unit === u)?.steps.find((y) => y.detail === s)?.ms))));
    });
    return h('div.panel', cmpTable(['Unit / step'], rows, runs));
  },

  resources(runs, ids) {
    runs.forEach((r, i) => { r.__id = ids[i]; });
    const units = [...new Set(runs.flatMap((r) => (r.resources || []).map((u) => u.unit)))];
    if (!units.length) return h('p.dim', 'none of these runs has resource data');
    const metrics = [['app_cores', 'app cores', (v) => fmt.n(v, 2)], ['app_rss_mb_max', 'app RSS', (v) => fmt.n(v, 0) + ' MB'], ['sys_cpu_pct_mean', 'machine CPU %', (v) => fmt.n(v, 1)], ['other_cores', 'other work (cores)', (v) => fmt.n(v, 2)], ['freq_mhz_mean', 'MHz', (v) => fmt.n(v, 0)]];
    const rows = units.flatMap((u) => metrics.map(([k, l, f]) => h('tr', h('td', `${u} · ${l}`), ...cmpCells(runs, (r) => (r.resources || []).find((x) => x.unit === u)?.[k], f))));
    return h('div.panel', cmpTable(['Unit · metric'], rows, runs));
  },

  context(runs, ids) {
    const rows = {};
    runs.forEach((r, i) => {
      const m = r.machine || r.meta?.machine || {};
      for (const [k, v] of Object.entries(r.meta || {})) if (typeof v !== 'object') (rows['run · ' + k] = rows['run · ' + k] || [])[i] = v;
      for (const [k, v] of Object.entries(m)) (rows['machine · ' + k] = rows['machine · ' + k] || [])[i] = v;
    });
    const mid = runs.map((r) => (r.machine || r.meta?.machine || {}).id);
    return h('div', new Set(mid).size > 1 ? h('p.slow', 'These runs are from different machines (or one has no machine record): absolute times are not comparable.') : null,
      h('div.panel', h('table.data', h('thead', h('tr', h('th', 'Field'), runs.map((_, i) => h('th', { style: { color: runColor(i) } }, fmt.when(ids[i]))))),
        h('tbody', Object.entries(rows).map(([k, vs]) => { const diff = new Set(runs.map((_, i) => String(vs[i]))).size > 1; return h('tr', h('td', { class: diff ? 'ok' : 'dim' }, k), runs.map((_, i) => h('td.mono', vs[i] == null ? '–' : String(vs[i])))); })))));
  },
};

/** One group across runs: statistics on a common scale, samples and per-detail timings. */
function groupCompare(id, runs, ids) {
  const gs = runs.map((r) => (r.latency || []).find((g) => g.id === id));
  const key = (g) => g && (g.settle ? 'settle' : g.paint ? 'paint' : null);
  const max = Math.max(...gs.map((g) => g && g[key(g)] ? g[key(g)].max : 0), 1);
  const dts = [...new Set(gs.flatMap((g) => (g && g.details || []).map((d) => d.detail)))];
  return h('div.panel', h('h3', id), h('p.dim', 'whisker: min – p95 (box) – max, thick line = median, on one shared scale'),
    gs.map((g, i) => h('div.bar', { style: { gridTemplateColumns: '210px 1fr 150px' } }, h('span.bl', { style: { color: runColor(i) } }, label(ids[i])), g ? whisker(g[metricOf(g)], max, runColor(i)) : h('span.dim', 'not in this run'),
      h('span.bv', g ? fmt.ms(g.value) : '–', g ? h('small', ` n=${g.n}`) : null))),
    dts.length ? h('div', h('h3', 'Per detail (settle)'), cmpTable(['Detail'], dts.map((d) => h('tr', h('td', d), ...cmpCells(runs, (r) => (r.latency || []).find((g) => g.id === id)?.details?.find((x) => x.detail === d)?.settle))), runs.map((r, i) => Object.assign(r, { __id: ids[i] })))) : null);
}
const metricOf = (g) => g.settle ? 'settle' : 'paint';

boot();
