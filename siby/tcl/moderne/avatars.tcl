###
### Siby: players' avatars: a square photo, and the player's card on hover.
### The title (GM, IM…) is text next to the name, as on Lichess (a badge
### drawn on a 43-pixel photo is never sharp; Yosha 2026-11-05).
###
### The photos and cards come from Gaby's players pack, unzipped next to
### gaby.si4 (format: docs/PLAYERS_PACK.md of the ultrabase repository):
###   gaby_joueurs/gaby_names.tsv  name as shown in Gaby TAB Qid
###   gaby_joueurs/index.txt       normalised name key TAB Qid (see cles)
###   gaby_joueurs/translit.txt    characters folded by the keys
###   gaby_joueurs/joueurs.jsonl   one card per player (title, federation,
###                                years, Wikipedia links, photo credit)
###   gaby_joueurs/photos/<Qid>.png, silhouette.png, VERSION
### The pack is updated with Gaby (entry "joueurs" of its manifest, see
### ::moderne::avatars::verifierPaquet). Without the pack: no photo.
###

namespace eval ::moderne::avatars {
  variable index        ;# index(key) = Qid
  variable noms         ;# noms(name as shown in Gaby) = Qid
  variable fiches       ;# fiches(Qid) = raw JSON line of the card
  variable charge {}    ;# folder of the pack loaded
  variable translit {}
}

proc ::moderne::avatars::T {fr en} { return [::moderne::tr $fr $en] }

### Folder of the players pack (next to Gaby), empty if absent
proc ::moderne::avatars::dossier {} {
  set g {}
  catch {set g [::moderne::gaby::trouverFichier]}
  if {$g eq {}} { return {} }
  set d [file join [file dirname $g] gaby_joueurs]
  if {[file isdirectory $d]} { return $d }
  return {}
}

proc ::moderne::avatars::lignes {f} {
  set c [open $f r]
  fconfigure $c -encoding utf-8
  set l [split [read $c] \n]
  close $c
  return $l
}

proc ::moderne::avatars::charger {} {
  variable index
  variable noms
  variable fiches
  variable charge
  variable translit
  set d [dossier]
  if {$d eq $charge && [array exists index]} { return }
  set charge $d
  array unset index ; array set index {}
  array unset noms ; array set noms {}
  array unset fiches ; array set fiches {}
  set translit {}
  if {$d eq {}} { return }
  catch {
    foreach l [lignes [file join $d translit.txt]] {
      if {[llength $l] == 2} { lappend translit [lindex $l 0] [lindex $l 1] }
    }
  }
  catch {
    foreach l [lignes [file join $d index.txt]] {
      set p [split $l \t]
      if {[llength $p] == 2 && ![info exists index([lindex $p 0])]} { set index([lindex $p 0]) [lindex $p 1] }
    }
  }
  catch {
    foreach l [lignes [file join $d gaby_names.tsv]] {
      set p [split $l \t]
      if {[llength $p] == 2} { set noms([lindex $p 0]) [lindex $p 1] }
    }
  }
  # (cards read when needed: only the line is kept)
  catch {
    foreach l [lignes [file join $d joueurs.jsonl]] {
      if {[regexp {"qid"\s*:\s*"(Q[0-9]+)"} $l -> q]} { set fiches($q) $l }
    }
  }
}

### The pack changed (update): read again, images made again
proc ::moderne::avatars::recharger {} {
  variable charge
  set charge {}
  catch {array unset ::moderne::avatars::index}
  foreach img [image names] {
    if {[string match ::moderne::avatars::img_* $img]} { catch {image delete $img} }
  }
  charger
}

### Keys of a name: its words in lower case, without accents, sorted
### ("Carlsen, Magnus" = "Magnus Carlsen" -> "carlsen magnus"), and the
### surname with the first initial ("carlsen m"), for "Carlsen, M."
proc ::moderne::avatars::cles {nom} {
  variable translit
  set s [string tolower [string map $translit $nom]]
  regsub -all {[^a-z0-9]+} $s { } s
  set mots [lsort -unique [lsearch -all -inline -not -exact [split [string trim $s]] {}]]
  if {![llength $mots]} { return {} }
  set l [list [join $mots " "]]
  # surname: before the comma ("Carlsen, Magnus"), else the last word
  set brut [string tolower [string map $translit $nom]]
  if {[string first , $brut] >= 0} {
    set nomFamille [string trim [lindex [split $brut ,] 0]]
    set prenom [string trim [lindex [split $brut ,] 1]]
  } else {
    set w [split [string trim $brut]]
    set nomFamille [lindex $w end]
    set prenom [lindex $w 0]
  }
  regsub -all {[^a-z0-9 ]+} $nomFamille { } nomFamille
  regsub -all {[^a-z]} $prenom {} prenom
  if {$prenom ne {} && $nomFamille ne {}} {
    lappend l "[join [lsort [split [string trim $nomFamille]]] " "] [string index $prenom 0]"
  }
  return $l
}

