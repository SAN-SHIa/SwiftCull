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

<p align="center">
  <img src="./imgs/post.png" alt="SwiftCull" />
</p>

> 一款为摄影师打造的 macOS 原生照片快速筛选工具。从 SD 卡里的数千张照片中，用最少的操作挑出该留的、删掉该删的。纯 SwiftUI + 系统原生框架，无第三方依赖。

---

## 📥 下载安装

前往 [Releases](https://github.com/SAN-SHIa/SwiftCull/releases) 页面下载最新版 `SwiftCull.dmg`，打开后将 SwiftCull 拖入 Applications 即可完成安装。

> [!IMPORTANT]
> 由于应用未经过 Apple 公证（Notarization），macOS 可能会阻止打开。请前往「系统设置 → 隐私与安全性」，点击「仍要打开」即可。

---

## 🎯 功能特性

- 🚀 **多维筛选** — 文件类型、评分、Finder 标签、文件名、拍摄日期，支持按月/日分组浏览
- 🔍 **大图审片** — 单图模式下捏合/双击/按钮缩放（最高 6×），放大后拖拽平移，切图自动复位
- 🏷️ **原生标签与评分** — 读取 Finder 标签并双向同步，批量编辑后「完成」才写入、「取消」即还原
- 🗑️ **配对删除与导出** — 自动关联 RAW+JPG+MOV，删除同步移入废纸篓；导出后台执行不卡界面
- 📷 **EXIF 解析** — 相机型号、镜头、焦距、光圈、快门、ISO 等元数据，基于 ImageIO 原生实现
- 🖱️ **灵活选择** — 拖拽框选、`⌘` 点选、`⇧` 连选，网格尺寸无级调节，方向键精准跨行

---

## 📸 界面预览

<table>
  <tr>
    <td align="center" width="50%">
      <img src="./imgs/dark.jpeg" width="400" /><br/>
      <sub><b>深色模式</b></sub>
    </td>
    <td align="center" width="50%">
      <img src="./imgs/light.jpeg" width="400" /><br/>
      <sub><b>浅色模式</b></sub>
    </td>
  </tr>
</table>

---

## 🛠 系统要求

- macOS 14.0 (Sonoma) 或更高版本
- Xcode 16.0 或更高版本（仅源码构建时需要）

---

## 🏗 构建与运行

**方式一：直接下载 DMG（推荐）**

前往 [Releases](https://github.com/SAN-SHIa/SwiftCull/releases) 下载 `SwiftCull.dmg`。

<details>
<summary><strong>方式二：源码构建</strong></summary>

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

> 修改、增删源文件后，记得重新运行 `xcodegen generate`（或 `./run.sh gen`）同步工程。

</details>

---

## ⌨️ 快捷键指南

<div align="center">

| 快捷键 | 说明 |
|:---|:---|
| `↑` `↓` `←` `→` | 按网格位置选择照片 |
| 拖拽框选 | 鼠标框选多张照片 |
| `Space` | Quick Look 预览 |
| `E` | 网格 / 大图切换 |
| `Q` | 完成并退出多选 |
| 双指捏合 | 缩放网格缩略图 |
| 大图缩放 | 捏合 / 双击 / `＋` `－` 缩放，拖拽平移 |
| `Tab` | 切换侧边栏 |
| `1`–`5` | 设置评分 |
| `0` | 清除评分 |
| `Delete` | 删除所选照片 |
| `A` | 全选当前筛选结果 |
| `Esc` | 退出多选 / 取消输入焦点 |
| `⌘O` | 打开文件夹 |

</div>

---

## 📄 许可证

SwiftCull 基于 [MIT License](./LICENSE) 开源。
