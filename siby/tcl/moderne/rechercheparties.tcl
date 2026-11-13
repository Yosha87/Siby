###
### Siby: "Find games", a simple search like the Play window: a player
### (with suggestions) and their colour, an opponent, a minimum opponent
### rating, an event, years, the result seen from the player. The old
### header search (all the criteria) stays one click away: "Advanced
### search…". The search replaces the filter of the current database.
###

namespace eval ::moderne::rparties {
  variable w .rechercheParties
  variable form
  array set form {joueur {} couleur deux adversaire {} eloMin {} tournoi {} de {} a {} gains 1 nulles 1 pertes 1}
}

proc ::moderne::rparties::T {fr en} { return [::moderne::tr $fr $en] }
proc ::moderne::rparties::C {nom} { return [::moderne::c $nom] }

proc ::moderne::rparties::ouvrir {} {
  variable w
  variable form
  if {[winfo exists $w]} { raise $w ; focus $w.f.g.j.e ; return }
  ::moderne::jouer::polices
  set fond [C fond]
  toplevel $w -background $fond
  wm title $w [T "Rechercher des parties" "Find games"]
  wm transient $w .
  wm resizable $w 0 0
  set f [frame $w.f -background $fond -padx 22 -pady 16]
  pack $f -fill both -expand 1
  label $f.titre -text [T "Rechercher des parties" "Find games"] -font SibyJouerTitre \
      -background $fond -foreground [C texteFort] -anchor w
  label $f.base -text "[T "Dans" "In"] [::moderne::nomBase [sc_base filename [sc_base current]]]" \
      -font SibyJouerPetit -background $fond -foreground [C texteDoux] -anchor w
  pack $f.titre $f.base -side top -fill x

  # One grid, so the columns line up: player | colour, opponent | min.
  # rating, event | years
  set g [frame $f.g -background $fond]
  pack $g -side top -fill x
  champ $g.j [T "Joueur·se" "Player"] ::moderne::rparties::form(joueur) 30 1
  frame $g.c -background $fond
  ::moderne::jouer::section $g.c.l [T "Avec" "With"] 1
  pack $g.c.l -side top -fill x -pady {12 5}
  ::moderne::jouer::segments $g.c.s ::moderne::rparties::form(couleur) [list \
      [list blancs [T "Blancs" "White"]] [list noirs [T "Noirs" "Black"]] [list deux [T "Les deux" "Both"]]] \
      ::moderne::rparties::majResultats
  pack $g.c.s -side top -fill x
  champ $g.a [T "Adversaire" "Opponent"] ::moderne::rparties::form(adversaire) 30 1
  frame $g.e -background $fond
  ::moderne::jouer::section $g.e.l [T "Elo adverse min." "Min. opponent rating"] 1
  pack $g.e.l -side top -fill x -pady {12 5}
  ttk::spinbox $g.e.s -from 0 -to 3000 -increment 100 -width 7 -textvariable ::moderne::rparties::form(eloMin)
  pack $g.e.s -side top -anchor w
  champ $g.t [T "Tournoi" "Event"] ::moderne::rparties::form(tournoi) 30 0
  frame $g.d -background $fond
  ::moderne::jouer::section $g.d.l [T "Années" "Years"] 1
  pack $g.d.l -side top -fill x -pady {12 5}
  frame $g.d.v -background $fond
  ttk::spinbox $g.d.v.de -from 1475 -to 2100 -width 5 -textvariable ::moderne::rparties::form(de)
  label $g.d.v.t -text "–" -background $fond -foreground [C texte]
  ttk::spinbox $g.d.v.a -from 1475 -to 2100 -width 5 -textvariable ::moderne::rparties::form(a)
  pack $g.d.v.de $g.d.v.t $g.d.v.a -side left -padx {0 4}
  pack $g.d.v -side top -anchor w
  grid $g.j $g.c -sticky new
  grid $g.a $g.e -sticky new
  grid $g.t $g.d -sticky new
  grid configure $g.j $g.a $g.t -padx {0 16}
  grid columnconfigure $g 0 -weight 3
  grid columnconfigure $g 1 -weight 2

  # Result, seen from the player (or White when no player)
  ::moderne::jouer::section $f.lres [T "Résultat" "Result"]
  set style Toolbutton
  if {![catch {ttk::style layout Segment.Toolbutton} l] && $l ne {}} { set style Segment.Toolbutton }
  ttk::frame $f.res
  pack $f.res -side top -fill x
  foreach k {gains nulles pertes} {
    ttk::checkbutton $f.res.$k -style $style -variable ::moderne::rparties::form($k)
    pack $f.res.$k -side left -padx 1 -fill x -expand 1
  }
  majResultats
  trace remove variable ::moderne::rparties::form(joueur) write ::moderne::rparties::majResultats
  trace add variable ::moderne::rparties::form(joueur) write ::moderne::rparties::majResultats

  # Buttons, result line
  frame $f.btn -background $fond
  pack $f.btn -side top -fill x -pady {18 0}
  ttk::button $f.btn.avance -text [T "Recherche avancée…" "Advanced search…"] -style Toolbutton \
      -command {destroy .rechercheParties ; ::search::header}
  catch {::utils::tooltip::Set $f.btn.avance [T "Tous les critères : Elo, titres, ECO, longueur, commentaires…" \
      "All the criteria: ratings, titles, ECO, length, comments…"]}
  ttk::button $f.btn.vider -text [T "Effacer" "Clear"] -style Toolbutton -command ::moderne::rparties::vider
  ttk::button $f.btn.ok -text [T "Rechercher" "Search"] -command ::moderne::rparties::chercher
  if {![catch {ttk::style layout Accent.TButton} l] && $l ne {}} { $f.btn.ok configure -style Accent.TButton }
  pack $f.btn.avance $f.btn.vider -side left
  pack $f.btn.ok -side right
  label $f.etat -text {} -background $fond -foreground [C texteDoux] -anchor w
  pack $f.etat -side top -fill x -pady {10 0}

  bind $w <Escape> [list destroy $w]
  bind $w <Return> ::moderne::rparties::chercher
  catch {placeWinOverParent $w .}
  focus $f.g.j.e
}

