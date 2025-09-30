import SwiftUI
import UIKit

@available(iOS 15.0, *)
public struct MainView: View {
    @EnvironmentObject public var app: AppModel

    @State private var urlString: String = ""
    @State private var showAlert = false
    @State private var alertMessage = ""

    @State private var showGlobalFolderPicker = false
    @State private var showPerDownloadFolderPicker = false
    @State private var showBrowser = false

    @State private var showAdvancedVideo = false
    @State private var showAdvancedAudio = false

    @State private var crfText: String = ""
    @State private var videoBitrateText: String = ""
    @State private var audioBitrateText: String = ""

    public init() {}

    public var body: some View {
        NavigationView {
            List {
                DownloadURLSection(
                    urlString: $urlString,
                    onPaste: pasteFromClipboard,
                    onDownload: startDownloadTapped
                )

                DownloadKindSection(kind: $app.kind)

                if app.kind != .audio {
                    VideoOptionsSection(
                        quality: $app.videoQuality,
                        container: $app.container,
                        showAdvanced: $showAdvancedVideo,
                        crfText: $crfText,
                        videoBitrateText: $videoBitrateText,
                        onCRFChange: applyCRFText,
                        onVideoBitrateChange: applyVideoBitrateText
                    )

                    TranscodeOptionsSection(
                        enableTranscoding: $app.enableTranscoding,
                        preset: $app.transcode
                    )
                } else {
                    AudioOptionsSection(
                        format: $app.audioFormat,
                        showAdvanced: $showAdvancedAudio,
                        audioBitrateText: $audioBitrateText,
                        onAudioBitrateChange: applyAudioBitrateText
                    )
                }

                SaveLocationSection(
                    defaultFolderName: app.defaultSaveFolder?.lastPathComponent ?? "Documents",
                    perDownloadFolderName: app.perDownloadFolder?.lastPathComponent ?? "—",
                    onSelectDefault: { showGlobalFolderPicker = true },
                    onSelectPerDownload: { showPerDownloadFolderPicker = true }
                )

                BehaviorSection(
                    exportToPhotos: $app.exportToPhotos,
                    supportedFormatsOnly: $app.supportedFormatsOnly,
                    enableChunkedDownload: $app.enableChunkedDownload
                )

                StatusSection(
                    showProgress: app.showProgress,
                    progress: app.progress,
                    infoTitle: app.info?.title,
                    outputFileName: app.outputFileURL?.lastPathComponent,
                    errorMessage: app.error?.localizedDescription,
                    exceptionDescription: app.exception.map(String.init(describing:))
                )

                DownloadsListView(downloads: app.downloads)

                aboutSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("YoutubeDL")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showBrowser = true
                    } label: {
                        Label("Open Browser", systemImage: "safari")
                            .labelStyle(.iconOnly)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Text(app.youtubeDL.version ?? "yt-dlp: ?")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .sheet(isPresented: $showBrowser) {
                BrowserView()
            }
            .sheet(isPresented: $showGlobalFolderPicker) {
                FolderPicker(initialURL: app.defaultSaveFolder) { picked in
                    app.setGlobalSaveFolder(url: picked)
                }
            }
            .sheet(isPresented: $showPerDownloadFolderPicker) {
                FolderPicker(initialURL: app.perDownloadFolder ?? app.defaultSaveFolder) { picked in
                    app.setPerDownloadFolder(url: picked)
                }
            }
            .sheet(item: Binding(
                get: { app.webViewURL.map { WebSheet(url: $0) } },
                set: { app.webViewURL = $0?.url }
            )) { sheet in
                WebViewSheet(url: sheet.url) { discoveredURL in
                    app.webViewURL = nil
                    app.url = discoveredURL
                }
            }
            .onAppear(perform: syncNumericFieldsFromModel)
            .alert(alertMessage, isPresented: $showAlert) {
                Button("OK", role: .cancel) { }
            }
        }
    }

    private var aboutSection: some View {
        Section {
            LabeledContent("yt-dlp", value: app.youtubeDL.version ?? "unknown")
            LabeledContent("App Model", value: "v2")
        } header: {
            Label("About", systemImage: "ellipsis.circle")
        }
    }

    // MARK: - Actions

    private func pasteFromClipboard() {
        let pasteboard = UIPasteboard.general
        if let url = pasteboard.url ?? pasteboard.string.flatMap({ URL(string: $0) }) {
            urlString = url.absoluteString
        } else {
            presentAlert("Clipboard does not contain a URL")
        }
    }

    private func startDownloadTapped() {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed) else {
            presentAlert("Invalid URL")
            return
        }

        applyCRFText()
        applyVideoBitrateText()
        applyAudioBitrateText()
        app.url = url
    }

    private func presentAlert(_ message: String) {
        alertMessage = message
        showAlert = true
    }

    private func syncNumericFieldsFromModel() {
        crfText = app.videoCRF.map(String.init) ?? ""
        videoBitrateText = app.videoBitrateKbps.map(String.init) ?? ""
        audioBitrateText = app.audioBitrateKbps.map(String.init) ?? ""
    }

    private func applyCRFText() {
        let trimmed = crfText.trimmingCharacters(in: .whitespacesAndNewlines)
        app.videoCRF = Int(trimmed)
        if app.videoCRF == nil && !trimmed.isEmpty {
            crfText = ""
        }
    }

    private func applyVideoBitrateText() {
        let trimmed = videoBitrateText.trimmingCharacters(in: .whitespacesAndNewlines)
        app.videoBitrateKbps = Int(trimmed)
        if app.videoBitrateKbps == nil && !trimmed.isEmpty {
            videoBitrateText = ""
        }
    }

    private func applyAudioBitrateText() {
        let trimmed = audioBitrateText.trimmingCharacters(in: .whitespacesAndNewlines)
        app.audioBitrateKbps = Int(trimmed)
        if app.audioBitrateKbps == nil && !trimmed.isEmpty {
            audioBitrateText = ""
        }
    }
}
