//
//  MainView.swift
//  YoutubeDL
//
//  Full SwiftUI MainView that binds to AppModel.swift
//  Contains all UI pieces in one file (as requested):
//  - URL input, paste, download
//  - Kind, Quality, Container, AudioFormat, Transcode
//  - Advanced fields (CRF, bitrates)
//  - Save folder pickers (global & per-download)
//  - Progress card, status, downloads history
//  - WebView-based fallback sheet for sites like Instagram
//

import SwiftUI
import UniformTypeIdentifiers
import WebKit
import AVFoundation

@available(iOS 15.0, *)
public struct MainView: View {
    @EnvironmentObject public var app: AppModel

    // URL input
    @State private var urlString: String = ""
    @State private var showAlert: Bool = false
    @State private var alertMessage: String = ""

    // Folder pickers
    @State private var showGlobalFolderPicker: Bool = false
    @State private var showPerDownloadFolderPicker: Bool = false

    // Browser / webview
    @State private var showBrowser: Bool = false

    // Advanced toggles
    @State private var showAdvancedVideo: Bool = false
    @State private var showAdvancedAudio: Bool = false

    // editable text fields for numeric entries
    @State private var crfText: String = ""
    @State private var vBitrateText: String = ""
    @State private var aBitrateText: String = ""

    public init() {}

