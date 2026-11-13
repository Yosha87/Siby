
###
### Siby: "Prepare against a player"
###
### A window that gathers what is needed to prepare for a game:
###   - the player's games in a database (e.g. Gaby), with
###     filters (since a given year, minimum opponent rating);
###   - their repertoire with White and with Black, as a tree
###     (moves, number of games, player's score, latest date);
###   - their games, most recent first, filtered on the chosen line;
###   - a button to show the position on the board and open the opening
###     tree of the reference database ("opening reference");
###   - export of the preparation to PGN (tree of their repertoire, with statistics).
###
### Nothing is modified in the databases: the database's filter is reset to
### its full state after the search.
###

namespace eval ::moderne::prepa {
  variable w .prepaWin
  # Settings (remembered for the session)
  variable joueur {}
  variable base 0          ;# database number (slot) to search in
  variable baseRef 0       ;# reference database for the opening tree
  variable depuis {}       ;# minimum year (empty = all)
  variable eloMin 0        ;# minimum opponent rating (0 = no filter)
  variable cadence {}      ;# {} (all), classical, rapid or blitz: flag 1/2/3 or "Cadence" header
  variable eloRef 0        ;# minimum rating of both players in the reference (0 = all)
  # Results
  variable parties {}      ;# list of dicts, one per game
  variable sN              ;# sN(node), sG, sD, sP, sDer: games, wins, draws, losses, latest (see stat)
  variable enfants         ;# enfants(node) = list of moves
  variable fils            ;# fils(node,move) = child node
  variable racine          ;# racine(color) = root node (see noeud)
  variable cheminNoeud     ;# cheminNoeud(tree,item) = {color path}
  variable filtreLigne {}  ;# {color path}: line chosen for the Games tab
  # Library (tab that follows the board): index of the positions of the player's games
  variable dGen 0          ;# generation of the arrays below (named idx_<dGen>...)
  variable indexCpp 0      ;# 1: the index is in C++ (sc_prepa), not in the arrays
  variable idx             ;# idx(color,key,move) = {n wins draws losses latest} (see idxIci)
  variable idxCoups        ;# idxCoups(color,key) = the moves played there
  variable idxElos         ;# idxElos(color,key,move) = list of {rating opponentRating score}
  variable idxParties      ;# idxParties(color,key) = list of {gnum ply}
  variable partieDe        ;# partieDe(gnum) = dict of the game
  variable biblioCouleur white  ;# white or black (their side, as on Lichess's Player tab)
  variable pliesBiblio 60  ;# plies indexed per game
  # Online games (Lichess, Chess.com: tcl/moderne/enligne.tcl)
  variable enLigne 1       ;# (old setting, replaced by source)
  variable source base     ;# the player's games: base | lichess | chesscom | toutes
  variable compteLichess {}
  variable compteChesscom {}
  array set stat {}
  array set enfants {}
  array set cheminNoeud {}
}

proc ::moderne::prepa::T {fr en} { return [::moderne::tr $fr $en] }

### List of open databases: {slot label} ...
### Default database: the current one, unless it is the empty clipbase (case
### of a layout restored before the databases are opened): then the largest
### open database
proc ::moderne::prepa::baseParDefaut {} {
  set b [sc_base current]
  if {$b != [sc_info clipbase]} { return $b }
  # current clipbase: the first open database (usually database 1)
  for {set i 1} {$i <= [sc_base count total]} {incr i} {
    if {$i == [sc_info clipbase] || ![sc_base inUse $i]} { continue }
    return $i
  }
  return $b
}

### Default reference database: Siby's reference database (Gaby unless
### another was chosen, ::moderne::mesbases) when it is open, else the
### largest open database (neither the clipbase nor "Siby live"), else b
proc ::moderne::prepa::refParDefaut {b} {
  set f {}
  catch {set f [::moderne::mesbases::fichierRef]}
  if {$f ne {}} {
    set r 0
    catch {set r [::moderne::mesbases::slot $f]}
    if {$r} { return $r }
  }
  set max -1 ; set r 0
  for {set i 1} {$i <= [sc_base count total]} {incr i} {
    if {$i == [sc_info clipbase] || ![sc_base inUse $i] || [estLive $i]} { continue }
    if {[sc_base numGames $i] > $max} { set max [sc_base numGames $i] ; set r $i }
  }
  return [expr {$r ? $r : $b}]
}

proc ::moderne::prepa::estLive {b} {
  string match "*Siby live" [sc_base filename $b]
}

### A database has just been opened (it is the current one):
### - if the preparation was still searching the clipbase, it switches to a
###   real database;
### - Siby's reference database (Gaby by default) becomes the reference;
### - a database larger than the reference: offered as the reference
proc ::moderne::prepa::baseOuverte {} {
  variable base
  variable baseRef
  set ouverte [sc_base current]
  if {!$base || ![sc_base inUse $base] || $base == [sc_info clipbase]} {
    set ancienne $base
    set base [refParDefaut 0]
    if {!$base} { set base [baseParDefaut] }
    if {$baseRef == $ancienne} { set baseRef 0 }
  }
  catch {::moderne::mesbases::proposerReference $ouverte}
  refAuto
  catch majBases
}

### The reference ("All games", the reference games): always Siby's
### reference database (Gaby by default), open; no Database 2 to choose
### any more (Yosha, 2026-11-01: "All games = all the reference's games")
### (ouvrir 1: opened if it is not, only when the preparation opens;
### otherwise only looked up among the open databases: a database being
### opened must not open the 6 GB reference too)
proc ::moderne::prepa::refAuto {{ouvrir 0}} {
  variable baseRef
  set r 0
  catch {
    set fr [::moderne::mesbases::fichierRef]
    if {$fr ne {}} {
      set r [expr {$ouvrir ? [::moderne::mesbases::baseReference 0] : [::moderne::mesbases::slot $fr]}]
    }
  }
  if {!$r || [catch {sc_base inUse $r} u] || !$u || [estLive $r]} { set r 0 }
  if {$r} { set baseRef $r ; return }
  # (no reference database: what was set stays, if still open)
  if {![refActive] || [estLive $baseRef]} { set baseRef 0 }
}

### Notice at the bottom right: use the larger database b as the reference?
proc ::moderne::prepa::proposerRef {b} {
  set w .prepaRef
  catch {destroy $w}
  set nom [::moderne::nomBase [sc_base filename $b]]
  frame $w -background [::moderne::c surface2] -highlightthickness 1 \
      -highlightbackground [::moderne::c accent] -padx 14 -pady 10
  label $w.t -background [::moderne::c surface2] -foreground [::moderne::c texteFort] \
      -font font_Regular -justify left -wraplength 380 -text [T \
      "Utiliser $nom ([::utils::thousands [sc_base numGames $b]] parties) comme base de référence ?" \
      "Use $nom ([::utils::thousands [sc_base numGames $b]] games) as the reference database?"]
  frame $w.b -background [::moderne::c surface2]
  ttk::button $w.b.ok -text [T "Utiliser" "Use it"] -command [list ::moderne::prepa::choisirRef $b]
  catch {$w.b.ok configure -style Accent.TButton}
  ttk::button $w.b.non -text [T "Non merci" "No thanks"] -command [list ::moderne::mesbases::refuserReference $b]
  pack $w.b.non $w.b.ok -side right -padx {6 0}
  pack $w.t -side top -anchor w -pady {0 6}
  pack $w.b -side top -fill x
  place $w -in . -relx 1.0 -rely 1.0 -x -18 -y -18 -anchor se
  raise $w
  # (it goes away by itself)
  after 20000 [list catch [list destroy $w]]
}

proc ::moderne::prepa::choisirRef {b} {
  variable baseRef
  catch {destroy .prepaRef}
  if {![sc_base inUse $b]} { return }
  set baseRef $b
  # (also Siby's reference database: opening library, padlock)
  catch {::moderne::mesbases::retenirReference $b}
  catch {::moderne::mesbases::remplir}
  catch {set ::moderne::biblio::base $b ; ::moderne::biblio::majBases}
  catch majBases
}

### The more recent of two SCID dates, ignoring unknown dates
### ("????.??.??"); "2024.??.??" counts as 2024.00.00.
proc ::moderne::prepa::plusRecente {a b} {
  if {![regexp {^[0-9]{4}} $a]} { return $b }
  if {![regexp {^[0-9]{4}} $b]} { return $a }
  if {[string compare [string map {? 0} $a] [string map {? 0} $b]] >= 0} { return $a }
  return $b
}

### Open databases {slot label ...}. pourRef: the list of Database 2,
### with the players' downloaded online games too (Yosha, 2026-10-31)
proc ::moderne::prepa::bases {{pourRef 0}} {
  set res {}
  for {set i 1} {$i <= [sc_base count total]} {incr i} {
    if {![sc_base inUse $i]} { continue }
    if {$i == [sc_info clipbase]} {
      set nom [T "Presse-papier" "Clipbase"]
    } elseif {![catch {::moderne::enligne::estBaseEnLigne [sc_base filename $i]} oui] && $oui} {
      # (the online games: Database 1 takes them with "Their games")
      if {!$pourRef} { continue }
      set nom "[T "En ligne" "Online"] : [::moderne::nomBase [sc_base filename $i]]"
    } else {
      set nom [::moderne::nomBase [sc_base filename $i]]
    }
    lappend res $i "$i : $nom ([::utils::thousands [sc_base numGames $i]])"
  }
  return $res
}

### Reference database open (0: none; see refAuto)
proc ::moderne::prepa::refActive {} {
  variable baseRef
  expr {[string is integer -strict $baseRef] && $baseRef > 0 && ![catch {sc_base inUse $baseRef} u] && $u}
}

proc ::moderne::prepa::libelleBase {slot} {
  if {$slot == 0} { return [T "0 : aucune" "0 : none"] }
  foreach {i lib} [bases 1] { if {$i == $slot} { return $lib } }
  foreach {i lib} [bases] { if {$i == $slot} { return $lib } }
  return {}
}

proc ::moderne::prepa::slotDepuisLibelle {lib} {
  # ("1 : Gaby": the number without the space, else "g1 _123" game ids
  # that no click could open, Yosha 2026-10-31)
  return [string trim [lindex [split $lib :] 0]]
}

################################################################################
### Window
################################################################################

### From the menu: the "Preparation" layout (large board, engines below,
### the preparation on the right), unless the window is already open
proc ::moderne::prepa::ouvrirDisposition {} {
  variable w
  if {![winfo exists $w] && [::moderne::actif] && $::docking::USE_DOCKING} {
    ::moderne::disposition::preparation
    if {[winfo exists $w]} { catch {::createToplevel $w} ; return }
  }
  ouvrir
}

