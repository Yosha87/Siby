###
### Siby: My profile (Options › My profile…)
###
### Who you are, entered once and used everywhere:
###   - name (as in the databases: "Iglesias, Yosha"), Lichess and Chess.com
###     accounts: your games open from your side (the board
###     turns round when you have Black; SCID's "my player names");
###   - your online games downloaded in one click;
###   - "Me" in the preparation (prepare against yourself);
###   - your White and Black repertoire databases, proposed by the
###     repertoire scan.
###

namespace eval ::moderne::profil {
  variable w .profilWin
}
foreach v {profilNom profilLichess profilChesscom profilAutres profilRepB profilRepN} {
  if {![info exists ::moderne::$v]} { set ::moderne::$v {} }
}

proc ::moderne::profil::T {fr en} { return [::moderne::tr $fr $en] }

### Names of the profile (for SCID's board turning)
proc ::moderne::profil::noms {} {
  set l {}
  foreach x [concat [list $::moderne::profilNom $::moderne::profilLichess $::moderne::profilChesscom] \
      [split $::moderne::profilAutres "\n"]] {
    set x [string trim $x]
    if {$x ne {} && $x ni $l} { lappend l $x }
  }
  return $l
}

### SCID's list follows the profile (names already there are kept)
proc ::moderne::profil::appliquer {} {
  foreach n [noms] {
    if {$n ni $::myPlayerNames} { lappend ::myPlayerNames $n }
  }
}

### First use: the profile takes SCID's names
proc ::moderne::profil::reprendre {} {
  if {$::moderne::profilNom eq {} && [llength $::myPlayerNames]} {
    set ::moderne::profilNom [lindex $::myPlayerNames 0]
    set ::moderne::profilAutres [join [lrange $::myPlayerNames 1 end] "\n"]
  }
}

