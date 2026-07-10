import SwiftUI

struct ShelfMiniView: View {
    let item: ShelfItem

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: item.isDirectory ? "folder.fill" : "doc.fill")
                .font(.caption2)
            Text(item.displayName)
                .font(.caption2)
                .lineLimit(1)
        }
    }
}

struct ShelfView: View {
    let items: [ShelfItem]
    let isPremium: Bool
    let onRemove: (ShelfItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Floating Shelf", systemImage: "tray.and.arrow.down.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if items.isEmpty {
                Text("Drop a file or link here")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(visibleItems) { item in
                    ShelfRow(item: item, onRemove: onRemove)
                }
            }
        }
    }

    private var visibleItems: [ShelfItem] {
        if isPremium {
            return items
        }
        return Array(items.prefix(1))
    }
}

struct ShelfRow: View {
    let item: ShelfItem
    let onRemove: (ShelfItem) -> Void

    var body: some View {
        HStack {
            Image(systemName: item.isDirectory ? "folder" : "link")
            Text(item.displayName)
                .lineLimit(1)
            Spacer()
            Button {
                onRemove(item)
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .font(.caption)
        .onDrag {
            NSItemProvider(object: item.url as NSURL)
        }
    }
}
