# game.tcl: part of Scid

#   Prompts the user if they want to discard the changes to the
#   current game. Returns :
# 0 -> saves then continue
# 1 -> discard changes and continue
# 2 -> cancel action

### Siby: would ConfirmDiscard ask whether to save the game? (a game
### changed by hand, in a database where games are saved)
proc ::game::demanderait {} {
  if {$::trialMode || [sc_base isReadOnly] || ![sc_game altered]} { return 0 }
  if {[info exists ::game::remplacerSansQuestion] && $::game::remplacerSansQuestion} { return 0 }
  if {[sc_game info halfmoves] == 0} { return 0 }
  set f [sc_base filename]
  if {[info exists ::moderne::basesExploration] && $f in $::moderne::basesExploration} { return 0 }
  if {[file normalize $f] eq [file normalize [file join $::sibyDocsDir "Siby live"]]} { return 0 }
  return 1
}

### Siby: before another game takes the board's place (a game opened, a
### position set up, a game started): a changed game that would ask to be
### saved stays in its tab, the new one opens in a new tab, no question
### (Yosha 2026-11-09, as for broadcasts). Same answers as ConfirmDiscard.
proc ::game::ConfirmDiscardOnglet {} {
  if {[::game::demanderait] && [llength [info commands ::moderne::onglets::nouveau]]} {
    if {[catch {::moderne::onglets::nouveau} ok] || !$ok} { return 2 }
    return 1
  }
  return [::game::ConfirmDiscard]
}

proc ::game::ConfirmDiscard {} {
  # Siby: a game carried from another database goes back there first
  if {![catch {::moderne::onglets::confirmerPorte} r] && $r ne {}} { return $r }
  # This should be rewritten with tk_dialog and "return answer"
  # rather than "::game::answer" S.A.

  # This is not correct. We can have an altered game , then start Trial mode.
  # Instead, we should [setTrialMode 0], then check [sc_game altered], but needs lots of testing
  if {$::trialMode || [sc_base isReadOnly] || ![sc_game altered]} {
    return 1
  }
  # Siby: the game replaced on purpose (paste > Replace the game): not saved,
  # no question (Yosha 2026-11-06)
  if {[info exists ::game::remplacerSansQuestion] && $::game::remplacerSansQuestion} {
    return 1
  }
  if {[sc_game info halfmoves] == 0} {
    # Discard the "altered" games in the EPD window, and Setup Board if length is 0
    return 1
  }
  # Siby: databases where one explores without wanting to save
  set ::game::baseActuelle [sc_base filename]
  if {[info exists ::moderne::basesExploration] && $::game::baseActuelle in $::moderne::basesExploration} {
    return 1
  }
  # (the broadcasts' database: the games are Lichess's, not saved, as on
  # Lichess; "Save to..." keeps an annotated game)
  if {[file normalize $::game::baseActuelle] eq [file normalize [file join $::sibyDocsDir "Siby live"]]} {
    return 1
  }
  set w .confirmDiscard
  # Siby: the question is already being asked (second click, double-click in
  # the list): bring it back to the front and cancel this second request
  if {[winfo exists $w]} {
    catch {raise $w ; focus $w}
    return 2
  }
  set ::game::plusDemander 0

  toplevel $w
  wm state $w withdrawn
  wm title $w Siby
  set ::game::answer 2
  pack [frame $w.top] -side top
  addHorizontalRule $w
  pack [frame $w.bottom] -expand 1 -fill x -side bottom

  # label $w.top.icon -bitmap question
  # pack $w.top.icon -side left -padx 20 -pady 5

  # Siby: which game, in which database (Yosha 2026-11-04: "we don't know
  # which game nor which database")
  set txt $::tr(ClearGameDialog)
  catch {
    set bl [string trim [sc_game tags get White]]
    set no [string trim [sc_game tags get Black]]
    if {$bl in {{} ?}} { set bl ? }
    if {$no in {{} ?}} { set no ? }
    set num [sc_game number]
    set quoi [expr {$num > 0 ? [::moderne::tr "partie $num" "game $num"] : [::moderne::tr "nouvelle partie" "new game"]}]
    set base [file tail [sc_base filename [sc_base current]]]
    set txt [::moderne::tr "« $bl – $no » ($quoi, $base) a été modifiée.\nL'enregistrer ?" \
        "\"$bl – $no\" ($quoi, $base) was changed.\nSave it?"]
  }
  label $w.top.txt -text $txt -justify center
  pack $w.top.txt -padx 12 -pady 8 -side right

  button $w.bottom.b1 -width 10 -text $::tr(Save)     -command {destroy .confirmDiscard ; set ::game::answer 0}
  button $w.bottom.b2 -width 10 -text $::tr(DontSave) -command {destroy .confirmDiscard ; set ::game::answer 1}
  button $w.bottom.b3 -width 10 -text $::tr(Cancel)   -command {destroy .confirmDiscard ; set ::game::answer 2}
  # Siby: buttons as wide as their text
  if {[llength [info commands ::moderne::actif]] && [::moderne::actif]} {
    foreach b {b1 b2 b3} { $w.bottom.$b configure -width 0 -padx 14 }
    $w.top.txt configure -justify center -padx 16 -pady 6
  }
  pack $w.bottom.b1 $w.bottom.b2 $w.bottom.b3 -side left -padx 10 -pady 5
  # Siby: don't ask again for this database (free exploration)
  if {[llength [info commands ::moderne::actif]] && [::moderne::actif] && $::game::baseActuelle ne {}} {
    ttk::checkbutton $w.plus -variable ::game::plusDemander -text [::moderne::tr \
        "Ne plus demander pour cette base (« Ne pas sauvegarder » automatique)" \
        "Don't ask again for this database (« Don't save » automatically)"]
    pack $w.plus -side bottom -anchor w -padx 10 -pady {4 2} -after $w.bottom
  }

  bind $w <Destroy> {set ::game::answer 2}
  bind $w <Right> "event generate $w <Tab>"
  bind $w <Left> "event generate $w <Shift-Tab>"

  update
  placeWinOverParent $w .
  wm state $w normal

  catch { grab $w }

  focus $w.bottom.b2
  vwait ::game::answer
  if {$::game::plusDemander && $::game::answer == 1 && $::game::baseActuelle ne {}} {
    if {![info exists ::moderne::basesExploration]} { set ::moderne::basesExploration {} }
    lappend ::moderne::basesExploration $::game::baseActuelle
  }
  return $::game::answer
}

