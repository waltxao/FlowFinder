# Switchable Comparison

## Purpose

对比稿只用于检查，不是确认按钮。它让用户在真实比例和真实状态下看见差异；最终决策来自对话中的那一个问题。

## Contract

- 自包含 HTML：无外部字体、图片、脚本或网络请求。
- 写入宿主指定的可视化输出目录，再用宿主工具呈现。
- 包含「现状」基线 + 2–4 个互斥选项；一轮只回答一个轴。
- 使用真实窗口比例与真实状态：单/双栏、侧栏显示/隐藏、全屏、主题。
- 显示关键数值（中心线、间距、字号、图标尺寸、避让量），不要只给观感。
- 选项标签与提问逐字一致；选中态清晰可见。
- 键盘可操作；按钮使用 `aria-pressed`。
- 不默认选中推荐项；推荐只能在对话里说明。

## Minimum Structure

1. 标题 + 「仅供检查，确认请在对话中回答」提示。
2. 选项控件：现状 / A / B / C。
3. 状态控件：侧栏、单双栏、全屏。
4. 预览 stage：按真实比例渲染。
5. 读数区：当前选项、关键数值、当前状态。
6. 注释：基线、接缝、中心线或避让量。

## Behavioral Variant

行为型取舍在普通结构上增加：

1. 现状行为矩阵：操作 × 当前结果 × 证据（file:line 或运行记录）。
2. 每个选项的操作结果 mock：至少删除、移动、双击/打开；按功能裁剪并标明。
3. 若已有同类控件或确认弹窗，现状区必须并列展示，避免重复控制。
4. 选项标签与提问逐字一致；一轮只测一个行为轴。

## Self-Check Before Presenting

提交给用户前逐项执行：

- [ ] 点击每个选项，stage 有明显变化，选中态同步更新。
- [ ] 每个状态开关在每个选项下都能工作。
- [ ] 事件选择器只作用于控件，例如 `.vc-controls [data-option]`；不要让根节点的 `data-*` 被 `closest` 抢先命中。
- [ ] 无控制台错误、无缺失资源、目标尺寸无溢出。
- [ ] 有过渡动画时，等动画结束再测量/截图；不要把中间态当成 bug。
- [ ] Tab 能聚焦控件，Enter/Space 能触发。
- [ ] 对比稿脱离聊天也能看懂：标签、数值、状态、代价都在页面上。
- [ ] 选项目标与将要提问的标签完全一致。
- [ ] 没有把推荐项默认选中。
- [ ] 行为型：现状矩阵有证据；每个选项都展示各操作结果 mock；没有把「待验」写成结论。

## Known Failure

来源案例中的 A2/A3 无法切换：

```html
<!-- 错误：根节点也有 data-style -->
<div class="vc-app" data-style="weld">
  <button data-style="weld">A1</button>
  <button data-style="soft">A2</button>
</div>
```

```js
// 错误：点击 A2 时 closest 先命中根节点
const style = event.target.closest('[data-style]').dataset.style;
```

修复：把选择器限定在控制区，并校验命中元素属于控件。

```js
const controls = app.querySelector('.vc-controls');
controls.addEventListener('click', (event) => {
  const button = event.target.closest('[data-option]');
  if (!button || !controls.contains(button)) return;
  setOption(button.dataset.option);
});
```

规则：根节点只放状态（如 `data-current-option`），选项按钮才放 `data-option`；不要让两组属性同名。

## Handling Multiple Instances

如果宿主把多个对比稿放在同一页面：

- 用 `.vc-app` 遍历初始化，不要依赖全局唯一 `id`。
- 每个实例的作用域限定在自己的根节点内。
- 不要用 `document.querySelector('[data-option]')` 取第一个匹配。
- 控件事件绑定在实例的 `.vc-controls` 上。

## Fallback

如果宿主没有可视化呈现工具：

1. 生成自包含 HTML 文件，告诉用户路径并请其打开。
2. 或使用带标注的真实截图/线框图，标明数值和基线。
3. 明确说明「当前无法内嵌切换」，不要静默退化成纯文字选项。
4. 如果连截图也不可用，使用代码度量 + 标注 mock，并把像素观感列入人工确认项。

## Template

复制 `assets/comparison-shell.html` 后：

1. 替换选项名称和 stage 内容。
2. 在 `configs` 中改数值，保持现状 + 2–4 个选项。
3. 保留 `.vc-controls` 作用域和 `data-option` 命名。
4. 按 Self-Check 逐项点击，再向用户提问。
5. 一次只改一个轴；下一轮复制模板重新做，不在同一页堆叠多个问题。
6. 作为内联片段使用时，保留 `.vc-app`、`<style>` 和 `<script>`，去掉 `<html>/<head>/<body>` 包装；确认宿主会执行片段中的脚本。
