//
//  DownloadViewController.swift
//  Hello World
//
//  Created by Changbeom Ahn on 2020/03/14.
//  Copyright © 2020 Jane Developer. All rights reserved.
//

import UIKit
import Photos
import AVKit
import MetalKit
import MetalPerformanceShaders
import CoreVideo

class DownloadViewController: UIViewController {

    var url: URL? {
        didSet {
            url.map { extractInfo($0) }
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
    }
    
    @IBAction
    func handlePan(_ sender: UIPanGestureRecognizer) {
        print(#function, sender)
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
    
    @IBAction func crop(_ sender: UIBarButtonItem) {
//        let fetchOptions = PHFetchOptions()
//        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "modificationDate", ascending: true)]
//        let videos = PHAsset.fetchAssets(with: .video, options: fetchOptions)
//        let video = videos[videos.count - 1]
//        print(video)
//
//        video.requestContentEditingInput(with: nil) { (contentEditingInput, info) in
//            print(contentEditingInput?.audiovisualAsset, info)
//            guard let input = contentEditingInput,
//                let asset = input.audiovisualAsset
//                else { return }

        do {
            let location = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("video")
                .appendingPathExtension("mp4")
            
        let asset = AVURLAsset(url: location)
            print(asset)
            let compatiblePresets = AVAssetExportSession.exportPresets(compatibleWith: asset)
            print(compatiblePresets)
            if compatiblePresets.contains(AVAssetExportPresetHighestQuality) {
                //                let output = PHContentEditingOutput(contentEditingInput: input)
                do {
                    let url = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("out.mp4")
                    
                    try? FileManager.default.removeItem(at: url)
                    
                    let composition = AVMutableComposition()
                    guard let videoCompositionTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
                        let audioCompositionTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
                        else { fatalError() }
                    
                    let videoAssetTrack = asset.tracks(withMediaType: .video)[0]
                    let audioAssetTrack = asset.tracks(withMediaType: .audio)[0]
                    
                    let timeRange = CMTimeRange(start: .zero, duration: CMTime(seconds: 30, preferredTimescale: asset.duration.timescale))
                    
                    try videoCompositionTrack.insertTimeRange(timeRange, of: videoAssetTrack, at: .zero)
                    try audioCompositionTrack.insertTimeRange(timeRange, of: audioAssetTrack, at: .zero)
                    
                    videoCompositionTrack.scaleTimeRange(timeRange, toDuration: CMTime(seconds: 60, preferredTimescale: asset.duration.timescale))
                    
                    let transform = videoAssetTrack.preferredTransform
                    let isPortrait = transform.a == 0 && transform.d == 0 && abs(transform.b) == 1 && abs(transform.c) == 1
                    
                    let videoCompositionInstruction = AVMutableVideoCompositionInstruction()
                    videoCompositionInstruction.timeRange = videoCompositionTrack.timeRange
                    
                    let videoLayerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoCompositionTrack)
                    
                    print(videoAssetTrack.preferredTransform)
                    let translate = CGAffineTransform(translationX: -videoAssetTrack.naturalSize.width / 3, y: 0)
                    videoLayerInstruction.setTransform(
                        translate
//                        transform
                        , at: .zero)
                    videoCompositionInstruction.layerInstructions = [videoLayerInstruction]
                    
                    let videoComposition = AVMutableVideoComposition()
                    videoComposition.instructions = [videoCompositionInstruction]
                    
                    let size = videoAssetTrack.naturalSize
                    videoComposition.renderSize =
                        CGSize(width: size.width / 2, height: size.height)
//                        size.applying(scale.inverted())
                    videoComposition.renderScale = 1
                    videoComposition.frameDuration =
                        videoAssetTrack.minFrameDuration
//                        CMTime(seconds: 1, preferredTimescale: 30)
                    
                    let mainQueue = DispatchQueue(label: "main")
                    let videoQueue = DispatchQueue(label: "video")
                    let audioQueue = DispatchQueue(label: "audio")

                    var cancelled = false
                    
                    struct Context {
                        let reader: AVAssetReader
                        let writer: AVAssetWriter
                        
                        let readerVideoOutput: AVAssetReaderOutput
                        let writerVideoInput: AVAssetWriterInput
                    
                        let readerAudioOutput: AVAssetReaderOutput
                        let writerAudioInput: AVAssetWriterInput
                    }
                    
                    func setupAssetReaderAndAssetWriter() throws -> Context {
                        let reader = try AVAssetReader(asset:
                            composition
//                            asset
                        )
                        
                        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)

                        guard let localComposition = reader.asset as? AVComposition else { fatalError() }
                        let readerVideoOutput =
                            AVAssetReaderVideoCompositionOutput(videoTracks: localComposition.tracks(withMediaType: .video), videoSettings: nil)
//                            AVAssetReaderTrackOutput(track: videoAssetTrack, outputSettings: nil)
                        
                        readerVideoOutput.alwaysCopiesSampleData = false
                        
                        readerVideoOutput.videoComposition = videoComposition
//                        if reader.canAdd(readerVideoOutput) {
                            reader.add(readerVideoOutput)
//                        }

                        let writerVideoInput = AVAssetWriterInput(mediaType: .video, outputSettings: nil)
//                        if writer.canAdd(writerVideoInput) {
                            writer.add(writerVideoInput)
//                        }
                        
                        let readerAudioOutput =
                            AVAssetReaderTrackOutput(track:
                                audioCompositionTrack
//                                audioAssetTrack
                                , outputSettings: nil)
                        
                        readerAudioOutput.alwaysCopiesSampleData = false
                        
//                        if reader.canAdd(readerAudioOutput) {
                            reader.add(readerAudioOutput)
//                        }
                        
                        let writerAudioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: nil)
//                        if writer.canAdd(writerAudioInput) {
                            writer.add(writerAudioInput)
//                        }
                        
                        return Context(reader: reader, writer: writer, readerVideoOutput: readerVideoOutput, writerVideoInput: writerVideoInput, readerAudioOutput: readerAudioOutput, writerAudioInput: writerAudioInput)
                    }
                    
                    func readingAndWritingDidFinish(successfully success: Bool, error: Error?, context: Context?) {
                        if !success {
                            context?.reader.cancelReading()
                            context?.writer.cancelWriting()
                            
                            print(error)
                        } else {
                            PHPhotoLibrary.shared().performChanges({
                                let changeRequest = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
                                //                            changeRequest.contentEditingOutput = output
                            }) { (success, error) in
                                print(success, error)

                                DispatchQueue.main.async {
                                    URL(string: "instagram://camera").map { UIApplication.shared.open($0, options: [:], completionHandler: nil)}
                                }
                            }
                        }
                    }
                    
                    func startAssetReaderAndAssetWriter(context: Context) throws {
                        guard context.reader.startReading() else { throw context.reader.error! }

                        guard context.writer.startWriting() else { throw context.writer.error! }
                        
                        let dispatchGroup = DispatchGroup()

                        context.writer.startSession(atSourceTime: .zero)
                        
                        var videoFinished = false
                        var audioFinished = false
                        
                        dispatchGroup.enter()
                        
                        context.writerVideoInput.requestMediaDataWhenReady(on: videoQueue) {
                            if videoFinished {
                                return
                            }
                            var completedOrFailed = false
                            
                            while context.writerVideoInput.isReadyForMoreMediaData && !completedOrFailed {
                                guard let sampleBuffer = context.readerVideoOutput.copyNextSampleBuffer() else {
                                    completedOrFailed = true
                                    continue
                                }
                                completedOrFailed = !context.writerVideoInput.append(sampleBuffer)
                            }
                            
                            if completedOrFailed {
                                let oldFinished = videoFinished
                                videoFinished = true
                                if !oldFinished {
                                    context.writerVideoInput.markAsFinished()
                                }
                                dispatchGroup.leave()
                            }
                        }

                        dispatchGroup.enter()
                        
                        context.writerAudioInput.requestMediaDataWhenReady(on: audioQueue) {
                            if audioFinished {
                                return
                            }
                            var completedOrFailed = false
                            
                            while context.writerAudioInput.isReadyForMoreMediaData && !completedOrFailed {
                                guard let sampleBuffer = context.readerAudioOutput.copyNextSampleBuffer() else {
                                    completedOrFailed = true
                                    continue
                                }
                                completedOrFailed = !context.writerAudioInput.append(sampleBuffer)
                            }

                            if completedOrFailed {
                                let oldFinished = audioFinished
                                audioFinished = true
                                if !oldFinished {
                                    context.writerAudioInput.markAsFinished()
                                }
                                audioFinished = true
                                dispatchGroup.leave()
                            }
                        }
                        
                        dispatchGroup.notify(queue: mainQueue) {
                            if cancelled {
                                context.reader.cancelReading()
                                context.writer.cancelWriting()
                            } else {
                                do {
                                    guard context.reader.status != .failed else { throw context.reader.error! }
                                    context.writer.finishWriting {
                                        let success = context.writer.status != .failed
                                        readingAndWritingDidFinish(successfully: success, error: success ? nil : context.writer.error, context: context)
                                    }
                                }
                                catch {
                                    readingAndWritingDidFinish(successfully: false, error: error, context: context)
                                }
                            }
                        }
                    }
                    
                    composition
//                    asset
                        .loadValuesAsynchronously(forKeys: ["tracks"]) {
                        mainQueue.async {
                            guard !cancelled else { return }
                            
                            do {
                                var localError: NSError?
                                guard asset.statusOfValue(forKey: "tracks", error: &localError) == .loaded else { throw localError! }
                                
                                try? FileManager.default.removeItem(at: url)
                                
                                let context = try setupAssetReaderAndAssetWriter()
                                
                                try startAssetReaderAndAssetWriter(context: context)
                            }
                            catch {
                                readingAndWritingDidFinish(successfully: false, error: error, context: nil)
                            }
                        }
                    }
                    
//                    let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality)
//                    exportSession?.outputURL = url
//                    exportSession?.outputFileType =
//                        //                        .mov
//                        .mp4
//
//                    exportSession?.videoComposition = videoComposition
//
//                    exportSession?.exportAsynchronously {
//                        switch exportSession?.status {
//                        case .failed:
//                            print("failed:", exportSession?.error)
//                        case .cancelled:
//                            print("canceled")
//                        default:
//                            PHPhotoLibrary.shared().performChanges({
//                                let changeRequest = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
//                                //                            changeRequest.contentEditingOutput = output
//                            }) { (success, error) in
//                                print(success, error)
//                            }
////                            DispatchQueue.main.async {
////                                self.present(UIActivityViewController(activityItems: [url], applicationActivities: nil), animated: true, completion: nil)
////                            }
//                        }
//                    }
                }
                catch {
                    print(error)
                }
            }
            }
            catch {
                print(error)
//            }

        }
    }
    
