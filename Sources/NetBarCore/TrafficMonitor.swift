import Combine
import Foundation

@MainActor
public final class TrafficMonitor: ObservableObject {
    @Published public private(set) var rows: [ProcessTraffic] = []
    @Published public private(set) var isMonitoring = false
    @Published public private(set) var updatedAt: Date?
    @Published public private(set) var errorMessage: String?
    private let sampler: any TrafficSampling
    private var task: Task<Void, Never>?
    private var generation = 0

    public init(sampler: any TrafficSampling = NetTopSampler()) {
        self.sampler = sampler
    }

    public func start() {
        guard task == nil else { return }
        generation += 1
        let currentGeneration = generation
        rows = []
        updatedAt = nil
        errorMessage = nil
        isMonitoring = true
        task = Task { [weak self, sampler] in
            while !Task.isCancelled {
                do {
                    let rows = try await sampler.sample()
                    guard !Task.isCancelled, let self, self.generation == currentGeneration else { return }
                    self.rows = rows
                    self.updatedAt = Date()
                } catch {
                    guard !Task.isCancelled, let self, self.generation == currentGeneration else { return }
                    self.errorMessage = error.localizedDescription
                    self.rows = []
                    self.updatedAt = nil
                    self.isMonitoring = false
                    self.task = nil
                    return
                }
            }
        }
    }

    public func stop() {
        generation += 1
        task?.cancel()
        task = nil
        sampler.stop()
        isMonitoring = false
        rows = []
        updatedAt = nil
        errorMessage = nil
    }
}
