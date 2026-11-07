#!/bin/zsh
set -euo pipefail
cd -- "${0:A:h}"
./build.sh
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' '.build/音频自动切换.app/Contents/Info.plist')
stage=$(mktemp -d "$PWD/.build/dmg.XXXXXX")
trap 'if [[ -d "$stage/音频自动切换.app" ]]; then /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$stage/音频自动切换.app" >/dev/null 2>&1 || true; fi; /bin/rm -rf -- "$stage"' EXIT
# Staging lives in a hidden build folder to avoid duplicate application icons.
ditto '.build/音频自动切换.app' "$stage/音频自动切换.app"
ln -s /Applications "$stage/Applications"
cat > "$stage/安装说明.txt" <<'TEXT'
安装方法

1. 将“音频自动切换”拖到 Applications（应用程序）。
2. 从“应用程序”中打开 App，后台服务会自动配置。
3. 拖动设备列表设置优先级，顺序自动保存。

首次安装无需安装开发工具，无需运行终端命令。
首次打开后会配置当前用户的登录后台项，系统可能通知你已有后台项。

这是 Apple Silicon 版本，最低 macOS 13。当前只在 macOS 27 上实测。
当前版本采用本地签名，尚未经过 Apple Developer ID 签名和 Apple 公证。
macOS 可能阻止首次运行，请仅在确认来源后，按系统“隐私与安全性”中的提示由你决定是否允许。

更新时先退出控制窗口，再将新版拖入“应用程序”替换旧版，打开新版即可迁移后台服务。
原有设备顺序会保留。

完全移除前，请在 App 的“音频自动切换”菜单中选择“停用并移除登录后台项”。
TEXT
mkdir -p artifacts
output="artifacts/AudioPriority-v${version}-macOS-arm64.dmg"
if [[ -e "$output" ]]; then
    echo "已存在 $output，请先归档旧安装包。" >&2
    exit 1
fi
hdiutil create -volname '音频自动切换' -srcfolder "$stage" -format UDZO -ov "$output"
hdiutil verify "$output"
shasum -a 256 "$output" | sed 's#  artifacts/#  #' > "$output.sha256"
echo "$output"
# Preserve a recoverable build archive, then remove the discoverable test bundle.
ditto -c -k --sequesterRsrc --keepParent '.build/音频自动切换.app' '.build/last-built-app.zip'
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$PWD/.build/音频自动切换.app" >/dev/null 2>&1 || true
/bin/rm -rf -- '.build/音频自动切换.app'
