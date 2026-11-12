# Building and running SCID vs. PC ("modern" version) on Linux

Tested on Ubuntu 24.04 (Tcl/Tk 8.6.14, g++ 13), on 10/18/2026.

## 1. Required packages

```sh
sudo apt-get install -y g++ make tcl-dev tk-dev libx11-dev zlib1g-dev
```

Optional, but recommended:

```sh
sudo apt-get install -y stockfish fonts-inter fonts-noto-core
```

- `stockfish`: analysis engine (Stockfish 16 in Ubuntu 24.04, which supports WDL).
- `fonts-inter` or `fonts-noto-core`: modern fonts. SCID uses the first
  available font among Inter, Noto Sans, Cantarell, Ubuntu and DejaVu Sans.

To regenerate the cburnett pieces (rarely needed), you also need
`librsvg2-bin` and `imagemagick`.

## 2. Building

From the root of the repository:

```sh
outils/compiler.sh          # or: outils/compiler.sh --deps  (installs the packages first)
```

The script runs `./configure` then `make` in `scidvspc/`, and installs everything into
`build-install/` (inside the repository). **Nothing is written to the system.** The
build takes about 20 seconds. The compiler warnings
(`register`, `memcpy`…) come from the original code and are harmless.

Equivalent manual build:

```sh
cd scidvspc
./configure BINDIR=$PWD/../build-install/bin SHAREDIR=$PWD/../build-install/share/scid
make -j$(nproc)
make install
```

## 3. Running

```sh
build-install/bin/scid                     # empty database (clipbase)
build-install/bin/scid my_database.pgn     # opens a PGN file or a .si4 database
```

Personal settings are in `~/.scidvspc/` (options, engines).
To add Stockfish: menu **Tools › Analysis Engines › New**, command
`/usr/games/stockfish`, check UCI. WDL is then enabled automatically.

## 4. What is where

| Path | Contents |
|---|---|
| `scidvspc/` | Code of SCID vs. PC 4.27 (GPL v2), imported as is, then modified |
| `scidvspc/tcl/moderne/` | **Our additions**: theme (`theme.tcl`), pieces (`cburnett.tcl`, generated), WDL (`wdl.tcl`) |
| `scidvspc/bitmaps/cburnett/` | Original SVGs of the cburnett pieces + credits |
| `outils/compiler.sh` | Build + local installation |
| `outils/generer_pieces.sh` | Regenerates `tcl/moderne/cburnett.tcl` from the SVGs |
| `outils/captures/` | Automatic screenshots under Xvfb |
| `captures/` | Before / after screenshots |

The changes made in the original files are all marked with a
`Siby` comment (`grep -rn "Siby" scidvspc/tcl`). The executable `scid`
file is the concatenation of the Tcl files listed in
`scidvspc/Makefile.conf` (variable `TCLS`): after any change to a
`.tcl` file, run `outils/compiler.sh` again.

## 5. Screenshots (Xvfb)

```sh
sudo apt-get install -y xvfb imagemagick
outils/captures/capturer.sh captures/apres-sombre
THEME=clair outils/captures/capturer.sh captures/apres-clair
# original version: build the import commit in another folder, then
outils/captures/capturer.sh captures/avant /path/to/scid-original/bin/scid
```

The script starts a virtual display and a blank configuration, opens the game
Kasparov–Topalov (Wijk aan Zee 1999) before 24.Rxd4!!, starts Stockfish, then
takes screenshots of the board, the analysis, the PGN, the game list, the tree and
the board settings dialog.

## 6. Going back to the original look

Menu **Options › Appearance (Theme)** › "Original Scid vs. PC look", then
restart. Pieces and board colors are changed in
**Options › Chessboard/Pieces**; a row of Lichess palettes has been added there.

## Windows version (64-bit)

Built from Linux by cross-compilation (MinGW-w64), without installing
anything on Windows:

```
sudo apt install mingw-w64 zip      # plus wine64 for testing
outils/windows/construire.sh        # → dist/Siby-windows-x64.zip
```

The script downloads and builds Tcl/Tk 8.6.14 for Windows once
(in `build-windows/`), builds SCID with `scidvspc/Makefile.mingw`, then
assembles a portable folder: `Siby.exe` (a launcher without console window, outils/windows/lanceur.c), `bin\Siby.exe` and the
SCID files, `lib\` (Tcl/Tk), `README.txt`, `COPYING.txt`. The only
dependencies are `tcl86.dll`, `tk86.dll`, `zlib1.dll` (included).

Windows-specific issues handled:
- `Siby.exe` reads `scid.gui` as UTF-8 (`-encoding utf-8` added by
  `src/tkscid.cpp`), otherwise the accented characters of the interface would be broken;
- English by default, French can be chosen in **Options › Language**; fonts
  Segoe UI / Consolas;
- no `engines.dat` shipped: Scidlet by default, Stockfish and Leela
  looked for in `bin\engines`, the home folder, Downloads,
  Program Files…;
- fix for a `return` at the top level of `tcl/tools/analysis.tcl`
  that stopped the whole loading of SCID on the first startup on Windows.

Tested under Wine (Xvfb): French interface, dark theme, ultrabase
open, partial search and tree working, Stockfish detected.
