###
### Siby: annotating a game (Tools › Annotate the game). Method from Oracle
### (github.com/Yosha87/Oracle, MIT, by Yosha Iglesias).
###
### With Toby (the default when it is configured), Toby alone: for every
### position it gives each plausible move's probability for a player of that
### rating and its expected score at that level (Leela and Maia), and the
### position's expected score for such a player; the loss of a move is the
### best move's expected score minus the played one's; analyses Toby already
### made (game against it, panel) are reused; a few Toby processes share the
### graphics card. Without Toby, below: an engine and Oracle's formula.
###
### For each move of the main line (or of a range of moves):
###   - an engine (Stockfish, as on Lichess; Leela only without it) evaluates every
###     position with its two best moves (MultiPV 2);
###   - winning chances by rating (expected score, ES):
###       coefficient = rating × −0.00000274 + 0.00048
###       ES = 100 × (0.5 + 0.5 × (2 / (1 + e^(coefficient × cp)) − 1))
###     cp clamped to ±2000, a mate counts ±10000;
###   - errors: drop of the expected score (Toby's formula, at the average
###     rating of the game's players) between the best move and the move
###     played: 5 or more ?!, 10 ?, 15 ?? (Lichess's thresholds);
###   - good moves: the move is within 2 points of the best one, and humans
###     of that level hardly see it (Toby's probability at the game's
###     rating): under 7 % !!, under 30 % !; nothing when Maia's favourite
###     move does at least as well (rules compared on Yosha's annotated
###     games: outils/annotation/comparer_symboles.py);
###   - variations (optional): for each ? and ??, the best move, then the
###     engine's best move as long as it is the only good one (gap of 10
###     points or more to the second best, at the rating of the side to
###     move; 12 moves at most), and the evaluation at the end (=, +=, +/-,
###     +- ...).
### Engines run in their own processes (an engine used by the analysis
### panel is borrowed and given back; see occupation.tcl), one per core for
### a CPU engine, the positions shared among them; the board is not moved.
###

namespace eval ::moderne::oracle {
  variable form
  array set form {}
  variable memo             ;# memo(key) = an engine search's lines, this session (cleMemo)
  array set memo {}
  variable memoRepris 0     ;# searches taken back from the memory (tests)
  variable etat idle        ;# idle | moteur | variantes | initToby | toby | fini
  variable pipe {}
  variable positions {}     ;# list of {fen uci san side}
  variable evals            ;# evals(i) = {cpWhite bestUci cp2White secondUci}
  array set evals {}
  variable toby             ;# toby(i) = {es probs}
  array set toby {}
  variable variantes        ;# variantes(i) = {ucis cpWhiteAtTheEnd}
  array set variantes {}
  variable file {}
  variable courant -1
  variable tobyBloc {}
  variable pool {}          ;# engine processes: tpipe(w), tetat(w) init|libre|occupe,
  variable enCours 0        ;#   tjob(w) {eval i} or {var i ucis}, tlignes(w) multipv -> {type value move}
  array set tpipe {}
  variable mode uci         ;# uci: the engine judges, Toby (Maia) gives the probabilities
  variable scores           ;# scores(i) = dict uci -> cp (White) of the moves searched at i
  array set scores {}
  variable jouesFaits 0     ;# moves played outside the engine's best ones: searched
  variable tdata            ;# tdata(i) = Toby at position i: {es <0-1> moves {uci {prob maia es}}}
  array set tdata {}
  variable seuilUnique 10   ;# gap (ES points) for an only good move
  variable tdist            ;# tdist(i) = Toby's probabilities at i, game's rating (dict uci -> p), from the review
  array set tdist {}
  variable occasionSeuil 10 ;# chance: the best move at least this far (ES points) above what Toby expects
  variable maxVariante 12
  variable nbToby 4     ;# at most (cores - 1 below that): Toby processes on a whole game
}

proc ::moderne::oracle::T {fr en} { return [::moderne::tr $fr $en] }

### Winning chances (expected score) for the side the cp are given for:
### cp clamped to ±2000, mates (±10000) are not
proc ::moderne::oracle::gain {elo cp} {
  if {abs($cp) < 10000} { set cp [expr {max(-2000, min(2000, $cp))}] }
  set k [expr {$elo * -0.00000274 + 0.00048}]
  return [expr {100.0 * (0.5 + 0.5 * (2.0 / (1.0 + exp($k * $cp)) - 1.0))}]
}

### Rating at which the mistakes are judged: the average of the players'
### ratings (header), the one given if only one is, else 2000 (classical);
### Toby's formula takes a rating only, the time control just picks which
### one the header gives
proc ::moderne::oracle::eloPartie {} {
  set l {}
  foreach t {WhiteElo BlackElo} {
    set v {}
    catch {set v [sc_game tags get $t]}
    if {[string is integer -strict $v] && $v > 0} { lappend l $v }
  }
  if {![llength $l]} { return 2000 }
  return [expr {round(([tcl::mathop::+ {*}$l]) / double([llength $l]))}]
}

### Error symbol: drop of the expected score (Toby's formula, at rating elo)
### between the best move and the move played (mover's point of view, cp):
### 5 points ?! (inaccuracy), 10 ? (mistake), 15 ?? (blunder), Lichess's
### thresholds. Yosha's choice (2026-10-27): the game's average rating
### rather than Lichess's single curve, which was too lenient for strong
### players (on her annotated games, 82 % of her ?? found at 2300 against
### 66 %: outils/annotation/comparer_symboles.py).
proc ::moderne::oracle::symboleErreur {elo cpAvant cpApres} {
  set d [expr {[gain $elo $cpAvant] - [gain $elo $cpApres]}]
  if {$d >= 15} { return ?? }
  if {$d >= 10} { return ? }
  if {$d >= 5} { return ?! }
  return {}
}

### Good move symbol: a good move humans of that level hardly see. The move
### loses at most 2 points against the best one, and Maia's probability of
### the move (0-100, at the player's rating) is low: under 7 % "!!", under
### 30 % "!" (and the caller checks that Maia's favourite move is not at
### least as good). No other rule: compared on Yosha's annotated games
### (outils/annotation/comparer_symboles.py), Maia's surprise is the closest
### to her symbols, and the hand-made rules (sacrifices, only good move,
### nothing in a decided game) did not help.
proc ::moderne::oracle::bonCoupSurprise {perte prob} {
  if {$perte > 2 || $prob eq {}} { return {} }
  if {$prob < 7} { return !! }
  if {$prob < 30} { return ! }
  return {}
}

### Good moves (Yosha's rule, 2026-10-29, checked on her annotated games:
### 7 of 10 symbols agree with hers). The move played is the engine's best,
### ahead of the second best by at least 5 expected-score points (at the
### player's rating), and Maia (raw, at the player's rating) gives it less
### than a limit that grows with the gap: 5 % at 5 points, 2 % more per point,
### at most 50 % (reached at 27.5 points): "!". It is "!!" (a puzzle's first
### move) when it is ahead by at least 25 points, Maia gives it less than
### 10 %, and it is the only move that wins (at least 70 after it, not with
### the second best) or the only one that saves the game (at least 40 after
### it, at most 25 with the second best). maia: Maia's probability of the
### move played (0-100), {} unknown.
namespace eval ::moderne::oracle {
  variable bonEcart 5       ;# ES points ahead of the second best: !
  variable bonMaia 5        ;# Maia limit (%) at that gap...
  variable bonPente 2       ;# ...plus this per point of gap...
  variable bonPlafond 50    ;# ...at most this
  variable brillantEcart 25 ;# !!
  variable brillantMaia 10
  variable gagne 70         ;# winning after the move (!! as the only winning move)
  variable tient 40         ;# holding (!! as the only saving move)...
  variable perdu 25         ;# ...when the second best loses
}
### Candidate for a good move (best move, far enough ahead): Maia is asked
proc ::moderne::oracle::candidatBon {i} {
  variable bonEcart
  # (a sacrifice: Toby's probabilities wanted too, for "without this move")
  if {![catch {candidatSacrifice $i} c] && $c} { return 1 }
  set e [ecartMeilleur $i]
  if {$e ne {} && [lindex $e 0] >= $bonEcart} { return 1 }
  # (the move played is not the best: the best one may start the variation
  # of a mistake and get its own "!", Yosha 2026-11-04)
  variable evals
  if {![info exists evals($i)]} { return 0 }
  set e [ecartMeilleur $i [lindex $evals($i) 1]]
  return [expr {$e ne {} && [lindex $e 0] >= $bonEcart}]
}
### {gap esBest esSecond} of ply i when the move played is the engine's best
### (side to move's point of view, at the player's rating), {} otherwise
proc ::moderne::oracle::ecartMeilleur {i {coup {}}} {
  variable evals
  variable positions
  variable form
  if {![info exists evals($i)]} { return {} }
  lassign $evals($i) cp1 u1 cp2 u2
  # (coup: another move than the one played, the first of a variation)
  if {$coup eq {}} { set coup [lindex $positions $i 1] }
  if {$u1 ne $coup || $u2 eq {} || ![string is double -strict $cp2]} { return {} }
  set side [lindex $positions $i 3]
  set elo [expr {$side eq "white" ? $form(eloB) : $form(eloN)}]
  if {$side eq "black"} { set cp1 [expr {-$cp1}] ; set cp2 [expr {-$cp2}] }
  set e1 [gain $elo $cp1] ; set e2 [gain $elo $cp2]
  return [list [expr {$e1 - $e2}] $e1 $e2]
}
proc ::moderne::oracle::bonCoupPuzzle {i maia {coup {}}} {
  foreach v {bonEcart bonMaia bonPente bonPlafond brillantEcart brillantMaia gagne tient perdu} { variable $v }
  if {$maia eq {}} { return {} }
  set e [ecartMeilleur $i $coup]
  if {$e eq {}} { return {} }
  lassign $e ecart e1 e2
  if {$ecart >= $brillantEcart && $maia < $brillantMaia &&
      (($e1 >= $gagne && $e2 < $gagne) || ($e1 >= $tient && $e2 <= $perdu))} { return !! }
  set limite [expr {min($bonPlafond, $bonMaia + $bonPente * ($ecart - $bonEcart))}]
  if {$ecart >= $bonEcart && $maia < $limite} { return ! }
  return {}
}

################################################################################
### Sacrifices (Yosha 2026-11-06, after chess.com's "Brilliant"): a good
### move that gives up a piece. After the move, the opponent's best line of
### captures (each side taking its best capture or stopping) leaves the mover
### with less material and takes one of its pieces (knight or more: pawns
### alone are gambits, a trade taken back is no loss). Or a promotion to
### less than a queen when the queen does clearly worse. It is "!!" from 5
### points given up (pawn 1, knight and bishop 3, rook 5, queen 9; a knight
### or bishop promoted instead of a queen: 6), "!" below. Only when the move
### is the best or nearly (2 points), leaves at least 50 %, and the position
### was not completely winning without it: Toby's other moves at the game's
### rating, their probabilities spread again, under 90 % (Yosha's rule; a
### sacrifice in a won position gets nothing, as on chess.com). No filter on
### Maia: a sacrifice is good even when easy to see (Qb8+ in the Opera game).
### Measured on Yosha's annotated games, outils/annotation/mesurer_bons.py.
################################################################################

namespace eval ::moderne::oracle {
  variable sacrifices   ;# sacrifices(i) = points given up by the move played (cache)
  array set sacrifices {}
}

proc ::moderne::oracle::valeur {p} {
  switch -- [string tolower $p] { p { return 1 } n - b { return 3 } r { return 5 } q { return 9 } }
  return 0
}

### Square number (a1 = 0 … h8 = 63) of "e4"
proc ::moderne::oracle::caseNum {c} {
  expr {([scan [string index $c 0] %c] - 97) + 8 * ([string index $c 1] - 1)}
}

### Best material the side to move wins by captures from fen (it may stop):
### {gain {values taken, in order}}; the game being the scratch one
### (at most 400 positions for one move: a position full of captures froze
### the review for tens of seconds; the biggest captures first)
proc ::moderne::oracle::prises {fen prof} {
  variable noeudsPrises
  if {$prof == 0 || [incr noeudsPrises] > 400} { return [list 0 {}] }
  sc_game startBoard $fen
  set b [sc_pos board]
  set best 0
  set ligne {}
  set liste {}
  foreach u [sc_pos movesUci] {
    set dest [string range $u 2 3]
    set p [string index $b [caseNum $dest]]
    set v [expr {$p ne "." ? [valeur $p] : 0}]
    # (en passant: a pawn going sideways to an empty square)
    if {!$v && [string tolower [string index $b [caseNum [string range $u 0 1]]]] eq "p" &&
        [string index $u 0] ne [string index $u 2]} { set v 1 }
    if {!$v} { continue }
    if {[string length $u] == 5} { incr v [expr {[valeur [string index $u 4]] - 1}] }
    lappend liste [list $v $u]
  }
  foreach x [lsort -integer -decreasing -index 0 $liste] {
    lassign $x v u
    sc_game startBoard $fen
    if {[catch {sc_move addUCI $u}]} { continue }
    set f2 [sc_pos fen]
    lassign [prises $f2 [expr {$prof - 1}]] r suite
    if {$v - $r > $best} { set best [expr {$v - $r}] ; set ligne [concat [list $v] $suite] }
  }
  return [list $best $ligne]
}

