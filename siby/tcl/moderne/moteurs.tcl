
###
### Siby: detection and setup of Stockfish, Leela (lc0) and Toby
###
### - On first startup (no engines.dat file yet), SCID looks for
###   engines on the machine and adds them at the top of the
###   engine list (Stockfish on F2, Leela on F3), before Toga and Phalanx.
### - Tools menu › "Detect engines" to do it again
###   later (engines already present are not duplicated).
###
### Settings applied:
###   Stockfish: Threads = 1, Hash = 1/8 of memory (≤ 4 GB),
###              SyzygyPath if a Syzygy tablebase folder is found.
###   Leela:     lc0 default settings (it picks the best
###              backend by itself: CUDA on an NVIDIA card); network found
###              next to the program or in ~/.lc0 if present (not a Maia
###              network).
###   (no Maia alone: Toby has its own Maia)
###   Toby:      the toby program (Toby's folder, Siby's engines…), no option.
### WDL is enabled automatically for both (tcl/moderne/wdl.tcl).
###

namespace eval ::moderne::moteurs {}

### Folders to search for the programs, in addition to PATH
proc ::moderne::moteurs::dossiers {} {
  set d {}
  set sep [expr {$::windowsOS ? ";" : ":"}]
  if {[info exists ::env(PATH)]} { set d [split $::env(PATH) $sep] }
  set home [expr {[info exists ::env(HOME)] ? $::env(HOME) : "~"}]
  if {$::windowsOS} {
    # Windows: SCID folder (and its engines / moteurs subfolders),
    # user profile, Downloads, Program Files
    set ici [file dirname [info nameofexecutable]]
    if {[info exists ::env(USERPROFILE)]} { set home [file normalize $::env(USERPROFILE)] }
    set l [list $ici $ici/engines $ici/moteurs $home/stockfish $home/lc0 $home/Leela $home/Toby $home/maia \
               $home/Downloads $home/Téléchargements $home/Desktop $home/engines $home/moteurs]
    foreach v {ProgramFiles ProgramW6432 LOCALAPPDATA} {
      if {[info exists ::env($v)]} {
        set p [file normalize $::env($v)]
        lappend l $p/Stockfish $p/stockfish $p/lc0 $p/Lc0 $p/Leela
      }
    }
    catch {lappend l [file join $::scidUserDir engines]}
    return [concat $d [sousDossiers $l]]
  }
  # (Siby's own engines folder first: the "Add an engine" downloads, and the
  # archive's share/scid/engines)
  set l {}
  catch {lappend l [file join $::scidShareDir engines]}
  catch {lappend l [file join $::scidUserDir engines]}
  lappend l /usr/games /usr/local/games /usr/local/bin /opt/stockfish /opt/lc0 \
             $home/bin $home/.local/bin $home/stockfish $home/lc0 $home/Leela $home/leela $home/Toby $home/toby $home/maia \
             $home/engines $home/moteurs $home/.local/share/lc0 \
             $home/Downloads $home/Téléchargements $home/Desktop $home/Bureau
  foreach x [concat $l [sousDossiers $l]] {
    if {$x ni $d} { lappend d $x }
  }
  return $d
}

### Folders where official archives unpack, up to two levels down: the
### Windows "Extract all" makes a folder named after the zip, and the
### Stockfish archive has its own stockfish folder inside
### (Downloads/stockfish-windows-x86-64-avx2/stockfish/stockfish-….exe)
proc ::moderne::moteurs::sousDossiers {racines} {
  set res {}
  foreach x $racines {
    lappend res $x
    foreach sd [glob -nocomplain -types d -directory $x stockfish* Stockfish* lc0* Lc0* Leela* leela* toby* Toby* maia* Maia*] {
      lappend res $sd
      foreach sd2 [glob -nocomplain -types d -directory $sd stockfish* Stockfish* lc0* Lc0* Leela* leela* toby* Toby* maia* Maia*] {
        lappend res $sd2
      }
    }
  }
  return $res
}

### First executable found among the patterns (e.g. stockfish*, lc0)
proc ::moderne::moteurs::trouver {motifs} {
  foreach dir [dossiers] {
    foreach m $motifs {
      # (official Stockfish binaries are named stockfish-ubuntu-x86-64-avx2)
      if {$::windowsOS} { set m $m.exe }
      foreach f [lsort [glob -nocomplain -directory $dir -- $m]] {
        if {$::windowsOS && [string tolower [file extension $f]] ne ".exe"} { continue }
        if {[file isfile $f] && [file executable $f] && [file extension $f] ni {.txt .md .tar .gz .zip}} {
          return [file normalize $f]
        }
      }
    }
  }
  return {}
}