### New Game
#   Clears the active game, checking first if it is altered.
#   Updates any affected windows.

proc ::game::Clear {{confirm yes}} {
  if {$confirm == "yes"} {
    set confirm [::game::ConfirmDiscard]
    if {$confirm == 2} { return }
    if {$confirm == 0} {
      ::game::Save
    }
  }

  setTrialMode 0
  sc_game new
  updateBoard -pgn
  updateTitle
  updateMenuStates
  ::tools::graphs::score::Refresh
}

#   Strips all comments or variations from a game

proc ::game::Strip {type {parent .}} {
  sc_game undoPoint

  if {[catch {sc_game strip $type} result]} {
    tk_messageBox -parent $parent -type ok -icon info -title Siby -message $result
    return
  }
  updateBoard -pgn
  updateTitle
  ::tools::graphs::score::Refresh
}

proc ::game::TruncateBegin {} {
  sc_game undoPoint

  # Siby: the move selected is kept, as in ChessBase (on 3.Bb5 the game
  # starts with 3.Bb5): the game is cut one ply before, then the move
  # played again. SCID cut it at the position after the move, which lost
  # it (Yosha 2026-11-10)
  set recul 0
  if {[::moderne::actif] && ![sc_pos isAt start] && ![sc_pos isAt vstart]} {
    sc_move back
    set recul 1
  }
  if {[catch {sc_game truncate -start} result]} {
    if {$recul} { sc_move forward }
    tk_messageBox -parent . -type ok -icon info -title Siby -message $result
    return
  }
  if {$recul} { sc_move forward }
  updateBoard -pgn
  ::tools::graphs::score::Refresh
}

