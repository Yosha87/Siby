###
### Siby: drag and drop in the game list
###
###   - games dragged onto another row of the list: they move there (the
###     database's order changes at once, like SCID's "move up / down");
###     a bar then offers to undo all the moves since it appeared;
###   - games dragged onto a database (a tile of the switcher under the
###     list, or of "My databases"): they are copied into it.
###
### A drag starts after a few pixels with the button held, on a selected
### row (all the selected games) or on any row (that game alone).
###

namespace eval ::moderne::glisser {
  variable etat {}       ;# {} | pret | glisse
  variable jeux {}       ;# game numbers being dragged
  variable depart {}     ;# {X Y} of the press
  variable base 0        ;# database of the dragged games
  variable cible {}      ;# {ligne <num>} | {base <slot> <name>} | {fichier <file>} | {}
  variable surligne {}   ;# widget(s) highlighted as the target
  variable deplacements {} ;# moves {from to} since the bar appeared (undo)
  variable tout 0        ;# Ctrl+A: every game of the list (the filter) is selected
  variable baseTout 0
}

### Number of games in the filter of database b
proc ::moderne::glisser::nbFiltre {b} {
  set c [sc_base current]
  sc_base switch $b
  set n [sc_filter count]
  sc_base switch $c
  return $n
}

### Ctrl+A: every game of the list, not only the rows on screen
proc ::moderne::glisser::toutSelectionner {} {
  variable tout 1
  variable baseTout [sc_base current]
  set t .glistWin.tree
  catch {$t selection set [$t children {}]}
  catch {setGamelistTitle}
}

proc ::moderne::glisser::finTout {} {
  variable tout
  if {!$tout} { return }
  set tout 0
  catch {setGamelistTitle}
}

proc ::moderne::glisser::T {fr en} { return [::moderne::tr $fr $en] }

proc ::moderne::glisser::installer {t} {
  catch {::moderne::glisser::installerChoix $t}
  bind $t <ButtonPress-1> {+::moderne::glisser::presser %W %x %y %X %Y}
  bind $t <B1-Motion> {+::moderne::glisser::bouger %W %X %Y}
  bind $t <ButtonRelease-1> {+::moderne::glisser::lacher %W %X %Y}
  $t tag configure cibleGlisse -background [::moderne::c accent] -foreground #ffffff
}

proc ::moderne::glisser::presser {t x y X Y} {
  variable etat
  variable jeux
  variable depart
  variable base
  variable tout
  set etat {}
  if {[$t identify region $x $y] ni {cell tree}} { return }
  set id [$t identify item $x $y]
  if {$id eq {}} { return }
  # every game selected (Ctrl+A): dragging takes the whole filter, a click
  # outside the selection ends it
  if {$tout} {
    if {$id in [$t selection]} {
      set jeux filtre
      set depart [list $X $Y]
      set base [sc_base current]
      set etat pret
      return
    }
    finTout
  }
  # (the selection before the click changes it: every chosen game, on
  # screen or not)
  set ids [expr {$id in [$t selection] ? [$t selection] : [list $id]}]
  set jeux {}
  foreach i $ids {
    set n [$t set $i Number]
    if {[string is integer -strict $n] && $n > 0} { lappend jeux $n }
  }
  if {$id in [$t selection]} { catch {set jeux [numerosChoisis]} }
  if {![llength $jeux]} { return }
  set jeux [lsort -integer -unique $jeux]
  set depart [list $X $Y]
  set base [sc_base current]
  set etat pret
}

proc ::moderne::glisser::bouger {t X Y} {
  variable etat
  variable depart
  variable jeux
  if {$etat eq {}} { return }
  if {$etat eq "pret"} {
    lassign $depart x0 y0
    if {abs($X - $x0) + abs($Y - $y0) < 8} { return }
    set etat glisse
    # (the dragged games stay selected)
    catch {
      set sel {}
      foreach i [$t children {}] { if {[$t set $i Number] in $jeux} { lappend sel $i } }
      if {[llength $sel]} { $t selection set $sel }
    }
    jeton
  }
  catch {wm geometry .glisserJeton +[expr {$X + 14}]+[expr {$Y + 10}]}
  chercherCible $t $X $Y
  return -code break
}

