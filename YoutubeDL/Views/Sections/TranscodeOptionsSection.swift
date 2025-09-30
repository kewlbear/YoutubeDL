import SwiftUI

struct TranscodeOptionsSection: View {
    @Binding var enableTranscoding: Bool
    @Binding var preset: TranscodePreset

    var body: some View {
        Section {
            Toggle(isOn: $enableTranscoding) {
                Label("Enable Transcoding", systemImage: "scissors")
            }
            .toggleStyle(.switch)

            if enableTranscoding {
                Picker("Preset", selection: $preset) {
                    ForEach(TranscodePreset.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.menu)

                Text(preset.helpText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
        } header: {
            Label("Transcoding", systemImage: "cpu")
        }
    }
}