proc ::moderne::prepa::ouvrir {} {
  variable w
  variable base
  variable baseRef
  # Database 1: Siby's reference database (Gaby), opened if needed;
  # the reference ("All games"): Siby's reference database (refAuto)
  # (also when Database 1 was never chosen by hand and the reference is
  # not open yet: Gaby added while another database was open, Yosha
  # 2026-10-31)
  variable baseChoisie
  if {![info exists baseChoisie]} { set baseChoisie 0 }
  set refOuverte 1
  catch {
    set fr [::moderne::mesbases::fichierRef]
    if {$fr ne {} && ![::moderne::mesbases::slot $fr]} { set refOuverte 0 }
  }
  if {!$base || ![sc_base inUse $base] || $base == [sc_info clipbase] || [estLive $base] || (!$baseChoisie && !$refOuverte)} {
    set r 0
    catch {
      # (not while Gaby is still read in the background: it comes by
      # itself, ::moderne::mesbases::referencePrete; 2026-11-06)
      if {[::moderne::mesbases::fichierRef] ne {}} { set r [::moderne::mesbases::baseReference 0] }
    }
    if {$r && [sc_base inUse $r] && ![estLive $r]} { set base $r } else { set base [refParDefaut 0] }
    if {!$base} { set base [baseParDefaut] }
  }
  refAuto 1

  if {[winfo exists $w]} {
    ::createToplevel $w
    catch majBases
    focus $w.haut.joueur
    return
  }
  # "Dockable" window: tab of the main window (SCID's docking
  # mode) or separate window
  ::createToplevel $w
  ::setTitle $w [T "Se préparer contre un adversaire" "Prepare against a player"]

  ### Row 1: player, databases
  set h $w.haut
  ttk::frame $h -padding {10 8 10 2}
  pack $h -side top -fill x
  ttk::label $h.lj -text [T "Joueur·se :" "Player:"]
  ttk::combobox $h.joueur -width 24 -textvariable ::moderne::prepa::joueur
  ttk::label $h.lb -text [T "Base :" "Database:"]
  ttk::combobox $h.base -width 22 -state readonly
  ttk::label $h.lr -text [T "Base 2 :" "Database 2:"]
  ttk::combobox $h.ref -width 22 -state readonly
  foreach x [list $h.lb $h.base] {
    catch {::utils::tooltip::Set $x [T "Base où chercher ses parties (son répertoire, sa fiche)" \
        "Database searched for their games (their repertoire, their profile)"]}
  }
  foreach x [list $h.lr $h.ref] {
    catch {::utils::tooltip::Set $x [T "Base 2 : la référence, ce qui se joue en général dans chaque position" \
        "Database 2: the reference, what is generally played in each position"]}
  }
  # (the min. Elo of the reference games: behind the settings gear)
  set f $w.filtres
  ttk::frame $f -padding {10 0 10 6}
  ttk::label $f.ler -text [T "Elo min. (référence) :" "Min. Elo (reference):"]
  ttk::spinbox $f.eloref -width 7 -from 0 -to 3000 -increment 100 -textvariable ::moderne::prepa::eloRef \
      -command {::moderne::prepa::majReference ; ::moderne::prepa::majBiblio}
  bind $f.eloref <Return> {::moderne::prepa::majReference ; ::moderne::prepa::majBiblio}
  catch {::utils::tooltip::Set $f.eloref [T "Elo minimal des parties de la référence (« Toutes les parties »)" \
      "Minimum Elo of the reference games (\"All games\")"]}
  # (no "Prepare" or "Me" button: the search starts as soon as a player is
  # chosen or a filter changes, as on Lichess; Yosha, 2026-10-30)
  # (player and database on one row: the space goes to the tables, Yosha
  # 2026-11-04; no Database 2 field: the reference is Siby's reference
  # database)
  grid $h.lj $h.joueur $h.lb $h.base -padx 4 -pady 2 -sticky w
  grid columnconfigure $h 5 -weight 1

  ### Row 2: the time control, always there, and the settings gear (the
  ### other filters, seldom changed, behind it)
  pack $f -side top -fill x
  ttk::label $f.ld -text [T "Depuis l'année :" "Since year:"]
  ttk::spinbox $f.depuis -width 6 -from 1850 -to 2100 -textvariable ::moderne::prepa::depuis
  ttk::label $f.le -text [T "Elo adverse min. :" "Min. opponent Elo:"]
  ttk::spinbox $f.elo -width 6 -from 0 -to 3000 -increment 100 -textvariable ::moderne::prepa::eloMin
  # Time control: "Cadence" header (classical / rapid / blitz) filled in by
  # Gaby. Databases without this header yield nothing with this filter.
  ttk::label $f.lc -text [T "Cadence :" "Time control:"]
  # (5 buttons: all, blitz, rapid, slow, correspondence)
  ::moderne::cadence::barre $f.cadence ::moderne::prepa::cadence ::moderne::prepa::cadenceChangee \
      {set ::moderne::prepa::base}
  ttk::button $f.reg -text "⚙" -style Toolbutton -command ::moderne::prepa::basculerReglages
  catch {::utils::tooltip::Set $f.reg [T "Réglages : Elo minimum de la référence, depuis l'année, Elo adverse minimum" \
      "Settings: reference minimum Elo, since year, minimum opponent Elo"]}
  grid $f.lc $f.cadence $f.reg -row 0 -padx 4 -pady 1 -sticky w
  # (in a frame of their own: shown, they do not move the row above)
  ttk::frame $f.plus
  grid $f.plus -row 1 -column 0 -columnspan 8 -sticky w
  # (the width it needs goes to a last, empty column, not to the time
  # control's label)
  grid columnconfigure $f 7 -weight 1
  grid $f.ler $f.eloref $f.ld $f.depuis $f.le $f.elo -in $f.plus -row 0 -padx 4 -pady 1 -sticky w
  foreach x {ler eloref ld depuis le elo} { raise $f.$x $f.plus }
  ::moderne::prepa::afficherReglages
  foreach x [list $f.depuis $f.elo] {
    $x configure -command ::moderne::prepa::relancer
    bind $x <Return> ::moderne::prepa::relancer
    bind $x <FocusOut> ::moderne::prepa::relancer
  }

  ### Online games (Lichess, Chess.com)
  set e $w.enligne
  ttk::frame $e -padding {10 0 10 6}
  pack $e -side top -fill x
  ttk::label $e.l -text [T "En ligne :" "Online:"]
  ttk::label $e.ll -text Lichess
  ttk::entry $e.li -width 16 -textvariable ::moderne::prepa::compteLichess
  ttk::label $e.lc -text Chess.com
  ttk::entry $e.cc -width 16 -textvariable ::moderne::prepa::compteChesscom
  ttk::button $e.dl -text [T "Télécharger ses parties" "Download their games"] -command ::moderne::prepa::telechargerEnLigne
  # The player's games: those of the database, Lichess, Chess.com, or all
  set style Toolbutton
  if {![catch {ttk::style layout Segment.Toolbutton} l] && $l ne {}} { set style Segment.Toolbutton }
  ttk::frame $e.src
  ttk::label $e.src.l -text [T "Ses parties :" "Their games:"]
  pack $e.src.l -side left -padx {0 4}
  foreach {val fr en} {base Base Database lichess Lichess Lichess chesscom Chess.com Chess.com toutes Toutes All} {
    ttk::radiobutton $e.src.$val -text [T $fr $en] -style $style -variable ::moderne::prepa::source -value $val \
        -command ::moderne::prepa::lancer
    pack $e.src.$val -side left -padx 1
  }
  ttk::label $e.etat -foreground gray50 -text {}
  grid $e.l $e.ll $e.li $e.lc $e.cc $e.dl -padx 3 -pady 1 -sticky w
  grid x $e.src - - $e.etat - -padx 3 -pady 1 -sticky w

  ### Summary: the photo, the FIDE title and the champions' gold piece (as
  ### on the board of the broadcasts), then the text (Yosha 2026-11-06: no
  ### title for a FIDE player outside the photos pack)
  ttk::frame $w.tete
  pack $w.tete -side top -fill x
  ttk::label $w.photoJ -padding {12 2 0 6}
  label $w.titreJ -font font_Bold -foreground #d59020 -background [::moderne::c fond] -padx 0 -pady 2
  ttk::label $w.championJ -padding {0 2 0 0}
  ttk::label $w.resume -padding {6 2 12 6} -font font_Bold \
      -text [T "Tape le nom de la personne (les premières lettres suffisent) et choisis-la dans la liste." \
                "Type the player's name (first letters are enough) and pick it in the list."]
  pack $w.photoJ $w.titreJ $w.championJ -in $w.tete -side left -anchor n
  pack $w.resume -in $w.tete -side left -anchor n -fill x -expand 1

  ### Tabs
  set nb $w.nb
  ttk::notebook $nb
  pack $nb -side top -fill both -expand 1 -padx 10

  # Player profile (ChessMonitor style)
  ttk::frame $nb.fiche
  $nb add $nb.fiche -text [T "Fiche" "Profile"]
  ::moderne::fiche::creer $nb.fiche


  # Library that follows the board (ChessBase style)
  set fr $nb.biblio
  ttk::frame $fr
  $nb add $fr -text [T "Bibliothèque" "Library"]
  ttk::frame $fr.h
  ttk::label $fr.h.l -text [T "Ses coups :" "Their moves:"]
  set style Toolbutton
  if {![catch {ttk::style layout Segment.Toolbutton} l] && $l ne {}} { set style Segment.Toolbutton }
  ttk::radiobutton $fr.h.blancs -style $style -variable ::moderne::prepa::biblioCouleur -value white -command ::moderne::prepa::majBiblio
  ttk::radiobutton $fr.h.noirs -style $style -variable ::moderne::prepa::biblioCouleur -value black -command ::moderne::prepa::majBiblio
  pack $fr.h.l -side left -padx 4
  pack $fr.h.blancs $fr.h.noirs -side left -padx 1
  pack $fr.h -side top -fill x -pady {4 0}
  ttk::label $fr.pos -font font_Bold -padding {6 4} -text {}
  pack $fr.pos -side top -fill x
  ttk::label $fr.ref -padding {6 0} -text {}
  pack $fr.ref -side top -fill x
  ttk::panedwindow $fr.pw -orient vertical
  pack $fr.pw -side top -fill both -expand 1
  ttk::frame $fr.pw.h
  ttk::frame $fr.pw.b
  $fr.pw add $fr.pw.h -weight 3
  $fr.pw add $fr.pw.b -weight 2
  ::moderne::biblio::creerTablePrepa $fr.pw.h.t
  ttk::scrollbar $fr.pw.h.sb -command [list $fr.pw.h.t yview]
  $fr.pw.h.t configure -yscrollcommand [list ::moderne::tableau::defilement $fr.pw.h.t $fr.pw.h.sb]
  pack $fr.pw.h.sb -side right -fill y
  pack $fr.pw.h.t -side left -fill both -expand 1
  # At the bottom: the player's games through the position | reference games
  ttk::notebook $fr.pw.b.nb
  pack $fr.pw.b.nb -fill both -expand 1
  set o $fr.pw.b.nb.lui
  ttk::frame $o
  $fr.pw.b.nb add $o -text [T "Ses parties" "Their games"]
  ttk::label $fr.pw.b.titre -padding {2 4 2 2} -text {}
  pack $fr.pw.b.titre -in $o -side top -anchor w
  creerListe $fr.pw.b.t
  $fr.pw.b.t configure -height 6
  bind $fr.pw.b.t <ButtonRelease-1> {::moderne::prepa::clicPartie %W %x %y ::moderne::prepa::chargerPartieBiblio}
  bind $fr.pw.b.t <Return> {::moderne::prepa::chargerPartieBiblio %W ; break}
  # (hovered: the game's next moves on one line, the board following the
  # pointer, as in Analysis' library)
  ::moderne::biblio::installerSurvolParties $fr.pw.b.t ::moderne::prepa::base ::moderne::prepa::chargerPartieBiblio
  ttk::scrollbar $fr.pw.b.sb -command [list $fr.pw.b.t yview]
  $fr.pw.b.t configure -yscrollcommand [list $fr.pw.b.sb set]
  pack $fr.pw.b.sb -in $o -side right -fill y
  pack $fr.pw.b.t -in $o -side left -fill both -expand 1
  set o $fr.pw.b.nb.ref
  ttk::frame $o
  $fr.pw.b.nb add $o -text [T "Parties de la référence" "Reference games"]
  ::moderne::biblio::creerListeParties $o.t
  ttk::scrollbar $o.sb -command [list $o.t yview]
  $o.t configure -yscrollcommand [list $o.sb set]
  pack $o.sb -side right -fill y
  pack $o.t -side left -fill both -expand 1
  bind $o.t <ButtonRelease-1> {::moderne::prepa::clicPartie %W %x %y ::moderne::prepa::chargerPartieRef}
  bind $o.t <Return> {::moderne::prepa::chargerPartieRef %W ; break}
  ::moderne::biblio::installerSurvolParties $o.t ::moderne::prepa::baseRef
  # (the explanation in a bubble under an ⓘ is gone: a bubble popping up
  # when the pointer went by, Yosha 2026-11-06; no explanations in the
  # interface)
  bind $nb <<NotebookTabChanged>> ::moderne::prepa::majBiblio
  ::moderne::biblio::abonner ::moderne::prepa::majBiblio
  bind $w <Destroy> [list ::moderne::biblio::fermeture %W $w ::moderne::prepa::majBiblio]
  foreach {couleur titre} [list white [T "Arbre Blancs" "Tree as White"] \
                                black [T "Arbre Noirs" "Tree as Black"]] {
    set fr $nb.$couleur
    ttk::frame $fr
    $nb add $fr -text $titre
    # Above: their repertoire; below: the reference database at the chosen
    # position (one above the other: the columns have the whole width)
    ttk::panedwindow $fr.pw -orient vertical
    pack $fr.pw -fill both -expand 1
    ttk::frame $fr.pw.g
    ttk::frame $fr.pw.d
    $fr.pw add $fr.pw.g -weight 3
    $fr.pw add $fr.pw.d -weight 2
    set fr $fr.pw.g
    creerArbre $fr.t $couleur
    ttk::scrollbar $fr.sb -command [list $fr.t yview]
    $fr.t configure -yscrollcommand [list $fr.sb set]
    pack $fr.sb -side right -fill y
    pack $fr.t -side left -fill both -expand 1
    creerPanneauRef $nb.$couleur.pw.d
  }
  set fr $nb.parties
  ttk::frame $fr
  $nb add $fr -text [T "Parties" "Games"]
  ttk::frame $fr.info
  ttk::label $fr.info.l -textvariable ::moderne::prepa::texteFiltre
  ttk::button $fr.info.tout -text [T "Toutes ses parties" "All games"] \
      -command {set ::moderne::prepa::filtreLigne {} ; ::moderne::prepa::remplirParties}
  pack $fr.info.l -side left -padx 4 -pady 4
  pack $fr.info.tout -side right -padx 4 -pady 4
  pack $fr.info -side top -fill x
  creerListe $fr.t
  # (the hover line, as in the other game lists; Yosha 2026-11-08)
  ::moderne::biblio::installerSurvolParties $fr.t ::moderne::prepa::base ::moderne::prepa::chargerPartie debut
  ttk::scrollbar $fr.sb -command [list $fr.t yview]
  $fr.t configure -yscrollcommand [list $fr.sb set]
  pack $fr.sb -side right -fill y
  pack $fr.t -side left -fill both -expand 1
  # the notation: the same window as in Analysis, brought here while this
  # tab is in front (Yosha 2026-11-06: an opened game's moves seen without
  # going to Analysis)
  ttk::frame $nb.notation
  $nb add $nb.notation -text [T "Notation" "Notation"]
  bind $nb <<NotebookTabChanged>> +::moderne::prepa::suivreNotation
  bind $nb.notation <Configure> ::moderne::prepa::placerNotation
  bind $nb.notation <Map> {after idle ::moderne::prepa::suivreNotation}

  ### Filling the database lists
  majBases
  bind $h.base <<ComboboxSelected>> {
    set ::moderne::prepa::base [::moderne::prepa::slotDepuisLibelle [%W get]]
    set ::moderne::prepa::baseChoisie 1
    ::moderne::prepa::relancer
  }
  bind $h.ref <<ComboboxSelected>> {
    set ::moderne::prepa::baseRef [::moderne::prepa::slotDepuisLibelle [%W get]]
    ::moderne::prepa::relancer
  }
  bind $h.base <Button-1> {+::moderne::prepa::majBases}
  bind $h.ref <Button-1> {+::moderne::prepa::majBases}

  ### Name completion
  # Clickable list of players while typing
  ::moderne::suggestions::attacher $h.joueur ::moderne::prepa::suggestions ::moderne::prepa::joueurChoisi 1
  bind $h.joueur <<ComboboxSelected>> {::moderne::prepa::nomChoisi}
  bind $h.joueur <Return> {::moderne::prepa::lancer}
  bind $w <Escape> [list ::moderne::echap $w]

  catch {::moderne::repeindre $w}
  ::createToplevelFinalize $w
  focus $h.joueur
}

