#!/bin/bash
# Offline only: apply the overlay to a temporary copy of the stable DTB.
set -euo pipefail
export LC_ALL=C
[[ $# = 1 && -f $1 ]]
here=$(dirname "$(readlink -f "$0")")
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
dtc -@ -I dts -O dtb -o "$tmp/timing.dtbo" "$here/k4-i2c2-android-timing.dts"
fdtoverlay -i "$1" -o "$tmp/merged.dtb" "$tmp/timing.dtbo"
for prop in clock-frequency:200000 i2c-scl-rising-time-ns:800 i2c-scl-falling-time-ns:40; do
    [[ $(fdtget -t u "$tmp/merged.dtb" /i2c@ff120000 "${prop%:*}") = "${prop#*:}" ]]
    fdtput -d "$tmp/merged.dtb" /i2c@ff120000 "${prop%:*}"
done
dtc -qs -I dtb -O dts -o "$tmp/stable.dts" "$1"
dtc -qs -I dtb -O dts -o "$tmp/merged.dts" "$tmp/merged.dtb"
cmp "$tmp/stable.dts" "$tmp/merged.dts"
echo 'Only the three expected I2C timing properties differ.'
