#!/bin/bash
#
# Turn a directory of .deb files into a signed APT repository.
#
#   scripts/make-apt-repo.sh <debs-dir> <site-dir> <codename>
#
# Needs apt-utils (apt-ftparchive) and gpg with the signing key imported;
# SIGNING_KEY_ID selects the key. Layout:
#   <site>/pool/main/*.deb
#   <site>/dists/<codename>/{InRelease,Release,Release.gpg}
#   <site>/dists/<codename>/main/binary-amd64/Packages{,.gz}
#   <site>/key.gpg (binary) and key.asc (armored) public key
#
set -euo pipefail
debs=$1 site=$2 codename=$3
: "${SIGNING_KEY_ID:?set SIGNING_KEY_ID}"

mkdir -p "$site/pool/main" "$site/dists/$codename/main/binary-amd64"
find "$debs" -name '*.deb' -exec cp {} "$site/pool/main/" \;

cd "$site"
apt-ftparchive packages pool > "dists/$codename/main/binary-amd64/Packages"
gzip -9kf "dists/$codename/main/binary-amd64/Packages"

apt-ftparchive \
    -o APT::FTPArchive::Release::Origin="php-focal-backports" \
    -o APT::FTPArchive::Release::Label="php-focal-backports" \
    -o APT::FTPArchive::Release::Suite="$codename" \
    -o APT::FTPArchive::Release::Codename="$codename" \
    -o APT::FTPArchive::Release::Architectures="amd64" \
    -o APT::FTPArchive::Release::Components="main" \
    -o APT::FTPArchive::Release::Description="Sury's PHP security backports rebuilt for Ubuntu $codename, without telemetry" \
    release "dists/$codename" > "dists/$codename/Release"

gpg --batch --yes -u "$SIGNING_KEY_ID" --clearsign -o "dists/$codename/InRelease" "dists/$codename/Release"
gpg --batch --yes -u "$SIGNING_KEY_ID" -abs -o "dists/$codename/Release.gpg" "dists/$codename/Release"
gpg --batch --yes --export "$SIGNING_KEY_ID" > key.gpg
gpg --batch --yes --armor --export "$SIGNING_KEY_ID" > key.asc
