
###
### Siby: Lichess-style clocks for games against an engine
###
### The "Play against an engine" window (tcl/tools/sergame.tcl) had two
### analog dials. Here: two large digital clocks, oriented the same way
### as the board (opponent at the top, you at the bottom), with the
### player's name; the running one is highlighted, red under 20 seconds.
### The countdown is still SCID's (::gameclock): only the display changes.
###

namespace eval ::moderne::pendule {}

proc ::moderne::pendule::T {fr en} { return [::moderne::tr $fr $en] }

### "4:59", "1:02:03"; under 10 s: "0:09"
proc ::moderne::pendule::texte {sec} {
  set sec [expr {abs(int($sec))}]
  set h [expr {$sec / 3600}]
  set m [expr {($sec % 3600) / 60}]
  set s [expr {$sec % 60}]
  if {$h > 0} { return [format "%d:%02d:%02d" $h $m $s] }
  return [format "%d:%02d" $m $s]
}

### Font for the clocks (fixed-width digits) and the moves
proc ::moderne::pendule::polices {} {
  if {"font_Pendule" in [font names]} { return }
  set fam [font actual font_Regular -family]
  foreach f {{Roboto Mono} Consolas {DejaVu Sans Mono} {Liberation Mono} {Courier New}} {
    if {[lsearch -exact [font families] $f] >= 0} { set fam $f ; break }
  }
  font create font_Pendule -family $fam -size 30
  font create font_PenduleDixiemes -family $fam -size 20
  set r [font actual font_Regular -family]
  font create font_JeuCoups -family $r -size 12
  font create font_JeuCoupsGras -family $r -size 12 -weight bold
  font create font_JeuNom -family $r -size 12
  font create font_JeuResultat -family $r -size 15 -weight bold
  font create font_JeuRaison -family $r -size 11 -slant italic
  font create font_JeuBouton -family $r -size 11
  font create font_JeuRevanche -family $r -size 13
  variable figurines {}
  foreach f {{Segoe UI Symbol} {DejaVu Sans} {Noto Sans Symbols2} {Arial Unicode MS} {FreeSerif}} {
    if {[lsearch -exact [font families] $f] >= 0} { set figurines $f ; break }
  }
  if {$figurines ne {}} { font create font_JeuFigurine -family $figurines -size 12 }
}

### Panel colors (Lichess dark theme)
array set ::moderne::pendule::coul {
  fond #262421  case #302e2c  texte #bababa  doux #8b8a88  num #403e3c
  marche #3d5c25  urgence #8a3a24  tombe #5b3329  courant #34577a
  bouton #3a3836  survol #4a4846  point #629924
}

