# Triby: what Gaby, Siby and Toby hand each other

Triby is the common project of Yosha Iglesias, in three parts that all end
in "by": Gaby (the games database, repository `ultrabase`), Siby (Scid
Improved By Yosha, this repository) and Toby (the human-like engine,
repository `toby-dev`). This file is the contract
between them. **Whoever changes a shared format updates this file and tells
the other two sessions in the same change.**

## Gaby → Siby

- **Update address**, built into Siby (`::moderne::gaby::urlDefaut`, the
  settings field can change it): `https://gaby.tribychess.org/gaby_manifest.json`
  (Cloudflare R2, bucket `gaby`, private until Yosha connects the domain;
  until then Siby's automatic check fails silently, and a manual check says
  the server is not open yet). All files named in the manifest are relative
  to it, at the bucket root.

### The database
- `gaby.si4 / .sn4 / .sg4`: a SCID 4 database.
- **Custom flags** (owner: Gaby, rules CAD-1..6 in `ultrabase/docs/RULES.md`):
  1 classical, 2 rapid, 3 blitz, 4 correspondence, 5 online (added to the
  cadence, e.g. "35" = online blitz). Labels (8 characters at most), in
  English from v12: "Classic", "Rapid", "Blitz", "Corresp", "Online"; v11
  bases have the French ones ("Classiq", "Rapide", "Blitz", "Corresp",
  "En ligne"), still accepted. A base whose flag 5 is labelled "Online" or
  "En ligne" is a Gaby base (`nsbDrapeauEnLigne`, `src/nsb.h`). Siby shows
  the labels in the interface language (`::moderne::libelleDrapeau`).
  Ready-made searches: "Gaby 1 - Classical.sso" … "Gaby 6 - Over the board
  only.sso".
- **Time control** in Siby (`nsbCadence`, `src/nsb.h`): in a Gaby base the
  flags only; the event name only leaves out non-standard chess
  (simultaneous, blindfold, odds, Chess960...). `sbclassement` lists the
  games whose event name says another cadence ("DESACCORDS"): they go to
  Gaby, whose rules decide.
- **PGN tags** written by Gaby: `GabyId` (stable for a given build),
  `Cadence` (classique / rapide / blitz / correspondance), `ScidFlags`,
  `Online "1"`, `Source` (TWIC / Lichess / Lumbra-sub), `WhiteFideId` /
  `BlackFideId`, `WhiteTitle` / `BlackTitle`, `TimeControl`.
- **Player names**: the FIDE name; exact FIDE namesakes get "(birth year)"
  or "(FIDE id)", e.g. "Rudlof, Jan (1974)". Everything in Siby that matches
  by name (players pack, Alter Ego, gaby.sbc) relies on it.
- **Elo**: Gaby fills over-the-board games without an Elo with the player's
  Elo of the same cadence and month (v12, about 150,000 places; no tag marks
  it). Siby's estimate in brackets (from `gaby.sbc`) is only the fallback.

### Files built with Siby's tools
Gaby builds `sbbiblio` and `sbclassement` from this repository
(`siby/`: `./configure && make sbbiblio sbclassement`) and runs them on
each complete base.
- `gaby.sbl`, `gaby.online.sbl` (opening library), `gaby.sbp` (position
  index): `sbbiblio`, format version `NSB_VERSION` (`src/nsb.h`). A file of
  an older version is rebuilt by Siby. Since version 3, the top games of
  games without ratings rank with the players' estimated ratings from
  `gaby.sbc`: run `sbclassement` **before** `sbbiblio`.
- `gaby.sbc` (historical ratings): `sbclassement`. One line per player and
  year, sorted by name byte by byte:
  `name, year, classical rating, games, margin, fide, birth, rapid rating,
  games, margin, fide, blitz rating, games, margin, fide` (tabs;
  `0 0 0 0` = no game in that cadence that year). Files with only the first
  7 columns are still read.
- **Siby tells Gaby** whenever `NSB_VERSION` or the `.sbc` format changes,
  so Gaby rebuilds the tools before the next complete base.

