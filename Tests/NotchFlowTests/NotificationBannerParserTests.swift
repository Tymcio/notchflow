import CoreGraphics
import XCTest
@testable import NotchFlow

final class NotificationBannerParserTests: XCTestCase {
    private let toastFrame = CGRect(x: 1200, y: 40, width: 340, height: 72)

    private func snapshot(
        frame: CGRect? = nil,
        role: String = "AXGroup",
        isNotificationCenterBanner: Bool = true,
        hint: String? = nil,
        icons: [String] = [],
        texts: [String] = [],
        structured: NotificationBannerStructuredFields = NotificationBannerStructuredFields(),
        attributed: String? = nil,
        buttons: [NotificationBannerButton] = []
    ) -> NotificationBannerSnapshot {
        var snapshot = NotificationBannerSnapshot(
            frame: frame ?? toastFrame,
            role: role,
            isNotificationCenterBanner: isNotificationCenterBanner,
            deliveringBundleHint: hint
        )
        snapshot.iconTexts = icons
        snapshot.otherTexts = texts
        snapshot.structured = structured
        snapshot.attributedDescription = attributed
        snapshot.buttons = buttons
        return snapshot
    }

    private func button(_ text: String, role: String = "AXButton", depth: Int = 2) -> NotificationBannerButton {
        NotificationBannerButton(
            role: role,
            accessibilityText: text.lowercased(),
            keywordText: text.lowercased(),
            depth: depth
        )
    }

    func testStructuredMessagingBannerKeepsSenderAndBody() throws {
        let banner = try XCTUnwrap(NotificationBannerParser.parse(snapshot(
            hint: "net.whatsapp.WhatsApp",
            icons: ["WhatsApp"],
            texts: ["Ada Nowak", "Are we still on for lunch?"],
            structured: NotificationBannerStructuredFields(
                title: "Ada Nowak",
                body: "Are we still on for lunch?"
            )
        )))

        XCTAssertEqual(banner.deliveringBundleID, "net.whatsapp.WhatsApp")
        XCTAssertEqual(banner.serviceBundleID, "net.whatsapp.WhatsApp")
        XCTAssertEqual(banner.title, "Ada Nowak")
        XCTAssertEqual(banner.body, "Are we still on for lunch?")
        XCTAssertTrue(banner.hasTrustedSource)
        XCTAssertFalse(banner.isCall)
        XCTAssertFalse(banner.isLikelyCall)
        XCTAssertFalse(banner.supportsQuickReply)
    }

    func testSenderComesFromAttributedDescriptionWhenStaticTextsAreSparse() throws {
        let banner = try XCTUnwrap(NotificationBannerParser.parse(snapshot(
            hint: "org.whispersystems.signal-desktop",
            attributed: "Signal, Alice Smith, See you at 6"
        )))

        XCTAssertEqual(banner.serviceBundleID, "org.whispersystems.signal-desktop")
        XCTAssertEqual(banner.title, "Alice Smith")
        XCTAssertEqual(banner.body, "See you at 6")
        XCTAssertTrue(banner.iconLabels.contains("Signal"))
    }

    func testPrivacyScrubbedMessagingBannerBecomesPresencePing() throws {
        let banner = try XCTUnwrap(NotificationBannerParser.parse(snapshot(
            hint: "org.whispersystems.signal-desktop",
            icons: ["Signal"],
            texts: ["Powiadomienie"]
        )))

        XCTAssertEqual(banner.title, "Signal")
        XCTAssertEqual(banner.body, loc("New message"))
    }

    func testIncomingCallBannerIsFlaggedAsCall() throws {
        let banner = try XCTUnwrap(NotificationBannerParser.parse(snapshot(
            isNotificationCenterBanner: false,
            hint: "com.apple.FaceTime",
            texts: ["Ada Nowak", "Incoming call"],
            buttons: [button("Decline"), button("Answer")]
        )))

        XCTAssertTrue(banner.isCall)
        XCTAssertTrue(banner.isLikelyCall)
        XCTAssertTrue(banner.hasAnswerControl)
        XCTAssertTrue(banner.hasDeclineControl)
        XCTAssertNil(banner.replyField)
        XCTAssertNil(banner.replyButton)
    }

    func testPolishContinuityCallIsFlaggedWithoutButtons() throws {
        let banner = try XCTUnwrap(NotificationBannerParser.parse(snapshot(
            texts: ["Martyna Tymków", "Połączenie przychodzące"]
        )))
        XCTAssertTrue(banner.isLikelyCall)
    }

    func testRejectsTinyFramesAndUnknownRolesWithoutButtons() {
        XCTAssertNil(NotificationBannerParser.parse(snapshot(
            frame: CGRect(x: 0, y: 0, width: 40, height: 20),
            texts: ["Ada", "Hi"]
        )))
        XCTAssertNil(NotificationBannerParser.parse(snapshot(
            role: "AXButton",
            isNotificationCenterBanner: false,
            texts: ["Ada", "Hi"]
        )))
        XCTAssertNil(NotificationBannerParser.parse(snapshot(
            frame: CGRect(x: 0, y: 0, width: 340, height: 500),
            texts: ["Ada", "Hi"]
        )), "Non-call banners taller than a toast are not notifications")
    }

    func testFramePrefilterMatchesParserBounds() {
        XCTAssertTrue(NotificationBannerParser.frameCanBeBanner(toastFrame))
        XCTAssertFalse(NotificationBannerParser.frameCanBeBanner(CGRect(x: 0, y: 0, width: 59, height: 80)))
        XCTAssertFalse(NotificationBannerParser.frameCanBeBanner(CGRect(x: 0, y: 0, width: 300, height: 23)))
        XCTAssertFalse(NotificationBannerParser.frameCanBeBanner(CGRect(x: 0, y: 0, width: 300, height: 721)))
    }

    func testSenderFromCallLikeTextSkipsAudioRoutes() {
        XCTAssertEqual(NotificationBannerParser.senderFromCallLikeText("Ada Nowak, mobile"), "Ada Nowak")
        XCTAssertEqual(
            NotificationBannerParser.senderFromCallLikeText("Anna Kowalska, Połączenie przychodzące"),
            "Anna Kowalska"
        )
        XCTAssertNil(NotificationBannerParser.senderFromCallLikeText("Mikrofon (iPhone (Marcin))"))
        XCTAssertNil(NotificationBannerParser.senderFromCallLikeText("Lunch at noon"))
    }

    func testAttributedDescriptionPartsDropInternalLabels() {
        XCTAssertEqual(
            NotificationBannerParser.attributedDescriptionParts(" Signal, Alice ,, widget-local:com.apple.x, Hi "),
            ["Signal", "Alice", "Hi"]
        )
        XCTAssertEqual(NotificationBannerParser.attributedDescriptionParts(nil), [])
    }

    func testFingerprintIgnoresElementIdentity() throws {
        let first = try XCTUnwrap(NotificationBannerParser.parse(snapshot(
            hint: "net.whatsapp.WhatsApp",
            structured: NotificationBannerStructuredFields(title: "Ada", body: "Hi")
        )))
        let second = try XCTUnwrap(NotificationBannerParser.parse(snapshot(
            hint: "net.whatsapp.WhatsApp",
            structured: NotificationBannerStructuredFields(title: "Ada", body: "Hi")
        )))
        XCTAssertEqual(first.fingerprint, second.fingerprint)
    }
}
