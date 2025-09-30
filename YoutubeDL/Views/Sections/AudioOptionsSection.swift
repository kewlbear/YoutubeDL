import SwiftUI

struct AudioOptionsSection: View {
    @Binding var format: AudioFormat
    @Binding var showAdvanced: Bool
    @Binding var audioBitrateText: String

    var onAudioBitrateChange: () -> Void

    var body: some View {
        Section {
            LabeledContent("Format", value: format.rawValue.uppercased()) {
                Picker("Audio Format", selection: $format) {
                    ForEach(AudioFormat.allCases) { option in
                        Text(option.rawValue.uppercased()).tag(option)
                    }
                }
                .pickerStyle(.menu)
            }

            DisclosureGroup(isExpanded: $showAdvanced) {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Audio Bitrate (kbps)")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        TextField("auto", text: $audioBitrateText)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.numberPad)
                            .onChange(of: audioBitrateText) { _ in onAudioBitrateChange() }
                            .textFieldStyle(.roundedBorder)
                    }

                    Text("Set a target bitrate for AAC or MP3 outputs if desired.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 6)
            } label: {
                Text("Advanced Audio Options")
            }
        } header: {
            Label("Audio Options", systemImage: "headphones")
        }
    }
}
