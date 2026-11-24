
###
### Siby: integration of Toby (UCI engine predicting human moves)
###
### For each legal move, Toby gives the probability that a player of the
### given rating plays it, and the win / draw / loss outcome of that move
### between players of those ratings. Its "bestmove" is the most likely move, not the best one.
###
### This module:
###   - recognizes Toby (engine name, or its "Rating Source" and
###     "Move Model" options);
###   - sends it before each "go": Display Full, White/Black Rating,
###     Rating Source, Time Control (derived from the PGN, editable in
###     "Toby settings"), Move Model Auto, MultiPV 500, UCI_ShowWDL true,
###     Mode Prediction (in analysis: the most likely move);
###   - before a new position: stop, waits for "bestmove", then position
###     and go (tcl/tools/analysis.tcl);
###   - reads the "info string toby begin … end" blocks and replaces the whole
###     table at each "end" (never merges two blocks); stages
###     1 and 2 and non-final blocks are shown grayed out;
###   - displays: Move | Toby % | win/draw/loss bar | expected score %,
###     under the header "Toby — 2650 vs 2700, FIDE, Classical"; the move played
###     in the game is highlighted; a click on a row plays the move;
###   - feeds the evaluation bar with "toby position" (converted to
###     White's point of view);
###   - ignores standard MultiPV lines (depth, nodes, speed: mere
###     progress markers).
###

namespace eval ::moderne::toby {
  variable hybride 0   ;# the Toby in use offers Precision Hybrid (Toby 1.0, GPU package)
  variable est         ;# est(n): 1 if engine n is Toby
  array set est {}
  variable bloc        ;# bloc(n): {etape final lignes position} being received
  array set bloc {}
  variable tableau     ;# tableau(n): last complete block
  array set tableau {}
  variable attente     ;# attente(n): time of the "stop" (waiting for bestmove)
  array set attente {}
  variable ignorer     ;# ignorer(n): lines of a stopped search, to be ignored
  array set ignorer {}
  variable reglages    ;# reglages(game key): dict of the settings for that game
  array set reglages {}
  variable cotePlateau ;# cotePlateau(n): side to move in the analyzed position
  array set cotePlateau {}
  variable form        ;# variables of the "Toby settings" window
  array set form {}
  variable jeu         ;# settings of "Play against Toby" (remembered, options.dat)
  if {![array exists jeu]} { array set jeu {} }
  variable fenGo       ;# fenGo(n): position and settings of the last "go"
  array set fenGo {}
  variable memoire     ;# memoire(fen|white|black|time control): last complete
  array set memoire {} ;#   block of Toby there (reused by the game annotation)
}

### Toby's complete analysis of a position, if one was received this session
### for those ratings and that time control ({} otherwise)
proc ::moderne::toby::analyseConnue {fen blanc noir cadence} {
  variable memoire
  set k "[join [lrange [split $fen] 0 3]]|$blanc|$noir|$cadence"
  return [expr {[info exists memoire($k)] ? $memoire($k) : {}}]
}

proc ::moderne::toby::T {fr en} { return [::moderne::tr $fr $en] }

### Is engine n Toby?
proc ::moderne::toby::estToby {n} {
  variable est
  if {[info exists est($n)]} { return $est($n) }
  set oui 0
  catch {
    if {[string match -nocase *toby* [lindex $::engines(list) $n 0]]} { set oui 1 }
  }
  if {!$oui && [info exists ::analysis(uciOptions$n)]} {
    set noms {}
    foreach opt $::analysis(uciOptions$n) { lappend noms [lindex $opt 0] }
    if {"Rating Source" in $noms && "Move Model" in $noms} { set oui 1 }
  }
  # (only remember once the engine's options are known)
  if {$oui || ([info exists ::analysis(uciOptions$n)] && [llength $::analysis(uciOptions$n)])} { set est($n) $oui }
  return $oui
}

### Precision (Toby option, Accurate | Fast): Accurate = Leela calculates,
### in Classical with an NVIDIA card, otherwise the same as Fast; Fast =
### Stockfish calculates, guided by Leela's raw policy (one Leela evaluation
### per move, GPU or CPU), Stockfish alone only when Leela is missing or fails
proc ::moderne::toby::envoyerPrecision {n {envoi ::sendToEngine} {analyse 1}} {
  set p Accurate
  if {[info exists ::moderne::toby::precision]} {
    if {$::moderne::toby::precision eq "Fast"} { set p Fast }
    # (Hybrid: only a Toby that offers it, Toby 1.0 with the GPU package)
    if {$::moderne::toby::precision eq "Hybrid" && $::moderne::toby::hybride} { set p Hybrid }
  }
  # Toby 2 has no Precision (Toby 1.0's option, ignored): its product,
  # Accurate where Toby 2 lists it (full package, NVIDIA card, lc0), else
  # Standard; only in the analysis panel (one Leela on the card), Standard
  # in games (Siby beta 8 sent only Precision: Toby 2 stayed on Standard
  # with an NVIDIA card, Yosha 2026-11-23)
  if {[aOption $n "Toby 2 Product"]} {
    set t2 Standard
    if {$analyse && $p eq "Accurate" && [info exists ::moderne::toby::t2Accurate($n)] && $::moderne::toby::t2Accurate($n)} { set t2 Accurate }
    catch {$envoi $n "setoption name Toby 2 Product value $t2"}
    variable produit
    variable produitRaison
    if {!$analyse} { return }
    # (Toby's refusal, said once per process, stays until it restarts)
    if {![info exists produitRaison($n)] || $produitRaison($n) eq {} || $t2 eq "Standard"} {
      set produit($n) $t2
      set produitRaison($n) {}
    }
    return
  }
  catch {$envoi $n "setoption name Precision value $p"}
}
### Toby 2's product for the analysis panel: Accurate where Toby 2 lists
### it and Siby's Precision is Accurate, else Standard ({} for another engine)
proc ::moderne::toby::produitVoulu {n} {
  if {![aOption $n "Toby 2 Product"]} { return {} }
  set p Accurate
  if {[info exists ::moderne::toby::precision] && $::moderne::toby::precision eq "Fast"} { set p Fast }
  if {$p eq "Accurate" && [info exists ::moderne::toby::t2Accurate($n)] && $::moderne::toby::t2Accurate($n)} { return Accurate }
  return Standard
}

### Before a go: when Toby 2's product changes (engine start, setting
### changed, review giving the engine back), "setoption … Toby 2 Product",
### then "isready" (Toby 2 prepares Accurate there, the Toby session
### 2026-11-23); 1 when the go must wait for readyok
proc ::moderne::toby::preparerProduit {n} {
  variable produitPrepare
  set p [produitVoulu $n]
  if {$p eq {}} { return 0 }
  if {[info exists produitPrepare($n)] && $produitPrepare($n) eq $p} { return 0 }
  set produitPrepare($n) $p
  ::sendToEngine $n "setoption name Toby 2 Product value $p"
  set ::analysis(waitForReadyOk$n) 1
  ::sendToEngine $n isready
  return 1
}

### A review frees the graphics card: an analysis panel's Toby 2 in
### Accurate (its Leela on the card) is closed for the review, so that the
### level's Toby processes get the card's memory (1 process instead of 3,
### and 17.5 s to reload it on Standard when it was borrowed, Yosha's
### siby.log 2026-11-23); it comes back afterwards, analysing again if it
### was (the Toby session's choice). Called after the panels are paused.
proc ::moderne::toby::libererCarte {} {
  variable horsCarte
  array unset horsCarte
  set fermes 0
  foreach f [winfo children .] {
    if {![regexp {^\.analysisWin([0-9]+)$} $f -> n]} { continue }
    if {![info exists ::moderne::toby::produitPrepare($n)] || $::moderne::toby::produitPrepare($n) ne "Accurate"} { continue }
    set analysait [info exists ::moderne::occupation::enPause($n)]
    unset -nocomplain ::moderne::occupation::enPause($n)
    set horsCarte($n) $analysait
    catch {::moderne::journal "Siby: Toby 2 Accurate (engine $n) closed for the review, back afterwards"}
    catch {::moderne::occupation::fermerAnalyse $n}
    incr fermes
  }
  if {$fermes} {
    catch {::moderne::nsb::annonce [T "Toby (Précis) quitte l'analyse pendant le bilan (il reviendra après)" \
        "Toby (Accurate) leaves the analysis during the review (it will come back afterwards)"] -1}
    after 3500 {catch ::moderne::nsb::finAnnonce}
    # (its process and Leela ended, about 0.3 s on Windows, before the
    # card's free memory is read for the level's share)
    update
    after 1500
  }
  return $fermes
}

### End of the review: the Toby closed by libererCarte comes back
proc ::moderne::toby::rendreCarte {} {
  variable horsCarte
  foreach n [array names horsCarte] {
    set analysait $horsCarte($n)
    unset horsCarte($n)
    if {![winfo exists .analysisWin$n]} { catch {makeAnalysisWin $n} }
    if {$analysait} { after 1500 [list ::moderne::sante::reprendre $n 0] }
  }
}

### What engine n's option line offers: Precision Hybrid (Toby 1.0, GPU
### package), Toby 2 Product Accurate (listed only where it can run: an
### NVIDIA card and the full package)
proc ::moderne::toby::noterOption {n nom ligne} {
  if {$nom eq "Precision" && [regexp {\mvar Hybrid\M} $ligne]} { set ::moderne::toby::hybride 1 }
  if {$nom eq "Toby 2 Product"} { set ::moderne::toby::t2Accurate($n) [regexp {\mvar Accurate\M} $ligne] }
}

### Does engine n offer the UCI option nom?
proc ::moderne::toby::aOption {n nom} {
  if {![info exists ::analysis(uciOptions$n)]} { return 0 }
  foreach opt $::analysis(uciOptions$n) {
    if {[string equal -nocase [lindex $opt 0] $nom]} { return 1 }
  }
  return 0
}

### Forgets what we know about engine n (window closed, other engine)
proc ::moderne::toby::oublier {n} {
  variable est
  variable bloc
  variable tableau
  variable attente
  variable ignorer
  variable reponse
  variable analyse
  variable produit
  variable produitRaison
  variable t2Accurate
  variable produitPrepare
  variable attentePrep
  foreach v {est bloc tableau attente ignorer reponse analyse produit produitRaison t2Accurate produitPrepare attentePrep} { catch {unset ${v}($n)} }
  catch {.main.board.bd delete toby}
}

################################################################################
### Per-game settings (prefilled from the PGN)
################################################################################

proc ::moderne::toby::clePartie {} {
  return "[sc_base current]:[sc_game number]"
}

### UCI "position" of the current position with the game's move history
### (Toby's Maia uses the previous positions; any UCI engine accepts it):
### "startpos moves …" or "fen <start> moves …"; the bare FEN when the line
### holds a null move. Extra moves (ponder) are appended.
proc ::moderne::toby::positionPartie {{extra {}}} {
  set coups {}
  catch {set coups [sc_game moves coord]}
  if {$coups eq {} || [lsearch -exact $coups 0000] >= 0} {
    set p "position fen [sc_pos fen]"
    if {$extra ne {}} { append p " moves $extra" }
    return $p
  }
  lappend coups {*}$extra
  if {[sc_game startBoard]} { return "position fen [sc_game startPos] moves [join $coups]" }
  return "position startpos moves [join $coups]"
}

### Time control (Classical | Rapid | Blitz) from the TimeControl header:
### estimated duration = base + 40 × increment (< 600 s: Blitz, < 3600 s: Rapid)
proc ::moderne::toby::cadenceDe {tc} {
  set tc [string trim $tc]
  if {$tc in {{} - ? *}} { return {} }
  # "40/7200:3600" (several periods): the first one counts
  set periode [lindex [split $tc :] 0]
  if {[regexp {^(\d+)/(\d+)} $periode -> coups secondes]} {
    set base $secondes ; set inc 0
  } elseif {[regexp {^(\d+)(?:\+(\d+(?:\.\d+)?))?$} $periode -> base inc]} {
    if {$inc eq {}} { set inc 0 }
  } else {
    return {}
  }
  set duree [expr {$base + 40 * $inc}]
  if {$duree < 600} { return Blitz }
  if {$duree < 3600} { return Rapid }
  return Classical
}

### The current game's TimeControl header in seconds ("5400+30"). Lichess
### broadcasts copy the organisers' "90+30" (minutes + seconds), while a
### PGN counts seconds: 90+30 read as seconds made a classical game rapid
### (Yosha, 2026-11-04). The base is taken as minutes when the first clock
### of the game is far above it (1:30:08 against "90"), or, without clocks,
### for a broadcast with a base under 10 "minutes"
proc ::moderne::toby::tcPartie {} {
  set tc {}
  catch {regexp {TimeControl "([^"]*)"} [sc_game tags get Extra] -> tc}
  set tc [string trim $tc]
  if {$tc in {{} - ? *}} { return $tc }
  set horloge {}
  catch {
    foreach {num v} [sc_game values clk] {
      set horloge [::moderne::direct::secondes $v]
      break
    }
  }
  set diffusion 0
  catch {set diffusion [string match -nocase *lichess.org/broadcast* "[sc_game tags get Site] [sc_game tags get Extra]"]}
  # (decided on the first period, for all of them)
  set minutes 0
  if {[regexp {^(?:\d+/)?(\d+)} $tc -> base]} {
    if {[string is double -strict $horloge] && $horloge > 0} {
      set minutes [expr {$horloge >= 20 * $base && $horloge <= 70 * $base}]
    } elseif {$diffusion && $base < 180} {
      # (organisers' minutes: 90, 120, 45… under 180; from 180 on, seconds:
      # "180+2" is a blitz, it was read as 180 minutes, a classical game,
      # Yosha 2026-11-10, Carlsen - Giri, Total Chess blitz)
      set minutes 1
    }
  }
  if {!$minutes} { return $tc }
  set r {}
  foreach p [split $tc :] {
    if {[regexp {^((?:\d+/)?)(\d+)((?:\+[0-9.]+)?)$} $p -> coups base inc]} {
      set p "$coups[expr {$base * 60}]$inc"
    }
    lappend r $p
  }
  return [join $r :]
}

