import SwiftUI

/// Full-width tab row with a flexible gap for the physical notch (Notchify-style).
struct ExpandedNotchTabBar: View {
    @Binding var activeModule: IslandModule
    let isPremium: Bool

    var body: some View {
        HStack(spacing: 0) {
            ForEach(IslandModule.leadingTabs) { module in
                tabButton(module)
            }
            Spacer(minLength: 0)
            ForEach(IslandModule.trailingTabs) { module in
                tabButton(module)
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 2)
        .frame(maxWidth: .infinity, alignment: .top)
    }

    @ViewBuilder
    private func tabButton(_ module: IslandModule) -> some View {
        let isActive = activeModule == module
        let isLocked = module.requiresPremium && !isPremium

        Button {
            guard !isLocked else { return }
            activeModule = module
        } label: {
            Image(systemName: module.systemImage)
                .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                .foregroundStyle(isActive ? .white : .white.opacity(0.45))
                .frame(width: 28, height: 24)
                .background {
                    if isActive {
                        Capsule()
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
                .padding(.horizontal, 4)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(module.title)
    }
}
