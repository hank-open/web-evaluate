---
name: web-evaluate
version: 1.1.0
description: |
  Web 端页面性能评估与优化建议。分析目标 URL 的 Core Web Vitals、
  资源加载、渲染阻塞、JS/CSS 体积、缓存策略等，生成可执行的优化报告（Markdown 或 HTML 格式）。
  Use when: "性能评估", "页面优化", "web vitals", "加载慢", "性能诊断",
  "LCP", "FID", "CLS", "TTI", "bundle size", "performance audit",
  "生成性能报告", "html 报告", "markdown 报告".
  Voice triggers: "帮我评估页面性能", "页面加载太慢", "web performance audit", "生成性能报告".
triggers:
  - web 性能评估
  - 页面性能诊断
  - web performance audit
  - core web vitals
  - 页面优化建议
  - 生成性能报告
  - html 性能报告
allowed-tools:
  - Bash
  - Read
  - Write
  - WebFetch
  - AskUserQuestion
---

# /web-evaluate

Web 端页面性能全面评估与优化建议 skill。

---

## 工作流

### Phase 0: 收集目标信息

通过 AskUserQuestion 收集：

1. **目标 URL** — 要评估的页面地址
2. **设备类型** — Mobile / Desktop / 两者
3. **评估重点** — 全面诊断 / 加载速度 / 渲染性能 / 资源优化 / 缓存策略

**STOP**，等待用户回答后继续。

---

### Phase 1: 环境探测

```bash
# 检测项目类型（如在项目目录下运行）
_PROJ_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "standalone")
echo "PROJECT_ROOT: $_PROJ_ROOT"

# 检查是否有 package.json 判断前端框架
if [ -f "$_PROJ_ROOT/package.json" ]; then
  cat "$_PROJ_ROOT/package.json" | grep -E '"(react|vue|next|nuxt|vite|webpack|name|version)"' | head -10
fi

# 检查 browse 工具
_ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
B=""
[ -n "$_ROOT" ] && [ -x "$_ROOT/.claude/skills/gstack/browse/dist/browse" ] && B="$_ROOT/.claude/skills/gstack/browse/dist/browse"
[ -z "$B" ] && B="$HOME/.claude/skills/gstack/browse/dist/browse"
[ -x "$B" ] && echo "BROWSE_READY: $B" || echo "BROWSE_NOT_AVAILABLE"
```

---

### Phase 2: 性能数据采集

根据用户提供的 URL，执行以下采集步骤（每项均输出结构化数据）：

#### 2.1 HTTP 头信息分析

```bash
TARGET_URL="<用户输入的URL>"

# 获取响应头
curl -I -L --max-time 10 -s "$TARGET_URL" | head -30

# 测量首字节时间 TTFB
curl -o /dev/null -s -w "TTFB: %{time_starttransfer}s\nTotal: %{time_total}s\nDNS: %{time_namelookup}s\nConnect: %{time_connect}s\nTLS: %{time_appconnect}s\nSize: %{size_download} bytes\nStatus: %{http_code}\n" "$TARGET_URL"
```

#### 2.2 资源清单抓取

用 WebFetch 抓取页面 HTML，分析：
- `<script>` 标签数量和 `async`/`defer` 使用情况
- `<link rel="stylesheet">` 数量
- `<img>` 标签是否有 `loading="lazy"` 和 `width`/`height` 属性
- `<link rel="preload">` / `<link rel="prefetch">` 使用情况
- `<meta>` viewport 配置
- 是否有第三方脚本（广告、分析、聊天工具）

#### 2.3 响应头缓存分析

从 curl 响应头中提取：
- `Cache-Control` / `Expires` 策略
- `ETag` / `Last-Modified` 验证缓存
- `Content-Encoding`（gzip/br 压缩）
- `Content-Security-Policy`
- HTTP 版本（HTTP/1.1 vs HTTP/2 vs HTTP/3）

---

### Phase 3: 性能指标评分

根据采集到的数据，对以下 Core Web Vitals 和关键指标进行评分：

| 指标 | 含义 | Good | Needs Improvement | Poor |
|------|------|------|-------------------|------|
| **LCP** (最大内容绘制) | 主要内容加载速度 | ≤2.5s | 2.5–4s | >4s |
| **FID/INP** (交互延迟) | 首次输入响应 | ≤100ms | 100–300ms | >300ms |
| **CLS** (累计布局偏移) | 视觉稳定性 | ≤0.1 | 0.1–0.25 | >0.25 |
| **TTFB** (首字节时间) | 服务器响应 | ≤800ms | 800ms–1.8s | >1.8s |
| **FCP** (首次内容绘制) | 首屏出现时间 | ≤1.8s | 1.8–3s | >3s |
| **TTI** (可交互时间) | 完全可交互 | ≤3.8s | 3.8–7.3s | >7.3s |

评分输出格式：
```
SCORE CARD:
  TTFB:    [GOOD/WARN/POOR] Xms
  压缩:    [ON/OFF] gzip/br/none
  HTTP版本:[HTTP/1.1|HTTP/2|HTTP/3]
  缓存:    [CONFIGURED/MISSING]
  图片懒加载: [YES/NO/PARTIAL]
  脚本优化: [GOOD/WARN/POOR] (async/defer使用率)
  第三方脚本: [X个] (风险提示)
```

---

### Phase 4: 问题诊断与优化建议

针对每个发现的问题，输出标准化建议条目：

```
[CRITICAL] 问题标题
  现状: 具体描述（数字/比例）
  影响: 对用户体验的实际影响
  修复: 具体可执行的代码或配置方案
  预期收益: 优化后预计提升幅度

[WARNING] 问题标题
  ...

[INFO] 问题标题
  ...
```

