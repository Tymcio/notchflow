import Foundation
import XCTest
@testable import NotchFlow

final class NotificationCatalogTests: XCTestCase {
    func testSupportedCatalogIncludesMessagingAppsAndMail() {
        let ids = Set(NotificationAppCatalog.supportedNotificationApps.map(\.bundleID))
        XCTAssertTrue(ids.contains("net.whatsapp.WhatsApp"))
        XCTAssertTrue(ids.contains("org.whispersystems.signal-desktop"))
        XCTAssertTrue(ids.contains("com.apple.MobileSMS"))
        XCTAssertTrue(ids.contains("com.apple.mail"))
        XCTAssertFalse(ids.contains("com.skype.skype"))
        XCTAssertFalse(ids.contains("com.rambox"))
        XCTAssertFalse(NotificationAppCatalog.isAggregator("com.rambox"))
        XCTAssertTrue(NotificationAppCatalog.isEmailApp("com.apple.mail"))
        XCTAssertTrue(NotificationAppCatalog.isMessagingApp("net.whatsapp.WhatsApp"))
        XCTAssertFalse(NotificationAppCatalog.isMessagingApp("com.apple.mail"))
        // Bundle IDs look like AX labels — catalog name must still win.
        XCTAssertEqual(NotificationAppCatalog.name(for: "com.facebook.archon"), "Messenger")
        XCTAssertEqual(NotificationAppCatalog.name(for: "org.whispersystems.signal-desktop"), "Signal")
    }

    func testResolvePrefersTrustedCatalogHintAndExactIconLabels() {
        let resolved = NotificationAppCatalog.resolve(
            iconTexts: ["Signal"],
            contentTexts: ["Alice", "Hello"],
            deliveringHint: "org.whispersystems.signal-desktop"
        )
        XCTAssertEqual(resolved.delivering, "org.whispersystems.signal-desktop")
        XCTAssertEqual(resolved.service, "org.whispersystems.signal-desktop")
        XCTAssertTrue(resolved.hasTrustedSource)

        let mail = NotificationAppCatalog.resolve(
            iconTexts: ["Mail"],
            contentTexts: ["Boss", "Quarterly report"],
            deliveringHint: "com.apple.mail"
        )
        XCTAssertEqual(mail.delivering, "com.apple.mail")
        XCTAssertTrue(NotificationAppCatalog.isEmailApp(mail.service))
    }

    func testSignalIdentitySurvivesReverseDNSAXLabelsAndPrivacyBanners() {
        XCTAssertEqual(
            NotificationAppCatalog.iconIdentityLabel(
                fromAccessibilityLabel: "org.whispersystems.signal-desktop"
            ),
            "Signal"
        )
        XCTAssertEqual(
            NotificationAppCatalog.matchMessagingAppFromIconLabels(
                in: ["org.whispersystems.signal-desktop"]
            )?.bundleID,
            "org.whispersystems.signal-desktop"
        )

        let privacy = NotificationAppCatalog.resolve(
            iconTexts: ["Signal"],
            contentTexts: [],
            deliveringHint: "org.whispersystems.signal-desktop"
        )
        XCTAssertEqual(privacy.delivering, "org.whispersystems.signal-desktop")
        XCTAssertEqual(privacy.service, "org.whispersystems.signal-desktop")
        XCTAssertEqual(privacy.displayName, "Signal")

        // Generic system header alone is not readable — hub synthesizes a presence ping.
        XCTAssertFalse(
            NotificationAppCatalog.isReadableNotificationText(
                title: "Powiadomienie",
                body: ""
            )
        )
    }

    func testForeignPosterStaysForeign() {
        let resolved = NotificationAppCatalog.resolve(
            iconTexts: ["Cursor"],
            contentTexts: ["Agent finished", "Build completed"],
            deliveringHint: "com.todesktop.230313mzl4w4u92"
        )
        XCTAssertEqual(resolved.delivering, "com.todesktop.230313mzl4w4u92")
        XCTAssertEqual(resolved.service, "unknown.app")
    }

    func testCallHostBundleIDsResolveToPhoneOrFaceTime() {
        let phone = NotificationAppCatalog.name(for: "com.apple.mobilephone")
        XCTAssertNotEqual(phone, "Powiadomienie")
        XCTAssertNotEqual(phone, "Notification")
        XCTAssertTrue(phone == "Phone" || phone == "Telefon" || !phone.contains("."))

        let faceTime = NotificationAppCatalog.name(for: "com.apple.FaceTime")
        XCTAssertNotEqual(faceTime, "Powiadomienie")
        XCTAssertNotEqual(faceTime, "Notification")
        XCTAssertTrue(
            faceTime.localizedCaseInsensitiveContains("FaceTime") || !faceTime.contains(".")
        )
    }

