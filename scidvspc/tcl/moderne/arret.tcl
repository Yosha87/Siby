###
### Siby: Windows shutting down (or logging off) while Siby is open
###
### Windows asks every program whether it may close (WM_QUERYENDSESSION,
### which Tk turns into the WM_SAVE_YOURSELF protocol). Siby must answer at
### once: no dialog (a dialog at that moment blocks the shutdown screen).
### The unsaved games are written to a recovery PGN file, the options are
### saved, the engines are stopped, and Siby quits. At the next start, a
### notice says where the recovered games are.
###

namespace eval ::moderne::arret {
  variable enCours 0
}

proc ::moderne::arret::T {fr en} { return [::moderne::tr $fr $en] }

proc ::moderne::arret::fichier {} {
  return [file join $::scidUserDir "recuperation-arret.pgn"]
}

proc ::moderne::arret::installer {} {
  foreach w [list . $::dot_w] { catch {wm protocol $w WM_SAVE_YOURSELF ::moderne::arret::windows} }
}

### Is the session ending? (engine deaths are then not reported)
proc ::moderne::arret::actif {} {
  variable enCours
  return $enCours
}

proc ::moderne::arret::windows {} {
  variable enCours
  if {$enCours} { return }
  set enCours 1
  # 1. the unsaved games, into the recovery file
  catch {
    set pgn {}
    set courante [sc_base current]
    for {set i 1} {$i <= [sc_base count total]} {incr i} {
      if {[catch {sc_base switch $i}]} { continue }
      if {[sc_base inUse] && [sc_game altered]} { append pgn [::moderne::pgnAnglais -width 80] "\n\n" }
    }
    catch {sc_base switch $courante}
    if {$pgn ne {}} {
      set f [open [fichier] a]
      fconfigure $f -encoding utf-8
      puts $f $pgn
      close $f
    }
  }
  # 2. options, recent files
  catch {if {$::optionsAutoSave} { .menu.options invoke [tr OptionsSave] }}
  catch ::recentFiles::save
  catch ::utils::history::Save
  # 3. engines and downloads stopped
  arreterProcessus
  exit 0
}

### Every process Siby started, stopped: analysis engines, Toby (kept
### loaded between analyses, with its own Stockfish / Leela), the review's
### and the level's engines, engines started in advance, broadcast and
### download streams (curl). On Windows a child process outlives Siby
### otherwise, and keeps Siby's folder in use (it cannot be deleted:
### "in use by another program", Yosha 2026-11-01). The whole tree of each
### process is stopped (taskkill /T).
proc ::moderne::arret::arreterProcessus {} {
  catch ::moderne::direct::arreterFlux
  foreach c [chan names] {
    if {[catch {pid $c} pids] || ![llength $pids]} { continue }
    catch {fileevent $c readable {}}
    catch {fileevent $c writable {}}
    foreach p $pids {
      if {$::windowsOS} {
        catch {exec taskkill /F /T /PID $p}
      } else {
        # (its children first: Toby's engines)
        catch {exec pkill -KILL -P $p}
        catch {exec kill -KILL $p}
      }
    }
    catch {fconfigure $c -blocking 0}
    catch {close $c}
  }
}

################################################################################
### Engines that stop or hang (Yosha 2026-11-05). An analysis engine that
### dies while it analyses gets its module back and its analysis restarted;
### one that analyses is asked "isready" every 30 s, and stopped and
### restarted when "readyok" has not come 20 s later (UCI engines answer it
### even while searching). At most 3 restarts in 2 minutes per engine.
################################################################################

