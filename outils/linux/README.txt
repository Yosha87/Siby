Siby for Linux (64-bit)
=======================

Siby is free software (GNU GPL v2). The projects it is built on, with
their licences and authors, are listed in Help > Thanks; the licence
texts are in the licences folder.

Installation
------------
Nothing to install: unpack the archive anywhere (for example in your
home folder), then run ./siby from the Siby folder.
To add Siby to your applications menu: ./installer-raccourci.sh

Your files: the settings are in ~/.scidvspc; Gaby and your databases
("My Siby games", "Siby live") in ~/Documents/Siby (the Documents folder
of your session). A new version of Siby replaces none of them. Older
versions kept Gaby and the databases in ~/.scidvspc: they are moved to
~/Documents/Siby on the first start (an item already there is never
replaced).

Tcl/Tk is included. A usual desktop (X11 or Wayland with XWayland) is
all Siby needs.

Engines
-------
Siby looks for Stockfish and Leela on first start, and on request
(Tools > Engines: detect Stockfish and Leela): in Siby's
share/scid/engines folder, your home folder, Downloads, Desktop, and the
usual system folders (/usr/games, /usr/bin, /usr/local/bin).

Syzygy tablebases: a syzygy folder in your home folder (or choose one in
Tools > Tablebases).
