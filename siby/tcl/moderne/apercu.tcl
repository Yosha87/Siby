
###
### Siby: preview of search results on a mini-board
###
### Reusable panel (partial-position search, ready-made
### searches): the game found is shown at the matching position, without
### touching the current game on the main board.
###   ← / →   previous / next move
###   ↑ / ↓   previous / next game found (filter order)
###   Home / End   start / end of the game
###   Enter   open the game at this position on the main board
###
### Positions come from "sc_game boards" (C++), which reads the game
### in the database without loading it.
###

namespace eval ::moderne::apercu {
  # For each panel p: etat($p,idx) rank in the filter, etat($p,g)
  # game number, etat($p,pos) list {move board}, etat($p,ply)
  # ply shown, etat($p,trouve) ply of the position found
  variable etat
  array set etat {}
}

proc ::moderne::apercu::T {fr en} { return [::moderne::tr $fr $en] }

### Creates panel p (a ttk::frame); taille = square size
proc ::moderne::apercu::creer {p {taille 35}} {
  variable etat
  ttk::frame $p
  ttk::label $p.titre -font font_Bold -text [T "Aperçu" "Preview"]
  pack $p.titre -side top -anchor w
  ::board::new $p.b $taille
  pack $p.b -side top -pady 4
  ttk::label $p.partie -wraplength [expr {$taille * 8 + 20}] -justify left -text {}
  ttk::label $p.coup -font font_Bold -text {}
  pack $p.partie $p.coup -side top -anchor w
  ttk::frame $p.nav
  foreach {n txt cmd} {
    debut "|<"  {deplacer $p debut}
    prec  "<"   {deplacer $p -1}
    suiv  ">"   {deplacer $p 1}
    fin   ">|"  {deplacer $p fin}
    trouve "⌖" {deplacer $p trouve}
    haut  "▲" {partie $p -1}
    bas   "▼" {partie $p 1}
  } {
    ttk::button $p.nav.$n -text $txt -width 3 -command [list ::moderne::apercu::[lindex $cmd 0] $p [lindex $cmd 2]]
    pack $p.nav.$n -side left -padx 1
  }
  ttk::button $p.nav.ouvrir -text [T "Ouvrir" "Open"] -command [list ::moderne::apercu::ouvrir $p]
  pack $p.nav.ouvrir -side left -padx {6 0}
  pack $p.nav -side top -anchor w -pady 4
  ttk::label $p.aide -foreground gray50 -wraplength [expr {$taille * 8 + 20}] -justify left -text [T \
"← → coups • ↑ ↓ parties trouvées • Entrée : ouvrir • ⌖ : revenir à la position trouvée" \
"← → moves • ↑ ↓ found games • Enter: open • ⌖: back to the found position"]
  pack $p.aide -side top -anchor w
  set etat($p,idx) 0
  set etat($p,g) 0
  set etat($p,pos) {}
  set etat($p,ply) 0
  set etat($p,trouve) 0
  ::board::update $p.b [string repeat . 64]
  # Click on the mini-board: give it keyboard focus
  bind $p.b.bd <Button-1> [list focus [winfo toplevel $p]]
  return $p
}

### Keyboard shortcuts on window w for panel p (except when
### the focus is in an entry field)
proc ::moderne::apercu::clavier {w p} {
  foreach {touche cmd} {
    <Left> {deplacer -1} <Right> {deplacer 1} <Up> {partie -1} <Down> {partie 1}
    <Home> {deplacer debut} <End> {deplacer fin} <Return> {ouvrir} <KP_Enter> {ouvrir}
  } {
    bind $w $touche [list ::moderne::apercu::touche $p {*}$cmd]
  }
}

proc ::moderne::apercu::touche {p cmd args} {
  set f [focus]
  if {$f ne {} && [winfo class $f] in {TEntry Entry TSpinbox Spinbox Text TCombobox Treeview}} { return }
  if {![winfo exists $p]} { return }
  if {$cmd eq "ouvrir"} { ouvrir $p } else { $cmd $p {*}$args }
  return -code break
}

