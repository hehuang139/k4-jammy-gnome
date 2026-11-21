#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export K4_DOCKER_NETWORK=none LC_ALL=C
# The published image uses ext4 orphan_file. Jammy e2fsck 1.46 cannot check stock ext4.
fsck_image=${K4_FSCK_IMAGE:-ubuntu@sha256:678c6550cc43645e08669028bc177f50be4e7c5b8cca677067b1914d4afc7a03}
if [[ ! -f work/board-split ]]; then
  build/docker-run.sh build/unpack-board.sh split
  touch work/board-split
fi
docker run --rm --network none --mount "type=bind,src=$PWD/work,dst=/task,readonly" "$fsck_image" /bin/sh -ec '
  /sbin/e2fsck -V
  /sbin/e2fsck -fn /task/board-boot.img
  /sbin/e2fsck -fn /task/board-os.img
'
build/docker-run.sh build/unpack-board.sh extract
unlink work/board-split
