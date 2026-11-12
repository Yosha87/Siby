###
### Siby: Tools › Add an engine. One card per engine (Toby, Stockfish,
### Leela; no Maia alone: Toby has its own): "Download" fetches it into Siby's engines folder and sets
### it up; "Choose a file" adds one already on the computer.
###
### Sources:
### - Stockfish: the official "universal" build of the latest release
###   (GitHub, stable address), Windows and Linux;
### - Leela (lc0): the latest release on GitHub (Windows only: lc0 publishes
###   no Linux build), CUDA build with an NVIDIA card, else the CPU one, and
###   the network Toby uses (BT3, storage.lczero.org);
### - Toby: a manifest (Toby's session, docs/INTERFACES.md) listing per
###   platform the components core, maia, leela-cuda, stockfish with their
###   address, size and sha256; with an NVIDIA card all four, else core +
###   maia + stockfish (Toby's calculator, Auto, then uses Stockfish). Empty address
###   until Toby is published: the card then offers the local file only.
###

namespace eval ::moderne::ajout {
  variable w .ajoutMoteur
  variable manifesteToby https://toby.tribychess.org/toby_manifest.json
  # download addresses (tests: replaced by a local server)
  variable urls {
    stockfish https://github.com/official-stockfish/Stockfish/releases/latest/download
    lc0 https://api.github.com/repos/LeelaChessZero/lc0/releases/latest
    reseau https://storage.lczero.org/files/networks-contrib/BT3-768x15x24h-swa-2790000.pb.gz
  }
  variable etat           ;# etat(cle) = text under the card
  array set etat {}
  variable enCours        ;# enCours(cle): download or unpacking under way
  array set enCours {}
}

proc ::moderne::ajout::T {fr en} { return [::moderne::tr $fr $en] }

### Platform: windows-x64 or linux-x64
proc ::moderne::ajout::plateforme {} {
  if {$::windowsOS} { return windows-x64 }
  return linux-x64
}

### NVIDIA graphics card: nvidia-smi answers
proc ::moderne::ajout::nvidia {} {
  variable nvidia
  if {[info exists nvidia]} { return $nvidia }
  set nvidia 0
  set exe [auto_execok nvidia-smi]
  if {$exe eq {} && $::windowsOS} {
    foreach d [list "$::env(SystemRoot)/System32" "C:/Program Files/NVIDIA Corporation/NVSMI"] {
      if {[file exists $d/nvidia-smi.exe]} { set exe [list $d/nvidia-smi.exe] ; break }
    }
  }
  if {$exe ne {} && ![catch {exec {*}$exe -L} sortie] && [string match "*GPU*" $sortie]} { set nvidia 1 }
  return $nvidia
}

### Siby's engines folder (created if needed), kept when Siby is updated
### or unzipped elsewhere (Yosha, 2026-11-04: each new version had to
### download Toby again): on Windows %LOCALAPPDATA%\Siby\engines (not in
### Documents: OneDrive would sync gigabytes), on Linux
### ~/.local/share/Siby/engines; else the user folder. A folder chosen in
### the Engines window comes first (engines already there stay where they
### are: moved by hand if wanted)
namespace eval ::moderne::ajout { variable dossierChoisi ; if {![info exists dossierChoisi]} { set dossierChoisi {} } }

proc ::moderne::ajout::dossier {} {
  variable dossierChoisi
  set candidats [list $dossierChoisi [dossierDurable] [file join $::scidUserDir engines]]
  foreach d $candidats {
    if {$d eq {} || [catch {file mkdir $d}]} { continue }
    if {[file writable $d]} { return [file normalize $d] }
  }
  return [file normalize [file join $::scidUserDir engines]]
}

### Choosing the downloads folder
proc ::moderne::ajout::choisirDossier {} {
  variable w
  variable dossierChoisi
  set d [tk_chooseDirectory -parent $w -initialdir [dossier] -mustexist 0 \
      -title [T "Dossier des moteurs téléchargés" "Folder of downloaded engines"]]
  if {$d eq {}} { return }
  set dossierChoisi [file normalize $d]
  catch {::options.write}
  catch {majDossier $w.f.bas.dossier}
}

proc ::moderne::ajout::majDossier {b} {
  $b configure -text "📁 [file nativename [dossier]]"
  catch {::utils::tooltip::Set $b [T "Dossier des moteurs téléchargés" "Folder of downloaded engines"]}
}

proc ::moderne::ajout::dossierDurable {} {
  if {$::windowsOS} {
    if {[info exists ::env(LOCALAPPDATA)] && $::env(LOCALAPPDATA) ne {}} {
      return [file normalize [file join $::env(LOCALAPPDATA) Siby engines]]
    }
    return {}
  }
  if {[info exists ::env(XDG_DATA_HOME)] && $::env(XDG_DATA_HOME) ne {}} {
    return [file normalize [file join $::env(XDG_DATA_HOME) Siby engines]]
  }
  return [file normalize [file join ~ .local share Siby engines]]
}

################################################################################
### Engines already configured
################################################################################

### Index in engines(list) of the first engine whose name matches, or -1
proc ::moderne::ajout::indexMoteur {motif} {
  set i 0
  foreach e $::engines(list) {
    if {[string match -nocase $motif [lindex $e 0]]} { return $i }
    incr i
  }
  return -1
}

### Installed: an engine of the list with that name whose program is still
### there (its files deleted: the card offers the download again, which
### replaces the entry; Yosha 2026-11-04)
proc ::moderne::ajout::installe {cle} {
  set motifs [dict get {toby {*toby*} stockfish {*stockfish*} leela {*leela* *lc0*}} $cle]
  foreach e $::engines(list) {
    foreach m $motifs {
      if {[string match -nocase $m [lindex $e 0]] && [programmeLa [lindex $e 1]]} { return 1 }
    }
  }
  return 0
}

