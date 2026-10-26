import SwiftUI
import UniformTypeIdentifiers
import UIKit

@main
struct NextCompatApp: App {
    @StateObject private var model = CompatModel()
    var body: some Scene { WindowGroup { MainScreen().environmentObject(model) } }
}

@MainActor
final class CompatModel: ObservableObject {
    @Published var installed: ImportedIPA?
    @Published var requestedSymbol = ""
    @Published var busy = false
    @Published var status = "Import a decrypted IPA to start."
    @Published var exportedURL: URL?
    @Published var crashName: String?
    @Published var patchedHistory: [String] = []
    private let service = IPAService()
    private let fm = FileManager.default
    private var savedOriginal: URL?

    var canPatch: Bool {
        guard let app = installed else { return false }
        return !busy && app.imports.filter { $0.symbol == requestedSymbol && !$0.weak }.count == 1
    }

    // Stage and inspect large IPA archives away from the UI thread. A decrypted
    // 100+ MB package can take time to copy and unzip on an iPhone.
    func importFile(_ url: URL) {
        guard !busy else { return }
        let ext = url.pathExtension.lowercased()
        guard ext == "ipa" || ext == "tipa" else {
            status = "Choose a decrypted .ipa or .tipa file from Files."
            return
        }
        do {
            let dir = try supportDirectory()
            let target = dir.appendingPathComponent("Original-\(UUID().uuidString).ipa")
            busy = true
            status = "Copying and inspecting \(url.lastPathComponent)…"
            Task {
                do {
                    let result = try await Task.detached(priority: .userInitiated) {
                        let scoped = url.startAccessingSecurityScopedResource()
                        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                        try FileManager.default.copyItem(at: url, to: target)
                        do {
                            return try IPAService().inspect(target)
                        } catch {
                            try? FileManager.default.removeItem(at: target)
                            throw error
                        }
                    }.value
                    installed = result
                    savedOriginal = target
                    requestedSymbol = result.imports.contains(where: {
                        $0.symbol == "_NSUserActivityTypeLiveActivity" && !$0.weak
                    }) ? "_NSUserActivityTypeLiveActivity" : ""
                    exportedURL = nil
                    status = "\(result.name) imported. \(result.imports.count) symbols inspected."
                } catch {
                    status = "IPA import failed: \(error.localizedDescription)"
                    try? fm.removeItem(at: target)
                }
                busy = false
            }
        } catch {
            status = "IPA import failed: \(error.localizedDescription)"
            busy = false
        }
    }

