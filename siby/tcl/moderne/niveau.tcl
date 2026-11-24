###
### niveau.tcl: level of play estimated from the moves (Siby)
###
### For each side of a game, a Bayesian estimate of the rating that best
### explains the moves played (outils/elo_bayes/RESULTS.md):
###   log posterior(E) = log prior(E) + sum over the moves of log p(move | E)
### p(move | E) comes from Toby ("toby likelihood", docs/INTERFACES.md):
### per move, 5 ratings around the current estimate (-600, -300, 0, +300,
### +600), joined by straight lines and extended by the end slopes; on test
### games this stays within about 10 points of the full rating grid.
### Prior: the ratings of over-the-board players for the time control
### (mean and spread of the calibration sample), never the game's own
### ratings: the moves decide (a 2300 who plays badly gets less). The
### posterior mean is then corrected linearly (calibre). Every move counts,
### from move 1 (closer to the real rating than from move 9, 2026-11-02).
### Calibrated on 2,531 games with FIDE
### ratings (outils/niveau/comparer.py) so that it has no bias by level: a
### 1600 gets about 1600 on average, a 2700 about 2700 (the plain posterior
### mean pulls everyone toward the mean, +165 at 1500 and -260 at 2700 in
### rapid). Mean absolute error on one game: about 170 to 180 points (5-fold
### cross validation, from move 1; 180 to 200 from move 9).
###
### Dedicated Toby processes do the work, each on its own moves with one
### Stockfish thread (they do not disturb the analysis panel nor the
### opponent in a game).
###

namespace eval ::moderne::niveau {
  variable pipes            ;# pipes(w) = Toby process w
  array set pipes {}
  variable courants         ;# courants(w) = request being computed by w
  array set courants {}
  variable attentes
  array set attentes {}
  variable numero 0
  variable file {}          ;# requests waiting: {cle cote position uci source cadence}
  variable notes            ;# notes(cle,cote) = log posterior on the grid (list)
  array set notes {}
  variable compte           ;# compte(cle,cote) = moves counted
  array set compte {}
  variable faits            ;# faits(cle) = plies already queued
  array set faits {}
  variable rappels          ;# rappels(cle) = command run after each update
  array set rappels {}
  variable grille {}
  for {set e 1200} {$e <= 3000} {incr e 10} { lappend grille $e }
  # first ply counted: every move from the first one (2026-11-02: on the
  # calibration sample the level is closer to the real rating counting from
  # move 1, mean error 177, than from move 9, 192; the opening chosen says
  # something of the level, and an early blunder counts)
  variable premierCoup 0
  variable minCoups 10      ;# moves counted before an estimate is shown
  # shown ceiling: Toby learned from human games, which stop around 2900;
  # above that it cannot tell levels apart (TCEC engines from 3300 to 3800
  # all came out between 2750 and 3150, 2026-11-01): the number is still
  # computed and saved, but shown as "2900+"
  variable plafond 2900
  variable plafondA 2500    ;# from the moves alone (no rating): "2500+" from here
  variable plancherA 1600   ;# from the moves alone: "under 1600" below
  # floor: the lowest FIDE rating (1400 since 2024) and the bottom of the
  # calibration sample; below it the corrected number means nothing (it
  # could read 250): shown as "1400−"
  variable plancher 1400
  variable gardeMinutes 10  ;# a Toby idle is kept loaded that long (minutes)
  variable sansReponse 0    ;# 1: this Toby does not know "toby likelihood" (older version)
  variable capacites        ;# capacites(w) = Toby's "capabilities" lines (likelihood-dist...)
  array set capacites {}
  variable delai 90000      ;# ms without an answer before giving up (Maia may load first)
  variable total            ;# total(cle) = moves queued for game cle (progress)
  array set total {}
  # per Toby time control: prior {mean sd} and correction {a b} of the
  # posterior mean. Unbiased by level: fit posterior = c + d * rating on the
  # calibration sample, then a = -c/d, b = 1/d (outils/niveau/comparer.py)
  # Toby 1.0 (it says "info string toby version 1.0" at uci): its own
  # calibration (Toby 2026-11-12, same 2,531 games, model T5 on the
  # engine's own Stockfish values, the hash cleared between positions;
  # mean absolute error 185.2 / 185.4 / 173.8); an older Toby keeps the
  # previous one
  variable calibre {
    Classical {2097 415 70.2 0.9701}
    Rapid     {2103 397 -346.3 1.0584}
    Blitz     {2183 380 -506.9 1.1634}
  }
  variable calibreAncien {
    Classical {2097 415 165.0 0.9299}
    Rapid     {2122 412 -401.9 1.077}
    Blitz     {2193 389 -405.2 1.1248}
  }
  # The calibration for Toby's H6b likelihood (Fast with one Leela policy
  # per position, Toby 2026-11-12): used for a game only when every answer
  # of its review said "model H6b"; {} until it is measured
  variable calibreH6b {}
  # Toby 2 ("info string toby version 2.x"): its own calibration and its
  # players' ratings settings, measured with its final weights (Toby
  # session, 2026-11-19); {} until then: Toby 1.0's are used
  variable calibreToby2 {}
  variable priorEloToby2 {}
  # The players' ratings as part of the estimate (Toby session, not adopted
  # yet, 2026-11-12): per place where the game was played (otb, lichess,
  # chesscom) and time control ("otb Classical"...), a dict of:
  #   sdElo s     the side's rating weighs with standard deviation s against
  #               the time control's prior (product of the normal laws);
  #   remplace 1  the prior is N(rating, s) instead (Toby's estimator);
  #   flat 1      a flat prior: the moves only, no shrinkage to the mean;
  #   tau t       the sum of the moves' log-likelihoods divided by t;
  #   brut 1      the posterior mean as it is (no linear correction);
  #   cal {mu sd a b}  else that case's prior and correction;
  #   sansElo {…} the setting used for a side whose rating is missing;
  #   derive {c0 c1 {k1 p1} {k2 p2}…}  the average drift d(r) taken off the
  #               estimate: c0 + c1·r + Σ pi·max(0, r − ki), r the side's
  #               rating clamped to deriveClamp {lo hi}.
  # Empty: ratings unused, as before. Adopted (Yosha 2026-11-12, Toby
  # session's fit on the calibration sample): over-the-board games, prior
  # N(the side's rating, 800), tau 3, the average drift for players of that
  # rating taken off (a player who plays as their rating ends near it;
  # Brier on open games: classical 0.0933, rapid 0.0915, blitz 0.1122).
  # Online games and sides without rating: the calibration lines (the
  # rapid and blitz ones fitted on the FIDE rapid / blitz lists).
  variable priorElo {
    {otb Classical} {remplace 1 sdElo 800 tau 3 brut 1
      derive {531.4751 -0.2509 {1800 0.1425} {2200 -0.1736} {2500 -0.4476}} deriveClamp {1400 2800}}
    {otb Rapid} {remplace 1 sdElo 800 tau 3 brut 1
      derive {267.4409 0.0402 {1800 -0.2853} {2200 -0.2804} {2500 -0.2195}} deriveClamp {1400 2800}}
    {otb Blitz} {remplace 1 sdElo 800 tau 3 brut 1
      derive {633.1739 -0.2009 {1800 0.0436} {2200 -0.4101} {2500 -0.0688}} deriveClamp {1400 2800}}
  }
  variable reglages          ;# reglages(cle,cote): the setting a side's estimate uses
  variable taus              ;# taus(cle,cote): its temperature (1 by default)
  variable modeles          ;# modeles(cle) = the models of the game's answers (H6b, T5)
  variable versionToby {}   ;# version Toby gave at uci ({}: an older Toby)
  variable pause 0          ;# 1: nothing new sent (a game: the engine's turn)
  variable revoir {}        ;# timer: moves waiting for the review's values looked at again
}

### The calibration of the Toby in use
### Siby's background engines (the review's level, Toby in the background,
### the annotation's engines) at low priority on Windows, as the analysis
### panels already are: they use only what the computer leaves free. A
### review running during a Zoom lesson cut the students' sound (Yosha
### 2026-11-11). Their child processes (Toby's Stockfish and lc0) inherit
### it.
proc ::moderne::prioriteBasse {canal} {
  if {!$::windowsOS} { return }
  foreach pid [pid $canal] { catch {sc_info priority $pid idle} }
}

proc ::moderne::niveau::calibration {{cle {}}} {
  variable versionToby
  variable calibre
  variable calibreAncien
  variable calibreH6b
  variable modeles
  # (Toby says which model gave each answer: "info string toby likelihood
  # end model H6b"; a bare "end" is T5, the model of calibre)
  if {$cle ne {} && $calibreH6b ne {} && [info exists modeles($cle)] && $modeles($cle) eq {H6b}} {
    return $calibreH6b
  }
  if {$versionToby eq {}} { return $calibreAncien }
  variable calibreToby2
  if {$calibreToby2 ne {} && [estToby2]} { return $calibreToby2 }
  # (a version that is not a plain number: it exists since 1.0)
  if {[catch {package vcompare $versionToby 1.0} r]} { return $calibre }
  return [expr {$r >= 0 ? $calibre : $calibreAncien}]
}

### Is the Toby in use version 2 or later ("2.0", "2.0 beta"…)?
proc ::moderne::niveau::estToby2 {} {
  variable versionToby
  if {![regexp {^([0-9]+)} [string trim $versionToby] -> majeur]} { return 0 }
  expr {$majeur >= 2}
}

proc ::moderne::niveau::T {fr en} { return [::moderne::tr $fr $en] }

### Siby's log on disk (siby.log in the settings folder, 2 MB at most): on
### Windows a program with windows has no standard error, the level's
### diagnostics went nowhere (Yosha's bullet review, 2026-11-04)
### The lines are written together, a second later at most and when Siby
### quits (::moderne::journalVider): opening and closing the file for each
### line took up to 1.2 s on Windows (the antivirus looks at each opening),
### 21 s during one review, which wrote Toby's lines (2026-11-06)
proc ::moderne::journal {texte} {
  variable journalTampon
  variable journalApres
  catch {puts stderr $texte}
  append journalTampon "[clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}] $texte\n"
  if {![info exists journalApres] || $journalApres eq {}} {
    set journalApres [after 1000 ::moderne::journalVider]
  }
  if {[string length $journalTampon] > 200000} { journalVider }
}
proc ::moderne::journalVider {} {
  variable journalTampon
  variable journalApres
  catch {after cancel $journalApres}
  set journalApres {}
  if {![info exists journalTampon] || $journalTampon eq {}} { return }
  set t $journalTampon
  set journalTampon {}
  set f [file join $::scidUserDir siby.log]
  # (written by a thread: opening the file froze the window on Windows)
  if {![catch {sc_ecrire_fond ajout $f $t 2000000}]} { return }
  catch {
    if {[file exists $f] && [file size $f] > 2000000} { file rename -force $f $f.1 }
    set c [open $f a]
    fconfigure $c -encoding utf-8
    puts -nonewline $c $t
    close $c
  }
  catch {close $c}
}

### Is a Toby engine installed (needed for the estimate)?
proc ::moderne::niveau::disponible {} {
  variable sansReponse
  return [expr {!$sansReponse && [llength [::moderne::toby::moteursToby]] > 0}]
}

### Starts following game cle: ratings of White and Black (0 = unknown),
### rating source (FIDE, Lichess Blitz...) and Toby time control
### (Classical, Rapid, Blitz); rappel: command run after each estimate
### options (game review): eloPartie R = the probability of each move played
### at rating R is kept too (the review's good moves: one Toby for both,
### 2026-10-29); tousCoups 1 = every move from the first one is asked (all
### of them count for the level)
proc ::moderne::niveau::suivre {cle eloB eloN source cadence {rappel {}} {options {}}} {
  # (a new game followed: Toby may be started again once more, see silence;
  # a level turned off for a Toby that did not answer is tried again: it
  # stayed off until Siby restarted, every later review had no level,
  # Yosha 2026-11-04)
  variable relances 0
  variable sansReponse 0
  variable notes
  variable compte
  variable faits
  variable rappels
  variable infos
  variable opts
  if {[info exists faits($cle)]} {
    set rappels($cle) $rappel
    return
  }
  set opts($cle) $options
  # (the game's ratings: used only through priorElo, see there)
  set cal [calibration]
  set c [expr {[dict exists $cal $cadence] ? [dict get $cal $cadence] : [dict get $cal Classical]}]
  # (the place is given by the review only: elsewhere, no setting applies)
  set lieu [expr {[dict exists $options lieu] ? [dict get $options lieu] : {}}]
  variable reglages
  variable taus
  foreach cote {B N} elo [list $eloB $eloN] {
    set r [reglageElo $lieu $cadence]
    set avecElo [expr {[string is integer -strict $elo] && $elo > 0}]
    # (a side without rating: that case's setting without it, else the
    # estimate without the ratings, as for the other cases)
    if {[dict size $r] && !$avecElo} { set r [expr {[dict exists $r sansElo] ? [dict get $r sansElo] : {}}] }
    set reglages($cle,$cote) $r
    set taus($cle,$cote) [expr {[dict exists $r tau] ? double([dict get $r tau]) : 1.0}]
    lassign $c mu sd
    if {[dict exists $r cal]} { lassign [dict get $r cal] mu sd }
    if {[dict exists $r flat] && [dict get $r flat]} {
      set notes($cle,$cote) [lrepeat [llength $::moderne::niveau::grille] 0.0]
    } else {
      if {[dict size $r] && $avecElo} { lassign [priorAvecElo $mu $sd $elo $r] mu sd }
      set notes($cle,$cote) [prior $mu $sd]
    }
    set compte($cle,$cote) 0
    # (Toby 2's level head: the plain sum of the moves' log-likelihoods,
    # its own prior and correction applied in estimationNiveau)
    variable sommes
    set sommes($cle,$cote) [lrepeat [llength $::moderne::niveau::grille] 0.0]
  }
  set faits($cle) 0
  set rappels($cle) $rappel
  set infos($cle) [list $source $cadence $eloB $eloN $lieu]
}

