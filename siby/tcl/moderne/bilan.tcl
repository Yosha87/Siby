###
### bilan.tcl: game review (Siby), for any game: the one on the board, a
### live game, a game against Toby or an Alter Ego, a game of a database.
### One click:
###   - annotates the game (symbols and critical variations: oracle.tcl,
###     quick analysis);
###   - estimates each side's level of play from the moves (niveau.tcl,
###     needs Toby);
###   - shows the review: the level of play and the count of !!, !, ?!, ?
###     and ?? of each side.
###

namespace eval ::moderne::bilan {
  variable w .bilanWin
  variable cle {}
  variable apres {}
  variable annote 0         ;# 1 once the annotation is written into the game
}

proc ::moderne::bilan::T {fr en} { return [::moderne::tr $fr $en] }

### The review's tab next to the notation, whatever happened to them before
### (Yosha 2026-11-12: a review started again from a broadcast after its tab
### was closed in Analysis came up drawn over the notation, out of every tab
### group; siby.log "Broadcasts: .fdockbilanWin was in {}")
### The notation's tab group, also while "Prepare against a player" borrows
### the notation for its Notation tab (it is then out of every group: its
### group is the one it goes back to; Yosha 2026-11-13: a review started
### from there came up next to Toby). Returns {group borrowed}
proc ::moderne::bilan::groupeNotation {} {
  if {![winfo exists .fdockpgnWin]} { return {} }
  set nb [::docking::find_tbn .fdockpgnWin]
  if {$nb ne {} && [winfo exists $nb]} { return [list $nb 0] }
  if {![catch {set ::moderne::prepa::pretNotation} p] && $p ne {}} {
    set nb [lindex $p 0]
    if {$nb ne {} && [winfo exists $nb]} { return [list $nb 1] }
  }
  return {}
}

proc ::moderne::bilan::placerOnglet {} {
  set d .fdockbilanWin
  if {![winfo exists $d]} { return }
  set g [groupeNotation]
  if {$g eq {}} { return }
  lassign $g nb prete
  set src [::docking::find_tbn $d]
  if {$src ne $nb} {
    catch {::moderne::journal "Review: tab was in {$src}, put next to the notation in $nb"}
    if {$src ne {} && [winfo exists $src]} { catch {$src forget $d} }
    catch {place forget $d}
    if {[catch {$nb add $d -text [T "Bilan" "Review"]}]} { catch {$nb select $d} }
    catch {$nb select $d}
    catch {raise $d}
  }
  # (the notation borrowed: the page of its group shown, the notation goes
  # back there, then the review in front)
  if {$prete} {
    catch {::moderne::lab::montrerPour $d}
    after idle [list catch [list $nb select $d]]
    after 300 [list catch [list $nb select $d]]
  }
}

proc ::moderne::bilan::lancer {} {
  variable w
  variable cle
  sc_game push copy
  sc_move end
  set n [llength [sc_game moves coord]]
  sc_game pop
  if {$n == 0} {
    tk_messageBox -parent . -icon info -message [T "La partie n'a pas de coups." "The game has no moves."]
    return
  }
  # (a broadcast game reviewed before: its review, kept on this computer,
  # put back into the game)
  catch depuisCache
  # (a review already there: its tab goes too, or the new one would come
  # up empty, titled ".fdockbilanWin")
  catch {destroy $w}
  catch {destroy .fdockbilanWin}
  update idletasks
  # a tab next to the notation (or a window without docking)
  if {$::docking::USE_DOCKING} {
    # (the tab's title from the start)
    set ::docking::titres(.fdockbilanWin) [T "Bilan" "Review"]
    ::createToplevel $w
    ::setTitle $w [T "Bilan" "Review"]
    catch {::createToplevelFinalize $w}
    catch placerOnglet
  } else {
    toplevel $w
    wm title $w [T "Bilan de la partie" "Game review"]
  }
  # (scrolls when the tab is low, e.g. under a broadcast: the frame lives
  # in a canvas)
  canvas $w.cv -highlightthickness 0 -borderwidth 0 -background [::moderne::c fond] \
      -yscrollcommand [list $w.sb set]
  ttk::scrollbar $w.sb -orient vertical -command [list $w.cv yview]
  pack $w.sb -side right -fill y
  pack $w.cv -side left -fill both -expand 1
  set f [ttk::frame $w.f -padding 16]
  raise $f $w.cv
  $w.cv create window 0 0 -anchor nw -window $f
  bind $f <Configure> [list ::moderne::bilan::zone $w]
  bind $w.cv <Configure> [list ::moderne::bilan::zone $w]
  set blanc [sc_game info white] ; set noir [sc_game info black]
  if {$blanc in {{} ?}} { set blanc [T Blancs White] }
  if {$noir in {{} ?}} { set noir [T Noirs Black] }
  ttk::label $f.vide
  ttk::label $f.b -text $blanc -font font_Bold
  ttk::label $f.n -text $noir -font font_Bold
  # (the progress on the right of the figures: the tab keeps the same height
  # during the review and after it, 2026-10-29)
  ttk::frame $f.prog
  grid $f.vide $f.b $f.n -sticky w -padx {0 18} -pady {0 8}
  ttk::label $f.etat -foreground [::moderne::c texteDoux] -text {} -wraplength 300
  grid $f.etat -in $f.prog -row 0 -column 0 -columnspan 2 -sticky w -pady {0 4}
  # progress of the annotation, then of the level of play (Toby)
  set r 1
  foreach {k fr en} {pa "Annotation" "Annotation" pn "Niveau de jeu" "Level of play"} {
    ttk::label $f.l$k -text [T $fr $en] -foreground [::moderne::c texteDoux]
    ttk::progressbar $f.$k -mode determinate -maximum 100 -length 160
    ttk::label $f.t$k -foreground [::moderne::c texteDoux]
    grid $f.l$k -in $f.prog -row $r -column 0 -sticky w -padx {0 10} -pady {4 0}
    grid $f.$k -in $f.prog -row $r -column 1 -sticky w -pady {4 0}
    grid $f.t$k -in $f.prog -row [incr r] -column 1 -sticky w
    incr r
  }
  # (stops the review: the engines go back to the analysis panels)
  ttk::button $f.arret -text [T "Arrêter le bilan" "Stop the review"] -command ::moderne::bilan::arreter
  grid $f.arret -in $f.prog -row $r -column 0 -columnspan 2 -sticky w -pady {10 0}
  foreach x {etat lpa pa tpa lpn pn tpn arret} { raise $f.$x }
  # (a gap before the figures)
  grid [ttk::frame $f.sep -height 4] -
  ttk::label $f.lniv -text [T "Niveau de jeu" "Level of play"]
  ttk::label $f.nivB -text … -font font_Bold
  ttk::label $f.nivN -text … -font font_Bold
  grid $f.lniv $f.nivB $f.nivN -sticky w -padx {0 18} -pady 2
  catch {::utils::tooltip::Set $f.lniv [T \
      "L'Elo qui explique le mieux les coups joués, d'après Toby, sur tous les coups de la partie ; sur l'échiquier, en partant du classement de la partie, dont les coups peuvent l'éloigner beaucoup" \
      "The rating that best explains the moves played, according to Toby, over all the moves of the game; over the board, starting from the game's rating, which the moves can move it far from"]}
  # accuracy of each side, as on Lichess (from the expected score lost)
  ttk::label $f.lprec -text [T "Précision" "Accuracy"]
  ttk::label $f.precB -text … -font font_Bold
  ttk::label $f.precN -text … -font font_Bold
  grid $f.lprec $f.precB $f.precN -sticky w -padx {0 18} -pady 2
  catch {::utils::tooltip::Set $f.lprec [T \
      "100 % = aucun coup n'a fait perdre d'espérance de gain (à l'Elo moyen de la partie, comme les erreurs)" \
      "100% = no move lost expected score (at the game's average rating, as the mistakes)"]}
  # (the colours of the notation, as on Lichess)
  foreach {s fr en coul} {!! "Coups brillants" "Brilliant moves" #168226 ! "Bons coups" "Good moves" #22ac38 \
                          ?! "Imprécisions" "Inaccuracies" #56b4e9 ? "Erreurs" "Mistakes" #e69f00 ?? "Gaffes" "Blunders" #df5353} {
    set k [string map {! e ? q} $s]
    ttk::label $f.l$k -text "$s  [T $fr $en]"
    catch {$f.l$k configure -foreground $coul}
    ttk::label $f.b$k -text …
    ttk::label $f.n$k -text …
    grid $f.l$k $f.b$k $f.n$k -sticky w -padx {0 18} -pady 2
  }
  # (placed once the table rows are: it would push them down otherwise)
  grid $f.prog -row 1 -column 3 -rowspan 8 -sticky nw -padx {24 0}
  variable dispoProg
  set dispoProg($f) colonne
  # (the figures' columns as wide from the start as with the results: the
  # curve beside them does not move when "…" becomes "≈ 2900+")
  set large [expr {[font measure font_Bold "≈ 2900+"] + 18}]
  foreach col {1 2} { grid columnconfigure $f $col -minsize $large }
  # (a line spanning the table and the curve's column, wider than both,
  # widens that last column only: the table and the curve stay put)
  grid columnconfigure $f 3 -weight 1
  # White's expected score along the game (click: go to that move)
  canvas $f.courbe -height [expr {[llength [zeitnot]] ? 146 : 110}] -width 420 -highlightthickness 0 -background [::moderne::c surface]
  grid $f.courbe - - -sticky we -pady {10 0}
  # (drawn again at its final size: drawn while the tab was being laid
  # out, its right part was cut off)
  bind $f.courbe <Configure> {
    after cancel ::moderne::bilan::courbeAjustee
    after 80 ::moderne::bilan::courbeAjustee
  }
  # why the level of play is missing (Toby too old, no Toby...)
  ttk::label $f.raison -foreground [::moderne::c texteDoux] -wraplength 420 -justify left
  grid $f.raison - - -sticky w -pady {8 0}
  catch {::moderne::repeindre $w}
  variable sansSelection
  if {$::docking::USE_DOCKING && !([info exists sansSelection] && $sansSelection)} {
    catch {[::docking::find_tbn .fdockbilanWin] select .fdockbilanWin}
  } else {
    ttk::button $f.fermer -text [T "Fermer" "Close"] -command [list destroy $w]
    grid $f.fermer - - -sticky e -pady {12 0}
    catch {placeWinOverParent $w .}
  }

  # a review saved in the game ([%eval] on every move, levels in the
  # header): shown at once, nothing computed
  variable instantane 0
  variable cleVue [clePartie]
  if {[instantane]} { return }
  # (a broadcast game: no longer followed, so that it does not change
  # under the review)
  catch {set ::moderne::direct::suivie {}}
  # the engines of the analysis panels wait (paused, in their place) until
  # the end of the review: one engine at a time on the graphics card
  ::moderne::occupation::pauserTout bilan
  # (a Toby 2 in Accurate: closed for the review, back afterwards)
  catch {::moderne::toby::libererCarte}
  bind $w <Destroy> {if {"%W" eq ".bilanWin"} { ::moderne::bilan::ferme }}
  set cle {}
  # (the review's times, for review.log: start, end of each part)
  variable chrono [dict create debut [clock milliseconds]]
  variable niveauFait 0
  # (set before the level of play starts: on a busy computer its first
  # step can end before the annotation has started, 2026-10-30)
  variable annotFinie 0
  # 1. the annotation (window of the annotation hidden, quick analysis)
  variable annote 0
  variable niveauLance 0
  ::moderne::oracle::ouvrir 0
  set ::moderne::oracle::form(precision) rapide
  # One Toby for the whole review (2026-10-29, Toby's advice): the level of
  # play's Toby starts at once, beside the annotation's Stockfish, and also
  # gives each move's probability at the game's rating (the good moves);
  # Toby's full answer only for the few candidate good moves. The
  # annotation starts no Toby of its own.
  # (a Toby that did not answer in an earlier review is tried again: it
  # stayed "unavailable" until Siby restarted, and the level of play then
  # waited "after the annotation" for ever, Yosha 2026-11-04)
  set ::moderne::niveau::sansReponse 0
  variable unToby [::moderne::niveau::disponible]
  variable attenteToby 0
  if {$unToby} {
    # (up to 4 Toby processes, as the computer allows: niveau::partage,
    # measured 2026-10-30)
    set ::moderne::niveau::paralleles 4
    catch {unset ::moderne::niveau::partageBilan}
    variable candidats {}
    # (the review marked first: the level borrows the panel's Toby only
    # then; the level started before the annotation: its key is needed
    # when the first evaluations come)
    set ::moderne::oracle::fournisseur ::moderne::bilan::probasToby
    niveauLancer
    array unset ::moderne::oracle::maiaJoue
    array unset ::moderne::oracle::maiaTous
    set avant $::moderne::oracle::form(toby)
    set ::moderne::oracle::form(toby) 0
    ::moderne::oracle::lancer
    set ::moderne::oracle::form(toby) $avant
  } else {
    ::moderne::oracle::lancer
  }
  variable annotFinie 0
  suivre
}

