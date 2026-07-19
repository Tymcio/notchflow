import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import ScreenCaptureKit
import Vision

/// Continuity call card helpers: locate window, OCR caller, click Answer/Decline.
///
/// On Tahoe the Continuity photo card has no window of its own — it is drawn inside a
/// full-screen transparent "Notification Center" window (layer ~21) that appears only
/// while the card is up. We capture that window and derive the card rect from the
/// opaque pixel bounding box.
///
/// All captures go through ScreenCaptureKit: the legacy `CGWindowListCreateImage`
/// pins the macOS "is recording your screen" indicator until the app quits, while
/// SCK screenshots are session-scoped and the indicator clears after each shot.
@MainActor
enum ContinuityCallActions {
    struct Card {
        let windowID: CGWindowID
        let ownerPID: pid_t
        /// Card rect in CG global coordinates (y down from top-left of main display).
        let cgRect: CGRect
        /// Captured image of the card (cropped), when the full-screen host path was used.
        let image: CGImage?
    }

    /// Gate for the screen-capture card search. Captures light up the macOS
    /// screen-recording indicator, so they are allowed only while a call is ringing.
    static var captureAllowed = false {
        didSet {
            if captureAllowed, !oldValue {
                // New ring — the previous card/OCR memo no longer applies.
                cachedCard = nil
                ocrMemo = nil
            }
        }
    }

    private static var cachedCard: (at: Date, card: Card?)?

    static func findCard() async -> Card? {
        // The card does not move during a ring: once located, only verify the host
        // window is still on screen (cheap metadata read, no capture).
        if let cached = cachedCard, let card = cached.card {
            if isWindowOnScreen(card.windowID) {
                cachedCard = (.now, card)
                return card
            }
            cachedCard = nil
        } else if let cached = cachedCard, Date().timeIntervalSince(cached.at) < 0.5 {
            // Recent miss — don't hammer SCK with rescans.
            return nil
        }
        let card = await locateCard()
        cachedCard = (.now, card)
        return card
    }

    /// Last successfully located card, even slightly stale — used for Answer/Decline
    /// clicks that must stay synchronous. The cover/OCR pollers keep this cache warm
    /// for the whole ring.
    static func recentCard(maxAge: TimeInterval) -> Card? {
        if let cached = cachedCard, let card = cached.card {
            if Date().timeIntervalSince(cached.at) <= maxAge || isWindowOnScreen(card.windowID) {
                return card
            }
        }
        return locateStandaloneCardWindow()
    }

    private static func locateCard() async -> Card? {
        if let standalone = locateStandaloneCardWindow() {
            return standalone
        }
        guard let host = locateFullScreenNCHost() else { return nil }
        return await cardFromFullScreenHost(
            windowID: host.windowID,
            pid: host.pid,
            hostBounds: host.bounds
        )
    }

    /// Pre-Tahoe: the Continuity card is its own mid-sized window near the top of a screen.
    /// Window enumeration here reads no window titles, so it does not touch the
    /// screen-recording TCC surface.
    private static func locateStandaloneCardWindow() -> Card? {
        guard let info = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return nil }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        var best: (score: Int, card: Card)?

