
###
### Siby: Alter Ego — play against a real player
###
### You pick a player from a database (Gaby, a reference database…).
### In the opening, the Alter Ego plays the moves this player played in the
### position, drawn at random according to their frequency; when the position
### leaves their repertoire, Toby takes over, set to the player's level.
###
### Weighted repertoire: a game counts more the closer it is to the target
### year (its weight is halved every 3 years before it): the Alter Ego
### plays the player's openings from that period, not those from their
### early days.
###
### Minimums: a position is only followed if the player had it in at least
### 2 games; with 20 games or more, their moves played less than 5% of the
### time are discarded. Under 20 games in the period, the level is flagged
### as approximate (it can still be changed, as always).
###
### Three modes:
###   - Prime  : the player at their peak; repertoire from games up to
###              that year;
###   - Current: their last known level; all their games;
###   - Age    : the player at a chosen age (if their date of birth is
###              known); repertoire from games up to that age.
###
### The level comes from the estimated historical rating (base.sbc, built
### by the sbclassement tool next to Siby); the FIDE Elo is shown when it
### exists, but Toby plays at the estimated level (the one shown on the board).
###

namespace eval ::moderne::alterego {
  variable w .alterEgo
  variable actif 0          ;# Alter Ego game in progress
  variable dernier 0        ;# the game that just ended was an Alter Ego's
  variable sorti 0          ;# out of the repertoire: Toby plays
  variable idx              ;# idx(key): dict move -> number of games
  array set idx {}
  variable form             ;# window settings
  array set form {}
  variable profil {}        ;# dict: annees {annee {classement parties marge fide}...} naissance nom
  variable calcul           ;# calcul(base): sbclassement channel in progress
  array set calcul {}
  variable nomAffiche {}
  variable plies 40         ;# depth of the repertoire read (plies)
  variable minParties 2     ;# minimum games to follow a position
  variable minNiveau 20     ;# minimum games for a reliable level
  variable demiVie 3        ;# game weight: halved every 3 years
}

proc ::moderne::alterego::T {fr en} { return [::moderne::tr $fr $en] }

### Favourite and recent opponents (saved): {player mode age colour
### minutes increment}; one click replays (Play menu)
foreach _v {favoris recents} {
  if {![info exists ::moderne::alterego::$_v]} { set ::moderne::alterego::$_v {} }
}
unset _v

proc ::moderne::alterego::reglagesActuels {} {
  variable form
  return [list [string trim $form(joueur)] $form(mode) $form(age) $form(couleur) \
      $::moderne::toby::jeu(minutes) $::moderne::toby::jeu(inc)]
}

proc ::moderne::alterego::estFavori {nom} {
  foreach e $::moderne::alterego::favoris { if {[lindex $e 0] eq $nom} { return 1 } }
  return 0
}

### ☆ / ★ of the window: the current player into / out of the favourites
proc ::moderne::alterego::basculerFavori {} {
  variable w
  set e [reglagesActuels]
  set nom [lindex $e 0]
  if {$nom eq {}} { return }
  if {[estFavori $nom]} {
    set ::moderne::alterego::favoris [lsearch -all -inline -not -index 0 $::moderne::alterego::favoris $nom]
  } else {
    lappend ::moderne::alterego::favoris $e
  }
  majEtoile
  catch {::moderne::jouer::majFavoris}
}

proc ::moderne::alterego::majEtoile {} {
  variable w
  variable form
  if {![winfo exists $w.f.etoile]} { return }
  set fav [estFavori [string trim $form(joueur)]]
  $w.f.etoile configure -text [expr {$fav ? "★ [T "Favori·te" "Favourite"]" : "☆ [T "Ajouter aux favoris" "Add to favourites"]"}]
}

### Play menu: favourites, then recent opponents
proc ::moderne::alterego::menuFavoris {m} {
  $m delete 0 end
  set n 0
  foreach e $::moderne::alterego::favoris {
    $m add command -label "★ [libelleEntree $e]" -command [list ::moderne::alterego::rejouer $e]
    incr n
  }
  set recents {}
  foreach e $::moderne::alterego::recents {
    if {[estFavori [lindex $e 0]]} { continue }
    lappend recents $e
  }
  if {[llength $recents]} {
    if {$n} { $m add separator }
    foreach e $recents { $m add command -label [libelleEntree $e] -command [list ::moderne::alterego::rejouer $e] ; incr n }
  }
  if {!$n} {
    $m add command -label [T "(aucun·e : Jouer › Alter Ego, puis ☆)" "(none: Play › Alter Ego, then ☆)"] -state disabled
  }
}

