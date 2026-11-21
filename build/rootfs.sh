#!/bin/bash
set -euo pipefail
cd /task
export LC_ALL=C
R=/task/work/jammy
B=ubuntu-base-22.04.5-base-arm64.tar.gz
if [[ ! -f work/base-extracted ]]; then
  mkdir -p "$R"
  tar -xzp --numeric-owner -f "work/cache/$B" -C "$R"
  touch work/base-extracted
fi
mkdir -p /tmp/k4-binfmt
mount -t binfmt_misc binfmt_misc /tmp/k4-binfmt
python3 - <<'PY'
with open('/tmp/k4-binfmt/register', 'wb') as f:
    f.write(rb':qemu-aarch64:M::\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\xb7\x00:\xff\xff\xff\xff\xff\xff\xff\x00\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff:/usr/bin/qemu-aarch64-static:F')
PY
mount --rbind /proc "$R/proc"
mount --rbind /dev "$R/dev"
mount -t tmpfs tmpfs "$R/run"
mkdir -p "$R/tmp"
chmod 1777 "$R/tmp"
if [[ ${1:-} == smoke.sh ]]; then
  exec build/smoke.sh "$R"
fi
# No target daemons may run during package configuration.
printf '#!/bin/sh\nexit 101\n' > "$R/usr/sbin/policy-rc.d"
chmod 755 "$R/usr/sbin/policy-rc.d"
rm -f "$R/etc/resolv.conf"
cp -L /etc/resolv.conf "$R/etc/resolv.conf"
install -m 644 build/jammy.list "$R/etc/apt/sources.list"
# Ubuntu Base ships no HTTPS CA store. Use the build container store only until apt installs its own.
if [[ ! -s "$R/etc/ssl/certs/ca-certificates.crt" ]]; then
  install -D -m 644 /etc/ssl/certs/ca-certificates.crt "$R/etc/ssl/certs/ca-certificates.crt"
fi
cat > "$R/etc/apt/apt.conf.d/80k4-build" <<'EOF'
Acquire::Retries "5";
Acquire::ForceIPv4 "true";
Acquire::https::Timeout "30";
Dpkg::Use-Pty "0";
APT::Install-Recommends "false";
EOF
if [[ ${1:-packages} == packages ]]; then
  cp build/target-packages.sh "$R/tmp/k4-target-packages.sh"
  chroot "$R" /usr/bin/env -i PATH=/usr/sbin:/usr/bin:/sbin:/bin HOME=/root TERM=dumb LC_ALL=C DEBIAN_FRONTEND=noninteractive /bin/bash /tmp/k4-target-packages.sh
  rm -f "$R/tmp/k4-target-packages.sh"
  touch work/packages-complete
else
  "build/$1" "$R"
fi