### The model of one answer of game cle, noted; a game whose answers come
### from two models (Leela failed in one of the Toby processes) keeps the
### T5 calibration, and siby.log says so once
proc ::moderne::niveau::noterModele {cle m} {
  variable modeles
  if {![info exists modeles($cle)]} { set modeles($cle) {} }
  if {$m in $modeles($cle)} { return }
  lappend modeles($cle) $m
  if {[llength $modeles($cle)] == 2} {
    catch {::moderne::journal "Level of play: answers from [join $modeles($cle) { and }] in one game, T5 calibration used"}
  }
}

### Does side cote's estimate of game cle start from the player's rating?
proc ::moderne::niveau::avecElo {cle cote} {
  variable reglages
  if {![info exists reglages($cle,$cote)]} { return 0 }
  set r $reglages($cle,$cote)
  expr {[dict exists $r remplace] && [dict get $r remplace]}
}

### Average drift d(r) of the estimate for players rated r (setting reglage)
proc ::moderne::niveau::derive {reglage r} {
  if {[dict exists $reglage deriveClamp]} {
    lassign [dict get $reglage deriveClamp] lo hi
    set r [expr {min(max($r, $lo), $hi)}]
  }
  set c [dict get $reglage derive]
  set d [expr {[lindex $c 0] + [lindex $c 1] * $r}]
  foreach kp [lrange $c 2 end] {
    lassign $kp k p
    set d [expr {$d + $p * max(0, $r - $k)}]
  }
  return $d
}

### The setting of the ratings for place lieu and time control cad, {} if none
proc ::moderne::niveau::reglageElo {lieu cad} {
  variable priorElo
  variable priorEloToby2
  set pe $priorElo
  if {$priorEloToby2 ne {} && [estToby2]} { set pe $priorEloToby2 }
  if {[dict exists $pe "$lieu $cad"]} { return [dict get $pe "$lieu $cad"] }
  return {}
}

### The prior with the side's rating: {mu sd}. The rating weighs with
### standard deviation sdElo against the prior (product of the two normal
### laws), or replaces it (remplace 1).
proc ::moderne::niveau::priorAvecElo {mu sd elo reglage} {
  if {![dict exists $reglage sdElo]} { return [list $mu $sd] }
  set s [dict get $reglage sdElo]
  if {[dict exists $reglage remplace] && [dict get $reglage remplace]} { return [list $elo $s] }
  set p1 [expr {1.0 / ($sd * $sd)}] ; set p2 [expr {1.0 / ($s * $s)}]
  return [list [expr {($mu * $p1 + $elo * $p2) / ($p1 + $p2)}] [expr {sqrt(1.0 / ($p1 + $p2))}]]
}

### Where the game on the board was played: otb (over the board, including
### the broadcasts of real events), lichess (played on lichess.org: Site
### lichess.org/<id> and Event "Rated/Casual ... game"), chesscom
proc ::moderne::niveau::lieuPartie {} {
  set site [sc_game tags get Site]
  set event [sc_game tags get Event]
  if {[regexp -nocase {chess\.com} $site]} { return chesscom }
  if {[regexp -nocase {lichess\.org/[A-Za-z0-9]{8}} $site] && [regexp -nocase {^(rated|casual)\M.*\mgame$} [string trim $event]]} { return lichess }
  return otb
}

proc ::moderne::niveau::prior {mu sd} {
  variable grille
  set l {}
  foreach e $grille { lappend l [expr {-0.5 * (($e - $mu) / double($sd)) ** 2}] }
  return $l
}

### New moves of game cle: start position (FEN or "startpos") and the whole
### move list (UCI); the moves not yet queued are queued
proc ::moderne::niveau::coups {cle depart ucis} {
  variable faits
  variable file
  variable infos
  variable premierCoup
  if {![info exists faits($cle)] || ![disponible]} { return }
  set n [llength $ucis]
  # (the moves already queued must still be the game's first moves: a game
  # taken back or changed starts again)
  variable dejaUcis
  set change [expr {[info exists dejaUcis($cle)] && [lrange $ucis 0 [expr {[llength $dejaUcis($cle)] - 1}]] ne $dejaUcis($cle)}]
  if {$n < $faits($cle) || $change} {
    # (the game was taken back or changed: start again)
    set r $::moderne::niveau::rappels($cle)
    lassign $infos($cle) source cadence eloB eloN
    oublier $cle
    suivre $cle $eloB $eloN $source $cadence $r
  }
  lassign $infos($cle) source cadence
  variable opts
  set tous [expr {[info exists opts($cle)] && [dict exists $opts($cle) tousCoups] && [dict get $opts($cle) tousCoups]}]
  for {set i $faits($cle)} {$i < $n} {incr i} {
    if {$i < $premierCoup && !$tous} { continue }
    set avant [lrange $ucis 0 [expr {$i - 1}]]
    set pos [expr {$depart eq "startpos" ? "position startpos" : "position fen $depart"}]
    if {[llength $avant]} { append pos " moves [join $avant]" }
    # side to move: White on even plies of a standard start
    set cote [expr {$i % 2 == 0 ? "B" : "N"}]
    if {$depart ne "startpos" && [lindex [split $depart] 1] eq "b"} { set cote [expr {$cote eq "B" ? "N" : "B"}] }
    # (type: compter = counted for the level; proba = before the first ply counted, only
    # the probability at the game's rating)
    lappend file [list $cle $cote $pos [lindex $ucis $i] $source $cadence $i [expr {$i < $premierCoup ? "proba" : "compter"}]]
    variable total
    incr total($cle)
  }
  set faits($cle) $n
  set dejaUcis($cle) $ucis
  variable dejaDepart
  set dejaDepart($cle) $depart
  suivant
}

### Moves of game cle from the current game of Siby's main board
proc ::moderne::niveau::coupsPartie {cle} {
  set ucis {}
  catch {
    sc_game push copy
    sc_move end
    set ucis [sc_game moves coord]
    set depart [expr {[sc_game startBoard] ? [sc_game startPos] : "startpos"}]
    sc_game pop
  }
  if {![info exists depart] || [lsearch -exact $ucis 0000] >= 0} { return }
  coups $cle $depart $ucis
}

### Moves of game cle from a PGN text (the main board is left alone)
proc ::moderne::niveau::coupsPgn {cle pgn} {
  set ucis {}
  set code [catch {
    sc_game push
    sc_game import $pgn
    sc_move end
    set ucis [sc_game moves coord]
    set depart [expr {[sc_game startBoard] ? [sc_game startPos] : "startpos"}]
  }]
  catch {sc_game pop}
  if {$code || [lsearch -exact $ucis 0000] >= 0} { return }
  coups $cle $depart $ucis
}

proc ::moderne::niveau::oublier {cle} {
  variable notes
  variable compte
  variable faits
  variable rappels
  variable infos
  variable file
  array unset notes $cle,*
  array unset compte $cle,*
  catch {unset ::moderne::niveau::modeles($cle)}
  array unset ::moderne::niveau::reglages $cle,*
  array unset ::moderne::niveau::taus $cle,*
  catch {unset faits($cle)}
  catch {unset rappels($cle)}
  catch {unset infos($cle)}
  catch {unset ::moderne::niveau::opts($cle)}
  array unset ::moderne::niveau::probas $cle,*
  array unset ::moderne::niveau::distrib $cle,*
  array unset ::moderne::niveau::maias $cle,*
  array unset ::moderne::niveau::tobys $cle,*
  array unset ::moderne::niveau::sommes $cle,*
  catch {unset ::moderne::niveau::modeJeu($cle)}
  catch {unset ::moderne::niveau::calJeu($cle)}
  catch {unset ::moderne::niveau::dejaDepart($cle)}
  catch {unset ::moderne::niveau::total($cle)}
  catch {unset ::moderne::niveau::dejaUcis($cle)}
  set f {}
  foreach r $file { if {[lindex $r 0] ne $cle} { lappend f $r } }
  set file $f
}

### Estimate of side cote (B or N) of game cle: {rating sd moves}, or {}
### (brut 1: the posterior itself, without the correction)
proc ::moderne::niveau::estimation {cle cote {brut 0}} {
  variable notes
  variable compte
  variable grille
  if {![info exists notes($cle,$cote)]} { return {} }
  if {[estNiveau $cle]} { return [estimationNiveau $cle $cote $brut] }
  set l $notes($cle,$cote)
  set m [tcl::mathfunc::max {*}$l]
  set s 0.0 ; set s1 0.0 ; set s2 0.0
  foreach e $grille v $l {
    set p [expr {exp($v - $m)}]
    set s [expr {$s + $p}]
    set s1 [expr {$s1 + $p * $e}]
    set s2 [expr {$s2 + $p * $e * $e}]
  }
  set moy [expr {$s1 / $s}]
  set sd [expr {sqrt(max(0.0, $s2 / $s - $moy * $moy))}]
  if {$brut} { return [list [expr {round($moy)}] [expr {round($sd)}] $compte($cle,$cote)] }
  # calibrated correction of the time control
  variable infos
  set cal [calibration $cle]
  set cad Classical
  catch {set cad [lindex $infos($cle) 1]}
  if {![dict exists $cal $cad]} { set cad Classical }
  lassign [dict get $cal $cad] - - a b
  # (the ratings used for this place and time control: its own correction,
  # or none)
  variable reglages
  set reglage {}
  catch {set reglage $reglages($cle,$cote)}
  if {[dict exists $reglage cal]} { lassign [dict get $reglage cal] - - a b }
  if {[dict exists $reglage brut] && [dict get $reglage brut]} { set a 0.0 ; set b 1.0 }
  # (the average drift of players of that rating, taken off)
  if {[dict exists $reglage derive]} {
    set r 0
    catch {set r [lindex $infos($cle) [expr {$cote eq "B" ? 2 : 3}]]}
    if {[string is integer -strict $r] && $r > 0} { set a [expr {$a - [derive $reglage $r]}] }
  }
  set moy [expr {$a + $b * $moy}]
  set sd [expr {$b * $sd}]
  return [list [expr {round($moy)}] [expr {round($sd)}] $compte($cle,$cote)]
}

### A level as shown: "2900+" above the ceiling, else the number (with "≈ "
### when approx)
proc ::moderne::niveau::affiche {r {approx 0} {source {}}} {
  variable plafond
  variable plancher
  if {![string is integer -strict $r]} { return $r }
  # (from the moves alone, no number at the ends: one game cannot tell
  # 2500 from 2800, Yosha and Toby 2026-11-22)
  if {$source eq "a"} {
    variable plafondA
    variable plancherA
    if {$r >= $plafondA} { return "$plafondA+" }
    if {$r < $plancherA} { return [T "moins de $plancherA" "under $plancherA"] }
  }
  if {$r > $plafond} { return "$plafond+" }
  if {$r < $plancher} { return "$plancher−" }
  return [expr {$approx ? "≈ $r" : $r}]
}

### Text shown: "≈ 2140" (empty until enough moves)
proc ::moderne::niveau::texte {cle cote} {
  variable minCoups
  set e [estimation $cle $cote]
  if {$e eq {} || [lindex $e 2] < $minCoups} { return {} }
  return [affiche [lindex $e 0] 1 [lindex $e 3]]
}