proc ::moderne::moteurs::coeurs {} {
  set n 0
  if {[info exists ::env(NUMBER_OF_PROCESSORS)]} { set n $::env(NUMBER_OF_PROCESSORS) }
  if {!$n} { catch {set n [exec nproc]} }
  if {![string is integer -strict $n] || $n < 1} {
    catch {set n [llength [regexp -all -inline -line {^processor} [exec cat /proc/cpuinfo]]]}
  }
  return [expr {$n < 1 ? 1 : $n}]
}

### Total memory in MB (Linux), 0 if unknown
proc ::moderne::moteurs::memoire {} {
  set mo 0
  catch {
    set f [open /proc/meminfo r]
    set t [read $f]
    close $f
    if {[regexp {MemTotal:\s+([0-9]+)} $t -> ko]} { set mo [expr {$ko / 1024}] }
  }
  # Windows: no /proc; assume 8 GB (1 GB Hash), adjustable later
  if {$mo == 0 && $::windowsOS} { set mo 8192 }
  return $mo
}

proc ::moderne::moteurs::dossierSyzygy {} {
  set home [expr {[info exists ::env(HOME)] ? $::env(HOME) : "~"}]
  set l [list $home/syzygy $home/Syzygy $home/tablebases $home/tb /usr/share/syzygy /opt/syzygy /usr/local/share/syzygy]
  if {$::windowsOS} {
    if {[info exists ::env(USERPROFILE)]} { set home [file normalize $::env(USERPROFILE)] }
    set l [list $home/syzygy $home/Syzygy $home/tablebases [file dirname [info nameofexecutable]]/syzygy C:/syzygy D:/syzygy C:/tablebases D:/tablebases]
  }
  foreach d $l {
    if {[file isdirectory $d] && [llength [glob -nocomplain -directory $d *.rtbw]]} { return $d }
  }
  return {}
}

proc ::moderne::moteurs::optionsStockfish {} {
  set opts {}
  set c [coeurs]
  # (1 CPU by default; change it in the engine window: "CPU − 1 +")
  lappend opts [list Threads 1]
  set mo [memoire]
  if {$mo > 0} {
    # 1/8 of memory, rounded to a power of 2, between 64 MB and 4 GB
    set h 64
    while {$h * 2 <= $mo / 8 && $h < 4096} { set h [expr {$h * 2}] }
    lappend opts [list Hash $h]
  }
  set tb [dossierSyzygy]
  if {$tb ne {}} { lappend opts [list SyzygyPath $tb] }
  return $opts
}

proc ::moderne::moteurs::optionsLeela {cmd} {
  set opts {}
  # Network: a weights file next to the program or in ~/.lc0
  set home [expr {[info exists ::env(HOME)] ? $::env(HOME) : "~"}]
  foreach d [list [file dirname $cmd] $home/.lc0 $home/.local/share/lc0] {
    set poids [lsearch -all -inline -not [lsort [glob -nocomplain -directory $d *.pb.gz *.pb *.onnx]] *maia*]
    if {[llength $poids]} { lappend opts [list WeightsFile [lindex $poids end]] ; break }
  }
  set tb [dossierSyzygy]
  if {$tb ne {}} { lappend opts [list SyzygyPath $tb] }
  return $opts
}


