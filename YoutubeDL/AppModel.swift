import Foundation
import Combine
import SwiftUI
import AVFoundation
import Photos
import YoutubeDL
import PythonKit

@MainActor
final class AppModel: ObservableObject {
    @Published var url: URL? = nil
    @Published var youtubeDL: YoutubeDL = YoutubeDL()

    @Published var enableChunkedDownload: Bool = true
    @Published var enableTranscoding: Bool = true
    @Published var supportedFormatsOnly: Bool = true
    @Published var exportToPhotos: Bool = true

    @Published var fileURL: URL? = nil
    @Published var downloads: [URL] = []
    @Published var showProgress: Bool = false
    @Published var progress: Progress = Progress()
    @Published var error: Error? = nil
    @Published var exception: PythonObject? = nil
    @Published var info: Info? = nil
    @Published var webViewURL: URL? = nil
    @Published var outputFileURL: URL? = nil

    @Published var kind: DownloadKind = .best
    @Published var videoQuality: VideoQuality = .best
    @Published var container: ContainerFormat = .mp4
    @Published var audioFormat: AudioFormat = .m4a
    @Published var transcode: TranscodePreset = .copy

    @Published var videoCRF: Int? = nil
    @Published var videoBitrateKbps: Int? = nil
    @Published var audioBitrateKbps: Int? = nil

    @Published var defaultSaveFolder: URL? = nil
    @Published var perDownloadFolder: URL? = nil

    private let service: YTDLPService
    private let defaults: UserDefaults
    private var subscriptions = Set<AnyCancellable>()

    private enum DefaultsKeys {
        static let kind = "app.kind"
        static let videoQuality = "app.videoQuality"
        static let container = "app.container"
        static let audioFormat = "app.audioFormat"
        static let transcode = "app.transcode"
        static let videoCRF = "app.videoCRF"
        static let videoBitrate = "app.videoBitrate"
        static let audioBitrate = "app.audioBitrate"
        static let enableTranscoding = "app.enableTranscoding"
        static let enableChunkedDownload = "app.enableChunkedDownload"
        static let supportedFormats = "app.supportedFormats"
        static let exportToPhotos = "app.exportToPhotos"
        static let defaultFolder = "app.defaultFolder"
        static let perDownloadFolder = "app.perDownloadFolder"
    }

    init(service: YTDLPService = .init(), defaults: UserDefaults = .standard) {
        self.service = service
        self.defaults = defaults

        if let docs = try? documentsDirectory() {
            youtubeDL.downloadsDirectory = docs
        }

        loadPreferences()
        observeURLChanges()
        observePreferenceChanges()
        loadStoredDownloads()
    }

    // MARK: - API

