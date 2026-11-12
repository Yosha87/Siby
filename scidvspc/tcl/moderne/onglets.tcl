###
### onglets.tcl: notation tabs (Siby), like the game tabs of ChessBase.
### Each tab holds a game: the active tab is the game on the board, the
### others are kept aside whole (database, number, moves, variations,
### comments, position, unsaved changes) by "sc_game park" (tkscid.cpp).
###   - Ctrl+N: a new game in a new tab;
###   - a game opened from the prep's lists: a new tab;
###   - click a tab to go back to its game, × or middle click to close it.
### Loading a game in other ways replaces the game of the active tab, as
### before.
###

namespace eval ::moderne::onglets {
  variable onglets {t1}     ;# tabs, in order
  variable actif t1         ;# tab of the game on the board
  variable parque           ;# parque(tab) = id of its parked game
  array set parque {}
  variable suivant 2
  variable titres           ;# titres(tab) = last title shown
  array set titres {}
}

proc ::moderne::onglets::T {fr en} { return [::moderne::tr $fr $en] }

### Something that must not lose the board: a game against an engine, an
### annotation running. Returns the reason, or "".
proc ::moderne::onglets::occupe {} {
  if {[winfo exists .serGameWin] || ([info exists ::moderne::alterego::actif] && $::moderne::alterego::actif)} {
    # (the game is over: its window is closed, as with "Analysis board";
    # Ctrl+N was refused after the result, Yosha 2026-11-04)
    if {[info exists ::moderne::jeu::fini] && $::moderne::jeu::fini && [winfo exists .serGameWin]} {
      catch {::sergame::abortGame}
      catch ::moderne::disposition::jeuApresAnnuler
      return {}
    }
    return [T "Termine d'abord la partie en cours." "Finish the game in progress first."]
  }
  # (an annotation or a review in progress works on the game in memory: it
  # is stopped if the user agrees, else nothing is opened)
  if {[info exists ::moderne::oracle::etat] && $::moderne::oracle::etat ni {idle fini {}}} {
    set r [tk_messageBox -parent . -icon question -type yesno -default yes -title Siby -message [T \
        "La review (ou l'annotation) de la partie actuelle n'est pas finie.\n\nL'arrêter et continuer ?" \
        "The review (or annotation) of the current game is not finished.\n\nStop it and go on?"]]
    if {$r ne "yes"} { return [T "Review en cours : rien n'a été ouvert." "Review in progress: nothing was opened."] }
    catch {destroy .bilanWin}
    catch {destroy .fdockbilanWin}
    catch ::moderne::bilan::ferme
    catch {destroy .oracleWin}
    catch ::moderne::oracle::arreter
  }
  return {}
}

### (a message box: a note in the status bar went unnoticed)
proc ::moderne::onglets::refuser {raison} {
  journal "  refused: $raison"
  tk_messageBox -parent . -icon info -title Siby -message $raison
}

### Opens a new tab and runs script there (empty: a new game). The game of
### the active tab stays in its tab. Returns 0 if refused.
proc ::moderne::onglets::nouveau {{script {}}} {
  variable onglets
  variable actif
  variable parque
  variable suivant
  set r [occupe]
  if {$r ne {}} { refuser $r ; return 0 }
  catch {setTrialMode 0}
  set parque($actif) [sc_game park]
  set t t$suivant
  incr suivant
  set i [lsearch -exact $onglets $actif]
  set onglets [linsert $onglets [expr {$i + 1}] $t]
  set actif $t
  if {$script ne {}} {
    uplevel #0 $script
  } else {
    updateBoard -pgn
  }
  catch {refreshWindows}
  dessiner
  return 1
}

### Ctrl+N
proc ::moderne::onglets::nouvellePartie {} {
  # (an empty game already: no new tab, like a browser's new tab page)
  if {[sc_game info halfmoves] == 0 && ![sc_game altered] && [sc_game number] == 0 \
        && [sc_game info white] in {{} ?} && [sc_game info black] in {{} ?}} {
    return
  }
  nouveau
}

### Opens game gnum of base b in a new tab (the base's game list, the
### prep's lists...); an empty active tab is reused
### Each step of opening a game, in "ouverture.log" (Siby's folder): a
### click that opens nothing can then be explained
proc ::moderne::onglets::journal {texte} {
  catch {
    set f [file join $::scidUserDir ouverture.log]
    if {[file exists $f] && [file size $f] > 200000} { file delete $f }
    set c [open $f a]
    puts $c "[clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}] $texte"
    close $c
  }
}

