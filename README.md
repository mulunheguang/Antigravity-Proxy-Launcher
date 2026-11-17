# Antigravity Proxy Launcher for macOS 🚀

<p align="center">
  <b>Antigravity App / IDE 透明代理启动器</b>
</p>

> 点击图标，自动检查本地 SOCKS5 代理、准备 SNI 中继并打开 Antigravity。适用于 Antigravity App 与 Antigravity IDE，支持菜单栏配置、代理检测和日志查看。

---

## 项目介绍

Antigravity 的部分服务请求可能无法正确使用系统代理，导致登录、模型请求或 AI 对话连接异常。本项目提供一个独立的 macOS 启动入口，通过 **hosts 域名映射**与 **TLS SNI 中继**，将指定服务域名的 HTTPS 流量交给本地 **SOCKS5 代理**。

日常使用时，先打开自己的代理软件，再点击 Dock 中的启动器图标。它会完成代理检查与中继准备，然后打开配置中的 Antigravity 应用。

**App 和 IDE 都可以使用。** 中继通过系统 hosts 映射处理已配置域名的请求。中继运行后，App 与 IDE 访问这些域名时都可以使用它。

`appPath` 决定启动器点击后打开哪个应用。如果 App 和 IDE 分别安装，可以将它设为常用应用的路径，再手动打开另一个应用，共用已经运行的中继。