### Adds the engines found. enTete: put them at the top of the list and on
### F2 / F3 (first startup). Returns the list of names added.
proc ::moderne::moteurs::detecter {{enTete 0}} {
  global engines
  set existants {}
  foreach e $engines(list) { lappend existants [file normalize [lindex $e 1]] }
  set dir $::scidUserDir
  set nouveaux {}
  set sf [trouver {stockfish stockfish-* stockfish_*}]
  if {$sf ne {} && $sf ni $existants} {
    lappend nouveaux [list Stockfish $sf {} $dir 0 0 {} 1 [optionsStockfish]]
  }
  set lc0 [trouver {lc0}]
  if {$lc0 ne {} && $lc0 ni $existants} {
    lappend nouveaux [list "Leela (lc0)" $lc0 {} $dir 0 0 {} 1 [optionsLeela $lc0]]
  }
  # (Maia alone is not offered: Toby has its own Maia, and plays and
  # predicts better; Yosha's decision, 2026-10-27)
  # Toby
  set toby [trouver {toby toby-*}]
  if {$toby ne {} && $toby ni $existants} {
    lappend nouveaux [list "Toby - The Oracle By Yosha" $toby {} $dir 0 0 {} 1 {}]
  }
  if {![llength $nouveaux]} { return {} }
  if {$enTete} {
    set engines(list) [concat $nouveaux $engines(list)]
    set engines(F2) 0
    set engines(F3) 1
  } else {
    set engines(list) [concat $engines(list) $nouveaux]
  }
  catch {::enginelist::write}
  set noms {}
  foreach n $nouveaux { lappend noms "[lindex $n 0] ([lindex $n 1])" }
  return $noms
}

### Tools menu
proc ::moderne::moteurs::menu {} {
  set noms [detecter 0]
  if {[llength $noms]} {
    set msg "[::moderne::tr "Moteurs ajoutés :" "Engines added:"]\n[join $noms \n]\n\n[::moderne::tr \
        "Réglages modifiables dans Outils › Moteurs d'analyse." "Settings can be changed in Tools › Analysis Engines."]"
  } else {
    set msg [::moderne::tr \
        "Aucun nouveau moteur trouvé (Stockfish, Leela, Toby). Outils › Ajouter un moteur les télécharge en un clic." \
        "No new engine found (Stockfish, Leela, Toby). Tools › Add an engine downloads them in one click."]
  }
  tk_messageBox -type ok -icon info -title Siby -message $msg
}

### Engine priority: the order of the engine list is the priority order.
### The first engine starts with F2, the second with F3 ... the eighth with
### F9 (no key beyond 8 engines). Engines are reordered by dragging them in
### the list (or with the arrow buttons).
proc ::moderne::moteurs::touches {} {
  global engines
  if {![info exists engines(list)]} { return }
  set n [llength $engines(list)]
  for {set i 0} {$i < 8} {incr i} {
    set engines(F[expr {$i + 2}]) [expr {$i < $n ? $i : {}}]
  }
}

proc startAnalysisWin {FunctionKey} {
  # (one press, one start: the key is caught by the focused window's own
  # binding and by the global one below)
  if {[info exists ::moderne::moteurs::toucheVue($FunctionKey)]} { return }
  set ::moderne::moteurs::toucheVue($FunctionKey) 1
  after idle [list unset -nocomplain ::moderne::moteurs::toucheVue($FunctionKey)]
  ::moderne::moteurs::touches
  if {![info exists ::engines($FunctionKey)]} { return }
  set n $::engines($FunctionKey)
  if {$n ne {}} { makeAnalysisWin $n }
}

if {[llength [info commands ::enginelist::write_scid]] == 0} {
  rename ::enginelist::write ::enginelist::write_scid
  rename ::enginelist::listEngines ::enginelist::listEngines_scid
  rename ::enginelist::choose ::enginelist::choose_scid
  rename ::enginelist::edit ::enginelist::edit_scid
}

proc ::enginelist::write {} {
  ::moderne::moteurs::touches
  ::enginelist::write_scid
  # (the Engines window shows the list as it is now)
  catch {after idle ::moderne::ajout::listeMoteurs}
}

### The Key column shows F2 to F9 by position
proc ::enginelist::listEngines {{focus 0}} {
  ::moderne::moteurs::touches
  ::enginelist::listEngines_scid $focus
  set l .enginelist.list.list
  if {![winfo exists $l]} { return }
  set sel [$l curselection]
  set n [$l size]
  # the name column as wide as the longest name (SCID cut names at 24 letters)
  set larg 24
  foreach e $::engines(list) { set larg [expr {max($larg, [string length [lindex $e 0]])}] }
  for {set i 0} {$i < $n} {incr i} {
    set t [$l get $i]
    set cle [expr {$i < 8 ? [format "  F%d  " [expr {$i + 2}]] : "      "}]
    set nom [format "%-${larg}s" [lindex [lindex $::engines(list) $i] 0]]
    set t "$nom$cle[string range $t 30 end]"
    $l delete $i
    $l insert $i $t
  }
  set titre .enginelist.title
  if {[winfo exists $titre]} {
    $titre configure -state normal -width [expr {max(93, $larg + 69)}]
    $titre delete 1.0 end
    $titre insert end [format "%-${larg}s %4s %5s %8s %8s" \
        $::tr(EngineName) $::tr(EngineKey) $::tr(EngineType) $::tr(EngineElo) $::tr(EngineTime)]
    $titre configure -state disabled
  }
  foreach i $sel { $l selection set $i }
  if {[llength $sel]} { $l see [lindex $sel 0] }
}

