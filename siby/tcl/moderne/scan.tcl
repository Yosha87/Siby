
###
### Siby: repertoire scan (ChessBase's "Repertoire scan")
###
### The recent games of a database (Gaby) are compared with one's
### repertoire (a database of lines, variations included, for example the
### course cleaned with Clean PGN) and listed, grouped by position:
###   - opponents' novelties: the opponent of the repertoire side plays a
###     move the repertoire does not cover;
###   - games that go beyond the preparation (end of a repertoire line):
###     what is played next;
###   - optionally, deviations by the repertoire side (other ideas for oneself).
### Positions are compared, not move orders: transpositions are
### recognized. Double-click on a game: it opens at the position of the
### deviation. The date of the most recent game seen is remembered: the
### next scan starts from there (weekly scan).
###
### Tools › Scan my repertoire…
###

namespace eval ::moderne::scan {
  variable w .scanWin
  variable baseRep 0
  variable baseScan 0
  variable couleur white
  variable depuis {}
  variable eloMin 2200
  variable cadence {}
  variable monCamp 0         ;# also show deviations by my side
  variable eloFort 2450      ;# average Elo from which an isolated deviation is examined
  variable maxExamens 150    ;# deviations whose history is looked up (tree search)
  variable historique        ;# historique(key) = games played before the period
  variable arret 0
  variable repCoups          ;# repCoups(key) = SAN moves of the repertoire
  variable repProf           ;# maximum depth of the repertoire (plies)
  variable groupes           ;# groupes(cat|key|move) = list of games
  variable lignes            ;# lignes(cat|key|move) = {lineText expected}
  variable ouvrir            ;# ouvrir(item) = {gnum ply}
  array set repCoups {}
  array set groupes {}
  array set lignes {}
  array set ouvrir {}
  array set historique {}
}

proc ::moderne::scan::T {fr en} { return [::moderne::tr $fr $en] }

################################################################################
### Reading the repertoire
################################################################################

proc ::moderne::scan::lireRepertoire {b} {
  variable repCoups
  variable repProf
  array unset repCoups
  set courante [sc_base current]
  if {$courante != $b} { sc_base switch $b }
  set suivants [dict create]
  set nb 0
  for {set g 1} {$g <= [sc_base numGames $b]} {incr g} {
    if {[catch {sc_game edges $g} e]} { continue }
    foreach {avant coup apres} $e {
      set k [::moderne::biblio::cle $avant]
      set k2 [::moderne::biblio::cle $apres]
      if {![info exists repCoups($k)]} { set repCoups($k) {} ; incr nb }
      if {$coup ni $repCoups($k)} { lappend repCoups($k) $coup }
      dict lappend suivants $k $k2
      if {![info exists repCoups($k2)]} { set repCoups($k2) {} }
    }
  }
  if {$courante != $b} { sc_base switch $courante }
  # Depth: breadth-first traversal from the starting positions
  set repProf 0
  set debut [::moderne::biblio::cle "RNBQKBNRPPPPPPPP................................pppppppprnbqkbnr w"]
  set vus [dict create $debut 0]
  set file [list $debut]
  while {[llength $file]} {
    set k [lindex $file 0]
    set file [lrange $file 1 end]
    set p [dict get $vus $k]
    if {$p > $repProf} { set repProf $p }
    if {![dict exists $suivants $k]} { continue }
    foreach k2 [dict get $suivants $k] {
      if {![dict exists $vus $k2]} { dict set vus $k2 [expr {$p + 1}] ; lappend file $k2 }
    }
  }
  return $nb
}

################################################################################
### Window
################################################################################

