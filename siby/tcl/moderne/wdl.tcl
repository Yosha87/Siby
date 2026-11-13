
###
### Siby: engine WDL (win / draw / loss) display
###
### Stockfish and Leela (lc0) can give, with the UCI_ShowWDL option, the
### probability of a win, draw and loss in addition to the evaluation. SCID vs. PC
### could already read these values (tcl/tools/uci.tcl), but the option had
### to be enabled by hand and the display was raw text.
###
### Here:
###  - the UCI_ShowWDL option is enabled automatically when the engine
###    offers it (unless it was set explicitly in the engine
###    configuration);
###  - a "1-0 / ½ / 0-1" bar is shown above the analysis
###    lines, from White's point of view (like the evaluation).
###

namespace eval ::moderne::wdl {
  # Enable UCI_ShowWDL automatically (0 to restore the original behavior)
  variable auto 1
  variable hauteur 22
}

### Should "setoption name UCI_ShowWDL value true" be sent to engine n?
proc ::moderne::wdl::doitActiver {n} {
  variable auto
  if {!$auto} { return 0 }
  if {![info exists ::analysis(uciOptions$n)]} { return 0 }
  set propose 0
  foreach opt $::analysis(uciOptions$n) {
    if {[lindex $opt 0] eq "UCI_ShowWDL"} { set propose 1 ; break }
  }
  if {!$propose} { return 0 }
  # Explicit setting by the user: respect it
  foreach opt [lindex $::engines(list) $n 8] {
    if {[lindex $opt 0] eq "UCI_ShowWDL"} { return 0 }
  }
  return 1
}

### Creates the bar (hidden as long as the engine sends no WDL)
proc ::moderne::wdl::creer {w} {
  variable hauteur
  if {[winfo exists $w.wdl]} { return }
  canvas $w.wdl -height $hauteur -highlightthickness 0 -borderwidth 0
  bind $w.wdl <Configure> [list ::moderne::wdl::redessiner $w]
}

proc ::moderne::wdl::redessiner {w} {
  if {[::moderne::actif] && [info exists ::moderne::wdl::moteurDe($w)]} {
    catch {::moderne::barres::horizontale $w.wdl $::moderne::wdl::moteurDe($w)}
  } else {
    ::moderne::wdl::dessiner $w
  }
}

### Updates the bar of analysis window n. It is shown only if
### the bars are placed in the engine windows (otherwise they are
### next to the board: tcl/moderne/barres.tcl).
proc ::moderne::wdl::mettreAJour {n} {
  set w .analysisWin$n
  if {![winfo exists $w]} { return }
  ::moderne::wdl::creer $w
  set dansMoteur [expr {[info exists ::moderne::barres::place] && $::moderne::barres::place eq "moteur" &&
                        [info exists ::moderne::barres::actif] && $::moderne::barres::actif}]
  if {![::moderne::actif]} {
    # Original look: WDL bar as before
    set dansMoteur [expr {[info exists ::analysis(seenWDL$n)] && $::analysis(seenWDL$n) && [info exists ::analysis(WDLval$n,0)]}]
  }
  if {!$dansMoteur} {
    if {[winfo ismapped $w.wdl]} { pack forget $w.wdl }
    return
  }
  if {![winfo ismapped $w.wdl] && [winfo exists $w.hist]} {
    if {[winfo exists $w.lc0] && [winfo ismapped $w.lc0]} {
      pack $w.wdl -side top -fill x -padx 4 -pady {4 2} -before $w.lc0
    } else {
      pack $w.wdl -side top -fill x -padx 4 -pady {4 2} {*}[::moderne::avantHist $w]
    }
  }
  set ::moderne::wdl::moteurDe($w) $n
  if {[::moderne::actif]} {
    catch {::moderne::barres::horizontale $w.wdl $n}
    return
  }
  set ::moderne::wdl::valeurs($w) $::analysis(WDLval$n,0)
  ::moderne::wdl::dessiner $w
}

proc ::moderne::wdl::dessiner {w} {
  variable hauteur
  if {![winfo exists $w.wdl] || ![info exists ::moderne::wdl::valeurs($w)]} { return }
  lassign $::moderne::wdl::valeurs($w) gain nulle perte
  set c $w.wdl
  $c delete all
  set larg [winfo width $c]
  if {$larg < 30} { return }
  set police font_Small
  set fond [expr {[::moderne::actif] ? [::moderne::c fond] : [$c cget -background]}]
  set doux [expr {[::moderne::actif] ? [::moderne::c texteDoux] : "#555555"}]
  $c configure -background $fond
  # Thin bar at the top (White / draw / Black), numbers below
  set e 6
  set x 0
  foreach {val coul} [list $gain #e8e8e8 $nulle #7a7a7a $perte #0b0b0b] {
    set l [expr {$larg * $val / 100.0}]
    if {$l > 0} { $c create rectangle $x 0 [expr {$x + $l}] $e -fill $coul -outline {} }
    set x [expr {$x + $l}]
  }
  if {[::moderne::actif] && $::moderne::theme eq "sombre"} {
    $c create rectangle 0 0 [expr {$larg - 1}] [expr {$e - 1}] -outline #3a3a3a
  }
  set y [expr {$e + 3}]
  $c create text 0 $y -anchor nw -font $police -fill $doux -text "1-0  $gain %"
  $c create text [expr {$larg / 2.0}] $y -anchor n -font $police -fill $doux -text "\u00bd  $nulle %"
  $c create text $larg $y -anchor ne -font $police -fill $doux -text "0-1  $perte %"
  set h [expr {$y + [font metrics $police -linespace] + 1}]
  if {[$c cget -height] != $h} { $c configure -height $h }
}

### Compact text for a MultiPV line: "52/40/8"
proc ::moderne::wdl::court {n idx} {
  if {![info exists ::analysis(seenWDL$n)] || !$::analysis(seenWDL$n) ||
      ![info exists ::analysis(WDLval$n,$idx)]} {
    return {}
  }
  return [join $::analysis(WDLval$n,$idx) /]
}

### White's chances (expected score in %) for each ply of the
### game: the engine's [%wdl w,d,l] annotation if present, otherwise computed
### from the evaluation (Lichess formula: 50 + 50 × (2 / (1 + e^(−0.00368 × cp)) − 1)).
### scores: list {x evaluation…} from "sc_game scores"; returns {x pct…}
proc ::moderne::wdl::chancesPartie {scores} {
  array set pct {}
  foreach {x e} $scores {
    if {![string is double -strict $e]} { continue }
    set cp [expr {$e * 100.0}]
    if {$cp > 2000} { set cp 2000 } elseif {$cp < -2000} { set cp -2000 }
    set pct($x) [expr {50.0 + 50.0 * (2.0 / (1.0 + exp(-0.00368208 * $cp)) - 1.0)}]
  }
  foreach {x v} [sc_game values wdl] {
    set p [split $v ,]
    if {[llength $p] == 3 && [string is double -strict [lindex $p 0]] && [string is double -strict [lindex $p 1]]} {
      set pct($x) [expr {[lindex $p 0] + [lindex $p 1] / 2.0}]
    }
  }
  set res {}
  foreach x [lsort -real [array names pct]] { lappend res $x [format %.1f $pct($x)] }
  return $res
}

### End Siby
