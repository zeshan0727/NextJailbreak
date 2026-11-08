import SwiftUI
import UniformTypeIdentifiers
import UIKit

@main struct NEXTREAInspectorApp: App {
    var body: some Scene {
        WindowGroup { InspectorView().preferredColorScheme(.dark) }
    }
}

private enum Theme {
    static let bg = Color(red: 0.045, green: 0.063, blue: 0.098)
    static let card = Color(red: 0.091, green: 0.125, blue: 0.172)
    static let accent = Color(red: 0.30, green: 0.81, blue: 0.96)
    static let muted = Color(red: 0.63, green: 0.73, blue: 0.80)
}

private struct AppInfo: Identifiable, Hashable {
    let id: String
    let name: String
    let version: String
    let path: String
}

struct InspectorView: View {
    @State private var installed: [AppInfo] = []
    @State private var query = ""
    @State private var chosen: AppInfo?
    @State private var importing = false
    @State private var importedIPA: URL?
    @State private var sharing = false
    @State private var shared: [Any] = []
    @State private var alertMessage = ""
    @State private var alertVisible = false

    private var filtered: [AppInfo] {
        query.isEmpty ? installed : installed.filter {
            $0.name.localizedCaseInsensitiveContains(query) ||
            $0.id.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack {
                            Image(systemName: "waveform.path.ecg.rectangle")
                                .foregroundStyle(Theme.accent)
                            Text("NEXT").font(.headline).tracking(2)
                            Spacer()
                            Text("TEST 0.1").font(.caption.bold()).foregroundStyle(Theme.accent)
                        }
                        Text("REA Inspector")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                        Text("Read-only evidence collection for Mac-side reverse engineering.")
                            .foregroundStyle(Theme.muted)
                            .font(.subheadline)
                        scanCard
                        ipaCard
                        installedCard
                        Text("LOCAL  ·  READ ONLY  ·  NO PRIVATE APP DATA")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(Theme.muted)
                            .frame(maxWidth: .infinity)
                    }
                    .padding(18)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .fileImporter(isPresented: $importing, allowedContentTypes: [.data], allowsMultipleSelection: false) { result in
                do {
                    guard let url = try result.get().first else { return }
                    guard url.pathExtension.lowercased() == "ipa" else {
                        throw NSError(domain: "NEXTREA", code: 1,
                                      userInfo: [NSLocalizedDescriptionKey: "Choose a .ipa file."])
                    }
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    let dst = root.appendingPathComponent(UUID().uuidString + "-" + url.lastPathComponent)
                    try FileManager.default.copyItem(at: url, to: dst)
                    importedIPA = dst
                } catch { show(error.localizedDescription) }
            }
            .sheet(isPresented: $sharing) { REAShare(items: shared) }
            .alert("NEXT REA", isPresented: $alertVisible) {
                Button("OK", role: .cancel) {}
            } message: { Text(alertMessage) }
            .onAppear(perform: scan)
        }
    }

    private var scanCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Label("Device scan", systemImage: "iphone.gen3").font(.headline)
                Spacer()
                Text("iOS \(UIDevice.current.systemVersion)")
                    .font(.caption.bold()).foregroundStyle(Theme.accent)
            }
            HStack(alignment: .firstTextBaseline) {
                Text("\(installed.count)")
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("visible apps").foregroundStyle(Theme.muted)
            }
            Button(action: scan) {
                Label("Refresh installed apps", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.bg)
            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 12))
            Text("Experimental private LaunchServices access. A sandboxed or restricted device can return zero apps.")
                .font(.caption).foregroundStyle(Theme.muted)
        }.panel()
    }

    private var ipaCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("IPA handoff", systemImage: "shippingbox").font(.headline)
            Text("Select a permitted IPA in Files and share it to your Mac for REA inspection.")
                .font(.subheadline).foregroundStyle(Theme.muted)
            Button { importing = true } label: {
                Label("Choose IPA file", systemImage: "folder").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).tint(Theme.accent)
            if let importedIPA {
                Text(importedIPA.lastPathComponent)
                    .font(.caption).foregroundStyle(Theme.muted).lineLimit(2)
                Button { share(importedIPA) } label: {
                    Label("Share IPA to Mac", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
            }
        }.panel()
    }

    private var installedCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Installed applications", systemImage: "square.stack.3d.up")
                .font(.headline)
            TextField("Search name or bundle ID", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(12)
                .background(Theme.bg, in: RoundedRectangle(cornerRadius: 12))
            if filtered.isEmpty {
                Text("No apps visible. You can still import an IPA.")
                    .font(.subheadline).foregroundStyle(Theme.muted)
            }
            ForEach(Array(filtered.prefix(150))) { app in
                Button { chosen = app } label: {
                    HStack {
                        Image(systemName: "app.fill").foregroundStyle(Theme.accent)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(app.name).font(.subheadline.bold()).lineLimit(1)
                            Text(app.id).font(.caption2)
                                .foregroundStyle(Theme.muted).lineLimit(1)
                        }
                        Spacer()
                        Image(systemName: chosen == app ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(chosen == app ? Theme.accent : Theme.muted)
                    }
                }
                .buttonStyle(.plain)
                Divider().overlay(Color.white.opacity(0.05))
            }
            if let chosen {
                Text("Selected: \(chosen.name) · v\(chosen.version)")
                    .font(.caption).foregroundStyle(Theme.muted)
                Button { export(chosen) } label: {
                    Label("Export metadata JSON", systemImage: "doc.text")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(Theme.accent)
            }
        }.panel()
    }

    private func scan() {
        installed = InstalledApps.installedApplications().compactMap { row in
            guard let id = row["bundleID"], !id.isEmpty else { return nil }
            return AppInfo(id: id, name: row["name"] ?? id,
                           version: row["version"] ?? "Unknown",
                           path: row["path"] ?? "Not exposed")
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        if let chosen, !installed.contains(chosen) { self.chosen = nil }
    }

    private func export(_ app: AppInfo) {
        do {
            let body: [String: Any] = [
                "schema": "next-rea-device-inventory/v1",
                "capturedAt": ISO8601DateFormatter().string(from: Date()),
                "bundleID": app.id, "name": app.name,
                "version": app.version, "bundlePath": app.path,
                "scope": "Metadata only; not source code or behavioral evidence."
            ]
            let bytes = try JSONSerialization.data(withJSONObject: body,
                                                   options: [.prettyPrinted, .sortedKeys])
            let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let target = root.appendingPathComponent("NEXT-REA-\(app.id).json")
            try bytes.write(to: target, options: .atomic)
            share(target)
        } catch { show(error.localizedDescription) }
    }
    private func share(_ url: URL) { shared = [url]; sharing = true }
    private func show(_ message: String) { alertMessage = message; alertVisible = true }
}

private struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content.frame(maxWidth: .infinity, alignment: .leading)
            .padding(17)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18)
                .strokeBorder(Color.white.opacity(0.08)))
    }
}
private extension View {
    func panel() -> some View { modifier(CardStyle()) }
}
private struct REAShare: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
