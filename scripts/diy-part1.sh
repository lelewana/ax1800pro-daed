#!/usr/bin/env bash
#
# DIY 第一步：在 feeds update 之前执行
# 用法：cd openwrt && bash ../scripts/diy-part1.sh
#
# 做三件事：
#   1. 挂 kenzok8/openwrt-daede 源（dae / daed / luci-app-daede）
#   2. 落地 v2ray-geodata（dae、daed 的 DEPENDS 硬依赖 v2ray-geoip / v2ray-geosite，
#      openwrt 官方 packages 源里只有 v2ray-geodata，包名不匹配，必须补上）
#   3. 把 jdcloud_re-ss-01 的内核填充尺寸从 6144k 改成 12288k
#      —— 开启 DEBUG_INFO_BTF 后内核变大，且 HLOS12M 分区表的内核分区是 12M；
#         若仍按 6M 填充，factory.bin 里的 rootfs 会写在错误偏移，刷完必定起不来。
#
set -euo pipefail

SRC_DIR=$(pwd)
if [ ! -f "$SRC_DIR/rules.mk" ] || [ ! -d "$SRC_DIR/target/linux" ]; then
  echo "错误：请在 openwrt 源码根目录执行本脚本（当前：$SRC_DIR）" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
echo "==> 1/4 添加 dae/daed 第三方源"
FEEDS_FILE="$SRC_DIR/feeds.conf.default"
if ! grep -q 'openwrt-daede' "$FEEDS_FILE"; then
  echo 'src-git daede https://github.com/kenzok8/openwrt-daede.git;main' >> "$FEEDS_FILE"
fi
grep -n 'daede' "$FEEDS_FILE"

# ---------------------------------------------------------------------------
echo "==> 2/4 落地 v2ray-geodata（提供 v2ray-geoip / v2ray-geosite）"
GEO_DIR="$SRC_DIR/package/v2ray-geodata"
mkdir -p "$GEO_DIR"
if ! grep -qs 'BuildPackage,v2ray-geoip' "$GEO_DIR/Makefile"; then
  rm -f "$GEO_DIR/Makefile"
  ok=0
  for u in \
    "https://raw.githubusercontent.com/kenzok8/small/master/v2ray-geodata/Makefile" \
    "https://cdn.jsdelivr.net/gh/kenzok8/small@master/v2ray-geodata/Makefile" \
    "https://ghfast.top/https://raw.githubusercontent.com/kenzok8/small/master/v2ray-geodata/Makefile" \
    "https://gh-proxy.com/https://raw.githubusercontent.com/kenzok8/small/master/v2ray-geodata/Makefile"; do
    echo "  尝试拉取：$u"
    if curl -fsSL --retry 3 --retry-delay 2 --max-time 60 "$u" -o "$GEO_DIR/Makefile" 2>/dev/null \
       && grep -qs 'BuildPackage,v2ray-geoip' "$GEO_DIR/Makefile"; then
      ok=1
      break
    fi
  done
  if [ "$ok" != 1 ]; then
    echo "错误：v2ray-geodata/Makefile 拉取失败（dae/daed 将因缺依赖而无法打包）" >&2
    exit 1
  fi
fi
grep -n 'Package/v2ray-geoip\|Package/v2ray-geosite' "$GEO_DIR/Makefile"

# ---------------------------------------------------------------------------
echo "==> 3/4 把 jdcloud_re-ss-01 的内核分区填充尺寸改为 12288k"
python3 - "$SRC_DIR/target/linux/qualcommax/image/ipq60xx.mk" <<'PY'
import re, sys, pathlib

path = pathlib.Path(sys.argv[1])
src = path.read_text()
pattern = re.compile(
    r"(define Device/jdcloud_re-ss-01\b(?:.|\n)*?KERNEL_SIZE\s*:=\s*)6144k"
)
new, count = pattern.subn(r"\g<1>12288k", src)
if count != 1:
    sys.exit(f"错误：KERNEL_SIZE 补丁匹配到 {count} 处（预期 1 处），源码结构可能已变化")
path.write_text(new)
print("补丁完成：jdcloud_re-ss-01 KERNEL_SIZE 6144k -> 12288k")
PY

# ---------------------------------------------------------------------------
echo "==> 4/4 校验补丁结果"
sed -n '/define Device\/jdcloud_re-ss-01/,/^TARGET_DEVICES += jdcloud_re-ss-01/p' \
  "$SRC_DIR/target/linux/qualcommax/image/ipq60xx.mk"

if ! sed -n '/define Device\/jdcloud_re-ss-01/,/^TARGET_DEVICES += jdcloud_re-ss-01/p' \
     "$SRC_DIR/target/linux/qualcommax/image/ipq60xx.mk" | grep -q 'KERNEL_SIZE := 12288k'; then
  echo "错误：KERNEL_SIZE 补丁未生效" >&2
  exit 1
fi

echo "diy-part1 完成"
