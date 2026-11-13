###
### tableau.tcl: a table drawn on a canvas (Siby), like Lichess's opening
### explorer: each cell can have its own colour, a results bar, its own
### tooltip. Sorted by clicking a header, columns hidden or shown by a
### right-click on the headers, a row highlighted on hover (with an arrow
### on the board for its move), played by a click, Up / Down / Return from
### the keyboard, Left / Right move on the board.
###
### Columns: list of dicts {id titre largeur ancre type groupe}
###   groupe: columns of the same group get a common title above their
###   headers (titreGroupe), and a line separates the groups
###   type: texte (default), barre (a {white draws black} bar, stretches)
### Rows: list of dicts
###   san    the move (click, arrow); empty: row not playable
###   cases  dict id -> dict {texte couleur gras bulle tri barre}
###          (tri: sort value; barre: {b d n} percentages for a bar column)
###   style  list among: joue (bold, accent), horsRef (orange), suivant
###          (accent mark on the left), estompe (faded)
###

namespace eval ::moderne::tableau {
  variable tab
  array set tab {}
}

proc ::moderne::tableau::T {fr en} { return [::moderne::tr $fr $en] }

### Creates the table cv (a canvas) with its columns
proc ::moderne::tableau::creer {cv colonnes} {
  variable tab
  canvas $cv -highlightthickness 0 -borderwidth 0 -background [::moderne::c surface] -yscrollincrement 1 -takefocus 1
  set tab($cv,cols) $colonnes
  set tab($cv,lignes) {}
  set tab($cv,masquees) {}
  set tab($cv,survol) -1
  set tab($cv,sel) -1
  set tab($cv,tri) {}
  set tab($cv,somme) {}
  bind $cv <Configure> [list ::moderne::tableau::plusTard $cv]
  bind $cv <Motion> [list ::moderne::tableau::survol $cv %x %y]
  bind $cv <Leave> [list ::moderne::tableau::survol $cv -1 -1]
  bind $cv <ButtonRelease-1> [list ::moderne::tableau::clic $cv %x %y]
  bind $cv <ButtonPress-3> [list ::moderne::tableau::clicDroit $cv %x %y %X %Y]
  bind $cv <MouseWheel> [list ::moderne::tableau::roulette $cv %D]
  bind $cv <Button-4> [list ::moderne::tableau::roulette $cv 120]
  bind $cv <Button-5> [list ::moderne::tableau::roulette $cv -120]
  bind $cv <Up> [list ::moderne::tableau::deplacer $cv -1]
  bind $cv <Down> [list ::moderne::tableau::deplacer $cv 1]
  bind $cv <Return> [list ::moderne::tableau::jouerSel $cv]
  bind $cv <Left> {::move::Back ; break}
  bind $cv <Right> {::move::Forward ; break}
  bind $cv <Destroy> [list ::moderne::tableau::oublier $cv %W]
  return $cv
}

### Title shown above the columns of group g
proc ::moderne::tableau::titreGroupe {cv g texte} {
  variable tab
  if {![info exists tab($cv,cols)]} { return }
  if {[info exists tab($cv,gtitres)] && [dict exists $tab($cv,gtitres) $g] && [dict get $tab($cv,gtitres) $g] eq $texte} { return }
  dict set tab($cv,gtitres) $g $texte
  plusTard $cv
}

proc ::moderne::tableau::oublier {cv w} {
  variable tab
  if {$w ne $cv} { return }
  array unset tab $cv,*
}

### New rows (the sort chosen by the user is kept); garder: same position,
### the scroll and the keyboard selection are kept too
proc ::moderne::tableau::remplir {cv lignes {garder 0}} {
  variable tab
  if {![winfo exists $cv]} { return }
  set tab($cv,lignes) $lignes
  set tab($cv,survol) -1
  # (the position these rows are about: a click is ignored once the board moved on)
  set tab($cv,pos) [sc_pos fen]
  if {!$garder} {
    set tab($cv,sel) -1
    $cv yview moveto 0
  }
  dessiner $cv
}

