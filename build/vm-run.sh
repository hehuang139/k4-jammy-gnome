#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source build/layout.env
[[ $# = 2 ]]
media=$1
case_name=$2
[[ $media = TF || $media = eMMC ]]
case $case_name in minimum|stale-gpt|installer|grown-gpt) ;; *) exit 2;; esac
[[ $case_name != installer && $case_name != grown-gpt || $media = eMMC ]]
key=${media^^}_ROOT_UUID
vm=work/v2-vm-$media-$case_name
install -d -m 700 "$vm"
exec docker run --rm --network none --user "$(id -u):$(id -g)" --name "k4-v2-${media,,}-$case_name" \
  --mount "type=bind,src=$PWD,dst=/task" --tmpfs /scratch:rw,size=9g,mode=1777 --workdir /task lzk4-jammy-vm:local \
  /bin/bash -ec '
  set -o pipefail
  media=$1; case_name=$2; vm=$3; root_uuid=$4; kver=$5; root_lba=$6; emmc_root_part=$7
  export TMPDIR=/scratch LC_ALL=C
  disk=/scratch/disk.img
  case $case_name in
    installer|grown-gpt)
      truncate -s 16000000000 "$disk"
      bash outputs/v2/install-emmc.sh --file "$disk"
      if [[ $case_name = grown-gpt ]]; then
        # Simulate interruption after GPT was written, before the filesystem resize.
        sgdisk --delete=2 --new="2:$root_lba:0" --typecode=2:8300 \
          --change-name=2:K4J_EMMC_ROOT --partition-guid="2:$emmc_root_part" "$disk"
      fi
      ;;
    *)
      zstd -dc "outputs/v2/K4-Jammy-GNOME-$media.img.zst" |
        dd bs=4M iflag=fullblock conv=sparse of="$disk" status=none
      if [[ $case_name = stale-gpt ]]; then truncate -s 16000000000 "$disk"; fi
      ;;
  esac
  dumpimage -T ramdisk -p 0 -o /scratch/k4-initrd "/task/work/uInitrd-$kver"
  exec qemu-system-aarch64 -machine virt,accel=tcg -cpu cortex-a72 -smp 4 -m 2048 \
    -kernel "/task/work/board-boot/vmlinuz-$kver" -initrd /scratch/k4-initrd \
    -append "root=UUID=$root_uuid rootwait rootfstype=ext4 rw console=tty1 console=ttyAMA0,115200" \
    -drive "file=$disk,if=none,id=disk,format=raw,snapshot=on" -device virtio-blk-pci,drive=disk \
    -device virtio-rng-pci -device virtio-gpu-pci -device qemu-xhci -device usb-kbd -device usb-tablet \
    -netdev user,id=testnet,restrict=on,hostfwd=tcp:127.0.0.1:2222-:22 -device virtio-net-pci,netdev=testnet,romfile= -display none \
    -chardev "socket,id=ser,path=/task/$vm/serial.sock,server=on,wait=off,logfile=/task/$vm/serial.log" -serial chardev:ser \
    -qmp "unix:/task/$vm/qmp.sock,server=on,wait=off" -no-reboot
  ' vm-run "$media" "$case_name" "$vm" "${!key}" "$KVER" "$ROOT_LBA" "$EMMC_ROOT_PART"
