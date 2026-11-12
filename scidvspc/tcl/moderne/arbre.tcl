
###
### Siby: tree analysis ("Deep Position Analysis")
###
### Starting from the board position, the engine (F2 key) explores the
### best moves of both sides: at each position, the N best moves
### (MultiPV) within X centipawns of the best one, down to the chosen
### depth. Transpositions are explored only once. The tree
### is displayed as it grows; "Open the tree" copies it into a
### new game in the clipboard (variations and evaluations as
### comments), without touching the current game.
###
### Tools › Tree analysis…
###

namespace eval ::moderne::arbre {
  variable w .arbreWin
  variable largeur 3       ;# moves per position
  variable profondeur 6    ;# plies
  variable temps 1000      ;# ms per position
  variable ecart 60        ;# maximum gap in centipawns from the best move
  variable pipe {}
  variable etat idle
  variable file {}         ;# positions to analyze: {key fen depth}
  variable courant {}
  variable lignesPV        ;# lignesPV(n) = {cp uciMove}
  array set lignesPV {}
  variable noeuds          ;# noeuds(key) = {fen children}; children = {{san uci cpWhite childKey} …}
  array set noeuds {}
  variable racine {}
  variable fait 0
  variable item            ;# item(key) = treeview item
  array set item {}
}

proc ::moderne::arbre::T {fr en} { return [::moderne::tr $fr $en] }

### Move number "12." or "12..." (no expr: "12." would become 12.0)
proc ::moderne::arbre::numero {noir num {force 1} {espace " "}} {
  if {!$noir} { return "$num.$espace" }
  if {$force} { return "$num...$espace" }
  return {}
}

proc ::moderne::arbre::ouvrir {} {
  variable w
  if {[winfo exists $w]} { raiseWin $w ; return }
  toplevel $w
  wm title $w [T "Analyse en arbre" "Tree analysis"]
  wm geometry $w 760x720
  set h $w.h
  ttk::frame $h -padding {10 8 10 4}
  pack $h -side top -fill x
  foreach {v fr en de a pas} {
    largeur    "Coups par position :" "Moves per position:" 1 6 1
    profondeur "Profondeur (demi-coups) :" "Depth (plies):" 1 14 1
    temps      "Temps par position (ms) :" "Time per position (ms):" 100 30000 100
    ecart      "Écart max. avec le meilleur (cp) :" "Max. gap from best (cp):" 0 500 10
  } {
    ttk::label $h.l$v -text [T $fr $en]
    ttk::spinbox $h.$v -width 7 -from $de -to $a -increment $pas -textvariable ::moderne::arbre::$v \
        -command ::moderne::arbre::estimer
    bind $h.$v <KeyRelease> ::moderne::arbre::estimer
    grid $h.l$v $h.$v -sticky w -padx 4 -pady 1
  }
  ttk::frame $w.b -padding {10 4}
  pack $w.b -side top -fill x
  ttk::button $w.b.go -text [T "Analyser la position de l'échiquier" "Analyse the board position"] -command ::moderne::arbre::lancer
  ttk::button $w.b.stop -text [T "Arrêter" "Stop"] -state disabled -command ::moderne::arbre::arreter
  ttk::button $w.b.ouvrir -text [T "Ouvrir l'arbre (nouvelle partie)" "Open the tree (new game)"] -state disabled \
      -command ::moderne::arbre::ouvrirPartie
  pack $w.b.go $w.b.stop $w.b.ouvrir -side left -padx 3
  ttk::label $w.etat -padding {12 4} -wraplength 720 -justify left -text {}
  pack $w.etat -side top -fill x
  ttk::treeview $w.t -columns {eval} -selectmode browse
  $w.t heading #0 -text [T "Coups (le meilleur en premier)" "Moves (best first)"] -anchor w
  $w.t heading eval -text [T "Éval. (Blancs)" "Eval (White)"]
  $w.t column eval -width 110 -anchor e -stretch 0
  ttk::scrollbar $w.sb -command [list $w.t yview]
  $w.t configure -yscrollcommand [list $w.sb set]
  pack $w.sb -side right -fill y -padx {0 10} -pady {0 10}
  pack $w.t -side left -fill both -expand 1 -padx {10 0} -pady {0 10}
  bind $w <Escape> [list destroy $w]
  bind $w <Destroy> [list ::moderne::arbre::fermeture %W]
  catch {::moderne::repeindre $w}
  estimer
}

proc ::moderne::arbre::fermeture {widget} {
  variable w
  if {$widget eq $w} { fermer }
}

### Maximum number of positions and corresponding duration
proc ::moderne::arbre::estimer {} {
  variable w
  variable largeur
  variable profondeur
  variable temps
  if {![winfo exists $w] || ![string is integer -strict $largeur] || ![string is integer -strict $profondeur] ||
      ![string is integer -strict $temps]} { return }
  set n 0
  set p 1
  for {set d 0} {$d < $profondeur} {incr d} { incr n $p ; set p [expr {$p * $largeur}] }
  set s [expr {$n * $temps / 1000}]
  $w.etat configure -text "[T "Au plus" "At most"] [::utils::thousands $n] [T "positions, soit" "positions, i.e."] \
[expr {$s / 3600}] h [format %02d [expr {$s / 60 % 60}]] min [T "(souvent bien moins : seuls les coups proches du meilleur sont suivis)." "(often much less: only moves close to the best are followed)."]"
}

