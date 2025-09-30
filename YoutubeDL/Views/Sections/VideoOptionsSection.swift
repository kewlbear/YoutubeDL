import SwiftUI

struct VideoOptionsSection: View {
    @Binding var quality: VideoQuality
    @Binding var container: ContainerFormat
    @Binding var showAdvanced: Bool
    @Binding var crfText: String
    @Binding var videoBitrateText: String

    var onCRFChange: () -> Void
    var onVideoBitrateChange: () -> Void

    var body: some View {
        Section {
            LabeledContent("Quality", value: quality.rawValue) {
                Picker("Quality", selection: $quality) {
                    ForEach(VideoQuality.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.menu)
            }

            LabeledContent("Container", value: container.rawValue.uppercased()) {
                Picker("Container", selection: $container) {
                    ForEach(ContainerFormat.allCases) { option in
                        Text(option.rawValue.uppercased()).tag(option)
                    }
                }
                .pickerStyle(.menu)
            }

            DisclosureGroup(isExpanded: $showAdvanced) {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("CRF")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        TextField("auto", text: $crfText)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.numberPad)
                            .onChange(of: crfText) { _ in onCRFChange() }
                            .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Video Bitrate (kbps)")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        TextField("auto", text: $videoBitrateText)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.numberPad)
                            .onChange(of: videoBitrateText) { _ in onVideoBitrateChange() }
                            .textFieldStyle(.roundedBorder)
                    }

                    Text("Leave empty for automatic values. CRF takes priority when bitrate is not set.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 6)
            } label: {
                Text("Advanced Video Options")
            }
        } header: {
            Label("Video Options", systemImage: "film")
        }
    }
}
