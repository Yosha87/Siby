#!/bin/bash
# Builds the published Linux package on Debian 11 (glibc 2.31), in Docker:
# built on a recent Linux, Siby needed its glibc and did not start on
# Ubuntu 22.04, Debian 12 or Mint 21 (found 2026-11-14). Built on an old one,
# it runs on every newer distribution. Tcl/Tk 8.6.14 (the Windows version) is
# built from source there, once, in the work folder.
#   outils/linux/construire_docker.sh [work_folder]
# Result: dist/Siby-linux-x64.tar.gz, as construire.sh
set -euo pipefail
ICI=$(cd "$(dirname "$0")" && pwd)
RACINE=$(cd "$ICI/../.." && pwd)
TRAVAIL=${1:-$RACINE/build-linux-docker}
mkdir -p "$TRAVAIL"
TRAVAIL=$(cd "$TRAVAIL" && pwd)
TCLVER=8.6.14
docker run --rm --network host \
  -e https_proxy="${https_proxy:-}" -e HTTPS_PROXY="${HTTPS_PROXY:-}" \
  ${CA:+-v "$CA:/ca.crt:ro"} \
  -v "$RACINE:/depot" -v "$TRAVAIL:/travail" -e TCLVER=$TCLVER \
  debian:bullseye bash -euc '
  [ -f /ca.crt ] && echo "Acquire::https::CAInfo \"/ca.crt\";" > /etc/apt/apt.conf.d/99ca
  export DEBIAN_FRONTEND=noninteractive
  # (Debian 11 archived: its security updates moved to archive.debian.org)
  printf "%s\n" "deb http://deb.debian.org/debian bullseye main" \
    "deb http://archive.debian.org/debian-security bullseye-security main" > /etc/apt/sources.list
  rm -f /etc/apt/sources.list.d/*
  apt-get update -qq >/dev/null
  apt-get install -y -qq build-essential curl ca-certificates zlib1g-dev libpng-dev \
    libx11-dev libxft-dev libxss-dev libfontconfig1-dev libxext-dev >/dev/null
  T=/travail/tcltk
  if [ ! -x $T/bin/tclsh8.6 ]; then
    mkdir -p /travail/sources && cd /travail/sources
    for p in tcl tk; do
      [ -f $p$TCLVER.tgz ] || curl -sSL -o $p$TCLVER.tgz "https://prdownloads.sourceforge.net/tcl/$p$TCLVER-src.tar.gz"
      rm -rf $p$TCLVER && tar xzf $p$TCLVER.tgz
    done
    (cd tcl$TCLVER/unix && ./configure --prefix=$T --enable-threads >/dev/null && make -j8 >/dev/null && make install >/dev/null)
    (cd tk$TCLVER/unix && ./configure --prefix=$T --enable-threads --with-tcl=$T/lib >/dev/null && make -j8 >/dev/null && make install >/dev/null)
  fi
  ldd --version | head -1
  TCLTK=$T CURL_EMBARQUE=1 sh /depot/outils/linux/construire.sh /travail/siby
'