### Points the move played at ply i gives up (0: none): a piece sacrificed,
### or a promotion to less than a queen (the queen's value less the piece's)
proc ::moderne::oracle::materielDonne {i} {
  variable sacrifices
  variable positions
  if {[info exists sacrifices($i)]} { return $sacrifices($i) }
  lassign [lindex $positions $i] fen u
  set r 0
  if {[string length $u] == 5 && [string index $u 4] ne "q"} {
    set r [expr {9 - [valeur [string index $u 4]]}]
  } elseif {$u ne {}} {
    sc_game push
    catch {
      sc_game startBoard $fen
      set b [sc_pos board]
      set p [string index $b [caseNum [string range $u 2 3]]]
      set pris [expr {$p ne "." ? [valeur $p] : 0}]
      sc_move addUCI $u
      set f2 [sc_pos fen]
      # (mate: no line of captures)
      if {[llength [sc_pos movesUci]]} {
        variable noeudsPrises 0
        lassign [prises $f2 6] adv ligne
        set piece 0
        set k 0
        foreach v $ligne { if {$k % 2 == 0 && $v >= 3} { set piece 1 } ; incr k }
        set perte [expr {$adv - $pris}]
        if {$perte >= 1 && $piece} { set r $perte }
      }
    }
    sc_game pop
  }
  set sacrifices($i) $r
  return $r
}

### Points given up at ply i if already known, else {} and the search asked
### for: one at a time, when Siby is idle (several at once in a pass of the
### review froze it 2 s)
proc ::moderne::oracle::materielConnu {i} {
  variable sacrifices
  if {[info exists sacrifices($i)]} { return $sacrifices($i) }
  variable aChercher
  if {![info exists aChercher]} { set aChercher {} }
  if {$i ni $aChercher} {
    lappend aChercher $i
    if {[llength $aChercher] == 1} { after idle ::moderne::oracle::chercherSuivant }
  }
  return {}
}
proc ::moderne::oracle::chercherSuivant {} {
  variable aChercher
  variable positions
  if {![llength $aChercher]} { return }
  set i [lindex $aChercher 0]
  set aChercher [lrange $aChercher 1 end]
  if {$i < [llength $positions]} {
    catch {materielDonne $i}
    # (a sacrifice: Toby's probabilities asked as for a good move)
    variable sacrifices
    if {[info exists sacrifices($i)] && $sacrifices($i) >= 1} {
      variable fournisseur
      if {[info exists fournisseur] && $fournisseur ne {}} { catch {::moderne::bilan::demanderBon $i} }
    }
  }
  if {[llength $aChercher]} { after 20 [list after idle ::moderne::oracle::chercherSuivant] }
}

### The engine's best move or nearly (2 ES points), by the searches made
proc ::moderne::oracle::presqueMeilleur {i} {
  variable evals
  variable scores
  variable positions
  variable form
  if {![info exists evals($i)]} { return 0 }
  set joue [lindex $positions $i 1]
  # (the engine's best: enough, even before the other moves' values)
  if {[lindex $evals($i) 1] eq $joue} { return 1 }
  if {![info exists scores($i)] || ![dict exists $scores($i) $joue]} { return 0 }
  set side [lindex $positions $i 3]
  set elo [expr {$side eq "white" ? $form(eloB) : $form(eloN)}]
  set sg [expr {$side eq "black" ? -1 : 1}]
  set best [gain $elo [expr {$sg * [lindex $evals($i) 0]}]]
  return [expr {$best - [gain $elo [expr {$sg * [dict get $scores($i) $joue]}]] <= 2}]
}

### Candidate sacrifice at ply i (the move played gives up material and is
### the best or nearly): Toby's probabilities and a wider search wanted
proc ::moderne::oracle::candidatSacrifice {i} {
  # (the cheap test first: the capture search only for a good move)
  if {![presqueMeilleur $i]} { return 0 }
  set m [materielConnu $i]
  return [expr {$m ne {} && $m >= 1}]
}

### Expected score of the position without the move played: Toby's other
### moves, their probabilities spread again, valued by the engine (a move it
### did not search: as its worst line); {} unknown
proc ::moderne::oracle::sansCeCoup {i} {
  variable scores
  variable tdist
  variable positions
  variable form
  if {![info exists tdist($i)] || ![info exists scores($i)]} { return {} }
  set joue [lindex $positions $i 1]
  set side [lindex $positions $i 3]
  set elo [expr {$side eq "white" ? $form(eloB) : $form(eloN)}]
  set sg [expr {$side eq "black" ? -1 : 1}]
  set pire {}
  dict for {u cp} $scores($i) {
    set e [gain $elo [expr {$sg * $cp}]]
    if {$pire eq {} || $e < $pire} { set pire $e }
  }
  set somme 0.0 ; set total 0.0
  dict for {u p} $tdist($i) {
    if {$u eq $joue || ![string is double -strict $p]} { continue }
    set e [expr {[dict exists $scores($i) $u] ? [gain $elo [expr {$sg * [dict get $scores($i) $u]}]] : $pire}]
    set somme [expr {$somme + $p * $e}]
    set total [expr {$total + $p}]
  }
  if {$total <= 0} { return {} }
  return [expr {$somme / $total}]
}

### "!!", "!" or {} for a sacrifice at ply i
proc ::moderne::oracle::symboleSacrifice {i} {
  variable scores
  variable positions
  variable form
  if {![presqueMeilleur $i]} { return {} }
  set m [materielConnu $i]
  if {$m eq {} || $m < 1} { return {} }
  set joue [lindex $positions $i 1]
  set side [lindex $positions $i 3]
  set elo [expr {$side eq "white" ? $form(eloB) : $form(eloN)}]
  set sg [expr {$side eq "black" ? -1 : 1}]
  set esJoue [gain $elo [expr {$sg * [dict get $scores($i) $joue]}]]
  if {$esJoue < 50} { return {} }
  # (a promotion: only when the queen does clearly worse, 10 points)
  if {[string length $joue] == 5 && [string index $joue 4] ne "q"} {
    set dame "[string range $joue 0 3]q"
    if {![dict exists $scores($i) $dame]} { return {} }
    if {$esJoue - [gain $elo [expr {$sg * [dict get $scores($i) $dame]}]] < 10} { return {} }
  }
  set sans [sansCeCoup $i]
  if {$sans eq {} || $sans >= 90} { return {} }
  return [expr {$m >= 5 ? "!!" : "!"}]
}

### "!" or "!!" on the first move u of a variation at ply i (just added,
### the current move), by the rule of the moves played: the engine's best
### move, far enough ahead of the second, and Maia's probability of it at
### the game's rating (maiaTous: every move, from Toby's "dist"); only the
### first move, the later ones are positions Toby has not seen
proc ::moderne::oracle::symboleVariante {i u} {
  variable maiaTous
  if {![info exists maiaTous($i)] || ![dict exists $maiaTous($i) $u]} { return }
  set s [bonCoupPuzzle $i [expr {100.0 * [dict get $maiaTous($i) $u]}] $u]
  if {$s ne {}} { sc_pos addNag $s }
}

### Error symbol from expected scores: loss (ES points) and the player's ES
### after the move (only when Toby's expected scores are all there is)
proc ::moderne::oracle::symbole {perte {esApres 50}} {
  if {$esApres >= 90} { return {} }
  if {$perte >= 20} { return ?? }
  if {$perte >= 10} { return ? }
  if {$perte >= 5} { return ?! }
  return {}
}

### Evaluation symbol of a position (cp from White's point of view); at
### 2000 the thresholds match SCID's +0.5 / +1.5 / +3.0
proc ::moderne::oracle::symboleEval {elo cpBlancs} {
  return [symboleEs [gain $elo $cpBlancs]]
}

### Evaluation symbol from White's expected score (0-100)
proc ::moderne::oracle::symboleEs {g} {
  if {$g >= 80} { return +- }
  if {$g >= 67} { return +/- }
  if {$g >= 55} { return += }
  if {$g > 45} { return = }
  if {$g > 33} { return =+ }
  if {$g > 20} { return -/+ }
  return -+
}

### Evaluation engine: Stockfish, as on Lichess (Leela at a few hundred
### nodes misses tactical blunders); else any engine that is not Toby,
### Leela last
proc ::moderne::oracle::moteurDefaut {} {
  set toby {}
  foreach t [::moderne::toby::moteursToby] { lappend toby [lindex $t 0] }
  set autre -1 ; set leela -1
  set i 0
  foreach e $::engines(list) {
    set nom "[lindex $e 0] [file tail [lindex $e 1]]"
    # (not the old engines that came with SCID: Scidlet does not answer as
    # the review needs, which then waited forever, seen on Windows
    # 2026-10-31; nor an engine that is not UCI)
    if {[regexp -nocase {^\s*(scidlet|phalanx|toga|fruit)} [lindex $e 0]] || [lindex $e 7] eq "0"} { incr i ; continue }
    if {$i ni $toby} {
      if {[string match -nocase *stockfish* $nom]} { return $i }
      if {[regexp -nocase {lc0|leela} $nom]} {
        if {$leela < 0} { set leela $i }
      } elseif {$autre < 0} { set autre $i }
    }
    incr i
  }
  return [expr {$autre >= 0 ? $autre : $leela}]
}

proc ::moderne::oracle::tobyDefaut {} {
  set t [::moderne::toby::moteursToby]
  return [expr {[llength $t] ? [lindex $t 0 0] : -1}]
}

### Elo of a PGN tag, 2000 if missing
proc ::moderne::oracle::eloTag {tag} {
  set v {}
  catch {set v [sc_game tags get $tag]}
  return [expr {[string is integer -strict $v] && $v > 0 ? $v : 2000}]
}

### Move numbers of the game's first and last moves
proc ::moderne::oracle::bornes {} {
  sc_game push copy
  sc_move start
  set de [lindex [split [sc_pos fen]] 5]
  sc_move end
  set fen [split [sc_pos fen]]
  set a [lindex $fen 5]
  if {[lindex $fen 1] eq "w" && $a > $de} { incr a -1 }
  sc_game pop
  return [list $de $a]
}

################################################################################
### Window (Tools › Annotate the game)
################################################################################

proc ::moderne::oracle::ouvrir {{visible 1}} {
  variable form
  set w .oracleWin
  if {[winfo exists $w]} { raise $w ; return }
  set form(eloB) [eloTag WhiteElo]
  set form(eloN) [eloTag BlackElo]
  if {![info exists form(ms)]} { set form(ms) 500 }
  if {![info exists form(toby)]} { set form(toby) 1 }
  # quick (Stockfish + Maia, a few seconds) or deep (Toby, about one
  # second per position; immediate after a game against Toby, whose
  # analyses are remembered)
  if {![info exists form(precision)]} { set form(precision) rapide }
  if {![info exists form(remplacer)]} { set form(remplacer) 1 }
  if {![info exists form(commentaire)]} { set form(commentaire) 0 }
  # (the chances' comments, "7 in 10 chance of finding it", "Chances taken":
  # no more, Yosha 2026-11-06; the old ones are cleaned from the comments)
  set form(chances) 0
  if {![info exists form(variantes)]} { set form(variantes) 1 }
  lassign [bornes] form(de) form(a)
  set form(cadence) Classical
  catch {
    set c [::moderne::toby::cadenceBilan]
    if {$c in {Classical Rapid Blitz}} { set form(cadence) $c }
  }
  # (the review runs the annotation without any window: none is created,
  # so that nothing can show it)
  if {!$visible} { return }
  toplevel $w
  wm title $w [T "Annoter la partie" "Annotate the game"]
  set f [ttk::frame $w.f -padding 14]
  pack $f -fill both -expand 1
  ttk::label $f.intro -wraplength 470 -justify left -text [T \
      "Chaque coup est jugé au niveau des joueur·ses : ?!, ? et ?? selon la perte d'espérance de gain (moteur), ! et !! pour un bon coup difficile à trouver à ce niveau (Toby). Sur chaque erreur, une variante : le meilleur coup, puis la suite tant qu'elle reste forcée pour le camp qui s'est trompé (l'adversaire jouant ses meilleurs coups) ; elle finit sur son dernier coup forcé, avec l'évaluation." \
      "Each move is judged at the players' level: ?!, ? and ?? from the loss of winning chances (engine), ! and !! for a good move hard to find at that level (Toby). On each mistake, a variation: the best move, then the line as long as it stays forced for the side who erred (the opponent playing their best moves); it ends on their last forced move, with the evaluation."]
  catch {::moderne::enBulle $f.intro}
  grid $f.intro - - -sticky w -pady {0 10}
  ttk::label $f.lp -text [T "Coups :" "Moves:"]
  ttk::frame $f.p
  ttk::spinbox $f.p.de -from 1 -to 999 -width 5 -textvariable ::moderne::oracle::form(de)
  ttk::label $f.p.a -text [T " à " " to "]
  ttk::spinbox $f.p.fin -from 1 -to 999 -width 5 -textvariable ::moderne::oracle::form(a)
  pack $f.p.de $f.p.a $f.p.fin -side left
  grid $f.lp $f.p -sticky w -pady 2
  set m [moteurDefaut]
  ttk::label $f.lm -text [T "Moteur d'évaluation :" "Evaluation engine:"]
  ttk::label $f.m -text [expr {$m >= 0 ? [lindex $::engines(list) $m 0] : [T "aucun" "none"]}]
  grid $f.lm $f.m -sticky w -pady 2
  ttk::checkbutton $f.v -variable ::moderne::oracle::form(variantes) -text [T \
      "Variantes sur les erreurs (? et ??)" "Variations on the mistakes (? and ??)"]
  ttk::frame $f.toby
  ttk::label $f.toby.l -text [T "Analyse :" "Analysis:"]
  ttk::radiobutton $f.toby.r -text [T "Rapide" "Quick"] \
      -variable ::moderne::oracle::form(precision) -value rapide
  ttk::radiobutton $f.toby.p -text [T "Poussée" "Deep"] \
      -variable ::moderne::oracle::form(precision) -value precise
  pack $f.toby.l $f.toby.r $f.toby.p -side left -padx {0 8}
  catch {::utils::tooltip::Set $f.toby.r [T \
      "Le moteur évalue chaque coup à profondeur fixe (18), Maia (Toby) donne sa probabilité au niveau des joueur·ses. Quelques secondes." \
      "The engine evaluates each move at a fixed depth (18), Maia (Toby) gives its probability at the players' level. A few seconds."]}
  catch {::utils::tooltip::Set $f.toby.p [T \
      "Même chose, plus profond (24 ; Leela : 4000 nœuds). Une à quelques minutes." \
      "The same, deeper (24; Leela: 4,000 nodes). One to a few minutes."]}

  ttk::checkbutton $f.r -variable ::moderne::oracle::form(remplacer) -text [T \
      "Remplacer les symboles de qualité déjà présents" "Replace the quality symbols already there"]
  ttk::checkbutton $f.com -variable ::moderne::oracle::form(commentaire) -text [T \
      "Ajouter la perte en commentaire (ex. « −12 % »)" "Add the loss as a comment (e.g. \"−12 %\")"]
  grid $f.v - - -sticky w -pady {8 0}
  grid $f.toby - - -sticky w
  grid $f.r - - -sticky w
  grid $f.com - - -sticky w
  ttk::label $f.etat -foreground [::moderne::c texteDoux] -text {}
  grid $f.etat - - -sticky w -pady {10 0}
  ttk::frame $f.btn
  ttk::button $f.btn.go -text [T "Annoter" "Annotate"] -command ::moderne::oracle::lancer
  catch {$f.btn.go configure -style Accent.TButton}
  ttk::button $f.btn.stop -text [T "Arrêter" "Stop"] -command ::moderne::oracle::arreter -state disabled
  ttk::button $f.btn.fermer -text [T "Fermer" "Close"] -command [list destroy $w]
  pack $f.btn.go $f.btn.stop -side left -padx {0 6}
  pack $f.btn.fermer -side right
  grid $f.btn - - -sticky ew -pady {12 0}
  bind $w <Destroy> [list ::moderne::oracle::fermeture %W $w]
  bind $w <Escape> [list $f.btn.fermer invoke]
  catch {::moderne::repeindre $w}
  if {$visible} { catch {placeWinOverParent $w .} }
}

