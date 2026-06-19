import XCTest
@testable import AndroidFileManager

final class ADBServiceParsingTests: XCTestCase {

    // MARK: - ls -la parsing

    func testParseLsLa_standardFiles() {
        let output = """
        total 16
        drwx------ 2 root root 4096 Jun 10 14:30 Documents
        -rwx------ 1 root root 1024 Jun 10 14:31 photo.jpg
        -rwx------ 1 root root  512 Jun 10 14:32 notes.txt
        """

        let items = parseLsLaOutput(output, dirPath: "/sdcard")
        XCTAssertEqual(items.count, 3)
        XCTAssertTrue(items[0].isDirectory)
        XCTAssertEqual(items[0].name, "Documents")
        XCTAssertEqual(items[0].path, "/sdcard/Documents")
        XCTAssertFalse(items[1].isDirectory)
        XCTAssertEqual(items[1].name, "photo.jpg")
        XCTAssertEqual(items[1].size, 1024)
    }

    func testParseLsLa_skipTotalLine() {
        let output = "total 8\ndrwx------ 2 root root 4096 Jun 10 14:30 Downloads\n"
        let items = parseLsLaOutput(output, dirPath: "/sdcard")
        XCTAssertEqual(items.count, 1)
    }

    func testParseLsLa_emptyOutput() {
        let items = parseLsLaOutput("", dirPath: "/sdcard")
        XCTAssertEqual(items.count, 0)
    }

    func testParseLsLa_filesWithSpacesInName() {
        let output = "total 4\n-rwx------ 1 root root 2048 Jun 10 14:30 My Photos"
        let items = parseLsLaOutput(output, dirPath: "/sdcard")
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].name, "My Photos")
    }

    func testParseLsLa_dateWithYear() {
        let output = "total 4\n-rwx------ 1 root root 2048 Jan 10  2025 old_file.txt"
        let items = parseLsLaOutput(output, dirPath: "/sdcard")
        XCTAssertEqual(items.count, 1)
        XCTAssertNotNil(items[0].modifiedDate)
    }

    func testParseLsLa_isoDateFormat() {
        // toybox ls -la on Xiaomi 15: ISO date "2026-06-16 14:30" (2 tokens, not US 3-token)
        let output = "total 8\n-rw-rw---- 1 root sdcard_rw 1234 2026-06-16 14:30 photo.jpg\ndrwxr-xr-x 2 root root 4096 2026-06-15 09:00 Downloads"
        let items = parseLsLaOutput(output, dirPath: "/sdcard")
        XCTAssertEqual(items.count, 2, "ISO date format: should parse 2 items")
        XCTAssertEqual(items[0].name, "photo.jpg")
        XCTAssertFalse(items[0].isDirectory)
        XCTAssertEqual(items[0].size, 1234)
        XCTAssertNotNil(items[0].modifiedDate)
        XCTAssertEqual(items[1].name, "Downloads")
        XCTAssertTrue(items[1].isDirectory)
        XCTAssertEqual(items[1].size, 4096)
    }

    // MARK: - find + stat compact format

    func testParseFindStat_compactFormat() {
        let output = """
        d|4096|1717999200|/sdcard/Documents
        f|1024|1717999260|/sdcard/photo.jpg
        """

        let items = parseFindStatOutput(output)
        XCTAssertEqual(items.count, 2)
        XCTAssertTrue(items[0].isDirectory)
        XCTAssertEqual(items[0].name, "Documents")
        XCTAssertEqual(items[0].size, 4096)
        XCTAssertFalse(items[1].isDirectory)
        XCTAssertEqual(items[1].name, "photo.jpg")
        XCTAssertEqual(items[1].size, 1024)
        XCTAssertNotNil(items[0].modifiedDate)
    }

    func testParseFindStat_emptyOutput() {
        let items = parseFindStatOutput("")
        XCTAssertEqual(items.count, 0)
    }

    // MARK: - ls -1aF parsing

    func testParseLs1a_standardOutput() {
        let output = """
        .
        ..
        Documents/
        photo.jpg
        """

        let items = parseLs1aOutput(output, dirPath: "/sdcard", usesF: true)
        XCTAssertEqual(items.count, 4)
        XCTAssertEqual(items[2].name, "Documents")
        XCTAssertTrue(items[2].isDirectory)
        XCTAssertEqual(items[3].name, "photo.jpg")
    }

    func testParseLs1a_skipsDotFiles() {
        let output = ".\n..\nDownloads\n.vscode"
        let items = parseLs1aOutput(output, dirPath: "/sdcard", usesF: false)
        XCTAssertEqual(items.count, 4) // . 和 .. 不过滤
    }

    // MARK: - test -d compact format

    func testParseTestDOutput() {
        let output = """
        d|Documents
        f|photo.jpg
        f|notes.txt
        """

        let items = parseTestDOutput(output, dirPath: "/sdcard")
        XCTAssertEqual(items.count, 3)
        XCTAssertTrue(items[0].isDirectory)
        XCTAssertEqual(items[0].name, "Documents")
        XCTAssertFalse(items[1].isDirectory)
        XCTAssertEqual(items[1].name, "photo.jpg")
    }

    func testParseTestD_skipsDotAndDotDot() {
        let output = "d|.\nd|..\nd|Downloads"
        let items = parseTestDOutput(output, dirPath: "/sdcard")
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].name, "Downloads")
    }
}
