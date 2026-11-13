###
### Siby: one Search window, in tabs (like ChessBase's), Yosha 2026-11-01
###
###   - at the top, the database searched (one of the open databases);
###   - tabs: Games (player and colour, opponent, ratings, event, site,
###     years, result seen from the player, time control, opening, text),
###     Position (partial position and material), Moves, Material and
###     patterns. The last three are the existing search windows, placed in
###     their tab (embedded toplevels, made when the tab is first shown);
###   - on the right, the preview of the games found (every tab);
###   - at the bottom, common to every tab: "Only within the games shown",
###     Clear, Search, Close.
### The old General search stays available: "More criteria…" (Games tab).
###

namespace eval ::moderne::recherche {
  variable w .rechercheWin
  variable form
  variable dansFiltre 0
  variable dedans 0        ;# an embedded window being made
  variable cible {}        ;# its name
  variable idCible {}      ;# the window id of its tab
  variable onglets {parties pos coups mat}
  variable utiliser        ;# utiliser(tab): its criteria used (combined)
  array set utiliser {parties 0 pos 0 coups 0 mat 0}
  variable et 0            ;# the search being made within the filter
  variable depuisPlus 0    ;# the search started from More criteria
}

proc ::moderne::recherche::T {fr en} { return [::moderne::tr $fr $en] }

proc ::moderne::recherche::formVide {} {
  variable form
  array set form {joueur {} couleur peu inverse 1 adversaire {} eloMin {} eloMax {} eloMode chaque tournoi {} lieu {}
    de {} a {} gains 1 nulles 1 pertes 1 cadence {} ecoDe {} ecoA {} texte {}}
}
::moderne::recherche::formVide

### The embedded windows: name, opening command (the window alone)
proc ::moderne::recherche::fenetre {onglet} {
  switch -- $onglet {
    pos   { return [list .positionsWin ::moderne::positions::ouvrir_seul] }
    coups { return [list .smv ::search::moves_seul] }
    mat   { return [list .motifsWin ::moderne::motifs::ouvrir_seul] }
  }
  return {}
}

proc ::moderne::recherche::ouvrir {{onglet parties}} {
  variable w
  if {![winfo exists $w]} { construire }
  wm deiconify $w
  raise $w
  catch {$w.nb select $w.nb.$onglet}
  majBases
  catch {focus $w.nb.parties.f.joueur}
}

proc ::moderne::recherche::construire {} {
  variable w
  toplevel $w -background [::moderne::c fond]
  wm title $w [T "Rechercher" "Search"]
  # the database searched
  set h [ttk::frame $w.h -padding {14 10 14 4}]
  pack $h -side top -fill x
  ttk::label $h.t -text [T "Rechercher dans" "Search in"] -font font_Bold
  ttk::combobox $h.base -width 40 -state readonly
  bind $h.base <<ComboboxSelected>> ::moderne::recherche::choisirBase
  ttk::label $h.k -text [T "Ctrl+Maj+F" "Ctrl+Shift+F"] -foreground [::moderne::c texteDoux]
  pack $h.t -side left
  pack $h.base -side left -padx 8
  pack $h.k -side right
  # bottom bar, common to every tab
  set b [ttk::frame $w.b -padding {14 8 14 12}]
  pack $b -side bottom -fill x
  ttk::checkbutton $b.filtre -variable ::moderne::recherche::dansFiltre
  ttk::label $b.etat -foreground [::moderne::c texteDoux]
  ttk::button $b.fermer -text [T "Fermer" "Close"] -command [list destroy $w]
  ttk::button $b.ok -text [T "Rechercher" "Search"] -command ::moderne::recherche::rechercher
  catch {$b.ok configure -style Accent.TButton}
  ttk::button $b.raz -text [T "Effacer les critères" "Clear criteria"] -command ::moderne::recherche::effacer
  # progress and Stop, for the Games search (it gave no progress: on a
  # large database Windows said "Not responding", Yosha 2026-11-02)
  canvas $b.prog -width 140 -height 6 -highlightthickness 0 -borderwidth 0 -background [::moderne::c surface2]
  $b.prog create rectangle 0 0 0 6 -fill [::moderne::c accent] -outline {} -tags bar
  ttk::button $b.stop -text [T "Arrêter" "Stop"] -command sc_progressBar
  # online tournaments of Gaby included or not (it was in the Search menu)
  ttk::checkbutton $b.otb -text [T "Tournois en ligne" "Online tournaments"] -variable ::moderne::otb::inclure \
      -command {catch ::moderne::otb::basculer ; ::moderne::recherche::majFiltre}
  catch {::utils::tooltip::Set $b.otb [T "Inclure les tournois en ligne de Gaby (Champions Chess Tour, Olympiade en ligne…) dans les recherches et la bibliothèque" \
      "Include Gaby's online tournaments (Champions Chess Tour, Online Olympiad…) in searches and the library"]}
  pack $b.filtre -side left
  pack $b.otb -side left -padx {12 0}
  pack $b.etat -side left -padx 16
  pack $b.fermer $b.ok -side right -padx {6 0}
  pack $b.raz -side right -padx {0 12}
  # criteria of several tabs combined (each searched within the results of
  # the one before, like ChessBase); none: the tab shown
  set u [ttk::frame $b.u]
  pack $u -side left -padx {24 0}
  ttk::label $u.t -text [T "Combiner :" "Combine:"]
  pack $u.t -side left
  foreach {o fr en} {parties Parties Games pos Position Position coups Coups Moves mat "Matériel et motifs" "Material and patterns"} {
    ttk::checkbutton $u.$o -text [T $fr $en] -variable ::moderne::recherche::utiliser($o) \
        -command ::moderne::recherche::majOnglets
    pack $u.$o -side left -padx {10 0}
  }
  catch {::utils::tooltip::Set $u.t [T "Les onglets cochés sont cherchés l'un après l'autre, chacun dans les résultats du précédent. Aucun coché : l'onglet affiché." "The ticked tabs are searched one after the other, each within the results of the one before. None ticked: the tab shown."]}
  # preview of the games found, on the right
  ::moderne::apercu::creer $w.r 30
  pack $w.r -side right -fill y -padx {6 14} -pady 6
  # the tabs
  ttk::notebook $w.nb
  pack $w.nb -side left -fill both -expand 1 -padx {14 0} -pady 6
  ongletParties
  foreach {o fr en} {pos "Position" "Position" coups "Coups" "Moves" mat "Matériel et motifs" "Material and patterns"} {
    # (a plain frame; the embedded window lives in a container inside it,
    # a new one each time: destroying an embedded window takes its
    # container with it, later)
    frame $w.nb.$o -background [::moderne::c fond]
    $w.nb add $w.nb.$o -text "  [T $fr $en]  "
  }
  bind $w <Return> ::moderne::recherche::rechercher
  bind $w <Escape> [list destroy $w]
  catch {::moderne::repeindre $w}
  # every tab made now: the window has the size of the largest one and
  # keeps it (it changed size from tab to tab)
  update idletasks
  foreach o {pos coups mat} {
    $w.nb select $w.nb.$o
    update idletasks
    embarquer $o
  }
  $w.nb select $w.nb.parties
  bind $w.nb <<NotebookTabChanged>> ::moderne::recherche::ongletChange
  # (a criterion changed in a tab: the tab ticked in "Combine", Yosha
  # 2026-11-02; the user may untick it)
  marquer parties $w.nb.parties
  # (never larger than the screen)
  update idletasks
  set lw [expr {min([winfo reqwidth $w], [winfo screenwidth $w] - 40)}]
  set lh [expr {min([winfo reqheight $w], [winfo screenheight $w] - 80)}]
  wm geometry $w ${lw}x${lh}
  # (the size taken: only the tab shown keeps its window)
  montrerSeul parties
  majBases
}

