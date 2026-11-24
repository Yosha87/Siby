###
### Siby: updates of Siby itself (Yosha 2026-11-03)
###
### A small manifest is published at siby.tribychess.org (its own bucket):
###   siby_manifest.json
###     { "version": "1.0.1", "date": "2026-11-15",
###       "notes_fr": "…", "notes_en": "…",
###       "windows": {"fichier": "Siby-windows-x64.zip", "sha256": "…", "taille": 36000000},
###       "linux":   {"fichier": "Siby-linux-x64.tar.gz", "sha256": "…", "taille": 33000000} }
###   File names are relative to the manifest (or full URLs).
###
### Rules:
###   - checked in the background a little after start, then every 12 hours,
###     and from Help › Check for updates; without network: nothing shown;
###   - a newer version is offered at the bottom right (Update / Later);
###     "Later" does not offer the same version again for 3 days (the menu
###     always does);
###   - Update: the package is downloaded in the background, its SHA-256
###     checked, then unzipped into a waiting folder; it replaces Siby's
###     files when Siby quits (Windows does not let a running program be
###     replaced), then Siby starts again. "Restart now" quits at once.
###   - the user's files (settings, databases, Gaby, engines) live in
###     Documents\Siby, not in Siby's folder: they are not touched;
###   - a Siby folder that cannot be written (Program Files…): the package
###     is downloaded, and its folder opened for a manual install.
###

namespace eval ::moderne::majsiby {
  # saved settings
  variable auto
  variable url
  variable plusTard          ;# dict version -> time "Later" was chosen
  # state
  variable manifeste {}
  variable etat {}           ;# {} | telechargement | pret
  variable attente {}        ;# folder holding the unzipped new version
  variable delai [expr {12 * 3600 * 1000}]
}
set ::moderne::majsiby::urlDefaut https://siby.tribychess.org/siby_manifest.json
foreach {_v _d} {auto 1 url {} plusTard {}} {
  if {![info exists ::moderne::majsiby::$_v]} { set ::moderne::majsiby::$_v $_d }
}
unset _v _d

proc ::moderne::majsiby::T {fr en} { return [::moderne::tr $fr $en] }

### Version numbers compared: -1, 0, 1. "1.0 beta" is older than "1.0";
### "1.0.1" newer than "1.0"
proc ::moderne::majsiby::comparer {a b} {
  set na {} ; set nb {}
  regexp {^[0-9.]+} [string trim $a] na
  regexp {^[0-9.]+} [string trim $b] nb
  set la [split [string trim $na .] .]
  set lb [split [string trim $nb .] .]
  for {set i 0} {$i < max([llength $la], [llength $lb])} {incr i} {
    set x [lindex $la $i] ; set y [lindex $lb $i]
    if {![string is integer -strict $x]} { set x 0 }
    if {![string is integer -strict $y]} { set y 0 }
    if {$x != $y} { return [expr {$x < $y ? -1 : 1}] }
  }
  # same numbers: a tag (beta, rc…) is older than none
  set ta [string trim [string range [string trim $a] [string length $na] end]]
  set tb [string trim [string range [string trim $b] [string length $nb] end]]
  if {$ta eq $tb} { return 0 }
  if {$ta eq {}} { return 1 }
  if {$tb eq {}} { return -1 }
  # (numbers inside the tag compared as numbers: "beta 10" newer than
  # "beta 9", which a plain string comparison got wrong)
  if {[lindex [lsort -dictionary [list $ta $tb]] 0] eq $ta} { return -1 }
  return 1
}

proc ::moderne::majsiby::plateforme {} {
  return [expr {$::windowsOS ? "windows" : "linux"}]
}

### Siby's folder (the one with README.txt, bin, lib); SIBY_RACINE for tests
proc ::moderne::majsiby::racine {} {
  if {[info exists ::env(SIBY_RACINE)]} { return $::env(SIBY_RACINE) }
  set d [file dirname [file normalize [info nameofexecutable]]]
  if {[file tail $d] eq "bin"} { set d [file dirname $d] }
  return $d
}

proc ::moderne::majsiby::adresseManifeste {} {
  variable url
  variable urlDefaut
  set u [string trim $url]
  if {$u eq {}} { set u $urlDefaut }
  if {[string match -nocase *.json $u]} { return $u }
  return "[string trimright $u /]/siby_manifest.json"
}

