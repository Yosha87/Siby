
###
### Siby: player mistake report (tab of the preparation window)
###
### The engine (the F2 one, usually Stockfish) analyzes the player's last N
### games, position by position, with a fixed time per move.
### For each of the player's moves, winning chances before and after are
### compared (same formula as Lichess):
###   - move accuracy: 103.17 × e^(−0.0435 × loss) − 3.17 (from 0 to 100);
###   - inaccuracy / mistake / blunder: loss of 5 / 10 / 15 points of winning
###     chances (Lichess thresholds), with the centipawn loss shown alongside.
### Results: accuracy and average loss per phase (opening = first 15
### moves, endgame = few pieces left) and per color, then the list of the
### player's mistakes (double-click: the game opens just before the move).
### Evaluations are kept on disk (data/evaluations.dat):
### rerunning the analysis on the same games is instant.
###

namespace eval ::moderne::erreurs {
  variable nbParties 20      ;# games analyzed (the most recent ones)
  variable tempsCoup 300     ;# milliseconds per position
  variable pipe {}
  variable etat idle         ;# idle | init | analyse
  variable file {}           ;# positions to analyze: {gnum ply fen}
  variable courant {}
  variable score {}          ;# last score received {cp|mate value}
  variable meilleur {}
  variable evals             ;# evals(fen) = {cpWhite uciMove}
  array set evals {}
  variable charge 0          ;# disk cache loaded
  variable parties {}        ;# {gnum color gameDict fens}
  variable total 0
  variable fait 0
}

proc ::moderne::erreurs::T {fr en} { return [::moderne::tr $fr $en] }

################################################################################
### Tab
################################################################################