### Shows the idx-th game of the filter (1 = first); 0 if the filter is empty
proc ::moderne::apercu::montrer {p idx} {
  variable etat
  if {![winfo exists $p]} { return }
  set n [sc_filter count]
  if {$n == 0 || ![sc_base inUse]} {
    set etat($p,idx) 0 ; set etat($p,g) 0 ; set etat($p,pos) {}
    $p.titre configure -text [T "Aperçu : aucune partie" "Preview: no game"]
    $p.partie configure -text {}
    $p.coup configure -text {}
    ::board::update $p.b [string repeat . 64]
    return
  }
  if {$idx < 1} { set idx 1 }
  if {$idx > $n} { set idx $n }
  set ligne [lindex [split [sc_game list $idx 1 "g*\tw*\tW*\tb*\tB*\tr*\td*\te*"] \n] 0]
  lassign [split $ligne \t] g blanc eloB noir eloN res date tournoi
  set g [string trim $g]
  if {![string is integer -strict $g]} { return }
  set etat($p,idx) $idx
  set etat($p,g) $g
  set etat($p,pos) [sc_game boards $g]
  set v [sc_filter value $g]
  set ply [expr {$v > 0 ? $v - 1 : 0}]
  if {$ply >= [llength $etat($p,pos)]} { set ply [expr {[llength $etat($p,pos)] - 1}] }
  if {$ply < 0} { set ply 0 }
  set etat($p,trouve) $ply
  set etat($p,ply) $ply
  # Orientation: same as the main board
  if {[::board::isFlipped $p.b] != [::board::isFlipped .main.board]} { ::board::flip $p.b }
  $p.titre configure -text "[T "Partie trouvée" "Found game"] [::utils::thousands $idx] / [::utils::thousands $n]"
  set elo1 [expr {[string trim $eloB] in {{} 0} ? {} : " ([string trim $eloB])"}]
  set elo2 [expr {[string trim $eloN] in {{} 0} ? {} : " ([string trim $eloN])"}]
  $p.partie configure -text "[string trim $blanc]$elo1 – [string trim $noir]$elo2   [string trim $res]\n[string trim $tournoi]  [string trim $date]"
  afficher $p
}

proc ::moderne::apercu::afficher {p} {
  variable etat
  set pos $etat($p,pos)
  if {![llength $pos]} { return }
  set ply $etat($p,ply)
  lassign [lindex $pos $ply] coup plateau
  ::board::update $p.b $plateau
  if {$ply == 0} {
    set txt [T "Position de départ" "Start position"]
  } else {
    # The side to move after the move tells who played it
    set num [expr {($ply + 1) / 2}]
    set apres [string index $plateau 65]
    # (no expr here: "8." would become 8.0)
    if {$apres eq "b"} { set txt "$num." } else { set txt "$num..." }
    append txt [::trans $coup]
  }
  if {$ply == $etat($p,trouve)} {
    append txt "   ← [T "position trouvée" "found position"]"
  }
  $p.coup configure -text $txt
  # Last move highlighted (start and destination squares)
  if {$ply > 0} {
    set avant [lindex $pos [expr {$ply - 1}] 1]
    for {set i 0} {$i < 64} {incr i} {
      if {[string index $avant $i] ne [string index $plateau $i]} {
        ::board::colorSquare $p.b $i $::highcolor
      }
    }
  }
}

proc ::moderne::apercu::deplacer {p dir} {
  variable etat
  if {![winfo exists $p] || ![llength $etat($p,pos)]} { return }
  set fin [expr {[llength $etat($p,pos)] - 1}]
  switch -- $dir {
    debut  { set etat($p,ply) 0 }
    fin    { set etat($p,ply) $fin }
    trouve { set etat($p,ply) $etat($p,trouve) }
    default {
      set n [expr {$etat($p,ply) + $dir}]
      if {$n < 0 || $n > $fin} { return }
      set etat($p,ply) $n
    }
  }
  afficher $p
}

proc ::moderne::apercu::partie {p dir} {
  variable etat
  if {![winfo exists $p] || $etat($p,idx) == 0} { return }
  set n [expr {$etat($p,idx) + $dir}]
  if {$n < 1 || $n > [sc_filter count]} { return }
  montrer $p $n
}

### Opens the displayed game on the main board, at the same position
proc ::moderne::apercu::ouvrir {p} {
  variable etat
  if {![winfo exists $p] || $etat($p,g) == 0} { return }
  set ply $etat($p,ply)
  if {[::game::Load $etat($p,g)] == -1} { return }
  sc_move start
  sc_move forward $ply
  updateBoard -pgn
}

### End Siby
