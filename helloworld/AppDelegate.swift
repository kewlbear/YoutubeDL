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
    static let shared = Downloader()
    
    func download(request: URLRequest) -> URLSessionDownloadTask {
        let configuration = URLSessionConfiguration.background(withIdentifier: "y")
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        let task = session.downloadTask(with: request)
        task.resume()
        return task
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
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        print(#function, session, downloadTask, location)
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        print(#function, session, downloadTask, bytesWritten, totalBytesWritten, totalBytesExpectedToWrite)
    }
}

func extractInfo(url: URL, completionHandler: @escaping (Info?) -> Void) {
    DispatchQueue.global(qos: .userInitiated).async {
        let youtube_dl = Python.import("youtube_dl")
        
        let options: PythonObject = [
            "format": "best[ext=mp4]",
            //        "outtmpl": location.path.pythonObject,
            //        "progress_hooks": [progress_hook],
            //        "nooverwrites": false,
            "nocheckcertificate": true,
        ]
        
        let youtubeDL = youtube_dl.YoutubeDL(options)
        
        let info = youtubeDL.extract_info(url.absoluteString, download: false, process: true)
        completionHandler(Info(info: info))
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
        
        return true
    }
    
    func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        print(userActivity.interaction)
        if #available(iOS 12.0, *) {
            guard let parameter = INParameter(keyPath: \DownloadIntent.url),
                let url = userActivity.interaction?.parameterValue(for: parameter) as? URL else
            {
                fatalError()
            }
            extractInfo(url: url) { info in
                guard let request = info?.format?.urlRequest else { return }
                let task = Downloader.shared.download(request: request)
                DispatchQueue.main.async {
                    let navigationController = self.window?.rootViewController as? UINavigationController
                    let downloadViewController = navigationController?.topViewController as? DownloadViewController
                    downloadViewController?.progressView.observedProgress = task.progress
                }
            }
        } else {
            // Fallback on earlier versions
        }
        return true
    }
}


extension PyObjectPointer {
    init<T>(_ pointer: UnsafeMutablePointer<T>) {
        self = PyObjectPointer(OpaquePointer(pointer))
    }
}
