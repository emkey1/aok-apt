#!/bin/sh
# build-deb.sh REF OUTDIR
# ---------------------------------------------------------------------------
# Build PSCAL at REF (a tag, branch or commit of github.com/emkey1/pscal) and
# package it as OUTDIR/pscal_<version>_<arch>.deb.
#
# Runs as root in a Debian trixie container, the release Devuan 6
# ("excalibur") is built from, so the package depends on the libraries a
# Devuan 6 filesystem has. The architecture is the container's.
#
# Version: tag V.<major>R<release> becomes <major>.<release>; a commit N past
# the tag becomes <major>.<release>+git<N>.<sha>. DEB_REVISION (default 1) is
# the Debian revision: bump it to rebuild the same PSCAL commit.
#
# What is in it: every program PSCAL's own `cmake --install` installs (the
# pascal, clike, rea and aether front ends, clike-repl, exsh, pscalvm and the
# bytecode tools) in /usr/bin, and their runtime files (units, headers,
# fonts, examples) in /usr/lib/pscal, rea's modules in /usr/lib/rea. SDL
# graphics are off.
# ---------------------------------------------------------------------------
set -eu

REF=${1:?usage: build-deb.sh REF OUTDIR}
OUT=${2:?usage: build-deb.sh REF OUTDIR}
SRC=${PSCAL_SRC:-/tmp/pscal-src}
WORK=/tmp/pscal-pkg
# dpkg-shlibdeps insists the files sit in debian/<package> of a source tree.
STAGE=$WORK/debian/pscal
RUNTIME_ROOT=/usr/lib/pscal
export DEBIAN_FRONTEND=noninteractive

die() { printf 'build-deb.sh: %s\n' "$*" >&2; exit 1; }
step() { printf '\n==> %s\n' "$*"; }

mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)

step "Build dependencies"
apt-get update
apt-get install -y --no-install-recommends \
    build-essential cmake git ca-certificates pkg-config \
    libcurl4-openssl-dev dpkg-dev file python3

step "PSCAL at $REF"
if [ ! -d "$SRC/.git" ]; then
    git clone https://github.com/emkey1/pscal.git "$SRC"
fi
cd "$SRC"
git fetch --tags --force origin
git checkout --detach "$REF"
# Shallow first; a pinned submodule commit that is not a branch tip can need
# the full history.
git submodule update --init --recursive --depth 1 ||
    git submodule update --init --recursive
SHA=$(git rev-parse --short=8 HEAD)

DESC=$(git describe --tags --long --match 'V.*' HEAD) ||
    die "no V.<major>R<release> tag reaches $REF"
set -- $(printf '%s\n' "$DESC" |
    sed -n 's/^V\.\([0-9][0-9]*\)R\([0-9][0-9]*\)-\([0-9][0-9]*\)-g[0-9a-f]*$/\1 \2 \3/p')