namespace eval ::moderne::sante {
  variable periode 30000      ;# ms between two pings
  variable delai 20000        ;# ms without readyok: hung
  variable relances           ;# relances(n) = times of its restarts
  array set relances {}
  variable pings              ;# pings(n) = {count sent-at} of our pings waiting
  array set pings {}
  variable attente            ;# attente(n) = since when Siby waits for its readyok
  array set attente {}
  variable vu                 ;# vu(n) = pipe of engine n once it answered a readyok
  array set vu {}             ;# (before: still loading, e.g. Toby's networks)
  # (SIBY_SANTE_PERIODE=ms: more often, for the tests)
  if {[info exists ::env(SIBY_SANTE_PERIODE)] && [string is integer -strict $::env(SIBY_SANTE_PERIODE)]} {
    set periode $::env(SIBY_SANTE_PERIODE)
  }
}
proc ::moderne::sante::T {fr en} { return [::moderne::tr $fr $en] }
proc ::moderne::sante::nom {n} {
  set e [lindex $::engines(list) $n]
  return [expr {$e ne {} ? [lindex $e 0] : "?"}]
}

### May engine n be restarted now? (noted if so)
proc ::moderne::sante::permis {n} {
  variable relances
  set t [clock milliseconds]
  set l {}
  if {[info exists relances($n)]} { foreach x $relances($n) { if {$t - $x < 120000} { lappend l $x } } }
  if {[llength $l] >= 3} { set relances($n) $l ; return 0 }
  lappend l $t
  set relances($n) $l
  return 1
}

### Engine n died (checkEngineIsAlive): 1 if it is restarted (no other notice)
proc ::moderne::sante::arrete {n analysait} {
  variable pings
  unset -nocomplain pings($n)
  if {!$analysait || [::moderne::arret::actif] || ![permis $n]} { return 0 }
  catch {::moderne::journal "Siby: engine [nom $n] stopped, restarted"}
  after 1000 [list ::moderne::sante::relancer $n [T "[nom $n] s'est arrêté : relancé." "[nom $n] stopped: restarted."]]
  return 1
}

proc ::moderne::sante::relancer {n annonce} {
  if {[winfo exists .analysisWin$n]} { return }
  if {[catch {makeAnalysisWin $n} err]} {
    catch {::moderne::journal "Siby: engine [nom $n] not restarted: $err"}
    return
  }
  catch {::moderne::nsb::annonce $annonce -1 ; after 6000 {catch ::moderne::nsb::finAnnonce}}
  after 1500 [list ::moderne::sante::reprendre $n 0]
}

### Its analysis started again once the engine is ready
proc ::moderne::sante::reprendre {n essai} {
  global analysis
  if {![winfo exists .analysisWin$n]} { return }
  if {[info exists analysis(analyzeMode$n)] && $analysis(analyzeMode$n)} { return }
  set pret 1
  catch {if {$analysis(uci$n)} { set pret $::uci::uciInfo(uciok$n) }}
  if {!$pret && $essai < 40} { after 500 [list ::moderne::sante::reprendre $n [incr essai]] ; return }
  catch {toggleEngineAnalysis $n}
}

### "readyok" of engine n: 1 if it answers one of our pings
proc ::moderne::sante::readyok {n} {
  variable pings
  variable vu
  catch {set vu($n) $::analysis(pipe$n)}
  if {![info exists pings($n)]} { return 0 }
  lassign $pings($n) k t
  if {$k <= 1} { unset pings($n) } else { set pings($n) [list [expr {$k - 1}] $t] }
  return 1
}

proc ::moderne::sante::boucle {} {
  variable periode
  catch ::moderne::sante::verifier
  after $periode ::moderne::sante::boucle
}

proc ::moderne::sante::verifier {} {
  global analysis
  variable pings
  variable delai
  set t [clock milliseconds]
  for {set n 0} {$n < [llength $::engines(list)]} {incr n} {
    if {![winfo exists .analysisWin$n] || ![info exists analysis(pipe$n)] || $analysis(pipe$n) eq {}} { unset -nocomplain pings($n) ; continue }
    if {![info exists analysis(analyzeMode$n)] || !$analysis(analyzeMode$n)} { unset -nocomplain pings($n) ; continue }
    if {![info exists analysis(uci$n)] || !$analysis(uci$n)} { continue }
    # (an engine that never answered yet is still loading)
    variable vu
    if {![info exists vu($n)] || $vu($n) ne $analysis(pipe$n)} { unset -nocomplain attente($n) ; continue }
    if {[info exists pings($n)]} {
      lassign $pings($n) k envoi
      if {$t - $envoi >= $delai} { bloque $n }
      continue
    }
    # (not while Siby itself waits for a readyok, a position just sent; but
    # waiting for it too long is a hang as well)
    variable attente
    if {[info exists analysis(waitForReadyOk$n)] && $analysis(waitForReadyOk$n)} {
      if {![info exists attente($n)]} { set attente($n) $t }
      if {$t - $attente($n) >= $delai} { unset attente($n) ; bloque $n }
      continue
    }
    unset -nocomplain attente($n)
    set pings($n) [list 1 $t]
    catch {sendToEngine $n isready}
  }
}

