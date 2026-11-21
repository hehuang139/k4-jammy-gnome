#!/bin/bash
set -euo pipefail
export LC_ALL=C
cd /task
source build/layout.env
[[ $# = 2 && -f $2 && ! -b $2 ]]
media=$1; disk=$2; upper=${media^^}
[[ $media = TF || $media = eMMC ]]
ruuid=${upper}_ROOT_UUID; buuid=${upper}_BOOT_UUID
bpart=${upper}_BOOT_PART; rpart=${upper}_ROOT_PART; disk_id=${upper}_DISK
boot_bytes=$(((BOOT_END-BOOT_LBA+1)*512))
root_bytes=$((IMAGE_BYTES - (ROOT_LBA+TAIL_SECTORS)*512))
rm -rf work/check-files
mkdir work/check-files
scratch=work
if [[ -d /scratch ]]; then scratch=/scratch; fi
boot=$scratch/check-boot.img
root=$scratch/check-root.img
trap 'rm -f "$boot" "$root"; rm -rf work/check-files' EXIT
printf '\n=== %s: %s ===\n' "$media" "$disk"
sgdisk -p "$disk" | tee work/check-files/pt
grep -Fi "Disk identifier (GUID): ${!disk_id}" work/check-files/pt
sgdisk -v "$disk" | tee work/check-files/gpt
grep -Fq 'No problems found' work/check-files/gpt
sgdisk -i 1 "$disk" | grep -Fi "Partition unique GUID: ${!bpart}"
sgdisk -i 2 "$disk" | grep -Fi "Partition unique GUID: ${!rpart}"
python3 - "$disk" "$BOOT_LBA" "$BOOT_END" "$ROOT_LBA" "$IMAGE_BYTES" "$TAIL_SECTORS" <<'PY'
import sys,struct
path,b,e,r,n,t=sys.argv[1:]; b,e,r,n,t=map(int,(b,e,r,n,t))
with open(path,'rb') as f:
    f.seek(512); assert f.read(8)==b'EFI PART'
    f.seek(2*512+32); assert struct.unpack('<QQ',f.read(16))==(b,e)
    f.seek(2*512+128+32); assert struct.unpack('<QQ',f.read(16))==(r,n//512-t-1)
    for sector, expect in ((64,bytes.fromhex('3b8cdcfc')), (16384,b'LOADER  '), (24576,b'BL3X')):
        f.seek(sector*512); assert f.read(len(expect))==expect
        print(f'RK3399 loader LBA {sector}: {expect.hex()}')
PY
cmp -n $(((BOOT_LBA-64)*512)) -i 32768 "$disk" work/board-prefix.bin
printf 'Loader region LBA 64..%s: identical to verified upstream asset\n' "$((BOOT_LBA-1))"
dd if="$disk" of="$boot" iflag=skip_bytes,count_bytes bs=4M skip="$((BOOT_LBA*512))" count="$boot_bytes" conv=sparse status=none
dd if="$disk" of="$root" iflag=skip_bytes,count_bytes bs=4M skip="$((ROOT_LBA*512))" count="$root_bytes" conv=sparse status=none
blkid -p "$boot" "$root"
[[ $(blkid -s UUID -o value "$boot") == "${!buuid}" && $(blkid -s UUID -o value "$root") == "${!ruuid}" ]]
e2fsck -fn "$boot"
e2fsck -fn "$root"
C=work/check-files
fsdump() { debugfs -R "dump -p $2 $C/$3" "$1" 2>&1; test -f "$C/$3"; }
fsdump "$boot" /boot.scr boot.scr
fsdump "$boot" /boot.cmd boot.cmd
fsdump "$boot" /armbianEnv.txt armbianEnv.txt
fsdump "$boot" /dtb/rockchip/rk3399-lzk4.dtb rk3399-lzk4.dtb
fsdump "$boot" /vmlinuz-"$KVER" Image
fsdump "$boot" /initrd.img-"$KVER" initrd
fsdump "$boot" /uInitrd-"$KVER" uInitrd
cmp "$C/boot.scr" work/board-boot/boot.scr
cmp "$C/boot.cmd" work/board-boot/boot.cmd
cmp "$C/rk3399-lzk4.dtb" work/board-boot/dtb/rockchip/rk3399-lzk4.dtb
cmp "$C/Image" "work/board-boot/vmlinuz-$KVER"
file "$C/Image"
dumpimage -l "$C/boot.scr"
dumpimage -l "$C/uInitrd"
python3 - "$C" <<'PY'
import sys,pathlib,zlib,struct
p=pathlib.Path(sys.argv[1]); im=(p/'Image').read_bytes()
assert im[56:60] == b'ARM\x64'
for name in ('boot.scr','uInitrd'):
    hdr,data=(p/name).read_bytes()[:64],(p/name).read_bytes()[64:]
    magic,hcrc,_,size,_,_,dcrc=struct.unpack('>7I',hdr[:28]); assert magic==0x27051956
    assert zlib.crc32(hdr[:4]+b'\0'*4+hdr[8:])==hcrc
    assert len(data)==size and zlib.crc32(data)==dcrc
    if name=='uInitrd': assert data==(p/'initrd').read_bytes()
    print(f'{name}: payload length and header/data CRC verified')
PY
fdtget "$C/rk3399-lzk4.dtb" / model
fdtget "$C/rk3399-lzk4.dtb" / compatible
for node in $(fdtget -l "$C/rk3399-lzk4.dtb" / | grep -E '(fe320000|fe330000)$'); do
  printf '%s: ' "$node"; fdtget "$C/rk3399-lzk4.dtb" "/$node" status | grep -x okay
done
[[ $(fdtget -l "$C/rk3399-lzk4.dtb" / | grep -Ec '(fe320000|fe330000)$') = 2 ]]
lsinitramfs "$C/initrd" > "$C/initrd-list"
for f in init scripts/local sbin/blkid; do grep -xE "(usr/)?$f" "$C/initrd-list"; done
grep -E '/virtio_(blk|pci)\.ko' "$C/initrd-list"
fsdump "$root" /etc/fstab fstab
fsdump "$root" /etc/k4-boot-medium medium
fsdump "$root" /usr/lib/os-release os-release
fsdump "$root" /bin/dash dash || fsdump "$root" /usr/bin/dash dash
fsdump "$root" /usr/lib/modules/"$KVER"/modules.dep modules.dep
for pair in \
  'kernel/drivers/gpu/drm/rockchip/rockchipdrm.ko:rockchipdrm.ko' \
  'kernel/drivers/gpu/drm/panfrost/panfrost.ko:panfrost.ko' \
  'kernel/drivers/block/zram/zram.ko:zram.ko' \
  'kernel/drivers/net/wireless/broadcom/brcm80211/brcmfmac/brcmfmac.ko:brcmfmac.ko'; do
  rel=${pair%:*}; base=${pair##*:}
  fsdump "$root" "/usr/lib/modules/$KVER/$rel" "$base"
  cmp "$C/$base" "work/board-os/modules/$KVER/$rel"
  file "$C/$base" | grep -E 'ARM aarch64|ARM64'
done
# Preserve the firmware alias and compare its actual backing file, not the link inode.
firmware_link=$(readlink work/board-os/firmware/brcm/BCM43430A1.hcd)
[[ $firmware_link == ../ap6212/bcm43438a1.hcd ]]
debugfs -R 'stat /usr/lib/firmware/brcm/BCM43430A1.hcd' "$root" 2>&1 | grep -F "Fast link dest: \"$firmware_link\""
fsdump "$root" /usr/lib/firmware/ap6212/bcm43438a1.hcd BCM43430A1.hcd
cmp "$C/BCM43430A1.hcd" work/board-os/firmware/ap6212/bcm43438a1.hcd
fsdump "$root" /etc/gdm3/custom.conf gdm.conf
fsdump "$root" /usr/share/xsessions/gnome-xorg.desktop session
fsdump "$root" /etc/default/locale locale
fsdump "$root" /etc/dconf/db/local.d/00-k4-input input
fsdump "$root" /usr/share/ibus/component/libpinyin.xml libpinyin.xml
fsdump "$root" /etc/systemd/system/k4-first-user.service first-user.service
fsdump "$root" /etc/shadow shadow
cat "$C/fstab" "$C/locale" "$C/input" "$C/gdm.conf"
grep -x "rootdev=UUID=${!ruuid}" "$C/armbianEnv.txt"
grep -Fx fdtfile=rockchip/rk3399-lzk4.dtb "$C/armbianEnv.txt"
[[ $(awk '$2=="/"{print $1}' "$C/fstab") = "UUID=${!ruuid}" ]]
[[ $(awk '$2=="/boot"{print $1}' "$C/fstab") = "UUID=${!buuid}" ]]
grep -Fx "$media" "$C/medium"
grep -Fx 'VERSION_ID="22.04"' "$C/os-release"
grep -Fx 'VERSION_CODENAME=jammy' "$C/os-release"
file "$C/dash" | grep -E 'ARM aarch64|ARM64'
grep -Fx LANG=zh_CN.UTF-8 "$C/locale"
grep -Fx "sources=[('xkb', 'us'), ('ibus', 'libpinyin')]" "$C/input"
grep -Fx 'DefaultSession=gnome-xorg.desktop' "$C/gdm.conf"
grep -Fx 'WaylandEnable=false' "$C/gdm.conf"
grep -E '<name>libpinyin</name>' "$C/libpinyin.xml"
grep -E 'rockchipdrm|rockchip_drm|panfrost|brcmfmac|zram' "$C/modules.dep" | cut -c1-130 | head -15 || true
[[ $(awk -F: '$1=="root"{print substr($2,1,1)}' "$C/shadow") =~ [!*] ]]
# Confirm offline that there is no pre-created normal account, and machine-id is not cloned.
fsdump "$root" /etc/passwd passwd
fsdump "$root" /etc/machine-id machine-id
! awk -F: '$3>=1000 && $3<60000 {found=1} END{exit !found}' "$C/passwd"
[[ ! -s $C/machine-id ]]
for p in /etc/systemd/system/display-manager.service /etc/systemd/system/multi-user.target.wants/k4-first-user.service /usr/lib/gnome-shell /usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc; do
  debugfs -R "stat $p" "$root" 2>&1 | grep -m1 '^Inode:'
done
fsdump "$root" /etc/k4-image-layout image-layout
fsdump "$root" /etc/NetworkManager/conf.d/10-globally-managed-devices.conf nm-devices
fsdump "$root" /etc/NetworkManager/system-connections/k4-wired.nmconnection nm-wired
fsdump "$root" /etc/ssh/sshd_config.d/10-k4.conf ssh-config
fsdump "$root" /etc/systemd/system/k4-grow-root.service grow-root.service
[[ $(awk -F= '$1=="ROOT_PARTUUID"{print $2}' "$C/image-layout") = "${!rpart}" ]]
grep -Fq 'except:type:ethernet' "$C/nm-devices"
grep -Fxq 'method=auto' "$C/nm-wired"
grep -Fxq 'PasswordAuthentication no' "$C/ssh-config"
! awk '$3=="swap" {found=1} END{exit !found}' "$C/fstab"
for p in swap.target zramswap.service; do
  debugfs -R "stat /etc/systemd/system/$p" "$root" 2>&1 | grep -F 'Fast link dest: "/dev/null"'
done
! debugfs -R 'ls /etc/ssh' "$root" 2>&1 | grep -F 'ssh_host_'
printf 'Offline file-image checks passed: %s\n' "$media"
