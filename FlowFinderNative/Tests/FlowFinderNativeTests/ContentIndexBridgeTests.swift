import XCTest
@testable import FlowFinderNative

/// Wave2 T7 — Content index bridge / FFI contract tests.
///
/// NOTE: The Swift test target is not yet wired into `Package.swift` or the
/// Xcode target (T11 wires project membership). These tests validate the
/// Swift-side ABI contract (enum raw values vs `ff_ffi.h` #defines) and the
/// stats JSON decoding — no Rust build is required to run them once T11 adds
/// the file to the test target.
final class ContentIndexBridgeTests: XCTestCase {

    // MARK: - Status / mode enum raw values (must match ff_ffi.h #defines)

    func testContentIndexStatusRawValuesMatchCConstants() {
        XCTAssertEqual(ContentIndexStatus.empty.rawValue, 0)
        XCTAssertEqual(ContentIndexStatus.indexing.rawValue, 1)
        XCTAssertEqual(ContentIndexStatus.ready.rawValue, 2)
        XCTAssertEqual(ContentIndexStatus.error.rawValue, 3)
        XCTAssertEqual(ContentIndexStatus.cancelled.rawValue, 4)
        XCTAssertEqual(ContentIndexStatus.unavailable.rawValue, 5)
    }

    func testContentIndexModeRawValuesMatchCConstants() {
        XCTAssertEqual(ContentIndexMode.incremental.rawValue, 0)
        XCTAssertEqual(ContentIndexMode.rebuild.rawValue, 1)
    }

    func testContentIndexStatusFromRawValue() {
        XCTAssertEqual(ContentIndexStatus(rawValue: 2), .ready)
        XCTAssertNil(ContentIndexStatus(rawValue: 99))
    }

    // MARK: - Stats JSON decoding

    func testContentIndexStatsDecodeFullJSON() {
        let json = """
        {"status":1,"paused":false,"document_count":1234,"total_candidates":90000,
         "processed":5678,"checkpoint_path":"/Users/x/docs/z.md",
         "last_build_at":1755120000,"root_path":"/Users/x"}
        """
        let stats = ContentIndexStats(json: json)
        XCTAssertNotNil(stats)
        XCTAssertEqual(stats?.status, .indexing)
        XCTAssertEqual(stats?.paused, false)
        XCTAssertEqual(stats?.documentCount, 1234)
        XCTAssertEqual(stats?.totalCandidates, 90000)
        XCTAssertEqual(stats?.processed, 5678)
        XCTAssertEqual(stats?.checkpointPath, "/Users/x/docs/z.md")
        XCTAssertEqual(stats?.lastBuildAt, 1755120000)
        XCTAssertEqual(stats?.rootPath, "/Users/x")
        XCTAssertNil(stats?.error)
    }

    func testContentIndexStatsDecodeNullOptionals() {
        let json = """
        {"status":0,"paused":false,"document_count":0,"total_candidates":0,
         "processed":0,"checkpoint_path":null,"last_build_at":null,"root_path":null}
        """
        let stats = ContentIndexStats(json: json)
        XCTAssertEqual(stats?.status, .empty)
        XCTAssertNil(stats?.checkpointPath)
        XCTAssertNil(stats?.lastBuildAt)
        XCTAssertNil(stats?.rootPath)
    }

    func testContentIndexStatsDecodeErrorField() {
        let json = #"{"status":3,"paused":false,"document_count":0,"total_candidates":0,"processed":0,"checkpoint_path":null,"last_build_at":null,"root_path":null,"error":"io: permission denied"}"#
        let stats = ContentIndexStats(json: json)
        XCTAssertEqual(stats?.status, .error)
        XCTAssertEqual(stats?.error, "io: permission denied")
    }

    func testContentIndexStatsDecodeMalformedJSONReturnsNil() {
        XCTAssertNil(ContentIndexStats(json: "not-json"))
        XCTAssertNil(ContentIndexStats(json: #"{"status":99}"#))
        XCTAssertNil(ContentIndexStats(json: ""))
    }

    // MARK: - Bridge singleton

    func testContentIndexBridgeSingleton() {
        let a = ContentIndexBridge.shared
        let b = ContentIndexBridge.shared
        XCTAssertTrue(a === b)
    }
}
