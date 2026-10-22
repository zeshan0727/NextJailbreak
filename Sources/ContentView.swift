import SwiftUI
import Combine

struct Note: Identifiable, Codable, Equatable {
    let id: UUID
    var content: String
    let createdAt: Date
    var modifiedAt: Date
    var isPinned: Bool

    var title: String {
        content.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true).first.map { String($0) } ?? "New Note"
    }

    var snippet: String {
        let lines = content.split(separator: "\n", omittingEmptySubsequences: true)
        if lines.count > 1 {
            let secondLine = lines[1]
            return secondLine.count > 30 ? String(secondLine.prefix(30)) + "..." : String(secondLine)
        } else if content.count > 30 {
            return String(content.prefix(30)) + "..."
        } else {
            return content
        }
    }
}

@MainActor
final class NotesViewModel: ObservableObject {
    @Published private(set) var notes: [Note] = []
    @Published var searchText: String = ""
    @Published var errorMessage: String? = nil
    @Published var showErrorAlert: Bool = false
    @Published var isLoading: Bool = false

    private let fileURL: URL
    private var saveCancellable: AnyCancellable?
    private var debounceSaveSubject = PassthroughSubject<Void, Never>()

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.fileURL = docs.appendingPathComponent("notes.json")
        loadNotes()
        setupAutoSave()
    }

    private func setupAutoSave() {
        saveCancellable = debounceSaveSubject
            .debounce(for: .seconds(1), scheduler: DispatchQueue.main)
            .sink { [weak self] in
                self?.saveNotes()
            }
    }

    func loadNotes() {
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            do {
                let data = try Data(contentsOf: self.fileURL)
                let decoded = try JSONDecoder().decode([Note].self, from: data)
                DispatchQueue.main.async {
                    self.notes = decoded
                    self.isLoading = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.notes = []
                    self.isLoading = false
                    if (error as NSError).code != NSFileReadNoSuchFileError {
                        self.errorMessage = "Failed to load notes: \(error.localizedDescription)"
                        self.showErrorAlert = true
                    }
                }
            }
        }
    }

    private func saveNotes() {
        DispatchQueue.global(qos: .background).async { [notes = self.notes, fileURL = self.fileURL, weak self] in
            do {
                let data = try JSONEncoder().encode(notes)
                try data.write(to: fileURL, options: [.atomic])
            } catch {
                DispatchQueue.main.async {
                    self?.errorMessage = "Failed to save notes: \(error.localizedDescription)"
                    self?.showErrorAlert = true
                }
            }
        }
    }

    func addNote() {
        let now = Date()
        let newNote = Note(id: UUID(), content: "", createdAt: now, modifiedAt: now, isPinned: false)
        notes.insert(newNote, at: 0)
        debounceSaveSubject.send()
    }

    func update(note: Note) {
        guard let idx = notes.firstIndex(where: { $0.id == note.id }) else { return }
        var updatedNote = note
        updatedNote.modifiedAt = Date()
        notes[idx] = updatedNote
        sortNotes()
        debounceSaveSubject.send()
    }

    func delete(note: Note) {
        notes.removeAll { $0.id == note.id }
        debounceSaveSubject.send()
    }

    func togglePin(note: Note) {
        guard let idx = notes.firstIndex(where: { $0.id == note.id }) else { return }
        notes[idx].isPinned.toggle()
        notes[idx].modifiedAt = Date()
        sortNotes()
        debounceSaveSubject.send()
    }

    func clearAll() {
        notes.removeAll()
        debounceSaveSubject.send()
    }

    private func sortNotes() {
        notes.sort {
            if $0.isPinned != $1.isPinned {
                return $0.isPinned && !$1.isPinned
            }
            return $0.modifiedAt > $1.modifiedAt
        }
    }

    var filteredNotes: [Note] {
        if searchText.isEmpty {
            return notes
        }
        let lower = searchText.lowercased()
        return notes.filter {
            $0.content.lowercased().contains(lower) || $0.title.lowercased().contains(lower)
        }
    }
}