proc ::moderne::oracle::fermeture {widget w} {
  if {$widget ne $w} { return }
  arreter
}

proc ::moderne::oracle::etat {texte} {
  if {[winfo exists .oracleWin.f.etat]} { .oracleWin.f.etat configure -text $texte }
}

### Why the annotation could not start (shown by the game review, whose
### annotation window is hidden); {} once it starts
proc ::moderne::oracle::echec {texte} {
  variable echec $texte
  etat $texte
}

################################################################################
### Run: engine (all positions of the range) and variations on several
### engine processes at once, then Toby
################################################################################

### Is move i (index in positions) in the chosen range?
proc ::moderne::oracle::dansPlage {i} {
  variable positions
  variable form
  set fen [split [lindex $positions $i 0]]
  set n [lindex $fen 5]
  return [expr {$n >= $form(de) && $n <= $form(a)}]
}

proc ::moderne::oracle::lancer {} {
  variable form
  variable positions
  variable evals
  variable toby
  variable variantes
  variable etat
  if {$etat ni {idle fini}} { return }
  variable echec {}
  variable mode
  # Toby alone when it is there: it gives the evaluation of the moves (Leela
  # and Maia at the players' level) and their probability
  # the engine judges the moves (Stockfish, as on Lichess);
  # Toby gives their probability for a player of that rating (Maia); the
  # deep analysis searches longer
  set mode uci
  set m [moteurDefaut]
  if {$m < 0} {
    echec [T "Le bilan a besoin de Stockfish." "The review needs Stockfish."]
    set r [tk_messageBox -type yesno -icon info -title Siby -message [T \
        "Le bilan a besoin de Stockfish, qui n'est pas encore installé.\n\nL'installer maintenant (Outils › Ajouter un moteur, en un clic) ?" \
        "The review needs Stockfish, which is not installed yet.\n\nInstall it now (Tools › Add an engine, in one click)?"]]
    if {$r eq "yes"} { catch {::moderne::ajout::ouvrir} }
    return
  }
  # everything judged at the game's average rating (2000 when unknown): the
  # mistakes, and Maia's probability for the good moves (Yosha's choice,
  # 2026-10-27)
  set form(eloPartie) [eloPartie]
  set form(eloB) $form(eloPartie)
  set form(eloN) $form(eloPartie)
  # the game's real time control (Rapid and Blitz have their own Maia and
  # networks: Classical on a blitz game used the wrong model, Toby's advice
  # 2026-10-29); Classical when unknown
  set form(cadence) Classical
  catch {
    set c [::moderne::toby::cadenceBilan]
    if {$c in {Classical Rapid Blitz}} { set form(cadence) $c }
  }
  foreach k {eloB eloN de a} {
    if {![string is integer -strict $form($k)]} { echec [T "Valeur incorrecte." "Wrong value."] ; return }
  }
  # Positions of the main line (the game is put back as it was)
  set positions {}
  sc_game push copy
  sc_move start
  while {1} {
    set fen [sc_pos fen]
    set side [sc_pos side]
    if {[sc_pos isAt end]} { lappend positions [list $fen {} {} $side] ; break }
    set san [sc_game info nextMove]
    sc_move forward
    lappend positions [list $fen [sc_game info previousMoveUCI] $san $side]
  }
  sc_game pop
  if {[llength $positions] < 2} { echec [T "La partie n'a pas de coups." "The game has no moves."] ; return }
  array unset evals
  variable provisoires
  array unset provisoires
  variable provAttente
  if {[info exists provAttente] && $provAttente ne {}} { after cancel $provAttente }
  set provAttente {}
  array unset toby
  array unset variantes
  variable tdata
  array unset tdata
  variable scores
  array unset scores
  variable tdist
  array unset tdist
  variable sacrifices
  array unset sacrifices
  variable aChercher {}
  variable jouesFaits 0
  if {![demarrerPool $m]} { return }
  # quick analysis: Toby's Maia (probabilities) at the same time as the engine
  variable poolFini 0
  variable tobyFini 1
  variable tobyArret {}
  if {$mode eq "uci" && $form(toby) && [tobyDefaut] >= 0 && [demarrer [tobyDefaut]]} { set tobyFini 0 }
  catch {.oracleWin.f.btn.go configure -state disabled}
  catch {.oracleWin.f.btn.stop configure -state normal}
}

### Number of engine processes: one per core but one (up to 8: a core stays
### free for Siby and the rest of the computer) for a CPU engine, one for
### Leela (graphics card)
proc ::moderne::oracle::nbProcessus {n} {
  variable mode
  variable nbToby
  # Toby: a few processes share the graphics card (measured on an RTX 4090:
  # 3 at once, 0.63 s per position instead of 0.91)
  if {$mode eq "toby"} { return [expr {max(1, min($nbToby, [::moderne::toby::coeurs] - 1))}] }
  set e [lindex $::engines(list) $n]
  if {[regexp -nocase {lc0|leela} "[lindex $e 0] [file tail [lindex $e 1]]"]} { return 1 }
  set c 2
  catch {set c [exec nproc]}
  catch {if {$::tcl_platform(platform) eq "windows"} { set c $::env(NUMBER_OF_PROCESSORS) }}
  if {![string is integer -strict $c] || $c < 1} { set c 2 }
  # (the review: the level of play's Toby works at the same time, with one
  # Stockfish thread: a core left for it too)
  variable fournisseur
  return [taillePool $c]
}

### Engine processes of the annotation's pool: one per core but one; in a
### review, half the cores (Toby, the slower part, gets the rest for Maia:
### the engine pool still ends well before it)
proc ::moderne::oracle::taillePool {{c {}}} {
  if {$c eq {}} { set c [::moderne::toby::coeurs] }
  variable fournisseur
  # (in a review: the cores Toby leaves, niveau::partage)
  if {[info exists fournisseur] && $fournisseur ne {}} {
    if {![catch {set n [dict get [::moderne::niveau::partage] pool]}]} { return [expr {max(1, min(16, $n))}] }
    return [expr {max(1, min(8, $c / 2))}]
  }
  return [expr {max(1, min(8, $c - 1))}]
}

### Starts engine process w of the pool (k processes in all): {} or the error
proc ::moderne::oracle::lancerProcessus {w k} {
  variable pool
  variable moteurN
  set e [lindex $::engines(list) $moteurN]
  set ancien [pwd]
  catch {cd [lindex $e 3]}
  set ok [catch {set p [open "| [list [lindex $e 1]] [lindex $e 2]" r+]} err]
  catch {cd $ancien}
  if {$ok} { return $err }
  ::moderne::prioriteBasse $p
  fconfigure $p -buffering line -blocking 0
  lappend pool $w
  variable tpipe ; set tpipe($w) $p
  variable tetat ; set tetat($w) init
  variable tjob ; set tjob($w) {}
  variable tlignes ; set tlignes($w) {}
  fileevent $p readable [list ::moderne::oracle::lirePool $w]
  envoyerA $w uci
  foreach opt [lindex $e 8] {
    lassign $opt nom val
    if {$nom in {MultiPV UCI_AnalyseMode}} { continue }
    # several processes share the cores and the memory
    if {$k > 1 && $nom in {Threads Hash}} { continue }
    envoyerA $w "setoption name $nom value $val"
  }
  variable mode
  variable form
  if {$mode eq "toby"} {
    # (whole game: several processes with one Stockfish thread each, as
    # calibrated, rather than one process with many threads)
    foreach {nom val} [list Display Full {Rating Source} FIDE {Time Control} $form(cadence) \
                           {Move Model} Auto MultiPV 500 UCI_ShowWDL true Mode Prediction \
                           {Provisional Lines} false {Stockfish Threads} 1] {
      envoyerA $w "setoption name $nom value $val"
    }
  } else {
    if {$k > 1} {
      envoyerA $w "setoption name Threads value 1"
    }
    # (64 MB is plenty for one position's search, and the hash is
    # cleared before each position: a small one clears in no time)
    envoyerA $w "setoption name Hash value 64"
    variable lignesMoteur
    if {![info exists lignesMoteur]} { set lignesMoteur 3 }
    envoyerA $w "setoption name MultiPV value $lignesMoteur"
  }
  envoyerA $w isready
  return {}
}

### The review's level of play is done: its cores go to the annotation,
### n more engine processes while enough work is left (on Yosha's PC the
### level now ends first and the annotation makes the review's length,
### Toby 2026-11-04). Same search per position: the values do not change.
proc ::moderne::oracle::agrandir {n} {
  variable pool
  variable file
  variable etat
  variable mode
  if {$etat ni {moteur variantes} || $mode eq "toby" || $n < 1} { return }
  # (only worth it with several positions left per new process)
  set n [expr {min($n, [llength $file] / 3, 16 - [llength $pool], [::moderne::toby::coeurs] - 1 - [llength $pool])}]
  if {$n < 1} { return }
  set w [expr {[tcl::mathfunc::max -1 {*}$pool] + 1}]
  set k [expr {[llength $pool] + $n}]
  for {set j 0} {$j < $n} {incr j} {
    if {[lancerProcessus [expr {$w + $j}] $k] ne {}} { break }
  }
  catch {::moderne::journal "Siby review: level done, [llength $pool] engine processes for the annotation"}
}

### Starts the engine processes; the jobs: the positions of the range (and
### the one after each move)
proc ::moderne::oracle::demarrerPool {n} {
  variable pool
  variable file
  variable positions
  variable etat
  variable enCours
  if {![::moderne::occupation::prendre $n oracle {::moderne::oracle::arreter}]} {
    echec [T "Annulé : le moteur est utilisé ailleurs." "Cancelled: the engine is used elsewhere."]
    return 0
  }
  variable moteurN $n
  set e [lindex $::engines(list) $n]
  set k [nbProcessus $n]
  set pool {}
  set enCours 0
  for {set w 0} {$w < $k} {incr w} {
    set err [lancerProcessus $w $k]
    if {$err ne {}} {
      if {$w == 0} {
        ::moderne::occupation::liberer $n oracle
        echec "[T "Impossible de lancer le moteur" "Cannot start the engine"] : $err"
        return 0
      }
      break
    }
  }
  set etat moteur
  set file {}
  set nb [llength $positions]
  for {set i 0} {$i < $nb - 1} {incr i} {
    if {![dansPlage $i]} { continue }
    if {[lindex $file end] ne [list eval $i]} { lappend file [list eval $i] }
    lappend file [list eval [expr {$i + 1}]]
  }
  # Toby: the positions it already analyzed (game against it, panel) are
  # reused; in the quick analysis too, where they are judged by Toby
  variable mode
  variable tdata
  variable form
  set reste {}
  foreach job $file {
    set i [lindex $job 1]
    set b [::moderne::toby::analyseConnue [lindex $positions $i 0] $form(eloB) $form(eloN) $form(cadence)]
    if {$b ne {}} { set tdata($i) [blocToby $b] }
    if {$b eq {} || $mode ne "toby"} { lappend reste $job }
  }
  set file $reste
  set ::moderne::oracle::fait 0
  set ::moderne::oracle::total [llength $file]
  # Lichess's cloud from the start of the game, the local engine from the
  # end: they meet somewhere, the opening costs nothing locally
  if {[cloudPossible]} {
    set file [lreverse $file]
    after idle ::moderne::oracle::cloudSuivant
  }
  return 1
}

