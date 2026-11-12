#!/bin/sh
# Builds SCID vs. PC and installs it into build-install/ (inside the repository),
# without writing anything to the system.
# Usage: outils/compiler.sh            (build + install)
#        outils/compiler.sh --deps     (first install the Debian/Ubuntu packages)
set -e
RACINE=$(cd "$(dirname "$0")/.." && pwd)
SRC="$RACINE/scidvspc"
DEST="$RACINE/build-install"

if [ "$1" = "--deps" ]; then
  sudo apt-get update
  sudo apt-get install -y g++ make tcl-dev tk-dev libx11-dev zlib1g-dev
fi

cd "$SRC"
./configure BINDIR="$DEST/bin" SHAREDIR="$DEST/share/scid"
make -j"$(nproc)"
make install
echo
echo "OK. Run with: $DEST/bin/scid"
