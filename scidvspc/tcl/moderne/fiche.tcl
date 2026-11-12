
###
### Siby: player profile (tab of the preparation)
###
### Inspired by ChessMonitor profiles: at a glance, what matters before
### playing someone.
###   - key figures: games, score, current and peak Elo, performance over
###     12 months, last game;
###   - results by color and by time control (classical / rapid / blitz);
###   - Elo curve (hover: date, Elo, tournament);
###   - activity per month, by time control (hover: month details);
###   - their openings (ECO codes) with White and with Black: count,
###     score, performance, last time;
###   - results by opponent strength;
###   - preparation notes, saved per player.
### The data comes from the games read by the preparation (prepa.tcl).
###

namespace eval ::moderne::fiche {
  variable courbe          ;# courbe(points): {x y date elo tournoi} for hovering
  array set courbe {}
  variable barres {}       ;# {x0 x1 text} for hovering over the activity
  variable nomNotes {}     ;# notes file of the displayed player
  variable copieNotes {}   ;# notes text, copied on each change
  variable notesModifiees 0
  variable ecoNoms         ;# cache of opening names
  array set ecoNoms {}
  variable fide {}         ;# {id card history} of the displayed player, or {}
}

proc ::moderne::fiche::T {fr en} { return [::moderne::tr $fr $en] }

### Colors: Siby theme, validated categories (dataviz tool,
### dark background #1e1c1a and light #ffffff)
proc ::moderne::fiche::couleur {role} {
  set sombre [expr {[::moderne::actif] && $::moderne::theme eq "sombre"}]
  switch -- $role {
    classique { return [expr {$sombre ? "#3987e5" : "#2a78d6"}] }
    rapide    { return [expr {$sombre ? "#d95926" : "#eb6834"}] }
    blitz     { return [expr {$sombre ? "#199e70" : "#1baf7a"}] }
    autre     { return [expr {$sombre ? "#6f6c68" : "#a8a5a0"}] }
    surface   { return [expr {[::moderne::actif] ? [::moderne::c champ] : "white"}] }
    texte     { return [expr {[::moderne::actif] ? [::moderne::c texte] : "black"}] }
    fort      { return [expr {[::moderne::actif] ? [::moderne::c texteFort] : "black"}] }
    doux      { return [expr {[::moderne::actif] ? [::moderne::c texteDoux] : "gray40"}] }
    grille    { return [expr {$sombre ? "#2b2b2b" : "#e6e4e0"}] }
  }
}

### Performance (approximate FIDE formula): average opponent Elo + dp(score)
proc ::moderne::fiche::perf {moyenneAdv p} {
  if {$p <= 0.0} { set dp -800 } elseif {$p >= 1.0} { set dp 800 } else {
    set dp [expr {-400.0 * log10(1.0 / $p - 1.0)}]
    if {$dp > 800} { set dp 800 } elseif {$dp < -800} { set dp -800 }
  }
  return [expr {round($moyenneAdv + $dp)}]
}

### Aggregate of games: {n gains nulles pertes scorePct perf derniere}
proc ::moderne::fiche::bilan {liste} {
  set n 0 ; set g 0 ; set d 0 ; set p 0 ; set somElo 0 ; set nElo 0 ; set pts 0.0 ; set der {}
  foreach pa $liste {
    set s [::moderne::prepa::scoreJoueur [dict get $pa res] [dict get $pa couleur]]
    if {$s eq {}} { continue }
    incr n
    if {$s == 1} { incr g } elseif {$s == 0.5} { incr d } else { incr p }
    set pts [expr {$pts + $s}]
    set e [dict get $pa elo]
    if {[string is integer -strict $e] && $e > 0} { incr somElo $e ; incr nElo }
    set der [::moderne::prepa::plusRecente [dict get $pa date] $der]
  }
  if {$n == 0} { return [list 0 0 0 0 {} {} {}] }
  set pct [expr {round(100.0 * $pts / $n)}]
  set pf {}
  if {$nElo > 0} { set pf [perf [expr {$somElo / double($nElo)}] [expr {$pts / $n}]] }
  return [list $n $g $d $p $pct $pf $der]
}

proc ::moderne::fiche::texteBilan {b} {
  lassign $b n g d p pct pf
  if {$n == 0} { return "–" }
  return "$n • $pct %  (+$g =$d −$p)"
}

################################################################################
### Building the tab
################################################################################