proc ::moderne::prepa::majBases {} {
  variable w
  variable base
  variable baseRef
  # (the same list for both, Yosha 2026-10-31: none, then every open
  # database; Database 1 is Gaby by default; the reference, no longer
  # chosen here, is Siby's reference database)
  set libs [list [libelleBase 0]]
  foreach {i lib} [bases 1] { lappend libs $lib }
  $w.haut.base configure -values $libs
  $w.haut.ref configure -values $libs
  if {$base != 0 && ([catch {sc_base inUse $base} u] || !$u)} { set base [sc_base current] }
  refAuto
  $w.haut.base set [libelleBase $base]
  $w.haut.ref set [libelleBase $baseRef]
}

### Repertoire tree (hierarchical ttk::treeview)
proc ::moderne::prepa::creerArbre {t couleur} {
  ttk::treeview $t -columns {n pct score nulles derniere} -selectmode browse
  $t heading #0 -text [T "Coups" "Moves"] -anchor w
  $t heading n -text [T "Parties" "Games"]
  $t heading pct -text [T "Fréq." "Freq."]
  $t heading score -text [T "Score" "Score"]
  $t heading nulles -text [T "Nulles" "Draws"]
  $t heading derniere -text [T "Dernière fois" "Last played"]
  $t column #0 -width 260 -stretch 1
  foreach c {n pct nulles} { $t column $c -width 90 -anchor e -stretch 0 }
  $t column score -width 130 -anchor e -stretch 0
  $t column derniere -width 120 -anchor center -stretch 0
  ::moderne::tri::activer $t
  # The player's moves are highlighted; the opponent's are more discreet
  $t tag configure joueur -font font_Bold
  $t tag configure adversaire -foreground [expr {[::moderne::actif] && $::moderne::theme eq "sombre" ? "#a9a6a2" : "#555555"}]
  bind $t <<TreeviewOpen>> [list ::moderne::prepa::deplier $t $couleur]
  bind $t <<TreeviewSelect>> [list ::moderne::prepa::selection $t $couleur]
  bind $t <Motion> {+::moderne::prepa::survolArbre %W %x %y}
  bind $t <Leave> {+catch {::moderne::biblio::flecheSurvol {}}}
  bind $t <Double-Button-1> {::moderne::prepa::voirPosition ; break}
}

### Game list
proc ::moderne::prepa::creerListe {t} {
  ttk::treeview $t -columns {date couleur adversaire elo resultat eco tournoi debut} \
      -show headings -selectmode browse
  foreach {c fr en largeur ancre} {
    date       Date        Date       105 center
    couleur    Couleur     Colour      70 center
    adversaire Adversaire  Opponent   170 w
    elo        Elo         Elo         55 e
    resultat   Résultat    Result      70 center
    eco        ECO         ECO         50 center
    tournoi    Tournoi     Event      170 w
    debut      Ouverture   Opening    260 w
  } {
    $t heading $c -text [T $fr $en]
    $t column $c -width $largeur -anchor $ancre -stretch [expr {$c in {tournoi debut adversaire}}]
  }
  ::moderne::tri::activer $t
  $t tag configure gain  -foreground [expr {[::moderne::actif] && $::moderne::theme eq "sombre" ? "#8fcf8f" : "#2e7d32"}]
  $t tag configure perte -foreground [expr {[::moderne::actif] && $::moderne::theme eq "sombre" ? "#ef8f7f" : "#b23a2a"}]
  bind $t <ButtonRelease-1> {::moderne::prepa::clicPartie %W %x %y ::moderne::prepa::chargerPartie}
  bind $t <Return> {::moderne::prepa::chargerPartie %W}
}

### Completion: suggests names starting with the typed text, with their number of games
proc ::moderne::prepa::completer {touche} {
  variable w
  variable base
  if {$touche in {Return Up Down Escape Tab}} { return }
  set texte [$w.haut.joueur get]
  if {[string length $texte] < 2 || ![sc_base inUse $base]} { return }
  set courante [sc_base current]
  if {$courante != $base} { sc_base switch $base }
  catch {set res [sc_name match -souple player $texte 20]}
  if {$courante != $base} { sc_base switch $courante }
  if {![info exists res]} { return }
  set valeurs {}
  foreach {n nom} $res { lappend valeurs "$nom  ([::utils::thousands $n])" }
  $w.haut.joueur configure -values $valeurs
}

### A name typed or picked from the list, without the count of games the
### list adds after two spaces ("Carlsen, M  (9 193)"): a namesake's mark
### ("Szabo, Laszlo (4)") or a year ("Fischer, R (1943)") stays
proc ::moderne::prepa::nettoyerSaisie {nom} {
  regsub "\\s\\s+\\(\[0-9 .,\u00a0\u202f\]+\\)\$" $nom {} nom
  return $nom
}

### The database's spelling of player nom: nom itself if the database has
### it, else the most played name equal to it without accents and case
proc ::moderne::prepa::nomDansBase {nom b} {
  if {[string first * $nom] >= 0 || [string first ? $nom] >= 0} { return $nom }
  if {!$b || ![sc_base inUse $b]} { return $nom }
  set courante [sc_base current]
  if {$courante != $b} { sc_base switch $b }
  set r {}
  catch {set r [sc_name match -souple player $nom 50]}
  if {$courante != $b} { sc_base switch $courante }
  set cible [::moderne::plier $nom]
  foreach {n x} $r {
    if {$x eq $nom} { return $nom }
  }
  foreach {n x} $r {
    if {[::moderne::plier $x] eq $cible} { return $x }
  }
  return $nom
}

### A text without accents nor case, as sc_name match -souple compares
### names ("Iglésias" and "IGLESIAS" give "iglesias")
proc ::moderne::plier {texte} {
  variable plierTable
  if {![info exists plierTable]} {
    set plierTable [list \u00c0 a \u00c1 a \u00c2 a \u00c3 a \u00c4 a \u00c5 a \u00c6 ae \u00c7 c \u00c8 e \u00c9 e \u00ca e \u00cb e \u00cc i \u00cd i \u00ce i \u00cf i \u00d0 d \u00d1 n \u00d2 o \u00d3 o \u00d4 o \u00d5 o \u00d6 o \u00d8 o \u00d9 u \u00da u \u00db u \u00dc u \u00dd y \u00de th \u00df ss \u00e0 a \u00e1 a \u00e2 a \u00e3 a \u00e4 a \u00e5 a \u00e6 ae \u00e7 c \u00e8 e \u00e9 e \u00ea e \u00eb e \u00ec i \u00ed i \u00ee i \u00ef i \u00f0 d \u00f1 n \u00f2 o \u00f3 o \u00f4 o \u00f5 o \u00f6 o \u00f8 o \u00f9 u \u00fa u \u00fb u \u00fc u \u00fd y \u00fe th \u00ff y \u0100 a \u0101 a \u0102 a \u0103 a \u0104 a \u0105 a \u0106 c \u0107 c \u0108 c \u0109 c \u010a c \u010b c \u010c c \u010d c \u010e d \u010f d \u0110 d \u0111 d \u0112 e \u0113 e \u0114 e \u0115 e \u0116 e \u0117 e \u0118 e \u0119 e \u011a e \u011b e \u011c g \u011d g \u011e g \u011f g \u0120 g \u0121 g \u0122 g \u0123 g \u0124 h \u0125 h \u0128 i \u0129 i \u012a i \u012b i \u012c i \u012d i \u012e i \u012f i \u0130 i \u0131 i \u0132 ij \u0133 ij \u0134 j \u0135 j \u0136 k \u0137 k \u0139 l \u013a l \u013b l \u013c l \u013d l \u013e l \u013f l \u0140 l \u0141 l \u0142 l \u0143 n \u0144 n \u0145 n \u0146 n \u0147 n \u0148 n \u0149 n \u014c o \u014d o \u014e o \u014f o \u0150 o \u0151 o \u0152 oe \u0153 oe \u0154 r \u0155 r \u0156 r \u0157 r \u0158 r \u0159 r \u015a s \u015b s \u015c s \u015d s \u015e s \u015f s \u0160 s \u0161 s \u0162 t \u0163 t \u0164 t \u0165 t \u0168 u \u0169 u \u016a u \u016b u \u016c u \u016d u \u016e u \u016f u \u0170 u \u0171 u \u0172 u \u0173 u \u0174 w \u0175 w \u0176 y \u0177 y \u0178 y \u0179 z \u017a z \u017b z \u017c z \u017d z \u017e z \u017f s \u01a0 o \u01a1 o \u01af u \u01b0 u \u01c4 dz \u01c5 dz \u01c6 dz \u01c7 lj \u01c8 lj \u01c9 lj \u01ca nj \u01cb nj \u01cc nj \u01cd a \u01ce a \u01cf i \u01d0 i \u01d1 o \u01d2 o \u01d3 u \u01d4 u \u01d5 u \u01d6 u \u01d7 u \u01d8 u \u01d9 u \u01da u \u01db u \u01dc u \u01de a \u01df a \u01e0 a \u01e1 a \u01e6 g \u01e7 g \u01e8 k \u01e9 k \u01ea o \u01eb o \u01ec o \u01ed o \u01f0 j \u01f1 dz \u01f2 dz \u01f3 dz \u01f4 g \u01f5 g \u01f8 n \u01f9 n \u01fa a \u01fb a \u0200 a \u0201 a \u0202 a \u0203 a \u0204 e \u0205 e \u0206 e \u0207 e \u0208 i \u0209 i \u020a i \u020b i \u020c o \u020d o \u020e o \u020f o \u0210 r \u0211 r \u0212 r \u0213 r \u0214 u \u0215 u \u0216 u \u0217 u \u0218 s \u0219 s \u021a t \u021b t \u021e h \u021f h \u0226 a \u0227 a \u0228 e \u0229 e \u022a o \u022b o \u022c o \u022d o \u022e o \u022f o \u0230 o \u0231 o \u0232 y \u0233 y]
  }
  return [string map $plierTable [string tolower $texte]]
}

### Player suggestions for the typed text: {label name}…; "Yosha
### Iglesias" also searches for "Iglesias, Yosha"
proc ::moderne::prepa::suggestions {texte} {
  variable base
  if {![sc_base inUse $base]} { return {} }
  # Attempts: the text as is (start of the name); "First Last": the last
  # word as the start of the name, the other words having to be in the name
  set essais [list [list $texte {}]]
  if {[string first , $texte] < 0 && [llength $texte] >= 2} {
    lappend essais [list [lindex $texte end] [lrange $texte 0 end-1]]
    lappend essais [list [lindex $texte 0] [lrange $texte 1 end]]
  }
  set courante [sc_base current]
  if {$courante != $base} { sc_base switch $base }
  set vus {}
  set res {}
  foreach essai $essais {
    lassign $essai debut autres
    set r {}
    # (many names: sorted afterwards by number of games)
    catch {set r [sc_name match -souple player $debut 500]}
    foreach {n nom} $r {
      if {$nom in $vus} { continue }
      set ok 1
      foreach mot $autres {
        if {[string first [::moderne::plier $mot] [::moderne::plier $nom]] < 0} { set ok 0 ; break }
      }
      if {!$ok} { continue }
      lappend vus $nom
      lappend res [list $n $nom]
    }
  }
  if {$courante != $base} { sc_base switch $courante }
  # The player with the most games first
  set liste {}
  foreach e [lrange [lsort -integer -decreasing -index 0 $res] 0 24] {
    lassign $e n nom
    # (all the games of the database, online ones included: the
    # preparation then counts those over the board)
    lappend liste [list "$nom   ([::utils::thousands $n] [T "parties dans la base" "games in the database"])" $nom]
  }
  return $liste
}

proc ::moderne::prepa::joueurChoisi {nom} {
  variable joueur
  set joueur $nom
  lancer
}

### Downloads the player's online games, then restarts the preparation
proc ::moderne::prepa::telechargerEnLigne {} {
  variable w
  variable joueur
  variable compteLichess
  variable compteChesscom
  set nom [nomJoueur]
  if {$nom eq {}} {
    $w.enligne.etat configure -text [T "Tape d'abord le nom de la personne." "Type the player's name first."]
    return
  }
  if {[string trim $compteLichess] eq {} && [string trim $compteChesscom] eq {}} {
    $w.enligne.etat configure -text [T "Indique son compte Lichess et/ou Chess.com." "Enter their Lichess and/or Chess.com account."]
    return
  }
  $w.enligne.dl configure -state disabled
  $w.enligne.etat configure -text [T "Téléchargement…" "Downloading…"]
  ::moderne::enligne::telecharger $nom $compteLichess $compteChesscom ::moderne::prepa::finEnLigne \
      ::moderne::prepa::progresEnLigne
}

### Lichess / Chess.com / All buttons: enabled if the player's online games
### have been downloaded
proc ::moderne::prepa::majSources {} {
  variable w
  set bl 0
  catch {set bl [::moderne::enligne::base [nomJoueur]]}
  foreach v {lichess chesscom toutes} {
    catch {$w.enligne.src.$v configure -state [expr {$bl > 0 ? "normal" : "disabled"}]}
  }
}

proc ::moderne::prepa::progresEnLigne {texte} {
  variable w
  catch {$w.enligne.etat configure -text "[T "Téléchargement" "Downloading"] • $texte"}
}

proc ::moderne::prepa::finEnLigne {message nb} {
  variable w
  variable enLigne
  if {![winfo exists $w]} { return }
  $w.enligne.dl configure -state normal
  set txt "[::utils::thousands $nb] [T "parties en ligne (blitz, rapide, classique)" "online games (blitz, rapid, classical)"]"
  if {$message ne {}} { append txt " • $message" }
  $w.enligne.etat configure -text $txt
  # (the player's online games stay separate: "Games: Lichess /
  # Chess.com / All" choice to see them)
  if {$nb > 0} { majSources ; lancer }
}

### Player name for the online games: the exact name found in the
### database (the most frequent) if the preparation was run, otherwise the typed name
proc ::moderne::prepa::nomJoueur {} {
  variable joueur
  variable parties
  set noms {}
  foreach p $parties { if {![dict get $p enligne]} { dict incr noms [dict get $p nom] } }
  set nom [string trim $joueur]
  set nom [nettoyerSaisie $nom]
  set best 0
  dict for {n c} $noms { if {$c > $best} { set best $c ; set nom $n } }
  return [string trim $nom "* "]
}

