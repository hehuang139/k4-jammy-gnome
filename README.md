# 亮钻 K4 V3.0｜Jammy GNOME 中文桌面

面向亮钻（Liontron）K4 PCB V3.0（RK3399，4 GB RAM / 16 GB eMMC）的社区构建：Ubuntu 22.04 arm64 用户态、GNOME/Xorg、简体中文和 IBus 智能拼音。TF 与 eMMC 分别使用自己的 GPT 和文件系统标识。Linux 内核、稳定版设备树、板级固件和启动区来自固定校验值的 ophub lzk4 底本；本项目不是官方厂商镜像。

**本仓库发布源码与校验记录，不托管整盘镜像或第三方闭源安装包。** 本地执行下列步骤可生成两份镜像：

```bash
bash build/resume.sh
cd outputs/v2
sha256sum -c --strict SHA256SUMS
```

参阅[构建与复测](build/BUILD.zh-CN.md)、[上游来源与许可边界](build/SOURCES.md)、[可选桌面软件](release/DESKTOP.zh-CN.md)。镜像文件名分别为 `K4-Jammy-GNOME-TF.img.zst` 和 `K4-Jammy-GNOME-eMMC.img.zst`，各解压为 7 GiB。自动扩容还要求 512 字节逻辑扇区、同盘匹配的 `/` 与 `/boot`。不要同时连接两份同一介质版本的镜像，以免 UUID 冲突。

## 启动与首次使用

1. TF 镜像用于整卡写入，不是拷进卡上的普通文件。写入前确认整卡标识并备份旧数据；先用 TF 断电冷启动，确认 HDMI、键鼠和有线网。
2. eMMC 版写入的是整个 eMMC 用户区，**会覆盖 Android 与旧分区**；先备份并准备恢复路径。可将 eMMC 镜像、`.raw.sha256`、`SHA256SUMS` 和 `install-emmc.sh` 放在一起，从本项目 TF 桌面执行 `sudo ./install-emmc.sh --device /dev/mmcblkN`，其中 `N` 必须换成已确认的 eMMC。安装器检查设备类型、当前 TF 根、挂载及占用，要求确认，先校验写回数据再迁移备份 GPT。关机、拔卡、断电后再单独启动 eMMC。
3. 首次启动按 HDMI 上的提示创建本地管理员和密码，再登录 GDM。根分区扩展只针对实际挂载的根盘；扩容日志为 `journalctl -b -u k4-grow-root`。出现 GPT/挂载标识不匹配时不会继续改盘。已扩容可用 `sudo systemctl restart k4-grow-root` 复核。默认不使用 swap；2 GiB 内存或多标签浏览器下要注意内存压力。
4. 以太网默认 DHCP。SSH 每机生成主机密钥，仅允许公钥认证，禁止 root 登录。先在本地终端把自己的公钥保存到 `~/.ssh/authorized_keys`（目录 `0700`、文件 `0600`），再根据 `nmcli device show` 的本机地址连接；用本机 `/etc/ssh/ssh_host_ed25519_key.pub` 核对首次连接指纹。不需要 SSH 时可 `sudo systemctl disable --now ssh`。
5. 使用 `Super`+`空格` 切换英语和智能拼音；若已切到拼音但仍直接输出字母，按一次 `Shift` 将拼音引擎切回中文模式。GNOME RDP 默认不开启，不包含任何预设远程凭据；另见可选软件文档。

## 硬件状态

首版 eMMC 已在 V3.0 实板走 USB Maskrom 写入与读回，从 eMMC 启动 GNOME/Xorg，HDMI 1920×1080；二版稳定 DTB 不变。实板首版因 i2c2 上的 PMIC/调压器响应超时，Panfrost 未建立渲染节点，Mesa 使用 llvmpipe。[实验说明](experiments/README.md)提供仅改 i2c2 时钟和 SCL 边沿参数的 TF 对照补丁，不属于稳定镜像。二版的 TF 冷启动、eMMC 独立冷启动及 GPU 行为需要实板复测。