### Small label following the pointer
proc ::moderne::glisser::jeton {} {
  variable jeux
  set j .glisserJeton
  catch {destroy $j}
  toplevel $j -background [::moderne::c accent]
  wm overrideredirect $j 1
  catch {wm attributes $j -topmost 1}
  label $j.l -background [::moderne::c accent] -foreground #ffffff -font font_Small -padx 8 -pady 3 \
      -text [texteJeux]
  pack $j.l
}

proc ::moderne::glisser::texteJeux {} {
  variable jeux
  if {$jeux eq "filtre"} {
    set n [sc_filter count]
    return [expr {$n == 1 ? [T "1 partie" "1 game"] : "[::utils::thousands $n] [T parties games]"}]
  }
  set n [llength $jeux]
  return [expr {$n == 1 ? [T "1 partie" "1 game"] : "$n [T parties games]"}]
}

proc ::moderne::glisser::effacerSurligne {} {
  variable surligne
  foreach {quoi w x} $surligne {
    switch -- $quoi {
      ligne { catch {$w tag remove cibleGlisse $x} }
      tuile { catch {$w configure -highlightbackground $x} }
      carte { catch {::moderne::mesbases::surligner $w 0} }
      cadre { catch {$w configure -background $x} }
    }
  }
  set surligne {}
}

### What is under the pointer: a row of the list, a database tile
proc ::moderne::glisser::chercherCible {t X Y} {
  variable cible
  variable surligne
  variable base
  effacerSurligne
  set cible {}
  set texte [texteJeux]
  set w [winfo containing $X $Y]
  if {$w eq $t} {
    set y [expr {$Y - [winfo rooty $t]}]
    set id [$t identify item 5 $y]
    if {$id ne {}} {
      set n [$t set $id Number]
      if {[string is integer -strict $n] && $n > 0} {
        set cible [list ligne $n]
        $t tag add cibleGlisse $id
        lappend surligne ligne $t $id
        set texte "[texteJeux] → [T "place" "position"] $n"
      }
    }
  } elseif {[regexp {^\.glistWin\.baseWin\.c\.f([0-9])} $w -> slot]} {
    if {[sc_base inUse $slot] && $slot != $base} {
      set f .glistWin.baseWin.c.f$slot
      set cible [list base $slot]
      lappend surligne cadre $f [$f cget -background]
      $f configure -background [::moderne::c accent]
      set texte "[texteJeux] → [::moderne::nomBase [sc_base filename $slot]]"
    }
  } elseif {[regexp {^(\.[^.]+\.c\.g(?:\.z[0-9]+)?\.t[0-9]+)} $w -> tuile] &&
            [info exists ::moderne::mesbases::tuileFichier($tuile)]} {
    set fichier $::moderne::mesbases::tuileFichier($tuile)
    set slot [::moderne::mesbases::slot $fichier]
    if {$slot != $base} {
      set cible [list fichier $fichier]
      lappend surligne carte $tuile {}
      ::moderne::mesbases::surligner $tuile 1
      set texte "[texteJeux] → [file rootname [file tail $fichier]]"
    }
  }
  catch {.glisserJeton.l configure -text $texte}
}

proc ::moderne::glisser::lacher {t X Y} {
  variable etat
  variable cible
  variable jeux
  variable base
  set e $etat
  set etat {}
  if {$e ne "glisse"} { return }
  catch {destroy .glisserJeton}
  effacerSurligne
  set c $cible
  set cible {}
  switch -- [lindex $c 0] {
    ligne   { after idle [list ::moderne::glisser::deplacer $base $jeux [lindex $c 1]] }
    base    { after idle [list ::moderne::glisser::copier $base $jeux [lindex $c 1]] }
    fichier { after idle [list ::moderne::glisser::copierFichier $base $jeux [lindex $c 1]] }
  }
  return -code break
}

################################################################################
### Moving games inside the database
################################################################################

