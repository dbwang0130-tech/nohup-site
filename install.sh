#!/bin/sh
# UULink 一键安装（macOS）：curl -fsSL https://uulink.pro/install.sh | sh
#
# 下载最新版 DMG → 装进 /Applications → 打开 UULink，之后由 App 的设置向导带着配对手机。
# 用 curl 下载的文件不带隔离标记，不会弹「来自互联网」的拦截；包本身是 Developer ID 签名并公证过的，装前仍会校验签名。
# 手机端首页的「一条命令安装」卡片显示的就是这条命令（UULinkiOS/Home/SidebarView.swift）。
#
# 测试用环境变量（平时不用设）：
#   UULINK_DMG_URL   换下载地址或本地 DMG（file:///…）
#   UULINK_APP_DIR   换安装目录（默认 /Applications），测试时装到临时目录，免得动到正在跑的 UULink
#   UULINK_NO_OPEN=1 装完不打开、不退出正在运行的 UULink

set -eu

DMG_URL="${UULINK_DMG_URL:-https://nohup-web.oss-cn-beijing.aliyuncs.com/download/mac/UULink-latest.dmg}"
APP_DIR="${UULINK_APP_DIR:-/Applications}"
APP="$APP_DIR/UULink.app"
BUNDLE_ID="pro.uulink.mac"
TEAM_ID="586LZ975EV"

case "${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}" in
    zh*) ZH=1 ;;
    *) ZH=0 ;;
esac
# say 中文 English
say() { if [ "$ZH" = 1 ]; then printf '%s\n' "$1"; else printf '%s\n' "$2"; fi; }
fail() { say "错误：$1" "Error: $2" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || fail "这条命令只适用于 macOS。Windows 版请在浏览器打开 https://uulink.pro/get 下载。" \
    "This command is for macOS only. For Windows, download from https://uulink.pro/get in a browser."

major=$(sw_vers -productVersion | cut -d. -f1)
[ "$major" -ge 14 ] || fail "UULink 需要 macOS 14 或更新版本，这台 Mac 是 $(sw_vers -productVersion)。" \
    "UULink requires macOS 14 or later. This Mac is running $(sw_vers -productVersion)."

TMP=$(mktemp -d -t uulink-install)
MNT="$TMP/mnt"
cleanup() {
    [ -d "$MNT" ] && hdiutil detach -quiet "$MNT" 2>/dev/null || true
    rm -rf "$TMP"
}
trap cleanup EXIT INT TERM

say "正在下载 UULink…" "Downloading UULink…"
curl -fL --progress-bar -o "$TMP/UULink.dmg" "$DMG_URL" || fail "下载失败，请检查网络后重试。" "Download failed. Check your network and try again."

mkdir -p "$MNT"
hdiutil attach -quiet -nobrowse -readonly -noautoopen -mountpoint "$MNT" "$TMP/UULink.dmg" \
    || fail "无法打开下载的安装包。" "Could not open the downloaded disk image."
[ -d "$MNT/UULink.app" ] || fail "安装包里没有 UULink.app。" "UULink.app was not found in the disk image."

# 装之前先验签：必须是我们的 Developer ID 签名，且通过公证
codesign --verify --deep --strict "$MNT/UULink.app" 2>/dev/null \
    && codesign -dv "$MNT/UULink.app" 2>&1 | grep -q "TeamIdentifier=$TEAM_ID" \
    || fail "安装包签名校验未通过，已停止安装。" "The app's code signature could not be verified. Installation stopped."

# 按可执行文件路径找主进程：open 拉起的主进程用 pgrep -f 匹配不到
running() { ps -axo comm= | grep -qxF "$APP/Contents/MacOS/UULink"; }

if [ -z "${UULINK_NO_OPEN:-}" ] && running; then
    # 正在运行时替换包会让运行中的进程签名失效而崩溃，先正常退出
    say "正在退出运行中的 UULink…" "Quitting the running UULink…"
    osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
    i=0
    while running && [ $i -lt 20 ]; do sleep 0.5; i=$((i + 1)); done
    running && fail "UULink 没有退出，请在菜单栏里手动退出后重新运行这条命令。" \
        "UULink did not quit. Quit it from the menu bar and run this command again."
fi

say "正在安装到 ${APP_DIR}…" "Installing to ${APP_DIR}…"
SUDO=""
if [ ! -w "$APP_DIR" ] || { [ -e "$APP" ] && [ ! -w "$APP" ]; }; then
    say "需要管理员权限，请输入这台 Mac 的登录密码。" "Administrator access is required. Enter your Mac login password."
    SUDO="sudo"
fi
$SUDO rm -rf "$APP"
$SUDO ditto "$MNT/UULink.app" "$APP" || fail "复制到 $APP_DIR 失败。" "Could not copy UULink to $APP_DIR."

version=$(defaults read "$APP/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo "")
say "已安装 UULink ${version}。" "UULink ${version} installed."

if [ -z "${UULINK_NO_OPEN:-}" ]; then
    open "$APP"
    say "UULink 已在菜单栏打开，按向导操作，最后用手机扫码配对即可。" \
        "UULink is now open in the menu bar. Follow the setup guide, then scan the QR code with your iPhone to pair."
fi
