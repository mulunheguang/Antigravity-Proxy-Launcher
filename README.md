# Antigravity Proxy Launcher

**给 Antigravity App 使用的独立透明代理启动器。** 点击一个图标，即可检查本地代理、准备代理中继，再打开 Antigravity，日常使用无需先打开 IDE。

当 Antigravity 的部分服务请求无法正确使用本地代理，出现登录或 AI 服务连接问题时，本项目可以将已配置的服务域名流量转发到本地 SOCKS5 代理。转发效果取决于代理可用性与域名覆盖范围。

本项目通过 **hosts 域名映射 + TLS SNI 中继 + SOCKS5 上游** 实现按域名透明转发。当前覆盖的七个域名列在文末。启动器适用于 Apple Silicon（M 系列）Mac。

## 能做什么

- 点击启动器，自动检查代理并打开 Antigravity App。
- 将指定 Google / Antigravity 服务域名的 HTTPS 流量交给本地 SOCKS5 代理。
- 在屏幕顶部的 **AG** 菜单中修改配置、检测代理、查看日志和停止中继。
- 重复点击时检查并复用健康的中继。
- 准备失败时回滚本次创建的中继和域名映射。

## 使用条件

- Apple Silicon（M 系列）Mac，macOS 12.0 或更新版本。
- 已安装 Antigravity App，默认路径为 `/Applications/Antigravity.app`。
- 本地代理软件正在运行，并提供**无认证 SOCKS5** 入口。
- 具备管理员授权权限，用于写入 hosts 和监听本机 443 端口。
- 从源码构建时，需要安装 Apple Xcode Command Line Tools。

默认代理地址为 `127.0.0.1:1082`。请以你自己的代理软件设置为准。已在本机验证 Shadowrocket 的这个端口可以接受 SOCKS5 请求，其他设备需要自行确认。

## 从源码生成启动器

在 Mac 的「终端」执行以下命令，先安装编译工具。已经安装的用户可以跳过。

```bash
xcode-select --install
```

然后下载本项目并构建。

```bash
git clone https://github.com/mulunheguang/Antigravity-Proxy-Launcher.git
cd Antigravity-Proxy-Launcher
./scripts/build-launcher.sh
```

构建成功后，会在项目的 `dist` 文件夹中生成 **Antigravity Launcher.app**。

构建时会从 `/Applications/Antigravity.app` 读取应用图标。如果 Antigravity 安装在其他位置，将它的完整路径传给构建脚本，例如下面这样。

```bash
./scripts/build-launcher.sh "$HOME/Applications/Antigravity.app"
```

这个参数用于构建时定位图标。实际要打开哪个应用，由下文配置中的 `appPath` 决定。

## 安装和日常使用

1. 将生成的 **Antigravity Launcher.app** 放到一个固定位置，例如你自己的「应用程序」文件夹。
2. 将这个启动器拖到 **Dock**，也就是屏幕底部或侧边那排应用图标中。
3. 打开 Shadowrocket 或其他代理软件，确保 SOCKS5 代理可用。
4. 点击 Dock 中的启动器图标。它会检查代理、准备中继，再打开真正的 Antigravity App。
5. 出现 macOS 管理员授权框时，输入本机管理员密码并授权。

启动器运行后，屏幕顶部菜单栏会出现 **AG**，通常在 Wi-Fi、电池、时间等图标附近。代理操作进行期间会显示 **AG…**。

**日常入口是这个启动器图标。** 直接点击原始 Antigravity App 的图标，会沿用原始应用的启动方式。

## 如何修改配置

### 通过 AG 菜单修改

1. 点击屏幕顶部的 **AG**。
2. 选择 **编辑配置…**，在打开的文本编辑器中修改 JSON 配置。
3. 按 **⌘S** 保存。
4. 回到 **AG** 菜单，选择 **打开 Antigravity**，让启动器读取并检查新配置。

如果首次启动因为默认端口或应用路径不同而失败，先关闭错误提示，再通过 **AG → 编辑配置…** 修改并重试。

配置示例如下。

```json
{
  "appPath": "/Applications/Antigravity.app",
  "proxyHost": "127.0.0.1",
  "proxyPort": 1082
}
```

各字段的含义如下。

- **`appPath`** 是要打开的应用的完整 `.app` 路径，例如 `/Applications/Antigravity.app`。路径填写到 `.app` 为止。如果你单独安装了 Antigravity IDE，也可以填写它的实际 `.app` 路径。
- **`proxyHost`** 是上游 SOCKS5 代理的 IPv4 地址。本机代理通常填写 `127.0.0.1`。
- **`proxyPort`** 是 SOCKS5 代理端口，填写 `1` 到 `65535` 之间的整数。例如你的 SOCKS5 端口是 `1080`，就将这里的 `1082` 改成 `1080`。