### Moves games (sorted numbers) to position n of database b: before the
### row when moving up, after it when moving down
proc ::moderne::glisser::deplacer {b jeux n} {
  variable deplacements
  if {$jeux eq "filtre"} { return }
  if {$b != [sc_base current]} { return }
  if {$n in $jeux} { return }
  if {![verifierEcriture $b]} { return }
  set g1 [lindex $jeux 0]
  set gk [lindex $jeux end]
  if {$g1 < $n && $gk > $n} {
    tk_messageBox -icon info -type ok -title Siby -parent .glistWin -message [T \
        "Dépose les parties au-dessus ou au-dessous de toutes celles que tu déplaces." \
        "Drop the games above or below all those you move."]
    return
  }
  set confirm [::game::ConfirmDiscard]
  if {$confirm == 2} { return }
  if {$confirm == 0} { ::game::Save }
  set courant [sc_game number]
  set k [llength $jeux]
  set mouvements {}
  if {$g1 > $n} {
    # up: game j goes to n + j
    set j 0
    foreach g $jeux { lappend mouvements [list $g [expr {$n + $j}]] ; incr j }
  } else {
    # down: the last first, to n, the previous to n - 1...
    set j 0
    foreach g [lreverse $jeux] { lappend mouvements [list $g [expr {$n - $j}]] ; incr j }
  }
  busyCursor .
  set fait {}
  set code [catch {
    foreach m $mouvements {
      lassign $m a d
      if {$a == $d} { continue }
      sc_game reorder $a $d
      lappend fait $m
      set courant [suivre $courant $a $d]
    }
  } err]
  unbusyCursor .
  if {$code} {
    tk_messageBox -icon error -type ok -title Siby -parent .glistWin -message $err
  }
  if {![llength $fait]} { return }
  lappend deplacements {*}$fait
  apres $b $courant
  # the moved games stay selected
  set nouveaux {}
  foreach m $mouvements { lappend nouveaux [lindex $m 1] }
  after idle [list ::moderne::glisser::selectionner $nouveaux]
  barre $b
}

### Number of game c after moving game a to position d
proc ::moderne::glisser::suivre {c a d} {
  if {$c == $a} { return $d }
  if {$a < $d && $c > $a && $c <= $d} { return [expr {$c - 1}] }
  if {$d < $a && $c >= $d && $c < $a} { return [expr {$c + 1}] }
  return $c
}

### After moves: the open game reloaded under its new number, windows
### refreshed, PGN file rewritten
proc ::moderne::glisser::apres {b courant} {
  if {$courant > 0 && $courant != [sc_game number]} {
    catch {sc_game load $courant}
    catch {updateBoard -pgn}
  }
  catch {::tree::refresh}
  catch {refreshWindows}
  catch {::windows::gamelist::Refresh}
  catch {::moderne::pgnfichier::modifie $b}
}

proc ::moderne::glisser::selectionner {nums} {
  set t .glistWin.tree
  if {![winfo exists $t]} { return }
  set sel {}
  foreach i [$t children {}] { if {[$t set $i Number] in $nums} { lappend sel $i } }
  if {[llength $sel]} { $t selection set $sel ; $t see [lindex $sel 0] }
}

### Bar above the list: the moves can be undone
proc ::moderne::glisser::barre {b} {
  variable deplacements
  set w .glistWin.glisserBarre
  if {![winfo exists .glistWin]} { return }
  if {![winfo exists $w]} {
    frame $w -background [::moderne::c surface] -padx 8 -pady 4
    label $w.l -background [::moderne::c surface] -foreground [::moderne::c texte]
    ttk::button $w.annuler -text [T "Annuler" "Undo"] -command [list ::moderne::glisser::annuler $b]
    ttk::button $w.ok -text [T "Garder cet ordre" "Keep this order"] -command ::moderne::glisser::garder
    catch {::utils::tooltip::Set $w.l [T "L'ordre est déjà enregistré dans la base ; « Annuler » remet les parties à leur place." \
        "The order is already saved in the database; \"Undo\" puts the games back."]}
    pack $w.l -side left
    pack $w.ok $w.annuler -side right -padx {6 0}
    set avant [lindex [pack slaves .glistWin] 0]
    if {$avant ne {}} { pack $w -side top -fill x -before $avant } else { pack $w -side top -fill x }
  }
  set n [llength $deplacements]
  $w.l configure -text [expr {$n == 1 ? [T "Ordre modifié : 1 déplacement" "Order changed: 1 move"] \
      : [T "Ordre modifié : $n déplacements" "Order changed: $n moves"]}]
}

proc ::moderne::glisser::garder {} {
  variable deplacements {}
  catch {destroy .glistWin.glisserBarre}
}

