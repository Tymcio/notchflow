import Foundation
import UserNotifications

enum NotificationService {
    // Demo mode posts nothing. It also runs as a bare debug executable, where
    // `UNUserNotificationCenter` raises an exception because there is no app bundle.
    static func requestAuthorization() {
        guard !DemoMode.isEnabled else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func post(title: String, body: String, sound: Bool = true) {
        guard !DemoMode.isEnabled else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if sound {
            content.sound = .default
        }
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
