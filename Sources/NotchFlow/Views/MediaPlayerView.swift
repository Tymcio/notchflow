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
                        .foregroundStyle(IslandStyle.primaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(state.artist)
                        .font(.caption)
                        .foregroundStyle(IslandStyle.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if showsLyrics, let snippet = state.lyricsSnippet, !snippet.isEmpty {
                        Text(snippet)
                            .font(.caption2.italic())
                            .foregroundStyle(IslandStyle.tertiaryText)
                            .lineLimit(1)
                            .transition(.opacity)
                    }
                }
                Spacer(minLength: 0)
            }
            .animation(IslandMotion.quick, value: state.lyricsSnippet)

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
                transportButton("backward.fill", label: "Poprzedni utwór", action: onPrevious)
                transportButton(
                    state.isPlaying ? "pause.fill" : "play.fill",
                    label: state.isPlaying ? "Wstrzymaj" : "Odtwórz",
                    action: onPlayPause,
                    large: true
                )
                transportButton("forward.fill", label: "Następny utwór", action: onNext)
            }
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func transportButton(
        _ systemName: String,
        label: String,
        action: @escaping () -> Void,
        large: Bool = false
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(large ? .title3.weight(.semibold) : .body.weight(.semibold))
                .foregroundStyle(IslandStyle.primaryText)
                .frame(width: large ? 32 : 28, height: large ? 32 : 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
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
        .clipShape(RoundedRectangle(cornerRadius: IslandRadius.small, style: .continuous))
        .onAppear { loadImage() }
        .onChange(of: artworkData) { _, _ in loadImage() }
        .onChange(of: artworkURL) { _, _ in loadImage() }
        .onChange(of: trackKey) { _, _ in loadImage() }
    }

    private func loadImage() {
        if trackKey != loadedTrackKey {
            loadedImage = nil
        }

        if let artworkData {
            decodeImage(from: artworkData, expectedTrackKey: trackKey)
            return
        }

        guard let artworkURL else {
            loadedImage = nil
            loadedTrackKey = trackKey
            return
        }

        if artworkURL.isFileURL {
            let expectedTrackKey = trackKey
            let url = artworkURL
            Task.detached(priority: .utility) {
                let data = try? Data(contentsOf: url)
                let image = data.flatMap { NSImage(data: $0) }
                await MainActor.run {
                    guard expectedTrackKey == trackKey else { return }
                    loadedImage = image
                    loadedTrackKey = trackKey
                }
            }
            return
        }

        let expectedTrackKey = trackKey
        Task {
            let data = await MusicArtworkFetcher.fetchFromURL(artworkURL)
            guard let data else { return }
            await MainActor.run {
                decodeImage(from: data, expectedTrackKey: expectedTrackKey)
            }
        }
    }

    private func decodeImage(from data: Data, expectedTrackKey: String) {
        let expectedKey = expectedTrackKey
        Task.detached(priority: .utility) {
            let image = NSImage(data: data)
            await MainActor.run {
                guard expectedKey == trackKey else { return }
                loadedImage = image
                loadedTrackKey = trackKey
            }
        }
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: IslandRadius.small, style: .continuous)
            .fill(IslandStyle.surfaceStroke)
            .overlay {
                Image(systemName: "music.note")
                    .font(.body)
                    .foregroundStyle(IslandStyle.tertiaryText)
            }
    }
}
