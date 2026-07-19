import Foundation
import Testing
@testable import NotchFlow

@Suite("Notification catalog and allowlist")
struct NotificationCatalogTests {
    @Test("Supported catalog includes messaging apps and Mail, excludes Skype and Rambox")
    func supportedCatalog() {
        let ids = Set(NotificationAppCatalog.supportedNotificationApps.map(\.bundleID))
        #expect(ids.contains("net.whatsapp.WhatsApp"))
        #expect(ids.contains("org.whispersystems.signal-desktop"))
        #expect(ids.contains("com.apple.MobileSMS"))
        #expect(ids.contains("com.apple.mail"))
        #expect(!ids.contains("com.skype.skype"))
        #expect(!ids.contains("com.rambox"))
        #expect(!NotificationAppCatalog.isAggregator("com.rambox"))
        #expect(NotificationAppCatalog.isEmailApp("com.apple.mail"))
        #expect(NotificationAppCatalog.isMessagingApp("net.whatsapp.WhatsApp"))
        #expect(!NotificationAppCatalog.isMessagingApp("com.apple.mail"))
        // Bundle IDs look like AX labels — catalog name must still win.
        #expect(NotificationAppCatalog.name(for: "com.facebook.archon") == "Messenger")
        #expect(NotificationAppCatalog.name(for: "org.whispersystems.signal-desktop") == "Signal")
    }

    @Test("Resolve prefers trusted catalog hint and exact icon labels")
    func resolveCatalogHint() {
        let resolved = NotificationAppCatalog.resolve(
            iconTexts: ["Signal"],
            contentTexts: ["Alice", "Hello"],
            deliveringHint: "org.whispersystems.signal-desktop"
        )
        #expect(resolved.delivering == "org.whispersystems.signal-desktop")
        #expect(resolved.service == "org.whispersystems.signal-desktop")
        #expect(resolved.hasTrustedSource)

        let mail = NotificationAppCatalog.resolve(
            iconTexts: ["Mail"],
            contentTexts: ["Boss", "Quarterly report"],
            deliveringHint: "com.apple.mail"
        )
        #expect(mail.delivering == "com.apple.mail")
        #expect(NotificationAppCatalog.isEmailApp(mail.service))
    }

