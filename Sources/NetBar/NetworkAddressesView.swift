import AppKit
import SwiftUI
import NetBarCore

struct NetworkAddressesView: View {
    let snapshot: NetworkPanelSnapshot
    var refresh: () -> Void = {}
    @State private var copied: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("网络信息").font(.system(size: 12, weight: .medium))
                Spacer()
                if copied != nil { Text("已复制").font(.system(size: 10)).foregroundStyle(.secondary) }
                Button(action: refresh) { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless)
                    .help("重新查询本机地址及公网出口")
                    .accessibilityLabel("刷新网络信息")
            }
            if snapshot.localAddresses.isEmpty {
                addressRow("本机", value: snapshot.localReadFailed ? "读取失败" : "未发现在线 Wi-Fi／以太网地址")
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(snapshot.localAddresses) { item in
                            addressRow("本机 · \(item.interface)", value: item.address, canCopy: true)
                        }
                    }
                }
                .frame(height: snapshot.localAddresses.count > 1 || snapshot.localAddresses.first?.version == .v6 ? 42 : 20)
            }
            Divider()
            publicRow("公网 IPv4", state: snapshot.ipv4)
            publicRow("公网 IPv6", state: snapshot.ipv6)
        }
        .padding(10)
        .task(id: copied) {
            guard copied != nil else { return }
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            copied = nil
        }
        .help("公网地址来自查询服务看到的出口，代理／VPN 可能影响结果；地区为 IP 归属地。成功结果缓存 5 分钟，可手动刷新。")
    }

    private func publicRow(_ label: String, state: AddressLookupState) -> some View {
        Group {
            switch state {
            case .available(let value):
                addressRow(label, value: value.address, canCopy: true, country: value.countryCode)
            case .idle, .loading: addressRow(label, value: "正在查询…")
            case .unavailable: addressRow(label, value: "暂不可用")
            }
        }
    }

    private func addressRow(_ label: String, value: String, canCopy: Bool = false, country: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(label).font(.system(size: 10)).foregroundStyle(.secondary).frame(width: 66, alignment: .leading)
            if canCopy {
                Button {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    if pasteboard.setString(value, forType: .string) { copied = value }
                } label: {
                    Text(value.replacingOccurrences(of: ":", with: ":\u{200B}"))
                        .font(.system(size: 11, design: .monospaced))
                        .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .help("点击复制 \(value)")
                .accessibilityLabel("\(label)，\(value)，点击复制")
            } else {
                Text(value).font(.system(size: 11)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let country, let flag = flag(country) {
                Text(flag).font(.system(size: 14))
                    .help(Locale(identifier: "zh_CN").localizedString(forRegionCode: country) ?? country)
                    .accessibilityLabel(Locale(identifier: "zh_CN").localizedString(forRegionCode: country) ?? country)
            }
        }
        .frame(minHeight: 18)
    }

    private func flag(_ code: String) -> String? {
        guard code.utf8.count == 2, code.utf8.allSatisfy({ (65...90).contains($0) }) else { return nil }
        return String(String.UnicodeScalarView(code.unicodeScalars.compactMap { UnicodeScalar(127397 + $0.value) }))
    }
}