################################################################################
### Lichess's cloud evaluations (the opening)
################################################################################

### The cloud is used with Stockfish (not Leela, not Toby); SIBY_SANS_CLOUD=1
### turns it off
proc ::moderne::oracle::cloudPossible {} {
  variable mode
  variable moteurN
  variable cloudGen
  if {![info exists cloudGen]} { set cloudGen 0 }
  incr cloudGen
  variable cloudFaits 0
  if {$mode eq "toby"} { return 0 }
  if {[info exists ::env(SIBY_SANS_CLOUD)] && $::env(SIBY_SANS_CLOUD) eq "1"} { return 0 }
  set e [lindex $::engines(list) $moteurN]
  if {[regexp -nocase {lc0|leela} "[lindex $e 0] [file tail [lindex $e 1]]"]} { return 0 }
  return 1
}

### Next position for the cloud: the earliest one still waiting for the
### engine. Stops where the local engine has been (or is), at the first
### position the cloud does not know, or on any error (too many requests, no
### internet): one boundary only, as the cloud's deep evaluations and the
### local ones (1M nodes) can differ in sharp positions
proc ::moderne::oracle::cloudSuivant {} {
  variable file
  variable etat
  variable jouesFaits
  variable positions
  variable cloudGen
  if {$etat ne "moteur" || $jouesFaits} { return }
  set i {}
  foreach job $file {
    lassign $job type j
    if {$type eq "eval" && ($i eq {} || $j < $i)} { set i $j }
  }
  if {$i eq {}} { return }
  # (contiguous: the position before must be done)
  variable evals
  if {$i > 0 && ![info exists evals([expr {$i - 1}])] && [dansPlage [expr {$i - 1}]]} { return }
  set fen [lindex $positions $i 0]
  set url "https://lichess.org/api/cloud-eval?multiPv=3&fen=[string map {{ } %20 / %2F} $fen]"
  ::moderne::direct::lireJson $url [list ::moderne::oracle::cloudRecu $cloudGen $i]
}

proc ::moderne::oracle::cloudRecu {gen i v} {
  variable cloudGen
  variable file
  variable etat
  variable jouesFaits
  if {$gen != $cloudGen || $etat ne "moteur" || $jouesFaits} { return }
  # (the local engine took it meanwhile: they have met)
  set k [lsearch -exact $file [list eval $i]]
  if {$k < 0 || $v eq {}} { return }
  set lignes [cloudLignes $i $v]
  if {$lignes eq {}} { return }
  # (a position no longer balanced: deep and local evaluations differ most
  # there, the local engine takes over)
  if {abs([cpLigne [dict get $lignes 1]]) > 200} { return }
  set file [lreplace $file $k $k]
  variable cloudFaits
  incr cloudFaits
  # (kept for the session, as the engine's searches)
  variable memo
  set memo([cleMemo [list eval $i]]) $lignes
  finiEval $i $lignes
  etat "[T "Évaluation" "Evaluation"] : [incr ::moderne::oracle::fait] / $::moderne::oracle::total"
  after idle ::moderne::oracle::distribuer
  after 50 ::moderne::oracle::cloudSuivant
}

### The cloud's answer as the engine's lines (side to move's point of view,
### as finiEval wants them); {} if too shallow or not 3 lines
proc ::moderne::oracle::cloudLignes {i v} {
  variable positions
  variable form
  set prof [::moderne::json::get $v depth {}]
  # (deeper than the local search: 1M nodes is about depth 22, 5M about 26)
  set min [expr {$form(precision) eq "precise" ? 30 : 24}]
  if {![string is integer -strict $prof] || $prof < $min} { return {} }
  set fen [lindex $positions $i 0]
  set noirs [expr {[lindex $positions $i 3] eq "black"}]
  set lignes {}
  set k 0
  foreach pv [::moderne::json::get $v pvs {}] {
    set uci [lindex [::moderne::json::get $pv moves {}] 0]
    if {![regexp {^[a-h][1-8][a-h][1-8][qrbn]?$} $uci]} { return {} }
    # (Lichess writes castling king-takes-rook: e1h1 is e1g1 for the engine)
    if {[cloudRoi $fen [string range $uci 0 1]]} {
      set uci [string map {e1h1 e1g1 e1a1 e1c1 e8h8 e8g8 e8a8 e8c8} $uci]
    }
    set mat [::moderne::json::get $pv mate {}]
    set cp [::moderne::json::get $pv cp {}]
    if {[string is integer -strict $mat]} {
      set l [list mate [expr {$noirs ? -$mat : $mat}] $uci]
    } elseif {[string is integer -strict $cp]} {
      set l [list cp [expr {$noirs ? -$cp : $cp}] $uci]
    } else {
      return {}
    }
    dict set lignes [incr k] $l
  }
  if {$k < 3} { return {} }
  return $lignes
}

### Is there a king on that square of the FEN?
proc ::moderne::oracle::cloudRoi {fen case} {
  set rangs [split [lindex $fen 0] /]
  set col [expr {[scan [string index $case 0] %c] - 97}]
  set rang [lindex $rangs [expr {8 - [string index $case 1]}]]
  set c 0
  foreach ch [split $rang {}] {
    if {[string is digit $ch]} { incr c $ch ; continue }
    if {$c == $col} { return [expr {$ch in {K k}}] }
    incr c
  }
  return 0
}

proc ::moderne::oracle::envoyerA {w texte} {
  variable tpipe
  if {![info exists tpipe($w)] || $tpipe($w) eq {}} { return }
  catch {puts $tpipe($w) $texte ; flush $tpipe($w)}
}

proc ::moderne::oracle::lirePool {w} {
  variable tpipe
  variable tetat
  variable tlignes
  if {![info exists tpipe($w)] || $tpipe($w) eq {}} { return }
  set p $tpipe($w)
  if {[eof $p]} { fermerPool ; etat [T "Le moteur s'est arrêté." "The engine stopped."] ; arreter ; return }
  while {[info exists tpipe($w)] && $tpipe($w) eq $p && [gets $p l] >= 0} {
    if {$tetat($w) eq "init"} {
      if {$l eq "readyok"} { set tetat($w) libre ; distribuer }
      continue
    }
    variable mode
    if {$mode eq "toby"} {
      ligneToby $w $l
      continue
    }
    if {[string match "info *" $l]} {
      if {[regexp {score (cp|mate) (-?[0-9]+)} $l -> t v] &&
          ![regexp {score (cp|mate) -?[0-9]+ (lower|upper)bound} $l]} {
        set k 1
        regexp { multipv ([0-9]+)} $l -> k
        set c {}
        regexp { pv ([a-h][1-8][a-h][1-8][qrbn]?)} $l -> c
        dict set tlignes($w) $k [list $t $v $c]
      }
    } elseif {[regexp {^bestmove (\S+)} $l -> c]} {
      set lignes $tlignes($w)
      if {![dict exists $lignes 1] && [regexp {^[a-h][1-8][a-h][1-8]} $c]} {
        dict set lignes 1 [list cp 0 $c]
      } elseif {[dict exists $lignes 1] && [lindex [dict get $lignes 1] 2] eq {} &&
                [regexp {^[a-h][1-8][a-h][1-8]} $c]} {
        dict set lignes 1 [lreplace [dict get $lignes 1] 2 2 $c]
      }
      fini $w $lignes
    }
  }
}

### Search limit: a fixed depth (consistent from one position to the next),
### capped in time; Leela: a number of nodes
proc ::moderne::oracle::limite {} {
  variable form
  variable moteurN
  set profond [expr {$form(precision) eq "precise"}]
  set e [lindex $::engines(list) $moteurN]
  if {[regexp -nocase {lc0|leela} "[lindex $e 0] [file tail [lindex $e 1]]"]} {
    return "nodes [expr {$profond ? 4000 : 800}]"
  }
  # (as Lichess: a fixed number of nodes per position, 1 000 000 for an
  # analysis asked for, 5 000 000 for official broadcasts; the level of play
  # was calibrated with the same 1 000 000)
  return "nodes [expr {$profond ? 5000000 : 1000000}]"
}

### Gives a job to each free process; when nothing is left: the variations
### (once), then Toby
proc ::moderne::oracle::distribuer {} {
  variable pool
  variable tetat
  variable tjob
  variable tlignes
  variable file
  variable etat
  variable enCours
  variable positions
  variable form
  if {$etat ni {moteur variantes}} { return }
  # (searches already done this session for the same position, move and
  # settings, e.g. a game reviewed again after more moves: taken back at
  # once, only the new positions searched, Yosha 2026-11-05)
  variable mode
  variable memo
  if {$mode ne "toby"} {
    set reste {}
    set repris 0
    foreach job $file {
      set k [cleMemo $job]
      if {[info exists memo($k)]} { traiter $job $memo($k) ; incr repris } else { lappend reste $job }
    }
    if {$repris} {
      set file $reste
      variable memoRepris
      incr memoRepris $repris
    }
  }
  foreach w $pool {
    if {![llength $file]} { break }
    if {$tetat($w) ne "libre"} { continue }
    set job [lindex $file 0]
    set file [lrange $file 1 end]
    set tetat($w) occupe
    set tjob($w) $job
    set tlignes($w) {}
    incr enCours
    lassign $job type i coups
    set fen [lindex $positions $i 0]
    variable mode
    if {$mode eq "toby"} {
      envoyerA $w "setoption name White Rating value $form(eloB)"
      envoyerA $w "setoption name Black Rating value $form(eloN)"
    } else {
      # (the engine's memory cleared: each position is evaluated the same
      # way whatever was searched before on that process; a review with
      # another split between the processes gave one position a very
      # different evaluation, 2026-11-01)
      envoyerA $w ucinewgame
    }
    if {$type eq "eval"} {
      envoyerA $w [positionUci $i]
      envoyerA $w "go [limite]"
    } elseif {$type eq "alt"} {
      envoyerA $w "setoption name MultiPV value 6"
      envoyerA $w [positionUci $i]
      envoyerA $w "go [limite]"
    } elseif {$type eq "joue"} {
      # the move played, searched from its own position (same depth)
      envoyerA $w [positionUci $i]
      envoyerA $w "go [limite] searchmoves [lindex $positions $i 1]"
    } else {
      envoyerA $w [positionUci $i $coups]
      envoyerA $w "go [limite]"
    }
  }
  if {$enCours || [llength $file]} { return }
  # the moves played that are not among the engine's best: searched alone
  variable jouesFaits
  if {$etat eq "moteur" && !$jouesFaits} {
    set jouesFaits 1
    if {[debutJoues]} { return }
  }
  if {$etat eq "moteur" && $form(variantes) && [debutVariantes]} { return }
  fermerPool
  finMoteur
}

### Engine's answer for process w
### The key of a search in the session's memory: the job (type, move or
### line), the position and the settings (engine, precision)
proc ::moderne::oracle::cleMemo {job} {
  variable positions
  variable form
  lassign $job type i coups
  set u [expr {$type eq "joue" ? [lindex $positions $i 1] : {}}]
  return [list $type [lindex $positions $i 0] $u $coups [moteurDefaut] $form(precision)]
}

### A search's answer used (from the engine, or from the memory)
proc ::moderne::oracle::traiter {job lignes} {
  lassign $job type i coups
  if {$type eq "eval"} {
    finiEval $i $lignes
    etat "[T "Évaluation" "Evaluation"] : [incr ::moderne::oracle::fait] / $::moderne::oracle::total"
  } elseif {$type eq "joue"} {
    finiJoue $i $lignes
  } elseif {$type eq "alt"} {
    finiAlt $i $lignes
  } else {
    finiVariante $i $coups $lignes
  }
}

proc ::moderne::oracle::fini {w lignes} {
  variable tetat
  variable tjob
  variable enCours
  variable etat
  if {$etat ni {moteur variantes}} { return }
  set job $tjob($w)
  set tetat($w) libre
  set tjob($w) {}
  incr enCours -1
  lassign $job type i coups
  variable mode
  # (kept for the session: the same search is not made again)
  if {$mode ne "toby" && $lignes ne {} && [dict exists $lignes 1]} {
    variable memo
    set memo([cleMemo $job]) $lignes
  }
  if {$mode eq "toby"} {
    if {$type eq "eval"} {
      variable tdata
      if {$lignes ne {}} { set tdata($i) $lignes }
      etat "Toby : [incr ::moderne::oracle::fait] / $::moderne::oracle::total"
    } else {
      finiVarianteToby $i $coups $lignes
    }
  } elseif {$type eq "eval"} {
    finiEval $i $lignes
    etat "[T "Évaluation" "Evaluation"] : [incr ::moderne::oracle::fait] / $::moderne::oracle::total"
  } elseif {$type eq "joue"} {
    finiJoue $i $lignes
  } elseif {$type eq "alt"} {
    finiAlt $i $lignes
    # (the process back to its usual number of lines)
    variable lignesMoteur
    envoyerA $w "setoption name MultiPV value [expr {[info exists lignesMoteur] ? $lignesMoteur : 3}]"
  } else {
    finiVariante $i $coups $lignes
  }
  after idle ::moderne::oracle::distribuer
}

