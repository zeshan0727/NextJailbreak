from pathlib import Path
p = Path("Core/proxy.go")
s = p.read_text()
old = 'net.Listen("tcp", fmt.Sprintf("127.0.0.1:%d", proxyPort))'
new = 'net.Listen("tcp", fmt.Sprintf("0.0.0.0:%d", proxyPort))'
if old in s:
    s = s.replace(old, new, 1)
marker = "func generateProxyMobileConfig() string {"
helper = """func localWiFiIPv4() string {
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
"""
if "func localWiFiIPv4() string {" not in s:
    s = s.replace(marker, helper + marker, 1)
s = s.replace(marker, marker + "\n\tproxyHost := localWiFiIPv4()", 1)
needle = "<key>ProxyServer</key>"
pos = s.index(needle)
pos = s.index("<string>127.0.0.1</string>", pos)
s = s[:pos] + "<string>` + proxyHost + `</string>" + s[pos+len("<string>127.0.0.1</string>"):]
p.write_text(s)