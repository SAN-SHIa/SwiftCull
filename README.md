# ⚡ SwiftCull - 照片快筛
<div align="center">
  <div>
    <a href="https://github.com/SAN-SHIa/SwiftCull/releases"><img alt="GitHub Release" src="https://img.shields.io/github/v/release/SAN-SHIa/SwiftCull?style=flat-square" /></a>
    <a href="https://github.com/SAN-SHIa/SwiftCull"><img alt="Platform: macOS 14.0+" src="https://img.shields.io/badge/macOS-14.0%2B-blue?style=flat-square" /></a>
    <a href="https://github.com/SAN-SHIa/SwiftCull/blob/main/LICENSE"><img alt="License: MIT" src="https://img.shields.io/github/license/SAN-SHIa/SwiftCull?style=flat-square" /></a>
    <a href="https://github.com/SAN-SHIa/SwiftCull"><img alt="GitHub Stars" src="https://img.shields.io/github/stars/SAN-SHIa/SwiftCull?style=flat-square" /></a>
    <a href="https://github.com/SAN-SHIa/SwiftCull"><img alt="项目访问量" src="https://komarev.com/ghpvc/?username=SAN-SHIa-SwiftCull&color=brightgreen&label=views&style=flat-square" /></a>
  </div>
  <br>
</div>
<img src="./imgs/post.png" alt="SwiftCull" />

## 📥 下载安装

