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

class AppModel: ObservableObject {
    static private let isPythonInitialized: Bool = {
        print("initialize Python")
        PythonSupport.initialize()
        return true
    }()
    
    @Published var url: URL?
    
    @MainActor @Published var youtubeDL: YoutubeDL?
    
    @Published var enableChunkedDownload = true
    
    @Published var enableTranscoding = true
    
    @Published var supportedFormatsOnly = true
    
    var formatSelector: ((Info?) async -> [Format])?
    
    lazy var subscriptions = Set<AnyCancellable>()
    
    init() {
        $url.compactMap { $0 }
        .sink { url in
            self.startDownload(url: url)
        }.store(in: &subscriptions)
    }
    
    func startDownload(url: URL) {
        guard Self.isPythonInitialized else { return }
        
        Task {
            do {
                let youtubeDL = try await YoutubeDL(initializePython: false, downloadPythonModule: YoutubeDL.shouldDownloadPythonModule)
                await MainActor.run {
                    self.youtubeDL = youtubeDL
                }
                let fileURL = try await youtubeDL.download(url: url, formatSelector: formatSelector)
                print(#function, fileURL)
            } catch YoutubeDLError.canceled {
                print(#function, "canceled")
            } catch {
                print(#function, error)
            }
        }
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