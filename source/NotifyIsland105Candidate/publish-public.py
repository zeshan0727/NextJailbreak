#!/usr/bin/env python3
"""Publish only the approved RootHide variant; preserve every unrelated APT stanza."""
import bz2, gzip, hashlib, json, lzma, re, shutil, subprocess, sys
from datetime import datetime,timezone
from email.utils import format_datetime
from pathlib import Path
root, output, source = map(Path,sys.argv[1:4])
package="com.nextsolution.nextaura.notification-island"; version="1.0.17"; arch="iphoneos-arm64e"
filename="NotifyIsland_1.0.17_RootHide.deb"
deb=output/filename
def check(ok,msg):
    if not ok: raise SystemExit(msg)
def field(block,key):
    match=re.search(r"(?m)^"+re.escape(key)+r":\s*([^\n]+)$",block)
    return match.group(1).strip() if match else None
def run(*args): return subprocess.check_output([str(x) for x in args],text=True).strip()
def sha(path,algo): return hashlib.new(algo,path.read_bytes()).hexdigest()
for k,v in [("Package",package),("Version",version),("Architecture",arch),("Maintainer","Next Jailbreak")]:
    check(run("dpkg-deb","-f",deb,k)==v,"Unexpected "+k)
dest=root/"debfiles"/filename; dest.parent.mkdir(exist_ok=True); shutil.copy2(deb,dest)
(root/"icons").mkdir(exist_ok=True); shutil.copy2(output/"notify-island.png",root/"icons/notify-island.png")
(root/"depictions").mkdir(exist_ok=True)
for name in ("notify-island.html","notify-island.json"): shutil.copy2(source/name,root/"depictions"/name)
# Build stanza directly from the actual control, not manually maintained values.
control=run("dpkg-deb","-f",deb)
stanza=control+"\n"+f"Filename: ./debfiles/{filename}\nSize: {dest.stat().st_size}\nMD5sum: {sha(dest,'md5')}\nSHA1: {sha(dest,'sha1')}\nSHA256: {sha(dest,'sha256')}"
p=root/"Packages"
blocks=[x.strip() for x in re.split(r"\n\s*\n",p.read_text()) if x.strip()]
had=any(field(x,"Package")==package and field(x,"Version")==version and field(x,"Architecture")==arch for x in blocks)
other=[x for x in blocks if not(field(x,"Package")==package and field(x,"Version")==version and field(x,"Architecture")==arch)]
other.append(stanza)
p.write_text("\n\n".join(other)+"\n")
raw=p.read_bytes()
(root/"Packages.gz").write_bytes(gzip.compress(raw,compresslevel=9,mtime=0))
(root/"Packages.bz2").write_bytes(bz2.compress(raw,compresslevel=9))
(root/"Packages.xz").write_bytes(lzma.compress(raw,preset=9|lzma.PRESET_EXTREME))
with (root/"Packages.zst").open("wb") as stream:
    subprocess.run(["zstd","-19","-q","-c",str(p)],stdout=stream,check=True)
for suffix,decode in [("gz",gzip.decompress),("bz2",bz2.decompress),("xz",lzma.decompress)]:
    check(decode((root/("Packages."+suffix)).read_bytes())==raw,"Index compression mismatch "+suffix)
check(subprocess.check_output(["zstd","-q","-d","-c",str(root/"Packages.zst")])==raw,"zstd mismatch")
rel=root/"Release"; content=rel.read_text()
check("Origin: Next Jailbreak" in content,"Wrong repository")
if not had:
    m=re.search(r"(?m)^Version: (\d+)\.(\d+)\.(\d+)$",content)
    if m: content=content[:m.start()]+f"Version: {m[1]}.{m[2]}.{int(m[3])+1}"+content[m.end():]
content=re.sub(r"(?m)^Date:.*$", "Date: "+format_datetime(datetime.now(timezone.utc),usegmt=True),content)
# Keep any existing Release checksum blocks correct, without inventing
# a new signing mechanism or changing repository distribution structure.
lines=content.splitlines(); mode=None; digests={"MD5Sum":"md5","SHA1":"sha1","SHA256":"sha256","SHA512":"sha512"}
for i,line in enumerate(lines):
    if line and not line.startswith(" "): mode=line.rstrip(":") if line.rstrip(":") in digests else None
    elif mode and line.strip():
        parts=line.split()
        if len(parts)==3:
            path=root/parts[2]
            if path.is_file(): lines[i]=f" {sha(path,digests[mode])} {path.stat().st_size:16d} {parts[2]}"
rel.write_text("\n".join(lines)+"\n")
# Add a single product feature to the existing public repository page.
page=root/"repo/index.html"; html=page.read_text(); marker='<!-- notify-island-public-release -->'
if marker not in html:
    # Insert within main, directly before its closing element.
    check("</main>" in html,"Repository page layout not recognized")
    card=marker+'''
<section class="section" aria-label="Notify Island">
<div class="section-head"><span class="eyebrow">Next Jailbreak · Tweaks</span><h2>Notify Island</h2><p>Custom Dynamic Island notifications. Version 1.0.17 for RootHide.</p></div>
<article class="card"><img src="/icons/notify-island.png" alt="Notify Island" width="72" height="72" style="border-radius:16px"><h3>Five styles. Your notifications.</h3><p>Full Cover, Classic, Fluid, Capsule and Floating, with separate compact and expanded settings and replies for supported apps.</p><div class="actions"><a class="button primary" href="sileo://package/com.nextsolution.nextaura.notification-island">Open in Sileo</a><a class="button" href="/depictions/notify-island.html">Details</a></div></article>
</section>
'''
    html=html.replace("</main>",card+"\n</main>",1)
    page.write_text(html)
check(sum(field(x,"Package")==package and field(x,"Version")==version and field(x,"Architecture")==arch for x in re.split(r"\n\s*\n",p.read_text()))==1,"Duplicate index entry")
print("Published",package,version,arch,sha(dest,"sha256"))