proc ::moderne::alterego::libelleEntree {e} {
  lassign $e nom mode age couleur minutes inc
  set m [dict get [list prime [T prime prime] actuel [T actuel current] age "[T "à" "at"] $age [T ans years]"] $mode]
  set c [expr {$couleur eq "white" ? [T "tu as les Blancs" "you have White"] : [T "tu as les Noirs" "you have Black"]}]
  return "$nom ($m) • $minutes+$inc • $c"
}

### One click: the same opponent, with the same settings
proc ::moderne::alterego::rejouer {e} {
  variable form
  variable w
  lassign $e nom mode age couleur minutes inc
  set form(depart) initiale
  ouvrir
  if {![winfo exists $w]} { return }
  set form(joueur) $nom
  set form(mode) $mode
  set form(age) $age
  set form(couleur) $couleur
  set ::moderne::toby::jeu(minutes) $minutes
  set ::moderne::toby::jeu(inc) $inc
  majInfo
  lancer
}

### ------------------------------------------------------------------------
### Historical rating (base.sbc)

proc ::moderne::alterego::outil {} {
  set dir [file dirname [info nameofexecutable]]
  foreach n {sbclassement.exe sbclassement} {
    set f [file join $dir $n]
    if {[file executable $f]} { return $f }
  }
  return {}
}

proc ::moderne::alterego::fichierNsc {b} {
  set f "[file rootname [sc_base filename $b]].sbc"
  # (file of the NovaScid era: renamed)
  set ancien "[file rootname [sc_base filename $b]].nsc"
  if {![file exists $f] && [file exists $ancien]} { catch {file rename $ancien $f} }
  return $f
}

### File state: absent, perime (older than the database), ok.
### Gaby: the daily files make gaby.si4 newer every day, but one day of
### games barely moves the yearly ratings, and gaby.sbc is replaced (or
### set aside) together with the base by each big update (complete zip):
### an existing gaby.sbc is always that of the current complete base.
proc ::moderne::alterego::etatNsc {b} {
  set f [fichierNsc $b]
  if {![file exists $f]} { return absent }
  if {![catch {::moderne::gaby::estGaby $b} g] && $g} { return ok }
  set si4 "[file rootname [sc_base filename $b]].si4"
  if {[file exists $si4] && [file mtime $si4] > [file mtime $f]} { return perime }
  return ok
}

### Runs sbclassement in the background for database b
proc ::moderne::alterego::calculer {b} {
  variable calcul
  if {[info exists calcul($b)]} { return }
  set exe [outil]
  if {$exe eq {}} { return }
  set base [file rootname [sc_base filename $b]]
  if {[catch {open [list | $exe $base] r} f]} { return }
  fconfigure $f -blocking 0 -buffering line
  set calcul($b) $f
  fileevent $f readable [list ::moderne::alterego::lireCalcul $b $f]
  majInfo
}

proc ::moderne::alterego::lireCalcul {b f} {
  variable calcul
  variable form
  while {[gets $f l] >= 0} {
    # overall percentage (classical, then rapid and blitz)
    if {[regexp {^PROGRES 0 (\d+)} $l -> p]} {
      set form(progres) $p
    } elseif {[regexp {^PROGRES 1 (\d+) (\d+)} $l -> i n] && $n > 0} {
      set form(progres) [expr {int(40.0 * $i / $n)}]
    } elseif {[regexp {^PROGRES 2 (\d+)} $l -> it]} {
      set form(progres) [expr {min(99, 41 + int(1.5 * $it))}]
    }
  }
  if {[eof $f]} {
    catch {close $f}
    unset -nocomplain calcul($b)
    set form(progres) {}
    majInfo
  } else {
    majProgres
  }
}

