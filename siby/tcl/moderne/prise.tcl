
###
### Siby: Lichess-style piece handling (main board)
###
###   - ghost piece: while a piece is being dragged, a transparent
###     image stays on its start square;
###   - legal-move dots: when a piece is picked up (click or
###     drag), a dot on every square it can go to, a ring on
###     captures.
###
### Options (Options › Appearance): ::moderne::fantome, ::moderne::pointsCoups
### (enabled by default, see tcl/start.tcl).
###

namespace eval ::moderne::prise {
  variable plateau .main.board
  variable caseAffichee -1
}

### Color c1 blended with c2 (alpha = share of c1, between 0 and 1)
proc ::moderne::prise::melange {c1 c2 alpha} {
  lassign [winfo rgb . $c1] r1 g1 b1
  lassign [winfo rgb . $c2] r2 g2 b2
  set res "#"
  foreach a [list $r1 $g1 $b1] b [list $r2 $g2 $b2] {
    append res [format %02x [expr {int(($alpha * $a + (1 - $alpha) * $b) / 257)}]]
  }
  return $res
}

### Transparent image of a piece (cached)
proc ::moderne::prise::imageFantome {img} {
  set f fantome_$img
  if {$f in [image names]} { return $f }
  if {[catch {
    image create photo $f -format {png -alpha 0.35} -data [$img data -format png]
  }]} {
    return {}
  }
  return $f
}

################################################################################
### Ghost piece
################################################################################

### After ::board::setDragSquare: ghost on the drag's start square
proc ::moderne::prise::apresGlisser {cmd args} {
  variable plateau
  set w [lindex $cmd 1]
  if {$w ne $plateau} { return }
  $w.bd delete fantome
  set sq $::board::_drag($w)
  if {$sq < 0 || $sq > 63 || !$::moderne::fantome} { return }
  set lettre [string index $::board::_data($w) $sq]
  if {$lettre in {. " "} || ![info exists ::board::letterToPiece($lettre)]} { return }
  set img $::board::letterToPiece($lettre)$::board::_size($w)
  if {$img ni [image names]} { return }
  set f [imageFantome $img]
  if {$f eq {}} { return }
  lassign [::board::midSquare $w $sq] x y
  $w.bd create image $x $y -image $f -tags fantome
  catch {$w.bd lower fantome p$sq}
}

################################################################################
### Legal-move dots
################################################################################

### Destination squares of the legal moves from square sq (0 = a1 … 63 = h8)
proc ::moderne::prise::destinations {sq} {
  set res {}
  if {[catch {sc_pos movesUci} coups]} { return {} }
  foreach c $coups {
    set de [expr {([scan [string index $c 0] %c] - 97) + 8 * ([string index $c 1] - 1)}]
    if {$de != $sq} { continue }
    set vers [expr {([scan [string index $c 2] %c] - 97) + 8 * ([string index $c 3] - 1)}]
    if {$vers ni $res} { lappend res $vers }
  }
  return $res
}

proc ::moderne::prise::effacerPoints {} {
  variable plateau
  variable caseAffichee
  catch {effacerSurvol}
  catch {$plateau.bd delete pointsCoups}
  set caseAffichee -1
}

### Updates the dots according to the selected square (::selectedSq)
proc ::moderne::prise::majPoints {args} {
  variable plateau
  variable caseAffichee
  if {![winfo exists $plateau]} { return }
  set sq $::selectedSq
  if {!$::moderne::pointsCoups || $sq < 0 || $sq > 63} { effacerPoints ; return }
  # Only for a piece of the side to move
  set camp [string index [sc_pos side] 0]
  if {[string index [::board::piece $plateau $sq] 0] ne $camp} { effacerPoints ; return }
  if {$sq == $caseAffichee && [llength [$plateau.bd find withtag pointsCoups]]} { return }
  effacerPoints
  set w $plateau
  # mouse hover (without dragging): tint of the hovered square
  if {[string first survol [bind $w.bd <Motion>]] < 0} {
    bind $w.bd <Motion> {+::moderne::prise::survol %x %y}
  }
  set taille $::board::_size($w)
  set vert #14551e
  foreach d [destinations $sq] {
    lassign [::board::midSquare $w $d] x y
    set fond [expr {$::sqcol($d) ? $::lite : $::dark}]
    catch {
      set f [$w.bd itemcget sq$d -fill]
      if {$f ne {}} { set fond $f }
    }
    set occupee [expr {[string index [::board::piece $w $d] 0] ni {e {}}}]
    if {$occupee} {
      # Capture: ring along the edge of the square
      set e [expr {max(2, int($taille * 0.08))}]
      set r [expr {$taille / 2.0 - $e / 2.0 - 1}]
      set item [$w.bd create oval [expr {$x - $r}] [expr {$y - $r}] [expr {$x + $r}] [expr {$y + $r}] \
          -outline [melange $vert $fond 0.45] -width $e -tags [list pointsCoups pc$d]]
    } else {
      set r [expr {max(3, $taille * 0.15)}]
      set item [$w.bd create oval [expr {$x - $r}] [expr {$y - $r}] [expr {$x + $r}] [expr {$y + $r}] \
          -fill [melange $vert $fond 0.5] -outline {} -tags [list pointsCoups pc$d]]
    }
    # The dot must not prevent clicking on the square
    $w.bd bind pc$d <ButtonPress-1> "pressSquare $d 0"
    $w.bd bind pc$d <ButtonPress-2> "pressSquare $d 1"
    $w.bd bind pc$d <Control-ButtonPress-1> "::moderne::coup::ctrlClic $d"
  }
  # Below the pieces (capture rings remain visible around them)
  catch {$w.bd raise pointsCoups}
  for {set i 0} {$i < 64} {incr i} {
    if {[string index [::board::piece $w $i] 0] ni {e {}}} { catch {$w.bd raise p$i} }
  }
  catch {$w.bd raise fantome}
  catch {$w.bd lower fantome p$sq}
  catch {$w.bd raise p$sq}
  set caseAffichee $sq
}

