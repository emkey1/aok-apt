# aok-apt: AOK-Workstation's own apt repository

Packages for the Devuan 6 ("excalibur") filesystems of
[AOK-Workstation](https://github.com/emkey1/ish-AOK), for arm64 and amd64,
served by GitHub Pages from the `gh-pages` branch:

    https://emkey1.github.io/aok-apt

| Package | What it is |
|---|---|
| `pscal` | [PSCAL](https://github.com/emkey1/pscal): the `pascal`, `clike`, `rea` and `aether` front ends, `exsh`, `pscalvm` and the bytecode tools, with their runtime files in `/usr/lib/pscal`. No SDL graphics. |

## Using it

**In AOK-Workstation** nothing needs doing. A native root's companion
filesystem gets this source when it is set up, and an existing companion
gets it the next time `sudo apt` runs. Then:

```sh
sudo apt update
sudo apt install pscal
```

Any other Devuan 6 filesystem in AOK-Workstation can add it with
`sudo sh /AOK/tools/aok-apt.sh`, and stop using it with
`sudo sh /AOK/tools/aok-apt.sh --remove`.

**Anywhere else** running Devuan 6 or Debian 13 (trixie), arm64 or amd64:

```sh
sudo curl -fsSL -o /usr/share/keyrings/aok-apt.asc https://emkey1.github.io/aok-apt/aok-apt.asc
sudo tee /etc/apt/sources.list.d/aok.sources <<'EOF'
Types: deb
URIs: https://emkey1.github.io/aok-apt
Suites: excalibur
Components: main
Signed-By: /usr/share/keyrings/aok-apt.asc
EOF
sudo apt update
```

The repository is signed with this key:

    ed25519 D127 47AE 9E6F 55A7 C139  BD6F E16C 5C31 AF98 5A69
    AOK-Workstation apt repository (github.com/emkey1/aok-apt)

Check the fingerprint of the key you downloaded before you trust it:
`gpg --show-keys /usr/share/keyrings/aok-apt.asc`. The same key is in this
repository as `aok-apt.asc`, and AOK-Workstation ships it as
`/AOK/tools/aok-apt.asc`.

## Building and publishing

The **PSCAL packages** workflow (Actions, Run workflow) takes a PSCAL tag,
branch or commit and a Debian revision. It:

1. builds `pscal_<version>_<arch>.deb` for arm64 (on GitHub's arm64 runner)
   and amd64, each in a `debian:trixie` container
   ([`pscal/build-deb.sh`](pscal/build-deb.sh));
2. installs each into clean containers (Debian trixie on both, Devuan 6 on
   amd64; there is no arm64 Devuan image) and runs one program in every
   language, each importing something from `/usr/lib/pscal`
   ([`pscal/smoke-test.sh`](pscal/smoke-test.sh));
3. adds the packages to `gh-pages`, rebuilds the indexes and signs them
   ([`scripts/publish.sh`](scripts/publish.sh)).

Versions: PSCAL tag `V.1R34` is `1.34`; a commit past it is
`1.34+git<N>.<sha>`; the Debian revision follows (`1.34-1`). A published
file is never replaced: to rebuild the same commit, bump the revision.

The signing key is the repository secret `APT_SIGNING_KEY` (an armoured
private key without a passphrase, used only by `publish.sh`, imported into a
throwaway keyring). The maintainer keeps a backup and a revocation
certificate offline. If the key is ever replaced, AOK-Workstation's copy
(`opt/AOK/tools/aok-apt.asc` in ish-AOK) has to change in the same release.