### The player's lines in the .sbc (sorted by name, byte by byte):
### binary search without reading the whole file.
### Returns {foundName lines} (lines: {annee classement parties marge fide naissance ordinateur}...)
### in one time control (cadence 0 classical, 1 rapid, 2 blitz: the .sbc
### columns of that cadence); the years without games in it are left out.
### The profile (peak, age, repertoire years) is the classical one.
proc ::moderne::alterego::lireNsc {b nom {cadence 0}} {
  set fichier [fichierNsc $b]
  if {![file exists $fichier]} { return {} }
  set f [open $fichier rb]
  set taille [file size $fichier]
  set cible [encoding convertto utf-8 $nom]
  set res [chercherNom $f $taille $cible]
  if {![llength [lindex $res 1]]} {
    # database names in Latin-1
    set res [chercherNom $f $taille [encoding convertto iso8859-1 $nom]]
  }
  # (the same person only: the exact name, else its official spelling
  # (spelling.ssp, as sbclassement merged the names: "Morphy, Paul C" is
  # "Morphy, Paul"), never a namesake: "Greco, Gioachino" took "Greco,
  # Giovanni (*1958)" at 1449, Yosha 2026-11-11)
  if {![llength [lindex $res 1]]} {
    set officiel {}
    catch {set officiel [sc_name retrievename $nom]}
    if {$officiel ne {} && $officiel ne $nom} {
      set res [chercherNom $f $taille [encoding convertto utf-8 $officiel]]
    }
  }
  close $f
  lassign $res trouve lignes
  if {$trouve ne {}} { set trouve [encoding convertfrom utf-8 $trouve] }
  # columns after the name: year, classical rating games margin fide,
  # birth, rapid rating games margin fide, blitz rating games margin fide,
  # computer (1: an engine, by its name; absent in older files)
  set debut [lindex {1 6 10} $cadence]
  set gardees {}
  foreach x $lignes {
    set c [lrange $x $debut [expr {$debut + 3}]]
    if {[llength $c] == 4 && [lindex $c 0] > 0} {
      set ordi [lindex $x 14]
      lappend gardees [list [lindex $x 0] {*}$c [lindex $x 5] [expr {$ordi eq "1"}]]
    }
  }
  if {![llength $gardees]} { set trouve {} }
  return [list $trouve $gardees]
}

### Position (byte) of the first line whose name is >= target
proc ::moderne::alterego::debutNom {f taille cible} {
  set bas 0
  set haut $taille
  while {$haut - $bas > 8192} {
    set m [expr {($bas + $haut) / 2}]
    seek $f $m
    gets $f
    if {[gets $f l] < 0} { set haut $m ; continue }
    set n [lindex [split $l \t] 0]
    if {[string compare $n $cible] < 0} { set bas $m } else { set haut $m }
  }
  return $bas
}

proc ::moderne::alterego::chercherNom {f taille cible} {
  seek $f [debutNom $f $taille $cible]
  if {[tell $f] > 0} { gets $f }
  set lignes {}
  while {[gets $f l] >= 0} {
    set c [split $l \t]
    set n [lindex $c 0]
    set cmp [string compare $n $cible]
    if {$cmp < 0} { continue }
    if {$cmp > 0} { break }
    lappend lignes [lrange $c 1 end]
  }
  return [list [expr {[llength $lignes] ? $cible : {}}] $lignes]
}

### A first name compared: without a birth year "(*1958)", dots and
### spaces ("M. S." -> "MS")
proc ::moderne::alterego::prenomCourt {p} {
  regsub {\(\*?[0-9]+\)\s*$} $p {} p
  regsub -all {[.\s-]} $p {} p
  return $p
}

proc ::moderne::alterego::initiales {p} {
  set r {}
  foreach m [split [regsub {\(\*?[0-9]+\)\s*$} $p {}] { .-}] {
    if {$m ne {}} { append r [string toupper [string index $m 0]] }
  }
  return $r
}

proc ::moderne::alterego::chercherVariante {f taille cible} {
  set virgule [string first , $cible]
  if {$virgule < 1} { return {} }
  set famille [string range $cible 0 $virgule]
  # (the first name: the same one, possibly shortened, "M" or "M." for
  # "Magnus"; the same initial only took "Greco, Giovanni (*1958)" at 1449
  # for "Greco, Gioachino", Yosha 2026-11-11)
  set cherche [prenomCourt [string range $cible [expr {$virgule + 1}] end]]
  seek $f [debutNom $f $taille $famille]
  if {[tell $f] > 0} { gets $f }
  array set parNom {}
  while {[gets $f l] >= 0} {
    set c [split $l \t]
    set n [lindex $c 0]
    if {[string compare $n $famille] < 0} { continue }
    if {![string equal -length [string length $famille] $n $famille]} { break }
    set prenom [string trimleft [string range $n [string length $famille] end]]
    # (a namesake marked by Gaby, "Szabo, Laszlo (4)": another person)
    if {[regexp {\([0-9]{1,2}\)$} $n]} { continue }
    set p [prenomCourt $prenom]
    if {$cherche eq {} || $p eq {}} { continue }
    # (initials, "G.K." for "Garry": compared with the initials)
    if {[regexp {^[A-Z]{1,3}$} $cherche] || [regexp {^[A-Z]{1,3}$} $p]} {
      set ia [initiales $p] ; set ic [initiales $cherche]
      if {[regexp {^[A-Z]{1,3}$} $cherche]} { set ic $cherche }
      if {[regexp {^[A-Z]{1,3}$} $p]} { set ia $p }
      set k [expr {min([string length $ia], [string length $ic])}]
      if {![string equal -length $k $ia $ic]} { continue }
    } else {
      set k [expr {min([string length $p], [string length $cherche])}]
      if {![string equal -nocase -length $k $p $cherche]} { continue }
    }
    lappend parNom($n) [lrange $c 1 end]
  }
  set meilleur {}
  set max -1
  foreach n [array names parNom] {
    set tot 0
    foreach x $parNom($n) { incr tot [lindex $x 2] }
    if {$tot > $max} { set max $tot ; set meilleur $n }
  }
  if {$meilleur eq {}} { return {} }
  return [list $meilleur $parNom($meilleur)]
}

