
###
### Siby: opening library that follows the board
###
### Like ChessBase's opening reference: a table of the moves played
### in the main board's position (transpositions included),
### updated after every move. A double-click (or Enter) on a move plays it
### on the board; ← and → go back and forward in the game.
###
### Two uses:
###   - Tools › Opening library: the chosen reference database
###     (Gaby) with its best games in the position;
###   - the "Library" tab of the preparation against a player
###     (tcl/moderne/prepa.tcl), which adds the player's moves and games.
###
### The statistics come from SCID's tree (sc_tree search), with its
### position cache (.stc): frequent positions are instantaneous.
### outils/bibliotheque.sh fills this cache in advance for a large database.
###

namespace eval ::moderne::biblio {
  variable w .biblioWin
  variable base 0          ;# reference database (slot)
  variable base2 0         ;# second database added to the statistics (0 = none)
  variable eloMin 0        ;# minimum rating of both players (0 = all)
  variable depuis {}       ;# minimum year (empty = all)
  variable cadence {}      ;# {} (all), classical, rapid, blitz (flags 1/2/3)
  variable noteFiltre {}   ;# note on the filters of the last search
  variable maxParties 200  ;# games shown below the table
  variable abonnes {}      ;# procedures called when the board changes
  variable enCours 0       ;# a library tree search is running
  variable drapeaux        ;# drapeaux(file|count): does the database have time-control flags
  array set drapeaux {}
  variable san             ;# san(table,item): move in English notation
  array set san {}
  # Tree search cache (Siby): going back to a position already
  # seen is instantaneous. Key: database, file, game count, position, filters.
  variable cache [dict create]
  variable ordreCache {}
  variable maxCache 400
  variable cleCourante     ;# cleCourante(base): last position requested
  array set cleCourante {}
  variable optsCourantes   ;# optsCourantes(base): its filters
  array set optsCourantes {}
  variable cleArbre        ;# cleArbre(base): position of SCID's tree state
  array set cleArbre {}
  variable progres {}      ;# canvas of the progress bar
  variable positionEnCours {} ;# position of the running search
}

proc ::moderne::biblio::cleRecherche {b opts} {
  return "$b|[sc_base filename $b]|[sc_base numGames $b]|[cle [sc_pos board]]|$opts"
}

proc ::moderne::biblio::memoriser {k v} {
  variable cache
  variable ordreCache
  variable maxCache
  if {![dict exists $cache $k]} { lappend ordreCache $k }
  dict set cache $k $v
  while {[llength $ordreCache] > $maxCache} {
    dict unset cache [lindex $ordreCache 0]
    set ordreCache [lrange $ordreCache 1 end]
  }
}

### Canvas of the progress bar: the library's thin line if it
### is open, otherwise a hidden canvas (the progress mostly serves to
### keep the interface responsive during a long search)
proc ::moderne::biblio::canevasProgres {} {
  variable w
  if {[winfo exists $w.prog]} { return $w.prog }
  if {![winfo exists .moderneProgres]} {
    canvas .moderneProgres -width 100 -height 2
    .moderneProgres create rectangle 0 0 0 0 -tags bar
  }
  return .moderneProgres
}

### A reference to compare with: Database 2 chosen in the preparation
### (elsewhere, always)
proc ::moderne::biblio::refChoisie {} {
  set r 1
  catch {
    if {[winfo exists $::moderne::prepa::w]} { set r [::moderne::prepa::refActive] }
  }
  return $r
}

proc ::moderne::biblio::T {fr en} { return [::moderne::tr $fr $en] }

### Called by updateBoard3 (tcl/main.tcl) after every position change
proc ::moderne::biblio::suivre {} {
  variable abonnes
  if {![llength $abonnes]} { return }
  after cancel ::moderne::biblio::majAbonnes
  after 120 ::moderne::biblio::majAbonnes
}

