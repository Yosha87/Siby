###
### Siby: "My databases" view, like ChessBase's: a tile per database (the
### open ones, the recent ones, the ones added by hand), with the number
### of games. Double click: open (or switch to it). Right click: open,
### close, search in it, use as the reference database (opening library),
### remove the tile, delete the database.
###
### ::moderne::mesBases (saved): databases added by hand (.si4 paths);
### ::moderne::basesRetirees (saved): tiles removed (not shown again even
### if the database is in the recent files).
###

namespace eval ::moderne::mesbases {
  variable w .mesBasesWin
  variable choisie {}
}
foreach {_v _d} {mesBases {} basesRetirees {}} {
  if {![info exists ::moderne::$_v]} { set ::moderne::$_v $_d }
}
unset _v _d

proc ::moderne::mesbases::T {fr en} { return [::moderne::tr $fr $en] }

### .si4 path of a database name or slot (a PGN file keeps its name)
proc ::moderne::mesbases::chemin {f} {
  set f [file normalize $f]
  if {[estPgn $f]} { return $f }
  if {[file extension $f] ne ".si4"} { set f "$f.si4" }
  return $f
}

proc ::moderne::mesbases::estPgn {f} {
  expr {[string match -nocase *.pgn $f] || [string match -nocase *.pgn.gz $f]}
}

