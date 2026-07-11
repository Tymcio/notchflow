import SwiftUI

/// Full-width tab row with a flexible gap for the physical notch (Notchify-style).
struct ExpandedNotchTabBar: View {
    @Binding var activeModule: IslandModule
    let isPremium: Bool
    var notchCutoutWidth: CGFloat = 0
    var badgeCounts: [IslandModule: Int] = [:]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(IslandModule.leadingTabs) { module in
                tabButton(module)
            }
            Spacer(minLength: notchCutoutWidth)
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
        IslandModuleTabButton(
            module: module,
            isActive: activeModule == module,
            isLocked: module.requiresPremium && !isPremium,
            badgeCount: badgeCounts[module] ?? 0,
            style: .expanded
        ) {
            activeModule = module
        }
    }
}
