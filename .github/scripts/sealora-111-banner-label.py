#!/usr/bin/env python3
"""Sealora 1.0.11: remove app-authored TEST from banner heading only."""
from pathlib import Path
import plistlib,sys
root=Path(sys.argv[1])
banner=root/"Sealora/Features/BannerAdsView.swift"
source=banner.read_text()
old='Text(receivedAd ? (showLiveAds ? "ADVERTISEMENT" : "ADVERTISEMENT · TEST") : "NEXT PROMOTION")'
new='Text(receivedAd ? "ADVERTISEMENT" : "NEXT PROMOTION")'
if source.count(old)!=1:
    raise SystemExit("Unexpected banner source; refusing to patch")
source=source.replace(old,new)
assert 'ca-app-pub-3940256099942544/2435281174' in source
assert 'ca-app-pub-4770123899731214/5001772479' in source
assert '@AppStorage("sealora-admob-live-enabled")' in source
banner.write_text(source)

info=root/"Sealora/Info.plist"
data=plistlib.loads(info.read_bytes())
assert data['CFBundleShortVersionString']=='1.0.10' and str(data['CFBundleVersion'])=='11'
assert data['GADApplicationIdentifier']=='ca-app-pub-4770123899731214~1230048425'
data['CFBundleShortVersionString']='1.0.11'
data['CFBundleVersion']='12'
info.write_bytes(plistlib.dumps(data,fmt=plistlib.FMT_XML,sort_keys=False))
proj=root/"project.yml"
if proj.exists():
    text=proj.read_text()
    assert text.count('CFBundleShortVersionString: 1.0.10')==1
    assert text.count('CFBundleVersion: "11"')==1
    proj.write_text(text.replace('CFBundleShortVersionString: 1.0.10','CFBundleShortVersionString: 1.0.11')
                        .replace('CFBundleVersion: "11"','CFBundleVersion: "12"'))
print("Sealora 1.0.11: visible banner heading is ADVERTISEMENT; Google test creatives untouched.")
