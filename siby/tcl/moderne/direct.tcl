###
### Siby: live broadcasts, powered by Lichess
###
### Siby broadcasts nothing itself: it reads the public Lichess broadcast
### API (https://lichess.org/api#tag/Broadcasts) and shows the games live.
###   - tournaments: ongoing / upcoming / finished, like the Lichess page,
###     search, sections of a group (Open, Women...), rounds;
###   - games of a round, or matches for team events;
###   - the round is followed through the Lichess stream: every move is
###     received as soon as it is played;
###   - two views, like Lichess: the broadcast view (tournaments, rounds,
###     games, no board) and the game view (board, engines, notation, live
###     panel with the clocks and the other games of the round);
###   - a followed game goes into the "Siby live" database; new moves are
###     added at the end of its main line, the user's own analysis
###     (variations, position) is kept, "Back to live" returns to the last
###     move (like Lichess).
### Downloads go through curl, like the online games.
###

namespace eval ::moderne::direct {
  variable baseSurvol 0     ;# database of the players' library lists (hover preview)
  variable w .directWin
  variable onglet active     ;# active | upcoming | past | search
  variable recherche {}
  variable tours {}          ;# tours shown in the list (dicts)
  variable tour {}           ;# current tour (API answer)
  variable ronde {}          ;# current round id
  variable rondeEnCours 0
  variable parties           ;# parties(id): dict of the game
  array set parties {}
  variable ordre {}          ;# game ids in board order
  variable flux {}           ;# curl pipe of the stream
  variable tampon {}
  variable suivie {}         ;# game id followed on the main board
  variable numLive           ;# numLive(id): game number in "Siby live"
  array set numLive {}
  variable page 1
  variable api https://lichess.org
  variable panneau .liveWin  ;# live panel of the game view
  variable coupsLive {}      ;# main line (SAN) of the followed game
  variable nouveaux 0        ;# moves received while the user analyses
  variable recu              ;# recu(id): time of the last update (s)
  array set recu {}
  variable silence 0
  variable entrees {}        ;# entries of the list as received (tour + round)
  variable vue parties       ;# right side: parties (games) | joueurs (players)
  variable filtre {}         ;# search: games and players shown
  variable joueurs {}        ;# players of the current tour (API answer)
  variable erreur {}         ;# HTTP status of the last failed request (000: no connection)
}

proc ::moderne::direct::T {fr en} { return [::moderne::tr $fr $en] }

