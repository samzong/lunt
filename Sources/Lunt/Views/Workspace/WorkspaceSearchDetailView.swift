import AppKit
import LuntCore
import SwiftUI

struct WorkspaceSearchDetailView: View {
    let search: SavedSearch
    @Binding var selectedSearchId: UUID?
    @Binding var confirmingDeleteId: UUID?
    let onEdit: () -> Void

    @Environment(GitHubSession.self) private var session
    @Environment(SearchService.self) private var searchService

    private var results: [SearchResultItem] {
        searchService.resultsBySearchId[search.id] ?? []
    }

    private var queryWebURL: URL? {
        let trimmed = search.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
        else { return nil }
        return URL(string: "https://github.com/search?q=\(encoded)")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if confirmingDeleteId == search.id {
                deleteBanner
            }

            detailHeader

            Text(
                search.watchAlerts
                    ? "workspace.search.watch_hint_on".localized
                    : "workspace.search.watch_hint_off".localized
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            if let errorMessage = searchService.errorsBySearchId[search.id] {
                InlineErrorBanner(message: errorMessage)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            Text(String(format: "workspace.search.matches_header".localized, results.count))
                .font(.subheadline.weight(.semibold))

            resultsList
        }
        .task(id: search.id) {
            if search.isEnabled, session.isAuthenticated, searchService.resultsBySearchId[search.id] == nil {
                await searchService.syncSearch(id: search.id)
            }
        }
    }

    private var deleteBanner: some View {
        HStack(spacing: 10) {
            Text(String(format: "workspace.search.delete_confirm".localized, search.name))
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
                searchService.deleteSearch(id: search.id)
                confirmingDeleteId = nil
                selectedSearchId = searchService.savedSearches.first?.id
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
                    Text(search.name)
                        .font(.title3.weight(.semibold))
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        Text(search.query)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .lineLimit(2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(
                                Color.primary.opacity(0.1),
                                lineWidth: 1
                            ))

                        if let url = queryWebURL {
                            Link(destination: url) {
                                Image(systemName: "arrow.up.forward.square").font(.caption)
                            }
                            .help("workspace.search.open_github".localized)
                        }

                        Text(lastSyncedText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 8)

                HStack(spacing: 6) {
                    switchPill(
                        title: search.isPinned ? "workspace.search.pinned_in_work".localized : "workspace.search.pin_to_work".localized,
                        isActive: search.isPinned,
                        activeColor: .accentColor
                    ) {
                        searchService.updateSearch(id: search.id, options: .init(isPinned: !search.isPinned))
                    }

                    switchPill(
                        title: search.watchAlerts ? "workspace.search.watch_on".localized : "workspace.search.watch_off".localized,
                        isActive: search.watchAlerts,
                        activeColor: .accentColor
                    ) {
                        let nextValue = !search.watchAlerts
                        searchService.updateSearch(id: search.id, options: .init(watchAlerts: nextValue))
                        if nextValue, session.isAuthenticated {
                            Task { await searchService.syncSearch(id: search.id) }
                        }
                    }

                    switchPill(
                        title: search.isEnabled ? "workspace.status.enabled".localized : "workspace.status.paused".localized,
                        isActive: search.isEnabled,
                        activeColor: .green
                    ) {
                        searchService.toggleSearch(id: search.id)
                    }

                    Button {
                        Task { await searchService.syncSearch(id: search.id) }
                    } label: {
                        if searchService.isLoading {
                            ProgressView().controlSize(.mini)
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }
                    }
                    .liquidGlassButtonStyle()
                    .controlSize(.small)
                    .disabled(searchService.isLoading)
                    .help("workspace.monitor.sync_now".localized)

                    Button(action: onEdit) {
                        Image(systemName: "pencil")
                    }
                    .liquidGlassButtonStyle()
                    .controlSize(.small)
                    .help("common.edit".localized)
                    .accessibilityLabel("common.edit".localized)

                    Button(role: .destructive) {
                        confirmingDeleteId = search.id
                    } label: {
                        Image(systemName: "trash")
                    }
                    .liquidGlassButtonStyle()
                    .controlSize(.small)
                    .help("workspace.search.delete".localized)
                    .accessibilityLabel("workspace.search.delete".localized)
                }
            }

            Divider()
        }
    }

    private func switchPill(
        title: String,
        isActive: Bool,
        activeColor: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(isActive ? activeColor : .secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(isActive ? activeColor.opacity(0.12) : Color.primary.opacity(0.05), in: Capsule())
                .overlay(Capsule().strokeBorder(isActive ? activeColor.opacity(0.4) : Color.primary.opacity(0.14), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var resultsList: some View {
        if results.isEmpty {
            PolishedEmptyStateView(
                title: String(format: "workspace.search.matches_header".localized, 0),
                message: "workspace.search.no_matches".localized,
                systemImage: "magnifyingglass",
                accent: .secondary
            )
            .frame(maxWidth: .infinity, minHeight: 200)
        } else {
            LazyVStack(spacing: 2) {
                ForEach(results) { item in
                    UnifiedItemRow(
                        model: .fromSearchResult(item),
                        isActive: false,
                        isCommandHeld: false,
                        shortcutNumber: nil,
                        onOpen: {
                            if let url = item.webURL {
                                NSWorkspace.shared.open(url)
                            }
                        },
                        onToggleRead: nil
                    )
                }
            }
        }
    }

    private var lastSyncedText: String {
        if let lastSyncedAt = searchService.lastSyncedAt {
            return String(format: "workspace.last_synced".localized, lastSyncedAt.timeAgo())
        }
        return "workspace.last_synced_never".localized
    }
}
