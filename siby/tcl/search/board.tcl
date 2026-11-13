###
### search/board.tcl: Board (and Moves) Search routines for Scid.
###

set searchInVars 0
set sBoardIgnoreCols 0
set sBoardSearchType Exact
set checkTest 0
set sMoves {}

# ::search::board
#   Opens the search window for the current board position.
#
proc ::search::board {} {
  global glstart searchInVars sBoardType sBoardIgnoreCols refDatabase

  set w .sb
  if {[winfo exists $w]} {
    wm deiconify $w
    raiseWin $w
    return
  }

  toplevel $w
  wm withdraw $w
  wm title $w "$::tr(BoardSearch)"

  bind $w <Escape> "$w.b.cancel invoke"
  bind $w <Return> "$w.b.search invoke"
  bind $w <F1> { helpWindow Searches Board }

  label $w.type -textvar ::tr(SearchType) -font font_Bold
  pack $w.type -side top
  pack [frame $w.g] -side top -fill x
  radiobutton $w.g.exact -textvar ::tr(SearchBoardExact) \
      -variable sBoardSearchType -value Exact
  radiobutton $w.g.pawns -textvar ::tr(SearchBoardPawns) \
      -variable sBoardSearchType -value Pawns
  radiobutton $w.g.files -textvar ::tr(SearchBoardFiles) \
      -variable sBoardSearchType -value Fyles
  radiobutton $w.g.material -textvar ::tr(SearchBoardAny) \
      -variable sBoardSearchType -value Material
  set row 0
  foreach i {exact pawns files material} {
    grid $w.g.$i -row $row -column 0 -sticky w
    incr row
  }
  addHorizontalRule $w

  pack [frame $w.refdb] -side top -fill x
  checkbutton $w.refdb.cb -textvar ::tr(SearchInRefDatabase) -variable ::searchRefBase \
               -command "checkState ::searchRefBase $w.refdb.lb"

  set found -1
  ttk::combobox $w.refdb.lb -textvariable refDatabase -state readonly
  if {![info exists refDatabase]} {
    set refDatabase 0
  }

  # Add clipbase to possible bases
  set baseName [file tail [sc_base filename [sc_base count total]]]
  set ::listbases $baseName
  if {$baseName == $refDatabase} {set found 0}

  # and then the rest
  for {set i 1} {$i < [sc_base count total]} {incr i} {
    if {[sc_base inUse $i]} {
      set baseName [file tail [sc_base filename $i]]
      lappend ::listbases $baseName
      if {$baseName == $refDatabase} {set found $i}
    }
  }
  $w.refdb.lb configure -values $::listbases

  if {$found > -1} {
    if {[catch {
      $w.refdb.lb current $found
    }]} {
    # hmmm - still can throw error
    $w.refdb.lb current [expr {[llength $::listbases] - 1}]
    }
  } else {
    $w.refdb.lb current [expr {[llength $::listbases] - 1}]
  }

  checkState ::searchRefBase $w.refdb.lb

  pack $w.refdb.cb -side left
  pack $w.refdb.lb -side left -padx 20
  addHorizontalRule $w

  ::search::addFilterOpFrame $w
  addHorizontalRule $w

  ### Progress bar

  canvas $w.progress -height 20 -width 300  -relief solid -border 1
  $w.progress create rectangle 0 0 0 0 -fill $::progcolor -outline $::progcolor -tags bar
  $w.progress create text 295 10 -anchor e -font font_Regular -tags time \
      -fill black -text "0:00 / 0:00"

  frame $w.b2
  pack $w.b2 -side top
  frame $w.b
  checkbutton $w.b2.vars -textvar ::tr(LookInVars) -padx 10 -pady 5 \
      -onvalue 1 -offvalue 0 -variable searchInVars
  checkbutton $w.b2.flip -textvar ::tr(IgnoreColors) -padx 10 -pady 5 \
      -onvalue 1 -offvalue 0 -variable sBoardIgnoreCols

  dialogbutton $w.b.stop -textvar ::tr(Stop) -command sc_progressBar
  $w.b.stop configure -state disabled

  dialogbutton $w.b.search -textvar ::tr(Search) -command {
    busyCursor .
    .sb.b.stop configure -state normal
    grab .sb.b.stop
    sc_progressBar .sb.progress bar 301 21 time

    if { $::searchRefBase } {
      ### Search a particular base rather than the one that is open

      # Find the base number by searching the basenames for a match with combobox variable refDatabase
      set found 0
      set base  9 ; # this line not really needed
      for {set i 1} {$i <= [sc_base count total]} {incr i} {
	if {[sc_base inUse $i]} {
	  if {[file tail [sc_base filename $i]] == $::refDatabase} {
	    set base $i
	    set found 1
	    break
	  }
	}
      }

      if {$found} {
	set str [sc_search board $::search::filter::operation $sBoardSearchType $searchInVars $sBoardIgnoreCols $base]
      } else {
	set str {Database not open}
      }
    } else {
      set str [sc_search board $::search::filter::operation $sBoardSearchType $searchInVars $sBoardIgnoreCols ]
    }

    unbusyCursor .
    grab release .sb.b.stop
    .sb.b.stop configure -state disabled
    .sb.status configure -text $str
    set glstart 1

    set gamesFound [lindex $str 0]
    if { $::searchRefBase && $gamesFound > 0 && $gamesFound != {Database}} {
      ::file::SwitchToBase $base
      ::search::loadFirstGame
    }
    ::windows::stats::Refresh
  }

  dialogbutton $w.b.cancel -textvar ::tr(Close) -command "focus .main ; destroy $w"
  pack $w.b2.vars $w.b2.flip -side left -pady 2 -padx 5
  packbuttons right $w.b.cancel .sb.b.stop .sb.b.search
  label $w.status -text "" -width 1 -font font_Small -relief sunken -anchor w
  pack $w.status -side bottom -fill x
  # Siby: the search accelerator
  ttk::frame $w.accel
  ttk::label $w.accel.l -foreground [::moderne::c texteDoux]
  ttk::button $w.accel.b -command ::search::accel::creerDemande
  pack $w.accel.l -side left -padx 10
  pack $w.accel -side bottom -fill x -pady {0 4}
  pack $w.b -side bottom -fill x
  pack $w.progress -side bottom -pady 2
  ::search::accel::etat
  wm resizable $w 0 0
  standardShortcuts $w
  ::search::Config

  placeWinOverParent $w .
  wm state $w normal
  focus $w.b.search
}

