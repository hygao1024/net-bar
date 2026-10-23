import AppKit
import Combine
import Sparkle

/// 更新会话属于应用，不随设置窗口关闭而取消。下载、校验和替换均由 Sparkle 持有。
@MainActor
final class UpdateController: NSObject, ObservableObject, SPUUpdaterDelegate {
    enum Status: Equatable {
        case idle, checking, current, available(String), downloading(String), ready(String), installing
        case failed, unavailable(String)

        var title: String {
            switch self {
            case .idle: return "随时保持最新"
            case .checking: return "正在检查更新…"
            case .current: return "暂无可用更新"
            case .available(let version): return "发现新版本 \(version)"
            case .downloading(let version): return "正在下载 \(version)…"
            case .ready(let version): return "\(version) 已准备就绪"
            case .installing: return "正在准备安装…"
            case .failed: return "更新未完成"
            case .unavailable: return "暂时无法检查更新"
            }
        }

        var detail: String {
            switch self {
            case .idle: return "获取 NetBar 的最新改进。"
            case .checking: return "正在连接更新服务。"
            case .current: return "当前没有适用于这台 Mac 的新版本。"
            case .available: return "查看版本说明，选择何时安装。"
            case .downloading: return "你可以关闭设置，下载会在后台继续。"
            case .ready: return "退出时自动安装，也可以现在安装并重新打开。"
            case .installing: return "请按照更新窗口中的提示完成安装。"
            case .failed: return "请重试检查更新；仍失败时可前往发布页下载。"
            case .unavailable(let reason): return reason
            }
        }

        var isBusy: Bool {
            switch self {
            case .checking, .downloading, .installing: return true
            default: return false
            }
        }
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var canCheck = false
    @Published private(set) var isEnabled = false
    @Published private(set) var automaticChecks = false
    @Published private(set) var automaticDownloads = false
    @Published private(set) var lastCheck: Date?
    private var updater: SPUUpdater?
    private let userDriver: (any SPUUserDriver)?
    private var observations: [NSKeyValueObservation] = []
    let version: String
    static let releasesURL = URL(string: "https://github.com/hygao1024/net-bar/releases")!

    init(userDriver: (any SPUUserDriver)? = nil) {
        self.userDriver = userDriver
        let info = Bundle.main.infoDictionary ?? [:]
        version = "\(info["CFBundleShortVersionString"] as? String ?? "开发版本")（\(info["CFBundleVersion"] as? String ?? "—")）"
        super.init()
    }

    init(preview status: Status) {
        userDriver = nil
        version = "1.2.0（6）"
        super.init()
        self.status = status
        canCheck = !status.isBusy
        isEnabled = true
        automaticChecks = true
        automaticDownloads = true
        if case .unavailable = status {
            canCheck = false
            isEnabled = false
            automaticChecks = false
            automaticDownloads = false
        }
    }

    func start() {
        guard updater == nil else { return }
        guard Bundle.main.bundleURL.pathExtension == "app" else {
            status = .unavailable("请打开安装后的 NetBar.app 来检查更新。")
            return
        }
        guard let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
              Data(base64Encoded: key)?.count == 32 else {
            status = .unavailable("此构建尚未配置更新验证，请从发布页获取正式版本。")
            return
        }
        let driver = userDriver ?? SPUStandardUserDriver(hostBundle: .main, delegate: nil)
        let updater = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: driver, delegate: self)
        self.updater = updater
        do {
            try updater.start()
            isEnabled = true
        } catch {
            status = .unavailable("更新服务未能启动，请从发布页重新安装。")
            return
        }
        observations = [
            updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in self?.synchronize() }
            },
            updater.observe(\.automaticallyChecksForUpdates, options: [.new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in self?.synchronize() }
            },
            updater.observe(\.automaticallyDownloadsUpdates, options: [.new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in self?.synchronize() }
            },
            updater.observe(\.lastUpdateCheckDate, options: [.new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in self?.synchronize() }
            }
        ]
        synchronize()
    }

    private func synchronize() {
        guard let updater, isEnabled else { return }
        canCheck = updater.canCheckForUpdates
        automaticChecks = updater.automaticallyChecksForUpdates
        automaticDownloads = updater.automaticallyDownloadsUpdates
        lastCheck = updater.lastUpdateCheckDate
    }

    func setAutomaticChecks(_ enabled: Bool) {
        updater?.automaticallyChecksForUpdates = enabled
        synchronize()
    }

    func setAutomaticDownloads(_ enabled: Bool) {
        updater?.automaticallyDownloadsUpdates = enabled
        synchronize()
    }

    func checkForUpdates() {
        guard let updater, updater.canCheckForUpdates else { return }
        updater.checkForUpdates()
    }

    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        status = .checking
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        status = .available(item.displayVersionString)
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        status = .current
    }

    func updater(_ updater: SPUUpdater, willDownloadUpdate item: SUAppcastItem, with request: NSMutableURLRequest) {
        status = .downloading(item.displayVersionString)
    }

    func updater(_ updater: SPUUpdater, didExtractUpdate item: SUAppcastItem) {
        status = .ready(item.displayVersionString)
    }

    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        status = .installing
    }

    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem,
                 immediateInstallationBlock: @escaping () -> Void) -> Bool {
        status = .ready(item.displayVersionString)
        return false
    }

    func updater(_ updater: SPUUpdater, userDidMake choice: SPUUserUpdateChoice,
                 forUpdate updateItem: SUAppcastItem, state: SPUUserUpdateState) {
        if choice == .skip { status = .idle }
    }

    func userDidCancelDownload(_ updater: SPUUpdater) { status = .idle }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        if let error = error as NSError? {
            switch error.domain == SUSparkleErrorDomain ? error.code : -1 {
            case Int(SUError.noUpdateError.rawValue): status = .current
            case Int(SUError.installationCanceledError.rawValue): status = .idle
            default: status = .failed
            }
        } else if status == .checking {
            status = .idle
        }
        synchronize()
    }
}
