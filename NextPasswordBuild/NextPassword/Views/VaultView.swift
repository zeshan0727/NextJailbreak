import SwiftUI
import UIKit

struct VaultView: View {
    @EnvironmentObject private var vault: VaultStore
    @State private var showingAdd = false
    @State private var search = ""

    private var filtered: [PasswordEntry] {
        search.isEmpty ? vault.entries : vault.entries.filter {
            $0.site.localizedCaseInsensitiveContains(search) ||
            $0.username.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if filtered.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "key.fill")
                            .font(.system(size: 42))
                            .foregroundColor(.secondary)
                        Text("No Passwords").font(.headline)
                        Text("Generate and save your first password.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                }

                ForEach(filtered) { entry in
                    NavigationLink {
                        EntryDetailView(entry: entry)
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(entry.site).font(.headline)
                            Text(entry.username.isEmpty ? entry.link : entry.username)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .onDelete { offsets in
                    let ids = offsets.map { filtered[$0].id }
                    vault.delete(ids: ids)
                }
            }
            .navigationTitle("Password Vault")
            .searchable(text: $search)
            .toolbar {
                Button { showingAdd = true } label: {
                    Image(systemName: "plus")
                }
            }
            .sheet(isPresented: $showingAdd) {
                AddPasswordView()
            }
        }
    }
}

struct EntryDetailView: View {
    let entry: PasswordEntry
    @State private var reveal = false

    var body: some View {
        Form {
            LabeledContent("Site", value: entry.site)
            LabeledContent("Username", value: entry.username)
            Section("Password") {
                Text(reveal ? entry.password : String(repeating: "•", count: max(8, entry.password.count)))
                    .font(.system(.body, design: .monospaced))
                Button(reveal ? "Hide" : "Reveal") { reveal.toggle() }
                Button("Copy Password") {
                    UIPasteboard.general.string = entry.password
                    DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
                        if UIPasteboard.general.string == entry.password {
                            UIPasteboard.general.string = ""
                        }
                    }
                }
            }
            if let url = URL(string: entry.link), !entry.link.isEmpty {
                Link("Open Website", destination: url)
            }
            if !entry.notes.isEmpty {
                Section("Notes") { Text(entry.notes) }
            }
        }
        .navigationTitle(entry.site)
    }
}