### The tabs whose criteria are combined show a ✓
proc ::moderne::recherche::majOnglets {} {
  variable w
  variable utiliser
  foreach {o fr en} {parties Parties Games pos Position Position coups Coups Moves mat "Matériel et motifs" "Material and patterns"} {
    catch {$w.nb tab $w.nb.$o -text "  [expr {$utiliser($o) ? "✓ " : ""}][T $fr $en]  "}
  }
}

### The open databases (not the clipbase), the current one chosen
proc ::moderne::recherche::majBases {} {
  variable w
  if {![winfo exists $w.h.base]} { return }
  set b [remplirChoix $w.h.base]
  # (an open database becomes the one searched; the reference still
  # closed is opened only when searching)
  if {$b ne {} && $b ne "ref" && $b != [sc_base current]} { choisirBase }
  majFiltre
}

proc ::moderne::recherche::choisirBase {} {
  variable w
  choisirDans $w.h.base
  majFiltre
}

### "Search in" for every search (this window, Current position, Players,
### Tournaments, Advanced header search; Yosha 2026-11-02): the reference
### database first, open or not, then the other open databases. Fills
### combobox cb and returns the database chosen ("ref": the reference, not
### open yet). The choice is shared by every search.
proc ::moderne::recherche::remplirChoix {cb} {
  variable basesDe
  variable choix
  set l {} ; set bases {}
  set refFichier {}
  catch {set refFichier [::moderne::mesbases::fichierRef]}
  set refSlot 0
  if {$refFichier ne {}} {
    catch {set refSlot [::moderne::mesbases::slot $refFichier]}
    if {!$refSlot && ![file exists $refFichier]} { set refFichier {} }
  }
  if {$refFichier ne {}} {
    set n [expr {$refSlot ? " ([::utils::thousands [sc_base numGames $refSlot]] [T parties games])" : ""}]
    lappend l "[::moderne::nomBase $refFichier]$n · [T référence reference]"
    lappend bases [expr {$refSlot ? $refSlot : "ref"}]
  }
  for {set i 1} {$i <= [sc_base count total]} {incr i} {
    if {![sc_base inUse $i] || $i == [sc_info clipbase] || $i == $refSlot} { continue }
    lappend l "[::moderne::nomBase [sc_base filename $i]] ([::utils::thousands [sc_base numGames $i]] [T parties games])"
    lappend bases $i
  }
  $cb configure -values $l
  set basesDe($cb) $bases
  # (the choice made stays; else the reference; without a reference, the
  # current database, as before)
  set k -1
  if {[info exists choix]} { set k [lsearch -exact $bases $choix] }
  if {$k < 0 && $refFichier eq {}} { set k [lsearch -exact $bases [sc_base current]] }
  if {$k < 0 && [llength $l]} { set k 0 }
  if {$k < 0} { return {} }
  $cb current $k
  set choix [lindex $bases $k]
  return $choix
}

### The database chosen in cb becomes the one searched (the reference opened
### if needed); the game on the board stays there, still in its own database
proc ::moderne::recherche::choisirDans {cb} {
  variable basesDe
  variable choix
  set i [$cb current]
  if {$i < 0 || ![info exists basesDe($cb)]} { return }
  set b [lindex $basesDe($cb) $i]
  set choix $b
  if {$b eq "ref"} {
    set b 0
    catch {set b [::moderne::mesbases::baseReference]}
    if {!$b} { return }
    set choix $b
  }
  if {$b ne {} && $b != [sc_base current]} {
    ::moderne::onglets::enGardant [list catch [list ::file::SwitchToBase $b]]
  }
}

