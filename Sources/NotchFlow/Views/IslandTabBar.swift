import SwiftUI

struct IslandTabBar: View {
    @Binding var activeModule: IslandModule
    let isPremium: Bool

    var body: some View {
        HStack(spacing: 6) {
            ForEach(IslandModule.allCases) { module in
                moduleButton(module)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
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
                .foregroundStyle(isActive ? .white : .white.opacity(0.4))
                .frame(width: 30, height: 24)
                .background {
                    if isActive {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
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