### The review tab follows the game shown: another game's review, read
### from the game (or kept on this computer for a broadcast game), or a
### button to compute it
proc ::moderne::bilan::clePartie {} {
  return [list [sc_base current] [sc_game number] [sc_game info white] [sc_game info black] \
              [sc_game tags get Event] [sc_game tags get Round]]
}

proc ::moderne::bilan::partieChangee {} {
  variable w
  variable cleVue
  if {![winfo exists $w] || ![info exists cleVue]} { return }
  set k [clePartie]
  if {$k eq $cleVue} { return }
  # (a review being computed keeps its game)
  if {[enCours]} { return }
  set cleVue $k
  after cancel ::moderne::bilan::autrePartie
  after idle ::moderne::bilan::autrePartie
}

### A review being computed (annotation or level of play not over)
proc ::moderne::bilan::enCours {} {
  variable instantane
  variable annotFinie
  variable niveauFait
  if {[info exists instantane] && $instantane} { return 0 }
  if {[info exists annotFinie] && !$annotFinie} { return 1 }
  if {[info exists niveauFait] && !$niveauFait} { return 1 }
  return 0
}

### Does the game shown have a review (in the game, or kept)?
proc ::moderne::bilan::dejaFait {} {
  if {[baseLive]} {
    set coups [coupsUci]
    if {[llength $coups] && [file exists [fichierCache $coups]]} { return 1 }
  }
  set ok 1
  sc_game push copy
  sc_move start
  set n 0
  while {1} {
    if {![regexp {\[%eval\s} [sc_pos getComment]]} { set ok 0 ; break }
    if {[sc_pos isAt end]} { break }
    sc_move forward
    incr n
  }
  sc_game pop
  return [expr {$ok && $n > 0}]
}

proc ::moderne::bilan::autrePartie {} {
  variable w
  variable cleVue
  if {![winfo exists $w]} { return }
  if {[dejaFait]} {
    # (the tab stays where it is: in front only if it was)
    variable sansSelection 1
    set focus [focus]
    if {[catch lancer err]} { puts stderr "Siby review: [string range $::errorInfo 0 600]" }
    set sansSelection 0
    catch {focus $focus}
    return
  }
  # no review yet: the players and a button
  set f $w.f
  foreach x [winfo children $f] { destroy $x }
  set blanc [sc_game info white] ; set noir [sc_game info black]
  if {$blanc in {{} ?}} { set blanc [T Blancs White] }
  if {$noir in {{} ?}} { set noir [T Noirs Black] }
  ttk::label $f.titre -text "$blanc – $noir" -font font_Bold
  ttk::label $f.texte -foreground [::moderne::c texteDoux] \
      -text [T "Pas encore de bilan pour cette partie." "No review of this game yet."]
  ttk::button $f.faire -text [T "Faire le bilan" "Review the game"] -command ::moderne::bilan::lancer
  catch {$f.faire configure -style Accent.TButton}
  grid $f.titre -sticky w -pady {0 8}
  grid $f.texte -sticky w -pady {0 10}
  grid $f.faire -sticky w
  catch {::moderne::repeindre $w}
  set cleVue [clePartie]
}
trace add execution updateBoard leave {apply {args { catch ::moderne::bilan::partieChangee }}}

### End of the review once the annotation and the level are both over
proc ::moderne::bilan::finSiTout {} {
  variable annotFinie
  variable niveauFait
  if {![info exists annotFinie] || ![info exists niveauFait]} { return }
  if {$annotFinie && $niveauFait} {
    catch journalToby
    catch journalBilan
    catch enregistrer
    catch masquerProgression
    fin
  }
}

### Review over: the progress lines go (only the results stay)
proc ::moderne::bilan::masquerProgression {} {
  variable w
  set f $w.f
  foreach x {etat lpa pa tpa lpn pn tpn sep arret prog} { catch {grid remove $f.$x} }
}

### "Stop the review": the annotation and the level of play stop where they
### are (what is written into the game stays: the symbols, if the
### annotation was over); nothing is saved as a finished review
proc ::moderne::bilan::arreter {} {
  variable w
  variable cle
  variable apres
  set ::moderne::oracle::fournisseur {}
  variable annote
  variable annotFinie
  variable niveauFait
  catch {after cancel $apres}
  if {[info exists ::moderne::oracle::etat] && $::moderne::oracle::etat ni {idle fini}} {
    catch {destroy .oracleWin}
    catch ::moderne::oracle::arreter
  }
  if {$cle ne {}} { catch {::moderne::niveau::oublier $cle} }
  set cle {}
  set annotFinie 1
  set niveauFait 1
  variable niveauLance 1
  if {[winfo exists $w]} {
    masquerProgression
    grid $w.f.prog -row 1 -column 3 -rowspan 8 -sticky nw -padx {24 0}
    grid $w.f.etat
    catch {placerCourbe $w}
    $w.f.etat configure -text [expr {$annote
        ? [T "Bilan arrêté : la partie est annotée, le niveau de jeu n'a pas été calculé." \
             "Review stopped: the game is annotated, the level of play was not computed."]
        : [T "Bilan arrêté : rien n'a été écrit dans la partie." "Review stopped: nothing was written into the game."]}]
    foreach c {B N} { catch {$w.f.niv$c configure -text –} }
  }
  fin
}

################################################################################
### The review kept: [%eval] in the moves' comments (as on Lichess) and the
### levels in the header (WhiteLevel, BlackLevel, Annotator); a broadcast
### game's review also kept on this computer (Siby's folder, "bilans"),
### for the same moves
################################################################################

### Main line in UCI (the game's identity for the cache)
proc ::moderne::bilan::coupsUci {} {
  sc_game push copy
  set l [sc_game moves coord]
  sc_game pop
  return $l
}

### (the time control in the key too: a review judged as a classical game
### was read back after the blitz broadcasts were recognised, Yosha
### 2026-11-11, Total Chess blitz)
proc ::moderne::bilan::fichierCache {coups} {
  set cad Classical
  catch {set cad [::moderne::toby::cadenceBilan]}
  return [file join $::scidUserDir bilans "[format %08x [zlib crc32 "[join $coups]|$cad"]].bilan"]
}

proc ::moderne::bilan::baseLive {} {
  return [expr {[file normalize [sc_base filename]] eq [file normalize [file join $::sibyDocsDir "Siby live"]]}]
}

### Extra header tags {name value...} without the review's
proc ::moderne::bilan::autresEnTetes {} {
  set l {}
  foreach {t v} [sc_game tags get Extra] {
    if {$t ni {WhiteLevel BlackLevel WhiteLevelSource BlackLevelSource Annotator LevelMethod}} { lappend l "$t \"$v\"" }
  }
  return $l
}

### Writes the finished review into the game (and the cache for a
### broadcast game)
proc ::moderne::bilan::enregistrer {} {
  variable annote
  variable instantane
  variable cle
  # (annote: the annotation ended normally; the oracle's window, closed
  # then, puts its state back to idle)
  if {$instantane || !$annote} { return }
  set nb [llength $::moderne::oracle::positions]
  set loc [sc_pos location]
  sc_move start
  for {set i 0} {$i < $nb} {incr i} {
    if {$i > 0 && [catch {sc_move forward}]} { break }
    if {![info exists ::moderne::oracle::evals($i)]} { continue }
    set cp [lindex $::moderne::oracle::evals($i) 0]
    if {![string is double -strict $cp]} { continue }
    set c [string trim [regsub -all {\[%(eval|best) [^\]]*\]} [sc_pos getComment] {}]]
    # (a mistake: the best move kept too, [%best uci], hidden as [%eval]
    # is: the green arrow when the review is read back from the game,
    # Yosha 2026-11-05; an inaccuracy has no variation to take it from)
    set best {}
    if {$i > 0 && [info exists ::moderne::oracle::evals([expr {$i - 1}])]} {
      set u [lindex $::moderne::oracle::evals([expr {$i - 1}]) 1]
      set joue [lindex $::moderne::oracle::positions [expr {$i - 1}] 1]
      if {[regexp {^[a-h][1-8][a-h][1-8][qrbn]?$} $u] && $u ne $joue && [llength [lsearch -all -inline -regexp [sc_pos getNags] {^\?!$|^\?$|^\?\?$}]]} {
        set best " \[%best $u\]"
      }
    }
    sc_pos setComment [string trim "[format {[%%eval %.2f]} [expr {$cp / 100.0}]]$best $c"]
  }
  catch {sc_move start ; sc_move forward $loc}
  set tags [autresEnTetes]
  foreach {c t} {B WhiteLevel N BlackLevel} {
    set e {}
    if {$cle ne {}} { set e [::moderne::niveau::estimation $cle $c] }
    if {$e ne {} && [lindex $e 2] > 0} {
      lappend tags "$t \"[lindex $e 0]\""
      # (from the moves alone: kept, so that a saved review shows "2500+" too)
      if {[lindex $e 3] eq "a"} { lappend tags "${t}Source \"moves\"" }
    }
  }
  set m [lindex $::engines(list) [::moderne::oracle::moteurDefaut] 0]
  lappend tags "Annotator \"Siby ([string trim "$m, Toby" ", "])\""
  # (the method of the levels: a review made with an earlier one is made
  # again, see instantane)
  lappend tags "LevelMethod \"$::moderne::bilan::methodeNiveau\""
  sc_game tags set -extra $tags
  sc_game setaltered 1
  updateBoard -pgn
  # a broadcast game: kept on this computer for the same moves
  if {[baseLive]} {
    set coups [coupsUci]
    set f [fichierCache $coups]
    file mkdir [file dirname $f]
    set h [open $f w]
    fconfigure $h -encoding utf-8
    puts -nonewline $h [list $coups [::moderne::pgnAnglais]]
    close $h
  }
}

### A broadcast game reviewed before: its review put back into the game
proc ::moderne::bilan::depuisCache {} {
  if {![baseLive]} { return }
  set coups [coupsUci]
  set f [fichierCache $coups]
  if {![file exists $f]} { return }
  set h [open $f r]
  fconfigure $h -encoding utf-8
  lassign [read $h] memes pgn
  close $h
  if {$memes ne $coups} { return }
  sc_game import $pgn
  sc_move end
  updateBoard -pgn
}

### The method of the levels written with a review: a review saved with
### another one (or none, before 2026-11-12) is made again, its levels
### having been computed differently (Yosha 2026-11-12: the rating as the
### starting point in over-the-board classical, the recomputed calibration)
set ::moderne::bilan::methodeNiveau 2026-11-19

