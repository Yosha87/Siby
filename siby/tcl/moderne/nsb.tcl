
###
### Siby: precomputed opening library (.sbl file)
###
### For a large database (Gaby), the sbbiblio tool (next to
### Siby) computes once the statistics of the positions of the first
### moves and the best games of each, in "base.sbl" next to
### "base.si4". The opening library, the preparation and the Tree window
### then read them instantly (without Elo / period / time-control filter; with
### a filter, the normal search takes over).
###
### Updating: when a database of at least 200,000 games is opened or
### used by the opening library, Siby checks its .sbl; if it is missing
### or no longer matches the database, sbbiblio is started in the background.
### Meanwhile the opening library works as before (normal search).
### You can also run "sbbiblio base.si4" yourself, for example at the end
### of a database update script.
###
### sbbiblio also builds the position search index (base.sbp), which
### speeds up "Search › Partial position"; it is updated in
### blocks (only new or modified games are reread).
###
### A database with time-control flags (Gaby: 1 classical, 2 rapid,
### 3 blitz) also gets one library per time control (base.classical.sbl,
### base.rapid.sbl, base.blitz.sbl, "sbbiblio --cadence N"), so that the
### time-control filter is instant too (Yosha 2026-11-05). They are
### checked, built or updated one after the other once the main library
### is up to date; the daily additions are a few seconds each.
###

namespace eval ::moderne::nsb {
  variable minParties 200000  ;# database size from which the file is built
  variable canal              ;# canal(b): sbbiblio running for database b
  array set canal {}
  variable etat               ;# etat(b): text shown in the opening library
  array set etat {}
  variable vu                 ;# vu(b): "file|games" already checked
  array set vu {}
}

proc ::moderne::nsb::T {fr en} { return [::moderne::tr $fr $en] }

### Path of sbbiblio (next to the Siby executable)
proc ::moderne::nsb::outil {} {
  set dir [file dirname [info nameofexecutable]]
  foreach n {sbbiblio.exe sbbiblio} {
    set f [file join $dir $n]
    if {[file executable $f]} { return $f }
  }
  return {}
}

### Checks database b; starts the build if needed (force: even a
### small database, and even if the file is up to date)
proc ::moderne::nsb::verifier {b {force 0}} {
  variable minParties
  variable canal
  variable vu
  variable etat
  if {!$b || ![sc_base inUse $b] || $b == [sc_info clipbase]} { return }
  # (Gaby merged from its two parts lost its flags' names: put back)
  catch {::moderne::gaby::reparerDrapeaux $b}
  # (a full rebuild put off by the user: not this session, the library
  # there is kept as it is)
  variable plusTard
  if {!$force && [info exists plusTard([sc_base filename $b])]} { return }
  # (the move search accelerator too, in the background, after the
  # library: board.tcl)
  after 3000 [list catch [list ::search::accel::fond $b]]
  if {[info exists canal($b)]} { return }
  set n [sc_base numGames $b]
  set cle "[sc_base filename $b]|$n"
  if {!$force && [info exists vu($b)] && $vu($b) eq $cle} { return }
  set vu($b) $cle
  if {[catch {sc_nsb etat $b} r]} { return }
  lassign $r e nFichier nBase fichier eNsp
  if {$fichier eq {}} { return }
  if {$eNsp eq {}} { set eNsp ok }
  switch -- $e {
    ok      { set etat($b) [T "⚡ bibliothèque instantanée" "⚡ instant library"] }
    partiel { set etat($b) [T "⚡ bibliothèque instantanée (mise à jour à faire)" "⚡ instant library (update pending)"] }
    default { set etat($b) {} }
  }
  majIndicateur
  if {!$force && (($e eq "ok" && $eNsp eq "ok") || $n < $minParties)} {
    if {$e eq "ok" && $n >= $minParties} { verifierCadences $b }
    return
  }
  variable raison
  variable passes
  set raison($b) $e
  # (a file from an older Siby: same name, older format)
  if {$e eq "absent" && [file exists $fichier]} { set raison($b) ancien }
  # sbbiblio passes: 1-2 opening library (.sbl), 3 position index (.sbp)
  set passes($b) [expr {($force || $e ne "ok") ? 3 : 1}]
  if {$passes($b) == 1} { set raison($b) [expr {$eNsp eq "absent" ? "nsp" : "nspMaj"}] }
  lancer $b $fichier $force
}

