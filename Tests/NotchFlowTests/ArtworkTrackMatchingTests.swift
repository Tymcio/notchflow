import XCTest
@testable import NotchFlow

final class ArtworkTrackMatchingTests: XCTestCase {
    private let track = ArtworkTrackIdentity(key: "Song A|Artist|Album", title: "Song A", artist: "Artist")

    func testPlayerReportingSameTrackMatches() {
        XCTAssertTrue(track.matches(playerTitle: "Song A", playerArtist: "Artist"))
        XCTAssertTrue(track.matches(playerTitle: " song a ", playerArtist: "ARTIST"))
    }

    func testPlayerOnAnotherTrackDoesNotMatch() {
        XCTAssertFalse(track.matches(playerTitle: "Song B", playerArtist: "Artist"))
        XCTAssertFalse(track.matches(playerTitle: "Song A", playerArtist: "Someone Else"))
    }

    func testMissingArtistOnEitherSideComparesTitleOnly() {
        XCTAssertTrue(track.matches(playerTitle: "Song A", playerArtist: ""))
        let noArtist = ArtworkTrackIdentity(key: "Song A||", title: "Song A", artist: "")
        XCTAssertTrue(noArtist.matches(playerTitle: "Song A", playerArtist: "Artist"))
        XCTAssertFalse(noArtist.matches(playerTitle: "Song B", playerArtist: "Artist"))
    }

    @MainActor
    func testFoundArtworkIsCachedEvenAfterTheTrackChanged() throws {
        let data = Data([1, 2, 3])
        let entry = try XCTUnwrap(MediaMonitor.artworkCacheEntry(for: .found(data), isCurrentTrack: false))
        XCTAssertEqual(entry.data, data)
        XCTAssertNil(entry.ttl)
    }

    @MainActor
    func testMissIsOnlyRememberedWhileTheTrackIsCurrent() throws {
        XCTAssertNil(MediaMonitor.artworkCacheEntry(for: .notFound, isCurrentTrack: false))
        let entry = try XCTUnwrap(MediaMonitor.artworkCacheEntry(for: .notFound, isCurrentTrack: true))
        XCTAssertNil(entry.data)
        XCTAssertEqual(entry.ttl, MediaMonitor.failedLookupRetryInterval)
    }

    @MainActor
    func testAnswerForAnotherTrackIsNeverCachedAsArtwork() throws {
        XCTAssertNil(MediaMonitor.artworkCacheEntry(for: .trackChanged, isCurrentTrack: false))
        let entry = try XCTUnwrap(MediaMonitor.artworkCacheEntry(for: .trackChanged, isCurrentTrack: true))
        XCTAssertNil(entry.data)
        XCTAssertEqual(entry.ttl, MediaMonitor.trackMismatchRetryInterval)
    }
}
