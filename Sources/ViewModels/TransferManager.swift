import SwiftUI
import Observation

@MainActor
@Observable
final class TransferManager {
    private let adb = ADBService.shared
    var tasks: [TransferTask] = []
    var isTransferring = false
    private var pausedTasks: Set<UUID> = []

    func enqueue(task: TransferTask) {
        tasks.append(task)
        processNextIfIdle()
    }

    private func processNextIfIdle() {
        guard !isTransferring else { return }
        guard let idx = tasks.firstIndex(where: { $0.status == .queued && !pausedTasks.contains($0.id) }) else {
            isTransferring = false
            return
        }
        isTransferring = true
        processTask(at: idx)
    }

    private func processTask(at idx: Int) {
        let task = tasks[idx]
        tasks[idx].status = .transferring

        Task {
            do {
                if task.direction == .push {
                    try await adb.pushFile(
                        device: task.deviceId,
                        localPath: task.localPath,
                        remotePath: task.remotePath
                    ) { [weak self] current, total in
                        Task { @MainActor [weak self] in
                            self?.updateProgress(taskId: task.id, current: current)
                        }
                    }
                } else {
                    try await adb.pullFile(
                        device: task.deviceId,
                        remotePath: task.remotePath,
                        localPath: task.localPath
                    ) { [weak self] current, total in
                        Task { @MainActor [weak self] in
                            self?.updateProgress(taskId: task.id, current: current)
                        }
                    }
                }
                if let i = tasks.firstIndex(where: { $0.id == task.id }) {
                    tasks[i].status = .completed
                } else {
                    androidFMLog("TransferManager: 任务 \(task.id) 已完成但已从列表中移除")
                }
            } catch {
                if let i = tasks.firstIndex(where: { $0.id == task.id }) {
                    tasks[i].status = .failed
                } else {
                    androidFMLog("TransferManager: 任务 \(task.id) 失败但已从列表中移除")
                }
            }

            isTransferring = false
            processNextIfIdle()
        }
    }

    private func updateProgress(taskId: UUID, current: Int64) {
        if let i = tasks.firstIndex(where: { $0.id == taskId }) {
            tasks[i].transferredBytes = current
        }
    }

    func pause(taskId: UUID) {
        pausedTasks.insert(taskId)
        // 如果暂停的是当前传输中的任务，立即终止 adb 进程
        if let idx = tasks.firstIndex(where: { $0.id == taskId }),
           tasks[idx].status == .transferring {
            adb.cancelCurrentTransfer()
            tasks[idx].status = .queued
            isTransferring = false
            processNextIfIdle()
        }
    }

    func resume(taskId: UUID) {
        pausedTasks.remove(taskId)
        processNextIfIdle()
    }

    func cancelAll() {
        tasks.removeAll()
        pausedTasks.removeAll()
        isTransferring = false
        adb.cancelCurrentTransfer()
    }

    func retryFailed() {
        for i in tasks.indices where tasks[i].status == .failed {
            tasks[i].status = .queued
        }
        processNextIfIdle()
    }

    func cancel(taskId: UUID) {
        let wasTransferring = tasks.first(where: { $0.id == taskId })?.status == .transferring
        tasks.removeAll { $0.id == taskId }
        if wasTransferring {
            adb.cancelCurrentTransfer()
            isTransferring = false
            processNextIfIdle()
        } else if tasks.isEmpty {
            isTransferring = false
        }
    }

    func clearCompleted() {
        tasks.removeAll { $0.status == .completed }
    }
}