    @Test("Signal identity survives reverse-DNS AX icon labels and privacy banners")
    func signalPrivacyIdentity() {
        #expect(
            NotificationAppCatalog.iconIdentityLabel(
                fromAccessibilityLabel: "org.whispersystems.signal-desktop"
            ) == "Signal"
        )
        #expect(
            NotificationAppCatalog.matchMessagingAppFromIconLabels(
                in: ["org.whispersystems.signal-desktop"]
            )?.bundleID == "org.whispersystems.signal-desktop"
        )

        let privacy = NotificationAppCatalog.resolve(
            iconTexts: ["Signal"],
            contentTexts: [],
            deliveringHint: "org.whispersystems.signal-desktop"
        )
        #expect(privacy.delivering == "org.whispersystems.signal-desktop")
        #expect(privacy.service == "org.whispersystems.signal-desktop")
        #expect(privacy.displayName == "Signal")

        // Generic system header alone is not readable — hub synthesizes a presence ping.
        #expect(
            !NotificationAppCatalog.isReadableNotificationText(
                title: "Powiadomienie",
                body: ""
            )
        )
    }

    @Test("Foreign posters are not remapped to Messages")
    func foreignPosterStaysForeign() {
        let resolved = NotificationAppCatalog.resolve(
            iconTexts: ["Cursor"],
            contentTexts: ["Agent finished", "Build completed"],
            deliveringHint: "com.todesktop.230313mzl4w4u92"
        )
        #expect(resolved.delivering == "com.todesktop.230313mzl4w4u92")
        #expect(resolved.service == "unknown.app")
    }

    @Test("Call host bundle IDs resolve to Phone/FaceTime, not Notification")
    func callHostDisplayName() {
        let phone = NotificationAppCatalog.name(for: "com.apple.mobilephone")
        #expect(phone != "Powiadomienie")
        #expect(phone != "Notification")
        #expect(phone == "Phone" || phone == "Telefon" || !phone.contains("."))

        let faceTime = NotificationAppCatalog.name(for: "com.apple.FaceTime")
        #expect(faceTime != "Powiadomienie")
        #expect(faceTime != "Notification")
        #expect(faceTime.localizedCaseInsensitiveContains("FaceTime") || !faceTime.contains("."))
    }

    @Test("Weekday calendar chrome is not a plausible caller name")
    func calendarChromeRejectedAsCaller() {
        #expect(!NotificationAppCatalog.isPlausibleCallerName("NIEDZIELA"))
        #expect(!NotificationAppCatalog.isPlausibleCallerName("niedziela"))
        #expect(!NotificationAppCatalog.isPlausibleCallerName("Sunday"))
        #expect(!NotificationAppCatalog.isPlausibleCallerName("19 LIPCA"))
        #expect(!NotificationAppCatalog.isPlausibleCallerName("NIEDZIELA, 19 LIPCA"))
        #expect(NotificationAppCatalog.isCalendarChromeLabel("NIEDZIELA, 19 LIPCA"))
        #expect(!NotificationAppCatalog.isCalendarChromeLabel("Ada Nowak"))
        #expect(NotificationAppCatalog.isPlausibleCallerName("Ada Nowak"))
        #expect(NotificationAppCatalog.isPlausibleCallerName("Martyna Tymków"))
        #expect(NotificationAppCatalog.isContinuityCallSubtitle("Z Twojego iPhone'a"))
        #expect(!NotificationAppCatalog.isPlausibleCallerName("„NotchFlow” chce uzyskać dostęp do Twoich kontaktów."))
        #expect(NotificationAppCatalog.isSystemCallUILabel("Kamera (iPhone (Marcin))"))
        #expect(NotificationAppCatalog.isContinuityDeviceRouteLabel("Mikrofon (iPhone (Marcin))"))
        #expect(!NotificationAppCatalog.isPlausibleCallerName("Mikrofon (iPhone (Marcin))"))
    }

    @Test("Settings migration drops unsupported and Rambox aggregator IDs")
    func settingsMigration() {
        let migrated = NotchSettings.migratedAllowedNotificationBundleIDs([
            "com.rambox",
            "net.whatsapp.WhatsApp",
            "com.skype.skype",
            "desktop.WhatsApp",
            "com.apple.mail",
            "com.todesktop.230313mzl4w4u92",
        ])
        #expect(migrated == [
            "net.whatsapp.WhatsApp",
            "com.apple.mail",
        ])
    }
}

@Suite("Live activity priority and call banner metrics")
@MainActor
struct CallActivityTests {
    @Test("Incoming call outranks active call and notifications")
    func liveActivityPriority() {
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
        #expect(resolved == .incomingCall(incoming))
    }

    @Test("Notification peek temporarily outranks a running focus timer")
    func notificationOutranksTimer() {
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
        #expect(resolved == .notification(peek))
    }

    @Test("Incoming banner width stays within bounds")
    func incomingBannerWidth() {
        let call = IncomingCallActivity(
            callerName: "Wesley Tingey",
            appBundleID: "com.apple.FaceTime",
            receivedAt: .now
        )
        let width = IncomingCallBannerMetrics.preferredWidth(for: call, cutoutWidth: 184)
        #expect(width >= NotchFlowConstants.minIncomingCallBannerWidth)
        #expect(width <= NotchFlowConstants.maxIncomingCallBannerWidth)
    }

    @Test("Notification drip width stays within bounds")
    func notificationBannerWidth() {
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
        #expect(width >= NotchFlowConstants.minNotificationBannerWidth)
        #expect(width <= NotchFlowConstants.maxNotificationBannerWidth)
    }
}
