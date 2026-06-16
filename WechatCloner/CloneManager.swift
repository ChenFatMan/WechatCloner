import AppKit
import Foundation

@MainActor
final class CloneManager: ObservableObject {
    @Published private(set) var sources: [SourceApp] = []
    @Published private(set) var clones: [CloneApp] = []
    @Published private(set) var isWorking = false
    @Published var statusMessage = "准备就绪"
    @Published var errorMessage: String?

    private let fileManager: FileManager
    private let shell: ShellRunner
    private let editor: AppBundleEditor
    private let backupManager: BackupManager
    private let installDirectory: URL

    init(
        fileManager: FileManager = .default,
        shell: ShellRunner = ShellRunner(),
        editor: AppBundleEditor = AppBundleEditor(),
        backupManager: BackupManager = BackupManager(),
        installDirectory: URL = URL(fileURLWithPath: "/Applications")
    ) {
        self.fileManager = fileManager
        self.shell = shell
        self.editor = editor
        self.backupManager = backupManager
        self.installDirectory = installDirectory
    }

    func refresh() {
        do {
            sources = try scanSources()
            clones = try scanClones()
            statusMessage = "已扫描到 \(sources.count) 个源应用，\(clones.count) 个分身"
            errorMessage = nil
        } catch {
            errorMessage = Self.readable(error)
        }
    }

    func addSource(url: URL) {
        do {
            let source = try editor.readSourceApp(at: url)
            if !sources.contains(source) {
                sources.append(source)
            }
            statusMessage = "已添加源应用：\(source.displayName)"
            errorMessage = nil
        } catch {
            errorMessage = Self.readable(error)
        }
    }

    func suggestedCloneName(for source: SourceApp) -> String {
        let base = source.displayName
        var index = 2

        while fileManager.fileExists(atPath: installDirectory.appendingPathComponent("\(base)\(index).app").path) {
            index += 1
        }

        return "\(base)\(index)"
    }

