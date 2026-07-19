import SwiftUI

struct LicenseSettingsTab: View {
    let status: LicenseStatus
    @Binding var licenseKey: String
    @Binding var licenseMessage: String
    let onActivate: () -> Void
    let onDeactivate: () -> Void
    let onDeactivateInPolar: () -> Void
    var onDeactivateAgents: (() -> Void)?
    var onDeactivateAgentsInPolar: (() -> Void)?

    private var licenseMessageIsSuccess: Bool {
        licenseMessage == loc("License activated.")
            || licenseMessage == loc("Agents addon activated.")
    }

    var body: some View {
        SettingsFormContent {
            if !LicenseMode.current.isEnforced {
                Section {
                    Label {
                        LocText("Beta period — all Premium and Agents features are unlocked. A key will be required in the stable release; any key entered now will be remembered.")
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

                LabeledContent(loc("Agents addon")) {
                    Text(status.hasAgentsAddon ? loc("Active") : loc("Not activated"))
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

            if status.isPremium {
                Section {
                    Button(loc("Remove from this Mac"), role: .destructive, action: onDeactivate)

                    Button(loc("Release activation (Polar)"), action: onDeactivateInPolar)
                        .buttonStyle(.bordered)

                    if !licenseMessage.isEmpty {
                        Text(licenseMessage)
                            .font(.caption)
                            .foregroundStyle(licenseMessageIsSuccess ? .green : .secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } header: {
                    Text(loc("Manage Premium"))
                }
            }

            if status.hasAgentsAddon {
                Section {
                    if let onDeactivateAgents {
                        Button(loc("Remove Agents from this Mac"), role: .destructive, action: onDeactivateAgents)
                    }
                    if let onDeactivateAgentsInPolar {
                        Button(loc("Release Agents activation (Polar)"), action: onDeactivateAgentsInPolar)
                            .buttonStyle(.bordered)
                    }
                } header: {
                    Text(loc("Manage Agents"))
                }
            }

            if !status.isPremium || !status.hasAgentsAddon {
                Section {
                    TextField(loc("License key"), text: $licenseKey)
                        .textFieldStyle(.roundedBorder)
                        .font(.body.monospaced())

                    Button(loc("Activate license"), action: onActivate)
                        .buttonStyle(.borderedProminent)
                        .disabled(licenseKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    if !licenseMessage.isEmpty {
                        Text(licenseMessage)
                            .font(.caption)
                            .foregroundStyle(licenseMessageIsSuccess ? .green : .secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } header: {
                    Text(loc("License key"))
                } footer: {
                    SettingsFooterCaption("Paste a Premium key (NOTCHFLOW_…) or Agents key (NOTCHFLOW_AGENTS_…) from notchflow.eu.")
                }

                Section {
                    if !status.isPremium {
                        Link(loc("Buy Premium at notchflow.eu"), destination: NotchFlowConstants.websiteURL.appending(path: "pricing"))
                    }
                    if !status.hasAgentsAddon {
                        Link(loc("Buy Agents addon (€14.90)"), destination: NotchFlowConstants.websiteURL.appending(path: "pricing"))
                    }
                }
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
