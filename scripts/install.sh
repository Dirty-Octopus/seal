#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="${1:-$ROOT/dist/Seal.app}"
DEST="/Applications/Seal.app"

if [ ! -d "$SOURCE" ]; then
    echo "找不到应用：$SOURCE" >&2
    exit 1
fi

if [ "$DEST" != "/Applications/Seal.app" ]; then
    echo "拒绝安装到意外路径：$DEST" >&2
    exit 1
fi

# 1) 先尝试普通复制。绝不默认使用 sudo。
if rm -rf "$DEST" 2>/dev/null && /usr/bin/ditto "$SOURCE" "$DEST" 2>/dev/null; then
    echo "Installed without elevation: $DEST"
    exit 0
fi

# 2) 权限不足时，才通过 macOS 系统认证弹窗申请管理员权限。
#    不使用 sudo，也不在终端里索要密码。
echo "需要管理员权限，正在打开 macOS 系统认证窗口…"
/usr/bin/osascript \
    -e 'on run argv' \
    -e 'set src to item 1 of argv' \
    -e 'set dst to item 2 of argv' \
    -e 'do shell script "/bin/rm -rf " & quoted form of dst & " && /usr/bin/ditto " & quoted form of src & " " & quoted form of dst with administrator privileges with prompt "Seal 需要管理员权限来安装到 /Applications。"' \
    -e 'end run' \
    "$SOURCE" "$DEST"

echo "Installed with administrator approval: $DEST"
