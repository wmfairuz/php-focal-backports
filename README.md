# PHP security backports for Ubuntu 20.04

Patched **PHP 7.2, 7.3, 7.4, 8.0, 8.1 and 8.2** packages for **Ubuntu 20.04 LTS (focal)**,
published as a signed APT repository.

If your 20.04 servers got PHP from Ondřej Surý's PPA (`ppa:ondrej/php`), they
have not received a PHP update since June 2025: the PPA stopped publishing for
20.04 when Ubuntu ended its standard support. This repository rebuilds Sury's
current, patched PHP packages for 20.04 so those servers can be fixed with a
normal `apt upgrade`.

> [!IMPORTANT]
> This is an unofficial, community rebuild. It is not affiliated with or
> endorsed by the PHP project, Ondřej Surý, or Canonical.
> Ubuntu 20.04 and PHP 7.2–8.1 are end-of-life: use this to stay patched while
> you move to Ubuntu 24.04 and a supported PHP, not as long-term support.

## Contents

- [What's fixed](#whats-fixed)
- [Is this for me?](#is-this-for-me)
- [Quick start](#quick-start) (one command)
- [Check that it worked](#check-that-it-worked)
- [What's in the repository](#whats-in-the-repository)
- [Can I trust these packages?](#can-i-trust-these-packages)
- [Removing the repository](#removing-the-repository)
- [Troubleshooting](#troubleshooting)
- [For maintainers](#for-maintainers)
- [Credits and license](#credits-and-license)

## What's fixed

| PHP | Package version in this repo        | What `php -v` shows | CVE-2026-109618 / CVE-2026-109619 |
| --- | ----------------------------------- | ------------------- | --------------------------------- |
| 7.2 | `7.2.34-66+pfb1~ubuntu20.04.1`      | 7.2.34              | fixed (backport)                  |
| 7.3 | `7.3.33-35+pfb1~ubuntu20.04.1`      | 7.3.33              | fixed (backport)                  |
| 7.4 | `1:7.4.33-31+pfb1~ubuntu20.04.1`    | 7.4.33              | fixed (backport)                  |
| 8.0 | `1:8.0.30-25+pfb1~ubuntu20.04.1`    | 8.0.30              | fixed (backport)                  |
| 8.1 | `8.1.34-9+pfb1~ubuntu20.04.1`       | 8.1.34              | fixed (backport)                  |
| 8.2 | `8.2.35-1+pfb1~ubuntu20.04.1`       | 8.2.35              | fixed (upstream release)          |

CVE-2026-109618 and CVE-2026-109619 are the critical (CVSS 9.2) remote code
execution bugs fixed in PHP 8.2.35 / 8.3.36 / 8.4.27 / 8.5.12 on 2026-10-21.
PHP no longer maintains 7.2–8.1; Sury backported the fix to those branches,
which is why their version number does not change. Each package also carries
every earlier security fix in Sury's packaging.

## Is this for me?

**Yes, if** your server runs Ubuntu 20.04 on amd64 (x86-64) and PHP 7.2, 7.3,
7.4, 8.0, 8.1 or 8.2 from Ondřej's PPA, Ubuntu's own `php7.4`, or nothing yet.

**No, if** your server is:

- **Ubuntu 22.04 or 24.04**: use Ondřej's PPA (`ppa:ondrej/php`) directly. It
  already has the fix.
- **arm64 / ARM**: only amd64 packages are built.
- **PHP 8.3 or newer, or 7.1 and older, on 20.04**: not built here.
- **cPanel, Plesk, or a Docker image**: update PHP through those instead.

Find your release and architecture with:

```bash
lsb_release -cs        # must print: focal
dpkg --print-architecture   # must print: amd64
```

## Quick start

Take a snapshot or backup of the server first: Ondřej's old 20.04 packages are
no longer downloadable, so you cannot `apt` your way back to them.

Then run **one command**:

```bash
curl -fsSL https://raw.githubusercontent.com/wmfairuz/php-focal-backports/main/install.sh | sudo bash
```

It checks the server is Ubuntu 20.04 amd64, adds the repository after
verifying its signing key, shows which PHP packages it will upgrade and asks
before changing anything, upgrades only the PHP 7.2–8.2 you already have
(keeping your `php.ini` and pool files), restarts PHP-FPM / Apache, and
confirms each PHP version is patched. It stops without changing anything if
apt would remove a package. Running it again is safe.

To run it unattended (for example from Ansible), skip the prompt:

```bash
curl -fsSL https://raw.githubusercontent.com/wmfairuz/php-focal-backports/main/install.sh | sudo bash -s -- --yes
```

Read [`install.sh`](install.sh) before piping it to `sudo bash` if your policy
requires it. From then on, future fixes arrive with your normal
`sudo apt update && sudo apt upgrade`.

### Manual setup

The same steps by hand.

**1. Add the repository** (once per server):

```bash
curl -fsSL https://wmfairuz.github.io/php-focal-backports/key.gpg \
  | sudo tee /usr/share/keyrings/php-focal-backports.gpg >/dev/null

echo "deb [signed-by=/usr/share/keyrings/php-focal-backports.gpg] https://wmfairuz.github.io/php-focal-backports focal main" \
  | sudo tee /etc/apt/sources.list.d/php-focal-backports.list

sudo apt update
```

**2. See what will change** before changing anything:

```bash
apt list --upgradable 2>/dev/null | grep pfb
```

**3. Upgrade only the PHP packages you already have** (nothing new is
installed, and other system packages are left alone):

```bash
sudo apt install --only-upgrade 'php7.2*' 'php7.3*' 'php7.4*' 'php8.0*' 'php8.1*' 'php8.2*' 'libapache2-mod-php*' 'libphp*'
```

If apt asks whether to keep or replace a modified config file (`php.ini`, a
pool file), answer **N** to keep yours.

**4. Restart PHP** so the running processes load the new code:

```bash
sudo systemctl restart 'php*-fpm'
sudo systemctl restart apache2   # only if you use Apache with mod_php
```

From now on, future fixes arrive with your normal `sudo apt update && sudo apt upgrade`.

## Check that it worked

Every PHP package should now come from this repository (`pfb` in the version):

```bash
dpkg -l 'php*-common' | grep ^ii
```

```
ii  php8.1-common  8.1.34-9+pfb1~ubuntu20.04.1  amd64  documentation, examples and common module for PHP
ii  php8.2-common  8.2.35-1+pfb1~ubuntu20.04.1  amd64  documentation, examples and common module for PHP
```

Also confirm each PHP-FPM service came back up:

```bash
systemctl status 'php*-fpm' --no-pager | grep -E '●|Active:'
```

For a full report, the
[`check-php-up-2026.sh`](https://github.com/wmfairuz/server-helper/blob/main/check-php-up-2026.sh)
script (read-only by default) lists every PHP on the server and should print
**PATCHED** for each one.

## What's in the repository

The same set of packages Sury publishes for each PHP version, so `apt` sees
them as newer versions of what you already have:

`cli`, `fpm`, `cgi`, `common`, `dev`, `embed`, `phpdbg`, `litespeed`,
`libapache2-mod-php`, and the extensions `bcmath`, `bz2`, `curl`, `dba`,
`enchant`, `gd`, `gmp`, `imap`, `interbase`, `intl`, `json` (7.4), `ldap`,
`mbstring`, `mysql`, `odbc`, `opcache`, `pgsql`, `pspell`, `readline`, `snmp`,
`soap`, `sqlite3`, `sybase`, `tidy`, `xml`, `xmlrpc` (7.4), `xsl`, `zip`.

**Not included:** extensions Sury ships as separate source packages, such as
`php-redis`, `php-imagick`, `php-memcached`, `php-xdebug`, `php-mongodb`, or
anything from PECL. The copies you already have keep working with these
packages, and they are not affected by these CVEs.

### One change from Sury's packages: telemetry is removed

Since February 2026, Sury's PHP-FPM and Apache module send the package name,
version and a timestamp (encrypted) to `telemetry.sury.org` over UDP port 53
every time they start, to check for updates. These builds leave that code out,
and the build fails if any package still contains the telemetry host name.
Nothing else in the source or packaging is changed.

### Ubuntu's own php7.4 and Ubuntu Pro

These packages have a higher version than Ubuntu's own `php7.4`
(`7.4.3-4ubuntu2.x`, including the Ubuntu Pro/ESM builds), so adding this
repository also upgrades a server that uses Ubuntu's `php7.4`. If you have
Ubuntu Pro and want to keep Canonical's `php7.4`, pin it before upgrading:

```bash
printf 'Package: php7.4* libapache2-mod-php7.4 libphp7.4*\nPin: origin wmfairuz.github.io\nPin-Priority: -1\n' \
  | sudo tee /etc/apt/preferences.d/php-focal-backports-no-7.4
```

## Can I trust these packages?

You are trusting this repository's build, so everything that goes into it is
public and checkable:

- **Source**: Sury's own source packages, downloaded from
  `packages.sury.org` and checked against the SHA-256 hashes pinned in
  [`sources/`](sources/). The build stops if any hash differs.
- **Build**: GitHub Actions runs [`build.sh`](build.sh) in a clean
  `ubuntu:20.04` container, against 20.04's own libraries. The workflow is
  [`.github/workflows/build.yml`](.github/workflows/build.yml); full build logs
  and checksums are attached to every
  [release](https://github.com/wmfairuz/php-focal-backports/releases).
- **Signing**: the APT repository is signed by a dedicated key that exists only
  as a GitHub Actions secret. Check that the key you installed is this one:

  ```bash
  gpg --show-keys /usr/share/keyrings/php-focal-backports.gpg
  ```

  The fingerprint must be `EAD9 0151 D4B3 AF78 A6E7  FB1B 408D 844A ED9B 9D0A`
  (also in [`key.asc`](key.asc)). The key expires on 2029-10-21.

- **Not done**: PHP's own test suite is not run, and the builds are not
  bit-for-bit reproducible.

## Removing the repository

```bash
sudo rm /etc/apt/sources.list.d/php-focal-backports.list \
        /usr/share/keyrings/php-focal-backports.gpg
sudo apt update
```

The installed packages stay as they are; they just stop receiving updates from
here. After moving a server to Ubuntu 22.04 or 24.04, remove this repository
and use Ondřej's PPA again.

## Troubleshooting

**`apt update` says the repository is not signed / `NO_PUBKEY`**:
the key file is missing or empty. Repeat step 1 and check its fingerprint
(see above).

**`404 Not Found` for `.../dists/focal/...`**: the server is not on 20.04, or
the `.list` line has a typo. Only `focal` exists.

**`apt list --upgradable` shows nothing with `pfb`**: either PHP is already up
to date, or it is not installed from a source these packages replace. Check
what you have with `dpkg -l 'php*' | grep ^ii`.

**apt wants to remove packages**: stop and read the list. This usually means
an extension from a separate source package (for example `php8.1-redis`) pins
an exact older `php8.1-common`. Upgrade that extension in the same command, or
open an issue with the full apt output.

**PHP-FPM fails to start after the upgrade**: run `sudo php-fpm8.2 -t`
(replace the version) to see the config error, and check
`journalctl -u php8.2-fpm -n 50`.

Anything else: [open an issue](https://github.com/wmfairuz/php-focal-backports/issues)
with your `lsb_release -a`, `dpkg -l 'php*' | grep ^ii`, and the full error.

## For maintainers

### Ship a new security fix

When Sury publishes a fixed revision of PHP 7.2–8.2:

```bash
scripts/update-sources.sh           # re-pin sources/ to Sury's current packages
git diff sources/                   # review: only the versions you expect
git commit -am "Update to Sury's <versions>" && git push
```

Wait for the build on `main` to pass, then publish:

```bash
git tag -a v$(date +%Y.%m.%d) -m "<what changed>"
git push origin v$(date +%Y.%m.%d)
```

The tag rebuilds everything, signs the repository, deploys it to GitHub Pages,
and creates a release with logs and checksums. Update the table in
[What's fixed](#whats-fixed) when versions change.

To rebuild the **same** sources (for example after a `build.sh` fix), bump
`REVISION` in `.github/workflows/build.yml` instead, so the `+pfbN` suffix goes
up and servers see an upgrade.

### Build locally

```bash
mkdir -p sources-dl out
(cd sources-dl && while read -r _ f; do
   curl -fsSLO "https://packages.sury.org/php/pool/main/p/php8.2/${f//+/%2B}"
 done < ../sources/php8.2.sha256)
docker run --rm --platform linux/amd64 -v "$PWD:/repo:ro" -v "$PWD/sources-dl:/sources:ro" \
  -v "$PWD/out:/out" -e PHP=8.2 ubuntu:20.04 bash /repo/build.sh
```

### Signing key

The private key is the `APT_SIGNING_KEY` Actions secret and is not stored
anywhere else. If it is lost or must be rotated, generate a new ed25519 signing
key, replace the secret and `key.asc`, update the fingerprint in this README,
and tell users to repeat step 1 of the quick start.

## Credits and license

- PHP packaging and security backports: Ondřej Surý ([deb.sury.org](https://deb.sury.org)).
  If this helps your business, consider
  [supporting his work](https://deb.sury.org/#donate) or
  [Freexian's PHP LTS](https://www.freexian.com/lts/php/), which offers
  commercially supported packages for 20.04.
- Build approach adapted from [Niek/php7](https://github.com/Niek/php7).
- This repository's scripts and documentation: [MIT](LICENSE). PHP and Sury's
  packaging keep their own licenses, included in each package.
