import SwiftUI
import LocalAuthentication
import CryptoKit
import Combine

// MARK: - Models

enum VaultItemType: String, Codable, CaseIterable, Identifiable {
    case password, note, document
    var id: String { rawValue }
}

protocol VaultItemProtocol: Identifiable, Codable {
    var id: UUID { get }
    var type: VaultItemType { get }
    var title: String { get set }
}

struct PasswordItem: VaultItemProtocol {
    var id = UUID()
    let type: VaultItemType = .password
    var title: String
    var username: String
    var password: String
    var url: String
    var notes: String
}

struct NoteItem: VaultItemProtocol {
    var id = UUID()
    let type: VaultItemType = .note
    var title: String
    var content: String
}

struct DocumentItem: VaultItemProtocol {
    var id = UUID()
    let type: VaultItemType = .document
    var title: String
    var fileName: String
    var fileData: Data
    var fileUTType: String
}

enum VaultItem: Identifiable, Codable {
    case password(PasswordItem)
    case note(NoteItem)
    case document(DocumentItem)

    var id: UUID {
        switch self {
        case .password(let p): return p.id
        case .note(let n): return n.id
        case .document(let d): return d.id
        }
    }

    var type: VaultItemType {
        switch self {
        case .password: return .password
        case .note: return .note
        case .document: return .document
        }
    }

    var title: String {
        get {
            switch self {
            case .password(let p): return p.title
            case .note(let n): return n.title
            case .document(let d): return d.title
            }
        }
        set {
            switch self {
            case .password(var p): p.title = newValue; self = .password(p)
            case .note(var n): n.title = newValue; self = .note(n)
            case .document(var d): d.title = newValue; self = .document(d)
            }
        }
    }
}

// MARK: - Vault Storage

actor VaultStorage {
    static let shared = VaultStorage()

    private let fileURL: URL
    private let keychainService = "com.example.vault"
    private let keychainAccountKey = "vaultEncryptionKey"

    private var encryptionKey: SymmetricKey?

    init() {
        let fm = FileManager.default
        let dir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("vaultdata.enc")
    }

    private func loadOrCreateKey() throws -> SymmetricKey {
        if let keyData = try? KeychainHelper.shared.read(service: keychainService, account: keychainAccountKey) {
            return SymmetricKey(data: keyData)
        } else {
            let key = SymmetricKey(size: .bits256)
            try KeychainHelper.shared.save(keyData: key.withUnsafeBytes { Data($0) }, service: keychainService, account: keychainAccountKey)
            return key
        }
    }

    func loadItems() async throws -> [VaultItem] {
        if encryptionKey == nil {
            encryptionKey = try loadOrCreateKey()
        }
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let sealedBox = try AES.GCM.SealedBox(combined: data)
        let decrypted = try AES.GCM.open(sealedBox, using: encryptionKey!)
        let items = try JSONDecoder().decode([VaultItem].self, from: decrypted)
        return items
    }

    func saveItems(_ items: [VaultItem]) async throws {
        if encryptionKey == nil {
            encryptionKey = try loadOrCreateKey()
        }
        let data = try JSONEncoder().encode(items)
        let sealedBox = try AES.GCM.seal(data, using: encryptionKey!)
        try sealedBox.combined!.write(to: fileURL, options: [.atomic])
    }

    func resetStorage() async throws {
        try? FileManager.default.removeItem(at: fileURL)
        encryptionKey = try loadOrCreateKey()
    }
}

// MARK: - Keychain Helper

final class KeychainHelper {
    static let shared = KeychainHelper()
    private init() {}

    func save(keyData: Data, service: String, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: keyData
        ]
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unhandledError(status: status) }
    }

    func read(service: String, account: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess {
            return result as? Data
        } else if status == errSecItemNotFound {
            return nil
        } else {
            throw KeychainError.unhandledError(status: status)
        }
    }

    func delete(service: String, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandledError(status: status)
        }
    }

    enum KeychainError: Error {
        case unhandledError(status: OSStatus)
    }
}

// MARK: - Authentication

