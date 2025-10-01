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
        progress: @escaping (ProgressUpdate) -> Void,
        logHandler: ((String, String) -> Void)? = nil,
        makeTranscodeProgressBlock: (() -> ((Double) -> Void)?)? = nil
    ) async throws -> YTDLPResult {
        progress(.init(stage: .extracting, title: nil))

        var infoObj: PythonObject? = nil
        var files: [String] = []
        var infos: [PythonObject] = []
        var errorMessage: String?

        let argv = buildArguments(for: url, configuration: configuration)
        try await yt_dlp(argv: argv) { dict in
            infoObj = dict["info_dict"]

            let statusObject = dict["status"]
            let status: String
            if statusObject == Python.None {
                status = "unknown"
            } else {
                status = String(statusObject) ?? "unknown"
            }

            switch status {
            case "downloading":
                let downloaded = Self.int64(from: dict["downloaded_bytes"])
                let total = Self.int64(from: dict["total_bytes"]) ?? Self.int64(from: dict["total_bytes_estimate"])
                let speed = Self.int(from: dict["speed"])
                let eta = Self.timeInterval(from: dict["eta"])
                progress(.init(stage: .downloading(downloaded: downloaded, total: total, speed: speed, eta: eta), title: nil))
            case "finished":
                let filenameObject = dict["filename"]
                if filenameObject != Python.None, let fname = String(filenameObject) {
                    files.append(fname)
                }
                if let infoObj { infos.append(infoObj) }
            default:
                break
            }
        } log: { level, message in
            logHandler?(level, message)
            if level == "error" { errorMessage = message }
        } makeTranscodeProgressBlock: {
            guard let makeTranscodeProgressBlock else { return { _ in } }
            guard let callback = makeTranscodeProgressBlock() else { return { _ in } }
            return { value in
                progress(.init(stage: .transcoding(value), title: nil))
                callback(value)
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

    private func yt_dlp(
        argv: [String],
        progress: @escaping (PythonObject) -> Void,
        log: @escaping (String, String) -> Void,
        makeTranscodeProgressBlock: @escaping () -> ((Double) -> Void)?
    ) async throws {
        _ = progress
        _ = log
        _ = makeTranscodeProgressBlock

        guard let _ = try? Python.attemptImport("yt_dlp") else {
            throw NSError(
                domain: "YTDLPService",
                code: 2,
                userInfo: [
                    NSLocalizedDescriptionKey: "The embedded yt-dlp Python module could not be loaded."
                ]
            )
        }

        throw NSError(
            domain: "YTDLPService",
            code: 3,
            userInfo: [
                NSLocalizedDescriptionKey: "The yt-dlp execution bridge is unavailable in this build."
            ]
        )
    }
}
