###
### Siby: official FIDE data of the players (profile of the preparation,
### Alter Ego), from Gaby's players pack:
###   gaby_joueurs/fide_joueurs.tsv.gz    one line per FIDE id, header line:
###     fide_id nom fed sexe naissance titre titre_f elo_std elo_rapide
###     elo_blitz parties_std mois_liste
###   gaby_joueurs/fide_historique.tsv.gz one line per FIDE id:
###     fide_id<TAB>s2001-01:2849,s2001-07:2838,r2012-03:2810,b2012-03:2900
###     (s standard, r rapid, b blitz; only the months where it changes)
### Both sorted by FIDE id. They are unzipped once next to the pack
### (.tsv), then read by binary search: nothing is loaded in memory, one
### line costs a few disk reads.
### The FIDE id of a player comes from the games of Gaby
### (WhiteFideId / BlackFideId headers).
###

namespace eval ::moderne::fide {
  variable cache          ;# cache(file,id) = line (or {})
  array set cache {}
  variable enCours        ;# enCours(name): being unzipped in the background
  array set enCours {}
}

### Unzipped file of the pack, {} without the pack or while it is being
### unzipped (in the background, see preparer: the profile then shows the
### games' Elos). Unzipped here, waiting, only if preparer did not run.
proc ::moderne::fide::fichier {nom} {
  variable enCours
  set d [::moderne::avatars::dossier]
  if {$d eq {}} { return {} }
  if {[info exists enCours($nom)]} { return {} }
  set gz [file join $d $nom.tsv.gz]
  set tsv [file join $d $nom.tsv]
  if {[aRefaire $gz $tsv]} {
    if {[catch {
      set in [open $gz rb]
      zlib push gunzip $in
      set out [open $tsv.part wb]
      fcopy $in $out
      close $in ; close $out
      file rename -force $tsv.part $tsv
    } err]} {
      catch {close $in} ; catch {close $out}
      catch {file delete $tsv.part}
      return {}
    }
    variable cache
    array unset cache
  }
  if {[file exists $tsv]} { return $tsv }
  return {}
}

proc ::moderne::fide::aRefaire {gz tsv} {
  expr {[file exists $gz] && (![file exists $tsv] || [file mtime $tsv] < [file mtime $gz])}
}

### Unzips the pack's files in the background (startup, new pack): about
### 4 s of work that does not freeze the window
proc ::moderne::fide::preparer {} {
  variable enCours
  set d [::moderne::avatars::dossier]
  if {$d eq {}} { return }
  foreach nom {fide_joueurs fide_historique} {
    if {[info exists enCours($nom)]} { continue }
    set gz [file join $d $nom.tsv.gz]
    set tsv [file join $d $nom.tsv]
    if {![aRefaire $gz $tsv]} { continue }
    if {[catch {
      set in [open $gz rb]
      zlib push gunzip $in
      set out [open $tsv.part wb]
    }]} {
      catch {close $in}
      continue
    }
    set enCours($nom) 1
    fcopy $in $out -command [list ::moderne::fide::prepare $nom $in $out $tsv]
  }
}

proc ::moderne::fide::prepare {nom in out tsv args} {
  variable enCours
  variable cache
  catch {close $in}
  catch {close $out}
  # (args: bytes copied, then an error message if any)
  if {[llength $args] < 2} {
    catch {file rename -force $tsv.part $tsv}
  } else {
    catch {file delete $tsv.part}
  }
  unset -nocomplain enCours($nom)
  array unset cache
}