proc ::moderne::oracle::finiEval {i lignes} {
  variable evals
  variable positions
  if {![dict exists $lignes 1]} { return }
  set noirs [expr {[lindex $positions $i 3] eq "black"}]
  set l1 [dict get $lignes 1]
  set cp [cpLigne $l1]
  if {[lindex $l1 0] eq "mate" && [lindex $l1 1] == 0} { set cp -10000 }
  set cp2 {}
  set c2 {}
  if {[dict exists $lignes 2]} {
    set cp2 [cpLigne [dict get $lignes 2]]
    set c2 [lindex [dict get $lignes 2] 2]
    if {$noirs} { set cp2 [expr {-$cp2}] }
  }
  if {$noirs} { set cp [expr {-$cp}] }
  set evals($i) [list $cp [lindex $l1 2] $cp2 $c2]
  # (the review: Maia is asked at once for a candidate good move, so that
  # its "!" comes with the mistakes, not after the variations)
  variable fournisseur
  if {[info exists fournisseur] && $fournisseur ne {}} { catch {::moderne::bilan::demanderBon $i} }
  # (the mistakes shown as the evaluations come, once a second at most)
  variable provAttente
  if {![info exists provAttente] || $provAttente eq {}} {
    set provAttente [after 1000 {catch ::moderne::oracle::provisoire}]
  }
  # every move searched (MultiPV), White's point of view
  variable scores
  set scores($i) {}
  dict for {k l} $lignes {
    set c [cpLigne $l]
    if {[lindex $l 0] eq "mate" && [lindex $l 1] == 0} { set c -10000 }
    if {[lindex $l 2] ne {}} { dict set scores($i) [lindex $l 2] [expr {$noirs ? -$c : $c}] }
  }
}

### Moves played that the engine did not list among its best: one search
### each, from the position before the move (searchmoves)
proc ::moderne::oracle::debutJoues {} {
  variable positions
  variable scores
  variable file
  set file {}
  set nb [llength $positions]
  for {set i 0} {$i < $nb - 1} {incr i} {
    if {![dansPlage $i] || ![info exists scores($i)]} { continue }
    set u [lindex $positions $i 1]
    if {$u ne {} && ![dict exists $scores($i) $u]} { lappend file [list joue $i] }
    # (a sacrifice: its position searched wider, 6 lines, for the value of
    # the other moves; a promotion to less than a queen: the queen's too)
    if {![catch {candidatSacrifice $i} c] && $c} { lappend file [list alt $i] }
  }
  if {![llength $file]} { return 0 }
  after idle ::moderne::oracle::distribuer
  return 1
}

proc ::moderne::oracle::finiJoue {i lignes} {
  variable scores
  variable positions
  if {![dict exists $lignes 1]} { return }
  set l1 [dict get $lignes 1]
  set c [cpLigne $l1]
  if {[lindex $l1 0] eq "mate" && [lindex $l1 1] == 0} { set c -10000 }
  if {[lindex $positions $i 3] eq "black"} { set c [expr {-$c}] }
  dict set scores($i) [lindex $positions $i 1] $c
}

### The wider search of a sacrifice: each move's value kept with the others
proc ::moderne::oracle::finiAlt {i lignes} {
  variable scores
  variable positions
  set noirs [expr {[lindex $positions $i 3] eq "black"}]
  dict for {k l} $lignes {
    set c [cpLigne $l]
    if {[lindex $l 0] eq "mate" && [lindex $l 1] == 0} { set c -10000 }
    set u [lindex $l 2]
    if {$u ne {} && ![dict exists $scores($i) $u]} { dict set scores($i) $u [expr {$noirs ? -$c : $c}] }
  }
}

proc ::moderne::oracle::fermerPool {} {
  variable pool
  variable tpipe
  if {![info exists pool]} { return }
  foreach w $pool {
    if {![info exists tpipe($w)] || $tpipe($w) eq {}} { continue }
    set p $tpipe($w)
    set tpipe($w) {}
    catch {fileevent $p readable {}}
    catch {puts $p quit ; flush $p}
    catch {close $p}
  }
  set pool {}
}

### Toby (one process), for the ! and !!
proc ::moderne::oracle::demarrer {n} {
  variable pipe
  variable etat
  variable file
  variable positions
  variable form
  set e [lindex $::engines(list) $n]
  if {![::moderne::occupation::prendre $n oracle {::moderne::oracle::arreter}]} {
    variable tobyArret [T "utilisé ailleurs" "used elsewhere"]
    return 0
  }
  variable tobyN $n
  set ancien [pwd]
  catch {cd [lindex $e 3]}
  # (its error messages too: said in the review if Toby stops)
  set ok [catch {set pipe [open "| [list [lindex $e 1]] [lindex $e 2] 2>@1" r+]} err]
  catch {cd $ancien}
  if {!$ok} { ::moderne::prioriteBasse $pipe }
  variable tobyArret {}
  variable tobyMessages {}
  variable tobyJournal [list "Toby: [lindex $e 1] [lindex $e 2]"]
  variable tobyTemps {}
  if {$ok} {
    set pipe {}
    set tobyArret $err
    ::moderne::occupation::liberer $n oracle
    return 0
  }
  fconfigure $pipe -buffering line -blocking 0
  fileevent $pipe readable ::moderne::oracle::lire
  variable tetatT initToby
  envoyer uci
  foreach opt [lindex $e 8] {
    lassign $opt nom val
    if {$nom in {MultiPV UCI_AnalyseMode}} { continue }
    envoyer "setoption name $nom value $val"
  }
  foreach {nom val} [list Display Full {Rating Source} FIDE {Time Control} $form(cadence) \
                         {Move Model} Auto MultiPV 500 UCI_ShowWDL true Mode Prediction \
                         {Provisional Lines} false] {
    envoyer "setoption name $nom value $val"
  }
  # the review (quick analysis): Toby's Fast precision, its calculator
  # Stockfish instead of Leela, no graphics card. Toby's advice for batch
  # work (2026-10-29): top-1 61.2 % against 61.9 % in Classical, the same in
  # Rapid and Blitz; Leela shared by several Toby processes on a laptop
  # graphics card fell to 161 nodes/s on Yosha's computer
  if {$form(precision) eq "rapide"} { envoyer "setoption name Precision value Fast" }
  envoyer isready
  # (Toby that never gets ready (its networks not loading) is left out too)
  variable tobyGarde [after 90000 ::moderne::oracle::tobyMuet]
  variable tfile {}
  set nb [llength $positions]
  for {set i 0} {$i < $nb - 1} {incr i} {
    if {[dansPlage $i]} { lappend tfile $i }
  }
  variable tobyTotal [llength $tfile]
  variable tobySautes 0
  return 1
}

proc ::moderne::oracle::envoyer {texte} {
  variable pipe
  if {$pipe eq {}} { return }
  journal "> $texte"
  catch {puts $pipe $texte ; flush $pipe}
}

### Timing of Toby's steps for each position (toby_annotation.log): s1 s2
### s3 = its blocks (F = final), c = a complement (a move Leela did not
### explore, 64 nodes), STOP = the 10 s guard, fin = its move; ms since "go"
proc ::moderne::oracle::etapeToby {quoi} {
  variable tobyT0
  variable tobyEtapes
  variable tobyDetail
  variable courant
  if {![info exists tobyT0]} { return }
  if {![info exists tobyEtapes]} { set tobyEtapes {} }
  if {![info exists tobyDetail]} { set tobyDetail {} }
  set t [expr {[clock milliseconds] - $tobyT0}]
  if {$quoi eq "c"} {
    # (the complements counted, only the first and last kept)
    if {[string match "*c*" [lindex $tobyEtapes end]]} {
      lassign [split [lindex $tobyEtapes end] @] k
      set k [expr {[string trimleft $k c] + 1}]
      lset tobyEtapes end "c$k@$t"
      return
    }
    set quoi c1
  }
  lappend tobyEtapes "$quoi@$t"
  if {$quoi eq "fin"} {
    lappend tobyDetail "ply $courant: [join $tobyEtapes { }]"
    set tobyEtapes {}
  }
}

### The first exchanges with Toby during an annotation, kept in
### toby_annotation.log (Siby's folder) when it ends: to see why Toby gave
### no probabilities, if so
proc ::moderne::oracle::journal {ligne} {
  variable tobyJournal
  if {![info exists tobyJournal]} { set tobyJournal {} }
  if {[llength $tobyJournal] < 80} { lappend tobyJournal $ligne }
}

proc ::moderne::oracle::ecrireJournal {} {
  variable tobyJournal
  if {![info exists tobyJournal] || ![llength $tobyJournal]} { return }
  variable tobyTemps
  set resume {}
  if {[info exists tobyTemps] && [llength $tobyTemps]} {
    set t [lsort -integer $tobyTemps]
    set n [llength $t]
    set resume "Toby per position: [expr {$n}] positions, median [lindex $t [expr {$n / 2}]] ms, slowest [lindex $t end] ms, total [expr {[tcl::mathop::+ {*}$t] / 1000.0}] s"
  }
  set tobyTemps {}
  catch {
    variable tobyDetail
    set f [open [file join $::scidUserDir toby_annotation.log] w]
    puts $f "[clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}]"
    if {$resume ne {}} { puts $f $resume }
    variable tobyDetail
    if {[info exists tobyDetail] && [llength $tobyDetail]} {
      puts $f "Steps of each position (ms after go; s1-s3 = blocks, F = final, cN = complements, STOP = 10 s guard):"
      puts $f [join $tobyDetail \n]
      puts $f ""
    }
    puts $f [join $tobyJournal \n]
    close $f
  }
  set tobyJournal {}
  variable tobyDetail {}
}

proc ::moderne::oracle::lire {} {
  variable pipe
  variable etat
  variable tobyBloc
  if {$pipe eq {}} { return }
  variable tetatT
  variable tobyFini
  variable poolFini
  if {[eof $pipe]} {
    # (Toby stopped before the end: its last messages, for the review)
    variable tobyArret
    variable tobyMessages
    set tobyArret [expr {[llength $tobyMessages] ? [lindex $tobyMessages end] : [T "arrêt sans message" "stopped without a message"]}]
    fermerMoteur ; set tobyFini 1
    if {$poolFini} { annoter }
    return
  }
  while {$pipe ne {} && [gets $pipe l] >= 0} {
    journal "< $l"
    # (lines that are not UCI: Toby's messages, the last few kept)
    if {[string trim $l] ne {} && ![regexp {^(info|id|option|bestmove|uciok|readyok)\M} $l]} {
      variable tobyMessages
      set tobyMessages [lrange [lappend tobyMessages [string range [string trim $l] 0 200]] end-2 end]
    }
    if {$tetatT eq "initToby"} {
      if {$l eq "readyok"} { set tetatT toby ; suivante }
      continue
    }
    if {$tetatT eq "complet"} { ligneComplete $l ; continue }
    set mots [split [regsub -all {\s+} [string trim $l] " "] " "]
    if {[string match "info string Toby: checking the moves*" $l]} { etapeToby c }
    if {[lrange $mots 0 2] eq {info string toby}} {
      switch -- [lindex $mots 3] {
        begin    {
          set tobyBloc [dict create final [champ $mots final 0] probs {} es {}]
          etapeToby "s[champ $mots stage ?][expr {[champ $mots final 0] ? "F" : ""}]"
        }
        move     {
          if {$tobyBloc ne {}} {
            # (Toby's probability, Maia corrected: "hard to find" for a
            # player of that rating; Maia's alone if Toby had no time)
            dict set tobyBloc probs [lindex $mots 4] [champ $mots prob [champ $mots maia 0]]
          }
        }
        position { if {$tobyBloc ne {}} { dict set tobyBloc es [champ $mots es {}] } }
      }
    } elseif {[regexp {^bestmove } $l]} {
      variable tobyGarde
      catch {after cancel $tobyGarde}
      # (time of this position, for toby_annotation.log)
      variable tobyT0
      variable tobyTemps
      if {[info exists tobyT0]} { lappend tobyTemps [expr {[clock milliseconds] - $tobyT0}] }
      etapeToby fin
      finiToby
    }
  }
}

################################################################################
### Toby's full analysis of the candidate good moves: Toby's expected scores
### (the move played, the position as humans play it) decide the ! and !!
################################################################################

### Moves that may deserve a ! : no mistake, near the engine's best move,
### not obvious (Maia), and no full Toby analysis known yet
proc ::moderne::oracle::candidats {} {
  variable positions
  variable toby
  variable tdata
  variable evals
  variable form
  set l {}
  set n [llength $positions]
  for {set i 0} {$i < $n - 1} {incr i} {
    if {![dansPlage $i] || [info exists tdata($i)] || ![info exists toby($i)]} { continue }
    lassign [erreur $i] s perte
    # a mistake for Stockfish: Toby confirms it (or not) for this level
    if {$s ne {}} { lappend l $i ; continue }
    if {$perte > 2} { continue }
    lassign $toby($i) - probs
    set joue [lindex $positions $i 1]
    if {![dict exists $probs $joue] || ![string is double -strict [dict get $probs $joue]]} { continue }
    if {[dict get $probs $joue] >= 0.30} { continue }
    # (taking the piece that has just moved there: never a "!")
    if {$i > 0 && [string range [lindex $positions [expr {$i - 1}] 1] 2 3] eq [string range $joue 2 3]} { continue }
    # (Stockfish sees no real gap to the second best move: Toby will not
    # either; 4 points, looser than the 10 of a "!")
    if {[info exists evals($i)]} {
      lassign $evals($i) cp1 u1 cp2 u2
      if {$u1 ne $joue || $cp2 eq {} || ![string is double -strict $cp2]} { continue }
      set side [lindex $positions $i 3]
      set elo [expr {$side eq "white" ? $form(eloB) : $form(eloN)}]
      if {$side eq "black"} { set cp1 [expr {-$cp1}] ; set cp2 [expr {-$cp2}] }
      if {[gain $elo $cp1] - [gain $elo $cp2] < 4} { continue }
    }
    lappend l $i
  }
  return $l
}

