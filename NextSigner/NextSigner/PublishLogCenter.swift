import SwiftUI
import UIKit

struct PublishStatusPayload: Decodable, Equatable {
    let requestID: String
    let state: String
    let stage: String
    let message: String
    let runURL: String?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case requestID = "request_id"
        case state
        case stage
        case message
        case runURL = "run_url"
        case updatedAt = "updated_at"
    }
}

struct PublishLogEntry: Identifiable, Equatable {
    enum Kind: Equatable {
        case info
        case success
        case failure
    }

    let id = UUID()
    let timestamp: Date
    let stage: String
    let message: String
    let kind: Kind

    init(stage: String, message: String, kind: Kind = .info, timestamp: Date = Date()) {
        self.timestamp = timestamp
        self.stage = stage
        self.message = message
        self.kind = kind
    }

    var timeText: String {
        Self.formatter.string(from: timestamp)
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}

@MainActor
final class PublishLogCenter: ObservableObject {
    static let shared = PublishLogCenter()

    @Published var entries: [PublishLogEntry] = []
    @Published var isVisible = false
    @Published var isExpanded = false
    @Published var isRunning = false
    @Published var headline = "Publish Log"
    @Published var latestRunURL: URL?

    private var lastBackendSignature: String?

    private init() {}

    func begin(appName: String, requestID: String) {
        entries = []
        lastBackendSignature = nil
        latestRunURL = nil
        isVisible = true
        isExpanded = false
        isRunning = true
        headline = "Publishing \(appName)"
        append(stage: "Prepare", message: "Publish request \(requestID.prefix(8)) created.")
    }

    func append(stage: String, message: String, kind: PublishLogEntry.Kind = .info) {
        guard !message.isEmpty else { return }
        entries.append(PublishLogEntry(stage: stage, message: message, kind: kind))
        if entries.count > 80 {
            entries.removeFirst(entries.count - 80)
        }
    }

    func apply(_ status: PublishStatusPayload) {
        let signature = "\(status.state)|\(status.stage)|\(status.message)"
        if signature == lastBackendSignature { return }
        lastBackendSignature = signature

        if let value = status.runURL, let url = URL(string: value) {
            latestRunURL = url
        }

        let kind: PublishLogEntry.Kind
        switch status.state.lowercased() {
        case "success": kind = .success
        case "failed", "failure": kind = .failure
        default: kind = .info
        }
        append(stage: status.stage, message: status.message, kind: kind)

        if kind == .success {
            isRunning = false
            headline = "Published Successfully"
        } else if kind == .failure {
            isRunning = false
            headline = "Publish Failed"
            isExpanded = true
        }
    }

    func fail(_ message: String) {
        isVisible = true
        isRunning = false
        isExpanded = true
        headline = "Publish Failed"
        append(stage: "Error", message: message, kind: .failure)
    }

    func finish(_ message: String) {
        isRunning = false
        headline = "Published Successfully"
        append(stage: "Complete", message: message, kind: .success)
    }

    func clear() {
        guard !isRunning else { return }
        entries = []
        latestRunURL = nil
        lastBackendSignature = nil
        isVisible = false
        isExpanded = false
        headline = "Publish Log"
    }

    func copyLog() {
        let text = entries.map { "[\($0.timeText)] \($0.stage): \($0.message)" }.joined(separator: "\n")
        UIPasteboard.general.string = text
    }
}

struct PublishLogMiniView: View {
    @ObservedObject var center: PublishLogCenter

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                statusIcon
                VStack(alignment: .leading, spacing: 1) {
                    Text(center.headline)
                        .font(.caption.bold())
                        .lineLimit(1)
                    if let last = center.entries.last {
                        Text(last.stage)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()

                Button {
                    center.copyLog()
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Copy publish log")

                if let runURL = center.latestRunURL {
                    Button {
                        UIApplication.shared.open(runURL)
                    } label: {
                        Image(systemName: "arrow.up.right.square")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open GitHub run")
                }

                Button {
                    center.isExpanded.toggle()
                } label: {
                    Image(systemName: center.isExpanded ? "chevron.down" : "chevron.up")
                }
                .buttonStyle(.plain)

                if !center.isRunning {
                    Button {
                        center.clear()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.plain)
                }
            }

            if center.isRunning {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 5) {
                        ForEach(center.entries) { entry in
                            HStack(alignment: .top, spacing: 6) {
                                Text(entry.timeText)
                                    .foregroundStyle(.secondary)
                                Text(entry.stage + ":")
                                    .fontWeight(.semibold)
                                Text(entry.message)
                                    .foregroundColor(entry.kind == .failure ? .red : .primary)
                                    .textSelection(.enabled)
                            }
                            .font(.system(size: 10, design: .monospaced))
                            .id(entry.id)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: center.isExpanded ? 210 : 82)
                .onChange(of: center.entries.count) { _ in
                    if let id = center.entries.last?.id {
                        proxy.scrollTo(id, anchor: .bottom)
                    }
                }
            }
        }
        .padding(12)
        .background(NSTheme.elevated.opacity(0.98), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.quaternary, lineWidth: 1)
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        if center.isRunning {
            ProgressView()
                .controlSize(.small)
        } else if center.headline.contains("Failed") {
            Image(systemName: "xmark.octagon.fill")
                .foregroundStyle(.red)
        } else {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        }
    }
}
