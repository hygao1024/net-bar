import Foundation
import Testing
@testable import NetSpeedCore

@Suite("菜单栏显示设置")
struct MenuBarPreferencesTests {
    @Test("单位和小数位独立设置，异常精度与数值可恢复")
    func formatting() {
        #expect(MenuBarRate.string(128_600, compact: true, decimalPlaces: 0) == "129 K")
        #expect(MenuBarRate.string(128_600, compact: true, decimalPlaces: 1) == "128.6 K")
        #expect(MenuBarRate.string(2_560_000, compact: true, decimalPlaces: 2) == "2.56 M")
        #expect(MenuBarRate.string(2_560_000, decimalPlaces: 2) == "2.56 MB/s")
        #expect(MenuBarRate.string(1_000_000_000, compact: true) == "1.0 G")
        #expect(MenuBarRate.string(0, compact: true, decimalPlaces: 2) == "0.00 K")
        #expect(MenuBarRate.string(.infinity, compact: true) == "—")
        #expect(MenuBarRate.string(128_600, decimalPlaces: Int.max) == "128.6 KB/s")
        #expect(!MenuBarRate.string(Double.greatestFiniteMagnitude, compact: true).contains("+"))
        #expect(MenuBarRate.string(1_000_000_000_000, compact: true, decimalPlaces: 0) == "1000 G")
        #expect(MenuBarRate.string(999_990, decimalPlaces: 2) == "999.99 KB/s")
        #expect(MenuBarRate.string(999_999, decimalPlaces: 2) == "1.00 MB/s")
    }

    @Test("舍入到千位时切换单位，不使用加号封顶")
    func unitRounding() {
        for places in 0...2 {
            let step = pow(10, -Double(places))
            for (divisor, unit) in [(1_000.0, "M"), (1_000_000.0, "G")] {
                let rate = (1000 - step / 4) * divisor
                let expected = places == 0 ? "1" : "1." + String(repeating: "0", count: places)
                #expect(MenuBarRate.string(rate, compact: true, decimalPlaces: places) == expected + " " + unit)
                #expect(MenuBarRate.string(rate, decimalPlaces: places) == expected + " " + unit + "B/s")
            }
        }
    }

    @Test("设置自动保存，重建后保留；仅图标不会清除样式")
    @MainActor func persistence() throws {
        let suite = "NetSpeed.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = MenuBarPreferences(defaults: defaults)
        #expect(preferences.appearance == MenuBarAppearance())
        var changes = 0
        preferences.onChange = {
            changes += 1
            #expect(MenuBarPreferences(defaults: defaults).appearance == preferences.appearance)
        }
        preferences.appearance.mode = .speedOnly
        preferences.appearance.showsArrows = false
        preferences.appearance.compactUnits = true
        preferences.appearance.decimalPlaces = 2
        preferences.appearance.fontName = "Menlo-Regular"
        preferences.appearance.fontSize = 10.5
        preferences.appearance.mode = .iconOnly
        #expect(changes == 7)
        let restored = MenuBarPreferences(defaults: defaults)
        #expect(restored.appearance == preferences.appearance)
        restored.appearance.mode = .iconAndSpeed
        #expect(!restored.appearance.showsArrows && restored.appearance.compactUnits)
        #expect(restored.appearance.decimalPlaces == 2 && restored.appearance.fontName == "Menlo-Regular")
        #expect(restored.appearance.fontSize == 10.5)
        preferences.onChange = nil
    }

    @Test("字号边界、损坏数据与恢复默认")
    @MainActor func fontSizeValidation() throws {
        let suite = "NetSpeed.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        for stored in ["-1", "100", "\"wrong\"", "null"] {
            defaults.set(Data("{\"fontSize\":\(stored),\"compactUnits\":true}".utf8),
                         forKey: MenuBarPreferences.storageKey)
            let preferences = MenuBarPreferences(defaults: defaults)
            #expect(preferences.appearance.fontSize == 9)
            #expect(preferences.appearance.compactUnits)
        }
        let preferences = MenuBarPreferences(defaults: defaults)
        for size in [7.0, 9.5, 12.0] {
            preferences.appearance.fontSize = size
            #expect(MenuBarPreferences(defaults: defaults).appearance.fontSize == size)
        }
        for size in [Double.nan, .infinity, -.infinity, 0, 13] {
            preferences.appearance.fontSize = size
            #expect(preferences.appearance.fontSize == 9)
        }
        preferences.appearance.fontSize = 12
        preferences.appearance = MenuBarAppearance()
        #expect(MenuBarPreferences(defaults: defaults).appearance.fontSize == 9)
    }

    @Test("损坏或旧设置逐字段恢复，未知模式不会隐藏入口")
    @MainActor func invalidPersistence() throws {
        let suite = "NetSpeed.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data("broken".utf8), forKey: MenuBarPreferences.storageKey)
        #expect(MenuBarPreferences(defaults: defaults).appearance == MenuBarAppearance())
        defaults.set(Data(#"{"mode":"hidden","decimalPlaces":-9,"showsArrows":false,"compactUnits":"wrong"}"#.utf8),
                     forKey: MenuBarPreferences.storageKey)
        let preferences = MenuBarPreferences(defaults: defaults)
        #expect(preferences.appearance.mode == .iconAndSpeed)
        #expect(preferences.appearance.decimalPlaces == 1)
        #expect(!preferences.appearance.showsArrows)
        #expect(!preferences.appearance.compactUnits)
        #expect(preferences.appearance.fontName.isEmpty)
        #expect(preferences.appearance.fontSize == 9, "旧设置缺少字号时使用原默认值")
        preferences.appearance.decimalPlaces = 999
        #expect(preferences.appearance.decimalPlaces == 1)
        preferences.appearance.fontName = String(repeating: "x", count: 129)
        #expect(preferences.appearance.fontName.isEmpty)
    }
}
