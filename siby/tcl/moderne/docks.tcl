
###
### Siby: moving "docked" windows with the mouse
###
### You grab a window's tab (engine, PGN, opening library…) and
### drop it on a tab group:
###   - in the center (or on the tab bar): it becomes a tab of that group;
###   - near an edge (top, bottom, left, right): it goes on that side,
###     in a new group (e.g. Stockfish below the board; a second
###     engine dropped on Stockfish's right edge goes next to it).
### While dragging, a frame shows where the window will go.
### (Right-clicking a tab keeps its Up / Down / Left /
### Right / Detach commands.)
###

namespace eval ::moderne::docks {
  variable depart {}     ;# {x y} of the press on the tab
  variable zone {}       ;# targeted {notebook anchor}: anchor = center | n | s | e | w
  variable actif 0       ;# the drag has started (more than a few pixels)
}

proc ::moderne::docks::gere {nb} {
  return [expr {$nb ne {} && [info exists ::docking::tbs($nb)] && [winfo exists $nb]}]
}

### Target zone under screen point (X, Y): {notebook anchor} or {}
proc ::moderne::docks::zoneSous {X Y} {
  set w [winfo containing $X $Y]
  if {$w eq {}} { return {} }
  # Window embedded in a tab ("-use" toplevel): its .fdock… frame
  set top [winfo toplevel $w]
  if {$top ne "." && [winfo exists .fdock[string range $top 1 end]]} {
    set w .fdock[string range $top 1 end]
  }
  set t [::docking::find_tbn $w]
  # (on the notebook itself or one of its tab frames)
  while {![gere $t] && $w ne "." && $w ne {}} {
    set w [winfo parent $w]
    set t [::docking::find_tbn $w]
  }
  if {![gere $t]} { return {} }
  set x [expr {$X - [winfo rootx $t]}]
  set y [expr {$Y - [winfo rooty $t]}]
  set L [winfo width $t]
  set H [winfo height $t]
  if {$L < 10 || $H < 10} { return {} }
  # On the tab bar: tab
  if {$y < 30} { return [list $t centre] }
  set rx [expr {double($x) / $L}]
  set ry [expr {double($y) / $H}]
  if {$rx > 0.3 && $rx < 0.7 && $ry > 0.3 && $ry < 0.7} { return [list $t centre] }
  # Nearest edge
  set d [list [list w $rx] [list e [expr {1.0 - $rx}]] [list n $ry] [list s [expr {1.0 - $ry}]]]
  return [list $t [lindex [lsort -real -index 1 $d] 0 0]]
}

### Frame showing the zone (4 strips, everywhere; translucent fill where
### the system allows it)
proc ::moderne::docks::montrer {t ancre} {
  set x [winfo rootx $t] ; set y [winfo rooty $t]
  set L [winfo width $t] ; set H [winfo height $t]
  switch $ancre {
    w { set L [expr {$L / 2}] }
    e { set x [expr {$x + $L / 2}] ; set L [expr {$L / 2}] }
    n { set H [expr {$H / 2}] }
    s { set y [expr {$y + $H / 2}] ; set H [expr {$H / 2}] }
  }
  set couleur #3d8bfd
  catch {set couleur [::moderne::c accent]}
  set e 4
  foreach {nom gx gy gl gh} [list h $x $y $L $e  b $x [expr {$y + $H - $e}] $L $e \
                                  g $x $y $e $H  d [expr {$x + $L - $e}] $y $e $H] {
    set f .dockZone$nom
    if {![winfo exists $f]} {
      toplevel $f -background $couleur -borderwidth 0
      wm overrideredirect $f 1
    }
    wm geometry $f ${gl}x${gh}+${gx}+${gy}
    wm deiconify $f
    raise $f
  }
  if {[tk windowingsystem] in {win32 aqua}} {
    set f .dockZonefond
    if {![winfo exists $f]} {
      toplevel $f -background $couleur
      wm overrideredirect $f 1
      catch {wm attributes $f -alpha 0.22}
    }
    wm geometry $f [expr {$L - 2 * $e}]x[expr {$H - 2 * $e}]+[expr {$x + $e}]+[expr {$y + $e}]
    wm deiconify $f
    raise $f
  }
}

proc ::moderne::docks::cacher {} {
  foreach nom {h b g d fond} {
    if {[winfo exists .dockZone$nom]} { wm withdraw .dockZone$nom }
  }
}

################################################################################
### Replacements for procedures of tcl/utils/win.tcl
################################################################################

proc ::moderne::docks::appui {path x y} {
  variable depart
  variable actif
  variable zone
  set depart [list [winfo pointerx .] [winfo pointery .]]
  set actif 0
  set zone {}
}

proc ::moderne::docks::glisser {path X Y} {
  variable depart
  variable actif
  variable zone
  ::docking::motion $path
  if {$::docking::c_path eq {} || ![gere $::docking::c_path]} { return }
  if {!$actif} {
    lassign $depart x0 y0
    if {$x0 eq {} || abs($X - $x0) + abs($Y - $y0) < 10} { return }
    set actif 1
  }
  set zone [zoneSous $X $Y]
  if {$zone eq {}} { cacher ; return }
  lassign $zone t ancre
  # A single-tab group cannot be placed next to itself
  if {$t eq $::docking::c_path && $ancre ne "centre" && [llength [$t tabs]] < 2} {
    set zone {}
    cacher
    return
  }
  montrer $t $ancre
}

proc ::moderne::docks::lacher {w X Y} {
  variable actif
  variable zone
  cacher
  # Tabs of a notebook inside a window (not a dock group): dragged along
  # the tabs, the tab moves there (Yosha 2026-11-07)
  if {$::docking::c_path eq {} && [winfo exists $w] && [winfo class $w] eq "TNotebook"} {
    bind TNotebook <ButtonRelease-1> [namespace code {::docking::show_menu %W %x %y}]
    reordonner $w $X $Y
    return
  }
  set z $zone
  set zone {}
  set etaitActif $actif
  set actif 0
  set src $::docking::c_path
  if {!$etaitActif || $z eq {} || $src eq {} || ![gere $src] || \
      ([lindex $z 1] eq "centre" && [lindex $z 0] eq $src)} {
    # Same group or simple click: original behavior (reorder the tabs)
    ::docking::end_motion_origine $w $X $Y
    return
  }
  lassign $z t ancre
  bind TNotebook <ButtonRelease-1> [namespace code {::docking::show_menu %W %x %y}]
  $src configure -cursor {}
  if {$ancre eq "centre"} {
    # Tab from another group (dropped anywhere on this group)
    if {$Y - [winfo rooty $t] < 30} {
      ::docking::move_tab $src $t $X $Y
    } else {
      ::docking::move_tab $src $t
    }
  } else {
    set nouveau [::docking::add_tbn $t $ancre]
    ::docking::move_tab $src $nouveau
    after idle [list ::moderne::docks::partager $t $nouveau]
  }
  set ::docking::c_path {}
  ::docking::setTabStatus
}

