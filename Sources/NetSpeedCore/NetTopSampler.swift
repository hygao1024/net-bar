import Foundation

@MainActor
public protocol TrafficSampling: AnyObject {
    func sample() async throws -> [ProcessTraffic]
    func stop()
}

/// 仅持有当前一轮采样；关闭面板时同步终止子进程。
@MainActor
public final class NetTopSampler: TrafficSampling {
    private var process: Process?
    private let executableURL: URL
    private let arguments: [String]
    private let timeout: Duration

    public init(
        executableURL: URL = URL(fileURLWithPath: "/usr/bin/nettop"),
        arguments: [String] = ["-P", "-n", "-x", "-d", "-L", "2", "-s", "1", "-J", "bytes_in,bytes_out"],
        timeout: Duration = .seconds(5)
    ) {
        self.executableURL = executableURL
        self.arguments = arguments
        self.timeout = timeout
    }

    public func sample() async throws -> [ProcessTraffic] {
        try Task.checkCancellation()
        let child = Process()
        let pipe = Pipe()
        child.executableURL = executableURL
        child.arguments = arguments
        child.standardInput = FileHandle.nullDevice
        child.standardOutput = pipe
        child.standardError = pipe
        try child.run()
        process = child

        let deadline = Task { @MainActor in
            try await Task.sleep(for: timeout)
            if child.isRunning {
                child.terminate()
                return true
            }
            return false
        }
        defer {
            deadline.cancel()
            if process === child { process = nil }
        }

        // 排空管道在后台进行，避免缓冲区满导致死锁，也不阻塞菜单栏交互。
        let data = await Task.detached(priority: .utility) {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            child.waitUntilExit()
            try? pipe.fileHandleForReading.close()
            return data
        }.value
        try Task.checkCancellation()
        deadline.cancel()
        if (try? await deadline.value) == true { throw SamplingError.timedOut }
        let output = String(decoding: data, as: UTF8.self)
        guard child.terminationStatus == 0 else {
            let reason = output.trimmingCharacters(in: .whitespacesAndNewlines)
            throw SamplingError.failed(reason.isEmpty ? "nettop 已退出（\(child.terminationStatus)）" : String(reason.prefix(240)))
        }
        return try NetTopParser.parse(output)
    }

    public func stop() {
        if let process, process.isRunning { process.terminate() }
        process = nil
    }
}