### Engine n does not answer: stopped (its whole process tree), restarted
proc ::moderne::sante::bloque {n} {
  global analysis
  variable pings
  variable attente
  unset -nocomplain pings($n) attente($n)
  set c $analysis(pipe$n)
  catch {::moderne::journal "Siby: engine [nom $n] not answering, stopped"}
  catch {fileevent $c readable {}}
  if {![catch {pid $c} pids]} {
    foreach p $pids {
      if {$::windowsOS} { catch {exec taskkill /F /T /PID $p} } else { catch {exec pkill -KILL -P $p} ; catch {exec kill -KILL $p} }
    }
  }
  catch {fconfigure $c -blocking 0}
  catch {close $c}
  set analysis(pipe$n) {}
  catch {destroy .analysisWin$n}
  if {[permis $n]} {
    after 1000 [list ::moderne::sante::relancer $n [T "[nom $n] ne répondait plus : relancé." "[nom $n] was not answering: restarted."]]
  } else {
    catch {::moderne::arret::moteurArrete -message [T "[nom $n] ne répond plus." "[nom $n] is not answering."]}
  }
}

after idle {after 5000 ::moderne::sante::boucle}

### At startup: games recovered at the last shutdown
proc ::moderne::arret::verifier {} {
  set f [fichier]
  if {![file exists $f] || [file size $f] == 0} { return }
  set dest [file join $::scidUserDir "recuperation-[clock format [file mtime $f] -format %Y-%m-%d_%H%M].pgn"]
  catch {file rename -force $f $dest}
  after 3000 [list ::moderne::arret::annoncer $dest]
}

