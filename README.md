# 恒时 Aeterna

Aeterna 是一个面向考场一体机/投影场景的考试看板系统，提供考试计划编排、全屏放映、时间同步与关键节点提醒。

## 核心功能

- 多天考试计划编排，支持导入/导出 JSON
- 放映模式实时看板：时钟、科目、倒计时、进度
- 时间源切换：离线手动、内网同步、云端拉取
- 关键节点提醒：开考前、开考、结束前、结束
- 动态主题：支持明暗模式与多套主题配色实时切换

## 技术栈

- Flutter 3.x / Dart 3.x
- `shared_preferences`：本地配置持久化
- `ntp`：网络时间同步
- `window_manager`：桌面窗口控制
- `url_launcher`：外链跳转（GitHub 主页/仓库地址）

## 快速开始

```bash
flutter pub get
flutter run -d linux
```

可用设备查看：

```bash
flutter devices
```

## 项目结构

- `lib/app/`：应用壳层、路由、全局主题注入
- `lib/core/`：时间控制与配置管理
- `lib/features/home/`：启动器与关于页面
- `lib/features/monitor/`：放映看板
- `lib/features/schedule/`：计划编排
- `lib/features/settings/`：系统设置与主题切换
- `lib/theme/`：设计令牌与主题构建

## 开源协议

本项目基于 **Apache License 2.0** 开源。

- 你可以用于商业项目、修改和再发布
- 分发时请保留许可证与版权声明

## 维护者

- GitHub: [ziyi127](https://github.com/ziyi127)
- Avatar: ![ziyi127 avatar](https://github.com/ziyi127.png)
- 仓库主页: [https://github.com/ziyi127](https://github.com/ziyi127)

## 说明

如果你准备将本地项目发布到 GitHub：

1. 先在 GitHub 创建新仓库（例如 `Aeterna`）
2. 再在本地目录初始化 Git 并推送

```bash
git init
git add .
git commit -m "chore: initial publish"
git branch -M main
git remote add origin https://github.com/ziyi127/Aeterna.git
git push -u origin main
```
