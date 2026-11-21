#!/bin/bash
# Install the exact field-tested vendor DEB on the target, outside the image build.
set -euo pipefail
export LC_ALL=C
[[ $EUID = 0 && $# = 1 && -f $1 ]] || { echo "Usage: sudo $0 /path/to/vendor-arm64.deb" >&2; exit 2; }
. /etc/os-release
[[ $ID = ubuntu && $VERSION_CODENAME = jammy && $(dpkg --print-architecture) = arm64 ]] || exit 2
staging=$(mktemp -d)
trap 'rm -rf -- "$staging"' EXIT
chmod 755 "$staging"
package=$staging/sogoupinyin_4.2.1.145_arm64.deb
install -m 644 -- "$1" "$package"
printf '%s  %s\n' '216341466a2972a0cf912db21adda0e613f15a8b562398fc9da0516cdafcc1ae' "$package" | sha256sum -c --strict -
[[ $(dpkg-deb -f "$package" Package) = sogoupinyin && $(dpkg-deb -f "$package" Version) = 4.2.1.145 && $(dpkg-deb -f "$package" Architecture) = arm64 ]]
for soname in libpango-1.0.so.0 libpangoft2-1.0.so.0; do
    path=/opt/sogoupinyin/files/lib/$soname
    dpkg-divert --local --add --rename --divert "$path.k4-vendor" "$path"
done
apt-get install --no-install-recommends \
    fcitx fcitx-frontend-gtk2 fcitx-frontend-gtk3 fcitx-frontend-qt5 fcitx-module-x11 \
    qml-module-qtquick2 qml-module-qtquick-controls qml-module-qtquick-layouts qml-module-qtquick-window2 \
    libqt5svg5 libgsettings-qt1 libxss1 libpango-1.0-0 libpangoft2-1.0-0 "$package"
printf '%s\n' 'As your desktop user, run im-config -n fcitx, then log out and back in. Add Sogou Pinyin in fcitx-configtool (install fcitx-config-gtk if needed).'
