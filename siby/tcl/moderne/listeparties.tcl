###
### Siby: game list extras
###
### - "Board position": the game list shows only the games of the current
###   database that reach the position on the board, and follows the board
###   (like the games of the Lichess opening explorer). It combines with the
###   time control buttons and the text filter. A game opened from the list
###   starts at that position.
### - "My databases" tab (next to the notation and the game list): the
###   databases of the desk (as in the My databases view) as a list, sorted
###   by name; a click on a heading sorts by that column.
###

namespace eval ::moderne::listeparties {
  variable position 0     ;# "Board position" on
  variable textes {}      ;# text filters applied while following the board
  variable dernier {}     ;# database and position of the last search
  variable attente {}     ;# pending search (after id)
  variable interne 0      ;# our own search running
}

proc ::moderne::listeparties::T {fr en} { return [::moderne::tr $fr $en] }

### The toggle button, in the game list toolbar
proc ::moderne::listeparties::installer {} {
  set w .glistWin
  if {![winfo exists $w.b] || [winfo exists $w.b.position]} { return }
  ttk::checkbutton $w.b.position -style Toolbutton -text [T "Position de l'échiquier" "Board position"] \
      -variable ::moderne::listeparties::position -command ::moderne::listeparties::basculer
  catch {::utils::tooltip::Set $w.b.position [T \
      "Ne montre que les parties de la base qui ont la position de l'échiquier (suit l'échiquier)" \
      "Shows only the games of the database that reach the position on the board (follows the board)"]}
  set apres [expr {[winfo exists $w.b.chercher] ? "$w.b.chercher" : "$w.b.goto"}]
  if {[winfo exists $w.b.cadence]} { set apres $w.b.cadence }
  pack $w.b.position -side left -padx {0 8} -after $apres
}

proc ::moderne::listeparties::basculer {} {
  variable position
  variable dernier
  variable textes
  set dernier {}
  if {$position} {
    # the games shown now (a search, a text, a time control) are kept: the
    # position is looked for among them (Yosha 2026-11-01)
    sc_filter snapshot
    set textes {}
    appliquer
  } else {
    # back to the list of before
    filtrer [list sc_filter restore]
  }
}

### The position on the board changed: new search a moment later (moving
### quickly through a game makes a single search)
proc ::moderne::listeparties::suivre {} {
  variable position
  variable attente
  if {!$position || ![winfo exists .glistWin]} { return }
  after cancel $attente
  set attente [after 150 ::moderne::listeparties::appliquer]
}

proc ::moderne::listeparties::cle {} {
  return [list [sc_base current] [lrange [split [sc_pos fen]] 0 3]]
}

proc ::moderne::listeparties::appliquer {} {
  variable position
  variable dernier
  if {!$position || ![winfo exists .glistWin]} { return }
  set c [cle]
  if {$c eq $dernier} { return }
  set dernier $c
  filtrer {sc_filter restore ; sc_search board AND Exact false 0}
}

