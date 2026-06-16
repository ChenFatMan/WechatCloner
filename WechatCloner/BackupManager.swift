import Foundation

struct BackupManager: Sendable {
    private let backupRoot: URL

    init(
        backupRoot: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("WechatClonerBackups")
    ) {
        self.backupRoot = backupRoot
    }

    func backupContainer(for clone: CloneApp, timestamp: Date = Date()) throws -> BackupResult {
        let directory = backupDirectory(for: clone, timestamp: timestamp)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let source = containerURL(for: clone.bundleIdentifier)
        guard FileManager.default.fileExists(atPath: source.path) else {
            return BackupResult(directory: directory, containerBackupURL: nil, appBackupURL: nil)
        }

        let target = directory.appendingPathComponent("Container")
        try copyContainerReplacingExisting(source: source, target: target)

        return BackupResult(directory: directory, containerBackupURL: target, appBackupURL: nil)
    }

    func backupAppAndContainer(for clone: CloneApp, timestamp: Date = Date()) throws -> BackupResult {
        let directory = backupDirectory(for: clone, timestamp: timestamp)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let appTarget = directory.appendingPathComponent(clone.url.lastPathComponent)
        try copyReplacingExisting(source: clone.url, target: appTarget)

        let containerSource = containerURL(for: clone.bundleIdentifier)
        let containerTarget = directory.appendingPathComponent("Container")
        let backedUpContainer: URL?
        if FileManager.default.fileExists(atPath: containerSource.path) {
            try copyContainerReplacingExisting(source: containerSource, target: containerTarget)
            backedUpContainer = containerTarget
        } else {
            backedUpContainer = nil
        }

        return BackupResult(directory: directory, containerBackupURL: backedUpContainer, appBackupURL: appTarget)
    }

    func backupApp(for clone: CloneApp, timestamp: Date = Date()) throws -> BackupResult {
        let directory = backupDirectory(for: clone, timestamp: timestamp)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let appTarget = directory.appendingPathComponent(clone.url.lastPathComponent)
        try copyReplacingExisting(source: clone.url, target: appTarget)

        return BackupResult(directory: directory, containerBackupURL: nil, appBackupURL: appTarget)
    }

    func containerURL(for bundleIdentifier: String) -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library")
            .appendingPathComponent("Containers")
            .appendingPathComponent(bundleIdentifier)
    }

    private func backupDirectory(for clone: CloneApp, timestamp: Date) -> URL {
        backupRoot
            .appendingPathComponent(clone.bundleIdentifier)
            .appendingPathComponent(Self.timestampFormatter.string(from: timestamp))
    }

    private func copyReplacingExisting(source: URL, target: URL) throws {
        if FileManager.default.fileExists(atPath: target.path) {
            try FileManager.default.removeItem(at: target)
        }
        try FileManager.default.copyItem(at: source, to: target)
    }

    private func copyContainerReplacingExisting(source: URL, target: URL) throws {
        if FileManager.default.fileExists(atPath: target.path) {
            try FileManager.default.removeItem(at: target)
        }

        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)

        let resourceKeys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]
        guard let enumerator = FileManager.default.enumerator(
            at: source,
            includingPropertiesForKeys: resourceKeys,
            options: [],
            errorHandler: { url, error in
                Self.shouldSkipContainerMetadata(url) ? true : {
                    NSLog("WechatCloner backup enumeration failed at %@: %@", url.path, error.localizedDescription)
                    return false
                }()
            }
        ) else {
            return
        }

        for case let itemURL as URL in enumerator {
            if Self.shouldSkipContainerMetadata(itemURL) {
                if (try? itemURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    enumerator.skipDescendants()
                }
                continue
            }

            let relativePath = String(itemURL.path.dropFirst(source.path.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard !relativePath.isEmpty else { continue }

            let destinationURL = target.appendingPathComponent(relativePath)
            let values = try itemURL.resourceValues(forKeys: Set(resourceKeys))

            if values.isDirectory == true && values.isSymbolicLink != true {
                try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)
            } else {
                try FileManager.default.createDirectory(
                    at: destinationURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try FileManager.default.copyItem(at: itemURL, to: destinationURL)
            }
        }
    }

    private static func shouldSkipContainerMetadata(_ url: URL) -> Bool {
        url.lastPathComponent == ".com.apple.containermanagerd.metadata.plist"
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
}