### Line of FIDE id in file f (sorted by id), {} if absent: binary search
### on the byte offsets
proc ::moderne::fide::chercher {f id} {
  variable cache
  if {[info exists cache($f,$id)]} { return $cache($f,$id) }
  set ligne {}
  if {[string is integer -strict $id] && ![catch {open $f r} c]} {
    fconfigure $c -encoding utf-8
    # bas: always the start of a line; the line looked for starts before haut
    set bas 0
    set haut [file size $f]
    while {$haut - $bas > 4096} {
      set milieu [expr {($bas + $haut) / 2}]
      seek $c $milieu
      gets $c ;# (to the start of the next line)
      if {[gets $c l] < 0} { set haut $milieu ; continue }
      set k [lindex [split $l \t] 0]
      if {![string is integer -strict $k] || $k < $id} {
        set bas [tell $c]
      } elseif {$k == $id} {
        set ligne $l ; set bas $haut
        break
      } else {
        set haut $milieu
      }
    }
    # the last few kilobytes, line by line
    if {$ligne eq {}} {
      seek $c $bas
      while {[gets $c l] >= 0} {
        set k [lindex [split $l \t] 0]
        if {![string is integer -strict $k]} { continue }
        if {$k == $id} { set ligne $l ; break }
        if {$k > $id} { break }
      }
    }
    close $c
  }
  set cache($f,$id) $ligne
  return $ligne
}

### Card of FIDE id: dict {nom fed sexe naissance titre titre_f elo_std
### elo_rapide elo_blitz parties_std mois_liste}, {} if unknown
proc ::moderne::fide::joueur {id} {
  set f [fichier fide_joueurs]
  if {$f eq {}} { return {} }
  set l [chercher $f $id]
  if {$l eq {}} { return {} }
  set v [lrange [split $l \t] 1 end]
  set d {}
  foreach k {nom fed sexe naissance titre titre_f elo_std elo_rapide elo_blitz parties_std mois_liste} x $v {
    dict set d $k [string trim $x]
  }
  return $d
}

### Rating history of FIDE id: {cadence {{YYYY-MM elo} ...} ...} with the
### cadences classique, rapide, blitz (as in the profile), {} if unknown
proc ::moderne::fide::historique {id} {
  set f [fichier fide_historique]
  set l {}
  if {$f ne {}} { set l [chercher $f $id] }
  set h {}
  foreach e [split [lindex [split $l \t] 1] ,] {
    if {![regexp {^([srb])([0-9]{4}-[0-9]{2}):([0-9]+)$} $e -> t m elo]} { continue }
    dict lappend h [dict get {s classique r rapide b blitz} $t] [list $m $elo]
  }
  # (the official lists before 2001, Gaby's elo_officiel, in front of the
  # classical ones)
  set avant [officielsAvant2001 {} $id]
  if {[llength $avant]} {
    set apres {}
    if {[dict exists $h classique]} {
      foreach e [dict get $h classique] {
        if {[string compare [lindex $e 0] 2001-01] >= 0} { lappend apres $e }
      }
    }
    dict set h classique [concat $avant $apres]
  }
  return $h
}

### Peak of a history list {{YYYY-MM elo} ...}: {elo YYYY-MM}, {} if empty
proc ::moderne::fide::pic {l} {
  set best {}
  foreach e $l {
    if {$best eq {} || [lindex $e 1] > [lindex $best 0]} { set best [list [lindex $e 1] [lindex $e 0]] }
  }
  return $best
}

### FIDE id of a player from a game of base b: the WhiteFideId or
### BlackFideId header of game gnum, on the player's side ({} if none)
proc ::moderne::fide::idPartie {b gnum couleur} {
  set tag [expr {$couleur eq "white" || $couleur eq "B" ? "WhiteFideId" : "BlackFideId"}]
  set id {}
  catch {
    set r [lindex [sc_gaby tags $b $gnum $gnum $tag] 0]
    set id [string trim [lindex $r end]]
  }
  if {![string is integer -strict $id] || $id <= 0} { return {} }
  return $id
}

### Titles shown for a player, from the two FIDE columns (open title t,
### women's title tf): the open title alone when it is of the same rank as
### the women's one or higher (GM and WGM: "GM"; GM and WIM: "GM"); both
### when the women's title is higher (FM and WIM: "FM WIM")
proc ::moderne::fide::titres {t tf} {
  set rangs {GM IM FM CM}
  set rangsF {WGM WIM WFM WCM}
  set i [lsearch -exact $rangs [string toupper [string trim $t]]]
  set j [lsearch -exact $rangsF [string toupper [string trim $tf]]]
  set l {}
  if {$i >= 0} { lappend l [lindex $rangs $i] }
  if {$j >= 0 && ($i < 0 || $j < $i)} { lappend l [lindex $rangsF $j] }
  return [join $l " "]
}

