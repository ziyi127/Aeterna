<div align="center">

![Aeterna](https://raw.githubusercontent.com/ziyi127/Aeterna/main/Aeterna.jpeg)

# Aeterna

**可靠、清晰的考试日程播放与考场计时系统**

[![License](https://img.shields.io/badge/license-GPL--3.0-blue.svg)](LICENSE)
[![Rust](https://img.shields.io/badge/Rust-1.85%2B-orange)](https://www.rust-lang.org)
[![Qt](https://img.shields.io/badge/Qt-6.7%2B-brightgreen)](https://www.qt.io)
[![Platform](https://img.shields.io/badge/Platform-Windows%20%7C%20macOS%20%7C%20Linux-lightgrey)](https://github.com/ziyi127/Aeterna/releases)

</div>

## Aeterna 能做什么

- **按真实时间自动推进**：在开始、结束和结束前提醒时自动切换状态，减少人工计时压力。
- **面向大屏的播放器**：独立播放窗口，清楚展示当前科目、倒计时、考场号与公告。
- **可视化日程编辑**：创建、排序和校验多场考试；开始时间、结束时间、提醒时间和材料清单一目了然。
- **多屏与远程能力**：可发现局域网设备进行投屏，并提供 HTTP API 供集成控制。
- **更可靠的时间**：支持 NTP 校时，适合对时间准确性有要求的考场。
- **适配你的环境**：Windows、macOS 和 Linux 均可使用，支持浅色、深色和高对比度外观。

## 使用前准备

1. 从 [Releases](https://github.com/ziyi127/Aeterna/releases) 下载与你的系统对应的 **portable** 压缩包（推荐）。它只包含 Aeterna 实际使用的 Qt 运行时、插件和 QML 模块，不包含 Qt SDK、头文件或构建工具。
2. 解压后运行 Aeterna：Linux 运行 `bin/aeterna`，Windows 运行 `aeterna.exe`，macOS 打开 `aeterna.app`。
3. 高级用户也可选择 **bare** 压缩包；它不包含任何 Qt 运行时，需自行安装与程序的版本、编译器 ABI 和架构匹配的 Qt 6、QML 模块及平台插件。
4. 在首页选择“新建/编辑日程”，填写考试信息并保存为 JSON。
5. 载入日程后打开播放器。开始前请核对系统时间，必要时在设置中进行 NTP 校时。

> 请在正式考试开始前，用一份测试日程完整演练一次提醒、全屏显示和退出密码流程。

## 日程文件格式

日程文件是 UTF-8 编码的 JSON。时间使用 `YYYY-MM-DD HH:MM:SS`，`alertTime` 表示结束前几分钟提醒（`0` 表示关闭提醒）。

```json
{
  "examName": "2026 年春季期末考试",
  "message": "请遵守考场纪律，听从监考安排。",
  "examInfos": [
    {
      "name": "语文",
      "start": "2026-07-01 08:30:00",
      "end": "2026-07-01 10:30:00",
      "alertTime": 10,
      "materials": [
        { "name": "答题卡", "quantity": 1, "unit": "张" }
      ]
    }
  ]
}
```

保存前，Aeterna 会提示必填项、无效时间和可能重叠的场次。存在时间重叠的日程不能进入播放器。

## 从源码构建

### 开发依赖

| 平台 | 依赖 |
|------|------|
| **Linux** | `qt6-base-dev`, `qt6-declarative-dev`, `libgl1-mesa-dev`, `libxkbcommon-dev`, `librsvg2-bin` |
| **macOS** | `brew install qt@6` |
| **Windows** | [Qt 6.7+](https://www.qt.io/download-qt-installer)（勾选 MSVC 2022 64-bit 与 Qt Declarative） |

```bash
git clone https://github.com/ziyi127/Aeterna.git
cd Aeterna
cargo build --release
./target/release/aeterna
```

首次构建会下载 Rust 依赖；请使用稳定版 Rust 1.85 或更高版本。

## 常见问题

**播放器提示日程无效？** 请检查每场考试的名称、开始/结束时间是否完整，结束是否晚于开始，以及场次是否重叠。

**时间不准确？** 检查操作系统时间，并在设置中启用或手动执行 NTP 校时。

**无法启动或界面缺少组件？** 请优先下载 Release 中的完整压缩包；从源码运行则需要安装上表列出的 Qt 6 开发依赖。

## 开发者信息

项目采用 Rust + Qt 6 构建。目录说明：

```
src/core/       考试数据、校验与播放状态机
src/ui/         QML 后端与窗口逻辑
src/services/   NTP、HTTP API 与投屏服务
resources/qml/  界面与设计系统
```

## 版本与发布

当前正式版本为 **v2.0.6**。推送与 `Cargo.toml` 版本一致的 `vX.Y.Z` 标签会自动执行质量检查，并发布以下六个资产及 SHA-256 校验和：

| 平台 | 推荐便携包 | 高级用户 bare 包 |
|------|------------|------------------|
| Linux x86_64 | `aeterna-X.Y.Z-linux-x86_64-portable.tar.gz` | `aeterna-X.Y.Z-linux-x86_64-bare.tar.gz` |
| Windows x86_64 | `aeterna-X.Y.Z-windows-x86_64-portable.zip` | `aeterna-X.Y.Z-windows-x86_64-bare.zip` |
| macOS Apple Silicon | `aeterna-X.Y.Z-macos-arm64-portable.zip` | `aeterna-X.Y.Z-macos-arm64-bare.tar.gz` |

Linux 便携包是按 ELF/QML 依赖裁剪的 Qt runtime bundle，不是 AppImage，仍依赖兼容的系统图形、驱动、字体和基础库；Windows 便携包由 windeployqt 按 PE/QML 依赖部署；macOS 便携包由 macdeployqt 按 Mach-O/QML 依赖部署。三个平台的 bare 包都不携带 Qt 运行时。macOS 便携包目前未签名、未公证，首次启动可能需要在 Finder 中右键选择“打开”。

## 贡献

- 发现问题请提交 [Issue](https://github.com/ziyi127/Aeterna/issues)。
- 欢迎通过 Pull Request 贡献改进。

## 许可证

[GNU General Public License v3.0](LICENSE)

版权所有 © 2026 [ziyi127](https://github.com/ziyi127)