proc ::moderne::prise::basculer {} {
  effacerPoints
  catch {.main.board.bd delete fantome}
}

proc ::moderne::prise::installer {} {
  trace add execution ::board::setDragSquare leave ::moderne::prise::apresGlisser
  trace add execution pressSquare leave ::moderne::prise::majPoints
  trace add execution releaseSquare leave ::moderne::prise::majPoints
  # (the position changes by other means: arrow keys, click in the PGN…)
  trace add execution updateBoard leave ::moderne::prise::majPoints
}

::moderne::prise::installer

### End Siby

################################################################################
### Hovered square (as in Lichess): on a square the picked-up piece can go to,
### the dot disappears and the square is slightly tinted
################################################################################

image create photo Teinte_survol -format png -data {iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGMQCZXzBQAB3QDVIIEFOwAAAABJRU5ErkJggg==}
image create photo Teinte_voilePromo -format png -data {iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGMwMDCYBgACSwEnoUU65gAAAABJRU5ErkJggg==}

namespace eval ::moderne::prise {
  variable survolCase -1
  variable dernierXY {}
  variable couleurTenue {}
}

proc ::moderne::prise::effacerSurvol {} {
  variable plateau
  variable survolCase
  catch {
    $plateau.bd delete survolTeinte
    if {$survolCase >= 0} { $plateau.bd itemconfigure pc$survolCase -state normal }
  }
  set survolCase -1
}

proc ::moderne::prise::survol {x y} {
  variable plateau
  variable survolCase
  set w $plateau
  if {![winfo exists $w.bd] || ![llength [$w.bd find withtag pointsCoups]]} { effacerSurvol ; return }
  set sq [::board::getSquare $w $x $y]
  if {$sq == $survolCase} { return }
  effacerSurvol
  if {$sq < 0 || ![llength [$w.bd find withtag pc$sq]]} { return }
  $w.bd itemconfigure pc$sq -state hidden
  ::moderne::echiquier::teinte $w $sq survol survolTeinte
  set survolCase $sq
}

################################################################################
### Held piece: if the board is redrawn while it is being dragged
### (the engine has just moved), it stays in hand
################################################################################

proc ::moderne::prise::apresDrag {cmd args} {
  variable dernierXY
  lassign $cmd - w x y
  if {$w ne ".main.board"} { return }
  set dernierXY [list $x $y]
  survol $x $y
}

proc ::moderne::prise::apresMaj {cmd args} {
  variable dernierXY
  variable couleurTenue
  set w [lindex $cmd 1]
  if {$w ne ".main.board" || ![info exists ::board::_drag($w)]} { return }
  set sq $::board::_drag($w)
  if {$sq < 0 || $sq > 63 || ![llength $dernierXY]} { return }
  set c [string index [::board::piece $w $sq] 0]
  if {$couleurTenue eq {} || $c ne $couleurTenue} {
    # piece captured by the engine (or no longer there): it leaves the hand
    set ::board::_drag($w) -1
    set ::selectedSq -1
    catch {$w.bd delete fantome}
    effacerPoints
    return
  }
  lassign $dernierXY x y
  $w.bd coords p$sq $x $y
  $w.bd raise p$sq
  catch {apresGlisser [list ::board::setDragSquare $w $sq]}
}

proc ::moderne::prise::noterTenue {cmd args} {
  variable couleurTenue
  variable dernierXY
  lassign $cmd - w sq
  if {$w ne ".main.board"} { return }
  if {$sq < 0} { set couleurTenue {} ; set dernierXY {} ; return }
  set couleurTenue [string index [::board::piece $w $sq] 0]
  set dernierXY {}
}

################################################################################
### Promotion (as in Lichess): the board darkens, the four pieces
### appear in circles on the destination file (queen on the promotion
### square, then knight, rook, bishop). Click elsewhere or Esc: canceled.
################################################################################

namespace eval ::moderne::prise {
  variable choixPromo {}
  variable autoDame 0
}

