(() => {
  'use strict';
  const D = JSON.parse(document.getElementById('handbook-data').textContent);
  const $ = id => document.getElementById(id);
  const escape = value => String(value).replace(/[&<>"']/g, ch => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[ch]));
  let view = 'walkthrough', caseIndex = 0, topic = 'bodies', recovery = 'split';
  const roleNames = D.roleNames;
  const routes = {
    walkthrough: D.cases.map(c => ({href:'#walkthrough/' + c.id, title:c.short, key:c.id})),
    reference: D.topics.map(t => ({href:'#reference/' + t[0], title:t[1], key:t[0]})),
    work: [{href:'#work/overview', title:'First milestone', key:'overview'}, ...D.roleOrder.map(role => ({href:'#work/' + role, title:roleNames[role], key:role}))]
  };
  function navigation(active) {
    const items = routes[view];
    $('section-nav').setAttribute('aria-label', view === 'walkthrough' ? 'Walkthrough steps' : view === 'reference' ? 'Reference topics' : 'Implementation roles');
    $('section-nav').innerHTML = items.map(x => '<a href="' + x.href + '"' + (x.key === active ? ' aria-current="page"' : '') + '>' + escape(x.title) + '</a>').join('');
    $('mobile-nav').innerHTML = items.map(x => '<option value="' + x.href + '"' + (x.key === active ? ' selected' : '') + '>' + escape(x.title) + '</option>').join('');
    document.querySelectorAll('[data-view]').forEach(el => {
      if (el.dataset.view === view) el.setAttribute('aria-current', 'page');
      else el.removeAttribute('aria-current');
    });
    $('reference-search-box').hidden = view !== 'reference';
    if (view !== 'reference') { $('reference-search').value = ''; $('clear-search').hidden = true; }
    document.body.dataset.view = view;
  }
  function page(content, title) {
    $('page-content').innerHTML = content;
    document.title = title + ' — BOM';
  }
  function route() {
    if (location.hash === '#page-content' || location.hash === '#main') return;
    let parts;
    try { parts = location.hash.slice(1).split('/').map(decodeURIComponent); } catch { parts = []; }
    view = ['walkthrough','reference','work'].includes(parts[0]) ? parts[0] : 'walkthrough';
    if (view === 'walkthrough') {
      const found = D.cases.findIndex(c => c.id === parts[1]);
      caseIndex = found >= 0 ? found : 0;
      navigation(D.cases[caseIndex].id);
      const c = D.cases[caseIndex];
      page(c.id === 'recovery' ? D.recoveryPages[recovery] : D.casePages[c.id], c.title);
    } else if (view === 'reference') {
      $('reference-search').value = ''; $('clear-search').hidden = true;
      if (parts[1] === 'map') {
        if (D.recordPages[parts[2]]) { topic = D.recordTopics[parts[2]]; navigation(topic); page(D.recordPages[parts[2]], parts[2]); }
        else { topic = 'bodies'; navigation(topic); page(D.topicPages[topic], 'Body components'); }
      } else if (parts[1] === 'contracts') {
        topic = D.topicPages[parts[2]] ? parts[2] : 'coordinates';
        navigation(topic); page(D.topicPages[topic], D.topics.find(t => t[0] === topic)[1]);
      } else if (parts[1] === 'rules' && D.rules[parts[2]]) {
        topic = 'rules'; navigation(topic);
        const r = D.rules[parts[2]];
        page('<p class="breadcrumb"><a href="#reference/rules">Rules</a></p><h1>' + escape(r.id + ' — ' + r.title) + '</h1><div class="source-document">' + r.html + '</div>', r.id);
      } else if (parts[1] === 'entry' && D.entries[parts[2]]) {
        const r = D.entries[parts[2]];
        topic = r.kind === 'question' ? 'unresolved' : 'rules'; navigation(topic);
        page('<p class="breadcrumb"><a href="#reference/' + topic + '">' + (r.kind === 'question' ? 'Unresolved details' : 'Rules') + '</a></p><h1>' + escape(r.id + ' — ' + r.title) + '</h1><div class="source-document">' + r.html + '</div>', r.id);
      } else if (parts[1] === 'sources' && D.sources[parts[2]]) {
        topic = 'sources'; navigation(topic);
        const s = D.sources[parts[2]];
        page('<p class="breadcrumb"><a href="#reference/sources">Source documents</a></p><p class="source-download"><button type="button" data-download-source="' + escape(s.name) + '">Download Markdown</button></p><div class="source-document">' + s.html + '</div>', s.name.replace(/\.md$/, ''));
      } else {
        topic = D.topicPages[parts[1]] ? parts[1] : 'bodies';
        navigation(topic); page(D.topicPages[topic], D.topics.find(t => t[0] === topic)[1]);
      }
    } else if (parts[1] === 'overview' || !parts[1]) {
      navigation('overview');
      page(D.workOverview, D.implementation.title);
    } else {
      const t = D.tasks.find(t => t.id === parts[1]);
      const role = t ? t.role : D.roleOrder.includes(parts[1]) ? parts[1] : 'simulation';
      navigation(role);
      page(t ? D.taskPages[t.id] : D.rolePages[role], t ? t.title : roleNames[role]);
    }
  }
  function search() {
    const q = $('reference-search').value.trim().toLowerCase();
    $('clear-search').hidden = !q;
    if (!q) { route(); return; }
    const records = Object.values(D.records).filter(r => (r.title + ' ' + r.status + ' ' + r.fields.map(f => f.text).join(' ')).toLowerCase().includes(q));
    const entries = Object.values(D.entries).filter(r => (r.kind !== 'decision' || q.startsWith('dec-')) && (r.id + ' ' + r.title + ' ' + r.markdown).toLowerCase().includes(q));
    let result = '<h1>Search results</h1><p class="search-count">' + (records.length + entries.length) + ' results for “' + escape($('reference-search').value.trim()) + '”.</p>';
    records.forEach(r => {
      result += '<article class="search-result"><h2><a href="#reference/map/' + encodeURIComponent(r.id) + '">' + escape(r.title) + '</a></h2><p class="result-status">' + escape(r.status) + '</p><p>' + escape(r.fields[0].text) + '</p></article>';
    });
    entries.forEach(r => {
      const target = r.kind === 'rule' ? 'rules' : 'entry';
      const label = r.kind === 'question' ? (r.status === 'Resolved' ? 'Resolved question' : 'Open question') : r.kind === 'decision' ? 'Decision history' : r.status === 'Accepted' ? '' : r.status;
      const snippet = r.markdown.split('\n\n').find(s => !s.startsWith('**')) || '';
      const status = label ? '<p class="result-status">' + escape(label) + '</p>' : '';
      result += '<article class="search-result"><h2><a href="#reference/' + target + '/' + r.id + '">' + escape(r.id + ' — ' + r.title) + '</a></h2>' + status + '<p>' + escape(snippet.slice(0,230)) + '</p></article>';
    });
    if (!records.length && !entries.length) result += '<p>No matching record or rule.</p>';
    page(result, 'Search results');
  }
  function download(name, content) {
    const blob = new Blob([content], {type:'text/markdown;charset=utf-8'});
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a'); a.href = url; a.download = name;
    document.body.appendChild(a); a.click(); a.remove();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
  }
  $('mobile-nav').addEventListener('change', e => { location.hash = e.target.value; });
  $('reference-search').addEventListener('input', search);
  $('clear-search').addEventListener('click', () => { $('reference-search').value = ''; search(); $('reference-search').focus(); });
  document.addEventListener('click', e => {
    const source = e.target.closest('[data-download-source]');
    if (source) download(source.dataset.downloadSource, D.sources[source.dataset.downloadSource].markdown);
    const result = e.target.closest('[data-rebuild]');
    if (result) {
      recovery = result.dataset.rebuild;
      page(D.recoveryPages[recovery], 'Reconstruction');
    }
  });
  document.addEventListener('keydown', e => {
    if (view !== 'walkthrough' || e.altKey || e.ctrlKey || e.metaKey || e.shiftKey || e.target.closest('input,select,textarea,[contenteditable],summary,button')) return;
    if (e.key === 'ArrowRight' && caseIndex < D.cases.length - 1) { e.preventDefault(); location.hash = '#walkthrough/' + D.cases[caseIndex + 1].id; }
    if (e.key === 'ArrowLeft' && caseIndex > 0) { e.preventDefault(); location.hash = '#walkthrough/' + D.cases[caseIndex - 1].id; }
  });
  window.addEventListener('hashchange', () => { route(); window.scrollTo({top:0,behavior:'instant'}); if (location.hash !== '#page-content' && location.hash !== '#main') $('page-content').focus({preventScroll:true}); });
  window.addEventListener('beforeprint', () => document.querySelectorAll('#page-content details').forEach(d => { d.dataset.beforePrint = String(d.open); d.open = true; }));
  window.addEventListener('afterprint', () => document.querySelectorAll('#page-content details[data-before-print]').forEach(d => { d.open = d.dataset.beforePrint === 'true'; delete d.dataset.beforePrint; }));
  route();
})();
