import Foundation
import Testing
@testable import NetSpeedCore

@MainActor
private final class ControlledSampler: TrafficSampling {
    var starts = 0
    var stops = 0
    var pending: [Int: CheckedContinuation<[ProcessTraffic], any Error>] = [:]

    func sample() async throws -> [ProcessTraffic] {
        starts += 1
        let id = starts
        return try await withCheckedThrowingContinuation { pending[id] = $0 }
    }

    // 故意允许取消后的结果晚到，验证监控层也会隔离旧数据。
    func stop() { stops += 1 }
    func complete(_ id: Int, rows: [ProcessTraffic]) { pending.removeValue(forKey: id)?.resume(returning: rows) }
    func fail(_ id: Int) { pending.removeValue(forKey: id)?.resume(throwing: SamplingError.invalidOutput) }
}

@Suite("面板采样生命周期")
@MainActor
struct LifecycleTests {
    private let row = ProcessTraffic(pid: 42, name: "Browser", download: 1000, upload: 10)

    private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(condition(), "等待状态变化超时")
    }

    @Test("默认不采样，停止后不刷新、不重启")
    func hiddenStopsSampling() async throws {
        let sampler = ControlledSampler()
        let monitor = TrafficMonitor(sampler: sampler)
        try await Task.sleep(for: .milliseconds(20))
        #expect(sampler.starts == 0)
        monitor.start()
        monitor.start()
        try await waitUntil { sampler.starts == 1 }
        sampler.complete(1, rows: [row])
        try await waitUntil { sampler.starts == 2 }
        #expect(monitor.rows == [row])
        #expect(monitor.updatedAt != nil)
        monitor.stop()
        #expect(sampler.stops == 1)
        #expect(!monitor.isMonitoring)
        #expect(monitor.rows.isEmpty)
        sampler.complete(2, rows: [row])
        try await Task.sleep(for: .milliseconds(30))
        #expect(sampler.starts == 2)
        #expect(monitor.updatedAt == nil)
        #expect(monitor.rows.isEmpty)
    }

    @Test("快速重开不能接受上次面板的样本")
    func reopenIgnoresStaleResult() async throws {
        let sampler = ControlledSampler()
        let monitor = TrafficMonitor(sampler: sampler)
        monitor.start()
        try await waitUntil { sampler.starts == 1 }
        monitor.stop()
        monitor.start()
        try await waitUntil { sampler.starts == 2 }
        sampler.complete(1, rows: [row])
        try await Task.sleep(for: .milliseconds(20))
        #expect(monitor.rows.isEmpty)
        #expect(monitor.updatedAt == nil)
        sampler.complete(2, rows: [])
        try await waitUntil { sampler.starts == 3 }
        #expect(monitor.updatedAt != nil)
        monitor.stop()
        sampler.complete(3, rows: [])
    }

    @Test("错误清除旧数据，重试可恢复")
    func errorAndRetry() async throws {
        let sampler = ControlledSampler()
        let monitor = TrafficMonitor(sampler: sampler)
        monitor.start()
        try await waitUntil { sampler.starts == 1 }
        sampler.complete(1, rows: [row])
        try await waitUntil { sampler.starts == 2 }
        sampler.fail(2)
        try await waitUntil { monitor.errorMessage != nil }
        #expect(monitor.rows.isEmpty)
        #expect(monitor.updatedAt == nil)
        #expect(!monitor.isMonitoring)
        monitor.start()
        try await waitUntil { sampler.starts == 3 }
        #expect(monitor.errorMessage == nil)
        sampler.complete(3, rows: [row])
        try await waitUntil { sampler.starts == 4 }
        #expect(monitor.rows == [row])
        monitor.stop()
        sampler.complete(4, rows: [])
    }

    @Test("真实子进程在停止后退出")
    func processTermination() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let pidFile = directory.appendingPathComponent("pid")
        let sampler = NetTopSampler(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "echo $$ > \"$1\"; exec /bin/sleep 30", "test", pidFile.path]
        )
        let sample = Task { try await sampler.sample() }
        try await waitUntil { FileManager.default.fileExists(atPath: pidFile.path) }
        let pidText = try String(contentsOf: pidFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        let pid = try #require(Int32(pidText))
        #expect(kill(pid, 0) == 0)
        sample.cancel()
        sampler.stop()
        do {
            _ = try await sample.value
            Issue.record("取消采样应抛出错误")
        } catch is CancellationError {} catch { Issue.record("错误类型不符：\(error)") }
        #expect(kill(pid, 0) == -1)
        #expect(errno == ESRCH)
    }

    @Test("超时终止采样")
    func timeout() async {
        let sampler = NetTopSampler(executableURL: URL(fileURLWithPath: "/bin/sleep"), arguments: ["30"], timeout: .milliseconds(50))
        do {
            _ = try await sampler.sample()
            Issue.record("应该超时")
        } catch SamplingError.timedOut {} catch { Issue.record("错误类型不符：\(error)") }
    }

    @Test("本机 nettop 可以读取两帧")
    func liveNetTop() async throws {
        let sampler = NetTopSampler()
        let rows = try await sampler.sample()
        #expect(rows.allSatisfy { $0.pid > 0 && $0.download >= 0 && $0.upload >= 0 })
    }
}
