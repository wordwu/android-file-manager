import Foundation

extension ADBService {
    // MARK: - APK 安装与应用列表
    // MARK: - APK 安装
    
    /// 尝试 pm install -r，失败遇降级错误自动 -d 重试
    private func pmInstallWithDowngradeRetry(device: String, remotePath: String) throws {
        let cmd = "pm install -r \"\(shellEscape(remotePath))\""
        do {
            _ = try run(["-s", device, "shell", cmd], timeout: C.adbInstall)
        } catch let err as ADBError {
            guard case .commandFailed(exitCode: _, let stderrStr) = err else { throw err }
            if stderrStr.contains("INSTALL_FAILED_VERSION_DOWNGRADE") {
                let downgradeCmd = "pm install -r -d \"\(shellEscape(remotePath))\""
                androidFMLog("[ADBService] pmInstall: retry with -d: device=\(device)")
                _ = try run(["-s", device, "shell", downgradeCmd], timeout: C.adbInstall)
            } else {
                throw err
            }
        }
    }

    /// 安装 APK 到设备（含 -d 降级重试，兼容老 Android）
    func installAPK(device: String, localPath: String) throws {
        let fileName = (localPath as NSString).lastPathComponent
        let remoteTmp = "/data/local/tmp/\(fileName)"
        androidFMLog("[ADBService] installAPK: pushing \(fileName) to \(remoteTmp)")

        _ = try run(["-s", device, "push", localPath, remoteTmp], timeout: C.adbInstall)
        defer {
            do {
                _ = try run(["-s", device, "shell", "rm -f \"\(shellEscape(remoteTmp))\""], timeout: 5)
            } catch {
                androidFMLog("installAPK(push) cleanup failed (non-fatal): \(error)")
            }
        }

        try pmInstallWithDowngradeRetry(device: device, remotePath: remoteTmp)
    }

    /// 安装错误信息映射（中文友好提示）
    static func installErrorMessage(from error: Error) -> String {
        let desc = error.localizedDescription
        if desc.contains("USER_RESTRICTED") {
            return "安装被限制，请在手机上确认「USB 调试」和「安装未知应用」权限已开启"
        }
        if desc.contains("INSTALL_FAILED_VERSION_DOWNGRADE") {
            return "安装失败：当前版本高于要安装的版本，请先卸载再试"
        }
        if desc.contains("INSTALL_FAILED_UPDATE_INCOMPATIBLE") {
            return "安装失败：签名不一致，请先卸载旧版本"
        }
        if desc.contains("INSTALL_FAILED_INSUFFICIENT_STORAGE") {
            return "安装失败：存储空间不足"
        }
        if desc.contains("INSTALL_FAILED_INVALID_APK") {
            return "安装失败：APK 文件不完整或已损坏"
        }
        if desc.contains("INSTALL_FAILED") {
            return "安装失败，请检查 USB 调试权限和存储空间"
        }
        if desc.contains("Failure") {
            return "安装失败，请检查 APK 是否完整且兼容"
        }
        return "安装失败，请稍后重试"
    }

    /// 从设备下载 APK 到本地临时目录后安装（含状态回调）
    static func installAPKWithStatus(device: String, remotePath: String, fileName: String,
                                     onStatus: @escaping @Sendable (String) -> Void) async {
        let shared = ADBService.shared
        do {
            onStatus("正在准备 \(fileName)...")
            let tmpName = "install_\(UUID().uuidString).apk"
            let tmpRemote = "/data/local/tmp/\(tmpName)"

            // cp 到 /data/local/tmp/ 绕过 SELinux（比 pull→push 快）
            let cpCmd = "cp \"\(shared.shellEscape(remotePath))\" \"\(shared.shellEscape(tmpRemote))\""
            _ = try shared.run(["-s", device, "shell", cpCmd], timeout: 10)
            defer {
                do {
                    _ = try shared.run(["-s", device, "shell", "rm -f \"\(shared.shellEscape(tmpRemote))\""], timeout: 5)
                } catch {
                    androidFMLog("installAPK cleanup failed (non-fatal): \(error)")
                }
            }

            onStatus("正在安装 \(fileName)...")
            do {
                try shared.pmInstallWithDowngradeRetry(device: device, remotePath: tmpRemote)
                onStatus("\(fileName) 安装成功")
            } catch {
                throw error
            }
        } catch {
            let msg = installErrorMessage(from: error)
            onStatus(msg)
        }
    }

    /// ADB 心跳检测
    // MARK: - 应用列表管理

    /// 列出设备上所有已安装的应用（含 APK 路径和系统/三方分类）
    func listPackages(device: String) throws -> [AppInfo] {
        let output = try run(["-s", device, "shell", "pm list packages -f"], timeout: 15)
        var apps: [AppInfo] = []

        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            let cleaned = trimmed.replacingOccurrences(of: "package:", with: "")
            // Android 12+ 路径含 base64 ==, 用正则精确定位最后的 '=包名'
            guard let sepRange = cleaned.range(of: "=[a-zA-Z_][a-zA-Z0-9_.]*$",
                                                  options: .regularExpression) else { continue }
            let path = String(cleaned[..<sepRange.lowerBound])
            let pkg = String(cleaned[cleaned.index(after: sepRange.lowerBound)...])
            let isSys = C.systemDirPrefixes.contains(where: { path.hasPrefix($0) })
            apps.append(AppInfo(packageName: pkg, apkPath: path, isSystem: isSys))
        }

