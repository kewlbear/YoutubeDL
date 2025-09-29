//
//  AppModel.swift
//  YoutubeDL
//
//  Full AppModel for YoutubeDL app
//  - download options
//  - yt-dlp invocation and progress handling
//  - postprocessing (ffmpeg args via yt-dlp postprocessor)
//

import Foundation
import Combine
import SwiftUI
import AVFoundation
import Photos
import YoutubeDL
import PythonKit

// --------------------------------------------------
// MARK: - Options / Enums
// --------------------------------------------------

public enum DownloadKind: String, CaseIterable, Identifiable {
    case video = "Video"
    case audio = "Audio"
    case best  = "Best"
    public var id: String { rawValue }
}

public enum VideoQuality: String, CaseIterable, Identifiable {
    case p2160 = "2160p (4K)"
    case p1440 = "1440p"
    case p1080 = "1080p"
    case p720  = "720p"
    case p480  = "480p"
    case p360  = "360p"
    case best  = "Best"
    public var id: String { rawValue }
}

public enum ContainerFormat: String, CaseIterable, Identifiable {
    case mp4 = "mp4"
    case mkv = "mkv"
    case webm = "webm"
    public var id: String { rawValue }
}

public enum AudioFormat: String, CaseIterable, Identifiable {
    case m4a = "m4a"
    case mp3 = "mp3"
    case opus = "opus"
    case flac = "flac"
    case wav = "wav"
    case best = "best"
    public var id: String { rawValue }
}

public enum TranscodePreset: String, CaseIterable, Identifiable {
    case copy = "Copy (no re-encode)"
    case h264_fast = "H.264 - Fast"
    case h264_quality = "H.264 - Quality"
    case hevc_fast = "HEVC - Fast"
    case hevc_quality = "HEVC - Quality"
    case vp9_fast = "VP9 - Fast"
    case vp9_quality = "VP9 - Quality"

    public var id: String { rawValue }
}

// --------------------------------------------------
// MARK: - AppModel Class
// --------------------------------------------------

@MainActor
public final class AppModel: ObservableObject {

    // MARK: Published state used by UI

    @Published public var url: URL? = nil
    @Published public var youtubeDL: YoutubeDL = YoutubeDL()

    @Published public var enableChunkedDownload: Bool = true
    @Published public var enableTranscoding: Bool = true
    @Published public var supportedFormatsOnly: Bool = true
    @Published public var exportToPhotos: Bool = true

    @Published public var fileURL: URL? = nil
    @Published public var downloads: [URL] = []
    @Published public var showProgress: Bool = false
    @Published public var progress: Progress = Progress()
    @Published public var error: Error? = nil
    @Published public var exception: PythonObject? = nil
    @Published public var info: Info? = nil
    @Published public var webViewURL: URL? = nil
    @Published public var outputFileURL: URL? = nil

    // UI-configurable model fields (bound to MainView)
    @Published public var kind: DownloadKind = .best
    @Published public var videoQuality: VideoQuality = .best
    @Published public var container: ContainerFormat = .mp4
    @Published public var audioFormat: AudioFormat = .m4a
    @Published public var transcode: TranscodePreset = .copy

    @Published public var videoCRF: Int? = nil
    @Published public var videoBitrateKbps: Int? = nil
    @Published public var audioBitrateKbps: Int? = nil

    // Save folders
    @Published public var defaultSaveFolder: URL? = nil
    @Published public var perDownloadFolder: URL? = nil

    // Internals
    lazy var subscriptions = Set<AnyCancellable>()

    // MARK: - Init

    public init() {
        // default downloads directory to app documents
        if let docs = try? documentsDirectory() {
            youtubeDL.downloadsDirectory = docs
        }

        // react to url set by UI
        $url
            .compactMap { $0 }
            .sink { [weak self] url in
                Task {
                    await self?.startDownload(url: url)
                }
            }
            .store(in: &subscriptions)

        // load existing downloads (if any)
        do {
            downloads = try loadDownloads()
        } catch {
            print("AppModel.init loadDownloads()", error)
        }
    }

    // MARK: - Start download flow

