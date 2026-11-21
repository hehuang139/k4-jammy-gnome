#!/bin/bash
set -euo pipefail
apt-get -o Acquire::Languages=none update
# Recover an interrupted package stage before resuming the install transaction.
if ! dpkg --configure -a; then
  apt-get -y --no-install-recommends --fix-broken install
  dpkg --configure -a
fi
if [ ! -e /var/lib/k4-base-upgraded ]; then
apt-get -y --no-install-recommends -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold upgrade
touch /var/lib/k4-base-upgraded
fi
apt-get -y --no-install-recommends install \
  ubuntu-keyring ca-certificates systemd-sysv udev kmod sudo adduser dbus dbus-user-session \
  initramfs-tools busybox-initramfs zstd e2fsprogs fdisk util-linux \
  gdm3 gnome-shell gnome-session gnome-settings-daemon \
  gnome-control-center gnome-terminal nautilus gedit gnome-initial-setup gnome-keyring \
  gnome-shell-extension-prefs yaru-theme-gtk yaru-theme-icon \
  xserver-xorg-core xserver-xorg-input-libinput xserver-xorg-video-all xwayland xauth \
  libgl1-mesa-dri mesa-utils fonts-dejavu fonts-noto-cjk fonts-noto-color-emoji \
  locales language-pack-zh-hans language-pack-gnome-zh-hans ibus ibus-libpinyin \
  network-manager wpasupplicant wireless-regdb rfkill iproute2 iputils-ping \
  alsa-utils pulseaudio pulseaudio-module-bluetooth bluez \
  udisks2 gvfs accountsservice policykit-1 systemd-timesyncd tzdata \
  xz-utils gzip curl less nano pciutils usbutils ethtool gdisk mmc-utils cloud-guest-utils openssh-server openssl gnome-remote-desktop
# Clean up an incremental build upgraded from v1; do not install zram in fresh builds.
if dpkg-query -W -f='${db:Status-Status}' zram-tools 2>/dev/null | grep -qx installed; then
  apt-get -y purge zram-tools
fi