proc ::search::moves {} {

  global glstart sSideToMove checkTest

  set w .smv
  if {[winfo exists $w]} {
    wm deiconify $w
    raiseWin $w
    return
  }

  toplevel $w
  wm withdraw $w
  wm title $w [::moderne::tr "Recherche par coups" "Move search"]

  bind $w <Escape> "$w.b.cancel invoke"
  bind $w <Return> "$w.b.search invoke"
  bind $w <F1> { helpWindow Searches Move }

  label $w.type -textvar ::tr(Moves) -font font_Bold
  pack $w.type -side top
  pack [frame $w.g] -side top -fill x
  pack [ttk::entry $w.g.moves -textvariable sMoves -width 40] -padx 10 -pady 4 -fill x
  # Siby: how to write the moves
  pack [ttk::label $w.g.aide -foreground [::moderne::c texteDoux] -justify left -text [::moderne::tr \
      "Par exemple : Bxh7+ Kxh7 Ng5+ (Blancs et Noirs en alternance ; lettres anglaises : K R Q B N P) • .Qg3 = un coup blanc • ...Qg3 = un coup noir\nBxh7 = une prise • B-h7 = pas une prise • Bh7 = avec ou sans prise\n? = n'importe quel coup • Nf3-g5 = case de départ précisée • RxNd4 = prend un cavalier en d4 • BxQ = prend la dame\nh8=N = promotion en cavalier • h8=/=Q = une sous-promotion • =N = en cavalier, sur n'importe quelle case (8=N : les Blancs, 1=N : les Noirs) • Ph8 = un pion en h8, avec ou sans prise • Bh7+ = échec exigé, Bh7# = mat" \
      "For example: Bxh7+ Kxh7 Ng5+ (White and Black in turn) • .Qg3 = a White move • ...Qg3 = a Black move\nBxh7 = a capture • B-h7 = not a capture • Bh7 = with or without capture\n? = any move • Nf3-g5 = starting square given • RxNd4 = takes a knight on d4 • BxQ = takes the queen\nh8=N = promotion to a knight • h8=/=Q = an underpromotion • =N = to a knight, on any square (8=N: White, 1=N: Black) • Ph8 = a pawn on h8, capturing or not • Bh7+ = check required, Bh7# = mate"]] -padx 10 -anchor w

  addHorizontalRule $w

  ### Siby: the order of the moves
  if {![info exists ::search::ordreCoups]} { set ::search::ordreCoups 0 }
  pack [frame $w.ordre] -side top -fill x -expand 1
  label $w.ordre.label -text [::moderne::tr "Ordre des coups" "Order of the moves"] -font font_Bold
  pack $w.ordre.label -side top
  pack [frame $w.ordre.radio] -side top
  foreach {v fr en bfr ben} {
    0 "Consécutifs" "Consecutive" "Les coups se suivent dans la partie, Blancs et Noirs en alternance. Deux coups blancs de suite : g3 ? Bg2" "The moves follow each other in the game, White and Black in turn. Two White moves in a row: g3 ? Bg2"
    1 "Dans cet ordre" "In this order" "Les coups sont joués dans cet ordre par le camp choisi, d'autres coups peuvent venir entre eux." "The moves are played in this order by the chosen side, other moves may come between them."
    2 "Dans n'importe quel ordre" "In any order" "Tous les coups sont joués dans la partie par le camp choisi, dans n'importe quel ordre." "All the moves are played in the game by the chosen side, in any order."
  } {
    radiobutton $w.ordre.radio.o$v -text [::moderne::tr $fr $en] -variable ::search::ordreCoups -value $v \
        -command ::search::movesCamp
    ::utils::tooltip::Set $w.ordre.radio.o$v [::moderne::tr $bfr $ben]
    pack $w.ordre.radio.o$v -side left -padx 10
  }
  # Siby: from the first to the last move, at most so many moves
  if {![info exists ::search::ecartMax]} { set ::search::ecartMax {} }
  pack [frame $w.ordre.ecart] -side top -pady {2 0}
  ttk::label $w.ordre.ecart.a -text [::moderne::tr "Du premier au dernier coup : au plus" "From the first to the last move: at most"]
  ttk::spinbox $w.ordre.ecart.n -from 1 -to 200 -width 4 -textvariable ::search::ecartMax
  ttk::label $w.ordre.ecart.b -text [::moderne::tr "coups" "moves"]
  pack $w.ordre.ecart.a $w.ordre.ecart.n $w.ordre.ecart.b -side left -padx 3
  foreach x {a n b} {
    ::utils::tooltip::Set $w.ordre.ecart.$x [::moderne::tr \
        "Par exemple 3 : g3 au 5e coup puis Bg2 au plus tard au 8e. Vide : sans limite." \
        "For example 3: g3 on move 5, then Bg2 on move 8 at the latest. Empty: no limit."]
  }

  addHorizontalRule $w

  ### Side to move
  pack [frame $w.ends] -side top -fill x -expand 1
  label $w.ends.label -font font_Bold
  pack $w.ends.label -side top
  pack [frame $w.ends.radio ] -side top
  radiobutton $w.ends.radio.white -textvar ::tr(White) -variable sSideToMove -value w
  radiobutton $w.ends.radio.black -textvar ::tr(Black) -variable sSideToMove -value b
  radiobutton $w.ends.radio.both -text [::moderne::tr "L'un ou l'autre" "Either"] -variable sSideToMove -value wb
  pack $w.ends.radio.white $w.ends.radio.black $w.ends.radio.both -side left -padx 15
  ::search::movesCamp

  addHorizontalRule $w

  ### Check test
  frame $w.mate ;# (Siby: automatic, from the "+" / "#" written)
  label $w.mate.label -text [::moderne::tr "Test d'échec" "Check Test"] -font font_Bold
  pack $w.mate.label -side top
  pack [frame $w.mate.radio ] -side top

  ### position.h: (These checks take time)
  # (should we do it automaticslly if '+' or '#' are in entry field ?
  # SAN_NO_CHECKTEST = 0, SAN_CHECKTEST  = 1, SAN_MATETEST = 2;
  radiobutton $w.mate.radio.no -textvar ::tr(No) -variable checkTest -value 0
  radiobutton $w.mate.radio.check -text [::moderne::tr Échec Check] -variable checkTest -value 1
  radiobutton $w.mate.radio.mate -text [::moderne::tr Mat Mate] -variable checkTest -value 2
  pack $w.mate.radio.no $w.mate.radio.check $w.mate.radio.mate -side left -padx 15


  ::search::addFilterOpFrame $w
  addHorizontalRule $w

  ### Progress bar

  canvas $w.progress -height 20 -width 300  -relief solid -border 1
  $w.progress create rectangle 0 0 0 0 -fill $::progcolor -outline $::progcolor -tags bar
  $w.progress create text 295 10 -anchor e -font font_Regular -tags time \
      -fill black -text "0:00 / 0:00"

  frame $w.b
  dialogbutton $w.b.stop -textvar ::tr(Stop) -command sc_progressBar
  $w.b.stop configure -state disabled

  dialogbutton $w.b.search -textvar ::tr(Search) -command {
    # Siby: French or English pieces, commas, move numbers, long notation;
    # the check test follows the "+" / "#" written
    set moves [::moderne::positions::coupsNormalises [.smv.g.moves get]]
    set checkTest [::moderne::positions::testEchec $moves]
    set ::search::erreurCoups {}
    set inconnue [::moderne::positions::pieceInconnue [.smv.g.moves get]]
    if {$inconnue ne {}} {
      lassign $inconnue l m
      set str [::moderne::tr "Pièce non reconnue : $l ($m)" "Piece not recognized: $l ($m)"]
      set ::search::erreurCoups $str
    } elseif {$moves == {}} {
      set str [::moderne::tr "Aucun coup" "No move"]
      set ::search::erreurCoups $str
    } elseif {[lindex [set camp [::moderne::positions::campDesCoups $::search::ordreCoups]] 0] eq "erreur"} {
      set str [lindex $camp 1]
      set ::search::erreurCoups $str
    } else {
      # (the side written with the moves, ".Qg3" / "...Qg3", before the
      # one chosen below)
      set camp [lindex $camp 1]
      if {$camp eq {}} { set camp $sSideToMove }
      # (Siby: in the Search window, its own bar and Stop button)
      set stop .smv.b.stop
      set barre [list .smv.progress bar 301 21 time]
      catch {lassign [::moderne::recherche::barreCommune] stop barre}
      busyCursor .
      $stop configure -state normal
      catch {grab $stop}
      sc_progressBar {*}$barre
      ::search::accel::avant
      sc_progressBar {*}$barre
      set ecart [expr {$::search::ordreCoups != 0 && [string is integer -strict $::search::ecartMax] ? $::search::ecartMax : 0}]
      # (Siby: an error, e.g. a move it cannot read, left the grab and the
      # busy cursor on: everything froze, Yosha 2026-11-04)
      # (after a position search in the same search: the moves after that
      # position only, Yosha 2026-11-09)
      set apres [expr {[info exists ::search::apresPosition] && $::search::apresPosition}]
      # (and the material where the moves start, when the Material tab is
      # combined without a position, Yosha 2026-11-10)
      set mat [expr {[info exists ::search::materielCoups] ? $::search::materielCoups : {}}]
      set ::search::materielCoups {}
      set code [catch {sc_search moves $::search::filter::operation $moves $checkTest $camp $::search::ordreCoups $ecart $apres $mat} str]
      unbusyCursor .
      catch {grab release $stop}
      catch {$stop configure -state disabled}
      catch ::moderne::recherche::finBarre
      if {$code} {
        if {[regexp {unreadable move: (.*)$} $str -> m]} {
          set str [::moderne::tr "Coup non reconnu : $m" "Move not recognized: $m"]
        }
        set ::search::erreurCoups $str
        catch {.smv.status configure -text $str}
        return
      }
      # (the accelerator's share is said under the dialog)
      regsub {  \[accel [0-9]+\]} $str {} str
      ::search::accel::etat

      ::search::loadFirstGame
      ::windows::stats::Refresh
      # Siby: the results in their module (the moves found: all of them
      # when consecutive, else the first)
      set texte [.smv.g.moves get]
      set details [lindex [list [::moderne::tr consécutifs consecutive] [::moderne::tr "dans cet ordre" "in this order"] \
          [::moderne::tr "dans n'importe quel ordre" "in any order"]] $::search::ordreCoups]
      if {$camp eq "w"} { append details " • [::moderne::tr Blancs White]" } elseif {$camp eq "b"} { append details " • [::moderne::tr Noirs Black]" }
      if {$::search::ordreCoups && $ecart > 0} { append details " • [::moderne::tr "au plus $ecart coups" "at most $ecart moves"]" }
      catch {::moderne::resultats::montrer "$texte  ($details)" [expr {$::search::ordreCoups == 0 ? [llength $moves] : 1}]}
    }
    .smv.status configure -text $str
  }

  dialogbutton $w.b.cancel -textvar ::tr(Close) -command "focus .main ; destroy $w"
  packbuttons right $w.b.cancel .smv.b.stop .smv.b.search
  label $w.status -text "" -width 1 -font font_Small -relief sunken -anchor w
  pack $w.status -side bottom -fill x
  # Siby: the search accelerator
  ttk::frame $w.accel
  ttk::label $w.accel.l -foreground [::moderne::c texteDoux]
  ttk::button $w.accel.b -command ::search::accel::creerDemande
  pack $w.accel.l -side left -padx 10
  pack $w.accel -side bottom -fill x -pady {0 4}
  pack $w.b -side bottom -fill x
  pack $w.progress -side bottom -pady 2
  ::search::accel::etat
  wm resizable $w 0 0
  ::search::Config

  # (Siby: embedded in the search tab, Windows refuses a state change on it)
  catch {placeWinOverParent $w .}
  catch {wm state $w normal}
  focus $w.g.moves
}