### Called at the end of building the game window
proc ::moderne::pendule::habiller {w} {
  variable coul
  variable ordre
  variable depart
  catch {::moderne::premove::annuler}
  if {![::moderne::actif] || ![winfo exists $w.fclocks]} { return }
  polices
  set ::moderne::jeu::fini 0
  # the game only stops when the window itself is closed (not
  # when one of its elements is redrawn)
  if {![info exists ::moderne::pendule::gardeDestroy($w)]} {
    set ::moderne::pendule::gardeDestroy($w) 1
    bind $w <Destroy> [list ::moderne::pendule::surDestroy $w %W [bind $w <Destroy>]]
  }
  pack forget $w.fclocks $w.fbuttons
  catch {$w configure -background $coul(fond)}
  set p $w.lich
  catch {destroy $p}
  frame $p -background $coul(fond)
  pack $p -side left -fill y -anchor nw -padx {6 0}
  # starting position (for the rematch)
  set depart {}
  catch {
    set loc [sc_pos location]
    sc_move start ; set depart [sc_pos fen] ; sc_move ply $loc
  }
  # At the top: the color at the top of the board
  set haut [expr {[::board::isFlipped .main.board] ? 1 : 2}]
  set bas [expr {3 - $haut}]
  set ordre [list $haut $bas]
  frame $p.vh -height 1 -background $coul(fond)
  pack $p.vh -side top -fill x
  pendule $p.ph $haut
  pack $p.ph -side top -anchor w
  nom $p.nh $haut
  pack $p.nh -side top -fill x
  # at the bottom (from the bottom up)
  frame $p.vb -height 1 -background $coul(fond)
  pack $p.vb -side bottom -fill x
  pendule $p.pb $bas
  pack $p.pb -side bottom -anchor w
  nom $p.nb $bas
  pack $p.nb -side bottom -fill x
  # in the middle: controls, moves, game end
  set c $p.cmd
  frame $c -background $coul(case)
  pack $c -side bottom -fill x
  foreach {b txt cmd} [list \
      reprendre "▶  [T Continuer Resume]" {.serGameWin.fbuttons.resume invoke} \
      annuler "↶  [T "Reprendre le coup" Takeback]" ::moderne::jeu::reprendreCoup \
      abandon "⚑  [T Abandonner Resign]" ::moderne::jeu::abandonner \
      quitter "✕  [T Quitter Quit]" ::sergame::abortGame] {
    bouton $c.$b $txt $cmd
    pack $c.$b -side left -fill x -expand 1
  }
  pack forget $c.reprendre
  set f $p.fin
  frame $f -background $coul(case)
  label $f.res -font font_JeuResultat -background $coul(case) -foreground $coul(texte)
  label $f.raison -font font_JeuRaison -background $coul(case) -foreground $coul(texte) -wraplength 320
  # two rematches (Yosha 2026-11-03): colours swapped (as on Lichess) or
  # the same colours
  frame $f.rev -background $coul(case)
  bouton $f.revanche [T REVANCHE REMATCH] {::moderne::jeu::finClic ::moderne::jeu::revanche} font_JeuRevanche $coul(bouton)
  bouton $f.rejouer [T REJOUER "PLAY AGAIN"] {::moderne::jeu::finClic {::moderne::jeu::revanche 0}} font_JeuRevanche $coul(bouton)
  catch {::utils::tooltip::Set $f.revanche [T "Nouvelle partie, couleurs inversées" "New game, colours swapped"]}
  catch {::utils::tooltip::Set $f.rejouer [T "Nouvelle partie, mêmes couleurs" "New game, same colours"]}
  bouton $f.nouveau [T "NOUVEL ADVERSAIRE" "NEW OPPONENT"] {::moderne::jeu::finClic ::moderne::jeu::nouvelAdversaire}
  bouton $f.analyse [T "ÉCHIQUIER D'ANALYSE" "ANALYSIS BOARD"] {::moderne::jeu::finClic ::moderne::jeu::echiquierAnalyse}
  bouton $f.annoter [T "BILAN DE LA PARTIE" "GAME REVIEW"] {::moderne::jeu::finClic ::moderne::jeu::annoter}
  pack $f.res -side top -pady {10 2}
  pack $f.raison -side top -pady {0 10} -padx 8
  pack $f.rev -side top -fill x -padx 12
  grid $f.revanche $f.rejouer -in $f.rev -sticky ew -ipady 14
  grid configure $f.rejouer -padx {6 0}
  grid columnconfigure $f.rev {0 1} -weight 1 -uniform rev
  pack $f.nouveau $f.analyse $f.annoter -side top -fill x -padx 12 -pady {6 0} -ipady 4
  frame $f.marge -height 10 -background $coul(case)
  pack $f.marge -side top
  set t $p.coups
  frame $t -background $coul(case) -width 320 -height 100
  grid propagate $t 0
  grid columnconfigure $t 0 -minsize 44
  grid columnconfigure $t {1 2} -weight 1 -uniform coups
  pack $t -side top -fill both -expand 1
  set ::moderne::pendule::coupsAffiches {}
  # the panel follows the board's height
  bind $p <Configure> [list ::moderne::pendule::aligner $w]
  majTout $w
  after 300 [list ::moderne::pendule::aligner $w]
}

### <Destroy> of the game window: only for the window itself
proc ::moderne::pendule::surDestroy {w W script} {
  if {$W ne $w} { return }
  unset -nocomplain ::moderne::pendule::gardeDestroy($w)
  uplevel #0 [string map [list %W $W] $script]
}

