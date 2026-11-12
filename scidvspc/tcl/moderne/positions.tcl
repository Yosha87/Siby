
###
### Siby: partial-position and material search
###
### You place only the pieces that matter (for example the pawn
### structure), and SCID finds the games where those pieces stand on those
### squares, whatever the rest of the board. Options:
###   - exact pawn structure: no pawns other than the ones placed;
###   - symmetry: also search for the mirrored position (files a↔h);
###   - reversed colors: also search for the position seen from the other side
###     (white pawns ↔ black pawns, ranks 1↔8);
###   - material: minimum / maximum number of each piece and of units
###     (pawn 1, knight and bishop 3, rook 5, queen 9) for each side;
###   - duration: the position must hold for several plies in a row;
###   - empty squares: squares that must remain empty ("✕" tool);
###   - "one of these squares" groups (A, B, C, D): a given piece must
###     occupy at least one of the group's squares (e.g. a white knight on d5
###     or f5, a black pawn on c7 or c5).
### The search is done in C++ (sc_search partial, src/tkscid.cpp and
### Game::PartialMatch in src/game.cpp).
###
### Search menu › "Partial position and material…".
###

namespace eval ::moderne::positions {
  variable plateau [string repeat . 64]   ;# a1 … h8, like sc_pos board
  variable piece main                      ;# tool: main (hand), poubelle (bin), piece (P…k), "vide", or group A…D
  variable glisse -1                       ;# hand: square of the piece being moved
  variable vides {}                        ;# squares that must remain empty (0…63)
  variable groupes                         ;# groupes(A,piece) / groupes(A,cases)
  array set groupes {A,piece P A,cases {} B,piece p B,cases {} C,piece N C,cases {} D,piece n D,cases {}}
  # group colors on the board
  variable couleurs {A #2f7de1 B #e8871e C #b04fd6 D #1fa37a}
  variable exact 0
  variable symetrie 0
  variable inverse 0
  variable duree 1
  variable dansFiltre 0
  variable mat                             ;# mat(wq,min) … mat(bu,max)
  array set mat {}
}

proc ::moderne::positions::T {fr en} { return [::moderne::tr $fr $en] }

proc ::moderne::positions::ouvrir {} {
  variable mat
  set w .positionsWin
  if {[winfo exists $w]} { raiseWin $w ; return }
  toplevel $w
  wm title $w [T "Recherche : position partielle et matériel" "Search: partial position and material"]
  ttk::frame $w.f -padding 10
  pack $w.f -fill both -expand 1

  ### Left column: editor
  set g $w.f.g
  ttk::frame $g
  ttk::label $g.titre -font font_Bold -text [T "Pièces à trouver" "Pieces to find"]
  pack $g.titre -side top -anchor w
  ttk::label $g.aide -wraplength 340 -justify left -text [T \
"Place seulement les pièces qui comptent ; le reste de l'échiquier est libre. Main : glisser les pièces (hors de l'échiquier : les retirer). Pièce choisie : clic pour la poser, clic droit pour changer sa couleur. ✕ : aucune pièce sur la case. Groupes A–D : la pièce du groupe doit être sur au moins une de ses cases." \
"Place only the pieces that matter; the rest of the board is free. Hand: drag the pieces (off the board: removed). Piece chosen: click to put it, right-click to change its colour. ✕: no piece on the square. Groups A–D: the group's piece must stand on at least one of its squares."]
  catch {::moderne::enBulle $g.aide}
  pack $g.aide -side top -anchor w -pady {0 4}
  # board between two palettes, as Lichess's editor (Yosha 2026-11-02):
  # black pieces above, white below, each with the hand (move pieces; off
  # the board: removed) and the bin; a piece chosen follows the pointer,
  # small, and a right click changes its colour
  palette $g.noirs b
  ::board::new $g.b 40
  palette $g.blancs w
  pack $g.noirs $g.b $g.blancs -side top -pady 2
  set c $g.b.bd
  bind $c <ButtonPress-1> {::moderne::positions::appui %x %y}
  bind $c <B1-Motion> {::moderne::positions::bouge %x %y}
  bind $c <ButtonRelease-1> {::moderne::positions::relache %x %y}
  bind $c <Motion> {::moderne::positions::bouge %x %y}
  bind $c <Leave> {::moderne::positions::fantome {} 0 0 0}
  bind $c <ButtonPress-3> {::moderne::positions::clicDroit %x %y ; break}
  # "One of these squares" groups
  ttk::frame $g.grp
  ttk::label $g.grp.l -text [T "Une parmi ces cases :" "One of these squares:"]
  pack $g.grp.l -side left -padx {0 4}
  foreach x {A B C D} {
    ttk::radiobutton $g.grp.r$x -text [T "Groupe $x" "Group $x"] -variable ::moderne::positions::piece \
        -value $x -style Toolbutton -command ::moderne::positions::outilChange
    ttk::menubutton $g.grp.m$x -menu $g.grp.m$x.menu -direction below
    menu $g.grp.m$x.menu -tearoff 0
    foreach {l img} {P wp N wn B wb R wr Q wq K wk p bp n bn b bb r br q bq k bk} {
      $g.grp.m$x.menu add command -image ${img}25 -command [list ::moderne::positions::pieceGroupe $x $l]
    }
    pack $g.grp.r$x $g.grp.m$x -side left -padx {4 0}
  }
  pack $g.grp -side top -pady 2
  ttk::frame $g.bt
  ttk::button $g.bt.prin -text [T "Copier l'échiquier principal" "Copy main board"] \
      -command {::moderne::positions::copier 0}
  ttk::button $g.bt.pions -text [T "Ses pions seulement" "Its pawns only"] \
      -command {::moderne::positions::copier 1}
  ttk::button $g.bt.vider -text [T "Vider" "Clear"] -command ::moderne::positions::vider
  pack $g.bt.prin $g.bt.pions $g.bt.vider -side left -padx 2
  pack $g.bt -side top -pady 2

  ### Middle column: options and material
  set m $w.f.m
  ttk::frame $m
  ttk::label $m.titre -font font_Bold -text [T "Options" "Options"]
  pack $m.titre -side top -anchor w
  foreach {v fr en} {
    exact    "Structure de pions exacte (aucun autre pion)" "Exact pawn structure (no other pawns)"
    symetrie "Chercher aussi la position symétrique (a↔h)"   "Also search the mirrored position (a↔h)"
    inverse  "Chercher aussi avec les couleurs inversées"     "Also search with colours reversed"
    dansFiltre "Chercher seulement dans le filtre actuel"     "Search within the current filter only"
  } {
    ttk::checkbutton $m.$v -variable ::moderne::positions::$v -text [T $fr $en]
    pack $m.$v -side top -anchor w
  }
  ttk::frame $m.d
  ttk::label $m.d.l -text [T "Durée minimale (demi-coups de suite) :" "Minimum duration (consecutive plies):"]
  ttk::spinbox $m.d.s -from 1 -to 40 -width 4 -textvariable ::moderne::positions::duree
  pack $m.d.l $m.d.s -side left
  pack $m.d -side top -anchor w -pady 4

  ttk::label $m.mt -font font_Bold -text [T "Matériel (vide = libre)" "Material (empty = any)"]
  pack $m.mt -side top -anchor w -pady {10 2}
  set t $m.mat
  ttk::frame $t
  ttk::label $t.h0 -text {}
  ttk::label $t.h1 -text [T "Blancs min" "White min"]
  ttk::label $t.h2 -text max
  ttk::label $t.h3 -text [T "Noirs min" "Black min"]
  ttk::label $t.h4 -text max
  grid $t.h0 $t.h1 $t.h2 $t.h3 $t.h4 -padx 3
  foreach {c fr en} {q Dames Queens r Tours Rooks b Fous Bishops n Cavaliers Knights p Pions Pawns u "Unités" "Units"} {
    ttk::label $t.l$c -text [T $fr $en]
    set ligne [list $t.l$c]
    foreach camp {w b} {
      foreach b {min max} {
        if {![info exists mat($camp$c,$b)]} { set mat($camp$c,$b) {} }
        ttk::entry $t.$camp$c$b -width 4 -justify center -textvariable ::moderne::positions::mat($camp$c,$b)
        lappend ligne $t.$camp$c$b
      }
    }
    grid {*}$ligne -padx 3 -pady 1
    grid $t.l$c -sticky w
  }
  pack $t -side top -anchor w
  # (units: pieces and pawns, counted one by one, never in points)
  catch {::utils::tooltip::Set $t.lu [T "Nombre de pièces et de pions (roi non compté)" \
      "Number of pieces and pawns (king not counted)"]}
  ttk::button $m.effmat -text [T "Effacer le matériel" "Clear material"] -command ::moderne::positions::viderMateriel
  pack $m.effmat -side top -anchor w -pady 2

  ttk::frame $m.bas
  ttk::button $m.bas.ok -text [T "Rechercher" "Search"] -command ::moderne::positions::lancer
  catch {$m.bas.ok configure -style Accent.TButton}
  ttk::button $m.bas.stop -text [T "Arrêter" "Stop"] -state disabled -command sc_progressBar
  ttk::button $m.bas.fermer -text [T "Fermer" "Close"] -command [list destroy $w]
  pack $m.bas.ok $m.bas.stop $m.bas.fermer -side left -padx 3
  pack $m.bas -side top -anchor w -pady {14 4}
  # progress: bar and elapsed / estimated time
  canvas $m.prog -height 14 -width 320 -highlightthickness 0 -borderwidth 0 \
      -background [::moderne::c surface]
  $m.prog create rectangle 0 0 220 14 -fill [::moderne::c surface2] -outline {} -tags fond
  $m.prog create rectangle 0 0 0 14 -fill [::moderne::c accent] -outline {} -tags bar
  $m.prog create text 320 7 -anchor e -fill [::moderne::c texteDoux] -font font_Small -tags temps
  ttk::label $m.res -font font_Bold -wraplength 300 -justify left -text {}
  pack $m.res -side top -anchor w

  ### Right column: results preview
  ::moderne::apercu::creer $w.f.r 35
  ::moderne::apercu::clavier $w $w.f.r

  grid $g $m $w.f.r -sticky nw -padx 8
  bind $w <Escape> [list destroy $w]
  catch {::moderne::repeindre $w}
  afficher
  outilDepart
}

### The tool at the start: the hand when there are pieces to move, else a
### piece to put (a hand on an empty board made no sense, Yosha 2026-11-02)
proc ::moderne::positions::outilDepart {} {
  variable plateau
  variable piece
  if {$plateau eq [string repeat . 64]} {
    if {$piece in {main poubelle}} { set piece P }
  } else {
    set piece main
  }
  outilChange
}

### A palette: hand, the six pieces of one colour, bin
proc ::moderne::positions::palette {p couleur} {
  frame $p -background [::moderne::c surface2] -padx 3 -pady 3
  set police [list [font actual font_Regular -family] 16]
  label $p.main -text \u270B -font $police -width 2 -background [::moderne::c surface2] -foreground [::moderne::c texte]
  bind $p.main <Button-1> [list ::moderne::positions::choisir main]
  catch {::utils::tooltip::Set $p.main [T "Main : déplacer les pièces (hors de l'échiquier : les retirer)" \
      "Hand: move the pieces (off the board: remove them)"]}
  pack $p.main -side left -padx 2
  foreach x {k q r b n p} {
    set lettre [expr {$couleur eq "w" ? [string toupper $x] : $x}]
    label $p.$x -image $couleur${x}40 -background [::moderne::c surface2] -borderwidth 0
    bind $p.$x <Button-1> [list ::moderne::positions::choisir $lettre]
    pack $p.$x -side left -padx 1
  }
  label $p.poubelle -text 🗑 -font $police -width 2 -background [::moderne::c surface2] -foreground [::moderne::c texte]
  bind $p.poubelle <Button-1> [list ::moderne::positions::choisir poubelle]
  catch {::utils::tooltip::Set $p.poubelle [T "Poubelle : retirer des pièces" "Bin: remove pieces"]}
  pack $p.poubelle -side left -padx 2
  # (the search's own tool: a square that must stay empty)
  label $p.vide -text \u2715 -font $police -width 2 -background [::moderne::c surface2] -foreground #d03030
  bind $p.vide <Button-1> [list ::moderne::positions::choisir vide]
  catch {::utils::tooltip::Set $p.vide [T "Croix : aucune pièce sur cette case" "Cross: no piece on this square"]}
  pack $p.vide -side left -padx 2
}

### Tool chosen, highlighted in the palettes
proc ::moderne::positions::choisir {o} {
  variable piece
  set piece $o
  outilChange
}

proc ::moderne::positions::outilChange {} {
  variable piece
  set g .positionsWin.f.g
  foreach p [list $g.noirs $g.blancs] couleur {b w} {
    foreach x {main k q r b n p poubelle vide} {
      set actif [expr {$x eq $piece}]
      if {$x ni {main poubelle vide}} {
        set actif [expr {[expr {$couleur eq "w" ? [string toupper $x] : $x}] eq $piece}]
      }
      catch {$p.$x configure -background [expr {$actif ? [::moderne::c accent] : [::moderne::c surface2]}]}
    }
  }
  catch {$g.b.bd configure -cursor [expr {$piece eq "main" ? "hand2" : ($piece eq "poubelle" ? "X_cursor" : "")}]}
}

proc ::moderne::positions::caseSous {x y} {
  return [::board::getSquare .positionsWin.f.g.b $x $y]
}

proc ::moderne::positions::appui {x y} {
  variable piece
  variable plateau
  variable glisse
  set sq [caseSous $x $y]
  if {$sq < 0} { return }
  switch -- $piece {
    main {
      if {[string index $plateau $sq] ne "."} { set glisse $sq ; bouge $x $y }
    }
    poubelle { effacer $sq }
    default { clic $sq }
  }
}

proc ::moderne::positions::relache {x y} {
  variable glisse
  variable plateau
  if {$glisse < 0} { return }
  set de $glisse
  set glisse -1
  set sq [caseSous $x $y]
  set ch [string index $plateau $de]
  liberer $de
  # (dropped off the board: removed; no pawn on the first or last rank)
  if {$sq >= 0 && !($ch in {P p} && ($sq < 8 || $sq > 55))} {
    liberer $sq
    set plateau [string replace $plateau $sq $sq $ch]
  }
  fantome {} 0 0 0
  afficher
}

### Right click: with a piece chosen, its colour changes (as on Lichess);
### else the square is cleared
proc ::moderne::positions::clicDroit {x y} {
  variable piece
  if {[string length $piece] == 1 && [string match {[KQRBNPkqrbnp]} $piece]} {
    choisir [expr {[string is upper $piece] ? [string tolower $piece] : [string toupper $piece]}]
    bouge $x $y
    return
  }
  set sq [caseSous $x $y]
  if {$sq >= 0} { effacer $sq }
}

### Under the pointer: the piece moved (full size), or the piece chosen,
### small beside the pointer
proc ::moderne::positions::bouge {x y} {
  variable piece
  variable glisse
  variable plateau
  if {$glisse >= 0} {
    fantome [string index $plateau $glisse] $x $y 1
  } elseif {[string length $piece] == 1 && [string match {[KQRBNPkqrbnp]} $piece]} {
    fantome $piece $x $y 0
  } else {
    fantome {} 0 0 0
  }
}

proc ::moderne::positions::fantome {ch x y grand} {
  set c .positionsWin.f.g.b.bd
  if {![winfo exists $c]} { return }
  $c delete fantome
  if {$ch eq {}} { return }
  if {$grand} {
    catch {$c create image $x $y -image $::board::letterToPiece($ch)40 -tags fantome}
  } else {
    catch {$c create image [expr {$x + 14}] [expr {$y + 14}] -image $::board::letterToPiece($ch)25 -tags fantome}
  }
  $c raise fantome
}

proc ::moderne::positions::afficher {} {
  variable plateau
  set w .positionsWin
  if {![winfo exists $w]} { return }
  ::board::update $w.f.g.b "$plateau w"
  dessinerMarques
}

### Empty squares (red cross) and groups (small piece, colored frame,
### group letter) on the editor
proc ::moderne::positions::dessinerMarques {} {
  variable vides
  variable groupes
  variable couleurs
  set b .positionsWin.f.g.b
  set c $b.bd
  $c delete marqPartiel
  set t $::board::_size($b)
  set d [expr {$t / 2 - 5}]
  foreach sq $vides {
    lassign [::board::midSquare $b $sq] x y
    $c create line [expr {$x-$d}] [expr {$y-$d}] [expr {$x+$d}] [expr {$y+$d}] -fill #d03030 -width 3 -tags marqPartiel -state disabled
    $c create line [expr {$x-$d}] [expr {$y+$d}] [expr {$x+$d}] [expr {$y-$d}] -fill #d03030 -width 3 -tags marqPartiel -state disabled
  }
  # Several groups on the same square: nested frames
  array set nb {}
  foreach x {A B C D} {
    set img $::board::letterToPiece($groupes($x,piece))25
    foreach sq $groupes($x,cases) {
      lassign [::board::midSquare $b $sq] cx cy
      set k [expr {[info exists nb($sq)] ? $nb($sq) : 0}]
      set nb($sq) [expr {$k + 1}]
      set e [expr {$t / 2 - 2 - 4 * $k}]
      $c create rectangle [expr {$cx-$e}] [expr {$cy-$e}] [expr {$cx+$e}] [expr {$cy+$e}] \
          -outline [dict get $couleurs $x] -width 3 -tags marqPartiel -state disabled
      if {$k == 0} {
        $c create image $cx [expr {$cy + 3}] -image $img -tags marqPartiel -state disabled
        $c create text [expr {$cx-$e+4}] [expr {$cy-$e+2}] -anchor nw -text $x -font font_Small \
            -fill [dict get $couleurs $x] -tags marqPartiel -state disabled
      }
    }
  }
  # Icon of each group's piece in its button
  foreach x {A B C D} {
    catch {.positionsWin.f.g.grp.m$x configure -image $::board::letterToPiece($groupes($x,piece))25}
  }
}

proc ::moderne::positions::pieceGroupe {x l} {
  variable groupes
  variable piece
  set groupes($x,piece) $l
  # No pawn on the first or last rank
  if {$l in {P p}} {
    set ok {}
    foreach sq $groupes($x,cases) { if {$sq >= 8 && $sq <= 55} { lappend ok $sq } }
    set groupes($x,cases) $ok
  }
  set piece $x
  afficher
}

### Removes the square from all conditions (except the group given in "garder")
proc ::moderne::positions::liberer {sq {garder {}}} {
  variable plateau
  variable vides
  variable groupes
  set plateau [string replace $plateau $sq $sq .]
  set vides [lsearch -all -inline -not -exact $vides $sq]
  foreach x {A B C D} {
    if {$x eq $garder} { continue }
    set groupes($x,cases) [lsearch -all -inline -not -exact $groupes($x,cases) $sq]
  }
}

proc ::moderne::positions::clic {sq} {
  variable plateau
  variable piece
  variable vides
  variable groupes
  if {$piece eq "vide"} {
    set deja [expr {$sq in $vides}]
    liberer $sq
    if {!$deja} { lappend vides $sq }
  } elseif {$piece in {A B C D}} {
    # Groups may overlap, but not with a set piece or an empty square
    if {$groupes($piece,piece) in {P p} && ($sq < 8 || $sq > 55)} { return }
    liberer $sq $piece
    if {$sq in $groupes($piece,cases)} {
      set groupes($piece,cases) [lsearch -all -inline -not -exact $groupes($piece,cases) $sq]
    } else {
      lappend groupes($piece,cases) $sq
    }
  } else {
    set actuel [string index $plateau $sq]
    # No pawn on the first or last rank
    if {$actuel ne $piece && $piece in {P p} && ($sq < 8 || $sq > 55)} { return }
    liberer $sq
    if {$actuel ne $piece} { set plateau [string replace $plateau $sq $sq $piece] }
  }
  afficher
}

proc ::moderne::positions::effacer {sq} {
  liberer $sq
  afficher
}

proc ::moderne::positions::vider {} {
  variable plateau
  variable vides
  variable groupes
  set plateau [string repeat . 64]
  set vides {}
  foreach x {A B C D} { set groupes($x,cases) {} }
  afficher
  catch outilDepart
}

proc ::moderne::positions::viderMateriel {} {
  variable mat
  foreach k [array names mat] { set mat($k) {} }
}

### Copies the position from the main board (pawns only if pions = 1)
proc ::moderne::positions::copier {pions} {
  variable plateau
  set p [string range [sc_pos board] 0 63]
  if {$pions} { regsub -all {[^Pp]} $p . p }
  vider
  set plateau $p
  afficher
  # (pieces on the board now: the hand)
  outilDepart
}

### Arguments for sc_search partial
proc ::moderne::positions::arguments {} {
  variable plateau
  variable exact
  variable symetrie
  variable inverse
  variable duree
  variable mat
  set pieces {}
  for {set i 0} {$i < 64} {incr i} {
    set c [string index $plateau $i]
    if {$c ne "."} { lappend pieces [list $c [::board::san $i]] }
  }
  variable vides
  variable groupes
  set cases {}
  foreach sq $vides { lappend cases [::board::san $sq] }
  set grp {}
  foreach x {A B C D} {
    if {![llength $groupes($x,cases)]} { continue }
    set l {}
    foreach sq $groupes($x,cases) { lappend l [::board::san $sq] }
    lappend grp [list $groupes($x,piece) $l]
  }
  set args [list -pieces $pieces -empty $cases -oneof $grp -pawnsexact $exact -mirror $symetrie -flip $inverse]
  if {![string is integer -strict $duree] || $duree < 1} { set duree 1 }
  lappend args -length $duree
  # (the Material tab combined with this one: its counts at the same
  # position, Yosha 2026-11-10; dict wq.. bp, wm bm, diff -> {min max})
  variable materielCombine
  if {![info exists materielCombine]} { set materielCombine {} }
  foreach camp {w b} {
    foreach c {q r b n p u} {
      set mi [string trim $mat($camp$c,min)]
      set ma [string trim $mat($camp$c,max)]
      set autre [expr {[dict exists $materielCombine $camp$c] ? [dict get $materielCombine $camp$c] : {}}]
      if {$mi eq {} && $ma eq {} && $autre eq {}} { continue }
      foreach v [list $mi $ma] {
        if {$v ne {} && ![string is integer -strict $v]} {
          error [T "Matériel : « $v » n'est pas un nombre." "Material: \"$v\" is not a number."]
        }
      }
      if {$mi eq {}} { set mi 0 }
      if {$ma eq {}} { set ma 16 }
      if {$autre ne {}} {
        set mi [expr {max($mi, [lindex $autre 0])}]
        set ma [expr {min($ma, [lindex $autre 1])}]
      }
      if {$c eq "u"} {
        lappend args -${camp}units [list $mi $ma]
      } else {
        lappend args -$camp$c [list $mi $ma]
      }
    }
  }
  foreach {k opt} {wm -wminor bm -bminor diff -diff} {
    if {[dict exists $materielCombine $k]} { lappend args $opt [dict get $materielCombine $k] }
  }
  return $args
}

proc ::moderne::positions::lancer {} {
  variable dansFiltre
  variable plateau
  set w .positionsWin
  if {![sc_base inUse]} { return }
  if {[catch {arguments} args]} {
    tk_messageBox -parent $w -icon error -type ok -title Siby -message $args
    return
  }
  variable vides
  variable groupes
  set rien [expr {$plateau eq [string repeat . 64] && ![llength $vides]}]
  foreach x {A B C D} { if {[llength $groupes($x,cases)]} { set rien 0 } }
  if {$rien && [llength $args] <= 14} {
    tk_messageBox -parent $w -icon info -type ok -title Siby -message [T \
        "Place au moins une pièce ou indique un matériel." "Place at least one piece or set some material."]
    return
  }
  lappend args -filter [expr {$dansFiltre ? "AND" : "RESET"}]
  set m $w.f.m
  variable enCours
  if {[info exists enCours] && $enCours} { return }
  set enCours 1
  # The search reads every game: on a large database it can take a while.
  # The bar (refreshed every 1000 games) keeps the window responsive,
  # "Stop" interrupts it.
  $m.res configure -text [T "Recherche en cours…" "Searching…"]
  $m.prog coords bar 0 0 0 14
  $m.prog itemconfigure temps -text {}
  pack $m.prog -side top -anchor w -pady {2 6} -before $m.res
  $m.bas.ok configure -state disabled
  $m.bas.stop configure -state normal
  sc_progressBar $m.prog bar 219 13 temps
  busyCursor .
  set t0 [clock milliseconds]
  set code [catch {sc_search partial {*}$args} err]
  set ms [expr {[clock milliseconds] - $t0}]
  set enCours 0
  catch {sc_progressBar}
  unbusyCursor .
  if {![winfo exists $w]} { return }
  $m.bas.ok configure -state normal
  $m.bas.stop configure -state disabled
  pack forget $m.prog
  set interrompu [string match "*nterrupt*" $err]
  if {!$interrompu} { set interrompu [regexp -nocase {interrompu|interrupted} $err] }
  if {$code} {
    tk_messageBox -parent $w -icon error -type ok -title Siby -message $err
    return
  }
  set n [sc_filter count]
  set txt "[::utils::thousands $n] [expr {$n == 1 ? [T "partie trouvée" "game found"] : [T "parties trouvées" "games found"]}] ([format %.1f [expr {$ms / 1000.0}]] s)"
  if {$interrompu} { append txt " • [T "recherche arrêtée" "search stopped"]" }
  $w.f.m.res configure -text $txt
  set ::glstart 1
  catch {::windows::stats::Refresh}
  catch {::windows::gamelist::Refresh}
  catch {::tree::refresh}
  ::moderne::apercu::montrer $w.f.r 1
  focus $w
}


################################################################################
### Move search (Search > Moves…), ChessBase style: a sequence of
### consecutive moves, "Fxh7+ Rxh7 Cg5+". French or English pieces, commas
### or spaces, "?" for any move, "Cf3-g5" to give the starting square;
### "+" / "#" are checked only when written.
################################################################################

proc ::moderne::positions::coupsNormalises {texte} {
  variable campsEcrits
  set campsEcrits {}
  set l {}
  set marque {}
  foreach t [split [string map {, " " ; " " … ...} $texte]] {
    set t [string trim $t]
    # ("1." "12..." move numbers left out; "." before a move: White's,
    # "...": Black's, Yosha 2026-11-04)
    if {[regexp {^[0-9]*(\.+)(.*)$} $t -> points t]} {
      set marque [expr {[string length $points] >= 2 ? "b" : "w"}]
    }
    if {$t eq {}} { continue }
    lappend campsEcrits $marque
    set marque {}
    set t [string map {0-0-0 O-O-O 0-0 O-O ≠ =/=} $t]
    # (English piece letters only, whatever the language, Yosha 2026-11-04)
    lappend l $t
  }
  return $l
}

### The side of the first move, from the "." and "..." written with the
### moves (after coupsNormalises): w, b, {} (none written) or an error
### message (sides that cannot be)
proc ::moderne::positions::campDesCoups {mode} {
  variable campsEcrits
  set premier {}
  set i 0
  foreach c $campsEcrits {
    if {$c ne {}} {
      # consecutive: White and Black in turn; otherwise one side plays them all
      set s [expr {$mode == 0 && $i % 2 ? ($c eq "w" ? "b" : "w") : $c}]
      if {$premier eq {}} {
        set premier $s
      } elseif {$s ne $premier} {
        if {$mode == 0} {
          return [list erreur [::moderne::tr "Deux coups du même camp à la suite" "Two moves in a row by the same side"]]
        }
        return [list erreur [::moderne::tr "Coups des deux camps : seulement en « Consécutifs »" "Moves by both sides: Consecutive only"]]
      }
    }
    incr i
  }
  return [list ok $premier]
}

### The first piece letter of the moves written that is not an English one
### ({} when all are): only English letters are read, whatever the
### language (Yosha 2026-11-04)
proc ::moderne::positions::pieceInconnue {texte} {
  set lettres KQRBNP
  foreach t [split [string map {, " " ; " " … ...} $texte]] {
    regsub {^[0-9]*\.+} [string trim $t] {} t
    foreach x [regexp -all -inline {^[A-Z]|[x=/][A-Z]} $t] {
      set l [string index $x end]
      if {$l eq "O"} { continue }
      if {[string first $l $lettres] < 0} { return [list $l $t] }
    }
  }
  return {}
}

### Check test needed by the moves written (0 none, 1 check, 2 mate)
proc ::moderne::positions::testEchec {coups} {
  set n 0
  foreach c $coups {
    if {[string match *# $c]} { return 2 }
    if {[string match *+ $c]} { set n 1 }
  }
  return $n
}

### End Siby