### Siby: consecutive moves: the side plays the first one; otherwise it
### plays all of them
proc ::search::movesCamp {} {
  if {![winfo exists .smv.ends.label]} { return }
  # (the limit counts only when other moves may come between)
  foreach x {a n b} {
    catch {.smv.ordre.ecart.$x state [expr {$::search::ordreCoups == 0 ? "disabled" : "!disabled"}]}
  }
  .smv.ends.label configure -text [expr {$::search::ordreCoups == 0 \
      ? [::moderne::tr "Premier coup joué par" "First move played by"] \
      : [::moderne::tr "Coups joués par" "Moves played by"]}]
}

################################################################################
### Siby: the search accelerator, as ChessBase's (<base>.sia, made by Siby on
### this computer): a signature per game, so that a move search decodes only
### the games that can match. Offered at the first move search on a large
### base; kept up to date by itself (games added by Gaby's daily files or
### saved again); made again when the base was replaced (Gaby's complete
### download) if it was wanted. The choice per base is kept
### (::moderne::accelChoix: path -> 1 wanted, 0 declined).
################################################################################

namespace eval ::search::accel {
  variable seuil 100000     ;# games: offered from this size
}
if {![info exists ::moderne::accelChoix]} { set ::moderne::accelChoix {} }

proc ::search::accel::T {fr en} { return [::moderne::tr $fr $en] }

