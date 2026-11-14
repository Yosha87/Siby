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
# With TCLTK=<prefix>: the Tcl/Tk built there (tclConfig.sh, lib/, include/)
# instead of the system's. The published package is built that way on an old
# Linux by construire_docker.sh, so that it runs on the usual distributions.
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
if [ -n "${TCLTK:-}" ]; then
  "$TCLTK/bin/tclsh8.6" ./configure BINDIR="$TRAVAIL/install/bin" SHAREDIR="$TRAVAIL/install/share/scid" \
    TCL_INCLUDE="-I$TCLTK/include" TCL_LIBRARY="-L$TCLTK/lib -ltcl8.6 -lpthread -ldl -lm" \
    TK_LIBRARY="-L$TCLTK/lib -ltcl8.6 -ltk8.6 -lX11 -lpthread -ldl -lm" > "$TRAVAIL/configure.log" 2>&1
else
  ./configure BINDIR="$TRAVAIL/install/bin" SHAREDIR="$TRAVAIL/install/share/scid" > "$TRAVAIL/configure.log" 2>&1
fi
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
  if [ -n "${TCLTK:-}" ]; then f="$TCLTK/lib/$l"; else
  f=$(ldconfig -p | awk -v l="$l" '$1 == l {print $NF; exit}'); fi
  [ -n "$f" ] || { echo "$l not found" >&2; exit 1; }
  cp -L "$f" "$DIST/lib/"
done
# (small X libraries Tk needs that a minimal Linux may lack: Siby did not
# start on a fresh Ubuntu without libXss, test of 2026-10-30)
for l in libXss.so.1 libXft.so.2; do
  f=$(ldconfig -p | awk -v l="$l" '$1 == l {print $NF; exit}')
  [ -n "$f" ] && cp -L "$f" "$DIST/lib/"
done
if [ -n "${TCLTK:-}" ]; then
  cp -a "$TCLTK/lib/tcl8.6" "$DIST/lib/tcl8.6"
  cp -a "$TCLTK/lib/tk8.6" "$DIST/lib/tk8.6"
  # (Tcl's modules, msgcat among them: clock needs it at start)
  cp -a "$TCLTK/lib/tcl8" "$DIST/lib/tcl8"
else
  cp -a /usr/share/tcltk/tcl8.6 "$DIST/lib/tcl8.6"
  cp -a /usr/share/tcltk/tk8.6 "$DIST/lib/tk8.6"
fi
mkdir -p "$DIST/share/scid/engines"
# (with CURL_EMBARQUE=1: this Linux's curl and its libraries in lib/curl/,
# used only where the system has no curl: Siby downloads everything with it,
# and Ubuntu 22.04 Desktop and Debian do not install it, 2026-11-14)
if [ "${CURL_EMBARQUE:-}" = 1 ]; then
  mkdir -p "$DIST/lib/curl/libs"
  cp -L "$(command -v curl)" "$DIST/lib/curl/curl.bin"
  ldd "$DIST/lib/curl/curl.bin" | awk '/=>/ {print $3}' | while read -r l; do
    case "$(basename "$l")" in
      libc.so*|libm.so*|libpthread.so*|libdl.so*|librt.so*|libresolv.so*|ld-linux*) ;;
      *) cp -L "$l" "$DIST/lib/curl/libs/" ;;
    esac
  done
  cat > "$DIST/lib/curl/curl" <<'C'
#!/bin/sh
# curl shipped with Siby, for a Linux without one: its own libraries only
D=$(cd "$(dirname "$0")" && pwd)
LD_LIBRARY_PATH="$D/libs" exec "$D/curl.bin" "$@"
C
  chmod 755 "$DIST/lib/curl/curl"
fi
# Launcher: Tcl/Tk from lib/, then Siby
cat > "$DIST/siby" <<'L'
#!/bin/sh
# Siby launcher: uses the Tcl/Tk shipped in lib/
ICI=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
export LD_LIBRARY_PATH="$ICI/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export TCL_LIBRARY="$ICI/lib/tcl8.6"
export TK_LIBRARY="$ICI/lib/tk8.6"
# (Siby downloads with curl: the one shipped when the system has none)
if ! command -v curl >/dev/null 2>&1 && [ -x "$ICI/lib/curl/curl" ]; then
  export PATH="$ICI/lib/curl:$PATH"
fi
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

# (every file writable by its owner: Tcl installs its libraries read-only,
# and Siby's update could not replace them, test of 2026-11-14)
chmod -R u+w "$DIST"

### 3. Archive
cd "$RACINE/dist"
rm -f "$NOM-linux-x64.tar.gz"
tar czf "$NOM-linux-x64.tar.gz" --transform "s,^$NOM-linux,$NOM," "$NOM-linux"
echo "== Done: $RACINE/dist/$NOM-linux-x64.tar.gz ($(du -h "$NOM-linux-x64.tar.gz" | cut -f1))"