### Is an engine's program there (a file, or a command found on the PATH)?
proc ::moderne::ajout::programmeLa {cmd} {
  if {$cmd eq {}} { return 0 }
  if {[file exists $cmd]} { return 1 }
  return [expr {[file pathtype $cmd] eq "relative" && [auto_execok $cmd] ne {}}]
}

### The configured engine of a card (engines(list) entry), {} if none
proc ::moderne::ajout::moteurDe {cle} {
  set motifs [dict get {toby {*toby*} stockfish {*stockfish*} leela {*leela* *lc0*}} $cle]
  # (one whose program is there first: an old entry whose files were
  # deleted must not hide the one just downloaded)
  set absent {}
  foreach e $::engines(list) {
    foreach m $motifs {
      if {![string match -nocase $m [lindex $e 0]]} { continue }
      if {[programmeLa [lindex $e 1]]} { return $e }
      if {$absent eq {}} { set absent $e }
    }
  }
  return $absent
}

### Version of an installed engine: its "id name", asked once in the
### background ("uci"); {} until it answered
namespace eval ::moderne::ajout { variable versions ; array set versions {} ; variable renommer ; array set renommer {} }
proc ::moderne::ajout::version {cle} {
  return [versionMoteur [moteurDe $cle]]
}

proc ::moderne::ajout::versionMoteur {e} {
  variable versions
  set cmd [lindex $e 1]
  if {$cmd eq {}} { return {} }
  if {[info exists versions($cmd)]} { return [expr {$versions($cmd) eq "attente" ? {} : $versions($cmd)}] }
  set versions($cmd) attente
  set dossier [lindex $e 3]
  set ici [pwd]
  if {[catch {
    if {$dossier ne {} && [file isdirectory $dossier]} { cd $dossier }
    set f [open |[concat [list $cmd] [lindex $e 2]] r+]
  }]} {
    catch {cd $ici}
    set versions($cmd) {}
    return {}
  }
  catch {cd $ici}
  fconfigure $f -blocking 0 -buffering line
  fileevent $f readable [list ::moderne::ajout::versionLue $f $cmd]
  catch {puts $f uci ; flush $f}
  after 6000 [list ::moderne::ajout::versionFin $f $cmd]
  return {}
}

proc ::moderne::ajout::versionLue {f cmd} {
  variable versions
  if {[catch {gets $f l} n] || $n < 0} {
    if {[eof $f]} { versionFin $f $cmd }
    return
  }
  if {[regexp {^id name (.+)$} [string trim $l] -> nom]} { set versions($cmd) [string trim $nom] }
  if {[string trim $l] eq "uciok"} { versionFin $f $cmd }
}

proc ::moderne::ajout::versionFin {f cmd} {
  variable versions
  if {[lsearch [chan names] $f] < 0} { return }
  catch {fileevent $f readable {}}
  catch {puts $f quit ; flush $f}
  catch {fconfigure $f -blocking 0 ; close $f}
  if {$versions($cmd) eq "attente"} { set versions($cmd) {} }
  # "Other engine": named after its "id name" once known
  variable renommer
  if {[info exists renommer($cmd)]} {
    set ancien $renommer($cmd)
    unset renommer($cmd)
    set i [lsearch -exact -index 0 $::engines(list) $ancien]
    if {$i >= 0 && $versions($cmd) ne {} && [lsearch -exact -index 0 $::engines(list) $versions($cmd)] < 0} {
      lset ::engines(list) $i 0 $versions($cmd)
      catch {::enginelist::write}
      etat autre "✓ [T "Ajouté :" "Added:"] $versions($cmd)"
    } elseif {$i >= 0 && $versions($cmd) eq {}} {
      etat autre [T "Ajouté, mais il ne répond pas comme un moteur UCI : vérifie le programme." \
                    "Added, but it does not answer as a UCI engine: check the program."]
    }
  }
  after idle ::moderne::ajout::majCartes
  after idle ::moderne::ajout::listeMoteurs
}

### lc0 program already configured, {} otherwise
proc ::moderne::ajout::lc0 {} {
  foreach e $::engines(list) {
    set cmd [lindex $e 1]
    if {[string match -nocase *lc0* [file tail $cmd]] && [file exists $cmd]} { return $cmd }
  }
  catch {return [::moderne::moteurs::trouver {lc0}]}
  return {}
}

### Adds (or replaces, same name) an engine; options: list of {name value}
proc ::moderne::ajout::enregistrer {nom cmd options} {
  global engines
  set e [list $nom [file normalize $cmd] {} $::scidUserDir 0 0 {} 1 $options]
  set i [lsearch -exact -index 0 $engines(list) $nom]
  if {$i >= 0} {
    set engines(list) [lreplace $engines(list) $i $i $e]
  } else {
    lappend engines(list) $e
  }
  catch {::enginelist::write}
  catch {::moderne::moteurs::touches}
}

################################################################################
### Window
################################################################################

