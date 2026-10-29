import SwiftUI

enum SignerMainTab: Hashable {
    case home, sign, signedApps, library, settings
}

struct NextSignerDashboardView: View {
    @ObservedObject var store: SignerStore
    @ObservedObject var local: LocalSigningController
    @Binding var selectedTab: SignerMainTab

    @State private var showingProfiles = false
    @State private var showingActivity = false

    private var savedBytes: Int64 {
        local.signedApps.reduce(Int64(0)) { $0 + $1.sizeBytes }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    brandHeader
                    hero
                    SignerSectionHeader(
                        title: "Quick actions",
                        subtitle: "Everything you need, one tap away."
                    )
                    HStack(spacing: 12) {
                        actionCard("Sign an IPA", detail: "On-device signing",
                                   symbol: "signature", tint: SignerDesign.blue) {
                            selectedTab = .sign
                        }
                        actionCard("Re-sign apps", detail: "Batch or selected",
                                   symbol: "arrow.triangle.2.circlepath", tint: SignerDesign.violet) {
                            selectedTab = .signedApps
                        }
                    }

                    SignerSectionHeader(
                        title: "Your workspace",
                        subtitle: "All files and signing keys stay on this device."
                    )
                    HStack(spacing: 12) {
                        SignerMetricCard(
                            icon: "app.badge.checkmark",
                            value: "\(local.signedApps.count)",
                            caption: "Signed IPAs"
                        )
                        SignerMetricCard(
                            icon: "internaldrive",
                            value: ByteCountFormatter.string(fromByteCount: savedBytes, countStyle: .file),
                            caption: "Local storage"
                        )
                    }

                    setupCard

                    if !local.signedApps.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Recently signed").font(.title3.bold())
                                Spacer()
                                Button("See all") { selectedTab = .signedApps }
                                    .font(.subheadline.weight(.semibold))
                            }
                            VStack(spacing: 0) {
                                ForEach(Array(local.signedApps.prefix(3))) { app in
                                    HStack(spacing: 12) {
                                        Image(systemName: "square.stack.3d.up.fill")
                                            .font(.title3)
                                            .foregroundStyle(SignerDesign.blue)
                                            .frame(width: 38, height: 38)
                                            .background(SignerDesign.blue.opacity(0.1),
                                                        in: RoundedRectangle(cornerRadius: 10))
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(app.appName).font(.subheadline.weight(.semibold))
                                            Text(app.bundleID).font(.caption2)
                                                .foregroundStyle(.secondary).lineLimit(1)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.caption.weight(.bold)).foregroundStyle(.tertiary)
                                    }
                                    .padding(13)
                                    .contentShape(Rectangle())
                                    .onTapGesture { selectedTab = .signedApps }
                                    if app.id != local.signedApps.prefix(3).last?.id {
                                        Divider().padding(.leading, 63)
                                    }
                                }
                            }
                            .background(SignerDesign.card, in: RoundedRectangle(cornerRadius: 19))
                        }
                    }

                    HStack {
                        Button { showingActivity = true } label: {
                            Label("Activity", systemImage: "clock.arrow.circlepath")
                        }
                        Spacer()
                        Text("Next Signer · iOS 16+")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .font(.subheadline)
                    .padding(.bottom, 6)
                }
                .padding(18)
            }
            .background(SignerDesign.canvas.ignoresSafeArea())
            .navigationTitle("Overview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { selectedTab = .settings } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .onAppear {
                local.refreshCredentials()
                local.refreshSignedApps()
            }
            .sheet(isPresented: $showingProfiles) {
                NextSignerLocalProfileView(local: local)
            }
            .sheet(isPresented: $showingActivity) {
                NextSignerActivityView(store: store)
            }
        }
    }

    private var brandHeader: some View {
        HStack(spacing: 11) {
            Image(systemName: "checkmark.shield.fill")
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 43, height: 43)
                .background(SignerDesign.hero, in: RoundedRectangle(cornerRadius: 13))
            VStack(alignment: .leading, spacing: 1) {
                Text("NEXT SIGNER").font(.subheadline.bold()).tracking(1.4)
                Text("Professional IPA workspace")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            SignerStatusDot(ready: local.credentialsReady,
                            label: local.credentialsReady ? "Ready" : "Setup needed")
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("PRIVATE · ON-DEVICE", systemImage: "lock.shield")
                .font(.caption2.bold()).tracking(1.4)
                .foregroundStyle(.white.opacity(0.85))

            Text("Sign smarter.\nShip faster.")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .tracking(-0.7)
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)

            Text("Sign, re-sign and manage your apps from a single secure workspace.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.86))
                .fixedSize(horizontal: false, vertical: true)

            Button {
                selectedTab = .sign
            } label: {
                HStack {
                    Label("Start signing", systemImage: "bolt.fill")
                    Spacer()
                    Image(systemName: "arrow.up.right")
                }
                .font(.subheadline.bold())
                .foregroundStyle(SignerDesign.blue)
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
                .background(.white, in: RoundedRectangle(cornerRadius: 13))
            }
            .buttonStyle(.plain)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SignerDesign.hero, in: RoundedRectangle(cornerRadius: 25))
    }

    private func actionCard(_ title: String, detail: String, symbol: String,
                            tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: symbol)
                    .font(.title2)
                    .foregroundStyle(tint)
                    .frame(width: 44, height: 44)
                    .background(tint.opacity(0.11), in: RoundedRectangle(cornerRadius: 12))
                Text(title).font(.subheadline.bold()).foregroundStyle(.primary)
                Text(detail).font(.caption).foregroundStyle(.secondary)
                HStack {
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.caption.bold())
                        .foregroundStyle(tint)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(SignerDesign.card, in: RoundedRectangle(cornerRadius: 20))
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(SignerDesign.hairline, lineWidth: 0.7)
            }
        }
        .buttonStyle(.plain)
    }

    private var setupCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Signing credentials").font(.headline)
                    Text("Required for local signing and re-signing")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "key.horizontal.fill")
                    .foregroundStyle(SignerDesign.blue)
            }
            HStack(spacing: 7) {
                statusChip("P12", isReady: local.hasP12)
                statusChip("Profile", isReady: local.hasProvisioningProfile)
                statusChip("Password", isReady: local.p12PasswordIsStored)
            }
            Button {
                showingProfiles = true
            } label: {
                HStack {
                    Text("Manage signing profiles")
                    Spacer()
                    Image(systemName: "chevron.right")
                }
                .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .tint(SignerDesign.blue)
        }
        .padding(17)
        .background(SignerDesign.card, in: RoundedRectangle(cornerRadius: 20))
    }

    private func statusChip(_ label: String, isReady: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: isReady ? "checkmark.circle.fill" : "exclamationmark.circle")
                .foregroundStyle(isReady ? .green : .orange)
            Text(label).font(.caption.weight(.medium)).lineLimit(1)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .background(SignerDesign.canvas, in: Capsule())
    }
}
