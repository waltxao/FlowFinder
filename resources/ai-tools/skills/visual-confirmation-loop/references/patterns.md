# 可视化确认骨架

所有骨架遵循同一条硬规则：**根节点只存激活态（`data-active-*`），控件才存选项值（`data-*`）**。这样 `closest()` 不会误命中根节点。

## 1. 开关式对比稿

适用于同一画布切换 A/B/C 或 A1/A2/A3。控制组可以多，但本轮只问一个轴。

```html
<div id="cmp" data-active-model="a" data-active-seam="fillet">
  <div class="cmp-controls">
    <div role="group" aria-label="模型">
      <button type="button" data-model="a" aria-pressed="true">A 焊死式</button>
      <button type="button" data-model="b" aria-pressed="false">B 悬浮胶囊</button>
    </div>
    <div role="group" aria-label="接缝变体">
      <button type="button" data-seam="fillet" aria-pressed="true">A1 内凹</button>
      <button type="button" data-seam="soft" aria-pressed="false">A2 柔和</button>
      <button type="button" data-seam="gap" aria-pressed="false">A3 微缝</button>
    </div>
  </div>

  <div class="cmp-frame" style="width:1060px;max-width:100%;height:260px">
    <div class="cmp-tabs">
      <div class="cmp-tab active">Documents</div>
      <div class="cmp-tab">项目</div>
      <div class="cmp-tab">下载</div>
    </div>
    <div class="cmp-card">内容区</div>
    <span class="cmp-scale">1:1 · 1060×700（此处截取顶栏）</span>
  </div>

  <p class="cmp-caption" data-caption>选择模型后，再确认接缝变体。</p>
</div>

<style>
  #cmp { --bg:#1c1c1e; --card:#2c2c2e; --text:#f2f2f7; --muted:#8e8e93; --gap:0px; }
  #cmp[data-active-model="b"] { --card:#3a3a3c; --gap:5px; }
  #cmp .cmp-frame { position:relative; background:var(--bg); border-radius:12px; overflow:hidden; }
  #cmp .cmp-tabs { display:flex; gap:var(--gap); padding:16px 24px 0; }
  #cmp .cmp-tab { padding:8px 14px; border-radius:9px 9px 0 0; color:var(--muted); font-size:13px; }
  #cmp .cmp-tab.active { background:var(--card); color:var(--text); }
  #cmp[data-active-seam="soft"] .cmp-tab.active { box-shadow:0 2px 6px rgb(0 0 0 / .35); }
  #cmp[data-active-seam="gap"] .cmp-tab.active { margin-bottom:3px; box-shadow:0 2px 8px rgb(0 0 0 / .4); }
  #cmp .cmp-card { min-height:150px; background:var(--card); color:var(--text); padding:16px 24px; }
  #cmp .cmp-scale { position:absolute; right:10px; bottom:8px; font-size:10px; color:var(--muted); }
  #cmp .cmp-controls { display:flex; gap:12px; flex-wrap:wrap; margin-bottom:10px; }
  #cmp button[aria-pressed="true"] { outline:2px solid #0a84ff; outline-offset:1px; }
</style>

<script>
  (() => {
    const root = document.getElementById('cmp');
    root.addEventListener('click', (event) => {
      const modelBtn = event.target.closest('button[data-model]');
      if (modelBtn) {
        root.dataset.activeModel = modelBtn.dataset.model;
        root.querySelectorAll('button[data-model]').forEach((btn) => {
          btn.setAttribute('aria-pressed', String(btn === modelBtn));
        });
        return;
      }
      const seamBtn = event.target.closest('button[data-seam]');
      if (seamBtn) {
        root.dataset.activeSeam = seamBtn.dataset.seam;
        root.querySelectorAll('button[data-seam]').forEach((btn) => {
          btn.setAttribute('aria-pressed', String(btn === seamBtn));
        });
      }
    });
  })();
</script>
```

CSS 必须用 `#cmp[data-active-model="b"]` 这类选择器。不要写 `[data-model="b"]`，否则根节点和按钮可能同时命中。

## 2. 编号解剖图

每个争议部位一个编号和一个图例按钮；点击图例高亮元素。适合顶栏、工具栏、详情栏这类元素多且拥挤的区域。