### Profile: years, peak (margin <= 100), last level, birth
proc ::moderne::alterego::profil {b nom} {
  lassign [lireNsc $b $nom] trouve lignes
  if {![llength $lignes]} { return {} }
  set naissance 0
  set ordinateur 0
  set pic {} ; set picR -1
  set dernier {}
  foreach x $lignes {
    lassign $x annee r n marge fide nai ordi
    if {$nai > 0} { set naissance $nai }
    if {$ordi eq "1"} { set ordinateur 1 }
    if {$marge <= 100 && $r > $picR} { set picR $r ; set pic $x }
  }
  if {$pic eq {}} {
    # no year reliable enough: the most played one
    set max -1
    foreach x $lignes { if {[lindex $x 2] > $max} { set max [lindex $x 2] ; set pic $x } }
  }
  # last level: the last reliable-enough year, otherwise the last one
  foreach x [lreverse $lignes] {
    if {[lindex $x 3] <= 150} { set dernier $x ; break }
  }
  if {$dernier eq {}} { set dernier [lindex $lignes end] }
  return [dict create nom $trouve lignes $lignes pic $pic dernier $dernier naissance $naissance ordinateur $ordinateur \
      premiere [lindex $lignes 0 0] derniere [lindex $lignes end 0]]
}

### Level for a year (the closest known year)
proc ::moderne::alterego::niveauEn {p annee} {
  set best {} ; set ecart 9999
  foreach x [dict get $p lignes] {
    set e [expr {abs([lindex $x 0] - $annee)}]
    # for equal distance, the most reliable year
    if {$e < $ecart || ($e == $ecart && [lindex $x 3] < [lindex $best 3])} { set ecart $e ; set best $x }
  }
  return $best
}

proc ::moderne::alterego::penduleChangee {args} {
  variable w
  if {![winfo exists $w]} { return }
  after cancel ::moderne::alterego::majInfo
  after 300 ::moderne::alterego::majInfo
}

### Time control of the game, from the clock: Classical, Rapid or Blitz
proc ::moderne::alterego::cadenceJeu {} {
  set cad Classical
  catch {set cad [::moderne::toby::cadencePendule $::moderne::toby::jeu(minutes) $::moderne::toby::jeu(inc)]}
  return $cad
}

### Level for Toby in the game's time control: the player's rapid or blitz
### rating of the nearest year (5 years at most) when the .sbc has one, else
### the classical level r. Returns {level cadence} (cadence: the one used)
proc ::moderne::alterego::niveauCadence {annee r} {
  # Always the classical level, whatever the clock (Yosha 2026-11-01:
  # classical is the only rating that is reliable over a career; most
  # games will be blitz or rapid, and the rapid / blitz estimates came out
  # far too high, e.g. Carlsen at 10: 2538 in blitz for 2061 classical).
  # Toby still gets the game's time control.
  return [list $r Classical]
  variable form
  variable profil
  set cad [cadenceJeu]
  set k [lsearch -exact {Classical Rapid Blitz} $cad]
  if {$k <= 0 || $profil eq {}} { return [list $r Classical] }
  set niveau $r
  set utilise Classical
  set ecart 99
  catch {
    foreach x [lindex [lireNsc $form(base) [dict get $profil nom] $k] 1] {
      set e [expr {abs([lindex $x 0] - $annee)}]
      if {$e < $ecart && $e <= 5} { set ecart $e ; set niveau [lindex $x 1] ; set utilise $cad }
    }
  }
  return [list $niveau $utilise]
}

### Official classical rating of the profile's player in year an ({} if none)
proc ::moderne::alterego::eloOfficiel {an} {
  variable form
  variable profil
  if {$profil eq {}} { return {} }
  set nom [dict get $profil nom]
  set r {}
  catch {
    set id [::moderne::fide::idNom $form(base) $nom]
    set r [::moderne::fide::eloAnnee [::moderne::fide::officiels $nom $id] $an]
  }
  return $r
}