proc ::moderne::pendule::bouton {b txt cmd {police font_JeuBouton} {fond {}}} {
  variable coul
  if {$fond eq {}} { set fond $coul(case) }
  label $b -text $txt -font $police -background $fond -foreground $coul(texte) -cursor hand2 -pady 6
  bind $b <Enter> [list $b configure -background $coul(survol) -foreground #ffffff]
  bind $b <Leave> [list $b configure -background $fond -foreground $coul(texte)]
  bind $b <ButtonRelease-1> [list after idle $cmd]
}

proc ::moderne::pendule::pendule {f n} {
  variable coul
  frame $f -background $coul(case)
  label $f.t -text 00:00 -font font_Pendule -anchor w -padx 14 -pady 2 \
      -background $coul(case) -foreground $coul(texte)
  label $f.d -text {} -font font_PenduleDixiemes -anchor sw -padx 0 -pady 4 \
      -background $coul(case) -foreground $coul(texte)
  pack $f.t -side left
  pack $f.d -side left -fill y -padx {0 14}
}

proc ::moderne::pendule::nom {f n} {
  variable coul
  frame $f -background $coul(case)
  set nom [expr {$n == 1 ? [sc_game tags get White] : [sc_game tags get Black]}]
  if {$nom in {{} ?}} { set nom [expr {$n == 1 ? [T Blancs White] : [T Noirs Black]}] }
  # (an Alter Ego: the real player's photo and title, "Carlsen · Alter Ego
  # 2013", Yosha 2026-11-09)
  set ae {}
  catch {set ae [::moderne::alterego::joueur [expr {$n == 1 ? "White" : "Black"}]]}
  set titre {}
  if {$ae ne {}} {
    set nom [lindex $ae 1]
    catch {set titre [::moderne::avatars::titreFide [lindex $ae 0]]}
    if {$titre in {WC WWC}} { set titre {} }
  }
  label $f.pt -text "●" -font font_JeuNom -background $coul(case) -foreground $coul(point)
  pack $f.pt -side left -padx {10 4} -pady 6
  if {$ae ne {} && ![catch {::moderne::avatars::photo [lindex $ae 0] 32} ph] && $ph ne {}} {
    catch {
      ::moderne::avatars::creer $f.av 32
      ::moderne::avatars::maj $f.av [lindex $ae 0] $titre 32
      pack $f.av -side left -padx {0 6} -pady 4
    }
  }
  if {$titre ne {}} {
    label $f.ti -text $titre -font font_JeuNom -background $coul(case) -foreground #d59020
    pack $f.ti -side left -padx {0 6}
  }
  label $f.n -text $nom -font font_JeuNom -anchor w -background $coul(case) -foreground $coul(texte)
  pack $f.n -side left -fill x
}

### The top of the upper clock level with the top of the board, the bottom
### of the lower one level with the bottom of the board (like Lichess)
proc ::moderne::pendule::aligner {w} {
  set p $w.lich
  if {![winfo exists $p] || ![winfo exists .main.board.bd]} { return }
  set bd .main.board.bd
  set cote [expr {8 * ($::board::_size(.main.board) + $::board::_border(.main.board))}]
  set haut [expr {[winfo rooty $bd] - [winfo rooty $p]}]
  set bas [expr {[winfo rooty $p] + [winfo height $p] - [winfo rooty $bd] - $cote}]
  if {$haut < 1 || $haut > 400} { set haut 1 }
  if {$bas < 1 || $bas > 400} { set bas 1 }
  if {[$p.vh cget -height] != $haut} { $p.vh configure -height $haut }
  if {[$p.vb cget -height] != $bas} { $p.vb configure -height $bas }
}

### Remaining time (seconds, with decimals) of clock n
proc ::moderne::pendule::reste {n} {
  if {[info exists ::moderne::horloge::ms($n)]} {
    set ms $::moderne::horloge::ms($n)
    if {$::gameclock::data(running$n) && [info exists ::moderne::horloge::t0($n)]} {
      set ms [expr {$ms + [clock milliseconds] - $::moderne::horloge::t0($n)}]
    }
    return [expr {-$ms / 1000.0}]
  }
  set c 0
  catch {set c $::gameclock::data(counter$n)}
  return [expr {-$c}]
}

### "03:00", "1:02:03"; under 10 s: "00:09" + ".8"
proc ::moderne::pendule::texteJeu {sec} {
  set neg [expr {$sec < 0}]
  set sec [expr {abs($sec)}]
  set e [expr {int($sec)}]
  set h [expr {$e / 3600}]
  set m [expr {($e % 3600) / 60}]
  set s [expr {$e % 60}]
  if {$h > 0} { return [list [format "%d:%02d:%02d" $h $m $s] {}] }
  set dix {}
  if {$sec < 10 && !$neg} { set dix ".[expr {int($sec * 10) % 10}]" }
  return [list [format "%02d:%02d" $m $s] $dix]
}

proc ::moderne::pendule::majTout {w} {
  variable ordre
  variable coul
  set p $w.lich
  if {![winfo exists $p]} { return }
  set fini [expr {$::sergame::timeMode eq "timebonus"}]
  foreach pos {h b} n $ordre {
    set f $p.p$pos
    set marche 0
    catch {set marche $::gameclock::data(running$n)}
    set r [reste $n]
    # (the side whose flag fell: 00:00, whatever was added after)
    if {[info exists ::moderne::horloge::tombe($n)]} { set r 0 }
    if {$fini} {
      lassign [texteJeu [expr {max(0, $r)}]] txt dix
    } else {
      # time per move: the counter goes up from 0
      lassign [texteJeu [expr {-$r}]] txt dix
      set dix {}
    }
    if {$fini && $r <= 0} {
      set fond $coul(tombe) ; set texte #ffffff
    } elseif {$marche && $fini && $r < 10} {
      set fond $coul(urgence) ; set texte #ffffff
    } elseif {$marche} {
      set fond $coul(marche) ; set texte #ffffff
    } else {
      set fond $coul(case) ; set texte $coul(doux)
    }
    foreach x [list $f $f.t $f.d] { $x configure -background $fond }
    $f.t configure -text $txt -foreground $texte
    $f.d configure -text $dix -foreground $texte
    # flag fell: end of the game
    if {$fini && $marche && $r <= 0} { ::moderne::horloge::tombee $n }
  }
  # "Resume" button (game paused) and moves
  catch {
    if {$::pause && !$::moderne::jeu::fini} {
      if {![winfo ismapped $p.cmd.reprendre]} { pack $p.cmd.reprendre -side left -fill x -expand 1 -before $p.cmd.abandon }
    } elseif {[winfo ismapped $p.cmd.reprendre]} {
      pack forget $p.cmd.reprendre
    }
  }
  catch {majCoups $p.coups}
  after 100 [list ::moderne::pendule::majTout $w]
}

### Move in figurines (♘f3) if a font contains them
proc ::moderne::pendule::figurine {san} {
  variable figurines
  set l [string index $san 0]
  # (letters when the notation uses letters, as everywhere)
  if {$::moderne::notation ne "figurines"} { return [list [::moderne::coupTexte $san] {}] }
  if {$figurines eq {} || $l ni {K Q R B N}} { return [list $san {}] }
  set u [dict get {K ♔ Q ♕ R ♖ B ♗ N ♘} $l]
  return [list $u [string range $san 1 end]]
}

proc ::moderne::pendule::lignesCoups {} {
  set lignes {}
  set num 0 ; set b {} ; set n {} ; set ouvert 0
  foreach tok [sc_game moves] {
    if {[regexp {^(\d+)\.(\.\.)?(.*)$} $tok -> k points reste]} {
      if {$ouvert} { lappend lignes [list $num $b $n] }
      set num $k ; set b {} ; set n {} ; set ouvert 1
      if {$points ne {}} { set b "…" }
      set tok $reste
      if {$tok eq {}} { continue }
    }
    if {![regexp {^[a-hKQRBNO]} $tok]} { continue }
    if {$b eq {}} { set b $tok } else { set n $tok }
  }
  if {$ouvert} { lappend lignes [list $num $b $n] }
  return $lignes
}

### Move list (like Lichess): number, white move, black move; the
### last move highlighted; the last lines that fit
proc ::moderne::pendule::majCoups {t} {
  variable coupsAffiches
  variable coul
  set lignes [lignesCoups]
  set h [winfo height $t]
  set cle [list $lignes $h]
  if {$cle eq $coupsAffiches} { return }
  set coupsAffiches $cle
  foreach c [winfo children $t] { destroy $c }
  set police [expr {"font_JeuFigurine" in [font names] ? "font_JeuFigurine" : "font_JeuCoups"}]
  set hl [expr {[font metrics $police -linespace] + 12}]
  set max [expr {max(1, $h / $hl)}]
  set debut [expr {max(0, [llength $lignes] - $max)}]
  set r 0
  set derniere [expr {[llength $lignes] - 1}]
  foreach l [lrange $lignes $debut end] {
    lassign $l num b n
    set i [expr {$debut + $r}]
    label $t.k$r -text $num -font font_JeuCoups -width 3 -anchor center \
        -background $coul(num) -foreground $coul(doux)
    grid $t.k$r -row $r -column 0 -sticky nsew
    set col 1
    foreach coup [list $b $n] cote {b n} {
      set courant [expr {$i == $derniere && (($cote eq "n" && $n ne {}) || ($cote eq "b" && $n eq {}))}]
      lassign [figurine $coup] f reste
      label $t.$cote$r -text "$f$reste" -font $police -anchor w -padx 10 -pady 6 \
          -background [expr {$courant ? $coul(courant) : $coul(case)}] \
          -foreground [expr {$courant ? "#ffffff" : $coul(texte)}]
      grid $t.$cote$r -row $r -column $col -sticky nsew
      incr col
    }
    incr r
  }
}


###
### Clocks to the tenth of a second during a game against an engine: the
### SCID countdown (one second at a time, the fraction lost on each
### move) is replaced by a countdown in milliseconds.
###

namespace eval ::moderne::horloge {
  variable ms   ;# counter (ms) of each clock: negative = time remaining
  variable t0   ;# time of the last start
}

proc ::moderne::horloge::actif {} {
  expr {[::moderne::actif] && [winfo exists .serGameWin]}
}

proc ::moderne::horloge::synchro {n} {
  variable ms
  # SCID integer counter (sent to the engine): toward zero
  set ::gameclock::data(counter$n) [expr {int($ms($n) / 1000.0)}]
}

proc ::moderne::horloge::installer {} {
  if {[llength [info commands ::gameclock::start_origine]]} { return }
  foreach c {start stop add setSec reset} { rename ::gameclock::$c ::gameclock::${c}_origine }
  proc ::gameclock::setSec {n value} {
    if {[::moderne::horloge::actif]} {
      set ::moderne::horloge::ms($n) [expr {$value * 1000}]
    } else {
      catch {unset ::moderne::horloge::ms($n)}
    }
    ::gameclock::setSec_origine $n [expr {int($value)}]
  }
  proc ::gameclock::reset {n} {
    ::gameclock::reset_origine $n
    catch {unset ::moderne::horloge::ms($n)}
    catch {unset ::moderne::horloge::t0($n)}
    catch {unset ::moderne::horloge::tombe($n)}
    # (start of a game: ply from which the clocks run, see start)
    set ::moderne::horloge::plyDepart [sc_pos location]
  }
  proc ::gameclock::add {n value} {
    # (no increment once the flag has fallen: a move played after the time
    # was out gave its 2 s back, and the game ended on time with « 00:00.8 »
    # on the clock, Yosha 2026-11-14)
    if {[::moderne::horloge::tombee $n]} { return }
    if {[info exists ::moderne::horloge::ms($n)]} {
      set ::moderne::horloge::ms($n) [expr {$::moderne::horloge::ms($n) - $value * 1000}]
      ::moderne::horloge::synchro $n
      return
    }
    # (the game just ended, its clock gone: an engine move still on its way)
    if {![info exists ::gameclock::data(counter$n)]} { return }
    ::gameclock::add_origine $n $value
  }
  proc ::gameclock::start {n} {
    if {![::moderne::horloge::actif]} { return [::gameclock::start_origine $n] }
    # like Lichess: the clocks only run once each side has made a move
    if {[winfo exists .serGameWin] && [info exists ::moderne::horloge::plyDepart] &&
        [sc_pos location] < $::moderne::horloge::plyDepart + 2} { return }
    if {$::gameclock::data(running$n)} { return }
    if {![info exists ::moderne::horloge::ms($n)]} {
      set ::moderne::horloge::ms($n) [expr {$::gameclock::data(counter$n) * 1000}]
    }
    set ::gameclock::data(running$n) 1
    set ::gameclock::data(prevcounter$n) $::gameclock::data(counter$n)
    set ::moderne::horloge::t0($n) [clock milliseconds]
    set ::gameclock::after$n [after 100 [list ::moderne::horloge::tic $n]]
  }
  proc ::gameclock::stop {n} {
    if {![info exists ::moderne::horloge::t0($n)]} { return [::gameclock::stop_origine $n] }
    if {!$::gameclock::data(running$n)} { return -1 }
    set ::gameclock::data(running$n) 0
    catch {after cancel [set ::gameclock::after$n]}
    set ecoule [expr {[clock milliseconds] - $::moderne::horloge::t0($n)}]
    unset ::moderne::horloge::t0($n)
    set ::moderne::horloge::ms($n) [expr {$::moderne::horloge::ms($n) + $ecoule}]
    ::moderne::horloge::synchro $n
    # (out of time when the move is played: lost then, not at the clock's
    # next refresh)
    ::moderne::horloge::tombee $n
    set ::gameclock::data(prevcounter$n) $::gameclock::data(counter$n)
    return [expr {int(round($ecoule / 1000.0))}]
  }
}

### Side n's flag fallen (time control with increment, time out, the game
### not over yet: its end is asked for once)? Kept until the clock is reset
proc ::moderne::horloge::tombee {n} {
  variable tombe
  if {[info exists tombe($n)]} { return 1 }
  if {![info exists ::sergame::timeMode] || $::sergame::timeMode ne "timebonus"} { return 0 }
  if {![info exists ::moderne::horloge::ms($n)] || $::moderne::jeu::fini} { return 0 }
  if {[::moderne::pendule::reste $n] > 0} { return 0 }
  set tombe($n) 1
  after idle [list ::moderne::jeu::fin [expr {$n == 1 ? 0 : 1}] temps]
  return 1
}

### The clock of the side that just moved, kept in the game after its
### move: [%clk h:mm:ss] as in Lichess games (shown under the moves and
### read by the review; Yosha 2026-11-09)
proc ::moderne::horloge::noterClk {} {
  variable ms
  if {![actif]} { return }
  set n [expr {[sc_pos side] eq "white" ? 2 : 1}]
  if {[info exists ms($n)]} {
    set reste [expr {-$ms($n) / 1000.0}]
  } elseif {[info exists ::gameclock::data(counter$n)]} {
    set reste [expr {-$::gameclock::data(counter$n)}]
  } else {
    return
  }
  if {$reste < 0} { set reste 0 }
  set s [expr {int(round($reste))}]
  set clk [format {[%%clk %d:%02d:%02d]} [expr {$s / 3600}] [expr {($s / 60) % 60}] [expr {$s % 60}]]
  set c [string trim [regsub -all {\[%clk [^\]]*\]} [sc_pos getComment] {}]]
  sc_pos setComment [string trim "$clk $c"]
}