proc ::moderne::glisser::annuler {b} {
  variable deplacements
  if {$b != [sc_base current] || ![sc_base inUse $b]} { garder ; return }
  set confirm [::game::ConfirmDiscard]
  if {$confirm == 2} { return }
  if {$confirm == 0} { ::game::Save }
  set courant [sc_game number]
  busyCursor .
  foreach m [lreverse $deplacements] {
    lassign $m a d
    if {[catch {sc_game reorder $d $a}]} { break }
    set courant [suivre $courant $d $a]
  }
  unbusyCursor .
  garder
  apres $b $courant
}

################################################################################
### Copying games into another database
################################################################################

### Can games be written into database b? (padlock, read-only)
proc ::moderne::glisser::verifierEcriture {b} {
  set nom [::moderne::nomBase [sc_base filename $b]]
  if {![catch {::moderne::mesbases::estCadenassee $b} c] && $c} {
    tk_messageBox -icon info -type ok -title Siby -message [T \
        "« $nom » est cadenassée : lève le cadenas (clic droit sur sa tuile) pour la modifier." \
        "\"$nom\" is padlocked: lift the padlock (right-click on its tile) to change it."]
    return 0
  }
  set ro 0
  set c [sc_base current]
  sc_base switch $b
  catch {set ro [sc_base isReadOnly]}
  sc_base switch $c
  if {$ro} {
    tk_messageBox -icon info -type ok -title Siby -message [T \
        "« $nom » est en lecture seule." "\"$nom\" is read-only."]
    return 0
  }
  return 1
}

proc ::moderne::glisser::copier {de jeux vers} {
  if {![sc_base inUse $de] || ![sc_base inUse $vers] || $de == $vers} { return }
  if {![verifierEcriture $vers]} { return }
  busyCursor .
  # (every game of the list: the filter)
  set code [catch {
    if {$jeux eq "filtre"} { sc_filter copy $de $vers } else { sc_filter copy $de $vers $jeux }
  } err]
  unbusyCursor .
  if {$code} {
    tk_messageBox -icon error -type ok -title Siby -message $err
    return
  }
  catch {::moderne::pgnfichier::modifie $vers}
  catch {::windows::switcher::Refresh}
  catch {::moderne::mesbases::remplir}
  set n [expr {$jeux eq "filtre" ? [nbFiltre $de] : [llength $jeux]}]
  set nom [file rootname [::moderne::nomBase [sc_base filename $vers]]]
  catch {::moderne::nsb::annonce [expr {$n == 1 ? [T "1 partie copiée dans « $nom »" "1 game copied to \"$nom\""] \
      : [T "$n parties copiées dans « $nom »" "$n games copied to \"$nom\""]}] -1}
  after 2500 {catch ::moderne::nsb::finAnnonce}
}

### A tile of "My databases": the database is opened first if needed
### (without showing it), then the games are copied
proc ::moderne::glisser::copierFichier {de jeux f} {
  set b [::moderne::mesbases::slot $f]
  if {!$b} {
    set c [sc_base current]
    set ::file::discret 1
    catch {::file::Open [expr {[::moderne::mesbases::estPgn $f] ? $f : [file rootname $f]}]}
    set ::file::discret 0
    catch {::file::SwitchToBase $c}
    set b [::moderne::mesbases::slot $f]
  }
  if {!$b} { return }
  copier $de $jeux $b
}

################################################################################
### Several games chosen as in Windows' file explorer (Yosha 2026-11-06).
### The list only holds the rows on screen (SCID pages it): the chosen games
### are kept here by number, put back on the rows when the page changes,
### and the actions take them all (delete, copy, drag, right click).
###   click, Ctrl+click, Shift+click (from the last one clicked, even on
###   another page), Ctrl+Shift+click; arrows, Shift+arrows, Ctrl+arrows
###   (moves without choosing) and Ctrl+Space, Home / End, Page up / down
###   (with Shift), Ctrl+A (all, see toutSelectionner)
################################################################################

namespace eval ::moderne::glisser {
  variable choix {}       ;# chosen game numbers (database choixBase)
  variable choixBase 0
  variable ancre {}       ;# position in the list (1 = first) of the anchor
  variable curseur {}     ;# position of the current row
  variable appui {}       ;# {modifiers position} of the last click, until the selection follows
  variable reapplique 0
}