### Target year and level according to the mode: {annee classement fide
### officiel} (officiel: the level is the official rating)
proc ::moderne::alterego::cible {} {
  variable form
  variable profil
  if {$profil eq {}} { return {} }
  switch -- $form(mode) {
    prime  { set x [dict get $profil pic] }
    actuel { set x [dict get $profil dernier] }
    age    {
      set nai [dict get $profil naissance]
      if {!$nai} { set x [dict get $profil pic] } else { set x [niveauEn $profil [expr {$nai + $form(age)}]] }
    }
  }
  lassign $x annee r n marge fide
  set anneeLigne $annee
  if {$form(mode) eq "age" && [dict get $profil naissance]} {
    set annee [expr {[dict get $profil naissance] + $form(age)}]
  }
  # The "FIDE" value is the average Elo written in the player's games of
  # that year: shown only for that very year and when it is plausible
  # (Carlsen at 10, year 2000: 2581 from misdated games, Yosha 2026-11-01)
  if {$anneeLigne != $annee || ![string is integer -strict $fide] || abs($fide - $r) > 400} { set fide 0 }
  # The official classical rating of that year (FIDE lists, OlimpBase
  # before 2001), when there is one, is the level (Yosha 2026-11-03): the
  # estimate only fills the years without one
  set officiel [eloOfficiel $annee]
  if {$officiel ne {}} { set r $officiel ; set fide $officiel }
  return [list $annee $r $fide [expr {$officiel ne {}}]]
}

### ------------------------------------------------------------------------
### Window

### The "Play" window (moderne/jouer.tcl), on Alter Ego
proc ::moderne::alterego::ouvrir {} {
  ::moderne::jouer::ouvrir alterego
}

### Name suggestions (like the preparation, in the chosen database)
proc ::moderne::alterego::suggestions {texte} {
  variable form
  set b $form(base)
  if {![sc_base inUse $b] || [string length $texte] < 2} { return {} }
  set courante [sc_base current]
  if {$courante != $b} { sc_base switch $b }
  set r {}
  catch {set r [sc_name match -souple player $texte 200]}
  if {$courante != $b} { sc_base switch $courante }
  set res {}
  foreach {n nom} $r { lappend res [list $n $nom] }
  set res [lsort -integer -decreasing -index 0 $res]
  set sortie {}
  foreach x [lrange $res 0 11] {
    lassign $x n nom
    lappend sortie [list "$nom  ([::utils::thousands $n])" $nom]
  }
  return $sortie
}

proc ::moderne::alterego::joueurChoisi {nom} {
  variable form
  set form(joueur) $nom
  majInfo
}

proc ::moderne::alterego::majProgres {} {
  variable w
  variable form
  if {![winfo exists $w.f.info2] || $form(progres) eq {}} { return }
  $w.f.info2 configure -text [T \
      "Classement historique de la base : $form(progres) %" \
      "Database's historical rating: $form(progres)%"]
}

