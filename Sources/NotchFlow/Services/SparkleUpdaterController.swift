#if canImport(Sparkle)
import Foundation
import Sparkle

@MainActor
final class SparkleUpdaterController: NSObject {
    static let shared = SparkleUpdaterController()

    private var updaterController: SPUStandardUpdaterController?

    /// Sparkle is only started when release keys are present in Info.plist.
    var isConfigured: Bool {
        Self.sparkleConfiguration(in: Bundle.main) != nil
    }

    func start() {
        guard isConfigured, updaterController == nil else { return }
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    func checkForUpdates() {
        guard isConfigured else { return }
        updaterController?.updater.checkForUpdates()
    }

    private static func sparkleConfiguration(in bundle: Bundle) -> (feedURL: String, publicKey: String)? {
        guard let publicKey = bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
              let feedURL = bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String,
              isUsableSparkleValue(publicKey),
              isUsableSparkleValue(feedURL),
              URL(string: feedURL) != nil
        else {
            return nil
        }
        return (feedURL, publicKey)
    }

    private static func isUsableSparkleValue(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard !trimmed.contains("$") else { return false }
        return true
    }
}
#endif
