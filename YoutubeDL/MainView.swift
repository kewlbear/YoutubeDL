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
    
    @State var showingFormats = false
    
    @State var formatsSheet: ActionSheet?

    @State var urlString = ""
    
    @State var isExpanded = true
    
    @State var expandOptions = true
    
    var body: some View {
        List {
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
                
                return await withCheckedContinuation { continuation in
                    check(info: info, continuation: continuation)
                }
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
   
    func alert(message: String) {
        alertMessage = message
        isShowingAlert = true
    }
    
    func check(info: Info?, continuation: CheckedContinuation<[Format], Never>) {
        guard let formats = info?.formats else {
            continuation.resume(returning: [])
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
                continuation.resume(returning: [best])
            } else if let bestVideo = _bestVideo, let bestAudio = _bestAudio {
                continuation.resume(returning: [bestVideo, bestAudio])
            } else {
                continuation.resume(returning: [])
                DispatchQueue.main.async {
                    self.alert(message: NSLocalizedString("NoSuitableFormat", comment: "Alert message"))
                }
            }
            return
        }

        formatsSheet = ActionSheet(title: Text("ChooseFormat"), message: Text("SomeFormatsNeedTranscoding"), buttons: [
            .default(Text(String(format: NSLocalizedString("BestFormat", comment: "Alert action"), bestHeight)),
                     action: {
                         continuation.resume(returning: [best])
                     }),
            .default(Text(String(format: NSLocalizedString("RemuxingFormat", comment: "Alert action"),
                                 bestVideo.ext ?? NSLocalizedString("NoExt?", comment: "Nil"),
                                 bestAudio.ext ?? NSLocalizedString("NoExt?", comment: "Nil"),
                                 bestVideoHeight)),
                     action: {
                         continuation.resume(returning: [bestVideo, bestAudio])
                     }),
            .cancel() {
                continuation.resume(returning: [])
            }
        ])

        DispatchQueue.main.async {
            showingFormats = true
        }
    }
}

@available(iOS 13.0.0, *)
struct MainView_Previews: PreviewProvider {
    static var previews: some View {
        MainView()
            .environmentObject(AppModel())
    }
}