### Updates the displayed level from the player and the mode
proc ::moderne::alterego::majInfo {} {
  variable w
  variable form
  variable profil
  variable calcul
  if {![winfo exists $w]} { return }
  set f $w.f
  set b $form(base)
  set etat [etatNsc $b]
  if {$etat ne "ok" && ![info exists calcul($b)]} {
    if {[outil] ne {}} { calculer $b }
  }
  # (an outdated file, after a database update, is used while the new
  # one is computed in the background)
  if {[info exists calcul($b)] && $etat eq "absent"} {
    set form(progres) [expr {$form(progres) eq {} ? 0 : $form(progres)}]
    $f.info configure -text {}
    majProgres
    $f.btn.ok configure -state disabled
    return
  }
  $f.btn.ok configure -state normal
  set nom [string trim $form(joueur)]
  set profil {}
  if {$nom ne {}} { set profil [profil $b $nom] }
  $f.m.nAge configure -state disabled
  if {$profil eq {}} {
    catch {$f.info configure -image {}}
    $f.info configure -text [expr {$nom eq {} ? {} : "$nom • [T "pas de classement" "no rating"]"}]
    catch {$f.info configure -image [::moderne::avatars::photo $nom 64] -compound left}
    # (playable all the same, at the level chosen: 2000 at first; Greco,
    # Yosha 2026-11-11)
    if {$nom ne {}} {
      set sig "$form(base)|$nom|sansElo"
      if {![info exists form(sig)] || $form(sig) ne $sig} {
        set form(sig) $sig
        set form(niveau) 2000
      }
      catch {$f.n.l configure -text [T "niveau choisi" "chosen level"] -foreground [::moderne::c texteDoux]}
    }
    $f.info2 configure -text [expr {$etat eq "ok" ? {} : [T \
        "Classement historique indisponible : sbclassement introuvable à côté de Siby." \
        "Historical rating unavailable: sbclassement not found next to Siby."]}]
    return
  }
  set nai [dict get $profil naissance]
  # "At an age" only when the birth year is known (greyed out otherwise)
  catch {
    $f.m.age state [expr {$nai ? "!disabled" : "disabled"}]
    ::utils::tooltip::Set $f.m.age [expr {$nai ? [T "Son niveau à l'âge choisi" "Their level at the chosen age"] \
        : [T "Date de naissance inconnue" "Birth year unknown"]}]
  }
  if {$nai} {
    $f.m.nAge configure -state [expr {$form(mode) eq "age" ? "normal" : "disabled"}] \
        -from [expr {max(5, [dict get $profil premiere] - $nai)}] -to [expr {[dict get $profil derniere] - $nai}]
    if {$form(mode) eq "age"} {
      set form(age) [expr {max([dict get $profil premiere] - $nai, min([dict get $profil derniere] - $nai, $form(age)))}]
    }
  } elseif {$form(mode) eq "age"} {
    set form(mode) prime
  }
  lassign [cible] annee r fide officiel
  set qui [dict get $profil nom]
  set age [expr {$nai ? " ([expr {$annee - $nai}] [T ans years])" : {}}]
  set titre [dict get {prime Prime actuel Dernier age Âge} $form(mode)]
  if {![::moderne::actif] || $::language ne "F"} { set titre [dict get {prime Prime actuel Latest age Age} $form(mode)] }
  set texte "$qui • $titre $annee$age • "
  if {$officiel} {
    append texte "[T "Elo FIDE" "FIDE rating"] $fide"
  } else {
    if {$fide > 0} { append texte "[T "Elo FIDE" "FIDE rating"] $fide • " }
    append texte "[T "niveau estimé" "estimated level"] $r"
  }
  $f.info configure -text $texte
  # (Siby: the player's photo, like Chess.com)
  catch {$f.info configure -image [::moderne::avatars::photo $qui 64] -compound left}
  set p [dict get $profil pic]
  # suggested level (editable); warning if few games
  # (in the clock's time control: rapid or blitz rating when known)
  lassign [niveauCadence $annee $r] rCad cadUtilisee
  set sig "$form(base)|$qui|$form(mode)|$annee|$cadUtilisee"
  if {![info exists form(sig)] || $form(sig) ne $sig} {
    set form(sig) $sig
    set form(niveau) [expr {max(400, min(3600, $rCad))}]
  }
  set nb 0
  foreach x [dict get $profil lignes] {
    if {$form(mode) eq "actuel" || [lindex $x 0] <= $annee} { incr nb [lindex $x 2] }
  }
  variable minNiveau
  if {$officiel} {
    $f.n.l configure -text [T "Elo FIDE" "FIDE rating"] -foreground [::moderne::c texteDoux]
  } elseif {$nb < $minNiveau} {
    $f.n.l configure -text [T "peu de parties ($nb) : approximatif" \
        "few games ($nb): approximate"] -foreground #e0a040
  } else {
    set mot [T "estimé" "estimated"]
    if {$cadUtilisee ne "Classical"} {
      append mot " ([dict get [T {Rapid rapide Blitz blitz} {Rapid rapid Blitz blitz}] $cadUtilisee])"
    }
    $f.n.l configure -text $mot -foreground [::moderne::c texteDoux]
  }
  $f.info2 configure -text [T \
      "[dict get $profil premiere]–[dict get $profil derniere] • pic [lindex $p 1] ([lindex $p 0]) • répertoire jusqu'en $annee" \
      "[dict get $profil premiere]–[dict get $profil derniere] • peak [lindex $p 1] ([lindex $p 0]) • repertoire up to $annee"]
}

### ------------------------------------------------------------------------
### Game