proc ::moderne::profil::ouvrir {} {
  variable w
  if {[winfo exists $w]} { raiseWin $w ; return }
  reprendre
  catch {::moderne::jouer::defauts}
  ::moderne::jouer::polices
  set fond [::moderne::c fond]
  toplevel $w -background $fond
  wm title $w [T "Mon profil" "My profile"]
  wm resizable $w 0 0
  set f [frame $w.f -background $fond -padx 22 -pady 16]
  pack $f -fill both -expand 1
  # header: my photo (the silhouette when unknown), name
  frame $f.tete -background $fond
  pack $f.tete -side top -fill x
  set img {}
  catch {set img [::moderne::avatars::photo $::moderne::profilNom 64]}
  if {$img ne {}} {
    label $f.tete.photo -image $img -background $fond
    pack $f.tete.photo -side left -padx {0 12}
  }
  label $f.tete.t -text [T "Mon profil" "My profile"] -font SibyJouerTitre -background $fond \
      -foreground [::moderne::c texteFort] -anchor w
  label $f.tete.s -text [T "Pour te préparer contre toi-même, retrouver tes parties et jouer à ton niveau" \
      "To prepare against yourself, find your games and play at your level"] -font SibyJouerPetit \
      -background $fond -foreground [::moderne::c texteDoux] -anchor w
  pack $f.tete.t $f.tete.s -side top -anchor w

  # Me: name, rating, accounts
  set g [frame $f.g -background $fond]
  pack $g -side top -fill x
  champ $g.nom [T "Mon nom" "My name"] ::moderne::profilNom 30 \
      [T "Tel qu'il apparaît dans les bases : Nom, Prénom" "As it appears in the databases: Surname, First name"]
  catch {::moderne::suggestions::attacher $g.nom.e ::moderne::profil::suggestions ::moderne::profil::nomChoisi 1}
  champ $g.elo [T "Mon Elo" "My rating"] ::moderne::toby::jeu(eloMoi) 7 \
      [T "Celui de la fenêtre « Jouer » (Ton Elo)" "The one of the Play window (Your rating)"]
  champ $g.li [T "Compte Lichess" "Lichess account"] ::moderne::profilLichess 30 {}
  champ $g.cc [T "Compte Chess.com" "Chess.com account"] ::moderne::profilChesscom 18 {}
  grid $g.nom $g.elo -sticky new
  grid $g.li $g.cc -sticky new
  grid configure $g.nom $g.li -padx {0 16}
  grid columnconfigure $g 0 -weight 3
  grid columnconfigure $g 1 -weight 2

  # My repertoires: one card per colour
  ::moderne::jouer::section $f.lrep [T "Mes répertoires" "My repertoires"]
  frame $f.reps -background $fond
  pack $f.reps -side top -fill x
  set i 0
  foreach {var fr en} {profilRepB "Avec les Blancs" "With White" profilRepN "Avec les Noirs" "With Black"} {
    set c [frame $f.g$var -background [::moderne::c surface] -highlightthickness 1 \
        -highlightbackground [::moderne::c bordure] -padx 12 -pady 9]
    label $c.t -text [T $fr $en] -font font_Bold -background [::moderne::c surface] -foreground [::moderne::c texteFort] -anchor w
    label $c.n -text {} -background [::moderne::c surface] -foreground [::moderne::c texteDoux] -anchor w
    frame $c.b -background [::moderne::c surface]
    ttk::button $c.b.c -text [T "Choisir…" "Choose…"] -style Toolbutton -command [list ::moderne::profil::choisirRep $var]
    ttk::button $c.b.x -text × -width 2 -style Toolbutton -command "set ::moderne::$var {} ; ::moderne::profil::majReps"
    catch {::utils::tooltip::Set $c.b.x [T "Ne plus utiliser cette base" "Stop using this database"]}
    pack $c.b.c $c.b.x -side left
    pack $c.t $c.n $c.b -side top -anchor w
    grid $c -in $f.reps -row 0 -column $i -sticky nsew -padx [expr {$i ? "4 0" : "0 4"}]
    grid columnconfigure $f.reps $i -weight 1 -uniform reps
    incr i
  }
  majReps

  # actions
  set b [frame $w.b -background $fond -padx 22 -pady 14]
  pack $b -side bottom -fill x
  ttk::button $b.dl -text [T "Télécharger mes parties en ligne" "Download my online games"] -command ::moderne::profil::telecharger
  label $b.etat -background $fond -foreground [::moderne::c texteDoux]
  ttk::button $b.ok -text OK -command ::moderne::profil::fermer
  catch {$b.ok configure -style Accent.TButton}
  pack $b.dl -side left
  pack $b.ok -side right
  pack $b.etat -side left -padx 8
  bind $w <Escape> ::moderne::profil::fermer
  wm protocol $w WM_DELETE_WINDOW ::moderne::profil::fermer
  catch {placeWinCenter $w}
}

### A labelled entry
proc ::moderne::profil::champ {p titre var largeur tip} {
  frame $p -background [::moderne::c fond]
  ::moderne::jouer::section $p.l $titre 1
  pack $p.l -side top -fill x -pady {12 5}
  ttk::entry $p.e -width $largeur -textvariable $var
  pack $p.e -side top -fill x
  if {$tip ne {}} { catch {::utils::tooltip::Set $p.e $tip} }
}

proc ::moderne::profil::majReps {} {
  variable w
  foreach var {profilRepB profilRepN} {
    set f [set ::moderne::$var]
    catch {$w.f.g$var.n configure -text [expr {$f eq {} ? [T "(aucun)" "(none)"] : [file rootname [file tail $f]]}]}
  }
}

proc ::moderne::profil::choisirRep {var} {
  variable w
  set f [tk_getOpenFile -parent $w -title [T "Base de répertoire" "Repertoire database"] \
      -filetypes [list [list [T "Bases" "Databases"] {.si4 .pgn}]]]
  if {$f eq {}} { return }
  set ::moderne::$var [file normalize $f]
  majReps
}

proc ::moderne::profil::fermer {} {
  variable w
  foreach v {profilNom profilLichess profilChesscom} { set ::moderne::$v [string trim [set ::moderne::$v]] }
  appliquer
  catch {destroy $w}
}