### Wikidata id of a player: the name exactly as shown in Gaby, else its
### keys; empty if none
proc ::moderne::avatars::trouver {nom} {
  variable index
  variable noms
  charger
  set nom [string trim $nom]
  if {[info exists noms($nom)]} { return $noms($nom) }
  # (a namesake marked by Gaby, "Botvinnik, Mikhail (*1983)", "Szabo, Laszlo
  # (4)", "Botvinnik, M (Minsk 1987)": another person, never the famous
  # one's card, photo or crown by the surname and initial; only the name
  # exactly as written, Yosha 2026-11-09)
  if {[regexp {\([^()]*\)\s*$} $nom]} { return {} }
  # (a given name with one more initial or name, "Petrosian, Tigran L.":
  # another person, never the famous one's card by the surname and
  # initial; Tigran L. Petrosian got the world champion's photo and crown,
  # Yosha 2026-11-13)
  set prenoms {}
  if {[string first , $nom] >= 0} {
    regsub -all {[^[:alpha:] -]+} [lindex [split $nom ,] 1] { } prenoms
    set prenoms [lsearch -all -inline -not -exact [split [string trim $prenoms]] {}]
  }
  set i 0
  foreach k [cles $nom] {
    incr i
    if {$i > 1 && [llength $prenoms] > 1 && [lsearch -regexp $prenoms {^[[:alpha:]]$}] >= 0} { break }
    if {[info exists index($k)]} {
      # (found by the name's look only: not a game played outside their
      # life, "Lasker, E" in 1952, Yosha 2026-11-09)
      if {![dansSaVie $index($k)]} { return {} }
      return $index($k)
    }
  }
  return {}
}

### The year of the game being shown (set by the players' rows; empty:
### unknown, no check)
namespace eval ::moderne::avatars { variable anneePartie {} }

### Could card q's player have played in ::moderne::avatars::anneePartie?
### (from 5 years old to the last year they played, given by Gaby
### ("gaby": {"last": year}), else to the year of death; unknown dates: yes)
### ("Botvinnik, M" in Minsk 1993: not the champion, who stopped in 1970
### and died in 1995, Yosha 2026-11-10)
proc ::moderne::avatars::dansSaVie {q} {
  variable anneePartie
  variable fiches
  if {![string is integer -strict $anneePartie] || $anneePartie < 1000 || ![info exists fiches($q)]} { return 1 }
  set ne {} ; set mort {} ; set dernier {}
  regexp {"born"\s*:\s*([0-9]+)} $fiches($q) -> ne
  regexp {"died"\s*:\s*([0-9]+)} $fiches($q) -> mort
  regexp {"gaby"\s*:\s*\{[^\}]*"last"\s*:\s*([0-9]+)} $fiches($q) -> dernier
  if {$ne ne {} && $anneePartie < $ne + 5} { return 0 }
  if {$dernier ne {} && $anneePartie > $dernier} { return 0 }
  if {$mort ne {} && $anneePartie > $mort} { return 0 }
  return 1
}

### Photo image of a player, at 128, 64, 43 or 32 px (the silhouette if
### none; empty without the pack)
proc ::moderne::avatars::photo {nom {taille 64}} {
  set q [trouver $nom]
  set d [dossier]
  if {$d eq {}} { return {} }
  set fichier [expr {$q ne {} ? [file join $d photos $q.png] : {}}]
  if {$fichier eq {} || ![file exists $fichier]} {
    set q silhouette
    set fichier [file join $d silhouette.png]
  }
  set nomImg ::moderne::avatars::img_${q}_$taille
  if {[lsearch -exact [image names] $nomImg] >= 0} { return $nomImg }
  if {![file exists $fichier]} { return {} }
  if {[catch {image create photo ::moderne::avatars::src_$q -file $fichier}]} { return {} }
  set r [expr {max(1, 128 / $taille)}]
  image create photo $nomImg
  $nomImg copy ::moderne::avatars::src_$q -subsample $r $r
  image delete ::moderne::avatars::src_$q
  return $nomImg
}

