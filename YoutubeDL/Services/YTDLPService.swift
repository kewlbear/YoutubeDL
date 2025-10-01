import Foundation
import PythonKit

struct YTDLPConfiguration {
    var kind: DownloadKind
    var videoQuality: VideoQuality
    var container: ContainerFormat
    var audioFormat: AudioFormat
    var transcode: TranscodePreset
    var videoCRF: Int?
    var videoBitrateKbps: Int?
    var audioBitrateKbps: Int?
    var enableTranscoding: Bool
    var enableChunkedDownload: Bool
    var supportedFormatsOnly: Bool
}

struct YTDLPResult {
    var infoObject: PythonObject?
    var files: [String]
    var infoSnapshots: [PythonObject]
}

final class YTDLPService {
    struct ProgressUpdate: Equatable {
        enum Stage: Equatable {
            case extracting
            case downloading(downloaded: Int64?, total: Int64?, speed: Int?, eta: TimeInterval?)
            case transcoding(Double)
        }

        var stage: Stage
        var title: String?
    }

    func run(
        url: URL,
        configuration: YTDLPConfiguration,
        outputDirectory: URL? = nil,
        progress: @escaping (ProgressUpdate) -> Void,
        logHandler: ((String, String) -> Void)? = nil
    ) async throws -> YTDLPResult {
        progress(.init(stage: .extracting, title: nil))

        var infoObj: PythonObject? = nil
        var files: [String] = []
        var infos: [PythonObject] = []
        var errorMessage: String?
        var seenInfoIdentifiers: Set<String> = []

        let extractedInfo = try await yt_dlp(
            url: url,
            configuration: configuration,
            outputDirectory: outputDirectory,
            progress: { dict in
                if let latestInfo = Self.dictionaryValue(dict, key: "info_dict") {
                    infoObj = latestInfo
                    if let identifier = Self.stringValue(latestInfo, key: "id") {
                        if !seenInfoIdentifiers.contains(identifier) {
                            seenInfoIdentifiers.insert(identifier)
                            infos.append(latestInfo)
                        }
                    } else {
                        infos.append(latestInfo)
                    }
                }

                let status = Self.stringValue(dict, key: "status") ?? "unknown"
                let isPostprocessor = Self.dictionaryValue(dict, key: "postprocessor") != nil

                switch status {
                case "downloading":
                    let downloaded = Self.int64(from: dict["downloaded_bytes"])
                    let total = Self.int64(from: dict["total_bytes"]) ?? Self.int64(from: dict["total_bytes_estimate"])
                    let speed = Self.int(from: dict["speed"])
                    let eta = Self.timeInterval(from: dict["eta"])
                    progress(.init(stage: .downloading(downloaded: downloaded, total: total, speed: speed, eta: eta), title: nil))
                case "finished":
                    if isPostprocessor {
                        progress(.init(stage: .transcoding(1), title: nil))
                    } else {
                        let filenameObject = dict["filename"]
                        if filenameObject != Python.None, let fname = String(filenameObject) {
                            files.append(fname)
                        }
                        if let infoObj { infos.append(infoObj) }
                    }
                case "postprocessing", "processing":
                    if let percent = Self.percent(from: dict) {
                        progress(.init(stage: .transcoding(percent), title: nil))
                    } else {
                        progress(.init(stage: .transcoding(0), title: nil))
                    }
                case "started":
                    if isPostprocessor {
                        progress(.init(stage: .transcoding(0), title: nil))
                    }
                default:
                    if isPostprocessor, let percent = Self.percent(from: dict) {
                        progress(.init(stage: .transcoding(percent), title: nil))
                    }
                }
            },
            log: { level, message in
                logHandler?(level, message)
                if level == "error" { errorMessage = message }
            }
        )

        if let extractedInfo {
            if infoObj == nil { infoObj = extractedInfo }
            if let identifier = Self.stringValue(extractedInfo, key: "id") {
                if !seenInfoIdentifiers.contains(identifier) {
                    seenInfoIdentifiers.insert(identifier)
                    infos.append(extractedInfo)
                }
            } else {
                infos.append(extractedInfo)
            }
        }

        if let err = errorMessage {
            throw NSError(domain: "YTDLPService", code: 1, userInfo: [NSLocalizedDescriptionKey: err])
        }

        return YTDLPResult(infoObject: infoObj, files: files, infoSnapshots: infos)
    }

