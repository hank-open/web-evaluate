---
name: web-evaluate
version: 1.2.0
description: |
  Web 端页面性能评估与优化建议。分析目标 URL 的 Core Web Vitals、
  资源加载、渲染阻塞、JS/CSS 体积、缓存策略等，生成可执行的优化报告。
  支持 Markdown / HTML 报告格式，历史对比模式，确定性评分公式。
  Use when: "性能评估", "页面优化", "web vitals", "加载慢", "性能诊断",
  "LCP", "FID", "CLS", "TTI", "bundle size", "performance audit",
  "生成性能报告", "html 报告", "markdown 报告", "对比上次".
  Voice triggers: "帮我评估页面性能", "页面加载太慢", "web performance audit", "生成性能报告".
triggers:
  - web 性能评估
  - 页面性能诊断
  - web performance audit
  - core web vitals
  - 页面优化建议
  - 生成性能报告
  - html 性能报告
  - 对比上次评估
allowed-tools:
  - Bash
  - Read
  - Write
  - WebFetch
  - AskUserQuestion
---

# /web-evaluate

Web 端页面性能全面评估与优化建议 skill。

**支持参数：**
```
/web-evaluate <URL> [--mobile] [--desktop] [--html] [--md] [--both] [--quick] [--compare]
```

- `--mobile` / `--desktop`：指定设备类型（默认 desktop）
- `--html` / `--md` / `--both`：指定报告格式（默认询问）
- `--quick`：跳过子资源大小测量，仅做 HTTP 头快速分析
- `--compare`：与上次同 URL 的评估结果对比差异

---

## Phase 0: 智能参数解析

从用户输入中自动提取参数，**已提供的参数跳过交互提问**。

```bash
# 解析逻辑（伪代码，由 AI 执行）
ARGS="<用户输入的完整命令>"

# 1. 提取 URL（以 http/https 开头的片段）
TARGET_URL=$(echo "$ARGS" | grep -oE 'https?://[^ ]+')

# 2. 解析 flags
[[ "$ARGS" == *"--mobile"*  ]] && DEVICE="mobile"   || DEVICE="desktop"
[[ "$ARGS" == *"--html"*   ]] && FORMAT="html"
[[ "$ARGS" == *"--md"*     ]] && FORMAT="md"
[[ "$ARGS" == *"--both"*   ]] && FORMAT="both"
[[ "$ARGS" == *"--quick"*  ]] && MODE="quick"        || MODE="full"
[[ "$ARGS" == *"--compare"*]] && COMPARE="true"      || COMPARE="false"

echo "TARGET_URL: $TARGET_URL"
echo "DEVICE: $DEVICE"
echo "FORMAT: ${FORMAT:-unset}"
echo "MODE: $MODE"
echo "COMPARE: $COMPARE"
```

**只在参数缺失时才提问：**
- 未提供 URL → AskUserQuestion 询问目标地址
- 未提供 `--html/--md/--both` → Phase 5 时询问报告格式
- 其余参数使用默认值，不打断流程

---

## Phase 1: 环境探测

```bash
_PROJ_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "standalone")
echo "PROJECT_ROOT: $_PROJ_ROOT"

if [ -f "$_PROJ_ROOT/package.json" ]; then
  grep -E '"(react|vue|next|nuxt|vite|webpack|name|version)"' "$_PROJ_ROOT/package.json" | head -10
fi

B="$HOME/.claude/skills/gstack/browse/dist/browse"
[ -x "$B" ] && echo "BROWSE_READY: $B" || echo "BROWSE_NOT_AVAILABLE"
```

---

## Phase 2: 性能数据采集

### 2.1 HTTP 指标（必做）

```bash
# 3次 TTFB 采样取平均，排除网络抖动
for i in 1 2 3; do
  curl -o /dev/null -s --max-time 15 \
    -w "Run$i TTFB:%{time_starttransfer} DNS:%{time_namelookup} Connect:%{time_connect} TLS:%{time_appconnect} Total:%{time_total} Size:%{size_download} Status:%{http_code}\n" \
    "$TARGET_URL"
done

# 响应头：缓存 / 压缩 / HTTP 版本
curl -I -L --max-time 10 -s "$TARGET_URL"
```

