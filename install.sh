#!/bin/bash
#
# One-command setup for php-focal-backports on an Ubuntu 20.04 server:
# adds the signed repository, upgrades the PHP 7.2–8.2 packages already
# installed, restarts PHP, and checks the result.
#
#   curl -fsSL https://raw.githubusercontent.com/wmfairuz/php-focal-backports/main/install.sh | sudo bash
#
# Add `-s -- --yes` after `bash` to skip the confirmation prompt.
# Safe to run again: it only does what is still needed.
#
set -euo pipefail

REPO_URL="https://wmfairuz.github.io/php-focal-backports"
FINGERPRINT="EAD90151D4B3AF78A6E7FB1B408D844AED9B9D0A"
KEYRING="/usr/share/keyrings/php-focal-backports.gpg"
LIST="/etc/apt/sources.list.d/php-focal-backports.list"
PHP_RE='^(php(7\.[2-4]|8\.[0-2])($|-)|libapache2-mod-php(7\.[2-4]|8\.[0-2])$|libphp(7\.[2-4]|8\.[0-2])-)'

ASSUME_YES=no
case "${1:-}" in -y|--yes) ASSUME_YES=yes ;; esac

if [ -t 1 ]; then
    G='\033[0;32m'; R='\033[0;31m'; Y='\033[1;33m'; B='\033[1m'; N='\033[0m'
else
    G=''; R=''; Y=''; B=''; N=''
fi
step() { echo -e "\n${B}==> $*${N}"; }
ok()   { echo -e "  ${G}✓${N} $*"; }
warn() { echo -e "  ${Y}!${N} $*"; }
die()  { echo -e "  ${R}✗ $*${N}" >&2; exit 1; }

# ── 1. Is this server a fit? ──────────────────────────────────────────
step "Checking this server"
[ "$(id -u)" -eq 0 ] || die "Run as root: curl … | sudo bash"
# shellcheck disable=SC1091
. /etc/os-release
[ "${VERSION_CODENAME:-}" = "focal" ] || die "This is ${PRETTY_NAME:-unknown}, not Ubuntu 20.04. On 22.04/24.04 use ppa:ondrej/php instead."
[ "$(dpkg --print-architecture)" = "amd64" ] || die "Only amd64 is supported (this is $(dpkg --print-architecture))."
ok "$PRETTY_NAME, amd64"

# ── 2. Add the signed repository ──────────────────────────────────────
step "Adding the repository"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
# Nothing here may wait forever: bounded downloads, apt lock waits and gpg
APT_LOCK=(-o DPkg::Lock::Timeout=120)
if ! command -v gpg >/dev/null 2>&1; then
    echo "  Installing gnupg (needed to verify the key)…"
    timeout 600 apt-get update -qq 2>/dev/null || true   # other broken sources must not block this
    timeout 600 apt-get install -y -qq "${APT_LOCK[@]}" gnupg >/dev/null \
        || die "Could not install gnupg. Is another apt/dpkg running? Check: ps aux | grep -E '[a]pt|[d]pkg'"
fi
echo "  Downloading signing key…"
curl -fsSL --connect-timeout 15 --max-time 60 --retry 2 "$REPO_URL/key.gpg" -o "$tmp/key.gpg" \
    || die "Could not download $REPO_URL/key.gpg — check outbound HTTPS: curl -v $REPO_URL/key.gpg"
echo "  Verifying it…"
# Throwaway keyring: never touches root's ~/.gnupg (a stale lock there makes gpg wait forever)
mkdir -m 700 "$tmp/gnupg"
got=$(GNUPGHOME="$tmp/gnupg" timeout 30 gpg --batch --show-keys --with-colons "$tmp/key.gpg" 2>/dev/null \
      | awk -F: '/^fpr/ && !f {print $10; f=1}') || true
[ -n "$got" ] || die "gpg could not read the downloaded key (timed out or not a key). Try: gpg --show-keys $tmp/key.gpg"
[ "$got" = "$FINGERPRINT" ] || die "Signing key fingerprint is '$got', expected $FINGERPRINT. Not adding it."
install -m 0644 "$tmp/key.gpg" "$KEYRING"
echo "deb [signed-by=$KEYRING] $REPO_URL focal main" > "$LIST"
ok "Key verified ($FINGERPRINT)"
ok "Repository added: $LIST"

echo "  Running apt update (can take a minute)…"
if ! timeout 600 apt-get update -qq 2>"$tmp/update.err"; then
    warn "apt update reported errors from other sources (not this repository) — fix them separately:"
    sed -n '1,5s/^/      /p' "$tmp/update.err"
fi
apt-cache policy > "$tmp/policy" 2>/dev/null || true
grep -qF "$REPO_URL" "$tmp/policy" || die "apt cannot read $REPO_URL — check the errors above."
ok "apt can read the repository"
if ppa=$(grep -rlsE 'ppa\.launchpad(content)?\.net/ondrej/php' /etc/apt/sources.list /etc/apt/sources.list.d/); then
    warn "Ondrej's PPA is still configured ($ppa). It has no 20.04 packages left, and its"
    warn "stale index can make apt try downloads that 404. Consider removing it:"
    echo "      sudo add-apt-repository --remove ppa:ondrej/php"
fi

# ── 3. Which PHP is installed, and what would change? ─────────────────
step "Looking at installed PHP"
mapfile -t pkgs < <(dpkg-query -W -f='${db:Status-Abbrev} ${Package}\n' 2>/dev/null \
                     | awk '$1=="ii"{print $2}' | grep -E "$PHP_RE" || true)
