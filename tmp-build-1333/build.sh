#!/bin/bash
set -euo pipefail
R="$RUNNER_TEMP"
rm -rf "$R/appsrc" "$R/nqrsrc" "$R/out" "$R/DD" "$R/iconvenv" "$R/theos-rh"
mkdir -p "$R/out"

# Reconstruct exact 1.3.30 app source without compiling it.
awk '/^ASSETS=/{exit} {print}' tmp-build-1330/build.sh > "$R/reconstruct-app1330.sh"
bash "$R/reconstruct-app1330.sh"
P="$R/appsrc"
FILES_SHA=$(shasum -a 256 "$P/NextReminder/Sources/FileSharing.swift" | awk '{print $1}')

# Apply 1.3.32: Gmail persistence/recovery + missed-reminder daily fallback.
python3 - <<'PYAPP'
from pathlib import Path
import os,re
root=Path(os.environ['RUNNER_TEMP'])/'appsrc'

# Gmail connection record: Keychain primary, UserDefaults mirror.
p=root/'NextReminder/Sources/GmailConnection.swift'
s=p.read_text()
marker='''struct GmailConnectionRecord: Codable, Equatable {
    var connectorID: String
    var emailAddress: String
    var connectedAt: Date
}
'''
insert='''
private enum GmailConnectionRecordKeychain {
    private static let service = "com.nextsolution.nextreminder.gmail-connection-record"
    private static let account = "primary"

    static func save(_ record: GmailConnectionRecord) {
        guard let data = try? JSONEncoder().encode(record) else { return }
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        var query = base
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        query[kSecValueData as String] = data
        SecItemAdd(query as CFDictionary, nil)
    }

    static func load() -> GmailConnectionRecord? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(GmailConnectionRecord.self, from: data)
    }

    static func remove() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
'''
if 'GmailConnectionRecordKeychain' not in s:
    if marker not in s: raise SystemExit('Gmail record marker missing')
    s=s.replace(marker,marker+insert,1)

old='''    func load() -> GmailConnectionRecord? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(GmailConnectionRecord.self, from: data)
    }

    func save(_ record: GmailConnectionRecord) {
        guard let data = try? JSONEncoder().encode(record) else { return }
        UserDefaults.standard.set(data, forKey: key)
        UserDefaults.standard.removeObject(forKey: manualDisconnectKey)
        GmailConnectionIssueStore.shared.clear()
        Task { await GmailConnectionAlertManager.shared.clearAlert() }
    }

    func clear() {
        UserDefaults.standard.removeObject(forKey: key)
        UserDefaults.standard.set(true, forKey: manualDisconnectKey)
        GmailConnectionIssueStore.shared.clear()
        Task { await GmailConnectionAlertManager.shared.clearAlert() }
    }
'''
new='''    func load() -> GmailConnectionRecord? {
        if let secure = GmailConnectionRecordKeychain.load() {
            if let data = try? JSONEncoder().encode(secure) {
                UserDefaults.standard.set(data, forKey: key)
            }
            return secure
        }
        guard let data = UserDefaults.standard.data(forKey: key),
              let record = try? JSONDecoder().decode(GmailConnectionRecord.self, from: data) else { return nil }
        GmailConnectionRecordKeychain.save(record)
        return record
    }

    func save(_ record: GmailConnectionRecord) {
        guard let data = try? JSONEncoder().encode(record) else { return }
        UserDefaults.standard.set(data, forKey: key)
        GmailConnectionRecordKeychain.save(record)
        UserDefaults.standard.removeObject(forKey: manualDisconnectKey)
        GmailConnectionIssueStore.shared.clear()
        Task { await GmailConnectionAlertManager.shared.clearAlert() }
    }

    func clear() {
        UserDefaults.standard.removeObject(forKey: key)
        GmailConnectionRecordKeychain.remove()
        UserDefaults.standard.set(true, forKey: manualDisconnectKey)
        GmailConnectionIssueStore.shared.clear()
        Task { await GmailConnectionAlertManager.shared.clearAlert() }
    }
'''
if old not in s: raise SystemExit('Gmail store block missing')
s=s.replace(old,new,1)

old='''                do {
                    _ = try await GmailOAuthClient.shared.restoreConnection(
                        connectorID: record.connectorID
                    )
                    return
                } catch {
'''
new='''                do {
                    let restored = try await GmailOAuthClient.shared.restoreConnection(
                        connectorID: record.connectorID
                    )
                    GmailConnectionStore.shared.save(restored)
                    var settings = EmailAutomationSettings.load()
                    settings.remoteConnectorID = restored.connectorID
                    settings.senderLabel = restored.emailAddress
                    settings.persist()
                    NotificationCenter.default.post(name: .nextEmailAutomationSettingsChanged, object: nil)
                    return
                } catch {
'''
if old not in s: raise SystemExit('Health restore block missing')
s=s.replace(old,new,1)
p.write_text(s)

