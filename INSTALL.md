# Installing Mneme on macOS

Mneme v0.1.0 is distributed as a free, ad-hoc signed macOS app. It is not notarized by Apple because notarization requires a paid Apple Developer Program account.

This means macOS may show a security warning the first time you open the app. This is expected for this release. You only need to approve the app once on your Mac.

## Install

1. Download `Mneme-v0.1.0-macos-arm64.dmg` from the [Releases](https://github.com/mjyang04/Mneme/releases) page.
2. Open the DMG file.
3. Drag `Mneme.app` into `Applications`.
4. Eject the DMG.

## First Launch

If double-clicking `Mneme.app` shows a warning, use this method:

1. Open Finder.
2. Go to `Applications`.
3. Right-click or Control-click `Mneme.app`.
4. Choose **Open**.
5. Confirm the macOS prompt.

If macOS still blocks the app:

1. Open **System Settings**.
2. Go to **Privacy & Security**.
3. Find the message about `Mneme.app`.
4. Click **Open Anyway**.
5. Open `Mneme.app` again.

After this first approval, Mneme should open normally.

## Why This Happens

macOS Gatekeeper checks downloaded apps. Apps distributed outside the Mac App Store normally need an Apple Developer ID signature and Apple notarization to open without this warning.

Mneme v0.1.0 is a free public build without Apple notarization. The app is still locally signed for bundle integrity, but macOS cannot identify it as a notarized app from a paid Apple Developer account.

## Safety Notes

- Download Mneme only from the official GitHub release page.
- Do not run copies from unknown mirrors.
- The release DMG has a SHA256 checksum listed in the release notes.
- Mneme stores its data locally and does not include cloud sync, analytics, or telemetry.

---

# macOS 安装说明

Mneme v0.1.0 是免费发布的 macOS 应用，使用 ad-hoc signing。它没有经过 Apple notarization，因为 notarization 需要付费 Apple Developer Program 账号。

因此，macOS 首次打开时可能会显示安全提示。这是当前版本的预期现象。你只需要在自己的 Mac 上批准一次。

## 安装

1. 从 [Releases](https://github.com/mjyang04/Mneme/releases) 页面下载 `Mneme-v0.1.0-macos-arm64.dmg`。
2. 打开 DMG 文件。
3. 将 `Mneme.app` 拖入 `Applications`。
4. 推出 DMG。

## 首次启动

如果双击 `Mneme.app` 时出现安全提示，请使用下面的方法：

1. 打开 Finder。
2. 进入 `Applications`。
3. 右键点击，或按住 Control 点击 `Mneme.app`。
4. 选择 **Open/打开**。
5. 确认 macOS 弹出的提示。

如果 macOS 仍然阻止打开：

1. 打开 **System Settings/系统设置**。
2. 进入 **Privacy & Security/隐私与安全性**。
3. 找到关于 `Mneme.app` 的提示。
4. 点击 **Open Anyway/仍要打开**。
5. 再次打开 `Mneme.app`。

完成这一次批准后，Mneme 之后通常可以正常打开。

## 为什么会这样

macOS Gatekeeper 会检查从网络下载的应用。Mac App Store 之外分发的应用，通常需要 Apple Developer ID 签名和 Apple notarization，才能在首次打开时不显示这类警告。

Mneme v0.1.0 是免费公开构建，没有 Apple notarization。应用仍然做了本地签名以保证 bundle 结构完整，但 macOS 无法把它识别为来自付费 Apple Developer 账号的 notarized app。

## 安全建议

- 只从官方 GitHub release 页面下载 Mneme。
- 不要运行未知镜像来源的副本。
- Release notes 中会列出 DMG 的 SHA256 校验值。
- Mneme 的数据保存在本机，不包含云同步、分析统计或遥测。
