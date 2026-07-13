import SwiftUI

struct IdleWingRow<Leading: View, Trailing: View>: View {
    let layout: IdleWingLayout
    let showsLeftWing: Bool
    let showsRightWing: Bool
    @ViewBuilder let leading: () -> Leading
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 0) {
            if layout.leftSlotWidth > 0 {
                Group {
                    if showsLeftWing {
                        idleWing(isLeading: true, content: leading)
                    } else {
                        Color.clear
                    }
                }
                .frame(width: layout.leftSlotWidth, height: layout.panelHeight)
            }

            Color.clear
                .frame(width: layout.centerClearWidth, height: layout.panelHeight)
                .allowsHitTesting(false)

            if layout.rightSlotWidth > 0 {
                Group {
                    if showsRightWing {
                        idleWing(isLeading: false, content: trailing)
                    } else {
                        Color.clear
                    }
                }
                .frame(width: layout.rightSlotWidth, height: layout.panelHeight)
            }
        }
        .frame(width: layout.panelWidth, height: layout.panelHeight, alignment: .topLeading)
        .clipped()
        .transaction { transaction in
            transaction.animation = nil
        }
    }

    @ViewBuilder
    private func idleWing<Content: View>(isLeading: Bool, @ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .background {
                NotchWingShape(isLeading: isLeading)
                    .fill(.black)
            }
            .clipShape(NotchWingShape(isLeading: isLeading))
    }
}
