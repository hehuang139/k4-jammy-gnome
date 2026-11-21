#!/bin/bash
set -euo pipefail
cd /task
R=$1
export LC_ALL=C
# dbus/IBus need a machine-id even in a throwaway chroot; the release image must have none.
[[ ! -s $R/etc/machine-id ]]
tr -d '-' </proc/sys/kernel/random/uuid > "$R/etc/machine-id"
trap ': > "$R/etc/machine-id"; rm -rf "$R/tmp/k4-smoke.sh" "$R/tmp/k4-ibus-smoke.sh" "$R/tmp/k4-smoke-home" "$R/tmp/k4-smoke-runtime"' EXIT
cat > "$R/tmp/k4-ibus-smoke.sh" <<'EOF'
#!/bin/bash
set -euo pipefail
[[ $(gsettings get org.gnome.desktop.input-sources sources) = "[('xkb', 'us'), ('ibus', 'libpinyin')]" ]]
gsettings get org.gnome.desktop.input-sources sources
export DISPLAY=:42
ibus-daemon --daemonize --replace --single
trap 'ibus exit 2>/dev/null || :' EXIT
for i in $(seq 1 12); do
  if ibus list-engine > "$HOME/engines" 2>/dev/null; then break; fi
  sleep 1
done
grep -E '^[[:space:]]*libpinyin[[:space:]]+-' "$HOME/engines"
# Engine activation is a graphical-session check, not a headless chroot check.
test -x /usr/libexec/ibus-engine-libpinyin
EOF
cat > "$R/tmp/k4-smoke.sh" <<'EOF'
#!/bin/bash
set -euo pipefail
set -x
[[ $(uname -m) = aarch64 ]]
[[ $(dpkg --print-architecture) = arm64 ]]
. /etc/os-release
[[ $ID = ubuntu && $VERSION_ID = 22.04 && $VERSION_CODENAME = jammy ]]
[[ $(locale -a | grep -x zh_CN.utf8) = zh_CN.utf8 ]]
LC_ALL=zh_CN.UTF-8 locale charmap | grep -x UTF-8
fc-match -f '%{family}\n' 'sans-serif:lang=zh-cn' | grep -F 'Noto Sans CJK SC'
gnome-shell --version
/usr/sbin/gdm3 --version
[[ $(gsettings get org.gnome.desktop.input-sources sources) = "[('xkb', 'us'), ('ibus', 'libpinyin')]" ]]
gsettings get org.gnome.desktop.wm.keybindings switch-input-source
dpkg-query -W -f='${Package}\t${Version}\t${Architecture}\n' gdm3 gnome-session gnome-shell ibus ibus-libpinyin fonts-noto-cjk network-manager openssh-server gnome-remote-desktop libgl1-mesa-dri
install -d -m700 -o nobody -g nogroup /tmp/k4-smoke-home /tmp/k4-smoke-runtime
su -s /bin/bash nobody -c 'env -i PATH=/usr/bin:/bin LANG=zh_CN.UTF-8 HOME=/tmp/k4-smoke-home XDG_RUNTIME_DIR=/tmp/k4-smoke-runtime dbus-run-session -- /bin/bash /tmp/k4-ibus-smoke.sh'
EOF
chroot "$R" /bin/bash /tmp/k4-smoke.sh
