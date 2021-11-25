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

class AppModel: ObservableObject {
    @Published var url: URL?
    
    @Published var youtubeDL = YoutubeDL()
    
    @Published var enableChunkedDownload = true
    
    @Published var enableTranscoding = true
    
    @Published var supportedFormatsOnly = true
    
    @Published var exportToPhotos = true
    
    @Published var fileURL: URL?
    
    @Published var downloads: [URL] = []
    
    var formatSelector: YoutubeDL.FormatSelector?
    
    lazy var subscriptions = Set<AnyCancellable>()
    
    init() {
        $url.compactMap { $0 }
        .sink { url in
            Task {
                await self.startDownload(url: url)
            }
        }.store(in: &subscriptions)
        
        do {
            downloads = try loadDownloads()
        } catch {
            // FIXME: ...
            print(#function, error)
        }
    }
    
    func startDownload(url: URL) async {
        do {
            let fileURL = try await youtubeDL.download(url: url, formatSelector: formatSelector)
            print(#function, self.fileURL ?? "no url?")
            Task.detached { @MainActor in
                self.fileURL = fileURL
            }
        } catch YoutubeDLError.canceled {
            print(#function, "canceled")
        } catch {
            print(#function, error)
        }
    }
    
    func save(info: Info) throws -> URL {
        let title = info.safeTitle
        let fileManager = FileManager.default
        var url = try documentsDirectory()
            .appendingPathComponent(title)
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
    
    func transcode() {
        
    }
    
    func share() {
        
    }
}
