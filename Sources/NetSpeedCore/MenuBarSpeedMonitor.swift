import Foundation

public enum MenuBarSpeedState: Equatable, Sendable {
    case measuring
    case available(NetworkSpeed)
    case unavailable
}

/// 菜单栏独立读取内核计数器，不启动 nettop，也不持有应用列表或视图。
@MainActor
public final class MenuBarSpeedMonitor {
    public var onChange: ((MenuBarSpeedState) -> Void)?
    public private(set) var state: MenuBarSpeedState = .measuring
    private var task: Task<Void, Never>?
    private var calculator = NetworkSpeedCalculator()
    private let read: () throws -> [InterfaceBytes]
    private let now: () -> TimeInterval
    private let interval: Duration

    public convenience init() {
        self.init(read: NetworkInterfaceReader.read, now: { ProcessInfo.processInfo.systemUptime })
    }

    init(read: @escaping () throws -> [InterfaceBytes], now: @escaping () -> TimeInterval,
         interval: Duration = .seconds(1)) {
        self.read = read
        self.now = now
        self.interval = interval
    }

    public func start() {
        guard task == nil else { return }
        calculator.reset()
        refresh()
        let interval = interval
        task = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: interval, tolerance: .milliseconds(100)) }
                catch { return }
                guard !Task.isCancelled, let self else { return }
                self.refresh()
            }
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
        calculator.reset()
        publish(.measuring)
    }

    private func refresh() {
        do {
            let interfaces = try read()
            if let rate = calculator.update(interfaces, time: now()) {
                publish(.available(rate))
            } else {
                publish(.measuring)
            }
        } catch {
            calculator.reset()
            publish(.unavailable)
        }
    }

    private func publish(_ value: MenuBarSpeedState) {
        guard value != state else { return }
        state = value
        onChange?(value)
    }

    deinit { task?.cancel() }
}
