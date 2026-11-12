###
### revision.tcl: replay training (Siby), as in ChessBase: you play one side
### of the game on the main board, Siby plays the other side's moves of the
### line (the main line, or the variation the board is in). A move that is
### not the line's is taken back with a short message; "Show the move"
### plays it. The notation is hidden meanwhile. Useful to revise a
### repertoire file or a game.
###

namespace eval ::moderne::revision {
  variable actif 0
  variable couleur white     ;# the side you play
  variable trouves 0         ;# your moves found at the first try
  variable joues 0           ;# your moves to find so far
  variable essai 0           ;# 1 once a wrong move was tried on this move
  variable partie {}         ;# {base number tab} of the game revised
  variable apres {}
}

proc ::moderne::revision::T {fr en} { return [::moderne::tr $fr $en] }

### Starts: you play couleur (white | black) from the board's position
proc ::moderne::revision::lancer {couleur} {
  variable actif
  variable trouves 0
  variable joues 0
  variable essai 0
  variable partie
  if {[sc_game info nextMoveUCI] eq {}} {
    tk_messageBox -parent . -icon info -title Siby -message [T \
        "Pas de coups après cette position : place-toi au début de la ligne à réviser." \
        "No moves after this position: go to the start of the line to revise."]
    return
  }
  catch {setTrialMode 0}
  set actif 1
  set ::moderne::revision::couleur $couleur
  set onglet {}
  catch {set onglet $::moderne::onglets::actif}
  set partie [list [sc_base current] [sc_game number] $onglet]
  bandeau
  if {[sc_pos side] ne $couleur} { reponse } else { etat [T "À toi de jouer." "Your move."] }
}

proc ::moderne::revision::arreter {{texte {}}} {
  variable actif
  variable apres
  catch {after cancel $apres}
  set actif 0
  catch {destroy .pgnWin.revision}
  catch {destroy .pgnWin.revisionCache}
  if {$texte ne {}} { catch {::moderne::nsb::annonce $texte -1 ; after 4000 ::moderne::nsb::finAnnonce} }
  catch {updateBoard -pgn}
}

### Still on the game revised?
proc ::moderne::revision::memePartie {} {
  variable partie
  set onglet {}
  catch {set onglet $::moderne::onglets::actif}
  expr {[list [sc_base current] [sc_game number] $onglet] eq $partie}
}

### A move played on the board (addMove): 1 if handled here
proc ::moderne::revision::intercepter {sq1 sq2} {
  variable actif
  variable couleur
  variable trouves
  variable joues
  variable essai
  if {!$actif} { return 0 }
  if {![memePartie]} { arreter ; return 0 }
  # (the other side's move is on its way)
  if {[sc_pos side] ne $couleur} { return 1 }
  set attendu [sc_game info nextMoveUCI]
  if {$attendu eq {}} { fin ; return 1 }
  set uci "[::board::san $sq1][::board::san $sq2]"
  if {$uci eq [string range $attendu 0 3]} {
    incr joues
    if {!$essai} { incr trouves }
    set essai 0
    sc_move forward
    updateBoard -pgn -animate
    etat [T "✓ Bien joué" "✓ Well played"]
    if {[sc_game info nextMoveUCI] eq {}} { fin ; return 1 }
    reponse
  } else {
    set essai 1
    set ::selectedSq -1
    updateBoard
    etat [T "✗ Pas ce coup, réessaie" "✗ Not this move, try again"] erreur
  }
  return 1
}

### The other side's move, a little after yours
proc ::moderne::revision::reponse {} {
  variable apres
  catch {after cancel $apres}
  set apres [after 500 ::moderne::revision::jouerReponse]
}

proc ::moderne::revision::jouerReponse {} {
  variable actif
  variable couleur
  if {!$actif || ![memePartie]} { return }
  if {[sc_game info nextMoveUCI] eq {}} { fin ; return }
  sc_move forward
  updateBoard -pgn -animate
  if {[sc_game info nextMoveUCI] eq {}} { fin ; return }
  if {[sc_pos side] ne $couleur} { reponse }
}

