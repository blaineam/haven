import MediaPlayer
import SwiftUI

/// Parse a track's encoded id "<storeID>~<persistentID>" (either part may be absent).
func trackIds(_ catalogId: String) -> (store: String?, pid: UInt64?) {
    let parts = catalogId.split(separator: "~", maxSplits: 1, omittingEmptySubsequences: false)
    let store = parts.first.map(String.init).flatMap { ($0.isEmpty || $0 == "0") ? nil : $0 }
    let pid = parts.count > 1 ? UInt64(parts[1]) : nil
    return (store, pid)
}

/// The exact library song matching a persistent id, if it exists on this device.
@MainActor func librarySong(_ pid: UInt64) -> MPMediaItem? {
    let q = MPMediaQuery.songs()
    q.addFilterPredicate(MPMediaPropertyPredicate(value: pid, forProperty: MPMediaItemPropertyPersistentID))
    return q.items?.first
}

/// An in-app song picker that lets you **hear** a song before choosing it. Browses your
/// music library, plays a preview through Apple Music, and keeps only a `TrackRef`
/// (the ids + title/artist) — never the audio. Each viewer plays it through their own
/// Apple Music, so Haven shares the *reference*, not the file.
struct SongPicker: View {
    var onPick: (TrackRefFfi) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var songs: [MPMediaItem] = []
    @State private var query = ""
    @State private var previewing: MPMediaEntityPersistentID?
    @State private var denied = false
    private let preview = MPMusicPlayerController.applicationMusicPlayer

    private var filtered: [MPMediaItem] {
        guard !query.isEmpty else { return songs }
        return songs.filter {
            ($0.title ?? "").localizedCaseInsensitiveContains(query) ||
            ($0.artist ?? "").localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                KithBackground()
                if denied {
                    ContentUnavailableView("Music access off", systemImage: "music.note.list",
                                           description: Text("Allow access to your music in Settings to pick a song."))
                } else {
                    List(filtered, id: \.persistentID) { item in
                        HStack(spacing: 12) {
                            Button { togglePreview(item) } label: {
                                Image(systemName: previewing == item.persistentID ? "pause.circle.fill" : "play.circle.fill")
                                    .font(.title2).foregroundStyle(KithTheme.pink)
                            }
                            .buttonStyle(.plain)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title ?? "Unknown song").font(.subheadline.weight(.medium)).lineLimit(1)
                                Text(item.artist ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            Button("Use") { choose(item) }
                                .font(.subheadline.weight(.semibold)).tint(KithTheme.pink).buttonStyle(.bordered)
                        }
                        .listRowBackground(Color.clear)
                    }
                    .scrollContentBackground(.hidden)
                    .searchable(text: $query, prompt: "Search your music")
                }
            }
            .navigationTitle("Pick a song")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Cancel") { stopPreview(); dismiss() } } }
            .onAppear(perform: load)
            .onDisappear(perform: stopPreview)
        }
    }

    private func load() {
        MPMediaLibrary.requestAuthorization { status in
            DispatchQueue.main.async {
                guard status == .authorized else { denied = true; return }
                songs = (MPMediaQuery.songs().items ?? []).sorted { ($0.title ?? "") < ($1.title ?? "") }
            }
        }
    }
    private func togglePreview(_ item: MPMediaItem) {
        if previewing == item.persistentID { stopPreview() }
        else {
            preview.setQueue(with: MPMediaItemCollection(items: [item]))
            preview.play()
            previewing = item.persistentID
        }
    }
    private func stopPreview() {
        if previewing != nil { preview.stop() }
        previewing = nil
    }
    private func choose(_ item: MPMediaItem) {
        stopPreview()
        onPick(TrackRefFfi(
            catalogId: "\(item.playbackStoreID)~\(item.persistentID)",
            title: item.title ?? "Unknown song",
            artist: item.artist ?? "",
            artworkUrl: "",
            durationMs: UInt64(max(0, item.playbackDuration) * 1000)
        ))
        dismiss()
    }
}
