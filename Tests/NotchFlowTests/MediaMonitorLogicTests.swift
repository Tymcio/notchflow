import AppKit
import XCTest
@testable import NotchFlow

final class MediaStateMergerTests: XCTestCase {
    private func state(
        title: String = "Song A",
        artist: String = "Artist",
        artwork: Data? = nil,
        isPlaying: Bool = true,
        elapsed: Double = 10,
        duration: Double = 200,
        bundleID: String? = "com.spotify.client",
        lyrics: String? = nil,
        sampledAt: Date = Date(timeIntervalSince1970: 100)
    ) -> MediaPlaybackState {
        MediaPlaybackState(
            title: title,
            artist: artist,
            album: "Album",
            artworkURL: nil,
            artworkData: artwork,
            isPlaying: isPlaying,
            elapsed: elapsed,
            duration: duration,
            bundleIdentifier: bundleID,
            lyricsSnippet: lyrics,
            positionSampledAt: sampledAt
        )
    }

    func testSameTrackKeepsArtworkAndLyrics() {
        let current = state(artwork: Data([1, 2, 3]), lyrics: "First line")
        let merged = MediaStateMerger.merge(incoming: state(elapsed: 12), current: current)
        XCTAssertEqual(merged.artworkData, Data([1, 2, 3]))
        XCTAssertEqual(merged.lyricsSnippet, "First line")
        XCTAssertEqual(merged.elapsed, 12)
    }

    func testTrackChangeClearsArtworkAndLyrics() {
        let current = state(artwork: Data([1, 2, 3]), lyrics: "First line")
        let merged = MediaStateMerger.merge(incoming: state(title: "Song B"), current: current)
        XCTAssertNil(merged.artworkData)
        XCTAssertNil(merged.lyricsSnippet, "Lyrics of the previous track must not carry over")
        XCTAssertEqual(merged.title, "Song B")
    }

    func testUnusableTimingFallsBackToCurrent() {
        let current = state(elapsed: 42, duration: 180)
        let merged = MediaStateMerger.merge(incoming: state(elapsed: 0.2, duration: 0), current: current)
        XCTAssertEqual(merged.elapsed, 42)
        XCTAssertEqual(merged.duration, 180)
    }

    func testPositionSampleOnlyMovesWhenTimingOrPlaybackChanges() {
        let now = Date(timeIntervalSince1970: 500)
        let current = state(sampledAt: Date(timeIntervalSince1970: 100))
        XCTAssertEqual(
            MediaStateMerger.merge(incoming: state(), current: current, now: now).positionSampledAt,
            current.positionSampledAt
        )
        XCTAssertEqual(
            MediaStateMerger.merge(incoming: state(isPlaying: false), current: current, now: now).positionSampledAt,
            now
        )
    }

    func testPausedUpdateFromAnotherPlayerIsStale() {
        let playing = state(bundleID: "com.spotify.client")
        let otherPaused = state(title: "Other", isPlaying: false, bundleID: "com.apple.Music")
        XCTAssertTrue(MediaStateMerger.isStaleOtherPlayer(otherPaused, current: playing))
        XCTAssertFalse(MediaStateMerger.isStaleOtherPlayer(state(isPlaying: false), current: playing))
    }

    func testScriptingPollForNewTrackDropsOldLyrics() throws {
        let current = state(artwork: Data([9]), lyrics: "Old line")
        let script = state(title: "Song B", elapsed: 3)
        let merged = try XCTUnwrap(MediaStateMerger.mergeScripting(script, into: current))
        XCTAssertEqual(merged.title, "Song B")
        XCTAssertNil(merged.lyricsSnippet)
        XCTAssertNil(merged.artworkData)

        let sameTrack = try XCTUnwrap(MediaStateMerger.mergeScripting(state(elapsed: 30), into: current))
        XCTAssertEqual(sameTrack.lyricsSnippet, "Old line")
        XCTAssertEqual(sameTrack.artworkData, Data([9]))
    }

    func testScriptingPollFromPausedOtherPlayerIsIgnored() {
        let current = state(bundleID: "com.spotify.client")
        let script = state(isPlaying: false, bundleID: "com.apple.Music")
        XCTAssertNil(MediaStateMerger.mergeScripting(script, into: current))
    }
}

final class MediaEnrichmentCacheTests: XCTestCase {
    func testStoresHitsAndMisses() {
        var cache = MediaEnrichmentCache<String>(capacity: 4)
        XCTAssertNil(cache.lookup("a"))
        cache.store("line", for: "a")
        cache.store(nil, for: "b")
        guard case .hit("line") = cache.lookup("a") else { return XCTFail("expected hit") }
        guard case .miss = cache.lookup("b") else { return XCTFail("expected cached miss") }
        XCTAssertEqual(cache.value(for: "a"), "line")
        XCTAssertNil(cache.value(for: "b"))
    }

