import AppKit
import Contacts
import Foundation

/// Looks up a contact thumbnail for an incoming-call display name.
enum ContactPhotoProvider {
    @MainActor
    static func thumbnail(forCallerName name: String, side: CGFloat = 64) -> NSImage? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard NotificationAppCatalog.isPlausibleCallerName(trimmed) else { return nil }

        let store = CNContactStore()
        let status = CNContactStore.authorizationStatus(for: .contacts)
        switch status {
        case .authorized, .limited:
            break
        case .notDetermined:
            // Don't block the main actor; next ring can use the photo after the prompt.
            store.requestAccess(for: .contacts) { _, _ in }
            return nil
        default:
            return nil
        }

        let keys: [CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactNicknameKey as CNKeyDescriptor,
            CNContactThumbnailImageDataKey as CNKeyDescriptor,
            CNContactImageDataKey as CNKeyDescriptor,
            CNContactIdentifierKey as CNKeyDescriptor,
        ]

        let request = CNContactFetchRequest(keysToFetch: keys)
        request.unifyResults = true

        var best: CNContact?
        var bestScore = 0
        let needle = normalize(trimmed)

        do {
            try store.enumerateContacts(with: request) { contact, stop in
                let score = matchScore(contact: contact, needle: needle, raw: trimmed)
                if score > bestScore {
                    bestScore = score
                    best = contact
                }
                if score >= 100 {
                    stop.pointee = true
                }
            }
        } catch {
            return nil
        }

        guard bestScore >= 60, let contact = best else { return nil }
        let data = contact.thumbnailImageData ?? contact.imageData
        guard let data, let image = NSImage(data: data) else { return nil }
        return resized(image, side: side)
    }

    private static func normalize(_ text: String) -> String {
        text
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func matchScore(contact: CNContact, needle: String, raw: String) -> Int {
        let full = normalize([contact.givenName, contact.familyName]
            .filter { !$0.isEmpty }
            .joined(separator: " "))
        let org = normalize(contact.organizationName)
        let nick = normalize(contact.nickname)

        if !full.isEmpty, full == needle { return 100 }
        if !nick.isEmpty, nick == needle { return 95 }
        if !org.isEmpty, org == needle { return 90 }

        if !full.isEmpty, needle.contains(full) || full.contains(needle) { return 80 }

        let parts = raw.split(separator: " ").map { normalize(String($0)) }.filter { $0.count >= 2 }
        if parts.count >= 2 {
            let given = normalize(contact.givenName)
            let family = normalize(contact.familyName)
            if parts.contains(given), parts.contains(family) { return 100 }
            if parts.contains(where: { $0 == given || $0 == family }) { return 55 }
        }
        return 0
    }

    private static func resized(_ image: NSImage, side: CGFloat) -> NSImage {
        let target = NSSize(width: side, height: side)
        let out = NSImage(size: target)
        out.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(
            in: NSRect(origin: .zero, size: target),
            from: NSRect(origin: .zero, size: image.size),
            operation: .copy,
            fraction: 1
        )
        out.unlockFocus()
        return out
    }
}