proc ::game::Truncate {} {
  sc_game undoPoint

  if {[catch {sc_game truncate} result]} {
    tk_messageBox -parent . -type ok -icon info -title Siby -message $result
    return
  }
  updateBoard -pgn
  updateTitle
  ::tools::graphs::score::Refresh
}

proc ::game::Delete {} {
  sc_game flag delete [sc_game number] invert
  updateStatusBar
  ::windows::gamelist::Refresh
}

#   Loads the next or previous filtered game in the database.
#   The parameter <action> should be "previous" , "next", "first" or "last"

proc ::game::LoadNextPrev {action {raise 1}} {
  global pgnWin statusBar
  if {![sc_base inUse]} {
    set statusBar "  There is no $action game: this is an empty database."
    return
  }
  set number [sc_filter $action]
  # Siby: after the last game, the first one (and before the first, the
  # last), Yosha 2026-11-10
  if {$number == 0 && [::moderne::actif]} {
    catch {set number [sc_filter [expr {$action eq "next" ? "first" : "last"}]]}
  }
  if {$number == 0} {
    set statusBar "  There is no $action game in the current filter."
    return
  }
  if {$number == [sc_game number]} {
    set statusBar "  Game $number already loaded."
    return
  }
  ::game::Load $number 1 $raise
}

#   Reloads the current game.

proc ::game::Reload {} {
  if {![sc_base inUse]} { return }
  if {[sc_game number] < 1} { return }
  ::game::Load [sc_game number]
}

#   Loads a random game from the database.

proc ::game::LoadRandom {} {
  set ngames [sc_filter size]
  if {$ngames == 0} { return }
  set r [expr {(int (rand() * $ngames)) + 1} ]
  set gnumber [sc_filter index $r]
  ::game::Load $gnumber
}


# ::game::LoadNumber
#
#    Prompts for the number of the game to load.

set ::game::entryLoadNumber ""
trace variable ::game::entryLoadNumber w {::utils::validate::Regexp {^[0-9]*$}}

proc ::game::LoadNumber {} {
  set ::game::entryLoadNumber ""
  if {![sc_base inUse]} { return }

  set confirm [::game::ConfirmDiscardOnglet]
  if {$confirm == 2} { return }
  if {$confirm == 0} {
    ::game::Save
  }

  if {[sc_base numGames] < 1} { return }

  set w .glnumDialog
  if {[winfo exists $w]} {
    raiseWin $w
    return
  }
  toplevel $w
  wm title $w "Siby: [tr GameNumber]"
  wm state $w withdrawn

  label $w.label -text $::tr(LoadGameNumber)
  pack $w.label -side top -pady 5 -padx 5

  entry $w.entry  -width 10 -textvariable ::game::entryLoadNumber
  bind $w.entry <Escape> { .glnumDialog.buttons.cancel invoke }
  bind $w.entry <Return> { .glnumDialog.buttons.load invoke }
  pack $w.entry -side top -pady 5

  set b [frame $w.buttons]
  pack $b -side top -fill x
  dialogbutton $b.load -text "OK" -command {
    # todo: Can we integrate this into ::file::Open
    if {[catch {sc_game load $::game::entryLoadNumber} result]} {
      tk_messageBox -type ok -icon info -title Siby -message $result
    }
    focus .main
    destroy .glnumDialog
    flipBoardForPlayerNames
    updateBoard -pgn
    refreshWindows
    ::bookmarks::AddCurrentGame
  }
  dialogbutton $b.cancel -text $::tr(Cancel) -command {
    destroy .glnumDialog
    focus .main
  }
  packbuttons right $b.cancel $b.load

  placeWinOverParent $w .
  update
  wm state $w normal
  focus $w.entry
}

### Loads a specified game from the active database.