计算 TTFB 均值，用于 Phase 3 评分。

### 2.2 资源清单（抓取原始 HTML）

```bash
curl -s --max-time 15 "$TARGET_URL"
```

从 HTML 中提取：
- `<script>` 数量，有无 `async`/`defer`/`type="module"`
- `<link rel="stylesheet">` 数量
- `<link rel="modulepreload">` / `<link rel="preload">` 使用情况
- `<img>` 是否有 `loading="lazy"` 和 `width`/`height`
- `<meta name="viewport">` 内容
- 第三方域名脚本数量
- HTML 内联 SVG / 内联 style 大小

### 2.3 子资源大小测量（`--quick` 时跳过）

```bash
# 从 HTML 中提取所有 /assets/*.js 和 /assets/*.css
# 逐一测量原始大小和 gzip 传输大小
for chunk in $CHUNKS; do
  raw=$(curl -I -s --max-time 10 "$BASE$chunk" | grep -i "content-length" | awk '{print $2}' | tr -d '\r')
  gz=$(curl -o /dev/null -s --max-time 20 -H "Accept-Encoding: gzip, deflate, br" -w "%{size_download}" "$BASE$chunk")
  cc=$(curl -I -s --max-time 10 "$BASE$chunk" | grep -i "cache-control" | tr -d '\r')
  echo "$chunk | raw=${raw}B | gz=${gz}B | $cc"
done
```

---

## Phase 2.5: 历史记录对比

历史数据保存路径：`$HOME/.gstack/web-evaluate/history.jsonl`

每条记录格式（单行 JSON）：
```json
{
  "ts": "2026-07-14T15:40:00Z",
  "url": "https://example.com/",
  "ttfb_ms": 881,
  "total_raw_kb": 5205,
  "total_gz_kb": 1259,
  "score": 47,
  "http_version": "2",
  "cache": false,
  "compression": "gzip",
  "critical": 4,
  "warning": 4
}
```

**加载历史并对比（`--compare` 或自动检测同 URL 历史）：**

```bash
HISTORY_FILE="$HOME/.gstack/web-evaluate/history.jsonl"

# 查找同 URL 的最近一条记录
if [ -f "$HISTORY_FILE" ]; then
  PREV=$(grep "\"url\":\"$TARGET_URL\"" "$HISTORY_FILE" | tail -1)
  if [ -n "$PREV" ]; then
    echo "HISTORY_FOUND: $PREV"
  else
    echo "HISTORY_NOT_FOUND"
  fi
fi
```

**若找到历史记录，在报告顶部输出对比表：**

```
┌─────────────────┬──────────────┬──────────────┬──────────────┐
│ 指标             │ 上次 (日期)   │ 本次          │ 变化          │
├─────────────────┼──────────────┼──────────────┼──────────────┤
│ 总评分           │ 47           │ XX           │ ▲/▼ +N       │
│ TTFB            │ 881ms        │ XXXms        │ ▲/▼ ±Xms     │
│ 传输总量         │ 1,259 KB     │ X,XXX KB     │ ▲/▼ ±X KB    │
│ CRITICAL 数      │ 4            │ X            │ ▲/▼ ±N       │
│ 缓存             │ 未配置        │ XX           │              │
└─────────────────┴──────────────┴──────────────┴──────────────┘
```

若无历史记录，本次评估完成后自动保存（无需提示用户）。

**历史写入（每次评估结束时执行）：**

```bash
HISTORY_FILE="$HOME/.gstack/web-evaluate/history.jsonl"
mkdir -p "$(dirname $HISTORY_FILE)"
echo "{\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"url\":\"$TARGET_URL\",\"ttfb_ms\":TTFB,\"total_raw_kb\":RAW_KB,\"total_gz_kb\":GZ_KB,\"score\":SCORE,\"http_version\":\"HTTP_VER\",\"cache\":CACHE_BOOL,\"compression\":\"COMP\",\"critical\":N_CRITICAL,\"warning\":N_WARNING}" \
  >> "$HISTORY_FILE"
```

---

## Phase 3: 确定性评分公式

总分 100 分，各维度独立计算，**分值由明确数值规则决定，不依赖模型判断**。

