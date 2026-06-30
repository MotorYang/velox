<p align="center">
  <img src="Velox/Supporting%20Files/app_logo.png" alt="Velox Logo" width="120">
</p>

<h1 align="center">Velox</h1>

<p align="center">
  使用 Swift 构建的 macOS 原生终端、SSH 与 SFTP 客户端。
</p>

<p align="center">
  <a href="README.md">English</a> | 简体中文
</p>

<p align="center">
  <a href="https://motoryang.github.io/velox/">工具介绍页面</a>
</p>

## 项目简介

Velox 是一款面向 macOS 的原生终端与 SSH/SFTP 客户端。项目使用 SwiftUI 和 AppKit 构建桌面体验，使用 SwiftTerm 渲染终端，使用 Citadel、SwiftNIO 和 Swift Crypto 提供纯 Swift 的 SSH 与 SFTP 能力。

当前项目重点是把本地终端、远程 Shell、服务器目录、凭据管理和文件传输放在同一个轻量窗口里，减少在 Terminal、Finder 和独立 SFTP 工具之间切换的成本。

## 功能特性

- 本地终端窗口，支持当前工作目录标题同步。
- SSH 远程 Shell 连接，支持密码、RSA 私钥和 Ed25519 私钥认证。
- SFTP 文件面板，支持远程目录浏览、路径跳转、上传、下载、重命名和删除。
- Finder 拖拽上传文件或目录到远程 SFTP 目录。
- 多服务器资料管理，支持文件夹分组、复制、编辑、删除和双击连接。
- 密码和私钥口令通过 macOS Keychain 存储。
- 连接断开后的自动重连调度。
- 可配置终端字体、字号、窗口尺寸、亮色/暗色外观和透明度。
- macOS 菜单快捷入口：
  - `Command-P`：打开服务器管理器。
  - `Command-F`：打开远程文件面板。

## 技术栈

- Swift / SwiftUI / AppKit
- SwiftTerm 1.13.0
- Citadel 0.12.1
- SwiftNIO 2.101.2
- Swift Crypto 3.15.1
- macOS Keychain Services
- Xcode project + Swift Package Manager

依赖版本以 `Velox.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` 为准。

## 系统要求

- macOS 26.5 或更高版本
- Xcode 26 或兼容版本
- Swift Package Manager 网络访问权限，用于首次解析依赖

> 当前 Xcode 工程的 `MACOSX_DEPLOYMENT_TARGET` 为 `26.5`。如果需要支持更低版本 macOS，请先确认 SwiftUI、AppKit API 和第三方依赖的兼容性，再调整工程设置。

## 构建与运行

1. 克隆仓库：

   ```bash
   git clone https://github.com/MotorYang/velox.git
   cd Velox
   ```

2. 使用 Xcode 打开工程：

   ```bash
   open Velox.xcodeproj
   ```

3. 在 Xcode 中选择 `Velox` scheme。

4. 等待 Swift Package Manager 解析依赖后，点击 Run。

也可以通过命令行构建：

```bash
xcodebuild -project Velox.xcodeproj -scheme Velox -configuration Debug build
```

## 使用方式

### 本地终端

启动应用后会进入本地终端。窗口标题会跟随本地用户、主机名和工作目录变化。

### 添加服务器

1. 按 `Command-P` 打开服务器管理器。
2. 点击 `New Server`。
3. 填写名称、主机、端口、用户名和认证方式。
4. 保存后双击服务器连接。

认证方式：

- Password：密码会保存到 macOS Keychain。
- RSA Key：选择本地 RSA 私钥文件。
- Ed25519 Key：选择本地 Ed25519 私钥文件，可选私钥口令。

### 文件传输

连接 SSH 后，Velox 会打开远程文件面板：

- 双击目录进入远程路径。
- 双击文件下载。
- 拖拽本地文件或目录到面板上传。
- 使用行操作重命名或删除远程文件。
- 在路径栏输入远程路径后回车跳转。

## 自动发布

推送代码到 `production` 分支会触发 `Build and Release` GitHub Actions workflow。该流程会使用 Release 配置构建 Apple Silicon 版 macOS App，将 `Velox.app` 打包为 `Velox_arm64_v<version>.zip`，并发布到 [GitHub Releases](https://github.com/MotorYang/velox/releases)。

如果没有 Apple Developer Program 账号，当前产物可以做到 ad-hoc 签名，但不能 notarize。macOS Gatekeeper 首次启动时仍会显示“Apple 无法验证此 App”的提示。

ad-hoc 版本可以通过以下方式打开：

1. 右键点击 `Velox.app`，选择“打开”，再确认“打开”。
2. 或首次被拦截后，到“系统设置 > 隐私与安全性”里选择“仍要打开”。
3. 仅本地测试时，也可以执行 `xattr -dr com.apple.quarantine /Applications/Velox.app` 移除 quarantine 标记。

如果发布 runner 是自托管环境，并且需要使用 `127.0.0.1:10808` 本地代理，请把仓库变量 `USE_LOCAL_PROXY` 设置为 `true`。如果使用 GitHub-hosted runner，不要启用该变量，除非代理确实存在于 runner 环境内部。

要发布不会被 Gatekeeper 提示“无法验证开发者”的 macOS 产物，需要加入 Apple Developer Program，并配置这些 GitHub 仓库 Secrets：

- `APPLE_CERTIFICATE_BASE64`：Developer ID Application `.p12` 证书的 base64 内容。
- `APPLE_CERTIFICATE_PASSWORD`：`.p12` 证书密码。
- `APPLE_ID`：用于 notarization 的 Apple ID 邮箱。
- `APPLE_APP_SPECIFIC_PASSWORD`：Apple ID 的 app-specific password。
- `APPLE_TEAM_ID`：Apple Developer Team ID。

当上述 notarization secrets 全部存在时，发布 workflow 会使用 Developer ID 签名 `Velox.app`，提交 Apple notarization，staple 公证票据，用 `spctl` 校验，并发布 `notarized` zip 产物。缺少这些 secrets 时，workflow 会回退为 `adhoc` zip 产物。

## 项目结构

```text
Velox/
  App/                  应用入口、菜单命令和 AppDelegate
  Core/                 Keychain、SSH 认证、字体和输入法辅助
  Models/               服务器资料、远程文件和设置模型
  Services/             SSH/SFTP 会话、窗口样式和服务器资料存储
  Views/
    Main/               主窗口容器
    Terminal/           SwiftTerm / AppKit 桥接和终端窗口
    SFTP/               远程文件面板、传输冲突处理和本地终端桥接
    ServerManager/      服务器管理器
    Settings/           设置界面
  Supporting Files/     资源、图标和 entitlements
```

## 安全与隐私

- 服务器资料保存在 `UserDefaults`，密码和私钥口令保存在 macOS Keychain。
- 私钥文件本身不复制进应用数据目录，服务器资料只保存私钥路径。
- 当前 SSH host key 校验策略在代码中使用接受任意主机密钥的方式，适合开发阶段快速连接；用于生产环境前建议实现 known_hosts 校验或指纹确认流程。

## 贡献

欢迎提交 Issue 和 Pull Request。建议改动前先确认：

- 新功能是否符合 macOS 原生交互。
- SSH/SFTP 相关改动是否保持异步执行，避免阻塞主线程。
- UI 状态更新是否回到 `MainActor`。
- 涉及凭据的改动是否继续使用 Keychain，不把密钥或密码写入明文存储。

## 开源协议

本项目基于 MIT License 开源，详见 [LICENSE](LICENSE)。