proc ::moderne::onglets::ouvrir {b gnum {ply 0}} {
  set ouvertes {}
  catch {
    for {set i 1} {$i <= [sc_base count total]} {incr i} {
      if {[sc_base inUse $i]} { lappend ouvertes "$i:[sc_base numGames $i]" }
    }
  }
  journal "open base $b game $gnum ply $ply: current base [sc_base current] game [sc_game number], bases in use $ouvertes"
  # the game already open in a tab: that tab, not a second copy (Yosha
  # 2026-11-01)
  set t [ongletDe $b $gnum]
  if {$t ne {}} {
    journal "  already open in tab $t"
    variable actif
    if {$t ne $actif} { activer $t }
    if {$ply > 0 && $t eq $actif} {
      sc_move start
      sc_move forward $ply
      updateBoard -pgn
    }
    after idle ::moderne::onglets::montrerNotation
    return 1
  }
  set script [list ::moderne::onglets::charger $b $gnum $ply]
  if {[videActif]} {
    set r [occupe]
    if {$r ne {}} { refuser $r ; return 0 }
    uplevel #0 $script
    dessiner
    return 1
  }
  return [nouveau $script]
}

### The tab holding game gnum of database b (empty if none)
proc ::moderne::onglets::ongletDe {b gnum} {
  variable onglets
  variable actif
  variable parque
  if {![string is integer -strict $gnum] || $gnum <= 0} { return {} }
  if {[sc_base current] == $b && [sc_game number] == $gnum} { return $actif }
  foreach t $onglets {
    if {$t eq $actif || ![info exists parque($t)]} { continue }
    if {[catch {sc_game park info $parque($t)} i]} { continue }
    if {[lindex $i 0] == $b && [lindex $i 1] == $gnum} { return $t }
  }
  return {}
}

proc ::moderne::onglets::charger {b gnum {ply 0}} {
  if {$b != [sc_base current]} { ::file::SwitchToBase $b }
  journal "  switched: current base [sc_base current] ([sc_base numGames] games)"
  if {[::game::Load $gnum] == -1} { journal "  load refused (unsaved game kept)" ; return }
  journal "  loaded: base [sc_base current] game [sc_game number]"
  # the notation comes to the front (else, behind the game list or the
  # preparation, nothing seems to happen: the game opens at its start)
  after idle ::moderne::onglets::montrerNotation
  # (never silent: if the game did not come, say why)
  if {[sc_base current] != $b || [sc_game number] != $gnum} {
    set nom $b
    catch {set nom [::moderne::nomBase [sc_base filename $b]]}
    refuser [T "La partie $gnum de la base $nom n'a pas pu être ouverte." \
                "Game $gnum of database $nom could not be opened."]
    return
  }
  if {$ply > 0} {
    sc_move start
    sc_move forward $ply
    updateBoard -pgn
  }
}

proc ::moderne::onglets::montrerNotation {} {
  catch {
    set nb [::docking::find_tbn .fdockpgnWin]
    if {$nb ne {}} { $nb select .fdockpgnWin }
  }
  catch {raise .pgnWin}
}

### Is the active tab an untouched new game?
proc ::moderne::onglets::videActif {} {
  expr {[sc_game number] == 0 && ![sc_game altered] && [sc_game info halfmoves] == 0}
}

### Back to the game of tab t
proc ::moderne::onglets::activer {t} {
  variable onglets
  variable actif
  variable parque
  if {$t eq $actif || ![info exists parque($t)]} { return }
  set r [occupe]
  if {$r ne {}} { refuser $r ; return }
  catch {setTrialMode 0}
  set p $parque($t)
  set base [lindex [sc_game park info $p] 0]
  # (its database was closed meanwhile: back in the clipbase, unsaved)
  set ouverte 0
  catch {set ouverte [sc_base inUse $base]}
  if {!$ouverte} {
    set base [sc_info clipbase]
    sc_game park rebase $p $base 0
  }
  set parque($actif) [sc_game park]
  if {$base != [sc_base current]} { sc_base switch $base }
  set deplace [sc_game park restore $p]
  unset parque($t)
  set actif $t
  # (the database's own game had unsaved changes: kept in a new tab)
  if {$deplace ne {}} {
    variable suivant
    set n t$suivant
    incr suivant
    lappend onglets $n
    set parque($n) $deplace
  }
  updateBoard -pgn -switch
  catch {refreshWindows all}
  dessiner
}

