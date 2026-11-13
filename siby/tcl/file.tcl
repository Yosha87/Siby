
### file.tcl

# Get confirmation then exit.

proc ::file::Exit {}  {

  # sanity check in case of errant multiple calls
  if {[winfo exists .unsaved]} {return}

  # is OSX recursively calling this proc when tk_dialog exits ?
  wm protocol . WM_DELETE_WINDOW {}

  # (Siby: games carried to another database go back to theirs first)
  catch ::moderne::onglets::rapatrierTout
  # Check for altered game in all bases except the clipbase:
  set unsavedCount 0
  set savedBase [sc_base current]
  set msg ""
  set nbases [sc_base count total]
  for {set i 1} {$i < [sc_base count total]} {incr i} {
    sc_base switch $i
    if {[sc_base inUse] && [sc_game altered] && ![sc_base isReadOnly]} {
      # (Siby live: games one explores, never offered for saving)
      set fname [file tail [sc_base filename]]
      if {$fname eq "Siby live"} { continue }
      if {$unsavedCount == 0} {
        append msg [::moderne::tr "Parties non enregistrées :" "Games not saved:"]
        append msg "\n\n"
      }
      incr unsavedCount
      # (Siby: the game named by its players, and its database)
      set bl [string trim [sc_game tags get White]] ; if {$bl in {{} ?}} { set bl ? }
      set no [string trim [sc_game tags get Black]] ; if {$no in {{} ?}} { set no ? }
      set g [sc_game number]
      set quoi [expr {$g > 0 ? [::moderne::tr "partie $g" "game $g"] : [::moderne::tr "nouvelle partie" "new game"]}]
      append msg "•  $bl – $no  ($fname, $quoi)\n"
    }
  }
  # Switch back to original database:
  sc_base switch $savedBase
  # (and the games of the other notation tabs)
  catch {::moderne::onglets::nonEnregistres msg unsavedCount}

  if {$unsavedCount > 0} {
    # Siby: save and quit, quit without saving, or cancel
    set answer [tk_dialog .unsaved [::moderne::tr "Siby : confirmer la sortie" "Siby: Confirm Quit"] $msg {} 0 \
        [::moderne::tr "Enregistrer et quitter" "Save and exit"] \
        [::moderne::tr "Quitter sans enregistrer" "Exit without saving"] [tr Cancel]]
    if {$answer == 2 || $answer < 0} {
      wm protocol . WM_DELETE_WINDOW {::file::Exit}
      return
    }
    if {$answer == 0 && ![catch ::moderne::onglets::toutEnregistrer err] && $err ne {}} {
      tk_messageBox -icon error -type ok -title Siby -message $err
      wm protocol . WM_DELETE_WINDOW {::file::Exit}
      return
    }
  } elseif {[winfo exists .comp]} {
    set msg [::moderne::tr "Un tournoi entre moteurs est en cours." "A Computer Tournament is running."]
    append msg "\n$::tr(ExitDialog)"
    set answer [tk_dialog .unsaved [::moderne::tr "Siby : confirmer la sortie" "Siby: Confirm Quit"] $msg question {} "   [tr FileExit]   " [tr Cancel]]
    if {$answer != 0} {
      wm protocol . WM_DELETE_WINDOW {::file::Exit}
      return
    }
  }

  ::tree::mask::close
  if {[winfo exists .glistWin]} {
    ::windows::gamelist::recordWidths
  }
  for {set i 0} {$i < [llength $::engines(list)]} {incr i} {
    if {[winfo exists .analysisWin$i]} {
        # Try to be nice and close all engines, especially Graham's driver. It's a bit of a mess, but
        # Destroy/WM_DELETE_WINDOW is now unbound (on windows only?) so call proc exclusively
        destroyAnalysisWin $i

        # This vwait is essential for eboards, but may need removing if it misbehaves elsewhere. S.A.
        # ... Hmm - it does stop app exitting in undocked mode. Nasty S.A.
	if {$::docking::USE_DOCKING} {
	  vwait ::analysisWin$i
	}
    }
  }
  if {$::optionsAutoSave} {
    # restore askToReplaceMoves if necessary
    if {[winfo exists .tacticsWin]} {
      ::tactics::restoreAskToReplaceMoves
    }
    .menu.options invoke [tr OptionsSave]
  }
  ::recentFiles::save
  ::utils::history::Save
  # Siby: no process left behind (engines, Toby, downloads)
  catch ::moderne::arret::arreterProcessus
  # (quitting normally: no game to bring back at the next start)
  catch ::moderne::reprise::quitter
  catch ::moderne::integrite::quitter
  # (a normal quit is not a start that failed: see the safe start)
  catch {file delete [file join $::scidUserDir demarrage.txt]}
  catch ::moderne::pgnfichier::nettoyer
  # (a new version of Siby waiting: installed once Siby has ended)
  catch ::moderne::majsiby::auQuitter
  # (Options › Back to the default settings: done now, then Siby again)
  catch ::moderne::reglagesDefaut::auQuitter
  # (Siby's log: the lines still waiting written, then every writing of the
  # background thread finished, 2 s at most)
  catch ::moderne::journalVider
  catch {sc_ecrire_fond attendre 2000}
  destroy .
}

