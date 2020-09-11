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

enum NotificationRequestIdentifier: String {
    case transcode
}

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
            let error = error as NSError
            if error.domain != NSCocoaErrorDomain || error.code != CocoaError.fileNoSuchFile.rawValue {
                print(#function, error)
            }
        }

        let task = session.downloadTask(with: request)
        task.taskDescription = kind.rawValue
//        print(#function, request, trace)
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
            } else {
                print(#function, session.error ?? "no error?")
                DispatchQueue.main.async {
                    self.topViewController?.navigationItem.title = "Merge failed: \(session.error?.localizedDescription ?? "no error?")"
                }
            }
        }
    }
    
    func transcode() {
        DispatchQueue.main.async {
            guard UIApplication.shared.applicationState == .active else {
                notify(body: "앱을 실행하고 트랜스코딩을 하세요.", identifier: NotificationRequestIdentifier.transcode.rawValue)
                return
            }
            
            let alert = UIAlertController(title: nil, message: "트랜스코딩이 끝날 때까지 다른 앱으로 전환하지 마세요.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "확인", style: .default, handler: nil))
            self.topViewController?.present(alert, animated: true, completion: nil)
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
                    let speed = progress / elapsed
                    let ETA = (1 - progress) / speed
                    
                    guard ETA.isFinite else { return }
                    
                    DispatchQueue.main.async {
                        self.topViewController?.navigationItem.title =
                            "Transcoding \(self.percentFormatter.string(from: NSNumber(value: progress)) ?? "?") ETA \(self.dateComponentsFormatter.string(from: ETA) ?? "?")"
                    }
                }
                
                self.transcoder?.frameBlock = { pixelBuffer in
                    self.transcoder?.frameBlock = nil
                    
                    DispatchQueue.main.async {
                        (self.topViewController as? DownloadViewController)?.pixelBuffer = pixelBuffer
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
        if let error = error {
            print(#function, session, task, error)
        }
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
    
    fileprivate func appendChunk(_ location: URL, to url: URL, offset: UInt64) throws {
        let data = try Data(contentsOf: location, options: .alwaysMapped)

        let file = try FileHandle(forWritingTo: url)
        if #available(iOS 13.0, *) {
            try file.seek(toOffset: offset)
        } else {
            file.seek(toFileOffset: offset)
        }
        file.write(data)
//        if #available(iOS 13.0, *) {
//            try file.close()
//        } else {
//            // Fallback on earlier versions
//        }
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let (_, range, size) = (downloadTask.response as? HTTPURLResponse)?.contentRange
            ?? (nil, -1 ..< -1, -1)
//        print(#function, session, location)
        
        let kind = Kind(rawValue: downloadTask.taskDescription ?? "") ?? .complete

        do {
            if range.isEmpty {
                try FileManager.default.moveItem(at: location, to: kind.url)
            } else {
                let part = kind.url.part
                try appendChunk(location, to: part, offset: UInt64(range.lowerBound))
                
                guard range.upperBound >= size else {
                    session.getTasksWithCompletionHandler { (_, _, tasks) in
                        tasks.first {
                            $0.originalRequest?.url == downloadTask.originalRequest?.url
                                && ($0.originalRequest?.value(forHTTPHeaderField: "Range") ?? "")
                                .hasPrefix("bytes=\(range.upperBound)-") }?
                            .resume()
                    }
                    return
                }
                
                try FileManager.default.moveItem(at: part, to: kind.url)
            }
            
            DispatchQueue.main.async {
                self.topViewController?.navigationItem.prompt = "Download finished"
            }
            
            session.getTasksWithCompletionHandler { (_, _, tasks) in
                print(#function, tasks)
                tasks.first { $0.state == .suspended }?.resume()
            }
            
            switch kind {
            case .complete:
                export(kind.url)
            case .videoOnly, .audioOnly:
                guard transcoder == nil else {
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
        let (_, range, size) = (downloadTask.response as? HTTPURLResponse)?.contentRange ?? (nil, 0..<0, totalBytesExpectedToWrite)
        let count = range.lowerBound + totalBytesWritten
        let bytesPerSec = Double(count) / elapsed
        let remain = Double(size - count) / bytesPerSec
        
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
        let percent = percentFormatter.string(from: NSNumber(value: Double(count) / Double(size)))
        DispatchQueue.main.async {
            self.topViewController?.navigationItem.prompt = "\(percent ?? "?%") of \(ByteCountFormatter.string(fromByteCount: size, countStyle: .file)) at \(ByteCountFormatter.string(fromByteCount: Int64(bytesPerSec), countStyle: .file))/s ETA \(self.dateComponentsFormatter.string(from: remain) ?? "?") \(downloadTask.taskDescription ?? "no description?")"
        }
    }
}

extension HTTPURLResponse {
    var contentRange: (String?, Range<Int64>, Int64)? {
        var contentRange: String?
        if #available(iOS 13.0, *) {
            contentRange = value(forHTTPHeaderField: "Content-Range")
        } else {
            // Fallback on earlier versions
            assertionFailure()
            return nil
        }
        print(#function, contentRange ?? "no Content-Range?")
        
        guard let string = contentRange else { return nil }
        let scanner = Scanner(string: string)
        var prefix: NSString?
        var start: Int64 = -1
        var end: Int64 = -1
        var size: Int64 = -1
        guard scanner.scanUpToCharacters(from: .decimalDigits, into: &prefix),
              scanner.scanInt64(&start),
              scanner.scanString("-", into: nil),
              scanner.scanInt64(&end),
              scanner.scanString("/", into: nil),
              scanner.scanInt64(&size) else { return nil }
        return (prefix as String?, Range(start...end), size)
    }
}

extension URLRequest {
    mutating func setRange(start: Int64, fullSize: Int64) -> Int64 {
        let random = (1..<(chunkSize * 95 / 100)).randomElement().map { start + $0 }
        let end = random ?? (fullSize - 1)
        setValue("bytes=\(start)-\(end)", forHTTPHeaderField: "Range")
        return end
    }
}
