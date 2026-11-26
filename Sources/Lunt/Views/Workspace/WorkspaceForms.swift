import AppKit
import LuntCore
import SwiftUI

struct WorkspaceMonitorFormCard: View {
    let existingMonitor: MonitorDefinition?
    let onCancel: () -> Void
    let onSaved: (MonitorDefinition, String) -> Void

    @Environment(GitHubSession.self) private var session
    @Environment(MonitorStore.self) private var store
    @Environment(MonitorEngine.self) private var engine

    @State private var targetKind: TargetKind = .repository
    @State private var targetInput = ""
    @State private var displayName = ""
    @State private var errorMessage: String?
    @State private var isSaving = false

    private enum TargetKind: String, CaseIterable, Identifiable {
        case account, repository

        var id: String {
            rawValue
        }
    }

    var body: some View {
        WorkspaceFormShell(
            title: (existingMonitor == nil ? "workspace.monitor.add" : "workspace.monitor.edit").localized,
            note: "workspace.monitor.form.note".localized,
            saveTitle: "workspace.monitor.save".localized,
            isBusy: isSaving,
            errorMessage: errorMessage,
            onCancel: onCancel,
            onSave: { Task { await save() } }
        ) {
            Picker("", selection: $targetKind) {
                Text("workspace.monitor.type.account".localized).tag(TargetKind.account)
                Text("workspace.monitor.type.repository".localized).tag(TargetKind.repository)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 220)
        } content: {
            HStack(spacing: 10) {
                WorkspaceLabeledField("workspace.monitor.target.label") {
                    TextField(
                        (targetKind == .account
                            ? "workspace.monitor.target_placeholder.account"
                            : "workspace.monitor.target_placeholder.repository").localized,
                        text: $targetInput
                    )
                    .textFieldStyle(.roundedBorder)
                }
                WorkspaceLabeledField("workspace.monitor.name.label") {
                    TextField("workspace.monitor.name_placeholder".localized, text: $displayName)
                        .textFieldStyle(.roundedBorder)
                }
                .frame(maxWidth: 220)
            }

            if let existingMonitor,
               let parsed = MonitorTarget.parse(input: targetInput, type: targetKind.rawValue),
               parsed.idString != existingMonitor.target.idString {
                Label("workspace.monitor.target_change_note".localized, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear(perform: loadExisting)
        .onChange(of: existingMonitor?.id) { _, _ in loadExisting() }
    }

    private func loadExisting() {
        errorMessage = nil
        guard let monitor = existingMonitor else {
            targetKind = .repository
            targetInput = ""
            displayName = ""
            return
        }
        switch monitor.target {
        case let .account(login):
            targetKind = .account
            targetInput = login
        case let .repository(owner, name):
            targetKind = .repository
            targetInput = "\(owner)/\(name)"
        }
        displayName = monitor.name ?? ""
    }

    @MainActor
    private func save() async {
        errorMessage = nil
        guard let target = MonitorTarget.parse(input: targetInput, type: targetKind.rawValue) else {
            errorMessage = "workspace.monitor.error.invalid_target".localized
            return
        }
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmed.isEmpty ? nil : trimmed

        isSaving = true
        defer { isSaving = false }

        if let existing = existingMonitor {
            let changed = existing.target.idString != target.idString
            if changed, let err = await validateRemote(target) {
                errorMessage = err
                return
            }
            guard store.updateMonitorDetails(id: existing.id, target: target, name: name) else {
                errorMessage = "workspace.monitor.error.duplicate".localized
                return
            }
            let updated = store.monitors.first { $0.id == existing.id } ?? existing
            if changed {
                await engine.sync(monitor: updated)
            }
            onSaved(updated, "workspace.monitor.saved_status".localized)
            return
        }

        if let err = await validateRemote(target) {
            errorMessage = err
            return
        }
        let def = MonitorDefinition(
            target: target,
            name: name,
            isEnabled: true,
            eventToggles: ["commit": true, "pr": true, "issue": true, "release": true, "comment": true]
        )
        guard store.addMonitor(def) else {
            errorMessage = "workspace.monitor.error.duplicate".localized
            return
        }
        await engine.sync(monitor: def)
        onSaved(def, "workspace.monitor.saved_status".localized)
    }

    @MainActor
    private func validateRemote(_ target: MonitorTarget) async -> String? {
        guard let rest = session.restClient else {
            return "workspace.monitor.error.not_authenticated".localized
        }
        switch target {
        case let .account(login):
            return await rest.userExists(username: login)
                ? nil : String(format: "workspace.monitor.error.account_not_found".localized, login)
        case let .repository(owner, name):
            return await rest.repositoryExists(owner: owner, repo: name)
                ? nil : String(format: "workspace.monitor.error.repo_not_found".localized, "\(owner)/\(name)")
        }
    }
}

struct WorkspaceSearchFormCard: View {
    let existingSearch: SavedSearch?
    let onCancel: () -> Void
    let onSaved: (SavedSearch, String) -> Void

    @Environment(SearchService.self) private var searchService

    @State private var name = ""
    @State private var query = ""
    @State private var searchType: SearchType = .all
    @State private var isPinned = true
    @State private var watchAlerts = false
    @State private var previewItems: [SearchResultItem] = []
    @State private var hasRunPreview = false
    @State private var isLoadingPreview = false
    @State private var errorMessage: String?

    var body: some View {
        WorkspaceFormShell(
            title: (existingSearch == nil ? "workspace.search.add" : "workspace.search.edit").localized,
            note: "workspace.search.form.note".localized,
            saveTitle: "workspace.search.save".localized,
            isBusy: false,
            errorMessage: errorMessage,
            onCancel: onCancel,
            onSave: save
        ) {
            Picker("", selection: $searchType) {
                Text("workspace.search.type.all".localized).tag(SearchType.all)
                Text("workspace.search.type.issue".localized).tag(SearchType.issue)
                Text("workspace.search.type.pr".localized).tag(SearchType.pr)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 260)
        } content: {
            WorkspaceLabeledField("workspace.search.name.label") {
                TextField("workspace.search.name_placeholder".localized, text: $name)
                    .textFieldStyle(.roundedBorder)
            }
            WorkspaceLabeledField("workspace.search.query.label") {
                TextField("workspace.search.query_placeholder".localized, text: $query, axis: .vertical)
                    .font(.system(.body, design: .monospaced))
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2 ... 4)
            }
            HStack(spacing: 16) {
                Toggle("workspace.search.pin_to_work".localized, isOn: $isPinned).toggleStyle(.checkbox)
                Toggle("workspace.search.watch_alerts".localized, isOn: $watchAlerts).toggleStyle(.checkbox)
                Spacer()
                if isLoadingPreview {
                    ProgressView().controlSize(.small)
                }
                Button("workspace.search.preview".localized) { Task { await runPreview() } }
                    .liquidGlassButtonStyle()
                    .disabled(isLoadingPreview)
            }
            if hasRunPreview {
                previewSection
            }
        }
        .onAppear(perform: loadExisting)
        .onChange(of: existingSearch?.id) { _, _ in loadExisting() }
    }

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(format: "workspace.search.preview_results".localized, previewItems.count))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if previewItems.isEmpty {
                Text("workspace.search.no_matches".localized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(previewItems.prefix(6)) { item in
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
                .frame(maxHeight: 180)
            }
        }
    }

    private func loadExisting() {
        errorMessage = nil
        previewItems = []
        hasRunPreview = false
        guard let search = existingSearch else {
            name = ""
            query = ""
            searchType = .all
            isPinned = true
            watchAlerts = false
            return
        }
        name = search.name
        query = search.query
        searchType = search.type
        isPinned = search.isPinned
        watchAlerts = search.watchAlerts
    }

    @MainActor
    private func runPreview() async {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            errorMessage = "workspace.search.empty_query_error".localized
            return
        }
        errorMessage = nil
        isLoadingPreview = true
        previewItems = await searchService.fetchPreview(query: trimmedQuery, type: searchType)
        hasRunPreview = true
        isLoadingPreview = false
    }