### The Σ row under the moves (all the position's games): its cells, as a
### row's ("coup" gets "Σ"); {} for none. Kept at the bottom of the panel
### when the moves run below it, as on Lichess (Yosha 2026-11-12). Set
### before remplir.
proc ::moderne::tableau::somme {cv cases} {
  variable tab
  if {![info exists tab($cv,cols)]} { return }
  set tab($cv,somme) $cases
}

### The Σ row at the bottom of what shows of the panel, never below its
### own place after the last move
proc ::moderne::tableau::placerSomme {cv} {
  variable tab
  if {![winfo exists $cv] || ![info exists tab($cv,ySomme)]} { return }
  set c [$cv coords fondSomme]
  if {![llength $c]} { return }
  set bas [$cv canvasy [winfo height $cv]]
  set voulu [expr {min($tab($cv,ySomme), $bas - $tab($cv,hl) - 4)}]
  set voulu [expr {max($voulu, $tab($cv,y0))}]
  set dy [expr {$voulu - [lindex $c 1]}]
  if {abs($dy) >= 0.5} { $cv move somme 0 $dy }
  $cv raise somme
}

### The panel scrolled: its scrollbar, then the Σ row
proc ::moderne::tableau::defilement {cv sb args} {
  catch {$sb set {*}$args}
  placerSomme $cv
}

### Changes a column's title
proc ::moderne::tableau::titre {cv id texte} {
  variable tab
  if {![info exists tab($cv,cols)]} { return }
  set l {}
  foreach c $tab($cv,cols) {
    if {[dict get $c id] eq $id} { dict set c titre $texte }
    lappend l $c
  }
  set tab($cv,cols) $l
}

### A cell of a row changes (e.g. the cloud evaluation arrives)
proc ::moderne::tableau::majCase {cv san col cellule} {
  variable tab
  if {![info exists tab($cv,lignes)]} { return }
  set l {}
  foreach r $tab($cv,lignes) {
    if {[dict get $r san] eq $san} { dict set r cases $col $cellule }
    lappend l $r
  }
  set tab($cv,lignes) $l
}

proc ::moderne::tableau::plusTard {cv} {
  after cancel [list ::moderne::tableau::dessiner $cv]
  after 30 [list ::moderne::tableau::dessiner $cv]
}

proc ::moderne::tableau::roulette {cv d} {
  $cv yview scroll [expr {$d > 0 ? -40 : 40}] units
}

### Displayed columns
proc ::moderne::tableau::visibles {cv} {
  variable tab
  set l {}
  foreach c $tab($cv,cols) {
    if {[dict get $c id] ni $tab($cv,masquees)} { lappend l $c }
  }
  return $l
}

### Text of a cell (for the tests and the widths)
proc ::moderne::tableau::texte {r col} {
  if {[dict exists $r cases $col texte]} { return [dict get $r cases $col texte] }
  return {}
}

### Rows in the displayed order: the chosen sort, else as given
proc ::moderne::tableau::ordre {cv} {
  variable tab
  set lignes $tab($cv,lignes)
  if {$tab($cv,tri) eq {}} { return $lignes }
  lassign $tab($cv,tri) col dec
  set avec {} ; set sans {}
  foreach r $lignes {
    set v {}
    if {[dict exists $r cases $col tri]} {
      set v [dict get $r cases $col tri]
    } else {
      set v [texte $r $col]
    }
    if {$v eq {}} { lappend sans $r } else { lappend avec [list $v $r] }
  }
  set numerique 1
  foreach p $avec { if {![string is double -strict [lindex $p 0]]} { set numerique 0 ; break } }
  set opts [expr {$numerique ? "-real" : "-dictionary"}]
  set triees [lsort $opts -index 0 {*}[expr {$dec ? "-decreasing" : {}}] $avec]
  set res {}
  foreach p $triees { lappend res [lindex $p 1] }
  # (rows without a value stay at the bottom, in their order)
  return [concat $res $sans]
}

