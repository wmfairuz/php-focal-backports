#!/bin/bash
#
# Re-pin sources/php<ver>.sha256 to the source packages Sury currently
# publishes on packages.sury.org (Debian bookworm), for every version this
# repository builds. Review `git diff sources/` before committing.
#
#   scripts/update-sources.sh
#
set -euo pipefail
cd "$(dirname "$0")/.."

index=$(curl -fsSL https://packages.sury.org/php/dists/bookworm/main/source/Sources.gz | gunzip)

for file in sources/php*.sha256; do
    pkg=$(basename "$file" .sha256)
    pins=$(echo "$index" | awk -v want="$pkg" '
        /^Package: /           { pkg = $2; inf = 0 }
        /^Checksums-Sha256:/   { inf = 1; next }
        inf && /^ /            { if (pkg == want) print $1 "  " $3; next }
        inf && !/^ /           { inf = 0 }')
    if [ -z "$pins" ]; then
        echo "WARNING: $pkg not found in Sury's index — left unchanged" >&2
        continue
    fi
    echo "$pins" > "$file"
    echo "$pkg: $(echo "$pins" | awk '/\.dsc$/ {print $2}')"
done