proc ::file::ExitFast {} {
  wm protocol . WM_DELETE_WINDOW {}
  if {$::optionsAutoSave} {
    # restore askToReplaceMoves if necessary
    if {[winfo exists .tacticsWin]} {
      ::tactics::restoreAskToReplaceMoves
    }
    .menu.options invoke [tr OptionsSave]
  }
  ::recentFiles::save
  catch ::moderne::arret::arreterProcessus
  # (quitting normally: no game to bring back at the next start)
  catch ::moderne::reprise::quitter
  catch ::moderne::integrite::quitter
  # (a normal quit is not a start that failed: see the safe start)
  catch {file delete [file join $::scidUserDir demarrage.txt]}
  catch ::moderne::pgnfichier::nettoyer
  # (a new version of Siby waiting: installed once Siby has ended)
  catch ::moderne::majsiby::auQuitter
  # (Options › Back to the default settings: done now, then Siby again)
  catch ::moderne::reglagesDefaut::auQuitter
  # (Siby's log: the lines still waiting written, then every writing of the
  # background thread finished, 2 s at most)
  catch ::moderne::journalVider
  catch {sc_ecrire_fond attendre 2000}
  destroy .
}

# ::file::New
#
#   Opens file-save dialog and creates a new database.

proc ::file::New {} {
  if {[sc_base count free] == 0} {
    tk_messageBox -title Siby -type ok -icon info \
        -message [::moderne::tr "Trop de bases ouvertes : fermes-en une d'abord." "Too many databases open; close one first"]
    return
  }
  # (Siby: databases only; EPD position files are an old SCID tool, still
  # under Tools)
  # (Siby: a Siby database or a PGN file, like ChessBase's "New database")
  set ftype {
    { "Siby databases (.si4)" {".si4"} }
    { "PGN files (.pgn)" {".pgn"} }
  }
  set ::file::typeNouveau {}
  if {![file isdirectory $::initialDir(base)] || [file normalize $::initialDir(base)] eq [file normalize $::env(HOME)]} {
    set ::initialDir(base) [::file::dossierDefaut]
  }
  set fName [tk_getSaveFile -initialdir $::initialDir(base) -defaultextension .si4 -filetypes [::utils::trTypesFichiers $ftype] \
      -typevariable ::file::typeNouveau -title [::moderne::tr "Nouvelle base" "New database"]]
  if {$fName == {}} {
    return
  }
  # (the PGN type chosen and a name without its extension)
  if {[string match -nocase *pgn* $::file::typeNouveau] && [string tolower [file extension $fName]] ne ".pgn"} {
    set fName "[file rootname $fName].pgn"
  }
  if {[string tolower [file extension $fName]] eq ".pgn"} {
    # an empty PGN file, opened like the others (the games added are
    # written back to it)
    if {![file exists $fName] && [catch {close [open $fName w]} err]} {
      tk_messageBox -icon warning -type ok -parent . -title Siby \
          -message [::moderne::tr "Impossible de créer $fName\n$err" "Can't create $fName\n$err"]
      return
    }
    catch {if {$fName ni $::moderne::mesBases} { lappend ::moderne::mesBases $fName }}
    ::file::Open $fName
    return
  } elseif {[file extension $fName] == ".epd"} {
    if {![::epd::newEpdWin create $fName]} {
      return
    }
  } else {
    if {[file extension $fName] == ".si4"} {
      set fName [file rootname $fName]
    }
    if {[catch {sc_base create $fName} result]} {
      tk_messageBox -icon warning -type ok -parent . \
          -title [::moderne::tr "Siby : erreur" "Siby: error"] -message [::moderne::tr "$result\nImpossible de créer $fName" "$result\nCan't create $fName"]
      return
    }
    # set default icon
    catch {sc_base type [sc_base current] 1}
    set fName $fName.si4
  }
  set ::glistFlipped([sc_base current]) 0
  ::recentFiles::add $fName
  refreshWindows all
  refreshSearchDBs
  updateBoard -pgn -switch
}