### The review saved in the game, shown without computing: 1 if done
proc ::moderne::bilan::instantane {} {
  variable w
  variable instantane
  set methode {}
  foreach {x y} [sc_game tags get Extra] { if {$x eq "LevelMethod"} { set methode $y } }
  if {$methode ne $::moderne::bilan::methodeNiveau} { return 0 }
  # the positions of the main line and their [%eval]
  set positions {}
  array set ev {}
  sc_game push copy
  sc_move start
  set i 0
  set complet 1
  while {1} {
    set fen [sc_pos fen]
    set side [sc_pos side]
    if {[regexp {\[%eval\s+([-+]?[0-9.]+)\]} [sc_pos getComment] -> v]} {
      set ev($i) [list [expr {round($v * 100)}]]
    } else {
      set complet 0
    }
    # (the best move before a mistake, kept with the review)
    if {$i > 0 && [regexp {\[%best\s+([a-h][1-8][a-h][1-8][qrbn]?)\]} [sc_pos getComment] -> b]} {
      set meilleur([expr {$i - 1}]) $b
    }
    if {[sc_pos isAt end]} { lappend positions [list $fen {} {} $side] ; break }
    set san [sc_game info nextMove]
    sc_move forward
    lappend positions [list $fen [sc_game info previousMoveUCI] $san $side]
    incr i
  }
  sc_game pop
  foreach k [array names meilleur] {
    if {[info exists ev($k)]} { set ev($k) [list [lindex $ev($k) 0] $meilleur($k)] }
  }
  if {!$complet || [llength $positions] < 2} { return 0 }
  set instantane 1
  set ::moderne::oracle::positions $positions
  array unset ::moderne::oracle::evals
  array set ::moderne::oracle::evals [array get ev]
  variable annote 1
  variable annotFinie 1
  variable niveauFait 1
  variable niveauLance 1
  variable cle {}
  set f $w.f
  compter
  catch precision
  catch courbe
  set niv {}
  foreach {c t} {B WhiteLevel N BlackLevel} {
    set v {} ; set src {}
    foreach {x y} [sc_game tags get Extra] {
      if {$x eq $t} { set v $y }
      if {$x eq "${t}Source" && $y eq "moves"} { set src a }
    }
    set txt [expr {[string is integer -strict $v] ? [::moderne::niveau::affiche $v 1 $src] : "–"}]
    $f.niv$c configure -text $txt
    lappend niv $txt
  }
  $f.pa configure -value 100
  $f.tpa configure -text [T "terminée" "done"]
  $f.pn configure -value 100
  $f.tpn configure -text [T "terminé" "done"]
  $f.etat configure -text [T "Bilan déjà fait : relu dans la partie, rien à recalculer." \
      "Review already done: read from the game, nothing to compute."]
  # (a broadcast game: the levels by the players' names too)
  catch {::moderne::direct::niveauBandesTextes {*}$niv}
  masquerProgression
  return 1
}

### Scroll region of the review, and the mouse wheel over all of it
proc ::moderne::bilan::zone {w} {
  if {![winfo exists $w.cv]} { return }
  set f $w.f
  catch {placerCourbe $w}
  $w.cv configure -scrollregion [list 0 0 [winfo reqwidth $f] [winfo reqheight $f]]
  # (no scrollbar when everything shows)
  if {[winfo reqheight $f] <= [winfo height $w.cv]} {
    $w.cv yview moveto 0
    pack forget $w.sb
  } elseif {![winfo ismapped $w.sb]} {
    pack $w.sb -side right -fill y -before $w.cv
  }
  foreach x [concat $w.cv $f [winfo children $f]] {
    if {"bilanDefil" ni [bindtags $x]} { bindtags $x [concat [bindtags $x] bilanDefil] }
  }
}
### The curve under the table by default; on the right of it when it would
### be cut off at the bottom and there is room on the right (Yosha
### 2026-11-01). Decided from the tab's size only, from the start: nothing
### moves when the review ends. With the curve on the right, the progress
### of a running review is shown over it (the curve is still mostly empty
### then), else on the right of the table as before.
proc ::moderne::bilan::placerCourbe {w} {
  set f $w.f
  set c $f.courbe
  if {![winfo exists $c]} { return }
  variable ligneCourbe
  variable hautCourbe
  set info [grid info $c]
  if {$info eq {}} { return }
  if {![info exists ligneCourbe] || [dict get $info -column] == 0} {
    set ligneCourbe [dict get $info -row]
    set hautCourbe [$c cget -height]
  }
  lassign [grid bbox $f 0 0 2 [expr {$ligneCourbe - 1}]] - - largT hautT
  set bas [expr {32 + $hautT + 10 + $hautCourbe + 8}]
  # (the tab's width without the scrollbar, which comes and goes)
  set largOnglet [winfo width $w.cv]
  if {[winfo ismapped $w.sb]} { incr largOnglet [winfo width $w.sb] }
  set libre [expr {$largOnglet - [winfo reqwidth $w.sb] - 32 - $largT - 24}]
  set droite [expr {[winfo height $w.cv] > 1 && [winfo height $w.cv] < $bas && $libre >= 300}]
  # (the progress: shown while the review runs, gone after it)
  set prog [expr {[winfo manager $f.prog] ne {}}]
  if {$droite} {
    set larg [expr {min(640, $libre - 4)}]
    # (as tall as the table's rows beside it)
    lassign [grid bbox $f 0 1 2 8] - - - hautL
    set haut [expr {max($hautCourbe, $hautL)}]
    if {[dict get $info -column] != 3 || abs([$c cget -width] - $larg) > 4} {
      $c configure -width $larg -height $haut
      grid $c -row 1 -column 3 -rowspan 8 -columnspan 1 -sticky nw -padx {24 0} -pady 0
    }
    # (the line under the table spans the curve's column too: a long text
    # there does not widen the table and push the curve)
    catch {grid configure $f.raison -columnspan 4}
    if {$prog} { progression $f ligne $ligneCourbe }
  } else {
    if {[dict get $info -column] != 0} {
      $c configure -width 420 -height $hautCourbe
      grid $c -row $ligneCourbe -column 0 -columnspan 3 -rowspan 1 -sticky we -padx 0 -pady {10 0}
    }
    catch {grid configure $f.raison -columnspan 3}
    if {$prog} { progression $f colonne $ligneCourbe }
  }
}

### The progress of a running review: in a column on the right of the
### figures (colonne), or on one line under them when the curve is on the
### right (ligne, Yosha 2026-11-01: the curve stays visible as it fills in).
### Only the widgets still shown are laid out again.
proc ::moderne::bilan::progression {f dispo ligne} {
  variable dispoProg
  if {[info exists dispoProg($f)] && $dispoProg($f) eq $dispo} { return }
  set dispoProg($f) $dispo
  set vus {}
  foreach x {etat lpa pa tpa lpn pn tpn arret} { if {[winfo manager $f.$x] ne {}} { lappend vus $x } }
  if {$dispo eq "ligne"} {
    grid $f.prog -row $ligne -column 0 -columnspan 4 -rowspan 1 -sticky w -padx 0 -pady {10 0}
    set pos {etat {0 {0 16}} lpa {1 {0 6}} pa {2 0} tpa {3 {6 16}} lpn {4 {0 6}} pn {5 0} tpn {6 {6 16}} arret {7 0}}
    # ("Annotating…" says what the bars say: left out of the line, unless
    # it is all that is left, the message of a stopped review)
    if {[llength $vus] > 1} {
      set vus [lsearch -all -inline -not -exact $vus etat]
      catch {grid remove $f.etat}
    }
    foreach x $vus {
      lassign [dict get $pos $x] col padx
      grid $f.$x -in $f.prog -row 0 -column $col -columnspan 1 -sticky w -padx $padx -pady 0
    }
    foreach x {pa pn} { $f.$x configure -length 90 }
  } else {
    grid $f.prog -row 1 -column 3 -rowspan 8 -columnspan 1 -sticky nw -padx {24 0} -pady 0
    if {"etat" ni $vus && [winfo manager $f.pa] ne {}} { lappend vus etat }
    set pos {etat {0 0 2 {0 0} {0 4}} lpa {1 0 1 {0 10} {4 0}} pa {1 1 1 0 {4 0}} tpa {2 1 1 0 0}
             lpn {3 0 1 {0 10} {4 0}} pn {3 1 1 0 {4 0}} tpn {4 1 1 0 0} arret {5 0 2 0 {10 0}}}
    foreach x $vus {
      lassign [dict get $pos $x] row col span padx pady
      grid $f.$x -in $f.prog -row $row -column $col -columnspan $span -sticky w -padx $padx -pady $pady
    }
    foreach x {pa pn} { $f.$x configure -length 160 }
  }
  foreach x $vus { raise $f.$x }
}

bind bilanDefil <MouseWheel> {catch {.bilanWin.cv yview scroll [expr {%D > 0 ? -2 : 2}] units}}
bind bilanDefil <Button-4> {catch {.bilanWin.cv yview scroll -2 units}}
bind bilanDefil <Button-5> {catch {.bilanWin.cv yview scroll 2 units}}

### 2. the level of play (niveau.tcl, Toby), once the annotation is over
proc ::moderne::bilan::niveauLancer {} {
  variable niveauLance
  variable cle
  variable w
  if {$niveauLance} { return }
  set niveauLance 1
  if {![::moderne::niveau::disponible]} {
    catch {$w.f.raison configure -text [::moderne::niveau::pourquoi]}
    variable niveauFait 1
    maj
    finSiTout
    return
  }
  # (calibrated on FIDE ratings: the source is always FIDE)
  set pgn [::moderne::toby::depuisPgn]
  set cad [::moderne::toby::cadenceBilan]
  # bullet: judged as blitz, the level only indicative (Toby plan for the
  # release, Yosha 2026-11-03; a Bullet mode comes in 1.1)
  if {[dict exists $pgn bullet] && [dict get $pgn bullet]} {
    catch {$w.f.raison configure -text [T "Bullet : Toby n'est pas encore calibré pour cette cadence, le niveau est indicatif (probablement sous-estimé)." \
        "Bullet: Toby is not calibrated for this time control yet, the level is indicative (probably underestimated)."]}
  }
  # (one Toby: every move asked, with the game's rating for the good moves)
  variable unToby
  # (the good moves need only Maia's probability at the game's rating: a
  # recent Toby gives it with each move of the level ("dist", eloDist),
  # an older one is asked apart; the level counts every move as usual)
  set options [dict create eloDist [::moderne::oracle::eloPartie]]
  # (a game against Toby: the moves already done while the player thought)
  set prete {}
  catch {set prete [::moderne::bilan::prepa::reprendre]}
  if {$prete ne {}} {
    set cle $prete
    set ::moderne::niveau::rappels($cle) ::moderne::bilan::maj
  } else {
    # (one key per game and settings: the same game reviewed again after
    # more moves, e.g. a broadcast game, keeps the moves already counted and
    # computes only the new ones, Yosha 2026-11-05)
    set ident {}
    foreach t {White Black Event Site Date Round} { lappend ident [sc_game tags get $t] }
    catch {lappend ident [expr {[sc_game startBoard] ? [sc_game startPos] : "startpos"}]}
    lappend ident $cad [dict get $options eloDist]
    set cle "bilan:[format %08x [zlib crc32 [join $ident |]]]"
    # (where the game was played and its ratings: for the estimate with
    # the ratings, when it is adopted; unused otherwise)
    dict set options lieu [::moderne::niveau::lieuPartie]
    set eloB [sc_game tags get WhiteElo] ; set eloN [sc_game tags get BlackElo]
    if {![string is integer -strict $eloB]} { set eloB 0 }
    if {![string is integer -strict $eloN]} { set eloN 0 }
    ::moderne::niveau::suivre $cle $eloB $eloN FIDE $cad ::moderne::bilan::maj $options
  }
  ::moderne::niveau::coupsPartie $cle
  maj
}

