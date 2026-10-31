# Agent Note: Native popover background material

Status: implemented

## Problem

面板的外层实色底板遮住了桌面背景，用户希望在保留白色内容卡片的同时，让卡片之间和四周呈现磨玻璃。

## Decision

外层使用 NSVisualEffectView 的 popover 材质和 behindWindow 混合模式，由系统模糊窗口后方内容并适配外观。材质视图随面板创建和释放，不为材质另建窗口、截图缓存或外观监听器。材料层不参与点击或辅助功能导航。

卡片将原有半透明填充合成在实色系统背景上，维持原来的底色与文字对比度，不让桌面纹理穿透卡片。SwiftUI 的减少透明度环境值启用时，外层回退为系统实色背景。容器已由[无箭头浮动面板](../architecture/2026-10-31-arrowless-panel.md)取代 NSPopover，材质与卡片分层决定继续保留。

## Alternatives considered

- 仅降低整个面板的不透明度：会同时淡化文字和卡片，也不会产生背景模糊。
- 对所有卡片应用材质：不符合保留白色内容区域的需求，容易使密集数值受背景干扰。
- 自行捕获桌面并模糊：增加权限、刷新和资源清理负担，系统材质已能完成目标。

## Consequences

磨玻璃的颜色与强度受桌面内容、系统外观和辅助功能设置影响，不固定为某个灰度。支持原有 macOS 最低版本，不引入新版 Liquid Glass API。

真实 SwiftUI 离屏预览覆盖浅深色、增加对比度和减少透明度回退；离屏缓存无法证明窗口服务器的桌面模糊效果，实际通透程度仍需在桌面上检查。当前材质与预览限制由[界面设计说明](../../../interface-design.md)维护。