### Closes tab t (asks first if its game has unsaved changes)
proc ::moderne::onglets::fermer {t} {
  variable onglets
  variable actif
  variable parque
  if {[llength $onglets] < 2} { return }
  if {$t ne $actif} {
    set info [sc_game park info $parque($t)]
    if {[lindex $info 2]} {
      # (unsaved changes: shown first, so the question is about the game on the board)
      activer $t
      if {$actif ne $t} { return }
    } else {
      sc_game park drop $parque($t)
      unset parque($t)
      set i [lsearch -exact $onglets $t]
      set onglets [lreplace $onglets $i $i]
      dessiner
      return
    }
  }
  set r [occupe]
  if {$r ne {}} { refuser $r ; return }
  set confirm [::game::ConfirmDiscard]
  if {$confirm == 2} { return }
  if {$confirm == 0} { ::game::Save }
  # the tab next to it comes on the board
  set i [lsearch -exact $onglets $t]
  set voisin [lindex $onglets [expr {$i + 1 < [llength $onglets] ? $i + 1 : $i - 1}]]
  sc_game setaltered 0
  activer $voisin
  if {$actif ne $voisin} { return }
  sc_game park drop $parque($t)
  unset parque($t)
  set i [lsearch -exact $onglets $t]
  set onglets [lreplace $onglets $i $i]
  dessiner
}

proc ::moderne::onglets::fermerAutres {t} {
  variable onglets
  activer $t
  foreach o $onglets { if {$o ne $t} { fermer $o } }
}

### Title of a game: the players' surnames, or "New game"
proc ::moderne::onglets::nom {s} {
  set s [string trim $s]
  if {$s in {{} ?}} { return {} }
  # (surname first in databases: "Carlsen, Magnus")
  set s [lindex [split $s ,] 0]
  if {[string length $s] > 14} { set s "[string range $s 0 12]…" }
  return $s
}

proc ::moderne::onglets::titre {t} {
  variable actif
  variable parque
  if {$t eq $actif} {
    set b [sc_game info white] ; set n [sc_game info black]
    set modif [sc_game altered]
    set vide [expr {[sc_game info halfmoves] == 0}]
  } else {
    lassign [sc_game park info $parque($t)] - - modif b n
    set vide 0
  }
  set b [nom $b] ; set n [nom $n]
  if {$b eq {} && $n eq {}} {
    set x [T "Nouvelle partie" "New game"]
  } else {
    if {$b eq {}} { set b ? }
    if {$n eq {}} { set n ? }
    set x "$b – $n"
  }
  if {$modif} { append x " •" }
  return $x
}

### Quitting: the unsaved games of the other tabs are listed too (as the
### active games of the databases, clipbase aside)
proc ::moderne::onglets::nonEnregistres {msgVar countVar} {
  upvar $msgVar msg $countVar n
  variable parque
  foreach t [array names parque] {
    lassign [sc_game park info $parque($t)] b g modif
    if {!$modif || $b == [sc_info clipbase] || ![sc_base inUse $b]} { continue }
    set lecture 1
    catch {set lecture [sc_base isReadOnly $b]}
    if {$lecture} { continue }
    set fname [file tail [sc_base filename $b]]
    if {$fname eq "Siby live"} { continue }
    if {$n == 0} { append msg "[T "Parties non enregistrées :" "Games not saved:"]\n\n" }
    incr n
    append msg "•  [titre $t]  ($fname, [T onglet tab])\n"
  }
}

### Quitting with "Save and exit": the unsaved game of every tab and of every
### database is saved (in its database, a new game added there), PGN files
### rewritten at once. Returns an error text, empty if all went well.
proc ::moderne::onglets::toutEnregistrer {} {
  variable onglets
  variable actif
  variable parque
  set erreurs {}
  # the active tab's game first (it is set aside when another tab comes)
  if {[sc_game altered] && ![sc_base isReadOnly] && [sc_base current] != [sc_info clipbase]} {
    if {[catch {sc_game save [sc_game number]} e]} { lappend erreurs $e }
  }
  # the other tabs, one after the other on the board
  foreach t $onglets {
    if {$t eq $actif || ![info exists parque($t)]} { continue }
    lassign [sc_game park info $parque($t)] b g modif
    if {!$modif || $b == [sc_info clipbase]} { continue }
    activer $t
    if {[sc_game altered] && ![sc_base isReadOnly]} {
      if {[catch {sc_game save [sc_game number]} e]} { lappend erreurs $e }
    }
  }
  # the game of each database (the active tab's among them)
  set courante [sc_base current]
  for {set i 1} {$i < [sc_base count total]} {incr i} {
    if {$i == [sc_info clipbase] || [catch {sc_base switch $i}]} { continue }
    if {[sc_base inUse] && [sc_game altered] && ![sc_base isReadOnly]} {
      if {[catch {sc_game save [sc_game number]} e]} { lappend erreurs $e }
    }
  }
  catch {sc_base switch $courante}
  # (PGN files are rewritten "after idle": now, before quitting)
  update idletasks
  return [join $erreurs \n]
}

################################################################################
### The tab bar, above the notation
################################################################################

