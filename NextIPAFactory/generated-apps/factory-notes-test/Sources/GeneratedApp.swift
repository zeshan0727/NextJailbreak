import Foundation
import SwiftUI

struct Note: Identifiable, Codable {
    var id: UUID
    var title: String
    var body: String
    var createdAt: Date
    var updatedAt: Date

    var displayTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled Note" : title
    }
}

final class NotesStore: ObservableObject {
    @Published private(set) var notes: [Note] = []
    @Published var errorMessage: String?

    private let fileURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("notes.json")

    init() {
        load()
    }

    func add(title: String, body: String) {
        let now = Date()
        notes.insert(Note(id: UUID(), title: title, body: body, createdAt: now, updatedAt: now), at: 0)
        save()
    }

    func update(id: UUID, title: String, body: String) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[index].title = title
        notes[index].body = body
        notes[index].updatedAt = Date()
        notes.sort { $0.updatedAt > $1.updatedAt }
        save()
    }

    func delete(id: UUID) {
        notes.removeAll { $0.id == id }
        save()
    }

    private func load() {
        do {
            guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
            let data = try Data(contentsOf: fileURL)
            notes = try JSONDecoder().decode([Note].self, from: data)
            notes.sort { $0.updatedAt > $1.updatedAt }
        } catch {
            errorMessage = "Your notes could not be loaded: \(error.localizedDescription)"
        }
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(notes)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            errorMessage = "Your changes could not be saved: \(error.localizedDescription)"
        }
    }
}

private enum EditorTarget: Identifiable {
    case new
    case existing(Note)

    var id: String {
        switch self {
        case .new: return "new"
        case .existing(let note): return note.id.uuidString
        }
    }

    var note: Note? {
        if case .existing(let note) = self { return note }
        return nil
    }
}

@main
struct GeneratedAppApp: App {
    var body: some Scene {
        WindowGroup {
            NotesHomeView()
        }
    }
}

private struct NotesHomeView: View {
    @StateObject private var store = NotesStore()
    @State private var searchText = ""
    @State private var editorTarget: EditorTarget?
    @AppStorage("appearanceMode") private var appearanceMode = "system"

    private var colorScheme: ColorScheme? {
        switch appearanceMode {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    private var filteredNotes: [Note] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return store.notes }
        return store.notes.filter {
            $0.title.localizedStandardContains(query) || $0.body.localizedStandardContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(filteredNotes) { note in
                        Button {
                            editorTarget = .existing(note)
                        } label: {
                            NoteCardView(note: note)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 7, leading: 16, bottom: 7, trailing: 16))
                        .swipeActions {
                            Button(role: .destructive) {
                                store.delete(id: note.id)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                store.delete(id: note.id)
                            } label: {
                                Label("Delete Note", systemImage: "trash")
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text(searchText.isEmpty ? "YOUR NOTES" : "SEARCH RESULTS")
                        Spacer()
                        Text("\(filteredNotes.count)")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color(uiColor: .systemGroupedBackground))
            .overlay {
                if filteredNotes.isEmpty {
                    VStack(spacing: 14) {
                        Image(systemName: searchText.isEmpty ? "note.text" : "magnifyingglass")
                            .font(.system(size: 44, weight: .light))
                            .foregroundStyle(.indigo)
                        Text(searchText.isEmpty ? "A fresh page" : "No matching notes")
                            .font(.title3.weight(.semibold))
                        Text(searchText.isEmpty ? "Capture an idea, a list, or a moment." : "Try a different search term.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        if searchText.isEmpty {
                            Button("Create a Note") { editorTarget = .new }
                                .buttonStyle(.borderedProminent)
                                .padding(.top, 6)
                        }
                    }
                    .padding(32)
                }
            }
            .navigationTitle("Notes")
            .searchable(text: $searchText, prompt: "Search notes")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Menu {
                        Picker("Appearance", selection: $appearanceMode) {
                            Label("System", systemImage: "circle.lefthalf.filled").tag("system")
                            Label("Light", systemImage: "sun.max").tag("light")
                            Label("Dark", systemImage: "moon").tag("dark")
                        }
                    } label: {
                        Label("Appearance", systemImage: "circle.lefthalf.filled")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        editorTarget = .new
                    } label: {
                        Label("New Note", systemImage: "square.and.pencil")
                    }
                }
            }
            .sheet(item: $editorTarget) { target in
                NoteEditorView(note: target.note) { title, body in
                    if let note = target.note {
                        store.update(id: note.id, title: title, body: body)
                    } else {
                        store.add(title: title, body: body)
                    }
                }
            }
            .alert("Storage Error", isPresented: Binding(
                get: { store.errorMessage != nil },
                set: { if !$0 { store.errorMessage = nil } }
            )) {
                Button("OK") { store.errorMessage = nil }
            } message: {
                Text(store.errorMessage ?? "An unknown error occurred.")
            }
        }
        .tint(.indigo)
        .preferredColorScheme(colorScheme)
    }
}

private struct NoteCardView: View {
    let note: Note

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 8) {
                Text(note.displayTitle)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            Text(note.body.isEmpty ? "No additional text" : note.body.replacingOccurrences(of: "\n", with: " "))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Label(note.updatedAt.formatted(date: .abbreviated, time: .shortened), systemImage: "clock")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
    }
}

private struct NoteEditorView: View {
    let note: Note?
    let onSave: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var content: String

    init(note: Note?, onSave: @escaping (String, String) -> Void) {
        self.note = note
        self.onSave = onSave
        _title = State(initialValue: note?.title ?? "")
        _content = State(initialValue: note?.body ?? "")
    }

    private var isEmpty: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                TextField("Title", text: $title)
                    .font(.title2.weight(.bold))
                    .textInputAutocapitalization(.sentences)
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 18)
                Divider().padding(.horizontal, 20)
                TextEditor(text: $content)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                if let note = note {
                    Text("Created \(note.createdAt.formatted(date: .abbreviated, time: .shortened))  ·  Edited \(note.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 14)
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(note == nil ? "New Note" : "Edit Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        onSave(title.trimmingCharacters(in: .whitespacesAndNewlines), content)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(isEmpty)
                }
            }
        }
        .tint(.indigo)
    }
}