proc ::game::Load { selection {update 1} {raise 1}} {
  # If an invalid game number, just return:
  if {$selection < 1 || $selection > [sc_base numGames]} {
    return
  }
  if {[winfo exists .fics] && $::fics::mainGame > -1} {
    ### Handle cases where fics playing and observing
    if {($::fics::playing==1 || $::fics::playing==-1)} {
      ::fics::updateConsole "Siby: game loads disabled while playing a game"
      return
    }
    ::fics::demote_mainGame
    set ::fics::mainGame -1
    set ::fics::autoload {}
  } else {
    set confirm [::game::ConfirmDiscardOnglet]
    if {$confirm == 2} { return -1 }
    if {$confirm == 0} {
      ::game::Save
    }
  }

  setTrialMode 0
  sc_game load $selection
  flipBoardForPlayerNames
  if {$update} {
    updateBoard -pgn
  }
  if {$raise && \
      ![winfo exists .tourney] && \
      ![winfo exists .twinchecker] && \
      ![winfo exists .sb] && \
      ![winfo exists .sh] && \
      ![winfo exists .bmedit] && \
      ![winfo exists .sm] && ![winfo exists .smv] } {
    raiseWin .
  }
  refreshWindows
  ::bookmarks::AddCurrentGame
}

### Replaces numerous 'sc_game save [sc_game number]' around the place.
# New saved games are added to Game History

proc ::game::Save {} {
    set n [sc_game number]
    sc_game save $n
    if {$n == 0} {
      # add new game to history
      ::bookmarks::AddCurrentGame
      updateMenuStates
    }
}

#   Produces a popup dialog for loading a game or other actions
#   such as merging it into the current game.

proc ::game::LoadMenu {w base gnum x y} {
  set m $w.gLoadMenu
  if {! [winfo exists $m]} {
    menu $m
    $m add command -label $::tr(BrowseGame)
    $m add command -label $::tr(LoadGame)
    $m add command -label $::tr(MergeGame)
  }
  $m entryconfigure 0 -command "::gbrowser::new $base $gnum"

  $m entryconfigure 1 -command "
    if {!\[checkBaseInUse $base $w\]} {
      return
    }
    if {\[sc_base current\] != $base} {
      sc_base switch $base
      # These two not now refreshed with game::Load below
      ::plist::refresh
      ::tourney::refresh
    }
    ::game::Load $gnum"

  $m entryconfigure 2 -command "mergeGame $base $gnum"

  ### Use tk_popup, amd remove the event hacks
  ### Wish8.7a0 menu's "post" doesn't allow for any way to cancel the menu for some reason - S.A.
  tk_popup $m $x $y
}


#   Entry variable for GotoMoveNumber dialog.
set ::game::moveEntryNumber ""
trace variable ::game::moveEntryNumber w {::utils::validate::Regexp {^[0-9]*$}}

#    Prompts for the move number to go to in the current game.

proc ::game::GotoMoveNumber {} {
  set ::game::moveEntryNumber ""
  set w .mnumDialog
  if {[winfo exists $w]} {
    raiseWin $w
    return
  }
  toplevel $w
  wm title $w "Siby: [tr GameGotoMove]"

  label $w.label -text $::tr(GotoMoveNumber)
  pack $w.label -side top -pady 5 -padx 5

  entry $w.entry -width 8 -textvariable ::game::moveEntryNumber -borderwidth 0 ; # -justify right
  bind $w.entry <Escape> { .mnumDialog.buttons.cancel invoke }
  bind $w.entry <Return> { .mnumDialog.buttons.load invoke }
  pack $w.entry -side top -pady 5

  set b [frame $w.buttons]
  pack $b -side top -fill x
  dialogbutton $b.load -text "OK" -command {
    if {$::game::moveEntryNumber > 0} {
      catch {sc_move ply [expr {($::game::moveEntryNumber - 1) * 2}] ; sc_move forward}
    }
    focus .main
    destroy .mnumDialog
    # updateBoard -pgn
    updateBoard
  }
  dialogbutton $b.cancel -text $::tr(Cancel) -command {
    focus .main
    destroy .mnumDialog
    focus .main
  }
  packbuttons right $b.cancel $b.load

  placeWinOverParent $w .

  focus $w.entry
}

### End of file: game.tcl
