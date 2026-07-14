import SwiftUI

struct LicenseSettingsTab: View {
    let status: LicenseStatus
    @Binding var licenseKey: String
    @Binding var licenseMessage: String
    let onActivate: () -> Void
    let onDeactivate: () -> Void
    let onDeactivateInPolar: () -> Void

    private var licenseMessageIsSuccess: Bool {
        licenseMessage == loc("License activated.")
    }

    var body: some View {
        SettingsFormContent {
            if !LicenseMode.current.isEnforced {
                Section {
                    Label {
                        LocText("Beta period — all Premium features are unlocked. A key will be required in the stable release; any key entered now will be remembered.")
                            .font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "sparkles")
                    }
                    .foregroundStyle(.secondary)
                }
            }

            Section {
                LabeledContent(loc("Plan")) {
                    Text(status.isPremium ? localizedTier(status.tier) : loc("Free"))
                        .fontWeight(.medium)
                }

                if status.isPremium, let validatedAt = status.validatedAt {
                    LabeledContent(loc("Activated")) {
                        Text(validatedAt, style: .date)
                    }
                }
            } header: {
                Text(loc("License status"))
            }

            Section {
                TextField(loc("License key"), text: $licenseKey)
                    .textFieldStyle(.roundedBorder)
                    .font(.body.monospaced())

                HStack(spacing: 10) {
                    Button(loc("Activate license"), action: onActivate)
                        .buttonStyle(.borderedProminent)
                        .disabled(licenseKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button(loc("Remove from this Mac"), role: .destructive, action: onDeactivate)
                        .disabled(!status.isPremium && licenseKey.isEmpty)
                }

                Button(loc("Release activation (Polar)"), action: onDeactivateInPolar)
                    .buttonStyle(.bordered)
                    .disabled(!status.isPremium)

                if !licenseMessage.isEmpty {
                    Text(licenseMessage)
                        .font(.caption)
                        .foregroundStyle(licenseMessageIsSuccess ? .green : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                Text(loc("License key"))
            } footer: {
                SettingsFooterCaption("Paste the key from your purchase at notchflow.eu (e.g. NOTCHFLOW_… or UUID from Polar email).")
            }

            Section {
                Link(loc("Buy Premium at notchflow.eu"), destination: NotchFlowConstants.websiteURL.appending(path: "pricing"))
            }
        }
    }

    private func localizedTier(_ tier: LicenseTier) -> String {
        switch tier {
        case .free: loc("Free")
        case .annual: loc("Annual")
        case .lifetime: loc("Lifetime")
        }
    }
}
