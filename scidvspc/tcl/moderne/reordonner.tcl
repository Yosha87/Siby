###
### Siby: putting the games of a database (or a PGN file) in one's own
### order: File › Reorder the games… A list of all the games, rows moved
### with the mouse (drag and drop) or the ↑ / ↓ buttons, then "Fix the
### order" (with confirmation): the games are copied in that order (moves,
### variations, comments, flags kept) into a new database, which replaces
### the old one. The original is kept as a copy: base.avant-ordre.si4 (and
### .sn4, .sg4); a PGN file is rewritten through a temporary file (no .bak
### since 2026-11-02). Up to 5,000 games.
###

namespace eval ::moderne::reordonner {
  variable w .reordonnerWin
  variable base 0
  variable glisse {}
  variable max 5000
}

proc ::moderne::reordonner::T {fr en} { return [::moderne::tr $fr $en] }

proc ::moderne::reordonner::ouvrir {} {
  variable w
  variable base
  variable max
  set b [sc_base current]
  if {$b == [sc_info clipbase] || ![sc_base inUse $b]} {
    tk_messageBox -icon info -type ok -title Siby -message [T "Ouvre d'abord la base (ou le fichier PGN) à réordonner." \
        "Open the database (or PGN file) to reorder first."]
    return
  }
  set n [sc_base numGames $b]
  if {$n < 2 || $n > $max} {
    tk_messageBox -icon info -type ok -title Siby -message [T \
        "Réordonner à la main est prévu pour les bases de 2 à [::utils::thousands $max] parties (celle-ci en a [::utils::thousands $n])." \
        "Reordering by hand is meant for databases of 2 to [::utils::thousands $max] games (this one has [::utils::thousands $n])."]
    return
  }
  if {![catch {::moderne::mesbases::estCadenassee $b} c] && $c} {
    tk_messageBox -icon info -type ok -title Siby -message [T \
        "Cette base est cadenassée. Retire d'abord le cadenas (Mes bases, clic droit sur la base)." \
        "This database is padlocked. Remove the padlock first (My databases, right click on the database)."]
    return
  }
  if {![info exists ::moderne::pgnfichier::fichier($b)] && [sc_base isReadOnly $b]} {
    tk_messageBox -icon info -type ok -title Siby -message [T "Cette base est en lecture seule." "This database is read-only."]
    return
  }
  set base $b
  catch {destroy $w}
  toplevel $w
  wm title $w "[T "Réordonner les parties" "Reorder the games"] : [::moderne::nomBase [sc_base filename $b]]"
  set f [ttk::frame $w.f -padding 12]
  pack $f -fill both -expand 1
  # (a PGN file is rewritten in place: no copy is kept, the sentence only
  # for a database)
  set copie [expr {[info exists ::moderne::pgnfichier::fichier($b)] ? "" : [T " L'original est gardé en copie." " The original is kept as a copy."]}]
  ttk::label $f.intro -wraplength 700 -justify left -foreground [::moderne::c texteDoux] -text [T \
      "Glisse les parties à la souris (ou ↑ / ↓) pour les mettre dans ton ordre, puis « Fixer l'ordre ».$copie" \
      "Drag the games with the mouse (or ↑ / ↓) to put them in your order, then \"Fix the order\".$copie"]
  catch {::moderne::enBulle $f.intro}
  pack $f.intro -side top -anchor w -pady {0 8}
  set t [ttk::treeview $f.t -columns {num blanc noir res tournoi date} -show headings -selectmode extended -height 20]
  foreach {c fr en l a} {num N° No 50 e blanc Blancs White 170 w noir Noirs Black 170 w res Rés. Res. 60 center
                         tournoi Tournoi Event 200 w date Date Date 90 center} {
    $t heading $c -text [T $fr $en]
    $t column $c -width $l -anchor $a -stretch [expr {$c in {blanc noir tournoi}}]
  }
  ttk::scrollbar $f.sb -command [list $t yview]
  $t configure -yscrollcommand [list $f.sb set]
  ttk::frame $f.b
  ttk::button $f.b.haut -text "↑" -width 3 -command {::moderne::reordonner::deplacer -1}
  ttk::button $f.b.bas -text "↓" -width 3 -command {::moderne::reordonner::deplacer 1}
  ttk::label $f.b.etat -foreground [::moderne::c texteDoux] -text {}
  ttk::button $f.b.fixer -text [T "Fixer l'ordre" "Fix the order"] -command ::moderne::reordonner::fixer -state disabled
  catch {$f.b.fixer configure -style Accent.TButton}
  ttk::button $f.b.annuler -text [T "Fermer" "Close"] -command [list destroy $w]
  pack $f.b.haut $f.b.bas -side left -padx {0 4}
  pack $f.b.etat -side left -padx 10
  pack $f.b.annuler $f.b.fixer -side right -padx {6 0}
  pack $f.b -side bottom -fill x -pady {8 0}
  pack $f.sb -side right -fill y
  pack $t -side left -fill both -expand 1
  # games in their current order
  set courante [sc_base current]
  foreach r [sc_gaby tags $b 1 [sc_base numGames $b] White Black Result Event Date] {
    lassign $r g bl no res ev d
    $t insert {} end -id g$g -values [list $g $bl $no [string map {1/2-1/2 ½-½} $res] $ev $d]
  }
  bind $t <ButtonPress-1> {::moderne::reordonner::prendre %W %y}
  bind $t <B1-Motion> {::moderne::reordonner::survoler %W %y}
  bind $t <ButtonRelease-1> {::moderne::reordonner::poser %W %y}
  bind $w <Escape> [list destroy $w]
  catch {::moderne::repeindre $w}
  catch {placeWinOverParent $w .}
}

