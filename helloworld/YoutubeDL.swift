//
//  YoutubeDL.swift
//  YD
//
//  Created by 안창범 on 2020/09/03.
//  Copyright © 2020 Kewlbear. All rights reserved.
//

import Foundation

struct Info: CustomStringConvertible {
    let info: PythonObject

    var dict: [String: PythonObject]? {
        Dictionary(info)
    }

    var title: String? {
        dict?["title"].flatMap { String($0) }
    }

    var format: Format? {
        dict.map { Format(format: $0) }
    }
    
    var formats: [Format] {
        let array: [PythonObject]? = dict?["formats"].flatMap { Array($0) }
        let dicts: [[String: PythonObject]?]? = array?.map { Dictionary($0) }
        return dicts?.compactMap { $0.flatMap { Format(format: $0) } } ?? []
    }
    
    var description: String {
        "\(dict?["title"] ?? "no title?")"
    }
}

let chunkSize = 10_000_000

@dynamicMemberLookup
struct Format: CustomStringConvertible {
    let format: [String: PythonObject]
    
    var url: URL? { self[dynamicMember: "url"].flatMap { URL(string: $0) } }
    
    var httpHeaders: [String: String] {
        format["http_headers"].flatMap { Dictionary($0) } ?? [:]
    }
    
    var urlRequest: URLRequest? {
        guard let url = url else {
            return nil
        }
        var request = URLRequest(url: url)
        for (field, value) in httpHeaders {
            request.addValue(value, forHTTPHeaderField: field)
        }
        
        // https://github.com/ytdl-org/youtube-dl/issues/15271#issuecomment-362834889
        let random = (0...(chunkSize * 95 / 100)).randomElement()
        let end = random ?? (chunkSize - 1)
        request.setValue("bytes=0-\(end)", forHTTPHeaderField: "Range")

        return request
    }
    
    var height: Int? { format["height"].flatMap { Int($0) } }
    
    var filesize: Int? { format["filesize"].flatMap { Int($0) } }
    
    var isAudioOnly: Bool { self.vcodec == "none" }
    
    var isVideoOnly: Bool { self.acodec == "none" }
    
    var description: String {
        "\(format["format"] ?? "no format?") \(format["ext"] ?? "no ext?") \(format["filesize"] ?? "no size?")"
    }
    
    subscript(dynamicMember key: String) -> String? {
        format[key].flatMap { String($0) }
    }
}

class YoutubeDL {
    func extractInfo(url: URL) -> ([Format], Info?) {
        let youtube_dl = Python.import("youtube_dl")
        
        let options: PythonObject = [
            "format": "bestvideo,bestaudio[ext=m4a]",
            //        "outtmpl": location.path.pythonObject,
            //        "progress_hooks": [progress_hook],
            //        "nooverwrites": false,
            "nocheckcertificate": true,
            //            "update_self": true,
        ]
        
        let youtubeDL = youtube_dl.YoutubeDL(options)
        
        print(#function, url, trace)
        let info = youtubeDL.extract_info(url.absoluteString, download: false, process: true)
        
        let format_selector = youtubeDL.build_format_selector(options["format"])
        let formats_to_download = format_selector(info)
        var formats: [Format] = []
        for format in formats_to_download {
            guard let dict: [String: PythonObject] = Dictionary(format) else { fatalError() }
            formats.append(Format(format: dict))
        }
        
        return (formats, Info(info: info))
    }
}

extension PyObjectPointer {
    init<T>(_ pointer: UnsafeMutablePointer<T>) {
        self = PyObjectPointer(OpaquePointer(pointer))
    }
}