################################################################################
### Exploration
################################################################################

proc ::moderne::arbre::lancer {} {
  variable w
  variable etat
  variable file
  variable noeuds
  variable racine
  variable fait
  variable item
  variable largeur
  if {$etat ne "idle"} { return }
  set e [::moderne::erreurs::moteur]
  if {$e eq {}} {
    $w.etat configure -text [T "Aucun moteur configuré." "No engine configured."]
    return
  }
  array unset noeuds
  array unset item
  $w.t delete [$w.t children {}]
  set fen [sc_pos fen]
  set racine [::moderne::erreurs::cleFen $fen]
  set noeuds($racine) [list $fen {}]
  set item($racine) {}
  set file [list [list $racine $fen 0]]
  set fait 0
  if {![demarrer $e]} { return }
  $w.b.go configure -state disabled
  $w.b.stop configure -state normal
  $w.b.ouvrir configure -state disabled
}

proc ::moderne::arbre::demarrer {e} {
  variable pipe
  variable etat
  variable largeur
  variable w
  variable moteurN [::moderne::occupation::index $e]
  if {![::moderne::occupation::prendre $moteurN arbre {::moderne::arbre::arreter ; ::moderne::arbre::fermer}]} {
    $w.etat configure -text [T "Annulé : le moteur est utilisé ailleurs." "Cancelled: the engine is used elsewhere."]
    return 0
  }
  set ancien [pwd]
  catch {cd [lindex $e 3]}
  set ok [catch {set pipe [open "| [list [lindex $e 1]] [lindex $e 2]" r+]} err]
  catch {cd $ancien}
  if {$ok} {
    $w.etat configure -text "[T "Impossible de lancer le moteur" "Cannot start the engine"] : $err"
    set pipe {}
    return 0
  }
  fconfigure $pipe -buffering line -blocking 0
  fileevent $pipe readable ::moderne::arbre::lire
  set etat init
  envoyer uci
  foreach opt [lindex $e 8] {
    lassign $opt nom val
    if {$nom in {MultiPV UCI_AnalyseMode}} { continue }
    envoyer "setoption name $nom value $val"
  }
  envoyer "setoption name MultiPV value $largeur"
  envoyer isready
  return 1
}

proc ::moderne::arbre::envoyer {texte} {
  variable pipe
  if {$pipe eq {}} { return }
  catch {puts $pipe $texte ; flush $pipe}
}

proc ::moderne::arbre::lire {} {
  variable pipe
  variable etat
  variable lignesPV
  if {$pipe eq {}} { return }
  if {[eof $pipe]} { fermer ; return }
  while {$pipe ne {} && [gets $pipe l] >= 0} {
    if {$etat eq "init"} {
      if {$l eq "readyok"} { set etat analyse ; suivante }
      continue
    }
    if {[string match "info *" $l] && [string first " pv " $l] > 0} {
      if {[regexp {score (?:lower|upper)bound} $l] || [regexp {score (cp|mate) -?[0-9]+ (lower|upper)bound} $l]} { continue }
      set n 1
      regexp {multipv ([0-9]+)} $l -> n
      if {[regexp {score (cp|mate) (-?[0-9]+)} $l -> t v] && [regexp { pv ([a-h][1-8][a-h][1-8][qrbn]?)} $l -> c]} {
        set cp [expr {$t eq "mate" ? ($v > 0 ? 10000 - 10 * $v : -10000 - 10 * $v) : $v}]
        set lignesPV($n) [list $cp $c]
      }
    } elseif {[string match "bestmove *" $l]} {
      fini
    }
  }
}

proc ::moderne::arbre::suivante {} {
  variable file
  variable courant
  variable lignesPV
  variable temps
  if {![llength $file]} { termine ; return }
  set courant [lindex $file 0]
  set file [lrange $file 1 end]
  array unset lignesPV
  envoyer "position fen [lindex $courant 1]"
  envoyer "go movetime $temps"
}

