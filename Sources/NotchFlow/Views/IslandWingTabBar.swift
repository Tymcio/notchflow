import SwiftUI

struct IslandWingTabBar: View {
    @Binding var activeModule: IslandModule
    let isPremium: Bool
    let side: IslandModuleWingSide

    private var modules: [IslandModule] {
        IslandModule.allCases.filter { $0.wingSide == side }
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(modules) { module in
                moduleButton(module)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 4)
    }

    @ViewBuilder
    private func moduleButton(_ module: IslandModule) -> some View {
        let isActive = activeModule == module
        let isLocked = module.requiresPremium && !isPremium

        Button {
            guard !isLocked else { return }
            activeModule = module
        } label: {
            Image(systemName: module.systemImage)
                .font(.system(size: 11, weight: isActive ? .semibold : .regular))
                .foregroundStyle(isActive ? .white : .white.opacity(0.42))
                .frame(width: 28, height: 22)
                .background {
                    if isActive {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(.white.opacity(0.14))
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if isLocked {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 6, weight: .bold))
                            .foregroundStyle(.white.opacity(0.35))
                            .offset(x: 3, y: -2)
                    }
                }
        }
        .buttonStyle(.plain)
        .help(module.title)
    }
}