    func importCrash(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            guard let symbol = CrashReportParser.missingSymbol(in: text) else {
                status = "No DYLD missing-symbol error found in this report."
                return
            }
            requestedSymbol = symbol
            crashName = url.lastPathComponent
            status = "Crash report identifies \(symbol). Verify matching IPA import before patching."
        } catch { status = "Crash import failed: \(error.localizedDescription)" }
    }

    func exportPatch() {
        guard canPatch, let source = savedOriginal else { return }
        let symbol = requestedSymbol
        busy = true
        status = "Applying targeted compatibility patch…"
        Task {
            do {
                let dir = try supportDirectory().appendingPathComponent("Exports")
                let result = try await Task.detached(priority: .userInitiated) {
                    try IPAService().patch(source: source, symbol: symbol, outputFolder: dir)
                }.value
                exportedURL = result.ipa
                patchedHistory.insert("\(symbol) • byte \(result.receipt.offset) • \(result.ipa.lastPathComponent)", at: 0)
                status = "Verified: one import changed to optional. Share IPA to TrollStore to install."
            } catch { status = "Patch failed safely: \(error.localizedDescription)" }
            busy = false
        }
    }

    func originalURL() -> URL? { savedOriginal }

    private func supportDirectory() throws -> URL {
        let base = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let dir = base.appendingPathComponent("NextCompat", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

struct MainScreen: View {
    @EnvironmentObject private var model: CompatModel
    @State private var activePicker: ImportKind?
    private let panel = Color(red: 0.10, green: 0.14, blue: 0.22)
    private let accent = Color(red: 0.48, green: 0.73, blue: 1.0)

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(colors: [Color(red: 0.08, green: 0.12, blue: 0.20), Color(red: 0.04, green: 0.06, blue: 0.11)], startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        header
                        HStack(spacing: 10) {
                            stat("Selected", model.installed == nil ? "0" : "1")
                            stat("Imports", "\(model.installed?.imports.count ?? 0)")
                            stat("Fixed", "\(model.patchedHistory.count)")
                        }
                        group("Select app") {
                            Button {
                                model.status = "Opening Files — choose a decrypted .ipa or .tipa…"
                                activePicker = .ipa
                            } label: {
                                Label(model.installed?.name ?? "Import decrypted IPA", systemImage: "square.and.arrow.down")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .disabled(model.busy)
                            if let app = model.installed {
                                Text("\(app.identifier)  •  v\(app.version)").font(.caption).foregroundStyle(.white.opacity(0.62))
                            }
                        }
                        group("Crash analysis") {
                            Button {
                                model.status = "Opening Files — choose a .ips crash report…"
                                activePicker = .crash
                            } label: {
                                Label(model.crashName ?? "Import .ips crash report", systemImage: "doc.text.magnifyingglass")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .disabled(model.busy)
                            TextField("Missing symbol (exact name)", text: $model.requestedSymbol)
                                .textInputAutocapitalization(.never).autocorrectionDisabled()
                                .padding(12).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                                .foregroundStyle(.white)
                            if let app = model.installed, !model.requestedSymbol.isEmpty {
                                let matching = app.imports.filter { $0.symbol == model.requestedSymbol }
                                Label(matching.isEmpty ? "Symbol not present in selected executable" : (matching.allSatisfy(\.weak) ? "Already optional" : "Required import found — eligible for test patch"), systemImage: matching.count == 1 && !matching[0].weak ? "checkmark.shield" : "exclamationmark.triangle")
                                    .font(.caption).foregroundStyle(matching.count == 1 && !matching[0].weak ? .green : .orange)
                            }
                        }
                        group("Repair") {
                            Text("Changes only the exact matching chained-import weak-link flag. Runtime compatibility is not guaranteed.")
                                .font(.caption).foregroundStyle(.white.opacity(0.65))
                            Button(action: model.exportPatch) {
                                Label(model.busy ? "Processing…" : "Create patched IPA", systemImage: "wrench.adjustable.fill")
                                    .fontWeight(.semibold).frame(maxWidth: .infinity).padding(12)
                            }
                            .buttonStyle(.plain).background(model.canPatch ? accent : .gray.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
                            .foregroundStyle(.black).disabled(!model.canPatch)
                            if let url = model.exportedURL {
                                ShareLink(item: url) {
                                    Label("Export to TrollStore / Files", systemImage: "square.and.arrow.up")
                                        .frame(maxWidth: .infinity).padding(12)
                                }.background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                            }
                            if let original = model.originalURL() {
                                ShareLink(item: original) {
                                    Label("Export original IPA (rollback)", systemImage: "arrow.uturn.backward")
                                        .font(.footnote)
                                }
                            }
                        }
                        group("Activity") {
                            HStack(alignment: .top, spacing: 10) {
                                if model.busy {
                                    ProgressView().tint(accent)
                                } else {
                                    Image(systemName: "info.circle")
                                }
                                Text(model.status).font(.subheadline)
                            }
                            .foregroundStyle(.white.opacity(0.85))
                            ForEach(model.patchedHistory, id: \.self) { record in
                                Text(record).font(.caption2.monospaced()).foregroundStyle(.white.opacity(0.65))
                            }
                        }
                        Text("Experimental · On-device IPA patching only · Does not disable jailbreak detection or bypass signing. Keep backups and do not test with critical financial apps.")
                            .font(.caption2).foregroundStyle(.white.opacity(0.5))
                    }.padding(18)
                }
            }
            .navigationTitle("NextCompat").navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            // iOS 16 sometimes fails to present multiple SwiftUI fileImporter
            // modifiers on the same view. One UIKit document picker is reliable,
            // and reports selection/cancellation back to the model.
            .sheet(item: $activePicker) { kind in
                NativeDocumentPicker(kind: kind, onPick: { url in
                    activePicker = nil
                    if kind == .ipa { model.importFile(url) }
                    else { model.importCrash(url) }
                }, onCancel: {
                    activePicker = nil
                    model.status = "File selection cancelled."
                })
            }
        }.tint(accent).preferredColorScheme(.dark)
    }
    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "shield.lefthalf.filled").font(.system(size: 30, weight: .semibold))
                .foregroundStyle(accent).frame(width: 60, height: 60)
                .background(accent.opacity(0.13), in: RoundedRectangle(cornerRadius: 18))
            VStack(alignment: .leading, spacing: 3) {
                Text("NextCompat").font(.title2.bold())
                Text("iOS 16 Compatibility Manager").font(.caption).foregroundStyle(.white.opacity(0.55))
            }
            Spacer()
            Text("1.0.1").font(.caption.bold()).foregroundStyle(.green)
        }.foregroundStyle(.white)
    }
    private func stat(_ name: String, _ value: String) -> some View {
        VStack(spacing: 7) {
            Text(value).font(.title2.bold()).monospacedDigit()
            Text(name).font(.caption2).foregroundStyle(.white.opacity(0.55))
        }.frame(maxWidth: .infinity).padding(13)
            .background(panel, in: RoundedRectangle(cornerRadius: 14))
            .foregroundStyle(.white)
    }
    private func group<Content: View>(_ name: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(name.uppercased()).font(.caption.weight(.bold)).foregroundStyle(accent)
            content()
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(panel, in: RoundedRectangle(cornerRadius: 18))
            .foregroundStyle(.white)
    }
}


// A single UIKit picker supports both IPA and crash files on iOS 16.
private enum ImportKind: String, Identifiable {
    case ipa
    case crash
    var id: String { rawValue }
}

private struct NativeDocumentPicker: UIViewControllerRepresentable {
    let kind: ImportKind
    let onPick: (URL) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let types: [UTType] = [.item, .data]
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: types,
            asCopy: true
        )
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) { }

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick, onCancel: onCancel)
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let onPick: (URL) -> Void
        private let onCancel: () -> Void

        init(onPick: @escaping (URL) -> Void, onCancel: @escaping () -> Void) {
            self.onPick = onPick
            self.onCancel = onCancel
        }

        func documentPicker(_ controller: UIDocumentPickerViewController,
                            didPickDocumentsAt urls: [URL]) {
            guard let selected = urls.first else {
                onCancel()
                return
            }
            onPick(selected)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onCancel()
        }
    }
}
