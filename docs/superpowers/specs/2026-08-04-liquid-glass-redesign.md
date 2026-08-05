# FlowFinder 液态玻璃视觉重设计（v0.7.2）

> 日期：2026-08-04
> 版本：v0.7.1 → v0.7.2
> 状态：已批准
> 范围：Swift & AppKit 侧玻璃材质令牌与 FFGlassView 重写
> 参考：Apple "Liquid Glass" 设计规范（WWDC25 Session 219 "Liquid Glass everywhere"）

## 背景与问题

v0.7.1 三轮修复后用户反馈「液态玻璃效果涉及到的界面都不太符合预期」「没有浮动在操作区上方的玻璃效果」。经精读代码确认根因：当前 FFGlassView 把液态玻璃越做越像普通亚克力磨砂——
- tint 涂层 0.25/0.35 alpha 把玻璃整片染色，掩盖了原生 NSGlassEffectView 的动态透明特性
- 噪声平铺 4%/5.5% alpha 在玻璃上加杂色（液态玻璃是平滑材质，不应有噪点）
- 顶部高光 0.5pt 太细，没有"被光照射的边缘"柔光感
- 描边 1pt 太细 + alpha 不够，玻璃边界不清晰
- 浮层与嵌入式元素用同一套阴影参数，浮层显不出"浮起"

## 设计原则（Apple Liquid Glass）

1. **不透明度跟随内容**：液态玻璃应让下方内容"模糊地透出来"，不应用 tint 整片染色。原生 NSGlassEffectView 自身已有动态模糊，tint 仅作"弱苍白化"提高文字可读
2. **平滑材质，不叠噪声**：液态玻璃是平滑的，杂色噪点是亚克力磨砂的设计，移除
3. **顶部柔光**：被光照射的边缘感，1pt 宽、alpha 0.18~0.22 的柔和白光（不是 0.5pt 细硬线）
4. **"磨边"亮线**：1.75pt 宽的边缘反光，像被磨光的玻璃边缘
5. **分级阴影**：浮层（详情栏/工具面板/设备栏）有外阴影显"浮起"；嵌入式小元素（搜索框/卡片）贴在已有玻璃上不浮起，无外阴影
6. **分级样式**：浮层用 NSGlassEffectView.Style.regular（标准液态玻璃有厚度感）；嵌入式小元素用 .clear（轻盈半浮）
7. **分级描边**：浮层用强亮描边显眼，嵌入式用弱亮描边不突兀

## 令牌重设计（DesignTokens.swift / FFDesign.Glass）

| 参数 | 旧值 | 新值 | 说明 |
|---|---|---|---|
| noiseAlphaLight/Dark | 0.040 / 0.055 | **0** / **0** | 液态玻璃不叠噪声 |
| highlightInset | 0.5 | **1** | 1pt 宽柔光（替代 0.5pt 细硬线） |
| highlightAlphaLight/Dark | 0.15 / 0.06 | **0.22** / **0.10** | 柔光更可见 |
| innerShadowAlphaLight/Dark | 0.10 / 0.25 | **0.06** / **0.18** | 液态玻璃自身有厚度，内阴影减量 |
| tintLight | white 0.25 | **white 0.10** | 极淡苍白化，让原生玻璃材质透出 |
| tintDark | black 0.35 | **black 0.18** | 微暗 |
| cornerRadiusPanel | 16 | **14** | 浮层圆角略收敛（更精致） |
| cornerRadiusComponent | 10 | 10 | 不变 |
| borderLight / borderDark | white 0.70 / 0.22 | **white 0.65 / 0.20** | 略降，因宽度增大补偿 |
| borderWidth | 1（隐含） | **1.75** | "磨边"反光更明显 |
| borderLightComponent / Dark | （共用 panel） | **white 0.45 / 0.14** | 嵌入式描边弱化 |
| shadowOpacity / Radius / Offset（panel） | 0.28 / 8 / 3 | **0.30 / 14 / 6** | 浮层明显浮起 |
| shadowOpacity / Radius / Offset（component） | （同 panel） | **0 / 0 / (0,0)** | 嵌入式无外阴影 |

## FFGlassView 重写要点

- **移除 noiseLayer 叠加**：setupPanelGlass/setupComponentGlass 不再 `addSublayer(noise)`（保留 `noiseLayer` 属性兼容 refreshAppearance，但不再加载实际噪声 texture）
- **分级阴影**：setup() 与 updateSublayerFrames() 均按 `level == .panel` / `.component` 应用不同 shadow 参数
- **分级描边**：makeBorderLayer() 按 level 选 `FFDesign.glassBorder`（panel）/ `glassBorderComponent`（component）；lineWidth 用 `FFDesign.Glass.borderWidth`（1.75pt）
- **装饰层 frame 只更新 tint**（噪声层已不加载）
- **border 路径偏移**：用 `borderWidth / 2`，替代硬编码 0.5
- **refreshAppearance 分级刷新**：borderLayer.strokeColor 按分级取色；移除 noiseLayer 刷新

## 改动文件清单

| 文件 | 改动 |
|---|---|
| `UI/DesignTokens.swift` | 令牌重设计（噪声置零、柔光、宽描边、分级阴影/描边、降 tint） |
| `UI/FFGlassView.swift` | setup 分级阴影；setupPanelGlass/Component 移除 noiseLayer；makeBorderLayer 分级；updateSublayerFrames 分级阴影 + border 偏移；refreshAppearance 分级描边 |

## 分级语义（API 使用指南）

- **panel**：浮起、有外部阴影、强亮描边、`.regular` style → 详情栏、工具面板、设备栏、toolBar
- **component**：嵌入式、无外阴影、弱亮描边、`.clear` style → 搜索框、工具卡片、设置分区卡片、SMB 卡片、TaskBar、颜色选择器

## 验证方式

1. 编译 Debug build，运行 App
2. 主窗口：详情栏 / 工具面板 / 设备栏应明显"浮在文件列表上方"（有 14pt radius 外阴影 + 1.75pt 强亮描边 + 枇淡 tint 让背景模糊透出）
3. 嵌入式元素（搜索框、工具卡片）应"贴在已有玻璃之上"，边界清晰但不浮起（无外阴影 + 弱亮描边）
4. 主题深浅色切换：玻璃材质应平滑适配，无反转、无亮色块