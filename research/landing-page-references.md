# PortDock 落地页参考调研报告

> Wayfinder 调研 ticket：[调研：同类 macOS 工具落地页参考](https://github.com/LurenKT/PortDock/issues/2)
> 调研时间：2026-07-15。共实际访问 6 个同类工具落地页（逐页抓取）+ 3 篇 GitHub Pages 官方文档，托管方式用 HTTP 响应头（`server` 等字段）独立核对过一轮。页面上引用的下载量/星数等数字均为各站自报，未独立核对。

## 第一部分：参考落地页调研

### 1. Sloth — 与 PortDock 品类最接近（基于 lsof 的开放文件/端口查看器，开源）

URL：https://sveinbjorn.org/sloth

- **分区结构**：导航（作者个人站导航）→ 应用名+图标 → 一段功能描述+特性列表 → 下载区（版本+多种安装方式）→ 三张界面截图 → 页脚。
- **Hero 文案**：无营销式大标题，开头直接一句定位："Sloth is a native Mac app that shows all open files and sockets in use by all running processes on your system."（和 PortDock 的一句话定位句式几乎同构）。首屏视觉物只有应用图标。
- **下载 CTA**：按钮文案 "⬇ Download Sloth 3.6"，直链 zip 文件；按钮旁直接标注 **"1.3 MB、Intel/ARM 64-bit、macOS 11+、已签名公证"**；下方给出 `brew install --cask sloth`；再往下列旧系统对应的历史版本（10.13–10.15 用 3.4，更早用 3.2）。
- **托管**：自建（Apache，作者个人站）。
- **值得借鉴**：
  1. **把「体积 1.3 MB + 签名公证 + 芯片架构 + 系统要求」直接写在下载按钮同一行**——这四项恰好全是 PortDock 的信任主张，一行小字比单独一个「信任区块」更可信。
  2. **brew cask 命令用等宽代码块紧跟主按钮之后**，两种安装路径并列不互相抢戏。
  3. 反面教训：首屏只有图标没有产品截图，陌生用户要滚到底部才看到界面——PortDock 应把截图提到首屏。

### 2. Maccy — 开源菜单栏工具，且本身就用 GitHub Pages 托管

URL：https://maccy.app/

- **分区结构**：防伪警告条 → Hero（Logo+标题+一句描述+双 CTA+系统要求）→ "Why" 6 个特性卡片 → "How" 使用说明配图 → 4 条用户评价 → 底部重复 CTA+文档链接。
- **Hero 文案**：主标题就是产品名 "Maccy"，副标题 "Clipboard manager for macOS which does one job — keep your copy history at hand. Period."（单一职责+口语收尾的定位句）。首屏视觉物为应用 Logo。
- **下载 CTA**：双按钮 "Get in App Store" + "Download now"（Gumroad）；按钮下方一行 "Requires macOS Sonoma 14 or higher"；页面强调 "It is and will always be free"。未提 Homebrew。
- **托管**：**GitHub Pages（响应头 `server: GitHub.com`，已核实）+ 自定义域名**——直接证明 PortDock 的部署方案能撑起这个精致度。
- **值得借鉴**：
  1. **6 个特性卡片里把「安全隐私」「开源」「原生轻量」当一等公民功能来写**，而不是塞在页脚——与 PortDock 的信任主张（无遥测/开源/体积小）完全同构，可直接套这个卡片区模式。
  2. 底部**重复一次下载 CTA**，长页滚到底不用回头。
  3. "does one job … Period." 的句式：一句话说清单一职责，PortDock 可仿写（见文末建议）。

### 3. Rectangle — 开源窗口管理器，免费+Pro 双轨

URL：https://rectangleapp.com/

- **分区结构**：导航 → Hero（名称+一句描述+下载按钮）→ Pro 版推广 → 功能区 "Plenty of shortcuts" → 功能区 "Pick your snap areas" → Spectacle 迁移说明 → 捐赠/赞助商 → 相关应用推荐 → 许可证说明 → 版本历史+页脚。
- **Hero 文案**：主标题 "Rectangle"，副标题 "Move and resize windows in macOS using keyboard shortcuts or snap areas"（动词开头、纯功能陈述）。首屏视觉物是 512px 应用图标。
- **下载 CTA**：按钮文案 "Download"，**直接指向 GitHub Releases 的当前版本**；按钮附近标注 "Supports macOS 10.15+, Intel and Apple Silicon"。无 brew 命令。
- **托管**：Cloudflare 前置，源站不可判断。
- **值得借鉴**：
  1. **免费开源版的 Download 按钮直指 GitHub Releases 资产**，不做中间下载页——PortDock 主 CTA 可同样直链最新 release 的 .dmg。
  2. "Supports macOS 10.15+, Intel and Apple Silicon" 这种**架构+版本一行式标注**放按钮紧邻位置。
  3. 反面教训：Pro 推广、相关应用推荐、赞助商混排让页面很长且分散；PortDock 无商业化诉求，砍掉这些能明显更干净。

### 4. Ice — 开源菜单栏管理工具（GitHub 3 万+ star 档）

URL：https://icemenubar.app/

- **分区结构**：极简导航（Home / Donate / Download / View on GitHub 四项）→ Hero（Logo+标题+下载按钮+捐赠链接+**演示视频**）→ 5 个功能模块（每个配对应截图/动图）→ 页脚。整页只有三层，是本次样本里最短的结构。
- **Hero 文案**：主标题 "Ice"，副标题是一整段功能陈述（"Ice is a powerful menu bar management tool. While its primary function is hiding and showing menu bar items…"）。首屏视觉物是**一段 .mov 演示视频**（Show On Hover 效果）。
- **下载 CTA**：按钮文案 "Download"，链接由 JS 动态解析（静态源码里是 `javascript:void(0)`，推测运行时取最新 GitHub release）。无 brew 命令、无系统要求标注。
- **托管**：非 GitHub Pages（响应头显示 PHP/APISIX）。
- **值得借鉴**：
  1. **「一个功能 = 一段动图」的功能区组织**：每个功能模块左文右图（或上下），动图直接演示交互——PortDock 的「级联启动」是动态过程，静态截图讲不清，最适合这种一段 5–10 秒的动图/视频。
  2. **导航只保留 4 项**（Home/Download/GitHub/Donate），对单页产品站足够。
  3. 反面教训：副标题太长（两句 40+ 词），且下载按钮无系统要求标注——这两点 PortDock 都应避免。

### 5. AltTab — 开源起家、现为免费+Pro 的窗口切换器（对照：开源产品成熟期页面）

URL：https://alt-tab.app/（原 alt-tab-macos.netlify.app 301 跳转至此）

- **分区结构**：导航（Home/Features/Changelog/Pricing）→ 下载按钮（带下载量）→ Hero（标题+副标题+大产品截图）→ 数据条（下载量/GitHub star/媒体评价）→ Pro 功能四项 → 免费 vs 付费对比表 → 页脚（FAQ/GitHub/多语言切换）。
- **Hero 文案**：主标题 "AltTab Pro"，副标题 **"See every window. Switch in an instant."**（两个超短句，先结果后速度）。首屏视觉物是一张大产品截图（webp）。
- **下载 CTA**：按钮文案 "Download"，旁边缀 "8.2M downloads"（自报数字），指向 GitHub release 的 zip。无 brew 命令、无系统要求标注。
- **托管**：Cloudflare 前置；历史上托管在 Netlify（旧域名 301 可证），现源站不可判断。
- **值得借鉴**：
  1. **「两短句副标题」模式**：第一句说用户看到什么，第二句说多快——PortDock 可仿写成 "See every port. Start the whole stack in one click." 这类结构。
  2. **信任数据条**（GitHub star 数 16K、媒体引语）放在 hero 之下第一屏边缘——PortDock 早期没有大数字，可以换成 "MIT · ~X MB · 0 依赖 · 0 网络请求" 四枚事实徽章，同样位置同样作用。
  3. 反面教训：免费/付费对比表和 Pricing 导航让「开源免费」的第一印象被稀释；PortDock 保持纯免费叙事更干净。

### 6. Proxyman — 商业独立开发者作品对照（打磨天花板）

URL：https://proxyman.com/（原 proxyman.io 301 跳转至此）

- **分区结构**（很长，取骨架）：导航 → Hero（标题+副标题+下载按钮+**首屏视频**）→ 社会证明（Product Hunt/App Store 评分）→ "Trusted by 500,000+ developers"+客户 logo 墙 → 6 个原生 macOS 特性交互卡片 → 多个功能纵深区（抓包/脚本/Diff/Compose/团队协作/移动端/终端）→ 功能清单 → 用户评价 → 团队故事 → 页脚。
- **Hero 文案**：主标题 **"Capture HTTP(s) in a second"**（动词+时间承诺），副标题 "Best-in-class native macOS app to capture, decrypt, and mock your HTTP(s) requests/responses with powerful debugging tools."。首屏视觉物是嵌入式产品演示视频。
- **下载 CTA**："Download for macOS"，直链 `/release/osx/Proxyman_latest.dmg`；按钮下方一行 **"Apple Silicon & Intel • macOS 13+ • macOS Tahoe (26)"**。无 brew 命令展示。
- **托管**：Cloudflare 前置，自建。
- **值得借鉴**：
  1. **`Proxyman_latest.dmg` 固定链接模式**：主 CTA 永远指向「最新版」的稳定 URL，页面不用每次发版改链接——PortDock 用 GitHub 的 `releases/latest/download/PortDock.dmg` 路径可实现同样效果。
  2. **"Apple Silicon & Intel • macOS 13+" 用圆点分隔的一行系统要求**，是样本里最干净的标注格式。
  3. **"native macOS app" 作为副标题里的显式卖点**——PortDock 的原生 SwiftUI/零依赖同样值得写进副标题而非藏在 README。

### 候选访问情况说明

- 全部 6 个目标最终访问成功；其中 2 个经 301 跳转后成功：`alt-tab-macos.netlify.app → alt-tab.app`、`proxyman.io → proxyman.com`。
- Stats（exelban/stats）、Hidden Bar 未纳入：两者以 GitHub 仓库 README 为主要门面、无独立产品落地页（此判断基于检索结果，未做穷尽核实），对「落地页分区结构」调研无增量。
- TablePlus 未再访问：已有 Proxyman 作为商业对照，且 6 个样本已覆盖任务要求的 4–6 个。

## 第二部分：GitHub Pages 发布事实核实

以下三点均以 docs.github.com 当前文档核实（2026-07-15 抓取）。

**1. 从 main 分支 /docs 目录发布 project site**
文档：[Configuring a publishing source for your GitHub Pages site](https://docs.github.com/en/pages/getting-started-with-github-pages/configuring-a-publishing-source-for-your-github-pages-site)
- 步骤：仓库 Settings → Pages → "Build and deployment" 下 Source 选 "Deploy from a branch" → 分支下拉选 `main` → 文件夹下拉选 `/docs` → Save。
- 发布源文件夹只有两个选项：分支根目录 `/` 或该分支的 `/docs` 文件夹。
- 文档明确警告：选了 `/docs` 之后如果把该目录从分支里删掉，"your site won't build and you'll get a page build error message"。
- 入口文件：文档写明 "GitHub Pages will look for an `index.html`, `index.md`, or `README.md` file as the entry file"（出处：[Creating a GitHub Pages site](https://docs.github.com/en/pages/getting-started-with-github-pages/creating-a-github-pages-site)；文档未明确写三者优先顺序）。

**2. project site 的 URL 基路径**
文档：[About GitHub Pages](https://docs.github.com/en/pages/getting-started-with-github-pages/about-github-pages)
- project site 的 URL 格式为 `http(s)://<owner>.github.io/<repositoryname>`，即 PortDock 站点位于 `lurenkt.github.io/PortDock/`，基路径是 `/PortDock/` 而非 `/`。
- 由此推论（标准 HTML 行为，非文档原文）：页面内所有以 `/` 开头的绝对路径引用（如 `/style.css`、`/img/hero.png`）会指到 `lurenkt.github.io/style.css` 而 404；**必须用相对路径（`style.css`、`./img/hero.png`）或写死 `/PortDock/` 前缀**。单页手写 HTML 全用相对路径即可，无需 base 标签。

**3. Jekyll 默认处理与 `.nojekyll`**
文档：[Creating a GitHub Pages site](https://docs.github.com/en/pages/getting-started-with-github-pages/creating-a-github-pages-site)、[About GitHub Pages and Jekyll](https://docs.github.com/en/pages/setting-up-a-github-pages-site-with-jekyll/about-github-pages-and-jekyll)
- 从分支发布时 Jekyll 默认运行："If you publish your site from a source branch, GitHub Pages will use Jekyll to build your site by default."
- 禁用方式：在发布源根目录（即 `/docs` 下）创建空文件 `.nojekyll`，作用是 "disable the Jekyll build process"。
- 纯手写 HTML 需不需要：Jekyll 会照常输出普通 HTML，但**不会构建/输出**这些内容：`_` `.` `#` 开头的文件或目录、`~` 结尾的文件、`/node_modules` 与 `/vendor` 目录。所以纯手写 HTML 只要没有下划线开头的资源目录（如 `_assets/`）不加 `.nojekyll` 也能跑；**但加一个空 `.nojekyll` 成本为零，还能跳过无意义的 Jekyll 构建并杜绝这类坑，建议直接加**。

## 结构建议初稿

> 以下是基于上述 6 个参考案例综合出的推荐分区顺序，属建议初稿，待原型阶段与用户确认后再定。

1. **极简导航**（Logo + GitHub + Download 共 3 项）——Ice 证明单页产品站 3–4 项导航足够。
2. **Hero：两短句标题 + 一行副标题 + 主 CTA**（如 "See every port. Start the whole stack in one click." 风格；副标题里显式写 "native SwiftUI, zero dependencies"）——AltTab 的短句模式 + Proxyman 的 native 卖点前置。
3. **主 CTA 按钮直链 `releases/latest/download/*.dmg`，按钮同行小字标注 "Apple Silicon & Intel • macOS XX+ • ~X MB • 已签名公证"**——Rectangle 的直链 + Sloth 的体积/公证标注 + Proxyman 的圆点分隔格式。
4. **CTA 正下方给 brew 命令代码块**（若已提交 cask；未提交则此行暂缺）——Sloth 的双安装路径并列模式。
5. **Hero 下方一张带阴影的深色大截图（或 5–10 秒级联启动动图）**——AltTab 首屏大截图 + Ice 用动图讲动态交互；级联启动是 PortDock 最不可截图化的卖点，优先做成动图。
6. **事实徽章条：MIT 开源 · 零依赖 · 无遥测 · 0 网络请求 · ~X MB**——AltTab 数据条位置 + Maccy 把隐私/开源当一等功能写的思路；早期没有 star 数就用可验证事实顶上。
7. **三段功能区（端口总览 / 依赖关系检测 / 一键级联启动），每段一图一短文**——Ice 的「一功能一动图」组织，砍到三段控制页长。
8. **底部重复下载 CTA + 页脚（GitHub / MIT License / Changelog）**——Maccy 的底部重复 CTA；不设捐赠/推荐位，保持单一目标。

工程注意事项（对应第二部分结论）：全站相对路径引用资源；`docs/` 根放 `index.html` + 空 `.nojekyll`；主 CTA 用 `github.com/LurenKT/PortDock/releases/latest/download/…` 固定链接避免每次发版改页面。