proc ::moderne::oracle::passeComplete {} {
  variable pipe
  variable cfile
  variable tetatT
  # the mistakes are known: written into the notation at once (the good
  # moves and the variations come at the end)
  catch provisoire
  # (the review: Toby's probabilities come from the level of play's Toby,
  # one process for both; the review fills toby() then annotates)
  variable fournisseur
  if {$pipe eq {} && [info exists fournisseur] && $fournisseur ne {}} {
    set f $fournisseur
    set fournisseur {}
    uplevel #0 $f
    return
  }
  if {$pipe eq {}} { annoter ; return }
  # the quick analysis (the review) stops here: its pass already has
  # Toby's full answer for every move; the second look at the candidate
  # good moves took minutes, hidden behind "Variations n / n" (2026-10-27)
  variable form
  if {$form(precision) eq "rapide"} { fermerMoteur ; annoter ; return }
  set cfile [candidats]
  if {![llength $cfile]} { fermerMoteur ; annoter ; return }
  set tetatT complet
  etat [T "Toby examine les bons coups possibles…" "Toby looks at the possible good moves…"]
  suivanteComplete
}

proc ::moderne::oracle::suivanteComplete {} {
  variable cfile
  variable courant
  variable tobyBloc
  variable positions
  variable form
  variable etat
  variable garde
  if {$etat ni {moteur variantes toby}} { return }
  if {![llength $cfile]} { fermerMoteur ; annoter ; return }
  set courant [lindex $cfile 0]
  set cfile [lrange $cfile 1 end]
  set tobyBloc {}
  variable arrete 0
  envoyer "setoption name White Rating value $form(eloB)"
  envoyer "setoption name Black Rating value $form(eloN)"
  envoyer [positionUci $courant]
  envoyer "go infinite"
  # (safety: 20 s at most per position)
  catch {after cancel $garde}
  set garde [after 20000 {::moderne::oracle::envoyer stop}]
}

### A line of Toby's full analysis: the final block is kept, then "stop"
proc ::moderne::oracle::ligneComplete {l} {
  variable tobyBloc
  variable courant
  variable tdata
  variable arrete
  variable garde
  set mots [split [regsub -all {\s+} [string trim $l] " "] " "]
  if {[lrange $mots 0 2] eq {info string toby}} {
    switch -- [lindex $mots 3] {
      begin {
        set tobyBloc [dict create final [champ $mots final 0] etape [champ $mots stage 1] moves {} es {}]
      }
      move {
        if {$tobyBloc ne {}} {
          dict set tobyBloc moves [lindex $mots 4] [list [champ $mots prob {}] [champ $mots maia {}] [champ $mots es {}]]
        }
      }
      position { if {$tobyBloc ne {}} { dict set tobyBloc es [champ $mots es {}] } }
      end {
        if {$tobyBloc ne {} && [dict get $tobyBloc final] && [dict get $tobyBloc etape] >= 3 && !$arrete} {
          set tdata($courant) [dict create es [dict get $tobyBloc es] moves [dict get $tobyBloc moves]]
          set arrete 1
          envoyer stop
        }
      }
    }
  } elseif {[regexp {^bestmove } $l]} {
    catch {after cancel $garde}
    after idle ::moderne::oracle::suivanteComplete
  }
}

### Value following word key in a list of words
proc ::moderne::oracle::champ {mots cle defaut} {
  set i [lsearch -exact $mots $cle]
  return [expr {$i >= 0 ? [lindex $mots [expr {$i + 1}]] : $defaut}]
}

### Score of a line for the side to move, in cp (mate ±10000)
proc ::moderne::oracle::cpLigne {ligne} {
  lassign $ligne t v
  if {$t eq "mate"} { return [expr {$v > 0 ? 10000 : -10000}] }
  return $v
}

### Toby's next position
proc ::moderne::oracle::suivante {} {
  variable file
  variable courant
  variable positions
  variable form
  variable etat
  variable tobyBloc
  if {$etat ni {moteur variantes toby}} { return }
  variable tfile
  variable tobyFini
  variable poolFini
  if {![llength $tfile]} {
    # (Toby stays open for the full analysis of the candidate good moves)
    set tobyFini 1
    if {$poolFini} { passeComplete }
    return
  }
  # (Toby's probability only decides the ! and !!: a move that loses more
  # than 2 points, or a mistake, can be neither, so its position is
  # skipped. While the engine still runs (its search of the move played may
  # still lower the loss), only clear losses are skipped. On Yosha's
  # computer Toby took several seconds a position: 15 of 154 done when the
  # engine was over, 2026-10-29)
  while {[llength $tfile] && [tobyInutile [lindex $tfile 0] $poolFini]} {
    set tfile [lrange $tfile 1 end]
    variable tobySautes
    incr tobySautes
  }
  if {![llength $tfile]} {
    set tobyFini 1
    if {$poolFini} { passeComplete }
    return
  }
  set courant [lindex $tfile 0]
  set tfile [lrange $tfile 1 end]
  set tobyBloc {}
  envoyer "setoption name White Rating value $form(eloB)"
  envoyer "setoption name Black Rating value $form(eloN)"
  envoyer [positionUci $courant]
  # no time given: Toby runs its fixed computation and answers by itself
  # when done (Toby's advice, 2026-10-27); 10 s at most per position
  variable tobyT0 [clock milliseconds]
  variable tobyEtapes {}
  variable tobyGarde
  catch {after cancel $tobyGarde}
  # (the engine done, Toby's progress is shown: else the status stays on
  # the last variation)
  if {$poolFini} {
    variable tobyTotal
    etat "Toby : [expr {$tobyTotal - [llength $tfile]}] / $tobyTotal"
  }
  envoyer "go"
  variable tobyGarde [after 10000 ::moderne::oracle::arretToby]
}

### Is Toby's probability useless at ply i? (no ! or !! possible: the move is
### a mistake or loses more than 2 points; final: the engine is done)
proc ::moderne::oracle::tobyInutile {i final} {
  variable evals
  if {![info exists evals($i)] || ![info exists evals([expr {$i + 1}])]} { return 0 }
  lassign [erreur $i] s perte
  if {$final} { return [expr {$s ne {} || $perte > 2}] }
  return [expr {$perte > 8}]
}

### Toby's progress once the engine is done and Toby still runs (the
### review shows it): {done total}, or {} otherwise
proc ::moderne::oracle::tobyProgres {} {
  variable poolFini
  variable tobyFini
  variable tobyTotal
  variable tfile
  variable etat
  if {$etat ni {moteur variantes} || $tobyFini || !$poolFini || ![info exists tobyTotal]} { return {} }
  # (the positions left that Toby will really look at)
  set reste 0
  foreach i $tfile { if {![tobyInutile $i 1]} { incr reste } }
  return [list [expr {$tobyTotal - $reste}] $tobyTotal]
}

### Stops Toby's search of the current position (it then gives its move)
proc ::moderne::oracle::arretToby {} {
  variable tobyGarde
  catch {after cancel $tobyGarde}
  etapeToby STOP
  envoyer stop
  # (Toby must answer at once: silent 15 s more, it is stuck (seen on
  # Windows, 2026-10-29, the review frozen on "Variations n / n"); it is
  # then left out and the review ends without its last probabilities)
  set tobyGarde [after 15000 ::moderne::oracle::tobyMuet]
}

proc ::moderne::oracle::tobyMuet {} {
  variable tobyFini
  variable poolFini
  variable tobyArret
  variable tetatT
  variable etat
  if {$etat ni {moteur variantes}} { fermerMoteur ; return }
  journal "! no answer to stop: Toby left out"
  set tobyArret [T "Toby ne répondait plus" "Toby stopped answering"]
  fermerMoteur
  set tetatT {}
  set tobyFini 1
  if {$poolFini} { passeComplete }
}

### After the engine (and the variations): Toby, or the end
proc ::moderne::oracle::finMoteur {} {
  variable form
  variable moteurN
  variable mode
  variable poolFini
  variable tobyFini
  if {[info exists moteurN]} { ::moderne::occupation::liberer $moteurN oracle }
  set poolFini 1
  # (the probabilities may still be coming)
  if {!$tobyFini} { return }
  passeComplete
}

proc ::moderne::oracle::finiToby {} {
  variable courant
  variable tobyBloc
  variable toby
  if {$courant >= 0 && $tobyBloc ne {}} {
    set toby($courant) [list [dict get $tobyBloc es] [dict get $tobyBloc probs]]
  }
  after idle ::moderne::oracle::suivante
}

################################################################################
### Variations on the mistakes
################################################################################

### Mistakes (? and ??) of the range: one job each (the best move)
proc ::moderne::oracle::debutVariantes {} {
  variable positions
  variable evals
  variable etat
  variable file
  set file {}
  set nb [llength $positions]
  variable mode
  variable tdata
  for {set i 0} {$i < $nb - 1} {incr i} {
    if {![dansPlage $i]} { continue }
    if {$mode eq "toby"} {
      if {![info exists tdata($i)]} { continue }
      lassign [erreurToby $i] s
      set m [lindex [meilleursToby $tdata($i)] 0 0]
    } else {
      if {![info exists evals($i)]} { continue }
      lassign [erreur $i] s
      set m [lindex $evals($i) 1]
    }
    if {$s in {? ??} && $m ni [list {} [lindex $positions $i 1]]} {
      lappend file [list var $i [list $m]]
    }
  }
  if {![llength $file]} { return 0 }
  set etat variantes
  set ::moderne::oracle::fait 0
  set ::moderne::oracle::total [llength $file]
  etat "[T "Variantes" "Variations"] : 0 / $::moderne::oracle::total"
  after idle ::moderne::oracle::distribuer
  return 1
}

### Engine's answer in a variation. The side whose mistake is corrected (the
### hero) plays the variation's moves while each is their only good one;
### the other side always answers with its best move (Yosha, 2026-10-31:
### "forced for the hero, on the villain's best moves"). Otherwise the
### variation ends with the evaluation.
proc ::moderne::oracle::finiVariante {i coups lignes} {
  variable positions
  variable form
  variable variantes
  variable seuilUnique
  variable maxVariante
  variable file
  # side to move after the variation's moves
  set blancs [expr {([lindex $positions $i 3] eq "white") == ([llength $coups] % 2 == 0)}]
  set elo [expr {$blancs ? $form(eloB) : $form(eloN)}]
  set cp1 {}
  set c1 {}
  if {[dict exists $lignes 1]} {
    set l1 [dict get $lignes 1]
    set cp1 [cpLigne $l1]
    if {[lindex $l1 0] eq "mate" && [lindex $l1 1] == 0} { set cp1 -10000 }
    set c1 [lindex $l1 2]
  }
  set unique 0
  # (an odd number of moves: the villain to move, best move always)
  set vilain [expr {[llength $coups] % 2 == 1}]
  if {$c1 ne {}} {
    if {$vilain || ![dict exists $lignes 2]} {
      set unique 1
    } else {
      set cp2 [cpLigne [dict get $lignes 2]]
      set unique [expr {[gain $elo $cp1] - [gain $elo $cp2] >= $seuilUnique}]
    }
  }
  # The evaluation changed along the line (the hero's expected score moved
  # by the threshold or more since the variation's first move): the line
  # stops there, with the new evaluation
  if {$unique && $cp1 ne {}} {
    set heros [expr {[lindex $positions $i 3] eq "white"}]
    set eloH [expr {$heros ? $form(eloB) : $form(eloN)}]
    set esH [gain $eloH [expr {$vilain ? -$cp1 : $cp1}]]
    set unique [garderVariante $i [llength $coups] $esH]
  }
  if {$unique && [llength $coups] < $maxVariante} {
    # (in front of the queue: a started variation is finished first)
    set file [linsert $file 0 [list var $i [concat $coups [list $c1]]]]
    return
  }
  set esB {}
  if {$cp1 ne {}} { set esB [gain $elo [expr {$blancs ? $cp1 : -$cp1}]] }
  # (the line ends on the hero's last forced move, not on the villain's
  # answer: "54.Kxh6 +-", Yosha 2026-10-31; the evaluation after the
  # villain's best answer is that of the position before it)
  if {[llength $coups] > 1 && [llength $coups] % 2 == 0} { set coups [lrange $coups 0 end-1] }
  set variantes($i) [list $coups $esB]
  etat "[T "Variantes" "Variations"] : [incr ::moderne::oracle::fait] / $::moderne::oracle::total"
}

proc ::moderne::oracle::fermerMoteur {} {
  variable pipe
  variable tobyN
  variable tobyGarde
  catch {after cancel $tobyGarde}
  ecrireJournal
  if {$pipe ne {}} {
    catch {fileevent $pipe readable {}}
    catch {puts $pipe quit ; flush $pipe}
    catch {close $pipe}
  }
  set pipe {}
  if {[info exists tobyN]} { ::moderne::occupation::liberer $tobyN oracle ; unset tobyN }
}

proc ::moderne::oracle::arreter {} {
  variable etat
  variable file
  variable moteurN
  set file {}
  variable provAttente
  if {[info exists provAttente] && $provAttente ne {}} { after cancel $provAttente ; set provAttente {} }
  fermerPool
  fermerMoteur
  if {[info exists moteurN]} { ::moderne::occupation::liberer $moteurN oracle }
  if {$etat ni {idle fini}} { etat [T "Arrêté." "Stopped."] }
  set etat idle
  catch {.oracleWin.f.btn.go configure -state normal}
  catch {.oracleWin.f.btn.stop configure -state disabled}
}

################################################################################
### Toby alone: its blocks, mistakes and good moves
################################################################################

