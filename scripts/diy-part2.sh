#!/usr/bin/env bash
#
# DIY 第二步：在 feeds update/install 之后、make defconfig 之前执行
# 用法：cd openwrt && bash ../scripts/diy-part2.sh
#
# 做三件事：
#   1. 写入首次启动脚本，把固件默认配成"旁路由"（LAN 静态 IP + 关 DHCP）
#   2. 附带一个改 LAN 网段的小工具，方便换主路由网段
#   3. 定制主机名 / 时区 / 默认中文 / root 初始密码
#
set -euo pipefail

SRC_DIR=$(pwd)
if [ ! -f "$SRC_DIR/rules.mk" ]; then
  echo "错误：请在 openwrt 源码根目录执行本脚本（当前：$SRC_DIR）" >&2
  exit 1
fi

FILES_DIR="$SRC_DIR/files"
mkdir -p "$FILES_DIR/etc/uci-defaults" "$FILES_DIR/usr/sbin"

# ---------------------------------------------------------------------------
echo "==> 1/3 写入旁路由默认配置（首次启动执行一次）"
cat > "$FILES_DIR/etc/uci-defaults/99-ax1800pro-bypass" <<'EOF'
#!/bin/sh
# 京东云亚瑟 AX1800 Pro 旁路由默认值
# 需要改网段：ssh 登录后执行 set-lan-ip <本机IP> <主路由IP>
[ -n "$IPKG_INSTROOT" ] && exit 0

# root 初始密码 password（首次登录后请立刻修改）
( echo "password"; echo "password" ) | passwd root >/dev/null 2>&1

uci -q set system.@system[0].hostname='ax1800pro'
uci -q set system.@system[0].timezone='CST-8'
uci -q set system.@system[0].zonename='Asia/Shanghai'
uci -q set system.ntp.enabled='1'
uci -q set luci.main.lang='zh_cn'

# --- 旁路由网络：与主路由同网段，网关/DNS 指向主路由 ---
uci -q set network.lan.proto='static'
uci -q set network.lan.ipaddr='192.168.1.2'
uci -q set network.lan.netmask='255.255.255.0'
uci -q set network.lan.gateway='192.168.1.1'
uci -q set network.lan.dns='192.168.1.1'
uci -q set network.lan.delegate='0'
uci -q delete network.lan.ip6assign
uci -q delete network.lan.ip6ifaceid

# --- 关闭本机 DHCP / RA，避免和主路由抢地址池 ---
uci -q set dhcp.lan.ignore='1'
uci -q delete dhcp.lan.dhcpv4
uci -q delete dhcp.lan.dhcpv6
uci -q delete dhcp.lan.ra
uci -q delete dhcp.lan.ra_flags

# --- dnsmasq 放宽：旁路由只做转发，不做权威/防重绑 ---
uci -q set dhcp.@dnsmasq[0].domainneeded='0'
uci -q set dhcp.@dnsmasq[0].boguspriv='0'
uci -q set dhcp.@dnsmasq[0].rebind_protection='0'
uci -q set dhcp.@dnsmasq[0].localise_queries='0'

uci commit
/etc/init.d/daed enable >/dev/null 2>&1
exit 0
EOF
chmod 0755 "$FILES_DIR/etc/uci-defaults/99-ax1800pro-bypass"

# ---------------------------------------------------------------------------
echo "==> 2/3 写入 set-lan-ip 小工具"
cat > "$FILES_DIR/usr/sbin/set-lan-ip" <<'EOF'
#!/bin/sh
# 用法: set-lan-ip <本机IP> [主路由网关]
# 例：  set-lan-ip 192.168.31.2 192.168.31.1
[ -z "$1" ] && { echo "用法: set-lan-ip <本机IP> [主路由网关]"; exit 1; }
IP="$1"
GW="${2:-$(echo "$IP" | awk -F. '{print $1"."$2"."$3".1"}')"

uci set network.lan.proto='static'
uci set network.lan.ipaddr="$IP"
uci set network.lan.netmask='255.255.255.0'
uci set network.lan.gateway="$GW"
uci set network.lan.dns="$GW"
uci commit network
/etc/init.d/network restart

echo "LAN 已改为 $IP，网关/DNS = $GW"
echo "请用 http://$IP 重新访问（本机 DHCP 保持关闭）"
EOF
chmod 0755 "$FILES_DIR/usr/sbin/set-lan-ip"

# ---------------------------------------------------------------------------
echo "==> 3/3 展示将要打包进固件的自定义文件"
find "$FILES_DIR" -type f -printf '%m %p\n'

echo "diy-part2 完成"
