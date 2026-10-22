import Foundation
import Testing
@testable import NetSpeedCore

private actor AddressProbe {
    private(set) var calls = 0
    let failing: Bool
    init(failing: Bool = false) { self.failing = failing }
    func lookup(_ version: IPVersion) throws -> PublicAddress {
        calls += 1
        if failing { throw URLError(.notConnectedToInternet) }
        return PublicAddress(address: version == .v4 ? "203.0.113.42" : "2001:db8::42", countryCode: "JP")
    }
}

private actor DelayedAddressProbe {
    private(set) var calls = 0
    private var continuations: [Int: CheckedContinuation<PublicAddress, any Error>] = [:]
    func lookup(_ version: IPVersion) async throws -> PublicAddress {
        let id = calls
        calls += 1
        return try await withCheckedThrowingContinuation { continuations[id] = $0 }
    }
    func finish(_ ids: [Int], value: String) {
        for id in ids { continuations.removeValue(forKey: id)?.resume(returning: PublicAddress(address: value)) }
    }
}

@Suite("网络地址")
struct NetworkPanelTests {
    @Test("公网响应验证地址族、结构和长度，不接受错误页或注入文本")
    func responseValidation() throws {
        #expect(try PublicAddressService.parseAddress(Data("203.0.113.42\n".utf8), version: .v4) == "203.0.113.42")
        #expect(try PublicAddressService.parseAddress(Data("2001:db8::42\n".utf8), version: .v6) == "2001:db8::42")
        for text in ["<html>error</html>", "2001:db8::1", "999.1.1.1", "1.1.1.1\n8.8.8.8", "1.1.1.1\0garbage", String(repeating: "x", count: 8193)] {
            #expect(throws: (any Error).self) { try PublicAddressService.parseAddress(Data(text.utf8), version: .v4) }
        }
        #expect(throws: (any Error).self) { try PublicAddressService.parseAddress(Data("1.1.1.1".utf8), version: .v6) }
        let good = Data(#"{"success":true,"ip":"203.0.113.42","country_code":"JP"}"#.utf8)
        #expect(PublicAddressService.parseCountry(good, address: "203.0.113.42") == "JP")
        #expect(PublicAddressService.parseCountry(good, address: "203.0.113.43") == nil)
        for code in ["JPN", "jp", "日本", "J1"] {
            let data = Data("{\"success\":true,\"ip\":\"203.0.113.42\",\"country_code\":\"\(code)\"}".utf8)
            #expect(PublicAddressService.parseCountry(data, address: "203.0.113.42") == nil)
        }
        #expect(PublicAddressService.parseCountry(Data("{}".utf8), address: "203.0.113.42") == nil)
    }

    @MainActor private func waitUntil(_ condition: () async -> Bool) async throws {
        for _ in 0..<200 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(await condition(), "等待网络地址状态超时")
    }

    @Test("关闭不查询；缓存、到期和网络切换")
    @MainActor func lifecycleAndCache() async throws {
        let probe = AddressProbe()
        var time = 100.0
        var reads = 0
        var signature = ["en0:192.168.1.2"]
        let model = NetworkPanelModel(readLocal: {
            reads += 1
            return LocalNetworkSnapshot(addresses: [], signature: signature)
        }, lookup: { try await probe.lookup($0) }, now: { time })
        #expect(reads == 0)
        #expect(await probe.calls == 0)
        model.refreshAddresses(force: true)
        #expect(reads == 0)
        model.start()
        try await waitUntil { if case .available = model.snapshot.ipv6 { return true }; return false }
        #expect(await probe.calls == 2)
        model.stop()
        #expect(model.snapshot == NetworkPanelSnapshot() && !model.isVisible)
        model.start()
        #expect(await probe.calls == 2, "有效缓存不应重复查询")
        time += 301
        model.refreshAddresses()
        try await waitUntil { await probe.calls == 4 }
        try await waitUntil { if case .available = model.snapshot.ipv6 { return true }; return false }
        signature = ["en0:192.168.1.2", "utun0:10.0.0.1"]
        model.refreshAddresses()
        try await waitUntil { await probe.calls == 6 }
        model.stop()
    }

    @Test("关闭与快速重开时丢弃迟到结果")
    @MainActor func lateResults() async throws {
        let probe = DelayedAddressProbe()
        let model = NetworkPanelModel(readLocal: { LocalNetworkSnapshot(addresses: [], signature: []) },
                                      lookup: { try await probe.lookup($0) }, now: { 1 })
        model.start()
        try await waitUntil { await probe.calls == 2 }
        model.stop()
        model.start()
        try await waitUntil { await probe.calls == 4 }
        await probe.finish([0, 1], value: "old")
        try await Task.sleep(for: .milliseconds(20))
        #expect(model.snapshot.ipv4 == .loading && model.snapshot.ipv6 == .loading)
        await probe.finish([2, 3], value: "new")
        try await waitUntil { model.snapshot.ipv6 == .available(PublicAddress(address: "new")) }
        #expect(model.snapshot.ipv4 == .available(PublicAddress(address: "new")))
        model.stop()
    }

    @Test("地址查询失败独立呈现，短暂缓存后允许重试")
    @MainActor func failuresAndRetry() async throws {
        let probe = AddressProbe(failing: true)
        var time = 10.0
        let model = NetworkPanelModel(readLocal: { throw URLError(.unknown) },
                                      lookup: { try await probe.lookup($0) }, now: { time })
        model.start()
        try await waitUntil { model.snapshot.ipv4 == .unavailable && model.snapshot.ipv6 == .unavailable }
        #expect(model.snapshot.localReadFailed)
        model.refreshAddresses()
        #expect(await probe.calls == 2)
        time += 31
        model.refreshAddresses()
        try await waitUntil { await probe.calls == 4 }
        model.refreshAddresses(force: true)
        try await waitUntil { await probe.calls == 6 }
        model.stop()
    }

    @Test("单一地址族查询失败不覆盖另一个地址族")
    @MainActor func independentFamilies() async throws {
        let model = NetworkPanelModel(readLocal: { LocalNetworkSnapshot(addresses: [], signature: []) },
                                      lookup: { version in
            if version == .v6 { throw URLError(.cannotFindHost) }
            return PublicAddress(address: "203.0.113.42")
        }, now: { 1 })
        model.start()
        try await waitUntil {
            model.snapshot.ipv4 == .available(PublicAddress(address: "203.0.113.42")) && model.snapshot.ipv6 == .unavailable
        }
        model.stop()
    }

    @Test("地址轮询独立运行，关闭停止，重开恢复")
    @MainActor func addressPolling() async throws {
        let probe = AddressProbe()
        var reads = 0
        let model = NetworkPanelModel(readLocal: {
            reads += 1
            return LocalNetworkSnapshot(addresses: [], signature: [])
        }, lookup: { try await probe.lookup($0) }, now: { 1 }, refreshInterval: .milliseconds(5))
        model.start()
        try await waitUntil { reads >= 3 }
        model.stop()
        let stoppedReads = reads
        try await Task.sleep(for: .milliseconds(30))
        #expect(reads == stoppedReads)
        #expect(model.snapshot == NetworkPanelSnapshot())
        model.start()
        try await waitUntil { reads >= stoppedReads + 3 }
        model.stop()
    }

    @Test("真实本机接口可读取，局域网地址不含隧道或回环")
    func localInterfaces() throws {
        let snapshot = try LocalNetworkReader.read()
        #expect(snapshot.addresses.allSatisfy { $0.interface.hasPrefix("en") })
        #expect(Set(snapshot.addresses.map(\.id)).count == snapshot.addresses.count)
    }
}