### The annotation's engine done (oracle.tcl, fournisseur): the good moves
### need Maia's probability of the move played where it is the engine's best,
### well ahead of the second (Maia alone: at once, ahead of the level's
### moves); then the annotation is written. The level of play goes on.
proc ::moderne::bilan::probasToby {{etape demande}} {
  variable cle
  variable attenteToby
  variable candidats
  set o ::moderne::oracle
  if {[set ${o}::etat] ni {moteur variantes}} { return }
  set n [expr {[llength [set ${o}::positions]] - 1}]
  set attenteToby 1
  # (Toby gone or too old: annotated without the good moves)
  if {$cle eq {} || ![::moderne::niveau::disponible]} {
    set attenteToby 0
    ${o}::annoter
    return
  }
  if {$etape eq "demande"} {
    # (most were asked as their evaluation came: demanderBon)
    for {set i 0} {$i < $n} {incr i} { demanderBon $i }
  }
  set reste 0
  catch {set reste [::moderne::niveau::maiaEnAttente $cle]}
  if {$reste > 0 && [::moderne::niveau::disponible]} { after 200 [list ::moderne::bilan::probasToby attente] ; maj ; return }
  recolterMaia
  set attenteToby 0
  ${o}::annoter
}

### Ply i's evaluation is known: Maia asked if its move may deserve a "!"
### (once per ply)
proc ::moderne::bilan::demanderBon {i} {
  variable cle
  variable candidats
  set o ::moderne::oracle
  if {$cle eq {} || ![${o}::dansPlage $i] || $i in $candidats || ![${o}::candidatBon $i]} { return }
  lappend candidats $i
  ::moderne::niveau::demanderMaia $cle $i [${o}::positionUci $i] [set ${o}::form(eloPartie)]
}

### Maia's answers come: kept for the annotation, the "!" shown at once
proc ::moderne::bilan::recolterMaia {} {
  variable cle
  variable candidats
  set o ::moderne::oracle
  if {$cle eq {} || ![info exists candidats]} { return }
  set nouveaux 0
  foreach i $candidats {
    if {[info exists ${o}::maiaJoue($i)]} { continue }
    set d [::moderne::niveau::maia $cle $i]
    # (every move: the first move of a mistake's variation is judged too)
    if {[dict size $d]} { set ${o}::maiaTous($i) $d }
    set joue [lindex [set ${o}::positions] $i 1]
    if {[dict exists $d $joue]} { set ${o}::maiaJoue($i) [expr {100.0 * [dict get $d $joue]}] ; incr nouveaux }
  }
  if {$nouveaux && [set ${o}::etat] in {moteur variantes}} { catch ${o}::provisoire }
  # (Toby's probabilities of every move, for the chances' comments)
  set n [llength [set ${o}::positions]]
  for {set i 0} {$i < $n} {incr i} {
    if {[info exists ${o}::tdist($i)]} { continue }
    set d [::moderne::niveau::tobyDist $cle $i]
    if {$d ne {}} { set ${o}::tdist($i) $d }
  }
}

### toby_annotation.log (Siby's folder): the review's Toby times (one
### process for the good moves and the level of play)
proc ::moderne::bilan::journalToby {} {
  variable unToby
  if {![info exists unToby] || !$unToby} { return }
  set l [::moderne::niveau::tempsResume]
  if {$l eq {}} { return }
  set f [open [file join $::scidUserDir toby_annotation.log] w]
  puts $f "[clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}] game review, one Toby (level of play and good moves)"
  puts $f [join $l \n]
  # the good moves' candidates: the move, its gap over the second best (ES
  # points), Maia's probability and the symbol given (to see why a move got
  # a "!" or not)
  variable candidats
  set o ::moderne::oracle
  set lignes {}
  catch {
    for {set i 0} {$i < [llength [set ${o}::positions]] - 1} {incr i} {
      set e [${o}::ecartMeilleur $i]
      if {$e eq {} || [lindex $e 0] < 5} { continue }
      set san [lindex [set ${o}::positions] $i 2]
      set num [expr {$i / 2 + 1}][expr {$i % 2 ? "..." : "."}]
      set m [expr {[info exists ${o}::maiaJoue($i)] ? [format %.1f [set ${o}::maiaJoue($i)]] : "-"}]
      lassign $e ecart e1 e2
      lappend lignes "  $num$san: gap [format %.1f $ecart] (best [format %.1f $e1], second [format %.1f $e2]), Maia $m %, symbol [lindex [${o}::juger $i] 0]"
    }
  }
  if {[llength $lignes]} {
    puts $f "Best moves played at least 5 points ahead of the second (\"!\": Maia under 5 % + 2 per point of gap above 5, at most 50 %):"
    puts $f [join $lignes \n]
  }
  close $f
}

### Progress of Toby's probabilities while the review waits for them
proc ::moderne::bilan::progresToby {} {
  variable cle
  if {$cle eq {}} { return {} }
  return [::moderne::niveau::progression $cle]
}

### End of the review (or its tab closed): the panels analyse again
proc ::moderne::bilan::fin {} {
  # (no review running any more: else the next level of play (a live game
  # followed) borrowed the panel's Toby again, and its "Analyse" button did
  # nothing, Yosha 2026-11-11)
  set ::moderne::oracle::fournisseur {}
  # (the panel's Toby lent to the review goes back before the panels resume)
  catch ::moderne::niveau::rendre
  # (the Toby 2 in Accurate closed for the review comes back)
  catch ::moderne::toby::rendreCarte
  # (back to one Toby for the level of play outside the review)
  set ::moderne::niveau::paralleles 1
  # (the review's extra Toby processes closed at once: 3.5 to 5 GB each on
  # Windows; one stays loaded for a while, unless a panel has a Toby)
  catch {::moderne::niveau::surplus [::moderne::niveau::aGarder]}
  ::moderne::occupation::reprendre bilan
}

### Review tab closed: Toby's work for it is dropped
proc ::moderne::bilan::ferme {} {
  variable cle
  set ::moderne::oracle::fournisseur {}
  # (the annotation of this review stops too: else Stockfish and Toby go on
  # in the background and slow down the engines in use)
  if {[info exists ::moderne::oracle::etat] && $::moderne::oracle::etat ni {idle fini}} {
    catch {destroy .oracleWin}
    catch ::moderne::oracle::arreter
  }
  if {$cle ne {}} { catch {::moderne::niveau::oublier $cle} }
  set cle {}
  fin
}

### Follows the annotation until it is over
proc ::moderne::bilan::suivre {} {
  variable w
  variable apres
  if {![winfo exists $w]} { return }
  set e $::moderne::oracle::etat
  if {$e eq "fini"} {
    variable annote 1
    compter
    catch precision
    catch courbe
    catch {destroy .oracleWin}
    variable annotFinie 1
    niveauLancer
    maj
    finSiTout
    return
  }
  if {$e eq "idle"} {
    # (the annotation could not start: maj says why, from oracle::erreur)
    if {[catch {set ::moderne::oracle::echec} err] || $err eq {}} {
      set ::moderne::oracle::echec [T "aucun moteur d'analyse" "no analysis engine"]
    }
    catch {destroy .oracleWin}
    variable annotFinie 1
    niveauLancer
    maj
    finSiTout
    return
  }
  catch recolterMaia
  # (the curve and the symbols' count as the evaluations come, every 2 s)
  variable tic
  if {![info exists tic]} { set tic 0 }
  if {[incr tic] % 4 == 1} { catch courbe ; catch compter }
  set apres [after 500 ::moderne::bilan::suivre]
  maj
}

