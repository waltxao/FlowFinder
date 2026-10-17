# 历史设计稿索引

> **本目录下的文档已不再具有解释权。**
>
> 2026-10-17 起，需求与规格的解释权移交给：
>
> | 文档 | 作用 |
> |---|---|
> | `docs/PRODUCT.md` | 产品是什么、给谁、不做什么 |
> | `docs/DESIGN-SPEC.md` | 视觉与交互的规格本体 |
> | `docs/ACCEPTANCE.md` | 什么算做对了 |
> | `docs/REQUIREMENTS.md` | 当前版本要交付的需求清单 |
>
> 本目录仅作**追溯**用途。与上表冲突时，以上表为准。

---

## 为什么降权

这 20 份稿子记录了每一轮改了什么，但没有一份定义「什么算改对了」。结果是视觉基准在 18 天内换了 6 次：

```
07-20 完整重构 → 07-22 访达风格 → 07-27 访达重设计
→ 07-28 克隆访达 → 07-29 全面重设计 → 08-04 液态玻璃
```

其中 2026-07-28 把「完全克隆访达」写成硬约束，2026-08-04 又按「要更多液态玻璃」重做——两条本身互斥。两份都留在目录里，于是任何一轮都可以合法地引用其中一份来推翻另一份。

降权不是否定这些工作，而是停止让它们互相打架。

---

## 清单

| 日期 | 文档 | 该轮确立的主要决策 |
|---|---|---|
| 2026-07-18 | `beta-ui-completion-design.md` | 首份规格：文件浏览 / 搜索 / 查重三条路径；复刻原版双面板布局 |
| 2026-07-20 | `complete-rewrite-design.md` | 从 Tauri + React 重构为 Swift/AppKit + Rust |
| 2026-07-22 | `finder-style-ui-redesign.md` | 首次提出仿访达风格 |
| 2026-07-27 | `v0.6.5-finder-redesign-design.md` | 工具栏**双行**布局；操作区 1px 发丝线；选中态访达标准 |
| 2026-07-27 | `v0.6.5-ui-audit-report.md` | 20 个验收问题的巡检记录 |
| 2026-07-28 | `v0.6.6-finder-clone-redesign-design.md` | 「完全克隆访达」；收藏彩色图标且不折叠；药丸列头；设备浮层左下角 |
| 2026-07-29 | `v0.6.7-full-ui-redesign-design.md` | 亚克力侧栏 + 实体操作区材质架构；路径栏完全仿访达；标签读写 xattr |
| 2026-08-01 | `v0.6.9-ui-detail-refinement-design.md` | 超椭圆圆角；**详情栏浮层化**；1px 边框 + divider 0 |
| 2026-08-02 | `round2-fixes-design.md` | 第二轮修复批量 |
| 2026-08-02 | `sqlite-cache-freshness-design.md` | SQLite 缓存新鲜度 |
| 2026-08-02 | `ui-fixes-batch-design.md` | UI 修复批量 |
| 2026-08-03 | `round3-fixes-design.md` | 第三轮修复批量 |
| 2026-08-04 | `liquid-glass-redesign.md` | 液态玻璃视觉重设计（FFGlassView 重写） |
| 2026-08-18 | `quality-polish-batch-design.md` | 质量打磨批量 |
| 2026-08-28 | `divider-handle-glow-follow-design.md` | 分隔条亮线跟随鼠标 |
| 2026-08-29 | `details-bar-redesign-design.md` | 详情栏可调高、三模块可调宽 |
| 2026-08-30 | `native-experience-blueprint.md` | 原生体验四波次（主线程 / 键盘 / 交互 / 视觉） |
| 2026-09-02 | `v0.8.0-sidebar-favorites-redesign-design.md` | 侧栏单一 outline 分区模型、拖拽重排、失效灰显 |
| 2026-10-17 | `v0.8.0-beta-spec.md` | 曾提出移植 ZCode 扁平风、单行工具栏；**该方向已于同日撤销** |
| 2026-10-17 | `v0.8.0-requirements-audit.md` | 首次需求审查（状态列未核对代码，结论已由新文档取代） |

---

## 引用规则

1. 需要追溯「某个决策是哪一轮定的」→ 查本表
2. 需要知道「现在应该怎么做」→ 查 `docs/DESIGN-SPEC.md`
3. 两者冲突时 → 以 `DESIGN-SPEC.md` 为准，并在其 §18 登记变更