### Tooltip of the estimate
proc ::moderne::niveau::bulle {cle cote} {
  set e [estimation $cle $cote]
  if {$e eq {}} { return {} }
  lassign $e r sd n source
  variable plafond
  variable plancher
  variable plafondA
  variable plancherA
  if {$source eq "a" && $r >= $plafondA} {
    return "[T "Niveau de jeu estimé dans cette partie : $plafondA+\nUne partie ne permet pas de distinguer les niveaux plus hauts.\nd'après $n coups (Toby)" \
              "Level of play estimated in this game: $plafondA+\nOne game cannot tell upper levels apart.\nfrom $n moves (Toby)"][noteEpoque]"
  }
  if {$source eq "a" && $r < $plancherA} {
    return "[T "Niveau de jeu estimé dans cette partie : moins de $plancherA\nUne partie ne permet pas de distinguer les niveaux plus bas.\nd'après $n coups (Toby)" \
              "Level of play estimated in this game: under $plancherA\nOne game cannot tell lower levels apart.\nfrom $n moves (Toby)"][noteEpoque]"
  }
  if {$r < $plancher} {
    return "[T "Niveau de jeu estimé dans cette partie : sous $plancher, le plancher du classement FIDE\n(pas de nombre plus précis en dessous)\nd'après $n coups" \
              "Level of play estimated in this game: below $plancher, the FIDE rating floor\n(no finer number below it)\nfrom $n moves"][noteEpoque]"
  }
  if {$r > $plafond} {
    return "[T "Niveau de jeu estimé dans cette partie : au-dessus de $plafond\n(Toby ne distingue pas les niveaux au-delà : les parties humaines s'arrêtent vers $plafond)\nd'après $n coups" \
              "Level of play estimated in this game: above $plafond\n(Toby cannot tell levels apart beyond that: human games stop around $plafond)\nfrom $n moves"][noteEpoque]"
  }
  # (no margin: "to about 930 points" read as "we know nothing" while the
  # estimate is often right; Lichess and chess.com show none, Yosha
  # 2026-11-22; to come back once Toby's uncertainty is known calibrated)
  return "[T "Niveau de jeu estimé dans cette partie : $r\nd'après $n coups (Toby)" \
            "Level of play estimated in this game: $r\nfrom $n moves (Toby)"][noteEpoque]"
}

### For a game played before 2018 (Date tag of the current game): the level
### is measured with today's standards. Measured 2026-10-30: the same Elo
### meant weaker play then (about 90 to 165 points lower before 2018, Elo
### deflation); {} otherwise
proc ::moderne::niveau::noteEpoque {} {
  set a 0
  catch {set a [string range [sc_game tags get Date] 0 3]}
  if {![string is integer -strict $a] || $a < 1800 || $a >= 2018} { return {} }
  # (no "at the same rating" sentence: there were no ratings in 1927,
  # Yosha 2026-11-09)
  return [T "\nPartie de $a : niveau mesuré avec les standards d'aujourd'hui." \
            "\nGame from $a: level measured with today's standards."]
}

### Ratings asked for a move: a fixed grid, 1200 to 3000 every 150 (13
### ratings, read with PCHIP: as close to the 25-point grid as every 100 with
### straight lines, 30 % less Maia; Toby, 2026-11-04), before: every 100 (the
### calibration's range). The same game then gives the same level whatever
### the order the answers come back in; the ratings used to follow the
### running estimate, and two reviews of one game differed by about 20
### points (2026-11-01). On the calibration sample (4,830 players) this grid
### is within 1.3 points on average of the 25-point grid the level was
### calibrated with (13.4 for the old moving grid, up to 384); Toby computes
### the 19 ratings in one Maia call (0.75 s per move instead of 0.72 s).
proc ::moderne::niveau::notesDemandees {cle cote} {
  variable notesFixes
  if {![info exists notesFixes]} {
    for {set r 1200} {$r <= 3000} {incr r 150} { lappend notesFixes $r }
  }
  return $notesFixes
}

### Ratings asked for a request: the level's (around the estimate), plus the
### game's rating in a review; only the latter before the first ply counted
proc ::moderne::niveau::notesPour {cle cote type} {
  variable opts
  set r {}
  catch {set r [dict get $opts($cle) eloPartie]}
  if {$type eq "proba"} { return [expr {$r ne {} ? $r : [notesDemandees $cle $cote]}] }
  set l [notesDemandees $cle $cote]
  if {$r ne {} && $r ni $l} { lappend l $r }
  return $l
}

### Probability (0-1) of the move played at ply i of game cle at the game's
### rating ({} if not known yet)
proc ::moderne::niveau::proba {cle i} {
  variable probas
  if {[info exists probas($cle,$i)]} { return $probas($cle,$i) }
  return {}
}

### Toby's full answer at ply i ({es probs esCoups}: the position's expected
### score, dicts move -> probability and expected score), asked with
### demanderGo; {} until it is there
proc ::moderne::niveau::distribution {cle i} {
  variable distrib
  if {[info exists distrib($cle,$i)]} { return $distrib($cle,$i) }
  return {}
}

### Asks Toby's full answer at ply i (position pos, UCI) at rating elo, ahead
### of the level's moves
proc ::moderne::niveau::demanderGo {cle i pos elo} {
  variable file
  variable infos
  variable total
  if {![info exists infos($cle)]} { return }
  lassign $infos($cle) source cadence
  set file [linsert $file 0 [list $cle {} $pos {} $source $cadence $i go $elo]]
  incr total($cle)
  suivant
}

### Maia's probabilities at ply i (dict move -> probability 0-1), asked with
### demanderMaia; {} until they are there
proc ::moderne::niveau::maia {cle i} {
  variable maias
  if {[info exists maias($cle,$i)]} { return $maias($cle,$i) }
  return {}
}

### Toby's probabilities at ply i at the game's rating (dict move ->
### probability 0-1), given with the level's request ("dist"); {} until
### they are there
proc ::moderne::niveau::tobyDist {cle i} {
  variable tobys
  if {[info exists tobys($cle,$i)]} { return $tobys($cle,$i) }
  return {}
}

### Maia requests of game cle not answered yet (queued or running)
proc ::moderne::niveau::maiaEnAttente {cle} {
  variable file
  set n 0
  foreach r [concat $file [enCours]] {
    if {[lindex $r 0] eq $cle && ([lindex $r 7] eq "maia" || [lindex $r 9] eq "maia")} { incr n }
  }
  return $n
}

### Asks Maia's probabilities at ply i (Maia alone, at once), ahead of the
### level's moves
proc ::moderne::niveau::demanderMaia {cle i pos elo} {
  variable file
  variable infos
  variable total
  if {![info exists infos($cle)]} { return }
  # (a Toby with "dist": Maia's distribution comes with the level's request
  # of that move, which is moved to the front; nothing more is asked)
  if {[avecDist]} {
    variable maias
    if {[info exists maias($cle,$i)]} { return }
    foreach r [enCours] { if {[lindex $r 0] eq $cle && [lindex $r 6] == $i && [lindex $r 7] in {compter proba}} { return } }
    set k 0
    foreach r $file {
      if {[lindex $r 0] eq $cle && [lindex $r 6] == $i && [lindex $r 7] in {compter proba}} {
        set r2 [lrange $r 0 7]
        lappend r2 $elo maia
        set file [linsert [lreplace $file $k $k] 0 $r2]
        suivant
        return
      }
      incr k
    }
  }
  lassign $infos($cle) source cadence
  set file [linsert $file 0 [list $cle {} $pos {} $source $cadence $i maia $elo]]
  incr total($cle)
  suivant
}

### Does a running Toby give Maia's distribution with "toby likelihood"
### ("dist", Toby 2026-10-29)?
proc ::moderne::niveau::avecDist {} {
  variable capacites
  foreach w [array names capacites] { if {"likelihood-dist" in $capacites($w) || [niveauServi $w]} { return 1 } }
  return 0
}

### Adds a move's likelihood: ratings rs and probabilities ps
proc ::moderne::niveau::ajouter {cle cote rs ps} {
  variable notes
  variable compte
  variable grille
  if {![info exists notes($cle,$cote)]} { return }
  set ys {}
  foreach p $ps { lappend ys [expr {log(max($p, 1e-9))}] }
  # (the temperature of the side's setting, 1 by default)
  variable taus
  if {[info exists taus($cle,$cote)] && $taus($cle,$cote) != 1.0} {
    set ys [lmap y $ys {expr {$y / $taus($cle,$cote)}}]
  }
  set l {}
  foreach v $notes($cle,$cote) q [interpoler $rs $ys $grille] { lappend l [expr {$v + $q}] }
  set notes($cle,$cote) $l
  incr compte($cle,$cote)
}

### log p at each rating of es, from its values ys at the ratings rs:
### PCHIP (monotone piecewise cubic, Fritsch-Carlson, as scipy's
### PchipInterpolator) inside rs, straight lines beyond its ends. Ratings
### every 150 with PCHIP are as close to the calibration's 25-point grid
### as every 100 with straight lines (Toby, 2026-11-04)
proc ::moderne::niveau::interpoler {rs ys es} {
  # (sorted, each rating once)
  set paires {}
  foreach r $rs y $ys { lappend paires [list $r $y] }
  set paires [lsort -real -unique -index 0 $paires]
  set xs {} ; set ys {}
  foreach p $paires { lappend xs [expr {double([lindex $p 0])}] ; lappend ys [lindex $p 1] }
  set n [llength $xs]
  if {$n == 0} { return [lrepeat [llength $es] 0.0] }
  if {$n == 1} { return [lrepeat [llength $es] [lindex $ys 0]] }
  set h {} ; set d {}
  for {set k 0} {$k < $n - 1} {incr k} {
    set hk [expr {[lindex $xs $k+1] - [lindex $xs $k]}]
    lappend h $hk
    lappend d [expr {([lindex $ys $k+1] - [lindex $ys $k]) / $hk}]
  }
  # slopes at the ratings
  set m [lrepeat $n 0.0]
  if {$n == 2} {
    set m [list [lindex $d 0] [lindex $d 0]]
  } else {
    for {set k 1} {$k < $n - 1} {incr k} {
      set d0 [lindex $d $k-1] ; set d1 [lindex $d $k]
      if {$d0 == 0 || $d1 == 0 || ($d0 > 0) != ($d1 > 0)} { continue }
      set h0 [lindex $h $k-1] ; set h1 [lindex $h $k]
      set w1 [expr {2 * $h1 + $h0}] ; set w2 [expr {$h1 + 2 * $h0}]
      lset m $k [expr {($w1 + $w2) / ($w1 / $d0 + $w2 / $d1)}]
    }
    lset m 0 [pchipBout [lindex $h 0] [lindex $h 1] [lindex $d 0] [lindex $d 1]]
    lset m end [pchipBout [lindex $h end] [lindex $h end-1] [lindex $d end] [lindex $d end-1]]
  }
  set r {}
  set k 0
  foreach e $es {
    if {$e <= [lindex $xs 0]} {
      lappend r [expr {[lindex $ys 0] + [lindex $d 0] * ($e - [lindex $xs 0])}]
      continue
    }
    if {$e >= [lindex $xs end]} {
      lappend r [expr {[lindex $ys end] + [lindex $d end] * ($e - [lindex $xs end])}]
      continue
    }
    while {$k > 0 && [lindex $xs $k] > $e} { incr k -1 }
    while {[lindex $xs $k+1] < $e} { incr k }
    set hk [lindex $h $k]
    set t [expr {($e - [lindex $xs $k]) / $hk}]
    set t2 [expr {$t * $t}] ; set t3 [expr {$t2 * $t}]
    lappend r [expr {(2 * $t3 - 3 * $t2 + 1) * [lindex $ys $k] + ($t3 - 2 * $t2 + $t) * $hk * [lindex $m $k]
                     + (-2 * $t3 + 3 * $t2) * [lindex $ys $k+1] + ($t3 - $t2) * $hk * [lindex $m $k+1]}]
  }
  return $r
}

### End slope of PCHIP (3 points, shape-preserving), as scipy
proc ::moderne::niveau::pchipBout {h0 h1 d0 d1} {
  set m [expr {((2 * $h0 + $h1) * $d0 - $h0 * $d1) / ($h0 + $h1)}]
  set sm [expr {$m > 0 ? 1 : ($m < 0 ? -1 : 0)}]
  set s0 [expr {$d0 > 0 ? 1 : ($d0 < 0 ? -1 : 0)}]
  set s1 [expr {$d1 > 0 ? 1 : ($d1 < 0 ? -1 : 0)}]
  if {$sm != $s0} { return 0.0 }
  if {$s0 != $s1 && abs($m) > abs(3 * $d0)} { return [expr {3 * $d0}] }
  return $m
}

################################################################################
### The Toby process
################################################################################

### Several Toby processes, each on its own moves, each with one Stockfish
### thread: about linear in the number of processes, and exactly the
### setting the level of play was calibrated with (one thread).
proc ::moderne::niveau::nbProcessus {} {
  # one: each Toby holds Maia, Leela and Stockfish in memory (1.5 to 4 GB
  # with its lc0 on Yosha's computer); four filled the memory and nothing
  # moved any more (2026-10-27). Two during a game review (Yosha's choice,
  # 2026-10-29): there Toby gets "toby likelihood" and Precision Fast, so
  # no Leela is loaded (about 1.3 GB each, one core each), and only with 6
  # cores or more
  # In a review (paralleles > 1): as many as the computer allows, decided
  # once at the review's start (2026-10-29, Yosha's choice): one Toby per 3
  # cores, 1.3 GB of free memory each with 2 GB kept, 4 at most; the
  # engine pool of the annotation leaves them their cores
  variable paralleles
  if {[info exists paralleles] && $paralleles > 1} {
    # (a Toby that runs batches uses every core it is given by itself:
    # one process, one Maia in memory; Toby 2026-11-01)
    if {[avecLot] && [lotUtile]} { return 1 }
    return [dict get [partage] toby]
  }
  return 1
}

### The computer's cores during a review (2026-10-30, measured on a pod with
### 12 cores: 1 Toby 113 s, 4 Toby 50 s, 4 Toby with Maia on the graphics
### card 36 s): one core left free for Siby and the system; with an NVIDIA
### card Maia runs on it and each Toby takes one core (its Stockfish), else
### three (Stockfish and two Maia threads); at most 4 Toby, 1.3 GB of free
### memory each with 2 GB kept; Siby's engine pool gets the rest. Decided
### once per review: {toby n maia threads pool n}
proc ::moderne::niveau::partage {} {
  variable partageBilan
  if {[info exists partageBilan]} { return $partageBilan }
  set c [::moderne::toby::coeurs]
  # (3.5 to 5 GB each on Windows measured on Yosha's PC 2026-10-30, with
  # Leela loaded; in a review Toby runs Precision Fast and "toby
  # likelihood", no Leela: 1.3 GB on a Linux pod. 4.5 GB each kept her
  # 12-core PC at 2 Toby, the level taking 115 s for 78 positions while
  # the annotation was over in 34 s (review.log, 2026-11-02): 2.5 GB, the
  # panel's Toby, already in memory, being borrowed besides)
  set parMemoire [expr {max(1, int(([memoireLibre] - 3000) / 2500))}]
  # Maia runs on the processor in Toby's package, NVIDIA card or not (its
  # PyTorch is the CPU one; Toby 2026-11-02): each Toby gets its share of
  # the cores for Maia ("Maia Threads"), else every Toby took all of them
  # and 4 Toby were no faster than 2 (4.9 s per position instead of 2.9).
  # One Toby per 3 cores, at most 4; Maia threads: cores / Toby (Toby's
  # advice), its Stockfish being short (0.2 to 0.5 s per position)
  set n [expr {max(1, min(4, $c / 3, $parMemoire))}]
  # (on the graphics card: the process with the full answers (lc0, about
  # 2.8 GB) plus one per 1.25 GB left (Maia, about 1.2 GB), measured by
  # Toby on a T4, 2026-11-08)
  set vram [vramLibre]
  if {$vram ne {}} { set n [expr {max(1, min($n, 1 + int(($vram - 2800) / 1250)))}] }
  set mt [expr {max(1, $c / $n)}]
  # (Maia on the graphics card, as Toby says: one thread each is enough)
  if {[info exists ::moderne::toby::maiaDevice] && $::moderne::toby::maiaDevice eq "cuda"} { set mt 1 }
  set pool [expr {max(1, $c - 1 - $n)}]
  set partageBilan [dict create toby $n maia $mt pool $pool]
  # (in review.log: the graphics memory it was decided with)
  if {$vram ne {}} { dict set partageBilan vram $vram }
  return $partageBilan
}

### In a review, the analysis panel's Toby (paused, Maia loaded) is borrowed
### instead of starting another Toby (2026-10-29: 16 s and 1.3 GB saved).
### Returns the worker's name, {} if none can be borrowed.
proc ::moderne::niveau::emprunter {} {
  variable pipes
  variable courants
  variable emprunts
  variable pret
  if {![info exists ::moderne::oracle::fournisseur] || $::moderne::oracle::fournisseur eq {}} { return {} }
  foreach t [::moderne::toby::moteursToby] {
    set n [lindex $t 0]
    set w p$n
    if {[info exists pipes($w)]} { continue }
    if {![winfo exists .analysisWin$n] || ![info exists ::analysis(pipe$n)] || $::analysis(pipe$n) eq {}} { continue }
    if {![info exists ::analysis(uciok$n)] || !$::analysis(uciok$n)} { continue }
    if {[info exists ::analysis(analyzeMode$n)] && $::analysis(analyzeMode$n)} { continue }
    set p $::analysis(pipe$n)
    set pipes($w) $p
    set courants($w) {}
    set emprunts($w) $n
    set pret($w) 0
    fileevent $p readable [list ::moderne::niveau::lire $w]
    # ("uci" again: its capabilities, read before "readyok")
    # (Toby 2: the level on Standard, its Accurate given back afterwards)
    if {[::moderne::toby::aOption $n "Toby 2 Product"]} {
      catch {puts $p "setoption name Toby 2 Product value Standard"}
      # (prepared again, with isready, at the panel's next go)
      catch {unset ::moderne::toby::produitPrepare($n)}
    }
    catch {puts $p stop ; puts $p "setoption name Precision value Fast" ; puts $p "setoption name Mode value Prediction" ; puts $p "setoption name Stockfish Threads value 1" ; puts $p "setoption name Maia Threads value [filsMaia]" ; puts $p uci ; puts $p isready ; flush $p}
    return $w
  }
  return {}
}

### The borrowed panels' Toby given back (end of the review)
proc ::moderne::niveau::rendre {} {
  variable emprunts
  variable file
  variable pipes
  foreach w [array names emprunts] {
    # (the panel's Toby gets its own Maia threads back: its engine option,
    # 0 = Toby's choice)
    set v 0
    catch {
      foreach opt [lindex $::engines(list) $emprunts($w) 8] {
        if {[lindex $opt 0] eq "Maia Threads"} { set v [lindex $opt 1] }
      }
    }
    catch {puts $pipes($w) "setoption name Maia Threads value $v" ; flush $pipes($w)}
    set f {}
    foreach r $file { if {[lindex $r 0] ne {}} { lappend f $r } }
    fermer $w
  }
}

### Is the panel of engine n lent to the level of play?
proc ::moderne::niveau::prete {n} {
  variable emprunts
  foreach w [array names emprunts] { if {$emprunts($w) == $n} { return 1 } }
  return 0
}

# (a lent panel is not started again until it is given back)
if {[llength [info commands ::toggleEngineAnalysis]] && ![llength [info commands ::moderne::niveau::toggleOrigine]]} {
  rename ::toggleEngineAnalysis ::moderne::niveau::toggleOrigine
  proc ::toggleEngineAnalysis {{n -1}} {
    # (its window closed or being made meanwhile: nothing to start or stop,
    # it failed on its button, monkey test 2026-11-12)
    if {$n != -1 && ![winfo exists .analysisWin$n.b.startStop]} { return }
    if {$n != -1 && [::moderne::niveau::prete $n]} {
      # (lent to a review still running: it stays there; else given back
      # at once, the user asks for it)
      if {[info exists ::moderne::oracle::fournisseur] && $::moderne::oracle::fournisseur ne {}} { return }
      foreach w [array names ::moderne::niveau::emprunts] {
        if {$::moderne::niveau::emprunts($w) == $n} { ::moderne::niveau::fermer $w }
      }
    }
    uplevel 1 [list ::moderne::niveau::toggleOrigine $n]
  }
}

### Maia's threads in each Toby of the level: the cores Siby's engine pool
### leaves free (in a review), shared between the Toby processes; else 2
proc ::moderne::niveau::filsMaia {} {
  if {[info exists ::moderne::oracle::fournisseur] && $::moderne::oracle::fournisseur ne {}} {
    return [dict get [partage] maia]
  }
  return 2
}

### Free memory of the NVIDIA card in MB, the largest one ({} without a
### card or when it can't be read)
proc ::moderne::niveau::vramLibre {} {
  set gpu 0
  catch {set gpu [::moderne::ajout::nvidia]}
  if {$gpu ne "1"} { return {} }
  set exe [auto_execok nvidia-smi]
  if {$exe eq {} && $::windowsOS} {
    foreach d [list "$::env(SystemRoot)/System32" "C:/Program Files/NVIDIA Corporation/NVSMI"] {
      if {[file exists $d/nvidia-smi.exe]} { set exe [list $d/nvidia-smi.exe] ; break }
    }
  }
  if {$exe eq {} || [catch {exec {*}$exe --query-gpu=memory.free --format=csv,noheader,nounits << {}} t]} { return {} }
  set m {}
  foreach l [split $t \n] {
    set l [string trim $l]
    if {[string is integer -strict $l] && ($m eq {} || $l > $m)} { set m $l }
  }
  return $m
}

### Free memory in MB (a large value when it can't be read: the cores decide)
proc ::moderne::niveau::memoireLibre {} {
  # (unknown: as if 6 GB were free, so one Toby only)
  set mo 6000
  # (asked to the system directly: wmic is gone from recent Windows, and
  # PowerShell started from Siby's window prints nothing)
  if {![catch {sc_gaby memoire} m] && [string is integer -strict $m] && $m > 0} { return $m }
  catch {
    if {$::windowsOS} {
      # (FreePhysicalMemory in KB; wmic is gone from recent Windows 11:
      # PowerShell then)
      set k {}
      catch {
        # (an empty input: wmic and PowerShell can wait on it forever)
        set t [exec {*}[auto_execok wmic] OS get FreePhysicalMemory /Value << {}]
        regexp {FreePhysicalMemory=([0-9]+)} $t -> k
      }
      if {$k eq {}} {
        catch {
          set t [exec {*}[auto_execok powershell] -NoProfile -NonInteractive -InputFormat None -Command \
                     {(Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory} << {}]
          regexp {([0-9]+)} $t -> k
        }
      }
      if {$k ne {}} { set mo [expr {$k / 1024}] }
    } else {
      set f [open /proc/meminfo] ; set t [read $f] ; close $f
      if {[regexp {MemAvailable:\s+([0-9]+)} $t -> k]} { set mo [expr {$k / 1024}] }
    }
  }
  return $mo
}

### Starts the Toby processes ahead (they load Maia, which takes a while),
### without giving them any move yet: the review calls it at its start, so
### that the level of play begins at once after the annotation
proc ::moderne::niveau::prechauffer {} {
  variable pipes
  variable fermeture
  catch {after cancel $fermeture}
  if {![disponible]} { return }
  while {[array size pipes] < [nbProcessus]} {
    # (one at a time until it said whether it runs batches)
    if {[attenteUci]} { break }
    set w [lancer]
    if {$w eq {}} { break }
    envoyer $w isready
  }
}

### Gives a move to each free process
proc ::moderne::niveau::suivant {} {
  variable file
  variable pipes
  variable courants
  variable sansReponse
  if {$sansReponse} { set file {} ; return }
  variable pause
  if {$pause} { return }
  # nothing left to do: Toby closed after a while (it holds a lot of
  # memory); new moves cancel that
  variable fermeture
  catch {after cancel $fermeture}
  if {![llength $file] && ![llength [enCours]]} {
    # (a minute: in a review, Toby's full answers for the good moves come
    # once the annotation's engine is done; loading Maia again costs seconds)
    # (one Toby kept loaded for gardeMinutes, for the next review or level
    # of play: no "Toby is starting" each time; the others closed now)
    variable paralleles
    if {![info exists paralleles] || $paralleles <= 1} { surplus [aGarder] }
    set fermeture [after [expr {max(1, $::moderne::niveau::gardeMinutes) * 60000}] ::moderne::niveau::arreter]
    return
  }
  # processes started as needed (no more than the moves waiting)
  variable pret
  variable uciok
  variable lots
  set libres {}
  foreach w [array names pipes] {
    if {$courants($w) eq {} && (![info exists pret($w)] || $pret($w)) && [info exists uciok($w)] && ![info exists lots($w)]} { lappend libres $w }
  }
  # (the full answers going to one process only, they start no other one)
  set aFaire 0
  foreach r $file { if {[lindex $r 7] ni {go maia}} { incr aFaire } }
  if {$aFaire < [llength $file] && ![array size pipes]} { incr aFaire }
  while {$aFaire > [llength $libres] && [array size pipes] < [nbProcessus] && ![attenteUci]} {
    # (in a review: the analysis panel's Toby, paused, is borrowed first:
    # Maia already loaded, no second process)
    set w [emprunter]
    if {$w ne {}} { break }
    set w [lancer]
    if {$w eq {}} { break }
  }
  if {![array size pipes]} { set file {} ; return }
  foreach w $libres {
    if {![llength $file]} { break }
    # (a Toby that runs batches: the probabilities waiting, in one batch)
    if {[lotPossible $w]} {
      set lot [prendreLot]
      if {[llength $lot] >= 2} { envoyerLot $w $lot ; continue }
    }
    # (full answers, go and maia, only to one process: in Classical Fast a
    # "go" starts an lc0 in Toby, 1.6 GB of graphics memory each; the
    # others only get "toby likelihood" and never start one, Toby
    # 2026-11-08)
    # (Toby 2's level head in a review: a move waits for the annotation's
    # Stockfish values of its position, attendValeurs)
    set k -1
    set j 0
    set porte [expr {$w eq [porteGo]}]
    set attend 0
    foreach r $file {
      if {$porte || [lindex $r 7] ni {go maia}} {
        if {![attendValeurs $w $r]} { set k $j ; break }
        set attend 1
      }
      incr j
    }
    if {$k < 0} {
      # (moves waiting for the annotation's values: looked at again in a
      # moment, whatever brings the values)
      variable revoir
      if {$attend && (![info exists revoir] || $revoir eq {})} {
        set revoir [after 1000 {set ::moderne::niveau::revoir {} ; ::moderne::niveau::suivant}]
      }
      continue
    }
    set r [lindex $file $k]
    set file [lreplace $file $k $k]
    set courants($w) $r
    variable debut
    set debut($w) [clock milliseconds]
    lassign $r cle cote pos uci source cadence ply type elo
    envoyer $w "setoption name Rating Source value $source"
    envoyer $w "setoption name Time Control value $cadence"
    envoyer $w $pos
      if {$type in {go maia}} {
      # go: Toby's full answer at the game's rating; maia: Maia alone (a
      # move asked in under 0.4 s: Toby answers with Maia only, at once,
      # without its Stockfish search), for the good moves
      variable bloc
      set bloc($w) {}
      foreach {o v} [list {White Rating} $elo {Black Rating} $elo Display Full MultiPV 500 \
                         {Provisional Lines} [expr {$type eq "maia" ? "true" : "false"}] Mode Prediction Precision Fast] {
        envoyer $w "setoption name $o value $v"
      }
      envoyer $w [expr {$type eq "maia" ? "go movetime 50" : "go"}]
    } else {
      envoyer $w [commandeProba $w $r]
    }
    attendre $w
  }
}

### The process that gets the full answers (go, maia): the borrowed panel's
### Toby (its lc0 is there anyway), else the first one started
proc ::moderne::niveau::porteGo {} {
  variable pipes
  variable emprunts
  foreach w [lsort -dictionary [array names emprunts]] {
    if {[info exists pipes($w)]} { return $w }
  }
  return [lindex [lsort -dictionary [array names pipes]] 0]
}

### The "toby likelihood" command of request r for process w
proc ::moderne::niveau::commandeProba {w r} {
  lassign $r cle cote pos uci source cadence ply type elo
  if {[modeNiveau $w $cle $cadence]} { return [commandeNiveau $w $r] }
  # (with "dist": Maia's distribution at the game's rating too, for the
  # good moves; the same Stockfish search)
  # (the rating: the request's, moved to the front for a good move,
  # else the one given for Maia's distribution (eloDist, a review), else
  # the game's when it is followed)
  set mots {}
  variable opts
  variable capacites
  foreach o {eloDist eloPartie} {
    if {$elo eq {} && [info exists opts($cle)] && [dict exists $opts($cle) $o]} {
      set elo [dict get $opts($cle) $o]
    }
  }
  if {$elo ne {} && [info exists capacites($w)] && "likelihood-dist" in $capacites($w)} {
    set mots " dist $elo"
  }
  return "toby likelihood $uci$mots [notesPour $cle $cote $type]"
}

################################################################################
### Review batches (Toby 2026-11-01, GUI_INTEGRATION.md 7ter): the
### probabilities of many moves sent at once between "toby batch begin" and
### "toby batch end"; Toby computes them on several cores and answers each
### block in the order of the commands, the same values as one by one
################################################################################

### Does a running Toby run batches?
proc ::moderne::niveau::avecLot {} {
  variable capacites
  foreach w [array names capacites] { if {"batch" in $capacites($w)} { return 1 } }
  return 0
}

proc ::moderne::niveau::lotPossible {w} {
  variable capacites
  variable lotsRefuses
  if {![info exists capacites($w)] || "batch" ni $capacites($w) || [info exists lotsRefuses($w)]} { return 0 }
  return [lotUtile]
}

### Batches pay only when the computer holds a single Toby anyway (no
### graphics card, or little memory): one Maia then, and batches add
### Stockfish workers. When it can hold several, several Tobys, one move at a
### time, are faster: each has its own Maia (measured 2026-11-01, RTX 3090
### and 12 cores: level 15-17 s with 4 Tobys, 20-22 s with batches; 8 cores
### without graphics card: batches 46 s for the review, 51-56 s without)
proc ::moderne::niveau::lotUtile {} {
  # Off for now (2026-11-01): on a computer without a graphics card Maia
  # is the limit, and the gain was not stable (Azure, 8 cores: level 31 to
  # 52 s with batches, 40 to 45 s one by one); to try again once Toby runs
  # Maia on several positions at once. ::env(SIBY_LOTS) turns them on.
  if {![info exists ::env(SIBY_LOTS)]} { return 0 }
  variable paralleles
  if {![info exists paralleles] || $paralleles <= 1} { return 1 }
  set n 1
  catch {set n [dict get [partage] toby]}
  return [expr {$n <= 1}]
}

### A Toby started that has not said yet what it can do (its "uciok")
proc ::moderne::niveau::attenteUci {} {
  variable pipes
  variable uciok
  foreach w [array names pipes] { if {![info exists uciok($w)]} { return 1 } }
  return 0
}

### Requests of the next batch, taken from the queue: the probabilities at
### its head with the same rating source and time control (options apply to
### the whole batch); a full answer (go, maia) stops it
proc ::moderne::niveau::prendreLot {} {
  variable file
  set lot {}
  set k 0
  foreach r $file {
    if {[lindex $r 7] ni {compter proba}} { break }
    if {$k && [lrange $r 4 5] ne [lrange [lindex $lot 0] 4 5]} { break }
    if {$k >= [tailleLot]} { break }
    lappend lot $r
    incr k
  }
  if {$k >= 2} { set file [lrange $file $k end] }
  return $lot
}

### Moves per batch: enough to keep every worker busy, small enough that a
### good move's full answer waits little, the workers follow the cores freed
### when the annotation ends, and the ratings asked (around the current
### estimate) follow the estimate
proc ::moderne::niveau::tailleLot {} {
  set k [ouvriersLot]
  # (while the annotation's engines run, Toby has few workers: short
  # batches, so the cores they free at the end are used at once; measured on
  # 8 cores 2026-11-01, batches of 8 moves on 1 worker held the level back)
  if {[info exists ::moderne::oracle::pool] && [llength $::moderne::oracle::pool]} {
    return [expr {max(2, 2 * $k)}]
  }
  return [expr {max(8, min(24, 3 * $k))}]
}

### Toby's Stockfish workers ("Review Workers"): in a review, the cores the
### annotation's engines and Maia leave (all of them but one once the
### annotation is done); else half the cores, the panels may analyse
proc ::moderne::niveau::ouvriersLot {} {
  set c [::moderne::toby::coeurs]
  set mt [filsMaia]
  variable paralleles
  if {[info exists paralleles] && $paralleles > 1} {
    set pool 0
    if {[info exists ::moderne::oracle::pool] && [llength $::moderne::oracle::pool]} {
      catch {set pool [dict get [partage] pool]}
    }
    return [expr {max(1, min(16, $c - 1 - $mt - $pool))}]
  }
  return [expr {max(1, min(16, $c / 2))}]
}

### Sends batch lot to process w
proc ::moderne::niveau::envoyerLot {w lot} {
  variable courants
  variable lotReste
  variable lots
  variable debut
  lassign [lindex $lot 0] - - - - source cadence
  envoyer $w "setoption name Rating Source value $source"
  envoyer $w "setoption name Time Control value $cadence"
  envoyer $w "setoption name Review Workers value [ouvriersLot]"
  envoyer $w "toby batch begin"
  foreach r $lot {
    envoyer $w [lindex $r 2]
    envoyer $w [commandeProba $w $r]
  }
  envoyer $w "toby batch end"
  catch {::moderne::journal "Siby level: Toby batch of [llength $lot] moves, [ouvriersLot] workers"}
  set lots($w) 1
  set courants($w) [lindex $lot 0]
  set lotReste($w) [lrange $lot 1 end]
  set debut($w) [clock milliseconds]
  attendre $w
}

### Timer of the request being computed by w (no answer: silence)
proc ::moderne::niveau::attendre {w} {
  variable delai
  variable attentes
  variable courants
  catch {after cancel $attentes($w)}
  set r $courants($w)
  set type [lindex $r 7]
  # (a full answer: 30 s at most, Maia being loaded already; a batch on a
  # busy computer: twice the usual time)
  variable lots
  set d [expr {[info exists lots($w)] ? 2 * $delai : $delai}]
  set attentes($w) [after [expr {$type eq "go" ? 30000 : ($type eq "maia" ? 15000 : $d)}] [list ::moderne::niveau::silence $w $r]]
}

### A block of the batch answered: the next one becomes the current request
### (1), or the batch has no more (0)
proc ::moderne::niveau::lotSuivant {w} {
  variable lotReste
  variable courants
  variable debut
  if {![info exists lotReste($w)] || ![llength $lotReste($w)]} { return 0 }
  set courants($w) [lindex $lotReste($w) 0]
  set lotReste($w) [lrange $lotReste($w) 1 end]
  set debut($w) [clock milliseconds]
  attendre $w
  return 1
}

### "info string toby batch end": w is free again; requests left without an
### answer (a batch error) go back to the queue, asked one by one from now on
proc ::moderne::niveau::finLot {w} {
  variable lots
  variable lotReste
  variable courants
  variable file
  variable attentes
  catch {unset lots($w)}
  set reste {}
  if {$courants($w) ne {}} { lappend reste $courants($w) }
  if {[info exists lotReste($w)]} { lappend reste {*}$lotReste($w) }
  catch {unset lotReste($w)}
  if {[llength $reste]} {
    variable lotsRefuses
    set lotsRefuses($w) 1
    catch {::moderne::journal "Siby level: Toby batch ended with [llength $reste] answers missing: one by one from now on"}
    catch {after cancel $attentes($w)}
    set courants($w) {}
    set file [concat $reste $file]
  }
  after idle ::moderne::niveau::suivant
}

### Requests being computed (all processes)
proc ::moderne::niveau::enCours {} {
  variable courants
  variable lotReste
  set l {}
  foreach w [array names courants] { if {$courants($w) ne {}} { lappend l $courants($w) } }
  foreach w [array names lotReste] { lappend l {*}$lotReste($w) }
  return $l
}

### No answer to a request: an older Toby without "toby likelihood". The
### estimate is turned off until Siby restarts (nothing is shown).
proc ::moderne::niveau::silence {w requete} {
  variable courants
  variable sansReponse
  if {![info exists courants($w)] || $courants($w) ne $requete} { return }
  # (a full answer that does not come: that position is given up, the
  # estimate goes on)
  if {[lindex $requete 7] in {go maia}} {
    envoyer $w stop
    set courants($w) {}
    # (the other full answers are not asked: each would wait 30 s too)
    variable file
    set f {}
    foreach r $file { if {[lindex $r 7] ni {go maia}} { lappend f $r } }
    set file $f
    after idle ::moderne::niveau::suivant
    return
  }
  # (a Toby that stopped answering, or a computer too busy: that process is
  # closed and a new one gets its requests, once per review, before the
  # level is given up; Yosha's bullet review, 2026-11-04)
  variable relances
  if {![info exists relances]} { set relances 0 }
  if {$relances < 1} {
    incr relances
    catch {::moderne::journal "Siby level: no answer from $w to \"[lrange $requete 0 1] [lindex $requete 3] [lindex $requete 7]\": Toby started again"}
    variable lotReste
    variable file
    set reste [list $requete]
    if {[info exists lotReste($w)]} { lappend reste {*}$lotReste($w) }
    fermer $w
    set file [concat $reste $file]
    after idle ::moderne::niveau::suivant
    return
  }
  # (in the log: which process and which request, to tell a real silence
  # from a timer left behind)
  catch {::moderne::journal "Siby level: no answer from $w to \"[lrange $requete 0 1] [lindex $requete 3] [lindex $requete 7]\": level turned off"}
  set sansReponse 1
  prevenir
  arreter
}

### A new Toby process; returns its name (empty: none)
proc ::moderne::niveau::lancer {} {
  variable pipes
  variable courants
  variable numero
  set t [lindex [::moderne::toby::moteursToby] 0]
  if {$t eq {}} { return {} }
  set e [lindex $::engines(list) [lindex $t 0]]
  set ancien [pwd]
  catch {cd [lindex $e 3]}
  # (Maia's threads for this Toby, Toby's advice 2026-10-29: else each
  # process takes every core and several of them only slow one another)
  set avant {}
  foreach v {OMP_NUM_THREADS MKL_NUM_THREADS TOBY_TORCH_THREADS} {
    lappend avant $v [expr {[info exists ::env($v)] ? $::env($v) : "\0"}]
    set ::env($v) [filsMaia]
  }
  # (each process its own Stockfish cache file: one writer per file,
  # Toby 2026-10-30; the panels' Toby keeps toby_sf_cache)
  variable caches
  set k 1
  while {[info exists caches($k)] && [info exists pipes($caches($k))]} { incr k }
  lappend avant TOBY_SF_CACHE_FILE [expr {[info exists ::env(TOBY_SF_CACHE_FILE)] ? $::env(TOBY_SF_CACHE_FILE) : "\0"}]
  catch {set ::env(TOBY_SF_CACHE_FILE) [file nativename [::moderne::toby::fichierCache toby_sf_cache_$k]]}
  set ok [catch {set p [open "| [list [lindex $e 1]] [lindex $e 2][::sibyErreursMoteur]" r+]}]
  if {!$ok} { ::moderne::prioriteBasse $p }
  foreach {v x} $avant { if {$x eq "\0"} { catch {unset ::env($v)} } else { set ::env($v) $x } }
  catch {cd $ancien}
  if {$ok} { return {} }
  set w t[incr numero]
  ::moderne::journal "Siby level: $w started: [lindex $e 0] ([lindex $e 1])"
  set caches($k) $w
  set pipes($w) $p
  set courants($w) {}
  fconfigure $p -buffering line -blocking 0
  fileevent $p readable [list ::moderne::niveau::lire $w]
  envoyer $w uci
  # (Precision Fast and Mode Prediction at once, before anything else: with
  # its defaults (Accurate, Classical) each process of the review started
  # its own Leela, 1 to 2 GB each: four lc0 beside four Toby filled Yosha's
  # memory and the level stalled, 2026-11-04)
  envoyer $w "setoption name Precision value Fast"
  envoyer $w "setoption name Mode value Prediction"
  set appareil Auto
  foreach opt [lindex $e 8] {
    lassign $opt nom val
    # (Toby 2 Product: the level's processes stay on Standard; with
    # Accurate each would put its own network and Leela on the graphics card,
    # up to 4 during a review; the level does no search, Toby 2026-11-20)
    if {$nom in {MultiPV UCI_AnalyseMode {White Rating} {Black Rating} {Stockfish Threads} Threads Precision Mode {Toby 2 Product}}} { continue }
    if {$nom eq "Network Device"} { set appareil $val ; continue }
    envoyer $w "setoption name $nom value $val"
  }
  # (Toby 2's network on the graphics card when there is an NVIDIA one,
  # unless CPU was chosen in Toby's options: Auto follows the product,
  # Standard here, so the processor. A review with 3 processes on a T4:
  # 34.8 s on the processor, 28.5 s on the card, 3.4 GB of its memory,
  # Yosha 2026-11-22: "Carte graphique par défaut". Without a card that
  # answers, Toby goes back to the processor by itself)
  if {$appareil eq "Auto" && ![catch {::moderne::ajout::nvidia} g] && $g eq "1"} { set appareil GPU }
  if {$appareil ne "Auto"} { envoyer $w "setoption name Network Device value $appareil" }
  variable appareils
  set appareils($w) $appareil
  envoyer $w "setoption name Stockfish Threads value 1"
  # (Maia's share of the cores: the environment variables above are not
  # read by Toby's package, the UCI option is)
  envoyer $w "setoption name Maia Threads value [filsMaia]"
  # (no "uciok" for a while: the moves are sent anyway)
  variable delai
  after $delai [list ::moderne::niveau::sansUciok $w $p]
  return $w
}

proc ::moderne::niveau::sansUciok {w p} {
  variable pipes
  variable uciok
  if {![info exists pipes($w)] || $pipes($w) ne $p || [info exists uciok($w)]} { return }
  # (a slow start, e.g. on Windows while the annotation's engines take the
  # cores: the moves are sent anyway, one by one, as before batches; only a
  # move without an answer turns the level off)
  catch {::moderne::journal "Siby level: no uciok from $w yet: moves sent one by one"}
  set uciok($w) 1
  after idle ::moderne::niveau::suivant
}

proc ::moderne::niveau::envoyer {w t} {
  variable pipes
  # (the log: the first requests of each process)
  variable envoisNotes
  if {![info exists envoisNotes($w)]} { set envoisNotes($w) 0 }
  if {$envoisNotes($w) < 12 && ![string match "position *" $t]} {
    incr envoisNotes($w)
    ::moderne::journal "Siby level: $w <- $t"
  }
  if {[info exists pipes($w)]} { catch {puts $pipes($w) $t ; flush $pipes($w)} }
}

proc ::moderne::niveau::lire {w} {
  variable pipes
  variable courants
  variable rappels
  if {![info exists pipes($w)]} { return }
  set p $pipes($w)
  if {[eof $p]} { fermer $w ; after idle ::moderne::niveau::suivant ; return }
  while {[info exists pipes($w)] && [gets $p l] >= 0} {
    # (the log: what the process says about itself, and its errors)
    if {[regexp -nocase {^id name|^info string toby (version|capabilities|maia|timing)|error|warning|unknown command} $l]} {
      ::moderne::journal "Siby level: $w -> [string range $l 0 300]"
    }
    set mots [split [regsub -all {\s+} [string trim $l] " "] " "]
    # (where Maia runs: "info string toby maia device cuda|cpu", Toby
    # 2026-11-02; without it, an older Toby, the processor)
    if {[lrange $mots 0 4] eq {info string toby maia device}} {
      set ::moderne::toby::maiaDevice [lindex $mots 5]
      continue
    }
    if {[lrange $mots 0 3] eq {info string toby version}} {
      variable versionToby [lindex $mots 4]
      continue
    }
    if {[lrange $mots 0 3] eq {info string toby capabilities}} {
      variable capacites
      # (every word: one capability per line, or several on one line, or
      # none: Toby's "core" package, without Maia, Toby 2026-11-18)
      if {![info exists capacites($w)]} { set capacites($w) {} }
      lappend capacites($w) {*}[lrange $mots 4 end]
      continue
    }
    if {[string trim $l] eq "uciok"} {
      variable uciok
      set uciok($w) 1
      # a Toby that says what it can do, without "likelihood" (no Maia):
      # no level of play, at once, rather than 90 s without an answer
      variable capacites
      if {[info exists capacites($w)] && [lsearch -glob $capacites($w) likelihood*] < 0 && "level" ni $capacites($w)} {
        variable sansReponse 1
        variable file {}
        catch {::moderne::journal "Siby level: this Toby has no likelihood (capabilities: $capacites($w)), level of play off"}
      }
      # (in a review, the other processes once this one said it runs no
      # batches)
      variable paralleles
      if {[info exists paralleles] && $paralleles > 1} { after idle ::moderne::niveau::prechauffer }
      after idle ::moderne::niveau::suivant
    }
    if {[lrange $mots 0 4] eq {info string toby level calibration}} {
      lireCalibration $w $mots
      continue
    }
    if {[lrange $mots 0 4] eq {info string toby level display}} {
      lireAffichage $w $mots
      continue
    }
    if {[lrange $mots 0 4] eq {info string toby batch end}} {
      variable lots
      if {[info exists lots($w)]} { finLot $w }
      continue
    }
    # (a borrowed panel's Toby: its own last answers are skipped until
    # "readyok")
    variable pret
    if {[info exists pret($w)] && !$pret($w)} {
      if {[string trim $l] eq "readyok"} { set pret($w) 1 ; after idle ::moderne::niveau::suivant }
      continue
    }
    if {$courants($w) eq {}} { continue }
    # (Toby 1.0 rc2's heartbeat, every second of a long search: thinking,
    # not hung; the timer starts again, up to three times the usual wait)
    if {[lrange $mots 0 3] eq {info string toby alive}} {
      variable debut
      variable delai
      if {[info exists debut($w)] && [clock milliseconds] - $debut($w) < 3 * $delai} { attendre $w }
      continue
    }
    lassign $courants($w) cle cote pos uci source cadence ply type elo
    if {$type in {go maia}} { ligneGo $w $mots ; continue }
    if {[lrange $mots 0 2] eq {info string toby} && [lindex $mots 3] in {maia dist}} {
      set d {}
      foreach {m q} [lrange $mots 5 end] { if {[string is double -strict $q]} { dict set d $m $q } }
      if {[lindex $mots 3] eq "maia"} {
        variable maias
        set maias($cle,$ply) $d
      } else {
        variable tobys
        set tobys($cle,$ply) $d
        variable modeJeu
        if {[info exists modeJeu($cle)] && $modeJeu($cle) eq "level"} {
          # (the head's distribution at the game's rating takes Maia's place
          # for the "!", Yosha 2026-11-18; the thresholds are re-tuned later)
          variable maias
          set maias($cle,$ply) $d
          if {[dict exists $d $uci]} {
            variable probas
            set probas($cle,$ply) [dict get $d $uci]
          }
        }
      }
      continue
    }
    if {[lrange $mots 0 3] eq {info string toby level}} {
      # (Toby 2's level head: answered like "toby likelihood", see there)
      switch -- [lindex $mots 4] {
        error {
          catch {::moderne::journal "Siby level: $w -> [string range $l 0 200]"}
          # (on the graphics card, an error is most likely its memory full
          # (another program, a small card): Toby does not fall back by
          # itself, Toby 2026-11-22. The process goes to the processor and
          # the move is asked again, once; else it would be left out of
          # the level without a word)
          variable appareils
          variable reessais
          if {[lindex $mots 5] ne "stopped" && [info exists appareils($w)] && $appareils($w) eq "GPU" && $courants($w) ne {}} {
            set appareils($w) CPU
            envoyer $w "setoption name Network Device value CPU"
            set k [lrange $courants($w) 0 1],[lindex $courants($w) 6]
            if {![info exists reessais($k)]} {
              set reessais($k) 1
              variable reprendre
              set reprendre($w) $courants($w)
            }
            catch {::moderne::journal "Siby level: $w on the processor from now on, after an error on the graphics card"}
          }
          continue
        }
        unavailable {
          niveauIndisponible $w $l
          continue
        }
        end {
          noterTemps $w $type
          # (a move to ask again after an error on the graphics card: back
          # at the head of the queue, not counted)
          variable reprendre
          if {[info exists reprendre($w)]} {
            variable file
            set file [linsert $file 0 $reprendre($w)]
            unset reprendre($w)
            variable attentes
            catch {after cancel $attentes($w)}
            set courants($w) {}
            after idle ::moderne::niveau::suivant
            continue
          }
          set m [lindex $mots 6]
          if {$type in {compter proba} && $m ne {}} { noterModele $cle $m }
          variable attentes
          catch {after cancel $attentes($w)}
          set courants($w) {}
          set enLot [lotSuivant $w]
          if {[info exists rappels($cle)] && $rappels($cle) ne {}} {
            catch {uplevel #0 $rappels($cle)}
          }
          if {!$enLot} { after idle ::moderne::niveau::suivant }
          continue
        }
      }
      if {[lindex $mots 4] eq $uci && $type eq "compter"} {
        set rs {} ; set ls {}
        foreach {r q} [lrange $mots 5 end] {
          if {[string is integer -strict $r] && [string is double -strict $q]} { lappend rs $r ; lappend ls $q }
        }
        if {[llength $rs] >= 2} { ajouterNiveau $cle $cote $rs $ls }
      }
      continue
    }
    if {[lrange $mots 0 3] ne {info string toby likelihood}} { continue }
    if {[lindex $mots 4] eq "end"} {
      noterTemps $w $type
      if {$type in {compter proba}} { noterModele $cle [expr {[lindex $mots 5] eq "model" && [lindex $mots 6] ne {} ? [lindex $mots 6] : "T5"}] }
      variable attentes
      catch {after cancel $attentes($w)}
      set courants($w) {}
      # (in a batch: the next block is the next request's; the process is
      # free at "toby batch end")
      set enLot [lotSuivant $w]
      if {[info exists rappels($cle)] && $rappels($cle) ne {}} {
        catch {uplevel #0 $rappels($cle)}
      }
      if {!$enLot} { after idle ::moderne::niveau::suivant }
    } elseif {[lindex $mots 4] eq $uci} {
      set rs {} ; set ps {}
      foreach {r q} [lrange $mots 5 end] {
        if {[string is integer -strict $r] && [string is double -strict $q]} { lappend rs $r ; lappend ps $q }
      }
      # (the game's rating: the move's probability for the review, kept
      # apart; the level uses its own ratings only)
      variable opts
      set r {}
      catch {set r [dict get $opts($cle) eloPartie]}
      if {$r ne {}} {
        set k [lsearch -exact $rs $r]
        if {$k >= 0} {
          variable probas
          set probas($cle,$ply) [lindex $ps $k]
          if {$r ni [notesDemandees $cle $cote]} { set rs [lreplace $rs $k $k] ; set ps [lreplace $ps $k $k] }
        }
      }
      if {$type eq "compter" && [llength $rs] >= 2} { ajouter $cle $cote $rs $ps }
    }
  }
}

### A line of Toby's full answer (request type go): the final block's moves
### and the position's expected score; bestmove ends it
proc ::moderne::niveau::ligneGo {w mots} {
  variable courants
  variable bloc
  variable distrib
  variable rappels
  lassign $courants($w) cle cote pos uci source cadence ply
  if {[lrange $mots 0 2] eq {info string toby}} {
    switch -- [lindex $mots 3] {
      begin { set bloc($w) [dict create probs {} es {} esCoups {} maias {}] }
      move {
        if {$bloc($w) ne {}} {
          set i [lsearch -exact $mots prob]
          if {$i > 0} { dict set bloc($w) probs [lindex $mots 4] [lindex $mots [expr {$i + 1}]] }
          set i [lsearch -exact $mots maia]
          if {$i > 0} { dict set bloc($w) maias [lindex $mots 4] [lindex $mots [expr {$i + 1}]] }
          set i [lsearch -exact $mots es]
          if {$i > 0} { dict set bloc($w) esCoups [lindex $mots 4] [lindex $mots [expr {$i + 1}]] }
        }
      }
      position {
        if {$bloc($w) ne {}} {
          set i [lsearch -exact $mots es]
          if {$i > 0} { dict set bloc($w) es [lindex $mots [expr {$i + 1}]] }
        }
      }
    }
    return
  }
  if {[lindex $mots 0] ne "bestmove"} { return }
  noterTemps $w [lindex $courants($w) 7]
  variable attentes
  catch {after cancel $attentes($w)}
  if {$bloc($w) ne {}} {
    if {[lindex $courants($w) 7] eq "maia"} {
      variable maias
      set maias($cle,$ply) [dict get $bloc($w) maias]
    } else {
      set distrib($cle,$ply) [list [dict get $bloc($w) es] [dict get $bloc($w) probs] [dict get $bloc($w) esCoups]]
    }
  }
  set courants($w) {}
  if {[info exists rappels($cle)] && $rappels($cle) ne {}} { catch {uplevel #0 $rappels($cle)} }
  after idle ::moderne::niveau::suivant
}

### Time of each request, by type (likelihood: compter / proba; go)
proc ::moderne::niveau::noterTemps {w type} {
  variable debut
  variable temps
  if {![info exists debut($w)]} { return }
  set t [expr {[clock milliseconds] - $debut($w)}]
  if {$type eq "proba"} { set type compter }
  lappend temps($type) $t
}

### Summary lines of the times since the last call (then forgotten)
proc ::moderne::niveau::tempsResume {} {
  variable temps
  set l {}
  foreach {type nom} {compter "probabilities of the move played (toby likelihood)" go "full answers (go)" maia "Maia alone (candidate good moves)"} {
    if {![info exists temps($type)] || ![llength $temps($type)]} { continue }
    set t [lsort -integer $temps($type)]
    set n [llength $t]
    lappend l "$nom: $n, median [lindex $t [expr {$n / 2}]] ms, slowest [lindex $t end] ms, total [expr {[tcl::mathop::+ {*}$t] / 1000.0}] s"
  }
  array unset temps
  return $l
}

### Process w stops (its move, if any, is lost: counted as done)
proc ::moderne::niveau::fermer {w} {
  variable pipes
  variable courants
  variable attentes
  variable emprunts
  variable pret
  if {![info exists pipes($w)]} { return }
  set p $pipes($w)
  unset pipes($w)
  set courants($w) {}
  catch {after cancel $attentes($w)}
  catch {unset pret($w)}
  variable capacites
  catch {unset capacites($w)}
  foreach v {uciok lots lotReste lotsRefuses} {
    variable $v
    catch {unset ${v}($w)}
  }
  # (a borrowed panel's Toby goes back to its panel, alive: its options are
  # sent again before its next analysis)
  if {[info exists emprunts($w)]} {
    set n $emprunts($w)
    unset emprunts($w)
    catch {puts $p stop ; puts $p "setoption name Provisional Lines value true" ; flush $p}
    catch {fileevent $p readable [list ::uci::processAnalysisInput $n]}
    # the panel's own settings sent back at once (the review had set
    # Precision Fast and 1 Stockfish thread): with Accurate and Classical,
    # Toby starts its Leela in the background now, so it is ready when the
    # user analyses again (Toby session's advice, 2026-11-01)
    catch {
      foreach o [::moderne::toby::optionsVoulues $n] {
        puts $p "setoption name [lindex $o 0] value [lindex $o 1]"
      }
      ::moderne::toby::envoyerPrecision $n [list apply {{p n m} { puts $p $m }} $p]
      flush $p
    }
    return
  }
  catch {fileevent $p readable {}}
  catch {puts $p stop ; puts $p quit ; flush $p}
  catch {close $p}
}

### The estimate was turned off: every view following a game is told
proc ::moderne::niveau::prevenir {} {
  variable rappels
  foreach cle [array names rappels] {
    if {$rappels($cle) ne {}} { catch {uplevel #0 $rappels($cle)} }
  }
}

### Why the estimate is not available (empty: it is)
proc ::moderne::niveau::pourquoi {} {
  if {![llength [::moderne::toby::moteursToby]]} {
    return [T "Le niveau de jeu demande Toby (Outils › Ajouter un moteur)." \
        "The level of play needs Toby (Tools › Add an engine)."]
  }
  return {}
}

### Progress of game cle: {moves done, moves queued}
proc ::moderne::niveau::progression {cle} {
  variable total
  if {![info exists total($cle)]} { return {0 0} }
  return [list [expr {$total($cle) - [restants $cle]}] $total($cle)]
}

### Closes the idle Toby processes beyond the first n
### Toby processes to keep loaded when idle: one, for the next review or
### level of play, unless an analysis panel has a Toby (the review borrows
### that one: a second copy held 800 MB to 1.3 GB for nothing, Yosha
### 2026-11-05)
proc ::moderne::niveau::aGarder {} {
  foreach t [::moderne::toby::moteursToby] {
    set n [lindex $t 0]
    if {[winfo exists .analysisWin$n] && [info exists ::analysis(pipe$n)] && $::analysis(pipe$n) ne {}} { return 0 }
  }
  return 1
}

proc ::moderne::niveau::surplus {n} {
  variable pipes
  variable courants
  set garde 0
  foreach w [lsort [array names pipes]] {
    if {[info exists courants($w)] && $courants($w) ne {}} { incr garde ; continue }
    if {$garde < $n} { incr garde ; continue }
    fermer $w
  }
}

proc ::moderne::niveau::arreter {} {
  variable pipes
  catch {if {[array size pipes]} { puts stderr "Siby level: Toby closed by [lindex [info level -1] 0]" }}
  variable file {}
  foreach w [array names pipes] { fermer $w }
}

### Only game cle among those whose key starts with prefixe: the moves of
### the others still waiting are dropped (e.g. another live game followed)
proc ::moderne::niveau::seulement {prefixe cle} {
  variable file
  set f {}
  foreach r $file {
    if {[string match $prefixe* [lindex $r 0]] && [lindex $r 0] ne $cle} { continue }
    lappend f $r
  }
  set file $f
}

### Moves still to compute for game cle (progress)
proc ::moderne::niveau::restants {cle} {
  variable file
  set n 0
  foreach r $file { if {[lindex $r 0] eq $cle} { incr n } }
  foreach r [enCours] { if {[lindex $r 0] eq $cle} { incr n } }
  return $n
}

################################################################################
### Toby 2's level head ("toby level", docs/INTERFACES.md, Toby's
### docs/SIBY_LEVEL_HEAD.md, 2026-11-19): no Maia. Toby announces
### "level" in its capabilities, then one calibration line per group of time
### controls (classical; rapid and blitz together), keyed by the model's name.
### Per move: "toby level move <uci> [best <cp> played <cp>] [cadence c]
### [dist <elo>]" after the position before the move; the answer is the
### move's natural log-likelihood every 50 points from 1200 to 3000, then an
### end line naming the model. Siby sums each side's curves, S(E), and applies
### the head's own estimators: E_A (the moves only) and E_R (with the player's
### rating). A game is computed with one method from its first move to its
### last; a Toby without "level" keeps "toby likelihood" (T5).
################################################################################

namespace eval ::moderne::niveau {
  variable calNiveau        ;# calNiveau(model,group) = dict field -> values
  array set calNiveau {}
  variable modeleNiveau     ;# modeleNiveau(w) = model of w's calibration lines
  array set modeleNiveau {}
  variable niveauKo         ;# niveauKo(w) = 1: w cannot serve "toby level"
  array set niveauKo {}
  variable niveauIndispo 0  ;# 1: Toby said "toby level unavailable" (all processes)
  variable modeJeu          ;# modeJeu(cle) = level | t5, fixed at the game's first request
  array set modeJeu {}
  variable calJeu           ;# calJeu(cle) = the calibration of the game's group
  array set calJeu {}
  variable sommes           ;# sommes(cle,cote) = S(E) on grille
  array set sommes {}
}

### The head's group of a Toby time control
proc ::moderne::niveau::groupeNiveau {cadence} {
  return [expr {[string tolower $cadence] eq "classical" ? "classical" : "rapidblitz"}]
}

### "info string toby level calibration model M group G grid … use_er …"
### (one line per group; the numbers are read, never written in Siby: they
### change with each training of the head)
proc ::moderne::niveau::lireCalibration {w mots} {
  variable calNiveau
  variable modeleNiveau
  variable niveauKo
  if {[lindex $mots 5] eq "error"} {
    set niveauKo($w) 1
    catch {::moderne::journal "Siby level: $w has no level head calibration: toby likelihood used"}
    return
  }
  set cles {model group grid ea_tau ea_mean ea_sd ea_corr ea_coef knots bounds er_tau er_s er_drift c_er c_ea sd_scale use_ea use_er
            ea_stretch ea_coef_review ea_stretch_review ea_cap_high ea_cap_low}
  set d [dict create]
  set k {}
  foreach m [lrange $mots 5 end] {
    # (a field this Siby does not know yet, "word_word": a field of its own,
    # never words added to the field before it; values are numbers or
    # single words, "level", "spl", "toby2-level-v1")
    if {$m in $cles || [regexp {^[a-z]+(_[a-z0-9]+)+$} $m]} { set k $m ; dict set d $k {} ; continue }
    if {$k ne {}} { dict lappend d $k $m }
  }
  foreach c {model group ea_tau ea_mean ea_sd ea_coef knots bounds} {
    if {![dict exists $d $c] || [dict get $d $c] eq {}} {
      catch {::moderne::journal "Siby level: $w calibration line without $c, ignored"}
      return
    }
  }
  set modele [dict get $d model]
  # (the display fields of the same model and group, from their own line,
  # whichever came first)
  variable affNiveau
  if {[info exists affNiveau($modele,[dict get $d group])]} { set d [dict merge $d $affNiveau($modele,[dict get $d group])] }
  set calNiveau($modele,[dict get $d group]) $d
  set modeleNiveau($w) $modele
  catch {::moderne::journal "Siby level: $w level head $modele, group [dict get $d group]"}
}

### Does process w serve "toby level"?
proc ::moderne::niveau::niveauServi {w} {
  variable capacites
  variable niveauKo
  variable niveauIndispo
  if {$niveauIndispo || [info exists niveauKo($w)]} { return 0 }
  return [expr {[info exists capacites($w)] && "level" in $capacites($w)}]
}

### The calibration of group g for process w's model ({} if not read yet)
proc ::moderne::niveau::calibrationNiveau {w g} {
  variable calNiveau
  variable modeleNiveau
  if {![info exists modeleNiveau($w)] || ![info exists calNiveau($modeleNiveau($w),$g)]} { return {} }
  return $calNiveau($modeleNiveau($w),$g)
}

### Is game cle computed by the level head? Fixed at its first request to
### process w (the same method from the first move to the last)
proc ::moderne::niveau::modeNiveau {w cle cadence} {
  variable modeJeu
  if {[info exists modeJeu($cle)]} { return [expr {$modeJeu($cle) eq "level"}] }
  set mode t5
  if {[niveauServi $w]} {
    set mode level
    # (a group switched back to Toby 1.0 in the calibration file)
    set cal [calibrationNiveau $w [groupeNiveau $cadence]]
    if {$cal ne {} && [dict exists $cal use_ea] && [dict get $cal use_ea] ne "level"} { set mode t5 }
  }
  set modeJeu($cle) $mode
  catch {::moderne::journal "Siby level: game $cle by [expr {$mode eq "level" ? "Toby's level head" : "toby likelihood"}]"}
  return [expr {$mode eq "level"}]
}

proc ::moderne::niveau::estNiveau {cle} {
  variable modeJeu
  return [expr {[info exists modeJeu($cle)] && $modeJeu($cle) eq "level"}]
}

### The "toby level" command of request r for process w
proc ::moderne::niveau::commandeNiveau {w r} {
  lassign $r cle cote pos uci source cadence ply type elo
  variable opts
  foreach o {eloDist eloPartie} {
    if {$elo eq {} && [info exists opts($cle)] && [dict exists $opts($cle) $o]} {
      set elo [dict get $opts($cle) $o]
    }
  }
  set c "toby level move $uci[valeursBilan $pos $uci $ply] cadence [string tolower $cadence]"
  if {[string is integer -strict $elo] && $elo > 0} { append c " dist $elo" }
  return $c
}

### Does request r wait for the review's Stockfish values? A level-head move
### of the game being annotated, while the annotation runs and has not
### valued its position yet (it is sent then, best and played; the
### annotation over, or another game: sent without, Toby searches itself)
proc ::moderne::niveau::attendValeurs {w r} {
  lassign $r cle cote pos uci source cadence ply type
  if {$type ne "compter" || ![string match bilan:* $cle]} { return 0 }
  if {![info exists ::moderne::bilan::annotFinie] || $::moderne::bilan::annotFinie} { return 0 }
  if {![info exists ::moderne::bilan::cle] || $::moderne::bilan::cle ne $cle} { return 0 }
  variable modeJeu
  if {[info exists modeJeu($cle)] ? $modeJeu($cle) ne "level" : ![niveauServi $w]} { return 0 }
  if {![info exists ::moderne::oracle::positions]} { return 0 }
  if {![::moderne::oracle::dansPlage $ply]} { return 0 }
  return [expr {[valeursBilan $pos $uci $ply] eq {}}]
}

### The review's Stockfish values of ply (best move, move played), mover's
### point of view, mates ±10000: " best <cp> played <cp>", or {} when the
### annotation has not reached the position yet (Toby then searches it
### itself) or is about another game
proc ::moderne::niveau::valeursBilan {pos uci ply} {
  set o ::moderne::oracle
  if {![info exists ${o}::positions] || ![info exists ${o}::evals($ply)] || ![info exists ${o}::scores($ply)]} { return {} }
  set positions [set ${o}::positions]
  if {$ply >= [llength $positions] || [lindex $positions $ply 1] ne $uci} { return {} }
  # (the same game: the moves before ply are the annotation's)
  set avant {}
  regexp { moves (.*)$} $pos -> avant
  set siens {}
  for {set k 0} {$k < $ply} {incr k} { lappend siens [lindex $positions $k 1] }
  if {[join $avant] ne [join $siens]} { return {} }
  set scores [set ${o}::scores($ply)]
  if {![dict exists $scores $uci]} { return {} }
  set best [lindex [set ${o}::evals($ply)] 0]
  set joue [dict get $scores $uci]
  if {![string is integer -strict $best] || ![string is integer -strict $joue]} { return {} }
  if {[lindex $positions $ply 3] eq "black"} { set best [expr {-$best}] ; set joue [expr {-$joue}] }
  return " best $best played $joue"
}

### Adds a move's curve (ratings rs, natural log-likelihoods ls) to side
### cote's S(E)
proc ::moderne::niveau::ajouterNiveau {cle cote rs ls} {
  variable sommes
  variable compte
  variable grille
  if {![info exists sommes($cle,$cote)]} { return }
  set l {}
  foreach v $sommes($cle,$cote) q [interpoler $rs $ls $grille] { lappend l [expr {$v + $q}] }
  set sommes($cle,$cote) $l
  incr compte($cle,$cote)
}

### "toby level unavailable (…)": the games begun with the head start again
### with "toby likelihood"
proc ::moderne::niveau::niveauIndisponible {w l} {
  variable niveauIndispo 1
  variable courants
  variable file
  variable modeJeu
  catch {::moderne::journal "Siby level: $w -> [string range $l 0 200]: toby likelihood used"}
  set r $courants($w)
  set courants($w) {}
  variable attentes
  catch {after cancel $attentes($w)}
  foreach cle [array names modeJeu] {
    if {$modeJeu($cle) eq "level"} { recommencer $cle }
  }
  after idle ::moderne::niveau::suivant
}

### Game cle computed again from its first move (its method chosen again)
proc ::moderne::niveau::recommencer {cle} {
  variable infos
  variable rappels
  variable opts
  variable dejaUcis
  variable dejaDepart
  if {![info exists infos($cle)] || ![info exists dejaUcis($cle)]} { return }
  lassign $infos($cle) source cadence eloB eloN
  set r $rappels($cle)
  set o [expr {[info exists opts($cle)] ? $opts($cle) : {}}]
  set u $dejaUcis($cle)
  set d [expr {[info exists dejaDepart($cle)] ? $dejaDepart($cle) : "startpos"}]
  oublier $cle
  suivre $cle $eloB $eloN $source $cadence $r $o
  coups $cle $d $u
}

### The calibration of game cle: the one of its answers' model and group
proc ::moderne::niveau::calibrationJeu {cle} {
  variable calJeu
  variable calNiveau
  variable modeles
  variable infos
  if {[info exists calJeu($cle)]} { return $calJeu($cle) }
  if {![info exists modeles($cle)] || ![info exists infos($cle)]} { return {} }
  set g [groupeNiveau [lindex $infos($cle) 1]]
  set m [lindex $modeles($cle) 0]
  if {![info exists calNiveau($m,$g)]} { return {} }
  # (kept with the game: a review read back later needs no running Toby)
  set calJeu($cle) $calNiveau($m,$g)
  return $calJeu($cle)
}

### basis(r) = 1, r', (r' - k1)+, (r' - k2)+, (r' - k3)+ with r' = r
### bounded
proc ::moderne::niveau::baseNiveau {r cal} {
  lassign [dict get $cal bounds] lo hi
  set r [expr {min(max(double($r), $lo), $hi)}]
  set b [list 1.0 $r]
  foreach k [dict get $cal knots] { lappend b [expr {max(0.0, $r - $k)}] }
  return $b
}

proc ::moderne::niveau::produit {a b} {
  set s 0.0
  foreach x $a y $b { if {$x ne {} && $y ne {}} { set s [expr {$s + $x * $y}] } }
  return $s
}

### Posterior mean and spread of S(E) / tau with a normal prior N(mu, sd)
### (sd "flat": no prior)
proc ::moderne::niveau::posterieure {S tau mu sd} {
  variable grille
  set L {}
  foreach e $grille v $S {
    set x [expr {$v / double($tau)}]
    if {$sd ne "flat"} { set x [expr {$x - 0.5 * (($e - $mu) / double($sd)) ** 2}] }
    lappend L $x
  }
  set m [tcl::mathfunc::max {*}$L]
  set s 0.0 ; set s1 0.0 ; set s2 0.0
  foreach e $grille v $L {
    set p [expr {exp($v - $m)}]
    set s [expr {$s + $p}]
    set s1 [expr {$s1 + $p * $e}]
    set s2 [expr {$s2 + $p * $e * $e}]
  }
  set x [expr {$s1 / $s}]
  return [list $x [expr {sqrt(max(0.0, $s2 / $s - $x * $x))}]]
}

### Estimate of side cote of game cle by the level head: {rating sd moves}
### or {}; E_R (with the player's rating) where Siby uses the ratings
### (over-the-board games, rated sides), else E_A (the moves only)
proc ::moderne::niveau::estimationNiveau {cle cote brut} {
  variable sommes
  variable compte
  variable infos
  if {![info exists sommes($cle,$cote)]} { return {} }
  set cal [calibrationJeu $cle]
  if {$cal eq {}} { return {} }
  set n $compte($cle,$cote)
  set R 0
  catch {set R [lindex $infos($cle) [expr {$cote eq "B" ? 2 : 3}]]}
  set k [expr {[dict exists $cal sd_scale] ? [dict get $cal sd_scale] : 1.0}]
  set er [expr {[avecElo $cle $cote] && [string is integer -strict $R] && $R > 0 && [dict exists $cal er_tau] && [dict exists $cal er_drift] \
                && (![dict exists $cal use_er] || [dict get $cal use_er] eq "level")}]
  if {$er} {
    set s [dict get $cal er_s]
    lassign [posterieure $sommes($cle,$cote) [dict get $cal er_tau] $R $s] m sx
    if {$brut} { return [list [expr {round($m)}] [expr {round($sx)}] $n] }
    set e [expr {$m - [produit [dict get $cal er_drift] [baseNiveau $R $cal]]}]
    return [list [expr {round($e)}] [expr {round($k * $sx)}] $n r]
  }
  lassign [posterieure $sommes($cle,$cote) [dict get $cal ea_tau] [dict get $cal ea_mean] [dict get $cal ea_sd]] x sx
  if {$brut} { return [list [expr {round($x)}] [expr {round($sx)}] $n] }
  lassign [eaDepuisX $cal $x [string match bilan:* $cle]] - e pente
  # (4th: "a", from the moves alone with Toby's display ends (ea_cap_high,
  # ea_cap_low); none without them, as before)
  set source {}
  if {[dict exists $cal ea_cap_high] && [dict exists $cal ea_cap_low]} {
    set source a
    variable plafondA [dict get $cal ea_cap_high]
    variable plancherA [dict get $cal ea_cap_low]
  }
  set v [expr {round($e)}]
  # (the ends decided on the value itself, not on its rounding: 2499.6
  # stays a number, 1599.6 is under 1600)
  if {$source eq "a"} {
    if {$e < $plafondA && $v >= $plafondA} { set v [expr {$plafondA - 1}] }
    if {$e < $plancherA && $v >= $plancherA} { set v [expr {$plancherA - 1}] }
  }
  return [list $v [expr {round(abs($pente) * $sx * $k)}] $n $source]
}

### "info string toby level display model M group G ea_stretch … ea_cap_low
### 1600" (Toby 2026-11-22: the E_A display fields on a line of their own,
### the calibration lines unchanged for the Sibys already out): kept by
### model and group, merged into that calibration
proc ::moderne::niveau::lireAffichage {w mots} {
  variable affNiveau
  variable calNiveau
  set d [dict create]
  set k {}
  foreach m [lrange $mots 5 end] {
    if {$m in {model group} || [regexp {^[a-z]+(_[a-z0-9]+)+$} $m]} { set k $m ; dict set d $k {} ; continue }
    if {$k ne {}} { dict lappend d $k $m }
  }
  if {![dict exists $d model] || ![dict exists $d group]} {
    catch {::moderne::journal "Siby level: $w display line without model or group, ignored"}
    return
  }
  set c [dict get $d model],[dict get $d group]
  set d [dict remove $d model group]
  set affNiveau($c) $d
  if {[info exists calNiveau($c)]} { set calNiveau($c) [dict merge $calNiveau($c) $d] }
  catch {::moderne::journal "Siby level: $w display fields for $c: [dict keys $d]"}
}

### E_A from the posterior mean x (Toby's frozen display fields,
### ea_display_fields.json 2026-11-22): E_A = coef · basis(x), with
### ea_coef_review in a review when present; then, when Toby sends a
### stretch, shown = clip(ea_mean + k (E_A - ea_mean), bounds), k =
### ea_stretch_review in a review, ea_stretch otherwise. Without those
### fields, as before. {E_A shown slope}
proc ::moderne::niveau::eaDepuisX {cal x revue} {
  set c [dict get $cal ea_coef]
  if {$revue && [dict exists $cal ea_coef_review] && [llength [dict get $cal ea_coef_review]] == [llength $c]} { set c [dict get $cal ea_coef_review] }
  if {[dict exists $cal ea_corr] && [dict get $cal ea_corr] eq "lin"} {
    set e [expr {[lindex $c 0] + [lindex $c 1] * $x}]
    set pente [lindex $c 1]
  } else {
    set e [produit $c [baseNiveau $x $cal]]
    # (the slope at x, inside the bounds)
    lassign [dict get $cal bounds] lo hi
    set xb [expr {min(max($x, $lo), $hi)}]
    set pente [lindex $c 1]
    foreach kn [dict get $cal knots] ck [lrange $c 2 end] { if {$xb > $kn} { set pente [expr {$pente + $ck}] } }
  }
  set cleK [expr {$revue ? "ea_stretch_review" : "ea_stretch"}]
  if {![dict exists $cal $cleK] || ![string is double -strict [dict get $cal $cleK]]} { return [list $e $e $pente] }
  set k [dict get $cal $cleK]
  set m [dict get $cal ea_mean]
  lassign [dict get $cal bounds] lo hi
  set montre [expr {min(max($m + $k * ($e - $m), $lo), $hi)}]
  return [list $e $montre [expr {$pente * $k}]]
}

### End Siby

### Saves what is known of game cle (all its moves computed) in file f, to
### be read back by charger under another key (a review opened later)
proc ::moderne::niveau::sauver {cle f} {
  variable faits
  variable infos
  variable opts
  variable total
  if {![info exists faits($cle)] || [restants $cle] > 0} { return 0 }
  set d [dict create version 1 faits $faits($cle) infos $infos($cle) \
      opts [expr {[info exists opts($cle)] ? $opts($cle) : {}}] \
      total [expr {[info exists total($cle)] ? $total($cle) : 0}]]
  foreach t {modeJeu calJeu modeles} {
    variable $t
    if {[info exists ${t}($cle)]} { dict set d $t [set ${t}($cle)] }
  }
  foreach t {notes compte probas distrib maias tobys sommes} {
    variable $t
    set l {}
    foreach k [array names $t $cle,*] { lappend l [string range $k [string length $cle,] end] [set ${t}($k)] }
    dict set d $t $l
  }
  file mkdir [file dirname $f]
  set c [open $f.part w]
  fconfigure $c -encoding utf-8
  puts -nonewline $c $d
  close $c
  file rename -force $f.part $f
  return 1
}

### Reads file f (sauver) as game cle, with rappel; 0 if unreadable
proc ::moderne::niveau::charger {cle f {rappel {}}} {
  if {[catch {
    set c [open $f r]
    fconfigure $c -encoding utf-8
    set d [read $c]
    close $c
  }] || [catch {dict get $d version}]} { return 0 }
  oublier $cle
  variable faits
  variable infos
  variable opts
  variable total
  variable rappels
  set faits($cle) [dict get $d faits]
  set infos($cle) [dict get $d infos]
  set opts($cle) [dict get $d opts]
  set total($cle) [dict get $d total]
  set rappels($cle) $rappel
  foreach t {notes compte probas distrib maias tobys sommes} {
    variable $t
    if {![dict exists $d $t]} { continue }
    foreach {k v} [dict get $d $t] { set ${t}($cle,$k) $v }
  }
  foreach t {modeJeu calJeu modeles} {
    variable $t
    if {[dict exists $d $t]} { set ${t}($cle) [dict get $d $t] }
  }
  return 1
}