proc ::moderne::fiche::creer {f} {
  # Vertical scrolling: a canvas that contains the profile frame
  canvas $f.c -highlightthickness 0 -background [couleur surface]
  ttk::scrollbar $f.sb -orient vertical -command [list $f.c yview]
  $f.c configure -yscrollcommand [list $f.sb set]
  pack $f.sb -side right -fill y
  pack $f.c -side left -fill both -expand 1
  set i $f.c.in
  ttk::frame $i -padding 10
  $f.c create window 0 0 -window $i -anchor nw -tags interieur
  bind $i <Configure> [list $f.c configure -scrollregion [list 0 0 %w %h]]
  bind $f.c <Configure> [list $f.c itemconfigure interieur -width %w]
  foreach w [list $f.c $i] {
    bind $w <MouseWheel> "$f.c yview scroll \[expr {-%D / 120}\] units"
    bind $w <Button-4> [list $f.c yview scroll -3 units]
    bind $w <Button-5> [list $f.c yview scroll 3 units]
  }

  ttk::label $i.vide -padding 20 -text [T "Prépare un joueur ou une joueuse (en haut) pour afficher sa fiche." \
                                          "Prepare a player (top) to show their profile."]
  pack $i.vide -side top -anchor w

  # Key figures
  ttk::frame $i.cles
  foreach k {parties score elo perf derniere} {
    ttk::frame $i.cles.$k -padding {14 6}
    ttk::label $i.cles.$k.v -font font_H2 -text {}
    ttk::label $i.cles.$k.l -foreground [couleur doux] -text {}
    pack $i.cles.$k.v $i.cles.$k.l -side top -anchor w
    pack $i.cles.$k -side left
  }

  # Results by color and time control (also serves as the key figures table)
  ttk::label $i.tres -font font_Bold -text [T "Résultats par couleur et par cadence" "Results by colour and time control"]
  ttk::treeview $i.res -columns {classique rapide blitz toutes} -height 3 -selectmode none
  $i.res heading #0 -text {}
  $i.res column #0 -width 90 -stretch 0
  foreach {c fr en} {classique Classique Classical rapide Rapide Rapid blitz Blitz Blitz toutes Toutes All} {
    $i.res heading $c -text [T $fr $en]
    $i.res column $c -width 170 -anchor center
  }

  # Elo curve and activity
  ttk::label $i.telo -font font_Bold -text [T "Classement Elo (une courbe par cadence)" "Elo rating (one line per time control)"]
  # Clickable legend: a click hides or shows the curve again
  ttk::frame $i.legElo
  foreach c {classique rapide blitz} fr {Classique Rapide Blitz} en {Classical Rapid Blitz} {
    canvas $i.legElo.c$c -width 12 -height 12 -highlightthickness 0 -background [couleur $c] -cursor hand2
    ttk::label $i.legElo.l$c -text [T $fr $en] -cursor hand2
    pack $i.legElo.c$c -side left -padx {10 4}
    pack $i.legElo.l$c -side left
    foreach x [list $i.legElo.c$c $i.legElo.l$c] {
      bind $x <Button-1> [list ::moderne::fiche::basculerCourbe $i $c]
    }
    ::utils::tooltip::Set $i.legElo.l$c [T "Clic : masquer ou afficher cette courbe" "Click: hide or show this line"]
  }
  canvas $i.elo -height 190 -highlightthickness 0 -background [couleur surface]
  ttk::label $i.tact -font font_Bold -text [T "Activité (parties par mois)" "Activity (games per month)"]
  ttk::frame $i.leg
  foreach c {classique rapide blitz} fr {Classique Rapide Blitz} en {Classical Rapid Blitz} {
    canvas $i.leg.c$c -width 12 -height 12 -highlightthickness 0 -background [couleur $c] -cursor hand2
    ttk::label $i.leg.l$c -text [T $fr $en] -cursor hand2
    pack $i.leg.c$c -side left -padx {10 4}
    pack $i.leg.l$c -side left
    foreach x [list $i.leg.c$c $i.leg.l$c] {
      bind $x <Button-1> [list ::moderne::fiche::basculerCourbe $i $c]
    }
  }
  canvas $i.act -height 150 -highlightthickness 0 -background [couleur surface]
  bind $i.elo <Motion> [list ::moderne::fiche::survolElo $i.elo %x %y]
  bind $i.elo <Leave> [list $i.elo delete survol]
  bind $i.act <Motion> [list ::moderne::fiche::survolActivite $i.act %x]
  bind $i.act <Leave> [list $i.act delete survol]
  bind $i.elo <Configure> ::moderne::fiche::redessiner
  bind $i.act <Configure> ::moderne::fiche::redessiner

  # Openings (ECO) with each color
  ttk::frame $i.ouv
  foreach couleur {white black} titre [list [T "Ses ouvertures avec les Blancs" "Their openings as White"] \
                                             [T "Ses ouvertures avec les Noirs" "Their openings as Black"]] {
    set o $i.ouv.$couleur
    ttk::frame $o
    ttk::label $o.t -font font_Bold -text $titre
    ttk::treeview $o.tv -columns {n score perf der} -height 10 -selectmode none
    $o.tv heading #0 -text [T "Ouverture" "Opening"] -anchor w
    $o.tv column #0 -width 170 -stretch 1
    foreach {c fr en l} {n Parties Games 58 score Score Score 58 perf Perf Perf 50 der "Dernière" "Last" 88} {
      $o.tv heading $c -text [T $fr $en]
      $o.tv column $c -width $l -anchor e -stretch 0
    }
    ::moderne::tri::activer $o.tv
    pack $o.t -side top -anchor w -pady {8 2}
    pack $o.tv -side top -fill x
    pack $o -side left -fill both -expand 1 -padx {0 10}
  }

  # By opponent strength
  ttk::label $i.tforce -font font_Bold -text [T "Selon la force de l'adversaire (parties sur l'échiquier)" "By opponent strength (over-the-board games)"]
  ttk::treeview $i.force -columns {n score perf} -height 6 -selectmode none
  $i.force heading #0 -text [T "Elo de l'adversaire" "Opponent Elo"] -anchor w
  $i.force column #0 -width 160 -stretch 0
  foreach {c fr en} {n Parties Games score Score Score perf Perf Perf} {
    $i.force heading $c -text [T $fr $en]
    $i.force column $c -width 110 -anchor e -stretch 0
  }

  # Notes
  ttk::label $i.tnotes -font font_Bold -text [T "Notes de préparation (enregistrées automatiquement)" "Preparation notes (saved automatically)"]
  text $i.notes -height 8 -wrap word -undo 1 -background [couleur surface] -foreground [couleur fort] \
      -insertbackground [couleur fort] -relief flat -padx 8 -pady 6 -font font_Regular
  # Copy of the text on each change: on closing (<Destroy>), the
  # widget no longer exists, so this copy is written instead
  bind $i.notes <<Modified>> {::moderne::fiche::copierNotes %W}
  bind $i.notes <KeyRelease> {::moderne::fiche::copierNotes %W ; after cancel ::moderne::fiche::sauverNotes ; after 1500 ::moderne::fiche::sauverNotes}
  bind $i.notes <FocusOut> ::moderne::fiche::sauverNotes
  bind $i.notes <Destroy> ::moderne::fiche::sauverNotes
}

