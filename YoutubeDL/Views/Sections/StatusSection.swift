import SwiftUI

struct StatusSection: View {
    var showProgress: Bool
    var progress: Progress
    var infoTitle: String?
    var outputFileName: String?
    var errorMessage: String?
    var exceptionDescription: String?

    var body: some View {
        Section {
            if showProgress {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "arrow.down.circle")
                        Text("Downloading…")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Spacer()
                        if let eta = progress.estimatedTimeRemaining {
                            Text("ETA \(Int(eta))s")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let infoTitle {
                        Text(infoTitle)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    ProgressView(progress)
                }
                .padding(.vertical, 4)
            }

            if let outputFileName {
                VStack(alignment: .leading, spacing: 4) {
                    statusRow(title: "Finished", systemImage: "checkmark.circle.fill", accent: .green)
                    Text(outputFileName)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, showProgress ? 12 : 0)
            }

            if let errorMessage {
                VStack(alignment: .leading, spacing: 4) {
                    statusRow(title: "Error", systemImage: "exclamationmark.triangle.fill", accent: .red)
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 8)
            }

            if let exceptionDescription {
                VStack(alignment: .leading, spacing: 4) {
                    statusRow(title: "Python Exception", systemImage: "exclamationmark.octagon.fill", accent: .orange)
                    Text(exceptionDescription)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 8)
            }
        } header: {
            Label("Status", systemImage: "info.circle")
        }
    }
}

private extension StatusSection {
    func statusRow(title: String, systemImage: String, accent: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(accent)
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(accent)
        }
    }
}
