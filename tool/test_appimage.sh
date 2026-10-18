#!/usr/bin/env bash
# 在没有系统 GStreamer 的干净环境里验证发布的 AppImage。
#
# 关键点：容器里**故意不装 GStreamer**——装了就会掩盖"依赖没打进包"这个回归，
# 而那正是这个脚本要抓的东西。所有 GStreamer 库、编解码器与插件扫描器都必须来自
# AppImage 自己。
#
# 用法：bash tool/test_appimage.sh JO-AIClient-v<版本>-linux-x64-appimage.AppImage
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "用法：$0 <AppImage 文件>" >&2
  exit 1
fi

appimage="$(realpath "$1")"
gst_inspect="$(command -v gst-inspect-1.0)"

docker run --rm -i \
  --mount "type=bind,src=$appimage,dst=/tmp/JO-AIClient.AppImage,readonly" \
  --mount "type=bind,src=$gst_inspect,dst=/tmp/gst-inspect-1.0,readonly" \
  ubuntu:22.04 bash -s <<'CONTAINER'
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
# 只装桌面/显示相关依赖。**不要**在这里装 GStreamer——那会掩盖缺库回归。
# GTK 的 libepoxy 会动态加载 libGLESv2.so.2，只装 Mesa/EGL 提供不了它。
apt-get install -y --no-install-recommends \
  ca-certificates libgtk-3-0 libgl1-mesa-dri libegl1 libgles2 libasound2 \
  dbus-x11 xvfb xauth xdotool

cd /tmp
./JO-AIClient.AppImage --appimage-extract >/dev/null
export LIBGL_ALWAYS_SOFTWARE=1

# gst-inspect-1.0 来自构建机，但它用到的 GStreamer 库、编解码器与插件扫描器
# 必须全部来自这个容器里的 AppImage。
(
  export APPDIR=/tmp/squashfs-root
  export LD_LIBRARY_PATH="$APPDIR/usr/lib"
  # shellcheck disable=SC1091
  source "$APPDIR/apprun-hooks/linuxdeploy-plugin-gstreamer.sh"
  test -x "$GST_PLUGIN_SCANNER_1_0"
  scanner_dependencies="$(ldd "$GST_PLUGIN_SCANNER_1_0")"
  if grep -q 'not found' <<<"$scanner_dependencies"; then
    echo "$scanner_dependencies" >&2
    exit 1
  fi
  for element in appsrc appsink playbin decodebin audiopanorama autoaudiosink; do
    /tmp/gst-inspect-1.0 "$element" >/dev/null
  done
)

xvfb-run -a dbus-run-session -- bash -s <<'DISPLAY_TEST'
set -euo pipefail
# 启动真实产物，并且**不注入**任何库/插件的搜索路径。
/tmp/JO-AIClient.AppImage --appimage-extract-and-run >/tmp/jo_aiclient.log 2>&1 &
app_pid=$!
trap 'kill "$app_pid" 2>/dev/null || true' EXIT

# 必须真的出现窗口，并且在 30 秒内持续检查有没有提前退出（至少盯满 10 秒）。
for ((attempt = 1; attempt <= 30; attempt++)); do
  sleep 1
  if ! kill -0 "$app_pid" 2>/dev/null; then
    cat /tmp/jo_aiclient.log
    echo "启动检查完成前 JO-AIClient 就退出了" >&2
    exit 1
  fi
  if ((attempt >= 10)) && xdotool search --onlyvisible --class '[Jj][Oo][-_]?[Aa][Ii][Cc]lient' >/dev/null; then
    echo "AppImage 启动与 GStreamer 依赖检查通过"
    exit 0
  fi
done

cat /tmp/jo_aiclient.log
echo "30 秒内 JO-AIClient 没有出现窗口" >&2
exit 1
DISPLAY_TEST
CONTAINER
