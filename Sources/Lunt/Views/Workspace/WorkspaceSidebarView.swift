import LuntCore
import SwiftUI

struct WorkspaceSidebarView: View {
    let mode: WorkspaceMode
    let monitors: [MonitorDefinition]
    let monitorEvents: [MonitorEvent]
    let searches: [SavedSearch]
    let searchResultsById: [UUID: [SearchResultItem]]
    @Binding var selectedMonitorId: UUID?
    @Binding var selectedSearchId: UUID?
    @Binding var searchText: String
    let onToggleMonitorEnabled: (MonitorDefinition) -> Void
    let onDeleteMonitor: (UUID) -> Void
    let onToggleSearchPinned: (SavedSearch) -> Void
    let onToggleSearchEnabled: (SavedSearch) -> Void
    let onDeleteSearch: (UUID) -> Void

    private var trimmedQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredMonitors: [MonitorDefinition] {
        guard !trimmedQuery.isEmpty else { return monitors }
        return monitors.filter {
            $0.displayName.localizedStandardContains(trimmedQuery) ||
                $0.target.idString.localizedStandardContains(trimmedQuery)
        }
    }

    private var filteredSearches: [SavedSearch] {
        guard !trimmedQuery.isEmpty else { return searches }
        return searches.filter {
            $0.name.localizedStandardContains(trimmedQuery) ||
                $0.query.localizedStandardContains(trimmedQuery) ||
                $0.type.displayName.localizedStandardContains(trimmedQuery)
        }
    }

    var body: some View {
        Group {
            if mode == .monitors {
                monitorsList
            } else {
                searchesList
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 220, ideal: 244, max: 280)
        .searchable(
            text: $searchText,
            placement: .sidebar,
            prompt: Text(
                mode == .monitors
                    ? "workspace.monitor.filter_placeholder".localized
                    : "workspace.search.filter_placeholder".localized
            )
        )
    }

    private var monitorsList: some View {
        List(selection: $selectedMonitorId) {
            Section {
                if filteredMonitors.isEmpty {
                    emptyRow(
                        trimmedQuery.isEmpty
                            ? "workspace.monitor.empty.title".localized
                            : "workspace.sidebar.no_matches".localized
                    )
                } else {
                    ForEach(filteredMonitors) { monitor in
                        monitorRow(monitor)
                            .tag(monitor.id)
                            .contextMenu {
                                Button(
                                    monitor.isEnabled
                                        ? "workspace.status.paused".localized
                                        : "workspace.status.active".localized
                                ) {
                                    onToggleMonitorEnabled(monitor)
                                }
                                Divider()
                                Button("common.delete".localized, role: .destructive) {
                                    onDeleteMonitor(monitor.id)
                                }
                            }
                    }
                }
            } header: {
                Text(String(format: "workspace.sidebar.monitors".localized, filteredMonitors.count))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var searchesList: some View {
        List(selection: $selectedSearchId) {
            Section {
                if filteredSearches.isEmpty {
                    emptyRow(
                        trimmedQuery.isEmpty
                            ? "workspace.search.empty.title".localized
                            : "workspace.sidebar.no_matches".localized
                    )
                } else {
                    ForEach(filteredSearches) { search in
                        searchRow(search)
                            .tag(search.id)
                            .contextMenu {
                                Button(
                                    search.isPinned
                                        ? "workspace.search.pinned_in_work".localized
                                        : "workspace.search.pin_to_work".localized
                                ) {
                                    onToggleSearchPinned(search)
                                }
                                Button(
                                    search.isEnabled
                                        ? "workspace.status.paused".localized
                                        : "workspace.status.enabled".localized
                                ) {
                                    onToggleSearchEnabled(search)
                                }
                                Divider()
                                Button("common.delete".localized, role: .destructive) {
                                    onDeleteSearch(search.id)
                                }
                            }
                    }
                }
            } header: {
                Text(String(format: "workspace.sidebar.searches".localized, filteredSearches.count))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func monitorRow(_ monitor: MonitorDefinition) -> some View {
        let matchingEvents = monitorEvents.filter { $0.targetId == monitor.id }
        let hasUnread = monitor.isEnabled && matchingEvents.contains { event in
            !event.isRead && monitor.eventToggles[event.kind, default: true]
        }
        let dotColor: Color = if !monitor.isEnabled {
            .secondary.opacity(0.45)
        } else if hasUnread {
            Color.accentColor
        } else {
            .green
        }

        return HStack(spacing: 8) {
            Circle()
                .fill(dotColor)
                .frame(width: 6, height: 6)

            Text(monitor.displayName)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 6)

            Text("\(matchingEvents.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.vertical, 2)
    }

    private func searchRow(_ search: SavedSearch) -> some View {
        let dotColor: Color = if !search.isEnabled {
            .secondary.opacity(0.45)
        } else if search.watchAlerts {
            Color.accentColor
        } else {
            .green
        }
        let count = searchResultsById[search.id]?.count ?? 0

        return HStack(spacing: 8) {
            Circle()
                .fill(dotColor)
                .frame(width: 6, height: 6)

            Text(search.name)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 6)

            Text(searchSuffix(for: search, count: count))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
        }
        .padding(.vertical, 2)
    }

    private func searchSuffix(for search: SavedSearch, count: Int) -> String {
        var tags: [String] = []
        if search.isPinned {
            tags.append("workspace.badge.work".localized)
        }
        if search.watchAlerts {
            tags.append("workspace.badge.watch".localized)
        }
        if tags.isEmpty {
            return "\(count)"
        }
        return "\(tags.joined(separator: " · ")) · \(count)"
    }

    private func emptyRow(_ message: String) -> some View {
        Text(message)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.vertical, 6)
    }
}