proc ::moderne::tableau::trier {cv col} {
  variable tab
  if {[lindex $tab($cv,tri) 0] eq $col} {
    if {[lindex $tab($cv,tri) 1]} {
      set tab($cv,tri) [list $col 0]
    } else {
      # third click: back to the original order
      set tab($cv,tri) {}
    }
  } else {
    set tab($cv,tri) [list $col [expr {$col ne "coup"}]]
  }
  dessiner $cv
}

### Column widths: the natural width (title, contents); the bar columns
### share what is left
proc ::moderne::tableau::largeurs {cv cols lignes larg} {
  set res {}
  set fixe 0
  set nBarres 0
  foreach c $cols {
    set id [dict get $c id]
    if {[dict get $c type] eq "barre"} { incr nBarres ; continue }
    # (tight margins: the table must fit in a layout's column)
    set w [expr {[font measure font_Small [dict get $c titre]] + 14}]
    # (a title allowed to run over the column on its left, the bar's: the
    # column as narrow as its figures, "+49", Yosha 2026-11-09)
    if {[dict exists $c titreLibre] && [dict get $c titreLibre]} { set w 36 }
    foreach r $lignes {
      set t [texte $r $id]
      set f [expr {[dict exists $r cases $id gras] && [dict get $r cases $id gras] ? "font_Bold" : "font_Regular"}]
      set w [expr {max($w, [font measure $f $t] + 14)}]
    }
    if {[dict exists $c largeur] && [dict get $c largeur] > $w} { set w [dict get $c largeur] }
    dict set res $id $w
    incr fixe $w
  }
  set reste [expr {$larg - $fixe - 8}]
  set lb [expr {$nBarres ? max(50, $reste / $nBarres) : 0}]
  foreach c $cols {
    # (never narrower than its title, unless the table would not fit: then
    # the bar gives way, its title cut)
    if {[dict get $c type] eq "barre"} {
      set titreL [expr {[font measure font_Small [dict get $c titre]] + 14}]
      dict set res [dict get $c id] [expr {$reste >= $nBarres * $titreL ? max($lb, $titreL) : $lb}]
    }
  }
  return $res
}

