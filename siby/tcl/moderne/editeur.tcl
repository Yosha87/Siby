###
### Siby: board editor (Edit › Set up a position), like Lichess's: a
### palette of black pieces above the board and of white pieces below,
### each with a hand (move pieces) and a bin (remove them). A piece chosen
### in the palette follows the pointer over the board and is put down with
### each click (clicking the same piece again takes it away); right click
### switches the piece in hand to the other colour, or clears a square. On the right: side to move, castling rights, the FEN
### (editable), starting position, clear, flip; "Done" starts the game
### from that position, as in SCID's setup board (which it replaces).
###

namespace eval ::moderne::editeur {
  variable w .editeurPos
  variable plateau        ;# 64 characters, a1 = 0, "." = empty
  variable outil main     ;# main | poubelle | a FEN letter (K Q R B N P k q …)
  variable trait w
  variable roques         ;# roques(K Q k q): castling rights wanted
  array set roques {K 1 Q 1 k 1 q 1}
  variable glisse -1      ;# hand: square of the piece being moved
}

proc ::moderne::editeur::T {fr en} { return [::moderne::tr $fr $en] }

proc ::moderne::editeur::ouvrir {} {
  variable w
  variable plateau
  variable trait
  variable roques
  if {[winfo exists $w]} { raise $w ; focus $w ; return }
  set confirm [::game::ConfirmDiscardOnglet]
  if {$confirm == 2} { return }
  if {$confirm == 0} { catch {sc_game save [sc_game number]} }
  catch {setTrialMode 0}
  # starting point: the position on the main board
  depuisFen [sc_pos fen]

  toplevel $w
  wm withdraw $w
  wm title $w [T "Éditeur de position" "Board editor"]
  set f [ttk::frame $w.f -padding 12]
  pack $f -fill both -expand 1
  set g [ttk::frame $f.g]
  set d [ttk::frame $f.d -padding {16 0 0 0}]
  grid $g $d -sticky n

  # board, between the two palettes (black above, white below)
  # (smaller than the main board: the window fits beside it)
  set taille 40
  set principal 0
  catch {set principal $::board::_size(.main.board)}
  foreach t $::boardSizes {
    if {$t <= min(55, 0.45 * $principal)} { set taille $t }
  }
  palette $g.noirs b $taille
  ::board::new $g.bd $taille 0
  catch {set ::board::_coords($g.bd) 1 ; ::board::coords $g.bd}
  if {[::board::isFlipped]} { ::board::flip $g.bd }
  palette $g.blancs w $taille
  ordrePalettes
  set c $g.bd.bd
  bind $c <ButtonPress-1> {::moderne::editeur::appui %x %y}
  bind $c <B1-Motion> {::moderne::editeur::bouge %x %y}
  bind $c <ButtonRelease-1> {::moderne::editeur::relache %x %y}
  bind $c <Motion> {::moderne::editeur::bouge %x %y}
  bind $c <Leave> {::moderne::editeur::fantome {} 0 0}
  bind $c <ButtonPress-3> {::moderne::editeur::clicDroit %x %y ; break}

  # right side
  ttk::label $d.lt -text [T "Trait" "Side to move"] -font font_Bold
  ttk::frame $d.t
  ttk::radiobutton $d.t.w -text [T "Aux Blancs" "White to play"] -variable ::moderne::editeur::trait -value w \
      -command ::moderne::editeur::maj
  ttk::radiobutton $d.t.b -text [T "Aux Noirs" "Black to play"] -variable ::moderne::editeur::trait -value b \
      -command ::moderne::editeur::maj
  pack $d.t.w $d.t.b -side left -padx {0 10}
  ttk::label $d.lr -text [T "Roques" "Castling"] -font font_Bold
  ttk::frame $d.r
  foreach {k fr en ligne colonne} {K "Blancs O-O" "White O-O" 0 0 Q "Blancs O-O-O" "White O-O-O" 0 1
                                   k "Noirs O-O" "Black O-O" 1 0 q "Noirs O-O-O" "Black O-O-O" 1 1} {
    ttk::checkbutton $d.r.c$k -text [T $fr $en] -variable ::moderne::editeur::roques($k) \
        -command ::moderne::editeur::maj
    grid $d.r.c$k -row $ligne -column $colonne -sticky w -padx {0 12} -pady 1
  }
  ttk::label $d.etat -text {} -foreground #e06c5a
  ttk::frame $d.b
  foreach {nom fr en cmd} {
    depart "Position de départ" "Starting position" ::moderne::editeur::depart
    vider  "Vider l'échiquier"  "Clear board"       ::moderne::editeur::vider
    tourner "Retourner"         "Flip board"        ::moderne::editeur::tourner
  } {
    ttk::button $d.b.$nom -text [T $fr $en] -command $cmd
    pack $d.b.$nom -side top -fill x -pady 2
  }
  ttk::label $d.lf -text FEN -font font_Bold
  ttk::frame $d.fen
  ttk::entry $d.fen.e -width 28 -textvariable ::moderne::editeur::fenTexte
  ttk::button $d.fen.copier -text [T "Copier" "Copy"] -command ::moderne::editeur::copierFen
  ttk::button $d.fen.coller -text [T "Coller" "Paste"] -command ::moderne::editeur::collerFen
  catch {::utils::tooltip::Set $d.fen.coller [T "La position de la FEN du presse-papiers" "The position of the FEN in the clipboard"]}
  pack $d.fen.e -side left -fill x -expand 1
  pack $d.fen.copier $d.fen.coller -side left -padx {4 0}
  bind $d.fen.e <Return> {::moderne::editeur::fenSaisie}
  bind $d.fen.e <FocusOut> {::moderne::editeur::fenSaisie}
  ttk::frame $d.fin
  ttk::button $d.fin.ok -text [T "Terminé" "Done"] -command ::moderne::editeur::valider
  catch {$d.fin.ok configure -style Accent.TButton}
  ttk::button $d.fin.annuler -text [T "Annuler" "Cancel"] -command [list destroy $w]
  pack $d.fin.annuler $d.fin.ok -side right -padx {6 0}
  foreach x [list $d.lt $d.t $d.lr $d.r $d.etat $d.b $d.lf $d.fen] {
    pack $x -side top -anchor w -fill x -pady {0 6}
  }
  pack configure $d.lr $d.b $d.lf -pady {10 4}
  pack $d.fin -side bottom -fill x -pady {16 0}

  bind $w <Escape> [list destroy $w]
  choisir main
  maj
  catch {::moderne::repeindre $w}
  centrer
}