### Main file open procedure. If no filename given, shows a file-open dialog

# This proc should return an error status... (so do it gradually)
# But it is used everywhere, and will take some time to fix

### Siby: default folder of the file dialogs: Documents (Windows: the real
### Documents folder, also when OneDrive moved it), else the home folder
proc ::file::dossierDefaut {} {
  if {$::windowsOS} {
    if {![catch {
      package require registry
      set d [registry get {HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders} Personal]
    }] && [file isdirectory $d]} { return [file normalize $d] }
    if {[info exists ::env(USERPROFILE)] && [file isdirectory [file join $::env(USERPROFILE) Documents]]} {
      return [file join $::env(USERPROFILE) Documents]
    }
  }
  foreach d [list [file join $::env(HOME) Documents] $::env(HOME)] {
    if {[file isdirectory $d]} { return $d }
  }
  return [pwd]
}

proc ::file::Open {{fName ""} {parent .} {update 1}} {

  if {[sc_base count free] == 0} {
    tk_messageBox -type ok -icon info -title Siby \
        -message [::moderne::tr "Trop de bases ouvertes : fermes-en une d'abord." "Too many databases are open; close one first"] -parent $parent
    return
  }

  if {[sc_info gzip]} {
    set ftype {
      { {Siby databases (.si4) and PGN} {.si4 .si3 .pgn .PGN .pgn.gz .epd .epd.gz} }
      { {Siby databases (.si4)} {.si4 .si3} }
      { {PGN files (.pgn)} {.pgn .PGN .pgn.gz} }
      { {EPD positions (.epd)} {.epd .EPD .epd.gz} }
    }
  } else {
    set ftype {
      { {Siby databases (.si4) and PGN} {.si4 .si3 .pgn .PGN .epd} }
      { {Siby databases (.si4)} {.si4 .si3} }
      { {PGN files (.pgn)} {.pgn .PGN} }
      { {EPD positions (.epd)} {.epd .EPD} }
    }
  }
  if {$fName == ""} {
    # Siby: the last folder used, else Documents (not the home folder full
    # of technical folders)
    set dir $::file::finder::data(dir)
    if {![file isdirectory $dir] || [file normalize $dir] eq [file normalize $::env(HOME)]} {
      set dir [::file::dossierDefaut]
    }
    set fName [tk_getOpenFile -initialdir $dir -filetypes [::utils::trTypesFichiers $ftype] \
                 -title [::moderne::tr "Ouvrir une base" "Open a database"] -parent $parent]
    if {$fName == ""} { return }
    set ::file::finder::data(dir) [file dirname $fName]
  }

  setTrialMode 0 0

  set ext [file extension $fName]
  if {$ext == "" || [file readable "$fName.si4"]} {
    set fName "$fName.si4"
    set ext .si4
  }

  if {$ext == ".sg4" || $ext == ".sn4"} {
    set fName "[file rootname $fName].si4"
    set ext .si4
  }

  if {$ext == ".si3" && [file exists $fName]} {
    ::file::Upgrade [file rootname $fName]
    return
  }

  set fName [fullname $fName]

  set slot [sc_base slot $fName]
  if {$slot != 0} {
    sc_base switch $slot
    refreshWindows all
    updateBoard -pgn -switch
    return
  }

  # The ::recentFiles::remove and ::recentFiles::add should probably be
  # handled when "if {err == 0}"

  set err 0
  busyCursor .

  if {$ext == ".si4"} {
    set fName [file rootname $fName]
    if {[catch {openBase $fName} result]} {
      set err 1
      if {![string match {*doesn't exist*} $result] && ![string match {*n'existe pas*} $result]} {
        set result [::moderne::tr "$result\nImpossible d'ouvrir $fName." "$result\nCan't open $fName."]
      }
      unbusyCursor .
      tk_messageBox -icon warning -type ok -parent $parent \
          -title [::moderne::tr "Siby : erreur d'ouverture du fichier" "Siby: Error opening file"] -message "$result"
      ::recentFiles::remove "$fName.si4"
      return -1
    } else {
      set ::initialDir(base) [file dirname $fName]
      ::recentFiles::add "$fName.si4"
    }
  } elseif {[string match "*.epd" [string tolower $fName]]} {
    # EPD file:
    if {[::epd::newEpdWin open $fName]} {
      ::recentFiles::add $fName
      unbusyCursor .
      ::bookmarks::AddCurrentGame
      refreshWindows
      return
    } else {
      ::recentFiles::remove $fName
    }
  } else {
    if {![file exists $fName]} {
      set err 1
      ::recentFiles::remove $fName
      unbusyCursor .
      tk_messageBox -icon warning -type ok -parent $parent \
          -title [::moderne::tr "Siby : erreur d'ouverture du fichier" "Siby: Error opening file"] -message [::moderne::tr "Le fichier $fName n'existe pas." "File $fName doesn't exist."]
    } else {
      if {$ext != ".pgn" && $ext != ".PGN"} {
	puts {Unknown file type, assuming PGN.}
      }
      ## note : .zip isn't supported by zlib. Only .pgn.gz is supported.

      set result [::moderne::tr "Le fichier $fName n'est pas lisible." "File $fName is not readable."]
      if {(![file readable $fName])  || \
	    [catch {sc_base create $fName true} result]} {
	set err 1
	unbusyCursor .
	tk_messageBox -icon warning -type ok -parent $parent \
	    -title [::moderne::tr "Siby : erreur d'ouverture du fichier" "Siby: Error opening file"] -message $result
      } else {
	doPgnFileImport $fName [::moderne::tr "Ouverture de [file tail $fName] en lecture seule\n" "Opening [file tail $fName] read-only\n"]
	sc_base type [sc_base current] 3
	# Siby: editable PGN database, saved to the file
	catch {::moderne::pgnfichier::ouvert [sc_base current] $fName}
	::recentFiles::add $fName
	set ::initialDir(pgn) [file dirname $fName]
	set ::initialDir(file) [file tail $fName]
      }
    }
  }

  set ::glstart 1
  if {$err == 0} {
    # Siby: padlocks (the reference database is padlocked by default)
    after idle {catch ::moderne::mesbases::appliquerCadenas}
    # Siby: opening a database loads no game (SCID loaded the
    # first one); the game list opens instead
    if {[llength [info commands ::moderne::actif]] && [::moderne::actif]} {
      # (not for a database opened in the background, e.g. the reference
      # database of the libraries: ::file::discret)
      if {![info exists ::file::discret] || !$::file::discret} {
        # (not from My databases going to the Lab: its layout has the game
        # list; opened here it filled the whole window for a moment)
        if {![info exists ::file::sansListe] || !$::file::sansListe} {
          after idle {catch ::windows::gamelist::Open}
        }
        # the preparation switches from the clipbase to the opened database
        after idle {catch ::moderne::prepa::baseOuverte}
      }
      # instant opening library (.sbl) of a large database: checked, rebuilt if needed
      after 2000 [list catch [list ::moderne::nsb::verifier [sc_base current]]]
    } else {
      catch {sc_game load auto}
    }
    # Setting this here makes the gamelist show *only* last line of "default" opened DBs
    # set ::glstart [sc_game number]
    flipBoardForPlayerNames
    set ::glistFlipped([sc_base current]) $::flippedForPlayer
    if {[sc_game number] != 1 && [winfo exists .glistWin]} {
      # glistWin doesnt exist at init  - hmm
      ::windows::gamelist::showCurrent
    }
  }
  unbusyCursor .

  ### Hmmm - Check if tree/bestgames exists for this base, and update tab name
  set current [sc_base current]
  if {[winfo exists .treeWin$current]} {
    ::setTitle .treeWin$current "[tr Tree] \[[file tail [sc_base filename $current]]\]"
  }
  if {[winfo exists .treeBest$current]} {
    ::setTitle .treeBest$current "$::tr(TreeBestGames) \[[file tail [sc_base filename $current]]\]"
  }

  if {$update} {
    refreshWindows all
    refreshSearchDBs
    ::bookmarks::AddCurrentGame
    updateBoard -pgn -switch
  }
  # else bookmarks will call refreshWindows after correct game loaded
}

