//
//  MainView.swift
//
//  Copyright (c) 2020 Changbeom Ahn
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.
//

import SwiftUI
import YoutubeDL
import PythonKit
import FFmpegSupport
import AVFoundation

@available(iOS 13.0.0, *)
struct MainView: View {
    @State var alertMessage: String?
    
    @State var isShowingAlert = false
    
    @State var info: Info?
    
    @State var error: Error? {
        didSet {
            alertMessage = error?.localizedDescription
            isShowingAlert = true
        }
    }
    
    @EnvironmentObject var app: AppModel
    
    @State var indeterminateProgressKey: String?
    
    @State var isTranscodingEnabled = true
    
    @State var isRemuxingEnabled = true
    
    @State var urlString = ""
    
    @State var isExpanded = true
    
    @State var expandOptions = true
    
    @State var formats: ([([Format], String)])?
    
    @State var formatsContinuation: FormatsContinuation?
    
    var body: some View {
        List {
            Section {
                DownloadsView()
            }
            
            Section {
                DisclosureGroup(isExpanded: $isExpanded) {
                    Button("Paste URL") {
                        let pasteBoard = UIPasteboard.general
                        //                guard pasteBoard.hasURLs || pasteBoard.hasStrings else {
                        //                    alert(message: "Nothing to paste")
                        //                    return
                        //                }
                        guard let url = pasteBoard.url ?? pasteBoard.string.flatMap({ URL(string: $0) }) else {
                            alert(message: "Nothing to paste")
                            return
                        }
                        urlString = url.absoluteString
                        self.app.url = url
                    }
                    Button(#"Prepend "y" to URL in Safari"#) {
                        // FIXME: open Safari
                        open(url: URL(string: "https://youtube.com")!)
                    }
                    Button("Download shortcut") {
                        // FIXME: open Shortcuts
                        open(url: URL(string: "https://www.icloud.com/shortcuts/e226114f6e6c4440b9c466d1ebe8fbfc")!)
                    }
                } label: {
                    TextField("URL", text: $urlString)
                        .onSubmit {
                            guard let url = URL(string: urlString) else {
                                alert(message: "Invalid URL")
                                return
                            }
                            app.url = url
                        }
                }
            }
            
            if let key = indeterminateProgressKey {
                ProgressView(key)
                    .frame(maxWidth: .infinity)
            }
            
            if info != nil {
                Section {
                    Text(info?.title ?? "nil?")
                }
                
                Section {
                    DisclosureGroup("Options", isExpanded: $expandOptions) {
                        Toggle("Fast Download", isOn: $app.enableChunkedDownload)
                        Toggle("Enable Transcoding", isOn: $app.enableTranscoding)
                        Toggle("Hide Unsupported Formats", isOn: $app.supportedFormatsOnly)
                        Toggle("Copy to Photos", isOn: $app.exportToPhotos)
                    }
                }
            }
           
            if let progress = app.youtubeDL?.downloader.progress {
                ProgressView(progress)
            }
            
            app.youtubeDL?.version.map { Text("yt-dlp version \($0)") }
        }
        .onAppear(perform: {
            app.formatSelector = { info in
                indeterminateProgressKey = nil
                self.info = info
                
                let (formats, timeRange) = await withCheckedContinuation { continuation in
                    check(info: info, continuation: continuation)
                }
                
                var url: URL?
                if !formats.isEmpty {
                    url = save(info: info)
                }
                
                return (formats, url, timeRange, formats.first?.vbr)
            }
        })
        .onChange(of: app.url) { newValue in
            guard let url = newValue else { return }
            urlString = url.absoluteString
            indeterminateProgressKey = "Extracting info"
            guard isExpanded else { return }
            isExpanded = false
        }
        .alert(isPresented: $isShowingAlert) {
            Alert(title: Text(alertMessage ?? "no message?"))
        }
//        .sheet(item: $app.fileURL) { url in
////            TrimView(url: url)
//        }
        .sheet(item: $formats) {
            // FIXME: cancel download
        } content: { formats in
            DownloadOptionsView(formats: formats, duration: info!.duration, continuation: formatsContinuation!)
        }
    }
    
    func open(url: URL) {
        UIApplication.shared.open(url, options: [:]) {
            if !$0 {
                alert(message: "Failed to open \(url)")
            }
        }
    }
   
    func alert(message: String) {
        alertMessage = message
        isShowingAlert = true
    }
    