[项目仓库](https://github.com/mulunheguang/Antigravity-Proxy-Launcher)

---

## 功能特性

- 🚀 **一键启动** — 检查代理、准备中继、打开 Antigravity。
- 🖥️ **App / IDE 适用** — 为两者访问已覆盖域名的请求提供代理转发。
- 🔌 **透明转发** — hosts 映射配合 TLS SNI 中继，连接本地 SOCKS5 上游。
- ⚙️ **菜单栏配置** — 通过屏幕顶部的 **AG** 修改代理端口和应用路径。
- 🔍 **实际请求检测** — 验证 SOCKS5 建隧道、TLS 证书及 HTTPS 响应。
- 📋 **日志与清理** — 查看中继日志，停止时清理启动器添加的域名映射。
- ♻️ **环境复用** — 重复点击时检查并复用健康的中继。

> 关闭 Antigravity App 或 IDE 后，中继继续运行。需要停止代理时，使用 **AG → 停止代理并退出启动器**。

---

## 快速开始

### 1. 环境准备

- **Apple Silicon Mac**，即 M 系列芯片，macOS 12.0 或更新版本。
- 已安装 Antigravity App 或 Antigravity IDE。
- 本地代理软件提供**无认证 SOCKS5** 入口。
- 具备本机管理员授权权限。

从源码构建时，先安装 Apple 命令行工具。已安装的用户可以跳过。

```bash
xcode-select --install
```

### 2. 下载并构建

```bash
git clone https://github.com/mulunheguang/Antigravity-Proxy-Launcher.git
cd Antigravity-Proxy-Launcher
./scripts/build-launcher.sh
```

构建完成后，启动器位于以下位置。

```text
dist/Antigravity Launcher.app
```

构建脚本默认从 `/Applications/Antigravity.app` 读取图标。如果应用位于其他位置，可传入实际的 `.app` 完整路径，例如下面这样。

```bash
./scripts/build-launcher.sh "$HOME/Applications/Antigravity.app"
```

这个参数用于构建时定位图标。运行时打开哪个应用，由配置文件中的 `appPath` 决定。

### 3. 放入 Dock

1. 将 **Antigravity Launcher.app** 放到固定位置，例如自己的「应用程序」文件夹。
2. 将启动器拖到 **Dock**，也就是屏幕底部或侧边的应用图标栏。
3. 打开 Shadowrocket 或其他代理软件。
4. 点击启动器，按系统提示输入本机管理员密码，等待目标应用打开。

已有构建完成的 `.app` 时，可以直接从这一步开始。

### 4. 配置代理与应用路径

启动器运行后，屏幕顶部菜单栏会出现文字 **AG**，通常在 Wi-Fi、电池、时间等图标附近。操作进行期间会显示 **AG…**。

点击 **AG → 编辑配置…**，修改下面的配置，按 **⌘S** 保存，再选择 **AG → 打开 Antigravity** 应用新配置。

```json
{
  "appPath": "/Applications/Antigravity.app",
  "proxyHost": "127.0.0.1",
  "proxyPort": 1082
}
```

- **`appPath`** — 要启动的 App 或 IDE 的完整 `.app` 路径。填写到 `.app` 为止。
- **`proxyHost`** — SOCKS5 代理的 IPv4 地址，本机代理通常使用 `127.0.0.1`。
- **`proxyPort`** — SOCKS5 代理端口，填写 `1` 到 `65535` 之间的整数。

默认值为 `127.0.0.1:1082`。请按照自己的代理软件设置填写。部分软件提供 HTTP / SOCKS5 混合端口，可以通过 **AG → 检测代理** 确认 SOCKS5 实际转发是否可用。

> 如果首次启动提示连接失败或应用路径错误，关闭提示后仍可通过 **AG → 编辑配置…** 修改，再点击 **打开 Antigravity** 重试。

---

## 配置文件位置

首次运行会为当前 Mac 用户创建独立配置，路径如下。

```text
~/Library/Application Support/Antigravity Proxy Launcher/config.json
```

找不到 **AG** 时，可以在访达按 **⌘⇧G**，粘贴下面的目录并回车，然后打开里面的 `config.json`。

```text
~/Library/Application Support/Antigravity Proxy Launcher/
```

编辑后保存，再次运行启动器即可。JSON 中的路径和地址保留双引号，端口填写为数字。

仓库中的 `launcher/config.json` 用作打包时的默认模板。已经使用过启动器的用户，应修改自己用户目录中的配置。

---

## 菜单栏操作

- **打开 Antigravity** — 读取配置，检查代理，准备或复用中继，再打开目标 App 或 IDE。
- **检测代理** — 通过配置的 SOCKS5 上游执行 HTTPS 请求。
- **编辑配置…** — 打开当前用户的配置文件。
- **查看中继日志** — 打开日志，排查连接与转发问题。
- **停止代理并退出启动器** — 停止本启动器的中继，清理它添加的 hosts 记录，刷新 DNS 缓存并退出。

中继日志位于以下位置。

```text
/var/run/antigravity-proxy-launcher/relay.log
```

---

## 工作原理

点击启动器后的流程如下。

```text
检查配置与应用路径
        ↓
通过 SOCKS5 完成 HTTPS 检测
        ↓
启动或复用本机 127.0.0.1:443 中继
        ↓
验证中继转发，并准备 hosts 域名映射
        ↓
打开配置中的 Antigravity App / IDE
```

请求的转发路径如下。

```text
App / IDE 访问已覆盖域名
        ↓
hosts 将域名解析到 127.0.0.1
        ↓
SNI 中继读取 TLS 连接中的目标域名
        ↓
通过本地 SOCKS5 代理连接目标服务器
```

当前覆盖以下七个域名，列表位于 `launcher/proxy-runtime.sh`。

```text
daily-cloudcode-pa.googleapis.com
cloudcode-pa.googleapis.com
oauth2.googleapis.com
accounts.google.com
www.googleapis.com
generativelanguage.googleapis.com
content-cloudcode-pa.googleapis.com
```

---

## 常见问题

### 为什么开机后第一次使用需要输入密码？

写入 hosts 和准备本机 443 中继需要管理员权限。重启电脑后的首次使用、中继重启或代理配置变化时，可能再次要求授权。同一次开机期间，健康的中继通常可以直接复用。

### App 和 IDE 需要分别运行一个中继吗？

可以共用同一个中继。先通过启动器准备环境，然后打开 App 或 IDE。两者访问上述域名时都会使用已准备好的转发路径。启动器的 `appPath` 用来选择点击图标后自动打开哪一个应用。

### 检测成功，为什么显示 HTTP 404？

检测请求访问 Google API 根路径，服务器可能返回 HTTP 404。SOCKS5 建隧道、TLS 证书验证和服务器响应均完成时，说明这次 HTTPS 请求的转发已完成。App 和 IDE 中的具体功能可以结合实际操作与中继日志确认。

### 提示本机 443 端口被占用怎么办？

先停止旧版代理中继或其他占用本机 443 端口的服务，再通过启动器重试。

### 退出 Antigravity 后，如何关闭代理？

点击 **AG → 停止代理并退出启动器**，按提示授权。此操作会清理本启动器创建的中继和 hosts 记录。

---

## 适用范围与运行说明

- **代理协议** — 上游需要支持无认证 SOCKS5。检测会检查实际 HTTPS 请求。
- **域名范围** — 当前转发上述七个域名的 HTTPS 流量。其他域名由应用和系统网络设置处理。
- **系统级映射** — hosts 对整台 Mac 生效，其他程序访问相同域名时也会使用中继。
- **按需启动** — 通过点击启动器准备环境，当前版本没有配置开机启动任务。
- **兼容验证** — 已在本机验证 App 启动和中继转发，并收到 IDE 可正常对话的使用反馈。不同版本、模型与功能涉及的域名可能不同，可结合日志确认并按需扩展。

---

## 项目结构

```text
Antigravity-Proxy-Launcher/
├── launcher/
│   ├── Launcher.swift          # 原生启动器与 AG 菜单
│   ├── Info.plist              # 应用信息与系统版本要求
│   ├── config.json             # 默认配置模板
│   └── proxy-runtime.sh        # 中继起停、hosts 与转发校验
├── scripts/
│   └── build-launcher.sh       # 构建独立 macOS 应用
├── src/
│   └── relay.c                 # TLS SNI 中继
├── dist/                       # 本机构建输出
├── vscode-extension/           # 保留的扩展源码
└── LICENSE
```

---

## 致谢与许可证

本项目基于 raybz 的 Antigravity-Proxy 继续开发，增加了独立 macOS 启动器、菜单栏配置及兼容性修复。采用 MIT 许可证，并保留原作者版权声明。启动器图标在构建时从本机已安装的 Antigravity 应用读取。

[原项目](https://github.com/raybz/Antigravity-Proxy) · [MIT 许可证](LICENSE)
