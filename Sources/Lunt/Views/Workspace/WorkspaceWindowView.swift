import LuntCore
import SwiftUI

struct WorkspaceWindowView: View {
    @Environment(SearchService.self) private var searchService
    @Environment(MonitorStore.self) private var monitorStore
    @Environment(WorkspaceNavigationState.self) private var workspaceNavigationState

    @State private var selectedMonitorId: UUID?
    @State private var selectedSearchId: UUID?
    @State private var sidebarSearchText = ""
    @State private var isCreatingNew = false
    @State private var editingMonitor: MonitorDefinition?
    @State private var editingSearch: SavedSearch?
    @State private var confirmingDeleteMonitorId: UUID?
    @State private var confirmingDeleteSearchId: UUID?
    @State private var statusMessage: String?
    @State private var statusTask: Task<Void, Never>?

    private var currentMonitor: MonitorDefinition? {
        if let id = selectedMonitorId,
           let match = monitorStore.monitors.first(where: { $0.id == id }) {
            return match
        }
        return monitorStore.monitors.first
    }

    private var currentSearch: SavedSearch? {
        if let id = selectedSearchId,
           let match = searchService.savedSearches.first(where: { $0.id == id }) {
            return match
        }
        return searchService.savedSearches.first
    }

    private var modeBinding: Binding<WorkspaceMode> {
        Binding(
            get: { workspaceNavigationState.selectedMode },
            set: { newMode in
                workspaceNavigationState.selectedMode = newMode
                resetTransientUI()
                ensureValidSelection()
            }
        )
    }

