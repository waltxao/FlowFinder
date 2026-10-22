import AppKit
import XCTest
@testable import FlowFinder

private final class FFMockMetadataProvider: FFMetadataProviding {
    var requests: [(String, (Result<FFFileMetadata, Error>) -> Void, UUID)] = []
    var cancelled: [UUID] = []

    func load(path: String,
              completion: @escaping (Result<FFFileMetadata, Error>) -> Void) -> UUID {
        let id = UUID()
        requests.append((path, completion, id))
        return id
    }

    func cancel(_ token: UUID) {
        cancelled.append(token)
    }
}

final class FFMetadataServiceTests: XCTestCase {

    private func meta(_ path: String) -> FFFileMetadata {
        FFFileMetadata(path: path, kind: "文件", size: 1)
    }

    func testOldResultIsDroppedAfterNewRequest() {
        let provider = FFMockMetadataProvider()
        let service = FFMetadataService(provider: provider)
        var got: [String] = []
        let done = expectation(description: "new result")
        service.load(path: "/a") { result in
            if case .success(let meta) = result { got.append(meta.path) }
        }
        service.load(path: "/b") { result in
            if case .success(let meta) = result { got.append(meta.path) }
            done.fulfill()
        }
        provider.requests[0].1(.success(meta("/a")))
        provider.requests[1].1(.success(meta("/b")))
        wait(for: [done], timeout: 1)
        XCTAssertEqual(got, ["/b"])
    }

    func testCancelDropsPendingResult() {
        let provider = FFMockMetadataProvider()
        let service = FFMetadataService(provider: provider)
        var got: [String] = []
        let token = service.load(path: "/a") { result in
            if case .success(let meta) = result { got.append(meta.path) }
        }
        service.cancel(token)
        provider.requests[0].1(.success(meta("/a")))
        let idle = expectation(description: "runloop")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { idle.fulfill() }
        wait(for: [idle], timeout: 1)
        XCTAssertTrue(got.isEmpty)
        XCTAssertEqual(provider.cancelled.count, 1)
    }

    func testFailureIsForwardedToLatestRequest() {
        let provider = FFMockMetadataProvider()
        let service = FFMetadataService(provider: provider)
        let done = expectation(description: "failure")
        service.load(path: "/a") { result in
            if case .failure = result { done.fulfill() }
        }
        provider.requests[0].1(.failure(NSError(domain: "test", code: 1)))
        wait(for: [done], timeout: 1)
    }

    func testDefaultProviderReadsFileAttributesOffMainThread() {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("note.txt")
        try? "hello flowfinder".data(using: .utf8)?.write(to: file)

        let service = FFMetadataService()
        let done = expectation(description: "metadata")
        service.load(path: file.path) { result in
            switch result {
            case .success(let meta):
                XCTAssertEqual(meta.path, file.path)
                XCTAssertEqual(meta.kind, "TXT 文件")
                XCTAssertGreaterThan(meta.size, 0)
                XCTAssertNotNil(meta.modified)
            case .failure(let error):
                XCTFail("unexpected failure: \(error)")
            }
            done.fulfill()
        }
        wait(for: [done], timeout: 2)
    }
}