proc ::moderne::ajout::cartes {} {
  return [list \
    toby "Toby" \
      "Prédit et joue comme une personne réelle du niveau choisi (Maia et Leela ou Stockfish)." \
      "Predicts and plays like a real person of the chosen level (Maia, and Leela or Stockfish)." \
    stockfish "Stockfish" \
      "La référence des moteurs libres : parmi les plus forts au monde, utilisé par les grands maîtres et les grandes plateformes." \
      "The reference among free engines: one of the strongest in the world, trusted by grandmasters and leading platforms." \
    leela "Leela (lc0)" \
      "Moteur libre à réseau neuronal qui a appris les échecs en jouant contre lui-même : un style unique, fort en stratégie ; rapide avec une carte NVIDIA." \
      "Free neural-network engine that learned chess by playing itself: a unique style, strong in strategy; fast with an NVIDIA card." \
    autre [T "Autre moteur" "Other engine"] \
      "N'importe quel moteur UCI : choisis son programme, Siby lit son nom et le règle." \
      "Any UCI engine: choose its program, Siby reads its name and sets it up."]
}

### The Engines window: my engines (order = F2 to F9, version, analyse,
### options, edit, delete), then the cards to add one (download or file),
### "Other engine" for any UCI engine. SCID's old window stays behind
### "Advanced settings".
proc ::moderne::ajout::ouvrir {} {
  variable w
  if {[winfo exists $w]} { raise $w ; focus $w ; listeMoteurs ; return }
  toplevel $w
  wm withdraw $w
  wm title $w [T "Moteurs" "Engines"]
  set f [ttk::frame $w.f -padding 16]
  pack $f -fill both -expand 1
  # my engines
  ttk::label $f.titreMes -text [T "Mes moteurs" "My engines"] -font font_Bold
  ttk::label $f.sousMes -foreground [::moderne::c texteDoux] -text [T \
      "L'ordre donne les touches : le premier se lance avec F2, le deuxième avec F3… jusqu'à F9." \
      "The order gives the keys: the first starts with F2, the second with F3… up to F9."]
  ttk::frame $f.mes
  grid $f.titreMes - - -sticky w
  grid $f.sousMes - - -sticky w -pady {0 6}
  grid $f.mes - - -sticky we -pady {0 14}
  # add one
  ttk::label $f.titre -text [T "Ajouter un moteur" "Add an engine"] -font font_Bold
  ttk::label $f.sous -foreground [::moderne::c texteDoux] -text [T \
      "Téléchargé dans le dossier des moteurs de Siby, puis réglé tout seul." \
      "Downloaded into Siby's engines folder, then set up automatically."]
  grid $f.titre - - -sticky w
  grid $f.sous - - -sticky w -pady {0 8}
  # the cards, two per row
  ttk::frame $f.cartes
  grid $f.cartes - - -sticky nsew
  set k 0
  foreach {cle nom fr en} [cartes] {
    set c [carte $f.c$cle $cle $nom [T $fr $en]]
    grid $c -in $f.cartes -row [expr {$k / 2}] -column [expr {$k % 2}] -sticky nsew -padx 5 -pady 5
    incr k
  }
  grid columnconfigure $f.cartes {0 1} -weight 1 -uniform cartes
  grid columnconfigure $f {0 1 2} -weight 1
  ttk::frame $f.bas
  # (no "Advanced settings": everything is in the engine rows and the ⋯
  # menu of each panel; Yosha 2026-11-01)
  ttk::button $f.bas.fermer -text [T "Fermer" "Close"] -command [list destroy $w]
  pack $f.bas.fermer -side right
  # the folder where downloads go
  ttk::button $f.bas.dossier -style Toolbutton -command ::moderne::ajout::choisirDossier
  pack $f.bas.dossier -side left
  majDossier $f.bas.dossier
  grid $f.bas - - -sticky we -pady {14 0}
  bind $w <Escape> [list destroy $w]
  foreach k {F2 F3 F4 F5 F6 F7 F8 F9} { bind $w <$k> [list startAnalysisWin $k] }
  listeMoteurs
  majCartes
  catch {::moderne::repeindre $w}
  update idletasks
  set x [expr {[winfo rootx .] + ([winfo width .] - [winfo reqwidth $w]) / 2}]
  set y [expr {[winfo rooty .] + max(0, ([winfo height .] - [winfo reqheight $w]) / 2)}]
  wm geometry $w +[expr {max(0, $x)}]+[expr {max(0, $y)}]
  wm deiconify $w
}

### The rows of "My engines"
proc ::moderne::ajout::listeMoteurs {} {
  variable w
  set m $w.f.mes
  if {![winfo exists $m]} { return }
  foreach c [winfo children $m] { destroy $c }
  catch {::moderne::moteurs::touches}
  set n [llength $::engines(list)]
  if {!$n} {
    grid [ttk::label $m.vide -foreground [::moderne::c texteDoux] -text [T \
        "Aucun moteur : ajoute-en un ci-dessous." "No engine: add one below."]] -sticky w
    return
  }
  set doux [::moderne::c texteDoux]
  for {set i 0} {$i < $n} {incr i} {
    set e [lindex $::engines(list) $i]
    set r $m.r$i
    ttk::label $r-k -text [expr {$i < 8 ? "F[expr {$i + 2}]" : ""}] -font font_Bold -foreground [::moderne::c accent] -width 4
    ttk::label $r-n -text [lindex $e 0] -font font_Bold
    set v [versionMoteur $e]
    ttk::label $r-v -text [expr {$v ne {} && $v ne [lindex $e 0] ? $v : ""}] -foreground $doux
    catch {::utils::tooltip::Set $r-n "[T "Programme :" "Program:"] [lindex $e 1]"}
    ttk::frame $r-b
    ttk::button $r-b.go -text "▶" -width 3 -command [list ::moderne::ajout::analyser $i]
    ttk::button $r-b.haut -text "↑" -width 3 -command [list ::moderne::ajout::deplacer $i -1]
    ttk::button $r-b.bas -text "↓" -width 3 -command [list ::moderne::ajout::deplacer $i 1]
    ttk::button $r-b.opt -text [T "Options" "Options"] -command [list ::uci::uciConfigN $i $w]
    ttk::button $r-b.mod -text [T "Modifier" "Edit"] -command [list ::enginelist::edit $i]
    ttk::button $r-b.sup -text "✕" -width 3 -command [list ::moderne::ajout::supprimer $i]
    if {$i == 0} { $r-b.haut state disabled }
    if {$i == $n - 1} { $r-b.bas state disabled }
    if {![lindex $e 7]} { $r-b.opt state disabled }
    pack $r-b.go $r-b.haut $r-b.bas $r-b.opt $r-b.mod $r-b.sup -side left -padx 1
    foreach {x t} [list $r-b.go [T "Analyser avec ce moteur" "Analyse with this engine"] \
        $r-b.haut [T "Monter (touche plus petite)" "Move up (smaller key)"] $r-b.bas [T "Descendre" "Move down"] \
        $r-b.opt [T "Options UCI du moteur (Threads, Hash…)" "The engine's UCI options (Threads, Hash…)"] \
        $r-b.mod [T "Nom, programme, dossier" "Name, program, folder"] $r-b.sup [T "Retirer de la liste" "Remove from the list"]] {
      catch {::utils::tooltip::Set $x $t}
    }
    grid $r-k $r-n $r-v $r-b -sticky w -pady 2
    grid configure $r-v -padx {10 20}
  }
}