enum AuthenticationState: Equatable {
    case unauthenticated
    case authenticating
    case authenticated
    case failed(String?)
}

// MARK: - VaultViewModel

@MainActor
final class VaultViewModel: ObservableObject {
    @Published var authState: AuthenticationState = .unauthenticated
    @Published var vaultItems: [VaultItem] = []
    @Published var biometricEnabled: Bool = false
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    private let keychainService = "com.example.vault"
    private let passcodeAccount = "vaultPasscode"
    private let biometricAccount = "vaultBiometricEnabled"

    private var cancellables = Set<AnyCancellable>()

    init() {
        loadBiometricPreference()
    }

    func loadBiometricPreference() {
        if let data = try? KeychainHelper.shared.read(service: keychainService, account: biometricAccount),
           let enabled = data.first, enabled == 1 {
            biometricEnabled = true
        } else {
            biometricEnabled = false
        }
    }

    func setBiometricEnabled(_ enabled: Bool) {
        biometricEnabled = enabled
        let data = Data([enabled ? 1 : 0])
        try? KeychainHelper.shared.save(keyData: data, service: keychainService, account: biometricAccount)
    }

    func authenticate() {
        authState = .authenticating
        let context = LAContext()
        var error: NSError?
        if biometricEnabled && context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "Authenticate to access Vault") { [weak self] success, err in
                DispatchQueue.main.async {
                    if success {
                        self?.authState = .authenticated
                        Task { await self?.loadVault() }
                    } else {
                        self?.authState = .failed("Biometric authentication failed.")
                    }
                }
            }
        } else {
            authState = .unauthenticated
        }
    }

    func verifyPasscode(_ input: String) -> Bool {
        guard let stored = try? KeychainHelper.shared.read(service: keychainService, account: passcodeAccount),
              let storedString = stored.flatMap({ String(data: $0, encoding: .utf8) }) else {
            return false
        }
        return storedString == input
    }

    func setPasscode(_ newPasscode: String) throws {
        guard newPasscode.count == 6 else { throw VaultError.invalidPasscodeLength }
        let data = Data(newPasscode.utf8)
        try KeychainHelper.shared.save(keyData: data, service: keychainService, account: passcodeAccount)
    }

    func hasPasscode() -> Bool {
        if let data = try? KeychainHelper.shared.read(service: keychainService, account: passcodeAccount),
           let str = data.flatMap({ String(data: $0, encoding: .utf8) }) {
            return str.count == 6
        }
        return false
    }

    func loadVault() async {
        isLoading = true
        do {
            vaultItems = try await VaultStorage.shared.loadItems()
            errorMessage = nil
        } catch {
            vaultItems = []
            errorMessage = "Failed to load vault data."
        }
        isLoading = false
    }

    func saveVault() async {
        do {
            try await VaultStorage.shared.saveItems(vaultItems)
            errorMessage = nil
        } catch {
            errorMessage = "Failed to save vault data."
        }
    }

    func addItem(_ item: VaultItem) async {
        vaultItems.append(item)
        await saveVault()
    }

    func updateItem(_ item: VaultItem) async {
        if let idx = vaultItems.firstIndex(where: { $0.id == item.id }) {
            vaultItems[idx] = item
            await saveVault()
        }
    }

    func deleteItem(_ item: VaultItem) async {
        vaultItems.removeAll(where: { $0.id == item.id })
        await saveVault()
    }

    func resetPasscode() async throws {
        try await VaultStorage.shared.resetStorage()
        try KeychainHelper.shared.delete(service: keychainService, account: passcodeAccount)
        setBiometricEnabled(false)
        vaultItems = []
        authState = .unauthenticated
    }

    enum VaultError: Error, LocalizedError {
        case invalidPasscodeLength
        var errorDescription: String? {
            switch self {
            case .invalidPasscodeLength: return "Passcode must be exactly 6 digits."
            }
        }
    }
}

// MARK: - Views

struct ContentView: View {
    @StateObject private var vm = VaultViewModel()

