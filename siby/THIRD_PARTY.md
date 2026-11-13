# Third-party components in Siby

Siby is free software under the GNU General Public License v2 (see
COPYING). It is a fork of SCID vs. PC (Steven Atkinson), itself based on
Scid (Shane Hudson and contributors). It includes or uses:

| Component | Use | Licence |
|---|---|---|
| SCID vs. PC, Scid | the program Siby comes from | GPL v2 |
| Tcl/Tk 8.6 | the interface toolkit (built from its source) | Tcl/Tk licence (BSD-style) |
| zlib | compression | zlib licence |
| Fathom (src/fathom) | Syzygy tablebase probing | MIT |
| libwebp, decoder only (src/webp) | covers of Lichess broadcasts | BSD-3-Clause (see src/webp/COPYING) |
| flag-icons | country flags | MIT |
| cburnett piece set | the default pieces | GPL v2 or later |
| Lichess piece sets (bitmaps/pieces) | other piece sets | see bitmaps/pieces/LISEZMOI.md: GPL v2+, Apache 2.0, AGPL v3+, GPL v3+, MIT, CC BY 4.0 |
| Move sounds (sounds/siby) | knocks of the pieces | CC0 1.0 |

Not included, downloaded on request, each a separate program with its own
licence: Toby (AGPL v3), Stockfish (GPL v3), Leela Chess Zero (GPL v3),
Gaby (games database; its own terms, see gaby.tribychess.org).

Removed from SCID vs. PC: the Nalimov tablebase code (src/egtb, all rights
reserved) and the opening books (books/*.bin, licence unknown).
