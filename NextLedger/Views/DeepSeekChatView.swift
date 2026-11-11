import SwiftUI

private enum AIChatMode: String, CaseIterable, Identifiable {
    case ledger = "Ledger Search"
    case deepSeek = "DeepSeek Chat"

    var id: String { rawValue }
}

private struct DeepSeekChatBubble: Identifiable, Codable {
    let id = UUID()
    let role: String
    let content: String
    var transactionIDs: [UUID] = []
}

struct DeepSeekChatView: View {
    @EnvironmentObject private var store: LedgerStore
    @AppStorage("DeepSeekModel") private var model = "deepseek-v4-flash"
    @AppStorage("AIChatMode") private var chatMode = AIChatMode.ledger.rawValue
    @State private var messages: [DeepSeekChatBubble] = DeepSeekChatHistory.load()
    @State private var draft = ""
    @State private var sending = false
    @State private var errorMessage: String?
    @State private var selectedTransaction: LedgerTransaction?

    var body: some View {
        VStack(spacing: 0) {
            Picker("Chat mode", selection: $chatMode) {
                ForEach(AIChatMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            if messages.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 38))
                        .foregroundStyle(AppTheme.purple)
                    Text(isLedgerMode ? "Search My Ledger" : "Ask DeepSeek")
                        .font(.title2.bold())
                    Text(isLedgerMode
                         ? "Ask for an amount, vendor, category, account, or date. Results stay on this iPhone and use no API tokens."
                         : "General AI chat does not receive your ledger data. Switch to Ledger Search to query transactions.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(30)
                Spacer()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(messages) { message in
                                chatBubble(message)
                                    .id(message.id)
                            }
                            if sending {
                                HStack {
                                    ProgressView()
                                    Text("DeepSeek is responding…")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                }
                                .padding(.horizontal)
                            }
                        }
                        .padding()
                    }
                    .onChange(of: messages.count) { _ in
                        if let id = messages.last?.id {
                            withAnimation { proxy.scrollTo(id, anchor: .bottom) }
                        }
                    }
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(AppTheme.red)
                    .padding(.horizontal)
                    .padding(.bottom, 6)
            }

            HStack(alignment: .bottom, spacing: 9) {
                TextField(isLedgerMode ? "Search transactions" : "Message DeepSeek", text: $draft, axis: .vertical)
                    .lineLimit(1...5)
                    .padding(11)
                    .background(AppTheme.page, in: RoundedRectangle(cornerRadius: 16))
                Button(action: send) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 31))
                }
                .disabled(cleanedDraft.isEmpty || sending || (!isLedgerMode && !DeepSeekService.shared.hasAPIKey))
            }
            .padding()
            .background(.ultraThinMaterial)
        }
        .navigationTitle("DeepSeek Chat")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Clear") {
                    messages = []
                    errorMessage = nil
                }
                .disabled(messages.isEmpty || sending)
            }
        }
        .sheet(item: $selectedTransaction) { transaction in
            TransactionSnapshotView(transaction: transaction)
                .environmentObject(store)
        }
        .onChange(of: messages.count) { _ in
            DeepSeekChatHistory.save(messages)
        }
        .overlay {
            if !DeepSeekService.shared.hasAPIKey && !isLedgerMode {
                VStack(spacing: 12) {
                    Image(systemName: "key.slash.fill")
                        .font(.system(size: 38))
                        .foregroundStyle(AppTheme.purple)
                    Text("DeepSeek Not Connected").font(.title2.bold())
                    Text("Save a DeepSeek API key in Settings first.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.regularMaterial)
            }
        }
    }

    private func chatBubble(_ message: DeepSeekChatBubble) -> some View {
        HStack {
            if message.role == "user" { Spacer(minLength: 42) }
            VStack(alignment: .leading, spacing: 9) {
                Text(message.content)
                    .textSelection(.enabled)
                ForEach(message.transactionIDs, id: \.self) { id in
                    if let transaction = store.transactions.first(where: { $0.id == id }) {
                        Button {
                            selectedTransaction = transaction
                        } label: {
                            Label("Open \(transaction.vendor?.isEmpty == false ? transaction.vendor! : transaction.category) transaction", systemImage: "arrow.up.right.square")
                                .font(.caption.bold())
                                .lineLimit(1)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .padding(12)
            .foregroundStyle(message.role == "user" ? .white : .primary)
            .background(
                message.role == "user" ? AppTheme.purple : Color(uiColor: .secondarySystemBackground),
                in: RoundedRectangle(cornerRadius: 17, style: .continuous)
            )
            if message.role != "user" { Spacer(minLength: 42) }
        }
    }

    private var cleanedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isLedgerMode: Bool {
        chatMode == AIChatMode.ledger.rawValue
    }

    private func send() {
        let text = cleanedDraft
        guard !text.isEmpty else { return }
        draft = ""
        errorMessage = nil
        messages.append(DeepSeekChatBubble(role: "user", content: text))

        if isLedgerMode {
            let result = LedgerChatSearch.run(query: text, store: store, force: true)
            messages.append(DeepSeekChatBubble(
                role: "assistant",
                content: result.response,
                transactionIDs: result.transactionIDs
            ))
            return
        }
        guard DeepSeekService.shared.hasAPIKey else {
            errorMessage = "Connect DeepSeek in Settings first."
            return
        }
        sending = true

        let recent = messages.suffix(8).map {
            DeepSeekMessage(role: $0.role, content: $0.content)
        }
        let requestMessages = [
            DeepSeekMessage(
                role: "system",
                content: "You are a concise, helpful general assistant inside Next Ledger. Keep responses practical and under 500 words. Do not claim access to ledger data unless the user includes it in this chat."
            )
        ] + recent

        Task {
            do {
                let response = try await DeepSeekService.shared.request(
                    messages: requestMessages,
                    model: model,
                    maxTokens: 500
                )
                await MainActor.run {
                    messages.append(DeepSeekChatBubble(role: "assistant", content: response))
                    sending = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    sending = false
                }
            }
        }
    }
}

private enum DeepSeekChatHistory {
    private static let key = "DeepSeekPersistentChatHistory"

    static func load() -> [DeepSeekChatBubble] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let messages = try? JSONDecoder().decode([DeepSeekChatBubble].self, from: data) else { return [] }
        return messages
    }

    static func save(_ messages: [DeepSeekChatBubble]) {
        let limited = Array(messages.suffix(100))
        UserDefaults.standard.set(try? JSONEncoder().encode(limited), forKey: key)
    }
}