    func buildArguments(for url: URL, configuration: YTDLPConfiguration) -> [String] {
        var argv: [String] = []

        switch configuration.kind {
        case .audio:
            argv += ["-f", "bestaudio/best", "--extract-audio"]
            if configuration.audioFormat != .best {
                argv += ["--audio-format", configuration.audioFormat.rawValue.lowercased()]
            }
            if let bitrate = configuration.audioBitrateKbps {
                argv += ["--audio-quality", "\(bitrate)k"]
            }
        case .video:
            argv += ["-f", videoFormatSelector(configuration: configuration)]
        case .best:
            argv += ["-f", "bestvideo+bestaudio/best"]
        }

        argv += ["--merge-output-format", configuration.container.rawValue.lowercased()]

        if configuration.kind != .audio, configuration.enableTranscoding,
           let ffmpegArgs = ffmpegPostprocessorArgs(configuration: configuration) {
            argv += ["--postprocessor-args", "Merger+ffmpeg:\(ffmpegArgs)"]
        }

        if configuration.enableChunkedDownload {
            argv += ["--concurrent-fragments", "5"]
        } else {
            argv += ["--concurrent-fragments", "1"]
        }

        argv += ["-o", "%(title).200B.%(ext)s"]
        argv += ["--no-check-certificates"]
        argv += [url.absoluteString]

        return argv
    }

    private func videoFormatSelector(configuration: YTDLPConfiguration) -> String {
        let height: Int?
        switch configuration.videoQuality {
        case .p2160: height = 2160
        case .p1440: height = 1440
        case .p1080: height = 1080
        case .p720:  height = 720
        case .p480:  height = 480
        case .p360:  height = 360
        case .best:  height = nil
        }

        let limit = height.map { "[height<=\($0)]" } ?? ""

        if configuration.supportedFormatsOnly {
            return "bestvideo[vcodec~='(avc1|h264)']\(limit)+bestaudio[acodec~='(aac|mp4a)']/best\(limit)"
        } else {
            return "bestvideo\(limit)+bestaudio/best\(limit)"
        }
    }

    private func ffmpegPostprocessorArgs(configuration: YTDLPConfiguration) -> String? {
        let mov = "-movflags +faststart"

        switch configuration.transcode {
        case .copy:
            if configuration.videoBitrateKbps == nil && configuration.videoCRF == nil && configuration.audioBitrateKbps == nil {
                return "\(mov) -c:v copy -c:a copy"
            } else {
                return "\(mov)"
            }
        case .h264_fast, .h264_quality:
            var args = "\(mov) -c:v libx264 -preset "
            args += (configuration.transcode == .h264_fast ? "veryfast" : "slow")
            if let bitrate = configuration.videoBitrateKbps {
                args += " -b:v \(bitrate)k"
            } else if let crf = configuration.videoCRF {
                args += " -crf \(crf)"
            } else {
                args += (configuration.transcode == .h264_fast ? " -crf 23" : " -crf 20")
            }
            args += " -c:a aac -b:a \((configuration.audioBitrateKbps ?? 192))k"
            return args
        case .hevc_fast, .hevc_quality:
            var args = "\(mov) -c:v libx265 -preset "
            args += (configuration.transcode == .hevc_fast ? "fast" : "slow")
            if let bitrate = configuration.videoBitrateKbps {
                args += " -b:v \(bitrate)k"
            } else if let crf = configuration.videoCRF {
                args += " -crf \(crf)"
            } else {
                args += (configuration.transcode == .hevc_fast ? " -crf 28" : " -crf 24")
            }
            args += " -tag:v hvc1 -c:a aac -b:a \((configuration.audioBitrateKbps ?? 192))k"
            return args
        case .vp9_fast, .vp9_quality:
            var args = "\(mov) -c:v libvpx-vp9 -deadline "
            args += (configuration.transcode == .vp9_fast ? "realtime" : "good")
            if let bitrate = configuration.videoBitrateKbps {
                args += " -b:v \(bitrate)k"
            } else if let crf = configuration.videoCRF {
                args += " -crf \(crf)"
            } else {
                args += (configuration.transcode == .vp9_fast ? " -crf 33" : " -crf 28")
            }
            args += " -c:a copy"
            return args
        }
    }

