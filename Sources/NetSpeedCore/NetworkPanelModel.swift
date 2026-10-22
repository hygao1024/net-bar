import Combine
import Foundation

public struct NetworkPanelSnapshot: Equatable, Sendable {
    public var localAddresses: [LocalAddress] = []
    public var localReadFailed = false
    public var ipv4: AddressLookupState = .idle
    public var ipv6: AddressLookupState = .idle

    public init() {}
}

@MainActor
public final class NetworkPanelModel: ObservableObject {
    @Published public private(set) var snapshot = NetworkPanelSnapshot()
    public private(set) var isVisible = false
    private var tasks: [IPVersion: Task<Void, Never>] = [:]
    private var cache: [IPVersion: (state: AddressLookupState, time: TimeInterval)] = [:]
    private var signature: [String]?
    private var generation = 0
    private var refreshTask: Task<Void, Never>?
    private let refreshInterval: Duration
    private let readLocal: () throws -> LocalNetworkSnapshot
    private let lookup: @Sendable (IPVersion) async throws -> PublicAddress
    private let now: () -> TimeInterval

    public convenience init() {
        let service = PublicAddressService()
        self.init(readLocal: LocalNetworkReader.read, lookup: service.lookup,
                  now: { ProcessInfo.processInfo.systemUptime })
    }

    init(readLocal: @escaping () throws -> LocalNetworkSnapshot,
         lookup: @escaping @Sendable (IPVersion) async throws -> PublicAddress,
         now: @escaping () -> TimeInterval, refreshInterval: Duration = .seconds(5)) {
        self.readLocal = readLocal
        self.lookup = lookup
        self.now = now
        self.refreshInterval = refreshInterval
    }

    public func start() {
        guard !isVisible else { return }
        isVisible = true
        refreshAddresses()
        let interval = refreshInterval
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: interval) }
                catch { return }
                guard !Task.isCancelled, let self else { return }
                self.refreshAddresses()
            }
        }
    }

    public func stop() {
        isVisible = false
        refreshTask?.cancel()
        refreshTask = nil
        cancelLookups()
        snapshot = NetworkPanelSnapshot()
    }

    public func refreshAddresses(force: Bool = false) {
        guard isVisible else { return }
        let time = now()
        do {
            let local = try readLocal()
            if signature != local.signature {
                cancelLookups()
                cache = [:]
                signature = local.signature
            }
            snapshot.localAddresses = local.addresses
            snapshot.localReadFailed = false
        } catch {
            snapshot.localAddresses = []
            snapshot.localReadFailed = true
        }
        if force { cancelLookups(); cache = [:] }
        for version in IPVersion.allCases {
            if let saved = cache[version] {
                let lifetime: TimeInterval = saved.state == .unavailable ? 30 : 300
                if time - saved.time < lifetime { set(saved.state, for: version); continue }
            }
            guard tasks[version] == nil else { continue }
            set(.loading, for: version)
            let requestGeneration = generation
            let lookup = lookup
            tasks[version] = Task { [weak self] in
                let result: AddressLookupState
                do { result = .available(try await lookup(version)) }
                catch { result = .unavailable }
                guard !Task.isCancelled, let self, self.isVisible,
                      self.generation == requestGeneration else { return }
                self.cache[version] = (result, self.now())
                self.set(result, for: version)
                self.tasks[version] = nil
            }
        }
    }

    private func set(_ value: AddressLookupState, for version: IPVersion) {
        if version == .v4 { snapshot.ipv4 = value } else { snapshot.ipv6 = value }
    }

    private func cancelLookups() {
        generation += 1
        tasks.values.forEach { $0.cancel() }
        tasks = [:]
    }

    deinit {
        refreshTask?.cancel()
        tasks.values.forEach { $0.cancel() }
    }
}
