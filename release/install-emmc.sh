#!/bin/bash
# Run on the K4 TF system, or use --file with a disposable regular file for offline verification.
set -euo pipefail
export LC_ALL=C
usage() { echo "Usage: $0 --device /dev/mmcblkN | --file preallocated-disposable-file.img" >&2; exit 2; }
die() { echo "ERROR: $*" >&2; exit 1; }
[[ $# = 2 ]] || usage
home=$(cd -- "$(dirname -- "$0")" && pwd -P)
image=K4-Jammy-GNOME-eMMC.img.zst
raw_sum=$home/K4-Jammy-GNOME-eMMC.raw.sha256
min=7516192768
tf_uuid=9b255e1c-c95a-4e12-8a8e-20830a3f0755
emmc_part=b74da222-f313-485e-90eb-47fbe86da0e5
[[ ! -L "$2" || $1 = --device ]] || die 'file target cannot be a symlink'
target=$(realpath -e -- "$2") || die 'target does not exist'
[[ $target != "$home/$image" && $target != "$raw_sum" ]] || die 'target overlaps source'
case $1 in
  --file)
    [[ -f $target && $(stat -c %h "$target") = 1 ]] || die '--file needs a preallocated regular file with one link'
    [[ ! $target -ef $home/$image && ! $target -ef $raw_sum && ! $target -ef $home/SHA256SUMS && ! $target -ef $0 ]] || die 'target overlaps installer inputs'
    size=$(stat -c %s -- "$target")
    mode=file
    ;;
  --device)
    [[ $EUID = 0 ]] || die 'run with sudo on the K4 TF system'
    [[ $target =~ ^/dev/mmcblk[0-9]+$ && -b $target ]] || die 'specify the whole eMMC user-area device, not a partition or boot0/boot1'
    name=${target##*/}
    [[ $(cat "/sys/class/block/$name/device/type") = MMC && $(cat "/sys/class/block/$name/removable") = 0 ]] || die 'selected device is not non-removable eMMC'
    [[ $(tr '\0' '\n' </proc/device-tree/compatible | grep -x liontron,lzk4) ]] || die 'not an RK3399 device tree'
    [[ $(cat /etc/k4-boot-medium) = TF ]] || die 'not running the delivered TF system'
    root=$(findmnt -n -o SOURCE --mountpoint /)
    [[ $(blkid -s UUID -o value -- "$root") = "$tf_uuid" ]] || die 'root UUID does not match the released TF image'
    tf_disk=$(lsblk -ndo PKNAME -- "$root")
    [[ -n $tf_disk && $tf_disk != "$name" && $(cat "/sys/class/block/$tf_disk/device/type") = SD ]] || die 'running root is not on a separate SD card'
    assert_idle() {
      local node id swapdev
      local -a nodes holders
      mapfile -t nodes < <(lsblk -nrpo NAME -- "$target")
      [[ ${#nodes[@]} -ge 1 && ${nodes[0]} = "$target" ]] || die 'cannot enumerate target devices'
      shopt -s nullglob
      for node in "${nodes[@]}"; do
        id=$(lsblk -ndro MAJ:MIN -- "$node")
        [[ -n $id ]] || die "cannot identify $node"
        if findmnt -rn -o MAJ:MIN | grep -Fx "$id" >/dev/null; then die "unmount $node first"; fi
        while read -r swapdev; do
          [[ ! $node -ef $swapdev ]] || die "disable swap on $node first"
        done < <(swapon --noheadings --raw --show=NAME)
        holders=(/sys/dev/block/"$id"/holders/*)
        [[ ${#holders[@]} = 0 ]] || die "$node has active holders"
      done
    }
    assert_idle
    [[ $(blockdev --getss "$target") = 512 ]] || die 'target logical sector size is not 512 bytes'
    [[ $(blockdev --getro "$target") = 0 ]] || die 'eMMC is read-only'
    size=$(blockdev --getsize64 "$target")
    mode=device
    ;;
  *) usage ;;
esac
[[ $size -ge $min && $((size%512)) = 0 ]] || die "target requires at least $min bytes and 512-byte alignment; got $size"
for c in zstd sgdisk sha256sum dd; do command -v "$c" >/dev/null || die "missing tool: $c"; done
[[ -f $home/$image && -f $home/SHA256SUMS && -f $raw_sum ]] || die 'keep the eMMC image, SHA256SUMS and eMMC raw SHA256 next to this script'
(cd "$home"; awk -v f="$image" -v s="${raw_sum##*/}" '$2==f{print; n++} $2==s{print; m++} END{if(n!=1 || m!=1) exit 1}' SHA256SUMS | sha256sum -c --strict)
read -r expected < "$raw_sum"
[[ $expected =~ ^[0-9a-f]{64}$ ]] || die 'invalid expected raw SHA256'
printf 'Target: %s (%s bytes); image: %s (%s bytes)\n' "$target" "$size" "$image" "$min"
if [[ $mode = device ]]; then
  lsblk -b -o NAME,SIZE,TYPE,RO,RM,MOUNTPOINTS -- "$target"
  echo 'The eMMC user area (including Android) will be overwritten. Back up to other storage first.'
  printf 'Type ERASE %s to proceed: ' "$target" >/dev/tty
  IFS= read -r answer </dev/tty
  [[ $answer = "ERASE $target" ]] || die 'cancelled'
  assert_idle
fi
# No partition mount or loop setup: write the RK3399 loader slots and both GPT partitions as one image.
if [[ $mode = file ]]; then
  # Treat the written prefix as zero before skipping zero blocks, preserving the old tail.
  # Fall back to full writes if the target filesystem does not support hole punching.
  conv=notrunc,fsync
  if command -v fallocate >/dev/null && fallocate --punch-hole --keep-size --offset 0 --length "$min" -- "$target"; then
    conv=notrunc,sparse,fsync
  fi
  zstd -dc -- "$home/$image" | dd of="$target" bs=4M iflag=fullblock conv="$conv" status=progress
else
  zstd -dc -- "$home/$image" | dd of="$target" bs=4M iflag=fullblock conv=notrunc,fsync status=progress
  blockdev --flushbufs "$target"
fi
actual=$(dd if="$target" bs=4M iflag=fullblock,count_bytes count="$min" status=none | sha256sum | cut -d' ' -f1)
[[ $actual = "$expected" ]] || die "write/readback mismatch: $actual (expected $expected)"
printf 'Readback SHA256: %s (%s bytes)\n' "$actual" "$min"
if [[ $size -gt $min ]]; then
  # Do this only after byte-for-byte verification; this intentionally changes GPT metadata.
  sgdisk --move-second-header "$target"
fi
report=$(sgdisk -v "$target")
printf '%s\n' "$report"
grep -Fq 'No problems found' <<< "$report" || die 'GPT verification failed'
sgdisk -i 2 "$target" | grep -Fi "Partition unique GUID: $emmc_part" >/dev/null || die 'unexpected eMMC PARTUUID'
sync
if [[ $mode = device ]]; then
  echo 'Install verified. Power off, remove TF and USB, disconnect power, then power on.'
else
  echo 'File-backed eMMC layout verified.'
fi