proc ::moderne::scan::ouvrir {} {
  variable w
  variable baseRep
  variable baseScan
  # One-off tool: separate window (not a tab of the layout)
  if {[winfo exists $w]} { raiseWin $w ; return }
  if {!$baseScan || ![sc_base inUse $baseScan]} { set baseScan [::moderne::prepa::baseParDefaut] }
  # (the repertoire of the profile for this colour, if there is one)
  if {!$baseRep || ![sc_base inUse $baseRep]} {
    set baseRep 0
    catch {set baseRep [::moderne::profil::baseRepertoire $::moderne::scan::couleur]}
    if {!$baseRep} { set baseRep [sc_base current] }
  }
  toplevel $w
  wm title $w [T "Scanner mon répertoire" "Scan my repertoire"]
  wm geometry $w 1150x820

  set h $w.haut
  ttk::frame $h -padding {10 8 10 4}
  pack $h -side top -fill x
  ttk::label $h.lr -text [T "Mon répertoire :" "My repertoire:"]
  ttk::combobox $h.rep -width 32 -state readonly
  ttk::radiobutton $h.blancs -text [T "je joue les Blancs" "I play White"] -variable ::moderne::scan::couleur -value white \
      -command ::moderne::scan::dateParDefaut
  ttk::radiobutton $h.noirs -text [T "je joue les Noirs" "I play Black"] -variable ::moderne::scan::couleur -value black \
      -command ::moderne::scan::dateParDefaut
  grid $h.lr $h.rep $h.blancs $h.noirs -padx 4 -pady 2 -sticky w
  ttk::label $h.lb -text [T "Base à scanner :" "Database to scan:"]
  ttk::combobox $h.base -width 32 -state readonly
  grid $h.lb $h.base -padx 4 -pady 2 -sticky w
  ttk::frame $h.f
  ttk::label $h.f.ld -text [T "Parties depuis le :" "Games since:"]
  ttk::entry $h.f.depuis -width 11 -textvariable ::moderne::scan::depuis
  ttk::label $h.f.le -text [T "Elo min. (les deux) :" "Min. Elo (both):"]
  ttk::spinbox $h.f.elo -width 6 -from 0 -to 3000 -increment 100 -textvariable ::moderne::scan::eloMin
  ttk::label $h.f.lc -text [T "Cadence :" "Time control:"]
  ::moderne::cadence::barre $h.f.cadence ::moderne::scan::cadence {}
  pack $h.f.ld $h.f.depuis $h.f.le $h.f.elo $h.f.lc $h.f.cadence -side left -padx 4
  ttk::frame $h.f2
  ttk::label $h.f2.lf -text [T "Examiner aussi les écarts isolés à partir d'un Elo moyen de :" "Also examine isolated deviations from avg Elo:"]
  ttk::spinbox $h.f2.fort -width 6 -from 0 -to 3000 -increment 50 -textvariable ::moderne::scan::eloFort
  pack $h.f2.lf $h.f2.fort -side left -padx 4
  grid $h.f - - - -sticky w -pady 2
  grid $h.f2 - - - -sticky w -pady 2
  ttk::frame $h.o
  ttk::checkbutton $h.o.moi -text [T "Montrer aussi les écarts de mon camp" "Also show deviations by my side"] \
      -variable ::moderne::scan::monCamp
  ttk::button $h.o.go -text [T "Scanner" "Scan"] -command ::moderne::scan::lancer
  ttk::button $h.o.stop -text [T "Arrêter" "Stop"] -command {set ::moderne::scan::arret 1} -state disabled
  pack $h.o.moi -side left -padx 4
  pack $h.o.go $h.o.stop -side left -padx 4
  grid $h.o - - - -sticky w -pady 2

  ttk::label $w.res -font font_Bold -padding {12 4} -wraplength 900 -justify left -text [T \
"Choisis la base de ton répertoire (lignes et variantes), ta couleur et la base à scanner, puis « Scanner »." \
"Choose your repertoire database (lines and variations), your colour and the database to scan, then Scan."]
  pack $w.res -side top -fill x

  set f $w.f
  ttk::frame $f -padding {10 0 10 4}
  pack $f -side top -fill both -expand 1
  ttk::treeview $f.t -columns {n avant elo der meilleure prevu} -selectmode browse
  $f.t heading #0 -text [T "Position et coup joué" "Position and move played"] -anchor w
  $f.t column #0 -width 420 -stretch 1
  foreach {c fr en l ancre} {
    n         Parties          Games          65  e
    avant     "Avant la période" "Before"     110  e
    elo       "Elo moy."       "Avg Elo"      70  e
    der       "Dernière"       "Last"         95  center
    meilleure "Meilleure partie / joueur·ses" "Best game / players" 260 w
    prevu     "Mon répertoire" "My repertoire" 150 w
  } {
    $f.t heading $c -text [T $fr $en] -anchor [expr {$ancre eq "w" ? "w" : "center"}]
    $f.t column $c -width $l -anchor $ancre -stretch [expr {$c eq "meilleure"}]
  }
  set sombre [expr {[::moderne::actif] && $::moderne::theme eq "sombre"}]
  $f.t tag configure categorie -font font_Bold
  $f.t tag configure adv -foreground [expr {$sombre ? "#f0b35b" : "#a35a00"}]
  ttk::scrollbar $f.sb -command [list $f.t yview]
  $f.t configure -yscrollcommand [list $f.sb set]
  pack $f.sb -side right -fill y
  pack $f.t -side left -fill both -expand 1
  bind $f.t <Double-Button-1> {::moderne::scan::ouvrirPartie ; break}
  bind $f.t <Return> {::moderne::scan::ouvrirPartie ; break}

  ttk::label $w.aide -foreground gray50 -padding {12 0 12 8} -wraplength 900 -justify left -text [T \
"Les positions sont comparées (transpositions reconnues). Déplie une ligne pour voir les parties ; double-clic sur une partie pour l'ouvrir à la position de l'écart. La date de la partie la plus récente est retenue pour le prochain scan." \
"Positions are compared (transpositions recognised). Expand a row to see the games; double-click a game to open it at the deviation. The latest game date is remembered for the next scan."]
  catch {::moderne::enBulle $w.aide}
  pack $w.aide -side bottom -fill x

  majBases
  bind $h.rep <<ComboboxSelected>> {
    set ::moderne::scan::baseRep [::moderne::prepa::slotDepuisLibelle [%W get]]
    ::moderne::scan::dateParDefaut
  }
  bind $h.base <<ComboboxSelected>> {
    set ::moderne::scan::baseScan [::moderne::prepa::slotDepuisLibelle [%W get]]
  }
  bind $h.rep <Button-1> {+::moderne::scan::majBases}
  bind $h.base <Button-1> {+::moderne::scan::majBases}
  bind $w <Escape> [list destroy $w]
  catch {::moderne::repeindre $w}
  dateParDefaut
}