### The time controls' libraries of database b (after the main one): the
### first one missing or out of date is built or updated
proc ::moderne::nsb::verifierCadences {b} {
  variable canal
  if {[info exists canal($b)]} { return }
  variable plusTard
  if {[info exists plusTard([sc_base filename $b])]} { return }
  if {[catch {::moderne::biblio::aDrapeaux $b} oui] || !$oui} { return }
  foreach c {1 2 3} {
    if {[catch {sc_nsb etat $b $c} r]} { return }
    lassign $r e - - fichier
    if {$fichier eq {} || $e eq "ok"} { continue }
    variable raison
    variable passes
    set raison($b) $e
    set passes($b) 2
    lancer $b [file join [file dirname $fichier] [file rootname [file rootname [file tail $fichier]]]].sbl 0 $c
    return
  }
}

proc ::moderne::nsb::lancer {b fichier force {cadence 0}} {
  variable canal
  variable cadenceEnCours
  set cadenceEnCours($b) $cadence
  variable etat
  set exe [outil]
  if {$exe eq {}} {
    set etat($b) [T "bibliothèque instantanée : sbbiblio introuvable à côté de Siby" "instant library: sbbiblio not found next to Siby"]
    majIndicateur
    return
  }
  set base [file rootname $fichier]
  set args [list $exe]
  if {!$force} { lappend args --si-perime }
  if {$cadence} { lappend args --cadence $cadence }
  lappend args $base
  if {[catch {open |$args r} f]} {
    set etat($b) "[T "bibliothèque instantanée : lancement impossible" "instant library: cannot start"] ($f)"
    majIndicateur
    return
  }
  fconfigure $f -blocking 0 -buffering line
  set canal($b) $f
  set etat($b) [T "préparation de la bibliothèque instantanée…" "building the instant library…"]
  majIndicateur
  variable raison
  set nom [file tail $base]
  if {$cadence} {
    # (the daily additions of a time control: a few seconds, no notice)
    if {[expr {[info exists raison($b)] ? $raison($b) : {}}] ne "partiel"} {
      set cad [lindex [list {} [T classique classical] [T rapide rapid] [T blitz blitz]] $cadence]
      annonce [T "Base $nom : bibliothèque instantanée $cad" "Database $nom: $cad instant library"] 0
    }
    fileevent $f readable [list ::moderne::nsb::lire $b $f]
    return
  }
  switch -- [expr {[info exists raison($b)] ? $raison($b) : {}}] {
    partiel { set titre [T "Nouvelles parties dans $nom : mise à jour de la bibliothèque instantanée" "New games in $nom: updating the instant library"] }
    ancien  { set titre [T "Base $nom : bibliothèque instantanée au nouveau format" "Database $nom: instant library moving to the new format"] }
    perime  { set titre [T "La base $nom a changé : reconstruction de la bibliothèque instantanée" "Database $nom changed: rebuilding the instant library"] }
    nsp     { set titre [T "Base $nom : création de l'index de recherche de positions" "Database $nom: building the position search index"] }
    nspMaj  { set titre [T "Base $nom : mise à jour de l'index de recherche de positions" "Database $nom: updating the position search index"] }
    default { set titre [T "Nouvelle base $nom : création de la bibliothèque instantanée" "New database $nom: building the instant library"] }
  }
  annonce $titre 0
  fileevent $f readable [list ::moderne::nsb::lire $b $f]
}

### Databases at least this large: their full rebuild asked first
namespace eval ::moderne::nsb { variable grandeBase 1000000 }

### A full rebuild of database b about to start (sbbiblio's channel f):
### stopped and asked when the database is very large; 1 if stopped
proc ::moderne::nsb::demanderComplet {b f} {
  variable grandeBase
  variable accepte
  set n [sc_base numGames $b]
  set fich [sc_base filename $b]
  if {$n < $grandeBase || [info exists accepte($fich)]} { return 0 }
  variable canal
  variable debutLib
  # the process stopped (by its own number)
  catch {
    foreach p [pid $f] {
      if {$::windowsOS} { exec taskkill /PID $p /F } else { exec kill $p }
    }
  }
  catch {fileevent $f readable {}}
  catch {close $f}
  unset -nocomplain canal($b) debutLib($b)
  journal $b "full rebuild stopped: asked first"
  catch {finAnnonce}
  variable cadenceEnCours
  set cad [expr {[info exists cadenceEnCours($b)] ? $cadenceEnCours($b) : 0}]
  set cadenceEnCours($b) 0
  after idle [list ::moderne::nsb::questionComplet $b $fich $cad]
  return 1
}