### Number of games of a closed PGN file: counted from its "[Event" lines
### (files up to 30 MB, about a quarter of a second), kept while the file
### does not change; "PGN" for a larger file
proc ::moderne::mesbases::nbPgn {f} {
  variable nbPgnCache
  if {[catch {list [file mtime $f] [file size $f]} cle]} { return PGN }
  if {[info exists nbPgnCache($f)] && [lrange $nbPgnCache($f) 0 1] eq $cle} { return [lindex $nbPgnCache($f) 2] }
  if {[lindex $cle 1] > 30000000 || [string match -nocase *.gz $f]} { return PGN }
  if {[catch {
    set c [open $f rb]
    set t [read $c]
    close $c
    set n [regexp -all -line {^\[Event } $t]
  }]} { return PGN }
  set nbPgnCache($f) [list {*}$cle $n]
  return $n
}

### Databases shown: open, added by hand, recent (minus the removed ones)
proc ::moderne::mesbases::liste {} {
  set l {}
  for {set i 1} {$i <= [sc_base count total]} {incr i} {
    if {![sc_base inUse $i] || $i == [sc_info clipbase] || [catch {sc_base filename $i} f]} { continue }
    # (not the database of the broadcast games)
    if {[file tail $f] eq "Siby live"} { continue }
    if {[file exists "$f.si4"]} { lappend l [chemin $f] } elseif {[estPgn $f] && [file exists $f]} { lappend l [chemin $f] }
  }
  foreach f $::moderne::mesBases { lappend l [chemin $f] }
  # My Siby games: always there (created empty by creerMesParties)
  set j [file join $::sibyDocsDir "Siby games"]
  if {[file exists $j.si4]} { lappend l [chemin $j] }
  if {[info exists ::recentFiles(data)]} {
    foreach f $::recentFiles(data) {
      if {[string match -nocase *.si4 $f] || [estPgn $f]} { lappend l [chemin $f] }
    }
  }
  set res {}
  foreach f $l {
    if {$f in $res || ![file exists $f] || $f in $::moderne::basesRetirees} { continue }
    # (a player's online games: the preparation's own database)
    # (except the user's own, My profile's: "My online games")
    if {[catch {::moderne::enligne::estBaseEnLigne $f} oui] == 0 && $oui
        && ([catch {::moderne::enligne::estMaBase $f} mien] || !$mien)} { continue }
    lappend res $f
  }
  return $res
}

### "My Siby games" (Siby games, where the games against Toby and
### the Alter Egos are saved) created empty once, after the start, so that
### it is in My databases from the first day; the current database is kept
proc ::moderne::mesbases::creerMesParties {} {
  set j [file join $::sibyDocsDir "Siby games"]
  if {[file exists $j.si4]} { return }
  set courante [sc_base current]
  if {![catch {sc_base create $j} b]} { catch {sc_base close $b} }
  catch {sc_base switch $courante}
}
after 5000 {catch ::moderne::mesbases::creerMesParties}

### Slot of the database if it is open, else 0
proc ::moderne::mesbases::slot {f} {
  set r [expr {[estPgn $f] ? [file normalize $f] : [file rootname $f]}]
  for {set i 1} {$i <= [sc_base count total]} {incr i} {
    if {[sc_base inUse $i] && [file normalize [sc_base filename $i]] eq $r} { return $i }
  }
  return 0
}

### Reference database (saved file): the one chosen in the opening library
### or with "Use as reference"; Gaby otherwise
if {![info exists ::moderne::fichierReference]} { set ::moderne::fichierReference {} }

### Slot of the reference database, opened if needed (without leaving the
### current game; one try per file and session); otherwise the largest open
### database (neither the clipboard nor "Siby live"); 0 if none
### attendre 0: while the file is still read in the background (sc_base
### prepa), no waiting: 0 is returned and the opening comes by itself once
### the reading is over (referencePrete). The Lab and the library ask this
### way: opening Gaby waited for that reading and froze the screen 15 s on
### Linux, 22 s on Windows, just after starting (night battery 2026-11-06)
proc ::moderne::mesbases::baseReference {{attendre 1}} {
  variable essaye
  set candidats [list $::moderne::fichierReference]
  catch {lappend candidats [::moderne::gaby::trouverFichier]}
  foreach f $candidats {
    if {$f eq {}} { continue }
    set f [chemin $f]
    set b [slot $f]
    if {$b} { return $b }
    if {!$attendre && [file exists $f] && ![info exists essaye($f)] && [enLecture $f]} {
      attendreReference
      return 0
    }
    if {[file exists $f] && ![info exists essaye($f)]} {
      # (tests: who waits for a reference still being read)
      if {[info exists ::env(SIBY_TRACE_REF)] && [enLecture $f]} { catch {puts "REFERENCE ATTENDUE PAR [info level -1]"} }
      set essaye($f) 1
      set c [sc_base current]
      set ::file::discret 1
      catch {::file::Open [file rootname $f]}
      set ::file::discret 0
      catch {::file::SwitchToBase $c}
      set b [slot $f]
      if {$b} { return $b }
    }
  }
  set live {}
  catch {set live [file normalize [file join $::sibyDocsDir "Siby live"]]}
  set b 0
  set max -1
  for {set i 1} {$i <= [sc_base count total]} {incr i} {
    if {$i == [sc_info clipbase] || ![sc_base inUse $i]} { continue }
    if {[file normalize [sc_base filename $i]] eq $live} { continue }
    if {[sc_base numGames $i] > $max} { set max [sc_base numGames $i] ; set b $i }
  }
  return $b
}

### Is file f (a reference candidate) still being read in the background?
proc ::moderne::mesbases::enLecture {f} {
  if {[catch {sc_base prepa} e]} { return 0 }
  return [expr {[lindex $e 0] eq "encours" && [lindex $e 1] eq [file rootname [fullname $f]]}]
}

### The reference read in the background: opened once the reading is over
### (instantly then), and the library shown on it
proc ::moderne::mesbases::attendreReference {} {
  variable attenteRef
  if {[info exists attenteRef] && $attenteRef} { return }
  set attenteRef 1
  catch {::moderne::direct::annonceBreve [T "Gaby se charge…" "Gaby is loading…"]}
  after 200 ::moderne::mesbases::referencePrete
}
proc ::moderne::mesbases::referencePrete {} {
  variable attenteRef
  set f {}
  catch {set f [fichierRef]}
  if {$f ne {} && [enLecture $f]} { after 200 ::moderne::mesbases::referencePrete ; return }
  set attenteRef 0
  set b 0
  catch {set b [baseReference]}
  if {!$b} { return }
  # (the preparation, opened meanwhile, takes it as its reference and, if
  # no database was chosen there by hand, as its database)
  catch {
    if {[winfo exists $::moderne::prepa::w]} {
      ::moderne::prepa::refAuto
      if {![info exists ::moderne::prepa::baseChoisie] || !$::moderne::prepa::baseChoisie} { set ::moderne::prepa::base $b }
      ::moderne::prepa::majBases
    }
  }
  # (the library, shown meanwhile on another database, goes to it)
  catch {
    if {[winfo exists $::moderne::biblio::w] && $::moderne::biblio::base != $b} {
      set ::moderne::biblio::base $b
      catch ::moderne::biblio::majBases
      ::moderne::biblio::maj
    }
  }
}

### Is the reference database still to be opened by baseReference (a file
### there, not open, not tried yet)?
proc ::moderne::mesbases::referenceAOuvrir {} {
  variable essaye
  set candidats [list $::moderne::fichierReference]
  catch {lappend candidats [::moderne::gaby::trouverFichier]}
  foreach f $candidats {
    if {$f eq {}} { continue }
    set f [chemin $f]
    if {[slot $f]} { return 0 }
    if {[file exists $f] && ![info exists essaye($f)]} { return 1 }
  }
  return 0
}

### The reference database read in the background after startup (Gaby:
### 3 s of reading, which froze the screen when the Lab first opened):
### its opening then takes what was read (sc_base prepa)
proc ::moderne::mesbases::prelireReference {} {
  if {[catch {referenceAOuvrir} r] || !$r} { return }
  set candidats [list $::moderne::fichierReference]
  catch {lappend candidats [::moderne::gaby::trouverFichier]}
  foreach f $candidats {
    if {$f eq {}} { continue }
    set f [chemin $f]
    if {[estPgn $f] || ![file exists $f]} { continue }
    # (the name as ::file::Open will give it)
    if {[catch {sc_base prepa [file rootname [fullname $f]]}]} { return }
    # (not opened after 20 minutes: the memory given back)
    after [expr {20 * 60 * 1000}] {catch {
      if {[lindex [sc_base prepa] 0] eq "pret"} { sc_base prepa oublier }
    }}
    return
  }
}

### Remembers database b as the reference (not the clipboard nor "Siby live")
proc ::moderne::mesbases::retenirReference {b} {
  if {!$b || $b == [sc_info clipbase] || ![sc_base inUse $b]} { return }
  set f [sc_base filename $b]
  if {[string match "*Siby live" $f]} { return }
  set ::moderne::fichierReference [chemin $f]
  after idle ::moderne::mesbases::appliquerCadenas
}

################################################################################
### Padlock: a padlocked database can't be changed (no game saved, deleted,
### reordered or added). Read-only in memory only: nothing is written to
### the files, and the padlock is taken off with one click. The reference
### database (Gaby by default) is padlocked unless it was unlocked; Gaby's
### own updates go through (the padlock is lifted during the import).
### ::moderne::cadenas / ::moderne::sansCadenas (saved): paths padlocked /
### unlocked by hand.
################################################################################

foreach {_v _d} {cadenas {} sansCadenas {}} {
  if {![info exists ::moderne::$_v]} { set ::moderne::$_v $_d }
}
unset _v _d
namespace eval ::moderne::mesbases { variable pose ; array set pose {} }

### Name of a database as shown: "Gaby" for Gaby's file (gaby.si4, written in
### lowercase by the Gaby program), else the file's name
proc ::moderne::nomBase {f} {
  set t [file tail $f]
  if {[string tolower [file rootname $t]] eq "gaby" || [string tolower $t] eq "gaby"} { return Gaby }
  # (every game played in Siby against an engine, Toby, Leela or an Alter
  # Ego, saved automatically)
  if {$t eq "Siby games" || $t eq "Siby games.si4"} {
    return [::moderne::tr "Mes parties Siby" "My Siby games"]
  }
  if {![catch {::moderne::enligne::estMaBase $f} mien] && $mien} {
    return [::moderne::tr "Mes parties en ligne" "My online games"]
  }
  return $t
}

### Path of the reference database ({} if none)
proc ::moderne::mesbases::fichierRef {} {
  # (a reference whose file is gone, deleted or moved, is forgotten)
  if {$::moderne::fichierReference ne {} && ![file exists [chemin $::moderne::fichierReference]]} {
    set ::moderne::fichierReference {}
  }
  if {$::moderne::fichierReference ne {}} { return [chemin $::moderne::fichierReference] }
  set g {}
  catch {set g [::moderne::gaby::trouverFichier]}
  if {$g eq {}} { return {} }
  return [chemin $g]
}

proc ::moderne::mesbases::cadenassee {f} {
  set f [chemin $f]
  if {$f in $::moderne::cadenas} { return 1 }
  if {$f in $::moderne::sansCadenas} { return 0 }
  expr {$f eq [fichierRef]}
}

### Padlock (or not) of every open database, according to the settings
proc ::moderne::mesbases::appliquerCadenas {} {
  variable pose
  foreach b [array names pose] {
    if {![sc_base inUse $b] || [chemin [sc_base filename $b]] ne $pose($b)} { unset pose($b) }
  }
  for {set b 1} {$b <= [sc_base count total]} {incr b} {
    if {![sc_base inUse $b] || $b == [sc_info clipbase]} { continue }
    set f [chemin [sc_base filename $b]]
    if {[string match "*Siby live*" $f]} { continue }
    if {[cadenassee $f]} {
      if {![sc_base isReadOnly $b]} {
        if {![catch {sc_base isReadOnly verrou $b 1}]} { set pose($b) $f }
      }
    } elseif {[info exists pose($b)]} {
      catch {sc_base isReadOnly verrou $b 0}
      unset pose($b)
    }
  }
  catch {::windows::switcher::Refresh}
}

### Is open database b padlocked by Siby?
proc ::moderne::mesbases::estCadenassee {b} {
  variable pose
  info exists pose($b)
}

proc ::moderne::mesbases::basculerCadenas {f} {
  set f [chemin $f]
  set avant [cadenassee $f]
  # (the reference unlocked only on purpose: only its updates change it
  # otherwise, Yosha 2026-11-09)
  if {$avant && $f eq [fichierRef]} {
    set r [tk_messageBox -parent . -icon warning -title Siby -default cancel \
        -boutons [list retirer [T "Retirer le cadenas" "Remove the padlock"] cancel [T "Annuler" "Cancel"]] \
        -message [T "Retirer le cadenas de « [::moderne::nomBase $f] », la base de référence ?" \
                    "Remove the padlock of « [::moderne::nomBase $f] », the reference database?"]]
    if {$r ne "retirer"} { return }
  }
  set ::moderne::cadenas [lsearch -all -inline -not -exact $::moderne::cadenas $f]
  set ::moderne::sansCadenas [lsearch -all -inline -not -exact $::moderne::sansCadenas $f]
  if {$avant} { lappend ::moderne::sansCadenas $f } else { lappend ::moderne::cadenas $f }
  appliquerCadenas
  remplir
  catch updateTitle
}

### For Siby's own writing (Gaby's updates): padlock lifted, then put back
proc ::moderne::mesbases::lever {b} {
  if {![estCadenassee $b]} { return 0 }
  catch {sc_base isReadOnly verrou $b 0}
  return 1
}
proc ::moderne::mesbases::reposer {b leve} {
  if {$leve && [sc_base inUse $b]} { catch {sc_base isReadOnly verrou $b 1} }
}

### "My databases" view (navigation bar): the tiles fill the window, like a
### desktop (the board is a hidden tab, as in the broadcast list)
proc ::moderne::mesbases::vue {} {
  # (a finished game against an engine closed first)
  if {![catch {::moderne::jeu::fermerSiFinie [info level 0]} r] && $r} { return }
  if {![::moderne::direct::docking]} { ouvrir ; return }
  # (from the Lab: laid over it, the Lab kept underneath, see superposer;
  # from a broadcast laid over the Lab too)
  catch ::moderne::direct::retirerSuperposition
  # (already laid over the Lab: nothing to rebuild)
  if {[enSuperposition]} {
    catch {raise .fdockmesBasesWin}
    catch synchroniser
    catch remplir
    return
  }
  set bloc [::moderne::disposition::blocLab]
  set ok 0
  if {$bloc ne {} && ![catch superposer ok] && $ok} { return }
  # (the slow way, a layout of its own: why, in siby.log)
  set pourquoi {}
  foreach {nom test} {enVue {::moderne::mesbases::enVue} jeu {winfo exists .serGameWin} directVue {::moderne::direct::vueOuverte}
                      directDessus {::moderne::direct::enSuperposition} plateauVu {winfo ismapped .main.board} blocs {::moderne::lab::blocs}} {
    set v ? ; catch {set v [uplevel #0 $test]} ; lappend pourquoi "$nom=$v"
  }
  foreach lab [::moderne::lab::blocs] { catch {lappend pourquoi "$lab=[winfo ismapped $lab]"} }
  catch {::moderne::journal "My databases: own layout (Lab [expr {$bloc ne {} ? {there} : {absent}}], laid over: $ok; $pourquoi)"}
  set W [expr {[winfo screenwidth .] - 40}]
  set H [expr {[winfo screenheight .] - 90}]
  ::moderne::disposition::appliquer moderne_mesbases [list [list MainWindowGeometry "${W}x${H}+10+10"] \
      [list [list .pw vertical {}] [list TNotebook .nb [list .fdockmesBasesWin .fdockmain]]]] 0
  cacherEchiquier
  after 600 ::moderne::mesbases::cacherEchiquier
}

proc ::moderne::mesbases::cacherEchiquier {} {
  if {![winfo exists .fdockmesBasesWin]} { return }
  catch {
    set nb [::docking::find_tbn .fdockmain]
    if {$nb eq [::docking::find_tbn .fdockmesBasesWin]} {
      $nb select .fdockmesBasesWin
      $nb hide .fdockmain
    }
  }
  catch synchroniser
  catch remplirSiChange
}

### My databases laid over the Lab (Yosha 2026-11-06: going to the Lab took
### 1.7 s on Windows, every window of the Lab destroyed for My databases'
### layout and made again on the way back). From the Lab, the tiles' window
### leaves its tab and covers the work area (the left bar stays); back to
### the Lab, it is hidden (in no tab: the Lab has its own list): nothing is
### rebuilt. Another layout
### asked meanwhile takes it back first (::docking::layout_restore).
### superpose: {notebook index title tab-chosen-before} while laid over
namespace eval ::moderne::mesbases { variable superpose {} }
proc ::moderne::mesbases::superposer {} {
  variable superpose
  variable w
  if {$superpose ne {}} { raise .fdockmesBasesWin ; return 1 }
  if {![winfo exists .fdockmesBasesWin]} {
    # (made in a tab of the Lab first: as part of a layout, so that the
    # Lab does not show that tab's page, Analysis, under the cover)
    set avant [expr {[info exists ::docking::enConstruction] ? $::docking::enConstruction : 0}]
    set ::docking::enConstruction 1
    catch ouvrir
    set ::docking::enConstruction $avant
    update idletasks
  }
  set f .fdockmesBasesWin
  if {![winfo exists $f]} { return 0 }
  # (taken out of the tab it may have been put in, the tab chosen before
  # kept in front there: the Lab has its own list of the databases, Yosha
  # 2026-11-06, the tiles' tab is not left in it)
  set nb [::docking::find_tbn $f]
  if {$nb ne {} && [winfo exists $nb] && $f in [$nb tabs]} {
    set avant [$nb select]
    if {$avant eq $f} { set avant [lindex [lsearch -all -inline -not -exact [$nb tabs] $f] 0] }
    $nb forget $f
    if {$avant ne {} && [winfo exists $avant] && $avant in [$nb tabs]} { catch {$nb select $avant} }
  }
  set superpose 1
  catch ::moderne::prepa::rendreNotation
  catch ::moderne::docks::pauserSousCouverture
  place $f -in .pw -x 0 -y 0 -relwidth 1 -relheight 1
  raise $f
  catch synchroniser
  catch remplir
  catch {focus $w.c}
  return 1
}
proc ::moderne::mesbases::enSuperposition {} {
  variable superpose
  expr {$superpose ne {} && [winfo exists .fdockmesBasesWin]}
}
### The cover taken off: the tiles' window hidden (in no tab), the Lab under
### it shown again
proc ::moderne::mesbases::retirerSuperposition {} {
  variable superpose
  if {$superpose eq {}} { return 0 }
  set superpose {}
  catch ::moderne::docks::reprendreSousCouverture
  set f .fdockmesBasesWin
  if {![winfo exists $f]} { return 0 }
  place forget $f
  after idle {catch ::moderne::prepa::suivreNotation}
  return 1
}

### In the desktop view (board hidden): a database opened goes back to
### the analysis layout, with its game list
proc ::moderne::mesbases::enVue {} {
  if {[enSuperposition]} { return 1 }
  if {![winfo exists .fdockmesBasesWin] || ![winfo exists .fdockmain]} { return 0 }
  set nb [::docking::find_tbn .fdockmain]
  expr {$nb ne {} && $nb eq [::docking::find_tbn .fdockmesBasesWin] && [$nb tab .fdockmain -state] eq "hidden"}
}

proc ::moderne::mesbases::ouvrir {} {
  # (a finished game against an engine closed first)
  if {![catch {::moderne::jeu::fermerSiFinie ::moderne::mesbases::ouvrir} r] && $r} { return }
  variable w
  catch synchroniser
  if {[winfo exists $w]} {
    # (laid over the Lab, or hidden since: shown over it again, not put in
    # one of its tabs)
    if {[enSuperposition]} { remplir ; return }
    if {[::docking::find_tbn .fdockmesBasesWin] eq {} && ![catch {::moderne::direct::labDessous} lab] && $lab ne {}} {
      if {![catch superposer ok] && $ok} { return }
    }
    ::createToplevel $w ; remplir ; return
  }
  ::createToplevel $w
  ::setTitle $w [T "Mes bases" "My databases"]
  set h [ttk::frame $w.haut -padding {10 8}]
  pack $h -side top -fill x
  ttk::label $h.t -text [T "Mes bases" "My databases"] -font font_Bold
  ttk::button $h.ajouter -text [T "Ajouter des bases…" "Add databases…"] -command ::moderne::mesbases::ajouter
  ttk::button $h.nouvelle -text [T "Nouvelle base…" "New database…"] -command {::file::New ; ::moderne::mesbases::remplir}
  ttk::button $h.dossier -text [T "Ajouter un dossier de l'ordinateur…" "Add a computer folder…"] -command {::moderne::mesbases::ajouterDossierDisque {}}
  catch {::utils::tooltip::Set $h.dossier [T "Un dossier de l'ordinateur : ses bases et ses PGN, ses sous-dossiers ; les nouveaux fichiers apparaissent tout seuls" \
      "A folder from the computer: its databases and PGN files, its subfolders; new files appear by themselves"]}
  # sort of the tiles (Yosha 2026-11-02)
  ttk::menubutton $h.tri -menu $h.tri.m -style Toolbutton
  ::menu $h.tri.m -tearoff 0
  foreach {v fr en} {recent "Récemment ouvertes" "Recently opened" nom "Nom" "Name" taille "Nombre de parties" "Number of games"} {
    $h.tri.m add radiobutton -label [T $fr $en] -variable ::moderne::mesbases::tri -value $v \
        -command ::moderne::mesbases::remplir
  }
  # search by name, a compact field in the top bar (as Lichess's studies)
  ttk::frame $h.rech
  ttk::label $h.rech.l -text "🔍" -foreground [::moderne::c texteDoux]
  ttk::entry $h.rech.e -width 26 -textvariable ::moderne::mesbases::filtre
  catch {::utils::tooltip::Set $h.rech.e [T "Rechercher une base par son nom" "Search a database by name"]}
  pack $h.rech.l -side left -padx {0 4}
  pack $h.rech.e -side left -ipady 2
  bind $h.rech.e <KeyRelease> {after cancel ::moderne::mesbases::remplir ; after 150 ::moderne::mesbases::remplir}
  pack $h.t -side left
  pack $h.tri -side left -padx {16 0}
  pack $h.rech -side left -padx {16 0}
  pack $h.nouvelle $h.dossier $h.ajouter -side right -padx {6 0}
  # first install: Gaby offered here until it is on this computer
  ttk::button $h.gaby -text [T "Télécharger Gaby" "Download Gaby"] -style Accent.TButton \
      -command {catch ::moderne::gaby::confirmerGrande}
  catch {::utils::tooltip::Set $h.gaby [T "Gaby, la base de référence de Siby (environ 11 millions de parties, mise à jour chaque jour)" \
      "Gaby, Siby's reference database (about 11 million games, updated every day)"]}
  set c [canvas $w.c -highlightthickness 0 -borderwidth 0 -background [::moderne::c fond] \
      -yscrollcommand [list $w.sb set]]
  ttk::scrollbar $w.sb -command [list $c yview]
  pack $w.sb -side right -fill y
  pack $c -side left -fill both -expand 1
  ttk::frame $c.g -padding 8
  $c create window 0 0 -anchor nw -window $c.g -tags grille
  # (filled again once the size has settled, and only if something shown
  # changed: every size of the start filled it, 4 times 1.5 to 3 s on
  # Windows, Yosha 2026-11-17)
  bind $c <Configure> {::moderne::mesbases::redimensionne}
  # (a press on an empty place, dragged: a frame chooses the cards it
  # touches; Ctrl: adds them)
  foreach x [list $c $c.g] {
    bind $x <Button-1> {::moderne::mesbases::lassoDebut %X %Y 0}
    bind $x <Control-Button-1> {::moderne::mesbases::lassoDebut %X %Y 1}
    bind $x <B1-Motion> {::moderne::mesbases::lassoBouge %X %Y}
    bind $x <ButtonRelease-1> {::moderne::mesbases::lassoFin %X %Y}
  }
  # (arrows: the next card; Shift+arrows: the ones in between; Ctrl+arrows:
  # moves without choosing, Ctrl+Space chooses; Ctrl+A: all; Enter: open)
  foreach {k d} {Left gauche Right droite Up haut Down bas Home debut End fin} {
    bind $c <$k> [list ::moderne::mesbases::fleche $d {} ]
    bind $c <$k> +break
    bind $c <Shift-$k> [list ::moderne::mesbases::fleche $d shift]
    bind $c <Shift-$k> +break
    bind $c <Control-$k> [list ::moderne::mesbases::fleche $d ctrl]
    bind $c <Control-$k> +break
    bind $c <Control-Shift-$k> [list ::moderne::mesbases::fleche $d shift]
    bind $c <Control-Shift-$k> +break
  }
  bind $c <Control-space> {::moderne::mesbases::basculer $::moderne::mesbases::choisie ; break}
  bind $c <Control-a> {::moderne::mesbases::toutChoisir ; break}
  bind $c <Control-A> {::moderne::mesbases::toutChoisir ; break}
  bind $c <Return> {::moderne::mesbases::ouvrirChoix ; break}
  bind $c <Escape> {::moderne::mesbases::rienChoisir ; break}
  # right click on an empty place: New folder…
  bind $c <Button-3> {::moderne::mesbases::menuPage %X %Y}
  bind $c.g <Button-3> {::moderne::mesbases::menuPage %X %Y}
  # Del: the tile goes away (the file stays); Ctrl+Del: the file is deleted
  bind $c <Delete> {::moderne::mesbases::touche retirer}
  bind $c <Control-Delete> {::moderne::mesbases::touche supprimer}
  # (the wheel's direction: it only went up, Yosha 2026-11-17)
  bind $c <MouseWheel> "$c yview scroll \[expr {%D > 0 ? -1 : 1}\] units"
  bind $c <Button-4> [list $c yview scroll -1 units]
  bind $c <Button-5> [list $c yview scroll 1 units]
  catch {::moderne::repeindre $w}
  if {[llength [info commands ::createToplevelFinalize]]} { catch {::createToplevelFinalize $w} }
  remplir
}

### The databases, like Lichess's studies (Yosha 2026-11-02): a grid with
### thin lines, the name in the link colour, one line of details, the first
### games below (as a study's chapters); folders that fold. The only colour:
### the accent, for the names (links) and the database open now.
proc ::moderne::mesbases::redimensionne {} {
  variable attenteTaille
  catch {after cancel $attenteTaille}
  set attenteTaille [after 150 ::moderne::mesbases::remplirSiChange]
}

### What the tiles show: their width, the databases, the choice, the
### filter, the folded folders, the view, the open databases
proc ::moderne::mesbases::signature {} {
  variable w
  variable choisie
  variable filtre
  variable replies
  set o {}
  for {set i 1} {$i <= [sc_base count total]} {incr i} { if {[sc_base inUse $i]} { lappend o $i [sc_base numGames $i] } }
  return [list $w [winfo width $w.c] [liste] [expr {[info exists choisie] ? $choisie : {}}] \
      [expr {[info exists filtre] ? $filtre : {}}] [expr {[info exists replies] ? $replies : {}}] $o [sc_base current] \
      [expr {[info exists ::moderne::mesbases::compacts] ? $::moderne::mesbases::compacts : {}}] $::moderne::basesRetirees]
}

### Filled again only if what it shows changed; always when no tile is
### there (never an empty page, Yosha 2026-11-17)
proc ::moderne::mesbases::remplirSiChange {} {
  variable w
  variable signatureRemplie
  if {![winfo exists $w.c]} { return }
  if {[winfo exists $w.c.g] && [llength [winfo children $w.c.g]] > 0
      && [info exists signatureRemplie] && [signature] eq $signatureRemplie} { return }
  remplir
}

proc ::moderne::mesbases::remplir {} {
  variable w
  variable choisie
  variable filtre
  variable replies
  catch ::moderne::basesliste::plusTard
  set c $w.c
  if {![winfo exists $c]} { return }
  # (every folder closed at each start, "Other databases" too: fewer cards
  # to draw, Yosha 2026-11-17)
  variable fermesAuDemarrage
  if {![info exists fermesAuDemarrage]} {
    set fermesAuDemarrage 1
    catch {foreach g [concat [nomsGroupes] [list [T "Autres bases" "Other databases"]]] { if {$g ni $replies} { lappend replies $g } }}
  }
  variable signatureRemplie
  catch {set signatureRemplie [signature]}
  set g $c.g
  foreach x [winfo children $g] { destroy $x }
  # (tile -> file: games dragged from the list are dropped on a tile)
  variable tuileFichier
  array unset tuileFichier
  set larg [winfo width $c]
  if {$larg < 100} { set larg 900 }
  set parLigne [expr {max(1, ($larg - 24) / 420)}]
  # (each card: its width with the gap and the shadow)
  set lc [expr {($larg - 24) / $parLigne}]
  polices
  # (card: margins, the title, two lines of pills, four games with a line
  # between them, the gap and the shadow)
  set hTete [expr {max(44, [font metrics siby_baseTitre -linespace] + 4 + 2 * ([font metrics font_Small -linespace] + 6) + 4)}]
  set hc [expr {24 + 22 + $hTete + 4 * ([font metrics font_Regular -linespace] + 9) + 14 + [ecart]}]
  set i 0
  set gaby {}
  catch {set gaby [chemin [::moderne::gaby::trouverFichier]]}
  # reference database: the saved one, Gaby otherwise
  set ref $gaby
  catch {set ref [fichierRef]}
  catch {$w.haut.tri configure -text "[T "Trier :" "Sort:"] [libelleTri] ▾"}
  # (the button "Download Gaby" while there is none, and none being downloaded)
  catch {
    set sansGaby [expr {![::moderne::gaby::installee] && !$::moderne::gaby::enCours}]
    if {$sansGaby && ![winfo ismapped $w.haut.gaby]} {
      pack $w.haut.gaby -side right -padx {6 0} -before $w.haut.nouvelle
    } elseif {!$sansGaby} {
      pack forget $w.haut.gaby
    }
  }
  # (the databases shown, by folder: those of a folded folder are counted)
  set parSection [dict create]
  set ordreSections {}
  foreach {f sec} [ordre $gaby $ref] {
    if {$filtre ne {} && [string first [string tolower $filtre] [string tolower [file rootname [::moderne::nomBase $f]]]] < 0} { continue }
    if {$sec ni $ordreSections} { lappend ordreSections $sec }
    dict lappend parSection $sec $f
  }
  # (the empty folders too, in their place: folders by name, then the
  # databases out of any folder)
  set dossiersTous [nomsGroupes]
  if {[llength $dossiersTous] && $filtre eq {}} {
    set autre [T "Autres bases" "Other databases"]
    set nouvel {}
    if {{} in $ordreSections} { lappend nouvel {} }
    foreach nomD $dossiersTous { lappend nouvel $nomD }
    lappend nouvel $autre
    set ordreSections $nouvel
  }
  variable titreDossier
  array unset titreDossier
  variable affiches {}
  set ligne 0
  set k 0
  foreach sec $ordreSections {
    # (a folder inside a folded one: not shown at all)
    if {[dansReplie $sec]} { continue }
    set fichiers [expr {[dict exists $parSection $sec] ? [dict get $parSection $sec] : {}}]
    set plie [expr {$sec ne {} && $sec in $replies}]
    # a folder: its name, its number of databases; a click folds it
    if {$sec ne {}} {
      set s [frame $g.s$k -background [::moderne::c fond] -cursor hand2]
      label $s.f -text [expr {$plie ? "▸" : "▾"}] -font font_Bold -background [::moderne::c fond] -foreground [::moderne::c texteDoux]
      label $s.i -image [iconeDossier] -background [::moderne::c fond]
      # (a folder in a folder: its own name, set in by its depth)
      label $s.n -text [nomCourt $sec] -font font_Bold -background [::moderne::c fond] -foreground [::moderne::c texteFort]
      label $s.c -text [llength $fichiers] -font font_Small -background [::moderne::c fond] -foreground [::moderne::c texteDoux]
      pack $s.f $s.i $s.n $s.c -side left -padx {0 6}
      if {[info exists ::moderne::mesbases::suivisNoms] && $sec in $::moderne::mesbases::suivisNoms} {
        catch {::utils::tooltip::Set $s.n [dict get $::moderne::mesbases::suivis $sec]}
      }
      foreach x [list $s $s.f $s.i $s.n $s.c] {
        # (a click folds it; dragged onto another folder's title: put
        # before it)
        bind $x <Button-1> [list ::moderne::mesbases::dossierDebut $sec %X %Y]
        bind $x <B1-Motion> {::moderne::mesbases::dossierBouge %X %Y}
        bind $x <ButtonRelease-1> {::moderne::mesbases::dossierFin %X %Y}
        bind $x <Button-3> [list ::moderne::mesbases::menuPage %X %Y \
            [expr {$sec eq [T "Autres bases" "Other databases"] && $sec ni [nomsGroupes] ? {} : $sec}] [cleVue $sec]]
      }
      # (cards are dropped on the title; "Other databases": out of the folders)
      set titreDossier($s) [expr {$sec in [nomsGroupes] ? $sec : {}}]
      grid $s -row $ligne -column 0 -columnspan $parLigne -sticky w -padx [list [expr {8 + 26 * [profondeur $sec]}] 8] -pady {14 4}
      incr ligne
      incr k
    }
    if {$plie} { continue }
    if {![llength $fichiers] && ![aDesSousDossiers $sec]} {
      label $g.v$k -text [T "Classeur vide : glisse une base sur son titre" "Empty binder: drag a database onto its title"] \
          -font font_Small -background [::moderne::c fond] -foreground [::moderne::c texteDoux]
      grid $g.v$k -row $ligne -column 0 -columnspan $parLigne -sticky w -padx [list [expr {30 + 26 * [profondeur $sec]}] 8] -pady {0 6}
      incr ligne
      continue
    }
    if {![llength $fichiers]} { continue }
    if {[enListe $sec]} {
      # (the List view: smaller cards, more on a line, in their own frame so
      # that the columns of the large ones do not change)
      set z [frame $g.z$k -background [::moderne::c fond]]
      grid $z -row $ligne -column 0 -columnspan $parLigne -sticky nw
      incr ligne
      incr k
      set nL [expr {max(1, ($larg - 24) / 300)}]
      set lL [expr {($larg - 24) / $nL}]
      set hL [expr {24 + [font metrics font_Bold -linespace] + 16 + [ecart]}]
      set col 0 ; set lz 0
      foreach f $fichiers {
        lappend affiches $f
        grid [ligne $z.t$i $f $gaby $ref $lL $hL] -row $lz -column $col -sticky nw
        if {[incr col] >= $nL} { set col 0 ; incr lz }
        incr i
      }
      continue
    }
    set col 0
    foreach f $fichiers {
      lappend affiches $f
      set t [cellule $g.t$i $f $gaby $ref $lc $hc]
      grid $t -row $ligne -column $col -sticky nw
      if {[incr col] >= $parLigne} { set col 0 ; incr ligne }
      incr i
    }
    if {$col} { incr ligne }
  }
  if {!$i && ![llength $ordreSections]} {
    ttk::label $g.vide -foreground [::moderne::c texteDoux] -text [expr {$filtre ne {} ?
        [T "Aucune base ne correspond." "No database matches."] :
        [T "Aucune base : « Ajouter une base… » ou Fichier › Ouvrir." "No database: \"Add a database…\" or File › Open."]}]
    grid $g.vide -row 0 -column 0 -pady 20 -padx 8
  }
  update idletasks
  $c configure -scrollregion [list 0 0 [winfo reqwidth $g] [winfo reqheight $g]]
}

### One database: a card drawn on a canvas (rounded corners, soft
### shadow, lifted when hovered; Yosha 2026-11-03), the icon in a tinted
### rounded square, the details as small pills, the first games below (as
### a study's chapters) with thin lines between them. The widgets of the
### card ($t0.carte: .i .n .d .p) sit on the drawing.
proc ::moderne::mesbases::cellule {t0 f gaby ref lc hc} {
  variable choisie
  variable tuileFichier
  set ouverte [slot $f]
  set e [ecart]
  frame $t0 -background [::moderne::c fond] -width $lc -height $hc
  pack propagate $t0 0
  set tuileFichier($t0) $f
  set cw [expr {$lc - $e}]
  set ch [expr {$hc - $e}]
  canvas $t0.fond -highlightthickness 0 -borderwidth 0 -background [::moderne::c fond] -width $lc -height $hc
  place $t0.fond -x 0 -y 0 -width $lc -height $hc
  dessinerCarte $t0 $f 0
  set fond [couleurCarte $f 0]
  set m 12
  set t $t0.carte
  frame $t -background $fond
  place $t -x [expr {$m + 4}] -y [expr {$m - 2}] -width [expr {$cw - 2 * $m - 4}] -height [expr {$ch - 2 * $m}]
  pack propagate $t 0
  set haut [frame $t.h -background $fond]
  # the icon in a tinted rounded square (the reference: a star)
  canvas $t.i -width 44 -height 44 -highlightthickness 0 -borderwidth 0 -background $fond
  arrondi $t.i 0 0 44 44 11 -fill [::moderne::c tuileIcone] -outline {}
  if {$f eq $gaby || $f eq $ref} {
    $t.i create text 22 22 -text ★ -font [list [font actual font_Regular -family] 16] -fill [::moderne::c accent]
  } else {
    $t.i create image 22 22 -image [iconeBase]
  }
  set l [expr {$cw - 2 * $m - 4 - 66}]
  set titre [frame $haut.t -background $fond]
  label $t.n -text [couper [file rootname [::moderne::nomBase $f]] siby_baseTitre $l] -font siby_baseTitre \
      -background $fond -foreground [::moderne::c accent] -anchor w
  set infos [details $f $ouverte $ref]
  # (the details also as one text: the tooltip and the tests)
  label $t.d -text [join [lmap x $infos {lindex $x 0}] " · "]
  canvas $t.pu -highlightthickness 0 -borderwidth 0 -background $fond -width $l -height 22
  set hPuces [pastilles $t.pu $infos $l]
  $t.pu configure -height $hPuces
  pack $t.i -in $haut -side left -anchor n -padx {0 14}
  pack $t.n -in $haut -side top -anchor w -fill x
  pack $t.pu -in $haut -side top -anchor w -pady {4 0}
  pack $haut -side top -fill x -padx {14 10} -pady {12 10}
  # the first games, as a study's chapters
  set p [frame $t.p -background $fond]
  pack $p -side top -fill x -padx {14 10}
  grid columnconfigure $p 0 -weight 1
  set ap [apercu $f $ouverte]
  # (an empty database: nothing to show, whether opened or not)
  if {$ap eq "jamais" && [string match "0 *" [$t.d cget -text]]} { set ap {} }
  if {$ap eq "jamais"} { lireApercuPlusTard $f }
  if {$ap eq "jamais"} {
    label $p.m -text [T "Aperçu à la première ouverture" "Preview at the first opening"] -font font_Small \
        -background $fond -foreground [::moderne::c texteDoux] -anchor w
    grid $p.m -row 0 -column 0 -sticky w
  } elseif {![llength $ap]} {
    label $p.m -text [T "Aucune partie" "No games"] -font font_Small -background $fond -foreground [::moderne::c texteDoux] -anchor w
    grid $p.m -row 0 -column 0 -sticky w
  } else {
    set j 0
    set larg [expr {$cw - 2 * $m - 4 - 24}]
    set l1 [expr {$larg * 60 / 100}]
    set l2 [expr {$larg - $l1 - 10}]
    set r 0
    foreach x $ap {
      lassign [libellePartie $x] a b
      if {$j} {
        frame $p.s$j -background [::moderne::c trait] -height 1
        grid $p.s$j -row $r -column 0 -columnspan 2 -sticky ew
        incr r
      }
      label $p.a$j -text [couper $a font_Regular $l1] -font font_Regular -background $fond -foreground [::moderne::c texte] -anchor w
      label $p.b$j -text [couper $b font_Small $l2] -font font_Small -background $fond -foreground [::moderne::c texteDoux] -anchor e
      grid $p.a$j -row $r -column 0 -sticky w -pady 4
      grid $p.b$j -row $r -column 1 -sticky e -pady 4 -padx {10 0}
      incr r
      incr j
    }
  }
  # click: chosen; double click: opened; right click: its menu
  lierCarte $t0 $f [concat [list $t0.fond $t $haut $titre $p] [winfo children $t] [winfo children $haut] [winfo children $p]]
  catch {::utils::tooltip::Set $t.n $f}
  return $t0
}

### The events of a card's widgets (both views)
proc ::moderne::mesbases::lierCarte {t0 f tout} {
  foreach x $tout {
    if {![winfo exists $x]} { continue }
    bind $x <Enter> [list ::moderne::mesbases::survolPlusTard $t0 $f]
    bind $x <Leave> [list ::moderne::mesbases::survolPlusTard $t0 $f]
    # (several databases, as in the file explorer: Ctrl+click adds or
    # removes one, Shift+click the ones in between, Ctrl+Shift+click adds
    # them; a press on one of the chosen cards keeps them all, to drag them)
    bind $x <Button-1> [list ::moderne::mesbases::appui $f %X %Y {}]
    bind $x <Control-Button-1> [list ::moderne::mesbases::appui $f %X %Y ctrl]
    bind $x <Shift-Button-1> [list ::moderne::mesbases::appui $f %X %Y shift]
    bind $x <Control-Shift-Button-1> [list ::moderne::mesbases::appui $f %X %Y ctrlshift]
    bind $x <B1-Motion> {::moderne::mesbases::glisserBouge %X %Y}
    bind $x <ButtonRelease-1> {::moderne::mesbases::relache %X %Y}
    bind $x <Double-Button-1> [list after idle [list ::moderne::mesbases::ouvrirBase $f]]
    bind $x <Button-3> [list ::moderne::mesbases::menu $f %X %Y]
  }
}

### One database in the "List" view of a binder (Yosha 2026-11-05): a small
### card with its icon, its name and the kind of file
proc ::moderne::mesbases::ligne {t0 f gaby ref lc hc} {
  variable tuileFichier
  set e [ecart]
  frame $t0 -background [::moderne::c fond] -width $lc -height $hc
  pack propagate $t0 0
  set tuileFichier($t0) $f
  set cw [expr {$lc - $e}]
  set ch [expr {$hc - $e}]
  canvas $t0.fond -highlightthickness 0 -borderwidth 0 -background [::moderne::c fond] -width $lc -height $hc
  place $t0.fond -x 0 -y 0 -width $lc -height $hc
  dessinerCarte $t0 $f 0
  set fond [couleurCarte $f 0]
  set m 12
  set t $t0.carte
  frame $t -background $fond
  place $t -x [expr {$m + 4}] -y [expr {$m - 2}] -width [expr {$cw - 2 * $m - 4}] -height [expr {$ch - 2 * $m}]
  pack propagate $t 0
  if {$f eq $gaby || $f eq $ref} {
    label $t.i -text ★ -font [list [font actual font_Regular -family] 13] -background $fond -foreground [::moderne::c accent]
  } else {
    label $t.i -image [image_ bases 1] -background $fond
  }
  set ext [expr {[string match -nocase *.pgn.gz $f] ? ".pgn.gz" : ([estPgn $f] ? ".pgn" : ".si4")}]
  label $t.x -text $ext -font font_Small -background $fond -foreground [::moderne::c texteDoux]
  set l [expr {$cw - 2 * $m - 4 - 40 - [font measure font_Small $ext] - 16}]
  label $t.n -text [couper [file rootname [::moderne::nomBase $f]] font_Bold $l] -font font_Bold \
      -background $fond -foreground [::moderne::c accent] -anchor w
  pack $t.i -side left -padx {6 10}
  pack $t.x -side right -padx {6 8}
  pack $t.n -side left -fill x -expand 1
  lierCarte $t0 $f [list $t0.fond $t $t.i $t.n $t.x]
  catch {::utils::tooltip::Set $t.n $f}
  return $t0
}

### A binder's view: "grand" (large icons, the default) or "liste"; key
### of the section: the binder's name, *autres* for "Other databases"
proc ::moderne::mesbases::cleVue {sec} {
  if {$sec eq [T "Autres bases" "Other databases"] && $sec ni [nomsGroupes]} { return *autres* }
  return $sec
}
proc ::moderne::mesbases::enListe {sec} {
  variable compacts
  expr {$sec ne {} && [cleVue $sec] in $compacts}
}
proc ::moderne::mesbases::changerVue {cle vue} {
  variable compacts
  set compacts [lsearch -all -inline -not -exact $compacts $cle]
  if {$vue eq "liste"} { lappend compacts $cle }
  remplir
  catch ::options.write
}

### A rounded rectangle on canvas c
proc ::moderne::mesbases::arrondi {c x0 y0 x1 y1 r args} {
  $c create polygon \
    [expr {$x0+$r}] $y0 [expr {$x1-$r}] $y0 $x1 $y0 $x1 [expr {$y0+$r}] \
    $x1 [expr {$y1-$r}] $x1 $y1 [expr {$x1-$r}] $y1 [expr {$x0+$r}] $y1 \
    $x0 $y1 $x0 [expr {$y1-$r}] $x0 [expr {$y0+$r}] $x0 $y0 \
    -smooth 1 -splinesteps 10 {*}$args
}

### Colour between a and b (t from 0 to 1)
proc ::moderne::mesbases::melange {a b t} {
  scan [::moderne::c $a] "#%2x%2x%2x" r1 g1 b1
  scan $b "#%2x%2x%2x" r2 g2 b2
  format "#%02x%02x%02x" [expr {int($r1 + ($r2 - $r1) * $t)}] [expr {int($g1 + ($g2 - $g1) * $t)}] [expr {int($b1 + ($b2 - $b1) * $t)}]
}

### Background of a card (hovered: lighter)
proc ::moderne::mesbases::couleurCarte {f dessus} {
  # (light theme: cards lighter than the page, as on Lichess)
  if {[info exists ::moderne::theme] && $::moderne::theme eq "clair"} {
    return [::moderne::c [expr {$dessus ? "champ" : "surface"}]]
  }
  return [::moderne::c [expr {$dessus ? "survol" : "surface2"}]]
}

### The card's drawing: a soft shadow (layers wider and paler outwards,
### lower when hovered), the rounded card, an accent outline when chosen
proc ::moderne::mesbases::dessinerCarte {t0 f dessus} {
  variable choisie
  set c $t0.fond
  if {![winfo exists $c]} { return }
  $c delete all
  set e [ecart]
  set cw [expr {[$c cget -width] - $e}]
  set ch [expr {[$c cget -height] - $e}]
  # (room above for the lift and the outline: lifted, the chosen card's
  # blue top was cut off, Yosha 2026-11-18)
  set x0 4 ; set y0 5 ; set x1 [expr {$cw}] ; set y1 [expr {$ch - 4}]
  set lev [expr {$dessus ? 3 : 0}]
  set noir [expr {[info exists ::moderne::theme] && $::moderne::theme eq "clair" ? "#8a857f" : "#000000"}]
  for {set k 7} {$k >= 1} {incr k -1} {
    set t [expr {0.5 + 0.5 * $k / 7.0}]
    arrondi $c [expr {$x0 - $k + 1}] [expr {$y0 - $k + 3 + $lev}] [expr {$x1 + $k - 1}] [expr {$y1 + $k + 2 + $lev}] [expr {14 + $k}] \
        -fill [melange fond $noir [expr {1 - $t}]] -outline {}
  }
  set choisi [estChoisie $f]
  # (the card reached with Ctrl+arrows, not chosen: a dashed outline)
  set curseur [expr {!$choisi && [info exists choisie] && $f eq $choisie}]
  arrondi $c $x0 [expr {$y0 - $lev}] $x1 [expr {$y1 - $lev}] 14 -fill [couleurCarte $f $dessus] \
      -outline [expr {$choisi ? [::moderne::c accent] : ($curseur ? [::moderne::c texteDoux] : {})}] -width 1.5 \
      -dash [expr {$curseur ? {4 3} : {}}] -tags carte
  # (the widgets follow the lift)
  catch {place configure $t0.carte -y [expr {10 - $lev}]}
}

### The details as pills on canvas c, on as many lines as needed (width l);
### returns the height used
proc ::moderne::mesbases::pastilles {c infos l} {
  set x 0 ; set y 0
  set h [expr {[font metrics font_Small -linespace] + 6}]
  foreach i $infos {
    lassign $i texte coul
    set w [expr {[font measure font_Small $texte] + 16}]
    if {$x > 0 && $x + $w > $l} { set x 0 ; incr y [expr {$h + 4}] }
    arrondi $c $x $y [expr {$x + $w}] [expr {$y + $h}] [expr {$h / 2}] -fill [::moderne::c pastille] -outline {}
    $c create text [expr {$x + 8}] [expr {$y + $h / 2}] -text $texte -font font_Small -anchor w \
        -fill [expr {$coul eq "accent" ? [::moderne::c accent] : [::moderne::c texteDoux]}]
    incr x [expr {$w + 6}]
  }
  return [expr {$y + $h}]
}

### Hover: the card under the pointer (checked a moment after Enter/Leave:
### going from one widget of the card to another is not leaving it)
proc ::moderne::mesbases::survolPlusTard {t0 f} {
  after cancel [list ::moderne::mesbases::survol $t0 $f]
  after 30 [list ::moderne::mesbases::survol $t0 $f]
}

proc ::moderne::mesbases::survol {t0 f} {
  variable dessus
  if {![winfo exists $t0]} { return }
  set w [winfo containing [winfo pointerx .] [winfo pointery .]]
  set d [expr {$w ne {} && [string first "$t0." "$w."] == 0}]
  if {[info exists dessus($t0)] && $dessus($t0) == $d} { return }
  set dessus($t0) $d
  dessinerCarte $t0 $f $d
  set fond [couleurCarte $f $d]
  set t $t0.carte
  set tous [list $t $t.h $t.h.t $t.p]
  # (the List view has no head nor games)
  foreach y [list $t $t.h $t.p] { if {[winfo exists $y]} { lappend tous {*}[winfo children $y] } }
  foreach x $tous {
    if {![winfo exists $x] || [string match $t.p.s* $x]} { continue }
    catch {$x configure -background $fond}
  }
}

### A card outlined (games dragged over it: glisser.tcl), or back to normal
proc ::moderne::mesbases::surligner {t0 oui} {
  set c $t0.fond
  if {![winfo exists $c]} { return }
  variable choisie
  variable tuileFichier
  set choisi [expr {[info exists tuileFichier($t0)] && [estChoisie $tuileFichier($t0)]}]
  set curseur [expr {!$choisi && [info exists tuileFichier($t0)] && [info exists choisie] && $tuileFichier($t0) eq $choisie}]
  $c itemconfigure carte -outline [expr {$oui || $choisi ? [::moderne::c accent] : ($curseur ? [::moderne::c texteDoux] : {})}] \
      -dash [expr {!$oui && $curseur ? {4 3} : {}}]
}

### Gap between the cards (pixels)
proc ::moderne::mesbases::ecart {} { return 16 }

### First games of a closed Siby database never seen: read in the
### background (opened read-only, then closed), one at a time, small
### databases only (a large one, as Gaby, when it is first opened)
proc ::moderne::mesbases::lireApercuPlusTard {f} {
  variable aLire
  variable apercuEssaye
  if {[info exists apercuEssaye($f)] || [estPgn $f]} { return }
  set si4 "[file rootname $f].si4"
  if {![file exists $si4] || [file size $si4] > 20000000} { return }
  if {![info exists aLire]} { set aLire {} }
  if {$f ni $aLire} { lappend aLire $f }
  after cancel ::moderne::mesbases::lireApercuSuivant
  after 300 ::moderne::mesbases::lireApercuSuivant
}

proc ::moderne::mesbases::lireApercuSuivant {} {
  variable aLire
  variable apercuEssaye
  variable apercus
  if {![info exists aLire] || ![llength $aLire]} { return }
  set f [lindex $aLire 0]
  set aLire [lrange $aLire 1 end]
  set apercuEssaye($f) 1
  if {![slot $f]} {
    set courante [sc_base current]
    if {![catch {sc_base open -readonly [file rootname $f]} b]} {
      set l {}
      catch {
        foreach r [split [string trimright [sc_game list 1 4 "w*\tb*\te*"] \n] \n] {
          if {$r ne {}} { lappend l [split $r \t] }
        }
      }
      catch {sc_base close $b}
      dict set apercus $f $l
    }
    catch {sc_base switch $courante}
  }
  if {[llength $aLire]} {
    after 50 ::moderne::mesbases::lireApercuSuivant
  } else {
    catch remplir
  }
}

### "Carlsen – Nakamura" and the event (a study's chapter: its name alone)
proc ::moderne::mesbases::libellePartie {r} {
  lassign $r bl no ev
  set nets {}
  foreach n [list $bl $no] {
    set n [string trim $n]
    if {$n in {? -}} { set n {} }
    # (the surname: "Carlsen, Magnus" -> Carlsen)
    lappend nets [string trim [lindex [split $n ,] 0]]
  }
  if {$ev in {? -}} { set ev {} }
  lassign $nets bl no
  if {$bl eq {} && $no eq {}} { return [list [expr {$ev ne {} ? $ev : "?"}] {}] }
  return [list "[expr {$bl eq {} ? "?" : $bl}] – [expr {$no eq {} ? "?" : $no}]" $ev]
}

### The details line: games, PGN, reference, padlock, open or when last opened
proc ::moderne::mesbases::details {f ouverte ref} {
  variable ouvertures
  set n [::moderne::enligne::nbParties $f]
  if {$ouverte} { set n [sc_base numGames $ouverte] } elseif {[estPgn $f]} { set n [nbPgn $f] }
  set l {}
  if {[string is integer -strict $n]} {
    lappend l [list "[::utils::thousands $n] [expr {$n == 1 ? [T partie game] : [T parties games]}]" {}]
  }
  if {[estPgn $f]} { lappend l {PGN {}} }
  if {$f eq $ref} { lappend l [list [T référence reference] accent] }
  if {[cadenassee $f]} { lappend l [list [T cadenassée locked] {}] }
  if {$ouverte} {
    lappend l [list "● [T ouverte open]" accent]
  } elseif {[dict exists $ouvertures $f]} {
    lappend l [list [depuis [dict get $ouvertures $f]] {}]
  }
  # Gaby: date of the last update
  set etat {}
  catch {if {$f eq [chemin [::moderne::gaby::trouverFichier]]} { set etat [::moderne::gaby::texteEtat] }}
  if {$etat ne {}} { lappend l [list $etat {}] }
  return $l
}

### "today", "3 days ago"…
proc ::moderne::mesbases::depuis {s} {
  set j [expr {([clock seconds] - $s) / 86400}]
  if {$j < 1} { return [T "ouverte aujourd'hui" "opened today"] }
  if {$j < 2} { return [T "ouverte hier" "opened yesterday"] }
  if {$j < 14} { return [T "ouverte il y a $j jours" "opened $j days ago"] }
  if {$j < 60} { set n [expr {$j / 7}] ; return [T "ouverte il y a $n semaines" "opened $n weeks ago"] }
  if {$j < 730} { set n [expr {$j / 30}] ; return [T "ouverte il y a $n mois" "opened $n months ago"] }
  set n [expr {$j / 365}]
  return [T "ouverte il y a $n ans" "opened $n years ago"]
}

### The first four games {white black event}: read in the database when it
### is open, in the file for a PGN file, else those seen when it was last
### open (kept); "jamais" when never seen
proc ::moderne::mesbases::apercu {f ouverte} {
  variable apercus
  set l {}
  if {$ouverte} {
    set courante [sc_base current]
    catch {
      sc_base switch $ouverte
      foreach r [split [string trimright [sc_game list 1 4 "w*\tb*\te*"] \n] \n] {
        if {$r ne {}} { lappend l [split $r \t] }
      }
    }
    catch {sc_base switch $courante}
    dict set apercus $f $l
    return $l
  }
  if {[estPgn $f] && ![string match -nocase *.gz $f] && [file exists $f]} {
    # (read again only when the file changed: 200 KB per PGN at each fill,
    # 2 s per fill with 74 databases on Windows, Yosha 2026-11-17)
    variable apercusPgn
    set sig {}
    catch {set sig [list [file mtime $f] [file size $f]]}
    if {$sig ne {} && [info exists apercusPgn($f)] && [lindex $apercusPgn($f) 0] eq $sig} {
      return [lindex $apercusPgn($f) 1]
    }
    if {![catch {
      set h [open $f r]
      fconfigure $h -encoding utf-8
      set t [read $h 200000]
      close $h
    }]} {
      set r {}
      foreach {- tag val} [regexp -all -inline {\[(Event|White|Black) "([^"]*)"\]} $t] {
        if {$tag eq "Event" && [dict size $r]} {
          lappend l [list [valeur $r White] [valeur $r Black] [valeur $r Event]]
          set r {}
          if {[llength $l] >= 4} { break }
        }
        dict set r $tag $val
      }
      if {[dict size $r] && [llength $l] < 4} {
        lappend l [list [valeur $r White] [valeur $r Black] [valeur $r Event]]
      }
      dict set apercus $f $l
      if {$sig ne {}} { set apercusPgn($f) [list $sig $l] }
      return $l
    }
  }
  if {[dict exists $apercus $f]} { return [dict get $apercus $f] }
  return jamais
}

### Folds or unfolds a folder (remembered)
proc ::moderne::mesbases::plier {sec} {
  variable replies
  if {$sec in $replies} {
    set replies [lsearch -all -inline -not -exact $replies $sec]
  } else {
    lappend replies $sec
  }
  remplir
}

### Text cut to width l on one line, "…" at the end (the full name: tooltip)
proc ::moderne::mesbases::couper {texte police l} {
  if {[font measure $police $texte] <= $l} { return $texte }
  while {$texte ne {} && [font measure $police "$texte…"] > $l} { set texte [string range $texte 0 end-1] }
  return "[string trimright $texte]…"
}

### The fonts of the page (the names larger, as Lichess's studies)
proc ::moderne::mesbases::polices {} {
  if {"siby_baseTitre" ni [font names]} {
    font create siby_baseTitre {*}[font actual font_Regular]
  }
  set s [font actual font_Regular -size]
  font configure siby_baseTitre -size [expr {$s < 0 ? round($s * 1.45) : round($s * 1.45)}]
}

### Icons: a database (the left bar's cylinder) and a folder
proc ::moderne::mesbases::iconeBase {} { return [image_ bases 1.5] }
proc ::moderne::mesbases::iconeDossier {} { return [image_ classeur 1] }

### Icon nom of the left bar's set (navicones.tcl), at size k (1, 1.5, 2)
### times the screen's scale
proc ::moderne::mesbases::image_ {nom k} {
  set theme [expr {[info exists ::moderne::theme] && $::moderne::theme eq "clair" ? "clair" : "sombre"}]
  set f 1
  catch {set f [::moderne::icones::facteur]}
  set f [expr {$f * $k}]
  set cle [expr {$f >= 2 ? "$theme@2" : ($f >= 1.5 ? "$theme@1.5" : $theme)}]
  if {![info exists ::moderne::navigation::iconesData($nom,$cle)]} { set cle $theme }
  set img siby_mb_${nom}_$cle
  if {[lsearch -exact [image names] $img] < 0} {
    image create photo $img -format png -data $::moderne::navigation::iconesData($nom,$cle)
  }
  return $img
}

proc ::moderne::mesbases::valeur {d k} {
  expr {[dict exists $d $k] ? [dict get $d $k] : {}}
}

proc ::moderne::mesbases::choisir {f} {
  variable choisie
  variable w
  variable tuileFichier
  variable selection
  set choisie $f
  set selection [list $f]
  variable ancre $f
  # (only the frames' colour changes: rebuilding the tiles on the first
  # click put the second one on a new tile, and the double click that
  # opens a database was never seen; Yosha 2026-11-02)
  redessinerChoix
  catch {focus $w.c}
}

### Del / Ctrl+Del on the chosen tile
proc ::moderne::mesbases::touche {action} {
  variable choisie
  variable selection
  if {![info exists choisie] || $choisie eq {} || $choisie ni [liste]} { return }
  # (Del with several chosen: all their tiles; Ctrl+Del: one at a time)
  if {$action eq "retirer" && [llength $selection] > 1} { retirerSelection ; return }
  set cible [expr {[llength $selection] == 1 ? [lindex $selection 0] : $choisie}]
  if {$cible ni [liste]} { return }
  $action $cible
}

proc ::moderne::mesbases::ouvrirBase {f} {
  # (the database first, then the Lab built once around it: the Lab built
  # first was filled with the former database, then everything was computed
  # and drawn again for the new one, the library and the game list four
  # times; "slow and chaotic", Yosha 2026-11-02)
  set versLab [enVue]
  set b [slot $f]
  # (the game on the board stays there, still in its own database)
  set ::file::sansListe $versLab
  ::moderne::onglets::enGardant {
    if {$b} {
      catch {::file::SwitchToBase $b}
    } else {
      catch {::file::Open [expr {[estPgn $f] ? $f : [file rootname $f]}]}
    }
  }
  set ::file::sansListe 0
  if {$versLab} { catch ::moderne::disposition::analyse }
  after idle ::moderne::mesbases::remplir
  # (the game list shown, its title on this database: the tab stayed on
  # the notation, its title on the former database, Yosha 2026-11-16)
  after idle ::moderne::mesbases::montrerListe
  after 600 ::moderne::mesbases::montrerListe
}

proc ::moderne::mesbases::montrerListe {} {
  if {![winfo exists .glistWin]} { catch ::windows::gamelist::Open }
  set nb {}
  catch {set nb [::docking::find_tbn .fdockglistWin]}
  if {$nb ne {}} { catch {$nb select .fdockglistWin} }
  catch setGamelistTitle
}

proc ::moderne::mesbases::menu {f X Y} {
  variable w
  variable selection
  if {$f in $selection && [llength $selection] > 1} { menuSelection $X $Y ; return }
  choisir $f
  # (a menu of the main window, not of the tile view: a command that
  # changes the layout destroys the tile view, and destroying the menu
  # while its command runs made Siby crash on Windows, Yosha 2026-11-01;
  # the commands also run just after the menu is closed)
  set m .mesBasesMenu
  catch {destroy $m}
  ::menu $m -tearoff 0
  set b [slot $f]
  $m add command -label [T "Ouvrir" "Open"] -command [list after idle [list ::moderne::mesbases::ouvrirBase $f]]
  $m add command -label [T "Fermer" "Close"] -state [expr {$b ? "normal" : "disabled"}] \
      -command [list after idle [list ::moderne::mesbases::fermer $f]]
  # (where the file is: the tile only gives its name, Yosha 2026-11-09)
  $m add command -label [T "Afficher dans le dossier" "Show in folder"] \
      -command [list after idle [list ::moderne::rapport::montrer [file nativename $f]]]
  $m add command -label [T "Copier le chemin" "Copy path"] \
      -command [list after idle [list ::moderne::mesbases::copierChemin $f]]
  $m add separator
  $m add command -label [T "Rechercher dans cette base…" "Search in this database…"] \
      -command [list after idle [list ::moderne::mesbases::rechercher $f]]
  $m add command -label [T "Base de référence (bibliothèque d'ouvertures)" "Reference database (opening library)"] \
      -command [list after idle [list ::moderne::mesbases::reference $f]]
  $m add command -label [expr {[cadenassee $f] ? [T "Retirer le cadenas" "Remove the padlock"] : [T "Cadenasser (protéger des modifications)" "Padlock (protect from changes)"]}] \
      -command [list after idle [list ::moderne::mesbases::basculerCadenas $f]]
  $m add command -label [expr {[estPgn $f] ? [T "Convertir en base Siby (.si4)…" "Convert to a Siby database (.si4)…"] : [T "Convertir en PGN…" "Convert to PGN…"]}] \
      -command [list after idle [list ::moderne::mesbases::convertir $f]]
  $m add command -label [T "Nettoyer la base…" "Clean up the database…"] \
      -command [list after idle [list ::moderne::mesbases::nettoyerBase $f]]
  $m add command -label [T "Nettoyer : commentaires → variantes…" "Clean: comments → variations…"] \
      -command [list after idle [list ::moderne::mesbases::nettoyer $f]]
  # groups: labels kept by Siby, the files do not move
  set mg $m.groupes
  ::menu $mg -tearoff 0
  set sonGroupe [groupe $f]
  foreach nomG [nomsGroupes] {
    set lib "[string repeat "    " [profondeur $nomG]][nomCourt $nomG]"
    $mg add command -label [expr {$nomG eq $sonGroupe ? "✓ $lib" : $lib}] \
        -command [list after idle [list ::moderne::mesbases::ranger $f $nomG]]
  }
  if {[llength [nomsGroupes]]} { $mg add separator }
  $mg add command -label [T "Nouveau classeur…" "New binder…"] \
      -command [list after idle [list ::moderne::mesbases::nouveauGroupe $f]]
  if {$sonGroupe ne {}} {
    $mg add command -label [T "Sortir du classeur" "Take out of the binder"] \
        -command [list after idle [list ::moderne::mesbases::ranger $f {}]]
  }
  $m add cascade -label [T "Déplacer vers" "Move to"] -menu $mg
  $m add separator
  $m add command -label [T "Retirer l'icône" "Remove the tile"] -accelerator [T Suppr Del] \
      -command [list after idle [list ::moderne::mesbases::retirer $f]]
  $m add command -label [T "Supprimer la base…" "Delete the database…"] -accelerator [T "Ctrl+Suppr" "Ctrl+Del"] \
      -command [list after idle [list ::moderne::mesbases::supprimer $f]]
  catch {::moderne::menubar::epurer $m}
  tk_popup $m $X $Y
}

### Right click > Copy path: the file's full path, as the system writes it
proc ::moderne::mesbases::copierChemin {f} {
  clipboard clear
  clipboard append [file nativename $f]
}

### Right click > Clean up the database (Yosha 2026-11-06): the games marked
### as deleted removed for good, from a Siby database (SCID's compaction)
### or a PGN file (rewritten without them); the database opened if needed
proc ::moderne::mesbases::nettoyerBase {f} {
  set b [slot $f]
  set c [sc_base current]
  if {!$b} {
    set ::file::discret 1
    catch {::file::Open [expr {[estPgn $f] ? $f : [file rootname $f]}]}
    set ::file::discret 0
    set b [slot $f]
  }
  if {!$b} {
    tk_messageBox -type ok -icon error -title Siby -message [T "Base impossible à ouvrir." "The database could not be opened."]
    return
  }
  if {[estCadenassee $b]} {
    catch {::file::SwitchToBase $c}
    tk_messageBox -type ok -icon info -title Siby -message [T "Base cadenassée : retire d'abord le cadenas." "The database is padlocked: remove the padlock first."]
    return
  }
  catch {::file::SwitchToBase $b}
  if {[sc_base isReadOnly $b] && ![info exists ::moderne::pgnfichier::fichier($b)]} {
    tk_messageBox -type ok -icon info -title Siby -message [T "Base en lecture seule : elle ne peut pas être nettoyée." "Read-only database: it cannot be cleaned up."]
  } else {
    # (one question, then done: a PGN file is rewritten without them, see
    # ::moderne::pgnfichier::compacter)
    if {[catch {::compactGames .} err]} {
      tk_messageBox -type ok -icon error -title Siby -message "[T "Nettoyage impossible" "Could not clean up"] : $err"
    }
  }
  if {$c != $b && [sc_base inUse $c]} { catch {::file::SwitchToBase $c} }
  remplir
}

### Converts database f: Siby database (.si4) -> PGN file, PGN file -> Siby
### database. dest: the new file (empty: asked, next to f). The new file gets
### its tile; returns it (empty if nothing was done).
proc ::moderne::mesbases::convertir {f {dest {}}} {
  set versPgn [expr {![estPgn $f]}]
  set racine [file rootname $f]
  if {[string match -nocase *.pgn.gz $f]} { set racine [file rootname $racine] }
  if {$dest eq {}} {
    if {$versPgn} {
      set types {{"PGN" {.pgn}}}
      set ext .pgn
    } else {
      set types {{"Siby databases" {.si4}}}
      set ext .si4
    }
    set dest [tk_getSaveFile -initialdir [file dirname $f] -initialfile [file tail $racine]$ext \
        -defaultextension $ext -filetypes [::utils::trTypesFichiers $types] \
        -title [expr {$versPgn ? [T "Convertir en PGN" "Convert to PGN"] : [T "Convertir en base Siby" "Convert to a Siby database"]}]]
    if {$dest eq {}} { return {} }
  }
  set courante [sc_base current]
  # a progress window with a Stop button (Gaby: 11 million games, several
  # minutes; without it Siby seemed frozen, Yosha 2026-11-01)
  progression [expr {$versPgn ? [T "Conversion en PGN" "Converting to PGN"] : [T "Conversion en base Siby" "Converting to a Siby database"]}] \
      "[file tail $f] → [file tail $dest]"
  busyCursor .
  set err [catch {
    if {$versPgn} {
      # the database, opened for the time of the export if it was not
      set b [slot $f]
      set ouverte [expr {$b > 0}]
      if {!$ouverte} { set b [sc_base open $racine] }
      sc_base switch $b
      sc_base export all PGN $dest -append 0 -starttext "" -endtext "" -comments 1 -variations 1 \
          -spaces 0 -symbols 0 -indentComments 0 -indentVariations 0 -column 0 -noMarkCodes 0 \
          -convertNullMoves 1 -newlines 1 -utf8 1 -bom 0 -noClocks [expr {!$::moderne::exportTemps}]
      set n [sc_base numGames $b]
      if {!$ouverte} { sc_base close $b }
    } else {
      set base [file rootname $dest]
      foreach e {.si4 .sg4 .sn4 .stc} { catch {file delete -force $base$e} }
      set b [sc_base create $base]
      sc_base import file $f
      set n [sc_base numGames $b]
      sc_base close $b
      set dest $base.si4
    }
  } msg]
  unbusyCursor .
  set arrete [finProgression]
  if {[sc_base inUse $courante]} { catch {sc_base switch $courante} }
  if {$err} {
    tk_messageBox -icon warning -type ok -title Siby -message "[T "Conversion impossible" "Conversion failed"] : $msg"
    return {}
  }
  if {$arrete} {
    tk_messageBox -icon info -type ok -title Siby -message [T \
        "Conversion arrêtée : le fichier ne contient que les parties déjà converties." \
        "Conversion stopped: the file holds only the games converted so far."]
  }
  if {[chemin $dest] ni [lmap x $::moderne::mesBases {chemin $x}]} { lappend ::moderne::mesBases $dest }
  catch {::moderne::nsb::annonce "$n [expr {$n == 1 ? [T "partie convertie" "game converted"] : [T "parties converties" "games converted"]}] : [file tail $dest]" -1}
  after 2500 {catch ::moderne::nsb::finAnnonce}
  after idle ::moderne::mesbases::remplir
  catch {refreshWindows all}
  return $dest
}

### A small window with a progress bar, the time and a Stop button
proc ::moderne::mesbases::progression {titre texte} {
  set p .progressionSiby
  catch {destroy $p}
  toplevel $p -background [::moderne::c fond] -padx 18 -pady 14
  wm title $p "Siby – $titre"
  wm transient $p .
  wm resizable $p 0 0
  ttk::label $p.t -text $titre -font font_Bold
  ttk::label $p.f -text $texte -foreground [::moderne::c texteDoux]
  canvas $p.c -width 360 -height 16 -highlightthickness 0 -borderwidth 0 -background [::moderne::c surface2]
  $p.c create rectangle 0 0 0 16 -fill [::moderne::c accent] -outline {} -tags bar
  $p.c create text 356 8 -anchor e -fill [::moderne::c texte] -font font_Small -tags temps
  ttk::button $p.stop -text [T "Arrêter" "Stop"] -command {set ::moderne::mesbases::arret 1 ; sc_progressBar}
  pack $p.t $p.f -side top -anchor w
  pack $p.c -side top -pady 10
  pack $p.stop -side top -anchor e
  catch {::moderne::repeindre $p}
  variable arret 0
  update idletasks
  catch {placeWinOverParent $p .}
  update
  sc_progressBar $p.c bar 361 17 temps
}

### Progress window closed; 1 if the user stopped
proc ::moderne::mesbases::finProgression {} {
  variable arret
  catch {sc_progressBar}
  catch {destroy .progressionSiby}
  set a [expr {[info exists arret] && $arret}]
  set arret 0
  return $a
}

proc ::moderne::mesbases::fermer {f} {
  set b [slot $f]
  if {$b} { catch {::file::Close $b} }
  after idle ::moderne::mesbases::remplir
}

proc ::moderne::mesbases::rechercher {f} {
  ouvrirBase $f
  set b [slot $f]
  if {$b} { catch {::file::SwitchToBase $b} ; catch {::moderne::rparties::ouvrir} }
}

proc ::moderne::mesbases::reference {f} {
  if {$f eq {}} { return }
  ouvrirBase $f
  set b [slot $f]
  if {!$b} { return }
  set ::moderne::biblio::base $b
  retenirReference $b
  # (the Preparation takes it as its Database 2 at once: it kept the
  # previous one, 2026-10-29)
  catch {set ::moderne::prepa::baseRef $b}
  catch ::moderne::prepa::majBases
  catch {set ::moderne::biblio::cache [dict create]}
  catch {::moderne::biblio::majBases}
  catch {::moderne::biblio::maj}
  after idle ::moderne::mesbases::remplir
}

### Clean PGN on a database of the view: the lines written in the
### comments become variations. A PGN file gives a new PGN file (next to
### it, added to the view); a Siby database is cleaned in place, from the
### Clean PGN window ("All games of the database").
proc ::moderne::mesbases::nettoyer {f} {
  variable w
  set p [::moderne::mesbases::parent]
  if {[estPgn $f]} {
    set racine [file rootname $f]
    if {[string match -nocase *.pgn.gz $f]} { set racine [file rootname $racine] }
    set dest [tk_getSaveFile -parent $p -initialdir [file dirname $f] \
        -initialfile "[file tail $racine] ([T variantes variations]).pgn" -defaultextension .pgn \
        -filetypes [::utils::trTypesFichiers {{"PGN" {.pgn}}}] -title [T "PGN nettoyé" "Cleaned PGN"]]
    if {$dest eq {}} { return }
    if {[chemin $dest] eq [chemin $f]} {
      tk_messageBox -parent $p -icon warning -type ok -title Siby -message [T \
          "Choisis un autre nom : le fichier d'origine est gardé tel quel." "Choose another name: the original file is kept as it is."]
      return
    }
    set courante [sc_base current]
    busyCursor .
    set err [catch {::moderne::cleanpgn::fichier $f $dest} r]
    unbusyCursor .
    if {[sc_base inUse $courante]} { catch {sc_base switch $courante} }
    if {$err} {
      tk_messageBox -parent $p -icon warning -type ok -title Siby -message "[T "Nettoyage impossible" "Cleaning failed"] : $r"
      return
    }
    lassign $r total modifiees var ign
    if {[chemin $dest] ni [lmap x $::moderne::mesBases {chemin $x}]} { lappend ::moderne::mesBases $dest }
    after idle ::moderne::mesbases::remplir
    tk_messageBox -parent $p -icon info -type ok -title Siby -message [T \
        "[file tail $dest] : $modifiees parties modifiées sur $total, $var coups ajoutés en variantes ($ign lignes ignorées)." \
        "[file tail $dest]: $modifiees of $total games changed, $var moves added as variations ($ign lines ignored)."]
    return
  }
  if {[cadenassee $f]} {
    tk_messageBox -parent $p -icon info -type ok -title Siby -message [T \
        "Cette base est cadenassée : retire d'abord le cadenas (clic droit) pour la modifier." \
        "This database is padlocked: remove the padlock first (right click) to change it."]
    return
  }
  set b [slot $f]
  if {$b} { catch {::file::SwitchToBase $b} } else { catch {::file::Open [file rootname $f]} }
  if {[file normalize [sc_base filename]] ne [file normalize [file rootname $f]]} { return }
  ::moderne::cleanpgn::dialogue
  set ::moderne::cleanpgn::portee base
  catch {wm title .cleanpgnWin "[T "Nettoyer" "Clean"] : [file tail [file rootname $f]]"}
}

### The window a dialog is attached to: My databases when it is on screen,
### else the main window. (The tile view's window exists but is hidden while
### the list view is shown: on Windows a dialog attached to it stayed
### invisible, « Add a database… » seemed to do nothing, Yosha 2026-11-13)
proc ::moderne::mesbases::parent {} {
  variable w
  if {[winfo exists $w] && [winfo viewable $w]} { return $w }
  set f [focus]
  if {$f ne {} && [winfo exists $f] && [winfo viewable $f]} { return [winfo toplevel $f] }
  return .
}

### Add a database… (several at once with Ctrl or Shift; dossier: put in
### that folder, Yosha 2026-11-05)
proc ::moderne::mesbases::ajouter {{dossier {}}} {
  variable w
  set fs [tk_getOpenFile -multiple 1 -parent [::moderne::mesbases::parent] -filetypes [list \
      [list [T "Bases Siby et PGN" "Siby and PGN databases"] {.si4 .pgn .PGN}] \
      [list [T "Bases Siby" "Siby databases"] {.si4}] [list PGN {.pgn .PGN}]]]
  if {![llength $fs]} { return }
  ajouterFichiers $fs $dossier
  return $fs
}

namespace eval ::moderne::mesbases { variable ajouts {} ; variable nAjouts 0 }

### Files fs added (into folder dossier when given)
proc ::moderne::mesbases::ajouterFichiers {fs {dossier {}}} {
  variable groupes
  variable ajouts
  # (first in their folder, whatever the sort, Yosha 2026-11-13: the last
  # added first, those added together in their order)
  set lot [incr ::moderne::mesbases::nAjouts]
  set i 0
  foreach f $fs {
    set f [chemin $f]
    dict set ajouts $f [expr {$lot * 100000 - [incr i]}]
    if {$f ni $::moderne::mesBases} { lappend ::moderne::mesBases $f }
    set ::moderne::basesRetirees [lsearch -all -inline -not -exact $::moderne::basesRetirees $f]
    if {$dossier ne {}} { dict set groupes $f $dossier }
  }
  if {$dossier ne {}} { creerDossier $dossier 0 }
  # (the folders holding them unfolded: added into a folded « Other
  # databases », or already there, nothing seemed to happen, Yosha
  # 2026-11-13)
  catch {deplierPour [lmap f $fs {chemin $f}]}
  remplir
  # (and scrolled to: a folder lower down stayed out of sight)
  if {[llength $fs]} { after idle [list after 0 [list catch [list ::moderne::mesbases::montrer [chemin [lindex $fs end]]]]] }
  catch ::options.write
}

### The folders (and their parents) holding databases fs unfolded
proc ::moderne::mesbases::deplierPour {fs} {
  variable replies
  foreach f $fs {
    set sec [groupe $f]
    if {$sec eq {}} { set sec [T "Autres bases" "Other databases"] }
    set replies [lsearch -all -inline -not -exact $replies $sec]
    # (a folder inside a folded one: its parents too)
    foreach r $replies { if {[string first "$r / " $sec] == 0} { set replies [lsearch -all -inline -not -exact $replies $r] } }
  }
}

proc ::moderne::mesbases::retirer {f} {
  # (the reference or Gaby removed: no longer the reference nor Gaby; another
  # Gaby, e.g. downloaded to another folder, takes over)
  oublierReference $f
  set ::moderne::mesBases [lsearch -all -inline -not -exact $::moderne::mesBases $f]
  if {$f ni $::moderne::basesRetirees} { lappend ::moderne::basesRetirees $f }
  remplir
  catch ::options.write
}

proc ::moderne::mesbases::oublierReference {f} {
  if {$::moderne::fichierReference ne {} && [chemin $::moderne::fichierReference] eq $f} {
    set ::moderne::fichierReference {}
  }
  if {$::moderne::gaby::fichier ne {} && [chemin $::moderne::gaby::fichier] eq $f} {
    set ::moderne::gaby::fichier {}
  }
}

proc ::moderne::mesbases::supprimer {f} {
  variable w
  set nom [file rootname [::moderne::nomBase $f]]
  if {[cadenassee $f]} {
    tk_messageBox -parent [::moderne::mesbases::parent] -icon info -type ok -title Siby -message [T \
        "« $nom » est cadenassée : lève le cadenas (clic droit) avant de la supprimer." \
        "\"$nom\" is padlocked: remove the padlock (right-click) before deleting it."]
    return
  }
  set gaby {}
  catch {set gaby [chemin [::moderne::gaby::trouverFichier]]}
  set msg [T "Supprimer la base « $nom » et toutes ses parties ? On ne peut pas revenir en arrière." \
      "Delete the database \"$nom\" and all its games? This cannot be undone."]
  if {$f eq $gaby} {
    append msg "\n\n" [T "C'est Gaby : il faudra la retélécharger (Outils › Gaby)." "This is Gaby: it will have to be downloaded again (Tools › Gaby)."]
  }
  if {[tk_messageBox -parent [::moderne::mesbases::parent] -icon warning -type yesno -default no -title Siby -message $msg] ne "yes"} { return }
  set b [slot $f]
  if {$b} { catch {::file::Close $b} }
  if {[slot $f]} { return }
  oublierReference $f
  if {[estPgn $f]} {
    catch {file delete -force $f}
  } else {
    set r [file rootname $f]
    foreach x {.si4 .sn4 .sg4 .sbl .online.sbl .ajouts.sbl .ajouts.online.sbl .sbp .sbc .maj.json .classical.sbl .classical.online.sbl .rapid.sbl .rapid.online.sbl .blitz.sbl .blitz.online.sbl .classical.ajouts.sbl .classical.ajouts.online.sbl .rapid.ajouts.sbl .rapid.ajouts.online.sbl .blitz.ajouts.sbl .blitz.ajouts.online.sbl} {
      catch {file delete -force $r$x}
    }
  }
  catch {::recentFiles::remove $f}
  set ::moderne::mesBases [lsearch -all -inline -not -exact $::moderne::mesBases $f]
  remplir
}

# (once: the reference's padlock put back, lifted on Yosha's Gaby without
# her knowing, 2026-11-09; a later deliberate unlock is kept)
if {![info exists ::moderne::cadenasRefRemis]} { set ::moderne::cadenasRefRemis 0 }
proc ::moderne::mesbases::remettreCadenasRef {} {
  if {$::moderne::cadenasRefRemis} { return }
  set ::moderne::cadenasRefRemis 1
  set r [fichierRef]
  if {$r ne {}} { set ::moderne::sansCadenas [lsearch -all -inline -not -exact $::moderne::sansCadenas $r] }
}

# (databases opened at start)
after 3000 {catch ::moderne::mesbases::remettreCadenasRef ; catch ::moderne::mesbases::appliquerCadenas}

### A database opened that is larger than the reference (or with no
### reference at all): offered as the reference, once per file
### (::moderne::refRefusees, saved: files offered and declined)
if {![info exists ::moderne::refRefusees]} { set ::moderne::refRefusees {} }
set ::moderne::mesbases::minRef 10000

proc ::moderne::mesbases::proposerReference {b} {
  variable minRef
  if {!$b || $b == [sc_info clipbase] || ![sc_base inUse $b]} { return 0 }
  set f [sc_base filename $b]
  if {[string match "*Siby live*" $f]} { return 0 }
  if {![catch {::moderne::enligne::estBaseEnLigne $f} oui] && $oui} { return 0 }
  set f [chemin $f]
  set ref [fichierRef]
  if {$f eq $ref || $f in $::moderne::refRefusees} { return 0 }
  set n [sc_base numGames $b]
  if {$n < $minRef} { return 0 }
  set nRef 0
  if {$ref ne {}} {
    set r [slot $ref]
    if {$r} {
      set nRef [sc_base numGames $r]
    } elseif {[catch {::moderne::enligne::nbParties $ref} nRef] || ![string is integer -strict $nRef]} {
      set nRef 0
    }
  }
  if {$n <= $nRef} { return 0 }
  ::moderne::prepa::proposerRef $b
  return 1
}

proc ::moderne::mesbases::refuserReference {b} {
  catch {destroy .prepaRef}
  if {![sc_base inUse $b]} { return }
  set f [chemin [sc_base filename $b]]
  if {$f ni $::moderne::refRefusees} { lappend ::moderne::refRefusees $f }
  catch ::options.write
}

### End Siby

### Siby: the reference database (Gaby, 13 million games: a few seconds)
### opened just after start-up, with its progress window, rather than at
### the first click on a broadcast game or a preparation, where the window
### froze without saying why (tests on the real Gaby, 2026-10-30)
proc ::moderne::mesbases::prechargerReference {} {
  if {[info exists ::env(SIBY_SANS_PRECHARGE)]} { return }
  set f {}
  catch {set f [fichierRef]}
  if {$f eq {} || ![file exists $f] || [slot $f]} { return }
  catch {baseReference}
}
# (not started automatically: opened at start-up it changed the current
# database while the game given on the command line was loading, the board
# then showed an empty game; tests of 2026-10-30)

### Ctrl+Shift+S (File › Save as…): the game saved in any database, Siby
### (.si4) or PGN, open or not, existing or new (Yosha, 2026-11-01: the
### menu of the open databases only was not enough). An existing file gets
### the game added; a new one is created; a database already open gets it
### through Siby (a PGN file open in Siby is rewritten by pgnfichier).
proc ::moderne::mesbases::enregistrerSous {} {
  variable dossierSous
  if {![info exists dossierSous] || ![file isdirectory $dossierSous]} {
    set dossierSous [file normalize ~]
    catch {set dossierSous [file dirname [sc_base filename [sc_base current]]]}
    if {![file isdirectory $dossierSous]} { set dossierSous [file normalize ~] }
  }
  set types [list [list [T "Base Siby" "Siby database"] {.si4}] [list [T "Fichier PGN" "PGN file"] {.pgn}] [list [T "Tous les fichiers" "All files"] *]]
  set opts [list -parent . -title [T "Enregistrer la partie dans…" "Save the game in…"] \
      -filetypes $types -defaultextension .si4 -initialdir $dossierSous]
  # (an existing file is not replaced: the game is added to it)
  if {[catch {set f [tk_getSaveFile {*}$opts -confirmoverwrite 0]}]} { set f [tk_getSaveFile {*}$opts] }
  if {$f eq {}} { return }
  set f [file normalize $f]
  set dossierSous [file dirname $f]
  set ext [string tolower [file extension $f]]
  if {$ext ni {.si4 .pgn}} { set f "[file rootname $f].si4" ; set ext .si4 }
  set b [slot $f]
  if {$b} { ::moderne::direct::enregistrerDans $b ; return }
  set pgn [::moderne::pgnAnglais]
  if {[catch {
    if {$ext eq ".pgn"} {
      set h [open $f a]
      fconfigure $h -encoding utf-8
      if {[file size $f] > 0} { puts $h {} }
      puts $h [string trim $pgn]
      puts $h {}
      close $h
      set tuile $f
    } else {
      set racine [file rootname $f]
      set courante [sc_base current]
      set nb [expr {[file exists $racine.si4] ? [sc_base open $racine] : [sc_base create $racine]}]
      set code [catch {
        sc_base switch $nb
        sc_game new
        sc_game import $pgn
        sc_game save 0
      } err]
      catch {sc_base close $nb}
      catch {sc_base switch $courante}
      if {$code} { error $err }
      set tuile $racine.si4
    }
  } err]} {
    tk_messageBox -icon error -type ok -title Siby -message "[T "Enregistrement impossible" "Could not save"] : $err"
    return
  }
  # (the file gets its tile in My databases)
  if {[chemin $tuile] ni [lmap x $::moderne::mesBases {chemin $x}]} { lappend ::moderne::mesBases $tuile }
  catch remplir
  catch {::windows::switcher::Refresh}
  catch {::windows::gamelist::Refresh}
  ::moderne::direct::annonceBreve "[T "Partie enregistrée dans" "Game saved in"] [file tail $tuile]"
}

################################################################################
### Sort and groups of the tiles (Yosha 2026-11-02). Saved; independent of
### where the files are: a group is a label Siby keeps, the file stays where
### it is. Gaby, the reference database and My Siby games stay first.
################################################################################

namespace eval ::moderne::mesbases {
  foreach {_v _d} {tri recent ouvertures {} groupes {} dossiers {} apercus {} replies {} filtre {} ordreDossiers {} suivis {} selection {} affiches {} compacts {}} {
    if {![info exists $_v]} { variable $_v $_d }
  }
  unset -nocomplain _v _d
}

proc ::moderne::mesbases::libelleTri {} {
  variable tri
  switch -- $tri {
    nom    { return [T "nom" "name"] }
    taille { return [T "nombre de parties" "number of games"] }
  }
  return [T "récemment ouvertes" "recently opened"]
}

### A database opened or brought to the front: remembered as opened now
proc ::moderne::mesbases::noterOuverture {args} {
  variable ouvertures
  if {[catch {sc_base filename [sc_base current]} f] || $f eq {}} { return }
  if {[sc_base current] == [sc_info clipbase]} { return }
  set f [chemin $f]
  dict set ouvertures $f [clock seconds]
  # (its first games, shown while it is closed)
  catch {apercu $f [sc_base current]}
}
foreach _c {::file::Open ::file::SwitchToBase} {
  catch {trace add execution $_c leave ::moderne::mesbases::noterOuverture}
}
unset -nocomplain _c

proc ::moderne::mesbases::groupe {f} {
  variable groupes
  return [expr {[dict exists $groupes $f] ? [dict get $groupes $f] : {}}]
}

### The folders: those holding databases, and the empty ones made with
### "New folder…" (kept until deleted)
proc ::moderne::mesbases::nomsGroupes {} {
  variable groupes
  variable dossiers
  set l {}
  dict for {f g} $groupes { if {$g ni $l} { lappend l $g } }
  foreach g $dossiers { if {$g ni $l} { lappend l $g } }
  # (a folder in a folder: its parents are folders too)
  foreach g $l {
    set p {}
    foreach morceau [lrange [morceaux $g] 0 end-1] {
      set p [expr {$p eq {} ? $morceau : "$p / $morceau"}]
      if {$p ni $l} { lappend l $p }
    }
  }
  return [lsort -command ::moderne::mesbases::compareDossiers $l]
}

proc ::moderne::mesbases::ranger {f g} {
  variable groupes
  variable dossiers
  # (a folder left empty stays: only "Delete the folder" removes it)
  set avant [groupe $f]
  if {$g eq {}} { dict unset groupes $f } else { dict set groupes $f $g }
  if {$avant ne {} && $avant ni [nomsGroupes]} { lappend dossiers $avant }
  remplir
  catch ::options.write
}

### An empty folder (right click on the page: New folder…)
proc ::moderne::mesbases::creerDossier {g {dessiner 1}} {
  variable dossiers
  if {$g ne {} && $g ni $dossiers} { lappend dossiers $g }
  if {!$dessiner} { return }
  remplir
  catch ::options.write
}

### A folder deleted: its databases go back out of it (the files stay)
proc ::moderne::mesbases::supprimerDossier {g} {
  variable groupes
  variable dossiers
  variable suivis
  variable ordreDossiers
  # (its folders too; their databases go back out of the folders)
  set dossiers [lmap x $dossiers {expr {[dedans $x $g] ? [continue] : $x}}]
  dict for {f x} $groupes { if {[dedans $x $g]} { dict unset groupes $f } }
  dict for {x p} $suivis { if {[dedans $x $g]} { dict unset suivis $x } }
  set ordreDossiers [lmap x $ordreDossiers {expr {[dedans $x $g] ? [continue] : $x}}]
  variable compacts
  set compacts [lmap x $compacts {expr {[dedans $x $g] ? [continue] : $x}}]
  remplir
  catch ::options.write
}

### Menu of the page (right click on an empty place) and of a folder
proc ::moderne::mesbases::menuPage {X Y {dossier {}} {cle {}}} {
  variable compacts
  set m .mesBasesMenuPage
  catch {destroy $m}
  ::menu $m -tearoff 0
  if {$cle ne {}} {
    # (the binder's view, kept for each binder)
    set ::moderne::mesbases::vueMenu [expr {$cle in $compacts ? "liste" : "grand"}]
    foreach {v fr en} {grand "Grandes icônes" "Large icons" liste "Liste" "List"} {
      $m add radiobutton -label [T $fr $en] -variable ::moderne::mesbases::vueMenu -value $v \
          -command [list after idle [list ::moderne::mesbases::changerVue $cle $v]]
    }
    $m add separator
  }
  if {$dossier ne {}} {
    # (a folder: what goes into it)
    $m add command -label [T "Ajouter des bases ici…" "Add databases here…"] -command [list after idle [list ::moderne::mesbases::ajouter $dossier]]
    $m add command -label [T "Ajouter un dossier de l'ordinateur ici…" "Add a folder from the computer here…"] \
        -command [list after idle [list ::moderne::mesbases::ajouterDossierDisque $dossier]]
    $m add command -label [T "Nouveau classeur dedans…" "New binder inside…"] -command [list after idle [list ::moderne::mesbases::nouveauGroupe {} $dossier]]
    $m add separator
    $m add command -label [T "Renommer le classeur…" "Rename the binder…"] -command [list after idle [list ::moderne::mesbases::renommerDossier $dossier]]
    $m add command -label [T "Supprimer le classeur « [nomCourt $dossier] » (les bases restent)" "Delete the binder \"[nomCourt $dossier]\" (the databases stay)"] \
        -command [list ::moderne::mesbases::supprimerDossier $dossier]
  } else {
    $m add command -label [T "Nouveau classeur…" "New binder…"] -command [list after idle [list ::moderne::mesbases::nouveauGroupe {}]]
    $m add separator
    $m add command -label [T "Ajouter des bases…" "Add databases…"] -command [list after idle ::moderne::mesbases::ajouter]
    $m add command -label [T "Ajouter un dossier de l'ordinateur… (ses bases et ses PGN, et ses sous-dossiers ; les nouveaux fichiers apparaissent tout seuls)" \
        "Add a folder from the computer… (its databases and PGN files, and its subfolders; new files appear by themselves)"] \
        -command [list after idle [list ::moderne::mesbases::ajouterDossierDisque {}]]
    $m add command -label [T "Nouvelle base…" "New database…"] -command {::file::New ; ::moderne::mesbases::remplir}
  }
  catch {::moderne::menubar::epurer $m}
  tk_popup $m $X $Y
}

### Drag a card onto a folder (its title or one of its cards), or out of
### the folders (the page, or a card outside any folder)
proc ::moderne::mesbases::glisserDebut {f X Y} {
  variable glisse
  variable selection
  # (a chosen card dragged: all the chosen ones)
  set qui [expr {$f in $selection ? $selection : [list $f]}]
  set glisse [list $qui $X $Y 0]
}

proc ::moderne::mesbases::glisserBouge {X Y} {
  variable glisse
  if {![info exists glisse] || $glisse eq {}} { return }
  lassign $glisse f x0 y0 actif
  if {!$actif} {
    if {abs($X - $x0) + abs($Y - $y0) < 8} { return }
    set glisse [list $f $x0 $y0 1]
    set j .mesBasesJeton
    catch {destroy $j}
    toplevel $j -background [::moderne::c accent]
    wm overrideredirect $j 1
    label $j.l -text [expr {[llength $f] > 1 ? [T "[llength $f] bases" "[llength $f] databases"] : [file rootname [::moderne::nomBase [lindex $f 0]]]}] -font font_Regular -padx 10 -pady 4 \
        -background [::moderne::c surface2] -foreground [::moderne::c texteFort]
    pack $j.l -padx 1 -pady 1
  }
  catch {wm geometry .mesBasesJeton +[expr {$X + 14}]+[expr {$Y + 10}]}
  variable cibleDossier
  set cibleDossier [dossierSous $X $Y]
  marquerDossier $cibleDossier
}

proc ::moderne::mesbases::glisserFin {X Y} {
  variable glisse
  variable cibleDossier
  if {![info exists glisse] || $glisse eq {}} { return 0 }
  lassign $glisse f x0 y0 actif
  set glisse {}
  catch {destroy .mesBasesJeton}
  marquerDossier none
  if {!$actif} { return 0 }
  set g [dossierSous $X $Y]
  if {$g eq "none"} { return 1 }
  set qui [lmap x $f {expr {[groupe $x] ne $g ? $x : [continue]}}]
  if {[llength $qui]} { after idle [list ::moderne::mesbases::rangerTous $qui $g] }
  return 1
}

### Folder under the pointer: its name, {} for "out of the folders", none
### outside the page
proc ::moderne::mesbases::dossierSous {X Y} {
  variable w
  variable titreDossier
  variable tuileFichier
  set x [winfo containing $X $Y]
  if {$x eq {} || ![string match $w.c* $x]} { return none }
  foreach s [array names titreDossier] {
    if {[string first "$s." "$x."] == 0} { return $titreDossier($s) }
  }
  foreach t [array names tuileFichier] {
    if {[string first "$t." "$x."] == 0} { return [groupe $tuileFichier($t)] }
  }
  return {}
}

### The folder title under the dragged card, in the accent colour
proc ::moderne::mesbases::marquerDossier {g} {
  variable titreDossier
  foreach s [array names titreDossier] {
    if {![winfo exists $s.n]} { continue }
    $s.n configure -foreground [expr {$titreDossier($s) eq $g ? [::moderne::c accent] : [::moderne::c texteFort]}]
  }
}

### Asks the name of a new group, then puts f in it
proc ::moderne::mesbases::nouveauGroupe {f {parent {}}} {
  variable parentNouveau $parent
  set d .mesBasesGroupe
  catch {destroy $d}
  toplevel $d
  wm title $d [T "Nouveau classeur" "New binder"]
  wm transient $d .
  set ::moderne::mesbases::saisie {}
  ttk::frame $d.f -padding 14
  pack $d.f -fill both -expand 1
  ttk::label $d.f.l -text [T "Nom :" "Name:"]
  ttk::entry $d.f.e -textvariable ::moderne::mesbases::saisie -width 30
  ttk::frame $d.f.b
  ttk::button $d.f.b.ok -text OK -command [list ::moderne::mesbases::finNouveauGroupe $f]
  ttk::button $d.f.b.annuler -text [T Annuler Cancel] -command [list destroy $d]
  pack $d.f.l -anchor w
  pack $d.f.e -fill x -pady 8
  pack $d.f.b -anchor e
  pack $d.f.b.annuler $d.f.b.ok -side right -padx {6 0}
  bind $d.f.e <Return> [list ::moderne::mesbases::finNouveauGroupe $f]
  bind $d <Escape> [list destroy $d]
  catch {::moderne::repeindre $d}
  catch {placeWinOverParent $d .}
  focus $d.f.e
}

proc ::moderne::mesbases::finNouveauGroupe {f} {
  variable parentNouveau
  set g [string trim [string map {/ -} $::moderne::mesbases::saisie]]
  catch {destroy .mesBasesGroupe}
  if {$g eq {}} { return }
  if {[info exists parentNouveau] && $parentNouveau ne {}} { set g "$parentNouveau / $g" }
  if {$f eq {}} { creerDossier $g } else { rangerTous $f $g }
}

### Number of games of tile f (for the sort), -1 if unknown
proc ::moderne::mesbases::nbPourTri {f} {
  set n -1
  catch {set n [::moderne::enligne::nbParties $f]}
  set b [slot $f]
  if {$b} { set n [sc_base numGames $b] } elseif {[estPgn $f]} { catch {set n [nbPgn $f]} }
  return [expr {[string is integer -strict $n] ? $n : -1}]
}

### The tiles in order: {file section ...}. First Gaby, the reference
### database and My Siby games (no title); then each group (its name as
### title); then the others ("Other databases" when there are groups)
proc ::moderne::mesbases::ordre {gaby ref} {
  variable tri
  variable ouvertures
  variable ajouts
  set tous [liste]
  set mesParties [chemin [file join $::sibyDocsDir "Siby games"].si4]
  set tete {}
  # (first: Gaby, the reference, My Siby games, unless put in a folder)
  foreach f [list $gaby $ref $mesParties] {
    if {$f ne {} && $f in $tous && $f ni $tete && [groupe $f] eq {}} { lappend tete $f }
  }
  set reste {}
  foreach f $tous { if {$f ni $tete} { lappend reste $f } }
  # sort keys
  set cles {}
  foreach f $reste {
    set nom [string tolower [file rootname [::moderne::nomBase $f]]]
    switch -- $tri {
      nom    { set k 0 }
      taille { set k [expr {-[nbPourTri $f]}] }
      default { set k [expr {[dict exists $ouvertures $f] ? -[dict get $ouvertures $f] : 0}] }
    }
    # (added in this session: first, the last added at the top)
    if {[dict exists $ajouts $f]} { set k [expr {-(1 << 50) - [dict get $ajouts $f]}] }
    lappend cles [list $k $nom $f]
  }
  set cles [lsort -index 1 -dictionary $cles]
  set cles [lsort -index 0 -integer $cles]
  set res {}
  foreach f $tete { lappend res $f {} }
  set groupesVus [nomsGroupes]
  foreach g $groupesVus {
    foreach c $cles { if {[groupe [lindex $c 2]] eq $g} { lappend res [lindex $c 2] $g } }
  }
  set autre [expr {[llength $groupesVus] ? [T "Autres bases" "Other databases"] : {}}]
  foreach c $cles { if {[groupe [lindex $c 2]] eq {}} { lappend res [lindex $c 2] $autre } }
  return $res
}

### Text cut to two lines of width l (in font police), "…" at the end of
### the second when it is longer (the full name: the tile's tooltip)
proc ::moderne::mesbases::deuxLignes {texte police l} {
  set lignes {}
  set ligne {}
  foreach m [split $texte " "] {
    set essai [expr {$ligne eq {} ? $m : "$ligne $m"}]
    if {$ligne ne {} && [font measure $police $essai] > $l} {
      lappend lignes $ligne
      set ligne $m
    } else {
      set ligne $essai
    }
  }
  if {$ligne ne {}} { lappend lignes $ligne }
  if {[llength $lignes] <= 2} { return $texte }
  set fin [lindex $lignes 1]
  while {$fin ne {} && [font measure $police "$fin…"] > $l} { set fin [string range $fin 0 end-1] }
  return "[lindex $lignes 0] [string trimright $fin]…"
}

################################################################################
### Several databases chosen (Ctrl+click, Shift+click), dragged or put away
### together; folders in folders ("Parent / Child"), renamed, put in order
### by dragging their title; a folder of the computer followed (its new
### files appear by themselves). Yosha 2026-11-05.
################################################################################

proc ::moderne::mesbases::estChoisie {f} {
  variable selection
  variable choisie
  return [expr {[info exists selection] && $f in $selection}]
}

proc ::moderne::mesbases::redessinerChoix {} {
  variable tuileFichier
  variable dessus
  foreach t [array names tuileFichier] {
    set d [expr {[info exists dessus($t)] && $dessus($t)}]
    catch {dessinerCarte $t $tuileFichier($t) $d}
    catch {surligner $t 0}
  }
}

### Ctrl+click: f added to the chosen ones, or taken out
proc ::moderne::mesbases::basculer {f} {
  variable selection
  variable choisie
  variable ancre
  if {$f eq {}} { return }
  if {$f in $selection} {
    set selection [lsearch -all -inline -not -exact $selection $f]
  } else {
    lappend selection $f
  }
  set choisie $f
  set ancre $f
  redessinerChoix
  catch {focus $::moderne::mesbases::w.c}
}

### Shift+click: every card from the anchor (the last one clicked) to f, in
### the order shown, instead of the chosen ones (ajouter: added to them)
proc ::moderne::mesbases::etendre {f {ajouter 0}} {
  variable selection
  variable choisie
  variable affiches
  variable ancre
  if {![info exists ancre] || $ancre ni $affiches} { set ancre $choisie }
  set a [lsearch -exact $affiches $ancre]
  set b [lsearch -exact $affiches $f]
  if {$a < 0 || $b < 0} { choisir $f ; return }
  if {$a > $b} { lassign [list $a $b] b a }
  if {!$ajouter} { set selection {} }
  foreach x [lrange $affiches $a $b] { if {$x ni $selection} { lappend selection $x } }
  set choisie $f
  redessinerChoix
  catch {focus $::moderne::mesbases::w.c}
}

proc ::moderne::mesbases::retirerSelection {} {
  variable selection
  foreach f $selection {
    if {$f ni $::moderne::basesRetirees} { lappend ::moderne::basesRetirees $f }
    set ::moderne::mesBases [lsearch -all -inline -not -exact $::moderne::mesBases $f]
  }
  set selection {}
  remplir
  catch ::options.write
}

proc ::moderne::mesbases::rangerTous {fs g} {
  variable groupes
  variable dossiers
  foreach f $fs {
    set avant [groupe $f]
    if {$g eq {}} { dict unset groupes $f } else { dict set groupes $f $g }
    if {$avant ne {} && $avant ni [nomsGroupes] && $avant ni $dossiers} { lappend dossiers $avant }
  }
  remplir
  catch ::options.write
}

### Right click on one of several chosen cards
proc ::moderne::mesbases::menuSelection {X Y} {
  variable selection
  set m .mesBasesMenu
  catch {destroy $m}
  ::menu $m -tearoff 0
  set n [llength $selection]
  set mg $m.groupes
  ::menu $mg -tearoff 0
  foreach nomG [nomsGroupes] {
    $mg add command -label "[string repeat "    " [profondeur $nomG]][nomCourt $nomG]" \
        -command [list after idle [list ::moderne::mesbases::rangerTous $selection $nomG]]
  }
  if {[llength [nomsGroupes]]} { $mg add separator }
  $mg add command -label [T "Nouveau classeur…" "New binder…"] \
      -command [list after idle [list ::moderne::mesbases::nouveauGroupe $selection]]
  $m add cascade -label [T "Déplacer les $n bases vers" "Move the $n databases to"] -menu $mg
  $m add command -label [T "Sortir du classeur" "Take out of the binder"] \
      -command [list after idle [list ::moderne::mesbases::rangerTous $selection {}]]
  $m add separator
  set ouvertes [lmap f $selection {expr {[slot $f] ? $f : [continue]}}]
  $m add command -label [T "Fermer" "Close"] -state [expr {[llength $ouvertes] ? "normal" : "disabled"}] \
      -command [list after idle [list apply {{fs} { foreach f $fs { catch {::moderne::mesbases::fermer $f} } }} $ouvertes]]
  $m add command -label [T "Retirer les $n icônes" "Remove the $n tiles"] -accelerator [T Suppr Del] \
      -command [list after idle ::moderne::mesbases::retirerSelection]
  tk_popup $m $X $Y
}

### Folders in folders: "Parent / Child"
proc ::moderne::mesbases::morceaux {g} {
  return [lmap x [split [string map [list " / " \x01] $g] \x01] {string trim $x}]
}
proc ::moderne::mesbases::nomCourt {g} { return [lindex [morceaux $g] end] }
proc ::moderne::mesbases::profondeur {g} {
  if {$g eq {} || $g eq [T "Autres bases" "Other databases"]} { return 0 }
  return [expr {[llength [morceaux $g]] - 1}]
}
### Is folder x folder g or inside it?
proc ::moderne::mesbases::dedans {x g} {
  return [expr {$x eq $g || [string first "$g / " $x] == 0}]
}
proc ::moderne::mesbases::aDesSousDossiers {g} {
  if {$g eq {}} { return 0 }
  foreach x [nomsGroupes] { if {$x ne $g && [dedans $x $g]} { return 1 } }
  return 0
}
### A folder inside a folded one
proc ::moderne::mesbases::dansReplie {g} {
  variable replies
  if {$g eq {}} { return 0 }
  foreach r $replies { if {$r ne $g && [string first "$r / " $g] == 0} { return 1 } }
  return 0
}
### Folders in order: each level in the order put by dragging (ordreDossiers),
### else by name; a folder's folders right after it
proc ::moderne::mesbases::compareDossiers {a b} {
  variable ordreDossiers
  set ma [morceaux $a] ; set mb [morceaux $b]
  set pa {} ; set pb {}
  for {set i 0} {$i < max([llength $ma], [llength $mb])} {incr i} {
    if {$i >= [llength $ma]} { return -1 }
    if {$i >= [llength $mb]} { return 1 }
    set pa [expr {$pa eq {} ? [lindex $ma $i] : "$pa / [lindex $ma $i]"}]
    set pb [expr {$pb eq {} ? [lindex $mb $i] : "$pb / [lindex $mb $i]"}]
    if {$pa eq $pb} { continue }
    set ra [lsearch -exact $ordreDossiers $pa] ; set rb [lsearch -exact $ordreDossiers $pb]
    if {$ra >= 0 && $rb >= 0} { return [expr {$ra < $rb ? -1 : 1}] }
    if {$ra >= 0} { return -1 }
    if {$rb >= 0} { return 1 }
    return [string compare -nocase [lindex $ma $i] [lindex $mb $i]]
  }
  return 0
}

### A folder's title: a click folds it, a drag puts it before another folder
proc ::moderne::mesbases::dossierDebut {g X Y} {
  variable glisseDossier
  set glisseDossier [list $g $X $Y 0]
}
proc ::moderne::mesbases::dossierBouge {X Y} {
  variable glisseDossier
  if {![info exists glisseDossier] || $glisseDossier eq {}} { return }
  lassign $glisseDossier g x0 y0 actif
  if {$g eq [T "Autres bases" "Other databases"] && $g ni [nomsGroupes]} { return }
  if {!$actif} {
    if {abs($X - $x0) + abs($Y - $y0) < 8} { return }
    set glisseDossier [list $g $x0 $y0 1]
    set j .mesBasesJeton
    catch {destroy $j}
    toplevel $j -background [::moderne::c accent]
    wm overrideredirect $j 1
    label $j.l -text "🗀 [nomCourt $g]" -font font_Bold -padx 10 -pady 4 \
        -background [::moderne::c surface2] -foreground [::moderne::c texteFort]
    pack $j.l -padx 1 -pady 1
  }
  catch {wm geometry .mesBasesJeton +[expr {$X + 14}]+[expr {$Y + 10}]}
  marquerDossier [titreSous $X $Y]
}
proc ::moderne::mesbases::dossierFin {X Y} {
  variable glisseDossier
  if {![info exists glisseDossier] || $glisseDossier eq {}} { return }
  lassign $glisseDossier g x0 y0 actif
  set glisseDossier {}
  catch {destroy .mesBasesJeton}
  marquerDossier none
  if {!$actif} { plier $g ; return }
  set cible [titreSous $X $Y]
  if {$cible ne {} && $cible ne "none" && ![dedans $cible $g]} { deplacerDossier $g $cible }
}
### The folder title under the pointer ({} if none)
proc ::moderne::mesbases::titreSous {X Y} {
  variable titreDossier
  set x [winfo containing $X $Y]
  if {$x eq {}} { return {} }
  foreach s [array names titreDossier] {
    if {[string first "$s." "$x."] == 0} { return $titreDossier($s) }
  }
  return {}
}
### Folder g (and its folders) put just before folder cible
proc ::moderne::mesbases::deplacerDossier {g cible} {
  variable ordreDossiers
  set l [nomsGroupes]
  set bloc [lmap x $l {expr {[dedans $x $g] ? $x : [continue]}}]
  set reste [lmap x $l {expr {[dedans $x $g] ? [continue] : $x}}]
  set i [lsearch -exact $reste $cible]
  set ordreDossiers [linsert $reste $i {*}$bloc]
  remplir
  catch ::options.write
}

### Rename a folder (its folders follow)
proc ::moderne::mesbases::renommerDossier {g} {
  set d .mesBasesGroupe
  catch {destroy $d}
  toplevel $d
  wm title $d [T "Renommer le classeur" "Rename the binder"]
  wm transient $d .
  set ::moderne::mesbases::saisie [nomCourt $g]
  ttk::frame $d.f -padding 14
  pack $d.f -fill both -expand 1
  ttk::label $d.f.l -text [T "Nom :" "Name:"]
  ttk::entry $d.f.e -textvariable ::moderne::mesbases::saisie -width 30
  ttk::frame $d.f.b
  ttk::button $d.f.b.ok -text OK -command [list ::moderne::mesbases::finRenommer $g]
  ttk::button $d.f.b.annuler -text [T Annuler Cancel] -command [list destroy $d]
  pack $d.f.l -anchor w
  pack $d.f.e -fill x -pady 8
  pack $d.f.b -anchor e
  pack $d.f.b.annuler $d.f.b.ok -side right -padx {6 0}
  bind $d.f.e <Return> [list ::moderne::mesbases::finRenommer $g]
  bind $d <Escape> [list destroy $d]
  catch {::moderne::repeindre $d}
  catch {placeWinOverParent $d .}
  $d.f.e selection range 0 end
  focus $d.f.e
}
proc ::moderne::mesbases::finRenommer {g} {
  set n [string trim [string map {/ -} $::moderne::mesbases::saisie]]
  catch {destroy .mesBasesGroupe}
  if {$n eq {}} { return }
  set m [morceaux $g]
  set nouveau [join [lreplace $m end end $n] " / "]
  renommer $g $nouveau
}
proc ::moderne::mesbases::renommer {g nouveau} {
  variable groupes
  variable dossiers
  variable replies
  variable ordreDossiers
  variable suivis
  if {$nouveau eq $g || $nouveau eq {}} { return }
  set changer [list apply {{x g n} { expr {[string first $g $x] == 0 && ($x eq $g || [string first "$g / " $x] == 0) ? "$n[string range $x [string length $g] end]" : $x} }}]
  set gr {}
  dict for {f x} $groupes { dict set gr $f [{*}$changer $x $g $nouveau] }
  set groupes $gr
  set dossiers [lmap x $dossiers {{*}$changer $x $g $nouveau}]
  set replies [lmap x $replies {{*}$changer $x $g $nouveau}]
  set ordreDossiers [lmap x $ordreDossiers {{*}$changer $x $g $nouveau}]
  variable compacts
  set compacts [lmap x $compacts {{*}$changer $x $g $nouveau}]
  set s {}
  dict for {x p} $suivis { dict set s [{*}$changer $x $g $nouveau] $p }
  set suivis $s
  remplir
  catch ::options.write
}

### A folder of the computer: a folder of the view with its databases and
### PGN files, its subfolders as folders inside it; followed: the files
### added there later appear by themselves (dans: the folder of the view it
### goes into)
proc ::moderne::mesbases::ajouterDossierDisque {{dans {}} {rep {}}} {
  variable w
  variable suivis
  if {$rep eq {}} {
    set rep [tk_chooseDirectory -parent [::moderne::mesbases::parent] -mustexist 1 \
        -title [T "Ajouter un dossier de l'ordinateur" "Add a folder from the computer"]]
  }
  if {$rep eq {} || ![file isdirectory $rep]} { return }
  set rep [file normalize $rep]
  set nom [string map {/ -} [file tail $rep]]
  set g [expr {$dans eq {} ? $nom : "$dans / $nom"}]
  dict set suivis $g $rep
  creerDossier $g 0
  # (added on purpose: its files shown again if their tiles were removed,
  # and put in this binder even if they were in another one)
  lireDossierDisque $g $rep 0 1
  synchroniser
  remplir
  catch ::options.write
}

### The followed folders read again: new files added in their folder, files
### gone taken out (at most 3 levels below and 500 files a folder)
proc ::moderne::mesbases::synchroniser {} {
  variable suivis
  variable groupes
  variable suivisNoms {}
  dict for {g rep} $suivis {
    if {![file isdirectory $rep]} { continue }
    lappend suivisNoms $g
    lireDossierDisque $g $rep 0
  }
  # (the files of a followed folder that are gone)
  dict for {f x} $groupes {
    foreach s $suivisNoms { if {[dedans $x $s] && ![file exists $f]} { dict unset groupes $f ; set ::moderne::mesBases [lsearch -all -inline -not -exact $::moderne::mesBases $f] } }
  }
}
### (expres: the folder just added by hand, see ajouterDossierDisque)
proc ::moderne::mesbases::lireDossierDisque {g rep niveau {expres 0}} {
  variable groupes
  set n 0
  # (one file once: Windows' glob ignores the case, *.pgn and *.PGN match
  # the same files)
  foreach f [lsort -unique [lmap x [glob -nocomplain -types f -directory $rep *.si4 *.pgn *.PGN *.pgn.gz] {chemin $x}]] {
    if {[incr n] > 500} { break }
    if {$expres} {
      set ::moderne::basesRetirees [lsearch -all -inline -not -exact $::moderne::basesRetirees $f]
      dict set groupes $f $g
    }
    # (a database taken out of the view by hand stays out)
    if {$f in $::moderne::basesRetirees} { continue }
    if {$f ni $::moderne::mesBases} { lappend ::moderne::mesBases $f }
    if {![dict exists $groupes $f]} { dict set groupes $f $g }
  }
  if {$niveau >= 3} { return }
  foreach d [lsort -dictionary [glob -nocomplain -types d -directory $rep *]] {
    if {[string match .* [file tail $d]]} { continue }
    # (a subfolder without any database: no folder in the view)
    if {![llength [glob -nocomplain -types f -directory $d *.si4 *.pgn *.PGN *.pgn.gz]] && ![llength [glob -nocomplain -types d -directory $d *]]} { continue }
    set sg "$g / [string map {/ -} [file tail $d]]"
    lireDossierDisque $sg $d [expr {$niveau + 1}] $expres
    if {$sg in [nomsGroupes]} { creerDossier $sg 0 }
  }
}

################################################################################
### Choosing several databases with the mouse and the keyboard, as in the
### file explorer (Yosha 2026-11-05): a press on one of the chosen cards
### keeps them all (dragged together; a click without moving keeps that
### one only); a frame drawn from an empty place; arrows, Shift+arrows,
### Ctrl+arrows and Ctrl+Space, Ctrl+A.
################################################################################

### Press on card f (mode: {} | ctrl | shift | ctrlshift)
proc ::moderne::mesbases::appui {f X Y mode} {
  variable selection
  variable differe {}
  switch -- $mode {
    ctrl {
      # (a chosen one is taken out on release, if it was not dragged)
      if {$f in $selection} { set differe [list basculer $f] } else { basculer $f }
    }
    shift     { etendre $f 0 }
    ctrlshift { etendre $f 1 }
    default {
      if {$f in $selection && [llength $selection] > 1} {
        set differe [list choisir $f]
      } else {
        choisir $f
      }
    }
  }
  glisserDebut $f $X $Y
}

proc ::moderne::mesbases::relache {X Y} {
  variable differe
  set glisse [glisserFin $X $Y]
  if {!$glisse && [info exists differe] && $differe ne {}} {
    ::moderne::mesbases::[lindex $differe 0] [lindex $differe 1]
  }
  set differe {}
}

### Card widget -> file and file -> card widget (cards shown)
proc ::moderne::mesbases::carteDe {f} {
  variable tuileFichier
  foreach t [array names tuileFichier] {
    if {$tuileFichier($t) eq $f && [winfo exists $t]} { return $t }
  }
  return {}
}

### The frame drawn from an empty place: the cards it touches are chosen
proc ::moderne::mesbases::lassoDebut {X Y ajouter} {
  variable lasso
  variable selection
  set lasso [list $X $Y 0 $ajouter [expr {$ajouter ? $selection : {}}]]
  catch {focus $::moderne::mesbases::w.c}
}

proc ::moderne::mesbases::lassoBouge {X Y} {
  variable lasso
  variable selection
  variable tuileFichier
  if {![info exists lasso] || $lasso eq {}} { return }
  lassign $lasso x0 y0 actif ajouter avant
  if {!$actif} {
    if {abs($X - $x0) + abs($Y - $y0) < 6} { return }
    lset lasso 2 1
    # (four thin windows over the cards, in the accent colour)
    foreach k {h b g d} {
      set j .mesBasesLasso$k
      catch {destroy $j}
      toplevel $j -background [::moderne::c accent] -borderwidth 0
      wm overrideredirect $j 1
      catch {wm attributes $j -topmost 1}
    }
  }
  # (inside the view)
  set c $::moderne::mesbases::w.c
  set cx [winfo rootx $c] ; set cy [winfo rooty $c]
  set X [expr {max($cx, min($X, $cx + [winfo width $c] - 1))}]
  set Y [expr {max($cy, min($Y, $cy + [winfo height $c] - 1))}]
  set xa [expr {min($x0, $X)}] ; set xb [expr {max($x0, $X)}]
  set ya [expr {min($y0, $Y)}] ; set yb [expr {max($y0, $Y)}]
  set lw [expr {max(1, $xb - $xa)}] ; set lh [expr {max(1, $yb - $ya)}]
  catch {wm geometry .mesBasesLassoh ${lw}x1+$xa+$ya}
  catch {wm geometry .mesBasesLassob ${lw}x1+$xa+$yb}
  catch {wm geometry .mesBasesLassog 1x${lh}+$xa+$ya}
  catch {wm geometry .mesBasesLassod 1x${lh}+$xb+$ya}
  # (the cards touched, in the order shown)
  set touchees {}
  foreach t [array names tuileFichier] {
    if {![winfo ismapped $t]} { continue }
    set tx [winfo rootx $t] ; set ty [winfo rooty $t]
    set tx1 [expr {$tx + [winfo width $t] - [ecart]}] ; set ty1 [expr {$ty + [winfo height $t] - [ecart]}]
    if {$tx1 >= $xa && $tx <= $xb && $ty1 >= $ya && $ty <= $yb} { lappend touchees $tuileFichier($t) }
  }
  set nouvelle $avant
  foreach f $touchees { if {$f ni $nouvelle} { lappend nouvelle $f } }
  if {$nouvelle ne $selection} {
    set selection $nouvelle
    variable choisie [lindex $selection end]
    variable ancre $choisie
    redessinerChoix
  }
}

proc ::moderne::mesbases::lassoFin {X Y} {
  variable lasso
  if {![info exists lasso] || $lasso eq {}} { return }
  lassign $lasso x0 y0 actif ajouter
  set lasso {}
  foreach k {h b g d} { catch {destroy .mesBasesLasso$k} }
  # (a click on an empty place: nothing chosen)
  if {!$actif && !$ajouter} { rienChoisir }
}

proc ::moderne::mesbases::rienChoisir {} {
  variable selection {}
  variable choisie {}
  redessinerChoix
}

proc ::moderne::mesbases::toutChoisir {} {
  variable affiches
  variable selection
  variable choisie
  if {![info exists affiches] || ![llength $affiches]} { return }
  set selection $affiches
  if {$choisie ni $affiches} { set choisie [lindex $affiches 0] }
  redessinerChoix
}

### Enter: the chosen database opened (one only)
proc ::moderne::mesbases::ouvrirChoix {} {
  variable selection
  variable choisie
  set f [expr {[llength $selection] == 1 ? [lindex $selection 0] : $choisie}]
  if {$f ne {} && $f in [liste]} { after idle [list ::moderne::mesbases::ouvrirBase $f] }
}

### Arrow keys (d: gauche droite haut bas debut fin; mode: {} | shift | ctrl):
### the card next to the current one; Shift: the ones from the anchor;
### Ctrl: the current one moves, nothing else changes
proc ::moderne::mesbases::fleche {d mode} {
  variable affiches
  variable choisie
  variable selection
  if {![info exists affiches] || ![llength $affiches]} { return }
  set i [lsearch -exact $affiches $choisie]
  if {$i < 0} {
    set cible [lindex $affiches 0]
  } else {
    set cible [voisine $choisie $d]
  }
  if {$cible eq {}} { return }
  switch -- $mode {
    shift { etendre $cible 0 }
    ctrl  { set choisie $cible ; redessinerChoix }
    default { choisir $cible }
  }
  montrer $cible
}

### The card next to f in direction d, in the grid as shown
proc ::moderne::mesbases::voisine {f d} {
  variable affiches
  set i [lsearch -exact $affiches $f]
  switch -- $d {
    gauche { return [expr {$i > 0 ? [lindex $affiches [expr {$i - 1}]] : {}}] }
    droite { return [lindex $affiches [expr {$i + 1}]] }
    debut  { return [lindex $affiches 0] }
    fin    { return [lindex $affiches end] }
  }
  # up and down: the nearest card of the row above or below, by its left side
  set t [carteDe $f]
  if {$t eq {}} { return {} }
  set x [winfo rootx $t] ; set y [winfo rooty $t]
  set meilleure {} ; set ligneM {} ; set ecartM {}
  foreach g $affiches {
    set u [carteDe $g]
    if {$u eq {} || $u eq $t} { continue }
    set yu [winfo rooty $u]
    if {$d eq "haut" ? $yu >= $y : $yu <= $y} { continue }
    set dy [expr {abs($yu - $y)}]
    set dx [expr {abs([winfo rootx $u] - $x)}]
    if {$ligneM eq {} || $dy < $ligneM || ($dy == $ligneM && $dx < $ecartM)} {
      set meilleure $g ; set ligneM $dy ; set ecartM $dx
    }
  }
  return $meilleure
}

### The view scrolled so that card f is seen
proc ::moderne::mesbases::montrer {f} {
  variable w
  set t [carteDe $f]
  if {$t eq {} || ![winfo exists $w.c]} { return }
  set c $w.c
  set h [winfo reqheight $c.g]
  if {$h <= 0} { return }
  set y0 [expr {[winfo rooty $t] - [winfo rooty $c.g]}] ; set y1 [expr {$y0 + [winfo height $t]}]
  lassign [$c yview] a b
  set vu0 [expr {$a * $h}] ; set vu1 [expr {$b * $h}]
  if {$y0 < $vu0} {
    $c yview moveto [expr {double($y0) / $h}]
  } elseif {$y1 > $vu1} {
    $c yview moveto [expr {double($y1 - ($vu1 - $vu0)) / $h}]
  }
}
