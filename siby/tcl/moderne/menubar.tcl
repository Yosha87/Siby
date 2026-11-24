###
### Siby: the menu bar, reorganised (2026-10-24)
###
### SCID's menus (.menu) are kept as they are, hidden: other code still
### reads and invokes them. Siby shows its own bar (.menuSiby) built from
### a description: each entry is either new or taken from an old entry
### (same command, state, check variable), so nothing is duplicated. The
### menus are rebuilt each time they open: states, open databases and
### recent files are always current, and the labels follow the language.
###
### Left out on purpose (still in the code): identify the opening, go to
### move number (Ctrl+G stays), game preview (in the game list's menu),
### sounds (SCID's spoken moves need the Snack library, absent from Siby),
### correspondence chess, FICS,
### engine tournaments, tactical game, external hardware (Novag), bookmarks,
### file finder, read-only (the padlock does it), game info panel and status
### bar options, startup windows, the 17 languages Siby is not translated
### into.
###
### Shortcuts: Ctrl+C copies the game (PGN), Ctrl+Shift+C the position
### (FEN), Ctrl+V pastes a game or a position (detected).
###

namespace eval ::moderne::menubar {
  variable barre .menuSiby
  variable menus {
    fichier  "Fichier"    "File"
    jouer    "Jouer"      "Play"
    edition  "Édition"    "Edit"
    partie   "Partie"     "Game"
    chercher "Rechercher" "Search"
    fenetres "Fenêtres"   "Windows"
    outils   "Outils"     "Tools"
    options  "Options"    "Options"
    aide     "Aide"       "Help"
  }
}

proc ::moderne::menubar::T {fr en} { return [::moderne::tr $fr $en] }

################################################################################
### Shortcut text: "control-S" -> "Ctrl+Maj+S"
################################################################################

proc ::moderne::menubar::raccourci {a} {
  if {$a eq {}} { return {} }
  set fr [expr {[::moderne::tr F E] eq "F"}]
  set maj [expr {$fr ? "Maj+" : "Shift+"}]
  if {[regexp -nocase {^(control|ctrl)-sht-(.*)$} $a -> - t]} { return "Ctrl+$maj$t" }
  if {[regexp -nocase {^(control|ctrl)-(.*)$} $a -> - t]} {
    set noms [expr {$fr ? {delete Suppr home Début end Fin down ↓ up ↑ space Espace} : {delete Del home Home end End down ↓ up ↑ space Space}}]
    if {[dict exists $noms [string tolower $t]]} { return "Ctrl+[dict get $noms [string tolower $t]]" }
    if {[string length $t] == 1 && [string is upper $t]} { return "Ctrl+$maj$t" }
    return "Ctrl+[string toupper $t]"
  }
  if {[regexp -nocase {^alt-(.*)$} $a -> t]} { return "Alt+$t" }
  return $a
}

################################################################################
### Old entries
################################################################################

### Index of the entry of old menu m whose command (or variable) matches
### the glob pattern, -1 if none
proc ::moderne::menubar::trouver {m motif} {
  if {![winfo exists $m]} { return -1 }
  set n [$m index end]
  if {$n eq "none"} { return -1 }
  for {set i 0} {$i <= $n} {incr i} {
    if {[$m type $i] in {separator tearoff}} { continue }
    set c {} ; catch {set c [string trim [$m entrycget $i -command]]}
    set v {} ; catch {set v [$m entrycget $i -variable]}
    set l {} ; catch {set l [$m entrycget $i -label]}
    if {[string match $motif $c] || ($v ne {} && [string match $motif $v]) || [string match $motif "label:$l"]} { return $i }
  }
  return -1
}

### Copies entry i of old menu m to the end of menu d (label, shortcut and
### cascade target may be replaced); a cascade is copied with its entries
proc ::moderne::menubar::cloner {m i d {label {}} {exclus {}}} {
  set type [$m type $i]
  set opts {}
  foreach o {-command -variable -value -onvalue -offvalue -state -indicatoron -selectcolor -image -compound} {
    if {![catch {$m entrycget $i $o} v] && $v ne {}} { lappend opts $o $v }
  }
  set l [expr {$label ne {} ? $label : [$m entrycget $i -label]}]
  set a {}
  catch {set a [raccourci [$m entrycget $i -accelerator]]}
  if {$type eq "cascade"} {
    set src [$m entrycget $i -menu]
    set sous [nouveauSous $d]
    copierMenu $src $sous $exclus
    $d add cascade -label $l -menu $sous {*}[expr {[$m entrycget $i -state] eq "disabled" ? {-state disabled} : {}}]
    return
  }
  $d add $type -label $l -accelerator $a {*}$opts
}

### A new submenu of d
proc ::moderne::menubar::nouveauSous {d} {
  set k 0
  while {[winfo exists $d.s$k]} { incr k }
  menu $d.s$k -tearoff 0
  return $d.s$k
}

