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
\tif err != nil {
\t\treturn "127.0.0.1"
\t}
\tfor _, iface := range interfaces {
\t\tif iface.Flags&net.FlagUp == 0 || iface.Flags&net.FlagLoopback != 0 {
\t\t\tcontinue
\t\t}
\t\taddrs, err := iface.Addrs()
\t\tif err != nil {
\t\t\tcontinue
\t\t}
\t\tfor _, addr := range addrs {
\t\t\tvar ip net.IP
\t\t\tswitch v := addr.(type) {
\t\t\tcase *net.IPNet:
\t\t\t\tip = v.IP
\t\t\tcase *net.IPAddr:
\t\t\t\tip = v.IP
\t\t\t}
\t\t\tif ip == nil {
\t\t\t\tcontinue
\t\t\t}
\t\t\tip = ip.To4()
\t\t\tif ip == nil || ip.IsLoopback() {
\t\t\t\tcontinue
\t\t\t}
\t\t\treturn ip.String()
\t\t}
\t}
\treturn "127.0.0.1"
}
"""
if "func localWiFiIPv4() string {" not in s:
    s = s.replace(marker, helper + marker, 1)
s = s.replace(marker, marker + "\n\tproxyHost := localWiFiIPv4()", 1)
oldhost = "<string>127.0.0.1</string>\n\t\t\t\t\t<key>ProxyServerPort</key>"
newhost = "<string>` + proxyHost + `</string>\n\t\t\t\t\t<key>ProxyServerPort</key>"
if oldhost not in s:
    raise SystemExit("proxy profile host pattern not found")
s = s.replace(oldhost, newhost, 1)
p.write_text(s)