proc ::moderne::prepa::nomChoisi {} {
  variable w
  variable joueur
  # "Carlsen, M  (9 193)" -> "Carlsen, M" (the count after two spaces: a
  # namesake's mark, "Szabo, Laszlo (4)", or a year, "(1974)", stays)
  set joueur [nettoyerSaisie [$w.haut.joueur get]]
  lancer
}

################################################################################
### Search and computations
################################################################################

### Escapes the special characters of a "string match" pattern
proc ::moderne::prepa::echapperMotif {s} {
  return [string map {\\ \\\\ * \\* ? \\? [ \\[ ] \\]} $s]
}

### Converts "1.e4 e5 2.Nf3" into the list {e4 e5 Nf3}
proc ::moderne::prepa::coupsSan {texte} {
  set res {}
  foreach tok $texte {
    regsub {^[0-9]+\.+} $tok {} tok
    if {$tok eq {} || [regexp {^(1-0|0-1|1/2-1/2|\*)$} $tok]} { continue }
    lappend res $tok
  }
  return $res
}

### Score from the player's point of view: 1 win, 0.5 draw, 0 loss, {} unknown
proc ::moderne::prepa::scoreJoueur {resultat couleur} {
  switch -- $resultat {
    1-0 { return [expr {$couleur eq "white" ? 1 : 0}] }
    0-1 { return [expr {$couleur eq "black" ? 1 : 0}] }
    =-= - 1/2 - 1/2-1/2 - = { return 0.5 }
  }
  return {}
}

### Time control changed: the player's games are read again with that
### time control (their moves, score and overperformance follow it), and the
### reference too
### A filter or a database changed: the search again (a player chosen,
### once the changes stop for half a second; nothing if nothing changed)
proc ::moderne::prepa::relancer {} {
  catch marquerReglages
  after cancel ::moderne::prepa::relancerMaintenant
  after 500 ::moderne::prepa::relancerMaintenant
}

proc ::moderne::prepa::relancerMaintenant {} {
  variable joueur
  variable base
  variable baseRef
  variable depuis
  variable eloMin
  variable dernierLancer
  if {[string trim $joueur] eq {}} { return }
  if {[info exists dernierLancer] && $dernierLancer eq [list [string trim $joueur] $base $baseRef $depuis $eloMin]} { return }
  lancer
}

proc ::moderne::prepa::cadenceChangee {} {
  variable parties
  if {[llength $parties]} { lancer } else { majBiblio }
}

proc ::moderne::prepa::lancer {} {
  variable w
  variable joueur
  variable base
  variable depuis
  variable eloMin
  variable parties
  variable filtreLigne
  variable cadence

  set joueur [string trim $joueur]
  set joueur [nettoyerSaisie $joueur]
  if {$joueur eq {}} { return }
  variable baseRef
  variable dernierLancer [list $joueur $base $baseRef $depuis $eloMin]
  # New player: forget the previous one's online accounts
  variable dernierJoueur
  variable compteLichess
  variable compteChesscom
  if {![info exists dernierJoueur] || $dernierJoueur ne $joueur} {
    set compteLichess {} ; set compteChesscom {}
    catch {$w.enligne.etat configure -text {}}
  }
  set dernierJoueur $joueur
  # Empty clipbase chosen by default (window opened before the databases):
  # take the database opened since then
  variable baseRef
  if {$base != 0 && (![sc_base inUse $base] || ($base == [sc_info clipbase] && [sc_base numGames $base] == 0))} {
    set ancienne $base
    set base [baseParDefaut]
    if {$baseRef == $ancienne || ![refActive]} { set baseRef 0 }
    catch majBases
  }
  if {$base == 0 || [catch {sc_base inUse $base} u] || !$u} {
    tk_messageBox -parent $w -icon warning -type ok -title Siby \
        -message [T "Choisis d'abord la base 1 (en haut) : celle des parties de la joueuse ou du joueur." \
                    "Choose Database 1 first (top): the database of the player's games."]
    return
  }
  if {![string is integer -strict $eloMin]} { set eloMin 0 }
  set depuis [string trim $depuis]
  if {$depuis ne {} && ![string is integer -strict $depuis]} { set depuis {} }
  # A name typed with or without its accents ("Hernández, Gilberto" for the
  # database's "Hernandez, Gilberto"): the database's spelling, the most
  # played one if several (Yosha 2026-11-05)
  set joueur [nomDansBase $joueur $base]

  # (window being rebuilt by a layout: recreate it)
  if {![winfo exists $w.resume]} {
    catch {ouvrir}
    if {![winfo exists $w.resume]} { return }
  }
  $w.resume configure -text [T "Recherche en cours…" "Searching…"] -image {}
  catch {
    $w.photoJ configure -image {}
    $w.titreJ configure -text {}
    $w.championJ configure -image {} -text {}
  }
  busyCursor $w
  update idletasks

  # Reading the moves (without touching the current game: sc_game boards
  # reads the database directly)
  set parties {}
  # New arrays for the library index; the previous ones are thrown away a
  # little at a time (freeing several hundred thousand entries at once took
  # 3 s)
  variable dGen
  jeter $dGen
  incr dGen
  # (the index in C++ when the binary has it: sc_prepa; read by idxIci and
  # partiesIci)
  variable indexCpp [expr {[llength [info commands ::sc_prepa]] > 0}]
  if {$indexCpp} { sc_prepa reset }
  upvar #0 ::moderne::prepa::idx_[set ::moderne::prepa::dGen] idx
  upvar #0 ::moderne::prepa::idxCoups_[set ::moderne::prepa::dGen] idxCoups
  upvar #0 ::moderne::prepa::idxElos_[set ::moderne::prepa::dGen] idxElos
  upvar #0 ::moderne::prepa::idxParties_[set ::moderne::prepa::dGen] idxParties
  upvar #0 ::moderne::prepa::partieDe_[set ::moderne::prepa::dGen] partieDe
  set erreur {}
  # Databases read: the chosen database, plus the player's online games if requested
  set baseOTB $base
  variable source
  set bl [::moderne::enligne::base [nomJoueur]]
  if {$source eq "base" || $bl <= 0 || $bl == $base} {
    set bases [list $base]
  } elseif {$source eq "toutes"} {
    set bases [list $base $bl]
  } else {
    set bases [list $bl]
  }
  # 1. The searches (one pass on each database)
  set taches {}
  set otbRefaire {}
  foreach b $bases {
    set courante [sc_base current]
    if {$courante != $b} { sc_base switch $b }

    # Exact name search (in quotes = "string match" pattern on the
    # C++ side). If the name contains * or ?, these wildcards are kept: "Carlsen, M*"
    # groups "Carlsen, M" and "Carlsen, Magnus".
    if {[string first * $joueur] >= 0 || [string first ? $joueur] >= 0} {
      set motifTcl $joueur
    } else {
      set motifTcl [echapperMotif $joueur]
    }
    set motif "\"$motifTcl\""
    # Both colours (-flip), over the board only and the time control in the
    # same pass: each pass reads the whole database (about 1 s on Gaby)
    set otb [expr {[catch {::moderne::otb::exclure $b} x] ? {} : ($x ? {-fCustom5 no} : {})}]
    if {$otb ne {}} { lappend otbRefaire $b }
    set brut [expr {[llength [info commands ::sc_search_otb]] ? "::sc_search_otb" : "::sc_search"}]
    set drap {}
    if {$cadence ne {}} { set drap [list -fCustom[::moderne::cadence::numero $cadence] yes] }
    set lignes {}
    if {[catch {
      $brut header -white $motif -flip 1 {*}$otb {*}$drap -filter RESET
      # Nothing with the exact name ("Carlsen" for "Carlsen, Magnus"): take
      # all the names that start this way
      if {[sc_filter count] == 0 && [string index $motifTcl end] ne "*"} {
        append motifTcl *
        set motif "\"$motifTcl\""
        $brut header -white $motif -flip 1 {*}$otb {*}$drap -filter RESET
      }
      # Time control. Gaby stores it in two ways:
      #  - SCID custom flag 1 / 2 / 3 (classical / rapid / blitz),
      #    stored in the index: instant search (above);
      #  - extra "Cadence" header: each game must be decoded.
      # If the flag gives nothing (database without these flags), the
      # search is redone with the header.
      if {$cadence ne {} && [sc_filter count] == 0} {
        $brut header -white $motif -flip 1 {*}$otb -filter RESET
        $brut header -extratag Cadence -tagvalue $cadence -filter AND
      }
      set nb [sc_filter count]
      if {$nb > 0} {
        set lignes [sc_game list 1 $nb "g*\tw*\tb*\tr*\td*\tW*\tB*\to*\te*\tS*\ts*"]
      }
    } msg]} { set erreur $msg }
    # Leave nothing behind: full filter (the online games left out again a
    # little later, in another pass), original database
    if {[llength [info commands ::sc_filter_otb]]} { catch {sc_filter_otb reset} } else { catch {sc_filter reset} }
    if {$courante != $b} { sc_base switch $courante }
    if {$erreur ne {}} { break }
    lappend taches [list $b $motifTcl [split [string trimright $lignes \n] \n]]
  }
  foreach b $otbRefaire { after 300 [list ::moderne::prepa::refiltrer $b] }
  if {$erreur ne {}} {
    unbusyCursor $w
    $w.resume configure -text "[T Erreur Error] : $erreur"
    return
  }

  # 2. Reading the games: in slices when there are many (the interface stays
  # responsive; about 0.7 ms a game)
  variable lecture
  variable lectureGen
  if {![info exists lectureGen]} { set lectureGen 0 }
  set total 0
  foreach t $taches { incr total [llength [lindex $t 2]] }
  set lecture [dict create gen [incr lectureGen] taches $taches it 0 il 0 faites 0 total $total baseOTB $baseOTB]
  # (always in slices, the first one now: read all at once when there were
  # fewer than 1500 games, a database not yet in the disk cache froze Siby
  # for 3 to 4 s)
  lireTranche $lectureGen 1
}

### Over the board only: the online games of database b out of its filter
### again (after a search)
proc ::moderne::prepa::refiltrer {b} {
  if {![sc_base inUse $b]} { return }
  catch {::moderne::otb::filtrer $b}
}

### Is a preparation being read? (the games of a player with many games are
### read in slices)
proc ::moderne::prepa::enLecture {} {
  variable lecture
  variable ficheEnAttente
  expr {([info exists lecture] && [dict size $lecture] > 0) || ([info exists ficheEnAttente] && $ficheEnAttente)}
}

### Reads the games of the preparation: everything (tranche 0) or about
### 150 ms of work, then the rest later
proc ::moderne::prepa::lireTranche {gen tranche} {
  variable lecture
  variable w
  variable parties
  variable source
  variable depuis
  variable eloMin
  if {![info exists lecture] || ![dict exists $lecture gen] || [dict get $lecture gen] != $gen} { return }
  if {![winfo exists $w.resume]} { set lecture {} ; return }
  set taches [dict get $lecture taches]
  set it [dict get $lecture it]
  set il [dict get $lecture il]
  set faites [dict get $lecture faites]
  set baseOTB [dict get $lecture baseOTB]
  set fin [expr {[clock milliseconds] + 150}]
  set erreur {}
  set cpp $::moderne::prepa::indexCpp
  while {$it < [llength $taches]} {
    lassign [lindex $taches $it] b motifTcl lignes
    if {![sc_base inUse $b]} { incr it ; set il 0 ; continue }
    set courante [sc_base current]
    if {$courante != $b} { sc_base switch $b }
    # (a read error must not leave the database switched or the cursor busy)
    if {[catch {
      while {$il < [llength $lignes]} {
        if {$tranche && [clock milliseconds] > $fin} { break }
        set ligne [lindex $lignes $il]
        incr il
        incr faites
        if {[catch {lassign [split $ligne \t] gnum blanc noir res date welo belo eco event depart site}]} { continue }
        # Online games: Lichess or Chess.com according to the Site header
        set origine base
        if {$b != $baseOTB} {
          set origine [expr {[string match -nocase *lichess* $site] ? "lichess" : "chesscom"}]
          if {$source in {lichess chesscom} && $origine ne $source} { continue }
        }
        set gnum [string trim $gnum]
        if {![string is integer -strict $gnum] || $gnum < 1} { continue }
        if {[string trim $depart] eq "S"} { continue }   ;# non-standard starting position
        if {[string match -nocase $motifTcl $blanc]} {
          set couleur white ; set adv $noir ; set advElo $belo ; set sonElo $welo ; set sonNom $blanc
        } else {
          set couleur black ; set adv $blanc ; set advElo $welo ; set sonElo $belo ; set sonNom $noir
        }
        set annee [string range $date 0 3]
        if {$depuis ne {} && (![string is integer -strict $annee] || $annee < $depuis)} { continue }
        if {$eloMin > 0 && (![string is integer -strict [string trim $advElo]] || $advElo < $eloMin)} { continue }
        # Time control: Gaby's flags 1 / 2 / 3 (classical, rapid, blitz)
        set cad {}
        foreach {k c} {1 classique 2 rapide 3 blitz} {
          if {![catch {sc_game flag $k $gnum} v] && $v eq "1"} { set cad $c ; break }
        }
        # All the positions of the game (C++, without loading it): the moves
        # for the tree, the positions for the library
        # (the trees and the export: the whole game, as on Lichess; the
        # library index: its first $pliesBiblio plies)
        if {$cpp} {
          # (C++: the moves of the game, its positions indexed on the way;
          # the same work as indexer, about ten times faster)
          set score [scoreJoueur [string trim $res] $couleur]
          set col [expr {$score eq 1 ? 1 : ($score eq 0.5 ? 2 : ($score eq 0 ? 3 : 0))}]
          set r1 [string trim $sonElo] ; set r2 [string trim $advElo]
          set elos {}
          if {$score ne {} && [string is integer -strict $r1] && [string is integer -strict $r2] && $r1 > 0 && $r2 > 0} {
            set elos [list $r1 $r2 $score]
          }
          set coups [sc_prepa add $gnum $couleur "$b:$gnum" $col $date $elos $::moderne::prepa::pliesBiblio]
        } else {
          set tout [sc_game boards $gnum]
          set positions [lrange $tout 0 $::moderne::prepa::pliesBiblio]
          set coups {}
          foreach pos [lrange $tout 1 end] { lappend coups [lindex $pos 0] }
        }
        set p [dict create gnum $gnum base $b id "$b:$gnum" enligne [expr {$b != $baseOTB}] couleur $couleur adversaire $adv \
            elo [string trim $advElo] sonElo [string trim $sonElo] res [string trim $res] date $date eco [string trim $eco] \
            tournoi $event coups $coups cadence $cad nom [string trim $sonNom] origine $origine]
        lappend parties $p
        if {$cpp} {
          set ::moderne::prepa::partieDe_[set ::moderne::prepa::dGen]($b:$gnum) $p
        } else {
          indexer $p $positions
        }
      }
    } msgLecture]} { set erreur $msgLecture }
    if {$courante != $b} { sc_base switch $courante }
    if {$erreur ne {}} { break }
    if {$il < [llength $lignes]} { break }
    incr it
    set il 0
  }
  if {$erreur eq {} && $it < [llength $taches]} {
    dict set lecture it $it
    dict set lecture il $il
    dict set lecture faites $faites
    set total [dict get $lecture total]
    $w.resume configure -text "[T "Lecture des parties" "Reading the games"] : [::utils::thousands $faites] / [::utils::thousands $total] ([expr {100 * $faites / max(1, $total)}] %)"
    after 1 [list ::moderne::prepa::lireTranche $gen 1]
    return
  }
  set lecture {}
  lancerFin $erreur
}

