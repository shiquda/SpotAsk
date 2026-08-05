# SpotAsk README 首屏图标与徽章实践

调研日期：2026-08-04

范围：GitHub README 首屏中的产品识别图形、可访问的图片写法，以及 2--4 个决策有用的元数据徽章。GitHub 官方文档用于确认渲染约束；公开项目 README 用于观察可复用的信息架构。样本不是 GitHub 的强制规范。

## 结论先行

SpotAsk 适合采用“一个产品图标 + 一句定位 + 三枚徽章 + 一个清晰下载/构建入口”的首屏。图标负责辨识度，真实聊天截图负责证明产品体验，徽章只负责回答访客的采用问题：现在能拿到什么版本、自动化检查是否通过、许可证是什么。

推荐保留以下三枚徽章：

1. CI 状态：链接到 GitHub Actions 的 `CI` 工作流。
2. 最新版本：链接到 GitHub Releases；目前仓库有公开的 `v0.1.2` Release，含 arm64、x86_64 DMG 和校验文件。
3. 许可证：链接到仓库中的 AGPL-3.0 `LICENSE`。

不建议把 Swift、SwiftUI、OpenAI、star 数、下载量或一串社交平台图标做成首屏徽章。它们通常不能帮助用户决定是否下载或构建 SpotAsk；平台与架构信息用一句短文本或 `Requirements` 说明即可。

## GitHub 的可验证约束

### README 是首屏导览

GitHub 将 README 描述为访客通常首先看到的内容，并列出其常见职责：说明项目做什么、为什么有用、如何开始、在哪里求助，以及谁在维护。GitHub 还建议 README 只放开始使用和贡献所需的信息，较长的材料放入 wiki 或其他文档。因此首屏应先完成身份、价值和下一步动作，再放状态信息。

来源：[About the repository README file](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-readmes)

### 图片路径、替代文本和响应式图形

- 仓库内的图片应使用相对路径；GitHub 会按当前分支转换路径，克隆仓库后相对路径也更容易继续工作。
- GitHub 对图片的定义中，`alt` 文本是图片信息的简短文字等价物。首屏图标应使用类似 `SpotAsk app icon` 的描述性文本；产品截图应说明画面中的任务和结果，而不是只写 `screenshot`。
- GitHub 支持 `<picture>` 元素。官方 Quickstart 用它根据 `prefers-color-scheme` 选择明暗图片，并明确要求为屏幕阅读器提供描述性的 `alt`。这适合确实存在明暗两套品牌资产时使用，不需要为了图标强行增加两套资源。
- GitHub 的仓库社交预览是独立于 README 的设置：官方建议 PNG/JPG/GIF 小于 1 MB，最佳显示尺寸为 1280x640。社交预览用于分享仓库链接，不能替代 README 中识别项目和展示产品的图形。

