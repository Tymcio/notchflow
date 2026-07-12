import SwiftUI

struct ExpandedIslandStackHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct ExpandedModuleContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

extension View {
    func reportExpandedIslandStackHeight() -> some View {
        background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: ExpandedIslandStackHeightKey.self,
                    value: proxy.size.height
                )
            }
        }
    }

    func reportExpandedModuleContentHeight() -> some View {
        background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: ExpandedModuleContentHeightKey.self,
                    value: proxy.size.height
                )
            }
        }
    }
}