proc ::search::accel::cle {} { file normalize [sc_base filename] }

### {state covered games bytes todo}; state none | ok | update | stale
proc ::search::accel::lire {} {
  if {[catch {sc_search accel info} r]} { return {none 0 0 0 0} }
  return $r
}

proc ::search::accel::mo {octets} {
  set m [expr {$octets / 1048576.0}]
  if {$m >= 1024} { return "[T [string map {. ,} [format %.1f [expr {$m / 1024}]]] [format %.1f [expr {$m / 1024}]]] [T Go GB]" }
  return "[expr {max(1, round($m))}] [T Mo MB]"
}

### Before a move search. The accelerator is made by itself, in the
### background (sbbiblio --accel, a separate program: Siby keeps answering;
### on Gaby, a few minutes), for every base of 100,000 games or more (Yosha
### 2026-11-03: no question, no window); meanwhile the search runs without
### it. A small update (a few games added) is made at once.
proc ::search::accel::avant {} {
  lassign [lire] etat n total octets aFaire
  switch -- $etat {
    ok { return }
    update {
      if {$aFaire < 20000} {
        construire [T "Mise à jour de l'accélérateur de recherche…" "Updating the search accelerator…"]
        return
      }
    }
  }
  # (a search asks again: the base may have changed since it was checked)
  variable vu
  unset -nocomplain vu([sc_base current])
  catch {fond [sc_base current]}
}