[ $# -eq 3 ] || die "cannot make a version of '$DESC'"
UPSTREAM="$1.$2"
[ "$3" = 0 ] || UPSTREAM="$UPSTREAM+git$3.$SHA"
VERSION="$UPSTREAM-${DEB_REVISION:-1}"
ARCH=$(dpkg --print-architecture)
printf 'version %s, architecture %s, from %s\n' "$VERSION" "$ARCH" "$DESC"

step "Configure and build"
rm -rf build
cmake -S . -B build \
    -DCMAKE_BUILD_TYPE=Release \
    -DRELEASE_BUILD=ON \
    -DSDL=OFF \
    -DCMAKE_INSTALL_PREFIX=/usr \
    -DCMAKE_INSTALL_LIBDIR=lib \
    -DPSCAL_INSTALL_ROOT="$RUNTIME_ROOT"
cmake --build build --parallel "$(nproc)"

step "Stage the install"
rm -rf "$WORK"
DESTDIR="$STAGE" cmake --install build
[ -x "$STAGE/usr/bin/pascal" ] || die "the install has no /usr/bin/pascal"
[ -d "$STAGE$RUNTIME_ROOT/lib" ] || die "the install has no $RUNTIME_ROOT/lib"
# rea does not use the install root: it looks beside its binary, in
# /usr/lib/rea, which is why CMAKE_INSTALL_LIBDIR is plain lib above (Debian's
# default, lib/<multiarch>, put its modules where rea never looks).
[ -f "$STAGE/usr/lib/rea/strings" ] || die "the install has no /usr/lib/rea/strings"
# The install backs up a running exsh as exsh.previous; never ship one.
rm -f "$STAGE/usr/bin/exsh.previous"
for f in "$STAGE"/usr/bin/*; do
    if file -b "$f" | grep -q '^ELF'; then
        strip --strip-unneeded "$f"
    fi
done

DOC="$STAGE/usr/share/doc/pscal"
mkdir -p "$DOC/third-party"
{
    printf 'PSCAL, built from %s (%s) of https://github.com/emkey1/pscal\n' "$DESC" "$SHA"
    printf 'for AOK-Workstation (https://github.com/emkey1/aok-apt).\n\n'
    printf 'PSCAL is licensed under the Apache License, Version 2.0:\n\n'
    cat LICENSE
    if [ -f NOTICE ]; then
        printf '\n\nNOTICE:\n\n'
        cat NOTICE
    fi
    printf '\n\nCode from other projects built into these programs keeps its own\n'
    printf 'licence; the texts are in /usr/share/doc/pscal/third-party.\n'
} > "$DOC/copyright"
# Every licence file of the third-party code in the tree, named by its path.
find third-party components/*/src/third_party components/*/third-party \
        -maxdepth 3 -type f \
        \( -iname 'LICENSE*' -o -iname 'COPYING*' -o -iname 'NOTICE*' \) 2>/dev/null |
    while IFS= read -r lic; do
        cp "$lic" "$DOC/third-party/$(printf '%s' "$lic" | tr '/' '_')"
    done

step "Package metadata"
mkdir -p "$WORK/debian" "$STAGE/DEBIAN"
printf 'Source: pscal\n\nPackage: pscal\nArchitecture: any\n' > "$WORK/debian/control"
set --
for f in "$STAGE"/usr/bin/*; do
    if file -b "$f" | grep -q '^ELF'; then
        set -- "$@" "-e$f"
    fi
done
[ $# -gt 0 ] || die "no programs in /usr/bin to scan"
SHLIBDEPS=$(cd "$WORK" && dpkg-shlibdeps -O "$@") || die "dpkg-shlibdeps failed"
DEPENDS=$(printf '%s\n' "$SHLIBDEPS" | sed -n 's/^shlibs:Depends=//p')
[ -n "$DEPENDS" ] || die "dpkg-shlibdeps found no dependencies: $SHLIBDEPS"
INSTALLED_SIZE=$(du -sk --exclude=DEBIAN "$STAGE" | cut -f1)

cat > "$STAGE/DEBIAN/control" <<EOF
Package: pscal
Version: $VERSION
Architecture: $ARCH
Maintainer: emkey1 <emkey1@users.noreply.github.com>
Installed-Size: $INSTALLED_SIZE
Depends: $DEPENDS
Section: interpreters
Priority: optional
Homepage: https://github.com/emkey1/pscal
Description: Pascal, C-like, Rea and Aether front ends for the PSCAL bytecode VM
 PSCAL compiles Pascal, a C-like language, Rea and Aether to bytecode for one
 virtual machine, and includes exsh, a shell built on the same runtime.
 .
 Built from $DESC ($SHA) of github.com/emkey1/pscal for the Devuan 6
 filesystems of AOK-Workstation, without SDL graphics.
EOF

# exsh can be a login shell.
cat > "$STAGE/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
if [ "$1" = configure ] && command -v add-shell >/dev/null 2>&1; then
    add-shell /usr/bin/exsh
fi
EOF
cat > "$STAGE/DEBIAN/postrm" <<'EOF'
#!/bin/sh
set -e
if [ "$1" = remove ] || [ "$1" = purge ]; then
    if command -v remove-shell >/dev/null 2>&1; then
        remove-shell /usr/bin/exsh
    fi
fi
EOF
chmod 755 "$STAGE/DEBIAN/postinst" "$STAGE/DEBIAN/postrm"

step "Build the .deb"
DEB="$OUT/pscal_${VERSION}_${ARCH}.deb"
dpkg-deb --root-owner-group -Zxz --build "$STAGE" "$DEB"
dpkg-deb --info "$DEB"
dpkg-deb --contents "$DEB" | awk '{print $6}' | grep '^\./usr/bin/' | sort
ls -l "$DEB"
printf 'BUILT %s\n' "$DEB"