### Repertoire: the player's moves, with the color played by the Alter
### Ego, in their games up to the target year
proc ::moderne::alterego::chargerRepertoire {b nom couleur jusqua} {
  variable idx
  variable plies
  array unset idx
  array set idx {}
  set courante [sc_base current]
  if {$courante != $b} { sc_base switch $b }
  set n 0
  set erreur {}
  if {[catch {
    set op RESET
    foreach v [variantes $nom] {
      set motif "\"[string map {\\ \\\\ * \\* ? \\? \[ \\\[ \] \\\]} $v]\""
      sc_search header -[expr {$couleur eq "white" ? "white" : "black"}] $motif -filter $op
      set op OR
    }
    sc_search header -date [list 0000.00.00 "$jusqua.12.31"] -filter AND
    set nb [sc_filter count]
    if {$nb > 0} {
      variable demiVie
      foreach ligne [split [string trimright [sc_game list 1 $nb "g*\tS*\td*"] \n] \n] {
        lassign [split $ligne \t] gnum depart date
        # Weight: games close to the target year count more (halved
        # every "demiVie" years): it plays as in that period
        set annee [string range [string trim $date] 0 3]
        set poids 1.0
        if {[string is integer -strict $annee] && $annee > 0} {
          set poids [expr {pow(0.5, max(0, $jusqua - $annee) / double($demiVie))}]
        }
        set gnum [string trim $gnum]
        if {![string is integer -strict $gnum] || [string trim $depart] eq "S"} { continue }
        set positions [lrange [sc_game boards $gnum] 0 $plies]
        set np [llength $positions]
        for {set i 0} {$i + 1 < $np} {incr i} {
          set pos [lindex $positions $i 1]
          # (only the positions where it is the player's turn to move)
          set trait [expr {[string index $pos 65] eq "w" ? "white" : "black"}]
          if {$trait ne $couleur} { continue }
          set cle [::moderne::biblio::cle $pos]
          set coup [lindex $positions [expr {$i + 1}] 0]
          # {games weight}
          set v {0 0.0}
          if {[info exists idx($cle)] && [dict exists $idx($cle) $coup]} { set v [dict get $idx($cle) $coup] }
          dict set idx($cle) $coup [list [expr {[lindex $v 0] + 1}] [expr {[lindex $v 1] + $poids}]]
        }
        incr n
      }
    }
  } err]} { set erreur $err }
  catch {sc_filter reset}
  if {$courante != $b} { sc_base switch $courante }
  if {$erreur ne {}} { error $erreur }
  return $n
}

### Spellings of the same player in the current database: same surname,
### and one first name a prefix of the other ("G" / "Gary", but not
### "Georgy" / "Gary")
proc ::moderne::alterego::variantes {nom} {
  # (the same person only: the names of the database with the same
  # official spelling (spelling.ssp), as the rating; never a namesake,
  # Yosha 2026-11-11)
  set res [list $nom]
  set virgule [string first , $nom]
  if {$virgule < 1} { return $res }
  set officiel {}
  catch {set officiel [sc_name retrievename $nom]}
  if {$officiel eq {}} { return $res }
  set r {}
  catch {set r [sc_name match player "[string range $nom 0 $virgule]" 300]}
  foreach {nb v} $r {
    if {$v eq $nom} { continue }
    set o {}
    catch {set o [sc_name retrievename $v]}
    if {$o eq $officiel} { lappend res $v }
  }
  return $res
}

proc ::moderne::alterego::lancer {} {
  variable w
  variable form
  variable profil
  variable actif
  variable sorti
  variable nomAffiche
  if {$profil eq {}} { catch majInfo }
  # (rematch: no window, the main one)
  set pw [expr {[winfo exists $w] ? $w : "."}]
  set nomBase [string trim $form(joueur)]
  if {$profil eq {} && $nomBase eq {}} {
    tk_messageBox -icon info -parent $pw -title "Alter Ego" -message [T \
        "Choisis un joueur ou une joueuse de la base." "Choose a player from the database."]
    return
  }
  if {$profil ne {}} {
    lassign [cible] annee r fide
  } else {
    # (no rating: all their games, the level chosen)
    set annee 9999 ; set r 2000 ; set fide 0
    set sansProfil 1
    set profil [dict create nom $nomBase lignes {} pic {} dernier {} naissance 0 ordinateur 0 premiere 0 derniere 9999]
  }
  # The Alter Ego plays the opposite color
  set saCouleur [expr {$form(couleur) eq "white" ? "black" : "white"}]
  busyCursor $pw
  update idletasks
  # (Current mode: up to their last game in the database)
  set jusqua [expr {$form(mode) eq "actuel" ? max($annee, [dict get $profil derniere]) : $annee}]
  if {[catch {chargerRepertoire $form(base) $nomBase $saCouleur $jusqua} n]} {
    unbusyCursor $pw
    tk_messageBox -icon error -parent $pw -title "Alter Ego" -message $n
    return
  }
  unbusyCursor $pw
  if {[info exists sansProfil] && !$n} {
    set profil {}
    tk_messageBox -icon info -parent $pw -title "Alter Ego" -message [T \
        "Aucune partie de $nomBase dans la base." "No games of $nomBase in the database."]
    return
  }
  set qui [dict get $profil nom]
  set court [lindex [split $qui ,] 0]
  # (who and which year, for the players' rows: photo, title, "Carlsen ·
  # Alter Ego 2013"; kept in the game's headers, Yosha 2026-11-09)
  variable nomComplet $qui
  variable anneeJeu [expr {$annee == 9999 ? {} : $annee}]
  set nomAffiche [expr {$annee == 9999 ? $court : "$court • $annee"}]
  if {$fide > 0} { append nomAffiche " • FIDE $fide" }
  # (an engine, tagged in the .sbc: said, Yosha 2026-11-05)
  if {[dict exists $profil ordinateur] && [dict get $profil ordinateur]} { append nomAffiche " • [T ordinateur computer]" }
  set ::moderne::toby::jeu(couleur) $form(couleur)
  set niveau [lindex [niveauCadence $annee $r] 0]
  if {[string is integer -strict $form(niveau)]} { set niveau $form(niveau) }
  set ::moderne::toby::jeu(eloToby) [expr {max(400, min(3600, $niveau))}]
  set ::moderne::toby::jeu(source) FIDE
  set ::moderne::toby::jeu(depart) $form(depart)
  if {![info exists ::moderne::toby::jeu(barres)]} { set ::moderne::toby::jeu(barres) 0 }
  set noms [lmap e [::moderne::toby::moteursToby] {lindex $e 1}]
  if {![info exists ::moderne::toby::jeu(moteur)] || $::moderne::toby::jeu(moteur) ni $noms} {
    set ::moderne::toby::jeu(moteur) [lindex $noms 0]
  }
  set sorti 0
  set actif 1
  set form(parties) $n
  # recent opponents (the last 6)
  set e [reglagesActuels]
  set ::moderne::alterego::recents [lrange [concat [list $e] \
      [lsearch -all -inline -not -index 0 $::moderne::alterego::recents [lindex $e 0]]] 0 5]
  catch {destroy $w}
  if {[info exists sansProfil]} { set profil {} }
  ::moderne::toby::jeuLancer
}

