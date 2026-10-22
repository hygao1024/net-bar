import ServiceManagement
import Testing
@testable import NetSpeedCore

@MainActor
private final class LoginServiceStub: LoginItemServicing {
    var status: SMAppService.Status = .notRegistered
    var registrationStatus: SMAppService.Status = .enabled
    var shouldFail = false
    var changes = 0
    enum Failure: Error { case denied }
    func register() throws {
        changes += 1
        if shouldFail { throw Failure.denied }
        status = registrationStatus
    }
    func unregister() throws {
        changes += 1
        if shouldFail { throw Failure.denied }
        status = .notRegistered
    }
}

@Suite("开机启动状态")
@MainActor
struct LoginItemTests {
    @Test("初次读取不注册，开关可开启和关闭")
    func toggle() {
        let service = LoginServiceStub()
        let controller = LoginItemController(service: service)
        #expect(!controller.isRequested)
        #expect(service.changes == 0)
        controller.setEnabled(true)
        #expect(controller.status == .enabled)
        controller.setEnabled(true)
        #expect(service.changes == 1)
        controller.setEnabled(false)
        #expect(!controller.isRequested)
        #expect(service.changes == 2)
    }

    @Test("失败后显示错误并保留系统真实状态")
    func failure() {
        let service = LoginServiceStub()
        let controller = LoginItemController(service: service)
        service.shouldFail = true
        controller.setEnabled(true)
        #expect(!controller.isRequested)
        #expect(controller.errorMessage != nil)
        service.status = .enabled
        controller.setEnabled(false)
        #expect(controller.isRequested)
        #expect(controller.errorMessage != nil)
    }

    @Test("待批准可撤销，系统外部变更可同步")
    func approvalAndRefresh() {
        let service = LoginServiceStub()
        service.registrationStatus = .requiresApproval
        let controller = LoginItemController(service: service)
        controller.setEnabled(true)
        #expect(controller.requiresApproval)
        #expect(controller.isRequested)
        controller.setEnabled(false)
        #expect(!controller.requiresApproval)
        #expect(!controller.isRequested)
        service.status = .enabled
        controller.refresh()
        #expect(controller.isRequested)
        service.status = .notRegistered
        controller.refresh()
        #expect(!controller.isRequested)
        #expect(service.changes == 2)
    }

    @Test("命令行运行不能注册；未找到应用不显示成功")
    func unavailable() {
        let service = LoginServiceStub()
        let commandLine = LoginItemController(service: service, isAppBundle: false)
        commandLine.setEnabled(true)
        #expect(service.changes == 0)
        #expect(commandLine.errorMessage != nil)
        service.registrationStatus = .notFound
        let controller = LoginItemController(service: service)
        controller.setEnabled(true)
        #expect(!controller.isRequested)
        #expect(controller.errorMessage != nil)
    }
}