### A line of Toby in process w; at bestmove, the last block (the final one
### if any) goes to fini
proc ::moderne::oracle::ligneToby {w l} {
  variable tlignes
  set mots [split [regsub -all {\s+} [string trim $l] " "] " "]
  if {[lrange $mots 0 2] eq {info string toby}} {
    switch -- [lindex $mots 3] {
      begin {
        dict set tlignes($w) cours [dict create final [champ $mots final 0] es {} moves {}]
      }
      move {
        if {![dict exists $tlignes($w) cours]} { return }
        set c [dict get $tlignes($w) cours]
        dict set c moves [lindex $mots 4] [list [champ $mots prob 0] [champ $mots maia 0] [champ $mots es -]]
        dict set tlignes($w) cours $c
      }
      position {
        if {![dict exists $tlignes($w) cours]} { return }
        set c [dict get $tlignes($w) cours]
        dict set c es [champ $mots es {}]
        dict set tlignes($w) cours $c
      }
      end {
        if {![dict exists $tlignes($w) cours]} { return }
        set c [dict get $tlignes($w) cours]
        if {[dict get $c final] || ![dict exists $tlignes($w) final]} { dict set tlignes($w) dernier $c }
        if {[dict get $c final]} { dict set tlignes($w) final 1 }
      }
    }
  } elseif {[regexp {^bestmove } $l]} {
    set b {}
    if {[dict exists $tlignes($w) dernier]} {
      set d [dict get $tlignes($w) dernier]
      set b [dict create es [dict get $d es] moves [dict get $d moves]]
    }
    fini $w $b
  }
}

### Block of the Toby panel (toby.tcl) in the form used here
proc ::moderne::oracle::blocToby {b} {
  set moves {}
  foreach l [dict get $b lignes] {
    dict set moves [dict get $l uci] [list [dict get $l prob] [dict get $l maia] [dict get $l es]]
  }
  set es {}
  catch {set es [dict get $b position es]}
  return [dict create es $es moves $moves]
}

### Moves of a block with an expected score, best first: {{uci es} ...}
### (es from 0 to 100, for the side to move)
proc ::moderne::oracle::meilleursToby {b} {
  set l {}
  dict for {u v} [dict get $b moves] {
    set es [lindex $v 2]
    if {[string is double -strict $es]} { lappend l [list $u [expr {100.0 * $es}]] }
  }
  return [lsort -real -decreasing -index 1 $l]
}

### Expected score (0-100) of the move played at i, for the player: from
### Toby's block of the position, or else from the next position's
proc ::moderne::oracle::esJoueToby {i} {
  variable tdata
  variable positions
  set joue [lindex $positions $i 1]
  if {[info exists tdata($i)] && [dict exists $tdata($i) moves $joue]} {
    set es [lindex [dict get $tdata($i) moves $joue] 2]
    if {[string is double -strict $es]} { return [expr {100.0 * $es}] }
  }
  set j [expr {$i + 1}]
  if {[info exists tdata($j)] && [string is double -strict [dict get $tdata($j) es]]} {
    return [expr {100.0 * (1.0 - [dict get $tdata($j) es])}]
  }
  return {}
}

### Mistake of move i with Toby: {symbol loss ES-after esBefore esPlayed}
proc ::moderne::oracle::erreurToby {i} {
  variable tdata
  if {![info exists tdata($i)]} { return {{} 0 50 50 50} }
  set m [meilleursToby $tdata($i)]
  set esJ [esJoueToby $i]
  if {![llength $m] || $esJ eq {}} { return {{} 0 50 50 50} }
  set esB [lindex $m 0 1]
  set perte [expr {max(0.0, $esB - $esJ)}]
  return [list [symbole $perte $esJ] $perte $esJ $esB $esJ]
}

### Symbol, loss and probability of move i with Toby (board on the position
### before the move)
proc ::moderne::oracle::jugerToby {i} {
  variable tdata
  variable positions
  variable seuilUnique
  lassign [erreurToby $i] s perte esApres esAvant esJoue
  if {$s ne {} || ![info exists tdata($i)]} { return [list $s $perte {}] }
  set joue [lindex $positions $i 1]
  set m [meilleursToby $tdata($i)]
  if {![llength $m] || [esJoueToby $i] eq {}} { return [list {} $perte {}] }
  # probability (Maia's, as in the quick analysis): a move Toby does not
  # even list is very unlikely
  set prob 0.0
  if {[dict exists $tdata($i) moves $joue]} {
    set p [lindex [dict get $tdata($i) moves $joue] 1]
    if {[string is double -strict $p]} { set prob [expr {100.0 * $p}] }
  }
  set s [bonCoupSurprise $perte $prob]
  # (no "!" when Maia's favourite move does at least as well, by Toby)
  if {$s ne {}} {
    set top {} ; set pmax -1 ; set esTop {}
    dict for {u v} [dict get $tdata($i) moves] {
      set p [lindex $v 1]
      if {[string is double -strict $p] && $p > $pmax} { set top $u ; set pmax $p ; set esTop [lindex $v 2] }
    }
    if {$top ne {} && $top ne $joue && [string is double -strict $esTop] && 100.0 * $esTop >= [esJoueToby $i]} { set s {} }
  }
  return [list $s $perte $prob]
}

### Quick analysis: is Toby's analysis of move i known (game against Toby,
### panel)? It is then judged by Toby
proc ::moderne::oracle::tobyConnu {i} {
  variable tdata
  return [expr {[info exists tdata($i)] && [llength [meilleursToby $tdata($i)]] && [esJoueToby $i] ne {}}]
}

### The hero's expected score esH after n moves of variation i: kept from
### the first move; 0 when it has moved by seuilUnique or more since (the
### line is no longer the one that was judged)
proc ::moderne::oracle::garderVariante {i n esH} {
  variable esDepart
  variable seuilUnique
  if {$n <= 1 || ![info exists esDepart($i)]} {
    set esDepart($i) $esH
    return 1
  }
  return [expr {abs($esH - $esDepart($i)) < $seuilUnique}]
}

### Toby's answer in a variation: the same rule as finiVariante
proc ::moderne::oracle::finiVarianteToby {i coups b} {
  variable positions
  variable variantes
  variable seuilUnique
  variable maxVariante
  variable file
  set blancs [expr {([lindex $positions $i 3] eq "white") == ([llength $coups] % 2 == 0)}]
  set m {}
  if {$b ne {}} { set m [meilleursToby $b] }
  # (the villain, an odd number of moves in: best move always; the hero:
  # only their only good move, as in finiVariante)
  set vilain [expr {[llength $coups] % 2 == 1}]
  set unique [expr {[llength $m] && ($vilain || [llength $m] < 2 || [lindex $m 0 1] - [lindex $m 1 1] >= $seuilUnique)}]
  if {$unique && $b ne {} && [string is double -strict [dict get $b es]]} {
    set es [expr {100.0 * [dict get $b es]}]
    set unique [garderVariante $i [llength $coups] [expr {$vilain ? 100.0 - $es : $es}]]
  }
  if {$unique && [llength $coups] < $maxVariante} {
    set file [linsert $file 0 [list var $i [concat $coups [list [lindex $m 0 0]]]]]
    return
  }
  set esB {}
  if {$b ne {} && [string is double -strict [dict get $b es]]} {
    set es [expr {100.0 * [dict get $b es]}]
    set esB [expr {$blancs ? $es : 100.0 - $es}]
  }
  # (ends on the hero's last forced move, as in finiVariante)
  if {[llength $coups] > 1 && [llength $coups] % 2 == 0} { set coups [lrange $coups 0 end-1] }
  set variantes($i) [list $coups $esB]
  etat "[T "Variantes" "Variations"] : [incr ::moderne::oracle::fait] / $::moderne::oracle::total"
}

################################################################################
### The symbols, written into the game
################################################################################

### Mistake of move i: {symbol loss ES-after esBefore esPlayed} (player's
### point of view, at the player's rating)
proc ::moderne::oracle::erreur {i} {
  variable evals
  variable positions
  variable form
  if {![info exists evals($i)] || ![info exists evals([expr {$i + 1}])]} { return {{} 0 50 50 50} }
  lassign $evals($i) avant c1 cp2 c2
  set apres [lindex $evals([expr {$i + 1}]) 0]
  # the move played scored from the same position, at the same depth (two
  # separate searches disagree by a few tens of cp)
  variable scores
  set joue [lindex $positions $i 1]
  if {[info exists scores($i)] && [dict exists $scores($i) $joue]} {
    set apres [dict get $scores($i) $joue]
  }
  set side [lindex $positions $i 3]
  set elo [expr {$side eq "white" ? $form(eloB) : $form(eloN)}]
  if {$side eq "black"} { set avant [expr {-$avant}] ; set apres [expr {-$apres}] }
  set perte [expr {max(0.0, [gain $elo $avant] - [gain $elo $apres])}]
  set esAvant [gain $elo $avant]
  set esJoue [gain $elo $apres]
  # (the symbol at the game's average rating)
  set eloP [expr {[info exists form(eloPartie)] ? $form(eloPartie) : [eloPartie]}]
  return [list [symboleErreur $eloP $avant $apres] $perte $esJoue $esAvant $esJoue]
}

### Does Maia's favourite move (at the player's rating) do at least as well
### as the move played (engine: best move, or a score at least as high)? Then
### the move played is no "!": humans of that level would play as well.
### (On Yosha's annotated games: more of the "!" are hers, as many found.)
proc ::moderne::oracle::maiaVoitMieux {i joue maia} {
  variable evals
  variable scores
  variable positions
  set top {} ; set pmax -1
  dict for {u p} $maia {
    if {[string is double -strict $p] && $p > $pmax} { set top $u ; set pmax $p }
  }
  if {$top eq {} || $top eq $joue} { return 0 }
  if {[info exists evals($i)] && [lindex $evals($i) 1] eq $top} { return 1 }
  if {[info exists scores($i)] && [dict exists $scores($i) $top] && [dict exists $scores($i) $joue]} {
    set d [expr {[dict get $scores($i) $top] - [dict get $scores($i) $joue]}]
    if {[lindex $positions $i 3] eq "black"} { set d [expr {-$d}] }
    return [expr {$d >= 0}]
  }
  return 0
}

### Symbol and loss of move i. The board is on the position before the move
### (for the recapture, the only legal move and the sacrifice).
proc ::moderne::oracle::juger {i} {
  variable evals
  variable toby
  variable positions
  variable form
  variable seuilUnique
  lassign [erreur $i] s perte esApres esAvant esJoue
  if {$s ne {} || ![info exists evals($i)] || ![info exists evals([expr {$i + 1}])]} {
    return [list $s $perte {}]
  }
  set joue [lindex $positions $i 1]
  set side [lindex $positions $i 3]
  set elo [expr {$side eq "white" ? $form(eloB) : $form(eloN)}]
  set prob {}
  set maia {}   ;# Maia's probabilities of the moves {uci p}
  if {[info exists toby($i)]} {
    lassign $toby($i) es maia
  }
  # (or Maia's probabilities in an analysis Toby already made: game, panel)
  variable tdata
  if {(![llength $maia] || ![dict exists $maia $joue]) && [info exists tdata($i)]} {
    set maia {}
    dict for {u v} [dict get $tdata($i) moves] { dict set maia $u [lindex $v 1] }
  }
  if {[dict exists $maia $joue] && [string is double -strict [dict get $maia $joue]]} {
    set prob [expr {100.0 * [dict get $maia $joue]}]
  }
  # (Maia's probability of the move played: given by the review, else
  # Toby's from an analysis)
  variable maiaJoue
  set pm {}
  if {[info exists maiaJoue($i)]} { set pm $maiaJoue($i) } elseif {$prob ne {}} { set pm $prob }
  set s [bonCoupPuzzle $i $pm]
  # (a sacrifice: its own symbol, the higher of the two kept)
  if {$s ne "!!" && ![catch {symboleSacrifice $i} sac] && $sac ne {}} {
    # (a sacrifice that would be "!" and that Maia hardly ever plays, under
    # 10 % at the player's rating: "!!"; the puzzle rule's "!" stay as they
    # are; measured on Yosha's annotated games, Yosha 2026-11-07)
    if {$sac eq "!" && [string is double -strict $pm] && $pm < 10} { set sac !! }
    if {$sac eq "!!" || $s eq {}} { set s $sac }
  }
  # (rarity of the move: the lower, the rarer)
  set prio [expr {$prob eq {} ? 100 : $prob}]
  return [list $s $perte $prio]
}

### The mistakes (?! ? ??) written as soon as the evaluations are there;
### annoter writes the final symbols over them. provisoires(i): the symbol
### written at ply i.
proc ::moderne::oracle::provisoire {} {
  variable positions
  variable provisoires
  variable provAttente {}
  set nb [llength $positions]
  sc_game push copy
  sc_move start
  set symboles {}
  for {set i 0} {$i < $nb - 1} {incr i} {
    set s {}
    if {[dansPlage $i]} { catch {lassign [juger $i] s} }
    lappend symboles $s
    if {[catch {sc_move forward}]} { break }
  }
  sc_game pop
  set loc [sc_pos location]
  set change 0
  sc_move start
  for {set i 0} {$i < $nb - 1} {incr i} {
    if {[catch {sc_move forward}]} { break }
    set s [lindex $symboles $i]
    if {$s ni {! !! ?! ? ??}} { continue }
    # (written during the analysis: a symbol changed since is replaced)
    if {[info exists provisoires($i)]} {
      if {$provisoires($i) eq $s} { continue }
      set autres [lsearch -all -inline -not -exact [sc_pos getNags] $provisoires($i)]
      sc_pos clearNags
      foreach x $autres { if {$x ne "0"} { catch {sc_pos addNag $x} } }
      unset provisoires($i)
      incr change
    }
    if {$s in [sc_pos getNags]} { continue }
    catch {sc_pos addNag $s ; set provisoires($i) $s ; incr change}
  }
  catch {sc_move start ; sc_move forward $loc}
  if {$change} {
    sc_game setaltered 1
    # (only the notation shows the symbols: updateBoard also redrew the
    # board, gave the position again to the engines, the tablebases and the
    # game's information, every second of the review: 0.33 s on Linux,
    # freezes of 3 to 5 s on Windows, night battery 2026-11-06)
    if {[catch {::pgn::Refresh 1}]} { updateBoard -pgn }
  }
}

