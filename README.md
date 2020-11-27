# YoutubeDL

This iOS app uses youtube-dl python module to download videos from YouTube.

- Screen shots
![Screen shot 1](/Images/Screen%20Shot%201.png)
![Screen shot 2](/Images/Screen%20Shot%202.png)
![Screen shot 3](/Images/Screen%20Shot%203.png)
![Screen shot 4](/Images/Screen%20Shot%204.png)

- Video
[![Watch the video](https://img.youtube.com/vi/WdFj7fUnmC0/hqdefault.jpg)](https://youtu.be/WdFj7fUnmC0)

## Warning

This app is NOT AppStore-safe.  Historically AppStore has been removing apps downloading videos from YouTube.  This app will likely be rejected by AppStore.

## Features

- Automatically downloads youtube-dl python module from https://yt-dl..org
- Download media using URLSession
- Support background download
- Support chunk based download
- Transcode using embedded FFmpeg libraries

## Usage

Run this app in a simulator.

To run on a device:
- Change code sign identity
- Change bundle ID

## Swift Packages

- https://github.com/kewlbear/Python-iOS
- https://github.com/kewlbear/FFmpeg-iOS
- https://github.com/kewlbear/YoutubeDL-iOS

## TODO

- Improve UI/UX
- Improve modularization
- Documentation

## License

MIT