proc ::moderne::onglets::dessiner {} {
  variable onglets
  variable actif
  variable titres
  set w .pgnWin
  if {![winfo exists $w.text]} { return }
  # (one row of tabs that scrolls sideways when they do not all fit: the
  # wheel over them, or the arrows; the active tab always shown)
  set barre $w.onglets
  if {![winfo exists $barre]} {
    frame $barre -height 28 -background [::moderne::c fond]
    pack $barre -side top -fill x -before $w.text
    pack propagate $barre 0
    frame $barre.vue -background [::moderne::c fond]
    pack $barre.vue -side left -fill both -expand 1
    foreach {n s d} {g ‹ -150 d › 150} {
      label $barre.$n -text $s -background [::moderne::c fond] -foreground [::moderne::c texteDoux] -padx 6 -font font_Bold
      bind $barre.$n <ButtonPress-1> [list ::moderne::onglets::defiler $d]
      bind $barre.$n <Enter> {%W configure -foreground [::moderne::c texteFort]}
      bind $barre.$n <Leave> {%W configure -foreground [::moderne::c texteDoux]}
    }
    bind $barre.vue <Configure> {::moderne::onglets::voirActif}
  }
  set f $barre.vue.in
  catch {destroy $f}
  frame $f -background [::moderne::c fond]
  variable decalage
  if {![info exists decalage]} { set decalage 0 }
  place $f -in $barre.vue -x [expr {-$decalage}] -y 0 -relheight 1
  array unset titres
  set k 0
  foreach t $onglets {
    set o [frame $f.o$k -background [expr {$t eq $actif ? [::moderne::c surface2] : [::moderne::c fond]}]]
    set fg [expr {$t eq $actif ? [::moderne::c texteFort] : [::moderne::c texteDoux]}]
    label $o.l -text [titre $t] -background [$o cget -background] -foreground $fg -padx 8 -pady 4
    set titres($t) [$o.l cget -text]
    pack $o.l -side left
    if {[llength $onglets] > 1} {
      label $o.x -text × -background [$o cget -background] -foreground [::moderne::c texteDoux] -padx 4
      pack $o.x -side left -padx {0 4}
      bind $o.x <Enter> [list $o.x configure -foreground [::moderne::c texteFort]]
      bind $o.x <Leave> [list $o.x configure -foreground [::moderne::c texteDoux]]
      bind $o.x <ButtonRelease-1> [list after idle [list ::moderne::onglets::fermer $t]]
      catch {::utils::tooltip::Set $o.x [T "Fermer l'onglet (Ctrl+W, clic du milieu)" "Close the tab (Ctrl+W, middle click)"]}
    }
    # (a line under the active tab, as in the dock tabs)
    if {$t eq $actif} {
      frame $o.trait -height 2 -background [::moderne::c accent]
      place $o.trait -relx 0 -rely 1 -relwidth 1 -anchor sw
    }
    foreach x [list $o $o.l] {
      # (dragged along the tabs: the tab moves there, Yosha 2026-11-07)
      bind $x <ButtonPress-1> [list ::moderne::onglets::appui $t %X]
      bind $x <B1-Motion> [list ::moderne::onglets::glisser $t %X]
      bind $x <ButtonRelease-1> [list ::moderne::onglets::lacher $t]
      bind $x <ButtonRelease-2> [list after idle [list ::moderne::onglets::fermer $t]]
      bind $x <Button-3> [list ::moderne::onglets::menu $t %X %Y]
    }
    pack $o -side left -padx {0 1}
    incr k
  }
  label $f.plus -text + -background [::moderne::c fond] -foreground [::moderne::c texteDoux] -padx 8 -pady 2 -font font_Bold
  bind $f.plus <ButtonRelease-1> {after idle ::moderne::onglets::nouveau}
  bind $f.plus <Enter> {%W configure -foreground [::moderne::c texteFort]}
  bind $f.plus <Leave> {%W configure -foreground [::moderne::c texteDoux]}
  catch {::utils::tooltip::Set $f.plus [T "Nouvelle partie dans un nouvel onglet (Ctrl+N)" "New game in a new tab (Ctrl+N)"]}
  pack $f.plus -side left
  # the wheel over the tabs scrolls them
  foreach x [concat [list $barre $barre.vue $f] [winfo children $f] [lmap c [winfo children $f] {winfo children $c}]] {
    foreach x2 $x {
      bind $x2 <MouseWheel> {::moderne::onglets::defiler [expr {%D > 0 ? -80 : 80}]}
      bind $x2 <Shift-MouseWheel> {::moderne::onglets::defiler [expr {%D > 0 ? -80 : 80}]}
      bind $x2 <Button-4> {::moderne::onglets::defiler -80}
      bind $x2 <Button-5> {::moderne::onglets::defiler 80}
    }
  }
  after cancel ::moderne::onglets::ajuster
  after idle ::moderne::onglets::ajuster
}

