import AppKit

struct LauncherConfig: Codable {
    var appPath: String
    var proxyHost: String
    var proxyPort: Int

    func validate(validateApp: Bool) throws {
        let parts = proxyHost.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4, parts.allSatisfy({ UInt8($0) != nil }),
              (1...65535).contains(proxyPort), appPath.hasPrefix("/") else {
            throw LauncherError.message("请在配置文件中填写完整的应用路径、IPv4 代理地址和 1–65535 端口。")
        }
        guard validateApp else { return }
        let name = try run("/usr/bin/plutil", [
            "-extract", "CFBundleExecutable", "raw", "-expect", "string", "-n", "--",
            appPath + "/Contents/Info.plist",
        ])
        guard !name.isEmpty, !name.contains("/"), !name.contains("\n"),
              name != ".", name != "..",
              FileManager.default.isExecutableFile(atPath: appPath + "/Contents/MacOS/" + name) else {
            throw LauncherError.message("应用路径中缺少有效的主程序。请检查配置中的 appPath。")
        }
    }
}

enum LauncherError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let text): return text }
    }
}

@discardableResult
func run(_ executable: String, _ arguments: [String]) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    // An injected parent shell must not affect the launcher or system utilities.
    var environment = ProcessInfo.processInfo.environment
    for key in ["DYLD_INSERT_LIBRARIES", "DYLD_LIBRARY_PATH", "ALL_PROXY", "HTTPS_PROXY",
                "HTTP_PROXY", "all_proxy", "https_proxy", "http_proxy", "ANTIGRAVITY_CONFIG"] {
        environment.removeValue(forKey: key)
    }
    process.environment = environment
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    let output = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    guard process.terminationStatus == 0 else {
        throw LauncherError.message(output.isEmpty ? "操作失败（退出码 \(process.terminationStatus)）。" : output)
    }
    return output
}

func shellQuote(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

func appleScriptQuote(_ value: String) -> String {
    "\"" + value.replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"") + "\""
}

final class LauncherService {
    static let autostartJob = "/Library/LaunchDaemons/local.antigravity.proxy-launcher.relay.plist"
    static let autostartLog = "/Library/PrivilegedHelperTools/local.antigravity.proxy-launcher.relay/service.log"

    var autostartEnabled: Bool {
        FileManager.default.fileExists(atPath: Self.autostartJob)
    }

    let resources: URL
    let configURL: URL

    init() throws {
        guard let url = Bundle.main.resourceURL else {
            throw LauncherError.message("启动器缺少 Resources 目录。")
        }
        resources = url
        let support = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Antigravity Proxy Launcher")
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        configURL = support.appendingPathComponent("config.json")
        if !FileManager.default.fileExists(atPath: configURL.path) {
            try FileManager.default.copyItem(at: resources.appendingPathComponent("config.json"), to: configURL)
        }
    }

    func loadConfig(validateApp: Bool = true) throws -> LauncherConfig {
        let config = try JSONDecoder().decode(LauncherConfig.self, from: Data(contentsOf: configURL))
        try config.validate(validateApp: validateApp)
        return config
    }

    func checkProxy(_ config: LauncherConfig) throws -> String {
        let result = try run("/usr/bin/curl", [
            "--disable", "--noproxy", "", "--proxy", "socks5h://\(config.proxyHost):\(config.proxyPort)",
            "--connect-timeout", "5", "--max-time", "15", "--silent", "--show-error",
            "--output", "/dev/null", "--write-out", "%{http_code}",
            "https://www.googleapis.com/",
        ])
        guard result.count == 3, result != "000", Int(result) != nil else {
            throw LauncherError.message("SOCKS5 HTTPS 转发校验失败。\n\(result)")
        }
        return "SOCKS5 已完成连接、TLS 证书验证及 HTTPS 请求，HTTP 状态码为 \(result)。"
    }

    func helperArguments(_ action: String, _ config: LauncherConfig) -> [String] {
        [resources.appendingPathComponent("proxy-runtime.sh").path, action,
         resources.appendingPathComponent("antigravity-relay").path,
         config.proxyHost, String(config.proxyPort)]
    }

    func privileged(_ arguments: [String]) throws {
        let command = (["/bin/bash"] + arguments).map(shellQuote).joined(separator: " ")
        try run("/usr/bin/osascript", [
            "-e", "do shell script " + appleScriptQuote(command) + " with administrator privileges",
        ])
    }

