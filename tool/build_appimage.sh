#!/usr/bin/env bash
# 把 Flutter 的 Linux 产物打成 AppImage，并把它的原生运行时依赖一并装进包里。
#
# 为什么需要这个脚本：只把 Flutter 的 bundle 塞进 AppImage，运行时仍会用**用户机器上**的
# 库（GStreamer 等）。用户那边缺库或缺插件时，表现为启动失败、或音频相关功能不可用。
# 这里用 linuxdeploy 扫描 AppDir 里的每个 ELF（含 Flutter 插件与原生资源），并由
# gstreamer 插件把动态加载的编解码器与 gst-plugin-scanner 复制进包，同时安装指向这些
# 副本的 AppRun hook。
#
# 用法：bash tool/build_appimage.sh build/linux/x64/release/bundle "$VERSION"
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "用法：$0 <Flutter 产物目录> <版本号>" >&2
  exit 1
fi

bundle_dir="$(realpath "$1")"
version="$2"
arch="$(uname -m)"
case "$arch" in
  x86_64|aarch64) ;;
  *) echo "不支持的 AppImage 架构：$arch" >&2; exit 1 ;;
esac

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output="$PWD/JO-AIClient-v${version}-linux-x64-appimage.AppImage"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT
app_dir="$work_dir/AppDir"

mkdir -p "$app_dir/usr/bin"
cp -a "$bundle_dir/." "$app_dir/usr/bin/"
# linuxdeploy 要求库放在 usr/lib；而 Flutter 会按可执行文件的相对路径去找 lib/libapp.so。
# 所以把 lib 挪到 usr/lib，再用软链把那一路径保留下来，避免同一个库存两份。
mv "$app_dir/usr/bin/lib" "$app_dir/usr/lib"
ln -s ../lib "$app_dir/usr/bin/lib"

cat > "$work_dir/jo_aiclient.desktop" <<'DESKTOP'
[Desktop Entry]
Name=JO-AIClient
Exec=jo_aiclient
Icon=jo_aiclient
Type=Application
Categories=Utility;
DESKTOP
dart run "$repo_root/tool/prepare_appimage_icon.dart" \
  "$repo_root/assets/app_icon.png" "$work_dir/jo_aiclient.png"

curl -fL --retry 3 -o "$work_dir/linuxdeploy.AppImage" \
  "https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-${arch}.AppImage"
curl -fL --retry 3 -o "$work_dir/appimagetool.AppImage" \
  "https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-${arch}.AppImage"
# 插件来源钉死到具体提交：它以后改了复制规则，我们必须显式跟一次，而不是被悄悄改掉。
curl -fL --retry 3 -o "$work_dir/linuxdeploy-plugin-gstreamer.sh" \
  "https://raw.githubusercontent.com/linuxdeploy/linuxdeploy-plugin-gstreamer/2a2e67491c32995a3f279ad0ecbe77abd512b42a/linuxdeploy-plugin-gstreamer.sh"
chmod +x "$work_dir/"*.AppImage "$work_dir/linuxdeploy-plugin-gstreamer.sh"

# CI 里没有 FUSE，用解包运行；并保留 Flutter 已经处理过的产物，不要再 strip 一遍。
export APPIMAGE_EXTRACT_AND_RUN=1
export NO_STRIP=1
export ARCH="$arch"
export VERSION="$version"

# 这一步会扫描 AppDir 里的每个 ELF；gstreamer 插件同时把动态加载的编解码器
# 与 gst-plugin-scanner 复制进包，并写入选择这些副本的 AppRun hook。
"$work_dir/linuxdeploy.AppImage" --appdir "$app_dir" \
  --desktop-file "$work_dir/jo_aiclient.desktop" \
  --icon-file "$work_dir/jo_aiclient.png" \
  --plugin gstreamer

# gstreamer 插件是在它自己的依赖扫描之后才复制那些辅助可执行文件的，
# 所以要再跑一遍把它们的依赖补齐，然后才出最终产物。
"$work_dir/linuxdeploy.AppImage" --appdir "$app_dir"

"$work_dir/appimagetool.AppImage" "$app_dir" "$output"
echo "已生成 $output"