    func check(info: Info?, continuation: FormatsContinuation) {
        guard let formats = info?.formats else {
            continuation.resume(returning: ([], nil))
            return
        }
        
        let _bestAudio = formats.filter { $0.isAudioOnly && $0.ext == "m4a" }.last
        let _bestVideo = formats.filter {
            $0.isVideoOnly && (isTranscodingEnabled || !$0.isTranscodingNeeded) }.last
        let _best = formats.filter { !$0.isRemuxingNeeded && !$0.isTranscodingNeeded }.last
        print(_best ?? "no best?", _bestVideo ?? "no bestvideo?", _bestAudio ?? "no bestaudio?")
        guard let best = _best, let bestVideo = _bestVideo, let bestAudio = _bestAudio,
              let bestHeight = best.height, let bestVideoHeight = bestVideo.height
//              , bestVideoHeight > bestHeight
        else
        {
            if let best = _best {
                notify(body: String(format: NSLocalizedString("DownloadStartFormat", comment: "Notification body"),
                                    info?.title ?? NSLocalizedString("NoTitle?", comment: "Nil")))
                continuation.resume(returning: ([best], nil))
            } else if let bestVideo = _bestVideo, let bestAudio = _bestAudio {
                continuation.resume(returning: ([bestVideo, bestAudio], nil))
            } else {
                continuation.resume(returning: ([], nil))
                DispatchQueue.main.async {
                    self.alert(message: NSLocalizedString("NoSuitableFormat", comment: "Alert message"))
                }
            }
            return
        }

        formatsContinuation = continuation
        self.formats = [
            ([best],
             String(format: NSLocalizedString("BestFormat", comment: "Alert action"),
                    bestHeight)),
            ([bestVideo, bestAudio],
             String(format: NSLocalizedString("RemuxingFormat", comment: "Alert action"),
                    bestVideo.ext,
                    bestAudio.ext,
                    bestVideoHeight)),
        ]
    }
    
    func save(info: Info) -> URL? {
        do {
            return try app.save(info: info)
        } catch {
            print(#function, error)
            self.error = error
            return nil
        }
    }
}

extension Array: Identifiable where Element == ([Format], String) {
    public var id: [String] { map(\.0).flatMap { $0.map(\.format_id) } }
}

typealias TimeRange = Range<TimeInterval>

typealias FormatsContinuation = CheckedContinuation<([Format], TimeRange?), Never>

struct DownloadOptionsView: View {
    let formats: [([Format], String)]
    
    let duration: Int
    
    let continuation: FormatsContinuation
    
    @AppStorage(wrappedValue: true, "cut") var cut: Bool
    
    @State var start = "0"
    @State var end: String
    @State var length: String
    
    enum Fields: Hashable {
        case start, end, length
    }
    
