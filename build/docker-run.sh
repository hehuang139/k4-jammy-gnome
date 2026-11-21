#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
scratch=()
if [[ ${K4_DOCKER_SCRATCH:-0} != 0 ]]; then scratch=(--tmpfs "/scratch:rw,size=$K4_DOCKER_SCRATCH,mode=1777"); fi
exec docker run --rm "${scratch[@]}" --network "${K4_DOCKER_NETWORK:-bridge}" --cap-add SYS_ADMIN --security-opt seccomp=unconfined --security-opt apparmor=unconfined \
  --mount "type=bind,src=$PWD,dst=/task" --workdir /task lzk4-jammy-tools:local "$@"
