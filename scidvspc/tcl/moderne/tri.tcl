
###
### Siby: sorting tables by clicking a column header
###
### ::moderne::tri::activer t   : makes all columns of ttk::treeview t
###                               sortable (first click: descending
###                               order for numbers, ascending
###                               for text; second click: reversed);
### The chosen sort is kept when the table is filled again (a trace
### on the table's "insert" command reapplies it).
###
### Numbers are recognized despite thousands separators, "%",
### "+" or spaces ("1,234", "54 %", "+0.35"); empty rows
### or "–" always go to the end. In a hierarchical tree, each
### level is sorted separately.
###

namespace eval ::moderne::tri {
  variable etat       ;# etat(t) = {column descending}
  array set etat {}
  variable titres     ;# titres(t,col) = original header text
  array set titres {}
}

proc ::moderne::tri::activer {t} {
  variable titres
  foreach c [concat #0 [$t cget -columns]] {
    set titres($t,$c) [$t heading $c -text]
    $t heading $c -command [list ::moderne::tri::cliquer $t $c]
  }
  trace add execution $t leave [list ::moderne::tri::apresCommande $t]
  # Siby: columns fitted to the width, minimum width, right-click
  # on the headers (fit, show / hide)
  catch {::moderne::colonnes::installer $t}
  return $t
}

proc ::moderne::tri::apresCommande {t cmd args} {
  variable etat
  if {[lindex $cmd 1] ne "insert" || ![info exists etat($t)]} { return }
  after cancel [list ::moderne::tri::reappliquer $t]
  after idle [list ::moderne::tri::reappliquer $t]
}

proc ::moderne::tri::cliquer {t c} {
  variable etat
  if {[info exists etat($t)] && [lindex $etat($t) 0] eq $c} {
    set dec [expr {![lindex $etat($t) 1]}]
  } else {
    set dec [estNumerique $t $c]
  }
  set etat($t) [list $c $dec]
  reappliquer $t
}

### Numeric value of a cell, or {} if it is not a number
proc ::moderne::tri::nombre {v} {
  set v [string map {, {} " " {} " " {} " " {} % {} + {}} [string trim $v]]
  if {[string is double -strict $v]} { return $v }
  return {}
}

proc ::moderne::tri::valeur {t id c} {
  if {$c eq "#0"} { return [$t item $id -text] }
  return [$t set $id $c]
}

proc ::moderne::tri::estNumerique {t c} {
  set nb 0
  set tx 0
  foreach id [lrange [$t children {}] 0 30] {
    set v [string trim [valeur $t $id $c]]
    if {$v in {{} – - ?}} { continue }
    if {[nombre $v] ne {}} { incr nb } else { incr tx }
  }
  return [expr {$nb > 0 && $nb >= $tx}]
}

proc ::moderne::tri::reappliquer {t} {
  variable etat
  variable titres
  if {![winfo exists $t] || ![info exists etat($t)]} { return }
  lassign $etat($t) c dec
  set num [estNumerique $t $c]
  trierNiveau $t {} $c $dec $num
  # Arrow in the header of the sorted column
  foreach col [concat #0 [$t cget -columns]] {
    if {![info exists titres($t,$col)]} { continue }
    set titre $titres($t,$col)
    if {$col eq $c} { append titre [expr {$dec ? " ▼" : " ▲"}] }
    $t heading $col -text $titre
  }
}

proc ::moderne::tri::trierNiveau {t parent c dec num} {
  set pleins {}
  set vides {}
  foreach id [$t children $parent] {
    set v [string trim [valeur $t $id $c]]
    if {$num} { set v [nombre $v] }
    if {$v eq {} || $v in {– - ?}} {
      lappend vides $id
    } else {
      lappend pleins [list $id $v]
    }
    if {[llength [$t children $id]]} { trierNiveau $t $id $c $dec $num }
  }
  set opts [expr {$num ? "-real" : "-dictionary"}]
  if {$dec} { lappend opts -decreasing }
  set ordre {}
  foreach p [lsort {*}$opts -index 1 $pleins] { lappend ordre [lindex $p 0] }
  set ordre [concat $ordre $vides]
  # ("Total" rows or summaries tagged "fixe": always at the bottom)
  set debut {}
  set fixes {}
  foreach id $ordre {
    if {"fixe" in [$t item $id -tags]} { lappend fixes $id } else { lappend debut $id }
  }
  set ordre [concat $debut $fixes]
  $t children $parent $ordre
}

### End Siby


################################################################################
### Table columns: always fully visible (they share the available
### width), never shrunk to nothing, right-click menu on the headers
################################################################################