proc ::moderne::prise::promotion {sq} {
  variable choixPromo
  variable autoDame
  if {$autoDame} { return 2 }
  set w .main.board
  set bd $w.bd
  set taille $::board::_size($w)
  set bord $::board::_border($w)
  set col [expr {[sc_pos side] eq "white" ? "w" : "b"}]
  set pas [expr {$col eq "w" ? -8 : 8}]
  # small piece images (in the circles) and large ones (hovered square)
  set petit [lindex $::boardSizes 0]
  foreach s $::boardSizes { if {$s <= $taille * 0.8} { set petit $s } }
  if {"${col}q$petit" ni [image names]} { set petit $taille }
  # veil over the whole board
  set cote [expr {8 * ($taille + $bord)}]
  set voile Teinte_voilePromo_$cote
  if {$voile ni [image names]} {
    image create photo $voile -width $cote -height $cote
    $voile copy Teinte_voilePromo -zoom $cote $cote
  }
  $bd create image 0 0 -anchor nw -image $voile -tags promoUI
  set cases {}
  set k 0
  foreach {p code} {q 2 n 5 r 3 b 4} {
    set s [expr {$sq + $k * $pas}]
    lassign [::board::midSquare $w $s] x y
    set r [expr {$taille / 2.0}]
    set rr [expr {$r * 0.92}]
    $bd create rectangle [expr {$x - $r}] [expr {$y - $r}] [expr {$x + $r}] [expr {$y + $r}] \
        -fill #d0682c -outline {} -state hidden -tags [list promoUI promoR$s]
    $bd create oval [expr {$x - $rr}] [expr {$y - $rr}] [expr {$x + $rr}] [expr {$y + $rr}] \
        -fill #b0b0b0 -outline {} -tags [list promoUI promoC$s]
    $bd create image $x $y -image ${col}$p$petit -tags [list promoUI promoP$s]
    lappend cases $s [list $code ${col}$p$petit ${col}$p$taille]
    incr k
  }
  $bd bind promoUI <Motion> [list ::moderne::prise::promoSurvol %x %y $cases]
  $bd bind promoUI <ButtonPress-1> [list ::moderne::prise::promoClic %x %y $cases]
  set ancienFocus [focus]
  focus $bd
  bind $bd <Escape> {set ::moderne::prise::choixPromo annule}
  set choixPromo {}
  set ::selectedSq -1
  # (the board moving elsewhere meanwhile, the window closed or Siby quit:
  # the choice is cancelled; the wait stayed open after going back a move,
  # every later promotion was refused and Siby could not quit, Yosha
  # 2026-11-04)
  variable promoFen [sc_pos fen]
  bind $bd <Destroy> {+set ::moderne::prise::choixPromo annule}
  vwait ::moderne::prise::choixPromo
  unset -nocomplain promoFen
  if {![winfo exists $bd]} { return annule }
  bind $bd <Escape> {}
  $bd delete promoUI
  catch {focus $ancienFocus}
  return $choixPromo
}

proc ::moderne::prise::promoSurvol {x y cases} {
  set w .main.board
  set sq [::board::getSquare $w $x $y]
  foreach {s d} $cases {
    lassign $d code petit grand
    if {$s == $sq} {
      $w.bd itemconfigure promoR$s -state normal
      $w.bd itemconfigure promoC$s -state hidden
      $w.bd itemconfigure promoP$s -image $grand
    } else {
      $w.bd itemconfigure promoR$s -state hidden
      $w.bd itemconfigure promoC$s -state normal
      $w.bd itemconfigure promoP$s -image $petit
    }
  }
}

proc ::moderne::prise::promoClic {x y cases} {
  set sq [::board::getSquare .main.board $x $y]
  foreach {s d} $cases {
    if {$s == $sq} { set ::moderne::prise::choixPromo [lindex $d 0] ; return }
  }
  set ::moderne::prise::choixPromo annule
}

### A promotion being chosen while the board shows another position (move
### taken back, game changed): cancelled
proc ::moderne::prise::promoPerimee {args} {
  variable promoFen
  if {[info exists promoFen] && [sc_pos fen] ne $promoFen} {
    set ::moderne::prise::choixPromo annule
  }
}

proc ::moderne::prise::installerJeu {} {
  if {[llength [info commands ::getPromoPiece_origine]]} { return }
  rename ::getPromoPiece ::getPromoPiece_origine
  proc ::getPromoPiece {} {
    if {[::moderne::actif] && [info exists ::moderne::prise::casePromo] && [winfo exists .main.board.bd]} {
      set sq $::moderne::prise::casePromo
      unset ::moderne::prise::casePromo
      return [::moderne::prise::promotion $sq]
    }
    catch {unset ::moderne::prise::casePromo}
    return [::getPromoPiece_origine]
  }
  trace add execution ::board::dragPiece leave ::moderne::prise::apresDrag
  trace add execution ::updateBoard leave ::moderne::prise::promoPerimee
  trace add execution ::board::update leave ::moderne::prise::apresMaj
  trace add execution ::board::setDragSquare leave ::moderne::prise::noterTenue
}

::moderne::prise::installerJeu
