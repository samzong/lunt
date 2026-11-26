import LuntCore
import SwiftUI

struct RulesTab: View {
    let settingsWidth: CGFloat

    @Environment(RuleStorage.self) private var ruleStorage
    @State private var showingEditor = false
    @State private var editingRule: NotificationRule?

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
                    // Simple merge: append rules that have different IDs
                    // Or for user experience, maybe just add all as "Copies"?
                    // Let's rely on ID check.
                    for rule in rules {
                        // If ID exists, update. If not, append.
                        if ruleStorage.rules.contains(where: { $0.id == rule.id }) {
                            ruleStorage.updateRule(rule)
                        } else {
                            ruleStorage.addRule(rule)
                        }
                    }
                } catch {
                    print("Failed to import rules: \(error)")
                    // Ideally show an alert here
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
                    print("Failed to export rules: \(error)")
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
