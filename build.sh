#!/bin/bash
#
# Build Sury's patched PHP source package for the Ubuntu release this
# container runs, without Sury's DNS telemetry.
#
# Runs inside a clean ubuntu:<release> container with:
#   /repo     this repository (read-only)
#   /sources  the pinned Sury source files (read-only)
#   /out      where the .deb files are written
# Env: PHP=8.2 (required), REVISION=1, JOBS=4
#
# Adapted from https://github.com/Niek/php7 (MIT).
#
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
# shellcheck disable=SC1091
. /etc/os-release
: "${PHP:?set PHP, e.g. PHP=8.2}"
REVISION=${REVISION:-1}
JOBS=${JOBS:-4}
target="ubuntu${VERSION_ID}"

# Never start services inside the build container
printf '#!/bin/sh\nexit 101\n' > /usr/sbin/policy-rc.d
chmod +x /usr/sbin/policy-rc.d
# Ubuntu mirrors drop connections under load; retry instead of failing the build
echo 'Acquire::Retries "5";' > /etc/apt/apt.conf.d/80retries
apt-get update
apt-get install -y --no-install-recommends build-essential devscripts equivs dpkg-dev ca-certificates

mkdir -p /build /out
cd /sources
sha256sum -c "/repo/sources/php${PHP}.sha256"
dpkg-source --no-check -x ./php"${PHP}"_*.dsc /build/php
cd /build/php

# ── Strip Sury's DNS telemetry ─────────────────────────────────────────
# Sury's patch makes FPM and mod_php send package/version to
# telemetry.sury.org:53 on start, switched on by TELEMETRY_HOST from
# /usr/lib/php/php-common.mk. Never pull that file in, and compile the
# header out entirely (its newer libsodium calls also break on 20.04).
sed -i '/^-include \/usr\/lib\/php\/php-common.mk/d' debian/rules
sed -i 's/^#include "secure_dns_telemetry.h"/#ifdef TELEMETRY_HOST\n#include "secure_dns_telemetry.h"\n#endif/' \
    sapi/apache2handler/php_functions.c sapi/fpm/fpm/fpm_main.c

# ── Version: Sury's revision + ours, sorting above Ondrej's frozen focal builds
base=$(dpkg-parsechangelog -SVersion | sed 's/+0~.*//')
export DEBFULLNAME='php-focal-backports' DEBEMAIL='noreply@github.com'
dch --newversion "${base}+pfb${REVISION}~${target}.1" --distribution "$VERSION_CODENAME" --force-distribution \
    "Rebuild Sury's security backports for ${PRETTY_NAME}, without DNS telemetry."

export DEB_BUILD_OPTIONS="nocheck noddebs parallel=${JOBS}"
export DEB_BUILD_PROFILES=nocheck
mk-build-deps --install --remove --tool 'apt-get -y --no-install-recommends' debian/control
dpkg-buildpackage -us -uc -b -j"${JOBS}"

# ── Refuse to ship anything that still knows the telemetry host ────────
mkdir -p /tmp/check
for deb in /build/*.deb; do
    dpkg-deb -x "$deb" /tmp/check
done
if grep -rlaF 'telemetry.sury.org' /tmp/check; then
    echo "ERROR: telemetry.sury.org found in the files above" >&2
    exit 1
fi

cp /build/*.deb /out/
dpkg-query -W -f='${binary:Package}\t${Version}\n' > "/out/build-dependencies-php${PHP}.txt"
cd /out
sha256sum ./*.deb > "SHA256SUMS-php${PHP}"