### Small updates, in Siby itself (a few thousand games: under a second)
proc ::search::accel::construire {texte} {
  if {[winfo exists .smv.status]} { .smv.status configure -text $texte ; update idletasks }
  if {[catch {sc_search accel build} r]} {
    catch {.smv.status configure -text "[T "Accélérateur de recherche : erreur" "Search accelerator: error"] ($r)"}
  }
  etat
}

### Made in the background for base b (if it is large enough, not declined,
### not already being made, and the opening library is not being built)
proc ::search::accel::fond {b {force 0}} {
  variable seuil
  variable canal
  variable avance
  if {!$b || ![sc_base inUse $b] || $b == [sc_info clipbase]} { return }
  if {[info exists canal($b)]} { return }
  # (checked once per base and size: called at each library update)
  variable vu
  set cle "[sc_base filename $b]|[sc_base numGames $b]"
  if {!$force && [info exists vu($b)] && $vu($b) eq $cle} { return }
  if {[catch {sc_search accel info $b} r]} { return }
  lassign $r etat n total octets aFaire
  if {$etat eq "ok"} { set vu($b) $cle ; return }
  set f [file normalize [sc_base filename $b]]
  if {!$force && ($total < $seuil || ([dict exists $::moderne::accelChoix $f] && [dict get $::moderne::accelChoix $f] eq "0"))} { set vu($b) $cle ; return }
  # (one heavy reading of the base at a time: after the opening library)
  if {[info exists ::moderne::nsb::canal($b)]} {
    after 5000 [list catch [list ::search::accel::fond $b $force]]
    return
  }
  set vu($b) $cle
  set exe [::moderne::nsb::outil]
  if {$exe eq {}} { return }
  if {[catch {open [list | $exe --accel [sc_base filename $b]] r} c]} { return }
  fconfigure $c -blocking 0 -buffering line
  set canal($b) $c
  set avance($b) 0
  ::moderne::nsb::annonce [T "Base [file tail $f] : création de l'accélérateur de recherche de coups" \
      "Database [file tail $f]: building the move search accelerator"] 0
  fileevent $c readable [list ::search::accel::lireFond $b $c]
  etat
}