### My online games, into the database of my name (as for a preparation)
proc ::moderne::profil::telecharger {} {
  variable w
  set nom [string trim $::moderne::profilNom]
  if {$nom eq {}} { catch {$w.b.etat configure -text [T "Indique d'abord ton nom." "Enter your name first."]} ; return }
  if {[string trim $::moderne::profilLichess] eq {} && [string trim $::moderne::profilChesscom] eq {}} {
    catch {$w.b.etat configure -text [T "Indique un compte Lichess ou Chess.com." "Enter a Lichess or Chess.com account."]}
    return
  }
  catch {$w.b.dl configure -state disabled}
  catch {$w.b.etat configure -text [T "Téléchargement…" "Downloading…"]}
  ::moderne::enligne::telecharger $nom $::moderne::profilLichess $::moderne::profilChesscom \
      ::moderne::profil::finTelechargement ::moderne::profil::progres
}

proc ::moderne::profil::progres {texte} {
  variable w
  catch {$w.b.etat configure -text $texte}
}

proc ::moderne::profil::finTelechargement {message nb} {
  variable w
  catch {$w.b.dl configure -state normal}
  set txt "[::utils::thousands $nb] [T "parties" "games"]"
  if {$message ne {}} { append txt " • $message" }
  catch {$w.b.etat configure -text $txt}
  if {$nb > 0} {
    set b [::moderne::enligne::base $::moderne::profilNom]
    if {$b} { catch {::file::SwitchToBase $b} }
  }
}

### Repertoire database of the profile for a colour (white / black), opened
### discreetly; 0 if none
proc ::moderne::profil::baseRepertoire {couleur} {
  set f [expr {$couleur eq "white" ? $::moderne::profilRepB : $::moderne::profilRepN}]
  if {$f eq {} || ![file exists $f]} { return 0 }
  set b [::moderne::mesbases::slot $f]
  if {$b} { return $b }
  set c [sc_base current]
  set ::file::discret 1
  catch {::file::Open [expr {[::moderne::mesbases::estPgn $f] ? $f : [file rootname $f]}]}
  set ::file::discret 0
  catch {::file::SwitchToBase $c}
  return [::moderne::mesbases::slot $f]
}

### At startup: SCID's names follow the profile
after 2000 {catch ::moderne::profil::appliquer}

### The names of Gaby (else of the reference database, else of the current
### one) for "My name", as in Prepare (Yosha 2026-11-04: they came from
### the database on the board, often none)
proc ::moderne::profil::base {} {
  set b -1
  catch {set b [::moderne::gaby::baseOuverte]}
  if {$b <= 0} { catch {set b $::moderne::prepa::baseRef} }
  if {![string is integer -strict $b] || $b <= 0 || ![sc_base inUse $b]} { set b [sc_base current] }
  return $b
}

proc ::moderne::profil::suggestions {texte} {
  if {[string length $texte] < 2} { return {} }
  set b [base]
  set courante [sc_base current]
  if {$courante != $b} { sc_base switch $b }
  set r {}
  catch {set r [::moderne::rparties::suggestions $texte]}
  if {$courante != $b} { sc_base switch $courante }
  return $r
}

### A name chosen: its FIDE rating and its online accounts (Gaby's table)
### filled in when known and still empty
proc ::moderne::profil::nomChoisi {nom} {
  set ::moderne::profilNom $nom
  set b [base]
  set id {}
  catch {set id [::moderne::fide::idNom $b $nom]}
  if {$id ne {}} {
    catch {
      set e [dict get [::moderne::fide::joueur $id] elo_std]
      if {[string is integer -strict $e] && $e > 0} { set ::moderne::toby::jeu(eloMoi) $e }
    }
  }
  catch {
    lassign [::moderne::enligne::comptesJoueur $nom $id] li cc
    if {[string trim $::moderne::profilLichess] eq {} && $li ne {}} { set ::moderne::profilLichess $li }
    if {[string trim $::moderne::profilChesscom] eq {} && $cc ne {}} { set ::moderne::profilChesscom $cc }
  }
}

