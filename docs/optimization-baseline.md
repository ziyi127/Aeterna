# Aeterna 优化基线与验收

本文件记录优化项目的统一基线和验收阈值，确保每次改动可量化验证。

## 1. 统一执行命令

```bash
flutter pub get
flutter analyze
flutter test
```

平台构建 smoke：

```bash
flutter build linux --debug
flutter build web --profile
flutter build windows --debug
flutter build macos --debug
flutter build apk --debug
```

## 2. 基线指标（首轮采样）

建议在同一台机器、同一电源模式下采样 3 次并取中位数。

- 启动耗时（冷启动）
- 空闲 CPU（主页面停留 5 分钟）
- 内存波动（监控页运行 30 分钟）
- 构建耗时（linux/web/android）
- 产物体积（web 构建目录、apk、linux 可执行）

可记录格式：

| 指标 | 基线值 | 目标值 | 当前值 | 备注 |
| --- | --- | --- | --- | --- |
| 冷启动耗时 | - | <= 基线 * 0.85 | - | |
| 监控页 30 分钟内存波动 | - | <= 2 MB 持续漂移 | - | |
| 计划持久化写入频率 | - | <= 1 次/10 秒 | - | |
| Linux 构建耗时 | - | <= 基线 * 0.9 | - | |
| Web 产物体积 | - | <= 基线 * 0.85 | - | |

## 3. 验收闸门

- 质量闸门：analyze 无新增 error。
- 测试闸门：核心时间模块测试全部通过。
- 性能闸门：监控页长时间运行无持续内存爬升。
- 交付闸门：至少 Linux 与 Web 构建通过，其余平台有可追踪结论。

## 4. 采样记录

### 2026-04-04

- 待采集。
