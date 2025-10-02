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
            let status = String(dict["status"]) ?? "unknown"

            switch status {
            case "downloading":
                let downloaded = Self.int64(from: dict["downloaded_bytes"])
                let total = Self.int64(from: dict["total_bytes"]) ??
                    Self.int64(from: dict["total_bytes_estimate"])
                let speed = Self.int(from: dict["speed"])
                let eta = Self.timeInterval(from: dict["eta"])
                progress(.init(stage: .downloading(downloaded: downloaded, total: total, speed: speed, eta: eta), title: nil))
            case "finished":
                if let fname = Self.string(from: dict["filename"]) {
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
        guard let value = sanitized(value), let intValue = Int(value) else { return nil }
        return Int64(intValue)
    }

    private static func int(from value: PythonObject?) -> Int? {
        guard let value = sanitized(value), let result = Int(value) else { return nil }
        return result
    }

    private static func timeInterval(from value: PythonObject?) -> TimeInterval? {
        guard let value = sanitized(value), let doubleValue = Double(value) else { return nil }
        return doubleValue
    }

    private static func string(from value: PythonObject?) -> String? {
        guard let value = sanitized(value) else { return nil }
        return String(value)
    }

    private static func sanitized(_ value: PythonObject?) -> PythonObject? {
        guard let value, value != Python.None else { return nil }
        return value
    }

    private func yt_dlp(
        argv: [String],
        progress: @escaping (PythonObject) -> Void,
        log: @escaping (String, String) -> Void,
        makeTranscodeProgressBlock: @escaping () -> ((Double) -> Void)?
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let pyArgv = PythonObject(argv)

                    let progressBlock: @convention(block) (PythonObject) -> PythonObject = { dictionary in
                        progress(dictionary)
                        return Python.None
                    }
                    let progressCallback = PythonObject(progressBlock)

                    let logBlock: @convention(block) (PythonObject, PythonObject) -> PythonObject = { level, message in
                        let levelString = String(level) ?? "info"
                        let messageString = String(message) ?? String(describing: message)
                        log(levelString, messageString)
                        return Python.None
                    }
                    let logCallback = PythonObject(logBlock)

                    let transcodeFactoryBlock: @convention(block) () -> PythonObject = {
                        guard let swiftCallback = makeTranscodeProgressBlock() else {
                            return Python.None
                        }

                        let wrappedBlock: @convention(block) (PythonObject) -> PythonObject = { value in
                            if let doubleValue = Double(value) {
                                swiftCallback(doubleValue)
                            } else if let stringValue = String(value) {
                                let trimmed = stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                                if let parsed = Double(trimmed) {
                                    swiftCallback(parsed)
                                } else if trimmed.hasSuffix("%"),
                                          let percent = Double(trimmed.dropLast()) {
                                    swiftCallback(percent / 100.0)
                                }
                            }
                            return Python.None
                        }

                        return PythonObject(wrappedBlock)
                    }
                    let transcodeFactory = PythonObject(transcodeFactoryBlock)

                    let result = Self.pythonRunner.run(pyArgv, progressCallback, logCallback, transcodeFactory)

                    if let exitCode = Int(result), exitCode != 0 {
                        let error = NSError(
                            domain: "YTDLPService",
                            code: exitCode,
                            userInfo: [NSLocalizedDescriptionKey: "yt-dlp exited with code \(exitCode)"]
                        )
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: ())
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static let pythonRunner: PythonObject = {
        let builtins = Python.import("builtins")
        let types = Python.import("types")
        let module = types.ModuleType("__ytdlp_service__")
        let code = """
import yt_dlp

def _normalize_message(message):
    if isinstance(message, bytes):
        try:
            return message.decode()
        except Exception:
            return repr(message)
    return str(message)

def run(argv, progress_cb, log_cb, transcode_factory):
    class SwiftLogger(object):
        def debug(self, msg):
            log_cb("debug", _normalize_message(msg))

        def info(self, msg):
            log_cb("info", _normalize_message(msg))

        def warning(self, msg):
            log_cb("warning", _normalize_message(msg))

        def error(self, msg):
            log_cb("error", _normalize_message(msg))

        def fatal(self, msg):
            log_cb("fatal", _normalize_message(msg))

    hooks = []
    if progress_cb is not None:
        def _progress_hook(data):
            try:
                progress_cb(data)
            except Exception as exc:
                log_cb("error", f"progress hook error: {exc}")

        hooks.append(_progress_hook)

    transcode_callback = None

    def _postprocessor_hook(data):
        nonlocal transcode_callback
        status = data.get("status")
        if status == "started":
            try:
                callback = transcode_factory()
            except Exception as exc:
                log_cb("error", f"transcode factory error: {exc}")
                callback = None
            transcode_callback = callback if callback is not None else None
            if transcode_callback is not None:
                try:
                    transcode_callback(0.0)
                except Exception:
                    pass
        elif status in ("processing", "downloading"):
            if transcode_callback is not None:
                fraction = None
                processed = data.get("processed_bytes") or data.get("downloaded_bytes") or data.get("fragment_index")
                total = data.get("total_bytes") or data.get("total_bytes_estimate") or data.get("fragment_count")
                if processed is not None and total:
                    try:
                        fraction = float(processed) / float(total)
                    except Exception:
                        fraction = None
                if fraction is None:
                    percent = data.get("percent") or data.get("_percent_str") or data.get("progress")
                    if percent is not None:
                        if isinstance(percent, str):
                            stripped = percent.strip()
                            if stripped.endswith("%"):
                                stripped = stripped[:-1]
                            percent = stripped
                        try:
                            value = float(percent)
                            fraction = value / 100.0 if value > 1.0 else value
                        except Exception:
                            fraction = None
                if fraction is not None:
                    try:
                        transcode_callback(max(0.0, min(float(fraction), 1.0)))
                    except Exception:
                        pass
        elif status in ("finished", "done"):
            if transcode_callback is not None:
                try:
                    transcode_callback(1.0)
                except Exception:
                    pass
                transcode_callback = None

    parser, opts, args = yt_dlp.parse_options(list(argv))
    if opts is None:
        return 101

    params = vars(opts)
    params.setdefault("progress_hooks", [])
    params["progress_hooks"].extend(hooks)
    params.setdefault("postprocessor_hooks", []).append(_postprocessor_hook)
    params["logger"] = SwiftLogger()

    ydl = yt_dlp.YoutubeDL(params)
    try:
        result = ydl.download(list(args) if args is not None else [])
    finally:
        try:
            ydl.close()
        except Exception:
            pass

    return int(result)
"""
        builtins.exec(code, module.__dict__)
        return module
    }()
}