proc ::moderne::erreurs::creer {f} {
  ttk::frame $f.h -padding {10 8 10 4}
  pack $f.h -side top -fill x
  ttk::label $f.h.ln -text [T "Ses" "Their"]
  ttk::spinbox $f.h.n -width 4 -from 1 -to 500 -textvariable ::moderne::erreurs::nbParties
  ttk::label $f.h.ln2 -text [T "dernières parties, temps par position :" "latest games, time per position:"]
  ttk::spinbox $f.h.t -width 6 -from 50 -to 10000 -increment 50 -textvariable ::moderne::erreurs::tempsCoup
  ttk::label $f.h.lt -text ms
  ttk::button $f.h.go -text [T "Analyser au moteur" "Analyse with engine"] -command ::moderne::erreurs::lancer
  ttk::button $f.h.stop -text [T "Arrêter" "Stop"] -command ::moderne::erreurs::arreter -state disabled
  pack $f.h.ln $f.h.n $f.h.ln2 $f.h.t $f.h.lt -side left -padx 3
  pack $f.h.go $f.h.stop -side left -padx {10 3}
  ttk::label $f.etat -padding {12 2} -wraplength 900 -justify left -text [T \
"Le moteur de la touche F2 (Stockfish) analyse ses parties les plus récentes (filtres de la préparation : période, cadence, Elo adverse). Compter environ 80 positions par partie : 20 parties à 300 ms ≈ 8 minutes ; les évaluations sont gardées pour les fois suivantes." \
"The F2 engine analyses their latest games (preparation filters apply). About 80 positions per game; evaluations are cached."]
  pack $f.etat -side top -fill x

  # Key figures
  ttk::frame $f.cles -padding {10 4}
  foreach k {precision acpl gaffes erreurs} {
    ttk::frame $f.cles.$k -padding {14 4}
    ttk::label $f.cles.$k.v -font font_H2 -text {}
    ttk::label $f.cles.$k.l -text {}
    pack $f.cles.$k.v $f.cles.$k.l -side top -anchor w
    pack $f.cles.$k -side left
  }
  pack $f.cles -side top -fill x

  # By phase and by color
  ttk::treeview $f.phases -columns {coups precision acpl impr err gaffes} -height 7 -selectmode none
  $f.phases heading #0 -text [T "Phase" "Phase"] -anchor w
  $f.phases column #0 -width 200 -stretch 0
  foreach {c fr en l} {coups Coups Moves 70 precision Précision Accuracy 90 acpl "Perte moy. (cp)" "Avg loss (cp)" 120
                       impr Imprécisions Inaccuracies 100 err Erreurs Mistakes 80 gaffes Gaffes Blunders 80} {
    $f.phases heading $c -text [T $fr $en]
    $f.phases column $c -width $l -anchor e -stretch 0
  }
  $f.phases tag configure total -font font_Bold
  pack $f.phases -side top -fill x -padx 10 -pady 4

  # The player's mistakes
  ttk::label $f.tl -font font_Bold -padding {10 6 10 2} -text [T "Ses erreurs et gaffes (double-clic : ouvrir la partie avant son coup)" "Their mistakes and blunders (double-click: open the game before their move)"]
  pack $f.tl -side top -anchor w
  ttk::frame $f.l
  pack $f.l -side top -fill both -expand 1 -padx 10 -pady {0 10}
  ttk::treeview $f.l.t -columns {type coup avant apres mieux phase partie} -show headings -selectmode browse
  foreach {c fr en l ancre} {
    type   Type          Type          80  w
    coup   Coup          Move          95  w
    avant  Avant         Before        70  e
    apres  Après         After         70  e
    mieux  "Le moteur préférait" "Engine preferred" 130 w
    phase  Phase         Phase         90  w
    partie Partie        Game         380  w
  } {
    $f.l.t heading $c -text [T $fr $en] -anchor [expr {$ancre eq "e" ? "e" : "w"}]
    $f.l.t column $c -width $l -anchor $ancre -stretch [expr {$c eq "partie"}]
  }
  ::moderne::tri::activer $f.l.t
  set sombre [expr {[::moderne::actif] && $::moderne::theme eq "sombre"}]
  $f.l.t tag configure gaffe -foreground [expr {$sombre ? "#ef8f7f" : "#b23a2a"}]
  $f.l.t tag configure erreur -foreground [expr {$sombre ? "#f0b35b" : "#a35a00"}]
  ttk::scrollbar $f.l.sb -command [list $f.l.t yview]
  $f.l.t configure -yscrollcommand [list $f.l.sb set]
  pack $f.l.sb -side right -fill y
  pack $f.l.t -side left -fill both -expand 1
  bind $f.l.t <Double-Button-1> {::moderne::erreurs::ouvrirErreur %W ; break}
  bind $f.l.t <Return> {::moderne::erreurs::ouvrirErreur %W ; break}
}

proc ::moderne::erreurs::cadre {} { return .prepaWin.nb.erreurs }

################################################################################
### Evaluation cache (text file: fen \t ms \t cp \t move)
################################################################################

proc ::moderne::erreurs::fichierCache {} {
  set dir [file join $::scidUserDir data]
  file mkdir $dir
  return [file join $dir evaluations.dat]
}

proc ::moderne::erreurs::chargerCache {} {
  variable evals
  variable charge
  if {$charge} { return }
  set charge 1
  set f [fichierCache]
  if {![file exists $f]} { return }
  catch {
    set c [open $f r]
    while {[gets $c l] >= 0} {
      lassign [split $l \t] fen ms cp coup
      if {![string is integer -strict $ms] || ![string is integer -strict $cp]} { continue }
      # keep the longest analysis
      if {![info exists evals($fen)] || [lindex $evals($fen) 2] < $ms} {
        set evals($fen) [list $cp $coup $ms]
      }
    }
    close $c
  }
}

proc ::moderne::erreurs::noterCache {fen cp coup ms} {
  variable evals
  set evals($fen) [list $cp $coup $ms]
  catch {
    set c [open [fichierCache] a]
    puts $c "$fen\t$ms\t$cp\t$coup"
    close $c
  }
}

### FEN key without the move counters (same position = same evaluation)
proc ::moderne::erreurs::cleFen {fen} { return [join [lrange [split $fen] 0 3] " "] }

################################################################################
### Launch
################################################################################

