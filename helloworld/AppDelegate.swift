//
//  AppDelegate.swift
//  Hello World
//
//  Created by 안창범 on 2020/04/20.
//  Copyright © 2020 Jane Developer. All rights reserved.
//

import UIKit
import Python
import Intents
import Photos
import SwiftUI

let trace = "trace"

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

struct Format: CustomStringConvertible {
    let format: [String: PythonObject]
    
    var url: URL? { format["url"].flatMap { String($0) }.flatMap { URL(string: $0) } }
    
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
        return request
    }
    
    var description: String {
        "\(format["format"] ?? "no format?") \(format["ext"] ?? "no ext?") \(format["filesize"] ?? "no size?")"
    }
}

class Downloader: NSObject {

    enum Kind: String {
        case complete, videoOnly, audioOnly
        
        var url: URL {
            do {
                return try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                    .appendingPathComponent("video")
                    .appendingPathExtension(self != .audioOnly ? "mp4" : "m4a")
            }
            catch {
                print(error)
                fatalError()
            }
        }
    }
    
    static let shared = Downloader(backgroundURLSessionIdentifier:
//                                    "YD"
        nil
    )
    
    var session: URLSession = URLSession.shared
    
    init(backgroundURLSessionIdentifier: String?) {
        super.init()
        
        var configuration: URLSessionConfiguration
        if let identifier = backgroundURLSessionIdentifier {
            configuration = URLSessionConfiguration.background(withIdentifier: identifier)
        } else {
            configuration = .default
        }

        configuration.networkServiceType = .responsiveAV
        
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }
    