### A notice at the bottom right, in Siby's style (as the reference
### database's offer), instead of a system message box: how many games
### were kept, where, and a button to open them (Yosha, 2026-11-01)
proc ::moderne::arret::annoncer {dest} {
  set n 0
  catch {
    set f [open $dest r]
    fconfigure $f -encoding utf-8
    set n [regexp -all -line {^\[Event } [read $f]]
    close $f
  }
  ::moderne::notice .recuperation [T "Parties récupérées" "Games recovered"] [expr {$n == 1 \
      ? [T "Windows a fermé Siby en s'arrêtant. La partie non enregistrée a été gardée." \
           "Windows closed Siby when shutting down. The unsaved game was kept."] \
      : [T "Windows a fermé Siby en s'arrêtant. Les $n parties non enregistrées ont été gardées." \
           "Windows closed Siby when shutting down. The $n unsaved games were kept."]}] \
      $dest [expr {$n == 1 ? [T "Ouvrir la partie" "Open the game"] : [T "Ouvrir ces parties" "Open these games"]}] \
      [list ::moderne::arret::ouvrir $dest] [T "Plus tard" "Later"]
}

### The recovered games opened as a database (added to My databases)
proc ::moderne::arret::ouvrir {dest} {
  catch {destroy .recuperation}
  if {[catch {::moderne::mesbases::ouvrirBase $dest}]} { catch {::file::Open $dest} }
}

### An engine stopped by itself: nothing while the session ends; a notice
### that does not block Siby otherwise (a modal box would hold Windows'
### shutdown if it came then)
proc ::moderne::arret::moteurArrete {args} {
  if {[actif]} { return }
  set msg [dict get $args -message]
  if {[catch {::moderne::nsb::annonce $msg -1}]} {
    after idle [list tk_messageBox -type ok -icon info -title Siby -message $msg]
    return
  }
  after 6000 {catch ::moderne::nsb::finAnnonce}
}

###
### Siby and Windows' files (2026-11-01): one Siby at a time (start.tcl
### hands a second start's files over by DDE), and .pgn / .si4 opened with
### Siby. Windows 10 and 11 do not let a program make itself the default:
### Siby registers itself for the current user (no administrator rights:
### HKEY_CURRENT_USER), so it is offered in "Open with" and listed in
### Windows' default apps, which opens for the user to choose.
###

namespace eval ::moderne::systeme {
  variable pret 0
}

proc ::moderne::systeme::T {fr en} { return [::moderne::tr $fr $en] }

### Files handed over by another start of Siby (or given at start): opened,
### and Siby to the front
proc ::moderne::systeme::recevoir {} {
  variable pret
  if {!$pret} { return }
  set fichiers {}
  foreach l $::sibyRecus { lappend fichiers {*}$l }
  set ::sibyRecus {}
  catch {wm deiconify .}
  catch {raise .}
  catch {focus -force .}
  foreach f $fichiers {
    if {[catch {::moderne::mesbases::ouvrirBase $f}]} { catch {::file::Open $f} }
  }
}

### At startup: the files that came while Siby was starting; the
### registration kept up to date (the portable folder may have moved); the
### offer, once, on Windows
proc ::moderne::systeme::demarrage {} {
  variable pret
  set pret 1
  after 1500 ::moderne::systeme::recevoir
  if {!$::windowsOS} { return }
  if {$::moderne::systeme::associe} { catch {associer} }
  # (not during tests: SIBY_INSTANCES_MULTIPLES, set by the test harnesses)
  if {!$::moderne::systeme::demande && ![info exists ::env(SIBY_INSTANCES_MULTIPLES)]} { after 8000 {::moderne::systeme::proposer 0} }
}

### The program Windows starts for a file: Siby.exe at the top of the
### portable folder (the launcher), else bin\Siby.exe
proc ::moderne::systeme::exe {} {
  set bin [file dirname [info nameofexecutable]]
  set lanceur [file join [file dirname $bin] Siby.exe]
  if {[file exists $lanceur]} { return $lanceur }
  return [info nameofexecutable]
}

### Registers Siby for .pgn and .si4 (current user). Only what changed is
### written (a new version unzipped elsewhere: new paths); Explorer is then
### told, otherwise it kept its cached icons, or a blank one, for a while
proc ::moderne::systeme::associer {{exts {.pgn .si4}}} {
  package require registry
  variable change 0
  set exe [file nativename [exe]]
  set cmd "\"$exe\" \"%1\""
  set icone "\"[file nativename [info nameofexecutable]]\",0"
  set classes {HKEY_CURRENT_USER\Software\Classes}
  foreach {ext progid desc} [list \
      .pgn Siby.pgn [T "Parties d'échecs PGN (Siby)" "PGN chess games (Siby)"] \
      .si4 Siby.si4 [T "Base Siby" "Siby database"]] {
    if {$ext ni $exts} { continue }
    ecrire "$classes\\$progid" {} $desc
    ecrire "$classes\\$progid\\DefaultIcon" {} $icone
    ecrire "$classes\\$progid\\shell\\open\\command" {} $cmd
    ecrire "$classes\\$ext\\OpenWithProgids" $progid {} none
    # (the default only where no program has the extension yet; otherwise
    # Windows asks the user, who chooses in its settings)
    if {[catch {registry get "$classes\\$ext" {}} v] || $v eq {}} {
      ecrire "$classes\\$ext" {} $progid
    }
    # (Siby chosen with Windows' "Open with > Choose another app": Windows
    # then uses Applications\Siby.exe, which had no icon: blank files)
    ecrire "$classes\\Applications\\Siby.exe\\SupportedTypes" $ext {}
  }
  ecrire "$classes\\Applications\\Siby.exe" FriendlyAppName Siby
  ecrire "$classes\\Applications\\Siby.exe\\DefaultIcon" {} $icone
  ecrire "$classes\\Applications\\Siby.exe\\shell\\open\\command" {} $cmd
  # Windows' default apps list
  set cap {HKEY_CURRENT_USER\Software\Siby\Capabilities}
  ecrire $cap ApplicationName Siby
  ecrire $cap ApplicationDescription [T "Bases et analyse d'échecs" "Chess databases and analysis"]
  foreach ext $exts { ecrire "$cap\\FileAssociations" $ext Siby[string range $ext 0 end] }
  ecrire {HKEY_CURRENT_USER\Software\RegisteredApplications} Siby {Software\Siby\Capabilities}
  set ::moderne::systeme::associe 1
  if {$change} { catch sc_associations }
}

### A registry value written only if it differs (notes the change)
proc ::moderne::systeme::ecrire {cle nom valeur {type sz}} {
  variable change
  if {![catch {registry get $cle $nom} v] && $v eq $valeur} { return }
  registry set $cle $nom $valeur $type
  set change 1
}

### Uninstall (Windows): Windows' registrations of Siby removed (current
### user), then the program folder deleted once Siby has closed. Never the
### user's files: Documents\Siby (databases, settings, notes, Gaby,
### engines) stays, and a Siby unzipped again finds everything there.
proc ::moderne::systeme::desinstaller {} {
  if {!$::windowsOS} { return }
  set prog [file normalize [file dirname [file dirname [info nameofexecutable]]]]
  set docs [file normalize $::sibyDocsDir]
  set r [tk_messageBox -parent . -icon question -type yesno -default no -title [T "Désinstaller Siby" "Uninstall Siby"] \
      -message [T "Désinstaller Siby ?" "Uninstall Siby?"] \
      -detail "[T "Tes bases et tes réglages restent dans" "Your databases and settings stay in"] [file nativename $docs]."]
  if {$r ne "yes"} { return }
  catch desenregistrer
  # (a reinstalled Siby asks again before taking the files)
  set ::moderne::systeme::associe 0
  set ::moderne::systeme::demande 0
  catch ::options.write
  # the program folder: only when it is surely Siby's and holds none of the
  # user's files
  if {[dossierSupprimable $prog $docs]} { supprimerApres $prog [pid] }
  # (the normal way out: unsaved games are offered for saving; the folder
  # goes once Siby has really ended)
  after 200 ::file::Exit
}

### Folder prog deleted once process pidAttendu has ended (a small script
### of Windows' own, started now, waiting in the background)
proc ::moderne::systeme::supprimerApres {prog pidAttendu} {
  set tmp [expr {[info exists ::env(TEMP)] ? $::env(TEMP) : $::scidUserDir}]
  set bat [file join $tmp siby-desinstaller-$pidAttendu.cmd]
  set f [open $bat w]
  fconfigure $f -translation crlf -encoding cp1252
  puts $f "@echo off"
  puts $f ":attendre"
  puts $f "tasklist /fi \"PID eq $pidAttendu\" | find \"$pidAttendu\" >nul && (ping -n 2 127.0.0.1 >nul & goto attendre)"
  puts $f "rmdir /s /q \"[file nativename $prog]\""
  puts $f "del \"%~f0\""
  close $f
  # ("start" alone ran the script with cmd /K: its console stayed open)
  exec cmd.exe /c start "" /min cmd.exe /c [file nativename $bat] &
}

### Is folder prog Siby's own (bin\Siby.exe in it), without the user's files
### in it (nor it in theirs), and not a drive, the home folder or Documents?
proc ::moderne::systeme::dossierSupprimable {prog docs} {
  if {![file exists [file join $prog bin Siby.exe]]} { return 0 }
  set p [string tolower $prog/] ; set d [string tolower $docs/]
  if {[string first $p $d] == 0 || [string first $d $p] == 0} { return 0 }
  if {[llength [file split $prog]] < 3} { return 0 }
  foreach x [list [file normalize ~] [file normalize ~/Documents] [file normalize ~/Desktop]] {
    if {[string tolower $prog] eq [string tolower $x]} { return 0 }
  }
  return 1
}

### Windows' registrations of Siby (current user) removed: its file types,
### its place in "Open with" and in the default apps
proc ::moderne::systeme::desenregistrer {} {
  package require registry
  set classes {HKEY_CURRENT_USER\Software\Classes}
  foreach {ext progid} {.pgn Siby.pgn .si4 Siby.si4} {
    catch {registry delete "$classes\\$progid"}
    catch {registry delete "$classes\\$ext\\OpenWithProgids" $progid}
    if {![catch {registry get "$classes\\$ext" {}} v] && $v eq $progid} {
      catch {registry delete "$classes\\$ext" {}}
    }
  }
  catch {registry delete "$classes\\Applications\\Siby.exe"}
  catch {registry delete {HKEY_CURRENT_USER\Software\Siby}}
  catch {registry delete {HKEY_CURRENT_USER\Software\RegisteredApplications} Siby}
  catch sc_associations
}

### The default apps settings of Windows, on Siby when possible
proc ::moderne::systeme::parametres {} {
  if {[catch {exec cmd.exe /c start "" "ms-settings:defaultapps?registeredAppUser=Siby" &}]} {
    catch {exec cmd.exe /c start "" "ms-settings:defaultapps" &}
  }
}

### The offer (demande 0: at first start, a notice; 1: from the menu)
proc ::moderne::systeme::proposer {depuisMenu} {
  variable choix
  set ::moderne::systeme::demande 1
  catch ::options.write
  foreach e {pgn si4} { if {![info exists choix($e)]} { set choix($e) 1 } }
  set w [::moderne::notice .fichiersSiby [T "Ouvrir vos parties avec Siby ?" "Open your games with Siby?"] \
      [T "Siby peut ouvrir ces fichiers d'un double-clic :" "Siby can open these files with a double click:"] \
      {} [T "Oui" "Yes"] ::moderne::systeme::faire [T "Pas maintenant" "Not now"]]
  # the choice: PGN files, Siby databases, or both
  set fond [::moderne::c surface2]
  frame $w.ext -background $fond
  foreach {e lib} [list pgn [T "Fichiers PGN (.pgn)" "PGN files (.pgn)"] si4 [T "Bases Siby (.si4)" "Siby databases (.si4)"]] {
    ttk::checkbutton $w.ext.$e -text $lib -variable ::moderne::systeme::choix($e) \
        -command ::moderne::systeme::majChoix
    pack $w.ext.$e -side top -anchor w
  }
  pack $w.ext -side top -fill x -before $w.b
  majChoix
}

### "Yes" only with at least one kind of file chosen
proc ::moderne::systeme::majChoix {} {
  variable choix
  catch {.fichiersSiby.b.ok state [expr {$choix(pgn) || $choix(si4) ? "!disabled" : "disabled"}]}
}

### The extensions chosen
proc ::moderne::systeme::extensions {} {
  variable choix
  set l {}
  foreach e {pgn si4} { if {![info exists choix($e)] || $choix($e)} { lappend l .$e } }
  return $l
}

proc ::moderne::systeme::faire {} {
  set exts [extensions]
  if {![llength $exts]} { return }
  if {[catch [list associer $exts] err]} {
    ::moderne::notice .fichiersSiby [T "Ouvrir avec Siby" "Open with Siby"] \
        "[T "Windows n'a pas accepté l'enregistrement" "Windows did not accept the registration"] : $err" {} {} {}
    return
  }
  catch ::options.write
  ::moderne::notice .fichiersSiby [T "Siby ouvre vos parties" "Siby opens your games"] \
      [T "Siby est maintenant proposé pour ouvrir les fichiers [join $exts { et }]. Si un autre programme les ouvre encore d'un double-clic, choisis Siby dans les paramètres de Windows (Applications par défaut)." \
         "Siby is now offered to open [join $exts { and }] files. If another program still opens them with a double click, choose Siby in Windows' settings (Default apps)."] \
      {} [T "Paramètres de Windows" "Windows settings"] ::moderne::systeme::parametres
}
