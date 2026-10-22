import Darwin
import Foundation
import Testing
@testable import NetSpeedCore

@Suite("菜单栏整机网速")
struct NetworkSpeedTests {
    private func interface(_ name: String = "en0", index: UInt32 = 1,
                           received: UInt64, sent: UInt64) -> InterfaceBytes {
        InterfaceBytes(index: index, name: name, received: received, sent: sent)
    }

    @Test("64 位计数按实际时间间隔计算，首帧只建基准")
    func deltaAndElapsedTime() {
        var calculator = NetworkSpeedCalculator()
        let base: UInt64 = 8_000_000_000
        #expect(calculator.update([interface(received: base, sent: base)], time: 10) == nil)
        #expect(calculator.update([interface(received: base + 5000, sent: base + 1000)], time: 12.5)
                == NetworkSpeed(download: 2000, upload: 400))
    }

    @Test("多网卡独立计算，新接口与计数重置不产生尖峰")
    func interfaceChanges() {
        var calculator = NetworkSpeedCalculator()
        _ = calculator.update([interface(received: 1000, sent: 1000)], time: 1)
        #expect(calculator.update([
            interface(received: 1200, sent: 1100),
            interface("en1", index: 2, received: 9_000_000, sent: 9_000_000)
        ], time: 2) == NetworkSpeed(download: 200, upload: 100))
        #expect(calculator.update([
            interface(received: 10, sent: 10),
            interface("en1", index: 2, received: 9_000_600, sent: 9_000_200)
        ], time: 3) == NetworkSpeed(download: 600, upload: 200))
        #expect(calculator.update([
            interface(index: 9, received: 8_000_000, sent: 8_000_000)
        ], time: 4) == NetworkSpeed(download: 0, upload: 0))
        #expect(calculator.update([], time: 5) == NetworkSpeed(download: 0, upload: 0))
    }

    @Test("恢复采样重新建基准，零时间间隔不除零")
    func resetAndInvalidTime() {
        var calculator = NetworkSpeedCalculator()
        _ = calculator.update([interface(received: 100, sent: 100)], time: 1)
        #expect(calculator.update([interface(received: 200, sent: 200)], time: 1) == nil)
        calculator.reset()
        #expect(calculator.update([interface(received: 8_000_000, sent: 8_000_000)], time: 100) == nil)
        #expect(calculator.update([interface(received: 8_000_010, sent: 8_000_020)], time: 101)
                == NetworkSpeed(download: 10, upload: 20))
    }

    @Test("只计在线 Wi-Fi 和以太网，排除回环与虚拟接口")
    func interfaceFilter() {
        let flags: Int32 = IFF_UP | IFF_RUNNING
        #expect(NetworkInterfaceReader.includes(name: "en0", type: UInt8(IFT_ETHER), flags: flags))
        #expect(NetworkInterfaceReader.includes(name: "en12", type: UInt8(IFT_ETHER), flags: flags))
        for name in ["lo0", "utun0", "bridge0", "awdl0", "llw0", "vmenet0", "en", "enX"] {
            #expect(!NetworkInterfaceReader.includes(name: name, type: UInt8(IFT_ETHER), flags: flags))
        }
        #expect(!NetworkInterfaceReader.includes(name: "en0", type: UInt8(IFT_ETHER), flags: IFF_UP))
        #expect(!NetworkInterfaceReader.includes(name: "en0", type: UInt8(IFT_ETHER), flags: flags | IFF_LOOPBACK))
    }

    @Test("菜单栏单位与异常值显示")
    func format() {
        #expect(MenuBarRate.string(0) == "0.0 KB/s")
        #expect(MenuBarRate.string(25_600) == "25.6 KB/s")
        #expect(MenuBarRate.string(2_500_000) == "2.5 MB/s")
        #expect(MenuBarRate.string(1_000_000_000) == "1.0 GB/s")
        #expect(MenuBarRate.string(.nan) == "—")
        #expect(MenuBarRate.string(-1) == "—")
    }

    @Test("本机可直接读取 64 位网卡计数，无需子进程")
    func liveInterfaceCounters() throws {
        let rows = try NetworkInterfaceReader.read()
        #expect(Set(rows.map(\.name)).count == rows.count)
        #expect(rows.allSatisfy { $0.name.hasPrefix("en") && $0.index > 0 })
    }

    @MainActor
    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(condition(), "等待菜单栏采样超时")
    }

    @Test("菜单栏独立采样，停止与恢复不沿用旧基准")
    @MainActor func monitorLifecycle() async throws {
        var reads = 0
        let monitor = MenuBarSpeedMonitor(read: {
            reads += 1
            return [interface(received: UInt64(reads * 1000), sent: UInt64(reads * 100))]
        }, now: { Double(reads) }, interval: .milliseconds(10))
        #expect(reads == 0)
        monitor.start()
        monitor.start()
        #expect(reads == 1)
        #expect(monitor.state == .measuring)
        try await waitUntil { monitor.state == .available(NetworkSpeed(download: 1000, upload: 100)) }
        monitor.stop()
        let stopped = reads
        try await Task.sleep(for: .milliseconds(50))
        #expect(reads == stopped)
        #expect(monitor.state == .measuring)
        monitor.start()
        #expect(monitor.state == .measuring)
        try await waitUntil { monitor.state == .available(NetworkSpeed(download: 1000, upload: 100)) }
        monitor.stop()
    }

    @Test("读取失败不显示零速率，恢复后重建基准")
    @MainActor func monitorFailureRecovery() async throws {
        var failing = true
        var reads = 0
        let monitor = MenuBarSpeedMonitor(read: {
            reads += 1
            if failing { throw POSIXError(.EIO) }
            return [interface(received: UInt64(reads * 100), sent: 0)]
        }, now: { Double(reads) }, interval: .milliseconds(10))
        var states: [MenuBarSpeedState] = []
        monitor.onChange = { states.append($0) }
        monitor.start()
        #expect(monitor.state == .unavailable)
        failing = false
        try await waitUntil { monitor.state == .available(NetworkSpeed(download: 100, upload: 0)) }
        #expect(states.contains(.measuring))
        monitor.stop()
    }
}