proc refreshWindows {{all no}} {
  ::windows::gamelist::Reload
  ### Done in updateBoard
  # ::tree::refresh
  ::windows::stats::Refresh
  ::tools::graphs::score::Refresh

  if {$all != "no"} {
    ### too slow to refresh all the time
    # ::crosstab::Refresh
    ### Some refreshes will have to call these two themselves
    ### They *should* be done *sometime* when doing a base switch
    ::plist::refresh
    ::tourney::refresh
    if {[winfo exists .extratags]} {
      update ; # Hmmm... needed for proper progressBar operation when swapping bases.
      extraTags
    }
  }

  updateMenuStates
  updateTitle
  updateStatusBar
  refreshCustomFlags
  checkCQLSearch
}

### Update a few widgets with the Custom Flags
### (Only needs to be done after DB switch/open/close)

proc refreshCustomFlags {} {

  global maintFlag maintFlags maintFlaglist glistFlag

  ### maintenance window

  set w .maintWin
  if {[winfo exists $w]} {

      for {set i 1} { $i < 7} { incr i} {
	set desc [sc_game flag $i description]
	$w.title.cust.text$i configure -text $desc
      }

      ### Update the CustomFlag menubutton menus

      for {set idx 12} {$idx < 18} {incr idx} {
	set flag [ lindex $maintFlaglist $idx]
	set tmp [sc_game flag $flag description]
        if {$tmp == "" } {
          set tmp "Custom $flag"
        } else {
          set tmp "$tmp ($flag)"
        }
	.maintWin.mark.title.m entryconfigure $idx -label "$tmp"
      }

      ### Update the CustomFlag menubutton title
      # [Dont translate CustomFlag1 (etc)]

      if {$maintFlag ni {1 2 3 4 5 6}} {
	set tmp $::tr($maintFlags($maintFlag))
      } else  {
	set tmp [sc_game flag $maintFlag description]
	if {$tmp == "" } {
	  set tmp "Custom $maintFlag"
	} else {
	  set tmp "$tmp ($maintFlag)"
	}
      }
      set flagname $tmp
      # set flagname "$::tr($maintFlags($maintFlag)) [string tolower $::tr(Flag)]"
      $w.mark.title configure -text "$flagname"
      $w.title.mark configure -text "$flagname"
      $w.title.desc.text configure -text [sc_base description]
  }
}