前往 [Releases](https://github.com/SAN-SHIa/SwiftCull/releases) 页面下载最新版 `SwiftCull.dmg`，打开后将 SwiftCull 拖入 Applications 即可完成安装。

> **首次打开提示：** 由于应用未经过 Apple 公证（Notarization），macOS 可能会阻止打开。请前往「系统设置 → 隐私与安全性」，点击「仍要打开」即可。

## 🎯 功能特性

**1. 🚀 极速筛选，告别低效**
面对 SD 卡中数千张照片，逐张查看费时费力。SwiftCull 支持按文件类型（RAW/JPG/MOV）、评分、Finder 标签和文件名智能筛选，配合键盘方向键导航和空格键 Quick Look 预览，让你像在 Finder 中一样快速浏览，筛选效率提升数倍。拖拽框选、`⌘` 点击、`⇧` 点击多选，网格大小可调。

**2. 🤖 AI 智能筛选**
集成 AI 照片分析能力，支持本地 Vision 框架和 LLM 云端分析两种模式。AI 可自动识别照片质量、构图、表情等维度，快速标记"保留"与"删除"建议，大幅减少人工筛选工作量。分析完成后提供 Review 界面，逐张确认 AI 建议。

**3. 🏷️ 原生标签，无缝协作**
深度集成 macOS Finder 标签系统，自动发现你的自定义标签名称和颜色。在 SwiftCull 中标记的红色、黄色标签，在 Finder 中同样可见，反之亦然。评分与标签支持批量操作，选中多张照片一键设置，无需逐张处理。

**4. 🗑️ 一键清理，释放空间**
每张照片往往同时存在 RAW 和 JPG 两个文件，手动删除容易遗漏。SwiftCull 自动识别配对文件，一键删除同时清理 RAW+JPG，连同 MOV 视频文件也一并管理，彻底释放存储空间。筛选结果可一键导出到指定目录。

**5. 📷 EXIF 信息，一目了然**
自动提取相机型号、镜头、焦距、光圈、快门速度、ISO、拍摄时间等 EXIF 数据，基于 ImageIO 框架纯原生实现。

## 📸 界面预览

| 深色模式 | 浅色模式 |
|:--------:|:--------:|
| <img src="./imgs/dark.jpeg" width="400" /> | <img src="./imgs/light.jpeg" width="400" /> |

## ⌨️ 快捷键

| 导航 | 评分 | 视图 | 操作 |
|:----:|:----:|:----:|:----:|
| `←` `→` 前后切换 | `1`–`5` 设置评分 | `E` 网格/单张切换 | `⌘O` 打开文件夹 |
| `↑` `↓` 按列跳转 | `0` 清除评分 | `Tab` 侧边栏开关 | `A` 全选 |
| `Space` Quick Look 预览 | | `F` 切换全屏 | `⌫` 删除选中 |
| | | | `⌘/` 快捷键指南 |

## 🛠 系统要求

- macOS 14.0 (Sonoma) 或更高版本
- Xcode 16.0 或更高版本（仅源码构建时需要）

## 🏗 构建与运行

**方式一：直接下载 DMG（推荐）**

前往 [Releases](https://github.com/SAN-SHIa/SwiftCull/releases) 下载 `SwiftCull.dmg`。

**方式二：源码构建**

1. 克隆仓库：
   ```bash
   git clone git@github.com:SAN-SHIa/SwiftCull.git
   cd SwiftCull
   ```

2. 生成 Xcode 项目（需要 [XcodeGen](https://github.com/yonaskolb/XcodeGen)）：
   ```bash
   brew install xcodegen
   xcodegen generate
   ```

3. 构建并运行：
   ```bash
   # 使用快捷脚本（推荐）
   ./run.sh           # Debug 构建并启动
   ./run.sh release   # Release 构建
   ./run.sh dmg       # 打包 DMG 安装包
   ./run.sh clean     # 清理构建产物
   ./run.sh help      # 查看所有命令
   ```

   或在 Xcode 中打开：
   ```bash
   open SwiftCull.xcodeproj
   ```

## 📖 使用方法

1. 启动 SwiftCull — 自动检测已连接的 SD 卡和常用目录
2. 点击**打开文件夹**或按 `⌘O` 选择其他目录
3. 单击照片选中，按**空格键**进行 Quick Look 大图预览
4. 使用**方向键**在照片间导航
5. 点击**选择**按钮进入批量选择模式
6. 在选择模式中，使用工具栏批量设置评分、标签或删除
7. 使用 **AI 筛选**面板进行智能照片分析与批量决策

## 🧩 项目架构

```
SwiftCull/
├── App/
│   ├── SwiftCullApp.swift            # 应用入口
│   └── KeyboardShortcutHandler.swift  # 快捷键管理
├── Models/
│   ├── PhotoEntry.swift              # 照片数据模型
│   ├── FilterOptions.swift           # 筛选条件
│   ├── FinderTag.swift               # Finder 标签
│   ├── PhotoExifInfo.swift           # EXIF 信息
│   └── AIAnalysisResult.swift        # AI 分析结果
├── Services/
│   ├── FileService.swift             # 文件操作
│   ├── RatingService.swift           # 评分管理
│   ├── TagService.swift              # 标签管理
│   ├── FinderTagService.swift        # Finder 标签集成
│   ├── ThumbnailService.swift        # 缩略图生成
│   ├── AICullService.swift           # AI 筛选核心
│   ├── LLMService.swift              # LLM 云端分析
│   ├── LocalVisionService.swift      # 本地 Vision 分析
│   ├── FastPreScreen.swift           # 快速预筛选
│   └── ProjectMetadataService.swift  # 项目元数据
├── ViewModels/
│   ├── PhotoStore.swift              # 照片数据管理
│   └── PhotoCellState.swift          # 单元格状态
└── Views/
    ├── ContentView.swift             # 主视图
    ├── FilterSidebar.swift           # 筛选侧边栏
    ├── PhotoGridView.swift           # 照片网格
    ├── PhotoDetailView.swift         # 照片详情
    ├── PhotoCardView.swift           # 照片卡片
    ├── AsyncThumbnailView.swift      # 异步缩略图
    ├── RatingView.swift              # 评分视图
    ├── SelectionCommandBar.swift     # 批量操作栏
    ├── WelcomeView.swift             # 欢迎页面
    ├── AICullPanelView.swift         # AI 筛选面板
    ├── AICullReviewView.swift        # AI 结果确认
    ├── AICullSettingsView.swift      # AI 设置
    └── Components/                   # 可复用组件
```

## 📄 许可证

[MIT](./LICENSE)