    var body: some View {
        Group {
            switch vm.authState {
            case .unauthenticated:
                AuthenticationView()
                    .environmentObject(vm)
            case .authenticating:
                ProgressView("Authenticating...")
            case .authenticated:
                VaultListView()
                    .environmentObject(vm)
            case .failed(let message):
                AuthenticationView(errorMessage: message)
                    .environmentObject(vm)
            }
        }
        .onAppear {
            vm.authenticate()
        }
        .alert(item: $vm.errorMessage) { msg in
            Alert(title: Text("Error"), message: Text(msg), dismissButton: .default(Text("OK")))
        }
    }
}

// MARK: AuthenticationView

struct AuthenticationView: View {
    @EnvironmentObject var vm: VaultViewModel
    @State private var passcodeInput: String = ""
    @State private var showResetPasscodeConfirm = false
    var errorMessage: String?

    var body: some View {
        VStack(spacing: 20) {
            Text("Vault")
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)

            if let errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .accessibilityLabel("Authentication error: \(errorMessage)")
            }

            if vm.biometricEnabled {
                Button(action: {
                    vm.authenticate()
                }) {
                    Label("Use Biometric Authentication", systemImage: "faceid")
                        .font(.title3)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.accentColor.opacity(0.2))
                        .cornerRadius(10)
                }
                .accessibilityLabel("Authenticate using biometrics")
            }

            VStack(alignment: .leading) {
                Text("Enter 6-digit Passcode")
                    .font(.headline)
                SecureField("Passcode", text: $passcodeInput)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .font(.title2)
                    .padding(10)
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(8)
                    .accessibilityLabel("Passcode input field")
                    .onSubmit {
                        verifyPasscode()
                    }
            }
            .padding(.horizontal)

            Button("Unlock") {
                verifyPasscode()
            }
            .buttonStyle(.borderedProminent)
            .disabled(passcodeInput.count != 6)
            .accessibilityLabel("Unlock vault with passcode")

            if vm.biometricEnabled {
                Button("Reset Passcode") {
                    showResetPasscodeConfirm = true
                }
                .foregroundColor(.red)
                .accessibilityLabel("Reset passcode after biometric authentication")
                .confirmationDialog("Resetting passcode will erase all vault data. Are you sure?", isPresented: $showResetPasscodeConfirm) {
                    Button("Reset", role: .destructive) {
                        Task {
                            do {
                                try await vm.resetPasscode()
                            } catch {
                                // ignore
                            }
                        }
                    }
                    Button("Cancel", role: .cancel) {}
                }
            }

            Spacer()
        }
        .padding()
        .onAppear {
            passcodeInput = ""
        }
    }

    private func verifyPasscode() {
        if vm.verifyPasscode(passcodeInput) {
            vm.authState = .authenticated
            Task { await vm.loadVault() }
        } else {
            vm.authState = .failed("Incorrect passcode.")
            passcodeInput = ""
        }
    }
}

// MARK: VaultListView

struct VaultListView: View {
    @EnvironmentObject var vm: VaultViewModel
    @State private var searchText = ""
    @State private var showingAddItem = false
    @State private var showingSettings = false
    @State private var alertItemToDelete: VaultItem?

    var filteredItems: [VaultItem] {
        if searchText.isEmpty {
            return vm.vaultItems
        } else {
            return vm.vaultItems.filter {
                $0.title.localizedCaseInsensitiveContains(searchText) ||
                itemContent($0).localizedCaseInsensitiveContains(searchText)
            }
        }
    }

    var groupedItems: [VaultItemType: [VaultItem]] {
        Dictionary(grouping: filteredItems, by: { $0.type })
    }