proc ::moderne::tableau::dessiner {cv} {
  variable tab
  if {![winfo exists $cv] || ![info exists tab($cv,cols)]} { return }
  $cv delete all
  set lignes [ordre $cv]
  set tab($cv,ordre) $lignes
  set cols [visibles $cv]
  set larg [winfo width $cv]
  if {$larg < 50} { set larg 900 }
  set fh [font metrics font_Regular -linespace]
  set hl [expr {$fh + 10}]
  set tab($cv,hl) $hl
  set lw [largeurs $cv $cols $lignes $larg]
  set texteC [::moderne::c texte]
  set doux [::moderne::c texteDoux]
  set sombre [expr {[::moderne::actif] && $::moderne::theme eq "sombre"}]
  set accent [::moderne::c accent]
  set joueC [expr {$sombre ? "#6fb3f2" : "#1b62b0"}]
  set horsC [expr {$sombre ? "#f0b35b" : "#a35a00"}]
  # x of each column
  set x 6
  set tab($cv,xs) {}
  foreach c $cols {
    set id [dict get $c id]
    set w [dict get $lw $id]
    dict set tab($cv,xs) $id [list $x [expr {$x + $w}]]
    set x [expr {$x + $w}]
  }
  set largTotale [expr {max($larg, $x + 6)}]
  # groups: a common title above their columns, a line between groups
  set y 2
  set groupes {}
  foreach c $cols {
    set g [expr {[dict exists $c groupe] ? [dict get $c groupe] : {}}]
    lassign [dict get $tab($cv,xs) [dict get $c id]] x1 x2
    if {[llength $groupes] && [lindex $groupes end 0] eq $g} {
      lset groupes end 2 $x2
    } else {
      lappend groupes [list $g $x1 $x2]
    }
  }
  set separations {}
  if {[llength [lsearch -all -inline -not -index 0 $groupes {}]]} {
    set gt [expr {[info exists tab($cv,gtitres)] ? $tab($cv,gtitres) : {}}]
    foreach gr $groupes {
      lassign $gr g x1 x2
      if {$g eq {}} { continue }
      set t [expr {[dict exists $gt $g] ? [dict get $gt $g] : $g}]
      # (cut to the width of the group)
      while {[string length $t] > 3 && [font measure font_Bold $t] > $x2 - $x1 - 12} { set t "[string range $t 0 end-2]…" }
      $cv create text [expr {($x1 + $x2) / 2}] [expr {$y + $hl / 2}] -anchor center -text $t \
          -fill [::moderne::c texteFort] -font font_Bold
      $cv create line [expr {$x1 + 6}] [expr {$y + $hl - 2}] [expr {$x2 - 6}] [expr {$y + $hl - 2}] -fill $accent -width 2
    }
    set y [expr {$y + $hl}]
    # (the line between two groups)
    for {set k 1} {$k < [llength $groupes]} {incr k} {
      if {[lindex $groupes $k 0] ne {} || [lindex $groupes [expr {$k - 1}] 0] ne {}} {
        lappend separations [lindex $groupes $k 1]
      }
    }
  }
  # headers
  foreach c $cols {
    set id [dict get $c id]
    lassign [dict get $tab($cv,xs) $id] x1 x2
    set t [dict get $c titre]
    if {[lindex $tab($cv,tri) 0] eq $id} { append t [expr {[lindex $tab($cv,tri) 1] ? " ▼" : " ▲"}] }
    set anc [dict get $c ancre]
    set xt [expr {$anc eq "e" ? $x2 - 8 : ($anc eq "center" ? ($x1 + $x2) / 2 : $x1 + 8)}]
    set ancT [expr {$anc eq "center" ? "center" : $anc}]
    if {![dict exists $c titreLibre] || ![dict get $c titreLibre]} {
      while {[string length $t] > 3 && [font measure font_Small $t] > $x2 - $x1 - 6} { set t "[string range $t 0 end-2]…" }
    }
    $cv create text $xt [expr {$y + $hl / 2}] -anchor $ancT -text $t -fill $doux -font font_Small -tags [list entete e_$id]
    $cv bind e_$id <ButtonRelease-1> "[list ::moderne::tableau::trier $cv $id] ; break"
    $cv bind e_$id <Enter> [list $cv configure -cursor hand2]
    $cv bind e_$id <Leave> [list $cv configure -cursor {}]
  }
  set y [expr {$y + $hl}]
  $cv create line 0 $y $largTotale $y -fill [::moderne::c bordure]
  set tab($cv,y0) $y
  if {![llength $lignes]} {
    $cv create text [expr {$larg / 2}] [expr {$y + 30}] -text [T "Aucun coup dans cette position" "No move in this position"] \
        -fill $doux -font font_Regular
    $cv configure -scrollregion [list 0 0 $largTotale [expr {$y + 60}]]
    return
  }
  set i 0
  foreach r $lignes {
    set y1 [expr {$y + $i * $hl}]
    set y2 [expr {$y1 + $hl}]
    set ym [expr {($y1 + $y2) / 2}]
    set fond [expr {$i % 2 ? [::moderne::c ligneAlt] : [::moderne::c surface]}]
    $cv create rectangle 0 $y1 $largTotale $y2 -fill $fond -outline {} -tags [list fond f$i]
    set style [expr {[dict exists $r style] ? [dict get $r style] : {}}]
    if {"suivant" in $style} {
      $cv create rectangle 0 $y1 3 $y2 -fill $accent -outline {}
    }
    foreach c $cols {
      set id [dict get $c id]
      lassign [dict get $tab($cv,xs) $id] x1 x2
      if {![dict exists $r cases $id]} { continue }
      set cel [dict get $r cases $id]
      if {[dict get $c type] eq "barre"} {
        if {[dict exists $cel barre]} {
          lassign [dict get $cel barre] b d n
          ::moderne::biblio::barreBNN $cv [expr {$x1 + 4}] [expr {$y1 + 4}] [expr {$x2 - 4}] [expr {$y2 - 4}] $b $d $n $sombre
        }
        continue
      }
      # (no expr: it would turn "+10" into 10)
      set t {}
      if {[dict exists $cel texte]} { set t [dict get $cel texte] }
      if {$t eq {}} { continue }
      set coul $texteC
      set police font_Regular
      if {$id eq "coup"} {
        if {"joue" in $style} { set coul $joueC ; set police font_Bold }
        if {"horsRef" in $style} { set coul $horsC }
      }
      if {"estompe" in $style} { set coul $doux }
      if {[dict exists $cel couleur] && [dict get $cel couleur] ne {}} { set coul [dict get $cel couleur] }
      if {[dict exists $cel gras] && [dict get $cel gras]} { set police font_Bold }
      set anc [dict get $c ancre]
      set xt [expr {$anc eq "e" ? $x2 - 8 : ($anc eq "center" ? ($x1 + $x2) / 2 : $x1 + 8)}]
      $cv create text $xt $ym -anchor [expr {$anc eq "center" ? "center" : $anc}] -text $t -fill $coul -font $police
    }
    incr i
  }
  set yFin [expr {$y + $i * $hl}]
  foreach xs $separations {
    $cv create line $xs [expr {$tab($cv,y0) - $hl}] $xs $yFin -fill [::moderne::c bordure] -width 2
  }
  # the Σ row (see somme)
  catch {unset tab($cv,ySomme)}
  if {[info exists tab($cv,somme)] && [dict size $tab($cv,somme)]} {
    set y1 $yFin
    set y2 [expr {$y1 + $hl}]
    set ym [expr {($y1 + $y2) / 2}]
    set avant [$cv find all]
    $cv create rectangle 0 $y1 $largTotale [expr {$y2 + 4}] -fill [::moderne::c surface] -outline {} -tags fondSomme
    $cv create line 0 $y1 $largTotale $y1 -fill [::moderne::c bordure]
    foreach xs $separations { $cv create line $xs $y1 $xs $y2 -fill [::moderne::c bordure] -width 2 }
    foreach c $cols {
      set id [dict get $c id]
      lassign [dict get $tab($cv,xs) $id] x1 x2
      set anc [dict get $c ancre]
      set xt [expr {$anc eq "e" ? $x2 - 8 : ($anc eq "center" ? ($x1 + $x2) / 2 : $x1 + 8)}]
      set ancT [expr {$anc eq "center" ? "center" : $anc}]
      if {$id eq "coup"} {
        $cv create text $xt $ym -anchor $ancT -text "Σ" -fill $doux -font font_Bold
        continue
      }
      if {![dict exists $tab($cv,somme) $id]} { continue }
      set cel [dict get $tab($cv,somme) $id]
      if {[dict get $c type] eq "barre"} {
        if {[dict exists $cel barre]} {
          lassign [dict get $cel barre] b d n
          ::moderne::biblio::barreBNN $cv [expr {$x1 + 4}] [expr {$y1 + 4}] [expr {$x2 - 4}] [expr {$y2 - 4}] $b $d $n $sombre
        }
        continue
      }
      set t [expr {[dict exists $cel texte] ? [dict get $cel texte] : {}}]
      if {$t eq {}} { continue }
      set coul [expr {[dict exists $cel couleur] && [dict get $cel couleur] ne {} ? [dict get $cel couleur] : $texteC}]
      $cv create text $xt $ym -anchor $ancT -text $t -fill $coul -font font_Bold
    }
    foreach id [$cv find all] { if {$id ni $avant} { $cv addtag somme withtag $id } }
    set tab($cv,ySomme) $y1
    set yFin $y2
  }
  $cv configure -scrollregion [list 0 0 $largTotale [expr {$yFin + 4}]]
  set tab($cv,survol) -1
  if {$tab($cv,sel) >= 0 && $tab($cv,sel) < $i} { marquer $cv $tab($cv,sel) [::moderne::c survol] }
  placerSomme $cv
}

