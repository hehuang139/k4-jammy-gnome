#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
umask 022
mkdir -p work/cache logs
cache=$PWD/work/cache
fetch() {
 local url=$1 dest=$2
 if [[ ! -f $dest ]]; then
   for attempt in 1 2 3 4 5; do
     if curl --fail --location --show-error --silent --retry 3 --retry-connrefused --connect-timeout 20 --continue-at - "$url" -o "$dest.part"; then
       break
     else
       rc=$?
     fi
     if [[ $rc = 33 ]]; then
       # Metadata/small mirrors may not support Range. Keep the partial unless a fresh copy succeeds.
       curl --fail --location --show-error --silent --retry 3 --connect-timeout 20 "$url" -o "$dest.fresh"
       mv "$dest.fresh" "$dest.part"
       break
     fi
     [[ $attempt != 5 ]] || return "$rc"
     sleep "$attempt"
   done
   mv "$dest.part" "$dest"
 fi
}
case ${1:-all} in
all|board)
 board=Armbian_26.11.0_rockchip_lzk4_bookworm_6.18.57_server_2026.10.19.img.gz
 digest=14aa496c134817ec4b47d1eabd287859caaf1058234c327b30ec8d300729018f
 fetch https://api.github.com/repos/ophub/amlogic-s9xxx-armbian/releases/tags/Armbian_bookworm_arm64_server_2026.10 "$cache/ophub-release.json"
 jq -e --arg name "$board" --arg digest "sha256:$digest" '.assets[]|select(.name==$name and .digest==$digest)' "$cache/ophub-release.json" > logs/ophub-asset.json
 board_url=$(jq -r .browser_download_url logs/ophub-asset.json)
 python3 build/fetch-ranges.py "$board_url" "$cache/$board" "$(jq -r .size logs/ophub-asset.json)"
 (cd "$cache"; sha256sum -c <<<"$digest  $board")
 ;;
esac
case ${1:-all} in
all|ubuntu)
 ubuntu_url=https://cdimage.ubuntu.com/ubuntu-base/releases/22.04/release
 ubuntu=ubuntu-base-22.04.5-base-arm64.tar.gz
 fetch "$ubuntu_url/SHA256SUMS" "$cache/ubuntu.SHA256SUMS"
 fetch "$ubuntu_url/SHA256SUMS.gpg" "$cache/ubuntu.SHA256SUMS.gpg"
 gpgv --keyring /usr/share/keyrings/ubuntu-cloudimage-keyring.gpg "$cache/ubuntu.SHA256SUMS.gpg" "$cache/ubuntu.SHA256SUMS" || gpgv --keyring /usr/share/keyrings/ubuntu-archive-keyring.gpg "$cache/ubuntu.SHA256SUMS.gpg" "$cache/ubuntu.SHA256SUMS"
 fetch "$ubuntu_url/$ubuntu" "$cache/$ubuntu"
 (cd "$cache"; grep -F "$ubuntu" ubuntu.SHA256SUMS | sha256sum -c)
 ;;
esac