### "Show the move": the line's move is played (not counted as found)
proc ::moderne::revision::voir {} {
  variable actif
  variable couleur
  variable joues
  variable essai
  if {!$actif || [sc_pos side] ne $couleur || ![memePartie]} { return }
  set m [sc_game info nextMove]
  if {$m eq {}} { fin ; return }
  incr joues
  set essai 0
  sc_move forward
  updateBoard -pgn -animate
  etat "[T "Le coup de la ligne :" "The line's move:"] $m"
  if {[sc_game info nextMoveUCI] eq {}} { fin ; return }
  reponse
}

proc ::moderne::revision::fin {} {
  variable trouves
  variable joues
  arreter [T "Fin de la ligne : $trouves coup[expr {$trouves > 1 ? "s" : ""}] trouvé[expr {$trouves > 1 ? "s" : ""}] du premier coup sur $joues." \
             "End of the line: $trouves move[expr {$trouves == 1 ? "" : "s"}] found at the first try out of $joues."]
}

################################################################################
### The bar under the notation, and the notation hidden
################################################################################

proc ::moderne::revision::bandeau {} {
  variable couleur
  set w .pgnWin
  if {![winfo exists $w.text]} { return }
  catch {destroy $w.revision}
  set b [ttk::frame $w.revision -padding {8 6}]
  ttk::label $b.t -font font_Bold -text [expr {$couleur eq "white" ? [T "Révision : tu joues les Blancs" "Revision: you play White"] \
                                                                  : [T "Révision : tu joues les Noirs" "Revision: you play Black"]}]
  ttk::label $b.e
  ttk::label $b.score -foreground [::moderne::c texteDoux]
  ttk::button $b.voir -text [T "Voir le coup" "Show the move"] -command ::moderne::revision::voir
  ttk::button $b.stop -text [T "Arrêter" "Stop"] -command ::moderne::revision::arreter
  pack $b.t -side left
  pack $b.stop $b.voir -side right -padx {6 0}
  pack $b.score -side right -padx 10
  pack $b.e -side left -padx 12
  pack $b -side bottom -fill x -before $w.text
  # the next moves are not shown meanwhile
  set c [frame $w.revisionCache -background [::moderne::c fond]]
  label $c.l -background [::moderne::c fond] -foreground [::moderne::c texteDoux] \
      -text [T "La notation est masquée pendant la révision." "The notation is hidden during the revision."]
  place $c.l -relx 0.5 -rely 0.3 -anchor center
  place $c -in $w.text -x 0 -y 0 -relwidth 1 -relheight 1
  raise $c
  majScore
}

proc ::moderne::revision::etat {texte {genre ok}} {
  set b .pgnWin.revision
  if {![winfo exists $b]} { return }
  $b.e configure -text $texte -foreground [expr {$genre eq "erreur" ? "#df5353" : [::moderne::c texte]}]
  majScore
}

proc ::moderne::revision::majScore {} {
  variable trouves
  variable joues
  set b .pgnWin.revision
  if {![winfo exists $b]} { return }
  $b.score configure -text [expr {$joues ? "$trouves / $joues" : ""}]
  catch {::utils::tooltip::Set $b.score [T "Coups trouvés du premier coup / coups joués" "Moves found at the first try / moves played"]}
}

### Menu entries (Game menu, notation's right click)
proc ::moderne::revision::entrees {m} {
  $m add command -label [T "Réviser la ligne : je joue les Blancs" "Revise the line: I play White"] \
      -command {::moderne::revision::lancer white}
  $m add command -label [T "Réviser la ligne : je joue les Noirs" "Revise the line: I play Black"] \
      -command {::moderne::revision::lancer black}
}

### End Siby