### Settings derived from the PGN of the current game
proc ::moderne::toby::depuisPgn {} {
  set eloB 0 ; set eloN 0 ; set site {} ; set tc {}
  catch {set eloB [sc_game tags get WhiteElo]}
  catch {set eloN [sc_game tags get BlackElo]}
  catch {set site [sc_game tags get Site]}
  set tc [tcPartie]
  # (older games against Toby: only SCID's "Timemode" header, in minutes)
  if {$tc eq {}} {
    catch {
      if {[regexp {Timemode "Time\+Bonus ([0-9.]+)\+([0-9.]+)/} [sc_game tags get Extra] -> m i]} {
        set tc "[expr {int(round($m * 60))}]+[expr {int($i)}]"
      }
    }
  }
  if {![string is integer -strict $eloB]} { set eloB 0 }
  if {![string is integer -strict $eloN]} { set eloN 0 }
  # Only one rating given: it applies to both
  if {$eloB == 0 && $eloN > 0} { set eloB $eloN }
  if {$eloN == 0 && $eloB > 0} { set eloN $eloB }
  set cadence [cadenceDe $tc]
  # (no time control: the database's flags, Gaby's or Siby's downloads:
  # 2 "Rapid", 3 "Blitz"; 40 % of Gaby's rapid and blitz games have no
  # TimeControl, Yosha 2026-11-11)
  if {$cadence eq {}} { set cadence [cadenceDrapeaux] }
  # A game played on Lichess: its URL (8 characters) and a time control,
  # or a correspondence game ("-"); a study, an imported game or a
  # broadcast keeps FIDE ratings (their Elo read as Lichess ones and their
  # time control as blitz before, Yosha 2026-11-11)
  set lichess [regexp -nocase {^https?://(www\.)?lichess\.org/[A-Za-z0-9]{8}$} [string trim $site]]
  set event {}
  catch {set event [sc_game tags get Event]}
  if {$lichess && $cadence eq {} && !($tc eq "-" && [regexp -nocase {correspondence|unlimited} $event])} { set lichess 0 }
  if {$lichess} {
    if {$cadence eq {}} { set cadence Classical }
    set source "Lichess $cadence"
  } elseif {[string match -nocase *chess.com* $site] && [cadenceDe $tc] ne {}} {
    # (Chess.com: no "Classical" rating; daily games as rapid)
    set source "Chess.com [expr {$cadence eq "Blitz" ? "Blitz" : "Rapid"}]"
  } else {
    if {$cadence eq {}} { set cadence Classical }
    set source FIDE
  }
  return [dict create blanc $eloB noir $eloN source $source cadence $cadence fleches 0 bullet [estBullet $tc]]
}

### Time control from the database's flags of the current game ({} if
### none): flag 2 named "Rapid"/"Rapide", flag 3 "Blitz" (Gaby, online
### downloads); rapid first, as Gaby counts it (nsbMalusTop)
proc ::moderne::toby::cadenceDrapeaux {} {
  set g 0
  catch {set g [sc_game number]}
  if {!$g} { return {} }
  foreach {num motif cad} {2 rapid* Rapid 3 blitz* Blitz} {
    set d {}
    catch {set d [string tolower [string trim [sc_game flag $num description]]]}
    if {![string match $motif $d]} { continue }
    if {![catch {sc_game flag $num $g} v] && $v} { return $cad }
  }
  return {}
}

### The time control a review computes the level with: the one set for
### this game in "Toby settings" ("This game"), else the PGN's
proc ::moderne::toby::cadenceBilan {} {
  variable reglages
  set k [clePartie]
  if {[info exists reglages($k)] && [dict exists $reglages($k) cadence]} {
    return [dict get $reglages($k) cadence]
  }
  return [dict get [depuisPgn] cadence]
}

### Bullet (under 3 minutes: base + 40 × increment < 180 s): Toby has no
### such time control yet, the game is judged as blitz
proc ::moderne::toby::estBullet {tc} {
  set tc [string trim $tc]
  set periode [lindex [split $tc :] 0]
  if {![regexp {^(\d+)(?:\+(\d+(?:\.\d+)?))?$} $periode -> base inc]} { return 0 }
  if {$inc eq {}} { set inc 0 }
  expr {$base + 40 * $inc < 180}
}

### Settings used for the analysis:
###   "fixe" mode (default): one rating given for both sides (2300
###     FIDE classical at first, editable in "Toby settings…");
###   "partie" mode: predict the current game, with the ratings of both
###     players and the time control from its PGN (editable for this game).
proc ::moderne::toby::reglagesPartie {} {
  variable reglages
  if {$::moderne::toby::modeAnalyse eq "fixe"} {
    set e $::moderne::toby::defElo
    return [dict create blanc $e noir $e source $::moderne::toby::defSource \
        cadence $::moderne::toby::defCadence fleches $::moderne::toby::fleches]
  }
  set k [clePartie]
  if {[info exists reglages($k)]} {
    set r $reglages($k)
  } else {
    set r [depuisPgn]
  }
  # (a game without ratings, e.g. a new game: the fixed rating and its
  # rating list; Toby got 0 before, Yosha 2026-11-08)
  if {![dict get $r blanc] && ![dict get $r noir]} {
    set e $::moderne::toby::defElo
    dict set r blanc $e
    dict set r noir $e
    dict set r source $::moderne::toby::defSource
    # (the game's time control if it has one, else the fixed one)
    if {[tcPartie] eq {}} { dict set r cadence $::moderne::toby::defCadence }
  }
  dict set r fleches $::moderne::toby::fleches
  return $r
}

### Time trouble, from the time per move left (seconds): under 15 s per
### move Toby plays blitz, under 90 s rapid (the thresholds of cadenceDe,
### 10 minutes and 1 hour for 40 moves); never above the game's time control
proc ::moderne::toby::cadenceZeitnot {cadence parCoup} {
  # (an option, off by default: the game's time control for the whole
  # game, Yosha 2026-11-10; at 37...Nf5 in a classical game, 3 moves
  # before the time control, Toby got Rapid or Blitz)
  if {!$::moderne::toby::zeitnot} { return $cadence }
  if {![string is double -strict $parCoup]} { return $cadence }
  set rang [dict create Blitz 0 Rapid 1 Classical 2]
  if {![dict exists $rang $cadence]} { return $cadence }
  set c [expr {$parCoup < 15 ? "Blitz" : ($parCoup < 90 ? "Rapid" : "Classical")}]
  return [expr {[dict get $rang $c] < [dict get $rang $cadence] ? $c : $cadence}]
}

### Periods of the time control: {{moves seconds increment} ...}, moves 0
### for the rest of the game. Game against Toby, else the TimeControl
### header: "5400+30", "40/5400+30:1800+30", "40/7200:3600"
proc ::moderne::toby::periodes {} {
  if {[winfo exists .serGameWin]} {
    if {[info exists ::sergame::timeMode] && $::sergame::timeMode eq "timebonus"} {
      set inc [expr {[sc_pos side] eq "white" ? $::sergame::winc : $::sergame::binc}]
      return [list [list 0 0 $inc]]
    }
    return {}
  }
  set tc [tcPartie]
  set l {}
  foreach p [split [string trim $tc] :] {
    if {[regexp {^(?:([0-9]+)/)?([0-9]+)(?:\+([0-9]+))?$} $p -> coups sec inc]} {
      if {$coups eq {}} { set coups 0 }
      if {$inc eq {}} { set inc 0 }
      lappend l [list $coups $sec $inc]
    }
  }
  return $l
}

### Time per move left to the side to move (seconds), or {}: the time left
### plus the increments, shared among the moves until the next time control
### (40 moves when the game ends without one, as Lichess counts)
proc ::moderne::toby::tempsParCoup {} {
  set t [tempsRestant]
  if {![string is double -strict $t]} { return {} }
  set coup [lindex [split [sc_pos fen]] 5]
  if {![string is integer -strict $coup]} { set coup 1 }
  return [lindex [parCoupA $t $coup [periodes]] 0]
}

### Time per move (seconds) and moves left to the next time control for
### time left t at move number coup: {per-move moves-left}
proc ::moderne::toby::parCoupA {t coup periodes} {
  set reste 40
  set inc 0
  set fin 0
  foreach p $periodes {
    lassign $p coups sec i
    set inc $i
    if {$coups == 0} { set reste 40 ; break }
    incr fin $coups
    if {$coup <= $fin} { set reste [expr {$fin - $coup + 1}] ; break }
  }
  return [list [expr {($t + $reste * $inc) / double($reste)}] $reste]
}

### Time trouble level of a time per move: 0 none, 1 short of time (under
### 90 s per move), 2 time trouble (under 15 s per move), as cadenceZeitnot
proc ::moderne::toby::niveauZeitnot {parCoup} {
  expr {$parCoup < 15 ? 2 : ($parCoup < 90 ? 1 : 0)}
}

### Time left (seconds) to the side to move, or {} if unknown: clock of a
### game against Toby, broadcast clocks, or [%clk] of the move before
proc ::moderne::toby::tempsRestant {} {
  if {[winfo exists .serGameWin]} {
    set c [expr {[sc_pos side] eq "white" ? 1 : 2}]
    if {![catch {::gameclock::getSec $c} s]} { return $s }
    return {}
  }
  if {![catch {::moderne::direct::tempsRestant} s] && $s ne {}} { return $s }
  # [%clk] of the side to move's last move (two plies back)
  set s {}
  if {[sc_var level] == 0 && [sc_pos location] >= 2} {
    catch {
      sc_move back
      set com [sc_pos getComment]
      sc_move forward
      if {[regexp {\[%clk ([0-9]+):([0-9]+):([0-9]+)} $com -> h m sec]} {
        set s [expr {[scan $h %d] * 3600 + [scan $m %d] * 60 + [scan $sec %d]}]
      }
    }
  }
  return $s
}

### Settings of the game, the time control adjusted to time trouble
proc ::moderne::toby::reglagesEffectifs {} {
  set r [reglagesPartie]
  if {$::moderne::toby::modeAnalyse ne "fixe"} {
    set t {}
    catch {set t [tempsParCoup]}
    dict set r cadence [cadenceZeitnot [dict get $r cadence] $t]
  }
  return $r
}

### Options sent to Toby before each "go": list of {name value}
### Logical cores of the computer
### An NVIDIA graphics card (its driver's nvidia-smi is there): Toby then
### runs Maia on it (TOBY_DEVICE=auto, Toby 2026-10-30)
proc ::moderne::toby::carteNvidia {} {
  variable carte
  if {[info exists carte]} { return $carte }
  set carte [expr {[auto_execok nvidia-smi] ne {}}]
  if {!$carte && $::tcl_platform(platform) eq "windows"} {
    catch {set carte [file exists [file join $::env(SystemRoot) System32 nvidia-smi.exe]]}
  }
  return $carte
}

proc ::moderne::toby::coeurs {} {
  variable coeurs
  if {[info exists coeurs]} { return $coeurs }
  set c 2
  catch {set c [exec nproc]}
  catch {if {$::tcl_platform(platform) eq "windows"} { set c $::env(NUMBER_OF_PROCESSORS) }}
  if {![string is integer -strict $c] || $c < 1} { set c 2 }
  set coeurs $c
  return $c
}

### Stockfish threads for Toby: 0 (Toby's own choice, 1 thread in
### Classical), unless the user set a number in the engine's options.
### Toby's networks were trained on 1-thread Stockfish values; with 4
### threads its numbers changed from one run to the next (37...Nf5 at
### 13.7 % then 22.5 % in the same position) and were off calibration,
### for no real gain in time (1.5 to 1.8 s to the final answer either way,
### Toby's node budget being fixed), measured 2026-11-01.
proc ::moderne::toby::filsStockfish {{n -1}} {
  if {$n >= 0} {
    foreach opt [lindex [lindex $::engines(list) $n] 8] {
      if {[lindex $opt 0] eq "Stockfish Threads" && [lindex $opt 1] ne {} && [lindex $opt 1] != 0} { return [lindex $opt 1] }
    }
  }
  return 0
}

proc ::moderne::toby::optionsVoulues {{n -1}} {
  set r [reglagesEffectifs]
  return [list \
      [list {Stockfish Threads} [filsStockfish $n]] \
      [list Display Full] \
      [list {White Rating} [dict get $r blanc]] \
      [list {Black Rating} [dict get $r noir]] \
      [list {Rating Source} [dict get $r source]] \
      [list {Time Control} [dict get $r cadence]] \
      [list {Move Model} Auto] \
      [list MultiPV 500] \
      [list UCI_ShowWDL true] \
      [list Mode Prediction]]
}

### "Toby — 2650 vs 2700, FIDE, Classical"
### Settings in use, short (the tab already names Toby): the ratings,
### and the time control when it is not classical; the full text is in
### the tooltip
proc ::moderne::toby::titreCourt {} {
  set r [reglagesPartie]
  set eloB [dict get $r blanc]
  set eloN [dict get $r noir]
  set t [expr {$eloB == $eloN ? $eloB : "$eloB–$eloN"}]
  if {!$eloB && !$eloN} { set t [T "Elo ?" "Elo ?"] }
  if {[dict get $r cadence] ne "Classical" || [dict get $r source] ne "FIDE"} {
    set cad [dict get {Classical Classique Rapid Rapide Blitz Blitz} [dict get $r cadence]]
    if {[string match en* [::moderne::tr fr en]]} { set cad [dict get $r cadence] }
    append t " • $cad"
  }
  return $t
}

proc ::moderne::toby::titre {} {
  set r [reglagesPartie]
  set eloB [dict get $r blanc]
  set eloN [dict get $r noir]
  set elos [expr {$eloB || $eloN ? "$eloB vs $eloN" : [T "Elo non renseigné" "no rating"]}]
  if {$eloB == $eloN && $eloB} { set elos $eloB }
  set cad [dict get {Classical Classique Rapid Rapide Blitz Blitz} [dict get $r cadence]]
  if {![::moderne::actif] || [string match en* [::moderne::tr fr en]]} { set cad [dict get $r cadence] }
  # ("Lichess Blitz" already states the time control)
  set source [dict get $r source]
  set t "Toby • $elos, $source"
  if {$source eq "FIDE"} { append t ", $cad" }
  # Toby 2's product actually running (Accurate refused: Toby's reason)
  variable produit
  variable produitRaison
  foreach k [lsort [array names produit]] {
    append t ", Toby 2 $produit($k)"
    if {[info exists produitRaison($k)] && $produitRaison($k) ne {}} { append t " ($produitRaison($k))" }
    break
  }
  # where Maia runs (Toby says it at uci), as Yosha asked (2026-11-02)
  variable maiaDevice
  if {[info exists maiaDevice] && $maiaDevice ne {}} {
    append t ", " [expr {$maiaDevice in {cuda gpu} ? [T "Maia sur GPU" "Maia on GPU"] : [T "Maia sur CPU" "Maia on CPU"]}]
  }
  return $t
}

################################################################################
### Protocol: called by tcl/tools/analysis.tcl and tcl/tools/uci.tcl
################################################################################

### Before "position …" and "go": sends the options, clears the old table
# Options › Preload Toby (saved), and the last analysis with it (saved:
# Toby is preloaded only when it is used)
namespace eval ::moderne::toby {
  if {![info exists precharger]} { variable precharger 1 }
  # (time trouble: Rapid or Blitz when little time is left per move)
  if {![info exists zeitnot]} { variable zeitnot 0 }
  if {![info exists derniereUtilisation]} { variable derniereUtilisation 0 }
}

### The analysis panel's Toby loads its Leela at once, in the background,
### right after "uci": else its first Accurate search waited ~8 s more for
### it (Toby 1.0 starts Leela only when a search needs it, Toby session
### 2026-11-08). Never sent to the review's processes, which must not load
### one. envoi: command prefix that sends a line to the process.
proc ::moderne::toby::prechargerLeela {n envoi} {
  if {![estToby $n]} { return }
  # (always: Toby itself starts Leela only where it is used, Fast Classical
  # included, on the processor without an NVIDIA card)
  {*}$envoi "setoption name Leela Preload value true"
}

proc ::moderne::toby::avantGo {n} {
  variable ignorer
  variable bloc
  variable cotePlateau
  if {![estToby $n]} { return }
  set ::moderne::toby::derniereUtilisation [clock seconds]
  foreach opt [optionsVoulues $n] {
    ::sendToEngine $n "setoption name [lindex $opt 0] value [lindex $opt 1]"
  }
  envoyerPrecision $n
  # (Toby 1.0 rc3: after its final block in go infinite, ~1.5 s more on the
  # GPU and one refined block; on by default in the analysis panel only,
  # never in reviews or games, Yosha 2026-11-09)
  if {[aOption $n Deepening]} { catch {::sendToEngine $n "setoption name Deepening value true"} }
  set ignorer($n) 0
  catch {unset bloc($n)}
  set cotePlateau($n) [sc_pos side]
  variable fenGo
  set r [reglagesEffectifs]
  set fenGo($n) [list [sc_pos fen] [dict get $r blanc] [dict get $r noir] [dict get $r cadence]]
  set depart [clock milliseconds]
  after 15000 [list ::moderne::toby::surveiller $n $depart]
  # (the bar keeps its value until the first block of the new position)
  afficherAttente $n
}

### After "stop" has been sent for a new position
proc ::moderne::toby::stopEnvoye {n} {
  variable attente
  variable ignorer
  if {![estToby $n]} { return }
  set attente($n) [clock milliseconds]
  set ignorer($n) 1
}

### Must we still wait for "bestmove" before sending the position?
proc ::moderne::toby::doitAttendre {n} {
  variable attente
  if {![info exists attente($n)]} { return 0 }
  # (safety: no more than 15 s; the first go waits for Maia to load)
  if {[clock milliseconds] - $attente($n) > 15000} { unset attente($n) ; return 0 }
  return 1
}

proc ::moderne::toby::bestmove {n} {
  variable attente
  catch {unset attente($n)}
}

### Log of the exchanges with Toby (the last 400 lines), to understand
### an empty display: "Log" button of the window
proc ::moderne::toby::noter {n texte} {
  variable journal
  if {![estToby $n]} { return }
  lappend journal($n) "[clock format [clock seconds] -format %H:%M:%S] $texte"
  if {[llength $journal($n)] > 400} { set journal($n) [lrange $journal($n) end-399 end] }
}

proc ::moderne::toby::journalFenetre {n} {
  variable journal
  set w .tobyJournal
  catch {destroy $w}
  toplevel $w
  wm title $w [T "Journal de Toby" "Toby log"]
  text $w.t -width 110 -height 30 -wrap none -font font_Small
  catch {$w.t configure -background [::moderne::c champ] -foreground [::moderne::c texte] -borderwidth 0}
  ttk::scrollbar $w.sb -command [list $w.t yview]
  $w.t configure -yscrollcommand [list $w.sb set]
  ttk::frame $w.b -padding 6
  ttk::label $w.b.l -foreground [::moderne::c texteDoux] -text [T \
      "« > » : envoyé à Toby, « < » : reçu. Copie ce texte pour me l'envoyer." \
      "\"> \": sent to Toby, \"< \": received."]
  ttk::button $w.b.copier -text [T "Copier" "Copy"] -command [list apply {{w} {
    clipboard clear ; clipboard append [$w.t get 1.0 end]
  }} $w]
  pack $w.b.l -side left
  pack $w.b.copier -side right
  pack $w.b -side bottom -fill x
  pack $w.sb -side right -fill y
  pack $w.t -side left -fill both -expand 1
  if {[info exists journal($n)]} { $w.t insert end [join $journal($n) \n] }
  $w.t see end
}

### 15 s after a go without any block from Toby: say so, with the last line received
proc ::moderne::toby::surveiller {n depart} {
  variable reponse
  variable journal
  set f .analysisWin$n.toby
  if {![winfo exists $f]} { return }
  if {[info exists reponse($n)] && $reponse($n) >= $depart} { return }
  # (never analysed yet: still loading; said as such for two minutes)
  variable analyse
  if {![info exists analyse($n)] && [clock milliseconds] - $depart < 120000} {
    after 15000 [list ::moderne::toby::surveiller $n $depart]
    return
  }
  # (blocks received but skipped as those of an earlier search, whose
  # bestmove never came: the count is wrong, start again from zero)
  if {[info exists ::analysis(aSauter$n)] && $::analysis(aSauter$n) > 0} {
    noter $n "! $::analysis(aSauter$n) recherche(s) encore attendue(s) : compteur remis à zéro"
    set ::analysis(aSauter$n) 0
    set ::analysis(enCours$n) 1
    # (and the position is sent again: its blocks were lost)
    catch {unset ::analysis(cleEnvoyee$n)}
    catch {updateAnalysis $n}
    return
  }
  set derniere {}
  if {[info exists journal($n)]} {
    foreach l [lreverse $journal($n)] { if {[regexp {^\S+ < (.*)$} $l -> derniere]} { break } }
  }
  $f.h.etat configure -text [T "Toby n'a encore rien envoyé (voir « Journal de Toby » dans ⋯)" "Nothing from Toby yet (see \"Toby log\" in ⋯)"]
  catch {pack $f.h.etat -in $f.h.e -side left -padx 6 -after $f.h.titre}
  noter $n "! aucun bloc « info string toby » reçu 15 s après le go ; dernière ligne : $derniere"
}

### Ordinary "info" lines (MultiPV, depth…): ignored for Toby
proc ::moderne::toby::ignorerInfo {n ligne} {
  if {![estToby $n]} { return 0 }
  return [expr {![string match "info string*" $ligne]}]
}

### An "info string …" line from Toby (text = what follows "info string")
proc ::moderne::toby::ligne {n texte} {
  set texte [string trim $texte " \t\r\n"]
  # Toby's own warning (e.g. "Toby: WARNING files missing in nn/: …"),
  # shown in the panel as Toby wrote it
  if {[regexp -nocase {^toby:\s*warning\s*(.*)$} $texte -> quoi]} {
    noter $n "! $texte"
    catch {.analysisWin$n.toby.h.etat configure -text "Toby : $quoi"}
    catch {pack .analysisWin$n.toby.h.etat -in .analysisWin$n.toby.h.e -side left -padx 6 -after .analysisWin$n.toby.h.titre}
    return 1
  }
  # Toby 2 refused Accurate (no lc0, card or driver): Standard answers
  if {[regexp {^Toby 2 Accurate is not available here \((.*)\)} $texte -> pourquoi]} {
    variable produit
    variable produitRaison
    set produit($n) Standard
    set produitRaison($n) $pourquoi
    noter $n "! $texte"
    return 1
  }
  if {![string match -nocase "toby *" $texte]} { return 0 }
  # (where Maia runs, said before readyok: the review shares the cores
  # with it, niveau::partage)
  if {[regexp -nocase {^toby maia device (\S+)} $texte -> d]} {
    set ::moderne::toby::maiaDevice [string tolower $d]
    return 1
  }
  variable reponse
  set reponse($n) [clock milliseconds]
  # (a first analysis block: Toby is loaded)
  if {[regexp -nocase {^toby begin} $texte]} {
    variable analyse
    set analyse($n) 1
  }
  if {[catch {ligneToby $n $texte} err]} {
    noter $n "! erreur Siby : $err"
    catch {.analysisWin$n.toby.h.etat configure -text "[T "erreur" "error"] : $err"}
    catch {pack .analysisWin$n.toby.h.etat -in .analysisWin$n.toby.h.e -side left -padx 6 -after .analysisWin$n.toby.h.titre}
  }
  return 1
}

proc ::moderne::toby::ligneToby {n texte} {
  variable bloc
  variable tableau
  variable ignorer
  if {[info exists ignorer($n)] && $ignorer($n)} { return }
  set mots [split [regsub -all {\s+} $texte " "] " "]
  lset mots 0 toby
  switch -- [string tolower [lindex $mots 1]] {
    begin {
      set etape [champ $mots stage 1]
      set final [champ $mots final 0]
      set bloc($n) [dict create etape $etape final $final lignes {} position {}]
    }
    move {
      if {![info exists bloc($n)]} { return }
      set i [lsearch -exact $mots wdl]
      set wdl [expr {$i >= 0 ? [lrange $mots [expr {$i + 1}] [expr {$i + 3}]] : {- - -}}]
      dict lappend bloc($n) lignes [dict create \
          uci [lindex $mots 2] san [champ $mots san {}] prob [champ $mots prob {}] \
          maia [champ $mots maia {}] wdl $wdl es [champ $mots es -]]
    }
    position {
      if {![info exists bloc($n)]} { return }
      set i [lsearch -exact $mots wdl]
      dict set bloc($n) position [dict create wdl [lrange $mots [expr {$i + 1}] [expr {$i + 3}]] es [champ $mots es -]]
    }
    others {
      # (Toby 1.0 rc2: the legal moves not listed, total probability and
      # count, after the final block; a greyed last row, Yosha 2026-11-09)
      set autres [list [lindex $mots 2] [lindex $mots 3]]
      if {[info exists bloc($n)]} {
        dict set bloc($n) autres $autres
      } elseif {[info exists tableau($n)]} {
        dict set tableau($n) autres $autres
        afficher $n
      }
    }
    end {
      if {![info exists bloc($n)]} { return }
      # (block of another position, received late: ignored)
      if {![blocDuPlateau $bloc($n)]} { unset bloc($n) ; return }
      # The whole table is replaced by this block
      set tableau($n) $bloc($n)
      variable tTableau
      set tTableau($n) [clock microseconds]
      # a complete analysis is remembered for the annotation
      variable fenGo
      if {[dict get $bloc($n) final] && [dict get $bloc($n) etape] >= 3 && [info exists fenGo($n)] &&
          [lindex $fenGo($n) 0] eq [sc_pos fen]} {
        lassign $fenGo($n) fen blanc noir cadence
        variable memoire
        if {[array size memoire] > 5000} { array unset memoire }
        set memoire([join [lrange [split $fen] 0 3]]|$blanc|$noir|$cadence) $bloc($n)
      }
      unset bloc($n)
      afficher $n
      majBarre $n
      fleches $n
    }
  }
}

### Value following keyword k in the word list
proc ::moderne::toby::champ {mots k defaut} {
  set i [lsearch -exact $mots $k]
  if {$i < 0 || $i + 1 >= [llength $mots]} { return $defaut }
  return [lindex $mots [expr {$i + 1}]]
}

################################################################################
### Evaluation bar and arrows
################################################################################

### WDL (per mille, side to move) → {win draw loss} in % from White's
### point of view; {} if unknown
proc ::moderne::toby::wdlBlancs {n wdl} {
  variable cotePlateau
  lassign $wdl w d l
  if {![string is integer -strict $w] || ![string is integer -strict $d] || ![string is integer -strict $l]} { return {} }
  if {[info exists cotePlateau($n)] && $cotePlateau($n) eq "black"} { lassign [list $l $w] w l }
  return [list [expr {round($w / 10.0)}] [expr {round($d / 10.0)}] [expr {round($l / 10.0)}]]
}

proc ::moderne::toby::majBarre {n} {
  variable tableau
  variable cotePlateau
  # The position's value: the moves' W/D/L weighted by the probability that
  # a player of that rating plays each of them, the table read as a whole
  # (Yosha 2026-11-03: a likely losing move, 2nd most probable, must make
  # the opponent the favourite; Toby's own "toby position" value, from the
  # engine's evaluation, said 47 % where the table gave 61 %). Toby's value
  # only when the moves have none.
  set pos [estimation $tableau($n)]
  if {$pos eq {}} {
    set pos [dict get $tableau($n) position]
    if {$pos eq {} || ![string is double -strict [dict get $pos es]]} { return }
  }
  set es [dict get $pos es]
  # Expected score from White's point of view: 1 − es when Black is to move
  if {[info exists cotePlateau($n)] && $cotePlateau($n) eq "black"} { set es [expr {1.0 - $es}] }
  set wdl [wdlBlancs $n [dict get $pos wdl]]
  catch {.analysisWin$n.toby.h.ev configure -text "[expr {round(100 * $es)}] %"}
  # Equivalent in pawns (inverse of the bar's formula) for "classic" mode
  set x [expr {min(0.999, max(0.001, $es))}]
  set cp [expr {-log(1.0 / $x - 1.0) / 0.00368208 / 100.0}]
  catch {::moderne::barres::valeursExternes $n [list [format %.2f $cp] 0 $wdl]}
}

### Expected score of a block's position (side to move, 0-1): the moves
### weighted by their probability, else Toby's own value; {} if none
proc ::moderne::toby::esBloc {bloc} {
  set p [estimation $bloc]
  if {$p ne {}} { return [dict get $p es] }
  set es {}
  catch {set es [dict get $bloc position es]}
  return [expr {[string is double -strict $es] ? $es : {}}]
}

### Provisional evaluation of the position: average of the moves' WDL (per mille,
### side to move), weighted by each move's probability
proc ::moderne::toby::estimation {bloc} {
  set sp 0.0 ; set sw 0.0 ; set sd 0.0 ; set sl 0.0
  foreach l [dict get $bloc lignes] {
    set p [string trimright [dict get $l prob] %]
    lassign [dict get $l wdl] w d lo
    if {![string is double -strict $p] || $p <= 0} { continue }
    if {![string is double -strict $w] || ![string is double -strict $d] || ![string is double -strict $lo]} { continue }
    set sp [expr {$sp + $p}]
    set sw [expr {$sw + $p * $w}] ; set sd [expr {$sd + $p * $d}] ; set sl [expr {$sl + $p * $lo}]
  }
  if {$sp <= 0} { return {} }
  set w [expr {round($sw / $sp)}] ; set d [expr {round($sd / $sp)}] ; set lo [expr {round($sl / $sp)}]
  set t [expr {max(1, $w + $d + $lo)}]
  return [dict create wdl [list $w $d $lo] es [expr {($w + $d / 2.0) / $t}]]
}

### "e4" → 28 (0 = a1 … 63 = h8)
proc ::moderne::toby::caseNum {c} {
  return [expr {([scan [string index $c 0] %c] - 97) + 8 * ([string index $c 1] - 1)}]
}

### Arrows for the 3 most likely moves, with thickness proportional to
### the probability (settings option, off by default)
proc ::moderne::toby::fleches {n} {
  variable tableau
  set bd .main.board.bd
  catch {$bd delete toby}
  if {![dict get [reglagesPartie] fleches] || ![info exists tableau($n)]} { return }
  set taille $::board::_size(.main.board)
  set couleur [expr {[dict get $tableau($n) final] ? "#15781b" : "#7a8f7b"}]
  foreach l [lrange [dict get $tableau($n) lignes] 0 2] {
    set p [dict get $l prob]
    if {![string is double -strict $p]} { continue }
    set uci [dict get $l uci]
    if {![regexp {^([a-h][1-8])([a-h][1-8])} $uci -> de vers]} { continue }
    set de [caseNum $de]
    set vers [caseNum $vers]
    if {[catch {::board::mark::GetArrowCoords $bd $de $vers} coords]} { continue }
    set e [expr {max(2, $taille * (0.04 + 0.22 * $p))}]
    $bd create line {*}$coords -fill $couleur -width $e -arrow last \
        -arrowshape [list [expr {$e * 1.6}] [expr {$e * 1.6}] [expr {$e * 0.9}]] -tags toby
  }
}

################################################################################
### Table in the engine window
################################################################################

### Normal status (computing, provisional, final): in the tooltip of the
### settings; the status label is only shown for a problem
proc ::moderne::toby::etatNormal {f texte} {
  $f.h.etat configure -text $texte
  catch {pack forget $f.h.etat}
  catch {::utils::tooltip::Set $f.h.titre "[titre]  •  $texte"}
}

proc ::moderne::toby::creer {n} {
  set w .analysisWin$n
  set f $w.toby
  if {[winfo exists $f]} { return $f }
  # (no top padding: the header row is level with the other engines')
  ttk::frame $f -padding {6 0 6 2}
  ttk::frame $f.h
  ttk::label $f.h.titre -font font_Bold -text [titreCourt]
  ttk::label $f.h.etat -foreground [::moderne::c texteDoux] -text {}
  ttk::button $f.h.reglages -text "⚙" -style Toolbutton \
      -command [list ::moderne::toby::reglagesFenetre $n]
  # Two modes: a fixed rating (default) or the game's ratings and time control
  set style Toolbutton
  if {![catch {ttk::style layout Segment.Toolbutton} l] && $l ne {}} { set style Segment.Toolbutton }
  ttk::frame $f.h.mode
  ttk::radiobutton $f.h.mode.fixe -text [T "Elo fixe" "Fixed Elo"] -style $style \
      -variable ::moderne::toby::modeAnalyse -value fixe -command [list ::moderne::toby::changerMode $n]
  ttk::radiobutton $f.h.mode.partie -text [T "Cette partie" "This game"] -style $style \
      -variable ::moderne::toby::modeAnalyse -value partie -command [list ::moderne::toby::changerMode $n]
  pack $f.h.mode.fixe $f.h.mode.partie -side left -padx 1
  ::utils::tooltip::Set $f.h.mode.fixe [T "Un Elo donné pour les deux camps (réglable dans « Réglages… »)" "One rating for both sides"]
  ::utils::tooltip::Set $f.h.mode.partie [T "Prédire cette partie : Elo des deux joueur·ses et cadence du PGN" "Predict this game: both ratings and time control from the PGN"]
  # One row, like the other engines' header (so that the moves of both
  # start at the same height): the dot (green: computing), the position's
  # expected score in large type, the mode, the settings in use and the
  # status; "Settings…" on the right, the log in the "⋯" menu
  catch {font create font_GrandEval -family [font actual font_Regular -family] -size 17 -weight bold}
  ttk::frame $f.h.e
  ttk::label $f.h.pt -text "●" -foreground [::moderne::c inactif]
  # (room for "100 %" from the start, 6 digits wide since "%" is wider
  # than a digit: "…" took less, and the row moved when the score came,
  # Yosha 2026-11-11)
  ttk::label $f.h.ev -text "…" -font font_GrandEval -foreground [::moderne::c texteFort] -width 6 -anchor w
  ::utils::tooltip::Set $f.h.ev [T "Espérance de gain des Blancs dans la position (Toby)" "White's expected score in this position (Toby)"]
  $f.h.titre configure -font font_Small -foreground [::moderne::c texteDoux]
  $f.h.etat configure -font font_Small
  pack $f.h.pt -in $f.h.e -side left -padx {4 4}
  pack $f.h.ev -in $f.h.e -side left -padx {0 8}
  pack $f.h.mode -in $f.h.e -side left -padx {0 8}
  pack $f.h.titre -in $f.h.e -side left
  # (a drawn icon, the same on every system: the gear character looked
  # like a molecule in Windows' font)
  catch {$f.h.reglages configure -text {} -image [::moderne::navigation::imageIcone ⚙] -padding {2 0}}
  # (first in the packing order: a long title (ratings and time control)
  # is cut, not the button, Yosha 2026-11-11)
  pack $f.h.reglages -in $f.h.e -side right -before $f.h.pt
  ::utils::tooltip::Set $f.h.reglages [T "Réglages de Toby…" "Toby settings…"]
  # (status and full settings: in the tooltip of the short title)
  pack $f.h.e -side top -fill x
  catch {
    $w.b.plus.m add separator
    $w.b.plus.m add command -label [T "Journal de Toby" "Toby log"] -command [list ::moderne::toby::journalFenetre $n]
  }
  # (created before their frames: must be raised, otherwise they are hidden)
  foreach x {pt ev titre etat mode reglages} { raise $f.h.$x }
  pack $f.h -side top -fill x
  canvas $f.cv -highlightthickness 0 -borderwidth 0 -background [::moderne::c surface] \
      -height [expr {[lindex [hauteurs] 0] + 4 * [lindex [hauteurs] 1] + 6}]
  ttk::scrollbar $f.sb -command [list $f.cv yview]
  $f.cv configure -yscrollcommand [list $f.sb set]
  pack $f.sb -side right -fill y
  pack $f.cv -side left -fill both -expand 1
  bind $f.cv <Configure> [list ::moderne::toby::afficher $n]
  bind $f.cv <ButtonRelease-1> [list ::moderne::toby::clic $n %y]
  bind $f.cv <Motion> [list ::moderne::toby::survol $n %y]
  bind $f.cv <MouseWheel> "$f.cv yview scroll \[expr {%D > 0 ? -1 : 1}\] units"
  bind $f.cv <Button-4> [list $f.cv yview scroll -1 units]
  bind $f.cv <Button-5> [list $f.cv yview scroll 1 units]
  $f.cv configure -yscrollincrement 20
  # The table takes the place of the analysis lines; the info row
  # (depth, nodes, speed) is hidden
  if {[winfo exists $w.hist] && [winfo manager $w.hist] eq "pack"} {
    pack $f -side top -fill both -expand 1 -before $w.hist
  } else {
    pack $f -side top -fill both -expand 1
  }
  catch {pack forget $w.hist}
  catch {pack forget $w.text}
  # (the number of lines makes no sense for Toby: MultiPV 500 sent at each go)
  catch {pack forget $w.b.multipv}
  bind $f <Destroy> [list ::moderne::toby::oublier $n]
  # Default height: the header and 4 moves (the rest scrolls)
  after 300 [list ::moderne::toby::ajusterHauteur $n]
  return $f
}

### Heights of the table's header and rows: those of the other engines'
### panels (column titles, then one line per row), so that Toby's rows sit
### level with Stockfish's beside it
proc ::moderne::toby::hauteurs {} {
  set ls [font metrics font_Regular -linespace]
  set pas [expr {$ls + 10}]
  catch {set pas [::moderne::moteur::pasLigne]}
  return [list [expr {$ls + 8}] $pas]
}

### Rows Toby's table is sized for, with v moves shown: those moves and
### « Other moves », at most 4 (more scroll); none at 0 (the score only)
proc ::moderne::toby::rangsTableau {v} {
  if {![string is integer -strict $v]} { set v 8 }
  if {$v <= 0} { return 0 }
  return [expr {min($v + 1, 4)}]
}

proc ::moderne::toby::ajusterHauteur {n} {
  set w .analysisWin$n
  if {![winfo exists $w.toby]} { return }
  lassign [hauteurs] hh hl
  set r [rangsTableau [::moderne::moteur::vues $n]]
  # (no move shown: the table goes, the score stays)
  if {$r == 0} {
    catch {pack forget $w.toby.cv $w.toby.sb}
  } elseif {[winfo manager $w.toby.cv] eq {}} {
    pack $w.toby.sb -side right -fill y
    pack $w.toby.cv -side left -fill both -expand 1
  }
  $w.toby.cv configure -height [expr {$r == 0 ? 1 : $hh + $r * $hl + 6}]
  update idletasks
  set h [expr {[winfo reqheight $w.b] + [winfo reqheight $w.toby]}]
  catch {dict set ::moderne::moteur::hauteurMem "[::moderne::moteur::nom $n]|toby|$r" $h}
  catch {::moderne::docks::ajusterHauteur .fdockanalysisWin$n $h}
}

proc ::moderne::toby::afficherAttente {n} {
  set w .analysisWin$n
  if {![winfo exists $w]} { return }
  set f [creer $n]
  titrer $f
  catch {$f.h.ev configure -text "…"}
  catch {$f.h.pt configure -foreground #4cc16b}
  etatNormal $f [T "calcul…" "computing…"]
  # (nothing received yet from this process: Toby is loading its networks,
  # seconds, more at the first start after a reboot; said instead of an
  # empty panel)
  variable analyse
  if {![info exists analyse($n)]} {
    $f.h.etat configure -text [T "Toby se charge…" "Toby is loading…"]
    catch {pack $f.h.etat -in $f.h.e -side left -padx 6 -after $f.h.titre}
  }
  # the table of the previous position is no longer shown (its moves
  # would not match the board)
  variable tableau
  catch {unset tableau($n)}
  catch {$f.cv delete all}
}

### Do the moves of a block match the board? (each one starts from a
### square holding a piece of the side to move)
proc ::moderne::toby::blocDuPlateau {b} {
  set bd [sc_pos board]
  set trait [string index $bd 65]
  foreach l [dict get $b lignes] {
    set uci [dict get $l uci]
    if {[string length $uci] < 4} { continue }
    set f [expr {[scan [string index $uci 0] %c] - 97}]
    set r [expr {[string index $uci 1] - 1}]
    if {$f < 0 || $f > 7 || $r < 0 || $r > 7} { return 0 }
    set p [string index $bd [expr {$r * 8 + $f}]]
    if {$trait eq "w" ? ![string is upper -strict $p] : ![string is lower -strict $p]} { return 0 }
  }
  return 1
}

### Toby next to another engine: its column titles at the same height as
### the other's (measured on screen: the fonts of the two headers differ
### by a few pixels on Windows); the gap goes above Toby's table
proc ::moderne::toby::aligner {n} {
  variable decal
  variable alignPrevu
  set alignPrevu($n) 0
  set w .analysisWin$n
  if {![winfo exists $w.toby.cv] || ![winfo ismapped $w.toby.cv]} { return }
  if {![info exists decal($n)]} { set decal($n) 0 }
  foreach f [winfo children .] {
    if {![regexp {^\.analysisWin([0-9]+)$} $f -> k] || $k == $n} { continue }
    if {[winfo exists $f.toby] || ![winfo exists $f.colonnes] || ![winfo ismapped $f.colonnes]} { continue }
    # (side by side: their panels start at the same height)
    if {abs([winfo rooty $f] - [winfo rooty $w]) > 3} { continue }
    set ys [expr {[winfo rooty $f.colonnes] - [winfo rooty $f]}]
    set yt [expr {[winfo rooty $w.toby.cv] - [winfo rooty $w]}]
    set d [expr {max(0, $decal($n) + $ys - $yt)}]
    if {$d != $decal($n) && $d < 40} {
      set decal($n) $d
      catch {pack configure $w.toby.h -pady [list 0 $d]}
    }
    return
  }
}

proc ::moderne::toby::afficher {n} {
  variable alignPrevu
  if {![info exists alignPrevu($n)] || !$alignPrevu($n)} {
    set alignPrevu($n) 1
    after idle [list ::moderne::toby::aligner $n]
  }
  variable tableau
  set f .analysisWin$n.toby
  if {![winfo exists $f]} { return }
  # Dot: green while Toby is computing, gray when paused
  set actif [expr {[info exists ::analysis(analyzeMode$n)] && $::analysis(analyzeMode$n)}]
  catch {$f.h.pt configure -foreground [expr {$actif ? "#4cc16b" : [::moderne::c inactif]}]}
  set cv $f.cv
  $cv delete all
  titrer $f
  if {![info exists tableau($n)]} { return }
  set etape [dict get $tableau($n) etape]
  set final [dict get $tableau($n) final]
  set provisoire [expr {!$final || $etape < 3}]
  etatNormal $f [expr {$provisoire \
      ? [T "provisoire (étape $etape/3)…" "provisional (stage $etape/3)…"] \
      : [T "définitif" "final"]}]
  set larg [winfo width $cv]
  if {$larg < 50} { set larg 520 }
  lassign [hauteurs] hh hl
  set texte [expr {$provisoire ? [::moderne::c texteDoux] : [::moderne::c texte]}]
  set doux [::moderne::c texteDoux]
  set chiffre [font measure font_Regular 0]
  set xC 10
  # Move column as wide as the longest move (O-O-O, Nxe7+…)
  set largCoup [font measure font_Bold "Nf3+"]
  foreach l [dict get $tableau($n) lignes] {
    set lc [font measure font_Bold [::trans [dict get $l san]]]
    if {$lc > $largCoup} { set largCoup $lc }
  }
  set xT [expr {$xC + max(11 * $chiffre, $largCoup + 8 + [font measure font_Bold "00.0 %"])}]
  set xB [expr {$xT + 3 * $chiffre}]
  set xE [expr {$larg - 10}]
  set xBf [expr {$xE - 6 * $chiffre}]
  # Headers
  # (Prob.: the probability that a player of that rating plays the move)
  foreach {x ancre fr en} [list $xC w Coup Move $xT e "Proba" "Prob." \
                               $xB w [T "B / = / N" "W / = / B"] {} $xE e [T "Esp." "Exp."] {}] {
    $cv create text $x [expr {$hh / 2}] -anchor $ancre -text [expr {$en eq {} ? $fr : [T $fr $en]}] \
        -fill $doux -font font_Small
  }
  $cv create line 0 $hh $larg $hh -fill [::moderne::c bordure]
  set joue {}
  catch {set joue [sc_game info nextMoveNT]}
  # W/D/L bars and expected scores always from White's point of view
  variable cotePlateau
  set noirs [expr {[info exists cotePlateau($n)] && $cotePlateau($n) eq "black"}]
  lassign {#e8e8e8 #8f8c88 #1e1e1e #262421 #ffffff #e8e8e8} cG cD cP tG tD tP
  set y $hh
  set i 0
  set lignes [dict get $tableau($n) lignes]
  # (the moves shown: the first ones; those hidden go into « Other moves »,
  # with what Toby put there, so that it still says all the rest, Yosha
  # 2026-11-16)
  set vues [::moderne::moteur::vues $n]
  set autresP {} ; set autresK 0
  if {[dict exists $tableau($n) autres]} { lassign [dict get $tableau($n) autres] autresP autresK }
  if {[llength $lignes] > $vues} {
    foreach l [lrange $lignes $vues end] {
      set p [dict get $l prob]
      if {![string is double -strict $p]} { continue }
      set autresP [expr {[string is double -strict $autresP] ? $autresP + $p : $p}]
      if {![string is integer -strict $autresK]} { set autresK 0 }
      incr autresK
    }
    set lignes [lrange $lignes 0 [expr {$vues - 1}]]
  }
  foreach l $lignes {
    set y1 [expr {$y + $i * $hl}]
    set y2 [expr {$y1 + $hl}]
    set ym [expr {($y1 + $y2) / 2}]
    set san [dict get $l san]
    set fond [expr {$i % 2 ? ($::moderne::theme eq "clair" ? "#f0f3f6" : "#272a2e") : [::moderne::c surface]}]
    set tags [list ligne l$i]
    if {$san ne {} && $san eq $joue} {
      set fond [::moderne::c selection]
    }
    $cv create rectangle 0 $y1 $larg $y2 -fill $fond -outline {} -tags [list fond f$i]
    if {$san ne {} && $san eq $joue} {
      $cv create rectangle 0 $y1 3 $y2 -fill [::moderne::c accent] -outline {}
    }
    set bleu [expr {$::moderne::theme eq "clair" ? "#1565c0" : "#6cc4ff"}]
    $cv create text $xC $ym -anchor w -text [::trans $san] -fill [expr {$provisoire ? $texte : $bleu}] -font font_Bold
    set p [dict get $l prob]
    set ptxt [expr {[string is double -strict $p] ? [format %.1f [expr {100 * $p}]] : "?"}]
    $cv create text $xT $ym -anchor e -text "$ptxt %" -fill $texte -font font_Bold
    # Win / draw / loss bar
    lassign [dict get $l wdl] w d pe
    # (from White's point of view, like the expected score: Toby gives
    # them for the side to move)
    if {$noirs} { lassign [list $pe $w] w pe }
    set bx1 [expr {$xB + 4}]
    set bx2 [expr {$xBf - 10}]
    if {[string is integer -strict $w] && [string is integer -strict $d] && [string is integer -strict $pe] && $bx2 > $bx1 + 20} {
      set L [expr {$bx2 - $bx1}]
      set x $bx1
      foreach v [list $w $d $pe] c [list $cG $cD $cP] tc [list $tG $tD $tP] {
        set lw [expr {$L * $v / 1000.0}]
        if {$lw <= 0} { continue }
        # Provisional: softened colors
        if {$provisoire} {
          catch {set c [::moderne::prise::melange $c [::moderne::c surface] 0.45]}
          catch {set tc [::moderne::prise::melange $tc [::moderne::c surface] 0.6]}
        }
        $cv create rectangle $x [expr {$y1 + 4}] [expr {$x + $lw}] [expr {$y2 - 4}] -fill $c -outline {}
        set lib [expr {round($v / 10.0)}]
        if {$lw > [font measure font_Small 00] + 6} {
          $cv create text [expr {$x + $lw / 2}] $ym -text $lib -fill $tc -font font_Small
        }
        set x [expr {$x + $lw}]
      }
      $cv create rectangle $bx1 [expr {$y1 + 4}] $bx2 [expr {$y2 - 4}] -outline [::moderne::c inactif]
    } else {
      $cv create text [expr {($bx1 + $bx2) / 2}] $ym -text "?" -fill $doux -font font_Small
    }
    set es [dict get $l es]
    if {$noirs && [string is double -strict $es]} { set es [expr {1.0 - $es}] }
    set etxt [expr {[string is double -strict $es] ? "[expr {round(100 * $es)}] %" : "?"}]
    $cv create text $xE $ym -anchor e -text $etxt -fill $texte -font font_Regular
    incr i
  }
  # the moves Toby did not list, together: their probability only, greyed
  if {1} {
    set p $autresP ; set k $autresK
    if {[string is double -strict $p] && [string is integer -strict $k] && $k > 0} {
      set y1 [expr {$y + $i * $hl}]
      set ym [expr {$y1 + $hl / 2}]
      set fond [expr {$i % 2 ? ($::moderne::theme eq "clair" ? "#f0f3f6" : "#272a2e") : [::moderne::c surface]}]
      $cv create rectangle 0 $y1 $larg [expr {$y1 + $hl}] -fill $fond -outline {} -tags autres
      set lib [T "Autres coups" "Other moves"]
      set pc [expr {100 * $p < 0.05 ? "<0.1 %" : "[format %.1f [expr {100 * $p}]] %"}]
      # (a narrow panel: the label would run over the figure, both on one
      # line then, Yosha 2026-11-09)
      if {$xC + [font measure font_Regular $lib] + 10 > $xT - [font measure font_Regular $pc]} {
        $cv create text $xC $ym -anchor w -text "$lib[T " : " ": "]$pc" -fill $doux -font font_Regular
      } else {
        $cv create text $xC $ym -anchor w -text $lib -fill $doux -font font_Regular
        $cv create text $xT $ym -anchor e -text $pc -fill $doux -font font_Regular
      }
      incr i
    }
  }
  $cv configure -scrollregion [list 0 0 $larg [expr {$y + $i * $hl + 4}]]
}

proc ::moderne::toby::ligneSous {n y} {
  variable tableau
  set cv .analysisWin$n.toby.cv
  if {![info exists tableau($n)]} { return -1 }
  lassign [hauteurs] hh hl
  set y [$cv canvasy $y]
  set i [expr {int(($y - $hh) / $hl)}]
  if {$y < $hh || $i >= [llength [dict get $tableau($n) lignes]]} { return -1 }
  return $i
}

proc ::moderne::toby::survol {n y} {
  set cv .analysisWin$n.toby.cv
  $cv configure -cursor [expr {[ligneSous $n $y] >= 0 ? "hand2" : {}}]
}

### Click on a row: play the move
proc ::moderne::toby::clic {n y} {
  variable tableau
  set i [ligneSous $n $y]
  if {$i < 0} { return }
  set san [dict get [lindex [dict get $tableau($n) lignes] $i] san]
  if {$san eq {}} { return }
  addSanMove $san -animate
  updateBoard -pgn
}

################################################################################
### "Toby settings" window (per game)
################################################################################

proc ::moderne::toby::reglagesFenetre {n} {
  variable form
  set w .tobyReglages
  if {[winfo exists $w]} { raise $w ; focus $w ; return }
  set form(n) $n
  set form(mode) $::moderne::toby::modeAnalyse
  set form(defElo) $::moderne::toby::defElo
  set form(defCadence) $::moderne::toby::defCadence
  set form(defSource) $::moderne::toby::defSource
  set form(fleches) $::moderne::toby::fleches
  set form(zeitnot) $::moderne::toby::zeitnot
  set form(precision) $::moderne::toby::precision
  set r [::moderne::toby::reglagesDePartie]
  foreach k {blanc noir source cadence} { set form($k) [dict get $r $k] }
  ::moderne::jouer::polices
  set fond [::moderne::c fond]
  toplevel $w -background $fond
  wm title $w [T "Réglages de Toby" "Toby settings"]
  wm transient $w .
  wm resizable $w 0 0
  set f [frame $w.f -background $fond -padx 22 -pady 16]
  pack $f -fill both -expand 1
  # header: logo, title, what Toby does in analysis
  frame $f.tete -background $fond
  pack $f.tete -side top -fill x
  if {![catch {::moderne::logos::image toby 48} logo] && $logo ne {}} {
    label $f.tete.logo -image $logo -background $fond
    pack $f.tete.logo -side left -padx {0 12}
  }
  label $f.tete.t -text [T "Réglages de Toby" "Toby settings"] -font SibyJouerTitre -background $fond \
      -foreground [::moderne::c texteFort] -anchor w
  label $f.tete.s -text [T "En analyse : le coup qu'un humain de ce niveau jouerait" \
      "In analysis: the move a human of this level would play"] -font SibyJouerPetit -background $fond \
      -foreground [::moderne::c texteDoux] -anchor w
  pack $f.tete.t $f.tete.s -side top -anchor w

  # Mode: two cards
  ::moderne::jouer::section $f.lmode [T "Niveau" "Level"]
  frame $f.modes -background $fond
  pack $f.modes -side top -fill x
  set i 0
  foreach {m fr1 en1 fr2 en2} {
    fixe "Elo fixe" "Fixed rating" "Un même niveau pour les deux camps" "One level for both sides"
    partie "Prédire cette partie" "Predict this game" "L'Elo et la cadence des joueur·ses du PGN" "The players' ratings and time control from the PGN"} {
    carteReglage $f.modes.$m $m [T $fr1 $en1] [T $fr2 $en2]
    grid $f.modes.$m -row 0 -column $i -sticky nsew -padx [expr {$i ? "4 0" : "0 4"}]
    grid columnconfigure $f.modes $i -weight 1 -uniform modes -minsize 250
    incr i
  }
  frame $f.corps -background $fond
  pack $f.corps -side top -fill x

  # Precision: only with an NVIDIA card (without one, both are the same)
  set nv 0
  catch {set nv [::moderne::ajout::nvidia]}
  if {$nv} {
    ::moderne::jouer::section $f.lpr [T "Précision" "Precision"]
    set choix [list [list Accurate [T "Précis" "Accurate"]] [list Fast [T "Rapide" "Fast"]]]
    if {$::moderne::toby::hybride} { lappend choix [list Hybrid [T "Hybride" "Hybrid"]] }
    ::moderne::jouer::segments $f.pr ::moderne::toby::form(precision) $choix
    pack $f.pr -side top -fill x
    # (Toby 1.0: Fast is Stockfish guided by Leela's policy, Stockfish alone
    # only when Leela is missing or fails; the Toby session, 2026-11-15)
    set bulle [T "Précis : Leela calcule, en classique avec une carte NVIDIA. Rapide : Stockfish calcule, guidé par Leela (une évaluation par coup). Identiques en rapide et en blitz." \
        "Accurate: Leela calculates, in Classical with an NVIDIA card. Fast: Stockfish calculates, guided by Leela (one evaluation per move). The same in Rapid and Blitz."]
    # (Toby's own words, 2026-11-03)
    if {$::moderne::toby::hybride} {
      append bulle "\n" [T "Hybride : les valeurs de Stockfish et la première impression de Leela sur chaque coup ; proche de Précis, presque aussi rapide que Rapide avec une carte NVIDIA. En classique seulement, sinon identique à Rapide." \
          "Hybrid: Stockfish's values plus Leela's first impression of each move; close to Accurate, about as fast as Fast with an NVIDIA card. Classical only; elsewhere the same as Fast."]
    }
    catch {::utils::tooltip::Set $f.pr $bulle}
  }
  ttk::checkbutton $f.fleches -variable ::moderne::toby::form(fleches) -text [T \
      "Flèches des 3 coups les plus probables sur l'échiquier" "Arrows for the 3 most likely moves on the board"]
  pack $f.fleches -side top -anchor w -pady {14 0}
  ttk::checkbutton $f.zeitnot -variable ::moderne::toby::form(zeitnot) -text [T \
      "Manque de temps : rapide ou blitz quand il reste peu de temps par coup" \
      "Time trouble: rapid or blitz when little time is left per move"]
  catch {::utils::tooltip::Set $f.zeitnot [T "Moins de 90 s par coup jusqu'au contrôle : rapide ; moins de 15 s : blitz" \
      "Under 90 s per move to the time control: rapid; under 15 s: blitz"]}
  pack $f.zeitnot -side top -anchor w -pady {6 0}
  frame $f.btn -background $fond
  ttk::button $f.btn.ok -text [T "Appliquer" "Apply"] -command ::moderne::toby::appliquer
  if {![catch {ttk::style layout Accent.TButton} l] && $l ne {}} { $f.btn.ok configure -style Accent.TButton }
  ttk::button $f.btn.annuler -text [T "Fermer" "Close"] -command [list destroy $w]
  pack $f.btn.ok $f.btn.annuler -side right -padx 3
  pack $f.btn -side top -fill x -pady {16 0}
  bind $w <Escape> [list destroy $w]
  bind $w <Return> ::moderne::toby::appliquer
  choisirMode $form(mode)
  catch {placeWinOverParent $w .}
}

### A mode card (fixed rating / this game)
proc ::moderne::toby::carteReglage {c m titre sous} {
  set fond [::moderne::c surface]
  frame $c -background $fond -highlightthickness 1 -highlightbackground [::moderne::c bordure] -padx 12 -pady 9 -cursor hand2
  label $c.n -text $titre -font font_Bold -background $fond -foreground [::moderne::c texteFort] -anchor w
  label $c.t -text $sous -font SibyJouerPetit -background $fond -foreground [::moderne::c texteDoux] \
      -anchor w -justify left -wraplength 220
  pack $c.n $c.t -side top -anchor w
  foreach x [list $c $c.n $c.t] { bind $x <Button-1> [list ::moderne::toby::choisirMode $m] }
}

### Shows the settings of a mode
proc ::moderne::toby::choisirMode {m} {
  variable form
  set f .tobyReglages.f
  if {![winfo exists $f]} { return }
  set form(mode) $m
  foreach k {fixe partie} {
    set c $f.modes.$k
    set on [expr {$k eq $m}]
    set fond [expr {$on ? [::moderne::jouer::melange [::moderne::c surface] [::moderne::c accent] 0.14] : [::moderne::c surface]}]
    $c configure -background $fond -highlightbackground [expr {$on ? [::moderne::c accent] : [::moderne::c bordure]}]
    $c.n configure -background $fond
    $c.t configure -background $fond
  }
  set p $f.corps
  foreach x [winfo children $p] { destroy $x }
  set sources {FIDE {Lichess Classical} {Lichess Rapid} {Lichess Blitz} {Chess.com Rapid} {Chess.com Blitz}}
  set cadences [list [list Classical [T "Classique" "Classical"]] [list Rapid [T "Rapide" "Rapid"]] [list Blitz Blitz]]
  set fond [::moderne::c fond]
  if {$m eq "fixe"} {
    ::moderne::jouer::section $p.lc [T "Cadence" "Time control"]
    ::moderne::jouer::segments $p.c ::moderne::toby::form(defCadence) $cadences
    pack $p.c -side top -fill x
    ::moderne::jouer::niveau $p.niv [T "Niveau des deux camps" "Level of both sides"] ::moderne::toby::form(defElo) 1400 2900 10
    ttk::combobox $p.niv.v.src -state readonly -width 15 -textvariable ::moderne::toby::form(defSource) -values $sources
    pack $p.niv.v.src -side left -padx {10 0} -pady {4 0}
    bind $p.niv.v.src <<ComboboxSelected>> {::moderne::toby::bornesReglage}
    pack $p.niv -side top -fill x
  } else {
    ::moderne::jouer::section $p.lc [T "Cadence" "Time control"]
    ::moderne::jouer::segments $p.c ::moderne::toby::form(cadence) $cadences
    pack $p.c -side top -fill x
    frame $p.niv -background $fond
    pack $p.niv -side top -fill x
    ::moderne::jouer::niveau $p.niv.b [T "Elo des Blancs" "White rating"] ::moderne::toby::form(blanc) 1400 2900 10
    ::moderne::jouer::niveau $p.niv.n [T "Elo des Noirs" "Black rating"] ::moderne::toby::form(noir) 1400 2900 10
    grid $p.niv.b $p.niv.n -sticky ew -padx {0 14}
    grid columnconfigure $p.niv 0 -weight 1 -uniform niv
    grid columnconfigure $p.niv 1 -weight 1 -uniform niv
    frame $p.src -background $fond
    pack $p.src -side top -fill x -pady {10 0}
    label $p.src.l -text [T "Classement :" "Rating list:"] -background $fond -foreground [::moderne::c texte]
    ttk::combobox $p.src.c -state readonly -width 18 -textvariable ::moderne::toby::form(source) -values $sources
    bind $p.src.c <<ComboboxSelected>> {::moderne::toby::bornesReglage}
    ttk::button $p.src.pgn -text [T "Reprendre du PGN" "From the PGN"] -style Toolbutton \
        -command {::moderne::toby::formDepuisPgn ; ::moderne::toby::choisirMode partie}
    catch {::utils::tooltip::Set $p.src.pgn [T "L'Elo, le classement et la cadence écrits dans la partie" \
        "The ratings, rating list and time control written in the game"]}
    pack $p.src.l $p.src.c -side left -padx {0 6}
    pack $p.src.pgn -side right
  }
  bornesReglage
}

### Sliders bounded by the rating list (like the Play window)
proc ::moderne::toby::bornesReglage {} {
  variable form
  set p .tobyReglages.f.corps.niv
  if {![winfo exists $p]} { return }
  if {$form(mode) eq "fixe"} {
    set l [list $p.s defElo $form(defSource)]
  } else {
    set l [list $p.b.s blanc $form(source) $p.n.s noir $form(source)]
  }
  foreach {s var src} $l {
    lassign [::moderne::jouer::bornes $src] a b
    $s configure -from $a -to $b
    set v $form($var)
    # (0: rating unknown in the PGN: the other side's, like Toby does)
    if {$v eq "0" && $var in {blanc noir}} {
      set autre $form([expr {$var eq "blanc" ? "noir" : "blanc"}])
      set v [expr {[string is integer -strict $autre] && $autre > 0 ? $autre : $form(defElo)}]
      set form($var) $v
    }
    if {![string is integer -strict $v] || $v < $a} { set form($var) $a }
    if {$v > $b} { set form($var) $b }
  }
}

### "This game" settings (saved for the game, otherwise from the PGN)
proc ::moderne::toby::reglagesDePartie {} {
  variable reglages
  set k [clePartie]
  if {[info exists reglages($k)]} { return $reglages($k) }
  return [depuisPgn]
}

proc ::moderne::toby::formDepuisPgn {} {
  variable form
  set r [depuisPgn]
  foreach k {blanc noir source cadence} { set form($k) [dict get $r $k] }
  set form(mode) partie
}

proc ::moderne::toby::appliquer {} {
  variable form
  variable reglages
  foreach k {blanc noir defElo} {
    if {![string is integer -strict $form($k)] || $form($k) < 0} { set form($k) 0 }
    if {$form($k) > 3600} { set form($k) 3600 }
  }
  set ::moderne::toby::modeAnalyse $form(mode)
  set ::moderne::toby::defElo $form(defElo)
  set ::moderne::toby::defCadence $form(defCadence)
  set ::moderne::toby::defSource $form(defSource)
  set ::moderne::toby::fleches $form(fleches)
  set ::moderne::toby::zeitnot $form(zeitnot)
  if {[info exists form(precision)]} { set ::moderne::toby::precision $form(precision) }
  set reglages([clePartie]) [dict create blanc $form(blanc) noir $form(noir) source $form(source) \
      cadence $form(cadence) fleches $form(fleches)]
  catch {destroy .tobyReglages}
  changerMode $form(n)
}

### The panel's title ("2697–2746"): when it changes, the header redrawn at
### once; Windows left the old, longer one under the new one for a second
### after a game change, while Siby was busy (Yosha 2026-11-11)
proc ::moderne::toby::titrer {f} {
  set t [titreCourt]
  if {[$f.h.titre cget -text] eq $t} { return }
  $f.h.titre configure -text $t
  catch {update idletasks}
}

### Mode or settings changed: new title, analysis restarted with the
### new options
proc ::moderne::toby::changerMode {n} {
  catch {.main.board.bd delete toby}
  if {[winfo exists .analysisWin$n]} {
    catch {titrer .analysisWin$n.toby}
    catch {updateAnalysis $n}
  }
}

################################################################################
### Play against Toby (Play › Play against Toby…)
###
### The game itself is that of "Play against an engine" (clock,
### "go wtime … btime … winc … binc", never "go infinite"). Before the
### game, Siby sends Toby: Display Full, its rating on its side and
### the user's on the other, Rating Source, Time Control derived from
### the clock, and Mode Human. In Human mode, Toby itself picks its move at
### random according to its probabilities: no drawing on Siby's side. (The Mode
### option is hidden: Toby does not advertise it, it is sent explicitly.)
################################################################################

### Engines whose name contains "toby": list of {index name}
proc ::moderne::toby::moteursToby {} {
  set res {}
  set i 0
  foreach e $::engines(list) {
    if {[string match -nocase *toby* [lindex $e 0]]} { lappend res [list $i [lindex $e 0]] }
    incr i
  }
  return $res
}

### Engines of the "Play" window: Toby first, then Leela (lc0, not Maia,
### whose networks lc0 also runs): list of {number name}
proc ::moderne::toby::moteursJeu {} {
  set res [moteursToby]
  set i 0
  foreach e $::engines(list) {
    set nom [lindex $e 0]
    if {[regexp -nocase {leela|lc0} $nom] && ![regexp -nocase {maia|toby} $nom]} { lappend res [list $i $nom] }
    incr i
  }
  return $res
}

proc ::moderne::toby::estLeelaJeu {n} {
  set nom [lindex $::engines(list) $n 0]
  expr {[regexp -nocase {leela|lc0} $nom] && ![regexp -nocase {maia|toby} $nom]}
}

### "go" limit added for Leela: " nodes N" (max. nodes per move), else ""
proc ::moderne::toby::limiteNoeuds {n} {
  variable jeu
  if {![estLeelaJeu $n] || ![info exists jeu(noeuds)]} { return {} }
  if {![string is integer -strict $jeu(noeuds)] || $jeu(noeuds) <= 0} { return {} }
  return " nodes $jeu(noeuds)"
}

### Time Control from the clock (minutes, increment in seconds)
proc ::moderne::toby::cadencePendule {minutes inc} {
  if {![string is double -strict $minutes]} { set minutes 5 }
  if {![string is double -strict $inc]} { set inc 0 }
  set c [cadenceDe "[expr {int(round($minutes * 60))}]+[expr {int($inc)}]"]
  return [expr {$c eq {} ? "Classical" : $c}]
}

### "Continue from here" (like Lichess): play the board's position against
### Toby (qui = toby) or an Alter Ego (qui = alterego), as the side to move
proc ::moderne::toby::jouerIci {{qui toby}} {
  variable jeu
  set couleur [sc_pos side]
  ::moderne::jouer::defauts
  if {$qui eq "alterego"} {
    set ::moderne::alterego::form(depart) actuelle
    set ::moderne::alterego::form(couleur) $couleur
  } else {
    set jeu(depart) actuelle
    set jeu(couleur) $couleur
  }
  set ::moderne::jouer::ici 1
  ::moderne::jouer::ouvrir $qui
}

### Menu entries "This position against Toby / an Alter Ego" (Play menus,
### notation menu)
proc ::moderne::toby::entreesIci {m} {
  $m add command -label [T "Jouer cette position contre Toby…" "Play this position against Toby…"] \
      -command {::moderne::toby::jouerIci toby}
  $m add command -label [T "Jouer cette position contre un Alter Ego…" "Play this position against an Alter Ego…"] \
      -command {::moderne::toby::jouerIci alterego}
}

### The "Play" window (moderne/jouer.tcl), on Toby
proc ::moderne::toby::jeuFenetre {} {
  ::moderne::jouer::ouvrir toby
}

proc ::moderne::toby::jeuLancer {} {
  variable jeu
  # The game code (tcl/tools/sergame.tcl) loads after the start-up, which
  # can take a few seconds with a large database: wait for it
  if {[info commands ::sergame::play] eq {}} {
    after 250 ::moderne::toby::jeuLancer
    return
  }
  set n {}
  foreach e [moteursJeu] { if {[lindex $e 1] eq $jeu(moteur)} { set n [lindex $e 0] } }
  if {$n eq {}} { return }
  foreach k {eloToby eloMoi} {
    if {[string is double -strict $jeu($k)]} { set jeu($k) [expr {int(round($jeu($k)))}] }
    if {![string is integer -strict $jeu($k)] || $jeu($k) < 0} { set jeu($k) 0 }
    if {$jeu($k) > 3600} { set jeu($k) 3600 }
  }
  if {![string is double -strict $jeu(minutes)] || $jeu(minutes) <= 0} { set jeu(minutes) 3 }
  if {![string is integer -strict $jeu(inc)] || $jeu(inc) < 0} { set jeu(inc) 0 }
  # Start: initial position, or the board's (new game
  # starting from this position)
  if {$jeu(depart) eq "actuelle"} {
    set fen [sc_pos fen]
    set r [::game::ConfirmDiscardOnglet]
    if {$r == 2} { return }
    if {$r == 0} { ::game::Save }
    setTrialMode 0
    sc_game new
    if {$fen ne $::defaultFen} { catch {sc_game startBoard $fen} }
    set ::sergame::startFromCurrent 1
  } else {
    set ::sergame::startFromCurrent 0
  }
  set ::moderne::barres::enPartie 0
  catch {destroy .jouer}
  catch {destroy .configSerGameWin}
  # Clock: "Time + increment" for both sides
  set ::sergame::timeMode timebonus
  set ::sergame::wtime $jeu(minutes)
  set ::sergame::btime $jeu(minutes)
  set ::sergame::winc $jeu(inc)
  set ::sergame::binc $jeu(inc)
  set ::sergame::ponder 0
  set ::sergame::useBook 0
  set ::sergame::isOpening 0
  set ::sergame::coachIsWatching 0
  set ::sergame::engineName [expr {[estLeelaJeu $n] ? $jeu(moteur) : "$jeu(moteur) ($jeu(eloToby))"}]
  set alterEgo [expr {[info exists ::moderne::alterego::actif] && $::moderne::alterego::actif}]
  if {$alterEgo} { set ::sergame::engineName "Alter Ego • $::moderne::alterego::nomAffiche" }
  # The user plays the side at the bottom of the board (its way before the
  # games, kept: given back once they are over, disposition::jeuApres)
  if {![info exists ::moderne::disposition::sensAvantJeu]} {
    set ::moderne::disposition::sensAvantJeu [::board::isFlipped .main.board]
  }
  ::board::flip .main.board [expr {$jeu(couleur) eq "black"}]
  set jeu(enCours) 1
  # (the start of the game heard, as on Lichess)
  catch {::moderne::sons::jouer debut}
  if {$::sergame::startFromCurrent} {
    # (sergame only sets the headers for a game from the start)
    sc_game tags set -event [expr {$alterEgo ? "Alter Ego" : [T "Partie contre Toby" "Game against Toby"]}]
    sc_game tags set -date [::utils::date::today]
  }
  # (the previous game's window closed for good first, events included:
  # destroyed and made again under the same name in one go, on Windows the
  # new one looked gone before it was made, its container was destroyed
  # under it and Tk stopped Siby, "UpdateWrapper: Container was destroyed";
  # Rematch and Play again closed it a moment before and did not crash,
  # Yosha 2026-11-09. Its end does not give the layout back: a game follows)
  if {[winfo exists .serGameWin]} {
    set ::moderne::disposition::demarrage 1
    catch ::sergame::abortGame
    catch {destroy .serGameWin}
    update
  }
  ::sergame::play $n
  # (the new game's window made: the end of a game counts again; a game
  # resigned at once gives its layout back, Yosha 2026-11-09)
  after idle {set ::moderne::disposition::demarrage 0}
  # the players' names from the side chosen, never from the board's
  # orientation (sergame guesses them from it)
  set moi [getMyPlayerName]
  if {$moi eq {}} { set moi ? }
  set lui $::sergame::engineName
  catch {
    sc_game tags set -white [expr {$jeu(couleur) eq "white" ? $moi : $lui}]
    sc_game tags set -black [expr {$jeu(couleur) eq "white" ? $lui : $moi}]
  }
  # (an Alter Ego: who, and which year, in the headers: the players' rows
  # show their photo, title and "Carlsen · Alter Ego 2013")
  if {$alterEgo} {
    catch {
      set x [lmap {t v} [sc_game tags get Extra] {list $t $v}]
      set x [lsearch -all -inline -not -regexp -index 0 $x {^AlterEgo(Year)?$}]
      lappend x [list AlterEgo $::moderne::alterego::nomComplet] [list AlterEgoYear $::moderne::alterego::anneeJeu]
      sc_game tags set -extra [lmap e $x {format {%s "%s"} {*}$e}]
    }
  }
  # both ratings in the header: the game review and Toby's "This game"
  # read them (Leela: no rating for her)
  set eloMoi [expr {[string is integer -strict $jeu(eloMoi)] ? $jeu(eloMoi) : 0}]
  set eloLui [expr {[estLeelaJeu $n] || ![string is integer -strict $jeu(eloToby)] ? 0 : $jeu(eloToby)}]
  if {$jeu(couleur) eq "white"} { lassign [list $eloMoi $eloLui] eB eN } else { lassign [list $eloLui $eloMoi] eB eN }
  catch {
    sc_game tags set -whiteElo $eB -blackElo $eN
    # the clock as a standard TimeControl header (seconds+increment, as
    # Lichess writes it): the review judges the game in its time control
    if {$::sergame::timeMode eq "timebonus"} {
      set tc "[expr {int(round($::sergame::wtime * 60))}]+[expr {int($::sergame::winc)}]"
      set x [lsearch -all -inline -not -index 0 [lmap {t v} [sc_game tags get Extra] {list $t $v}] TimeControl]
      sc_game tags set -extra [concat [lmap e $x {format {%s "%s"} {*}$e}] [list "TimeControl \"$tc\""]]
    }
    if {[sc_game tags get Event] eq "UCI Game"} {
      sc_game tags set -event [expr {$alterEgo ? "Alter Ego" : [estLeelaJeu $n] ? [T "Partie contre Leela" "Game against Leela"] : [T "Partie contre Toby" "Game against Toby"]}]
    }
    updateBoard -pgn
  }
}

### "Set up a position…": opens SCID's position setup; the game
### will then start from the board's position
proc ::moderne::toby::jeuPoser {} {
  variable jeu
  set jeu(depart) actuelle
  ::moderne::editeur::ouvrir
  catch {raise .editeurPos}
}

### Called by ::sergame::play (tcl/tools/sergame.tcl) after the engine's
### options: Toby settings for the game, including Mode Human
proc ::moderne::toby::optionsPartie {n} {
  variable jeu
  if {[estLeelaJeu $n]} { optionsLeela $n ; return }
  if {![string match -nocase *toby* [lindex $::engines(list) $n 0]]} { return }
  foreach {k v} {eloToby 0 eloMoi 0 source FIDE} {
    if {![info exists jeu($k)]} { set jeu($k) $v }
  }
  # Toby plays the color opposite to the one at the bottom of the board
  set tobyBlancs [::board::isFlipped .main.board]
  # Toby's own rating capped at 2900: above it, it plays no stronger
  # (no data beyond about 2850; tests of 2026-10-31)
  set eloT [expr {$jeu(eloToby) > 2900 ? 2900 : $jeu(eloToby)}]
  set eloB [expr {$tobyBlancs ? $eloT : $jeu(eloMoi)}]
  set eloN [expr {$tobyBlancs ? $jeu(eloMoi) : $eloT}]
  # Only one rating known: it applies to both
  if {$eloB == 0} { set eloB $eloN }
  if {$eloN == 0} { set eloN $eloB }
  # (Toby always plays over the board: Lichess and Chess.com ratings sent as
  # their FIDE equivalent, with Rating Source FIDE; in rapid and blitz,
  # Lichess or Chess.com made it imitate online players, who blunder more;
  # Yosha 2026-11-04)
  set eloB [::moderne::toby::elo::depuisSource $eloB $jeu(source)]
  set eloN [::moderne::toby::elo::depuisSource $eloN $jeu(source)]
  switch $::sergame::timeMode {
    timebonus { set cad [cadencePendule $::sergame::wtime $::sergame::winc] }
    movetime  { set cad [cadenceDe "[expr {int(40 * $::sergame::movetime)}]+0"] }
    default   { set cad Classical }
  }
  if {$cad eq {}} { set cad Classical }
  variable reglagesJeu [list $eloB $eloN $cad]
  foreach {nom val} [list Display Full {White Rating} $eloB {Black Rating} $eloN \
                         {Rating Source} FIDE {Time Control} $cad Mode Human \
                         {Stockfish Threads} [filsStockfish $n]] {
    ::sergame::sendToEngine $n "setoption name $nom value $val"
  }
  envoyerPrecision $n ::sergame::sendToEngine 0
  set jeu(enCours) 0
}

### Leela for a game: contempt (lc0 0.30+: the Elo advantage it assumes,
### WDL calibrated on the player's rating), "play" mode
proc ::moderne::toby::optionsLeela {n} {
  variable jeu
  set c [expr {[info exists jeu(contempt)] && [string is integer -strict $jeu(contempt)] ? $jeu(contempt) : 0}]
  if {[info exists jeu(noeuds)] && $jeu(noeuds) eq "1"} { set c 0 }
  set moi [expr {[info exists jeu(eloMoi)] && [string is integer -strict $jeu(eloMoi)] && $jeu(eloMoi) > 0 ? $jeu(eloMoi) : 0}]
  if {$c != 0 && $moi > 0} {
    ::sergame::sendToEngine $n "setoption name WDLCalibrationElo value $moi"
    ::sergame::sendToEngine $n "setoption name ContemptMode value play"
    ::sergame::sendToEngine $n "setoption name Contempt value $c"
  } else {
    ::sergame::sendToEngine $n "setoption name Contempt value 0"
  }
  set jeu(enCours) 0
}

### "go" of a game against Toby: its analysis of the position is remembered
proc ::moderne::toby::goJeu {n} {
  variable reglagesJeu
  variable fenGo
  if {![estToby $n] || ![info exists reglagesJeu]} { return }
  # time trouble: the time control of the moment
  lassign $reglagesJeu b no cad
  set cad [cadenceZeitnot $cad [tempsParCoup]]
  catch {::sergame::sendToEngine $n "setoption name Time Control value $cad"}
  set fenGo($n) [list [sc_pos fen] $b $no $cad]
  variable tGo
  set tGo($n) [clock microseconds]
}

###
### During a game against Toby (or an Alter Ego): a second Toby process
### analyzes the player's position while she thinks (the graphics card is
### idle then), and its analyses are remembered like the others: at the end
### of the game, the annotation finds almost every position already done.
###

namespace eval ::moderne::toby::ombre {
  variable pipe {}
  variable fen {}       ;# position being analyzed
  variable n -1
  variable bloc {}
  variable enCours 0
}

### Called every second while it is the player's turn (sergame::engineGo)
### A game short enough (under 10 minutes: base + 40 increments) that no
### extra Toby runs beside the opponent: in a 1+0 game, the shadow and the
### level's Toby made the opponent take 10 s per move (Yosha 2026-11-09)
proc ::moderne::toby::ombre::partieRapide {} {
  if {![info exists ::sergame::timeMode] || $::sergame::timeMode ne "timebonus"} { return 0 }
  if {[catch {expr {$::sergame::wtime * 60 + 40 * $::sergame::winc}} t]} { return 0 }
  return [expr {$t < 600}]
}

### The engine's turn: the shadow's search stopped at once (it went on
### while the opponent thought)
proc ::moderne::toby::ombre::pause {} {
  variable enCours
  variable fen
  if {$enCours} { envoyer stop ; set enCours 0 ; set fen {} }
}

proc ::moderne::toby::ombre::voir {n} {
  variable pipe
  variable fen
  variable enCours
  if {![::moderne::toby::estToby $n] || ![winfo exists .serGameWin]} { arreter ; return }
  if {[partieRapide]} { arreter ; return }
  if {![info exists ::moderne::toby::reglagesJeu]} { return }
  set f [sc_pos fen]
  if {$f eq $fen} { return }
  lassign $::moderne::toby::reglagesJeu blanc noir cadence
  # already known (e.g. analyzed in the panel): nothing to do
  set connue [::moderne::toby::analyseConnue $f $blanc $noir $cadence]
  if {$connue ne {}} {
    set fen $f
    catch {versBarre $f [esBloc $connue] {}}
    return
  }
  if {$pipe eq {} && ![lancer $n]} { return }
  if {$enCours} { envoyer stop }
  set fen $f
  variable bloc {}
  envoyer "setoption name White Rating value $blanc"
  envoyer "setoption name Black Rating value $noir"
  envoyer "setoption name Time Control value [::moderne::toby::cadenceZeitnot $cadence [::moderne::toby::tempsParCoup]]"
  envoyer [::moderne::toby::positionPartie]
  envoyer go
  set enCours 1
}

proc ::moderne::toby::ombre::lancer {num} {
  variable pipe
  variable n $num
  set e [lindex $::engines(list) $num]
  set ancien [pwd]
  catch {cd [lindex $e 3]}
  set ok [catch {set pipe [open "| [list [lindex $e 1]] [lindex $e 2][::sibyErreursMoteur]" r+]}]
  catch {cd $ancien}
  if {$ok} { set pipe {} ; return 0 }
  ::moderne::prioriteBasse $pipe
  fconfigure $pipe -buffering line -blocking 0
  fileevent $pipe readable ::moderne::toby::ombre::lire
  envoyer uci
  foreach opt [lindex $e 8] {
    lassign $opt nom val
    if {$nom in {MultiPV UCI_AnalyseMode}} { continue }
    envoyer "setoption name $nom value $val"
  }
  foreach {nom val} {Display Full {Rating Source} FIDE {Move Model} Auto MultiPV 500 UCI_ShowWDL true Mode Prediction} {
    envoyer "setoption name $nom value $val"
  }
  return 1
}

proc ::moderne::toby::ombre::envoyer {t} {
  variable pipe
  if {$pipe ne {}} { catch {puts $pipe $t ; flush $pipe} }
}

proc ::moderne::toby::ombre::lire {} {
  variable pipe
  variable bloc
  variable fen
  variable enCours
  if {$pipe eq {}} { return }
  if {[eof $pipe]} { arreter ; return }
  while {$pipe ne {} && [gets $pipe l] >= 0} {
    set mots [split [regsub -all {\s+} [string trim $l] " "] " "]
    if {[lrange $mots 0 2] eq {info string toby}} {
      switch -- [lindex $mots 3] {
        begin {
          set bloc [dict create etape [::moderne::toby::champ $mots stage 1] \
                        final [::moderne::toby::champ $mots final 0] lignes {} position {}]
        }
        move {
          if {$bloc eq {}} { continue }
          set i [lsearch -exact $mots wdl]
          set wdl [expr {$i >= 0 ? [lrange $mots [expr {$i + 1}] [expr {$i + 3}]] : {- - -}}]
          dict lappend bloc lignes [dict create uci [lindex $mots 4] \
              san [::moderne::toby::champ $mots san {}] prob [::moderne::toby::champ $mots prob {}] \
              maia [::moderne::toby::champ $mots maia {}] wdl $wdl es [::moderne::toby::champ $mots es -]]
        }
        position {
          if {$bloc eq {}} { continue }
          dict set bloc position [dict create es [::moderne::toby::champ $mots es -]]
          set i [lsearch -exact $mots wdl]
          set wdl [expr {$i >= 0 ? [lrange $mots [expr {$i + 1}] [expr {$i + 3}]] : {}}]
          versBarre $fen [::moderne::toby::champ $mots es -] $wdl
        }
        end {
          if {$bloc eq {} || ![dict get $bloc final] || [dict get $bloc etape] < 3} { continue }
          if {![info exists ::moderne::toby::reglagesJeu] || $fen eq {}} { continue }
          lassign $::moderne::toby::reglagesJeu blanc noir cadence
          set ::moderne::toby::memoire([join [lrange [split $fen] 0 3]]|$blanc|$noir|$cadence) $bloc
          set bloc {}
        }
      }
    } elseif {[string match "bestmove*" $l]} {
      set enCours 0
    }
  }
}

### Evaluation bar during the game: expected score es and WDL (per mille)
### of the side to move in fen, turned to White's point of view
proc ::moderne::toby::ombre::versBarre {fen es wdl} {
  if {![string is double -strict $es]} { return }
  set noirs [expr {[lindex [split $fen] 1] eq "b"}]
  if {$noirs} { set es [expr {1.0 - $es}] }
  set x [expr {min(0.999, max(0.001, $es))}]
  set cp [expr {-log(1.0 / $x - 1.0) / 0.00368208 / 100.0}]
  set pct {}
  if {[llength $wdl] == 3 && [string is integer -strict [lindex $wdl 0]]} {
    lassign $wdl w d l
    if {$noirs} { lassign [list $l $w] w l }
    set pct [list [expr {round($w / 10.0)}] [expr {round($d / 10.0)}] [expr {round($l / 10.0)}]]
  }
  catch {::moderne::barres::valeurPartie [list [format %.2f $cp] 0 $pct]}
}

proc ::moderne::toby::ombre::arreter {} {
  catch {::moderne::barres::valeurPartie {}}
  variable pipe
  variable fen {}
  variable enCours 0
  if {$pipe eq {}} { return }
  set p $pipe
  set pipe {}
  catch {fileevent $p readable {}}
  catch {puts $p stop ; puts $p quit ; flush $p}
  catch {close $p}
}

### End Siby

### Toby started without the Hugging Face Hub round-trip when Maia-3 is
### already in the cache (Toby's advice, 2026-10-29: each Toby start asked
### the hub for a checkpoint it had; without the cache the variable is left
### unset, else the first start could not download it)
proc ::moderne::toby::horsLigneSiCache {} {
  if {[info exists ::env(HF_HUB_OFFLINE)]} { return }
  set racines {}
  if {[info exists ::env(HF_HOME)]} { lappend racines [file join $::env(HF_HOME) hub] }
  if {[info exists ::env(HF_HUB_CACHE)]} { lappend racines $::env(HF_HUB_CACHE) }
  foreach v {USERPROFILE HOME} {
    if {[info exists ::env($v)]} { lappend racines [file join $::env($v) .cache huggingface hub] }
  }
  foreach r $racines {
    if {[llength [glob -nocomplain -directory [file join $r models--UofTCSSLab--Maia3-79M snapshots] */*.pt]]} {
      set ::env(HF_HUB_OFFLINE) 1
      return
    }
  }
}
catch ::moderne::toby::horsLigneSiCache

### A file of Siby's "cache" folder (made if needed); the cache files of
### the 30/10 packages, next to the program, are moved there
proc ::moderne::toby::fichierCache {nom} {
  set d [file join $::scidUserDir cache]
  catch {file mkdir $d}
  set ancien [file join $::scidUserDir $nom]
  if {[file exists $ancien] && ![file exists [file join $d $nom]]} {
    catch {file rename $ancien [file join $d $nom]}
  }
  catch {file delete $ancien}
  return [file join $d $nom]
}

### Toby's Stockfish answers kept on disk from one review to the next
### (TOBY_SF_CACHE_FILE, Toby 2026-10-29; an older Toby ignores it). Set
### for every Toby Siby starts, the panels' included.
proc ::moderne::toby::cacheStockfish {} {
  if {[info exists ::env(TOBY_SF_CACHE_FILE)] || ![info exists ::scidUserDir]} { return }
  set ::env(TOBY_SF_CACHE_FILE) [file nativename [fichierCache toby_sf_cache]]
  # (100,000 positions, about 80 MB, loaded after Toby is ready: no slower
  # start, Toby 2026-10-30)
  if {![info exists ::env(TOBY_SF_CACHE_SIZE)]} { set ::env(TOBY_SF_CACHE_SIZE) 100000 }
}
catch ::moderne::toby::cacheStockfish

################################################################################
### Lichess / Chess.com ratings converted to their FIDE equivalent, for games
### against Toby: Toby then always plays over the board (Rating Source FIDE),
### as Yosha asked (2026-11-04). Port of Toby's toby_rating_convert.py (v2):
### ChessGoals' rating comparison tables (https://chessgoals.com/rating-comparison/),
### interpolated linearly; Lichess below the lowest FIDE point: one FIDE point
### per Lichess point; Chess.com below its lowest FIDE point: through its
### Lichess equivalent (the USCF column shared by both tables).
################################################################################

namespace eval ::moderne::toby::elo {
  # Chess.com: blitz, bullet, rapid, USCF, FIDE ({}: no data);
  # Lichess: blitz, bullet, rapid, classical, USCF, FIDE
  variable tableCC {
    {500 550 815 925 {}}
    {600 615 905 1000 {}}
    {700 685 995 1075 {}}
    {800 760 1085 1150 {}}
    {900 840 1170 1220 {}}
    {1000 920 1255 1285 {}}
    {1100 1010 1340 1350 1660}
    {1150 1055 1380 1385 1665}
    {1200 1100 1420 1415 1670}
    {1250 1145 1460 1445 1675}
    {1300 1195 1500 1475 1685}
    {1350 1240 1540 1510 1700}
    {1400 1290 1580 1540 1710}
    {1450 1340 1620 1570 1725}
    {1500 1385 1655 1600 1740}
    {1550 1435 1690 1630 1760}
    {1600 1485 1730 1655 1780}
    {1650 1540 1765 1685 1800}
    {1700 1590 1800 1715 1820}
    {1750 1640 1835 1745 1840}
    {1800 1690 1870 1775 1865}
    {1850 1745 1900 1805 1890}
    {1900 1795 1935 1835 1915}
    {1950 1850 1965 1860 1940}
    {2000 1900 1995 1890 1965}
    {2100 2005 2055 1950 2020}
    {2200 2110 2110 2010 2075}
    {2300 2215 2165 2070 2135}
    {2400 2320 2215 2130 2190}
    {2500 2425 2260 2195 2245}
    {2600 2530 2300 2255 2300}
    {2700 2630 2340 2325 2350}
    {2800 2725 2375 2390 2400}
    {2900 2825 2405 2460 2445}
    {3000 2915 2430 2535 2485}
  }
  variable tableLI {
    {1090 1060 1290 1505 925 {}}
    {1160 1120 1360 1540 1000 {}}
    {1225 1180 1425 1575 1075 {}}
    {1290 1240 1490 1610 1150 {}}
    {1360 1305 1555 1650 1220 {}}
    {1425 1375 1615 1690 1285 {}}
    {1490 1445 1680 1730 1350 1660}
    {1525 1480 1710 1750 1385 1665}
    {1555 1515 1740 1770 1415 1670}
    {1590 1550 1765 1795 1445 1675}
    {1620 1585 1795 1815 1475 1685}
    {1655 1625 1825 1835 1510 1700}
    {1685 1660 1850 1860 1540 1710}
    {1720 1700 1880 1880 1570 1725}
    {1755 1735 1905 1900 1600 1740}
    {1785 1775 1935 1925 1630 1760}
    {1820 1815 1960 1945 1655 1780}
    {1850 1855 1990 1970 1685 1800}
    {1885 1890 2015 1990 1715 1820}
    {1915 1930 2040 2015 1745 1840}
    {1950 1970 2065 2035 1775 1865}
    {1980 2010 2090 2055 1805 1890}
    {2015 2050 2115 2080 1835 1915}
    {2045 2095 2140 2100 1860 1940}
    {2080 2135 2165 2120 1890 1965}
    {2145 2215 2215 2165 1950 2020}
    {2210 2300 2260 2205 2010 2075}
    {2275 2380 2310 2245 2070 2135}
    {2340 2465 2355 2280 2130 2190}
    {2410 2550 2400 2320 2195 2245}
    {2475 2635 2445 2350 2255 2300}
    {2540 2715 2490 2385 2325 2350}
    {2610 2800 2530 2415 2390 2400}
    {2675 2885 2575 2440 2460 2445}
    {2745 2970 2615 2465 2535 2485}
  }
  variable colsCC {blitz 0 bullet 1 rapid 2}
  variable colsLI {blitz 0 bullet 1 rapid 2 classical 3}
}

### Sorted pairs {xs ys}: column col against column y (rows where y is known)
proc ::moderne::toby::elo::paires {table col y} {
  set p {}
  foreach r $table {
    set v [lindex $r $y]
    if {$v ne {}} { lappend p [list [lindex $r $col] $v] }
  }
  set xs {} ; set ys {}
  foreach e [lsort -real -index 0 $p] { lappend xs [lindex $e 0] ; lappend ys [lindex $e 1] }
  return [list $xs $ys]
}

### Linear interpolation; outside: the slope of the first or last segment
proc ::moderne::toby::elo::interp {x xs ys} {
  set n [llength $xs]
  if {$x <= [lindex $xs 0]} {
    set k 1
  } elseif {$x >= [lindex $xs end]} {
    set k [expr {$n - 1}]
  } else {
    set k 1
    while {$k < $n - 1 && [lindex $xs $k] <= $x} { incr k }
  }
  set x0 [lindex $xs [expr {$k - 1}]] ; set x1 [lindex $xs $k]
  set y0 [lindex $ys [expr {$k - 1}]] ; set y1 [lindex $ys $k]
  return [expr {$y0 + double($y1 - $y0) / ($x1 - $x0) * ($x - $x0)}]
}

### The table, and below it one point of a scale per point of the other
proc ::moderne::toby::elo::lin {x xs ys} {
  if {$x < [lindex $xs 0]} { return [expr {[lindex $ys 0] - ([lindex $xs 0] - $x)}] }
  return [interp $x $xs $ys]
}

proc ::moderne::toby::elo::linInv {y xs ys} {
  if {$y < [lindex $ys 0]} { return [expr {[lindex $xs 0] - ([lindex $ys 0] - $y)}] }
  return [interp $y $ys $xs]
}

### FIDE equivalent of a rating: plateforme FIDE, Lichess or Chess.com;
### cadence blitz, bullet, rapid, classical (Chess.com has no classical
### table: read as rapid)
proc ::moderne::toby::elo::versFide {r plateforme cadence} {
  variable tableCC
  variable tableLI
  variable colsCC
  variable colsLI
  set cadence [string tolower $cadence]
  switch -glob -- [string tolower $plateforme] {
    chess* {
      if {$cadence eq "classical"} { set cadence rapid }
      if {![dict exists $colsCC $cadence]} { set cadence blitz }
      set col [dict get $colsCC $cadence]
      lassign [paires $tableCC $col 4] xs ys
      if {$r >= [lindex $xs 0]} { return [expr {round([interp $r $xs $ys])}] }
      # (below: through the Lichess equivalent of that time control)
      lassign [paires $tableCC $col 3] cx cu
      lassign [paires $tableLI [dict get $colsLI $cadence] 4] lx lu
      return [versFide [linInv [lin $r $cx $cu] $lx $lu] Lichess $cadence]
    }
    lichess {
      if {![dict exists $colsLI $cadence]} { set cadence blitz }
      lassign [paires $tableLI [dict get $colsLI $cadence] 5] xs ys
      return [expr {round([lin $r $xs $ys])}]
    }
  }
  return $r
}

### A rating in the game's rating list (FIDE, "Lichess Blitz", "Chess.com
### Rapid"...): its FIDE equivalent
proc ::moderne::toby::elo::depuisSource {r source} {
  if {![string is double -strict $r] || $r <= 0} { return $r }
  set mots [split $source]
  if {[llength $mots] < 2} { return $r }
  return [versFide $r [lindex $mots 0] [lindex $mots 1]]
}
