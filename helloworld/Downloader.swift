//
//  Downloader.swift
//  YD
//
//  Created by 안창범 on 2020/09/03.
//  Copyright © 2020 Kewlbear. All rights reserved.
//

import UIKit
import AVFoundation
import Photos

class Downloader: NSObject {

    enum Kind: String {
        case complete, videoOnly, audioOnly, otherVideo
        
        var url: URL {
            do {
                return try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                    .appendingPathComponent("video")
                    .appendingPathExtension(self != .audioOnly
                                                ? (self == .otherVideo ? "webm" : "mp4")
                                                : "m4a")
            }
            catch {
                print(error)
                fatalError()
            }
        }
    }
    
    static let shared = Downloader(backgroundURLSessionIdentifier:
                                    "YD"
//                                    nil
    )
    
    var session: URLSession = URLSession.shared
    
    let decimalFormatter = NumberFormatter()
    
    let percentFormatter = NumberFormatter()
    
    let dateComponentsFormatter = DateComponentsFormatter()
    
    var t = ProcessInfo.processInfo.systemUptime
    
    var t0 = ProcessInfo.processInfo.systemUptime
    
    var topViewController: UIViewController? {
        (UIApplication.shared.keyWindow?.rootViewController as? UINavigationController)?.topViewController
    }
    
    var transcoder: Transcoder?
    
    init(backgroundURLSessionIdentifier: String?) {
        super.init()
        
        decimalFormatter.numberStyle = .decimal

        percentFormatter.numberStyle = .percent
        percentFormatter.minimumFractionDigits = 1
        
        var configuration: URLSessionConfiguration
        if let identifier = backgroundURLSessionIdentifier {
            configuration = URLSessionConfiguration.background(withIdentifier: identifier)
        } else {
            configuration = .default
        }

        configuration.networkServiceType = .responsiveAV
        
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        print(session, "created")
    }
    
