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
import Resources

let trace = "trace"

@UIApplicationMain
class AppDelegate: NSObject, UIApplicationDelegate {
    var window: UIWindow?
    
    var downloadViewController: DownloadViewController? {
        let navigationController = window?.rootViewController as? UINavigationController
        return navigationController?.topViewController as? DownloadViewController
    }
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {

        UNUserNotificationCenter.current().delegate = self
        
        Init()
        
        _ = Downloader.shared // create URL session
        
        downloadViewController?.url = URL(string: "https://youtu.be/CM4CkVFmTds")
        
        return true
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
