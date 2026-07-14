import SwiftUI

@MainActor
struct QuickNotesView: View {
    @Bindable var appState: AppState
    @State private var draft = ""
    @State private var errorMessage = ""
    @FocusState private var isComposerFocused: Bool

    private var visibleNotes: [NoteItem] {
        appState.isPremium ? appState.notes : Array(appState.notes.prefix(NotchFlowConstants.freeNotesLimit))
    }

    private var canSave: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            composer

            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.caption2)
                    .foregroundStyle(Color.orange.opacity(0.95))
            }

            if !appState.isPremium {
                Text(locFormat("Notes: %lld/%lld", visibleNotes.count, NotchFlowConstants.freeNotesLimit))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(IslandStyle.secondaryText)
            }

            if visibleNotes.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(visibleNotes, id: \.id) { note in
                            noteRow(note)
                        }
                    }
                }
                .frame(maxHeight: 120)
            }
        }
    }

    private var composer: some View {
        HStack(spacing: 10) {
            ZStack(alignment: .topLeading) {
                if draft.isEmpty {
                    LocText("Quick note…")
                        .font(.subheadline)
                        .foregroundStyle(Color.white.opacity(0.48))
                        .allowsHitTesting(false)
                }

                TextField("", text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.subheadline)
                    .foregroundStyle(IslandStyle.primaryText)
                    .tint(.white)
                    .lineLimit(1...2)
                    .focused($isComposerFocused)
                    .onSubmit { saveNote() }
                    .onChange(of: isComposerFocused) { _, focused in
                        appState.isIslandInputFocused = focused
                    }
            }
            .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                AppController.panelController?.prepareForTyping()
                isComposerFocused = true
            }

            Button(action: saveNote) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(canSave ? Color.black.opacity(0.88) : IslandStyle.secondaryText)
                    .frame(width: 28, height: 28)
                    .background {
                        Circle()
                            .fill(canSave ? Color.white : Color.white.opacity(0.14))
                    }
            }
            .buttonStyle(.plain)
            .disabled(!canSave)
            .accessibilityLabel(loc("Add note"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background { composerBackground }
        .onDisappear {
            isComposerFocused = false
            appState.isIslandInputFocused = false
        }
    }

    private var composerBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.white.opacity(0.11))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isComposerFocused ? Color.white.opacity(0.35) : Color.white.opacity(0.16), lineWidth: 0.5)
            }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "square.and.pencil")
                .font(.title3)
                .foregroundStyle(IslandStyle.secondaryText)
            LocText("Capture ideas before they disappear.")
                .font(.caption)
                .foregroundStyle(IslandStyle.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }

    private func noteRow(_ note: NoteItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(Color.white.opacity(0.45))
                .frame(width: 3)
                .padding(.vertical, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(note.text)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(IslandStyle.primaryText)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(note.createdAt, style: .time)
                    .font(.caption2)
                    .foregroundStyle(IslandStyle.secondaryText)
            }

            if appState.isPremium, note.isPinned {
                Image(systemName: "pin.fill")
                    .font(.caption2)
                    .foregroundStyle(IslandStyle.accentText)
            }

            Button {
                appState.notesManager.remove(note)
                appState.notes = appState.notesManager.notes
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(IslandStyle.secondaryText)
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(Color.white.opacity(0.12)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(loc("Delete note"))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.09))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                }
        }
    }

    private func saveNote() {
        guard canSave else { return }

        do {
            try appState.notesManager.append(text: draft, isPremium: appState.isPremium)
            draft = ""
            errorMessage = ""
            appState.notes = appState.notesManager.notes
            isComposerFocused = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