    func startDownload(url: URL) async {
        resetTransientState()

        if let per = perDownloadFolder ?? defaultSaveFolder {
            youtubeDL.downloadsDirectory = per
        } else if let docs = try? documentsDirectory() {
            youtubeDL.downloadsDirectory = docs
        }

        let configuration = YTDLPConfiguration(
            kind: kind,
            videoQuality: videoQuality,
            container: container,
            audioFormat: audioFormat,
            transcode: transcode,
            videoCRF: videoCRF,
            videoBitrateKbps: videoBitrateKbps,
            audioBitrateKbps: audioBitrateKbps,
            enableTranscoding: enableTranscoding,
            enableChunkedDownload: enableChunkedDownload,
            supportedFormatsOnly: supportedFormatsOnly
        )

        do {
            let result = try await service.run(
                url: url,
                configuration: configuration,
                progress: { [weak self] update in
                    guard let self else { return }
                    Task { @MainActor in
                        self.apply(progressUpdate: update)
                    }
                },
                logHandler: { level, message in
                    print("[yt-dlp]", level, message)
                },
                makeTranscodeProgressBlock: { [weak self] in
                    guard let self else { return nil }
                    Task { @MainActor in
                        self.progress.kind = nil
                        self.progress.localizedDescription = NSLocalizedString("Transcoding...", comment: "")
                        self.progress.completedUnitCount = 0
                        self.progress.totalUnitCount = 100
                    }
                    let start = ProcessInfo.processInfo.systemUptime
                    return { value in
                        Task { @MainActor in
                            let elapsed = ProcessInfo.processInfo.systemUptime - start
                            let speed = value / max(elapsed, 0.000001)
                            let eta = (1 - value) / max(speed, 0.000001)
                            self.progress.completedUnitCount = Int64(value * 100)
                            self.progress.estimatedTimeRemaining = eta.isFinite ? eta : nil
                        }
                    }
                }
            )

            if let infoObject = result.infoObject,
               let decoded = try? PythonDecoder().decode(Info.self, from: infoObject) {
                info = decoded
            }

            guard let filename = result.infoObject.flatMap({ String($0["_filename"]) }) else {
                showProgress = false
                return
            }

            let outputURL: URL
            if #available(iOS 16.0, *) {
                outputURL = URL(filePath: filename)
            } else {
                outputURL = URL(fileURLWithPath: filename)
            }

            var finalURL = outputURL

            if let info {
                do {
                    let directory = try save(info: info, movingFileAt: outputURL)
                    finalURL = directory.appendingPathComponent(outputURL.lastPathComponent)
                    var stored = try loadDownloads()
                    if !stored.contains(directory) {
                        stored.insert(directory, at: 0)
                    }
                    downloads = stored
                } catch {
                    print("startDownload: failed to persist metadata", error)
                }
            }

            outputFileURL = finalURL
            showProgress = false

            if exportToPhotos && isVideoFile(finalURL) {
                exportToPhotosLibrary(finalURL)
            }

            setPerDownloadFolder(url: nil)
            notify(body: "Finished")
        } catch PythonError.exception(let exception, _) {
            print("AppModel.startDownload python exception:", exception)
            self.exception = exception
            self.showProgress = false
        } catch {
            print("AppModel.startDownload error:", error)
            if (url.host ?? "").hasSuffix("instagram.com") {
                webViewURL = url
            } else {
                self.error = error
            }
            self.showProgress = false
        }
    }

    func setGlobalSaveFolder(url: URL?) {
        defaultSaveFolder = url
        storeBookmark(url: url, key: DefaultsKeys.defaultFolder)
    }

    func setPerDownloadFolder(url: URL?) {
        perDownloadFolder = url
        storeBookmark(url: url, key: DefaultsKeys.perDownloadFolder)
    }

    func notify(body: String) {
        print("[AppModel.notify]", body)
    }

    // MARK: - Private helpers

    private func loadStoredDownloads() {
        do {
            downloads = try loadDownloads()
        } catch {
            print("AppModel.init loadDownloads()", error)
        }
    }

    private func resetTransientState() {
        error = nil
        exception = nil
        outputFileURL = nil
        info = nil
        showProgress = true
        progress = Progress()
        progress.localizedDescription = NSLocalizedString("Extracting info", comment: "progress description")
    }

    private func apply(progressUpdate update: YTDLPService.ProgressUpdate) {
        switch update.stage {
        case .extracting:
            showProgress = true
            progress.kind = .file
            progress.fileOperationKind = .downloading
            progress.completedUnitCount = 0
            progress.totalUnitCount = 0
            progress.localizedDescription = NSLocalizedString("Extracting info", comment: "progress description")
        case let .downloading(downloaded, total, speed, eta):
            progress.kind = .file
            progress.fileOperationKind = .downloading
            progress.totalUnitCount = total ?? 0
            progress.completedUnitCount = downloaded ?? 0
            progress.localizedDescription = NSLocalizedString("Downloading", comment: "progress description")
            if let speed {
                progress.throughput = speed
            } else {
                progress.throughput = nil
            }
            progress.estimatedTimeRemaining = eta
        case let .transcoding(value):
            progress.kind = nil
            progress.localizedDescription = NSLocalizedString("Transcoding...", comment: "")
            progress.completedUnitCount = Int64(value * 100)
            progress.totalUnitCount = 100
        }
    }

    private func observeURLChanges() {
        $url
            .compactMap { $0 }
            .removeDuplicates()
            .sink { [weak self] url in
                Task {
                    await self?.startDownload(url: url)
                }
            }
            .store(in: &subscriptions)
    }

    private func observePreferenceChanges() {
        $kind
            .dropFirst()
            .sink { [weak self] in self?.defaults.set($0.rawValue, forKey: DefaultsKeys.kind) }
            .store(in: &subscriptions)

        $videoQuality
            .dropFirst()
            .sink { [weak self] in self?.defaults.set($0.rawValue, forKey: DefaultsKeys.videoQuality) }
            .store(in: &subscriptions)

        $container
            .dropFirst()
            .sink { [weak self] in self?.defaults.set($0.rawValue, forKey: DefaultsKeys.container) }
            .store(in: &subscriptions)

        $audioFormat
            .dropFirst()
            .sink { [weak self] in self?.defaults.set($0.rawValue, forKey: DefaultsKeys.audioFormat) }
            .store(in: &subscriptions)

        $transcode
            .dropFirst()
            .sink { [weak self] in self?.defaults.set($0.rawValue, forKey: DefaultsKeys.transcode) }
            .store(in: &subscriptions)

        $videoCRF
            .dropFirst()
            .sink { [weak self] in self?.defaults.set($0, forKey: DefaultsKeys.videoCRF) }
            .store(in: &subscriptions)

        $videoBitrateKbps
            .dropFirst()
            .sink { [weak self] in self?.defaults.set($0, forKey: DefaultsKeys.videoBitrate) }
            .store(in: &subscriptions)

        $audioBitrateKbps
            .dropFirst()
            .sink { [weak self] in self?.defaults.set($0, forKey: DefaultsKeys.audioBitrate) }
            .store(in: &subscriptions)

        $enableTranscoding
            .dropFirst()
            .sink { [weak self] in self?.defaults.set($0, forKey: DefaultsKeys.enableTranscoding) }
            .store(in: &subscriptions)

        $enableChunkedDownload
            .dropFirst()
            .sink { [weak self] in self?.defaults.set($0, forKey: DefaultsKeys.enableChunkedDownload) }
            .store(in: &subscriptions)

        $supportedFormatsOnly
            .dropFirst()
            .sink { [weak self] in self?.defaults.set($0, forKey: DefaultsKeys.supportedFormats) }
            .store(in: &subscriptions)

        $exportToPhotos
            .dropFirst()
            .sink { [weak self] in self?.defaults.set($0, forKey: DefaultsKeys.exportToPhotos) }
            .store(in: &subscriptions)
    }

    private func loadPreferences() {
        if let raw = defaults.string(forKey: DefaultsKeys.kind), let value = DownloadKind(rawValue: raw) {
            kind = value
        }

        if let raw = defaults.string(forKey: DefaultsKeys.videoQuality), let value = VideoQuality(rawValue: raw) {
            videoQuality = value
        }

        if let raw = defaults.string(forKey: DefaultsKeys.container), let value = ContainerFormat(rawValue: raw) {
            container = value
        }

        if let raw = defaults.string(forKey: DefaultsKeys.audioFormat), let value = AudioFormat(rawValue: raw) {
            audioFormat = value
        }

        if let raw = defaults.string(forKey: DefaultsKeys.transcode), let value = TranscodePreset(rawValue: raw) {
            transcode = value
        }

        if defaults.object(forKey: DefaultsKeys.videoCRF) != nil {
            videoCRF = defaults.integer(forKey: DefaultsKeys.videoCRF)
        }

        if defaults.object(forKey: DefaultsKeys.videoBitrate) != nil {
            videoBitrateKbps = defaults.integer(forKey: DefaultsKeys.videoBitrate)
        }

        if defaults.object(forKey: DefaultsKeys.audioBitrate) != nil {
            audioBitrateKbps = defaults.integer(forKey: DefaultsKeys.audioBitrate)
        }

        if defaults.object(forKey: DefaultsKeys.enableTranscoding) != nil {
            enableTranscoding = defaults.bool(forKey: DefaultsKeys.enableTranscoding)
        }

        if defaults.object(forKey: DefaultsKeys.enableChunkedDownload) != nil {
            enableChunkedDownload = defaults.bool(forKey: DefaultsKeys.enableChunkedDownload)
        }

        if defaults.object(forKey: DefaultsKeys.supportedFormats) != nil {
            supportedFormatsOnly = defaults.bool(forKey: DefaultsKeys.supportedFormats)
        }

        if defaults.object(forKey: DefaultsKeys.exportToPhotos) != nil {
            exportToPhotos = defaults.bool(forKey: DefaultsKeys.exportToPhotos)
        }

        defaultSaveFolder = resolveBookmark(forKey: DefaultsKeys.defaultFolder)
        perDownloadFolder = resolveBookmark(forKey: DefaultsKeys.perDownloadFolder)
    }

    private func storeBookmark(url: URL?, key: String) {
        guard let url else {
            defaults.removeObject(forKey: key)
            return
        }

        do {
            let data = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            defaults.set(data, forKey: key)
        } catch {
            print("storeBookmark error", error)
        }
    }

    private func resolveBookmark(forKey key: String) -> URL? {
        guard let data = defaults.data(forKey: key) else { return nil }
        do {
            var stale = false
            let url = try URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
            if stale {
                storeBookmark(url: url, key: key)
            }
            return url
        } catch {
            print("resolveBookmark error", error)
            defaults.removeObject(forKey: key)
            return nil
        }
    }

    private func exportToPhotosLibrary(_ url: URL) {
        PHPhotoLibrary.shared().performChanges({
            _ = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
        }) { success, error in
            if let error { print("exportToPhotos error:", error) }
        }
    }

    private func isVideoFile(_ url: URL) -> Bool {
        let exts = ["mp4", "mov", "m4v", "mkv", "webm"]
        return exts.contains(url.pathExtension.lowercased())
    }

    @discardableResult
    func save(info: Info, movingFileAt sourceURL: URL) throws -> URL {
        let title = info.safeTitle
        let fm = FileManager.default

        let baseDirectory = sourceURL.deletingLastPathComponent()
        var directory: URL
        if baseDirectory.lastPathComponent == title {
            directory = baseDirectory
        } else {
            directory = baseDirectory.appendingPathComponent(title, isDirectory: true)
            var attempt = 2
            while fm.fileExists(atPath: directory.path) {
                directory = baseDirectory.appendingPathComponent("\(title) \(attempt)", isDirectory: true)
                attempt += 1
            }
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        do {
            try directory.setResourceValues(values)
        } catch {
            print("save(info:movingFileAt:) setResourceValues", error)
        }

        let data = try JSONEncoder().encode(info)
        try data.write(to: directory.appendingPathComponent("Info.json"), options: .atomic)

        let destination = directory.appendingPathComponent(sourceURL.lastPathComponent)
        if destination != sourceURL {
            if fm.fileExists(atPath: destination.path) {
                try fm.removeItem(at: destination)
            }
            try fm.moveItem(at: sourceURL, to: destination)
        }

        return directory
    }

    func loadDownloads() throws -> [URL] {
        let keys: Set<URLResourceKey> = [.nameKey, .isDirectoryKey, .contentModificationDateKey]
        let documents = try documentsDirectory()
        guard let enumerator = FileManager.default.enumerator(at: documents, includingPropertiesForKeys: Array(keys), options: .skipsHiddenFiles) else { return [] }
        var urls: [(url: URL, date: Date)] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: keys)
            guard enumerator.level == 2,
                  values.isDirectory == false,
                  url.lastPathComponent == "Info.json" else { continue }
            let directory = url.deletingLastPathComponent()
            let date = values.contentModificationDate ?? .distantPast
            urls.append((directory, date))
        }
        return urls
            .sorted { $0.date > $1.date }
            .map { $0.url }
    }

    func documentsDirectory() throws -> URL {
        try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
    }
}