### Tools › Engines: Siby's Engines window (my engines and adding one);
### SCID's window is "Advanced settings" there
proc ::enginelist::choose {} {
  ::moderne::ajout::ouvrir
}

### SCID's engines window, with Siby's drag and drop and F2-F9 keys
proc ::enginelist::choose_ancien {} {
  ::enginelist::choose_scid
  set w .enginelist
  set l $w.list.list
  if {![winfo exists $l]} { return }
  if {![winfo exists $w.aide]} {
    ttk::label $w.aide -font font_Small -text [::moderne::tr \
        "Glisse un moteur pour changer l'ordre : les 8 premiers se lancent avec F2 à F9." \
        "Drag an engine to change the order: the first 8 start with F2 to F9."]
    pack $w.aide -side top -anchor w -padx 8 -after $w.list
  }
  # the hand: the rows can be taken and moved
  $l configure -cursor hand2
  bind $l <ButtonPress-1> {+::moderne::moteurs::glisserDebut %W %y}
  bind $l <B1-Motion> {+::moderne::moteurs::glisserVers %W %y}
  bind $l <ButtonRelease-1> {+::moderne::moteurs::glisserFin %W %y}
  ::enginelist::listEngines [expr {[llength [$l curselection]] ? [lindex [$l curselection] 0] : 0}]
}

### Drag and drop in the engine list: the hand shows the rows can be moved,
### the engine taken is highlighted and follows the pointer's row
proc ::moderne::moteurs::glisserDebut {l y} {
  variable glisse [$l nearest $y]
  $l configure -cursor fleur
  catch {$l itemconfigure $glisse -background [::moderne::c accentFonce] -foreground white}
}

proc ::moderne::moteurs::glisserVers {l y} {
  variable glisse
  if {![info exists glisse]} { return }
  set v [$l nearest $y]
  # the drop place: a line under the target row
  for {set i 0} {$i < [$l size]} {incr i} {
    if {$i != $glisse} { catch {$l itemconfigure $i -background {}} }
  }
  if {$v != $glisse} {
    catch {$l itemconfigure $v -background [::moderne::c survol]}
  }
}

proc ::moderne::moteurs::glisserFin {l y} {
  global engines
  variable glisse
  if {![info exists glisse]} { return }
  set de $glisse
  unset glisse
  $l configure -cursor hand2
  for {set i 0} {$i < [$l size]} {incr i} { catch {$l itemconfigure $i -background {} -foreground {}} }
  set vers [$l nearest $y]
  if {$de eq {} || $vers eq {} || $de == $vers} { return }
  ::moderne::moteurs::deplacer $de $vers
}

