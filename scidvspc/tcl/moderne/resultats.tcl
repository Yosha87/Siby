###
### resultats.tcl: the results of a move search (Siby), in a module next to
### the notation, opened by the search itself:
###   - the search asked, the number of games, White / Draw / Black (bar, as
###     in the library) and the average rating
###   - one row per game: White, Black (with ratings), result, the moves
###     found ("16.♗xh7+ ♔xh7 17.♘g5+"), date, event
###   - hover: the position of the moves found on the main board, under a
###     veil; click: the game in a new notation tab, at that move
### Only the rows on screen are drawn and read (many results are fine).
###

namespace eval ::moderne::resultats {
  variable w .resultatsWin
  variable base 0          ;# base searched
  variable total 0         ;# games found
  variable coups 1         ;# plies shown in the "moves found" column
  variable requete {}      ;# the search, as written
  variable lignes          ;# lignes(k): row k (0 = first game found)
  array set lignes {}
  variable survolI -1
  variable apres {}
}

proc ::moderne::resultats::T {fr en} { return [::moderne::tr $fr $en] }

### After a search: the module shows the current filter of the base
###   requete: the search as written; coups: plies of the moves found to show
proc ::moderne::resultats::montrer {requete {coups 1}} {
  variable w
  variable base
  variable total
  variable lignes
  set base [sc_base current]
  set ::moderne::resultats::coups [expr {max(1, min(6, $coups))}]
  set ::moderne::resultats::requete $requete
  set total [sc_filter count]
  array unset lignes
  creer
  set f $w.f
  $f.titre configure -text $requete
  lassign [sc_search resultstats] n bl nu no elo
  set texte "[::utils::thousands $n] [T [expr {$n > 1 ? "parties" : "partie"}] [expr {$n > 1 ? "games" : "game"}]] [T sur of] [::utils::thousands [sc_base numGames $base]]"
  if {$elo > 0} { append texte "  •  [T "Elo moyen" "Average rating"] $elo" }
  $f.resume configure -text $texte
  set ::moderne::resultats::stats [list $n $bl $nu $no]
  dessinerBarre
  $f.cv yview moveto 0
  dessiner
  if {$::docking::USE_DOCKING} {
    # (a view laid over the Lab, My databases or a broadcast: taken off, the
    # results asked for are shown in the Lab and not drawn over it)
    catch ::moderne::mesbases::retirerSuperposition
    catch ::moderne::direct::retirerSuperposition
    catch placerOnglet
    catch {[::docking::find_tbn .fdockresultatsWin] select .fdockresultatsWin}
  } else {
    catch {raise $w}
  }
}

### The results next to the notation when they ended up next to an engine
### (Yosha 2026-11-12: a search's results opened next to Stockfish; not
### reproduced, siby.log says where they were). A place chosen by dragging
### the tab anywhere else is kept.
proc ::moderne::resultats::placerOnglet {} {
  set d .fdockresultatsWin
  if {![winfo exists $d] || ![winfo exists .fdockpgnWin]} { return }
  set nb [::docking::find_tbn .fdockpgnWin]
  set src [::docking::find_tbn $d]
  if {$nb eq {} || ![winfo exists $nb] || $src eq $nb} { return }
  set moteur 0
  if {$src ne {} && [winfo exists $src]} {
    foreach t [$src tabs] { if {[string match .fdockanalysisWin* $t]} { set moteur 1 } }
  }
  if {$src ne {} && !$moteur} { return }
  catch {::moderne::journal "Search results: tab was in {$src}, put next to the notation in $nb"}
  if {$src ne {} && [winfo exists $src]} { catch {$src forget $d} }
  if {[catch {$nb add $d -text [T "Résultats" "Results"]}]} { catch {$nb select $d} }
  catch {raise $d}
}

