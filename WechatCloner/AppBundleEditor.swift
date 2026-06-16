import Foundation

struct AppBundleEditor: Sendable {
    func readSourceApp(at url: URL) throws -> SourceApp {
        let info = try readInfoPlist(in: url)
        guard let bundleIdentifier = info["CFBundleIdentifier"] as? String, !bundleIdentifier.isEmpty else {
            throw CloneError.missingBundleIdentifier(url)
        }

        return SourceApp(
            url: url,
            displayName: displayName(from: info, fallback: url.deletingPathExtension().lastPathComponent),
            bundleIdentifier: bundleIdentifier,
            bundleVersion: bundleVersion(from: info)
        )
    }

    func readCloneApp(at url: URL) throws -> CloneApp {
        let info = try readInfoPlist(in: url)
        guard let bundleIdentifier = info["CFBundleIdentifier"] as? String, !bundleIdentifier.isEmpty else {
            throw CloneError.missingBundleIdentifier(url)
        }

        return CloneApp(
            url: url,
            displayName: displayName(from: info, fallback: url.deletingPathExtension().lastPathComponent),
            bundleIdentifier: bundleIdentifier,
            sourceBundleIdentifier: info["WCSourceBundleIdentifier"] as? String,
            bundleVersion: bundleVersion(from: info),
            isManagedByWechatCloner: info["WCClonedBy"] as? String == "WechatCloner"
        )
    }

    func updateCloneInfo(at url: URL, request: CloneRequest, source: SourceApp) throws {
        let plistURL = infoPlistURL(for: url)
        guard let data = try? Data(contentsOf: plistURL),
              var info = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            throw CloneError.cannotReadInfoPlist(plistURL)
        }

        info["CFBundleIdentifier"] = request.bundleIdentifier
        info["CFBundleName"] = request.cloneName
        info["CFBundleDisplayName"] = request.cloneName
        info["WCSourceBundleIdentifier"] = source.bundleIdentifier
        info["WCSourcePath"] = source.url.path
        info["WCClonedBy"] = "WechatCloner"

        let output: Data
        do {
            output = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        } catch {
            throw CloneError.cannotWriteInfoPlist(plistURL)
        }

        do {
            try output.write(to: plistURL, options: .atomic)
        } catch {
            throw CloneError.cannotWriteInfoPlist(plistURL)
        }
    }

    func isAppBundle(_ url: URL) -> Bool {
        url.pathExtension == "app" && FileManager.default.fileExists(atPath: infoPlistURL(for: url).path)
    }

    private func readInfoPlist(in bundleURL: URL) throws -> [String: Any] {
        guard isAppBundle(bundleURL) else {
            throw CloneError.invalidAppBundle(bundleURL)
        }

        let plistURL = infoPlistURL(for: bundleURL)
        guard let data = try? Data(contentsOf: plistURL),
              let info = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            throw CloneError.cannotReadInfoPlist(plistURL)
        }

        return info
    }

    private func infoPlistURL(for bundleURL: URL) -> URL {
        bundleURL.appendingPathComponent("Contents/Info.plist")
    }

    private func displayName(from info: [String: Any], fallback: String) -> String {
        if let displayName = info["CFBundleDisplayName"] as? String, !displayName.isEmpty {
            return displayName
        }

        if let bundleName = info["CFBundleName"] as? String, !bundleName.isEmpty {
            return bundleName
        }

        return fallback
    }

    private func bundleVersion(from info: [String: Any]) -> String {
        if let shortVersion = info["CFBundleShortVersionString"] as? String, !shortVersion.isEmpty {
            return shortVersion
        }

        if let version = info["CFBundleVersion"] as? String, !version.isEmpty {
            return version
        }

        return "未知版本"
    }
}
