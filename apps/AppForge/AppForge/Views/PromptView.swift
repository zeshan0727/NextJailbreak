import SwiftUI
import UIKit

struct PromptView: View {
    @EnvironmentObject private var state: AppState
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 17) {
                    ScreenHeading(title: "Requirement → Prompt", subtitle: "Describe the app you want to create.")
                    Text("App requirement").font(.headline)
                    TextEditor(text: $state.requirement)
                        .frame(minHeight: 135).scrollContentBackground(.hidden)
                        .padding(7).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
                        .accessibilityLabel("Plain-language app requirement")
                    ForgeButton(title: "Generate Prompt", symbol: "sparkles", loading: state.busyPrompt) {
                        Task { await state.generatePrompt() }
                    }
                    if !state.generatedPrompt.isEmpty {
                        Text("Editable generation prompt").font(.headline)
                        TextEditor(text: $state.generatedPrompt)
                            .frame(minHeight: 240).scrollContentBackground(.hidden)
                            .padding(7).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
                        HStack {
                            Button {
                                UIPasteboard.general.string = state.generatedPrompt
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            } label: { Label("Copy", systemImage: "doc.on.doc") }
                            Spacer()
                            Button {
                                state.sendPromptToCode()
                            } label: { Label("Send to Code", systemImage: "arrow.right.circle.fill") }
                            .buttonStyle(.borderedProminent)
                            Spacer()
                            Button("Clear", role: .destructive) { state.generatedPrompt = "" }
                        }.font(.subheadline)
                    }
                    if !state.history.isEmpty {
                        Text("Recent prompts").font(.headline).padding(.top, 8)
                        ForEach(state.history) { item in
                            Button {
                                state.requirement = item.requirement
                                state.generatedPrompt = item.prompt
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(item.requirement).lineLimit(2).foregroundStyle(.primary)
                                        Text(item.date, style: .date).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "arrow.uturn.backward")
                                }
                                .padding(13).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                            }
                        }
                    }
                }.padding(.horizontal, 17).padding(.bottom, 28)
            }
            .navigationTitle("Prompt")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