### Filter: the command given (all the games or the position), then the
### time control, then the text filters
proc ::moderne::listeparties::filtrer {commande} {
  variable textes
  variable interne
  set interne 1
  catch {busyCursor .glistWin}
  catch {uplevel #0 $commande}
  set cad {}
  catch {set cad $::moderne::cadence::liste}
  if {$cad ne {}} {
    if {[catch {sc_filter cadence [::moderne::cadence::numero $cad]} r] || $r < 0} {
      set ::moderne::cadence::liste {}
    }
  }
  foreach t $textes {
    catch {sc_filter textfilter $::windows::gamelist::findcase $t}
  }
  set interne 0
  catch {unbusyCursor .glistWin}
  set ::glstart 1
  catch {::windows::gamelist::Refresh first}
  catch {::windows::stats::Refresh}
  catch {updateStatusBar}
}

### Text filter applied (FilterText): kept while following the board
proc ::moderne::listeparties::texteAjoute {texte} {
  variable textes
  foreach t [split $texte +] {
    set t [string trim $t]
    if {$t ne {}} { lappend textes $t }
  }
}

### "All games": no position, no text, all time controls
proc ::moderne::listeparties::toutes {} {
  variable position
  variable textes
  variable dernier
  set position 0
  set textes {}
  set dernier {}
  set ::moderne::cadence::liste {}
  ::search::filter::reset
  catch {::windows::gamelist::Refresh first}
  catch {updateStatusBar}
}

### Another search (search windows, preparation…): the list stops
### following the board
proc ::moderne::listeparties::autreRecherche {args} {
  variable interne
  variable position
  if {$interne || !$position} { return }
  set cmd [lindex $args 0]
  if {[lindex $cmd 1] in {header board material moves}} {
    set position 0
    set ::moderne::listeparties::textes {}
  }
}

trace add execution updateBoard leave {apply {args { catch ::moderne::listeparties::suivre }}}
catch {trace add execution ::sc_search enter ::moderne::listeparties::autreRecherche}

################################################################################
### "My databases" tab: the desk databases as a list
################################################################################

namespace eval ::moderne::basesliste {
  variable w .basesListeWin
  variable tri {etat 0}   ;# column, reversed (by default the status: reference, open, recent)
  variable fichiers       ;# row -> file
  variable attente {}
}

proc ::moderne::basesliste::T {fr en} { return [::moderne::tr $fr $en] }

proc ::moderne::basesliste::ouvrir {} {
  variable w
  if {[winfo exists $w]} { ::createToplevel $w ; remplir ; return }
  # (made by a layout: the tab in front stays in front, the notation)
  set nb $::docking::layout_dest_notebook
  set devant {}
  if {$nb ne {} && [winfo exists $nb]} { catch {set devant [$nb select]} }
  ::createToplevel $w
  ::setTitle $w [T "Mes bases" "My databases"]
  set h [ttk::frame $w.haut -padding {8 6}]
  pack $h -side top -fill x
  ttk::button $h.ajouter -text [T "Ajouter une base…" "Add a database…"] -style Toolbutton \
      -command ::moderne::basesliste::ajouter
  ttk::button $h.nouvelle -text [T "Nouvelle base…" "New database…"] -style Toolbutton \
      -command {::file::New ; ::moderne::basesliste::remplir}
  ttk::button $h.vue -text [T "Vue en icônes" "Tile view"] -style Toolbutton -command ::moderne::mesbases::vue
  pack $h.ajouter $h.nouvelle -side left -padx {0 6}
  pack $h.vue -side right
  set f [ttk::frame $w.f]
  pack $f -side top -fill both -expand 1
  set t [ttk::treeview $f.t -columns {nom parties etat dossier} -show headings -selectmode browse \
      -yscrollcommand [list $f.sb set]]
  ttk::scrollbar $f.sb -command [list $t yview]
  pack $f.sb -side right -fill y
  pack $t -side left -fill both -expand 1
  foreach {col fr en larg ancre} {
    nom     "Base"     "Database" 200 w
    parties "Parties"  "Games"     90 e
    etat    "État"     "Status"   140 w
    dossier "Dossier"  "Folder"   220 w
  } {
    $t heading $col -text [T $fr $en] -command [list ::moderne::basesliste::trier $col]
    $t column $col -width $larg -anchor $ancre -stretch [expr {$col in {nom dossier}}]
  }
  $t tag configure ouverte -font font_Bold
  bind $t <Double-Button-1> {::moderne::basesliste::action ouvrirBase %x %y ; break}
  bind $t <Return> {::moderne::basesliste::action ouvrirBase}
  bind $t <Button-3> {::moderne::basesliste::menu %x %y %X %Y}
  bind $t <Delete> {::moderne::basesliste::action retirer}
  bind $t <Control-Delete> {::moderne::basesliste::action supprimer}
  bind $w <Map> "if {\"%W\" eq \"$w\"} ::moderne::basesliste::remplir"
  catch {::moderne::repeindre $w}
  ::createToplevelFinalize $w
  if {$devant ne {} && [winfo exists $devant]} { catch {$nb select $devant} }
  remplir
}

### "Add a database…": added (in « Other databases »), opened, first in the
### list and chosen (Yosha 2026-11-16: nothing seemed to happen, the list
### not refreshed and the database not opened)
proc ::moderne::basesliste::ajouter {} {
  variable w
  variable choisirApres
  set fs [::moderne::mesbases::ajouter]
  if {![llength $fs]} { return }
  set f [::moderne::mesbases::chemin [lindex $fs 0]]
  set choisirApres $f
  remplir
  catch {::moderne::mesbases::ouvrirBase $f}
  after 300 ::moderne::basesliste::remplir
}

### Value of column col for file f (sort key, then text)
proc ::moderne::basesliste::ligne {f ref gaby} {
  set ouverte [::moderne::mesbases::slot $f]
  set n {}
  catch {set n [::moderne::enligne::nbParties $f]}
  if {$ouverte} { set n [sc_base numGames $ouverte] } elseif {[::moderne::mesbases::estPgn $f]} { set n [::moderne::mesbases::nbPgn $f] }
  set etats {}
  if {[::moderne::mesbases::estPgn $f] && $n ne "PGN"} { lappend etats PGN }
  if {$ouverte} { lappend etats [T ouverte open] }
  if {$f eq $ref} { lappend etats [T référence reference] }
  if {[::moderne::mesbases::cadenassee $f]} { lappend etats 🔒 }
  set cle [file rootname [::moderne::nomBase $f]]
  set nom [expr {$f eq $gaby ? "★ $cle" : $cle}]
  set texteN [expr {[string is integer -strict $n] ? [::utils::thousands $n] : $n}]
  return [list $nom $texteN [join $etats " • "] [file nativename [file dirname $f]] \
      [expr {[string is integer -strict $n] ? $n : -1}] $ouverte $cle]
}

proc ::moderne::basesliste::remplir {} {
  variable w
  variable tri
  variable fichiers
  set t $w.f.t
  if {![winfo exists $t]} { return }
  set choisie {}
  catch {set choisie $fichiers([$t selection])}
  $t delete [$t children {}]
  array unset fichiers
  set gaby {}
  catch {set gaby [::moderne::mesbases::chemin [::moderne::gaby::trouverFichier]]}
  set ref $gaby
  catch {set ref [::moderne::mesbases::fichierRef]}
  set lignes {}
  foreach f [::moderne::mesbases::liste] {
    lappend lignes [list $f {*}[ligne $f $ref $gaby]]
  }
  lassign $tri col inverse
  # (always by name first: equal values stay in alphabetical order)
  set lignes [lsort -dictionary -index 7 $lignes]
  switch $col {
    parties { set lignes [lsort -integer -decreasing -index 5 $lignes] }
    etat    {
      # the reference first, then the open ones, then the most recently
      # opened (as the tile view's "Recently opened"), then by name
      # (Yosha 2026-11-12: the status text sorted as text put databases
      # without status above Gaby)
      set cles {}
      foreach l $lignes {
        set f [lindex $l 0]
        set rang [expr {$f eq $ref ? 0 : ([lindex $l 6] ? 1 : 2)}]
        set quand 0
        catch {set quand [dict get $::moderne::mesbases::ouvertures $f]}
        lappend cles [list $rang $quand $l]
      }
      set cles [lsort -integer -decreasing -index 1 $cles]
      set cles [lsort -integer -index 0 $cles]
      set lignes [lmap c $cles {lindex $c 2}]
    }
    dossier { set lignes [lsort -dictionary -index 4 $lignes] }
  }
  if {$inverse} { set lignes [lreverse $lignes] }
  # (added in this session: first, the last added at the top, as in the
  # tile view)
  set ajoutees {}
  set autres {}
  foreach l $lignes {
    set f [lindex $l 0]
    if {[dict exists $::moderne::mesbases::ajouts $f]} {
      lappend ajoutees [list [dict get $::moderne::mesbases::ajouts $f] $l]
    } else {
      lappend autres $l
    }
  }
  set lignes [concat [lmap x [lsort -integer -decreasing -index 0 $ajoutees] {lindex $x 1}] $autres]
  variable choisirApres
  if {[info exists choisirApres] && $choisirApres ne {}} { set choisie $choisirApres ; set choisirApres {} }
  foreach l $lignes {
    lassign $l f nom n etat dossier - ouverte
    set id [$t insert {} end -values [list $nom $n $etat $dossier] -tags [expr {$ouverte ? "ouverte" : ""}]]
    set fichiers($id) $f
    if {$f eq $choisie} { $t selection set $id ; $t see $id }
  }
  # the heading of the sort column shows its direction
  foreach c {nom parties etat dossier} {
    set texte [string trimright [$t heading $c -text] " ▲▼"]
    if {$c eq $col} { append texte [expr {$inverse ? " ▼" : " ▲"}] }
    $t heading $c -text $texte
  }
}

### Refreshed a moment after a database is opened, closed or changed
proc ::moderne::basesliste::plusTard {args} {
  variable w
  variable attente
  if {![winfo exists $w]} { return }
  after cancel $attente
  set attente [after 200 ::moderne::basesliste::remplir]
}
trace add execution updateMenuStates leave ::moderne::basesliste::plusTard

proc ::moderne::basesliste::trier {col} {
  variable tri
  lassign $tri c inverse
  set tri [list $col [expr {$c eq $col ? !$inverse : 0}]]
  remplir
}

### File of the row at x y (or of the selected row)
proc ::moderne::basesliste::fichier {{x {}} {y {}}} {
  variable w
  variable fichiers
  set t $w.f.t
  set id [expr {$x ne {} ? [$t identify row $x $y] : [lindex [$t selection] 0]}]
  if {$id eq {} || ![info exists fichiers($id)]} { return {} }
  $t selection set $id
  return $fichiers($id)
}

proc ::moderne::basesliste::action {quoi {x {}} {y {}}} {
  set f [fichier $x $y]
  if {$f eq {}} { return }
  ::moderne::mesbases::$quoi $f
  plusTard
}

proc ::moderne::basesliste::menu {x y X Y} {
  set f [fichier $x $y]
  if {$f eq {}} { return }
  ::moderne::mesbases::menu $f $X $Y
}