    func testWeekdayCalendarChromeIsNotAPlausibleCallerName() {
        XCTAssertFalse(NotificationAppCatalog.isPlausibleCallerName("NIEDZIELA"))
        XCTAssertFalse(NotificationAppCatalog.isPlausibleCallerName("niedziela"))
        XCTAssertFalse(NotificationAppCatalog.isPlausibleCallerName("Sunday"))
        XCTAssertFalse(NotificationAppCatalog.isPlausibleCallerName("19 LIPCA"))
        XCTAssertFalse(NotificationAppCatalog.isPlausibleCallerName("NIEDZIELA, 19 LIPCA"))
        XCTAssertTrue(NotificationAppCatalog.isCalendarChromeLabel("NIEDZIELA, 19 LIPCA"))
        XCTAssertFalse(NotificationAppCatalog.isCalendarChromeLabel("Ada Nowak"))
        XCTAssertTrue(NotificationAppCatalog.isPlausibleCallerName("Ada Nowak"))
        XCTAssertTrue(NotificationAppCatalog.isPlausibleCallerName("Martyna Tymków"))
        XCTAssertTrue(NotificationAppCatalog.isContinuityCallSubtitle("Z Twojego iPhone'a"))
        XCTAssertFalse(
            NotificationAppCatalog.isPlausibleCallerName(
                "„NotchFlow” chce uzyskać dostęp do Twoich kontaktów."
            )
        )
        XCTAssertTrue(NotificationAppCatalog.isSystemCallUILabel("Kamera (iPhone (Marcin))"))
        XCTAssertTrue(NotificationAppCatalog.isContinuityDeviceRouteLabel("Mikrofon (iPhone (Marcin))"))
        XCTAssertFalse(NotificationAppCatalog.isPlausibleCallerName("Mikrofon (iPhone (Marcin))"))
    }

    func testSettingsMigrationDropsUnsupportedAndRamboxAggregatorIDs() {
        let migrated = NotchSettings.migratedAllowedNotificationBundleIDs([
            "com.rambox",
            "net.whatsapp.WhatsApp",
            "com.skype.skype",
            "desktop.WhatsApp",
            "com.apple.mail",
            "com.todesktop.230313mzl4w4u92",
        ])
        XCTAssertEqual(migrated, [
            "net.whatsapp.WhatsApp",
            "com.apple.mail",
        ])
    }
}

@MainActor
final class CallActivityTests: XCTestCase {
    func testIncomingCallOutranksActiveCallAndNotifications() {
        let incoming = IncomingCallActivity(
            callerName: "Ada",
            appBundleID: "com.apple.FaceTime",
            receivedAt: .now
        )
        let active = ActiveCallActivity(
            callerName: "Ada",
            appBundleID: "com.apple.FaceTime",
            startedAt: .now
        )
        let peek = NotificationPeekActivity(
            id: UUID(),
            appName: "Messages",
            appBundleID: "com.apple.MobileSMS",
            openBundleID: "com.apple.MobileSMS",
            sender: "Bob",
            body: "Hi",
            receivedAt: .now,
            expiresAt: Date().addingTimeInterval(10),
            supportsQuickReply: true
        )

        let resolved = LiveActivityResolver.resolve(
            incomingCall: incoming,
            activeCall: active,
            agentSession: nil,
            timer: nil,
            notification: peek,
            showsMedia: true
        )
        XCTAssertEqual(resolved, .incomingCall(incoming))
    }

    func testNotificationPeekTemporarilyOutranksRunningFocusTimer() {
        let timer = FocusTimerActivity(
            formattedTime: "12:00",
            progress: 0.4,
            isRunning: true,
            modeLabel: "Focus",
            totalSeconds: 1500,
            mode: .countdown
        )
        let peek = NotificationPeekActivity(
            id: UUID(),
            appName: "Signal",
            appBundleID: "org.whispersystems.signal-desktop",
            openBundleID: "org.whispersystems.signal-desktop",
            sender: "Signal",
            body: "Notification",
            receivedAt: .now,
            expiresAt: Date().addingTimeInterval(8),
            supportsQuickReply: false
        )
        let resolved = LiveActivityResolver.resolve(
            incomingCall: nil,
            activeCall: nil,
            agentSession: nil,
            timer: timer,
            notification: peek,
            showsMedia: true
        )
        XCTAssertEqual(resolved, .notification(peek))
    }

    func testIncomingBannerWidthStaysWithinBounds() {
        let call = IncomingCallActivity(
            callerName: "Wesley Tingey",
            appBundleID: "com.apple.FaceTime",
            receivedAt: .now
        )
        let width = IncomingCallBannerMetrics.preferredWidth(for: call, cutoutWidth: 184)
        XCTAssertGreaterThanOrEqual(width, NotchFlowConstants.minIncomingCallBannerWidth)
        XCTAssertLessThanOrEqual(width, NotchFlowConstants.maxIncomingCallBannerWidth)
    }

    func testNotificationDripWidthStaysWithinBounds() {
        let peek = NotificationPeekActivity(
            id: UUID(),
            appName: "Signal",
            appBundleID: "org.whispersystems.signal-desktop",
            openBundleID: "org.whispersystems.signal-desktop",
            sender: "Signal",
            body: "New message",
            receivedAt: .now,
            expiresAt: Date().addingTimeInterval(10),
            supportsQuickReply: false
        )
        let width = NotificationBannerMetrics.preferredWidth(for: peek, cutoutWidth: 184)
        XCTAssertGreaterThanOrEqual(width, NotchFlowConstants.minNotificationBannerWidth)
        XCTAssertLessThanOrEqual(width, NotchFlowConstants.maxNotificationBannerWidth)
    }
}
