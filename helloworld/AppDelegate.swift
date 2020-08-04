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

let trace = "trace"

struct Info {
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
}

struct Format {
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
    
    static let shared = Downloader()
    
    func download(request: URLRequest, kind: Kind) -> URLSessionDownloadTask {
        do {
            try FileManager.default.removeItem(at: kind.url)
            print(#function, "removed", kind.url.lastPathComponent)
        }
        catch {
            print(#function, error)
        }

        let configuration = URLSessionConfiguration.background(withIdentifier: "y")
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        let task = session.downloadTask(with: request)
        task.taskDescription = kind.rawValue
        print(#function, request, trace)
        task.resume()
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
            "format": "bestvideo[ext=mp4],bestaudio[ext=m4a]",
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
        
//        do {
//            let location = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
//                .appendingPathComponent("video")
//                .appendingPathExtension("mp4")
//
//            try download(url: URL(fileURLWithPath: ""), to: location)
//        }
//        catch {
//            print(error)
//        }
        
//        if #available(iOS 11.0, *) {
//            download(URL(string:
////                            "https://m.youtube.com/watch?feature=youtu.be&v=fv-6WoaV6oY"
//                        "https://youtu.be/QBT5mDJF4E8"
//            )!)
//        } else {
//            // Fallback on earlier versions
//        }
        
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
                
                if #available(iOS 13.0, *) {
                    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound, .announcement, .providesAppNotificationSettings]) { (granted, error) in
                        print(granted, error)
                    }
                } else {
                    // Fallback on earlier versions
                }
                
                let content = UNMutableNotificationContent()
                content.body = #""\#(title)" 다운로드 시작!"#
                let notificationRequest = UNNotificationRequest(identifier: "Download", content: content, trigger: nil)
                UNUserNotificationCenter.current().add(notificationRequest, withCompletionHandler: nil)
            }
        }
    }
    
    func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        print(userActivity.interaction)
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