namespace eval ::moderne::colonnes {
  variable naturelle   ;# naturelle(t,col): width planned at creation
  array set naturelle {}
  variable dispo       ;# dispo(t): displayable columns (the planned ones)
  array set dispo {}
}

proc ::moderne::colonnes::T {fr en} { return [::moderne::tr $fr $en] }

proc ::moderne::colonnes::toutes {t} {
  set l [$t cget -columns]
  if {[string first tree [$t cget -show]] >= 0} { set l [concat #0 $l] }
  return $l
}

proc ::moderne::colonnes::affichees {t} {
  set d [$t cget -displaycolumns]
  if {$d eq "#all" || $d eq {}} { set d [$t cget -columns] }
  if {[string first tree [$t cget -show]] >= 0} { set d [concat #0 $d] }
  return $d
}

proc ::moderne::colonnes::installer {t} {
  bind $t <Configure> {+::moderne::colonnes::plusTard %W}
  bind $t <ButtonPress-3> {+::moderne::colonnes::clicDroit %W %x %y %X %Y}
  after idle [list ::moderne::colonnes::preparer $t]
}

### First time: planned widths and displayable columns
proc ::moderne::colonnes::preparer {t} {
  variable naturelle
  variable dispo
  if {![winfo exists $t] || [info exists dispo($t)]} { return }
  set dispo($t) [affichees $t]
  foreach c [toutes $t] {
    set naturelle($t,$c) [$t column $c -width]
    set titre [$t heading $c -text]
    set min [expr {max(36, [font measure TkHeadingFont $titre] + 18)}]
    if {$c eq "#0"} { set min [expr {max($min, 56)}] }
    $t column $c -minwidth [expr {min($min, max(36, $naturelle($t,$c)))}]
  }
  bind $t <Destroy> {+::moderne::colonnes::oublier %W}
  ajuster $t
}

proc ::moderne::colonnes::oublier {t} {
  variable naturelle
  variable dispo
  array unset naturelle $t,*
  unset -nocomplain dispo($t)
}

proc ::moderne::colonnes::plusTard {t} {
  after cancel [list ::moderne::colonnes::ajuster $t]
  after 60 [list ::moderne::colonnes::ajuster $t]
}

### Distributes the available width among the displayed columns, in proportion
### to their planned width (never below their minimum)
proc ::moderne::colonnes::ajuster {t} {
  variable naturelle
  variable dispo
  if {![winfo exists $t] || ![info exists dispo($t)]} { return }
  set dispo_l [winfo width $t]
  if {$dispo_l < 50} { return }
  set cols [affichees $t]
  set total 0
  foreach c $cols {
    if {![info exists naturelle($t,$c)]} { set naturelle($t,$c) [$t column $c -width] }
    incr total $naturelle($t,$c)
  }
  if {$total <= 0} { return }
  set k [expr {double($dispo_l - 4) / $total}]
  foreach c $cols {
    set l [expr {max([$t column $c -minwidth], int($naturelle($t,$c) * $k))}]
    $t column $c -width $l -stretch 1
  }
}

proc ::moderne::colonnes::clicDroit {t x y X Y} {
  variable dispo
  if {[$t identify region $x $y] ne "heading"} { return }
  if {![info exists dispo($t)]} { preparer $t }
  set m $t.menuColonnes
  catch {destroy $m}
  menu $m -tearoff 0
  $m add command -label [T "Ajuster les colonnes" "Fit columns"] -command [list ::moderne::colonnes::ajuster $t]
  $m add command -label [T "Tout afficher" "Show all"] -command [list ::moderne::colonnes::toutAfficher $t]
  $m add separator
  set aff [affichees $t]
  foreach c $dispo($t) {
    if {$c eq "#0"} { continue }
    set ::moderne::colonnes::vis($t,$c) [expr {$c in $aff}]
    set titre [$t heading $c -text]
    if {$titre eq {}} { set titre $c }
    $m add checkbutton -label $titre -variable ::moderne::colonnes::vis($t,$c) \
        -command [list ::moderne::colonnes::basculer $t $c]
  }
  tk_popup $m $X $Y
}

proc ::moderne::colonnes::basculer {t c} {
  variable dispo
  set d {}
  foreach x $dispo($t) {
    if {$x eq "#0"} { continue }
    if {$::moderne::colonnes::vis($t,$x)} { lappend d $x }
  }
  if {![llength $d] && [string first tree [$t cget -show]] < 0} { return }
  $t configure -displaycolumns $d
  ajuster $t
}

proc ::moderne::colonnes::toutAfficher {t} {
  variable dispo
  set d {}
  foreach x $dispo($t) { if {$x ne "#0"} { lappend d $x } }
  $t configure -displaycolumns $d
  ajuster $t
}