    var body: some View {
        NavigationStack {
            List {
                if vm.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, alignment: .center)
                } else if vm.vaultItems.isEmpty {
                    Text("No items in your vault.")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    ForEach(VaultItemType.allCases) { type in
                        if let items = groupedItems[type], !items.isEmpty {
                            Section(header: Text(type.rawValue.capitalized)) {
                                ForEach(items) { item in
                                    NavigationLink(value: item) {
                                        VaultItemRow(item: item)
                                    }
                                    .accessibilityLabel("[1m\(item.title)[0m, type \(type.rawValue)")
                                }
                                .onDelete { indexSet in
                                    guard let idx = indexSet.first else { return }
                                    let item = items[idx]
                                    alertItemToDelete = item
                                }
                            }
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search vault items")
            .navigationTitle("Vault")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingAddItem = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add new vault item")
                }
            }
            .sheet(isPresented: $showingAddItem) {
                AddVaultItemView { newItem in
                    Task {
                        await vm.addItem(newItem)
                    }
                    showingAddItem = false
                } onCancel: {
                    showingAddItem = false
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
                    .environmentObject(vm)
            }
            .alert("Delete Item", isPresented: Binding(get: { alertItemToDelete != nil }, set: { if !$0 { alertItemToDelete = nil } })) {
                Button("Delete", role: .destructive) {
                    if let item = alertItemToDelete {
                        Task {
                            await vm.deleteItem(item)
                        }
                        alertItemToDelete = nil
                    }
                }
                Button("Cancel", role: .cancel) {
                    alertItemToDelete = nil
                }
            }, message: {
                Text("Are you sure you want to delete \(alertItemToDelete?.title ?? "this item")?")
            })
            .navigationDestination(for: VaultItem.self) { item in
                VaultItemDetailView(item: item) { updatedItem in
                    Task {
                        await vm.updateItem(updatedItem)
                    }
                }
            }
        }
    }

    private func itemContent(_ item: VaultItem) -> String {
        switch item {
        case .password(let p):
            return p.username + " " + p.notes + " " + p.url
        case .note(let n):
            return n.content
        case .document(let d):
            return d.fileName
        }
    }
}

struct VaultItemRow: View {
    let item: VaultItem

    var body: some View {
        HStack {
            Image(systemName: iconName)
                .foregroundColor(iconColor)
                .accessibilityHidden(true)
            VStack(alignment: .leading) {
                Text(item.title)
                    .font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }

    private var iconName: String {
        switch item.type {
        case .password: return "key.fill"
        case .note: return "note.text"
        case .document: return "doc.fill"
        }
    }

    private var iconColor: Color {
        switch item.type {
        case .password: return .blue
        case .note: return .green
        case .document: return .orange
        }
    }

    private var subtitle: String {
        switch item {
        case .password(let p): return p.username
        case .note(let n): return n.content
        case .document(let d): return d.fileName
        }
    }
}

// MARK: VaultItemDetailView

struct VaultItemDetailView: View {
    @Environment(\.dismiss) var dismiss
    @State private var item: VaultItem
    @State private var showPassword: Bool = false
    @State private var showCopyConfirmation: Bool = false
    @State private var copyMessage: String = ""
    var onSave: (VaultItem) -> Void

    init(item: VaultItem, onSave: @escaping (VaultItem) -> Void) {
        _item = State(initialValue: item)
        self.onSave = onSave
    }

    var body: some View {
        Form {
            Section(header: Text("Title")) {
                TextField("Title", text: bindingTitle)
                    .accessibilityLabel("Title")
            }

            switch item {
            case .password(var p):
                Section(header: Text("Username")) {
                    TextField("Username", text: bindingPasswordUsername)
                        .textContentType(.username)
                        .accessibilityLabel("Username")
                }
                Section(header: Text("Password")) {
                    if showPassword {
                        TextField("Password", text: bindingPasswordPassword)
                            .textContentType(.password)
                            .accessibilityLabel("Password visible")
                    } else {
                        SecureField("Password", text: bindingPasswordPassword)
                            .textContentType(.password)
                            .accessibilityLabel("Password hidden")
                    }
                    Button(showPassword ? "Hide Password" : "Show Password") {
                        showPassword.toggle()
                    }
                    .accessibilityLabel(showPassword ? "Hide password" : "Show password")
                    Button("Copy Password") {
                        UIPasteboard.general.string = p.password
                        copyMessage = "Password copied to clipboard"
                        showCopyConfirmation = true
                    }
                    .accessibilityLabel("Copy password to clipboard")
                }
                Section(header: Text("URL")) {
                    TextField("URL", text: bindingPasswordURL)
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .accessibilityLabel("URL")
                }
                Section(header: Text("Notes")) {
                    TextEditor(text: bindingPasswordNotes)
                        .frame(minHeight: 80)
                        .accessibilityLabel("Notes")
                }
            case .note(var n):
                Section(header: Text("Note")) {
                    TextEditor(text: bindingNoteContent)
                        .frame(minHeight: 150)
                        .accessibilityLabel("Note content")
                    Button("Copy Note") {
                        UIPasteboard.general.string = n.content
                        copyMessage = "Note copied to clipboard"
                        showCopyConfirmation = true
                    }
                    .accessibilityLabel("Copy note content to clipboard")
                }
            case .document(let d):
                Section(header: Text("File")) {
                    Text(d.fileName)
                        .accessibilityLabel("Document file name: \(d.fileName)")
                    DocumentPreview(data: d.fileData, utType: d.fileUTType)
                        .frame(height: 200)
                }
            }

            Section {
                Button("Save") {
                    onSave(item)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("Save changes")
            }
        }
        .navigationTitle("Edit Item")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Cancel") {
                    dismiss()
                }
                .accessibilityLabel("Cancel editing")
            }
        }
        .toast(isPresented: $showCopyConfirmation, message: copyMessage)
    }