proc ::moderne::reordonner::arbre {} { return .reordonnerWin.f.t }

### Order shown: list of game numbers
proc ::moderne::reordonner::ordre {} {
  set l {}
  foreach id [[arbre] children {}] { lappend l [string range $id 1 end] }
  return $l
}

proc ::moderne::reordonner::changement {} {
  set l [ordre]
  set n 0
  set i 1
  foreach g $l { if {$g != $i} { incr n } ; incr i }
  set f .reordonnerWin.f.b
  $f.etat configure -text [expr {$n ? "[T "Ordre modifié" "Order changed"] ($n [T "parties à une autre place" "games moved"])" : {}}]
  $f.fixer configure -state [expr {$n ? "normal" : "disabled"}]
}

### Drag and drop
proc ::moderne::reordonner::prendre {t y} {
  variable glisse
  set id [$t identify item 5 $y]
  set glisse {}
  if {$id eq {}} { return }
  if {$id ni [$t selection]} { return }
  set glisse [$t selection]
}

proc ::moderne::reordonner::survoler {t y} {
  variable glisse
  if {![llength $glisse]} { return }
  set cible [$t identify item 5 $y]
  if {$cible eq {} || $cible in $glisse} { return }
  $t focus $cible
  $t see $cible
}

proc ::moderne::reordonner::poser {t y} {
  variable glisse
  if {![llength $glisse]} { return }
  set cible [$t identify item 5 $y]
  set l $glisse
  set glisse {}
  if {$cible eq {} || $cible in $l} { return }
  # dropped on a row: the dragged games go before it (after it when
  # moving down)
  set ic [$t index $cible]
  set i0 [$t index [lindex $l 0]]
  set pos [expr {$i0 < $ic ? $ic + 1 : $ic}]
  foreach id $l {
    set avant [$t index $id]
    if {$avant < $pos} { incr pos -1 }
    $t move $id {} $pos
    incr pos
  }
  $t selection set $l
  changement
}

### ↑ / ↓: the selection moves by one row
proc ::moderne::reordonner::deplacer {d} {
  set t [arbre]
  set sel [$t selection]
  if {![llength $sel]} { return }
  set ids [lsort -command [list ::moderne::reordonner::parIndex $t] $sel]
  if {$d > 0} { set ids [lreverse $ids] }
  foreach id $ids {
    set i [$t index $id]
    set j [expr {$i + $d}]
    if {$j < 0 || $j >= [llength [$t children {}]]} { return }
    $t move $id {} $j
  }
  $t see [lindex $ids 0]
  changement
}

proc ::moderne::reordonner::parIndex {t a b} { expr {[$t index $a] - [$t index $b]} }

################################################################################
### Fixing the order
################################################################################