proc ::moderne::horloge::tic {n} {
  variable ms
  variable t0
  if {![info exists t0($n)] || !$::gameclock::data(running$n)} { return }
  set c [expr {$ms($n) + [clock milliseconds] - $t0($n)}]
  set ::gameclock::data(counter$n) [expr {int($c / 1000.0)}]
  set ::gameclock::after$n [after 100 [list ::moderne::horloge::tic $n]]
}

::moderne::horloge::installer

###
### Game end (like Lichess): no more "Player wins" box; in the
### panel, the result, the reason, and Rematch / New opponent /
### Analysis board / Annotate the game
###

namespace eval ::moderne::jeu {
  variable fini 0
}

proc ::moderne::jeu::T {fr en} { return [::moderne::tr $fr $en] }

proc ::moderne::jeu::actif {} {
  expr {[::moderne::actif] && [winfo exists .serGameWin.lich]}
}

### Game over: moves are no longer played on the board
proc ::moderne::jeu::bloque {} {
  variable fini
  expr {[actif] && $fini}
}

### resultat: 1 (White wins), 0 (Black), = (draw)
### raison: mat pat temps abandon repetition 50coups materiel tempsNul
proc ::moderne::jeu::fin {resultat raison} {
  variable fini
  if {![actif] || $fini} { return 0 }
  set fini 1
  catch {::moderne::alterego::arreter 1}
  catch {::moderne::toby::ombre::arreter}
  catch {::moderne::premove::annuler}
  catch {::gameclock::stop 1}
  catch {::gameclock::stop 2}
  after cancel ::sergame::engineGo
  # (the review's preparation runs again, to the last move, then is saved:
  # the review can be opened later)
  catch {::moderne::bilan::prepa::finPartie}
  catch {set ::moderne::niveau::pause 0 ; ::moderne::niveau::suivant}
  # the engine may be thinking: stop it
  catch {
    set n $::sergame::engine
    ::sergame::sendToEngine $n stop
    set ::uci::uciInfo(bestmove$n) abort
  }
  # (time out against a side that cannot mate: a draw, as on Lichess)
  if {$raison eq "temps" && ![catch {::sibyPeutMater [expr {$resultat eq "1" ? "white" : "black"}]} m] && !$m} {
    set perdantCote [expr {$resultat eq "1" ? "black" : "white"}]
    set resultat =
    set raison tempsNul
  }
  sc_game tags set -result $resultat
  # (the end of the game heard, as on Lichess: victory, defeat or draw for
  # the player)
  catch {
    set moi [expr {$::moderne::toby::jeu(couleur) eq "black" ? "0" : "1"}]
    ::moderne::sons::jouer [expr {$resultat eq "=" ? "nulle" : ($resultat eq $moi ? "victoire" : "defaite")}]
  }
  set blancs [T "les blancs" white]
  set noirs [T "les noirs" black]
  set perdant [expr {$resultat eq "1" ? $noirs : $blancs}]
  if {[info exists perdantCote]} { set perdant [expr {$perdantCote eq "black" ? $noirs : $blancs}] }
  set gagnant [expr {$resultat eq "1" ? [T "Victoire des Blancs" "White is victorious"] : [T "Victoire des Noirs" "Black is victorious"]}]
  switch -- $raison {
    mat        { set txt "[T {Échec et mat} Checkmate] • $gagnant" }
    pat        { set txt "[T Pat Stalemate] • [T {Partie nulle} Draw]" }
    temps      { set txt "[string totitle $perdant 0 0] [T {sont tombés au temps} {time out}] • $gagnant" }
    abandon    { set txt "[string totitle $perdant 0 0] [T abandonnent resigned] • $gagnant" }
    repetition { set txt "[T {Triple répétition} {Threefold repetition}] • [T {Partie nulle} Draw]" }
    50coups    { set txt "[T {Règle des 50 coups} {Fifty moves}] • [T {Partie nulle} Draw]" }
    materiel   { set txt "[T {Matériel insuffisant} {Insufficient material}] • [T {Partie nulle} Draw]" }
    tempsNul   { set txt "[string totitle $perdant 0 0] [T {sont tombés au temps} {time out}] • [T {Partie nulle} Draw]" }
    default    { set txt $gagnant }
  }
  set res [dict get {1 1-0 0 0-1 = ½-½} $resultat]
  set f .serGameWin.lich.fin
  $f.res configure -text $res
  $f.raison configure -text $txt
  pack forget .serGameWin.lich.cmd
  pack $f -side bottom -fill x -before .serGameWin.lich.coups
  # (the end buttons take the place of Resign: a double click on Resign
  # must not start the review at once; clicks are ignored for a moment)
  variable finDepuis [clock milliseconds]
  # (mate and stalemate: the game is saved by sergame)
  if {$raison ni {mat pat}} { catch {::moderne::jeu::enregistrer} }
  updateBoard -pgn
  return 1
}

