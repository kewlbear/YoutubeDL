import SwiftUI

struct DownloadKindSection: View {
    @Binding var kind: DownloadKind

    var body: some View {
        Section {
            Picker("Kind", selection: $kind) {
                ForEach(DownloadKind.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.segmented)
        } header: {
            Label("What to download", systemImage: "switch.2")
        }
    }
}
