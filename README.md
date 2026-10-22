# PHP security backports for Ubuntu 20.04

Patched PHP **7.4, 8.0, 8.1 and 8.2** packages for **Ubuntu 20.04 (focal)**,
served as a signed APT repository. Ondřej Surý's PPA stopped publishing for
20.04 in June 2025, so servers that used it are stuck on old, vulnerable builds.

These packages are Sury's own patched sources, rebuilt unchanged for 20.04
except for one thing: **Sury's DNS telemetry is removed** (see below).

| PHP | Version | Fixes |
| --- | ------- | ----- |
| 7.4 | `1:7.4.33-31+pfb1~ubuntu20.04.1` | CVE-2026-109618, CVE-2026-109619 (backport) |
| 8.0 | `1:8.0.30-25+pfb1~ubuntu20.04.1` | CVE-2026-109618, CVE-2026-109619 (backport) |
| 8.1 | `8.1.34-9+pfb1~ubuntu20.04.1`    | CVE-2026-109618, CVE-2026-109619 (backport) |
| 8.2 | `8.2.35-1+pfb1~ubuntu20.04.1`    | CVE-2026-109618, CVE-2026-109619 (upstream) |

> [!WARNING]
> Ubuntu 20.04 and PHP 7.4–8.1 are end-of-life. Use this to buy time for an
> upgrade to Ubuntu 24.04 and a supported PHP, not as long-term support.

## Use on a server

Add the repository once:

```bash
curl -fsSL https://wmfairuz.github.io/php-focal-backports/key.gpg \
  | sudo tee /usr/share/keyrings/php-focal-backports.gpg >/dev/null
echo "deb [signed-by=/usr/share/keyrings/php-focal-backports.gpg] https://wmfairuz.github.io/php-focal-backports focal main" \
  | sudo tee /etc/apt/sources.list.d/php-focal-backports.list
sudo apt update
```

The repository is signed with key
`EAD9 0151 D4B3 AF78 A6E7 FB1B 408D 844A ED9B 9D0A` (also in [`key.asc`](key.asc)).
To check the key you downloaded:
`gpg --show-keys /usr/share/keyrings/php-focal-backports.gpg`.

Then upgrade the PHP versions you already have, and restart PHP:

```bash
sudo apt install --only-upgrade 'php7.4*' 'php8.0*' 'php8.1*' 'php8.2*' 'libapache2-mod-php*'
sudo systemctl restart 'php*-fpm'
```

Future fixes arrive through the normal `sudo apt update && sudo apt upgrade`.
The versions sort above the frozen Ondrej focal builds, so nothing else is needed.

Not included: extensions Sury packages separately (`php-redis`, `php-imagick`,
`php-xdebug`, …). Your existing builds of those keep working; they are not
affected by these CVEs.

## How it's built

GitHub Actions downloads Sury's source packages from packages.sury.org, checks
them against the hashes pinned in [`sources/`](sources/), and builds them in a
clean `ubuntu:20.04` container with [`build.sh`](build.sh). Tagged builds are
published to GitHub Pages as a GPG-signed APT repository
([`scripts/make-apt-repo.sh`](scripts/make-apt-repo.sh)). Build logs and
checksums are attached to each GitHub release. The PHP test suite is not run.

### Telemetry removed

Since February 2026 Sury's PHP-FPM and Apache module send the package name,
version and a timestamp to `telemetry.sury.org` (UDP 53) every time they start.
`build.sh` keeps that code out of the build, and the build fails if any
package still contains the telemetry host name.

### Releasing a new fix

1. Update `sources/php<ver>.sha256` with the new Sury source file hashes
   (or bump `REVISION` in the workflow to rebuild the same sources).
2. Push to `main` and wait for the build to pass.
3. Tag and push: `git tag v2026.10.22 && git push origin v2026.10.22`.

## Credits

Build approach adapted from [Niek/php7](https://github.com/Niek/php7) (MIT).
PHP packaging and security backports by Ondřej Surý
([deb.sury.org](https://deb.sury.org)); consider
[supporting his work](https://deb.sury.org/#donate) or
[Freexian's PHP LTS](https://www.freexian.com/lts/php/).