proc ::moderne::erreurs::moteur {} {
  # F2 engine, otherwise the first one whose name contains "stockfish", otherwise the first one
  set n {}
  if {[info exists ::engines(F2)] && [string is integer -strict $::engines(F2)] &&
      $::engines(F2) < [llength $::engines(list)]} { set n $::engines(F2) }
  if {$n eq {}} {
    set i 0
    foreach e $::engines(list) {
      if {[string match -nocase *stockfish* [lindex $e 0]]} { set n $i ; break }
      incr i
    }
  }
  if {$n eq {} && [llength $::engines(list)]} { set n 0 }
  if {$n eq {}} { return {} }
  return [lindex $::engines(list) $n]
}

proc ::moderne::erreurs::lancer {} {
  variable nbParties
  variable tempsCoup
  variable file
  variable parties
  variable total
  variable fait
  variable etat
  variable evals
  set f [cadre]
  if {![winfo exists $f.etat]} { return }
  if {$etat ne "idle"} { return }
  set lesParties $::moderne::prepa::parties
  if {![llength $lesParties]} {
    $f.etat configure -text [T "Prépare d'abord un joueur ou une joueuse (en haut)." "Prepare a player first (top)."]
    return
  }
  if {![string is integer -strict $nbParties] || $nbParties < 1} { set nbParties 20 }
  if {![string is integer -strict $tempsCoup] || $tempsCoup < 20} { set tempsCoup 300 }
  set e [moteur]
  if {$e eq {}} {
    $f.etat configure -text [T "Aucun moteur configuré (Outils › Moteurs d'analyse)." "No engine configured."]
    return
  }
  chargerCache
  # The player's N most recent games
  set tri [lsort -decreasing -command ::moderne::comparerDates $lesParties]
  set base $::moderne::prepa::base
  set courante [sc_base current]
  if {$courante != $base} { sc_base switch $base }
  set parties {}
  set file {}
  foreach p [lrange $tri 0 [expr {$nbParties - 1}]] {
    set g [dict get $p gnum]
    # (each game in its own database: main database or online games)
    set pb [expr {[dict exists $p base] ? [dict get $p base] : $base}]
    if {[sc_base current] != $pb} { sc_base switch $pb }
    if {[catch {sc_game fens $g 160} fens]} { continue }
    lappend parties [list $g [dict get $p couleur] $p $fens]
    foreach x $fens {
      set fen [lindex $x 1]
      set k [cleFen $fen]
      if {[info exists evals($k)] && [lindex $evals($k) 2] >= $tempsCoup} { continue }
      if {$k ni $file} { lappend file $k }
    }
  }
  if {[sc_base current] != $courante} { sc_base switch $courante }
  set total [llength $file]
  set fait 0
  if {$total == 0} { rapport ; return }
  if {![demarrerMoteur $e]} { return }
  $f.h.go configure -state disabled
  $f.h.stop configure -state normal
  progression
}

proc ::moderne::erreurs::progression {} {
  variable total
  variable fait
  variable tempsCoup
  set f [cadre]
  if {![winfo exists $f]} { return }
  set reste [expr {($total - $fait) * $tempsCoup / 1000}]
  $f.etat configure -text "[T "Analyse en cours" "Analysing"] : $fait / $total [T positions positions] • [T "environ" "about"] [expr {$reste / 60}] min [expr {$reste % 60}] s [T "restantes" "left"]"
}

################################################################################
### UCI dialogue (asynchronous)
################################################################################

