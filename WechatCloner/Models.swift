import Foundation

enum CloneError: LocalizedError {
    case sourceNotFound(URL)
    case invalidAppBundle(URL)
    case targetAlreadyExists(URL)
    case cannotReadInfoPlist(URL)
    case cannotWriteInfoPlist(URL)
    case missingBundleIdentifier(URL)
    case invalidCloneName
    case invalidBundleIdentifier(String)
    case sourceForCloneNotFound(String)
    case appBackupMissing(URL)
    case shellFailed(command: String, status: Int32, output: String)
    case deleteRefused(URL)

    var errorDescription: String? {
        switch self {
        case .sourceNotFound(let url):
            "找不到源应用：\(url.path)"
        case .invalidAppBundle(let url):
            "不是有效的 .app 应用包：\(url.path)"
        case .targetAlreadyExists(let url):
            "目标应用已存在，请换一个名称：\(url.path)"
        case .cannotReadInfoPlist(let url):
            "无法读取 Info.plist：\(url.path)"
        case .cannotWriteInfoPlist(let url):
            "无法写入 Info.plist：\(url.path)"
        case .missingBundleIdentifier(let url):
            "源应用缺少 CFBundleIdentifier：\(url.path)"
        case .invalidCloneName:
            "分身名称不能为空"
        case .invalidBundleIdentifier(let bundleIdentifier):
            "Bundle ID 不合法：\(bundleIdentifier)"
        case .sourceForCloneNotFound(let bundleIdentifier):
            "找不到分身对应的源应用：\(bundleIdentifier)"
        case .appBackupMissing(let url):
            "旧 App 备份不存在，无法回滚：\(url.path)"
        case .shellFailed(let command, let status, let output):
            "\(command) 执行失败，退出码 \(status)：\(output)"
        case .deleteRefused(let url):
            "拒绝删除非本工具创建的分身：\(url.path)"
        }
    }
}

struct SourceApp: Identifiable, Hashable, Sendable {
    let url: URL
    let displayName: String
    let bundleIdentifier: String
    let bundleVersion: String

    var id: String { url.path }
}

struct CloneApp: Identifiable, Hashable, Sendable {
    let url: URL
    let displayName: String
    let bundleIdentifier: String
    let sourceBundleIdentifier: String?
    let bundleVersion: String
    let isManagedByWechatCloner: Bool

    var id: String { url.path }
}

enum UpdateRecommendation: String, Sendable {
    case upToDate
    case upgradeRecommended
    case sourceMissing

    var title: String {
        switch self {
        case .upToDate:
            "已是最新"
        case .upgradeRecommended:
            "建议升级"
        case .sourceMissing:
            "找不到源"
        }
    }
}

struct CloneVersionStatus: Sendable {
    let sourceVersion: String?
    let recommendation: UpdateRecommendation
}

struct CloneRequest: Sendable {
    let sourceURL: URL
    let cloneName: String
    let bundleIdentifier: String
}

struct BackupResult: Sendable {
    let directory: URL
    let containerBackupURL: URL?
    let appBackupURL: URL?
}

struct CloneUpdatePlan: Sendable {
    let clone: CloneApp
    let source: SourceApp
    let cloneName: String
}

enum KnownApp {
    static let candidates: [URL] = [
        URL(fileURLWithPath: "/Applications/微信.app"),
        URL(fileURLWithPath: "/Applications/WeChat.app"),
        URL(fileURLWithPath: "/Applications/企业微信.app"),
        URL(fileURLWithPath: "/Applications/WeCom.app")
    ]

    static let supportedBundlePrefixes = [
        "com.tencent.xinWeChat",
        "com.tencent.WeWorkMac"
    ]

    static let sourceBundleIdentifiers = [
        "com.tencent.xinWeChat",
        "com.tencent.WeWorkMac"
    ]

    static func sourceBundleIdentifier(for cloneBundleIdentifier: String) -> String? {
        if cloneBundleIdentifier.hasPrefix("com.tencent.xinWeChat") {
            return "com.tencent.xinWeChat"
        }

        if cloneBundleIdentifier.hasPrefix("com.tencent.WeWorkMac") {
            return "com.tencent.WeWorkMac"
        }

        return nil
    }
}
