import SwiftUI

struct SaveLocationSection: View {
    var defaultFolderName: String
    var perDownloadFolderName: String
    var onSelectDefault: () -> Void
    var onSelectPerDownload: () -> Void

    var body: some View {
        Section {
            Button(action: onSelectDefault) {
                LabeledContent("Default Save Folder", value: defaultFolderName) {
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)

            Button(action: onSelectPerDownload) {
                LabeledContent("Per-download Folder", value: perDownloadFolderName) {
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
        } header: {
            Label("Save Location", systemImage: "folder")
        }
    }
}