################################################################################
### Filling
################################################################################

### Site whose online ratings the profile shows: {} when there are
### over-the-board games (their FIDE Elo is shown), else the site with the
### most games ("Lichess" or "Chess.com")
proc ::moderne::fiche::siteRetenu {parties} {
  set nb {}
  foreach pa $parties {
    if {![dict exists $pa enligne] || ![dict get $pa enligne]} { return {} }
    dict incr nb [siteDe $pa]
  }
  set site {} ; set m 0
  dict for {k v} $nb { if {$v > $m} { set m $v ; set site $k } }
  return $site
}

proc ::moderne::fiche::siteDe {pa} {
  set t [string tolower [dict get $pa tournoi]]
  if {[string match lichess* $t]} { return Lichess }
  if {[string match chess.com* $t]} { return Chess.com }
  return {}
}

### Does game pa count for the ratings, performances and opponent strength?
proc ::moderne::fiche::compteElo {pa} {
  variable siteElo
  set enLigne [expr {[dict exists $pa enligne] && [dict get $pa enligne]}]
  if {![info exists siteElo] || $siteElo eq {}} { return [expr {!$enLigne}] }
  expr {$enLigne && [siteDe $pa] eq $siteElo}
}

### "2014-05" -> "2014-04" ({} if not a month)
proc ::moderne::fiche::moisAvant {m} {
  if {![regexp {^([0-9]{4})-([0-9]{2})$} $m -> a mm]} { return {} }
  scan $mm %d mm
  if {[incr mm -1] < 1} { set mm 12 ; incr a -1 }
  return [format %04d-%02d $a $mm]
}

### FIDE data of the player of these games: {id card history}, {} if
### the pack or the player's FIDE id is missing. The id: the WhiteFideId /
### BlackFideId header of their most recent over-the-board games
proc ::moderne::fiche::donneesFide {parties} {
  if {[catch {::moderne::fide::fichier fide_historique} f] || $f eq {}} { return {} }
  set vues 0
  foreach pa [lsort -decreasing -command ::moderne::comparerDates $parties] {
    if {[dict exists $pa enligne] && [dict get $pa enligne]} { continue }
    if {[incr vues] > 30} { break }
    set id [::moderne::fide::idPartie [dict get $pa base] [dict get $pa gnum] [dict get $pa couleur]]
    if {$id eq {}} { continue }
    set h [::moderne::fide::historique $id]
    if {![llength $h]} { continue }
    return [list $id [::moderne::fide::joueur $id] $h]
  }
  return {}
}