### Analyzed position: keep the moves close to the best one, create the
### child positions and queue them
proc ::moderne::arbre::fini {} {
  variable courant
  variable lignesPV
  variable noeuds
  variable file
  variable ecart
  variable profondeur
  variable fait
  variable item
  variable w
  incr fait
  lassign $courant k fen prof
  set lignes {}
  foreach n [lsort -integer [array names lignesPV]] { lappend lignes $lignesPV($n) }
  if {[llength $lignes]} {
    set noir [expr {[lindex [split $fen] 1] eq "b"}]
    set meilleur [lindex $lignes 0 0]
    set enfants {}
    set dejaVus {}
    foreach l $lignes {
      lassign $l cp uci
      if {$meilleur - $cp > $ecart} { continue }
      # (with short time, a MultiPV line may be left over from a previous
      # iteration and repeat a move already seen)
      if {$uci in $dejaVus} { continue }
      lappend dejaVus $uci
      # Position after the move, move in SAN (scratch board: the game is not touched)
      set r [::moderne::entrainement::brouillon {
        sc_game startBoard $fen
        set san [string trim [sc_move addUCI $uci]]
        list $san [sc_pos fen]
      }]
      lassign $r san fen2
      set k2 [::moderne::erreurs::cleFen $fen2]
      set cpBlancs [expr {$noir ? -$cp : $cp}]
      lappend enfants [list $san $uci $cpBlancs $k2]
      # Display
      set num [expr {[lindex [split $fen] 5]}]
      set texte "[numero $noir $num 1 {}][::trans $san]"
      if {[winfo exists $w]} {
        set id [$w.t insert $item($k) end -text $texte -values [list [::moderne::erreurs::texteEval $cpBlancs]] -open 1]
      }
      if {![info exists noeuds($k2)]} {
        set noeuds($k2) [list $fen2 {}]
        set item($k2) [expr {[winfo exists $w] ? $id : {}}]
        if {$prof + 1 < $profondeur} { lappend file [list $k2 $fen2 [expr {$prof + 1}]] }
      }
    }
    lset noeuds($k) 1 $enfants
  }
  if {[winfo exists $w]} {
    $w.etat configure -text "[T "Analyse" "Analysis"] : $fait [T "positions faites" "positions done"], [llength $file] [T "en attente" "queued"]…"
  }
  suivante
}

proc ::moderne::arbre::arreter {} {
  variable file
  set file {}
  envoyer stop
}

proc ::moderne::arbre::termine {} {
  variable w
  variable fait
  fermer
  if {[winfo exists $w]} {
    $w.etat configure -text "[T "Terminé" "Done"] : $fait [T "positions analysées. « Ouvrir l'arbre » le copie dans une nouvelle partie du presse-papier." "positions analysed. \"Open the tree\" copies it to a new clipbase game."]"
    $w.b.ouvrir configure -state normal
  }
}

proc ::moderne::arbre::fermer {} {
  variable pipe
  variable etat
  variable w
  variable moteurN
  if {[info exists moteurN]} { ::moderne::occupation::liberer $moteurN arbre }
  if {$pipe ne {}} {
    catch {fileevent $pipe readable {}}
    catch {puts $pipe quit ; flush $pipe}
    catch {close $pipe}
  }
  set pipe {}
  set etat idle
  if {[winfo exists $w]} {
    $w.b.go configure -state normal
    $w.b.stop configure -state disabled
  }
}

################################################################################
### Copy into a game (PGN with variations)
################################################################################

### PGN text of the moves from position k (the best one as the main
### line, the others as variations)
proc ::moderne::arbre::pgn {k {numeroForce 1} {vus {}}} {
  variable noeuds
  if {![info exists noeuds($k)] || $k in $vus} { return {} }
  lappend vus $k
  lassign $noeuds($k) fen enfants
  if {![llength $enfants]} { return {} }
  set noir [expr {[lindex [split $fen] 1] eq "b"}]
  set num [lindex [split $fen] 5]
  set txt {}
  set premier [lindex $enfants 0]
  lassign $premier san uci cp k2
  append txt [numero $noir $num $numeroForce] "$san {[::moderne::erreurs::texteEval $cp]} "
  foreach e [lrange $enfants 1 end] {
    lassign $e s u c kk
    append txt "( [numero $noir $num]$s {[::moderne::erreurs::texteEval $c]} [pgn $kk 0 $vus]) "
  }
  append txt [pgn $k2 [expr {[llength $enfants] > 1}] $vus]
  return $txt
}

proc ::moderne::arbre::ouvrirPartie {} {
  variable racine
  variable noeuds
  if {$racine eq {} || ![info exists noeuds($racine)]} { return }
  set fen [lindex $noeuds($racine) 0]
  set texte "\[Event \"[T "Analyse en arbre" "Tree analysis"]\"\]\n\[Annotator \"[lindex [::moderne::erreurs::moteur] 0]\"\]\n"
  append texte "\[SetUp \"1\"\]\n\[FEN \"$fen\"\]\n\n[pgn $racine] *\n"
  set confirm [::game::ConfirmDiscardOnglet]
  if {$confirm == 2} { return }
  if {$confirm == 0} { ::game::Save }
  if {[sc_base current] != [sc_info clipbase]} { ::file::SwitchToBase [sc_info clipbase] }
  sc_game new
  if {[catch {sc_game import $texte} err]} {
    tk_messageBox -icon error -type ok -title Siby -message $err
    return
  }
  catch {sc_game save 0}
  sc_move start
  updateBoard -pgn
  catch {::windows::gamelist::Refresh}
  catch {refreshWindows}
}

### End Siby