    @FocusState var focus: Fields?
    
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        Form {
            ForEach(formats, id: \.1) { format in
                Button {
                    let s = seconds(start) ?? 0
                    let e = seconds(end) ?? 0
                    guard !cut || s < e else {
                        print("invalid time range")
                        return
                    }
                    let timeRange = cut ? TimeInterval(s)..<TimeInterval(e) : nil
                    continuation.resume(returning: (format.0, timeRange))
                    
                    dismiss()
                } label: {
                    Text(format.1)
                }
            }
            
            Section {
                HStack {
                    TextField("Start", text: $start)
                        .multilineTextAlignment(.trailing)
                        .focused($focus, equals: .start)
                    Text("~")
                    TextField("End", text: $end)
                        .multilineTextAlignment(.leading)
                        .focused($focus, equals: .end)
                    TextField("Length", text: $length)
                        .multilineTextAlignment(.trailing)
                        .focused($focus, equals: .length)
                }
                .disabled(!cut)
            } header: {
                Toggle("자르기", isOn: $cut)
            } footer: {
                Text("짧게 자를수록 변환이 빨리 끝납니다.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
        .onChange(of: start) { newValue in
            updateLength(start: newValue, end: end)
        }
        .onChange(of: end) { newValue in
            guard focus == .end else { return }
            updateLength(start: start, end: newValue)
        }
        .onChange(of: length) { newValue in
            guard focus == .length else { return }
            updateEnd(start: start, length: length)
        }
    }
    
    init(formats: [([Format], String)], duration: Int, continuation: FormatsContinuation) {
        self.formats = formats
        self.duration = duration
        
        self.continuation = continuation
        
        let string = format(duration) ?? ""
        _end = State(initialValue: string)
        _length = State(initialValue: string)
    }

    func updateLength(start: String, end: String) {
        guard let s = seconds(start), let e = seconds(end) else {
            return
        }
        let l = e - s
        length = format(l) ?? length
    }
    
    func updateEnd(start: String, length: String) {
        guard let s = seconds(start), let l = seconds(length) else {
            return
        }
        let e = s + l
        end = format(e) ?? end
    }
}

extension URL: Identifiable {
    public var id: URL { self }
}

//import MobileVLCKit

struct TrimView: View {
    class Model: NSObject, ObservableObject
//    , VLCMediaPlayerDelegate
    {
        let url: URL
        
//        lazy var player: VLCMediaPlayer = {
//            let player = VLCMediaPlayer()
//            player.media = VLCMedia(url: url)
//            player.delegate = self
//            return player
//        }()
        
        init(url: URL) {
            self.url = url
        }
    }
    
    @StateObject var model: Model
    
    @EnvironmentObject var app: AppModel
    
//    var drag: some Gesture {
//        DragGesture()
//            .onChanged { value in
//                let f = value.location.x / (model.player.drawable as! UIView).bounds.width
//                let t = f * CGFloat(model.player.media.length.intValue) / 1000
//                time = Date(timeIntervalSince1970: t)
//            }
//            .onEnded { value in
//                let f = value.location.x / (model.player.drawable as! UIView).bounds.width
//                let t = f * CGFloat(model.player.media.length.intValue)
//                model.player.time = VLCTime(int: Int32(t))
//            }
//    }
    
    @State var time = Date(timeIntervalSince1970: 0)
        
    let timeFormatter: Formatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()
    
    @State var start = ""
    
    @State var length = ""
    
    @State var end = ""
    
    enum FocusedField: Hashable {
        case start, length, end
    }
    
    @FocusState var focus: FocusedField?
    
    var body: some View {
        VStack {
//            Text(time, formatter: timeFormatter)
//            VLCView(player: model.player)
            TextField("Start", text: $start)
                .focused($focus, equals: .start)
            TextField("Length", text: $length)
                .focused($focus, equals: .length)
            TextField("End", text: $end)
                .focused($focus, equals: .end)
            Button {
//                if model.player.isPlaying {
//                    model.player.pause()
//                } else {
//                    model.player.play()
//                }
                Task {
                    await transcode()
                }
            } label: {
                Text(
//                    model.player.isPlaying ? "Pause" :
                        "Transcode")
            }
        }
//        .gesture(drag)
        .onChange(of: start) { newValue in
            updateLength(start: newValue, end: end)
        }
        .onChange(of: end) { newValue in
            guard focus == .end else { return }
            updateLength(start: start, end: newValue)
        }
        .onChange(of: length) { newValue in
            guard focus == .length else { return }
            updateEnd(start: start, length: length)
        }
    }
    
    init(url: URL) {
        _model = StateObject(wrappedValue: Model(url: url))
    }
    
    func transcode() async {
        let s = seconds(start) ?? 0
        let e = seconds(end) ?? 0
        guard s < e else {
            print(#function, "invalid interval:", start, "~", end)
            return
        }
        let out = model.url.deletingPathExtension().appendingPathExtension("mp4")
        try? FileManager.default.removeItem(at: out)
        let pipe = Pipe()
        Task {
            for try await line in pipe.fileHandleForReading.bytes.lines {
                print(#function, line)
            }
        }
        let t0 = Date()
        let ret = ffmpeg("FFmpeg-iOS",
                         "-progress", "pipe:\(pipe.fileHandleForWriting.fileDescriptor)",
                         "-nostats",
                         "-ss", start,
                         "-t", length,
                         "-i", model.url.path,
                         out.path)
        print(#function, ret, "took", Date().timeIntervalSince(t0), "seconds")
        
        let audio = URL(fileURLWithPath: out.path.replacingOccurrences(of: "-otherVideo.mp4", with: "-audioOnly.m4a"))
        let final = URL(fileURLWithPath: out.path.replacingOccurrences(of: "-otherVideo", with: ""))
        let timeRange = CMTimeRange(start: CMTime(seconds: Double(s), preferredTimescale: 1),
                                    end: CMTime(seconds: Double(e), preferredTimescale: 1))
        mux(videoURL: out, audioURL: audio, outputURL: final, timeRange: timeRange)
    }
    
    func mux(videoURL: URL, audioURL: URL, outputURL: URL, timeRange: CMTimeRange) {
        let t0 = ProcessInfo.processInfo.systemUptime
       
        let videoAsset = AVAsset(url: videoURL)
        let audioAsset = AVAsset(url: audioURL)
        
        guard let videoAssetTrack = videoAsset.tracks(withMediaType: .video).first,
              let audioAssetTrack = audioAsset.tracks(withMediaType: .audio).first else {
            print(#function,
                  videoAsset.tracks(withMediaType: .video),
                  audioAsset.tracks(withMediaType: .audio))
            return
        }
        
        let composition = AVMutableComposition()
        let videoCompositionTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        let audioCompositionTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        
        do {
            try videoCompositionTrack?.insertTimeRange(CMTimeRange(start: .zero, duration: videoAssetTrack.timeRange.duration), of: videoAssetTrack, at: .zero)
            try audioCompositionTrack?.insertTimeRange(timeRange, of: audioAssetTrack, at: .zero)
            print(#function, videoAssetTrack.timeRange, audioAssetTrack.timeRange)
        }
        catch {
            print(#function, error)
            return
        }
        
        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
            print(#function, "unable to init export session")
            return
        }
        
        session.outputURL = outputURL
        session.outputFileType = .mp4
        print(#function, "merging...")
        
        session.exportAsynchronously {
            print(#function, "finished merge", session.status.rawValue)
            print(#function, "took", ProcessInfo.processInfo.systemUptime - t0, "seconds")
            if session.status == .completed {
                print(#function, "success")
            } else {
                print(#function, session.error ?? "no error?")
            }
        }
    }

    func updateLength(start: String, end: String) {
        guard let s = seconds(start), let e = seconds(end) else {
            return
        }
        let l = e - s
        length = format(l) ?? length
    }
    
    func updateEnd(start: String, length: String) {
        guard let s = seconds(start), let l = seconds(length) else {
            return
        }
        let e = s + l
        end = format(e) ?? end
    }
}
    
func seconds(_ string: String) -> Int? {
    let components = string.split(separator: ":")
    guard components.count <= 3 else {
        print(#function, "too many components:", string)
        return nil
    }
    
    var seconds = 0
    for component in components {
        guard let number = Int(component) else {
            print(#function, "invalid number:", component)
            return nil
        }
        seconds = 60 * seconds + number
    }
    return seconds
}

//struct VLCView: UIViewRepresentable {
//    let player: VLCMediaPlayer
//
//    func makeUIView(context: Context) -> UIView {
//        let view = UIView()
//        player.drawable = view
//        return view
//    }
//
//    func updateUIView(_ uiView: UIView, context: Context) {
//        //
//    }
//}

import WebKit

struct WebView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        return webView
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {
        //
    }
    
    class Coordinator: NSObject, WKNavigationDelegate {
        
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
}

struct DownloadsView: View {
    @EnvironmentObject var app: AppModel
    
    var body: some View {
        ForEach(app.downloads) { download in
            NavigationLink(download.lastPathComponent, destination: DetailsView(url: download))
        }
    }
}

struct DetailsView: View {
    let url: URL
    
    @State var info: Info?
    
    @State var isExpanded = false
    
    @State var videoURL: URL?
    
    var body: some View {
        List {
            if let videoURL = videoURL {
                Section {
                    NavigationLink("Trim", destination: TrimView(url: videoURL))
                }
            }
            
            if let info = info {
                DisclosureGroup("\(info.formats.count) Formats", isExpanded: $isExpanded) {
                    ForEach(info.formats) { format in
                        Text(format.format)
                    }
                }
            }
        }
        .task {
            do {
                info = try JSONDecoder().decode(Info.self,
                                                from: try Data(contentsOf: url.appendingPathComponent("Info.json")))
                
                videoURL = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.contentTypeKey], options: .skipsHiddenFiles).first { url in
                    try! url.resourceValues(forKeys: [.contentTypeKey])
                        .contentType?.conforms(to: .movie)
                    ?? false
                }
            } catch {
                print(error)
            }
        }
    }
}

extension Format: Identifiable {
    public var id: String { format_id }
}

//@available(iOS 13.0.0, *)
//struct MainView_Previews: PreviewProvider {
//    static var previews: some View {
//        MainView()
//            .environmentObject(AppModel())
//    }
//}
