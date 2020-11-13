//
//  AppDelegate.swift
//  Hello World
//
//  Created by 안창범 on 2020/04/20.
//  Copyright © 2020 Jane Developer. All rights reserved.
//

import UIKit
import Intents
import SwiftUI
import VideoToolbox
import YoutubeDL

let trace = "trace"

//@UIApplicationMain
@objc(PythonAppDelegate)
class AppDelegate: NSObject, UIApplicationDelegate {
    var window: UIWindow?
    
    var downloadViewController: DownloadViewController? {
        let navigationController = window?.rootViewController as? UINavigationController
        return navigationController?.topViewController as? DownloadViewController
    }
    
    let youtubeDL = try! YoutubeDL()
    
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

    func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        print(userActivity.interaction ?? "no interaction?")
        if #available(iOS 12.0, *) {
            guard let parameter = INParameter(keyPath: \DownloadIntent.url),
                let url = userActivity.interaction?.parameterValue(for: parameter) as? URL else
            {
                fatalError()
            }
            
            downloadViewController?.url = url
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

func notify(body: String, identifier: String = "Download") {
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound, .providesAppNotificationSettings]) { (granted, error) in
        print(#function, "granted =", granted, error ?? "no error")
        guard granted else {
            return
        }
        
        let content = UNMutableNotificationContent()
        content.body = body
        let notificationRequest = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(notificationRequest, withCompletionHandler: nil)
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler(.alert)
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        print(#function, response.actionIdentifier)
        if response.actionIdentifier == UNNotificationDefaultActionIdentifier && response.notification.request.identifier == NotificationRequestIdentifier.transcode.rawValue {
            DispatchQueue.global(qos: .userInitiated).async {
                Downloader.shared.transcode()
            }
        }
        completionHandler()
    }
}