proc refreshSearchDBs {} {
  ### header search
  #   (todo)
  set w .sh
  if {[winfo exists $w]} {
  }

  ### board search
  set w .sb
  if {[winfo exists $w]} {
      set ::listbases {}

      # populate the combobox
      for {set i 1} {$i <= [sc_base count total]} {incr i} {
	if {[sc_base inUse $i]} {
	  lappend ::listbases [file tail [sc_base filename $i]]
	}
      }
      $w.refdb.lb configure -values $::listbases
      $w.refdb.lb current 0

      checkState ::searchRefBase $w.refdb.lb
  }
}

# ::file::Upgrade
#
#   Upgrades an old (version 3) Scid database to version 4.
#
proc ::file::Upgrade {name} {
  if {[file readable "$name.si4"]} {
    set msg [string trim $::tr(ConfirmOpenNew)]
    set res [tk_messageBox -title Siby -type yesno -icon info -message $msg]
    if {$res == "no"} { return }
    ::file::Open "$name.si4"
    return
  }

  set msg [string trim $::tr(ConfirmUpgrade)]
  set res [tk_messageBox -title Siby -type yesno -icon info -message $msg]
  if {$res == "no"} { return }
  progressWindow Siby "$::tr(Upgrading): [file tail $name]"\
      $::tr(Cancel) sc_progressBar
  busyCursor .
  update
  set err [catch {sc_base upgrade $name} res]
  unbusyCursor .
  closeProgressWindow
  if {$err} {
    tk_messageBox -title Siby -type ok -icon warning \
        -message [::moderne::tr "Impossible de mettre à jour la base :\n$res" "Unable to upgrade the database:\n$res"]
    return
  } else  {
    # rename game and name files, delete old .si3
    file rename "$name.sg3"  "$name.sg4"
    file rename "$name.sn3"  "$name.sn4"
    file delete "$name.si3"
  }
  ::file::Open "$name.si4"
}