    func prepareAndOpen() throws {
        let config = try loadConfig()
        if autostartEnabled {
            do {
                try run("/bin/bash", helperArguments("verify", config))
            } catch {
                throw LauncherError.message("代理自启动已启用，但当前配置的中继尚未就绪。请确认小火箭正在运行，并在 AG 中查看自启动日志。若修改过代理地址或端口，请重新选择「启用或更新代理自启动…」。")
            }
        } else {
            _ = try checkProxy(config)
            do {
                try run("/bin/bash", helperArguments("verify", config))
            } catch {
                try privileged(helperArguments("prepare", config))
            }
        }
        try run("/usr/bin/open", [config.appPath])
    }

    func enableAutostart() throws -> String {
        let config = try loadConfig(validateApp: false)
        let script = resources.appendingPathComponent("autostart.sh").path
        try privileged([script, "enable", config.proxyHost, String(config.proxyPort)])
        return "后台服务将自动等待 SOCKS5 和中继就绪。请保持小火箭运行，就绪后直接点击原版 Antigravity 图标。你可以从 AG 菜单查看自启动日志。"
    }

    func stop() throws {
        if autostartEnabled {
            try privileged([resources.appendingPathComponent("autostart.sh").path, "disable"])
        } else {
            // Cleanup only needs the ownership marker and the runtime PID file.
            try privileged([resources.appendingPathComponent("proxy-runtime.sh").path, "cleanup"])
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var service: LauncherService!
    var busy = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            service = try LauncherService()
        } catch {
            showError(error)
            NSApp.terminate(nil)
            return
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "AG"
        statusItem.button?.toolTip = "Antigravity 代理启动器"
        let menu = NSMenu()
        for (title, action) in [
            ("打开 Antigravity", #selector(openTarget)),
            ("检测代理", #selector(checkProxy)),
            ("编辑配置…", #selector(editConfig)),
            ("查看中继日志", #selector(openLog)),
            ("启用或更新代理自启动…", #selector(enableAutostart)),
            ("查看自启动日志", #selector(openAutostartLog)),
            ("停止代理并退出启动器", #selector(stopProxy)),
        ] {
            let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
            item.target = self
        }
        statusItem.menu = menu
        openTarget()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openTarget()
        return false
    }

    func perform(_ operation: @escaping () throws -> String?, quitOnSuccess: Bool = false) {
        guard !busy else { return }
        busy = true
        statusItem.button?.title = "AG…"
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try operation() }
            DispatchQueue.main.async {
                self.busy = false
                self.statusItem.button?.title = "AG"
                switch result {
                case .success(let message):
                    if quitOnSuccess { NSApp.terminate(nil) }
                    if let message = message {
                        let alert = NSAlert()
                        alert.messageText = "Antigravity 代理启动器"
                        alert.informativeText = message
                        NSApp.activate(ignoringOtherApps: true)
                        alert.runModal()
                    }
                case .failure(let error):
                    self.showError(error)
                }
            }
        }
    }

    @objc func openTarget() {
        perform {
            try self.service.prepareAndOpen()
            return nil
        }
    }

    @objc func checkProxy() {
        perform { try self.service.checkProxy(self.service.loadConfig(validateApp: false)) }
    }

    @objc func editConfig() {
        guard !busy else { return }
        do { try run("/usr/bin/open", ["-t", service.configURL.path]) }
        catch { showError(error) }
    }

    @objc func openLog() {
        do { try run("/usr/bin/open", ["-t", "/var/run/antigravity-proxy-launcher/relay.log"]) }
        catch { showError(error) }
    }

    @objc func enableAutostart() {
        perform { try self.service.enableAutostart() }
    }

    @objc func openAutostartLog() {
        do { try run("/usr/bin/open", ["-t", LauncherService.autostartLog]) }
        catch { showError(error) }
    }

    @objc func stopProxy() {
        perform({
            try self.service.stop()
            return nil
        }, quitOnSuccess: true)
    }

    func showError(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Antigravity 代理启动器"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "好")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}

if CommandLine.arguments.contains("--check") {
    do {
        let service = try LauncherService()
        let config = try service.loadConfig()
        print("目标应用 \(config.appPath)")
        print(try service.checkProxy(config))
    } catch {
        fputs(error.localizedDescription + "\n", stderr)
        exit(1)
    }
} else {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