proc ::moderne::ajout::analyser {i} {
  if {$i < 8} { startAnalysisWin F[expr {$i + 2}] } else { makeAnalysisWin $i }
}

proc ::moderne::ajout::deplacer {i sens} {
  set j [expr {$i + $sens}]
  if {$j < 0 || $j >= [llength $::engines(list)]} { return }
  catch {::moderne::moteurs::deplacer $i $j}
  listeMoteurs
  majCartes
}

proc ::moderne::ajout::supprimer {i} {
  variable w
  set e [lindex $::engines(list) $i]
  if {[winfo exists .analysisWin$i]} {
    tk_messageBox -parent $w -icon info -type ok -title Siby -message [T \
        "Ce moteur est ouvert : ferme d'abord son panneau." "This engine is open: close its panel first."]
    return
  }
  set r [tk_messageBox -parent $w -icon question -type okcancel -title Siby -message [T \
      "Retirer « [lindex $e 0] » de la liste des moteurs ?" "Remove \"[lindex $e 0]\" from the engine list?"] \
      -detail [T "Le programme reste sur l'ordinateur." "The program stays on the computer."]]
  if {$r ne "ok"} { return }
  set ::engines(list) [lreplace $::engines(list) $i $i]
  catch {::enginelist::write}
  listeMoteurs
  majCartes
}

proc ::moderne::ajout::carte {c cle nom texte} {
  ttk::frame $c -padding 12 -relief solid -borderwidth 1
  # the engine's logo on the left
  set img {}
  catch {set img [::moderne::logosmoteurs::image $cle]}
  ttk::label $c.logo -image $img
  pack $c.logo -side left -anchor n -padx {0 12}
  ttk::label $c.nom -text $nom -font font_Bold
  ttk::label $c.texte -text $texte -wraplength 300 -justify left
  ttk::label $c.etat -text {} -foreground [::moderne::c texteDoux] -wraplength 300 -justify left
  ttk::progressbar $c.barre -mode determinate -maximum 100 -length 260
  ttk::frame $c.b
  ttk::button $c.b.telecharger -text [T "Télécharger" "Download"] -command [list ::moderne::ajout::telecharger $cle]
  catch {$c.b.telecharger configure -style Accent.TButton}
  ttk::button $c.b.local -text [T "Choisir un fichier…" "Choose a file…"] -command [list ::moderne::ajout::local $cle]
  if {$cle eq "autre"} {
    pack $c.b.local -side left
  } else {
    pack $c.b.telecharger $c.b.local -side left -padx {0 6}
  }
  # Toby with an NVIDIA card: the smaller package too (Maia on the CPU,
  # no Leela), for a slow connection (Toby 2026-11-03)
  if {$cle eq "toby"} {
    ttk::button $c.b.leger -text [T "Version légère" "Light version"] -command {::moderne::ajout::telecharger toby light}
    catch {::utils::tooltip::Set $c.b.leger [T "0,7 Go au lieu de 3,9 Go : Maia sur le processeur, sans Leela" \
        "0.7 GB instead of 3.9 GB: Maia on the processor, without Leela"]}
    if {[nvidia]} { pack $c.b.leger -side left -padx {0 6} -before $c.b.local }
  }
  # (each engine's own licence, beside its name (a card of its own: a
  # separate program): SignPath's condition for signing Siby, which downloads them,
  # 2026-11-11)
  set licences {toby "AGPL v3" stockfish "GPL v3" leela "GPL v3"}
  if {[dict exists $licences $cle]} {
    ttk::frame $c.t
    pack forget $c.nom
    ttk::label $c.licence -text [dict get $licences $cle] -foreground [::moderne::c texteDoux]
    pack $c.t -side top -anchor w -fill x
    raise $c.nom $c.t
    pack $c.nom -in $c.t -side left
    pack $c.licence -in $c.t -side left -padx {8 0}
  } else {
    pack $c.nom -side top -anchor w
  }
  pack $c.texte -side top -anchor w -pady {2 6}
  pack $c.etat -side top -anchor w
  pack $c.b -side top -anchor w -pady {8 0}
  return $c
}

