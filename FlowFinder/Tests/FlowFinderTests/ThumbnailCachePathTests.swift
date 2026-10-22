import XCTest
@testable import FlowFinder

final class ThumbnailCachePathTests: XCTestCase {

    func testDiskFilenameNeverContainsPathSeparators() {
        let key = "/Users/me/Pictures/a:b?.png_64x64"
        let name = ThumbnailManager.diskCacheFilename(for: key)
        XCTAssertFalse(name.contains("/"))
        XCTAssertFalse(name.contains(":"))
        XCTAssertTrue(name.hasSuffix(".png"))
    }

    func testDiskFilenameIsDeterministicAndKeySpecific() {
        let a = ThumbnailManager.diskCacheFilename(for: "/a_64x64")
        let b = ThumbnailManager.diskCacheFilename(for: "/b_64x64")
        XCTAssertEqual(a, ThumbnailManager.diskCacheFilename(for: "/a_64x64"))
        XCTAssertNotEqual(a, b)
    }
}