    public func startDownload(url: URL) async {
        print("AppModel.startDownload:", url)

        // reset transient state
        await MainActor.run {
            self.error = nil
            self.exception = nil
            self.outputFileURL = nil
            self.showProgress = true
            self.progress = Progress()
            self.progress.localizedDescription = NSLocalizedString("Extracting info", comment: "progress description")
        }

        // configure downloads dir (per-download override or default)
        if let per = perDownloadFolder ?? defaultSaveFolder {
            youtubeDL.downloadsDirectory = per
        } else if let docs = try? documentsDirectory() {
            youtubeDL.downloadsDirectory = docs
        }

        do {
            let (infoObj, files, infos) = try await download(url: url)

            // decode Info if available (safe)
            if let infoObj {
                if let decoded = try? PythonDecoder().decode(Info.self, from: infoObj) {
                    await MainActor.run { self.info = decoded }
                } else {
                    print("startDownload: failed to decode Info from infoObj")
                }
            }

            guard let filename = infoObj.flatMap({ String($0["_filename"]) }) else {
                print("startDownload: no filename in infoObj")
                await MainActor.run {
                    self.showProgress = false
                }
                return
            }

            // convert to URL
            let outputURL: URL
            if #available(iOS 16.0, *) {
                outputURL = URL(filePath: filename)
            } else {
                outputURL = URL(fileURLWithPath: filename)
            }

            await MainActor.run {
                self.outputFileURL = outputURL
                self.showProgress = false
            }

            if exportToPhotos && isVideoFile(outputURL) {
                exportToPhotosLibrary(outputURL)
            }

            // clear per-download folder after a successful run
            perDownloadFolder = nil

            notify(body: "Finished")
        } catch PythonError.exception(let ex, _) {
            print("AppModel.startDownload python exception:", ex)
            await MainActor.run { self.exception = ex; self.showProgress = false }
        } catch {
            print("AppModel.startDownload error:", error)
            // fallback for instagram - let UI open a webview
            if (url.host ?? "").hasSuffix("instagram.com") {
                await MainActor.run { self.webViewURL = url }
            } else {
                await MainActor.run { self.error = error }
            }
            await MainActor.run { self.showProgress = false }
        }
    }

    // MARK: - Build yt-dlp args

    // returns the argument list for yt_dlp
    func buildArguments(for url: URL) -> [String] {
        var argv: [String] = []

        // Format selection
        switch kind {
        case .audio:
            argv += ["-f", "bestaudio/best"]
            argv += ["--extract-audio"]
            if audioFormat != .best {
                argv += ["--audio-format", audioFormat.rawValue.lowercased()]
            }
            if let a = audioBitrateKbps {
                argv += ["--audio-quality", "\(a)k"]
            }
        case .video:
            argv += ["-f", videoFormatSelectorString()]
        case .best:
            argv += ["-f", "bestvideo+bestaudio/best"]
        }

        // merge/output container
        argv += ["--merge-output-format", container.rawValue.lowercased()]

        // postprocessor args (ffmpeg)
        if kind != .audio {
            let ffmpegArgs = ffmpegPostprocessorArgs()
            if !ffmpegArgs.isEmpty {
                argv += ["--postprocessor-args", "Merger+ffmpeg:\(ffmpegArgs)"]
            } else {
                argv += ["--postprocessor-args", "Merger+ffmpeg:-movflags +faststart"]
            }
        }

        // output template
        argv += ["-o", "%(title).200B.%(ext)s"]

        // other safe flags
        argv += ["--no-check-certificates"]

        // finally URL
        argv += [url.absoluteString]

        return argv
    }

    // helper to pick video format expression for yt-dlp
    private func videoFormatSelectorString() -> String {
        func heightLimit(_ h: Int?) -> String {
            guard let h else { return "" }
            return "[height<=\(h)]"
        }

        let h: Int?
        switch videoQuality {
        case .p2160: h = 2160
        case .p1440: h = 1440
        case .p1080: h = 1080
        case .p720:  h = 720
        case .p480:  h = 480
        case .p360:  h = 360
        case .best:  h = nil
        }

        let limit = heightLimit(h)

        if supportedFormatsOnly {
            return "bestvideo[vcodec~='(avc1|h264)']\(limit)+bestaudio[acodec~='(aac|mp4a)']/best\(limit)"
        } else {
            return "bestvideo\(limit)+bestaudio/best\(limit)"
        }
    }

    // Build ffmpeg postprocessor args string
    private func ffmpegPostprocessorArgs() -> String {
        let mov = "-movflags +faststart"

        switch transcode {
        case .copy:
            return "\(mov) -c:v copy -c:a copy"
        case .h264_fast, .h264_quality:
            var args = "\(mov) -c:v libx264 -preset " + (transcode == .h264_fast ? "veryfast" : "slow")
            if let br = videoBitrateKbps {
                args += " -b:v \(br)k"
            } else if let crf = videoCRF {
                args += " -crf \(crf)"
            } else {
                args += (transcode == .h264_fast ? " -crf 23" : " -crf 20")
            }
            args += " -c:a aac -b:a \((audioBitrateKbps ?? 192))k"
            return args
        case .hevc_fast, .hevc_quality:
            var args = "\(mov) -c:v libx265 -preset " + (transcode == .hevc_fast ? "fast" : "slow")
            if let br = videoBitrateKbps {
                args += " -b:v \(br)k"
            } else if let crf = videoCRF {
                args += " -crf \(crf)"
            } else {
                args += (transcode == .hevc_fast ? " -crf 28" : " -crf 24")
            }
            args += " -tag:v hvc1 -c:a aac -b:a \((audioBitrateKbps ?? 192))k"
            return args
        case .vp9_fast, .vp9_quality:
            var args = "\(mov) -c:v libvpx-vp9 -deadline " + (transcode == .vp9_fast ? "realtime" : "good")
            if let br = videoBitrateKbps {
                args += " -b:v \(br)k"
            } else if let crf = videoCRF {
                args += " -crf \(crf)"
            } else {
                args += (transcode == .vp9_fast ? " -crf 33" : " -crf 28")
            }
            args += " -c:a copy"
            return args
        }
    }

    // MARK: - Perform download with yt-dlp helper wrapper

    func download(url: URL) async throws -> (PythonObject?, [String], [PythonObject]) {
        var infoObj: PythonObject? = nil
        var files: [String] = []
        var infos: [PythonObject] = []
        var errorMessage: String?

        await MainActor.run {
            self.showProgress = true
            self.progress = Progress(totalUnitCount: 0)
            self.progress.localizedDescription = NSLocalizedString("Extracting info", comment: "progress description")
        }

        let argv = buildArguments(for: url)
        print("Running yt-dlp with argv:", argv)

        try await yt_dlp(argv: argv) { dict in
            infoObj = dict["info_dict"]
            let status = String(dict["status"] ?? "unknown")

            switch status {
            case "downloading":
                Task { @MainActor in
                    self.progress.kind = .file
                    self.progress.fileOperationKind = .downloading
                    self.progress.completedUnitCount = Int64(dict["downloaded_bytes"]!) ?? -1
                    self.progress.totalUnitCount = Int64(Double(dict["total_bytes"] ?? dict["total_bytes_estimate"] ?? Python.None) ?? -1)
                    if let speed = Int(dict["speed"] ?? Python.None) { self.progress.throughput = speed }
                    self.progress.estimatedTimeRemaining = TimeInterval(dict["eta"] ?? Python.None) ?? nil
                }
            case "finished":
                if let fname = String(dict["filename"] ?? Python.None) {
                    files.append(fname)
                }
                if let infoObj { infos.append(infoObj) }
            default:
                break
            }
        } log: { level, message in
            print("[yt-dlp]", level, message)
            if level == "error" {
                errorMessage = message
            }
        } makeTranscodeProgressBlock: { [weak self] in
            guard let self = self else { return { _ in } }
            Task { @MainActor in
                self.progress.kind = nil
                self.progress.localizedDescription = NSLocalizedString("Transcoding...", comment: "")
                self.progress.completedUnitCount = 0
                self.progress.totalUnitCount = 100
            }
            let start = ProcessInfo.processInfo.systemUptime
            return { (p: Double) in
                Task { @MainActor in
                    let elapsed = ProcessInfo.processInfo.systemUptime - start
                    let speed = p / max(elapsed, 0.000001)
                    let ETA = (1 - p) / max(speed, 0.000001)
                    self.progress.completedUnitCount = Int64(p * 100)
                    self.progress.estimatedTimeRemaining = ETA.isFinite ? ETA : nil
                }
            }
        }

        if let err = errorMessage {
            throw NSError(domain: "AppModel", code: 1, userInfo: [NSLocalizedDescriptionKey: err])
        }

        return (infoObj, files, infos)
    }

    // MARK: - Helpers: export, IO, etc.

    private func exportToPhotosLibrary(_ url: URL) {
        PHPhotoLibrary.shared().performChanges({
            _ = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
        }) { success, err in
            if let err { print("exportToPhotos error:", err) }
        }
    }

    private func isVideoFile(_ url: URL) -> Bool {
        let exts = ["mp4", "mov", "m4v", "mkv", "webm"]
        return exts.contains(url.pathExtension.lowercased())
    }

    func save(info: Info) throws -> URL {
        let title = info.safeTitle
        let fm = FileManager.default
        let base = try documentsDirectory()
        var dir = URL(fileURLWithPath: title, relativeTo: base) // ✅ must be var
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try dir.setResourceValues(values)
        let data = try JSONEncoder().encode(info)
        try data.write(to: dir.appendingPathComponent("Info.json"))
        return dir
    }

    func loadDownloads() throws -> [URL] {
        let keys: Set<URLResourceKey> = [.nameKey, .isDirectoryKey]
        let documents = try documentsDirectory()
        guard let enumerator = FileManager.default.enumerator(at: documents, includingPropertiesForKeys: Array(keys), options: .skipsHiddenFiles) else { return [] }
        var urls: [URL] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: keys)
            guard enumerator.level == 2, url.lastPathComponent == "Info.json" else { continue }
            urls.append(url.deletingLastPathComponent())
        }
        return urls
    }

    func documentsDirectory() throws -> URL {
        try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
    }

    func setGlobalSaveFolder(url: URL?) {
        defaultSaveFolder = url
    }

    func setPerDownloadFolder(url: URL?) {
        perDownloadFolder = url
    }

    func notify(body: String) {
        print("[AppModel.notify]", body)
    }
}
