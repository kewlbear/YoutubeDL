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
        return request
    }
    
    var height: Int? { format["height"].flatMap { Int($0) } }
    
    var isAudioOnly: Bool { self.vcodec == "none" }
    
    var isVideoOnly: Bool { self.acodec == "none" }
    
    var description: String {
        "\(format["format"] ?? "no format?") \(format["ext"] ?? "no ext?") \(format["filesize"] ?? "no size?")"
    }
    
    subscript(dynamicMember key: String) -> String? {
        format[key].flatMap { String($0) }
    }
}

class Downloader: NSObject {

    enum Kind: String {
        case complete, videoOnly, audioOnly, otherVideo
        
        var url: URL {
            do {
                return try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                    .appendingPathComponent("video")
                    .appendingPathExtension(self != .audioOnly
                                                ? (self == .otherVideo ? "webm" : "mp4")
                                                : "m4a")
            }
            catch {
                print(error)
                fatalError()
            }
        }
    }
    
    static let shared = Downloader(backgroundURLSessionIdentifier:
                                    "YD"
//                                    nil
    )
    
    var session: URLSession = URLSession.shared
    
    let decimalFormatter = NumberFormatter()
    
    let percentFormatter = NumberFormatter()
    
    var t = ProcessInfo.processInfo.systemUptime
    
    var topViewController: UIViewController? {
        (UIApplication.shared.keyWindow?.rootViewController as? UINavigationController)?.topViewController
    }
    
    init(backgroundURLSessionIdentifier: String?) {
        super.init()
        
        decimalFormatter.numberStyle = .decimal
        percentFormatter.numberStyle = .percent
        
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
        return task
    }
    