# Pending Report send: restore stale connector and retry once.
p=root/'NextReminder/Sources/PendingReports.swift'
s=p.read_text()
old='''        Task {
            defer { sendingID = nil }
            do {
                let message = try await PendingReportEmailService().send(
                    report: report,
                    recipient: destination,
                    gmail: gmail,
                    endpoint: endpoint,
                    apiKey: apiKey
                )
                statusMessage = "Sent successfully to \\(destination). \\(message)"
                gmailRecord = GmailConnectionStore.shared.load() ?? gmail
            } catch {
                errorMessage = error.localizedDescription
                statusMessage = "Send failed. The PDF remains saved locally."
                gmailRecord = GmailConnectionStore.shared.load() ?? gmail
            }
        }
'''
new='''        Task {
            defer { sendingID = nil }
            do {
                let message = try await PendingReportEmailService().send(
                    report: report,
                    recipient: destination,
                    gmail: gmail,
                    endpoint: endpoint,
                    apiKey: apiKey
                )
                statusMessage = "Sent successfully to \\(destination). \\(message)"
                gmailRecord = GmailConnectionStore.shared.load() ?? gmail
            } catch {
                let firstMessage = error.localizedDescription
                let connectorExpired: Bool
                if let reportError = error as? PendingReportEmailError {
                    if case .connectorExpired = reportError { connectorExpired = true } else { connectorExpired = false }
                } else {
                    connectorExpired = false
                }
                let shouldRecover = GmailConnectionStore.isDisconnectionMessage(firstMessage) || connectorExpired
                if shouldRecover {
                    do {
                        statusMessage = "Refreshing Gmail connection and retrying PDF…"
                        let restored = try await GmailOAuthClient.shared.restoreConnection(connectorID: gmail.connectorID)
                        GmailConnectionStore.shared.save(restored)
                        var settings = EmailAutomationSettings.load()
                        settings.remoteConnectorID = restored.connectorID
                        settings.senderLabel = restored.emailAddress
                        settings.persist()
                        NotificationCenter.default.post(name: .nextEmailAutomationSettingsChanged, object: nil)
                        let message = try await PendingReportEmailService().send(
                            report: report,
                            recipient: destination,
                            gmail: restored,
                            endpoint: endpoint,
                            apiKey: apiKey
                        )
                        statusMessage = "Sent successfully to \\(destination) after Gmail recovery. \\(message)"
                        gmailRecord = restored
                        return
                    } catch {
                        errorMessage = "Gmail recovery/send retry failed: \\(error.localizedDescription)"
                    }
                } else {
                    errorMessage = firstMessage
                }
                statusMessage = "Send failed. The PDF remains saved locally."
                gmailRecord = GmailConnectionStore.shared.load() ?? gmail
            }
        }
'''
if old not in s: raise SystemExit('Pending report send block missing')
s=s.replace(old,new,1)
s=s.replace('NextReminder-iOS/1.3.29.39','NextReminder-iOS/1.3.32.42')
p.write_text(s)

# App-side fallback: if app is opened after a reminder becomes overdue, install
# one repeating daily notification at the original clock time.
p=root/'NextReminder/Sources/Services.swift'
s=p.read_text()
needle='''            let identifier = requestIdentifier(reminderID: reminder.id, offset: offset.rawValue)
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
            try? await center.add(request)
        }
    }

    func scheduleSnooze'''
replacement='''            let identifier = requestIdentifier(reminderID: reminder.id, offset: offset.rawValue)
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
            try? await center.add(request)
        }

        if reminder.dueDate <= Date(), !reminder.isHourlyRoutine {
            let content = UNMutableNotificationContent()
            content.title = reminder.title
            content.subtitle = "Missed reminder • repeats daily"
            content.body = reminder.notes.isEmpty
                ? "This reminder is still incomplete. Mark it Completed to stop daily alerts."
                : reminder.notes
            content.sound = .default
            content.badge = 1
            content.categoryIdentifier = Self.categoryIdentifier
            content.threadIdentifier = categoryName
            content.interruptionLevel = .timeSensitive
            content.relevanceScore = 1.0
            content.userInfo = ["reminderID": reminder.id.uuidString, "missedDaily": true]

            var components = Calendar.current.dateComponents([.hour, .minute, .second], from: reminder.dueDate)
            if components.second == nil { components.second = 0 }
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            let identifier = "\\(reminder.id.uuidString)-missed-daily"
            try? await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
        }
    }

    func scheduleSnooze'''
