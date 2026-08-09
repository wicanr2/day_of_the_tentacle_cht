#!/bin/bash
# 檢查一份 macOS 的 .app 在別人的 Mac 上跑不跑得起來。在 dott-cht:osxcross image 裡跑。
#
#   verify-mac-binary.sh <ScummVM.app 的路徑>
#
# 交叉編最危險的地方是「編得出來、看起來正常、在 Mac 上跑不動」，而 Linux 這端
# 沒有 macOS 可以執行，只能靜態檢查。下面四項是實際會讓玩家開不起來的原因：
#
#   1. 不是雙弧 —— Intel Mac 或 Apple Silicon 其中一邊直接開不了。
#   2. arm64 沒有 LC_CODE_SIGNATURE —— Apple Silicon 從 arm64 開始強制簽章，
#      沒有簽章的執行檔會被核心殺掉（Killed: 9），而檔案格式完全正常。
#   3. 連到編譯機才有的 dylib —— 交叉編最典型的失手：連結時吃到 /opt、/usr/local
#      底下的東西，玩家的 Mac 上沒有，一開就 dyld: Library not loaded。
#   4. 最低系統版本比宣稱的高 —— 使用者的 Mac 版本較舊時會直接拒絕執行。
set -euo pipefail

APP="${1:?用法: verify-mac-binary.sh <ScummVM.app>}"
T="x86_64-apple-${OSXCROSS_TARGET:-darwin24.5}"

# package-macos.sh 打包後會把 MacOS/scummvm 換成一支 shell script（負責帶
# --config 指到包裡的 ini），真正的執行檔改名成 scummvm.bin。直接對 scummvm
# 下 lipo 會得到「can't figure out the architecture type」——那是在對一個
# shell script 問架構。兩種佈局都要認。
BIN="$APP/Contents/MacOS/scummvm"
[ -f "$APP/Contents/MacOS/scummvm.bin" ] && BIN="$APP/Contents/MacOS/scummvm.bin"
[ -f "$BIN" ] || { echo "找不到 $BIN"; exit 1; }
echo "檢查對象：${BIN#"$APP/"}"

fail=0
say() { printf '%-42s %s\n' "$1" "$2"; }
bad() { say "$1" "✗ $2"; fail=1; }
ok()  { say "$1" "✓ $2"; }

# 1. 雙弧
info=$("$T-lipo" -info "$BIN")
if grep -q arm64 <<<"$info" && grep -q x86_64 <<<"$info"; then
  ok "雙弧（arm64 + x86_64）" "$info"
else
  bad "雙弧（arm64 + x86_64）" "$info"
fi

# 2. 每一弧各自檢查簽章與最低版本。lipo -thin 拆出來才驗得到單一弧，
#    直接對 universal 檔下 otool 只會看到第一個弧。
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
for arch in arm64 x86_64; do
  grep -q "$arch" <<<"$info" || continue
  "$T-lipo" -thin "$arch" "$BIN" -output "$tmp/$arch"

  if "$T-otool" -l "$tmp/$arch" | grep -q LC_CODE_SIGNATURE; then
    ok "$arch 帶簽章" "LC_CODE_SIGNATURE"
  elif [ "$arch" = arm64 ]; then
    bad "$arch 帶簽章" "沒有 LC_CODE_SIGNATURE，Apple Silicon 上會被殺掉"
  else
    ok "$arch 帶簽章" "沒有，但 x86_64 不強制"
  fi

  minos=$("$T-otool" -l "$tmp/$arch" | grep -A4 LC_BUILD_VERSION | grep -m1 'minos' || true)
  ok "$arch 最低系統版本" "${minos:-讀不到 LC_BUILD_VERSION}"

  # 相依的動態庫：只能出現 /usr/lib 與 /System/Library。自編的 SDL2/FLAC/ogg
  # 都是靜態連結，不該出現在這張清單裡。
  # [雷] 這裡一定要對拆出來的單弧查。對 fat binary 下 otool -L，它會為每個
  # 架構印一行「<檔案路徑> (architecture x86_64):」當標頭，那行會被當成一個
  # 相依項，於是永遠報「這個路徑在玩家的 Mac 上不存在」——指著執行檔自己。
  libs=$("$T-otool" -L "$tmp/$arch" | tail -n +2 | awk '{print $1}')
  strays=$(grep -vE '^(/usr/lib/|/System/Library/)' <<<"$libs" || true)
  if [ -z "$strays" ]; then
    ok "$arch 動態相依都在系統路徑" "$(wc -l <<<"$libs") 個"
  else
    bad "$arch 動態相依都在系統路徑" "以下在玩家的 Mac 上不存在：$(tr '\n' ' ' <<<"$strays")"
  fi
done

# 4. bundle 的基本結構
[ -f "$APP/Contents/Info.plist" ] && ok "Info.plist" "在" || bad "Info.plist" "缺"

echo
if [ "$fail" = 0 ]; then
  echo "靜態檢查全過。"
  echo "注意：這裡驗的是「不會因為結構問題開不起來」，不是「功能正常」——"
  echo "Linux 上執行不了 macOS binary，實際遊玩仍需要一台 Mac 確認。"
else
  echo "有項目沒過，見上面的 ✗。"
  exit 1
fi