    func download(request: URLRequest, kind: Kind) -> URLSessionDownloadTask {
        do {
            try FileManager.default.removeItem(at: kind.url)
            print(#function, "removed", kind.url.lastPathComponent)
        }
        catch {
            print(#function, error)
        }

        let task = session.downloadTask(with: request)
        task.taskDescription = kind.rawValue
        print(#function, request, trace)
        task.resume()
        return task
    }
    
    struct StreamContext {
        var dec_ctx: UnsafeMutablePointer<AVCodecContext>?
        var enc_ctx: UnsafeMutablePointer<AVCodecContext>?
    }
    
    func open_input_file(filename: String, ifmt_ctx: inout UnsafeMutablePointer<AVFormatContext>?, stream_ctx: inout [StreamContext]) -> Int32 {
        var ret = avformat_open_input(&ifmt_ctx, filename, nil, nil)
        if ret < 0 {
            print("Cannot open input file")
            return ret
        }
        
        ret = avformat_find_stream_info(ifmt_ctx, nil)
        if ret < 0 {
            print("Cannot find stream info")
            return ret
        }
        
        guard let ic = ifmt_ctx?.pointee else {
            return -19730225
        }
        
        stream_ctx = Array(repeating: StreamContext(), count: Int(ic.nb_streams))
        
        for index in 0..<Int(ic.nb_streams) {
            guard let stream = ic.streams[index] else { return -19730225 }
            guard let dec = avcodec_find_decoder(stream.pointee.codecpar.pointee.codec_id) else {
                print("Failed to find decoder for stream #\(index)")
                return -19730225
            }
            guard let codec_ctx = avcodec_alloc_context3(dec) else {
                print("Failed to allocate the decoder context for stream #\(index)")
                return -19730225
            }
            ret = avcodec_parameters_to_context(codec_ctx, stream.pointee.codecpar)
            if ret < 0 {
                print("Failed to copy decoder parameters to input decoder context for stream #\(index)")
                return ret
            }
            if codec_ctx.pointee.codec_type == AVMEDIA_TYPE_VIDEO || codec_ctx.pointee.codec_type == AVMEDIA_TYPE_AUDIO {
                if codec_ctx.pointee.codec_type == AVMEDIA_TYPE_VIDEO {
                    codec_ctx.pointee.framerate = av_guess_frame_rate(ifmt_ctx, stream, nil)
                }
                ret = avcodec_open2(codec_ctx, dec, nil)
                if ret < 0 {
                    print("Failed to open decoder for stream #\(index)")
                    return ret
                }
            }
            stream_ctx[index].dec_ctx = codec_ctx
        }
        
        av_dump_format(ifmt_ctx, 0, filename, 0)
        
        return 0
    }
    
    func open_output_file(filename: String, ifmt_ctx: UnsafePointer<AVFormatContext>, stream_ctx: inout [StreamContext], ofmt_ctx: inout UnsafeMutablePointer<AVFormatContext>?) -> Int32 {
        avformat_alloc_output_context2(&ofmt_ctx, nil, nil, filename)
        guard ofmt_ctx != nil else {
            print("Could not create output context")
            return -19730225
        }
        
        for index in 0..<Int(ifmt_ctx.pointee.nb_streams) {
            guard let out_stream = avformat_new_stream(ofmt_ctx, nil) else {
                print("Failed allocating output stream")
                return -19730225
            }
            
            guard let in_stream = ifmt_ctx.pointee.streams[index],
                  let dec_ctx = stream_ctx[index].dec_ctx else
            {
                return -19730225
            }
            
            if dec_ctx.pointee.codec_type == AVMEDIA_TYPE_VIDEO || dec_ctx.pointee.codec_type == AVMEDIA_TYPE_AUDIO {
                guard let encoder = avcodec_find_encoder(AV_CODEC_ID_H264) else { // FIXME: ...
                    print("Necessary encoder not found")
                    return -19730225
                }
                guard let enc_ctx = avcodec_alloc_context3(encoder) else {
                    print("Failed to allocate the encoder context")
                    return -19730225
                }
                
                if dec_ctx.pointee.codec_type == AVMEDIA_TYPE_VIDEO {
                    enc_ctx.pointee.height = dec_ctx.pointee.height
                    enc_ctx.pointee.width = dec_ctx.pointee.width
                    enc_ctx.pointee.sample_aspect_ratio = dec_ctx.pointee.sample_aspect_ratio
                    enc_ctx.pointee.pix_fmt = encoder.pointee.pix_fmts?.pointee ?? dec_ctx.pointee.pix_fmt
                    enc_ctx.pointee.time_base = av_inv_q(dec_ctx.pointee.framerate)
                } else {
                    enc_ctx.pointee.sample_rate = dec_ctx.pointee.sample_rate
                    enc_ctx.pointee.channel_layout = dec_ctx.pointee.channel_layout
                    enc_ctx.pointee.channels = av_get_channel_layout_nb_channels(enc_ctx.pointee.channel_layout)
                    enc_ctx.pointee.sample_fmt = encoder.pointee.sample_fmts.pointee
                    enc_ctx.pointee.time_base = AVRational(num: 1, den: enc_ctx.pointee.sample_rate)
                }
                
                if (((ofmt_ctx?.pointee.oformat.pointee.flags ?? 0) & AVFMT_GLOBALHEADER) != 0) {
                    enc_ctx.pointee.flags |= AVFMT_GLOBALHEADER
                }
                
                var ret = avcodec_open2(enc_ctx, encoder, nil)
                if ret < 0 {
                    print("Cannot open video encoder for stream #\(index)")
                    return ret
                }
                ret = avcodec_parameters_from_context(out_stream.pointee.codecpar, enc_ctx)
                if ret < 0 {
                    print("Failed to copy encoder parameters to output stream #\(index)")
                    return ret
                }
                
                out_stream.pointee.time_base = enc_ctx.pointee.time_base
                stream_ctx[index].enc_ctx = enc_ctx
            } else if dec_ctx.pointee.codec_type == AVMEDIA_TYPE_UNKNOWN {
                print("Elementary stream #\(index) is of unknown type, cannot proceed")
                return -19730225
            } else {
                let ret = avcodec_parameters_copy(out_stream.pointee.codecpar, in_stream.pointee.codecpar)
                if ret < 0 {
                    print("Copying parameters for stream #\(index) failed")
                    return ret
                }
                out_stream.pointee.time_base = in_stream.pointee.time_base
            }
        }
        av_dump_format(ofmt_ctx, 0, filename, 1)
        
        if (((ofmt_ctx?.pointee.oformat.pointee.flags ?? 0) & AVFMT_NOFILE) == 0) {
            let ret = avio_open(&ofmt_ctx!.pointee.pb, filename, AVIO_FLAG_WRITE)
            if ret < 0 {
                print("Could not open output file '\(filename)'")
                return ret
            }
        }
        
        let ret = avformat_write_header(ofmt_ctx, nil)
        if ret < 0 {
            print("Error occurred when opening output file")
            return ret
        }
        
        return 0
    }
    
    func tryMerge() {
        let videoAsset = AVAsset(url: Kind.videoOnly.url)
        let audioAsset = AVAsset(url: Kind.audioOnly.url)
        
        guard let videoAssetTrack = videoAsset.tracks(withMediaType: .video).first,
              let audioAssetTrack = audioAsset.tracks(withMediaType: .audio).first else {
            print(#function,
                  videoAsset.tracks(withMediaType: .video),
                  audioAsset.tracks(withMediaType: .audio), trace)
            
            var ifmt_ctx: UnsafeMutablePointer<AVFormatContext>?
            var stream_ctx: [StreamContext] = []
            var ret = open_input_file(filename: Kind.videoOnly.url.path, ifmt_ctx: &ifmt_ctx, stream_ctx: &stream_ctx)
            if ret < 0 {
                print(#function, ret)
                return
            }

            var ofmt_ctx: UnsafeMutablePointer<AVFormatContext>?
            let url = Kind.videoOnly.url.deletingLastPathComponent().appendingPathComponent("trans.mp4")
            ret = open_output_file(filename: url.path, ifmt_ctx: ifmt_ctx!, stream_ctx: &stream_ctx, ofmt_ctx: &ofmt_ctx)
            if ret < 0 {
                print(#function, ret)
                return
            }

            var packet = AVPacket()
            
            while true {
                ret = av_read_frame(ifmt_ctx, &packet)
                if ret < 0 {
                    break
                }
                let stream_index = Int(packet.stream_index)
                let type = ifmt_ctx?.pointee.streams[stream_index]?.pointee.codecpar.pointee.codec_type
                
                av_packet_rescale_ts(&packet, ifmt_ctx!.pointee.streams[stream_index]!.pointee.time_base, ofmt_ctx!.pointee.streams[stream_index]!.pointee.time_base)
                ret = av_interleaved_write_frame(ofmt_ctx, &packet)
                if ret < 0 {
                    print(#function, ret)
                    return
                }
                
                av_packet_unref(&packet)
            }

            av_write_trailer(ofmt_ctx)
            
            // FIXME: ...
            
            if (((ofmt_ctx?.pointee.oformat.pointee.flags ?? 0) & AVFMT_NOFILE) == 0) {
                avio_closep(&ofmt_ctx!.pointee.pb)
            }
            
            // FIXME: ...
            
            do {
                try FileManager.default.moveItem(at: Kind.videoOnly.url, to: Kind.videoOnly.url.appendingPathExtension("webm"))
                
                try FileManager.default.moveItem(at: url, to: Kind.videoOnly.url)
                
                tryMerge()
            }
            catch {
                print(#function, error)
            }
            
            return
        }
        
        let composition = AVMutableComposition()
        let videoCompositionTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        let audioCompositionTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        
        do {
            try videoCompositionTrack?.insertTimeRange(CMTimeRange(start: .zero, duration: videoAssetTrack.timeRange.duration), of: videoAssetTrack, at: .zero)
            try audioCompositionTrack?.insertTimeRange(CMTimeRange(start: .zero, duration: audioAssetTrack.timeRange.duration), of: audioAssetTrack, at: .zero)
            print(#function, videoAssetTrack.timeRange, audioAssetTrack.timeRange, trace)
        }
        catch {
            print(#function, error, trace)
            return
        }
        
        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
            print(#function, "unable to init export session", trace)
            return
        }
        let outputURL = Kind.videoOnly.url.deletingLastPathComponent().appendingPathComponent("output.mp4")
        
        try? FileManager.default.removeItem(at: outputURL)
        
        session.outputURL = outputURL
        session.outputFileType = .mp4
        print(#function, "merging...", trace)
        session.exportAsynchronously {
            print(#function, "finished merge", session.status.rawValue, trace)
            if session.status == .completed {
                self.export(outputURL)
            }
        }
    }
}

extension Downloader: URLSessionDelegate {
    func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {
        print(#function, session, error ?? "no error")
    }
    
    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        print(#function, session)
    }
}

extension Downloader: URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        print(#function, session, task, error ?? "no error")
    }
}

extension Downloader: URLSessionDownloadDelegate {
    
    fileprivate func export(_ url: URL) {
        PHPhotoLibrary.shared().performChanges({
            let changeRequest = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            //                            changeRequest.contentEditingOutput = output
        }) { (success, error) in
            print(#function, success, error ?? "", trace)
            
            let content = UNMutableNotificationContent()
            content.body = "Download complete!"
            let request = UNNotificationRequest(identifier: "Download", content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
        }
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        print(#function, session, downloadTask, location)
        
        do {
            let kind = Kind(rawValue: downloadTask.taskDescription ?? "") ?? .complete
            
            try FileManager.default.moveItem(at: location, to: kind.url)
            
            switch kind {
            case .complete:
                export(kind.url)
            case .videoOnly,.audioOnly:
                tryMerge()
            }
        }
        catch {
            print(error)
        }
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
//        print(#function, session, downloadTask, bytesWritten, totalBytesWritten, totalBytesExpectedToWrite)
    }
}

func extractInfo(url: URL, completionHandler: @escaping ([Format], Info?) -> Void) {
    DispatchQueue.global(qos: .userInitiated).async {
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

        completionHandler(formats, Info(info: info))
    }
}

extension NSNotification.Name {
    static let downloadProgress = NSNotification.Name("download progress")
}

let progressKey = "progress"

var def = PyMethodDef()

let progress_hook: PythonObject = {
//    let progress_hook = Python.import("helloworld.app").progress_hook
    
    func progressHook(_: PyObjectPointer?, args: PyObjectPointer?) -> PyObjectPointer? {
        if let args = args {
            let progress = PythonObject(args)[0]
            print(progress["downloaded_bytes"], progress)
            NotificationCenter.default.post(name: .downloadProgress, object: nil, userInfo: [progressKey: progress])
        }
        return _NonePointer
    }
    
    let name = UnsafeRawPointer(StaticString("prog_hook").utf8Start).bindMemory(to: Int8.self, capacity: 1)
    def = PyMethodDef(ml_name: name, ml_meth: progressHook, ml_flags: METH_VARARGS, ml_doc: nil)
    guard let progress_hook = PyCFunction_NewEx(&def, nil, nil) else { fatalError() }
    print(progress_hook)
    return PythonObject(progress_hook)
}()

//@UIApplicationMain
@objc(PythonAppDelegate)
class AppDelegate: NSObject, UIApplicationDelegate {
    var window: UIWindow?
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {

        UNUserNotificationCenter.current().delegate = self
        
        let navigationController = window?.rootViewController as? UINavigationController
        let downloadViewController = navigationController?.topViewController as? DownloadViewController
        
        NotificationCenter.default.addObserver(forName: .downloadProgress, object: nil, queue: .main) {
            guard let progress = $0.userInfo?[progressKey] as? PythonObject else { return }
            downloadViewController?.progressView?.progress = Float(progress["downloaded_bytes"] / progress["total_bytes"]) ?? 0
            
            if progress["status"] == "finished", let path = String(progress["filename"]) {
                let url = URL(fileURLWithPath: path)
                let activityViewController = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                downloadViewController?.present(activityViewController, animated: true, completion: nil)
            }
        }
        
//        if #available(iOS 11.0, *) {
//            download(URL(string:
////                            "https://m.youtube.com/watch?feature=youtu.be&v=fv-6WoaV6oY"
//                        "https://youtu.be/61P3OwsriOM"
//            )!)
//        } else {
//            // Fallback on earlier versions
//        }

        extractInfo(url: URL(string: "https://youtu.be/61P3OwsriOM")!) { formats, info in
            print(info?.formats ?? "no formats?", info ?? "no info?", info?.dict ?? "no dict?")
            DispatchQueue.main.async {
                downloadViewController?.info = info

                downloadViewController?.performSegue(withIdentifier: "formats", sender: nil)
            }
        }
        
        Downloader.shared.tryMerge()
        
//        window?.rootViewController = UIHostingController(rootView: DetailView())
        
        return true
    }
    
    @available(iOS 11.0, *)
    fileprivate func download(_ url: URL) {
        extractInfo(url: url) { formats, info in
            let video = formats.first ?? info?.format
            guard let request = video?.urlRequest, let title = info?.title else { return }
            
            let progress = Progress(totalUnitCount: 100)
            
            let task = Downloader.shared.download(request: request, kind: formats.count > 1 ? .videoOnly : .complete)
            
            progress.addChild(task.progress, withPendingUnitCount: 100)
            
            if formats.count > 1, let request = formats.last?.urlRequest {
                let task = Downloader.shared.download(request: request, kind: .audioOnly)
                print("audio", task)
                
                progress.totalUnitCount = 200
                progress.addChild(task.progress, withPendingUnitCount: 100)
            }
            
            DispatchQueue.main.async {
                let navigationController = self.window?.rootViewController as? UINavigationController
                let downloadViewController = navigationController?.topViewController as? DownloadViewController
                downloadViewController?.progressView.observedProgress =
//                    task.progress
                    progress
                
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound, .announcement, .providesAppNotificationSettings]) { (granted, error) in
                    print(granted, error ?? "no error")
                }
                
                let content = UNMutableNotificationContent()
                content.body = #""\#(title)" 다운로드 시작!"#
                let notificationRequest = UNNotificationRequest(identifier: "Download", content: content, trigger: nil)
                UNUserNotificationCenter.current().add(notificationRequest, withCompletionHandler: nil)
            }
        }
    }
    
    func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        print(userActivity.interaction ?? "no interaction?")
        if #available(iOS 12.0, *) {
            guard let parameter = INParameter(keyPath: \DownloadIntent.url),
                let url = userActivity.interaction?.parameterValue(for: parameter) as? URL else
            {
                fatalError()
            }
            download(url)
        } else {
            // Fallback on earlier versions
        }
        return true
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler(.alert)
    }
}

extension PyObjectPointer {
    init<T>(_ pointer: UnsafeMutablePointer<T>) {
        self = PyObjectPointer(OpaquePointer(pointer))
    }
}