### Once drawn: the bar as high as the tabs, the active one in view
proc ::moderne::onglets::ajuster {} {
  set f .pgnWin.onglets.vue.in
  if {![winfo exists $f]} { return }
  # (once the tabs have their sizes: their frame's <Configure>; a forced
  # "update idletasks" here cost 0.33 s at startup)
  # (only a change of width: scrolling moves the frame too, and must not
  # bring the active tab back)
  bind $f <Configure> {after idle [list ::moderne::onglets::ajusterApres %w]}
  ajusterApres
}
proc ::moderne::onglets::ajusterApres {{largeur {}}} {
  variable largeurVue
  set f .pgnWin.onglets.vue.in
  if {![winfo exists $f]} { return }
  set h [winfo reqheight $f]
  if {$h > 1 && [.pgnWin.onglets cget -height] != $h} { .pgnWin.onglets configure -height $h }
  if {$largeur ne {}} {
    if {[info exists largeurVue] && $largeurVue == $largeur} { return }
    set largeurVue $largeur
  }
  voirActif
}

### Tabs scrolled by d pixels (0: only kept within bounds), the arrows
### shown when the tabs do not all fit
proc ::moderne::onglets::defiler {d} {
  variable decalage
  set barre .pgnWin.onglets
  set f $barre.vue.in
  if {![winfo exists $f]} { return }
  if {![info exists decalage]} { set decalage 0 }
  set large [winfo reqwidth $f]
  set vue [winfo width $barre.vue]
  set trop [expr {$vue > 1 && $large > $vue + ([winfo ismapped $barre.g] ? [winfo width $barre.g] + [winfo width $barre.d] : 0)}]
  if {$trop && ![winfo ismapped $barre.g]} {
    pack $barre.d $barre.g -side right -before $barre.vue
    update idletasks
    set vue [winfo width $barre.vue]
  } elseif {!$trop && [winfo ismapped $barre.g]} {
    pack forget $barre.g $barre.d
    update idletasks
    set vue [winfo width $barre.vue]
  }
  set max [expr {max(0, $large - $vue)}]
  set decalage [expr {max(0, min($max, $decalage + $d))}]
  place configure $f -x [expr {-$decalage}]
}

### The active tab in view
proc ::moderne::onglets::voirActif {} {
  variable onglets
  variable actif
  variable decalage
  set f .pgnWin.onglets.vue.in
  set o $f.o[lsearch -exact $onglets $actif]
  if {![winfo exists $o]} { defiler 0 ; return }
  defiler 0
  set vue [winfo width .pgnWin.onglets.vue]
  set x0 [winfo x $o] ; set x1 [expr {$x0 + [winfo reqwidth $o]}]
  # (the last tab: the "+" after it shown too)
  if {$actif eq [lindex $onglets end]} { set x1 [winfo reqwidth $f] }
  if {$x0 < $decalage} {
    defiler [expr {$x0 - $decalage}]
  } elseif {$vue > 1 && $x1 > $decalage + $vue} {
    defiler [expr {$x1 - $decalage - $vue}]
  }
}

### Moving a tab by dragging it: the tabs make room while it is dragged,
### the new order is kept when it is dropped; a click without a drag
### still opens the tab
proc ::moderne::onglets::appui {t X} {
  variable glisse [list $t $X 0]
}
proc ::moderne::onglets::glisser {t X} {
  variable glisse
  variable onglets
  if {![info exists glisse] || [lindex $glisse 0] ne $t} { return }
  lassign $glisse - x0 parti
  if {!$parti && abs($X - $x0) < 10} { return }
  lset glisse 2 1
  set f .pgnWin.onglets.vue.in
  # the frames in their order on screen, without the dragged one
  set cadres {}
  foreach c [pack slaves $f] { if {[string match $f.o* $c]} { lappend cadres $c } }
  set moi $f.o[lsearch -exact $onglets $t]
  if {![winfo exists $moi]} { return }
  set autres [lsearch -all -inline -not -exact $cadres $moi]
  set avant {}
  foreach c $autres {
    if {$X < [winfo rootx $c] + [winfo width $c] / 2} { set avant $c ; break }
  }
  if {$avant ne {}} {
    pack $moi -before $avant
  } else {
    pack $moi -before $f.plus
  }
}
proc ::moderne::onglets::lacher {t} {
  variable glisse
  variable onglets
  set parti 0
  if {[info exists glisse] && [lindex $glisse 0] eq $t} { set parti [lindex $glisse 2] }
  set glisse {}
  if {!$parti} { after idle [list ::moderne::onglets::activer $t] ; return }
  # the new order: that of the frames on screen
  set f .pgnWin.onglets.vue.in
  set ordre {}
  foreach c [pack slaves $f] {
    if {[string match $f.o* $c]} { lappend ordre [lindex $onglets [string range $c [string length $f.o] end]] }
  }
  if {[llength $ordre] == [llength $onglets]} { set onglets $ordre }
  after idle ::moderne::onglets::dessiner
  catch ::moderne::reprise::ecrire
}