### Moves engine de to position vers. The analysis windows are numbered by
### list position: the engines running are closed, the list reordered, and
### they are started again at their new place (not during a game)
proc ::moderne::moteurs::deplacer {de vers} {
  global engines
  if {[winfo exists .serGameWin] || [winfo exists .comp] || [winfo exists .calvarWin]} {
    tk_messageBox -title Siby -icon info -parent [expr {[winfo exists .enginelist] ? ".enginelist" : "."}] -message [::moderne::tr \
        "Une partie contre un moteur est en cours : l'ordre des moteurs ne peut pas changer maintenant." \
        "A game against an engine is in progress: the engines' order cannot change now."]
    ::enginelist::listEngines $de
    return 0
  }
  # (the panels change place in their own tab, the layout stays as it is:
  # rebuilding the whole layout was too much, 2026-10-29)
  if {$::docking::USE_DOCKING && ![catch {echangerSurPlace $de $vers} ok] && $ok} {
    return 1
  }
  # the layout, saved before the engine windows close (closing them would
  # empty and remove their blocks): restored afterwards with the new numbers
  set disp {}
  if {$::docking::USE_DOCKING && [regexp {analysisWin} [winfo children .]] &&
      ![catch {::docking::layout_save moderne_reordre} ok] && $ok} {
    set disp $::docking::layout_list(moderne_reordre)
  }
  # new place of each engine (old number -> new number)
  set idx {}
  for {set n 0} {$n < [llength $engines(list)]} {incr n} { lappend idx $n }
  set idx [linsert [lreplace $idx $de $de] $vers $de]
  # engines running: remembered by their entry, closed
  set lances {}
  for {set n 0} {$n < [llength $engines(list)]} {incr n} {
    if {[winfo exists .analysisWin$n]} {
      lappend lances [lindex $engines(list) $n]
      catch {destroy .analysisWin$n}
    }
  }
  update
  set e [lindex $engines(list) $de]
  set engines(list) [linsert [lreplace $engines(list) $de $de] $vers $e]
  ::enginelist::listEngines $vers
  ::enginelist::write
  if {$disp ne {}} {
    # same layout, each engine in the block it had
    set carte {}
    for {set n 0} {$n < [llength $idx]} {incr n} {
      lappend carte "fdockanalysisWin[lindex $idx $n]\}" "fdockanalysisWin@$n\}"
      lappend carte "fdockanalysisWin[lindex $idx $n] " "fdockanalysisWin@$n "
    }
    set disp [string map $carte $disp]
    set disp [string map {fdockanalysisWin@ fdockanalysisWin} $disp]
    set ::docking::layout_list(moderne_reordre) $disp
    # the engines that ran run again at their new place, the paused ones stay paused
    set aLancer {}
    foreach x $lances {
      set n [lsearch -exact $engines(list) $x]
      if {$n >= 0} { lappend aLancer $n ; set ::moderne::docks::lancer($n) 1 }
    }
    ::docking::layout_restore moderne_reordre
    foreach n $aLancer {
      after 800 [list catch [list ::moderne::disposition::demarrer $n]]
    }
    return 1
  }
  # started again at their new place
  foreach x $lances {
    set n [lsearch -exact $engines(list) $x]
    if {$n >= 0} { after 300 [list catch [list makeAnalysisWin $n]] }
  }
  return 1
}

### Engine "de" moved to place "vers" without touching the layout: each
### open panel (running or paused) is made again under its new number, in
### the same tab group and at the same tab, the running ones run again.
### 0 if it can't (then the layout is rebuilt as before).
proc ::moderne::moteurs::echangerSurPlace {de vers} {
  global engines
  set nbM [llength $engines(list)]
  # where each engine's panel is: {entry kind notebook tab-index selected running}
  set places {}
  for {set n 0} {$n < $nbM} {incr n} {
    set f .fdockanalysisWin$n
    set p .fdockattenteanalysisWin$n
    if {[winfo exists .analysisWin$n] && [winfo exists $f]} {
      set nb [::docking::find_tbn $f]
      if {$nb eq {} || ![winfo exists $nb]} { return 0 }
      lappend places [list [lindex $engines(list) $n] moteur $nb [$nb index $f] \
          [expr {[$nb select] eq $f}] [expr {[info exists ::analysis(analyzeMode$n)] && $::analysis(analyzeMode$n)}]]
    } elseif {[winfo exists $p] && ![catch {::docking::find_tbn $p} nb] && $nb ne {} && [winfo exists $nb]
              && [lsearch -exact [$nb tabs] $p] >= 0} {
      lappend places [list [lindex $engines(list) $n] pause $nb [$nb index $p] [expr {[$nb select] eq $p}] 0]
    } elseif {[winfo exists .analysisWin$n]} {
      # (an undocked engine window: the layout way)
      return 0
    }
  }
  # (the sashes of the panes holding them, put back at the end: the new
  # panels would ask for other widths)
  set sashes {}
  foreach pl $places {
    set nb [lindex $pl 2]
    if {![info exists ::docking::tbs($nb)]} { continue }
    set pw $::docking::tbs($nb)
    if {[dict exists $sashes $pw] || ![winfo exists $pw]} { continue }
    set l {}
    for {set i 0} {$i < [llength [$pw panes]] - 1} {incr i} { lappend l [$pw sashpos $i] }
    dict set sashes $pw $l
  }
  # (a placeholder in each tab group, so that none empties and goes)
  set gardes {}
  set k 0
  foreach pl $places {
    set nb [lindex $pl 2]
    if {[winfo exists $nb.gardeOrdre]} { continue }
    frame $nb.gardeOrdre
    $nb add $nb.gardeOrdre -text " "
    lappend gardes $nb.gardeOrdre
  }
  # the panels go
  for {set n 0} {$n < $nbM} {incr n} {
    if {[winfo exists .analysisWin$n]} { catch {destroy .analysisWin$n} }
    set p .fdockattenteanalysisWin$n
    if {[winfo exists $p]} {
      catch {[::docking::find_tbn $p] forget $p}
      catch {destroy $p}
    }
  }
  update idletasks
  set e [lindex $engines(list) $de]
  set engines(list) [linsert [lreplace $engines(list) $de $de] $vers $e]
  ::enginelist::listEngines $vers
  ::enginelist::write
  # each panel made again under its new number, where it was
  set aLancer {}
  foreach pl [lsort -integer -index 3 $places] {
    lassign $pl entree type nb idx choisi tourne
    set m [lsearch -exact $engines(list) $entree]
    if {$m < 0 || ![winfo exists $nb]} { continue }
    if {$type eq "pause"} {
      ::moderne::docks::placeEnPause $nb .fdockanalysisWin$m $m
      set t .fdockattenteanalysisWin$m
    } else {
      set ::docking::layout_dest_notebook $nb
      catch {makeAnalysisWin $m}
      set ::docking::layout_dest_notebook {}
      set t .fdockanalysisWin$m
      if {$tourne} { lappend aLancer $m }
    }
    if {[winfo exists $t] && [::docking::find_tbn $t] ne $nb} {
      # (made in a group of its own beside: brought back, the group goes)
      set src [::docking::find_tbn $t]
      catch {$src forget $t}
      catch {$nb add $t -text [lindex $entree 0]}
      catch {::docking::_cleanup_tabs $src}
    }
    catch {$nb insert $idx $t}
    if {$choisi} { catch {$nb select $t} }
  }
  foreach g $gardes {
    catch {[winfo parent $g] forget $g}
    catch {destroy $g}
  }
  catch ::docking::setTabStatus
  # (again once the engines have drawn their panels)
  foreach t {0 400 1500} {
    after $t [list ::moderne::moteurs::remettreSashes $sashes]
  }
  foreach m $aLancer {
    after 300 [list catch [list ::moderne::disposition::demarrer $m]]
  }
  return 1
}

