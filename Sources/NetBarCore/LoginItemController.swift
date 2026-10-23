import Combine
import Foundation
import ServiceManagement

@MainActor
protocol LoginItemServicing {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
}

@MainActor
private struct MainAppLoginService: LoginItemServicing {
    var status: SMAppService.Status { SMAppService.mainApp.status }
    func register() throws { try SMAppService.mainApp.register() }
    func unregister() throws { try SMAppService.mainApp.unregister() }
}

/// 以系统登录项为唯一状态来源，不保存可能与系统设置不同步的布尔值。
@MainActor
public final class LoginItemController: ObservableObject {
    @Published public private(set) var status: SMAppService.Status = .notRegistered
    @Published public var errorMessage: String?
    private let service: any LoginItemServicing
    private let isAppBundle: Bool

    public convenience init() {
        self.init(service: MainAppLoginService(), isAppBundle: Bundle.main.bundleURL.pathExtension == "app")
    }

    init(service: any LoginItemServicing, isAppBundle: Bool = true) {
        self.service = service
        self.isAppBundle = isAppBundle
        refresh()
    }

    /// 待批准表示已注册的请求，旁边单独提示尚未生效，并允许关闭以撤销。
    public var isRequested: Bool { status == .enabled || status == .requiresApproval }
    public var requiresApproval: Bool { status == .requiresApproval }

    public func refresh() { status = service.status }

    public func setEnabled(_ enabled: Bool) {
        errorMessage = nil
        refresh()
        guard enabled != isRequested else { return }
        guard isAppBundle else {
            errorMessage = "请先打开打包后的 NetBar.app，再设置开机启动。"
            return
        }
        do {
            if enabled { try service.register() }
            else { try service.unregister() }
            refresh()
            if enabled && !isRequested {
                errorMessage = "系统未启用登录项。请将应用放到“应用程序”文件夹后重试。"
            }
        } catch {
            refresh()
            errorMessage = "无法\(enabled ? "开启" : "关闭")开机启动。请在系统设置的“通用 → 登录项”中检查，或稍后重试。\n\(error.localizedDescription)"
        }
    }

    public func openSettings() { SMAppService.openSystemSettingsLoginItems() }
}
