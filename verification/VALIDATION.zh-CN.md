# 二版验证记录｜2026-11-22（北京时间）

## 构建、离线和普通文件写入

- x86_64 Ubuntu 宿主、Docker 私有命名空间、QEMU ARM64 用户态；复用通过固定 SHA-256 与官方签名校验的 ophub lzk4 底本和 Ubuntu Base。Jammy `dpkg --audit` 为空；下游包版本见 `jammy-packages.tsv`。
- 两份压缩件各解出 7,516,192,768 字节。`sha256sum -c --strict`、`zstd -t`、`sgdisk -v` 和两分区 `e2fsck -fn` 通过；启动区 LBA 64–32767、板级 DTB 和内核与固定上游一致。两版 GPT/PARTUUID、根和 `/boot` 的 UUID 分别一致且互不相同。
- `build/verify-release.sh`：eMMC 安装器拒绝少 512 字节的文件；在有旧备份 GPT 的 16,000,000,000 字节普通文件中校验镜像写入、首 7 GiB 读回及备份 GPT 迁移到实际末扇区通过；未写入真实磁盘。

## ARM64 QEMU virt（2 GiB、隔离网络）

| 场景 | 最终 ext4（4 KiB 块） | 结果 |
| --- | ---: | --- |
| `TF stale-gpt`，16 GB，备份 GPT 留在原 7 GiB 位置 | 3,771,077 | 修正 GPT，在线扩展根分区和 ext4 |
| `TF minimum`，原始 7 GiB | 1,699,835 | 可在最小容量首启，保留开始扇区和标识 |
| `eMMC installer`，16 GB，安装器已迁移备份 GPT | 3,771,077 | 在线扩展根分区和 ext4 |
| `eMMC grown-gpt`，16 GB，只有 GPT 分区已扩大 | 3,771,077 | 补完 ext4 扩容，不再改变 GPT 分区边界 |

四个来宾均完成首次建用户，验证挂载、根起始扇区及 PARTUUID 保持，`systemctl restart k4-grow-root` 再次执行后容量不变，`SwapTotal=0`，NetworkManager 有线 DHCP，OpenSSH 公钥登录成功并拒绝密码与 root。独立 TF/eMMC 来宾的 machine-id、SSH 主机密钥和 TLS 证书指纹不同；TLS 私钥权限为 `0600` 且与本用户证书匹配。

## 可选软件与实验

- 在一次性 Jammy ARM64 chroot 用实际搜狗 4.2.1.145 安装包执行安装脚本：固定 SHA-256、Fcitx 4 与 GTK/Qt 依赖和两项 Pango `dpkg-divert` 检查通过，`dpkg --audit` 为空。首版实板 GTK 上屏已验证；二版搜狗的 Chrome 输入待复测。
- i2c2 实验覆盖层离线 `fdtoverlay` + 反编译对比只新增三项时序属性；不进稳定产物。首版实板 eMMC 的 1080p GNOME 已验证，二版实板 TF/eMMC 冷启动、PHY 协商和 GPU 加速仍待验证。未操作实板桌面或 RDP 客户端。

TF 与 eMMC 两个主场景均进入中文 GDM，分别经本地 GDM 登录得到 `seat0` 的活动 X11 会话。TF 来宾以桌面用户执行 `k4-rdp-tls --configure` 成功写入证书路径，`org.gnome.desktop.remote-desktop.rdp enable` 保持 `false`。
两台来宾从 GNOME 的 `Alt`+`F2` 入口启动 gedit，实测键盘输入 `hello` 和用智能拼音提交 `你好`，再读回保存的 UTF-8 文件逐字匹配。`Super`+`Space` 用于切换输入源；若拼音引擎处于英文直输状态，单按 `Shift` 回中文模式。
