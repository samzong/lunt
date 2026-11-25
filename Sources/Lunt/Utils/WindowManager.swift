import AppKit
import Foundation
import SwiftUI

@MainActor
public final class WindowManager: ObservableObject {
    public static let shared = WindowManager()

    @Published public var activeWindow: WindowIdentifier?

    private init() {}

    public func open(_ window: WindowIdentifier) {
        activeWindow = window

        if let url = URL(string: "lunt://window/\(window.rawValue)") {
            NSWorkspace.shared.open(url)
        }
    }
}
