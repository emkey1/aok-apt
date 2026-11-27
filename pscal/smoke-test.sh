#!/bin/sh
# smoke-test.sh DEBDIR | --installed
# ---------------------------------------------------------------------------
# Install DEBDIR's pscal .deb for this machine's architecture into a clean
# Debian or Devuan system (as root, in a container), or with --installed take
# the pscal already installed (from the repository: verify.yml), and run one
# small program in each language. Each program imports something from the runtime files in
# /usr/lib/pscal, so a wrong install root fails here rather than on a user's
# device. Prints PSCAL SMOKE OK at the end, and nothing like it on a failure.
# ---------------------------------------------------------------------------
set -eu

DEBS=${1:?usage: smoke-test.sh DEBDIR | --installed}
export DEBIAN_FRONTEND=noninteractive
ARCH=$(dpkg --print-architecture)
if [ "$DEBS" != --installed ]; then
    DEB=$(ls "$DEBS"/pscal_*_"$ARCH".deb | tail -n 1)
    [ -f "$DEB" ] || { echo "no pscal .deb for $ARCH in $DEBS" >&2; exit 1; }
    apt-get update
    apt-get install -y "$(cd "$(dirname "$DEB")" && pwd)/$(basename "$DEB")"
fi
dpkg-query -W pscal
grep -qx /usr/bin/exsh /etc/shells || { echo "exsh is not in /etc/shells" >&2; exit 1; }

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
cd "$T"
fails=0
check() { # NAME EXPECTED COMMAND...
    name=$1; want=$2; shift 2
    got=$("$@" 2>&1) || true
    case "$got" in
        *"$want"*) printf 'ok    %s\n' "$name" ;;
        *) printf 'FAIL  %s: wanted "%s", got:\n%s\n' "$name" "$want" "$got"; fails=$((fails + 1)) ;;
    esac
}

cat > smoke.pas <<'EOF'
program Smoke;
uses MathLib;
begin
  if PiValue > 3.14 then
    writeln('pascal ok')
  else
    writeln('pascal: MathLib is wrong');
end.
EOF
cat > smoke.cl <<'EOF'
import "math_utils.cl";

int main() {
    printf("clike ok %d\n", cube(3));
    return 0;
}
EOF
cat > smoke.rea <<'EOF'
#import "strings";

writeln("rea ok");
EOF
cat > smoke.aether <<'EOF'
fn main() -> Void {
    fx { println("aether ok"); }
    ret;
}
EOF

check pascal 'pascal ok' pascal smoke.pas
check clike 'clike ok 27' clike smoke.cl
check rea 'rea ok' rea smoke.rea
check aether 'aether ok' aether smoke.aether
check exsh 'exsh ok' exsh -c 'echo exsh ok'
for tool in pscalvm pscaljson2bc pscald pscalasm clike-repl; do
    if [ -x /usr/bin/$tool ]; then
        printf 'ok    %s is installed\n' "$tool"
    else
        printf 'note  %s is not in this build\n' "$tool"
    fi
done

if [ "$fails" -ne 0 ]; then
    echo "$fails check(s) failed" >&2
    exit 1
fi
echo "PSCAL SMOKE OK ($ARCH, $(. /etc/os-release && echo "$PRETTY_NAME"))"