### Card of a player (dict of joueurs.jsonl), empty if none
proc ::moderne::avatars::fiche {nom} {
  variable fiches
  set q [trouver $nom]
  if {$q eq {} || ![info exists fiches($q)]} { return {} }
  if {[catch {::moderne::json::parse $fiches($q)} f]} { return {} }
  return $f
}

### Title of a player in the card (in older cards WC / WWC for the world
### champions), empty if none
proc ::moderne::avatars::titreDe {nom} {
  set t {}
  catch {set t [::moderne::json::get [fiche $nom] title {}]}
  if {$t eq "null"} { set t {} }
  return $t
}

### World champion: WC (king), WWC (queen) or empty. Gaby's "champion"
### field, or its older cards where the title itself was WC / WWC (Yosha
### 2026-11-05: a gold king for the world champions, a gold queen for the
### women's world champions, the FIDE title kept as well)
proc ::moderne::avatars::champion {nom} {
  set c {}
  catch {set c [::moderne::json::get [fiche $nom] champion {}]}
  if {$c in {WC WWC}} { return $c }
  set t [titreDe $nom]
  if {$t in {WC WWC}} { return $t }
  return {}
}

### The FIDE title of the card (GM, IM, WGM…; not WC / WWC)
proc ::moderne::avatars::titreFide {nom} {
  set t [titreDe $nom]
  if {$t in {WC WWC}} { return {} }
  return $t
}

### Gold king or queen shown after a title in text (empty if none)
### Image of the champions' gold king or queen, empty if none: the piece
### (bitmaps/champions/WC_<h>.png, WWC_<h>.png, see outils/champions.py)
### at a height taken from the font, set on the text's baseline in an image
### centred like a line of text; the queen a little smaller than the king
### (its crown's points make it look taller; Yosha 2026-11-05)
proc ::moderne::avatars::imageChampion {nom {police font_Bold}} {
  set c [champion $nom]
  if {$c eq {}} { return {} }
  set img ::moderne::avatars::champion_${c}_$police
  if {[lsearch -exact [image names] $img] >= 0} { return $img }
  set d [::moderne::pieces::dossier]
  if {$d eq {}} { return {} }
  set asc [font metrics $police -ascent]
  set ligne [font metrics $police -linespace]
  set h [expr {round($asc * ($c eq "WC" ? 1.25 : 1.05))}]
  set h [expr {max(10, min(28, $h))}]
  set f [file join [file dirname $d] champions ${c}_$h.png]
  if {![file exists $f] || [catch {image create photo ${img}_p -file $f}]} { return {} }
  # (the piece centred on the capital letters of the name next to it (their
  # middle about 0.64 of the ascent from the top): on the baseline it stood
  # a quarter of a letter too high, Yosha 2026-11-09; the image as tall as
  # the line, more if needed, centred like the text)
  set haut [expr {round($asc * 0.64 - $h / 2.0)}]
  set e [expr {max(0, -$haut, $haut + $h - $ligne)}]
  image create photo $img -width [image width ${img}_p] -height [expr {$ligne + 2 * $e}]
  $img copy ${img}_p -to 0 [expr {$haut + $e}]
  image delete ${img}_p
  return $img
}

### The champion's mark on a label: the gold piece, else its symbol
proc ::moderne::avatars::marqueChampion {w nom {police font_Bold}} {
  set img [imageChampion $nom $police]
  if {$img ne {}} { $w configure -image $img -text {} } else { $w configure -image {} -text [symboleChampion $nom] }
  return [expr {$img ne {} || [symboleChampion $nom] ne {}}]
}

proc ::moderne::avatars::symboleChampion {nom} {
  switch -- [champion $nom] {
    WC { return "♚" }
    WWC { return "♛" }
  }
  return {}
}

### Text shown on hover: name, title, federation, years, Wikipedia, photo credit
proc ::moderne::avatars::credit {nom} {
  set f [fiche $nom]
  if {$f eq {}} { return {} }
  set g [list]
  foreach k {name title federation} {
    set v [::moderne::json::get $f $k {}]
    if {$v ne {} && $v ne "null"} { lappend g $v }
  }
  set ne [::moderne::json::get $f born {}]
  set mort [::moderne::json::get $f died {}]
  if {$ne eq "null"} { set ne {} }
  if {$mort eq "null"} { set mort {} }
  if {$ne ne {} || $mort ne {}} { lappend g "$ne–$mort" }
  set t [join $g "  •  "]
  set wp [::moderne::json::get $f wikipedia {}]
  # (the article opens on a click; the list of its languages, fifty codes,
  # is not shown)
  if {$wp ne {} && $wp ne "null" && [catch {dict size $wp}] == 0 && [dict size $wp]} {
    append t "\n[T "Wikipédia (clic)" "Wikipedia (click)"]"
  }
  set ph [::moderne::json::get $f photo {}]
  if {$ph ne {} && $ph ne "null"} {
    set auteur [::moderne::json::get $ph author {}]
    set licence [::moderne::json::get $ph licence {}]
    set c "[T Photo Photo] : $auteur"
    if {$licence ne {} && $licence ne "null"} { append c " ($licence)" }
    append t "\n$c • Wikimedia Commons"
  }
  return $t
}

