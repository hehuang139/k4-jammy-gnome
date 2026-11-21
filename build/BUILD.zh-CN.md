# 构建和复现

宿主需要 x86_64 Linux、Docker（普通用户能访问 Docker daemon）、Python 3、bash、GNU 核心工具、curl/jq/gpgv、Ubuntu CD Image 公钥、zstd 和 gdisk。构建使用任务 Docker 容器、Linux 支持 namespaced `binfmt_misc`、qemu-aarch64-static 及文件镜像。私有 user/mount namespace 的 1:1 映射保留目标包的 UID/GID；不在宿主全局注册 qemu，不传 `--privileged`、`--device`，不使用 loop、NBD 或物理盘。工具容器只绑定任务目录。源镜像使用的 ext4 orphan_file 以较新工具镜像 `ubuntu@sha256:678c6550cc43645e08669028bc177f50be4e7c5b8cca677067b1914d4afc7a03` 验证（可用 `K4_FSCK_IMAGE` 显式替代）。可用空间按任务当时 `df` 确认；建议准备 20 GiB 以上，特别是并存两个解包测试盘时。

1. 克隆本仓库并进入仓库根目录，执行 `bash build/resume.sh`。默认通过 GitHub 公开 release 与 Ubuntu CD Image 目录下载。Ubuntu 公开 keyring 需含指纹 `843938DF228D22F7B3742BC0D94AA3F0EFE21092`。
2. `build/fetch.sh` 核验发布件；`board-stage.sh` 只抽取必要分区和 LBA 区域、检查源 ext4、选出 kernel/DTB/modules/firmware。`target-packages.sh` 和 `jammy.list` 构建 Jammy arm64；`configure-target.sh` 建 GDM/locale/dconf/首启配置，以本系统 arm64 工具重建 initramfs。
3. `assemble.sh` 构建两个 GPT/EXT4 盘，使用 `layout.env` 明列尺寸与标识。`verify-release.sh` 以普通文件从发行压缩流模拟写 TF 与 eMMC，记录校验，输出放在 `outputs/v2/`。`verify-image.sh` 逐项检查两种落盘内容。不要求 Linux 主机处理真实 K4 设备。
4. 日志在 `logs/`；可用 `tail -f logs/{stages,fetch-board,rootfs,configure,verify-release}.log` 查看已有日志。阶段存在 `work/` 标记。失败时保留 `.part`、apt 缓存和构建目录；修复对应日志记录的错误，再执行 `build/resume.sh`。不应并行启动第二套构建。若修订已完成阶段，要移除相应阶段及依赖它的后续标记后重做（例如改首启需移除 `work/configured`、`work/smoke-complete`、`work/assembled-v2`、`work/images-verified-v2`，再续建）。
5. APT 的 `jammy-updates`/`jammy-security` 是滚动仓库，生成版的准确版本见 `jammy-packages.tsv`，来源优先级见 `jammy-apt-policy.txt`。重建时版本可能变化；GPT/文件系统 UUID 固定，但文件时间、文件系统种子和包版本等不保证逐字节重现发行哈希。

## 复测 QEMU virt

```bash
docker build -f build/Dockerfile.vm -t lzk4-jammy-vm:local build
build/vm-run.sh TF stale-gpt
```

在另一个本地终端执行 `python3 build/vm-control.py TF stale-gpt screenshot prompt`，确认提示后分别调用 `username`、`new-password`、`confirm-password`（每一步等待对应的 tty1 提示）；`login` 用于 GDM，`keys meta_l-spc` 对应 `Super`+`Space`；`serial` 可检查来宾 `/`、`/boot` 与服务，`quit` 退出。可在来宾临时复制 `build/vm-assert-guest.sh`，以 `sudo bash vm-assert-guest.sh TF 16000000000` 验证扩容、无 swap、网络和本机身份；按场景替换介质与字节数。`eMMC installer` 验证普通文件安装器迁移 GPT 后的扩容，`eMMC grown-gpt` 模拟分区已扩大但 ext4 尚未扩大，`TF minimum` 使用原始 7 GiB 容量。来宾从同一 arm64 内核/initramfs 直接启动；临时快照不会写回发行件，网络只在隔离容器内（来宾 DHCP，容器回环 2222 转发 SSH）。本测试不执行 RK3399 BootROM/SPL/U-Boot。

## 首版复盘

- Docker 工具镜像加 IPv4、连接超时和 APT 重试后构建成功；已存在的镜像不会重建，修改 Dockerfile 后请显式重建。上游镜像保留验证过的 HTTP Range 和最终 SHA-256，Ubuntu Base 先核验官方签名再核验哈希。
- 源 ext4 的 `orphan_file` 由较新版 e2fsck 只读检查；Jammy 用户态的 initramfs 调用 ARM64 `/usr/sbin/mkinitramfs`。dpkg 安装阶段完成后才写标记；中断后从 `dpkg --configure -a` 和 APT 修复续跑，发行仍要求 `dpkg --audit` 无输出。不要边运行某个脚本边编辑同一文件。
- 无 X11 的 chroot 只检查 IBus 的 D-Bus 注册，并显式检查 `LC_ALL=zh_CN.UTF-8`；键盘切换、上屏和输入法窗口在 GNOME 会话验证。