proc ::moderne::moteurs::remettreSashes {sashes} {
  update idletasks
  dict for {pw l} $sashes {
    if {![winfo exists $pw]} { continue }
    set i 0
    foreach x $l { catch {$pw sashpos $i $x} ; incr i }
  }
}

### Edit dialog: the shortcut follows the position, so the old F2/F3/F4
### choice is replaced by a note
proc ::enginelist::edit {index {copy {}}} {
  ::enginelist::edit_scid $index $copy
  set w .engineEdit
  if {![winfo exists $w.radio]} { return }
  foreach c [winfo children $w.radio] { pack forget $c }
  if {$index ne {} && $index >= 0 && $index < 8 && $copy eq {}} {
    set txt [::moderne::tr "Raccourci : F[expr {$index + 2}] (selon la place dans la liste)" \
        "Hot key: F[expr {$index + 2}] (from the position in the list)"]
  } else {
    set txt [::moderne::tr "Raccourci : selon la place dans la liste (F2 à F9)" \
        "Hot key: from the position in the list (F2 to F9)"]
  }
  pack [ttk::label $w.radio.siby -text $txt] -side left -padx 8 -pady 4
  foreach k {F2 F3 F4} { bind $w <$k> {} }
}

::moderne::moteurs::touches

### F2 to F9 wherever the keyboard is in the main window (a panel, the
### library, the preparation...), not only on the board: after the Engines
### window, F2 did nothing (Yosha 2026-11-04)
foreach k {F2 F3 F4 F5 F6 F7 F8 F9} {
  bind all <$k> [list +apply {{w k} {
    if {[winfo exists $w] && [winfo toplevel $w] eq "."} { startAnalysisWin $k }
  }} %W $k]
}

### First startup: tcl/tools/analysis.tcl created the default list
### (Toga, Phalanx, Scidlet) since there is no engines.dat; Stockfish and
### Leela are added at the top.
if {[info exists ::moderne_moteursParDefaut] && $::moderne_moteursParDefaut} {
  catch {::moderne::moteurs::detecter 1}
}

### End Siby
