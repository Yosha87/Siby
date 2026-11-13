
###
### Siby: threat analysis (ChessBase's "Threat")
###
### ⚠ button of the analysis window: the engine analyzes the position as if
### it were the other side's turn to move (a "pass"). Its lines thus
### show what the opponent is threatening. The mode follows the board; it
### is impossible when the side to move is in check (one cannot
### pass), so the engine then analyzes the normal position.
### While the threat is shown, the buttons that add the engine's moves to the
### game are disabled (those moves cannot be played in the game).
###
### Hooks: updateAnalysis (tcl/tools/analysis.tcl) and
### ::uci::formatPv (tcl/tools/uci.tcl).
###

namespace eval ::moderne::menace {
  variable actif          ;# actif(n): 1 if analysis window n is in threat mode
  array set actif {}
}

proc ::moderne::menace::T {fr en} { return [::moderne::tr $fr $en] }

### FEN to analyze for engine n in threat mode ({} otherwise, or if the side
### to move is in check)
proc ::moderne::menace::fen {n} {
  variable actif
  if {![info exists actif($n)] || !$actif($n)} { return {} }
  if {[sc_pos isCheck]} { return {} }
  # Engine locked on a position: the threat does not apply
  if {[info exists ::analysis(lockEngine$n)] && $::analysis(lockEngine$n)} { return {} }
  set f [split [sc_pos fen]]
  if {[llength $f] < 4} { return {} }
  lset f 1 [expr {[lindex $f 1] eq "w" ? "b" : "w"}]
  lset f 3 -
  return [join $f]
}

### Adds the button to analysis window n (called by makeAnalysisWin)
proc ::moderne::menace::bouton {n} {
  variable actif
  set w .analysisWin$n
  if {![winfo exists $w.b] || [winfo exists $w.b.menace]} { return }
  # Only for UCI engines (SCID's xboard branch always sends
  # the real position)
  if {![info exists ::analysis(uci$n)] || !$::analysis(uci$n)} { return }
  set actif($n) 0
  if {[lsearch -exact [image names] menace_off] >= 0} {
    # Like Lichess: a gray target, red when the threat is shown
    checkbutton $w.b.menace -image menace_off -selectimage menace_on -indicatoron false \
        -variable ::moderne::menace::actif($n) -command [list ::moderne::menace::basculer $n] \
        -relief flat -offrelief flat -overrelief flat -borderwidth 0 -highlightthickness 0
    catch {$w.b.menace configure -selectcolor [$w.b cget -background] -background [$w.b cget -background]}
  } else {
    checkbutton $w.b.menace -text "⚠" -font font_Bold -indicatoron false -width 2 \
        -variable ::moderne::menace::actif($n) -command [list ::moderne::menace::basculer $n]
    catch {$w.b.menace configure -relief [$w.b.lockengine cget -relief]}
  }
  ::utils::tooltip::Set $w.b.menace [T \
      "Afficher la menace : ce que l'adversaire jouerait si c'était son tour" \
      "Show threat: what the opponent would play if it were their move"]
  pack $w.b.menace -side left -after $w.b.lockengine
  trace add variable ::analysis(lockEngine$n) write [list ::moderne::menace::verrou $n]
  bind $w.b.menace <Destroy> [list trace remove variable ::analysis(lockEngine$n) write [list ::moderne::menace::verrou $n]]
}

### Engine lock during the threat: we go back to the real
### position (otherwise the engine would keep the threat position, decoded
### from the locked position)
proc ::moderne::menace::verrou {n args} {
  variable actif
  if {![info exists actif($n)] || !$actif($n)} { return }
  if {![info exists ::analysis(lockEngine$n)] || !$::analysis(lockEngine$n)} { return }
  set actif($n) 0
  set ::analysis(lockEngine$n) 0
  catch {::moderne::menace::basculer $n}
  set ::analysis(lockEngine$n) 1
}

proc ::moderne::menace::basculer {n} {
  variable actif
  set w .analysisWin$n
  if {![winfo exists $w]} { return }
  set etat [expr {$actif($n) ? "disabled" : "normal"}]
  foreach b {move line alllines} { catch {$w.b.$b configure -state $etat} }
  bandeau $n
  catch {updateAnalysis $n}
}

### Banner above the lines: reminds that the analysis is the threat's
proc ::moderne::menace::bandeau {n} {
  variable actif
  set w .analysisWin$n
  if {!$actif($n)} {
    catch {pack forget $w.menaceTxt}
    return
  }
  if {![winfo exists $w.menaceTxt]} {
    ttk::label $w.menaceTxt -padding {6 2} -font font_Bold \
        -foreground [expr {[::moderne::actif] && $::moderne::theme eq "sombre" ? "#f0b35b" : "#a35a00"}]
  }
  set qui [expr {[sc_pos side] eq "white" ? [T "des Noirs" "Black's"] : [T "des Blancs" "White's"]}]
  if {[info exists ::analysis(lockEngine$n)] && $::analysis(lockEngine$n)} {
    $w.menaceTxt configure -text [T "⚠ Menace inactive : le moteur est verrouillé sur une position" "⚠ Threat inactive: engine is locked"]
  } elseif {[sc_pos isCheck]} {
    $w.menaceTxt configure -text [T "⚠ Menace impossible : le camp au trait est en échec" "⚠ No threat analysis: side to move is in check"]
  } else {
    $w.menaceTxt configure -text "⚠ [T "Menace" "Threat"] : [T "lignes" "lines"] $qui [T "s'ils pouvaient jouer maintenant" "if they could move now"]"
  }
  if {![winfo ismapped $w.menaceTxt]} {
    if {[winfo exists $w.hist]} {
      pack $w.menaceTxt -side top -fill x {*}[::moderne::avantHist $w]
    } else {
      pack $w.menaceTxt -side top -fill x
    }
  }
}

### End Siby