### The selected tab of notebook w moved to the tab under the pointer (a
### drag of at least 10 pixels, along the tabs)
proc ::moderne::docks::reordonner {w X Y} {
  variable depart
  lassign $depart x0 y0
  if {$x0 eq {} || abs($X - $x0) < 10} { return }
  set x [expr {$X - [winfo rootx $w]}] ; set y [expr {$Y - [winfo rooty $w]}]
  if {[catch {$w index @$x,$y} dest] || $dest eq {} || $dest < 0} { return }
  set t [$w select]
  if {$t eq {} || [$w index $t] == $dest} { return }
  catch {$w insert $dest $t}
}

### Splits the space equally between the target group and the new group
proc ::moderne::docks::partager {t nouveau} {
  if {![winfo exists $t] || ![winfo exists $nouveau]} { return }
  update idletasks
  set pw $::docking::tbs($nouveau)
  set panes [$pw panes]
  set i [lsearch -exact $panes $t]
  set j [lsearch -exact $panes $nouveau]
  if {$i < 0 || $j < 0 || abs($i - $j) != 1} { return }
  set k [expr {min($i, $j)}]
  set a [lindex $panes $k]
  set b [lindex $panes [expr {$k + 1}]]
  if {[$pw cget -orient] eq "vertical"} {
    set debut [expr {[winfo rooty $a] - [winfo rooty $pw]}]
    set fin [expr {[winfo rooty $b] - [winfo rooty $pw] + [winfo height $b]}]
  } else {
    set debut [expr {[winfo rootx $a] - [winfo rootx $pw]}]
    set fin [expr {[winfo rootx $b] - [winfo rootx $pw] + [winfo width $b]}]
  }
  catch {$pw sashpos $k [expr {($debut + $fin) / 2}]}
}

proc ::moderne::docks::installer {} {
  if {![llength [info commands ::docking::end_motion_origine]]} {
    rename ::docking::end_motion ::docking::end_motion_origine
    proc ::docking::end_motion {w x y} { ::moderne::docks::lacher $w $x $y }
  }
  bind TNotebook <ButtonPress-1> {+::moderne::docks::appui %W %x %y}
  bind TNotebook <B1-Motion> {
    ::moderne::docks::glisser %W %X %Y
    bind TNotebook <ButtonRelease-1> {::docking::end_motion %W %X %Y}
  }
  bind TNotebook <Escape> {+::moderne::docks::cacher}
  # a double click on a divider: its two neighbours 50-50 (Yosha 2026-11-09)
  bind TPanedwindow <Double-Button-1> {+::moderne::docks::moitieMoitie %W %x %y}
  # (safety: the frame never stays visible after a release)
  bind all <ButtonRelease-1> {+after 100 ::moderne::docks::cacher}
}

::moderne::docks::installer


################################################################################
### New engine (F2, F3…): next to the other engines, not as a tab
################################################################################

### Called at the end of makeAnalysisWin: if the window of engine n landed
### in a group that already contains an engine, it moves into a new
### group to the right of that one, and the space is split 50/50.
proc ::moderne::docks::moduleCoteACote {n} {
  variable restauration
  # (an engine closed: the others share its space)
  if {[winfo exists .fdockanalysisWin$n]} {
    bind .fdockanalysisWin$n <Destroy> {after 300 {catch ::moderne::docks::egaliserMoteurs}}
  }
  if {[info exists restauration] && $restauration} { return }
  # (made in the place a layout keeps for it: it stays there)
  if {[info exists ::docking::placeImposee] && $::docking::placeImposee > 0} { return }
  set f .fdockanalysisWin$n
  if {![winfo exists $f]} { return }
  set nb [::docking::find_tbn $f]
  if {![gere $nb]} { return }
  # (an engine paused, with its ▶ button, counts as an engine)
  set autres 0
  foreach t [$nb tabs] {
    if {$t ne $f && ([string match .fdockanalysisWin* $t] || [string match .fdockattenteanalysisWin* $t])} { incr autres }
  }
  if {!$autres} {
    # Engines open elsewhere?
    set ailleurs {}
    foreach c [winfo children .] {
      if {$c ne $f && ([string match .fdockanalysisWin* $c] || [string match .fdockattenteanalysisWin* $c])} {
        set t [::docking::find_tbn $c]
        if {$t ne {}} { set ailleurs $t }
      }
    }
    if {$ailleurs ne {}} {
      # to the right of the last engine
      $nb select $f
      set nouveau [::docking::add_tbn $ailleurs e]
      ::docking::move_tab $nb $nouveau
      ::docking::setTabStatus
      after idle [list ::moderne::docks::partager $ailleurs $nouveau]
      after idle [list catch [list ::moderne::docks::ordonnerMoteurs $nouveau]]
      after idle {catch ::moderne::docks::egaliserMoteurs}
      return
    }
    # First engine: below the board (not as a tab elsewhere)
    set plateau [::docking::find_tbn .fdockmain]
    if {$plateau eq {} || ![info exists ::docking::tbs($plateau)]} { return }
    set pw $::docking::tbs($plateau)
    if {[info exists ::docking::tbs($nb)] && $::docking::tbs($nb) eq $pw && [$pw cget -orient] eq "vertical"} {
      set panes [$pw panes]
      if {[lsearch -exact $panes $nb] == [lsearch -exact $panes $plateau] + 1 && [llength [$nb tabs]] == 1} { return }
    }
    $nb select $f
    set nouveau [::docking::add_tbn $plateau s]
    ::docking::move_tab $nb $nouveau
    ::docking::setTabStatus
    after 300 [list catch [list ::moderne::moteur::ajusterHauteur $n]]
    return
  }
  $nb select $f
  set nouveau [::docking::add_tbn $nb e]
  ::docking::move_tab $nb $nouveau
  ::docking::setTabStatus
  after idle [list ::moderne::docks::partager $nb $nouveau]
  after idle [list catch [list ::moderne::docks::ordonnerMoteurs $nouveau]]
  after idle {catch ::moderne::docks::egaliserMoteurs}
}

