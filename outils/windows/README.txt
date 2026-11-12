Siby for Windows (64-bit)
=========================

Siby is free software (GNU GPL v2). The projects it is built on, with
their licences and authors, are listed in Help > Thanks; the licence
texts are in the licences folder.

Installation
------------
Nothing to install: unzip anywhere (for example in Documents), then
double-click "Siby.exe" (a launcher for bin\Siby.exe; bin\Siby.exe can be pinned to
the taskbar).

On first launch, Windows may show "Windows protected your PC" (unsigned
program): click "More info", then "Run anyway".

Your files
----------
Your settings, your databases ("My Siby games", "Siby live"), your notes,
the engines Siby downloads and Gaby are in Documents\Siby, not in Siby's
folder: to update Siby, unzip the new version (over the old one or
elsewhere) and nothing of yours is replaced. A version older than
2026-11 kept them in Siby's bin folder: the new version, unzipped over
it, moves them to Documents\Siby on its first start (an item already in
Documents\Siby is never replaced).

Uninstalling
------------
Help > Uninstall Siby...: Siby's registrations in Windows (file types,
"Open with") are removed and Siby's folder is deleted once Siby has
closed. Documents\Siby (your databases, settings, notes, Gaby, engines)
is kept: unzip Siby again and everything is there.

Engines
-------
Siby looks for Stockfish and Leela on first start, and on request
(Tools > Engines: detect Stockfish and Leela), in:
  - Siby's bin\engines folder;
  - your home folder, Downloads, Desktop;
  - Program Files, and the stockfish*, lc0*, Leela* folders inside.
Simplest: unzip Stockfish (stockfishchess.org) and Leela (lczero.org;
the CUDA build for an NVIDIA card, with a .pb.gz network next to
lc0.exe) into bin\engines, then use the menu above.

Syzygy tablebases: C:\syzygy, D:\syzygy or a syzygy folder in your home
folder (or choose one in Tools > Tablebases).

Settings
--------
Settings are stored in bin\config. To keep them when updating, copy
bin\config from the old folder into the new one; delete it to go back
to the default settings.
