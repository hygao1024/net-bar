import Darwin
import Foundation

public struct NetworkSpeed: Equatable, Sendable {
    public let download: Double
    public let upload: Double

    public init(download: Double, upload: Double) {
        self.download = download
        self.upload = upload
    }
}

struct InterfaceBytes: Sendable {
    let index: UInt32
    let name: String
    let received: UInt64
    let sent: UInt64
}

/// 逐接口计算差值，避免切换网卡、计数器重置或新接口加入时出现尖峰。
struct NetworkSpeedCalculator {
    private var previous: [String: InterfaceBytes] = [:]
    private var previousTime: TimeInterval?

    mutating func reset() {
        previous = [:]
        previousTime = nil
    }

    mutating func update(_ interfaces: [InterfaceBytes], time: TimeInterval) -> NetworkSpeed? {
        defer {
            previous = Dictionary(interfaces.map { ($0.name, $0) }, uniquingKeysWith: { _, new in new })
            previousTime = time
        }
        guard let previousTime else { return nil }
        let elapsed = time - previousTime
        guard elapsed.isFinite, elapsed > 0 else { return nil }
        var received = 0.0
        var sent = 0.0
        for interface in interfaces {
            guard let old = previous[interface.name], old.index == interface.index,
                  interface.received >= old.received, interface.sent >= old.sent else { continue }
            received += Double(interface.received - old.received)
            sent += Double(interface.sent - old.sent)
        }
        return NetworkSpeed(download: received / elapsed, upload: sent / elapsed)
    }
}

enum NetworkInterfaceReader {
    /// en* 的以太网/Wi-Fi 接口；排除回环、VPN、桥接与点对点接口，避免重复统计。
    static func includes(name: String, type: UInt8, flags: Int32) -> Bool {
        let suffix = name.dropFirst(2)
        return name.hasPrefix("en") && !suffix.isEmpty && suffix.allSatisfy(\.isNumber)
            && type == UInt8(IFT_ETHER)
            && flags & (IFF_UP | IFF_RUNNING) == (IFF_UP | IFF_RUNNING)
            && flags & (IFF_LOOPBACK | IFF_POINTOPOINT) == 0
    }

    static func read() throws -> [InterfaceBytes] {
        // IFLIST2 提供 64 位字节计数；不使用会在 4 GB 回绕的 if_data 计数。
        for attempt in 0..<2 {
            var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
            var length = 0
            guard sysctl(&mib, u_int(mib.count), nil, &length, nil, 0) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            var data = Data(count: length)
            let result = data.withUnsafeMutableBytes { bytes in
                sysctl(&mib, u_int(mib.count), bytes.baseAddress, &length, nil, 0)
            }
            if result != 0 {
                let code = errno
                if code == ENOMEM && attempt == 0 { continue }
                throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
            }
            return try data.withUnsafeBytes { bytes in
                var interfaces: [InterfaceBytes] = []
                var offset = 0
                guard length <= bytes.count else { throw POSIXError(.EINVAL) }
                while offset < length {
                    guard length - offset >= 4 else { throw POSIXError(.EINVAL) }
                    let size = Int(bytes.loadUnaligned(fromByteOffset: offset, as: UInt16.self))
                    guard size >= 4, size <= length - offset else { throw POSIXError(.EINVAL) }
                    if bytes[offset + 3] == UInt8(RTM_IFINFO2) {
                        guard size >= MemoryLayout<if_msghdr2>.size else { throw POSIXError(.EINVAL) }
                        let header = bytes.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                        var nameBuffer = [CChar](repeating: 0, count: Int(IFNAMSIZ))
                        if if_indextoname(UInt32(header.ifm_index), &nameBuffer) != nil {
                            let name = String(decoding: nameBuffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
                            if includes(name: name, type: header.ifm_data.ifi_type, flags: header.ifm_flags) {
                                interfaces.append(InterfaceBytes(index: UInt32(header.ifm_index), name: name,
                                    received: header.ifm_data.ifi_ibytes, sent: header.ifm_data.ifi_obytes))
                            }
                        }
                    }
                    offset += size
                }
                return interfaces
            }
        }
        throw POSIXError(.ENOMEM)
    }
}

public enum MenuBarRate {
    public static func string(_ bytes: Double, compact: Bool = false, decimalPlaces: Int = 1) -> String {
        guard bytes.isFinite, bytes >= 0 else { return "—" }
        let places = (0...2).contains(decimalPlaces) ? decimalPlaces : 1
        let units = ["KB/s", "MB/s", "GB/s"]
        let scale = pow(10, Double(places))
        var value = bytes / 1_000
        var index = 0
        // 按显示精度判断进位，避免舍入后出现 1000K 或用加号截断数值。
        while index < units.count - 1, (value * scale).rounded() / scale >= 1_000 {
            value /= 1_000
            index += 1
        }
        let unit = units[index]
        let suffix = " " + (compact ? String(unit.prefix(1)) : unit)
        return String(format: "%.*f", locale: Locale(identifier: "en_US_POSIX"), places, value) + suffix
    }
}