proc ::moderne::scan::majBases {} {
  variable w
  variable baseRep
  variable baseScan
  set libs {}
  foreach {b lib} [::moderne::prepa::bases] { lappend libs $lib }
  $w.haut.rep configure -values $libs
  $w.haut.base configure -values $libs
  if {[sc_base inUse $baseRep]} { $w.haut.rep set [::moderne::prepa::libelleBase $baseRep] }
  if {[sc_base inUse $baseScan]} { $w.haut.base set [::moderne::prepa::libelleBase $baseScan] }
}

### File that remembers the date of the last scan (per repertoire and color)
proc ::moderne::scan::fichierDate {} {
  variable baseRep
  variable couleur
  if {![sc_base inUse $baseRep]} { return {} }
  regsub -all {[^[:alnum:]_-]+} [file rootname [file tail [sc_base filename $baseRep]]] _ nom
  set dir [file join $::scidUserDir data]
  file mkdir $dir
  return [file join $dir "scan_${nom}_$couleur.txt"]
}

### Default date: the one remembered from the last scan, otherwise a year ago
proc ::moderne::scan::dateParDefaut {} {
  variable depuis
  set f [fichierDate]
  if {$f ne {} && [file exists $f]} {
    catch {
      set c [open $f r]
      set d [string trim [read $c]]
      close $c
      if {[regexp {^[0-9]{4}\.[0-9]{2}\.[0-9]{2}$} $d]} { set depuis $d ; return }
    }
  }
  set depuis [clock format [expr {[clock seconds] - 365 * 86400}] -format %Y.%m.%d]
}

