
###
### Siby: ready-made layouts, everything in a single window
###
### Relies on the "docking" mode of SCID vs. PC (tcl/utils/win.tcl):
### each window is a tab of a block, blocks are separated by
### draggable bars; a tab moves from one block to another by
### drag and drop, or is detached (right-click on the tab).
###
### Windows › Layout:
###   - Preparation: board on the left, Stockfish and Leela below it;
###     on the right, preparation against a player (opening library following
###     the board, the player's moves, games, and reference games),
###     with the general opening library and the game (PGN) as tabs;
###   - Analysis: board and engines on the left; on the right the opening
###     library at the top and the game (PGN) at the bottom;
###   - Play: set automatically at the start of a game against an engine
###     (clocks above the notation);
### The resulting layout (and its mouse adjustments) is saved like
### the others with Options › Layout › Save.
###

namespace eval ::moderne::disposition {
  variable forces {}   ;# engines imposed by a view (live broadcasts)
  variable hautDroite 0.6  ;# share of the right column's upper block
  variable partGauche 0.47 ;# share of the left column (board, engines)
}

### Layouts saved by the user over the ready-made ones (Windows ›
### My layouts): ::docking::layout_save format, empty = the original
foreach _n {preparation analyse lab} {
  if {![info exists ::moderne::disposition::perso_$_n]} { set ::moderne::disposition::perso_$_n {} }
}
unset _n

proc ::moderne::disposition::T {fr en} { return [::moderne::tr $fr $en] }

### The user's version of layout nom, if any: applied, engines started
proc ::moderne::disposition::appliquerPerso {nom} {
  set d [set ::moderne::disposition::perso_$nom]
  if {$d eq {} || !$::docking::USE_DOCKING} { return 0 }
  set ::docking::layout_list(moderne_$nom) $d
  ::docking::layout_restore moderne_$nom
  # (its engines arrive paused: ▶ in each panel)
  after 1000 {catch ::moderne::biblio::suivre}
  return 1
}

proc ::moderne::disposition::libelle {nom} {
  switch -- $nom {
    preparation { return [T "préparation" "preparation"] }
    analyse     { return [T "analyse" "analysis"] }
    lab         { return Lab }
  }
  return $nom
}