### Titles of FIDE id with the rule above; the game's title (defaut) when
### the player is not in the pack
proc ::moderne::fide::titresJoueur {id {defaut {}}} {
  if {![string is integer -strict $id] || $id <= 0} { return $defaut }
  set d [joueur $id]
  if {$d eq {}} { return $defaut }
  set t [titres [dict get $d titre] [dict get $d titre_f]]
  if {$t eq {}} { return $defaut }
  return $t
}

################################################################################
### Official ratings before 2001 (Gaby's manifest entry "elo_officiel",
### OlimpBase, reconstructed: not ratified by FIDE). One gzip file next to
### gaby.si4 (not in gaby_joueurs/, which each players pack replaces):
###   nom<TAB>fide_id<TAB>s1971-07:2760,s1972-07:2785,…
### names as in gaby.sn4, fide_id empty when unknown, every list of the
### player (not only the changes). From 2001 on, fide_historique (by id).
### Decided by Yosha (2026-11-03): an official rating, when there is one,
### is the player's level (Alter Ego plays at it) and anchors the curve.
################################################################################

namespace eval ::moderne::fide {
  variable offCharge {}      ;# file read into offNom / offId ({}: not yet)
  variable offNom            ;# offNom(name) = {id classements}
  variable offId             ;# offId(fide id) = name
  array set offNom {} ; array set offId {}
  variable idNoms            ;# idNoms(base,name) = FIDE id ({} if none)
  array set idNoms {}
  variable majOff 0          ;# a download is under way
}

proc ::moderne::fide::fichierOfficiels {} {
  set g {}
  catch {set g [::moderne::gaby::trouverFichier]}
  if {$g eq {}} { return {} }
  return [file join [file dirname $g] gaby_elo_officiel.tsv.gz]
}

proc ::moderne::fide::versionOfficiels {} {
  set f [fichierOfficiels]
  set v {}
  if {$f ne {}} { catch { set c [open $f.version r] ; set v [string trim [read $c]] ; close $c } }
  return $v
}

### The manifest read: download the file when its version changed
proc ::moderne::fide::verifierOfficiels {manifeste} {
  variable majOff
  if {$majOff} { return }
  set e [::moderne::json::get $manifeste elo_officiel {}]
  if {$e eq {} || $e eq "null"} { return }
  set v [::moderne::json::get $e version {}]
  set nom [::moderne::json::get $e fichier {}]
  set f [fichierOfficiels]
  if {$v eq {} || $nom eq {} || $f eq {}} { return }
  if {$v eq [versionOfficiels] && [file exists $f]} { return }
  set majOff 1
  set sortie [file join [::moderne::gaby::dossierTemp] $nom]
  ::moderne::gaby::recuperer [::moderne::gaby::adresseFichier $nom] $sortie \
      [list ::moderne::fide::officielsRecus $e $sortie]
}

proc ::moderne::fide::officielsRecus {e sortie fichier {err {}}} {
  variable majOff 0
  if {$fichier eq {} || ![file exists $sortie]} { return }
  set attendu [string tolower [::moderne::json::get $e sha256 {}]]
  if {$attendu ne {} && ([catch {sc_gaby sha256 $sortie} h] || $h ne $attendu)} {
    catch {file delete $sortie}
    return
  }
  set f [fichierOfficiels]
  if {[catch {
    file copy -force $sortie $f.part
    file rename -force $f.part $f
    set c [open $f.version w] ; puts $c [::moderne::json::get $e version {}] ; close $c
  } err]} {
    puts stderr "Siby: official ratings not installed: $err"
  }
  catch {file delete $sortie}
  variable offCharge {}
  variable cache
  array unset cache
}

