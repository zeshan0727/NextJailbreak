from pathlib import Path

p = Path('Core/proxy.go')
s = p.read_text()
old = 'net.Listen("tcp", fmt.Sprintf("127.0.0.1:%d", proxyPort))'
new = 'net.Listen("tcp", fmt.Sprintf("0.0.0.0:%d", proxyPort))'
if old in s:
    s = s.replace(old, new, 1)
marker = 'func generateProxyMobileConfig() string {'
helper = '''func localWiFiIPv4() string {
\tinterfaces, err := net.Interfaces()
\tif err != nil { return "127.0.0.1" }
\tfor _, iface := range interfaces {
\t\tif iface.Flags&net.FlagUp == 0 || iface.Flags&net.FlagLoopback != 0 { continue }
\t\taddrs, err := iface.Addrs()
\t\tif err != nil { continue }
\t\tfor _, addr := range addrs {
\t\t\tvar ip net.IP
\t\t\tswitch v := addr.(type) {
\t\t\tcase *net.IPNet: ip = v.IP
\t\t\tcase *net.IPAddr: ip = v.IP
\t\t\t}
\t\t\tif ip == nil { continue }
\t\t\tip = ip.To4()
\t\t\tif ip == nil || ip.IsLoopback() { continue }
\t\t\treturn ip.String()
\t\t}
\t}
\treturn "127.0.0.1"
}
'''
if 'func localWiFiIPv4() string {' not in s:
    s = s.replace(marker, helper + marker, 1)
s = s.replace(marker, marker + '\n\tproxyHost := localWiFiIPv4()', 1)
needle = '<key>ProxyServer</key>'
pos = s.index(needle)
pos = s.index('<string>127.0.0.1</string>', pos)
s = s[:pos] + '<string>` + proxyHost + `</string>' + s[pos+len('<string>127.0.0.1</string>'):]
p.write_text(s)

p = Path('App/FirstSetupView.swift')
s = p.read_text()
s = s.replace('import SwiftUI\nimport UIKit', 'import SwiftUI\nimport UIKit')
s = s.replace('@State private var manualHint = ""', '@State private var manualHint = ""\n    @State private var detectedWiFiIPv4 = "Detecting…"')
start = s.index('    private var proxyStep: some View {')
end = s.index('    private var certificateStep: some View {', start)
new_proxy = '''    private var proxyStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !setup.message.isEmpty {
                Label(setup.message, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            GroupBox(label: Label("Configure Wi-Fi System Proxy", systemImage: "wifi")) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Set HTTP Proxy to Manual. Use the detected Wi-Fi IPv4 address below and port 8888. Do not use 127.0.0.1.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        Text(detectedWiFiIPv4)
                            .font(.system(.body, design: .monospaced))
                        Spacer()
                        Text(":8888")
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                }
                .padding(.top, 4)
            }
            HStack(spacing: 12) {
                Button {
                    UIPasteboard.general.string = "\\(detectedWiFiIPv4):8888"
                } label: {
                    Label("Copy Address", systemImage: "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                Button {
                    openSettings(.wifi)
                } label: {
                    Label("Open Wi-Fi Settings", systemImage: "gearshape")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .task {
            detectedWiFiIPv4 = await currentWiFiIPv4() ?? "No Wi-Fi IPv4 detected"
        }
    }

    private func currentWiFiIPv4() async -> String? {
        var addrs: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addrs) == 0, let first = addrs else { return nil }
        defer { freeifaddrs(addrs) }
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let current = cursor {
            let flags = Int32(current.pointee.ifa_flags)
            let name = String(cString: current.pointee.ifa_name)
            if (flags & IFF_UP) != 0 && (flags & IFF_LOOPBACK) == 0 && name == "en0",
               let address = current.pointee.ifa_addr,
               address.pointee.sa_family == UInt8(AF_INET) {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
                let value = String(cString: host)
                if !value.isEmpty { return value }
            }
            cursor = current.pointee.ifa_next
        }
        return nil
    }

'''.splitlines()
s = s[:start] + '\n'.join(new_proxy) + '\n' + s[end:]
p.write_text(s)