### The current layout replaces layout nom (Windows › My layouts)
proc ::moderne::disposition::enregistrer {nom} {
  if {!$::docking::USE_DOCKING} { return }
  if {[catch {::docking::layout_save moderne_perso} ok] || !$ok} { return }
  set ::moderne::disposition::perso_$nom $::docking::layout_list(moderne_perso)
  catch {::moderne::nsb::annonce "[T "Disposition « [libelle $nom] » enregistrée : c'est maintenant la tienne" "Layout \"[libelle $nom]\" saved: it is now yours"]" -1}
  after 2500 {catch ::moderne::nsb::finAnnonce}
  catch {::options.write}
}

### Back to the ready-made layout nom
proc ::moderne::disposition::reinitialiser {nom} {
  set ::moderne::disposition::perso_$nom {}
  # (the Lab rebuilt even when on screen)
  if {$nom eq "lab"} {
    variable pageLab
    appliquer moderne_lab [descriptionLab $pageLab]
    return
  }
  $nom
}

proc ::moderne::disposition::menuPerso {m} {
  $m delete 0 end
  foreach nom {lab} {
    $m add command -label [T "Enregistrer la disposition actuelle comme « [libelle $nom] »" \
        "Save the current layout as \"[libelle $nom]\""] -command [list ::moderne::disposition::enregistrer $nom]
  }
  $m add separator
  foreach nom {lab} {
    $m add command -label [T "Revenir à la disposition « [libelle $nom] » d'origine" \
        "Back to the original \"[libelle $nom]\" layout"] -command [list ::moderne::disposition::reinitialiser $nom] \
        -state [expr {[set ::moderne::disposition::perso_$nom] eq {} ? "disabled" : "normal"}]
  }
}

### Engines on the F2 and F3 keys (Stockfish and Leela after detection)
proc ::moderne::disposition::moteurs {} {
  variable forces
  if {[llength $forces]} { return $forces }
  # the first two engines of the priority list (F2, F3…), leaving out the
  # old engines that came with SCID (Scidlet, Phalanx, Toga, Fruit) when
  # there are others
  catch {::moderne::moteurs::touches}
  set l {} ; set vieux {}
  foreach k {F2 F3 F4 F5 F6 F7 F8 F9} {
    if {![info exists ::engines($k)] || ![string is integer -strict $::engines($k)]} { continue }
    set n $::engines($k)
    if {$n < 0 || $n >= [llength $::engines(list)] || $n in $l || $n in $vieux} { continue }
    if {[regexp -nocase {^\s*(scidlet|phalanx|toga|fruit)} [lindex $::engines(list) $n 0]]} {
      lappend vieux $n
    } elseif {[llength $l] < 2} {
      lappend l $n
    }
  }
  foreach n $vieux { if {[llength $l] < 2} { lappend l $n } }
  if {![llength $l] && [llength $::engines(list)]} { set l 0 }
  return $l
}

### Builds the layout description (::docking::layout_save format)
###  droite: list of tabs of the right block;
###  droiteBas: tabs of a block below the previous one (empty: no block)
proc ::moderne::disposition::description {droite {droiteBas {}} {avecMoteurs 1} {colonneDroite {}}} {
  # Screen size (main window almost full screen)
  set W [expr {[winfo screenwidth .] - 40}]
  set H [expr {[winfo screenheight .] - 90}]
  set gauche [expr {int($W * $::moderne::disposition::partGauche)}]
  # Without engines below (play layout), the board has the whole height:
  # the left column as wide as it is high, so the board fills it
  if {!$avecMoteurs} {
    set gauche [expr {min(int($W * 0.6), max($gauche, $H - 40))}]
  }
  set hautPlateau [expr {int($H * 0.66)}]
  # Engines side by side below the board
  set mots [expr {$avecMoteurs ? [moteurs] : {}}]
  set blocMoteurs {}
  set i 2
  foreach n $mots {
    lappend blocMoteurs [list TNotebook .tb$i [list .fdockanalysisWin$n]]
    incr i
  }
  if {[llength $blocMoteurs] == 0} {
    set colonneGauche [list TNotebook .nb .fdockmain]
  } else {
    if {[llength $blocMoteurs] == 1} {
      set bas [lindex $blocMoteurs 0]
    } else {
      set bas [list TPanedwindow [concat [list [list .pw.pw0.pw1.pw2 horizontal [expr {$gauche / 2}]]] $blocMoteurs]]
    }
    set colonneGauche [list TPanedwindow [list [list .pw.pw0.pw1 vertical $hautPlateau] \
        [list TNotebook .nb .fdockmain] $bas]]
  }
  if {[llength $colonneDroite]} {
    # (given whole: the Lab block)
  } elseif {[llength $droiteBas]} {
    set colonneDroite [list TPanedwindow [list [list .pw.pw0.pw5 vertical [expr {int($H * $::moderne::disposition::hautDroite)}]] \
        [list TNotebook .tb6 $droite] [list TNotebook .tb7 $droiteBas]]]
  } else {
    set colonneDroite [list TNotebook .tb6 $droite]
  }
  set geom "${W}x${H}+10+10"
  return [list [list MainWindowGeometry $geom] \
      [list [list .pw vertical {}] [list TPanedwindow [list [list .pw.pw0 horizontal $gauche] $colonneGauche $colonneDroite]]]]
}

proc ::moderne::disposition::appliquer {nom description {avecMoteurs 1}} {
  if {!$::docking::USE_DOCKING} {
    tk_messageBox -type ok -icon info -title Siby -message [T \
        "Les dispositions demandent le mode « une seule fenêtre » : Options › Fenêtres › Docking, puis redémarrer Siby." \
        "Layouts need single-window (docking) mode: Options › Windows › Docking, then restart Siby."]
    return
  }
  set ::docking::layout_list($nom) $description
  ::docking::layout_restore $nom
  # (its engines arrive paused: ▶ in each panel; those already running
  # keep running)
  after 1000 {catch ::moderne::biblio::suivre}
  # engine panel heights adjusted right away (under the veil), without waiting
  # for their first analysis lines: the board no longer moves afterwards
  # (in a lambda: no global f / n left behind)
  after 300 [list apply {{} {
    foreach f [winfo children .] {
      if {[regexp {^\.analysisWin([0-9]+)$} $f -> n]} { catch {::moderne::moteur::ajusterHauteur $n} }
    }
    catch ::moderne::docks::egaliserMoteurs
  }}]
}

proc ::moderne::disposition::demarrer {n {essai 0}} {
  if {![winfo exists .analysisWin$n]} {
    # (its place is there, the engine is being made)
    if {[winfo exists .fdockattenteanalysisWin$n] && $essai < 600} {
      after 100 [list ::moderne::disposition::demarrer $n [incr essai]]
    }
    return
  }
  # (engine still loading, e.g. Toby's networks: started once it is ready)
  if {[info exists ::analysis(uci$n)] && $::analysis(uci$n) &&
      !$::analysis(uciok$n) && $essai < 600} {
    after 100 [list ::moderne::disposition::demarrer $n [incr essai]]
    return
  }
  if {![info exists ::analysis(analyzeMode$n)] || !$::analysis(analyzeMode$n)} {
    toggleEngineAnalysis $n
  }
}

### Siby: the Lab view (2026-11-01): board and engines on the left; on the
### right two big tabs, "Prepare against a player" and "Analysis" (opening
### library and tablebases above, notation, game list and my databases
### below), both built once: switching is instant (moderne/lab.tcl).
### ::moderne::disposition::pageLab: the page shown last.
if {![info exists ::moderne::disposition::pageLab]} { set ::moderne::disposition::pageLab analyse }

proc ::moderne::disposition::descriptionLab {page} {
  set H [expr {[winfo screenheight .] - 90}]
  set i [expr {$page eq "prepa" ? 0 : 1}]
  set droite [list TOnglets [list .pw.pw0.lab $i {prepa analyse}] \
      [list [list .pw.pw0.lab.p0 vertical {}] [list TNotebook .tb6 {.fdockprepaWin}]] \
      [list [list .pw.pw0.lab.p1 vertical [expr {int(($H - 50) * $::moderne::disposition::hautDroite)}]] \
          [list TNotebook .tb7 {.fdockbiblioWin .fdocktbWin}] \
          [list TNotebook .tb8 {.fdockpgnWin .fdockglistWin .fdockbasesListeWin}]]]
  return [description {} {} 1 $droite]
}

### The Lab block on screen (empty if not): neither My databases, a game
### being played, nor a broadcast
proc ::moderne::disposition::blocLab {} {
  if {![catch {::moderne::mesbases::enVue} v] && $v} { return {} }
  if {[winfo exists .serGameWin]} { return {} }
  if {[winfo exists .jeuCouvre] && [winfo ismapped .jeuCouvre]} { return {} }
  if {![catch {::moderne::direct::vueOuverte} v] && $v} { return {} }
  # (the broadcasts' list laid over it: under it, not on screen)
  if {![catch {::moderne::direct::enSuperposition} v] && $v} { return {} }
  if {![winfo exists .main.board] || ![winfo ismapped .main.board]} { return {} }
  foreach lab [::moderne::lab::blocs] {
    if {[winfo ismapped $lab]} { return $lab }
  }
  return {}
}

### Lab, page prepa or analyse (empty: the one shown last). Already on
### screen: only its page changes (instant)
proc ::moderne::disposition::lab {{page {}}} {
  variable pageLab
  if {$page eq {}} { set page $pageLab }
  # (My databases laid over the Lab: taken off, the Lab is there already)
  catch ::moderne::mesbases::retirerSuperposition
  catch ::moderne::direct::retirerSuperposition
  catch jeuRetirer
  set bloc [blocLab]
  if {$bloc ne {}} {
    ::moderne::lab::montrer $bloc $page
    return
  }
  set pageLab $page
  # (a view chosen before the window was shown at startup: My databases,
  # the startup view, does not replace it, see ::moderne::revelerFenetre)
  set ::moderne::disposition::choisie 1
  # (the reference database, Gaby, opened under the layout's veil: its
  # opening froze the screen 3 to 4 s before the veil came, Windows
  # 2026-11-03)
  set voile 0
  if {[::moderne::mesbases::referenceAOuvrir]} {
    set voile 1
    set avant $::moderne::docks::restaurations
    catch {::moderne::docks::voile 1}
    catch {update idletasks}
    # (not while Gaby is still read in the background: no waiting, it
    # comes by itself; 2026-11-06)
    catch {::moderne::mesbases::baseReference 0}
  }
  if {[appliquerPerso lab]} {
    after idle [list apply {{page} {
      foreach b [::moderne::lab::blocs] { ::moderne::lab::montrer $b $page }
    }} $page]
  } else {
    appliquer moderne_lab [descriptionLab $page]
  }
  # (no layout applied after all: the veil goes now)
  if {$voile && $::moderne::docks::restaurations == $avant} { catch {::moderne::docks::voile 0} }
}

### The Lab built again from scratch, on its current page (and the
### broadcast's view over it, if it was there): the rescue box's
### "Unblock" (Escape held), when the windows are in a bad state (Yosha
### 2026-11-11: the board over the whole window, the game panel half off).
### Not during a game against an engine: its layout stays.
proc ::moderne::disposition::refaire {} {
  if {[winfo exists .serGameWin]} { return }
  variable pageLab
  set page $pageLab
  catch {
    set bloc [blocLab]
    if {$bloc ne {}} { set page [lindex [::moderne::lab::titres $bloc] [::moderne::lab::actif $bloc]] }
  }
  # (the broadcast's view laid over the Lab comes back afterwards)
  set direct {}
  catch {set direct $::moderne::direct::superpose}
  catch ::moderne::mesbases::retirerSuperposition
  catch ::moderne::direct::retirerSuperposition
  catch jeuRetirer
  if {[appliquerPerso lab]} {
    after idle [list apply {{page} {
      foreach b [::moderne::lab::blocs] { catch {::moderne::lab::montrer $b $page} }
    }} $page]
  } else {
    appliquer moderne_lab [descriptionLab $page]
  }
  switch -- $direct {
    partie { after 1500 {catch ::moderne::direct::vuePartie} }
    liste  { after 1500 {catch ::moderne::direct::vueListe} }
  }
}

### The left bar's Lab: nothing when it is already on screen (a click
### reloaded it, closing and reopening the panels; Yosha 2026-11-01)
proc ::moderne::disposition::aller {{nom {}}} {
  # (a finished game against an engine closed first)
  if {![catch {::moderne::jeu::fermerSiFinie [list ::moderne::disposition::aller $nom]} r] && $r} { return }
  if {$nom eq {} && [blocLab] ne {}} { return }
  switch -- $nom {
    analyse     { lab analyse }
    preparation { lab prepa }
    default     { lab }
  }
}

### Is the Lab on screen with page nom (analyse, preparation; lab: either)?
proc ::moderne::disposition::dejaLa {nom} {
  set bloc [blocLab]
  if {$bloc eq {}} { return 0 }
  set page [lindex [::moderne::lab::titres $bloc] [::moderne::lab::actif $bloc]]
  switch -- $nom {
    lab         { return 1 }
    preparation { return [expr {$page eq "prepa"}] }
    analyse     { return [expr {$page eq "analyse"}] }
  }
  return 0
}

### The former layouts: the Lab on that page
proc ::moderne::disposition::preparation {} { lab prepa }
proc ::moderne::disposition::analyse {} { lab analyse }

### Play (game against an engine, Toby, Phalanx): board on the left,
### play panel on the right (clocks, moves; notation as a tab); no analysis
### engine. Applied at the start of the game (before the opponent engine
### is launched: the layout closes the engine windows).
proc ::moderne::disposition::jeuAvant {} {
  if {![::moderne::actif] || !$::docking::USE_DOCKING} { return }
  # (a new game starting: the previous game's window, destroyed next, is not
  # the end of a game; its layout giving back ran in the middle of the new
  # game's window and Tk stopped Siby on Windows, Yosha 2026-11-09)
  variable demarrage 1
  catch {after cancel $::moderne::disposition::finDemarrage}
  variable finDemarrage [after 3000 {set ::moderne::disposition::demarrage 0}]
  # (rematch: the playing layout is already there)
  variable revanche
  if {[info exists revanche] && $revanche && [winfo exists .fdockpgnWin]} {
    set revanche 0
    return
  }
  # (a game just ended, its layout not yet given back: a new game starts
  # right away, e.g. an Alter Ego from the Play menu; the layout of before
  # the first game comes back after this one)
  variable jeuApresId
  variable jeuApresMoteurs
  variable avantJeu
  if {[info exists jeuApresId] && $jeuApresId ne {}} {
    after cancel $jeuApresId
    set jeuApresId {}
    set avantJeu $jeuApresMoteurs
  }
  # the layout and the engines analysing before the game come back after
  # it (jeuApres)
  set moteurs {}
  foreach w [winfo children .] {
    if {[regexp {^\.analysisWin([0-9]+)$} $w -> n] &&
        [info exists ::analysis(analyzeMode$n)] && $::analysis(analyzeMode$n)} { lappend moteurs $n }
  }
  # (the Lab on screen: the playing layout laid over it, nothing rebuilt,
  # see jeuSuperposer; a new game while it is there: nothing to do)
  variable jeuSup
  if {$jeuSup ne {}} {
    if {![info exists avantJeu]} { set avantJeu {} }
    return
  }
  if {![info exists avantJeu]} {
    if {![catch {jeuSuperposer $moteurs} ok] && $ok} {
      set avantJeu [lsort -integer $moteurs]
      return
    }
    if {$ok ne "0"} { catch {::moderne::journal "Partie (disposition posée sur le Lab) : $ok"} }
  }
  # (the covers' borrowed windows given back before the layout is rebuilt:
  # destroyed with a cover still holding them, Tk stopped Siby on Windows)
  catch ::moderne::direct::retirerSuperposition
  catch ::moderne::mesbases::retirerSuperposition
  if {![info exists avantJeu] && ![catch {::docking::layout_save avantJeu} ok] && $ok} {
    set avantJeu [lsort -integer $moteurs]
  }
  # (playing, like Lichess: a large board, the play panel on its right)
  set ::moderne::disposition::partGauche 0.66
  set d [description {.fdockpgnWin} {} 0]
  set ::moderne::disposition::partGauche 0.47
  appliquer moderne_jeu $d 0
}

### End of the game (its engine freed): the layout of before the game and
### its engines analysing again
proc ::moderne::disposition::jeuApres {} {
  variable avantJeu
  if {![info exists avantJeu]} { return 0 }
  # (a new game starting: the old window's end changes nothing)
  variable demarrage
  if {[info exists demarrage] && $demarrage} { return 1 }
  # (rematch: kept for after the next game)
  variable revanche
  if {[info exists revanche] && $revanche} { return 1 }
  set moteurs $avantJeu
  unset avantJeu
  # (the board the way it was before the games: after a game with Black,
  # the broadcasts came back upside down, Yosha 2026-11-11)
  variable sensAvantJeu
  if {[info exists sensAvantJeu]} {
    catch {::board::flip .main.board $sensAvantJeu}
    unset sensAvantJeu
  }
  # (the game ended because another layout is being chosen: that one wins)
  if {[info exists ::docking::enConstruction] && $::docking::enConstruction} { return 0 }
  variable jeuSup
  if {$jeuSup eq {} && (![info exists ::docking::layout_list(avantJeu)] || $::docking::layout_list(avantJeu) eq {})} { return 0 }
  # (just after: the game window may be in the middle of being destroyed,
  # and rebuilding the layout under it makes Tk crash)
  variable jeuApresId [after idle [list ::moderne::disposition::jeuApresSuite $moteurs]]
  variable jeuApresMoteurs $moteurs
  return 1
}

### The layout of before the game rebuilt right now (game stopped from a
### menu or a dialog, not while its window is being destroyed)
proc ::moderne::disposition::jeuApresMaintenant {} {
  variable jeuApresId
  variable jeuApresMoteurs
  if {![info exists jeuApresId] || $jeuApresId eq {}} { return }
  after cancel $jeuApresId
  set jeuApresId {}
  jeuApresSuite $jeuApresMoteurs
}

### The layout of before the game will not come back: another one was
### asked at the end of the game (analysis board, game review)
proc ::moderne::disposition::jeuApresAnnuler {} {
  variable jeuApresId
  variable avantJeu
  if {[info exists jeuApresId] && $jeuApresId ne {}} { after cancel $jeuApresId }
  set jeuApresId {}
  catch {unset avantJeu}
}

proc ::moderne::disposition::jeuApresSuite {moteurs} {
  variable jeuApresId {}
  if {[info exists ::docking::enConstruction] && $::docking::enConstruction} { return }
  # (laid over the Lab: taken off, the Lab and its engines as they were)
  variable jeuSup
  if {$jeuSup ne {}} {
    jeuRetirer $moteurs
    return
  }
  # the engines running before the game run again
  foreach n $moteurs { set ::moderne::docks::lancer($n) 1 }
  ::docking::layout_restore avantJeu
  foreach n $moteurs {
    after 800 [list catch [list ::moderne::disposition::demarrer $n]]
  }
}

### Siby (2026-11-06): the playing layout laid over the Lab instead of
### one of its own (1.5 to 2 s to build on Windows, Yosha: "under 1 s"):
### the engines' row is taken out of the left column, which widens to the
### board's height; a cover with the notation (lent by the Lab) hides the
### Lab's right side, and the game window goes next to the notation. The
### analysis engines pause (the opponent's own engine window is closed, as
### the layout did); after the game all comes back as it was.
###  jeuSup: {} or a dict of what to put back
if {![info exists ::moderne::disposition::jeuSup]} { set ::moderne::disposition::jeuSup {} }

proc ::moderne::disposition::jeuSuperposer {moteurs} {
  variable jeuSup
  if {$jeuSup ne {}} { return 1 }
  set lab [::moderne::direct::labDessous]
  if {$lab eq {}} { return 0 }
  if {![winfo exists .pw.pw0] || $lab ni [.pw.pw0 panes]} { return 0 }
  set col [lindex [.pw.pw0 panes] 0]
  if {$col eq $lab} { return 0 }
  # (the broadcast and My databases covers off first, the notation lent
  # to the preparation's tab back: BEFORE the notation's place is read; read
  # while lent to the broadcasts' cover, its place there was taken off
  # again after the cover had given it back ("not managed by
  # .directCouvre.pw.bas"), the layout then rebuilt over the cover's
  # windows, and Tk stopped Siby on Windows ("UpdateWrapper: Container was
  # destroyed"), Yosha 2026-11-09)
  catch ::moderne::direct::retirerSuperposition
  catch ::moderne::mesbases::retirerSuperposition
  catch ::moderne::prepa::rendreNotation
  # (the notation made if its page was not shown yet)
  catch {::moderne::lab::fabriquerPage [lindex [::moderne::lab::pages $lab] 1]}
  if {![winfo exists .fdockpgnWin]} { return 0 }
  set pnb [::docking::find_tbn .fdockpgnWin]
  if {$pnb eq {} || ![winfo exists $pnb]} { return 0 }
  # the engines' row of the left column (everything but the board's group)
  set rangs {}
  set onglets {}
  if {[winfo class $col] eq "TPanedwindow"} {
    set sashes {}
    for {set i 0} {$i < [llength [$col panes]] - 1} {incr i} { lappend sashes [$col sashpos $i] }
    foreach p [$col panes] {
      if {[winfo class $p] eq "TNotebook" && ".fdockmain" in [$p tabs]} { continue }
      lappend rangs [list $p [lsearch -exact [$col panes] $p]]
    }
  } else {
    set sashes {}
  }
  # (each engine's place: its group, the group's pane and rank; a paused
  # engine's placeholder too, which the opponent's engine removes)
  foreach f [winfo children .] {
    if {[regexp {^\.fdock(?:attente)?analysisWin([0-9]+)$} $f -> n] && [winfo manager $f] ne {}} {
      set nb [::docking::find_tbn $f]
      if {$nb eq {} || ![info exists ::docking::tbs($nb)]} { continue }
      set pw $::docking::tbs($nb)
      lappend onglets [list $n $nb $pw [lsearch -exact [$pw panes] $nb]]
    }
  }
  set jeuSup [dict create lab $lab col $col rangs $rangs sashes $sashes onglets $onglets \
      pnb $pnb pidx [$pnb index .fdockpgnWin] ptitre [$pnb tab .fdockpgnWin -text] \
      pchoisi [expr {[$pnb select] eq ".fdockpgnWin"}] sash0 [.pw.pw0 sashpos 0] \
      moteursCote [::moderne::docks::rangsMoteurs]]
  # the analysis paused (the opponent's engine window closed: it is going
  # to play with that engine)
  foreach n $moteurs { catch {toggleEngineAnalysis $n} }
  set code [catch {
    foreach x $rangs { $col forget [lindex $x 0] }
    set c .jeuCouvre
    catch {destroy $c}
    frame $c -background [::moderne::c fond] -borderwidth 0
    ttk::notebook $c.nb
    pack $c.nb -fill both -expand 1
    set ::docking::tbs($c.nb) $c
    $pnb forget .fdockpgnWin
    $c.nb add .fdockpgnWin -text [dict get $jeuSup ptitre]
    # (the Lab's pages hidden: the board widening would make them all lay
    # out again under the cover, 1.5 s on Windows)
    foreach p [::moderne::lab::pages $lab] { catch {grid remove $p} }
    place $c -in $lab -x 0 -y 0 -relwidth 1 -relheight 1
    raise $c
    raise .fdockpgnWin
    # (as the playing layout: the left column as wide as it is high, at
    # most 60 % of the window)
    set W [winfo width .pw]
    set H [winfo height .pw]
    .pw.pw0 sashpos 0 [expr {min(int($W * 0.6), max(int($W * 0.66), $H - 40))}]
    # (kept in the layout's sashes: a deferred restoreGeometry of the Lab's
    # build, still to come on Windows, put the Lab's back and the game
    # panel was drawn over the board, Yosha 2026-11-13)
    catch {::moderne::docks::retenirSash .pw.pw0 0}
    catch ::docking::setTabStatus
  } err]
  if {$code} { jeuRetirer $moteurs ; return -code error $err }
  return 1
}

### The cover taken off: the engines' row, the notation and the Lab's page
### back; the engines that ran before the game run again
proc ::moderne::disposition::jeuRetirer {{moteurs {}}} {
  variable jeuSup
  if {$jeuSup eq {}} { return 0 }
  set d $jeuSup
  set jeuSup {}
  set c .jeuCouvre
  catch {place forget $c}
  set lab [dict get $d lab]
  set col [dict get $d col]
  # the notation back in its group
  set pnb [dict get $d pnb]
  if {[winfo exists .fdockpgnWin] && [winfo exists $pnb]} {
    catch {[::docking::find_tbn .fdockpgnWin] forget .fdockpgnWin}
    catch {
      set i [dict get $d pidx]
      if {$i >= [llength [$pnb tabs]]} { $pnb add .fdockpgnWin -text [dict get $d ptitre] } else { $pnb insert $i .fdockpgnWin -text [dict get $d ptitre] }
      if {[dict get $d pchoisi]} { $pnb select .fdockpgnWin }
    }
  }
  # (whatever else was opened in the cover goes next to the notation)
  if {[winfo exists $c.nb]} {
    foreach t [$c.nb tabs] {
      set titre [$c.nb tab $t -text]
      catch {$c.nb forget $t}
      ::moderne::docks::rangerOnglet $t $titre [expr {[winfo exists $pnb] ? $pnb : {}}] .jeuCouvre
    }
  }
  catch {unset ::docking::tbs($c.nb)}
  catch {destroy $c}
  # the engines' row and the sashes
  if {[winfo exists $col]} {
    foreach x [dict get $d rangs] {
      lassign $x p i
      if {![winfo exists $p] || $p in [$col panes]} { continue }
      if {$i < 0 || $i >= [llength [$col panes]]} { catch {$col add $p -weight 1} } else { catch {$col insert $i $p -weight 1} }
    }
  }
  # (the sashes once the panes are back in place)
  after idle [list apply {{col sashes sash0} {
    catch {.pw.pw0 sashpos 0 $sash0}
    catch {::moderne::docks::retenirSash .pw.pw0 0}
    update idletasks
    set i 0
    foreach s $sashes { catch {$col sashpos $i $s} ; incr i }
  }} $col [dict get $d sashes] [dict get $d sash0]]
  # (the engines side by side as they were: the row taken out and put back
  # shared its width another way, Yosha 2026-11-09; again once the engines
  # have drawn their panels)
  if {[dict exists $d moteursCote]} {
    foreach t {idle 400 1500} {
      after $t [list catch [list ::moderne::docks::remettreRangs [dict get $d moteursCote]]]
    }
  }
  # an engine window or placeholder gone meanwhile (the opponent's) made
  # again in its group, the group too if it went with it
  foreach x [dict get $d onglets] {
    lassign $x n nb pw i
    if {[winfo exists .fdockanalysisWin$n] || [winfo exists .fdockattenteanalysisWin$n]} { continue }
    if {![winfo exists $nb]} {
      if {![winfo exists $pw]} { continue }
      catch {
        ttk::notebook $nb
        if {$i < 0 || $i >= [llength [$pw panes]]} { $pw add $nb -weight 1 } else { $pw insert $i $nb -weight 1 }
        set ::docking::tbs($nb) $pw
      }
    }
    if {![winfo exists $nb]} { continue }
    if {$n in $moteurs} {
      set ::docking::layout_dest_notebook $nb
      catch {makeAnalysisWin $n}
      set ::docking::layout_dest_notebook {}
    } else {
      catch {::moderne::docks::placeEnPause $nb .fdockanalysisWin$n $n}
    }
  }
  if {[winfo exists $lab]} { catch {::moderne::lab::montrer $lab [::moderne::lab::actif $lab]} }
  catch ::docking::setTabStatus
  foreach n $moteurs { after 300 [list catch [list ::moderne::disposition::demarrer $n]] }
  after idle {catch ::moderne::prepa::suivreNotation}
  return 1
}

### Creates the game window w (clocks, buttons) in a block above
### the notation. Returns 1 if it is embedded, 0 otherwise (separate window).
proc ::moderne::disposition::jeuFenetre {w} {
  if {![::moderne::actif] || !$::docking::USE_DOCKING} { toplevel $w ; return 0 }
  set f .fdock[string range $w 1 end]
  set nb {}
  if {[winfo exists .fdockpgnWin]} { set nb [::docking::find_tbn .fdockpgnWin] }
  # (under the cover, in it: never in the Lab's group the notation may have
  # gone back to meanwhile, drawn over the board, Yosha 2026-11-13)
  variable jeuSup
  if {$jeuSup ne {} && [winfo exists .jeuCouvre.nb]} { set nb .jeuCouvre.nb }
  if {$nb ne {}} { set ::docking::layout_dest_notebook $nb }
  set code [catch {::createToplevel $w} res]
  set ::docking::layout_dest_notebook {}
  if {$code} { return -code error $res }
  # in the same group as the notation, in front of it: the panel takes
  # the full height (clocks level with the top and bottom of the board)
  if {$nb ne {}} {
    catch {$nb select $f}
    # the moves are already written between the clocks: no Notation tab
    # during the game (it comes back with the layout of after the game)
    catch {$nb hide .fdockpgnWin}
    ::docking::setTabStatus
  }
  return 1
}

### End of the build: tab title, block height adjusted
proc ::moderne::disposition::jeuFini {w titre} {
  ::createToplevelFinalize $w
  catch {::setTitle $w $titre}
  update idletasks
}

### End Siby