        return apps
    }

    /// 卸载应用
    func uninstallPackage(device: String, package: String) throws -> String {
        return try run(["-s", device, "uninstall", package], timeout: 30)
    }

    // MARK: - 批量备份 APK

    /// 获取设备型号名（ro.product.model）
    func getDeviceModel(device: String) -> String {
        do {
            let output = try run(["-s", device, "shell", "getprop ro.product.model"], timeout: 5)
            return output.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return "Unknown"
        }
    }

    /// 批量备份所有三方 APK 到本地文件夹
    /// - Returns: (成功数, 失败数, 备份文件夹路径)
    func backupAPKs(device: String, deviceModel: String) async -> (success: Int, failed: Int, dir: String) {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let dateStr = df.string(from: Date())
        let dirName = "\(deviceModel)_\(dateStr)"
        let backupDir = "\(NSHomeDirectory())/Downloads/\(dirName)"

        do {
            try fileManager.createDirectory(atPath: backupDir,
                                            withIntermediateDirectories: true, attributes: nil)
        } catch {
            androidFMLog("[backupAPKs] create dir failed: \(error)")
            return (0, 0, "")
        }

        let apps: [AppInfo]
        do {
            apps = try listPackages(device: device)
        } catch {
            androidFMLog("[backupAPKs] listPackages failed: \(error)")
            return (0, 0, backupDir)
        }

        let userApps = apps.filter { !$0.isSystem }
        var success = 0, failed = 0

        for app in userApps {
            let fileName = "\(app.packageName).apk"
            let localPath = "\(backupDir)/\(fileName)"
            do {
                _ = try run(["-s", device, "pull", app.apkPath, localPath], timeout: 60)
                success += 1
            } catch {
                androidFMLog("[backupAPKs] pull failed for \(app.packageName): \(error)")
                failed += 1
            }
        }

        return (success, failed, backupDir)
    }

    /// 后台解析应用名称和图标路径
    func resolveAppMeta(device: String, package: String, apkPath: String) async -> (name: String, iconPath: String?)? {
        do {
            let info = try await getAPKInfo(device: device, remotePath: apkPath)
            let name = info.appName.isEmpty ? nil : info.appName
            guard let name = name else { return nil }

            var iconPath: String? = nil
            // 尝试提取图标
            if let aapt = aaptPath {
                let tmpApk = "\(C.tmpApkPrefix)icon_\(UUID().uuidString).apk"
                defer { try? fileManager.removeItem(atPath: tmpApk) }

                try await pullFile(device: device, remotePath: apkPath, localPath: tmpApk) { _, _ in }

                // 用 aapt 获取图标资源名
                let badging = try runLocal(aapt, arguments: ["dump", "badging", tmpApk], timeout: 15)
                var iconRes: String?
                for line in badging.components(separatedBy: "\n") {
                    if line.hasPrefix("application-icon-") || line.hasPrefix("application:") {
                        // 从 application: label='...' icon='...' 中提取 icon
                        let kvs = line.components(separatedBy: " ")
                        for kv in kvs {
                            if kv.hasPrefix("icon='") {
                                iconRes = kv.replacingOccurrences(of: "icon='", with: "")
                                    .replacingOccurrences(of: "'", with: "")
                                break
                            }
                        }
                        if iconRes != nil { break }
                    }
                }

                // 若找到图标资源路径，尝试用 unzip 提取
                if let iconRes = iconRes {
                    let cachePath = "\(iconCacheDir)/\(package).png"
                    // 尝试提取最高密度图标
                    let densities = ["xxxhdpi", "xxhdpi", "xhdpi", "hdpi", "mdpi"]
                    var extracted = false
                    for density in densities {
                        let candidate = "res/drawable-\(density)/\(iconRes).png"
                        let unzip = Process()
                        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
                        unzip.arguments = ["-o", "-j", tmpApk, candidate, "-d", iconCacheDir]
                        unzip.standardOutput = FileHandle.nullDevice
                        unzip.standardError = FileHandle.nullDevice
                        try? unzip.run()
                        unzip.waitUntilExit()
                        if unzip.terminationStatus == 0,
                           fileManager.fileExists(atPath: cachePath)
                            || fileManager.fileExists(atPath: "\(iconCacheDir)/\(iconRes).png") {
                            // unzip -j strips dirs, so icon file is in iconCacheDir
                            let extractedFile = "\(iconCacheDir)/\(iconRes).png"
                            if fileManager.fileExists(atPath: extractedFile) {
                                try? fileManager.moveItem(atPath: extractedFile, toPath: cachePath)
                            }
                            if fileManager.fileExists(atPath: cachePath) {
                                iconPath = cachePath
                                extracted = true
                                break
                            }
                        }
                    }
                    // 如果按密度没找到，尝试 drawable 目录
                    if !extracted {
                        let candidate = "res/drawable/\(iconRes).png"
                        let unzip = Process()
                        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
                        unzip.arguments = ["-o", "-j", tmpApk, candidate, "-d", iconCacheDir]
                        unzip.standardOutput = FileHandle.nullDevice
                        unzip.standardError = FileHandle.nullDevice
                        try? unzip.run()
                        unzip.waitUntilExit()
                        let extractedFile = "\(iconCacheDir)/\(iconRes).png"
                        if unzip.terminationStatus == 0, fileManager.fileExists(atPath: extractedFile) {
                            let cachePath = "\(iconCacheDir)/\(package).png"
                            try? fileManager.moveItem(atPath: extractedFile, toPath: cachePath)
                            if fileManager.fileExists(atPath: cachePath) {
                                iconPath = cachePath
                            }
                        }
                    }
                }
            }

            return (name, iconPath)
        } catch {
            androidFMLog("[ADBService] resolveAppMeta error for \(package): \(error)")
            return nil
        }
    }
}