proc ::moderne::fiche::remplir {f joueur parties} {
  variable courbe
  set i $f.c.in
  sauverNotes
  foreach w [winfo children $i] { pack forget $w }
  if {![llength $parties]} {
    pack $i.vide -side top -anchor w
    return
  }
  set T ::moderne::fiche::T

  # Key figures
  set tout [bilan $parties]
  lassign $tout n g d p pct pf der
  set elos {}
  # Ratings: over-the-board games (FIDE Elo). With online games only (the
  # "Lichess" or "Chess.com" view), that site's ratings instead, never
  # mixed with another site's
  variable siteElo [siteRetenu $parties]
  foreach pa [lsort -command ::moderne::comparerDates $parties] {
    set e [dict get $pa sonElo]
    set cad [dict get $pa cadence]
    if {$cad eq {}} { set cad autre }
    # (online ratings are not mixed with FIDE Elos)
    if {![compteElo $pa]} { continue }
    if {[string is integer -strict $e] && $e > 0} { lappend elos [list [dict get $pa date] $e [dict get $pa tournoi] $cad] }
  }
  # Reference Elo: that of the classical games if there are any (standard
  # FIDE rating), otherwise that of all games
  set eloRef {}
  foreach e $elos { if {[lindex $e 3] eq "classique"} { lappend eloRef $e } }
  set libElo [T "Elo classique • max" "classical Elo • max"]
  if {![llength $eloRef]} { set eloRef $elos ; set libElo [T "Elo actuel • max" "current Elo • max"] }
  if {$siteElo ne {}} {
    # online: the rating of the time control with the most games
    set nb {}
    foreach e $elos { dict incr nb [lindex $e 3] }
    set cadMax {} ; set m 0
    dict for {k v} $nb { if {$v > $m} { set m $v ; set cadMax $k } }
    set eloRef [lsearch -all -inline -index 3 $elos $cadMax]
    set nomCad [dict get {classique {classique classical} rapide {rapide rapid} blitz {blitz blitz} autre {{} {}}} $cadMax]
    set libElo [T "Elo $siteElo [lindex $nomCad 0] • max" "$siteElo [lindex $nomCad 1] rating • max"]
  }
  set eloActuel [expr {[llength $eloRef] ? [lindex $eloRef end 1] : "–"}]
  set eloMax "–"
  foreach e $eloRef { if {$eloMax eq "–" || [lindex $e 1] > $eloMax} { set eloMax [lindex $e 1] } }
  # Official FIDE data (Gaby's players pack), over-the-board view: the
  # current rating and the real peak from the FIDE lists, and the curve
  # month by month (the games' Elos stay when the player is not found)
  variable fide {}
  set texteElo "$libElo $eloMax"
  if {$siteElo eq {}} {
    set fide [donneesFide $parties]
    # (no FIDE id in the games: the official lists before 2001 by name)
    if {$fide eq {}} {
      set avant {}
      catch {set avant [::moderne::fide::officielsAvant2001 $joueur]}
      if {[llength $avant]} { set fide [list {} {} [dict create classique $avant]] }
    }
    if {$fide ne {}} {
      lassign $fide id carte h
      set cadRef classique
      if {![dict exists $h classique]} { foreach k {rapide blitz} { if {[dict exists $h $k]} { set cadRef $k ; break } } }
      if {[dict exists $h $cadRef]} {
        lassign [::moderne::fide::pic [dict get $h $cadRef]] eloPic moisPic
        set eloActuel [lindex [dict get $h $cadRef] end 1]
        set champ [dict get {classique elo_std rapide elo_rapide blitz elo_blitz} $cadRef]
        if {$carte ne {} && [string is integer -strict [dict get $carte $champ]] && [dict get $carte $champ] > 0} {
          set eloActuel [dict get $carte $champ]
        }
        set nomCad [dict get {classique {classique classical} rapide {rapide rapid} blitz {blitz blitz}} $cadRef]
        set texteElo [T "Elo FIDE [lindex $nomCad 0] • max $eloPic ([::moderne::prepa::date [string map {- .} $moisPic]])" \
                        "FIDE [lindex $nomCad 1] rating • max $eloPic ([::moderne::prepa::date [string map {- .} $moisPic]])"]
        # the curve: one point per FIDE list (the month's rating)
        set elos {}
        foreach cad {classique rapide blitz} {
          if {![dict exists $h $cad]} { continue }
          set l [dict get $h $cad]
          # (only the changes are stored: the rating stays the same until
          # the next change, drawn as a step, and up to the last list)
          set fin {}
          if {$carte ne {}} { set fin [dict get $carte mois_liste] }
          for {set k 0} {$k < [llength $l]} {incr k} {
            lassign [lindex $l $k] m elo src
            # (before 2001: OlimpBase's reconstructed lists, credited)
            set lib [expr {$src eq "olimpbase" ? [T "liste reconstituée (OlimpBase, non ratifiée par la FIDE)" \
                "reconstructed list (OlimpBase, not ratified by FIDE)"] : [T "liste FIDE" "FIDE list"]}]
            lappend elos [list [string map {- .} $m].01 $elo $lib $cad]
            set suivant [expr {$k + 1 < [llength $l] ? [lindex $l [expr {$k + 1}] 0] : $fin}]
            # (every list is there before 2001: a gap means no official
            # rating, not the same one)
            if {$src eq "olimpbase" && $suivant ne {} && [scan $suivant %d-%d a2 m2] == 2 && [scan $m %d-%d a1 m1] == 2 \
                  && ($a2 - $a1) * 12 + $m2 - $m1 > 12} { set suivant {} }
            set veille [moisAvant $suivant]
            if {$veille ne {} && [string compare $veille $m] > 0} {
              lappend elos [list [string map {- .} $veille].01 $elo [T "liste FIDE" "FIDE list"] $cad]
            }
          }
        }
        set elos [lsort -index 0 $elos]
      }
    }
  }
  # Performance over the last 12 months (relative to their last game)
  set an [string range $der 0 3]
  set recentes {}
  if {[string is integer -strict $an]} {
    set limite "[expr {$an - 1}][string range $der 4 end]"
    foreach pa $parties {
      set dp [dict get $pa date]
      if {[regexp {^[0-9]{4}} $dp] && [string compare [string map {? 0} $dp] [string map {? 0} $limite]] >= 0} { lappend recentes $pa }
    }
  }
  # (perf. computed on over-the-board games: online ratings are not
  # FIDE Elos)
  set recentes [lmap pa $recentes {expr {[compteElo $pa] ? $pa : [continue]}}]
  set pf12 [lindex [bilan $recentes] 5]
  $i.cles.parties.v configure -text [::utils::thousands $n]
  set nEnLigne 0
  foreach pa $parties { if {[dict exists $pa enligne] && [dict get $pa enligne]} { incr nEnLigne } }
  $i.cles.parties.l configure -text [expr {$nEnLigne ? "[T "parties, dont" "games, incl."] $nEnLigne [T "en ligne" "online"]" : [T "parties" "games"]}]
  $i.cles.score.v configure -text "$pct %"
  $i.cles.score.l configure -text "+$g =$d −$p"
  $i.cles.elo.v configure -text $eloActuel
  $i.cles.elo.l configure -text $texteElo
  $i.cles.perf.v configure -text [expr {$pf12 eq {} ? "–" : $pf12}]
  $i.cles.perf.l configure -text "[T "perf. sur 12 mois" "12-month perf."] ([llength $recentes] [T parties games])"
  $i.cles.derniere.v configure -text [::moderne::prepa::date $der]
  $i.cles.derniere.l configure -text [T "dernière partie" "last game"]
  pack $i.cles -side top -fill x

  # Results by color and time control
  $i.res delete [$i.res children {}]
  foreach couleur {white black {}} lib [list [T Blancs White] [T Noirs Black] [T Total Total]] {
    set vals {}
    foreach cad {classique rapide blitz {}} {
      set l {}
      foreach pa $parties {
        if {$couleur ne {} && [dict get $pa couleur] ne $couleur} { continue }
        if {$cad ne {} && [dict get $pa cadence] ne $cad} { continue }
        lappend l $pa
      }
      lappend vals [texteBilan [bilan $l]]
    }
    $i.res insert {} end -text $lib -values $vals
  }
  pack $i.tres -side top -anchor w -pady {12 2}
  pack $i.res -side top -fill x

  # Curves
  set courbe(elos) $elos
  set courbe(parties) $parties
  pack $i.telo -side top -anchor w -pady {12 2}
  pack $i.legElo -side top -anchor w -pady {0 4}
  pack $i.elo -side top -fill x
  pack $i.tact -side top -anchor w -pady {12 2}
  pack $i.leg -side top -anchor w
  pack $i.act -side top -fill x
  after idle ::moderne::fiche::redessiner

  # Openings
  foreach couleur {white black} {
    set tv $i.ouv.$couleur.tv
    $tv delete [$tv children {}]
    array unset parEco
    foreach pa $parties {
      if {[dict get $pa couleur] ne $couleur} { continue }
      set e [string range [dict get $pa eco] 0 2]
      if {$e eq {}} { set e "?" }
      lappend parEco($e) $pa
    }
    set lignes {}
    foreach e [array names parEco] { lappend lignes [list $e [llength $parEco($e)]] }
    foreach l [lrange [lsort -integer -decreasing -index 1 $lignes] 0 14] {
      set e [lindex $l 0]
      lassign [bilan $parEco($e)] nn - - - pp pff dd
      $tv insert {} end -text "$e  [nomEco $e]" -values [list $nn "$pp %" $pff [::moderne::prepa::date $dd]]
    }
  }
  pack $i.ouv -side top -fill x -pady {6 0}

  # Opponent strength
  $i.force delete [$i.force children {}]
  foreach {min max lib} {2700 9999 "2700 +" 2600 2699 "2600 – 2699" 2500 2599 "2500 – 2599" 2400 2499 "2400 – 2499" 2200 2399 "2200 – 2399" 1 2199 "< 2200"} {
    set l {}
    foreach pa $parties {
      if {![compteElo $pa]} { continue }
      set e [dict get $pa elo]
      if {[string is integer -strict $e] && $e >= $min && $e <= $max} { lappend l $pa }
    }
    if {![llength $l]} { continue }
    lassign [bilan $l] nn - - - pp pff
    $i.force insert {} end -text $lib -values [list $nn "$pp %" $pff]
  }
  $i.tforce configure -text [expr {$siteElo eq {} ? [T "Selon la force de l'adversaire (parties sur l'échiquier)" "By opponent strength (over-the-board games)"] \
      : [T "Selon la force de l'adversaire (classement $siteElo)" "By opponent strength ($siteElo rating)"]}]
  pack $i.tforce -side top -anchor w -pady {12 2}
  pack $i.force -side top -anchor w

  # Notes
  pack $i.tnotes -side top -anchor w -pady {12 2}
  pack $i.notes -side top -fill x -pady {0 10}
  chargerNotes $i.notes $joueur
}