    func suggestedBundleIdentifier(for source: SourceApp, cloneName: String) -> String {
        let suffix = cloneName
            .lowercased()
            .unicodeScalars
            .map { CharacterSet.alphanumerics.contains($0) ? String($0) : "-" }
            .joined()
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))

        let stableSuffix = suffix.isEmpty ? "clone-\(clones.count + 2)" : suffix
        return "\(source.bundleIdentifier).clone.\(stableSuffix)"
    }

    func versionStatus(for clone: CloneApp) -> CloneVersionStatus {
        guard let source = try? Self.sourceForClone(clone, sources: sources) else {
            return CloneVersionStatus(sourceVersion: nil, recommendation: .sourceMissing)
        }

        let comparison = clone.bundleVersion.localizedStandardCompare(source.bundleVersion)
        let recommendation: UpdateRecommendation = comparison == .orderedAscending ? .upgradeRecommended : .upToDate

        return CloneVersionStatus(
            sourceVersion: source.bundleVersion,
            recommendation: recommendation
        )
    }

    func createClone(source: SourceApp, cloneName: String, bundleIdentifier: String) {
        let sanitizedName = cloneName.trimmingCharacters(in: .whitespacesAndNewlines)
        let sanitizedIdentifier = bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let request = CloneRequest(
            sourceURL: source.url,
            cloneName: sanitizedName,
            bundleIdentifier: sanitizedIdentifier
        )
        let installDirectory = installDirectory
        let shell = shell
        let editor = editor

        perform("正在创建 \(cloneName)...") {
            try Self.validate(request: request, editor: editor)

            let targetURL = installDirectory.appendingPathComponent("\(sanitizedName).app")
            guard FileManager.default.fileExists(atPath: source.url.path) else {
                throw CloneError.sourceNotFound(source.url)
            }
            guard !FileManager.default.fileExists(atPath: targetURL.path) else {
                throw CloneError.targetAlreadyExists(targetURL)
            }

            try Self.rebuildCloneApp(
                source: source,
                targetURL: targetURL,
                request: request,
                editor: editor,
                shell: shell
            )

            let clones = try Self.scanClones(in: installDirectory, editor: editor)
            Task { @MainActor in
                self.clones = clones
                self.statusMessage = "已创建：\(sanitizedName)"
            }
        }
    }

    func backupCloneData(_ clone: CloneApp) {
        let backupManager = backupManager

        perform("正在备份 \(clone.displayName) 数据...") {
            let backup = try backupManager.backupContainer(for: clone)
            Task { @MainActor in
                if backup.containerBackupURL == nil {
                    self.statusMessage = "未找到数据容器，已创建空备份目录：\(backup.directory.path)"
                } else {
                    self.statusMessage = "已备份数据：\(backup.directory.path)"
                }
            }
        }
    }

    func updateClone(_ clone: CloneApp) {
        updateClone(clone, shouldBackupContainer: false)
    }

    func backupAndUpdateClone(_ clone: CloneApp) {
        updateClone(clone, shouldBackupContainer: true)
    }

    func launch(_ clone: CloneApp) {
        let shell = shell

        perform("正在启动 \(clone.displayName)...") {
            try shell.run("/usr/bin/open", arguments: ["-n", clone.url.path])
            Task { @MainActor in
                self.statusMessage = "已启动：\(clone.displayName)"
            }
        }
    }

    func remove(_ clone: CloneApp) {
        let installDirectory = installDirectory
        let editor = editor

        perform("正在删除 \(clone.displayName)...") {
            try FileManager.default.removeItem(at: clone.url)
            let clones = try Self.scanClones(in: installDirectory, editor: editor)
            Task { @MainActor in
                self.clones = clones
                self.statusMessage = "已删除：\(clone.displayName)"
            }
        }
    }

    private func scanSources() throws -> [SourceApp] {
        try KnownApp.candidates
            .filter { fileManager.fileExists(atPath: $0.path) }
            .map { try editor.readSourceApp(at: $0) }
    }

    private func scanClones() throws -> [CloneApp] {
        try Self.scanClones(in: installDirectory, editor: editor)
    }

    nonisolated private static func scanClones(in installDirectory: URL, editor: AppBundleEditor) throws -> [CloneApp] {
        let apps = try FileManager.default.contentsOfDirectory(
            at: installDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )

        return apps
            .filter { $0.pathExtension == "app" }
            .compactMap { url in
                guard let clone = try? editor.readCloneApp(at: url),
                      Self.isCloneCandidate(clone) else {
                    return nil
                }
                return clone
            }
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    nonisolated private static func rebuildCloneApp(
        source: SourceApp,
        targetURL: URL,
        request: CloneRequest,
        editor: AppBundleEditor,
        shell: ShellRunner
    ) throws {
        try FileManager.default.copyItem(at: source.url, to: targetURL)
        try editor.updateCloneInfo(at: targetURL, request: request, source: source)
        try shell.run("/usr/bin/xattr", arguments: ["-cr", targetURL.path])
        try shell.run("/usr/bin/codesign", arguments: ["--force", "--deep", "--sign", "-", targetURL.path])
    }

    private func updateClone(_ clone: CloneApp, shouldBackupContainer: Bool) {
        let installDirectory = installDirectory
        let editor = editor
        let shell = shell
        let backupManager = backupManager
        let sources = sources

        perform(shouldBackupContainer ? "正在备份并更新 \(clone.displayName)..." : "正在更新 \(clone.displayName)...") {
            let source = try Self.sourceForClone(clone, sources: sources)
            let appBackup = shouldBackupContainer
                ? try backupManager.backupAppAndContainer(for: clone)
                : try backupManager.backupApp(for: clone)

            let request = CloneRequest(
                sourceURL: source.url,
                cloneName: clone.displayName,
                bundleIdentifier: clone.bundleIdentifier
            )

            do {
                try FileManager.default.removeItem(at: clone.url)
                try Self.rebuildCloneApp(
                    source: source,
                    targetURL: clone.url,
                    request: request,
                    editor: editor,
                    shell: shell
                )
            } catch {
                try Self.restoreAppIfPossible(cloneURL: clone.url, backupURL: appBackup.appBackupURL)
                throw error
            }

            let clones = try Self.scanClones(in: installDirectory, editor: editor)
            Task { @MainActor in
                self.clones = clones
                self.statusMessage = "已更新：\(clone.displayName)。备份目录：\(appBackup.directory.path)"
            }
        }
    }

    nonisolated private static func sourceForClone(_ clone: CloneApp, sources: [SourceApp]) throws -> SourceApp {
        let sourceBundleIdentifier = clone.sourceBundleIdentifier
            ?? KnownApp.sourceBundleIdentifier(for: clone.bundleIdentifier)

        guard let sourceBundleIdentifier,
              let source = sources.first(where: { $0.bundleIdentifier == sourceBundleIdentifier }) else {
            throw CloneError.sourceForCloneNotFound(clone.bundleIdentifier)
        }

        return source
    }

    nonisolated private static func restoreAppIfPossible(cloneURL: URL, backupURL: URL?) throws {
        guard let backupURL, FileManager.default.fileExists(atPath: backupURL.path) else {
            throw CloneError.appBackupMissing(cloneURL)
        }

        if FileManager.default.fileExists(atPath: cloneURL.path) {
            try FileManager.default.removeItem(at: cloneURL)
        }

        try FileManager.default.copyItem(at: backupURL, to: cloneURL)
    }

    nonisolated private static func isCloneCandidate(_ app: CloneApp) -> Bool {
        if app.sourceBundleIdentifier != nil {
            return true
        }

        let hasSupportedPrefix = KnownApp.supportedBundlePrefixes.contains { prefix in
            app.bundleIdentifier.hasPrefix(prefix)
        }
        let isOriginalSource = KnownApp.sourceBundleIdentifiers.contains(app.bundleIdentifier)

        return hasSupportedPrefix && !isOriginalSource
    }

    nonisolated private static func validate(request: CloneRequest, editor: AppBundleEditor) throws {
        guard editor.isAppBundle(request.sourceURL) else {
            throw CloneError.invalidAppBundle(request.sourceURL)
        }

        guard !request.cloneName.isEmpty else {
            throw CloneError.invalidCloneName
        }

        guard request.bundleIdentifier.contains(".") && !request.bundleIdentifier.contains(" ") else {
            throw CloneError.invalidBundleIdentifier(request.bundleIdentifier)
        }
    }

    private func perform(_ message: String, operation: @escaping @Sendable () throws -> Void) {
        isWorking = true
        statusMessage = message
        errorMessage = nil

        Task.detached {
            do {
                try operation()
            } catch {
                let message = Self.readable(error)
                await MainActor.run {
                    self.errorMessage = message
                }
            }

            await MainActor.run {
                self.isWorking = false
            }
        }
    }

    nonisolated private static func readable(_ error: Error) -> String {
        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            return description
        }
        return error.localizedDescription
    }
}
