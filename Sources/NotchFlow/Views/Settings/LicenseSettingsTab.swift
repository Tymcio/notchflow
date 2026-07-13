import SwiftUI

struct LicenseSettingsTab: View {
    let status: LicenseStatus
    @Binding var licenseKey: String
    @Binding var licenseMessage: String
    let onActivate: () -> Void
    let onDeactivate: () -> Void
    let onDeactivateInPolar: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if !LicenseMode.current.isEnforced {
                    Label {
                        Text("Okres beta — wszystkie funkcje Premium są odblokowane. Aktywacja klucza będzie wymagana w wersji stabilnej; wpisany teraz klucz zostanie zapamiętany.")
                            .font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "sparkles")
                    }
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.accentColor.opacity(0.1))
                    }
                }

                GroupBox("Status licencji") {
                    LabeledContent("Plan") {
                        Text(status.isPremium ? localizedTier(status.tier) : "Darmowa")
                            .fontWeight(.medium)
                    }

                    if status.isPremium, let validatedAt = status.validatedAt {
                        LabeledContent("Aktywowano") {
                            Text(validatedAt, style: .date)
                        }
                    }
                }

                GroupBox("Klucz licencyjny") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Wklej klucz z zakupu na notchflow.eu (np. NOTCHFLOW_… lub UUID z e-maila Polar).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        TextField("Klucz licencyjny", text: $licenseKey)
                            .textFieldStyle(.roundedBorder)
                            .font(.body.monospaced())
                            .frame(maxWidth: .infinity)

                        HStack(spacing: 10) {
                            Button("Aktywuj licencję", action: onActivate)
                                .buttonStyle(.borderedProminent)
                                .disabled(licenseKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                            Button("Usuń z tego Maca", role: .destructive, action: onDeactivate)
                                .disabled(!status.isPremium && licenseKey.isEmpty)
                        }

                        Button("Zwolnij aktywację (Polar)", action: onDeactivateInPolar)
                            .buttonStyle(.bordered)
                            .disabled(!status.isPremium)

                        if !licenseMessage.isEmpty {
                            Text(licenseMessage)
                                .font(.caption)
                                .foregroundStyle(licenseMessage.contains("aktywowana") ? .green : .secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Link("Kup Premium na notchflow.eu", destination: NotchFlowConstants.websiteURL.appending(path: "pricing"))
                    .font(.caption)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func localizedTier(_ tier: LicenseTier) -> String {
        switch tier {
        case .free: "Darmowa"
        case .annual: "Roczna"
        case .lifetime: "Dożywotnia"
        }
    }
}