### A button of the game's end: ignored during the first 0.4 s after it
### appeared (a double click on Resign launched the review)
proc ::moderne::jeu::finClic {cmd} {
  variable finDepuis
  if {[info exists finDepuis] && [clock milliseconds] - $finDepuis < 400} { return }
  uplevel #0 $cmd
}

### Saves a finished game against an engine (Stockfish, Toby, Alter Ego) in
### a dedicated database, "Siby games" in the settings folder (created on
### first use), never in the open database: that one is often the large
### reference database (or a PGN file), which a game would pollute and whose
### opening library, position index and ratings would have to be rebuilt.
proc ::moderne::jeu::enregistrer {} {
  if {![::moderne::actif]} { return [::game::Save] }
  set pgn [::moderne::pgnAnglais]
  set courante [sc_base current]
  set fichier [file normalize [file join $::sibyDocsDir "Siby games"]]
  set b -1
  for {set i 1} {$i <= [sc_base count total]} {incr i} {
    if {[sc_base inUse $i] && [file normalize [sc_base filename $i]] eq $fichier} { set b $i ; break }
  }
  if {$b < 0} {
    if {[file exists $fichier.si4]} {
      set b [sc_base open $fichier]
    } else {
      set b [sc_base create $fichier]
    }
  }
  sc_base switch $b
  set code [catch {
    sc_game new
    sc_game import $pgn
    sc_game save 0
  } err]
  sc_base switch $courante
  # (kept in Siby games: the game on the board no longer counts as altered;
  # the rematch asked "This game has been altered, save it?" and Save put it
  # in the open database too, a PGN file, Yosha 2026-11-04)
  if {!$code} { catch {sc_game setaltered 0} }
  catch {::windows::switcher::Refresh}
  catch {::windows::gamelist::Refresh}
  if {$code} { error $err }
  return $b
}