proc ::moderne::resultats::creer {} {
  variable w
  if {[winfo exists $w.f]} { return }
  if {$::docking::USE_DOCKING} {
    ::createToplevel $w
    ::setTitle $w [T "Résultats" "Results"]
    catch {::createToplevelFinalize $w}
  } else {
    toplevel $w
    wm title $w [T "Résultats de la recherche" "Search results"]
    wm geometry $w 900x600
  }
  set f [ttk::frame $w.f -padding {12 10 12 6}]
  pack $f -fill both -expand 1
  ttk::label $f.titre -font font_Bold
  ttk::label $f.resume -foreground [::moderne::c texteDoux]
  canvas $f.barre -height 22 -highlightthickness 0 -background [::moderne::c surface]
  pack $f.titre -side top -anchor w
  pack $f.resume -side top -anchor w -pady {2 4}
  pack $f.barre -side top -fill x -pady {0 8}
  bind $f.barre <Configure> ::moderne::resultats::dessinerBarre
  ttk::scrollbar $f.sb -command ::moderne::resultats::defiler
  canvas $f.cv -highlightthickness 0 -borderwidth 0 -background [::moderne::c surface] \
      -yscrollincrement 1 -yscrollcommand ::moderne::resultats::barreDefil
  pack $f.sb -side right -fill y
  pack $f.cv -side left -fill both -expand 1
  bind $f.cv <Configure> ::moderne::resultats::dessiner
  bind $f.cv <Motion> {::moderne::resultats::survol %y}
  bind $f.cv <Leave> {::moderne::resultats::survol -1}
  bind $f.cv <ButtonRelease-1> {::moderne::resultats::clic %y}
  bind $f.cv <Button-3> {::moderne::resultats::menu %y %X %Y}
  bind $f.cv <MouseWheel> {::moderne::resultats::defiler scroll [expr {%D > 0 ? -3 : 3}] units}
  bind $f.cv <Button-4> {::moderne::resultats::defiler scroll -3 units}
  bind $f.cv <Button-5> {::moderne::resultats::defiler scroll 3 units}
  catch {::moderne::repeindre $w}
}

### White / Draw / Black of all the games found, as in the library
proc ::moderne::resultats::dessinerBarre {} {
  variable w
  variable stats
  set cv $w.f.barre
  if {![winfo exists $cv] || ![info exists stats]} { return }
  $cv delete all
  lassign $stats n bl nu no
  if {!$n} { return }
  set b [expr {round(100.0 * $bl / $n)}]
  set d [expr {round(100.0 * $nu / $n)}]
  set larg [winfo width $cv] ; if {$larg < 50} { set larg 600 }
  catch {::moderne::biblio::barreBNN $cv 0 2 [expr {$larg - 2}] 20 $b $d [expr {max(0, 100 - $b - $d)}] \
      [expr {$::moderne::theme eq "sombre"}]}
  catch {::utils::tooltip::Set $cv [T "Blancs / Nulles / Noirs dans les parties trouvées" "White / Draw / Black in the games found"]}
}

### Scrolling: the rows on screen are drawn again
proc ::moderne::resultats::defiler {args} {
  variable w
  $w.f.cv yview {*}$args
  dessiner
}

proc ::moderne::resultats::barreDefil {a b} {
  variable w
  $w.f.sb set $a $b
}

### Height of a row, columns' places
proc ::moderne::resultats::geo {} {
  variable w
  set hl [expr {[font metrics font_Regular -linespace] + 10}]
  set larg [winfo width $w.f.cv] ; if {$larg < 100} { set larg 900 }
  set c [font measure font_Regular 0]
  # White, Black, result, moves found, date, event (the event takes what
  # is left; long texts are cut)
  set xB 8
  set lNom [expr {max(14 * $c, int(0.21 * $larg))}]
  set xN [expr {$xB + $lNom}]
  set xR [expr {$xN + $lNom}]
  set xM [expr {$xR + 5 * $c}]
  set xD [expr {$xM + max(20 * $c, int(0.22 * $larg))}]
  set xE [expr {$xD + 10 * $c}]
  return [list $hl $larg $xB $xN $xR $xM $xD $xE]
}

