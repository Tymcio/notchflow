import AppKit
import ApplicationServices
import Foundation

/// An `AXObserver` plus what is needed to (re)register it, handed to the scan queue.
/// `@unchecked Sendable`: AX handles are immutable CF references usable from any thread;
/// `refcon` is an opaque pointer that is only passed back to the AX API.
struct AXObserverHandle: @unchecked Sendable {
    let observer: AXObserver
    let pid: pid_t
    let refcon: UnsafeMutableRawPointer
}

/// Walks Notification Center's Accessibility tree on a private serial queue — never on the
/// main thread — and turns banner-like elements into `ParsedNotificationBanner`s.
///
/// Every element gets the short `AXHelpers.messagingTimeout`, and a whole scan is capped by
/// a node budget and a wall-clock budget, so a hung Notification Center costs at most a
/// couple of seconds of a background thread instead of blocking the UI.
final class NotificationBannerScanner: @unchecked Sendable {
    /// Serial queue for every AX read/write this scanner performs. Holds no other state.
    private let queue = DispatchQueue(label: "NotchFlow.NotificationBannerScanner", qos: .utility)

    static let maxBannerDepth = 10
    static let maxNodesPerPID = 1_000
    static let maxNodesPerBanner = 400
    static let maxSubtreeDepth = 14
    static let scanTimeBudget: TimeInterval = 1.5

    static let observedNotifications: [String] = [
        kAXWindowCreatedNotification,
        kAXCreatedNotification,
        kAXUIElementDestroyedNotification,
        kAXLayoutChangedNotification,
    ]

    func scan(pids: [pid_t]) async -> [ParsedNotificationBanner] {
        await run { Self.scanSynchronously(pids: pids) }
    }