    private func save() {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            errorMessage = "workspace.search.empty_query_error".localized
            return
        }
        errorMessage = nil
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = trimmed.isEmpty ? trimmedQuery : trimmed

        if let search = existingSearch {
            searchService.updateSearch(
                id: search.id,
                options: .init(name: resolvedName, query: trimmedQuery, isPinned: isPinned, type: searchType, watchAlerts: watchAlerts)
            )
            let updated = searchService.savedSearches.first { $0.id == search.id } ?? search
            Task { await searchService.syncSearch(id: updated.id) }
            onSaved(updated, "workspace.search.saved_status".localized)
            return
        }

        searchService.addSearch(name: resolvedName, query: trimmedQuery, type: searchType, isPinned: isPinned, watchAlerts: watchAlerts)
        if let created = searchService.savedSearches.last {
            Task { await searchService.syncSearch(id: created.id) }
            onSaved(created, "workspace.search.saved_status".localized)
        }
    }
}

private struct WorkspaceFormShell<HeaderPicker: View, Content: View>: View {
    let title: String
    let note: String
    let saveTitle: String
    let isBusy: Bool
    let errorMessage: String?
    let onCancel: () -> Void
    let onSave: () -> Void
    @ViewBuilder let headerPicker: HeaderPicker
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                headerPicker
            }
            content
            if let errorMessage {
                InlineErrorBanner(message: errorMessage)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            HStack(spacing: 8) {
                Text(note).font(.caption).foregroundStyle(.secondary)
                Spacer()
                if isBusy {
                    ProgressView().controlSize(.small)
                }
                Button("common.cancel".localized, action: onCancel).liquidGlassButtonStyle()
                Button(saveTitle, action: onSave).liquidGlassButtonStyle(prominent: true).disabled(isBusy)
            }
        }
        .padding(14)
        .liquidGlassSurface(cornerRadius: 14)
    }
}

private struct WorkspaceLabeledField<Content: View>: View {
    let titleKey: String
    @ViewBuilder let content: Content

    init(_ titleKey: String, @ViewBuilder content: () -> Content) {
        self.titleKey = titleKey
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(titleKey.localized).font(.caption).foregroundStyle(.secondary)
            content
        }
    }
}