proc ::moderne::tableau::ligneSous {cv y} {
  variable tab
  if {![info exists tab($cv,y0)] || $y < 0} { return -1 }
  set y [$cv canvasy $y]
  if {$y < $tab($cv,y0)} { return -1 }
  # (the Σ row laid over the last moves: not a move)
  set c [$cv coords fondSomme]
  if {[llength $c] && $y >= [lindex $c 1]} { return -1 }
  set i [expr {int(($y - $tab($cv,y0)) / $tab($cv,hl))}]
  if {$i >= [llength $tab($cv,ordre)]} { return -1 }
  return $i
}

proc ::moderne::tableau::colonneSous {cv x} {
  variable tab
  set x [$cv canvasx $x]
  dict for {id xs} $tab($cv,xs) {
    lassign $xs x1 x2
    if {$x >= $x1 && $x < $x2} { return $id }
  }
  return {}
}

proc ::moderne::tableau::marquer {cv i coul} {
  $cv itemconfigure f$i -fill $coul
}

proc ::moderne::tableau::fondNormal {i} {
  return [expr {$i % 2 ? [::moderne::c ligneAlt] : [::moderne::c surface]}]
}

proc ::moderne::tableau::survol {cv x y} {
  variable tab
  if {![info exists tab($cv,ordre)]} { return }
  set i [ligneSous $cv $y]
  if {$i != $tab($cv,survol)} {
    set a $tab($cv,survol)
    if {$a >= 0 && $a != $tab($cv,sel)} { marquer $cv $a [fondNormal $a] }
    if {$i >= 0} { marquer $cv $i [::moderne::c survol] }
    set tab($cv,survol) $i
    set san [expr {$i >= 0 ? [dict get [lindex $tab($cv,ordre) $i] san] : {}}]
    $cv configure -cursor [expr {$san ne {} ? "hand2" : {}}]
    catch {::moderne::biblio::flecheSurvol $san}
  }
  $cv delete bulle
  if {$i < 0} { return }
  # tooltip of the cell (or of the row)
  set r [lindex $tab($cv,ordre) $i]
  set col [colonneSous $cv $x]
  set texte {}
  if {$col ne {} && [dict exists $r cases $col bulle]} { set texte [dict get $r cases $col bulle] }
  if {$texte eq {} && [dict exists $r bulle]} { set texte [dict get $r bulle] }
  if {$texte eq {}} { return }
  bulle $cv $x $y $texte
}