```html
<div id="anatomy">
  <div class="bar">
    <span class="part" data-part="traffic">●●●</span>
    <button class="part" type="button" data-part="toggle">☰</button>
    <span class="part tab" data-part="tab">Documents</span>
    <span class="part" data-part="seam">接缝</span>
  </div>
  <ul class="legend">
    <li><button type="button" data-part="traffic" aria-pressed="false"><b>1</b> 红绿灯</button></li>
    <li><button type="button" data-part="toggle" aria-pressed="false"><b>2</b> 侧栏开关</button></li>
    <li><button type="button" data-part="tab" aria-pressed="false"><b>3</b> 标签本体</button></li>
    <li><button type="button" data-part="seam" aria-pressed="false"><b>4</b> 标签/卡片接缝</button></li>
  </ul>
</div>

<style>
  #anatomy .bar { position:relative; display:flex; align-items:center; gap:8px; height:44px; padding:0 16px; background:#1c1c1e; color:#f2f2f7; }
  #anatomy .part { outline:0 solid transparent; }
  #anatomy .part.is-target { outline:2px solid #ff9f0a; outline-offset:2px; }
  #anatomy .legend { display:grid; grid-template-columns:repeat(4,minmax(0,1fr)); gap:6px; padding:0; list-style:none; }
  #anatomy .legend button[aria-pressed="true"] { border-color:#ff9f0a; }
</style>

<script>
  (() => {
    const root = document.getElementById('anatomy');
    root.addEventListener('click', (event) => {
      const btn = event.target.closest('button[data-part]');
      if (!btn) return;
      const name = btn.dataset.part;
      root.querySelectorAll('.part').forEach((el) => {
        el.classList.toggle('is-target', el.dataset.part === name);
      });
      root.querySelectorAll('button[data-part]').forEach((b) => {
        b.setAttribute('aria-pressed', String(b === btn));
      });
    });
  })();
</script>
```

图例按钮和展示元素共用 `data-part` 值是可以的，因为它们不在同一个事件查询路径上；不要用 `closest('[data-part]')` 然后直接改状态，先限定 `button[data-part]`。

## 3. 中心线与 Δ 标注

用绝对定位虚线表示基准线，用公式实时算中心差。适合红绿灯、图标、标签文字是否共用中线，或左右面板接缝是否对齐。

```html
<div id="align" style="position:relative;width:520px;height:120px;background:#1c1c1e">
  <div class="centerline target" style="top:34px"></div>
  <div class="centerline current" id="currentLine" style="top:34px"></div>
  <div class="dot" style="position:absolute;left:24px;top:28px;width:12px;height:12px;border-radius:50%;background:#ff453a"></div>
  <span id="delta" style="position:absolute;left:48px;top:18px;color:#30d158;font:11px/1.4 -apple-system">Δ 0pt · 对齐</span>
  <input id="offset" type="range" min="-6" max="6" step="1" value="0" style="position:absolute;left:16px;bottom:12px;width:200px">
</div>

<style>
  #align .centerline { position:absolute; left:0; right:0; border-top:1px dashed; }
  #align .centerline.target { border-color:rgb(255 159 10 / .7); }
  #align .centerline.current { border-color:rgb(48 209 88 / .7); }
</style>

<script>
  (() => {
    const root = document.getElementById('align');
    const dot = root.querySelector('.dot');
    const offset = document.getElementById('offset');
    const delta = document.getElementById('delta');
    const currentLine = document.getElementById('currentLine');
    const targetCenter = 34;
    const dotCenterBase = 28 + 6;

    function render() {
      const shift = Number(offset.value);
      const center = dotCenterBase + shift;
      dot.style.top = (center - 6) + 'px';
      currentLine.style.top = center + 'px';
      const d = center - targetCenter;
      delta.textContent = d === 0 ? 'Δ 0pt · 对齐' : 'Δ ' + Math.abs(d) + 'pt · ' + (d > 0 ? '偏低' : '偏高');
      delta.style.color = d === 0 ? '#30d158' : '#ff9f0a';
    }
    offset.addEventListener('input', render);
    render();
  })();
</script>
```

规则：Δ 用真实单位（pt/px），不要只写“有点偏”；基准线必须来自真实布局值，不能目测。

## 4. 发送前自测脚本

在浏览器控制台或可视化页面内执行，逐个点击控件并断言根节点状态变化。任何 `ok: false` 都说明该控件没有生效。

```js
(async () => {
  const root = document.querySelector('[data-active-model]');
  const buttons = [...root.querySelectorAll('button[data-model], button[data-seam], button[data-mode]')];
  const results = [];
  for (const btn of buttons) {
    btn.click();
    await new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)));
    const axis = btn.dataset.model ? 'model' : btn.dataset.seam ? 'seam' : 'mode';
    const key = 'active' + axis[0].toUpperCase() + axis.slice(1);
    const actual = root.dataset[key];
    results.push({
      label: btn.textContent.trim(),
      axis,
      expected: btn.dataset[axis],
      actual,
      ok: actual === btn.dataset[axis],
    });
  }
  console.table(results);
  if (results.some((r) => !r.ok)) throw new Error('存在未生效的控件');
})();
```

补充两项人工检查：

1. 点控件里的 SVG 或文字，而不是只点按钮空白处。
2. 切换后截图对比，确认可见样式真的变化，而不只是 `aria-pressed` 变了。