        for window in info {
            guard let parsed = parseWindow(window), parsed.pid != pid_t(ownPID) else { continue }
            guard parsed.layer > 0 else { continue }
            if isExcludedOwner(pid: parsed.pid, ownerName: parsed.ownerName) { continue }

            let rect = parsed.rect
            guard rect.width >= 200, rect.width <= 900, rect.height >= 160, rect.height <= 1000 else {
                continue
            }
            guard isNearTopOfItsScreen(rect) else { continue }

            let haystack = ownerHaystack(pid: parsed.pid, ownerName: parsed.ownerName)
            let isCallHost = haystack.contains("mobilephone") || haystack.contains("facetime")
                || haystack.contains("phone") || haystack.contains("callkit")
                || haystack.contains("telephony")

            var score = Int(rect.width * rect.height / 100)
            if isCallHost { score += 50_000 }
            if rect.height >= 280 { score += 10_000 }

            let card = Card(windowID: parsed.windowID, ownerPID: parsed.pid, cgRect: rect, image: nil)
            if best == nil || score > best!.score {
                best = (score, card)
            }
        }
        return best?.card
    }

    private static func locateFullScreenNCHost() -> (windowID: CGWindowID, pid: pid_t, bounds: CGRect)? {
        guard let info = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return nil }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        for window in info {
            guard let parsed = parseWindow(window), parsed.pid != pid_t(ownPID) else { continue }
            guard parsed.layer >= 15 else { continue }
            let haystack = ownerHaystack(pid: parsed.pid, ownerName: parsed.ownerName)
            let isNCOwner = haystack.contains("notificationcenter") || haystack.contains("powiadom")
                || haystack.contains("notification")
            guard isNCOwner, isRoughlyFullScreen(parsed.rect) else { continue }
            return (parsed.windowID, parsed.pid, parsed.rect)
        }
        return nil
    }

    private struct ParsedWindow {
        let windowID: CGWindowID
        let pid: pid_t
        let rect: CGRect
        let layer: Int
        let ownerName: String
    }

    private static func parseWindow(_ window: [String: Any]) -> ParsedWindow? {
        guard let windowID = window[kCGWindowNumber as String] as? CGWindowID,
              let pid = window[kCGWindowOwnerPID as String] as? pid_t,
              let bounds = window[kCGWindowBounds as String] as? [String: Any],
              let width = number(bounds["Width"]),
              let height = number(bounds["Height"]),
              let x = number(bounds["X"]),
              let y = number(bounds["Y"])
        else { return nil }
        return ParsedWindow(
            windowID: windowID,
            pid: pid,
            rect: CGRect(x: x, y: y, width: width, height: height),
            layer: window[kCGWindowLayer as String] as? Int ?? 0,
            ownerName: window[kCGWindowOwnerName as String] as? String ?? ""
        )
    }

    private static func ownerHaystack(pid: pid_t, ownerName: String) -> String {
        let bundle = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier?.lowercased() ?? ""
        return bundle + " " + ownerName.lowercased()
    }

    private static func isExcludedOwner(pid: pid_t, ownerName: String) -> Bool {
        let haystack = ownerHaystack(pid: pid, ownerName: ownerName)
        return excludedOverlayOwners.contains { haystack.contains($0) }
    }

    /// Captures the transparent full-screen NC window (via ScreenCaptureKit) and finds
    /// the card as the opaque pixel bounding box.
    private static func cardFromFullScreenHost(
        windowID: CGWindowID,
        pid: pid_t,
        hostBounds: CGRect
    ) async -> Card? {
        guard captureAllowed else { return nil }
        guard CGPreflightScreenCaptureAccess() else { return nil }
        guard let image = await sckWindowImage(windowID: windowID, pointSize: hostBounds.size) else {
            return nil
        }
        // Pixel scan over a full-screen bitmap — keep it off the main actor.
        guard let bboxPixels = await Task.detached(priority: .userInitiated, operation: {
            opaqueBoundingBox(of: image)
        }).value else { return nil }

        let scaleX = hostBounds.width / CGFloat(image.width)
        let scaleY = hostBounds.height / CGFloat(image.height)
        let cardRect = CGRect(
            x: hostBounds.minX + bboxPixels.minX * scaleX,
            y: hostBounds.minY + bboxPixels.minY * scaleY,
            width: bboxPixels.width * scaleX,
            height: bboxPixels.height * scaleY
        )

        // Sanity: the Continuity card is a mid-sized panel, not a sliver or the whole screen.
        guard cardRect.width >= 180, cardRect.width <= hostBounds.width * 0.6,
              cardRect.height >= 140, cardRect.height <= hostBounds.height * 0.7
        else { return nil }

        let cropped = image.cropping(to: bboxPixels)
        return Card(windowID: windowID, ownerPID: pid, cgRect: cardRect, image: cropped)
    }

    /// One-shot SCK screenshot of a single window. Session-scoped: the privacy
    /// indicator lights only for the duration of the capture.
    private static func sckWindowImage(windowID: CGWindowID, pointSize: CGSize) async -> CGImage? {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        ) else { return nil }
        guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
            return nil
        }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        // Nominal (1x) resolution is enough for the alpha bounding box and OCR of a
        // large-print card.
        config.width = max(1, Int(pointSize.width))
        config.height = max(1, Int(pointSize.height))
        config.showsCursor = false
        config.scalesToFit = true
        return try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    /// SCK screenshot of the display region behind the card (excludes the card's host
    /// window and NotchFlow's own windows) — used by the cover panel.
    static func imageBehindCard(_ card: Card) async -> CGImage? {
        guard captureAllowed, CGPreflightScreenCaptureAccess() else { return nil }
        guard let content = try? await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        ) else { return nil }

        let display = content.displays.first { display in
            CGRect(x: display.frame.origin.x, y: display.frame.origin.y,
                   width: display.frame.width, height: display.frame.height)
                .intersects(card.cgRect)
        } ?? content.displays.first
        guard let display else { return nil }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        let excluded = content.windows.filter {
            $0.windowID == card.windowID || $0.owningApplication?.processID == pid_t(ownPID)
        }
        let filter = SCContentFilter(display: display, excludingWindows: excluded)

        let config = SCStreamConfiguration()
        config.sourceRect = CGRect(
            x: card.cgRect.minX - display.frame.minX,
            y: card.cgRect.minY - display.frame.minY,
            width: card.cgRect.width,
            height: card.cgRect.height
        )
        config.width = max(1, Int(card.cgRect.width))
        config.height = max(1, Int(card.cgRect.height))
        config.showsCursor = false
        return try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    /// Rect (in image pixels) of the Continuity card inside the transparent host window.
    ///
    /// The host can contain several opaque islands at once (call card + a regular
    /// banner + widgets), so a plain bounding box of all opaque pixels unions them
    /// into nonsense. Instead: find connected opaque components on a downsampled
    /// grid and pick the most card-like one (mid-sized, closest to the top).
    nonisolated private static func opaqueBoundingBox(of image: CGImage) -> CGRect? {
        let width = image.width
        let height = image.height
        let bytesPerRow = width * 4
        var data = [UInt8](repeating: 0, count: bytesPerRow * height)
        guard let ctx = CGContext(
            data: &data,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Downsample to a coarse grid; the card is hundreds of pixels wide.
        let step = 8
        let gridW = (width + step - 1) / step
        let gridH = (height + step - 1) / step
        var opaque = [Bool](repeating: false, count: gridW * gridH)
        for gy in 0..<gridH {
            // Bitmap row 0 = top scanline = CG global y direction (down): no flip needed.
            let rowStart = (gy * step) * bytesPerRow
            for gx in 0..<gridW where data[rowStart + (gx * step) * 4 + 3] > 220 {
                opaque[gy * gridW + gx] = true
            }
        }

        // Flood-fill connected components (4-neighbour) on the grid.
        var visited = [Bool](repeating: false, count: gridW * gridH)
        var best: (score: CGFloat, rect: CGRect)?
        var stack: [Int] = []
        for start in 0..<(gridW * gridH) where opaque[start] && !visited[start] {
            var minX = gridW, minY = gridH, maxX = 0, maxY = 0
            var cells = 0
            stack.removeAll(keepingCapacity: true)
            stack.append(start)
            visited[start] = true
            while let idx = stack.popLast() {
                let x = idx % gridW
                let y = idx / gridW
                cells += 1
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
                if x > 0, opaque[idx - 1], !visited[idx - 1] { visited[idx - 1] = true; stack.append(idx - 1) }
                if x < gridW - 1, opaque[idx + 1], !visited[idx + 1] { visited[idx + 1] = true; stack.append(idx + 1) }
                if y > 0, opaque[idx - gridW], !visited[idx - gridW] { visited[idx - gridW] = true; stack.append(idx - gridW) }
                if y < gridH - 1, opaque[idx + gridW], !visited[idx + gridW] { visited[idx + gridW] = true; stack.append(idx + gridW) }
            }

            let rect = CGRect(
                x: minX * step,
                y: minY * step,
                width: (maxX - minX + 1) * step,
                height: (maxY - minY + 1) * step
            )
            // Card-like: mid-sized, top part of the screen, reasonably filled.
            guard rect.width >= 180, rect.width <= CGFloat(width) * 0.6,
                  rect.height >= 120, rect.height <= CGFloat(height) * 0.7,
                  rect.minY < CGFloat(height) * 0.5
            else { continue }
            let fill = CGFloat(cells) / ((rect.width / CGFloat(step)) * (rect.height / CGFloat(step)))
            guard fill > 0.5 else { continue }

            // Prefer larger, higher components (the card over stray toasts below it).
            let score = rect.width * rect.height - rect.minY * 50
            if best == nil || score > best!.score {
                best = (score, rect)
            }
        }
        return best?.rect
    }

    /// Cheap liveness check (window metadata only, no capture, no TCC surface).
    static func isWindowOnScreen(_ windowID: CGWindowID) -> Bool {
        guard let info = CGWindowListCopyWindowInfo(.optionIncludingWindow, windowID)
            as? [[String: Any]] else { return false }
        return !info.isEmpty
    }

    private static func isRoughlyFullScreen(_ rect: CGRect) -> Bool {
        for screen in NSScreen.screens {
            if rect.width >= screen.frame.width * 0.95, rect.height >= screen.frame.height * 0.85 {
                return true
            }
        }
        return false
    }

    private static let excludedOverlayOwners: [String] = [
        "dock", "windowserver", "spotlight", "screencapture", "zrzut ekranu", "notchflow",
        "controlcenter", "control center", "centrum sterowania",
        "wallpaper", "loginwindow", "sirinc", "siri",
    ]

    /// CG global coords: y grows downward from the top-left of the main display.
    /// The Continuity card sits in the top ~40% of its own screen.
    private static func isNearTopOfItsScreen(_ rect: CGRect) -> Bool {
        for screen in NSScreen.screens {
            guard let mainScreen = NSScreen.screens.first else { continue }
            // Convert AppKit screen frame to CG coords (flip around main screen top).
            let cgScreenTop = mainScreen.frame.maxY - screen.frame.maxY
            let cgScreen = CGRect(
                x: screen.frame.minX,
                y: cgScreenTop,
                width: screen.frame.width,
                height: screen.frame.height
            )
            if cgScreen.intersects(rect) {
                return rect.minY - cgScreen.minY < cgScreen.height * 0.4
            }
        }
        return rect.minY < 500
    }

    /// One-line dump of top-of-screen windows — diagnostics for card detection misses.
    static func debugWindowSummary() -> String {
        guard let info = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return "cgwindowlist=nil" }

        var parts: [String] = []
        for window in info {
            guard let parsed = parseWindow(window) else { continue }
            let rect = parsed.rect
            guard rect.width >= 150, rect.height >= 100, rect.minY < 500 else { continue }
            let owner = parsed.ownerName.isEmpty
                ? (NSRunningApplication(processIdentifier: parsed.pid)?.bundleIdentifier ?? "pid\(parsed.pid)")
                : parsed.ownerName
            parts.append("\(owner):\(Int(rect.width))x\(Int(rect.height))@y\(Int(rect.minY))L\(parsed.layer)")
        }
        return parts.isEmpty ? "none>=150x100" : parts.joined(separator: " | ")
    }

    private static var ocrMemo: (windowID: CGWindowID, attempts: Int, result: String?)?

    static func ocrCallerName() async -> String? {
        guard captureAllowed else { return nil }
        if !CGPreflightScreenCaptureAccess() {
            _ = CGRequestScreenCaptureAccess()
            return nil
        }
        guard let card = await findCard() else { return nil }
        // Vision "accurate" recognition stalls the main actor for ~100ms+; the card
        // content is static, so don't re-run it all ring long.
        if let memo = ocrMemo, memo.windowID == card.windowID {
            if let result = memo.result { return result }
            if memo.attempts >= 3 { return nil }
        } else {
            ocrMemo = (card.windowID, 0, nil)
        }
        ocrMemo = (card.windowID, (ocrMemo?.attempts ?? 0) + 1, nil)
        let image: CGImage
        if let captured = card.image {
            image = captured
        } else if let fresh = await sckWindowImage(windowID: card.windowID, pointSize: card.cgRect.size) {
            image = fresh
        } else {
            return nil
        }

        let lines = await recognizeTextLinesOffMain(in: image)
        var name: String?
        for index in lines.indices where name == nil {
            guard NotificationAppCatalog.isContinuityCallSubtitle(lines[index]) else { continue }
            for candidate in lines[..<index].reversed()
            where NotificationAppCatalog.isPlausibleCallerName(candidate) {
                name = candidate
                break
            }
        }
        name = name ?? lines.first { NotificationAppCatalog.isPlausibleCallerName($0) }
        if let name {
            ocrMemo = (card.windowID, ocrMemo?.attempts ?? 1, name)
        }
        return name
    }

    /// Presses Continuity Answer. When the card position is known, a synthetic click
    /// is instant; the AX-tree search (three app trees over IPC) is the slow fallback.
    @discardableResult
    static func pressAnswer() -> Bool {
        if clickCardControl(isAnswer: true) { return true }
        return pressAXButton(matching: answerKeywords)
    }

    @discardableResult
    static func pressDecline() -> Bool {
        if clickCardControl(isAnswer: false) { return true }
        return pressAXButton(matching: declineKeywords)
    }

    private static func pressAXButton(matching keywords: [String]) -> Bool {
        let pids: [pid_t] = {
            var list: [pid_t] = []
            if let card = recentCard(maxAge: 5) { list.append(card.ownerPID) }
            for bundleID in NotificationAppCatalog.callUIHostBundleIDs {
                if let app = AXHelpers.runningApplication(bundleID: bundleID) {
                    list.append(app.processIdentifier)
                }
            }
            for bundleID in ["com.apple.notificationcenterui", "com.apple.UserNotificationCenter"] {
                if let app = AXHelpers.runningApplication(bundleID: bundleID) {
                    list.append(app.processIdentifier)
                }
            }
            return Array(Set(list))
        }()

        for pid in pids {
            let root = AXUIElementCreateApplication(pid)
            if let button = findButton(in: root, matching: keywords, depth: 0, budget: 200) {
                if AXHelpers.press(button) { return true }
            }
        }
        return false
    }

    /// Continuity card: green Answer pill on top, red Decline pill below it (top-right corner).
    private static func clickCardControl(isAnswer: Bool) -> Bool {
        // The ring state may have just flipped (captures gated off) — a card located
        // in the last few seconds is still positionally valid.
        guard let card = recentCard(maxAge: 5) else { return false }
        let rect = card.cgRect
        let x = rect.maxX - max(40, rect.width * 0.15)
        let answerY = rect.minY + max(20, rect.height * 0.07)
        let declineY = rect.minY + max(46, rect.height * 0.155)
        return click(at: CGPoint(x: x, y: isAnswer ? answerY : declineY))
    }

    private static func click(at point: CGPoint) -> Bool {
        let down = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseDown,
            mouseCursorPosition: point,
            mouseButton: .left
        )
        let up = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseUp,
            mouseCursorPosition: point,
            mouseButton: .left
        )
        guard let down, let up else { return false }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }

    private static func findButton(
        in element: AXUIElement,
        matching keywords: [String],
        depth: Int,
        budget: Int
    ) -> AXUIElement? {
        var remaining = budget
        return findButton(in: element, matching: keywords, depth: depth, budget: &remaining)
    }

    private static func findButton(
        in element: AXUIElement,
        matching keywords: [String],
        depth: Int,
        budget: inout Int
    ) -> AXUIElement? {
        guard depth < 10, budget > 0 else { return nil }
        budget -= 1
        let role = AXHelpers.role(of: element) ?? ""
        if role == "AXButton" || role == "AXCheckBox" {
            let hay = [
                AXHelpers.title(of: element),
                AXHelpers.description(of: element),
                AXHelpers.label(of: element),
                AXHelpers.help(of: element),
            ].compactMap { $0?.lowercased() }.joined(separator: " ")
            if keywords.contains(where: { hay.contains($0) }) {
                return element
            }
        }
        for child in AXHelpers.children(of: element) {
            if let found = findButton(in: child, matching: keywords, depth: depth + 1, budget: &budget) {
                return found
            }
        }
        return nil
    }

    private static func recognizeTextLinesOffMain(in image: CGImage) async -> [String] {
        await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            request.recognitionLanguages = ["pl-PL", "en-US", "de-DE", "es-ES", "it-IT"]
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do { try handler.perform([request]) } catch { return [] }
            return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }.value
    }

    private static func number(_ value: Any?) -> CGFloat? {
        if let n = value as? NSNumber { return CGFloat(truncating: n) }
        if let d = value as? Double { return CGFloat(d) }
        return nil
    }

    private static let answerKeywords = [
        "answer", "accept", "odbierz", "annehmen", "rispondi", "accetta",
        "contestar", "responder", "aceptar",
    ]
    private static let declineKeywords = [
        "decline", "reject", "odrzuć", "odrzuc", "ablehnen", "rifiuta", "rechazar",
    ]
}
