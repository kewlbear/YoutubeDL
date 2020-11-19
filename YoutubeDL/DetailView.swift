//
//  DetailView.swift
//  YD
//
//  Created by 안창범 on 2020/08/05.
//  Copyright © 2020 Jane Developer. All rights reserved.
//

import SwiftUI

@available(iOS 13.0, *)
struct DetailView: View {
    @State var progress = 0.7
    
    @State var tasks = [
        "Downloading video-only",
        "Downloading audio-only",
    ]
    
    var body: some View {
        VStack {
            if #available(iOS 14.0, *) {
                ProgressView(value: progress)
                    .padding()
            } else {
                // Fallback on earlier versions
            }
            
            ForEach(tasks, id: \.self) { item in
                Text(item)
            }
            
            Button(action: {
                
            }) {
                Image(systemName: "stop")
            }
            .padding()
        }
    }
}

@available(iOS 13.0.0, *)
struct DetailView_Previews: PreviewProvider {
    static var previews: some View {
        DetailView()
    }
}