### Rank of engine n: its place in the list, which gives its key (the
### first engine F2, the second F3…)
proc ::moderne::docks::rangMoteur {n} { return $n }

### An engine added beside others: the engines' groups of that row in the
### order of their keys, F2 on the left (Yosha 2026-11-11: Stockfish, F2,
### came back on the right of Toby). Only when an engine is added: groups
### moved by hand stay where they are.
proc ::moderne::docks::ordonnerMoteurs {nb} {
  if {![winfo exists $nb] || ![info exists ::docking::tbs($nb)]} { return }
  set pw $::docking::tbs($nb)
  if {![winfo exists $pw] || [winfo class $pw] ne "TPanedwindow" || [$pw cget -orient] ne "horizontal"} { return }
  set panes [$pw panes]
  foreach p $panes { if {![estMoteur $p]} { return } }
  set rangs {}
  foreach p $panes {
    set r 99
    foreach t [$p tabs] {
      if {[regexp {analysisWin([0-9]+)$} $t -> n]} { set r [expr {min($r, [rangMoteur $n])}] }
    }
    lappend rangs [list $r $p]
  }
  set ordre [lmap x [lsort -integer -index 0 $rangs] {lindex $x 1}]
  if {$ordre eq $panes} { return }
  set i 0
  foreach p $ordre { $pw insert $i $p ; incr i }
}

### Engines side by side get the same width: 1/2 each for two, 1/3 for
### three… (also when one of them is closed)
### Double click at x y of paned window pw: on a divider, the two panes
### beside it get the same size
proc ::moderne::docks::moitieMoitie {pw x y} {
  if {[catch {$pw identify $x $y} k] || ![string is integer -strict $k]} { return }
  set panes [$pw panes]
  if {$k + 1 >= [llength $panes]} { return }
  set a [lindex $panes $k]
  set b [lindex $panes [expr {$k + 1}]]
  if {[$pw cget -orient] eq "vertical"} {
    set debut [expr {[winfo rooty $a] - [winfo rooty $pw]}]
    set fin [expr {[winfo rooty $b] - [winfo rooty $pw] + [winfo height $b]}]
  } else {
    set debut [expr {[winfo rootx $a] - [winfo rootx $pw]}]
    set fin [expr {[winfo rootx $b] - [winfo rootx $pw] + [winfo width $b]}]
  }
  catch {$pw sashpos $k [expr {($debut + $fin) / 2}]}
}

### The rows of engines side by side: {pw {fraction…}} (sash / width), to put
### them back as they were after the layout changed under them
proc ::moderne::docks::rangsMoteurs {{pw .pw}} {
  set res {}
  if {![winfo exists $pw] || [winfo class $pw] ne "TPanedwindow"} { return {} }
  foreach p [$pw panes] {
    if {[winfo class $p] eq "TPanedwindow"} { lappend res {*}[rangsMoteurs $p] }
  }
  if {[$pw cget -orient] ne "horizontal"} { return $res }
  set panes [$pw panes]
  if {[llength $panes] < 2} { return $res }
  foreach p $panes { if {![estMoteur $p]} { return $res } }
  set l [winfo width $pw]
  if {$l < 50} { return $res }
  set f {}
  for {set k 0} {$k < [llength $panes] - 1} {incr k} { lappend f [expr {double([$pw sashpos $k]) / $l}] }
  lappend res [list $pw $f]
  return $res
}

proc ::moderne::docks::remettreRangs {rangs} {
  update idletasks
  foreach r $rangs {
    lassign $r pw f
    if {![winfo exists $pw] || [llength [$pw panes]] != [llength $f] + 1} { continue }
    set l [winfo width $pw]
    if {$l < 50} { continue }
    # (twice: a sash cannot pass its neighbour)
    foreach passe {1 2} {
      set k 0
      foreach x $f { catch {$pw sashpos $k [expr {round($x * $l)}]} ; incr k }
    }
  }
}

proc ::moderne::docks::estMoteur {p} {
  if {[winfo class $p] ne "TNotebook"} { return 0 }
  set t [$p tabs]
  if {![llength $t]} { return 0 }
  foreach x $t { if {![string match .fdockanalysisWin* $x] && ![string match .fdockattenteanalysisWin* $x]} { return 0 } }
  return 1
}

################################################################################
### Engines paused by default (as on Lichess, where the engine runs only once
### switched on): a layout shows each engine's panel with a ▶ button; the
### engine process starts only on a click. Engines already running keep
### running across layout changes (their windows are kept).
################################################################################

namespace eval ::moderne::docks { variable lancer ; array set lancer {} }

### Engine n to start with the next layout (then forgotten)
proc ::moderne::docks::aLancer {n} {
  variable lancer
  if {[info exists lancer($n)]} { unset lancer($n) ; return 1 }
  return 0
}

proc ::moderne::docks::placeEnPause {nb d n} {
  set p .fdockattente[string range $d 6 end]
  # (kept from the previous layout: it would be destroyed at the end of this one)
  catch {unset ::docking::gardes($p)}
  catch {destroy $p}
  set nom [lindex [lindex $::engines(list) $n] 0]
  frame $p -background [::moderne::c fond] -cursor hand2
  set c [frame $p.c -background [::moderne::c fond]]
  label $c.nom -text $nom -font font_Bold -background [::moderne::c fond] -foreground [::moderne::c texte]
  ttk::button $c.go -text "▶  [::moderne::tr Analyser Analyse]" -command [list ::moderne::docks::lancerEnPause $n]
  catch {$c.go configure -style Accent.TButton}
  label $c.aide -text [::moderne::tr "En pause : clique pour lancer l'analyse" "Paused: click to start the analysis"] \
      -background [::moderne::c fond] -foreground [::moderne::c texteDoux]
  pack $c.nom $c.go $c.aide -side top -pady 3
  place $c -relx 0.5 -rely 0.45 -anchor center
  foreach x [list $p $c $c.nom $c.aide] { bind $x <ButtonRelease-1> [list ::moderne::docks::lancerEnPause $n] }
  $nb add $p -text $nom
  # its usual height, as a running engine
  set h {}
  catch {set h [::moderne::moteur::hauteurPrevue $n]}
  # (never ran: estimated from the fonts)
  if {$h eq {}} { catch {set h [::moderne::moteur::hauteurEstimee $n]} }
  if {$h ne {}} { catch {::moderne::docks::ajusterHauteur $p $h} }
}

