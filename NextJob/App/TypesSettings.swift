import MessageUI
import SwiftUI
import UIKit

struct JobTypesView: View {
    @EnvironmentObject private var store: JobStore
    @State private var selectedType: JobType?
    @State private var addingType = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(store.jobTypes) { type in
                        Button {
                            selectedType = type
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(type.name)
                                        .foregroundStyle(.primary)
                                        .fontWeight(.semibold)
                                    Text("Target \(type.targetHours, specifier: "%.1f")h • \(store.settings.currency) \(type.defaultPrice, specifier: "%.2f")")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            store.deleteJobType(store.jobTypes[index])
                        }
                    }
                } header: {
                    Text("Default price and target time")
                } footer: {
                    Text("Selecting a type on a new job automatically fills its default price and target hours. You can still change them for each job.")
                }
            }
            .navigationTitle("Job Types")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        addingType = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(item: $selectedType) { type in
                NavigationStack {
                    JobTypeEditor(type: type)
                }
            }
            .sheet(isPresented: $addingType) {
                NavigationStack {
                    JobTypeEditor(type: nil)
                }
            }
        }
    }
}

struct JobTypeEditor: View {
    @EnvironmentObject private var store: JobStore
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var price: Double
    @State private var hours: Double

    let existingType: JobType?

    init(type: JobType?) {
        existingType = type
        _name = State(initialValue: type?.name ?? "")
        _price = State(initialValue: type?.defaultPrice ?? 0)
        _hours = State(initialValue: type?.targetHours ?? 1)
    }

    var body: some View {
        Form {
            Section("Job Type") {
                TextField("Name", text: $name)
                HStack {
                    Text("Default price")
                    Spacer()
                    Text(store.settings.currency)
                        .foregroundStyle(.secondary)
                    TextField("0", value: $price, format: .number.precision(.fractionLength(0...2)))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 110)
                }
                HStack {
                    Text("Target hours")
                    Spacer()
                    TextField("1", value: $hours, format: .number.precision(.fractionLength(0...1)))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 110)
                }
            }
        }
        .navigationTitle(existingType == nil ? "Add Type" : "Edit Type")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Save") {
                    save()
                }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func save() {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return }
        if var existingType {
            existingType.name = cleanName
            existingType.defaultPrice = max(0, price)
            existingType.targetHours = max(0, hours)
            store.updateJobType(existingType)
        } else {
            store.addJobType(JobType(name: cleanName, defaultPrice: max(0, price), targetHours: max(0, hours)))
        }
        dismiss()
    }
}

struct SettingsView: View {
    @EnvironmentObject private var store: JobStore

    var body: some View {
        NavigationStack {
            Form {
                Section("KB Accountants") {
                    TextField("Company name", text: settingsBinding(\.companyName))
                    TextField("Company email", text: settingsBinding(\.companyEmail))
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                    Text("This email is used for document requests and job-completion emails.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Your Details") {
                    TextField("Your name", text: settingsBinding(\.senderName))
                    TextField("Your email", text: settingsBinding(\.senderEmail))
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                }

                Section("App") {
                    TextField("Currency", text: settingsBinding(\.currency))
                        .textInputAutocapitalization(.characters)
                    Picker("Appearance", selection: settingsBinding(\.theme)) {
                        ForEach(AppTheme.allCases) { theme in
                            Text(theme.title).tag(theme)
                        }
                    }
                }

                Section("Storage") {
                    LabeledContent("Jobs", value: "\(store.jobs.count)")
                    LabeledContent("Job Types", value: "\(store.jobTypes.count)")
                    Text("Job data is saved locally. Attached documents are copied into the Next Job Files folder in the app's Documents storage.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("About") {
                    LabeledContent("App", value: "Next Job")
                    LabeledContent("Version", value: "1.0.0")
                    LabeledContent("Minimum iOS", value: "16.0")
                    LabeledContent("Author", value: "Next Solution – Zeeshan Barvi")
                }
            }
            .navigationTitle("Settings")
        }
    }

    private func settingsBinding<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(
            get: { store.settings[keyPath: keyPath] },
            set: { newValue in
                var copy = store.settings
                copy[keyPath: keyPath] = newValue
                store.updateSettings(copy)
            }
        )
    }
}
