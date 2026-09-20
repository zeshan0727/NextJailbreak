import SwiftUI
import UIKit

enum NATheme {
    static let cyan = Color(red: 0.03, green: 0.82, blue: 1.00)
    static let blue = Color(red: 0.12, green: 0.35, blue: 1.00)
    static let violet = Color(red: 0.50, green: 0.24, blue: 1.00)
    static let green = Color(red: 0.15, green: 0.92, blue: 0.54)
    static let pink = Color(red: 1.00, green: 0.23, blue: 0.62)
    static let orange = Color(red: 1.00, green: 0.62, blue: 0.13)
    static let panel = Color.white.opacity(0.075)
    static let stroke = Color.white.opacity(0.12)
    static let secondary = Color.white.opacity(0.62)
    static let background = LinearGradient(
        colors: [
            Color(red: 0.015, green: 0.025, blue: 0.055),
            Color(red: 0.015, green: 0.055, blue: 0.105),
            Color.black
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let accent = LinearGradient(colors: [cyan, blue, violet], startPoint: .topLeading, endPoint: .bottomTrailing)
}

struct NAAppBackground: View {
    var body: some View {
        ZStack {
            NATheme.background.ignoresSafeArea()
            Circle()
                .fill(NATheme.cyan.opacity(0.12))
                .frame(width: 320, height: 320)
                .blur(radius: 75)
                .offset(x: -180, y: -330)
            Circle()
                .fill(NATheme.violet.opacity(0.12))
                .frame(width: 300, height: 300)
                .blur(radius: 80)
                .offset(x: 190, y: -230)
        }
    }
}

struct NANextMark: View {
    var size: CGFloat = 42
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
                .fill(Color.black.opacity(0.72))
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
                        .stroke(NATheme.accent, lineWidth: max(1, size * 0.035))
                )
                .shadow(color: NATheme.cyan.opacity(0.35), radius: size * 0.22)

            Text("N")
                .font(.system(size: size * 0.62, weight: .black, design: .rounded))
                .foregroundStyle(NATheme.accent)
        }
        .frame(width: size, height: size)
    }
}

struct NAGlassCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(NATheme.panel)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(NATheme.stroke, lineWidth: 1)
                    )
            )
    }
}

struct NAStatusPill: View {
    let title: String
    let color: Color
    let systemImage: String
    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
            Text(title)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(color)
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(color.opacity(0.11), in: Capsule())
        .overlay(Capsule().stroke(color.opacity(0.25), lineWidth: 1))
    }
}

struct ModernRootView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            NAAppBackground()
            TabView {
                ModernAgentView()
                    .tabItem { Label("Agent", systemImage: "sparkles") }
                ModernToolsView()
                    .tabItem { Label("Tools", systemImage: "wrench.and.screwdriver.fill") }
                ModernFilesView()
                    .tabItem { Label("Files", systemImage: "folder.fill") }
                ModernSettingsView()
                    .tabItem { Label("Settings", systemImage: "gearshape.fill") }
            }
            .tint(NATheme.cyan)
        }
        .preferredColorScheme(.dark)
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                Task { await state.handleBecameActive() }
            } else if phase == .background && state.busy {
                state.backgroundState = BackgroundKeepAlive.shared.active ? "Extended background" : "Background"
            }
        }
    }
}

struct ModernAgentView: View {
    @EnvironmentObject var state: AppState
    @FocusState private var composerFocused: Bool

    private var helperConnected: Bool {
        state.rootHelperStatus.localizedCaseInsensitiveContains("Connected")
    }

    private func run(_ prompt: String) {
        guard !state.busy else { return }
        state.input = prompt
        Task { await state.send() }
    }

    private func copy(_ value: String) {
        UIPasteboard.general.string = value
        state.status = "Copied"
    }

    private func paste() {
        guard let value = UIPasteboard.general.string, !value.isEmpty else { return }
        if state.input.isEmpty { state.input = value }
        else { state.input += "\n" + value }
        composerFocused = true
    }

