
###
### Siby: repertoire training with spaced repetition
###
### Principle (spaced repetition): every position of your repertoire where it is
### your turn to move becomes a "card". SCID shows the position (after the
### line leading to it), you play the move on the board; if it is right,
### the card comes back later (1, 3, 7, 14, 30, 60, then 120 days); otherwise
### it comes back tomorrow.
###
### The repertoire is a SCID database (for example a course cleaned with Clean PGN,
### or an exported preparation): all its games, variations included, are
### read. You choose your color. Progress is stored in
### ~/.scidvspc/data/repetition_<base>_<couleur>.dat; if the repertoire changes,
### new positions become new cards and the progress of the others
### is kept.
###
### Tools menu › "Repertoire training (spaced repetition)…".
###

namespace eval ::moderne::entrainement {
  variable intervalles {0 1 3 7 14 30 60 120}  ;# days, by box (0 = new)
  variable nouvellesParSeance 20
  variable couleur white
  variable cartes        ;# cartes(fen) = {moves line}  (repertoire)
  variable ordre {}      ;# fens in repertoire order
  variable etat          ;# etat(fen) = {box dueDate successes failures}
  variable fichier {}
  variable file {}       ;# session queue (fens)
  variable courante {}   ;# fen of the current card
  variable depart {}     ;# start square chosen (first click)
  variable repondu 0
  variable stats         ;# stats(ok) stats(ko)
  array set cartes {}
  array set etat {}
  array set stats {ok 0 ko 0}
}

proc ::moderne::entrainement::T {fr en} { return [::moderne::tr $fr $en] }

### Runs a script on a "scratch" board (clipboard), without
### touching the current game or its number
proc ::moderne::entrainement::brouillon {script} {
  set courante [sc_base current]
  sc_base switch clipbase
  sc_game push copyfast
  set code [catch {uplevel 1 $script} res]
  sc_game pop
  sc_base switch $courante
  if {$code} { return -code error $res }
  return $res
}

proc ::moderne::entrainement::aujourdhui {} {
  return [expr {[clock seconds] / 86400}]
}

### Key of a position: placement, side to move, castling, en passant
proc ::moderne::entrainement::cle {fen} {
  return [join [lrange [split $fen] 0 3] " "]
}

################################################################################
### Reading the repertoire (all games, variations included)
################################################################################

proc ::moderne::entrainement::noter {fen san ligne} {
  variable cartes
  variable ordre
  variable couleur
  set trait [expr {[lindex [split $fen] 1] eq "w" ? "white" : "black"}]
  if {$trait ne $couleur} { return }
  set k [cle $fen]
  if {![info exists cartes($k)]} {
    set cartes($k) [list [list $san] $ligne $fen]
    lappend ordre $k
  } elseif {$san ni [lindex $cartes($k) 0]} {
    lset cartes($k) 0 [concat [lindex $cartes($k) 0] [list $san]]
  }
}

### Recursive walk of the current game from the current position
proc ::moderne::entrainement::parcourir {ligne} {
  while 1 {
    set fen [sc_pos fen]
    set principal [sc_game info nextMoveNT]
    if {$principal eq {}} { return }
    noter $fen $principal $ligne
    set nv [sc_var count]
    for {set i 0} {$i < $nv} {incr i} {
      sc_var enter $i                  ;# position after the variation's first move
      set premier [sc_game info previousMoveNT]
      noter $fen $premier $ligne
      parcourir [concat $ligne [list $premier]]
      sc_var exit                      ;# back to before the main-line move
    }
    sc_move forward
    lappend ligne $principal
  }
}

### Reads all games of database b. Returns the number of positions.
proc ::moderne::entrainement::lireRepertoire {b} {
  variable cartes
  variable ordre
  array unset cartes
  set ordre {}
  set courante [sc_base current]
  if {$courante != $b} { sc_base switch $b }
  set n [sc_base numGames]
  for {set i 1} {$i <= $n} {incr i} {
    if {[catch {sc_game load $i}]} { continue }
    sc_move start
    catch {parcourir {}}
  }
  if {$courante != $b} { sc_base switch $courante }
  return [llength $ordre]
}

################################################################################
### Progress (file)
################################################################################

