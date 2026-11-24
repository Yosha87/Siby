###
### Siby: one rule for the tabs (Yosha 2026-11-22: "tous ces problèmes
### d'onglets qui sont au mauvais endroit ou pas là"). Many repairs placed one
### tab each, after the fact (notation, review, search results, tablebase…);
### this one controller checks every tab, often:
###   - a tab that is not an engine never stays in a group holding an engine
###     (the search results opened next to Stockfish, out of sight);
###   - a tab never stays in no group at all.
### Such a tab goes to its home: its own group in the Lab (the notation and
### the review with the game list, the tablebase with the opening library),
### else the notation's group. A tab dragged anywhere else is left there.
### Each move is written to siby.log. Not while a layout is being built, and
### never inside the broadcasts' or the game's cover, whose groups are theirs.
###

namespace eval ::moderne::rangement {
  variable periode 1500
  variable compte 0      ;# tabs put back since the start (tests)
}

### The engine tabs (analysis windows: Stockfish, Toby, Leela…)
proc ::moderne::rangement::estMoteur {t} {
  return [expr {[string match .fdockanalysisWin* $t] || [string match .fdockattenteanalysisWin* $t]}]
}

### Does group nb hold an engine?
proc ::moderne::rangement::groupeMoteur {nb} {
  if {$nb eq {} || ![winfo exists $nb] || [catch {$nb tabs} tabs]} { return 0 }
  foreach t $tabs { if {[estMoteur $t]} { return 1 } }
  return 0
}

### Is there a group other than tb, not an engine's and not on a hidden
### page, that a window could go to?
proc ::moderne::rangement::autreGroupe {tb} {
  foreach t [array names ::docking::tbs] {
    if {$t eq $tb || ![winfo exists $t] || [winfo class $t] ne "TNotebook" || [couverture $t] || [groupeMoteur $t]} { continue }
    if {![catch {::moderne::lab::cache $t} c] && $c} { continue }
    return 1
  }
  return 0
}

### A cover's group (broadcasts, game): left to it
proc ::moderne::rangement::couverture {nb} {
  expr {[string match .directCouvre* $nb] || [string match .jeuCouvre* $nb]}
}

### Where tab d belongs: its own group in the Lab, else the notation's group,
### else the game list's; empty when none is on screen
proc ::moderne::rangement::maison {d} {
  set m {}
  if {$d in {.fdockpgnWin .fdocktbWin .fdockbilanWin}} { catch {set m [::moderne::direct::maisonLab $d]} }
  if {$m eq {} && $d ne ".fdockpgnWin"} { catch {set m [lindex [::moderne::bilan::groupeNotation] 0]} }
  if {$m eq {} && $d ne ".fdockglistWin" && [winfo exists .fdockglistWin]} { catch {set m [::docking::find_tbn .fdockglistWin]} }
  if {$m eq {} || ![winfo exists $m] || [couverture $m] || [groupeMoteur $m]} { return {} }
  return $m
}

### Moves tab d from group src (empty: in no group) to its home. 1 if moved
proc ::moderne::rangement::ramener {d src raison} {
  variable compte
  set dest [maison $d]
  if {$dest eq {} || $dest eq $src} { return 0 }
  set titre {}
  if {$src ne {} && [winfo exists $src]} {
    catch {set titre [$src tab $d -text]}
    set devant [expr {![catch {$src select} s] && $s eq $d}]
    catch {$src forget $d}
  } else {
    set devant 1
  }
  if {[string trim $titre] eq {} && [info exists ::docking::titres($d)]} { set titre $::docking::titres($d) }
  if {[catch {$dest add $d -text $titre}]} { return 0 }
  if {$devant} { catch {$dest select $d} }
  catch ::docking::setTabStatus
  incr compte
  catch {::moderne::journal "Siby: tab $d $raison {$src}, put back in $dest"}
  return 1
}

### One check of every tab
proc ::moderne::rangement::verifier {} {
  if {!$::docking::USE_DOCKING || ![winfo exists .pw]} { return }
  if {[info exists ::docking::enConstruction] && $::docking::enConstruction} { return }
  # (a game against an engine being set up, or a layout being applied)
  if {[info exists ::moderne::disposition::demarrage] && $::moderne::disposition::demarrage} { return }
  set n 0
  foreach t [array names ::docking::tbs] {
    if {![winfo exists $t] || [winfo class $t] ne "TNotebook" || [couverture $t]} { continue }
    if {![groupeMoteur $t]} { continue }
    foreach d [$t tabs] {
      # (never the board, nor a waiting place for a module not made yet)
      if {[estMoteur $d] || ![string match .fdock* $d] || $d eq ".fdockmain" || [string match .fdockattente* $d]} { continue }
      incr n [ramener $d $t "was with an engine in"]
    }
  }
  # tabs in no group at all (a window docked nowhere)
  foreach d {.fdockpgnWin .fdockglistWin .fdockresultatsWin .fdockbilanWin .fdocktbWin .fdockbiblioWin} {
    if {![winfo exists $d] || [winfo manager $d] ne {}} { continue }
    if {[::docking::find_tbn $d] ne {}} { continue }
    # (a cover holds it while shown: its own business)
    if {[info exists ::moderne::direct::superpose] && $::moderne::direct::superpose ne {}} { continue }
    incr n [ramener $d {} "was in no group"]
  }
  return $n
}

proc ::moderne::rangement::boucle {} {
  variable periode
  after cancel ::moderne::rangement::boucle
  catch ::moderne::rangement::verifier
  after $periode ::moderne::rangement::boucle
}

after idle {after 3000 ::moderne::rangement::boucle}

### End Siby
