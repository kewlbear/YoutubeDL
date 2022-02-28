//
//  DownloadViewController.swift
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

import UIKit
import Photos
import AVKit
import MetalKit
import MetalPerformanceShaders
import CoreVideo
import YoutubeDL
import PythonKit

class DownloadViewController: UIViewController {

    var url: URL? {
        didSet {
            url.map {
                do {
                    try extractInfo($0)
                }
                catch {
                    print(#function, error)
                }
            }
        }
    }
    
    var info: Info?
    
    @IBOutlet weak var progressView: UIProgressView!
    
    @IBOutlet weak var pauseItem: UIBarButtonItem!
    
    @IBOutlet weak var stopItem: UIBarButtonItem!
    
    @IBOutlet weak var transcodeItem: UIBarButtonItem!
    
    var documentInteractionController: UIDocumentInteractionController?
    
    var metalView: MTKView?
    
    var device = MTLCreateSystemDefaultDevice()
    
    var textureCache: CVMetalTextureCache?
    
    var textures: [MTLTexture?] = []
    
    var commandQueue: MTLCommandQueue?
    
    var pixelBuffer: CVPixelBuffer? {
        didSet {
            updateTextures()
            metalView?.setNeedsDisplay()
        }
    }
    
    var computePipelineState: MTLComputePipelineState?
    
    var isRemuxingEnabled = true
    
    var isTranscodingEnabled = true
    
    override func viewDidLoad() {
        super.viewDidLoad()

        PHPhotoLibrary.shared().register(self)
        
        device = MTLCreateSystemDefaultDevice()
        metalView = MTKView(frame: view.bounds)
        metalView?.contentMode = .scaleAspectFit
        metalView?.device = device
        metalView?.delegate = self
        metalView?.clearColor = MTLClearColorMake(1, 1, 1, 1)
        metalView?.colorPixelFormat = .bgra8Unorm
        metalView?.framebufferOnly = false
        metalView?.autoResizeDrawable = false
        metalView?.enableSetNeedsDisplay = true
        
        _ = device.map { CVMetalTextureCacheCreate(nil, nil, $0, nil, &textureCache) }
        
        metalView.map { view.addSubview($0) }
        
        let library = device?.makeDefaultLibrary()
        let function = library?.makeFunction(name: "capturedImageFragmentShader")
//        computePipelineState = try! device?.makeComputePipelineState(function: function!)
        
        let flexibleSpace = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        toolbarItems = [
            flexibleSpace,
            UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(add(_:))),
            flexibleSpace,
        ]
    }
    
    override func viewDidAppear(_ animated: Bool) {
        guard url == nil else {
            return
        }
        
        add(toolbarItems![1])
    }
    
    @IBAction func add(_ sender: Any) {
        let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: NSLocalizedString("Paste URL", comment: "Action title"), style: .default, handler: { _ in
            let pasteBoard = UIPasteboard.general
            guard let url = pasteBoard.url ?? pasteBoard.string.flatMap({ URL(string: $0) }) else {
                self.alert(message: "Nothing to paste")
                return
            }
            self.url = url
        }))
        alert.addAction(UIAlertAction(title: NSLocalizedString(#"Prepend "y" to address in Safari "#, comment: "Action title"), style: .default, handler: { _ in
            UIApplication.shared.open(URL(string: "https://youtube.com")!, options: [:], completionHandler: nil)
        }))
        alert.addAction(UIAlertAction(title: NSLocalizedString("Download shortcut", comment: "Action title"), style: .default, handler: { _ in
            UIApplication.shared.open(URL(string: "https://www.icloud.com/shortcuts/e226114f6e6c4440b9c466d1ebe8fbfc")!, options: [:], completionHandler: nil)
        }))
        alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: "Action title"),
                                      style: .cancel, handler: nil))
        if traitCollection.userInterfaceIdiom == .pad {
            alert.popoverPresentationController?.barButtonItem = sender as? UIBarButtonItem
        }
        present(alert, animated: true, completion: nil)
    }
    
    func updateTextures() {
        guard let pixelBuffer = self.pixelBuffer else {
            return
        }
        textures = (0..<3).map { createTexture(fromPixelBuffer: pixelBuffer, pixelFormat: .r8Unorm, planeIndex: $0) }
    }
    
    func createTexture(fromPixelBuffer pixelBuffer: CVPixelBuffer, pixelFormat: MTLPixelFormat, planeIndex: Int) -> MTLTexture? {
        var mtlTexture: MTLTexture? = nil
        let width = CVPixelBufferGetWidthOfPlane(pixelBuffer, planeIndex)
        let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, planeIndex)
        
        var texture: CVMetalTexture? = nil
        let status = textureCache.map { CVMetalTextureCacheCreateTextureFromImage(nil, $0, pixelBuffer, nil, pixelFormat, width, height, planeIndex, &texture) }
        if status == kCVReturnSuccess {
            mtlTexture = CVMetalTextureGetTexture(texture!)
        }
        
        return mtlTexture
    }
    
    // MARK: - Navigation

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        switch segue.identifier {
        default:
            assertionFailure()
        }
    }
    
    @IBAction func pauseDownload(_ sender: UIBarButtonItem) {
        sender.isEnabled = false
        
        Downloader.shared.session.getTasksWithCompletionHandler { (_, _, tasks) in
            let downloading = tasks.filter { $0.state == .running }
            if downloading.isEmpty {
                tasks.filter { $0.state == .suspended }.first?.resume()
            } else {
                for task in downloading {
                    task.suspend()
                }
            }
            
            DispatchQueue.main.async {
                self.navigationItem.prompt = NSLocalizedString(downloading.isEmpty ? "Resumed" : "Paused", comment: "Prompt") 
                sender.isEnabled = true
            }
        }
    }
}