proc ::moderne::entrainement::nomFichier {b} {
  variable couleur
  regsub -all {[^[:alnum:]_-]+} [file rootname [::moderne::nomBase [sc_base filename $b]]] _ nom
  set dir [file join $::scidUserDir data]
  file mkdir $dir
  return [file join $dir "repetition_${nom}_$couleur.dat"]
}

proc ::moderne::entrainement::charger {} {
  variable etat
  variable fichier
  array unset etat
  if {[file readable $fichier]} {
    set f [open $fichier r]
    fconfigure $f -encoding utf-8
    array set etat [read $f]
    close $f
  }
}

proc ::moderne::entrainement::sauver {} {
  variable etat
  variable fichier
  if {$fichier eq {}} { return }
  set f [open $fichier w]
  fconfigure $f -encoding utf-8
  puts $f [array get etat]
  close $f
}

### Result of an answer: updates the box and the due date
proc ::moderne::entrainement::noterReponse {k bon} {
  variable etat
  variable intervalles
  if {[info exists etat($k)]} {
    lassign $etat($k) boite echeance ok ko
  } else {
    lassign {0 0 0 0} boite echeance ok ko
  }
  if {$bon} {
    incr ok
    set boite [expr {min($boite + 1, [llength $intervalles] - 1)}]
  } else {
    incr ko
    set boite 1
  }
  set etat($k) [list $boite [expr {[aujourdhui] + [lindex $intervalles $boite]}] $ok $ko]
  sauver
}

### Cards due today, then new cards (in repertoire order)
proc ::moderne::entrainement::preparerFile {} {
  variable ordre
  variable etat
  variable file
  variable nouvellesParSeance
  set j [aujourdhui]
  set dues {}
  set nouvelles {}
  foreach k $ordre {
    if {[info exists etat($k)]} {
      if {[lindex $etat($k) 1] <= $j} { lappend dues [list $k [lindex $etat($k) 1]] }
    } else {
      lappend nouvelles $k
    }
  }
  set file {}
  foreach d [lsort -integer -index 1 $dues] { lappend file [lindex $d 0] }
  set nmax [expr {[string is integer -strict $nouvellesParSeance] ? $nouvellesParSeance : 20}]
  set file [concat $file [lrange $nouvelles 0 [expr {$nmax - 1}]]]
  return [list [llength $dues] [llength $nouvelles]]
}

################################################################################
### Window
################################################################################

proc ::moderne::entrainement::ouvrir {} {
  set w .entrainementWin
  if {[winfo exists $w]} { raiseWin $w ; return }
  toplevel $w
  wm title $w [T "Entraînement de répertoire" "Repertoire training"]
  ttk::frame $w.haut -padding {10 8}
  pack $w.haut -side top -fill x
  ttk::label $w.haut.lb -text [T "Répertoire : base courante" "Repertoire: current database"]
  ttk::radiobutton $w.haut.blancs -text [T "Je joue les Blancs" "I play White"] \
      -variable ::moderne::entrainement::couleur -value white
  ttk::radiobutton $w.haut.noirs -text [T "Je joue les Noirs" "I play Black"] \
      -variable ::moderne::entrainement::couleur -value black
  ttk::label $w.haut.ln -text [T "Nouvelles positions par séance :" "New positions per session:"]
  ttk::spinbox $w.haut.n -width 4 -from 0 -to 500 -textvariable ::moderne::entrainement::nouvellesParSeance
  ttk::button $w.haut.go -text [T "Commencer" "Start"] -command ::moderne::entrainement::commencer
  catch {::utils::tooltip::Set $w.haut.ln [T "Positions de ton répertoire que tu n'as jamais travaillées, ajoutées à chaque séance. Les autres reviennent quand il est temps de les revoir." "Positions of your repertoire you have never trained, added each session. The others come back when it is time to review them."]}
  grid $w.haut.lb $w.haut.blancs $w.haut.noirs -sticky w -padx 4 -pady 2
  grid $w.haut.ln $w.haut.n $w.haut.go -sticky w -padx 4 -pady 2

  ttk::label $w.info -padding {12 4} -font font_Bold -wraplength 560 -justify left -text [T \
"Choisis ta couleur puis « Commencer ». Joue le coup de ton répertoire en cliquant la pièce puis la case d'arrivée." \
"Choose your colour, then Start. Play your repertoire move by clicking the piece, then the target square."]
  pack $w.info -side top -fill x

  ttk::frame $w.centre
  pack $w.centre -side top -fill both -expand 1 -padx 10
  ::board::new $w.centre.board 50
  pack $w.centre.board -side left -padx 6 -pady 6
  ttk::frame $w.centre.d
  pack $w.centre.d -side left -fill both -expand 1 -padx 6
  ttk::label $w.centre.d.ligne -wraplength 300 -justify left -text {}
  ttk::label $w.centre.d.retour -wraplength 300 -justify left -font font_H3 -text {}
  ttk::label $w.centre.d.stats -wraplength 300 -justify left -text {}
  pack $w.centre.d.ligne $w.centre.d.retour $w.centre.d.stats -side top -anchor w -pady 6
  for {set i 0} {$i < 64} {incr i} {
    ::board::bind $w.centre.board $i <Button-1> [list ::moderne::entrainement::clic $i]
  }

  ttk::frame $w.bas -padding {10 4 10 10}
  pack $w.bas -side bottom -fill x
  ttk::button $w.bas.voir -text [T "Voir la réponse" "Show answer"] -command ::moderne::entrainement::voirReponse
  ttk::button $w.bas.suivant -text [T "Suivant" "Next"] -command ::moderne::entrainement::suivante
  ttk::button $w.bas.fermer -text [T "Fermer" "Close"] -command [list destroy $w]
  pack $w.bas.voir $w.bas.suivant -side left -padx 4
  pack $w.bas.fermer -side right -padx 4
  bind $w <Escape> [list destroy $w]
  bind $w <Return> ::moderne::entrainement::suivante
  catch {::moderne::repeindre $w}
}

