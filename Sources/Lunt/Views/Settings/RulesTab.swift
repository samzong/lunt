import LuntCore
import SwiftUI

struct RulesTab: View {
    let settingsWidth: CGFloat

    @Environment(RuleStorage.self) private var ruleStorage
    @Environment(NotificationService.self) private var notificationService
    @State private var showingEditor = false
    @State private var editingRule: NotificationRule?
    @State private var isRunningRules = false
    @State private var runStatusMessage: String?

    var body: some View {
        Form {
            Section {
                if ruleStorage.rules.isEmpty {
                    emptyStateView
                } else {
                    ForEach(ruleStorage.rules) { rule in
                        RuleRowView(
                            rule: rule,
                            onToggle: { ruleStorage.toggleRule(rule) },
                            onEdit: {
                                editingRule = rule
                                showingEditor = true
                            },
                            onDelete: { ruleStorage.deleteRule(rule) }
                        )
                    }
                    .onMove { source, destination in
                        ruleStorage.moveRule(from: source, to: destination)
                    }
                }
            } header: {
                HStack {
                    Text("rules.title".localized)

                    Spacer()

                    Button {
                        Task { await runActiveRules() }
                    } label: {
                        if isRunningRules {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("rules.run_active".localized)
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(
                        !notificationService.isAuthenticated ||
                            !ruleStorage.rules.contains(where: \.isEnabled) ||
                            isRunningRules
                    )

                    Menu {
                        Button("rules.import".localized) {
                            importRules()
                        }
                        Button("rules.export".localized) {
                            exportRules()
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.button)
                    .controlSize(.small)
                    .fixedSize()

                    Button {
                        editingRule = nil
                        showingEditor = true
                    } label: {
                        Label("rules.add".localized, systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            } footer: {
                if let runStatusMessage {
                    Text(runStatusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: settingsWidth)
        .sheet(isPresented: $showingEditor) {
            RuleEditorView(
                ruleStorage: ruleStorage,
                editingRule: editingRule,
                onSave: { showingEditor = false }
            )
        }
    }

    @MainActor
    private func runActiveRules() async {
        guard !isRunningRules else { return }
        isRunningRules = true
        defer { isRunningRules = false }

        let summary = await notificationService.applyActiveRules()
        if summary.failedCount > 0 {
            runStatusMessage = String(
                format: "rules.run_result.failed".localized,
                summary.markedAsReadCount,
                summary.failedCount
            )
        } else if summary.markedAsReadCount > 0 {
            runStatusMessage = String(
                format: "rules.run_result.marked".localized,
                summary.markedAsReadCount
            )
        } else {
            runStatusMessage = "rules.run_result.none".localized
        }
    }

    private func importRules() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        panel.begin { response in
            if response == .OK, let url = panel.url {
                do {
                    let data = try Data(contentsOf: url)
                    let rules = try JSONDecoder().decode([NotificationRule].self, from: data)
                    for rule in rules {
                        if ruleStorage.rules.contains(where: { $0.id == rule.id }) {
                            ruleStorage.updateRule(rule)
                        } else {
                            ruleStorage.addRule(rule)
                        }
                    }
                } catch {
                    runStatusMessage = String(format: "rules.import_failed".localized, error.localizedDescription)
                }
            }
        }
    }

    private func exportRules() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "lunt_rules.json"

        panel.begin { response in
            if response == .OK, let url = panel.url {
                do {
                    let data = try JSONEncoder().encode(ruleStorage.rules)
                    try data.write(to: url)
                } catch {
                    runStatusMessage = String(format: "rules.export_failed".localized, error.localizedDescription)
                }
            }
        }
    }

    private var emptyStateView: some View {
        PolishedEmptyStateView(
            title: "rules.empty.title".localized,
            message: "rules.empty.subtitle".localized,
            systemImage: "slider.horizontal.3",
            accent: .secondary
        )
        .frame(maxWidth: .infinity)
        .frame(height: 180)
    }
}