### Wikipedia article of a player: in the language of Siby, else English,
### else the first one
proc ::moderne::avatars::wikipedia {nom} {
  set wp [::moderne::json::get [fiche $nom] wikipedia {}]
  if {$wp eq {} || $wp eq "null" || [catch {dict size $wp}]} { return {} }
  foreach l [list [expr {[::moderne::tr F E] eq "F" ? "fr" : "en"}] en] {
    if {[dict exists $wp $l]} { return [dict get $wp $l] }
  }
  if {[dict size $wp]} { return [lindex [dict values $wp] 0] }
  return {}
}

### Avatar widget: the photo. Updated with ::moderne::avatars::maj.
proc ::moderne::avatars::creer {w {taille 43}} {
  set fond [::moderne::c fond]
  frame $w -background $fond -width $taille -height $taille
  pack propagate $w 0
  label $w.i -background $fond -borderwidth 0 -highlightthickness 0
  place $w.i -x 0 -y 0 -relwidth 1 -relheight 1
  return $w
}

### Title shown: the world champions' crown always; otherwise the game's
### (PGN) title when there is one, else the card's
proc ::moderne::avatars::titreAffiche {nom titre} {
  set ordre {WC WWC GM IM WGM FM WIM CM WFM WCM}
  set connu [titreFide $nom]
  set titre [string toupper [string trim $titre]]
  set c [champion $nom]
  if {$c ne {}} { return $c }
  if {$titre in $ordre} { return $titre }
  if {$connu in $ordre} { return $connu }
  return {}
}

proc ::moderne::avatars::maj {w nom {titre {}} {taille 43}} {
  if {![winfo exists $w]} { return }
  set img [photo $nom $taille]
  $w.i configure -image $img
  # (no card: no tooltip; the previous player's stayed, Carlsen's on
  # Mishra, Yosha 2026-11-11)
  set c [credit $nom]
  if {$c eq {}} {
    unset -nocomplain ::utils::tooltip::message($w.i)
  } else {
    catch {::utils::tooltip::Set $w.i $c}
  }
  # click: the player's Wikipedia article
  set lien [wikipedia $nom]
  if {$lien ne {}} {
    $w.i configure -cursor hand2
    bind $w.i <Button-1> [list catch [list openURL $lien]]
  } else {
    $w.i configure -cursor {}
    bind $w.i <Button-1> {}
  }
}

################################################################################
### Update of the pack with Gaby: the manifest's "joueurs" entry
###   {"version": "2026-10", "fichier": "gaby_joueurs_2026-10.zip",
###    "sha256": "…", "dossier": "gaby_joueurs"}
### When its version differs from gaby_joueurs/VERSION, the zip is
### downloaded, checked (sha256), unzipped next to gaby.si4 (it holds the
### gaby_joueurs/ folder) and replaces the old pack.
################################################################################

proc ::moderne::avatars::versionLocale {} {
  set d [dossier]
  if {$d eq {}} { return {} }
  set v {}
  catch {
    set c [open [file join $d VERSION] r]
    set v [string trim [read $c]]
    close $c
  }
  return $v
}

proc ::moderne::avatars::verifierPaquet {manifeste} {
  variable majPaquet
  if {[info exists majPaquet]} { return }
  set e [::moderne::json::get $manifeste joueurs {}]
  if {$e eq {} || $e eq "null"} { return }
  set v [::moderne::json::get $e version {}]
  set nomZip [::moderne::json::get $e fichier {}]
  if {$v eq {} || $nomZip eq {} || $v eq [versionLocale]} { return }
  set g [::moderne::gaby::trouverFichier]
  if {$g eq {} || ![file isdirectory [file dirname $g]]} { return }
  set majPaquet $e
  set sortie [file join [::moderne::gaby::dossierTemp] $nomZip]
  ::moderne::gaby::recuperer [::moderne::gaby::adresseFichier $nomZip] $sortie \
      [list ::moderne::avatars::paquetRecu $sortie]
}

