import SwiftUI

struct AddPasswordView: View {
    @EnvironmentObject private var vault: VaultStore
    @Environment(\.dismiss) private var dismiss
    @State private var site = ""
    @State private var username = ""
    @State private var link = ""
    @State private var notes = ""
    @State private var password = "MpMr@"
    @State private var showingAlphabet = false

    private var breakdown: PasswordBreakdown {
        PasswordGenerator.breakdown(site: site)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Website") {
                    TextField("Site or app name", text: $site)
                        .onChange(of: site) { newValue in
                            password = PasswordGenerator.websiteBased(site: newValue)
                        }
                    Text("Type only the main website name, such as Google or Facebook.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("Username or email", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("https://example.com", text: $link)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                }

                Section("Password Helper") {
                    helperRow("Fixed prefix", value: "MpMr@")
                    helperRow("Website letters", value: breakdown.cleanedSite.isEmpty ? "—" : breakdown.cleanedSite)
                    helperRow("Letter count", value: breakdown.letterCount == 0 ? "—" : "\(breakdown.letterCount)")
                    helperRow(
                        "First letter",
                        value: breakdown.firstLetter.map { "\($0) = \(String(format: "%02d", breakdown.firstPosition))" } ?? "—"
                    )
                    helperRow(
                        "Last letter",
                        value: breakdown.lastLetter.map { "\($0) = \(String(format: "%02d", breakdown.lastPosition))" } ?? "—"
                    )

                    Button("Open A–Z Position Helper") {
                        showingAlphabet = true
                    }
                }

                Section("Generated Password") {
                    Text(password)
                        .font(.system(.title3, design: .monospaced).bold())
                        .textSelection(.enabled)
                    Text("Rule: MpMr@ + letter count + first letter position + last letter position")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if breakdown.letterCount > 0 {
                        Text("Example breakdown: MpMr@ + \(breakdown.letterCount) + \(String(format: "%02d", breakdown.firstPosition)) + \(String(format: "%02d", breakdown.lastPosition))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Section("Notes") {
                    TextField("Optional", text: $notes, axis: .vertical)
                }
            }
            .navigationTitle("New Password")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        vault.add(.init(site: site, username: username, password: password, link: link, notes: notes))
                        dismiss()
                    }
                    .disabled(breakdown.letterCount == 0)
                }
            }
            .sheet(isPresented: $showingAlphabet) {
                AlphabetHelperView()
            }
        }
    }

    @ViewBuilder
    private func helperRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
                .font(.system(.body, design: .monospaced))
        }
    }
}

struct AlphabetHelperView: View {
    @Environment(\.dismiss) private var dismiss
    private let columns = [GridItem(.adaptive(minimum: 72), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(0..<26, id: \.self) { index in
                        let letter = String(UnicodeScalar(65 + index)!)
                        VStack(spacing: 4) {
                            Text(letter)
                                .font(.title2.bold())
                            Text(String(format: "%02d", index + 1))
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding()
            }
            .navigationTitle("A–Z Positions")
            .toolbar {
                Button("Done") { dismiss() }
            }
        }
    }
}