### Name of an opening from the ECO code (3 characters)
proc ::moderne::fiche::nomEco {e} {
  variable ecoNoms
  if {[info exists ecoNoms($e)]} { return $ecoNoms($e) }
  set nom {}
  catch {
    if {[regexp {\[([^\]]+)\]} [sc_eco summary $e 0] -> nom]} {}
  }
  set ecoNoms($e) $nom
  return $nom
}

################################################################################
### Elo curve and activity (drawn on Tk canvases)
################################################################################

proc ::moderne::fiche::redessiner {} {
  set w .prepaWin.nb.fiche.c.in
  if {![winfo exists $w.elo]} { return }
  catch {dessinerElo $w.elo}
  catch {dessinerActivite $w.act}
}

### SCID date "2024.05.17" -> decimal year
proc ::moderne::fiche::annee {d} {
  if {![regexp {^([0-9]{4})\.([0-9?]{2})\.([0-9?]{2})} $d -> a m j]} { return {} }
  if {![string is integer -strict $m]} { set m 6 }
  if {![string is integer -strict $j]} { set j 15 }
  scan $m %d m ; scan $j %d j
  return [expr {$a + ($m - 1) / 12.0 + ($j - 1) / 365.0}]
}

### Click on the Elo curve legend: hide / show a time control
proc ::moderne::fiche::basculerCourbe {i cad} {
  variable masque
  set masque($cad) [expr {!([info exists masque($cad)] && $masque($cad))}]
  foreach leg {legElo leg} {
    catch {$i.$leg.l$cad configure -foreground [expr {$masque($cad) ? [couleur doux] : [::moderne::c texte]}]}
    catch {$i.$leg.c$cad configure -background [expr {$masque($cad) ? [couleur grille] : [couleur $cad]}]}
  }
  redessiner
}