#    Opens a Scid database, showing a progress bar in a separate window
#    if the database is around 5 Mb or larger in size.
#   ::file::Open should be used if the base is not already in si4 format

proc openBase {name} {

  # This check should probably be done somewhere else
  # But fixing issue/all scenarios is very painful , so leave it here steven!
  if {![file exists $name.si4]} {
    return -code error [::moderne::tr "Le fichier « $name.si4 » n'existe pas." "File \"$name.si4\" doesn't exist."]
  }

  # Depending on how file is opened, windows can have "\" file separators
  # We don't want to open this twice somehow

  if {$::windowsOS && [string range $name 1 2] == ":\\"} {
    ::splash::add "Translating \"\\\" filename separators for $name"
    set name [string map {\\ /} $name]
  }

  set bsize 0

  ### wrong i think
  # set gfile "[file rootname $name].sg4"
  set gfile "$name.sg4"

  if {! [catch {file size $gfile} err]} { set bsize $err }
  set showProgress 0
  if {$bsize > 5000000} { set showProgress 1 }
  # (Siby: read in the background already: opened at once)
  if {![catch {sc_base prepa} p] && [lindex $p 0] eq "pret" && [lindex $p 1] eq $name} { set showProgress 0 }
  if {$showProgress} {
    progressWindow Siby "$::tr(OpeningTheDatabase): [file tail $name]"
  }
  if {$::fastDBopen} {
    set err [catch {sc_base open -fast $name} result]
  } else {
    set err [catch {sc_base open $name} result]
  }
  if {$showProgress} { closeProgressWindow }
  if {$err} {
    return -code error $result
  } else {
    return $result
  }
}

### Close the active base.

proc ::file::Close {{base -1}} {
  # Remember the current base
  set current [sc_base current]
  if {$base < 0} { set base $current }
  # Switch to the base which will be closed, and check for changes:
  sc_base switch $base
  if {[sc_base inUse]} {
    set confirm [::game::ConfirmDiscard]
    if {$confirm == 2} { return }
    if {$confirm == 0} {
      ::game::Save
    }
    setTrialMode 0
    sc_base close
    # Siby: its PGN file (if any) forgotten: the slot may hold another
    # database next
    catch {::moderne::pgnfichier::ferme $base}

    bind . <Control-Key-$base> {}

    ### Need these here, as otherwise a db "open base as tree" window won't close. S.A.
    ## (hmmm - this line is making us switch to empty base instead of clipbase when tree is closed and is locked)
    # but placing it before the (following) ::file::SwitchToBase commands seems to fix eveything.
    if {[winfo exists .treeWin$base]} { destroy .treeWin$base }

    # If closing current base - reset current game and switch to clipbase
    if { $current == $base } {
      ::file::SwitchToBase clipbase
    } else {
      ::file::SwitchToBase $current
    }

    if {[info exists ::crosstabBase] && $base == $::crosstabBase} {
      ::crosstab::Refresh
    }

    if {[winfo exists .emailWin]} { destroy .emailWin }
  } else {
    updateMenuStates
    updateStatusBar
    updateTitle
  }
  refreshSearchDBs
  set ::glistStart($current) 1

  catch {
    # Update sorting vars for the gamelist titles
    if {$base == $current} {
      set glistSortedBy  [lindex $::glistSortColumn($base) 0]
      if {$glistSortedBy != {} } {
	.glistWin.tree heading $glistSortedBy -image {}
      }
    }
    unset ::glistSortColumn($base)
  }
}


proc ::file::SwitchToBase {b} {
  setTrialMode 0 0
  sc_base switch $b

  # Close Email windows whenever a base is closed/switched:
  # if {[winfo exists .treeWin$b]} { destroy .treeWin$b }
  if {[winfo exists .emailWin]} { destroy .emailWin }

  updateBoard -pgn -switch

  refreshWindows all
}