### Engines across a view without engines (broadcast list, My databases):
### they are kept aside, paused, instead of being closed, and run again in
### the next view that shows them (Toby does not reload its networks). A
### view with engines closes those it does not show, as before.
namespace eval ::moderne::docks {
  variable reserve        ;# reserve(tab) = tab title of an engine kept aside
  array set reserve {}
  variable reprendre      ;# reprendre(n) = engine n was analysing
  array set reprendre {}
}

proc ::moderne::docks::reserveOfferte {} {
  variable reserve
  foreach t [array names reserve] {
    if {[winfo exists $t]} { set ::docking::gardes($t) $reserve($t) }
    unset reserve($t)
  }
}

### After a layout is built: the engines it reused analyse again; if it has
### no engine at all, the running ones are kept aside (analysis stopped)
proc ::moderne::docks::reserveApres {description {slot {}}} {
  variable reserve
  variable reprendre
  set avecMoteurs [regexp {fdockanalysisWin[0-9]+} $description]
  # (a game against an engine: no engine aside, as on Lichess; those
  # running before come back after the game, see disposition::jeuApres)
  if {$slot eq "moderne_jeu"} {
    array unset reprendre
    return
  }
  foreach t [array names ::docking::gardes] {
    if {![regexp {^\.fdockanalysisWin([0-9]+)$} $t -> n] || ![winfo exists $t]} { continue }
    if {$avecMoteurs} { catch {unset reprendre($n)} ; continue }
    if {[info exists ::analysis(analyzeMode$n)] && $::analysis(analyzeMode$n)} {
      set reprendre($n) 1
      catch {toggleEngineAnalysis $n}
    }
    set reserve($t) $::docking::gardes($t)
    unset ::docking::gardes($t)
  }
  if {!$avecMoteurs} { return }
  foreach n [array names reprendre] {
    unset reprendre($n)
    if {[winfo exists .fdockanalysisWin$n]} {
      after 300 [list catch [list ::moderne::disposition::demarrer $n]]
    }
  }
}

### A view laid over the whole Lab (My databases, the broadcasts' list):
### the engines analysing pause under it, as the layouts without engines
### did, and run again when the Lab comes back (2026-11-06)
namespace eval ::moderne::docks { variable sousCouverture {} }
proc ::moderne::docks::pauserSousCouverture {} {
  variable sousCouverture
  foreach w [winfo children .] {
    if {[regexp {^\.analysisWin([0-9]+)$} $w -> n] &&
        [info exists ::analysis(analyzeMode$n)] && $::analysis(analyzeMode$n)} {
      if {$n ni $sousCouverture} { lappend sousCouverture $n }
      catch {toggleEngineAnalysis $n}
    }
  }
}
proc ::moderne::docks::reprendreSousCouverture {} {
  variable sousCouverture
  set l $sousCouverture
  set sousCouverture {}
  if {[llength $l]} { after 200 [list ::moderne::docks::reprendreSuite $l] }
}
proc ::moderne::docks::reprendreSuite {l} {
  variable sousCouverture
  # (another cover laid meanwhile, e.g. from the list to My databases:
  # they wait for the Lab)
  set couvert 0
  catch {if {[::moderne::mesbases::enSuperposition]} { set couvert 1 }}
  catch {if {$::moderne::direct::superpose eq "liste"} { set couvert 1 }}
  if {$couvert} {
    foreach n $l { if {$n ni $sousCouverture} { lappend sousCouverture $n } }
    return
  }
  foreach n $l { catch {::moderne::disposition::demarrer $n} }
}

### Every paused engine started (e.g. the tests)
proc ::moderne::docks::lancerTousEnPause {} {
  foreach p [winfo children .] {
    if {[regexp {^\.fdockattenteanalysisWin([0-9]+)$} $p -> n]} { lancerEnPause $n }
  }
}

### Click on a paused engine: the engine is made in its place, then analyses
proc ::moderne::docks::lancerEnPause {n} {
  set p .fdockattenteanalysisWin$n
  if {![winfo exists $p]} { return }
  set nb [::docking::find_tbn $p]
  if {$nb eq {}} { return }
  ::docking::fenetreDifferee $nb $p [list ::makeAnalysisWin $n nostart]
  after 100 [list catch [list ::moderne::disposition::demarrer $n]]
}

proc ::moderne::docks::egaliserMoteurs {{pw .pw}} {
  if {![winfo exists $pw] || [winfo class $pw] ne "TPanedwindow"} { return }
  foreach p [$pw panes] {
    if {[winfo class $p] eq "TPanedwindow"} { egaliserMoteurs $p }
  }
  if {[$pw cget -orient] ne "horizontal"} { return }
  set panes [$pw panes]
  set n [llength $panes]
  if {$n < 2} { return }
  foreach p $panes { if {![estMoteur $p]} { return } }
  update idletasks
  set l [winfo width $pw]
  if {$l < 50} { return }
  # (twice: a sash cannot pass its neighbour)
  foreach passe {1 2} {
    for {set k 0} {$k < $n - 1} {incr k} {
      catch {$pw sashpos $k [expr {($k + 1) * $l / $n}]}
    }
  }
}

### Panes left empty once a layout is built (a window closed itself
### meanwhile) are removed
proc ::moderne::docks::retirerVoletsVides {pw} {
  foreach p [$pw panes] {
    if {[winfo class $p] eq "TPanedwindow"} { retirerVoletsVides $p }
  }
  if {$pw ne ".pw" && [winfo exists $pw] && ![llength [$pw panes]]} { destroy $pw }
}

### Engines of the new layout started in parallel, before the windows are
### built one after the other (each engine takes about a second to get
### ready: they now get ready at the same time)
proc ::moderne::docks::prelancer {description} {
  variable lancer
  foreach {- n} [regexp -all -inline {fdockanalysisWin([0-9]+)} $description] {
    # (only the engines that will run: the others wait, paused)
    if {![info exists lancer($n)]} { continue }
    if {[winfo exists .analysisWin$n] || [info exists ::moderne::docks::prelance($n)]} { continue }
    if {![string is integer -strict $n] || $n >= [llength $::engines(list)]} { continue }
    set data [lindex $::engines(list) $n]
    if {[llength $data] < 8 || ![lindex $data 7]} { continue }
    set cmd [toAbsPath [lindex $data 1]]
    set args [lindex $data 2]
    set dir [toAbsPath [lindex $data 3]]
    set avant [pwd]
    if {$dir ne "."} { catch {cd $dir} }
    if {![catch {open "| [list $cmd] $args[::sibyErreursMoteur]" "r+"} c]} {
      fconfigure $c -buffering line -blocking 0
      catch {puts $c uci}
      catch {::moderne::toby::prechargerLeela $n [list puts $c]}
      set ::moderne::docks::prelance($n) $c
    }
    catch {cd $avant}
  }
}