proc ::search::accel::lireFond {b c} {
  variable canal
  variable avance
  while {[gets $c l] >= 0} {
    if {[regexp {^PROGRES 4 (\d+) (\d+)} $l -> i n] && $n > 0} {
      set avance($b) [expr {min(100, int(100.0 * $i / $n))}]
      ::moderne::nsb::annonce {} $avance($b)
      etat
    } elseif {[string match ERREUR* $l]} {
      ::moderne::nsb::annonce "[T "Accélérateur de recherche : erreur" "Search accelerator: error"] ([string range $l 7 end])" -1
    }
  }
  if {![eof $c]} { return }
  catch {close $c}
  unset -nocomplain canal($b) avance($b)
  if {![string match *erreur* $::moderne::nsb::annonceTitre] && ![string match *error* $::moderne::nsb::annonceTitre]} {
    ::moderne::nsb::annonce [T "Accélérateur de recherche prêt : les recherches de coups seront plusieurs fois plus rapides" \
        "Search accelerator ready: move searches will be several times faster"] 100
  }
  after 5000 ::moderne::nsb::finAnnonce
  etat
}

### The button of the dialog (a base declined before, or a small one)
proc ::search::accel::creerDemande {} {
  dict set ::moderne::accelChoix [cle] 1
  catch {::options.write}
  fond [sc_base current] 1
}

### The dialog's line
proc ::search::accel::etat {} {
  variable seuil
  variable canal
  variable avance
  set w .smv.accel
  if {![winfo exists $w]} { return }
  set b [sc_base current]
  lassign [lire] etat n total octets
  pack forget $w.b
  if {[info exists canal($b)]} {
    $w.l configure -text "⚡ [T "Création de l'accélérateur de recherche en arrière-plan" "Building the search accelerator in the background"] : $avance($b) %"
  } elseif {$etat in {ok update}} {
    $w.l configure -text "⚡ [T "Accélérateur de recherche actif" "Search accelerator on"] ([mo $octets])"
    catch {::utils::tooltip::Set $w.l [T "Les recherches de coups lisent d'abord l'accélérateur et ne décodent que les parties qui peuvent correspondre. Il se met à jour tout seul." \
        "Move searches read the accelerator first and decode only the games that can match. It keeps up to date by itself."]}
  } elseif {$total >= 20000} {
    $w.l configure -text [T "Pas d'accélérateur de recherche pour cette base" "No search accelerator for this base"]
    $w.b configure -text [T "Créer ([mo $octets])" "Create ([mo $octets])"]
    catch {::utils::tooltip::Set $w.b [T "Rend les recherches de coups plusieurs fois plus rapides. Se crée en arrière-plan, une seule fois, et se met à jour tout seul." \
        "Makes move searches several times faster. Made in the background, once, and keeps up to date by itself."]}
    pack $w.b -side right -padx 10
  } else {
    $w.l configure -text {}
  }
}

### After games were added (Gaby's daily files): updated if there is one
proc ::search::accel::suivre {} {
  lassign [lire] etat n total octets aFaire
  if {$etat ne "update"} { return }
  if {$aFaire < 20000} { catch {sc_search accel build} } else { catch {fond [sc_base current]} }
}

set ::search::cqlStripSwitch 0
set ::search::cqlCommentSwitch 0

