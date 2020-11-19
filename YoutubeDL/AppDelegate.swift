//
//  AppDelegate.swift
//
//  Copyright (c) 2020 Changbeom Ahn
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

import UIKit
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
        
        SetPythonHome()
        
        _ = Downloader.shared // create URL session
        
        downloadViewController?.url = URL(string: "https://youtu.be/CM4CkVFmTds")
        
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
