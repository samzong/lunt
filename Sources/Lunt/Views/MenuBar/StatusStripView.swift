import AppKit
import LuntCore
import SwiftUI

struct StatusStripView: View {
    let notice: String?
    let isSyncing: Bool
    let lastSyncedAt: Date?
    let isAuthenticated: Bool

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(notice != nil ? Color.accentColor : Color.green)
                        .frame(width: 6, height: 6)

                    Text(statusText)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text("menubar.shortcuts.hint".localized)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .fixedSize()
            }
            .frame(height: 30)
            .padding(.horizontal, 12)
            .background(Color.primary.opacity(0.04))
        }
    }

    private var statusText: String {
        if let notice {
            return notice
        }
        if !isAuthenticated {
            return "menubar.status.not_signed_in".localized
        }
        if isSyncing {
            return "menubar.status.syncing".localized
        }
        if let lastSyncedAt {
            let template = "menubar.status.synced".localized
            let relative = lastSyncedAt.timeAgo()
            if template.contains("%@") {
                return String(format: template, relative)
            }
            return "\(template) \(relative)"
        }
        return "menubar.status.ready".localized
    }
}

enum PopoverKeyAction {
    case closeQuickFilter
    case openShortcut(Int)
    case refresh
    case toggleQuickFilter
    case moveSelection(Int)
    case openSelected
    case toggleReadSelected
}

private struct UncheckedEventBox: @unchecked Sendable {
    let event: NSEvent
}

private struct UncheckedOptionalEventBox: @unchecked Sendable {
    let event: NSEvent?
}

@MainActor
final class PopoverKeyMonitor {
    var handler: ((NSEvent) -> NSEvent?)?
    private var monitor: Any?

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            let incoming = UncheckedEventBox(event: event)
            return MainActor.assumeIsolated {
                UncheckedOptionalEventBox(event: self?.handler?(incoming.event) ?? incoming.event)
            }.event
        }
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    static func action(
        for event: NSEvent,
        quickFilterOpen: Bool,
        hasRows: Bool
    ) -> PopoverKeyAction? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""

        if event.keyCode == 53, quickFilterOpen {
            return .closeQuickFilter
        }
        if flags == .command, let digit = Int(chars), (1 ... 9).contains(digit) {
            return .openShortcut(digit - 1)
        }
        if flags == .command, chars == "r" {
            return .refresh
        }
        if flags.isEmpty, chars == "/" {
            return .toggleQuickFilter
        }
        guard hasRows else { return nil }

        switch event.keyCode {
        case 125:
            return .moveSelection(1)
        case 126:
            return .moveSelection(-1)
        case 36, 76:
            return .openSelected
        default:
            if flags.isEmpty, chars == "e" {
                return .toggleReadSelected
            }
            return nil
        }
    }
}

struct PopoverWindowAccessor: NSViewRepresentable {
    let onWindowChange: (NSWindow?) -> Void

    func makeNSView(context _: Context) -> WindowObserverView {
        let view = WindowObserverView()
        view.onWindowChange = onWindowChange
        return view
    }

    func updateNSView(_ nsView: WindowObserverView, context _: Context) {
        nsView.onWindowChange = onWindowChange
        onWindowChange(nsView.window)
    }

    final class WindowObserverView: NSView {
        var onWindowChange: ((NSWindow?) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onWindowChange?(window)
        }
    }
}
