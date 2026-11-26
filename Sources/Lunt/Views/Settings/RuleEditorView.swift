import LuntCore
import SwiftUI

struct RuleEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let ruleStorage: RuleStorage
    let editingRule: NotificationRule?
    let onSave: () -> Void

    @State private var name = ""
    @State private var isEnabled = true
    @State private var conditions: [RuleCondition] = []
    @State private var logicOperator: RuleLogicOperator = .and
    @State private var actions: Set<RuleActionType> = []

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("rules.editor.name".localized, text: $name)
                    Toggle("rules.editor.enabled".localized, isOn: $isEnabled)
                }

                Section("rules.editor.conditions".localized) {
                    ForEach($conditions) { $condition in
                        ConditionRow(condition: $condition)
                    }
                    .onDelete { offsets in
                        conditions.remove(atOffsets: offsets)
                    }

                    Button {
                        conditions.append(RuleCondition(
                            field: .reason,
                            operator: .equals,
                            value: ""
                        ))
                    } label: {
                        Label("rules.editor.add_condition".localized, systemImage: "plus")
                    }

                    if conditions.count > 1 {
                        Picker("rules.editor.logic".localized, selection: $logicOperator) {
                            Text("AND").tag(RuleLogicOperator.and)
                            Text("OR").tag(RuleLogicOperator.any)
                        }
                        .pickerStyle(.segmented)
                    }
                }

                Section("rules.editor.actions".localized) {
                    ForEach(RuleActionType.allCases, id: \.self) { actionType in
                        Toggle(isOn: Binding(
                            get: { actions.contains(actionType) },
                            set: { isOn in
                                if isOn {
                                    actions.insert(actionType)
                                } else {
                                    actions.remove(actionType)
                                }
                            }
                        )) {
                            Label(actionType.displayName, systemImage: actionType.icon)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(editingRule == nil ? "rules.editor.new".localized : "rules.editor.edit".localized)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel".localized) {
                        dismiss()
                    }
                    .liquidGlassButtonStyle()
                }

                if #available(macOS 26.0, *) {
                    ToolbarSpacer(.fixed, placement: .confirmationAction)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("common.save".localized) {
                        saveRule()
                    }
                    .disabled(name.isEmpty || conditions.isEmpty || actions.isEmpty)
                    .liquidGlassButtonStyle(prominent: true)
                }
            }
        }
        .frame(width: 560, height: 430)
        .onAppear {
            if let rule = editingRule {
                name = rule.name
                isEnabled = rule.isEnabled
                conditions = rule.conditions
                logicOperator = rule.logicOperator
                actions = Set(rule.actions.map(\.type))
            }
        }
    }

    private func saveRule() {
        let ruleActions = actions.map { RuleAction(type: $0) }

        if let existingRule = editingRule {
            var updatedRule = existingRule
            updatedRule.name = name
            updatedRule.isEnabled = isEnabled
            updatedRule.conditions = conditions
            updatedRule.logicOperator = logicOperator
            updatedRule.actions = ruleActions
            ruleStorage.updateRule(updatedRule)
        } else {
            let newRule = NotificationRule(
                name: name,
                isEnabled: isEnabled,
                priority: ruleStorage.rules.count,
                conditions: conditions,
                logicOperator: logicOperator,
                actions: ruleActions
            )
            ruleStorage.addRule(newRule)
        }

        onSave()
        dismiss()
    }
}

struct ConditionRow: View {
    @Binding var condition: RuleCondition

    var body: some View {
        HStack(spacing: 8) {
            Picker("", selection: $condition.field) {
                ForEach(RuleField.allCases, id: \.self) { field in
                    Text(field.displayName).tag(field)
                }
            }
            .frame(width: 100)

            Picker("", selection: $condition.operator) {
                ForEach(availableOperators, id: \.self) { ruleOperator in
                    Text(ruleOperator.displayName).tag(ruleOperator)
                }
            }
            .frame(width: 120)

            valueField
        }
    }

    private var availableOperators: [RuleOperator] {
        if condition.field.supportsWildcard {
            RuleOperator.allCases
        } else {
            [.equals, .notEquals]
        }
    }

    @ViewBuilder private var valueField: some View {
        switch condition.field {
        case .reason:
            Picker("", selection: $condition.value) {
                Text("—").tag("")
                ForEach(NotificationReason.allCases, id: \.rawValue) { reason in
                    Text(reason.displayName).tag(reason.rawValue)
                }
            }
        case .notificationType:
            Picker("", selection: $condition.value) {
                Text("—").tag("")
                ForEach(NotificationType.allCases, id: \.rawValue) { type in
                    Text(type.displayName).tag(type.rawValue)
                }
            }
        default:
            TextField("rules.editor.value".localized, text: $condition.value)
                .textFieldStyle(.roundedBorder)
        }
    }
}
