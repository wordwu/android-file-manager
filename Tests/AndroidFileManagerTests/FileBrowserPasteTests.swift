import XCTest
import Foundation

final class FileBrowserPasteTests: XCTestCase {

    // MARK: - Paste rename collision algorithm

    /// Replicates the rename collision logic from FileBrowser.paste()
    func resolvePastePath(srcPath: String, destDir: String, existingPaths: inout Set<String>) -> String {
        let name = (srcPath as NSString).lastPathComponent
        let dest = destDir.hasSuffix("/") ? destDir : "\(destDir)/"
        var destPath = "\(dest)\(name)"

        if existingPaths.contains(destPath) {
            let base = destPath
            var counter = 1
            while existingPaths.contains(destPath) {
                let dotIdx = base.lastIndex(of: ".")
                if let idx = dotIdx {
                    destPath = "\(base[..<idx]) \(counter)\(base[idx...])"
                } else {
                    destPath = "\(base) \(counter)"
                }
                counter += 1
                if counter > 99 { break }
            }
        }

        existingPaths.insert(destPath)
        return destPath
    }

    func testNoCollision_returnsOriginalPath() {
        var existing: Set<String> = ["/sdcard/notes.txt"]
        let result = resolvePastePath(srcPath: "/sdcard/photo.jpg", destDir: "/sdcard", existingPaths: &existing)
        XCTAssertEqual(result, "/sdcard/photo.jpg")
        XCTAssertTrue(existing.contains("/sdcard/photo.jpg"))
    }

    func testSingleCollision_renamesWithNumber() {
        var existing: Set<String> = ["/sdcard/photo.jpg"]
        let result = resolvePastePath(srcPath: "/sdcard/photo.jpg", destDir: "/sdcard", existingPaths: &existing)
        XCTAssertEqual(result, "/sdcard/photo 1.jpg")
    }

    func testMultipleCollisions_incrementsCounter() {
        var existing: Set<String> = [
            "/sdcard/photo.jpg",
            "/sdcard/photo 1.jpg",
            "/sdcard/photo 2.jpg"
        ]
        let result = resolvePastePath(srcPath: "/sdcard/photo.jpg", destDir: "/sdcard", existingPaths: &existing)
        XCTAssertEqual(result, "/sdcard/photo 3.jpg")
    }

    func testNoExtension_renamesWithSpaceCounter() {
        var existing: Set<String> = ["/sdcard/README"]
        let result = resolvePastePath(srcPath: "/sdcard/README", destDir: "/sdcard", existingPaths: &existing)
        XCTAssertEqual(result, "/sdcard/README 1")
    }

    func testMultipleNoExtension_incrementsCorrectly() {
        var existing: Set<String> = ["/sdcard/Dockerfile", "/sdcard/Dockerfile 1"]
        let result = resolvePastePath(srcPath: "/sdcard/Dockerfile", destDir: "/sdcard", existingPaths: &existing)
        XCTAssertEqual(result, "/sdcard/Dockerfile 2")
    }

    func testDestDirWithoutTrailingSlash_addsSlash() {
        var existing: Set<String> = []
        let result = resolvePastePath(srcPath: "/sdcard/file.txt", destDir: "/sdcard/Downloads", existingPaths: &existing)
        XCTAssertEqual(result, "/sdcard/Downloads/file.txt")
    }

    func testSequentialCopy_multipleFiles() {
        var existing: Set<String> = []
        let r1 = resolvePastePath(srcPath: "/sdcard/a.txt", destDir: "/sdcard", existingPaths: &existing)
        let r2 = resolvePastePath(srcPath: "/sdcard/a.txt", destDir: "/sdcard", existingPaths: &existing)
        let r3 = resolvePastePath(srcPath: "/sdcard/a.txt", destDir: "/sdcard", existingPaths: &existing)

        XCTAssertEqual(r1, "/sdcard/a.txt")
        XCTAssertEqual(r2, "/sdcard/a 1.txt")
        XCTAssertEqual(r3, "/sdcard/a 2.txt")
    }

    func testCounterLimit99_breaksAfterMax() {
        var existing: Set<String> = ["/sdcard/test.txt"]
        // Fill up to 99
        for i in 1...98 {
            existing.insert("/sdcard/test \(i).txt")
        }
        let result = resolvePastePath(srcPath: "/sdcard/test.txt", destDir: "/sdcard", existingPaths: &existing)
        // Should break at counter=99, meaning destPath = "test 99.txt"
        XCTAssertEqual(result, "/sdcard/test 99.txt")
    }
}
