import Foundation

public struct ProcessTraffic: Identifiable, Equatable, Sendable {
    public let pid: Int32
    public let name: String
    public let download: Double
    public let upload: Double
    public var id: Int32 { pid }
    public var isActive: Bool { download > 0 || upload > 0 }

    public init(pid: Int32, name: String, download: Double, upload: Double) {
        self.pid = pid
        self.name = name
        self.download = download
        self.upload = upload
    }
}

public enum TrafficSort: Sendable {
    case download, upload

    public func sorted(_ rows: [ProcessTraffic], ascending: Bool = false) -> [ProcessTraffic] {
        rows.sorted { left, right in
            let lhs = self == .download ? left.download : left.upload
            let rhs = self == .download ? right.download : right.upload
            if lhs != rhs { return ascending ? lhs < rhs : lhs > rhs }
            if left.name != right.name { return left.name < right.name }
            return left.pid < right.pid
        }
    }
}

public enum TrafficRate {
    public static func string(_ bytes: Double) -> String {
        let value = bytes.isFinite ? max(0, bytes) : 0
        let divisor = value >= 1_000_000 ? 1_000_000.0 : 1_000.0
        let unit = value >= 1_000_000 ? "MB/s" : "KB/s"
        return String(format: "%.2f %@", locale: Locale(identifier: "en_US_POSIX"), value / divisor, unit)
    }
}

public enum SamplingError: LocalizedError, Sendable {
    case invalidOutput
    case failed(String)
    case timedOut

    public var errorDescription: String? {
        switch self {
        case .invalidOutput: "未能读取网速样本，请重试。"
        case .failed(let reason): "采样失败：\(reason)"
        case .timedOut: "采样超时，请重试。"
        }
    }
}

public enum NetTopParser {
    /// -d 的首帧是累计值，只有第二帧才是约一秒内的流量增量。
    public static func parse(_ output: String) throws -> [ProcessTraffic] {
        var frame = 0
        var inputIndex: Int?
        var outputIndex: Int?
        var rows: [ProcessTraffic] = []
        var pids = Set<Int32>()

        for line in output.split(whereSeparator: \.isNewline) {
            let fields = csvFields(String(line))
            if fields.first == "", let input = fields.firstIndex(of: "bytes_in"),
               let output = fields.firstIndex(of: "bytes_out") {
                frame += 1
                inputIndex = input
                outputIndex = output
                continue
            }
            guard frame == 2 else { continue }
            // nettop 可能包含 kernel_task.0；PID 0 是合法内核记录。
            guard let inputIndex, let outputIndex,
                  fields.count > max(inputIndex, outputIndex),
                  let identity = fields.first,
                  let dot = identity.lastIndex(of: "."),
                  let pid = Int32(identity[identity.index(after: dot)...]), pid >= 0,
                  let download = Double(fields[inputIndex]), download.isFinite, download >= 0,
                  let upload = Double(fields[outputIndex]), upload.isFinite, upload >= 0,
                  pids.insert(pid).inserted else { throw SamplingError.invalidOutput }
            let name = String(identity[..<dot])
            // 实测 nettop 会返回“.PID”；缺少名称不应使整帧有效流量失效。
            rows.append(ProcessTraffic(pid: pid, name: name.isEmpty ? "未命名进程" : name, download: download, upload: upload))
        }
        guard frame == 2 else { throw SamplingError.invalidOutput }
        return rows
    }

    private static func csvFields(_ line: String) -> [String] {
        var result: [String] = []
        var field = ""
        var quoted = false
        var iterator = line.makeIterator()
        var current = iterator.next()
        while let character = current {
            if character == "\"" {
                if quoted {
                    let next = iterator.next()
                    if next == "\"" { field.append("\"") }
                    else { quoted = false; current = next; continue }
                } else { quoted = true }
            } else if character == ",", !quoted {
                result.append(field)
                field = ""
            } else { field.append(character) }
            current = iterator.next()
        }
        result.append(field)
        return result
    }
}