### End of the preparation: trees, games, profile, library
proc ::moderne::prepa::lancerFin {erreur} {
  variable w
  variable parties
  variable joueur
  variable filtreLigne
  # Online accounts already used for this player
  variable compteLichess
  variable compteChesscom
  if {$compteLichess eq {} && $compteChesscom eq {}} {
    variable base
    lassign [::moderne::enligne::comptesDe [nomJoueur] $base] compteLichess compteChesscom
  }
  unbusyCursor $w
  catch {::windows::gamelist::Refresh}

  if {$erreur ne {}} {
    $w.resume configure -text "[T Erreur Error] : $erreur"
    return
  }
  set filtreLigne {}
  calculerArbres
  remplirArbre $w.nb.white.pw.g.t white
  remplirArbre $w.nb.black.pw.g.t black
  foreach c {white black} {
    set d $w.nb.$c.pw.d
    $d.t delete [$d.t children {}]
    $d.titre configure -text [T "Référence : choisis un coup à gauche." "Reference: select a move on the left."]
  }
  remplirParties
  majResume
  catch {majSources}
  # The profile, then the library: a little later (each takes up to a second
  # with thousands of games: the interface breathes in between)
  variable lectureGen
  variable ficheEnAttente 1
  if {[llength $parties] < 1500} {
    lancerFiche $lectureGen
  } else {
    after 50 [list ::moderne::prepa::lancerFiche $lectureGen]
  }
}

proc ::moderne::prepa::lancerFiche {gen} {
  variable w
  variable parties
  variable joueur
  variable lectureGen
  variable ficheEnAttente
  if {$gen != $lectureGen || ![winfo exists $w.nb.fiche]} { set ficheEnAttente 0 ; return }
  set ficheEnAttente 0
  # Profile: under the most frequent exact name (the ratings do not depend on
  # how the name was typed)
  set noms {}
  foreach p $parties { dict incr noms [dict get $p nom] }
  set nomFiche $joueur
  set best 0
  dict for {nm c} $noms { if {$c > $best} { set best $c ; set nomFiche $nm } }
  ::moderne::fiche::remplir $w.nb.fiche $nomFiche $parties
  if {[llength $parties] < 1500} {
    majBiblio
  } else {
    after 50 [list apply {{gen} {
      if {$gen == $::moderne::prepa::lectureGen} { ::moderne::prepa::majBiblio }
    }} $gen]
  }
}

### Throws away the library index arrays of generation gen, in slices
proc ::moderne::prepa::jeter {gen {noms {}} {tableaux {idx idxCoups idxElos idxParties partieDe}}} {
  while {![llength $noms]} {
    if {![llength $tableaux]} { return }
    set v ::moderne::prepa::[lindex $tableaux 0]_$gen
    if {[array exists $v] && [array size $v] > 0} {
      set noms [array names $v]
      break
    }
    unset -nocomplain $v
    set tableaux [lrange $tableaux 1 end]
  }
  set v ::moderne::prepa::[lindex $tableaux 0]_$gen
  foreach k [lrange $noms 0 19999] { unset -nocomplain ${v}($k) }
  set noms [lrange $noms 20000 end]
  if {![llength $noms]} {
    unset -nocomplain $v
    set tableaux [lrange $tableaux 1 end]
  }
  after 20 [list ::moderne::prepa::jeter $gen $noms $tableaux]
}

### Adds the positions of a game to the library index
proc ::moderne::prepa::indexer {p positions} {
  upvar #0 ::moderne::prepa::idx_[set ::moderne::prepa::dGen] idx
  upvar #0 ::moderne::prepa::idxCoups_[set ::moderne::prepa::dGen] idxCoups
  upvar #0 ::moderne::prepa::idxElos_[set ::moderne::prepa::dGen] idxElos
  upvar #0 ::moderne::prepa::idxParties_[set ::moderne::prepa::dGen] idxParties
  upvar #0 ::moderne::prepa::partieDe_[set ::moderne::prepa::dGen] partieDe
  set couleur [dict get $p couleur]
  set gnum [dict get $p id]
  set partieDe($gnum) $p
  set score [scoreJoueur [dict get $p res] $couleur]
  set date [dict get $p date]
  # (per game, not per position: the score column and the ratings)
  set col [expr {$score eq 1 ? 1 : ($score eq 0.5 ? 2 : ($score eq 0 ? 3 : 0))}]
  set r1 [dict get $p sonElo] ; set r2 [dict get $p elo]
  set eloOk [expr {$score ne {} && [string is integer -strict $r1] && [string is integer -strict $r2] && $r1 > 0 && $r2 > 0}]
  set triplet [list $r1 $r2 $score]
  array set vues {}
  set n [llength $positions]
  for {set i 0} {$i < $n} {incr i} {
    # (key: the 64 squares and the side to move, as ::moderne::biblio::cle)
    set plateau [lindex $positions $i 1]
    set cle $couleur,[string range $plateau 0 63][string index $plateau 65]
    # A position repeated within the same game only counts once
    if {[info exists vues($cle)]} { continue }
    set vues($cle) 1
    lappend idxParties($cle) [list $gnum $i]
    if {$i + 1 >= $n} { continue }
    set coup [lindex $positions [expr {$i + 1}] 0]
    # (counts and ratings kept apart, each added in place: rebuilding a
    # growing list for every game made this quadratic)
    if {[info exists idx($cle,$coup)]} {
      lassign $idx($cle,$coup) nn g d pp der
    } else {
      lassign {0 0 0 0 {}} nn g d pp der
      lappend idxCoups($cle) $coup
      set idxElos($cle,$coup) {}
    }
    incr nn
    switch -- $col { 1 { incr g } 2 { incr d } 3 { incr pp } }
    if {$date ne $der} { set der [plusRecente $date $der] }
    set idx($cle,$coup) [list $nn $g $d $pp $der]
    # (both ratings of the game and the result: Elo gain of the move)
    if {$eloOk} { lappend idxElos($cle,$coup) $triplet }
  }
}

### The player's moves in position cle ("color,key"): dict englishMove ->
### {n wins draws losses latest elos}
proc ::moderne::prepa::idxIci {cle} {
  if {$::moderne::prepa::indexCpp} { return [sc_prepa ici $cle] }
  upvar #0 ::moderne::prepa::idx_[set ::moderne::prepa::dGen] idx
  upvar #0 ::moderne::prepa::idxCoups_[set ::moderne::prepa::dGen] idxCoups
  upvar #0 ::moderne::prepa::idxElos_[set ::moderne::prepa::dGen] idxElos
  set res [dict create]
  if {![info exists idxCoups($cle)]} { return $res }
  foreach coup $idxCoups($cle) {
    dict set res $coup [concat $idx($cle,$coup) [list $idxElos($cle,$coup)]]
  }
  return $res
}

### The games of the player that went through position cle: list of {id ply}
proc ::moderne::prepa::partiesIci {cle} {
  if {$::moderne::prepa::indexCpp} { return [sc_prepa parties $cle] }
  upvar #0 ::moderne::prepa::idxParties_[set ::moderne::prepa::dGen] idxParties
  if {[info exists idxParties($cle)]} { return $idxParties($cle) }
  return {}
}

proc ::moderne::prepa::nbIci {cle} {
  if {$::moderne::prepa::indexCpp} { return [sc_prepa nb $cle] }
  return [llength [partiesIci $cle]]
}

### Usual White edge in Elo at an average level, for the tooltips only (the
### overperformance is not corrected: Yosha 2026-11-09). Measured on the
### Ultrabase sample, classical games with both ratings: +19 at 1500, +29
### at 2100, +40 at 2700.
proc ::moderne::prepa::avantageBlanc {niveau} {
  return [expr {round(max(0.0, 19.0 + 0.0175 * ($niveau - 1500)))}]
}

### The same overperformance from averages (a database's move: n games,
### the movers' average rating r1, their opponents' r2, score s 0-1): as
### gainElo with n games all at that gap, in one sum (Yosha 2026-11-09).
### Returns {gain sd n}, or {} without enough rated games.
proc ::moderne::prepa::gainEloMoyennes {r1 r2 s n {sd0 50.0}} {
  if {$n < 1 || $r1 <= 0 || $r2 <= 0} { return {} }
  set lp {}
  set grille {}
  for {set d -300} {$d <= 300} {incr d 5} {
    lappend grille $d
    set x [expr {1.0 / (1.0 + pow(10.0, ($r2 - $r1 - $d) / 400.0))}]
    lappend lp [expr {-0.5 * ($d / $sd0) ** 2 + $n * ($s * log($x) + (1.0 - $s) * log(1.0 - $x))}]
  }
  set m [tcl::mathfunc::max {*}$lp]
  set z 0.0 ; set s1 0.0 ; set s2 0.0
  foreach d $grille v $lp {
    set p [expr {exp($v - $m)}]
    set z [expr {$z + $p}] ; set s1 [expr {$s1 + $p * $d}] ; set s2 [expr {$s2 + $p * $d * $d}]
  }
  set moy [expr {$s1 / $z}]
  set sd [expr {sqrt(max(0.0, $s2 / $z - $moy * $moy))}]
  return [list [expr {round($moy)}] [expr {round($sd)}] $n]
}

### Overperformance of a move of the player (Bayesian "perf − Elo"): how much stronger (or weaker) than
### their rating they play after it. Bayesian: the gain d starts at 0 (+- 50)
### and each game moves it according to its result against the score
### expected from both ratings of that day (a win against a weaker player
### moves it little). elos: list of {own rating, opponent's rating, score}.
### Returns {gain sd games} (gain and sd rounded), or {} without a rated game.
proc ::moderne::prepa::gainElo {elos {sd0 50.0}} {
  if {![llength $elos]} { return {} }
  set grille {}
  for {set d -300} {$d <= 300} {incr d 5} { lappend grille $d }
  set lp {}
  foreach d $grille {
    set v [expr {-0.5 * ($d / $sd0) ** 2}]
    foreach e $elos {
      lassign $e r1 r2 s
      set x [expr {1.0 / (1.0 + pow(10.0, ($r2 - $r1 - $d) / 400.0))}]
      set v [expr {$v + $s * log($x) + (1.0 - $s) * log(1.0 - $x)}]
    }
    lappend lp $v
  }
  set m [tcl::mathfunc::max {*}$lp]
  set z 0.0 ; set s1 0.0 ; set s2 0.0
  foreach d $grille v $lp {
    set p [expr {exp($v - $m)}]
    set z [expr {$z + $p}] ; set s1 [expr {$s1 + $p * $d}] ; set s2 [expr {$s2 + $p * $d * $d}]
  }
  set moy [expr {$s1 / $z}]
  set sd [expr {sqrt(max(0.0, $s2 / $z - $moy * $moy))}]
  return [list [expr {round($moy)}] [expr {round($sd)}] [llength $elos]]
}

### "Library" tab: follows the position of the main board
################################################################################
### Notation tab: the notation window (.fdockpgnWin, in a tab group of the
### Analysis page) lent while the tab is in front and on screen, then given
### back to its group, in its place, in front again if it was.
###  pretNotation: {} or {group index title chosen}
################################################################################

namespace eval ::moderne::prepa { variable pretNotation {} }

proc ::moderne::prepa::suivreNotation {{essai 0}} {
  variable w
  # (viewable: a hidden Lab page leaves its windows "mapped")
  # (and the preparation's own place in the main window: viewable stops at
  # its embedded window)
  set c .fdock[string range $w 1 end]
  set ici [expr {[winfo exists $w.nb] && [$w.nb select] eq "$w.nb.notation" && [winfo viewable $w.nb.notation]
                 && [winfo exists $c] && [winfo viewable $c] && ![::moderne::prepa::couvert]}]
  if {$ici} { emprunterNotation ; return }
  rendreNotation
  # (the tab in front but its page not shown yet: Windows maps the windows
  # a moment later; tried again a few times)
  if {$essai < 5 && [winfo exists $w.nb] && [$w.nb select] eq "$w.nb.notation" && ![::moderne::prepa::couvert]
      && [winfo exists .fdock[string range $w 1 end]] && [::moderne::lab::cache [::docking::find_tbn .fdock[string range $w 1 end]]] == 0} {
    after 100 [list ::moderne::prepa::suivreNotation [incr essai]]
  }
}