### The process started in advance for engine n (empty if none)
proc ::moderne::docks::prisPrelance {n} {
  if {![info exists ::moderne::docks::prelance($n)]} { return {} }
  set c $::moderne::docks::prelance($n)
  unset ::moderne::docks::prelance($n)
  catch {unset ::moderne::docks::garde($n)}
  if {[catch {eof $c} fin] || $fin} { catch {close $c} ; return {} }
  return $c
}

### Those not used by the layout are stopped (not Toby started at
### start-up: it waits for its panel)
proc ::moderne::docks::finPrelance {} {
  foreach n [array names ::moderne::docks::prelance] {
    if {[info exists ::moderne::docks::garde($n)]} { continue }
    catch {close $::moderne::docks::prelance($n)}
    unset ::moderne::docks::prelance($n)
  }
}

### Toby started a few seconds after Siby's start, when it is used (an
### analysis with it in the last 30 days): it loads its networks while the
### user looks at their databases, and its panel finds it ready (Options ›
### Preload Toby, Yosha 2026-11-05). The process waits for the panel
### (prisPrelance), like the engines of a layout change.
### (after the reference database's reading in the background, at most
### 60 s after the start; the time it waited written to siby.log)
proc ::moderne::docks::prechargerTobyApres {{n 0}} {
  set lecture 0
  catch {set lecture [expr {[lindex [sc_base prepa] 0] eq "encours"}]}
  if {$lecture && $n < 52} {
    after 1000 [list ::moderne::docks::prechargerTobyApres [incr n]]
    return
  }
  catch {::moderne::journal "Toby preload at [format %.1f [expr {([clock milliseconds] - $::sibyT0) / 1000.0}]] s after the start (waited $n s for the reference database)"}
  prechargerToby
}

proc ::moderne::docks::prechargerToby {} {
  if {![info exists ::moderne::toby::precharger] || !$::moderne::toby::precharger} { return }
  if {[info exists ::env(SIBY_DEMARRAGE_BRUT)] && $::env(SIBY_DEMARRAGE_BRUT) ne {} && ![info exists ::env(SIBY_PRECHARGE_TOBY)]} { return }
  set derniere 0
  catch {set derniere $::moderne::toby::derniereUtilisation}
  if {![string is integer -strict $derniere] || [clock seconds] - $derniere > 30 * 86400} { return }
  set t [lindex [::moderne::toby::moteursToby] 0]
  if {$t eq {}} { return }
  set n [lindex $t 0]
  if {[winfo exists .analysisWin$n] || [info exists ::moderne::docks::prelance($n)]} { return }
  set data [lindex $::engines(list) $n]
  if {[llength $data] < 8 || ![lindex $data 7]} { return }
  set avant [pwd]
  set dir [toAbsPath [lindex $data 3]]
  if {$dir ne "."} { catch {cd $dir} }
  if {![catch {open "| [list [toAbsPath [lindex $data 1]]] [lindex $data 2][::sibyErreursMoteur]" "r+"} c]} {
    fconfigure $c -buffering line -blocking 0
    catch {puts $c uci}
    catch {::moderne::toby::prechargerLeela $n [list puts $c]}
    set ::moderne::docks::prelance($n) $c
    set ::moderne::docks::garde($n) 1
    catch {::moderne::journal "Toby preloaded (engine $n)"}
  }
  catch {cd $avant}
}

### Saved layouts follow the screen's scale: they are stored in pixels, so
### a layout saved at 100 % (or before Siby handled scaled Windows screens)
### is enlarged at 150 %, and the other way round. ::moderne::echelleEcran
### (saved): the [tk scaling] the layouts were saved with.
proc ::moderne::docks::echelleTexte {d r} {
  set res {}
  while {[regexp -indices {(MainWindowGeometry )([0-9]+)x([0-9]+)|(horizontal|vertical) ([0-9]+)} $d tout - w h - n]} {
    append res [string range $d 0 [expr {[lindex $tout 0] - 1}]]
    set m [string range $d {*}$tout]
    if {[lindex $w 0] >= 0} {
      set ww [expr {round([string range $d {*}$w] * $r)}]
      set hh [expr {round([string range $d {*}$h] * $r)}]
      # (the window stays within the screen)
      set ww [expr {min($ww, [winfo screenwidth .])}]
      set hh [expr {min($hh, [winfo screenheight .])}]
      append res "MainWindowGeometry ${ww}x${hh}"
    } else {
      regexp {^(\S+) } $m -> sens
      append res "$sens [expr {round([string range $d {*}$n] * $r)}]"
    }
    set d [string range $d [expr {[lindex $tout 1] + 1}] end]
  }
  return "$res$d"
}

proc ::moderne::docks::mettreAEchelle {} {
  set actuelle [tk scaling]
  if {![info exists ::moderne::echelleEcran] || ![string is double -strict $::moderne::echelleEcran]} {
    # (layouts saved before: at 100 %, 96 dpi)
    set ::moderne::echelleEcran [expr {96 / 72.0}]
  }
  set r [expr {$actuelle / $::moderne::echelleEcran}]
  if {abs($r - 1.0) < 0.05} { return }
  foreach slot [array names ::docking::layout_list] {
    catch {set ::docking::layout_list($slot) [echelleTexte $::docking::layout_list($slot) $r]}
  }
  foreach nom {preparation analyse} {
    catch {
      set v ::moderne::disposition::perso_$nom
      if {[set $v] ne {}} { set $v [echelleTexte [set $v] $r] }
    }
  }
  set ::moderne::echelleEcran $actuelle
}

### While a layout is being built (under its veil), a full "update" only
### lays out and draws ("update idletasks"): add_tab, the game list, the
### engine windows and restoreGeometry each called "update", about 20 times
### a layout; on Windows each one handled every pending event and redrew
### the half-built window, 2.4 to 3.8 s a layout against 0.3 s on Linux
### (night battery 2026-11-06, scenario profil_dispo)
if {![llength [info commands ::moderne::docks::updateOrigine]]} {
  rename ::update ::moderne::docks::updateOrigine
  proc ::update {args} {
    # (the "update idletasks" while building are kept: without them the
    # layout was all done at the end, slower still, 2.5 s against 1.8 s)
    if {![llength $args] && [info exists ::docking::enConstruction] && $::docking::enConstruction} {
      ::moderne::docks::updateOrigine idletasks
      return
    }
    ::moderne::docks::updateOrigine {*}$args
  }
}