### The question itself (not during a game: when it is over)
proc ::moderne::nsb::questionComplet {b fich {cad 0}} {
  if {![sc_base inUse $b] || [sc_base filename $b] ne $fich} { return }
  if {[winfo exists .serGameWin] || [grab current] ne {}} {
    after 5000 [list ::moderne::nsb::questionComplet $b $fich $cad]
    return
  }
  # (all its libraries: on Gaby, 10.8 million games, main 385 s and the
  # time controls' 290 s more)
  set parM 0.6
  if {![catch {::moderne::biblio::aDrapeaux $b} oui] && $oui} { set parM 1.05 }
  set min [expr {max(1, int(round([sc_base numGames $b] / 1000000.0 * $parM)))}]
  set nom [file tail $fich]
  set r [tk_messageBox -parent . -icon question -title Siby -default plusTard \
      -boutons [list maintenant [T "Maintenant" "Now"] plusTard [T "Plus tard" "Later"]] \
      -message [T "Bibliothèque instantanée de « $nom » à reconstruire (environ $min min)." \
                  "The instant library of « $nom » needs rebuilding (about $min min)."]]
  variable accepte
  variable plusTard
  if {$r eq "maintenant"} {
    set accepte($fich) 1
    unset -nocomplain plusTard($fich)
    # (a time control's library stopped: that one again, not the main one)
    if {$cad} { verifierCadences $b } else { verifier $b 1 }
  } else {
    # (asked again at the next start)
    set plusTard($fich) 1
    journal $b "full rebuild put off"
  }
}

proc ::moderne::nsb::lire {b f} {
  variable canal
  variable etat
  variable vu
  while {[gets $f l] >= 0} {
    if {[regexp {^MODE (AJOUTS|COMPLET) (\S+)} $l -> mode quoi]} {
      variable debutLib
      variable cadenceEnCours
      set cad [expr {[info exists cadenceEnCours($b)] ? $cadenceEnCours($b) : 0}]
      set debutLib($b) [list [clock milliseconds] $mode $quoi $cad]
      journal $b "$mode $quoi (time control $cad)"
      # a very large database whose library has to be rebuilt in full
      # (it had one): never without asking, minutes of work (Yosha
      # 2026-11-09: Gaby rebuilt for 6 minutes after one of its games was
      # saved)
      # (the time controls' libraries too: the answer for the main one
      # covers them, asked alone otherwise)
      if {$mode eq "COMPLET" && $quoi ne "absente" && $quoi ne "demande" && [demanderComplet $b $f]} { return }
      # (a complete rebuild where additions were expected: said, the
      # notice no longer shows the Gaby update's title)
      if {$mode eq "COMPLET" && [winfo exists .annonceNsb]} {
        set nom [file tail [sc_base filename $b]]
        set c [lindex [list {} [T " classique" " classical"] [T " rapide" " rapid"] [T " blitz" " blitz"]] $cad]
        # (the step among the four libraries of a database with time
        # controls: the classical one after the main one looked like a
        # second rebuild, Yosha 2026-11-09)
        set etape {}
        if {![catch {::moderne::biblio::aDrapeaux $b} oui] && $oui} { set etape " ([expr {$cad + 1}]/4)" }
        annonce [T "Base $nom : bibliothèque instantanée$c reconstruite en entier$etape" \
            "Database $nom:$c instant library rebuilt in full$etape"] -1
      }
      continue
    }
    if {[regexp {^PROGRES (\d) (\d+) (\d+)} $l -> passe i n] && $n > 0} {
      variable passes
      variable cadenceEnCours
      # (a time control's library: passes 1 and 2, in its notice if it
      # has one; the main library's state is left as it is)
      if {[info exists cadenceEnCours($b)] && $cadenceEnCours($b)} {
        if {[winfo exists .annonceNsb]} {
          annonce {} [expr {min(100, int(100.0 * ($passe - 1 + double($i) / $n) / 2))}]
        }
        continue
      }
      set np [expr {[info exists passes($b)] ? $passes($b) : 3}]
      set k [expr {max(0, $passe - (3 - $np) - 1)}]
      set pct [expr {min(100, int(100.0 * ($k + double($i) / $n) / $np))}]
      if {$passe < 3} {
        set etat($b) "[T "préparation de la bibliothèque instantanée" "building the instant library"] : $pct %"
        majIndicateur
      } elseif {$np == 3} {
        set etat($b) [T "⚡ bibliothèque instantanée" "⚡ instant library"]
        majIndicateur
      }
      annonce {} $pct
    } elseif {[string match ERREUR* $l]} {
      set etat($b) "[T "bibliothèque instantanée : erreur" "instant library: error"] ([string range $l 7 end])"
      majIndicateur
      annonce $etat($b) -1
    }
  }
  if {![eof $f]} { return }
  catch {close $f}
  unset -nocomplain canal($b)
  variable debutLib
  if {[info exists debutLib($b)]} {
    journal $b "end after [expr {([clock milliseconds] - [lindex $debutLib($b) 0]) / 1000}] s"
    unset debutLib($b)
  }
  variable annonceTitre
  variable cadenceEnCours
  set cad [expr {[info exists cadenceEnCours($b)] ? $cadenceEnCours($b) : 0}]
  set cadenceEnCours($b) 0
  if {$cad} {
    if {[winfo exists .annonceNsb] && ![string match *erreur* $annonceTitre] && ![string match *error* $annonceTitre]} {
      annonce {} 100
    }
    after 5000 ::moderne::nsb::finAnnonce
    catch {set ::moderne::biblio::cache [dict create]}
    catch {set ::moderne::biblio::ordreCache {}}
    # (the next time control, if any)
    if {[sc_base inUse $b]} { after 500 [list catch [list ::moderne::nsb::verifierCadences $b]] }
    after idle {catch ::moderne::biblio::suivre}
    return
  }
  if {![string match *erreur* $annonceTitre] && ![string match *error* $annonceTitre]} {
    variable passes
    if {[info exists passes($b)] && $passes($b) == 1} {
      annonce [T "Index de recherche de positions prêt" "Position search index ready"] 100
    } else {
      annonce [T "Bibliothèque instantanée et index de recherche prêts" "Instant library and search index ready"] 100
    }
  }
  after 5000 ::moderne::nsb::finAnnonce
  unset -nocomplain vu($b)
  # new opening library: results kept in memory must be recomputed
  catch {set ::moderne::biblio::cache [dict create]}
  catch {set ::moderne::biblio::ordreCache {}}
  if {[sc_base inUse $b]} { verifier $b }
  after idle {catch ::moderne::biblio::suivre}
}

