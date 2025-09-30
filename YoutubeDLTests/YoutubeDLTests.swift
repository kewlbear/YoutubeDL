import XCTest
@testable import YoutubeDL

final class YoutubeDLTests: XCTestCase {
    func testSecondsFromHMSString() {
        XCTAssertEqual(secondsFromHMSString(""), nil)
        XCTAssertEqual(secondsFromHMSString("1"), 1)
        XCTAssertEqual(secondsFromHMSString("03"), 3)
        XCTAssertEqual(secondsFromHMSString("3:21"), 201)
        XCTAssertEqual(secondsFromHMSString("5:43:21"), (5 * 60 + 43) * 60 + 21)
        XCTAssertNil(secondsFromHMSString("4:3:2:1"))
        XCTAssertNil(secondsFromHMSString("abc"))
    }

    func testFormatSecondsToHMS() {
        XCTAssertEqual(formatSecondsToHMS(0), "0:00")
        XCTAssertEqual(formatSecondsToHMS(59), "0:59")
        XCTAssertEqual(formatSecondsToHMS(61), "1:01")
        XCTAssertEqual(formatSecondsToHMS(3601), "1:00:01")
        XCTAssertEqual(formatSecondsToHMS(15_321), "4:15:21")
        XCTAssertEqual(formatSecondsToHMS(-1), "0:00")
    }

    func testYTDLPArgumentsRespectToggles() {
        let sampleURL = URL(string: "https://example.com/video")!
        let baseConfiguration = YTDLPConfiguration(
            kind: .video,
            videoQuality: .p1080,
            container: .mp4,
            audioFormat: .m4a,
            transcode: .h264_fast,
            videoCRF: nil,
            videoBitrateKbps: nil,
            audioBitrateKbps: nil,
            enableTranscoding: true,
            enableChunkedDownload: true,
            supportedFormatsOnly: true
        )

        let service = YTDLPService()
        let enabledArgs = service.buildArguments(for: sampleURL, configuration: baseConfiguration)
        XCTAssertTrue(enabledArgs.contains("--postprocessor-args"))
        XCTAssertTrue(enabledArgs.contains("--concurrent-fragments"))
        XCTAssertTrue(enabledArgs.contains("5"))

        var disabled = baseConfiguration
        disabled.enableTranscoding = false
        disabled.enableChunkedDownload = false
        let disabledArgs = service.buildArguments(for: sampleURL, configuration: disabled)
        XCTAssertFalse(disabledArgs.contains("--postprocessor-args"))
        XCTAssertTrue(disabledArgs.contains("--concurrent-fragments"))
        if let fragmentsIndex = disabledArgs.firstIndex(of: "--concurrent-fragments") {
            XCTAssertEqual(disabledArgs[disabledArgs.index(after: fragmentsIndex)], "1")
        } else {
            XCTFail("Missing fragment argument")
        }
    }
}
