# 独立 macOS 启动器

在 Apple Silicon Mac 上运行，点击启动器即可检查 SOCKS5、准备 hosts 与 SNI 中继并打开 Antigravity App。启动器采用现有的七个域名映射与 SNI 中继方案。应用图标取自本机安装的 Antigravity。

## 构建

在本仓库根目录执行以下命令。

```bash
./scripts/build-launcher.sh
```

构建产物位于 `dist/Antigravity Launcher.app`。构建只写入本仓库，不会安装启动器，也不会变更目标应用的签名。生成的应用包含原生启动器、中继、配置和运行脚本。

## 安装与使用

1. 将 `dist/Antigravity Launcher.app` 复制到自己的应用程序文件夹，例如 `~/Applications`。
2. 将它拖到 Dock，以后点击该入口启动 Antigravity。
3. 保持 Shadowrocket 运行。默认上游为无认证 SOCKS5 `127.0.0.1:1082`，目标为 `/Applications/Antigravity.app`。
4. 首次准备环境会显示 macOS 管理员授权框。中继仍然健康时，下次点击复用已有环境。重启电脑后第一次点击需要再次授权。
5. 启动后，菜单栏中的「AG」提供打开应用、检测代理、编辑配置、查看日志，以及停止代理并退出启动器。

首次运行会将默认配置复制到 `~/Library/Application Support/Antigravity Proxy Launcher/config.json`。「编辑配置」打开此文件，保存后再次选择「打开 Antigravity」即可。改变 `appPath` 可指定本机另一个 Antigravity .app，包括单独安装的 Antigravity IDE。填写完整的 .app 路径。

同一份启动器仅运行一个实例，重复点击会检查环境并打开目标应用。关闭 Antigravity 窗口或退出 Antigravity 后，中继继续运行。通过菜单「停止代理并退出启动器」清理环境，需要管理员授权。该操作移除启动器自己的 hosts 标记记录。

运行时状态和中继日志位于 `/var/run/antigravity-proxy-launcher/`。

## 可选的开机自启动

自启动默认关闭。在 **AG → 启用或更新代理自启动…** 授权后，启动器会按当前配置安装 macOS `LaunchDaemon`。开机后，服务等待 SOCKS5 上游通过 HTTPS 检测，再启动中继并添加 `hosts` 映射。用 **AG → 查看自启动日志** 确认中继就绪后，可从原版图标手动打开 Antigravity App 或 IDE。

中继连续三次 HTTPS 检测失败后，服务会停掉中继并撤销自己添加的 `hosts` 映射。检测到连接恢复后重新启用。其他程序访问这些域名时也可能使用同一个中继。

修改代理地址或端口后，重新选择 **启用或更新代理自启动…** 应用配置。使用 **AG → 停止代理并退出启动器** 可注销服务并清理映射。若菜单栏没有 **AG**，先打开新版启动器。

如果启用时提示已有其他来源的 `hosts` 映射，请先清理原有代理工具留下的映射，再重试。

## 从旧版升级

1.1.1 修复了旧中继忽略 `SIGTERM` 导致退出失败的问题。停止时，启动器会先请求中继正常退出，超时后再次核对进程归属，才会结束仍在运行的旧中继。

如果旧版菜单仍提示「中继尚未退出」，可以从仓库根目录运行新版包里的清理脚本。脚本只清理启动器的中继状态和 `hosts` 映射，需要管理员授权。

```bash
sudo /bin/bash "dist/Antigravity Launcher.app/Contents/Resources/proxy-runtime.sh" cleanup
```

清理完成后，从旧版 **AG → 停止代理并退出启动器** 退出，再打开新版启动器。

## 校验与限制

启动器使用 curl 完成 SOCKS5 建隧道、TLS 证书验证和 HTTPS 请求。中继启动时还会单独验证本机 443 端口的实际 HTTPS 转发。HTTP 404 等有效服务器响应同样可以证明转发完成。TCP 连接成功不会被单独视为代理可用。

启动器发现其他程序占用本机 443 端口时会提示错误。使用之前请停止旧版扩展中继。启动器采用独立的进程记录与 hosts 标记，不会停止其他中继或删除旧版扩展的 hosts 记录。

本版使用 SNI 中继，不执行动态库注入或应用重签名。覆盖的域名与 `vscode-extension/src/relayDomains.ts` 一致。完整应用的登录、对话及其他域名请求还需要在实际使用中验收。其他域名的流量由原应用和系统的网络设置决定。

可在终端执行应用包中的原生启动器 `Contents/MacOS/AntigravityProxyLauncher --check`，检查目标路径和 SOCKS5 HTTPS 转发，不准备特权环境或启动目标应用。
