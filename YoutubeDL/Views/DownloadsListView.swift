import SwiftUI
import UniformTypeIdentifiers

struct DownloadsListView: View {
    var downloads: [URL]

    var body: some View {
        Section {
            if downloads.isEmpty {
                Text("No downloads yet")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(downloads, id: \.self) { directory in
                    NavigationLink(destination: DownloadDetailsView(directoryURL: directory)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(directory.lastPathComponent)
                                .font(.body)
                            Text(directory.formattedDate)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        } header: {
            Label("Downloads", systemImage: "tray.and.arrow.down")
        }
    }
}

private extension URL {
    var formattedDate: String {
        let values = try? resourceValues(forKeys: [.contentModificationDateKey])
        let date = values?.contentModificationDate ?? .distantPast
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

struct DownloadDetailsView: View {
    let directoryURL: URL
    @State private var info: Info?
    @State private var videoURL: URL?
    @State private var formatsExpanded = false

    var body: some View {
        List {
            if let info {
                Section {
                    Text(info.title)
                        .font(.headline)
                    if let duration = info.duration.flatMap({ formatSecondsToHMS($0) }) {
                        Text("Duration: \(duration)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if let uploader = info.uploader, !uploader.isEmpty {
                        Text("Uploader: \(uploader)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if !info.formats.isEmpty {
                        DisclosureGroup("\(info.formats.count) formats", isExpanded: $formatsExpanded) {
                            ForEach(info.formats) { format in
                                Text(format.summary)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Metadata")
                }
            }

            if let videoURL {
                Section {
                    Text(videoURL.lastPathComponent)
                        .font(.body)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("File")
                }
            }
        }
        .navigationTitle(directoryURL.lastPathComponent)
        .task { await loadContent() }
    }

    @MainActor
    private func loadContent() async {
        do {
            let data = try Data(contentsOf: directoryURL.appendingPathComponent("Info.json"))
            info = try JSONDecoder().decode(Info.self, from: data)

            let files = try FileManager.default.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: [.contentTypeKey],
                options: .skipsHiddenFiles
            )
            videoURL = files.first { url in
                (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType?.conforms(to: .movie)) ?? false
            }
        } catch {
            print("DownloadDetailsView loadContent error:", error)
        }
    }
}