### The same "Search in" at the top of an older search window w; maj: the
### window's own refresh after a change of database
proc ::moderne::recherche::ajouterChoix {w {maj {}}} {
  if {![winfo exists $w] || [winfo exists $w.sibyBase]} { return }
  set f [ttk::frame $w.sibyBase -padding {10 8 10 4}]
  ttk::label $f.t -text [T "Rechercher dans" "Search in"] -font font_Bold
  ttk::combobox $f.base -width 40 -state readonly
  pack $f.t -side left
  pack $f.base -side left -padx 8
  set premier [lindex [pack slaves $w] 0]
  if {$premier ne {}} { pack $f -side top -fill x -before $premier } else { pack $f -side top -fill x }
  bind $f.base <<ComboboxSelected>> [list apply {{cb maj} {
    ::moderne::recherche::choisirDans $cb
    if {$maj ne {}} { catch {uplevel #0 $maj} }
  }} $f.base $maj]
  # the database chosen is the one searched from now on
  remplirChoix $f.base
  choisirDans $f.base
  if {$maj ne {}} { catch {uplevel #0 $maj} }
}

### "Only within the games shown (n)"
proc ::moderne::recherche::majFiltre {} {
  variable w
  if {![winfo exists $w.b.filtre]} { return }
  set n 0
  catch {set n [sc_filter count]}
  $w.b.filtre configure -text [T "Chercher seulement dans les parties affichées ([::utils::thousands $n])" \
      "Only within the games shown ([::utils::thousands $n])"]
}

################################################################################
### Games tab
################################################################################

proc ::moderne::recherche::ongletParties {} {
  variable w
  set p [ttk::frame $w.nb.parties -padding 14]
  $w.nb add $p -text "  [T Parties Games]  "
  set f [ttk::frame $p.f]
  pack $f -side top -fill x
  set r 0
  # White and Black, and "either colour" (it was Player, colour, Opponent;
  # Yosha 2026-11-03)
  ttk::label $f.lj -text [T "Blancs" "White"]
  ttk::combobox $f.joueur -width 32 -textvariable ::moderne::recherche::form(joueur)
  catch {::moderne::suggestions::attacher $f.joueur ::moderne::rparties::suggestions \
      [list ::moderne::rparties::choisi ::moderne::recherche::form(joueur)]}
  grid $f.lj -row $r -column 0 -sticky w -pady 4
  grid $f.joueur -row $r -column 1 -sticky w -padx 8
  set rangBlancs $r
  incr r
  ttk::label $f.la -text [T "Noirs" "Black"]
  ttk::combobox $f.adv -width 32 -textvariable ::moderne::recherche::form(adversaire)
  catch {::moderne::suggestions::attacher $f.adv ::moderne::rparties::suggestions \
      [list ::moderne::rparties::choisi ::moderne::recherche::form(adversaire)]}
  ttk::checkbutton $f.inv -text [T "Ignorer les couleurs" "Ignore colours"] -variable ::moderne::recherche::form(inverse) \
      -command ::moderne::recherche::libellesResultat
  catch {::utils::tooltip::Set $f.inv [T "Les noms peuvent avoir les Blancs ou les Noirs" "The names may have White or Black"]}
  grid $f.la -row $r -column 0 -sticky w -pady 4
  grid $f.adv -row $r -column 1 -sticky w -padx 8
  # (beside both names, between the two rows, ticked by default: one
  # usually wants a player's games with both colours, Yosha 2026-11-03)
  grid $f.inv -row $rangBlancs -rowspan 2 -column 2 -sticky w -padx 8
  incr r
  # ratings (both players)
  # "each player": both ratings in the range; "average": the mean of the
  # two (games with a missing rating left out), Yosha 2026-11-03
  ttk::label $f.le -text [T "Elo" "Rating"]
  ttk::frame $f.elo
  ttk::spinbox $f.elo.a -width 6 -from 0 -to 3500 -increment 100 -textvariable ::moderne::recherche::form(eloMin)
  ttk::label $f.elo.t -text " – "
  ttk::spinbox $f.elo.b -width 6 -from 0 -to 3500 -increment 100 -textvariable ::moderne::recherche::form(eloMax)
  ttk::radiobutton $f.elo.chaque -text [T "de chaque joueur·se" "of each player"] \
      -variable ::moderne::recherche::form(eloMode) -value chaque
  ttk::radiobutton $f.elo.moy -text [T "moyen des deux" "average of both"] \
      -variable ::moderne::recherche::form(eloMode) -value moyenne
  catch {::utils::tooltip::Set $f.elo.chaque [T "Les deux joueur·ses doivent avoir un Elo entre ces deux nombres" \
      "Both players must have a rating between these two numbers"]}
  catch {::utils::tooltip::Set $f.elo.moy [T "La moyenne des deux Elo doit être entre ces deux nombres (parties sans Elo exclues)" \
      "The average of both ratings must be between these two numbers (games without ratings left out)"]}
  pack $f.elo.a $f.elo.t $f.elo.b -side left
  pack $f.elo.chaque -side left -padx {12 0}
  pack $f.elo.moy -side left -padx {8 0}
  grid $f.le -row $r -column 0 -sticky w -pady 4
  grid $f.elo -row $r -column 1 -sticky w -padx 8
  incr r
  foreach {cle fr en} {tournoi "Tournoi" "Event" lieu "Lieu" "Site"} {
    ttk::label $f.l$cle -text [T $fr $en]
    ttk::entry $f.$cle -width 34 -textvariable ::moderne::recherche::form($cle)
    grid $f.l$cle -row $r -column 0 -sticky w -pady 4
    grid $f.$cle -row $r -column 1 -sticky w -padx 8
    incr r
  }
  ttk::label $f.ld -text [T "Années" "Years"]
  ttk::frame $f.d
  ttk::spinbox $f.d.a -width 6 -from 1400 -to 2100 -textvariable ::moderne::recherche::form(de)
  ttk::label $f.d.t -text " – "
  ttk::spinbox $f.d.b -width 6 -from 1400 -to 2100 -textvariable ::moderne::recherche::form(a)
  pack $f.d.a $f.d.t $f.d.b -side left
  grid $f.ld -row $r -column 0 -sticky w -pady 4
  grid $f.d -row $r -column 1 -sticky w -padx 8
  incr r
  ttk::label $f.lr -text [T "Résultat" "Result"]
  ttk::frame $f.res
  foreach v {gains nulles pertes} {
    ttk::checkbutton $f.res.$v -variable ::moderne::recherche::form($v)
    pack $f.res.$v -side left -padx {0 12}
  }
  # (seen from the player when there is one; else White's / Black's win:
  # "Won" without a player meant White won, Yosha 2026-11-02)
  libellesResultat
  trace add variable ::moderne::recherche::form(joueur) write ::moderne::recherche::libellesResultat
  trace add variable ::moderne::recherche::form(adversaire) write ::moderne::recherche::libellesResultat
  grid $f.lr -row $r -column 0 -sticky w -pady 4
  grid $f.res -row $r -column 1 -columnspan 2 -sticky w -padx 8
  incr r
  ttk::label $f.lc -text [T "Cadence" "Time control"]
  catch {::moderne::cadence::barre $f.cad ::moderne::recherche::form(cadence) {} {sc_base current}}
  grid $f.lc -row $r -column 0 -sticky w -pady 4
  catch {grid $f.cad -row $r -column 1 -sticky w -padx 8}
  incr r
  ttk::label $f.lo -text [T "Ouverture (ECO)" "Opening (ECO)"]
  ttk::frame $f.eco
  ttk::entry $f.eco.a -width 6 -textvariable ::moderne::recherche::form(ecoDe)
  ttk::label $f.eco.t -text " – "
  ttk::entry $f.eco.b -width 6 -textvariable ::moderne::recherche::form(ecoA)
  pack $f.eco.a $f.eco.t $f.eco.b -side left
  grid $f.lo -row $r -column 0 -sticky w -pady 4
  grid $f.eco -row $r -column 1 -sticky w -padx 8
  incr r
  ttk::label $f.lt -text [T "Texte dans la partie" "Text in the game"]
  ttk::entry $f.texte -width 34 -textvariable ::moderne::recherche::form(texte)
  grid $f.lt -row $r -column 0 -sticky w -pady 4
  grid $f.texte -row $r -column 1 -sticky w -padx 8
  incr r
  ttk::button $f.plus -style Toolbutton -text [T "Plus de critères (titres FIDE, nombre de coups, fin de partie, drapeaux)…" \
      "More criteria (FIDE titles, game length, end of game, flags)…"] -command ::moderne::recherche::plus
  grid $f.plus -row $r -column 0 -columnspan 3 -sticky w -pady {14 0}
  foreach x {joueur adv tournoi lieu texte} { bind $f.$x <Return> {::moderne::recherche::rechercher ; break} }
}

### The sc_search header arguments of the Games tab
proc ::moderne::recherche::libellesResultat {args} {
  variable w
  variable form
  set f $w.nb.parties.f.res
  if {![winfo exists $f]} { return }
  # the names typed win or lose ("Carlsen gagne"), else White / Black
  set noms {}
  foreach v {joueur adversaire} defFr {"Les Blancs" "Les Noirs"} defEn {White Black} {
    set n [string trim [lindex [split [string trim $form($v)] ,] 0]]
    lappend noms [expr {$n eq {} ? [list [T $defFr $defEn] 1] : [list $n 0]}]
  }
  # (either colour with one name only: the other one is the opponent)
  set seul [expr {[lindex $noms 0 1] != [lindex $noms 1 1]}]
  set l {}
  foreach x $noms {
    lassign $x n pluriel
    if {$pluriel && $form(inverse) && $seul} {
      lappend l [T "L'adversaire gagne" "Opponent won"]
    } else {
      lappend l [expr {$pluriel ? [T "$n gagnent" "$n won"] : [T "$n gagne" "$n won"]}]
    }
  }
  set l [linsert $l 1 [T "Nulle" "Draw"]]
  foreach v {gains nulles pertes} t $l { $f.$v configure -text $t }
}

proc ::moderne::recherche::arguments {} {
  variable form
  variable dansFiltre
  set joueur [string trim $form(joueur)]
  set adv [string trim $form(adversaire)]
  set maxElo [sc_info limit elo]
  set e1 [expr {[string is integer -strict $form(eloMin)] ? $form(eloMin) : 0}]
  set e2 [expr {[string is integer -strict $form(eloMax)] && $form(eloMax) > 0 ? $form(eloMax) : $maxElo}]
  if {$form(eloMode) eq "moyenne"} {
    set welo [list 0 $maxElo] ; set moyelo [list $e1 $e2]
    # an untouched range keeps every game, rated or not
    if {$e1 == 0 && $e2 == $maxElo} { set moyelo [list 0 $maxElo] }
  } else {
    set welo [list $e1 $e2] ; set moyelo [list 0 $maxElo]
  }
  set de [expr {[string is integer -strict $form(de)] ? $form(de) : "0000"}]
  set a [expr {[string is integer -strict $form(a)] ? $form(a) : [sc_info limit year]}]
  set g $form(gains) ; set n $form(nulles) ; set p $form(pertes)
  set tous [expr {$g && $n && $p}]
  # White's name, Black's name; "either colour": the names (and the results
  # with them) may be the other way round
  set res [list $g $n $p $tous]
  set blanc $joueur ; set noir $adv
  set flip [expr {$form(inverse) && ($joueur ne {} || $adv ne {})}]
  set args [list -white $blanc -black $noir -event [string trim $form(tournoi)] \
      -site [string trim $form(lieu)] -date [list "$de.00.00" "$a.12.31"] -results $res \
      -welo $welo -belo $welo -moyelo $moyelo -flip $flip -filter [expr {$::moderne::recherche::et ? "AND" : "RESET"}]]
  set ecoDe [string trim $form(ecoDe)] ; set ecoA [string trim $form(ecoA)]
  if {$ecoDe ne {} || $ecoA ne {}} {
    if {$ecoDe eq {}} { set ecoDe A00 }
    if {$ecoA eq {}} { set ecoA E99/4 }
    lappend args -eco [list $ecoDe $ecoA No]
  }
  set t [string trim $form(texte)]
  if {$t ne {}} { lappend args -pgn [list $t] -ignoreCase 1 }
  return $args
}

proc ::moderne::recherche::chercherParties {} {
  variable form
  variable w
  busyCursor .
  # (progress shown and the window kept alive during the search)
  set b $w.b
  pack $b.stop -side right -padx {6 0} -before $b.raz
  pack $b.prog -side right -padx {6 0} -before $b.stop
  $b.prog coords bar 0 0 0 6
  update idletasks
  catch {sc_progressBar $b.prog bar [winfo width $b.prog] 6}
  # (More criteria open: its criteria too, the Games tab's fields copied
  # into it when this window's Search was pressed)
  variable depuisPlus
  if {!$depuisPlus} { catch versPlus }
  set code [catch {sc_search header {*}[arguments] {*}[extrasPlus]} err]
  catch {pack forget $b.prog $b.stop}
  if {!$code && $form(cadence) ne {}} {
    catch {sc_filter cadence [::moderne::cadence::numero $form(cadence)]}
  }
  unbusyCursor .
  if {$code} { etat $err ; return 0 }
  return 1
}

### The moves search, embedded: the common bar's progress and Stop button
### ({Stop button} {sc_progressBar arguments}); an error outside the window
proc ::moderne::recherche::barreCommune {} {
  variable w
  if {![winfo exists $w.b.stop] || ![winfo exists .smv] || [winfo ismapped .smv.b.stop]} { error "not embedded" }
  set b $w.b
  pack $b.stop -side right -padx {6 0} -before $b.raz
  pack $b.prog -side right -padx {6 0} -before $b.stop
  $b.prog coords bar 0 0 0 6
  update idletasks
  return [list $b.stop [list $b.prog bar [winfo width $b.prog] 6]]
}

proc ::moderne::recherche::finBarre {} {
  variable w
  catch {pack forget $w.b.prog $w.b.stop}
}

################################################################################
### The other tabs: the existing windows, embedded
################################################################################

### A tab shown for the first time: its window made inside it
proc ::moderne::recherche::ongletChange {} {
  variable w
  set o [lindex [split [$w.nb select] .] end]
  majFiltre
  montrerSeul $o
  lassign [fenetre $o] fen cmd
  if {$fen eq {} || [winfo exists $fen]} { return }
  embarquer $o
}

### Only the tab shown has its embedded window: on Windows an embedded
### window stays on screen over the other tabs, even withdrawn (Games
### selected, half of Material and patterns shown; Yosha 2026-11-02). The
### windows of the other tabs are destroyed, and made again when their tab
### comes back (their criteria live in variables)
proc ::moderne::recherche::montrerSeul {o} {
  variable w
  foreach x {pos coups mat} {
    if {$x eq $o} { continue }
    lassign [fenetre $x] fen cmd
    if {![winfo exists $fen]} { continue }
    catch {destroy $fen}
    foreach c [winfo children $w.nb.$x] { catch {destroy $c} }
  }
}

proc ::moderne::recherche::embarquer {o} {
  variable w
  variable cible
  variable idCible
  variable dedans
  lassign [fenetre $o] fen cmd
  update idletasks
  set cible $fen
  # (a new container in the tab: an old one may still be going away)
  foreach c [winfo children $w.nb.$o] { catch {destroy $c} }
  variable numero
  if {![info exists numero]} { set numero 0 }
  set c [frame $w.nb.$o.c[incr numero] -container 1 -background [::moderne::c fond]]
  pack $c -fill both -expand 1
  update idletasks
  set idCible [winfo id $c]
  set dedans 1
  rename ::toplevel ::moderne::recherche::toplevel_tk
  proc ::toplevel {nom args} {
    if {$nom eq $::moderne::recherche::cible} {
      return [::moderne::recherche::toplevel_tk $nom {*}$args -use $::moderne::recherche::idCible]
    }
    return [::moderne::recherche::toplevel_tk $nom {*}$args]
  }
  set code [catch {uplevel #0 $cmd} err]
  rename ::toplevel {}
  rename ::moderne::recherche::toplevel_tk ::toplevel
  set dedans 0
  # (Windows: the moves window asks for a window state its container
  # cannot give, "the container does not support the request"; it is made
  # all the same: go on, its own buttons hidden below; the tab kept its
  # Search / Close buttons, Yosha 2026-11-03)
  if {$code} {
    puts stderr "Siby search tab $o: $err"
    if {![winfo exists $fen]} { return }
  }
  catch {wm deiconify $fen}
  # their own Search / Close buttons, game list choice and preview: the
  # window's common ones replace them
  switch -- $o {
    pos {
      foreach x {.positionsWin.f.m.bas.ok .positionsWin.f.m.bas.stop .positionsWin.f.m.bas.fermer .positionsWin.f.m.dansFiltre} { catch {pack forget $x} ; catch {grid remove $x} }
      catch {grid remove .positionsWin.f.r} ; catch {pack forget .positionsWin.f.r}
    }
    coups {
      # (its progress and Stop too: the common bar has them, Yosha 2026-11-04)
      foreach x {.smv.b.search .smv.b.cancel .smv.b.stop .smv.progress .smv.filterop} { catch {pack forget $x} }
    }
    mat {
      foreach x {.motifsWin.bas.ok .motifsWin.bas.stop .motifsWin.bas.fermer .motifsWin.c.res .motifsWin.c.t4} { catch {pack forget $x} ; catch {grid remove $x} }
      # (6 piece-on-square conditions instead of 10: the window fits a
      # 1080-pixel screen)
      foreach g [winfo children .motifsWin.c] {
        foreach i {4 5 9 10} {
          foreach k {c p e f r} { catch {grid remove $g.$k$i} }
        }
      }
      # pieces on squares and the options folded under "More criteria" (the
      # material alone is the usual search; the window needed the full
      # screen, Yosha 2026-11-02)
      variable plus
      plusCriteres [expr {[info exists plus] ? $plus : 0}]
    }
  }
  # (the tab's own Search button, should it show again, and its Return
  # key: the common search, which updates the preview and the count; the
  # moves tab's own one left the preview on the previous search, Yosha
  # 2026-11-03)
  variable commandeOrig
  foreach x {.positionsWin.f.m.bas.ok .smv.b.search .motifsWin.bas.ok} {
    if {![string match $fen* $x] || ![winfo exists $x]} { continue }
    set c [$x cget -command]
    if {$c ne "::moderne::recherche::rechercher"} { set commandeOrig($x) $c }
    catch {$x configure -command ::moderne::recherche::rechercher}
  }
  marquer $o $fen
  bind $fen <Destroy> [list ::moderne::recherche::sortie %W $fen]
}

### An embedded window destroyed (its Escape key…): its tab is made again
### at the next display
proc ::moderne::recherche::sortie {x fen} {
  if {$x ne $fen} { return }
}

################################################################################
### Common bar
################################################################################

### The status line; erreur: shown in red (an impossible material, a move
### that cannot be read)
proc ::moderne::recherche::etat {texte {erreur 0}} {
  variable w
  if {![info exists w] || ![winfo exists $w.b.etat]} { return }
  $w.b.etat configure -text $texte -foreground [expr {$erreur ? "#e5534b" : [::moderne::c texteDoux]}]
}

### The Material tab's counts: dict wq.. bp, wm bm (minor pieces), diff ->
### {min max}
proc ::moderne::recherche::materielOnglet {} {
  global pMin pMax
  set d {}
  foreach k {wq wr wb wn wp bq br bb bn bp wm bm} {
    if {[info exists pMin($k)] && [info exists pMax($k)]} { dict set d $k [list $pMin($k) $pMax($k)] }
  }
  if {[info exists ::minMatDiff] && [info exists ::maxMatDiff]} { dict set d diff [list $::minMatDiff $::maxMatDiff] }
  return $d
}

### Does the Material tab hold only counts (no pattern, no other option)?
proc ::moderne::recherche::materielSeul {} {
  global pattPiece pattFyle pattRank nPatterns
  if {[info exists nPatterns]} {
    for {set i 1} {$i <= $nPatterns} {incr i} {
      if {[info exists pattPiece($i)] && ($pattPiece($i) ne "?" || $pattFyle($i) ne "?" || $pattRank($i) ne "?")} { return 0 }
    }
  }
  foreach {v defaut} {matchEnd 0 minMoveNum 1 maxMoveNum 999 minHalfMoves 1 oppBishops Either ignoreColors 0} {
    if {[info exists ::$v] && [set ::$v] ne $defaut} { return 0 }
  }
  return 1
}

### The Material tab's counts that no position can have (minor pieces out of
### reach of the bishops and knights, a minimum above a maximum): the
### message, else {}
proc ::moderne::recherche::materielImpossible {} {
  global pMin pMax
  foreach {camp nom} [list w [T Blancs White] b [T Noirs Black]] {
    foreach k {q r b n p m} {
      if {[info exists pMin($camp$k)] && $pMin($camp$k) > $pMax($camp$k)} {
        return [T "Matériel impossible ($nom) : un minimum au-dessus du maximum." "Impossible material ($nom): a minimum above the maximum."]
      }
    }
    if {![info exists pMin(${camp}m)]} { continue }
    set bnMin [expr {$pMin(${camp}b) + $pMin(${camp}n)}]
    set bnMax [expr {$pMax(${camp}b) + $pMax(${camp}n)}]
    if {$pMin(${camp}m) > $bnMax || $pMax(${camp}m) < $bnMin} {
      return [T "Matériel impossible ($nom) : pièces mineures $pMin(${camp}m) à $pMax(${camp}m), mais fous + cavaliers $bnMin à $bnMax." \
          "Impossible material ($nom): minor pieces $pMin(${camp}m) to $pMax(${camp}m), but bishops + knights $bnMin to $bnMax."]
    }
  }
  return {}
}

proc ::moderne::recherche::rechercher {} {
  variable w
  variable dansFiltre
  variable utiliser
  variable et
  # (the reference database chosen but not open yet: opened now)
  variable choix
  if {[info exists choix] && $choix eq "ref"} { choisirBase ; majBases }
  if {![sc_base inUse]} { return }
  set courant [lindex [split [$w.nb select] .] end]
  # One order for every combination (Yosha 2026-11-10): Games (no move,
  # it only narrows the games), Material, Position (the move shown), Moves
  # (the moves after the position, when there is one)
  set liste {}
  foreach o {parties mat pos coups} { if {$utiliser($o)} { lappend liste $o } }
  if {![llength $liste]} { set liste [list $courant] }
  # (Position and Material together: the material checked at the position
  # found, not anywhere in the game; impossible material said at once,
  # Yosha 2026-11-10)
  set ::moderne::positions::materielCombine {}
  if {"mat" in $liste} {
    set err [::moderne::recherche::materielImpossible]
    if {$err ne {}} { etat $err 1 ; return }
  }
  # (Material and Moves without Position: the material where the moves
  # start, Yosha 2026-11-10)
  set ::search::materielCoups {}
  if {"coups" in $liste && "mat" in $liste && "pos" ni $liste} {
    set m {}
    dict for {k v} [::moderne::recherche::materielOnglet] {
      switch -- $k { wm { set o -wminor } bm { set o -bminor } diff { set o -diff } default { set o -$k } }
      lappend m $o $v
    }
    set ::search::materielCoups $m
    if {[::moderne::recherche::materielSeul]} {
      set liste [lsearch -all -inline -not -exact $liste mat]
    }
  }
  if {"pos" in $liste && "mat" in $liste} {
    set ::moderne::positions::materielCombine [::moderne::recherche::materielOnglet]
    # (only counts in the Material tab: already checked by the position
    # search, its own search skipped, about 2 s on Gaby)
    if {[::moderne::recherche::materielSeul]} {
      set liste [lsearch -all -inline -not -exact $liste mat]
    }
  }
  set t0 [clock milliseconds]
  set premier 1
  set faites {}
  foreach o $liste {
    # the first one in the whole database (or the games shown), the next
    # ones within the results of the one before
    set et [expr {$premier ? $dansFiltre : 1}]
    set ::search::filter::operation [expr {$et ? 0 : 2}]
    set ::moderne::positions::dansFiltre $et
    lassign [fenetre $o] fen
    if {$fen ne {} && ![winfo exists $fen]} { embarquer $o }
    set ok 1
    switch -- $o {
      parties { set ok [chercherParties] }
      pos   {
        # (Stop in the common bar; the tab shows its own progress)
        catch {pack $w.b.stop -side right -padx {6 0} -before $w.b.raz}
        catch {::moderne::positions::lancer}
        catch {pack forget $w.b.stop}
      }
      coups {
        # (the button's own command: the button itself now runs this one)
        variable commandeOrig
        set ::search::erreurCoups {}
        # (the position searched just before: the moves after it, in each
        # game, Yosha 2026-11-09)
        set ::search::apresPosition [expr {"pos" in $faites}]
        if {[info exists commandeOrig(.smv.b.search)]} {
          catch {uplevel #0 $commandeOrig(.smv.b.search)}
        } else {
          catch {.smv.b.search invoke}
        }
        set ::search::apresPosition 0
        # (a move it cannot read: said here, no count of games)
        if {$::search::erreurCoups ne {}} { catch {etat $::search::erreurCoups 1} ; return }
      }
      mat   {
        catch {pack $w.b.stop -side right -padx {6 0} -before $w.b.raz}
        catch {::moderne::motifs::lancer}
        catch {pack forget $w.b.stop}
      }
    }
    if {!$ok || ![winfo exists $w]} { return }
    set premier 0
    lappend faites $o
    if {[sc_filter count] == 0} { break }
  }
  set ::moderne::positions::materielCombine {}
  set ::search::materielCoups {}
  set n [sc_filter count]
  set ms [expr {[clock milliseconds] - $t0}]
  etat "[::utils::thousands $n] [expr {$n == 1 ? [T "partie trouvée" "game found"] : [T "parties trouvées" "games found"]}] ([format %.1f [expr {$ms / 1000.0}]] s)"
  set ::glstart 1
  catch {::windows::gamelist::Refresh}
  catch {::windows::stats::Refresh}
  catch {updateStatusBar}
  catch {::moderne::apercu::montrer $w.r 1}
  majFiltre
  # (the Moves search shows its own results, with the moves found)
  if {"coups" ni $faites && $n > 0} { catch {::moderne::resultats::montrer [titreRecherche $faites]} }
  # (More criteria: its status line too)
  catch {.sh.status configure -text [$w.b.etat cget -text]}
}

### The searches made, in words, for the results module
proc ::moderne::recherche::titreRecherche {faites} {
  variable form
  set l {}
  foreach o $faites {
    switch -- $o {
      parties {
        set noms {}
        foreach v {joueur adversaire} { if {[string trim $form($v)] ne {}} { lappend noms [string trim $form($v)] } }
        lappend l [expr {[llength $noms] ? [join $noms " – "] : [T Parties Games]}]
      }
      pos { lappend l [T Position Position] }
      mat { lappend l [T Matériel Material] }
    }
  }
  return [join $l "  +  "]
}

### More criteria: the old General search, its criteria added to the Games
### tab's (Yosha 2026-11-10: its results were apart from the Search window
### and the Results module). The fields both windows have are copied from
### one to the other; its own Search runs this window's search.
proc ::moderne::recherche::plus {} {
  catch versPlus
  ::search::header
  if {![winfo exists .sh]} { return }
  .sh.b.search configure -command ::moderne::recherche::plusChercher
  # (where to search: this window's "Only within the games shown")
  catch {pack forget .sh.filterop}
}

proc ::moderne::recherche::plusChercher {} {
  variable utiliser
  variable depuisPlus
  variable w
  catch checkDates
  depuisPlus
  set utiliser(parties) 1
  catch {::moderne::recherche::majOnglets}
  if {![winfo exists $w]} { catch {ouvrir parties} }
  set depuisPlus 1
  catch rechercher
  set depuisPlus 0
}

### The Games tab's fields into More criteria
proc ::moderne::recherche::versPlus {} {
  variable form
  set max [sc_info limit elo]
  set ::sWhite [string trim $form(joueur)]
  set ::sBlack [string trim $form(adversaire)]
  set ::sIgnoreCol [expr {$form(inverse) ? "Yes" : "No"}]
  set ::sEvent [string trim $form(tournoi)]
  set ::sSite [string trim $form(lieu)]
  if {$form(eloMode) eq "chaque"} {
    set e1 [expr {[string is integer -strict $form(eloMin)] ? $form(eloMin) : 0}]
    set e2 [expr {[string is integer -strict $form(eloMax)] && $form(eloMax) > 0 ? $form(eloMax) : $max}]
    set ::sWhiteEloMin $e1 ; set ::sBlackEloMin $e1
    set ::sWhiteEloMax $e2 ; set ::sBlackEloMax $e2
  }
  set ::sDateMin [expr {[string is integer -strict $form(de)] ? "$form(de).00.00" : "0000.00.00"}]
  set ::sDateMax [expr {[string is integer -strict $form(a)] ? "$form(a).12.31" : "[sc_info limit year].12.31"}]
  set ::sResWin $form(gains) ; set ::sResDraw $form(nulles) ; set ::sResLoss $form(pertes)
  set ::sEcoMin [expr {[string trim $form(ecoDe)] eq {} ? "A00" : [string trim $form(ecoDe)]}]
  set ::sEcoMax [expr {[string trim $form(ecoA)] eq {} ? "E99" : [string trim $form(ecoA)]}]
  set ::sPgntext(1) [string trim $form(texte)]
}

### More criteria's fields back into the Games tab
proc ::moderne::recherche::depuisPlus {} {
  variable form
  set max [sc_info limit elo]
  set form(joueur) $::sWhite
  set form(adversaire) $::sBlack
  set form(inverse) [expr {$::sIgnoreCol eq "Yes"}]
  set form(tournoi) $::sEvent
  set form(lieu) $::sSite
  if {$::sWhiteEloMin == $::sBlackEloMin && $::sWhiteEloMax == $::sBlackEloMax} {
    set form(eloMode) chaque
    set form(eloMin) [expr {$::sWhiteEloMin > 0 ? $::sWhiteEloMin : {}}]
    set form(eloMax) [expr {$::sWhiteEloMax < $max ? $::sWhiteEloMax : {}}]
  }
  set y1 [string range $::sDateMin 0 3] ; set y2 [string range $::sDateMax 0 3]
  set form(de) [expr {[string is integer -strict $y1] && $y1 > 0 ? $y1 : {}}]
  set form(a) [expr {[string is integer -strict $y2] && $y2 < [sc_info limit year] ? $y2 : {}}]
  set form(gains) $::sResWin ; set form(nulles) $::sResDraw ; set form(pertes) $::sResLoss
  set form(ecoDe) [expr {$::sEcoMin eq "A00" ? {} : $::sEcoMin}]
  set form(ecoA) [expr {$::sEcoMax eq "E99" ? {} : $::sEcoMax}]
  set form(texte) $::sPgntext(1)
  catch libellesResultat
}

### More criteria's own criteria (while its window is open), added after
### the Games tab's: what the tab cannot say
proc ::moderne::recherche::extrasPlus {} {
  if {![winfo exists .sh]} { return {} }
  set max [sc_info limit elo]
  set a [list -round $::sRound -delo [list $::sEloDiffMin $::sEloDiffMax] \
      -length [list $::sGlMin $::sGlMax] -toMove $::sSideToMove \
      -gameNumber [list $::sGnumMin $::sGnumMax] \
      -preComment $::preComment -postComment $::postComment \
      -extratag $::sTag -tagvalue $::sTagValue -gameend $::sGameEnd]
  # ratings: White's and Black's apart
  if {$::sWhiteEloMin != $::sBlackEloMin || $::sWhiteEloMax != $::sBlackEloMax} {
    lappend a -welo [list $::sWhiteEloMin $::sWhiteEloMax] -belo [list $::sBlackEloMin $::sBlackEloMax]
  }
  # dates to the day
  if {![string match *.00.00 $::sDateMin] && ![string match *.??.?? $::sDateMin] || ![string match *.12.31 $::sDateMax]} {
    lappend a -date [list $::sDateMin $::sDateMax]
  }
  if {!$::sResOther && $::sResWin && $::sResDraw && $::sResLoss} {
    lappend a -results [list 1 1 1 0]
  }
  if {$::sEco eq "No"} { lappend a -eco [list $::sEcoMin $::sEcoMax No] }
  set textes {}
  foreach i {1 2 3} { if {$::sPgntext($i) ne {}} { lappend textes $::sPgntext($i) } }
  if {[llength $textes] > 1} { lappend a -pgn $textes -ignoreCase $::sPgncase }
  set wt {} ; set bt {}
  foreach i $::sTitleList {
    if {$::sTitles(w:$i)} { lappend wt $i }
    if {$::sTitles(b:$i)} { lappend bt $i }
  }
  lappend a -wtitles $wt -btitles $bt
  foreach f {StdStart Promotions UnderPromo Comments Variations Annotations} {
    lappend a -f$f $::sHeaderFlags($f)
  }
  lappend a -fDelete $::sHeaderFlags(DeleteFlag)
  foreach {o f} {WhiteOp WhiteOpFlag BlackOp BlackOpFlag Middlegame MiddlegameFlag Endgame EndgameFlag
      Novelty NoveltyFlag PawnStruct PawnFlag Tactics TacticsFlag Kingside KsideFlag Queenside QsideFlag
      Brilliancy BrilliancyFlag Blunder BlunderFlag User UserFlag} {
    lappend a -f$o $::sHeaderFlags($f)
  }
  foreach i {1 2 3 4 5 6} { lappend a -fCustom$i $::sHeaderFlags(CustomFlag$i) }
  return $a
}

proc ::moderne::recherche::effacer {} {
  variable w
  set o [lindex [split [$w.nb select] .] end]
  switch -- $o {
    parties { formVide }
    pos   { catch {::moderne::positions::vider} }
    coups { catch {set ::sMoves {}} }
    mat   { catch {::search::material::any} ; catch {clearPatterns} ; catch {::moderne::motifs::lireMotifs} }
  }
  # (its criteria cleared: no longer combined)
  variable utiliser
  set utiliser($o) 0
  majOnglets
  etat {}
}

################################################################################
### The menus and buttons open this window, on the right tab
################################################################################

### Material and patterns: sections 2 (pieces on squares) and 3 (options)
### shown or folded
proc ::moderne::recherche::plusCriteres {montrer} {
  set c .motifsWin.c
  if {![winfo exists $c]} { return }
  variable plus $montrer
  if {![winfo exists $c.plus]} {
    ttk::button $c.plus -style Toolbutton -command {::moderne::recherche::plusCriteres [expr {!$::moderne::recherche::plus}]}
    grid $c.plus -row 5 -column 0 -sticky w -pady {12 8}
  }
  $c.plus configure -text [expr {$montrer ? [T "▾ Moins de critères" "▾ Fewer criteria"] :
      [T "▸ Plus de critères (pièces sur des cases, coups, fous, couleurs inversées)" "▸ More criteria (pieces on squares, moves, bishops, colours reversed)"]}]
  # (the button takes the place of the separator under the material)
  catch {grid remove $c.s1}
  foreach x {t2 d2 patt pb s2 t3 opt} {
    if {![winfo exists $c.$x]} { continue }
    if {$montrer} { grid $c.$x } else { grid remove $c.$x }
  }
}

### A criterion changed in tab o: the tab ticked in "Combine"
proc ::moderne::recherche::marquer {o racine} {
  set tag rechercheModif_$o
  foreach e [enfants $racine] {
    if {[lsearch -exact [bindtags $e] $tag] < 0} { bindtags $e [concat [list $tag] [bindtags $e]] }
  }
  foreach ev {<KeyRelease> <<ComboboxSelected>> <<Increment>> <<Decrement>>} {
    bind $tag $ev [list ::moderne::recherche::modifie $o %W %K]
  }
  bind $tag <ButtonRelease-1> [list ::moderne::recherche::modifieClic $o %W]
}

proc ::moderne::recherche::enfants {w} {
  set l [list $w]
  foreach e [winfo children $w] { lappend l {*}[enfants $e] }
  return $l
}

proc ::moderne::recherche::modifie {o x {touche {}}} {
  variable utiliser
  # (keys that change nothing: moving, Tab, Return…)
  if {$touche in {Tab ISO_Left_Tab Return KP_Enter Escape Left Right Up Down Home End Shift_L Shift_R Control_L Control_R Alt_L Alt_R}} { return }
  if {[info exists utiliser($o)] && !$utiliser($o)} {
    set utiliser($o) 1
    majOnglets
  }
}

### A click that changes something (a box, a choice, the board of the
### Position tab, a button such as "Allow anything"), not one in a field
proc ::moderne::recherche::modifieClic {o x} {
  # (showing or folding more criteria changes nothing)
  if {[string match *.plus $x]} { return }
  if {[winfo class $x] in {TEntry Entry TCombobox TSpinbox Text TScrollbar Scrollbar TNotebook TLabel Label TFrame Frame}} { return }
  modifie $o $x
}

### The older search windows get "Search in" when they open
proc ::moderne::recherche::installerChoix {} {
  foreach {cmd fen maj} {::search::board .sb {} search::header .sh {} ::plist::Open .plist ::plist::refresh ::tourney::Open .tourney ::tourney::refresh} {
    if {![llength [info commands $cmd]]} { continue }
    catch {trace add execution $cmd leave [list apply {{fen maj args} {
      if {![::moderne::actif]} { return }
      ::moderne::recherche::ajouterChoix $fen $maj
      # (Current position: SCID's "reference database" box replaced by it)
      if {$fen eq ".sb"} { set ::searchRefBase 0 ; catch {pack forget .sb.refdb} }
    }} $fen $maj]}
  }
}
after idle ::moderne::recherche::installerChoix

proc ::moderne::recherche::installer {} {
  if {[llength [info commands ::moderne::positions::ouvrir_seul]]} { return }
  foreach {ancien onglet} {::moderne::positions::ouvrir pos ::search::moves coups ::moderne::motifs::ouvrir mat ::moderne::rparties::ouvrir parties} {
    if {![llength [info commands $ancien]]} { continue }
    rename $ancien ${ancien}_seul
    proc $ancien {args} [string map [list %A $ancien %O $onglet] {
      if {$::moderne::recherche::dedans || ![::moderne::actif]} { return [%A_seul {*}$args] }
      ::moderne::recherche::ouvrir %O
    }]
  }
}
after idle ::moderne::recherche::installer

### End Siby