################################################################################
### Scan
################################################################################

proc ::moderne::scan::lancer {} {
  variable w
  variable baseRep
  variable baseScan
  variable couleur
  variable depuis
  variable eloMin
  variable cadence
  variable monCamp
  variable arret
  variable repCoups
  variable repProf
  variable groupes
  variable lignes
  if {![sc_base inUse $baseRep] || ![sc_base inUse $baseScan]} {
    tk_messageBox -parent $w -icon warning -type ok -title Siby -message [T \
        "Choisis la base du répertoire et la base à scanner." "Choose the repertoire and the database to scan."]
    return
  }
  if {![regexp {^[0-9]{4}(\.[0-9]{2}(\.[0-9]{2})?)?$} $depuis]} {
    tk_messageBox -parent $w -icon warning -type ok -title Siby -message [T \
        "Date au format AAAA.MM.JJ (par exemple 2025.09.01)." "Date as YYYY.MM.DD (e.g. 2025.09.01)."]
    return
  }
  # A repertoire has at most a few thousand games: reading a large database
  # as a repertoire would take all the memory
  set nbRep [sc_base numGames $baseRep]
  if {$nbRep > 20000} {
    tk_messageBox -parent $w -icon warning -type ok -title Siby -message [T \
        "La base choisie comme répertoire a [::utils::thousands $nbRep] parties : choisis ta base de répertoire (quelques centaines de parties), pas une base de référence." \
        "The database chosen as repertoire has [::utils::thousands $nbRep] games: choose your repertoire database (a few hundred games), not a reference database."]
    return
  }
  $w.res configure -text [T "Lecture du répertoire…" "Reading the repertoire…"]
  update idletasks
  set nRep [lireRepertoire $baseRep]
  if {$nRep == 0} {
    $w.res configure -text [T "Le répertoire est vide." "The repertoire is empty."]
    return
  }
  array unset groupes
  array unset lignes
  set arret 0
  $w.haut.o.go configure -state disabled
  $w.haut.o.stop configure -state normal

  set courante [sc_base current]
  if {$courante != $baseScan} { sc_base switch $baseScan }
  # All games in the period: the total number of times a move was played
  # in the period is used to tell whether it had already been played before.
  # The Elo and time control are then used to pick the relevant deviations.
  set d $depuis
  while {[string length $d] < 10} { append d ".01" }
  # (SCID dates stop in 2047)
  sc_search header -date [list $d 2047.12.31] -filter RESET
  set drapeau 0
  if {$cadence ne {}} { set drapeau [::moderne::cadence::numero $cadence] }
  if {![string is integer -strict $eloMin]} { set eloMin 0 }
  set total [sc_filter count]
  set maxPlies [expr {$repProf + 2}]
  set vus 0
  set idx 0
  set plusRecente {}
  set t0 [clock milliseconds]
  for {set g [sc_filter first]} {$g && !$arret} {set g [sc_filter next $g]} {
    incr idx
    if {$idx % 500 == 0} {
      $w.res configure -text "[T "Scan" "Scanning"] : [::utils::thousands $idx] / [::utils::thousands $total]…"
      update
      if {![winfo exists $w]} { break }
    }
    if {[catch {sc_game boards $g $maxPlies} pos]} { continue }
    set n [llength $pos]
    set ecart {}
    for {set i 0} {$i < $n} {incr i} {
      set k [::moderne::biblio::cle [lindex $pos $i 1]]
      if {![info exists repCoups($k)]} { break }      ;# out of the repertoire from the start
      if {$i + 1 >= $n} { break }                       ;# game finished within the repertoire
      set coup [lindex $pos [expr {$i + 1}] 0]
      if {![llength $repCoups($k)]} {
        # End of a repertoire line: what is played next
        set ecart [list fin $k $coup $i]
        break
      }
      if {$coup in $repCoups($k)} { continue }
      set trait [string index [lindex $pos $i 1] 65]
      set moi [expr {($trait eq "w") == ($couleur eq "white")}]
      if {$moi && !$monCamp} { break }
      set ecart [list [expr {$moi ? "moi" : "adv"}] $k $coup $i]
      break
    }
    if {![llength $ecart]} { continue }
    incr vus
    lassign $ecart cat k coup i
    set cle "$cat|$k|$coup"
    # Game information (rank $idx in the filter); relevant if
    # both players have the minimum Elo and the requested time control
    set info [lindex [split [sc_game list $idx 1 "w*\tW*\tb*\tB*\tr*\td*\te*"] \n] 0]
    lassign [split $info \t] - eb - en
    set eb [string trim $eb] ; set en [string trim $en]
    set pert [expr {[string is integer -strict $eb] && [string is integer -strict $en] && $eb >= $eloMin && $en >= $eloMin}]
    if {$pert && $drapeau && ([catch {sc_game flag $drapeau $g} v] || $v ne "1")} { set pert 0 }
    lappend groupes($cle) [list $g $i $info $pert]
    if {![info exists lignes($cle)]} {
      set sans {}
      foreach p [lrange $pos 1 $i] { lappend sans [lindex $p 0] }
      set lignes($cle) [list $sans $coup $repCoups($k) [string index [lindex $pos $i 1] 65]]
    }
    set date [string trim [lindex [split $info \t] 5]]
    if {[regexp {^[0-9]{4}\.[0-9]{2}\.[0-9]{2}$} $date]} { set plusRecente [::moderne::prepa::plusRecente $date $plusRecente] }
  }
  # (the scanned database's filter is reset: nothing is left behind)
  catch {sc_filter reset}
  set erreurHisto {}
  if {!$arret && [catch {examinerHistorique} erreurHisto]} {
    set erreurHisto " • [T "historique incomplet" "history incomplete"] : $erreurHisto"
  } else {
    set erreurHisto {}
  }
  if {$courante != $baseScan} { sc_base switch $courante }
  catch {::windows::gamelist::Refresh}
  $w.haut.o.go configure -state normal
  $w.haut.o.stop configure -state disabled
  if {![winfo exists $w]} { return }
  set ms [expr {[clock milliseconds] - $t0}]
  # Date remembered for the next scan
  if {!$arret && [regexp {^[0-9]{4}\.[0-9]{2}\.[0-9]{2}$} $plusRecente]} {
    catch {
      set c [open [fichierDate] w]
      puts $c $plusRecente
      close $c
    }
  }
  afficher
  $w.res configure -text "[::utils::thousands $idx] [T "parties scannées depuis le" "games scanned since"] $depuis \
([format %.1f [expr {$ms / 1000.0}]] s) • [::utils::thousands $vus] [T "passent par mon répertoire et en sortent" "follow my repertoire then leave it"]\
[expr {$arret ? [T " (scan interrompu)" " (scan stopped)"] : ""}]$erreurHisto"
}

