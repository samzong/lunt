import LuntCore
import SwiftUI

struct MenuBarEventRow: View {
    let event: MonitorEvent
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconForEventKind(event.kind))
                .font(.system(size: 13))
                .foregroundStyle(colorForEventKind(event.kind))
                .frame(width: 24, height: 24)
                .background(colorForEventKind(event.kind).opacity(0.12))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    if !event.actor.isEmpty {
                        Text("@\(event.actor)")
                            .fontWeight(.semibold)
                    }
                    Text(event.repo)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(event.occurredAt.timeAgo())
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .font(.caption)

                Text(event.title)
                    .font(.subheadline)
                    .foregroundStyle(event.isRead ? .secondary : .primary)
                    .fontWeight(event.isRead ? .regular : .semibold)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
    }

    private func iconForEventKind(_ kind: String) -> String {
        switch kind {
        case "commit": "arrow.triangle.pull"
        case "issue": "exclamationmark.bubble"
        case "pr": "arrow.triangle.merge"
        case "release": "shippingbox"
        case "comment": "text.bubble"
        case "code_match": "doc.text.magnifyingglass"
        default: "bell"
        }
    }

    private func colorForEventKind(_ kind: String) -> Color {
        switch kind {
        case "commit": .blue
        case "issue": .green
        case "pr": .purple
        case "release": .orange
        case "comment": .teal
        case "code_match": .cyan
        default: .secondary
        }
    }
}