### While a layout is being restored, do not move anything
set ::moderne::docks::restaurations 0
proc ::moderne::docks::installerRestauration {} {
  if {[llength [info commands ::docking::layout_restore_origine]]} { return }
  rename ::docking::layout_restore ::docking::layout_restore_origine
  proc ::docking::layout_restore {slot} {
    # (a layout restored just after another: the end of the previous one
    # must not fall in the middle of this one, when an engine window calls
    # "update")
    # (asked while another layout is being built: it comes just after)
    if {[info exists ::docking::enConstruction] && $::docking::enConstruction} {
      after 100 [list ::docking::layout_restore $slot]
      return
    }
    catch {after cancel $::moderne::docks::finRestauration}
    # (My databases laid over the Lab: back to its tab before the windows
    # are taken out of their tabs)
    catch ::moderne::mesbases::retirerSuperposition
    # (My databases' window hidden after it was laid over the Lab (in no
    # tab): destroyed, the layout makes it again if it has it. Put back in
    # a tab, its content was no longer drawn on Windows: an empty "My
    # databases" tab, Yosha 2026-11-17, after a broadcast)
    catch {
      if {[winfo exists .fdockmesBasesWin] && [::docking::find_tbn .fdockmesBasesWin] eq {}} {
        catch {destroy .mesBasesWin}
        catch {destroy .fdockmesBasesWin}
      }
    }
    catch ::moderne::direct::retirerSuperposition
    catch ::moderne::disposition::jeuRetirer
    catch ::moderne::prepa::rendreNotation
    incr ::moderne::docks::restaurations
    catch ::moderne::docks::mettreAEchelle
    set ::moderne::docks::restauration 1
    # (the engine windows are going to be recreated under the same name)
    catch {array unset ::moderne::moteur::ajuste}
    # Veil during setup (otherwise the windows are seen being
    # built one by one)
    ::moderne::docks::voile 1
    catch {::moderne::docks::prelancer $::docking::layout_list($slot)}
    # (engines kept aside by a view without engines: offered to this layout)
    catch ::moderne::docks::reserveOfferte
    set ::docking::enConstruction 1
    set code [catch {::docking::layout_restore_origine $slot} res opts]
    set ::docking::enConstruction 0
    catch ::docking::detruireGardes
    # (engines started in advance: stopped after the layout's engines are
    # made, see ::docking::lancerDifferees; at once if none waits)
    if {![llength $::docking::differees]} { catch ::moderne::docks::finPrelance }
    catch {::moderne::docks::retirerVoletsVides .pw}
    # (after a failure, nothing may point to a half-built layout)
    set ::docking::layout_dest_notebook ""
    catch ::docking::oublierDetruits
    catch {raise .voileDisposition}
    set ::moderne::docks::finRestauration [after 300 ::moderne::docks::finRestauration]
    # (the veil stays during the final adjustments: engine panel
    # heights, engine startup)
    set ::moderne::docks::finVoileMax [expr {[clock milliseconds] + 4000}]
    after 100 ::moderne::docks::finVoile
    return -options $opts $res
  }
}

### The veil goes away when every engine has received its first lines (its
### final height is then set), at the latest after 4 s
proc ::moderne::docks::finVoile {} {
  variable finVoileMax
  set attendre 0
  foreach f [winfo children .] {
    if {![regexp {^\.analysisWin([0-9]+)$} $f -> n]} { continue }
    if {![info exists ::analysis(analyzeMode$n)] || !$::analysis(analyzeMode$n)} { continue }
    # (its height is known from last time: no need to wait for its lines)
    set prevue {}
    catch {set prevue [::moderne::moteur::hauteurPrevue $n]}
    if {$prevue ne {}} { continue }
    if {![info exists ::moderne::moteur::ajuste($n)] || $::moderne::moteur::ajuste($n) ne "$f.hist.text"} {
      set attendre 1
    }
  }
  if {$attendre && [clock milliseconds] < $finVoileMax} {
    set ::moderne::docks::finVoileAttendu 1
    after 150 ::moderne::docks::finVoile
    return
  }
  # (time for the height adjustment, 200 ms after the first lines; at
  # once if nothing had to be waited for: windows kept as they were),
  # then until the board keeps the same size (it is resized when the
  # panels settle)
  set ::moderne::docks::tailleVue {}
  if {[info exists ::moderne::docks::finVoileAttendu] && $::moderne::docks::finVoileAttendu} {
    set ::moderne::docks::finVoileAttendu 0
    after 450 ::moderne::docks::finVoileStable
  } else {
    after 60 ::moderne::docks::finVoileStable
  }
}

proc ::moderne::docks::finVoileStable {} {
  variable finVoileMax
  variable tailleVue
  # (pending resizes applied first: the board is resized a moment after
  # the panels, see ::docking::handleConfigureEvent)
  catch {update idletasks}
  foreach id [after info] {
    # (an event may have run or been cancelled meanwhile)
    if {[catch {lindex [after info $id] 0} script]} { continue }
    if {[string match "*resizeMainBoard*" $script]} {
      after cancel $id
      catch ::resizeMainBoard
    }
  }
  set t {}
  catch {set t [list [winfo width .main.board] [winfo height .main.board] $::board::_size(.main.board)]}
  # (the layout is still settling: the panel heights asked for meanwhile
  # are applied just after it, they must happen under the veil)
  variable restauration
  if {[info exists restauration] && $restauration && [clock milliseconds] < $finVoileMax + 2000} {
    set tailleVue {}
    after 80 ::moderne::docks::finVoileStable
    return
  }
  if {$t ne $tailleVue && [clock milliseconds] < $finVoileMax + 2000} {
    set tailleVue $t
    after 100 ::moderne::docks::finVoileStable
    return
  }
  ::moderne::docks::voile 0
}

