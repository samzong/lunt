import AppKit
import LuntCore
import SwiftUI

struct WorkspaceMonitorDetailView: View {
    let monitor: MonitorDefinition
    @Binding var selectedMonitorId: UUID?
    @Binding var confirmingDeleteId: UUID?
    let onEdit: () -> Void
    let onStatus: (String) -> Void

    @Environment(MonitorStore.self) private var monitorStore
    @Environment(MonitorEngine.self) private var monitorEngine
    @State private var isSyncing = false

    private let eventKinds: [(key: String, titleKey: String)] = [
        ("commit", "workspace.event_kind.commit"),
        ("pr", "workspace.event_kind.pr"),
        ("issue", "workspace.event_kind.issue"),
        ("release", "workspace.event_kind.release"),
        ("comment", "workspace.event_kind.comment"),
    ]

    private var matchedEvents: [MonitorEvent] {
        monitorStore.events.filter { event in
            event.targetId == monitor.id && monitor.eventToggles[event.kind, default: true]
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if confirmingDeleteId == monitor.id {
                deleteBanner
            }

            detailHeader

            if let errorMessage = monitorEngine.errorsByMonitorId[monitor.id] {
                InlineErrorBanner(message: errorMessage)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            filterChipsRow

            Text("workspace.monitor.recent_events".localized)
                .font(.subheadline.weight(.semibold))

            eventsList
        }
    }

    private var deleteBanner: some View {
        HStack(spacing: 10) {
            Text(String(format: "workspace.monitor.delete_confirm".localized, monitor.displayName))
                .font(.caption)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            Button("common.cancel".localized) {
                confirmingDeleteId = nil
            }
            .liquidGlassButtonStyle()
            .controlSize(.small)

            Button("workspace.action.confirm_delete".localized, role: .destructive) {
                monitorStore.removeMonitor(id: monitor.id)
                confirmingDeleteId = nil
                selectedMonitorId = monitorStore.monitors.first?.id
            }
            .liquidGlassButtonStyle(prominent: true)
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.red.opacity(0.35), lineWidth: 1))
    }

    private var detailHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(monitor.displayName)
                        .font(.title3.weight(.semibold))
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        Text(monitor.target.badgeLabel)
                            .font(.system(.caption, design: .monospaced))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(
                                Color.primary.opacity(0.1),
                                lineWidth: 1
                            ))

                        Text(lastSyncedText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 8)

                HStack(spacing: 6) {
                    Button {
                        monitorStore.updateMonitor(id: monitor.id, isEnabled: !monitor.isEnabled)
                    } label: {
                        Text(monitor.isEnabled ? "workspace.status.active".localized : "workspace.status.paused".localized)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(monitor.isEnabled ? .green : .secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(monitor.isEnabled ? Color.green.opacity(0.12) : Color.primary.opacity(0.05), in: Capsule())
                            .overlay(Capsule().strokeBorder(
                                monitor.isEnabled ? Color.green.opacity(0.4) : Color.primary.opacity(0.14),
                                lineWidth: 1
                            ))
                    }
                    .buttonStyle(.plain)

                    Button {
                        Task { await syncNow() }
                    } label: {
                        HStack(spacing: 5) {
                            if isSyncing {
                                ProgressView().controlSize(.mini)
                            } else {
                                Image(systemName: "arrow.triangle.2.circlepath").font(.caption)
                            }
                            Text("workspace.monitor.sync_now".localized)
                        }
                    }
                    .liquidGlassButtonStyle()
                    .controlSize(.small)
                    .disabled(isSyncing)

                    Button(action: onEdit) {
                        Image(systemName: "pencil")
                    }
                    .liquidGlassButtonStyle()
                    .controlSize(.small)
                    .help("common.edit".localized)
                    .accessibilityLabel("common.edit".localized)

                    Button(role: .destructive) {
                        confirmingDeleteId = monitor.id
                    } label: {
                        Image(systemName: "trash")
                    }
                    .liquidGlassButtonStyle()
                    .controlSize(.small)
                    .help("workspace.monitor.delete".localized)
                    .accessibilityLabel("workspace.monitor.delete".localized)
                }
            }

            Divider()
        }
    }

    private var filterChipsRow: some View {
        HStack(spacing: 6) {
            ForEach(eventKinds, id: \.key) { kind in
                let isSelected = monitor.eventToggles[kind.key, default: true]
                Button {
                    var toggles = monitor.eventToggles
                    toggles[kind.key] = !isSelected
                    monitorStore.updateMonitorToggles(id: monitor.id, toggles: toggles)
                } label: {
                    Text(kind.titleKey.localized)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(isSelected ? .primary : .secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(isSelected ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.05), in: Capsule())
                        .overlay(Capsule().strokeBorder(
                            isSelected ? Color.accentColor.opacity(0.4) : Color.primary.opacity(0.1),
                            lineWidth: 1
                        ))
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder private var eventsList: some View {
        if matchedEvents.isEmpty {
            PolishedEmptyStateView(
                title: "workspace.monitor.recent_events".localized,
                message: "workspace.monitor.no_events".localized,
                systemImage: "waveform.path.ecg",
                accent: .secondary
            )
            .frame(maxWidth: .infinity, minHeight: 200)
        } else {
            LazyVStack(spacing: 2) {
                ForEach(matchedEvents) { event in
                    UnifiedItemRow(
                        model: .fromMonitorEvent(event),
                        isActive: false,
                        isCommandHeld: false,
                        shortcutNumber: nil,
                        onOpen: {
                            if !event.isRead {
                                monitorStore.markEventRead(id: event.id)
                            }
                            if let url = URL.validatedGitHubWebURL(from: event.url) {
                                NSWorkspace.shared.open(url)
                            }
                        },
                        onToggleRead: {
                            monitorStore.toggleEventRead(id: event.id)
                        }
                    )
                }
            }
        }
    }

    private var lastSyncedText: String {
        if let date = monitorStore.lastSyncedAt[monitor.id] {
            return String(format: "workspace.last_synced".localized, date.timeAgo())
        }
        return "workspace.last_synced_never".localized
    }

    @MainActor
    private func syncNow() async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        await monitorEngine.sync(monitor: monitor)
        onStatus(String(format: "workspace.monitor.synced_status".localized, monitor.displayName))
    }
}