### Title of the active tab after each change on the board (cheap: only
### when it changed)
proc ::moderne::onglets::maj {args} {
  variable actif
  variable titres
  set f .pgnWin.onglets
  if {![winfo exists $f]} { after idle ::moderne::onglets::dessiner ; return }
  set x [titre $actif]
  if {[info exists titres($actif)] && $titres($actif) eq $x} { return }
  dessiner
}

proc ::moderne::onglets::menu {t X Y} {
  set m .pgnWin.ongletsMenu
  catch {destroy $m}
  ::menu $m -tearoff 0
  $m add command -label [T "Nouvel onglet" "New tab"] -accelerator Ctrl+N -command ::moderne::onglets::nouveau
  $m add separator
  $m add command -label [T "Fermer" "Close"] -accelerator Ctrl+W -command [list ::moderne::onglets::fermer $t]
  $m add command -label [T "Fermer les autres onglets" "Close the other tabs"] -command [list ::moderne::onglets::fermerAutres $t]
  variable onglets
  if {[llength $onglets] < 2} {
    $m entryconfigure 2 -state disabled
    $m entryconfigure 3 -state disabled
  }
  catch {::moderne::repeindre $m}
  tk_popup $m $X $Y
}

proc ::moderne::onglets::init {{n 0}} {
  if {$n == 0} { trace add execution updateBoard leave ::moderne::onglets::maj }
  # (the notation may be built a little later)
  if {![winfo exists .pgnWin.text] && $n < 40} {
    after 250 [list ::moderne::onglets::init [incr n]]
    return
  }
  dessiner
}

after idle {after idle ::moderne::onglets::init}

################################################################################
### Never losing a game (Yosha 2026-11-05): every 5 s the games of the tabs
### that would be lost (changed and not saved, or new with moves) are
### written to reprise/session.txt in Siby's folder; quitting normally
### deletes it. At the next start after a crash or "Quit Siby", Siby offers
### to bring them back, each in its tab, in its database when it is open.
################################################################################

namespace eval ::moderne::reprise {
  variable derniere {}     ;# what was written last (written again only if changed)
  variable cache           ;# cache(parked id) = its entry (a parked game does not change)
  array set cache {}
  variable active 1        ;# 0 while quitting
}

proc ::moderne::reprise::fichier {} { file join $::scidUserDir reprise session.txt }

### Entry of a game: {titre base numero modifie pgn emplacement}
proc ::moderne::reprise::entree {titre b numero modifie pgn {loc {}}} {
  set f {}
  catch {if {$b != [sc_info clipbase]} { set f [file normalize [sc_base filename $b]] }}
  return [list titre $titre base $f numero $numero modifie $modifie pgn $pgn emplacement $loc]
}

### The games that would be lost, one entry each
proc ::moderne::reprise::entrees {} {
  variable cache
  set l {}
  set actif $::moderne::onglets::actif
  foreach t $::moderne::onglets::onglets {
    if {$t eq $actif} {
      set b [sc_base current]
      set coups [sc_game info halfmoves]
      set modif [sc_game altered]
      if {!$modif && !($b == [sc_info clipbase] && $coups > 0)} { continue }
      set pgn [::moderne::pgnAnglais -width 80]
      lappend l [entree [::moderne::onglets::titre $t] $b [sc_game number] $modif $pgn [sc_pos location]]
    } elseif {[info exists ::moderne::onglets::parque($t)]} {
      set p $::moderne::onglets::parque($t)
      lassign [sc_game park info $p] b numero modif
      if {!$modif && !($b == [sc_info clipbase])} { continue }
      if {![info exists cache($p)]} {
        set pgn [sc_game park pgn $p]
        # (an empty new game kept in its tab: nothing to keep)
        if {!$modif && ![regexp {\m1\.} $pgn]} { set cache($p) {} } else {
          set cache($p) [entree [::moderne::onglets::titre $t] $b $numero $modif $pgn]
        }
      }
      if {$cache($p) ne {}} { lappend l $cache($p) }
    }
  }
  return $l
}

