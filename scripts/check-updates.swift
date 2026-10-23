import AppKit
import Combine
import Sparkle

/// 仅测试可执行文件链接此驱动：自动回答隔离测试应用的更新交互，产品仍使用 Sparkle 原生窗口。
@MainActor
final class TestUpdateDriver: NSObject, SPUUserDriver {
    let mode: String
    let root: URL
    init(mode: String, root: URL) { self.mode = mode; self.root = root }
    func record(_ name: String, _ value: String = "ok") {
        try! value.write(to: root.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }
    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        preconditionFailure("已显式配置更新默认值，不应请求权限")
    }
    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        if mode == "cancel" {
            cancellation()
            record("cancelled")
            NSApp.terminate(nil)
        }
    }
    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState,
                         reply: @escaping (SPUUserUpdateChoice) -> Void) {
        record("found")
        reply(.install)
    }
    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}
    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {}
    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) {
        record("current")
        acknowledgement()
        NSApp.terminate(nil)
    }
    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {
        record("error", String(describing: error))
        var underlying: NSError? = error as NSError
        var codes: [String] = []
        while let current = underlying {
            codes.append("\(current.domain):\(current.code)")
            underlying = current.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        record("error-codes", codes.joined(separator: "\n"))
        acknowledgement()
        NSApp.terminate(nil)
    }
    func showDownloadInitiated(cancellation: @escaping () -> Void) { record("download") }
    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {}
    func showDownloadDidReceiveData(ofLength length: UInt64) {}
    func showDownloadDidStartExtractingUpdate() { record("extract") }
    func showExtractionReceivedProgress(_ progress: Double) {
        if progress > 0 { record("extracted-data") }
    }
    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) { reply(.install) }
    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool,
                              retryTerminatingApplication: @escaping () -> Void) {}
    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) { acknowledgement() }
    func dismissUpdateInstallation() {}
}

@main
@MainActor
final class CheckUpdates: NSObject, NSApplicationDelegate {
    var updates: UpdateController?
    var observation: AnyCancellable?

    static func main() {
        let app = NSApplication.shared
        let delegate = CheckUpdates()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let root = URL(fileURLWithPath: Bundle.main.object(forInfoDictionaryKey: "NetBarTestRoot") as! String)
        let mode = Bundle.main.object(forInfoDictionaryKey: "NetBarTestMode") as! String
        let driver = TestUpdateDriver(mode: mode, root: root)
        if Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String == "2" {
            driver.record("relaunched")
            NSApp.terminate(nil)
            return
        }
        let updates = UpdateController(userDriver: driver)
        self.updates = updates
        updates.start()
        precondition(updates.isEnabled && updates.canCheck, "真实应用中的更新服务应启动")
        if mode == "settings" {
            updates.setAutomaticChecks(true)
            updates.setAutomaticDownloads(true)
            precondition(updates.automaticChecks && updates.automaticDownloads)
            updates.setAutomaticDownloads(false)
            updates.setAutomaticChecks(false)
            precondition(!updates.automaticChecks && !updates.automaticDownloads)
            precondition(UserDefaults.standard.object(forKey: "SUEnableAutomaticChecks") as? Bool == false)
            precondition(UserDefaults.standard.object(forKey: "SUAutomaticallyUpdate") as? Bool == false)
            driver.record("settings")
            NSApp.terminate(nil)
            return
        }
        observation = updates.$status.sink { status in
            driver.record("status", status.title)
            if case .ready = status, mode == "background" {
                // 让 Sparkle 完成当前回调，随后模拟用户正常退出。
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    driver.record("quit-install")
                    NSApp.terminate(nil)
                }
            }
        }
        if mode != "background" { updates.checkForUpdates() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) {
            driver.record("timeout")
            NSApp.terminate(nil)
        }
    }
}
