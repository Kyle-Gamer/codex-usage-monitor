# Codex Usage Monitor

一个独立的 macOS 菜单栏应用，用于显示 Codex 主额度的剩余百分比和下一次重置时间。

## 构建与安装

需要 macOS 13 或更高版本，以及 Swift 命令行工具。项目不修改 ChatGPT.app、`~/.codex` 配置或凭证。由于只安装了 Command Line Tools 的 Mac 不一定带 XCTest，项目包含一个不依赖 Xcode 的 Swift 测试运行器。

```sh
cd "Codex Usage Monitor"
./Scripts/build_app.sh --install
open "$HOME/Applications/Codex Usage Monitor.app"
```

只构建不安装：

```sh
./Scripts/build_app.sh
```

生成分享用 ZIP：

```sh
./Scripts/package_app.sh
```

当前默认生成 Apple Silicon (`arm64`) 的临时签名 ZIP。需要兼容 Intel Mac 时：

```sh
./Scripts/package_app.sh --universal
```

产物会写入 `Dist/`，同时生成同名 `.sha256` 校验文件。

## 分发方式

### 自己的 MacBook 或可信的个人设备

把 `Dist/` 下的 ZIP 通过 AirDrop、网盘或 U 盘传过去，解压后将 `Codex Usage Monitor.app` 放到 `~/Applications` 或 `/Applications`，然后双击启动。首次被 Gatekeeper 拦截时，在 Finder 中右键应用选择“打开”，再确认一次。

这类临时签名包只适合自己或明确知情的设备。不要把 `auth.json`、access token 或 refresh token 一起打包；每台设备都必须自行安装并登录 ChatGPT/Codex Desktop。

### 分享给其他用户

正式分发建议加入 Apple Developer Program，创建 `Developer ID Application` 证书，然后用证书签名并提交公证：

```sh
./Scripts/package_app.sh --universal \
  --developer-id="Developer ID Application: Your Name (TEAMID)"
xcrun notarytool submit "Dist/Codex Usage Monitor-1.0.0-universal-developer-id.zip" \
  --keychain-profile "YOUR_NOTARY_PROFILE" --wait
xcrun stapler staple "Build/Codex Usage Monitor.app"
ditto -c -k --sequesterRsrc --keepParent \
  "Build/Codex Usage Monitor.app" \
  "Dist/Codex Usage Monitor-1.0.0-universal-notarized.zip"
spctl --assess --type execute --verbose=4 "Build/Codex Usage Monitor.app"
```

要分发给用户的是重新打包后的 `*-notarized.zip`，因为公证票据是在 `stapler` 步骤写入 App 的。公证后的 ZIP 或 DMG 才适合作为面向其他用户的正常下载包；用户通常无需执行“移除隔离属性”或绕过 Gatekeeper。当前机器没有 Developer ID 证书，因此本项目现在能直接产出的是临时签名包。

### 运行前提

目标 Mac 需要 macOS 13 或更高版本，并安装 ChatGPT Desktop/Codex。这个显示器通过 ChatGPT 应用内置的 Codex App Server 读取当前登录账户额度，不携带账户凭证，也不会把你的额度分享给其他用户。

单独运行核心测试：

```sh
swift run -c debug CodexUsageMonitorTests
```

卸载：

```sh
./Scripts/uninstall.sh
```

## Token 活动

状态栏默认不显示 Token 活动。可在面板设置中开启“在状态栏显示今日 Token 用量”。面板展示今日、本月、累计消耗和单日峰值，今日与本月同时显示 API 价格估值。数据来自 Codex App Server 的 `account/usage/read`，每日桶按返回的日期匹配本机日历。

OpenAI 官方 API 价格按模型和输入、缓存输入、输出类别定价，而 Profile 仅返回 token 总量，不包含模型和 token 类别拆分。因此当前美元值只是将总量按 `gpt-5.3-codex` 标准输入价（每百万 Token $1.75）折算的参考估值，不是实际账单，也不是 Codex 订阅消费金额。该价格可能调整。

## 数据来源

应用启动 ChatGPT 内置的 Codex App Server，通过 JSON-RPC/NDJSON 请求 `account/rateLimits/read` 和 `account/usage/read`，并监听 `account/rateLimits/updated`。应用不读取 `auth.json`，不保存 access token 或 refresh token。App Server 推送到达时即时更新，并每 60 秒主动校准一次。

如果当前 Codex 版本返回了 banked reset（额度重置机会），面板会显示可用次数、机会标题、过期时间和倒计时。点击“重置”后会先弹出二次确认，再调用 `account/rateLimitResetCredit/consume`；请求使用一次性幂等键，成功后会重新读取额度。完整重置会同时刷新 Codex 的 5 小时和 7 天窗口。旧版 App Server 未提供该字段时，面板继续正常显示额度，不会发起猜测性的重置请求。

顶部显示默认为“更紧张的额度”，也可以在面板设置中固定显示 5 小时或 7 天窗口。若用户选择的窗口暂时没有返回，界面会保留设置并临时回退到可用窗口，菜单栏中的 `*` 表示发生了回退。面板不提供手动刷新按钮，应用会自动轮询并在收到 App Server 推送时立即更新。

## 目录

- `Sources/CodexUsageMonitorCore`：协议模型、窗口识别、显示策略、倒计时和预警逻辑。
- `Sources/CodexUsageMonitor`：App Server 子进程、菜单栏状态项、SwiftUI 面板和登录启动。
- `Tests`：核心逻辑和协议解析测试。
- `Scripts`：构建、临时签名、安装和卸载脚本。