### 3.1 各维度满分与规则

#### A. 加载速度 — 35 分

**TTFB（15分）**
| TTFB 均值 | 得分 |
|-----------|------|
| ≤ 200ms   | 15   |
| ≤ 500ms   | 12   |
| ≤ 800ms   | 9    |
| ≤ 1200ms  | 5    |
| ≤ 1800ms  | 2    |
| > 1800ms  | 0    |

**FCP 估算（10分）** — 基于 TTFB + 传输大小推算
| FCP 估算  | 得分 |
|-----------|------|
| ≤ 1.8s    | 10   |
| ≤ 3.0s    | 6    |
| ≤ 4.5s    | 3    |
| > 4.5s    | 0    |

FCP 估算公式：`FCP ≈ TTFB + gz_total_kb / 下行速度(10Mbps估算) + JS解析时间估算`  
JS 解析时间估算：`raw_js_mb × 500ms/MB`（Chrome V8 基准）

**LCP 估算（10分）** — SPA 项目 LCP ≈ TTI，公式同上加 JS 执行时间
| LCP 估算  | 得分 |
|-----------|------|
| ≤ 2.5s    | 10   |
| ≤ 4.0s    | 6    |
| ≤ 6.0s    | 3    |
| > 6.0s    | 0    |

#### B. 交互响应 — 25 分

**TTI 估算（15分）** — `TTFB + 传输时间 + JS解析时间`
| TTI 估算  | 得分 |
|-----------|------|
| ≤ 3.8s    | 15   |
| ≤ 5.0s    | 10   |
| ≤ 7.3s    | 5    |
| > 7.3s    | 0    |

**JS Bundle 合理性（10分）**
| JS 总原始大小 | 得分 |
|--------------|------|
| ≤ 500 KB     | 10   |
| ≤ 1 MB       | 7    |
| ≤ 2 MB       | 4    |
| ≤ 4 MB       | 2    |
| > 4 MB       | 0    |

#### C. 视觉稳定性 — 20 分

**CLS（10分）** — 无法静态测量时得 5 分（中立）；若检测到无 img width/height 减 2 分；无 aspect-ratio 减 1 分。

**CSS 体积合理性（10分）**
| CSS 总原始大小 | 得分 |
|---------------|------|
| ≤ 50 KB       | 10   |
| ≤ 150 KB      | 7    |
| ≤ 400 KB      | 4    |
| > 400 KB      | 1    |

#### D. 网络优化 — 20 分

**缓存策略（8分）**
| 情况 | 得分 |
|------|------|
| 静态资源有 `Cache-Control: immutable` 或 `max-age≥31536000` | 8 |
| 有 `Cache-Control` 但 max-age < 1年 | 4 |
| 仅有 `ETag` / `Last-Modified` | 1 |
| 完全无缓存头 | 0 |

**压缩（6分）**
| 情况 | 得分 |
|------|------|
| Brotli (br) | 6 |
| gzip        | 4 |
| 无压缩       | 0 |

**HTTP 版本（4分）**
| 版本 | 得分 |
|------|------|
| HTTP/3 | 4 |
| HTTP/2 | 3 |
| HTTP/1.1 | 0 |

**第三方脚本扣分（上限 -4分）**
- 每个第三方脚本域名 -1 分

### 3.2 评分等级

| 总分     | 等级    | 颜色   |
|----------|---------|--------|
| 90–100   | 优秀    | 🟢 green  |
| 75–89    | 良好    | 🟡 yellow |
| 60–74    | 待改进  | 🟠 orange |
| 0–59     | 较差    | 🔴 red    |

### 3.3 输出明细

评分完成后，**必须逐项列出每维度的得分和扣分原因**：

```
=== 评分明细 ===
A. 加载速度 (35分满分)
   TTFB 881ms           → 5/15
   FCP 估算 ~3s          → 6/10
   LCP 估算 ~4s          → 6/10
   小计: 17/35

B. 交互响应 (25分满分)
   TTI 估算 ~6s          → 5/15
   JS Bundle 5.2MB       → 0/10
   小计: 5/25

C. 视觉稳定性 (20分满分)
   CLS (静态中立)        → 5/10
   CSS 702KB             → 1/10
   小计: 6/20

D. 网络优化 (20分满分)
   缓存: 无 Cache-Control → 0/8
   压缩: gzip            → 4/6
   HTTP/2               → 3/4
   第三方脚本: 0个       → 0扣分
   小计: 7/20  (实际: 7/20)

总分: 17+5+6+7 = 35/100  ← 注：此为示例，实际按真实数据计算
```