### End by mate or stalemate (sergame::checkEndOfGame)
proc ::moderne::jeu::finMatPat {} {
  if {![sc_pos isCheck]} { return [fin = pat] }
  return [fin [expr {[sc_pos side] eq "black" ? 1 : 0}] mat]
}

### Takeback (as against the computer on Lichess, Yosha 2026-11-11): on
### the player's turn, their last move and the engine's answer are taken
### back; the clocks go on. The review prepared during the game starts
### again at the end (its moves changed).
proc ::moderne::jeu::reprendreCoup {} {
  variable fini
  if {![actif] || $fini} { return }
  # (the engine thinking: its move first)
  if {[sc_pos side] eq [::board::opponentColor]} { return }
  while {[sc_var level] > 0} { sc_var exit }
  sc_move end
  # (location: plies from the start; the player's move and the engine's
  # answer, 2 plies, needed)
  set loc [sc_pos location]
  if {$loc < 2} { return }
  sc_move back 2
  sc_game truncate
  catch {set ::uci::uciInfo(prevscore$::sergame::engine) {}}
  # (an Alter Ego back in its repertoire)
  catch {set ::moderne::alterego::sorti 0}
  catch {::moderne::bilan::prepa::oublier}
  updateBoard -pgn
}

### A game against an engine over but still on screen: closed, then cmd run
### once its layout has given the Lab back (its engines, the board's way);
### 1 if so, the caller then stops (Yosha 2026-11-11: the broadcasts opened
### over a finished game had no engines and an upside-down board). As on
### Lichess, leaving a finished game closes it.
proc ::moderne::jeu::fermerSiFinie {cmd} {
  variable fini
  if {![winfo exists .serGameWin] || ![info exists fini] || !$fini} { return 0 }
  catch {::sergame::abortGame}
  after 1200 $cmd
  return 1
}

