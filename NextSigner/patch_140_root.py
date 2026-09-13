from pathlib import Path

path = Path('NextSigner/NextSigner/NextSignerRootView.swift')
text = path.read_text(encoding='utf-8')
old = '''struct NextSignerRootView: View {
    @StateObject private var store = SignerStore()

    var body: some View {
        TabView {
            NextSignerManualSignView(store: store)
                .tabItem { Label("Sign", systemImage: "signature") }

            NextSignerLibraryView(store: store)
                .tabItem { Label("Library", systemImage: "square.stack.3d.up.fill") }

            NextSignerActivityView(store: store)
                .tabItem { Label("Activity", systemImage: "clock.arrow.circlepath") }

            SigningProfileView(store: store)
                .tabItem { Label("Profiles", systemImage: "checkmark.seal.fill") }

            NextSignerSettingsPlusView(store: store)
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .tint(.accentColor)
    }
}
'''
new = '''struct NextSignerRootView: View {
    @StateObject private var store = SignerStore()
    @StateObject private var local = LocalSigningController()

    var body: some View {
        TabView {
            NextSignerLocalSignView(store: store, local: local)
                .tabItem { Label("Sign", systemImage: "signature") }

            NextSignerSignedAppsView(store: store, local: local)
                .tabItem { Label("Signed Apps", systemImage: "checkmark.seal.fill") }

            NextSignerLibraryView(store: store)
                .tabItem { Label("Library", systemImage: "square.stack.3d.up.fill") }

            NextSignerActivityView(store: store)
                .tabItem { Label("Activity", systemImage: "clock.arrow.circlepath") }

            NextSignerLocalProfileView(local: local)
                .tabItem { Label("Profiles", systemImage: "person.badge.key.fill") }

            NextSignerLocalSettingsView(store: store, local: local)
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .tint(.accentColor)
    }
}
'''
if old not in text:
    raise SystemExit('Expected NextSignerRootView block not found')
path.write_text(text.replace(old, new, 1), encoding='utf-8')
print('NextSignerRootView patched for local signing and Signed Apps')