proc ::moderne::avatars::paquetRecu {sortie f {err {}}} {
  variable majPaquet
  set e $majPaquet
  if {$f eq {} || ![file exists $sortie]} { unset majPaquet ; return }
  set attendu [string tolower [::moderne::json::get $e sha256 {}]]
  if {$attendu ne {} && ([catch {sc_gaby sha256 $sortie} h] || $h ne $attendu)} {
    catch {file delete $sortie}
    unset majPaquet
    return
  }
  if {[catch {installerPaquet $sortie [::moderne::json::get $e dossier gaby_joueurs] \
                 [list ::moderne::avatars::paquetInstalle $sortie]} err]} {
    puts stderr "Siby: players pack not installed: $err"
    catch {file delete $sortie}
    unset majPaquet
  }
}

### End of the pack's installation (err empty: installed)
proc ::moderne::avatars::paquetInstalle {sortie err} {
  variable majPaquet
  if {$err ne {}} {
    puts stderr "Siby: players pack not installed: $err"
  } else {
    # (its FIDE data, unzipped in the background)
    after 2000 {catch ::moderne::fide::preparer}
  }
  catch {file delete $sortie}
  unset -nocomplain majPaquet
}

### Unzips the pack into a new folder next to Gaby, then puts it in place
### of the old one (kept on failure). With suite: in slices of about 100 ms
### (2,577 photos froze Siby 5 s on Windows, 2026-10-31), then "suite
### error" (error empty when done); without it, at once
proc ::moderne::avatars::installerPaquet {zip {nomDossier gaby_joueurs} {suite {}}} {
  set racine [file dirname [::moderne::gaby::trouverFichier]]
  set neuf [file join $racine ${nomDossier}_nouveau]
  catch {file delete -force $neuf}
  file mkdir $neuf
  set entrees [::moderne::gaby::lireZip $zip]
  if {$suite eq {}} {
    foreach entree $entrees { extraire $zip $neuf $nomDossier $entree }
    installerFin $racine $nomDossier
    return
  }
  after idle [list ::moderne::avatars::installerTranche $zip $racine $nomDossier $entrees $suite]
}

proc ::moderne::avatars::installerTranche {zip racine nomDossier entrees suite} {
  set neuf [file join $racine ${nomDossier}_nouveau]
  set fin [expr {[clock milliseconds] + 100}]
  if {[catch {
    while {[llength $entrees] && [clock milliseconds] < $fin} {
      extraire $zip $neuf $nomDossier [lindex $entrees 0]
      set entrees [lrange $entrees 1 end]
    }
  } err]} {
    catch {file delete -force $neuf}
    uplevel #0 [concat $suite [list $err]]
    return
  }
  if {[llength $entrees]} {
    after 1 [list ::moderne::avatars::installerTranche $zip $racine $nomDossier $entrees $suite]
    return
  }
  set err {}
  catch {installerFin $racine $nomDossier} err
  uplevel #0 [concat $suite [list $err]]
}

### One entry of the zip into folder neuf
proc ::moderne::avatars::extraire {zip neuf nomDossier entree} {
  lassign $entree nom methode comp dec donnees
  if {[string index $nom end] eq "/"} { return }
  # (paths inside the zip: gaby_joueurs/…; nothing outside the folder)
  set parties [file split $nom]
  if {[lindex $parties 0] eq $nomDossier} { set parties [lrange $parties 1 end] }
  if {![llength $parties] || ".." in $parties || [file pathtype [lindex $parties 0]] ne "relative"} { return }
  set cible [file join $neuf {*}$parties]
  file mkdir [file dirname $cible]
  set in [open $zip rb]
  seek $in $donnees
  if {$methode == 8} { zlib push inflate $in }
  set out [open $cible wb]
  chan copy $in $out -size $dec
  close $in
  close $out
}

### The new folder in place of the old one
proc ::moderne::avatars::installerFin {racine nomDossier} {
  set neuf [file join $racine ${nomDossier}_nouveau]
  set vieux [file join $racine ${nomDossier}_ancien]
  if {![file exists [file join $neuf joueurs.jsonl]]} {
    file delete -force $neuf
    error "no joueurs.jsonl in the archive"
  }
  set actuel [file join $racine $nomDossier]
  catch {file delete -force $vieux}
  if {[file exists $actuel]} { file rename $actuel $vieux }
  if {[catch {file rename $neuf $actuel} err]} {
    if {[file exists $vieux]} { file rename $vieux $actuel }
    error $err
  }
  catch {file delete -force $vieux}
  recharger
}

### End Siby
