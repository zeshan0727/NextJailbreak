import SwiftUI

struct ContentView: View {
    @StateObject private var store = NextPostStore()

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.02, green: 0.04, blue: 0.08), Color(red: 0.03, green: 0.07, blue: 0.13), Color.black], startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 18) {
                    header
                    stats
                    refreshButton
                    generateButton
                    articleContext
                    yourTakeBox
                    resultBox
                    actionButtons
                    sourceFooter
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 30)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { adBanner }
        .task { await store.refreshStats() }
        .alert("Next Post", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("OK", role: .cancel) { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image("NextPostIcon").resizable().scaledToFit().frame(width: 68, height: 68)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: .blue.opacity(0.25), radius: 14, y: 5)
            VStack(alignment: .leading, spacing: 4) {
                Text("Next Post").font(.system(size: 30, weight: .bold, design: .rounded))
                Text("Your voice → Next Jailbreak → X").font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var stats: some View {
        HStack(spacing: 0) {
            stat(title: "Articles", value: "\(store.totalArticles)")
            divider
            stat(title: "Opened in X", value: "\(store.generatedCount)", accent: true)
            divider
            stat(title: "Remaining", value: "\(store.remainingThisCycle)")
        }
        .padding(.vertical, 16).background(panelBackground)
    }

    private func stat(title: String, value: String, accent: Bool = false) -> some View {
        VStack(spacing: 5) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(size: 24, weight: .bold, design: .rounded)).foregroundStyle(accent ? Color.blue : Color.primary).monospacedDigit()
        }.frame(maxWidth: .infinity)
    }

    private var divider: some View {
        Rectangle().fill(Color.white.opacity(0.10)).frame(width: 1, height: 44)
    }

    private var refreshButton: some View {
        VStack(spacing: 8) {
            Button {
                Task { await store.refreshStats(manual: true) }
            } label: {
                HStack(spacing: 9) {
                    if store.isRefreshing { ProgressView().tint(.white) } else { Image(systemName: "arrow.clockwise") }
                    Text(store.isRefreshing ? "Refreshing Articles…" : "Refresh Articles").fontWeight(.semibold)
                    Spacer()
                    if !store.isRefreshing { Image(systemName: "newspaper").foregroundStyle(.secondary) }
                }
                .padding(.horizontal, 15).padding(.vertical, 12)
                .background(Color.white.opacity(0.065)).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.white.opacity(0.10), lineWidth: 1))
            }
            .buttonStyle(.plain).disabled(store.isLoading || store.isRefreshing)

            if !store.refreshResult.isEmpty {
                Text(store.refreshResult).font(.caption)
                    .foregroundStyle(store.historyProtected ? Color.orange : (store.refreshResult.contains("new article") ? Color.green : Color.secondary))
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 4)
            }
        }
    }

    private var generateButton: some View {
        Button {
            Task { await store.generate() }
        } label: {
            HStack(spacing: 10) {
                if store.isLoading { ProgressView().tint(.white) } else { Image(systemName: "shuffle") }
                Text(store.isLoading ? "Selecting Article…" : "Select Next Article").fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 16).foregroundStyle(.white)
            .background(LinearGradient(colors: [Color.blue, Color.purple], startPoint: .leading, endPoint: .trailing))
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
        .disabled(store.isLoading || store.isRefreshing).opacity(store.isLoading ? 0.78 : 1)
    }

    @ViewBuilder private var articleContext: some View {
        if let article = store.selectedArticle {
            VStack(alignment: .leading, spacing: 9) {
                Label("Verified article context", systemImage: "checkmark.shield.fill").font(.headline)
                Text(article.title).font(.subheadline.weight(.semibold))
                if !store.verifiedContext.isEmpty {
                    Text(store.verifiedContext).font(.subheadline).foregroundStyle(.secondary)
                }
                Text("Use this as factual context. Write the final opinion/commentary below in your own words.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(15).frame(maxWidth: .infinity, alignment: .leading).background(panelBackground)
        }
    }

    @ViewBuilder private var yourTakeBox: some View {
        if store.selectedArticle != nil {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Label("Your Take", systemImage: "person.text.rectangle").font(.headline)
                    Spacer()
                    Text("\(store.userTake.trimmingCharacters(in: .whitespacesAndNewlines).count)+ chars")
                        .font(.caption.monospacedDigit()).foregroundStyle(store.canOpenInX ? Color.green : Color.secondary)
                }
                TextEditor(text: $store.userTake)
                    .frame(minHeight: 105)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .background(Color.black.opacity(0.25))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(store.canOpenInX ? Color.green.opacity(0.45) : Color.white.opacity(0.10), lineWidth: 1))
                Text("Write at least \(PostComposer.minimumUserTakeCharacters) characters yourself. Next Post only adds the article link and focused hashtags.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(15).background(panelBackground)
        }
    }

    private var resultBox: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("X Preview", systemImage: "text.quote").font(.headline)
                Spacer()
                if !store.generatedPost.isEmpty {
                    Text("\(store.generatedPost.count)/\(PostComposer.maximumCharacters)").font(.caption.monospacedDigit())
                        .foregroundColor(store.generatedPost.count <= PostComposer.maximumCharacters ? .gray : .red)
                }
            }
            Divider().overlay(Color.white.opacity(0.08))
            if store.generatedPost.isEmpty {
                Text(store.selectedArticle == nil ? "Select an article first." : "Your final X post preview appears here as you write Your Take.")
                    .font(.subheadline).foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 90, alignment: .center)
            } else {
                Text(store.generatedPost).font(.system(size: 16, design: .rounded)).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
            }
        }
        .padding(16).background(panelBackground)
    }

    private var actionButtons: some View {
        VStack(spacing: 11) {
            Button { store.copyPost() } label: {
                Label(store.copied ? "Copied!" : "Copy Preview", systemImage: store.copied ? "checkmark.circle.fill" : "doc.on.doc")
                    .frame(maxWidth: .infinity).padding(.vertical, 14).fontWeight(.semibold)
                    .background(Color.white.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }.disabled(!store.canOpenInX)

            Button { store.openInX() } label: {
                HStack { Image(systemName: "arrow.up.right.square.fill"); Text("Open in X") }
                    .frame(maxWidth: .infinity).padding(.vertical, 15).fontWeight(.bold).foregroundStyle(.white)
                    .background(LinearGradient(colors: [Color(red: 0.08, green: 0.42, blue: 0.98), Color.purple], startPoint: .leading, endPoint: .trailing))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }.disabled(!store.canOpenInX).opacity(store.canOpenInX ? 1 : 0.5)

            if store.selectedArticle != nil {
                Button { store.openArticle() } label: { Label("View Source Article", systemImage: "safari").font(.subheadline.weight(.semibold)) }
            }
        }.buttonStyle(.plain)
    }

    private var adBanner: some View {
        VStack(spacing: 2) {
            Text("ADVERTISEMENT").font(.system(size: 8, weight: .medium)).foregroundStyle(.tertiary)
            LevelPlayBannerView().frame(maxWidth: .infinity).frame(height: 58)
        }.padding(.top, 3).background(Color.black.opacity(0.96))
    }

    private var sourceFooter: some View {
        VStack(spacing: 7) {
            HStack(spacing: 6) {
                Circle().fill(store.statusText.contains("Connected") || store.statusText.contains("Refreshed") ? Color.green : Color.blue).frame(width: 7, height: 7)
                Text(store.statusText).font(.caption).foregroundStyle(.secondary)
            }
            Text("Source: https://nextjailbreak.com • Cycle \(store.cycleNumber)").font(.caption2).foregroundStyle(.tertiary)
        }.frame(maxWidth: .infinity)
    }

    private var panelBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.055))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.white.opacity(0.10), lineWidth: 1))
    }
}

#Preview { ContentView().preferredColorScheme(.dark) }
