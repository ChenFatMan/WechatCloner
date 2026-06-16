import AppKit
import SwiftUI

struct ContentView: View {
    @StateObject private var manager = CloneManager()
    @State private var selectedSource: SourceApp?
    @State private var selectedClone: CloneApp?
    @State private var cloneName = ""
    @State private var bundleIdentifier = ""
    @State private var isShowingImporter = false

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            HStack(spacing: 0) {
                sourcePanel
                    .frame(width: 330)

                Divider()

                clonePanel
            }

            Divider()

            statusBar
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            manager.refresh()
            selectFirstSourceIfNeeded()
        }
        .fileImporter(
            isPresented: $isShowingImporter,
            allowedContentTypes: [.application],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                manager.addSource(url: url)
                selectedSource = manager.sources.first { $0.url == url }
                updateDefaultsForSelection()
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("WechatCloner")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(Color(nsColor: .labelColor))

                Text("本地复制 .app、修改 Bundle ID、重新签名并启动。不含授权、注入或网络请求。")
                    .font(.system(size: 13))
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
            }

            Spacer()

            Button("重新扫描") {
                manager.refresh()
                selectFirstSourceIfNeeded()
            }
            .disabled(manager.isWorking)
        }
        .padding(24)
    }

    private var sourcePanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("源应用")
                    .font(.system(size: 18, weight: .semibold))

                Spacer()

                Button("选择 .app") {
                    isShowingImporter = true
                }
                .disabled(manager.isWorking)
            }

            if manager.sources.isEmpty {
                emptyState("未找到微信或企业微信", detail: "点击“选择 .app”手动添加源应用。")
            } else {
                List(manager.sources, selection: $selectedSource) { source in
                    SourceRow(source: source)
                        .tag(source)
                }
                .listStyle(.sidebar)
                .onChange(of: selectedSource) { _ in
                    updateDefaultsForSelection()
                }
            }

            cloneForm
        }
        .padding(20)
    }

    private var cloneForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("创建分身")
                .font(.system(size: 16, weight: .semibold))

            TextField("分身名称，例如 微信2", text: $cloneName)
                .textFieldStyle(.roundedBorder)

            TextField("Bundle ID，例如 com.tencent.xinWeChat.clone.wechat2", text: $bundleIdentifier)
                .textFieldStyle(.roundedBorder)

            Button {
                guard let selectedSource else { return }
                manager.createClone(
                    source: selectedSource,
                    cloneName: cloneName,
                    bundleIdentifier: bundleIdentifier
                )
            } label: {
                Text(manager.isWorking ? "处理中..." : "创建分身")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedSource == nil || cloneName.isEmpty || bundleIdentifier.isEmpty || manager.isWorking)
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var clonePanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("分身列表")
                    .font(.system(size: 18, weight: .semibold))

                Spacer()

                if let selectedClone {
                    Button("在 Finder 显示") {
                        NSWorkspace.shared.activateFileViewerSelecting([selectedClone.url])
                    }

                    Button("备份数据") {
                        manager.backupCloneData(selectedClone)
                    }
                    .disabled(manager.isWorking)

                    Button("更新") {
                        manager.updateClone(selectedClone)
                    }
                    .disabled(manager.isWorking)

                    Button("备份并更新") {
                        manager.backupAndUpdateClone(selectedClone)
                    }
                    .disabled(manager.isWorking)

                    Button("删除", role: .destructive) {
                        manager.remove(selectedClone)
                        self.selectedClone = nil
                    }
                    .disabled(manager.isWorking)

                    Button("启动") {
                        manager.launch(selectedClone)
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(manager.isWorking)
                }
            }

            if manager.clones.isEmpty {
                emptyState("还没有分身", detail: "从左侧选择源应用并创建一个新的 .app 分身。")
            } else {
                List(manager.clones, selection: $selectedClone) { clone in
                    CloneRow(clone: clone, versionStatus: manager.versionStatus(for: clone))
                        .tag(clone)
                }
                .listStyle(.inset)
            }
        }
        .padding(20)
    }

    private var statusBar: some View {
        HStack(spacing: 12) {
            if manager.isWorking {
                ProgressView()
                    .controlSize(.small)
            }

            Text(manager.errorMessage ?? manager.statusMessage)
                .foregroundStyle(manager.errorMessage == nil ? Color(nsColor: .secondaryLabelColor) : .red)
                .lineLimit(2)

            Spacer()
        }
        .font(.system(size: 13))
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private func emptyState(_ title: String, detail: String) -> some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
            Text(detail)
                .font(.system(size: 13))
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .multilineTextAlignment(.center)
    }

    private func selectFirstSourceIfNeeded() {
        if selectedSource == nil {
            selectedSource = manager.sources.first
            updateDefaultsForSelection()
        }
    }

    private func updateDefaultsForSelection() {
        guard let selectedSource else { return }
        let name = manager.suggestedCloneName(for: selectedSource)
        cloneName = name
        bundleIdentifier = manager.suggestedBundleIdentifier(for: selectedSource, cloneName: name)
    }
}

private struct SourceRow: View {
    let source: SourceApp

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(source.displayName)
                .font(.system(size: 14, weight: .semibold))
            Text(source.bundleIdentifier)
                .font(.system(size: 12))
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
            Text("原版版本：\(source.bundleVersion)")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color(nsColor: .labelColor))
            Text(source.url.path)
                .font(.system(size: 11))
                .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                .lineLimit(1)
        }
        .padding(.vertical, 4)
    }
}

private struct CloneRow: View {
    let clone: CloneApp
    let versionStatus: CloneVersionStatus

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: clone.url.path))
                .resizable()
                .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(clone.displayName)
                    .font(.system(size: 15, weight: .semibold))
                Text(clone.bundleIdentifier)
                    .font(.system(size: 12))
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                HStack(spacing: 8) {
                    Text("分身版本：\(clone.bundleVersion)")

                    if let sourceVersion = versionStatus.sourceVersion {
                        Text("原版版本：\(sourceVersion)")
                    }
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color(nsColor: .labelColor))
                Text(clone.url.path)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                    .lineLimit(1)
            }

            Spacer()

            Text(versionStatus.recommendation.title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(recommendationColor(versionStatus.recommendation))

            if !clone.isManagedByWechatCloner {
                Text("外部分身")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 6)
    }

    private func recommendationColor(_ recommendation: UpdateRecommendation) -> Color {
        switch recommendation {
        case .upToDate:
            .green
        case .upgradeRecommended:
            .orange
        case .sourceMissing:
            .red
        }
    }
}