### Reads the file once (about 34,000 players, a few tenths of a second)
proc ::moderne::fide::chargerOfficiels {} {
  variable offCharge
  variable offNom
  variable offId
  set f [fichierOfficiels]
  if {$f eq {} || ![file exists $f]} { return 0 }
  set sig "$f [file mtime $f]"
  if {$offCharge eq $sig} { return 1 }
  array unset offNom ; array unset offId
  if {[catch {
    set c [open $f rb]
    zlib push gunzip $c
    fconfigure $c -encoding utf-8 -translation lf
    gets $c   ;# (header)
    while {[gets $c l] >= 0} {
      set p [split $l \t]
      if {[llength $p] < 3} { continue }
      lassign $p nom id cl
      set offNom($nom) [list $id $cl]
      if {$id ne {}} { set offId($id) $nom }
    }
    close $c
  } err]} {
    catch {close $c}
    puts stderr "Siby: official ratings unreadable: $err"
    return 0
  }
  set offCharge $sig
  return 1
}

### Classical official lists before 2001 of a name or a FIDE id:
### {{YYYY-MM elo olimpbase} ...}, oldest first
proc ::moderne::fide::officielsAvant2001 {{nom {}} {id {}}} {
  variable offNom
  variable offId
  if {![chargerOfficiels]} { return {} }
  if {$nom eq {} && $id ne {} && [info exists offId($id)]} { set nom $offId($id) }
  if {$nom eq {} || ![info exists offNom($nom)]} { return {} }
  lassign $offNom($nom) idF cl
  # (a namesake: the name's FIDE id is someone else's)
  if {$id ne {} && $idF ne {} && $idF ne $id} { return {} }
  set l {}
  foreach e [split $cl ,] {
    if {[regexp {^s([0-9]{4}-[0-9]{2}):([0-9]+)$} $e -> m elo]} { lappend l [list $m $elo olimpbase] }
  }
  return $l
}

### FIDE id of a name in base b: the pre-2001 file, else the FideId header
### of their most recent games (kept for the session)
proc ::moderne::fide::idNom {b nom} {
  variable idNoms
  variable offNom
  if {[info exists idNoms($b,$nom)]} { return $idNoms($b,$nom) }
  set id {}
  if {[chargerOfficiels] && [info exists offNom($nom)]} { set id [lindex $offNom($nom) 0] }
  if {$id eq {}} {
    foreach x [sc_name sibyparties $b $nom 30] {
      lassign $x g couleur
      catch {set id [idPartie $b $g $couleur]}
      if {$id ne {}} { break }
    }
  }
  set idNoms($b,$nom) $id
  return $id
}

### Official classical rating of year an: the average of the ratings in
### force month by month that year ({} if none). A pre-2001 list counts 12
### months at most (a player absent from the lists has no official rating
### then); a fide_historique change holds until the next one.
proc ::moderne::fide::eloAnnee {l an} {
  set somme 0 ; set n 0
  for {set mois 1} {$mois <= 12} {incr mois} {
    set m [format %04d-%02d $an $mois]
    set cours {}
    foreach e $l {
      if {[string compare [lindex $e 0] $m] <= 0} { set cours $e } else { break }
    }
    if {$cours eq {}} { continue }
    if {[lindex $cours 2] eq "olimpbase"} {
      scan [lindex $cours 0] %d-%d a mm
      if {($an - $a) * 12 + $mois - $mm >= 12} { continue }
    }
    incr somme [lindex $cours 1] ; incr n
  }
  if {!$n} { return {} }
  return [expr {int(round(double($somme) / $n))}]
}

### Classical official lists of a player, before and after 2001:
### {{YYYY-MM elo ?olimpbase?} ...}
proc ::moderne::fide::officiels {nom id} {
  set l [officielsAvant2001 $nom $id]
  if {$id ne {}} {
    set h [historique $id]
    if {[dict exists $h classique]} {
      foreach e [dict get $h classique] {
        if {[string compare [lindex $e 0] 2001-01] >= 0} { lappend l $e }
      }
    }
  }
  return [lsort -index 0 $l]
}
