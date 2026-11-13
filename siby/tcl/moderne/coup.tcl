
###
### Siby: "a move already exists" — clearer dialog
###
### Like ChessBase: a move different from the game's becomes a new
### variation, without asking. With Ctrl held down while playing the move,
### a window offers: new variation, new main line, replace the
### continuation, trial, cancel, with the list of moves already present
### (double-click: enter that line). Options › Appearance "Ask when a move
### already exists": the window every time.
###

namespace eval ::moderne::coup {
  variable reponse cancel
  variable plus 0
  variable lignes {}
  variable avecCtrl 0   ;# Ctrl held down during the current move
}

proc ::moderne::coupExistant {} {
  set w .coupExistant
  catch {destroy $w}
  toplevel $w
  wm withdraw $w
  wm title $w [::moderne::tr "Nouvelle variante" "New variation"]
  catch {wm transient $w .}
  set ::moderne::coup::reponse cancel
  set ::moderne::coup::plus 0
  ttk::frame $w.f -padding 14
  pack $w.f -fill both -expand 1
  # On the left: the moves already present here (like ChessBase); double-click
  # = enter that line
  ttk::frame $w.f.g
  ttk::label $w.f.g.t -text [::moderne::tr "Coups déjà présents" "Existing moves"] -foreground [::moderne::c texteDoux]
  listbox $w.f.g.l -height 6 -width 22 -activestyle none -exportselection 0 -borderwidth 0 -highlightthickness 1
  catch {$w.f.g.l configure -font font_Regular -background [::moderne::c champ] -foreground [::moderne::c texte] \
      -selectbackground [::moderne::c accentFonce] -selectforeground #ffffff -highlightcolor [::moderne::c bordure] \
      -highlightbackground [::moderne::c bordure]}
  pack $w.f.g.t -side top -anchor w -pady {0 4}
  pack $w.f.g.l -side top -fill both -expand 1
  set ::moderne::coup::lignes {}
  catch {
    set m [sc_game info nextMove]
    if {$m ne {}} {
      $w.f.g.l insert end "[sc_pos moveNumber][expr {[sc_pos side] eq "white" ? "." : "..."}][string trim [getNextMoves 3]]"
      lappend ::moderne::coup::lignes main
    }
    set i 0
    foreach v [sc_var list] {
      if {$v ne {}} {
        sc_var moveInto $i
        set suite [string trim [getNextMoves 3]]
        sc_var exit
        $w.f.g.l insert end "[sc_pos moveNumber][expr {[sc_pos side] eq "white" ? "." : "..."}]$suite"
        lappend ::moderne::coup::lignes $i
      }
      incr i
    }
  }
  bind $w.f.g.l <Double-Button-1> {::moderne::coup::suivre}
  pack $w.f.g -side left -fill both -expand 1 -padx {0 14}
  # On the right: the choices
  ttk::frame $w.f.b
  foreach {val fr en} {
    var      "Nouvelle variante"         "New variation"
    mainline "Nouvelle ligne principale" "New main line"
    replace  "Remplacer la suite"        "Overwrite"
    trial    "Essai (sans modifier)"     "Trial (no change)"
    cancel   "Annuler"                   "Cancel"
  } {
    ttk::button $w.f.b.$val -text [::moderne::tr $fr $en] -command [list ::moderne::coup::fin $val]
    pack $w.f.b.$val -side top -fill x -pady 2
  }
  pack configure $w.f.b.cancel -pady {14 2}
  catch {$w.f.b.var configure -style Accent.TButton}
  ttk::checkbutton $w.f.b.plus -variable ::moderne::coup::plus -text [::moderne::tr \
      "Toujours ce choix sans demander" "Always do this without asking"]
  pack $w.f.b.plus -side top -anchor w -pady {10 0}
  ttk::label $w.f.b.aide -foreground [::moderne::c texteDoux] -wraplength 220 -justify left -text [::moderne::tr \
      "Coup simple : nouvelle variante sans question. Ctrl + coup : cette fenêtre." \
      "Plain move: new variation without asking. Ctrl + move: this window."]
  pack $w.f.b.aide -side top -anchor w -pady {6 0}
  pack $w.f.b -side left -fill y
  bind $w <Escape> {::moderne::coup::fin cancel}
  bind $w <Return> {::moderne::coup::fin var}
  wm protocol $w WM_DELETE_WINDOW {::moderne::coup::fin cancel}
  update idletasks
  catch {placeWinOverParent $w .}
  wm deiconify $w
  focus $w.f.b.var
  catch {grab $w}
  vwait ::moderne::coup::reponse
  return $::moderne::coup::reponse
}

### Double-click on a move already present: enter that line instead of
### adding the move played
proc ::moderne::coup::suivre {} {
  set i [.coupExistant.f.g.l curselection]
  if {$i eq {}} { return }
  set ligne [lindex $::moderne::coup::lignes $i]
  fin cancel
  if {$ligne eq "main"} {
    after idle {sc_move forward ; updateBoard -pgn ; catch ::moderne::sons::dejaJoue}
  } else {
    after idle [list apply {{i} {sc_var moveInto $i ; updateBoard -pgn ; catch ::moderne::sons::dejaJoue}} $ligne]
  }
}

### Ctrl held down when the move is played?
proc ::moderne::coup::ctrl {etat} {
  set ::moderne::coup::avecCtrl [expr {($etat & 4) != 0}]
}

### Ctrl + click on a square: with a piece already picked up, it is a move
### "with Ctrl" (variation dialog); otherwise, SCID's arrow
proc ::moderne::coup::ctrlClic {case} {
  if {$::selectedSq != -1} {
    set ::moderne::coup::avecCtrl 1
    pressSquare $case 0
    set ::moderne::coup::avecCtrl 0
  } else {
    drawArrow $case $::commenteditor::State(markColor)
  }
}

proc ::moderne::coup::fin {val} {
  variable plus
  if {$plus && $val in {var replace mainline}} {
    set ::moderne::choixCoupExistant $val
    set ::askToReplaceMoves 0
  }
  catch {grab release .coupExistant}
  catch {destroy .coupExistant}
  set ::moderne::coup::reponse $val
}

### End Siby