proc ::moderne::reordonner::fixer {} {
  variable base
  set b $base
  if {![sc_base inUse $b]} { return }
  set l [ordre]
  set estPgn [info exists ::moderne::pgnfichier::fichier($b)]
  set copie [expr {$estPgn ? "" : [T " L'original est gardé en copie." " The original is kept as a copy."]}]
  if {[tk_messageBox -parent .reordonnerWin -icon question -type yesno -title Siby -message [T \
      "Enregistrer les [llength $l] parties de [::moderne::nomBase [sc_base filename $b]] dans cet ordre ?$copie" \
      "Save the [llength $l] games of [::moderne::nomBase [sc_base filename $b]] in this order?$copie"]] ne "yes"} { return }
  if {[sc_base current] == $b && [sc_game altered]} {
    if {[tk_messageBox -parent .reordonnerWin -icon warning -type yesno -title Siby -message [T \
        "La partie ouverte a des modifications non enregistrées, qui seront perdues. Continuer ?" \
        "The open game has unsaved changes, which will be lost. Go on?"]] ne "yes"} { return }
  }
  set pgn [expr {[info exists ::moderne::pgnfichier::fichier($b)] ? $::moderne::pgnfichier::fichier($b) : {}}]
  set racine [sc_base filename $b]
  # the games, in the new order, into a new database
  set tmp [file join [expr {$pgn ne {} ? [::moderne::gaby::dossierTemp] : [file dirname $racine]}] "[file tail $racine].nouvel-ordre"]
  foreach x {.si4 .sn4 .sg4} { catch {file delete -force $tmp$x} }
  busyCursor .
  set code [catch {
    set n [sc_base create $tmp]
    sc_filter copy $b $n $l
    if {[sc_base numGames $n] != [llength $l]} { error [T "copie incomplète" "incomplete copy"] }
    # flag names (Gaby…) follow
    sc_base switch $n
    for {set k 1} {$k <= 6} {incr k} {
      set desc {}
      sc_base switch $b
      catch {set desc [sc_game flag $k description]}
      sc_base switch $n
      if {[string trim $desc] ne {}} { catch {sc_game flag $k setdescription $desc} }
    }
    if {$pgn ne {}} {
      # PGN file: written from the new database to a temporary file, which
      # then replaces the original (no .bak copy since 2026-11-02)
      sc_base export all PGN $pgn.siby-tmp -append 0 -starttext "" -endtext "" -comments 1 -variations 1 \
          -spaces 0 -symbols 0 -indentComments 0 -indentVariations 0 -column 0 -noMarkCodes 0 \
          -convertNullMoves 1 -newlines 1 -utf8 1 -bom 0
      sc_base close $n
      file rename -force $pgn.siby-tmp $pgn
    } else {
      sc_base close $n
    }
  } err]
  unbusyCursor .
  if {$code} {
    catch {sc_base close $n}
    foreach x {.si4 .sn4 .sg4} { catch {file delete -force $tmp$x} }
    tk_messageBox -icon error -type ok -title Siby -message "[T "L'ordre n'a pas pu être fixé (la base est intacte) :" "The order could not be fixed (the database is untouched):"]\n$err"
    return
  }
  # the database is reopened (its game numbers have changed)
  sc_base switch $b
  sc_game new
  ::file::Close $b
  if {$pgn ne {}} {
    foreach x {.si4 .sn4 .sg4} { catch {file delete -force $tmp$x} }
    ::file::Open $pgn
  } else {
    # the original kept as base.avant-ordre.*, the new one in its place
    set sauve "$racine.avant-ordre"
    foreach x {.si4 .sn4 .sg4} {
      catch {file delete -force $sauve$x}
      file rename -force $racine$x $sauve$x
      file rename -force $tmp$x $racine$x
    }
    foreach x {.sbl .online.sbl .ajouts.sbl .ajouts.online.sbl .sbp .classical.sbl .classical.online.sbl .rapid.sbl .rapid.online.sbl .blitz.sbl .blitz.online.sbl .classical.ajouts.sbl .classical.ajouts.online.sbl .rapid.ajouts.sbl .rapid.ajouts.online.sbl .blitz.ajouts.sbl .blitz.ajouts.online.sbl} { catch {file delete -force $racine$x} }
    ::file::Open $racine
  }
  catch {destroy .reordonnerWin}
  catch {::moderne::nsb::annonce [expr {$estPgn ? [T "Ordre fixé" "Order fixed"] : [T "Ordre fixé (original gardé en copie)" "Order fixed (original kept as a copy)"]}] -1}
  after 3000 {catch ::moderne::nsb::finAnnonce}
}

### End Siby