### The views laid over the Lab raised again, in front of a window just
### made under them
proc ::moderne::docks::releverCouvertures {} {
  catch {if {[::moderne::mesbases::enSuperposition]} { raise .fdockmesBasesWin }}
  catch {
    if {[::moderne::direct::enSuperposition]} {
      raise .directCouvre
      foreach nb {.directCouvre.liste .directCouvre.pw.haut .directCouvre.pw.bas} {
        if {[winfo exists $nb] && [winfo ismapped $nb]} { foreach t [$nb tabs] { raise $t } }
      }
    }
  }
  catch {
    if {[winfo exists .jeuCouvre] && [winfo ismapped .jeuCouvre]} {
      raise .jeuCouvre
      foreach t [.jeuCouvre.nb tabs] { raise $t }
    }
  }
}

### Windows: the main window's painting held (0) or given back, all of it
### repainted at once (1); elsewhere nothing
proc ::moderne::docks::redessin {etat} {
  variable redessinCoupe
  if {!$::windowsOS || [llength [info commands sc_redessin]] == 0} { return }
  if {!$etat && (![info exists redessinCoupe] || !$redessinCoupe)} {
    set redessinCoupe 1
    catch {sc_redessin [winfo id .] 0}
  } elseif {$etat && [info exists redessinCoupe] && $redessinCoupe} {
    set redessinCoupe 0
    catch {sc_redessin [winfo id .] 1}
  }
}

### The veil taken off once the slow windows are made (at the latest at
### limite) and the board has its size
proc ::moderne::docks::voileApresDifferees {limite} {
  set enCours 0
  foreach id [after info] {
    if {[catch {lindex [after info $id] 0} script]} { continue }
    if {[string match "*fenetreDifferee*" $script] || [string match "*restoreGeometry*" $script]} { set enCours 1 ; break }
  }
  if {($enCours || [llength $::docking::differees]) && [clock milliseconds] < $limite} {
    after 30 [list ::moderne::docks::voileApresDifferees $limite]
    return
  }
  catch {update idletasks}
  # (the board's resize asked meanwhile done now, under the veil)
  foreach id [after info] {
    if {[catch {lindex [after info $id] 0} script]} { continue }
    if {[string match "*resizeMainBoard*" $script]} { after cancel $id ; catch ::resizeMainBoard }
  }
  catch {update idletasks}
  ::moderne::docks::voile 0
}

### Recreated windows (.fdock…) are at the same level as the veil and
### would come in front of it: raise it again as long as it is there
proc ::moderne::docks::voileDessus {} {
  if {![winfo exists .voileDisposition]} { return }
  raise .voileDisposition
  after 30 ::moderne::docks::voileDessus
}

### Plain veil over the window area during a layout change:
### a borderless, topmost window placed exactly over the work
### area (on Windows, embedded panels are real windows that
### would come in front of a simple frame)
proc ::moderne::docks::voile {mettre} {
  set v .voileDisposition
  if {!$mettre} {
    # the slow windows of the layout (engines, game list) made now, still
    # under the veil: the layout is shown once whole (they came after it,
    # one by one, Yosha 2026-11-06: "on voit la construction des fenêtres")
    if {[winfo exists $v] && [llength $::docking::differees]} {
      ::docking::lancerDifferees
      after 20 [list ::moderne::docks::voileApresDifferees [expr {[clock milliseconds] + 3000}]]
      return
    }
    catch {update idletasks}
    # (Windows: the main window paints again, all at once, still under the
    # veil)
    redessin 1
    # (Windows: the veil made see-through a moment first, so the windows
    # under it paint themselves while still covered; taken off at once,
    # they were seen painting one after the other)
    if {$::windowsOS && [winfo exists $v] && ![catch {wm attributes $v -alpha 0.97}]} {
      after 120 [list catch [list destroy $v]]
      after 121 ::docking::lancerDifferees
      return
    }
    catch {destroy $v}
    after 1 ::docking::lancerDifferees
    return
  }
  # (startup: the main window is not shown yet; and until it is (the Lab
  # built at startup, after ::moderne_demarrage), the startup window is the
  # only thing seen: the veil came over it, Yosha 2026-11-08)
  if {[info exists ::moderne_demarrage] && $::moderne_demarrage} { return }
  if {[winfo exists .sibyDemarrage]} { return }
  if {$::windowsOS && ![catch {wm attributes . -alpha} a] && $a < 0.99} { return }
  if {![winfo exists .pw] || ![winfo ismapped .pw]} { return }
  catch {destroy $v}
  toplevel $v -background [::moderne::c fond]
  wm overrideredirect $v 1
  catch {wm attributes $v -topmost 1}
  label $v.l -text [::moderne::tr "Disposition…" "Layout…"] -font font_Small \
      -background [::moderne::c fond] -foreground [::moderne::c texteDoux]
  place $v.l -relx 0.5 -rely 0.5 -anchor center
  wm geometry $v "[winfo width .pw]x[winfo height .pw]+[winfo rootx .pw]+[winfo rooty .pw]"
  raise $v
  update idletasks
  # (Windows: the panels are real windows and painted over the veil while
  # being built, Yosha's video 2026-11-06: the main window stops painting
  # until the veil goes)
  redessin 0
  ::moderne::docks::voileDessus
  # (safeguard: never more than 10 s)
  catch {after cancel $::moderne::docks::gardeVoile}
  set ::moderne::docks::gardeVoile [after 10000 {catch {::moderne::docks::voile 0}}]
}
::moderne::docks::installerRestauration

################################################################################
### Height of an engine group: just what its lines need
### (the neighboring group, usually the board, takes the rest)
################################################################################

### Pane (notebook or nested panedwindow) containing notebook nb,
### and the vertical panedwindow it is a pane of; {} if there is none
proc ::moderne::docks::voletVertical {nb} {
  set c $nb
  set pw [expr {[info exists ::docking::tbs($c)] ? $::docking::tbs($c) : {}}]
  while {$pw ne {} && [winfo exists $pw]} {
    if {[winfo class $pw] eq "TPanedwindow" && [$pw cget -orient] eq "vertical"} {
      return [list $c $pw]
    }
    set c $pw
    set pw [winfo parent $pw]
    if {$pw eq "." || [winfo class $pw] ne "TPanedwindow"} { return {} }
  }
  return {}
}

