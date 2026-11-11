#!/usr/bin/env python3
"""Sealora 1.0.12: auto-load approved production ads; no banner headings or placeholders."""
from pathlib import Path
import plistlib
import sys

root=Path(sys.argv[1]).resolve()
banner=root/"Sealora/Features/BannerAdsView.swift"
src=banner.read_text()
old='''/// Reserves 50 points above the bottom tab bar; never obscures signing controls.
struct SealoraBannerInset: ViewModifier {
    @AppStorage("sealora-show-test-banner") private var showBanner = true

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom, spacing: 0) {
            if showBanner {
                SealoraBannerSlot()
                    .frame(maxWidth: .infinity)
                    .background(.regularMaterial)
                    .overlay(alignment: .top) { Divider() }
            }
        }
    }
}

private struct SealoraBannerSlot: View {
    @EnvironmentObject private var consent: SealoraConsentManager
    @AppStorage("sealora-admob-live-enabled") private var showLiveAds = false
    @State private var receivedAd = false

    private var adUnitID: String {
        showLiveAds ? SealoraAdConfiguration.bannerUnitID : SealoraAdConfiguration.testBannerUnitID
    }

    var body: some View {
        VStack(spacing: 1) {
            HStack {
                Text(receivedAd ? "ADVERTISEMENT" : "NEXT PROMOTION")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .frame(width: 320)
            ZStack {
                if consent.canRequestAds {
                    SealoraGoogleBanner(adUnitID: adUnitID, onStateChange: { receivedAd = $0 })
                        .id(adUnitID)
                        .frame(width: 320, height: 50)
                }
                if !receivedAd || !consent.canRequestAds {
                    Link(destination: SealoraAdConfiguration.website) {
                        HStack(spacing: 10) {
                            Image(systemName: "n.circle.fill")
                                .font(.system(size: 30))
                                .foregroundStyle(SealoraTheme.gradient)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("NEXT Jailbreak")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(.primary)
                                Text("iOS tools, news and tutorials")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "arrow.up.right")
                                .font(.caption.bold())
                                .foregroundStyle(SealoraTheme.blue)
                        }
                        .padding(.horizontal, 12)
                        .frame(width: 320, height: 50)
                        .background(Color(uiColor: .secondarySystemGroupedBackground),
                                    in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(width: 320, height: 50)
        }
        .padding(.top, 4)
        .padding(.bottom, 4)
        .accessibilityElement(children: .contain)
        .onChange(of: adUnitID) { _ in receivedAd = false }
        .onChange(of: consent.canRequestAds) { _ in receivedAd = false }
    }
}'''
new='''/// The banner occupies no space until Google has delivered an ad.
struct SealoraBannerInset: ViewModifier {
    @AppStorage("sealora-show-test-banner") private var showBanner = true

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom, spacing: 0) {
            if showBanner {
                SealoraBannerSlot()
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

private struct SealoraBannerSlot: View {
    @EnvironmentObject private var consent: SealoraConsentManager
    // Production unit is selected automatically; users can still switch to demo ads
    // for explicit testing. Google's server decides whether the app may serve ads.
    @AppStorage("sealora-admob-live-enabled") private var showLiveAds = true
    @State private var receivedAd = false

    private var adUnitID: String {
        showLiveAds ? SealoraAdConfiguration.bannerUnitID : SealoraAdConfiguration.testBannerUnitID
    }

    var body: some View {
        ZStack {
            if consent.canRequestAds {
                SealoraGoogleBanner(adUnitID: adUnitID, onStateChange: { receivedAd = $0 })
                    .id(adUnitID)
                    .frame(width: 320, height: 50)
                    .opacity(receivedAd ? 1 : 0)
                    .accessibilityHidden(!receivedAd)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: receivedAd ? 50 : 0, alignment: .top)
        .clipped()
        .onAppear {
            // Migrate previous installs that defaulted to demo mode. Do not repeat
            // this migration if the user subsequently selects demo mode manually.
            let defaults = UserDefaults.standard
            if !defaults.bool(forKey: "sealora-production-default-migrated-v1") {
                showLiveAds = true
                defaults.set(true, forKey: "sealora-production-default-migrated-v1")
            }
        }
        .onChange(of: adUnitID) { _ in receivedAd = false }
        .onChange(of: consent.canRequestAds) { allowed in
            if !allowed { receivedAd = false }
        }
    }
}'''
assert src.count(old)==1, f"Unexpected banner source; count={src.count(old)}"
src=src.replace(old,new)
src=src.replace("/// The Google sample unit is used until the developer deliberately switches to live ads.",
                "/// Uses the production unit automatically, gated by UMP consent and AdMob readiness.")
src=src.replace("/// SDK native 320×50 banner. Uses demo ad unit by default to protect publisher account.",
                "/// SDK native 320×50 banner; Google controls whether the requested unit fills.")
assert "NEXT PROMOTION" not in src and 'ADVERTISEMENT' not in src
assert 'SealoraGoogleBanner(adUnitID: adUnitID' in src
assert 'ca-app-pub-4770123899731214/5001772479' in src
banner.write_text(src)

settings=root/"Sealora/Features/SettingsView.swift"
s=settings.read_text()
assert s.count('@AppStorage("sealora-admob-live-enabled") private var useLiveAds = false')==1
s=s.replace('@AppStorage("sealora-admob-live-enabled") private var useLiveAds = false',
            '@AppStorage("sealora-admob-live-enabled") private var useLiveAds = true')
s=s.replace('Toggle("Use production AdMob banner", isOn: $useLiveAds)',
            'Toggle("Use production AdMob banner", isOn: $useLiveAds)')
old_text='''                Text(useLiveAds ?
                     "Publisher banner unit enabled. Ad serving can remain limited until Google approves the app. Do not click your own live ads." :
                     "Google test ads are enabled. Production AdMob IDs are configured; enable live ads only after app readiness approval. A NEXT promotion fills empty placements.")
                    .font(.footnote).foregroundStyle(.secondary)
'''
new_text='''                Text(useLiveAds ?
                     "Ads load automatically when AdMob permits serving. Empty placements stay hidden. Never click your own ads." :
                     "Google demo ads are enabled for development. This device should be registered as a test device before requesting production ads.")
                    .font(.footnote).foregroundStyle(.secondary)
'''
assert s.count(old_text)==1
s=s.replace(old_text,new_text)
s=s.replace("Optional test advertising contacts Google;", "Optional advertising contacts Google;")
settings.write_text(s)

info=root/"Sealora/Info.plist"
p=plistlib.loads(info.read_bytes())
assert p['CFBundleShortVersionString']=='1.0.11' and str(p['CFBundleVersion'])=='12'
assert p['GADApplicationIdentifier']=='ca-app-pub-4770123899731214~1230048425'
p['CFBundleShortVersionString']='1.0.12'
p['CFBundleVersion']='13'
info.write_bytes(plistlib.dumps(p,fmt=plistlib.FMT_XML,sort_keys=False))

proj=root/"project.yml"
if proj.exists():
    cfg=proj.read_text()
    assert cfg.count('CFBundleShortVersionString: 1.0.11')==1
    assert cfg.count('CFBundleVersion: "12"')==1
    proj.write_text(cfg.replace('CFBundleShortVersionString: 1.0.11','CFBundleShortVersionString: 1.0.12')
                    .replace('CFBundleVersion: "12"','CFBundleVersion: "13"'))
print("Sealora 1.0.12: production ad unit auto-selected, no banner labels or promotion placeholder, hidden until loaded.")