### State of every card: installed or not, available or not here
proc ::moderne::ajout::majCartes {} {
  variable w
  variable etat
  variable enCours
  variable manifesteToby
  if {![winfo exists $w]} { return }
  foreach {cle nom fr en} [cartes] {
    set c $w.f.c$cle
    if {[info exists enCours($cle)]} {
      $c.b.telecharger state disabled
      $c.b.local state disabled
      if {![winfo ismapped $c.barre]} { pack $c.barre -side top -anchor w -pady {6 0} -before $c.b }
    } else {
      $c.b.telecharger state !disabled
      $c.b.local state !disabled
      pack forget $c.barre
    }
    if {$cle eq "autre"} {
      $c.etat configure -text [expr {[info exists etat(autre)] ? $etat(autre) : ""}]
      continue
    }
    # (the download button only when there is something to download:
    # not installed, and a download offered here)
    if {[installe $cle] || [disponible $cle] ne {}} {
      pack forget $c.b.telecharger
    } elseif {[winfo manager $c.b.telecharger] eq {}} {
      pack $c.b.telecharger -side left -padx {0 6} -before $c.b.local
    }
    set dispo [disponible $cle]
    if {$dispo ne {}} { $c.b.telecharger state disabled }
    # (Toby's light version: beside the download button, with its state)
    if {[winfo exists $c.b.leger]} {
      if {[winfo manager $c.b.telecharger] eq {} || ![nvidia]} {
        pack forget $c.b.leger
      } elseif {[winfo manager $c.b.leger] eq {}} {
        pack $c.b.leger -side left -padx {0 6} -after $c.b.telecharger
      }
      $c.b.leger state [expr {[info exists enCours($cle)] || $dispo ne {} ? "disabled" : "!disabled"}]
    }
    if {[info exists etat($cle)] && $etat($cle) ne {}} {
      $c.etat configure -text $etat($cle)
    } elseif {[installe $cle]} {
      # the version, as the engine gives it ("id name"), and where it is
      set v [version $cle]
      $c.etat configure -text [expr {$v ne {} ? "✓ [T "Installé :" "Installed:"] $v" : [T "✓ Déjà installé" "✓ Already installed"]}]
      # (installed: nothing to download, "Choose a file" stays)
      pack forget $c.b.telecharger
      catch {pack forget $c.b.leger}
      # (the tooltip set once: Set adds bindings each time)
      set bulle "[T "Programme :" "Program:"] [lindex [moteurDe $cle] 1]"
      if {![info exists ::utils::tooltip::message($c.etat)] || $::utils::tooltip::message($c.etat) ne $bulle} {
        catch {::utils::tooltip::Set $c.etat $bulle}
      }
    } elseif {$dispo ne {}} {
      $c.etat configure -text $dispo
    } else {
      $c.etat configure -text {}
    }
  }
}

### Why the download is not offered here ({} if it is)
proc ::moderne::ajout::disponible {cle} {
  variable manifesteToby
  switch $cle {
    toby {
      if {$manifesteToby eq {}} {
        return [T "Téléchargement bientôt disponible (Toby pas encore publié) ; « Choisir un fichier » pour un Toby déjà installé." \
                  "Download available soon (Toby not published yet); \"Choose a file\" for a Toby already installed."]
      }
    }
    leela {
      if {!$::windowsOS} {
        return [T "Sous Linux, Leela ne fournit pas de programme tout prêt à télécharger : installe lc0 avec ta distribution ou compile-le (lczero.org), puis « Choisir un fichier »." \
                  "On Linux, Leela provides no ready-made program to download: install lc0 from your distribution or build it (lczero.org), then \"Choose a file\"."]
      }
    }
  }
  return {}
}

proc ::moderne::ajout::etat {cle texte {pct {}}} {
  variable w
  variable etat
  set etat($cle) $texte
  if {[winfo exists $w.f.c$cle]} {
    $w.f.c$cle.etat configure -text $texte
    if {$pct ne {}} { $w.f.c$cle.barre configure -value $pct }
  }
}

################################################################################
### Local file
################################################################################

proc ::moderne::ajout::local {cle} {
  variable w
  set types [expr {$::windowsOS ? [list [list [T "Programmes" "Programs"] .exe] [list [T "Tous les fichiers" "All files"] *]] \
                                 : [list [list [T "Tous les fichiers" "All files"] *]]}]
  set f [tk_getOpenFile -parent $w -title [T "Choisir le programme du moteur" "Choose the engine's program"] -filetypes $types]
  if {$f eq {}} { return }
  if {$cle eq "autre"} {
    # named after its program until it gives its own name ("id name")
    variable renommer
    variable versions
    set nom [file rootname [file tail $f]]
    set i 2 ; set base $nom
    while {[lsearch -exact -index 0 $::engines(list) $nom] >= 0} { set nom "$base ($i)" ; incr i }
    enregistrer $nom $f {}
    set cmd [file normalize $f]
    set renommer($cmd) $nom
    catch {unset versions($cmd)}
    versionMoteur [lindex $::engines(list) [lsearch -exact -index 0 $::engines(list) $nom]]
    etat autre [T "Lecture du nom du moteur…" "Reading the engine's name…"]
    listeMoteurs
    return
  }
  switch $cle {
    toby      { enregistrer "Toby - The Oracle By Yosha" $f [optionsToby] }
    stockfish { enregistrer Stockfish $f [::moderne::moteurs::optionsStockfish] }
    leela     { enregistrer "Leela (lc0)" $f [::moderne::moteurs::optionsLeela $f] }
  }
  etat $cle [T "✓ Ajouté : [file tail $f]" "✓ Added: [file tail $f]"]
  majCartes
}

### Toby's options: none. Toby's calculator defaults to Auto (Leela with
### an NVIDIA card in Classical, else Stockfish), the recommended value.
proc ::moderne::ajout::optionsToby {} {
  return {}
}

