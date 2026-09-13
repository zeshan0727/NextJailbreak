from pathlib import Path

root = Path('NextSigner/Vendor/Zsign-Package')
bridge = root / 'swift/zsign.mm'
s = bridge.read_text()
s = s.replace(
    'void(^completionHandler)(BOOL success, NSError *error)',
    'void(^completionHandler)(BOOL success)'
)
old_call = 'bundle.SignFolder(&zsa, strFolder, strBundleId, strBundleVersion, strDisplayName, arrDylibFiles, bForce, bWeakInject, bEnableCache, excludeprovion)'
new_call = 'bundle.SignFolder(&zsa, strFolder, strBundleId, strBundleVersion, strDisplayName, arrDylibFiles, arrDisDylibFiles, bForce, bWeakInject, bEnableCache, excludeprovion)'
if old_call not in s:
    raise SystemExit('Expected stale SignFolder bridge call not found')
s = s.replace(old_call, new_call)
s = s.replace('completionHandler(bRet);', 'if (completionHandler) { completionHandler(bRet); }')
bridge.write_text(s)

bundle = root / 'src/bundle.cpp'
b = bundle.read_text()
old = '''if (!pSignAsset->m_strProvData.empty()) {
\t\tif (bRemoveProvision) {
\t\t\tif (!ZFile::WriteFileV(pSignAsset->m_strProvData, "%s/embedded.mobileprovision", m_strAppFolder.c_str())) { // embedded.mobileprovision'''
new = '''if (!pSignAsset->m_strProvData.empty()) {
\t\tif (!bRemoveProvision) {
\t\t\tif (!ZFile::WriteFileV(pSignAsset->m_strProvData, "%s/embedded.mobileprovision", m_strAppFolder.c_str())) { // embedded.mobileprovision'''
if old not in b:
    raise SystemExit('Expected inverted embedded.mobileprovision condition not found')
bundle.write_text(b.replace(old, new, 1))

# The upstream package target uses path "src" while listing Objective-C++ bridge
# files from ../swift. SwiftPM currently resolves the target but silently omits
# those bridge files, leaving _zsign/_checkCert/etc undefined at app link time.
# Point the C/ObjC++ target at the package root so the bridge is compiled.
(root / 'Package.swift').write_text(r'''// swift-tools-version: 5.8
import PackageDescription

let package = Package(
    name: "Zsign",
    platforms: [
        .iOS(.v12),
        .macOS(.v10_15),
        .tvOS(.v12),
        .watchOS(.v8),
        .custom("xros", versionString: "1.3")
    ],
    products: [
        .library(name: "zsignc", targets: ["ZsignC"]),
        .library(name: "Zsign", targets: ["Zsign"]),
    ],
    dependencies: [
        .package(url: "https://github.com/krzyzanowskim/OpenSSL", from: "3.3.3001")
    ],
    targets: [
        .target(
            name: "ZsignC",
            dependencies: [
                .product(name: "OpenSSL", package: "OpenSSL")
            ],
            path: ".",
            sources: [
                "src/archo.cpp",
                "src/bundle.cpp",
                "src/macho.cpp",
                "src/openssl.cpp",
                "swift/utils.mm",
                "src/signing.cpp",
                "swift/zsign.mm",
                "src/common/base64.cpp",
                "src/common/fs.cpp",
                "src/common/json.cpp",
                "src/common/log.cpp",
                "src/common/sha.cpp",
                "src/common/timer.cpp",
                "src/common/util.cpp"
            ],
            publicHeadersPath: "src/include",
            cxxSettings: [
                .headerSearchPath("src"),
                .headerSearchPath("src/common"),
                .headerSearchPath("swift"),
                .unsafeFlags(["-std=c++17"])
            ],
            linkerSettings: [
                .linkedFramework("OpenSSL")
            ]
        ),
        .target(
            name: "Zsign",
            dependencies: ["ZsignC"],
            path: "swift",
            sources: ["zsign.swift"]
        )
    ]
)
''')

print('Patched Zsign package for Next Signer local signing')