proc ::moderne::erreurs::demarrerMoteur {e} {
  variable pipe
  variable etat
  variable moteurN [::moderne::occupation::index $e]
  if {![::moderne::occupation::prendre $moteurN erreurs {::moderne::erreurs::arreter ; ::moderne::erreurs::fermer}]} {
    catch {[cadre].etat configure -text [T "Annulé : le moteur est utilisé ailleurs." "Cancelled: the engine is used elsewhere."]}
    return 0
  }
  set cmd [lindex $e 1]
  set args [lindex $e 2]
  set dir [lindex $e 3]
  set ancien [pwd]
  catch {cd $dir}
  set ok [catch {set pipe [open "| [list $cmd] $args[::sibyErreursMoteur]" r+]} err]
  catch {cd $ancien}
  if {$ok} {
    [cadre].etat configure -text "[T "Impossible de lancer le moteur" "Cannot start the engine"] : $err"
    set pipe {}
    return 0
  }
  fconfigure $pipe -buffering line -blocking 0
  fileevent $pipe readable ::moderne::erreurs::lire
  set etat init
  envoyer uci
  # Engine settings (Threads, Hash…) as configured in SCID
  foreach opt [lindex $e 8] {
    lassign $opt nom val
    if {$nom in {MultiPV UCI_AnalyseMode}} { continue }
    envoyer "setoption name $nom value $val"
  }
  envoyer isready
  return 1
}

proc ::moderne::erreurs::envoyer {texte} {
  variable pipe
  if {$pipe eq {}} { return }
  catch {puts $pipe $texte ; flush $pipe}
}

proc ::moderne::erreurs::lire {} {
  variable pipe
  variable etat
  variable score
  variable meilleur
  if {$pipe eq {}} { return }
  if {[eof $pipe]} { fermer ; return }
  # (the engine may be closed during the loop, at the end of the analysis)
  while {$pipe ne {} && [gets $pipe l] >= 0} {
    if {$etat eq "init"} {
      if {$l eq "readyok"} { set etat analyse ; suivante }
      continue
    }
    if {[string match "info *" $l]} {
      if {[regexp {score (cp|mate) (-?[0-9]+)} $l -> t v]} {
        # (lowerbound / upperbound bounds are ignored)
        if {![regexp {score (cp|mate) -?[0-9]+ (lower|upper)bound} $l]} { set score [list $t $v] }
      }
      if {[regexp { pv ([a-h][1-8][a-h][1-8][qrbn]?)} $l -> c]} { set meilleur $c }
    } elseif {[regexp {^bestmove (\S+)} $l -> c]} {
      if {$meilleur eq {}} { set meilleur $c }
      fini
    }
  }
}

proc ::moderne::erreurs::suivante {} {
  variable file
  variable courant
  variable score
  variable meilleur
  variable tempsCoup
  if {![llength $file]} { termine ; return }
  set courant [lindex $file 0]
  set file [lrange $file 1 end]
  set score {}
  set meilleur {}
  envoyer "position fen $courant 0 1"
  envoyer "go movetime $tempsCoup"
}

proc ::moderne::erreurs::fini {} {
  variable courant
  variable score
  variable meilleur
  variable tempsCoup
  variable fait
  if {$courant ne {} && [llength $score]} {
    lassign $score t v
    # Score from the side-to-move's point of view -> White's point of view
    if {$t eq "mate"} {
      set cp [expr {$v > 0 ? 10000 - 10 * $v : -10000 - 10 * $v}]
    } else {
      set cp $v
    }
    if {[lindex [split $courant] 1] eq "b"} { set cp [expr {-$cp}] }
    noterCache $courant $cp $meilleur $tempsCoup
  }
  incr fait
  if {$fait % 5 == 0} { progression }
  suivante
}

proc ::moderne::erreurs::arreter {} {
  variable file
  set file {}
  envoyer stop
}

proc ::moderne::erreurs::termine {} {
  fermer
  rapport
}

proc ::moderne::erreurs::fermer {} {
  variable pipe
  variable etat
  variable moteurN
  if {[info exists moteurN]} { ::moderne::occupation::liberer $moteurN erreurs }
  if {$pipe ne {}} {
    catch {fileevent $pipe readable {}}
    catch {puts $pipe quit ; flush $pipe}
    catch {close $pipe}
  }
  set pipe {}
  set etat idle
  set f [cadre]
  if {[winfo exists $f]} {
    $f.h.go configure -state normal
    $f.h.stop configure -state disabled
  }
}

################################################################################
### Report
################################################################################