################################################################################
### Downloads (curl, in the background) and unpacking
################################################################################

### Runs the steps of cle one after the other: each step is a command that
### calls ::moderne::ajout::suite cle when it is done
proc ::moderne::ajout::telecharger {cle {variante {}}} {
  variable enCours
  variable etapes
  if {[info exists enCours($cle)]} { return }
  variable tobyVariante $variante
  set dest [dossier]
  switch $cle {
    stockfish {
      set fichier [expr {$::windowsOS ? "stockfish-windows-x86-64-universal.zip" : "stockfish-linux-x86-64-universal.tar.gz"}]
      variable urls
      set url [dict get $urls stockfish]/$fichier
      set etapes($cle) [list \
          [list recuperer $url [file join $dest $fichier] Stockfish] \
          [list deballer [file join $dest $fichier] [file join $dest stockfish]] \
          [list installerStockfish [file join $dest stockfish]]]
    }
    leela {
      set etapes($cle) [list \
          [list chercherLc0 [file join $dest lc0]] \
          [list recuperer [dict get $::moderne::ajout::urls reseau] \
               [file join $dest lc0 BT3-768x15x24h-swa-2790000.pb.gz] [T "réseau de Leela" "Leela's network"]] \
          [list installerLeela [file join $dest lc0]]]
    }
    toby {
      set etapes($cle) [list [list manifesteToby [file join $dest Toby]]]
    }
  }
  set enCours($cle) 1
  majCartes
  suite $cle
}

proc ::moderne::ajout::suite {cle} {
  variable etapes
  variable enCours
  if {![info exists enCours($cle)]} { return }
  if {![llength $etapes($cle)]} {
    unset enCours($cle)
    majCartes
    return
  }
  set e [lindex $etapes($cle) 0]
  set etapes($cle) [lrange $etapes($cle) 1 end]
  if {[catch {::moderne::ajout::[lindex $e 0] $cle {*}[lrange $e 1 end]} err]} {
    echec $cle $err
  }
}

### The download or the setup failed: the card says why
proc ::moderne::ajout::echec {cle err} {
  variable enCours
  unset -nocomplain enCours($cle)
  etat $cle "[T "Échec" "Failed"] : $err"
  majCartes
}

### Downloads url to fichier (size shown as it grows), then the next step;
### sha256 checked when given
proc ::moderne::ajout::recuperer {cle url fichier quoi {sha256 {}} {octets 0}} {
  file mkdir [file dirname $fichier]
  file delete -force $fichier.part
  set cmd [list curl -sSLf --connect-timeout 20 -A "Siby (add an engine)" -o $fichier.part $url]
  if {[catch {open "|$cmd 2>@1" r} p]} { error [T "téléchargement impossible (curl)" "download failed (curl)"] }
  fconfigure $p -blocking 0
  variable dl
  set dl($cle) [list $p $fichier $quoi $sha256 $octets {}]
  fileevent $p readable [list ::moderne::ajout::recupLu $cle]
  after 500 [list ::moderne::ajout::recupSuivi $cle]
}

proc ::moderne::ajout::recupSuivi {cle} {
  variable dl
  if {![info exists dl($cle)]} { return }
  lassign $dl($cle) p fichier quoi sha256 octets
  set n 0
  catch {set n [file size $fichier.part]}
  set mo [format %.0f [expr {$n / 1048576.0}]]
  if {$octets > 0} {
    set pct [expr {min(99, int(100.0 * $n / $octets))}]
    etat $cle "$quoi : [T "téléchargement" "downloading"] $pct % ($mo / [format %.0f [expr {$octets / 1048576.0}]] Mo)" $pct
  } else {
    etat $cle "$quoi : [T "téléchargement" "downloading"] $mo Mo" 0
  }
  after 500 [list ::moderne::ajout::recupSuivi $cle]
}

proc ::moderne::ajout::recupLu {cle} {
  variable dl
  lassign $dl($cle) p fichier quoi sha256 octets sortie
  append sortie [read $p]
  lset dl($cle) 5 $sortie
  if {![eof $p]} { return }
  fconfigure $p -blocking 1
  set code [catch {close $p} err]
  unset dl($cle)
  if {$code || ![file exists $fichier.part] || [file size $fichier.part] == 0} {
    file delete -force $fichier.part
    echec $cle "$quoi : [T "téléchargement impossible" "download failed"] [string trim $sortie]"
    return
  }
  if {$sha256 ne {}} {
    if {[catch {sc_gaby sha256 $fichier.part} h] || ![string equal -nocase $h $sha256]} {
      file delete -force $fichier.part
      echec $cle "$quoi : [T "fichier abîmé pendant le téléchargement (sha256)" "file damaged during the download (sha256)"]"
      return
    }
  }
  file rename -force $fichier.part $fichier
  suite $cle
}

### Unpacks an archive (.zip in Tcl, .tar.gz with tar) into dest
proc ::moderne::ajout::deballer {cle archive dest} {
  file mkdir $dest
  etat $cle [T "Décompression…" "Unpacking…"]
  if {[string match -nocase *.zip $archive]} {
    variable zip
    variable zipTotal
    variable zipFait
    set entrees [::moderne::gaby::lireZip $archive]
    set zip($cle) [list $archive $dest $entrees]
    # (the bar follows the bytes unpacked)
    set zipTotal($cle) 0
    foreach e $entrees { incr zipTotal($cle) [lindex $e 3] }
    set zipFait($cle) 0
    etat $cle [T "Décompression… 0 %" "Unpacking… 0 %"] 0
    after idle [list ::moderne::ajout::zipEntree $cle]
  } else {
    if {[catch {open [list | tar xzf $archive -C $dest 2>@1] r} p]} { error "tar: $p" }
    fconfigure $p -blocking 0
    fileevent $p readable [list ::moderne::ajout::tarFin $cle $p $archive]
  }
}