### The selection changes Siby makes itself (the page refilled, the chosen
### games put back) are told by Tk later, once the event loop runs: they
### are left out until it is idle
proc ::moderne::glisser::ignorerSuite {} {
  variable reapplique 1
  after cancel ::moderne::glisser::finIgnorer
  after idle ::moderne::glisser::finIgnorer
}
proc ::moderne::glisser::finIgnorer {} { variable reapplique 0 }

### Position in the list (1 = first) of row id
proc ::moderne::glisser::position {t id} {
  set i [lsearch -exact [$t children {}] $id]
  if {$i < 0} { return {} }
  return [expr {$::glstart + $i}]
}

### Game numbers of the list from position p1 to p2 (in the list's order)
proc ::moderne::glisser::numerosEntre {p1 p2} {
  if {$p1 > $p2} { lassign [list $p1 $p2] p2 p1 }
  set k [lsearch -exact $::glistHeaders Number]
  if {$k < 0} { return {} }
  set l {}
  catch {
    foreach ligne [split [string trimright [sc_game list $p1 [expr {$p2 - $p1 + 1}] [list [lindex $::glistCodes $k]] 0] \n] \n] {
      set n [string trim [lindex $ligne 0]]
      if {[string is integer -strict $n] && $n > 0} { lappend l $n }
    }
  }
  return $l
}

proc ::moderne::glisser::numeroLigne {t id} {
  set n [string trim [$t set $id Number]]
  expr {[string is integer -strict $n] ? $n : {}}
}

### The chosen games put back on the rows on screen
proc ::moderne::glisser::reappliquer {} {
  variable choix
  variable choixBase
  variable curseur
  variable reapplique
  variable tout
  set t .glistWin.tree
  if {![winfo exists $t] || $tout} { return }
  if {$choixBase != [sc_base current]} { set choix {} ; set choixBase [sc_base current] ; return }
  set sel {}
  set i 0
  foreach id [$t children {}] {
    set n [numeroLigne $t $id]
    if {$n ne {} && [dict exists $choix $n]} { lappend sel $id }
    if {$curseur ne {} && $::glstart + $i == $curseur} { catch {$t focus $id} }
    incr i
  }
  if {[lsort $sel] eq [lsort [$t selection]]} { return }
  ignorerSuite
  $t selection set $sel
}

### The chosen games of the list (numbers, sorted), "filtre" after Ctrl+A
proc ::moderne::glisser::numerosChoisis {} {
  variable tout
  variable choix
  variable choixBase
  if {$tout} { return filtre }
  set t .glistWin.tree
  if {$choixBase == [sc_base current] && [dict size $choix]} {
    return [lsort -integer [dict keys $choix]]
  }
  set l {}
  catch {foreach id [$t selection] { set n [numeroLigne $t $id] ; if {$n ne {}} { lappend l $n } }}
  return [lsort -integer -unique $l]
}

### A click: its modifiers and its row's position, for the selection that
### follows (Tk's own bindings change it)
proc ::moderne::glisser::noterAppui {t x y etat} {
  variable appui
  set id [$t identify item $x $y]
  if {$id eq {} || [$t identify region $x $y] ni {cell tree}} { set appui {} ; return }
  set m {}
  if {$etat & 4} { lappend m ctrl }
  if {$etat & 1} { lappend m shift }
  set appui [list $m [position $t $id]]
}

### The list's selection changed (a click, or Siby choosing a row)
proc ::moderne::glisser::selectionChangee {t} {
  variable reapplique
  variable appui
  variable choix
  variable choixBase
  variable ancre
  variable curseur
  variable tout
  if {$reapplique || $tout} { return }
  set choixBase [sc_base current]
  set page {}
  foreach id [$t children {}] { set n [numeroLigne $t $id] ; if {$n ne {}} { lappend page $n } }
  set sur {}
  foreach id [$t selection] { set n [numeroLigne $t $id] ; if {$n ne {}} { lappend sur $n } }
  lassign $appui m p
  set appui {}
  if {$p eq {}} {
    # (no click: Siby chose a row, the current game...)
    set choix {}
    foreach n $sur { dict set choix $n 1 }
    catch {set curseur [position $t [lindex [$t selection] 0]]}
    if {$curseur ne {}} { set ancre $curseur }
    return
  }
  if {"shift" in $m && $ancre ne {}} {
    if {"ctrl" ni $m} { set choix {} }
    foreach n [numerosEntre $ancre $p] { dict set choix $n 1 }
    set curseur $p
    after idle ::moderne::glisser::reappliquer
    return
  }
  if {"ctrl" in $m} {
    foreach n $page { dict unset choix $n }
  } else {
    set choix {}
  }
  foreach n $sur { dict set choix $n 1 }
  set ancre $p
  set curseur $p
}

