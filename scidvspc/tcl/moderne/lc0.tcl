
###
### Siby: Leela (lc0) per-move statistics
###
### With the VerboseMoveStats and LogLiveStats options, lc0 sends for each
### candidate move a line such as:
###   info string d2d4  (293 ) N:  1234 (+ 5) (P: 12.34%) (WL:  0.0123) (D: 0.456)
###                     (M: 120.3) (Q:  0.0123) (U: 0.0123) (S: 0.1234) (V:  0.0123)
### then a "node" line summarizing the position. SCID used to ignore them.
### Here, they are shown in a table in the analysis window:
###   move, visits (N and % of visits), network policy (P),
###   win / draw / loss in % (from White's point of view, like the evaluation).
### Both options are enabled automatically when the engine
### offers them (that is, for lc0), unless set explicitly.
###

namespace eval ::moderne::lc0 {
  variable auto 0          ;# enable VerboseMoveStats / LogLiveStats automatically (off since
                           ;# 2026-10-31: Leela shown as the other engines, eval / W/D/L / line)
  variable maxLignes 10    ;# moves shown
  variable bloc            ;# bloc(n): lines of the block being received
  array set bloc {}
  variable fen             ;# fen(n): position sent to the engine (to write the moves)
  array set fen {}
  variable ignorer         ;# ignorer(n): lines from a stopped search
  array set ignorer {}
}

### Before "position … go" (tcl/tools/analysis.tcl): new position
proc ::moderne::lc0::avantGo {n} {
  variable fen
  variable ignorer
  variable bloc
  set fen($n) [sc_pos fen]
  catch {set f [::moderne::menace::fen $n] ; if {$f ne {}} { set fen($n) $f }}
  set ignorer($n) 0
  catch {unset bloc($n)}
  catch {.analysisWin$n.lc0 delete [.analysisWin$n.lc0 children {}]}
}

### After "stop": statistics still arriving belong to
### the old position
proc ::moderne::lc0::stopEnvoye {n} {
  variable ignorer
  set ignorer($n) 1
}

### UCI move (e2e4) → the user's notation (Cf3, Nf3…) in position fen
proc ::moderne::lc0::san {n uci} {
  variable fen
  set f [expr {[info exists fen($n)] ? $fen($n) : [sc_pos fen]}]
  set s {}
  catch {set s [string trim [::uci::formatPv $n $uci $f]]}
  if {$s eq {}} { return {} }
  return [::trans $s]
}

### Options to send to engine n: list of {name value}
proc ::moderne::lc0::optionsAuto {n} {
  variable auto
  if {!$auto || ![info exists ::analysis(uciOptions$n)]} { return {} }
  set proposees {}
  foreach opt $::analysis(uciOptions$n) { lappend proposees [lindex $opt 0] }
  set reglees {}
  foreach opt [lindex $::engines(list) $n 8] { lappend reglees [lindex $opt 0] }
  set res {}
  foreach o {VerboseMoveStats LogLiveStats} {
    if {$o in $proposees && $o ni $reglees} { lappend res [list $o true] }
  }
  return $res
}

### Called by tcl/tools/uci.tcl for each "info string …" line
proc ::moderne::lc0::ligne {n texte} {
  variable bloc
  variable ignorer
  if {[info exists ignorer($n)] && $ignorer($n)} { return }
  # texte = what follows "info string"
  if {![regexp {^(\S+)\s+\(\s*\d+\s*\)\s+N:\s*(\d+)} $texte -> coup visites]} { return }
  set p {} ; set wl {} ; set d {} ; set q {}
  regexp {\(P:\s*([-0-9.]+)%\)} $texte -> p
  regexp {\(WL:\s*([-0-9.]+)\)} $texte -> wl
  regexp {\(D:\s*([-0-9.]+)\)} $texte -> d
  regexp {\(Q:\s*([-0-9.]+)\)} $texte -> q
  if {$coup eq "node"} {
    set lignes [expr {[info exists bloc($n)] ? $bloc($n) : {}}]
    set bloc($n) {}
    afficher $n $lignes $visites
    return
  }
  lappend bloc($n) [list $coup $visites $p $wl $d $q]
}

proc ::moderne::lc0::creer {w} {
  if {[winfo exists $w.lc0]} { return }
  set T ::moderne::tr
  set t $w.lc0
  ttk::treeview $t -columns {n pct p gain nulle perte} -show {tree headings} -height 6 -selectmode none
  $t heading #0 -text [$T "Coup (Leela)" "Move (Leela)"] -anchor w
  foreach {c fr en l} {
    n     Visites   Visits     70
    pct   %         %          50
    p     Politique Policy     75
    gain  1-0       1-0        50
    nulle \u00bd    \u00bd     50
    perte 0-1       0-1        50
  } {
    $t heading $c -text [$T $fr $en]
    $t column $c -width $l -anchor e -stretch 0
  }
  $t column #0 -width 90 -stretch 1
}

### Shows the moves of the received block (sorted by visits)
proc ::moderne::lc0::afficher {n lignes total} {
  variable maxLignes
  set w .analysisWin$n
  if {![winfo exists $w] || ![llength $lignes]} { return }
  creer $w
  set t $w.lc0
  if {![winfo ismapped $t] && [winfo exists $w.hist]} {
    # order: WDL bar, Leela table, analysis lines
    if {[winfo exists $w.wdl] && [winfo ismapped $w.wdl]} {
      pack $t -side top -fill x -padx 4 -pady 2 -after $w.wdl
    } else {
      pack $t -side top -fill x -padx 4 -pady 2 {*}[::moderne::avantHist $w]
    }
  }
  $t delete [$t children {}]
  set noirs [expr {[info exists ::analysis(side$n)] && $::analysis(side$n) eq "black"}]
  set somme 0
  foreach l $lignes { incr somme [lindex $l 1] }
  if {$somme == 0} { set somme 1 }
  foreach l [lrange [lsort -integer -decreasing -index 1 $lignes] 0 [expr {$maxLignes - 1}]] {
    lassign $l coup visites p wl d q
    set san [san $n $coup]
    # (illegal move here: statistics from another position, not shown)
    if {$san eq {}} { continue }
    # W/D/L from the side-to-move's point of view: W = (1 - D + WL) / 2, L = (1 - D - WL) / 2
    set gain {} ; set nulle {} ; set perte {}
    if {[string is double -strict $wl] && [string is double -strict $d]} {
      set W [expr {(1.0 - $d + $wl) / 2.0}]
      set L [expr {(1.0 - $d - $wl) / 2.0}]
      if {$noirs} { lassign [list $L $W] W L }
      set gain "[expr {round(100 * $W)}]"
      set nulle "[expr {round(100 * $d)}]"
      set perte "[expr {round(100 * $L)}]"
    }
    $t insert {} end -text $san -values [list $visites \
        "[expr {round(100.0 * $visites / $somme)}]" \
        [expr {$p eq {} ? {} : "$p%"}] $gain $nulle $perte]
  }
}

### End Siby