proc ::moderne::entrainement::commencer {} {
  variable fichier
  variable ordre
  variable stats
  set w .entrainementWin
  set b [sc_base current]
  # A repertoire has at most a few thousand games (a reference database
  # would take all the memory)
  set nb [sc_base numGames $b]
  if {$nb > 20000} {
    tk_messageBox -parent $w -icon warning -type ok -title Siby -message [T \
        "La base courante a [::utils::thousands $nb] parties : ouvre ta base de répertoire (quelques centaines de parties) et rends-la courante." \
        "The current database has [::utils::thousands $nb] games: open your repertoire database (a few hundred games) and make it current."]
    return
  }
  # Reading loads the games of the current database: protect the current game
  set confirm [::game::ConfirmDiscardOnglet]
  if {$confirm == 2} { return }
  if {$confirm == 0} { ::game::Save }
  set num [sc_game number]
  busyCursor .
  set n [lireRepertoire $b]
  unbusyCursor .
  if {$num > 0} { catch {sc_game load $num} } else { sc_game new }
  catch {updateBoard -pgn}
  if {$n == 0} {
    $w.info configure -text [T "Aucune position à jouer pour cette couleur dans la base courante." \
                               "No position to play for this colour in the current database."]
    return
  }
  set fichier [nomFichier $b]
  charger
  lassign [preparerFile] nDues nNouvelles
  array set stats {ok 0 ko 0}
  $w.info configure -text "[T "Répertoire" "Repertoire"] : [::utils::thousands $n] [T "positions" "positions"] • [T "à revoir aujourd'hui" "due today"] : $nDues • [T "jamais vues" "never seen"] : $nNouvelles"
  suivante
}

### Shows the position of card k
proc ::moderne::entrainement::afficherCarte {k} {
  variable cartes
  variable couleur
  set w .entrainementWin
  lassign $cartes($k) coups ligne fen
  set plateau [brouillon { sc_game startBoard $fen ; sc_pos board }]
  set b $w.centre.board
  if {[::board::isFlipped $b] != ($couleur eq "black")} { ::board::flip $b }
  ::board::update $b $plateau
  $b.bd delete mark
}

proc ::moderne::entrainement::texteLigne {ligne fen} {
  # numbering from an unknown starting FEN: number from 1
  set res {}
  set i 0
  foreach c $ligne {
    if {$i % 2 == 0} { append res "[expr {$i / 2 + 1}].$c " } else { append res "$c " }
    incr i
  }
  return [::trans [string trim $res]]
}

