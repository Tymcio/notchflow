import SwiftUI

struct IslandTabBar: View {
    @Binding var activeModule: IslandModule
    let isPremium: Bool
    var hasAgentsAddon: Bool = true
    var badgeCounts: [IslandModule: Int] = [:]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(IslandModule.allCases) { module in
                IslandModuleTabButton(
                    module: module,
                    isActive: activeModule == module,
                    isLocked: moduleLockState(module),
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

    private func moduleLockState(_ module: IslandModule) -> Bool {
        if module.requiresPremium && !isPremium { return true }
        if module.requiresAgentsAddon && !hasAgentsAddon { return true }
        return false
    }
}