if needle not in s: raise SystemExit('Notification schedule insertion point missing')
s=s.replace(needle,replacement,1)
p.write_text(s)

# Version bump.
pbx=root/'NextReminder.xcodeproj/project.pbxproj'
s=pbx.read_text()
s=re.sub(r'CURRENT_PROJECT_VERSION = 40;', 'CURRENT_PROJECT_VERSION = 42;', s)
s=re.sub(r'MARKETING_VERSION = 1\.3\.30;', 'MARKETING_VERSION = 1.3.32;', s)
pbx.write_text(s)
for rel in ['NextReminder/Resources/Info.plist','NextReminderLiveActivity/Info.plist']:
    q=root/rel
    if q.exists():
        t=q.read_text().replace('<string>1.3.30</string>','<string>1.3.32</string>').replace('<string>40</string>','<string>42</string>')
        q.write_text(t)
PYAPP

# Regression and feature guards.
test "$(shasum -a 256 "$P/NextReminder/Sources/FileSharing.swift" | awk '{print $1}')" = "$FILES_SHA"
grep -q 'GmailConnectionRecordKeychain' "$P/NextReminder/Sources/GmailConnection.swift"
grep -q 'GmailConnectionStore.shared.save(restored)' "$P/NextReminder/Sources/GmailConnection.swift"
grep -q 'Refreshing Gmail connection and retrying PDF' "$P/NextReminder/Sources/PendingReports.swift"
grep -q 'missed-daily' "$P/NextReminder/Sources/Services.swift"

# Build app using the already-proven 1.3.30 icon path.
ASSETS="$P/NextReminder/Resources/Assets.xcassets"
ICONSET="$ASSETS/AppIcon.appiconset"
mkdir -p "$ICONSET" "$ASSETS/AccentColor.colorset" "$ASSETS/LaunchBackground.colorset"
python3 -m venv "$R/iconvenv"
"$R/iconvenv/bin/pip" install --quiet pillow
"$R/iconvenv/bin/python" - <<'PYICON'
from PIL import Image, ImageDraw
from pathlib import Path
import os,json
root=Path(os.environ['RUNNER_TEMP'])/'appsrc/NextReminder/Resources/Assets.xcassets/AppIcon.appiconset'
root.mkdir(parents=True,exist_ok=True)
S=1024
img=Image.new('RGB',(S,S),(18,18,22)); d=ImageDraw.Draw(img)
for r in range(720,0,-8):
    t=r/720; col=(int(255-(45*t)), int(103-(45*t)), int(28-(12*t)))
    d.ellipse((S/2-r,S/2-r,S/2+r,S/2+r),fill=col)
d.rounded_rectangle((190,205,834,820),radius=145,fill=(25,25,30),outline=(255,255,255),width=10)
d.ellipse((410,330,614,534),fill=(255,255,255)); d.rounded_rectangle((390,430,634,625),radius=80,fill=(255,255,255)); d.rectangle((365,575,659,625),fill=(255,255,255)); d.ellipse((474,630,550,706),fill=(255,255,255)); d.ellipse((585,560,755,730),fill=(255,116,38),outline=(25,25,30),width=12); d.line((625,645,665,683),fill='white',width=22); d.line((665,683,724,616),fill='white',width=22)
img.save(root/'AppIcon-1024.png',optimize=True)
for size in [40,58,60,80,87,120,180]: img.resize((size,size),Image.Resampling.LANCZOS).save(root/f'AppIcon-{size}.png',optimize=True)
contents={"images":[{"filename":"AppIcon-40.png","idiom":"iphone","scale":"2x","size":"20x20"},{"filename":"AppIcon-60.png","idiom":"iphone","scale":"3x","size":"20x20"},{"filename":"AppIcon-58.png","idiom":"iphone","scale":"2x","size":"29x29"},{"filename":"AppIcon-87.png","idiom":"iphone","scale":"3x","size":"29x29"},{"filename":"AppIcon-80.png","idiom":"iphone","scale":"2x","size":"40x40"},{"filename":"AppIcon-120.png","idiom":"iphone","scale":"3x","size":"40x40"},{"filename":"AppIcon-120.png","idiom":"iphone","scale":"2x","size":"60x60"},{"filename":"AppIcon-180.png","idiom":"iphone","scale":"3x","size":"60x60"},{"filename":"AppIcon-1024.png","idiom":"ios-marketing","scale":"1x","size":"1024x1024"}],"info":{"author":"xcode","version":1}}
(root/'Contents.json').write_text(json.dumps(contents,indent=2)+'\n')
(root.parent/'Contents.json').write_text('{"info":{"author":"xcode","version":1}}\n')
PYICON
cat > "$ASSETS/AccentColor.colorset/Contents.json" <<'EOF'
{"colors":[],"info":{"author":"xcode","version":1}}
EOF
cat > "$ASSETS/LaunchBackground.colorset/Contents.json" <<'EOF'
{"colors":[],"info":{"author":"xcode","version":1}}
EOF