    private var bindingTitle: Binding<String> {
        Binding(get: { item.title }, set: { item.title = $0 })
    }

    private var bindingPasswordUsername: Binding<String> {
        Binding(get: {
            if case .password(let p) = item { return p.username }
            return ""
        }, set: { newVal in
            if case .password(var p) = item {
                p.username = newVal
                item = .password(p)
            }
        })
    }

    private var bindingPasswordPassword: Binding<String> {
        Binding(get: {
            if case .password(let p) = item { return p.password }
            return ""
        }, set: { newVal in
            if case .password(var p) = item {
                p.password = newVal
                item = .password(p)
            }
        })
    }

    private var bindingPasswordURL: Binding<String> {
        Binding(get: {
            if case .password(let p) = item { return p.url }
            return ""
        }, set: { newVal in
            if case .password(var p) = item {
                p.url = newVal
                item = .password(p)
            }
        })
    }

    private var bindingPasswordNotes: Binding<String> {
        Binding(get: {
            if case .password(let p) = item { return p.notes }
            return ""
        }, set: { newVal in
            if case .password(var p) = item {
                p.notes = newVal
                item = .password(p)
            }
        })
    }

    private var bindingNoteContent: Binding<String> {
        Binding(get: {
            if case .note(let n) = item { return n.content }
            return ""
        }, set: { newVal in
            if case .note(var n) = item {
                n.content = newVal
                item = .note(n)
            }
        })
    }
}

// MARK: DocumentPreview

import UniformTypeIdentifiers
import PDFKit

struct DocumentPreview: UIViewRepresentable {
    let data: Data
    let utType: String