proc ::moderne::prepa::emprunterNotation {} {
  variable w
  variable pretNotation
  set f .fdockpgnWin
  if {![winfo exists $f]} { catch ::pgn::Open }
  if {![winfo exists $f]} { return }
  if {$pretNotation eq {}} {
    set nb [::docking::find_tbn $f]
    if {$nb ne {} && [winfo exists $nb] && $f in [$nb tabs]} {
      set choisi [expr {[$nb select] eq $f}]
      set pretNotation [list $nb [$nb index $f] [$nb tab $f -text] $choisi]
      $nb forget $f
    } else {
      set pretNotation [list {} 0 [T "Notation" "Notation"] 0]
    }
  }
  placerNotation
}

### Laid exactly over the tab's area (the two windows are siblings in the
### main window; the tab's frame is inside the preparation's)
proc ::moderne::prepa::placerNotation {} {
  variable w
  variable pretNotation
  if {$pretNotation eq {} || ![winfo exists .fdockpgnWin] || ![winfo exists $w.nb.notation]} { return }
  set c .fdock[string range $w 1 end]
  if {![winfo exists $c] || ![winfo viewable $c] || ![winfo viewable $w.nb.notation]} { return }
  set x [expr {[winfo rootx $w.nb.notation] - [winfo rootx $c]}]
  set y [expr {[winfo rooty $w.nb.notation] - [winfo rooty $c]}]
  place .fdockpgnWin -in $c -x $x -y $y -width [winfo width $w.nb.notation] -height [winfo height $w.nb.notation]
  raise .fdockpgnWin
}

### A view laid over the Lab (My databases, a broadcast, a game): the
### notation goes back to its group, the cover may need it
proc ::moderne::prepa::couvert {} {
  if {![catch {::moderne::mesbases::enSuperposition} v] && $v} { return 1 }
  if {![catch {::moderne::direct::enSuperposition} v] && $v} { return 1 }
  if {[winfo exists .jeuCouvre] && [winfo ismapped .jeuCouvre]} { return 1 }
  return 0
}

proc ::moderne::prepa::rendreNotation {} {
  variable pretNotation
  if {$pretNotation eq {}} { return }
  lassign $pretNotation nb i titre choisi
  set pretNotation {}
  set f .fdockpgnWin
  if {![winfo exists $f]} { return }
  catch {place forget $f}
  if {$nb ne {} && [winfo exists $nb]} {
    catch {
      if {$i >= [llength [$nb tabs]]} { $nb add $f -text $titre } else { $nb insert $i $f -text $titre }
      if {$choisi} { $nb select $f }
    }
    catch {raise $f}
  }
}

proc ::moderne::prepa::majBiblio {} {
  variable w
  upvar #0 ::moderne::prepa::partieDe_[set ::moderne::prepa::dGen] partieDe
  variable baseRef
  variable eloRef
  variable biblioCouleur
  variable parties
  if {![winfo exists $w] || [$w.nb select] ne "$w.nb.biblio"} { return }
  set f $w.nb.biblio
  set cle [::moderne::biblio::cle [sc_pos board]]
  # Color: the chosen one (White by default)
  set nb(white) [nbIci white,$cle]
  set nb(black) [nbIci black,$cle]
  set couleur $biblioCouleur
  if {$couleur ni {white black}} { set couleur white ; set biblioCouleur white }
  $f.h.blancs configure -text "[T "avec les Blancs" "as White"] ($nb(white))"
  $f.h.noirs configure -text "[T "avec les Noirs" "as Black"] ($nb(black))"
  $f.pos configure -text [::moderne::biblio::texteIci]

  # 1. Right away (no search): the player's moves and games
  set lui [idxIci $couleur,$cle]
  catch {
    variable joueur
    set nomT [string trim $joueur]
    if {[info exists ::moderne::prepa::nomAffiche] && $::moderne::prepa::nomAffiche ne {} && [llength $parties]} { set nomT $::moderne::prepa::nomAffiche }
    if {$nomT ne {}} { ::moderne::tableau::titreGroupe $f.pw.h.t joueur $nomT }
    if {[refActive]} { ::moderne::tableau::titreGroupe $f.pw.h.t ref [::moderne::nomBase [sc_base filename $baseRef]] }
  }
  # (only when the reference is slow: a fast one fills the table at once,
  # without the half-filled table first and its rows jumping, Yosha
  # 2026-11-04)
  variable refDuree
  set enDeuxTemps [expr {![refActive] || ![info exists refDuree] || $refDuree > 250}]
  if {$enDeuxTemps} {
    ::moderne::biblio::remplirPrepa $f.pw.h.t {attente {}} $lui $couleur
    $f.ref configure -text "[T "Référence : recherche…" "Reference: searching…"]"
    # Reference games: cleared during the search
    $f.pw.b.nb.ref.t delete [$f.pw.b.nb.ref.t children {}]
    $f.pw.b.nb tab $f.pw.b.nb.ref -text "[T "Parties de la référence" "Reference games"] (…)"
  }

  # The player's games that went through this position (most recent first)
  set t $f.pw.b.t
  $t delete [$t children {}]
  set liste {}
  foreach gp [partiesIci $couleur,$cle] {
    lassign $gp gnum ply
    lappend liste [list [dict get $partieDe($gnum) date] $gnum $ply]
  }
  foreach e [lsort -decreasing -index 0 $liste] {
    lassign $e - gnum ply
    set p $partieDe($gnum)
    set score [scoreJoueur [dict get $p res] $couleur]
    set tag {}
    if {$score eq 1} { set tag gain } elseif {$score eq 0} { set tag perte }
    $t insert {} end -id b[string map {: _} $gnum],$ply -tags $tag -values [list \
        [date [dict get $p date]] \
        [lindex [list [T Noirs Black] [T Blancs White]] [expr {$couleur eq "white"}]] \
        [dict get $p adversaire] [dict get $p elo] [string map {=-= ½-½} [dict get $p res]] \
        [dict get $p eco] [dict get $p tournoi] [texteLigne [lrange [dict get $p coups] 0 9]]]
  }
  ::moderne::zebrer $t
  set qui [lindex [list [T "avec les Noirs" "as Black"] [T "avec les Blancs" "as White"]] [expr {$couleur eq "white"}]]
  if {![llength $parties]} {
    $f.pw.b.titre configure -text [T "Prépare d'abord un joueur ou une joueuse (en haut) pour voir ses coups et ses parties ici." \
                                     "Prepare a player first (top) to see their moves and games here."]
  } else {
    $f.pw.b.titre configure -text "[T "Ses parties" "Their games"] $qui [T "passées par cette position" "through this position"] : [llength $liste]"
  }
  $f.pw.b.nb tab $f.pw.b.nb.lui -text "[T "Ses parties" "Their games"] ([llength $liste])"
  if {$enDeuxTemps} { update idletasks }

  # 2. The reference (search in the database, sometimes long): the player's moves
  # are already shown; the reference is added when the search finishes
  if {![refActive]} {
    ::moderne::biblio::remplirPrepa $f.pw.h.t {0 {}} $lui $couleur 1
    $f.pw.b.nb tab $f.pw.b.nb.ref -text "[T "Parties de la référence" "Reference games"] (0)"
    $f.ref configure -text [T "Référence : aucune base de référence ouverte (Gaby, ou celle choisie dans Mes bases)" \
        "Reference: no reference database open (Gaby, or the one chosen in My databases)"]
    return
  }
  set t0 [clock milliseconds]
  set ref [::moderne::biblio::statsIci $baseRef $eloRef $::moderne::prepa::depuis $::moderne::prepa::cadence]
  set refDuree [expr {[clock milliseconds] - $t0}]
  # (search interrupted by a new move: the next one will fill in)
  if {[lindex $ref 0] == -1} { return }
  if {[cleIci] ne $cle} { return }
  set total [::moderne::biblio::remplirPrepa $f.pw.h.t $ref $lui $couleur 1]
  set nRef [::moderne::biblio::remplirMeilleures $f.pw.b.nb.ref.t $baseRef $total]
  $f.pw.b.nb tab $f.pw.b.nb.ref -text "[T "Parties de la référence" "Reference games"] ([::utils::thousands $total])"
  set filtre [::moderne::biblio::texteFiltres $eloRef $::moderne::prepa::depuis $::moderne::prepa::cadence]
  set nomRef [expr {[sc_base inUse $baseRef] ? [::moderne::nomBase [sc_base filename $baseRef]] : "–"}]
  $f.ref configure -text "[T "Référence" "Reference"] ($nomRef$filtre)[T " : " ": "][::utils::thousands $total] [expr {$total == 1 ? [T "partie dans cette position" "game in this position"] : [T "parties dans cette position" "games in this position"]}]"
}

proc ::moderne::prepa::cleIci {} {
  return [::moderne::biblio::cle [sc_pos board]]
}

### Opens a reference game at the board's position
proc ::moderne::prepa::chargerPartieRef {t {x {}} {y {}}} {
  variable baseRef
  set id [ligneVisee $t $x $y]
  if {![string match g* $id]} { return }
  ::moderne::biblio::ouvrirPartie $baseRef [string range $id 1 end]
  partieChargee
}

### Opens one of the player's games at the library's position
### Line targeted by a double-click (under the pointer), otherwise the active line
proc ::moderne::prepa::ligneVisee {t x y} {
  set id {}
  if {$y ne {}} { set id [$t identify row 1 $y] }
  if {$id eq {}} { set id [$t focus] }
  # (the list may have been filled again meanwhile)
  if {$id eq {} || [catch {$t exists $id} ok] || !$ok} { return {} }
  catch {$t selection set [list $id] ; $t focus $id}
  return $id
}

proc ::moderne::prepa::chargerPartieBiblio {t {x {}} {y {}}} {
  set id [ligneVisee $t $x $y]
  if {![regexp {^b([0-9]+)_([0-9]+),([0-9]+)$} $id -> b gnum ply]} { return }
  ::moderne::biblio::ouvrirPartie $b $gnum $ply
  partieChargee
}

### Builds the two repertoire trees from the games read
proc ::moderne::prepa::calculerArbres {} {
  variable parties
  variable enfants
  variable fils
  variable racine
  variable ng
  variable prof
  variable nid
  variable gRes
  variable gDn
  variable sN ; variable sG ; variable sD ; variable sP ; variable sDer
  # The tree is built lazily: a node is split by next move only when it
  # is needed (opened, exported, looked up). Building it all at once took
  # 6 s or more for 12,000 games.
  foreach a {enfants fils racine ng prof gRes gDn sN sG sD sP sDer} { array unset $a }
  set nid 0
  set i 0
  set lui(white) {} ; set lui(black) {}
  foreach p $parties {
    set couleur [dict get $p couleur]
    set score [scoreJoueur [dict get $p res] $couleur]
    set gRes($i) [expr {$score eq 1 ? "sG" : ($score eq 0.5 ? "sD" : ($score eq 0 ? "sP" : {}))}]
    set date [dict get $p date]
    set gDn($i) [expr {[regexp {^[0-9]{4}} $date] ? [string map {? 0} $date] : {}}]
    lappend lui($couleur) $i
    incr i
  }
  foreach couleur {white black} {
    set racine($couleur) [nouveauNoeud $lui($couleur) 0]
  }
}

### New tree node: the games (indexes in parties) gone through it, depth d
proc ::moderne::prepa::nouveauNoeud {jeux d} {
  variable parties
  variable ng
  variable prof
  variable nid
  variable gRes
  variable gDn
  variable sN ; variable sG ; variable sD ; variable sP ; variable sDer
  set id [incr nid]
  set ng($id) $jeux
  set prof($id) $d
  if {![llength $jeux]} { return $id }
  set sN($id) [llength $jeux]
  set sG($id) 0 ; set sD($id) 0 ; set sP($id) 0
  set dn {} ; set der {}
  foreach i $jeux {
    if {$gRes($i) ne {}} { incr $gRes($i)($id) }
    if {$gDn($i) ne {} && [string compare $gDn($i) $dn] > 0} {
      set dn $gDn($i)
      set der [dict get [lindex $parties $i] date]
    }
  }
  set sDer($id) $der
  return $id
}

### Splits node id by next move (once)
proc ::moderne::prepa::developper {id} {
  variable parties
  variable ng
  variable prof
  variable fils
  variable enfants
  if {![info exists ng($id)]} { return }
  set d $prof($id)
  set ordre {}
  foreach i $ng($id) {
    set coup [lindex [dict get [lindex $parties $i] coups] $d]
    if {$coup eq {}} { continue }
    if {![info exists groupe($coup)]} { lappend ordre $coup }
    lappend groupe($coup) $i
  }
  foreach coup $ordre {
    set fils($id,$coup) [nouveauNoeud $groupe($coup) [expr {$d + 1}]]
    lappend enfants($id) $coup
  }
  # (developed: the list of games is no longer needed)
  unset ng($id)
}

### Node of the tree of colour couleur reached by the moves of chemin ({} if
### none), developed
proc ::moderne::prepa::noeud {couleur chemin} {
  variable fils
  variable racine
  if {![info exists racine($couleur)]} { return {} }
  set id $racine($couleur)
  developper $id
  foreach c $chemin {
    if {![info exists fils($id,$c)]} { return {} }
    set id $fils($id,$c)
    developper $id
  }
  return $id
}

### Statistics of a node: {n wins draws losses latest} ({} if no game)
proc ::moderne::prepa::stat {id} {
  variable sN ; variable sG ; variable sD ; variable sP ; variable sDer
  if {$id eq {} || ![info exists sN($id)]} { return {} }
  return [list $sN($id) $sG($id) $sD($id) $sP($id) $sDer($id)]
}

### Formats a SCID date "2023.05.14" (the "??" are removed)
### Two games {... date ...} in date order; an unknown part of a date
### ("????.??.??", "1993.??.??") counts as the oldest: the games with no
### date came first in "most recent first", Yosha 2026-11-05
proc ::moderne::comparerDates {a b} {
  string compare [string map {? 0} [dict get $a date]] [string map {? 0} [dict get $b date]]
}

