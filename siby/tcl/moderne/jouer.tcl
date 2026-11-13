###
### Siby: the "Play" window, like Lichess's "Play with the computer":
###   - the opponent as two cards: Toby (a human of the chosen level) and
###     Alter Ego (a real player); no Leela opponent since 2026-11-01;
###   - the time control as chips (presets, or "Custom");
###   - the settings of the chosen opponent (levels as sliders; Alter Ego:
###     player, database, period, card);
###   - the start (initial position, board position, set up a position);
###   - three colour buttons (White / Random / Black): one click starts the
###     game.
### The settings are those of ::moderne::toby::jeu and
### ::moderne::alterego::form; the games are started by
### ::moderne::toby::jeuLancer and ::moderne::alterego::lancer.
###

namespace eval ::moderne::jouer {
  variable w .jouer
}
if {![info exists ::moderne::jouer::onglet]} { set ::moderne::jouer::onglet toby }

proc ::moderne::jouer::T {fr en} { return [::moderne::tr $fr $en] }
proc ::moderne::jouer::C {nom} { return [::moderne::c $nom] }

### Colour between a and b (t: 0 = a, 1 = b), for the selected card
proc ::moderne::jouer::melange {a b t} {
  lassign [winfo rgb . $a] r1 g1 b1
  lassign [winfo rgb . $b] r2 g2 b2
  format #%02x%02x%02x [expr {int(($r1 + ($r2 - $r1) * $t) / 257)}] \
      [expr {int(($g1 + ($g2 - $g1) * $t) / 257)}] [expr {int(($b1 + ($b2 - $b1) * $t) / 257)}]
}

proc ::moderne::jouer::polices {} {
  if {"SibyJouerGrand" ni [font names]} {
    font create SibyJouerGrand -family [font actual font_Regular -family] -size 17 -weight bold
    font create SibyJouerTitre -family [font actual font_Regular -family] -size 14 -weight bold
    font create SibyJouerSection -family [font actual font_Regular -family] -size 8 -weight bold
    font create SibyJouerPetit -family [font actual font_Regular -family] -size 8
    font create SibyJouerRoi -size 30
  }
}

proc ::moderne::jouer::defauts {} {
  # Toby's level: 2900 until one is chosen with the slider, then the last
  # one chosen (Yosha 2026-10-31)
  if {![info exists ::moderne::toby::jeu(eloChoisi)] || $::moderne::toby::jeu(eloChoisi) ne "1"} {
    set ::moderne::toby::jeu(eloToby) 2900
  }
  foreach {k v} {couleur white eloToby 2900 eloMoi 1800 source FIDE minutes 3 inc 2 depart initiale barres 0 contempt 200 noeuds 1} {
    if {![info exists ::moderne::toby::jeu($k)]} { set ::moderne::toby::jeu($k) $v }
  }
  foreach {k v} {mode prime age 25 couleur white joueur {} progres {} niveau 2000 depart initiale} {
    if {![info exists ::moderne::alterego::form($k)]} { set ::moderne::alterego::form($k) $v }
  }
}

### Engines for an opponent: list of {number name}
proc ::moderne::jouer::moteurs {quoi} {
  switch $quoi {
    toby - alterego { return [::moderne::toby::moteursToby] }
    leela {
      set r {}
      foreach e [::moderne::toby::moteursJeu] {
        if {[::moderne::toby::estLeelaJeu [lindex $e 0]]} { lappend r $e }
      }
      return $r
    }
  }
}

################################################################################
### Window
################################################################################

