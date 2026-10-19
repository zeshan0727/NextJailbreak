import SwiftUI

struct ERPDimensionSettingsView: View {
    @State private var definitions = ERPAccountingEngine.dimensionDefinitions
    @State private var editing: ERPDimensionDefinition?
    @State private var adding = false

    var body: some View {
        List {
            Section {
                Button {
                    adding = true
                } label: { Label("Add Financial Dimension", systemImage: "plus.circle.fill") }
            } footer: {
                Text("Dimensions are stored on each transaction and can be required by posting rules or used as filters in ERP custom reports. Examples: Cost Center, Department, Project, Employee, Location, Business Unit.")
            }

            Section("Dimensions") {
                if definitions.isEmpty {
                    Text("No financial dimensions configured.")
                        .foregroundStyle(.secondary)
                }
                ForEach(definitions) { definition in
                    Button {
                        editing = definition
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(definition.name).font(.headline).foregroundStyle(.primary)
                                Text(definition.values.isEmpty ? "Free text" : "\(definition.values.count) allowed values")
                                    .font(.caption).foregroundStyle(.secondary)
                                let required = [
                                    definition.requiredForIncome ? "Income" : nil,
                                    definition.requiredForExpense ? "Expense" : nil,
                                    definition.requiredForTransfer ? "Transfer" : nil
                                ].compactMap { $0 }.joined(separator: ", ")
                                if !required.isEmpty {
                                    Text("Required: \(required)").font(.caption2).foregroundStyle(AppTheme.orange)
                                }
                            }
                            Spacer()
                            Image(systemName: definition.enabled ? "checkmark.circle.fill" : "pause.circle")
                                .foregroundStyle(definition.enabled ? AppTheme.green : .secondary)
                        }
                    }
                }
                .onDelete(perform: delete)
                .onMove(perform: move)
            }
        }
        .navigationTitle("Financial Dimensions")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
        .sheet(isPresented: $adding) {
            NavigationStack {
                ERPDimensionDefinitionEditor(definition: ERPDimensionDefinition()) { value in
                    definitions.append(value)
                    save()
                    adding = false
                }
            }
        }
        .sheet(item: $editing) { definition in
            NavigationStack {
                ERPDimensionDefinitionEditor(definition: definition) { value in
                    if let index = definitions.firstIndex(where: { $0.id == value.id }) { definitions[index] = value }
                    save()
                    editing = nil
                }
            }
        }
        .onAppear { definitions = ERPAccountingEngine.dimensionDefinitions }
        .onDisappear(perform: save)
    }

    private func delete(at offsets: IndexSet) {
        definitions.remove(atOffsets: offsets)
        save()
    }

    private func move(from offsets: IndexSet, to destination: Int) {
        definitions.move(fromOffsets: offsets, toOffset: destination)
        save()
    }

    private func save() { ERPAccountingEngine.dimensionDefinitions = definitions }
}

private struct ERPDimensionDefinitionEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var definition: ERPDimensionDefinition
    @State private var newValue = ""
    let onSave: (ERPDimensionDefinition) -> Void

    init(definition: ERPDimensionDefinition, onSave: @escaping (ERPDimensionDefinition) -> Void) {
        _definition = State(initialValue: definition)
        self.onSave = onSave
    }

    var body: some View {
        Form {
            Section("Dimension") {
                TextField("Name", text: $definition.name)
                Toggle("Enabled", isOn: $definition.enabled)
            }
            Section("Required On") {
                Toggle("Income", isOn: $definition.requiredForIncome)
                Toggle("Expense", isOn: $definition.requiredForExpense)
                Toggle("Transfer", isOn: $definition.requiredForTransfer)
            }
            Section("Allowed Values") {
                HStack {
                    TextField("Add value", text: $newValue)
                    Button("Add") { addValue() }
                        .disabled(newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if definition.values.isEmpty {
                    Text("Leave empty to allow free-text values on transactions.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach(definition.values, id: \.self) { value in Text(value) }
                    .onDelete { definition.values.remove(atOffsets: $0) }
            }
        }
        .navigationTitle("Dimension")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    definition.name = definition.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    onSave(definition)
                    dismiss()
                }
                .disabled(definition.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func addValue() {
        let value = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !definition.values.contains(where: { $0.caseInsensitiveCompare(value) == .orderedSame }) else { return }
        definition.values.append(value)
        definition.values.sort { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        newValue = ""
    }
}

struct ERPTransactionDimensionsEditor: View {
    @Binding var values: [String: String]
    let type: TransactionType

    private var definitions: [ERPDimensionDefinition] {
        ERPAccountingEngine.dimensionDefinitions.filter(\.enabled)
    }

    var body: some View {
        if !definitions.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Financial Dimensions")
                    .font(.headline)
                ForEach(definitions) { definition in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 4) {
                            Text(definition.name).font(.subheadline.weight(.semibold))
                            if definition.required(for: type) {
                                Text("Required").font(.caption2.bold()).foregroundStyle(AppTheme.orange)
                            }
                        }
                        if definition.values.isEmpty {
                            TextField("Enter \(definition.name)", text: binding(for: definition.name))
                                .textInputAutocapitalization(.words)
                                .padding(11)
                                .background(.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        } else {
                            Picker(definition.name, selection: binding(for: definition.name)) {
                                Text("Not set").tag("")
                                ForEach(definition.values, id: \.self) { Text($0).tag($0) }
                            }
                            .pickerStyle(.menu)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                }
            }
            .padding(14)
            .background(AppTheme.purple.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func binding(for name: String) -> Binding<String> {
        Binding(
            get: { values[name] ?? "" },
            set: { value in values[name] = value }
        )
    }
}