proc ::search::cql {} {
  global glstart tr

  set w .scql
  if {[winfo exists $w]} {
    wm deiconify $w
    raiseWin $w
    parseCommentForCQL
    return
  }

  toplevel $w
  wm withdraw $w
  wm title $w "CQL $tr(Search)"
  setWinLocation $w
  setWinSize $w

  bind $w <Escape> "$w.b.cancel invoke"
  #bind $w <Return> "$w.b.search invoke"
  bind $w <F1> { helpWindow CQL }

  label $w.type -textvar tr(CQLLabel) -font font_Bold
  pack  $w.type -side top

  frame $w.s
  label $w.s.strip -font font_Bold -textvar tr(CQLStrip)
  radiobutton $w.s.stripyes -textvar tr(Yes) -variable ::search::cqlStripSwitch -value 1
  radiobutton $w.s.stripno  -textvar tr(No)  -variable ::search::cqlStripSwitch -value 0

  label $w.s.comment -font font_Bold -textvar tr(CQLComments)
  radiobutton $w.s.commentyes -textvar tr(Yes) -variable ::search::cqlCommentSwitch -value 1 -command checkCQLSearch
  radiobutton $w.s.commentno  -textvar tr(No)  -variable ::search::cqlCommentSwitch -value 0 -command checkCQLSearch
  pack $w.s.comment $w.s.commentyes $w.s.commentno [label $w.s.space -width 5] \
       $w.s.strip   $w.s.stripyes   $w.s.stripno   -side left -pady 1

  canvas $w.progress -height 20 -width 300  -relief solid -border 1
  $w.progress create rectangle 0 0 0 0 -fill $::progcolor -outline $::progcolor -tags bar
  $w.progress create text 295 10 -anchor e -font font_Regular -tags time \
      -fill black -text "0:00 / 0:00"

  frame $w.b
  dialogbutton $w.b.stop -textvar tr(Stop) -command sc_progressBar -state disabled

  dialogbutton $w.b.search -textvar tr(Search) -command {
    set w .scql

    $w.status     configure -text {}

    busyCursor .
    $w.b.stop configure -state normal
    grab $w.b.stop
    sc_progressBar $w.progress bar 301 21 time

    set cqlSyntax [$w.g.syntax get 0.0 end]

    # Only allow CQL commenting for the clipbase
    set allowComments [expr  {([sc_base current] == [sc_info clipbase]) && $::search::cqlCommentSwitch}]

    set err [catch {
      set str [sc_search cql $::search::filter::operation $::search::cqlStripSwitch $allowComments $cqlSyntax]
    } result]

    unbusyCursor .
    grab release $w.b.stop
    $w.b.stop configure -state disabled

    if {$err} {
      tk_messageBox -title Siby -type ok -icon warning \
        -message [::moderne::tr "Erreur fatale renvoyée par la requête CQL :\n$result" "Fatal error returned from CQL query:\n$result"]
      return
    }

    if {[sc_filter count] > 0} {
      ::search::loadFirstGame
    } else {
      # current game could be altered
      if {$::search::cqlStripSwitch && $::search::cqlCommentSwitch} {
        ::game::Reload
      }
    }
    ::windows::stats::Refresh

    set index [string first "|" $str]
    if { $index > 5 } {
      set str "[string range $str 0 $index-1] -- [string range $str $index+1 end]"
    }

    $w.status configure -text $str
  }

  dialogbutton $w.b.cancel -textvar tr(Close) -command "focus .main ; destroy $w"

  packbuttons right $w.b.cancel $w.b.stop $w.b.search

  dialogbutton $w.b.save -textvar tr(Save) -command ::search::cqlSave
  dialogbutton $w.b.load -textvar tr(LoadGame) -command ::search::cqlLoad

  packbuttons left  $w.b.save $w.b.load

  label $w.status -text "" -font font_Small -relief sunken -anchor w

  pack $w.status     -side bottom -fill x
  pack $w.b          -side bottom -fill x

  pack $w.progress   -side bottom -pady 2
  pack [frame $w.line4 -height 2 -borderwidth 2 -relief sunken] -fill x -pady 5 -side bottom

  ::search::addFilterOpFrame $w 0 bottom
  pack [frame $w.line5 -height 2 -borderwidth 2 -relief sunken] -fill x -pady 5 -side bottom

  pack $w.s          -side bottom
  pack [frame $w.line6 -height 2 -borderwidth 2 -relief sunken] -fill x -pady 5 -side bottom

  ### pack text widget last to allow for nice resizing

  frame $w.g
  pack $w.g -side top -expand 1 -fill both -padx 2 -pady 1

  text $w.g.syntax -height 12 -width 64 -wrap word -yscrollcommand "$w.g.ybar set" -undo 1
  scrollbar $w.g.ybar -command "$w.g.syntax yview" -takefocus 0

  pack $w.g.ybar -side right -fill y
  pack $w.g.syntax -side left -fill both -expand 1

  bind $w.g.syntax <Control-a> {.scql.g.syntax tag add sel 0.0 end-1c ; break}
  bind $w.g.syntax <Control-z> {catch {.scql.g.syntax edit undo} ; break}; # Control-z is default text binding anyway
  bind $w.g.syntax <Control-y> {catch {.scql.g.syntax edit redo} ; break}; # but the others are not
  bind $w.g.syntax <Control-r> {catch {.scql.g.syntax edit redo} ; break}


  ::search::Config
  checkCQLSearch

  bind $w <Configure> "recordWinSize $w"
  wm state $w normal
  focus $w.g.syntax
  parseCommentForCQL
}