    var body: some View {
        NavigationSplitView {
            WorkspaceSidebarView(
                mode: workspaceNavigationState.selectedMode,
                monitors: monitorStore.monitors,
                monitorEvents: monitorStore.events,
                searches: searchService.savedSearches,
                searchResultsById: searchService.resultsBySearchId,
                selectedMonitorId: $selectedMonitorId,
                selectedSearchId: $selectedSearchId,
                searchText: $sidebarSearchText,
                onToggleMonitorEnabled: { monitor in
                    monitorStore.updateMonitor(id: monitor.id, isEnabled: !monitor.isEnabled)
                },
                onDeleteMonitor: { id in
                    selectedMonitorId = id
                    confirmingDeleteMonitorId = id
                },
                onToggleSearchPinned: { search in
                    searchService.updateSearch(id: search.id, options: .init(isPinned: !search.isPinned))
                },
                onToggleSearchEnabled: { search in
                    searchService.toggleSearch(id: search.id)
                },
                onDeleteSearch: { id in
                    selectedSearchId = id
                    confirmingDeleteSearchId = id
                }
            )
        } detail: {
            detailContent
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 900, minHeight: 520)
        .liquidWindowBackground()
        .navigationTitle(WindowIdentifier.workspace.title)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Picker("", selection: modeBinding) {
                    Text("workspace.mode.monitors".localized).tag(WorkspaceMode.monitors)
                    Text("workspace.mode.searches".localized).tag(WorkspaceMode.searches)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            if let statusMessage {
                ToolbarItem(placement: .automatic) {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.primary.opacity(0.06), in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.1), lineWidth: 1))
                }
            }

            ToolbarItem(placement: .primaryAction) {
                Button(action: toggleCreateNew) {
                    Label(
                        workspaceNavigationState.selectedMode == .monitors
                            ? "workspace.action.new_monitor".localized
                            : "workspace.action.new_search".localized,
                        systemImage: "plus"
                    )
                }
                .liquidGlassButtonStyle()
            }
        }
        .onAppear {
            applyPendingNavigation()
            ensureValidSelection()
        }
        .onDisappear { statusTask?.cancel() }
        .onChange(of: workspaceNavigationState.pendingMode) { _, _ in applyPendingNavigation() }
        .onChange(of: selectedMonitorId) { _, _ in
            confirmingDeleteMonitorId = nil
            editingMonitor = nil
        }
        .onChange(of: selectedSearchId) { _, _ in
            confirmingDeleteSearchId = nil
            editingSearch = nil
        }
        .onChange(of: monitorStore.monitors.map(\.id)) { _, _ in ensureValidSelection() }
        .onChange(of: searchService.savedSearches.map(\.id)) { _, _ in ensureValidSelection() }
    }

    private var detailContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if workspaceNavigationState.selectedMode == .monitors {
                    monitorsDetail
                } else {
                    searchesDetail
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private var monitorsDetail: some View {
        if isCreatingNew || editingMonitor != nil {
            WorkspaceMonitorFormCard(
                existingMonitor: editingMonitor,
                onCancel: {
                    isCreatingNew = false
                    editingMonitor = nil
                },
                onSaved: { saved, notice in
                    isCreatingNew = false
                    editingMonitor = nil
                    selectedMonitorId = saved.id
                    showStatus(notice)
                }
            )
        }

        if let monitor = currentMonitor {
            WorkspaceMonitorDetailView(
                monitor: monitor,
                selectedMonitorId: $selectedMonitorId,
                confirmingDeleteId: $confirmingDeleteMonitorId,
                onEdit: {
                    isCreatingNew = false
                    confirmingDeleteMonitorId = nil
                    editingMonitor = monitor
                },
                onStatus: showStatus
            )
        } else if !isCreatingNew {
            PolishedEmptyStateView(
                title: "workspace.monitor.empty.title".localized,
                message: "workspace.monitor.empty.subtitle".localized,
                systemImage: "waveform.path.ecg"
            ) {
                Button("workspace.monitor.add".localized) {
                    isCreatingNew = true
                }
                .liquidGlassButtonStyle(prominent: true)
            }
            .frame(minHeight: 340)
        }
    }

    @ViewBuilder private var searchesDetail: some View {
        if isCreatingNew || editingSearch != nil {
            WorkspaceSearchFormCard(
                existingSearch: editingSearch,
                onCancel: {
                    isCreatingNew = false
                    editingSearch = nil
                },
                onSaved: { saved, notice in
                    isCreatingNew = false
                    editingSearch = nil
                    selectedSearchId = saved.id
                    showStatus(notice)
                }
            )
        }

        if let search = currentSearch {
            WorkspaceSearchDetailView(
                search: search,
                selectedSearchId: $selectedSearchId,
                confirmingDeleteId: $confirmingDeleteSearchId,
                onEdit: {
                    isCreatingNew = false
                    confirmingDeleteSearchId = nil
                    editingSearch = search
                }
            )
        } else if !isCreatingNew {
            PolishedEmptyStateView(
                title: "workspace.search.empty.title".localized,
                message: "workspace.search.empty.subtitle".localized,
                systemImage: "magnifyingglass"
            ) {
                Button("workspace.search.add".localized) {
                    isCreatingNew = true
                }
                .liquidGlassButtonStyle(prominent: true)
            }
            .frame(minHeight: 340)
        }
    }

    private func applyPendingNavigation() {
        guard let navigation = workspaceNavigationState.consumePendingNavigation() else { return }
        workspaceNavigationState.selectedMode = navigation.mode
        resetTransientUI()
        isCreatingNew = navigation.createNew
        ensureValidSelection()
    }

    private func ensureValidSelection() {
        if let id = selectedMonitorId, !monitorStore.monitors.contains(where: { $0.id == id }) {
            selectedMonitorId = nil
        }
        if selectedMonitorId == nil {
            selectedMonitorId = monitorStore.monitors.first?.id
        }
        if let id = selectedSearchId, !searchService.savedSearches.contains(where: { $0.id == id }) {
            selectedSearchId = nil
        }
        if selectedSearchId == nil {
            selectedSearchId = searchService.savedSearches.first?.id
        }
    }

    private func resetTransientUI() {
        isCreatingNew = false
        editingMonitor = nil
        editingSearch = nil
        confirmingDeleteMonitorId = nil
        confirmingDeleteSearchId = nil
    }

    private func toggleCreateNew() {
        editingMonitor = nil
        editingSearch = nil
        confirmingDeleteMonitorId = nil
        confirmingDeleteSearchId = nil
        isCreatingNew.toggle()
    }

    private func showStatus(_ message: String) {
        statusMessage = message
        statusTask?.cancel()
        statusTask = Task {
            try? await Task.sleep(for: .seconds(2.8))
            guard !Task.isCancelled else { return }
            statusMessage = nil
        }
    }
}
