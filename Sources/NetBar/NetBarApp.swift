import AppKit
import SwiftUI
import NetBarCore

@main
struct NetBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}
