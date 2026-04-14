# CopySouL

CopySouL 是一个原生 macOS SwiftUI 应用，用来导入 SOUL pack，并按其中的说话风格、示例对话和资源模仿一个人的表达方式。当前版本是产品骨架：已经包含 SOUL 导入、半透明聊天界面、图片输入、受限工具调用、可配置模型后端和按 SOUL 隔离的长期记忆。

## 当前能力

- 原生 macOS SwiftUI，使用 XcodeGen 生成 Xcode 工程。
- 半透明桌面聊天 UI：左侧是 SOUL 选择和导入入口，中间是当前 SOUL 的对话区，底部支持文字、图片附件和截图附件。
- SOUL pack 导入：必需 `SOUL.md` 和 `setting.json`，资源目录缺失时跳过，多余目录保留为其他资源。
- 表情包作为受限工具 `select_meme` 调用：模型先生成文字，再按 SOUL pack 中的表情包描述选择一张合适图片。
- 长期记忆：SQLite + FTS 本地存储，完全按 SOUL 隔离，不做传统 session 列表。
- 记忆更新：每轮回复后用独立记忆总结模型抽取候选事实/偏好，本地去重、搜索、权重衰减和命中加权。
- 模型配置：支持 OpenAI-compatible、Claude、Gemini、Ollama-compatible；聊天模型、视觉模型、记忆总结模型可分别设置，API key 存 Keychain。
- 受限工具：仅提供 `memory_search`、`take_screenshot`、`select_meme`，不暴露 shell、文件系统、浏览器等 Agent 工具。
- 截图工具：使用 ScreenCaptureKit，截图前隐藏 CopySouL 自身窗口；缺少系统屏幕录制权限时会返回错误提示。

## 环境要求

- macOS 15+
- Xcode 26.2 或兼容版本
- Swift 6
- XcodeGen

检查工具链：

```sh
swift --version
xcodebuild -version
xcodegen --version
```

## 快速开始

生成工程：

```sh
xcodegen generate
```

运行默认测试：

```sh
xcodebuild test -scheme CopySouL -destination 'platform=macOS'
```

打开工程：

```sh
open CopySouL.xcodeproj
```

默认 scheme 是 `CopySouL`，只跑稳定单元测试。`CopySouL UI` 是单独的 UI smoke test scheme，可能需要 macOS 自动化权限；如果命令行提示 `Timed out while enabling automation mode`，请先在系统设置中允许 Xcode/测试运行器进行自动化控制后再单独运行。

## SOUL Pack 格式

SOUL pack 是一个文件夹，最小结构如下：

```text
MySoul/
  SOUL.md
  setting.json
```

带资源的结构示例：

```text
MySoul/
  SOUL.md
  setting.json
  assets/
    表情包/
      memes.md
      A.png
      B.jpg
      C.gif
    文档/
      notes.md
    图片/
      photo.png
```

导入规则：

- `SOUL.md`：必需，包含说话风格定义和示例对话。
- `setting.json`：必需，包含开关和默认配置；未知字段会保留。
- `assets` / `asset` / `资源` / `素材` / `resource` / `resources`：可选资源根目录。
- 表情包、文档、图片等分类目录是可选的；缺少就跳过。
- 自定义目录不会阻止导入，会按文件类型启发识别或作为 `other` 保存。

表情包目录内可以放一个或多个 `.md` 描述文件。描述文件按行匹配图片文件名，例如：

```md
A.png 画面内容：开心拍桌。什么时候用：用户成功了或气氛很开心。
B.jpg 画面内容：沉默盯屏幕。什么时候用：遇到离谱问题或需要吐槽。
C.gif 画面内容：无语转头。什么时候用：轻微嫌弃但不想太严肃。
```

只有带描述的表情包会暴露给 `select_meme` 工具；缺少描述的图片会被导入，但不会被工具自动选择。

## setting.json

当前支持字段：

```json
{
  "displayName": "Alice",
  "enableMemeReplies": true,
  "allowMultiSentenceReplies": true,
  "defaultModel": "gpt-5.4"
}
```

也兼容部分蛇形命名和中文命名，例如 `display_name`、`enable_meme_replies`、`allow_multi_sentence_replies`、`表情包回复`、`多句回复`。

默认值：

- `enableMemeReplies`: `true`
- `allowMultiSentenceReplies`: `true`
- `displayName`: 未设置时使用文件夹名
- `defaultModel`: 未设置时使用应用设置里的聊天模型

## 模型后端

首次启动会显示 onboarding，之后也可以在设置页修改：

- provider: OpenAI-compatible / Claude / Gemini / Ollama-compatible
- base URL
- API key
- chat model
- vision model
- memory model

API key 使用 Keychain 保存。Ollama-compatible 可以不填 API key，其他 provider 需要有效 key 才能请求模型。

## 长期记忆

CopySouL 不保存传统 session 列表。当前聊天上下文只用于运行时模型上下文，真正可长期检索的内容来自记忆库。

记忆策略：

- 每个 SOUL 使用独立记忆空间。
- 每轮对话结束后调用独立记忆总结模型，产出新事实、用户偏好、更新和忽略项。
- SQLite 存储记忆，FTS 用于本地检索。
- 相同记忆按 hash 去重，重复命中会增加权重。
- 默认超过 3 个月未命中的记忆会降权，命中后提升权重并刷新使用时间。
- 低权重记忆默认不再参与检索，相当于软遗忘。

## 项目结构

```text
CopySouL/
  App/          应用入口和 AppViewModel
  Models/       SOUL、记忆、聊天、LLM 数据结构
  Services/     SOUL 导入、SQLite 记忆、LLM provider、工具、截图、Keychain
  Views/        SwiftUI 主界面、侧栏、聊天区、设置和 onboarding
  Resources/    Info.plist
CopySouLTests/  单元测试
CopySouLUITests/ UI smoke test
project.yml     XcodeGen 配置
```

## 测试覆盖

当前默认测试覆盖：

- SOUL pack 必需文件校验。
- `assets` / `asset` / 自定义目录识别。
- 表情包 markdown 描述解析。
- `setting.json` 默认值和未知字段保留。
- 记忆按 SOUL 隔离、去重、搜索、3 个月降权、命中加权。
- OpenAI-compatible、Claude、Gemini、Ollama-compatible 请求构造。

运行：

```sh
xcodebuild test -scheme CopySouL -destination 'platform=macOS'
```

可选 UI smoke test：

```sh
xcodebuild test -scheme 'CopySouL UI' -destination 'platform=macOS'
```

## 当前限制

- 这是本地产品骨架，不包含 marketplace、云同步、多账号或跨平台客户端。
- 图片输入已经接到 provider 请求构造，但真实效果取决于所选模型是否支持视觉输入。
- UI 自动化测试在未授权 macOS 自动化权限时会被系统阻止。
- 应用图标、打包发布、完整错误恢复和模型流式输出还未完善。
