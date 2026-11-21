#!/bin/bash
set -euo pipefail
cd /task
R=$1
source build/layout.env
[[ -f work/packages-complete && -f work/board-complete ]]
install -d "$R/usr/lib/modules" "$R/usr/lib/firmware"
rsync -aH work/board-os/modules/ "$R/usr/lib/modules/"
rsync -aH work/board-os/firmware/ "$R/usr/lib/firmware/"
install -D -m 644 work/board-os/modprobe.d/brcmfmac.conf "$R/etc/modprobe.d/k4-brcmfmac.conf"
install -m 644 "work/board-boot/config-$KVER" "$R/boot/"
install -m 644 "work/board-boot/System.map-$KVER" "$R/boot/"
install -m 755 build/first-user "$R/usr/local/sbin/k4-first-user"
install -m 644 build/k4-first-user.service "$R/etc/systemd/system/"
install -d "$R/etc/systemd/system/gdm.service.d" "$R/etc/dconf/profile" "$R/etc/dconf/db/local.d" "$R/etc/gdm3" "$R/etc/initramfs-tools/conf.d"
cat > "$R/etc/systemd/system/gdm.service.d/10-k4-first-user.conf" <<'EOF'
[Unit]
After=k4-first-user.service
ConditionPathExists=/var/lib/k4-setup/user-created
EOF
cat > "$R/etc/gdm3/custom.conf" <<'EOF'
[daemon]
WaylandEnable=false
InitialSetupEnable=False
DefaultSession=gnome-xorg.desktop

[security]

[xdmcp]

[chooser]

[debug]
EOF
cat > "$R/etc/dconf/profile/user" <<'EOF'
user-db:user
system-db:local
EOF
cat > "$R/etc/dconf/db/local.d/00-k4-input" <<'EOF'
[org/gnome/desktop/input-sources]
sources=[('xkb', 'us'), ('ibus', 'libpinyin')]

[org/gnome/desktop/wm/keybindings]
switch-input-source=['<Super>space']
switch-input-source-backward=['<Shift><Super>space']

[org/gnome/desktop/interface]
enable-animations=false
EOF
cat > "$R/etc/default/locale" <<'EOF'
LANG=zh_CN.UTF-8
LANGUAGE=zh_CN:zh
EOF
cat > "$R/etc/locale.gen" <<'EOF'
en_US.UTF-8 UTF-8
zh_CN.UTF-8 UTF-8
EOF
printf '%s\n' 'k4-jammy' > "$R/etc/hostname"
cat > "$R/etc/hosts" <<'EOF'
127.0.0.1 localhost
127.0.1.1 k4-jammy
::1 localhost ip6-localhost ip6-loopback
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
EOF
ln -sfn /etc/default/locale "$R/etc/locale.conf"
ln -sfn /usr/share/zoneinfo/Asia/Shanghai "$R/etc/localtime"
printf 'Asia/Shanghai\n' > "$R/etc/timezone"
rm -f "$R/etc/default/zramswap"
install -m 755 build/grow-root "$R/usr/local/sbin/k4-grow-root"
install -D -m 755 build/k4-rdp-tls "$R/usr/local/bin/k4-rdp-tls"
install -m 644 build/{k4-grow-root,k4-ssh-hostkeys}.service "$R/etc/systemd/system/"
install -d "$R/etc/systemd/system/ssh.service.d" "$R/etc/ssh/sshd_config.d"
cat > "$R/etc/systemd/system/ssh.service.d/10-k4-hostkeys.conf" <<'EOF'
[Unit]
Requires=k4-ssh-hostkeys.service
After=k4-ssh-hostkeys.service
EOF
cat > "$R/etc/ssh/sshd_config.d/10-k4.conf" <<'EOF'
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
EOF
install -d "$R/etc/NetworkManager/conf.d" "$R/etc/NetworkManager/system-connections"
# Shadow Ubuntu's rule which otherwise excludes all Ethernet devices.
cat > "$R/etc/NetworkManager/conf.d/10-globally-managed-devices.conf" <<'EOF'
[keyfile]
unmanaged-devices=*,except:type:ethernet,except:type:wifi,except:type:gsm,except:type:cdma
EOF
umask 077
cat > "$R/etc/NetworkManager/system-connections/k4-wired.nmconnection" <<'EOF'
[connection]
id=K4 Wired DHCP
type=ethernet
autoconnect=true
autoconnect-priority=-100