### Opens the window on an opponent (toby | alterego; empty: the
### last one)
proc ::moderne::jouer::ouvrir {{quoi {}}} {
  variable w
  variable onglet
  catch {::moderne::alterego::arreter}
  defauts
  # the initial position by default; the board's only from "Play this
  # position" (::moderne::toby::jouerIci)
  variable ici
  if {![info exists ici] || !$ici} {
    set ::moderne::toby::jeu(depart) initiale
    set ::moderne::alterego::form(depart) initiale
  }
  set ici 0
  if {$quoi ne {}} { set onglet $quoi }
  # (no Leela opponent any more, Yosha 2026-11-01: Toby plays up to 2900)
  if {$onglet ni {toby alterego}} { set onglet toby }
  if {![llength [moteurs toby]]} {
    tk_messageBox -icon info -parent . -title [T "Jouer" "Play"] -message [T \
        "Toby n'est pas parmi les moteurs : ajoute-le dans Outils › Moteurs." \
        "Toby is not among the engines: add it in Tools › Engines."]
    return
  }
  if {[winfo exists $w]} {
    choisir $onglet
    raise $w ; focus $w
    return
  }
  polices
  toplevel $w -background [C fond]
  wm title $w [T "Jouer" "Play"]
  wm transient $w .
  wm resizable $w 0 0
  set f [frame $w.f -background [C fond] -padx 22 -pady 16]
  pack $f -fill both -expand 1
  # (no big title: the window's title says it; the height is kept for
  # small screens)
  # Opponents
  section $f.l1 [T "Adversaire" "Opponent"]
  frame $f.cartes -background [C fond]
  pack $f.cartes -side top -fill x
  set i 0
  foreach {cle nom fr en} {
    toby Toby {} {}
    alterego "Alter Ego" "Un humain spécifique, d'hier ou d'aujourd'hui" "A specific human, past or present"} {
    carte $f.cartes.$cle $cle $nom [expr {$cle eq "toby" ? [texteToby] : [T $fr $en]}]
    grid $f.cartes.$cle -row 0 -column $i -sticky nsew -padx [expr {$i ? "4 0" : "0 4"}]
    grid columnconfigure $f.cartes $i -weight 1 -uniform cartes -minsize 218
    incr i
  }

  # The opponent's settings (rebuilt when the opponent changes)
  frame $f.corps -background [C fond]
  pack $f.corps -side top -fill x

  # Colour: one click starts the game
  frame $f.couleurs -background [C fond]
  pack $f.couleurs -side top -pady {18 0}
  # (the board's kings; random: half white, half black, like Lichess)
  set rois [rois]
  foreach {c img bg tip} [list \
      white [lindex $rois 0] [C surface2] [T "Jouer avec les Blancs (un clic lance la partie)" "Play White (one click starts the game)"] \
      hasard [lindex $rois 1] [C surface2] [T "Couleur au hasard (un clic lance la partie)" "Random colour (one click starts the game)"] \
      black [lindex $rois 2] [C surface2] [T "Jouer avec les Noirs (un clic lance la partie)" "Play Black (one click starts the game)"]] {
    label $f.couleurs.$c -image $img -background $bg -width 84 -height 84 -cursor hand2 \
        -highlightthickness 2 -highlightbackground $bg -highlightcolor $bg
    pack $f.couleurs.$c -side left -padx 6
    bind $f.couleurs.$c <Button-1> [list ::moderne::jouer::lancer $c]
    bind $f.couleurs.$c <Enter> [list %W configure -highlightbackground [C accent]]
    bind $f.couleurs.$c <Leave> [list %W configure -highlightbackground $bg]
    catch {::utils::tooltip::Set $f.couleurs.$c $tip}
  }

  # the review prepared while the player thinks (on by default)
  ttk::checkbutton $f.prepa -variable ::moderne::bilan::prepa::actif \
      -text [T "Préparer le bilan pendant la partie" "Prepare the review during the game"] \
      -command {catch ::options.write}
  catch {::utils::tooltip::Set $f.prepa [T "Pendant ta réflexion, Toby calcule déjà le niveau des coups joués : le bilan s'affiche presque tout de suite à la fin. Il s'arrête quand Toby doit jouer." \
      "While you think, Toby already works out the level of the moves played: the review shows almost at once at the end. It stops when Toby has to move."]}
  pack $f.prepa -side top -pady {14 0}

  bind $w <Escape> [list destroy $w]
  bind $w <Destroy> {if {"%W" eq ".jouer"} {catch {trace remove variable ::moderne::toby::jeu(noeuds) write ::moderne::jouer::majContempt}}}
  choisir $onglet
  catch {placeWinOverParent $w .}
  placer
}

### Keeps the whole window on the screen (above the taskbar), whatever its
### height (Alter Ego is the tallest)
proc ::moderne::jouer::placer {} {
  variable w
  if {![winfo exists $w]} { return }
  update idletasks
  set h [winfo reqheight $w]
  set x [winfo x $w]
  set y [winfo y $w]
  set haut [winfo vrootheight $w]
  if {$haut <= 0} { set haut [winfo screenheight $w] }
  # (title bar and taskbar)
  set bas [expr {$haut - 80}]
  if {$y + $h > $bas} { set y [expr {max(0, $bas - $h)}] }
  if {$y < 0} { set y 0 }
  wm geometry $w +$x+$y
}

### King images of the current piece set (60 px): white, half-half, black
proc ::moderne::jouer::rois {} {
  set t 60
  set mi ::moderne::jouer::roiHasard
  catch {image delete $mi}
  image create photo $mi -width $t -height $t
  set m [expr {$t / 2}]
  $mi copy wk$t -from 0 0 $m $t -to 0 0
  $mi copy bk$t -from $m 0 $t $t -to $m 0
  return [list wk$t $mi bk$t]
}

proc ::moderne::jouer::fermer {} {
  variable w
  catch {destroy $w}
}

### Small capitals section title
proc ::moderne::jouer::section {nom texte {parent {}}} {
  label $nom -text [string toupper $texte] -font SibyJouerSection -background [C fond] \
      -foreground [C texteDoux] -anchor w
  if {$parent eq {}} { pack $nom -side top -fill x -pady {12 5} }
  return $nom
}

### An opponent card: logo, name, one line
### Toby's levels in a rating list: {min max}, as recommended by Toby
### (sealed test v2, 2026-10-26): FIDE 1400-2900 (validated in Classical),
### Lichess 600-3000 (validated; under 600 nothing changes), Chess.com
### 600-2800 (converted)
proc ::moderne::jouer::bornes {source} {
  switch -glob -- $source {
    FIDE        { return {1400 2900} }
    Lichess*    { return {600 3000} }
    Chess.com*  { return {600 2800} }
  }
  return {600 3000}
}

proc ::moderne::jouer::texteToby {} {
  return [T "Un humain générique, à l'Elo de ton choix" "A generic human, at the rating you choose"]
}

### Rating list changed: slider bounds, levels kept inside, card text
proc ::moderne::jouer::majBornes {} {
  set p .jouer.f.corps.niv
  lassign [bornes $::moderne::toby::jeu(source)] a b
  foreach {x var} {toby eloToby moi eloMoi} {
    if {![winfo exists $p.$x.s]} { continue }
    $p.$x.s configure -from $a -to $b
    set v $::moderne::toby::jeu($var)
    if {![string is integer -strict $v] || $v < $a} { set ::moderne::toby::jeu($var) $a }
    if {$v > $b} { set ::moderne::toby::jeu($var) $b }
  }
  catch {.jouer.f.cartes.toby.t configure -text [texteToby]}
}

