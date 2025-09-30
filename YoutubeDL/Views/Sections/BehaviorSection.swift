import SwiftUI
import UIKit

struct BehaviorSection: View {
    @Binding var exportToPhotos: Bool
    @Binding var supportedFormatsOnly: Bool
    @Binding var enableChunkedDownload: Bool

    var body: some View {
        Section {
            Toggle(isOn: $exportToPhotos) {
                Label("Export to Photos (video)", systemImage: "photo.on.rectangle.angled")
            }

            Toggle(isOn: $supportedFormatsOnly) {
                Label("Prefer iOS-friendly streams", systemImage: "iphone")
            }

            Toggle(isOn: $enableChunkedDownload) {
                Label("Concurrent downloads", systemImage: "rectangle.stack.badge.plus")
            }

            Toggle(isOn: Binding(
                get: { UIApplication.shared.isIdleTimerDisabled },
                set: { UIApplication.shared.isIdleTimerDisabled = $0 }
            )) {
                Label("Keep screen awake", systemImage: "moon.zzz")
            }
        } header: {
            Label("Behavior", systemImage: "gearshape")
        }
    }
}