extension DownloadViewController: MTKViewDelegate {
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // FIXME: ?
    }
    
    func draw(in view: MTKView) {
        guard !textures.isEmpty,
              let commandBuffer = commandQueue?.makeCommandBuffer(),
              let drawable = view.currentDrawable,
              let device = device else
        {
            return
        }
        
        let drawingTexture = drawable.texture
        
        let encoder = commandBuffer.makeComputeCommandEncoder()
        encoder?.setComputePipelineState(computePipelineState!)
        for index in 0..<3 {
            encoder?.setTexture(textures[index], index: index)
        }
        
//        encoder?.dispatchThreadgroups(textures[0]!.thr, threadsPerThreadgroup: <#T##MTLSize#>)
        encoder?.endEncoding()
        
        commandBuffer.present(drawable)
        commandBuffer.commit()
        
        self.textures = []
    }
}

extension DownloadViewController: PHPhotoLibraryChangeObserver {
    func photoLibraryDidChange(_ changeInstance: PHChange) {
        print(changeInstance)
    }
}

extension DownloadViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        print(#function, gestureRecognizer, otherGestureRecognizer)
        return true
    }
}

let av1CodecPrefix = "av01."

extension Format {
    var isRemuxingNeeded: Bool { isVideoOnly || isAudioOnly }
    
    var isTranscodingNeeded: Bool {
        self.ext == "mp4"
            ? (self.vcodec ?? "").hasPrefix(av1CodecPrefix)
            : self.ext != "m4a"
    }
}

extension DownloadViewController {
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
        
        DispatchQueue.main.async {
            let alert = UIAlertController(title: NSLocalizedString("ChooseFormat", comment: "Alert title"),
                                          message: NSLocalizedString("SomeFormatsNeedTranscoding", comment: "Alert message"),
                                          preferredStyle: .actionSheet)
            alert.addAction(UIAlertAction(title: String(format: NSLocalizedString("BestFormat", comment: "Alert action"), bestHeight),
                                          style: .default,
                                          handler: { _ in
                                            self.download(format: best, start: true, faster: false)
                                          }))
            alert.addAction(UIAlertAction(title: String(format: NSLocalizedString("RemuxingFormat", comment: "Alert action"),
                                                        bestVideo.ext ?? NSLocalizedString("NoExt?", comment: "Nil"),
                                                        bestAudio.ext ?? NSLocalizedString("NoExt?", comment: "Nil"),
                                                        bestVideoHeight),
                                          style: .default,
                                          handler: { _ in
                                            self.download(format: bestVideo, start: true, faster: true)
                                            self.download(format: bestAudio, start: false, faster: true)
            }))
            alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: "Action title"),
                                          style: .cancel, handler: nil))
            if self.traitCollection.userInterfaceIdiom == .pad {
                alert.popoverPresentationController?.sourceView = self.progressView
                alert.popoverPresentationController?.sourceRect = self.progressView.bounds
            }
            self.present(alert, animated: true, completion: nil)
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
            Downloader.shared.t0 = ProcessInfo.processInfo.systemUptime
            tasks.first?.resume()
        }
    }
    
    @available(iOS 11.0, *)
    fileprivate func extractInfo(_ url: URL) throws {
        if YoutubeDL.shouldDownloadPythonModule {
            print(#function, "downloading python module...")
            notify(body: "Downloading Python module...")
            YoutubeDL.downloadPythonModule { error in
                DispatchQueue.main.async {
                    guard error == nil else {
                        print(#function, error ?? "no error??")
                        self.alert(message: error?.localizedDescription ?? "no error?")
                        return
                    }
                    print(#function, "downloaded python module")

                    // FIXME: better way?
    //                DispatchQueue.main.async {
    //                    self.alert(message: NSLocalizedString("Downloaded youtube_dl. Restart app.", comment: "Alert message"))
    //                }
                    do {
                        try self.extractInfo(url)
                    }
                    catch {
                        self.alert(message: error.localizedDescription)
                    }
                }
            }
            return
        }
        
        let youtubeDL = try YoutubeDL()
        
        navigationItem.title = url.absoluteString
        
        Downloader.shared.session.getAllTasks {
            for task in $0 {
                task.cancel()
            }
        }
        
        notify(body: NSLocalizedString("ExtractingInfo", comment: "Notification body"))
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                (_, self.info) = try youtubeDL.extractInfo(url: url)
                
                DispatchQueue.main.async {
                    self.navigationItem.title = self.info?.title
                }
                
                self.check(info: self.info)
            }
            catch {
                print(#function, error)
                guard let error = error as? PythonError, case let .exception(exception, traceback: _) = error else {
                    return
                }
                if (String(exception.args[0]) ?? "").contains("Unsupported URL: ") {
                    DispatchQueue.main.async {
                        self.alert(message: NSLocalizedString("Unsupported URL", comment: "Alert message"))
                    }
                }
            }
        }
    }
}

extension URL {
    var part: URL {
        appendingPathExtension("part")
    }
}

extension UIViewController {
    func alert(message: String) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Action"), style: .default, handler: nil))
        present(alert, animated: true, completion: nil)
    }
}
