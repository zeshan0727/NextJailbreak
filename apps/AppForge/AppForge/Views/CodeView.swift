import SwiftUI
import UIKit

struct CodeView: View {
    @EnvironmentObject private var state: AppState
    @State private var selectedPath = ""
    @State private var sharing = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    ScreenHeading(title: "Prompt → Code", subtitle: "AI produces source; AppForge adds a fixed build scaffold.")
                    Text("Generation prompt").font(.headline)
                    TextEditor(text: $state.codePrompt)
                        .frame(minHeight: 140).scrollContentBackground(.hidden)
                        .padding(7).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
                    NavigationLink(destination: DiagnosticsView()) {
                        Label("Import iPhone Crash Report (.ips) & Repair", systemImage: "stethoscope")
                    }
                    .buttonStyle(.bordered)
                    if state.repairStatus.contains("JSON") { Text(state.repairStatus).font(.caption).foregroundStyle(.secondary) }
                    ForgeButton(title: "Generate Code", symbol: "curlybraces.square", loading: state.busyCode) {
                        Task { await state.generateCode() }
                    }
                    if let project = state.project {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(project.appName).font(.title2.bold())
                                Text(project.bundleId).font(.footnote).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(project.files.count) files").font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical, 6)
                        Text("Project file tree").font(.headline)
                        ForEach(project.files.sorted(by: { $0.path < $1.path })) { file in
                            Button {
                                selectedPath = file.path
                                UISelectionFeedbackGenerator().selectionChanged()
                            } label: {
                                Label(file.path, systemImage: file.path.hasSuffix(".swift") ? "curlybraces" : "doc.text")
                                    .font(.system(.footnote, design: .monospaced))
                                    .frame(maxWidth: .infinity, alignment: .leading).padding(10)
                                    .background(selectedPath == file.path ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.08),
                                                in: RoundedRectangle(cornerRadius: 8))
                            }.buttonStyle(.plain)
                        }
                        if let file = project.files.first(where: { $0.path == selectedPath }) ?? project.files.first {
                            HStack {
                                Text(file.path).font(.caption.bold()).lineLimit(1)
                                Spacer()
                                Button {
                                    UIPasteboard.general.string = file.content
                                } label: { Label("Copy source", systemImage: "doc.on.doc") }
                            }.padding(.top, 12)
                            ScrollView([.horizontal, .vertical]) {
                                Text(file.content)
                                    .font(.system(size: 11, design: .monospaced))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(12)
                            }
                            .frame(height: 290)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                        }
                        HStack {
                            Button {
                                state.exportZip()
                                sharing = state.exportURL != nil
                            } label: { Label("Export ZIP", systemImage: "square.and.arrow.up") }
                            .buttonStyle(.bordered)
                            Spacer()
                            Button {
                                state.sendProjectToGitHub()
                            } label: { Label("Send to GitHub", systemImage: "arrow.right") }
                            .buttonStyle(.borderedProminent)
                        }.padding(.vertical, 12)
                        Text("Generated Swift code is validated structurally but must pass Xcode build to prove compilation. Build errors can be sent to AI repair.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(.horizontal, 17).padding(.bottom, 30)
            }
            .navigationTitle("Code")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $sharing) {
                if let url = state.exportURL { ShareSheet(items: [url]) }
            }
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
