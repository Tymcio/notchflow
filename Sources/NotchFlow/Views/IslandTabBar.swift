import SwiftUI

struct IslandTabBar: View {
    @Binding var activeModule: IslandModule
    let isPremium: Bool
    var badgeCounts: [IslandModule: Int] = [:]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(IslandModule.allCases) { module in
                IslandModuleTabButton(
                    module: module,
                    isActive: activeModule == module,
                    isLocked: module.requiresPremium && !isPremium,
                    badgeCount: badgeCounts[module] ?? 0,
                    style: .compact
                ) {
                    activeModule = module
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }
}