### Gives the group containing docked window f the height h (pixels
### of f's content, without the tab), by moving the sash above it
proc ::moderne::docks::ajusterHauteur {f h} {
  variable restauration
  # Layout being applied: done as soon as it is in place, still under the
  # veil (a retry 400 ms later came after the veil and the board moved)
  if {[info exists restauration] && $restauration} {
    variable hauteursAttente
    dict set hauteursAttente $f $h
    return
  }
  if {![winfo exists $f]} { return }
  set nb [::docking::find_tbn $f]
  if {![gere $nb]} { return }
  set r [voletVertical $nb]
  if {$r eq {}} { return }
  lassign $r c pw
  update idletasks
  set panes [$pw panes]
  set i [lsearch -exact $panes $c]
  if {$i < 0} { return }
  # desired panel height: tab + content
  set onglet [expr {[winfo rooty $f] - [winfo rooty $nb]}]
  if {$onglet < 0 || $onglet > 80} { set onglet 32 }
  set voulu [expr {$h + $onglet + 4}]
  # panels side by side in the same row (two engines): the row takes the
  # height of the tallest one
  variable voulus
  # (keyed by the window, the paused placeholder and the panel that
  # replaces it being one: the row does not shrink for a moment between
  # them; Yosha 2026-11-01)
  set cle [string map {.fdockattente .fdock} $f]
  set voulus($c,$cle) $voulu
  foreach k [array names voulus $c,*] {
    set fk [lindex [split $k ,] end]
    if {![winfo exists $fk] && ![winfo exists [string map {.fdock .fdockattente} $fk]]} { unset voulus($k) ; continue }
    set voulu [expr {max($voulu, $voulus($k))}]
  }
  set haut [expr {[winfo rooty $c] - [winfo rooty $pw]}]
  set bas [expr {$haut + [winfo height $c]}]
  if {$i > 0} {
    # sash above the panel
    set pos [expr {max(120, $bas - $voulu)}]
    catch {$pw sashpos [expr {$i - 1}] $pos}
    retenirSash $pw [expr {$i - 1}]
  } elseif {[llength $panes] > 1} {
    # top panel: sash below it
    catch {$pw sashpos 0 [expr {$haut + $voulu}]}
    retenirSash $pw 0
  }
}

### The layout's sash positions follow the heights set here: putting the
### layout's bars back later (a window replacing its placeholder) must not
### undo them
proc ::moderne::docks::retenirSash {pw k} {
  if {![info exists ::docking::sashpos]} { return }
  set l {}
  foreach elt $::docking::sashpos {
    lassign $elt w pos
    if {$w eq $pw && $k < [llength $pos]} {
      catch {lset pos $k [$pw sashpos $k]}
      set elt [list $w $pos]
    }
    lappend l $elt
  }
  set ::docking::sashpos $l
}

### End of a layout change: the panel heights asked for meanwhile
proc ::moderne::docks::finRestauration {} {
  # (the review next to the notation once the layout is built)
  catch ::moderne::bilan::verifierPlusTard
  variable restauration 0
  variable hauteursAttente
  if {![info exists hauteursAttente]} { return }
  set d $hauteursAttente
  set hauteursAttente {}
  dict for {f h} $d { catch {ajusterHauteur $f $h} }
}

################################################################################
### A running engine paused (its ▶ / ⏸ button, or a review): the paused view
### covers its panel, as on Lichess where a stopped engine shows no line,
### instead of the last lines of another position (2026-10-29). The engine
### stays loaded: a click anywhere on it analyses again at once.
################################################################################

proc ::moderne::docks::voilesPause {} {
  foreach f [winfo children .] {
    if {![regexp {^\.analysisWin([0-9]+)$} $f -> n]} { continue }
    set actif [expr {[info exists ::analysis(analyzeMode$n)] && $::analysis(analyzeMode$n)}]
    set v $f.voilePause
    if {$actif} { catch {destroy $v} ; continue }
    if {[winfo exists $v]} { raise $v ; continue }
    # (an engine still loading is not "paused")
    if {[info exists ::analysis(uci$n)] && $::analysis(uci$n) && !$::analysis(uciok$n)} { continue }
    frame $v -background [::moderne::c fond] -cursor hand2
    set c [frame $v.c -background [::moderne::c fond]]
    label $c.nom -text [lindex [lindex $::engines(list) $n] 0] -font font_Bold \
        -background [::moderne::c fond] -foreground [::moderne::c texte]
    ttk::button $c.go -text "▶  [::moderne::tr Analyser Analyse]" -command [list ::moderne::docks::reprendrePause $n]
    catch {$c.go configure -style Accent.TButton}
    label $c.aide -text [::moderne::tr "En pause : clique pour lancer l'analyse" "Paused: click to start the analysis"] \
        -background [::moderne::c fond] -foreground [::moderne::c texteDoux]
    pack $c.nom $c.go $c.aide -side top -pady 3
    place $c -relx 0.5 -rely 0.45 -anchor center
    foreach x [list $v $c $c.nom $c.aide] { bind $x <ButtonRelease-1> [list ::moderne::docks::reprendrePause $n] }
    place $v -x 0 -y 0 -relwidth 1 -relheight 1
    raise $v
  }
}

proc ::moderne::docks::reprendrePause {n} {
  catch {destroy .analysisWin$n.voilePause}
  if {[winfo exists .analysisWin$n] && !([info exists ::analysis(analyzeMode$n)] && $::analysis(analyzeMode$n))} {
    catch {toggleEngineAnalysis $n}
  }
}

if {[::moderne::actif] && [llength [info commands ::toggleEngineAnalysis]]} {
  trace add execution ::toggleEngineAnalysis leave {apply {args { after idle {catch ::moderne::docks::voilesPause} }}}
}

### End Siby


### A docked window's tab t (its container frame .fdock…) given a place in
### tab group nb, or, when nb is gone, in another group of the layout:
### never destroyed while its window is alive. A container destroyed under
### its window stops Siby on Windows ("UpdateWrapper: Container was
### destroyed"): a game's play panel, just made, lost that way when the
### previous game's layout was given back, Yosha 2026-11-09.
proc ::moderne::docks::rangerOnglet {t titre nb {exclure {}}} {
  if {$nb ne {} && [winfo exists $nb] && ![catch {$nb add $t -text $titre}]} { catch {raise $t} ; return 1 }
  # the window inside it (.fdockX holds .X)
  set fen .[string range [winfo name $t] 5 end]
  if {[string match fdock* [winfo name $t]] && [winfo exists $fen]} {
    foreach g [array names ::docking::tbs] {
      if {![winfo exists $g] || [winfo class $g] ne "TNotebook"} { continue }
      if {$exclure ne {} && [string match $exclure* $g]} { continue }
      if {![catch {$g add $t -text $titre}]} { catch {raise $t} ; return 1 }
    }
    # (nowhere to go: kept, unmapped, rather than destroyed)
    return 0
  }
  catch {destroy $t}
  return 0
}