    private static func int64(from value: PythonObject?) -> Int64? {
        guard let value, value != Python.None, let intValue = Int(value) else { return nil }
        return Int64(intValue)
    }

    private static func int(from value: PythonObject?) -> Int? {
        guard let value, value != Python.None, let result = Int(value) else { return nil }
        return result
    }

    private static func timeInterval(from value: PythonObject?) -> TimeInterval? {
        guard let value, value != Python.None, let doubleValue = Double(value) else { return nil }
        return doubleValue
    }

    private static func dictionaryValue(_ dict: PythonObject, key: String) -> PythonObject? {
        do {
            return try Python.attemptThrowing {
                dict.__getitem__(PythonObject(key))
            }
        } catch {
            return nil
        }
    }

    private static func stringValue(_ dict: PythonObject, key: String) -> String? {
        guard let value = dictionaryValue(dict, key: key), value != Python.None else { return nil }
        return String(value)
    }

    private static func percent(from dict: PythonObject) -> Double? {
        if let progressDict = dictionaryValue(dict, key: "progress"),
           let value = dictionaryValue(progressDict, key: "percent"),
           let percent = normalizedPercent(from: value) {
            return percent
        }

        if let value = dictionaryValue(dict, key: "_percent_str"),
           let percent = normalizedPercent(from: value) {
            return percent
        }

        if let value = dictionaryValue(dict, key: "percentage"),
           let percent = normalizedPercent(from: value) {
            return percent
        }

        if let value = dictionaryValue(dict, key: "percent"),
           let percent = normalizedPercent(from: value) {
            return percent
        }

        return nil
    }

    private static func normalizedPercent(from value: PythonObject) -> Double? {
        guard value != Python.None else { return nil }

        if let direct = Double(value) {
            return clampPercent(direct)
        }

        if let rawString = String(value) {
            let trimmed = rawString.replacingOccurrences(of: "%", with: "").replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            if let parsed = Double(trimmed) {
                return clampPercent(parsed)
            }
        }

        return nil
    }

    private static func clampPercent(_ value: Double) -> Double {
        let normalized = value > 1 ? value / 100 : value
        return max(0, min(1, normalized))
    }

    private func yt_dlp(
        url: URL,
        configuration: YTDLPConfiguration,
        outputDirectory: URL?,
        progress: @escaping (PythonObject) -> Void,
        log: @escaping (String, String) -> Void
    ) async throws -> PythonObject? {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    guard let module = try? Python.attemptImport("yt_dlp") else {
                        throw NSError(
                            domain: "YTDLPService",
                            code: 2,
                            userInfo: [
                                NSLocalizedDescriptionKey: "The embedded yt-dlp Python module could not be loaded."
                            ]
                        )
                    }

                    let os = Python.import("os")
                    let currentWorkingDirectory = os.getcwd()
                    defer { _ = os.chdir(currentWorkingDirectory) }

                    if let outputDirectory {
                        do {
                            try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true, attributes: nil)
                        } catch {
                            log("warning", "Failed to ensure output directory exists: \(error)")
                        }
                        os.makedirs(outputDirectory.path, exist_ok: true)
                        os.chdir(outputDirectory.path)
                    }

                    let bridge = PythonCallbackBridge(progressHandler: progress, logHandler: log)