    private func messageText(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 18) {
                            hero
                            rootCard
                            quickActions

                            if state.messages.count > 1 {
                                HStack {
                                    Text("CONVERSATION")
                                        .font(.caption2.weight(.bold))
                                        .tracking(1.6)
                                        .foregroundStyle(NATheme.secondary)
                                    Spacer()
                                    if state.busy {
                                        ProgressView().tint(NATheme.cyan)
                                    }
                                }
                                .padding(.top, 4)
                            }

                            ForEach(state.messages) { message in
                                messageBubble(message)
                                    .id(message.id)
                            }
                        }
                        .padding(.horizontal, 18)
                        .padding(.top, 16)
                        .padding(.bottom, 16)
                    }
                    .onChange(of: state.messages.count) { _ in
                        guard let last = state.messages.last else { return }
                        withAnimation(.easeOut(duration: 0.25)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }

                composer
            }
            .background(Color.clear)
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var hero: some View {
        HStack(spacing: 13) {
            NANextMark(size: 48)
            VStack(alignment: .leading, spacing: 3) {
                Text("Next Agent")
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                Text("Your iPhone. No Limits.")
                    .font(.subheadline)
                    .foregroundStyle(NATheme.secondary)
            }
            Spacer()
            NAStatusPill(
                title: state.busy ? "Working" : "Ready",
                color: state.busy ? NATheme.orange : NATheme.green,
                systemImage: state.busy ? "bolt.horizontal.fill" : "checkmark.circle.fill"
            )
        }
    }

    private var rootCard: some View {
        Button {
            state.checkRootHelper()
        } label: {
            NAGlassCard {
                VStack(spacing: 13) {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle().fill((helperConnected ? NATheme.green : NATheme.orange).opacity(0.17))
                            Circle().fill(helperConnected ? NATheme.green : NATheme.orange)
                                .frame(width: 12, height: 12)
                                .shadow(color: helperConnected ? NATheme.green : NATheme.orange, radius: 8)
                        }
                        .frame(width: 42, height: 42)

                        VStack(alignment: .leading, spacing: 3) {
                            Text("Root Helper")
                                .font(.headline)
                            Text(helperConnected ? "Connected & Running" : "Tap to verify connection")
                                .font(.subheadline)
                                .foregroundStyle(helperConnected ? NATheme.green : NATheme.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(NATheme.secondary)
                    }

                    HStack(spacing: 0) {
                        metric("Agent", "Astra")
                        Divider().overlay(Color.white.opacity(0.10))
                        metric("Root", helperConnected ? "Active" : "Check")
                        Divider().overlay(Color.white.opacity(0.10))
                        metric("Background", state.backgroundState)
                    }
                    .frame(height: 45)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.caption.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Text(label)
                .font(.caption2)
                .foregroundStyle(NATheme.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("QUICK ACTIONS")
                    .font(.caption2.weight(.bold))
                    .tracking(1.6)
                    .foregroundStyle(NATheme.secondary)
                Spacer()
                Text(state.lastTool == "None" ? "Power tools" : "Last: \(state.lastTool)")
                    .font(.caption2)
                    .foregroundStyle(NATheme.cyan)
                    .lineLimit(1)
            }

            HStack(spacing: 10) {
                actionTile("Device", "cpu", NATheme.cyan) {
                    run("Give me a compact device and RootHide status summary. Do not modify anything.")
                }
                actionTile("Processes", "waveform.path.ecg", NATheme.pink) {
                    run("Show running processes as root and identify launchd, SpringBoard, backboardd and nextagentd.")
                }
                actionTile("Storage", "externaldrive.fill", NATheme.green) {
                    run("Show system and user storage usage and free space.")
                }
                actionTile("Apps", "square.grid.2x2.fill", NATheme.violet) {
                    run("List installed apps with names and bundle identifiers.")
                }
            }
        }
    }

    private func actionTile(_ title: String, _ icon: String, _ color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 9) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(color.opacity(0.15))
                    Image(systemName: icon)
                        .foregroundStyle(color)
                }
                .frame(width: 35, height: 35)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(NATheme.panel, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous).stroke(NATheme.stroke))
        }
        .buttonStyle(.plain)
    }

    private func messageBubble(_ message: ChatMessage) -> some View {
        HStack(alignment: .bottom) {
            if message.role == "assistant" {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        NANextMark(size: 25)
                        Text("NEXT AGENT")
                            .font(.caption2.weight(.bold))
                            .tracking(1.3)
                            .foregroundStyle(NATheme.cyan)
                    }
                    Text(messageText(message.text))
                        .font(.body)
                        .textSelection(.enabled)
                    HStack {
                        Button {
                            copy(message.text)
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                        }
                        .buttonStyle(.plain)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(NATheme.secondary)
                        Spacer()
                    }
                }
                .padding(14)
                .background(NATheme.panel, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(NATheme.stroke))
                .contextMenu {
                    Button("Copy response") { copy(message.text) }
                }
                Spacer(minLength: 26)
            } else {
                Spacer(minLength: 42)
                Text(message.text)
                    .font(.body)
                    .textSelection(.enabled)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .foregroundStyle(.white)
                    .background(NATheme.accent, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
                    .contextMenu {
                        Button("Copy prompt") { copy(message.text) }
                    }
            }
        }
    }

    private var composer: some View {
        VStack(spacing: 8) {
            if state.busy || state.backgroundState != "Idle" {
                HStack(spacing: 8) {
                    if state.busy { ProgressView().tint(NATheme.cyan).scaleEffect(0.8) }
                    Text(state.busy ? state.status : state.backgroundState)
                        .font(.caption)
                        .foregroundStyle(NATheme.secondary)
                    Spacer()
                }
                .padding(.horizontal, 20)
            }

            HStack(alignment: .bottom, spacing: 9) {
                Button(action: paste) {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 39, height: 39)
                        .background(NATheme.panel, in: Circle())
                        .overlay(Circle().stroke(NATheme.stroke))
                }
                .buttonStyle(.plain)

                TextField("Ask Next Agent anything…", text: $state.input, axis: .vertical)
                    .focused($composerFocused)
                    .lineLimit(1...5)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 11)
                    .background(NATheme.panel, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 19, style: .continuous).stroke(NATheme.stroke))

                Button {
                    Task { await state.send() }
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(
                            Circle().fill(
                                state.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || state.busy
                                    ? AnyShapeStyle(Color.gray.opacity(0.35))
                                    : AnyShapeStyle(NATheme.accent)
                            )
                        )
                }
                .buttonStyle(.plain)
                .disabled(state.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || state.busy)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 9)
        }
        .padding(.top, 8)
        .background(.ultraThinMaterial)
    }
}

