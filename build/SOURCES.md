# 输入来源（版本和适用范围）

- ophub/amlogic-s9xxx-armbian tag `Armbian_bookworm_arm64_server_2026.10`，asset ID `655186622`，公开文件 `Armbian_26.11.0_rockchip_lzk4_bookworm_6.18.57_server_2026.10.19.img.gz`，821253469 字节。GitHub API 的 `digest`: `sha256:14aa496c134817ec4b47d1eabd287859caaf1058234c327b30ec8d300729018f`。构建时在本机 `logs/ophub-asset.json` 记录所选资产。不是 Jammy 用户态来源。
  - https://github.com/ophub/amlogic-s9xxx-armbian/releases/tag/Armbian_bookworm_arm64_server_2026.10
  - https://github.com/ophub/amlogic-s9xxx-armbian/issues/3722 （V9.0 社区讨论）
- ophub/u-boot `4b44a60236466258b8c1a4ab92a8d661277887fe` 的 `u-boot/rockchip/lzk4/{idbloader.bin,uboot.img,trust.bin}`；原镜像相应区域逐字节与这三个文件一致。文件哈希见 `ophub-loader.txt`。整盘使用直接从发布件抽取的 LBA 64–32767，不重新拼造 bootloader。
  - https://github.com/ophub/u-boot/tree/4b44a60236466258b8c1a4ab92a8d661277887fe/u-boot/rockchip/lzk4
  - https://docs.u-boot.org/en/latest/board/rockchip/rockchip.html （Rockchip 分立 loader / U-Boot 磁盘位置与写盘路径；实际 trust 位置以发布镜像与二进制对照为准）
- Ubuntu Base `22.04.5` Jammy arm64 `ubuntu-base-22.04.5-base-arm64.tar.gz`，SHA-256 `075d4abd2817a5023ab0a82f5cb314c5ec0aa64a9c0b40fd3154ca3bfdae979f`。`SHA256SUMS` 和 `SHA256SUMS.gpg` 由 Ubuntu CD Image Automatic Signing Key (2012) 验证，指纹 `843938DF228D22F7B3742BC0D94AA3F0EFE21092`。其余目标软件由 Ubuntu Ports 签名的 `jammy`、`jammy-updates`、`jammy-security` 获取，非 Debian 或 Noble 下的用户态。
  - https://cdimage.ubuntu.com/ubuntu-base/releases/22.04/release/
  - https://ports.ubuntu.com/ubuntu-ports/
- 厂方 K4 V11 规格书第 9、10 页；此项目针对贴纸标称 4 GB/16 GB 的 V3.0 设备。
  - https://www.liontron.cn/showinfo-118-185-0.html

## 许可与发行范围

- 仓库的自有脚本、补丁和文档按仓库 `LICENSE` 发布；不变更第三方软件和固件的许可。本仓库不托管 Ubuntu/Armbian 的原始镜像、抽出的二进制或构建后的磁盘镜像。
- Kernel、模块、U-Boot、固件和 Rockchip 的 loader/trust 输入不应被视为统一许可证。上游 GPL 项目与固定二进制资产的对应完整源代码、构建配置，以及该固件集合每个文件的再分发条件未逐项核清。为此本次仅发布可执行的源码配方、来源和校验值；下载在构建机本地进行。
- Jammy 软件包以 Ubuntu Ports 签名索引为准，软件包版权见目标系统 `/usr/share/doc/<package>/copyright` 及对应源包。项目使用 Ubuntu、Armbian 和板厂名称仅为标明兼容性及来源。Google Chrome、搜狗及 RustDesk 由用户按厂商说明独立安装，见 `release/DESKTOP.zh-CN.md`。
