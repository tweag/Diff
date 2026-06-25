---
name: haskell-toolchain
description: >
  Install a specific version of GHC, cabal-install, and stack using ghcup,
  plus a recent z3 binary from GitHub. Use this skill
  whenever the user needs to set up or reproduce a Haskell build environment
  in a container: version-pinned toolchains, CI images, LiquidHaskell setups,
  or any task that starts with "install GHC".
compatibility:
  os: Ubuntu 22.04 / 24.04 (Debian-based), x86_64
  network: downloads.haskell.org, hackage.haskell.org, github.com must be reachable
---

# Haskell Toolchain

## 1. System prerequisites

```bash
apt-get update -qq
apt-get install -y --no-install-recommends \
  curl ca-certificates \
  build-essential \
  libgmp-dev libffi-dev zlib1g-dev \
  libnuma-dev \
  pkg-config
```

`libnuma-dev` is required by some GHC bindists; omitting it causes a silent
link failure.

## 2. Install ghcup (non-interactive)

```bash
export BOOTSTRAP_HASKELL_NONINTERACTIVE=1
export BOOTSTRAP_HASKELL_NO_UPGRADE=1
# Do not install any default GHC/cabal yet — we pin versions below
export BOOTSTRAP_HASKELL_INSTALL_NO_STACK=1
export GHCUP_INSTALL_BASE_PREFIX=/usr/local

curl -sSf https://get-ghcup.haskell.org | sh

# Make ghcup and installed tools available in the current shell
source /usr/local/.ghcup/env
# For subsequent RUN layers in a Dockerfile, persist it:
echo 'source /usr/local/.ghcup/env' >> /etc/profile.d/ghcup.sh
```

`BOOTSTRAP_HASKELL_NONINTERACTIVE=1` suppresses all prompts.
`GHCUP_INSTALL_BASE_PREFIX=/usr/local` installs system-wide rather than into
`~/.ghcup`.

## 3. Install specific tool versions

Replace the version strings with whatever the project requires.

```bash
# Discover available versions if needed:
#   ghcup list --tool ghc
#   ghcup list --tool cabal
#   ghcup list --tool stack

GHC_VERSION=9.6.6
CABAL_VERSION=3.10.3.0
STACK_VERSION=2.15.7

ghcup install ghc   $GHC_VERSION   && ghcup set ghc   $GHC_VERSION
ghcup install cabal $CABAL_VERSION && ghcup set cabal $CABAL_VERSION
ghcup install stack $STACK_VERSION && ghcup set stack $STACK_VERSION
```

`ghcup set` updates the unversioned symlinks (`ghc`, `cabal`, `stack`) so
nothing downstream needs to know the exact version.

Verify:

```bash
ghc   --version   # The Glorious Glasgow Haskell Compilation System, version <GHC_VERSION>
cabal --version   # cabal-install version <CABAL_VERSION>
stack --version   # Version <STACK_VERSION>, ...
```

## 4. Prime the Hackage index

```bash
cabal update
```

This is a network call to `hackage.haskell.org`. Run it once before the fist
`cabal build` invocations.

## 5. Install a recent z3 binary

The Ubuntu 24.04 apt package for z3 is 4.8.12 (2021). LiquidHaskell and
other SMT-backed tools benefit from a much newer release. Install from the
GitHub release binary instead.

```bash
Z3_VERSION=4.16.0  # update to latest tag from github.com/Z3Prover/z3/releases
GLIBC_VERSION=2.39

curl -sSfL \
  "https://github.com/Z3Prover/z3/releases/download/z3-${Z3_VERSION}/z3-${Z3_VERSION}-x64-glibc-${GLIBC_VERSION}.zip" \
  -o /tmp/z3.zip

apt-get install -y --no-install-recommends unzip
unzip -q /tmp/z3.zip -d /tmp/z3-bin
install -m 755 /tmp/z3-bin/z3-${Z3_VERSION}-x64-glibc-2.35/bin/z3 /usr/local/bin/z3
rm -rf /tmp/z3.zip /tmp/z3-bin

z3 --version  # Z3 version 4.16.0 - 64 bit
```

The glibc-2.35 build runs on Ubuntu 22.04 and 24.04. Check the releases page
for the exact asset filename if the version changes.