private struct NAToolItem: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let prompt: String
}

struct ModernToolsView: View {
    @EnvironmentObject var state: AppState

    private let tools: [NAToolItem] = [
        .init(title: "Touch Control", subtitle: "Tap, press & swipe", icon: "hand.tap.fill", color: NATheme.cyan, prompt: "Check HID status and tell me whether global tap, swipe and keyboard injection are ready. Do not perform an input action yet."),
        .init(title: "Text Input", subtitle: "Type into focused fields", icon: "keyboard.fill", color: NATheme.violet, prompt: "Check whether text input control is ready. Do not type anything yet."),
        .init(title: "UI Automation", subtitle: "Run local action sequences", icon: "point.3.connected.trianglepath.dotted", color: NATheme.blue, prompt: "Explain the UI automation tools currently available on this iPhone in a compact bullet list."),
        .init(title: "Device Info", subtitle: "Hardware, iOS & jailbreak", icon: "cpu.fill", color: NATheme.cyan, prompt: "Show device information and jailbreak status. Do not modify anything."),
        .init(title: "Processes", subtitle: "Root process table", icon: "waveform.path.ecg", color: NATheme.pink, prompt: "Show the current root process list and identify major iOS services."),
        .init(title: "Storage", subtitle: "Capacity & free space", icon: "externaldrive.fill", color: NATheme.green, prompt: "Show filesystem capacity and free space."),
        .init(title: "Installed Apps", subtitle: "Inspect applications", icon: "square.grid.2x2.fill", color: NATheme.violet, prompt: "List installed applications with bundle identifiers."),
        .init(title: "File Tools", subtitle: "Browse, copy & move", icon: "folder.fill", color: NATheme.orange, prompt: "Summarize the file-management tools available to you. Do not change any files."),
        .init(title: "Packages", subtitle: "RootHide package database", icon: "shippingbox.fill", color: NATheme.violet, prompt: "List installed RootHide packages and versions, compactly."),
        .init(title: "Network", subtitle: "Interfaces & addresses", icon: "network", color: NATheme.cyan, prompt: "Show local network interfaces and addresses. Do not contact external services."),
        .init(title: "Clipboard", subtitle: "Read & replace text", icon: "doc.on.clipboard.fill", color: NATheme.blue, prompt: "Tell me what clipboard tools are available. Do not change the clipboard."),
        .init(title: "System", subtitle: "Root helper & services", icon: "gearshape.2.fill", color: NATheme.green, prompt: "Check root helper health and summarize available system-control tools. Do not modify anything.")
    ]

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Tools")
                                .font(.system(size: 33, weight: .bold, design: .rounded))
                            Text("Powerful utilities for your device.")
                                .foregroundStyle(NATheme.secondary)
                        }
                        Spacer()
                        NANextMark(size: 43)
                    }

                    HStack(spacing: 8) {
                        NAStatusPill(title: "RootHide", color: NATheme.cyan, systemImage: "shield.fill")
                        NAStatusPill(title: state.sensitiveActions ? "Control ON" : "Read-only", color: state.sensitiveActions ? NATheme.orange : NATheme.green, systemImage: state.sensitiveActions ? "hand.tap.fill" : "eye.fill")
                    }

                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(tools) { tool in
                            Button {
                                state.input = tool.prompt
                                Task { await state.send() }
                            } label: {
                                VStack(alignment: .leading, spacing: 12) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                                            .fill(tool.color.opacity(0.14))
                                        Image(systemName: tool.icon)
                                            .font(.system(size: 21, weight: .semibold))
                                            .foregroundStyle(tool.color)
                                    }
                                    .frame(width: 44, height: 44)

                                    Text(tool.title)
                                        .font(.headline)
                                        .foregroundStyle(.white)
                                    Text(tool.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(NATheme.secondary)
                                        .multilineTextAlignment(.leading)
                                        .lineLimit(2)
                                    Spacer(minLength: 0)
                                    HStack {
                                        Text("Open")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(tool.color)
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(NATheme.secondary)
                                    }
                                }
                                .padding(14)
                                .frame(maxWidth: .infinity, minHeight: 164, alignment: .topLeading)
                                .background(NATheme.panel, in: RoundedRectangle(cornerRadius: 21, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 21, style: .continuous).stroke(NATheme.stroke))
                            }
                            .buttonStyle(.plain)
                            .disabled(state.busy)
                        }
                    }
                }
                .padding(18)
            }
            .background(Color.clear)
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

