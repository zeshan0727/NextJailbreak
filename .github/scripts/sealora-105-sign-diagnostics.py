#!/usr/bin/env python3
"""Sealora 1.0.5: preserve strict CMS/CodeDirectory checks and expose failure reason."""
from pathlib import Path
import plistlib
import sys

root=Path(sys.argv[1]).resolve()

inspector=root/"Sealora/Core/ArchiveInspector.swift"
s=inspector.read_text()
old='''        let signatures = try RorkSigner.checkMachOCodeSignatures(binary)
        guard !signatures.isEmpty,
              signatures.allSatisfy({ $0.hasCMS && $0.cmsSignatureValid && $0.codeDirectoryHashesValid }) else {
            throw SealoraError.damagedOutput("Main executable CMS signature or CodeDirectory validation failed")
        }
'''
new='''        // Verify each architecture independently. Never count a failed signature as success.
        let reports: [MachOCodeSignatureCheckReport]
        do {
            reports = try RorkSigner.checkMachOCodeSignatures(binary)
        } catch {
            throw SealoraError.damagedOutput(
                "Cannot inspect the newly signed executable (\\(error.localizedDescription)). " +
                "Original IPA preserved; no signed result was saved."
            )
        }
        guard !reports.isEmpty else {
            throw SealoraError.damagedOutput(
                "No readable signature was found on the main executable. Original IPA preserved."
            )
        }
        for report in reports {
            let slice = report.architectureIndex + 1
            guard report.hasCMS else {
                throw SealoraError.damagedOutput(
                    "Architecture \\(slice): certificate-backed CMS signature is missing. " +
                    "The IPA may contain unsupported code, or signing did not finish."
                )
            }
            guard report.codeDirectoryHashesValid else {
                let bad = report.codeDirectories.filter { !$0.isValid }
                let details = bad.map { directory in
                    let pages = directory.codeSlotsValid ? "valid" : "invalid"
                    let special = directory.specialSlotsValid ? "valid" : "invalid"
                    let slots = directory.declaredCodeSlotCount == directory.expectedCodeSlotCount ? "valid" : "invalid"
                    return "code pages \\(pages); special slots \\(special); slot count \\(slots)"
                }.joined(separator: "; ")
                throw SealoraError.damagedOutput(
                    "Architecture \\(slice): CodeDirectory integrity failed" +
                    (details.isEmpty ? "." : " (\\(details)).") +
                    " Original IPA preserved; no signed result was saved."
                )
            }
            guard report.cmsSignatureValid else {
                throw SealoraError.damagedOutput(
                    "Architecture \\(slice): the certificate-backed CMS signature failed " +
                    "cryptographic verification, although CodeDirectory hashes passed. " +
                    "The signing engine output is invalid for this executable. " +
                    "Original IPA preserved; no signed result was saved."
                )
            }
        }
'''
assert s.count(old)==1, "ArchiveInspector signature verification block changed"
inspector.write_text(s.replace(old,new))

app=root/"Sealora/SealoraApp.swift"
s=app.read_text()
old='''            Button("OK", role: .cancel) { library.alertText = nil }
        } message: { Text(library.alertText ?? "") }'''
new='''            Button("Copy Details") {
                UIPasteboard.general.string = library.alertText
                library.alertText = nil
            }
            Button("OK", role: .cancel) { library.alertText = nil }
        } message: { Text(library.alertText ?? "") }'''
assert s.count(old)==2, "Expected two alert presentations"
app.write_text(s.replace(old,new))

info=root/"Sealora/Info.plist"
plist=plistlib.loads(info.read_bytes())
assert plist["CFBundleShortVersionString"]=="1.0.4" and str(plist["CFBundleVersion"])=="5"
plist["CFBundleShortVersionString"]="1.0.5"
plist["CFBundleVersion"]="6"
info.write_bytes(plistlib.dumps(plist,fmt=plistlib.FMT_XML,sort_keys=False))

project=root/"project.yml"
s=project.read_text()
assert "CFBundleShortVersionString: 1.0.4" in s and 'CFBundleVersion: "5"' in s
project.write_text(s.replace("CFBundleShortVersionString: 1.0.4","CFBundleShortVersionString: 1.0.5").replace('CFBundleVersion: "5"','CFBundleVersion: "6"'))

assert 'CMS signature or CodeDirectory validation failed' not in inspector.read_text()
assert 'codeDirectoryHashesValid' in inspector.read_text() and 'cmsSignatureValid' in inspector.read_text()
assert 'Copy Details' in app.read_text()
print("Sealora 1.0.5 strict signature checks and diagnostics applied")