[ethernet]

[ipv4]
method=auto

[ipv6]
method=auto
EOF
chmod 600 "$R/etc/NetworkManager/system-connections/k4-wired.nmconnection"
umask 022
cat > "$R/etc/initramfs-tools/conf.d/50-k4" <<'EOF'
# Both RK3399 MMC controllers/PHY, EXT4 and GPT are built into this kernel.
MODULES=list
COMPRESS=gzip
EOF
printf 'RESUME=none\n' > "$R/etc/initramfs-tools/conf.d/resume"
# The additional virtio modules allow direct-kernel file-image VM boot/diagnosis.
printf 'virtio_pci\nvirtio_blk\n' > "$R/etc/initramfs-tools/modules"
cat > "$R/tmp/k4-configure.sh" <<'EOF'
#!/bin/bash
set -euo pipefail
export LC_ALL=C
kver=$1
# Keep build provenance without leaving build APT lists and downloads in the image.
apt-cache policy
apt-cache policy gnome-shell gdm3 ibus-libpinyin libc6 systemd libgl1-mesa-dri
EOF
chroot "$R" /usr/bin/env DEBIAN_FRONTEND=noninteractive /bin/bash /tmp/k4-configure.sh "$KVER" >logs/jammy-apt-policy.txt
rm -f "$R/tmp/k4-configure.sh"
chroot "$R" locale-gen
chroot "$R" dconf update
chroot "$R" fc-cache -sf
chroot "$R" passwd -l root
# GDM package stores custom.conf as /etc/gdm3/custom.conf and launches /usr/sbin/gdm3.
chroot "$R" /bin/systemctl --root=/ enable k4-first-user.service NetworkManager.service systemd-resolved.service systemd-timesyncd.service k4-grow-root.service ssh.service
chroot "$R" /bin/systemctl --root=/ mask getty@tty1.service NetworkManager-wait-online.service zramswap.service swap.target
chroot "$R" /bin/systemctl --root=/ set-default graphical.target
GDM_UNIT=$(find "$R/lib/systemd/system/" -maxdepth 1 -name gdm.service -printf '%f\n')
[[ $GDM_UNIT == gdm.service ]]
ln -sfn /lib/systemd/system/gdm.service "$R/etc/systemd/system/display-manager.service"
printf '/usr/sbin/gdm3\n' > "$R/etc/X11/default-display-manager"
test -f "$R/usr/share/xsessions/gnome-xorg.desktop"
# mkinitramfs uses the installed arm64 tools, not the host's own initramfs or kernel.
depmod -b "$R" "$KVER"
chroot "$R" /usr/sbin/mkinitramfs -o "/boot/initrd.img-$KVER" "$KVER"
mkimage -A arm64 -O linux -T ramdisk -C gzip -n "Jammy $KVER" -d "$R/boot/initrd.img-$KVER" "work/uInitrd-$KVER"
chroot "$R" dpkg-query -W -f='${binary:Package}\t${Version}\t${Architecture}\t${db:Status-Abbrev}\n' >logs/jammy-packages.tsv
chroot "$R" dpkg --audit >logs/jammy-dpkg-audit.txt
if [[ -s logs/jammy-dpkg-audit.txt ]]; then
  cat logs/jammy-dpkg-audit.txt >&2; exit 1
fi
chroot "$R" apt-get clean
rm -f "$R/etc/apt/apt.conf.d/80k4-build" "$R/usr/sbin/policy-rc.d" "$R/etc/resolv.conf"
ln -s /run/systemd/resolve/stub-resolv.conf "$R/etc/resolv.conf"
: > "$R/etc/machine-id"
ln -sfn /etc/machine-id "$R/var/lib/dbus/machine-id"
rm -f "$R/var/lib/systemd/random-seed" "$R"/etc/ssh/ssh_host_* "$R"/var/lib/NetworkManager/{secret_key,seen-bssids,timestamps,no-auto-default.state}
find "$R/var/lib/apt/lists" -mindepth 1 -maxdepth 1 -type f -delete
find "$R/var/log" -type f -exec truncate -s0 {} +
# /boot is mounted from partition 1 in the output image. Do not duplicate its contents on rootfs.
rm -f "$R/boot/initrd.img-$KVER" "$R/boot/config-$KVER" "$R/boot/System.map-$KVER"
touch work/configured