优化建议覆盖以下维度：

#### 加载性能
- **减少渲染阻塞资源** — CSS 内联关键路径，非关键 CSS 异步加载
- **JavaScript 优化** — Tree-shaking、Code Splitting、动态 import()
- **图片优化** — WebP/AVIF 格式、响应式图片 `srcset`、懒加载
- **字体优化** — `font-display: swap`、预加载关键字体
- **预加载关键资源** — `<link rel="preload">` 用于 LCP 元素

#### 网络优化
- **HTTP/2 或 HTTP/3** — 多路复用，减少连接开销
- **CDN 部署** — 静态资源就近分发
- **压缩** — Brotli 压缩（比 gzip 效率高 15–25%）
- **缓存策略** — 静态资源长期缓存 + 内容哈希
- **DNS 预解析** — `<link rel="dns-prefetch">` 第三方域名

#### 渲染性能
- **避免强制同步布局** — 批量读写 DOM
- **减少主线程阻塞** — Web Workers 处理计算密集任务
- **虚拟滚动** — 长列表使用虚拟化
- **CSS 动画** — 使用 `transform`/`opacity` 触发 GPU 加速

#### Bundle 优化（如为前端项目）
- **Bundle 分析** — 可视化依赖树（webpack-bundle-analyzer / rollup-plugin-visualizer）
- **依赖去重** — 检查重复引入的 polyfill 或工具库
- **按需引入** — UI 组件库 tree-shaking 配置
- **压缩工具** — Terser / esbuild minify

---

### Phase 5: 生成优化报告

首先询问用户偏好的报告格式（若用户在命令中已指定格式则跳过询问）：

通过 AskUserQuestion 询问：
- A) Markdown 报告（.md）— 适合存档、版本控制、粘贴到文档
- B) HTML 报告（.html）— 可视化仪表盘，浏览器直接打开，含进度条和颜色评级
- C) 两者都生成

```bash
REPORT_DIR="$HOME/.gstack/web-evaluate"
mkdir -p "$REPORT_DIR"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
MD_FILE="$REPORT_DIR/report-$TIMESTAMP.md"
HTML_FILE="$REPORT_DIR/report-$TIMESTAMP.html"
```

#### Markdown 报告结构

```markdown
# Web 性能评估报告

**目标 URL:** {url}
**评估时间:** {datetime}
**设备类型:** {mobile/desktop}
**项目识别:** {framework}

## 执行摘要

总体评分: X/100
核心问题: N 个 CRITICAL，M 个 WARNING，K 个 INFO

## SCORE CARD

TTFB / 压缩 / HTTP版本 / 缓存 / 脚本优化 / 第三方脚本

## 资源加载总览

| 资源 | 原始大小 | 传输大小 | 压缩比 |
...

## Core Web Vitals 估算

| 指标 | 估算值 | 评级 |
...

## 详细诊断

### CRITICAL 问题（含修复代码）
### WARNING 问题
### INFO

## 优化优先级路线图

### 第一阶段（1–2天，收益最高）
### 第二阶段（3–5天）
### 第三阶段（1–2周）

## 参考资源
```

#### HTML 报告结构

HTML 报告为单文件自包含（无外部依赖），包含：
- **头部仪表盘** — 总分圆形进度条（SVG），CRITICAL/WARNING/INFO 计数徽章
- **Score Card 网格** — 每个指标卡片显示颜色评级（绿/黄/红）+ 图标
- **资源瀑布图** — 横向条形图展示各 chunk 大小（原始 vs 传输）
- **Core Web Vitals 卡片** — 彩色仪表盘显示各指标状态
- **问题列表** — 可折叠的 accordion，CRITICAL 默认展开，含代码块
- **路线图时间轴** — 三阶段竖向时间轴
- **样式** — 内联 CSS，深色/亮色主题，打印友好

生成 HTML 后自动在浏览器打开：
```bash
open "$HTML_FILE"
```

告知用户报告路径：
- Markdown: `报告已保存到: {MD_FILE}`
- HTML: `报告已保存到: {HTML_FILE}（已在浏览器打开）`

---

### Phase 6: 交互式深入分析（可选）

通过 AskUserQuestion 询问用户是否需要对某个问题深入分析：

- **图片优化** — 提供具体图片压缩和格式转换的 shell 脚本
- **Bundle 分析** — 根据项目框架提供具体 webpack/vite 配置
- **缓存配置** — 生成 Nginx / Caddy / Vercel 的缓存头配置
- **服务器端渲染** — 评估是否适合 SSR/SSG 迁移
- **监控接入** — 接入 Web Vitals 实时监控的代码方案

**STOP**，等待用户选择后提供对应的详细方案。

---

## 评分算法

总分 = 加权平均各维度得分（满分 100）

| 维度 | 权重 |
|------|------|
| 加载速度 (TTFB + FCP + LCP) | 35% |
| 交互响应 (FID/INP + TTI) | 25% |
| 视觉稳定性 (CLS) | 20% |
| 网络优化 (压缩 + 缓存 + HTTP版本) | 20% |

等级：
- 90–100: 优秀 (green)
- 75–89:  良好 (yellow)
- 60–74:  待改进 (orange)
- 0–59:   较差 (red)

---

## 局限性说明

此 skill 基于静态 HTTP 分析，无法测量：
- 真实用户的 JavaScript 执行时间（需 RUM 工具）
- 动态渲染内容的 CLS（需浏览器运行时）
- 精确的 LCP 元素识别（需 browse 工具配合）

如需精确的实验室数据，建议配合 `/benchmark` skill 或使用 [PageSpeed Insights](https://pagespeed.web.dev/) 进行完整测量。
