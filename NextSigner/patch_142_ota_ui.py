from pathlib import Path

path = Path('NextSigner/NextSigner/NextSignerLocalViews.swift')
text = path.read_text()

old_install = '''                Button {
                    if let url = local.trollStoreInstallURL(for: app) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Label("Install", systemImage: "arrow.down.app.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
'''
new_install = '''                Button {
                    local.install(app, using: store)
                } label: {
                    Label("Install", systemImage: "arrow.down.app.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(local.installingID != nil || local.publishingID != nil)
'''
if old_install in text:
    text = text.replace(old_install, new_install, 1)
elif new_install not in text:
    raise SystemExit('Install button pattern not found')

old_progress = '''            if local.publishingID == app.id {
                ProgressView(value: local.publishProgress)
                Text("Publishing signed IPA to site…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
'''
new_progress = '''            if local.installingID == app.id {
                ProgressView()
                Text(local.installMessage ?? "Preparing Apple OTA installation…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if local.publishingID == app.id {
                ProgressView(value: local.publishProgress)
                Text("Publishing signed IPA to site…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
'''
if new_progress not in text:
    if old_progress not in text:
        raise SystemExit('Progress pattern not found')
    text = text.replace(old_progress, new_progress, 1)

if '.disabled(local.publishingID != nil || local.installingID != nil)\n' not in text:
    text = text.replace(
        '.disabled(local.publishingID != nil)\n',
        '.disabled(local.publishingID != nil || local.installingID != nil)\n',
        1
    )
if '.disabled(local.publishingID == app.id || local.installingID == app.id)\n' not in text:
    text = text.replace(
        '.disabled(local.publishingID == app.id)\n',
        '.disabled(local.publishingID == app.id || local.installingID == app.id)\n',
        1
    )

old_note = 'Text("Install and Share use the local signed IPA. GitHub is contacted only if you press Publish.")'
new_note = 'Text("Install uses Apple OTA Ad Hoc installation. The already-signed IPA is staged temporarily over HTTPS and is not added to your site. Publish remains a separate manual action.")'
if old_note in text:
    text = text.replace(old_note, new_note, 1)
elif new_note not in text:
    raise SystemExit('Install note pattern not found')

path.write_text(text)
print('NextSignerLocalViews.swift is patched for Apple OTA install.')
