###
### Siby: retractable navigation bar on the left of the main window (like
### Lichess's side menu): layouts, live broadcasts, my databases, play.
### Folded (default): icons only, the names in tooltips; unfolded: icons
### and names. ::moderne::navOuverte (saved): unfolded or not;
### ::moderne::navVisible (saved): the bar shown at all.
###

namespace eval ::moderne::navigation {
  variable w .navSiby
}
foreach {_v _d} {navOuverte 0 navVisible 1} {
  if {![info exists ::moderne::$_v]} { set ::moderne::$_v $_d }
}
unset _v _d

proc ::moderne::navigation::T {fr en} { return [::moderne::tr $fr $en] }

### Entries: icon, French name, English name, command; "-" draws a thin
### separator. Groups: where the games are, the two workspaces (from the
### lightest to the fullest), then live chess (broadcasts, play).
proc ::moderne::navigation::entrees {} {
  return {
    ▤ "Mes bases" "My databases" ::moderne::mesbases::vue
    - - - -
    ⊞ "Lab" "Lab" ::moderne::disposition::aller
    - - - -
    ● "Retransmissions" "Broadcasts" ::moderne::direct::ouvrir
    - - - -
    ♞ "Jouer" "Play" {::moderne::jouer::ouvrir toby}
  }
}

### The icons of the bar, drawn as images of the same size (moderne/
### navicones.tcl): fonts draw the symbols at different sizes, and Windows
### turns some into colour emoji
proc ::moderne::navigation::imageIcone {icone} {
  variable iconesData
  set nom [dict get {▤ bases ⊞ lab ● direct ♞ jouer » deplier « replier ⚙ reglages} $icone]
  set theme [expr {[info exists ::moderne::theme] && $::moderne::theme eq "clair" ? "clair" : "sombre"}]
  # (the size for the screen's scale, as the other icons: 150 %, 200 %)
  set f 1
  catch {set f [::moderne::icones::facteur]}
  set cle [expr {$f == 1 ? $theme : "$theme@$f"}]
  if {![info exists iconesData($nom,$cle)]} { set cle $theme }
  set img siby_nav_${nom}_$cle
  if {[lsearch -exact [image names] $img] < 0} {
    image create photo $img -format png -data $iconesData($nom,$cle)
  }
  return $img
}

### The button of an entry (by its icon), for the tests
proc ::moderne::navigation::bouton {icone} {
  variable w
  set i 0
  foreach {ic fr en cmd} [entrees] {
    if {$ic eq "-"} { continue }
    if {$ic eq $icone} { return $w.e$i }
    incr i
  }
  return ""
}

### At the start: installs the bar once the main window is ready (the
### paned window .pw may come a little later on a slow start), trying
### every 200 ms, n times at most
proc ::moderne::navigation::installerPret {n} {
  variable w
  if {[winfo exists $w] || !$::moderne::navVisible} { return }
  if {[::moderne::actif] && $::docking::USE_DOCKING && [winfo exists .pw]} {
    if {[catch installer e]} { puts stderr "Siby navigation: $e" }
    return
  }
  if {$n > 0} { after 200 [list ::moderne::navigation::installerPret [expr {$n - 1}]] }
}

