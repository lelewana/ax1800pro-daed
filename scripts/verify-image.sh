#!/usr/bin/env bash
#
# 编译完成后执行：确认产物真的能用（BTF / 包 / 12M 内核填充）。
# 用法：cd openwrt && bash ../scripts/verify-image.sh
#
set -uo pipefail

fail=0
TARGET_DIR="bin/targets/qualcommax/ipq60xx"

# ---------------------------------------------------------------------------
echo "== 1/4 镜像文件 =="
ls -lh "$TARGET_DIR" || true

FACTORY=$(ls "$TARGET_DIR"/*factory.bin 2>/dev/null | head -n1)
SYSUPGRADE=$(ls "$TARGET_DIR"/*sysupgrade.bin 2>/dev/null | head -n1)
MANIFEST=$(ls "$TARGET_DIR"/*.manifest 2>/dev/null | head -n1)

for f in "$FACTORY" "$SYSUPGRADE" "$MANIFEST"; do
  if [ -n "$f" ] && [ -s "$f" ]; then
    printf '  \033[32m✓\033[0m %s\n' "$f"
  else
    printf '  \033[31m✗\033[0m 缺失：%s\n' "${f:-factory/sysupgrade/manifest}"
    fail=1
  fi
done

# ---------------------------------------------------------------------------
echo "== 2/4 内核按 12M 填充（factory.bin 的前置条件） =="
if [ -n "$FACTORY" ]; then
  SIZE=$(stat -c%s "$FACTORY")
  LIMIT=$((12 * 1024 * 1024))
  if [ "$SIZE" -gt "$LIMIT" ]; then
    printf '  \033[32m✓\033[0m factory.bin %s 字节 > 12M(%s)，内核已按 12288k 填充\n' "$SIZE" "$LIMIT"
  else
    printf '  \033[31m✗\033[0m factory.bin 只有 %s 字节，未按 12M 填充\n' "$SIZE"
    fail=1
  fi
fi

echo "== 3/4 内核自带 BTF（dae/daed 的 CO-RE 前提） =="
VMLINUX=$(find build_dir -maxdepth 6 -name vmlinux -type f 2>/dev/null | head -n1)
if [ -n "$VMLINUX" ]; then
  echo "  找到 vmlinux: $VMLINUX ($(du -h "$VMLINUX" | cut -f1))"
  if readelf -S "$VMLINUX" 2>/dev/null | grep -q '\.BTF'; then
    printf '  \033[32m✓\033[0m 存在 .BTF 段\n'
  else
    printf '  \033[31m✗\033[0m vmlinux 没有 .BTF 段，daed 运行时会失败\n'
    fail=1
  fi
else
  printf '  \033[33m!\033[0m 未找到 vmlinux，跳过 BTF 段检查\n'
fi

echo "  内核镜像（FIT）尺寸："
find build_dir -maxdepth 6 -name '*.itb' -type f -printf '  %p  %s 字节\n' 2>/dev/null | head -n5 || true

# ---------------------------------------------------------------------------
echo "== 4/4 固件内已装包 =="
check_pkg() {
  local name="$1"
  if grep -qE "^${name} " "$MANIFEST" 2>/dev/null; then
    printf '  \033[32m✓\033[0m %s\n' "$(grep -E "^${name} " "$MANIFEST" | head -n1)"
  else
    printf '  \033[31m✗\033[0m %s 未打进固件\n' "$name"
    fail=1
  fi
}
check_pkg dae
check_pkg daed
check_pkg luci-app-daede
check_pkg v2ray-geoip
check_pkg v2ray-geosite
check_pkg kmod-sched-bpf

if [ "$fail" != 0 ]; then
  echo ""
  echo "产物校验失败。" >&2
  exit 1
fi

echo ""
echo "产物校验全部通过。"
