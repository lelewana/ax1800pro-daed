#!/usr/bin/env bash
#
# make defconfig 之后执行：确认关键配置没有被 kconfig 悄悄丢掉。
# 任何一个关键项缺失都会让 CI 直接失败，避免"编译成功但固件里没有 daed"。
#
set -uo pipefail

CFG=${1:-.config}
if [ ! -f "$CFG" ]; then
  echo "错误：找不到 $CFG" >&2
  exit 1
fi

fail=0

expect() { # expect <symbol> <value>
  local sym="$1" exp="$2" line
  if [ "$exp" = "n" ]; then
    # kconfig 对 n 的写法是 "# SYM is not set"，也可能整行不存在
    line=$(grep -E "^${sym}=" "$CFG" | tail -n1)
    if [ -z "$line" ]; then
      printf '  \033[32m✓\033[0m %s 已关闭\n' "$sym"
      return
    fi
    printf '  \033[31m✗\033[0m %s 期望关闭，实际=%s\n' "$sym" "$line"
    fail=1
    return
  fi
  line=$(grep -E "^${sym}=" "$CFG" | tail -n1)
  if [ "$line" = "${sym}=${exp}" ]; then
    printf '  \033[32m✓\033[0m %s\n' "$line"
  else
    printf '  \033[31m✗\033[0m %s 期望=%s 实际=%s\n' "$sym" "$exp" "${line:-<缺失>}"
    fail=1
  fi
}

expect_unset() { # expect_unset <symbol>
  local sym="$1" line
  line=$(grep -E "^${sym}=" "$CFG" | tail -n1)
  if [ -z "$line" ]; then
    printf '  \033[32m✓\033[0m %s 未启用\n' "$sym"
  else
    printf '  \033[31m✗\033[0m %s 不应启用，实际=%s\n' "$sym" "$line"
    fail=1
  fi
}

echo "== 目标平台 =="
expect CONFIG_TARGET_qualcommax_ipq60xx_DEVICE_jdcloud_re-ss-01 y
expect CONFIG_TARGET_PROFILE '"DEVICE_jdcloud_re-ss-01"'
expect CONFIG_TARGET_ARCH_PACKAGES '"aarch64_cortex-a53"'

echo "== 内核 eBPF/BTF =="
expect CONFIG_KERNEL_DEBUG_INFO y
expect CONFIG_KERNEL_DEBUG_INFO_BTF y
expect CONFIG_KERNEL_DEBUG_INFO_REDUCED n
expect CONFIG_KERNEL_BPF_EVENTS y
expect CONFIG_KERNEL_KPROBES y
expect CONFIG_KERNEL_XDP_SOCKETS y
expect CONFIG_KERNEL_CGROUP_BPF y

echo "== dae / daed =="
expect CONFIG_PACKAGE_dae y
expect CONFIG_PACKAGE_daed y
expect CONFIG_PACKAGE_luci-app-daede y
expect CONFIG_DAE_USE_KERNEL_BTF y
expect CONFIG_DAED_USE_KERNEL_BTF y
expect_unset CONFIG_DAED_USE_VMLINUX_BTF
expect_unset CONFIG_DAE_USE_VMLINUX_BTF

echo "== dae/daed 依赖 =="
expect CONFIG_PACKAGE_v2ray-geoip y
expect CONFIG_PACKAGE_v2ray-geosite y
expect CONFIG_PACKAGE_kmod-sched-bpf y
expect CONFIG_PACKAGE_kmod-veth y
expect CONFIG_PACKAGE_ca-bundle y

echo "== 内核分区填充尺寸（源码补丁） =="
if sed -n '/define Device\/jdcloud_re-ss-01/,/^TARGET_DEVICES += jdcloud_re-ss-01/p' \
     target/linux/qualcommax/image/ipq60xx.mk | grep -q 'KERNEL_SIZE := 12288k'; then
  printf '  \033[32m✓\033[0m KERNEL_SIZE := 12288k\n'
else
  printf '  \033[31m✗\033[0m KERNEL_SIZE 不是 12288k（factory.bin 偏移会错，刷机起不来）\n'
  fail=1
fi

if [ "$fail" != 0 ]; then
  echo ""
  echo "配置校验失败，终止构建。" >&2
  exit 1
fi

echo ""
echo "配置校验全部通过。"