### In the middle of Siby's window
proc ::moderne::editeur::centrer {} {
  variable w
  update idletasks
  set lw [winfo reqwidth $w] ; set lh [winfo reqheight $w]
  set x [expr {[winfo rootx .] + ([winfo width .] - $lw) / 2}]
  set y [expr {[winfo rooty .] + ([winfo height .] - $lh) / 2}]
  wm geometry $w +[expr {max(0, $x)}]+[expr {max(0, $y)}]
  wm deiconify $w
  raise $w
  focus $w
}

### A palette: hand, the six pieces of the colour, bin
proc ::moderne::editeur::palette {p couleur taille} {
  frame $p -background [::moderne::c surface2] -padx 4 -pady 4
  set police [list [font actual font_Regular -family] [expr {max(14, $taille / 2)}]]
  label $p.main -text ✋ -font $police -width 2 -background [::moderne::c surface2] -foreground [::moderne::c texte]
  bind $p.main <Button-1> [list ::moderne::editeur::choisir main]
  ::utils::tooltip::Set $p.main [T "Main : déplacer les pièces (hors de l'échiquier : les retirer)" \
      "Hand: move the pieces (off the board: remove them)"]
  pack $p.main -side left -padx 2
  foreach x {k q r b n p} {
    set lettre [expr {$couleur eq "w" ? [string toupper $x] : $x}]
    label $p.$x -image $couleur$x$taille -background [::moderne::c surface2] -borderwidth 0
    bind $p.$x <Button-1> [list ::moderne::editeur::choisir $lettre]
    pack $p.$x -side left -padx 2
  }
  label $p.poubelle -text 🗑 -font $police -width 2 -background [::moderne::c surface2] -foreground [::moderne::c texte]
  bind $p.poubelle <Button-1> [list ::moderne::editeur::choisir poubelle]
  ::utils::tooltip::Set $p.poubelle [T "Poubelle : retirer des pièces" "Bin: remove pieces"]
  pack $p.poubelle -side left -padx 2
}

### Chosen tool, highlighted in the palettes
proc ::moderne::editeur::choisir {o} {
  variable w
  variable outil
  set outil $o
  set g $w.f.g
  foreach p [list $g.noirs $g.blancs] couleur {b w} {
    foreach x {main k q r b n p poubelle} {
      set actif 0
      if {$x eq $o} { set actif 1 }
      if {$x ni {main poubelle}} {
        set lettre [expr {$couleur eq "w" ? [string toupper $x] : $x}]
        set actif [expr {$lettre eq $o}]
      }
      catch {$p.$x configure -background [expr {$actif ? [::moderne::c accent] : [::moderne::c surface2]}]}
    }
  }
  catch {$w.f.g.bd.bd configure -cursor [expr {$o eq "main" ? "hand2" : ($o eq "poubelle" ? "X_cursor" : "none")}]}
}

