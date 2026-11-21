#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export LC_ALL=C K4_DOCKER_NETWORK=none
source build/layout.env
[[ -f outputs/v2/image-metadata.tsv ]]
if [[ ${1:-} != in-container ]]; then
  exec env K4_DOCKER_NETWORK=none K4_DOCKER_SCRATCH=${K4_DOCKER_SCRATCH:-9g} build/docker-run.sh build/verify-release.sh in-container
fi
install -m 755 release/install-emmc.sh outputs/v2/install-emmc.sh
# The installer needs a manifest during the file test. Do not leave an
# apparently complete manifest if a subsequent validation step fails.
trap 'if [[ ! -f work/images-verified-v2 ]]; then rm -f outputs/v2/SHA256SUMS outputs/v2/.SHA256SUMS.stage; fi' EXIT
(
  cd outputs/v2
  sha256sum K4-Jammy-GNOME-{TF,eMMC}.img.zst K4-Jammy-GNOME-eMMC.raw.sha256 image-metadata.tsv install-emmc.sh >.SHA256SUMS.stage
  mv .SHA256SUMS.stage SHA256SUMS
  sha256sum -c --strict SHA256SUMS
  zstd -t K4-Jammy-GNOME-{TF,eMMC}.img.zst
)
scratch=/scratch
[[ -d $scratch ]]
# Everything written below is a task-local regular file, never a host block device.
[[ ! -e "$scratch/tf-sim.img" || -f "$scratch/tf-sim.img" && ! -L "$scratch/tf-sim.img" ]]
zstd -dc outputs/v2/K4-Jammy-GNOME-TF.img.zst | dd bs=4M iflag=fullblock conv=sparse,fsync of="$scratch/tf-sim.img" status=none
actual=$(sha256sum "$scratch/tf-sim.img" | cut -d' ' -f1)
expect=$(awk -F '\t' '$1=="TF" {print $4}' outputs/v2/image-metadata.tsv)
[[ $(stat -c%s "$scratch/tf-sim.img") = "$IMAGE_BYTES" && $actual = "$expect" ]]
printf 'TF image readback: %s (%s bytes)\n' "$actual" "$IMAGE_BYTES"
build/verify-image.sh TF "$scratch/tf-sim.img"
unlink "$scratch/tf-sim.img"
[[ ! -e "$scratch/emmc-too-small.img" || -f "$scratch/emmc-too-small.img" && ! -L "$scratch/emmc-too-small.img" ]]
truncate -s "$((IMAGE_BYTES-512))" "$scratch/emmc-too-small.img"
if outputs/v2/install-emmc.sh --file "$scratch/emmc-too-small.img"; then
  echo 'Installer accepted an undersized target' >&2; exit 1
fi
[[ $(stat -c %s "$scratch/emmc-too-small.img") = "$((IMAGE_BYTES-512))" && $(du -B1 "$scratch/emmc-too-small.img" | cut -f1) = 0 ]]
unlink "$scratch/emmc-too-small.img"
[[ ! -e "$scratch/emmc-sim.img" || -f "$scratch/emmc-sim.img" && ! -L "$scratch/emmc-sim.img" ]]
truncate -s 16000000000 "$scratch/emmc-sim.img"
# An old backup header at the end should not win over the new primary GPT.
sgdisk --clear --new=1:2048:0 --change-name=1:prior-system "$scratch/emmc-sim.img"
printf 'K4-old-tail-test' | dd of="$scratch/emmc-sim.img" bs=1 seek=12000000000 conv=notrunc status=none
outputs/v2/install-emmc.sh --file "$scratch/emmc-sim.img"
[[ $(stat -c%s "$scratch/emmc-sim.img") = 16000000000 ]]
[[ $(dd if="$scratch/emmc-sim.img" bs=1 skip=12000000000 count=16 status=none) = K4-old-tail-test ]]
build/verify-image.sh eMMC "$scratch/emmc-sim.img"
# Confirm that the new alternate GPT header resides at the actual last sector.
[[ $(dd if="$scratch/emmc-sim.img" bs=512 skip="$((16000000000/512-1))" count=1 status=none | head -c8) = 'EFI PART' ]]
touch work/images-verified-v2