    func download(request: URLRequest, kind: Kind) -> URLSessionDownloadTask {
        do {
            try FileManager.default.removeItem(at: kind.url)
            print(#function, "removed", kind.url.lastPathComponent)
        }
        catch {
            print(#function, error)
        }

        let task = session.downloadTask(with: request)
        task.taskDescription = kind.rawValue
        print(#function, request, trace)
        task.priority = URLSessionTask.highPriority
        return task
    }
    
    func tryMerge() {
        let t0 = ProcessInfo.processInfo.systemUptime
        
        let videoAsset = AVAsset(url: Kind.videoOnly.url)
        let audioAsset = AVAsset(url: Kind.audioOnly.url)
        
        guard let videoAssetTrack = videoAsset.tracks(withMediaType: .video).first,
              let audioAssetTrack = audioAsset.tracks(withMediaType: .audio).first else {
            print(#function,
                  videoAsset.tracks(withMediaType: .video),
                  audioAsset.tracks(withMediaType: .audio), trace)
            DispatchQueue.main.async {
                self.topViewController?.navigationItem.title = "Merge failed"
            }
            return
        }
        
        let composition = AVMutableComposition()
        let videoCompositionTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        let audioCompositionTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        
        do {
            try videoCompositionTrack?.insertTimeRange(CMTimeRange(start: .zero, duration: videoAssetTrack.timeRange.duration), of: videoAssetTrack, at: .zero)
            try audioCompositionTrack?.insertTimeRange(CMTimeRange(start: .zero, duration: audioAssetTrack.timeRange.duration), of: audioAssetTrack, at: .zero)
            print(#function, videoAssetTrack.timeRange, audioAssetTrack.timeRange, trace)
        }
        catch {
            print(#function, error, trace)
            DispatchQueue.main.async {
                self.topViewController?.navigationItem.title = error.localizedDescription
            }
            return
        }
        
        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
            print(#function, "unable to init export session", trace)
            return
        }
        let outputURL = Kind.videoOnly.url.deletingLastPathComponent().appendingPathComponent("output.mp4")
        
        try? FileManager.default.removeItem(at: outputURL)
        
        session.outputURL = outputURL
        session.outputFileType = .mp4
        print(#function, "merging...", trace)
        DispatchQueue.main.async {
            self.topViewController?.navigationItem.title = "Merging..."
        }
        session.exportAsynchronously {
            print(#function, "finished merge", session.status.rawValue, trace)
            print(#function, "took", self.dateComponentsFormatter.string(from: ProcessInfo.processInfo.systemUptime - t0) ?? "?")
            if session.status == .completed {
                self.export(outputURL)
            }
        }
    }
    
    func transcode() {
        DispatchQueue.main.async {
            guard UIApplication.shared.applicationState == .active else {
                notify(body: "앱을 실행하고 트랜스코딩을 하세요.")
                return
            }
            
            notify(body: "트랜스코딩이 끝날 때까지 다른 앱으로 전환하지 마세요.")
        }
        
        do {
            try FileManager.default.removeItem(at: Kind.videoOnly.url)
        }
        catch {
            print(#function, error)
        }
        
        DispatchQueue.main.async {
            self.topViewController?.navigationItem.title = "Transcoding..."
        }
        
        let t0 = ProcessInfo.processInfo.systemUptime
        
        transcoder = Transcoder()
        var ret: Int32?

        func requestProgress() {
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
                self.transcoder?.progressBlock = { progress in
                    self.transcoder?.progressBlock = nil
                    
                    let elapsed = ProcessInfo.processInfo.systemUptime - t0
                    let remain = (1 - progress) * elapsed
                    
                    DispatchQueue.main.async {
                        self.topViewController?.navigationItem.title =
                            "Transcoding \(self.percentFormatter.string(from: NSNumber(value: progress)) ?? "?") ETA \(self.dateComponentsFormatter.string(from: remain) ?? "?")"
                    }
                }
                
                if ret == nil {
                    requestProgress()
                }
            }
        }
        
        requestProgress()
        
        ret = transcoder?.transcode(from: Kind.otherVideo.url, to: Kind.videoOnly.url)
        
        transcoder = nil
        
        print(#function, ret ?? "nil?", "took", dateComponentsFormatter.string(from: ProcessInfo.processInfo.systemUptime - t0) ?? "?")
        
        notify(body: "트랜스코딩 완료")
        
        tryMerge()
    }
}

extension Downloader: URLSessionDelegate {
    func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {
        print(#function, session, error ?? "no error")
    }
    
    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        print(#function, session)
    }
}

extension Downloader: URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        print(#function, session, task, error ?? "no error")
    }
}

extension Downloader: URLSessionDownloadDelegate {
    
    fileprivate func export(_ url: URL) {
        DispatchQueue.main.async {
            self.topViewController?.navigationItem.title = "Exporting..."
        }
        
        PHPhotoLibrary.shared().performChanges({
            let changeRequest = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            //                            changeRequest.contentEditingOutput = output
        }) { (success, error) in
            print(#function, success, error ?? "", trace)
            
            notify(body: "Download complete!")
            DispatchQueue.main.async {
                self.topViewController?.navigationItem.title = "Finished"
            }
        }
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        print(#function, session, downloadTask, location)
        
        DispatchQueue.main.async {
            self.topViewController?.navigationItem.prompt = "Download finished"
        }
        
        session.getTasksWithCompletionHandler { (_, _, tasks) in
            print(#function, tasks)
            tasks.first { $0.state == .suspended }?.resume()
        }
        
        do {
            let kind = Kind(rawValue: downloadTask.taskDescription ?? "") ?? .complete
            
            try FileManager.default.moveItem(at: location, to: kind.url)
            
            switch kind {
            case .complete:
                export(kind.url)
            case .videoOnly, .audioOnly:
                guard transcoder != nil else {
                    break
                }
                tryMerge()
            case .otherVideo:
                DispatchQueue.global(qos: .userInitiated).async {
                    self.transcode()
                }
            }
        }
        catch {
            print(error)
        }
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let t = ProcessInfo.processInfo.systemUptime
        guard t - self.t > 0.9 else {
            return
        }
        self.t = t
        
        let elapsed = t - t0
        let bytesPerSec = Double(totalBytesWritten) / elapsed
        let remain = Double(totalBytesExpectedToWrite - totalBytesWritten) / bytesPerSec
        
//        print(
////            #function,
////              session,
//              downloadTask.taskIdentifier,
//            ByteCountFormatter.string(fromByteCount: bytesWritten, countStyle: .file),
//            ByteCountFormatter.string(fromByteCount: totalBytesWritten, countStyle: .file),
//            ByteCountFormatter.string(fromByteCount: totalBytesExpectedToWrite, countStyle: .file),
//            ByteCountFormatter.string(fromByteCount: Int64(bytesPerSec), countStyle: .file), "/s",
//            dateComponentsFormatter.string(from: elapsed) ?? "?", "elapsed",
//            dateComponentsFormatter.string(from: remain) ?? "?", "remain"
//            )
        DispatchQueue.main.async {
            self.topViewController?.navigationItem.prompt = "\(self.percentFormatter.string(from: NSNumber(value: Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))) ?? "?%") of \(ByteCountFormatter.string(fromByteCount: totalBytesExpectedToWrite, countStyle: .file)) at \(ByteCountFormatter.string(fromByteCount: Int64(bytesPerSec), countStyle: .file))/s ETA \(self.dateComponentsFormatter.string(from: remain) ?? "?") \(downloadTask.taskDescription ?? "no description?")"
        }
    }
}