proc ::moderne::fiche::dessinerElo {c} {
  variable courbe
  $c delete all
  set W [winfo width $c] ; set H [winfo height $c]
  # One point per month and per time control: the median of the month's
  # Elos (sources sometimes record a different rating than the one for the
  # time control, which caused spikes)
  array set mois {}
  foreach e $courbe(elos) {
    if {![regexp {^([0-9]{4})\.([0-9]{2})} [lindex $e 0] -> a m]} { continue }
    # FIDE Elo: a game with no known time control counts as classical
    set cad [lindex $e 3]
    if {$cad eq "autre"} { set cad classique }
    if {[info exists ::moderne::fiche::masque($cad)] && $::moderne::fiche::masque($cad)} { continue }
    lappend mois($cad,$a.$m) $e
  }
  set pts {}
  foreach k [lsort [array names mois]] {
    set l [lsort -integer -index 1 $mois($k)]
    set med [lindex $l [expr {[llength $l] / 2}]]
    lassign [split $k ,] cad am
    lassign [split $am .] a m
    scan $m %d m
    set x [expr {$a + ($m - 0.5) / 12.0}]
    set tournoi [lindex $med 2]
    if {[llength $l] > 1} { append tournoi "  ([llength $l] [T "parties ce mois-là" "games that month"])" }
    lappend pts [list $x [lindex $med 1] "$a.[format %02d $m]" $tournoi $cad]
  }
  set pts [lsort -real -index 0 $pts]
  if {[llength $pts] < 2 || $W < 50} {
    $c create text 12 [expr {$H / 2}] -anchor w -fill [couleur doux] -font font_Small \
        -text [::moderne::fiche::T "Pas assez de parties avec un Elo." "Not enough rated games."]
    set courbe(points) {}
    return
  }
  set x0 [lindex $pts 0 0] ; set x1 [lindex $pts end 0]
  if {$x1 - $x0 < 0.1} { set x0 [expr {$x0 - 0.05}] ; set x1 [expr {$x1 + 0.05}] }
  set ymin 9999 ; set ymax 0
  foreach p $pts { set y [lindex $p 1] ; if {$y < $ymin} { set ymin $y } ; if {$y > $ymax} { set ymax $y } }
  # Bounds rounded to 25 points, at least 50 apart
  set ymin [expr {int(floor(($ymin - 10) / 25.0) * 25)}]
  set ymax [expr {int(ceil(($ymax + 10) / 25.0) * 25)}]
  if {$ymax - $ymin < 50} { incr ymax 25 ; incr ymin -25 }
  set g 48 ; set dr 14 ; set ht 10 ; set bas 22
  set sx [expr {($W - $g - $dr) / double($x1 - $x0)}]
  set sy [expr {($H - $ht - $bas) / double($ymax - $ymin)}]
  # Subtle grid: 4 horizontal lines, years on the x axis
  set pas [expr {max(25, int(ceil(($ymax - $ymin) / 4.0 / 25.0)) * 25)}]
  for {set v $ymin} {$v <= $ymax} {incr v $pas} {
    set y [expr {$H - $bas - ($v - $ymin) * $sy}]
    $c create line $g $y [expr {$W - $dr}] $y -fill [couleur grille]
    $c create text [expr {$g - 6}] $y -anchor e -text $v -fill [couleur doux] -font font_Small
  }
  # (one year in 1, 2, 5 or 10 labelled, so the years never touch)
  set largAn [expr {[font measure font_Small 2000] + 12}]
  set pasAn 1
  foreach k {1 2 5 10 20} { set pasAn $k ; if {$k * $sx >= $largAn} { break } }
  for {set a [expr {int(ceil($x0))}]} {$a <= $x1} {incr a} {
    set x [expr {$g + ($a - $x0) * $sx}]
    $c create line $x $ht $x [expr {$H - $bas}] -fill [couleur grille]
    if {$a % $pasAn == 0} {
      $c create text $x [expr {$H - $bas + 4}] -anchor n -text $a -fill [couleur doux] -font font_Small
    }
  }
  # One 2 px line per time control (classical, rapid and blitz Elos are
  # separate ratings); marker on the last point of each
  set courbe(points) {}
  foreach cad {classique rapide blitz} {
    set coords {}
    set morceau {}
    set xPrec {}
    foreach p $pts {
      if {[lindex $p 4] ne $cad} { continue }
      set x [expr {$g + ([lindex $p 0] - $x0) * $sx}]
      set y [expr {$H - $bas - ([lindex $p 1] - $ymin) * $sy}]
      # (one continuous line, like Lichess, even across months without
      # games: the best estimate between two known ratings)
      set xPrec [lindex $p 0]
      lappend morceau $x $y
      lappend coords $x $y
      lappend courbe(points) [list $x $y [lindex $p 2] [lindex $p 1] [lindex $p 3] $cad]
    }
    lappend morceaux $morceau
    foreach m $morceaux {
      if {[llength $m] >= 4} {
        $c create line {*}$m -fill [couleur $cad] -width 2 -joinstyle round
      } elseif {[llength $m] == 2} {
        lassign $m xm ym
        $c create oval [expr {$xm-2}] [expr {$ym-2}] [expr {$xm+2}] [expr {$ym+2}] -fill [couleur $cad] -outline {}
      }
    }
    set morceaux {}
    if {[llength $coords] >= 2} {
      lassign [lrange $coords end-1 end] xe ye
      $c create oval [expr {$xe-4}] [expr {$ye-4}] [expr {$xe+4}] [expr {$ye+4}] \
          -fill [couleur $cad] -outline [couleur surface] -width 2
    }
  }
}