proc ::moderne::prepa::date {d} {
  regsub {(\.\?\?)+$} $d {} d
  if {[string index $d 0] eq "?"} { return {} }
  return $d
}

proc ::moderne::prepa::pourcent {a b} {
  if {$b <= 0} { return {} }
  return "[expr {round(100.0 * $a / $b)}] %"
}

### Shows the children of a node, from most to least played
proc ::moderne::prepa::ajouterEnfants {t couleur parentItem chemin} {
  variable enfants
  variable cheminNoeud
  if {![info exists enfants([noeud $couleur $chemin])]} { return }
  set total [lindex [stat [noeud $couleur $chemin]] 0]
  set liste {}
  foreach coup $enfants([noeud $couleur $chemin]) {
    set c [concat $chemin [list $coup]]
    lappend liste [list $coup [lindex [stat [noeud $couleur $c]] 0]]
  }
  set ply [llength $chemin]                  ;# 0 = White's first move
  set traitBlancs [expr {$ply % 2 == 0}]
  set coupDuJoueur [expr {($couleur eq "white") == $traitBlancs}]
  foreach el [lsort -integer -decreasing -index 1 $liste] {
    lassign $el coup n
    set c [concat $chemin [list $coup]]
    lassign [stat [noeud $couleur $c]] n g d p der
    set joues [expr {$g + $d + $p}]
    set numero [expr {$ply / 2 + 1}]
    # (no expr here: "1.e4" would be read as the number 1e4)
    if {$traitBlancs} { set texte "$numero.$coup" } else { set texte "$numero...$coup" }
    set item [$t insert $parentItem end -text [::trans $texte] \
        -values [list [::utils::thousands $n] [pourcent $n $total] \
                      [pourcent [expr {$g + 0.5 * $d}] $joues] [pourcent $d $joues] [date $der]] \
        -tags [lindex {adversaire joueur} $coupDuJoueur]]
    set cheminNoeud($t,$item) [list $couleur $c]
    # "Expandable" node: a dummy child, replaced when opened
    if {[info exists enfants([noeud $couleur $c])]} {
      $t insert $item end -text "…" -tags factice
    }
  }
}

proc ::moderne::prepa::remplirArbre {t couleur} {
  variable cheminNoeud
  array unset cheminNoeud $t,*
  $t delete [$t children {}]
  ajouterEnfants $t $couleur {} {}
  # Automatically expand the main line for a few moves
  set item [lindex [$t children {}] 0]
  for {set i 0} {$i < 4 && $item ne {}} {incr i} {
    $t item $item -open 1
    deplier $t $couleur $item
    set item [lindex [$t children $item] 0]
  }
}

proc ::moderne::prepa::deplier {t couleur {item {}}} {
  variable cheminNoeud
  if {$item eq {}} { set item [$t focus] }
  if {$item eq {} || ![info exists cheminNoeud($t,$item)]} { return }
  set kids [$t children $item]
  if {[llength $kids] == 1 && [$t tag has factice [lindex $kids 0]]} {
    $t delete $kids
    ajouterEnfants $t $couleur $item [lindex $cheminNoeud($t,$item) 1]
  }
}

proc ::moderne::prepa::selection {t couleur} {
  variable cheminNoeud
  variable filtreLigne
  variable enSuivi
  # (selection set by the board tracking: nothing else to redo)
  if {[info exists enSuivi] && $enSuivi} { return }
  set item [$t focus]
  if {$item eq {} || ![info exists cheminNoeud($t,$item)]} { return }
  set filtreLigne $cheminNoeud($t,$item)
  # the board follows the tree (click or arrow keys)
  catch {allerA [lindex $cheminNoeud($t,$item) 1]}
  remplirParties
  # Reference: slightly delayed, so as not to slow down keyboard navigation
  after cancel ::moderne::prepa::majReference
  after 150 ::moderne::prepa::majReference
}

### Hovering over a move in the tree: arrow on the board if the board is
### at the position it starts from
proc ::moderne::prepa::survolArbre {t x y} {
  variable cheminNoeud
  set id [$t identify row $x $y]
  set fl {}
  if {$id ne {} && [info exists cheminNoeud($t,$id)]} {
    set chemin [lindex $cheminNoeud($t,$id) 1]
    set n [llength $chemin]
    set ply 0
    catch {set ply [sc_pos location]}
    set partie {}
    catch {set partie [sc_game moves nonums]}
    if {$n > 0 && $ply == $n - 1 && [lrange $partie 0 [expr {$n - 2}]] eq [lrange $chemin 0 end-1]} {
      set fl [lindex $chemin end]
    }
  }
  catch {::moderne::biblio::flecheSurvol $fl}
}

### Both trees follow the main board: the line played is
### expanded and selected (as far as it exists in their repertoire)
proc ::moderne::prepa::suivreArbres {} {
  after cancel ::moderne::prepa::suivreArbresMaintenant
  after 150 ::moderne::prepa::suivreArbresMaintenant
}

proc ::moderne::prepa::suivreArbresMaintenant {} {
  variable w
  variable enSuivi
  if {![winfo exists $w.nb]} { return }
  set ligne {}
  catch {set ligne [sc_game moves nonums]}
  set enSuivi 1
  foreach couleur {white black} {
    set t $w.nb.$couleur.pw.g.t
    if {[winfo exists $t]} { catch {placerDansArbre $t $couleur $ligne} }
  }
  after 100 {set ::moderne::prepa::enSuivi 0}
  # The reference (to the right of the trees) also follows, if a tree is shown
  set onglet {}
  catch {set onglet [$w.nb select]}
  foreach couleur {white black} {
    set t $w.nb.$couleur.pw.g.t
    if {$onglet eq "$w.nb.$couleur" && [winfo exists $t] && [$t focus] ne {}} {
      variable cheminNoeud
      variable filtreLigne
      if {[info exists cheminNoeud($t,[$t focus])]} {
        set filtreLigne $cheminNoeud($t,[$t focus])
        catch {remplirParties}
        after cancel ::moderne::prepa::majReference
        after 150 ::moderne::prepa::majReference
      }
    }
  }
}

proc ::moderne::prepa::placerDansArbre {t couleur ligne} {
  variable cheminNoeud
  set item {}
  set chemin {}
  set trouve {}
  foreach coup $ligne {
    lappend chemin $coup
    if {$item ne {}} { deplier $t $couleur $item }
    set suivant {}
    foreach enfant [$t children $item] {
      if {[info exists cheminNoeud($t,$enfant)] && [lindex $cheminNoeud($t,$enfant) 1] eq $chemin} {
        set suivant $enfant
        break
      }
    }
    if {$suivant eq {}} { break }
    if {$item ne {}} { $t item $item -open 1 }
    set item $suivant
    set trouve $item
  }
  if {$trouve eq {}} {
    $t selection set {}
    return
  }
  $t selection set $trouve
  $t focus $trouve
  # the move played is expanded: its continuations are visible right away
  catch {deplier $t $couleur $trouve}
  $t item $trouve -open 1
  $t see $trouve
}

################################################################################
### "Reference" panel: the reference database at the chosen position
################################################################################

proc ::moderne::prepa::creerPanneauRef {f} {
  ttk::label $f.titre -font font_Bold -padding {6 2} -wraplength 520 -justify left \
      -text [T "Référence : choisis un coup à gauche pour voir ce qui s'y joue." \
                "Reference: select a move on the left to see what is played there."]
  pack $f.titre -side top -fill x
  set t $f.t
  ttk::treeview $t -columns {lui n pct score nulles elo derniere} -show {tree headings} -selectmode browse
  $t heading #0 -text [T "Coup" "Move"] -anchor w
  foreach {c fr en l} {
    lui    "Prépa"        "Prep"          60
    n      "Parties"      "Games"         80
    pct    "Fréq."        "Freq."         55
    score  "Score Blancs" "White score"  100
    nulles "Nulles"       "Draws"         60
    elo    "Elo moy."     "Avg Elo"       70
    derniere "Dernière fois" "Last played" 105
  } {
    $t heading $c -text [T $fr $en]
    $t column $c -width $l -anchor e -stretch 0
  }
  $t column #0 -width 90 -stretch 1
  ::moderne::tri::activer $t
  $t tag configure joue -font font_Bold \
      -foreground [expr {[::moderne::actif] && $::moderne::theme eq "sombre" ? "#6fb3f2" : "#1b62b0"}]
  $t tag configure horsRef -foreground [expr {[::moderne::actif] && $::moderne::theme eq "sombre" ? "#f0b35b" : "#a35a00"}]
  ttk::scrollbar $f.sb -command [list $t yview]
  $t configure -yscrollcommand [list $f.sb set]
  # (the colours in a tooltip, not a sentence always shown: Yosha
  # 2026-11-04, see CLAUDE.md)
  catch {::utils::tooltip::Set $t [T \
      "Bleu : ses coups (colonne Prépa : ses parties) • Orange : ses coups absents de la référence" \
      "Blue: their moves (Prep column: their games) • Orange: their moves missing from the reference"]}
  pack $f.sb -side right -fill y
  pack $t -side left -fill both -expand 1
}

### Statistics of the reference database for the position after "chemin"
### (list of rows {rank move n pct score draws elo perf year eco}).
### The current game is not touched: we go through the clipbase,
### as SCID itself does for tree masks.
proc ::moderne::prepa::statsReference {chemin} {
  variable baseRef
  if {![refActive]} { return {} }
  # (cache shared with the library: going back to a line is instantaneous)
  set k "ref|$baseRef|[sc_base filename $baseRef]|[sc_base numGames $baseRef]|$chemin|$::moderne::prepa::eloRef"
  if {[dict exists $::moderne::biblio::cache $k]} { return [dict get $::moderne::biblio::cache $k] }
  # Line of the main board (the usual case: the trees follow
  # the board): same search as the library, interruptible and
  # keeping the interface responsive, without going through the clipbase
  set ici {}
  catch {set ici [sc_game moves nonums]}
  if {![sc_game startBoard] && $chemin eq $ici} {
    set eloRef $::moderne::prepa::eloRef
    if {![string is integer -strict $eloRef] || $eloRef < 0} { set eloRef 0 }
    lassign [::moderne::biblio::chercherIci $baseRef [list -minelo $eloRef]] total lignes
    if {$total == -1} { return -1 }
    set res {}
    set rang 0
    foreach l $lignes {
      lassign $l - aff n pct score nulles elo perf derniere
      lappend res [list [incr rang] $aff $n $pct $score $nulles $elo $perf $derniere]
    }
    ::moderne::biblio::memoriser $k $res
    return $res
  }
  set res [statsReferenceCalcul $chemin]
  if {[llength $res]} { ::moderne::biblio::memoriser $k $res }
  return $res
}

proc ::moderne::prepa::statsReferenceCalcul {chemin} {
  variable baseRef
  set courante [sc_base current]
  sc_base switch clipbase
  sc_game push copyfast
  set res {}
  if {![catch {
    # (no "sc_game new": it would erase the clipbase's game number)
    sc_game startBoard "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
    if {[llength $chemin]} { sc_move addSan $chemin }
    # Minimum rating of both players (-minelo option added to the C++: Siby)
    set eloRef $::moderne::prepa::eloRef
    if {![string is integer -strict $eloRef] || $eloRef < 0} { set eloRef 0 }
    # (guard against a nested search from the Tree window: see biblio.tcl)
    set ::moderne::biblio::enCours 1
    set code [catch {sc_tree search -base $baseRef -list 1 -adjust 0 -nsb 1 -minelo $eloRef} res]
    set ::moderne::biblio::enCours 0
    if {$code} { error $res }
  } err]} {
  } else {
    set res {}
  }
  sc_game pop
  sc_base switch $courante
  # The search replaced the tree state of the reference database (shared
  # with its Tree window: best games, jump to the right move, training
  # mode); it is recomputed for the main board's position.
  if {[winfo exists .treeWin$baseRef]} { after idle [list ::tree::refresh $baseRef] }
  return $res
}

proc ::moderne::prepa::majReference {} {
  variable w
  variable enfants
  variable baseRef
  if {![winfo exists $w]} { return }
  set ligne [ligneChoisie]
  if {$ligne eq {}} { return }
  lassign $ligne couleur chemin
  set f $w.nb.$couleur.pw.d
  set t $f.t
  if {![refActive]} {
    $t delete [$t children {}]
    $f.titre configure -text [T "Référence : aucune base de référence ouverte" "Reference: no reference database open"]
    return
  }
  $f.titre configure -text "[T "Référence : recherche…" "Reference: searching…"]"
  set lignes [statsReference $chemin]
  # (search interrupted, or another search running: try again)
  if {$lignes eq "-1"} {
    after cancel ::moderne::prepa::majReference
    after 250 ::moderne::prepa::majReference
    return
  }
  # (the selection changed during the search)
  if {[ligneChoisie] ne $ligne} { return }
  $t delete [$t children {}]

  # The player's moves from this position
  array set lui {}
  if {[info exists enfants([noeud $couleur $chemin])]} {
    foreach coup $enfants([noeud $couleur $chemin]) {
      # sc_tree returns the moves in the interface language (Cc6 in French):
      # so we compare with the translated form of the player's moves
      set lui([::trans $coup]) [lindex [stat [noeud $couleur [concat $chemin [list $coup]]]] 0]
    }
  }
  set total 0
  foreach l $lignes {
    # (the original "average year" column now holds the date of the
    # most recent game: see treeLastDateString in src/tkscid.cpp)
    lassign $l rang coup n pct score nulles elo perf derniere
    # (the last line of sc_tree is the total, without a rank)
    if {![string is integer -strict $rang] || ![string is integer -strict $n]} { continue }
    # "[end]": games that ended in this position (this is not a move)
    if {[string index $coup 0] eq "\["} { continue }
    incr total $n
    set tag {}
    set nLui {}
    if {[info exists lui($coup)]} { set tag joue ; set nLui $lui($coup) ; unset lui($coup) }
    $t insert {} end -text $coup -tags $tag -values [list $nLui \
        [::utils::thousands $n] "[expr {round($pct)}] %" "$score %" $nulles $elo $derniere]
  }
  # The player's moves unknown to the reference (out of book, rarities)
  foreach coup [array names lui] {
    $t insert {} end -text $coup -tags horsRef -values [list $lui($coup) 0 {} {} {} {} {}]
  }
  ::moderne::zebrer $t
  if {[llength $chemin]} {
    set apres "[T "après" "after"] [texteLigne $chemin]"
  } else {
    set apres [T "position initiale" "initial position"]
  }
  set filtreElo {}
  if {[string is integer -strict $::moderne::prepa::eloRef] && $::moderne::prepa::eloRef > 0} {
    set filtreElo ", Elo ≥ $::moderne::prepa::eloRef"
  }
  $f.titre configure -text "[T "Référence" "Reference"] ([::moderne::nomBase [sc_base filename $baseRef]]$filtreElo), $apres[T " : " ": "][::utils::thousands $total] [T parties games]"
}

