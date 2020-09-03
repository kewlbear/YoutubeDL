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
import SwiftUI
import VideoToolbox

let trace = "trace"

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
        
        _ = Downloader.shared // create URL session
        
//        if #available(iOS 11.0, *) {
//            download(URL(string:
////                            "https://m.youtube.com/watch?feature=youtu.be&v=fv-6WoaV6oY"
////                        "https://youtu.be/61P3OwsriOM"
//                         "https://youtu.be/61P3OwsriOM"
//            )!)
//        } else {
//            // Fallback on earlier versions
//        }

//        window?.rootViewController = UIHostingController(rootView: DetailView())
        
        testVP9()
        
        return true
    }
    
    func testVP9() {
        var _formatDescription: CMVideoFormatDescription?
        var status = CMVideoFormatDescriptionCreate(allocator: nil, codecType: kCMVideoCodecType_VP9, width: 320, height: 240, extensions: nil, formatDescriptionOut: &_formatDescription)
        guard status == noErr, let formatDescription = _formatDescription else {
            print(#function, "CMVideoFormatDescriptionCreate =", status)
            return
        }

        var _decompressionSession: VTDecompressionSession?
        status = VTDecompressionSessionCreate(allocator: nil, formatDescription: formatDescription, decoderSpecification: nil, imageBufferAttributes: nil, outputCallback: nil, decompressionSessionOut: &_decompressionSession)
//        assert(status != kVTCouldNotFindVideoDecoderErr)
        guard status == noErr, let decompressionSession = _decompressionSession else {
            print(#function, "VTDecompressionSessionCreate =", status)
            return
        }
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
                notify(body: #""\#(best.title ?? "No title?")" 다운로드 시작"#)
                download(format: best, start: true)
            } else if let bestVideo = _bestVideo, let bestAudio = _bestAudio {
                download(format: bestVideo, start: true)
                download(format: bestAudio, start: false)
            } else {
                DispatchQueue.main.async {
                    self.downloadViewController?.performSegue(withIdentifier: "formats", sender: nil)
                }
            }
            return
        }
        
        DispatchQueue.main.async {
            let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
            alert.addAction(UIAlertAction(title: "Video+Audio.mp4 (\(bestHeight)p)", style: .default, handler: { _ in
                self.download(format: best, start: true)
            }))
            alert.addAction(UIAlertAction(title: "Video.\(bestVideo.ext ?? "?") + Audio.m4a (\(bestVideoHeight)p)", style: .default, handler: { _ in
                self.download(format: bestVideo, start: true)
                self.download(format: bestAudio, start: false)
            }))
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
            self.window?.rootViewController?.present(alert, animated: true, completion: nil)
        }
    }
    
    func download(format: Format, start: Bool) {
        guard let request = format.urlRequest else { fatalError() }
        let task = Downloader.shared.download(request: request, kind: format.isVideoOnly
                                                ? (format.ext == "mp4" ? .videoOnly : .otherVideo)
                                                : (format.isAudioOnly ? .audioOnly : .complete))
        if start {
            Downloader.shared.t0 = ProcessInfo.processInfo.systemUptime
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
    
    func applicationDidEnterBackground(_ application: UIApplication) {
        if Downloader.shared.transcoder != nil {
            notify(body: "트랜스코딩이 중딘되었습니다. 앱으로 전환하고 트랜스코딩을 다시 하세요.")
        }
    }
}

func notify(body: String) {
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound, .providesAppNotificationSettings]) { (granted, error) in
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

extension AppDelegate: UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler(.alert)
    }
}
