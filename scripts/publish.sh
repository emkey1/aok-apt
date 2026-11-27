#!/bin/sh
# publish.sh SITE DEBDIR
# ---------------------------------------------------------------------------
# Add DEBDIR's .debs to the apt repository checked out at SITE (the gh-pages
# branch), rebuild its indexes, and sign them.
#
# The signing key comes from the APT_SIGNING_KEY environment variable (the
# repository secret of that name: an ASCII-armoured private key with no
# passphrase). It is imported into a throwaway keyring and never written
# anywhere else.
#
# Layout, served by GitHub Pages:
#   pool/main/<first letter>/<source>/<name>_<version>_<arch>.deb
#   dists/excalibur/main/binary-<arch>/Packages(.gz)
#   dists/excalibur/{Release,InRelease,Release.gpg}
#   aok-apt.asc                       the public key
# ---------------------------------------------------------------------------
set -eu

SITE=${1:?usage: publish.sh SITE DEBDIR}
DEBS=${2:?usage: publish.sh SITE DEBDIR}
SUITE=excalibur
COMPONENT=main
ARCHES="arm64 amd64"

die() { printf 'publish.sh: %s\n' "$*" >&2; exit 1; }

[ -n "${APT_SIGNING_KEY:-}" ] || die "APT_SIGNING_KEY is not set"
command -v apt-ftparchive >/dev/null || die "apt-ftparchive is missing (apt-utils)"

GNUPGHOME=$(mktemp -d)
export GNUPGHOME
trap 'rm -rf "$GNUPGHOME"' EXIT
printf '%s\n' "$APT_SIGNING_KEY" | gpg --batch --quiet --import
FPR=$(gpg --batch --with-colons --list-secret-keys | awk -F: '$1 == "fpr" { print $10; exit }')
[ -n "$FPR" ] || die "APT_SIGNING_KEY holds no secret key"

# A .deb already published under a name is never replaced by different bytes:
# apt clients that cached the old index would reject it as a hash mismatch.
# Rebuilding the same PSCAL commit means bumping the Debian revision.
added=0
for deb in "$DEBS"/*.deb; do
    [ -f "$deb" ] || continue
    name=$(dpkg-deb --field "$deb" Package)
    dir="$SITE/pool/$COMPONENT/$(printf '%s' "$name" | cut -c1)/$name"
    dest="$dir/${deb##*/}"
    mkdir -p "$dir"
    if [ -e "$dest" ]; then
        cmp -s "$deb" "$dest" || die "${deb##*/} is already published with other contents; bump the revision"
        printf 'already published: %s\n' "${deb##*/}"
        continue
    fi
    cp "$deb" "$dest"
    printf 'added: %s\n' "${dest#"$SITE"/}"
    added=$((added + 1))
done

cd "$SITE"
for arch in $ARCHES; do
    dir=dists/$SUITE/$COMPONENT/binary-$arch
    mkdir -p "$dir"
    apt-ftparchive --arch "$arch" packages "pool/$COMPONENT" > "$dir/Packages"
    gzip -9nkf "$dir/Packages"
    printf '%s: %s package(s)\n' "$arch" "$(grep -c '^Package:' "$dir/Packages" || true)"
done

release=$(mktemp)
apt-ftparchive \
    -o APT::FTPArchive::Release::Origin="AOK-Workstation" \
    -o APT::FTPArchive::Release::Label="AOK-Workstation" \
    -o APT::FTPArchive::Release::Suite="$SUITE" \
    -o APT::FTPArchive::Release::Codename="$SUITE" \
    -o APT::FTPArchive::Release::Architectures="$ARCHES" \
    -o APT::FTPArchive::Release::Components="$COMPONENT" \
    -o APT::FTPArchive::Release::Description="AOK-Workstation packages for Devuan 6 (excalibur)" \
    release "dists/$SUITE" > "$release"
mv "$release" "dists/$SUITE/Release"
chmod 644 "dists/$SUITE/Release"

gpg --batch --yes --local-user "$FPR" --digest-algo SHA512 \
    --clearsign --output "dists/$SUITE/InRelease" "dists/$SUITE/Release"
gpg --batch --yes --local-user "$FPR" --digest-algo SHA512 \
    --armor --detach-sign --output "dists/$SUITE/Release.gpg" "dists/$SUITE/Release"
gpg --batch --verify "dists/$SUITE/InRelease" 2>&1 | grep -q 'Good signature' ||
    die "the new InRelease does not verify"
gpg --batch --armor --export "$FPR" > aok-apt.asc

printf 'signed with %s; %d new package file(s)\n' "$FPR" "$added"
