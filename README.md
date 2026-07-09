<div align="center">

![Aeterna](https://raw.githubusercontent.com/ziyi127/Aeterna/main/Aeterna.jpeg)

# Aeterna

**下一代跨平台桌面播放器 · Rust + Qt6 原生构建**

[![License](https://img.shields.io/badge/license-GPL--3.0-blue.svg)](LICENSE)
[![Rust](https://img.shields.io/badge/Rust-1.85%2B-orange)](https://www.rust-lang.org)
[![Qt](https://img.shields.io/badge/Qt-6.7%2B-brightgreen)](https://www.qt.io)
[![Platform](https://img.shields.io/badge/Platform-Windows%20%7C%20macOS%20%7C%20Linux-lightgrey)](https://github.com/ziyi127/Aeterna/releases)

</div>

---

## ✨ 特性

- **🎮 专业播放引擎** — 基于 Rust 构建的高性能播放核心，低延迟、高精度
- **📺 多窗口界面** — 独立的播放器窗口与编辑器窗口，支持拆分视图
- **🌐 局域网投射** — 内置 mDNS 发现 + WebSocket 投屏协议
- **🔌 插件系统** — 可扩展的插件架构，支持动态加载
- **🖥️ 跨平台原生** — Qt6 原生界面，一致的体验在 Windows / macOS / Linux
- **🎨 精致 UI** — Pinguo Design System 设计语言，支持明暗主题自动切换
- **📡 HTTP API** — 内置 REST API 服务，支持远程控制
- **⏰ NTP 校时** — 集成 NTP 时间同步服务
- **🪟 Windows UIAccess** — 支持 UIAccess 权限提升以支持全局热键

## 🖼️ 截图

> 暂无

## 🚀 快速开始

### 前置依赖

| 平台 | 依赖 |
|------|------|
| **Linux** | `qt6-base-dev`, `qt6-declarative-dev`, `libgl1-mesa-dev`, `libxkbcommon-dev`, `librsvg2-bin` |
| **macOS** | `brew install qt@6` |
| **Windows** | [Qt 6.7+](https://www.qt.io/download-qt-installer) (勾选 MSVC 2022 64-bit + Qt Declarative) |

### 从源码构建

```bash
# 克隆仓库
git clone https://github.com/ziyi127/Aeterna.git
cd Aeterna

# 构建（自动下载依赖）
cargo build --release

# 运行
./target/release/aeterna
```

> 首次构建需要下载 Rust crate 依赖，耗时约 5-15 分钟（取决于网络环境）。

### 下载预编译版本

前往 [Releases](https://github.com/ziyi127/Aeterna/releases) 下载对应平台的压缩包：

| 平台 | 架构 | 后缀 |
|------|------|------|
| Linux | x86_64 | `.tar.gz` |
| Linux | i686 | `.tar.gz` |
| Windows | x86_64 | `.zip` |
| Windows | x86 | `.zip` |
| macOS | Intel | `.tar.gz` |
| macOS | Apple Silicon | `.tar.gz` |

> 注意：运行时需确保系统已安装 Qt6 运行时库。

## 🏗️ 项目结构

```
Aeterna/
├── src/
│   ├── main.rs              # 入口 + 引擎初始化
│   ├── window_manager.rs    # 窗口管理 + 单实例锁
│   ├── ui_access.rs         # Windows UIAccess 权限
│   ├── core/                # 核心数据模型与播放引擎
│   ├── ui/                  # QML 界面后台逻辑
│   ├── services/            # HTTP API、NTP、投射服务
│   └── plugins/             # 插件系统
├── resources/
│   ├── qml/                 # Qt QML 界面文件
│   ├── icons/               # 图标资源
│   └── resources.qrc        # Qt 资源描述
├── build.rs                 # 构建脚本 (QRC → qrc! 宏)
└── Cargo.toml               # Rust 项目配置
```

## 📜 版本历史

| 版本 | 状态 | 说明 |
|------|------|------|
| **v2.0** | ✅ Beta | Rust + Qt6 重写，全新架构 |

> v2.0 使用 Rust 和 Qt6 完全重写，拥有更好的性能和更精美的界面。

## 🤝 贡献

本项目由 **ziyi127** 独立开发维护。

- 🐛 发现 Bug？请提交 [Issue](https://github.com/ziyi127/Aeterna/issues)
- 💡 有想法？欢迎提交 Pull Request
- ⭐ 喜欢这个项目？给个 Star 支持一下！

## 📄 许可证

[GNU General Public License v3.0](LICENSE)

> [!IMPORTANT]
> Apache2.0许可证已停用，现在使用新的许可证方案，请查阅最新版许可证！(๑•̀ㅂ•́)و✧

版权所有 © 2026 [ziyi127](https://github.com/ziyi127)

---

<div align="center">
  <sub>Built with ❤️ by <a href="https://github.com/ziyi127">ziyi127</a></sub>
  <br>
  <sub>基于 Rust + Qt6 · 跨平台原生桌面应用</sub>
</div>