private struct NAFileItem: Identifiable {
    let id = UUID()
    let name: String
    let directory: Bool
    let size: Int64
}

struct ModernFilesView: View {
    @State private var path = "/var/mobile"
    @State private var items: [NAFileItem] = []
    @State private var status = "Ready"
    @State private var selectedText: String?
    @State private var selectedName = ""
    @State private var loading = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Files")
                            .font(.system(size: 33, weight: .bold, design: .rounded))
                        Text("Root-aware file browser.")
                            .foregroundStyle(NATheme.secondary)
                    }
                    Spacer()
                    NANextMark(size: 43)
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)

                HStack(spacing: 9) {
                    Button {
                        goParent()
                    } label: {
                        Image(systemName: "chevron.left")
                            .frame(width: 34, height: 34)
                            .background(NATheme.panel, in: Circle())
                    }
                    .buttonStyle(.plain)

                    HStack {
                        Image(systemName: "folder.fill").foregroundStyle(NATheme.cyan)
                        Text(path)
                            .font(.caption.monospaced())
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button { load() } label: { Image(systemName: "arrow.clockwise") }
                            .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 13)
                    .frame(height: 42)
                    .background(NATheme.panel, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(NATheme.stroke))
                }
                .padding(.horizontal, 18)

                if loading {
                    Spacer()
                    ProgressView("Reading \(path)…").tint(NATheme.cyan)
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(items) { item in
                                Button {
                                    open(item)
                                } label: {
                                    HStack(spacing: 12) {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                                .fill((item.directory ? NATheme.cyan : NATheme.violet).opacity(0.12))
                                            Image(systemName: item.directory ? "folder.fill" : "doc.fill")
                                                .foregroundStyle(item.directory ? NATheme.cyan : NATheme.violet)
                                        }
                                        .frame(width: 40, height: 40)

                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(item.name)
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(.white)
                                                .lineLimit(1)
                                            Text(item.directory ? "Directory" : ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file))
                                                .font(.caption)
                                                .foregroundStyle(NATheme.secondary)
                                        }
                                        Spacer()
                                        Image(systemName: item.directory ? "chevron.right" : "doc.text.magnifyingglass")
                                            .foregroundStyle(NATheme.secondary)
                                    }
                                    .padding(11)
                                    .background(NATheme.panel, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous).stroke(NATheme.stroke))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 18)
                        .padding(.bottom, 20)
                    }
                }

                if !status.isEmpty {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(NATheme.secondary)
                        .lineLimit(2)
                        .padding(.horizontal, 18)
                }
            }
            .background(Color.clear)
            .toolbar(.hidden, for: .navigationBar)
            .task { load() }
            .sheet(isPresented: Binding(get: { selectedText != nil }, set: { if !$0 { selectedText = nil } })) {
                NavigationStack {
                    ScrollView {
                        Text(selectedText ?? "")
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                    .background(Color.black)
                    .navigationTitle(selectedName)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Copy") { UIPasteboard.general.string = selectedText }
                        }
                    }
                    .preferredColorScheme(.dark)
                }
            }
        }
    }

    private func normalizedChild(_ name: String) -> String {
        if path == "/" { return "/" + name }
        return path + "/" + name
    }

    private func load() {
        loading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let result = RootDaemonClient.request(action: "list", argument: path)
            var parsed: [NAFileItem] = []
            var message = result.success ? "Loaded" : result.output
            if result.success,
               let data = result.output.data(using: .utf8),
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let rawItems = object["items"] as? [[String: Any]] {
                parsed = rawItems.compactMap { row in
                    guard let name = row["name"] as? String else { return nil }
                    let directory = row["directory"] as? Bool ?? false
                    let size = (row["size"] as? NSNumber)?.int64Value ?? 0
                    return NAFileItem(name: name, directory: directory, size: size)
                }
                .sorted {
                    if $0.directory != $1.directory { return $0.directory && !$1.directory }
                    return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
                message = "\(parsed.count) items"
            }
            DispatchQueue.main.async {
                items = parsed
                status = message
                loading = false
            }
        }
    }

    private func open(_ item: NAFileItem) {
        let target = normalizedChild(item.name)
        if item.directory {
            path = target
            load()
            return
        }

        loading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let result = RootDaemonClient.request(action: "read", argument: target)
            DispatchQueue.main.async {
                loading = false
                if result.success {
                    selectedName = item.name
                    selectedText = result.output
                    status = "Read \(item.name)"
                } else {
                    status = result.output
                }
            }
        }
    }

    private func goParent() {
        guard path != "/" else { return }
        var components = path.split(separator: "/").map(String.init)
        guard !components.isEmpty else { return }
        components.removeLast()
        path = components.isEmpty ? "/" : "/" + components.joined(separator: "/")
        load()
    }
}

