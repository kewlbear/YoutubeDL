import Foundation

/// Lightweight representation of the metadata that yt-dlp returns for a download.
/// Only the fields that the app currently needs are modelled to keep decoding resilient
/// to upstream changes.
public struct Info: Codable, Hashable {
    public struct Format: Codable, Hashable, Identifiable {
        public var formatId: String
        public var format: String
        public var ext: String?
        public var resolution: String?
        public var vcodec: String?
        public var acodec: String?
        public var tbr: Double?
        public var filesize: Double?

        public var id: String { formatId }

        public init(
            formatId: String,
            format: String,
            ext: String? = nil,
            resolution: String? = nil,
            vcodec: String? = nil,
            acodec: String? = nil,
            tbr: Double? = nil,
            filesize: Double? = nil
        ) {
            self.formatId = formatId
            self.format = format
            self.ext = ext
            self.resolution = resolution
            self.vcodec = vcodec
            self.acodec = acodec
            self.tbr = tbr
            self.filesize = filesize
        }

        private enum CodingKeys: String, CodingKey {
            case formatId = "format_id"
            case format
            case ext
            case resolution
            case vcodec
            case acodec
            case tbr
            case filesize
        }
    }

    public var id: String?
    public var title: String
    public var duration: Double?
    public var uploader: String?
    public var webpageURL: URL?
    public var thumbnail: URL?
    public var formats: [Format]

    public init(
        id: String? = nil,
        title: String,
        duration: Double? = nil,
        uploader: String? = nil,
        webpageURL: URL? = nil,
        thumbnail: URL? = nil,
        formats: [Format] = []
    ) {
        self.id = id
        self.title = title
        self.duration = duration
        self.uploader = uploader
        self.webpageURL = webpageURL
        self.thumbnail = thumbnail
        self.formats = formats
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case duration
        case uploader
        case webpageURL = "webpage_url"
        case thumbnail
        case formats
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(String.self, forKey: .id)
        self.title = try container.decodeIfPresent(String.self, forKey: .title) ?? "Untitled"
        self.duration = try container.decodeIfPresent(Double.self, forKey: .duration)
        self.uploader = try container.decodeIfPresent(String.self, forKey: .uploader)
        self.webpageURL = try container.decodeIfPresent(URL.self, forKey: .webpageURL)
        self.thumbnail = try container.decodeIfPresent(URL.self, forKey: .thumbnail)
        self.formats = try container.decodeIfPresent([Format].self, forKey: .formats) ?? []
    }
}

public extension Info {
    /// Sanitised title that is safe to use as a directory name on iOS.
    var safeTitle: String {
        let illegal = CharacterSet(charactersIn: "\\/:?%*|\"<>\u{0000}")
        let cleaned = title.components(separatedBy: illegal).joined(separator: "-")
        let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Download" : trimmed
    }

    /// Convenience helper to display a human readable duration if available.
    var formattedDuration: String? {
        guard let duration else { return nil }
        guard duration.isFinite else { return nil }
        let totalSeconds = Int(duration.rounded())
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
}

public extension Info.Format {
    /// Human readable summary suitable for list rows in the UI.
    var summary: String {
        var parts: [String] = [format]
        if let resolution, !resolution.isEmpty, resolution != "audio only" {
            parts.append(resolution)
        }
        if let vcodec, !vcodec.isEmpty { parts.append(vcodec) }
        if let acodec, !acodec.isEmpty, acodec != vcodec { parts.append(acodec) }
        if let rate = tbr, rate > 0 {
            parts.append(String(format: "%.0f kbps", rate))
        }
        if let size = formattedFilesize {
            parts.append(size)
        }
        return parts.joined(separator: " · ")
    }

    private var formattedFilesize: String? {
        guard let filesize, filesize > 0 else { return nil }
        let units = ["B", "KB", "MB", "GB"]
        var size = filesize
        var unitIndex = 0
        while size >= 1024, unitIndex < units.count - 1 {
            size /= 1024
            unitIndex += 1
        }
        return String(format: unitIndex == 0 ? "%.0f %@" : "%.1f %@", size, units[unitIndex])
    }
}
