#!/usr/bin/env python3
"""Patch Sealora 1.0.3 source to remove UDID dependency in 1.0.4."""
from pathlib import Path
import plistlib, sys
root=Path(sys.argv[1]).resolve()

def load(path): return (root/path).read_text()
def save(path,data): (root/path).write_text(data)
def replace_exact(text,old,new,label):
    if text.count(old)!=1:
        raise RuntimeError(label + ' unexpected match count: ' + str(text.count(old)))
    return text.replace(old,new,1)

p='Sealora/Features/SettingsView.swift'
s=load(p)
s=replace_exact(s,'    @Environment(\\.scenePhase) private var scenePhase\n','',p)
s=replace_exact(s,'    @State private var deviceUDID = ""\n','',p)
a=s.index('            Section("Registered test device") {')
b=s.index('            Section("Privacy and appearance") {',a)
s=s[:a]+s[b:]
s=replace_exact(s,'        .onAppear { deviceUDID = library.deviceUDID }\n        .onChange(of: scenePhase) { phase in\n            if phase == .active { deviceUDID = library.deviceUDID }\n        }\n','',p)
save(p,s)

p='Sealora/SealoraApp.swift'
s=load(p)
s=replace_exact(s,'import Security\n','',p)
s=replace_exact(s,'            .onOpenURL { url in\n                Task { await UDIDEnrollment.complete(url, library: library) }\n            }\n','',p)
s=s[:s.index('/// One-time, consent-based Profile Service flow.')].rstrip()+'\n'
save(p,s)

p='Sealora/Core/ProfileAudit.swift'
s=load(p)
a=s.index('    static func check(data: Data, identity: SigningIdentity, bundleID: String, deviceUDID: String?) throws {')
b=s.index('    private static func profilePlist(',a)
s=s[:a]+'''    /// Check signing authorization; iOS enforces Ad Hoc device lists at installation.
    static func check(data: Data, identity: SigningIdentity, bundleID: String) throws {
        let profile = try RorkSigner.decodeProvisioningProfile(data)
        guard let expiry = profile.expirationDate, expiry > Date() else {
            throw SealoraError.expired("Selected provisioning profile")
        }
        guard profile.supportsBundleIdentifier(bundleID) else {
            throw SealoraError.incompatibleProfile("This profile allows \\(profile.authorizedBundleIdentifier ?? "unknown"), not \\(bundleID).")
        }
        guard profile.containsDeveloperCertificate(for: identity) else {
            throw SealoraError.incompatibleProfile("The selected profile does not contain this certificate.")
        }
    }

'''+s[b:]
save(p,s)

p='Sealora/Core/SigningService.swift'
s=load(p)
s=replace_exact(s,'                        testUDID: String,\n','',p)
s=replace_exact(s,'            try ProfileAudit.check(data: mainProfile, identity: identity, bundleID: choice.bundleID,\n                                   deviceUDID: testUDID.isEmpty ? nil : testUDID)\n','            try ProfileAudit.check(data: mainProfile, identity: identity, bundleID: choice.bundleID)\n',p)
s=replace_exact(s,'                    try ProfileAudit.check(data: data, identity: identity, bundleID: identifier,\n                                           deviceUDID: testUDID.isEmpty ? nil : testUDID)\n','                    try ProfileAudit.check(data: data, identity: identity, bundleID: identifier)\n',p)
save(p,s)

p='Sealora/Core/LibraryStore.swift'
s=load(p)
a=s.index('    var deviceUDID: String {')
b=s.index('    func updateAppearance(_ mode: AppearanceMode)',a)
s=s[:a]+s[b:]
s=replace_exact(s,'        let device = deviceUDID\n','',p)
s=replace_exact(s,'SigningService.perform(choice, testUDID: device)','SigningService.perform(choice)',p)
s=replace_exact(s,'        isUnlocked = !protectWithBiometrics\n','        isUnlocked = !protectWithBiometrics\n        SecureVault.delete("test-device-udid")\n        SecureVault.delete("pending-udid-session-v1")\n',p)
save(p,s)

p='Sealora/Core/SecureVault.swift'
save(p,replace_exact(load(p),'    static let testDeviceKey = "test-device-udid"\n','',p))

p=root/'Sealora/Info.plist'
info=plistlib.loads(p.read_bytes())
assert info['CFBundleShortVersionString']=='1.0.3' and str(info['CFBundleVersion'])=='4'
info.pop('CFBundleURLTypes',None)
info['CFBundleShortVersionString']='1.0.4'
info['CFBundleVersion']='5'
p.write_bytes(plistlib.dumps(info,fmt=plistlib.FMT_XML,sort_keys=False))

p='project.yml'
s=replace_exact(load(p),'        CFBundleShortVersionString: 1.0.3\n','        CFBundleShortVersionString: 1.0.4\n',p)
s=replace_exact(s,'        CFBundleVersion: "4"\n','        CFBundleVersion: "5"\n',p)
save(p,s)

source='\n'.join(p.read_text() for p in (root/'Sealora').rglob('*.swift'))
for obsolete in ['UDIDEnrollment','deviceUDID','testUDID','Registered test device','Get This Device’s UDID','saveDeviceUDID']:
    assert obsolete not in source,obsolete
assert 'profile.containsDeveloperCertificate(for: identity)' in source
assert 'profile.supportsBundleIdentifier(bundleID)' in source
print('Sealora 1.0.4 profile and signing checks preserved; UDID UI and requirement removed')
