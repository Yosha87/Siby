#!/bin/sh

# Scid vs. PC
#
# Based on Shane's Chess Information Database
#
# Copyright Steven Atkinson (stevenaaus@yahoo.com) , Pascal Georges, Shane Hudson
# Released under the GPL
# This is freely redistributable software; see the file named "COPYING"
# or "copying.txt" that came with this program.

# The next line restarts using tkscid (Siby: script read as UTF-8): \
exec "`dirname "$0"`"/tkscid -encoding utf-8 "$0" "$@"

set scidVersion 4.27
set scidVersionDate {May 20, 2026}
# Siby's own version, the one shown to users (beta until the 1.0
# release); scidVersion above is the internal version of the database
# engine (checked against sc_info version), never shown
set sibyVersion "1.0 beta 3"

package require Tcl 8.5
package require Tk  8.5

# Siby: the window stays invisible during startup (menus, board and
# layout are being built); it is shown once ready, maximized
# (::moderne::revelerFenetre, end of end.tcl)
set ::moderne_demarrage 1
# built off-screen, at its final size (Windows needs a displayed
# window to place the layout's dividers)
wm geometry . "[winfo screenwidth .]x[expr {[winfo screenheight .] - 80}]+-30000+-30000"
if {$tcl_platform(platform) eq "windows"} {
  catch {wm attributes . -alpha 0.0}
  # (cloaked as soon as Windows has made the window: not even seen being
  # built in the taskbar's thumbnail, Yosha 2026-11-07; shown again by
  # ::moderne::montrerQuandPret)
  bind . <Map> {+if {"%W" eq "." && [info exists ::moderne_demarrage] && $::moderne_demarrage} { catch {sc_cacher [wm frame .] 1} }}
} else {
  wm withdraw .
}

# Siby: a small window while Siby starts (the main one is hidden until
# ready): the logo and a thin progress bar, gone when Siby appears
# (Yosha 2026-11-08). The bar moves at each step (it cannot move during a
# step: Siby is busy). Not for the test scenarios (SIBY_DEMARRAGE_BRUT).
namespace eval ::sibyDemarrage { variable largeur 240 }
proc ::sibyDemarrage::creer {} {
  if {[info exists ::env(SIBY_DEMARRAGE_BRUT)] && $::env(SIBY_DEMARRAGE_BRUT) ne {}} { return }
  # (for the measures: Siby's startup with and without it)
  if {[info exists ::env(SIBY_SANS_ACCUEIL)] && $::env(SIBY_SANS_ACCUEIL) ne {}} { return }
  set w .sibyDemarrage
  if {[winfo exists $w]} { return }
  variable largeur
  toplevel $w -background #000000 -highlightthickness 1 -highlightbackground #2a2a2a
  wm overrideredirect $w 1
  # (the logo: a copy of moderne/logos.tcl's siby 128, read before it loads)
  catch {
    image create photo ::sibyDemarrage::logo -format png -data {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}
    label $w.logo -image ::sibyDemarrage::logo -background #000000 -borderwidth 0
    # (Siby's logo as every window's icon from the start: Tk's feather
    # was seen in the taskbar while Siby started, Yosha 2026-11-08)
    catch {wm iconphoto . -default ::sibyDemarrage::logo}
    pack $w.logo -padx 60 -pady {30 20}
  }
  canvas $w.barre -width $largeur -height 3 -background #222222 -highlightthickness 0 -borderwidth 0
  $w.barre create rectangle 0 0 0 3 -fill #57c8ff -width 0 -tags plein
  pack $w.barre -padx 40 -pady {0 12}
  # (the copyright notice shown at the start: under the GPL, a modified
  # version of an interactive program that shows one must keep it, Yosha
  # 2026-11-09)
  label $w.droits -text "Siby © 2026 Yosha Iglesias · based on SCID vs. PC" -background #000000 -foreground #6a737b \
      -font TkSmallCaptionFont -borderwidth 0
  pack $w.droits -pady {0 14}
  update idletasks
  # (its size known from its content: on Windows the window had no size
  # yet when read, its corner went to the middle of the screen and the
  # window to the bottom right, Yosha 2026-11-08)
  set l [winfo reqwidth $w] ; set h [winfo reqheight $w]
  set lMin [expr {$largeur + 2 * 40 + 2}]
  if {[catch {image height ::sibyDemarrage::logo} hLogo]} { set hLogo 0 }
  set hMin [expr {$hLogo + 30 + 20 + 3 + 12 + [winfo reqheight $w.droits] + 14 + 2}]
  if {$l < $lMin} { set l $lMin }
  if {$h < $hMin} { set h $hMin }
  set x [expr {([winfo screenwidth $w] - $l) / 2}]
  set y [expr {([winfo screenheight $w] - $h) / 2}]
  wm geometry $w ${l}x${h}+$x+$y
  update idletasks
  # (Windows: centred again by Windows itself, in its own pixels; with the
  # screen scaled, Tk's centre was off, Yosha 2026-11-08)
  if {$::tcl_platform(platform) eq "windows"} {
    catch {variable centre [sc_centrer [wm frame $w]]}
    update idletasks
  }
  variable geoCreee [list [winfo rootx $w] [winfo rooty $w] [winfo width $w] [winfo height $w]]
  catch {variable reelCreee [sc_centrer [wm frame $w] read]}
}

### Windows: centred again once shown and laid out (at 125 % the window was
### seen off centre, to the bottom right, Yosha 2026-11-09)
proc ::sibyDemarrage::recentrer {} {
  set w .sibyDemarrage
  if {![winfo exists $w] || $::tcl_platform(platform) ne "windows"} { return }
  catch {variable centre [sc_centrer [wm frame $w]]}
}
proc ::sibyDemarrage::avancer {pct} {
  set w .sibyDemarrage
  if {![winfo exists $w]} { return }
  variable largeur
  $w.barre coords plein 0 0 [expr {$largeur * min(100, $pct) / 100}] 3
  # (the first steps: centred again, the window now really shown)
  variable recentre
  if {![info exists recentre] || $recentre < 3} {
    incr recentre
    recentrer
  }
  # (drawn at once only while the scripts load, when nothing else would
  # draw it; later Siby draws it between two steps: forcing it then laid
  # out the hidden main window too, Siby came about 1 s later)
  if {$pct <= 50} { update idletasks }
}
proc ::sibyDemarrage::fin {} {
  # (where it was, in siby.log: its place once made, after Windows' centring,
  # and at the end, with the screen; to see what moved it)
  set w .sibyDemarrage
  catch {
    variable geoCreee
    variable centre
    set reel {}
    catch {set reel [sc_centrer [wm frame $w] read]}
    variable reelCreee
    ::moderne::journal "Startup window: made at [expr {[info exists geoCreee] ? $geoCreee : {?}}], centred [expr {[info exists centre] ? $centre : {-}}], last at [list [winfo rootx $w] [winfo rooty $w] [winfo width $w] [winfo height $w]], screen [winfo screenwidth $w]x[winfo screenheight $w], tk scaling [tk scaling]; Windows: at start {[expr {[info exists reelCreee] ? $reelCreee : {}}]}, at the end {$reel}"
  }
  catch {destroy .sibyDemarrage}
}
catch ::sibyDemarrage::creer
catch {::sibyDemarrage::avancer 5}
# (safeguard: shown after 60 s at the latest)
after 60000 {catch ::moderne::revelerFenetre}

# Determine operating system platform: unix or windows

set windowsOS	[expr {$tcl_platform(platform) == "windows"}]
set unixOS	[expr {$tcl_platform(platform) == "unix"}]

# Siby on Windows: one Siby at a time. A second start (a .pgn or .si4
# double-clicked while Siby is open, or Siby started again) hands its files
# to the Siby already open, which comes to the front, and stops there (DDE,
# Tk's own mechanism on Windows; 2026-11-01). SIBY_INSTANCES_MULTIPLES=1
# (tests) lets several run.
set ::sibyRecus {}
if {$windowsOS && ![info exists env(SIBY_INSTANCES_MULTIPLES)] && ![catch {package require dde}]} {
  set fichiersArg {}
  foreach a $argv {
    if {[string index $a 0] in {- /}} { continue }
    if {[file exists $a]} { lappend fichiersArg [file normalize $a] }
  }
  if {[llength [dde services TclEval Siby]]} {
    if {![catch {dde execute -async TclEval Siby \
        "lappend ::sibyRecus [list $fichiersArg] ; catch ::moderne::systeme::recevoir"}]} {
      exit 0
    }
  }
  catch {dde servername Siby}
  unset fichiersArg
}

# debugging a procedure (can affect performance/toolbar)
if {0} {
  set procname update

  rename $procname oldprocname
  proc $procname {args} {
    if {$::windowsOS} {
      catch {::splash::add "$procname $args"}
    } else {
      puts "$::procname $args ([info  level [expr [info level] -1]])"
    }
    eval oldprocname $args
  }
}

if {![catch {tk windowingsystem} wsystem] && $wsystem == "aqua"} {
  # Note - we don't currently support installing on Mac in the unix fashion (ie /usr)
  set macOS 1
  set macCocoa [expr {!("AppKit" ni [winfo server .])}]
  # set macCarbon [string match QD* [winfo server .]]
  set scidName {Siby}
  if {[file isdirectory /usr/local/bin]} {
    # Wish does not use the Bash path for some reason
    set env(PATH) $env(PATH):/usr/local/bin
  }
  catch {
    # Thanks to Francois for this hack to add treeview Control-Button-1 bindings to the gamelist
    event add <<ToggleSelection>> <Control-ButtonPress-1>
  }
} else {
  set macOS 0
  set macCocoa 0
  set scidName {Siby}
}

# Check that on Unix, the version of tkscid matches the version of this
# script or on Windows, that the scid.exe and scid.gui versions are identical.

if {[string compare [sc_info version] $scidVersion]} {
  wm withdraw .
  if {$windowsOS} {
    set msg "This is $::scidName version [sc_info version], but the scid.gui data\n"
    append msg "file has the version number $scidVersion.\n"
  } else {
    set msg "This is $::scidName version $scidVersion,\nbut the "
    append msg "tkscid program \nit uses is version [sc_info version].\n"
    append msg "Check that the path to tkscid is correct."
  }
  tk_messageBox -type ok -icon error -title "Siby: version error" -message $msg
  exit 1
}

#############################################################
#
# NAMESPACES
#
# The main Tcl/Tk namespaces used in the Scid application are
# initialized here, so that default values can be set up and
# altered when the user options file is loaded.
#
foreach ns {
  ::splash
  ::utils
  ::utils::date ::utils::font ::utils::history ::utils::pane ::utils::string
  ::utils::sound ::utils::validate ::utils::win
  ::file
  ::file::finder ::file::maint ::maint
  ::bookmarks
  ::edit
  ::game
  ::gbrowser
  ::search
  ::search::filter ::search::board ::search::header ::search::material
  ::windows
  ::windows::gamelist ::windows::stats ::tree ::tree::mask ::windows::tree
  ::windows::switcher ::windows::eco ::crosstab ::pgn ::book
  ::tools
  ::tools::analysis ::tools::email
  ::tools::graphs
  ::tools::graphs::filter ::tools::graphs::absfilter ::tools::graphs::rating ::tools::graphs::score
  ::tb ::optable
  ::board ::move
  ::tacgame ::sergame ::opening ::tactics ::calvar ::uci ::fics
  ::config ::docking
  ::commenteditor
} {
  namespace eval $ns {}
}

### ::pause is used as a semaphore by the trace command in tacgame (and fics)

