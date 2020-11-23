# YoutubeDL

This iOS app uses youtube-dl python module to download videos from YouTube.

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
