# 京东云亚瑟 AX1800 Pro · 2G 分区 + dae/daed 旁路由固件（云编译）

本仓库是 **GitHub Actions 云编译脚手架**，不是 fanchmwrt 源码本身。它按固定配方产出
**`jdcloud,re-ss-01`（京东云无线宝亚瑟 AX1800 Pro / IPQ6000）** 的一体化旁路由固件。

| 项目 | 取值 |
|---|---|
| 目标设备 | `qualcommax / ipq60xx / DEVICE_jdcloud_re-ss-01` |
| 内存 | **1GB**（硬改机型；固件侧不写 DTS 内存节点，容量由 uboot 按 CDT 上报） |
| 分区 | **rootfs 2048M + HLOS 12M**（对应 `gpt-JDC_AX1800_Pro_dual-boot_rootfs2048M_HLOS12M_no-last-partition.bin`） |
| 代理 | **dae + daed** 双内核 + **luci-app-daede** 界面 |
| 内核 | 已开 `DEBUG_INFO_BTF / BPF_EVENTS / XDP_SOCKETS`，内核按 **12288k** 填充 |
| 默认形态 | **旁路由**：LAN `192.168.1.2`，网关/DNS `192.168.1.1`，DHCP 关闭 |
| 源码 | `fanchmwrt/fanchmwrt-snapshot` @ `fanchmwrt-26.11`（snapshot，非稳定版） |

## 目录结构

```
.github/workflows/build.yml       云编译工作流
config/ax1800pro-2g-daed.config   .config 基底（目标 + daed + 内核 BTF）
scripts/diy-part1.sh              挂 daede 源 / 补 v2ray-geodata / 内核分区改 12M
scripts/diy-part2.sh              旁路由默认值、改网段工具、主机名时区
scripts/verify-config.sh          defconfig 后校验关键项，缺失即失败
scripts/verify-image.sh           产物校验（12M 填充 / .BTF 段 / 已装包）
```

## 触发方式

| 触发 | 是否构建 |
|---|---|
| Actions → `Build AX1800 Pro 2G daed` → **Run workflow** | ✅ 强制构建 |
| push 修改 `config/`、`scripts/`、workflow 本身 | ✅ 构建（便于验证改动） |
| 每天 03:17（北京时间）定时 | 上游有新提交才构建，同 SHA 已有 Release 则跳过 |
| 只改 `README.md` | ❌ 不触发 |

构建成功后自动发布 **Release**，tag 形如 `v20261108-abc1234`（日期 + 上游短 SHA），
Actions 底部同时保留 Artifact。产物：

- `*squashfs-factory.bin` —— **首次刷机**，走 uboot `/big.html`
- `*squashfs-sysupgrade.bin` —— 已在 fanchmwrt 上时页面/命令行升级
- `*.manifest`、`sha256sums`、`profiles.json`

> dae/daed 本体已内置固件，**不需要再装 run 包或 apk**。

## 刷机顺序（顺序错会砖）

0. **备份**（原系统 SSH，先做，必须有本地副本）
   ```sh
   dd if=/dev/mmcblk0p15 of=/tmp/art_backup.img bs=512      # ART 无线校准，最要紧
   dd if=/dev/mmcblk0p13 of=/tmp/appsbl_backup.img bs=512   # 主 uboot
   dd if=/dev/mmcblk0p14 of=/tmp/appsbl1_backup.img bs=512  # uboot 备份
   ```
1. **刷 12M 内核 uboot**：先刷支持 12M 内核的 `u-boot.bin`（主备两个分区都刷），
   否则 `http://192.168.1.1/big.html` 打不开，12M 内核固件无法引导。
2. **刷 GPT 分区表**：`http://192.168.1.1/img.html` 上传
   `gpt-JDC_AX1800_Pro_dual-boot_rootfs2048M_HLOS12M_no-last-partition.bin`。
   - 若分区表是 1024M 版本，本固件同样可用（rootfs 更小而已），但**不要混用 512M 版本**。
3. **1G 内存机型刷 1G CDT**：`http://192.168.1.1/cdt.html` 刷
   `cdt-Arthur_1G_DDR3.bin`（或 `dd if=... of=/dev/mmcblk0p10`）。
   不刷 CDT 只会认出 512MB，固件本身没问题但内存浪费一半。
