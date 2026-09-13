from pathlib import Path

path = Path('NextSigner/NextSigner/NextSignerRootView.swift')
text = path.read_text(encoding='utf-8')
replacements = {
    'NextSignerSignView(store: store)\n                .tabItem { Label("Publish", systemImage: "paperplane.fill") }':
    'NextSignerManualSignView(store: store)\n                .tabItem { Label("Sign", systemImage: "signature") }',
    'NextSignerSettingsView(store: store)\n                .tabItem { Label("Settings", systemImage: "gearshape") }':
    'NextSignerSettingsPlusView(store: store)\n                .tabItem { Label("Settings", systemImage: "gearshape") }',
}
for old, new in replacements.items():
    if old not in text:
        raise SystemExit(f'Expected text not found: {old!r}')
    text = text.replace(old, new, 1)
path.write_text(text, encoding='utf-8')
print('NextSignerRootView patched for sign-first and backup UI')