    func makeUIView(context: Context) -> UIView {
        if UTType(utType)?.conforms(to: .pdf) == true {
            let pdfView = PDFView()
            pdfView.document = PDFDocument(data: data)
            pdfView.autoScales = true
            pdfView.backgroundColor = .clear
            return pdfView
        } else if UTType(utType)?.conforms(to: .image) == true {
            let imageView = UIImageView(image: UIImage(data: data))
            imageView.contentMode = .scaleAspectFit
            imageView.backgroundColor = .clear
            return imageView
        } else {
            let label = UILabel()
            label.text = "Unsupported file preview"
            label.textAlignment = .center
            label.textColor = .secondaryLabel
            return label
        }
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

// MARK: AddVaultItemView

struct AddVaultItemView: View {
    @Environment(\.dismiss) var dismiss
    @State private var selectedType: VaultItemType = .password

    @State private var title: String = ""

    // Password fields
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var url: String = ""
    @State private var notes: String = ""
    @State private var showPassword: Bool = false

    // Note fields
    @State private var noteContent: String = ""

    // Document fields
    @State private var documentData: Data?
    @State private var documentFileName: String = ""
    @State private var documentUTType: String = ""
    @State private var showingFilePicker = false
    @State private var filePickerError: String?

    var onSave: (VaultItem) -> Void
    var onCancel: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Item Type")) {
                    Picker("Type", selection: $selectedType) {
                        ForEach(VaultItemType.allCases) { type in
                            Text(type.rawValue.capitalized).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel("Select vault item type")
                }

                Section(header: Text("Title")) {
                    TextField("Title", text: $title)
                        .accessibilityLabel("Title")
                }

                switch selectedType {
                case .password:
                    Section(header: Text("Username")) {
                        TextField("Username", text: $username)
                            .textContentType(.username)
                            .accessibilityLabel("Username")
                    }
                    Section(header: Text("Password")) {
                        if showPassword {
                            TextField("Password", text: $password)
                                .textContentType(.password)
                                .accessibilityLabel("Password visible")
                        } else {
                            SecureField("Password", text: $password)
                                .textContentType(.password)
                                .accessibilityLabel("Password hidden")
                        }
                        Button(showPassword ? "Hide Password" : "Show Password") {
                            showPassword.toggle()
                        }
                        .accessibilityLabel(showPassword ? "Hide password" : "Show password")
                    }
                    Section(header: Text("URL")) {
                        TextField("URL", text: $url)
                            .keyboardType(.URL)
                            .textContentType(.URL)
                            .accessibilityLabel("URL")
                    }
                    Section(header: Text("Notes")) {
                        TextEditor(text: $notes)
                            .frame(minHeight: 80)
                            .accessibilityLabel("Notes")
                    }
                case .note:
                    Section(header: Text("Note")) {
                        TextEditor(text: $noteContent)
                            .frame(minHeight: 150)
                            .accessibilityLabel("Note content")
                    }
                case .document:
                    Section(header: Text("File Attachment")) {
                        if let data = documentData {
                            DocumentPreview(data: data, utType: documentUTType)
                                .frame(height: 200)
                            Text(documentFileName)
                                .accessibilityLabel("Attached file name: \(documentFileName)")
                        } else {
                            Text("No file attached")
                                .foregroundColor(.secondary)
                        }
                        Button("Attach File") {
                            showingFilePicker = true
                        }
                        .accessibilityLabel("Attach document file")
                        if let error = filePickerError {
                            Text(error)
                                .foregroundColor(.red)
                                .accessibilityLabel("File picker error: \(error)")
                        }
                    }
                }
            }
            .navigationTitle("Add Item")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        onCancel()
                        dismiss()
                    }
                    .accessibilityLabel("Cancel adding item")
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveItem()
                        dismiss()
                    }
                    .disabled(!isValid)
                    .accessibilityLabel("Save new vault item")
                }
            }
            .fileImporter(isPresented: $showingFilePicker, allowedContentTypes: [.pdf, .image]) { result in
                switch result {
                case .success(let url):
                    do {
                        let data = try Data(contentsOf: url)
                        documentData = data
                        documentFileName = url.lastPathComponent
                        documentUTType = url.typeIdentifier ?? "public.data"
                        filePickerError = nil
                    } catch {
                        filePickerError = "Failed to load file."
                    }
                case .failure:
                    filePickerError = "File selection was cancelled or failed."
                }
            }
        }
    }

    private var isValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        (selectedType != .document || documentData != nil)
    }

    private func saveItem() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        switch selectedType {
        case .password:
            let item = PasswordItem(title: trimmedTitle, username: username, password: password, url: url, notes: notes)
            onSave(.password(item))
        case .note:
            let item = NoteItem(title: trimmedTitle, content: noteContent)
            onSave(.note(item))
        case .document:
            guard let data = documentData else { return }
            let item = DocumentItem(title: trimmedTitle, fileName: documentFileName, fileData: data, fileUTType: documentUTType)
            onSave(.document(item))
        }
    }
}

// MARK: SettingsView

struct SettingsView: View {
    @EnvironmentObject var vm: VaultViewModel
    @Environment(\.dismiss) var dismiss