### Called by ::sergame::engineGo when it is the Alter Ego's turn to move:
### a repertoire move (SAN), or {} (Toby plays)
proc ::moderne::alterego::coup {} {
  variable actif
  variable sorti
  variable idx
  if {!$actif || $sorti} { return {} }
  set cle [::moderne::biblio::cle [sc_pos board]]
  if {![info exists idx($cle)]} {
    set sorti 1
    return {}
  }
  set total 0
  set poidsTotal 0.0
  dict for {c v} $idx($cle) { incr total [lindex $v 0] ; set poidsTotal [expr {$poidsTotal + [lindex $v 1]}] }
  # Minimums: a position seen in a single game is no longer "their
  # repertoire"; with enough games, moves played less than 5% of the
  # time (one-off tries, blunders) are discarded
  variable minParties
  if {$total < $minParties} { set sorti 1 ; return {} }
  # (draw by weight: recent moves come up more often)
  set coups {}
  set somme 0.0
  dict for {c v} $idx($cle) {
    lassign $v nb p
    if {$total >= 20 && $p < 0.05 * $poidsTotal} { continue }
    lappend coups $c $p
    set somme [expr {$somme + $p}]
  }
  set t [expr {rand() * $somme}]
  set choix {}
  foreach {c p} $coups {
    if {$t < $p} { set choix $c ; break }
    set t [expr {$t - $p}]
  }
  if {$choix eq {} && [llength $coups]} { set choix [lindex $coups end-1] }
  if {$choix eq {}} { set sorti 1 ; return {} }
  # Short human thinking time (their clock is running)
  set ms [expr {600 + int(rand() * 1400)}]
  set ::moderne::alterego::attente 0
  after $ms {set ::moderne::alterego::attente 1}
  vwait ::moderne::alterego::attente
  if {![catch {::moderne::jeu::bloque} b] && $b} { return {} }
  # (the position may have changed during the wait: takeback, resignation…)
  if {[::moderne::biblio::cle [sc_pos board]] ne $cle} { return {} }
  return $choix
}

### Game over, new game against Toby alone: no more Alter Ego. finPartie 1
### (the game just ended): the Alter Ego remembered for Rematch and Play
### again (they came after the end and started Toby alone, Yosha 2026-11-09)
proc ::moderne::alterego::arreter {{finPartie 0}} {
  variable actif
  variable dernier
  set dernier [expr {$finPartie && $actif}]
  set actif 0
}

### The Alter Ego of side coul (White | Black) of the game on the board:
### {name for the photo and title, name shown}, {} if it is not one
proc ::moderne::alterego::joueur {coul} {
  set nom [sc_game tags get $coul]
  if {![string match "Alter Ego*" $nom]} { return {} }
  set qui {} ; set an {}
  foreach {t v} [sc_game tags get Extra] {
    if {$t eq "AlterEgo"} { set qui $v }
    if {$t eq "AlterEgoYear"} { set an $v }
  }
  # (the game just starting: its headers come after the panel)
  variable actif
  if {$qui eq {} && $actif && [info exists ::moderne::alterego::nomComplet]} {
    set qui $::moderne::alterego::nomComplet
    set an $::moderne::alterego::anneeJeu
  }
  if {$qui eq {}} { return {} }
  set court [lindex [split $qui ,] 0]
  return [list $qui [string trim "$court · Alter Ego $an"]]
}

### End Siby
