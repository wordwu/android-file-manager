import XCTest
@testable import AndroidFileManager

/// 集成测试：验证 listFiles 四策略 fallback 链的正确性
@MainActor
final class ListFilesStrategyTests: XCTestCase {

    override func setUp() {
        ADBService.shared.mockShell = nil
    }

    override func tearDown() {
        ADBService.shared.mockShell = nil
    }

    private func hasArg(_ args: [String], _ substr: String) -> Bool {
        args.joined(separator: " ").contains(substr)
    }

    // MARK: - 策略 1: ls -la 成功

    func testStrategy1_lsLa_succeeds() async throws {
        let lsOutput = """
        total 8
        drwx------ 2 root root 4096 Jun 10 14:30 Documents
        -rwx------ 1 root root 1024 Jun 10 14:31 photo.jpg
        """

        ADBService.shared.mockShell = { [self] args, _ in
            if hasArg(args, "ls") && hasArg(args, "-la") {
                return lsOutput
            }
            throw ADBError.commandFailed(exitCode: 1, stderr: "unexpected")
        }

        let items = try ADBService.shared.listFiles(device: "emulator-5554", path: "/sdcard")
        XCTAssertEqual(items.count, 2)
        XCTAssertTrue(items[0].isDirectory)
        XCTAssertEqual(items[0].name, "Documents")
        XCTAssertFalse(items[1].isDirectory)
        XCTAssertEqual(items[1].name, "photo.jpg")
    }

    // MARK: - 策略 2: ls -la 失败 → find+stat compact 格式成功

    func testStrategy2_fallbackToFindStat() async throws {
        let statOutput = """
        d|4096|1717999200|/sdcard/Downloads
        f|512|1717999260|/sdcard/readme.txt
        """

        ADBService.shared.mockShell = { [self] args, _ in
            if hasArg(args, "ls") && hasArg(args, "-la") {
                throw ADBError.commandFailed(exitCode: 1, stderr: "permission denied")
            }
            if hasArg(args, "find") {
                return statOutput
            }
            throw ADBError.commandFailed(exitCode: 1, stderr: "unexpected")
        }

        let items = try ADBService.shared.listFiles(device: "emulator-5554", path: "/sdcard")
        XCTAssertEqual(items.count, 2)
        XCTAssertTrue(items[0].isDirectory)
        XCTAssertEqual(items[0].name, "Downloads")
        XCTAssertEqual(items[0].size, 4096)
        XCTAssertFalse(items[1].isDirectory)
        XCTAssertEqual(items[1].name, "readme.txt")
        XCTAssertEqual(items[1].size, 512)
    }

    // MARK: - 策略 3: ls -1aF 兜底

    func testStrategy3_fallbackToLs1aF() async throws {
        let ls1aFOutput = """
        .
        ..
        Downloads/
        readme.txt
        """

        ADBService.shared.mockShell = { [self] args, _ in
            if hasArg(args, "ls") && hasArg(args, "-la") {
                throw ADBError.commandFailed(exitCode: 1, stderr: "")
            }
            if hasArg(args, "find") {
                throw ADBError.commandFailed(exitCode: 2, stderr: "")
            }
            if hasArg(args, "-1aF") {
                return ls1aFOutput
            }
            throw ADBError.commandFailed(exitCode: 1, stderr: "unexpected")
        }

        let items = try ADBService.shared.listFiles(device: "emulator-5554", path: "/sdcard")
        // 文件夹在前：Downloads→.→..→readme.txt
        XCTAssertEqual(items.count, 4)
        XCTAssertEqual(items[0].name, "Downloads")
        XCTAssertTrue(items[0].isDirectory)
    }

    // MARK: - 策略 4: ls -1a 兜底

    func testStrategy4_fallbackToLs1a() async throws {
        let ls1aOutput = """
        .
        ..
        cache
        logs
        """

        ADBService.shared.mockShell = { [self] args, _ in
            if hasArg(args, "ls") && hasArg(args, "-la") {
                throw ADBError.commandFailed(exitCode: 1, stderr: "")
            }
            if hasArg(args, "find") {
                throw ADBError.commandFailed(exitCode: 2, stderr: "")
            }
            if hasArg(args, "-1aF") {
                throw ADBError.commandFailed(exitCode: 1, stderr: "no -F flag")
            }
            if hasArg(args, "-1a") {
                return ls1aOutput
            }
            throw ADBError.commandFailed(exitCode: 1, stderr: "unexpected")
        }

        let items = try ADBService.shared.listFiles(device: "emulator-5554", path: "/sdcard")
        XCTAssertEqual(items.count, 4)
        // 无 -F，全部当普通文件，排序: . < .. < cache < logs
        XCTAssertEqual(items[0].name, ".")
        XCTAssertEqual(items[1].name, "..")
        XCTAssertEqual(items[2].name, "cache")
        XCTAssertEqual(items[3].name, "logs")
    }

    // MARK: - 排序

    func testSortedOutput_foldersFirst() async throws {
        let lsOutput = """
        total 16
        -rwx------ 1 root root  512 Jun 10 14:30 z_photo.jpg
        drwx------ 2 root root 4096 Jun 10 14:30 a_folder
        -rwx------ 1 root root 1024 Jun 10 14:31 b_file.txt
        """

        ADBService.shared.mockShell = { [self] args, _ in
            if hasArg(args, "ls") && hasArg(args, "-la") {
                return lsOutput
            }
            throw ADBError.commandFailed(exitCode: 1, stderr: "")
        }

        let items = try ADBService.shared.listFiles(device: "emulator-5554", path: "/sdcard")
        XCTAssertEqual(items.count, 3)
        XCTAssertTrue(items[0].isDirectory)
        XCTAssertEqual(items[0].name, "a_folder")
        XCTAssertFalse(items[1].isDirectory)
        XCTAssertFalse(items[2].isDirectory)
        XCTAssert(items[1].name < items[2].name)
    }
}
