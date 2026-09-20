import Foundation
import XCTest
@testable import Harbor

final class PartialDownloadImportServiceTests: XCTestCase {
    func testProbeRequiresRangeSupportAndValidator() throws {
        let response = HTTPURLResponse(
            url: URL(string: "https://example.com/file.zip")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: [
                "Accept-Ranges": "bytes",
                "Content-Length": "1000",
                "ETag": "\"version-1\""
            ]
        )!

        let probe = try PartialDownloadImportService.makeProbe(
            from: response,
            requireRangeSupport: true
        )

        XCTAssertEqual(probe.expectedBytes, 1000)
        XCTAssertEqual(probe.entityTag, "\"version-1\"")
    }

    func testProbeRejectsMissingValidator() {
        let response = HTTPURLResponse(
            url: URL(string: "https://example.com/file.zip")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: [
                "Accept-Ranges": "bytes",
                "Content-Length": "1000"
            ]
        )!

        XCTAssertThrowsError(
            try PartialDownloadImportService.makeProbe(
                from: response,
                requireRangeSupport: true
            )
        ) { error in
            XCTAssertEqual(error as? PartialDownloadImportError, .missingValidator)
        }
    }
}