proc ::moderne::reprise::ecrire {} {
  variable derniere
  variable active
  if {!$active} { return }
  set l {}
  if {[catch {set l [entrees]} err]} { return }
  if {$l eq $derniere} { return }
  set f [fichier]
  # (written by a thread, in the order asked: the file's opening and
  # renaming froze the window 0.7 to 1 s on Windows, after each move;
  # 2026-11-06)
  if {[llength [info commands sc_ecrire_fond]]} {
    if {![catch {
      if {![llength $l]} {
        sc_ecrire_fond supprimer $f
      } else {
        # (the folder made once: "file mkdir" took 0.1 s on Windows)
        variable dossierFait
        if {![info exists dossierFait]} { file mkdir [file dirname $f] ; set dossierFait 1 }
        sc_ecrire_fond remplacer $f "$l\n"
      }
    }]} { set derniere $l ; return }
  }
  catch {
    if {![llength $l]} {
      file delete $f
    } else {
      file mkdir [file dirname $f]
      set c [open $f.tmp w] ; fconfigure $c -encoding utf-8
      puts $c $l
      close $c
      file rename -force $f.tmp $f
    }
    set derniere $l
  }
}

proc ::moderne::reprise::boucle {} {
  catch ::moderne::reprise::ecrire
  after 5000 ::moderne::reprise::boucle
}

### Quitting normally: nothing to bring back
proc ::moderne::reprise::quitter {} {
  variable active 0
  # (after the writings still waiting, in their order)
  if {[catch {sc_ecrire_fond supprimer [fichier]}]} { catch {file delete [fichier]} }
}

### At the start: the games of last time offered back
proc ::moderne::reprise::proposer {} {
  # (answered, or nothing to offer: the other start questions may come,
  # e.g. a database to check; one on top of the other, the first one's
  # buttons waited for the check's end, Yosha 2026-11-09)
  variable fini
  set f [fichier]
  if {![file exists $f]} { set fini 1 ; boucle ; return }
  set l {}
  catch {set c [open $f] ; fconfigure $c -encoding utf-8 ; set l [read $c] ; close $c}
  # (kept aside whatever the answer: one never knows)
  catch {file rename -force $f [file join [file dirname $f] precedente.txt]}
  if {[catch {llength $l}] || ![llength $l]} { set fini 1 ; boucle ; return }
  set titres [join [lmap e $l {dict get $e titre}] \n]
  set r [tk_messageBox -parent . -icon question -title Siby -default reprendre \
      -boutons [list reprendre [T "Reprendre" "Restore"] no [T "Non" "No"]] \
      -message [T "Reprendre les parties non enregistrées de la dernière fois ?" "Restore the unsaved games of last time?"] \
      -detail $titres]
  if {$r eq "reprendre"} {
    foreach e $l { catch {restaurer $e} err ; if {$err ne {}} { catch {::moderne::rapport::journal "Siby reprise: $err"} } }
  }
  set fini 1
  boucle
}

proc ::moderne::reprise::T {fr en} { return [::moderne::tr $fr $en] }

### One game back, in a new tab (the empty tab of the start is reused)
proc ::moderne::reprise::restaurer {e} {
  set vide [expr {[sc_game info halfmoves] == 0 && ![sc_game altered] && [sc_game number] == 0}]
  if {!$vide} { if {![::moderne::onglets::nouveau {}]} { return } }
  # its database, when open now
  set b [sc_info clipbase]
  set f [dict get $e base]
  if {$f ne {}} {
    for {set i 1} {$i <= [sc_base count total]} {incr i} {
      if {[sc_base inUse $i] && ![catch {file normalize [sc_base filename $i]} n] && $n eq $f} { set b $i ; break }
    }
  }
  if {$b != [sc_base current]} { sc_base switch $b }
  sc_game new
  sc_game import [dict get $e pgn]
  set numero [dict get $e numero]
  if {$b != [sc_info clipbase] && $numero > 0} {
    # (as its game in the database, changed: saving replaces it)
    set p [sc_game park]
    sc_game park rebase $p $b $numero
    sc_game park restore $p
  }
  sc_game setaltered 1
  sc_move end
  set loc [dict get $e emplacement]
  if {$loc ne {}} { catch {sc_move pgn $loc} }
  updateBoard -pgn
  catch ::moderne::onglets::dessiner
}

# (after the tabs and the windows of the start)
after idle {after 1500 {catch ::moderne::reprise::proposer}}

### End Siby

################################################################################
### The game stays on the board when another database is opened (Yosha
### 2026-11-02: "the game still belongs to its database, one just looks at
### the position in another one"). Opening or switching to a database from
### My databases or File › Open carries the game along: it is parked out
### of its database and shown in the new one's slot, remembering where it
### comes from (origine). Ctrl+S saves it in its own database, going back
### to it does too, and so does quitting; loading another game in the
### browsed database first puts it back home (asking to save it there if
### it was changed).
################################################################################

