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
})();