xcodebuild -project "$P/NextReminder.xcodeproj" -scheme NextReminder -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath "$R/DD" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' build
APP=$(find "$R/DD/Build/Products/Release-iphoneos" -maxdepth 1 -name NextReminder.app -print -quit)
test -n "$APP"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Info.plist")" = '1.3.32'
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Info.plist")" = '42'
mkdir -p "$R/out/Payload"; cp -R "$APP" "$R/out/Payload/"
(cd "$R/out" && zip -qry NextReminder_1.3.32_Unsigned.tipa Payload)
rm -rf "$R/out/Payload"

# Reconstruct exact 1.0.16 tweak source, then add missed-reminder scheduler.
awk '/^brew install dpkg ldid/{exit} {print}' tmp-build-1331/build.sh > "$R/reconstruct-tweak1016.sh"
bash "$R/reconstruct-tweak1016.sh"
TROOT="$R/nqrsrc"
cp tmp-build-1333/MissedReminderScheduler.m "$TROOT/MissedReminderScheduler.m"
python3 - <<'PYTWEAK'
from pathlib import Path
import os,re
root=Path(os.environ['RUNNER_TEMP'])/'nqrsrc'
p=root/'Makefile'; s=p.read_text()
needle='PersistentReportScheduler.m'
if 'MissedReminderScheduler.m' not in s:
    s=s.replace(needle,needle+' MissedReminderScheduler.m',1)
p.write_text(s)
p=root/'Tweak.xm'; s=p.read_text()
decl='extern "C" void NQRStartMissedReminderScheduler(void);\n'
if decl not in s:
    pos=s.find('\n'); s=s[:pos+1]+decl+s[pos+1:]
call='NQRStartPersistentReportScheduler();'
if call not in s: raise SystemExit('Persistent scheduler call missing')
if 'NQRStartMissedReminderScheduler();' not in s:
    s=s.replace(call,call+'\n        NQRStartMissedReminderScheduler();',1)
p.write_text(s)
p=root/'control'; s=p.read_text(); s=re.sub(r'^Version:\s*1\.0\.16\s*$','Version: 1.0.17',s,flags=re.M); p.write_text(s)
PYTWEAK

grep -q 'Version: 1.0.17' "$TROOT/control"
grep -q 'MissedReminderScheduler.m' "$TROOT/Makefile"
grep -q 'NQRStartMissedReminderScheduler();' "$TROOT/Tweak.xm"
grep -q 'initWithBundleIdentifier' "$TROOT/MissedReminderScheduler.m"
grep -q 'missed-daily' "$TROOT/MissedReminderScheduler.m"
grep -q 'com.nextsolution.nextreminder.database.changed' "$TROOT/MissedReminderScheduler.m"
grep -q 'PCPersistentTimer' "$TROOT/MissedReminderScheduler.m"

brew install dpkg ldid
THEOSROOT="$R/theos-rh"
git init "$THEOSROOT"
git -C "$THEOSROOT" remote add origin https://github.com/roothide/theos.git
git -C "$THEOSROOT" fetch --depth 1 origin 88506b2c22e9e07dd4ed055f23c9e398a117a2c7
git -C "$THEOSROOT" checkout --detach 88506b2c22e9e07dd4ed055f23c9e398a117a2c7
git -C "$THEOSROOT" submodule update --init --recursive --depth 1
export THEOS="$THEOSROOT" THEOS_PACKAGE_SCHEME=roothide
make -C "$TROOT" clean package FINALPACKAGE=1
D=$(find "$TROOT/packages" -name '*.deb' -print -quit)
test -n "$D"
test "$(dpkg-deb -f "$D" Version)" = '1.0.17'
X=$(mktemp -d); dpkg-deb -x "$D" "$X"
F=$(find "$X" -name NextQuickReminder.dylib -print -quit); test -n "$F"
strings -a "$F" > "$R/tweak.strings"
grep -q 'starting missed-reminder daily scheduler' "$R/tweak.strings"
grep -q 'missed-daily' "$R/tweak.strings"
grep -q 'initWithBundleIdentifier:' "$R/tweak.strings"
grep -q 'Starting PCPersistentTimer report scheduler' "$R/tweak.strings"
cp "$D" "$R/out/NextQuickReminder_1.0.17_RootHide.deb"

cd "$R/out"
shasum -a 256 NextReminder_1.3.32_Unsigned.tipa NextQuickReminder_1.0.17_RootHide.deb > SHA256SUMS.txt
ls -lh
cat SHA256SUMS.txt