### Symbols of each side, read from the annotated game (main line)
proc ::moderne::bilan::compter {} {
  variable w
  variable symboles
  variable coupsSymbole
  array set symboles {}
  foreach c {B N} { foreach s {!! ! ?! ? ??} { set symboles($c,$s) 0 ; set coupsSymbole($c,$s) {} } }
  sc_game push copy
  sc_move start
  while {![sc_pos isAt end]} {
    set c [expr {[sc_pos side] eq "white" ? "B" : "N"}]
    sc_move forward
    foreach x [sc_pos getNags] {
      if {[info exists symboles($c,$x)]} { incr symboles($c,$x) ; lappend coupsSymbole($c,$x) [sc_pos location] }
    }
  }
  sc_game pop
  set f $w.f
  # (as on Lichess: the count in the symbol's colour, grey at 0; a click goes
  # to that side's next move with that symbol)
  set couleurs {!! #168226 ! #22ac38 ?! #56b4e9 ? #e69f00 ?? #df5353}
  foreach s {!! ! ?! ? ??} {
    set k [string map {! e ? q} $s]
    foreach c {B N} {
      set l $f.[string tolower [string index $c 0]]$k
      set n $symboles($c,$s)
      $l configure -text $n -foreground [expr {$n ? [dict get $couleurs $s] : [::moderne::c texteDoux]}] \
          -cursor [expr {$n ? "hand2" : ""}]
      bind $l <Button-1> [list ::moderne::bilan::allerSymbole $c $s]
      catch {::utils::tooltip::Set $l [expr {$n ? [T "Clic : le suivant" "Click: the next one"] : ""}]}
    }
  }
}

### The next move of side c (B / N) with symbol s after the current one (the
### first one again after the last)
proc ::moderne::bilan::allerSymbole {c s} {
  variable coupsSymbole
  if {![info exists coupsSymbole($c,$s)] || ![llength $coupsSymbole($c,$s)]} { return }
  # (the board is put on the position before the move: the next one after
  # it at each click)
  set ici [expr {[sc_pos location] + 1}]
  set l $coupsSymbole($c,$s)
  set cible [lindex $l 0]
  foreach x $l { if {$x > $ici} { set cible $x ; break } }
  # the move played, from the position before it
  set joue {}
  catch {sc_move start ; sc_move forward $cible ; set joue [sc_game info previousMoveUCI] ; sc_move back}
  updateBoard -pgn
  # arrows, only after a click here (never while going through the
  # notation): the move played green for a ! or !!; for a mistake, the
  # move played red and the best move green
  if {$s in {?! ? ??}} {
    catch {fleches $cible $joue}
  } else {
    catch {fleches $cible {} $joue}
  }
  # the cursor on the curve at the move (Yosha 2026-11-04)
  variable epinglePly $cible
  variable epingleIci [sc_pos location]
  catch epingler
}

### Lichess's best move for the position of a mistake: the green arrow, if
### the board is still there
proc ::moderne::bilan::flecheCloud {ply rouge loc fen v} {
  if {$v eq {} || [sc_pos location] != $loc || [sc_pos fen] ne $fen} { return }
  if {![info exists ::moderne::bilan::flecheIci] || $::moderne::bilan::flecheIci != $loc} { return }
  set uci [lindex [::moderne::json::get [lindex [::moderne::json::get $v pvs {}] 0] moves {}] 0]
  if {![regexp {^[a-h][1-8][a-h][1-8][qrbn]?$} $uci]} { return }
  # (Lichess writes castling king-takes-rook)
  set roi [string range $uci 0 1]
  if {$roi in {e1 e8} && [string index [sc_pos board] [expr {([scan [string index $uci 0] %c] - 97) + 8 * ([string index $uci 1] - 1)}]] in {K k}} {
    set uci [string map {e1h1 e1g1 e1a1 e1c1 e8h8 e8g8 e8a8 e8c8} $uci]
  }
  if {$uci eq $rouge} { return }
  fleches $ply $rouge $uci
}

### The review's arrows on the position before move ply: rouge (the move
### played, a mistake) and the best move in green (by default the
### engine's); gone once the board moves
proc ::moderne::bilan::fleches {ply rouge {vert {}}} {
  set i [expr {$ply - 1}]
  if {$vert eq {} && $rouge ne {}} {
    if {[info exists ::moderne::oracle::evals($i)]} { set vert [lindex $::moderne::oracle::evals($i) 1] }
    # (a review read from the game: the variation of the mistake)
    if {[string length $vert] < 4} { catch {set vert [lindex [sc_var list UCI] 0]} }
  }
  # (still unknown, a game reviewed elsewhere: Lichess's cloud evaluation
  # of the position, the green arrow drawn when it answers)
  if {$vert eq {} && $rouge ne {}} {
    set loc [sc_pos location]
    set fen [sc_pos fen]
    catch {
      ::moderne::direct::lireJson "https://lichess.org/api/cloud-eval?multiPv=1&fen=[string map {{ } %20 / %2F} $fen]" \
          [list ::moderne::bilan::flecheCloud $ply $rouge $loc $fen]
    }
  }
  set bd .main.board.bd
  if {![winfo exists $bd]} { return }
  $bd delete flecheBilan
  foreach uci [list $rouge $vert] couleur {#c62828 #15781b} {
    if {[string length $uci] < 4 || ($couleur eq "#15781b" && $uci eq $rouge)} { continue }
    set de [expr {([scan [string index $uci 0] %c] - 97) + 8 * ([string index $uci 1] - 1)}]
    set a  [expr {([scan [string index $uci 2] %c] - 97) + 8 * ([string index $uci 3] - 1)}]
    ::moderne::fleche::dessiner $bd $de $a $couleur 0 0.7 flecheBilan
  }
  variable flecheIci [sc_pos location]
}
trace add execution updateBoard leave {apply {args {
  if {[info exists ::moderne::bilan::flecheIci] && [sc_pos location] != $::moderne::bilan::flecheIci} {
    catch {.main.board.bd delete flecheBilan}
    unset ::moderne::bilan::flecheIci
  }
  if {[info exists ::moderne::bilan::epingleIci] && [sc_pos location] != $::moderne::bilan::epingleIci} {
    unset -nocomplain ::moderne::bilan::epingleIci ::moderne::bilan::epinglePly
    catch ::moderne::bilan::epingler
  }
}}}

### Time trouble of each move of the main line, from the mover's clock
### before it (the [%clk] of their previous move): a list by ply (1 = the
### first move) of {level seconds moves-left increment} ({} when unknown); {} for a
### game without times. The time per move until the next time control
### (increments included, as Toby counts it) is compared with the normal
### time per move of the time control: under half, short of time (level
### 1); under a quarter, time trouble (level 2). (Fixed thresholds in
### seconds do not work: with 30 s per move added, the time per move never
### goes under 30 s.)
proc ::moderne::bilan::zeitnot {} {
  set vals {}
  catch {set vals [sc_game values clk]}
  if {![llength $vals]} { return {} }
  set clk {}
  foreach {num v} $vals {
    dict set clk [expr {int(round(($num - 0.5) * 2))}] [::moderne::direct::secondes $v]
  }
  set per [::moderne::toby::periodes]
  # (no TimeControl header: the first clock as the time of the game, no
  # increment)
  if {![llength $per]} {
    set t0 0
    foreach k {1 2} { if {[dict exists $clk $k]} { set t0 [expr {max($t0, [dict get $clk $k])}] } }
    if {$t0 <= 0} { return {} }
    set per [list [list 0 $t0 0]]
  }
  sc_game push copy
  sc_move end
  set n [sc_pos location]
  sc_game pop
  set r {}
  for {set ply 1} {$ply <= $n} {incr ply} {
    if {![dict exists $clk [expr {$ply - 2}]]} { lappend r {} ; continue }
    set t [dict get $clk [expr {$ply - 2}]]
    set coup [expr {($ply + 1) / 2}]
    lassign [::moderne::toby::parCoupA $t $coup $per] pc reste
    # normal time per move of the period the move is in
    set normal {}
    set fin 0
    set incr 0
    foreach p $per {
      lassign $p coups sec inc
      set incr $inc
      set m [expr {$coups > 0 ? $coups : 40}]
      set normal [expr {($sec + $m * $inc) / double($m)}]
      if {$coups == 0} { break }
      incr fin $coups
      if {$coup <= $fin} { break }
    }
    set niv 0
    if {$normal ne {} && $normal > 0} {
      set niv [expr {$pc < $normal / 4.0 ? 2 : ($pc < $normal / 2.0 ? 1 : 0)}]
    }
    # (moves left shown only before a real time control: in a game without
    # one, blitz or sudden death, the 40 moves are only for the calculation)
    set controle 0
    set fin 0
    foreach p $per {
      lassign $p coups
      if {$coups == 0} { break }
      incr fin $coups
      if {$coup <= $fin} { set controle 1 ; break }
    }
    lappend r [list $niv $t [expr {$controle ? $reste : {}}] $incr]
  }
  return $r
}

### Level of play and progress
### While the review runs: its tab still next to the notation, put back
### there otherwise (and written to siby.log, with where it was). Yosha
### 2026-11-13, beta 3, real engines: a review started from the game list
### ended in Stockfish's group, with no line in siby.log at the start: moved
### afterwards. Not while the preparation borrows the notation (that would
### switch pages under the user's feet); at most once a second
proc ::moderne::bilan::verifierPlace {{force 0}} {
  variable dernierControle
  set t [clock milliseconds]
  if {!$force && [info exists dernierControle] && $t - $dernierControle < 1000} { return }
  set dernierControle $t
  if {!$::docking::USE_DOCKING || ![winfo exists .fdockbilanWin]} { return }
  set g [groupeNotation]
  if {$g eq {}} { return }
  set ici [::docking::find_tbn .fdockbilanWin]
  # (next to an engine: moved even while the notation is lent; Yosha
  # 2026-11-14, the review in Stockfish's group after a broadcast and a
  # game, beta 6, nothing in siby.log)
  set moteur [expr {$ici ne {} && [winfo exists $ici] && [llength [lsearch -all -glob [$ici tabs] *analysisWin*]]}]
  if {[lindex $g 1] && !$moteur} { return }
  if {$ici ne [lindex $g 0]} { placerOnglet }
}

### Checked again once a layout, a page or the broadcasts' cover changed
proc ::moderne::bilan::verifierPlusTard {} {
  if {![winfo exists .fdockbilanWin]} { return }
  after cancel {catch {::moderne::bilan::verifierPlace 1}}
  after 400 {catch {::moderne::bilan::verifierPlace 1}}
}

proc ::moderne::bilan::maj {} {
  variable w
  variable cle
  if {![winfo exists $w]} { return }
  catch verifierPlace
  set f $w.f
  set reste 0
  # annotation progress (phases of oracle.tcl)
  variable annote
  set e $::moderne::oracle::etat
  if {$annote} {
    $f.pa configure -value 100
    $f.tpa configure -text [T "terminée" "done"]
  } else {
    set fait 0 ; set tot 0
    catch {set fait $::moderne::oracle::fait ; set tot $::moderne::oracle::total}
    set phases {moteur {Évaluation Evaluation} variantes {Variantes Variations} initToby {Toby Toby} toby {Toby Toby}}
    set phase [expr {[dict exists $phases $e] ? [dict get $phases $e] : {{} {}}}]
    # (the engine and the variations done, Toby's probabilities may still
    # be coming: their progress, not the last "Variations n / n")
    set tp {}
    catch {set tp [::moderne::oracle::tobyProgres]}
    # (one Toby for the review: the level of play's progress)
    variable attenteToby
    if {[info exists attenteToby] && $attenteToby} { catch {set tp [progresToby]} }
    if {$tp ne {}} {
      lassign $tp fait tot
      set phase {{Toby (bons coups)} {Toby (good moves)}}
    }
    $f.pa configure -value [expr {$tot > 0 ? 100.0 * $fait / $tot : 0}]
    $f.tpa configure -text [expr {$tot > 0 ? "[T {*}$phase] : $fait / $tot" : [T "démarrage…" "starting…"]}]
  }
  if {$annote} {
    $f.etat configure -text [T "Partie annotée : symboles et variantes dans la notation." "Game annotated: symbols and variations in the notation."]
    # the ! and !! need Toby's probabilities (how rarely humans of that
    # level find the move): said when there were none
    set nbProbas 0
    catch {set nbProbas [expr {[array size ::moderne::oracle::toby] + [array size ::moderne::oracle::tdata]}]}
    # (one Toby for the review: its probabilities come with the level of play)
    catch {incr nbProbas [array size ::moderne::oracle::tdist]}
    catch {incr nbProbas [array size ::moderne::oracle::maiaJoue]}
    # (positions Toby skipped on purpose: no ! possible there)
    catch {incr nbProbas $::moderne::oracle::tobySautes}
    if {!$nbProbas && [llength [::moderne::toby::moteursToby]]} {
      set arret {}
      catch {set arret $::moderne::oracle::tobyArret}
      if {$arret ne {}} {
        $f.raison configure -text [T \
            "Toby s'est arrêté pendant l'annotation ($arret) : les bons coups (! et !!) n'ont pas pu être cherchés." \
            "Toby stopped during the annotation ($arret): the good moves (! and !!) could not be looked for."]
      } else {
        $f.raison configure -text [T \
            "Toby n'a donné aucune probabilité pendant l'annotation : les bons coups (! et !!) n'ont pas pu être cherchés (échanges avec Toby dans toby_annotation.log, dossier de Siby)." \
            "Toby gave no probabilities during the annotation: the good moves (! and !!) could not be looked for (exchanges with Toby in toby_annotation.log, Siby's folder)."]
      }
    }
  } else {
    foreach c {B N} { $f.niv$c configure -text … }
    # (the annotation could not start: why, instead of "Annotating…" forever)
    variable annotFinie
    set err {}
    catch {set err $::moderne::oracle::echec}
    if {[info exists annotFinie] && $annotFinie && $err ne {}} {
      $f.etat configure -text "[T "Annotation impossible" "No annotation"] : $err"
    } else {
      # (nothing above the bars while they run: "Annotating…" said what the
      # Annotation bar says; Yosha 2026-11-01)
      $f.etat configure -text {}
    }
  }
  niveauMaj
}

### Level of play of each side, and its progress (in plies)
proc ::moderne::bilan::niveauMaj {} {
  variable w
  variable cle
  variable niveauLance
  variable niveauFait
  set f $w.f
  if {!$niveauLance} {
    $f.tpn configure -text [T "après l'annotation" "after the annotation"]
    return
  }
  if {$cle eq {}} {
    # (no Toby: said in $f.raison)
    foreach c {B N} { $f.niv$c configure -text – }
    $f.pn configure -value 0
    $f.tpn configure -text [T "indisponible" "unavailable"]
    return
  }
  lassign [::moderne::niveau::progression $cle] fait tot
  set fini [expr {$fait >= $tot}]
  if {![::moderne::niveau::disponible]} {
    # (Toby stopped answering)
    set fini 1
    $f.raison configure -text [T "Toby n'a pas répondu : niveau de jeu indisponible (Toby trop ancien ?)." \
        "Toby did not answer: no level of play (Toby too old?)."]
  }
  $f.pn configure -value [expr {$tot > 0 ? 100.0 * $fait / $tot : 100}]
  # (nothing back yet: Toby is loading its networks, which takes a while,
  # all the more with the annotation's own Toby loading too)
  if {$fini} {
    $f.tpn configure -text [T "terminé" "done"]
  } elseif {$fait == 0} {
    $f.tpn configure -text [T "Toby démarre…" "Toby is starting…"]
  } else {
    $f.tpn configure -text [T "$fait / $tot demi-coups" "$fait / $tot plies"]
  }
  set minCoups $::moderne::niveau::minCoups
  foreach c {B N} {
    set e [::moderne::niveau::estimation $cle $c]
    if {$e eq {} || [lindex $e 2] < 1} {
      $f.niv$c configure -text [expr {$fini ? "–" : "…"}]
      if {$fini} {
        catch {::utils::tooltip::Set $f.niv$c [T "Partie trop courte : le niveau demande au moins 10 coups de chaque camp" \
            "Game too short: the level needs at least 10 moves by each side"]}
      }
      continue
    }
    lassign $e moy sd n source
    # (few moves or a wide spread: shown as rough; while computing, the
    # estimate so far, in grey)
    # (spread of the posterior itself, before the level correction)
    # (always "≈": the level is an estimate, within about 250 points; the
    # saved review shows it so too, Yosha's battery 2026-11-02)
    set approx 1
    $f.niv$c configure -text [::moderne::niveau::affiche $moy $approx $source] \
        -foreground [expr {$fini ? [::moderne::c texte] : [::moderne::c texteDoux]}]
    # (from the moves alone, at the ends: no number, Yosha 2026-11-22)
    set pa $::moderne::niveau::plafondA
    set ba $::moderne::niveau::plancherA
    if {$source eq "a" && $moy >= $pa} {
      catch {::utils::tooltip::Set $f.niv$c "[T \
          "$pa+ • $n coups mesurés • Une partie ne permet pas de distinguer les niveaux plus hauts." \
          "$pa+ • $n moves measured • One game cannot tell upper levels apart."][::moderne::niveau::noteEpoque]"}
      continue
    }
    if {$source eq "a" && $moy < $ba} {
      catch {::utils::tooltip::Set $f.niv$c "[T \
          "Moins de $ba • $n coups mesurés • Une partie ne permet pas de distinguer les niveaux plus bas." \
          "Under $ba • $n moves measured • One game cannot tell lower levels apart."][::moderne::niveau::noteEpoque]"}
      continue
    }
    set pl $::moderne::niveau::plafond
    set pb $::moderne::niveau::plancher
    if {$moy < $pb} {
      catch {::utils::tooltip::Set $f.niv$c "[T \
          "Sous $pb, le plancher du classement FIDE • $n coups mesurés • pas de nombre plus précis en dessous" \
          "Below $pb, the FIDE rating floor • $n moves measured • no finer number below it"][::moderne::niveau::noteEpoque]"}
      continue
    }
    if {$moy > $pl} {
      catch {::utils::tooltip::Set $f.niv$c "[T \
          "Au-dessus de $pl • $n coups mesurés • Toby ne distingue pas les niveaux au-delà de $pl (les parties humaines s'arrêtent là)" \
          "Above $pl • $n moves measured • Toby cannot tell levels apart beyond $pl (human games stop there)"][::moderne::niveau::noteEpoque]"}
      continue
    }
    # (over-the-board classical with the player's rating: said so, Toby
    # session's wording, 2026-11-12; no margin, Yosha 2026-11-22)
    if {[::moderne::niveau::avecElo $cle $c]} {
      catch {::utils::tooltip::Set $f.niv$c "[T \
          "$moy • $n coups mesurés • part du classement de la partie (parties sur l'échiquier seulement) ; les coups peuvent l'en éloigner beaucoup" \
          "$moy • $n moves measured • uses the player's rating as a starting point (over-the-board games only); the moves can move the estimate far from it"][::moderne::niveau::noteEpoque]"}
      continue
    }
    catch {::utils::tooltip::Set $f.niv$c "[T \
        "$moy • $n coups mesurés • d'après Toby, pas l'Elo de la partie" \
        "$moy • $n moves measured • from Toby, not the game's ratings"][::moderne::niveau::noteEpoque]"}
  }
  # (a broadcast game: the levels by the players' names follow the review's,
  # since the game is no longer followed live)
  catch {::moderne::direct::niveauBandes $cle}
  if {$fini && !$niveauFait} {
    set niveauFait 1
    # (the annotation still running: the level's cores go to its engine)
    # (the cores the level had: all but one, minus the engine pool's)
    catch {::moderne::oracle::agrandir [expr {[::moderne::toby::coeurs] - 1 - [dict get [::moderne::niveau::partage] pool]}]}
    finSiTout
  }
}

################################################################################
### Accuracy and curve, from the annotation's evaluations (oracle.tcl):
### evals(i) = centipawns (White) of the position after i plies. As on
### Lichess (lila AccuracyPercent), with the expected score of Toby's formula
### (at the game's average rating) instead of Lichess's win percent.
################################################################################

### Expected score (%) of the side to move at position i, White's at i if
### blanc is 1; {} without evaluation
proc ::moderne::bilan::es {i elo pourBlancs} {
  if {![info exists ::moderne::oracle::evals($i)]} { return {} }
  set cp [lindex $::moderne::oracle::evals($i) 0]
  if {![string is double -strict $cp]} { return {} }
  if {!$pourBlancs} { set cp [expr {-$cp}] }
  return [::moderne::oracle::gain $elo $cp]
}

proc ::moderne::bilan::precisionCoup {avant apres} {
  if {$apres >= $avant} { return 100.0 }
  set a [expr {103.1668100711649 * exp(-0.04354415386753951 * ($avant - $apres)) - 3.166924740191411 + 1}]
  return [expr {max(0.0, min(100.0, $a))}]
}

proc ::moderne::bilan::precision {} {
  variable w
  # (both sides at the game's average rating, as the mistakes: the same
  # moves give the same accuracy, whatever the rating gap)
  set elo [::moderne::oracle::eloPartie]
  set nb [llength $::moderne::oracle::positions]
  # White's expected score along the game (for the weights)
  set es {50.0}
  set coups {}
  for {set i 0} {$i < $nb - 1} {incr i} {
    set blanc [expr {[lindex $::moderne::oracle::positions $i 3] eq "white"}]
    set av [es $i $elo $blanc]
    set ap [es [expr {$i + 1}] $elo $blanc]
    set wb [es [expr {$i + 1}] $elo 1]
    if {$av eq {} || $ap eq {} || $wb eq {}} { continue }
    lappend es $wb
    lappend coups [list $blanc [precisionCoup $av $ap]]
  }
  set n [llength $coups]
  set f $w.f
  if {$n < 2} {
    foreach c {B N} { $f.prec$c configure -text – }
    return
  }
  # weights: volatility of the expected score around each move
  set taille [expr {max(2, min(8, $n / 10))}]
  set fenetres {}
  for {set k 0} {$k < $taille - 2} {incr k} { lappend fenetres [lrange $es 0 [expr {$taille - 1}]] }
  for {set k 0} {$k + $taille <= [llength $es]} {incr k} { lappend fenetres [lrange $es $k [expr {$k + $taille - 1}]] }
  set poids {}
  foreach x $fenetres {
    set m [expr {[tcl::mathop::+ {*}$x] / double([llength $x])}]
    set v 0.0
    foreach y $x { set v [expr {$v + ($y - $m) ** 2}] }
    lappend poids [expr {max(0.5, min(12.0, sqrt($v / [llength $x])))}]
  }
  foreach c {1 0} cle {B N} {
    set sp 0.0 ; set sw 0.0 ; set sh 0.0 ; set k 0
    foreach coup $coups p [lrange $poids 0 [expr {$n - 1}]] {
      lassign $coup blanc a
      if {$blanc != $c} { continue }
      if {$p eq {}} { set p 1.0 }
      set sp [expr {$sp + $a * $p}]
      set sw [expr {$sw + $p}]
      set sh [expr {$sh + 1.0 / max($a, 1.0)}]
      incr k
    }
    if {!$k} { $f.prec$cle configure -text – ; continue }
    set acc [expr {(($sp / $sw) + ($k / $sh)) / 2.0}]
    $f.prec$cle configure -text "[format %.0f $acc] %"
  }
}

proc ::moderne::bilan::courbe {} {
  variable w
  variable trace
  set c $w.f.courbe
  if {![winfo exists $c]} { return }
  $c delete all
  update idletasks
  set larg [winfo width $c] ; if {$larg < 100} { set larg 420 }
  set haut [winfo height $c] ; if {$haut < 50} { set haut 110 }
  set elo [::moderne::oracle::eloPartie]
  set nb [llength $::moderne::oracle::positions]
  if {$nb < 3} { return }
  # room for the scale on the left, and above and under the curve (and,
  # for a game with move times, the White and Black time-trouble strips)
  set zl [zeitnot]
  set mg [expr {[llength $zl] ? 58 : 4}] ; set y0 4 ; set y1 [expr {$haut - 6 - ([llength $zl] ? 32 : 0)}]
  set h [expr {$y1 - $y0}]
  set dx [expr {double($larg - $mg - 4) / ($nb - 1)}]
  set trace [dict create mg $mg dx $dx y0 $y0 h $h nb $nb elo $elo zeit $zl]
  # (segments of consecutive evaluated positions: during the review the
  # cloud fills the start and the engine the end, the middle stays empty)
  set pts {}
  set segments {}
  set seg {}
  for {set i 0} {$i < $nb} {incr i} {
    set e [es $i $elo 1]
    if {$e eq {}} {
      if {[llength $seg] >= 4} { lappend segments $seg }
      set seg {}
      continue
    }
    lappend pts [expr {$mg + $i * $dx}] [expr {$y1 - $e / 100.0 * $h}]
    lappend seg [expr {$mg + $i * $dx}] [expr {$y1 - $e / 100.0 * $h}]
  }
  if {[llength $seg] >= 4} { lappend segments $seg }
  if {[llength $pts] < 4} {
    # (nothing evaluated yet: a message instead of an empty grey area)
    $c create text [expr {$larg / 2}] [expr {$haut / 2}] -font font_Small -fill [::moderne::c texteDoux] \
        -text [T "La courbe se dessine pendant l'analyse…" "The curve is drawn during the analysis…"]
    return
  }
  # As on Lichess: grey above the middle line (White better), black
  # under it (Black better), orange curve, no scale (the hover gives
  # the value)
  set fond [::moderne::c surface2]
  set xd [expr {$larg - 4}]
  set ym [expr {$y1 - $h / 2.0}]
  # luminous background: a vertical gradient, dark at the top, lighter
  # downwards (bands; the grey area follows it, band by band)
  set nbB 18
  set bandes {}
  for {set k 0} {$k < $nbB} {incr k} {
    set ya [expr {$y0 + $h * $k / double($nbB)}]
    set yb [expr {$y0 + $h * ($k + 1) / double($nbB)}]
    set t [expr {$k / double($nbB - 1)}]
    set cb [expr {$t < 0.5 ? [::moderne::barres::melange $fond #000000 [format %.2f [expr {0.45 * (1 - 2 * $t)}]]] \
                             : [::moderne::barres::melange $fond #ffffff [format %.2f [expr {0.10 * (2 * $t - 1)}]]]}]
    $c create rectangle $mg $ya $xd [expr {$yb + 1}] -fill $cb -outline {}
    lappend bandes $ya $yb $cb
  }
  set sombre [::moderne::barres::melange $fond #000000 0.85]
  foreach seg $segments {
    # (the crossings of the middle line inserted, so each side is exact)
    set pc {}
    set px {} ; set py {}
    foreach {x y} $seg {
      if {$px ne {} && ($py - $ym) * ($y - $ym) < 0} {
        lappend pc [expr {$px + ($x - $px) * ($ym - $py) / double($y - $py)}] $ym
      }
      lappend pc $x $y
      set px $x ; set py $y
    }
    set xa [lindex $pc 0] ; set xb [lindex $pc end-1]
    # White better: the band's colour lightened, between the curve and
    # the middle line
    foreach {ya yb cb} $bandes {
      if {$ya >= $ym} { break }
      set yb [expr {min($yb, $ym)}]
      set haut {}
      set vide 1
      foreach {x y} $pc {
        set yy [expr {max($ya, min($yb, $y))}]
        if {$yy < $yb} { set vide 0 }
        lappend haut $x $yy
      }
      if {$vide} { continue }
      $c create polygon $xa $yb {*}$haut $xb $yb -fill [::moderne::barres::melange $cb #ffffff 0.22] -outline {}
    }
    # Black better: black under the middle line
    set bas {}
    foreach {x y} $pc { lappend bas $x [expr {max($y, $ym)}] }
    $c create polygon $xa $ym {*}$bas $xb $ym -fill $sombre -outline {}
  }
  $c create line $mg $ym $xd $ym -fill [::moderne::barres::melange $fond #ffffff 0.35]
  # phases, as Lichess divides a game: Opening, Middlegame, Endgame
  lassign [phases] milieu fin
  if {$milieu ne {} || $fin ne {}} {
    foreach {i fr en} [list 0 Ouverture Opening $milieu "Milieu de jeu" Middlegame $fin Finale Endgame] {
      if {$i eq {}} { continue }
      set x [expr {$mg + $i * $dx + ($i == 0 ? 1 : 0)}]
      $c create line $x $y0 $x $y1 -fill [::moderne::barres::melange $fond #ffffff 0.30]
      $c create text [expr {$x + 2}] [expr {$y0 + 3}] -angle 270 -anchor sw -text [T $fr $en] \
          -font font_Small -fill [::moderne::c texteDoux]
    }
  }
  foreach seg $segments { $c create line {*}$seg -fill #d85000 -width 2 }
  # time trouble of each side, move by move: orange short of time, red
  # time trouble (zeitnot)
  if {[llength $zl]} {
    foreach {coul ligne nom} [list 1 0 [T Blancs White] 0 1 [T Noirs Black]] {
      set ya [expr {$y1 + 14 + $ligne * 11}] ; set yb [expr {$ya + 7}]
      $c create rectangle $mg $ya [expr {$larg - 4}] $yb -fill [::moderne::c surface2] -outline {}
      $c create text [expr {$mg - 5}] [expr {($ya + $yb) / 2}] -anchor e -text $nom -font font_Small -fill [::moderne::c texteDoux]
      set ply 0
      foreach z $zl {
        incr ply
        if {($ply % 2) != $coul || $z eq {} || [lindex $z 0] == 0} { continue }
        # (from the move to the side's next one: no gaps between its moves)
        set xa [expr {$mg + ($ply - 1) * $dx}] ; set xb [expr {min($larg - 4, $mg + ($ply + 1) * $dx)}]
        $c create rectangle $xa $ya $xb $yb -outline {} \
            -fill [expr {[lindex $z 0] == 2 ? "#df5353" : "#e69f00"}]
      }
    }
  }
  # mistakes marked with their colour
  sc_game push copy
  sc_move start
  set i 0
  while {![sc_pos isAt end]} {
    sc_move forward
    incr i
    foreach x [sc_pos getNags] {
      set coul [dict get {?? #df5353 ? #e69f00 ?! #56b4e9 ! #22ac38 !! #168226 X {}} [expr {$x in {?? ? ?! ! !!} ? $x : "X"}]]
      if {$coul eq {}} { continue }
      set e [es $i $elo 1]
      if {$e eq {}} { continue }
      set px [expr {$mg + $i * $dx}] ; set py [expr {$y1 - $e / 100.0 * $h}]
      $c create oval [expr {$px - 3}] [expr {$py - 3}] [expr {$px + 3}] [expr {$py + 3}] -fill $coul -outline $coul
    }
  }
  sc_game pop
  bind $c <ButtonRelease-1> {::moderne::bilan::allerA %x}
  bind $c <Motion> {::moderne::bilan::survol %x}
  bind $c <Leave> ::moderne::bilan::finSurvol
  $c configure -cursor hand2
  catch epingler
}

### Plies where the middlegame and the endgame start, as Lichess divides a
### game (scalachess Divider): middlegame at the first position with at
### most 10 pieces (no kings, no pawns), or fewer than 4 pieces of a side
### on its back rank, or mixed pieces (mixedness over 150); endgame at the
### first with at most 6 pieces. {} for a phase not reached
proc ::moderne::bilan::phases {} {
  # (the same game's positions: the phases kept; the curve, redrawn every
  # 2 s during the review, computed them each time, 2026-11-06)
  variable phasesMemo
  if {[info exists phasesMemo] && [lindex $phasesMemo 0] eq $::moderne::oracle::positions} {
    return [lindex $phasesMemo 1]
  }
  set r [phasesCalcul]
  set phasesMemo [list $::moderne::oracle::positions $r]
  return $r
}
proc ::moderne::bilan::phasesCalcul {} {
  set milieu {} ; set fin {}
  set i 0
  foreach p $::moderne::oracle::positions {
    set cases [casesFen [lindex $p 0]]
    set pieces 0
    foreach x $cases { if {$x ne "." && [string tolower $x] ni {k p}} { incr pieces } }
    if {$milieu eq {}} {
      # (first rank: index 0 to 7, last rank: 56 to 63)
      set rb 0 ; set rn 0
      for {set k 0} {$k < 8} {incr k} {
        if {[string is upper [lindex $cases $k]] && [lindex $cases $k] ne "."} { incr rb }
        set x [lindex $cases [expr {56 + $k}]]
        if {$x ne "." && [string is lower $x]} { incr rn }
      }
      if {$pieces <= 10 || $rb < 4 || $rn < 4 || [melee $cases] > 150} { set milieu $i }
    }
    if {$milieu ne {} && $pieces <= 6} { set fin $i ; break }
    incr i
  }
  if {$milieu ne {} && $fin ne {} && $milieu >= $fin} { set milieu {} }
  return [list $milieu $fin]
}

### The 64 squares of a FEN (a1 = 0, h8 = 63), "." for an empty one
proc ::moderne::bilan::casesFen {fen} {
  set rangs [lreverse [split [lindex [split $fen] 0] /]]
  set res {}
  foreach r $rangs {
    foreach ch [split $r {}] {
      if {[string is digit $ch]} { lappend res {*}[lrepeat $ch .] } else { lappend res $ch }
    }
  }
  return $res
}

### Lichess's "mixedness": how much the two sides' pieces mingle, over
### every 2x2 block of the board
proc ::moderne::bilan::melee {cases} {
  set acc 0
  for {set yy 0} {$yy < 7} {incr yy} {
    set y [expr {$yy + 1}]
    for {set xx 0} {$xx < 7} {incr xx} {
      set b 0 ; set n 0
      foreach d {0 1 8 9} {
        set x [lindex $cases [expr {$yy * 8 + $xx + $d}]]
        if {$x eq "."} { continue }
        if {[string is upper $x]} { incr b } else { incr n }
      }
      incr acc [scoreMelee $y $b $n]
    }
  }
  return $acc
}

proc ::moderne::bilan::scoreMelee {y b n} {
  switch -- "$b$n" {
    01 { return [expr {1 + $y}] }
    02 { return [expr {$y < 6 ? 2 + (6 - $y) : 0}] }
    03 - 04 { return [expr {$y < 7 ? 3 + (7 - $y) : 0}] }
    10 { return [expr {1 + (8 - $y)}] }
    11 { return [expr {5 + abs(4 - $y)}] }
    12 { return [expr {4 + (7 - $y)}] }
    13 { return [expr {5 + (7 - $y)}] }
    20 { return [expr {$y > 2 ? 2 + ($y - 2) : 0}] }
    21 { return [expr {4 + ($y - 1)}] }
    22 { return 7 }
    30 - 40 { return [expr {$y > 1 ? 3 + ($y - 1) : 0}] }
    31 { return [expr {5 + ($y - 1)}] }
  }
  return 0
}

### The curve again at the canvas's size (only once it has been drawn)
proc ::moderne::bilan::courbeAjustee {} {
  variable trace
  variable w
  if {![info exists trace] || ![winfo exists $w.f.courbe]} { return }
  if {[llength [$w.f.courbe find all]]} { catch courbe }
}

### Ply under the pointer (0 = the start), or -1
proc ::moderne::bilan::plySous {x} {
  variable trace
  if {![info exists trace] || ![dict exists $trace dx]} { return -1 }
  set i [expr {int(round(($x - [dict get $trace mg]) / [dict get $trace dx]))}]
  set nb [dict get $trace nb]
  if {$i < 0} { set i 0 }
  if {$i >= $nb} { set i [expr {$nb - 1}] }
  return $i
}

### Hover: the move under the pointer, its position on the main board
### (under a veil, as when hovering an engine line) and its expected score
proc ::moderne::bilan::survol {x} {
  variable w
  variable survolPly
  set i [plySous $x]
  if {$i < 0} { return }
  if {[info exists survolPly] && $survolPly == $i} { return }
  set survolPly $i
  set plateau [marqueur $w.f.courbe $i survol]
  if {$plateau eq {}} { return }
  catch {$w.f.courbe itemconfigure epingle -state hidden}
  catch {::moderne::moteur::apercuPlateau $plateau}
}

### The blue cursor on the curve at ply i (a line, a dot at its expected
### score and a label: move, symbol, score, clock), drawn with tag tag;
### returns the board after the move ({} when out of the game)
proc ::moderne::bilan::marqueur {c i tag} {
  variable trace
  if {![info exists trace] || ![dict exists $trace dx]} { return {} }
  sc_game push copy
  sc_move start
  set ok 1
  if {$i > 0} { set ok [expr {![catch {sc_move forward $i}]}] }
  set plateau [sc_pos board]
  set coup {}
  catch {set coup [sc_game info previousMove]}
  # (the move's symbol: ?, !…)
  set symb {}
  if {$i > 0} { foreach x [sc_pos getNags] { if {$x in {!! ! !? ?! ? ??}} { append symb $x } } }
  sc_game pop
  if {!$ok} { return {} }
  $c delete $tag
  set mg [dict get $trace mg] ; set dx [dict get $trace dx]
  set y0 [dict get $trace y0] ; set h [dict get $trace h]
  set px [expr {$mg + $i * $dx}]
  $c create line $px $y0 $px [expr {$y0 + $h}] -fill [::moderne::c accent] -tags $tag
  set e [es $i [dict get $trace elo] 1]
  if {$e ne {}} {
    set py [expr {$y0 + $h - $e / 100.0 * $h}]
    $c create oval [expr {$px - 4}] [expr {$py - 4}] [expr {$px + 4}] [expr {$py + 4}] \
        -fill [::moderne::c accent] -outline [::moderne::c surface] -tags $tag
  }
  if {$i == 0} {
    set texte [T "Début" "Start"]
  } else {
    set num [expr {($i + 1) / 2}]
    set texte "$num[expr {$i % 2 ? "." : "..."}] [figurine $coup]$symb"
  }
  if {$e ne {}} { append texte "  •  [T Blancs White] [format %.0f $e] %" }
  # the mover's time before the move, and its time trouble
  set z {}
  if {$i > 0 && [dict exists $trace zeit]} { set z [lindex [dict get $trace zeit] [expr {$i - 1}]] }
  if {$z ne {}} {
    lassign $z niv t reste inc
    # ("1:32 + 30"/c pour 9 coups": the time left, the time added per move)
    set aj [expr {$inc > 0 ? " + [T "$inc\"/c" "${inc}s/move"]" : {}}]
    append texte "  •  [::moderne::direct::hms $t]$aj"
    if {$reste ne {}} { append texte " [T pour for] $reste [expr {$reste > 1 ? [T coups moves] : [T coup move]}]" }
  }
  set t [$c create text 0 0 -anchor nw -text $texte -font font_Small -fill [::moderne::c texteFort] -tags $tag]
  lassign [$c bbox $t] bx1 by1 bx2 by2
  set lw [expr {$bx2 - $bx1 + 12}] ; set lh [expr {$by2 - $by1 + 6}]
  set lx [expr {$px + 8}]
  if {$lx + $lw > [winfo width $c] - 2} { set lx [expr {$px - $lw - 8}] }
  if {$lx < 2} { set lx 2 }
  set ly [expr {$y0 + 2}]
  $c coords $t [expr {$lx + 6}] [expr {$ly + 3}]
  set r [$c create rectangle $lx $ly [expr {$lx + $lw}] [expr {$ly + $lh}] \
      -fill [::moderne::c surface] -outline [::moderne::c bordure] -tags $tag]
  $c raise $t $r
  return $plateau
}

### The cursor pinned on an annotated move clicked in the table, until the
### board moves (as the arrows); epinglePly unset: none
proc ::moderne::bilan::epingler {} {
  variable w
  variable epinglePly
  set c $w.f.courbe
  if {![winfo exists $c]} { return }
  $c delete epingle
  if {![info exists epinglePly]} { return }
  marqueur $c $epinglePly epingle
}

### "Nf6" as the notation shows it ("♘f6", "Nf6" or "Cf6")
proc ::moderne::bilan::figurine {san} {
  return [::moderne::coupTexte $san]
}

proc ::moderne::bilan::finSurvol {} {
  variable w
  variable survolPly
  catch {unset survolPly}
  catch {$w.f.courbe delete survol}
  catch {$w.f.courbe itemconfigure epingle -state normal}
  catch {::moderne::moteur::finApercu}
}

proc ::moderne::bilan::allerA {x} {
  set i [plySous $x]
  if {$i < 0} { return }
  finSurvol
  sc_move start
  if {$i > 0} { catch {sc_move forward $i} }
  updateBoard -pgn
}

################################################################################
### Moves coloured by their symbol in the notation, as on Lichess:
### !! dark green, ! green, !? pink, ?! blue, ? orange, ?? red
################################################################################

### Move times shown in the notation (option): the ones the next move of
### that side is played with, coloured when short of time (orange) or in
### time trouble (red), as on the review's curve
proc ::moderne::bilan::tempsCouleurs {t} {
  if {![info exists ::moderne::tempsCoups] || !$::moderne::tempsCoups} { return }
  set zl [zeitnot]
  if {![llength $zl]} { return }
  $t tag configure zeit0 -foreground [::moderne::c texteDoux]
  $t tag configure zeit1 -foreground #e69f00
  $t tag configure zeit2 -foreground #df5353
  sc_game push copy
  foreach tag [$t tag names] {
    if {![regexp {^c_([0-9]+)$} $tag -> n]} { continue }
    if {[catch {sc_move pgn $n}] || [sc_var level] != 0} { continue }
    # (the time after move p: the side's next move, ply p + 2, starts with it)
    set niv [lindex $zl [expr {[sc_pos location] + 1}] 0]
    if {$niv eq {}} { set niv 0 }
    set debut [lindex [$t tag ranges $tag] 0]
    if {$debut eq {}} { continue }
    if {[regexp -indices {^\s*([0-9]+:[0-9:]+)} [$t get $debut "$debut + 24 chars"] -> idx]} {
      lassign $idx a b
      $t tag add zeit$niv "$debut + $a chars" "$debut + [expr {$b + 1}] chars"
    }
  }
  sc_game pop
  catch {$t tag raise zeit0 ; $t tag raise zeit1 ; $t tag raise zeit2}
}

proc ::moderne::bilan::couleurs {t} {
  set couls {!! #168226 ! #22ac38 !? #ea45d8 ?! #56b4e9 ? #e69f00 ?? #df5353}
  set codes {$3 !! $1 ! $5 !? $6 ?! $2 ? $4 ??}
  foreach {s c} $couls {
    $t tag configure symb$s -foreground $c
    catch {$t tag raise symb$s}
  }
  set i 1.0
  while {[set r [$t tag nextrange nag $i]] ne {}} {
    lassign $r a b
    set i $b
    set x [string trim [$t get $a $b]]
    if {[dict exists $codes $x]} { set x [dict get $codes $x] }
    if {![dict exists $couls $x]} { continue }
    $t tag add symb$x $a $b
    # the move just before the symbol (maybe after a space)
    set fait 0
    for {set k 1} {$k <= 3 && !$fait} {incr k} {
      foreach tag [$t tag names "$a - $k chars"] {
        if {[string match m_* $tag]} {
          set m [$t tag prevrange $tag "$a"]
          if {$m ne {}} { $t tag add symb$x {*}$m }
          set fait 1
          break
        }
      }
    }
  }
}

### End Siby

### The end of each part, noted once (traces on annotFinie and niveauFait)
proc ::moderne::bilan::noterFin {nom args} {
  variable chrono
  variable $nom
  if {![info exists chrono] || ![info exists $nom] || ![set $nom]} { return }
  if {![dict exists $chrono $nom]} { dict set chrono $nom [clock milliseconds] }
}
trace add variable ::moderne::bilan::annotFinie write {::moderne::bilan::noterFin annotFinie}
trace add variable ::moderne::bilan::niveauFait write {::moderne::bilan::noterFin niveauFait}

### review.log (Siby's folder): one line per review, the last 50 kept: the
### computer (cores, NVIDIA card, free memory), how the review shared it
### (Toby processes, Maia threads, engine pool) and the time of each part,
### to see why a review is slow (Yosha 2026-11-02)
proc ::moderne::bilan::journalBilan {} {
  variable chrono
  if {![info exists chrono] || ![dict exists $chrono debut]} { return }
  set t0 [dict get $chrono debut]
  set s {}
  foreach {k nom} {annotFinie annotation niveauFait level} {
    if {[dict exists $chrono $k]} { lappend s "$nom [format %.1f [expr {([dict get $chrono $k] - $t0) / 1000.0}]] s" }
  }
  lappend s "total [format %.1f [expr {([clock milliseconds] - $t0) / 1000.0}]] s"
  set coups 0
  catch {set coups [llength $::moderne::oracle::positions]}
  set p {}
  catch {set p [::moderne::niveau::partage]}
  set gpu 0
  catch {set gpu [::moderne::toby::carteNvidia]}
  set mem ?
  catch {set mem [::moderne::niveau::memoireLibre]}
  set l "[clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}] $coups positions: [join $s {, }];\
 [::moderne::toby::coeurs] cores, NVIDIA $gpu, free memory $mem MB, sharing {$p},\
 batches [expr {[catch {::moderne::niveau::lotUtile} b] ? 0 : $b}]"
  # (the game and the time control the level was computed with: a blitz
  # judged as classical could not be seen, Yosha 2026-11-11)
  catch {
    variable cle
    set tc {}
    catch {regexp {TimeControl "([^"]*)"} [sc_game tags get Extra] -> tc}
    set cad ?
    catch {lassign $::moderne::niveau::infos($cle) - cad}
    set niv {}
    foreach c {B N} {
      set e {}
      catch {set e [lindex [::moderne::niveau::estimation $cle $c] 0]}
      lappend niv [expr {$e eq {} ? "-" : $e}]
    }
    set lieu ?
    catch {set lieu [lindex $::moderne::niveau::infos($cle) 4]}
    set elos {}
    foreach c {B N} { lappend elos [expr {[::moderne::niveau::avecElo $cle $c] ? "rating" : "moves only"}] }
    append l "; [sc_game tags get White] - [sc_game tags get Black], TimeControl \"$tc\" read as\
 \"[::moderne::toby::tcPartie]\", level computed as $cad, place $lieu ([join $elos /]), levels [join $niv /]"
  }
  set f [file join $::scidUserDir review.log]
  set lignes {}
  catch { set h [open $f r] ; set lignes [split [string trimright [read $h] \n] \n] ; close $h }
  lappend lignes $l
  set lignes [lrange $lignes end-49 end]
  set h [open $f w] ; puts $h [join $lignes \n] ; close $h
  catch {puts stderr "Siby review: $l"}
}

################################################################################
### The review prepared during a game against Toby or an Alter Ego (option,
### on by default, Yosha 2026-11-03): while the player thinks (Toby's
### opponent idle) the level of play of the moves already played is
### computed; it pauses as soon as the engine has to move. At the end of
### the game the review takes the moves done and computes only the rest.
### The computer works during the game instead of all at once after it.
################################################################################

namespace eval ::moderne::bilan::prepa {
  variable actif          ;# option (saved)
  if {![info exists actif]} { set actif 1 }
  variable cle {}         ;# the level's key of the game being prepared
  variable sig {}         ;# its settings {start cadence eloDist}
  variable finies {}      ;# finished games still computing: id -> key
}

proc ::moderne::bilan::prepa::reglages {} {
  set depart startpos
  catch { if {[sc_game startBoard]} { set depart [sc_game startPos] } }
  set cad Classical
  catch {set cad [::moderne::toby::cadenceBilan]}
  return [list $depart $cad [::moderne::oracle::eloPartie]]
}

### The player's turn (sergame::engineGo, every second): the moves played
### so far are handed to the level, which runs again
proc ::moderne::bilan::prepa::avancer {} {
  variable actif
  variable cle
  variable sig
  if {!$actif || ![::moderne::niveau::disponible]} { return }
  # (a fast game: the opponent alone on the computer, the review after)
  if {![catch {::moderne::toby::ombre::partieRapide} r] && $r} { return }
  # (enough memory for one more Toby besides the opponent: else nothing)
  if {[::moderne::niveau::memoireLibre] < 4000} { return }
  set s [reglages]
  if {$cle eq {} || $s ne $sig} {
    oublier
    set cle "prepa:[clock milliseconds]"
    set sig $s
    ::moderne::niveau::suivre $cle 0 0 FIDE [lindex $s 1] {} [dict create eloDist [lindex $s 2]]
  }
  set ::moderne::niveau::pause 0
  ::moderne::niveau::coupsPartie $cle
}

### The engine's turn: nothing new sent to the level (the move under way
### ends), the opponent has the computer
proc ::moderne::bilan::prepa::pause {} {
  variable cle
  if {$cle ne {}} { set ::moderne::niveau::pause 1 }
}

### Identity of the game on the board for the prepared level: its start,
### its moves and settings
proc ::moderne::bilan::prepa::id {} {
  return [format %08x [zlib crc32 "[reglages] [::moderne::bilan::coupsUci]"]]
}

proc ::moderne::bilan::prepa::fichier {id} {
  return [file join $::scidUserDir bilans "$id.niveau"]
}

### End of a game (jeu::fin): its key goes on in the background until all
### its moves are done, then is saved: a review opened later (after other
### games, or another day) takes it
proc ::moderne::bilan::prepa::finPartie {} {
  variable cle
  variable sig
  variable finies
  if {$cle eq {}} { return }
  if {[reglages] ne $sig} { oublier ; return }
  set id [id]
  # (prepared levels older than 90 days: dropped)
  catch {
    foreach f [glob -nocomplain -directory [file join $::scidUserDir bilans] *.niveau] {
      if {[clock seconds] - [file mtime $f] > 90 * 86400} { file delete $f }
    }
  }
  dict set finies $id $cle
  set ::moderne::niveau::rappels($cle) [list ::moderne::bilan::prepa::fini $id]
  ::moderne::niveau::coupsPartie $cle
  set cle {}
  set sig {}
  set ::moderne::niveau::pause 0
  ::moderne::niveau::suivant
  fini $id
}

### A finished game's key: saved once all its moves are computed
proc ::moderne::bilan::prepa::fini {id} {
  variable finies
  if {![dict exists $finies $id]} { return }
  set c [dict get $finies $id]
  if {[::moderne::niveau::restants $c] > 0} { return }
  if {[catch {::moderne::niveau::sauver $c [fichier $id]} ok] || !$ok} { return }
  dict unset finies $id
  ::moderne::niveau::oublier $c
}

### The key prepared for the game on the board ({} if none): the game being
### played, a finished game still computing, or one saved on disk. The
### review goes on with it.
proc ::moderne::bilan::prepa::reprendre {} {
  variable cle
  variable sig
  variable finies
  set ::moderne::niveau::pause 0
  if {$cle ne {} && [reglages] eq $sig} {
    set c $cle
    set cle {}
    set sig {}
    return $c
  }
  oublier
  set id [id]
  if {[dict exists $finies $id]} {
    set c [dict get $finies $id]
    dict unset finies $id
    return $c
  }
  set f [fichier $id]
  if {[file exists $f]} {
    set c "prepa:[clock milliseconds]"
    if {[::moderne::niveau::charger $c $f]} { return $c }
  }
  return {}
}

proc ::moderne::bilan::prepa::oublier {} {
  variable cle
  variable sig
  set ::moderne::niveau::pause 0
  if {$cle ne {}} { catch {::moderne::niveau::oublier $cle} }
  set cle {}
  set sig {}
}
