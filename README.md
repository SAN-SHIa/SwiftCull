# SwiftCull

一款基于 SwiftUI 构建的 macOS 原生照片管理应用。专为摄影师设计，可快速筛选、评分、标记和删除 SD 卡及大型目录中的照片。

## 功能特性

- **照片扫描** — 读取并识别 SD 卡或任意目录中的照片（JPG、NEF/RAW、MOV）
- **智能筛选** — 按文件名、评分、文件类型（JPG/RAW/RAW+JPG/MOV）和 Finder 标签筛选
- **评分系统** — 1-5 星评分，支持批量操作
- **macOS Finder 标签** — 完整集成 macOS 原生标签系统，自动发现自定义标签名称和颜色
- **Quick Look 预览** — 按空格键预览照片，与 Finder 体验一致
- **键盘导航** — 方向键导航，空格键预览，Delete 键删除
- **批量操作** — 多选照片后批量设置评分、标签或删除
- **一键删除** — 同时删除 JPG 和 RAW（NEF）配对文件
- **文件类型标识** — 照片上显示 RAW/RAW+JPG/JPG/MOV 类型徽章
- **缩略图缓存** — 二级缓存（内存 + 磁盘），10GB+ 目录也能快速加载
- **排序选项** — 按名称、日期、评分或大小排序，支持正序/逆序

## 系统要求

- macOS 14.0 (Sonoma) 或更高版本
- Xcode 16.0 或更高版本

## 构建与运行

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

3. 打开并运行：
   ```bash
   open SwiftCull.xcodeproj
   ```

   或使用命令行编译：
   ```bash
   xcodebuild -project SwiftCull.xcodeproj -scheme SwiftCull -configuration Debug build
   ```

## 使用方法

1. 启动 SwiftCull — 自动加载配置路径中的照片
2. 点击**打开文件夹**或按 `⌘O` 选择其他目录
3. 单击照片选中，按**空格键**进行 Quick Look 大图预览
4. 使用**方向键**在照片间导航
5. 点击**选择**按钮进入批量选择模式
6. 在选择模式中，使用工具栏批量设置评分、标签或删除

### 键盘快捷键

| 按键 | 操作 |
|------|------|
| `空格` | Quick Look 预览 / 关闭预览 |
| `↑ ↓ ← →` | 在照片间导航 |
| `⌘O` | 打开文件夹 |
| `⌘1-5` | 设置评分 |
| `⌘0` | 清除评分 |
| `⌘Delete` | 移至废纸篓 |
| `A` | 全选（非文本输入时） |

## 项目架构

```
SwiftCull/
├── App/
│   └── SwiftCullApp.swift         # 应用入口，键盘监听
├── Models/
│   ├── PhotoEntry.swift           # 照片数据模型，FinderTagService
│   └── FilterOptions.swift        # 筛选与排序选项
├── Services/
│   ├── FileService.swift          # 文件系统扫描与删除
│   ├── RatingService.swift        # 评分持久化（UserDefaults）
│   ├── TagService.swift           # macOS Finder 标签读写（xattr）
│   └── ThumbnailService.swift     # 异步缩略图生成与缓存
├── ViewModels/
│   └── PhotoStore.swift           # 核心状态管理
└── Views/
    ├── ContentView.swift          # 主布局（NavigationSplitView）
    ├── FilterSidebar.swift        # 筛选与排序面板
    ├── PhotoGridView.swift        # 照片网格与选择
    ├── PhotoDetailView.swift      # 照片详情与 Quick Look
    ├── AsyncThumbnailView.swift   # 异步缩略图加载
    └── RatingView.swift           # 星级评分组件
```

## 标签系统

SwiftCull 完整集成 macOS 原生 Finder 标签系统。启动时自动扫描桌面、文稿和下载目录，发现自定义标签名称及其关联颜色。SwiftCull 写入的标签与 Finder 完全兼容——两个应用中显示相同的颜色和名称。

macOS 颜色编号映射：

| 编号 | 颜色 |
|------|------|
| 1 | 灰色 |
| 2 | 绿色 |
| 3 | 紫色 |
| 4 | 蓝色 |
| 5 | 黄色 |
| 6 | 红色 |
| 7 | 橙色 |

## 许可证

MIT
