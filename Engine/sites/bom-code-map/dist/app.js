(() => {
  'use strict';
  const {files,lanes,journeys}=window.ATLAS;
  const $=id=>document.getElementById(id);
  const ids=Object.keys(files);
  let selected='yard',mode='explore',step=0,timer=null;
  const escape=s=>String(s).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  $('lanes').innerHTML=lanes.map((lane,i)=>`<section class="lane" aria-label="${escape(lane.name)}"><div class="lane-label"><b>0${i+1}</b>${escape(lane.name)}</div><div class="nodes">${lane.files.map(id=>{const f=files[id];return `<button class="node" data-file="${id}" aria-pressed="false"><span class="node-name">${id}.odin</span><span class="node-role">${f.role}</span><span class="node-meta"><span>${f.lines} L</span><span class="node-bar"><i style="width:${f.lines/439*100}%"></i></span></span></button>`}).join('')}</div></section>`).join('');
  function stop(){if(timer)clearInterval(timer);timer=null;$('play').textContent='Play path'}
  function select(id,{scroll=false}={}){
    selected=id;
    const f=files[id];
    const focus=mode==='explore'?[selected,...f.related]:journeys[mode].steps[step].focus;
    document.querySelectorAll('.node').forEach(n=>{const key=n.dataset.file;n.classList.toggle('selected',key===id);n.classList.toggle('related',key!==id&&focus.includes(key));n.classList.toggle('dim',!focus.includes(key));n.setAttribute('aria-pressed',String(key===id))});
    $('inspector').innerHTML=`<div class="file-top"><span>FILE / ${f.role.toUpperCase()}</span><span class="file-number">${String(ids.indexOf(id)+1).padStart(2,'0')} / 15</span></div><h2>${id}.odin</h2><p class="file-tagline">${f.tag}</p><p class="file-description">${f.description}</p><p class="detail-label">HOW IT WORKS</p><ol class="steps">${f.steps.map(s=>`<li>${s}</li>`).join('')}</ol><p class="detail-label">KEY FUNCTIONS</p><div class="related-links">${f.functions.map(s=>`<code class="related-link">${s}()</code>`).join('')}</div><p class="detail-label">FITS TOGETHER WITH</p><div class="related-links">${f.related.map(key=>`<button class="related-link" data-related="${key}">${key} ↗</button>`).join('')}</div><details><summary>Look inside · ${f.lines} lines</summary><pre><code>${escape(f.source||'')}</code></pre><p class="source-location">src/${id}.odin${f.sourceLine?':'+f.sourceLine:''} · source excerpt</p></details>`;
    $('inspector').querySelectorAll('[data-related]').forEach(b=>b.addEventListener('click',()=>{setMode('explore',false);select(b.dataset.related)}));
    requestAnimationFrame(drawWires);
    if(scroll&&matchMedia('(max-width:850px)').matches)$('inspector').scrollIntoView({behavior:matchMedia('(prefers-reduced-motion:reduce)').matches?'instant':'smooth',block:'start'});
  }
  function drawWires(){
    const map=$('map'),rect=map.getBoundingClientRect();
    const get=id=>document.querySelector(`.node[data-file="${id}"]`).getBoundingClientRect();
    const start=get(selected),sx=start.left+start.width/2-rect.left,sy=start.top+start.height/2-rect.top;
    const targets=mode==='explore'?files[selected].related:journeys[mode].steps[step].focus.filter(x=>x!==selected);
    $('wires').setAttribute('viewBox',`0 0 ${rect.width} ${rect.height}`);
    $('wires').innerHTML=targets.map(id=>{const r=get(id),x=r.left+r.width/2-rect.left,y=r.top+r.height/2-rect.top;return `<path class="wire" d="M ${sx} ${sy} C ${sx} ${(sy+y)/2}, ${x} ${(sy+y)/2}, ${x} ${y}"/>`}).join('');
  }
  function renderStep(){
    const journey=journeys[mode],s=journey.steps[step];
    $('journey-count').textContent=`${journey.label} / ${String(step+1).padStart(2,'0')} OF ${String(journey.steps.length).padStart(2,'0')}`;
    $('journey-title').textContent=s.title;$('journey-copy').textContent=s.copy;
    $('prev').disabled=step===0;$('next').disabled=step===journey.steps.length-1;
    $('progress').innerHTML=journey.steps.map((s,i)=>`<button class="${i<step?'complete':i===step?'current':''}" aria-label="Step ${i+1}: ${escape(s.title)}" ${i===step?'aria-current="step"':''} data-step="${i}"></button>`).join('');
    $('progress').querySelectorAll('button').forEach(b=>b.addEventListener('click',()=>{stop();step=Number(b.dataset.step);renderStep()}));
    select(s.file);
  }
  function setMode(next,render=true){stop();mode=next;step=0;document.querySelectorAll('.mode').forEach(b=>{b.classList.toggle('active',b.dataset.mode===mode);b.setAttribute('aria-pressed',String(b.dataset.mode===mode))});$('journey').hidden=mode==='explore';$('map-hint').textContent=mode==='explore'?'Select a file to follow its connections':'Highlighted files take part in this step';if(render){if(mode==='explore')select(selected);else renderStep()}}
  document.querySelectorAll('.mode').forEach(b=>b.addEventListener('click',()=>setMode(b.dataset.mode)));
  document.querySelectorAll('.node').forEach(b=>b.addEventListener('click',()=>{setMode('explore',false);select(b.dataset.file,{scroll:true})}));
  $('prev').addEventListener('click',()=>{stop();if(step>0){step--;renderStep()}});
  $('next').addEventListener('click',()=>{stop();if(step<journeys[mode].steps.length-1){step++;renderStep()}});
  $('play').addEventListener('click',()=>{if(timer){stop();return}if(step===journeys[mode].steps.length-1){step=0;renderStep()}$('play').textContent='Pause';timer=setInterval(()=>{if(step<journeys[mode].steps.length-1){step++;renderStep()}else stop()},4500)});
  document.addEventListener('visibilitychange',()=>{if(document.hidden)stop()});
  new ResizeObserver(()=>requestAnimationFrame(drawWires)).observe($('map'));
  select(selected);
})();