proc ::moderne::jeu::abandonner {} {
  if {![actif]} { return }
  fin [expr {[::board::opponentColor] eq "white" ? 1 : 0}] abandon
}

### Rematch: colors swapped (inverser 0: the same colours), same start,
### same time control
proc ::moderne::jeu::revanche {{inverser 1}} {
  set n $::sergame::engine
  # (the clock not started yet, a game ended at once: the usual start)
  set depart {}
  catch {set depart $::moderne::pendule::depart}
  set toby [expr {![catch {::moderne::toby::estToby $n} t] && $t}]
  set ae [expr {([info exists ::moderne::alterego::actif] && $::moderne::alterego::actif) ||
                ([info exists ::moderne::alterego::dernier] && $::moderne::alterego::dernier)}]
  # (the playing layout stays as it is: neither the layout of before the
  # game nor the playing one built again; the one of before the game comes
  # back after the last game)
  set ::moderne::disposition::revanche 1
  after 10000 {set ::moderne::disposition::revanche 0}
  ::sergame::abortGame
  if {$ae} {
    # the same Alter Ego (same period, level, time control), colours swapped
    if {$inverser} {
      set ::moderne::alterego::form(couleur) [expr {$::moderne::alterego::form(couleur) eq "white" ? "black" : "white"}]
    }
    if {$depart ne {} && $depart ne $::defaultFen} {
      catch {sc_move start}
      if {[sc_pos fen] ne $depart} { catch {setTrialMode 0 ; sc_game new ; sc_game startBoard $depart} }
      set ::moderne::alterego::form(depart) actuelle
    } else {
      set ::moderne::alterego::form(depart) initiale
    }
    after idle ::moderne::alterego::lancer
  } elseif {$toby} {
    if {$inverser} {
      set ::moderne::toby::jeu(couleur) [expr {$::moderne::toby::jeu(couleur) eq "white" ? "black" : "white"}]
    }
    if {$depart ne {} && $depart ne $::defaultFen} {
      catch {sc_move start}
      if {[sc_pos fen] ne $depart} { catch {setTrialMode 0 ; sc_game new ; sc_game startBoard $depart} }
      set ::moderne::toby::jeu(depart) actuelle
    } else {
      set ::moderne::toby::jeu(depart) initiale
    }
    after idle ::moderne::toby::jeuLancer
  } else {
    if {$inverser} { ::board::flip .main.board }
    if {$depart ne {} && $depart ne $::defaultFen} {
      # the same starting position, the same side to move (Yosha
      # 2026-11-03): a new game from it (sergame only sets the headers of a
      # game from the start)
      catch {setTrialMode 0}
      sc_game new
      catch {sc_game startBoard $depart}
      set ::sergame::startFromCurrent 1
      set moi [getMyPlayerName]
      if {$moi eq {}} { set moi ? }
      set noirs [::board::isFlipped .main.board]
      sc_game tags set -event "UCI Game" -date [::utils::date::today] \
          -white [expr {$noirs ? $::sergame::engineName : $moi}] -black [expr {$noirs ? $moi : $::sergame::engineName}]
    } else {
      set ::sergame::startFromCurrent 0
    }
    after idle [list ::sergame::play $n]
  }
}

