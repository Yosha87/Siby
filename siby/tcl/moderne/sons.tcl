###
### Siby: move sounds (Options › Sounds), on by default as on Lichess.
###
### A short, low wooden knock for a move (two variants, picked at random so
### it does not sound mechanical) and a higher, double knock for a capture.
### Cut, shortened and filtered from "chess foley" by Amatsuuu
### (freesound.org, sounds 629181 and 629182, CC0).
### Played for a move entered on the board, a move of the opponent (engine,
### Toby) and when stepping forward through a game.
### On Windows the sound is played by the system (sc_info playsound, winmm);
### elsewhere by paplay, aplay or afplay if present.
###

namespace eval ::moderne::sons {}
if {![info exists ::moderne::sons::actifs]} { set ::moderne::sons::actifs 1 }

proc ::moderne::sons::dossier {} {
  foreach d [list [file join $::scidShareDir sounds siby] \
                  [file join [file dirname [info nameofexecutable]] sounds siby] \
                  [file join [file dirname [info nameofexecutable]] .. sounds siby]] {
    if {[file isdirectory $d]} { return $d }
  }
  return {}
}

### type: coup | prise; for a game against an engine (as on Lichess): debut,
### then victoire, defaite or nulle for the player
proc ::moderne::sons::jouer {type} {
  if {!$::moderne::sons::actifs} { return }
  set d [dossier]
  if {$d eq {}} { return }
  set l [lsort [glob -nocomplain -directory $d bois_${type}*.wav]]
  if {![llength $l]} { return }
  set f [lindex $l [expr {int(rand() * [llength $l])}]]
  if {![catch {sc_info playsound $f} ok] && $ok} { entretien ; return }
  foreach p {paplay aplay afplay} {
    if {[auto_execok $p] ne {}} { catch {exec $p $f >/dev/null 2>/dev/null &} ; return }
  }
}

### Windows: the sound output is fed by its own thread (sibyson.cpp), as a
### browser does; "-upkeep" now returns 0 at once
proc ::moderne::sons::entretien {} {
  variable entretienApres
  if {[info exists entretienApres] && $entretienApres ne {}} { return }
  set entretienApres [after 40 ::moderne::sons::entretienTic]
}
proc ::moderne::sons::entretienTic {} {
  variable entretienApres {}
  if {![catch {sc_info playsound -upkeep} ouvert] && $ouvert} {
    set entretienApres [after 40 ::moderne::sons::entretienTic]
  }
}

### A move just played (SAN): capture or plain move
proc ::moderne::sons::coup {san} {
  jouer [expr {[string first x $san] >= 0 ? "prise" : "coup"}]
}

### The sound of the move just played on the board, if the board moved
### forward by one move since position avant ({location} of sc_pos): as on
### Lichess, a sound for each move really played (right arrow, by hand, a
### variation chosen), none when the variations' choice opens, none going
### back (Yosha 2026-11-09)
proc ::moderne::sons::siAvance {avant} {
  if {[sc_pos location] == $avant + 1} { coup [sc_game info previous] }
}

### A move already in the game, played again by hand: stepped into, with its
### sound
proc ::moderne::sons::dejaJoue {} {
  coup [sc_game info previous]
}

proc ::moderne::sons::installer {} {
  foreach p {AnnounceNewMove AnnounceForward} {
    if {![llength [info commands ::utils::sound::${p}Orig]] && [llength [info commands ::utils::sound::$p]]} {
      rename ::utils::sound::$p ::utils::sound::${p}Orig
      proc ::utils::sound::$p {move} "catch {::moderne::sons::coup \$move} ; ::utils::sound::${p}Orig \$move"
    }
  }
}
::moderne::sons::installer