### A labelled entry (with player name suggestions)
proc ::moderne::rparties::champ {p titre var largeur noms} {
  frame $p -background [C fond]
  ::moderne::jouer::section $p.l $titre 1
  pack $p.l -side top -fill x -pady {12 5}
  ttk::entry $p.e -width $largeur -textvariable $var
  pack $p.e -side top -fill x
  if {$noms} {
    catch {::moderne::suggestions::attacher $p.e ::moderne::rparties::suggestions [list ::moderne::rparties::choisi $var]}
  }
}

proc ::moderne::rparties::suggestions {texte} {
  if {[string length $texte] < 2} { return {} }
  set r {}
  catch {set r [sc_name match -souple player $texte 200]}
  set res {}
  foreach {n nom} $r { lappend res [list $n $nom] }
  set sortie {}
  foreach x [lrange [lsort -integer -decreasing -index 0 $res] 0 11] {
    lassign $x n nom
    lappend sortie [list "$nom  ([::utils::thousands $n])" $nom]
  }
  return $sortie
}

proc ::moderne::rparties::choisi {var nom} {
  set $var $nom
}

### Result labels: from the player's side, else White's
proc ::moderne::rparties::majResultats {args} {
  variable form
  set f .rechercheParties.f.res
  if {![winfo exists $f]} { return }
  if {[string trim $form(joueur)] eq {} && $form(couleur) eq "deux"} {
    set l [list "1-0" "½-½" "0-1"]
  } else {
    set l [list [T "Gains" "Wins"] [T "Nulles" "Draws"] [T "Pertes" "Losses"]]
  }
  foreach k {gains nulles pertes} t $l { $f.$k configure -text $t }
}

proc ::moderne::rparties::vider {} {
  variable form
  array set form {joueur {} couleur deux adversaire {} eloMin {} tournoi {} de {} a {} gains 1 nulles 1 pertes 1}
  catch {.rechercheParties.f.etat configure -text {}}
  majResultats
}

### The sc_search header arguments of the form
proc ::moderne::rparties::arguments {} {
  variable form
  set joueur [string trim $form(joueur)]
  set adv [string trim $form(adversaire)]
  set maxElo [sc_info limit elo]
  set elo [list 0 $maxElo]
  if {[string is integer -strict $form(eloMin)] && $form(eloMin) > 0} { set elo [list $form(eloMin) $maxElo] }
  set de [expr {[string is integer -strict $form(de)] ? $form(de) : "0000"}]
  set a [expr {[string is integer -strict $form(a)] ? $form(a) : [sc_info limit year]}]
  # results: win draw loss (White's), then "no result" (kept when all are)
  set g $form(gains) ; set n $form(nulles) ; set p $form(pertes)
  set tous [expr {$g && $n && $p}]
  # the player with Black: their wins are 0-1
  set noirs [expr {$form(couleur) eq "noirs"}]
  set res [expr {$noirs ? [list $p $n $g $tous] : [list $g $n $p $tous]}]
  set blanc {} ; set noir {} ; set welo [list 0 $maxElo] ; set belo [list 0 $maxElo]
  set flip 0
  switch $form(couleur) {
    blancs { set blanc $joueur ; set noir $adv ; set belo $elo }
    noirs  { set blanc $adv ; set noir $joueur ; set welo $elo }
    deux   {
      # (either colour: the player as White, the search also tries the
      # colours swapped, results seen from the player)
      set blanc $joueur ; set noir $adv ; set belo $elo
      set flip [expr {$joueur ne {} || $adv ne {}}]
    }
  }
  return [list -white $blanc -black $noir -event [string trim $form(tournoi)] \
      -date [list "$de.00.00" "$a.12.31"] -results $res -welo $welo -belo $belo \
      -flip $flip -filter RESET]
}

proc ::moderne::rparties::chercher {} {
  set f .rechercheParties.f
  if {![sc_base inUse]} { return }
  busyCursor .
  set code [catch {sc_search header {*}[arguments]} str]
  unbusyCursor .
  if {$code} {
    catch {$f.etat configure -text $str}
    return
  }
  set nb [sc_filter count]
  catch {$f.etat configure -text [T "[::utils::thousands $nb] parties trouvées" "[::utils::thousands $nb] games found"]}
  catch {::windows::gamelist::Refresh}
  catch {::windows::stats::Refresh}
  catch {::moderne::rparties::majResultats}
}

### End Siby