proc ::moderne::biblio::majAbonnes {} {
  variable abonnes
  # A search of the Tree window is running (we are called during
  # its progress bar): do not start a nested search on the
  # same tree state, try again a little later
  if {[info exists ::tree(refresh)] && $::tree(refresh)} {
    after cancel ::moderne::biblio::majAbonnes
    after 150 ::moderne::biblio::majAbonnes
    return
  }
  # Our search is running for a position already left behind:
  # interrupt it and start again on the new position
  variable enCours
  variable positionEnCours
  if {$enCours} {
    # (only if it is searching a position other than the board's)
    if {$positionEnCours ne [cle [sc_pos board]]} { catch {sc_progressBar} }
    after cancel ::moderne::biblio::majAbonnes
    after 100 ::moderne::biblio::majAbonnes
    return
  }
  foreach a $abonnes {
    if {[catch {uplevel #0 $a} err]} {
      catch {::splash::add "Bibliothèque : $err"}
      # (in siby.log too: the broadcast's library stayed on one position,
      # Yosha 2026-11-11)
      catch {::moderne::rapport::journal "Library: $a: $err\n[string range $::errorInfo 0 600]"}
    }
  }
}

### <Destroy> also arrives for each child widget: only unsubscribe when
### the window itself is closed
proc ::moderne::biblio::fermeture {widget fenetre cmd} {
  if {$widget eq $fenetre} { desabonner $cmd }
}

proc ::moderne::biblio::abonner {cmd} {
  variable abonnes
  if {$cmd ni $abonnes} { lappend abonnes $cmd }
}

proc ::moderne::biblio::desabonner {cmd} {
  variable abonnes
  set abonnes [lsearch -all -inline -not -exact $abonnes $cmd]
}

### Key of a position: the 64 squares and the side to move (sc_pos board format)
proc ::moderne::biblio::cle {plateau} {
  return "[string range $plateau 0 63][string index $plateau 65]"
}

### Statistics of the reference database in the main board's
### position. Returns {total lines}, each line being
### {sanEnglish sanDisplayed n pct score draws elo perf latest}.
proc ::moderne::biblio::statsIci {baseRef eloMin {depuis {}} {cadence {}}} {
  variable noteFiltre
  set noteFiltre {}
  if {!$baseRef || ![sc_base inUse $baseRef]} { return {0 {}} }
  if {![string is integer -strict $eloMin] || $eloMin < 0} { set eloMin 0 }
  set opts [list -minelo $eloMin]
  if {[string is integer -strict $depuis] && $depuis > 0} { lappend opts -since $depuis }
  set drapeau 0
  if {$cadence ne {}} { set drapeau [::moderne::cadence::numero $cadence] }
  # Database without time-control flags (other than Gaby): the
  # filter would yield nothing; it is ignored and reported (decided for the
  # whole database, not position by position)
  if {$drapeau && ![aDrapeaux $baseRef]} {
    set drapeau 0
    set noteFiltre [T "cadence ignorée : cette base n'a pas les drapeaux de cadence" "time control ignored: no time-control flags in this base"]
  }
  set r [chercherIci $baseRef [concat $opts [expr {$drapeau ? [list -flag $drapeau] : {}}]]]
  # With a filter, the tree state shared with the Tree window is that
  # of a filtered search: it is recomputed if that window is open.
  if {($eloMin > 0 || [llength $opts] > 2 || $drapeau) && [winfo exists .treeWin$baseRef]} {
    after idle [list ::tree::refresh $baseRef]
  }
  return $r
}

### Does database b have time-control flags (1 / 2 / 3)? Samples at
### most 3000 games spread over the database; result kept per database.
proc ::moderne::biblio::aDrapeaux {b} {
  variable drapeaux
  set cle "[sc_base filename $b]|[sc_base numGames $b]"
  if {[info exists drapeaux($cle)]} { return $drapeaux($cle) }
  set oui 0
  set n [sc_base numGames $b]
  set courante [sc_base current]
  if {$courante != $b} { sc_base switch $b }
  set pas [expr {max(1, $n / 3000)}]
  for {set g 1} {$g <= $n && !$oui} {incr g $pas} {
    foreach k {1 2 3 4} {
      if {![catch {sc_game flag $k $g} v] && $v eq "1"} { set oui 1 ; break }
    }
  }
  if {$courante != $b} { sc_base switch $courante }
  set drapeaux($cle) $oui
  return $oui
}

### Tree search in the main board's position; returns
### {total lines}, each line being
### {sanEnglish sanDisplayed n pct score draws elo perf latest}
proc ::moderne::biblio::chercherIci {baseRef opts {avecCache 1}} {
  variable enCours
  variable cache
  variable cleCourante
  variable optsCourantes
  variable cleArbre
  set k [cleRecherche $baseRef $opts]
  set cleCourante($baseRef) $k
  set optsCourantes($baseRef) $opts
  if {$avecCache && [dict exists $cache $k]} { return [dict get $cache $k] }
  # A very large database (Gaby) whose instant library is being built (a
  # new complete Gaby): no full search, it takes minutes and Siby no longer
  # answers (Yosha, 2026-10-30); the views are refreshed when it is ready
  variable attenteNsb
  catch {unset attenteNsb($baseRef)}
  variable tresGrosse
  if {![info exists tresGrosse]} { set tresGrosse 2000000 }
  if {[sc_base numGames $baseRef] > $tresGrosse} {
    set e ok
    catch {set e [lindex [sc_nsb etat $baseRef] 0]}
    # (a time control's library too: missing or being rebuilt, the search
    # read all 11 million games, 11 s while a broadcast game opened,
    # Yosha 2026-11-08)
    set i [lsearch -exact $opts -flag]
    if {$e in {ok partiel} && $i >= 0} {
      set f [lindex $opts [expr {$i + 1}]]
      if {$f in {1 2 3}} {
        set ec ok
        catch {set ec [lindex [sc_nsb etat $baseRef $f] 0]}
        if {$ec ni {ok partiel}} { set e $ec }
      }
    }
    if {$e ni {ok partiel}} {
      set attenteNsb($baseRef) 1
      catch {::moderne::nsb::verifier $baseRef}
      return {-1 {}}
    }
  }
  # A search is already running (we are called during its progress):
  # do not nest it; the caller will be restarted
  if {$enCours} { return {-1 {}} }
  set enCours 1
  variable positionEnCours [cle [sc_pos board]]
  # Progress bar: the search yields to the interface every
  # 5,000 games (no more "Not responding"), and can be interrupted
  set c [canevasProgres]
  catch {
    $c delete bar
    $c create rectangle 0 0 0 0 -tags bar -fill [::moderne::c accent] -outline {}
    sc_progressBar $c bar [expr {max(50, [winfo width $c])}] 2
  }
  set code [catch {sc_tree search -base $baseRef -list 1 -adjust 0 -nsb 1 {*}$opts} res]
  catch {$c coords bar 0 0 0 0}
  set enCours 0
  if {$code || $res in {interrupted canceled}} { return {-1 {}} }
  set cleArbre($baseRef) $k
  set lignes {}
  set total 0
  foreach l $res {
    # (original "average year" column: date of the most recent game)
    lassign $l rang coup n pct score nulles elo perf derniere
    if {![string is integer -strict $rang] || ![string is integer -strict $n]} { continue }
    if {[string index $coup 0] eq "\["} { continue }   ;# [end]: games that end here
    incr total $n
    # (shown through ::trans: figurines, or the chosen letters)
    set coupEn [untrans $coup]
    lappend lignes [list $coupEn [::trans $coupEn] $n $pct $score $nulles $elo $perf $derniere]
  }
  memoriser $k [list $total $lignes]
  return [list $total $lignes]
}

################################################################################
### Move table
################################################################################

### Creates table t. avecJoueur: "Him" columns (preparation)
proc ::moderne::biblio::creerTable {t {avecJoueur 0}} {
  set cols {lui luiScore luiGain luiDer cloud n pct score nulles elo perf derniere}
  ttk::treeview $t -columns $cols -show {tree headings} -selectmode browse
  $t heading #0 -text [T "Coup" "Move"] -anchor w
  foreach {c fr en l ancre} {
    lui      "Ses parties"    "Their games"  80  e
    luiScore "Son score"      "Their score"  80  e
    luiGain  "Surperf"        "Overperf"     75  e
    luiDer   "Sa dernière"    "Their last"  100  center
    cloud    "Cloud"          "Cloud"        70  e
    n        "Parties"        "Games"        85  e
    pct      "%"              "%"            50  e
    score    "Score Blancs"   "White score"  95  e
    nulles   "Nulles"         "Draws"        60  e
    elo      "Elo moy."       "Avg Elo"      70  e
    perf     "Perf"           "Perf"         55  e
    derniere "Dernière fois"  "Last played" 100  center
  } {
    $t heading $c -text [T $fr $en]
    $t column $c -width $l -anchor $ancre -stretch 0
  }
  $t column #0 -width 90 -stretch 1
  if {!$avecJoueur} { $t configure -displaycolumns {cloud n pct score nulles elo perf derniere} }
  set sombre [expr {[::moderne::actif] && $::moderne::theme eq "sombre"}]
  # the player's moves coloured by their Elo gain (green: they play better
  # after it, red: worse; dark: clear, light: slight). Created before "joue":
  # in a treeview, the tag created first wins.
  foreach {tag sombreC clairC} {gain2 #3fb950 #1a7f37 gain1 #9ad6a6 #4c9a5e perte1 #f0a3a3 #c25555 perte2 #f85149 #b31d28} {
    $t tag configure $tag -foreground [expr {$sombre ? $sombreC : $clairC}]
  }
  $t tag configure joue -font font_Bold -foreground [expr {$sombre ? "#6fb3f2" : "#1b62b0"}]
  $t tag configure horsRef -foreground [expr {$sombre ? "#f0b35b" : "#a35a00"}]
  $t tag configure suivant -background [expr {$sombre ? "#3a3f2a" : "#f4f0c8"}]
  ::moderne::tri::activer $t
  # one click plays the move (as on Lichess)
  bind $t <ButtonRelease-1> {::moderne::biblio::jouerClic %W %x %y}
  bind $t <Motion> {+::moderne::biblio::survolTable %W %x %y}
  bind $t <Leave> {+::moderne::biblio::flecheSurvol {}}
  bind $t <Return> [list ::moderne::biblio::jouer $t]
  bind $t <Left> {::move::Back ; break}
  bind $t <Right> {::move::Forward ; break}
  return $t
}

### Fills the table. ref = result of statsIci; lui = dict
### sanEnglish -> {n wins draws losses latest} (empty without a player)
proc ::moderne::biblio::remplir {t ref lui} {
  variable san
  variable vue
  array unset san $t,*
  set vue($t,fen) [sc_pos fen]
  $t delete [$t children {}]
  lassign $ref total lignes
  set suivant [sc_game info nextMoveNT]
  set i 0
  set lignesRef {}
  foreach l $lignes { dict set lignesRef [lindex $l 0] $l }
  # Order: the player's moves (most played first), then the reference's other moves
  set ordre {}
  if {[dict size $lui]} {
    set paires {}
    dict for {c s} $lui { lappend paires [list $c [lindex $s 0]] }
    foreach p [lsort -integer -decreasing -index 1 $paires] { lappend ordre [lindex $p 0] }
  }
  foreach l $lignes { if {[lindex $l 0] ni $ordre} { lappend ordre [lindex $l 0] } }
  foreach c $ordre {
    set valsLui [list {} {} {} {}]
    set tags {}
    if {[dict exists $lui $c]} {
      lassign [dict get $lui $c] n g d p der elos
      # (score over the player's finished games: "*" results do not count)
      set fini [expr {$g + $d + $p}]
      set gain [::moderne::prepa::gainElo $elos]
      # (no expr here: it would turn "+10" into 10)
      if {$gain eq {}} {
        set texteGain –
      } elseif {[lindex $gain 0] > 0} {
        set texteGain "+[lindex $gain 0]"
      } else {
        set texteGain [lindex $gain 0]
      }
      set valsLui [list $n [expr {$fini ? "[expr {round(100.0 * ($g + $d / 2.0) / $fini)}] %" : "–"}] $texteGain [::moderne::prepa::date $der]]
      lappend tags joue
      if {$gain ne {}} {
        lassign $gain gd gsd
        if {abs($gd) >= 5} {
          set fort [expr {abs($gd) >= 20 && abs($gd) > $gsd}]
          lappend tags [expr {$gd > 0 ? ($fort ? "gain2" : "gain1") : ($fort ? "perte2" : "perte1")}]
        }
      }
    }
    if {[dict exists $lignesRef $c]} {
      lassign [dict get $lignesRef $c] - aff n pct score nulles elo perf derniere
      set valsRef [list [::utils::thousands $n] "[expr {round($pct)}] %" "$score %" $nulles $elo $perf $derniere]
    } elseif {$total eq "attente"} {
      # (reference search in progress)
      set aff [::trans $c]
      set valsRef [list … {} {} {} {} {} {}]
    } else {
      set aff [::trans $c]
      set valsRef [list 0 {} {} {} {} {} {}]
      if {[dict exists $lui $c] && [refChoisie]} { lappend tags horsRef }
    }
    if {$c eq $suivant} { lappend tags suivant }
    set id m[incr i]
    set san($t,$id) $c
    $t insert {} end -id $id -text $aff -tags $tags -values [concat $valsLui [list [cloudCoup $t $c]] $valsRef]
  }
  ::moderne::zebrer $t
  cloudTable $t
  cloudDemander $t
  return $total
}

proc ::moderne::biblio::survolTable {t x y} {
  variable san
  set id [$t identify row $x $y]
  if {$id eq {} || ![info exists san($t,$id)]} { flecheSurvol {} ; return }
  flecheSurvol $san($t,$id)
}

### Plays the move chosen in the table on the main board
proc ::moderne::biblio::jouer {t} {
  variable san
  variable vue
  set id [$t focus]
  if {$id eq {} || ![info exists san($t,$id)]} { return }
  # (the table of an earlier position, not redrawn yet: two quick clicks)
  if {[info exists vue($t,fen)] && $vue($t,fen) ne [sc_pos fen]} { return }
  if {[catch {addSanMove $san($t,$id) -animate}]} { return }
  updateBoard -pgn
  focus $t
}

### Click on a move row (not on the headings, which sort the table)
proc ::moderne::biblio::jouerClic {t x y} {
  variable san
  if {[$t identify region $x $y] ni {cell tree}} { return }
  set id [$t identify item $x $y]
  if {$id eq {} || ![info exists san($t,$id)]} { return }
  $t focus $id
  after idle [list ::moderne::biblio::jouer $t]
}

################################################################################
### Preparation library: a table drawn on a canvas (tableau.tcl), so that
### each cell can have its colour: the player's results bar next to the
### reference's, the overperformance coloured, tooltips per cell
################################################################################

proc ::moderne::biblio::creerTablePrepa {cv} {
  set cols {}
  foreach {id fr en ancre type} {
    coup     "Coup"            "Move"          w text
    lui      "Parties"         "Games"         e text
    luiScore "Score"           "Score"         e text
    luiRes   "Résultats"       "Results"       w barre
    surperf  "Surperf"         "Overperf"      e text
    luiDer   "Dernière"        "Last"          center text
    cloud    "Cloud"           "Cloud"         e text
    n        "Parties"         "Games"         e text
    pct      "%"               "%"             e text
    refRes   "Résultats"       "Results"       w barre
    refSurperf "Surperf"       "Overperf"      e text
  } {
    # (average rating, performance and last game: in the bar's tooltip, as
    # on Lichess; the table fits in the panel)
    # (the player's columns and the reference's under their own titles,
    # separated: they were hard to tell apart, 2026-10-29)
    set g [expr {$id in {lui luiScore luiRes surperf luiDer} ? "joueur" : ($id eq "coup" ? "" : "ref")}]
    set col [dict create id $id titre [T $fr $en] ancre $ancre type $type groupe $g]
    # (the overperformances' titles run over the bars on their left: the
    # columns as narrow as "+49")
    if {$id in {surperf refSurperf}} { dict set col titreLibre 1 }
    lappend cols $col
  }
  ::moderne::tableau::creer $cv $cols
  ::moderne::tableau::titreGroupe $cv joueur [T "Joueur·se" "Player"]
  ::moderne::tableau::titreGroupe $cv ref [T "Toutes les parties" "All games"]
  return $cv
}

### Overperformance of a database's move, from its library line: the movers'
### average Elo, their performance and the score (the opponents' average
### taken back from the performance, FIDE's table as in crosstab.cpp).
### scoreJoueur: the mover's score in %. {gain sd n} or {}.
proc ::moderne::biblio::surperfRef {elo perf scoreJoueur n} {
  if {![string is integer -strict $elo] || ![string is integer -strict $perf] || $elo <= 0 || $perf <= 0} { return {} }
  if {![string is double -strict $scoreJoueur] || ![string is integer -strict $n] || $n < 10} { return {} }
  set dp {0 7 14 21 29 36 43 50 57 65 72 80 87 95 102 110 117 125 133 141 149 158 166 175 184 193 202 211 220 230
          240 251 262 273 284 296 309 322 336 351 366 383 401 422 444 470 501 538 589 677 800}
  set pc [expr {max(0, min(100, int(round($scoreJoueur))))}]
  set adv [expr {$pc >= 50 ? $perf - [lindex $dp [expr {$pc - 50}]] : $perf + [lindex $dp [expr {50 - $pc}]]}]
  return [::moderne::prepa::gainEloMoyennes $elo $adv [expr {$scoreJoueur / 100.0}] $n]
}

### Overperformance of a library line of the view {san aff n part b d nr elo perf der}
proc ::moderne::biblio::surperfVue {cv l} {
  variable vue
  lassign $l san aff n part b d nr elo perf der
  if {![info exists vue($cv,fen)] || ![string is double -strict $b] || ![string is double -strict $nr]} { return {} }
  set sj [expr {[lindex $vue($cv,fen) 1] eq "b" ? $nr + $d / 2.0 : $b + $d / 2.0}]
  return [surperfRef $elo $perf $sj $n]
}

### Average level of the games {own rating, opponent's, score}
proc ::moderne::biblio::niveauElos {elos} {
  set s 0.0 ; set k 0
  foreach e $elos { lassign $e r1 r2 ; set s [expr {$s + ($r1 + $r2) / 2.0}] ; incr k }
  return [expr {$k ? $s / $k : 0}]
}

### Last line of the overperformance tooltips: White's usual edge at that level
proc ::moderne::biblio::noteSurperf {niveau} {
  if {![string is double -strict $niveau] || $niveau <= 0} { return {} }
  return "\n[T "Avantage blanc habituel à ce niveau" "Usual White edge at this level"][T " : " ": "]+[::moderne::prepa::avantageBlanc $niveau] Elo"
}

### "+49", "-13" (no expr: it would turn "+10" into 10)
proc ::moderne::biblio::texteSurperf {gain} {
  if {$gain eq {}} { return {} }
  set g [lindex $gain 0]
  if {$g > 0} { return "+$g" }
  return $g
}

### Colour of an overperformance {gain sd}: dark when clear, light when
### slight, nothing near 0
proc ::moderne::biblio::couleurSurperf {gain} {
  if {$gain eq {}} { return {} }
  lassign $gain gd gsd
  if {abs($gd) < 5} { return {} }
  set sombre [expr {[::moderne::actif] && $::moderne::theme eq "sombre"}]
  set fort [expr {abs($gd) >= 20 && abs($gd) > $gsd}]
  if {$gd > 0} {
    if {$fort} { return [expr {$sombre ? "#3fb950" : "#1a7f37"}] }
    return [expr {$sombre ? "#9ad6a6" : "#4c9a5e"}]
  }
  if {$fort} { return [expr {$sombre ? "#f85149" : "#b31d28"}] }
  return [expr {$sombre ? "#f0a3a3" : "#c25555"}]
}

### Fills the preparation table. ref = result of statsIci; lui = dict
### sanEnglish -> {n wins draws losses latest elos}; couleur: the player's
### colour (white / black). Returns the reference's total.
proc ::moderne::biblio::remplirPrepa {cv ref lui couleur {garder 0}} {
  variable vue
  set vue($cv,fen) [sc_pos fen]
  set vue($cv,args) [list $ref $lui $couleur]
  lassign $ref total lignes
  set suivant [sc_game info nextMoveNT]
  set lignesRef {}
  foreach l $lignes { dict set lignesRef [lindex $l 0] $l }
  # Order: the player's moves (most played first), then the reference's others
  set ordre {}
  if {[dict size $lui]} {
    set paires {}
    dict for {c s} $lui { lappend paires [list $c [lindex $s 0]] }
    foreach p [lsort -integer -decreasing -index 1 $paires] { lappend ordre [lindex $p 0] }
  }
  foreach l $lignes { if {[lindex $l 0] ni $ordre} { lappend ordre [lindex $l 0] } }
  set doux [::moderne::c texteDoux]
  set anneeVieux [expr {[clock format [clock seconds] -format %Y] - 5}]
  set rows {}
  foreach c $ordre {
    set cases {}
    set style {}
    set aff [::trans $c]
    if {[dict exists $lui $c]} {
      lassign [dict get $lui $c] n g d p der elos
      lappend style joue
      set fini [expr {$g + $d + $p}]
      dict set cases lui [dict create texte $n tri $n]
      if {$fini} {
        set sc [expr {round(100.0 * ($g + $d / 2.0) / $fini)}]
        dict set cases luiScore [dict create texte "$sc %" tri $sc]
        # her results, White / Draws / Black like the reference's bar
        set pg [expr {round(100.0 * $g / $fini)}] ; set pd [expr {round(100.0 * $d / $fini)}]
        set pp [expr {max(0, 100 - $pg - $pd)}]
        set barre [expr {$couleur eq "white" ? [list $pg $pd $pp] : [list $pp $pd $pg]}]
        dict set cases luiRes [dict create barre $barre tri $sc \
            bulle "+$g =$d −$p ([T "sur" "out of"] $fini [expr {$fini > 1 ? [T parties games] : [T partie game]}])"]
      }
      set gain [::moderne::prepa::gainElo $elos]
      if {$gain ne {}} {
        lassign $gain gd gsd nn
        # (no expr: it would turn "+10" into 10)
        if {$gd > 0} { set t "+$gd" } else { set t $gd }
        set sTot 0.0 ; set eTot 0.0
        foreach e $elos {
          lassign $e r1 r2 s
          set sTot [expr {$sTot + $s}]
          set eTot [expr {$eTot + 1.0 / (1.0 + pow(10.0, ($r2 - $r1) / 400.0))}]
        }
        set bulle "$t Elo [T "par rapport à son classement" "relative to their rating"]"
        append bulle "\n$nn [expr {$nn > 1 ? [T parties games] : [T partie game]}] : [expr {round(100.0 * $sTot / $nn)}] % [T "marqués" "scored"], [expr {round(100.0 * $eTot / $nn)}] % [T "attendus" "expected"]"
        if {$nn < 10} { append bulle " [T "(peu de parties)" "(few games)"]" }
        append bulle [noteSurperf [niveauElos $elos]]
        dict set cases surperf [dict create texte $t tri $gd couleur [couleurSurperf $gain] gras 1 bulle $bulle]
      }
      set dd [::moderne::prepa::date $der]
      if {$dd ne {}} {
        # (the year only: the table fits; the full date on hover)
        set cel [dict create texte [string range $dd 0 3] tri $dd bulle "[T "Dernière partie" "Last game"] : $dd"]
        if {[string range $dd 0 3] < $anneeVieux} {
          # (a move not played for years: faded)
          dict set cel couleur $doux
          dict set cases coup [dict create texte $aff tri $aff couleur $doux]
        }
        dict set cases luiDer $cel
      }
    }
    if {![dict exists $cases coup]} { dict set cases coup [dict create texte $aff tri $aff] }
    if {[dict exists $lignesRef $c]} {
      lassign [dict get $lignesRef $c] - aff2 n pct score nulles elo perf derniere
      dict set cases n [dict create texte [::utils::thousands $n] tri $n]
      dict set cases pct [dict create texte "[expr {round($pct)}] %" tri $pct]
      set r [bnn $score $nulles]
      if {$r ne {}} {
        lassign $r b dn nr
        set bl "[T Blancs White] $b % • [T nulles draws] $dn % • [T Noirs Black] $nr %\n[::utils::thousands $n] [T parties games]"
        if {[string is integer -strict $elo] && $elo > 0} { append bl "\n[T "Elo moyen" "Average Elo"] : $elo" }
        if {[string is integer -strict $perf] && $perf > 0} { append bl "\n[T "Performance" "Performance"] : $perf" }
        if {[string trim $derniere] ne {}} { append bl "\n[T "Dernière partie" "Last played"] : [string trim $derniere]" }
        dict set cases refRes [dict create barre $r tri [string map {% {} " " {}} $score] bulle $bl]
        # the database's overperformance of the move, as the player's
        set sj [expr {[sc_pos side] eq "white" ? $b + $dn / 2.0 : $nr + $dn / 2.0}]
        set gr [surperfRef $elo $perf $sj $n]
        if {$gr ne {}} {
          dict set cases refSurperf [dict create texte [texteSurperf $gr] tri [lindex $gr 0] couleur [couleurSurperf $gr] gras 1 \
              bulle "[texteSurperf $gr] Elo [T "par rapport à leur classement" "relative to their rating"]\n[T "Elo moyen" "Average Elo"] $elo • [T "Perf" "Perf"] $perf[noteSurperf $elo]"]
        }
      }
    } elseif {$total eq "attente"} {
      dict set cases n [dict create texte …]
    } elseif {[dict exists $lui $c] && [refChoisie]} {
      # (orange: a move of the player that the reference never has; with
      # no Database 2 there is nothing to compare with)
      lappend style horsRef
    }
    set ev [cloudCoup $cv $c]
    if {$ev ne {}} { dict set cases cloud [dict create texte $ev tri [string map {# 99} $ev]] }
    if {$c eq $suivant} { lappend style suivant }
    lappend rows [dict create san $c cases $cases style $style]
  }
  set prof [cloudProfondeur $cv]
  ::moderne::tableau::titre $cv cloud [expr {$prof eq {} ? "Cloud" : "Cloud $prof"}]
  ::moderne::tableau::somme $cv [sommePrepa $ref $lui $couleur]
  ::moderne::tableau::remplir $cv $rows $garder
  if {!$garder} { cloudDemander $cv }
  return $total
}

### The Σ row of the preparation's library (Yosha 2026-11-12, as the
### Lichess view's): the player's games in the position, their score and
### results, their overperformance over all of them, their last game; the
### reference's games, 100 %, their results. {} when there is nothing.
proc ::moderne::biblio::sommePrepa {ref lui couleur} {
  lassign $ref total lignes
  set cases {}
  if {[dict size $lui]} {
    set n 0 ; set g 0 ; set d 0 ; set p 0 ; set der {} ; set elos {}
    dict for {c s} $lui {
      lassign $s n1 g1 d1 p1 der1 elos1
      incr n $n1 ; incr g $g1 ; incr d $d1 ; incr p $p1
      set dd [::moderne::prepa::date $der1]
      if {$dd ne {} && [string compare $dd $der] > 0} { set der $dd }
      lappend elos {*}$elos1
    }
    dict set cases lui [dict create texte $n]
    set fini [expr {$g + $d + $p}]
    if {$fini} {
      set sc [expr {round(100.0 * ($g + $d / 2.0) / $fini)}]
      dict set cases luiScore [dict create texte "$sc %"]
      set pg [expr {round(100.0 * $g / $fini)}] ; set pd [expr {round(100.0 * $d / $fini)}]
      set pp [expr {max(0, 100 - $pg - $pd)}]
      dict set cases luiRes [dict create barre [expr {$couleur eq "white" ? [list $pg $pd $pp] : [list $pp $pd $pg]}]]
    }
    set gain [::moderne::prepa::gainElo $elos]
    if {$gain ne {}} {
      set gd [lindex $gain 0]
      dict set cases surperf [dict create texte [expr {$gd > 0 ? "+$gd" : $gd}] couleur [couleurSurperf $gain]]
    }
    if {$der ne {}} { dict set cases luiDer [dict create texte [string range $der 0 3]] }
  }
  if {[string is integer -strict $total] && $total > 0} {
    dict set cases n [dict create texte [::utils::thousands $total]]
    dict set cases pct [dict create texte "100 %"]
    set sB 0.0 ; set sD 0.0 ; set sN 0
    foreach l $lignes {
      lassign $l - - n1 - score nulles
      set r [bnn $score $nulles]
      if {$r eq {} || ![string is integer -strict $n1]} { continue }
      lassign $r b dn nr
      set sB [expr {$sB + $b * $n1}] ; set sD [expr {$sD + $dn * $n1}] ; incr sN $n1
    }
    if {$sN > 0} {
      set b [expr {round($sB / $sN)}] ; set dn [expr {round($sD / $sN)}]
      dict set cases refRes [dict create barre [list $b $dn [expr {max(0, 100 - $b - $dn)}]]]
    }
  }
  return $cases
}

### Position text: "After 1.e4 c5 2.Nf3 (Black to move)"
proc ::moderne::biblio::texteIci {} {
  set coups [string trim [sc_game moves]]
  set trait [expr {[sc_pos side] eq "white" ? [T "trait aux Blancs" "White to move"] : [T "trait aux Noirs" "Black to move"]}]
  if {$coups eq {}} { return "[T "Position de départ" "Start position"] ($trait)" }
  # sc_game moves: "1.e4 c5 2.Nf3" (English notation)
  set res $coups
  if {[string length $res] > 90} { set res "…[string range $res end-88 end]" }
  return "[T "Après" "After"] [::trans [string trim $res]] ($trait)"
}

################################################################################
### General window: Tools › Opening library
################################################################################

### The settings rows shown or hidden (gear button)
proc ::moderne::biblio::basculerReglages {} {
  variable reglagesOuverts
  set reglagesOuverts [expr {!$reglagesOuverts}]
  afficherReglages
}

proc ::moderne::biblio::afficherReglages {} {
  variable w
  variable reglagesOuverts
  set h $w.haut
  if {![winfo exists $h.cadence.reg]} { return }
  if {$reglagesOuverts} { grid $h.plus } else { grid remove $h.plus }
  marquerReglages
}

### The gear marked (accent) while a setting filters the games
proc ::moderne::biblio::marquerReglages {} {
  variable w
  set h $w.haut
  if {![winfo exists $h.cadence.reg]} { return }
  set actif 0
  catch {if {[string is integer -strict $::moderne::biblio::eloMin] && $::moderne::biblio::eloMin > 0} { set actif 1 }}
  catch {if {[string trim $::moderne::biblio::depuis] ne {}} { set actif 1 }}
  catch {if {[string trim $::moderne::biblio::cadence] ni {{} tout toutes all}} { set actif 1 }}
  catch {if {!$::moderne::otb::inclure} { set actif 1 }}
  # (a word with the gear, and an arrow: open or closed, Yosha 2026-11-04)
  set ouvert [expr {[info exists ::moderne::biblio::reglagesOuverts] && $::moderne::biblio::reglagesOuverts}]
  $h.cadence.reg configure -text "⚙ [T Réglages Settings][expr {$actif ? " •" : ""}] [expr {$ouvert ? "▴" : "▾"}]"
}

proc ::moderne::biblio::ouvrir {} {
  variable w
  variable base
  # "Dockable" window: tab of the main window (SCID's docking
  # mode) or separate window
  if {[winfo exists $w]} { ::createToplevel $w ; return }
  if {!$base || ![sc_base inUse $base]} { set base [referenceOuCourante] }
  ::createToplevel $w
  ::setTitle $w [T "Bibliothèque d'ouvertures" "Opening library"]

  set h $w.haut
  ttk::frame $h -padding {10 8 10 4}
  pack $h -side top -fill x
  ttk::label $h.lb -text [T "Base :" "Database:"]
  ttk::combobox $h.base -width 34 -state readonly
  ttk::label $h.le -text [T "Elo min. des deux joueur·ses :" "Min. Elo (both players):"]
  ttk::spinbox $h.elo -width 6 -from 0 -to 3000 -increment 100 -textvariable ::moderne::biblio::eloMin \
      -command ::moderne::biblio::maj
  bind $h.elo <Return> ::moderne::biblio::maj
  ttk::label $h.ld -text [T "Depuis :" "Since:"]
  ttk::spinbox $h.depuis -width 6 -from 1850 -to 2100 -textvariable ::moderne::biblio::depuis \
      -command ::moderne::biblio::maj
  bind $h.depuis <Return> ::moderne::biblio::maj
  ttk::label $h.lc -text [T "Cadence :" "Time control:"]
  ::moderne::cadence::barre $h.cadence ::moderne::biblio::cadence ::moderne::biblio::maj \
      {expr {$::moderne::biblio::base > 0 ? $::moderne::biblio::base : [sc_base current]}}
  # (two rows: the window must fit in a layout column)
  ttk::label $h.lb2 -text [T "+ base :" "+ database:"]
  ttk::combobox $h.base2 -width 30 -state readonly
  grid $h.lb $h.base $h.lb2 $h.base2 - - -padx 4 -pady 1 -sticky w
  # View: Lichess-style bars or detailed table
  set style Toolbutton
  if {![catch {ttk::style layout Segment.Toolbutton} l] && $l ne {}} { set style Segment.Toolbutton }
  ttk::frame $h.vue
  ttk::radiobutton $h.vue.l -text [T "Barres" "Bars"] -style $style -variable ::moderne::biblio::vueLichess -value 1 \
      -command ::moderne::biblio::changerVue
  ttk::radiobutton $h.vue.t -text [T "Tableau" "Table"] -style $style -variable ::moderne::biblio::vueLichess -value 0 \
      -command ::moderne::biblio::changerVue
  pack $h.vue.l $h.vue.t -side left -padx 1
  ::utils::tooltip::Set $h.vue.l [T "Une barre Blancs / Nulles / Noirs par coup, comme sur Lichess (survol : Elo moyen, perf)" "One White / Draw / Black bar per move, as on Lichess (hover: average Elo, perf)"]
  ::utils::tooltip::Set $h.vue.t [T "Tableau détaillé : toutes les colonnes, triables" "Detailed table: all columns, sortable"]
  # (row 1: the time control, always there, and the gear; row 2, behind
  # the gear: Elo, since, online tournaments)
  # (time control on its own row: the window must fit in a column)
  # online tournaments of Gaby included or not, beside the time controls
  # as Lichess's explorer filters (it was in the Search menu)
  ttk::checkbutton $h.otb -text [T "Tournois en ligne" "Online tournaments"] -variable ::moderne::otb::inclure \
      -command {catch ::moderne::otb::basculer}
  catch {::utils::tooltip::Set $h.otb [T "Inclure les tournois en ligne de Gaby (Champions Chess Tour, Olympiade en ligne…)" "Include Gaby's online tournaments (Champions Chess Tour, Online Olympiad…)"]}
  grid $h.vue -row 0 -column 6 -padx {12 4} -sticky e
  # The settings seldom changed (Elo, since, online tournaments) behind a
  # gear, as Lichess's explorer: the table gets
  # their two rows (Yosha 2026-11-04); the gear is marked while one of
  # them filters
  # (in the time controls' row, just after them)
  ttk::button $h.cadence.reg -text "⚙" -style Toolbutton -command ::moderne::biblio::basculerReglages
  pack $h.cadence.reg -side left -padx {14 0}
  catch {::utils::tooltip::Set $h.cadence.reg [T "Réglages : Elo minimum, depuis, tournois en ligne" "Settings: minimum Elo, since, online tournaments"]}
  # (the gear right after the time controls: at the far right it went off
  # the panel with the English labels)
  grid $h.lc $h.cadence -row 1 -padx 4 -pady 1 -sticky w
  # (in a frame of their own: shown, they do not widen the columns of the
  # rows above, which moved)
  ttk::frame $h.plus
  grid $h.plus -row 2 -column 0 -columnspan 8 -sticky w
  grid $h.le $h.elo $h.ld $h.depuis $h.otb -in $h.plus -row 0 -padx 4 -pady 1 -sticky w
  foreach x {le elo ld depuis otb} { raise $h.$x $h.plus }
  variable reglagesOuverts
  if {![info exists reglagesOuverts]} { set reglagesOuverts 0 }
  afficherReglages
  bind $h.base <<ComboboxSelected>> {
    set ::moderne::biblio::base [::moderne::prepa::slotDepuisLibelle [%W get]]
    catch {::moderne::mesbases::retenirReference $::moderne::biblio::base}
    ::moderne::biblio::maj
  }
  bind $h.base <Button-1> {+::moderne::biblio::majBases}
  # Second database (e.g. one's own games or courses) added to the statistics
  bind $h.base2 <<ComboboxSelected>> {
    set ::moderne::biblio::base2 [::moderne::prepa::slotDepuisLibelle [%W get]]
    if {![string is integer -strict $::moderne::biblio::base2]} { set ::moderne::biblio::base2 0 }
    ::moderne::biblio::maj
  }
  bind $h.base2 <Button-1> {+::moderne::biblio::majBases}
  majBases

  ttk::label $w.pos -font font_Bold -padding {12 2} -text {}
  pack $w.pos -side top -fill x
  # Siby: state of the instant library (.sbl), below the position
  ttk::label $w.nsb -foreground [::moderne::c accent] -padding {12 0} -text {}
  canvas $w.prog -height 2 -highlightthickness 0 -borderwidth 0 -background [::moderne::c fond]
  pack $w.prog -side top -fill x -padx 10

  ttk::panedwindow $w.pw -orient vertical
  pack $w.pw -side top -fill both -expand 1 -padx 10 -pady {0 10}
  ttk::frame $w.pw.h
  ttk::frame $w.pw.b
  $w.pw add $w.pw.h -weight 3
  $w.pw add $w.pw.b -weight 2
  creerTable $w.pw.h.t 0
  creerVue $w.pw.h.cv
  ttk::scrollbar $w.pw.h.sb -command [list $w.pw.h.t yview]
  $w.pw.h.t configure -yscrollcommand [list $w.pw.h.sb set]
  changerVue

  ttk::label $w.pw.b.titre -padding {2 6 2 2} -text [T "Meilleures parties dans cette position" "Best games in this position"]
  pack $w.pw.b.titre -side top -anchor w
  creerListeParties $w.pw.b.t
  ttk::scrollbar $w.pw.b.sb -command [list $w.pw.b.t yview]
  $w.pw.b.t configure -yscrollcommand [list $w.pw.b.sb set]
  pack $w.pw.b.sb -side right -fill y
  pack $w.pw.b.t -side left -fill both -expand 1
  bind $w.pw.b.t <Double-Button-1> {::moderne::biblio::chargerMeilleure %W ; break}
  bind $w.pw.b.t <Return> {::moderne::biblio::chargerMeilleure %W}
  installerSurvolParties $w.pw.b.t ::moderne::biblio::base

  ttk::label $w.aide -padding {12 0 12 8} -foreground gray50 -text [T \
      "Clic (barres) ou double-clic (tableau) : jouer le coup • ← → : reculer / avancer • clic sur un en-tête : trier • suit l'échiquier principal" \
      "Click (bars) or double-click (table): play the move • ← →: back / forward • click a header to sort • follows the main board"]
  catch {::moderne::enBulle $w.aide}
  pack $w.aide -side bottom -fill x
  bind $w <Escape> [list ::moderne::echap $w]
  bind $w <Destroy> [list ::moderne::biblio::fermeture %W $w ::moderne::biblio::majSiChange]
  # (the board followed: searched only when the position or the database
  # changed)
  abonner ::moderne::biblio::majSiChange
  # (in docking mode, it is the tab's container frame that is shown
  # or hidden; the embedded window stays "shown")
  set cadre .fdock[string range $w 1 end]
  if {[winfo exists $cadre]} {
    bind $cadre <Map> ::moderne::biblio::majSiChange
  } else {
    bind $w <Map> "if {\"%W\" eq \"$w\"} ::moderne::biblio::majSiChange"
  }
  catch {::moderne::repeindre $w}
  ::createToplevelFinalize $w
  maj
  focus [expr {$::moderne::biblio::vueLichess ? "$w.pw.h.cv" : "$w.pw.h.t"}]
}

proc ::moderne::biblio::majBases {} {
  variable w
  variable base
  variable base2
  # (the library may have been closed since this was scheduled)
  if {![winfo exists $w.haut.base]} { return }
  set libs {}
  foreach {b lib} [::moderne::prepa::bases] { lappend libs $lib }
  $w.haut.base configure -values $libs
  $w.haut.base2 configure -values [concat [list [T "aucune" "none"]] $libs]
  if {[sc_base inUse $base]} { $w.haut.base set [::moderne::prepa::libelleBase $base] }
  if {$base2 && [sc_base inUse $base2]} {
    $w.haut.base2 set [::moderne::prepa::libelleBase $base2]
  } else {
    set base2 0
    $w.haut.base2 set [T "aucune" "none"]
  }
}

### Statistics of several databases merged move by move: games
### added up; score, average rating and perf weighted by the number of
### games; latest date = the most recent one.
proc ::moderne::biblio::statsPlusieurs {bases eloMin depuis cadence} {
  variable noteFiltre
  set note {}
  set ordre {}
  array set m {}
  set total 0
  set totaux {}
  foreach b $bases {
    lassign [statsIci $b $eloMin $depuis $cadence] t lignes
    if {$t == -1} { return {-1 {} {}} }
    if {$noteFiltre ne {}} { set note $noteFiltre }
    incr total $t
    lappend totaux $t
    foreach l $lignes {
      lassign $l san aff n pct score nulles elo perf der
      regsub {%} $nulles {} nulles
      if {![info exists m($san)]} {
        lappend ordre $san
        set m($san) [list $aff 0 0.0 0.0 0.0 0 0.0 0 {}]
      }
      lassign $m($san) a nn sS sN sE nE sP nP d
      incr nn $n
      set sS [expr {$sS + $score * $n}]
      if {[string is double -strict $nulles]} { set sN [expr {$sN + $nulles * $n}] }
      if {[string is integer -strict $elo] && $elo > 0} { set sE [expr {$sE + $elo * $n}] ; incr nE $n }
      if {[string is integer -strict $perf] && $perf > 0} { set sP [expr {$sP + $perf * $n}] ; incr nP $n }
      set d [::moderne::prepa::plusRecente $der $d]
      set m($san) [list $a $nn $sS $sN $sE $nE $sP $nP $d]
    }
  }
  set noteFiltre $note
  set res {}
  foreach san $ordre {
    lassign $m($san) a nn sS sN sE nE sP nP d
    if {$nn == 0} { continue }
    lappend res [list $san $a $nn [expr {100.0 * $nn / max(1, $total)}] [format %.1f [expr {$sS / $nn}]] \
        "[expr {round($sN / $nn)}]%" [expr {$nE ? round($sE / $nE) : ""}] [expr {$nP ? round($sP / $nP) : ""}] $d]
  }
  return [list $total [lsort -integer -decreasing -index 2 $res] $totaux]
}

### Game list (gnum, players, result, date, tournament)
proc ::moderne::biblio::creerListeParties {t} {
  ttk::treeview $t -columns {blanc eloB noir eloN res date tournoi} -show headings -selectmode browse -height 6
  foreach {c fr en l ancre} {
    blanc   Blancs     White   170 w
    eloB    Elo        Elo      50 e
    noir    Noirs      Black   170 w
    eloN    Elo        Elo      50 e
    res     Résultat   Result   70 center
    date    Date       Date    100 center
    tournoi Tournoi    Event   220 w
  } {
    $t heading $c -text [T $fr $en]
    $t column $c -width $l -anchor $ancre -stretch [expr {$c in {blanc noir tournoi}}]
  }
  ::moderne::tri::activer $t
  return $t
}

### The reference database, or else the current one
proc ::moderne::biblio::referenceOuCourante {} {
  set b 0
  catch {set b [::moderne::mesbases::baseReference 0]}
  if {!$b} { set b [sc_base current] }
  return $b
}

proc ::moderne::biblio::maj {} {
  catch marquerReglages
  variable w
  catch {flecheSurvol {}}
  variable base
  variable eloMin
  variable maxParties
  if {![winfo exists $w]} { return }
  # Tab hidden in the layout: no search (it will be done
  # when the tab is shown, see <Map>)
  if {![visible]} { return }
  # (database closed meanwhile: back to the reference database)
  if {!$base || ![sc_base inUse $base]} { set base [referenceOuCourante] ; catch majBases }
  catch {::moderne::nsb::verifier $base}
  catch {::moderne::nsb::majIndicateur}
  $w.pos configure -text [texteIci]
  variable depuis
  variable cadence
  variable noteFiltre
  variable base2
  set bases [list $base]
  if {$base2 && $base2 != $base && [sc_base inUse $base2]} { lappend bases $base2 }
  # During the search: "searching…" and no more old games
  $w.pw.b.titre configure -text "[T "Recherche dans la base…" "Searching the database…"]"
  $w.pw.b.t delete [$w.pw.b.t children {}]
  if {[llength $bases] > 1} {
    # Best games: those of the first database (its tree state is
    # that of its own search)
    set ref [statsPlusieurs $bases $eloMin $depuis $cadence]
    if {[lindex $ref 0] == -1} { attente $base ; return }
    set total [remplir $w.pw.h.t $ref {}]
    remplirVue $w.pw.h.cv $ref
    remplirMeilleures $w.pw.b.t $base [lindex $ref 2 0]
  } else {
    set ref [statsIci $base $eloMin $depuis $cadence]
    if {[lindex $ref 0] == -1} { attente $base ; return }
    set total [remplir $w.pw.h.t $ref {}]
    remplirVue $w.pw.h.cv $ref
    remplirMeilleures $w.pw.b.t $base $total
  }
  set filtre [texteFiltres $eloMin $depuis $cadence]
  set noms [join [lmap b $bases {file tail [sc_base filename $b]}] " + "]
  $w.pw.b.titre configure -text "[::utils::thousands $total] [expr {$total == 1 ? [T "partie dans cette position" "game in this position"] : [T "parties dans cette position" "games in this position"]}] ($noms$filtre) • [T "les meilleures" "best ones"] ([::moderne::nomBase [sc_base filename $base]]) :"
  variable dessine [signature]
}

### What the library shows depends on (to skip a search already shown)
proc ::moderne::biblio::signature {} {
  variable base
  variable base2
  variable eloMin
  variable depuis
  variable cadence
  set l [list $base $base2 $eloMin $depuis $cadence $::moderne::biblio::vueLichess]
  catch {lappend l [sc_pos fen] [sc_base numGames $base]}
  return $l
}

### The tab shown again: searched only if something changed since the last
### display (opening the Lab searched twice, once when the library was made
### and once when its tab was shown; Yosha 2026-11-02)
proc ::moderne::biblio::majSiChange {} {
  variable dessine
  if {[info exists dessine] && $dessine eq [signature]} { return }
  maj
}

### No search yet: said why (instant library being built)
proc ::moderne::biblio::attente {b} {
  variable w
  variable attenteNsb
  if {![info exists attenteNsb($b)]} { return }
  catch {$w.pw.b.titre configure -text [T \
      "Bibliothèque instantanée de [::moderne::nomBase [sc_base filename $b]] en préparation : les coups s'afficheront dès qu'elle sera prête." \
      "Instant library of [::moderne::nomBase [sc_base filename $b]] being built: the moves will show as soon as it is ready."]}
}

### Best games of the position in database b (sc_tree best reads the
### result of the tree search just done by statsIci)
proc ::moderne::biblio::remplirMeilleures {t b total} {
  variable maxParties
  variable cache
  variable cleCourante
  variable optsCourantes
  variable cleArbre
  $t delete [$t children {}]
  if {$total <= 0} { return 0 }
  set k [expr {[info exists cleCourante($b)] ? $cleCourante($b) : {}}]
  if {$k ne {} && [dict exists $cache meilleures|$k]} {
    set best [dict get $cache meilleures|$k]
  } else {
    # sc_tree best reads the tree state of the last real search: if it
    # is for another position (result taken from the cache), redo the
    # search for this one
    if {$k ne {} && (![info exists cleArbre($b)] || $cleArbre($b) ne $k)} {
      if {[lindex [chercherIci $b $optsCourantes($b) 0] 0] == -1} { return 0 }
    }
    if {[catch {sc_tree best $b $maxParties All Best "w*\tW*\tb*\tB*\tr*\td*\te*"} best]} { return 0 }
    if {$k ne {}} { memoriser meilleures|$k $best }
  }
  set n 0
  foreach l [split [string trimright $best \n] \n] {
    # "number<space>tab-separated fields"
    if {![regexp {^([0-9]+) (.*)$} $l -> g reste]} { continue }
    lassign [split $reste \t] blanc eloB noir eloN res date tournoi
    if {![catch {$t insert {} end -id g$g -values [list [string trim $blanc] [string trim $eloB] \
        [string trim $noir] [string trim $eloN] [string map {=-= ½-½} [string trim $res]] [string trim $date] [string trim $tournoi]]}]} {
      incr n
    }
  }
  ::moderne::zebrer $t
  return $n
}

### ", Elo ≥ 2500, since 2020, classical" (or empty)
proc ::moderne::biblio::texteFiltres {eloMin depuis cadence} {
  variable noteFiltre
  set t {}
  if {[string is integer -strict $eloMin] && $eloMin > 0} { append t ", Elo ≥ $eloMin" }
  if {[string is integer -strict $depuis] && $depuis > 0} { append t ", [T depuis since] $depuis" }
  if {$cadence ne {} && $noteFiltre eq {}} { append t ", $cadence" }
  if {$noteFiltre ne {}} { append t " • $noteFiltre" }
  return $t
}

### Is the library visible (tab shown)?
proc ::moderne::biblio::visible {} {
  variable w
  set cadre .fdock[string range $w 1 end]
  if {[winfo exists $cadre]} { return [winfo ismapped $cadre] }
  return [winfo ismapped $w]
}

### Opens one of the best games at the current position
proc ::moderne::biblio::chargerMeilleure {t} {
  variable base
  set id [$t focus]
  if {![string match g* $id]} { return }
  ouvrirPartie $base [string range $id 1 end]
}

### Opens game gnum of database b and goes to the ply where the main
### board's position is reached (otherwise to the start)
proc ::moderne::biblio::ouvrirPartie {b gnum {ply {}}} {
  set cible [cle [sc_pos board]]
  if {$ply eq {} || ![string is integer -strict $ply]} {
    set ply 0
    set i 0
    set courante [sc_base current]
    if {$courante != $b} { sc_base switch $b }
    if {[catch {sc_game boards $gnum} positions]} { set positions {} }
    if {$courante != $b} { sc_base switch $courante }
    foreach p $positions {
      if {[cle [lindex $p 1]] eq $cible} { set ply $i ; break }
      incr i
    }
  }
  # (in a new notation tab: the game looked at before stays in its tab)
  ::moderne::onglets::ouvrir $b $gnum $ply
}


################################################################################
### A game of the list, hovered: its next moves from the board's position on
### one line, just under the game; the pointer going left or right along the
### game picks a move of the line, highlighted, and the board shows the
### position after it (veiled: a preview). The wheel steps too. (Yosha
### 2026-11-06; before: the moves in a bubble on several lines, the board on
### the last one.) Right-click: open, review, merge, copy.
################################################################################

namespace eval ::moderne::biblio {
  variable survolP {}       ;# {treeview row}
  variable survolApres {}
  variable suite {}         ;# {{san board} …} from the board's position
  variable suiteI 0         ;# index shown on the board
  variable suiteDebut 0     ;# ply (in the game) of the board's position
  variable suiteX {}        ;# k → {x0 x1}: each move's place on the line (screen)
  variable suiteK 0         ;# move last picked by the pointer
}

### t: the list; varBase: the variable holding its database number (rows
### "g<game>", or "b<database>_<game>,<ply>" as in the preparation)
proc ::moderne::biblio::installerSurvolParties {t varBase {menu 1} {depuis position}} {
  # (depuis: "position" = the moves after the board's position, for the
  # lists that follow the board; "debut" = from the game's first move, for
  # a list that does not, Prepare's Games tab, Yosha 2026-11-08)
  variable survolDepuis
  set survolDepuis($t) $depuis
  bind $t <Motion> [list ::moderne::biblio::survolPartie %W $varBase %x %y %X %Y]
  bind $t <Leave> {after 30 [list ::moderne::biblio::quitterListe %W]}
  # (the wheel scrolls the list, as before; Ctrl+wheel steps through the
  # hovered game's moves, Yosha 2026-11-06)
  # (break: the list's own wheel handling did it too, Ctrl+wheel scrolled
  # the list as well as the moves)
  bind $t <MouseWheel> "[list ::moderne::biblio::defilerListe %W %D] ; break"
  bind $t <Button-4> "[list ::moderne::biblio::defilerListe %W 120] ; break"
  bind $t <Button-5> "[list ::moderne::biblio::defilerListe %W -120] ; break"
  bind $t <Control-MouseWheel> "[list ::moderne::biblio::pasSuite %W %D] ; break"
  bind $t <Control-Button-4> "[list ::moderne::biblio::pasSuite %W 120] ; break"
  bind $t <Control-Button-5> "[list ::moderne::biblio::pasSuite %W -120] ; break"
  # (Shift+wheel: the list's own sideways scrolling)
  foreach e {Shift-MouseWheel Shift-Button-4 Shift-Button-5} {
    bind $t <$e> {::moderne::biblio::finSurvolPartie ; continue}
  }
  # (menu: 1 = the right-click menu; or the command a click on a row runs,
  # called with {t x y} by "Open the game", as in Prepare's lists)
  variable ouvrirDe
  if {$menu ne "0"} {
    if {$menu ne "1"} { set ouvrirDe($t) $menu }
    bind $t <ButtonPress-3> [list ::moderne::biblio::menuPartie %W $varBase %x %y %X %Y]
  }
  bind $t <ButtonPress-1> +::moderne::biblio::finSurvolPartie
  # (a double click whose first click went through the line: the list's
  # own double click, Yosha 2026-11-07)
  bind $t <ButtonPress-1> {+if {[::moderne::biblio::deuxiemeClic %W %x %y]} break}
}

### The pointer left the list: the line goes, unless the pointer is on it
proc ::moderne::biblio::quitterListe {{t {}}} {
  variable clavier
  variable survolP
  # (the pointer went on to another list: its own line is left alone)
  if {$t ne {} && [llength $survolP] && [lindex $survolP 0] ne $t} { return }
  set X [winfo pointerx .] ; set Y [winfo pointery .]
  if {[info exists clavier] && $clavier eq [list $X $Y]} { return }
  if {[winfo exists .biblioSuite] && [dansZone $X $Y]} { return }
  finSurvolPartie
}
# (Siby no longer the active program, Alt+Tab: the line goes)
catch {bind . <Deactivate> {+catch ::moderne::biblio::finSurvolPartie}}

### The game of row: {database game}, empty if none
proc ::moderne::biblio::partieDeLigne {row varBase {t {}}} {
  if {[regexp {^b([0-9]+)_([0-9]+)} $row -> b g]} { return [list $b $g] }
  # (Prepare's Games tab: g<base>_<game>)
  if {[regexp {^g([0-9]+)_([0-9]+)$} $row -> b g]} { return [list $b $g] }
  # (the game list: the current database, the number in its first column)
  if {$varBase eq "courante"} {
    if {$row eq {} || $t eq {} || [catch {$t set $row Number} n]} { return {} }
    if {![regexp {([0-9]+)} $n -> g]} { return {} }
    return [list [sc_base current] $g]
  }
  if {[regexp {^g([0-9]+)$} $row -> g]} { return [list [set $varBase] $g] }
  # (the broadcast's library: a player's game, p<game>,<ply>)
  if {[regexp {^p([0-9]+),[0-9]+$} $row -> g]} { return [list [set $varBase] $g] }
  return {}
}

proc ::moderne::biblio::survolPartie {t varBase x y X Y} {
  variable survolP
  variable survolApres
  set row [$t identify row $x $y]
  # (on the column titles Tk still gives a row: no game there)
  if {[$t identify region $x $y] in {heading separator}} { set row {} }
  set p [partieDeLigne $row $varBase $t]
  if {$p eq {}} { finSurvolPartie ; return }
  if {$survolP eq [list $t $row]} { suivrePointeur $X ; return }
  # (the row just clicked through the line: no line on it again for now)
  variable survolBloque
  if {[info exists survolBloque] && $survolBloque eq [list $t $row]} { return }
  set survolBloque {}
  finSurvolPartie
  set survolP [list $t $row]
  # (a short wait: going over the rows quickly reads one game only)
  set survolApres [after 120 [list ::moderne::biblio::apercuPartie $t $row {*}$p $X $Y]]
}

proc ::moderne::biblio::apercuPartie {t row b gnum X Y} {
  variable survolP
  variable suite
  variable suiteI
  variable suiteDebut
  if {$survolP ne [list $t $row] || ![winfo exists $t] || !$b || ![sc_base inUse $b]} { return }
  # (the list refilled meanwhile, e.g. sorted: that row is gone, Yosha's
  # log 2026-11-09 "Item I018 not found")
  if {[catch {$t exists $row} oui] || !$oui} { return }
  set courante [sc_base current]
  if {$courante != $b} { sc_base switch $b }
  if {[catch {sc_game boards $gnum} positions]} { set positions {} }
  # (the game's own numbering: a game from a position starts at its move
  # number and side to move, "25..." rather than "1.", Yosha 2026-11-08)
  variable suiteBase 0
  catch {
    set fen [lindex [sc_game fens $gnum 1] 0 1]
    set n [lindex $fen 5] ; set trait [lindex $fen 1]
    if {[string is integer -strict $n] && $n >= 1} {
      set suiteBase [expr {($n - 1) * 2 + ($trait eq "b")}]
    }
  }
  if {$courante != $b} { sc_base switch $courante }
  set debut -1
  variable survolDepuis
  if {![info exists survolDepuis($t)] || $survolDepuis($t) ne "debut"} {
    set cible [cle [sc_pos board]]
    set i 0
    foreach p $positions {
      if {[cle [lindex $p 1]] eq $cible} { set debut $i ; break }
      incr i
    }
  }
  # (the game list: games without the board's position, from their start)
  if {$debut < 0} { set debut 0 }
  # up to 12 moves each (24 plies) after the board's position
  set suite [lrange $positions $debut [expr {$debut + 24}]]
  set suiteDebut $debut
  if {[llength $suite] < 2} { return }
  set suiteI 1
  variable suiteK 0
  variable suitePartie [list $b $gnum]
  bulle $t $row [expr {[llength $positions] - 1 > $debut + 24}]
  suivrePointeur $X
}

### The line: under the row, as wide as the list, one line of moves
proc ::moderne::biblio::bulle {t row plus} {
  variable suite
  variable suiteDebut
  variable suiteX
  set b .biblioSuite
  catch {destroy $b}
  toplevel $b -background [::moderne::c bordure]
  wm overrideredirect $b 1
  # (in front: as a mere child of Siby's window, Windows showed it behind;
  # it goes as soon as Siby is no longer the active program, so it does not
  # stay above the others after Alt+Tab, Yosha 2026-11-06)
  catch {wm attributes $b -topmost 1}
  text $b.t -wrap none -height 1 -borderwidth 0 -highlightthickness 0 \
      -background [::moderne::c surface2] -foreground [::moderne::c texte] -padx 10 -pady 0 \
      -font font_Regular -cursor {}
  pack $b.t -padx 1 -pady {0 1} -fill both -expand 1
  $b.t tag configure num -foreground [::moderne::c texteDoux]
  $b.t tag configure ici -background [::moderne::c accent] -foreground [::moderne::c fond]
  for {set k 1} {$k < [llength $suite]} {incr k} {
    variable suiteBase
    set ply [expr {$suiteBase + $suiteDebut + $k}]
    set san [::trans [lindex $suite $k 0]]
    if {$ply % 2} {
      $b.t insert end "[expr {($ply + 1) / 2}]." num
    } elseif {$k == 1} {
      $b.t insert end "[expr {$ply / 2}]…" num
    }
    $b.t insert end " $san " [list m$k]
  }
  if {$plus} { $b.t insert end "…" num }
  $b.t configure -state disabled
  # two lines, the list's whole width (Yosha 2026-11-07): on top the game's
  # own row again, cell by cell (the line no longer hides it), under it
  # the moves; the pointer anywhere on the row opens it
  if {[catch {$t bbox $row} bb]} { return }
  set f [ttk::style lookup Treeview -font]
  if {$f eq {}} { set f TkDefaultFont }
  set hr [expr {$bb ne {} ? [lindex $bb 3] : [font metrics $f -linespace] + 4}]
  # (the moves: one row high, as the list's rows)
  # (in the list's own font: a smaller font did not fit the row)
  $b.t configure -font $f -pady [expr {max(0, ($hr - [font metrics $f -linespace]) / 2)}]
  # (the game's row: a one-row list of the list's own columns, widths and
  # style, so that every cell is exactly where it is in the list)
  set cols [$t cget -columns]
  set show [lsearch -all -inline -not -exact [$t cget -show] headings]
  ttk::treeview $b.r -columns $cols -displaycolumns [$t cget -displaycolumns] \
      -show $show -height 1 -selectmode none -takefocus 0 -cursor {}
  catch {$b.r configure -style [$t cget -style]}
  foreach c [concat [list #0] $cols] {
    foreach o {-width -minwidth -anchor} { catch {$b.r column $c $o [$t column $c $o]} }
    catch {$b.r column $c -stretch 0}
  }
  $b.r tag configure ici -background [::moderne::c selection] -foreground [::moderne::c texteFort]
  set id [$b.r insert {} end -text [$t item $row -text] -values [$t item $row -values] -tags ici]
  # (cut to the row itself: the list's own margins left out)
  frame $b.rf -height $hr -background [::moderne::c selection]
  pack $b.rf -before $b.t -fill x -pady {1 0}
  place $b.r -in $b.rf -x 0 -y 0 -relwidth 1 -height $hr
  raise $b.r
  set l [winfo width $t]
  set x [winfo rootx $t]
  wm geometry $b ${l}x[expr {$hr + $hr + 2}]+$x+[winfo rooty $t]
  update idletasks
  ajusterRangee $b.r $id $hr 0
  set l [winfo width $t]
  set x [winfo rootx $t]
  update idletasks
  catch {$b.r xview moveto [lindex [$t xview] 0]}
  set h [expr {$hr + $hr + 2}]
  set y [winfo rooty $t]
  if {$bb ne {}} { set y [expr {$y + [lindex $bb 1] - 1}] }
  wm geometry $b ${l}x${h}+$x+$y
  # the line's zone: the row from the list's left edge (the first column
  # belongs to it: going back there does not close the line)
  variable zoneLigne [list [winfo rootx $t] $y [expr {[winfo rootx $t] + [winfo width $t]}] [expr {$y + $h}]]
  foreach x [list $b $b.t $b.r] {
    bind $x <Motion> {::moderne::biblio::suivrePointeur %X}
    bind $x <Leave> {after 30 ::moderne::biblio::quitterLigne}
    bind $x <MouseWheel> {::moderne::biblio::defilerListe {} %D ; break}
    bind $x <Button-4> {::moderne::biblio::defilerListe {} 120 ; break}
    bind $x <Button-5> {::moderne::biblio::defilerListe {} -120 ; break}
    bind $x <Control-MouseWheel> {::moderne::biblio::pasSuite {} %D ; break}
    bind $x <Control-Button-4> {::moderne::biblio::pasSuite {} 120 ; break}
    bind $x <Control-Button-5> {::moderne::biblio::pasSuite {} -120 ; break}
    bind $x <ButtonRelease-1> {::moderne::biblio::ouvrirDepuisLigne ; break}
  }
  # (the game's own row: a click or right-click is the list's, as if the
  # line were not there: select, open, the game's menu)
  bind $b.r <Double-Button-1> {break}
  foreach n {1 3} {
    bind $b.r <ButtonPress-$n> "[list ::moderne::biblio::versListe $t $row $n %X %Y] %t ; break"
  }
  # (held and moved: the games are dragged in the list, as without the
  # line; released without moving: a click, Yosha 2026-11-10)
  bind $b.r <B1-Motion> "[list ::moderne::biblio::glisserDepuisLigne $t] %X %Y ; break"
  bind $b.r <ButtonRelease-1> "[list ::moderne::biblio::lacherSurLigne $t $row] %X %Y %t ; break"
  # (the pointer read every 40 ms: on Windows the line got no motion
  # events, the moves could not be picked by going along them)
  after cancel ::moderne::biblio::veiller
  after 40 ::moderne::biblio::veiller
  update idletasks
  set suiteX {}
  mesurerLigne
}

### The row's place in the little list, once it is shown (on Windows the
### place read at first was 0, the right one a moment later: the row sat
### 5 pixels low): read again for half a second
### (placed over its frame, not inside it: its height ends with the row,
### else its bottom margin covered the top of the moves)
proc ::moderne::biblio::ajusterRangee {r id hr n} {
  if {![winfo exists $r]} { return }
  set p {}
  catch {set p [lindex [$r bbox $id] 1]}
  if {$p ne {} && $p != -[dict get [place info $r] -y]} {
    place configure $r -y [expr {-$p}] -height [expr {$p + $hr}]
  }
  if {$n < 15} { after 30 [list ::moderne::biblio::ajusterRangee $r $id $hr [incr n]] }
}

### A click on the game's row (on the line): the line goes, the click is
### given to the list, the line not shown again until another game
### (with the click's time: the next click on the list makes a double
### click with it, the game opens; without it, a third click was needed)
proc ::moderne::biblio::versListe {t row n X Y {temps 0}} {
  variable survolBloque
  variable passage
  set survolBloque [list $t $row]
  if {![winfo exists $t]} { finSurvolPartie ; return }
  set passage {}
  set x [expr {$X - [winfo rootx $t]}] ; set y [expr {$Y - [winfo rooty $t]}]
  # (left button: only the press now, the line kept while the button is
  # held; its release or its moves follow, see lacherSurLigne and
  # glisserDepuisLigne: an immediate release ended any drag at once)
  if {$n == 1} {
    variable appuiLigne [list $X $Y]
    event generate $t <ButtonPress-1> -x $x -y $y -rootx $X -rooty $Y -time $temps
    return
  }
  finSurvolPartie
  event generate $t <ButtonPress-$n> -x $x -y $y -rootx $X -rooty $Y -time $temps
  event generate $t <ButtonRelease-$n> -x $x -y $y -rootx $X -rooty $Y -time $temps
}

### The button held on the line's row and moved a few pixels: the line goes
### (the next moves and the release reach the list itself) and the drag
### goes on in the list
proc ::moderne::biblio::glisserDepuisLigne {t X Y} {
  variable appuiLigne
  if {![info exists appuiLigne] || $appuiLigne eq {}} { return }
  lassign $appuiLigne X0 Y0
  if {abs($X - $X0) + abs($Y - $Y0) < 4} { return }
  set appuiLigne {}
  finSurvolPartie
  if {[winfo exists $t]} { catch {::moderne::glisser::bouger $t $X $Y} }
}

### Released on the line's row without moving: the click's release, in the
### list (select, open)
proc ::moderne::biblio::lacherSurLigne {t row X Y {temps 0}} {
  variable appuiLigne
  variable passage
  set appuiLigne {}
  finSurvolPartie
  if {![winfo exists $t]} { return }
  set x [expr {$X - [winfo rootx $t]}] ; set y [expr {$Y - [winfo rooty $t]}]
  event generate $t <ButtonRelease-1> -x $x -y $y -rootx $X -rooty $Y -time $temps
  # (after it: this click itself is not the second one of a double click)
  set passage [list $t $row [clock milliseconds]]
}

### A click on the list just after a click through the line, on the same
### game: the second click of a double click (a double click on the line
### needed a third click: the first one closed the line). The list's own
### double click is run.
proc ::moderne::biblio::deuxiemeClic {t x y} {
  variable passage
  if {![info exists passage] || [llength $passage] != 3} { return 0 }
  lassign $passage tp row quand
  set passage {}
  if {$tp ne $t || [clock milliseconds] - $quand > 500} { return 0 }
  if {[$t identify row $x $y] ne $row} { return 0 }
  set map [list %W $t %x $x %y $y]
  set sc [bind $t <Double-Button-1>]
  if {$sc ne {}} {
    catch {uplevel #0 [string map $map $sc]}
    return 1
  }
  foreach tag [$t item $row -tags] {
    set sc [$t tag bind $tag <Double-Button-1>]
    if {$sc ne {}} {
      catch {uplevel #0 [string map $map $sc]}
      return 1
    }
  }
  return 0
}

### Each move's place on the screen, for the pointer (once the line is
### displayed: on Windows it is a moment after it is made, and the places
### measured before were empty, the moves could not be picked)
proc ::moderne::biblio::mesurerLigne {} {
  variable suite
  variable suiteX
  set b .biblioSuite
  if {![winfo exists $b.t] || ![winfo viewable $b.t]} { return }
  set l {}
  set x0 [winfo rootx $b.t]
  for {set k 1} {$k < [llength $suite]} {incr k} {
    lassign [$b.t tag ranges m$k] d f
    if {$d eq {}} { break }
    set bd [$b.t bbox $d]
    set bf [$b.t bbox "$f - 1 char"]
    if {$bd eq {} || $bf eq {}} { break }
    dict set l $k [list [expr {$x0 + [lindex $bd 0]}] [expr {$x0 + [lindex $bf 0] + [lindex $bf 2]}]]
  }
  set suiteX $l
}

### While the line is shown: the move under the pointer, the line closed
### when the pointer leaves it (to the list: the game there)
proc ::moderne::biblio::dansZone {X Y} {
  variable zoneLigne
  if {![info exists zoneLigne] || [llength $zoneLigne] != 4} { return 0 }
  lassign $zoneLigne x0 y0 x1 y1
  expr {$X >= $x0 && $X < $x1 && $Y >= $y0 && $Y < $y1}
}
proc ::moderne::biblio::veiller {} {
  set b .biblioSuite
  if {![winfo exists $b]} { return }
  # (Windows: Siby no longer the active program, Alt+Tab; the event that
  # says so did not always come: the keyboard focus is read too)
  if {$::windowsOS && [focus] eq {}} { finSurvolPartie ; return }
  set X [winfo pointerx .] ; set Y [winfo pointery .]
  # (shown from the keyboard: stays until the pointer moves)
  variable clavier
  if {[info exists clavier] && $clavier ne {}} {
    if {[list $X $Y] eq $clavier} { after 40 ::moderne::biblio::veiller ; return }
    set clavier {}
  }
  set dedans [dansZone $X $Y]
  variable suiteX
  if {![dict size $suiteX]} { mesurerLigne }
  if {$dedans} {
    suivrePointeur $X
  } else {
    quitterLigne
    if {![winfo exists $b]} { return }
  }
  after 40 ::moderne::biblio::veiller
}

### ↓ / ↑ in the game list: the line of the game chosen, as when the pointer
### is on it, and the board at its first position (the game's start, or the
### board's position when the game goes through it), Yosha 2026-11-10:
### games starting from another position showed the usual start
proc ::moderne::biblio::apercuClavier {t} {
  variable survolApres
  variable survolP
  variable clavier
  if {![winfo exists $t]} { return }
  set row [$t focus]
  if {$row eq {} || [catch {$t exists $row} oui] || !$oui} { return }
  set p [partieDeLigne $row courante $t]
  if {$p eq {}} { return }
  finSurvolPartie
  set survolP [list $t $row]
  catch {$t see $row}
  # (a short wait: the key held down goes through the rows quickly)
  set survolApres [after 120 [list ::moderne::biblio::apercuClavierSuite $t $row {*}$p]]
}
proc ::moderne::biblio::apercuClavierSuite {t row b gnum} {
  variable survolP
  variable clavier
  variable suiteI
  variable suiteK
  if {$survolP ne [list $t $row] || ![winfo exists $t]} { return }
  set clavier [list [winfo pointerx .] [winfo pointery .]]
  apercuPartie $t $row $b $gnum [winfo rootx $t] [winfo rooty $t]
  if {![winfo exists .biblioSuite]} { set clavier {} ; return }
  # (the first position: before the first move of the line)
  set suiteK 0 ; set suiteI 0
  montrerSuite
}

### The pointer left the line: back on the list (another game), or away
proc ::moderne::biblio::quitterLigne {} {
  variable survolP
  variable clavier
  set X [winfo pointerx .] ; set Y [winfo pointery .]
  if {[info exists clavier] && $clavier eq [list $X $Y]} { return }
  if {[winfo exists .biblioSuite] && [dansZone $X $Y]} { return }
  set w [winfo containing $X $Y]
  set t [lindex $survolP 0]
  finSurvolPartie
  # (on the list: the game under the pointer now)
  if {$t ne {} && [winfo exists $t] && $w eq $t} {
    event generate $t <Motion> -x [expr {[winfo pointerx .] - [winfo rootx $t]}] \
        -y [expr {[winfo pointery .] - [winfo rooty $t]}] -warp 0
  }
}

### A click on the line: the game opened at the move shown
proc ::moderne::biblio::ouvrirDepuisLigne {} {
  variable suitePartie
  variable suiteDebut
  variable suiteI
  if {![info exists suitePartie] || $suitePartie eq {}} { return }
  lassign $suitePartie b gnum
  set ply [expr {$suiteDebut + $suiteI}]
  finSurvolPartie
  ouvrirPartie $b $gnum $ply
}

### The move under the pointer's left-right place (the last one shown past
### the end, the first one before the start)
proc ::moderne::biblio::suivrePointeur {X} {
  variable suite
  variable suiteI
  variable suiteX
  if {![llength $suite] || ![winfo exists .biblioSuite] || ![dict size $suiteX]} { return }
  set k 1
  dict for {i bornes} $suiteX {
    if {$X >= [lindex $bornes 0]} { set k $i }
  }
  # (only when the pointer goes to another move: the wheel's steps stay)
  variable suiteK
  if {$k != $suiteK} { set suiteK $k ; set suiteI $k ; montrerSuite }
}

### The position on the board, the move highlighted on the line
proc ::moderne::biblio::montrerSuite {} {
  variable suite
  variable suiteI
  if {![llength $suite]} { return }
  variable plateauVu [lindex $suite $suiteI 1]
  catch {::moderne::moteur::apercuPlateau $plateauVu}
  set t .biblioSuite.t
  if {![winfo exists $t]} { return }
  $t tag remove ici 1.0 end
  if {$suiteI > 0} {
    lassign [$t tag ranges m$suiteI] d f
    # (sideways only: "see" also scrolled the one line up and down, the
    # moves were cut on Windows)
    if {$d ne {}} { $t tag add ici $d $f ; $t see $f ; $t yview moveto 0 }
  }
}

### The position the preview shows (tests)
proc ::moderne::biblio::plateauVu {} {
  variable plateauVu
  return [expr {[info exists plateauVu] ? $plateauVu : {}}]
}

### Wheel over the list (or its line): the list scrolls, the line goes and
### comes back on the game now under the pointer
proc ::moderne::biblio::defilerListe {t d} {
  variable survolP
  if {$t eq {}} { set t [lindex $survolP 0] }
  if {$t eq {} || ![winfo exists $t]} { return }
  finSurvolPartie
  if {[string match .glistWin*.tree $t] || [string match .fdockglistWin*.tree $t]} {
    ::windows::gamelist::Scroll [expr {$d > 0 ? -1 : 1}]
  } else {
    $t yview scroll [expr {$d > 0 ? -1 : 1}] units
  }
  after idle [list apply {{t} {
    if {![winfo exists $t]} { return }
    set X [winfo pointerx .] ; set Y [winfo pointery .]
    if {[winfo containing $X $Y] ne $t} { return }
    event generate $t <Motion> -x [expr {$X - [winfo rootx $t]}] -y [expr {$Y - [winfo rooty $t]}] -rootx $X -rooty $Y
  }} $t]
}

### Ctrl+wheel over the list or its line: one move back or on
proc ::moderne::biblio::pasSuite {t d} {
  variable suite
  variable suiteI
  if {![llength $suite] || ![winfo exists .biblioSuite]} {
    if {$t ne {} && [winfo exists $t]} { $t yview scroll [expr {$d > 0 ? -1 : 1}] units }
    return
  }
  set suiteI [expr {max(1, min([llength $suite] - 1, $suiteI + ($d > 0 ? -1 : 1)))}]
  montrerSuite
}

proc ::moderne::biblio::finSurvolPartie {} {
  variable survolP
  variable survolApres
  variable suite
  variable suiteX
  catch {after cancel $survolApres}
  set survolP {}
  variable clavier {}
  catch {destroy .biblioSuite}
  if {[llength $suite]} { catch {::moderne::moteur::finApercu} }
  set suite {}
  set suiteX {}
}

### Right-click on a game of the list
proc ::moderne::biblio::menuPartie {t varBase x y X Y} {
  finSurvolPartie
  variable ouvrirDe
  set row [$t identify row $x $y]
  # (rows "g<game>" of the list's database, or with the database in them:
  # "g<base>_<game>", "b<base>_<game>,<ply>" in Prepare's lists)
  if {[regexp {^g([0-9]+)$} $row -> gnum]} {
    set b [set $varBase]
  } elseif {![regexp {^[gb]([0-9]+)_([0-9]+)(,[0-9]+)?$} $row -> b gnum]} {
    return
  }
  $t selection set $row
  $t focus $row
  if {[info exists ouvrirDe($t)]} {
    set ouvrir [concat $ouvrirDe($t) [list $t $x $y]]
  } else {
    set ouvrir [list ::moderne::biblio::ouvrirPartie $b $gnum]
  }
  set m .biblioMenuPartie
  catch {destroy $m}
  menu $m -tearoff 0
  $m add command -label [T "Ouvrir la partie" "Open the game"] -command $ouvrir
  $m add command -label [T "Fusionner dans la partie en cours" "Merge into the current game"] \
      -command [list ::moderne::menuclic::fusionner game $b $gnum] \
      -state [expr {($b == [sc_base current] && $gnum == [sc_game number]) ? "disabled" : "normal"}]
  $m add command -label [T "Bilan de la partie" "Game review"] \
      -command "$ouvrir ; after idle ::moderne::bilan::lancer"
  $m add command -label [T "Voir le tableau du tournoi" "Show crosstable"] -command [list ::moderne::croise::ouvrir $b $gnum]
  $m add separator
  $m add command -label [T "Copier la partie (PGN)" "Copy the game (PGN)"] -command [list ::moderne::biblio::copierPartie $b $gnum]
  menu $m.vers -tearoff 0
  set k 0
  for {set i 1} {$i <= [sc_base count total]} {incr i} {
    if {$i == $b || ![sc_base inUse $i]} { continue }
    set nom [file rootname [::moderne::nomBase [sc_base filename $i]]]
    if {$i == [sc_info clipbase]} { set nom [T "Presse-papier" "Clipbase"] }
    $m.vers add command -label $nom -command [list ::moderne::glisser::copier $b [list $gnum] $i]
    incr k
  }
  $m add cascade -label [T "Copier dans la base" "Copy into the database"] -menu $m.vers -state [expr {$k ? "normal" : "disabled"}]
  tk_popup $m $X $Y
}

proc ::moderne::biblio::copierPartie {b gnum} {
  set courante [sc_base current]
  if {$courante != $b} { sc_base switch $b }
  catch {::moderne::menuclic::copierPgn [list $gnum]}
  if {$courante != $b} { sc_base switch $courante }
}

################################################################################
### Lichess-style view: one row per move with a White / Draws /
### Black bar, the number of games; on hover: average rating, perf, latest
### game. A click plays the move. The "Move", "Games" and
### "White / Draws / Black" headers sort.
################################################################################

namespace eval ::moderne::biblio {
  variable vue          ;# vue(cv,lignes): displayed rows; vue(cv,tri): {col dec}
  array set vue {}
}

proc ::moderne::biblio::creerVue {cv} {
  canvas $cv -highlightthickness 0 -borderwidth 0 -background [::moderne::c surface] -yscrollincrement 1
  bind $cv <Configure> [list ::moderne::biblio::dessinerVue $cv]
  bind $cv <Motion> [list ::moderne::biblio::survolVue $cv %x %y]
  bind $cv <Leave> [list ::moderne::biblio::survolVue $cv -1 -1]
  bind $cv <ButtonRelease-1> [list ::moderne::biblio::clicVue $cv %x %y]
  bind $cv <MouseWheel> [list ::moderne::biblio::rouletteVue $cv %D]
  bind $cv <Button-4> [list ::moderne::biblio::rouletteVue $cv 120]
  bind $cv <Button-5> [list ::moderne::biblio::rouletteVue $cv -120]
  bind $cv <Left> {::move::Back ; break}
  bind $cv <Right> {::move::Forward ; break}
  return $cv
}

proc ::moderne::biblio::rouletteVue {cv d} {
  $cv yview scroll [expr {$d > 0 ? -40 : 40}] units
}

### Integer percentages {white draws black} that add up to 100
proc ::moderne::biblio::bnn {score nulles} {
  set score [string map {% {} " " {}} $score]
  set nulles [string map {% {} " " {}} $nulles]
  if {![string is double -strict $score]} { return {} }
  if {![string is double -strict $nulles]} { set nulles 0 }
  set b [expr {max(0.0, $score - $nulles / 2.0)}]
  set n [expr {max(0.0, 100.0 - $b - $nulles)}]
  set rb [expr {round($b)}]
  set rd [expr {round($nulles)}]
  return [list $rb $rd [expr {max(0, 100 - $rb - $rd)}]]
}

### View rows from a statsIci result: {san disp n share w d b elo perf latest}
proc ::moderne::biblio::lignesVue {ref} {
  lassign $ref total lignes
  set res {}
  foreach l $lignes {
    lassign $l san aff n pct score nulles elo perf derniere
    set r [bnn $score $nulles]
    if {$r eq {}} { continue }
    lappend res [concat [list $san $aff $n [expr {round($pct)}]] $r [list $elo $perf $derniere]]
  }
  return $res
}

proc ::moderne::biblio::remplirVue {cv ref} {
  variable vue
  set vue($cv,lignes) [lignesVue $ref]
  set vue($cv,suivant) [sc_game info nextMoveNT]
  set vue($cv,survol) -1
  set vue($cv,fen) [sc_pos fen]
  $cv yview moveto 0
  dessinerVue $cv
  cloudDemander $cv
}

################################################################################
### Lichess cloud evaluation (https://lichess.org/api#tag/Analysis): the
### evaluation of the position's best moves (up to 5) as Lichess's cloud
### knows it, shown in a "Cloud" column, its depth on the Σ row. Nothing
### when the position is not in the cloud or without internet.
################################################################################

namespace eval ::moderne::biblio {
  variable cloud      ;# cloud(fen) = {depth {san eval …}} ("" = not in the cloud)
  array set cloud {}
}

### The 4 first FEN fields (the cloud ignores the move counters)
proc ::moderne::biblio::cloudCle {fen} { join [lrange [split $fen] 0 3] }

proc ::moderne::biblio::cloudDemander {cv} {
  variable vue
  variable cloud
  set k [cloudCle $vue($cv,fen)]
  if {[info exists cloud($k)]} { return }
  # (a short wait: going through moves quickly sends one request only, for
  # the position where one stops; 150 ms, Yosha 2026-11-05)
  after cancel [list ::moderne::biblio::cloudEnvoyer $cv $k]
  after 150 [list ::moderne::biblio::cloudEnvoyer $cv $k]
}

proc ::moderne::biblio::cloudEnvoyer {cv k} {
  variable vue
  variable cloud
  if {![winfo exists $cv] || [cloudCle $vue($cv,fen)] ne $k || [info exists cloud($k)]} { return }
  set cloud($k) attente
  set fen $vue($cv,fen)
  set url "https://lichess.org/api/cloud-eval?multiPv=5&fen=[string map {{ } %20 / %2F} $fen]"
  # (the position on screen: before the review's requests; replaced if the
  # board moves on before it is sent)
  ::moderne::direct::lireJson $url [list ::moderne::biblio::cloudRecu $cv $k $fen] \
      biblio [list unset -nocomplain ::moderne::biblio::cloud($k)]
}

proc ::moderne::biblio::cloudRecu {cv k fen v} {
  variable vue
  variable cloud
  set evals {}
  set prof [::moderne::json::get $v depth {}]
  foreach pv [::moderne::json::get $v pvs {}] {
    set uci [lindex [::moderne::json::get $pv moves {}] 0]
    if {$uci eq {}} { continue }
    # (Lichess writes castling king-takes-rook: e1h1 = e1g1)
    set san {}
    foreach u [list $uci [string map {e1h1 e1g1 e1a1 e1c1 e8h8 e8g8 e8a8 e8c8} $uci]] {
      sc_game push
      catch {
        sc_game startBoard $fen
        set san [string trim [sc_move addUCI $u]]
      }
      sc_game pop
      if {$san ne {}} { break }
    }
    set san [string map {+ {} # {}} [lindex $san end]]
    if {$san eq {}} { continue }
    set mat [::moderne::json::get $pv mate {}]
    set cp [::moderne::json::get $pv cp {}]
    if {$mat ne {}} {
      set e "#$mat"
    } elseif {[string is integer -strict $cp]} {
      set e [format %+.1f [expr {$cp / 100.0}]]
    } else {
      continue
    }
    if {![dict exists $evals $san]} { dict set evals $san $e }
  }
  # (an error, not "unknown to the cloud": asked again, after Lichess's
  # pause for a "too many requests", while the position stays on screen;
  # before, the column stayed empty until the next move)
  if {$prof eq {} && $::moderne::direct::erreur ni {200 404}} {
    unset -nocomplain cloud($k)
    variable cloudEssais
    if {![info exists cloudEssais($k)]} { set cloudEssais($k) 0 }
    if {[incr cloudEssais($k)] <= 6} {
      set attente [expr {max(3000, max($::moderne::direct::lichessPause, $::moderne::direct::lichessPauseCloud) - [clock milliseconds] + 500)}]
      after $attente [list ::moderne::biblio::cloudReessayer $cv $k]
    }
    return
  }
  unset -nocomplain cloudEssais($k)
  set cloud($k) [expr {$prof eq {} ? {} : [list $prof $evals]}]
  # every view on that position (the library's table and its list view, the
  # preparation's...: only the first one asked)
  foreach x [array names vue *,fen] {
    set v [string range $x 0 end-4]
    if {![winfo exists $v] || [cloudCle $vue($x)] ne $k} { continue }
    if {[winfo class $v] eq "Treeview"} {
      cloudTable $v
    } elseif {[info exists ::moderne::tableau::tab($v,cols)] && [info exists vue($v,args)]} {
      # (preparation table: filled again, scroll and sort kept)
      remplirPrepa $v {*}$vue($v,args) 1
    } else {
      dessinerVue $v
    }
  }
}

proc ::moderne::biblio::cloudReessayer {cv k} {
  variable vue
  if {![winfo exists $cv] || ![info exists vue($cv,fen)] || [cloudCle $vue($cv,fen)] ne $k} { return }
  cloudDemander $cv
}

### Cloud evaluation of move san in the view's position ({} if unknown)
proc ::moderne::biblio::cloudCoup {cv san} {
  variable vue
  variable cloud
  if {![info exists vue($cv,fen)]} { return {} }
  set k [cloudCle $vue($cv,fen)]
  if {![info exists cloud($k)] || [llength $cloud($k)] != 2} { return {} }
  set san [string map {+ {} # {}} $san]
  set e [lindex $cloud($k) 1]
  # (not expr: "+0.2" would become 0.2)
  if {[dict exists $e $san]} { return [dict get $e $san] }
  return {}
}

### Library table: the Cloud column of each move, the depth in its header
proc ::moderne::biblio::cloudTable {t} {
  variable san
  if {![winfo exists $t]} { return }
  foreach id [$t children {}] {
    if {[info exists san($t,$id)]} { catch {$t set $id cloud [cloudCoup $t $san($t,$id)]} }
  }
  set prof [cloudProfondeur $t]
  catch {$t heading cloud -text [expr {$prof eq {} ? "Cloud" : "Cloud $prof"}]}
}

proc ::moderne::biblio::cloudProfondeur {cv} {
  variable vue
  variable cloud
  if {![info exists vue($cv,fen)]} { return {} }
  set k [cloudCle $vue($cv,fen)]
  if {![info exists cloud($k)] || [llength $cloud($k)] != 2} { return {} }
  return [lindex $cloud($k) 0]
}

proc ::moderne::biblio::trierVue {cv col} {
  variable vue
  if {[info exists vue($cv,tri)] && [lindex $vue($cv,tri) 0] eq $col} {
    set vue($cv,tri) [list $col [expr {![lindex $vue($cv,tri) 1]}]]
  } else {
    set vue($cv,tri) [list $col [expr {$col ne "coup"}]]
  }
  dessinerVue $cv
}

proc ::moderne::biblio::dessinerVue {cv} {
  variable vue
  if {![winfo exists $cv]} { return }
  $cv delete all
  set lignes [expr {[info exists vue($cv,lignes)] ? $vue($cv,lignes) : {}}]
  # Chosen sort (default: number of games, like Lichess)
  if {[info exists vue($cv,tri)]} {
    lassign $vue($cv,tri) col dec
    switch $col {
      coup    { set opts [list -dictionary -index 1] }
      parties { set opts [list -integer -index 2] }
      score   { set opts [list -real -index 4] }
    }
    if {$dec} { lappend opts -decreasing }
    set lignes [lsort {*}$opts $lignes]
  }
  set vue($cv,ordre) $lignes
  set larg [winfo width $cv]
  if {$larg < 50} { set larg 600 }
  set fh [font metrics font_Regular -linespace]
  set hl [expr {$fh + 12}]   ;# height of a row
  set vue($cv,hl) $hl
  set xC 12
  set xP [expr {$xC + 8 * [font measure font_Regular 0] + 20}]
  set xB [expr {$xP + 12 * [font measure font_Regular 0] + 10}]
  # Lichess cloud evaluation column, before the bar
  # (wide enough for the header "Cloud 60": the depth is shown there)
  set lCloud [expr {max([font measure font_Regular "-10.0"], [font measure font_Small "Cloud 99"])}]
  set xE [expr {$xB + $lCloud + 6}]
  set xB [expr {$xE + 14}]
  # (the bar is not stretched over a wide panel: 420 px at most)
  # Overperformance column after the bar (its title runs over the bar's)
  set lS [expr {[font measure font_Bold "+999"] + 12}]
  set xF [expr {min($larg - 12 - $lS, $xB + 420)}]
  set xS [expr {$xF + $lS}]
  set vue($cv,xB) $xB
  set texte [::moderne::c texte]
  set doux [::moderne::c texteDoux]
  set sombre [expr {$::moderne::theme eq "sombre"}]

  # Clickable headers
  set y 4
  array set fleche {}
  if {[info exists vue($cv,tri)]} {
    set fleche([lindex $vue($cv,tri) 0]) [expr {[lindex $vue($cv,tri) 1] ? " ▼" : " ▲"}]
  }
  set prof [cloudProfondeur $cv]
  $cv create text $xE [expr {$y + $hl / 2}] -anchor e -text [expr {$prof eq {} ? "Cloud" : "Cloud $prof"}] \
      -fill $doux -font font_Small -tags entete
  # ("Games" over the counts, "%" over the shares)
  set xPc [expr {$xE - $lCloud - 16}]
  $cv create text $xPc [expr {$y + $hl / 2}] -anchor e -text % -fill $doux -font font_Small -tags entete
  foreach {col x ancre fr en} [list coup $xC w Coup Move parties [expr {$xPc - [font measure font_Small " 100%"]}] e Parties Games \
                                    score $xB w "Blancs / Nulles / Noirs" "White / Draw / Black"] {
    set t "[T $fr $en][expr {[info exists fleche($col)] ? $fleche($col) : {}}]"
    $cv create text $x [expr {$y + $hl / 2}] -anchor $ancre -text $t -fill $doux -font font_Small -tags [list entete e_$col]
    $cv bind e_$col <ButtonRelease-1> "[list ::moderne::biblio::trierVue $cv $col] ; break"
    $cv bind e_$col <Enter> [list $cv configure -cursor hand2]
    $cv bind e_$col <Leave> [list $cv configure -cursor {}]
  }
  $cv create text $xS [expr {$y + $hl / 2}] -anchor e -text [T Surperf Overperf] -fill $doux -font font_Small -tags entete
  set y [expr {$y + $hl}]
  # (the table ends where the last column ends: no empty stripes on the right)
  set larg [expr {min($larg, $xS + 12)}]
  $cv create line 0 $y $larg $y -fill [::moderne::c bordure]
  set vue($cv,y0) $y

  if {![llength $lignes]} {
    $cv create text [expr {$larg / 2}] [expr {$y + 30}] -text [T "Aucune partie dans cette position" "No game in this position"] \
        -fill $doux -font font_Regular
    $cv configure -scrollregion [list 0 0 $larg [expr {$y + 60}]]
    return
  }

  set i 0
  set tot 0 ; set sB 0.0 ; set sD 0.0 ; set sE 0.0 ; set nE 0
  foreach l $lignes {
    lassign $l san aff n part b d nr elo perf der
    set y1 [expr {$y + $i * $hl}]
    set y2 [expr {$y1 + $hl}]
    set fond [expr {$i % 2 ? [::moderne::c ligneAlt] : [::moderne::c surface]}]
    $cv create rectangle 0 $y1 $larg $y2 -fill $fond -outline {} -tags [list fond f$i]
    if {$san eq $vue($cv,suivant)} {
      $cv create rectangle 0 $y1 3 $y2 -fill [::moderne::c accent] -outline {}
    }
    set ym [expr {($y1 + $y2) / 2}]
    $cv create text $xC $ym -anchor w -text $aff -fill $texte -font font_Bold
    set xPc [expr {$xE - $lCloud - 16}]
    $cv create text [expr {$xPc - [font measure font_Small " 100%"]}] $ym -anchor e \
        -text [::utils::thousands $n] -fill $texte -font font_Regular
    $cv create text $xPc $ym -anchor e -text [expr {$part < 1 ? "<1%" : "$part%"}] -fill $doux -font font_Small
    set ev [cloudCoup $cv $san]
    if {$ev ne {}} { $cv create text $xE $ym -anchor e -text $ev -fill $texte -font font_Regular }
    barreBNN $cv $xB [expr {$y1 + 4}] $xF [expr {$y2 - 4}] $b $d $nr $sombre
    set gr [surperfVue $cv $l]
    if {$gr ne {}} {
      set cs [couleurSurperf $gr]
      $cv create text $xS $ym -anchor e -text [texteSurperf $gr] -fill [expr {$cs eq {} ? $texte : $cs}] -font font_Bold
    }
    incr tot $n
    set sB [expr {$sB + $b * $n}]
    set sD [expr {$sD + $d * $n}]
    if {[string is integer -strict $elo] && $elo > 0} { set sE [expr {$sE + $elo * $n}] ; incr nE $n }
    incr i
  }
  # Σ row (all games of the position): kept at the bottom of the panel
  # when the moves run below it, as on Lichess (Yosha 2026-11-12)
  set y1 [expr {$y + $i * $hl}]
  set y2 [expr {$y1 + $hl}]
  set avant [$cv find all]
  $cv create rectangle 0 $y1 $larg [expr {$y2 + 6}] -fill [::moderne::c surface] -outline {} -tags fondSomme
  $cv create line 0 $y1 $larg $y1 -fill [::moderne::c bordure]
  set ym [expr {($y1 + $y2) / 2}]
  $cv create text $xC $ym -anchor w -text "Σ" -fill $doux -font font_Bold
  set xPc [expr {$xE - $lCloud - 16}]
  $cv create text [expr {$xPc - [font measure font_Small " 100%"]}] $ym -anchor e \
      -text [::utils::thousands $tot] -fill $texte -font font_Bold
  if {$tot > 0} {
    set b [expr {round($sB / $tot)}]
    set d [expr {round($sD / $tot)}]
    barreBNN $cv $xB [expr {$y1 + 4}] $xF [expr {$y2 - 4}] $b $d [expr {max(0, 100 - $b - $d)}] $sombre
  }
  foreach id [$cv find all] { if {$id ni $avant} { $cv addtag somme withtag $id } }
  set vue($cv,ySomme) $y1
  set vue($cv,total) [list $tot [expr {$nE ? round($sE / $nE) : {}}]]
  $cv configure -scrollregion [list 0 0 $larg [expr {$y2 + 6}]]
  set vue($cv,survol) -1
  placerSomme $cv
}

### The Σ row at the bottom of what shows of the panel, never below its
### own place after the last move
proc ::moderne::biblio::placerSomme {cv} {
  variable vue
  if {![winfo exists $cv] || ![info exists vue($cv,ySomme)]} { return }
  set c [$cv coords fondSomme]
  if {![llength $c]} { return }
  set hl $vue($cv,hl)
  set bas [$cv canvasy [winfo height $cv]]
  set voulu [expr {min($vue($cv,ySomme), $bas - $hl - 6)}]
  set voulu [expr {max($voulu, $vue($cv,y0))}]
  set dy [expr {$voulu - [lindex $c 1]}]
  if {abs($dy) >= 0.5} { $cv move somme 0 $dy }
  $cv raise somme
}

### The panel scrolled: the scrollbar, then the Σ row
proc ::moderne::biblio::defilementVue {cv sb args} {
  catch {$sb set {*}$args}
  placerSomme $cv
}

### White / Draws / Black bar with readable percentages inside
proc ::moderne::biblio::barreBNN {cv x1 y1 x2 y2 b d n sombre} {
  set L [expr {$x2 - $x1}]
  set cB [expr {$sombre ? "#e8e8e8" : "#ffffff"}]
  set cD [expr {$sombre ? "#7f7f7f" : "#a0a0a0"}]
  set cN [expr {$sombre ? "#0d0d0d" : "#4a4a4a"}]
  set tB #333333 ; set tD #ffffff ; set tN #e8e8e8
  set x $x1
  foreach p [list $b $d $n] c [list $cB $cD $cN] tc [list $tB $tD $tN] {
    set w [expr {$L * $p / 100.0}]
    if {$w <= 0} { continue }
    $cv create rectangle $x $y1 [expr {$x + $w}] $y2 -fill $c -outline {}
    set lib "$p%"
    if {$w > [font measure font_Small $lib] + 6} {
      $cv create text [expr {$x + $w / 2}] [expr {($y1 + $y2) / 2}] -text $lib -fill $tc -font font_Small
    }
    set x [expr {$x + $w}]
  }
  $cv create rectangle $x1 $y1 $x2 $y2 -outline [::moderne::c bordure]
}

proc ::moderne::biblio::ligneSous {cv y} {
  variable vue
  if {![info exists vue($cv,y0)] || $y < 0} { return -1 }
  set y [$cv canvasy $y]
  # (the Σ row laid over the last moves: not a move)
  set c [$cv coords fondSomme]
  if {[llength $c] && $y >= [lindex $c 1]} { return -1 }
  set i [expr {int(($y - $vue($cv,y0)) / $vue($cv,hl))}]
  if {$y < $vue($cv,y0) || $i >= [llength $vue($cv,ordre)]} { return -1 }
  return $i
}

proc ::moderne::biblio::survolVue {cv x y} {
  variable vue
  set i [ligneSous $cv $y]
  if {![info exists vue($cv,survol)]} { set vue($cv,survol) -1 }
  if {$i != $vue($cv,survol)} {
    set a $vue($cv,survol)
    if {$a >= 0} {
      $cv itemconfigure f$a -fill [expr {$a % 2 ? [::moderne::c ligneAlt] : [::moderne::c surface]}]
    }
    if {$i >= 0} { $cv itemconfigure f$i -fill [::moderne::c survol] }
    set vue($cv,survol) $i
    $cv configure -cursor [expr {$i >= 0 ? "hand2" : {}}]
  }
  $cv delete bulle
  if {$i < 0} { flecheSurvol {} ; return }
  # Tooltip: average rating, perf, latest game
  lassign [lindex $vue($cv,ordre) $i] san aff n part b d nr elo perf der
  flecheSurvol $san
  set lignes {}
  if {[string is integer -strict $elo] && $elo > 0} { lappend lignes "[T "Elo moyen" "Average Elo"] : $elo" }
  if {[string is integer -strict $perf] && $perf > 0} { lappend lignes "[T "Performance" "Performance"] : $perf" }
  set gr [surperfVue $cv [lindex $vue($cv,ordre) $i]]
  if {$gr ne {}} { lappend lignes "[T "Surperf" "Overperf"] : [texteSurperf $gr] Elo ± [lindex $gr 1][noteSurperf $elo]" }
  if {[string trim $der] ne {}} { lappend lignes "[T "Dernière partie" "Last played"] : $der" }
  lappend lignes "[::utils::thousands $n] [T parties games] • [T Blancs White] $b% • [T nulles draws] $d% • [T Noirs Black] $nr%"
  set texte [join $lignes \n]
  set cx [$cv canvasx $x]
  set cy [$cv canvasy $y]
  set t [$cv create text 0 0 -anchor nw -text $texte -font font_Small -fill [::moderne::c texteFort] -tags bulle]
  lassign [$cv bbox $t] bx1 by1 bx2 by2
  set lw [expr {$bx2 - $bx1 + 16}]
  set lh [expr {$by2 - $by1 + 10}]
  set px [expr {$cx + 14}]
  if {$px + $lw > [$cv canvasx [winfo width $cv]]} { set px [expr {$cx - $lw - 8}] }
  set py [expr {$cy + 16}]
  if {$py + $lh > [$cv canvasy [winfo height $cv]]} { set py [expr {$cy - $lh - 6}] }
  $cv coords $t [expr {$px + 8}] [expr {$py + 5}]
  set r [$cv create rectangle $px $py [expr {$px + $lw}] [expr {$py + $lh}] \
      -fill [::moderne::c surface2] -outline [::moderne::c bordure] -tags bulle]
  $cv raise $t $r
}

### Transparent arrow on the board for the hovered move (like Lichess);
### empty san: removes it
proc ::moderne::biblio::flecheSurvol {san} {
  variable flecheCourante
  set bd .main.board.bd
  if {![winfo exists $bd]} { return }
  if {[info exists flecheCourante] && $flecheCourante eq $san} { return }
  set flecheCourante $san
  $bd delete flecheSurvol
  if {$san eq {}} { return }
  set uci {}
  if {[catch {
    sc_game push copyfast
    sc_move addSan $san
    set uci [sc_game info previousMoveUCI]
  }]} { set uci {} }
  catch {sc_game pop}
  if {[string length $uci] < 4} { return }
  set de [expr {([scan [string index $uci 0] %c] - 97) + 8 * ([string index $uci 1] - 1)}]
  set a  [expr {([scan [string index $uci 2] %c] - 97) + 8 * ([string index $uci 3] - 1)}]
  catch {::moderne::fleche::dessiner $bd $de $a #1b5fb4 0 0.45 flecheSurvol}
}

proc ::moderne::biblio::clicVue {cv x y} {
  variable vue
  set i [ligneSous $cv $y]
  if {$i < 0} { return }
  set san [lindex $vue($cv,ordre) $i 0]
  # (the moves of an earlier position, not redrawn yet: two quick clicks
  # played a move of the previous position, "Error reading move(s): g5",
  # Yosha 2026-11-12)
  if {[info exists vue($cv,fen)] && $vue($cv,fen) ne [sc_pos fen]} { return }
  if {[catch {addSanMove $san -animate}]} { return }
  updateBoard -pgn
  focus $cv
}

### Switches from the Lichess view to the detailed table
proc ::moderne::biblio::changerVue {} {
  variable w
  if {![winfo exists $w]} { return }
  pack forget $w.pw.h.sb $w.pw.h.t $w.pw.h.cv
  if {$::moderne::biblio::vueLichess} {
    $w.pw.h.sb configure -command [list $w.pw.h.cv yview]
    $w.pw.h.cv configure -yscrollcommand [list ::moderne::biblio::defilementVue $w.pw.h.cv $w.pw.h.sb]
    pack $w.pw.h.sb -side right -fill y
    pack $w.pw.h.cv -side left -fill both -expand 1
  } else {
    $w.pw.h.sb configure -command [list $w.pw.h.t yview]
    $w.pw.h.cv configure -yscrollcommand {}
    pack $w.pw.h.sb -side right -fill y
    pack $w.pw.h.t -side left -fill both -expand 1
  }
}

### End Siby