### Winning chances (0–100) from White's point of view, Lichess formula
proc ::moderne::erreurs::chances {cp} {
  if {$cp > 1000} { set cp 1000 } elseif {$cp < -1000} { set cp -1000 }
  return [expr {50.0 + 50.0 * (2.0 / (1.0 + exp(-0.00368208 * $cp)) - 1.0)}]
}

### Non-pawn material (Q9 R5 B3 N3) of both sides, from a FEN
proc ::moderne::erreurs::materiel {fen} {
  set p [lindex [split $fen] 0]
  set m 0
  foreach c [split $p {}] {
    switch -- [string tolower $c] { q { incr m 9 } r { incr m 5 } b - n { incr m 3 } }
  }
  return $m
}

proc ::moderne::erreurs::phase {ply fen} {
  if {$ply < 30} { return ouverture }
  if {[materiel $fen] <= 26} { return finale }
  return milieu
}

### UCI move -> SAN (in the interface language), without touching the game
proc ::moderne::erreurs::san {fen uci} {
  if {$uci eq {}} { return {} }
  set r $uci
  catch {
    set r [::moderne::entrainement::brouillon {
      sc_game startBoard $fen
      string trim [sc_move addUCI $uci]
    }]
  }
  return [::trans $r]
}

proc ::moderne::erreurs::texteEval {cp} {
  if {$cp >= 9000} { return "#[expr {(10000 - $cp) / 10}]" }
  if {$cp <= -9000} { return "-#[expr {(10000 + $cp) / 10}]" }
  return [format %+.2f [expr {$cp / 100.0}]]
}

