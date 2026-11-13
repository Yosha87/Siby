#!/bin/sh
# Builds the 64-bit Linux version of Siby as a portable archive:
# unpack it anywhere, then run "./siby" (or the Siby.desktop shortcut).
# Tcl/Tk 8.6 is shipped inside (lib/), so nothing needs installing on a
# usual desktop (X11 or XWayland, fontconfig, Xft).
#
# Prerequisites to build (Ubuntu/Debian): sudo apt install build-essential
#   tcl8.6-dev tk8.6-dev zlib1g-dev libpng-dev
#
# Usage: outils/linux/construire.sh [work_folder]
# Result: dist/Siby-linux-x64.tar.gz (and the folder dist/Siby-linux next to it)
set -e
ICI=$(cd "$(dirname "$0")" && pwd)
RACINE=$(cd "$ICI/../.." && pwd)
TRAVAIL=${1:-$RACINE/build-linux}
mkdir -p "$TRAVAIL"
TRAVAIL=$(cd "$TRAVAIL" && pwd)

### 1. Build (copy of the sources, so as not to mix with the development build)
echo "== Siby for Linux"
rm -rf "$TRAVAIL/scid" "$TRAVAIL/install"
mkdir -p "$TRAVAIL/scid"
cd "$RACINE/siby"
tar cf - --exclude='*.o' --exclude='*.a' --exclude=./tkscid --exclude=./tcscid --exclude=./pgnscid --exclude=./sbbiblio \
    --exclude=./sbclassement --exclude=./scid --exclude=./tcl/sharedir.tcl . | (cd "$TRAVAIL/scid" && tar xf -)
cd "$TRAVAIL/scid"
./configure BINDIR="$TRAVAIL/install/bin" SHAREDIR="$TRAVAIL/install/share/scid" > "$TRAVAIL/configure.log" 2>&1
# (at most 16 jobs, then once more alone: the Makefile misses a dependency
# that shows with many cores, scmerge linked before game.o)
J=$(nproc); [ "$J" -gt 16 ] && J=16
make -j"$J" > "$TRAVAIL/make.log" 2>&1 || make >> "$TRAVAIL/make.log" 2>&1 || { tail -30 "$TRAVAIL/make.log" >&2; exit 1; }
make install > "$TRAVAIL/install.log" 2>&1 || { tail -30 "$TRAVAIL/install.log" >&2; exit 1; }
strip "$TRAVAIL/install/bin/"* 2>/dev/null || true

### 2. Portable folder: bin/ and share/scid/ side by side (Siby finds its
### files next to the program), Tcl/Tk in lib/
NOM=Siby
DIST="$RACINE/dist/$NOM-linux"
rm -rf "$DIST"
mkdir -p "$DIST/lib" "$DIST/licences"
cp -a "$TRAVAIL/install/bin" "$DIST/bin"
mkdir -p "$DIST/share"
cp -a "$TRAVAIL/install/share/scid" "$DIST/share/scid"
# (no example databases: they only served SCID's old tactics trainer, which
# Siby's menus no longer offer; the folder is kept, empty)
rm -f "$DIST/share/scid/bases/"*
for l in libtcl8.6.so libtk8.6.so; do
  f=$(ldconfig -p | awk -v l="$l" '$1 == l {print $NF; exit}')
  [ -n "$f" ] || { echo "$l not found" >&2; exit 1; }
  cp -L "$f" "$DIST/lib/"
done
# (small X libraries Tk needs that a minimal Linux may lack: Siby did not
# start on a fresh Ubuntu without libXss, test of 2026-10-30)
for l in libXss.so.1 libXft.so.2; do
  f=$(ldconfig -p | awk -v l="$l" '$1 == l {print $NF; exit}')
  [ -n "$f" ] && cp -L "$f" "$DIST/lib/"
done
cp -a /usr/share/tcltk/tcl8.6 "$DIST/lib/tcl8.6"
cp -a /usr/share/tcltk/tk8.6 "$DIST/lib/tk8.6"
mkdir -p "$DIST/share/scid/engines"
# Launcher: Tcl/Tk from lib/, then Siby
cat > "$DIST/siby" <<'L'
#!/bin/sh
# Siby launcher: uses the Tcl/Tk shipped in lib/
ICI=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
export LD_LIBRARY_PATH="$ICI/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export TCL_LIBRARY="$ICI/lib/tcl8.6"
export TK_LIBRARY="$ICI/lib/tk8.6"
exec "$ICI/bin/tkscid" -encoding utf-8 "$ICI/bin/scid" "$@"
L
chmod 755 "$DIST/siby"
# Icon, and a script that adds Siby to the applications menu
cp "$RACINE/siby/icons/siby.png" "$DIST/siby.png" 2>/dev/null || true
cat > "$DIST/installer-raccourci.sh" <<'L'
#!/bin/sh
# Adds Siby to the applications menu (for the current user only)
ICI=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
mkdir -p "$HOME/.local/share/applications"
cat > "$HOME/.local/share/applications/siby.desktop" <<D
[Desktop Entry]
Type=Application
Name=Siby
Comment=Chess databases, analysis and preparation
Exec="$ICI/siby" %F
Icon=$ICI/siby.png
Terminal=false
Categories=Game;BoardGame;
MimeType=application/x-chess-pgn;
D
echo "Siby added to the applications menu."
L
chmod 755 "$DIST/installer-raccourci.sh"
cp "$RACINE/siby/COPYING" "$DIST/licences/COPYING.txt"
cp "$RACINE/siby/README.txt" "$DIST/licences/README-scidvspc.txt"
cp "$ICI/README.txt" "$DIST/README.txt"

### 3. Archive
cd "$RACINE/dist"
rm -f "$NOM-linux-x64.tar.gz"
tar czf "$NOM-linux-x64.tar.gz" --transform "s,^$NOM-linux,$NOM," "$NOM-linux"
echo "== Done: $RACINE/dist/$NOM-linux-x64.tar.gz ($(du -h "$NOM-linux-x64.tar.gz" | cut -f1))"