### Rows from..from+n-1 (0-based) read from the base when needed
proc ::moderne::resultats::lire {de n} {
  variable base
  variable total
  variable lignes
  variable coups
  set manque -1
  for {set k $de} {$k < min($total, $de + $n)} {incr k} {
    if {![info exists lignes($k)]} { set manque $k ; break }
  }
  if {$manque < 0} { return }
  set courante [sc_base current]
  if {$courante != $base} { catch {sc_base switch $base} }
  set debut [expr {($manque / 50) * 50}]
  set r {}
  catch {set r [sc_search results [expr {$debut + 1}] [expr {max(100, $n + 50)}] $coups]}
  if {$courante != $base} { catch {sc_base switch $courante} }
  set k $debut
  foreach l $r { set lignes($k) $l ; incr k }
}

proc ::moderne::resultats::dessiner {} {
  variable w
  variable total
  variable lignes
  set cv $w.f.cv
  if {![winfo exists $cv]} { return }
  lassign [geo] hl larg xB xN xR xM xD xE
  $cv delete all
  set yEnt 0
  set doux [::moderne::c texteDoux] ; set texte [::moderne::c texte]
  set h [expr {($total + 1) * $hl}]
  $cv configure -scrollregion [list 0 0 $larg $h]
  set haut [winfo height $cv]
  set y0 [$cv canvasy 0]
  set premier [expr {max(0, int($y0 / $hl) - 1)}]
  set dernier [expr {min($total - 1, int(($y0 + $haut) / $hl))}]
  # headers (row 0, kept at the top of the view)
  set yh [expr {$y0}]
  $cv create rectangle 0 $yh $larg [expr {$yh + $hl}] -fill [::moderne::c surface] -outline {} -tags entete
  foreach {x lib} [list $xB [T Blancs White] $xN [T Noirs Black] $xR [T Rés. Res.] $xM [T "Coups trouvés" "Moves found"] \
                        $xD [T Date Date] $xE [T Tournoi Event]] {
    $cv create text $x [expr {$yh + $hl / 2}] -anchor w -text $lib -font font_Small -fill $doux -tags entete
  }
  $cv create line 0 [expr {$yh + $hl - 1}] $larg [expr {$yh + $hl - 1}] -fill [::moderne::c bordure] -tags entete
  if {$total == 0} {
    $cv create text [expr {$larg / 2}] [expr {$hl * 2}] -text [T "Aucune partie trouvée" "No game found"] -fill $doux
    return
  }
  lire $premier [expr {$dernier - $premier + 1}]
  set resCoul [dict create 1-0 #629924 0-1 #cc3333 =-= #8b8b8b * #8b8b8b]
  for {set k $premier} {$k <= $dernier} {incr k} {
    if {![info exists lignes($k)]} { continue }
    lassign $lignes($k) g bl eb no en res date ev motif ply
    set y1 [expr {($k + 1) * $hl}] ; set y2 [expr {$y1 + $hl}] ; set ym [expr {($y1 + $y2) / 2}]
    $cv create rectangle 0 $y1 $larg $y2 -outline {} -tags [list fond f$k] \
        -fill [expr {$k % 2 ? [::moderne::c ligneAlt] : [::moderne::c surface]}]
    foreach {x xFin nom elo} [list $xB $xN $bl $eb $xN $xR $no $en] {
      set lElo [expr {$elo > 0 ? [font measure font_Small " $elo"] + 4 : 0}]
      set nom [couper $nom font_Regular [expr {$xFin - $x - 10 - $lElo}]]
      set t [$cv create text $x $ym -anchor w -text $nom -font font_Regular -fill $texte]
      if {$elo > 0} {
        lassign [$cv bbox $t] - - bx
        $cv create text [expr {$bx + 4}] $ym -anchor w -text $elo -font font_Small -fill $doux
      }
    }
    set r [string map {=-= ½-½} $res]
    $cv create text $xR $ym -anchor w -text $r -font font_Bold -fill [dict get $resCoul $res]
    $cv create text $xM $ym -anchor w -text [couper [figurines $motif] font_Bold [expr {$xD - $xM - 10}]] \
        -font font_Bold -fill [::moderne::c accent]
    $cv create text $xD $ym -anchor w -text [string map {.?? {} ?? {}} $date] -font font_Regular -fill $doux
    $cv create text $xE $ym -anchor w -text [couper $ev font_Regular [expr {$larg - $xE - 8}]] -font font_Regular -fill $doux
  }
  # (the long names cut by the next column)
  $cv raise entete
}

### The text cut with "…" to fit in largeur pixels
proc ::moderne::resultats::couper {texte police largeur} {
  if {$largeur <= 0} { return {} }
  if {[font measure $police $texte] <= $largeur} { return $texte }
  set n [string length $texte]
  while {$n > 0 && [font measure $police "[string range $texte 0 $n-1]…"] > $largeur} { incr n -1 }
  return "[string range $texte 0 $n-1]…"
}

### "16.Bxh7+ Kxh7" as the notation shows moves (the move numbers stay)
proc ::moderne::resultats::figurines {texte} {
  set l {}
  foreach m [split $texte] {
    regexp {^([0-9]+\.+)?(.*)$} $m -> num san
    lappend l "$num[::moderne::coupTexte $san]"
  }
  return [join $l " "]
}

### Row under the pointer, or -1
proc ::moderne::resultats::ligneSous {y} {
  variable w
  variable total
  if {$y < 0 || ![winfo exists $w.f.cv]} { return -1 }
  lassign [geo] hl
  set cv $w.f.cv
  set k [expr {int([$cv canvasy $y] / $hl) - 1}]
  if {$y < $hl || $k < 0 || $k >= $total} { return -1 }
  return $k
}

### Hover: the position of the moves found, on the main board
proc ::moderne::resultats::survol {y} {
  variable w
  variable survolI
  variable apres
  set cv $w.f.cv
  set k [ligneSous $y]
  if {$k == $survolI} { return }
  if {$survolI >= 0} {
    catch {$cv itemconfigure f$survolI -fill [expr {$survolI % 2 ? [::moderne::c ligneAlt] : [::moderne::c surface]}]}
  }
  set survolI $k
  catch {after cancel $apres}
  if {$k < 0} {
    $cv configure -cursor {}
    catch {::moderne::moteur::finApercu}
    return
  }
  $cv itemconfigure f$k -fill [::moderne::c survol]
  $cv configure -cursor hand2
  # (a short wait: going over many rows quickly reads one game only)
  set apres [after 60 [list ::moderne::resultats::apercu $k]]
}

proc ::moderne::resultats::apercu {k} {
  variable lignes
  variable survolI
  if {$k != $survolI || ![info exists lignes($k)]} { return }
  set plateau [lindex $lignes($k) 10]
  if {$plateau ne {}} { catch {::moderne::moteur::apercuPlateau $plateau} }
}

### Click: the game in a new notation tab, at the moves found
### Right-click on a game: open it, or its tournament's crosstable
proc ::moderne::resultats::menu {y X Y} {
  variable lignes
  variable base
  set k [ligneSous $y]
  if {$k < 0 || ![info exists lignes($k)]} { return }
  set g [lindex $lignes($k) 0]
  set m .resultatsMenu
  catch {destroy $m}
  ::menu $m -tearoff 0
  $m add command -label [T "Ouvrir la partie" "Open the game"] -command [list ::moderne::resultats::clic $y]
  $m add command -label [T "Voir le tableau du tournoi" "Show crosstable"] -command [list ::moderne::croise::ouvrir $base $g]
  tk_popup $m $X $Y
}

proc ::moderne::resultats::clic {y} {
  variable lignes
  variable base
  set k [ligneSous $y]
  if {$k < 0 || ![info exists lignes($k)]} { return }
  lassign $lignes($k) g - - - - - - - - ply
  catch {::moderne::moteur::finApercu}
  ::moderne::onglets::ouvrir $base $g $ply
}

### End Siby
