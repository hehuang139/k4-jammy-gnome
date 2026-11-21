#!/bin/bash
set -euo pipefail
export LC_ALL=C
cd /task
source build/layout.env
test -f work/configured
[[ ! -s work/jammy/etc/machine-id ]]
R=work/jammy
BOOT=work/boot-staging
scratch=work
if [[ -d /scratch ]]; then scratch=/scratch; fi
raw=$scratch/release.img
bootimg=$scratch/release-boot.ext4
rootimg=$scratch/release-root.ext4
boot_bytes=$(((BOOT_END-BOOT_LBA+1)*512))
root_bytes=$((IMAGE_BYTES - (ROOT_LBA+TAIL_SECTORS)*512))
root_end=$((IMAGE_BYTES/512 - TAIL_SECTORS - 1))
test ! -e "$R/dev/null" # no container mount attached to staging tree
mkdir -p "$BOOT" outputs/v2
rsync -aH --delete --exclude /lost+found --exclude /armbian_first_run.txt.template --exclude /extlinux.conf.bak --exclude /extlinux/ --exclude "/initrd.img-$KVER" --exclude "/uInitrd-$KVER" work/board-boot/ "$BOOT/"
install -m 644 "work/uInitrd-$KVER" "$BOOT/uInitrd-$KVER"
dumpimage -T ramdisk -p 0 -o "$BOOT/initrd.img-$KVER" "$BOOT/uInitrd-$KVER"
test -L "$BOOT/Image" && test -L "$BOOT/uInitrd"
rm -f work/image-metadata.tsv.tmp outputs/v2/K4-Jammy-GNOME-eMMC.raw.sha256.tmp
for media in TF eMMC; do
  upper=${media^^}
  disk=${upper}_DISK; bpart=${upper}_BOOT_PART; rpart=${upper}_ROOT_PART
  buuid=${upper}_BOOT_UUID; ruuid=${upper}_ROOT_UUID
  blabel=K4J_${upper}_BOOT
  rlabel=K4J_${upper}_ROOT
  filename=K4-Jammy-GNOME-${media}.img.zst
  sed -e "s/^rootdev=.*/rootdev=UUID=${!ruuid}/" work/board-boot/armbianEnv.txt > "$BOOT/armbianEnv.txt"
  # Env import expects LF-delimited key=value pairs.
  printf '\n' >> "$BOOT/armbianEnv.txt"
  grep -Fx "rootdev=UUID=${!ruuid}" "$BOOT/armbianEnv.txt"
  cat > "$R/etc/fstab" <<EOF
# Liontron K4 / $media
UUID=${!ruuid} / ext4 defaults,noatime,errors=remount-ro 0 1
UUID=${!buuid} /boot ext4 defaults,noatime 0 2
EOF
  printf '%s\n' "$media" > "$R/etc/k4-boot-medium"
  cat > "$R/etc/k4-image-layout" <<EOF
DISK_GUID=${!disk}
BOOT_PARTUUID=${!bpart}
ROOT_PARTUUID=${!rpart}
BOOT_UUID=${!buuid}
ROOT_UUID=${!ruuid}
IMAGE_SECTORS=$((IMAGE_BYTES/512))
BOOT_START=$BOOT_LBA
BOOT_END=$BOOT_END
ROOT_START=$ROOT_LBA
ROOT_MIN_END=$root_end
EOF
  rm -f "$raw" "$bootimg" "$rootimg"
  truncate -s "$boot_bytes" "$bootimg"
  truncate -s "$root_bytes" "$rootimg"
  mkfs.ext4 -q -F -b 4096 -m 0 -O '^64bit,^metadata_csum' -E lazy_itable_init=0,lazy_journal_init=0 -U "${!buuid}" -L "$blabel" -d "$BOOT" "$bootimg"
  mkfs.ext4 -q -F -b 4096 -m 1 -E lazy_itable_init=0,lazy_journal_init=0 -U "${!ruuid}" -L "$rlabel" -d "$R" "$rootimg"
  e2fsck -fn "$bootimg"
  e2fsck -fn "$rootimg"
  df -h /task
  truncate -s "$IMAGE_BYTES" "$raw"
  dd if=work/board-prefix.bin of="$raw" bs=512 skip=64 seek=64 count=$((BOOT_LBA-64)) conv=notrunc,sparse status=none
  sgdisk --clear --disk-guid="${!disk}" \
    --new="1:$BOOT_LBA:$BOOT_END" --typecode=1:8300 --change-name="1:$blabel" --partition-guid="1:${!bpart}" \
    --new="2:$ROOT_LBA:$root_end" --typecode=2:8300 --change-name="2:$rlabel" --partition-guid="2:${!rpart}" "$raw"
  dd if="$bootimg" of="$raw" bs=1M seek=$((BOOT_LBA/2048)) conv=notrunc,sparse status=none
  dd if="$rootimg" of="$raw" bs=1M seek=$((ROOT_LBA/2048)) conv=notrunc,sparse status=none
  rm "$bootimg" "$rootimg"
  sgdisk -v "$raw"
  cmp -n $(((BOOT_LBA-64)*512)) -i 32768 "$raw" work/board-prefix.bin
  test "$(stat -c%s "$raw")" = "$IMAGE_BYTES"
  sha=$(sha256sum "$raw" | cut -d' ' -f1)
  zstd -T4 -8 --check -f -q "$raw" -o "outputs/v2/$filename.tmp"
  mv "outputs/v2/$filename.tmp" "outputs/v2/$filename"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$media" "$filename" "$IMAGE_BYTES" "$sha" "${!buuid}" "${!ruuid}" "${!rpart}" >>work/image-metadata.tsv.tmp
  if [[ $media = eMMC ]]; then
    printf '%s\n' "$sha" >outputs/v2/K4-Jammy-GNOME-eMMC.raw.sha256.tmp
  fi
  rm "$raw"
done
mv work/image-metadata.tsv.tmp outputs/v2/image-metadata.tsv
mv outputs/v2/K4-Jammy-GNOME-eMMC.raw.sha256.tmp outputs/v2/K4-Jammy-GNOME-eMMC.raw.sha256
