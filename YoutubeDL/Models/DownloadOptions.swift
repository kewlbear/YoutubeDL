import Foundation

enum DownloadKind: String, CaseIterable, Identifiable {
    case video = "Video"
    case audio = "Audio"
    case best  = "Best"

    var id: String { rawValue }
}

enum VideoQuality: String, CaseIterable, Identifiable {
    case p2160 = "2160p (4K)"
    case p1440 = "1440p"
    case p1080 = "1080p"
    case p720  = "720p"
    case p480  = "480p"
    case p360  = "360p"
    case best  = "Best"

    var id: String { rawValue }
}

enum ContainerFormat: String, CaseIterable, Identifiable {
    case mp4 = "mp4"
    case mkv = "mkv"
    case webm = "webm"

    var id: String { rawValue }
}

enum AudioFormat: String, CaseIterable, Identifiable {
    case m4a = "m4a"
    case mp3 = "mp3"
    case opus = "opus"
    case flac = "flac"
    case wav = "wav"
    case best = "best"

    var id: String { rawValue }
}

enum TranscodePreset: String, CaseIterable, Identifiable {
    case copy = "Copy (no re-encode)"
    case h264_fast = "H.264 - Fast"
    case h264_quality = "H.264 - Quality"
    case hevc_fast = "HEVC - Fast"
    case hevc_quality = "HEVC - Quality"
    case vp9_fast = "VP9 - Fast"
    case vp9_quality = "VP9 - Quality"

    var id: String { rawValue }
}

extension TranscodePreset {
    var helpText: String {
        switch self {
        case .copy:
            return "No re-encode — fastest, smallest CPU. If source is AV1/VP9 the file may not be Photos-compatible."
        case .h264_fast:
            return "H.264 encoding with fast preset — good balance between speed and compatibility."
        case .h264_quality:
            return "H.264 with quality preset — slower but higher visual quality."
        case .hevc_fast:
            return "HEVC (H.265) fast — smaller files but requires modern devices to playback natively."
        case .hevc_quality:
            return "HEVC quality — best efficiency, slower encoding."
        case .vp9_fast:
            return "VP9 (WebM) — web-optimized, may not be Photos-compatible."
        case .vp9_quality:
            return "VP9 high quality — large CPU cost, WEBM container."
        }
    }
}
