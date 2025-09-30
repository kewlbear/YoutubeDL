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
                    Label("Finished", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text(outputFileName)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, showProgress ? 12 : 0)
            }

            if let errorMessage {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Error", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 8)
            }

            if let exceptionDescription {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Python Exception", systemImage: "exclamationmark.octagon.fill")
                        .foregroundStyle(.orange)
                        .font(.subheadline)
                        .fontWeight(.semibold)
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
