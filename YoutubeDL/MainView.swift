//
//  MainView.swift
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

import SwiftUI

@available(iOS 13.0.0, *)
struct MainView: View {
    @State var alertMessage: String?
    
    @State var isShowingAlert = false
    
    @State var url: URL?
    
    var body: some View {
        List {
            if url != nil {
                Text(url?.absoluteString ?? "nil?")
            }
            
            Button("Paste URL") {
                let pasteBoard = UIPasteboard.general
//                guard pasteBoard.hasURLs || pasteBoard.hasStrings else {
//                    alert(message: "Nothing to paste")
//                    return
//                }
                // FIXME: paste
                guard let url = pasteBoard.url ?? pasteBoard.string.flatMap({ URL(string: $0) }) else {
                    alert(message: "Nothing to paste")
                    return
                }
                self.url = url
            }
            .alert(isPresented: $isShowingAlert) {
                Alert(title: Text(alertMessage ?? "no message?"))
            }
            
            Text(" or ")
            Button(#"Prepend "y" to URL in Safari"#) {
                // FIXME: open Safari
                open(url: URL(string: "https://youtube.com")!)
            }
            Text(" or ")
            Button("Download shortcut") {
                // FIXME: open Shortcuts
                open(url: URL(string: "https://www.icloud.com/shortcuts/e226114f6e6c4440b9c466d1ebe8fbfc")!)
            }

            if #available(iOS 14.0, *) {
                ProgressView()
            } else {
                // Fallback on earlier versions
            }
        }
    }
    
    func open(url: URL) {
        UIApplication.shared.open(url, options: [:]) {
            if !$0 {
                alert(message: "Failed to open \(url)")
            }
        }
    }
    
    func alert(message: String) {
        alertMessage = message
        isShowingAlert = true
    }
}

@available(iOS 13.0.0, *)
struct MainView_Previews: PreviewProvider {
    static var previews: some View {
        MainView()
    }
}
