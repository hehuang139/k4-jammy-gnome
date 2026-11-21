#!/bin/bash
set -euo pipefail
cd /task
export LC_ALL=C
source build/layout.env
asset=Armbian_26.11.0_rockchip_lzk4_bookworm_6.18.57_server_2026.10.19.img.gz
(cd work/cache; sha256sum -c <<<"14aa496c134817ec4b47d1eabd287859caaf1058234c327b30ec8d300729018f  $asset")
mkdir -p work/board-boot work/board-os
if [[ ${1:-} = split ]]; then
# The stock image's GPT has the required partition starts. Keep the entire reserved loader region.
gzip -dc "work/cache/$asset" | {
  dd iflag=fullblock bs=1M count=16 of=work/board-prefix.bin status=none
  dd iflag=fullblock bs=1M count=511 of=work/board-boot.img conv=sparse status=none
  dd iflag=fullblock bs=1M count=1 of=/dev/null status=none
  dd iflag=fullblock bs=1M count=2999 of=work/board-os.img conv=sparse status=none
  dd iflag=fullblock bs=1M count=1 of=work/board-tail.bin status=none
  test "$(wc -c)" = 0
}
[[ $(stat -c%s work/board-prefix.bin) = $((BOOT_LBA*512)) ]]
[[ $(stat -c%s work/board-boot.img) = $(((BOOT_END-BOOT_LBA+1)*512)) ]]
[[ $(stat -c%s work/board-os.img) = $((2999*1024*1024)) ]]
[[ $(stat -c%s work/board-tail.bin) = $((1024*1024)) ]]
python3 - <<'PY'
import struct
with open('work/board-prefix.bin','rb') as f:
    p=f.read(3*512)
assert p[512:520] == b'EFI PART'
assert struct.unpack_from('<QQ',p,1024+32) == (32768,1079295)
assert struct.unpack_from('<QQ',p,1024+128+32) == (1081344,7223295)
PY
blkid -p work/board-boot.img work/board-os.img
exit 0
fi
[[ ${1:-} = extract ]]
debugfs -R 'rdump / work/board-boot' work/board-boot.img
lib=/usr/lib
if ! debugfs -R 'stat /usr/lib/modules' work/board-os.img 2>&1 | grep -q '^Inode:'; then lib=/lib; fi
debugfs -R "rdump $lib/modules work/board-os" work/board-os.img
debugfs -R "rdump $lib/firmware work/board-os" work/board-os.img
debugfs -R "rdump /etc/modprobe.d work/board-os" work/board-os.img
[[ -d work/board-os/modules/$KVER ]]
[[ -d work/board-os/firmware ]]
[[ -f work/board-boot/dtb/rockchip/rk3399-lzk4.dtb ]]
[[ -f work/board-boot/vmlinuz-$KVER && -f work/board-boot/boot.scr ]]
[[ $(readlink work/board-boot/Image) == "vmlinuz-$KVER" ]]
[[ $(readlink work/board-boot/uInitrd) == "uInitrd-$KVER" ]]
dumpimage -l work/board-boot/boot.scr
dumpimage -l work/board-boot/uInitrd
fdtget work/board-boot/dtb/rockchip/rk3399-lzk4.dtb / model
fdtget work/board-boot/dtb/rockchip/rk3399-lzk4.dtb / compatible
rm work/board-boot.img work/board-os.img work/board-tail.bin
touch work/board-complete