proc ::moderne::ajout::tarFin {cle p archive} {
  read $p
  if {![eof $p]} { return }
  fconfigure $p -blocking 1
  if {[catch {close $p} err]} { echec $cle "tar : $err" ; return }
  file delete -force $archive
  suite $cle
}

### One entry of the zip at a time (chan copy: the window stays responsive)
proc ::moderne::ajout::zipEntree {cle} {
  variable zip
  lassign $zip($cle) archive dest entrees
  if {![llength $entrees]} {
    unset zip($cle)
    file delete -force $archive
    suite $cle
    return
  }
  lassign [lindex $entrees 0] nom methode comp dec donnees droits
  lset zip($cle) 2 [lrange $entrees 1 end]
  # (no absolute path nor ".." in an archive entry)
  set nom [string map {\\ /} $nom]
  if {[string match */ $nom] || [string match /* $nom] || [string match *..* $nom]} {
    after idle [list ::moderne::ajout::zipEntree $cle]
    return
  }
  set cible [file join $dest {*}[split $nom /]]
  file mkdir [file dirname $cible]
  set in [open $archive rb]
  seek $in $donnees
  if {$methode == 8} { zlib push inflate $in }
  set out [open $cible wb]
  zipMorceau $cle $in $out $cible $droits $dec
}

### One piece (8 MB) of an entry at a time: the bar moves during the large
### files too (the network weights)
proc ::moderne::ajout::zipMorceau {cle in out cible droits reste} {
  set t [expr {min($reste, 8388608)}]
  chan copy $in $out -size $t -command [list ::moderne::ajout::zipCopie $cle $in $out $cible $droits $reste]
}

proc ::moderne::ajout::zipCopie {cle in out cible droits reste n {err {}}} {
  variable zipTotal
  variable zipFait
  if {$err eq {} && [info exists zipFait($cle)]} {
    incr zipFait($cle) $n
    set pct [expr {$zipTotal($cle) > 0 ? min(99, int(100.0 * $zipFait($cle) / $zipTotal($cle))) : 0}]
    etat $cle "[T "Décompression…" "Unpacking…"] $pct %" $pct
  }
  # (the rest of this entry, unless it is all there or an error)
  if {$err eq {} && $n > 0 && $reste - $n > 0} {
    zipMorceau $cle $in $out $cible $droits [expr {$reste - $n}]
    return
  }
  catch {close $in}
  catch {close $out}
  # (Linux: the programs of the archive stay executable, e.g. Toby's
  # torch_shm_manager)
  if {!$::windowsOS && $droits & 0o111} { catch {file attributes $cible -permissions [format 0%o $droits]} }
  if {$err ne {}} { echec $cle "zip : $err" ; return }
  after idle [list ::moderne::ajout::zipEntree $cle]
}

### Makes a downloaded program executable (Linux: zip keeps no rights)
proc ::moderne::ajout::executable {f} {
  if {!$::windowsOS} { catch {file attributes $f -permissions u+x} }
}

### First file matching one of the patterns under dir (recursive)
proc ::moderne::ajout::chercherFichier {dir motifs} {
  foreach m $motifs {
    set l [glob -nocomplain -types f -directory $dir -- $m]
    if {[llength $l]} { return [lindex [lsort $l] 0] }
  }
  foreach s [lsort [glob -nocomplain -types d -directory $dir *]] {
    set r [chercherFichier $s $motifs]
    if {$r ne {}} { return $r }
  }
  return {}
}

################################################################################
### Per engine
################################################################################

proc ::moderne::ajout::installerStockfish {cle dir} {
  set m [expr {$::windowsOS ? {stockfish*.exe} : {stockfish-*}}]
  set exe [chercherFichier $dir [list $m stockfish]]
  if {$exe eq {}} { error [T "programme introuvable dans l'archive" "program not found in the archive"] }
  executable $exe
  enregistrer Stockfish $exe [::moderne::moteurs::optionsStockfish]
  etat $cle [T "✓ Stockfish installé" "✓ Stockfish installed"] 100
  suite $cle
}

### lc0: the latest Windows release on GitHub, CUDA build with an NVIDIA
### card, CPU build otherwise
proc ::moderne::ajout::chercherLc0 {cle dest} {
  if {!$::windowsOS} { error [T "pas de version Linux publiée par Leela" "Leela publishes no Linux build"] }
  etat $cle [T "Recherche de la dernière version de Leela…" "Looking for Leela's latest release…"]
  variable urls
  ::moderne::direct::lireJson [dict get $urls lc0] \
      [list ::moderne::ajout::lc0Version $cle $dest]
}

proc ::moderne::ajout::lc0Version {cle dest v} {
  set assets {}
  foreach a [::moderne::json::get $v assets {}] {
    lappend assets [list [::moderne::json::get $a name {}] [::moderne::json::get $a browser_download_url {}] \
                         [::moderne::json::get $a size 0]]
  }
  set motifs [expr {[nvidia] ? {*windows*cuda*.zip *windows*dx12*.zip *windows*cpu*.zip}
                             : {*windows*cpu*dnnl*.zip *windows*cpu*.zip *windows*openblas*.zip *windows*dx12*.zip}}]
  set choix {}
  foreach m $motifs {
    # (never a "nodll" build: it needs CUDA installed on the computer, else
    # lc0 does not start, cudart64_110.dll missing, Yosha 2026-11-04)
    foreach a $assets {
      if {[string match -nocase *nodll* [lindex $a 0]]} { continue }
      if {[string match -nocase $m [lindex $a 0]]} { set choix $a ; break }
    }
    if {$choix ne {}} { break }
  }
  if {$choix eq {}} {
    echec $cle [T "version Windows de Leela introuvable sur GitHub (lczero.org)" "Leela's Windows build not found on GitHub (lczero.org)"]
    return
  }
  lassign $choix nom url taille
  variable etapes
  set etapes($cle) [linsert $etapes($cle) 0 \
      [list recuperer $url [file join $dest $nom] "Leela ($nom)" {} $taille] \
      [list deballer [file join $dest $nom] $dest]]
  suite $cle
}

proc ::moderne::ajout::installerLeela {cle dir {fini 1}} {
  set exe [chercherFichier $dir [expr {$::windowsOS ? {lc0.exe} : {lc0}}]]
  if {$exe eq {}} { error [T "lc0 introuvable dans l'archive" "lc0 not found in the archive"] }
  executable $exe
  set opts [::moderne::moteurs::optionsLeela $exe]
  set net [chercherFichier $dir {*.pb.gz}]
  if {$net ne {}} {
    set i [lsearch -index 0 $opts WeightsFile]
    if {$i >= 0} { set opts [lreplace $opts $i $i] }
    lappend opts [list WeightsFile [file normalize $net]]
  }
  enregistrer "Leela (lc0)" $exe $opts
  if {$fini} { etat $cle [T "✓ Leela installé" "✓ Leela installed"] 100 }
  suite $cle
}

### Toby: its manifest (docs/INTERFACES.md), then its components
proc ::moderne::ajout::manifesteToby {cle dest} {
  variable manifesteToby
  if {$manifesteToby eq {}} { error [T "Toby n'est pas encore publié" "Toby is not published yet"] }
  etat $cle [T "Lecture de la fiche de Toby…" "Reading Toby's manifest…"]
  ::moderne::direct::lireJson $manifesteToby [list ::moderne::ajout::tobyComposants $cle $dest]
}

proc ::moderne::ajout::tobyComposants {cle dest v} {
  if {$v eq {}} {
    echec $cle [T "Toby n'est pas encore publié" "Toby is not published yet"]
    return
  }
  # Toby 1.0's manifest (2026-11-03): {"version", "windows": {"core",
  # "light", "full": {"fichier", "sha256", "taille"}}}, names relative to
  # the manifest; one standalone package: full (Maia and Leela on the
  # GPU) with an NVIDIA card, else light
  set os [expr {$::windowsOS ? "windows" : "linux"}]
  set pq [::moderne::json::get $v $os {}]
  if {$pq ne {} && $pq ne "null"} {
    set choix {}
    variable tobyVariante
    set ordre [expr {[nvidia] && $tobyVariante ne "light" ? {full light core} : {light core}}]
    foreach k $ordre {
      set x [::moderne::json::get $pq $k {}]
      if {$x ne {} && $x ne "null"} { set choix $x ; break }
    }
    set nom [::moderne::json::get $choix fichier {}]
    if {$nom eq {}} {
      echec $cle [T "fiche de Toby incomplète" "incomplete Toby manifest"]
      return
    }
    variable manifesteToby
    set url [expr {[regexp {^[a-z]+://} $nom] ? $nom : "[string range $manifesteToby 0 [string last / $manifesteToby]]$nom"}]
    set archive [file join [file dirname $dest] [file tail $nom]]
    variable etapes
    set etapes($cle) [concat [list \
        [list recuperer $url $archive Toby [::moderne::json::get $choix sha256 {}] [::moderne::json::get $choix taille 0]] \
        [list deballer $archive [file dirname $dest]] \
        [list installerToby $dest]] $etapes($cle)]
    suite $cle
    return
  }
  set p [::moderne::json::get $v platforms [plateforme] {}]
  if {$p eq {}} {
    echec $cle [T "pas de Toby pour cette plateforme" "no Toby for this platform"]
    return
  }
  set composants [expr {[nvidia] ? {core maia leela-cuda stockfish} : {core maia stockfish}}]
  set nouvelles {}
  foreach c $composants {
    set x [::moderne::json::get $p $c {}]
    if {$x eq {}} { continue }
    set url [::moderne::json::get $x url {}]
    set nom [file tail [lindex [split $url ?] 0]]
    if {$nom eq {}} { set nom $c.zip }
    set archive [file join [file dirname $dest] $nom]
    lappend nouvelles \
        [list recuperer $url $archive "Toby ($c)" [::moderne::json::get $x sha256 {}] [::moderne::json::get $x size 0]] \
        [list deballer $archive [file dirname $dest]]
  }
  if {![llength $nouvelles]} {
    echec $cle [T "fiche de Toby incomplète" "incomplete Toby manifest"]
    return
  }
  lappend nouvelles [list installerToby $dest]
  variable etapes
  set etapes($cle) [concat $nouvelles $etapes($cle)]
  suite $cle
}

proc ::moderne::ajout::installerToby {cle dir} {
  set exe [chercherFichier $dir [expr {$::windowsOS ? {toby.exe} : {toby}}]]
  if {$exe eq {}} { error [T "toby introuvable dans l'archive" "toby not found in the archive"] }
  executable $exe
  foreach x {lc0/lc0 stockfish/stockfish} { executable [file join [file dirname $exe] $x] }
  enregistrer "Toby - The Oracle By Yosha" $exe [optionsToby]
  etat $cle [T "✓ Toby installé" "✓ Toby installed"] 100
  suite $cle
}