来源：[Basic writing and formatting syntax - Images](https://docs.github.com/en/get-started/writing-on-github/getting-started-with-writing-and-formatting-on-github/basic-writing-and-formatting-syntax#images)、[Quickstart for writing on GitHub - responsive image](https://docs.github.com/en/get-started/writing-on-github/getting-started-with-writing-and-formatting-on-github/quickstart-for-writing-on-github#adding-an-image-to-suit-your-visitors)、[Customizing your repository's social media preview](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/customizing-your-repositorys-social-media-preview)

GitHub Flavored Markdown 规范进一步说明：图片描述最终通常作为 HTML `alt` 属性；GitHub.com 还会在 GFM 转成 HTML 后进行安全和一致性处理。因此应优先使用普通 Markdown 图片或简单、已验证的 HTML 包装，不要依赖复杂脚本或自定义 CSS。

来源：[GitHub Flavored Markdown Spec, Images](https://github.github.com/gfm/#images)

GitHub 自己的 `github-markup` 实现还说明，HTML 会经过激进的清理，可能移除脚本、内联样式以及 `class`/`id` 属性。`<p align="center">` 是 README 中常见且当前可用的单项居中写法，但不要把它扩展成依赖 CSS 的复杂布局；提交前应以 GitHub 实际渲染结果为准。

来源：[github/markup README](https://raw.githubusercontent.com/github/markup/master/README.md)、[github/markup issue #1090](https://github.com/github/markup/issues/1090)

## 一手 README 样本

以下数量是 2026-08-04 读取各仓库默认分支 README 源码时的首屏观察，不是质量评分。

| 项目 | 首屏图形与徽章 | 可借鉴做法 | 不应机械复制的部分 |
| --- | --- | --- | --- |
| [Astro](https://raw.githubusercontent.com/withastro/astro/main/README.md) | 品牌横幅；紧接定位句；CI、许可证、npm 版本 3 枚徽章；随后是 Install | 先回答“是什么”，再把最短安装动作放在徽章之后 | 其目录、生态包版本表和赞助区来自大型 monorepo，不适合 SpotAsk 首屏 |
| [Next.js](https://raw.githubusercontent.com/vercel/next.js/canary/packages/next/README.md) | Logo；维护方、npm 版本、许可证、社区 4 枚徽章；随后 Getting Started | 徽章各自对应维护者、可安装版本、许可证、社区入口 | “大型公司使用”等社会证明需要独立可靠证据，不能作为小项目默认文案 |
| [Immich](https://raw.githubusercontent.com/immich-app/immich/main/README.md) | 许可证和 Discord 2 枚徽章；Logo；定位句；可点击产品截图 | 极少徽章也能建立身份、支持入口和产品证据；截图紧贴定位 | 其多语言、演示账号和大型功能矩阵是成熟产品的需求 |
| [Excalidraw](https://raw.githubusercontent.com/excalidraw/excalidraw/master/README.md) | 品牌封面；定位句；许可证、下载、贡献、Discord、DeepWiki、Twitter 等 6 枚徽章 | 当每个入口都有真实维护者和用户动作时，徽章可以承担导航 | 6 枚以上会让首屏变成导航墙；下载、关注和社交徽章对 SpotAsk 的采用决策不如 Release/CI/License 直接 |
| [Plane](https://raw.githubusercontent.com/makeplane/plane/master/README.md) | Logo、定位、产品截图和网站/论坛/文档链接；没有首屏状态徽章；技术栈徽章在安装之后 | 复杂部署分支先给 Cloud/自托管行动，技术栈放在用户安装路径之后 | SpotAsk 不需要复制其 Cloud、自托管或多套部署入口 |

这些样本共同支持一个有限结论：图形要承担身份或产品证据，徽章要承担可验证的采用信号；首屏的具体数量应由项目阶段和真实入口决定。

## 为什么避免徽章墙

GitHub 的官方状态徽章文档只定义了一个明确用途：显示某个工作流当前是通过还是失败，并说明 README 是常见放置位置；它没有规定 README 应放多少枚徽章。因此“2--4 枚”是本项目的设计上限，而不是 GitHub 规则。

控制数量有四个工程和阅读理由：

1. 每枚徽章都会增加一个需要持续维护的图片 URL、落点和事实。Release、CI 或许可证失效时，首屏信任会直接受影响。
2. 徽章中的文字尺寸小、颜色多。数量一多，产品名称和定位句反而不再是第一视觉锚点，窄屏还会产生难看的换行。
3. 技术栈、star、下载量、访客量和“awesome”类徽章通常不能回答“我能否使用、如何安装、是否允许使用”这类采用问题；它们属于装饰或社区统计，不应默认占据首屏。
4. 徽章本质上是图片。每枚都应有描述性 `alt`，并链接到与文字完全一致的页面；否则屏幕阅读器用户和关闭图片的读者都只能看到无意义的图像。

来源：[Adding a workflow status badge](https://docs.github.com/en/actions/how-tos/monitor-workflows/add-a-status-badge)、[GitHub Flavored Markdown Spec, Images](https://github.github.com/gfm/#images)、[GitHub accessibility tips](https://github.blog/developer-skills/github/5-tips-for-making-your-github-profile-page-accessible/)。上述“上限”和“避免类型”是结合官方职责说明与一手样本作出的设计判断，不是 GitHub 的硬性限制。

## 针对 SpotAsk 的证据与建议

### 已有证据

- `Resources/AppIcon.icns` 是应用的稳定图标资源，`Resources/Info.plist` 将其声明为 `AppIcon`。README 不应直接把 macOS 专用 `.icns` 当作网页图片；应从同一资源导出一个已纳入仓库的 PNG。当前工作区已有候选 `images/spotask-icon.png`（1024x1024），提交前需确认它确实来自该应用图标并被 Git 跟踪。
- `images/spotask-chat.png` 是英文界面在浅色/深色模式下的斜线拼图（1526x1062），展示最新问答主界面；现有 README 已通过居中的 `<p align="center">` 包装，并给出描述性 `alt`。
- `Package.swift` 声明最低平台为 macOS 15；`.github/workflows/ci.yml` 对 arm64 和 x86_64 都运行 `swift test` 和 DMG 打包。
- GitHub Actions API 显示 `CI` 工作流处于 active，最近一次 main 运行成功；工作流公开徽章地址为 `https://github.com/shiquda/SpotAsk/actions/workflows/ci.yml/badge.svg`。
- GitHub Releases API 显示当前公开最新版本为 `v0.1.2`，有 arm64、x86_64 DMG 和 SHA256 校验文件；仓库许可证 API 和 `LICENSE` 均为 AGPL-3.0。

本地文件：[Resources/AppIcon.icns](../Resources/AppIcon.icns)、[Resources/Info.plist](../Resources/Info.plist)、[images/spotask-chat.png](../images/spotask-chat.png)、[Package.swift](../Package.swift)、[CI workflow](../.github/workflows/ci.yml)、[LICENSE](../LICENSE)

远程核验：[SpotAsk Releases API](https://api.github.com/repos/shiquda/SpotAsk/releases/latest)、[SpotAsk CI workflow API](https://api.github.com/repos/shiquda/SpotAsk/actions/workflows/ci.yml)、[SpotAsk CI runs API](https://api.github.com/repos/shiquda/SpotAsk/actions/workflows/ci.yml/runs?per_page=5)、[SpotAsk License API](https://api.github.com/repos/shiquda/SpotAsk/license)

### 推荐首屏结构

图标尺寸保持稳定即可，例如 96--112px；不要把图标做成占满首屏的横幅。徽章行使用普通 Markdown/HTML 图片，窄屏自然换行：

```html
<p align="center">
  <img src="images/spotask-icon.png" width="104" alt="SpotAsk app icon">
</p>

<h1 align="center">SpotAsk</h1>

<p align="center">
  A focused AI chat companion that lives in your macOS menu bar.
</p>

<p align="center">
  <a href="https://github.com/shiquda/SpotAsk/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/shiquda/SpotAsk?display_name=tag&sort=semver"></a>
  <a href="https://github.com/shiquda/SpotAsk/actions/workflows/ci.yml"><img alt="CI status" src="https://github.com/shiquda/SpotAsk/actions/workflows/ci.yml/badge.svg"></a>
  <a href="LICENSE"><img alt="License: AGPL-3.0" src="https://img.shields.io/github/license/shiquda/SpotAsk"></a>
</p>
```

`img.shields.io` 是第三方徽章服务，不是 GitHub 的必需依赖。若不希望首屏依赖第三方图片，可保留 GitHub Actions 原生状态徽章，并把 Release 和 License 改成带文字的普通链接；重要事实不应只存在于图片里。

建议在徽章行下方或定位句旁用一行普通文字写明 `macOS 15+ · Apple silicon and Intel · AGPL-3.0`，而不是新增平台、Swift 或技术栈徽章。这样既保留源信息，又不让技术标签压过下载动作。

## 落地验收清单

- 图标来自 `AppIcon.icns` 的 PNG 导出，文件已纳入 Git，GitHub 页面能直接加载。
- 图标、截图和徽章都有描述性 `alt`；徽章链接分别落到 Release、CI workflow 和 `LICENSE`。
- Release 徽章指向最新发布，不硬编码 `v0.1.2`，避免下次发布后过期。
- CI 徽章使用默认分支并在工作流变更后复核；GitHub 官方说明默认显示 default branch 状态。
- 首屏仍能在滚动前看到产品名、受众/结果句和下载或构建入口；徽章换行不能遮挡文字。
- 本地 Markdown 预览和 GitHub 渲染都检查图片路径、HTML 包装和链接；不要把 `.icns`、内部路径或未验证的社区链接直接放进首屏。

## 参考来源

- [GitHub Docs: About the repository README file](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-readmes)
- [GitHub Docs: Basic writing and formatting syntax - Images](https://docs.github.com/en/get-started/writing-on-github/getting-started-with-writing-and-formatting-on-github/basic-writing-and-formatting-syntax#images)
- [GitHub Docs: Quickstart for writing on GitHub](https://docs.github.com/en/get-started/writing-on-github/getting-started-with-writing-and-formatting-on-github/quickstart-for-writing-on-github#adding-an-image-to-suit-your-visitors)
- [GitHub Docs: Adding a workflow status badge](https://docs.github.com/en/actions/how-tos/monitor-workflows/add-a-status-badge)
- [GitHub Docs: Customizing your repository's social media preview](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/customizing-your-repositorys-social-media-preview)
- [GitHub Flavored Markdown Spec: Images](https://github.github.com/gfm/#images)
- [Astro README](https://raw.githubusercontent.com/withastro/astro/main/README.md)
- [Next.js README](https://raw.githubusercontent.com/vercel/next.js/canary/packages/next/README.md)
- [Excalidraw README](https://raw.githubusercontent.com/excalidraw/excalidraw/master/README.md)
- [Immich README](https://raw.githubusercontent.com/immich-app/immich/main/README.md)
- [Plane README](https://raw.githubusercontent.com/makeplane/plane/master/README.md)
