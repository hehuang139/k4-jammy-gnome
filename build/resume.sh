#!/bin/bash
# Reusable entry point; stage markers preserve the original work after an interruption.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p work logs outputs
exec 9>work/build.lock
flock -n 9 || { echo 'A build/resume.sh process is already running' >&2; exit 1; }
export LC_ALL=C
stage=initialization
say() { printf '[%s] %s\n' "$(date -Is)" "$*" | tee -a logs/stages.log; }
trap 'err=$?; say "ERROR: $stage (exit $err); see logs/; rerun build/resume.sh after restoring the failed stage"; printf "\n- %s：阶段 %s 退出 %s；查看 logs/，修复后用 build/resume.sh 恢复。\n" "$(date -Is)" "$stage" "$err" >> STATUS.md; exit "$err"' ERR
stage=assets; say "$stage"
flock -x work/fetch-board.lock bash -c 'build/fetch.sh board >>logs/fetch-board.log 2>&1'
build/fetch.sh ubuntu >>logs/fetch-ubuntu.log 2>&1
stage=tools; say "$stage"
if ! docker image inspect lzk4-jammy-tools:local >/dev/null 2>&1; then
  DOCKER_BUILDKIT=0 docker build -t lzk4-jammy-tools:local build >>logs/builder-resume.log 2>&1
fi
stage=board; say "$stage"
flock -x work/board-stage.lock bash -ec '[[ -f work/board-complete ]] || build/board-stage.sh >>logs/board-stage.log 2>&1'
stage=packages; say "$stage"
flock -x work/rootfs.lock bash -ec '[[ -f work/packages-complete ]] || build/docker-run.sh python3 build/private-userns.py bash build/rootfs.sh packages >>logs/rootfs.log 2>&1'
export K4_DOCKER_NETWORK=none
stage=configure; say "$stage"
flock -x work/rootfs.lock bash -ec '[[ -f work/configured ]] || build/docker-run.sh python3 build/private-userns.py bash build/rootfs.sh configure-target.sh >>logs/configure.log 2>&1'
stage=arm64-smoke; say "$stage"
if [[ ! -f work/smoke-complete ]]; then
  flock -x work/rootfs.lock build/docker-run.sh python3 build/private-userns.py bash build/rootfs.sh smoke.sh >>logs/arm64-smoke.log 2>&1
  touch work/smoke-complete
fi
stage=assemble; say "$stage"
if [[ ! -f work/assembled-v2 ]]; then
  K4_DOCKER_SCRATCH=${K4_DOCKER_SCRATCH:-9g} build/docker-run.sh build/assemble.sh >>logs/assemble.log 2>&1
  touch work/assembled-v2
fi
stage=verify; say "$stage"
if [[ ! -f work/images-verified-v2 ]]; then
  build/verify-release.sh >>logs/verify-release.log 2>&1
fi
say 'Both compressed variants and regular-file eMMC installation verified.'