proc ::moderne::tableau::bulle {cv x y texte} {
  set cx [$cv canvasx $x]
  set cy [$cv canvasy $y]
  set t [$cv create text 0 0 -anchor nw -text $texte -font font_Small -fill [::moderne::c texteFort] -tags bulle]
  lassign [$cv bbox $t] bx1 by1 bx2 by2
  set lw [expr {$bx2 - $bx1 + 16}]
  set lh [expr {$by2 - $by1 + 10}]
  set px [expr {$cx + 14}]
  if {$px + $lw > [$cv canvasx [winfo width $cv]]} { set px [expr {$cx - $lw - 8}] }
  set py [expr {$cy + 16}]
  if {$py + $lh > [$cv canvasy [winfo height $cv]]} { set py [expr {$cy - $lh - 6}] }
  $cv coords $t [expr {$px + 8}] [expr {$py + 5}]
  set rr [$cv create rectangle $px $py [expr {$px + $lw}] [expr {$py + $lh}] \
      -fill [::moderne::c surface2] -outline [::moderne::c bordure] -tags bulle]
  $cv raise $t $rr
}

### Click on a row: plays its move
proc ::moderne::tableau::clic {cv x y} {
  variable tab
  focus $cv
  set i [ligneSous $cv $y]
  if {$i < 0} { return }
  set san [dict get [lindex $tab($cv,ordre) $i] san]
  if {$san eq {}} { return }
  $cv delete bulle
  ::moderne::biblio::flecheSurvol {}
  jouer $cv $san
}