### Relevant games of a group and their average Elo
proc ::moderne::scan::pertinentes {cle} {
  variable groupes
  set l {}
  foreach p $groupes($cle) { if {[lindex $p 3]} { lappend l $p } }
  return $l
}

proc ::moderne::scan::eloMoyen {parties} {
  set s 0 ; set n 0
  foreach p $parties {
    lassign [split [lindex $p 2] \t] - eb - en
    foreach e [list [string trim $eb] [string trim $en]] {
      if {[string is integer -strict $e] && $e > 0} { incr s $e ; incr n }
    }
  }
  return [expr {$n ? $s / $n : 0}]
}

### For relevant opponents' novelties (strong players, or a move repeated
### in the period), number of games where the move had been played BEFORE
### the period: tree search in the whole database at the position of the
### deviation (total) minus the games of the period. The scanned database
### is the current database.
proc ::moderne::scan::examinerHistorique {} {
  variable w
  variable groupes
  variable historique
  variable baseScan
  variable eloFort
  variable maxExamens
  variable arret
  array unset historique
  set cands {}
  foreach cle [array names groupes "adv|*"] {
    set pert [pertinentes $cle]
    if {![llength $pert]} { continue }
    set elo [eloMoyen $pert]
    if {[llength $pert] >= 2 || $elo >= $eloFort} { lappend cands [list $cle [llength $pert] $elo] }
  }
  # Most played, then strongest first
  set cands [lsort -integer -decreasing -index 2 $cands]
  set cands [lsort -integer -decreasing -index 1 $cands]
  set cands [lrange $cands 0 [expr {$maxExamens - 1}]]
  set i 0
  foreach c $cands {
    if {$arret} { break }
    incr i
    set cle [lindex $c 0]
    set coup [lindex [split $cle |] 2]
    if {$i % 5 == 1} {
      $w.res configure -text "[T "Historique des nouveautés" "Novelty history"] : $i / [llength $cands]…"
      update
      if {![winfo exists $w]} { return }
    }
    lassign [lindex $groupes($cle) 0] g ply
    if {[catch {lindex [sc_game fens $g [expr {$ply + 1}]] $ply 1} fen] || $fen eq {}} { continue }
    set r [::moderne::entrainement::brouillon {
      sc_game startBoard $fen
      ::moderne::biblio::chercherIci $baseScan {}
    }]
    set total 0
    foreach l [lindex $r 1] {
      if {[lindex $l 0] eq $coup} { set total [lindex $l 2] ; break }
    }
    set historique($cle) [expr {max(0, $total - [llength $groupes($cle)])}]
  }
}