struct ModernSettingsView: View {
    @EnvironmentObject var state: AppState
    @State private var showAPIKey = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Settings")
                                .font(.system(size: 33, weight: .bold, design: .rounded))
                            Text("Tailored to your workflow.")
                                .foregroundStyle(NATheme.secondary)
                        }
                        Spacer()
                        NANextMark(size: 43)
                    }

                    settingsSection("CONNECTION") {
                        settingRow("Root Helper", detail: state.rootHelperStatus, icon: "bolt.shield.fill", color: NATheme.green) {
                            state.checkRootHelper()
                        }

                        Toggle(isOn: $state.backgroundContinuation) {
                            label("Extended Background", detail: "Continue active automation while another app is foregrounded", icon: "infinity", color: NATheme.blue)
                        }
                        .tint(NATheme.cyan)
                        .onChange(of: state.backgroundContinuation) { value in
                            UserDefaults.standard.set(value, forKey: "nextagent.backgroundContinuation")
                        }
                    }

                    settingsSection("DEVICE CONTROL") {
                        Toggle(isOn: $state.sensitiveActions) {
                            label("Allow Sensitive Actions", detail: "Required for tap, swipe, typing and state changes", icon: "hand.tap.fill", color: NATheme.orange)
                        }
                        .tint(NATheme.orange)
                        .onChange(of: state.sensitiveActions) { value in
                            UserDefaults.standard.set(value, forKey: "nextagent.sensitiveActions")
                        }

                        Button {
                            state.input = "Check HID status and verify whether tap, swipe, key press and text entry are ready. Do not perform an input action."
                            Task { await state.send() }
                        } label: {
                            label("Test Interaction Engine", detail: "Read-only readiness check", icon: "cursorarrow.rays", color: NATheme.cyan)
                        }
                        .buttonStyle(.plain)
                    }

                    settingsSection("OPENAI AGENT") {
                        HStack {
                            Group {
                                if showAPIKey {
                                    TextField("Project API key", text: $state.apiKeyDraft)
                                } else {
                                    SecureField("Project API key", text: $state.apiKeyDraft)
                                }
                            }
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()

                            Button { showAPIKey.toggle() } label: {
                                Image(systemName: showAPIKey ? "eye.slash" : "eye")
                                    .foregroundStyle(NATheme.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(12)
                        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                        HStack {
                            Button("Save Key") {
                                state.saveSettings()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(NATheme.blue)

                            Button("Verify Astra") {
                                Task { await state.createOrRepairAgent() }
                            }
                            .buttonStyle(.bordered)
                            .tint(NATheme.cyan)
                        }
                    }

                    settingsSection("SECURITY") {
                        label("Protected Data", detail: "Credential stores, passwords, authentication tokens and private communications remain blocked from root file tools.", icon: "lock.shield.fill", color: NATheme.green)
                        label("Action Guard", detail: "State-changing interaction tools require Sensitive Actions and consequential actions require your explicit instruction.", icon: "checkmark.shield.fill", color: NATheme.cyan)
                    }

                    settingsSection("ABOUT") {
                        HStack(spacing: 12) {
                            NANextMark(size: 38)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Next Agent").font(.headline)
                                Text("Production 0.5.0 • RootHide • GPT-6 Astra")
                                    .font(.caption)
                                    .foregroundStyle(NATheme.secondary)
                            }
                            Spacer()
                        }
                    }
                }
                .padding(18)
                .padding(.bottom, 24)
            }
            .background(Color.clear)
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.caption2.weight(.bold))
                .tracking(1.6)
                .foregroundStyle(NATheme.secondary)
                .padding(.leading, 3)
            NAGlassCard {
                VStack(alignment: .leading, spacing: 16) {
                    content()
                }
            }
        }
    }

    private func label(_ title: String, detail: String, icon: String, color: Color) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(color.opacity(0.14))
                Image(systemName: icon)
                    .foregroundStyle(color)
            }
            .frame(width: 39, height: 39)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(NATheme.secondary)
                    .lineLimit(3)
            }
            Spacer()
        }
    }

    private func settingRow(_ title: String, detail: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            label(title, detail: detail, icon: icon, color: color)
        }
        .buttonStyle(.plain)
    }
}
