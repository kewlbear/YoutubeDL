import SwiftUI

struct SaveLocationSection: View {
    var defaultFolderName: String
    var perDownloadFolderName: String
    var onSelectDefault: () -> Void
    var onSelectPerDownload: () -> Void

    var body: some View {
        Section {
            Button(action: onSelectDefault) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Default Save Folder")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Text(defaultFolderName)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: onSelectPerDownload) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Per-download Folder")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Text(perDownloadFolderName)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } header: {
            Label("Save Location", systemImage: "folder")
        }
    }
}