### Country of a place written by a broadcast ("Benidorm, Spain",
### "Villahermosa, Tabasco - México", "Bogota Colombia"): flag code or empty
proc ::moderne::drapeaux::code {lieu} {
  variable noms
  set l [string tolower [string trim $lieu]]
  if {$l eq {}} { return {} }
  # the last parts first ("..., Spain"), then the whole text
  set parts [lreverse [split $l ",-–/()|"]]
  foreach p $parts {
    set p [string trim $p " ."]
    if {[info exists noms($p)]} { return $noms($p) }
  }
  # a country's name as a word of the text ("Bogota Colombia")
  set mots [regexp -all -inline {[[:alpha:]'’.]+} $l]
  for {set n 3} {$n >= 1} {incr n -1} {
    for {set i [expr {[llength $mots] - $n}]} {$i >= 0} {incr i -1} {
      set m [join [lrange $mots $i [expr {$i + $n - 1}]] " "]
      if {[string length $m] >= 4 && [info exists noms($m)]} { return $noms($m) }
    }
  }
  return {}
}

### Empty image the size of a small flag (rows without a country)
proc ::moderne::drapeaux::vide {} {
  if {[lsearch -exact [image names] drapeau_vide] < 0} { image create photo drapeau_vide -width 21 -height 16 }
  return drapeau_vide
}

### Flag image of a country: petit (21x16, rows) or grand (128x96, covers)
proc ::moderne::drapeaux::photo {code taille} {
  variable donnees
  set src drapeau_$code
  if {[lsearch -exact [image names] $src] < 0} {
    if {![info exists donnees($code)]} { return {} }
    image create photo $src -format png -data $donnees($code)
  }
  set img ${src}_$taille
  if {[lsearch -exact [image names] $img] < 0} {
    image create photo $img
    if {$taille eq "grand"} { $img copy $src -zoom 2 2 } else { $img copy $src -subsample 3 3 }
  }
  return $img
}

################################################################################
### JSON (the Lichess answers): objects -> dicts, arrays -> lists,
### true/false -> 1/0, null -> empty
################################################################################

namespace eval ::moderne::json {
  variable tk {}
  variable p 0
}

proc ::moderne::json::parse {texte} {
  variable tk
  variable p
  set tk [regexp -all -inline {"(?:[^"\\]|\\.)*"|-?[0-9]+(?:\.[0-9]+)?(?:[eE][-+]?[0-9]+)?|true|false|null|[][{}:,]} $texte]
  set p 0
  set v [valeur]
  set tk {}
  return $v
}

proc ::moderne::json::chaine {x} {
  set x [string range $x 1 end-1]
  if {[string first "\\" $x] < 0} { return $x }
  return [subst -nocommands -novariables $x]
}

proc ::moderne::json::valeur {} {
  variable tk
  variable p
  set x [lindex $tk $p]
  incr p
  switch -- $x {
    "\{" {
      set d [dict create]
      if {[lindex $tk $p] eq "\}"} { incr p ; return $d }
      while {$p < [llength $tk]} {
        set k [chaine [lindex $tk $p]]
        incr p 2
        dict set d $k [valeur]
        set s [lindex $tk $p]
        incr p
        if {$s ne ","} { break }
      }
      return $d
    }
    "\[" {
      set l {}
      if {[lindex $tk $p] eq "\]"} { incr p ; return $l }
      while {$p < [llength $tk]} {
        lappend l [valeur]
        set s [lindex $tk $p]
        incr p
        if {$s ne ","} { break }
      }
      return $l
    }
    true { return 1 }
    false { return 0 }
    null { return {} }
  }
  if {[string index $x 0] eq "\""} { return [chaine $x] }
  return $x
}

### dict get with a default value
proc ::moderne::json::get {d args} {
  set defaut [lindex $args end]
  set cles [lrange $args 0 end-1]
  if {[catch {dict get $d {*}$cles} v]} { return $defaut }
  return $v
}

################################################################################
### Downloads
################################################################################

### Requests to lichess.org go through one queue, as Lichess asks of API
### clients: one request at a time, a pause between two (the cloud
### evaluation of a review sent a burst of requests and Lichess blocked the
### whole address, 2026-11-03), and a full minute without any request after
### a "too many requests" answer.
namespace eval ::moderne::direct {
  variable lichessFile {}      ;# waiting requests: {url suite}
  variable lichessOccupe 0     ;# a request is under way
  variable lichessDernier 0    ;# start of the last request (ms)
  variable lichessPause 0      ;# no request before this time (ms), after a 429
  # (after a 429, the cloud evaluations asked in the background (the review,
  # the review's green arrow) wait longer than those of the position on
  # screen: the reviews' bursts got the library's Cloud column refused,
  # Yosha 2026-11-05)
  variable lichessPauseFond 0
  # (a "too many requests" on the cloud evaluation: only the cloud
  # evaluations wait; it came back every minute and kept the broadcasts
  # waiting too, a click on a tournament seemed lost, Yosha 2026-11-09)
  variable lichessPauseCloud 0
}

proc ::moderne::direct::estCloud {url} { string match */api/cloud-eval* $url }

### Time before which a request for url may not go (ms)
proc ::moderne::direct::pauseLichess {url canal} {
  variable lichessPause
  if {![estCloud $url]} { return $lichessPause }
  variable lichessPauseCloud
  variable lichessPauseFond
  return [expr {$canal eq {} ? max($lichessPause, $lichessPauseCloud, $lichessPauseFond) : max($lichessPause, $lichessPauseCloud)}]
}

### A cloud evaluation refused at once during its pause (the error given
### when the answer is read)
proc ::moderne::direct::refuserCloud {url suite} {
  variable erreur 429
  noterLichess $url
  after idle [list apply {{suite} {
    set ::moderne::direct::erreur 429
    uplevel #0 [concat $suite [list {}]]
  }} $suite]
}

proc ::moderne::direct::estLichess {url} {
  return [regexp {^https?://(www\.)?lichess\.org/} $url]
}

### Minimal gap before a request to lichess.org (ms): one request at a
### time is Lichess's rule; the short gap only avoids back-to-back bursts
### (the review was not to be slower, Yosha 2026-11-03)
proc ::moderne::direct::ecartLichess {url canal} {
  # (the background cloud evaluations, the review's: 2 a second, Yosha
  # 2026-11-05; at 5 a second, reviews one after another got 429s)
  if {$canal eq {} && [string match */api/cloud-eval* $url]} { return 500 }
  return 200
}

proc ::moderne::direct::lichessSuivant {} {
  variable lichessFile
  variable lichessOccupe
  variable lichessDernier
  variable lichessPause
  if {$lichessOccupe || ![llength $lichessFile]} { return }
  set maintenant [clock milliseconds]
  # (cloud evaluations still waiting when their pause began: refused now,
  # they do not hold the others back)
  set reste {}
  foreach e $lichessFile {
    lassign $e u su ca
    if {[estCloud $u] && $maintenant < [pauseLichess $u $ca]} { refuserCloud $u $su ; continue }
    lappend reste $e
  }
  set lichessFile $reste
  if {![llength $lichessFile]} { return }
  lassign [lindex $lichessFile 0] url suite canal
  set quand [expr {max([pauseLichess $url $canal], $lichessDernier + [ecartLichess $url $canal])}]
  if {$maintenant < $quand} {
    after cancel ::moderne::direct::lichessSuivant
    after [expr {$quand - $maintenant}] ::moderne::direct::lichessSuivant
    return
  }
  set lichessFile [lrange $lichessFile 1 end]
  set lichessOccupe 1
  set lichessDernier $maintenant
  lireJsonMaintenant $url [list ::moderne::direct::lichessFini $url $suite]
}

proc ::moderne::direct::lichessFini {url suite v} {
  variable lichessOccupe 0
  variable erreur
  if {$erreur eq "429"} {
    if {[estCloud $url]} {
      variable lichessPauseCloud [expr {[clock milliseconds] + 60000}]
      variable lichessPauseFond [expr {[clock milliseconds] + 600000}]
    } else {
      variable lichessPause [expr {[clock milliseconds] + 60000}]
    }
  }
  noterLichess $url
  after idle ::moderne::direct::lichessSuivant
  uplevel #0 [concat $suite [list $v]]
}

### Lichess's answers in siby.log, once per change (a cloud column left
### empty on Windows with no clue, 2026-11-05)
proc ::moderne::direct::noterLichess {url} {
  variable erreur
  variable lichessDernierCode
  if {![info exists lichessDernierCode]} { set lichessDernierCode 200 }
  set c [expr {$erreur in {200 404} ? 200 : $erreur}]
  if {$c eq $lichessDernierCode} { return }
  catch {::moderne::journal [expr {$c eq "200" ? "Lichess: answering again" : "Lichess: answer $c ([lindex [split $url ?] 0])"}]}
  set lichessDernierCode $c
}

### GET url (JSON); calls "suite valeur" (empty value on error).
### canal: a request for what is on screen (e.g. "biblio"): it goes before
### the others and replaces the one of the same canal still waiting (the
### position has changed meanwhile), whose "abandon" script is run.
proc ::moderne::direct::lireJson {url suite {canal {}} {abandon {}}} {
  if {[estLichess $url]} {
    variable lichessFile
    variable lichessPause
    # (a cloud evaluation during the pause after a 429: answered at once,
    # with the error, rather than waiting a minute)
    # (the error given again when the answer is read: another answer in
    # between (the tablebase…) had put "200" back, and the library took the
    # position for one the cloud does not know, until Siby was started
    # again; Yosha 2026-11-06)
    if {[estCloud $url] && [clock milliseconds] < [pauseLichess $url $canal]} {
      refuserCloud $url $suite
      return
    }
    if {$canal ne {}} {
      set reste {}
      foreach e $lichessFile {
        if {[lindex $e 2] eq $canal} {
          catch {uplevel #0 [lindex $e 3]}
        } else {
          lappend reste $e
        }
      }
      set lichessFile [linsert $reste 0 [list $url $suite $canal $abandon]]
    } elseif {![string match */api/cloud-eval* $url]} {
      # (a request of the broadcasts view (list, tournament, round,
      # players): before the background cloud evaluations still waiting,
      # e.g. a review's; a click on a tournament waited behind dozens of
      # them, Yosha 2026-11-09)
      set k 0
      foreach e $lichessFile {
        if {[lindex $e 2] eq {} && [string match */api/cloud-eval* [lindex $e 0]]} { break }
        incr k
      }
      set lichessFile [linsert $lichessFile $k [list $url $suite {} {}]]
    } else {
      lappend lichessFile [list $url $suite {} {}]
    }
    lichessSuivant
    return
  }
  lireJsonMaintenant $url $suite
}

proc ::moderne::direct::lireJsonMaintenant {url suite} {
  # (the HTTP status on the last line: tells "no internet" from "Lichess
  # down" or "too many requests")
  set cmd [list curl -sSL --max-time 30 -A "Siby (live broadcasts)" -H "Accept: application/json" \
      -w "\n%{http_code}" $url]
  if {[catch {open "|$cmd" r} p]} {
    set ::moderne::direct::erreur 000
    uplevel #0 [concat $suite [list {}]]
    return
  }
  fconfigure $p -translation binary -blocking 0
  set ::moderne::direct::lu($p) {}
  fileevent $p readable [list ::moderne::direct::morceauJson $p $suite]
}

proc ::moderne::direct::morceauJson {p suite} {
  variable lu
  append lu($p) [read $p]
  if {![eof $p]} { return }
  fileevent $p readable {}
  catch {close $p}
  set t [encoding convertfrom utf-8 $lu($p)]
  unset lu($p)
  set code 000
  set i [string last "\n" $t]
  if {$i >= 0 && [string is integer -strict [string trim [string range $t $i end]]]} {
    set code [string trim [string range $t $i end]]
    set t [string range $t 0 [expr {$i - 1}]]
  }
  if {$code ne "200" || [catch {::moderne::json::parse $t} v]} { set v {} }
  # (not expr: "000" would become 0)
  variable erreur $code
  if {$code eq "200" && $v eq {}} { set erreur json }
  uplevel #0 [concat $suite [list $v]]
}

### What went wrong with the last Lichess request, for the user
proc ::moderne::direct::messageErreur {{introuvable {}}} {
  variable erreur
  switch -glob -- $erreur {
    000 { return [T "Pas de connexion à Lichess (internet ?)." "No connection to Lichess (internet?)."] }
    429 { return [T "Lichess demande de ralentir : nouvel essai dans une minute." "Lichess asks to slow down: trying again in a minute."] }
    404 { if {$introuvable ne {}} { return $introuvable } }
    5?? { return [T "Lichess est momentanément indisponible (maintenance ?). Nouvel essai automatique." \
              "Lichess is unavailable for the moment (maintenance?). Trying again automatically."] }
    json { return [T "Réponse de Lichess illisible. Nouvel essai automatique." \
              "Unreadable answer from Lichess. Trying again automatically."] }
  }
  return [T "Lichess a répondu par une erreur ($erreur)." "Lichess answered with an error ($erreur)."]
}

### Delay before trying again after a failed request (ms)
proc ::moderne::direct::delaiReessai {} {
  variable erreur
  return [expr {$erreur eq "429" ? 60000 : 30000}]
}

################################################################################
### Window
################################################################################

### Single-window (docking) mode: the views are layouts of the main window
proc ::moderne::direct::docking {} {
  expr {[::moderne::actif] && $::docking::USE_DOCKING}
}

### Tools menu: the broadcast view
proc ::moderne::direct::ouvrir {} {
  # (a finished game against an engine closed first: ::moderne::jeu::fermerSiFinie)
  if {![catch {::moderne::jeu::fermerSiFinie ::moderne::direct::ouvrir} r] && $r} { return }
  if {[docking]} {
    # back to the game that was being watched (left for another view), as
    # on Lichess; "← Broadcasts" in the game view goes to the list
    variable derniere
    variable parties
    variable numLive
    if {[info exists derniere] && $derniere ne {} && [info exists parties($derniere)]} {
      set id $derniere
      set ici 0
      catch {
        set ici [expr {[sc_base current] == [baseLive] && [info exists numLive($id)]
                       && [sc_game number] == $numLive($id)}]
      }
      if {$ici} {
        # (the game is on the board, as it was left: a review keeps it still)
        if {[catch vuePartie]} { vueListe }
      } elseif {[catch {suivre $id}]} {
        vueListe
      }
      return
    }
    vueListe
    return
  }
  ouvrirListe
}

### "← Broadcasts": the list, and no game to come back to
proc ::moderne::direct::retourListe {} {
  variable derniere {}
  vueListe
}

### Broadcast view: the list fills the window (the board is a hidden tab)
proc ::moderne::direct::vueListe {} {
  # (laid over the Lab when it is built: no layout to make)
  if {![catch {superposer liste} ok] && $ok} { return }
  if {$ok ne "0"} { catch {::moderne::journal "Retransmission (vue liste) : $ok"} }
  set W [expr {[winfo screenwidth .] - 40}]
  set H [expr {[winfo screenheight .] - 90}]
  ::moderne::disposition::appliquer moderne_direct_liste [list [list MainWindowGeometry "${W}x${H}+10+10"] \
      [list [list .pw vertical {}] [list TNotebook .nb [list .fdockdirectWin .fdockmain]]]] 0
  # like Lichess: no board while choosing a game (it comes back with the
  # game view)
  cacherEchiquier
  after 600 ::moderne::direct::cacherEchiquier
}

proc ::moderne::direct::cacherEchiquier {} {
  if {![winfo exists .fdockdirectWin]} { return }
  catch {
    set nb [::docking::find_tbn .fdockmain]
    if {$nb eq [::docking::find_tbn .fdockdirectWin]} {
      $nb select .fdockdirectWin
      $nb hide .fdockmain
    }
  }
}

### Game view: board and engines (Stockfish and Toby) on the left; live
### panel at the top right (with the players' library and the tablebase),
### notation and review below
proc ::moderne::direct::vuePartie {} {
  if {![catch {superposer partie} ok] && $ok} { return }
  if {$ok ne "0"} { catch {::moderne::journal "Retransmission (vue partie) : $ok"} }
  set ::moderne::disposition::forces [moteursDirect]
  # (the round's games above, the notation and the review below: half
  # each, the review fits with its curve)
  set ::moderne::disposition::hautDroite 0.5
  set code [catch {
    ::moderne::disposition::appliquer moderne_direct_partie \
        [::moderne::disposition::description {.fdockliveWin .fdockjoueursWin .fdocktbWin} {.fdockpgnWin}]
  } err]
  set ::moderne::disposition::forces {}
  set ::moderne::disposition::hautDroite 0.6
  if {$code} { error $err }
}

### Siby (2026-11-06): the two broadcast views laid over the Lab instead
### of layouts of their own, as My databases: the Lab stays built under
### them, so going to a broadcast and back is instant (each layout took
### 1.5 to 2 s to build on Windows, Yosha: "under 1 s"). The list covers
### the whole window; the game view covers the Lab's right side (live panel,
### players' library and tablebase above, notation below), the board and
### the engines being the Lab's. The tablebase and the notation are lent by
### the Lab and given back. Without the Lab built, or with other engines
### than the game view's, the layouts of before.
###  superpose: {} | liste | partie
namespace eval ::moderne::direct {
  variable superpose {}
  variable prets {}   ;# windows lent by the Lab: {window notebook index title selected}
}

### The Lab block built under the views (empty: none)
proc ::moderne::direct::labDessous {} {
  foreach lab [::moderne::lab::blocs] {
    if {[winfo exists $lab] && [winfo ismapped .pw]} { return $lab }
  }
  return {}
}

### The engine windows of the layout on screen (numbers, sorted)
proc ::moderne::direct::moteursLab {} {
  set l {}
  foreach f [winfo children .] {
    if {[regexp {^\.fdock(?:attente)?analysisWin([0-9]+)$} $f -> n] && [winfo manager $f] ne {}} { lappend l $n }
  }
  return [lsort -integer -unique $l]
}

### The cover: a frame of the main window with the list's tab group and the
### game view's two groups
proc ::moderne::direct::cache {} {
  set c .directCouvre
  if {[winfo exists $c.liste] && [winfo exists $c.pw.haut] && [winfo exists $c.pw.bas]} { return $c }
  catch {destroy $c}
  frame $c -background [::moderne::c fond] -borderwidth 0
  ttk::notebook $c.liste
  ttk::panedwindow $c.pw -orient vertical
  ttk::notebook $c.pw.haut
  ttk::notebook $c.pw.bas
  $c.pw add $c.pw.haut -weight 1
  $c.pw add $c.pw.bas -weight 1
  return $c
}

### The game view on screen: the live panel in a tab group of the layout
### (kept hidden under the Lab: no)
### Is window w (an embedded toplevel, ".liveWin") really on screen? Its
### own "mapped" flag stays set when its tab group is hidden under the
### Lab: its container is asked, all the way up
proc ::moderne::direct::aLEcran {w} {
  set f .fdock[string range $w 1 end]
  if {[winfo exists $f]} { return [winfo viewable $f] }
  expr {[winfo exists $w] && [winfo viewable $w]}
}

proc ::moderne::direct::vueOuverte {} {
  variable panneau
  if {![winfo exists $panneau]} { return 0 }
  # (shown on screen: open, whatever the tab groups say; the bands, the
  # LIVE line and the library stopped following when the group was not
  # found, Yosha 2026-11-11)
  if {[aLEcran $panneau]} { return 1 }
  set nb {}
  catch {set nb [::docking::find_tbn .fdock[string range $panneau 1 end]]}
  expr {$nb ne {}}
}

proc ::moderne::direct::enSuperposition {} {
  variable superpose
  expr {$superpose ne {} && [winfo exists .directCouvre]}
}

### The view v (liste, partie) laid over the Lab; 0: not possible
proc ::moderne::direct::superposer {v} {
  variable superpose
  variable panneau
  variable jw
  variable w
  variable prets
  if {![docking]} { return 0 }
  set lab [labDessous]
  if {$lab eq {}} { return 0 }
  # (the Lab's engines, whichever they are: after a game against an engine
  # the Lab kept the game's, the view then built a layout of its own and
  # its live panel came up empty, Yosha 2026-11-11)
  if {$superpose eq $v && [winfo exists .directCouvre] && [winfo ismapped .directCouvre]} {
    if {$v eq "liste"} { catch {raise .fdockdirectWin} }
    if {$v eq "partie"} { catch {garantirPrets .directCouvre} }
    return 1
  }
  if {$superpose ne {}} { retirerSuperposition }
  catch ::moderne::mesbases::retirerSuperposition
  # (the notation lent to the preparation's tab comes back first)
  catch ::moderne::prepa::rendreNotation
  set c [cache]
  if {$v eq "liste"} {
    pack forget $c.pw
    pack $c.liste -fill both -expand 1
    set ::docking::tbs($c.liste) $c
    catch ::moderne::docks::pauserSousCouverture
    place $c -in .pw -x 0 -y 0 -relwidth 1 -relheight 1
    raise $c
    set superpose liste
    if {[winfo exists .fdockdirectWin] && [::docking::find_tbn .fdockdirectWin] ne "$c.liste"} { catch {destroy $w} }
    set ::docking::layout_dest_notebook $c.liste
    set code [catch ouvrirListe err]
    set ::docking::layout_dest_notebook {}
    catch {raise .fdockdirectWin}
    catch ::docking::setTabStatus
    if {$code} { retirerSuperposition ; return -code error $err }
    # (the game view's panels made meanwhile, hidden: the first game opens
    # as fast as the next ones)
    variable preparation
    catch {after cancel $preparation}
    set preparation [after 1500 ::moderne::direct::preparer]
    return 1
  }
  # the game view: the Lab's windows of the analysis page made if they
  # were not yet (hidden page), then the tablebase and the notation lent
  catch {::moderne::lab::fabriquerPage [lindex [::moderne::lab::pages $lab] 1]}
  pack forget $c.liste
  pack $c.pw -fill both -expand 1
  set prets {}
  foreach {d dest} [list .fdocktbWin $c.pw.haut .fdockpgnWin $c.pw.bas .fdockbilanWin $c.pw.bas] {
    if {![winfo exists $d]} { continue }
    set nb [::docking::find_tbn $d]
    if {$nb eq {} || ![winfo exists $nb]} { continue }
    # (already in the cover, left there: lent again as it is, given back
    # to the Lab's group of the game list when the cover goes)
    if {[string match $c* $nb]} {
      lappend prets [list $d $c.perdu end [$nb tab $d -text] 1]
      continue
    }
    lappend prets [list $d $nb [$nb index $d] [$nb tab $d -text] [expr {[$nb select] eq $d}]]
  }
  set ::docking::tbs($c.pw.haut) $c.pw
  set ::docking::tbs($c.pw.bas) $c.pw
  # (the Lab's pages stay drawn under the cover, raised above them: shown
  # again they cost no redrawing, 0.4 s on Windows)
  place $c -in $lab -x 0 -y 0 -relwidth 1 -relheight 1
  raise $c
  set superpose partie
  set code [catch {
    # (the live panel and the players' library kept hidden from the last
    # time: shown again, their bands and contents brought up to date)
    set garde [expr {[winfo exists $panneau] && [winfo exists $jw] &&
        [::docking::find_tbn .fdock[string range $panneau 1 end]] eq "$c.pw.haut"}]
    set ::docking::layout_dest_notebook $c.pw.haut
    if {!$garde} {
      catch {destroy $panneau}
      catch {destroy $jw}
      ouvrirPanneau
      ouvrirJoueurs
    }
    set ::docking::layout_dest_notebook {}
    if {$garde} {
      bandes
      modeToby partie
      catch majPanneauListe
      catch majPanneauRondes
      catch majPanneau
      catch {after cancel ::moderne::direct::tic}
      after 1000 ::moderne::direct::tic
      after idle {catch ::moderne::direct::majJoueurs}
    }
    foreach x $prets {
      lassign $x d nb i titre
      set dest [expr {$d eq ".fdocktbWin" ? "$c.pw.haut" : "$c.pw.bas"}]
      catch {$nb forget $d}
      if {[catch {$dest add $d -text $titre}]} { catch {$dest select $d} }
    }
    foreach nb [list $c.pw.haut $c.pw.bas] {
      foreach t [$nb tabs] { raise $t }
    }
    catch {garantirPrets $c}
    catch {$c.pw.haut select .fdock[string range $panneau 1 end]}
    catch {$c.pw.bas select .fdockpgnWin}
    catch ::docking::setTabStatus
    # (half each, as the layout gave)
    after idle [list ::moderne::direct::moitie $c.pw]
  } err]
  set ::docking::layout_dest_notebook {}
  if {$code} { retirerSuperposition ; return -code error $err }
  return 1
}

### The live panel and the notation half each. The height is read once the
### cover is drawn: with the panels prepared, the game view shows before
### the cover has a height, and half of nothing hid the live panel
### (Yosha 2026-11-12).
proc ::moderne::direct::moitie {pw {n 0}} {
  if {![winfo exists $pw]} { return }
  set h [winfo height $pw]
  if {$h < 50 && $n < 40} {
    after 50 [list ::moderne::direct::moitie $pw [incr n]]
    return
  }
  catch {$pw sashpos 0 [expr {$h / 2}]}
}

### While the list is shown: the game view's live panel and players'
### library made in the cover's hidden part, left as a game view leaves them
### (kept, hidden), so that the first game opens without building them:
### 0.4 s of the 0.5 s it took on Linux, 2 s on Windows, Yosha 2026-11-11.
### One panel at a time, each when Siby is idle.
proc ::moderne::direct::preparer {{etape panneau}} {
  variable superpose
  variable panneau
  variable jw
  if {$superpose ne "liste"} { return }
  set c .directCouvre
  if {![winfo exists $c.pw.haut]} { return }
  set w [expr {$etape eq "panneau" ? $panneau : $jw}]
  if {![winfo exists $w]} {
    set debut [clock milliseconds]
    set ::docking::tbs($c.pw.haut) $c.pw
    set ::docking::layout_dest_notebook $c.pw.haut
    set code [catch {if {$etape eq "panneau"} { ouvrirPanneau } else { ouvrirJoueurs }} err]
    set ::docking::layout_dest_notebook {}
    # (as when a game view is left: the board's bands and Toby's mode go)
    if {$etape eq "panneau"} { catch {fermeturePanneau $panneau $panneau} }
    if {$code} {
      catch {::moderne::journal "Broadcasts: $etape not prepared: $err"}
      catch {destroy $w}
      return
    }
    catch {::moderne::journal "Broadcasts: $etape prepared in [expr {[clock milliseconds] - $debut}] ms"}
  }
  if {$etape eq "panneau"} {
    variable preparation [after 300 [list after idle [list ::moderne::direct::preparer joueurs]]]
  }
}

### The game view's notation and tablebase where they belong in the cover,
### wherever they are (taken back by another view meanwhile, or never lent:
### the game view showed no notation, Yosha 2026-11-11); written to
### siby.log when one had to be moved, with the place it was in. Their
### place in the Lab is noted (prets) so that it is given back.
proc ::moderne::direct::garantirPrets {c} {
  variable prets
  foreach {d dest} [list .fdocktbWin $c.pw.haut .fdockpgnWin $c.pw.bas .fdockbilanWin $c.pw.bas] {
    if {![winfo exists $d] || ![winfo exists $dest]} { continue }
    set nb [::docking::find_tbn $d]
    if {$nb eq $dest} { continue }
    catch {::moderne::journal "Broadcasts: $d was in {$nb}, put back in $dest"}
    if {$nb ne {} && [winfo exists $nb] && $nb ne $dest} {
      if {[lsearch -exact -index 0 $prets $d] < 0 && ![string match $c* $nb]} {
        lappend prets [list $d $nb [$nb index $d] [$nb tab $d -text] [expr {[$nb select] eq $d}]]
      }
      catch {$nb forget $d}
    }
    set titre [dict get [list .fdockpgnWin [T "Notation" "Notation"] .fdocktbWin [T "Tables de finales" "Tablebase"] .fdockbilanWin [T "Bilan" "Review"]] $d]
    if {[catch {$dest add $d -text $titre}]} { catch {$dest select $d} }
    catch {raise $d}
  }
}

### Window d's own group in the Lab, as the Lab's layout has it: the
### notation and the review with the game list, the tablebase with the
### opening library; {} if that group is not there
proc ::moderne::direct::maisonLab {d} {
  set voisin [dict get {.fdockpgnWin .fdockglistWin .fdockbilanWin .fdockglistWin .fdocktbWin .fdockbiblioWin} $d]
  if {![winfo exists $voisin]} { return {} }
  set nb [::docking::find_tbn $voisin]
  if {$nb eq {} || ![winfo exists $nb] || [string match .directCouvre* $nb] || [string match .jeuCouvre* $nb]} { return {} }
  return $nb
}

### The cover taken off: the Lab under it as it was. The live panel and the
### players' library are closed, as a change of layout did (the board's
### bands go with them); the list is kept, hidden.
proc ::moderne::direct::retirerSuperposition {} {
  variable superpose
  variable prets
  variable panneau
  variable jw
  if {$superpose eq {}} { return 0 }
  set v $superpose
  set superpose {}
  set c .directCouvre
  if {$v eq "liste"} { catch ::moderne::docks::reprendreSousCouverture }
  if {![winfo exists $c]} { set prets {} ; return 0 }
  place forget $c
  catch {unset ::docking::tbs($c.liste)}
  if {$v eq "partie"} {
    set lab [labDessous]
    # (the board's bands, the notation's live bar and Toby's mode go, as
    # when the panel was closed; the panel itself is kept, hidden)
    catch {fermeturePanneau $panneau $panneau}
    # the lent windows given back, with what was opened next to them
    # (the review next to the notation)
    foreach x $prets {
      lassign $x d nb i titre choisi
      if {![winfo exists $d]} { continue }
      # (its group of the Lab built again meanwhile, e.g. during a game
      # against an engine: the group of the game list or My databases, else
      # any of the Lab's; the notation stayed in the hidden cover, missing
      # from the Lab and from the next game view, Yosha 2026-11-11)
      # (its own group in the Lab when the one noted is gone or is the
      # cover's: the notation came back above the library, then next to
      # it, Yosha 2026-11-17)
      if {![winfo exists $nb] || [string match $c* $nb]} {
        set m [maisonLab $d]
        if {$m ne {}} { set nb $m ; set i end }
      }
      if {![winfo exists $nb]} {
        set nb {}
        foreach voisin {.fdockglistWin .fdockmesBasesWin .fdockpgnWin .fdocktbWin} {
          if {![winfo exists $voisin]} { continue }
          set v [::docking::find_tbn $voisin]
          if {$v ne {} && [winfo exists $v] && ![string match $c* $v]} { set nb $v ; break }
        }
        if {$nb eq {}} {
          foreach t [array names ::docking::tbs] {
            if {[winfo exists $t] && [winfo class $t] eq "TNotebook" && ![string match $c* $t] && [lsearch -exact [$t tabs] .fdockmain] < 0} { set nb $t ; break }
          }
        }
        if {$nb eq {}} { continue }
        set i end
      }
      set src [::docking::find_tbn $d]
      catch {$src forget $d}
      catch {
        if {$i eq "end" || $i >= [llength [$nb tabs]]} { $nb add $d -text $titre } else { $nb insert $i $d -text $titre }
        if {$choisi} { $nb select $d }
      }
    }
    foreach {src d} [list $c.pw.haut .fdocktbWin $c.pw.bas .fdockpgnWin] {
      if {![winfo exists $src]} { continue }
      foreach t [$src tabs] {
        if {$t in [list .fdock[string range $panneau 1 end] .fdock[string range $jw 1 end]]} { continue }
        # (the tablebase, the notation, the review: their own group in the
        # Lab; anything else opened there: with the notation)
        set m {}
        if {$t in {.fdockpgnWin .fdocktbWin .fdockbilanWin}} { set m [maisonLab $t] }
        if {$m eq {}} { set m [maisonLab [expr {$src eq "$c.pw.haut" ? ".fdocktbWin" : ".fdockpgnWin"}]] }
        set titre [$src tab $t -text]
        catch {$src forget $t}
        ::moderne::docks::rangerOnglet $t $titre $m .directCouvre
      }
    }
    set prets {}
    catch {unset ::docking::tbs($c.pw.haut)}
    catch {unset ::docking::tbs($c.pw.bas)}
  }
  catch ::docking::setTabStatus
  # (whatever stayed in the hidden cover, brought back: Yosha 2026-11-17,
  # no notation in the Lab after a broadcast game)
  after 300 {foreach d {.fdockpgnWin .fdocktbWin .fdockbilanWin} { catch {::sibyRapatrier $d} }}
  after idle {catch ::moderne::prepa::suivreNotation}
  # (the review given back next to the notation, never by an engine)
  catch ::moderne::bilan::verifierPlusTard
  return 1
}

### Default engines of the game view: Stockfish and Toby (else F2 / F3)
proc ::moderne::direct::moteursDirect {} {
  set l {}
  foreach motif {*stockfish* *toby*} {
    set i 0
    foreach e $::engines(list) {
      if {[string match -nocase $motif [lindex $e 0]] || [string match -nocase $motif [file tail [lindex $e 1]]]} {
        if {$i ni $l} { lappend l $i }
        break
      }
      incr i
    }
  }
  return $l
}

proc ::moderne::direct::ouvrirListe {} {
  variable w
  variable tours
  if {[winfo exists $w]} { catch {::createToplevel $w} ; catch {raise $w} ; return }
  if {[docking]} {
    ::createToplevel $w
    ::setTitle $w [T "Retransmissions" "Broadcasts"]
  } else {
    toplevel $w
    wm title $w [T "Retransmissions en direct" "Live broadcasts"]
    wm geometry $w 1280x760
    wm protocol $w WM_DELETE_WINDOW ::moderne::direct::fermer
  }
  set f [ttk::frame $w.f -padding 10]
  pack $f -fill both -expand 1

  # Title and Lichess credit
  set h [ttk::frame $f.h]
  ttk::label $h.titre -text [T "Retransmissions en direct" "Live broadcasts"] -font font_Bold
  ttk::label $h.lichess -text "Powered by Lichess" -foreground [::moderne::c accent] -cursor hand2
  bind $h.lichess <Button-1> {catch {openURL https://lichess.org/broadcast}}
  ::utils::tooltip::Set $h.lichess [T "Les retransmissions viennent de lichess.org (Siby ne diffuse rien)." \
      "The broadcasts come from lichess.org (Siby broadcasts nothing itself)."]
  pack $h.titre -side left
  pack $h.lichess -side right
  pack $h -side top -fill x -pady {0 8}

  # Tabs and search (like lichess.org/broadcast)
  set barre [ttk::frame $f.barre]
  pack $barre -side top -fill x -pady {0 8}
  set seg [ttk::frame $barre.seg]
  set style Toolbutton
  if {![catch {ttk::style layout Segment.Toolbutton} l] && $l ne {}} { set style Segment.Toolbutton }
  foreach {val fr en} {active "En cours" "Ongoing" upcoming "À venir" "Upcoming" past "Terminés" "Finished"} {
    ttk::radiobutton $seg.$val -text [T $fr $en] -style $style -variable ::moderne::direct::onglet \
        -value $val -command ::moderne::direct::chargerListe
    pack $seg.$val -side left -padx 1
  }
  pack $seg -side left
  set r [ttk::frame $barre.r]
  ttk::entry $r.e -textvariable ::moderne::direct::recherche -width 24
  ttk::button $r.b -text [T "Tournoi" "Tournament"] -command ::moderne::direct::chercher
  ttk::button $r.j -text [T "Joueur·se" "Player"] -command ::moderne::direct::chercherJoueur
  catch {::utils::tooltip::Set $r.b [T "Chercher un tournoi par son nom" "Find a tournament by its name"]}
  catch {::utils::tooltip::Set $r.j [T "Où joue cette personne ? (dans les tournois en cours)" "Where does this player play? (in the ongoing tournaments)"]}
  bind $r.e <Return> ::moderne::direct::chercher
  pack $r.e -side left
  pack $r.b $r.j -side left -padx {4 0}
  pack $r -side right

  ttk::panedwindow $f.pw -orient horizontal
  pack $f.pw -side top -fill both -expand 1

  # The tournaments, as a hidden list (the cards show them; selecting a
  # row opens the tournament)
  set g [ttk::frame $f.pw.g]
  set l [ttk::frame $g.l]
  ttk::treeview $l.t -columns {info} -show {tree headings} -selectmode browse
  $l.t heading #0 -text [T "Tournoi" "Tournament"] -anchor w
  $l.t heading info -text [T "Ronde / dates" "Round / dates"] -anchor w
  $l.t column #0 -width 340
  $l.t column info -width 120 -stretch 0
  ttk::scrollbar $l.y -orient vertical -command [list $l.t yview]
  $l.t configure -yscrollcommand [list $l.y set]
  pack $l.y -side right -fill y
  pack $l.t -side left -fill both -expand 1
  pack $l -side top -fill both -expand 1
  bind $l.t <<TreeviewSelect>> ::moderne::direct::tourChoisi

  # Tournament, rounds, games
  set d [ttk::frame $f.pw.d]
  ttk::label $d.retour -text "← [T "Tous les tournois" "All tournaments"]" -foreground [::moderne::c accent] -cursor hand2
  bind $d.retour <Button-1> ::moderne::direct::retourAccueil
  pack $d.retour -side top -anchor w -pady {0 6}
  ttk::label $d.nom -text [T "Choisis un tournoi à gauche." "Choose a tournament on the left."] -font font_Bold -wraplength 760 -justify left
  ttk::label $d.info -text {} -foreground [::moderne::c texteDoux] -wraplength 760 -justify left
  pack $d.nom $d.info -side top -anchor w
  set s [ttk::frame $d.s]
  ttk::label $s.lsec -text [T "Section :" "Section:"]
  ttk::combobox $s.sec -state readonly -width 22
  ttk::label $s.lr -text [T "Ronde :" "Round:"]
  ttk::combobox $s.r -state readonly -width 34
  bind $s.sec <<ComboboxSelected>> ::moderne::direct::sectionChoisie
  bind $s.r <<ComboboxSelected>> ::moderne::direct::rondeChoisie
  pack $s -side top -anchor w -pady 8
  # Games | Players, and a search box (filters both: find a player fast)
  set v [ttk::frame $d.v]
  ttk::radiobutton $v.parties -text [T "Parties" "Games"] -style Toolbutton \
      -variable ::moderne::direct::vue -value parties -command ::moderne::direct::basculerVue
  ttk::radiobutton $v.joueurs -text [T "Joueur·ses" "Players"] -style Toolbutton \
      -variable ::moderne::direct::vue -value joueurs -command ::moderne::direct::basculerVue
  ttk::label $v.lq -text "🔍"
  ttk::entry $v.q -width 28 -textvariable ::moderne::direct::filtre
  bind $v.q <KeyRelease> {after cancel ::moderne::direct::filtrer ; after 150 ::moderne::direct::filtrer}
  bind $v.q <Escape> {set ::moderne::direct::filtre {} ; ::moderne::direct::filtrer}
  catch {::utils::tooltip::Set $v.q [T "Chercher une joueuse ou un joueur (nom, titre, équipe, fédération)" \
      "Find a player (name, title, team, federation)"]}
  pack $v.parties $v.joueurs -side left
  pack $v.lq -side left -padx {16 4}
  pack $v.q -side left
  pack $v -side top -anchor w -pady {0 6}
  # players of the tournament (Lichess: rank, score, performance)
  set j [ttk::frame $d.j]
  ttk::treeview $j.t -columns {rang nom fed elo equipe score perf} -show headings -selectmode browse
  foreach {c fr en ww a} {
    rang "#" "#" 40 center
    nom "Joueur·se" "Player" 240 w
    fed "Féd." "Fed." 50 center
    elo "Elo" "Elo" 55 center
    equipe "Équipe" "Team" 200 w
    score "Points" "Points" 70 center
    perf "Perf." "Perf." 60 center
  } {
    $j.t heading $c -text [T $fr $en] -anchor $a
    $j.t column $c -width $ww -anchor $a -stretch [expr {$c in {nom equipe}}]
  }
  ttk::scrollbar $j.y -orient vertical -command [list $j.t yview]
  $j.t configure -yscrollcommand [list $j.y set]
  pack $j.y -side right -fill y
  pack $j.t -side left -fill both -expand 1
  catch {::moderne::tri::activer $j.t}
  bind $j.t <Double-Button-1> {after idle ::moderne::direct::suivreJoueur}
  bind $j.t <Return> {after idle ::moderne::direct::suivreJoueur}
  set p [ttk::frame $d.p]
  ttk::treeview $p.t -columns {n blanc eloB res noir eloN etat} -show {tree headings} -selectmode browse
  foreach {c fr en ww a} {
    n "N°" "No." 40 center
    blanc "Blancs" "White" 200 w
    eloB "Elo" "Elo" 55 center
    res "" "" 70 center
    noir "Noirs" "Black" 200 w
    eloN "Elo" "Elo" 55 center
    etat "Pendules" "Clocks" 200 center
  } {
    $p.t heading $c -text [T $fr $en] -anchor $a
    $p.t column $c -width $ww -anchor $a -stretch [expr {$c in {blanc noir}}]
  }
  $p.t column #0 -width 0 -stretch 0
  $p.t tag configure enCours -foreground [::moderne::c accent]
  $p.t tag configure match -font font_Bold
  ttk::scrollbar $p.y -orient vertical -command [list $p.t yview]
  $p.t configure -yscrollcommand [list $p.y set]
  pack $p.y -side right -fill y
  pack $p.t -side left -fill both -expand 1
  pack $p -side top -fill both -expand 1
  # (after the click: following a game changes the layout and destroys this list)
  bind $p.t <Motion> {::moderne::direct::survolListe %W %x %y blanc noir}
  bind $p.t <Leave> {::moderne::direct::survolListeFin %W}
  bind $p.t <Double-Button-1> {after idle ::moderne::direct::suivreSelection %W}
  bind $p.t <Return> {after idle ::moderne::direct::suivreSelection %W}
  set b [ttk::frame $d.b]
  ttk::label $b.etat -text {} -foreground [::moderne::c texteDoux]
  ttk::button $b.suivre -text [T "Suivre la partie" "Follow the game"] -command {after idle ::moderne::direct::suivreBouton}
  catch {$b.suivre configure -style Accent.TButton}
  ttk::button $b.web -text [T "Voir sur Lichess" "View on Lichess"] -command ::moderne::direct::voirLichess
  pack $b.etat -side left
  pack $b.suivre $b.web -side right -padx {6 0}
  pack $b -side top -fill x -pady {8 0}
  $f.pw add $d -weight 3
  basculerVue
  # home page: the tournaments as cards (like lichess.org/broadcast)
  set a [ttk::frame $d.a]
  canvas $a.c -highlightthickness 0 -borderwidth 0 -background [::moderne::c fond]
  ttk::scrollbar $a.y -orient vertical -command [list $a.c yview]
  $a.c configure -yscrollcommand [list $a.y set]
  frame $a.c.g -background [::moderne::c fond]
  $a.c create window 0 0 -window $a.c.g -anchor nw -tags g
  pack $a.y -side right -fill y
  pack $a.c -side left -fill both -expand 1
  bind $a.c <Configure> {::moderne::direct::disposerCartes}
  foreach x [list $a.c $a.c.g] {
    bind $x <MouseWheel> {::moderne::direct::rouler %D}
    bind $x <Button-4> {::moderne::direct::rouler 120}
    bind $x <Button-5> {::moderne::direct::rouler -120}
  }

  if {![docking]} { bind $w <Escape> ::moderne::direct::fermer }
  catch {::moderne::repeindre $w}
  if {[docking]} { ::createToplevelFinalize $w }
  if {[llength $tours]} { restaurer } else { chargerListe }
}

### Back to the broadcast view: the list, tournament and round as they were
proc ::moderne::direct::restaurer {} {
  variable w
  variable tours
  variable tour
  variable silence
  variable entrees
  variable encorePlus
  set t $w.f.pw.g.l.t
  set silence 1
  set liste $entrees
  set tours {}
  set entrees {}
  ajouterTours $liste [expr {[info exists encorePlus] && $encorePlus}]
  set id [::moderne::json::get $tour tour id {}]
  if {$id ne {} && [$t exists $id]} { $t selection set $id ; $t see $id }
  update idletasks
  set silence 0
  if {$tour ne {}} {
    masquerAccueil
    afficherTour
    afficherParties
  } else {
    afficherAccueil
  }
}

proc ::moderne::direct::fermer {} {
  variable w
  variable panneau
  arreterFlux
  catch {destroy $w}
  catch {destroy $panneau}
}

### Is a broadcast window open (list or live panel)?
proc ::moderne::direct::actif {} {
  variable w
  variable panneau
  expr {[winfo exists $w] || [winfo exists $panneau]}
}

proc ::moderne::direct::etat {texte} {
  variable w
  variable panneau
  catch {$w.f.pw.d.b.etat configure -text $texte}
  catch {$panneau.f.etat configure -text $texte}
}

################################################################################
### Tournament list
################################################################################

proc ::moderne::direct::chargerListe {} {
  # (the empty list's own words, if Lichess sent none: cleared)
  variable vide {}
  variable onglet
  variable api
  variable page
  variable tours
  variable w
  set page 1
  set tours {}
  variable entrees {}
  catch {$w.f.pw.g.l.t delete [$w.f.pw.g.l.t children {}]}
  afficherAccueil
  etat [T "Chargement des tournois…" "Loading tournaments…"]
  lireJson "$api/api/broadcast/top?page=1" ::moderne::direct::listeRecue
}

proc ::moderne::direct::pageSuivante {} {
  variable api
  variable page
  variable onglet
  incr page
  etat [T "Chargement…" "Loading…"]
  if {$onglet eq "search"} {
    variable recherche
    lireJson "$api/api/broadcast/search?page=$page&q=[::moderne::direct::url $recherche]" ::moderne::direct::rechercheRecue
  } else {
    lireJson "$api/api/broadcast/top?page=$page" ::moderne::direct::listeRecue
  }
}

proc ::moderne::direct::url {t} {
  set r {}
  foreach o [split [encoding convertto utf-8 $t] {}] {
    if {[string match {[A-Za-z0-9_.~-]} $o]} { append r $o } else { append r [format %%%02X [scan $o %c]] }
  }
  return $r
}

proc ::moderne::direct::chercher {} {
  variable recherche
  variable onglet
  variable api
  variable page
  variable tours
  variable w
  if {[string trim $recherche] eq {}} { set onglet active ; chargerListe ; return }
  set onglet search
  set page 1
  set tours {}
  variable entrees {}
  catch {$w.f.pw.g.l.t delete [$w.f.pw.g.l.t children {}]}
  afficherAccueil
  etat [T "Recherche…" "Searching…"]
  lireJson "$api/api/broadcast/search?page=1&q=[url $recherche]" ::moderne::direct::rechercheRecue
}

proc ::moderne::direct::rechercheRecue {v} {
  if {$v eq {}} { etat [messageErreur] ; return }
  ajouterTours [::moderne::json::get $v currentPageResults {}] [expr {[::moderne::json::get $v nextPage {}] ne {}}]
}

proc ::moderne::direct::listeRecue {v} {
  variable onglet
  variable w
  if {![winfo exists $w]} { return }
  if {$v eq {}} {
    etat [messageErreur]
    # (tried again while the window is open and the list still empty)
    after [delaiReessai] {
      if {[winfo exists $::moderne::direct::w] && ![llength $::moderne::direct::tours] &&
          $::moderne::direct::onglet ni {search joueur}} { ::moderne::direct::chargerListe }
    }
    return
  }
  switch -- $onglet {
    active   {
      set l [accueilEnCours $v]
      # (Lichess always has tournaments going on: an empty list is a
      # hiccup, said and tried again, Yosha 2026-11-09)
      if {![llength $l]} {
        variable vide [T "Lichess n'a envoyé aucun tournoi en cours. Nouvel essai dans 30 s." \
                           "Lichess sent no ongoing tournament. Trying again in 30 s."]
        ajouterTours {} 0
        etat $vide
        after 30000 {
          if {[winfo exists $::moderne::direct::w] && ![llength $::moderne::direct::tours] &&
              $::moderne::direct::onglet eq "active"} { ::moderne::direct::chargerListe }
        }
        return
      }
      ajouterTours $l 0
    }
    upcoming { ajouterTours [actifs $v 1] 0 }
    default  {
      set p [::moderne::json::get $v past {}]
      ajouterTours [::moderne::json::get $p currentPageResults {}] [expr {[::moderne::json::get $p nextPage {}] ne {}}]
    }
  }
}

### Ongoing (aVenir 0) or upcoming (1) tournaments of a /broadcast/top answer:
### Lichess gives both in "active" (the "upcoming" list is now empty); a
### tournament is upcoming while its first day is still to come. Lichess's
### order for the ongoing ones, by start date for the upcoming ones.
proc ::moderne::direct::actifs {v aVenir} {
  set maintenant [clock milliseconds]
  set l {}
  foreach e [concat [::moderne::json::get $v active {}] [::moderne::json::get $v upcoming {}]] {
    set debut [lindex [::moderne::json::get $e tour dates {}] 0]
    if {![string is wide -strict $debut]} { set debut 0 }
    if {($debut > $maintenant) == $aVenir} { lappend l [list $debut $e] }
  }
  if {$aVenir} { set l [lsort -integer -index 0 $l] }
  set r {}
  foreach x $l { lappend r [lindex $x 1] }
  return $r
}

### "Ongoing" tab, in Lichess's order: the tournaments under way, and the
### major ones (tier 4 and 5) even if they start in a few hours or ended a
### moment ago, as on lichess.org/broadcast
proc ::moderne::direct::accueilEnCours {v} {
  set maintenant [clock milliseconds]
  set l {}
  foreach e [concat [::moderne::json::get $v active {}] [::moderne::json::get $v upcoming {}]] {
    set debut [lindex [::moderne::json::get $e tour dates {}] 0]
    if {![string is wide -strict $debut]} { set debut 0 }
    if {$debut <= $maintenant || [::moderne::json::get $e tour tier 0] >= 4} { lappend l $e }
  }
  return $l
}

### First tournament of the list whose round is being played (else the first)
proc ::moderne::direct::premierEnDirect {} {
  variable entrees
  foreach e $entrees {
    if {[::moderne::json::get $e round ongoing 0]} { return [::moderne::json::get $e tour id {}] }
  }
  return [::moderne::json::get [lindex $entrees 0] tour id {}]
}

### "in 11 h", "in 2 days", "8 h ago" (ms since 1970)
proc ::moderne::direct::relatif {ms} {
  set d [expr {($ms - [clock milliseconds]) / 60000}]
  set a [expr {abs($d)}]
  if {$a < 60} {
    set t "$a min"
  } elseif {$a < 48 * 60} {
    set t "[expr {$a / 60}] h"
  } else {
    set t "[expr {$a / 1440}] [T jours days]"
  }
  return [expr {$d >= 0 ? [T "dans $t" "in $t"] : [T "il y a $t" "$t ago"]}]
}

### A date in words, local time, as Lichess shows it (Yosha 2026-11-11):
### "12 Nov" / "12 nov." (British English, as Siby's)
proc ::moderne::direct::jourMois {sec} {
  set m [scan [clock format $sec -format %m] %d]
  set mois [expr {[::moderne::tr F E] eq "F"
      ? [lindex {janv. févr. mars avr. mai juin juil. août sept. oct. nov. déc.} [expr {$m - 1}]]
      : [lindex {Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec} [expr {$m - 1}]]}]
  return "[scan [clock format $sec -format %d] %d] $mois"
}

### A round's start, local time: "12 Nov 20:00"
proc ::moderne::direct::debutRonde {ms} {
  set sec [expr {$ms / 1000}]
  return "[jourMois $sec] [clock format $sec -format %H:%M]"
}

### Dates of a tour (ms since 1970) as text: "10–12 Nov 2026",
### "28 Oct – 3 Nov 2026"
proc ::moderne::direct::dates {t} {
  set d [::moderne::json::get $t dates {}]
  if {![llength $d]} { return {} }
  set a [expr {[lindex $d 0] / 1000}]
  set an [clock format $a -format %Y]
  if {[llength $d] > 1} {
    set b [expr {[lindex $d 1] / 1000}]
    set bn [clock format $b -format %Y]
    if {[clock format $b -format %Y%m%d] ne [clock format $a -format %Y%m%d]} {
      if {[clock format $b -format %Y%m] eq [clock format $a -format %Y%m]} {
        return "[scan [clock format $a -format %d] %d]–[jourMois $b] $bn"
      }
      if {$bn eq $an} { return "[jourMois $a] – [jourMois $b] $bn" }
      return "[jourMois $a] $an – [jourMois $b] $bn"
    }
  }
  return "[jourMois $a] $an"
}

proc ::moderne::direct::ajouterTours {liste encore} {
  variable tours
  variable entrees
  variable encorePlus
  variable w
  set encorePlus $encore
  if {![winfo exists $w]} { return }
  set t $w.f.pw.g.l.t
  foreach e $liste {
    set tr [::moderne::json::get $e tour {}]
    set id [::moderne::json::get $tr id {}]
    if {$id eq {} || [$t exists $id]} { continue }
    lappend tours $tr
    lappend entrees $e
    set r [::moderne::json::get $e round {}]
    set info [::moderne::json::get $r name {}]
    if {[::moderne::json::get $r ongoing 0]} { set info "● $info" }
    if {$info eq {}} { set info [dates $tr] }
    $t insert {} end -id $id -text [::moderne::json::get $tr name ?] -values [list $info]
  }
  set n [llength [$t children {}]]
  etat [expr {$n ? "$n [T tournois tournaments]" : [T "Aucun tournoi." "No tournament."]}]
  if {[accueilVisible]} { remplirCartes }
}

################################################################################
### Home page: cards of the tournaments
################################################################################

proc ::moderne::direct::afficherAccueil {} {
  variable w
  set d $w.f.pw.d
  if {![winfo exists $d.a]} { return }
  place $d.a -x 0 -y 0 -relwidth 1 -relheight 1
  raise $d.a
  remplirCartes
}

proc ::moderne::direct::masquerAccueil {} {
  variable w
  catch {place forget $w.f.pw.d.a}
}

proc ::moderne::direct::accueilVisible {} {
  variable w
  expr {[winfo exists $w.f.pw.d.a] && [winfo manager $w.f.pw.d.a] eq "place"}
}

proc ::moderne::direct::rouler {delta} {
  variable w
  set c $w.f.pw.d.a.c
  if {[tk windowingsystem] eq "x11"} { set n [expr {$delta > 0 ? -3 : 3}] } else { set n [expr {-$delta / 40}] }
  $c yview scroll $n units
}

### Tournament name without the group name ("41st Cup | Open" -> "Open")
proc ::moderne::direct::sousTitre {nom groupe} {
  if {$groupe ne {} && [string first $groupe $nom] == 0} {
    return [string trim [string range $nom [string length $groupe] end] " |-–:"]
  }
  return {}
}

proc ::moderne::direct::remplirCartes {} {
  variable w
  variable entrees
  variable onglet
  variable encorePlus
  set g $w.f.pw.d.a.c.g
  if {![winfo exists $g]} { return }
  foreach x [winfo children $g] { destroy $x }
  set i 0
  if {$onglet eq "joueur"} {
    variable trouves
    foreach cle [lsort -dictionary [array names trouves]] {
      carteTrouve $g.c[incr i] $cle
    }
  } else {
    # (Lichess's order) the major tournaments (Lichess tier 4 and 5) as
    # large cards with their cover, the others as compact rows
    set vus {} ; set une {} ; set autres {}
    foreach e $entrees {
      set id [::moderne::json::get $e tour id {}]
      if {$id eq {} || $id in $vus} { continue }
      lappend vus $id
      if {[::moderne::json::get $e tour tier 0] >= 4} { lappend une $e } else { lappend autres $e }
    }
    if {[llength $une] && [llength $autres]} {
      label $g.tUne -text [string toupper [T "À la une" "Featured"]] -font font_Small \
          -background [::moderne::c fond] -foreground [::moderne::c texteDoux]
      label $g.tAutres -text [string toupper [T "Autres tournois" "Other tournaments"]] -font font_Small \
          -background [::moderne::c fond] -foreground [::moderne::c texteDoux]
    }
    # (the large cards first, then the medium ones)
    set grandes {} ; set moyennes {}
    foreach e $une {
      if {[::moderne::json::get $e tour tier 0] >= 5} { lappend grandes $e } else { lappend moyennes $e }
    }
    foreach e [concat $grandes $moyennes] { carte $g.c[incr i] $e 1 }
    foreach e $autres { ligneTour $g.l[incr i] $e }
    if {$i && [info exists encorePlus] && $encorePlus} {
      ttk::button $g.plus -text [T "Plus de tournois…" "More tournaments…"] -command ::moderne::direct::pageSuivante
    }
  }
  if {!$i && $onglet ne "joueur"} {
    variable vide
    set texteVide [T "Aucun tournoi." "No tournament."]
    if {[info exists vide] && $vide ne {}} { set texteVide $vide }
    label $g.vide -text $texteVide -background [::moderne::c fond] \
        -foreground [::moderne::c texteDoux]
  }
  disposerCartes
}

### A player found by the "Player" search: name, tournament, rating and score
proc ::moderne::direct::carteTrouve {c cle} {
  variable trouves
  lassign $trouves($cle) id nom titre nomTour info
  set fond [::moderne::c surface]
  frame $c -background $fond -highlightthickness 1 -highlightbackground [::moderne::c bordure] \
      -highlightcolor [::moderne::c bordure] -cursor hand2 -padx 12 -pady 10
  label $c.haut -text $nomTour -foreground [::moderne::c texteDoux] -background $fond -font font_Small -anchor w -justify left
  label $c.nom -text [string trim "$titre $nom"] -foreground [::moderne::c texteFort] -background $fond -font font_Bold -anchor w -justify left
  pack $c.haut $c.nom -side top -anchor w -fill x
  if {$info ne {}} {
    label $c.bas -text $info -foreground [::moderne::c texte] -background $fond -anchor w -justify left
    pack $c.bas -side top -anchor w -fill x -pady {6 0}
  }
  foreach x [concat $c [winfo children $c]] {
    bind $x <Button-1> [list ::moderne::direct::carteChoisie $cle]
    bind $x <Enter> [list ::moderne::direct::survolCarte $c 1]
    bind $x <Leave> [list ::moderne::direct::survolCarte $c 0]
    bind $x <MouseWheel> {::moderne::direct::rouler %D}
    bind $x <Button-4> {::moderne::direct::rouler 120}
    bind $x <Button-5> {::moderne::direct::rouler -120}
  }
}

### "← All tournaments": back to the cards
proc ::moderne::direct::retourAccueil {} {
  variable w
  variable silence
  set silence 1
  catch {$w.f.pw.g.l.t selection set {}}
  update idletasks
  set silence 0
  variable tour {}
  afficherAccueil
}

proc ::moderne::direct::carte {c e {couv 0}} {
  set tr [::moderne::json::get $e tour {}]
  set r [::moderne::json::get $e round {}]
  set id [::moderne::json::get $tr id {}]
  set fond [::moderne::c surface]
  frame $c -background $fond -highlightthickness 1 -highlightbackground [::moderne::c bordure] \
      -highlightcolor [::moderne::c bordure] -cursor hand2
  # the cover (Lichess's image, else the country's flag), drawn by disposerCartes
  if {$couv && [::moderne::json::get $tr tier 0] >= 5} { set ::moderne::direct::doubles($c) 1 } else { catch {unset ::moderne::direct::doubles($c)} }
  if {$couv} {
    canvas $c.img -highlightthickness 0 -borderwidth 0 -background [::moderne::c surface2] -height 10 -width 10
    pack $c.img -side top -fill x
    set ::moderne::direct::couvertures($c) [list $id [::moderne::json::get $tr image {}] \
        [::moderne::drapeaux::code [::moderne::json::get $tr info location {}]]]
  }
  set k [frame $c.k -background $fond -padx 12 -pady 10]
  pack $k -side top -fill both -expand 1
  label $k.haut -text [enTete $e] -foreground [couleurEnTete $e] -background $fond -font font_Small -anchor w
  set groupe [::moderne::json::get $e group {}]
  set nom [::moderne::json::get $tr name ?]
  set sous [sousTitre $nom $groupe]
  if {$sous ne {}} { set nom $groupe }
  if {[::moderne::json::get $tr tier 0] eq "5"} { set nom "★ $nom" }
  label $k.nom -text $nom -foreground [::moderne::c texteFort] -background $fond -font font_Bold \
      -anchor w -justify left
  pack $k.haut $k.nom -side top -anchor w -fill x
  if {$sous ne {}} {
    label $k.sous -text $sous -foreground [::moderne::c texte] -background $fond -anchor w -justify left
    pack $k.sous -side top -anchor w -fill x
  }
  set joueurs [::moderne::json::get $tr info players {}]
  if {$joueurs ne {}} {
    label $k.j -text $joueurs -foreground [::moderne::c texte] -background $fond -anchor w -justify left
    pack $k.j -side top -anchor w -fill x -pady {6 0}
  }
  lieuCadence $k.bas $tr $fond
  pack $k.bas -side top -anchor w -fill x -pady {6 0}
  progres $k.prog $e $fond
  if {[winfo exists $k.prog]} { pack $k.prog -side top -fill x -pady {8 0} }
  lierCarte $c $id
}

### Clicks, hover and wheel on a card and everything in it
proc ::moderne::direct::lierCarte {c id} {
  foreach x [concat $c [winfo children $c] [winfo children $c.k] [expr {[winfo exists $c.k.bas] ? [winfo children $c.k.bas] : {}}]] {
    bind $x <Button-1> [list ::moderne::direct::carteChoisie $id]
    bind $x <Enter> [list ::moderne::direct::survolCarte $c 1]
    bind $x <Leave> [list ::moderne::direct::survolCarte $c 0]
    bind $x <MouseWheel> {::moderne::direct::rouler %D}
    bind $x <Button-4> {::moderne::direct::rouler 120}
    bind $x <Button-5> {::moderne::direct::rouler -120}
  }
}

### Round n / N of a tournament: {n N} (empty when unknown)
proc ::moderne::direct::rondes {e} {
  set n {} ; set total {}
  regexp {\d+} [::moderne::json::get $e round name {}] n
  set f [string tolower [::moderne::json::get $e tour info format {}]]
  if {[regexp {(\d+)\s*-?\s*(rounds?|rondes?|rondas?|turni|runden)} $f -> x]} {
    set total $x
  } elseif {[regexp {(\d+)\s*-?\s*(players?|teams?|joueurs|équipes)} $f -> x] && $x > 1} {
    set total [expr {$x - 1}]
  }
  if {$n ne {} && $total ne {} && $n > $total} { set total {} }
  return [list $n $total]
}

### First line of a card: live, round n / N, dates
proc ::moderne::direct::enTete {e} {
  lassign [rondes $e] n total
  set nomR [::moderne::json::get $e round name {}]
  set ronde [expr {$n ne {} ? "[T Ronde Round] $n[expr {$total ne {} ? " / $total" : {}}]" : $nomR}]
  if {[::moderne::json::get $e round ongoing 0]} {
    return "● [T "EN DIRECT" "LIVE"]  •  $ronde"
  }
  # (as on Lichess: the next round "in 11 h", the last one "8 h ago")
  set debutR [::moderne::json::get $e round startsAt {}]
  set finR [::moderne::json::get $e round finishedAt {}]
  set maintenant [clock milliseconds]
  if {[string is wide -strict $debutR] && $debutR > $maintenant} {
    set dt [relatif $debutR]
  } elseif {[string is wide -strict $finR] && [string is wide -strict $debutR] && $maintenant - $debutR < 2 * 86400000} {
    set dt [relatif $debutR]
  } else {
    set dt [dates [::moderne::json::get $e tour {}]]
  }
  return [expr {$ronde eq {} ? $dt : ($dt eq {} ? $ronde : "$ronde  •  $dt")}]
}

### Live in red, as on Lichess
proc ::moderne::direct::couleurEnTete {e} {
  return [expr {[::moderne::json::get $e round ongoing 0] ? "#e5534b" : [::moderne::c texteDoux]}]
}

### Bottom line: flag, place, time control icon and time control
proc ::moderne::direct::lieuCadence {b tr fond} {
  frame $b -background $fond
  set lieu [::moderne::json::get $tr info location {}]
  set code [::moderne::drapeaux::code $lieu]
  if {$code ne {}} {
    label $b.d -image [::moderne::drapeaux::photo $code petit] -background $fond
    pack $b.d -side left -padx {0 6}
  }
  label $b.l -text $lieu -foreground [::moderne::c texteDoux] -background $fond -font font_Small -anchor w -justify left
  pack $b.l -side left
  set tc [::moderne::json::get $tr info tc {}]
  set img [dict get {standard cad_lente rapid cad_rapide blitz cad_blitz} \
      [expr {[::moderne::json::get $tr info fideTC {}] in {standard rapid blitz} ? [::moderne::json::get $tr info fideTC {}] : "standard"}]]
  if {$tc ne {} || [::moderne::json::get $tr info fideTC {}] ne {}} {
    if {[lsearch -exact [image names] $img] >= 0} {
      label $b.c -image $img -background $fond
      pack $b.c -side left -padx {10 4}
    }
    label $b.t -text [tcCourt $tc] -foreground [::moderne::c texteDoux] -background $fond -font font_Small
    pack $b.t -side left
    if {$tc ne {}} {
      foreach x [list $b.t $b.c] { if {[winfo exists $x]} { catch {::utils::tooltip::Set $x $tc} } }
    }
  }
}

### "90 min + 30 sec / move" -> "90+30"
proc ::moderne::direct::tcCourt {tc} {
  set n [regexp -all -inline {\d+} $tc]
  if {[llength $n] >= 2 && [regexp -nocase {min|'|\+|m } $tc]} { return "[lindex $n 0]+[lindex $n 1]" }
  return $tc
}

### Thin progress bar of the rounds played (red while live)
proc ::moderne::direct::progres {p e fond} {
  lassign [rondes $e] n total
  if {$n eq {} || $total eq {}} { return }
  canvas $p -width 10 -height 3 -highlightthickness 0 -borderwidth 0 -background [::moderne::c surface2]
  # rounds played: this one counts once finished, half while it is played
  set fait [expr {[::moderne::json::get $e round finished 0] ? $n : ([::moderne::json::get $e round ongoing 0] ? $n - 0.5 : $n - 1)}]
  set ::moderne::direct::progresTour($p) [list [expr {double($fait) / $total}] \
      [expr {[::moderne::json::get $e round ongoing 0] ? "#e5534b" : [::moderne::c accent]}]]
  bind $p <Configure> [list ::moderne::direct::dessinerProgres $p]
}

proc ::moderne::direct::dessinerProgres {p} {
  if {![winfo exists $p] || ![info exists ::moderne::direct::progresTour($p)]} { return }
  lassign $::moderne::direct::progresTour($p) f coul
  $p delete all
  $p create rectangle 0 0 [expr {int([winfo width $p] * min(1.0, $f))}] 3 -fill $coul -width 0
}

### A compact row: flag, name, place, round, time control
proc ::moderne::direct::ligneTour {c e} {
  set tr [::moderne::json::get $e tour {}]
  set id [::moderne::json::get $tr id {}]
  set fond [::moderne::c surface]
  frame $c -background $fond -cursor hand2 -highlightthickness 1 -highlightbackground $fond -highlightcolor $fond
  set k [frame $c.k -background $fond -padx 10 -pady 7]
  pack $k -fill both -expand 1
  set lieu [::moderne::json::get $tr info location {}]
  set code [::moderne::drapeaux::code $lieu]
  label $k.d -background $fond -image [expr {$code ne {} ? [::moderne::drapeaux::photo $code petit] : [::moderne::drapeaux::vide]}]
  set groupe [::moderne::json::get $e group {}]
  set nom [::moderne::json::get $tr name ?]
  set sous [sousTitre $nom $groupe]
  if {$sous ne {}} { set nom $groupe }
  frame $k.n -background $fond
  label $k.n.nom -text $nom -foreground [::moderne::c texteFort] -background $fond -font font_Bold -anchor w
  pack $k.n.nom -side left
  if {$sous ne {}} {
    label $k.n.sous -text "•  $sous" -foreground [::moderne::c texteDoux] -background $fond -anchor w
    pack $k.n.sous -side left -padx {8 0}
  }
  # (long addresses shortened, the whole one in the tooltip)
  set court [expr {[string length $lieu] > 38 ? "[string trim [string range $lieu 0 36]]…" : $lieu}]
  label $k.lieu -text $court -foreground [::moderne::c texteDoux] -background $fond -font font_Small -anchor w
  if {$court ne $lieu} { catch {::utils::tooltip::Set $k.lieu $lieu} }
  label $k.etat -text [enTete $e] -foreground [couleurEnTete $e] -background $fond -font font_Small -anchor w
  frame $k.cad -background $fond
  set img [dict get {standard cad_lente rapid cad_rapide blitz cad_blitz} \
      [expr {[::moderne::json::get $tr info fideTC {}] in {standard rapid blitz} ? [::moderne::json::get $tr info fideTC {}] : "standard"}]]
  if {[lsearch -exact [image names] $img] >= 0} {
    label $k.cad.i -image $img -background $fond
    pack $k.cad.i -side left -padx {0 4}
  }
  set tc [::moderne::json::get $tr info tc {}]
  label $k.cad.t -text [tcCourt $tc] -foreground [::moderne::c texteDoux] -background $fond -font font_Small
  pack $k.cad.t -side left
  if {$tc ne {}} { catch {::utils::tooltip::Set $k.cad.t $tc} }
  grid $k.d $k.n $k.lieu $k.etat $k.cad -sticky w -padx {0 14}
  grid columnconfigure $k 1 -weight 1
  foreach x [concat $c $k [winfo children $k] [winfo children $k.n] [winfo children $k.cad]] {
    bind $x <Button-1> [list ::moderne::direct::carteChoisie $id]
    bind $x <Enter> [list ::moderne::direct::survolCarte $c 1]
    bind $x <Leave> [list ::moderne::direct::survolCarte $c 0]
    bind $x <MouseWheel> {::moderne::direct::rouler %D}
    bind $x <Button-4> {::moderne::direct::rouler 120}
    bind $x <Button-5> {::moderne::direct::rouler -120}
  }
}

################################################################################
### Covers of the major tournaments: Lichess's image (WebP, cached on disk),
### else the country's flag
################################################################################

proc ::moderne::direct::dossierCouvertures {} {
  set d [file join $::scidUserDir couvertures]
  catch {file mkdir $d}
  return $d
}

### Draws the cover of card c at width l (2:1, as Lichess's images)
proc ::moderne::direct::couverture {c l} {
  variable couvertures
  if {![winfo exists $c.img] || ![info exists couvertures($c)]} { return }
  lassign $couvertures($c) id url code
  variable largeurCouv
  set largeurCouv($c) $l
  set h [expr {$l / 2}]
  $c.img configure -width $l -height $h
  $c.img delete all
  set f [file join [dossierCouvertures] $id.webp]
  set fait 0
  if {$url ne {} && [file exists $f] && [file size $f] > 0} {
    set p couv_$id
    if {[lsearch -exact [image names] $p] < 0} { image create photo $p }
    if {[image width $p] != $l} {
      if {[catch {sc_webp $f $p $l $h}]} { catch {file delete $f} ; set p {} }
    }
    if {$p ne {}} {
      $c.img create image 0 0 -image $p -anchor nw
      set fait 1
    }
  } elseif {$url ne {}} {
    telechargerCouverture $id $url
  }
  if {!$fait && $code ne {}} {
    $c.img create image [expr {$l / 2}] [expr {$h / 2}] -image [::moderne::drapeaux::photo $code grand]
  } elseif {!$fait} {
    $c.img create text [expr {$l / 2}] [expr {$h / 2}] -text ♛ -font {Helvetica 48} -fill [::moderne::c texteDoux]
  }
}

### Download of a cover (once per session and tournament), then the card is
### drawn again
proc ::moderne::direct::telechargerCouverture {id url} {
  variable enTelechargement
  if {[info exists enTelechargement($id)]} { return }
  set enTelechargement($id) 1
  set f [file join [dossierCouvertures] $id.webp]
  set cmd [list curl -sSL --max-time 30 -A "Siby (live broadcasts)" -o $f.part $url]
  if {[catch {open "|$cmd" r} p]} { return }
  fconfigure $p -blocking 0
  fileevent $p readable [list ::moderne::direct::couvertureRecue $p $id $f]
}

proc ::moderne::direct::couvertureRecue {p id f} {
  read $p
  if {![eof $p]} { return }
  catch {close $p}
  if {[file exists $f.part] && [file size $f.part] > 0} {
    catch {file rename -force $f.part $f}
  } else {
    catch {file delete $f.part}
    return
  }
  variable couvertures
  foreach c [array names couvertures] {
    if {[winfo exists $c] && [lindex $couvertures($c) 0] eq $id} {
      # (at the width the layout gave it, not the one on screen yet)
      variable largeurCouv
      couverture $c [expr {[info exists largeurCouv($c)] ? $largeurCouv($c) : [winfo width $c.img]}]
    }
  }
}

proc ::moderne::direct::survolCarte {c dedans} {
  if {![winfo exists $c]} { return }
  set fond [::moderne::c [expr {$dedans ? "survol" : "surface"}]]
  set bord [expr {[string match c* [winfo name $c]] ? [::moderne::c [expr {$dedans ? "accent" : "bordure"}]] : $fond}]
  $c configure -background $fond -highlightbackground $bord
  set l [winfo children $c]
  while {[llength $l]} {
    set x [lindex $l 0]
    set l [concat [lrange $l 1 end] [winfo children $x]]
    # (not the cover nor the progress bar)
    if {[winfo class $x] eq "Canvas"} { continue }
    catch {$x configure -background $fond}
  }
}

proc ::moderne::direct::carteChoisie {id} {
  variable w
  set t $w.f.pw.g.l.t
  if {[$t exists $id]} {
    $t selection set $id
    $t see $id
  } else {
    chargerTour $id
  }
}

### Grid of cards: as many columns of ~320 px as the width allows; the
### compact rows (other tournaments) take the whole width
proc ::moderne::direct::disposerCartes {} {
  variable w
  set c $w.f.pw.d.a.c
  if {![winfo exists $c]} { return }
  set g $c.g
  set larg [winfo width $c]
  if {$larg < 50} { return }
  # card width like Lichess's (about 270 points, whatever the screen's
  # scaling); the cards do not stretch past it, the rest stays empty
  set s [expr {max(1.0, [tk scaling] * 72 / 96.0)}]
  set ncol [expr {max(1, $larg / int(272 * $s))}]
  set lc [expr {min(($larg - 12 * ($ncol + 1)) / $ncol, int(290 * $s))}]
  # (the major tournament: two columns wide, gap included)
  set ld [expr {2 * $lc + 12}]
  set ligne 0
  if {[winfo exists $g.tUne]} {
    grid $g.tUne -row $ligne -column 0 -columnspan $ncol -sticky w -padx 12 -pady {14 0}
    incr ligne
  }
  set i 0
  set avantDouble 0
  foreach x [winfo children $g] {
    if {[winfo class $x] ne "Frame" || ![string match c* [winfo name $x]]} { continue }
    set ls [expr {[winfo exists $x.k] ? [concat [winfo children $x.k] [winfo children $x.k.bas]] : [winfo children $x]}]
    foreach l $ls {
      if {[winfo class $l] eq "Label"} { catch {$l configure -wraplength [expr {$lc - 26}]} }
    }
    # (the biggest tournaments, Lichess tier 5: double cards, as on Lichess,
    # side by side while the row has room)
    set double [expr {[info exists ::moderne::direct::doubles($x)] && $ncol >= 2}]
    if {$double && $i % $ncol + 2 > $ncol} { set i [expr {($i / $ncol + 1) * $ncol}] }
    # (the medium cards start on a new row, under the large ones)
    if {!$double && $avantDouble && $i % $ncol} { set i [expr {($i / $ncol + 1) * $ncol}] }
    set avantDouble $double
    grid $x -row [expr {$ligne + $i / $ncol}] -column [expr {$i % $ncol}] -columnspan [expr {$double ? 2 : 1}] \
        -padx {12 0} -pady {12 0} -sticky nsew
    if {$double} {
      foreach l $ls { if {[winfo class $l] eq "Label"} { catch {$l configure -wraplength [expr {$ld - 26}]} } }
    }
    if {[winfo exists $x.img]} { couverture $x [expr {$double ? $ld - 2 : $lc - 2}] }
    incr i [expr {$double ? 2 : 1}]
  }
  set ligne [expr {$ligne + ($i + $ncol - 1) / $ncol}]
  if {[winfo exists $g.tAutres]} {
    grid $g.tAutres -row $ligne -column 0 -columnspan $ncol -sticky w -padx 12 -pady {20 0}
    incr ligne
  }
  set premiere 1
  # (the rows' height: their content measured first)
  update idletasks
  # same column widths on every row (the name takes what is left), so the
  # rows line up
  set lignes {}
  foreach x [winfo children $g] {
    if {[winfo class $x] eq "Frame" && [string match l* [winfo name $x]]} { lappend lignes $x }
  }
  foreach col {2 3 4} { set max($col) 0 }
  foreach x $lignes {
    foreach {col nm} {2 lieu 3 etat 4 cad} {
      set max($col) [expr {max($max($col), [winfo reqwidth $x.k.$nm])}]
    }
  }
  foreach x $lignes {
    foreach col {2 3 4} { grid columnconfigure $x.k $col -minsize [expr {$max($col) + 14}] }
  }
  foreach x [winfo children $g] {
    if {[winfo class $x] ne "Frame" || ![string match l* [winfo name $x]]} { continue }
    pack propagate $x 0
    $x configure -width [expr {min($larg - 24, $ncol * ($lc + 12) - 12)}] -height [winfo reqheight $x.k]
    grid $x -row $ligne -column 0 -columnspan $ncol -sticky w -padx {12 0} -pady [expr {$premiere ? {10 0} : {2 0}}]
    set premiere 0
    incr ligne
  }
  if {[winfo exists $g.vide]} { grid $g.vide -row 0 -column 0 -padx 12 -pady 12 -sticky w }
  if {[winfo exists $g.plus]} {
    grid $g.plus -row $ligne -column 0 -padx 12 -pady 12 -sticky w
  }
  for {set k 0} {$k < 8} {incr k} {
    grid columnconfigure $g $k -minsize [expr {$k < $ncol ? $lc : 0}] -weight 0 -uniform [expr {$k < $ncol ? "c" : ""}]
  }
  $c itemconfigure g -width $larg
  update idletasks
  $c configure -scrollregion [list 0 0 $larg [expr {[winfo reqheight $g] + 12}]]
}

################################################################################
### Tournament, sections, rounds
################################################################################

proc ::moderne::direct::tourChoisi {} {
  variable w
  variable silence
  if {$silence} { return }
  set id [lindex [$w.f.pw.g.l.t selection] 0]
  # a player found in the ongoing tournaments: their tournament, the
  # players and games filtered on them
  variable trouves
  if {[info exists trouves($id)]} {
    lassign $trouves($id) idTour nom
    set ::moderne::direct::filtre $nom
    set ::moderne::direct::vue parties
    basculerVue
    chargerTour $idTour
    return
  }
  variable tour
  variable ordre
  # (selection given back by the return from the game view)
  if {$id eq [::moderne::json::get $tour tour id {}] && [llength $ordre]} { return }
  if {$id ne {}} { chargerTour $id }
}

proc ::moderne::direct::chargerTour {id} {
  variable api
  etat [T "Chargement du tournoi…" "Loading the tournament…"]
  # (Lichess asked to slow down: said, rather than a click that seems lost)
  variable lichessPause
  set reste [expr {([info exists lichessPause] ? $lichessPause : 0) - [clock milliseconds]}]
  if {$reste > 1000} {
    set s [expr {($reste + 999) / 1000}]
    etat [T "Lichess demande de ralentir : le tournoi s'ouvre dans $s s." "Lichess asks to slow down: the tournament opens in $s s."]
  }
  lireJson "$api/api/broadcast/$id" ::moderne::direct::tourRecu
}

proc ::moderne::direct::tourRecu {v} {
  variable tour
  variable w
  if {![actif]} { return }
  if {$v eq {}} { etat [messageErreur [T "Tournoi introuvable." "Tournament not found."]] ; return }
  set tour $v
  if {[winfo exists $w]} {
    masquerAccueil
    afficherTour 1
    rondeChoisie
  } else {
    # (another section chosen from the live panel: its current round)
    lassign [rondeDefaut $v] rid enCours
    if {$rid ne {}} { chargerRonde $rid $enCours }
  }
  majPanneauRondes
  chargerJoueursTour [::moderne::json::get $tour tour id {}]
}

################################################################################
### Players of the tournament, search
################################################################################

proc ::moderne::direct::chargerJoueursTour {id} {
  variable api
  variable joueurs {}
  afficherJoueurs
  if {$id eq {}} { return }
  lireJson "$api/broadcast/$id/players" [list ::moderne::direct::joueursRecus $id]
}

proc ::moderne::direct::joueursRecus {id v} {
  variable tour
  variable joueurs
  if {[::moderne::json::get $tour tour id {}] ne $id} { return }
  # (a list of players; an error answer is a dict)
  set joueurs {}
  if {![catch {::moderne::json::get [lindex $v 0] name {}} n] && $n ne {}} { set joueurs $v }
  afficherJoueurs
}

### "Player" search: the players of every ongoing tournament are read (a
### few at a time) and the ones matching the search are listed on the left
proc ::moderne::direct::chercherJoueur {} {
  variable recherche
  variable api
  variable w
  variable rechJ
  if {[string trim $recherche] eq {}} { return }
  set rechJ(q) [string trim $recherche]
  set rechJ(n) [incr rechJ(serie)]
  variable trouves
  array unset trouves
  catch {$w.f.pw.g.l.t delete [$w.f.pw.g.l.t children {}]}
  set ::moderne::direct::onglet joueur
  afficherAccueil
  etat [T "Recherche de « $rechJ(q) » dans les tournois en cours…" "Looking for \"$rechJ(q)\" in the ongoing tournaments…"]
  lireJson "$api/api/broadcast/top?page=1" [list ::moderne::direct::toursPourJoueur $rechJ(n)]
}

proc ::moderne::direct::toursPourJoueur {serie v} {
  variable rechJ
  if {$serie != $rechJ(n)} { return }
  set rechJ(file) {}
  if {$v eq {}} { etat [messageErreur] ; return }
  foreach t [::moderne::json::get $v active {}] {
    set id [::moderne::json::get $t tour id {}]
    if {$id ne {}} { lappend rechJ(file) [list $id [::moderne::json::get $t tour name {}]] }
  }
  set rechJ(total) [llength $rechJ(file)]
  set rechJ(lus) 0
  set rechJ(trouves) 0
  set rechJ(enCours) 0
  # (6 tournaments at a time)
  for {set k 0} {$k < 6} {incr k} { joueursSuivants $serie }
}

proc ::moderne::direct::joueursSuivants {serie} {
  variable rechJ
  variable api
  if {$serie != $rechJ(n)} { return }
  if {![llength $rechJ(file)]} {
    if {!$rechJ(enCours)} {
      etat [expr {$rechJ(trouves) ? [T "$rechJ(trouves) résultat(s) dans $rechJ(total) tournois en cours." "$rechJ(trouves) result(s) in $rechJ(total) ongoing tournaments."] \
          : [T "Personne de ce nom dans les $rechJ(total) tournois en cours." "Nobody of that name in the $rechJ(total) ongoing tournaments."]}]
    }
    return
  }
  lassign [lindex $rechJ(file) 0] id nom
  set rechJ(file) [lrange $rechJ(file) 1 end]
  incr rechJ(enCours)
  lireJson "$api/broadcast/$id/players" [list ::moderne::direct::joueursDuTour $serie $id $nom]
}

proc ::moderne::direct::joueursDuTour {serie id nomTour v} {
  variable rechJ
  variable w
  variable trouves
  if {$serie != $rechJ(n) || ![winfo exists $w]} { return }
  incr rechJ(enCours) -1
  incr rechJ(lus)
  set t $w.f.pw.g.l.t
  if {![catch {::moderne::json::get [lindex $v 0] name {}} n] && $n ne {}} {
    foreach j $v {
      set nom [::moderne::json::get $j name {}]
      set titre [::moderne::json::get $j title {}]
      if {![correspondTexte $rechJ(q) "$titre $nom [::moderne::json::get $j fed {}]"]} { continue }
      set cle [format jr%04d [incr rechJ(trouves)]]
      set sc [::moderne::json::get $j score {}]
      set info [::moderne::json::get $j rating {}]
      if {$sc ne {}} { append info "  •  [demi $sc] / [::moderne::json::get $j played {}]" }
      set trouves($cle) [list $id $nom $titre $nomTour $info]
      catch {$t insert {} end -id $cle -text "[string trim "$titre $nom"] • $nomTour" -values [list $info]}
    }
    if {[accueilVisible] && $::moderne::direct::onglet eq "joueur"} { remplirCartes }
  }
  etat [T "Recherche de « $rechJ(q) » : $rechJ(lus) / $rechJ(total) tournois…" "Looking for \"$rechJ(q)\": $rechJ(lus) / $rechJ(total) tournaments…"]
  joueursSuivants $serie
}

### Does query q match this text? (every word, accents and case ignored)
proc ::moderne::direct::correspondTexte {q texte} {
  set texte [simple $texte]
  foreach mot [split [simple $q]] {
    if {$mot ne {} && [string first $mot $texte] < 0} { return 0 }
  }
  return 1
}

### Text without accents, lower case (search)
proc ::moderne::direct::simple {t} {
  string tolower [string map {á a à a â a ä a ã a å a ā a ą a ć c č c ç c ď d é e è e ê e ë e ě e ę e ğ g í i ì i î i ï i ı i
    ł l ľ l ń n ň n ñ n ó o ò o ô o ö o õ o ø o ő o ř r ś s š s ş s ș s ť t ț t ú u ù u û u ü u ů u ű u ý y ÿ y ź z ż z ž z
    Á A À A Â A Ä A Ç C Č C É E È E Ê E Í I Î I Ł L Ñ N Ó O Ö O Ø O Ś S Š S Ş S Ú U Ü U Ý Y Ž Z ß ss æ ae œ oe} $t]
}

### Does the search match this text? (every word of the search)
proc ::moderne::direct::correspond {texte} {
  variable filtre
  set q [string trim $filtre]
  if {$q eq {}} { return 1 }
  set texte [simple $texte]
  foreach mot [split [simple $q]] {
    if {$mot ne {} && [string first $mot $texte] < 0} { return 0 }
  }
  return 1
}

proc ::moderne::direct::filtrer {} {
  afficherParties
  afficherJoueurs
}

proc ::moderne::direct::basculerVue {} {
  variable vue
  variable w
  set d $w.f.pw.d
  if {![winfo exists $d.j]} { return }
  pack forget $d.p $d.j
  pack [expr {$vue eq "joueurs" ? "$d.j" : "$d.p"}] -side top -fill both -expand 1 -before $d.b
}

proc ::moderne::direct::afficherJoueurs {} {
  variable joueurs
  variable w
  set t $w.f.pw.d.j.t
  if {![winfo exists $t]} { return }
  $t delete [$t children {}]
  set i 0
  foreach j $joueurs {
    incr i
    set nom [string trim "[::moderne::json::get $j title {}] [::moderne::json::get $j name ?]"]
    set fed [::moderne::json::get $j fed {}]
    set equipe [::moderne::json::get $j team {}]
    if {![correspond "$nom $fed $equipe"]} { continue }
    set sc [::moderne::json::get $j score {}]
    set joue [::moderne::json::get $j played {}]
    set points [expr {$sc eq {} ? {} : "[demi $sc] / $joue"}]
    $t insert {} end -id j$i -values [list [::moderne::json::get $j rank {}] $nom $fed \
        [::moderne::json::get $j rating {}] $equipe $points \
        [::moderne::json::get $j performances standard {}]]
  }
  catch {$w.f.pw.d.v.joueurs configure -state [expr {[llength $joueurs] ? "normal" : "disabled"}]}
}

### Game of a player in the current round (game id, or {})
proc ::moderne::direct::partieDe {nom} {
  variable parties
  variable ordre
  set cible [simple $nom]
  foreach id $ordre {
    foreach c {B N} {
      if {[simple [dict get $parties($id) nom$c]] eq $cible} { return $id }
    }
  }
  return {}
}

### Double click on a player: their game of the round is followed
proc ::moderne::direct::suivreJoueur {} {
  variable joueurs
  variable w
  set t $w.f.pw.d.j.t
  if {![winfo exists $t]} { return }
  set item [lindex [$t selection] 0]
  if {![regexp {^j([0-9]+)$} $item -> i]} { return }
  set nom [::moderne::json::get [lindex $joueurs [expr {$i - 1}]] name {}]
  set id [partieDe $nom]
  if {$id eq {}} {
    etat [T "$nom ne joue pas dans cette ronde." "$nom has no game in this round."]
    return
  }
  suivre $id
}

proc ::moderne::direct::suivreBouton {} {
  variable vue
  if {$vue eq "joueurs"} { suivreJoueur } else { suivreSelection }
}


### Header, sections and rounds of the current tournament; defaut: choose
### the round Lichess suggests (else the current round)
proc ::moderne::direct::afficherTour {{defaut 0}} {
  variable tour
  variable ronde
  variable w
  set v $tour
  set tr [::moderne::json::get $v tour {}]
  set d $w.f.pw.d
  $d.nom configure -text [::moderne::json::get $tr name ?]
  set info {}
  foreach k {format tc location} {
    set x [::moderne::json::get $tr info $k {}]
    if {$x ne {}} { lappend info $x }
  }
  set dt [dates $tr]
  if {$dt ne {}} { lappend info $dt }
  $d.info configure -text [join $info "  •  "]
  # sections of the group (Open, Women...)
  set sec [::moderne::json::get $v group tours {}]
  if {[llength $sec] > 1} {
    set noms {}
    set courant {}
    foreach s $sec {
      lappend noms [::moderne::json::get $s name ?]
      if {[::moderne::json::get $s id {}] eq [::moderne::json::get $tr id {}]} { set courant [::moderne::json::get $s name ?] }
    }
    $d.s.sec configure -values $noms
    $d.s.sec set $courant
    pack $d.s.lsec $d.s.sec -side left -padx {0 6}
  } else {
    pack forget $d.s.lsec $d.s.sec
  }
  # rounds
  set noms {}
  set defautId [lindex [rondeDefaut $v] 0]
  set choix {}
  foreach r [::moderne::json::get $v rounds {}] {
    set n [::moderne::json::get $r name ?]
    if {[::moderne::json::get $r ongoing 0]} {
      set n "● $n ([T "en cours" "live"])"
    } elseif {[::moderne::json::get $r finished 0]} {
      set n "✓ $n"
    } else {
      set debut [::moderne::json::get $r startsAt {}]
      if {$debut ne {}} { append n "  ([debutRonde $debut])" }
    }
    lappend noms $n
    set rid [::moderne::json::get $r id {}]
    if {(!$defaut && $rid eq $ronde) || ($defaut && $rid eq $defautId)} { set choix $n }
  }
  $d.s.r configure -values $noms
  if {$choix eq {} && [llength $noms]} { set choix [lindex $noms end] }
  $d.s.r set $choix
  pack $d.s.lr $d.s.r -side left -padx {0 6}
}

proc ::moderne::direct::sectionChoisie {} {
  variable tour
  variable w
  set nom [$w.f.pw.d.s.sec get]
  foreach s [::moderne::json::get $tour group tours {}] {
    if {[::moderne::json::get $s name {}] eq $nom} { chargerTour [::moderne::json::get $s id {}] ; return }
  }
}

proc ::moderne::direct::rondeChoisie {} {
  variable tour
  variable w
  set i [$w.f.pw.d.s.r current]
  set r [lindex [::moderne::json::get $tour rounds {}] $i]
  set id [::moderne::json::get $r id {}]
  if {$id eq {}} { return }
  chargerRonde $id [::moderne::json::get $r ongoing 0]
}

################################################################################
### Games of a round
################################################################################

proc ::moderne::direct::chargerRonde {id enCours} {
  variable ronde
  variable rondeEnCours
  variable api
  variable parties
  variable ordre
  arreterFlux
  set ronde $id
  set rondeEnCours $enCours
  array unset parties
  set ordre {}
  etat [T "Chargement de la ronde…" "Loading the round…"]
  lireJson "$api/api/broadcast/-/-/$id" [list ::moderne::direct::rondeRecue $id]
}

proc ::moderne::direct::rondeRecue {id v} {
  variable ronde
  variable parties
  variable ordre
  variable w
  if {![actif] || $id ne $ronde} { return }
  if {$v eq {}} { etat [messageErreur [T "Ronde introuvable." "Round not found."]] ; return }
  # (the same round may have been asked twice: start again from scratch)
  array unset parties
  set ordre {}
  set i 0
  foreach g [::moderne::json::get $v games {}] {
    incr i
    set gid [::moderne::json::get $g id {}]
    lassign [::moderne::json::get $g players {}] pb pn
    set p [dict create n $i res [::moderne::json::get $g status *] pgn {} plies 0 clkB {} clkN {}]
    foreach {cote j} [list B $pb N $pn] {
      dict set p nom$cote [::moderne::json::get $j name ?]
      dict set p titre$cote [::moderne::json::get $j title {}]
      dict set p elo$cote [::moderne::json::get $j rating {}]
      dict set p equipe$cote [::moderne::json::get $j team {}]
      set c [::moderne::json::get $j clock {}]
      if {$c ne {}} { dict set p clk$cote [hms [expr {$c / 100}]] }
    }
    set parties($gid) $p
    # time of the last move (Lichess: seconds of thought of the player to
    # move): the clock of the side to move runs from there, like on Lichess
    variable recu
    set reflexion [::moderne::json::get $g thinkTime {}]
    if {[string is integer -strict $reflexion] && [dict get $p res] eq "*"} {
      set recu($gid) [expr {[clock seconds] - $reflexion}]
    } else {
      catch {unset recu($gid)}
    }
    lappend ordre $gid
  }
  afficherParties
  majPanneauRondes
  demarrerFlux
  # (a game chosen on a player card, in another round)
  variable aSuivre
  if {$aSuivre ne {} && [info exists parties($aSuivre)]} {
    after idle [list ::moderne::direct::suivre $aSuivre]
  }
  set aSuivre {}
}

proc ::moderne::direct::hms {s} {
  if {![string is integer -strict $s]} { return {} }
  set h [expr {$s / 3600}]
  set m [expr {($s % 3600) / 60}]
  set sec [expr {$s % 60}]
  if {$h} { return [format "%d:%02d:%02d" $h $m $sec] }
  return [format "%d:%02d" $m $sec]
}

### Titles shown: from the FIDE data when the player is known there (open
### and women's titles, see ::moderne::fide::titres), else the game's
proc ::moderne::direct::titreJoueur {p cote} {
  set t [dict get $p titre$cote]
  if {[dict exists $p fide$cote]} { catch {set t [::moderne::fide::titresJoueur [dict get $p fide$cote] $t]} }
  return $t
}

proc ::moderne::direct::nomJoueur {p cote} {
  set t [titreJoueur $p $cote]
  return [string trim "$t [dict get $p nom$cote]"]
}

proc ::moderne::direct::texteRes {r} {
  switch -- $r {
    1-0 { return "1 – 0" }
    0-1 { return "0 – 1" }
    1/2-1/2 { return "½ – ½" }
  }
  return "*"
}

proc ::moderne::direct::valeursPartie {p} {
  set enCours [expr {[dict get $p res] eq "*"}]
  set etat {}
  set cb [dict get $p clkB] ; set cn [dict get $p clkN]
  if {$cb ne {}} { set cb [hms [secondes $cb]] }
  if {$cn ne {}} { set cn [hms [secondes $cn]] }
  if {$enCours && $cb ne {}} { set etat "$cb | $cn" }
  if {$enCours && [dict get $p plies] > 0} { append etat "  • [T coup move] [expr {([dict get $p plies] + 1) / 2}]" }
  return [list [dict get $p n] [nomJoueur $p B] [dict get $p eloB] [texteRes [dict get $p res]] \
      [nomJoueur $p N] [dict get $p eloN] [string trim $etat]]
}

### Team events: one row per match (team A – team B, score), boards below
proc ::moderne::direct::afficherParties {} {
  variable parties
  variable ordre
  variable w
  majPanneauListe
  set t $w.f.pw.d.p.t
  if {![winfo exists $t]} { return }
  $t delete [$t children {}]
  set equipes 0
  foreach id $ordre { if {[dict get $parties($id) equipeB] ne {}} { set equipes 1 ; break } }
  if {$equipes} {
    $t configure -show {tree headings}
    $t column #0 -width 24 -stretch 0
    foreach id $ordre {
      set p $parties($id)
      if {![correspond "[nomJoueur $p B] [nomJoueur $p N] [dict get $p equipeB] [dict get $p equipeN]"]} { continue }
      set cle [list [dict get $p equipeB] [dict get $p equipeN]]
      set inv [list [dict get $p equipeN] [dict get $p equipeB]]
      if {[info exists match($inv)]} { set cle $inv }
      if {![info exists match($cle)]} {
        set match($cle) "m[array size match]"
        $t insert {} end -id $match($cle) -open 1 -tags match
      }
      $t insert $match($cle) end -id $id -values [valeursPartie $p] \
          -tags [expr {[dict get $p res] eq "*" ? "enCours" : ""}]
    }
    foreach cle [array names match] { scoreMatch $match($cle) $cle }
  } else {
    $t configure -show headings
    foreach id $ordre {
      set p $parties($id)
      if {![correspond "[nomJoueur $p B] [nomJoueur $p N]"]} { continue }
      $t insert {} end -id $id -values [valeursPartie $p] -tags [expr {[dict get $p res] eq "*" ? "enCours" : ""}]
    }
  }
  set n [llength $ordre]
  set fini 0
  foreach id $ordre { if {[dict get $parties($id) res] ne "*"} { incr fini } }
  etat "$n [T parties games] • [expr {$n - $fini}] [T "en cours" "ongoing"]"
}

### Match row: score of the first team (it may have White or Black)
proc ::moderne::direct::scoreMatch {m cle {t {}}} {
  variable parties
  variable w
  if {$t eq {}} { set t $w.f.pw.d.p.t }
  lassign $cle a b
  set sa 0.0 ; set sb 0.0
  foreach id [$t children $m] {
    set p $parties($id)
    set blancA [expr {[dict get $p equipeB] eq $a}]
    switch -- [dict get $p res] {
      1-0 { if {$blancA} { set sa [expr {$sa + 1}] } else { set sb [expr {$sb + 1}] } }
      0-1 { if {$blancA} { set sb [expr {$sb + 1}] } else { set sa [expr {$sa + 1}] } }
      1/2-1/2 { set sa [expr {$sa + 0.5}] ; set sb [expr {$sb + 0.5}] }
    }
  }
  $t item $m -values [list {} $a {} "[demi $sa] – [demi $sb]" $b {} {}]
}

proc ::moderne::direct::demi {x} {
  set e [expr {int($x)}]
  if {$x - $e > 0.1} { return [expr {$e ? "$e½" : "½"}] }
  return $e
}

################################################################################
### Live stream of the round
################################################################################

proc ::moderne::direct::demarrerFlux {} {
  variable ronde
  variable flux
  variable tampon
  variable api
  arreterFlux
  set cmd [list curl -sS -N -A "Siby (live broadcasts)" "$api/api/stream/broadcast/round/$ronde.pgn"]
  if {[catch {open "|$cmd" r} p]} { return }
  set flux $p
  set tampon {}
  variable debutFlux [clock seconds]
  fconfigure $p -translation binary -blocking 0
  fileevent $p readable [list ::moderne::direct::morceauFlux $p $ronde]
}

proc ::moderne::direct::arreterFlux {} {
  variable flux
  if {$flux eq {}} { return }
  set p $flux
  set flux {}
  catch {fileevent $p readable {}}
  # (curl keeps the connection open: kill it before closing)
  foreach pid [pid $p] {
    if {$::windowsOS} { catch {exec taskkill /F /PID $pid} } else { catch {exec kill $pid} }
  }
  catch {close $p}
}

proc ::moderne::direct::morceauFlux {p id} {
  variable flux
  variable tampon
  variable ronde
  variable rondeEnCours
  variable w
  if {$p ne $flux} { catch {close $p} ; return }
  # no broadcast window left (another layout): stop the stream
  if {![actif]} { arreterFlux ; return }
  append tampon [read $p]
  # one game = its whole PGN, followed by 3 newlines
  while {[set i [string first "\n\n\n" $tampon]] >= 0} {
    set pgn [encoding convertfrom utf-8 [string range $tampon 0 $i]]
    set tampon [string range $tampon [expr {$i + 3}] end]
    if {[string trim $pgn] ne {}} { catch {pgnRecu [string trim $pgn]} }
  }
  if {[eof $p]} {
    set flux {}
    catch {close $p}
    # ongoing round: reconnect
    if {$rondeEnCours && [actif] && $id eq $ronde} {
      # (a stream that ends at once: Lichess or the connection is down)
      variable debutFlux
      if {[info exists debutFlux] && [clock seconds] - $debutFlux < 10} {
        etat [T "Direct interrompu (Lichess ou connexion) : reconnexion…" "Live stream interrupted (Lichess or connection): reconnecting…"]
      }
      after 5000 [list ::moderne::direct::reprendre $id]
    }
  }
}

proc ::moderne::direct::reprendre {id} {
  variable ronde
  variable flux
  variable w
  if {[actif] && $id eq $ronde && $flux eq {}} { demarrerFlux }
}

proc ::moderne::direct::tag {pgn nom} {
  if {[regexp "\\\[$nom \"(\[^\"\]*)\"\\\]" $pgn -> v]} { return $v }
  return {}
}

### A game received from the stream (its whole PGN)
proc ::moderne::direct::pgnRecu {pgn} {
  variable parties
  variable ordre
  variable suivie
  variable w
  set url [tag $pgn GameURL]
  set id [lindex [split $url /] end]
  if {$id eq {}} { return }
  if {![info exists parties($id)]} {
    set parties($id) [dict create n [expr {[llength $ordre] + 1}] nomB [tag $pgn White] nomN [tag $pgn Black] \
        titreB [tag $pgn WhiteTitle] titreN [tag $pgn BlackTitle] eloB [tag $pgn WhiteElo] eloN [tag $pgn BlackElo] \
        fideB [tag $pgn WhiteFideId] fideN [tag $pgn BlackFideId] \
        equipeB [tag $pgn WhiteTeam] equipeN [tag $pgn BlackTeam] clkB {} clkN {} plies 0]
    lappend ordre $id
    set nouvelle 1
  }
  set p $parties($id)
  set avant [dict get $p plies]
  dict set p res [tag $pgn Result]
  dict set p pgn $pgn
  # clocks: one [%clk] per move, the last ones are those of each side
  set clks [regexp -all -inline {\[%clk ([0-9:]+)\]} $pgn]
  set c {}
  foreach {- x} $clks { lappend c $x }
  set n [llength $c]
  dict set p plies $n
  if {$n >= 1} {
    set dernier [lindex $c end]
    set avant [expr {$n >= 2 ? [lindex $c end-1] : {}}]
    if {$n % 2} { dict set p clkB $dernier ; if {$avant ne {}} { dict set p clkN $avant } } \
    else { dict set p clkN $dernier ; dict set p clkB $avant }
  }
  set parties($id) $p
  variable recu
  # a new move: its clock starts now (the first reception keeps the time
  # given by Lichess with the round)
  if {![info exists recu($id)] || ($avant > 0 && [dict get $p plies] > $avant)} {
    set recu($id) [clock seconds]
  }
  if {$id eq $suivie} { majPartieSuivie }
  majPanneauListe
  set t $w.f.pw.d.p.t
  if {![winfo exists $t]} { return }
  if {[info exists nouvelle] || ![$t exists $id]} {
    afficherParties
  } else {
    $t item $id -values [valeursPartie $p] -tags [expr {[dict get $p res] eq "*" ? "enCours" : ""}]
    set m [$t parent $id]
    if {$m ne {}} {
      scoreMatch $m [list [lindex [$t item $m -values] 1] [lindex [$t item $m -values] 4]]
    }
  }
}

################################################################################
### Following a game on the main board
################################################################################

### PGN without the Lichess comments (computer evaluations, clocks) and
### annotation symbols: the moves only, Siby's engines do the analysis
proc ::moderne::direct::pgnPropre {pgn} {
  set i [string first "\n\n" $pgn]
  set tags [string range $pgn 0 $i]
  set coups [string range $pgn $i end]
  regsub -all {\{[^{}]*\}} $coups { } coups
  regsub -all {\$[0-9]+} $coups { } coups
  regsub -all {([a-hRNBQKO1-8+#=])[?!]+} $coups {\1} coups
  regsub -all {[0-9]+\.\.\.} $coups { } coups
  regsub -all {\s+} $coups { } coups
  return "$tags\n[string trim $coups]\n"
}

proc ::moderne::direct::baseLive {} {
  set fichier [file normalize [file join $::sibyDocsDir "Siby live"]]
  for {set i 1} {$i <= [sc_base count total]} {incr i} {
    if {[sc_base inUse $i] && [file normalize [sc_base filename $i]] eq $fichier} { return $i }
  }
  set courante [sc_base current]
  if {[file exists $fichier.si4]} {
    set b [sc_base open $fichier]
  } else {
    set b [sc_base create $fichier]
  }
  sc_base switch $courante
  catch {::windows::switcher::Refresh}
  return $b
}

proc ::moderne::direct::suivreSelection {{t {}}} {
  variable w
  variable parties
  if {$t eq {}} { set t $w.f.pw.d.p.t }
  if {![winfo exists $t]} { return }
  set id [lindex [$t selection] 0]
  if {$id eq {} || ![info exists parties($id)]} { return }
  suivre $id
}

### Main line (SAN) of a PGN
proc ::moderne::direct::coupsDe {pgn} {
  set i [string first "\n\n" $pgn]
  set texte [string range $pgn $i end]
  regsub -all {\{[^{}]*\}} $texte { } texte
  regsub -all {\([^()]*\)} $texte { } texte
  set l {}
  foreach x $texte {
    regsub {^[0-9]+\.+} $x {} x
    regsub {[?!]+$} $x {} x
    if {$x eq {} || [string match {$*} $x] || $x in {1-0 0-1 1/2-1/2 *}} { continue }
    lappend l $x
  }
  return $l
}

### Number of the game in "Siby live" (found again by its Lichess address)
proc ::moderne::direct::numeroLive {id} {
  variable numLive
  variable parties
  set b [baseLive]
  if {[info exists numLive($id)] && $numLive($id) <= [sc_base numGames $b]} { return $numLive($id) }
  set url [tag [dict get $parties($id) pgn] GameURL]
  if {$url eq {}} { return 0 }
  set n 0
  set connues [adressesBase $b]
  if {[dict exists $connues $url]} { set n [dict get $connues $url] }
  if {$n} { set numLive($id) $n }
  return $n
}

### Follows game id: it goes into "Siby live" and on the board; in
### single-window mode, the game view replaces the broadcast view
proc ::moderne::direct::suivre {id} {
  variable parties
  variable suivie
  variable numLive
  variable coupsLive
  variable nouveaux
  variable panneau
  # (a game of a round left in between: nothing to follow)
  if {![info exists parties($id)]} { return }
  set p $parties($id)
  if {[dict get $p pgn] eq {}} {
    # game not started yet (or moves not received): the players only, the
    # moves will come with the stream
    set tags {}
    foreach {tag cle} {White nomB Black nomN WhiteElo eloB BlackElo eloN WhiteTitle titreB BlackTitle titreN} {
      if {[dict get $p $cle] ne {}} { append tags "\[$tag \"[dict get $p $cle]\"\]\n" }
    }
    append tags "\[Site \"https://lichess.org/broadcast/-/-/[set ::moderne::direct::ronde]/$id\"\]\n"
    append tags "\[GameURL \"https://lichess.org/broadcast/-/-/[set ::moderne::direct::ronde]/$id\"\]\n"
    dict set p pgn "$tags\[Result \"*\"\]\n\n*"
    set parties($id) $p
  }
  variable chronoT [list debut [clock milliseconds]]
  # (a game against an engine in progress: refused, as everywhere else; it
  # was replaced by the broadcast game, which then sat in two tabs, monkey
  # test 2026-11-11; a finished one is closed by occupe)
  if {[winfo exists .serGameWin] || ([info exists ::moderne::alterego::actif] && $::moderne::alterego::actif)} {
    set r [::moderne::onglets::occupe]
    if {$r ne {}} { ::moderne::onglets::refuser $r ; return }
  }
  # (the game already in a tab, left for another game opened meanwhile:
  # that tab, not a second copy, Yosha 2026-11-11)
  if {[info exists numLive($id)]} {
    catch {
      set t [::moderne::onglets::ongletDe [baseLive] $numLive($id)]
      if {$t ne {} && $t ne $::moderne::onglets::actif} { ::moderne::onglets::activer $t }
    }
  }
  # (a game that would ask to be saved: it stays in its tab, the broadcast
  # game opens in a new one, no question; Yosha 2026-11-07)
  if {[::game::demanderait]} {
    if {![::moderne::onglets::nouveau]} { return }
  } else {
    set confirm [::game::ConfirmDiscard]
    if {$confirm == 2} { return }
    if {$confirm == 0} { ::game::Save }
  }
  chrono question
  set b [baseLive]
  set pgn [pgnPropre [dict get $p pgn]]
  set n [numeroLive $id]
  sc_base switch $b
  sc_game new
  sc_game import $pgn
  if {$n} {
    sc_game save $n
  } else {
    sc_game save 0
    set n [sc_base numGames $b]
  }
  set numLive($id) $n
  set suivie $id
  variable derniere $id
  set coupsLive [coupsDe $pgn]
  set nouveaux 0
  chrono base
  ::game::Load $n
  sc_move end
  chrono chargement
  updateBoard -pgn
  chrono echiquier
  catch {::windows::gamelist::Refresh}
  catch {::windows::switcher::Refresh}
  chrono listes
  # (the game view on screen, else laid again: hidden under the Lab after a
  # game against an engine, its panel still counted as open and the view
  # did not come back, Yosha 2026-11-11; laid already, vuePartie returns at
  # once)
  variable superpose
  if {[docking] && ![aLEcran $panneau] && !($superpose eq "partie" && [winfo exists .directCouvre] && [winfo viewable .directCouvre])} {
    vuePartie
  } else {
    majPanneau
  }
  # (the followed game in bold in the list: it stayed on the previous one
  # until the next move came, Yosha 2026-11-11)
  catch majPanneauListe
  chrono vue
  catch {chargerJoueurs}
  chrono joueurs
  etat "[T "Partie suivie : " "Following: "][nomJoueur $p B] – [nomJoueur $p N]"
  # (the screen drawn, then the times written if it was slow)
  after idle {after 0 {::moderne::direct::chrono affichage ; ::moderne::direct::chronoFin}}
}

### Opening a game's steps timed: written to "lenteurs.log" (Siby's
### folder) when the whole took more than 2 s, to find what is slow
proc ::moderne::direct::chrono {etape} {
  variable chronoT
  if {[info exists chronoT]} { lappend chronoT $etape [clock milliseconds] }
}

### While a broadcast game opens: the calls slower than 300 ms, kept for
### lenteurs.log (the "view" step took 18 s on Windows, 2026-10-29, not on
### Linux): which one is slow
namespace eval ::moderne::direct {
  variable lents {}
  variable pileLents {}
}
proc ::moderne::direct::espionner {} {
  foreach p {::makeAnalysisWin ::finirAnalysisWin ::uci::sendUCIoptions ::moderne::moteur::optionsDepart
             ::moderne::disposition::appliquer ::docking::layout_restore ::createToplevel ::updateBoard
             ::moderne::direct::chargerJoueurs ::moderne::direct::majPanneau ::moderne::direct::vuePartie
             ::moderne::biblio::maj ::moderne::biblio::suivre ::moderne::toby::ombre::maj ::moderne::moteur::apparence
             ::moderne::docks::prelancer ::moderne::disposition::demarrer ::toggleEngineAnalysis ::startAnalyzeMode
             ::moderne::horloges::maj ::moderne::barres::redessiner ::windows::gamelist::Refresh ::moderne::docks::finVoile
             ::moderne::direct::majJoueurs ::moderne::direct::lireJoueur ::moderne::direct::lirePartiesJoueur
             ::moderne::direct::lirePaquet ::moderne::biblio::chercherIci ::moderne::biblio::statsIci
             ::moderne::biblio::statsPlusieurs ::moderne::biblio::remplirMeilleures ::moderne::biblio::ouvrir
             ::moderne::syzygy::maj ::moderne::gaby::grandeSuivi ::moderne::gaby::verifier ::moderne::mesbases::baseReference
             ::docking::add_tab ::moderne::direct::ouvrirJoueurs ::moderne::syzygy::ouvrir} {
    if {![llength [info commands $p]]} { continue }
    catch {trace add execution $p enter [list ::moderne::direct::espionEntree $p]}
    catch {trace add execution $p leave [list ::moderne::direct::espionSortie $p]}
  }
}
proc ::moderne::direct::espionEntree {p args} {
  variable chronoT
  variable pileLents
  if {![info exists chronoT]} { return }
  lappend pileLents [clock milliseconds]
}
proc ::moderne::direct::espionSortie {p args} {
  variable chronoT
  variable pileLents
  variable lents
  if {![info exists chronoT] || ![llength $pileLents]} { set pileLents {} ; return }
  set t0 [lindex $pileLents end]
  set pileLents [lrange $pileLents 0 end-1]
  set d [expr {[clock milliseconds] - $t0}]
  if {$d >= 300} { lappend lents "[string repeat {  } [llength $pileLents]][namespace tail $p] $d" }
}
after 4000 {catch ::moderne::direct::espionner}

proc ::moderne::direct::chronoFin {} {
  variable chronoT
  variable lents
  variable pileLents {}
  set detail $lents
  set lents {}
  if {![info exists chronoT] || [llength $chronoT] < 4} { return }
  set t0 [lindex $chronoT 1]
  set total [expr {[lindex $chronoT end] - $t0}]
  set l {} ; set avant $t0
  foreach {e t} [lrange $chronoT 2 end] { lappend l "$e [expr {$t - $avant}]" ; set avant $t }
  unset chronoT
  variable seuilLent
  if {![info exists seuilLent]} { set seuilLent 2000 }
  if {$total < $seuilLent} { return }
  catch {
    set f [open [file join $::scidUserDir lenteurs.log] a]
    puts $f "[clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}] open a broadcast game: $total ms ([join $l {, }])"
    if {[llength $detail]} { puts $f "    slow calls (ms, innermost first): [join $detail { | }]" }
    close $f
  }
}

### Time left (seconds) to the side to move in the followed game, at the
### position on the board ([%clk] of their last move), or {}
proc ::moderne::direct::tempsRestant {} {
  variable suivie
  variable parties
  if {![surLaPartie] || [sc_var level] > 0} { return {} }
  set c {}
  foreach {- x} [regexp -all -inline {\[%clk ([0-9:]+)\]} [dict get $parties($suivie) pgn]] { lappend c $x }
  set p [sc_pos location]
  if {$p < 2 || $p - 2 >= [llength $c]} { return {} }
  return [secondes [lindex $c [expr {$p - 2}]]]
}

### Is the board on the followed game?
proc ::moderne::direct::surLaPartie {} {
  variable suivie
  variable numLive
  if {$suivie eq {} || ![info exists numLive($suivie)]} { return 0 }
  expr {[sc_base current] == [baseLive] && [sc_game number] == $numLive($suivie)}
}

### At the last move of the main line (= "live")?
proc ::moderne::direct::auDirect {} {
  expr {[sc_var level] == 0 && [sc_pos isAt end]}
}

### New moves of the followed game. On the board: they are added at the
### end of the main line; the user's variations and position are kept,
### the board follows only if it was at the last move (like Lichess).
proc ::moderne::direct::majPartieSuivie {} {
  variable suivie
  variable parties
  variable numLive
  variable coupsLive
  variable nouveaux
  if {![info exists numLive($suivie)]} { return }
  set b [baseLive]
  set n $numLive($suivie)
  set pgn [pgnPropre [dict get $parties($suivie) pgn]]
  set coups [coupsDe $pgn]
  set res [dict get $parties($suivie) res]
  # end of the followed game: said once
  variable finAnnoncee
  if {$res ne "*" && (![info exists finAnnoncee] || $finAnnoncee ne $suivie)} {
    set finAnnoncee $suivie
    set p $parties($suivie)
    annonceBreve "[T "Partie terminée : " "Game over: "][nomJoueur $p B] – [nomJoueur $p N]  [texteRes $res]"
  }
  set k [llength $coupsLive]
  set prolonge [expr {[llength $coups] >= $k && [lrange $coups 0 [expr {$k - 1}]] eq $coupsLive}]
  if {[surLaPartie] && $prolonge} {
    set direct [auDirect]
    set offset [sc_pos pgnOffset]
    while {[sc_var level] > 0} { sc_var exit }
    sc_move end
    set ajoutes 0
    foreach m [lrange $coups $k end] {
      if {[catch {sc_move addSan $m}]} { break }
      incr ajoutes
    }
    set coupsLive [lrange $coups 0 [expr {$k + $ajoutes - 1}]]
    if {$res ne "*"} { catch {sc_game tags set -result $res} }
    catch {completerEnTetes $pgn}
    catch {sc_game save $n}
    if {$direct} {
      sc_move end
      set nouveaux 0
    } else {
      catch {sc_move pgn $offset}
      incr nouveaux $ajoutes
    }
    updateBoard -pgn
  } elseif {[surLaPartie]} {
    # (correction of an earlier move by the broadcast: the game is replaced)
    sc_game new
    sc_game import $pgn
    sc_game save $n
    sc_game load $n
    sc_move end
    set coupsLive $coups
    set nouveaux 0
    updateBoard -pgn
  } else {
    # (the user is elsewhere, maybe on another game of "Siby live" with
    # unsaved changes: that game is set aside meanwhile and comes back as
    # it was, position included)
    set courante [sc_base current]
    if {$courante != $b} { sc_base switch $b }
    sc_game push
    set code [catch {
      sc_game import $pgn
      sc_game save $n
    } err]
    sc_game pop
    if {$courante != $b} { sc_base switch $courante }
    if {$code} { error $err }
    set coupsLive $coups
    catch {::windows::gamelist::Refresh}
  }
  majPanneau
}

### The headers of the followed game completed from the stream's PGN: a
### game opened before its PGN came had the players only (Event "?", no
### TimeControl) and kept them while its moves were added: Toby took the
### blitz for a classical game (Yosha 2026-11-11, Carlsen - Giri, Total
### Chess). Siby's own headers (the review's levels) are kept.
proc ::moderne::direct::completerEnTetes {pgn} {
  set recus {}
  foreach {- t v} [regexp -all -inline {\[(\w+) "([^"]*)"\]} [string range $pgn 0 [string first "\n\n" $pgn]]] {
    dict set recus $t $v
  }
  if {![dict exists $recus TimeControl] && ![dict exists $recus Event]} { return }
  set change 0
  foreach {t opt} {Event -event Site -site Date -date Round -round WhiteElo -whiteElo BlackElo -blackElo ECO -eco} {
    if {![dict exists $recus $t]} { continue }
    set v [dict get $recus $t]
    if {$v ne {} && $v ne [sc_game tags get $t]} { sc_game tags set $opt $v ; set change 1 }
    dict unset recus $t
  }
  foreach t {White Black Result} { dict unset recus $t }
  set extra {}
  foreach {t v} [sc_game tags get Extra] { dict set extra $t $v }
  foreach {t v} $recus {
    if {![dict exists $extra $t] || [dict get $extra $t] ne $v} { dict set extra $t $v ; set change 1 }
  }
  if {!$change} { return }
  set l {}
  foreach {t v} $extra { lappend l "$t \"$v\"" }
  sc_game tags set -extra $l
}

### "Back to live": last move of the main line
proc ::moderne::direct::revenirDirect {} {
  variable suivie
  variable nouveaux
  if {![surLaPartie]} {
    if {$suivie ne {}} { suivre $suivie }
    return
  }
  while {[sc_var level] > 0} { sc_var exit }
  sc_move end
  set nouveaux 0
  updateBoard -pgn
  majPanneau
}

### Copy of the game (with the user's analysis) into another database
proc ::moderne::direct::enregistrerDans {b} {
  set pgn [::moderne::pgnAnglais]
  set courante [sc_base current]
  sc_base switch $b
  set code [catch {
    sc_game new
    sc_game import $pgn
    sc_game save 0
  } err]
  sc_base switch $courante
  catch {::windows::switcher::Refresh}
  catch {::windows::gamelist::Refresh}
  if {$code} {
    tk_messageBox -icon error -type ok -title Siby -message $err
    return
  }
  set msg "[T "Partie enregistrée dans" "Game saved in"] [::moderne::nomBase [sc_base filename $b]]"
  annonceBreve $msg
}

### Menu of the databases to save the current game in: "Siby live"
### first for the live game, then the open writable databases
proc ::moderne::direct::menuEnregistrer {m} {
  $m delete 0 end
  set live 0
  if {[surLaPartie]} {
    set live [baseLive]
    $m add command -label "[T "Siby live (base du direct)" "Siby live (live database)"]" \
        -accelerator [T "Ctrl+S" "Ctrl+S"] -command ::moderne::direct::enregistrer
    $m add separator
  }
  set n 0
  for {set i 1} {$i <= [sc_base count total]} {incr i} {
    if {$i == [sc_info clipbase] || $i == $live || ![sc_base inUse $i] || [sc_base isReadOnly $i]} { continue }
    $m add command -label "[T "Copier dans" "Copy to"] [::moderne::nomBase [sc_base filename $i]]" \
        -command [list ::moderne::direct::enregistrerDans $i]
    incr n
  }
  if {!$n} { $m add command -label [T "(aucune autre base ouverte et modifiable)" "(no other open writable database)"] -state disabled }
  $m add command -label [T "Autre base ou fichier PGN…" "Another database or PGN file…"] \
      -command ::moderne::mesbases::enregistrerSous
  # the whole round
  variable ordre
  set nb [llength [partiesRonde]]
  if {$nb > 0} {
    $m add separator
    $m add command -label "[T "Toute la ronde" "The whole round"] ($nb [T parties games]) → Siby live" \
        -command [list ::moderne::direct::enregistrerRonde [baseLive]]
    for {set i 1} {$i <= [sc_base count total]} {incr i} {
      if {$i == [sc_info clipbase] || $i == [baseLive] || ![sc_base inUse $i] || [sc_base isReadOnly $i]} { continue }
      $m add command -label "[T "Toute la ronde" "The whole round"] ($nb [T parties games]) → [::moderne::nomBase [sc_base filename $i]]" \
          -command [list ::moderne::direct::enregistrerRonde $i]
    }
  }
}

### Games of the round that have moves (or at least the players)
proc ::moderne::direct::partiesRonde {} {
  variable ordre
  variable parties
  set l {}
  foreach id $ordre {
    if {[info exists parties($id)] && [dict get $parties($id) pgn] ne {}} { lappend l $id }
  }
  return $l
}

### Lichess address of each game among the last ones of database b
### (GameURL, else Site): dict url -> game number
proc ::moderne::direct::adressesBase {b} {
  set d [dict create]
  set n [sc_base numGames $b]
  if {$n == 0} { return $d }
  foreach r [sc_gaby tags $b [expr {max(1, $n - 20000 + 1)}] $n GameURL Site] {
    lassign $r g url site
    if {$url ne {}} { dict set d $url $g }
    if {$site ne {} && [string match *lichess.org* $site]} { dict set d $site $g }
  }
  return $d
}

### All the games of the round into database b: a game already there
### (same Lichess address) is replaced, the others are added; the game
### followed in "Siby live" keeps the user's analysis (saved as it is)
proc ::moderne::direct::enregistrerRonde {b} {
  variable parties
  variable suivie
  set courante [sc_base current]
  set live [baseLive]
  set ajoutees 0
  set remplacees 0
  # (the followed game, with the user's analysis)
  if {$b == $live && [surLaPartie]} { catch {sc_game save [sc_game number]} }
  set connues [adressesBase $b]
  set nouvelles {}
  set aRemplacer {}
  foreach id [partiesRonde] {
    if {$b == $live && $id eq $suivie} { continue }
    set pgn [pgnPropre [dict get $parties($id) pgn]]
    set n 0
    foreach t {GameURL Site} {
      set url [tag $pgn $t]
      if {$url ne {} && [dict exists $connues $url]} { set n [dict get $connues $url] ; break }
    }
    if {$n} { lappend aRemplacer $n $pgn } else { append nouvelles $pgn "\n\n" }
  }
  sc_base switch $b
  set code [catch {
    # new games: imported straight into the database (the open game is
    # not touched)
    if {$nouvelles ne {}} {
      set avant [sc_base numGames $b]
      sc_base import data $nouvelles
      set ajoutees [expr {[sc_base numGames $b] - $avant}]
    }
    # games already there: replaced through a temporary game, then the
    # open game is put back (with its number)
    if {[llength $aRemplacer]} {
      set num [sc_game number]
      set modifiee [sc_game altered]
      sc_game push
      foreach {n pgn} $aRemplacer {
        sc_game new
        sc_game import $pgn
        sc_game save $n
        incr remplacees
      }
      sc_game pop
      if {$num > 0 && !$modifiee} { catch {sc_game load $num} }
    }
  } err]
  sc_base switch $courante
  catch {::windows::switcher::Refresh}
  catch {::windows::gamelist::Refresh}
  if {$code} {
    tk_messageBox -icon error -type ok -title Siby -message $err
    return
  }
  set total [expr {$ajoutees + $remplacees + ($b == $live && $suivie ne {} ? 1 : 0)}]
  annonceBreve "[T "Ronde enregistrée dans" "Round saved in"] [::moderne::nomBase [sc_base filename $b]][T " : " ": "]$total [T parties games]"
}

### Ctrl+S on the live game: saved in "Siby live" (with the user's
### analysis); 0 when the current game is not the live game
proc ::moderne::direct::enregistrer {} {
  variable suivie
  variable numLive
  if {![surLaPartie]} { return 0 }
  if {[catch {sc_game save $numLive($suivie)} err]} {
    tk_messageBox -icon error -type ok -title Siby -message $err
    return 1
  }
  catch {::windows::gamelist::Refresh}
  annonceBreve "[T "Partie enregistrée dans" "Game saved in"] [file tail [sc_base filename [baseLive]]]"
  return 1
}

### Ctrl+Shift+S / File › Save as…: the live game, the menu (Siby live,
### the open databases, the whole round, another file…); any other game,
### the Save as dialog
proc ::moderne::enregistrerSous {} {
  if {[catch {::moderne::direct::surLaPartie} live] || !$live} {
    ::moderne::mesbases::enregistrerSous
    return
  }
  ::moderne::direct::choisirBase
}

### The live game's menu: the database to save it in (the live one first)
proc ::moderne::direct::choisirBase {{X {}} {Y {}}} {
  set m .menuEnregistrerDans
  catch {destroy $m}
  menu $m -tearoff 0
  menuEnregistrer $m
  if {$X eq {}} { lassign [winfo pointerxy .] X Y }
  tk_popup $m $X $Y [expr {[surLaPartie] ? 0 : {}}]
}

### Short notice at the bottom right (about a second)
proc ::moderne::direct::annonceBreve {msg} {
  if {[catch {::moderne::nsb::annonce $msg -1 ; after 1200 {catch {destroy .annonceNsb}}}]} { etat $msg }
}

### Small bar under the notation while a live game is followed (like
### Lichess): back to live, save; returns the bar (empty: no notation)
proc ::moderne::direct::barreNotation {} {
  set w .pgnWin
  if {![winfo exists $w.text]} { return {} }
  set d $w.live
  if {[winfo exists $d]} { return $d }
  ttk::frame $d -padding {6 4}
  ttk::button $d.direct -command ::moderne::direct::revenirDirect
  # (one width for all its labels, "● Live" to "Back to live  (+99)": the
  # buttons beside it no longer move, they overlapped for a second at each
  # game change while Windows redrew them, Yosha 2026-11-11)
  set l 0
  foreach x [list [T "● En direct" "● Live"] [T "Dernier coup" "Last move"] "[T "Revenir au direct" "Back to live"]  (+99)"] {
    set l [expr {max($l, [string length $x])}]
  }
  $d.direct configure -width $l
  catch {$d.direct configure -style Accent.TButton}
  ttk::menubutton $d.enr -text [T "Enregistrer" "Save"] -menu $d.enr.m
  menu $d.enr.m -tearoff 0 -postcommand [list ::moderne::direct::menuEnregistrer $d.enr.m]
  ttk::button $d.bilan -text [T "Bilan" "Review"] -command ::moderne::bilan::lancer
  catch {::utils::tooltip::Set $d.bilan [T "Bilan de la partie : symboles, variantes critiques, niveau de jeu de chaque joueur·se" \
      "Game review: symbols, critical variations, each player's level of play"]}
  pack $d.direct $d.enr $d.bilan -side left -padx {0 6}
  pack $d -side bottom -fill x -before $w.text
  return $d
}

################################################################################
### Live panel of the game view
################################################################################

proc ::moderne::direct::ouvrirPanneau {} {
  variable panneau
  set w $panneau
  if {[winfo exists $w]} { catch {::createToplevel $w} ; return }
  if {[docking]} {
    ::createToplevel $w
    ::setTitle $w [T "Direct" "Live"]
  } else {
    toplevel $w
    wm title $w [T "Direct" "Live"]
  }
  set f [ttk::frame $w.f -padding {10 8}]
  pack $f -fill both -expand 1
  # (the players and their clocks are above and below the board, like
  # on Lichess: see bandes)
  ttk::label $f.res -anchor w -font font_Bold
  pack $f.res -side top -fill x -pady 2
  # Buttons
  set b [ttk::frame $f.b]
  ttk::button $b.retour -text [T "← Retransmissions" "← Broadcasts"] -command ::moderne::direct::retourListe
  ttk::label $b.lichess -text "Powered by Lichess" -foreground [::moderne::c accent] -cursor hand2
  bind $b.lichess <Button-1> ::moderne::direct::voirLichess
  # section and round, as in the broadcast list
  ttk::combobox $b.sec -state readonly -width 14
  ttk::combobox $b.r -state readonly -width 22
  bind $b.sec <<ComboboxSelected>> ::moderne::direct::panneauSection
  bind $b.r <<ComboboxSelected>> ::moderne::direct::panneauRonde
  catch {::utils::tooltip::Set $b.sec [T "Section" "Section"]}
  catch {::utils::tooltip::Set $b.r [T "Ronde" "Round"]}
  pack $b.retour -side left -padx {0 6}
  pack $b.lichess -side right
  pack $b -side top -fill x -pady {8 6}
  # Other games of the round
  set l [ttk::frame $f.l]
  # (no clocks here: those of the followed game are above and below the
  # board; ongoing games are marked)
  ttk::treeview $l.t -columns {blanc res noir} -show {tree headings} -selectmode browse -height 6
  foreach {c fr en ww a} {
    blanc "Blancs" "White" 200 w
    res "" "" 70 center
    noir "Noirs" "Black" 200 w
  } {
    $l.t heading $c -text [T $fr $en] -anchor $a
    $l.t column $c -width $ww -anchor $a -stretch [expr {$c in {blanc noir}}]
  }
  $l.t column #0 -width 0 -stretch 0
  $l.t tag configure enCours -foreground [::moderne::c accent]
  $l.t tag configure suivie -font font_Bold
  $l.t tag configure match -font font_Bold
  ttk::scrollbar $l.y -orient vertical -command [list $l.t yview]
  $l.t configure -yscrollcommand [list $l.y set]
  pack $l.y -side right -fill y
  pack $l.t -side left -fill both -expand 1
  pack $l -side top -fill both -expand 1
  bind $l.t <Motion> {::moderne::direct::survolListe %W %x %y blanc noir}
  bind $l.t <Leave> {::moderne::direct::survolListeFin %W}
  bind $l.t <Double-Button-1> [list after idle ::moderne::direct::suivreSelection $l.t]
  bind $l.t <Return> [list after idle ::moderne::direct::suivreSelection $l.t]
  ttk::label $f.etat -foreground [::moderne::c texteDoux] -anchor w
  pack $f.etat -side top -fill x -pady {4 0}
  catch {::moderne::repeindre $w}
  if {[docking]} { ::createToplevelFinalize $w }
  bandes
  modeToby partie
  bind $w <Destroy> [list ::moderne::direct::fermeturePanneau %W $w]
  majPanneauListe
  majPanneauRondes
  majPanneau
  after 1000 ::moderne::direct::tic
}

### Round names of the current tour (live / finished / start time)
### Round shown by default: the live one, else the last finished one
### (like Lichess), else the one Lichess suggests
proc ::moderne::direct::rondeDefaut {v} {
  set dernier {}
  foreach r [::moderne::json::get $v rounds {}] {
    if {[::moderne::json::get $r ongoing 0]} { return [list [::moderne::json::get $r id {}] 1] }
    if {[::moderne::json::get $r finished 0]} { set dernier [::moderne::json::get $r id {}] }
  }
  if {$dernier eq {}} { set dernier [::moderne::json::get $v defaultRoundId {}] }
  if {$dernier eq {}} { set dernier [::moderne::json::get [lindex [::moderne::json::get $v rounds {}] end] id {}] }
  return [list $dernier 0]
}

proc ::moderne::direct::nomsRondes {} {
  variable tour
  set noms {}
  foreach r [::moderne::json::get $tour rounds {}] {
    set n [::moderne::json::get $r name ?]
    if {[::moderne::json::get $r ongoing 0]} {
      set n "● $n ([T "en cours" "live"])"
    } elseif {[::moderne::json::get $r finished 0]} {
      set n "✓ $n"
    } else {
      set debut [::moderne::json::get $r startsAt {}]
      if {$debut ne {}} { append n "  ([debutRonde $debut])" }
    }
    lappend noms $n
  }
  return $noms
}

### Section and round selectors of the live panel
proc ::moderne::direct::majPanneauRondes {} {
  variable panneau
  variable tour
  variable ronde
  set b $panneau.f.b
  if {![winfo exists $b.r]} { return }
  set tr [::moderne::json::get $tour tour {}]
  set sec [::moderne::json::get $tour group tours {}]
  if {[llength $sec] > 1} {
    set noms {}
    set courant {}
    foreach x $sec {
      lappend noms [::moderne::json::get $x name ?]
      if {[::moderne::json::get $x id {}] eq [::moderne::json::get $tr id {}]} { set courant [::moderne::json::get $x name ?] }
    }
    $b.sec configure -values $noms
    $b.sec set $courant
    pack $b.sec -side left -padx {0 6} -after $b.retour
  } else {
    pack forget $b.sec
  }
  set noms [nomsRondes]
  if {![llength $noms]} { pack forget $b.r ; return }
  $b.r configure -values $noms
  set i 0
  foreach r [::moderne::json::get $tour rounds {}] {
    if {[::moderne::json::get $r id {}] eq $ronde} { $b.r current $i ; break }
    incr i
  }
  pack $b.r -side left -padx {0 6} -after [expr {[winfo manager $b.sec] ne {} ? "$b.sec" : "$b.retour"}]
}

proc ::moderne::direct::panneauSection {} {
  variable panneau
  variable tour
  set nom [$panneau.f.b.sec get]
  foreach x [::moderne::json::get $tour group tours {}] {
    if {[::moderne::json::get $x name {}] eq $nom} { chargerTour [::moderne::json::get $x id {}] ; return }
  }
}

proc ::moderne::direct::panneauRonde {} {
  variable panneau
  variable tour
  set r [lindex [::moderne::json::get $tour rounds {}] [$panneau.f.b.r current]]
  set id [::moderne::json::get $r id {}]
  if {$id eq {}} { return }
  chargerRonde $id [::moderne::json::get $r ongoing 0]
}

################################################################################
### Players above and below the board (like Lichess): title, name, Elo,
### team, clock (the running one highlighted)
################################################################################

proc ::moderne::direct::bandes {} {
  if {![winfo exists .main.board]} { return }
  catch {::moderne::pendule::polices}
  ::moderne::bandeau::polices
  set fond [::moderne::bandeau::couleur]
  foreach b {liveHaut liveBas} {
    set f .main.$b
    catch {destroy $f}
    frame $f -background $fond
    label $f.titre -font font_Bold -foreground #d59020 -background $fond
    label $f.nom -font font_BandeNom -foreground [::moderne::c texte] -background $fond
    label $f.elo -font font_BandeElo -foreground [::moderne::c texteDoux] -background $fond
    label $f.equipe -foreground [::moderne::c texteDoux] -background $fond
    # (level of play estimated from the moves, Toby)
    label $f.niveau -foreground [::moderne::c accent] -background $fond
    label $f.clk -font font_PenduleDixiemes -width 8 -anchor e -padx 10 -pady 0 \
        -foreground [::moderne::c texte] -background [::moderne::c champ]
    pack $f.clk -side right -padx {0 4} -pady 4
    # (Siby: the player's photo; the title, and the world champions' gold
    # king or queen, as text next to the name, as on Lichess)
    catch {::moderne::avatars::creer $f.avatar 43 ; pack $f.avatar -side left -padx {4 8} -pady 2}
    label $f.champion -font font_BandeNom -foreground #d4a017 -background $fond
    pack $f.titre $f.champion $f.nom $f.elo $f.niveau $f.equipe -side left -padx {0 6}
    bind $f <Configure> [list ::moderne::direct::ajusterBande $b]
    foreach x [list $f.titre $f.nom $f.avatar.i] {
      catch {survolJoueur $x [list ::moderne::direct::nomBande $b]}
      catch {$x configure -cursor hand2}
    }
  }
  # (navigation arrows: in the notation panel, if wanted)
  catch ::moderne::bandeau::navNotation
  foreach b {liveHaut liveBas} { ::moderne::bandeau::habiller .main.$b }
  grid remove .main.button
  grid .main.liveHaut -row 1 -column 0 -sticky we -padx 5 -pady {4 0}
  grid .main.liveBas -row 3 -column 0 -sticky new -padx 5 -pady {0 4}
  ::moderne::bandeau::suivre
  after idle ::moderne::bandeau::aligner
}

### Toby in the live view: "This game" mode (the players' ratings and the
### time control of the broadcast); the user's mode comes back afterwards
### (mode empty)
proc ::moderne::direct::modeToby {mode} {
  variable modeTobyAvant
  if {![info exists ::moderne::toby::modeAnalyse]} { return }
  if {$mode ne {}} {
    if {![info exists modeTobyAvant]} { set modeTobyAvant $::moderne::toby::modeAnalyse }
  } else {
    if {![info exists modeTobyAvant]} { return }
    set mode $modeTobyAvant
    unset modeTobyAvant
  }
  if {$::moderne::toby::modeAnalyse eq $mode} { return }
  set ::moderne::toby::modeAnalyse $mode
  foreach w [winfo children .] {
    if {[regexp {^\.analysisWin([0-9]+)$} $w -> n] && [winfo exists $w.toby]} {
      catch {::moderne::toby::changerMode $n}
    }
  }
}

proc ::moderne::direct::fermeturePanneau {widget panneau} {
  if {$widget ne $panneau} { return }
  catch {destroy .main.liveHaut}
  catch {destroy .main.liveBas}
  catch {destroy .pgnWin.live}
  modeToby {}
  # (the names' bands come back)
  after idle {catch ::moderne::horloges::maj}
}

proc ::moderne::direct::majBandes {p cb cn trait} {
  # (board turned round: White above)
  set retourne 0
  catch {set retourne [::board::isFlipped .main.board]}
  set haut [expr {$retourne ? "B" : "N"}]
  set bas  [expr {$retourne ? "N" : "B"}]
  foreach {b c clk} [list liveHaut $haut [expr {$haut eq "B" ? $cb : $cn}] liveBas $bas [expr {$bas eq "B" ? $cb : $cn}]] {
    set f .main.$b
    if {![winfo exists $f]} { continue }
    $f.titre configure -text [titreJoueur $p $c]
    catch {
      set ch [::moderne::avatars::marqueChampion $f.champion [dict get $p nom$c] font_BandeNom]
      pack configure $f.champion -padx [expr {$ch ? {0 6} : 0}]
    }
    variable nomsBandes
    set nomsBandes($b) [dict get $p nom$c]
    catch {::moderne::avatars::maj $f.avatar [dict get $p nom$c] {} 43}
    $f.elo configure -text [dict get $p elo$c]
    $f.equipe configure -text [dict get $p equipe$c]
    # (the level of play from the game's review, if it had one)
    catch {
      set t [niveauPartie $c]
      if {$t ne [$f.niveau cget -text]} {
        $f.niveau configure -text $t
        ::utils::tooltip::Set $f.niveau [expr {$t ne {} ? [T "Niveau de jeu dans cette partie, d'après le Bilan (Toby)" \
            "Level of play in this game, from the review (Toby)"] : {}}]
      }
    }
    $f.clk configure -text $clk -width [string length $clk]
    ajusterBande $b
    if {$c eq $trait} {
      $f.clk configure -foreground #ffffff -background $::moderne::pendule::coul(marche)
    } else {
      $f.clk configure -foreground [::moderne::c texte] -background [::moderne::c champ]
    }
  }
}

### The player's full name in band b (the label may show it shortened)
proc ::moderne::direct::nomBande {b} {
  variable nomsBandes
  if {[info exists nomsBandes($b)]} { return $nomsBandes($b) }
  return [.main.$b.nom cget -text]
}

### "Martirosyan, Haik M." -> "Martirosyan, H."
proc ::moderne::direct::nomCourt {n} {
  if {[regexp {^([^,]+),\s*(\S)} $n -> nom p]} { return "$nom, $p." }
  return $n
}

### Band b too narrow for all it shows (the group was cut, Yosha
### 2026-11-11): the first name as its initial
proc ::moderne::direct::ajusterBande {b} {
  variable nomsBandes
  set f .main.$b
  if {![winfo exists $f] || ![info exists nomsBandes($b)]} { return }
  set W [winfo width $f]
  set nom $nomsBandes($b)
  if {$W > 1} {
    $f.nom configure -text $nom
    set besoin 0
    foreach w [pack slaves $f] {
      set px [dict get [pack info $w] -padx]
      incr besoin [expr {[winfo reqwidth $w] + [lindex $px 0] + [lindex $px end]}]
    }
    if {$besoin > $W} { set nom [nomCourt $nom] }
  }
  if {[$f.nom cget -text] ne $nom} { $f.nom configure -text $nom }
}

### Level of play of side c (B, N) of the game on the board, from its
### review: the game's header, else the review kept for the same moves;
### "≈ 2480" or {}
proc ::moderne::direct::niveauPartie {c} {
  set tag [expr {$c eq "B" ? "WhiteLevel" : "BlackLevel"}]
  set src {} ; set niv {}
  foreach {t v} [sc_game tags get Extra] {
    if {$t eq $tag && [string is integer -strict $v]} { set niv $v }
    if {$t eq "${tag}Source" && $v eq "moves"} { set src a }
  }
  if {$niv ne {}} { return [::moderne::niveau::affiche $niv 1 $src] }
  set f [::moderne::bilan::fichierCache [::moderne::bilan::coupsUci]]
  if {![file exists $f]} { return {} }
  set h [open $f r]
  fconfigure $h -encoding utf-8
  set pgn [lindex [read $h] 1]
  close $h
  if {[regexp "$tag \"(\\d+)\"" $pgn -> v]} { return [::moderne::niveau::affiche $v 1 [expr {[regexp "${tag}Source \"moves\"" $pgn] ? "a" : {}}]] }
  return {}
}

### Levels of play by the players' names from estimate cle (the review's,
### while it computes)
proc ::moderne::direct::niveauBandes {cle} {
  set retourne 0
  catch {set retourne [::board::isFlipped .main.board]}
  foreach {b c} [list liveHaut [expr {$retourne ? "B" : "N"}] liveBas [expr {$retourne ? "N" : "B"}]] {
    set l .main.$b.niveau
    if {![winfo exists $l]} { continue }
    set t [::moderne::niveau::texte $cle $c]
    if {$t eq {} || $t eq [$l cget -text]} { continue }
    $l configure -text $t
    ::utils::tooltip::Set $l [::moderne::niveau::bulle $cle $c]
  }
}

### Levels of play by the players' names, given as texts (White, Black)
proc ::moderne::direct::niveauBandesTextes {tB tN} {
  set retourne 0
  catch {set retourne [::board::isFlipped .main.board]}
  foreach {b t} [list liveHaut [expr {$retourne ? $tB : $tN}] liveBas [expr {$retourne ? $tN : $tB}]] {
    if {[winfo exists .main.$b.niveau] && $t ne "–"} { .main.$b.niveau configure -text $t }
  }
}

proc ::moderne::direct::secondes {hms} {
  set s 0
  foreach x [split $hms :] { scan $x %d v ; set s [expr {$s * 60 + $v}] }
  return $s
}

### Clocks of game id at the board position: each side's [%clk] of its
### last move played so far (empty before its first move)
proc ::moderne::direct::pendulesIci {id} {
  variable parties
  set c {}
  foreach {- x} [regexp -all -inline {\[%clk ([0-9:]+)\]} [dict get $parties($id) pgn]] { lappend c $x }
  # moves played up to the board position
  set m [sc_pos location]
  set cb {} ; set cn {}
  for {set j [expr {min($m, [llength $c]) - 1}]} {$j >= 0 && ($cb eq {} || $cn eq {})} {incr j -1} {
    if {$j % 2 == 0 && $cb eq {}} { set cb [hms [secondes [lindex $c $j]]] }
    if {$j % 2 == 1 && $cn eq {}} { set cn [hms [secondes [lindex $c $j]]] }
  }
  return [list $cb $cn]
}

### Clocks of game p: the side to move loses the time since the last move
proc ::moderne::direct::pendules {id} {
  variable parties
  variable recu
  set p $parties($id)
  set cb [dict get $p clkB]
  set cn [dict get $p clkN]
  if {$cb ne {}} { set cb [hms [secondes $cb]] }
  if {$cn ne {}} { set cn [hms [secondes $cn]] }
  if {[dict get $p res] ne "*" || ![info exists recu($id)]} { return [list $cb $cn {}] }
  set ecoule [expr {[clock seconds] - $recu($id)}]
  set trait [expr {[dict get $p plies] % 2 ? "N" : "B"}]
  if {$trait eq "B" && $cb ne {}} { set cb [hms [expr {max(0, [secondes $cb] - $ecoule)}]] }
  if {$trait eq "N" && $cn ne {}} { set cn [hms [expr {max(0, [secondes $cn] - $ecoule)}]] }
  return [list $cb $cn $trait]
}

### Players, clocks, result and the live button
proc ::moderne::direct::majPanneau {} {
  variable panneau
  variable suivie
  variable parties
  variable nouveaux
  set f $panneau.f
  if {![winfo exists $f] || $suivie eq {} || ![info exists parties($suivie)]} { return }
  if {![vueOuverte]} { return }
  set p $parties($suivie)
  lassign [pendules $suivie] cb cn trait
  # On an earlier move (or a finished game): the clocks at that move, as
  # on Lichess ([%clk] of each side's last move up to the board position)
  if {[surLaPartie] && [sc_var level] == 0 && !([auDirect] && [dict get $p res] eq "*")} {
    lassign [pendulesIci $suivie] cb cn
    set trait {}
  }
  majBandes $p $cb $cn $trait
  set res [dict get $p res]
  set titre "[nomJoueur $p B] – [nomJoueur $p N]"
  if {$res eq "*"} {
    $f.res configure -text "● [T "EN DIRECT" "LIVE"]   $titre" -foreground #e0443e
  } else {
    $f.res configure -text "[texteRes $res]   $titre" -foreground [::moderne::c texte]
  }
  set d [barreNotation]
  if {$d eq {}} { return }
  if {[surLaPartie] && [auDirect]} {
    set nouveaux 0
    $d.direct configure -text [expr {$res eq "*" ? [T "● En direct" "● Live"] : [T "Dernier coup" "Last move"]}] -state disabled
  } else {
    set t [T "Revenir au direct" "Back to live"]
    if {$nouveaux > 0} { append t "  (+$nouveaux)" }
    $d.direct configure -text $t -state normal
  }
}

### Games of the round in the panel (the followed one in bold)
proc ::moderne::direct::majPanneauListe {} {
  variable panneau
  variable parties
  variable ordre
  variable suivie
  set t $panneau.f.l.t
  if {![winfo exists $t]} { return }
  set sel [$t selection]
  $t delete [$t children {}]
  set equipes 0
  foreach id $ordre { if {[dict get $parties($id) equipeB] ne {}} { set equipes 1 ; break } }
  if {$equipes} { $t column #0 -width 20 } else { $t column #0 -width 0 }
  foreach id $ordre {
    set p $parties($id)
    set parent {}
    if {$equipes} {
      set cle [list [dict get $p equipeB] [dict get $p equipeN]]
      set inv [list [dict get $p equipeN] [dict get $p equipeB]]
      if {[info exists match($inv)]} { set cle $inv }
      if {![info exists match($cle)]} {
        set match($cle) "m[array size match]"
        $t insert {} end -id $match($cle) -open 1 -tags match
      }
      set parent $match($cle)
    }
    set tags {}
    if {[dict get $p res] eq "*"} { lappend tags enCours }
    if {$id eq $suivie} { lappend tags suivie }
    set res [dict get $p res]
    $t insert $parent end -id $id -values [list [nomJoueur $p B] [expr {$res eq "*" ? "●" : [texteRes $res]}] [nomJoueur $p N]] -tags $tags
  }
  foreach cle [array names match] { scoreMatch $match($cle) $cle $t }
  foreach m [array names match] {
    set v [$t item $match($m) -values]
    $t item $match($m) -values [list [lindex $v 1] [lindex $v 3] [lindex $v 4]]
  }
  foreach i $sel { if {[$t exists $i]} { $t selection set $i } }
  if {$suivie ne {} && [$t exists $suivie]} { $t see $suivie }
}

### Every second: clocks, live button
### The clocks follow the board when moving through the followed game
trace add execution updateBoard leave {apply {args {
  catch ::moderne::direct::majBarre
  if {[winfo exists $::moderne::direct::panneau]} { catch ::moderne::direct::majPanneau }
}}}

### The live bar under the notation (Back to live, Save, Review) only on the
### followed broadcast game: it stayed on a game against an Alter Ego, in
### the Analysis view (Yosha 2026-11-11)
proc ::moderne::direct::majBarre {} {
  set d .pgnWin.live
  if {![winfo exists $d]} { return }
  set montrer [surLaPartie]
  set vue [expr {[winfo manager $d] ne {}}]
  if {$montrer && !$vue} {
    pack $d -side bottom -fill x -before .pgnWin.text
  } elseif {!$montrer && $vue} {
    pack forget $d
  }
}

proc ::moderne::direct::tic {} {
  variable panneau
  if {![winfo exists $panneau]} { return }
  if {![vueOuverte]} { return }
  catch majPanneau
  after 1000 ::moderne::direct::tic
}

proc ::moderne::direct::voirLichess {} {
  variable w
  variable parties
  set id {}
  catch {set id [lindex [$w.f.pw.d.p.t selection] 0]}
  if {$id ne {} && [info exists parties($id)]} {
    set url [tag [dict get $parties($id) pgn] GameURL]
    if {$url ne {}} { catch {openURL $url} ; return }
  }
  variable tour
  set url [::moderne::json::get $tour tour url {}]
  if {$url ne {}} { catch {openURL $url} }
}

################################################################################
### "Players" panel of the game view: the repertoire of each player with
### their colour in this game (White player with White, Black player with
### Black), in the largest open database (Gaby), following the board
################################################################################

namespace eval ::moderne::direct {
  variable jw .joueursWin
  variable jNom           ;# jNom(white|black): player whose games are indexed
  array set jNom {}
  variable jIdx           ;# jIdx(colour,key) = dict move -> {n wins draws losses latest}
  array set jIdx {}
  variable jPassees       ;# jPassees(colour,key) = games through the position
  array set jPassees {}
  variable jTotal         ;# jTotal(colour) = games read
  array set jTotal {}
  variable jEtat          ;# jEtat(colour) = "loading" text or {}
  array set jEtat {}
  variable jMax 3000      ;# most recent games read per player
  variable jCouleur auto  ;# whose moves: auto (player to move), white, black
  variable jPlies 40
}

### Reference database: the largest open one (other than the clipboard and
### "Siby live")
proc ::moderne::direct::baseReference {} {
  # the reference database (opened if needed), never "Siby live"
  set b 0
  catch {set b [::moderne::mesbases::baseReference]}
  if {$b == [baseLive]} { set b 0 }
  return $b
}

proc ::moderne::direct::ouvrirJoueurs {} {
  variable jw
  set w $jw
  if {[winfo exists $w]} { catch {::createToplevel $w} ; return }
  if {[docking]} {
    ::createToplevel $w
    ::setTitle $w [T "Bibliothèque" "Library"]
  } else {
    toplevel $w
    wm title $w [T "Bibliothèque" "Library"]
  }
  set f [ttk::frame $w.f -padding {10 6}]
  pack $f -fill both -expand 1
  # Whose moves: the player to move (default), or White / Black
  set h [ttk::frame $f.h]
  set style Toolbutton
  if {![catch {ttk::style layout Segment.Toolbutton} l] && $l ne {}} { set style Segment.Toolbutton }
  foreach {v fr en} {auto "Camp au trait" "Side to move" white "Blancs" "White" black "Noirs" "Black"} {
    ttk::radiobutton $h.$v -text [T $fr $en] -style $style -variable ::moderne::direct::jCouleur \
        -value $v -command ::moderne::direct::majJoueurs
    pack $h.$v -side left -padx 1
  }
  pack $h -side top -anchor w -pady {0 4}
  ttk::label $f.qui -font font_Bold -anchor w
  ttk::label $f.info -foreground [::moderne::c texteDoux] -anchor w
  ttk::label $f.ref -foreground [::moderne::c texteDoux] -anchor w
  pack $f.qui $f.info $f.ref -side top -fill x
  ttk::panedwindow $f.pw -orient vertical
  pack $f.pw -side top -fill both -expand 1 -pady {4 0}
  ttk::frame $f.pw.h
  ttk::frame $f.pw.b
  $f.pw add $f.pw.h -weight 3
  $f.pw add $f.pw.b -weight 2
  # The player's moves (his columns) next to the reference database (Gaby)
  # (the Preparation's table: the player's columns apart from the
  # reference's, average Elo / perf / last game in the bar's tooltip)
  ::moderne::biblio::creerTablePrepa $f.pw.h.t
  ttk::scrollbar $f.pw.h.sb -command [list $f.pw.h.t yview]
  # (the Σ row follows the scrolling, as in Prepare)
  $f.pw.h.t configure -yscrollcommand [list ::moderne::tableau::defilement $f.pw.h.t $f.pw.h.sb]
  pack $f.pw.h.sb -side right -fill y
  pack $f.pw.h.t -side left -fill both -expand 1
  # Below, side by side: the player's games through the position (left)
  # and the top games of the reference database (right)
  ttk::panedwindow $f.pw.b.pw -orient horizontal
  pack $f.pw.b.pw -fill both -expand 1
  foreach {cote titre} {lui "" top ""} {
    set g [ttk::frame $f.pw.b.pw.$cote]
    ttk::label $g.titre -anchor w -padding {0 4 0 2}
    pack $g.titre -side top -fill x
    ::moderne::biblio::creerListeParties $g.t
    $g.t configure -displaycolumns {blanc eloB noir eloN res date}
    # (half width: the names give way, Elo, result and date stay whole)
    foreach {c l} {blanc 120 noir 120} { $g.t column $c -width $l -minwidth 60 -stretch 1 }
    $g.t heading res -text [T "Rés." "Res."]
    foreach {c l} {eloB 46 eloN 46 res 56 date 86} { $g.t column $c -width $l -minwidth $l -stretch 0 }
    ttk::scrollbar $g.sb -command [list $g.t yview]
    $g.t configure -yscrollcommand [list $g.sb set]
    pack $g.sb -side right -fill y
    pack $g.t -side left -fill both -expand 1
    bind $g.t <Double-Button-1> {::moderne::direct::partieAction %W nouveau ; break}
    bind $g.t <Return> {::moderne::direct::partieAction %W nouveau ; break}
    bind $g.t <Button-3> {::moderne::direct::menuPartie %W %x %y %X %Y}
    # (hovered: the game's next moves on one line, as in the Lab's library,
    # Yosha 2026-11-12; this panel keeps its own right-click menu)
    ::moderne::biblio::installerSurvolParties $g.t ::moderne::direct::baseSurvol 0
    $f.pw.b.pw add $g -weight 1
  }
  catch {::moderne::repeindre $w}
  if {[docking]} { ::createToplevelFinalize $w }
  ::moderne::biblio::abonner ::moderne::direct::majJoueurs
  bind $w <Destroy> [list ::moderne::biblio::fermeture %W $w ::moderne::direct::majJoueurs]
  chargerJoueurs
  # (the search in the reference database after the layout is shown: on
  # Gaby it takes seconds and would hold the switch to the game view)
  after 400 ::moderne::direct::majJoueurs
}

### A game of the lists: id "g<number>" (top games) or "p<number>,<ply>"
### (the player's games); action: nouveau (new board), inserer (into the
### notation, as a variation), ouvrir (open on the main board)
proc ::moderne::direct::partieAction {t action} {
  set id [$t focus]
  if {$id eq {}} { return }
  set ply {}
  if {[regexp {^p([0-9]+),([0-9]+)$} $id -> gnum ply]} {
  } elseif {[regexp {^g([0-9]+)$} $id -> gnum]} {
  } else { return }
  set b [baseReference]
  set ::moderne::direct::baseSurvol $b
  if {!$b} { return }
  switch -- $action {
    nouveau {
      if {$ply eq {}} { set ply [plyIci $b $gnum] }
      catch {::gbrowser::new $b $gnum $ply}
    }
    inserer { insererVariante $b $gnum }
    ouvrir { ::moderne::biblio::ouvrirPartie $b $gnum $ply }
  }
}

### Inserts game gnum of database b into the notation, as a variation
### from the board's position (like Lichess); the board does not move
proc ::moderne::direct::insererVariante {b gnum} {
  set cible [::moderne::biblio::cle [sc_pos board]]
  set courante [sc_base current]
  if {$courante != $b} { sc_base switch $b }
  if {[catch {sc_game boards $gnum} positions]} { set positions {} }
  if {$courante != $b} { sc_base switch $courante }
  set ply -1
  set i 0
  foreach p $positions {
    if {[::moderne::biblio::cle [lindex $p 1]] eq $cible} { set ply $i ; break }
    incr i
  }
  set coups {}
  foreach p [lrange $positions [expr {$ply + 1}] end] { lappend coups [lindex $p 0] }
  if {$ply < 0 || ![llength $coups]} {
    tk_messageBox -icon info -type ok -title Siby -message [T \
        "Cette partie ne passe pas par la position de l'échiquier, ou s'y arrête." \
        "This game does not reach the board's position, or ends there."]
    return
  }
  set dernier {}
  if {[sc_pos isAt vend]} {
    # end of the line: the variation replaces its last move (as SCID's
    # merge does)
    if {[sc_pos isAt vstart]} { return }
    set dernier [sc_game info previousMove]
    sc_move back
  }
  sc_game undoPoint
  sc_var create
  set premier 1
  if {$dernier ne {}} { set coups [linsert $coups 0 $dernier] }
  foreach m $coups {
    if {[catch {sc_move addSan $m}]} { break }
    if {$premier} {
      set premier 0
      catch {sc_pos setComment [nomPartie $b $gnum]}
    }
  }
  # (back at the position where the variation starts)
  sc_var exit
  if {$dernier ne {}} { catch {sc_move forward} }
  updateBoard -pgn
}

### "White - Black result, event year" of game gnum of database b
proc ::moderne::direct::nomPartie {b gnum} {
  variable jPartie
  if {[info exists jPartie($gnum)]} {
    lassign $jPartie($gnum) blanc eloB noir eloN res date ev
    set an [string range $date 0 3]
    if {[string first $an $ev] < 0} { append ev " $an" }
    return "$blanc - $noir $res, $ev"
  }
  return {}
}

proc ::moderne::direct::menuPartie {t x y X Y} {
  set id [$t identify item $x $y]
  if {$id eq {}} { return }
  $t selection set $id
  $t focus $id
  set m $t.menu
  catch {destroy $m}
  menu $m -tearoff 0
  $m add command -label [T "Ouvrir sur un nouvel échiquier" "Open on a new board"] -command [list ::moderne::direct::partieAction $t nouveau]
  $m add command -label [T "Insérer dans la notation (variante)" "Insert into the notation (variation)"] -command [list ::moderne::direct::partieAction $t inserer]
  $m add separator
  $m add command -label [T "Ouvrir à la place de la partie en direct" "Open instead of the live game"] -command [list ::moderne::direct::partieAction $t ouvrir]
  tk_popup $m $X $Y
}

### Ply where game gnum of database b reaches the board's position
proc ::moderne::direct::plyIci {b gnum} {
  set cible [::moderne::biblio::cle [sc_pos board]]
  set courante [sc_base current]
  if {$courante != $b} { sc_base switch $b }
  if {[catch {sc_game boards $gnum} positions]} { set positions {} }
  if {$courante != $b} { sc_base switch $courante }
  set i 0
  foreach p $positions {
    if {[::moderne::biblio::cle [lindex $p 1]] eq $cible} { return $i }
    incr i
  }
  return 0
}

### Players of the followed game: their games are read if needed
proc ::moderne::direct::chargerJoueurs {} {
  variable suivie
  variable parties
  variable jNom
  if {$suivie eq {} || ![info exists parties($suivie)]} { return }
  set p $parties($suivie)
  foreach c {white black} cote {B N} {
    set nom [dict get $p nom$cote]
    # (read again when the reference database has changed, e.g. opened
    # after the game was followed)
    variable jBase
    if {[info exists jNom($c)] && $jNom($c) eq $nom && [info exists jBase($c)] && $jBase($c) == [baseReference]} { continue }
    lireJoueur $c $nom
  }
}

proc ::moderne::direct::lireJoueur {c nom} {
  variable jNom
  variable jIdx
  variable jPassees
  variable jTotal
  variable jEtat
  variable jMax
  set jNom($c) $nom
  array unset jIdx $c,*
  array unset jPassees $c,*
  array unset ::moderne::direct::jListe $c,*
  set jTotal($c) 0
  set b [baseReference]
  set ::moderne::direct::baseSurvol $b
  variable jBase
  set jBase($c) $b
  # (no reference database: said once, below the table)
  if {!$b} { set jEtat($c) {} ; majJoueurs ; return }
  set jEtat($c) [T "lecture de ses parties…" "reading their games…"]
  majJoueurs 0
  # (already read in this database: at once)
  variable jCache
  set k [list $b $nom [sc_base numGames $b]]
  if {[info exists jCache($k)]} {
    lireLignes $c $nom $b [lignesCouleur $c {*}$jCache($k)]
    return
  }
  # the player's games, both colours in one pass over the database (about
  # 0.4 s on Gaby: one pass costs that, whatever the range of games, so the
  # search in slices of 2026-10-30 took a minute), once the game is shown
  after 300 [list ::moderne::direct::lirePartiesJoueur $c $nom $b $k]
}

### One pass over the database: the games where the player has either
### colour (exact name, else the name followed by anything); kept for both
### colours
proc ::moderne::direct::lirePartiesJoueur {c nom b k} {
  variable jNom
  variable jMax
  variable jw
  variable jCache
  if {![winfo exists $jw] || $jNom($c) ne $nom || ![sc_base inUse $b]} { return }
  if {[info exists jCache($k)]} {
    lireLignes $c $nom $b [lignesCouleur $c {*}$jCache($k)]
    return
  }
  # (same: after the layout)
  if {[dispositionEnCours]} {
    after 300 [list ::moderne::direct::lirePartiesJoueur $c $nom $b $k]
    return
  }
  # Each search is a full pass on the database (about 1 s on Gaby): one at
  # a time, with a pause between them so that the interface stays smooth
  variable jPasse
  if {![info exists jPasse]} { set jPasse 0 }
  set maintenant [clock milliseconds]
  if {$maintenant - $jPasse < 800} {
    after [expr {800 - ($maintenant - $jPasse)}] [list ::moderne::direct::lirePartiesJoueur $c $nom $b $k]
    return
  }
  set motif [::moderne::prepa::echapperMotif $nom]
  set courante [sc_base current]
  sc_base switch $b
  # (over the board only: in the same pass, not in a second one)
  set otb [expr {[catch {::moderne::otb::exclure $b} x] ? {} : ($x ? {-fCustom5 no} : {})}]
  set brut [expr {[llength [info commands ::sc_search_otb]] ? "::sc_search_otb" : "::sc_search"}]
  set lignes {}
  foreach pat [list $motif "$motif*"] {
    catch {
      $brut header -white "\"$pat\"" -flip 1 {*}$otb -filter RESET
      set n [sc_filter count]
      if {$n > 0} {
        # (the most recent ones, enough for each colour)
        set debut [expr {max(1, $n - 4 * $jMax + 1)}]
        set lignes [sc_game list $debut [expr {$n - $debut + 1}] "g*\tr*\td*\tw*\tW*\tb*\tB*\te*"]
      }
    }
    if {$lignes ne {}} { break }
  }
  # The whole database again in its filter, a little later (another pass)
  catch {sc_filter_otb reset}
  if {$otb ne {}} {
    after 400 [list ::moderne::direct::refiltrer $b]
  } else {
    catch {sc_filter reset}
  }
  sc_base switch $courante
  set jPasse [clock milliseconds]
  set jCache($k) [list $pat $lignes]
  if {$jNom($c) eq $nom} { lireLignes $c $nom $b [lignesCouleur $c $pat $lignes] }
  # (the other colour, waiting for the same player: from memory)
  set autre [expr {$c eq "white" ? "black" : "white"}]
  if {[info exists jNom($autre)] && $jNom($autre) eq $nom} {
    lireLignes $autre $nom $b [lignesCouleur $autre $pat $lignes]
  }
}

### Over the board only: the online games of database b out of its filter
### again (after a search of the players' games)
proc ::moderne::direct::refiltrer {b} {
  variable jPasse
  if {![sc_base inUse $b]} { return }
  set maintenant [clock milliseconds]
  if {$maintenant - $jPasse < 400} {
    after 400 [list ::moderne::direct::refiltrer $b]
    return
  }
  catch {::moderne::otb::filtrer $b}
  set jPasse [clock milliseconds]
}

### The lines of games where the player (pattern pat) has colour c, the
### most recent jMax
proc ::moderne::direct::lignesCouleur {c pat lignes} {
  variable jMax
  set res {}
  foreach l [split [string trimright $lignes \n] \n] {
    set f [split $l \t]
    set qui [string trim [lindex $f [expr {$c eq "white" ? 3 : 5}]]]
    if {[string match $pat $qui]} { lappend res $l }
  }
  return [join [lrange $res end-[expr {$jMax - 1}] end] \n]
}

### The games found (lines of sc_game list): read in packets
proc ::moderne::direct::lireLignes {c nom b lignes} {
  set file {}
  foreach l [split [string trimright $lignes \n] \n] {
    lassign [split $l \t] g r d bl eb no en ev
    set g [string trim $g]
    if {[string is integer -strict $g]} {
      lappend file [list $g [string trim $r] [string trim $d]]
      set ::moderne::direct::jPartie($g) [list [string trim $bl] [string trim $eb] [string trim $no] [string trim $en] [string trim $r] [string trim $d] [string trim $ev]]
    }
  }
  after idle [list ::moderne::direct::lirePaquet $c $nom $b $file]
}

### Reads the games in packets (the interface stays responsive)
proc ::moderne::direct::lirePaquet {c nom b file} {
  variable jNom
  variable jIdx
  variable jPassees
  variable jTotal
  variable jEtat
  variable jPlies
  variable jw
  if {![winfo exists $jw] || $jNom($c) ne $nom || ![sc_base inUse $b]} { return }
  set courante [sc_base current]
  sc_base switch $b
  set paquet [lrange $file 0 49]
  foreach e $paquet {
    lassign $e g r d
    if {[catch {sc_game boards $g $jPlies} pos]} { continue }
    incr jTotal($c)
    # player's score: result from their colour
    set score {}
    switch -- $r {
      1-0 { set score [expr {$c eq "white" ? 1 : 0}] }
      0-1 { set score [expr {$c eq "white" ? 0 : 1}] }
      =-= - 1/2-1/2 - 1/2 { set score 0.5 }
    }
    set r1 0 ; set r2 0
    catch {
      lassign $::moderne::direct::jPartie($g) - eb - en
      if {[string is integer -strict $eb] && [string is integer -strict $en]} {
        set r1 [expr {$c eq "white" ? $eb : $en}]
        set r2 [expr {$c eq "white" ? $en : $eb}]
      }
    }
    set vues {}
    set n [llength $pos]
    for {set i 0} {$i < $n} {incr i} {
      set cle [::moderne::biblio::cle [lindex $pos $i 1]]
      if {[dict exists $vues $cle]} { continue }
      dict set vues $cle 1
      incr jPassees($c,$cle)
      lappend ::moderne::direct::jListe($c,$cle) [list $g $i]
      if {$i + 1 >= $n} { continue }
      set coup [lindex $pos [expr {$i + 1}] 0]
      if {![info exists jIdx($c,$cle)]} { set jIdx($c,$cle) {} }
      set st [expr {[dict exists $jIdx($c,$cle) $coup] ? [dict get $jIdx($c,$cle) $coup] : {0 0 0 0 {} {}}}]
      lassign $st nn gg dd pp der elos
      incr nn
      if {$score eq 1} { incr gg } elseif {$score eq 0.5} { incr dd } elseif {$score eq 0} { incr pp }
      set der [::moderne::prepa::plusRecente $d $der]
      # (both ratings of that game: the overperformance, as in the Preparation)
      if {$score ne {} && $r1 > 0 && $r2 > 0} { lappend elos [list $r1 $r2 $score] }
      dict set jIdx($c,$cle) $coup [list $nn $gg $dd $pp $der $elos]
    }
  }
  sc_base switch $courante
  set reste [lrange $file 50 end]
  if {[llength $reste]} {
    set jEtat($c) "[T "lecture de ses parties…" "reading their games…"] [::utils::thousands $jTotal($c)]"
    majJoueurs 0
    after 1 [list ::moderne::direct::lirePaquet $c $nom $b $reste]
  } else {
    set jEtat($c) {}
    majJoueurs 0
  }
}

### Follows the board: the moves of the chosen player (default: the
### player to move) in the columns "His games / His score / His last", next
### to those of the reference database (Gaby), then its best games
### A layout is being built (or has just been): the slow searches wait
proc ::moderne::direct::dispositionEnCours {} {
  expr {([info exists ::docking::enConstruction] && $::docking::enConstruction)
        || ([info exists ::moderne::docks::restauration] && $::moderne::docks::restauration)
        || [winfo exists .voileDisposition]}
}

proc ::moderne::direct::majJoueurs {{avecRef 1}} {
  variable jRefCle
  variable jRef
  variable jw
  variable jNom
  variable jIdx
  variable jPassees
  variable jTotal
  variable jEtat
  variable jCouleur
  variable suivie
  variable parties
  variable jBase
  # (hidden under the Lab: brought up to date when shown again)
  if {![vueOuverte] && ![aLEcran $jw]} { return }
  # reference database changed since the players were read: read again
  if {$avecRef && [info exists jBase(white)] && $jBase(white) != [baseReference]} {
    after idle ::moderne::direct::chargerJoueurs
    return
  }
  set f $jw.f
  if {![winfo exists $f]} { return }
  if {![info exists jCouleur]} { set jCouleur auto }
  set cle [::moderne::biblio::cle [sc_pos board]]
  set c $jCouleur
  if {$c eq "auto"} { set c [sc_pos side] }
  set cote [expr {$c eq "white" ? "B" : "N"}]
  set nom [expr {[info exists jNom($c)] ? $jNom($c) : {}}]
  if {$suivie ne {} && [info exists parties($suivie)]} { set nom [nomJoueur $parties($suivie) $cote] }
  catch {
    $f.h.white configure -text "[T Blancs White] : [nomJoueur $parties($suivie) B]"
    $f.h.black configure -text "[T Noirs Black] : [nomJoueur $parties($suivie) N]"
  }
  $f.qui configure -text "$nom • [expr {$c eq "white" ? [T "avec les Blancs" "as White"] : [T "avec les Noirs" "as Black"]}]"
  set total [expr {[info exists jTotal($c)] ? $jTotal($c) : 0}]
  set ici [expr {[info exists jPassees($c,$cle)] ? $jPassees($c,$cle) : 0}]
  set etat [expr {[info exists jEtat($c)] ? $jEtat($c) : {}}]
  if {$etat ne {}} {
    set txt $etat
  } elseif {!$total} {
    set txt [T "aucune partie avec cette couleur dans la base de référence" "no game with this colour in the reference database"]
  } else {
    set txt "[::utils::thousands $total] [T parties games] • [::utils::thousands $ici] [T "passées par cette position" "through this position"]"
    if {[sc_pos side] ne $c} { append txt " • [T "en bleu : coups de ses adversaires" "in blue: their opponents' moves"]" }
  }
  $f.info configure -text $txt
  set lui [expr {[info exists jIdx($c,$cle)] ? $jIdx($c,$cle) : {}}]
  # the player's games through the position, most recent first
  set gl $f.pw.b.pw.lui
  $gl.t delete [$gl.t children {}]
  set liste {}
  if {[info exists ::moderne::direct::jListe($c,$cle)]} {
    foreach gp $::moderne::direct::jListe($c,$cle) {
      lassign $gp g ply
      if {[info exists ::moderne::direct::jPartie($g)]} { lappend liste [list [lindex $::moderne::direct::jPartie($g) 5] $g $ply] }
    }
  }
  foreach e [lrange [lsort -decreasing -index 0 $liste] 0 199] {
    lassign $e - g ply
    lassign $::moderne::direct::jPartie($g) bl eb no en r d ev
    $gl.t insert {} end -id p$g,$ply -values [list $bl $eb $no $en [string map {=-= ½-½} $r] $d $ev]
  }
  $gl.titre configure -text "[T "Parties de" "Games of"] $nom ([llength $liste])"
  # 1. right away: the player's moves (the reference is being searched;
  # while the player's games are read, the last reference is kept)
  catch {::moderne::tableau::titreGroupe $f.pw.h.t joueur $nom}
  if {!$avecRef && [info exists jRefCle] && $jRefCle eq $cle} {
    ::moderne::biblio::remplirPrepa $f.pw.h.t $jRef $lui $c
    return
  }
  ::moderne::biblio::remplirPrepa $f.pw.h.t {attente {}} $lui $c
  if {!$avecRef} { return }
  # (not while a layout is being built: it calls "update", and the search,
  # 3 s on Gaby when the position is not in the instant library, then held
  # the switch to the game view, 2026-10-31)
  if {[::moderne::direct::dispositionEnCours]} {
    variable majPlusTard
    catch {after cancel $majPlusTard}
    set majPlusTard [after 300 ::moderne::direct::majJoueurs]
    return
  }
  set b [baseReference]
  set ::moderne::direct::baseSurvol $b
  if {!$b} {
    $f.ref configure -text [T "Aucune base de référence ouverte." "No reference database open."]
    return
  }
  $f.ref configure -text "[::moderne::nomBase [sc_base filename $b]][T " : recherche…" ": searching…"]"
  update idletasks
  # 2. the reference database (instant library when it has one)
  set ref [::moderne::biblio::statsIci $b 0]
  if {[lindex $ref 0] == -1 || [::moderne::biblio::cle [sc_pos board]] ne $cle || ![winfo exists $f]} { return }
  set jRefCle $cle
  set jRef $ref
  catch {::moderne::tableau::titreGroupe $f.pw.h.t ref [::moderne::nomBase [sc_base filename $b]]}
  set total [::moderne::biblio::remplirPrepa $f.pw.h.t $ref $lui $c]
  set top $f.pw.b.pw.top
  set n [::moderne::biblio::remplirMeilleures $top.t $b $total]
  $f.ref configure -text "[::moderne::nomBase [sc_base filename $b]][T " : " ": "][::utils::thousands $total] [expr {$total == 1 ? [T "partie dans cette position" "game in this position"] : [T "parties dans cette position" "games in this position"]}]"
  $top.titre configure -text "[T "Top parties" "Top games"] ([::moderne::nomBase [sc_base filename $b]])"
}

proc ::moderne::direct::jouerCoupJoueur {t} {
  set coup [lindex [$t selection] 0]
  if {$coup eq {}} { return }
  catch {addSanMove $coup}
}

### End Siby

################################################################################
### Player card on hover (like Lichess): photo, rating, score and all the
### player's games of the tournament; a click follows a game
################################################################################

namespace eval ::moderne::direct {
  variable carteCache        ;# carteCache(tourId,player) {time answer}
  variable carteNom {}       ;# name the card is for
  variable aSuivre {}        ;# game to follow once its round is loaded
}

### Hover bindings on a widget showing the player of a side (script giving the name)
proc ::moderne::direct::survolJoueur {wid script} {
  bind $wid <Enter> [list ::moderne::direct::survolDebut %W $script]
  bind $wid <Leave> {::moderne::direct::survolFin}
}

proc ::moderne::direct::survolDebut {wid script} {
  catch {after cancel $::moderne::direct::survolAfter}
  catch {after cancel $::moderne::direct::fermerAfter}
  set ::moderne::direct::survolAfter [after 350 [list ::moderne::direct::carteJoueur $wid [uplevel #0 $script]]]
}

proc ::moderne::direct::survolFin {} {
  catch {after cancel $::moderne::direct::survolAfter}
  catch {after cancel $::moderne::direct::fermerAfter}
  set ::moderne::direct::fermerAfter [after 300 ::moderne::direct::fermerCarte]
}

### Treeviews of games: the White / Black column under the pointer
proc ::moderne::direct::survolListe {t x y colB colN} {
  set ligne [$t identify row $x $y]
  # (outside the columns: no column)
  if {[catch {$t column [$t identify column $x $y] -id} col]} { set col {} }
  set cle "$ligne $col"
  if {[info exists ::moderne::direct::survolCle($t)] && $::moderne::direct::survolCle($t) eq $cle} { return }
  set ::moderne::direct::survolCle($t) $cle
  variable parties
  if {$ligne eq {} || ![info exists parties($ligne)] || $col ni [list $colB $colN]} {
    survolFin
    return
  }
  set nom [dict get $parties($ligne) nom[expr {$col eq $colB ? "B" : "N"}]]
  catch {after cancel $::moderne::direct::survolAfter}
  catch {after cancel $::moderne::direct::fermerAfter}
  set ::moderne::direct::survolAfter [after 350 [list ::moderne::direct::carteJoueur $t $nom [winfo pointerx .] [winfo pointery .]]]
}

proc ::moderne::direct::survolListeFin {t} {
  catch {unset ::moderne::direct::survolCle($t)}
  survolFin
}

proc ::moderne::direct::fermerCarte {} {
  # (pointer on the card itself: it stays)
  set c .carteJoueur
  if {![winfo exists $c]} { return }
  set x [winfo pointerx .] ; set y [winfo pointery .]
  if {$x >= [winfo rootx $c] && $x < [winfo rootx $c] + [winfo width $c] &&
      $y >= [winfo rooty $c] && $y < [winfo rooty $c] + [winfo height $c]} {
    set ::moderne::direct::fermerAfter [after 300 ::moderne::direct::fermerCarte]
    return
  }
  destroy $c
  variable carteNom {}
}

### Lichess id of a player of the tournament: FIDE id, else the name
proc ::moderne::direct::idJoueur {nom} {
  variable joueurs
  foreach j $joueurs {
    if {[::moderne::json::get $j name {}] eq $nom} {
      set f [::moderne::json::get $j fideId {}]
      if {$f ne {}} { return $f }
    }
  }
  return [url $nom]
}

proc ::moderne::direct::carteJoueur {wid nom {x {}} {y {}}} {
  variable tour
  variable carteCache
  variable carteNom
  variable api
  if {$nom eq {} || $nom eq "?" || ![winfo exists $wid]} { return }
  set idTour [::moderne::json::get $tour tour id {}]
  if {$idTour eq {}} { return }
  if {$x eq {}} {
    set x [winfo rootx $wid]
    set y [expr {[winfo rooty $wid] + [winfo height $wid] + 2}]
  } else {
    incr x 12 ; incr y 12
  }
  set carteNom $nom
  set id [idJoueur $nom]
  set cle "$idTour,$id"
  dessinerCarte $nom $x $y {}
  if {[info exists carteCache($cle)] && [clock seconds] - [lindex $carteCache($cle) 0] < 60} {
    dessinerCarte $nom $x $y [lindex $carteCache($cle) 1]
    return
  }
  lireJson "$api/broadcast/$idTour/players/$id" [list ::moderne::direct::carteRecue $cle $nom $x $y]
}

proc ::moderne::direct::carteRecue {cle nom x y v} {
  variable carteCache
  variable carteNom
  if {$v eq {} || [catch {::moderne::json::get $v name {}} n] || $n eq {}} { set v {} }
  if {$v ne {}} { set carteCache($cle) [list [clock seconds] $v] }
  if {$carteNom eq $nom && [winfo exists .carteJoueur]} {
    dessinerCarte $nom $x $y $v [expr {$v eq {} ? [messageErreur [T "Pas de fiche pour cette personne." "No card for this player."]] : {}}]
  }
}

proc ::moderne::direct::points {p} {
  switch -- $p { 1/2 - 0.5 { return ½ } {} { return {} } default { return $p } }
}

proc ::moderne::direct::diffTexte {d} {
  if {![string is integer -strict $d] || $d == 0} { return {} }
  return [expr {$d > 0 ? "▲ +$d" : "▼ $d"}]
}

proc ::moderne::direct::dessinerCarte {nom x y v {msg {}}} {
  variable tour
  set c .carteJoueur
  set fond [::moderne::c surface]
  set doux [::moderne::c texteDoux]
  set vert #6fb86f ; set rouge #e0605a
  if {![winfo exists $c]} {
    toplevel $c -background [::moderne::c bordure] -padx 1 -pady 1
    wm overrideredirect $c 1
    catch {wm attributes $c -topmost 1}
    bind $c <Leave> {::moderne::direct::survolFin}
    bind $c <Enter> {catch {after cancel $::moderne::direct::fermerAfter}}
  }
  foreach e [winfo children $c] { destroy $e }
  set f [frame $c.f -background $fond -padx 12 -pady 10]
  pack $f -fill both -expand 1
  # header: photo, title and name, team, rating, score
  set h [frame $f.h -background $fond]
  set titre [::moderne::json::get $v title {}]
  # (photo only when there is one: no empty square)
  catch {
    if {[::moderne::avatars::photo $nom 64] ne {}} {
      ::moderne::avatars::creer $h.av 64
      $h.av configure -background $fond ; $h.av.i configure -background $fond
      ::moderne::avatars::maj $h.av $nom $titre 64
      pack $h.av -side left -anchor n -padx {0 12}
    }
  }
  set d [frame $h.d -background $fond]
  set l1 [frame $d.l1 -background $fond]
  if {$titre ne {}} { label $l1.t -text $titre -font font_Bold -foreground #d59020 -background $fond ; pack $l1.t -side left -padx {0 5} }
  label $l1.ch -font font_Bold -foreground #d4a017 -background $fond
  if {![catch {::moderne::avatars::marqueChampion $l1.ch $nom} ch] && $ch} { pack $l1.ch -side left -padx {0 5} }
  label $l1.n -text $nom -font font_Bold -foreground [::moderne::c texteFort] -background $fond
  pack $l1.n -side left
  pack $l1 -side top -anchor w
  if {$v eq {}} {
    label $d.att -text [expr {$msg ne {} ? $msg : [T "Chargement…" "Loading…"]}] -font font_Regular -foreground $doux -background $fond \
        -wraplength 320 -justify left
    pack $d.att -side top -anchor w
  } else {
    set equipe [::moderne::json::get $v team {}]
    if {$equipe ne {}} { label $d.eq -text $equipe -font font_Regular -foreground [::moderne::c texte] -background $fond ; pack $d.eq -side top -anchor w }
    set l3 [frame $d.l3 -background $fond]
    set bits {}
    foreach k {fed rating} { set x3 [::moderne::json::get $v $k {}] ; if {$x3 ne {}} { lappend bits $x3 } }
    label $l3.a -text [join $bits "  "] -font font_Regular -foreground [::moderne::c texte] -background $fond
    pack $l3.a -side left
    set diff {}
    foreach k [list standard rapid blitz] { set z [::moderne::json::get $v ratingDiffs $k {}] ; if {$z ne {}} { set diff $z ; break } }
    if {[diffTexte $diff] ne {}} {
      label $l3.d -text [diffTexte $diff] -font font_Regular -foreground [expr {$diff > 0 ? $vert : $rouge}] -background $fond
      pack $l3.d -side left -padx {8 0}
    }
    pack $l3 -side top -anchor w -pady {2 0}
    # (the online accounts from Gaby's table, as in Prepare: links)
    catch {
      lassign [::moderne::enligne::comptesJoueur $nom [::moderne::json::get $v fideId {}]] li cc
      if {$li ne {} || $cc ne {}} {
        set l4 [frame $d.l4 -background $fond]
        foreach {site compte url} [list Lichess $li "https://lichess.org/@/$li" Chess.com $cc "https://www.chess.com/member/$cc"] {
          if {$compte eq {}} { continue }
          label $l4.s$site -text "$site " -font font_Small -foreground $doux -background $fond
          label $l4.c$site -text $compte -font font_Small -foreground [::moderne::c lien] -background $fond -cursor hand2
          bind $l4.c$site <Button-1> [list openURL $url]
          pack $l4.s$site $l4.c$site -side left
          label $l4.e$site -text "   " -background $fond
          pack $l4.e$site -side left
        }
        pack $l4 -side top -anchor w -pady {2 0}
      }
    }
    set sc [::moderne::json::get $v score {}]
    set joue [::moderne::json::get $v played {}]
    set perf {}
    foreach k {standard rapid blitz} { set z [::moderne::json::get $v performances $k {}] ; if {$z ne {}} { set perf $z ; break } }
    set rang [::moderne::json::get $v rank {}]
    set tuiles {}
    if {$sc ne {}} {
      set t [demi $sc] ; if {$joue ne {}} { append t " / $joue" }
      lappend tuiles $t [T Points Points]
    }
    if {$perf ne {}} { lappend tuiles $perf [T Perf. Perf.] }
    if {$rang ne {}} { lappend tuiles $rang [T Rang Rank] }
    if {[llength $tuiles]} {
      set ts [frame $d.sc -background $fond]
      set k 0
      foreach {val lib} $tuiles {
        set tf [frame $ts.t$k -background $fond]
        label $tf.v -text $val -font font_Bold -foreground [::moderne::c texteFort] -background $fond
        label $tf.l -text $lib -font font_Small -foreground $doux -background $fond
        pack $tf.v $tf.l -side top -anchor w
        pack $tf -side left -padx {0 18}
        incr k
      }
      pack $ts -side top -anchor w -pady {6 0}
    }
  }
  pack $d -side left -anchor n
  pack $h -side top -anchor w -fill x
  # games of the tournament
  set g [frame $f.g -background $fond]
  set rondes [::moderne::json::get $tour rounds {}]
  set i 0
  foreach p [::moderne::json::get $v games {}] {
    set rid [::moderne::json::get $p round {}]
    set gid [::moderne::json::get $p id {}]
    set num ?
    set k 0
    foreach r $rondes { incr k ; if {[::moderne::json::get $r id {}] eq $rid} { set num $k ; break } }
    set adv [::moderne::json::get $p opponent {}]
    set pts [points [::moderne::json::get $p points {}]]
    set rd [::moderne::json::get $p ratingDiff {}]
    set ligne [list \
        $num $doux \
        [expr {[::moderne::json::get $p color white] eq "white" ? "○" : "●"}] [::moderne::c texte] \
        [string trim "[::moderne::json::get $adv title {}] [::moderne::json::get $adv name ?]"] [::moderne::c texteFort] \
        [::moderne::json::get $adv fed {}] $doux \
        [::moderne::json::get $adv rating {}] $doux \
        [expr {$pts eq {} ? "●" : $pts}] [expr {$pts eq "1" ? $vert : $pts eq "0" ? $rouge : $pts eq {} ? [::moderne::c accent] : [::moderne::c texte]}] \
        [diffTexte $rd] [expr {[string is integer -strict $rd] && $rd > 0 ? $vert : $rouge}]]
    set col 0
    set ws {}
    set fl [expr {$i % 2 ? [::moderne::c ligneAlt] : $fond}]
    foreach {txt coul} $ligne {
      # (the colour played: two drawn circles of the same size; the
      # characters ○ and ● differ in size, Yosha 2026-11-02)
      if {$col == 1} {
        set lb [pastille $g.c${i}_$col [expr {$txt eq "○" ? "blanc" : "noir"}] $fl]
        grid $lb -row $i -column $col -sticky we
        lappend ws $lb
        incr col
        continue
      }
      # (one font for every column; the result, or the live dot, centred)
      set lb [label $g.c${i}_$col -text $txt -font font_Regular -foreground $coul -background $fl \
          -anchor [expr {$col == 2 ? "w" : ($col == 5 ? "center" : "e")}] -padx 6 -pady 2 -cursor hand2]
      if {$col == 2} { $lb configure -anchor w }
      grid $lb -row $i -column $col -sticky [expr {$col == 2 ? "we" : "we"}]
      lappend ws $lb
      incr col
    }
    foreach lb $ws {
      bind $lb <Enter> [list ::moderne::direct::surligner $ws 1]
      bind $lb <Leave> [list ::moderne::direct::surligner $ws 0 $fl]
      bind $lb <Button-1> [list ::moderne::direct::suivrePartieDe $rid $gid]
    }
    incr i
  }
  grid columnconfigure $g 2 -weight 1
  if {$i} { pack $g -side top -fill x -pady {10 0} }
  update idletasks
  # inside the screen
  set lw [winfo reqwidth $c] ; set lh [winfo reqheight $c]
  set x [expr {min($x, [winfo screenwidth .] - $lw - 4)}]
  if {$y + $lh > [winfo screenheight .] - 4} { set y [expr {max(4, $y - $lh - 30)}] }
  wm geometry $c +$x+$y
  raise $c
}

proc ::moderne::direct::surligner {ws dedans {base {}}} {
  if {$base eq {}} { set base [::moderne::c surface] }
  set fond [expr {$dedans ? [::moderne::c survol] : $base}]
  variable pastilles
  foreach lb $ws {
    catch {$lb configure -background $fond}
    # (the circle image carries its background: redrawn on the new one)
    if {[info exists pastilles($lb)]} {
      lassign $pastilles($lb) d remplissage
      catch {$lb configure -image [rondLisse $d $remplissage #8a8a8a $fond]}
    }
  }
}

### Follow a game of the tournament, loading its round first if needed
proc ::moderne::direct::suivrePartieDe {rid gid} {
  variable ronde
  variable parties
  variable tour
  variable aSuivre
  catch {destroy .carteJoueur}
  if {$rid eq $ronde && [info exists parties($gid)]} {
    after idle [list ::moderne::direct::suivre $gid]
    return
  }
  set enCours 0
  foreach r [::moderne::json::get $tour rounds {}] {
    if {[::moderne::json::get $r id {}] eq $rid} { set enCours [::moderne::json::get $r ongoing 0] }
  }
  set aSuivre $gid
  chargerRonde $rid $enCours
}

################################################################################
### Any game with move times ([%clk], Gaby, Lichess, broadcasts): the players
### and their clocks above and below the board, following the move shown
### (like Lichess); without times, the names only. The live view has its
### own bands (bandes), a game against an engine its own clocks.
################################################################################

################################################################################
### The players' bands above and below the board, as wide as the board and
### its bars (one block: band, board, band, like Lichess; for a stream, a
### capture cut around it shows nothing else, Yosha 2026-11-09), on their
### own background. The navigation arrows: never under the board (room for
### a larger board); an option, off by default (the keyboard), puts them at
### the bottom of the notation panel (Yosha 2026-11-09).
################################################################################

namespace eval ::moderne::bandeau {}
if {![info exists ::moderne::flechesNav]} { set ::moderne::flechesNav 0 }

proc ::moderne::bandeau::couleur {} { return [::moderne::c surface2] }

### Fonts of the bands: the name and rating a little larger than the text
proc ::moderne::bandeau::polices {} {
  foreach {f base plus} {font_BandeNom font_Bold 2 font_BandeElo font_Regular 2} {
    set a [font actual $base]
    set t [dict get $a -size]
    dict set a -size [expr {$t < 0 ? $t - $plus - 1 : $t + $plus}]
    if {[lsearch -exact [font names] $f] < 0} { font create $f {*}$a } else { font configure $f {*}$a }
  }
}

### Band f: its background; the labels on it take its colour, the clock
### keeps its box
proc ::moderne::bandeau::habiller {f} {
  set c [couleur]
  $f configure -background $c
  foreach w [concat [winfo children $f] [expr {[winfo exists $f.j] ? [winfo children $f.j] : {}}]] {
    if {[string match *.clk $w]} { continue }
    catch {$w configure -background $c}
    catch {$w.i configure -background $c}
  }
}

### The bands as wide as the board block: from the left of the left bar
### (or the board) to the right of the right bar (or the board)
proc ::moderne::bandeau::aligner {} {
  if {![winfo exists .main.board.bd]} { return }
  set g {} ; set d {}
  foreach w {.main.board.barreg .main.board.bd .main.board.barred} {
    if {![winfo exists $w] || ![winfo ismapped $w]} { continue }
    # (a bar with nothing drawn, no engine yet: not part of the block)
    if {$w ne ".main.board.bd" && ![llength [$w find all]]} { continue }
    set x [winfo x $w]
    if {$g eq {} || $x < $g} { set g $x }
    set xd [expr {$x + [winfo width $w]}]
    if {$d eq {} || $xd > $d} { set d $xd }
  }
  if {$g eq {} || [winfo width .main.board.bd] < 50} { return }
  set g [expr {[winfo x .main.board] + $g}]
  set d [expr {[winfo width .main] - ([winfo x .main.board] + $d)}]
  if {$d < 0} { set d 0 }
  if {$g < 0} { set g 0 }
  foreach b {clkHaut clkBas liveHaut liveBas} {
    set f .main.$b
    if {![winfo exists $f] || [winfo manager $f] ne "grid"} { continue }
    if {[dict get [grid info $f] -padx] ne [list $g $d]} { grid configure $f -padx [list $g $d] }
  }
}

proc ::moderne::bandeau::suivre {} {
  variable suivi
  if {[info exists suivi]} { return }
  set suivi 1
  foreach w {.main.board .main.board.bd} {
    if {[winfo exists $w]} { bind $w <Configure> {+after cancel ::moderne::bandeau::aligner ; after idle ::moderne::bandeau::aligner} }
  }
  # (an engine's bar drawn, or emptied: the block widens or narrows)
  catch {trace add execution ::moderne::barres::redessiner leave {apply {args {
    after cancel ::moderne::bandeau::aligner ; after idle ::moderne::bandeau::aligner
  }}}}
}

### The arrows shown or not (option; the old "buttons" setting too)
proc ::moderne::bandeau::flechesVoulues {} {
  if {!$::moderne::flechesNav} { return 0 }
  if {[info exists ::gameInfo(showButtons)] && !$::gameInfo(showButtons)} { return 0 }
  return 1
}

### Options › Navigation arrows: put at once where they go
proc ::moderne::bandeau::basculerFleches {} {
  catch {grid remove .main.button}
  navNotation
}

### The arrows at the bottom of the notation panel, if wanted
proc ::moderne::bandeau::navNotation {} {
  set w .pgnWin
  if {![winfo exists $w.text]} { return }
  set nav $w.navSiby
  if {![flechesVoulues]} { catch {destroy $nav} ; return }
  if {[winfo exists $nav]} { return }
  frame $nav -background [::moderne::c fond]
  foreach {n txt cmd} {debut ⏮ ::move::Start arr ◀ ::move::Back av ▶ ::move::Forward fin ⏭ ::move::End} {
    ttk::button $nav.$n -text $txt -width 3 -style Toolbutton \
        -command "$cmd ; catch {if {\[::moderne::direct::vueOuverte\]} { ::moderne::direct::majPanneau }}"
    pack $nav.$n -side left
  }
  pack $nav -side bottom -pady 2 -before $w.text
}

namespace eval ::moderne::horloges {}

### Clock of each side at ply m: its last [%clk] up to there (before its
### first move: the time of that first move)
proc ::moderne::horloges::aLaPosition {vals m} {
  set cb {} ; set cn {} ; set pb {} ; set pn {}
  foreach {num v} $vals {
    set ply [expr {int(round(($num - 0.5) * 2))}]
    set blanc [expr {$ply % 2 == 1}]
    if {$blanc && $pb eq {}} { set pb $v }
    if {!$blanc && $pn eq {}} { set pn $v }
    if {$ply > $m} { continue }
    if {$blanc} { set cb $v } else { set cn $v }
  }
  if {$cb eq {}} { set cb $pb }
  if {$cn eq {}} { set cn $pn }
  set r {}
  foreach x [list $cb $cn] {
    lappend r [expr {$x eq {} ? {} : [::moderne::direct::hms [::moderne::direct::secondes $x]]}]
  }
  return $r
}

proc ::moderne::horloges::retirer {} {
  if {![winfo exists .main.clkHaut]} { return }
  catch {destroy .main.clkHaut}
  catch {destroy .main.clkBas}
  # (never under the board)
  catch {grid remove .main.button}
}

proc ::moderne::horloges::creer {} {
  catch {::moderne::pendule::polices}
  ::moderne::bandeau::polices
  set fond [::moderne::bandeau::couleur]
  foreach b {clkHaut clkBas} {
    set f .main.$b
    frame $f -background $fond
    frame $f.j -background $fond
    # (as in the live view: photo, title, name, rating,
    # and the review's level of play; Yosha 2026-11-04)
    catch {::moderne::avatars::creer $f.j.avatar 43 ; pack $f.j.avatar -side left -padx {0 8} -pady 2}
    label $f.j.titre -font font_Bold -foreground #d59020 -background $fond
    # (the world champions' gold king, the women's world champions' gold
    # queen, after the title)
    label $f.j.champion -font font_BandeNom -foreground #d4a017 -background $fond
    label $f.j.nom -font font_BandeNom -foreground [::moderne::c texte] -background $fond
    label $f.j.elo -font font_BandeElo -foreground [::moderne::c texteDoux] -background $fond
    label $f.j.niveau -foreground [::moderne::c accent] -background $fond
    pack $f.j.titre $f.j.champion $f.j.nom $f.j.elo $f.j.niveau -side left -padx {0 6}
    label $f.clk -font font_PenduleDixiemes -width 8 -anchor e -padx 10 -pady 0 \
        -foreground [::moderne::c texte] -background [::moderne::c champ]
    grid columnconfigure $f 0 -weight 1
    grid $f.j -row 0 -column 0 -sticky w -padx {4 0} -pady 2
    grid $f.clk -row 0 -column 2 -sticky e -padx {0 4} -pady 4
    ::moderne::bandeau::habiller $f
  }
  catch {unset ::moderne::horloges::photoCachee}
  grid .main.clkHaut -row 1 -column 0 -sticky we -padx 5 -pady {4 0}
  grid .main.clkBas -row 3 -column 0 -sticky new -padx 5 -pady {0 4}
  ::moderne::bandeau::suivre
  after idle ::moderne::bandeau::aligner
  placerBoutons
}

### The navigation arrows: never under the board (option: in the notation)
proc ::moderne::horloges::placerBoutons {} {
  catch {grid remove .main.button}
  catch ::moderne::bandeau::navNotation
}

proc ::moderne::horloges::maj {} {
  if {![winfo exists .main.board]} { return }
  # (live view: its bands; a game against an engine: its clocks)
  if {[::moderne::direct::vueOuverte] || [winfo exists .main.liveHaut] ||
      ([llength [info commands ::moderne::jeu::actif]] && [::moderne::jeu::actif])} {
    retirer
    return
  }
  set vals {}
  catch {set vals [sc_game values clk]}
  # (the players' names for every game, the clocks only with move times:
  # the names were missing without times, and the board changed size from
  # one game to the next, Yosha 2026-11-03)
  if {![winfo exists .main.clkHaut]} { creer }
  set cb {} ; set cn {}
  if {[llength $vals]} { lassign [aLaPosition $vals [sc_pos location]] cb cn }
  set retourne 0
  catch {set retourne [::board::isFlipped .main.board]}
  # (the game's year: a card found by the name's look only if they could
  # have played then)
  set ::moderne::avatars::anneePartie {}
  catch {regexp {^([0-9]{4})} [sc_game info date] -> ::moderne::avatars::anneePartie}
  foreach {b c} [list clkHaut [expr {$retourne ? "B" : "N"}] clkBas [expr {$retourne ? "N" : "B"}]] {
    set f .main.$b
    set nom [sc_game info [expr {$c eq "B" ? "white" : "black"}]]
    set elo {}
    catch {set elo [sc_game tags get [expr {$c eq "B" ? "WhiteElo" : "BlackElo"}]]}
    if {$nom eq "?"} { set nom {} }
    # (an Alter Ego: the real player's photo and title, "Carlsen · Alter Ego
    # 2013" shown)
    set ae {}
    catch {set ae [::moderne::alterego::joueur [expr {$c eq "B" ? "White" : "Black"}]]}
    if {$ae ne {}} {
      $f.j.nom configure -text [lindex $ae 1]
      set nom [lindex $ae 0]
    } else {
      $f.j.nom configure -text $nom
    }
    $f.j.elo configure -text [expr {[string is integer -strict $elo] && $elo > 0 ? $elo : {}}]
    set coul [expr {$c eq "B" ? "White" : "Black"}]
    set titre {} ; set niv {} ; set src {}
    foreach {t v} [sc_game tags get Extra] {
      if {$t eq "${coul}Title"} { set titre $v }
      if {$t eq "${coul}Level"} { set niv $v }
      if {$t eq "${coul}LevelSource" && $v eq "moves"} { set src a }
    }
    if {$titre eq {} && $nom ne {}} { catch {set titre [::moderne::avatars::titreFide $nom]} }
    if {$titre in {WC WWC}} { set titre {} }
    if {[winfo exists $f.j.titre]} {
      $f.j.titre configure -text $titre
      catch {set ch [::moderne::avatars::marqueChampion $f.j.champion $nom font_BandeNom] ; pack configure $f.j.champion -padx [expr {$ch ? {0 6} : 0}]}
      catch {
        # (no name, or no players' pack on this computer: no empty square)
        if {$nom eq {} || [::moderne::avatars::photo $nom 43] eq {}} {
          pack forget $f.j.avatar
        } else {
          if {![winfo ismapped $f.j.avatar] && [lsearch [pack slaves $f.j] $f.j.avatar] < 0 &&
              ![info exists ::moderne::horloges::photoCachee([winfo name $f])]} {
            pack $f.j.avatar -side left -padx {0 8} -pady 2 -before $f.j.titre
          }
          ::moderne::avatars::maj $f.j.avatar $nom $titre 43
        }
      }
      $f.j.niveau configure -text [expr {[string is integer -strict $niv] ? [::moderne::niveau::affiche $niv 1 $src] : {}}]
    }
    set t [expr {$c eq "B" ? $cb : $cn}]
    # (the box as wide as the digits shown: no empty hours, Yosha 2026-11-09)
    $f.clk configure -text $t -width [string length $t]
    # (no time: the clock's box hidden, its row kept)
    $f.clk configure -background [expr {$t eq {} ? [::moderne::bandeau::couleur] : [::moderne::c champ]}]
  }
  # (the year only for these rows: other cards keep no date check)
  set ::moderne::avatars::anneePartie {}
  # (no arrows under the board; in the notation if wanted)
  if {[winfo manager .main.button] ne {}} { placerBoutons }
  catch ::moderne::bandeau::navNotation
  after idle ::moderne::bandeau::aligner
}

trace add execution updateBoard leave {apply {args { catch ::moderne::horloges::maj }}}
# (the board turned round: the players above and below swap too, the
# player with Black below when Black is below; Yosha 2026-11-06)
trace add execution ::board::flip leave {apply {{cmd args} {
  if {[lindex $cmd 1] ne ".main.board"} { return }
  catch ::moderne::horloges::maj
  catch {if {[::moderne::direct::vueOuverte]} { ::moderne::direct::majPanneau }}
}}}

### A small circle for the colour played: light with a grey ring (White),
### dark with a grey ring (Black), both the same size. Drawn as a smoothed
### image: Tk on Windows draws small canvas ovals without smoothing, which
### look like cogs (Yosha 2026-11-04).
proc ::moderne::direct::pastille {c couleur fond} {
  set d [expr {max(9, [font metrics font_Regular -linespace] / 2)}]
  set img [::moderne::direct::rondLisse $d [expr {$couleur eq "blanc" ? "#f0f0f0" : "#1a1a1a"}] #8a8a8a $fond]
  label $c -image $img -background $fond -borderwidth 0 -padx 6 -pady 2 -cursor hand2
  variable pastilles
  set pastilles($c) [list $d [expr {$couleur eq "blanc" ? "#f0f0f0" : "#1a1a1a"}]]
  bind $c <Destroy> [list unset -nocomplain ::moderne::direct::pastilles($c)]
  return $c
}

### A photo image of a disc of diameter d (fill, a 1 px ring, background
### fond), with 4x4 supersampling; one image per set of arguments
proc ::moderne::direct::rondLisse {d remplissage contour fond} {
  variable ronds
  set cle [list $d $remplissage $contour $fond]
  if {[info exists ronds($cle)] && [lsearch -exact [image names] $ronds($cle)] >= 0} { return $ronds($cle) }
  set rgb {}
  foreach coul [list $remplissage $contour $fond] {
    lassign [winfo rgb . $coul] r g b
    lappend rgb [list [expr {$r / 257}] [expr {$g / 257}] [expr {$b / 257}]]
  }
  lassign $rgb cR cA cF
  set ray [expr {$d / 2.0}]
  set interieur [expr {$ray - 1.0}]
  set lignes {}
  for {set y 0} {$y < $d} {incr y} {
    set ligne {}
    for {set x 0} {$x < $d} {incr x} {
      set nR 0 ; set nA 0
      for {set sy 0} {$sy < 4} {incr sy} {
        for {set sx 0} {$sx < 4} {incr sx} {
          set dx [expr {$x + ($sx + 0.5) / 4.0 - $ray}]
          set dy [expr {$y + ($sy + 0.5) / 4.0 - $ray}]
          set r [expr {hypot($dx, $dy)}]
          if {$r <= $interieur} { incr nR } elseif {$r <= $ray} { incr nA }
        }
      }
      set nF [expr {16 - $nR - $nA}]
      set px "#"
      foreach i {0 1 2} {
        append px [format %02x [expr {round(([lindex $cR $i] * $nR + [lindex $cA $i] * $nA + [lindex $cF $i] * $nF) / 16.0)}]]
      }
      lappend ligne $px
    }
    lappend lignes $ligne
  }
  set img [image create photo -width $d -height $d]
  $img put $lignes
  set ronds($cle) $img
  return $img
}
