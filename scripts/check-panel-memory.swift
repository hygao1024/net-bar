import AppKit
import SwiftUI
import NetBarCore
import Darwin

@MainActor
private final class ProbeSampler: TrafficSampling {
    var samples = 0
    let rows: [ProcessTraffic]

    init() {
        // 固定 60 行，不读取真实网络，也不依赖当前机器的应用数量。
        rows = (1...60).map { (index: Int) -> ProcessTraffic in
            let pid = Int32(100_000 + index)
            let download = Double(index) * 1024
            let upload = Double(index) * 128
            return ProcessTraffic(pid: pid, name: "示例进程 \(index)", download: download, upload: upload)
        }
    }

    func sample() async throws -> [ProcessTraffic] {
        samples += 1
        try await Task.sleep(for: .milliseconds(100))
        try Task.checkCancellation()
        return rows
    }

    func stop() {}
}

/// 离屏测试实际面板生命周期；不会显示窗口、修改登录项或采样网络。
@main
struct CheckPanelMemory {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let cycles = CommandLine.arguments.dropFirst().first.flatMap(Int.init) ?? 3
        precondition((1...100).contains(cycles))
        let sampler = ProbeSampler()
        let monitor = TrafficMonitor(sampler: sampler)
        let suite = "NetBar.panelMemoryCheck.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = MenuBarPreferences(defaults: defaults)
        preferences.appearance.mode = .iconOnly
        let delegate = AppDelegate(monitor: monitor, menuBarPreferences: preferences)
        precondition(delegate.panel == nil, "首次点击前不应创建面板")
        try await Task.sleep(for: .milliseconds(200))
        report("启动未展开")
        precondition(sampler.samples == 0)

        for cycle in 1...cycles {
            autoreleasepool { delegate.preparePanel() }
            weak var previousWindow = delegate.panel
            weak var previousController: NSViewController?
            autoreleasepool { previousController = delegate.panel?.contentViewController }
            autoreleasepool {
                let host = delegate.panel!.contentViewController as! NSHostingController<TrafficView>
                if cycle == 1 {
                    host.rootView.preferences.sort = .upload
                    host.rootView.preferences.ascending = true
                } else {
                    precondition(host.rootView.preferences.sort == .upload)
                    precondition(host.rootView.preferences.ascending)
                }
            }
            monitor.start()
            try await Task.sleep(for: .milliseconds(350))
            precondition(monitor.rows.count == 60)
            autoreleasepool {
                let view = delegate.panel!.contentViewController!.view
                let bounds = NSRect(x: 0, y: 0, width: PanelLayout.width, height: PanelLayout.height)
                view.frame = bounds
                view.layoutSubtreeIfNeeded()
                if let bitmap = view.bitmapImageRepForCachingDisplay(in: bounds) {
                    view.cacheDisplay(in: bounds, to: bitmap)
                }
            }
            report("第\(cycle)次展开（离屏）")
            autoreleasepool {
                if cycle.isMultiple(of: 2) { delegate.closePanel() }
                else { delegate.panel?.cancelOperation(nil) }
            }
            precondition(delegate.panel == nil)
            let stoppedSamples = sampler.samples
            try await Task.sleep(for: .milliseconds(350))
            emit("停止状态：\(!monitor.isMonitoring)，行数：\(monitor.rows.count)，采样次数：\(stoppedSamples) → \(sampler.samples)")
            precondition(!monitor.isMonitoring && monitor.rows.isEmpty)
            precondition(sampler.samples == stoppedSamples, "关闭后不应继续采样")
            emit("控制器已释放：\(previousController == nil)")
            precondition(previousController == nil, "关闭后控制器应释放")
            precondition(previousWindow == nil, "关闭后面板窗口应释放")
            report("第\(cycle)次关闭")
        }
        autoreleasepool {
            let source = NSImage(size: NSSize(width: 512, height: 512), flipped: false) { rect in
                NSColor.systemBlue.setFill()
                rect.fill()
                return true
            }
            let thumbnail = ProcessIconImage.thumbnail(source)!
            precondition(thumbnail.size == NSSize(width: 16, height: 16))
            let bitmap = thumbnail.representations.first as! NSBitmapImageRep
            precondition(thumbnail.representations.count == 1 && bitmap.pixelsWide == 32 && bitmap.pixelsHigh == 32)
            precondition(bitmap.colorAt(x: 16, y: 16)!.alphaComponent > 0.99)
        }
        emit("面板生命周期验证通过")
    }

    private static func emit(_ text: String) {
        FileHandle.standardOutput.write(Data((text + "\n").utf8))
    }

    private static func report(_ phase: String) {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        precondition(result == KERN_SUCCESS)
        emit(String(format: "%@: physical footprint %.2f MiB", phase, Double(info.phys_footprint) / 1_048_576))
    }
}
