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

@available(iOS 13.0.0, *)
struct MainView: View {
    @State var alertMessage: String?
    
    @State var isShowingAlert = false
    
    @State var url: URL? {
        didSet {
            guard let url = url else {
                return
            }
            
            extractInfo(url: url)
        }
    }
    
    @State var info: Info?
    
    @State var error: Error?
    
    @State var youtubeDL: YoutubeDL?
    
    @State var indeterminateProgressKey: String?
    
    @State var isTranscodingEnabled = true
    
    @State var isRemuxingEnabled = true
    
    @State var showingFormats = false
    
    @State var formatsSheet: ActionSheet?

    @State var progress: Progress?
    
    var body: some View {
        List {
            if url != nil {
                Text(url?.absoluteString ?? "nil?")
            }
            
            if info != nil {
                Text(info?.title ?? "nil?")
            }
            
            if let key = indeterminateProgressKey {
                if #available(iOS 14.0, *) {
                    ProgressView(key)
                } else {
                    Text(key)
                }
            }
            
            if let progress = progress {
                if #available(iOS 14.0, *) {
                    ProgressView(progress)
                } else {
                    Text("\(progress)")
                }
            }
            
            youtubeDL?.version.map { Text("youtube_dl version \($0)") }
            
            Button("Paste URL") {
                let pasteBoard = UIPasteboard.general
//                guard pasteBoard.hasURLs || pasteBoard.hasStrings else {
//                    alert(message: "Nothing to paste")
//                    return
//                }
                // FIXME: paste
                guard let url = pasteBoard.url ?? pasteBoard.string.flatMap({ URL(string: $0) }) else {
                    alert(message: "Nothing to paste")
                    return
                }
                self.url = url
            }
            Button(#"Prepend "y" to URL in Safari"#) {
                // FIXME: open Safari
                open(url: URL(string: "https://youtube.com")!)
            }
            Button("Download shortcut") {
                // FIXME: open Shortcuts
                open(url: URL(string: "https://www.icloud.com/shortcuts/e226114f6e6c4440b9c466d1ebe8fbfc")!)
            }
        }
        .alert(isPresented: $isShowingAlert) {
            Alert(title: Text(alertMessage ?? "no message?"))
        }
        .actionSheet(isPresented: $showingFormats) { () -> ActionSheet in
            formatsSheet ?? ActionSheet(title: Text("nil?"))
        }
    }
    
    func open(url: URL) {
        UIApplication.shared.open(url, options: [:]) {
            if !$0 {
                alert(message: "Failed to open \(url)")
            }
        }
    }
    
    func extractInfo(url: URL) {
        guard let youtubeDL = youtubeDL else {
            loadPythonModule()
            return
        }
        
        indeterminateProgressKey = "Extracting info..."
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let (_, info) = try youtubeDL.extractInfo(url: url)
                DispatchQueue.main.async {
                    indeterminateProgressKey = nil
                    self.info = info
                    
                    check(info: info)
                }
            }
            catch {
                self.error = error
            }
        }
    }
    
    func loadPythonModule() {
        guard FileManager.default.fileExists(atPath: YoutubeDL.pythonModuleURL.path) else {
            downloadPythonModule()
            return
        }
        indeterminateProgressKey = "Loading Python module..."
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                youtubeDL = try YoutubeDL()
                DispatchQueue.main.async {
                    indeterminateProgressKey = nil
                    
                    url.map { extractInfo(url: $0) }
                }
            }
            catch {
                DispatchQueue.main.async {
                    alert(message: error.localizedDescription)
                }
            }
        }
    }
    
    func downloadPythonModule() {
        indeterminateProgressKey = "Downloading Python module..."
        YoutubeDL.downloadPythonModule { error in
            DispatchQueue.main.async {
                indeterminateProgressKey = nil
                guard error == nil else {
                    self.alert(message: error?.localizedDescription ?? "nil?")
                    return
                }

                loadPythonModule()
            }
        }
    }

    func alert(message: String) {
        alertMessage = message
        isShowingAlert = true
    }
    
    func check(info: Info?) {
        guard let formats = info?.formats else {
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
                download(format: best, start: true, faster: false)
            } else if let bestVideo = _bestVideo, let bestAudio = _bestAudio {
                download(format: bestVideo, start: true, faster: true)
                download(format: bestAudio, start: false, faster: true)
            } else {
                DispatchQueue.main.async {
                    self.alert(message: NSLocalizedString("NoSuitableFormat", comment: "Alert message"))
                }
            }
            return
        }
        
        formatsSheet = ActionSheet(title: Text("ChooseFormat"), message: Text("SomeFormatsNeedTranscoding"), buttons: [
            .default(Text(String(format: NSLocalizedString("BestFormat", comment: "Alert action"), bestHeight)),
                     action: {
                        self.download(format: best, start: true, faster: false)
                     }),
            .default(Text(String(format: NSLocalizedString("RemuxingFormat", comment: "Alert action"),
                                 bestVideo.ext ?? NSLocalizedString("NoExt?", comment: "Nil"),
                                 bestAudio.ext ?? NSLocalizedString("NoExt?", comment: "Nil"),
                                 bestVideoHeight)),
                     action: {
                        self.download(format: bestVideo, start: true, faster: true)
                        self.download(format: bestAudio, start: false, faster: true)
                     }),
            .cancel()
        ])

        DispatchQueue.main.async {
            showingFormats = true
        }
    }
    
    func download(format: Format, start: Bool, faster: Bool) {
        let kind: Downloader.Kind = format.isVideoOnly
            ? (!format.isTranscodingNeeded ? .videoOnly : .otherVideo)
            : (format.isAudioOnly ? .audioOnly : .complete)

        var requests: [URLRequest] = []
        
        if faster, let size = format.filesize {
            if !FileManager.default.createFile(atPath: kind.url.part.path, contents: Data(), attributes: nil) {
                print(#function, "couldn't create \(kind.url.part.lastPathComponent)")
            }

            var end: Int64 = -1
            while end < size - 1 {
                guard var request = format.urlRequest else { fatalError() }
                // https://github.com/ytdl-org/youtube-dl/issues/15271#issuecomment-362834889
                end = request.setRange(start: end + 1, fullSize: size)
                requests.append(request)
            }
        } else {
            guard let request = format.urlRequest else { fatalError() }
            requests.append(request)
        }

        let tasks = requests.map { Downloader.shared.download(request: $0, kind: kind) }

        if start {
            progress = Downloader.shared.progress
            progress?.kind = .file
            progress?.fileOperationKind = .downloading
            do {
                try "".write(to: kind.url, atomically: false, encoding: .utf8)
            }
            catch {
                print(error)
            }
            progress?.fileURL = kind.url

            Downloader.shared.t0 = ProcessInfo.processInfo.systemUptime
            tasks.first?.resume()
        }
    }
}

@available(iOS 13.0.0, *)
struct MainView_Previews: PreviewProvider {
    static var previews: some View {
        MainView()
    }
}