### The complete zip (big update)
- `gaby_complet_<v>.zip` and `gaby_complet_<v>_sans_sbp.zip`, entries at the
  root: `gaby.si4 .sn4 .sg4 .sbl .online.sbl .sbp .sbc .maj.json` (no
  `.sbp` in the second one; Siby then builds it in the background). Never
  `.ajouts.sbl`: Siby builds those from the daily files.
- `gaby.maj.json` (state file): the first one is written by Gaby inside
  the zip (`base_version` set, the rest empty); Siby updates it afterwards:
  `{base_version, telecharge_le, derniere_maj, derniere_verif, ajoutees,
  appliques [{fichier, date, parties, sha256}]}`.
- The big update replaces every `gaby.*` file of the base at once (the old
  ones are set aside), so an existing `gaby.sbc` always belongs to the
  current complete base: Alter Ego does not recompute it after a daily
  update.

### The manifest and the daily files
- `gaby_manifest.json`:
  - `base {date, version, fichier, lien, octets, sha256}`: the complete zip;
  - `mises_a_jour [{fichier "gaby_maj_YYYY-MM-DD.pgn", date, parties,
    octets, sha256, base_min}]`: 90 days, only files newer than the base;
  - `joueurs {version "YYYY-MM", fichier "gaby_joueurs_YYYY-MM.zip",
    octets, sha256, joueurs, dossier "gaby_joueurs"}`;
  - `drapeaux`: the flag labels.
- Daily files are PGN. Siby checks every sha256 before using a file.
- Every link in the manifest (`base.lien`, `mises_a_jour[].fichier`,
  `joueurs.fichier`, and `sans_sbp.lien` in `gaby_complet_<v>.json`) is a
  plain file name, resolved **relative to the manifest's own URL**
  (`::moderne::gaby::adresseFichier`); a full `https://` link is used as
  is. Only the manifest URL is set in Siby (Options), so the data can move
  host or domain with no Siby update.
- Hosting (decided by Yosha): domain tribychess.org, Gaby's files in a
  Cloudflare R2 bucket, later at
  `https://gaby.tribychess.org/gaby_manifest.json`. Private for now (no
  public address connected), so Siby ships with no default manifest URL
  yet. Gaby uploads with `scripts/publier_r2.py`: the manifest last, never
  before the files it lists, served with `Cache-Control: max-age=300`.