### "bibliotheque.log" (Siby's folder): each library update, complete or
### additions, why, and how long it took (to explain a slow one)
proc ::moderne::nsb::journal {b texte} {
  catch {
    set f [open [file join $::scidUserDir bibliotheque.log] a]
    puts $f "[clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}] [file tail [sc_base filename $b]] ([sc_base numGames $b]): $texte"
    close $f
  }
}

### Notice at the bottom right of the main window: title and progress
### bar (pct: 0–100; -1: no bar; empty title: unchanged)
namespace eval ::moderne::nsb { variable annonceTitre {} }
proc ::moderne::nsb::annonce {titre pct} {
  variable annonceTitre
  set a .annonceNsb
  if {![winfo exists $a]} {
    frame $a -background [::moderne::c surface2] -highlightthickness 1 \
        -highlightbackground [::moderne::c accent] -padx 14 -pady 10
    label $a.t -background [::moderne::c surface2] -foreground [::moderne::c texteFort] \
        -font font_Regular -justify left -wraplength 380
    ttk::progressbar $a.p -length 380 -maximum 100
    label $a.v -background [::moderne::c surface2] -foreground [::moderne::c texteDoux] -font font_Small -anchor w
    pack $a.t -side top -anchor w
    pack $a.p -side top -fill x -pady {8 2}
    pack $a.v -side top -anchor w
    place $a -in . -relx 1.0 -rely 1.0 -x -18 -y -18 -anchor se
  }
  if {$titre ne {}} { set annonceTitre $titre ; $a.t configure -text $titre }
  if {$pct >= 0} {
    $a.p configure -value $pct
    $a.v configure -text [expr {$pct >= 100 ? {} : "$pct %"}]
    if {![winfo ismapped $a.p]} { pack $a.p -side top -fill x -pady {8 2} -before $a.v }
  } else {
    pack forget $a.p
    $a.v configure -text {}
  }
  raise $a
}

proc ::moderne::nsb::finAnnonce {} {
  variable canal
  if {[array size canal]} { return }
  catch {destroy .annonceNsb}
}

### Status text in the Opening library window
proc ::moderne::nsb::majIndicateur {} {
  variable etat
  set w .biblioWin.nsb
  if {![winfo exists $w]} { return }
  set b $::moderne::biblio::base
  set t [expr {[info exists etat($b)] ? $etat($b) : {}}]
  $w configure -text $t
  if {$t eq {}} {
    pack forget $w
  } elseif {![winfo ismapped $w]} {
    catch {pack $w -side top -fill x -after .biblioWin.pos}
  }
}

### Tools › Rebuild the instant opening library (opening library database)
proc ::moderne::nsb::reconstruire {} {
  set b $::moderne::biblio::base
  if {!$b || ![sc_base inUse $b]} { set b [sc_base current] }
  if {$b == [sc_info clipbase]} { return }
  if {[outil] eq {}} {
    tk_messageBox -icon warning -type ok -title Siby -message [T \
        "L'outil sbbiblio est introuvable à côté de Siby." "The sbbiblio tool was not found next to Siby."]
    return
  }
  verifier $b 1
}

### End Siby
