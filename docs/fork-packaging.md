# Jovines/macshot 打包指引

本指引用于 [Jovines/macshot](https://github.com/Jovines/macshot) 的修改版。仓库的 `fork` remote 指向 Jovines，`origin` 指向上游。发布前用 `git remote -v` 核对仓库，用 `git rev-parse HEAD` 记录二进制对应的提交。

## 固定签名身份

当前安装版使用团队 `7437GDF3XU` 的 **Developer ID Application** 和应用标识 `com.sw33tlie.macshot.macshot`。常规更新保持这两项和 Developer ID 签名类型，macOS 才能将新构建识别为同一个应用并通常沿用录屏授权。每台新 Mac 仍须首次授权一次。上游正式版与这个 Fork 当前共用应用标识，切回上游时可能要重新授权。

```sh
security find-identity -v -p codesigning
```

本机登录钥匙串已有证书和私钥。换构建机时，从原钥匙串把这套身份导出为受密码保护的 `.p12`，再导入目标 Mac。单独下载的 `.cer` 没有私钥。若导入后没有有效身份，检查 Apple Developer ID G2 中间证书和私钥是否齐全。签名前可以用 `codesign -dr - /Applications/macshot.app` 核对已安装版的签名识别条件。

## 构建

有完整 Xcode 时，在仓库根目录构建 Release。最终签名由打包脚本统一完成。

```sh
build_dir=$(mktemp -d "${TMPDIR:-/tmp}/macshot-build.XXXXXX")
xcodebuild -project macshot.xcodeproj -scheme macshot -configuration Release \
  -destination 'platform=macOS' -derivedDataPath "$build_dir" \
  CODE_SIGNING_ALLOWED=NO build
app="$build_dir/Build/Products/Release/macshot.app"
```

这台 Mac 原先只有 Command Line Tools。可按 [预览版 3 的本机构建资料](https://github.com/Jovines/macshot/releases/tag/custom-4.5.0-preview.3) 中的 `macshot-local-build-files.zip` 复用 SwiftPM 构建路径。现有工作区中，仓库旁的 `local-build` 链接到当前 checkout，`macshot-custom.app` 是带已编译资源的暂存包。先同步当前 checkout 的 Swift 源文件清单和依赖版本，再运行 `swift build --package-path ../local-build -c release`。按资料中的 OCR 构建命令重编辅助程序，在 `bundle.py` 的本地副本里更新版本和源码提交后组装暂存包。把这个暂存包设为 `app`。旧组装脚本使用临时签名，因此必须继续执行下面的正式签名步骤。

## 签名并生成 ZIP

```sh
scripts/package-fork-preview.sh "$app" /absolute/path/macshot-custom-arm64.zip
```

脚本在临时目录中复制应用，从本机钥匙串选出团队的签名身份，依次签署 OCR、Sparkle 和主应用。它会设置安全时间戳并启用 hardened runtime，同时保留主应用的沙盒权限。打包后再解压校验签名，输出 SHA-256。应用包没有附带本机偏好和录屏权限。脚本会关闭上游自动检查更新，Fork 的版本通过自己的安装包更新。

钥匙串里如果有同一团队的多张有效证书，设置 `MACSHOT_SIGNING_IDENTITY` 为所选证书的 SHA-1 指纹。该指纹可用上面的 `security` 命令查看，私钥始终留在钥匙串。

公开分发时，先用 `xcrun notarytool store-credentials` 交互保存团队的公证凭据，再使用钥匙串配置名运行：

```sh
MACSHOT_NOTARY_PROFILE=macshot-fork \
  scripts/package-fork-preview.sh "$app" /absolute/path/macshot-custom-arm64.zip
```

脚本会等待 Apple 接受公证、装订票据并通过 Gatekeeper 检查。没有设置公证配置名时，产物是 **已签名、未公证** 的预览包。替换本机安装版前，先退出 macshot 并保留上一版安装包。安装后检查进程已启动，并核对 `codesign -dv --verbose=4 /Applications/macshot.app` 输出的签名团队。

发布到 Fork 时，用单独的 `custom-…` 预览标签，指向实际编译的提交。在 GitHub Releases 附上 ZIP、校验值和构建说明。不要用上游风格的 `v…` 标签触发继承来的正式发布流程。

## GitHub Actions

Fork 当前使用本机钥匙串做正式签名。继承来的 `.github/workflows/build-release.yml` 同时包含上游 Homebrew tap 和 Sparkle 更新源，因此它不能直接作为 Fork 的发行流程。

如果要迁移到 GitHub，先把 Fork 的工作流配置为手动运行、仅使用受保护的 GitHub Environment，并限制部署分支。签名阶段需要 `DEVELOPER_ID_CERT_P12` 和 `DEVELOPER_ID_CERT_PASSWORD` 两个 **Secrets**（加密 `.p12` 的 Base64 和密码），从临时钥匙串导入。公证另需本团队的 App Store Connect API 凭据（继承流程对应 `ASC_API_KEY`、`ASC_API_KEY_ID`、`ASC_API_ISSUER_ID`）。证书私钥、`.p12`、密码和公证密钥不得放入源码、日志或构建产物。Fork 的工作流仅需产出签名/公证包，不需要上游的 Homebrew token 或 Sparkle 私钥。