    func tryMerge() {
        let videoAsset = AVAsset(url: Kind.videoOnly.url)
        let audioAsset = AVAsset(url: Kind.audioOnly.url)
        
        guard let videoAssetTrack = videoAsset.tracks(withMediaType: .video).first,
              let audioAssetTrack = audioAsset.tracks(withMediaType: .audio).first else {
            print(#function,
                  videoAsset.tracks(withMediaType: .video),
                  audioAsset.tracks(withMediaType: .audio), trace)
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
    
    func transcode() {
        do {
            try FileManager.default.removeItem(at: Kind.videoOnly.url)
            
            Transcoder().transcode(from: Kind.otherVideo.url, to: Kind.videoOnly.url)
            
            tryMerge()
        }
        catch {
            print(#function, error)
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
            
            self.topViewController?.notify(body: "Download complete!")
        }
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        print(#function, session, downloadTask, location)
        
        session.getTasksWithCompletionHandler { (_, _, tasks) in
            print(#function, tasks)
            tasks.first { $0.state == .suspended }?.resume()
        }
        
        do {
            let kind = Kind(rawValue: downloadTask.taskDescription ?? "") ?? .complete
            
            try FileManager.default.moveItem(at: location, to: kind.url)
            
            switch kind {
            case .complete:
                export(kind.url)
            case .videoOnly, .audioOnly:
                tryMerge()
            case .otherVideo:
                transcode()
            }
        }
        catch {
            print(error)
        }
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let t = ProcessInfo.processInfo.systemUptime
        guard t - self.t > 0.1 else {
            return
        }
        self.t = t
        
        print(
//            #function,
//              session,
              downloadTask.taskIdentifier, bytesWritten, totalBytesWritten, totalBytesExpectedToWrite)
        DispatchQueue.main.async {
            self.topViewController?.navigationItem.title = self.percentFormatter.string(from: NSNumber(value: Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)))
        }
    }
}

class Transcoder {
    struct StreamContext {
        var dec_ctx: UnsafeMutablePointer<AVCodecContext>?
        var enc_ctx: UnsafeMutablePointer<AVCodecContext>?
    }
    
    var ifmt_ctx: UnsafeMutablePointer<AVFormatContext>?
    
    var ofmt_ctx: UnsafeMutablePointer<AVFormatContext>?

    var stream_ctx: [StreamContext] = []

    func open_input_file(filename: String) -> Int32 {
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
    
    func open_output_file(filename: String) -> Int32 {
        avformat_alloc_output_context2(&ofmt_ctx, nil, nil, filename)
        guard ofmt_ctx != nil else {
            print("Could not create output context")
            return -19730225
        }
        
        for index in 0..<Int(ifmt_ctx!.pointee.nb_streams) {
            guard let out_stream = avformat_new_stream(ofmt_ctx, nil) else {
                print("Failed allocating output stream")
                return -19730225
            }
            
            guard let in_stream = ifmt_ctx!.pointee.streams[index],
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
                    enc_ctx.pointee.pix_fmt =
//                        encoder.pointee.pix_fmts?.pointee ??
                        dec_ctx.pointee.pix_fmt
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
    
    func encode_write_frame(filt_frame: inout UnsafeMutablePointer<AVFrame>?, stream_index: Int) -> Int32 {
        var enc_pkt = AVPacket()
        av_init_packet(&enc_pkt)
        var got_frame: Int32 = 0
        let ret = avcodec_encode_video2(stream_ctx[stream_index].enc_ctx, &enc_pkt, filt_frame, &got_frame)
        av_frame_free(&filt_frame)
        if ret < 0 {
            return ret
        }
        if got_frame == 0 {
            return 0
        }
        
        enc_pkt.stream_index = Int32(stream_index)
        av_packet_rescale_ts(&enc_pkt, stream_ctx[stream_index].enc_ctx!.pointee.time_base, ofmt_ctx!.pointee.streams[stream_index]!.pointee.time_base)
        
        return av_interleaved_write_frame(ofmt_ctx, &enc_pkt)
    }
    
    func transcode(from: URL, to url: URL) {
        var ret = open_input_file(filename: from.path)
        if ret < 0 {
            return
        }

        ret = open_output_file(filename: url.path)
        if ret < 0 {
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
            
            var frame = av_frame_alloc()
            guard frame != nil else {
                return
            }
            av_packet_rescale_ts(&packet, ifmt_ctx!.pointee.streams[stream_index]!.pointee.time_base, stream_ctx[stream_index].dec_ctx!.pointee.time_base)
            let dec_func = type == AVMEDIA_TYPE_VIDEO ? avcodec_decode_video2 : avcodec_decode_audio4
            var got_frame: Int32 = 0
            ret = dec_func(stream_ctx[stream_index].dec_ctx, frame!, &got_frame, &packet)
            if ret < 0 {
                av_frame_free(&frame)
                print("Decoding failed")
                return
            }
            
            if got_frame != 0 {
                frame?.pointee.pts = frame!.pointee.best_effort_timestamp
                ret = encode_write_frame(filt_frame: &frame, stream_index: stream_index)
                av_frame_free(&frame)
                if ret < 0 {
                    return
                }
            } else {
                av_frame_free(&frame)
            }
            av_packet_unref(&packet)
        }

        av_write_trailer(ofmt_ctx)
        if (((ofmt_ctx?.pointee.oformat.pointee.flags ?? 0) & AVFMT_NOFILE) == 0) {
            avio_closep(&ofmt_ctx!.pointee.pb)
        }
    }
}

class YoutubeDL {
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
}

//@UIApplicationMain
@objc(PythonAppDelegate)
class AppDelegate: NSObject, UIApplicationDelegate {
    var window: UIWindow?
    
    var downloadViewController: DownloadViewController? {
        let navigationController = window?.rootViewController as? UINavigationController
        return navigationController?.topViewController as? DownloadViewController
    }
    
    let youtubeDL = YoutubeDL()
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {

        UNUserNotificationCenter.current().delegate = self
        
        if #available(iOS 11.0, *) {
            download(URL(string:
//                            "https://m.youtube.com/watch?feature=youtu.be&v=fv-6WoaV6oY"
//                        "https://youtu.be/61P3OwsriOM"
                         "https://youtu.be/61P3OwsriOM"
            )!)
        } else {
            // Fallback on earlier versions
        }

//        window?.rootViewController = UIHostingController(rootView: DetailView())
        
        return true
    }
    
    func check(formats: [Format]) {
        let _bestAudio = formats.filter { $0.isAudioOnly && $0.ext == "m4a" }.last
        let _bestVideo = formats.filter { $0.isVideoOnly }.last
        let _best = formats.filter { !$0.isVideoOnly && !$0.isAudioOnly && $0.ext == "mp4" }.last
        print(_best ?? "no best?", _bestVideo ?? "no bestvideo?", _bestAudio ?? "no bestaudio?")
        guard let best = _best, let bestVideo = _bestVideo, let bestAudio = _bestAudio,
              let bestHeight = best.height, let bestVideoHeight = bestVideo.height,
              bestVideoHeight > bestHeight else
        {
            if let best = _best {
                download(format: best, start: true)
            } else if let bestVideo = _bestVideo, let bestAudio = _bestAudio {
                download(format: bestVideo, start: true)
                download(format: bestAudio, start: false)
            } else {
                downloadViewController?.performSegue(withIdentifier: "formats", sender: nil)
            }
            return
        }
        
        let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "Video+Audio.mp4 (\(bestHeight)p)", style: .default, handler: { _ in
            self.download(format: best, start: true)
        }))
        alert.addAction(UIAlertAction(title: "Video.\(bestVideo.ext ?? "?") + Audio.m4a (\(bestVideoHeight)p)", style: .default, handler: { _ in
            self.download(format: bestVideo, start: true)
            self.download(format: bestAudio, start: false)
        }))
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        window?.rootViewController?.present(alert, animated: true, completion: nil)
    }
    
    func download(format: Format, start: Bool) {
        guard let request = format.urlRequest else { fatalError() }
        let task = Downloader.shared.download(request: request, kind: format.isVideoOnly
                                                ? (format.ext == "mp4" ? .videoOnly : .otherVideo)
                                                : (format.isAudioOnly ? .audioOnly : .complete))
        if start {
            task.resume()
        }
    }
    
    @available(iOS 11.0, *)
    fileprivate func download(_ url: URL) {
        downloadViewController?.navigationItem.title = url.absoluteString
        
        Downloader.shared.session.getAllTasks {
            for task in $0 {
                task.cancel()
            }
        }
        
        youtubeDL.extractInfo(url: url) { formats, info in
            self.check(formats: info?.formats ?? [])
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

extension UIViewController {
    func notify(body: String) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound, .announcement, .providesAppNotificationSettings]) { (granted, error) in
            print(granted, error ?? "no error")
            guard granted else {
                return
            }
            
            let content = UNMutableNotificationContent()
            content.body = body
            let notificationRequest = UNNotificationRequest(identifier: "Download", content: content, trigger: nil)
            UNUserNotificationCenter.current().add(notificationRequest, withCompletionHandler: nil)
        }
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