proc ::search::cqlSave {} {
  set w .scql

  set ftype [list [list [::moderne::tr "Fichier CQL" "CQL file"] {".cql"}]]
  set fName [tk_getSaveFile -initialdir $::initialDir(sso) -filetypes [::utils::trTypesFichiers $ftype] \
             -parent $w -title [::moderne::tr "Enregistrer une requête CQL" "Save a CQL Query"]]
  if {$fName == ""} { return }
  set ::initialDir(sso) [file dirname $fName]

  if {[string compare [file extension $fName] ".cql"] != 0} {
    append fName ".cql"
  }

  if {[catch {set searchF [open $fName w]}]} {
    tk_messageBox -title [::moderne::tr Erreur Error] -type ok -icon error -message [::moderne::tr "Impossible de créer le fichier CQL : $fName" "Unable to create CQL file: $fName"]
    return
  }
  puts $searchF [$w.g.syntax get 0.0 end]
  close $searchF
}

proc ::search::cqlLoad {} {
  set w .scql

  set ftype {
    {{CQL files}  {.cql} }
    {{Text files} {.txt} }
    {{All files}       * }
  }
  if {! [file isdirectory $::initialDir(sso)] } {
    set ::initialDir(sso) $::env(HOME)
  }
  set fName [tk_getOpenFile -initialdir $::initialDir(sso) -filetypes [::utils::trTypesFichiers $ftype] -title [::moderne::tr "Choisir un fichier de requête CQL" "Select a CQL query file"]]

  if {$fName != ""} {
    if {![catch {open $fName r} fd]} {
      $w.g.syntax delete 0.0 end
      while {[gets $fd line] >= 0} {
        $w.g.syntax insert end "$line\n"
        if {[eof $fd]} { break }
      }
      close $fd
      set ::initialDir(sso) [file dirname $fName]
    } else {
      tk_messageBox -title [::moderne::tr Erreur Error] -type ok -icon error -message [::moderne::tr "Impossible d'ouvrir le fichier CQL $fName en lecture." "Unable to open CQL file $fName for reading."]
    }
  }


}

### Validate/set configure status of some CQL widgets

proc checkCQLSearch {} {
  set w .scql.s

  if {![winfo exists $w]} {return}

  if {[sc_base current] != [sc_info clipbase]} {
    foreach i {comment commentyes commentno strip stripyes stripno} {
      $w.$i configure -state disabled
    }
  } else {
    foreach i {comment commentyes commentno} {
      $w.$i configure -state normal
    }

    if {$::search::cqlCommentSwitch} {
      set s normal
    } else {
      set s disabled
    }
    foreach i {strip stripyes stripno} {
      $w.$i configure -state $s
    }

  }
}

### Check current position for '%draw,full,SQUARE,color' comments and insert them as CQL search params

proc parseCommentForCQL {} {
  set comment [sc_pos getComment]
  if {[string match {*%draw full,*} $comment]} {
    set squares {}
    foreach line [split $comment %] {
      set line [string map {, \ } $line]
      if  {[scan $line %s%s%s%s a b c d] >= 4 && $a == "draw" && $b == "full"} {
        set piece [string index [sc_pos board] [::board::sq $c]]
        if {$piece == "."} {set piece {_}} ; # empty squares
        lappend squares $piece$c
      }
    }
    if {$squares != {}} {
      .scql.g.syntax delete 0.0 end
      .scql.g.syntax insert end "cql () $squares"
    }
  }
}
