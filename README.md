# WechatCloner

本项目是一个无授权、无联网逻辑的 macOS SwiftUI 应用，用于创建本机 `.app` 分身。

## 机制

创建分身时会执行以下步骤：

1. 复制源 `.app` 到 `/Applications/<分身名>.app`
2. 修改 `Contents/Info.plist` 中的 `CFBundleIdentifier`、`CFBundleName`、`CFBundleDisplayName`
3. 写入 `WCSourceBundleIdentifier`、`WCSourcePath`、`WCClonedBy` 标记，供本工具识别
4. 执行 `xattr -cr <分身.app>`
5. 执行 `codesign --force --deep --sign - <分身.app>`
6. 启动时使用 `open -n <分身.app>`

## 备份和更新

选中分身后可以执行：

- `备份数据`：复制 `~/Library/Containers/<分身BundleID>` 到 `~/WechatClonerBackups/<分身BundleID>/<时间戳>/Container`。
- `更新`：只备份旧 `.app`，再用当前源应用重建分身，保持原 Bundle ID 不变。
- `备份并更新`：同时备份旧 `.app` 和数据容器，再用当前源应用重建分身，保持原 Bundle ID 不变。

左侧源应用会显示原版版本。右侧分身会显示分身版本、对应原版版本，并在分身版本低于原版版本时标记 `建议升级`。

更新失败时会尝试从备份目录恢复旧 `.app`。聊天数据容器不会被删除或覆盖。

## 使用

用 Xcode 打开：

```bash
open WechatCloner.xcodeproj
```

然后选择 `WechatCloner` scheme 运行。

## 打包

安装完整 Xcode 后执行：

```bash
scripts/package.sh
```

脚本会使用项目内 `.build/DerivedData` 作为临时构建目录，把最终产物输出到：

```text
dist/WechatCloner.app
dist/WechatCloner.zip
```

默认构建完成后会删除 `.build/DerivedData`，因此不会保留在 `/Library/Developer/Xcode/DerivedData` 或用户全局 DerivedData 目录。需要保留临时构建目录时执行：

```bash
scripts/package.sh --keep-build
```

指定架构和输出文件名：

```bash
scripts/package.sh --arch arm64 --zip-name WechatCloner-v1.0.0-arm64.zip
scripts/package.sh --arch x86_64 --zip-name WechatCloner-v1.0.0-x86_64.zip
```

## 发布

推送 `v*` tag 会触发 GitHub Actions，分别构建 Apple Silicon 和 Intel 版本，并创建 GitHub Release：

```bash
git tag -a v1.0.0 -m "WechatCloner v1.0.0"
git push origin v1.0.0
```

Release 会包含：

```text
WechatCloner-v1.0.0-arm64.zip
WechatCloner-v1.0.0-x86_64.zip
```

## 边界

- 不包含授权、激活、统计、更新或远程 API。
- 不注入、不 patch 二进制、不修改微信数据目录。
- 删除功能允许删除列表中的本工具分身和外部分身；原始微信/企业微信不会进入分身列表。
- 首版默认扫描 `/Applications/微信.app`、`/Applications/WeChat.app`、`/Applications/企业微信.app`、`/Applications/WeCom.app`，也支持手动选择其他 `.app`。
