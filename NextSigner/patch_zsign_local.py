from pathlib import Path

bridge = Path('NextSigner/Vendor/Zsign-Package/swift/zsign.mm')
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

bundle = Path('NextSigner/Vendor/Zsign-Package/src/bundle.cpp')
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
print('Patched Zsign package for Next Signer local signing')
