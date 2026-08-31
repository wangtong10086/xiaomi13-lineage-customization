# Xiaomi 13 LineageOS 定制工具

[English](README.md) | 简体中文

本仓库收录 Xiaomi 13（`fuxi`）从 HyperOS 衍生环境迁移到 LineageOS / Android 16 后使用的小型、可审阅定制项。

> [!CAUTION]
> 这是源码与操作手册仓库，不是通用刷机包。所有写入操作都与设备、应用、ROM 和版本相关。执行前必须阅读对应文档、在本地备份并核对明确目标。

## 内容

- `health/`：限制范围的开机权限修复，仅处理 Qualcomm 电池 input-suspend 节点。
- `launcher/`：导出、规划并应用扁平化 MIUI Launcher 布局。
- `magisk/`：面向 Xiaomi TSM/OMAPI 兼容的可复现 Magisk 模块源码。
- `root/`：只读状态采集，以及版本锁定、备份优先的 MIUI 天气和相册/MiuiCore 挂载可见性修复。
- `push/`：XMSF systemize、受限 GMS/FCM 恢复、逐应用 XMSF 注册、Thanox 事件采集与微信进程回收。
- `settings/`：导出 Android 设置/输入法状态，并向单个明确设备应用审阅后的白名单。
- `wallet/`：Xiaomi Wallet 签名/运行时兼容脚本及恢复说明。
- `docs/`：升级、回滚及具体子系统说明。

仓库有意排除 launcher/LSPosed/应用私有数据库、真实包清单或 denylist、钱包数据、设备日志、token、联系人和消息正文。这些内容只能作为本地输入保存在被忽略的 `work/` 目录。

所有写入脚本都先创建备份并要求明确目标参数。布局导入还要求显式输入文件；应用前必须人工审阅。

MIUI 天气和 MIUI 相册依赖 `MiuiCore` Magisk 覆盖提供的框架文件，因此相关进程不能被 denylist 隐藏挂载。修改 root 隐藏配置前，请分别阅读 `docs/miui-weather-overlay-visibility.md` 与 `docs/miui-gallery-overlay-visibility.md`。

本仓库不提交 Xiaomi 专有 APK。需要 APK 的 Magisk 构建脚本只接受本地明确输入，并在打包前校验 SHA-256。

## 微信无常驻进程推送

当前方案让微信保持 `stopped=false`，由 FCM/Thanox 传递通知并保留正确会话跳转；主动使用或点击通知后，再按配置的短延迟回收微信进程。它不使用 `force-stop`，也不恢复微信私有数据库。修改超时、组件或 Thanox 规则前，必须阅读 [微信 FCM/Thanox 操作手册](docs/wechat-push-without-resident-process.md)。

## 状态、贡献与安全

这些脚本记录的是一套本地验证过的 `fuxi` 配置，公开目的是便于审阅与适配。精确版本检查是安全边界；单一版本成功不表示其他版本兼容。

提交 PR 前请阅读 [CONTRIBUTING.zh-CN.md](CONTRIBUTING.zh-CN.md)。漏洞或敏感信息暴露请使用 GitHub 私密漏洞报告；参见 [SECURITY.md](SECURITY.md)。