set ::MAX_GAMES [sc_info limit games]
set ::pause 0
set ::defaultBackground white
set ::defaultForeground black
# custom SelectColor colors (if available)
set ::bwidgetBackgrounds {#ffffff #ffffff #ffffff #ffffff #ffffff #ffffff #ffffff #ffffff #ffffff #ffffff #ffffff #ffffff}
set ::defaultGraphBackground white
set ::enableBackground 0
set ::enableForeground 0
set ::tacgame::threshold 0.9
set ::tacgame::levelMin 1200
set ::tacgame::levelMax 2200
set ::tacgame::levelFixed 1500
set ::tacgame::randomLevel 0
set ::tacgame::showblunder 1
set ::tacgame::showblundervalue 1
set ::tacgame::showblunderfound 1
set ::tacgame::showmovevalue 1
set ::tacgame::showevaluation 1
set ::tacgame::isLimitedAnalysisTime 1
set ::tacgame::analysisTime 10
set ::tacgame::openingType new
set ::tacgame::chosenOpening 0
set ::sergame::bookToUse {}
set ::sergame::useBook 1
set ::sergame::startFromCurrent 0
set ::sergame::timeMode movetime
set ::sergame::movetime 6
set ::sergame::current 0
set ::sergame::chosenOpening 0
set ::sergame::isOpening 0
set ::sergame::btime 300000
set ::sergame::wtime 3
set ::sergame::btime 3
set ::sergame::winc 2
set ::sergame::binc 2
set ::commenteditor::showBoard 1
set ::windows::gamelist::widths {}
set ::windows::gamelist::findcase 1
set ::windows::gamelist::showButtons 1
set ::windows::gamelist::customFont 0
set ::windows::gamelist::currColor blue2
set ::windows::switcher::icons 1
set ::windows::switcher::confirmCopy 1
set ::file::finder::data(dir) $::env(HOME)
set ::file::finder::data(sort) name
set ::file::finder::data(recurse) 0
set ::file::finder::data(Scid) 1
set ::file::finder::data(PGN) 1
set ::file::finder::data(EPD) 1
set ::file::finder::data(Old) 1
set ::tools::graphs::absfilter::type year
set ::tools::graphs::filter::type year
set ::tools::graphs::showpoints 1
set ::tools::graphs::spelling 0
set ::tools::graphs::showbar [expr ! $::macOS] ; # too slow on macs
set ::tools::graphs::type Auto
set ::tools::graphs::rating::year 1900
set ::tools::graphs::rating::elo 0
set macWheelMouse 1
set annotate(addTag) 1
set annotate(Moves) all
set annotate(WithVars) blunders
set annotate(WithScore) allmoves
set annotate(MissedMates) 1
set annotate(VarAtEnd) 1
set annotate(WantedDepth) 13
set annotate(Depth) 1
set useAnalysisBook 0
set annotate(isVar) 0
set annotate(scoreType) {+ 1.5}
set annotate(blunder) 1.0
set annotate(cutoff) 5.0
set maintFlag W
set ::gbrowser::size 35
set ::gbrowser::showEval 0
set comp(timecontrol) pergame
set comp(seconds) 180
set comp(base) 60
set comp(incr) 1
set comp(timeout) 0 ;# disabled by default
set comp(name) $scidName
set comp(rounds) 2
set comp(showclock) 0
set comp(debug) 1 ; # print info to console
set comp(animate) 1
set comp(type) Normal
set comp(ponder) 0
set comp(usebook) 0
set comp(book) {}
set comp(scoreType) No ; # add engine scores as comments
set comp(start) Normal
set photosMinimized 0
set bookmarks(gamehistory) {}
set playerInfoHistory {}
set epdAnnotateMode 0
set epdDelay 3
set evalTime 200 ;# milliseconds for  sc_pos analyze
set evalScale 5
set evalTicks 0
set evalUseLog 0

set defaultDBs {}
set tbOnline Lichess   ;# Siby: Lichess online tablebase (originally Nalimov)

proc ::docking::init_layout_list {{recover 0}} {
  # Default window docking layouts
  array set ::docking::layout_list {}

  # Basic layout : PGN window with main board
  set ::docking::layout_list(1) {{MainWindowGeometry 834x640+80+50} {{.pw vertical {}} {TPanedwindow {{.pw.pw0 horizontal 564} {TNotebook .nb .fdockmain} {TNotebook .tb1 .fdockpgnWin}}}}}

  if {$recover} {
    return
  }

  set ::docking::layout_list(2)  {{MainWindowGeometry 1311x716+65+36} {{.pw vertical {}} {TPanedwindow {{.pw.pw0 horizontal 570} {TNotebook .nb .fdockmain} {TPanedwindow {{.pw.pw0.pw2 vertical 261} {TPanedwindow {{.pw.pw0.pw2.pw9 horizontal 235} {TNotebook .tb32 .fdockpgnWin} {TPanedwindow {{.pw.pw0.pw2.pw9.pw30 vertical {}} {TNotebook .tb1 {.fdockplayerInfoWin .fdockcommentWin}}}}}} {TPanedwindow {{.pw.pw0.pw2.pw3 horizontal {}} {TNotebook .tb8 {.fdockglistWin .fdockcrosstabWin}}}}}}}}}}

  set ::docking::layout_list(3) {{MainWindowGeometry 968x666+80+50} {{.pw vertical {}} {TPanedwindow {{.pw.pw0 horizontal 566} {TNotebook .nb .fdockmain} {TPanedwindow {{.pw.pw0.pw2 vertical 363} {TNotebook .tb1 {.fdockanalysisWin1 .fdockpgnWin}} {TNotebook .tb3 {.fdocktreeWin1 .fdocktreeBest1}}}}}}}}
  set ::docking::layout_list(4) {{MainWindowGeometry 1449x817+76+30} {{.pw vertical {}} {TPanedwindow {{.pw.pw0 horizontal 747} {TNotebook .nb .fdockmain} {TPanedwindow {{.pw.pw0.pw2 vertical {}} {TPanedwindow {{.pw.pw0.pw2.pw3 horizontal {}} {TPanedwindow {{.pw.pw0.pw2.pw3.pw35 vertical 378} {TPanedwindow {{.pw.pw0.pw2.pw3.pw35.pw38 horizontal 347} {TNotebook .tb36 {.fdockpgnWin .fdockcommentWin}} {TNotebook .tb39 {.fdockanalysisWin0 .fdockplayerInfoWin .fdocktreeWin1}}}} {TNotebook .tb8 {.fdockglistWin .fdocksgraph .fdockcrosstabWin}}}}}}}}}}}}
  set ::docking::layout_list(5) {}
}

::docking::init_layout_list

### Tree/mask options:
set ::tree::showBar [expr {! $::macOS}]
set ::tree::showFrame 1
set ::tree::sortBest 1
set ::tree::short 1
set ::tree::autoAdjust 0
set ::tree::mask::recentMask {}
set ::tree::mask::autoLoadMask 0
set ::tree::mask::showMarkers 0
set ::tree::mask::tooltips 1
set ::tree::order frequency
# Auto-save tree cache when closing tree window:
set ::tree::autoSave 0

set cleaner(players) 1
set cleaner(events) 1
set cleaner(sites) 1
set cleaner(rounds) 1
set cleaner(eco) 1
set cleaner(elo) 1
set cleaner(twins) 1
set cleaner(cnames) 0
set cleaner(cgames) 0
set cleaner(tree) 0

#############################################################
# Customisable variables:

# scidExeDir: contains the directory of the Scid executable program.
# Used to determine the location of various relative data directories.
set scidExecutable [info nameofexecutable]

if {$scidExecutable == {}} {
  ### Shit. Wish8.6b2 returns {}
  if {$macOS} {
    set scidExecutable /Applications/ScidvsMac.app/Contents/MacOS/scid
    puts "scidExecutable is null. Now is \"$scidExecutable\""
  } elseif {$unixOS} {
    catch {
      set scidExecutable [exec readlink /proc/[pid]/exe]
    }
    puts "scidExecutable is null. Now is \"$scidExecutable\""
  } else {
    puts "scidExecutable is null"
  }
}

if {$scidExecutable == {}} {
  ### may work on windows, but will be broken on other OS
  set scidExeDir .
} else {
  if {[file type $scidExecutable] == "link"} {
    set scidExeDir [file dirname [file readlink $scidExecutable]]
    if {[file pathtype $scidExeDir] == "relative"} {
      set scidExeDir [file dirname [file join [file dirname $scidExecutable]\
	[file readlink $scidExecutable]]]
    }
  } else {
    set scidExeDir [file dirname $scidExecutable]
  }
}

# scidUserDir: location of user-specific Scid files.
# This is "~/.scid" on Unix, and the Scid exectuable dir on Windows.

### Siby: the user's documents (Gaby, their databases, and on Windows their
### settings) in Documents/Siby, which a new version of Siby does not
### replace; they were in the program's folder on Windows (2026-10-31).
### SIBY_DOCUMENTS gives another folder (tests).
proc ::sibyDossierDocuments {} {
  if {[info exists ::env(SIBY_DOCUMENTS)] && $::env(SIBY_DOCUMENTS) ne {}} {
    return [file normalize $::env(SIBY_DOCUMENTS)]
  }
  set docs {}
  if {$::windowsOS} {
    catch {
      package require registry
      set docs [registry get {HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders} Personal]
    }
    if {$docs eq {} && [info exists ::env(USERPROFILE)]} { set docs [file join $::env(USERPROFILE) Documents] }
  } else {
    # (the Documents folder of the session, whatever its name in the
    # desktop's language; xdg-user-dir gives the home folder when unset)
    catch {set docs [string trim [exec xdg-user-dir DOCUMENTS]]}
    if {$docs eq {} || [file normalize $docs] eq [file normalize ~]} { set docs [file join ~ Documents] }
  }
  if {$docs eq {}} { set docs ~ }
  return [file normalize [file join $docs Siby]]
}

### Moves the items of folder ancien matching motifs into nouveau, once (an
### item already there is left), then puts the new paths in the settings
### files of dossierConfig. Gaby on another disk stays where it is (too big
### to copy at startup): the settings keep pointing to it.
proc ::sibyDemenager {ancien nouveau motifs dossierConfig} {
  set ancien [file normalize $ancien]
  set nouveau [file normalize $nouveau]
  if {$ancien eq $nouveau || ![file isdirectory $ancien]} { return }
  set deplaces {}
  foreach m $motifs {
    foreach src [glob -nocomplain -directory $ancien $m] {
      set dst [file join $nouveau [file tail $src]]
      if {[file exists $dst]} { continue }
      if {[catch {file mkdir $nouveau}]} { return }
      if {[catch {file rename $src $dst}]} {
        if {[file isdirectory $src] && [file tail $src] eq "Gaby"} { continue }
        if {[catch {file copy $src $dst}]} { catch {file delete -force $dst} ; continue }
        # (the old one cannot be removed, e.g. a file in use: the copy is
        # removed, never two of them)
        if {[catch {file delete -force $src}]} { catch {file delete -force $dst} ; continue }
      }
      lappend deplaces $src $dst
    }
  }
  if {![llength $deplaces]} { return }
  set carte {}
  foreach {a n} $deplaces {
    lappend carte $a $n [file nativename $a] [file nativename $n]
  }
  foreach f [glob -nocomplain -directory $dossierConfig -types f *.dat] {
    if {[catch {
      set c [open $f r] ; fconfigure $c -encoding utf-8 ; set t [read $c] ; close $c
      set t2 [string map $carte $t]
      if {$t2 ne $t} { set c [open $f w] ; fconfigure $c -encoding utf-8 ; puts -nonewline $c $t2 ; close $c }
    }]} { catch {close $c} }
  }
  catch {
    set c [open [file join $nouveau "moved-from-[file tail $ancien].txt"] a]
    puts $c "[clock format [clock seconds]]: $deplaces"
    close $c
  }
}

set sibyDocsDir [::sibyDossierDocuments]
catch {file mkdir $sibyDocsDir}

if {$windowsOS} {
  # Siby: the user's files in Documents\Siby; once, those of an older
  # version, kept in the program's folder, are moved there (the new
  # version unpacked over the old one)
  set scidUserDir $sibyDocsDir
  if {![file exists [file join $scidUserDir config options.dat]] && [file exists [file join $scidExeDir config options.dat]]} {
    catch {::sibyDemenager $scidExeDir $scidUserDir \
        {config Gaby gaby-update {Siby games.*} {Siby live.*} bilans couvertures engines photos pieces textures \
         recuperation-*.pgn toby_annotation.log lenteurs.log} [file join $scidUserDir config]}
    # (in data, the user's files only: the program's own stay)
    catch {::sibyDemenager [file join $scidExeDir data] [file join $scidUserDir data] \
        {enligne prepa repetition_*.dat evaluations.dat *.spf Correspondence.* Inbox Outbox connector.xml Plugins} \
        [file join $scidUserDir config]}
  }

  # Need to cd here to open eco and spellfiles
  #   Probably only has any effect when opening a pgn/si4 file by double clicking on it,
  #   whence the CWD is not "."
  cd $scidExeDir
  # Windows has problems with "cmd.exe /c start" and spaces in file names "Documents and Settings"
  # so choose something dumb
  set scidLogDir {C:\log}
} else {
  set scidUserDir [file nativename "~/.scidvspc"]
  set scidLogDir [file nativename [file join $scidUserDir "log"]]
  # Siby: Gaby and the user's databases in ~/Documents/Siby (settings stay
  # in ~/.scidvspc); once, those kept in ~/.scidvspc are moved there
  catch {::sibyDemenager $scidUserDir $sibyDocsDir {Gaby {Siby games.*} {Siby live.*}} [file join $scidUserDir config]}
}

# scidConfigDir, scidDataDir, scidLogDir:
#   Location of Scid configuration, data and log files.
set scidConfigDir [file nativename [file join $scidUserDir "config"]]
set scidDataDir [file nativename [file join $scidUserDir "data"]]
set scidTexturesDir [file nativename [file join $scidUserDir "textures"]]
set scidPiecesDir [file nativename [file join $scidUserDir "pieces"]]
set scidPhotosDir [file nativename [file join $scidUserDir "photos"]]

# boardSizes: sizes after 80 are copied rom smaller ones
set boardSizes [list 25 30 35 40 45 50 55 60 65 70 75 80 90 100 110 120 130 140 150 160]

#load textures for lite and dark squares
set boardfile_dark "emptySquare"
set boardfile_lite "emptySquare"

#[file join $scidExeDir "bitmaps" "empty.gif"] ;# wsquare.gif

# boardSize: Default board size. See the available board sizes above.
set boardSize 60

# language for help pages and messages:
set language E
### Siby: English by default; French is chosen in Options › Language (and
### saved). SIBY_LANG=F (or E) forces a language, for tests.
if {[info exists ::env(SIBY_LANG)] && $::env(SIBY_LANG) in {E F}} { set language $::env(SIBY_LANG) }
set oldLang X

# Toolbar configuration/default visibility
set bigToolbar 0
foreach {tbicon status}  {
  new 0 open 0 save 1 close 0
  finder 0 bkm 1 gfirst 1 gprev 1 gnext 1 glast 1
  newgame 0 copy 0 paste 0
  rfilter 0 bsearch 0 hsearch 0 msearch 0
  ginfo 1 glist 1 pgn 1 tmt 1 comment 0 maint 1 eco 0 tree 1 crosst 1 engine 1 book 1
} {
  set toolbar($tbicon) $status
}

# boardCoords: 1 to show board Coordinates, 0 to hide them.
set boardCoords 0

# boardSTM: 1 to show side-to-move icon, 0 to hide it.
set boardSTM 1

# Default values for fonts:
proc createFont {name} {
  set opts $::fontOptions($name)
  font create font_$name \
      -family [lindex $opts 0] -size [lindex $opts 1] \
      -weight [lindex $opts 2] -slant [lindex $opts 3]
}

proc configureFont {name} {
  set opts $::fontOptions($name)
  font configure font_$name \
      -family [lindex $opts 0] -size [lindex $opts 1] \
      -weight [lindex $opts 2] -slant [lindex $opts 3]
}

proc reinitFont {name} {
  set ::fontOptions($name) $::fontOptions(old$name)
  configureFont $name
}

if {$windowsOS} {
  set fontOptions(Regular) { Arial           10 normal roman}
  set fontOptions(Menu)    { {MS Sans Serif}  9 normal roman}
  set fontOptions(Small)   { Arial            9 normal roman}
  set fontOptions(Tiny)    { Arial            7 normal roman}
  set fontOptions(Fixed)   { Courier          9 normal roman}
} elseif {$macOS} {
  set fontOptions(Regular) { {Lucida Grande} 12 normal roman}
  set fontOptions(Menu)    { {Lucida Grande} 14 normal roman}
  set fontOptions(Small)   { {Lucida Grande} 11 normal roman}
  set fontOptions(Tiny)    { {Lucida Grande}  9 normal roman}
  set fontOptions(Fixed)   { Monaco 10 normal roman}
} else {
  set fontOptions(Regular) { helvetica 11 normal roman}
  set fontOptions(Menu)    { helvetica 10 normal roman}
  set fontOptions(Small)   { helvetica 10 normal roman}
  set fontOptions(Tiny)    { helvetica  8 normal roman}

  # try a couple of fonts, and default to "fixed" if no luck
  if {[lsearch [font families] {Liberation Mono}] > 0} {
    set fontOptions(Fixed)   { {Liberation Mono} 11 normal roman}
  } elseif {[lsearch [font families] {Courier 10 Pitch}] > 0} {
    set fontOptions(Fixed)         { {Courier 10 Pitch} 12 normal roman}
  } else {
    set fontOptions(Fixed)   { fixed 11 normal roman}
  }
}

### Siby: modern default fonts (first available font)
if {$unixOS && !$macOS} {
  proc ::moderne_premierePolice {candidats defaut} {
    set familles [font families]
    foreach f $candidats {
      if {[lsearch -exact $familles $f] >= 0} { return $f }
    }
    return $defaut
  }
  set _sans [::moderne_premierePolice {Inter {Noto Sans} Cantarell Ubuntu {DejaVu Sans}} helvetica]
  set _mono [::moderne_premierePolice {{JetBrains Mono} {Noto Sans Mono} {DejaVu Sans Mono} {Liberation Mono}} fixed]
  set fontOptions(Regular) [list $_sans 11 normal roman]
  set fontOptions(Menu)    [list $_sans 11 normal roman]
  set fontOptions(Small)   [list $_sans 10 normal roman]
  set fontOptions(Tiny)    [list $_sans  9 normal roman]
  set fontOptions(Fixed)   [list $_mono 10 normal roman]
  unset _sans _mono
}
if {$windowsOS} {
  # Segoe UI (Windows 7 and later), Consolas for the fixed font
  set fontOptions(Regular) [list {Segoe UI} 10 normal roman]
  set fontOptions(Menu)    [list {Segoe UI} 10 normal roman]
  set fontOptions(Small)   [list {Segoe UI}  9 normal roman]
  set fontOptions(Tiny)    [list {Segoe UI}  8 normal roman]
  set fontOptions(Fixed)   [list Consolas 10 normal roman]
}
### End Siby

createFont Regular
createFont Menu
createFont Small
createFont Tiny
createFont Fixed

# Analysis command: to start chess analysis engine.
set analysisCommand ""
set analysis(boardEngine) 0

# Maximum number of lines to be saved in a log file
# (setting it to 0 also stops log file being created)
set analysis(logMax) 5000
set analysis(logName) 1
set analysis(maxPly) 0
set analysis(lowPriority) $::windowsOS
set analysis(wrapPV) 0
set analysis(showBoard) 0
set analysis(showEngineInfo) 0
set analysis(boardSize) 2
set analysis(boardType) Arrows
set analysis(boardSeqNumColor) black
set analysis(boardSeqCount) 3
set analysis(numberPVArrows) 1

# Colors

set lite        #f3f3f3
set dark        #7389b6		;# dark and lite square colors
set highcolor   #b0d0e0		;# color when something is selected
set bestcolor   #bebebe		;# suggested move square
set bgcolor     grey20		;# board (canvas) bg color, appears as the lines between the squares
set progcolor   rosybrown	;# progress bar
set buttoncolor #b0c0d0		;# (below)
set maincolor   black		;# Main line arrow color
set varcolor    grey80		;# Variation arrow colors
set squarecolor black           ;# box alternative to highcolor
# arrowWidth/Length is no longer under ::mark namespace to avoid version conflict when sourcing options.dat
set ::board::arrowWidth 2
set ::board::arrowLength 0.6
set ::board::enableMPVTls 0	;# enable Hanish's MPV traffic-light bar
set engineLineColor $maincolor  ;# Engine arrows
set whiteLineColor white
set blackLineColor grey50
set rowcolor    lightsteelblue1 ;# Tree/Crosstab/Book line/row bg color
set highlightcolor gray85       ;# Nameditor /playerinfo/ crosstable player name highlight colour
set switchercolor lightsteelblue3 ;# DB switcher
set crosscolor  grey80		;# Crosstable line colouring
set scorecolor  steelblue	;# Score Graph bars
set scorebarcolor  grey10	;# Score Graph current move

set borderwidth 1

# Set the radiobutton and checkbutton background color if desired.
# I find the maroon color on Unix ugly!
if {$unixOS} {
  option add *Radiobutton*selectColor $buttoncolor
  option add *Checkbutton*selectColor $buttoncolor
  # option add *Menu*selectColor $buttoncolor
}

set ::tactics::analysisTime 3
set ::opening::DisplayCMValue 0
set ::opening::displayCM 0
set ::opening::displayOpeningStats 1
set ::opening::maxDepth 10
set ::opening::removeGames 0

# Defaults for the PGN window:
# if ::pgn::showColor is 1, the PGN text will be colorized.
set ::pgn::showColor 1
set ::pgn::indentVars 1
set ::pgn::indentComments 1
set ::pgn::symbolicNags 1
set ::pgn::moveNumberSpaces 0
set ::pgn::shortHeader 1 ;# Siby: short header (not the raw PGN headers)
set ::pgn::boldMainLine 0
set ::pgn::columnFormat 0
set ::pgn::stripMarks 0
set ::pgn::showScrollbar 1
set ::pgn::prevOffset 0
set pgnColor(Header) "\#00008b"
set pgnColor(Main) "\#000000"
set pgnColor(Var) "\#0000ee"
set pgnColor(Nag) "\#aa2c2c" ;# ee0000
set pgnColor(Comment) "\#008b00"
set pgnColor(Current) lightSteelBlue
set pgnColor(NextMove) "\#fefe80"
set pgnColor(Background) "\#ffffff"

array set findopponent {}

proc initFICSDefaults {} {
  namespace eval fics {
    set use_timeseal 0
    set use_zseal 0
    set zseal_exec ""
    if {$::macOS} {
      set timeseal_exec "$::scidExeDir/timeseal"
    } else {
      if {$::windowsOS} {
	set timeseal_exec "$::scidExeDir/timeseal.exe"
      } else {
	set timeseal_exec "timeseal"
      }
    }
    set server        freechess.org
    set port_fics     5000
    set port_timeseal 5001
    set login         ""
    set password      ""
    # wtf is this necessary
    set findopponent(initTime) 10
    set findopponent(incTime)  0
    set findopponent(rated)    unrated
    set findopponent(color)    auto
    set findopponent(limitrating) 0
    set findopponent(rating1)  1000
    set findopponent(rating2)  1500
    set findopponent(manual)   auto
    set findopponent(formula)  ""
    set consolebg grey35
    set consolefg LimeGreen
    set chanoff 1
    set shouts 1
    set server_ip   0.0.0.0
    set autopromote 0
    set storeclk 1
    set autoraise 1
    set size 2
    set sound 0
    set no_results 0
    set no_requests 0
    set showEval 1

    proc initUserButtons {} {
      set ::fics::user_buttons {FICSInfo FICSOpponent Abort}
      set ::fics::user_commands {
	{::fics::writechan finger ; ::fics::writechan "inchannel $::fics::reallogin"}
	{if {$::fics::opponent != {}} { ::fics::writechan "finger $::fics::opponent" }}
	{::fics::writechan "abort"}
      }
    }

    initUserButtons
    # these are duplicated in fics::editInitCommands
    set init_commands [list \
      {set gin  0} \
      {set echo 1} \
      {set seek 0} \
    ]
    set show_buttons 1
    set allow_premove 1
  }
}

initFICSDefaults

# Defaults for initial directories:
set initialDir(base) $::env(HOME)
set initialDir(pgn)  $::env(HOME)
set initialDir(book) $::env(HOME)
set initialDir(epd)  $::env(HOME)
set initialDir(html) $::env(HOME)
set initialDir(tex)  $::env(HOME)
set initialDir(stm)  $::env(HOME)
set initialDir(sso)  $::env(HOME)
set initialDir(sff)  $::env(HOME)
set initialDir(report) $::env(HOME)
set initialDir(tablebase1) ""
set initialDir(tablebase2) ""
set initialDir(tablebase3) ""
set initialDir(tablebase4) ""

# glistSize: Number of games displayed in the game list window
set glistSize 15

# glexport: Format for saving Game List to text file.
set glexportDefault "g6: w13 W4  b13 B4  r3:m2 y4 s11 o4"
set glexport $glexportDefault

# Default window locations:
foreach i {. .main .pgnWin .helpWin .crosstabWin .treeWin .commentWin .glist \
      .playerInfoWin .baseWin .treeBest .tourney .finder \
      .ecograph .statsWin .glistWin .maintWin .nedit} {
  set winX($i) -1
  set winY($i) -1
}

for {set b 1} {$b<=[sc_base count total]} {incr b} {
  foreach i {.treeWin .treeBest} {
    set winX($i$b) -1
    set winY($i$b) -1
  }
}

# Default PGN window size:
set winWidth(.pgnWin)  65
set winHeight(.pgnWin) 20

# Default help window size:
set winWidth(.helpWin)  50
set winHeight(.helpWin) 32

# Default stats window size:
set winWidth(.statsWin) 60
set winHeight(.statsWin) 13

# Default crosstable window size:
set winWidth(.crosstabWin)  75
set winHeight(.crosstabWin) 15

# Default tree window size:
set winWidth(.treeWin)  58
set winHeight(.treeWin) 20

# Default comment editor size:
set winWidth(.commentWin)  40
set winHeight(.commentWin)  6

# Default spellcheck results window size:
set winWidth(.spellcheckWin)  55
set winHeight(.spellcheckWin) 25

# Default player info window size:
set winWidth(.playerInfoWin)  45
set winHeight(.playerInfoWin) 20

# Default switcher window size:
set winWidth(.baseWin) 310
set winHeight(.baseWin) 110

# Default Correspondence Chess window size:
set winWidth(.ccWindow) 10
set winHeight(.ccWindow) 20

# Default stats window lines:
array set ::windows::stats::display {
  r2600 1
  r2500 0
  r2400 1
  r2300 0
  r2200 1
  r2000 1
  r1800 0
  y1900 0
  y1950 0
  y1960 0
  y1970 0
  y1980 0
  y1990 0
  y2000 1
  y2005 1
  y2010 1
}

# Enable stats for subsequent years
for { set year [clock format [clock seconds] -format {%Y}] } \
    { $year > 2010 && ![info exists ::windows::stats::display([subst {y$year}])] } \
    { incr year -1 } {
      set ::windows::stats::display([subst {y$year}]) 1
    }

# Default PGN display options:
set pgnStyle(Tags) 1
set pgnStyle(Comments) 1
set pgnStyle(Vars) 1

# Auto-save options when exiting:
set optionsAutoSave 1

#  Numeric locale: first char is decimal, second is thousands.
#  Example: ".," for "1,234.5" format; ",." for "1.234,5" format.
set locale(numeric) ".,"

# Ask for piece translations (first letter)
set translatePieces 1

set colorActiveSquare 0

# Hightlight the last move played
set highlightLastMove 1
set highlightLastMoveWidth 3
set highlightLastMoveColor grey
set highlightLastMovePattern {} ; # unused, and also not saved

# Ask before replacing existing moves: on by default
set askToReplaceMoves 0 ;# Siby: new variation without asking (Ctrl + move: dialog)

# Show suggested moves
set suggestMoves 0

# Show variations popup window, arrows
# (Siby: on, as in ChessBase: where there are variations, "forward" offers
# the choice of the move)
set showVarPopup 1
# (Siby: off, as on Lichess; with it, the first "forward" on a move with
# variations draws arrows instead of playing the move)
set showVarArrows 0
namespace eval ::moderne {}
set ::moderne::flechesVariantesVues 0

# Keyboard Move entry options:
set moveEntry(On) 1
set moveEntry(AutoExpand) 0
set moveEntry(Coord) 1

# Autoplay and animation delays in milliseconds:
set autoplayDelay 5000
set animateDelay 200


# Geometry of windows:
array set geometry {}

# Default theme
if {$::windowsOS} {
  set lookTheme clam
} else {
  set lookTheme default
}

foreach i {tilegtk tileq keramik keramik_alt plastik dark} {
  catch {package require ttk::theme::$i}
}

#   Which windows should be opened on startup
set startup(pgn) 0
set startup(switcher) 0
set startup(tip) 0
set startup(tree) 0
set startup(finder) 0
set startup(crosstable) 0
set startup(gamelist) 0
set startup(stats) 0
set startup(book) 0
set startup(fics) 0

# myPlayerNames:
#   List of player name patterns for which the chessboard should be
#   flipped each time a game is loaded to show the board from that
#   players perspective.

set myPlayerNames {}

# These new checkbuttons (showMenu, showButtons etc) don't really have anything
# to do with gameInfo, but are here anyway S.A

set gameInfo(show) 1
set gameInfo(photos) 0
set gameInfo(hideNextMove) 0
set gameInfo(showMaterial) 1
set gameInfo(showEval) 0
set gameInfo(showFEN) 0
set gameInfo(showButtons) 1
set gameInfo(showStatus) 1
set gameInfo(showMenu) 1
set gameInfo(showTool) 1
set gameInfo(showMarks) 1
set gameInfo(wrap) 0
set gameInfo(fullComment) 0
set gameInfo(showTB) 0
if {[sc_info tb]} { set gameInfo(showTB) 2 }

### Twin game checker options
# "players" represents *exact* match or 4 chars only

array set twinSettings {
  players Yes
  colors  Yes
  event   No
  site    Yes
  round   Yes
  year    Yes
  month   Yes
  day     No
  result  No
  eco     No
  moves   Yes
  skipshort  Yes
  setfilter  Yes
  undelete   Yes
  comments   Yes
  variations Yes
  usefilter  No
  delete     Shorter
}
array set twinSettingsDefaults [array get twinSettings]

# Opening report options:
array set optable {
  Stats 1
  Oldest 5
  Newest 5
  Popular 1
  MostFrequent 6
  MostFrequentWhite 1
  MostFrequentBlack 1
  AvgPerf 1
  HighRating 8
  Results 1
  Shortest 5
  ShortestWhite 1
  ShortestBlack 1
  MoveOrders 8
  MovesFrom 1
  Themes 1
  Endgames 1
  MaxTableGames 500
  MaxGames 10000
  ExtraMoves 1
}
array set optableDefaults [array get optable]

# Player report options
array set preport {
  Stats 1
  Oldest 5
  Newest 5
  MostFrequentOpponents 6
  AvgPerf 1
  HighRating 8
  Results 1
  MostFrequentEcoCodes 6
  Themes 1
  Endgames 1
  MaxTableGames 500
  ExtraMoves 1
}
array set preportDefaults [array get preport]

# Export file options:
set exportFlags(comments) 1
set exportFlags(space) 1
set exportFlags(indentc) 0
set exportFlags(vars) 1
set exportFlags(indentv) 1
set exportFlags(newlines) 1
set exportFlags(column) 0
set exportFlags(append) 0
set exportFlags(symbols) 0
set exportFlags(htmldiag) 0
set exportFlags(stripMarks) 0
set exportFlags(convertNullMoves) 1
set exportFlags(utf8) 0
set default_exportStartFile(PGN) {}
set default_exportEndFile(PGN) {}

set default_latexRendering(engine) {pdflatex -interaction=nonstopmode}
if {$::windowsOS} {
  set default_latexRendering(viewer) start
} elseif {$::macOS} {
  # Use open -a if you want to force to the built in preview
  set default_latexRendering(viewer) open
} else {
  set default_latexRendering(viewer) xdg-open ; # evince, okular

  # Unused
  if {0} {
    if {[catch {exec xdg-mime query default application/pdf} result] == 0} {
      # cool unix has a registered app for pdfs so lets use it
      set latexViewer "xdg-open"
    } else {
      # try and detect the destop to make at least best guess
      if {[info exists ::env(XDG_CURRENT_DESKTOP)]} {
	set unixDesktop = [string tolower $::env(XDG_CURRENT_DESKTOP)]
      } else {
	switch -regexp -matchvar denv -- $::env(XDG_DATA_DIRS) {
	  .*(gnome|xfce|kde).* { set unixDesktop $denv }
	  default { set unixDesktop "unknown" }
	}
	switch $linuxDesktop {
	  gnome   {set latexViewer evince}
	  kde     {set latexViewer okular}
	  xfce    {set latexViewer evince}
	  default {set latexViewer xpdf}
	}
      }
    }
  }
}

set default_exportStartFile(Latex) {\documentclass{scrreprt}
% This is a LaTeX file generated by Siby.
% You must have xskak and KOMAScript packages installed to typeset this file.

\usepackage[margin=1cm]{geometry}
\usepackage{scrlayer-scrpage}
\usepackage{charter}
\usepackage[svgnames]{xcolor}
\usepackage{xskak}
\usepackage{lmodern}
\usepackage[T1]{fontenc}
\usepackage{latexsym}
\usepackage{pgfplots}
\pgfplotsset{compat=1.8}
\usepackage{tabularx}
\usepackage{longfbox}

% \definecolor{VariationColor}{gray}{0.40}
\definecolor{VariationColor}{RGB}{0,0,128}
% \definecolor{ScoreColor}{gray}{0.40}
\definecolor{ScoreColor}{RGB}{255,215,0}
\definecolor{GridColor}{RGB}{72,61,139}
\definecolor{EvenGameColor}{RGB}{240,240,240}
\definecolor{BlackPiecesGraphColor}{RGB}{101,37,37}
\definecolor{WhitePiecesGraphColor}{RGB}{189,183,107}

\setlength{\extrarowheight}{3pt}

\newcommand{\win}{1-0}
\newcommand{\loss}{0-1}
\newcommand{\draw}{=-=}
\newcommand{\p}{\figsymbol{p}}
\newcommand{\N}{\figsymbol{N}}
\newcommand{\B}{\figsymbol{B}}
\newcommand{\R}{\figsymbol{R}}
\newcommand{\Q}{\figsymbol{Q}}
\newcommand{\K}{\figsymbol{K}}

\renewcommand*\thesection{\arabic{section}}
\addtokomafont{section}{\color{blue}}
\addtokomafont{subsection}{\color{red}}

\begin{document}
}
set default_exportEndFile(Latex) {\end{document}
}

set default_exportStartFile(HTML) {<html>
  <head><title>Siby export</title></head>
  <body bgcolor="#ffffff">
}
set default_exportEndFile(HTML) {</body>
  </html>
}

foreach type {PGN HTML Latex} {
  set exportStartFile($type) $default_exportStartFile($type)
  set exportEndFile($type) $default_exportEndFile($type)
}

foreach type {engine viewer} {
  set latexRendering($type) $default_latexRendering($type)
}

# autoRaise: defines whether the "raise" command should be used to raise
# certain windows (like progress bars) when they become obscured.
# Some Unix window managers (e.g. some versions of Enlightenment and sawfish,
# so I have heard) have a bug where the Tcl/Tk "raise" command times out
# and takes a few seconds. Setting autoRaise to 0 will help avoid this.

# The above mentioned "1 second" bug is relevant to kde1 i think.
# Kde 3.5 (and WinXP) have focus stealing code that stops "raise"
# from working by default. In kde this can be changed by
# configuring "desktop > window behavior > advanced > focus stealing prevention"
# to "none"

set autoRaise 1

proc raiseWin {w} {
  global autoRaise
    if {$w == "." } {
     set w .main
    }
    if {$::docking::USE_DOCKING} {
      if {[catch {::docking::raiseTab $w}]} {
        # dammit, undocked windows aren't raising. fixme
	catch {wm deiconify $w}
	raise $w
	focus $w
      }
    } else {
      if {$autoRaise} {
	catch {wm deiconify $w}
	raise $w
	focus $w
      }
    }
}

# autoIconify:
#   Specified whether Scid should iconify all other Scid windows when
#   the main window is iconified. Most people like this behaviour but
#   some window managers send an "UnMap" event when the user switches
#   to another virtual window without iconifying the Scid window so
#   users of such managers will probably want to turn this off.

set autoIconify 1

# windowsDock:
# if true, most of toplevel windows are dockable and embedded in a main window
# windows can be moves among tabs (drag and drop) or undocked (right-clicking on tab)

set windowsDock 1
# set windowsDock [expr {!$::macOS}]

# autoLoadLayout :
# Automatic loading of layout # 1 at startup (docked windows mode only)
set autoLoadLayout 1

# autoResizeBoard:
# resize the board to fit the container
set autoResizeBoard 1

################################################################################
# if undocked window : sets the title of the toplevel window
# if docked : sets the name of the tab
# w : name of the toplevel window
proc setTitle { w title } {
  if { $::docking::USE_DOCKING && ! [ ::docking::isUndocked $w ]} {
    set f .fdock[ string range $w 1 end ]
    if { [catch {set nb [ ::docking::find_tbn $f ]} ]} {
      set nb ""
    }

    if { $nb == "" } {
      wm title $w $title
    } else  {
      # if target is main board, update the global window instead
      if { $w == ".main" && $title != [ ::tr "Board" ] } {
        wm title . $title
      } else  {
        # in docked mode trim down title to spare space
        if { [ string range $title 0 5 ] == "Siby: " &&  [ string length $title ] > 6 } {
          set title [string range $title 6 end]
        }
        $nb tab $f -text $title
      }
      # Siby: remembered, for the tab put back by a layout
      set ::docking::titres($f) $title
    }
  } else  {
    set wdock ".fdock[string range $w 1 end]"
    if { [winfo exists $wdock ] } { set w $wdock }
    wm title $w $title
  }

}
################################################################################
# Creates a toplevel window depending of the docking option
################################################################################
proc createToplevel { w } {
  set name [string range $w 1 end]
  set f .fdock$name

  # Raise window if already exist
  if { [winfo exists $w] } {
    if {! $::docking::USE_DOCKING } {
      tk::PlaceWindow $w
    } else {
      if { [::docking::isUndocked $w] } {
        tk::PlaceWindow $f
      } else {
        # (Siby: a window left out of every tab group after a layout
        # change is put back in one)
        set nb [::docking::find_tbn $f]
        if {$nb eq {} || ![winfo exists $nb]} {
          if {[winfo exists $f]} { catch {::docking::add_tab $f} }
          set nb [::docking::find_tbn $f]
        }
        if {$nb ne {} && [winfo exists $nb]} { catch {$nb select $f} }
      }
    }
    return "already_exists"
  }

  catch {
    unset ::docking::notebook_name($f)
  }

  if { $::docking::USE_DOCKING } {
    # (Siby: an empty tab left by a window destroyed directly)
    if {[winfo exists $f]} { catch {destroy $f} ; catch {::docking::oublierDetruits} }
    frame $f  -container 1
    toplevel .$name -use [ winfo id $f ]
    ::docking::add_tab $f
    # (Siby: add_tab lets pending events run; a layout change waiting
    # there may have destroyed the new window: it is made again)
    if {![winfo exists .$name]} {
      catch {destroy $f}
      frame $f -container 1
      toplevel .$name -use [winfo id $f]
      ::docking::add_tab $f
    }

    # auto focus mode : when the mouse enters a toplevel, it gets a forced focus to handle mouse wheel
    # only the highest stacked window can get the focus forced or on windows any time the mouse enters the main window, it will be raised
    bind .$name <Enter> {
      set tl [winfo toplevel %W]
      set focus [focus]
      if {[catch {set focus [winfo toplevel $focus]}]} {
         # if [focus] is {}, try to grab it again
         if {$::windowsOS} {
	   break
         } else {
	   focus -force .fdockmain
         }
      }
      if {$focus != $tl && ([lindex [wm stackorder .] end] == "." || $::macOS)} {
        if {$tl == ".fics"} {
          focus -force .fics.command.entry
        } else {
	  focus -force $tl
        }
      }
    }

  } else  {
    toplevel $w
  }

}

################################################################################
# In the case of a window closed without the context menu in docked mode, arrange for the tabs to be cleaned up
# Alternative way : directly call ::docking::cleanup $w when closing window
################################################################################
proc createToplevelFinalize {w} {
  if { $::docking::USE_DOCKING } {
    bind $w <Destroy> +[ namespace code "::docking::cleanup $w %W"]
  }
}

################################################################################
# Sets the menu for a new window : in docked mode the menu is displayed by clicking on the tab of the notebook
################################################################################
proc setMenu {w m} {
  if { ! $::docking::USE_DOCKING } {
    $w configure -menu $m
  }
}
################################################################################
# In docked mode, resize board automatically
# Very messy and there's probably a better way, but cant be bothered right now.
################################################################################
proc resizeMainBoard {} {
  global gameInfo board

  if { ! $::docking::USE_DOCKING } { return }

  bind .main <Configure> {}

  set w [winfo width .main]
  set h [winfo height .main]
  set bd .main.board

  ### calculate available height

  set height_used 0
  if {$gameInfo(showTool)} {
    incr height_used [ lindex [grid bbox .main 0 0] 3]
  }
  # (Siby: row 3, buttons below the board, or the lower player in the
  # live view; row 1, the upper player in the live view)
  # (and the players' bands of any game, arrows under them or not)
  if {$gameInfo(showButtons) || [winfo exists .main.liveBas] || [winfo exists .main.clkBas]} {
    incr height_used [ lindex [grid bbox .main 0 3] 3]
  }
  if {[winfo exists .main.liveHaut] || [winfo exists .main.clkHaut]} {
    incr height_used [ lindex [grid bbox .main 0 1] 3]
  }

  # coordinates
  incr height_used [expr {$::fd_size * $::boardCoords}]

  # game info &&& fixme
  set min_game_info_height [expr {6 + $gameInfo(showFEN) + $::macOS}]
  set game_info_line_height 5
  set min_game_info_lines 1
  if {$gameInfo(show)} {
    set min_game_info_lines 5
    set game_info_lines [.main.gameInfo count -displaylines 1.0 end]
    if { $game_info_lines > 0 } {
      # probably not very correct, do you know any better way to get this information?
      set game_info_line_height [expr 1.0 * [.main.gameInfo count -ypixels 1.0 end] / $game_info_lines]
    } else {
      # utter approximation
      set game_info_line_height [expr [font configure font_Regular -size] * 1.5]
    }
    set min_game_info_height [expr int($min_game_info_lines * $game_info_line_height + 5)]
  } elseif {[::moderne::actif]} {
    # (Siby: no game information under the board, no room kept for it:
    # an empty strip under the players' band, Yosha 2026-11-09)
    set min_game_info_height 4
  } else {
    set min_game_info_height [expr int([font configure font_Regular -size] * 1.5 * 2.5)]
  }
  incr height_used $min_game_info_height

  # status bar
  incr height_used [ lindex [grid bbox .main 0 5] 3]

  set availh [expr $h - $height_used]

  ### calculate available width

  set width_used 12
  if {[winfo exists .fics]} {
    ### proc ::board::ficslabels
    incr width_used [expr {$::fd_size * 2}]
  }

  incr width_used [expr {$::fd_size * $::boardCoords}]

  if {$::board::_stm($bd)} {
    incr width_used [ lindex [ grid bbox $bd 1 1] 2 ] ; # stmgap
    incr width_used [winfo width $bd.stm]
  }
  if {$::board::_showmat($bd)} {
    # we can't rely on board::_matwidth($bd) or the bbox of 12,1 because matwidth is being set afterwards
    incr width_used 30
  }
  if {$::board::_showEvalbar($bd)} {
    incr width [lindex [ grid bbox $bd 12 1] 2]
    incr width 2
  }

  # Not quite perfect for some reason (-16)
  set availw [expr $w - $width_used -16]

  if {$availh < $availw} {
    set min $availh
  } else  {
    set min $availw
  }

  if { $::autoResizeBoard } {
    # find the closest available size
    for {set i 0} {$i < [llength $::boardSizes]} {incr i} {
      set newSize [lindex $::boardSizes $i]
      if { $newSize > [ expr $min / 8 ] } {
        if {$i > 0} {
          set newSize [lindex $::boardSizes [expr $i -1] ]
        }
        break
      }
    }
    # resize the board
    ::board::resize .main.board $newSize
    set ::boardSize $newSize
  }

  # adjust game info height
  set new_game_info_lines [expr int(($min_game_info_height+($availh-$::boardSize*8))/$game_info_line_height)]
  if { $new_game_info_lines > $min_game_info_lines } {
    set new_game_info_lines [expr $new_game_info_lines - 1]
  }
  .main.gameInfo configure -height $new_game_info_lines

  update idletasks
  bind .main <Configure> {::docking::handleConfigureEvent %W}
}

proc toggleToolbar {} {
  if {$::gameInfo(showTool)} {
    grid .main.tb -row 0 -column 0 -columnspan 3 -sticky we
  } else {
    grid forget .main.tb
  }
}

proc toggleMenubar {} {
  set ::gameInfo(showMenu) [expr !$::gameInfo(showMenu)]
  showMenubar
}

proc showMenubar {} {
  if {!$::gameInfo(showMenu)} {
    $::dot_w configure -menu {}
  } else {
    $::dot_w configure -menu .menu
  }
}

proc toggleButtonBar {} {
  if {!$::gameInfo(showButtons)} {
    grid remove .main.button
  } else {
    # (Siby: -in .main, they may have been in the clocks' band; put back in
    # its middle if it is there)
    grid configure .main.button -in .main -row 3 -column 0 -pady {0 3} -padx 5 -sticky n
    catch ::moderne::horloges::maj
  }
}

proc toggleStatus {} {
  if {!$::gameInfo(showStatus)} {
    grid remove .main.statusbar
  } else {
    grid configure .main.statusbar -row 5 -column 0 -columnspan 3 -sticky we
  }
}

proc toggleGameInfo {} {
  set ::gameInfo(show) [expr ! $::gameInfo(show)]
  showGameInfo
  resizeMainBoard
}

proc showGameInfo {} {
  if {$::gameInfo(show)} {
    grid forget .main.gameInfoMini
    grid .main.gameInfoFrame -row 4 -column 0 -sticky nsew -padx 2
  } else  {
    grid forget .main.gameInfoFrame
    # Siby: nothing below the board (the players are in the notation)
    if {![::moderne::actif]} {
      grid .main.gameInfoMini -row 4 -column 0 -padx 2
    } else {
      grid forget .main.gameInfoMini
    }
  }
  update idletasks
}

# Email configuration

set email(logfile) [file join $scidLogDir "scidmail.log"]
set email(smtp) 1
set email(smproc) "/usr/lib/sendmail"
set email(server) localhost
set email(from) ""
set email(bcc) ""

# Sound options

set ::utils::sound::announceNew 0
set ::utils::sound::announceForward 0
set ::utils::sound::announceBack 0
set ::utils::sound::announceTock 0
set ::utils::sound::soundFolder {} ;# disabled by default
set ::utils::sound::device {}

set ::book::lastBook1 {} ; # book name without extension (.bin)
set ::book::lastBook2 {}
set ::book::lastTuning {}
set ::book::sortAlpha 0
set ::book::showTwo 0
set ::book::oppMovesVisible 0

# Engines list file: -- OLD NAMES, NO LONGER USED
#set engines(file) [file join $scidUserDir "engines.lis"]
#set engines(backup) [file join $scidUserDir "engines.bak"]

# Engines data:
set engines(list) {}
set engines(sort) Time
set engines(F2)  0
set engines(F3)  1
set engines(F4)  {}

proc resetInformants {} {
  global informant
  array set informant {}
  set informant("!?")  0.5
  set informant("?")   1.5
  set informant("??")  3.0
  set informant("?!")  0.5
  set informant("+=")  0.5
  set informant("+/-") 1.5
  set informant("+-")  3.0
  set informant("++-") 5.5
}

resetInformants

# Nice icon from OSX,
# ... but it doesn't antialias well in the text widget !%^&*

image create photo icon -format gif -data {
R0lGODlhLwAvAOf/AA4OIAQNQgQNSAYPOAYPPQ0PKg4NOBcPFQ4LQw8QMBAN
PggOUAARVxEMSgkOVx0SDRARNhQSKCQTBQwRUw0XNhYWJhATTxkUNREWRi4V
AhUZMwkXXxMUVx0ZIQsYWR8bGhgXWxkeMzMaAhIcXiMeJx0cQyUiEhQeWjgd
AR4hPCsiFCoiGT4dAB4eVh8gUhogYyImMSEfXioqIx4lYjIrD0YkACkqMSQn
UycmX04nADkxFVIpAk8rATwzDiYuZj40BzczIzEuT1UrADQzMVAxAFgtADEv
YFAxDV0tAlUwCjQ4OlkvClgyAEQ6DS41Z2AvAFEzFjczXVoxCVY4ADM3ZVA3
F2IxB083HmQyAUo5J0s/Blg1Hkc8KEE5S007I2c1BDs7XF47AEg+LkQ/NFU5
Kmo3AEk6TD1EQFREBFk7J2c6Bzw+Zz9DRUNDO2Y7D0dBS1E9RldIAERGQ1Y+
PUFFV19GAE1DQ0JFY2hAHExHRnBCAGVDHURMSF1NAEJNTmhJAF1OBVZKNVRL
QGNIKEhMX0hLbGRTAmFSEHhKAEhTU2hSBG1RAFNMYlJPXkxVUElRbmhXAGxV
AGpPM2ZSOmVXI2lTNmtaDGFWPm5cAlBbXGJXR3FeAFJeXndfAIRZAGFdTmhb
RnZjAGRbYGFdXltjX3pmBYNkAFxjcGhhW31pAFxnaF1kd21mVHppKoNtAm5o
XGFsbWRsaIpuAIhxAINvHHVuVWdvdm9uZo9zAJNxAI12AW50aox2EJ9wAJB4
AH9zS5F5BpN7AKN0AJh6AIt4M5Z+AJqBBKJ9BZeAHZ2DAI1/UaCGAKSEAJ6F
C5WBO6OIAJ+GGqWKA5yGM7GEBpeFTJ6JJaiNAKyLAK2RALOQAaOOSLGUBLeU
ALqRCLCUFrSXALWYDLOXKrqcAL6aALyeBMGcBsOdAMGhAMiiAL+iLMKjH8en
AsylBM+oAMKlNdOsANeuAsytK9iwBtqxANSyDt+1AOK4AOm9AOW9De7CAPLF
APXHAPjKAPvMAP7PAP///yH5BAEKAP8ALAAAAAAvAC8AAAj+AP8JHEiw4MBb
X5gMQ/fuHbyHD98tS5bMmMWLxcyx24jOnMGPBfcgWTSuYT15J+nRK7esJbOJ
FJMtW0dzXbtzIHOCKkMkVbFm0b59O9eu3btszCompVhsWLZ3RduxQ5fz4y03
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
}

# Siby: its logo in the taskbar from the start (SCID's until now, then
# Siby's once the modern files were loaded)
if {[catch {
  image create photo sibyIcone48 -format png -data {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}
  image create photo sibyIcone32 -format png -data {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}
  wm iconphoto . -default sibyIcone48 sibyIcone32
}]} {
  wm iconphoto . -default icon
}

# Opening files by double clicks/open-with on Mac
set mac_args 0

if {$macOS} {
  set mac_busy 0
  set isMacBaseReady 0

  proc macOpenWith {args} {
    global mac_busy
    global isMacBaseReady
    global mac_args

    # Un-nest arguments:
    set args [join $args]

    # Wait for openBase to be ready, if needed.
    # (does not seem to be accessed)
    if {$isMacBaseReady == 0} {
      if {$mac_args != 0} {
        tk_messageBox -type ok -icon info -title Siby -message \
            "Please, wait until Siby has finished starting up."
        return
      } else {
        # Save file names for later use:
        set mac_args $args
      }
      return
    }

    # Are we busy opening files? if so, display message and do nothing
    if {$mac_busy != 0} {
      tk_messageBox -type ok -icon info -title Siby -message \
          "Please, wait until the previous database(s) are opened and try again."
      return
    }

    # Un-nest argumens again if Scid opened on drag & drop
    if {$isMacBaseReady == 2} {
      # Un-nest arguments:
      set args [join $args]
      set isMacBaseReady 1
    }

    set mac_busy 1
    set errmsg ""
    foreach file $args {
      # Check for available slots:
      if {[sc_base count free] == 0} {
        tk_messageBox -type ok -icon info -title Siby \
            -message "Too many databases are open; close at least one \n\
            before opening more databases"
        #::splash::add "No slot available."
        return
      }
      set ext [file extension $file]
      # Email File:
      if {$ext == ".sem"} {
        #::tools::email
        continue
      }
      # SearchOptions file:
      # (Siby: never run, they are Tcl code: a file received from someone
      # could run any command)
      if {$ext == ".sso"} {
        continue
      }
      if {$ext == ".sg4" || $ext == ".sn4"} {
        set file "[file rootname $file].si4"
      }
      if {$ext == ".sg3" || $ext == ".sn3"} {
        set file "[file rootname $file].si3"
      }

      # Check if base is already opened
      set slot [sc_base slot $file]
      if {$slot != 0} {
        sc_base switch $slot
        refreshWindows
        updateBoard -pgn
      } else  {
        # All seems good, let's open those files:
        # (deiconify doesn't seem necessary - S.A. 2018)
        # wm deiconify $::dot_w
        ::file::Open $file
        focus .main
      }
    }
    set mac_busy 0
    set mac_args 0
  }
  proc tkOpenDocument {args} {
    after idle [list macOpenWith $args]
  }
  rename tkOpenDocument ::tk::mac::OpenDocument

  # Hack to allow focus and text copy from disabled text widgets on OSX
  rename text ::tk::mac::text
  proc text {w args} {
    eval ::tk::mac::text $w $args
    bind $w <1> "focus $w"
    $w configure -highlightthickness 0
  }
}

# Add empty updateStatusBar proc to avoid errors caused by early
# closing of the splash window:

proc updateStatusBar {} {}

set ::splash::keepopen 0 ;# Siby: no splash window
set ::splash::cache {}

# the function gets redfined once the fonts have been read from options.dat

proc ::splash::add {text {tag {indent}}} {
  lappend ::splash::cache $text
}

# Remember old font settings before loading options file:
set fontOptions(oldRegular) $fontOptions(Regular)
set fontOptions(oldMenu) $fontOptions(Menu)
set fontOptions(oldSmall) $fontOptions(Small)
set fontOptions(oldTiny) $fontOptions(Tiny)
set fontOptions(oldFixed) $fontOptions(Fixed)

# New configuration file names:
set scidConfigFiles(options)     options.dat
set scidConfigFiles(engines)     engines.dat
set scidConfigFiles(engines.bak) engines.dat
set scidConfigFiles(recentfiles) recent.dat
set scidConfigFiles(history)     history.dat
set scidConfigFiles(bookmarks)   bookmarks.dat
set scidConfigFiles(reports)     reports.dat
set scidConfigFiles(optrainer)   optrainer.dat

set ecoFile {}

set addRatings(overwrite) 0
set addRatings(filter)    1

# scidConfigFile:
#   Returns the full path and name of a Scid configuration file,
#   given its configuration type.
#
proc scidConfigFile {type} {
  global scidConfigDir scidConfigFiles
  if {! [info exists scidConfigFiles($type)]} {
    return -code error "No such config file type: $type"
  }
  return [file nativename [file join $scidConfigDir $scidConfigFiles($type)]]
}

# Create user ".scid" directory in Unix if necessary:
# Since the options file used to be ".scid", rename it:
if {! [file isdirectory $scidUserDir]} {
  if {[catch {file mkdir $scidUserDir} err]} {
    ::splash::add "Error creating $scidUserDir directory: $err" error
  } else {
    catch {file rename "$scidUserDir.old" $optionsFile}
  }
}

# Create the config, data and log directories if they do not exist:
proc makeScidDir {dir} {
  if {![file isdirectory $dir] || ![file writable $dir]} {
    if {[catch {file mkdir $dir} err]} {
      ::splash::add "Error creating directory $dir: $err" error
    } else {
      ::splash::add "Created directory: $dir"
    }
  }
}

makeScidDir $scidConfigDir
makeScidDir $scidDataDir
makeScidDir $scidLogDir

# moveOldConfigFiles removed S.A

set optionsFile [scidConfigFile options]

::splash::add "Command line is \"$::argv0 $::argv\""
::splash::add "User directory is \"$scidUserDir\""

if {[info tclversion] >= "8.6"} {
  ::splash::add "png image support is available."
  set png_image_support 1
  set boardStyle Merida1
} elseif { [catch { package require img::png } ] } {
  ::splash::add "TkImg not found. Most piece sets are disabled."
  set png_image_support 0
  set boardStyle Alpha
} else {
  ::splash::add "TkImg found. Enabling png image support."
  set png_image_support 1
  set boardStyle Merida1
}

set useGraphFigurine 1

### Siby: defaults of the new look (see tcl/moderne/theme.tcl).
# They apply only when options.dat holds no personal setting.
namespace eval ::moderne {}
namespace eval ::moderne::syzygy {}  ;# (options.dat remembers ::moderne::syzygy::chemin)
set ::moderne::theme sombre          ;# sombre (dark) | clair (light) | classique (original look)
namespace eval ::moderne::barres {}  ;# evaluation bars (tcl/moderne/barres.tcl)
set ::moderne::barres::actif 1
array set ::moderne::barres::mode {g classique d wdl}
set ::moderne::barres::place plateau  ;# plateau (board) | moteur (engine)
set ::moderne::barres::style large  ;# (the thin gauge was removed)
set ::moderne::echiquier marbre       ;# board: marbre (marble, blue, Lichess) | brun (brown)
set ::moderne::coordsDedans 1         ;# coordinates inside the squares
set ::moderne::barres::enPartie 0  ;# bars shown during a game against an engine
namespace eval ::moderne::prepa {}
namespace eval ::moderne::moteur {}
set ::moderne::moteur::unites {}       ;# evaluation unit per engine
# W/D/L column of the engine lines: hidden by default, as on Lichess (the
# eval, in centipawns or expected score, says it; 0/99/1 takes room)
set ::moderne::moteur::wdlVisible 0
# Windows: .pgn and .si4 opened with Siby (1: registered, kept up to date at
# each start); demande: the offer was made once
namespace eval ::moderne::systeme {}
set ::moderne::systeme::associe 0
set ::moderne::systeme::demande 0
set ::moderne::flechesMoteur 0       ;# engine arrows on the main board
set ::moderne::basesExploration {}  ;# databases where a modified game is discarded without asking
set ::moderne::choixCoupExistant var ;# move already present, without asking: var | replace | mainline
set ::moderne::fantome 1           ;# ghost piece on the origin square while dragging (Lichess)
set ::moderne::pointsCoups 1        ;# dots for the possible moves when a piece is picked up (Lichess)
namespace eval ::moderne::toby {}
array set ::moderne::toby::jeu {couleur white eloToby 2900 eloMoi 1800 source FIDE minutes 10 inc 5 depart initiale barres 0 contempt 200 noeuds 1} ;# Play against Toby (contempt, noeuds: Leela)
set ::moderne::toby::modeAnalyse fixe   ;# Toby in analysis: fixe (one Elo for both sides) | partie (Elo and time control from the PGN)
set ::moderne::toby::defElo 2300
set ::moderne::toby::defCadence Classical
set ::moderne::toby::defSource FIDE
set ::moderne::toby::fleches 0
set ::moderne::toby::precision Accurate ;# Toby: Accurate | Fast
namespace eval ::moderne::biblio {}
set ::moderne::biblio::vueLichess 1 ;# opening library: Lichess-style view (1) or detailed table (0)
set ::moderne::pgnUneLigne 1         ;# PGN export: one line of moves per game (like ChessBase, Lichess)
set ::moderne::tempsCoups 0          ;# notation: the move times ([%clk]) shown
set ::moderne::exportTemps 1         ;# PGN export: the move times ([%clk], [%emt]) kept
if {$png_image_support} {
  set boardStyle Cburnett            ;# cburnett pieces (Lichess)
}
# Lichess "brown" board
set lite        #f0d9b5
set dark        #b58863
set highcolor   #829769              ;# selected square
set bestcolor   #aaa23a              ;# suggested square
set bgcolor     #b58863              ;# lines between the squares (invisible if borderwidth is 0)
set borderwidth 0
set squarecolor #15781b
set highlightLastMoveColor #9bc700   ;# last move (blended with the square color)
set highlightLastMoveFill 1          ;# 1 = Lichess-style tinted square, 0 = outline (original)
# Lichess-style arrows: green for the main line, blue for variations
set maincolor   #15781b
set varcolor    #5d7fb8
set engineLineColor #15781b
set lookTheme   clam                 ;# flat ttk theme, recolored by tcl/moderne/theme.tcl
### End Siby

### Siby: safe start (Yosha 2026-11-05). Each start is counted in
### demarrage.txt, the count cleared once Siby has run 12 s (see
### ::moderne::rapport::veille). Two starts in a row that did not get that
### far: the settings (options.dat, with the layouts) may be what breaks
### Siby, the default ones are offered; the old file is kept aside.
### SIBY_SECOURS_REPONSE=oui|non answers without asking (tests).
proc ::sibyDemarrageSecours {optionsFile} {
  set f [file join $::scidUserDir demarrage.txt]
  set n 0
  catch {set c [open $f] ; set n [string trim [read $c]] ; close $c}
  if {![string is integer -strict $n]} { set n 0 }
  if {$n >= 2 && [file exists $optionsFile]} {
    set fr 0
    catch {set fr [string match fr* [::msgcat::mclocale]]}
    if {[info exists ::env(SIBY_LANG)]} { set fr [expr {$::env(SIBY_LANG) eq "F"}] }
    if {[info exists ::env(SIBY_SECOURS_REPONSE)]} {
      set r [expr {$::env(SIBY_SECOURS_REPONSE) eq "oui" ? "yes" : "no"}]
    } else {
      # (the startup window would hide the question)
      catch ::sibyDemarrage::fin
      set r [tk_messageBox -icon warning -type yesno -default yes -title Siby -message [expr {$fr \
          ? "Siby ne s'est pas ouvert correctement les deux dernières fois. Démarrer avec les réglages par défaut ?" \
          : "Siby did not open properly the last two times. Start with the default settings?"}]]
    }
    if {$r eq "yes"} {
      set copie "$optionsFile.secours-[clock format [clock seconds] -format %Y%m%d-%H%M%S]"
      if {![catch {file rename -force $optionsFile $copie}]} {
        puts stderr "Siby: safe start, the default settings (the old ones in $copie)"
        catch {
          set c [open [file join $::scidUserDir siby.log] a]
          puts $c "[clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}] Siby: safe start, the default settings (the old ones in $copie)"
          close $c
        }
      }
    }
    set n 0
  }
  catch {set c [open $f w] ; puts $c [expr {$n + 1}] ; close $c}
}
catch {::sibyDemarrageSecours $optionsFile}

### Siby: the namespaces of the saved settings made before reading them.
### options.dat is read before the tcl/moderne files; a "set ::a::b::x"
### whose namespace did not exist yet stopped the reading there, and every
### setting after it was lost at each start (My databases' folders, the
### databases added by hand, the reference database, the profile...;
### Yosha 2026-11-05).
catch {
  set _c [open $optionsFile r]
  set _t [read $_c]
  close $_c
  foreach {_x _ns} [regexp -all -inline -line {^\s*set\s+(::[A-Za-z0-9_:]+)::[^\s:(]+} $_t] {
    namespace eval $_ns {}
  }
}
catch {close $_c}
unset -nocomplain _c _t _x _ns

if {[catch {source $optionsFile} ]} {
  ::splash::add "Error loading options file \"$optionsFile\"" error
} else {
  ::splash::add "Loaded options from \"$optionsFile\"."
}

### Siby: the variation arrows turned off and the choice of the move turned
### on, once for everyone (options saved before 2026-10-27 still had SCID's
### defaults); the Options menu can change both
if {!$::moderne::flechesVariantesVues} {
  set showVarArrows 0
  set showVarPopup 1
  set ::moderne::flechesVariantesVues 1
}
### End Siby

# Hack to unset previous exportStartFile(Latex)
if {[string match *pstricks-add* $exportStartFile(Latex)]} {
  set exportStartFile(Latex) $default_exportStartFile(Latex)
}

if { [string first "-dock" [lindex $argv 0]] > -1} {
  set windowsDock 1
}

if { [string first "-nodock" [lindex $argv 0]] > -1} {
  # reset in case of error recovery
  set windowsDock 0
  ::docking::init_layout_list  1
}

if { [string first "-dock" [lindex $argv 0]] > -1} {
  set windowsDock 1
}

set ::docking::USE_DOCKING $windowsDock

if {$::docking::USE_DOCKING} {
  set dot_w .
} else  {
  set dot_w .main
}

::splash::add {}

# gradient
# Bryan Oakley
# https://wiki.tcl-lang.org/page/Making+color+gradients
#
#    color   - standard tk color; either a name or rgb value
#              (eg: "red", "#ff0000", etc)
#    factor  - a number between -1.0 and 1.0. Negative numbers
#              cause the color to be adjusted towards black;
#              positive numbers adjust the color towards white.
#    window  - a window name; used internally as an argument to
#              [winfo rgb]; defaults to "."

proc gradient {rgb factor {window .}} {

    foreach {r g b} [winfo rgb $window $rgb] {break}

    ### Figure out color depth and number of bytes to use in
    ### the final result.
    if {($r > 255) || ($g > 255) || ($b > 255)} {
	set max 65535
	set len 4
    } else {
	set max 255
	set len 2
    }

    ### Compute new red value by incrementing the existing
    ### value by a value that gets it closer to either 0 (black)
    ### or $max (white)
    set range [expr {$factor >= 0.0 ? $max - $r : $r}]
    set increment [expr {int($range * $factor)}]
    incr r $increment

    ### Compute a new green value in a similar fashion
    set range [expr {$factor >= 0.0 ? $max - $g : $g}]
    set increment [expr {int($range * $factor)}]
    incr g $increment

    ### Compute a new blue value in a similar fashion
    set range [expr {$factor >= 0.0 ? $max - $b : $b}]
    set increment [expr {int($range * $factor)}]
    incr b $increment

    ### Format the new rgb string
    set rgb \
	[format "#%.${len}X%.${len}X%.${len}X" \
	     [expr {($r>$max)?$max:(($r<0)?0:$r)}] \
	     [expr {($g>$max)?$max:(($g<0)?0:$g)}] \
	     [expr {($b>$max)?$max:(($b<0)?0:$b)}]]


    ### Return the new rgb string
    return $rgb
}

if {$enableForeground == 1} {
  # Text foreground only
  option add *Text*foreground $defaultForeground
  option add *Listbox*foreground $defaultForeground

  # Menus
  # option add *menu*foreground white
}
if {$enableBackground == 1} {
  option add *Text*background $defaultBackground
  option add *Listbox*background $defaultBackground
}
if {$enableBackground == 2} {
  option add *background $defaultBackground
  option add *activeBackground [::gradient $defaultBackground .4 .]
  option add *HighlightBackground $defaultBackground
}


# Reconfigure fonts if necessary

foreach i {Regular Menu Small Tiny Fixed} {
  if {$fontOptions($i) == $fontOptions(old$i)} {
    # Old font format in options file, or no file. Extract new options:
    set fontOptions($i) {}
    lappend fontOptions($i) [font actual font_$i -family]
    lappend fontOptions($i) [font actual font_$i -size]
    lappend fontOptions($i) [font actual font_$i -weight]
    lappend fontOptions($i) [font actual font_$i -slant]
  } else {
    # New font format in options file:
    configureFont $i
  }
}

# make font_Regular the default font for widgets

set fd_size [font actual font_Regular -size]
option add *Font font_Regular
option add *Menu*Font font_Menu
# option add *Menubutton*Font font_Menu
if {$unixOS} {
  option add Scrollbar*borderWidth 1
}

### Fonts now fully configure :> S.A

### Takes an entrybox, a (global?) var, and a text widget
#   Binds Entry <Return> to search the text widget for entry box contents

proc configFindEntryBox {entry var text} {
    upvar $var topvar

    ### This code originally in htext.tcl::updateHelpWindow
    $text tag configure Highlight -background orange

    set topvar(findprev) {}
    set topvar(findindex) 1.0
    bind $entry <Return> "nextFindEntryBox $entry $var $text"
    bind [winfo toplevel $entry] <Control-f> "focus $entry"
}

proc nextFindEntryBox {entry var text} {
    upvar 1 $var topvar

    if {$topvar(findprev) != $topvar(find)} {
      set topvar(findprev) $topvar(find)
    }
    $text tag remove Highlight 1.0 end

    if {[catch {
          set result [$text search -regexp -nocase -- $topvar(find) $topvar(findindex)]
        }]} {
      flashEntryBox $entry
      return
    }
    if {$result == {}} {
      set topvar(findindex) 1.0
      flashEntryBox $entry
    } else {
      if {[ regexp {(.*)\.(.*)} $result t1 line char]} {
        $text see $result
        # find the length of matching text
        regexp -nocase -- $topvar(find) [$text get $line.0 $line.end] matchVar
        set length [string length $matchVar]
        if {$length < 1} {
          set length 1
        }
        $text tag add Highlight $result $line.[expr $char + $length]
        set topvar(findindex) $line.[expr $char + 1]
      } ;# should always succeed ?
    }
}

### [bell] doesnt work on all platforms (esp. Linux), so make our own

proc flashEntryBox {w} {
      set bg [$w cget -background]
      set fg [$w cget -foreground]
      $w configure -background $fg -foreground $bg
      after 200 "$w configure -background $bg -foreground $fg"
}

### Add basic Bash-style history to entry boxes
#   (History up/down with arrows, Control-c to cancel, and alt-backspace to delete a word)

proc  configHistory {namespace entrybox} {

  set ::${namespace}::entrybox $entrybox

  bind $entrybox <Up> "::${namespace}::cmdHistory up"
  bind $entrybox <Down> "::${namespace}::cmdHistory down"
  if {$::macOS} {
    bind $entrybox <Option-BackSpace> "::${namespace}::cmdBackWord ; break"
  } else {
    bind $entrybox <Alt-BackSpace> "::${namespace}::cmdBackWord ; break"
  }

  namespace eval $namespace {
    variable history
    variable history_pos
    variable history_current
    variable entrybox

    set history {}
    set history_pos 0
    set history_current 0

    namespace export addHistory cmdHistory cmdClear cmdBackWord

    proc addHistory {text} {
      variable history
      variable history_pos
      variable history_current
      variable entrybox

      if {[lindex $history end] != $text} {
	lappend history $text
      }
      set history_pos [llength $history]
    }

    proc cmdHistory {action} {
      variable history
      variable history_pos
      variable history_current
      variable entrybox

      set t $entrybox

      if {$action == "up" && $history_pos > 0} {
	if {$history_pos == [llength $history]} {
	  set history_current [$t get]
	}
	$t delete 0 end
	incr history_pos -1
	$t insert end [lindex $history $history_pos]
      }
      if {$action == "down"} {
	if {$history_pos < [llength $history]} {
	  $t delete 0 end
	  incr history_pos
	  if {$history_pos == [llength $history]} {
	    set  entry $history_current
	  } else {
	    set entry [lindex $history $history_pos]
	  }
	  $t insert end $entry
	}
      }
    }

    proc cmdBackWord {} {
      variable entrybox

      # bash like delete last word on command line
      set entry [$entrybox get]
      # break line into two parts (before/after cursor)
      set i [$entrybox index insert]
      set t1 [string range $entry 0 $i-1]
      set t2 [string range $entry $i end]
      if {[string is space [string index $t1 end]]} {
	while {[string is space [string index $t1 end]]} {
	  set t1 [string range $t1 0 end-1]
          # Oops. "" is space !
	  if {$t1 == ""} { return }
	}
      } else {
	set j [string last { } $t1]
	set t1 [string range $t1 0 $j-1]
      }
      $entrybox delete 0 end
      $entrybox insert end $t1$t2

      $entrybox icursor [string length $t1]
    }

    proc cmdClear {} {
      variable history
      variable history_pos
      variable entrybox

      $entrybox delete 0 end
      set history_pos [llength $history]
    }

  }
}

### Start up splash window

proc ::splash::make {} {
  ### windows hack
  # Dont withdraw toplevel if windows and docked mode, because of rendering bugs in paned windows/tabs
  if {!($::windowsOS && $::docking::USE_DOCKING)} {
     wm withdraw .
  }

  set w [toplevel .splash]
  if {!$::splash::keepopen} { wm withdraw $w } ;# Siby

  ### Calculate size of the OS X dock
  #   - but it is busted. Maximized height doesnt want to work, and 'update's don't seem to help
  if {0 && $::macOS} {
      wm state $w zoomed
      set height_maximized [winfo height $w]
      wm state $w normal

      wm attributes $w -fullscreen 1
      set height_fullscreen [winfo height $w]
      wm attributes $w -fullscreen 0

      set ::macDockHeight [expr $height_fullscreen - $height_maximized]
      ::splash::add "OS X Dock height is $::macDockHeight"
  }

  wm withdraw $w
  wm protocol $w WM_DELETE_WINDOW [list wm withdraw $w]
  wm title $w "Welcome to $::scidName $::sibyVersion"

  ### Pack in this order to resize nicely
  # buttons
  frame $w.b
  pack $w.b -side bottom -fill x

  # command entry
  entry $w.command
  pack $w.command -side bottom -fill x -padx 3 -pady 2

  configHistory splash $w.command

  # text
  frame $w.f
  pack $w.f -side top -expand yes -fill both

  text $w.t -height 15 -width 55 -cursor top_left_arrow \
       -font font_Regular -wrap word \
      -yscrollcommand [list $w.ybar set] -setgrid 1
  scrollbar $w.ybar -command [list $w.t yview]

  # Translations aren't set up yet, but these are handled in setLanguage
  checkbutton $w.auto -text "Keep open after startup" \
      -variable ::splash::keepopen -font font_Small -pady 5 -padx 5
  button $w.dismiss -text Close -width 8 -command [list wm withdraw $w] \
      -font font_Small

  entry $w.find -width 10 -textvariable ::splash::find(find) -highlightthickness 0
  configFindEntryBox $w.find ::splash::find $w.t

  set ::splash::console 0
  bind $w.command <Return> {
    if {!$::splash::console} {
      set ::splash::console 1
      ::splash::add {}
      ::splash::add "$scidName $::sibyVersion Console"
      ::splash::add {------------------------------------}
      ::splash::add {Here you can enter commands to the Siby interpreter for execution.}
      ::splash::add {Try - "time {foreach i [array names helpText] {helpWindow $i}}" for a simple test and benchmark.}
    }
    set command [string trim [.splash.command get]]
    ::splash::add "# $command"
    ::splash::addHistory $command
    if {$command != {}} {
      if {[catch {set result [eval $command]} error]} {
	::splash::add "> $error"
      } else {
	::splash::add "> $result"
      }
    }
    .splash.t see end
    .splash.command delete 0 end
  }


  pack $w.auto -side left -in .splash.b -pady 2 -ipadx 10 -padx 10
  pack $w.find $w.dismiss -side right -in .splash.b -pady 2 -ipadx 10 -padx 10
  pack $w.ybar -in $w.f -side right -fill y
  pack $w.t -in $w.f -side left -fill both -expand yes

  # Centre the splash window:
  update idletasks
  set x [expr {[winfo screenwidth $w]/2 - [winfo reqwidth $w]/2 }]
  set y [expr {[winfo screenheight $w]/2 - [winfo reqheight $w]/2 }]
  wm geom $w +$x+$y
  # Siby: splash window only if requested (Help › At startup)
  if {$::splash::keepopen} { wm deiconify $w } else { wm withdraw $w }

  bind $w <F1> {helpWindow Console}
  bind $w <Escape> {.splash.dismiss invoke}

  $w.t tag configure indent -lmargin2 20
  $w.t tag configure error -foreground red
  $w.t tag configure scid_title -font {Arial 24 normal} -foreground darkslateblue

  $w.t insert end "        $::scidName     " scid_title
  $w.t image create end -image icon -padx 20 -pady 10
}

::splash::make

proc ::splash::add {text {tag {indent}}} {
  if {[winfo exists .splash]} {
    .splash.t insert end "\n$text" $tag
    if {$tag == {error}} {
      if {$::windowsOS} {
	puts $text
      } else {
	puts stderr $text
      }
    }
  }
}

::splash::add "$::scidName $::sibyVersion"
::splash::add "Credits: Help › Thanks."
::splash::add ""
::splash::add "(C) Steven Atkinson (stevenaaus@yahoo.com) 2008-2026"
::splash::add "(C) Pascal Georges 2006-2008"
::splash::add "(C) Shane Hudson 1999-2004"
::splash::add "(C) Gregor Cramer, Fulvio Benini and others."
::splash::add "Licenced under the GNU General Public License."
::splash::add ""

# add cached splash comments
foreach line $::splash::cache {
  ::splash::add $line
}

# A lot of code assumes tcl_platform is either windows or unix, so
# lotsa stuff may break if this is not the case.

if {[catch {.splash.t configure -insertforeground blue}]} {
  set result No
} else {
  set result Yes
}
::splash::add "Using Tcl/Tk version: [info patchlevel] (with Gregor's tk::text - $result)"

::splash::add "$tcl_platform(os) operating system, version $tcl_platform(osVersion)"
if {(! $windowsOS)  &&  (! $unixOS)} {
  ::splash::add "Operating System may not be supported"
}
if {[string match -nocase Linux $tcl_platform(os)]} {
  catch {
    ::splash::add "[eval exec cat [glob /etc/*-release] | uniq]"
  }
}

catch {
  ::splash::add "LANG environment var is $::env(LANG)"
}

::splash::add ""

### Workaround a bug in Wish 8.5.10 ttk::scale.
# To trigger, press Control-l three times and try to move y scrollbar

set buggyttk [expr {[info patchlevel] == {8.5.10}}]
if {$buggyttk} {
      ::splash::add "Warning - Disabling Tk-8.5.10's buggy ttk::scale widget." error
}


# Check board size is valid:
set newSize [lindex $boardSizes 0]
foreach sz $boardSizes {
  if {$boardSize >= $sz} { set newSize $sz }
}
set boardSize $newSize

# Load theme
catch {ttk::style theme use $lookTheme}
::ttk::style configure TNotebook.Tab -font font_Menu

if {$enableBackground == 2} {
  ::ttk::style configure TNotebook.Tab -font font_Menu
  ::ttk::style configure TNotebook -background $::defaultBackground
  ::ttk::style configure TPanedwindow -background $::defaultBackground
  ::ttk::style configure TScrollbar -background $::defaultBackground
  ::ttk::style configure TScale -background $::defaultBackground
}

# Redefine this combobox proc to disable highlighting of the selected entry ffs
proc ttk::combobox::SelectEntry {cb index} {
    $cb current $index
    # $cb selection range 0 end
    $cb selection clear
    $cb icursor end
    event generate $cb <<ComboboxSelected>> -when mark
}
# and disable stray wheelmouse from changing the mf laugh
ttk::bindMouseWheel TCombobox {#}


# Check for old (single-directory) tablebase option:
if {[info exists initialDir(tablebase)]} {
  set initialDir(tablebase1) $initialDir(tablebase)
}

set fontsize [font configure font_Regular -size]
set font [font configure font_Regular -family]

font create font_Bold -family $font -size $fontsize -weight bold
font create font_BoldItalic -family $font -size $fontsize -weight bold \
    -slant italic
font create font_Italic -family $font -size $fontsize -slant italic
font create font_H1 -family $font -size [expr {$fontsize + 16} ] -weight bold
font create font_H2 -family $font -size [expr {$fontsize + 6} ] -weight bold
font create font_H3 -family $font -size [expr {$fontsize + 4} ] -weight bold
font create font_H4 -family $font -size [expr {$fontsize + 2} ] -weight bold
font create font_Large -family $font -size [expr {$fontsize + 3} ]

set fontsize [font configure font_Small -size]
set font [font configure font_Small -family]
font create font_SmallBold -family $font -size $fontsize -weight bold
font create font_SmallItalic -family $font -size $fontsize -slant italic

# Hidden-file dialog hack
# https://sourceforge.net/p/pure-data/patches/208/
catch {tk_getOpenFile -with-invalid-argument}
namespace eval ::tk::dialog::file {
  variable showHiddenBtn 1
  variable showHiddenVar 0
}

## ttk init
# Gregor's code to give readonly combos/enrties/spinboxes a non-grey background
set fbg {}
switch "_$::ttk::currentTheme" {
   _alt     { set fbg [list readonly white disabled [ttk::style lookup $::ttk::currentTheme -background]] }
   _clam    { set fbg [list readonly white {readonly focus} [ttk::style lookup $::ttk::currentTheme -selectbackground]] }
   _default { set fbg [list readonly white disabled [ttk::style lookup $::ttk::currentTheme -background]] }
}
if {[llength $fbg]} {
   ttk::style map TCombobox -fieldbackground $fbg
   ttk::style map TEntry -fieldbackground $fbg
   if {[info tclversion] >= "8.6"} {
      ttk::style map TSpinbox -fieldbackground $fbg
   }
}

# Start in the clipbase, if no database is loaded at startup.
sc_base switch clipbase
catch {::sibyDemarrage::avancer 30}

###
### End of file: start.tcl