proc ::file::SwitchToNextBase {{dir 1}} {
  setTrialMode 0 0
  set b [sc_base current]
  set clipbase [sc_info clipbase]

  ### Rotate between bases until we find an open one.
  ### Switching to unopen bases seems silly, but this is old and tested (?) code from SCID
  while {1} {
    incr b $dir
    if {$b > $clipbase} {
      set b 1
    } elseif {$b < 1} {
      set b $clipbase
    }
    sc_base switch $b
    if {[sc_base inUse]} { break }
  }
  SwitchToBase $b
}


proc ::file::openBaseAsTree { { fName "" } } {
  setTrialMode 0 0
  set oldbase [sc_base current]

  if {[sc_base count free] == 0} {
    tk_messageBox -type ok -icon info -title Siby \
        -message [::moderne::tr "Trop de bases ouvertes : fermes-en une d'abord." "Too many databases are open; close one first"]
    return
  }

  if {$fName == ""} {
    if {[sc_info gzip]} {
      set ftype {
        { "Siby databases (.si4) and PGN" {".si4" ".si3" ".pgn" ".PGN" ".pgn.gz"} }
        { "Siby databases (.si4)" {".si4" ".si3"} }
        { "PGN files (.pgn)" {".pgn" ".PGN" ".pgn.gz"} }
      }
    } else {
      set ftype {
        { "Siby databases (.si4) and PGN" {".si4" ".si3" ".pgn" ".PGN"} }
        { "Siby databases (.si4)" {".si4" ".si3"} }
        { "PGN files (.pgn)" {".pgn" ".PGN"} }
      }
    }
    if {![file isdirectory $::initialDir(base)] || [file normalize $::initialDir(base)] eq [file normalize $::env(HOME)]} {
      set ::initialDir(base) [::file::dossierDefaut]
    }
    set fName [tk_getOpenFile -initialdir $::initialDir(base) -filetypes [::utils::trTypesFichiers $ftype] -title [::moderne::tr "Ouvrir une base Siby" "Open a Siby database"]]
    if {$fName == ""} { return }

    set fName [fullname $fName]
    set ::initialDir(base) [file dirname $fName]
    set ::initialDir(file) [file tail $fName]
  }


  if {[file extension $fName] == ""} {
    set fName "$fName.si4"
  }

  if {[file extension $fName] == ".si3" && [file exists $fName]} {
    ::file::Upgrade [file rootname $fName]
    return
  }

  ### Check it is not already open
  # Name handling is a little clumsy, but is tested
  if {[file extension $fName] == ".si4"} {
    set rName [file rootname $fName]
  } else {
    set rName $fName
  }
  for {set i 1} {$i <= [sc_base count total]} {incr i} {
    if {$rName == [sc_base filename $i]} {
      ::tree::Open $i
      return
    }
  }

  set err 0
  busyCursor .
  if {[file extension $fName] == ".si4"} {
    set fName [file rootname $fName]
    if {[catch {openBase $fName} result]} {
      unbusyCursor .
      set err 1
      tk_messageBox -icon warning -type ok -parent . -title [::moderne::tr "Siby : erreur d'ouverture du fichier" "Siby: Error opening file"] -message $result
      return
    } else {
      set ::initialDir(base) [file dirname $fName]
      set ::initialDir(file) [file tail $fName]
      ::recentFiles::add "$fName.si4"
    }
  } else {
    # PGN file:
    set result [::moderne::tr "Ce fichier n'est pas lisible." "This file is not readable."]
    if {(![file readable $fName])  || \
          [catch {sc_base create $fName true} result]} {
      unbusyCursor .
      set err 1
      tk_messageBox -icon warning -type ok -parent . -title [::moderne::tr "Siby : erreur d'ouverture du fichier" "Siby: Error opening file"] -message $result
      return
    } else {
      doPgnFileImport $fName [::moderne::tr "Ouverture de [file tail $fName] en lecture seule\n" "Opening [file tail $fName] read-only\n"]
      sc_base type [sc_base current] 3
      set ::initialDir(pgn) [file dirname $fName]
      set ::initialDir(file) [file tail $fName]
      ::recentFiles::add $fName
    }
  }
  unbusyCursor .

  set current [sc_base current]
  set ::glistFlipped([sc_base current]) 0
  ::tree::Open
  set ::tree(locked$current) 1

  ::file::SwitchToBase $oldbase
  refreshSearchDBs
}