4. **刷 factory 固件**：`http://192.168.1.1/big.html`（**不是**首页 `/`）上传
   `*squashfs-factory.bin`。亚瑟是双启动分区，若刷完仍进旧系统，在 uboot 首页切换
   `boot partition` 后再刷一次。
5. **后续升级**：`sysupgrade -n -F /tmp/*sysupgrade.bin`，或 LuCI「系统 → 备份/升级」。

刷完默认地址 **http://192.168.1.2**，root / `password`（首次登录请立即改）。

## 旁路由怎么用

固件首次启动已经写好旁路由默认值（`/etc/uci-defaults/99-ax1800pro-bypass`）：

- LAN：`192.168.1.2/24`，网关与 DNS 都指向 `192.168.1.1`（主路由）
- DHCP / RA 关闭，地址仍由主路由分配
- 网线接**任意 LAN 口**到主路由 LAN 口；WAN 口留空
- 客户端要用代理时，把网关（或 DHCP 下发的网关）指向 `192.168.1.2`

换主路由网段不用重刷：

```sh
set-lan-ip 192.168.31.2 192.168.31.1
```

## dae / daed 使用

- daed 面板：`http://192.168.1.2:2023`（daed 默认端口，首次进入自行设面板账号）
- LuCI：**服务 → daede**，同一个界面管理 dae 和 daed，切内核不用重装
- 已内置依赖：`ca-bundle`、`kmod-sched-core`、`kmod-sched-bpf`、`kmod-veth`、
  `kmod-nft-tproxy`、`kmod-tun`、`v2ray-geoip/geosite`
- BTF 用**内核自带**（不装 `vmlinux-btf`），所以内核镜像变大 → 内核分区必须 12M

## 这个配方里三处容易踩的坑（已处理）

1. **`KERNEL_SIZE` 必须是 12M**
   源码里 `jdcloud_re-ss-01` 固定 `KERNEL_SIZE := 6144k`，`factory.bin` 结构是
   `内核(填充到 KERNEL_SIZE) + rootfs`。用 HLOS12M 分区表时若仍按 6M 填充，
   rootfs 会落在内核分区里、真正的 rootfs 分区是空的 → 刷完不启动。
   `diy-part1.sh` 用正则把该值改成 `12288k`，并在 `verify-image.sh` 里检查
   `factory.bin > 12MiB`。

2. **`v2ray-geoip / v2ray-geosite` 官方源里没有**
   `dae`、`daed` 的 `DEPENDS` 硬依赖这两个包名，而 openwrt packages 源里只有
   `v2ray-geodata`（包名不同）。`diy-part1.sh` 会把 kenzok8/small 的
   `v2ray-geodata/Makefile`（含当日 pinned hash）落到 `package/v2ray-geodata`，
   由它产出这两个包。**若某天 hash 与上游不一致，重跑一次即可**（bot 每天同步）。

3. **`DEBUG_INFO_BTF` 与 `DEBUG_INFO_REDUCED` 互斥**
   OpenWrt 默认 `KERNEL_DEBUG_INFO_REDUCED=y`，此时 BTF 打不开。配置里显式关掉了它，
   `verify-config.sh` 会校验 `DEBUG_INFO_BTF=y` 且 `REDUCED` 关闭。

## 失败排查

- 日志在 Actions 页面；失败时 `build.log` 会作为 Artifact 上传
- `配置校验失败` → 包名或符号变了，看 `.config` 里缺失项，多半是 feed 改名
- `dae` 编译报 Go 版本不足 → 上游 snapshot 当天 packages 源的 golang 落后于
  dae 要求（README 里写的 Go 1.26+），等上游同步或改 `SOURCE_BRANCH` 到更新的分支
- `luci-app-daede` 找不到 → `feeds.conf.default` 里 daede 源被改，重看 `diy-part1.sh`
- 刷完不启动 → 九成是内核分区填充 / GPT 版本不匹配，按上面第 0～4 步核对

## 源码出处（保留版权）

- https://github.com/fanchmwrt/fanchmwrt-snapshot （branch `fanchmwrt-26.11`）
- https://github.com/kenzok8/openwrt-daede （dae / daed / luci-app-daede）
- https://github.com/kenzok8/small （v2ray-geodata）
- https://github.com/daeuniverse/dae · https://github.com/daeuniverse/daed
- 上游 https://github.com/openwrt/openwrt