    func testExpiringMissIsRetriedAfterTTL() {
        var cache = MediaEnrichmentCache<Data>(capacity: 4)
        let start = Date(timeIntervalSince1970: 0)
        cache.store(nil, for: "a", ttl: 120, now: start)
        XCTAssertNotNil(cache.lookup("a", now: start.addingTimeInterval(60)))
        XCTAssertNil(cache.lookup("a", now: start.addingTimeInterval(121)))
        XCTAssertEqual(cache.count, 0)
    }

    func testEvictsLeastRecentlyUsed() {
        var cache = MediaEnrichmentCache<Int>(capacity: 2)
        cache.store(1, for: "a")
        cache.store(2, for: "b")
        _ = cache.lookup("a")
        cache.store(3, for: "c")
        XCTAssertEqual(cache.value(for: "a"), 1)
        XCTAssertNil(cache.lookup("b"))
        XCTAssertEqual(cache.value(for: "c"), 3)
    }
}

final class MediaParsingTests: XCTestCase {
    func testTimingParserHandlesLocalizedNumbers() {
        XCTAssertEqual(MediaTimingParser.seconds(from: "12.5"), 12.5)
        XCTAssertEqual(MediaTimingParser.seconds(from: " 12,5\n"), 12.5)
        XCTAssertEqual(MediaTimingParser.seconds(from: "1.234,5"), 1234.5)
        XCTAssertEqual(MediaTimingParser.seconds(from: "1,234.5"), 1234.5)
        XCTAssertEqual(MediaTimingParser.seconds(from: "1 234,5"), 1234.5)
        XCTAssertNil(MediaTimingParser.seconds(from: "abc"))
        XCTAssertNil(MediaTimingParser.seconds(from: "inf"))
        XCTAssertNil(MediaTimingParser.seconds(from: ""))
    }

    func testLyricsParserPrefersSyncedFirstLine() {
        let synced = #"{"syncedLyrics":"[ar:Someone]\n[00:14.74] Hello there\n[00:16.00] Next","plainLyrics":"Plain"}"#
        XCTAssertEqual(LyricsService.parse(Data(synced.utf8)), .found("Hello there"))
        XCTAssertEqual(
            LyricsService.parse(Data(#"{"plainLyrics":"\n  Only plain\nmore"}"#.utf8)),
            .found("Only plain")
        )
        XCTAssertEqual(LyricsService.parse(Data(#"{"syncedLyrics":null,"plainLyrics":""}"#.utf8)), .notFound)
        XCTAssertEqual(LyricsService.parse(Data("not json".utf8)), .failed)
    }

    func testScriptedTrackConvertsSpotifyMilliseconds() throws {
        let spotify = ScriptedTrack(
            title: "Song", artist: "A", album: "B", playerState: "playing", rawDuration: 215_000, position: 12.5
        )
        let state = try XCTUnwrap(spotify.playbackState(bundleID: "com.spotify.client", fallbackDuration: 0))
        XCTAssertEqual(state.duration, 215)
        XCTAssertEqual(state.elapsed, 12.5)
        XCTAssertTrue(state.isPlaying)

        let music = ScriptedTrack(
            title: "Song", artist: "A", album: "B", playerState: "paused", rawDuration: 0, position: -1
        )
        let paused = try XCTUnwrap(music.playbackState(bundleID: "com.apple.Music", fallbackDuration: 180))
        XCTAssertEqual(paused.duration, 180)
        XCTAssertEqual(paused.elapsed, 0)
        XCTAssertFalse(paused.isPlaying)

        XCTAssertNil(ScriptedTrack(
            title: "", artist: "", album: "", playerState: "stopped", rawDuration: 0, position: 0
        ).playbackState(bundleID: "com.apple.Music", fallbackDuration: 0))
    }

    func testScriptedTrackParsesAppleScriptList() throws {
        let list = NSAppleEventDescriptor.list()
        let items = [
            NSAppleEventDescriptor(string: "Song"),
            NSAppleEventDescriptor(string: "Artist"),
            NSAppleEventDescriptor(string: "Album"),
            NSAppleEventDescriptor(string: "playing"),
            NSAppleEventDescriptor(double: 201.5),
            NSAppleEventDescriptor(double: 33.25),
        ]
        for (index, item) in items.enumerated() {
            list.insert(item, at: index + 1)
        }
        let track = try XCTUnwrap(ScriptedTrack(descriptor: list))
        XCTAssertEqual(track.title, "Song")
        XCTAssertEqual(track.playerState, "playing")
        XCTAssertEqual(track.rawDuration, 201.5)
        XCTAssertEqual(track.position, 33.25)
        XCTAssertNil(ScriptedTrack(descriptor: NSAppleEventDescriptor.list()))
    }

    func testArtworkDownsamplerShrinksLargeImages() throws {
        let size = 600
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        ))
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        let small = try XCTUnwrap(ArtworkDownsampler.downsample(png))
        let image = try XCTUnwrap(NSBitmapImageRep(data: small))
        XCTAssertLessThanOrEqual(max(image.pixelsWide, image.pixelsHigh), ArtworkDownsampler.maxPixelSize)
        XCTAssertNil(ArtworkDownsampler.downsample(Data("nope".utf8)))
    }
}