### Arrow keys and the others (sens: -1 1 debut fin -page page; mode: {}
### shift ctrl ctrlshift)
proc ::moderne::glisser::touche {t sens mode} {
  variable choix
  variable choixBase
  variable ancre
  variable curseur
  finTout
  set total [sc_filter count]
  if {$total < 1} { return }
  if {$choixBase != [sc_base current]} { set choix {} ; set choixBase [sc_base current] ; set curseur {} ; set ancre {} }
  if {$curseur eq {}} { catch {set curseur [position $t [$t focus]]} }
  if {$curseur eq {}} { set curseur $::glstart }
  switch -- $sens {
    debut { set p 1 }
    fin   { set p $total }
    page  { set p [expr {$curseur + max(1, $::glistSize - 1)}] }
    -page { set p [expr {$curseur - max(1, $::glistSize - 1)}] }
    default { set p [expr {$curseur + $sens}] }
  }
  set p [expr {max(1, min($total, $p))}]
  set curseur $p
  switch -- $mode {
    shift {
      if {$ancre eq {}} { set ancre $p }
      set choix {}
      foreach n [numerosEntre $ancre $p] { dict set choix $n 1 }
    }
    ctrlshift {
      if {$ancre eq {}} { set ancre $p }
      foreach n [numerosEntre $ancre $p] { dict set choix $n 1 }
    }
    ctrl {}
    default {
      set choix {}
      foreach n [numerosEntre $p $p] { dict set choix $n 1 }
      set ancre $p
    }
  }
  # (the row brought on screen: the page follows)
  set fin [expr {$::glstart + $::glistSize - 1}]
  if {$p < $::glstart} {
    set ::glstart $p
    ::windows::gamelist::Refresh first
  } elseif {$p > $fin} {
    set ::glstart [expr {max(1, $p - $::glistSize + 1)}]
    ::windows::gamelist::Refresh first
  }
  reappliquer
  catch {$t see [lindex [$t children {}] [expr {$p - $::glstart}]]}
  # (the game chosen: its line of moves and its first position on the board)
  catch {::moderne::biblio::apercuClavier $t}
}

### Ctrl+Space: the current row chosen or not
proc ::moderne::glisser::basculerCurseur {t} {
  variable choix
  variable curseur
  variable ancre
  variable choixBase
  if {$curseur eq {}} { return }
  set choixBase [sc_base current]
  set n [lindex [numerosEntre $curseur $curseur] 0]
  if {$n eq {}} { return }
  if {[dict exists $choix $n]} { dict unset choix $n } else { dict set choix $n 1 }
  set ancre $curseur
  reappliquer
}

proc ::moderne::glisser::installerChoix {t} {
  bind $t <ButtonPress-1> {+::moderne::glisser::noterAppui %W %x %y %s}
  bind $t <<TreeviewSelect>> {+::moderne::glisser::selectionChangee %W}
  foreach {k sens} {Up -1 Down 1 Home debut End fin Prior -page Next page} {
    foreach {mod mode} {{} {} Shift- shift Control- ctrl Control-Shift- ctrlshift} {
      bind $t <${mod}$k> [list ::moderne::glisser::touche %W $sens $mode]
      bind $t <${mod}$k> +break
    }
  }
  bind $t <Control-space> {::moderne::glisser::basculerCurseur %W ; break}
  # (Enter: the current row's game opened)
  bind $t <Return> {catch {::windows::gamelist::Load [::moderne::glisser::numeroLigne %W [%W focus]]} ; break}
  # (the chosen games put back once the page is refilled)
  if {![llength [info commands ::windows::gamelist::RefreshAvantChoix]]} {
    rename ::windows::gamelist::Refresh ::windows::gamelist::RefreshAvantChoix
    proc ::windows::gamelist::Refresh {args} {
      catch ::moderne::glisser::ignorerSuite
      set r [::windows::gamelist::RefreshAvantChoix {*}$args]
      catch ::moderne::glisser::reappliquer
      return $r
    }
  }
}