    public var body: some View {
        NavigationView {
            List {
                urlInputSection
                whatToDownloadSection

                if app.kind != .audio {
                    videoOptionsSection
                    transcodePresetSection
                } else {
                    audioOptionsSection
                }

                saveLocationSection
                behaviorSection

                statusSection

                downloadsHistorySection

                aboutSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("YoutubeDL")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showBrowser = true
                    } label: {
                        Image(systemName: "safari")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Text(app.youtubeDL.version ?? "yt-dlp: ?")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .sheet(isPresented: $showBrowser) { BrowserView() }
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
                set: { newVal in app.webViewURL = newVal?.url }
            )) { sheet in
                WebViewSheet(url: sheet.url) { discoveredURL in
                    // close and kick off download with discovered src
                    app.webViewURL = nil
                    app.url = discoveredURL
                }
            }
            .onAppear {
                syncNumericFieldsFromModel()
            }
            .alert(isPresented: $showAlert) {
                Alert(title: Text(alertMessage))
            }
        }
    }

    // MARK: - Sections

    private var urlInputSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    TextField("Enter URL or paste", text: $urlString)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .keyboardType(.URL)
                        .onSubmit { startDownloadTapped() }

                    Button(action: pasteFromClipboard) {
                        Image(systemName: "doc.on.clipboard")
                    }
                    .buttonStyle(.borderless)
                }

                HStack {
                    Spacer()
                    Button(action: startDownloadTapped) {
                        Label("Download", systemImage: "arrow.down.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    Spacer()
                }
            }
        } header: {
            Label("Download URL", systemImage: "link")
        }
    }

    private var whatToDownloadSection: some View {
        Section {
            Picker("Kind", selection: $app.kind) {
                ForEach(DownloadKind.allCases, id: \.self) { k in
                    Text(k.rawValue).tag(k)
                }
            }
            .pickerStyle(.segmented)
        } header: {
            Label("What to download", systemImage: "switch.2")
        }
    }

    private var videoOptionsSection: some View {
        Section {
            HStack {
                Label("Quality", systemImage: "sparkles")
                Spacer()
                Picker("Quality", selection: $app.videoQuality) {
                    ForEach(VideoQuality.allCases, id: \.self) { q in
                        Text(q.rawValue).tag(q)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 220)
            }

            HStack {
                Label("Container", systemImage: "tray")
                Spacer()
                Picker("Container", selection: $app.container) {
                    ForEach(ContainerFormat.allCases, id: \.self) { c in
                        Text(c.rawValue.uppercased()).tag(c)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 220)
            }

            DisclosureGroup("Advanced Video Options", isExpanded: $showAdvancedVideo) {
                VStack(spacing: 8) {
                    HStack {
                        Text("CRF")
                        Spacer()
                        TextField("auto", text: $crfText)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 120)
                            .keyboardType(.numberPad)
                            .onChange(of: crfText) { _ in applyCRFText() }
                    }
                    HStack {
                        Text("Video Bitrate (kbps)")
                        Spacer()
                        TextField("auto", text: $vBitrateText)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 120)
                            .keyboardType(.numberPad)
                            .onChange(of: vBitrateText) { _ in applyVBitrateText() }
                    }
                    Text("Leave empty for auto. CRF prioritized when bitrate is not set.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 6)
            }
        } header: {
            Label("Video Options", systemImage: "film")
        }
    }

    private var transcodePresetSection: some View {
        Section {
            HStack {
                Label("Transcode Preset", systemImage: "cpu")
                Spacer()
                Picker("Preset", selection: $app.transcode) {
                    ForEach(TranscodePreset.allCases, id: \.self) { p in
                        Text(p.rawValue).tag(p)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 220)
            }

            Text(helpTextForPreset(app.transcode))
                .font(.footnote)
                .foregroundStyle(.secondary)
        } header: {
            Label("Transcoding", systemImage: "scissors")
        }
    }

    private var audioOptionsSection: some View {
        Section {
            HStack {
                Label("Audio Format", systemImage: "music.note")
                Spacer()
                Picker("Audio Format", selection: $app.audioFormat) {
                    ForEach(AudioFormat.allCases, id: \.self) { f in
                        Text(f.rawValue.uppercased()).tag(f)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 220)
            }

            DisclosureGroup("Advanced Audio Options", isExpanded: $showAdvancedAudio) {
                VStack(spacing: 8) {
                    HStack {
                        Text("Audio Bitrate (kbps)")
                        Spacer()
                        TextField("auto", text: $aBitrateText)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 120)
                            .keyboardType(.numberPad)
                            .onChange(of: aBitrateText) { _ in applyABitrateText() }
                    }
                    Text("Set if you want a target kbps for audio (mp3/aac).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 6)
            }
        } header: {
            Label("Audio Options", systemImage: "headphones")
        }
    }

    private var saveLocationSection: some View {
        Section {
            HStack {
                Label("Default Save Folder", systemImage: "externaldrive")
                Spacer()
                Text(app.defaultSaveFolder?.lastPathComponent ?? "Documents")
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
            .onTapGesture { showGlobalFolderPicker = true }

            HStack {
                Label("Per-download Folder", systemImage: "folder.badge.plus")
                Spacer()
                Text(app.perDownloadFolder?.lastPathComponent ?? "—")
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
            .onTapGesture { showPerDownloadFolderPicker = true }
        } header: {
            Label("Save Location", systemImage: "folder")
        }
    }

    private var behaviorSection: some View {
        Section {
            Toggle(isOn: $app.exportToPhotos) {
                Label("Export to Photos (video)", systemImage: "photo.on.rectangle.angled")
            }
            Toggle(isOn: $app.supportedFormatsOnly) {
                Label("Prefer iOS-friendly streams (H.264/AAC)", systemImage: "iphone")
            }

            Toggle(isOn: Binding(
                get: { UIApplication.shared.isIdleTimerDisabled },
                set: { UIApplication.shared.isIdleTimerDisabled = $0 }
            )) {
                Text("Keep screen on while downloading")
            }
        } header: {
            Label("Behavior", systemImage: "gearshape")
        }
    }

    private var statusSection: some View {
        Section {
            if app.showProgress {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "arrow.down.circle")
                        Text("Downloading…").fontWeight(.semibold)
                        Spacer()
                        if let eta = app.progress.estimatedTimeRemaining {
                            Text("ETA \(Int(eta))s").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if let title = app.info?.title {
                        Text(title).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                    }
                    ProgressView(app.progress)
                }
            }

            if let out = app.outputFileURL {
                VStack(alignment: .leading) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        Text("Finished").fontWeight(.semibold)
                    }
                    Text(out.lastPathComponent).font(.footnote).foregroundStyle(.secondary)
                }
            }

            if let err = app.error {
                VStack(alignment: .leading) {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                        Text("Error").fontWeight(.semibold)
                    }
                    Text(err.localizedDescription).font(.footnote).foregroundStyle(.secondary)
                }
            }

            if let ex = app.exception {
                VStack(alignment: .leading) {
                    HStack {
                        Image(systemName: "exclamationmark.octagon.fill").foregroundStyle(.orange)
                        Text("Python Exception").fontWeight(.semibold)
                    }
                    Text(String(describing: ex)).font(.footnote).foregroundStyle(.secondary)
                }
            }
        } header: {
            Label("Status", systemImage: "info.circle")
        }
    }

    private var downloadsHistorySection: some View {
        Section {
            if app.downloads.isEmpty {
                Text("No downloads yet").foregroundStyle(.secondary)
            } else {
                ForEach(app.downloads, id: \.self) { dir in
                    NavigationLink(destination: DetailsViewForDirectory(url: dir)) {
                        Text(dir.lastPathComponent)
                    }
                }
            }
        } header: {
            Label("Downloads", systemImage: "tray.and.arrow.down")
        }
    }

    private var aboutSection: some View {
        Section {
            HStack {
                Text("yt-dlp version")
                Spacer()
                Text(app.youtubeDL.version ?? "unknown").foregroundStyle(.secondary)
            }
            HStack {
                Text("AppModel")
                Spacer()
                Text("v1").foregroundStyle(.secondary)
            }
        } header: {
            Label("About", systemImage: "ellipsis.circle")
        }
    }

    // MARK: - Actions & helpers

    private func pasteFromClipboard() {
        let pb = UIPasteboard.general
        if let u = pb.url ?? pb.string.flatMap({ URL(string: $0) }) {
            urlString = u.absoluteString
        } else {
            showUserAlert("Clipboard does not contain a URL")
        }
    }

    private func startDownloadTapped() {
        guard let u = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            showUserAlert("Invalid URL")
            return
        }
        // apply numeric fields to model
        applyCRFText(); applyVBitrateText(); applyABitrateText()
        app.url = u
    }

    private func showUserAlert(_ message: String) {
        alertMessage = message
        showAlert = true
    }

    private func syncNumericFieldsFromModel() {
        crfText = app.videoCRF.map(String.init) ?? ""
        vBitrateText = app.videoBitrateKbps.map(String.init) ?? ""
        aBitrateText = app.audioBitrateKbps.map(String.init) ?? ""
    }

    private func applyCRFText() {
        let t = crfText.trimmingCharacters(in: .whitespacesAndNewlines)
        app.videoCRF = Int(t)
        if app.videoCRF == nil && !t.isEmpty { crfText = "" }
    }

    private func applyVBitrateText() {
        let t = vBitrateText.trimmingCharacters(in: .whitespacesAndNewlines)
        app.videoBitrateKbps = Int(t)
        if app.videoBitrateKbps == nil && !t.isEmpty { vBitrateText = "" }
    }

    private func applyABitrateText() {
        let t = aBitrateText.trimmingCharacters(in: .whitespacesAndNewlines)
        app.audioBitrateKbps = Int(t)
        if app.audioBitrateKbps == nil && !t.isEmpty { aBitrateText = "" }
    }
}

// --------------------------------------------------
// MARK: - DetailsViewForDirectory (shows Info.json & first movie file)
// --------------------------------------------------

@available(iOS 15.0, *)
struct DetailsViewForDirectory: View {
    let url: URL
    @State private var info: Info? = nil
    @State private var videoURL: URL? = nil
    @State private var isExpanded = false

    var body: some View {
        List {
            if let info {
                Section(header: Text("Metadata")) {
                    Text(info.title).font(.headline)
                    if let duration = info.formattedDuration {
                        Text("Duration: \(duration)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if let uploader = info.uploader, !uploader.isEmpty {
                        Text("Uploader: \(uploader)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if !info.formats.isEmpty {
                        DisclosureGroup("\(info.formats.count) formats", isExpanded: $isExpanded) {
                            ForEach(info.formats) { format in
                                Text(format.summary)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            if let videoURL {
                Section(header: Text("File")) {
                    Text(videoURL.lastPathComponent)
                }
            }
        }
        .task {
            do {
                let data = try Data(contentsOf: url.appendingPathComponent("Info.json"))
                info = try JSONDecoder().decode(Info.self, from: data)

                let files = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.contentTypeKey], options: .skipsHiddenFiles)
                videoURL = files.first(where: { u in
                    (try? u.resourceValues(forKeys: [.contentTypeKey]).contentType?.conforms(to: .movie)) ?? false
                })
            } catch {
                print("DetailsViewForDirectory error:", error)
            }
        }
        .navigationTitle(url.lastPathComponent)
    }
}

// --------------------------------------------------
// MARK: - Browser & WebViewSheet for sites needing JS grab
// --------------------------------------------------

@available(iOS 15.0, *)
private struct BrowserView: View {
    @State private var address = ""
    @State private var url = URL(string: "https://instagram.com")
    var body: some View {
        VStack {
            HStack {
                TextField("https://...", text: $address)
                    .textInputAutocapitalization(.never)
                    .textFieldStyle(.roundedBorder)
                Button("Go") {
                    guard let newURL = URL(string: address.hasPrefix("https://") ? address : "https://\(address)") else { return }
                    url = newURL
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            WebViewRepresentable(url: url, handler: nil)
        }
    }
}

private struct WebSheet: Identifiable {
    let url: URL
    var id: URL { url }
}

@available(iOS 15.0, *)
private struct WebViewSheet: View {
    let url: URL
    var onFoundURL: (URL) -> Void

    var body: some View {
        WebViewRepresentable(url: url) { found in
            onFoundURL(found)
        }
    }
}

private let jsHandlerName = "yt_dl_handler"

private struct WebViewRepresentable: UIViewRepresentable {
    let url: URL?
    let handler: ((URL) -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator(handler: handler) }

    func makeUIView(context: Context) -> WKWebView {
        let w = WKWebView()
        w.navigationDelegate = context.coordinator
        w.configuration.userContentController.add(context.coordinator, name: jsHandlerName)
        return w
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        if let url, uiView.url != url {
            uiView.load(URLRequest(url: url))
        }
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        let handler: ((URL) -> Void)?
        init(handler: ((URL) -> Void)?) { self.handler = handler }
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if let s = message.body as? String, let u = URL(string: s) {
                handler?(u)
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard handler != nil else { return }
            Task { @MainActor in
                let js = """
                (function() {
                  var v = document.querySelector('video');
                  if (!v) return null;
                  return v.currentSrc || v.src || null;
                })();
                """
                for _ in 0..<20 {
                    if let res = try? await webView.evaluateJavaScript(js),
                       let s = res as? String,
                       let u = URL(string: s) {
                        handler?(u)
                        break
                    }
                    try? await Task.sleep(nanoseconds: 150_000_000)
                }
            }
        }
    }
}

// --------------------------------------------------
// MARK: - FolderPicker (UIDocumentPicker wrapper)
// --------------------------------------------------

struct FolderPicker: UIViewControllerRepresentable {
    let initialURL: URL?
    let onPick: (URL?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let pick = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.folder], asCopy: false)
        pick.delegate = context.coordinator
        pick.directoryURL = initialURL
        pick.allowsMultipleSelection = false
        return pick
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL?) -> Void
        init(onPick: @escaping (URL?) -> Void) { self.onPick = onPick }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { onPick(nil) }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { onPick(urls.first) }
    }
}

// --------------------------------------------------
// MARK: - Helpers
// --------------------------------------------------

private func helpTextForPreset(_ preset: TranscodePreset) -> String {
    switch preset {
    case .copy:
        return "No re-encode — fastest, smallest CPU. If source is AV1/VP9 the file may not be Photos-compatible."
    case .h264_fast:
        return "H.264 encoding with fast preset — good balance between speed and compatibility."
    case .h264_quality:
        return "H.264 with quality preset — slower but higher visual quality."
    case .hevc_fast:
        return "HEVC (H.265) fast — smaller files but requires modern devices to playback natively."
    case .hevc_quality:
        return "HEVC quality — best efficiency, slower encoding."
    case .vp9_fast:
        return "VP9 (WebM) — web-optimized, may not be Photos-compatible."
    case .vp9_quality:
        return "VP9 high quality — large CPU cost, WEBM container."
    }
}

private func secondsFromHMSString(_ string: String) -> Int? {
    let parts = string.split(separator: ":").map(String.init)
    guard parts.count <= 3, parts.allSatisfy({ Int($0) != nil }) else { return nil }
    var total = 0
    for part in parts { total = total * 60 + (Int(part) ?? 0) }
    return total
}

private func formatSecondsToHMS(_ value: Int) -> String {
    if value < 0 { return "0:00" }
    let h = value / 3600
    let m = (value % 3600) / 60
    let s = value % 60
    if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
    return String(format: "%d:%02d", m, s)
}
