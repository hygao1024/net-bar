import Darwin
import Foundation

public enum IPVersion: String, Sendable, CaseIterable { case v4 = "IPv4", v6 = "IPv6" }

public struct LocalAddress: Equatable, Sendable, Identifiable {
    public let interface: String
    public let address: String
    public let version: IPVersion
    public var id: String { interface + ":" + address }

    public init(interface: String, address: String, version: IPVersion) {
        self.interface = interface
        self.address = address
        self.version = version
    }
}

struct LocalNetworkSnapshot: Equatable, Sendable {
    let addresses: [LocalAddress]
    // 包含隧道地址，用于切换 VPN 时使公网缓存失效；不把隧道地址标为局域网地址。
    let signature: [String]
}

enum IPAddress {
    static func isValid(_ value: String, version: IPVersion) -> Bool {
        guard !value.contains("\0"), value.utf8.count < Int(INET6_ADDRSTRLEN) else { return false }
        if version == .v4 {
            var address = in_addr()
            return inet_pton(AF_INET, value, &address) == 1
        }
        var address = in6_addr()
        return inet_pton(AF_INET6, value, &address) == 1
    }
}

enum LocalNetworkReader {
    static func read() throws -> LocalNetworkSnapshot {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0 else { throw POSIXError(.EIO) }
        defer { freeifaddrs(head) }
        var cursor = head
        var addresses: [LocalAddress] = []
        var signature: [String] = []
        while let item = cursor {
            defer { cursor = item.pointee.ifa_next }
            let value = item.pointee
            guard let address = value.ifa_addr,
                  value.ifa_flags & UInt32(IFF_UP | IFF_RUNNING) == UInt32(IFF_UP | IFF_RUNNING),
                  value.ifa_flags & UInt32(IFF_LOOPBACK) == 0 else { continue }
            let family = Int32(address.pointee.sa_family)
            guard family == AF_INET || family == AF_INET6 else { continue }
            var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(address, socklen_t(address.pointee.sa_len), &buffer,
                              socklen_t(buffer.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let name = String(cString: value.ifa_name)
            let text = String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            signature.append(name + ":" + text)
            let suffix = name.dropFirst(2)
            guard name.hasPrefix("en"), !suffix.isEmpty, suffix.allSatisfy(\.isNumber) else { continue }
            addresses.append(LocalAddress(interface: name, address: text, version: family == AF_INET ? .v4 : .v6))
        }
        var seen: Set<String> = []
        let ordered = addresses.filter { seen.insert($0.id).inserted }.sorted {
            ($0.version.rawValue, $0.interface, $0.address) < ($1.version.rawValue, $1.interface, $1.address)
        }
        return LocalNetworkSnapshot(addresses: ordered, signature: signature.sorted())
    }
}

public struct PublicAddress: Equatable, Sendable {
    public let address: String
    public let countryCode: String?

    public init(address: String, countryCode: String? = nil) {
        self.address = address
        self.countryCode = countryCode
    }
}

public enum AddressLookupState: Equatable, Sendable {
    case idle, loading, unavailable
    case available(PublicAddress)
}

/// 两个独立的地址族端点；通过代理访问时显示该查询的出口，不推断本机所在地。
struct PublicAddressService: Sendable {
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 6
        configuration.timeoutIntervalForResource = 8
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        session = URLSession(configuration: configuration)
    }

    func lookup(_ version: IPVersion) async throws -> PublicAddress {
        let host = version == .v4 ? "ipv4.icanhazip.com" : "ipv6.icanhazip.com"
        let data = try await read(URL(string: "https://\(host)/")!)
        let address = try Self.parseAddress(data, version: version)
        try Task.checkCancellation()
        // 地区查询失败仍保留已获取的地址，不把两个独立结果合并成失败。
        let countryData = try? await read(URL(string: "https://ipwho.is/\(address)?fields=success,ip,country_code")!)
        try Task.checkCancellation()
        return PublicAddress(address: address, countryCode: countryData.flatMap { Self.parseCountry($0, address: address) })
    }

    private func read(_ url: URL) async throws -> Data {
        let (bytes, response) = try await session.bytes(from: url)
        // 超限或解析失败提前结束时也终止传输，避免继续接收无用响应。
        defer { bytes.task.cancel() }
        guard let response = response as? HTTPURLResponse, response.statusCode == 200,
              response.expectedContentLength <= 8192 else { throw URLError(.badServerResponse) }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < 8192 else { throw URLError(.dataLengthExceedsMaximum) }
            data.append(byte)
        }
        return data
    }

    static func parseAddress(_ data: Data, version: IPVersion) throws -> String {
        guard data.count <= 8192, let text = String(data: data, encoding: .utf8) else {
            throw URLError(.cannotParseResponse)
        }
        let address = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard IPAddress.isValid(address, version: version) else { throw URLError(.cannotParseResponse) }
        return address
    }

    static func parseCountry(_ data: Data, address: String) -> String? {
        struct Reply: Decodable { let success: Bool; let ip: String; let country_code: String? }
        guard let value = try? JSONDecoder().decode(Reply.self, from: data), value.success,
              value.ip == address, let code = value.country_code,
              code.count == 2, code.utf8.allSatisfy({ (65...90).contains($0) }) else { return nil }
        return code
    }
}
