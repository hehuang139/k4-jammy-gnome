# 可选桌面软件（本机安装）

基础镜像是 GNOME/Xorg + IBus 智能拼音，含 GNOME Remote Desktop。升级前先正常执行 Ubuntu 的软件更新。Chrome、搜狗、RustDesk 不预装，不把其 `.deb` 或用户状态纳入发行。以下为独立安装路径，避免将现场凭据、设备标识、厂商文件或远程服务配置做进通用镜像。

## 搜狗输入法 ARM64 与 Fcitx 4

从[搜狗 Linux 官网](https://shurufa.sogou.com/linux)取得 ARM64 的 `sogoupinyin_4.2.1.145_arm64.deb`（或使用你保存的同版官方包），用 `sudo bash release/install-sogou.sh /path/to/sogoupinyin_4.2.1.145_arm64.deb` 安装。脚本核对 SHA-256、包名、版本及架构，并安装 Fcitx GTK2/GTK3/Qt5 前端与 Jammy Qt/Pango 依赖。两份旧 Pango 库通过本地 `dpkg-divert` 移开，令搜狗加载 Jammy 自带版本。

在桌面用户的终端运行 `im-config -n fcitx`，注销后重新登录，在 Fcitx 设置中加入搜狗拼音并选用 `Ctrl`+`Space`，必要时安装 `fcitx-config-gtk`。同一会话不要同时将 IBus 与 Fcitx 设为全局输入法。先在 GTK 编辑器确认 `nihao` 上屏「你好」，再单独检查 Chrome 的输入框。要恢复基础输入法，卸载搜狗、移除对应的两条本地 `dpkg-divert`，运行 `im-config -n ibus` 后重新登录。

## Chrome ARM64

从[Google Chrome 官方下载](https://www.google.com/chrome/)选择 Linux ARM64 的 Debian/Ubuntu 包（不要混用 amd64）。在 Jammy ARM64 上用 `sudo apt install ./google-chrome-stable_current_arm64.deb`。安装后运行 `sudo apt update`，检查 Google 源及签名验证无误，再用 `apt-cache policy google-chrome-stable` 与 `google-chrome --version` 确认包来源和版本。若源验证失败，按 [Google Linux APT 签名说明](https://www.google.com/linuxrepositories/)修复；不使用 `trusted=yes` 或 `--allow-unauthenticated`。现场对照版本为 `158.0.8127.36`，厂商下载的 stable 版会更新。

## RustDesk ARM64

从 [RustDesk 1.5.3 的官方 Release](https://github.com/rustdesk/rustdesk/releases/tag/1.5.3)下载 `rustdesk-1.5.3-aarch64.deb`。官方资产 SHA-256 为 `fa85e8d3ccd45e2e303c2d1359af5dc51aa93d880e39ba47c9b04bfabd82ae19`；核对后用 `sudo apt install ./rustdesk-1.5.3-aarch64.deb`。这一步只在目标设备上执行，由程序在首次运行时生成本机身份；不复制其他设备的 RustDesk 配置或 ID。若不需要无人值守访问，关闭其后台服务或留空永久密码。按需配置自己信任的 RustDesk 服务端。

## GNOME Remote Desktop（RDP）

首次创建本地管理员时系统生成该用户独立的 TLS 密钥和证书。进入 **本机** GNOME/Xorg 后，以当前 GUI 用户运行 `k4-rdp-tls --configure` 来设置 GNOME RDP 证书和密钥；其他用户运行该命令时会为各自生成一套。随后可在 GNOME 设置 → 共享 → 远程桌面启用桌面共享，设置自己的 RDP 凭据并保存到用户自己的 keyring；不把密码写进脚本或镜像。首次连接时通过本机输出的证书指纹独立核对。现场用的是已登录、已解锁的 Xorg 桌面共享，并不是远程进入登录界面或多用户虚拟会话。只在受信网络使用；不把 3389 直接暴露在公网。