编辑时保留 JSON 的双引号和逗号，端口填写为数字。保存后更换代理地址或端口，可能需要再次输入管理员密码以重新准备中继。

### 找不到 AG 时直接打开配置

在访达中按 **⌘⇧G**，粘贴下面的路径并回车。

```text
~/Library/Application Support/Antigravity Proxy Launcher/
```

打开里面的 `config.json`，修改并保存，然后重新运行启动器。

首次运行会在当前 Mac 用户的上述目录中创建配置。每个人使用自己的配置文件。仓库里的 `launcher/config.json` 是打包时使用的默认模板，已经运行过启动器的用户应修改自己用户目录中的配置。

## AG 菜单中有哪些功能

- **打开 Antigravity** — 读取当前配置，验证代理，准备或复用中继，然后打开目标应用。
- **检测代理** — 通过配置的 SOCKS5 代理发送 HTTPS 请求，检查建隧道、TLS 证书验证及服务器响应。
- **编辑配置…** — 打开当前用户的配置文件。
- **查看中继日志** — 打开中继日志，排查转发错误。
- **停止代理并退出启动器** — 停止本启动器的中继，清理它添加的 hosts 记录，刷新 DNS 缓存并退出启动器。此操作需要管理员授权。

## 什么时候需要输入管理员密码

首次准备中继时会出现 macOS 管理员授权框。重启电脑后第一次使用，或者中继需要重新启动、代理配置发生变化时，可能再次要求授权。

同一次开机期间，中继持续健康运行时，再次点击启动器通常会复用现有环境。

退出 Antigravity App 后，中继会继续运行。需要结束代理时，使用 **AG → 停止代理并退出启动器**。

## 常见问题

### 首次运行提示代理连接失败

先确认代理软件正在运行，再通过 **AG → 编辑配置…** 检查地址和 SOCKS5 端口，保存后选择 **打开 Antigravity** 重试。

上游需要支持无认证 SOCKS5。如果代理软件提供混合端口，请确认该端口确实支持 SOCKS5。可以使用 **AG → 检测代理** 完成实际请求检测。

### 提示本机 443 端口被占用

SNI 中继需要监听 `127.0.0.1:443`。请先停止旧版 Antigravity 代理中继或其他占用此端口的服务，再重新打开启动器。

### 提示找不到应用或主程序

检查 `appPath` 是否指向实际安装的 `.app`。启动器会读取应用 `Info.plist` 中的主程序名来定位程序。

### 检测代理显示 HTTP 404

检测请求访问 Google API 根路径，可能收到 HTTP 404。只要 SOCKS5 建隧道、TLS 证书验证和 HTTPS 响应都完成，这个状态码就能证明检测请求已得到服务器响应。它仅代表该请求的转发结果。

### 去哪里查看日志

通过 **AG → 查看中继日志** 打开，文件路径如下。

```text
/var/run/antigravity-proxy-launcher/relay.log
```

## 当前转发范围

当前 hosts 映射覆盖以下域名，配置来源是 `launcher/proxy-runtime.sh`。

```text
daily-cloudcode-pa.googleapis.com
cloudcode-pa.googleapis.com
oauth2.googleapis.com
accounts.google.com
www.googleapis.com
generativelanguage.googleapis.com
content-cloudcode-pa.googleapis.com
```

这些域名的 HTTPS 请求会被导向本机 SNI 中继，由中继通过配置的 SOCKS5 上游建立连接。其他域名的网络行为由应用及系统设置决定。

hosts 属于系统级配置，因此启动器启用期间，其他程序访问上述域名也会经过该中继。中继关闭时应使用菜单中的停止操作，让域名映射一并清理。

如需扩展域名范围，需要修改运行脚本并重新构建。应用版本升级后，应结合实际使用情况确认登录、对话等功能是否需要新增域名。

## 项目文件

- `launcher/Launcher.swift` — 原生 macOS 启动器与 AG 菜单。
- `launcher/proxy-runtime.sh` — 中继生命周期、hosts 映射和特权操作。
- `launcher/config.json` — 首次运行所使用的默认配置模板。
- `launcher/Info.plist` — 启动器的名称、版本和最低系统要求。
- `scripts/build-launcher.sh` — 生成独立 `.app` 的构建脚本。
- `src/relay.c` — TLS SNI 中继实现。

仓库还保留了 VS Code 扩展和动态库相关源码，便于追溯与继续开发。上面的独立启动器流程使用原生应用和 SNI 中继。

## 致谢与许可证

本项目基于 raybz 的 Antigravity-Proxy 继续开发，增加了独立 macOS 启动器、AG 菜单配置入口及兼容性修复。原作者的版权声明保留在 MIT 许可证中。启动器图标在本机构建时从已安装的 Antigravity 应用复制。

[原项目](https://github.com/raybz/Antigravity-Proxy) · [MIT 许可证](LICENSE)