                    var options: PythonObject = [:]
                    options["progress_hooks"] = [bridge.progressHook]
                    options["postprocessor_hooks"] = [bridge.postprocessorHook]
                    options["logger"] = bridge.logger
                    options["quiet"] = true
                    options["noprogress"] = true
                    options["no_color"] = true
                    options["nocheckcertificate"] = true
                    options["noplaylist"] = true
                    options["outtmpl"] = "%(title).200B.%(ext)s"
                    options["progress_with_newline"] = true
                    options["merge_output_format"] = configuration.container.rawValue.lowercased()
                    options["concurrent_fragment_downloads"] = configuration.enableChunkedDownload ? 5 : 1
                    options["allow_unplayable_formats"] = PythonObject(!configuration.supportedFormatsOnly)

                    if let outputDirectory {
                        options["paths"] = ["home": outputDirectory.path]
                    }

                    switch configuration.kind {
                    case .audio:
                        options["format"] = "bestaudio/best"
                        var postprocessors: [PythonObject] = []
                        var audioProcessor: PythonObject = [
                            "key": "FFmpegExtractAudio",
                            "preferredcodec": configuration.audioFormat.rawValue.lowercased()
                        ]
                        if let bitrate = configuration.audioBitrateKbps {
                            audioProcessor["preferredquality"] = "\(bitrate)"
                        }
                        postprocessors.append(audioProcessor)
                        postprocessors.append(["key": "FFmpegMetadata"])
                        options["postprocessors"] = PythonObject(postprocessors)
                    case .video:
                        options["format"] = PythonObject(videoFormatSelector(configuration: configuration))
                    case .best:
                        options["format"] = "bestvideo+bestaudio/best"
                    }

                    var postprocessorArgs: PythonObject = [:]
                    var hasPostprocessorArgs = false
                    if configuration.kind != .audio, configuration.enableTranscoding,
                       let ffmpegArgs = ffmpegPostprocessorArgs(configuration: configuration) {
                        let arguments = ffmpegArgs.split(whereSeparator: { $0.isWhitespace }).map(String.init)
                        postprocessorArgs["Merger+ffmpeg"] = PythonObject(arguments)
                        hasPostprocessorArgs = true
                    }
                    if hasPostprocessorArgs {
                        options["postprocessor_args"] = postprocessorArgs
                    }

                    let downloader = try Python.attemptThrowing {
                        module.YoutubeDL(options)
                    }
                    let info = try Python.attemptThrowing {
                        downloader.extract_info(url.absoluteString, download: true)
                    }
                    continuation.resume(returning: info)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

private final class PythonCallbackBridge {
    let progressHook: PythonObject
    let postprocessorHook: PythonObject
    let logger: PythonObject

    private let logCallback: PythonObject

    init(progressHandler: @escaping (PythonObject) -> Void, logHandler: @escaping (String, String) -> Void) {
        progressHook = PythonObject { (args: [PythonConvertible]) -> PythonConvertible in
            if let first = args.first {
                progressHandler(PythonObject(first))
            }
            return Python.None
        }

        postprocessorHook = PythonObject { (args: [PythonConvertible]) -> PythonConvertible in
            if let first = args.first {
                progressHandler(PythonObject(first))
            }
            return Python.None
        }

        logCallback = PythonObject { (args: [PythonConvertible]) -> PythonConvertible in
            guard args.count >= 2 else { return Python.None }
            let level = String(PythonObject(args[0])) ?? "info"
            let message = String(PythonObject(args[1])) ?? ""
            logHandler(level, message)
            return Python.None
        }

        let builtins = Python.import("builtins")
        builtins.exec(
            """
class SwiftLogger:
    def __init__(self, callback):
        self._callback = callback

    def debug(self, message):
        self._callback('debug', str(message))

    def info(self, message):
        self._callback('info', str(message))

    def warning(self, message):
        self._callback('warning', str(message))

    def error(self, message):
        self._callback('error', str(message))

    def critical(self, message):
        self._callback('critical', str(message))
"""
        )

        let main = Python.import("__main__")
        logger = main.SwiftLogger(logCallback)
    }
}