proc ::moderne::majsiby::adresseFichier {nom} {
  if {[regexp {^[a-z]+://} $nom]} { return $nom }
  set m [adresseManifeste]
  if {[regexp {^[a-z]+://} $m]} { return "[string range $m 0 [string last / $m]]$nom" }
  return [file join [file dirname $m] $nom]
}

proc ::moderne::majsiby::dossierTemp {} {
  set d [file join $::scidUserDir siby-update]
  # (tests: a folder that outlives the test run)
  if {[info exists ::env(SIBY_MAJ_DOSSIER)]} { set d $::env(SIBY_MAJ_DOSSIER) }
  file mkdir $d
  return $d
}

### Background check (manuel: from the menu, the result is always said)
proc ::moderne::majsiby::demarrage {} {
  variable auto
  variable delai
  after cancel ::moderne::majsiby::demarrage
  after $delai ::moderne::majsiby::demarrage
  if {$auto ne "1" || [info exists ::env(SIBY_SANS_MAJ)]} { return }
  verifier 0
}

proc ::moderne::majsiby::verifier {manuel} {
  variable etat
  if {$etat ne {}} {
    if {$manuel} { annonceSimple [T "Mise à jour de Siby déjà en cours." "Siby update already in progress."] }
    return
  }
  set f [file join [dossierTemp] siby_manifest.json]
  catch {file delete $f}
  ::moderne::gaby::recuperer [adresseManifeste] $f [list ::moderne::majsiby::manifesteLu $manuel] 60
}

proc ::moderne::majsiby::manifesteLu {manuel fichier err} {
  variable manifeste
  variable plusTard
  if {$fichier eq {}} {
    if {$manuel} { annonceSimple [T "Siby : vérification impossible (pas de réseau ?)" "Siby: could not check (no network?)"] }
    return
  }
  if {[catch {
    set c [open $fichier r] ; fconfigure $c -encoding utf-8
    set manifeste [::moderne::json::parse [read $c]]
    close $c
  }] || ![dict exists $manifeste version]} {
    if {$manuel} { annonceSimple [T "Siby : fiche de mise à jour illisible." "Siby: unreadable update manifest."] }
    return
  }
  set v [dict get $manifeste version]
  if {[comparer $v $::sibyVersion] <= 0 || ![dict exists $manifeste [plateforme]]} {
    if {$manuel} { annonceSimple [T "Siby est à jour ($::sibyVersion)." "Siby is up to date ($::sibyVersion)."] }
    return
  }
  # "Later": not offered again for 3 days (the menu always offers it)
  if {!$manuel && [dict exists $plusTard $v] && [clock seconds] - [dict get $plusTard $v] < 3 * 86400} { return }
  proposer
}

### Notice at the bottom right: the new version, its notes, Update / Later
proc ::moderne::majsiby::proposer {} {
  variable manifeste
  set v [dict get $manifeste version]
  set notes [::moderne::json::get $manifeste [expr {$::language eq "F" ? "notes_fr" : "notes_en"}] {}]
  if {$notes eq {}} { set notes [::moderne::json::get $manifeste notes_en {}] }
  set w .sibyMaj
  catch {destroy $w}
  frame $w -background [::moderne::c surface2] -highlightthickness 1 \
      -highlightbackground [::moderne::c accent] -padx 14 -pady 10
  label $w.t -background [::moderne::c surface2] -foreground [::moderne::c texteFort] \
      -font font_Bold -justify left -wraplength 400 -text [T "Siby $v est disponible" "Siby $v is available"]
  label $w.d -background [::moderne::c surface2] -foreground [::moderne::c texteDoux] \
      -font font_Small -justify left -wraplength 400 -text [string range $notes 0 600]
  label $w.s -background [::moderne::c surface2] -foreground [::moderne::c texteDoux] \
      -font font_Small -justify left -wraplength 400 -text [T \
      "Téléchargée en arrière-plan, elle s'installe quand tu quittes Siby. Tes réglages et tes bases ne sont pas touchés." \
      "Downloaded in the background, it is installed when you quit Siby. Your settings and databases are not touched."]
  frame $w.b -background [::moderne::c surface2]
  ttk::button $w.b.ok -text [T "Mettre à jour" "Update"] -command {destroy .sibyMaj ; ::moderne::majsiby::telecharger}
  catch {$w.b.ok configure -style Accent.TButton}
  ttk::button $w.b.non -text [T "Plus tard" "Later"] -command [list ::moderne::majsiby::reporter $v]
  pack $w.b.non $w.b.ok -side right -padx {6 0}
  pack $w.t -side top -anchor w
  if {$notes ne {}} { pack $w.d -side top -anchor w -pady {4 0} }
  pack $w.s -side top -anchor w -pady {6 8}
  pack $w.b -side top -fill x
  place $w -in . -relx 1.0 -rely 1.0 -x -18 -y -18 -anchor se
  raise $w
}

proc ::moderne::majsiby::reporter {v} {
  variable plusTard
  dict set plusTard $v [clock seconds]
  catch {destroy .sibyMaj}
}

proc ::moderne::majsiby::annonceSimple {texte} {
  ::moderne::nsb::annonce $texte -1
  after 6000 {catch ::moderne::nsb::finAnnonce}
}

### Download, checksum, unzip into the waiting folder
proc ::moderne::majsiby::telecharger {} {
  variable manifeste
  variable etat
  set p [dict get $manifeste [plateforme]]
  set nom [::moderne::json::get $p fichier {}]
  if {$nom eq {}} { return }
  set etat telechargement
  set dest [file join [dossierTemp] [file tail $nom]]
  catch {file delete $dest}
  set v [dict get $manifeste version]
  ::moderne::nsb::annonce [T "Siby $v : téléchargement…" "Siby $v: downloading…"] 0
  ::moderne::gaby::recuperer [adresseFichier $nom] $dest [list ::moderne::majsiby::telecharge $dest] 3600
  after 500 [list ::moderne::majsiby::suivi $dest [::moderne::json::get $p taille 0]]
}

proc ::moderne::majsiby::suivi {dest taille} {
  variable etat
  if {$etat ne "telechargement"} { return }
  set n 0
  catch {set n [file size $dest]}
  if {$taille > 0} { ::moderne::nsb::annonce {} [expr {min(99, int(100.0 * $n / $taille))}] }
  after 500 [list ::moderne::majsiby::suivi $dest $taille]
}

proc ::moderne::majsiby::echec {texte} {
  variable etat
  set etat {}
  ::moderne::nsb::annonce $texte -1
  after 10000 {catch ::moderne::nsb::finAnnonce}
}

proc ::moderne::majsiby::telecharge {dest fichier err} {
  variable manifeste
  if {$fichier eq {}} { echec "[T "Siby : téléchargement impossible" "Siby: download failed"] ($err)" ; return }
  # (checked by Siby itself, and refused unless checked: with no SHA-256 in
  # the manifest, or the outside tool missing or blocked, the package was
  # installed unchecked; reported to Yosha on 2026-11-14)
  set attendu [string tolower [string trim [::moderne::json::get [dict get $manifeste [plateforme]] sha256 {}]]]
  ::moderne::nsb::annonce [T "Siby : vérification du fichier…" "Siby: checking the file…"] -1
  update idletasks
  set sha {}
  if {![regexp {^[0-9a-f]{64}$} $attendu] || [catch {sc_gaby sha256 $dest} sha] || ![string equal -nocase $sha $attendu]} {
    catch {file delete $dest}
    echec [T "Siby : fichier de mise à jour non vérifié (SHA-256), rien n'est changé." \
              "Siby: update file not verified (SHA-256), nothing is changed."]
    return
  }
  deballer $dest
}

proc ::moderne::majsiby::deballer {dest} {
  variable attente
  set attente [file join [dossierTemp] nouvelle]
  catch {file delete -force $attente}
  file mkdir $attente
  if {[string match -nocase *.zip $dest]} {
    set cmd [::moderne::gaby::commandeDezip $dest $attente]
  } else {
    set cmd [list tar -xzf $dest -C $attente]
  }
  if {$cmd eq {}} { echec [T "Siby : impossible de décompresser la mise à jour." "Siby: cannot unzip the update."] ; return }
  ::moderne::nsb::annonce [T "Siby : décompression…" "Siby: unzipping…"] -1
  if {[catch {open "|$cmd 2>@1" r} c]} { echec "[T "Siby : décompression impossible" "Siby: cannot unzip"] ($c)" ; return }
  fconfigure $c -blocking 0
  fileevent $c readable [list ::moderne::majsiby::deballe $c $dest]
}

proc ::moderne::majsiby::deballe {c dest} {
  variable attente
  variable etat
  variable manifeste
  read $c
  if {![eof $c]} { return }
  fconfigure $c -blocking 1
  set code [catch {close $c} err]
  set src [file join $attente Siby]
  if {![file isdirectory $src] || ![file exists [file join $src README.txt]]} {
    echec "[T "Siby : paquet de mise à jour incomplet" "Siby: incomplete update package"] $err"
    return
  }
  catch {file delete $dest}
  set v [dict get $manifeste version]
  catch {::moderne::nsb::finAnnonce}
  # a folder Siby cannot write into: the package is shown, to install by hand
  if {![file writable [racine]]} {
    set etat {}
    tk_messageBox -parent . -icon info -type ok -title Siby -message [T \
        "Siby $v est téléchargée, mais le dossier de Siby ([racine]) est protégé en écriture. Copie le contenu du dossier qui va s'ouvrir à la place de l'ancien." \
        "Siby $v is downloaded, but Siby's folder ([racine]) cannot be written to. Copy the content of the folder that opens over the old one."]
    catch {
      if {$::windowsOS} { exec explorer.exe [file nativename $src] & } else { exec xdg-open $src & }
    }
    return
  }
  set etat pret
  set w .sibyMaj
  catch {destroy $w}
  frame $w -background [::moderne::c surface2] -highlightthickness 1 \
      -highlightbackground [::moderne::c accent] -padx 14 -pady 10
  label $w.t -background [::moderne::c surface2] -foreground [::moderne::c texteFort] \
      -font font_Bold -justify left -wraplength 400 -text [T "Siby $v est prête" "Siby $v is ready"]
  label $w.s -background [::moderne::c surface2] -foreground [::moderne::c texteDoux] \
      -font font_Small -justify left -wraplength 400 -text [T \
      "Elle s'installera quand tu quitteras Siby, qui redémarrera tout seul." \
      "It is installed when you quit Siby, which then starts again by itself."]
  frame $w.b -background [::moderne::c surface2]
  ttk::button $w.b.ok -text [T "Redémarrer maintenant" "Restart now"] -command {destroy .sibyMaj ; ::file::Exit}
  catch {$w.b.ok configure -style Accent.TButton}
  ttk::button $w.b.non -text [T "En quittant" "When quitting"] -command [list destroy $w]
  pack $w.b.non $w.b.ok -side right -padx {6 0}
  pack $w.t $w.s -side top -anchor w -pady {0 6}
  pack $w.b -side top -fill x
  place $w -in . -relx 1.0 -rely 1.0 -x -18 -y -18 -anchor se
  raise $w
}

### Script that waits for Siby to end, copies the new files over the old
### ones, starts Siby again and cleans up; returns its path
proc ::moderne::majsiby::script {} {
  variable attente
  set src [file nativename [file join $attente Siby]]
  set dst [file nativename [racine]]
  set pid [pid]
  set d [dossierTemp]
  if {$::windowsOS} {
    set f [file join $d installer.bat]
    set exe [file nativename [file join [racine] Siby.exe]]
    set t "@echo off\r\n"
    append t ":attendre\r\n"
    append t "tasklist /FI \"PID eq $pid\" 2>nul | find \"$pid\" >nul && (timeout /t 1 /nobreak >nul & goto attendre)\r\n"
    append t "robocopy \"$src\" \"$dst\" /E /R:10 /W:1 /NFL /NDL /NJH /NJS /NP >nul\r\n"
    append t "if %ERRORLEVEL% GEQ 8 goto fin\r\n"
    append t "rmdir /S /Q \"[file nativename $attente]\"\r\n"
    append t ":fin\r\n"
    append t "start \"\" \"$exe\"\r\n"
    # (a .bat run by "start" stays open as a command prompt at its end:
    # closed here, seen by Yosha after 1.0 beta 2, 2026-11-13)
    append t "exit\r\n"
  } else {
    set f [file join $d installer.sh]
    set exe [file join [racine] siby]
    set t "#!/bin/sh\n"
    append t "while kill -0 $pid 2>/dev/null; do sleep 1; done\n"
    # (-f: a read-only file, such as the libtcl8.6.so of the package of
    # 2026-11-14, replaced too; with -a alone the copy stopped there)
    append t "cp -af \"$src/.\" \"$dst/\" && rm -rf \"$attente\"\n"
    append t "nohup \"$exe\" >/dev/null 2>&1 &\n"
  }
  set c [open $f w]
  fconfigure $c -translation binary
  puts -nonewline $c $t
  close $c
  catch {file attributes $f -permissions 0755}
  return $f
}

### When Siby quits with a new version waiting: the script is started,
### detached (it waits for this process to end)
proc ::moderne::majsiby::auQuitter {} {
  variable etat
  if {$etat ne "pret" || [info exists ::env(SIBY_MAJ_SANS_LANCER)]} { return }
  set f [script]
  if {$::windowsOS} {
    catch {exec {*}[auto_execok cmd] /c start "" /min [file nativename $f] &}
  } else {
    catch {exec /bin/sh $f >/dev/null 2>@1 &}
  }
}

################################################################################
### Toby's updates (Yosha 2026-11-17, before Toby 2)
###
### - Toby's manifest (toby.tribychess.org/toby_manifest.json, see
###   ajoutmoteur.tcl) is read a little after start, then every 12 hours,
###   and from Help › Check for updates, when a Toby downloaded by Siby is
###   registered (its program in a folder named Toby).
### - The installed version: Toby/siby_toby.txt (written by Siby: "version
###   variant"), else Toby/VERSION (Toby's own), else 1.0 (the only version
###   published before).
### - A newer one: offered at the bottom right (Update / Later, Later: not
###   again for 3 days). Update: the same variant (full, light, core) is
###   downloaded and checked (SHA-256) by Tools › Add an engine, unpacked
###   beside the old Toby (Toby.maj), and put in its place at Siby's next
###   start, before any Toby runs (a running Toby cannot be replaced on
###   Windows). Its path stays the same: nothing to set up again.
################################################################################

namespace eval ::moderne::majtoby {
  variable plusTard          ;# dict version -> time "Later" was chosen
  variable manifeste {}
  variable installe {}       ;# version just put in place at this start
}
if {![info exists ::moderne::majtoby::plusTard]} { set ::moderne::majtoby::plusTard {} }

proc ::moderne::majtoby::T {fr en} { return [::moderne::tr $fr $en] }

### The file naming the Toby waiting to be put in place: {new dest maj version}
proc ::moderne::majtoby::fichierAttente {} { return [file join $::scidUserDir toby_maj.txt] }

### Siby's start: the Toby waiting put in place of the old one
proc ::moderne::majtoby::appliquer {{essais 16}} {
  variable installe
  set f [fichierAttente]
  if {![file exists $f]} { return }
  if {[catch {set c [open $f r] ; set l [read $c] ; close $c}] || [llength $l] < 4} {
    catch {file delete $f}
    return
  }
  lassign $l nouveau dest maj version
  if {![file isdirectory $nouveau]} {
    catch {file delete $f}
    catch {::moderne::journal "Toby update: $nouveau missing, cancelled"}
    return
  }
  set ancien $dest.ancien
  catch {file delete -force $ancien}
  # (a Toby of the previous run may take a few seconds to end: tried for
  # 8 s, then at the next start)
  set err {}
  for {set i 0} {[file exists $dest] && $i < $essais} {incr i} {
    if {![catch {file rename $dest $ancien} err]} { set err {} ; break }
    after 500
  }
  if {[file exists $dest]} {
    catch {::moderne::journal "Toby update waiting: $err"}
    return 0
  }
  if {[catch {file rename $nouveau $dest} err]} {
    catch {file rename $ancien $dest}
    catch {::moderne::journal "Toby update failed: $err"}
    return 0
  }
  # (the old Toby, about 1 GB, deleted in the background: done here, Siby
  # froze 17 s, Windows VM 2026-11-18)
  supprimerPlusTard $ancien
  supprimerPlusTard $maj
  catch {file delete $f}
  set installe $version
  catch {::moderne::journal "Toby updated to $version"}
  return 1
}

### Is a Toby process running now (analysis, preload, level, review, game)?
proc ::moderne::majtoby::actif {} {
  if {[winfo exists .serGameWin]} { return 1 }
  if {[array size ::moderne::niveau::pipes]} { return 1 }
  if {[info exists ::moderne::oracle::pipe] && $::moderne::oracle::pipe ne {}} { return 1 }
  foreach t [::moderne::toby::moteursToby] {
    set n [lindex $t 0]
    if {[info exists ::moderne::docks::prelance($n)]} { return 1 }
    if {[info exists ::analysis(pipe$n)] && $::analysis(pipe$n) ne {}} { return 1 }
  }
  return 0
}

### Folder d deleted by a process of its own, Siby not waiting
proc ::moderne::majtoby::supprimerPlusTard {d} {
  if {![file exists $d]} { return }
  if {$::windowsOS} {
    if {[catch {exec {*}[auto_execok cmd] /c rmdir /s /q [file nativename $d] &}]} { catch {file delete -force $d} }
  } else {
    if {[catch {exec rm -rf $d &}]} { catch {file delete -force $d} }
  }
}

### Siby's start: an old Toby left by an update (Toby.ancien) deleted
proc ::moderne::majtoby::nettoyer {} {
  catch {
    set d [::moderne::ajout::dossier]
    foreach x [list [file join $d Toby.ancien]] { supprimerPlusTard $x }
  }
}

### The Toby downloaded by Siby: {exe folder}, or {}
proc ::moderne::majtoby::tobySiby {} {
  foreach t [::moderne::toby::moteursToby] {
    set exe [lindex [lindex $::engines(list) [lindex $t 0]] 1]
    catch {set exe [toAbsPath $exe]}
    set d [file dirname $exe]
    if {[file tail $d] eq "Toby" && [file exists $exe] && [file writable [file dirname $d]]} {
      return [list $exe $d]
    }
  }
  return {}
}

### Version and variant of the Toby in folder d
proc ::moderne::majtoby::versionDe {d} {
  set v {} ; set var {}
  catch {set c [open [file join $d siby_toby.txt] r] ; lassign [read $c] v var ; close $c}
  if {$v eq {}} { catch {set c [open [file join $d VERSION] r] ; set v [string trim [read $c]] ; close $c} }
  if {$v eq {}} { set v 1.0 }
  if {$var eq {}} {
    set var [expr {[file isdirectory [file join $d lc0]] ? "full" : "light"}]
  }
  return [list $v $var]
}

proc ::moderne::majtoby::demarrage {} {
  after cancel ::moderne::majtoby::demarrage
  after [expr {12 * 3600 * 1000}] ::moderne::majtoby::demarrage
  if {$::moderne::majsiby::auto ne "1" || [info exists ::env(SIBY_SANS_MAJ)]} { return }
  verifier 0
}

proc ::moderne::majtoby::verifier {manuel} {
  if {[tobySiby] eq {}} { return }
  set adresse $::moderne::ajout::manifesteToby
  if {[info exists ::env(SIBY_TOBY_MANIFESTE)]} { set adresse $::env(SIBY_TOBY_MANIFESTE) }
  if {$adresse eq {}} { return }
  set f [file join [::moderne::majsiby::dossierTemp] toby_manifest.json]
  catch {file delete $f}
  ::moderne::gaby::recuperer $adresse $f [list ::moderne::majtoby::manifesteLu $manuel] 60
}

proc ::moderne::majtoby::manifesteLu {manuel fichier err} {
  variable manifeste
  variable plusTard
  if {$fichier eq {}} { return }
  if {[catch {
    set c [open $fichier r] ; fconfigure $c -encoding utf-8
    set manifeste [::moderne::json::parse [read $c]]
    close $c
  }] || ![dict exists $manifeste version]} { return }
  set t [tobySiby]
  if {$t eq {}} { return }
  lassign [versionDe [lindex $t 1]] vi
  set v [dict get $manifeste version]
  # (already downloaded, waiting for the next start)
  if {[file exists [fichierAttente]]} {
    # (the version waiting, not the manifest's)
    set va $v
    catch {set c [open [fichierAttente] r] ; set va [lindex [read $c] 3] ; close $c}
    if {$manuel} { pret $va }
    return
  }
  if {[::moderne::majsiby::comparer $v $vi] <= 0} {
    if {$manuel} { ::moderne::majsiby::annonceSimple [T "Toby est à jour ($vi)." "Toby is up to date ($vi)."] }
    return
  }
  if {!$manuel && [dict exists $plusTard $v] && [clock seconds] - [dict get $plusTard $v] < 3 * 86400} { return }
  proposer
}

### A notice at the bottom right, above Siby's own if it is there
proc ::moderne::majtoby::cadre {} {
  set w .tobyMaj
  catch {destroy $w}
  frame $w -background [::moderne::c surface2] -highlightthickness 1 \
      -highlightbackground [::moderne::c accent] -padx 14 -pady 10
  return $w
}
proc ::moderne::majtoby::placer {w} {
  set y -18
  if {[winfo exists .sibyMaj] && [winfo ismapped .sibyMaj]} {
    update idletasks
    set y [expr {-18 - [winfo height .sibyMaj] - 12}]
  }
  place $w -in . -relx 1.0 -rely 1.0 -x -18 -y $y -anchor se
  raise $w
}

proc ::moderne::majtoby::proposer {} {
  variable manifeste
  set v [dict get $manifeste version]
  set notes [::moderne::json::get $manifeste [expr {$::language eq "F" ? "notes_fr" : "notes_en"}] {}]
  if {$notes eq {}} { set notes [::moderne::json::get $manifeste notes_en {}] }
  set w [cadre]
  label $w.t -background [::moderne::c surface2] -foreground [::moderne::c texteFort] \
      -font font_Bold -justify left -wraplength 400 -text [T "Toby $v est disponible" "Toby $v is available"]
  label $w.d -background [::moderne::c surface2] -foreground [::moderne::c texteDoux] \
      -font font_Small -justify left -wraplength 400 -text [string range $notes 0 600]
  frame $w.b -background [::moderne::c surface2]
  ttk::button $w.b.ok -text [T "Mettre à jour" "Update"] -command {destroy .tobyMaj ; ::moderne::majtoby::telecharger}
  catch {$w.b.ok configure -style Accent.TButton}
  ttk::button $w.b.non -text [T "Plus tard" "Later"] -command [list ::moderne::majtoby::reporter $v]
  pack $w.b.non $w.b.ok -side right -padx {6 0}
  pack $w.t -side top -anchor w
  if {$notes ne {}} { pack $w.d -side top -anchor w -pady {4 0} }
  pack $w.b -side top -fill x -pady {8 0}
  placer $w
}

proc ::moderne::majtoby::reporter {v} {
  variable plusTard
  dict set plusTard $v [clock seconds]
  catch {destroy .tobyMaj}
}

### Update: Tools › Add an engine downloads the same variant into the
### installed Toby's place (see ::moderne::ajout::tobyComposants)
proc ::moderne::majtoby::telecharger {} {
  set t [tobySiby]
  if {$t eq {}} { return }
  lassign [versionDe [lindex $t 1]] - var
  catch ::moderne::ajout::ouvrir
  ::moderne::ajout::telecharger toby $var [lindex $t 1]
}

### The new Toby unpacked: put in place at the next start
proc ::moderne::majtoby::pret {v} {
  set w [cadre]
  label $w.t -background [::moderne::c surface2] -foreground [::moderne::c texteFort] \
      -font font_Bold -justify left -wraplength 400 -text [T "Toby $v est prêt" "Toby $v is ready"]
  frame $w.b -background [::moderne::c surface2]
  ttk::button $w.b.ok -text [T "Redémarrer Siby" "Restart Siby"] -command {destroy .tobyMaj ; ::moderne::redemarrer}
  catch {$w.b.ok configure -style Accent.TButton}
  ttk::button $w.b.non -text [T "Plus tard" "Later"] -command {destroy .tobyMaj}
  pack $w.b.non $w.b.ok -side right -padx {6 0}
  pack $w.t -side top -anchor w
  pack $w.b -side top -fill x -pady {8 0}
  placer $w
}

### After the start: the Toby just put in place said
proc ::moderne::majtoby::annoncerInstalle {} {
  variable installe
  if {$installe eq {}} { return }
  ::moderne::majsiby::annonceSimple [T "✓ Toby $installe installé" "✓ Toby $installe installed"]
  set installe {}
}

# (the Toby waiting put in place now: Siby's start, before any engine runs)
after 30000 {catch ::moderne::majtoby::nettoyer}
# (two tries: a folder kept locked (antivirus, an Explorer window) froze
# every start 8 s; tried again at the next start)
catch {::moderne::majtoby::appliquer 2}