if [ ${#pkgs[@]} -eq 0 ]; then
    ok "No PHP 7.2–8.2 installed. The repository is ready; install what you need, e.g.:"
    echo "      sudo apt install php8.2-fpm php8.2-mysql"
    exit 0
fi
echo "  Installed: $(printf '%s\n' "${pkgs[@]}" | sed -E 's/^(php|libapache2-mod-php|libphp)([0-9.]+).*/\2/' | sort -uV | sed 's/^/PHP /' | paste -sd, - | sed 's/,/, /g')"

# Only touch packages this repository provides. Others (php8.0-imagick,
# php7.4-redis, …) stay as installed — and their stale Ondrej candidates,
# whose files are gone, must never be requested.
ours=(); others=()
for p in "${pkgs[@]}"; do
    if grep -qF "$REPO_URL" <<<"$(apt-cache madison "$p" 2>/dev/null)"; then ours+=("$p"); else others+=("$p"); fi
done
if [ ${#others[@]} -gt 0 ]; then
    echo "  Left as they are (not in this repository, they keep working):"
    echo "${others[*]}" | fold -s -w 72 | sed 's/^/      /'
fi

plan=""
[ ${#ours[@]} -gt 0 ] && plan=$(apt-get install -s --only-upgrade "${ours[@]}" 2>&1 || true)
removals=$(echo "$plan" | awk '/^Remv /{print $2}')
upgrades=$(echo "$plan" | awk '/^Inst /{print $2}')
from_ppa=$(echo "$plan" | awk '/^Inst / && /LP-PPA-ondrej/ {print $2}')
if [ -n "$removals" ]; then
    warn "apt would REMOVE these packages, so nothing was changed:"
    echo "$removals" | sed 's/^/      /'
    die "Upgrade them by hand or open an issue: https://github.com/wmfairuz/php-focal-backports/issues"
fi
if [ -n "$from_ppa" ]; then
    warn "apt also wants these from Ondrej's PPA, whose 20.04 files no longer exist:"
    echo "$from_ppa" | sed 's/^/      /'
    die "Remove the PPA (sudo add-apt-repository --remove ppa:ondrej/php), run apt update, then re-run this script."
fi
if [ -z "$upgrades" ]; then
    ok "PHP is already up to date from this repository."
else
    echo "  Will upgrade $(echo "$upgrades" | wc -l) packages (config files you have edited are kept):"
    echo "$upgrades" | paste -sd' ' - | fold -s -w 72 | sed 's/^/      /'

    if [ "$ASSUME_YES" != yes ]; then
        if ! { exec 3</dev/tty; } 2>/dev/null; then
            die "No terminal to ask on. Re-run with: … | sudo bash -s -- --yes"
        fi
        read -r -u 3 -p "  Take a snapshot first if you can. Continue? [y/N] " ans
        exec 3<&-
        [[ "$ans" =~ ^[Yy]$ ]] || { echo "  Nothing changed."; exit 0; }
    fi

    # ── 4. Upgrade, keeping existing config files ────────────────────
    step "Upgrading PHP"
    # confold: keep edited conffiles; UCF_FORCE_CONFFOLD: same for php.ini (managed by ucf)
    DEBIAN_FRONTEND=noninteractive UCF_FORCE_CONFFOLD=1 apt-get install -y -q --only-upgrade "${APT_LOCK[@]}" \
        -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold "${ours[@]}"
    ok "Packages upgraded"
fi

# ── 5. Restart what serves PHP ────────────────────────────────────────
step "Restarting PHP"
restarted=0
for unit in $(systemctl list-units --type=service --state=running --plain --no-legend 'php*-fpm*' 2>/dev/null | awk '{print $1}'); do
    systemctl restart "$unit" && ok "restarted $unit" || warn "failed to restart $unit — check: journalctl -u $unit -n 50"
    restarted=1
done
if ls /etc/apache2/mods-enabled/php*.load >/dev/null 2>&1 && systemctl is-active --quiet apache2; then
    systemctl restart apache2 && ok "restarted apache2" || warn "failed to restart apache2"
    restarted=1
fi
[ "$restarted" -eq 1 ] || warn "No running PHP-FPM or Apache mod_php found — nothing to restart."

# ── 6. Check the result ───────────────────────────────────────────────
step "Result"
fail=0
for common in $(printf '%s\n' "${pkgs[@]}" | grep -E '^php(7\.[2-4]|8\.[0-2])-common$'); do
    ver=$(dpkg-query -W -f='${Version}' "$common")
    mm=${common#php}; mm=${mm%-common}
    if zgrep -qE 'CVE-2026-10961[89]' "/usr/share/doc/$common/changelog.Debian.gz" 2>/dev/null; then
        ok "PHP $mm  $ver  — patched"
    elif ! grep -qF "$REPO_URL" <<<"$(apt-cache madison "$common" 2>/dev/null)"; then
        warn "PHP $mm  $ver  — not in this repository yet; re-run this script once it is"
    else
        echo -e "  ${R}✗${N} PHP $mm  $ver  — NOT patched"
        fail=1
    fi
done
for unit in $(systemctl list-units --type=service --all --plain --no-legend 'php*-fpm*' 2>/dev/null | awk '{print $1}'); do
    systemctl is-enabled --quiet "$unit" 2>/dev/null || continue
    if systemctl is-active --quiet "$unit"; then ok "$unit is running"; else echo -e "  ${R}✗${N} $unit is NOT running"; fail=1; fi
done

echo
if [ "$fail" -eq 0 ]; then
    echo -e "${G}${B}Done.${N} Future fixes arrive with: sudo apt update && sudo apt upgrade"
else
    echo -e "${R}${B}Some checks failed — see above.${N} Help: https://github.com/wmfairuz/php-focal-backports#troubleshooting"
    exit 1
fi