    // MARK: - Navigation

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        switch segue.identifier {
        case "formats":
            let viewController = segue.destination as? FormatTableViewController
            viewController?.formats = info?.formats ?? []
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
                self.navigationItem.prompt = downloading.isEmpty ? "Resumed" : "Paused"
                sender.isEnabled = true
            }
        }
    }
    
    @IBAction func stopDownload(_ sender: UIBarButtonItem) {
        sender.isEnabled = false
        
        Downloader.shared.session.getTasksWithCompletionHandler { (_, _, tasks) in
            for task in tasks {
                task.cancel()
            }
            
            Downloader.shared.transcoder?.isCancelled = true
            
            DispatchQueue.main.async {
                self.navigationItem.prompt = "Cancelled"
                sender.isEnabled = true
            }
        }
    }
    
    @IBAction func transcode(_ sender: UIBarButtonItem) {
        if Downloader.shared.transcoder == nil {
            DispatchQueue.global(qos: .userInitiated).async {
                Downloader.shared.transcode()
            }
        } else {
            Downloader.shared.transcoder?.isCancelled = true
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

extension DownloadViewController {
    func check(info: Info?) {
        guard let formats = info?.formats else {
            return
        }
        
        let _bestAudio = formats.filter { $0.isAudioOnly && $0.ext == "m4a" }.last
        let _bestVideo = formats.filter { $0.isVideoOnly
            && $0.ext ==
//            "webm"
            "mp4"
        }.last
        let _best = formats.filter { !$0.isVideoOnly && !$0.isAudioOnly && $0.ext == "mp4" }.last
        print(_best ?? "no best?", _bestVideo ?? "no bestvideo?", _bestAudio ?? "no bestaudio?")
        guard let best = _best, let bestVideo = _bestVideo, let bestAudio = _bestAudio,
              let bestHeight = best.height, let bestVideoHeight = bestVideo.height
//              , bestVideoHeight > bestHeight
        else
        {
            if let best = _best {
                notify(body: #""\#(info?.title ?? "No title?")" 다운로드 시작"#)
                download(format: best, start: true, faster: false)
            } else if let bestVideo = _bestVideo, let bestAudio = _bestAudio {
                download(format: bestVideo, start: true, faster: true)
                download(format: bestAudio, start: false, faster: true)
            } else {
                DispatchQueue.main.async {
                    self.performSegue(withIdentifier: "formats", sender: nil)
                }
            }
            return
        }
        
        DispatchQueue.main.async {
            let alert = UIAlertController(title: "다운로드 포맷 선택", message: "MP4 이외의 비디오는 다운로드 후 변환이 필요합니다.", preferredStyle: .actionSheet)
            alert.addAction(UIAlertAction(title: "Video+Audio.mp4 (\(bestHeight)p)", style: .default, handler: { _ in
                self.download(format: best, start: true, faster: false)
            }))
            alert.addAction(UIAlertAction(title: "Video.\(bestVideo.ext ?? "?") + Audio.m4a (\(bestVideoHeight)p)", style: .default, handler: { _ in
                self.download(format: bestVideo, start: true, faster: true)
                self.download(format: bestAudio, start: false, faster: true)
            }))
            alert.addAction(UIAlertAction(title: "취소", style: .cancel, handler: nil))
            self.present(alert, animated: true, completion: nil)
        }
    }
    
    func download(format: Format, start: Bool, faster: Bool) {
        let kind: Downloader.Kind = format.isVideoOnly
            ? (format.ext == "mp4" ? .videoOnly : .otherVideo)
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
    fileprivate func extractInfo(_ url: URL) {
        navigationItem.title = url.absoluteString
        
        Downloader.shared.session.getAllTasks {
            for task in $0 {
                task.cancel()
            }
        }
        
        notify(body: "영상 정보 받는중...")
        
        DispatchQueue.global(qos: .userInitiated).async {
            (_, self.info) = YoutubeDL().extractInfo(url: url)
            
            DispatchQueue.main.async {
                self.navigationItem.title = self.info?.title
            }
            
            self.check(info: self.info)
        }
    }
}

extension URL {
    var part: URL {
        appendingPathExtension("part")
    }
}