################################################################################
### Position
################################################################################

### Board and side from a FEN (rights read too); 0 if unreadable
proc ::moderne::editeur::depuisFen {fen} {
  variable plateau
  variable trait
  variable roques
  set champs [split [string trim $fen]]
  set lignes [split [lindex $champs 0] /]
  if {[llength $lignes] != 8} { return 0 }
  set p [string repeat . 64]
  for {set r 0} {$r < 8} {incr r} {
    set rang [expr {7 - $r}]
    set col 0
    foreach ch [split [lindex $lignes $r] {}] {
      if {[string is digit $ch]} { incr col $ch ; continue }
      if {[string first $ch KQRBNPkqrbnp] < 0 || $col > 7} { return 0 }
      set p [string replace $p [expr {$rang * 8 + $col}] [expr {$rang * 8 + $col}] $ch]
      incr col
    }
  }
  set plateau $p
  set trait [expr {[lindex $champs 1] eq "b" ? "b" : "w"}]
  set r [lindex $champs 2]
  foreach k {K Q k q} { set roques($k) [expr {[string first $k $r] >= 0}] }
  return 1
}

### FEN of the edited position. Castling rights only where king and rook
### are on their squares.
proc ::moderne::editeur::fen {} {
  variable plateau
  variable trait
  variable roques
  set rangs {}
  for {set rang 7} {$rang >= 0} {incr rang -1} {
    set s {}
    set vides 0
    for {set col 0} {$col < 8} {incr col} {
      set ch [string index $plateau [expr {$rang * 8 + $col}]]
      if {$ch eq "."} { incr vides ; continue }
      if {$vides} { append s $vides ; set vides 0 }
      append s $ch
    }
    if {$vides} { append s $vides }
    lappend rangs $s
  }
  set r {}
  foreach {k roi tour} {K 4 7 Q 4 0 k 60 63 q 60 56} {
    set attendu [expr {[string is upper $k] ? "K" : "k"}]
    set tourAttendue [expr {[string is upper $k] ? "R" : "r"}]
    if {$roques($k) && [string index $plateau $roi] eq $attendu && [string index $plateau $tour] eq $tourAttendue} {
      append r $k
    }
  }
  if {$r eq {}} { set r - }
  return "[join $rangs /] $trait $r - 0 1"
}

### Redraws the board, the FEN, the castling boxes and the legality line
proc ::moderne::editeur::maj {} {
  variable w
  variable plateau
  variable trait
  variable fenTexte
  if {![winfo exists $w]} { return }
  ::board::update $w.f.g.bd "$plateau $trait"
  set fenTexte [fen]
  # castling boxes: only usable where king and rook stand on their squares
  foreach {k roi tour} {K 4 7 Q 4 0 k 60 63 q 60 56} {
    set ok [expr {[string index $plateau $roi] eq [expr {[string is upper $k] ? "K" : "k"}]
                  && [string index $plateau $tour] eq [expr {[string is upper $k] ? "R" : "r"}]}]
    catch {$w.f.d.r.c$k state [expr {$ok ? "!disabled" : "disabled"}]}
  }
  $w.f.d.etat configure -text [expr {[legale] ? {} : [T "Position illégale" "Illegal position"]}]
}

### Is the position legal (SCID's own check)?
proc ::moderne::editeur::legale {} {
  sc_game push
  set ok [expr {![catch {sc_game startBoard [fen]}]}]
  sc_game pop
  return $ok
}

proc ::moderne::editeur::poser {sq ch} {
  variable plateau
  set plateau [string replace $plateau $sq $sq $ch]
}

################################################################################
### Mouse
################################################################################

proc ::moderne::editeur::caseSous {x y} {
  variable w
  return [::board::getSquare $w.f.g.bd $x $y]
}

proc ::moderne::editeur::appui {x y} {
  variable outil
  variable plateau
  variable glisse
  set sq [caseSous $x $y]
  if {$sq < 0} { return }
  switch -- $outil {
    main {
      if {[string index $plateau $sq] ne "."} { set glisse $sq ; bouge $x $y }
    }
    poubelle { poser $sq . ; maj }
    default {
      # (the same piece again: taken away, as on Lichess)
      poser $sq [expr {[string index $plateau $sq] eq $outil ? "." : $outil}]
      maj
    }
  }
}

