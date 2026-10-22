import AppKit
import SwiftUI
import NetSpeedCore

enum PanelLayout {
    static let width: CGFloat = 380
    static let height: CGFloat = 440
    static let rateWidth: CGFloat = 80
    static let columnSpacing: CGFloat = 6
}

struct TrafficView: View {
    @ObservedObject var monitor: TrafficMonitor

    var body: some View {
        TrafficPanel(
            rows: monitor.rows,
            updatedAt: monitor.updatedAt,
            errorMessage: monitor.errorMessage,
            retry: { monitor.start() },
            quit: { NSApp.terminate(nil) }
        )
    }
}

/// 纯展示视图也用于离屏渲染，预览不会启动采样或改变系统外观。
struct TrafficPanel: View {
    let rows: [ProcessTraffic]
    let updatedAt: Date?
    let errorMessage: String?
    var retry: () -> Void = {}
    var quit: () -> Void = {}

    @State private var sort: TrafficSort = .download
    @State private var ascending = false

    private var activeCount: Int { rows.filter(\.isActive).count }

    var body: some View {
        VStack(spacing: 6) {
            header
                .modifier(PanelGroup())
            VStack(spacing: 0) {
                if errorMessage != nil || updatedAt == nil || rows.isEmpty {
                    columnHeaders
                }
                content
            }
            .modifier(PanelGroup())
            footer
                .modifier(PanelGroup())
        }
        .padding(8)
        .frame(width: PanelLayout.width, height: PanelLayout.height)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("应用网速")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color(nsColor: .systemBlue))
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: 7) {
                Circle()
                    .fill(errorMessage != nil ? Color.orange : updatedAt == nil ? Color.secondary : Color.green)
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
                Text(headerDetail)
                Spacer(minLength: 8)
                Text(updatedAt == nil ? (errorMessage == nil ? "约一秒" : "已暂停") : "共 \(rows.count) 个进程")
                    .foregroundStyle(.secondary)
                    .help(updateDescription)
            }
            .font(.system(size: 12))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private var headerDetail: String {
        if errorMessage != nil { return "采样暂不可用" }
        if updatedAt == nil { return "正在读取网速" }
        return "\(activeCount) 个进程正在传输"
    }

    private var updateDescription: String {
        guard let updatedAt else { return "仅在面板展开时采样" }
        return "更新于 \(updatedAt.formatted(date: .omitted, time: .standard))"
    }

    private var columnHeaders: some View {
        HStack(spacing: PanelLayout.columnSpacing) {
            Text("应用 / 进程")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            sortButton("下载", column: .download)
            sortButton("上传", column: .upload)
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.65))
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder private var content: some View {
        if let errorMessage {
            message(symbol: "wifi.exclamationmark", title: "无法读取网速", detail: errorMessage) {
                Button("重新采样", action: retry)
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
            }
        } else if updatedAt == nil {
            VStack(spacing: 12) {
                ProgressView().controlSize(.small).accessibilityLabel("正在读取网速")
                Text("正在读取网速")
                    .font(.system(size: 13, weight: .medium))
                Text("首个样本需要约一秒")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if rows.isEmpty {
            message(symbol: "network", title: "暂无联网进程", detail: "检测到网络活动后会自动显示") { EmptyView() }
        } else {
            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                    Section {
                        ForEach(Array(sort.sorted(rows, ascending: ascending).enumerated()), id: \.element.id) { index, row in
                            TrafficRow(row: row)
                                .background(index.isMultiple(of: 2)
                                    ? Color.clear
                                    : Color.primary.opacity(0.025))
                        }
                    } header: {
                        // 表头与数据共用滚动区域，滚动条显示或隐藏时列宽始终一致。
                        columnHeaders
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Text("关闭即暂停")
                .help("关闭面板后停止采样，重新展开时读取新样本")
            Spacer(minLength: 8)
            Button("退出", action: quit)
                .buttonStyle(.borderless)
                .foregroundStyle(Color(nsColor: .systemBlue))
                .keyboardShortcut("q", modifiers: .command)
                .help("退出应用网速（⌘Q）")
                .accessibilityLabel("退出应用网速")
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .frame(height: 28)
    }

    private func sortButton(_ title: String, column: TrafficSort) -> some View {
        Button {
            if sort == column { ascending.toggle() }
            else { sort = column; ascending = false }
        } label: {
            Text(title)
                .font(.system(size: 12, weight: sort == column ? .medium : .regular))
                .foregroundStyle(sort == column ? Color(nsColor: .systemBlue) : Color.secondary)
                .frame(width: PanelLayout.rateWidth, height: 26, alignment: .trailing)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("按\(title)排序，再次点击切换升降序")
        .accessibilityLabel("按\(title)排序")
        .accessibilityValue(sort == column ? (ascending ? "升序" : "降序") : "未选中")
    }

    private func message<Content: View>(symbol: String, title: String, detail: String, @ViewBuilder action: () -> Content) -> some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(title).font(.system(size: 13, weight: .semibold))
            Text(detail)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            action()
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct PanelGroup: ViewModifier {
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content
            .background(Color(nsColor: .textBackgroundColor).opacity(0.65))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color(nsColor: .separatorColor).opacity(contrast == .increased ? 1 : 0.7), lineWidth: 1)
            }
    }
}

private struct TrafficRow: View {
    let row: ProcessTraffic

    var body: some View {
        HStack(spacing: PanelLayout.columnSpacing) {
            HStack(spacing: 6) {
                ProcessIcon(pid: row.pid)
                Text(row.name)
                    .font(.system(size: 12))
                    .lineLimit(1).truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            rate(row.download)
            rate(row.upload)
        }
        .padding(.horizontal, 10)
        .frame(height: 26)
        .help("\(row.name)\n进程编号：\(row.pid)")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(row.name)，进程编号 \(row.pid)")
        .accessibilityValue("下载 \(TrafficRate.string(row.download))，上传 \(TrafficRate.string(row.upload))")
    }

    private func rate(_ bytes: Double) -> some View {
        let parts = TrafficRate.string(bytes).split(separator: " ", maxSplits: 1)
        return HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(String(parts[0]))
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(bytes > 0 ? .primary : .secondary)
            Text(String(parts[1]))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.85)
        .frame(width: PanelLayout.rateWidth, alignment: .trailing)
    }
}

private struct ProcessIcon: View {
    let pid: Int32
    @State private var icon: NSImage?

    var body: some View {
        Group {
            if let icon {
                Image(nsImage: icon).resizable().interpolation(.high)
            } else {
                Image(systemName: "gearshape")
                    .resizable()
                    .foregroundStyle(.secondary)
                    .padding(3)
            }
        }
        .frame(width: 16, height: 16)
        .onAppear { icon = NSRunningApplication(processIdentifier: pid)?.icon }
        .accessibilityHidden(true)
    }
}
