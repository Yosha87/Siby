
###
### Siby: main board themes and coordinates inside the squares
###
###   ::moderne::echiquier  marbre (default, like Lichess's "blue marble"
###                         theme) | brun | bleu | vert | violet | ic |
###                         gris | rose (Lichess's plain colors)
###   ::moderne::coordsDedans 1: letters on the bottom rank, numbers on the
###                         right file, inside the squares, in the color
###                         of the other square (as in Lichess)
### Textures: tcl/moderne/marbre.tcl (outils/echiquier/generer_marbre.py).
###

namespace eval ::moderne::echiquier {
  # plain themes (Lichess): light, dark
  variable couleurs {
    brun   {#f0d9b5 #b58863}
    bleu   {#dee3e6 #8ca2ad}
    vert   {#ffffdd #86a666}
    violet {#9f90b0 #7d4a8d}
    ic     {#ececec #c1c18e}
    gris   {#c8c8c8 #8a8a8a}
    rose   {#f1f1c9 #f07272}
  }
}

proc ::moderne::echiquier::T {fr en} { return [::moderne::tr $fr $en] }

proc ::moderne::echiquier::appliquer {} {
  global boardfile_dark boardfile_lite
  if {$::moderne::echiquier eq "marbre" && "MarbreBleu0-l" in [image names]} {
    set boardfile_lite MarbreBleu0-l
    set boardfile_dark MarbreBleu0-d
    catch {SetBoardTextures}
    # Four variants per color, cropped to the square size
    foreach size $::boardSizes {
      foreach c {l d} {
        for {set k 0} {$k < 4} {incr k} {
          set img bg$c${size}_$k
          catch {image delete $img}
          image create photo $img -width $size -height $size
          $img copy MarbreBleu$k-$c -to 0 0 $size $size
        }
      }
    }
    set ::board::variantesTextures 1
    set ::lite #c4ced8
    set ::dark #5082b1
  } else {
    variable couleurs
    set boardfile_lite emptySquare
    set boardfile_dark emptySquare
    catch {SetBoardTextures}
    set ::board::variantesTextures 0
    set c {#f0d9b5 #b58863}
    if {[dict exists $couleurs $::moderne::echiquier]} { set c [dict get $couleurs $::moderne::echiquier] }
    lassign $c ::lite ::dark
  }
  if {[winfo exists .main.board]} {
    for {set i 0} {$i < 64} {incr i} { catch {::board::colorSquare .main.board $i} }
    catch {updateBoard}
    coords
  }
}

### Coordinates inside the squares of the main board
proc ::moderne::echiquier::coords {args} {
  set w .main.board
  if {![winfo exists $w.bd]} { return }
  set bd $w.bd
  $bd delete coordDedans
  if {!$::moderne::coordsDedans} { return }
  set taille $::board::_size($w)
  set f font_CoordDedans
  if {$f ni [font names]} { font create $f -family [font actual font_Regular -family] -weight bold }
  font configure $f -size [expr {max(7, int($taille / 9))}]
  set retourne [::board::isFlipped $w]
  set marge [expr {max(2, $taille / 22)}]
  for {set k 0} {$k < 8} {incr k} {
    # letters: bottom rank, bottom-left corner
    set sq [expr {$retourne ? 63 - $k : $k}]
    set lettre [string index abcdefgh [expr {$sq % 8}]]
    lassign [$bd coords sq$sq] x1 y1 x2 y2
    set coul [expr {$::sqcol($sq) ? $::dark : $::lite}]
    $bd create text [expr {$x1 + $marge}] [expr {$y2 - $marge / 2}] -anchor sw -text $lettre \
        -font $f -fill $coul -tags coordDedans
    # numbers: right file, top-right corner
    set sq [expr {$retourne ? 8 * $k : 8 * $k + 7}]
    set chiffre [expr {$sq / 8 + 1}]
    lassign [$bd coords sq$sq] x1 y1 x2 y2
    set coul [expr {$::sqcol($sq) ? $::dark : $::lite}]
    $bd create text [expr {$x2 - $marge}] [expr {$y1 + $marge / 2}] -anchor ne -text $chiffre \
        -font $f -fill $coul -tags coordDedans
  }
  # above the squares, below the pieces
  catch {$bd raise coordDedans}
  for {set i 0} {$i < 64} {incr i} { catch {$bd raise p$i} }
  catch {$bd raise arrows}
}

proc ::moderne::echiquier::apresUpdate {cmd args} {
  if {[lindex $cmd 1] eq ".main.board"} {
    coords
    catch {::moderne::premove::dessiner}
  }
}

proc ::moderne::echiquier::menu {m} {
  catch {destroy $m.echiquier}
  ::menu $m.echiquier -tearoff 0
  $m add cascade -label [T "Couleurs de l'échiquier (Lichess)" "Board colors (Lichess)"] -menu $m.echiquier
  foreach {v fr en} {
    marbre "Marbre bleu" "Blue marble"
    brun   "Brun" "Brown"
    bleu   "Bleu" "Blue"
    vert   "Vert" "Green"
    violet "Violet" "Purple"
    ic     "IC" "IC"
    gris   "Gris" "Grey"
    rose   "Rose" "Pink"
  } {
    $m.echiquier add radiobutton -label [T $fr $en] -variable ::moderne::echiquier -value $v \
        -command ::moderne::echiquier::appliquer
  }
  catch {destroy $m.pieces}
  ::menu $m.pieces -tearoff 0
  $m add cascade -label [T "Pièces" "Pieces"] -menu $m.pieces
  catch {::moderne::pieces::menu $m.pieces}
  $m add checkbutton -label [T "Coordonnées dans les cases" "Coordinates inside the squares"] \
      -variable ::moderne::coordsDedans -command ::moderne::echiquier::coords
}

proc ::moderne::echiquier::installer {} {
  if {![::moderne::actif]} { return }
  installerTeintes
  foreach c {::board::update ::board::resize ::board::flip} {
    catch {trace add execution $c leave ::moderne::echiquier::apresUpdate}
  }
  # SCID coordinates (outside the board): replaced by the in-square ones
  if {$::moderne::coordsDedans} { set ::boardCoords 0 }
  after idle ::moderne::echiquier::appliquer
}


### Transparent tint (Lichess) on a square: nom = selection | dernier
proc ::moderne::echiquier::teinte {w sq nom tag} {
  if {"Teinte_$nom" ni [image names]} { return 0 }
  set taille $::board::_size($w)
  set img Teinte_${nom}_$taille
  if {$img ni [image names]} {
    image create photo $img -width $taille -height $taille
    $img copy Teinte_$nom -zoom $taille $taille
  }
  lassign [::board::midSquare $w $sq] x y
  set id [$w.bd create image $x $y -image $img -tags $tag]
  catch {$w.bd lower $id p$sq}
  return 1
}

### Selected square: transparent green tint instead of the SCID outline
proc ::moderne::echiquier::installerTeintes {} {
  if {[llength [info commands ::board::highlightSquare_origine]]} { return }
  rename ::board::highlightSquare ::board::highlightSquare_origine
  proc ::board::highlightSquare {args} {
    set w [lindex $args 0]
    if {$w eq ".main.board" && [::moderne::actif] && !$::colorActiveSquare && !$::suggestMoves} {
      if {[llength $args] > 2} {
        set sq [lindex $args 1]
        if {$sq >= 0 && $sq <= 63 && [::moderne::echiquier::teinte $w $sq selection {moveRectangle mark}]} { return }
      } else {
        $w.bd delete moveRectangle
        return
      }
    }
    ::board::highlightSquare_origine {*}$args
  }
  # Last move: transparent tint (the texture remains visible)
  rename ::board::mark::FillSquare ::board::mark::FillSquare_origine
  proc ::board::mark::FillSquare {pathName square color} {
    set w [winfo parent $pathName]
    if {$w eq ".main.board" && [::moderne::actif] && $square >= 0 && $square <= 63} {
      if {[::moderne::echiquier::teinte $w $square dernier highlightLastMove]} { return }
    }
    ::board::mark::FillSquare_origine $pathName $square $color
  }
}

::moderne::echiquier::installer

### End Siby