proc ::moderne::navigation::installer {} {
  variable w
  if {![::moderne::actif] || !$::docking::USE_DOCKING || ![winfo exists .pw]} { return }
  catch {destroy $w}
  if {!$::moderne::navVisible} { return }
  set fond [::moderne::c fond]
  frame $w -background $fond -highlightthickness 0 -borderwidth 0
  set police [list [font actual font_Regular -family] 15]
  button $w.plier -text [expr {$::moderne::navOuverte ? "«" : "»"}] -relief flat -borderwidth 0 \
      -background $fond -foreground [::moderne::c texteDoux] -activebackground [::moderne::c survol] \
      -font font_Regular -command ::moderne::navigation::basculer -cursor hand2
  catch {$w.plier configure -text {} -image [imageIcone [expr {$::moderne::navOuverte ? "«" : "»"}]]}
  pack $w.plier -side top -fill x -pady {6 10}
  ::utils::tooltip::Set $w.plier [T "Déplier / replier la barre" "Unfold / fold the bar"]
  set i 0
  set s 0
  foreach {icone fr en cmd} [entrees] {
    if {$icone eq "-"} {
      frame $w.s$s -height 1 -background [::moderne::c bordure]
      pack $w.s$s -side top -fill x -padx 8 -pady 5
      incr s
      continue
    }
    set b $w.e$i
    set texte [expr {$::moderne::navOuverte ? "$icone  [T $fr $en]" : $icone}]
    # (folded: icons centered, whatever the width of each symbol in the font)
    button $b -text $texte -anchor [expr {$::moderne::navOuverte ? "w" : "center"}] \
        -relief flat -borderwidth 0 -padx 10 -pady 6 \
        -background $fond -foreground [::moderne::c texte] -activebackground [::moderne::c survol] \
        -activeforeground [::moderne::c texteFort] -cursor hand2 \
        -font [expr {$::moderne::navOuverte ? "font_Regular" : $police}] \
        -command [list ::moderne::navigation::lancer $cmd]
    # (an image, the name beside it when unfolded)
    if {![catch {imageIcone $icone} img]} {
      $b configure -image $img -compound left \
          -text [expr {$::moderne::navOuverte ? "  [T $fr $en]" : ""}]
    }
    # (folded: as tall as unfolded, the icons as spaced; Yosha 2026-11-01)
    if {!$::moderne::navOuverte} {
      # (an image-only button ignores -pady: its height in pixels)
      set d [expr {[hauteurDepliee $b [T $fr $en]] - [winfo reqheight $b]}]
      if {$d > 0} { $b configure -height [expr {[image height [$b cget -image]] + $d}] }
    }
    pack $b -side top -fill x
    ::utils::tooltip::Set $b [T $fr $en]
    if {$icone eq "⊞"} {
      ::utils::tooltip::Set $b [T "Lab : préparation et analyse" "Lab: preparation and analysis"]
    }
    # Play: a click opens the Play window (Toby chosen), a right click the
    # menu (Alter Ego favourites, play this position…)
    if {$icone eq "♞"} {
      bind $b <Button-3> ::moderne::navigation::menuJouer
      if {[tk windowingsystem] eq "aqua"} { bind $b <Button-2> ::moderne::navigation::menuJouer }
      ::utils::tooltip::Set $b [T "Jouer (clic droit : favoris, jouer cette position…)" "Play (right click: favourites, play this position…)"]
    }
    incr i
  }
  frame $w.sep -width 1 -background [::moderne::c bordure]
  place $w.sep -relx 1.0 -x -1 -y 0 -relheight 1.0
  pack $w -side left -fill y -before .pw
}

### Height of button b once unfolded (its icon and its name)
proc ::moderne::navigation::hauteurDepliee {b nom} {
  set t $b.mesure
  catch {destroy $t}
  button $t -text "  $nom" -image [$b cget -image] -compound left -font font_Regular \
      -relief flat -borderwidth 0 -padx 10 -pady 6
  set h [winfo reqheight $t]
  destroy $t
  return $h
}

proc ::moderne::navigation::lancer {cmd} {
  if {[catch {uplevel #0 $cmd} err]} { puts stderr "Siby navigation: $err" }
}

### "Play": against Toby (a level), or an Alter Ego (a real player),
### favourites and recent Alter Egos in one click
proc ::moderne::navigation::menuJouer {} {
  set m .navSiby.jouer
  catch {destroy $m}
  menu $m -tearoff 0
  $m add command -label [T "Contre Toby…" "Against Toby…"] -command {::moderne::jouer::ouvrir toby}
  $m add command -label [T "Contre un Alter Ego…" "Against an Alter Ego…"] -command {::moderne::jouer::ouvrir alterego}
  menu $m.ae -tearoff 0 -postcommand [list ::moderne::alterego::menuFavoris $m.ae]
  $m add cascade -label [T "Alter Ego : favoris et récents" "Alter Ego: favourites and recent"] -menu $m.ae
  $m add separator
  ::moderne::toby::entreesIci $m
  tk_popup $m {*}[winfo pointerxy .]
}

proc ::moderne::navigation::basculer {} {
  set ::moderne::navOuverte [expr {!$::moderne::navOuverte}]
  installer
}

### Menu: show / hide the bar
proc ::moderne::navigation::afficher {} {
  installer
  if {!$::moderne::navVisible} { catch {destroy .navSiby} }
}

### End Siby

###
### Game navigation from a button: after a click on a button, a radio button
### or a check box of the main window (e.g. Library › White / Black), the
### keyboard stays with it; the arrows then still move through the game
### (as on the board) instead of doing nothing.
###
proc ::moderne::navigation::touche {w cmd} {
  if {[winfo toplevel $w] ne "."} { return }
  uplevel #0 $cmd
  return -code break
}
foreach _c {TButton TRadiobutton TCheckbutton Button Radiobutton Checkbutton} {
  foreach {_k _cmd} {
    Left ::move::Back  Right ::move::Forward  Home {::move::Start 1}  End {::move::End 1}
    Up {::move::Back 10}  Down {::move::Forward 10}
  } {
    bind $_c <Key-$_k> [list ::moderne::navigation::touche %W $_cmd]
  }
}
unset _c _k _cmd