proc ::moderne::entrainement::suivante {} {
  variable file
  variable courante
  variable cartes
  variable depart
  variable repondu
  variable stats
  set w .entrainementWin
  if {![winfo exists $w]} { return }
  set depart {}
  set repondu 0
  $w.centre.d.retour configure -text {}
  if {![llength $file]} {
    set courante {}
    $w.centre.d.ligne configure -text [T "Séance terminée. Bravo !" "Session complete. Well done!"]
    $w.centre.d.stats configure -text "[T "Réussites" "Correct"] : $stats(ok) • [T "à revoir" "to review"] : $stats(ko)"
    return
  }
  set courante [lindex $file 0]
  set file [lrange $file 1 end]
  afficherCarte $courante
  lassign $cartes($courante) coups ligne fen
  set txt [expr {[llength $ligne] ? [texteLigne $ligne $fen] : [T "(position de départ)" "(starting position)"]}]
  $w.centre.d.ligne configure -text "$txt\n\n[T "À toi de jouer." "Your move."]"
  $w.centre.d.stats configure -text "[T "Reste" "Left"] : [expr {[llength $file] + 1}] • [T "Réussites" "Correct"] : $stats(ok) • [T "à revoir" "to review"] : $stats(ko)"
}

### Click on a square: first click = piece, second click = destination square
proc ::moderne::entrainement::clic {sq} {
  variable depart
  variable courante
  variable repondu
  set w .entrainementWin
  if {$courante eq {} || $repondu} { return }
  set b $w.centre.board
  if {$depart eq {}} {
    set depart $sq
    ::board::colorSquare $b $sq $::highcolor
    return
  }
  set de $depart
  set depart {}
  ::board::colorSquare $b $de
  if {$de == $sq} { return }
  set uci "[::board::san $de][::board::san $sq]"
  verifier $uci
}

proc ::moderne::entrainement::verifier {uci} {
  variable cartes
  variable courante
  variable repondu
  variable stats
  set w .entrainementWin
  lassign $cartes($courante) coups ligne fen
  # Move played -> SAN (queen promotion by default); illegal move = ignored
  set san [brouillon {
    sc_game startBoard $fen
    if {[catch {sc_move addUCI $uci}] && [catch {sc_move addUCI ${uci}q}]} {
      set r {}
    } else {
      set r [sc_game info previousMoveNT]
    }
    set r
  }]
  if {$san eq {}} { return }   ;# illegal move: wait for another try
  set repondu 1
  if {$san in $coups} {
    incr stats(ok)
    noterReponse $courante 1
    $w.centre.d.retour configure -foreground #7fd18b -text "✓ [::trans $san]"
    after 700 ::moderne::entrainement::suivante
  } else {
    incr stats(ko)
    noterReponse $courante 0
    $w.centre.d.retour configure -foreground #ef8f7f -text \
        "✗ [::trans $san] • [T "attendu" "expected"] : [::trans [join $coups {, }]]"
    montrerReponse
  }
}

### Arrow on the expected move(s)
proc ::moderne::entrainement::montrerReponse {} {
  variable cartes
  variable courante
  set w .entrainementWin
  lassign $cartes($courante) coups ligne fen
  foreach san $coups {
    set uci [brouillon {
      sc_game startBoard $fen
      if {[catch {sc_move addSan $san}]} { set r {} } else { set r [sc_game info previousMoveUCI] }
      set r
    }]
    if {$uci eq {}} { continue }
    set de [lsearch -exact $::board::squareIndex [string range $uci 0 1]]
    set a [lsearch -exact $::board::squareIndex [string range $uci 2 3]]
    ::board::mark::DrawArrow $w.centre.board.bd $de $a #15781b
  }
}

proc ::moderne::entrainement::voirReponse {} {
  variable courante
  variable repondu
  variable stats
  variable cartes
  set w .entrainementWin
  if {$courante eq {} || $repondu} { return }
  set repondu 1
  incr stats(ko)
  noterReponse $courante 0
  lassign $cartes($courante) coups
  $w.centre.d.retour configure -foreground #f0b35b -text "[T "Réponse" "Answer"] : [::trans [join $coups {, }]]"
  montrerReponse
}

### End Siby
