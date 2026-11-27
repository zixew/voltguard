import Foundation

public final class SingleInstanceGuard: @unchecked Sendable {
    public static let shared = SingleInstanceGuard()

    private let lockFileURL: URL
    private var fileDescriptor: Int32 = -1
    private let lock = NSLock()

    public init(lockFileURL: URL? = nil) {
        if let customURL = lockFileURL {
            self.lockFileURL = customURL
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            self.lockFileURL = appSupport
                .appendingPathComponent(DataConstants.Storage.appFolderName, isDirectory: true)
                .appendingPathComponent(DataConstants.Storage.lockFileName)
        }
    }

    deinit {
        releaseLock()
    }

    public func acquireLock() -> Bool {
        lock.withLock {
            if fileDescriptor >= 0 { return true }

            let dir = lockFileURL.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

            let fd = open(lockFileURL.path, O_CREAT | O_RDWR, 0o644)
            guard fd >= 0 else { return false }

            if flock(fd, LOCK_EX | LOCK_NB) == 0 {
                fileDescriptor = fd
                return true
            } else {
                close(fd)
                return false
            }
        }
    }

    public func releaseLock() {
        lock.withLock {
            if fileDescriptor >= 0 {
                flock(fileDescriptor, LOCK_UN)
                close(fileDescriptor)
                fileDescriptor = -1
            }
        }
    }
}