### Readable line "1.d4 d5 2.Nf3" for a list of moves from the start
proc ::moderne::scan::texteCoups {sans {debut 0}} {
  set res {}
  set i $debut
  foreach c $sans {
    if {$i % 2 == 0} { append res "[expr {$i / 2 + 1}].$c " } elseif {$res eq {}} {
      append res "[expr {$i / 2 + 1}]...$c "
    } else { append res "$c " }
    incr i
  }
  return [::trans [string trim $res]]
}

proc ::moderne::scan::afficher {} {
  variable w
  variable groupes
  variable lignes
  variable ouvrir
  variable historique
  set t $w.f.t
  $t delete [$t children {}]
  array unset ouvrir
  # Sorting the groups
  array set parCat {}
  foreach cle [array names groupes] {
    set cat [lindex [split $cle |] 0]
    if {$cat eq "adv"} {
      if {[info exists historique($cle)]} {
        set h $historique($cle)
        if {$h == 0} { set cat nouv } elseif {$h < 10} { set cat rare } else { set cat trou }
      } else {
        set cat autre
      }
    } elseif {![llength [pertinentes $cle]]} {
      set cat autre
    }
    lappend parCat($cat) $cle
  }
  foreach {cat ouvert fr en} {
    nouv 1 "Vraies nouveautés : jamais jouées avant la période dans cette position de mon répertoire" "Real novelties: never played before in this position of my repertoire"
    rare 1 "Coups rares qui reviennent (moins de 10 parties avant la période)" "Rare moves coming back (fewer than 10 games before)"
    trou 0 "Trous du répertoire : coups courants que mon répertoire ne prévoit pas" "Repertoire gaps: common moves my repertoire does not cover"
    fin 0 "Au-delà de ma préparation : ce qui se joue à la fin de mes lignes" "Beyond my preparation: what is played at the end of my lines"
    moi 0 "Écarts de mon camp : autres idées pour moi" "Deviations by my side: other ideas for me"
    autre 0 "Autres écarts (joueur·ses moins fort·es, coups isolés ou hors filtres)" "Other deviations (weaker players, isolated moves or outside filters)"
  } {
    if {![info exists parCat($cat)]} { continue }
    # Sort: novelties and rare moves by average Elo, holes by past frequency,
    # the rest by number of games
    set tri {}
    foreach c $parCat($cat) {
      set pert [pertinentes $c]
      set lp [expr {[llength $pert] ? $pert : $groupes($c)}]
      switch -- $cat {
        nouv - rare { set cleTri [eloMoyen $lp] }
        trou { set cleTri $historique($c) }
        default { set cleTri [llength $lp] }
      }
      lappend tri [list $c $cleTri]
    }
    set parent [$t insert {} end -text "[T $fr $en] ([llength $tri])" -open $ouvert -tags categorie]
    foreach x [lrange [lsort -integer -decreasing -index 1 $tri] 0 299] {
      set c [lindex $x 0]
      lassign $lignes($c) sans coup prevus trait
      set n [llength $sans]
      set num [expr {$n / 2 + 1}]
      if {$trait eq "w"} { set joue "$num.[::trans $coup]" } else { set joue "$num...[::trans $coup]" }
      set texte "[texteCoups $sans]  →  $joue"
      if {![llength $sans]} { set texte "→ $joue" }
      set pert [pertinentes $c]
      set parties [expr {[llength $pert] ? $pert : $groupes($c)}]
      set der {} ; set best {} ; set bestElo -1
      foreach p $parties {
        lassign [split [lindex $p 2] \t] bl eb no en res date tournoi
        set eb [string trim $eb] ; set en [string trim $en]
        if {[string is integer -strict $eb] && [string is integer -strict $en] && $eb + $en > $bestElo} {
          set bestElo [expr {$eb + $en}]
          set best "[string trim $bl] – [string trim $no] ([string trim $date])"
        }
        set der [::moderne::prepa::plusRecente [string trim $date] $der]
      }
      set prev [join [lmap m $prevus {::trans $m}] ", "]
      if {[lindex [split $c |] 0] eq "fin"} { set prev [T "(fin de ligne)" "(end of line)"] }
      set avant [expr {[info exists historique($c)] ? $historique($c) : "–"}]
      set elo [eloMoyen $parties]
      set tag [expr {$cat in {nouv rare} ? "adv" : ""}]
      set item [$t insert $parent end -text $texte -tags $tag -values [list \
          [llength $parties] $avant [expr {$elo ? $elo : ""}] [::moderne::prepa::date $der] $best $prev]]
      # The games (strongest first, 50 at most)
      set lp {}
      foreach p $parties {
        lassign [split [lindex $p 2] \t] bl eb no en res date tournoi
        set sc 0
        catch {set sc [expr {[string trim $eb] + [string trim $en]}]}
        lappend lp [list $sc $p]
      }
      foreach e [lrange [lsort -integer -decreasing -index 0 $lp] 0 49] {
        lassign [lindex $e 1] g ply info
        lassign [split $info \t] bl eb no en res date tournoi
        set id [$t insert $item end -text "[string trim $bl] ([string trim $eb]) – [string trim $no] ([string trim $en])  [string map {=-= ½-½} [string trim $res]]" \
            -values [list {} {} {} [::moderne::prepa::date [string trim $date]] [string trim $tournoi] {}]]
        set ouvrir($id) [list $g $ply]
      }
    }
  }
  if {![llength [$t children {}]]} {
    $t insert {} end -text [T "Aucune partie ne sort de ton répertoire sur cette période." \
                              "No game leaves your repertoire in this period."]
  }
}

proc ::moderne::scan::ouvrirPartie {} {
  variable w
  variable ouvrir
  variable baseScan
  set id [$w.f.t focus]
  if {![info exists ouvrir($id)]} {
    # Deviation line: expand / collapse
    if {$id ne {}} { $w.f.t item $id -open [expr {![$w.f.t item $id -open]}] }
    return
  }
  lassign $ouvrir($id) g ply
  ::moderne::biblio::ouvrirPartie $baseScan $g $ply
}

### End Siby
