//
//  AppModel.swift
//  YoutubeDL
//
//  Copyright (c) 2021 Changbeom Ahn
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

import Foundation
import PythonSupport
import YoutubeDL
import Combine
import UIKit
import AVFoundation
import Photos
import PythonKit

@MainActor
class AppModel: ObservableObject {
    @Published var url: URL?
    
    @Published var youtubeDL = YoutubeDL()
    
    @Published var enableChunkedDownload = true
    
    @Published var enableTranscoding = true
    
    @Published var supportedFormatsOnly = true
    
    @Published var exportToPhotos = true
    
    @Published var fileURL: URL?
    
    @Published var downloads: [URL] = []
    
    @Published var showProgress = false
    
    var progress = Progress()
    
    @Published var error: Error?
    
    @Published var exception: PythonObject?
    
    @Published var info: Info?
    
    @Published var webViewURL: URL?
    
    var formatSelector: YoutubeDL.FormatSelector?
    
    lazy var subscriptions = Set<AnyCancellable>()
    
    init() {
        youtubeDL.downloadsDirectory = try! documentsDirectory()
        
        $url
            .compactMap { $0 }
            .sink { url in
                Task {
                    await self.startDownload(url: url)
                }
            }
            .store(in: &subscriptions)
        
        do {
            downloads = try loadDownloads()
        } catch {
            // FIXME: ...
            print(#function, error)
        }
    }
    
    func startDownload(url: URL) async {
        print(#function, url)
        
        do {
            let (info, files, infos) = try await download(url: url)
            
            let outputURL: URL
            
            guard let path = info.flatMap({ String($0["_filename"]) }) else {
                print(#function, "no '_filename'?", info ?? "nil")
                return
            }
            if #available(iOS 16.0, *) {
                outputURL = URL(filePath: path)
            } else {
                outputURL = URL(fileURLWithPath: path)
            }
            
            export(url: outputURL)
            showProgress = false
            notify(body: "Finished")
        } catch YoutubeDLError.canceled {
            print(#function, "canceled")
        } catch PythonError.exception(let exception, traceback: _) {
            print(#function, exception)
            await MainActor.run {
                self.exception = exception
            }
        } catch {
            print(#function, error)
            if (url.host ?? "").hasSuffix("instagram.com") {
                await MainActor.run {
                    webViewURL = url
                }
                return
            }
            
            await MainActor.run {
                self.error = error
            }
        }
    }
    
    func save(info: Info) throws -> URL {
        let title = info.safeTitle
        let fileManager = FileManager.default
        var url = URL(fileURLWithPath: title, relativeTo: try documentsDirectory())
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        
        // exclude from iCloud backup
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
        
        let data = try JSONEncoder().encode(info)
        try data.write(to: url.appendingPathComponent("Info.json"))
        
        return url
    }
    
    func loadDownloads() throws -> [URL] {
        let keys: Set<URLResourceKey> = [.nameKey, .isDirectoryKey]
        let documents = try documentsDirectory()
        guard let enumerator = FileManager.default.enumerator(at: documents, includingPropertiesForKeys: Array(keys), options: .skipsHiddenFiles) else { fatalError() }
        var urls = [URL]()
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: keys)
            guard enumerator.level == 2, url.lastPathComponent == "Info.json" else { continue }
            print(enumerator.level, url.path.replacingOccurrences(of: documents.path, with: ""), values.isDirectory ?? false ? "dir" : "file")
            urls.append(url.deletingLastPathComponent())
        }
        return urls
    }
    
    func documentsDirectory() throws -> URL {
        try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
    }
    
    func pauseDownload() {
        
    }
    
    func resumeDownload() {
        
    }
    
    func cancelDownload() {
        
    }
    
    func download(url: URL) async throws -> (PythonObject?, [String], [PythonObject]) {
        progress.localizedDescription = NSLocalizedString("Extracting info", comment: "progress description")

        showProgress = true

        var info: PythonObject?
        var files = [String]()
        var formats = [PythonObject]()
        var error: String?
        
        let argv: [String] = (
            url.pathExtension == "mp4"
            ? ["-o", url.lastPathComponent,]
            : [
                "-f", "bestvideo+bestaudio[ext=m4a]/best",
                "--merge-output-format", "mp4",
                "--postprocessor-args", "Merger+ffmpeg:-c:v h264",
            ]
        )
        + [
            "--no-check-certificates",
            url.absoluteString,
        ]
        print(#function, argv)
        try await yt_dlp(argv: argv) { dict in
            info = dict["info_dict"]
//            if self.info == nil {
//                DispatchQueue.main.async {
//                    self.info = try? PythonDecoder().decode(Info.self, from: info!)
//                }
//            }
            
            let status = String(dict["status"]!)
            
            self.progress.localizedDescription = nil
            
            switch status {
            case "downloading":
                self.progress.kind = .file
                self.progress.fileOperationKind = .downloading
                if #available(iOS 16.0, *) {
                    self.progress.fileURL = URL(filePath: String(dict["tmpfilename"]!)!)
                } else {
                    // Fallback on earlier versions
                }
                self.progress.completedUnitCount = Int64(dict["downloaded_bytes"]!) ?? -1
                self.progress.totalUnitCount = Int64(Double(dict["total_bytes"] ?? dict["total_bytes_estimate"] ?? Python.None) ?? -1)
                self.progress.throughput = Int(dict["speed"]!)
                self.progress.estimatedTimeRemaining = TimeInterval(dict["eta"]!)
            case "finished":
                print(#function, dict["filename"] ?? "no filename")
                files.append(String(dict["filename"]!)!)
                formats.append(info!)
            default:
                print(#function, dict)
            }
        } log: { level, message in
            print(#function, level, message)
            
            if level == "error" || message.hasSuffix("has already been downloaded") {
                error = message
            }
        } makeTranscodeProgressBlock: {
            self.progress.kind = nil
            self.progress.localizedDescription = NSLocalizedString("Transcoding...", comment: "Progress description")
            self.progress.completedUnitCount = 0
            self.progress.totalUnitCount = 100
            
            let t0 = ProcessInfo.processInfo.systemUptime
            
            return { (progress: Double) in
                print(#function, "transcode:", progress)
                let elapsed = ProcessInfo.processInfo.systemUptime - t0
                let speed = progress / elapsed
                let ETA = (1 - progress) / speed
                
                guard ETA.isFinite else { return }
                
                self.progress.completedUnitCount = Int64(progress * 100)
                self.progress.estimatedTimeRemaining = ETA
            }
        }
        
        if let error {
            throw NSError(domain: "App", code: 1, userInfo: [NSLocalizedDescriptionKey: error])
        }
        
        return (info, files, formats)
    }
    
    func transcode(videoURL: URL, transcodedURL: URL, timeRange: TimeRange?, bitRate: Double?) async throws {
        progress.kind = nil
        progress.localizedDescription = NSLocalizedString("Transcoding...", comment: "Progress description")
        progress.totalUnitCount = 100
        
        let t0 = ProcessInfo.processInfo.systemUptime
        
        let transcoder = Transcoder { progress in
            print(#function, "transcode:", progress)
            let elapsed = ProcessInfo.processInfo.systemUptime - t0
            let speed = progress / elapsed
            let ETA = (1 - progress) / speed
            
            guard ETA.isFinite else { return }
            
            self.progress.completedUnitCount = Int64(progress * 100)
            self.progress.estimatedTimeRemaining = ETA
        }
       
        let _: Int = try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async {
                do {
                    try transcoder.transcode(from: videoURL, to: transcodedURL, timeRange: timeRange, bitRate: bitRate)
                    continuation.resume(returning: 0)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    func mux(video videoURL: URL, audio audioURL: URL, out outputURL: URL, timeRange: TimeRange?) async throws -> Bool {
        let t0 = ProcessInfo.processInfo.systemUptime
       
        let videoAsset = AVAsset(url: videoURL)
        let audioAsset = AVAsset(url: audioURL)
        
        guard let videoAssetTrack = videoAsset.tracks(withMediaType: .video).first,
              let audioAssetTrack = audioAsset.tracks(withMediaType: .audio).first else {
            print(#function,
                  videoAsset.tracks(withMediaType: .video),
                  audioAsset.tracks(withMediaType: .audio))
            return false
        }
        
        let composition = AVMutableComposition()
        let videoCompositionTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        let audioCompositionTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        
        do {
            try videoCompositionTrack?.insertTimeRange(CMTimeRange(start: .zero, duration: videoAssetTrack.timeRange.duration), of: videoAssetTrack, at: .zero)
            let range: CMTimeRange
            if let timeRange = timeRange {
                range = CMTimeRange(start: CMTime(seconds: timeRange.lowerBound, preferredTimescale: 1),
                                    end: CMTime(seconds: timeRange.upperBound, preferredTimescale: 1))
            } else {
                range = CMTimeRange(start: .zero, duration: audioAssetTrack.timeRange.duration)
            }
            try audioCompositionTrack?.insertTimeRange(range, of: audioAssetTrack, at: .zero)
            print(#function, videoAssetTrack.timeRange, range)
        }
        catch {
            print(#function, error)
            return false
        }
        
        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
            print(#function, "unable to init export session")
            return false
        }
        
        removeItem(at: outputURL)
        
        session.outputURL = outputURL
        session.outputFileType = .mp4
        print(#function, "merging...")
        
        DispatchQueue.main.async {
            let progress = self.progress
            progress.kind = nil
            progress.localizedDescription = NSLocalizedString("Merging...", comment: "Progress description")
            progress.localizedAdditionalDescription = nil
            progress.totalUnitCount = 0
            progress.completedUnitCount = 0
            progress.estimatedTimeRemaining = nil
        }
        
        Task {
            while session.status != .completed {
                print(#function, session.progress)
                progress.localizedDescription = "\(Int(session.progress * 100))%"
                try await Task.sleep(nanoseconds: 100_000_000)
            }
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            session.exportAsynchronously {
                print(#function, "finished merge", session.status.rawValue)
                print(#function, "took", self.youtubeDL.downloader.dateComponentsFormatter.string(from: ProcessInfo.processInfo.systemUptime - t0) ?? "?")
                if session.status == .completed {
                    if !self.youtubeDL.keepIntermediates {
                        removeItem(at: videoURL)
                        removeItem(at: audioURL)
                    }
                } else {
                    print(#function, session.error ?? "no error?")
                }
                
                continuation.resume(with: Result {
                    if let error = session.error { throw error }
                    return true
                })
            }
        }
    }
  
    func export(url: URL) {
        PHPhotoLibrary.shared().performChanges({
            _ = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
        }) { success, error in
            print(#function, success, error ?? "")
            DispatchQueue.main.async {
                self.error = error
            }
        }
    }
    
    func share() {
        
    }
}