### Every entry of old menu src into d, except those matching an exclusion
### pattern (label:..., command or variable glob)
proc ::moderne::menubar::copierMenu {src d {exclus {}}} {
  if {![winfo exists $src]} { return }
  # (menus filled when they open)
  catch {set pc [$src cget -postcommand] ; if {$pc ne {}} { uplevel #0 $pc }}
  set n [$src index end]
  if {$n eq "none"} { return }
  set dernierSep 1
  for {set i 0} {$i <= $n} {incr i} {
    set type [$src type $i]
    if {$type eq "tearoff"} { continue }
    if {$type eq "separator"} {
      if {!$dernierSep} { $d add separator ; set dernierSep 1 }
      continue
    }
    set c {} ; catch {set c [string trim [$src entrycget $i -command]]}
    set v {} ; catch {set v [$src entrycget $i -variable]}
    set l {} ; catch {set l [$src entrycget $i -label]}
    set ok 1
    foreach x $exclus {
      if {[string match $x "label:$l"] || ($c ne {} && [string match $x $c]) || ($v ne {} && [string match $x $v])} { set ok 0 ; break }
    }
    if {!$ok} { continue }
    cloner $src $i $d
    set dernierSep 0
  }
  # (no separator at the end)
  if {[$d index end] ne "none" && [$d type end] eq "separator"} { $d delete end }
}

################################################################################
### Description of the menus
################################################################################
###   {cmd fr en command ?shortcut?}         new entry
###   {old menu pattern ?fr en? ?shortcut?}  an old entry (its command, state...)
###   {chk fr en variable command ?shortcut?} new check entry
###   {sous fr en {description}}             new submenu
###   {copie menu fr en ?exclusions?}        an old submenu, copied
###   {proc name}                            entries added by a procedure
###   sep

proc ::moderne::menubar::description {nom} {
  switch -- $nom {
    fichier {
      return {
        {cmd "Mes bases" "My databases" ::moderne::mesbases::ouvrir}
        {old .menu.file ::file::New "Nouvelle base…" "New database…"}
        {old .menu.file ::file::Open "Ouvrir…" "Open…"}
        {old .menu.file ::file::Close "Fermer la base" "Close the database"}
        {cmd "Enregistrer la partie" "Save the game" ::gameSaveSiby Ctrl+S}
        {cmd "Enregistrer la partie sous…" "Save the game as…" ::moderne::enregistrerSous Ctrl+Maj+S}
        {proc cadenas}
        sep
        {proc bases}
        {proc recents}
        sep
        {old .menu.file ::file::Exit "Quitter" "Quit"}
      }
    }
    jouer {
      return {
        {cmd "Jouer contre Toby (adversaire humain)…" "Play against Toby (human opponent)…" ::moderne::toby::jeuFenetre}
        {cmd "Jouer contre un moteur…" "Play against an engine…" ::sergame::config}
        sep
        {cmd "Alter Ego : jouer contre une personne réelle…" "Alter Ego: play against a real player…" ::moderne::alterego::ouvrir}
        {copie .menu.play.alterego "Alter Ego : favoris et récents" "Alter Ego: favourites and recent"}
        sep
        {cmd "Jouer cette position contre Toby…" "Play this position against Toby…" {::moderne::toby::jouerIci toby}}
        {cmd "Jouer cette position contre un Alter Ego…" "Play this position against an Alter Ego…" {::moderne::toby::jouerIci alterego}}
        sep
        {sous "Entraînement" "Training" {
          {cmd "Réviser la ligne : je joue les Blancs" "Revise the line: I play White" {::moderne::revision::lancer white}}
          {cmd "Réviser la ligne : je joue les Noirs" "Revise the line: I play Black" {::moderne::revision::lancer black}}
          sep
          {cmd "Répertoire (répétition espacée)…" "Repertoire (spaced repetition)…" ::moderne::entrainement::ouvrir}
          {cmd "Ouvertures" "Openings" ::opening::config}
        }}
      }
    }
    edition {
      return {
        {old .menu.edit {menuUndo undo} "Annuler" "Undo" Ctrl+Z}
        {old .menu.edit {menuUndo redo} "Refaire" "Redo" Ctrl+Y}
        sep
        {cmd "Copier la partie (PGN)" "Copy the game (PGN)" ::pgn::copyPgn Ctrl+C}
        {cmd "Copier la position (FEN)" "Copy the position (FEN)" copyFEN Ctrl+Maj+C}
        {cmd "Coller une partie ou une position" "Paste a game or a position" ::moderne::menuclic::coller Ctrl+V}
        sep
        {old .menu.edit ::moderne::editeur::ouvrir "Éditeur de position…" "Board editor…"}
        {old .menu.edit importVar "Coller comme variante" "Paste as a variation"}
        {proc variantes}
        {copie .menu.edit.strip "Nettoyer" "Clean"}
        sep
        {old .menu.edit {setTrialMode*} "Mode essai" "Trial mode"}
      }
    }
    partie {
      return {
        {old .menu.game ::moderne::onglets::nouvellePartie "Nouvelle partie" "New game"}
        sep
        {old .menu.game gameSaveSiby "Enregistrer" "Save"}
        {old .menu.game gameAdd "Enregistrer comme nouvelle partie…" "Save as a new game…"}
        {old .menu.game ::moderne::enregistrerSous "Enregistrer la partie sous…" "Save the game as…"}
        sep
        {cmd "Informations de la partie…" "Game information…" ::moderne::infos::ouvrir}
        {cmd "Bilan de la partie" "Game review" ::moderne::bilan::lancer}
        {cmd "Annoter la partie…" "Annotate the game…" ::moderne::oracle::ouvrir}
        sep
        {sous "Aller à la partie" "Go to game" {
          {old .menu.game {::game::LoadNextPrev first} "Première" "First"}
          {old .menu.game {::game::LoadNextPrev previous} "Précédente" "Previous" "X"}
          {old .menu.game {::game::LoadNextPrev next} "Suivante" "Next" "C"}
          {old .menu.game {::game::LoadNextPrev last} "Dernière" "Last"}
          {old .menu.game ::game::LoadRandom "Au hasard" "Random"}
        }}
        {proc historique}
        sep
        {old .menu.game ::game::Reload "Recharger la partie" "Reload the game"}
        {old .menu.game ::game::Delete "Supprimer la partie" "Delete the game"}
      }
    }
    chercher {
      # (one Search window with its tabs: Games, Position, Moves, Material
      # and patterns; the online tournaments setting moved where it acts,
      # the Search window and the opening library; CQL removed: "the nerds
      # will have the real SCID", Yosha 2026-11-02)
      return {
        {cmd "Rechercher…" "Search…" ::moderne::rparties::ouvrir Ctrl+Maj+F}
        {old .menu.search ::search::board "Position actuelle…" "Current position…"}
        sep
        {old .menu.search ::plist::Open "Joueur·ses…" "Players…"}
        {old .menu.search ::tourney::Open "Tournois…" "Tournaments…"}
        sep
        {old .menu.search ::search::filter::reset "Réafficher toutes les parties (filtre)" "Show all games (filter)"}
        {old .menu.search ::search::filter::negate "Inverser le filtre" "Invert the filter"}
        sep
        {old .menu.search ::search::header "Recherche avancée dans les en-têtes…" "Advanced header search…"}
      }
    }
    fenetres {
      return {
        {old .menu.windows ::moderne::disposition::lab}
        {copie .menu.windows.perso "Mes dispositions" "My layouts"}
        sep
        {cmd "Mes bases" "My databases" ::moderne::mesbases::ouvrir}
        {old .menu.windows ::windows::gamelist::Open "Liste des parties" "Game list"}
        {old .menu.windows ::pgn::Open "Notation" "Notation"}
        {old .menu.windows ::commenteditor::Open "Commentaire" "Comment"}
        {cmd "Bibliothèque d'ouvertures" "Opening library" ::moderne::biblio::ouvrir}
        {old .menu.windows ::tb::Open "Tables de finales" "Tablebase"}
        {cmd "Retransmissions en direct" "Live broadcasts" ::moderne::direct::ouvrir}
        sep
        {sous "Plus (classique)" "More (classic)" {
          {old .menu.windows ::crosstab::Open "Tableau du tournoi" "Crosstable"}
          {old .menu.windows ::maint::Open "Maintenance" "Maintenance"}
          {old .menu.windows ::windows::stats::Open "Statistiques" "Statistics"}
          {old .menu.windows ::tree::Open "Arbre (classique)" "Tree (classic)"}
          {old .menu.windows ::book::Open "Livres d'ouvertures (.bin)" "Opening books (.bin)"}
        }}
      }
    }
    outils {
      return {
        {old .menu.tools ::enginelist::choose "Moteurs…" "Engines…"}
        {old .menu.tools ::moderne::ajout::ouvrir "Ajouter un moteur…" "Add an engine…"}
        {old .menu.tools ::moderne::moteurs::menu "Détecter les moteurs (Stockfish, Leela, Maia, Toby)" "Detect engines (Stockfish, Leela, Maia, Toby)"}
        {old .menu.tools {startAnalysisWin F2} "Lancer le moteur 1" "Start engine 1"}
        {old .menu.tools {startAnalysisWin F3} "Lancer le moteur 2" "Start engine 2"}
        sep
        {old .menu.tools ::moderne::oracle::ouvrir "Annoter la partie…" "Annotate the game…"}
        {old .menu.tools ::moderne::prepa::ouvrirDisposition}
        {cmd "Parties en ligne des adversaires…" "Opponents' online games…" ::moderne::enligne::fenetre}
        sep
        {copie .menu.tools.gaby "Gaby" "Gaby"}
        {copie .menu.tools.utils "Maintenance de la base" "Database maintenance"}
        {cmd "Réordonner les parties…" "Reorder the games…" ::moderne::reordonner::ouvrir}
        {old .menu.tools ::moderne::cleanpgn::dialogue}
        {old .menu.tools ::moderne::nsb::reconstruire}
        {sous "Importer / exporter" "Import / export" {
          {old .menu.tools importPgnFile "Importer un fichier PGN…" "Import a PGN file…"}
          {copie .menu.tools.exportcurrent "Exporter la partie" "Export the game"}
          {copie .menu.tools.exportfilter "Exporter les parties de la liste (filtre)" "Export the games of the list (filter)"}
        }}
        sep
        {sous "Plus (classique)" "More (classic)" {
          {old .menu.tools ::preport::preportDlg "Rapport sur un joueur ou une joueuse" "Player report"}
          {old .menu.tools ::book::tuning "Réglage des livres d'ouvertures" "Opening book tuning"}
          {proc plusOutils}
        }}
      }
    }
    options {
      return {
        {cmd "Mon profil (nom, comptes Lichess et Chess.com, répertoire)…" "My profile (name, Lichess and Chess.com accounts, repertoire)…" ::moderne::profil::ouvrir}
        sep
        {copie .menu.options.theme "Apparence" "Appearance" {{label:Barre d'état*} {label:Status bar*}}}
        {old .menu.options chooseBoardColors "Échiquier…" "Board…"}
        {chk "Flèches de navigation sous la notation" "Navigation arrows under the notation" ::moderne::flechesNav ::moderne::bandeau::basculerFleches}
        {chk "Position de départ : camp au trait en bas" "Starting position: side to move at the bottom" ::moderne::traitEnBas {catch flipBoardForPlayerNames}}
        {copie .menu.options.entry "Coups" "Moves"}
        {proc sons}
        {proc toby}
        {copie .menu.options.evalbar "Barres d'évaluation" "Evaluation bars" {::gameInfo(showEval) ::gbrowser::showEval ::fics::showEval ::evalTicks ::evalUseLog label:Échelle label:Scale label:Temps* label:Eval*Time*}}
        {copie .menu.options.colour "Couleurs" "Colours" {label:Arrière-plan label:Background* {label:Couleur du texte} label:Text* {label:Sélection des bases} label:Switcher* {label:Barre de progression} label:Progress*}}
        {copie .menu.options.fonts "Polices" "Fonts"}
        {copie .menu.options.numbers "Format des nombres" "Number format"}
        {copie .menu.options.export "Exportation" "Export"}
        sep
        {old .menu.options ::recentFiles::configure "Fichiers récents…" "Recent files…"}
        {sous "Dossiers et fichiers" "Folders and files" {
          {old .menu.options setTableBaseDir "Tables de finales…" "Endgame tablebases…"}
          {old .menu.options setBooksDir "Livres d'ouvertures…" "Opening books…"}
          {old .menu.options setTacticsBasesDir "Bases d'entraînement…" "Training databases…"}
          {old .menu.options ::windows::eco::LoadFile "Fichier ECO…" "ECO file…"}
          {old .menu.options readSpellCheckFile "Fichier d'orthographe des noms…" "Name spelling file…"}
        }}
        {old .menu.options.windows toggleFullScreen "Plein écran" "Full screen"}
        sep
        {old .menu.options {set defaultDBs*} "Rouvrir les bases au démarrage" "Reopen the databases at start"}
        {proc fichiersParDefaut}
        {old .menu.options {set optionF*} "Enregistrer les options" "Save the options"}
        {old .menu.options optionsAutoSave "Enregistrer les options en quittant" "Save the options on quitting"}
        {cmd "Revenir aux réglages par défaut… (tes bases, tes parties, Gaby et tes moteurs restent ; Siby redémarre)" "Back to the default settings… (your databases, games, Gaby and engines stay; Siby restarts)" ::moderne::reglagesDefaut::demander}
      }
    }
    aide {
      set l {
        {old .menu.help {helpWindow Contents} "Aide" "Help"}
        sep
        {cmd "Rechercher une mise à jour de Siby" "Check for Siby updates" {::moderne::majsiby::verifier 1 ; catch {::moderne::majtoby::verifier 1}}}
        {cmd "Signaler un problème…" "Report a problem…" {::moderne::rapport::demander}}
        {cmd "Soutenir Triby…" "Support Triby…" {openURL $::moderne::merci::soutien}}
        {cmd "Remerciements" "Thanks" ::moderne::merci::ouvrir}
        {cmd "À propos de Siby" "About Siby" ::moderne::menubar::aPropos}
      }
      # (Windows: the program folder and Windows' registrations removed, the
      # user's files kept, Yosha 2026-11-07)
      if {$::windowsOS} {
        lappend l sep {cmd "Désinstaller Siby…" "Uninstall Siby…" ::moderne::systeme::desinstaller}
      }
      return $l
    }
  }
}

### A game from a set-up position: the side to move at the bottom (main.tcl,
### flipBoardForPlayerNames); on by default
if {![info exists ::moderne::traitEnBas]} { set ::moderne::traitEnBas 1 }

### Builds menu d from a description
proc ::moderne::menubar::construire {d desc} {
  foreach x [winfo children $d] { destroy $x }
  $d delete 0 end
  foreach e $desc {
    switch -- [lindex $e 0] {
      sep {
        if {[$d index end] ne "none" && [$d type end] ne "separator"} { $d add separator }
      }
      cmd {
        lassign $e - fr en c a
        $d add command -label [T $fr $en] -command $c -accelerator [raccourci2 $a]
      }
      chk {
        lassign $e - fr en v c a
        $d add checkbutton -label [T $fr $en] -variable $v -command $c -accelerator [raccourci2 $a]
      }
      old {
        lassign $e - m motif fr en a
        set i [trouver $m $motif]
        if {$i < 0} { continue }
        cloner $m $i $d [expr {$fr ne {} ? [T $fr $en] : {}}]
        if {[llength $e] > 5} { catch {$d entryconfigure end -accelerator [raccourci2 $a]} }
      }
      sous {
        lassign $e - fr en sd
        set s [nouveauSous $d]
        construire $s $sd
        if {[$s index end] ne "none"} { $d add cascade -label [T $fr $en] -menu $s }
      }
      copie {
        lassign $e - m fr en exclus
        set s [nouveauSous $d]
        copierMenu $m $s $exclus
        if {[$s index end] ne "none"} { $d add cascade -label [T $fr $en] -menu $s }
      }
      proc { catch {[lindex $e 1] $d} }
    }
  }
  if {[$d index end] ne "none" && [$d type end] eq "separator"} { $d delete end }
}

### A shortcut written by hand (Ctrl+Maj+C) in the language
proc ::moderne::menubar::raccourci2 {a} {
  if {[::moderne::tr F E] eq "E"} { set a [string map {Maj+ Shift+ Suppr Del {Pg préc} PgUp {Pg suiv} PgDn} $a] }
  return $a
}

################################################################################
### Dynamic parts
################################################################################

### Padlock of the current database
proc ::moderne::menubar::cadenas {d} {
  set b [sc_base current]
  if {$b == [sc_info clipbase] || ![sc_base inUse $b]} { return }
  set f [::moderne::mesbases::chemin [::moderne::menuclic::fichierBase $b]]
  $d add command -label [expr {[::moderne::mesbases::cadenassee $f] ? [T "Retirer le cadenas" "Remove the padlock"] \
      : [T "Cadenasser (protéger des modifications)" "Padlock (protect from changes)"]}] \
      -command [list ::moderne::mesbases::basculerCadenas $f]
}

### Open databases (Alt+1…9)
proc ::moderne::menubar::bases {d} {
  set s [nouveauSous $d]
  for {set i 1} {$i <= [sc_base count total]} {incr i} {
    if {![sc_base inUse $i] && $i != [sc_info clipbase]} { continue }
    set nom [::moderne::nomBase [sc_base filename $i]]
    if {$i == [sc_info clipbase]} { set nom [T "Presse-papier" "Clipbase"] }
    $s add radiobutton -label $nom -variable ::moderne::menubar::courante -value $i \
        -accelerator "Alt+$i" -command [list ::file::SwitchToBase $i]
  }
  set ::moderne::menubar::courante [sc_base current]
  $d add cascade -label [T "Changer de base" "Switch database"] -menu $s
}

### Recent files (from SCID's File menu)
proc ::moderne::menubar::recents {d} {
  set n [.menu.file index end]
  set k 0
  for {set i 0} {$i <= $n} {incr i} {
    if {[.menu.file type $i] ne "command"} { continue }
    if {[string match ::recentFiles::load* [.menu.file entrycget $i -command]]} {
      if {!$k} { $d add separator }
      cloner .menu.file $i $d
      incr k
    }
  }
}

### Variation commands (submenus listing the variations)
proc ::moderne::menubar::variantes {d} {
  if {[sc_var count] == 0 && [sc_var level] == 0} { return }
  foreach {sm fr en} {.menu.edit.main "Promouvoir une variante" "Promote a variation"
                      .menu.edit.first "Placer une variante en premier" "Make a variation first"
                      .menu.edit.del "Supprimer une variante" "Delete a variation"} {
    for {set k 0} {$k <= [.menu.edit index end]} {incr k} {
      if {[.menu.edit type $k] eq "cascade" && [.menu.edit entrycget $k -menu] eq $sm} {
        if {[.menu.edit entrycget $k -state] ne "disabled"} { cloner .menu.edit $k $d [T $fr $en] }
      }
    }
  }
}

### Last games seen (end of SCID's Game menu)
proc ::moderne::menubar::historique {d} {
  set s [nouveauSous $d]
  set n [.menu.game index end]
  for {set i 0} {$i <= $n} {incr i} {
    if {[.menu.game type $i] ne "command"} { continue }
    if {[string match ::bookmarks::Go* [.menu.game entrycget $i -command]]} { cloner .menu.game $i $s }
  }
  if {[$s index end] ne "none"} { $d add cascade -label [T "Parties récentes" "Recent games"] -menu $s }
}

### SCID's "More" tools, without the e-mail games
proc ::moderne::menubar::plusOutils {d} {
  copierMenu .menu.tools.plus $d {*email* *Email* *mail*}
}

### English / French only
proc ::moderne::menubar::langues {d} {
  set s [nouveauSous $d]
  set n [.menu.options.language index end]
  for {set i 0} {$i <= $n} {incr i} {
    if {[.menu.options.language type $i] ne "radiobutton"} { continue }
    set l [.menu.options.language entrycget $i -label]
    if {$l in {English Francais Français}} {
      cloner .menu.options.language $i $s [expr {$l eq "English" ? "English" : "Français"}]
    }
  }
  $d add cascade -label [T "Langue" "Language"] -menu $s
}

proc ::moderne::menubar::aPropos {} {
  set v {}
  catch {set v " $::sibyVersion"}
  tk_messageBox -icon info -type ok -title Siby -message [T \
      "Siby$v\n\nLibre et gratuit (GPL).\n\nAide › Remerciements : les projets sur lesquels Siby repose." \
      "Siby$v\n\nFree software (GPL).\n\nHelp › Thanks: the projects Siby is built on."]
}

################################################################################
### The bar
################################################################################

proc ::moderne::menubar::creer {} {
  variable barre
  variable menus
  catch {destroy $barre}
  menu $barre -tearoff 0
  foreach {nom fr en} $menus {
    set m [menu $barre.$nom -tearoff 0 -postcommand [list ::moderne::menubar::remplir $nom]]
    $barre add cascade -label [T $fr $en] -menu $m -underline 0
    # (filled once now: keyboard navigation and Windows need entries)
    catch {remplir $nom}
  }
}

proc ::moderne::menubar::remplir {nom} {
  variable barre
  construire $barre.$nom [description $nom]
  epurer $barre.$nom
}

### Labels of the bar in the language
proc ::moderne::menubar::libelles {} {
  variable barre
  variable menus
  if {![winfo exists $barre]} { return }
  set i 0
  foreach {nom fr en} $menus {
    catch {$barre entryconfigure $i -label [T $fr $en]}
    incr i
  }
}

proc ::moderne::menubar::montrer {} {
  variable barre
  if {![winfo exists $barre]} { creer }
  # Windows, dark theme: the themed row of buttons shows this bar instead
  # of the native (white) one
  if {[winfo exists .barreMenus]} {
    ::moderne::barreMenus::remplir
    ::moderne::barreMenus::afficher
    return
  }
  if {[info exists ::gameInfo(showMenu)] && !$::gameInfo(showMenu)} {
    $::dot_w configure -menu {}
  } else {
    $::dot_w configure -menu $barre
  }
}

################################################################################
### Shortcuts: Ctrl+C / Ctrl+V for games and positions
################################################################################

### (a selected text in an entry or a text keeps the usual copy)
proc ::moderne::menubar::texteSelectionne {} {
  set f [focus]
  if {$f eq {}} { return 0 }
  # typing in a field: its own copy / paste
  if {[winfo class $f] in {Entry TEntry TCombobox Spinbox TSpinbox}} { return 1 }
  if {[winfo class $f] eq "Text"} {
    if {![catch {$f tag ranges sel} r] && [llength $r]} { return 1 }
    if {![catch {$f cget -state} st] && $st eq "normal"} { return 1 }
  }
  return 0
}

proc ::moderne::menubar::copier {} {
  if {[texteSelectionne]} { return }
  ::pgn::copyPgn
}

proc ::moderne::menubar::coller {} {
  if {[texteSelectionne]} { return }
  ::moderne::menuclic::coller
}

proc ::moderne::menubar::raccourcis {w} {
  bind $w <Control-c> {::moderne::menubar::copier}
  bind $w <Control-v> {::moderne::menubar::coller}
  bind $w <Control-V> {::moderne::menubar::coller}
  bind $w <Control-C> {if {![::moderne::menubar::texteSelectionne]} copyFEN}
}

proc ::moderne::menubar::installer {} {
  if {![::moderne::actif]} { return }
  creer
  montrer
  # SCID's showMenubar: the Siby bar
  if {![llength [info commands ::showMenubarOrig]]} {
    rename ::showMenubar ::showMenubarOrig
    proc ::showMenubar {} { ::moderne::menubar::montrer }
  }
  # language change: labels of the bar
  if {![llength [info commands ::setLanguageMenusOrig]]} {
    rename ::setLanguageMenus ::setLanguageMenusOrig
    proc ::setLanguageMenus {args} {
      ::setLanguageMenusOrig {*}$args
      catch ::moderne::menubar::libelles
      catch ::moderne::rapport::veille
    }
  }
  raccourcis .main
  # game list: Ctrl+C copies the selected games
  if {[winfo exists .glistWin]} { glisteRaccourcis }
}

proc ::moderne::menubar::glisteRaccourcis {} {
  bind .glistWin <Control-c> {::moderne::menuclic::copierPgn [::moderne::menuclic::selection]}
  bind .glistWin <Control-v> {::moderne::menuclic::coller}
}

################################################################################
### Labels without their explanations in brackets: the explanation shows
### as a tooltip when the entry is hovered ("Save (replace the game)…"
### -> "Save…", tooltip "replace the game")
################################################################################

namespace eval ::moderne::menubar {
  variable infobulle   ;# infobulle(menu,index) = text
  array set infobulle {}
}

### Every entry of menu m (and of its submenus)
proc ::moderne::menubar::epurer {m} {
  variable infobulle
  if {![winfo exists $m]} { return }
  array unset infobulle "$m,*"
  set n [$m index end]
  if {$n ne "none"} {
    for {set i 0} {$i <= $n} {incr i} {
      set type [$m type $i]
      if {$type in {separator tearoff}} { continue }
      if {$type eq "cascade"} { catch {epurer [$m entrycget $i -menu]} }
      set l {}
      catch {set l [$m entrycget $i -label]}
      if {![regexp {\([^()]+\)} $l]} { continue }
      set notes {}
      foreach {- x} [regexp -all -inline {\(([^()]+)\)} $l] { lappend notes [string trim $x] }
      regsub -all {\s*\([^()]+\)} $l {} court
      set court [string trim $court]
      # (a label that is only a note stays as it is)
      if {$court eq {} || $court in {… ...}} { continue }
      $m entryconfigure $i -label $court
      set infobulle($m,$i) [join $notes " • "]
    }
  }
  bind $m <<MenuSelect>> {::moderne::menubar::survol %W}
  bind $m <Unmap> {+catch {wm withdraw .infobulleMenu}}
}

proc ::moderne::menubar::survol {m} {
  variable infobulle
  set b .infobulleMenu
  set i {}
  catch {set i [$m index active]}
  if {$i eq {} || $i eq "none" || ![info exists infobulle($m,$i)] || ![winfo ismapped $m]} {
    catch {wm withdraw $b}
    return
  }
  if {![winfo exists $b]} {
    toplevel $b -background [::moderne::c bordure] -padx 1 -pady 1
    wm overrideredirect $b 1
    catch {wm attributes $b -topmost 1}
    label $b.l -background [::moderne::c surface] -foreground [::moderne::c texte] -font font_Small \
        -padx 8 -pady 4 -justify left -wraplength 360
    pack $b.l
  }
  $b.l configure -text $infobulle($m,$i)
  set x [expr {[winfo rootx $m] + [winfo width $m] + 4}]
  set y [expr {[winfo rooty $m] + [$m yposition $i]}]
  update idletasks
  if {$x + [winfo reqwidth $b] > [winfo screenwidth $m]} {
    set x [expr {max(0, [winfo rootx $m] - [winfo reqwidth $b] - 4)}]
  }
  wm geometry $b +$x+$y
  wm deiconify $b
  raise $b
}

### Options › Sounds
### Options › Open .pgn and .si4 files with Siby (Windows only)
proc ::moderne::menubar::fichiersParDefaut {d} {
  if {!$::windowsOS} { return }
  $d add command -label [T "Ouvrir les fichiers .pgn et .si4 avec Siby…" "Open .pgn and .si4 files with Siby…"] \
      -command {::moderne::systeme::proposer 1}
}

### Options › Preload Toby (its tooltip: what it does, what it costs)
proc ::moderne::menubar::toby {d} {
  $d add checkbutton -label [T "Précharger Toby (Toby se charge au démarrage de Siby et répond tout de suite dans le Lab et les retransmissions ; environ 1 Go de mémoire, seulement si tu l'as utilisé ce mois-ci)" \
      "Preload Toby (Toby loads when Siby starts and answers at once in the Lab and the broadcasts; about 1 GB of memory, only if you used it this month)"] \
      -variable ::moderne::toby::precharger
}

proc ::moderne::menubar::sons {d} {
  $d add checkbutton -label [T "Sons" "Sounds"] -variable ::moderne::sons::actifs \
      -command {catch {::moderne::sons::jouer coup}}
}

### Saves the options now (Options › Save options), quietly: used to keep
### a setting at once (a layout, your rating) even if Siby is not closed
### normally
proc ::options.write {} {
  set cmd {}
  catch {set cmd [.menu.options entrycget [tr OptionsSave] -command]}
  if {$cmd eq {}} { return }
  set barre {}
  catch {set barre $::statusBar}
  uplevel #0 $cmd
  catch {set ::statusBar $barre}
}

################################################################################
### When something goes wrong (Yosha 2026-11-04): Help › Report a problem
### gathers in one file what is needed to understand it (Siby's logs, the
### computer, the engines, the open databases, the game on the board), and
### an unexpected error opens a Siby window offering that report instead of
### Tk's technical one. Nothing is sent: the file is made in Siby's folder
### and shown, the user sends it.
################################################################################

namespace eval ::moderne::rapport {
  variable vues {}   ;# errors already shown this session (each once)
  variable adresse support@tribychess.org
  variable avecPartie 0
  # direct sending (outils/rapports/: a Cloudflare Worker); empty: by e-mail
  variable service {}
  variable cle {}
  variable texte {}
}

proc ::moderne::rapport::T {fr en} { return [::moderne::tr $fr $en] }

### The computer and Siby, as text
proc ::moderne::rapport::systeme {{erreur {}} {pile {}}} {
  set t {}
  catch {append t "Siby $::sibyVersion\n"}
  append t "[clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}]\n"
  append t "OS: $::tcl_platform(os) $::tcl_platform(osVersion) $::tcl_platform(machine)\n"
  append t "Tcl/Tk: [info patchlevel] / [package provide Tk], [tk windowingsystem]\n"
  catch {append t "Screen: [winfo screenwidth .]x[winfo screenheight .], scaling [format %.2f [tk scaling]]\n"}
  catch {append t "Cores: [::moderne::toby::coeurs], NVIDIA: [::moderne::ajout::nvidia], free memory: [::moderne::niveau::memoireLibre] MB\n"}
  catch {append t "Language: $::language, theme: $::moderne::theme\n"}
  catch {append t "Settings folder: $::scidUserDir\n"}
  if {$erreur ne {}} { append t "\nError:\n$erreur\n\n$pile\n" }
  append t "\nDatabases open:\n"
  catch {
    for {set b 1} {$b <= [sc_base count total]} {incr b} {
      if {[sc_base inUse $b]} { append t "  $b: [sc_base filename $b] ([sc_base numGames $b] games)\n" }
    }
  }
  append t "\nEngines:\n"
  catch { foreach e $::engines(list) { append t "  [lindex $e 0]: [lindex $e 1]\n" } }
  append t "\nWindows open:\n"
  catch { foreach w [winfo children .] { if {[winfo toplevel $w] eq $w && [winfo ismapped $w]} { append t "  $w [wm title $w]\n" } } }
  return $t
}

### Makes the report (a .zip, else a folder) in Siby's folder and shows it;
### erreur/pile: the error that led to it, if any
### The report's window: the game on the board included or not (not by
### default: it may be private), then the report made
proc ::moderne::rapport::demander {{erreur {}} {pile {}}} {
  variable avecPartie
  set w .sibyRapport
  catch {destroy $w}
  toplevel $w -background [::moderne::c fond]
  wm withdraw $w
  wm title $w [T "Signaler un problème" "Report a problem"]
  wm resizable $w 0 0
  catch {wm transient $w .}
  set f [ttk::frame $w.f -padding {22 18 22 14}]
  pack $f -fill both -expand 1
  set avecPartie 0
  ttk::label $f.lt -text [T "Ce qui s'est passé" "What happened"]
  text $f.t -width 56 -height 5 -wrap word -font font_Regular -borderwidth 0 -highlightthickness 1 \
      -background [::moderne::c champ] -foreground [::moderne::c texte] -insertbackground [::moderne::c texte] \
      -highlightcolor [::moderne::c accent] -highlightbackground [::moderne::c bordure] -padx 6 -pady 4
  pack $f.lt -anchor w
  pack $f.t -anchor w -fill x -pady {4 10}
  ttk::checkbutton $f.partie -variable ::moderne::rapport::avecPartie -text [T "Inclure la partie sur l'échiquier" "Include the game on the board"]
  pack $f.partie -anchor w
  ttk::frame $f.b
  pack $f.b -anchor e -pady {18 0}
  variable choix {}
  ttk::button $f.b.ok -text [T "Créer le rapport" "Make the report"] -style Accent.TButton -command {set ::moderne::rapport::choix ok}
  ttk::button $f.b.non -text [T Annuler Cancel] -command {set ::moderne::rapport::choix non}
  pack $f.b.ok $f.b.non -side left -padx {8 0}
  bind $w <Control-Return> {set ::moderne::rapport::choix ok}
  bind $w <Escape> {set ::moderne::rapport::choix non}
  wm protocol $w WM_DELETE_WINDOW {set ::moderne::rapport::choix non}
  catch {::moderne::repeindre $w}
  update idletasks
  catch {placeWinOverParent $w .}
  wm deiconify $w
  catch {focus -force $f.t}
  catch {grab $w}
  # (the window closed some other way, e.g. the rescue box's Unblock:
  # cancelled, never an error)
  bind $w <Destroy> {if {"%W" eq ".sibyRapport" && $::moderne::rapport::choix eq {}} { set ::moderne::rapport::choix non }}
  vwait ::moderne::rapport::choix
  catch {grab release $w}
  variable texte {}
  catch {set texte [string trim [$f.t get 1.0 end]]}
  catch {destroy $w}
  if {$choix ne "ok"} { return {} }
  return [creer $erreur $pile $avecPartie]
}

### The Windows (or Linux) user name and home folder replaced in the
### report's text files: they are in the paths of the logs and settings
proc ::moderne::rapport::anonymiser {d} {
  set carte {}
  set maison {}
  catch {set maison [file normalize ~]}
  if {[string length $maison] > 3} { lappend carte $maison <home> [file nativename $maison] <home> }
  foreach v {USERNAME USER} {
    if {[info exists ::env($v)] && [string length $::env($v)] >= 3} { lappend carte $::env($v) <utilisateur> ; break }
  }
  if {![llength $carte]} { return }
  foreach f [glob -nocomplain -directory $d -types f *] {
    catch {
      set c [open $f r] ; fconfigure $c -encoding utf-8 ; set t [read $c] ; close $c
      set t2 [string map -nocase $carte $t]
      if {$t2 ne $t} { set c [open $f w] ; fconfigure $c -encoding utf-8 ; puts -nonewline $c $t2 ; close $c }
    }
  }
}

proc ::moderne::rapport::creer {{erreur {}} {pile {}} {avecPartie 1}} {
  set nom "Siby-[T rapport report]-[clock format [clock seconds] -format %Y%m%d-%H%M%S]"
  set base [file join $::scidUserDir [T rapports reports]]
  # (two reports in the same second: each its own name)
  set k 1
  set racine $nom
  while {[file exists [file join $base $nom]] || [file exists [file join $base $nom.zip]]} { set nom "$racine-[incr k]" }
  set d [file join $base $nom]
  if {[catch {file mkdir $d} err]} {
    tk_messageBox -icon error -title Siby -message [T "Rapport impossible à créer." "The report could not be made."] -detail $err
    return
  }
  # Siby's logs (the lines still waiting written first)
  catch ::moderne::journalVider
  catch {sc_ecrire_fond attendre 2000}
  foreach f {siby.log siby.log.1 review.log lenteurs.log ouverture.log coups.log toby_annotation.log bibliotheque.log
             gaby-update/telechargements.log config/engines.dat config/options.dat} {
    set src [file join $::scidUserDir {*}[split $f /]]
    if {[file exists $src]} { catch {file copy -force $src [file join $d [file tail $f]]} }
  }
  variable texte
  catch {
    set c [open [file join $d systeme.txt] w] ; fconfigure $c -encoding utf-8
    if {$texte ne {}} { puts $c "What happened (user):\n$texte\n" }
    puts $c [systeme $erreur $pile] ; close $c
  }
  # the game on the board (what was being done), when asked
  if {$avecPartie} {
    catch {
      set c [open [file join $d partie.pgn] w] ; fconfigure $c -encoding utf-8
      puts $c [sc_game pgn -width 80] ; close $c
    }
  }
  anonymiser $d
  # one .zip to send (tar on Windows 10 and 11, zip on Linux and macOS)
  set zip "$d.zip"
  set ok 0
  catch {
    if {$::windowsOS} {
      set tar [file join $::env(SystemRoot) System32 tar.exe]
      exec $tar -a -c -f $zip -C $base $nom
    } else {
      exec sh -c "cd [list $base] && zip -q -r [list $nom.zip] [list $nom]"
    }
    set ok [file exists $zip]
  }
  if {$ok} { catch {file delete -force $d} ; set cible $zip } else { set cible $d }
  journal "Siby report: $cible"
  variable adresse
  variable service
  # direct sending when the service exists (and the report is one file)
  if {$service ne {} && $ok} {
    set r [tk_messageBox -icon info -title Siby -boutons [list envoyer [T "Envoyer" "Send"] \
        montrer [T "Montrer le fichier" "Show the file"] ok [T Annuler Cancel]] \
        -message [T "Rapport prêt." "Report ready."] -detail [file nativename $cible]]
    if {$r eq "envoyer"} {
      if {[envoyer $cible]} {
        tk_messageBox -icon info -title Siby -message [T "Rapport envoyé. Merci !" "Report sent. Thank you!"]
        return $cible
      }
      # (not sent: by e-mail instead)
    } else {
      if {$r eq "montrer"} { montrer $cible }
      return $cible
    }
  }
  set r [tk_messageBox -icon info -title Siby -boutons [list mail [T "Envoyer par e-mail" "Send by e-mail"] \
      montrer [T "Montrer le fichier" "Show the file"] ok OK] \
      -message [T "Rapport prêt." "Report ready."] -detail "[file nativename $cible]\n$adresse"]
  if {$r eq "mail"} {
    # (an e-mail ready to send; the file is shown to be dragged into it:
    # a mailto link cannot attach it)
    set v {} ; catch {set v $::sibyVersion}
    set sujet "Siby $v - [T rapport report] [file tail $cible]"
    set corps [T "Ce qui s'est passé :\n$texte\n\n(Fichier joint : [file tail $cible])" "What happened:\n$texte\n\n(Attached file: [file tail $cible])"]
    set lien "mailto:$adresse?subject=[encoder $sujet]&body=[encoder $corps]"
    # (the address and the subject copied in any case: many people have no
    # mail program, only a mail website; Yosha 2026-11-04)
    catch {clipboard clear ; clipboard append "$adresse"}
    if {[messagerie]} {
      # (on Windows not through "cmd /c start": its "&" splits the command)
      catch {
        if {$::windowsOS} {
          exec rundll32.exe url.dll,FileProtocolHandler $lien &
        } elseif {$::macOS} {
          exec open $lien &
        } else {
          exec xdg-open $lien &
        }
      }
    } else {
      tk_messageBox -icon info -title Siby -message [T "Adresse copiée : $adresse" "Address copied: $adresse"] \
          -detail [T "Objet : $sujet\nFichier à joindre : [file tail $cible]" "Subject: $sujet\nFile to attach: [file tail $cible]"]
    }
    set r montrer
  }
  if {$r eq "montrer"} { montrer $cible }
  return $cible
}

### The report's file shown in the system's file manager
proc ::moderne::rapport::montrer {cible} {
  catch {
    if {$::windowsOS} {
      exec explorer.exe /select,[file nativename $cible] &
    } elseif {$::macOS} {
      exec open -R $cible &
    } else {
      exec xdg-open [file dirname $cible] &
    }
  }
}

### Direct sending to the reports service (curl, in the background, the
### window kept alive): 1 if received
proc ::moderne::rapport::envoyer {cible} {
  variable service
  variable cle
  variable texte
  set v {} ; catch {set v $::sibyVersion}
  set langue {} ; catch {set langue $::language}
  set cmd [list curl -sS --max-time 60 -A "Siby $v" -H "X-Siby-Cle: $cle" \
      -F "fichier=@$cible;type=application/zip" -F "message=<-" -F "version=$v" -F "langue=$langue" $service]
  variable reponse {}
  variable fini 0
  if {[catch {open "|$cmd 2>@1" r+} c]} { journal "Siby report: not sent ($c)" ; return 0 }
  # (the message on curl's standard input: any text, quotes included)
  fconfigure $c -encoding utf-8 -blocking 0
  puts -nonewline $c $texte
  catch {chan close $c write}
  fileevent $c readable [list apply {{c} {
    append ::moderne::rapport::reponse [read $c]
    if {[eof $c]} { catch {close $c} ; set ::moderne::rapport::fini 1 }
  }} $c]
  catch {::moderne::nsb::annonce [T "Envoi du rapport…" "Sending the report…"] -1}
  vwait ::moderne::rapport::fini
  catch {::moderne::nsb::finAnnonce}
  journal "Siby report: sent to the service: [string range $reponse 0 200]"
  return [string match {*"ok":true*} $reponse]
}

proc ::moderne::rapport::journal {texte} { catch {::moderne::journal $texte} }

### Is there a mail program for mailto links? (Windows: the user's choice
### in the registry, or a handler registered for mailto; elsewhere: assumed)
proc ::moderne::rapport::messagerie {} {
  if {!$::windowsOS} { return 1 }
  if {[catch {package require registry}]} { return 0 }
  set prog {}
  catch {set prog [registry get {HKEY_CURRENT_USER\Software\Microsoft\Windows\Shell\Associations\UrlAssociations\mailto\UserChoice} ProgId]}
  if {$prog eq {}} {
    catch {set prog [registry get {HKEY_CLASSES_ROOT\mailto\shell\open\command} {}]}
  }
  # (Windows' own "Mail" app, removed from Windows 11: a dead choice)
  return [expr {$prog ne {} && ![string match -nocase *windowsmail* $prog]}]
}

### Text for a mailto link (percent-encoded UTF-8)
proc ::moderne::rapport::encoder {t} {
  set r {}
  foreach o [split [encoding convertto utf-8 $t] {}] {
    scan $o %c c
    if {($c >= 48 && $c <= 57) || ($c >= 65 && $c <= 90) || ($c >= 97 && $c <= 122) || $o in {- _ . ~}} {
      append r $o
    } else {
      append r [format %%%02X $c]
    }
  }
  return $r
}

### An unexpected error: written to siby.log, then a Siby window (once per
### error and session) offering the report
### Grabs, busy cursor and progress released (after an error, or by the
### Ctrl+Shift+Pause key)
proc ::moderne::rapport::debloquer {} {
  foreach g [grab current] { catch {grab release $g} }
  catch {unbusyCursor .}
  catch {doBusyCursor . 0}
  catch {set ::scid_busycursorState 0}
  # (a Siby box waiting for an answer, hidden behind a window: shown)
  foreach b [winfo children .] {
    if {[string match .sibyMessage* $b] && [winfo exists $b.f]} { catch {wm deiconify $b ; raise $b} }
  }
}

### Escape held 2 seconds: unblock or quit, even when a window holds the
### grab and nothing else answers (Yosha 2026-11-04: Ctrl+Alt+Del was the
### only way out)
namespace eval ::moderne::rapport {
  variable echap {}       ;# when Escape was pressed (ms)
  variable echapFin {}    ;# its release, waited for (autorepeat)
}
proc ::moderne::rapport::echapAppui {} {
  variable echap
  variable echapFin
  catch {after cancel $echapFin}
  if {$echap ne {}} { return }
  # (a timer, not the key's autorepeat: some systems do not repeat it)
  set echap [clock milliseconds]
  after 2000 [list ::moderne::rapport::echapLongue $echap]
}
proc ::moderne::rapport::echapLongue {debut} {
  variable echap
  variable arme
  if {$echap eq $debut} { set arme 1 }
}
proc ::moderne::rapport::echapRelache {} {
  variable echapFin
  # (X11 autorepeat sends a release before each press; the box comes once
  # the key is really released, else the held key would close it)
  set echapFin [after 150 ::moderne::rapport::echapFini]
}
proc ::moderne::rapport::echapFini {} {
  variable echap {}
  variable arme
  if {[info exists arme] && $arme} { set arme 0 ; secours }
}
bind all <KeyPress-Escape> {+::moderne::rapport::echapAppui}
bind all <KeyRelease-Escape> {+::moderne::rapport::echapRelache}

### Watchdog (sc_veille, in C): Siby's main part silent for 20 s (a long
### calculation, a loop), a box asks: stop the calculation, quit, wait.
### On Linux the box is a second Siby process running veille.tcl.
proc ::moderne::rapport::veille {{secondes 20}} {
  if {![llength [info commands sc_veille]]} { return }
  set titre [T "Siby ne répond plus" "Siby is not responding"]
  set arreter [T "Arrêter le calcul" "Stop the calculation"]
  set quitter [T "Quitter Siby" "Quit Siby"]
  set attendre [T "Attendre" "Wait"]
  set aide {}
  if {$::windowsOS == 0} {
    catch {
      set aide [file join $::scidUserDir veille.tcl]
      set c [open $aide w] ; fconfigure $c -encoding utf-8
      puts $c [string map [list @TITRE@ [list $titre] @ARRETER@ [list $arreter] @QUITTER@ [list $quitter] @ATTENDRE@ [list $attendre]] {
# Siby's watchdog box (written by Siby; exit 0 stop, 1 quit, 2 wait)
wm withdraw .
set w .v
toplevel $w -class SibyVeille -background #262421 -padx 18 -pady 14
wm title $w Siby
catch {wm attributes $w -topmost 1}
wm protocol $w WM_DELETE_WINDOW {exit 2}
label $w.t -text @TITRE@ -background #262421 -foreground #e8e6e3 -font {TkDefaultFont 11 bold}
frame $w.b -background #262421
button $w.b.a -text @ARRETER@ -command {exit 0} -background #3692e7 -foreground white -relief flat -padx 10 -pady 4
button $w.b.q -text @QUITTER@ -command {exit 1} -background #3a3835 -foreground #e8e6e3 -relief flat -padx 10 -pady 4
button $w.b.w -text @ATTENDRE@ -command {exit 2} -background #3a3835 -foreground #e8e6e3 -relief flat -padx 10 -pady 4
pack $w.t -anchor w -pady {0 12}
pack $w.b
pack $w.b.a $w.b.q $w.b.w -side left -padx 4
bind $w <Return> {exit 0}
bind $w <Escape> {exit 2}
update idletasks
wm geometry $w +[expr {([winfo screenwidth $w] - [winfo reqwidth $w]) / 2}]+[expr {[winfo screenheight $w] / 3}]
focus -force $w.b.a
}]
      close $c
    }
  }
  catch {sc_veille journal [file join $::scidUserDir siby.log]}
  catch {sc_veille demarrer $secondes $titre $arreter $quitter $attendre $aide}
}

### After the watchdog's question, as soon as Siby's scripts run again (in
### the middle of the one that was stuck): their stack in siby.log, for the
### problem report (the C command running is already noted by the watchdog)
proc ::moderne::rapport::gel {} {
  variable gels
  set pile {}
  for {set i [expr {[info level] - 1}]} {$i > 0} {incr i -1} {
    set l [info level $i]
    if {[string match "*::rapport::gel*" $l]} { continue }
    lappend pile [string range $l 0 200]
  }
  if {![llength $pile]} { set pile [list "(event loop)"] }
  set texte "Siby froze: script stack\n    [join $pile "\n    "]"
  journal $texte
  lappend gels $texte
}
################################################################################
### Databases cut off while written (Yosha 2026-11-05): the C side leaves a
### marker in bases_ecrites/ at a database's first write; quitting normally
### deletes them. Markers found at the start: those databases are offered
### a check when they are open (now or later), then a repair (the damaged
### games marked deleted). A small database is checked without asking (it
### takes a moment), a large one when the user says so; never repaired
### without asking.
################################################################################

namespace eval ::moderne::integrite {
  variable aVerifier {}     ;# paths (without extension) of the databases to check
  variable sansQuestion 200000  ;# databases smaller than this: checked without asking
}
proc ::moderne::integrite::T {fr en} { return [::moderne::tr $fr $en] }
proc ::moderne::integrite::dossier {} { file join $::scidUserDir bases_ecrites }
proc ::moderne::integrite::cle {f} { file rootname [file normalize $f] }

### At the start: the markers of last time read, the markers of this session on
proc ::moderne::integrite::demarrer {} {
  variable aVerifier
  set aVerifier {}
  set d [dossier]
  foreach m [glob -nocomplain -directory $d *.txt] {
    catch {
      set c [open $m] ; fconfigure $c -encoding utf-8 ; set f [string trim [read $c]] ; close $c
      # (a PGN file: Siby works on a copy and writes the file in one go,
      # it cannot be cut off)
      if {[regexp -nocase {\.pgn(\.gz)?$} $f]} { file delete $m ; continue }
      if {$f ne {}} { lappend aVerifier [list [cle $f] $m] }
    }
  }
  catch {file mkdir $d}
  catch {sc_veille bases [file nativename $d]}
  # (the databases open at the start)
  after 4000 ::moderne::integrite::ouvertes
}

proc ::moderne::integrite::ouvertes {} {
  for {set i 1} {$i <= [sc_base count total]} {incr i} {
    if {$i != [sc_info clipbase] && [sc_base inUse $i]} { catch {ouverte $i} }
  }
}

### A database just opened (sc_base open): to check?
proc ::moderne::integrite::ouverte {b} {
  variable aVerifier
  set k [cle [sc_base filename $b]]
  set i [lsearch -index 0 -exact $aVerifier $k]
  if {$i < 0} { return }
  set e [lindex $aVerifier $i]
  set aVerifier [lreplace $aVerifier $i $i]
  after idle [list ::moderne::integrite::proposer $b [lindex $e 1]]
}

proc ::moderne::integrite::nom {b} { ::moderne::nomBase [sc_base filename $b] }

proc ::moderne::integrite::proposer {b marqueur} {
  if {![sc_base inUse $b]} { return }
  # (the start's other question first: the games to restore; a check
  # under it kept its buttons from answering, Yosha 2026-11-09)
  # (nor during a game: the question came as the user resigned, Yosha
  # 2026-11-09)
  if {![info exists ::moderne::reprise::fini] || !$::moderne::reprise::fini || [winfo exists .verifBase] ||
      [winfo exists .serGameWin]} {
    after 3000 [list ::moderne::integrite::proposer $b $marqueur]
    return
  }
  # a small database (My Siby games…): checked at once, without asking (a
  # fraction of a second); only damaged games are said
  if {[sc_base numGames $b] < $::moderne::integrite::sansQuestion} {
    set abimees [verifier $b]
  } else {
    set r [tk_messageBox -parent . -icon warning -title Siby -default verifier \
        -boutons [list verifier [T "Vérifier" "Check"] cancel [T "Plus tard" "Later"]] \
        -message [T "« [nom $b] » n'a pas été fermée normalement. La vérifier ?" \
                    "« [nom $b] » was not closed normally. Check it?"]]
    # (later: asked again at the next start)
    if {$r ne "verifier"} { return }
    set abimees [verifier $b]
  }
  if {$abimees eq "interrompu"} { return }
  if {![llength $abimees]} {
    catch {file delete $marqueur}
    # (a check asked for: its answer; a small one done alone: nothing said)
    if {[sc_base numGames $b] >= $::moderne::integrite::sansQuestion} {
      tk_messageBox -parent . -icon info -title Siby -message [T "« [nom $b] » : aucune partie abîmée." "« [nom $b] »: no damaged game."]
    }
    return
  }
  set n [llength $abimees]
  set r [tk_messageBox -parent . -icon warning -title Siby -default reparer \
      -boutons [list reparer [T "Réparer" "Repair"] cancel [T "Plus tard" "Later"]] \
      -message [T "[expr {$n == 1 ? "1 partie abîmée" : "$n parties abîmées"}] dans « [nom $b] »." \
                  "[expr {$n == 1 ? "1 damaged game" : "$n damaged games"}] in « [nom $b] »."] \
      -detail [T "Parties : [join [lrange $abimees 0 19] {, }][expr {$n > 20 ? " …" : ""}]" "Games: [join [lrange $abimees 0 19] {, }][expr {$n > 20 ? " …" : ""}]"]]
  if {$r ne "reparer"} { return }
  reparer $b $abimees
  catch {file delete $marqueur}
}

### Numbers of the damaged games of database b ("interrompu": stopped)
proc ::moderne::integrite::verifier {b} {
  set courante [sc_base current]
  set w .verifBase
  catch {destroy $w}
  toplevel $w -background [::moderne::c fond]
  wm title $w Siby
  catch {wm transient $w .}
  ttk::frame $w.f -padding 14
  pack $w.f -fill both
  ttk::label $w.f.t -text [T "Vérification de « [nom $b] »…" "Checking « [nom $b] »…"]
  canvas $w.f.p -width 320 -height 8 -highlightthickness 0 -borderwidth 0 -background [::moderne::c surface2]
  $w.f.p create rectangle 0 0 0 8 -fill [::moderne::c accent] -outline {} -tags bar
  variable arrete 0
  ttk::button $w.f.s -text [T "Arrêter" "Stop"] -command {set ::moderne::integrite::arrete 1 ; sc_progressBar}
  pack $w.f.t -anchor w
  pack $w.f.p -pady 8
  pack $w.f.s -anchor e
  update idletasks
  if {$b != $courante} { sc_base switch $b }
  sc_progressBar $w.f.p bar 320 8
  set code [catch {sc_base check all} res]
  if {$b != $courante} { catch {sc_base switch $courante} }
  catch {destroy $w}
  variable arrete
  if {$arrete} { return interrompu }
  if {!$code} { return {} }
  set l {}
  foreach x [regexp -all -inline {Game ([0-9]+):} $res] {
    if {[string is integer -strict $x]} { lappend l $x }
  }
  return [lsort -integer -unique $l]
}

### The damaged games marked deleted (they stay in the file until compacted)
proc ::moderne::integrite::reparer {b abimees} {
  set courante [sc_base current]
  if {$b != $courante} { sc_base switch $b }
  foreach g $abimees { catch {sc_game flag delete $g 1} }
  if {$b != $courante} { catch {sc_base switch $courante} }
  catch {::windows::gamelist::Refresh}
  journal "Siby: [llength $abimees] damaged games marked deleted in [sc_base filename $b]"
}
proc ::moderne::integrite::journal {t} { catch {::moderne::journal $t} }

### Quitting normally: nothing cut off
proc ::moderne::integrite::quitter {} {
  catch {sc_veille bases {}}
  foreach m [glob -nocomplain -directory [dossier] *.txt] { catch {file delete $m} }
}

### A database closed: its marker (from this session) deleted
proc ::moderne::integrite::fermee {f} {
  foreach m [glob -nocomplain -directory [dossier] *.txt] {
    catch {
      set c [open $m] ; fconfigure $c -encoding utf-8 ; set g [string trim [read $c]] ; close $c
      if {[cle $g] eq [cle $f]} {
        variable aVerifier
        # (a marker of last time: kept, the database not checked yet)
        if {[lsearch -index 1 -exact $aVerifier $m] < 0} { file delete $m }
      }
    }
  }
}

after idle {after 500 {catch ::moderne::integrite::demarrer}}

# (the system's file and colour dialogs: Siby's loop may not run meanwhile)
foreach d {tk_getOpenFile tk_getSaveFile tk_chooseDirectory tk_chooseColor ::moderne::messageNatif} {
  if {[llength [info commands $d]] && ![llength [info commands ::moderne::rapport::orig_[string trimleft $d :]]]} {
    rename $d ::moderne::rapport::orig_[string trimleft $d :]
    proc $d {args} [string map [list @O@ ::moderne::rapport::orig_[string trimleft $d :]] {
      catch {sc_veille pause}
      try { return [@O@ {*}$args] } finally { catch {sc_veille reprise} }
    }]
  }
}
after idle {after 2000 ::moderne::rapport::veille}
# (a start that went well: the safe start's count cleared, see start.tcl)
after idle {after 12000 {catch {file delete [file join $::scidUserDir demarrage.txt]}}}

proc ::moderne::rapport::secours {} {
  variable secoursOuvert
  if {[info exists secoursOuvert] && $secoursOuvert} { return }
  set secoursOuvert 1
  journal "Siby: Escape held, rescue box"
  debloquer
  # (a search still running: stopped)
  catch {sc_progressBar}
  set r ok
  catch {set r [tk_messageBox -icon warning -title Siby -default debloquer \
      -boutons [list debloquer [T "Débloquer" "Unblock"] quitter [T "Quitter Siby" "Quit Siby"] cancel [T "Annuler" "Cancel"]] \
      -message [T "Siby est bloqué ?" "Is Siby stuck?"]]}
  set secoursOuvert 0
  switch -- $r {
    debloquer {
      debloquer
      # (the windows in a bad state: the layout made again, Yosha 2026-11-11)
      catch {::moderne::disposition::refaire}
      catch {updateBoard}
    }
    quitter { journal "Siby: quit from the rescue box" ; exit 0 }
  }
}

proc ::moderne::rapport::erreur {err} {
  variable vues
  set pile {}
  catch {set pile $::errorInfo}
  journal "Siby ERROR: $err\n$pile"
  # (an error in the middle of a task may have left a grab and the busy
  # cursor: nothing answered any more, Yosha 2026-11-04)
  debloquer
  set cle [string range $err 0 200]
  if {$cle in $vues} { return }
  lappend vues $cle
  if {[llength [info commands ::moderne::message]] == 0} { ::tk::dialog::error::bgerror $err ; return }
  set r [tk_messageBox -icon error -title Siby -boutons [list rapport [T "Faire un rapport" "Make a report"] ok [T "Continuer" "Continue"]] \
      -message [T "Siby a rencontré un problème." "Siby ran into a problem."] -detail [string range $err 0 300]]
  if {$r eq "rapport"} { demander $err $pile }
}


################################################################################
### Options › Back to the default settings… (Yosha 2026-11-05): the settings,
### the layouts and the windows' sizes back to Siby's defaults; the
### databases, the games, Gaby and the engines stay. The settings file is
### kept aside (options.dat.avant-defaut-<date>), as the safe start does,
### and Siby starts again.
################################################################################

namespace eval ::moderne::reglagesDefaut {
  variable demande 0
  # what is the user's, not a setting: kept (Yosha 2026-11-05: the binders
  # and the databases added were lost)
  variable gardes {
    ::moderne::mesBases ::moderne::basesRetirees ::moderne::mesbases::groupes
    ::moderne::mesbases::dossiers ::moderne::mesbases::replies
    ::moderne::mesbases::ordreDossiers ::moderne::mesbases::suivis
    ::moderne::mesbases::compacts ::moderne::mesbases::ouvertures
    ::moderne::mesbases::apercus ::moderne::fichierReference ::moderne::refRefusees
    ::moderne::cadenas ::moderne::sansCadenas ::moderne::gaby::fichier
    ::moderne::syzygy::chemin ::moderne::profilNom ::moderne::profilLichess
    ::moderne::profilChesscom ::moderne::profilAutres ::moderne::profilRepB
    ::moderne::profilRepN ::moderne::alterego::favoris ::moderne::alterego::recents
  }
}

proc ::moderne::reglagesDefaut::demander {} {
  set r [tk_messageBox -parent . -icon question -type okcancel -default cancel -title Siby \
      -message [::moderne::tr "Revenir aux réglages par défaut ?" "Back to the default settings?"]]
  if {$r ne "ok"} { return }
  variable demande 1
  # (the usual quit: the games to save are asked about; a quit cancelled
  # cancels this too)
  ::file::Exit
  set demande 0
}

### At the very end of the quit: the settings file put aside, then Siby
### started again
proc ::moderne::reglagesDefaut::auQuitter {} {
  variable demande
  if {!$demande} { return }
  set f [scidConfigFile options]
  if {[file exists $f]} {
    set copie "$f.avant-defaut-[clock format [clock seconds] -format %Y%m%d-%H%M%S]"
    catch {file rename -force $f $copie}
    catch {::moderne::journal "Back to the default settings (the old ones in $copie)"}
  }
  # (a new settings file with only what is the user's)
  variable gardes
  catch {
    # (the system's encoding, as Options › Save and the reading at start)
    set c [open $f w]
    puts $c "# Siby: back to the default settings; the user's databases, binders, profile... kept"
    foreach v $gardes {
      if {![info exists $v]} { continue }
      set ns [namespace qualifiers $v]
      if {$ns ne {}} { puts $c "namespace eval $ns {}" }
      puts $c "set $v [list [set $v]]"
    }
    close $c
  }
  catch {close $c}
  if {[info exists ::env(SIBY_SANS_REDEMARRAGE)]} { return }
  if {$::windowsOS} {
    catch {exec [::moderne::systeme::exe] &}
  } else {
    catch {exec [info nameofexecutable] [file normalize $::argv0] &}
  }
}
