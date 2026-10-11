'use strict';
/* Small helpers and SVG charts for the explorer. No dependencies, no network. */

const $ = (sel, el) => (el || document).querySelector(sel);
const NS = 'http://www.w3.org/2000/svg';

/** h('div.cls#id', {attr: v, onclick: fn}, ...children) -> element. Strings and numbers become text; null/false are skipped. */
function h(tag, attrs, ...kids) {
  const m = /^([a-z0-9]+)((?:[.#][\w-]+)*)$/i.exec(tag);
  const svg = ['svg', 'g', 'rect', 'line', 'path', 'text', 'circle', 'title', 'polyline'].includes(m[1]);
  const el = svg ? document.createElementNS(NS, m[1]) : document.createElement(m[1]);
  for (const t of (m[2].match(/[.#][\w-]+/g) || [])) t[0] === '.' ? el.classList.add(t.slice(1)) : (el.id = t.slice(1));
  if (attrs && (typeof attrs !== 'object' || attrs instanceof Node || Array.isArray(attrs))) { kids.unshift(attrs); attrs = null; }
  for (const [k, v] of Object.entries(attrs || {})) {
    if (v == null || v === false) continue;
    if (k.startsWith('on')) el.addEventListener(k.slice(2), v);
    else if (k === 'style' && typeof v === 'object') { for (const [p, x] of Object.entries(v)) p.startsWith('--') ? el.style.setProperty(p, x) : (el.style[p] = x); }
    else if (k === 'html') el.innerHTML = v;
    else el.setAttribute(k, v === true ? '' : v);
  }
  const add = (k) => { if (k == null || k === false) return; if (Array.isArray(k)) k.forEach(add); else el.append(k instanceof Node ? k : document.createTextNode(String(k))); };
  kids.forEach(add);
  return el;
}

const fmt = {
  ms: (v) => v == null || isNaN(v) ? '–' : v >= 1000 ? (v / 1000).toFixed(2) + ' s' : v >= 100 ? v.toFixed(0) + ' ms' : v >= 10 ? v.toFixed(1) + ' ms' : v.toFixed(2) + ' ms',
  n: (v, d = 0) => v == null || isNaN(v) ? '–' : Number(v).toLocaleString(undefined, { maximumFractionDigits: d, minimumFractionDigits: 0 }),
  bytes: (v) => v == null ? '–' : v >= 1048576 ? (v / 1048576).toFixed(1) + ' MB' : v >= 1024 ? (v / 1024).toFixed(1) + ' KB' : Math.round(v) + ' B',
  pct: (v, d = 0) => v == null || isNaN(v) ? '–' : (v > 0 ? '+' : '') + v.toFixed(d) + '%',
  dur: (s) => s == null ? '–' : s >= 60 ? Math.floor(s / 60) + 'm ' + Math.round(s % 60) + 's' : s.toFixed(0) + 's',
  when: (id) => /^(\d{4})(\d\d)(\d\d)-(\d\d)(\d\d)/.test(id) ? `${RegExp.$1}-${RegExp.$2}-${RegExp.$3} ${RegExp.$4}:${RegExp.$5}` : id,
};

/** Percent change of b against a (null when a is 0 or missing). */
const delta = (a, b) => a == null || b == null || a === 0 ? null : (b - a) / a * 100;
/** Colour class for a change: lower is better. */
const deltaClass = (d, eps = 5) => d == null ? 'na' : d <= -eps ? 'good' : d >= eps ? 'slow' : 'na';

const LAYER_COLORS = {};
function layerColor(name) {
  if (!LAYER_COLORS[name]) { let x = 0; for (const c of String(name)) x = (x * 31 + c.charCodeAt(0)) % 360; LAYER_COLORS[name] = `hsl(${x} 55% 55%)`; }
  return LAYER_COLORS[name];
}
const RUN_COLORS = ['#5b8def', '#e8833a', '#3fb68b', '#c45bd6', '#e5c13a', '#d95c5c', '#5bc2d6', '#8c8c99'];
const runColor = (i) => RUN_COLORS[i % RUN_COLORS.length];

/** Sortable table. cols: [{key, label, get(row), render(row)->node|string, num, cls(row)}]. Returns the table element; opts.onrow(row, tr). */
function table(cols, rows, opts = {}) {
  let sort = opts.sort || null, dir = opts.dir || -1;
  const tbl = h('table.data');
  const draw = () => {
    const data = rows.slice();
    if (sort) { const c = cols.find((x) => x.key === sort); const g = c.get || ((r) => r[c.key]); data.sort((a, b) => { const x = g(a), y = g(b); return (x == null) - (y == null) || (x > y ? 1 : x < y ? -1 : 0) * dir; }); }
    tbl.replaceChildren(
      h('thead', h('tr', cols.map((c) => h('th', { class: (c.num ? 'r ' : '') + (sort === c.key ? 'sorted' : ''), title: c.title || '', onclick: () => { dir = sort === c.key ? -dir : (c.num ? -1 : 1); sort = c.key; draw(); } },
        c.label, sort === c.key ? (dir < 0 ? ' ▼' : ' ▲') : '')))),
      h('tbody', data.map((r) => {
        const tr = h('tr', { class: opts.rowClass ? opts.rowClass(r) : '' }, cols.map((c) => {
          const v = c.render ? c.render(r) : (c.get ? c.get(r) : r[c.key]);
          return h('td', { class: (c.num ? 'r ' : '') + (c.cls ? c.cls(r) : '') }, v == null ? '–' : v);
        }));
        if (opts.onrow) { tr.classList.add('click'); tr.addEventListener('click', (e) => opts.onrow(r, tr, e)); }
        return tr;
      })));
    if (opts.after) opts.after(tbl);
  };
  draw();
  return tbl;
}

const tooltip = (() => {
  let el;
  return {
    show(e, html) { if (!el) { el = h('div.tip'); document.body.append(el); } el.innerHTML = html; el.style.display = 'block'; const w = el.offsetWidth; el.style.left = Math.min(innerWidth - w - 8, e.clientX + 14) + 'px'; el.style.top = Math.min(innerHeight - el.offsetHeight - 8, e.clientY + 14) + 'px'; },
    hide() { if (el) el.style.display = 'none'; },
  };
})();
const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
const tip = (el, html) => { el.addEventListener('mousemove', (e) => tooltip.show(e, typeof html === 'function' ? html() : html)); el.addEventListener('mouseleave', tooltip.hide); return el; };

const ratingOf = (v, b) => v == null || !b ? 'na' : v / b <= 1 ? 'good' : v / b <= 2 ? 'ok' : 'slow';

/** Thin horizontal meter: value against a budget (the full width is 2x the budget). */
function meter(v, budget) {
  const r = ratingOf(v, budget);
  return h('span.meter', h('i', { class: 'bg-' + r, style: { width: Math.min(100, (v || 0) / (2 * budget) * 100) + '%' } }), h('u'));
}

/** Line chart. series: [{name, color, pts: [{x, y, label, id, cls}]}], x are indices into xs (labels).
 *  opts: {w, h, budget, log, yfmt, onclick}. Each series polyline carries data-s=<name> so a legend can highlight it. */
function lineChart(series, xs, opts = {}) {
  const W = opts.w || 900, H = opts.h || 260, L = 54, R = 14, T = 12, B = 60;
  const T_ = opts.log ? (v) => Math.log10(Math.max(v, 0.01)) : (v) => v;
  const inv = opts.log ? (t) => Math.pow(10, t) : (t) => t;
  const all = series.flatMap((s) => s.pts.filter((p) => p.y != null).map((p) => T_(p.y)));
  const svg = h('svg.chart', { viewBox: `0 0 ${W} ${H}`, width: '100%' });
  if (!all.length) { svg.append(h('text', { x: W / 2, y: H / 2, 'text-anchor': 'middle', class: 'dim' }, 'no data for this selection')); return svg; }
  let ymax = Math.max(...all, opts.budget != null ? T_(opts.budget) : -Infinity), ymin = opts.log ? Math.min(...all) : 0;
  const pad = (ymax - ymin) * 0.06 || 1;
  ymax += pad; if (opts.log) ymin -= pad;
  const xw = (W - L - R) / Math.max(1, xs.length - 1);
  const X = (i) => L + (xs.length === 1 ? (W - L - R) / 2 : i * xw), Y = (v) => T + (H - T - B) * (1 - (T_(v) - ymin) / (ymax - ymin || 1));
  for (let i = 0; i <= 4; i++) {
    const v = inv(ymin + (ymax - ymin) * i / 4);
    svg.append(h('line', { x1: L, x2: W - R, y1: Y(v), y2: Y(v), class: 'grid' }), h('text', { x: L - 6, y: Y(v) + 4, 'text-anchor': 'end', class: 'axis' }, opts.yfmt ? opts.yfmt(v) : fmt.ms(v)));
  }
  const every = Math.ceil(xs.length / 14);
  xs.forEach((x, i) => { if (i % every === 0) svg.append(h('text', { x: X(i), y: H - B + 14, 'text-anchor': 'end', class: 'axis', transform: `rotate(-35 ${X(i)} ${H - B + 14})` }, x)); });
  if (opts.budget != null) svg.append(h('line', { x1: L, x2: W - R, y1: Y(opts.budget), y2: Y(opts.budget), class: 'budget' }), h('text', { x: W - R, y: Y(opts.budget) - 4, 'text-anchor': 'end', class: 'axis' }, opts.budgetLabel || 'budget'));
  for (const s of series) {
    const pts = s.pts.filter((p) => p.y != null);
    const g = h('g', { 'data-s': s.name, class: 'ser' });
    g.append(h('polyline', { points: pts.map((p) => `${X(p.x)},${Y(p.y)}`).join(' '), fill: 'none', stroke: s.color, 'stroke-width': opts.thin ? 1.2 : 1.8, opacity: 0.85 }));
    for (const p of pts) {
      const c = h('circle', { cx: X(p.x), cy: Y(p.y), r: opts.thin ? 2.5 : 4, fill: s.color, class: 'pt ' + (p.cls || ''), onclick: () => opts.onclick && opts.onclick(p) });
      tip(c, `<b>${esc(s.name)}</b><br>${esc(p.label || '')}<br>${(opts.yfmt || fmt.ms)(p.y)}${p.raw != null ? ' · ' + fmt.ms(p.raw) : ''}`);
      g.append(c);
    }
    svg.append(g);
  }
  return svg;
}

/** Tiny trend line of values (nulls skipped), optional budget line; the last point is marked. */
function spark(values, budget, color = 'var(--accent)', w = 120, hh = 28) {
  const v = values.map((y, i) => [i, y]).filter((p) => p[1] != null);
  const svg = h('svg.spark', { viewBox: `0 0 ${w} ${hh}`, width: w, height: hh });
  if (v.length < 2) return svg;
  const lo = Math.min(...v.map((p) => p[1]), budget ?? Infinity), hi = Math.max(...v.map((p) => p[1]), budget ?? 0);
  const X = (i) => 2 + i / Math.max(1, values.length - 1) * (w - 4), Y = (y) => 2 + (hh - 4) * (1 - (y - lo) / (hi - lo || 1));
  if (budget != null) svg.append(h('line', { x1: 0, x2: w, y1: Y(budget), y2: Y(budget), class: 'budget' }));
  svg.append(h('polyline', { points: v.map((p) => `${X(p[0])},${Y(p[1])}`).join(' '), fill: 'none', stroke: color, 'stroke-width': 1.4 }),
    h('circle', { cx: X(v[v.length - 1][0]), cy: Y(v[v.length - 1][1]), r: 2.4, fill: color }));
  return svg;
}

/** Grouped/plain horizontal bars. rows: [{label, value, color, sub, onclick}] */
function bars(rows, opts = {}) {
  const max = opts.max || Math.max(...rows.map((r) => r.value || 0), 1e-9);
  return h('div.bars', rows.map((r) => {
    const row = h('div.bar' + (r.onclick ? '.click' : ''), { onclick: r.onclick },
      h('span.bl', { title: r.label }, r.label),
      h('span.bt', h('i', { style: { width: Math.max(0.3, (r.value || 0) / max * 100) + '%', background: r.color || 'var(--accent)' } })),
      h('span.bv', (opts.fmt || fmt.ms)(r.value), r.sub ? h('small', ' ' + r.sub) : null));
    return r.tip ? tip(row, r.tip) : row;
  }));
}

/** Stacked horizontal bar of parts [{label, value, color}] scaled to `total`. */
function stack(parts, total, w = '100%') {
  const t = total || parts.reduce((a, p) => a + p.value, 0) || 1;
  return h('div.stack', { style: { width: w } }, parts.filter((p) => p.value > 0).map((p) => tip(h('i', { style: { width: p.value / t * 100 + '%', background: p.color } }), `${esc(p.label)}: ${fmt.ms(p.value)}`)));
}

/** Gantt: rows [{label, start, end, color}] in ms. */
function gantt(rows, opts = {}) {
  const W = opts.w || 900, RH = 20, L = opts.left || 190, H = rows.length * RH + 24;
  const max = Math.max(...rows.map((r) => r.end), 1);
  const X = (v) => L + v / max * (W - L - 12);
  const svg = h('svg.chart', { viewBox: `0 0 ${W} ${H}`, width: '100%' });
  rows.forEach((r, i) => {
    const y = i * RH + 4;
    svg.append(h('text', { x: L - 8, y: y + 13, 'text-anchor': 'end', class: 'axis' }, r.label));
    const rect = h('rect', { x: X(r.start), y, width: Math.max(1.5, X(r.end) - X(r.start)), height: RH - 6, rx: 2, fill: r.color || 'var(--accent)' });
    tip(rect, `<b>${esc(r.label)}</b><br>${fmt.ms(r.start)} → ${fmt.ms(r.end)} (${fmt.ms(r.end - r.start)})`);
    svg.append(rect);
  });
  for (let i = 0; i <= 4; i++) svg.append(h('text', { x: X(max * i / 4), y: H - 4, 'text-anchor': i === 4 ? 'end' : 'middle', class: 'axis' }, fmt.ms(max * i / 4)));
  return svg;
}

/** Dot strip of samples with min/median/max marks. */
function dots(values, opts = {}) {
  const W = opts.w || 1000, H = 46, L = 8, R = 8;
  const v = values.filter((x) => x != null).sort((a, b) => a - b);
  const svg = h('svg.chart', { viewBox: `0 0 ${W} ${H}`, width: opts.width || '100%' });
  if (!v.length) return svg;
  const lo = Math.min(v[0], opts.budget || Infinity) * 0.95, hi = Math.max(v[v.length - 1], opts.budget || 0) * 1.05;
  const X = (x) => L + (x - lo) / (hi - lo || 1) * (W - L - R);
  svg.append(h('line', { x1: L, x2: W - R, y1: 20, y2: 20, class: 'grid' }));
  if (opts.budget) svg.append(h('line', { x1: X(opts.budget), x2: X(opts.budget), y1: 4, y2: 36, class: 'budget' }));
  v.forEach((x) => svg.append(tip(h('circle', { cx: X(x), cy: 20, r: 3.5, fill: 'var(--accent)', opacity: 0.55 }), fmt.ms(x))));
  const med = v[Math.floor(v.length / 2)];
  svg.append(h('line', { x1: X(med), x2: X(med), y1: 8, y2: 32, stroke: 'var(--text)', 'stroke-width': 2 }));
  svg.append(h('text', { x: L, y: 44, class: 'axis' }, fmt.ms(v[0])), h('text', { x: W - R, y: 44, 'text-anchor': 'end', class: 'axis' }, fmt.ms(v[v.length - 1])));
  return svg;
}

/** Box/whisker: stat {min, med, p95, max} on a shared scale. */
function whisker(st, max, color) {
  const W = 360, X = (v) => 6 + v / max * (W - 12);
  const svg = h('svg.chart', { viewBox: `0 0 ${W} 22`, width: W });
  if (!st) return svg;
  svg.append(h('line', { x1: X(st.min), x2: X(st.max), y1: 11, y2: 11, stroke: color, 'stroke-width': 1.5, opacity: 0.6 }),
    h('rect', { x: X(st.min), y: 5, width: Math.max(2, X(st.p95 ?? st.max) - X(st.min)), height: 12, fill: color, opacity: 0.3 }),
    h('line', { x1: X(st.med), x2: X(st.med), y1: 3, y2: 19, stroke: color, 'stroke-width': 3 }));
  return tip(svg, `min ${fmt.ms(st.min)} · med ${fmt.ms(st.med)} · p95 ${fmt.ms(st.p95)} · max ${fmt.ms(st.max)}`);
}

/** Zoomable icicle flame graph for a {n, v, c} tree. */
function flame(tree, opts = {}) {
  const wrap = h('div.flame');
  const crumbs = h('div.crumbs');
  const holder = h('div');
  wrap.append(crumbs, holder);
  const RH = 18, W = 1100;
  const draw = (root, path) => {
    crumbs.replaceChildren(...path.map((n, i) => h('a', { onclick: () => draw(n, path.slice(0, i + 1)) }, n.n + (i < path.length - 1 ? ' ›' : ''))));
    const rows = [];
    let maxd = 0;
    const walk = (n, x0, w, d) => {
      if (w < 0.8) return;
      rows.push({ n, x0, w, d }); maxd = Math.max(maxd, d);
      let x = x0;
      for (const c of (n.c || [])) { const cw = w * c.v / (n.v || 1); walk(c, x, cw, d + 1); x += cw; }
    };
    walk(root, 0, W, 0);
    const svg = h('svg.chart', { viewBox: `0 0 ${W} ${(maxd + 1) * RH + 2}`, width: '100%' });
    const q = (opts.query && opts.query()) || '';
    for (const r of rows) {
      const hit = q && r.n.n.toLowerCase().includes(q);
      const g = h('g', { onclick: () => r.n.c && r.n.c.length && draw(r.n, path.concat([r.n])) },
        h('rect', { x: r.x0, y: r.d * RH, width: r.w - 0.6, height: RH - 1.5, rx: 2, fill: hit ? 'var(--accent)' : layerColor(opts.layerOf ? opts.layerOf(r.n.n) : r.n.n.replace(/^_?tui[._]?/, '').split(/[._]/)[0]), opacity: q && !hit ? 0.25 : 0.9, class: 'fl' }));
      if (r.w > 46) g.append(h('text', { x: r.x0 + 4, y: r.d * RH + 12.5, class: 'fltxt' }, r.n.n.slice(0, Math.floor(r.w / 6.6))));
      tip(g, `<b>${esc(r.n.n)}</b><br>${fmt.ms(r.n.v)} · ${(r.n.v / (root.v || 1) * 100).toFixed(1)}% of view`);
      svg.append(g);
    }
    holder.replaceChildren(svg);
  };
  wrap.redraw = () => draw(tree, [tree]);
  draw(tree, [tree]);
  return wrap;
}

/** Collapsible JSON tree, children built lazily. */
function jsonTree(value, name = 'root', open = false) {
  const isObj = value && typeof value === 'object';
  const row = h('div.jt');
  if (!isObj) { row.append(h('span.jk', name + ': '), h('span.jv.' + typeof value, typeof value === 'string' ? JSON.stringify(value) : String(value))); return row; }
  const keys = Array.isArray(value) ? value.map((_, i) => i) : Object.keys(value);
  const head = h('span.jh', `${name}  `, h('small', Array.isArray(value) ? `[${keys.length}]` : `{${keys.length}}`));
  const body = h('div.jb');
  let built = false;
  const build = (limit) => {
    body.replaceChildren(...keys.slice(0, limit).map((k) => jsonTree(value[k], k)));
    if (keys.length > limit) body.append(h('a.more', { onclick: () => build(limit + 500) }, `show ${Math.min(500, keys.length - limit)} more of ${keys.length - limit}`));
  };
  const toggle = () => { row.classList.toggle('open'); if (!built) { built = true; build(200); } };
  head.addEventListener('click', toggle);
  row.append(head, body);
  if (open) toggle();
  return row;
}
