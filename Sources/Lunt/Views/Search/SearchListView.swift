import AppKit
import LuntCore
import SwiftUI

struct SearchListView: View {
    @Environment(SearchService.self) private var searchService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openWindow) private var openWindow

    @Binding var selectedSearchId: UUID?

    let onItemTapped: (SearchResultItem) -> Void

    var body: some View {
        VStack(spacing: 0) {
            if let activeErrorMessage,
               !(searchService.isLoading && displayedItems.isEmpty && displayedRepositories.isEmpty) {
                InlineErrorBanner(message: activeErrorMessage)
            }
            content
        }
    }

    private var activeErrorMessage: String? {
        if let selectedSearchId {
            return searchService.errorsBySearchId[selectedSearchId]
        }
        let enabledErrors = searchService.savedSearches
            .filter(\.isEnabled)
            .compactMap { search -> String? in
                guard let error = searchService.errorsBySearchId[search.id] else { return nil }
                return "\(search.name): \(error)"
            }
        guard !enabledErrors.isEmpty else { return nil }
        return enabledErrors.joined(separator: "\n")
    }

    // MARK: - Content

    private var content: some View {
        Group {
            if searchService.savedSearches.isEmpty {
                emptyStateNoSearches
            } else if searchService.isLoading, displayedItems.isEmpty, displayedRepositories.isEmpty {
                loadingView
            } else if selectedSearchId == nil {
                if displayedItems.isEmpty, displayedRepositories.isEmpty {
                    emptyStateNoResults
                } else {
                    combinedResultsList
                }
            } else if isRepositorySearch {
                repositoryContent
            } else {
                if displayedItems.isEmpty {
                    emptyStateNoResults
                } else {
                    resultsList
                }
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: displayedItems.count)
    }

    // MARK: - Computed Properties

    private var isRepositorySearch: Bool {
        guard let selectedSearchId else { return false }
        return searchService.savedSearches.first { $0.id == selectedSearchId }?.type == .repository
    }

    private var displayedItems: [SearchResultItem] {
        if let selectedSearchId {
            searchService.resultsBySearchId[selectedSearchId] ?? []
        } else {
            searchService.items
        }
    }

    private var displayedRepositories: [RepositorySearchItem] {
        if let selectedSearchId {
            searchService.repositoryResultsBySearchId[selectedSearchId] ?? []
        } else {
            searchService.repositoryItems
        }
    }

    // MARK: - Combined Results List (All mode)

    private var combinedResultsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(displayedItems) { item in
                    SearchRowView(item: item)
                        .contentShape(Rectangle())
                        .onTapGesture { onItemTapped(item) }

                    if item.id != displayedItems.last?.id || !displayedRepositories.isEmpty {
                        Divider()
                            .padding(.leading, 44)
                    }
                }

                ForEach(displayedRepositories) { repo in
                    RepositoryRowView(repository: repo) {
                        if let url = repo.webURL {
                            NSWorkspace.shared.open(url)
                        }
                    }

                    if repo.id != displayedRepositories.last?.id {
                        Divider()
                            .padding(.leading, 44)
                    }
                }
            }
        }
    }

    // MARK: - Results List (Issue/PR only)

    private var resultsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(displayedItems) { item in
                    SearchRowView(item: item)
                        .contentShape(Rectangle())
                        .onTapGesture { onItemTapped(item) }

                    if item.id != displayedItems.last?.id {
                        Divider()
                            .padding(.leading, 44)
                    }
                }
            }
        }
    }

    // MARK: - Repository Content

    @ViewBuilder private var repositoryContent: some View {
        if displayedRepositories.isEmpty {
            if searchService.isLoading {
                loadingView
            } else {
                emptyStateNoResults
            }
        } else {
            repositoryList
        }
    }

    private var repositoryList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(displayedRepositories) { repo in
                    RepositoryRowView(repository: repo) {
                        if let url = repo.webURL {
                            NSWorkspace.shared.open(url)
                        }
                    }

                    if repo.id != displayedRepositories.last?.id {
                        Divider()
                            .padding(.leading, 44)
                    }
                }
            }
        }
    }

    // MARK: - Empty States

    private var emptyStateNoSearches: some View {
        PolishedEmptyStateView(
            title: "search.management.empty.title".localized,
            message: "search.management.empty.description".localized,
            systemImage: "magnifyingglass"
        ) {
            Button("search.list.manage".localized) {
                openWindow(id: WindowIdentifier.searchManagement.rawValue)
                Task { @MainActor in
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
    }

    private var emptyStateNoResults: some View {
        PolishedEmptyStateView(
            title: "search.list.no_results.title".localized,
            message: "search.list.no_results.description".localized,
            systemImage: "tray",
            accent: .secondary
        )
    }

    private var loadingView: some View {
        VStack {
            Spacer()
            ProgressView("search.list.loading".localized)
            Spacer()
        }
    }
}

struct InlineErrorBanner: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
                .padding(.top, 1)

            Text(message)
                .font(.caption)
                .foregroundStyle(.primary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.12))
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
}

#Preview {
    SearchListView(selectedSearchId: .constant(nil)) { _ in }
        .environment(SearchService(session: GitHubSession()))
        .frame(width: 360, height: 400)
}
