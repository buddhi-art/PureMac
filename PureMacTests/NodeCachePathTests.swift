import XCTest
@testable import PureMac

final class NodeCachePathTests: XCTestCase {
    func testApprovedManagerRootsRemainNarrow() {
        let home = "/Users/example"

        XCTAssertEqual(
            NodeCacheScanner.approvedNodeCacheRoots(for: .npm, home: home),
            ["/Users/example/.npm", "/Users/example/Library/Caches/npm"]
        )
        XCTAssertEqual(
            NodeCacheScanner.approvedNodeCacheRoots(for: .yarn, home: home),
            ["/Users/example/Library/Caches/Yarn", "/Users/example/.cache/yarn"]
        )
        XCTAssertEqual(
            NodeCacheScanner.approvedNodeCacheRoots(for: .pnpm, home: home),
            [
                "/Users/example/Library/pnpm/store",
                "/Users/example/.local/share/pnpm/store",
                "/Users/example/.pnpm-store",
                "/Users/example/.cache/pnpm",
            ]
        )
    }

    func testValidationAcceptsOnlyManagerRootOrDescendant() {
        let home = "/Users/example"

        XCTAssertEqual(
            NodeCacheScanner.validatedNodeCachePath(
                "/Users/example/.npm/_cacache",
                manager: .npm,
                home: home
            ),
            "/Users/example/.npm/_cacache"
        )
        XCTAssertEqual(
            NodeCacheScanner.validatedNodeCachePath(
                "/Users/example/Library/pnpm/store/v10",
                manager: .pnpm,
                home: home
            ),
            "/Users/example/Library/pnpm/store/v10"
        )
        XCTAssertNil(
            NodeCacheScanner.validatedNodeCachePath(
                "/Users/example/.npm",
                manager: .pnpm,
                home: home
            )
        )
    }

    func testValidationRejectsBroadParentsRelativePathsAndTraversal() {
        let home = "/Users/example"
        let rejected = [
            "/",
            home,
            "~/.npm",
            "/Users/example/Library/Application Support",
            "/Users/example/Library/Application Support/.cache",
            "/Users/example/.cache",
            "/Users/example/.npm/../../Library/Application Support",
            "/Users/example/.npm\n/Library",
        ]

        for candidate in rejected {
            XCTAssertNil(
                NodeCacheScanner.validatedNodeCachePath(candidate, manager: .npm, home: home),
                candidate
            )
        }
    }

    func testValidationRejectsSymlinkEscapingApprovedRoot() throws {
        let fileManager = FileManager.default
        let base = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let homeURL = base.appendingPathComponent("home", isDirectory: true)
        let cacheURL = homeURL.appendingPathComponent(".npm", isDirectory: true)
        let outsideURL = base.appendingPathComponent("outside", isDirectory: true)
        let aliasURL = cacheURL.appendingPathComponent("redirect", isDirectory: true)
        try fileManager.createDirectory(at: cacheURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: outsideURL, withIntermediateDirectories: true)
        try fileManager.createSymbolicLink(at: aliasURL, withDestinationURL: outsideURL)
        defer { try? fileManager.removeItem(at: base) }

        let home = homeURL.resolvingSymlinksInPath().path
        XCTAssertNil(
            NodeCacheScanner.validatedNodeCachePath(
                aliasURL.path,
                manager: .npm,
                home: home
            )
        )
    }

    func testPruningKeepsCanonicalParentAndRemovesDuplicateDescendants() {
        let paths = [
            "/Users/example/.npm/_cacache",
            "/Users/example/Library/Caches/npm",
            "/Users/example/.npm",
            "/Users/example/.npm",
            "/Users/example/Library/Caches/npm/content-v2",
        ]

        XCTAssertEqual(
            NodeCacheScanner.prunedNodeCachePaths(paths),
            ["/Users/example/.npm", "/Users/example/Library/Caches/npm"]
        )
    }
}