### Plays a move of the table, if the table still shows the board's position
### (two quick clicks: the second one hit the rows of the previous position)
proc ::moderne::tableau::jouer {cv san} {
  variable tab
  if {[info exists tab($cv,pos)] && $tab($cv,pos) ne [sc_pos fen]} { return }
  if {[catch {addSanMove $san -animate}]} { return }
  updateBoard -pgn
}

### Keyboard: Up / Down select a row, Return plays it
proc ::moderne::tableau::deplacer {cv d} {
  variable tab
  set n [llength $tab($cv,ordre)]
  if {!$n} { return }
  set a $tab($cv,sel)
  if {$a >= 0} { marquer $cv $a [fondNormal $a] }
  set i [expr {$a < 0 ? ($d > 0 ? 0 : $n - 1) : max(0, min($n - 1, $a + $d))}]
  set tab($cv,sel) $i
  marquer $cv $i [::moderne::c survol]
  catch {::moderne::biblio::flecheSurvol [dict get [lindex $tab($cv,ordre) $i] san]}
  # keeps the row in view
  set y1 [expr {$tab($cv,y0) + $i * $tab($cv,hl)}]
  lassign [$cv cget -scrollregion] - - - h
  if {$h > 0} {
    set haut [$cv canvasy 0]
    set bas [$cv canvasy [winfo height $cv]]
    if {$y1 < $haut + $tab($cv,y0) || $y1 + $tab($cv,hl) > $bas} {
      $cv yview moveto [expr {max(0.0, ($y1 - $tab($cv,y0) - 2.0 * $tab($cv,hl)) / $h)}]
    }
  }
  return -code break
}

proc ::moderne::tableau::jouerSel {cv} {
  variable tab
  set i $tab($cv,sel)
  if {$i < 0} { return }
  set san [dict get [lindex $tab($cv,ordre) $i] san]
  if {$san eq {}} { return -code break }
  jouer $cv $san
  return -code break
}

### Right-click on the headers: columns shown or hidden
proc ::moderne::tableau::clicDroit {cv x y X Y} {
  variable tab
  if {[$cv canvasy $y] > $tab($cv,y0)} { return }
  set m $cv.menuColonnes
  catch {destroy $m}
  menu $m -tearoff 0
  $m add command -label [T "Tout afficher" "Show all"] -command "set ::moderne::tableau::tab($cv,masquees) {} ; ::moderne::tableau::dessiner $cv"
  $m add separator
  foreach c $tab($cv,cols) {
    set id [dict get $c id]
    if {$id eq "coup"} { continue }
    set ::moderne::tableau::vis($cv,$id) [expr {$id ni $tab($cv,masquees)}]
    $m add checkbutton -label [dict get $c titre] -variable ::moderne::tableau::vis($cv,$id) \
        -command [list ::moderne::tableau::basculer $cv $id]
  }
  tk_popup $m $X $Y
}

proc ::moderne::tableau::basculer {cv id} {
  variable tab
  if {$::moderne::tableau::vis($cv,$id)} {
    set tab($cv,masquees) [lsearch -all -inline -not -exact $tab($cv,masquees) $id]
  } else {
    lappend tab($cv,masquees) $id
  }
  dessiner $cv
}

### Rows as shown (tests): {san {col text ...}}
proc ::moderne::tableau::contenu {cv} {
  variable tab
  set res {}
  foreach r $tab($cv,ordre) {
    set d {}
    dict for {id cel} [dict get $r cases] {
      if {[dict exists $cel texte]} { dict set d $id [dict get $cel texte] }
      if {[dict exists $cel couleur]} { dict set d $id,couleur [dict get $cel couleur] }
      if {[dict exists $cel barre]} { dict set d $id,barre [dict get $cel barre] }
    }
    lappend res [list [dict get $r san] $d [expr {[dict exists $r style] ? [dict get $r style] : {}}]]
  }
  return $res
}

### End Siby