struct ContentView: View {
    @StateObject private var vm = NotesViewModel()
    @State private var showingDeleteAlert = false
    @State private var noteToDelete: Note? = nil
    @State private var showingClearAllAlert = false
    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            VStack {
                if vm.notes.isEmpty && vm.searchText.isEmpty {
                    EmptyStateView()
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("No notes available. Tap the plus button to add a new note.")
                } else {
                    List {
                        ForEach(vm.filteredNotes) { note in
                            NavigationLink(value: note) {
                                NoteRow(note: note)
                                    .accessibilityElement(children: .combine)
                                    .accessibilityLabel("Note titled \(note.title). Preview: \(note.snippet)")
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                Button {
                                    vm.togglePin(note: note)
                                } label: {
                                    Label(note.isPinned ? "Unpin" : "Pin", systemImage: note.isPinned ? "pin.slash" : "pin")
                                }
                                .tint(note.isPinned ? .gray : .yellow)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    noteToDelete = note
                                    showingDeleteAlert = true
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .searchable(text: $vm.searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search notes")
                    .accessibilityLabel("Notes list")
                }
            }
            .navigationTitle("QuickNotes")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                    .accessibilityHint("Open settings")
                }
                ToolbarItem(placement: .bottomBar) {
                    Button {
                        vm.addNote()
                    } label: {
                        Image(systemName: "plus")
                            .font(.title)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Add new note")
                    .buttonStyle(.borderedProminent)
                }
            }
            .navigationDestination(for: Note.self) { note in
                NoteDetailView(note: note, vm: vm)
            }
            .alert("Delete Note", isPresented: $showingDeleteAlert, presenting: noteToDelete) { note in
                Button("Delete", role: .destructive) {
                    vm.delete(note: note)
                }
                Button("Cancel", role: .cancel) {}
            } message: { note in
                Text("Are you sure you want to delete the note titled \"\(note.title)\"?")
            }
            .alert("Error", isPresented: $vm.showErrorAlert, actions: {
                Button("OK", role: .cancel) {}
            }, message: {
                Text(vm.errorMessage ?? "Unknown error")
            })
            .sheet(isPresented: $showingSettings) {
                SettingsView(vm: vm, isPresented: $showingSettings)
            }
        }
    }
}

struct NoteRow: View {
    let note: Note

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(note.title)
                    .font(.headline)
                    .lineLimit(1)
                if note.isPinned {
                    Image(systemName: "pin.fill")
                        .foregroundColor(.yellow)
                        .accessibilityLabel("Pinned")
                }
                Spacer()
                Text(note.modifiedAt, style: .date)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Text(note.snippet)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 6)
    }
}

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "note.text")
                .resizable()
                .scaledToFit()
                .frame(width: 120, height: 120)
                .foregroundColor(.secondary)
                .accessibilityHidden(true)
            Text("No notes yet")
                .font(.title2)
                .foregroundColor(.secondary)
            Text("Tap the plus button to create your first note.")
                .font(.body)
                .foregroundColor(.secondary)
        }
        .padding()
    }
}

struct NoteDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var content: String
    @State private var isSavingError: Bool = false
    @State private var showDeleteAlert: Bool = false
    @State private var showPinToggleAlert: Bool = false
    @FocusState private var isFocused: Bool

    let noteId: UUID
    @ObservedObject var vm: NotesViewModel

    private var note: Note? {
        vm.notes.first(where: { $0.id == noteId })
    }

    init(note: Note, vm: NotesViewModel) {
        self.noteId = note.id
        self._content = State(initialValue: note.content)
        self.vm = vm
    }

    var body: some View {
        VStack {
            TextEditor(text: $content)
                .font(.body)
                .padding(8)
                .focused($isFocused)
                .accessibilityLabel("Note content")
                .accessibilityHint("Editable text area for note content")
                .onChange(of: content) { newValue in
                    scheduleSave()
                }
        }
        .navigationTitle(note?.title.isEmpty == false ? note!.title : "New Note")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Back") {
                    dismiss()
                }
                .keyboardShortcut(.escape, modifiers: [])
                .accessibilityLabel("Back to notes list")
            }
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button {
                    showDeleteAlert = true
                } label: {
                    Image(systemName: "trash")
                }
                .keyboardShortcut(.delete, modifiers: [.command])
                .accessibilityLabel("Delete note")
                Button {
                    togglePin()
                } label: {
                    Image(systemName: note?.isPinned == true ? "pin.slash" : "pin")
                }
                .accessibilityLabel(note?.isPinned == true ? "Unpin note" : "Pin note")
            }
        }
        .alert("Delete Note", isPresented: $showDeleteAlert) {
            Button("Delete", role: .destructive) {
                if let note = note {
                    vm.delete(note: note)
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete this note?")
        }
        .alert("Save Error", isPresented: $isSavingError) {
            Button("Retry") {
                saveNow()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Failed to save the note. Please try again.")
        }
        .onAppear {
            isFocused = true
        }
        .onReceive(vm.$showErrorAlert) { show in
            if show {
                isSavingError = true
            }
        }
    }

    private func scheduleSave() {
        // Update note content and modifiedAt, debounce handled in vm
        guard var note = note else { return }
        note.content = content
        vm.update(note: note)
    }

    private func saveNow() {
        guard var note = note else { return }
        note.content = content
        vm.update(note: note)
    }

    private func togglePin() {
        guard let note = note else { return }
        vm.togglePin(note: note)
    }
}

struct SettingsView: View {
    @ObservedObject var vm: NotesViewModel
    @Binding var isPresented: Bool
    @AppStorage("overrideColorScheme") private var overrideColorScheme: String = "system"

    var body: some View {
        NavigationStack {
            Form {
                Section("Appearance") {
                    Picker("Theme", selection: $overrideColorScheme) {
                        Text("System").tag("system")
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel("Theme selection")
                    .accessibilityHint("Choose light, dark, or system appearance")
                }
                Section("Data") {
                    Button(role: .destructive) {
                        vm.clearAll()
                        isPresented = false
                    } label: {
                        Text("Clear All Notes")
                    }
                    .accessibilityLabel("Clear all notes")
                    .accessibilityHint("Deletes all notes permanently")
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        isPresented = false
                    }
                    .accessibilityLabel("Close settings")
                }
            }
        }
        .preferredColorScheme(colorSchemeFromString(overrideColorScheme))
    }

    private func colorSchemeFromString(_ string: String) -> ColorScheme? {
        switch string {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }
}