proc ::moderne::jeu::nouvelAdversaire {} {
  set n $::sergame::engine
  set toby [expr {![catch {::moderne::toby::estToby $n} t] && $t}]
  ::sergame::abortGame
  if {$toby} { after idle ::moderne::toby::jeuFenetre } else { after idle ::sergame::config }
}

proc ::moderne::jeu::echiquierAnalyse {} {
  ::sergame::abortGame
  # (the layout of before the game does not come back meanwhile)
  catch ::moderne::disposition::jeuApresAnnuler
  after idle ::moderne::disposition::analyse
}

### Analysis board, and the game review at once (symbols, variations,
### level of play: bilan.tcl). The positions Toby analyzed during the game
### are judged by Toby, the others by Stockfish + Maia.
proc ::moderne::jeu::annoter {} {
  ::sergame::abortGame
  # (the layout of before the game does not come back meanwhile: it would
  # be rebuilt over the analysis board and the review)
  catch ::moderne::disposition::jeuApresAnnuler
  after idle {
    ::moderne::disposition::analyse
    after 300 ::moderne::jeu::bilanQuandPret
  }
}

### The review once the layout is built (its windows made, veil gone)
proc ::moderne::jeu::bilanQuandPret {{essais 0}} {
  set pret [expr {![winfo exists .voileDisposition] && ![llength $::docking::differees]
                  && !([info exists ::docking::enConstruction] && $::docking::enConstruction)}]
  if {!$pret && $essais < 50} {
    after 100 [list ::moderne::jeu::bilanQuandPret [incr essais]]
    return
  }
  ::moderne::bilan::lancer
}

###
### Premove (like Lichess) during a game against an engine: a move
### played while the engine is thinking is kept (its two squares tinted)
### and played as soon as the engine has replied, if it is then legal. A new
### move replaces the previous one; right-click on the board: canceled.
###

namespace eval ::moderne::premove {
  variable coup {}
}
image create photo Teinte_premove -format png -data {iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGMQkQvtAQAB5QEUGLaRFAAAAABJRU5ErkJggg==}

proc ::moderne::premove::actif {} {
  expr {[::moderne::actif] && [winfo exists .serGameWin] && [info exists ::sergame::engine]}
}

### The user's color (w or b): the engine plays at the top of the board
proc ::moderne::premove::moi {} {
  expr {[::board::opponentColor] eq "white" ? "b" : "w"}
}

### During the engine's turn: one's own pieces can be picked up (and dragged)
proc ::moderne::premove::piece {p} {
  expr {[actif] && [sc_pos side] eq [::board::opponentColor] && $p eq [moi]}
}

### Called at the start of addMove: 1 if the move is kept as a premove
proc ::moderne::premove::intercepter {sq1 sq2} {
  variable coup
  if {![actif] || $sq1 eq "null" || $sq2 eq "null"} { return 0 }
  if {[sc_pos side] ne [::board::opponentColor] || ![sc_pos isAt vend]} { return 0 }
  # from-square (sq2): a piece of the user's
  if {[string index [::board::piece .main.board $sq2] 0] ne [moi]} {
    annuler
    return 1
  }
  set coup [list $sq1 $sq2]
  # right-click on the board: premove canceled (like Lichess)
  if {[string first premove [bind .main.board.bd <ButtonPress-3>]] < 0} {
    bind .main.board.bd <ButtonPress-3> {+::moderne::premove::annuler}
  }
  dessiner
  return 1
}

proc ::moderne::premove::dessiner {args} {
  variable coup
  set w .main.board
  if {![winfo exists $w.bd]} { return }
  $w.bd delete premove
  if {![actif]} { set coup {} ; return }
  foreach sq $coup { catch {::moderne::echiquier::teinte $w $sq premove premove} }
}

proc ::moderne::premove::annuler {} {
  variable coup
  set coup {}
  catch {.main.board.bd delete premove}
}

### Called when the engine has moved: plays the premove if it is legal
proc ::moderne::premove::jouer {} {
  variable coup
  if {![llength $coup]} { return 0 }
  lassign $coup sq1 sq2
  annuler
  if {![actif] || [sc_pos side] eq [::board::opponentColor]} { return 0 }
  if {![sc_pos isLegal $sq1 $sq2]} { return 0 }
  # promotion as a premove: queen automatically (like Lichess)
  set ::moderne::prise::autoDame 1
  catch {addMove $sq1 $sq2 -animate}
  set ::moderne::prise::autoDame 0
  return 1
}

