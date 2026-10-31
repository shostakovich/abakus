import Foundation

/// Held while the store lives, so a second copy of the app cannot write the same budget.
final class BudgetLock {
    private let descriptor: Int32

    /// Nil when another process holds the lock.
    init?(url: URL) throws {
        let descriptor = open(url.path, O_RDWR | O_CREAT | O_CLOEXEC, 0o644)
        guard descriptor >= 0 else {
            throw BudgetDatabaseError.unreadable(path: url.path, reason: String(cString: strerror(errno)))
        }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            return nil
        }
        self.descriptor = descriptor
    }

    deinit {
        flock(descriptor, LOCK_UN)
        close(descriptor)
    }
}
