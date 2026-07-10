import SwiftUI

enum IslandTabButtonStyle {
    case expanded
    case compact
}

struct IslandModuleTabButton: View {
    let module: IslandModule
    let isActive: Bool
    let isLocked: Bool
    let style: IslandTabButtonStyle
    let onSelect: () -> Void

    var body: some View {
        Button {
            guard !isLocked else { return }
            onSelect()
        } label: {
            Image(systemName: module.systemImage)
                .font(.system(size: iconSize, weight: isActive ? .semibold : .regular))
                .foregroundStyle(isActive ? .white : .white.opacity(inactiveOpacity))
                .frame(width: buttonWidth, height: buttonHeight)
                .background {
                    if isActive {
                        activeBackground
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
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, verticalPadding)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(module.title)
    }

    private var iconSize: CGFloat {
        style == .expanded ? 12 : 11
    }

    private var inactiveOpacity: CGFloat {
        style == .expanded ? 0.45 : 0.4
    }

    private var buttonWidth: CGFloat {
        style == .expanded ? 28 : 30
    }

    private var buttonHeight: CGFloat {
        24
    }

    private var horizontalPadding: CGFloat {
        style == .expanded ? 4 : 0
    }

    private var verticalPadding: CGFloat {
        style == .expanded ? 4 : 0
    }

    @ViewBuilder
    private var activeBackground: some View {
        switch style {
        case .expanded:
            Capsule()
                .fill(.white.opacity(0.14))
        case .compact:
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.white.opacity(0.14))
        }
    }
}