namespace eval ::moderne::onglets {
  variable origine          ;# origine(base) = {home base, number, tags}
  array set origine {}
}

### What identifies the carried game (its number is 0 where it is shown)
proc ::moderne::onglets::empreinte {} {
  set l {}
  foreach t {White Black Event Date Round} { lappend l [sc_game tags get $t] }
  return $l
}

### The carried game shown in the current database: {home number}, or {}
proc ::moderne::onglets::porte {} {
  variable origine
  set b [sc_base current]
  if {![info exists origine($b)]} { return {} }
  lassign $origine($b) o n e
  set ok 0
  catch {set ok [expr {[sc_game number] == 0 && [sc_base inUse $o] && [empreinte] eq $e}]}
  if {!$ok} { unset origine($b) ; return {} }
  return [list $o $n]
}

### Runs script (opening or switching to a database), keeping the game on
### the board
proc ::moderne::onglets::enGardant {script} {
  set a [sc_base current]
  set code [catch {uplevel 1 $script} r]
  set b [sc_base current]
  if {$a != $b} { catch {porter $a $b} err }
  return -code $code $r
}

### The game of database a, shown in database b (the current one)
proc ::moderne::onglets::porter {a b} {
  variable origine
  if {![sc_base inUse $a] || [catch {occupe} r] || $r ne {}} { return }
  catch {setTrialMode 0}
  sc_base switch $a
  # (already a carried game: it keeps its home)
  set home [porte]
  if {$home ne {}} {
    unset origine($a)
  } else {
    set home [list $a [sc_game number]]
  }
  # (nothing worth keeping: an empty new game)
  if {[sc_game number] == 0 && [sc_game info halfmoves] == 0 && ![sc_game altered] &&
      [lindex [sc_game startBoard] 0] eq {}} {
    sc_base switch $b
    return
  }
  set e [empreinte]
  set id [sc_game park]
  sc_game park rebase $id $b 0
  sc_base switch $b
  set deplace [sc_game park restore $id]
  # (the database's own game had unsaved changes: kept in a new tab)
  if {$deplace ne {}} {
    variable onglets
    variable parque
    variable suivant
    set t t$suivant
    incr suivant
    lappend onglets $t
    set parque($t) $deplace
  }
  set origine($b) [concat $home [list $e]]
  journal "carried: [lindex $home 0]/[lindex $home 1] shown in $b"
  updateBoard -pgn
  catch {refreshWindows all}
  catch dessiner
}

### The carried game goes back to its database, which becomes the current
### one. Returns {home number} if there was one.
proc ::moderne::onglets::rapatrier {} {
  variable origine
  set p [porte]
  if {$p eq {}} { return {} }
  lassign $p o n
  set b [sc_base current]
  unset origine($b)
  set id [sc_game park]
  sc_game park rebase $id $o $n
  sc_base switch $o
  set deplace [sc_game park restore $id]
  if {$deplace ne {}} { catch {sc_game park drop $deplace} }
  journal "back home: $o/$n (from $b)"
  return $p
}

### Every carried game back home (before quitting)
proc ::moderne::onglets::rapatrierTout {} {
  variable origine
  set courante [sc_base current]
  foreach b [array names origine] {
    if {[catch {sc_base switch $b}]} { unset -nocomplain origine($b) ; continue }
    catch rapatrier
  }
  catch {sc_base switch $courante}
}

### Ctrl+S on a carried game: saved in its own database, then shown here
### again. Returns 1 if done.
proc ::moderne::onglets::enregistrerPorte {} {
  set b [sc_base current]
  set p [rapatrier]
  if {$p eq {}} { return 0 }
  set o [lindex $p 0]
  catch {gameSaveSiby}
  catch {porter $o $b}
  return 1
}

### Another game is about to be loaded in the browsed database: the carried
### game goes home first (asking there to save it if it was changed).
### Returns {} when no game is carried, else ConfirmDiscard's answer.
proc ::moderne::onglets::confirmerPorte {} {
  set b [sc_base current]
  set p [rapatrier]
  if {$p eq {}} { return {} }
  lassign $p o n
  set r [::game::ConfirmDiscard]
  if {$r == 2} {
    catch {porter $o $b}
    return 2
  }
  if {$r == 0} {
    catch {::game::Save}
  } elseif {[sc_game altered]} {
    # (not saved: the game in its database is the saved one again)
    if {$n > 0} { catch {sc_game load $n} } else { catch {sc_game new} }
  }
  sc_base switch $b
  return 1
}
