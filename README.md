# 每秒拍照

实验中常需定时记录仪器读数，研究人员却不得不守在设备旁。每秒拍照通过定时拍摄仪器屏幕，帮助减少人工盯守和抄录；启用数字监控后，还能识别并记录框选区域的读数，在数值满足条件时发送附原图的邮件提醒。

## 安装

- 支持 Apple 芯片、macOS 13 及以上；暂无 Intel 版本。
- 需要 imageSnap 和 Python 3.9 及以上。App 会自动查找本机兼容的 Python 3；数字识别使用 macOS Vision。可用 [Homebrew](https://brew.sh/) 安装依赖：`brew install imagesnap python`。
- 从 [Releases](https://github.com/zhushi-lab/instrument-camera-monitor/releases) 下载 `instrument-camera-monitor-macos-arm64.zip`，解压后将 `每秒拍照.app` 移入“应用程序”。下载包**未经过 Apple 公证**；首次打开若被拦截，可按 [Apple 的说明](https://support.apple.com/zh-cn/guide/mac-help/mh40617/mac) 在“隐私与安全性”中允许打开，并授予摄像头权限。

## 使用

1. 启动 App，设置拍照间隔、摄像头和保存位置。默认位置是 `~/Pictures/每秒拍照/`，可临时另存或修改默认位置。App 会试拍 3 张，并估算磁盘可拍时长。
2. 选择“仅拍照”或“拍照并监控数字”。监控时，在预览图上拖动、缩放方框，只框住一个读数；调整摄像头后，点“重新拍照”获取新画面。
3. 输入提醒条件：范围 `10~20`（含边界）、单值 `49` 或多值 `49、199、299`。支持负数和小数；读数有波动时建议使用范围。
4. 监控模式需设置 SMTP 发件邮箱、客户端授权码和收件邮箱；仅拍照无需邮箱。授权码保存在 macOS 钥匙串，设置可在启动窗口或拍摄中的菜单栏修改。
5. 设置总时长并开始。菜单栏“📷 拍照中”可打开照片目录或提前停止。

每次拍摄会在所选位置建立独立文件夹，JPEG 直接保存在其中。`capture.log` 记录拍摄情况；监控模式还会生成 `recognition.csv` 和 `monitor.log`。同一读数连续两张命中才发送提醒，并附上触发照片；读数离开后再次命中可重新提醒。

## 使用限制

- 拍照间隔受摄像头和系统负载影响；App 分段运行 imageSnap，每段最多拍 60 张，以抑制长时间运行的内存增长。
- 可拍时长按当前磁盘空间和试拍照片估算，实际时长会受其他程序占用、照片大小变化和摄像头故障影响。异常原因见 `capture.log`。
- 模糊、反光、遮挡或数码管闪烁可能造成误识别。正式实验前请短时试拍，检查 `recognition.csv`。邮件提醒**不能代替设备安全联锁**。
- 带识别的连续 4–6 小时运行尚未完成整段验证；目前已验证构建和短时实际拍摄。

## 从源码构建

在 Apple 芯片 Mac 上安装 Xcode Command Line Tools（`xcode-select --install`），进入本仓库目录运行：

```bash
bash build.sh
```

产物位于 `dist/arm64/`，包括 App、ZIP 和 SHA256 校验文件。发布页的 ZIP 改用英文文件名。可用 `bash install.sh` 安装到 `~/Applications`；已有同名 App 时不会覆盖。构建使用临时签名，没有 Developer ID 签名或公证。

## 隐私与许可

照片、日志和邮箱设置保存在本机；SMTP 授权码保存在钥匙串。仅在启用提醒且条件命中时，照片才通过用户配置的 SMTP 发往收件邮箱。项目不使用分析服务。反馈问题时，请先移除照片、日志或设置中的个人信息。源码采用 [MIT 许可](LICENSE)；imageSnap 遵循其自身许可。