---

## Phase 4: 问题诊断与优化建议

针对每个发现的问题，输出标准化建议条目：

```
[CRITICAL] 问题标题
  现状: 具体描述（数字/比例）
  影响: 对用户体验的实际影响（关联哪个评分维度扣了几分）
  修复: 具体可执行的代码或配置方案
  预期收益: 修复后该维度可新增 +N 分，总分预计 +N

[WARNING] 问题标题
  ...

[INFO] 问题标题（不影响评分，但值得关注）
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

## Phase 5: 生成优化报告

若用户未在命令中指定格式（无 `--html`/`--md`/`--both`），通过 AskUserQuestion 询问一次：
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

## 历史对比（若有）

| 指标 | 上次 | 本次 | 变化 |
...

## 评分明细

总分: X/100 — {等级}

| 维度 | 得分 | 满分 |
...（逐项明细）

## SCORE CARD

...

## 资源加载总览

| 资源 | 原始大小 | 传输大小 | 压缩比 |
...

## Core Web Vitals 估算

| 指标 | 估算值 | 评级 | 对应评分 |
...

## 详细诊断

### CRITICAL 问题（含修复代码 + 可新增分值）
### WARNING 问题
### INFO

## 优化优先级路线图

### 第一阶段（1–2天，收益最高，预计 +N 分）
### 第二阶段（3–5天，预计 +N 分）
### 第三阶段（1–2周，预计 +N 分）

## 参考资源
```

#### HTML 报告结构

HTML 报告为单文件自包含（无外部依赖），包含：
- **头部仪表盘** — 总分 SVG 圆形进度条，历史趋势迷你折线图（有历史时显示），CRITICAL/WARNING/INFO 徽章
- **历史对比表** — 有历史记录时显示 delta 行（↑↓ 箭头 + 颜色）
- **评分明细表** — 每个维度的得分/满分/扣分原因
- **Score Card 网格** — 每个指标卡片，颜色评级（绿/黄/红）
- **资源瀑布图** — 横向条形图，原始 vs 传输大小
- **Core Web Vitals 卡片** — 彩色状态卡
- **问题列表** — 可折叠 accordion，CRITICAL 默认展开，含代码块，标注 "+N分" 潜在收益
- **路线图时间轴** — 三阶段，标注每阶段完成后预计总分
- **样式** — 内联 CSS，深色主题，打印友好

生成 HTML 后自动在浏览器打开：
```bash
open "$HTML_FILE"
```

---

## Phase 6: 交互式深入分析（可选）

通过 AskUserQuestion 询问用户是否需要对某个问题深入分析：

- **图片优化** — 提供具体图片压缩和格式转换的 shell 脚本
- **Bundle 分析** — 根据项目框架提供具体 webpack/vite 配置
- **缓存配置** — 生成 Nginx / Caddy / Vercel / Cloudflare 的完整缓存配置
- **服务器端渲染** — 评估是否适合 SSR/SSG 迁移
- **监控接入** — 接入 Web Vitals RUM 监控的代码方案（web-vitals.js）
- **安全头检测** — HSTS / CSP / X-Frame-Options / Referrer-Policy 配置

**STOP**，等待用户选择后提供对应的详细方案。

---

## 局限性说明

此 skill 基于静态 HTTP 分析（curl），无法测量：
- 真实用户的 JavaScript 执行时间（需 RUM 工具）
- 动态渲染内容的 CLS（需浏览器运行时）
- 精确的 LCP 元素识别（需 browse 工具配合）

FCP / LCP / TTI 均为基于网络传输时间 + JS 体积的**估算值**，实际值因设备性能、网络环境差异较大。

如需精确的实验室数据，建议通过 [PageSpeed Insights](https://pagespeed.web.dev/) 进行完整测量，或配合 `/benchmark` skill 使用。
