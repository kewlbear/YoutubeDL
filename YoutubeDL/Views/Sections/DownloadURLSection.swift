import SwiftUI

struct DownloadURLSection: View {
    @Binding var urlString: String
    var onPaste: () -> Void
    var onDownload: () -> Void

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    TextField("Enter URL", text: $urlString)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .keyboardType(.URL)
                        .submitLabel(.go)
                        .onSubmit(onDownload)

                    Button(action: onPaste) {
                        Label("Paste", systemImage: "doc.on.clipboard")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Paste URL from clipboard")
                }

                Button(action: onDownload) {
                    Label("Download", systemImage: "arrow.down.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.vertical, 4)
        } header: {
            Label("Download URL", systemImage: "link")
        }
    }
}