proc ::moderne::erreurs::rapport {} {
  variable parties
  variable evals
  set f [cadre]
  if {![winfo exists $f]} { return }
  array set acc {}
  set liste {}
  foreach pr $parties {
    lassign $pr g couleur p fens
    set n [llength $fens]
    for {set i 0} {$i + 1 < $n} {incr i} {
      set fen [lindex $fens $i 1]
      set trait [expr {[lindex [split $fen] 1] eq "w" ? "white" : "black"}]
      if {$trait ne $couleur} { continue }
      set k1 [cleFen $fen]
      set fen2 [lindex $fens [expr {$i + 1}] 1]
      set k2 [cleFen $fen2]
      if {![info exists evals($k1)] || ![info exists evals($k2)]} { continue }
      set cp1 [lindex $evals($k1) 0]
      set cp2 [lindex $evals($k2) 0]
      # Player's point of view
      set sens [expr {$couleur eq "white" ? 1 : -1}]
      set w1 [chances [expr {$sens * $cp1}]]
      set w2 [chances [expr {$sens * $cp2}]]
      set perte [expr {max(0.0, $w1 - $w2)}]
      set precision [expr {max(0.0, min(100.0, 103.1668 * exp(-0.04354 * $perte) - 3.1669))}]
      set c1 [expr {max(-1000, min(1000, $sens * $cp1))}]
      set c2 [expr {max(-1000, min(1000, $sens * $cp2))}]
      set pcp [expr {max(0, $c1 - $c2)}]
      set ph [phase $i $fen]
      set type {}
      if {$perte >= 15} { set type gaffe } elseif {$perte >= 10} { set type erreur } elseif {$perte >= 5} { set type impr }
      foreach cle [list "$ph,$couleur" "$ph,tout" "tout,$couleur" "tout,tout"] {
        if {![info exists acc($cle)]} { set acc($cle) {0 0.0 0 0 0 0} }
        lassign $acc($cle) nb sp scp ni ne ng
        incr nb ; set sp [expr {$sp + $precision}] ; incr scp $pcp
        if {$type eq "impr"} { incr ni } elseif {$type eq "erreur"} { incr ne } elseif {$type eq "gaffe"} { incr ng }
        set acc($cle) [list $nb $sp $scp $ni $ne $ng]
      }
      if {$type in {erreur gaffe}} {
        set coup [lindex $fens [expr {$i + 1}] 0]
        set num [expr {$i / 2 + 1}]
        set texteCoup [expr {$trait eq "white" ? "$num.[::trans $coup]" : "$num...[::trans $coup]"}]
        append texteCoup [expr {$type eq "gaffe" ? "??" : "?"}]
        set pb [expr {[dict exists $p base] ? [dict get $p base] : $::moderne::prepa::base}]
        lappend liste [list $perte $type $texteCoup [texteEval $cp1] [texteEval $cp2] \
            [san $fen [lindex $evals($k1) 1]] $ph $g $i $p $pb]
      }
    }
  }
  # Key figures and table
  set t $f.phases
  $t delete [$t children {}]
  if {![info exists acc(tout,tout)]} {
    $f.etat configure -text [T "Pas d'évaluation disponible : lance l'analyse." "No evaluations yet: run the analysis."]
    return
  }
  lassign $acc(tout,tout) nb sp scp ni ne ng
  set nP [llength $parties]
  $f.cles.precision.v configure -text "[format %.0f [expr {$sp / $nb}]] %"
  $f.cles.precision.l configure -text [T "précision moyenne" "average accuracy"]
  $f.cles.acpl.v configure -text [expr {$scp / $nb}]
  $f.cles.acpl.l configure -text [T "perte moyenne (centipions)" "average loss (centipawns)"]
  $f.cles.gaffes.v configure -text [format %.1f [expr {double($ng) / $nP}]]
  $f.cles.gaffes.l configure -text [T "gaffes par partie" "blunders per game"]
  $f.cles.erreurs.v configure -text [format %.1f [expr {double($ne) / $nP}]]
  $f.cles.erreurs.l configure -text [T "erreurs par partie" "mistakes per game"]
  foreach {ph lib} [list ouverture [T "Ouverture (coups 1–15)" "Opening (moves 1–15)"] milieu [T "Milieu de partie" "Middlegame"] \
                         finale [T "Finale" "Endgame"] tout [T "Toute la partie" "Whole game"]] {
    foreach c {tout white black} lc [list {} [T "avec les Blancs" "as White"] [T "avec les Noirs" "as Black"]] {
      if {![info exists acc($ph,$c)]} { continue }
      lassign $acc($ph,$c) nb sp scp ni ne ng
      set tag [expr {$c eq "tout" ? "total" : ""}]
      set texte [expr {$c eq "tout" ? $lib : "    $lc"}]
      $t insert {} end -text $texte -tags $tag -values [list $nb "[format %.0f [expr {$sp / $nb}]] %" \
          [expr {$scp / $nb}] $ni $ne $ng]
    }
  }
  # List of mistakes, most serious first
  set l $f.l.t
  $l delete [$l children {}]
  foreach e [lsort -real -decreasing -index 0 $liste] {
    lassign $e perte type texteCoup avant apres mieux ph g i p pb
    set lib [expr {$type eq "gaffe" ? [T Gaffe Blunder] : [T Erreur Mistake]}]
    set qui [expr {[dict get $p couleur] eq "white" ? [T "Blancs" "White"] : [T "Noirs" "Black"]}]
    $l insert {} end -id "e${pb}_$g,$i" -tags $type -values [list $lib $texteCoup $avant $apres $mieux \
        [dict get {ouverture Ouverture milieu Milieu finale Finale} $ph] \
        "[::moderne::prepa::date [dict get $p date]] • $qui [T contre vs] [dict get $p adversaire] • [dict get $p tournoi]"]
  }
  $f.etat configure -text "[T "Analyse de" "Analysis of"] $nP [T "parties" "games"] • [T "ses coups" "their moves"] : $nb \
([T "moteur" "engine"] : [lindex [moteur] 0]). [T "Précision et seuils comme sur Lichess." "Accuracy and thresholds as on Lichess."]"
}

proc ::moderne::erreurs::ouvrirErreur {t} {
  set id [$t focus]
  if {![regexp {^e([0-9]+)_([0-9]+),([0-9]+)$} $id -> b g i]} { return }
  ::moderne::biblio::ouvrirPartie $b $g $i
}

### End Siby