proc ::moderne::fiche::survolElo {c x y} {
  variable courbe
  $c delete survol
  if {![info exists courbe(points)] || ![llength $courbe(points)]} { return }
  # Point closest to the pointer (horizontally, then vertically)
  set best {} ; set dist 1e9
  foreach p $courbe(points) {
    set dd [expr {abs([lindex $p 0] - $x) * 4 + abs([lindex $p 1] - $y)}]
    if {$dd < $dist} { set dist $dd ; set best $p }
  }
  lassign $best px py date elo tournoi cad
  set H [winfo height $c]
  $c create line $px 10 $px [expr {$H - 22}] -fill [couleur doux] -dash {2 3} -tags survol
  $c create oval [expr {$px-4}] [expr {$py-4}] [expr {$px+4}] [expr {$py+4}] \
      -fill [couleur $cad] -outline [couleur surface] -width 2 -tags survol
  set nomCad [expr {$cad eq "autre" ? [T "cadence inconnue" "unknown time control"] : $cad}]
  # (a point of the FIDE lists: no second line, the source goes without saying)
  set texte "[::moderne::prepa::date $date]  •  Elo $elo ($nomCad)"
  if {$tournoi ne {} && $tournoi ne [T "liste FIDE" "FIDE list"]} { append texte "\n$tournoi" }
  bulle $c $px $py $texte
}

### Tooltip on a canvas (text in a box, kept within the canvas)
proc ::moderne::fiche::bulle {c x y texte} {
  set W [winfo width $c]
  set t [$c create text 0 0 -anchor nw -text $texte -fill [couleur fort] -font font_Small -tags survol]
  lassign [$c bbox $t] a b cc d
  set lw [expr {$cc - $a + 12}] ; set lh [expr {$d - $b + 8}]
  set bx [expr {$x + 12}] ; set by [expr {$y - $lh - 8}]
  if {$bx + $lw > $W} { set bx [expr {$x - 12 - $lw}] }
  if {$by < 2} { set by [expr {$y + 12}] }
  set r [$c create rectangle $bx $by [expr {$bx + $lw}] [expr {$by + $lh}] \
      -fill [expr {[::moderne::actif] ? [::moderne::c fond] : "#ffffe0"}] -outline [couleur doux] -tags survol]
  $c coords $t [expr {$bx + 6}] [expr {$by + 4}]
  $c raise $t
}