proc ::moderne::jouer::carte {c cle nom texte} {
  set fond [C surface]
  frame $c -background $fond -highlightthickness 1 -highlightbackground [C bordure] -padx 10 -pady 8 -cursor hand2
  # (48 x 48 px tiles: Toby's logo, Alter Ego's (a human and their pink
  # double, Yosha 2026-11-10))
  set img {}
  if {$cle eq "toby"} { catch {set img [::moderne::logos::image toby 48]} }
  if {$cle eq "alterego"} {
    catch {
      set img ::moderne::jouer::alterego48
      if {$img ni [image names]} {
        image create photo $img -format png -data $::moderne::logosmoteurs::donnees(alterego,48)
      }
    }
  }
  if {$img ne {}} {
    label $c.i -image $img -background $fond -width [image width $img] -height [image height $img]
  } else {
    if {"::moderne::jouer::vide" ni [image names]} { image create photo ::moderne::jouer::vide -width 1 -height 1 }
    set av [dict get {leela #6b4bd6 alterego #c0632f toby #2b2b2b} $cle]
    label $c.i -text [dict get {leela Lc0 alterego AE toby T} $cle] -font font_Bold -foreground #fafafa \
        -background $av -image ::moderne::jouer::vide -compound center -width 48 -height 48
  }
  label $c.n -text $nom -font font_Bold -background $fond -foreground [C texteFort] -anchor w
  label $c.t -text $texte -font SibyJouerPetit -background $fond -foreground [C texteDoux] \
      -anchor w -justify left -wraplength 136
  grid $c.i -row 0 -column 0 -rowspan 2 -sticky n -padx {0 9}
  grid $c.n -row 0 -column 1 -sticky w
  grid $c.t -row 1 -column 1 -sticky nw
  set dispo [llength [moteurs $cle]]
  foreach x [list $c $c.i $c.n $c.t] {
    if {$dispo} {
      bind $x <Button-1> [list ::moderne::jouer::choisir $cle]
    } else {
      $x configure -cursor {}
      catch {::utils::tooltip::Set $x [expr {$cle eq "leela" \
          ? [T "Ajoute Leela dans Outils › Ajouter un moteur" "Add Leela in Tools › Add an engine"] \
          : [T "Ajoute Toby dans Outils › Ajouter un moteur" "Add Toby in Tools › Add an engine"]}]}
    }
  }
  if {!$dispo} { foreach x [list $c.n $c.t] { $x configure -foreground [C inactif] } }
}

### Shows the settings of an opponent
proc ::moderne::jouer::choisir {cle} {
  variable w
  variable onglet
  if {![llength [moteurs $cle]]} { return }
  set onglet $cle
  set f $w.f
  foreach k {toby alterego} {
    set c $f.cartes.$k
    if {![winfo exists $c]} { continue }
    set on [expr {$k eq $cle}]
    set fond [expr {$on ? [melange [C surface] [C accent] 0.14] : [C surface]}]
    $c configure -background $fond -highlightbackground [expr {$on ? [C accent] : [C bordure]}]
    foreach x {i n t} {
      if {$x eq "i" && [$c.i cget -image] in {{} ::moderne::jouer::vide}} { continue }
      $c.$x configure -background $fond
    }
  }
  foreach x [winfo children $f.corps] { destroy $x }
  catch {trace remove variable ::moderne::toby::jeu(noeuds) write ::moderne::jouer::majContempt}
  switch $cle {
    toby     { corpsToby $f.corps }
    alterego { corpsAlterEgo $f.corps }
  }
  if {[winfo ismapped $w]} { after idle ::moderne::jouer::placer }
}

################################################################################
### Shared parts
################################################################################

### Time control chips: presets {minutes increment}, then "Custom"
proc ::moderne::jouer::cadences {p} {
  section $p.lcad [T "Cadence" "Time control"]
  frame $p.cad -background [C fond]
  pack $p.cad -side top -fill x
  set i 0
  foreach {m s} {1 0 3 0 3 2 5 3 10 0 10 5 15 10 30 0 90 30} {
    pastille $p.cad.p$i "$m+$s" [nomCadence $m $s] [list ::moderne::jouer::cadenceChoisie $m $s]
    grid $p.cad.p$i -row [expr {$i / 5}] -column [expr {$i % 5}] -sticky nsew -padx 3 -pady 3
    incr i
  }
  pastille $p.cad.perso [T "Perso" "Custom"] … ::moderne::jouer::cadencePerso
  grid $p.cad.perso -row 1 -column 4 -sticky nsew -padx 3 -pady 3
  for {set c 0} {$c < 5} {incr c} { grid columnconfigure $p.cad $c -weight 1 -uniform cad }
  favorisCadence $p
  # custom: minutes + increment
  frame $p.perso -background [C fond]
  ttk::spinbox $p.perso.min -from 1 -to 180 -increment 1 -width 5 -textvariable ::moderne::toby::jeu(minutes) \
      -command ::moderne::jouer::majCadences
  label $p.perso.l1 -text [T "min +" "min +"] -background [C fond] -foreground [C texte]
  ttk::spinbox $p.perso.inc -from 0 -to 60 -increment 1 -width 4 -textvariable ::moderne::toby::jeu(inc) \
      -command ::moderne::jouer::majCadences
  label $p.perso.l2 -text [T "s par coup" "s per move"] -background [C fond] -foreground [C texte]
  ttk::button $p.perso.fav -text [T "☆ En favori" "☆ Favourite"] -style Toolbutton \
      -command ::moderne::jouer::ajouterCadenceFav
  catch {::utils::tooltip::Set $p.perso.fav [T "Garder cette cadence parmi les pastilles (clic droit sur la pastille pour la retirer)" \
      "Keep this time control among the chips (right click on the chip to remove it)"]}
  pack $p.perso.min $p.perso.l1 $p.perso.inc $p.perso.l2 -side left -padx 2
  pack $p.perso.fav -side left -padx {12 0}
  bind $p.perso.min <KeyRelease> ::moderne::jouer::majCadences
  bind $p.perso.inc <KeyRelease> ::moderne::jouer::majCadences
  majCadences
}

### Favourite time controls (::moderne::jouer::cadFavs, saved: list of
### {minutes increment}): chips after the presets, five per row; right
### click removes one
proc ::moderne::jouer::favorisCadence {p} {
  variable cadFavs
  if {![info exists cadFavs]} { set cadFavs {} }
  foreach x [winfo children $p.cad] { if {[string match f* [winfo name $x]]} { destroy $x } }
  set i 0
  foreach c $cadFavs {
    lassign $c m s
    set x $p.cad.f$i
    pastille $x "$m+$s" "★ [nomCadence $m $s]" [list ::moderne::jouer::cadenceChoisie $m $s]
    foreach y [list $x $x.a $x.b] {
      bind $y <Button-3> [list ::moderne::jouer::menuCadenceFav $i]
      if {[tk windowingsystem] eq "aqua"} { bind $y <Button-2> [list ::moderne::jouer::menuCadenceFav $i] }
    }
    catch {::utils::tooltip::Set $x [T "Cadence favorite (clic droit : la retirer)" "Favourite time control (right click: remove it)"]}
    grid $x -row [expr {2 + $i / 5}] -column [expr {$i % 5}] -sticky nsew -padx 3 -pady 3
    incr i
  }
}

proc ::moderne::jouer::ajouterCadenceFav {} {
  variable cadFavs
  variable w
  if {![info exists cadFavs]} { set cadFavs {} }
  set m $::moderne::toby::jeu(minutes)
  set s $::moderne::toby::jeu(inc)
  if {![string is integer -strict $m] || ![string is integer -strict $s] || $m < 1} { return }
  # (a preset is already a chip)
  set preset 0
  foreach {pm ps} {1 0 3 0 3 2 5 3 10 0 10 5 15 10 30 0 90 30} { if {$pm == $m && $ps == $s} { set preset 1 } }
  if {!$preset && [lsearch -exact $cadFavs [list $m $s]] < 0} { lappend cadFavs [list $m $s] }
  favorisCadence $w.f.corps
  majCadences
  catch {::options.write}
}

proc ::moderne::jouer::menuCadenceFav {i} {
  set m .jouer.menuCad
  catch {destroy $m}
  menu $m -tearoff 0
  $m add command -label [T "Retirer des favoris" "Remove from favourites"] -command [list ::moderne::jouer::retirerCadenceFav $i]
  tk_popup $m {*}[winfo pointerxy .jouer]
}

proc ::moderne::jouer::retirerCadenceFav {i} {
  variable cadFavs
  variable w
  set cadFavs [lreplace $cadFavs $i $i]
  favorisCadence $w.f.corps
  majCadences
  catch {::options.write}
}

### Bullet / Blitz / Rapid / Classical of a clock
proc ::moderne::jouer::nomCadence {m s} {
  if {![string is double -strict $m] || ![string is double -strict $s]} { return {} }
  if {$m * 60 + 40 * $s < 180} { return Bullet }
  set c [::moderne::toby::cadencePendule $m $s]
  return [dict get [T {Classical Classique Rapid Rapide Blitz Blitz} {Classical Classical Rapid Rapid Blitz Blitz}] $c]
}

### A chip: two lines (main, small), clickable
proc ::moderne::jouer::pastille {p texte sous cmd} {
  set fond [C surface]
  frame $p -background $fond -highlightthickness 1 -highlightbackground [C bordure] -cursor hand2 -pady 5
  label $p.a -text $texte -font font_Bold -background $fond -foreground [C texteFort]
  label $p.b -text $sous -font SibyJouerPetit -background $fond -foreground [C texteDoux]
  pack $p.a $p.b -side top
  foreach x [list $p $p.a $p.b] { bind $x <Button-1> $cmd }
}

proc ::moderne::jouer::marquerPastille {p on} {
  set fond [expr {$on ? [C accentFonce] : [C surface]}]
  $p configure -background $fond -highlightbackground [expr {$on ? [C accentFonce] : [C bordure]}]
  $p.a configure -background $fond -foreground [expr {$on ? "#ffffff" : [C texteFort]}]
  $p.b configure -background $fond -foreground [expr {$on ? "#dbefff" : [C texteDoux]}]
}

proc ::moderne::jouer::cadenceChoisie {m s} {
  set ::moderne::toby::jeu(minutes) $m
  set ::moderne::toby::jeu(inc) $s
  majCadences
}

proc ::moderne::jouer::cadencePerso {} {
  variable perso 1
  majCadences
  catch {focus .jouer.f.corps.perso.min}
}

### Highlights the chip of the current clock (else "Custom" and its fields)
proc ::moderne::jouer::majCadences {} {
  variable w
  variable perso
  set p $w.f.corps
  if {![winfo exists $p.cad]} { return }
  set m $::moderne::toby::jeu(minutes)
  set s $::moderne::toby::jeu(inc)
  set trouve 0
  set i 0
  foreach {pm ps} {1 0 3 0 3 2 5 3 10 0 10 5 15 10 30 0 90 30} {
    set on [expr {"$pm" eq "$m" && "$ps" eq "$s" && !([info exists perso] && $perso)}]
    if {$on} { set trouve 1 }
    marquerPastille $p.cad.p$i $on
    incr i
  }
  if {[info exists ::moderne::jouer::cadFavs]} {
    set i 0
    foreach c $::moderne::jouer::cadFavs {
      set on [expr {!$trouve && "[lindex $c 0]" eq "$m" && "[lindex $c 1]" eq "$s" && !([info exists perso] && $perso)}]
      if {$on} { set trouve 1 }
      if {[winfo exists $p.cad.f$i]} { marquerPastille $p.cad.f$i $on }
      incr i
    }
  }
  marquerPastille $p.cad.perso [expr {!$trouve}]
  $p.cad.perso.b configure -text [expr {$trouve ? "…" : "$m+$s"}]
  if {!$trouve} {
    if {![winfo ismapped $p.perso]} { pack $p.perso -side top -anchor w -pady {6 0} -after $p.cad }
  } else {
    pack forget $p.perso
  }
  set perso 0
}

### A level: section title, big number (+ a unit or a widget), slider
proc ::moderne::jouer::niveau {p titre var de a pas {unite {}}} {
  frame $p -background [C fond]
  section $p.l $titre 1
  pack $p.l -side top -fill x -pady {12 2}
  frame $p.v -background [C fond]
  label $p.v.n -textvariable $var -font SibyJouerGrand -background [C fond] -foreground [C texteFort]
  pack $p.v.n -side left
  if {$unite ne {}} {
    label $p.v.u -text $unite -background [C fond] -foreground [C texteDoux]
    pack $p.v.u -side left -padx {6 0} -pady {6 0}
  }
  pack $p.v -side top -fill x
  ttk::scale $p.s -from $de -to $a -orient horizontal -variable $var \
      -command [list ::moderne::jouer::arrondir $var $pas]
  # (the slider can write its value after the command, as a decimal:
  # "2900.0" was then shown, and read as no rating at all at the start of
  # the game: "Toby (0)", Yosha 2026-10-31)
  trace remove variable $var write [list ::moderne::jouer::entier $pas]
  trace add variable $var write [list ::moderne::jouer::entier $pas]
  pack $p.s -side top -fill x -pady {4 0}
  return $p
}

### A rating written as a decimal: back to a whole multiple of pas
proc ::moderne::jouer::entier {pas nom cle op} {
  if {$cle ne {}} { upvar 1 ${nom}($cle) v } else { upvar 1 $nom v }
  if {[info exists v] && [string is double -strict $v] && ![string is integer -strict $v]} {
    set v [expr {int(round($v / double($pas)) * $pas)}]
  }
}

proc ::moderne::jouer::arrondir {var pas v} {
  set r [expr {int(round($v / double($pas)) * $pas)}]
  # (compared as text: the slider writes "2900.0" at its end, equal in
  # value but shown with ".0")
  if {[set $var] ne $r} { set $var $r }
  if {$var eq "::moderne::toby::jeu(eloToby)"} { set ::moderne::toby::jeu(eloChoisi) 1 }
}

### Segmented choice: list of {value text tooltip}
proc ::moderne::jouer::segments {p var items {cmd {}}} {
  set style Toolbutton
  if {![catch {ttk::style layout Segment.Toolbutton} l] && $l ne {}} { set style Segment.Toolbutton }
  ttk::frame $p
  set i 0
  foreach it $items {
    lassign $it val texte tip
    ttk::radiobutton $p.s$i -text $texte -style $style -variable $var -value $val
    if {$cmd ne {}} { $p.s$i configure -command $cmd }
    pack $p.s$i -side left -padx 1 -fill x -expand 1
    if {$tip ne {}} { catch {::utils::tooltip::Set $p.s$i $tip} }
    incr i
  }
  return $p
}

### Start: initial position, board position (, odds, set up a position);
### with odds and set up: two rows of two
proc ::moderne::jouer::depart {p var {poser 1}} {
  if {!$poser} {
    segments $p $var [list [list initiale [T "Position initiale" "Initial position"]] \
                           [list actuelle [T "Position de l'échiquier" "Board position"]]]
    return $p
  }
  frame $p -background [C fond]
  set style Toolbutton
  if {![catch {ttk::style layout Segment.Toolbutton} l] && $l ne {}} { set style Segment.Toolbutton }
  frame $p.l -background [C fond]
  pack $p.l -side top -fill x
  foreach {x val fr en ligne col} {
      i initiale "Position initiale" "Initial position" 0 0
      a actuelle "Position de l'échiquier" "Board position" 0 1} {
    ttk::radiobutton $p.l.$x -text [T $fr $en] -style $style -variable $var -value $val
    grid $p.l.$x -row $ligne -column $col -sticky ew -padx 1 -pady 1
  }
  # (odds games removed for now, Yosha 2026-11-01: Toby predicts badly
  # with huge material differences; to come back later)
  if {[set $var] ni {initiale actuelle}} { set $var initiale }
  ttk::button $p.l.poser -text [T "Poser une position…" "Set up a position…"] -style $style -command {
    ::moderne::toby::jeuPoser
  }
  catch {::utils::tooltip::Set $p.l.poser [T "Poser une position sur l'échiquier, puis la jouer" "Set up a position on the board, then play it"]}
  grid $p.l.poser -row 1 -column 0 -columnspan 2 -sticky ew -padx 1 -pady 1
  grid columnconfigure $p.l 0 -weight 1 -uniform dep
  grid columnconfigure $p.l 1 -weight 1 -uniform dep
  return $p
}

### (no "Show the evaluation bars during the game" any more, Yosha
### 2026-11-01: as on Lichess, no evaluation while playing an engine)

################################################################################
### Toby
################################################################################

proc ::moderne::jouer::corpsToby {p} {
  cadences $p
  frame $p.niv -background [C fond]
  pack $p.niv -side top -fill x
  niveau $p.niv.toby [T "Niveau de Toby" "Toby's level"] ::moderne::toby::jeu(eloToby) 400 3000 50
  ttk::combobox $p.niv.toby.v.src -state readonly -width 15 -textvariable ::moderne::toby::jeu(source) \
      -values {FIDE {Lichess Classical} {Lichess Rapid} {Lichess Blitz} {Chess.com Rapid} {Chess.com Blitz}}
  catch {::utils::tooltip::Set $p.niv.toby.v.src [T "Le classement dans lequel s'entendent les deux Elo" "The rating list both ratings are in"]}
  pack $p.niv.toby.v.src -side left -padx {10 0} -pady {4 0}
  bind $p.niv.toby.v.src <<ComboboxSelected>> ::moderne::jouer::majBornes
  niveau $p.niv.moi [T "Ton Elo" "Your rating"] ::moderne::toby::jeu(eloMoi) 400 3000 50
  grid $p.niv.toby $p.niv.moi -sticky ew -padx {0 14}
  majBornes
  grid columnconfigure $p.niv 0 -weight 1 -uniform niv
  grid columnconfigure $p.niv 1 -weight 1 -uniform niv
  # several Toby engines: which one
  set noms [lmap e [moteurs toby] {lindex $e 1}]
  if {![info exists ::moderne::toby::jeu(moteur)] || $::moderne::toby::jeu(moteur) ni $noms} {
    set ::moderne::toby::jeu(moteur) [lindex $noms 0]
  }
  if {[llength $noms] > 1} {
    section $p.lm [T "Moteur" "Engine"]
    ttk::combobox $p.m -state readonly -width 30 -values $noms -textvariable ::moderne::toby::jeu(moteur)
    pack $p.m -side top -anchor w
  }
  section $p.ld [T "Départ" "Start"]
  depart $p.d ::moderne::toby::jeu(depart)
  pack $p.d -side top -fill x
}

################################################################################

proc ::moderne::jouer::corpsLeela {p} {
  set noms [lmap e [moteurs leela] {lindex $e 1}]
  if {![info exists ::moderne::jouer::leela] || $::moderne::jouer::leela ni $noms} {
    set ::moderne::jouer::leela [lindex $noms 0]
  }
  cadences $p
  section $p.lca [T "Calcul (nœuds par coup)" "Search (nodes per move)"]
  set tip [T "Nombre de positions que Leela examine par coup. 1 : elle joue à l'intuition, sans calculer, comme un super GM qui jouerait d'instinct ; plus le nombre monte, plus elle calcule et devient forte. ∞ : elle calcule selon la pendule." \
             "Number of positions Leela looks at per move. 1: it plays on intuition, without calculating, like a super GM playing on instinct; the higher the number, the more it calculates and the stronger it gets. ∞: it searches according to the clock."]
  segments $p.ca ::moderne::toby::jeu(noeuds) [list \
      [list 1 [T "1 • instinct" "1 • instinct"] $tip] [list 100 100 $tip] [list 1000 1000 $tip] [list 0 ∞ $tip]]
  pack $p.ca -side top -fill x
  section $p.lco [T "Contempt" "Contempt"]
  set tip [T "Leela se croit plus forte que toi : elle évite la nulle, garde la tension et prend des risques pour gagner. N'agit que si elle calcule (plus d'un nœud)." \
             "Leela assumes it is stronger than you: it avoids draws, keeps the tension and takes risks to win. Only works when it searches (more than one node)."]
  segments $p.co ::moderne::toby::jeu(contempt) [list \
      [list 0 [T "Objectif" "Objective"] $tip] [list 200 [T "Joue pour gagner" "Plays to win"] $tip] \
      [list 500 [T "Tout pour gagner" "All-out to win"] $tip]]
  pack $p.co -side top -fill x
  catch {::utils::tooltip::Set $p.lco $tip}
  frame $p.niv -background [C fond]
  pack $p.niv -side top -fill x
  niveau $p.niv.moi [T "Ton Elo" "Your rating"] ::moderne::toby::jeu(eloMoi) 400 3000 50
  catch {::utils::tooltip::Set $p.niv.moi.s [T "Sert à régler le contempt de Leela" "Used to set Leela's contempt"]}
  grid $p.niv.moi -sticky ew
  grid columnconfigure $p.niv 0 -weight 1
  if {[llength $noms] > 1} {
    section $p.lm [T "Moteur" "Engine"]
    ttk::combobox $p.m -state readonly -width 30 -values $noms -textvariable ::moderne::jouer::leela
    pack $p.m -side top -anchor w
  }
  section $p.ld [T "Départ" "Start"]
  depart $p.d ::moderne::toby::jeu(depart)
  pack $p.d -side top -fill x
  trace add variable ::moderne::toby::jeu(noeuds) write ::moderne::jouer::majContempt
  majContempt
}

### Contempt greyed out with 1 node (no search: it would do nothing)
proc ::moderne::jouer::majContempt {args} {
  set p .jouer.f.corps.co
  if {![winfo exists $p]} { return }
  set un [expr {$::moderne::toby::jeu(noeuds) eq "1"}]
  foreach x [winfo children $p] { $x state [expr {$un ? "disabled" : "!disabled"}] }
  .jouer.f.corps.lco configure -foreground [C [expr {$un ? "inactif" : "texteDoux"}]]
}

################################################################################
### Alter Ego (the widgets majInfo updates keep their names: info, info2,
### m.nAge, m.age, n.l, btn.ok, etoile)
################################################################################

proc ::moderne::jouer::corpsAlterEgo {p} {
  upvar #0 ::moderne::alterego::form form
  set ::moderne::alterego::w $p.ae
  frame $p.ae -background [C fond]
  pack $p.ae -side top -fill x
  set f [frame $p.ae.f -background [C fond]]
  pack $f -side top -fill x
  # the databases: the largest open one by default, usually Gaby
  set max -1
  set bases {}
  set form(base) [::moderne::prepa::baseParDefaut]
  for {set i 1} {$i <= [sc_base count total]} {incr i} {
    if {$i == [sc_info clipbase] || ![sc_base inUse $i]} { continue }
    lappend bases "$i : [::moderne::nomBase [sc_base filename $i]]"
    if {[sc_base numGames $i] > $max} { set max [sc_base numGames $i] ; set form(base) $i }
  }
  set form(baseTexte) "$form(base) : [::moderne::nomBase [sc_base filename $form(base)]]"
  # (the suggested level follows the clock's time control)
  foreach v {minutes inc} {
    trace remove variable ::moderne::toby::jeu($v) write ::moderne::alterego::penduleChangee
    trace add variable ::moderne::toby::jeu($v) write ::moderne::alterego::penduleChangee
  }

  # Player, database
  frame $f.qui -background [C fond]
  pack $f.qui -side top -fill x
  frame $f.qui.j -background [C fond]
  section $f.qui.j.l [T "Joueur·se" "Player"] 1
  pack $f.qui.j.l -side top -fill x -pady {12 5}
  ttk::entry $f.j -width 30 -textvariable ::moderne::alterego::form(joueur)
  pack $f.j -in $f.qui.j -side top -fill x
  ::moderne::suggestions::attacher $f.j ::moderne::alterego::suggestions ::moderne::alterego::joueurChoisi 1
  bind $f.j <Return> {::moderne::alterego::majInfo}
  bind $f.j <FocusOut> {+after 300 ::moderne::alterego::majInfo}
  frame $f.qui.b -background [C fond]
  section $f.qui.b.l [T "Dans la base" "In the database"] 1
  pack $f.qui.b.l -side top -fill x -pady {12 5}
  ttk::combobox $f.b -state readonly -width 18 -values $bases -textvariable ::moderne::alterego::form(baseTexte)
  pack $f.b -in $f.qui.b -side top -fill x
  catch {::utils::tooltip::Set $f.b [T "La base où chercher ses parties (son répertoire)" "The database holding their games (their repertoire)"]}
  bind $f.b <<ComboboxSelected>> {
    set ::moderne::alterego::form(base) [lindex $::moderne::alterego::form(baseTexte) 0]
    ::moderne::alterego::majInfo
  }
  grid $f.qui.j $f.qui.b -sticky ew
  grid columnconfigure $f.qui 0 -weight 3 -pad 14
  grid columnconfigure $f.qui 1 -weight 2

  # Favourites (★) and recent opponents: one click fills the settings
  frame $f.favs -background [C fond]
  pack $f.favs -side top -fill x -pady {8 0}
  majFavoris

  # Period
  section $f.lm [T "Époque" "Period"]
  set style Toolbutton
  if {![catch {ttk::style layout Segment.Toolbutton} l] && $l ne {}} { set style Segment.Toolbutton }
  ttk::frame $f.m
  pack $f.m -side top -fill x
  foreach {v fr en afr aen} {
    prime "Son meilleur niveau" "Their best level" "Son pic estimé" "Their estimated peak"
    actuel "Aujourd'hui" "Today" "Son niveau à sa dernière partie dans la base" "Their level at their last game in the database"
    age "À un âge" "At an age" "Son niveau à l'âge choisi" "Their level at the chosen age"} {
    ttk::radiobutton $f.m.$v -text [T $fr $en] -style $style -value $v \
        -variable ::moderne::alterego::form(mode) -command ::moderne::alterego::majInfo
    pack $f.m.$v -side left -padx 1 -fill x -expand 1
    catch {::utils::tooltip::Set $f.m.$v [T $afr $aen]}
  }
  ttk::spinbox $f.m.nAge -from 5 -to 100 -width 4 -textvariable ::moderne::alterego::form(age) \
      -command ::moderne::alterego::majInfo
  bind $f.m.nAge <KeyRelease> {after 300 ::moderne::alterego::majInfo}
  ttk::label $f.m.ans -text [T "ans" "years"]
  pack $f.m.nAge $f.m.ans -side left -padx {6 2}

  # Card of the player: photo, period, level (editable)
  set fond [C surface]
  frame $f.carte -background $fond -highlightthickness 1 -highlightbackground [C bordure] -padx 12 -pady 10
  pack $f.carte -side top -fill x -pady {12 0}
  label $f.info -wraplength 330 -justify left -anchor w -font font_Bold -text {} \
      -background $fond -foreground [C texteFort]
  label $f.info2 -wraplength 330 -justify left -anchor w -font SibyJouerPetit -text {} \
      -background $fond -foreground [C texteDoux]
  frame $f.n -background $fond
  ttk::spinbox $f.n.s -from 400 -to 3600 -increment 25 -width 5 -font SibyJouerGrand \
      -textvariable ::moderne::alterego::form(niveau)
  catch {::utils::tooltip::Set $f.n.s [T "Niveau de Toby quand la position sort de son répertoire (modifiable)" \
      "Toby's level once the position leaves their repertoire (editable)"]}
  label $f.n.l -text {} -font SibyJouerPetit -background $fond -foreground [C texteDoux]
  pack $f.n.s $f.n.l -side top -anchor e
  grid $f.info $f.n -in $f.carte -sticky w
  grid $f.info2 -in $f.carte -sticky w
  grid configure $f.n -rowspan 2 -sticky ne -padx {12 0}
  grid columnconfigure $f.carte 0 -weight 1

  cadences $p
  frame $p.niv -background [C fond]
  pack $p.niv -side top -fill x
  niveau $p.niv.moi [T "Ton Elo" "Your rating"] ::moderne::toby::jeu(eloMoi) 400 3000 50
  frame $p.niv.d -background [C fond]
  section $p.niv.d.l [T "Départ" "Start"] 1
  pack $p.niv.d.l -side top -fill x -pady {12 5}
  depart $p.niv.d.s ::moderne::alterego::form(depart) 0
  pack $p.niv.d.s -side top -fill x
  catch {::utils::tooltip::Set $p.niv.d.s [T "Depuis l'échiquier, son répertoire répond tant qu'il connaît la position" \
      "From the board, their repertoire answers as long as it knows the position"]}
  grid $p.niv.moi $p.niv.d -sticky new -padx {0 14}
  grid columnconfigure $p.niv 0 -weight 1 -uniform niv
  grid columnconfigure $p.niv 1 -weight 1 -uniform niv

  # (favourites: in the card, under the period)
  ttk::button $f.etoile -style Toolbutton -command ::moderne::alterego::basculerFavori
  grid $f.etoile -in $f.carte -row 2 -column 0 -sticky w -pady {6 0}
  # (hidden: majInfo greys it out while the ratings are computed)
  frame $f.btn
  ttk::button $f.btn.ok
  set ::moderne::alterego::aide [T \
      "Dans l'ouverture, son Alter Ego joue ses propres coups (tirés au sort selon leur fréquence dans ses parties) ; quand la position sort de son répertoire, Toby prend la suite à son niveau." \
      "In the opening, their Alter Ego plays their own moves (drawn according to how often they played them); once the position leaves their repertoire, Toby takes over at their level."]
  catch {::utils::tooltip::Set $f.carte $::moderne::alterego::aide}
  ::moderne::alterego::majInfo
  ::moderne::alterego::majEtoile
  bind $f.j <KeyRelease> {+::moderne::alterego::majEtoile}
  focus $f.j
}

### The favourite and recent opponents as chips (favourites first). Beyond
### 6, the last chip "+N" opens the others in a menu. Right click on a
### favourite: remove it.
proc ::moderne::jouer::majFavoris {} {
  set f $::moderne::alterego::w.f
  if {![winfo exists $f.favs]} { return }
  foreach x [winfo children $f.favs] { destroy $x }
  set liste {}
  foreach e $::moderne::alterego::favoris { lappend liste [list 1 $e] }
  foreach e $::moderne::alterego::recents {
    if {![::moderne::alterego::estFavori [lindex $e 0]]} { lappend liste [list 0 $e] }
  }
  if {![llength $liste]} {
    pack forget $f.favs
    return
  }
  if {![winfo ismapped $f.favs]} { catch {pack $f.favs -side top -fill x -pady {8 0} -after $f.qui} }
  set reste {}
  if {[llength $liste] > 6} {
    set reste [lrange $liste 5 end]
    set liste [lrange $liste 0 4]
  }
  set i 0
  foreach x $liste {
    lassign $x fav e
    set nom [string trim [lindex [split [lindex $e 0] ,] 0]]
    pastilleFavori $f.favs.b$i [expr {$fav ? "★ $nom" : $nom}] $fav
    bind $f.favs.b$i <Button-1> [list ::moderne::jouer::reprendre $e]
    if {$fav} { bind $f.favs.b$i <Button-3> [list ::moderne::jouer::menuFavori %W $e %X %Y] }
    catch {::utils::tooltip::Set $f.favs.b$i "[expr {$fav ? [T "Favori·te (clic droit : retirer)" "Favourite (right click: remove)"] : [T "Récent·e" "Recent"]}] : [::moderne::alterego::libelleEntree $e]"}
    pack $f.favs.b$i -side left -padx {0 6}
    incr i
  }
  if {[llength $reste]} {
    pastilleFavori $f.favs.plus "+[llength $reste] ▾" 0
    bind $f.favs.plus <Button-1> [list ::moderne::jouer::menuAutres %W $reste]
    pack $f.favs.plus -side left
  }
}

proc ::moderne::jouer::pastilleFavori {b texte fav} {
  label $b -text $texte -background [C surface] -foreground [expr {$fav ? [C texteFort] : [C texte]}] \
      -padx 10 -pady 3 -cursor hand2 -highlightthickness 1 -highlightbackground [C bordure]
  bind $b <Enter> [list %W configure -highlightbackground [C accent]]
  bind $b <Leave> [list %W configure -highlightbackground [C bordure]]
}

### "+N": the other favourites and recent opponents
proc ::moderne::jouer::menuAutres {b reste} {
  set m .jouer.autres
  catch {destroy $m}
  menu $m -tearoff 0
  foreach x $reste {
    lassign $x fav e
    $m add command -label "[expr {$fav ? "★ " : ""}][::moderne::alterego::libelleEntree $e]" \
        -command [list ::moderne::jouer::reprendre $e]
  }
  tk_popup $m [winfo rootx $b] [expr {[winfo rooty $b] + [winfo height $b]}]
}

proc ::moderne::jouer::menuFavori {b e X Y} {
  set m .jouer.fav
  catch {destroy $m}
  menu $m -tearoff 0
  $m add command -label [T "Retirer des favoris" "Remove from favourites"] -command [list ::moderne::jouer::retirerFavori $e]
  tk_popup $m $X $Y
}

proc ::moderne::jouer::retirerFavori {e} {
  set ::moderne::alterego::favoris [lsearch -all -inline -not -index 0 $::moderne::alterego::favoris [lindex $e 0]]
  ::moderne::alterego::majEtoile
  majFavoris
}

### A favourite or recent opponent: their settings, ready to play
proc ::moderne::jouer::reprendre {e} {
  lassign $e nom mode age couleur minutes inc
  set ::moderne::alterego::form(joueur) $nom
  set ::moderne::alterego::form(mode) $mode
  set ::moderne::alterego::form(age) $age
  set ::moderne::toby::jeu(minutes) $minutes
  set ::moderne::toby::jeu(inc) $inc
  ::moderne::alterego::majInfo
  ::moderne::alterego::majEtoile
  majCadences
}

################################################################################
### Start
################################################################################

proc ::moderne::jouer::lancer {couleur} {
  variable onglet
  # (the settings, your rating first, kept for next time even if Siby is
  # not closed normally)
  catch {::options.write}
  if {$couleur eq "hasard"} { set couleur [expr {rand() < 0.5 ? "white" : "black"}] }
  switch $onglet {
    toby {
      set ::moderne::toby::jeu(couleur) $couleur
      ::moderne::toby::jeuLancer
    }
    alterego {
      set f $::moderne::alterego::w.f
      if {[winfo exists $f.btn.ok] && [$f.btn.ok cget -state] eq "disabled"} { bell ; return }
      set ::moderne::alterego::form(couleur) $couleur
      ::moderne::alterego::lancer
    }
  }
}

### End Siby
