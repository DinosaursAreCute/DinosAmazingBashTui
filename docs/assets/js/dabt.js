(function () {
  var d = document, r = d.documentElement;
  d.getElementById('theme').onclick = function () {
    var cur = r.dataset.theme || (matchMedia('(prefers-color-scheme: light)').matches ? 'light' : 'dark');
    var n = cur === 'dark' ? 'light' : 'dark';
    r.dataset.theme = n;
    try { localStorage.setItem('dabt-theme', n); } catch (e) {}
  };
  d.getElementById('menu').onclick = function () { d.body.classList.toggle('open'); };
  var path = location.pathname.replace(/\/$/, '').replace(/\.html$/, '');
  d.querySelectorAll('.nav a').forEach(function (a) {
    var p = a.pathname.replace(/\/$/, '').replace(/\.html$/, '');
    if (p === path) a.classList.add('active');
  });
  d.querySelectorAll('.doc pre').forEach(function (pre) {
    if (pre.closest('.mermaid')) return;
    var b = d.createElement('button');
    b.className = 'copy'; b.textContent = 'Copy';
    b.onclick = function () {
      navigator.clipboard.writeText(pre.innerText.replace(/Copy$/, '').trimEnd());
      b.textContent = 'Copied'; setTimeout(function () { b.textContent = 'Copy'; }, 1200);
    };
    pre.appendChild(b);
  });
  d.querySelectorAll('.doc h2[id], .doc h3[id]').forEach(function (h) {
    var a = d.createElement('a'); a.href = '#' + h.id; a.className = 'anchor'; a.textContent = '#';
    h.appendChild(a);
  });

  // ── search (Pagefind: built by the deploy workflow into /pagefind, not
  // present in a plain local preview) ──────────────────────────────────
  var overlay = d.getElementById('search-overlay');
  var trigger = d.getElementById('search-trigger');
  var closeBtn = d.getElementById('search-close');
  var scopeBar = d.getElementById('search-scope');
  var section = (d.querySelector('.doc[data-pagefind-filter]') || {}).dataset;
  section = section && section.pagefindFilter ? section.pagefindFilter.replace('section:', '') : '';
  var ui = null, uiLoad = null, scope = 'section';

  function loadUI() {
    if (uiLoad) return uiLoad;
    var base = r.dataset.baseurl || '';
    var css = d.createElement('link'); css.rel = 'stylesheet'; css.href = base + '/pagefind/pagefind-ui.css';
    d.head.appendChild(css);
    uiLoad = new Promise(function (resolve, reject) {
      var s = d.createElement('script'); s.src = base + '/pagefind/pagefind-ui.js';
      s.onload = resolve; s.onerror = reject;
      d.body.appendChild(s);
    });
    return uiLoad;
  }

  function buildUI() {
    var opts = {
      element: '#search',
      showSubResults: true,
      showImages: false,
      resetStyles: false
    };
    if (scope === 'section' && section) opts.filters = { section: section };
    d.getElementById('search').innerHTML = '';
    ui = new window.PagefindUI(opts);
    var input = d.querySelector('#search input');
    if (input) input.focus();
  }

  function setScope(next) {
    scope = next;
    scopeBar.querySelectorAll('[role=tab]').forEach(function (t) {
      t.setAttribute('aria-selected', t.dataset.scope === next ? 'true' : 'false');
    });
    if (ui) buildUI();
  }

  function openSearch() {
    overlay.hidden = false;
    d.body.classList.add('search-open');
    loadUI().then(function () {
      if (!ui) buildUI();
      var input = d.querySelector('#search input');
      if (input) input.focus();
    }).catch(function () {
      d.getElementById('search').textContent = 'Search isn’t available on this preview — only on the deployed site.';
    });
  }

  function closeSearch() {
    overlay.hidden = true;
    d.body.classList.remove('search-open');
  }

  if (!section) setScope('all'); // e.g. the home page has no section to scope to
  if (trigger) trigger.onclick = openSearch;
  if (closeBtn) closeBtn.onclick = closeSearch;
  if (overlay) overlay.addEventListener('click', function (e) { if (e.target === overlay) closeSearch(); });
  if (scopeBar) scopeBar.querySelectorAll('[role=tab]').forEach(function (t) {
    t.onclick = function () { setScope(t.dataset.scope); };
  });
  d.addEventListener('keydown', function (e) {
    if (!overlay.hidden && e.key === 'Escape') { closeSearch(); return; }
    var tag = (e.target.tagName || '').toLowerCase();
    var typing = tag === 'input' || tag === 'textarea' || e.target.isContentEditable;
    if (overlay.hidden && !typing && e.key === '/') { e.preventDefault(); openSearch(); return; }
    if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'k') { e.preventDefault(); overlay.hidden ? openSearch() : closeSearch(); }
  });
})();