    @State private var showingChangePasscode = false
    @State private var newPasscode = ""
    @State private var confirmPasscode = ""
    @State private var passcodeError: String?
    @State private var showingExportSheet = false
    @State private var exportData: Data?
    @State private var exportError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Security")) {
                    Toggle("Enable Biometric Authentication", isOn: $vm.biometricEnabled)
                        .onChange(of: vm.biometricEnabled) { newValue in
                            vm.setBiometricEnabled(newValue)
                        }
                        .accessibilityLabel("Toggle biometric authentication")

                    Button("Change Passcode") {
                        showingChangePasscode = true
                    }
                    .accessibilityLabel("Change passcode")
                }

                Section(header: Text("Export")) {
                    Button("Export Vault Data") {
                        Task {
                            await exportVaultData()
                        }
                    }
                    .accessibilityLabel("Export encrypted vault data")
                    if let exportError {
                        Text(exportError)
                            .foregroundColor(.red)
                            .accessibilityLabel("Export error: \(exportError)")
                    }
                }

                Section(header: Text("About")) {
                    Text("Vault v1.0")
                    Link("Privacy Policy", destination: URL(string: "https://example.com/privacy")!)
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .accessibilityLabel("Close settings")
                }
            }
            .sheet(isPresented: $showingChangePasscode) {
                ChangePasscodeView(isPresented: $showingChangePasscode)
                    .environmentObject(vm)
            }
            .sheet(isPresented: $showingExportSheet, onDismiss: {
                exportData = nil
            }) {
                if let data = exportData {
                    ShareSheet(activityItems: [data])
                }
            }
        }
    }

    private func exportVaultData() async {
        do {
            let items = vm.vaultItems
            let encoder = JSONEncoder()
            let jsonData = try encoder.encode(items)

            // Encrypt export data with same key
            let key = try await VaultStorage.shared.loadOrCreateKey()
            let sealedBox = try AES.GCM.seal(jsonData, using: key)
            exportData = sealedBox.combined
            exportError = nil
            showingExportSheet = true
        } catch {
            exportError = "Failed to export vault data."
        }
    }
}

// MARK: ChangePasscodeView

struct ChangePasscodeView: View {
    @EnvironmentObject var vm: VaultViewModel
    @Binding var isPresented: Bool

    @State private var newPasscode = ""
    @State private var confirmPasscode = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("New Passcode")) {
                    SecureField("6-digit passcode", text: $newPasscode)
                        .keyboardType(.numberPad)
                        .accessibilityLabel("New passcode")
                }
                Section(header: Text("Confirm Passcode")) {
                    SecureField("Confirm passcode", text: $confirmPasscode)
                        .keyboardType(.numberPad)
                        .accessibilityLabel("Confirm new passcode")
                }
                if let errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .accessibilityLabel("Error: \(errorMessage)")
                }
            }
            .navigationTitle("Change Passcode")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        isPresented = false
                    }
                    .accessibilityLabel("Cancel passcode change")
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        savePasscode()
                    }
                    .disabled(newPasscode.count != 6 || confirmPasscode.count != 6)
                    .accessibilityLabel("Save new passcode")
                }
            }
        }
    }

    private func savePasscode() {
        guard newPasscode == confirmPasscode else {
            errorMessage = "Passcodes do not match."
            return
        }
        guard newPasscode.count == 6 else {
            errorMessage = "Passcode must be 6 digits."
            return
        }
        do {
            try vm.setPasscode(newPasscode)
            errorMessage = nil
            isPresented = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: ShareSheet

import UIKit

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    let applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: Toast Modifier

struct ToastModifier: ViewModifier {
    @Binding var isPresented: Bool
    let message: String

    func body(content: Content) -> some View {
        ZStack(alignment: .bottom) {
            content
            if isPresented {
                Text(message)
                    .font(.footnote)
                    .padding()
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                    .padding(.bottom, 40)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            withAnimation {
                                isPresented = false
                            }
                        }
                    }
                    .accessibilityLiveRegion(.polite)
            }
        }
    }
}

extension View {
    func toast(isPresented: Binding<Bool>, message: String) -> some View {
        modifier(ToastModifier(isPresented: isPresented, message: message))
    }
}