proc ::moderne::fiche::dessinerActivite {c} {
  variable courbe
  variable barres
  $c delete all
  set barres {}
  set W [winfo width $c] ; set H [winfo height $c]
  # Counts per month and per time control
  array set nb {}
  set mois {}
  foreach pa $courbe(parties) {
    set d [dict get $pa date]
    if {![regexp {^([0-9]{4})\.([0-9]{2})} $d -> a m]} { continue }
    set k "$a.$m"
    set cad [dict get $pa cadence]
    # Unknown time control: classical by default (as for the Elo curve)
    if {$cad in {{} autre}} { set cad classique }
    if {[info exists ::moderne::fiche::masque($cad)] && $::moderne::fiche::masque($cad)} { continue }
    if {![info exists nb($k,$cad)]} { set nb($k,$cad) 0 }
    incr nb($k,$cad)
    if {$k ni $mois} { lappend mois $k }
  }
  if {![llength $mois] || $W < 50} { return }
  set mois [lsort $mois]
  # All months between the first and the last (36 most recent at most)
  lassign [split [lindex $mois 0] .] a m ; scan $m %d m
  lassign [split [lindex $mois end] .] af mf ; scan $mf %d mf
  set liste {}
  while {$a < $af || ($a == $af && $m <= $mf)} {
    lappend liste [format "%04d.%02d" $a $m]
    incr m ; if {$m > 12} { set m 1 ; incr a }
  }
  set liste [lrange $liste end-35 end]
  set max 1
  foreach k $liste {
    set t 0
    foreach cad {classique rapide blitz autre} { if {[info exists nb($k,$cad)]} { incr t $nb($k,$cad) } }
    if {$t > $max} { set max $t }
  }
  set g 48 ; set dr 14 ; set ht 10 ; set bas 22
  set n [llength $liste]
  set larg [expr {($W - $g - $dr) / double($n)}]
  set sy [expr {($H - $ht - $bas) / double($max)}]
  # Grid: 0, max/2, max
  foreach v [lsort -unique -integer [list 0 [expr {$max / 2}] $max]] {
    set y [expr {$H - $bas - $v * $sy}]
    $c create line $g $y [expr {$W - $dr}] $y -fill [couleur grille]
    $c create text [expr {$g - 6}] $y -anchor e -text $v -fill [couleur doux] -font font_Small
  }
  set i 0
  foreach k $liste {
    set x0 [expr {$g + $i * $larg + 1}]
    set x1 [expr {$g + ($i + 1) * $larg - 1}]
    if {$x1 - $x0 > 28} { set mil [expr {($x0 + $x1) / 2.0}] ; set x0 [expr {$mil - 14}] ; set x1 [expr {$mil + 14}] }
    set y [expr {$H - $bas}]
    set detail {}
    set total 0
    foreach cad {classique rapide blitz autre} {
      if {![info exists nb($k,$cad)] || !$nb($k,$cad)} { continue }
      set h [expr {$nb($k,$cad) * $sy}]
      # 2 px gap between stacked segments
      $c create rectangle $x0 [expr {$y - $h + 1}] $x1 $y -fill [couleur $cad] -outline {}
      set y [expr {$y - $h - 1}]
      incr total $nb($k,$cad)
      lappend detail "[string totitle [expr {$cad eq "autre" ? [T "cadence inconnue" "unknown"] : $cad}]] $nb($k,$cad)"
    }
    lassign [split $k .] a m
    if {$m eq "01" || $i == 0} {
      $c create text [expr {($x0 + $x1) / 2}] [expr {$H - $bas + 4}] -anchor n -text $a -fill [couleur doux] -font font_Small
    }
    lappend barres [list [expr {$g + $i * $larg}] [expr {$g + ($i + 1) * $larg}] \
        "$m/$a : $total [T parties games][expr {[llength $detail] ? "\n[join $detail { • }]" : ""}]"]
    incr i
  }
}

proc ::moderne::fiche::survolActivite {c x} {
  variable barres
  $c delete survol
  foreach b $barres {
    lassign $b a z texte
    if {$x >= $a && $x < $z} {
      $c create rectangle $a 10 $z [expr {[winfo height $c] - 22}] -outline [couleur doux] -dash {2 3} -tags survol
      bulle $c $x 40 $texte
      return
    }
  }
}

################################################################################
### Preparation notes (one text file per player)
################################################################################

proc ::moderne::fiche::fichierNotes {joueur} {
  regsub -all {[^[:alnum:]_-]+} $joueur _ nom
  set dir [file join $::scidUserDir data prepa]
  file mkdir $dir
  return [file join $dir "$nom.txt"]
}

proc ::moderne::fiche::copierNotes {t} {
  variable copieNotes
  variable notesModifiees
  if {![winfo exists $t] || ![$t edit modified]} { return }
  set copieNotes [$t get 1.0 end-1c]
  set notesModifiees 1
}

proc ::moderne::fiche::chargerNotes {t joueur} {
  variable nomNotes
  variable notesModifiees
  set notesModifiees 0
  set nomNotes [fichierNotes $joueur]
  $t delete 1.0 end
  if {[file exists $nomNotes]} {
    set f [open $nomNotes r]
    fconfigure $f -encoding utf-8
    $t insert end [read -nonewline $f]
    close $f
  }
  $t edit reset
  $t edit modified 0
}

proc ::moderne::fiche::sauverNotes {} {
  variable nomNotes
  variable copieNotes
  variable notesModifiees
  set t .prepaWin.nb.fiche.c.in.notes
  if {[winfo exists $t]} { copierNotes $t }
  if {$nomNotes eq {} || !$notesModifiees} { return }
  if {[catch {
    set f [open $nomNotes w]
    fconfigure $f -encoding utf-8
    puts -nonewline $f $copieNotes
    close $f
  }]} { return }
  set notesModifiees 0
  if {[winfo exists $t]} { $t edit modified 0 }
}

### End Siby
