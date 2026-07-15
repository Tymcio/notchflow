import AppKit
import ApplicationServices
import Foundation

enum AXHelpers {
    static func children(of element: AXUIElement) -> [AXUIElement] {
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let childrenRef else {
            return []
        }

        return ((childrenRef as! NSArray) as Array).compactMap { item -> AXUIElement? in
            let object = item as CFTypeRef
            guard CFGetTypeID(object) == AXUIElementGetTypeID() else { return nil }
            return (object as! AXUIElement)
        }
    }

    static func role(of element: AXUIElement) -> String? {
        var roleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef) == .success else {
            return nil
        }
        return roleRef as? String
    }

    static func title(of element: AXUIElement) -> String? {
        var titleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleRef) == .success else {
            return nil
        }
        return titleRef as? String
    }

    static func description(of element: AXUIElement) -> String? {
        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &valueRef) == .success else {
            return nil
        }
        return valueRef as? String
    }

    static func value(of element: AXUIElement) -> String? {
        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success else {
            return nil
        }
        if let string = valueRef as? String {
            return string
        }
        if let attributed = valueRef as? NSAttributedString {
            return attributed.string
        }
        return nil
    }

    static func identifier(of element: AXUIElement) -> String? {
        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXIdentifierAttribute as CFString, &valueRef) == .success else {
            return nil
        }
        return valueRef as? String
    }

    static func parent(of element: AXUIElement) -> AXUIElement? {
        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &valueRef) == .success,
              let valueRef else {
            return nil
        }
        let object = valueRef as CFTypeRef
        guard CFGetTypeID(object) == AXUIElementGetTypeID() else { return nil }
        return (object as! AXUIElement)
    }

    /// Notification Center banners carry the posting app's bundle ID in `AXStackingIdentifier`
    /// (modern macOS). Returns nil on older systems or non-banner elements.
    static func stackingIdentifier(of element: AXUIElement) -> String? {
        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, "AXStackingIdentifier" as CFString, &valueRef) == .success else {
            return nil
        }
        return valueRef as? String
    }

    static func isHidden(_ element: AXUIElement) -> Bool {
        var hiddenRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXHiddenAttribute as CFString, &hiddenRef) == .success,
           let hidden = hiddenRef as? Bool, hidden {
            return true
        }
        return false
    }

    static func frame(of element: AXUIElement) -> CGRect? {
        guard let origin = point(for: element, attribute: kAXPositionAttribute as CFString),
              let size = size(for: element, attribute: kAXSizeAttribute as CFString),
              size.width > 0, size.height > 0 else {
            return nil
        }
        return CGRect(origin: origin, size: size)
    }

    static func press(_ element: AXUIElement) -> Bool {
        AXUIElementPerformAction(element, kAXPressAction as CFString) == .success
    }

    /// Performs the banner's "Close" accessibility action (localized), searching the element
    /// and its descendants. Returns true when a close action was found and performed.
    static func performCloseAction(on element: AXUIElement, depth: Int = 0) -> Bool {
        guard depth < 5 else { return false }

        if performMatchingAction(on: element, matching: closeActionKeywords) {
            return true
        }

        for child in children(of: element) {
            if performCloseAction(on: child, depth: depth + 1) {
                return true
            }
        }
        return false
    }

    private static func performMatchingAction(on element: AXUIElement, matching keywords: [String]) -> Bool {
        var namesRef: CFArray?
        guard AXUIElementCopyActionNames(element, &namesRef) == .success,
              let names = namesRef as? [String] else {
            return false
        }

        for name in names {
            let lowerName = name.lowercased()
            var matches = keywords.contains { lowerName.contains($0) }

            if !matches {
                var descriptionRef: CFString?
                if AXUIElementCopyActionDescription(element, name as CFString, &descriptionRef) == .success,
                   let description = (descriptionRef as String?)?.lowercased() {
                    matches = keywords.contains { description.contains($0) }
                }
            }

            if matches {
                return AXUIElementPerformAction(element, name as CFString) == .success
            }
        }
        return false
    }

    /// Localized names/descriptions of the notification banner close action (en, pl, de, it, es).
    private static let closeActionKeywords = [
        "close", "clear",
        "zamknij", "wyczyść", "usuń",
        "schließen", "entfernen", "löschen",
        "chiudi", "cancella", "rimuovi",
        "cerrar", "borrar", "eliminar"
    ]

    static func runningApplication(bundleID: String) -> NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
    }

    static func notificationCenterPID() -> pid_t? {
        let bundleIDs = [
            "com.apple.notificationcenterui",
            "com.apple.notificationcenter"
        ]

        for bundleID in bundleIDs {
            if let app = runningApplication(bundleID: bundleID) {
                return app.processIdentifier
            }
        }
        return nil
    }

    private static func point(for element: AXUIElement, attribute: CFString) -> CGPoint? {
        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &valueRef) == .success,
              let valueRef else {
            return nil
        }

        var point = CGPoint.zero
        guard AXValueGetValue(valueRef as! AXValue, .cgPoint, &point) else {
            return nil
        }
        return point
    }

    private static func size(for element: AXUIElement, attribute: CFString) -> CGSize? {
        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &valueRef) == .success,
              let valueRef else {
            return nil
        }

        var size = CGSize.zero
        guard AXValueGetValue(valueRef as! AXValue, .cgSize, &size) else {
            return nil
        }
        return size
    }
}
