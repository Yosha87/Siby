#!/bin/sh
# Builds the 64-bit Windows version of Siby from Linux
# (MinGW-w64 cross-compilation), as a zipped portable folder:
# unzip it, then run "Siby.exe" (a launcher for bin\Siby.exe).
#
# Prerequisites (Ubuntu/Debian): sudo apt install mingw-w64 zip
# Optional, for testing: wine64 (see outils/windows/tester.sh).
#
# Usage: outils/windows/construire.sh [work_folder]
# Result: dist/Siby-windows-x64.zip (and the folder next to it)
set -e
ICI=$(cd "$(dirname "$0")" && pwd)
RACINE=$(cd "$ICI/../.." && pwd)
TRAVAIL=${1:-$RACINE/build-windows}
TCLVER=8.6.14
CROSS=x86_64-w64-mingw32
mkdir -p "$TRAVAIL"
TRAVAIL=$(cd "$TRAVAIL" && pwd)
TCLTK="$TRAVAIL/tcltk"

command -v $CROSS-g++ >/dev/null || { echo "MinGW-w64 is missing: sudo apt install mingw-w64" >&2; exit 1; }

### 1. Tcl/Tk for Windows (only once)
if [ ! -f "$TCLTK/bin/tk86.dll" ]; then
  echo "== Tcl/Tk $TCLVER for Windows"
  mkdir -p "$TRAVAIL/sources"
  cd "$TRAVAIL/sources"
  for p in tcl tk; do
    [ -f $p.tgz ] || curl -sSL -o $p.tgz "https://prdownloads.sourceforge.net/tcl/$p$TCLVER-src.tar.gz"
    tar xzf $p.tgz
  done
  cd "$TRAVAIL/sources/tcl$TCLVER/win"
  ./configure --host=$CROSS --prefix="$TCLTK" --enable-64bit --enable-threads > "$TRAVAIL/tcl.log" 2>&1
  make -j"$(nproc)" >> "$TRAVAIL/tcl.log" 2>&1
  make install >> "$TRAVAIL/tcl.log" 2>&1
  cd "$TRAVAIL/sources/tk$TCLVER/win"
  ./configure --host=$CROSS --prefix="$TCLTK" --enable-64bit --enable-threads \
      --with-tcl="$TRAVAIL/sources/tcl$TCLVER/win" > "$TRAVAIL/tk.log" 2>&1
  make -j"$(nproc)" >> "$TRAVAIL/tk.log" 2>&1
  make install >> "$TRAVAIL/tk.log" 2>&1
fi

### 2. SCID (copy of the sources, so as not to mix with the Linux build)
echo "== SCID for Windows"
rm -rf "$TRAVAIL/scid"
mkdir -p "$TRAVAIL/scid"
cd "$RACINE/scidvspc"
tar cf - --exclude='*.o' --exclude='*.a' --exclude=./tkscid --exclude=./tcscid --exclude=./pgnscid --exclude=./sbbiblio --exclude=./sbclassement . | (cd "$TRAVAIL/scid" && tar xf -)
cd "$TRAVAIL/scid"
make -f Makefile.mingw W64=1 TCL_DIR="$TCLTK" -j"$(nproc)" > "$TRAVAIL/scid.log" 2>&1 || {
  tail -30 "$TRAVAIL/scid.log" >&2; exit 1; }
$CROSS-strip scid.exe tcscid.exe pgnscid.exe sbbiblio.exe sbclassement.exe scidt.exe scmerge.exe scidlet.exe

### 3. Portable folder
NOM=Siby
DIST="$RACINE/dist/$NOM"
rm -rf "$DIST"
mkdir -p "$DIST/bin" "$DIST/lib"
cd "$TRAVAIL/scid"
cp scid.exe "$DIST/bin/Siby.exe"
cp tcscid.exe pgnscid.exe sbbiblio.exe sbclassement.exe scidt.exe scmerge.exe scidlet.exe scid.gui "$DIST/bin/"
cp "$TCLTK/bin/tcl86.dll" "$TCLTK/bin/tk86.dll" "$TCLTK/bin/zlib1.dll" "$DIST/bin/"
# Shared files: on Windows, SCID looks for them next to scid.exe
mkdir -p "$DIST/bin/data" "$DIST/bin/lang" "$DIST/bin/engines"
cp scid.eco "$DIST/bin/data/"
cp spelling.ssp "$DIST/bin/data/"
for d in books html bitmaps bitmaps2 sounds; do cp -r $d "$DIST/bin/"; done
# (no example databases: they only served SCID's old tactics trainer, which
# Siby's menus no longer offer; an empty folder, which SCID expects)
mkdir -p "$DIST/bin/bases"
cp tcl/lang/*.tcl "$DIST/bin/lang/"
# Tcl/Tk libraries (Tcl looks for them in ..\lib relative to bin)
cp -r "$TCLTK/lib/tcl8.6" "$TCLTK/lib/tk8.6" "$TCLTK/lib/tcl8" "$DIST/lib/"
for p in dde1.4 reg1.3; do cp -r "$TCLTK/lib/$p" "$DIST/lib/"; done
# Readme at the top; licences (Siby's and those of the projects it builds
# on) in a folder of their own
mkdir -p "$DIST/licences"
cp COPYING "$DIST/licences/COPYING.txt"
cp "$RACINE/scidvspc/README.txt" "$DIST/licences/README-scidvspc.txt"
cp "$ICI/README.txt" "$DIST/README.txt"
# Launcher at the top: Siby.exe, no console window (a .bat file opens one)
$CROSS-gcc -municode -mwindows -O2 -o "$DIST/Siby.exe" "$ICI/lanceur.c" "$TRAVAIL/scid/scid.res" 2>/dev/null ||
  $CROSS-gcc -municode -mwindows -O2 -o "$DIST/Siby.exe" "$ICI/lanceur.c"
$CROSS-strip "$DIST/Siby.exe"

cd "$RACINE/dist"
rm -f "$NOM-windows-x64.zip"
zip -qr "$NOM-windows-x64.zip" "$NOM"
echo "== Done: $RACINE/dist/$NOM-windows-x64.zip ($(du -h "$NOM-windows-x64.zip" | cut -f1))"
