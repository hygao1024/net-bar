import Combine
import Foundation

public enum MenuBarDisplayMode: String, Codable, CaseIterable, Sendable {
    case iconAndSpeed, speedOnly, iconOnly

    public var showsSpeed: Bool { self != .iconOnly }
    public var showsIcon: Bool { self != .speedOnly }
}

public struct MenuBarAppearance: Codable, Equatable, Sendable {
    public var mode: MenuBarDisplayMode = .iconAndSpeed
    public var showsArrows = true
    public var compactUnits = false
    public var decimalPlaces = 1
    /// 空字符串表示系统等宽数字字体；其他值为已安装字体的 PostScript 名称。
    public var fontName = ""
    public static let fontSizeRange = 7.0...12.0
    public var fontSize = 9.0

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case mode, showsArrows, compactUnits, decimalPlaces, fontName, fontSize
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        mode = (try? values.decode(MenuBarDisplayMode.self, forKey: .mode)) ?? .iconAndSpeed
        showsArrows = (try? values.decode(Bool.self, forKey: .showsArrows)) ?? true
        compactUnits = (try? values.decode(Bool.self, forKey: .compactUnits)) ?? false
        decimalPlaces = (try? values.decode(Int.self, forKey: .decimalPlaces)) ?? 1
        fontName = (try? values.decode(String.self, forKey: .fontName)) ?? ""
        fontSize = (try? values.decode(Double.self, forKey: .fontSize)) ?? 9
        self = normalized
    }

    var normalized: Self {
        var result = self
        if !(0...2).contains(decimalPlaces) { result.decimalPlaces = 1 }
        if !Self.fontSizeRange.contains(fontSize) { result.fontSize = 9 }
        if fontName.count > 128 { result.fontName = "" }
        return result
    }
}

@MainActor
public final class MenuBarPreferences: ObservableObject {
    @Published public var appearance: MenuBarAppearance {
        didSet {
            if appearance != appearance.normalized {
                appearance = appearance.normalized
            }
            guard appearance != oldValue else { return }
            if let data = try? JSONEncoder().encode(appearance) {
                defaults.set(data, forKey: Self.storageKey)
            }
            onChange?()
        }
    }
    public var onChange: (() -> Void)?
    private let defaults: UserDefaults
    static let storageKey = "menuBarAppearance"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode(MenuBarAppearance.self, from: data) {
            appearance = saved
        } else {
            appearance = MenuBarAppearance()
        }
    }
}