### Scidb's Drag and Drop by Gregor Cramer
#   ported by Stevenaaus

proc RegisterDropEvents {target} {
  if {$::macOS} {return}
  ::tkdnd::drop_target register $target DND_Files
  bind $target <<DropEnter>> { HandleDropEvent enter %W}
  bind $target <<DropLeave>> { HandleDropEvent leave %W}
  bind $target <<Drop>> { HandleDropEvent %D %W}
}

proc HandleDropEvent {action window} {
  variable Defaults

  switch $action {
    enter  {}
    leave  {}
    default {
      # It is important that HandleDropEvent is returning as fast as possible.
      after idle [namespace code [list OpenUri $window $action]]
    }
  }

  return copy
}

proc OpenUri {window uriFiles} {

  if {[string match .glistWin* $window]} {
	 raiseWin .glistWin
  } else {
	 raiseWin .
  }
  update idletasks

  set errorList {}
  set rejectList {}
  set databaseList {}
  set filelist $uriFiles

  foreach file $filelist {
    set uri [string trimright $file]
    set file $uri
    if {[string length $file]} {
      if {[string equal -length 5 $file "file:"]} {
        if {[string equal -length 17 $file "file://localhost/"]} {
          # correct implementation
          set file [string range $file 16 end]
        } elseif {[string equal -length 8 $file "file:///"]} {
          # no hostname, but three slashes - nearly correct
          set file [string range $file 7 end]
        } elseif {[string index $file 5] eq "/"} {
          # theoretically, the hostname should be the first, but no one implements it
          set file [string range $uri 5 end]
          for {set n 1} {$n < 5} {incr n} { if {[string index $file $n] eq "/"} { break } }
          set file [string range $uri [expr {$n - 1}] end]

          if {![file exists $file]} {
            # perhaps a correct implementation with hostname?
            set i [string first "/" $file 1]
            if {$i >= 0} {
              set f [string range $file $i end]
              if {[file exists $f]} {
                # it seems so
                set file $f
              }
            }
          }
        } else {
          # no slash after "file:" - what is that for a crappy program?
          set file [string range $file 5 end]
        }
      }

      set file [file normalize $file]
    }

    if {[file exists $file]} {
      lappend databaseList $file
    } else {
      puts "Dnd: no such file $file"
    }
  }

  foreach file $databaseList {
    ::file::Open $file
  }

  if {[llength $errorList]} {
    if {[string match file:* $uriFiles] && [llength $databaseList] == 0} {
      set message [tr CannotOpenUri]
      if {[llength $errorList] > 10} {
        append message \n\n [join [lrange $errorList 0 9] \n]
        append message \n...
      } else {
        append message \n\n [join $errorList \n]
      }
    } else {
      set message [tr InvalidUri]
    }
    tk_messageBox -icon warning -type ok -parent . -message $message
  }

  if {[llength $rejectList]} {
    set message [tr UriRejected]
    if {[llength $rejectList] > 10} {
      append message \n\n [join [lrange $rejectList 0 9] \n]
      append message \n...
    } else {
      append message \n\n [join $rejectList \n]
    }
    set detail [tr UriRejectedDetail]
    append detail " .sci, .si4, .si3, .cbh, .pgn, .pgn.gz, .zip"
    tk_messageBox -icon info -type ok -parent . -message $message -detail $detail
  }

  if {[llength $databaseList] + [llength $rejectList] + [llength $errorList] == 0} {
    set message [tr EmptyUriList]
    tk_messageBox -icon info -type ok -parent . -message $message
  }
}


proc bgerror {err} {
  if {$err eq "selection owner didn't respond"} {
    set parent [::tkdnd::get_drop_target]
    if {[llength $parent] == 0} { set parent . }
    after idle [list tk_messageBox \
      -icon error \
      -parent $parent \
      -message [tr SelectionOwnerDidntRespond] \
    ]
  } elseif {[string match {*selection doesn't exist*} $err]} {
    # ignore this stupid message. this message appears
    # in case of empty strings. this is not an error!
  } elseif {[llength [info commands ::moderne::rapport::erreur]]} {
    # Siby: logged, and a report offered (moderne/menubar.tcl)
    ::moderne::rapport::erreur $err
  } else {
    ::tk::dialog::error::bgerror $err
  }
}

### end of file.tcl

