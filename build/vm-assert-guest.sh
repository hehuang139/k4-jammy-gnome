#!/bin/bash
# Run on the disposable QEMU guest only. No physical disk I/O.
set -euo pipefail
export LC_ALL=C
tr '\0' '\n' </proc/device-tree/compatible | grep -Fxq linux,dummy-virt
[[ $1 = TF || $1 = eMMC ]]
[[ $(cat /etc/k4-boot-medium) = "$1" ]]
expected_disk_bytes=$2
. /etc/k4-image-layout
r=$(findmnt -no SOURCE /)
b=$(findmnt -no SOURCE /boot)
[[ $r = /dev/vda2 && $b = /dev/vda1 ]]
[[ $(sudo blkid -p -s UUID -o value "$r") = "$ROOT_UUID" ]]
[[ $(sudo blkid -p -s UUID -o value "$b") = "$BOOT_UUID" ]]
[[ $(sudo blockdev --getsize64 /dev/vda) = "$expected_disk_bytes" ]]
[[ $(cat /sys/class/block/vda2/start) = "$ROOT_START" ]]
expected=$(( expected_disk_bytes/512 - 33 - ROOT_START ))
[[ $(cat /sys/class/block/vda2/size) = "$expected" ]]
verify() {
    sudo sgdisk -v /dev/vda | grep -F 'No problems found'
    sudo sgdisk -i 2 /dev/vda | grep -Fi "Partition unique GUID: $ROOT_PARTUUID"
    read -r blocks size < <(sudo tune2fs -l "$r" | awk '/^Block count:/ {n=$3} /^Block size:/ {print n,$3}')
    [[ $size = 4096 && $blocks = $((expected/8)) ]]
    printf 'ext4 block count=%s size=%s\n' "$blocks" "$size"
}
systemctl is-active k4-grow-root NetworkManager ssh
verify
sudo systemctl restart k4-grow-root
verify
sudo journalctl -b -u k4-grow-root --no-pager -o cat | grep -E 'GPT and ext4|Nothing to do|Resizing the filesystem'
grep -E '^SwapTotal:[[:space:]]+0 kB$' /proc/meminfo
[[ $(wc -l </proc/swaps) = 1 ]]
nmcli -g GENERAL.STATE,GENERAL.CONNECTION,IP4.ADDRESS device show | tee /tmp/k4-vm-network
grep -Fx 'K4 Wired DHCP' /tmp/k4-vm-network
grep -Eq '^10\.0\.2\.[0-9]+/24$' /tmp/k4-vm-network
sudo /usr/sbin/sshd -T | grep -E '^(passwordauthentication|kbdinteractiveauthentication|permitrootlogin) no$' | tee /tmp/k4-vm-ssh
[[ $(wc -l </tmp/k4-vm-ssh) = 3 ]]
key=$(getent passwd "$SUDO_USER" | cut -d: -f6)/.local/share/k4-rdp/tls/rdp.key
cert=${key%/*}/rdp.crt
[[ $(stat -c %a "$key") = 600 ]]
[[ $(openssl pkey -in "$key" -pubout) = "$(openssl x509 -in "$cert" -noout -pubkey)" ]]
[[ $(runuser -u "$SUDO_USER" -- k4-rdp-tls) = "$(openssl x509 -in "$cert" -noout -fingerprint -sha256)" ]]
openssl x509 -in "$cert" -noout -fingerprint -sha256
ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
printf 'machine-id: %s\n' "$(cat /etc/machine-id)"