proc ::moderne::editeur::relache {x y} {
  variable glisse
  if {$glisse < 0} { return }
  set de $glisse
  set glisse -1
  set sq [caseSous $x $y]
  variable plateau
  set ch [string index $plateau $de]
  poser $de .
  # (dropped off the board: the piece is removed)
  if {$sq >= 0} { poser $sq $ch }
  fantome {} 0 0
  maj
}

### Right click: with a piece in hand, the same piece of the other colour
### (as in the position search, Yosha 2026-11-08); otherwise the square
### cleared
proc ::moderne::editeur::clicDroit {x y} {
  variable outil
  if {[string length $outil] == 1 && [string match {[KQRBNPkqrbnp]} $outil]} {
    choisir [expr {[string is upper $outil] ? [string tolower $outil] : [string toupper $outil]}]
    bouge $x $y
    return
  }
  effacer $x $y
}

proc ::moderne::editeur::effacer {x y} {
  set sq [caseSous $x $y]
  if {$sq >= 0} { poser $sq . ; maj }
}

### The piece under the pointer: the chosen piece, or the one being moved
proc ::moderne::editeur::bouge {x y} {
  variable outil
  variable glisse
  variable plateau
  set ch {}
  if {$glisse >= 0} {
    set ch [string index $plateau $glisse]
  } elseif {$outil ni {main poubelle}} {
    set ch $outil
  }
  fantome $ch $x $y
}

proc ::moderne::editeur::fantome {ch x y} {
  variable w
  set c $w.f.g.bd.bd
  if {![winfo exists $c]} { return }
  $c delete fantome
  if {$ch eq {}} { return }
  set taille $::board::_size($w.f.g.bd)
  catch {$c create image $x $y -image $::board::letterToPiece($ch)$taille -tags fantome}
  $c raise fantome
}

################################################################################
### Buttons
################################################################################

proc ::moderne::editeur::depart {} {
  depuisFen $::defaultFen
  maj
}

proc ::moderne::editeur::vider {} {
  variable plateau
  set plateau [string repeat . 64]
  maj
}

proc ::moderne::editeur::tourner {} {
  variable w
  ::board::flip $w.f.g.bd
  ordrePalettes
  maj
}

### Each side's pieces on its own side of the board (Black above unless
### the board is flipped; Yosha 2026-11-03)
proc ::moderne::editeur::ordrePalettes {} {
  variable w
  set g $w.f.g
  if {![winfo exists $g.bd]} { return }
  pack forget $g.noirs $g.bd $g.blancs
  if {[::board::isFlipped $g.bd]} {
    pack $g.blancs $g.bd $g.noirs -side top -pady 4
  } else {
    pack $g.noirs $g.bd $g.blancs -side top -pady 4
  }
}

proc ::moderne::editeur::copierFen {} {
  clipboard clear
  clipboard append [fen]
}

### The FEN of the clipboard (a FEN alone, or one line of a text)
proc ::moderne::editeur::collerFen {} {
  variable w
  set texte {}
  catch {set texte [clipboard get]}
  foreach ligne [split [string trim $texte] \n] {
    set ligne [string trim $ligne]
    if {$ligne ne {} && [depuisFen $ligne]} {
      # (the message of a failed paste goes away)
      maj
      return
    }
  }
  $w.f.d.etat configure -text [T "Pas de FEN dans le presse-papiers" "No FEN in the clipboard"]
}

### FEN typed or pasted in the field
proc ::moderne::editeur::fenSaisie {} {
  variable fenTexte
  if {$fenTexte eq [fen]} { return }
  if {![depuisFen $fenTexte]} {
    variable w
    $w.f.d.etat configure -text [T "FEN illisible" "Unreadable FEN"]
    return
  }
  maj
}

### Done: the game starts from this position
proc ::moderne::editeur::valider {} {
  variable w
  if {![legale]} {
    tk_messageBox -parent $w -icon warning -type ok -title Siby -message [T \
        "Position illégale : vérifie les rois, les pions sur la 1re ou la 8e rangée, et le roi qui n'a pas le trait (il ne doit pas être en échec)." \
        "Illegal position: check the kings, pawns on the 1st or 8th rank, and the king not to move (it must not be in check)."]
    return
  }
  set f [fen]
  sc_game new
  sc_game startBoard $f
  destroy $w
  updateBoard -pgn
  catch {::windows::gamelist::Refresh}
}