proc ::moderne::oracle::annoter {} {
  variable positions
  variable form
  variable etat
  variable variantes
  variable provisoires
  # (no early symbol written after the final ones)
  variable provAttente
  if {[info exists provAttente] && $provAttente ne {}} { after cancel $provAttente ; set provAttente {} }
  set qualite {! ? !! ?? !? ?!}
  set compte [dict create]
  set nb [llength $positions]
  # (the choice of variations, if open, is closed: the game changes under
  # it and its grab would hold Siby)
  catch {grab release .variations}
  catch {destroy .variations}
  # 1. the symbols (the board goes through the game)
  sc_game push copy
  sc_move start
  set symboles {}
  for {set i 0} {$i < $nb - 1} {incr i} {
    set s {}
    set perte 0
    if {[dansPlage $i]} { lassign [juger $i] s perte prob }
    lappend symboles [list $s $perte]
    if {[catch {sc_move forward}]} { break }
  }
  sc_game pop
  # (the chances and the best move's SAN, before the game is changed)
  array set occ {}
  if {$form(chances)} {
    for {set i 0} {$i < $nb - 1} {incr i} {
      if {![dansPlage $i]} { continue }
      set o {}
      catch {set o [occasion $i]}
      if {$o eq {}} { continue }
      lassign [lindex $positions $i] fen
      # (the SAN alone, whatever comes around it; "36.0Kh2" was seen,
      # Yosha 2026-11-04)
      set brut [::moderne::syzygy::sanBrut $fen [lindex $o 2]]
      if {![regexp {(O-O-O|O-O|[KQRBN][a-h1-8]?x?[a-h][1-8]|[a-h](?:x[a-h])?[1-8](?:=[QRBN])?)[+#]?} $brut san]} { set san $brut }
      set san [sanTexte $san]
      set n [lindex [split $fen] 5]
      if {![string is integer -strict $n]} { set n [expr {[lindex $positions $i 3] eq "white" ? $i / 2 + 1 : ($i + 1) / 2}] }
      # "36. Kh2", "36... Kh2" (Yosha's choice, 2026-11-04)
      set num [expr {[lindex [split $fen] 1] eq "w" ? "$n. " : "$n... "}]
      set occ($i) [concat $o [list $num$san]]
    }
  }
  # 2. written into the game, with the variations
  sc_game undoPoint
  set loc [sc_pos location]
  sc_move start
  for {set i 0} {$i < $nb - 1} {incr i} {
    if {[catch {sc_move forward}]} { break }
    # (the symbol written early: replaced by the final one)
    if {[info exists provisoires($i)]} {
      set autres [lsearch -all -inline -not -exact [sc_pos getNags] $provisoires($i)]
      sc_pos clearNags
      foreach x $autres { if {$x ne "0"} { catch {sc_pos addNag $x} } }
    }
    if {![dansPlage $i]} { continue }
    lassign [lindex $symboles $i] s perte
    if {$form(remplacer)} {
      set autres {}
      foreach x [sc_pos getNags] { if {$x ni $qualite && $x ne "0"} { lappend autres $x } }
      sc_pos clearNags
      foreach x $autres { catch {sc_pos addNag $x} }
    }
    if {$s ne {}} {
      sc_pos addNag $s
      dict incr compte $s
      if {$form(commentaire) && $s in {?! ? ??}} {
        set c [sc_pos getComment]
        set ajout "−[expr {round($perte)}] %"
        sc_pos setComment [string trim "$c $ajout"]
      }
    }
    if {[info exists variantes($i)] && $s in {? ??}} {
      lassign $variantes($i) coups esB
      sc_move back
      if {[lindex $coups 0] ni [sc_var list UCI]} {
        sc_var create
        if {![catch {sc_move addUCI [lindex $coups 0]}]} {
          catch {symboleVariante $i [lindex $coups 0]}
          if {([llength $coups] == 1 || ![catch {sc_move addUCI [join [lrange $coups 1 end]]}]) && $esB ne {}} {
            catch {sc_pos addNag [symboleEs $esB]}
          }
        }
        sc_var exit
        dict incr compte variantes
      }
      sc_move forward
    }
    # the chance: how often a player of that level finds the move (Toby),
    # after the loss; a missed chance gets its best move as a variation
    set c [nettoyerChances [sc_pos getComment]]
    if {[info exists occ($i)]} {
      lassign $occ($i) k enjeu u1 pj pb san
      if {$k eq "trouvee"} {
        # (said only on a move annotated ! or !!: a chance taken by a move
        # that is not the best gets no comment, Yosha 2026-10-31)
        set t [expr {$s in {! !!} ? [phraseTrouvee $pj 1] : {}}]
        dict incr compte trouvees
      } else {
        set t [phraseManquee $pb $san]
        if {$form(variantes)} {
          sc_move back
          if {$u1 ni [sc_var list UCI]} {
            sc_var create
            if {![catch {sc_move addUCI $u1}]} { catch {symboleVariante $i $u1} }
            sc_var exit
          }
          sc_move forward
        }
      }
      dict incr compte occasions
      dict incr compte "occ[lindex $positions $i 3]"
      if {$k eq "trouvee"} { dict incr compte "tr[lindex $positions $i 3]" }
      if {$t ne {}} {
        # (a full stop after visible text only: the clock times [%clk …]
        # are not shown, ". Well played!", 2026-10-31)
        set vu [string trim [regsub -all {\[%[^\]]*\]} $c {}]]
        if {$vu ne {} && ![string match {*[.!?]} $vu]} { append c . }
        set c [string trim "$c $t"]
      }
    }
    sc_pos setComment $c
  }
  # the summary, on the last move
  if {$form(chances)} {
    catch {
      sc_move end
      set c [nettoyerChances [sc_pos getComment]]
      if {[dict exists $compte occasions]} {
        set r {}
        foreach {cote fr en} {white Blancs White black Noirs Black} {
          set n 0 ; set t 0
          catch {set n [dict get $compte occ$cote]}
          catch {set t [dict get $compte tr$cote]}
          if {$n} { lappend r "[T $fr $en] $t [T sur of] $n" }
        }
        # (no "odds from Toby" sentence: the same in every review)
        set t "[T "Occasions trouvées" "Chances taken"] : [join $r {, }]."
        set vu [string trim [regsub -all {\[%[^\]]*\]} $c {}]]
        if {$vu ne {} && ![string match {*[.!?]} $vu]} { append c . }
        set c [string trim "$c $t"]
      }
      sc_pos setComment $c
    }
  }
  # back where the board was (main line)
  catch {sc_move start ; sc_move forward $loc}
  array unset provisoires
  updateBoard -pgn
  set etat fini
  set r {}
  foreach s {!! ! ?! ? ??} { if {[dict exists $compte $s]} { lappend r "[dict get $compte $s] $s" } }
  if {[dict exists $compte variantes]} {
    set nv [dict get $compte variantes]
    lappend r "$nv [expr {$nv > 1 ? [T variantes variations] : [T variante variation]}]"
  }
  etat "[T "Partie annotée" "Game annotated"] : [expr {[llength $r] ? [join $r {, }] : [T "aucun symbole" "no symbol"]}]."
  catch {.oracleWin.f.btn.go configure -state normal}
  catch {.oracleWin.f.btn.stop configure -state disabled}
}

### A chance at ply i: the engine's best move is at least occasionSeuil
### ES points above what Toby expects from a player of that level (Toby's
### probabilities at the game's rating, the engine's values; the moves the
### engine did not search count as its worst line). Returns {} or
### {trouvee|manquee enjeu bestUci pPlayed pBest}: found when the move
### played is within 2 points of the best, missed from 5 points.
proc ::moderne::oracle::occasion {i} {
  variable evals
  variable scores
  variable tdist
  variable positions
  variable form
  variable occasionSeuil
  if {![info exists evals($i)] || ![info exists tdist($i)] || ![info exists scores($i)]} { return {} }
  set d $tdist($i)
  if {![dict size $d] || ![dict size $scores($i)]} { return {} }
  lassign $evals($i) cp1 u1
  set joue [lindex $positions $i 1]
  set side [lindex $positions $i 3]
  set elo [expr {$side eq "white" ? $form(eloB) : $form(eloN)}]
  set sg [expr {$side eq "black" ? -1 : 1}]
  set es [dict create]
  set pire {}
  dict for {u cp} $scores($i) {
    set e [gain $elo [expr {$sg * $cp}]]
    dict set es $u $e
    if {$pire eq {} || $e < $pire} { set pire $e }
  }
  if {![dict exists $es $u1]} { dict set es $u1 [gain $elo [expr {$sg * $cp1}]] }
  if {![dict exists $es $joue]} { return {} }
  set esBest [dict get $es $u1]
  # (only a move with no equal: another move as good, within the
  # threshold, makes it no chance; 17.cxd3 and Qxd3 equal were "Well
  # played!", Yosha 2026-10-31)
  dict for {u e} $es {
    if {$u ne $u1 && $esBest - $e < $occasionSeuil} { return {} }
  }
  set attendu 0.0
  set somme 0.0
  dict for {u p} $d {
    if {![string is double -strict $p]} { continue }
    set e [expr {[dict exists $es $u] ? [dict get $es $u] : $pire}]
    set attendu [expr {$attendu + $p * $e}]
    set somme [expr {$somme + $p}]
  }
  if {$somme <= 0} { return {} }
  set enjeu [expr {$esBest - $attendu / $somme}]
  if {$enjeu < $occasionSeuil} { return {} }
  set perte [expr {$esBest - [dict get $es $joue]}]
  if {$perte <= 2} {
    set k trouvee
  } elseif {$perte >= 5} {
    set k manquee
  } else {
    return {}
  }
  set pj [expr {[dict exists $d $joue] ? [dict get $d $joue] : 0.0}]
  set pb [expr {[dict exists $d $u1] ? [dict get $d $u1] : 0.0}]
  return [list $k $enjeu $u1 $pj $pb]
}

### "1 chance sur 2", "7 chances sur 10", "1 chance sur 25"… (p: 0-1);
### {} when the move is almost always found
proc ::moderne::oracle::chances {p} {
  if {$p >= 0.95} { return {} }
  if {$p < 0.01} { return [T "Moins de 1 chance sur 100" "Less than a 1 in 100 chance"] }
  if {$p < 0.1} {
    set n [expr {round(1.0 / $p)}]
    return [T "1 chance sur $n" "A 1 in $n chance"]
  }
  set n [expr {max(1, min(9, round(10.0 * $p)))}]
  if {$n == 5} { return [T "1 chance sur 2" "A 1 in 2 chance"] }
  return [T "$n [expr {$n > 1 ? "chances" : "chance"}] sur 10" "A $n in 10 chance"]
}

proc ::moderne::oracle::phraseTrouvee {p symbole} {
  set c [chances $p]
  if {$c eq {}} { return [T "Se trouve presque toujours." "Almost always found."] }
  set t "$c [T "de le trouver." "of finding it."]"
  if {!$symbole} { set t "[T "Bien joué !" "Well played!"] $t" }
  return $t
}

proc ::moderne::oracle::phraseManquee {p san} {
  set c [chances $p]
  if {$c eq {}} { return [T "$san se trouve presque toujours." "$san is almost always found."] }
  return "$c [T "de trouver" "of finding"] $san."
}

### The comment without what an earlier review wrote about the chances
proc ::moderne::oracle::nettoyerChances {c} {
  foreach re {
    {(Bien trouvé\. |Well found\. |Bien joué ! |Well played! |Dommage ! |Pity! )?(Moins de 1 chance sur 100|1 chances? sur \d+|\d+ chances? sur 10|Less than a 1 in 100 chance|A \d+ in \d+ chance) (de le trouver|of finding it|de trouver (?:\d+\.(?:\.\.)? )?[^ ]+|of finding (?:\d+\.(?:\.\.)? )?[^ ]+)\.?}
    {(Se trouve presque toujours|Almost always found)\.}
    {(Dommage ! |Pity! )?(?:\d+\.(?:\.\.)? )?[^ ]+ (se trouve presque toujours|is almost always found)\.}
    {(Occasions trouvées|Chances taken) : [^.]*\.( (Chances de trouver les coups|Odds of finding the moves) : Toby, [^.]*\.)?}
  } {
    regsub -all $re $c {} c
  }
  return [string trim [regsub -all {\s{2,}} $c { }]]
}

### A SAN with the interface's piece letters (D, T, F, C, R in French)
proc ::moderne::oracle::sanTexte {san} {
  if {$san eq {}} { return {} }
  if {[info exists ::language] && [info exists ::transPieces($::language)]} {
    catch {set san [string map $::transPieces($::language) $san]}
  }
  return $san
}

### End Siby

### UCI "position" of the main line's position i with the game's move history
### (Toby's Maia uses the previous positions): the start position, then the
### moves played up to i, then the extra moves
proc ::moderne::oracle::positionUci {i {coups {}}} {
  variable positions
  set historique {}
  for {set k 0} {$k < $i} {incr k} { lappend historique [lindex $positions $k 1] }
  lappend historique {*}$coups
  set p "position fen [lindex $positions 0 0]"
  if {[llength $historique]} { append p " moves [join $historique]" }
  return $p
}