    /// Runs `work` on the scan queue (serialised with scans) and returns its result.
    func run<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: work()) }
        }
    }

    // MARK: - Observer registration

    /// A window that just appeared, to be observed with an existing observer.
    struct WindowRegistration: @unchecked Sendable {
        let handle: AXObserverHandle
        let element: AXUIElement
    }

    /// Registers for banner-related notifications on the app element and its current windows.
    static func register(_ handle: AXObserverHandle) {
        let app = AXHelpers.applicationElement(pid: handle.pid)
        register(handle, on: app)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement] else { return }
        for window in windows {
            AXUIElementSetMessagingTimeout(window, AXHelpers.messagingTimeout)
            register(handle, on: window)
        }
    }

    /// Toast groups are created under existing windows, so each window is observed too.
    static func register(_ handle: AXObserverHandle, on element: AXUIElement) {
        for notification in observedNotifications {
            _ = AXObserverAddNotification(handle.observer, element, notification as CFString, handle.refcon)
        }
    }

    // MARK: - Scanning

    private struct Budget {
        var nodes: Int
        let deadline: DispatchTime

        var isExhausted: Bool {
            nodes <= 0 || DispatchTime.now() >= deadline
        }

        mutating func consume() -> Bool {
            guard !isExhausted else { return false }
            nodes -= 1
            return true
        }
    }

    static func scanSynchronously(pids: [pid_t]) -> [ParsedNotificationBanner] {
        let deadline = DispatchTime.now() + scanTimeBudget
        var banners: [ParsedNotificationBanner] = []
        var seenKeys = Set<String>()

        for pid in pids {
            guard DispatchTime.now() < deadline else { break }
            let app = AXHelpers.applicationElement(pid: pid)
            guard mayHaveBanners(app) else { continue }

            var budget = Budget(nodes: maxNodesPerPID, deadline: deadline)
            var found: [ParsedNotificationBanner] = []
            collectBanners(from: app, depth: 0, inheritedHint: nil, budget: &budget, into: &found)
            for banner in found where seenKeys.insert(banner.fingerprint).inserted {
                banners.append(banner)
            }
        }
        return banners
    }

    /// Cheap top-level check so idle Notification Center trees are not walked.
    static func mayHaveBanners(_ app: AXUIElement) -> Bool {
        for child in AXHelpers.children(of: app) {
            if AXHelpers.isHidden(child) { continue }
            // Tahoe hosts toasts inside a full-screen AXSystemDialog ("Notification Center").
            if AXHelpers.subrole(of: child) == "AXSystemDialog" {
                return true
            }
            let title = (AXHelpers.title(of: child) ?? "").lowercased()
            if notificationCenterTitleMarks.contains(where: { title.contains($0) }) {
                return true
            }
            guard let frame = AXHelpers.frame(of: child) else { continue }
            if frame.width >= 180, frame.height >= 36, frame.height <= 360 {
                return true
            }
        }
        return false
    }

    /// "Notification Center" window titles in en, pl, de, it/es.
    private static let notificationCenterTitleMarks = ["notification", "powiadom", "mitteilung", "notifica"]

    private static func collectBanners(
        from element: AXUIElement,
        depth: Int,
        inheritedHint: String?,
        budget: inout Budget,
        into results: inout [ParsedNotificationBanner]
    ) {
        guard depth < maxBannerDepth, budget.consume() else { return }

        // The stacking identifier sits on the banner window or an ancestor group; walking
        // top-down, the nearest ancestor's hint is the inherited one.
        let hint = bundleHint(of: element) ?? inheritedHint

        if let snapshot = snapshot(of: element, hint: hint, deadline: budget.deadline),
           let parsed = NotificationBannerParser.parse(snapshot) {
            results.append(parsed)
            // Banner groups already contain title/body — don't re-parse their static texts.
            if snapshot.isNotificationCenterBanner { return }
        }

        for child in AXHelpers.children(of: element) {
            if AXHelpers.isHidden(child) { continue }
            guard !budget.isExhausted else { break }
            collectBanners(from: child, depth: depth + 1, inheritedHint: hint, budget: &budget, into: &results)
        }
    }

    private static func bundleHint(of element: AXUIElement) -> String? {
        if let bundleID = NotificationAppCatalog.bundleID(fromStackingIdentifier: AXHelpers.stackingIdentifier(of: element)) {
            return bundleID
        }
        return NotificationAppCatalog.bundleID(fromStackingIdentifier: AXHelpers.identifier(of: element))
    }

    /// Reads one candidate element and its subtree in a single walk.
    private static func snapshot(
        of element: AXUIElement,
        hint: String?,
        deadline: DispatchTime
    ) -> NotificationBannerSnapshot? {
        guard let frame = AXHelpers.frame(of: element),
              NotificationBannerParser.frameCanBeBanner(frame) else { return nil }
        let role = AXHelpers.role(of: element) ?? ""
        guard role != "AXApplication", role != "AXSystemWide" else { return nil }
        let isNCBanner = AXHelpers.isNotificationCenterBanner(element)

        let plainBannerShape = NotificationBannerParser.allowedRoles.contains(role)
            && frame.width >= 180 && frame.height >= 36
        if !isNCBanner, !plainBannerShape {
            // Only a call-shaped element (two or more buttons) can still qualify.
            var countBudget = Budget(nodes: maxNodesPerBanner, deadline: deadline)
            var count = 0
            countButtons(in: element, depth: 0, knownRole: role, count: &count, budget: &countBudget)
            guard count >= 2 else { return nil }
        }

        var snapshot = NotificationBannerSnapshot(
            frame: frame,
            role: role,
            isNotificationCenterBanner: isNCBanner,
            deliveringBundleHint: hint
        )
        snapshot.element = element
        snapshot.attributedDescription = AXHelpers.attributedDescription(of: element)

        var walk = SubtreeWalk(budget: Budget(nodes: maxNodesPerBanner, deadline: deadline))
        walk.visit(element, depth: 0, knownRole: role)

        snapshot.iconTexts = walk.icons
        snapshot.otherTexts = walk.others
        snapshot.structured = walk.structured
        snapshot.buttons = walk.buttons.map(\.info)
        snapshot.replyField = walk.textField
        let keywordButtons = walk.buttons.filter {
            $0.info.role == "AXButton" && $0.info.depth < NotificationBannerActions.keywordSearchDepth
        }
        snapshot.replyButton = keywordButtons.first(where: {
            NotificationBannerActions.replyKeywords.contains(where: $0.info.keywordText.contains)
        })?.element ?? keywordButtons.first(where: {
            NotificationBannerActions.sendKeywords.contains(where: $0.info.keywordText.contains)
        })?.element
        return snapshot
    }

    private static func countButtons(
        in element: AXUIElement,
        depth: Int,
        knownRole: String? = nil,
        count: inout Int,
        budget: inout Budget
    ) {
        guard depth < maxSubtreeDepth, count < 2, budget.consume() else { return }
        let role = knownRole ?? AXHelpers.role(of: element) ?? ""
        if NotificationBannerParser.buttonRoles.contains(role) {
            count += 1
        }
        for child in AXHelpers.children(of: element) {
            countButtons(in: child, depth: depth + 1, count: &count, budget: &budget)
        }
    }

    /// One depth-first pass collecting text parts, structured fields, buttons and the reply field.
    private struct SubtreeWalk {
        var budget: Budget
        var icons: [String] = []
        var others: [String] = []
        var structured = NotificationBannerStructuredFields()
        var buttons: [(info: NotificationBannerButton, element: AXUIElement)] = []
        var textField: AXUIElement?

        private static let structuredDepth = 6
        private static let textDepth = 8
        private static let structuredIdentifiers: Set<String> = [
            "title", "subtitle", "body", "message", "appname", "app", "application",
        ]

        init(budget: Budget) {
            self.budget = budget
        }

        mutating func visit(_ element: AXUIElement, depth: Int, knownRole: String? = nil) {
            guard depth < NotificationBannerScanner.maxSubtreeDepth, budget.consume() else { return }
            let role = knownRole ?? AXHelpers.role(of: element) ?? ""
            let reader = AttributeReader(element: element)

            if depth < Self.structuredDepth {
                readStructuredField(reader)
            }
            if depth < Self.textDepth {
                readTextPart(reader, role: role)
            }
            if NotificationBannerParser.buttonRoles.contains(role) {
                let accessibilityText = [reader.title, reader.description, reader.value]
                    .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
                    .lowercased()
                let keywordText = [reader.title, reader.description, reader.label, reader.value]
                    .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                    .joined(separator: " ")
                buttons.append((
                    NotificationBannerButton(
                        role: role,
                        accessibilityText: accessibilityText,
                        keywordText: keywordText,
                        depth: depth
                    ),
                    element
                ))
            }
            if textField == nil,
               depth < NotificationBannerActions.keywordSearchDepth,
               role == "AXTextField" || role == "AXTextArea" {
                textField = element
            }

            for child in AXHelpers.children(of: element) {
                visit(child, depth: depth + 1)
            }
        }

        private mutating func readStructuredField(_ reader: AttributeReader) {
            let identifier = (reader.identifier ?? "").lowercased()
            guard Self.structuredIdentifiers.contains(identifier) else { return }
            let value = reader.value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !value.isEmpty, !NotificationAppCatalog.isInternalAccessibilityLabel(value) else { return }
            switch identifier {
            case "title":
                if structured.title == nil { structured.title = value }
                if NotificationAppCatalog.isExactAppName(value), structured.appName == nil {
                    structured.appName = value
                }
            case "subtitle":
                if structured.subtitle == nil { structured.subtitle = value }
            case "body", "message":
                if structured.body == nil { structured.body = value }
            default:
                if structured.appName == nil { structured.appName = value }
            }
        }

        private mutating func readTextPart(_ reader: AttributeReader, role: String) {
            if role == "AXStaticText" || role == "AXTextArea" || role == "AXTextField" {
                for read in [\AttributeReader.value, \.title, \.description, \.label, \.help] {
                    if let text = reader[keyPath: read]?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !text.isEmpty,
                       !NotificationAppCatalog.isInternalAccessibilityLabel(text) {
                        others.append(text)
                        break
                    }
                }
            } else if role == "AXImage" {
                var nodeIcons: [String] = []
                for read in [\AttributeReader.description, \.title, \.label, \.help] {
                    guard let raw = reader[keyPath: read]?.trimmingCharacters(in: .whitespacesAndNewlines),
                          !raw.isEmpty,
                          let label = NotificationAppCatalog.iconIdentityLabel(fromAccessibilityLabel: raw),
                          !nodeIcons.contains(label) else { continue }
                    nodeIcons.append(label)
                }
                icons.append(contentsOf: nodeIcons)
            } else if role != "AXButton",
                      let title = reader.title?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !title.isEmpty,
                      !NotificationAppCatalog.isInternalAccessibilityLabel(title) {
                others.append(title)
            }
        }
    }

    /// Lazily reads and caches string attributes of one element (each read is an IPC round trip).
    private final class AttributeReader {
        let element: AXUIElement
        private var cache: [String: String?] = [:]

        init(element: AXUIElement) {
            self.element = element
        }

        private func cached(_ key: String, _ read: (AXUIElement) -> String?) -> String? {
            if let hit = cache[key] { return hit }
            let value = read(element)
            cache[key] = .some(value)
            return value
        }

        var value: String? { cached("value", AXHelpers.value(of:)) }
        var title: String? { cached("title", AXHelpers.title(of:)) }
        var description: String? { cached("description", AXHelpers.description(of:)) }
        var label: String? { cached("label", AXHelpers.label(of:)) }
        var help: String? { cached("help", AXHelpers.help(of:)) }
        var identifier: String? { cached("identifier", AXHelpers.identifier(of:)) }
    }
}