### Readable "1.e4 c5 2.Nf3" line for a path
proc ::moderne::prepa::texteLigne {chemin} {
  set res {}
  set i 0
  foreach coup $chemin {
    if {$i % 2 == 0} { append res "[expr {$i / 2 + 1}].$coup " } else { append res "$coup " }
    incr i
  }
  return [::trans [string trim $res]]
}

proc ::moderne::prepa::remplirParties {} {
  variable w
  variable parties
  variable filtreLigne
  variable joueur
  set t $w.nb.parties.t
  $t delete [$t children {}]
  set liste {}
  foreach p $parties {
    if {$filtreLigne ne {}} {
      lassign $filtreLigne couleur chemin
      if {[dict get $p couleur] ne $couleur} { continue }
      if {[lrange [dict get $p coups] 0 [expr {[llength $chemin] - 1}]] ne $chemin} { continue }
    }
    lappend liste $p
  }
  set liste [lsort -decreasing -command ::moderne::comparerDates $liste]
  # (all of them up to 20,000: with only the 1,000 most recent, sorting by
  # date never showed the oldest games, Yosha 2026-11-05)
  set max 20000
  foreach p [lrange $liste 0 [expr {$max - 1}]] {
    set couleur [dict get $p couleur]
    set score [scoreJoueur [dict get $p res] $couleur]
    set tag {}
    if {$score eq 1} { set tag gain } elseif {$score eq 0} { set tag perte }
    set res [string map {=-= ½-½} [dict get $p res]]
    $t insert {} end -id g[dict get $p base]_[dict get $p gnum] -tags $tag -values [list \
        [date [dict get $p date]] \
        [lindex [list [T Noirs Black] [T Blancs White]] [expr {$couleur eq "white"}]] \
        [dict get $p adversaire] [dict get $p elo] $res [dict get $p eco] [dict get $p tournoi] \
        [texteLigne [lrange [dict get $p coups] 0 9]]]
  }
  ::moderne::zebrer $t
  set n [llength $liste]
  if {$filtreLigne eq {}} {
    set txt [T "Toutes ses parties, les plus récentes d'abord" "All games, most recent first"]
  } else {
    set qui [lindex [list [T "avec les Noirs" "as Black"] [T "avec les Blancs" "as White"]] [expr {[lindex $filtreLigne 0] eq "white"}]]
    set txt "[T "Ligne" "Line"] : [texteLigne [lindex $filtreLigne 1]]  ($qui)"
  }
  append txt " • [::utils::thousands $n] [T parties games]"
  if {$n > $max} { append txt " ([T "les $max plus récentes affichées" "showing the $max most recent"])" }
  set ::moderne::prepa::texteFiltre $txt
}

proc ::moderne::prepa::majResume {} {
  variable w
  variable joueur
  variable parties
  if {![llength $parties]} {
    set msg [T "Aucune partie trouvée pour « $joueur » avec ces filtres." \
               "No games found for \"$joueur\" with these filters."]
    if {$::moderne::prepa::cadence ne {}} {
      append msg " " [T "(Le filtre de cadence utilise les drapeaux 1/2/3 ou l'en-tête « Cadence » de Gaby ; cette base ne les a peut-être pas.)" \
                        "(The time-control filter uses Gaby's flags 1/2/3 or \"Cadence\" header; this database may not have them.)"]
    }
    $w.resume configure -text $msg
    return
  }
  # The player's exact name (the most frequent one in their games: the
  # field may hold only the start of it, "Carlsen, Magn")
  set noms {}
  foreach p $parties { dict incr noms [dict get $p nom] }
  set nomAff [string trim $joueur] ; set best 0
  dict for {nm c} $noms { if {$c > $best} { set best $c ; set nomAff $nm } }
  variable nomAffiche $nomAff
  # Years: unknown dates ("????") left out
  set dates {}
  foreach p $parties {
    set d [dict get $p date]
    if {[regexp {^[0-9]{4}} $d]} { lappend dates $d }
  }
  set dates [lsort $dates]
  # (over the board only when the online games are left out: said, the
  # name list counts all the games of the database)
  set otb 0
  catch {set otb [::moderne::otb::exclure $::moderne::prepa::base]}
  set txt "$nomAff • [::utils::thousands [llength $parties]] [expr {$otb && $::moderne::prepa::source eq "base" ? [T "parties sur l'échiquier" "over-the-board games"] : [T parties games]}]"
  if {$::moderne::prepa::cadence ne {}} { append txt " ($::moderne::prepa::cadence)" }
  if {[llength $dates]} {
    set a1 [string range [lindex $dates 0] 0 3]
    set a2 [string range [lindex $dates end] 0 3]
    append txt " ([expr {$a1 eq $a2 ? $a1 : "$a1–$a2"}])"
    append txt "   •   [T "Dernière partie" "Last game"] : [date [lindex $dates end]]"
  }
  # Most recent known rating of the player
  set recent [lsort -decreasing -command ::moderne::comparerDates $parties]
  foreach p $recent {
    if {[string is integer -strict [dict get $p sonElo]] && [dict get $p sonElo] > 0} {
      set d [date [dict get $p date]]
      append txt "   •   Elo : [dict get $p sonElo][expr {$d eq {} ? {} : " ($d)"}]"
      break
    }
  }
  # (second line: the scores by colour; on one line it was cut off)
  set lig2 {}
  foreach {couleur nom} [list white [T "Blancs" "White"] black [T "Noirs" "Black"]] {
    if {![llength [stat [noeud $couleur {}]]]} { continue }
    lassign [stat [noeud $couleur {}]] n g d p
    lappend lig2 "$nom : [::utils::thousands $n] (+$g =$d −$p, [pourcent [expr {$g + 0.5 * $d}] [expr {$g + $d + $p}]])"
  }
  if {[llength $lig2]} { append txt "\n[join $lig2 {   •   }]" }
  $w.resume configure -text $txt
  # (Siby: the player's photo, like Chess.com)
  catch {$w.photoJ configure -image [::moderne::avatars::photo $nomAff 43]}
  $w.resume configure -image {} -justify left
  # (their highest FIDE title: the FIDE card of Gaby's players pack, found
  # by the FIDE id of their games, else the photos pack's card)
  set tit {}
  catch {
    lassign [::moderne::fiche::donneesFide $parties] id carte
    if {$carte ne {}} { set tit [::moderne::fide::titres [dict get $carte titre] [dict get $carte titre_f]] }
  }
  if {$tit eq {}} { catch {set tit [::moderne::avatars::titreFide $nomAff]} }
  catch {
    $w.titreJ configure -text $tit -padx [expr {$tit eq {} ? 0 : 4}]
    set ch [::moderne::avatars::marqueChampion $w.championJ $nomAff]
    $w.championJ configure -padding [expr {$ch ? {0 2 0 0} : 0}]
  }
}

################################################################################
### Actions
################################################################################

### Line chosen in the tree of the visible tab: {color path} or {}
proc ::moderne::prepa::ligneChoisie {} {
  variable w
  variable cheminNoeud
  set onglet [$w.nb select]
  if {$onglet ni [list $w.nb.white $w.nb.black]} { return {} }
  set t $onglet.pw.g.t
  set item [$t focus]
  if {$item eq {} || ![info exists cheminNoeud($t,$item)]} { return {} }
  return $cheminNoeud($t,$item)
}

### Puts the main board on line chemin (moves in English notation):
### in the current game if it starts with this line, otherwise in a
### new game
proc ::moderne::prepa::allerA {chemin} {
  set partie {}
  catch {set partie [sc_game moves nonums]}
  set n [llength $chemin]
  set special 0
  catch {set special [sc_game startBoard]}
  if {!$special && [lrange $partie 0 [expr {$n - 1}]] eq $chemin} {
    sc_move start
    if {$n > 0} { sc_move forward $n }
  } else {
    set r [::game::ConfirmDiscardOnglet]
    if {$r == 2} { return }
    if {$r == 0} { ::game::Save }
    setTrialMode 0
    sc_game new
    catch {sc_move addSan $chemin}
    # (a line shown from the tree is not a game to save: no "this game
    # was modified" afterwards, unless moves are then played)
    catch {sc_game setaltered 0}
  }
  updateBoard -pgn
}

### Shows the position of the chosen line on the main board,
### oriented from the point of view of the player's opponent (you).
proc ::moderne::prepa::voirPosition {} {
  variable w
  set ligne [ligneChoisie]
  if {$ligne eq {}} {
    tk_messageBox -parent $w -icon info -type ok -title Siby \
        -message [T "Choisis d'abord un coup dans l'un des deux arbres." \
                    "First select a move in one of the two trees."]
    return 0
  }
  lassign $ligne couleur chemin
  set confirm [::game::ConfirmDiscardOnglet]
  if {$confirm == 2} { return 0 }
  if {$confirm == 0} { ::game::Save }
  setTrialMode 0
  sc_game new
  if {[catch {sc_move addSan $chemin} err]} {
    tk_messageBox -parent $w -icon error -type ok -title Siby -message $err
  }
  catch {sc_game setaltered 0}
  # You are playing against them: if they have White, you have Black
  set retourne [expr {$couleur eq "white"}]
  if {[::board::isFlipped .main.board] != $retourne} { ::board::flip .main.board }
  updateBoard -pgn
  updateTitle
  refreshWindows
  return 1
}

### Position on the board + opening tree of the reference database
proc ::moderne::prepa::reference {} {
  variable baseRef
  if {![voirPosition]} { return }
  set b [expr {[refActive] ? $baseRef : $::moderne::prepa::base}]
  # First let the updates triggered by the new board finish
  # (otherwise the tree gets a refresh before it is ready)
  update idletasks
  after 300 [list ::tree::Open $b]
}

### Loads a game from the list
proc ::moderne::prepa::chargerPartie {t {x {}} {y {}}} {
  set item [ligneVisee $t $x $y]
  ::moderne::onglets::journal "click in the Games tab at $x,$y: row '$item'"
  if {![regexp {^g([0-9]+)_([0-9]+)$} $item -> b gnum]} { return }
  # (in a new notation tab: the game looked at before stays in its tab)
  if {![::moderne::onglets::ouvrir $b $gnum]} { return }
  partieChargee
}

### One click on a game of a list opens it (as on Lichess); not on the
### column headings
proc ::moderne::prepa::clicPartie {t x y cmd} {
  if {[$t identify region $x $y] ni {cell tree}} {
    ::moderne::onglets::journal "click outside the rows ([$t identify region $x $y]) in $t"
    return
  }
  {*}$cmd $t $x $y
}

### The game opened is on the board: said briefly (the notation may be a
### tab hidden behind the preparation)
proc ::moderne::prepa::partieChargee {} {
  set b [sc_game info white] ; set n [sc_game info black]
  catch {::moderne::nsb::annonce "[T "Partie ouverte" "Game opened"] : $b – $n" -1}
  after 2500 {catch ::moderne::nsb::finAnnonce}
}

### End Siby

### The settings row shown or hidden (gear), the gear marked while a
### setting filters
proc ::moderne::prepa::basculerReglages {} {
  set ::moderne::prepa::reglagesOuverts [expr {![info exists ::moderne::prepa::reglagesOuverts] || !$::moderne::prepa::reglagesOuverts}]
  afficherReglages
}

proc ::moderne::prepa::afficherReglages {} {
  variable w
  if {![info exists ::moderne::prepa::reglagesOuverts]} { set ::moderne::prepa::reglagesOuverts 0 }
  set f $w.filtres
  if {![winfo exists $f.reg]} { return }
  if {$::moderne::prepa::reglagesOuverts} { grid $f.plus } else { grid remove $f.plus }
  marquerReglages
}

proc ::moderne::prepa::marquerReglages {} {
  variable w
  set f $w.filtres
  if {![winfo exists $f.reg]} { return }
  set actif 0
  foreach v {eloRef eloMin} {
    catch {if {[string is integer -strict [set ::moderne::prepa::$v]] && [set ::moderne::prepa::$v] > 0} { set actif 1 }}
  }
  catch {if {[string trim $::moderne::prepa::depuis] ne {}} { set actif 1 }}
  # (a word with the gear, and an arrow: open or closed, Yosha 2026-11-04)
  set ouvert [expr {[info exists ::moderne::prepa::reglagesOuverts] && $::moderne::prepa::reglagesOuverts}]
  $f.reg configure -text "⚙ [T Réglages Settings][expr {$actif ? " •" : ""}] [expr {$ouvert ? "▴" : "▾"}]"
}

### "Me": the player of My profile (opened if the profile is empty)
proc ::moderne::prepa::moi {} {
  variable joueur
  variable compteLichess
  variable compteChesscom
  if {[string trim $::moderne::profilNom] eq {}} { ::moderne::profil::ouvrir ; return }
  set joueur $::moderne::profilNom
  set compteLichess $::moderne::profilLichess
  set compteChesscom $::moderne::profilChesscom
  lancer
}
