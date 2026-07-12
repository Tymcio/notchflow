import AppKit
import SwiftUI

struct MediaPlayerView: View {
    let state: MediaPlaybackState
    let showsLyrics: Bool
    let onPlayPause: () -> Void
    let onNext: () -> Void
    let onPrevious: () -> Void
    let onSeek: (Double) -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                ArtworkView(artworkURL: state.artworkURL, artworkData: state.artworkData, trackKey: state.trackKey, size: 52)

                VStack(alignment: .leading, spacing: 2) {
                    Text(state.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(state.artist)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                    if showsLyrics, let snippet = state.lyricsSnippet, !snippet.isEmpty {
                        Text(snippet)
                            .font(.caption2.italic())
                            .foregroundStyle(.white.opacity(0.42))
                            .lineLimit(1)
                            .transition(.opacity)
                    }
                }
                Spacer(minLength: 0)
            }
            .animation(.easeOut(duration: 0.2), value: state.lyricsSnippet)

            if state.hasUsableDuration {
                TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                    MediaScrubberView(
                        position: state.interpolatedPosition(),
                        duration: state.duration,
                        onSeek: onSeek
                    )
                }
            }

            HStack(spacing: 28) {
                transportButton("backward.fill", action: onPrevious)
                transportButton(state.isPlaying ? "pause.fill" : "play.fill", action: onPlayPause, large: true)
                transportButton("forward.fill", action: onNext)
            }
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func transportButton(_ systemName: String, action: @escaping () -> Void, large: Bool = false) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(large ? .title3.weight(.semibold) : .body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: large ? 32 : 26, height: large ? 32 : 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct ArtworkView: View {
    let artworkURL: URL?
    var artworkData: Data? = nil
    let trackKey: String
    let size: CGFloat

    @State private var loadedImage: NSImage?
    @State private var loadedTrackKey = ""

    var body: some View {
        Group {
            if let loadedImage, loadedTrackKey == trackKey {
                Image(nsImage: loadedImage)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .onAppear { loadImage() }
        .onChange(of: artworkData) { _, _ in loadImage() }
        .onChange(of: artworkURL) { _, _ in loadImage() }
        .onChange(of: trackKey) { _, _ in loadImage() }
    }

    private func loadImage() {
        if trackKey != loadedTrackKey {
            loadedImage = nil
        }

        if let artworkData, let image = NSImage(data: artworkData) {
            loadedImage = image
            loadedTrackKey = trackKey
            return
        }

        guard let artworkURL else {
            loadedImage = nil
            loadedTrackKey = trackKey
            return
        }

        if artworkURL.isFileURL {
            loadedImage = NSImage(contentsOf: artworkURL)
            loadedTrackKey = trackKey
            return
        }

        let expectedTrackKey = trackKey
        Task {
            let data = await MusicArtworkFetcher.fetchFromURL(artworkURL)
            await MainActor.run {
                guard expectedTrackKey == trackKey else { return }
                if let data, let image = NSImage(data: data) {
                    loadedImage = image
                    loadedTrackKey = trackKey
                }
            }
        }
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(.white.opacity(0.08))
            .overlay {
                Image(systemName: "music.note")
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.35))
            }
    }
}
