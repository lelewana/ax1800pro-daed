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
  line=$(grep -E "^${sym}=" "$CFG" | tail -n1)
  if [ "$exp" = "n" ]; then
    # kconfig 对 n 的写法是 "# SYM is not set"，也可能整行不存在
    if [ -z "$line" ]; then
      printf '  [OK] %s 已关闭\n' "$sym"
      return
    fi
    printf '  [FAIL] %s 期望关闭，实际=%s\n' "$sym" "$line"
    fail=1
    return
  fi
  if [ "$line" = "${sym}=${exp}" ]; then
    printf '  [OK] %s\n' "$line"
  else
    printf '  [FAIL] %s 期望=%s 实际=%s\n' "$sym" "$exp" "${line:-<缺失>}"
    fail=1
  fi
}

expect_unset() { # expect_unset <symbol>
  local sym="$1" line
  line=$(grep -E "^${sym}=" "$CFG" | tail -n1)
  if [ -z "$line" ]; then
    printf '  [OK] %s 未启用\n' "$sym"
  else
    printf '  [FAIL] %s 不应启用，实际=%s\n' "$sym" "$line"
    fail=1
  fi
}

# ---------------------------------------------------------------------------
# CI：CONFIG_BPF_TOOLCHAIN_HOST=y 时 include/bpf.mk 通过 PATH 查找无版本号的
# clang / llc / opt / llvm-strip。Ubuntu 24.04 的 clang 元包常只提供
# clang-18 / llvm-strip-18 等带版本号二进制，这里补齐 llvm/lld 并建软链；
# 缺任何一个都提前终止，避免编译到一半才报 /invalid/clang。
# 仅在 GitHub Actions runner 中生效，不影响本地手工核对配置。
# ---------------------------------------------------------------------------
if [ "${CI:-}" = "true" ] && command -v sudo >/dev/null 2>&1; then
  if ! command -v llvm-strip >/dev/null 2>&1 || ! command -v llc >/dev/null 2>&1; then
    sudo apt-get update -qq
    sudo DEBIAN_FRONTEND=noninteractive apt-get -y -qq install llvm lld bc cpio python3-docutils
  fi
  LLVM_VER=$(clang --version | grep -oE '[0-9]+' | head -n1)
  for t in clang llc opt llvm-strip llvm-dis llvm-objcopy ld.lld; do
    if ! command -v "$t" >/dev/null 2>&1 && [ -n "$LLVM_VER" ] && command -v "${t}-${LLVM_VER}" >/dev/null 2>&1; then
      sudo ln -s "$(command -v "${t}-${LLVM_VER}")" "/usr/local/bin/$t"
    fi
  done
fi

echo "== 宿主 eBPF 工具链 =="
for t in clang llc opt llvm-strip; do
  tool_path=$(command -v "$t" || true)
  if [ -n "$tool_path" ]; then
    printf '  [OK] %-12s %s\n' "$t" "$tool_path"
  else
    printf '  [FAIL] %-12s 缺失（bpf.mk 需要无版本号二进制）\n' "$t"
    fail=1
  fi
done

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

echo "== eBPF 工具链（宿主 LLVM，避免 /invalid/clang） =="
expect CONFIG_DEVEL y
expect CONFIG_BPF_TOOLCHAIN_HOST y
expect CONFIG_USE_LLVM_HOST y
expect_unset CONFIG_USE_LLVM_BUILD
expect_unset CONFIG_USE_LLVM_PREBUILT

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
if grep -A40 'define Device/jdcloud_re-ss-01' \
     target/linux/qualcommax/image/ipq60xx.mk | grep -q 'KERNEL_SIZE := 12288k'; then
  printf '  [OK] KERNEL_SIZE := 12288k\n'
else
  printf '  [FAIL] KERNEL_SIZE 不是 12288k（factory.bin 偏移会错，刷机起不来）\n'
  fail=1
fi

if [ "$fail" != 0 ]; then
  echo ""
  echo "配置校验失败，终止构建。" >&2
  exit 1
fi

echo ""
echo "配置校验全部通过。"