### The players pack
- Built monthly by Gaby (owner of the photos and player cards), read by
  Siby (`tcl/moderne/avatars.tcl`): `gaby_joueurs/` next to `gaby.si4`,
  with `gaby_names.tsv`, `index.txt`, `translit.txt`, `joueurs.jsonl`,
  `photos/<Qid>.png`, `silhouette.png`, `VERSION` (and `refused.json`, the
  photos refused and why, for Gaby's own review: Siby ignores it). Linked by FIDE id and
  display name. The title badges stay in Siby (`bitmaps/avatars/badges`,
  `outils/badges.py`).
- Lighter pack (2026-10-31, manifest keys added; `joueurs` kept for older
  Siby versions):
  - `photos {version, fichier, octets, sha256, dossier "gaby_joueurs"}`:
    the pack without the `fide_*.tsv.gz` files (about 22 MB), downloaded
    again only when `photos.version` changes.
  - `fide {mois, dossier "gaby_fide", complet {fichier, octets, sha256},
    mensuel [{mois, fichier, octets, sha256}, …]}`: `complet` holds the
    four full FIDE files and `MOIS` (about 89 MB, first install or a copy
    older than the first monthly file); `mensuel` lists the last 12
    monthly updates, oldest first, applied in order after the local month:
    `fide_joueurs_modifies.tsv.gz` (replace or insert by fide_id),
    `fide_joueurs_retires.txt` (delete), `fide_historique_mois.tsv.gz` and
    `fide_parcours_mois.tsv.gz` (entries of that month, appended to the
    id's line, f/a/p groups kept in order), `fide_stats_mois.tsv.gz`
    (rows appended), `MOIS`.
  - Siby status: not used yet (planned after the release); Siby still
    reads `joueurs`.

### Official ratings before 2001
- Manifest entry `elo_officiel {version, fichier
  "gaby_elo_officiel_<version>.tsv.gz", octets, sha256, source
  "OlimpBase 1967-2000"}`, rebuilt with each complete base (about 1.6 MB,
  gzip, UTF-8, relative link, sha256 checked).
- Header `nom\tfide_id\tclassements`; one line per player sorted by name,
  names as in `gaby.sn4` (homonym mark included); `fide_id` empty when
  unknown; `classements` = `s1971-07:2760,s1972-07:2785,…` (classical,
  list month, oldest first; the yearly 1969 and 1970 lists written as
  January). 36,867 players.
- From 2001-01, the official ratings come from `fide_historique` (players
  pack), by FIDE id: not repeated here.
- Credit in the UI: "OlimpBase (reconstructed, not ratified by FIDE)".
- Use in Siby (decided by Yosha): official ratings shown as such and used
  as the anchors of the historical curve; the estimate only for years
  without an official rating, shown if its own margin is ≤ 100, or if it
  is framed within 2 years on each side by reliable or official years and
  stays within 100 points of them.
- Version 2026-10b (source "OlimpBase 1971-07 to 2000"): starts with the
  July 1971 list (the earlier lists were Elo's own, not FIDE's, and the
  yearly "-01" months are gone); players linked by OlimpBase's own key;
  FIDE ids FIDE later gave to someone else (about 3 %) left out; 33,596
  players, 88.8 % equal to the Elo written in the games.
- Siby status (2026-11-03): used. Downloaded with the manifest next to
  gaby.si4 (`gaby_elo_officiel.tsv.gz` + `.version`, sha256 checked),
  merged in front of `fide_historique`'s classical lists (by FIDE id, or by
  name when the games carry no id). Player card: one point per list,
  credited "OlimpBase (not ratified by FIDE)", a gap of more than 12
  months drawn as a gap. Alter Ego: the official rating of the year (the
  average of the ratings in force month by month) is Toby's level; the
  estimate only for years without one.

### Namesakes with older players (from the next complete base)
- 2,756 FIDE players whose exact name is also carried by an older player
  without a FIDE id get the birth mark, e.g. "Botvinnik, Mikhail (*1983)";
  the older player keeps the plain name. Same mark format as the FIDE
  namesakes (nothing to change in Siby). The base, gaby.sbc, fide_joueurs
  and the players pack change together, never under a daily file. List:
  ultrabase `config/homonymes_historiques.json`.

## Toby → Siby

The full contract is [`docs/GUI_INTEGRATION.md` in toby-dev](https://github.com/Yosha87/toby-dev/blob/main/docs/GUI_INTEGRATION.md)
(owner: Toby; until Yosha merges it, the current version, with Provisional
Lines and the Calculator options, is on toby-dev's branch
`claude/bold-meitner-p1kije`). What Siby relies on:

- UCI engine "Toby - The Oracle By Yosha"; Siby recognises "Toby" in the
  name (`::moderne::toby::estToby`). Lc0 and the launcher run without a
  console window.
- Options Siby sends: `Display Full`, `White Rating` / `Black Rating`
  (native ratings: Toby converts them itself; there is no `Elo` option),
  `Rating Source` (FIDE for over-the-board games), `Time Control`
  (Classical / Rapid / Blitz), `Move Model Auto`, `MultiPV 500`,
  `UCI_ShowWDL true`, the hidden `Mode` (Prediction in analysis, Human in
  games and Alter Ego), and `Provisional Lines false` for the annotation.
  Siby does not set `Calculator`: Toby's default, `Auto`, is the
  recommended value (Classical with an NVIDIA GPU: Leela + the history
  network; Rapid, Blitz or no NVIDIA GPU: the Stockfish calculator). The
  `info string Toby: ...` line says `calculator Leela|Stockfish`
  (Toby: commit a55d6f2, sealed test v2).
- `Precision` (`Accurate` default, `Fast`; replaces `Calculator`, which
  Toby still accepts): Accurate = Leela calculates, in Classical with an
  NVIDIA GPU, otherwise the same as Fast (so both are the same in Rapid and
  Blitz); Fast = Stockfish calculates, guided by Leela's raw policy (one
  Leela evaluation per move, GPU or CPU), Stockfish alone only when Leela is
  missing or fails (Toby 1.0). Siby sends it to Toby (analysis
  and games); the choice « Précis / Rapide »
  is in Toby's settings, shown only with an NVIDIA card
  (`::moderne::toby::precision`, saved).
- Positions are sent with the move history (`position startpos moves …` or
  `position fen <start> moves …`; `::moderne::toby::positionPartie`,
  `::moderne::oracle::positionUci`): Maia uses the previous positions.
- Output (Display Full): `info string toby begin … / toby move … / toby
  position … / toby end`, the whole table replaced at each end line,
  `final 1` = stable.
- Alter Ego sends the imitated player's rating in the game's time control
  (rapid or blitz columns of `gaby.sbc`, the clock deciding the cadence),
  with the same `Time Control`, `Rating Source` FIDE.

### Likelihood of a move (Elo estimate in Siby)
Siby estimates the level of play of each side from the moves (Bayesian
estimate, `outils/elo_bayes/RESULTS.md`). For that, Toby answers one
non-standard command, after `position ...` (the position before the move,
with the move list: Maia reads the previous positions):

    toby likelihood <uci move> <rating> [<rating> ...]

and replies, without a bestmove:

    info string toby likelihood <uci move> <rating> <probability> ...
    info string toby likelihood end

(or `info string toby likelihood error <reason>` before the end line). It
uses one Stockfish search (300,000 nodes, the network's training budget),
then Maia with the previous positions and the Stockfish network for each
rating, opponent not given, in the current Rating Source and Time Control.
It needs Stockfish next to Toby, even with Calculator = Leela. A `stop`
interrupts it. Siby asks for 5 ratings per move: its current estimate, -600,
-300, +300 and +600 (within 1000..3300).

Toby announces the command in its answer to `uci`, before `uciok`:

    info string toby capabilities likelihood

(more words may follow for later commands). Siby does not require it today.
(Toby: commit 80c9a7c. In Classical, with the fine-tuned Maia installed and
the `Fine-tuned Maia` option on, the default, the likelihood comes from that
Maia and its own network; the answer format is the same.)

### Download from Siby (Tools › Add an engine)
- Siby reads Toby's manifest at a fixed address (`::moderne::ajout::manifesteToby`,
  empty until Toby is published; the hosting is Yosha's decision):
  `{"version": "...", "platforms": {"windows-x64" | "linux-x64": {"core" |
  "maia" | "leela-cuda" | "stockfish": {"url", "sha256", "size"}}}}`.
- With an NVIDIA card (nvidia-smi answers): core + maia + leela-cuda +
  stockfish; otherwise core + maia + stockfish (Toby's `Auto` calculator
  then uses Stockfish). Each archive is checked (sha256) and unpacked
  into Siby's engines folder; the archives hold a `Toby/` folder with
  Toby's layout (`Toby/toby(.exe)`, `nn/`, `maia/`, `lc0/`, `nets/`,
  `stockfish/`). Siby registers `Toby/toby(.exe)` as "Toby - The Oracle By
  Yosha".

## Toby 2's level head in Siby (`toby level`, 2026-11-19)

Engine side: Toby's `docs/SIBY_LEVEL_HEAD.md`. Siby side: `siby/tcl/moderne/niveau.tcl`
(section "Toby 2's level head").

- A Toby that says `info string toby capabilities level` is asked
  `toby level move <uci> [best <cp> played <cp>] cadence <c> [dist <elo>]`
  instead of `toby likelihood`. Without `level`, after
  `info string toby level calibration error …` or `toby level unavailable`,
  Siby uses `toby likelihood` (T5) as before; a game begun with the head is
  then computed again from its first move.
- One method per game, fixed at its first request (`modeJeu`): every move of
  a game comes from the same model. A group whose calibration says
  `use_ea toby1` is computed with T5.
- Calibration lines (`info string toby level calibration model … group …`) are
  read by field name and kept per model and group; nothing of them is
  written in Siby. The calibration a game used is saved with it (a review
  read back needs no running Toby).
- Values: in a review, each move waits until the annotation has valued its
  position, then goes with `best` (Stockfish's best move, 1M nodes, MultiPV 3)
  and `played` (the move played, its own search when it is not among the 3),
  mover's point of view, mates ±10000. Outside a review, after the
  annotation, or for another game: no values, and Toby searches itself.
- `dist <elo>` (the game's rating in a review): the head's distribution gives
  the played move's probability and replaces Maia's for the "!".
- Estimate: each side's S(E), the sum of its curves (PCHIP onto Siby's
  10-point grid), then Toby's formulas: E_A (moves only) by default, E_R
  (with the player's rating) where Siby uses the ratings (over-the-board,
  rated sides). Interval: ±1.96 sd (the tooltip's "within about N points").
- Tests: `niveau_tete` (formulas against Python's figures, a game end to end,
  saved and read back), `niveau_tete_ko` / `niveau_tete_cal` (fallbacks),
  `bilan_tete` (a whole review, every move sent with values),
  `bilan_liste_tete`; the fake Toby speaks it with `TOBY_NIVEAU=1`
  (`outils/toby/toby_factice.py`).

## Gaby → Toby

- Toby's sealed test sources (Lichess 2025-09, TWIC issues 800-899) must
  never be used for training.
- Gaby's sources: TWIC from issue 920 on, Lichess broadcasts only (no rated
  online games), Lumbra. TWIC 800-899 games are likely present through
  Lumbra.
- Copies of one game across sources keep only the best copy's `Source`
  tag; `GabyId` links back to all copies in Gaby's index. So the `Source`
  tag is not a safe filter: filter Gaby's games by their moves against
  the sealed sets before any training use.

## Open points

- Siby could offer the `_sans_sbp` zip on slow connections (saves about
  0.54 GB; Siby builds the index itself).

## Siby releases (tribychess.org)

Siby checks `https://siby.tribychess.org/siby_manifest.json` (root of the
R2 bucket "siby") a little
after start, then every 12 hours (`siby/tcl/moderne/majsiby.tcl`):

```json
{ "version": "1.0.1", "date": "2026-11-15",
  "notes_fr": "Ce qui change…", "notes_en": "What changes…",
  "windows": {"fichier": "Siby-windows-x64.zip", "sha256": "…", "taille": 36000000},
  "linux":   {"fichier": "Siby-linux-x64.tar.gz", "sha256": "…", "taille": 33000000} }
```

- File names are relative to the manifest (or full URLs); `taille` in bytes
  (progress bar), `sha256` of the file (checked before anything changes).
- The packages are the ones built by `outils/windows/construire.sh` and
  `outils/linux/construire.sh`, with a single top folder `Siby/` holding
  `README.txt`.
- Versions compare by number, a tag ("1.0 beta") being older than the same
  number without one. `$::sibyVersion` (`siby/tcl/start.tcl`) must be
  raised for every release.
- Publishing a release: raise `$::sibyVersion`, build both packages, run
  `outils/manifeste_siby.sh "notes FR" "notes EN"` (writes
  `dist/siby_manifest.json` with the sha256 and sizes), upload the two
  packages, then the manifest last.
- Toby follows the same pattern (toby.tribychess.org), see below.

## Toby updates from Siby (Siby 1.0 beta 7)

- Siby reads `https://toby.tribychess.org/toby_manifest.json` a little
  after start, then every 12 hours, and from Help › Check for updates,
  when the registered Toby is one Siby downloaded (its program in a folder
  named `Toby`).
- Installed version: `Toby/siby_toby.txt` (written by Siby: `version
  variant`), else `Toby/VERSION` (Toby's own, one line such as `2.0`),
  else `1.0`. Versions compare by number as Siby's (`2.0` > `1.0`,
  `2.0 beta` < `2.0`).
- A newer `version`: a notice (Update / Later). Update downloads the same
  variant (`full`, `light`, `core`; `full` only with an NVIDIA card), with
  its `sha256` required and checked, unpacks it beside the old Toby
  (`Toby.maj`), and puts it in the old one's place at Siby's next start,
  before any Toby runs. The program's path does not change.
- What Toby's packages must keep: one top folder `Toby/` with
  `toby(.exe)` in it; `id name Toby - The Oracle By Yosha` (Siby names the
  engine from it); a `VERSION` file in `Toby/` is welcome. The manifest
  keeps its format (`version`, `notes_fr`, `notes_en`, `windows` /
  `linux` → `core` / `light` / `full` → `fichier`, `sha256`, `taille`);
  `notes_fr` / `notes_en` are shown in the notice (600 characters at
  most). New file names for each version (the old ones may stay).
