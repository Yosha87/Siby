
###
### Siby: a player's online games (Lichess, Chess.com)
###
### For preparation: the player's online games are downloaded through the
### public APIs (no account needed) and stored in a separate database
### (data/enligne/<joueur>.si4 in the SCID folder), never in the main
### reference database (Gaby). Account names are replaced by the
### player's name so that the preparation finds them with the player's games;
### the time control is computed from the clock (as on Lichess: base time
### + 40 × increment) and recorded with flags 1 / 2 / 3 (classical,
### rapid, blitz). Bullet, correspondence games and variants are
### left out.
###
### Downloading uses the curl program (present on Linux and in
### Windows 10 and later), without blocking the interface.
###

namespace eval ::moderne::enligne {
  # The whole history is downloaded (all the Lichess games, all the
  # Chess.com months); what was downloaded is kept in data/enligne/cache,
  # so the next times only the new games come (Lichess "since", Chess.com
  # months already ended are not asked again)
  variable maxLichess 0          ;# 0: all the Lichess games (else the most recent n)
  variable moisChesscom 0        ;# 0: all the Chess.com months (else the last n)
  variable bases                 ;# bases(file) = number of the open database
  array set bases {}
  variable comptes               ;# comptes(name) = {lichess chesscom}
  array set comptes {}
  variable charge 0
  variable dl                    ;# download in progress
  array set dl {}
}

proc ::moderne::enligne::T {fr en} { return [::moderne::tr $fr $en] }

proc ::moderne::enligne::dossier {} {
  set d [file join $::scidUserDir data enligne]
  file mkdir $d
  return $d
}

proc ::moderne::enligne::slug {nom} {
  regsub -all {[^[:alnum:]_-]+} [string trim $nom] _ s
  return [string trim $s _]
}

### Is f (a database file, with or without .si4) a player's online games
### database? (kept for the preparation only: not in My databases)
proc ::moderne::enligne::estBaseEnLigne {f} {
  set d [file normalize [file join $::scidUserDir data enligne]]
  string equal -nocase [file dirname [file normalize $f]] $d
}

### Is f the database of the user's own online games (Options › My
### profile)? It is in My databases, as "My online games" (a user: "it finds
### my online games, but I don't see them in any database", 2026-11-17)
proc ::moderne::enligne::estMaBase {f} {
  if {![info exists ::moderne::profilNom] || [string trim $::moderne::profilNom] eq {}} { return 0 }
  set f [file normalize $f]
  if {[string match -nocase *.si4 $f]} { set f [file rootname $f] }
  string equal -nocase $f [file normalize [fichierBase $::moderne::profilNom]]
}

proc ::moderne::enligne::fichierBase {nom} {
  return [file join [dossier] [slug $nom]]
}

################################################################################
### Online accounts remembered per player
################################################################################

proc ::moderne::enligne::chargerComptes {} {
  variable comptes
  variable charge
  if {$charge} { return }
  set charge 1
  set f [file join [dossier] comptes.txt]
  if {![file exists $f]} { return }
  catch {
    set c [open $f r]
    fconfigure $c -encoding utf-8
    while {[gets $c l] >= 0} {
      lassign [split $l \t] nom li cc
      if {$nom ne {}} { set comptes($nom) [list $li $cc] }
    }
    close $c
  }
}

### A player's online accounts {lichess chesscom}: the ones typed for them
### before, else those of Gaby's players pack (comptes_en_ligne.tsv, by
### FIDE id: the player card's, else the FideId of their games in base b)
proc ::moderne::enligne::comptesDe {nom {b {}}} {
  variable comptes
  chargerComptes
  if {[info exists comptes($nom)]} { return $comptes($nom) }
  return [comptesGaby $nom $b]
}

### Gaby's table: fide_id chesscom lichess source verifie (read once,
### again when the pack changes)
proc ::moderne::enligne::chargerGaby {} {
  variable gaby
  variable gabyFichier
  set f {}
  catch {set f [file join [::moderne::avatars::dossier] comptes_en_ligne.tsv]}
  if {$f eq {} || ![file exists $f]} { array unset gaby ; set gabyFichier {} ; return 0 }
  set cle "$f [file mtime $f]"
  if {[info exists gabyFichier] && $gabyFichier eq $cle} { return 1 }
  array unset gaby
  set gabyFichier $cle
  catch {
    set c [open $f r]
    fconfigure $c -encoding utf-8
    gets $c
    while {[gets $c l] >= 0} {
      lassign [split $l \t] id cc li source verifie
      if {$id ne {}} { set gaby($id) [list $li $cc $source $verifie] }
    }
    close $c
  }
  return 1
}

proc ::moderne::enligne::comptesGaby {nom {b {}}} {
  variable gaby
  if {$nom eq {} || ![chargerGaby]} { return {{} {}} }
  set id {}
  catch {
    set f [::moderne::avatars::fiche $nom]
    if {$f ne {} && [dict exists $f fide_id]} { set id [dict get $f fide_id] }
  }
  if {($id eq {} || $id eq "null") && $b ne {} && $b > 0} { catch {set id [::moderne::fide::idNom $b $nom]} }
  if {$id eq {} || $id eq "null" || ![info exists gaby($id)]} { return {{} {}} }
  return [lrange $gaby($id) 0 1]
}

### {lichess chesscom} of the player of FIDE id id in Gaby's table, else of
### name nom (the accounts noted by the user first)
proc ::moderne::enligne::comptesJoueur {nom {id {}}} {
  variable comptes
  variable gaby
  chargerComptes
  if {[info exists comptes($nom)]} { return $comptes($nom) }
  if {$id ne {} && $id ne "null" && [chargerGaby] && [info exists gaby($id)]} { return [lrange $gaby($id) 0 1] }
  return [comptesGaby $nom]
}

proc ::moderne::enligne::noterComptes {nom li cc} {
  variable comptes
  chargerComptes
  set comptes($nom) [list $li $cc]
  catch {
    set c [open [file join [dossier] comptes.txt] w]
    fconfigure $c -encoding utf-8
    foreach n [lsort [array names comptes]] {
      puts $c "$n\t[lindex $comptes($n) 0]\t[lindex $comptes($n) 1]"
    }
    close $c
  }
}

################################################################################
### Database of a player's online games
################################################################################

### Number of the database of this player's online games (opened if needed),
### 0 if there is none
proc ::moderne::enligne::base {nom} {
  variable bases
  set f [fichierBase $nom]
  if {[info exists bases($f)] && [sc_base inUse $bases($f)] &&
      [file rootname [sc_base filename $bases($f)]] eq [file normalize $f]} {
    return $bases($f)
  }
  # (opened by the user from My databases, not by this namespace: that
  # slot; "already opened" made the update fail)
  set s 0
  catch {set s [::moderne::mesbases::slot [::moderne::mesbases::chemin $f]]}
  if {$s} { set bases($f) $s ; return $s }
  if {![file exists $f.si4]} { return 0 }
  set courante [sc_base current]
  if {[catch {sc_base open $f} b]} { return 0 }
  if {$courante != [sc_base current]} { sc_base switch $courante }
  set bases($f) $b
  catch {::windows::switcher::Refresh}
  return $b
}

################################################################################
### Download (asynchronous, through curl)
################################################################################

### Reads the URL and calls "suite donnees" at the end (donnees empty in case
### of error)
proc ::moderne::enligne::lire {url accept suite {duree 120}} {
  set cmd [list curl -sSL --max-time $duree -A "Siby (preparation)"]
  if {$accept ne {}} { lappend cmd -H "Accept: $accept" }
  lappend cmd $url
  if {[catch {set p [open "|$cmd" r]} err]} {
    uplevel #0 [concat $suite [list {}]]
    return
  }
  fconfigure $p -translation binary -blocking 0
  set ::moderne::enligne::tampon($p) {}
  fileevent $p readable [list ::moderne::enligne::morceau $p $suite]
}

proc ::moderne::enligne::morceau {p suite} {
  variable tampon
  append tampon($p) [read $p]
  if {![eof $p]} {
    # Progress: games already received (Lichess streams the games, most
    # recent first: the date of the last one says how far back it is)
    set date {}
    set i [string last {[UTCDate "} $tampon($p)]
    if {$i < 0} { set i [string last {[Date "} $tampon($p)] }
    if {$i >= 0} { regexp {"([0-9]{4})\.([0-9]{2})} [string range $tampon($p) $i [expr {$i + 24}]] -> an mois ; catch {set date "$mois/$an"} }
    progres [regexp -all {\[Event } $tampon($p)] $date
    return
  }
  fileevent $p readable {}
  catch {close $p}
  set d [encoding convertfrom utf-8 $tampon($p)]
  unset tampon($p)
  uplevel #0 [concat $suite [list $d]]
}

### Downloads the online games of player nom (Lichess and/or
### Chess.com accounts); "fin message nbParties" is called at the end
### Progress text sent to dl(progres): "Lichess: 120 / 300
### games", "Chess.com: month 3 / 12 (85 games)"
proc ::moderne::enligne::progres {nbRecues {date {}}} {
  variable dl
  if {![info exists dl(progres)] || $dl(progres) eq {}} { return }
  if {$dl(etape) eq "lichess"} {
    set t "Lichess : [::utils::thousands $nbRecues] [T "nouvelles parties" "new games"]"
    if {$date ne {}} { append t " ([T "remonté jusqu'à" "back to"] $date)" }
  } elseif {$dl(etape) eq "chesscom"} {
    set t "Chess.com : [T mois month] $dl(moisFait) / $dl(moisTotal) ([expr {$dl(nbChesscom) + $nbRecues}] [T parties games])"
  } else {
    set t "Chess.com : [T "liste des mois…" "list of months…"]"
  }
  catch {uplevel #0 [concat $dl(progres) [list $t]]}
}

### Cache of what was downloaded: one file per Lichess account, one per
### Chess.com account and month
proc ::moderne::enligne::fichierCache {nom} {
  set d [file join [dossier] cache]
  file mkdir $d
  regsub -all {[^[:alnum:]_-]+} [string tolower $nom] _ nom
  return [file join $d $nom.pgn]
}

proc ::moderne::enligne::lireFichier {f} {
  if {![file exists $f]} { return {} }
  set c [open $f r] ; fconfigure $c -encoding utf-8
  set t [read $c] ; close $c
  return $t
}

proc ::moderne::enligne::ecrireFichier {f texte {mode w}} {
  set c [open $f $mode] ; fconfigure $c -encoding utf-8
  puts -nonewline $c $texte ; close $c
}

proc ::moderne::enligne::finir {fin message nb} {
  variable occupe 0
  uplevel #0 [concat $fin [list $message $nb]]
}

### Lichess "since" (ms): just after the most recent game already kept
proc ::moderne::enligne::depuisLichess {texte} {
  set max 0
  foreach {- d h} [regexp -all -inline {\[UTCDate "([0-9.]+)"\]\s*\[UTCTime "([0-9:]+)"\]} $texte] {
    if {[catch {clock scan "$d $h" -format {%Y.%m.%d %H:%M:%S} -timezone :UTC} t]} { continue }
    if {$t > $max} { set max $t }
  }
  return [expr {$max ? ($max + 1) * 1000 : 0}]
}

### One download at a time (e.g. the daily update of My online games,
### profil.tcl): another one waits for it
namespace eval ::moderne::enligne { variable occupe 0 }
proc ::moderne::enligne::telecharger {nom lichess chesscom fin {progres {}}} {
  variable dl
  variable occupe
  variable occupeDepuis
  # (a download that never ended, an error on the way: freed after 2 hours)
  if {$occupe && [info exists occupeDepuis] && [clock seconds] - $occupeDepuis > 7200} { set occupe 0 }
  if {$occupe} {
    if {$progres ne {}} { catch {uplevel #0 [concat $progres [list [T "En attente d'un autre téléchargement…" "Waiting for another download…"]]]} }
    after 2000 [list ::moderne::enligne::telecharger $nom $lichess $chesscom $fin $progres]
    return
  }
  set occupe 1
  set occupeDepuis [clock seconds]
  noterComptes $nom $lichess $chesscom
  array unset dl
  set dl(nom) $nom
  set dl(lichess) [string trim $lichess]
  set dl(chesscom) [string tolower [string trim $chesscom]]
  set dl(fin) [list ::moderne::enligne::finir $fin]
  set dl(progres) $progres
  set dl(etape) {}
  set dl(moisFait) 0
  set dl(moisTotal) 0
  set dl(nbChesscom) 0
  set dl(pgn) {}
  set dl(messages) {}
  if {$dl(lichess) ne {}} {
    set u "https://lichess.org/api/games/user/$dl(lichess)?rated=true&perfType=blitz,rapid,classical&clocks=false&evals=false&opening=false"
    variable maxLichess
    if {$maxLichess > 0} { append u "&max=$maxLichess" }
    set depuis [depuisLichess [lireFichier [fichierCache lichess_$dl(lichess)]]]
    if {$depuis} { append u "&since=$depuis" }
    set dl(etape) lichess
    progres 0
    # (the whole history: up to an hour for very active accounts)
    lire $u application/x-chess-pgn ::moderne::enligne::finLichess 3600
  } else {
    chesscom
  }
}

proc ::moderne::enligne::finLichess {donnees} {
  variable dl
  set f [fichierCache lichess_$dl(lichess)]
  if {[string first {[Event } $donnees] >= 0} {
    ecrireFichier $f "[string trim $donnees]\n\n" a
  }
  set tout [lireFichier $f]
  if {[string first {[Event } $tout] < 0} {
    lappend dl(messages) "Lichess : [T "aucune partie (compte introuvable ou réseau indisponible)" "no games (unknown account or no network)"]"
  } else {
    lappend dl(pgn) [list lichess $dl(lichess) $tout]
  }
  chesscom
}

proc ::moderne::enligne::chesscom {} {
  variable dl
  if {$dl(chesscom) eq {}} { construire ; return }
  set dl(etape) archives
  progres 0
  lire "https://api.chess.com/pub/player/$dl(chesscom)/games/archives" application/json ::moderne::enligne::finArchives
}

proc ::moderne::enligne::finArchives {donnees} {
  variable dl
  set urls [regexp -all -inline {https://api\.chess\.com/pub/player/[^"]+/games/[0-9]{4}/[0-9]{2}} $donnees]
  if {![llength $urls]} {
    lappend dl(messages) "Chess.com : [T "aucune archive (compte introuvable ou réseau indisponible)" "no archives (unknown account or no network)"]"
    construire
    return
  }
  # every month; the months already ended and kept are read from the cache
  set dl(mois) {}
  set dl(moisCache) {}
  variable moisChesscom
  if {$moisChesscom > 0} { set urls [lrange $urls end-[expr {$moisChesscom - 1}] end] }
  set ceMois [clock format [clock seconds] -format %Y/%m -timezone :UTC]
  set moisPasse [clock format [clock add [clock seconds] -1 month] -format %Y/%m -timezone :UTC]
  foreach u $urls {
    regexp {([0-9]{4})/([0-9]{2})$} $u -> a m
    set f [fichierCache "chesscom_$dl(chesscom)_${a}_$m"]
    # (the month just ended too: games finished at midnight may come late)
    if {[file exists $f] && "$a/$m" ni [list $ceMois $moisPasse]} {
      lappend dl(moisCache) $f
    } else {
      lappend dl(mois) $u
    }
  }
  foreach f $dl(moisCache) {
    set t [lireFichier $f]
    if {[string first {[Event } $t] >= 0} {
      lappend dl(pgn) [list chesscom $dl(chesscom) $t]
      incr dl(nbChesscom) [regexp -all {\[Event } $t]
    }
  }
  set dl(moisTotal) [llength $dl(mois)]
  set dl(etape) chesscom
  moisSuivant
}

proc ::moderne::enligne::moisSuivant {} {
  variable dl
  if {![llength $dl(mois)]} { construire ; return }
  set u [lindex $dl(mois) end]
  set dl(mois) [lrange $dl(mois) 0 end-1]
  set dl(moisUrl) $u
  incr dl(moisFait)
  progres 0
  lire $u/pgn {} ::moderne::enligne::finMois
}

proc ::moderne::enligne::finMois {donnees} {
  variable dl
  # kept for the next times (not an empty answer: maybe a network failure)
  if {[regexp {([0-9]{4})/([0-9]{2})$} $dl(moisUrl) -> a m] && [string first {[Event } $donnees] >= 0} {
    catch {ecrireFichier [fichierCache "chesscom_$dl(chesscom)_${a}_$m"] $donnees}
  }
  if {[string first {[Event } $donnees] >= 0} {
    lappend dl(pgn) [list chesscom $dl(chesscom) $donnees]
    incr dl(nbChesscom) [regexp -all {\[Event } $donnees]
  }
  moisSuivant
}

################################################################################
### Building the database
################################################################################

### Time control from the clock "300+3": classical, rapid, blitz, or {}
### (bullet, correspondence, unknown)
proc ::moderne::enligne::cadence {tc} {
  if {![regexp {^([0-9]+)(?:\+([0-9]+))?$} $tc -> b i]} { return {} }
  if {$i eq {}} { set i 0 }
  set s [expr {$b + 40 * $i}]
  if {$s < 180} { return {} }
  if {$s < 480} { return blitz }
  if {$s < 1500} { return rapide }
  return classique
}

proc ::moderne::enligne::construire {} {
  variable dl
  # The games are prepared in slices (thousands of games: several seconds of
  # work), then the database is made
  set dl(parties) {}
  set dl(cles) {}
  set dl(cadences) {}
  set dl(n) 0
  set dl(ix) 0
  set dl(k) -1
  after idle ::moderne::enligne::construireTranche
}

proc ::moderne::enligne::construireTranche {} {
  variable dl
  if {![info exists dl(ix)]} { return }
  set nom $dl(nom)
  # (name used in a regular-expression substitution)
  set nomRe [string map {& \\& \\ \\\\} $nom]
  set fin [expr {[clock milliseconds] + 150}]
  while {$dl(ix) < [llength $dl(pgn)]} {
    lassign [lindex $dl(pgn) $dl(ix)] site compte texte
    if {$dl(k) < 0} {
      # A game = headers + moves; split before each "[Event"
      regsub -all {\r} $texte {} texte
      set dl(pgn) [lreplace $dl(pgn) $dl(ix) $dl(ix) [list $site $compte $texte]]
      set morceaux [regexp -all -inline -indices {(?:^|\n)\[Event } $texte]
      set debuts {}
      foreach m $morceaux { lappend debuts [expr {[lindex $m 0] == 0 ? 0 : [lindex $m 0] + 1}] }
      lappend debuts [string length $texte]
      set dl(debuts) $debuts
      set dl(k) 0
    }
    set debuts $dl(debuts)
    for {set k $dl(k)} {$k + 1 < [llength $debuts]} {incr k} {
      if {[clock milliseconds] > $fin} {
        set dl(k) $k
        after 1 ::moderne::enligne::construireTranche
        return
      }
      set partie [string range $texte [lindex $debuts $k] [expr {[lindex $debuts [expr {$k + 1}]] - 1}]]
      # Variants and non-standard starting positions: left out
      if {[regexp {\[Variant "([^"]*)"\]} $partie -> v] && ![string match -nocase standard $v]} { continue }
      if {[regexp {\[SetUp "1"\]} $partie]} { continue }
      set tc {}
      regexp {\[TimeControl "([^"]*)"\]} $partie -> tc
      set cad [cadence $tc]
      if {$cad eq {}} { continue }
      # (the game's own address before Site is rewritten: what tells a
      # game already in the user's database, see construireBase)
      set cle {}
      if {![regexp {\[Link "([^"]+)"\]} $partie -> cle]} { regexp {\[Site "(https?://[^"]+)"\]} $partie -> cle }
      if {$cle eq {}} {
        set x {}
        foreach t {White Black UTCDate UTCTime Date Result} { set v {} ; regexp "\\\[$t \"(\[^\"\]*)\"\\\]" $partie -> v ; lappend x $v }
        set cle [join $x |]
      }
      # The account becomes the player's name (for the preparation)
      set compteRe [string map {\\ \\\\ . \\. * \\* ? \\? + \\+ ( \\( ) \\) [ \\[ ] \\]} $compte]
      regsub -nocase "\\\[White \"$compteRe\"\\\]" $partie "\[White \"$nomRe\"\]" partie
      regsub -nocase "\\\[Black \"$compteRe\"\\\]" $partie "\[Black \"$nomRe\"\]" partie
      set siteTxt [expr {$site eq "lichess" ? "lichess.org" : "chess.com"}]
      regsub {\[Site "[^"]*"\]} $partie "\[Site \"$siteTxt\"\]" partie
      regsub {\[Event "([^"]*)"\]} $partie "\[Event \"$siteTxt : \\1\"\]" partie
      lappend dl(parties) [string trim $partie]
      lappend dl(cles) $cle
      lappend dl(cadences) $cad
      incr dl(n)
    }
    incr dl(ix)
    set dl(k) -1
  }
  unset dl(ix)
  construireBase
}

### The database of the games prepared by construireTranche
proc ::moderne::enligne::construireBase {} {
  variable dl
  set nom $dl(nom)
  set cadences $dl(cadences)
  set n $dl(n)
  set message [join $dl(messages) "\n"]
  if {$n == 0} {
    uplevel #0 [concat $dl(fin) [list $message 0]]
    return
  }
  set f [fichierBase $nom]
  # The user's own games (My profile, in My databases): only the new games
  # added, what was done in the others kept (built again, the database
  # lost the user's comments and analyses each time)
  if {[estMaBase $f] && [file exists $f.si4] && [file exists $f.cles]} {
    ajouterNouvelles $f $message
    return
  }
  set textes "[join $dl(parties) "\n\n"]\n\n"
  # New database (this player's previous one is replaced)
  variable bases
  # (open by the user meanwhile: that slot closed before the files go)
  catch {set s [::moderne::mesbases::slot [::moderne::mesbases::chemin $f]] ; if {$s} { set bases($f) $s }}
  if {[info exists bases($f)] && [sc_base inUse $bases($f)]} {
    catch {
      set c [sc_base current]
      sc_base switch $bases($f)
      sc_base close
      if {$c != $bases($f) && [sc_base inUse $c]} { sc_base switch $c }
    }
  }
  foreach e {.si4 .sg4 .sn4 .stc} { catch {file delete -force $f$e} }
  set pgnFichier $f.pgn
  set c [open $pgnFichier w]
  fconfigure $c -encoding utf-8
  puts -nonewline $c $textes
  close $c
  set courante [sc_base current]
  if {[catch {
    set b [sc_base create $f]
    sc_base import file $pgnFichier
    # Time-control flags, in import order
    set g 0
    foreach cad $cadences {
      incr g
      if {$g > [sc_base numGames $b]} { break }
      catch {sc_game flag [dict get {classique 1 rapide 2 blitz 3} $cad] $g 1}
    }
    catch {sc_game flag 1 setdescription Classic}
    catch {sc_game flag 2 setdescription Rapid}
    catch {sc_game flag 3 setdescription Blitz}
    set bases($f) $b
  } err]} {
    if {[sc_base inUse $courante]} { catch {sc_base switch $courante} }
    uplevel #0 [concat $dl(fin) [list "$message\n[T Erreur Error] : $err" 0]]
    return
  }
  set nb [sc_base numGames $b]
  if {[sc_base inUse $courante]} { sc_base switch $courante }
  catch {::windows::switcher::Refresh}
  catch {ecrireFichier $f.cles "[join $dl(cles) \n]\n"}
  uplevel #0 [concat $dl(fin) [list $message $nb]]
}

### The new games added to the user's database f (keys of the games
### already there in f.cles)
proc ::moderne::enligne::ajouterNouvelles {f message} {
  variable dl
  set connues [split [lireFichier $f.cles] \n]
  set deja [dict create]
  foreach c $connues { if {$c ne {}} { dict set deja $c 1 } }
  set nouvelles {} ; set cles {} ; set cads {}
  foreach p $dl(parties) c $dl(cles) cad $dl(cadences) {
    if {[dict exists $deja $c]} { continue }
    dict set deja $c 1
    lappend nouvelles $p ; lappend cles $c ; lappend cads $cad
  }
  set b [base $dl(nom)]
  if {!$b} {
    uplevel #0 [concat $dl(fin) [list "$message\n[T Erreur Error] : $f" 0]]
    return
  }
  if {[llength $nouvelles]} {
    set pgn $f.nouvelles.pgn
    ecrireFichier $pgn "[join $nouvelles "\n\n"]\n\n"
    set courante [sc_base current]
    if {[catch {
      sc_base switch $b
      set avant [sc_base numGames $b]
      sc_base import file $pgn
      set g $avant
      foreach cad $cads {
        incr g
        if {$g > [sc_base numGames $b]} { break }
        catch {sc_game flag [dict get {classique 1 rapide 2 blitz 3} $cad] $g 1}
      }
    } err]} {
      if {[sc_base inUse $courante]} { catch {sc_base switch $courante} }
      catch {file delete $pgn}
      uplevel #0 [concat $dl(fin) [list "$message\n[T Erreur Error] : $err" 0]]
      return
    }
    if {[sc_base inUse $courante]} { sc_base switch $courante }
    catch {file delete $pgn}
    ecrireFichier $f.cles "[join $cles \n]\n" a
    catch {::windows::switcher::Refresh}
    if {[sc_base current] == $b} { catch {::windows::gamelist::Refresh} ; catch updateBoard }
  }
  set dl(nouvelles) [llength $nouvelles]
  uplevel #0 [concat $dl(fin) [list $message [sc_base numGames $b]]]
}

################################################################################
### Downloaded games (File menu): the databases of the players' online
### games, like ChessBase's "MyPGNdownload" (never in Gaby, never in the
### clipbase)
################################################################################

proc ::moderne::enligne::fenetre {} {
  set w .telechargesWin
  if {[winfo exists $w]} { raise $w ; ::moderne::enligne::remplirFenetre ; return }
  toplevel $w
  wm title $w [T "Parties téléchargées (Lichess, Chess.com)" "Downloaded games (Lichess, Chess.com)"]
  set f [ttk::frame $w.f -padding 12]
  pack $f -fill both -expand 1
  ttk::label $f.intro -wraplength 560 -justify left -foreground [::moderne::c texteDoux] -text [T \
      "Les parties en ligne téléchargées pendant la préparation, une base par joueur·se. Elles ne vont jamais dans Gaby." \
      "The online games downloaded during preparation, one database per player. They never go into Gaby."]
  catch {::moderne::enBulle $f.intro}
  pack $f.intro -side top -anchor w -pady {0 8}
  ttk::treeview $f.t -columns {joueur parties date} -show headings -height 12 -selectmode browse
  foreach {c fr en l a} {joueur Joueur·se Player 260 w parties Parties Games 90 e date "Téléchargées le" "Downloaded on" 150 center} {
    $f.t heading $c -text [T $fr $en]
    $f.t column $c -width $l -anchor $a -stretch [expr {$c eq "joueur"}]
  }
  pack $f.t -side top -fill both -expand 1
  ttk::frame $f.b
  ttk::button $f.b.ouvrir -text [T "Ouvrir" "Open"] -command ::moderne::enligne::ouvrirChoisie
  catch {$f.b.ouvrir configure -style Accent.TButton}
  ttk::button $f.b.suppr -text [T "Supprimer…" "Delete…"] -command ::moderne::enligne::supprimerChoisie
  ttk::button $f.b.dossier -text [T "Ouvrir le dossier" "Open the folder"] -command {catch {openURL "file://[::moderne::enligne::dossier]"}}
  ttk::button $f.b.fermer -text [T "Fermer" "Close"] -command [list destroy $w]
  pack $f.b.ouvrir $f.b.suppr $f.b.dossier -side left -padx {0 6}
  pack $f.b.fermer -side right
  pack $f.b -side top -fill x -pady {10 0}
  bind $f.t <Double-Button-1> ::moderne::enligne::ouvrirChoisie
  bind $w <Escape> [list destroy $w]
  catch {::moderne::repeindre $w}
  remplirFenetre
}

### Number of games of a database without opening it (index header)
proc ::moderne::enligne::nbParties {fichier} {
  if {[catch {
    set c [open $fichier rb]
    set h [read $c 17]
    close $c
  }]} { return ? }
  # .si4: "Scid.si" magic (8), version (2), base type (4), numGames (3 bytes, big-endian)
  if {[string range $h 0 6] ne "Scid.si" || [string length $h] < 17} { return ? }
  binary scan [string range $h 14 16] cu3 o
  return [expr {([lindex $o 0] << 16) | ([lindex $o 1] << 8) | [lindex $o 2]}]
}

proc ::moderne::enligne::remplirFenetre {} {
  set t .telechargesWin.f.t
  if {![winfo exists $t]} { return }
  $t delete [$t children {}]
  chargerComptes
  foreach f [lsort -dictionary [glob -nocomplain -directory [dossier] *.si4]] {
    set racine [file rootname $f]
    set nom [string map {_ " "} [file tail $racine]]
    $t insert {} end -id $racine -values [list $nom [nbParties $f] \
        [clock format [file mtime $f] -format "%d/%m/%Y %H:%M"]]
  }
  if {![llength [$t children {}]]} {
    $t insert {} end -id vide -values [list [T "(aucune : Se préparer contre un adversaire › Lichess / Chess.com)" "(none: Prepare against a player › Lichess / Chess.com)"] {} {}]
  }
}

proc ::moderne::enligne::choisie {} {
  set t .telechargesWin.f.t
  set id [$t focus]
  if {$id eq {} || $id eq "vide"} { return {} }
  return $id
}

proc ::moderne::enligne::ouvrirChoisie {} {
  set racine [choisie]
  if {$racine eq {}} { return }
  for {set i 1} {$i <= [sc_base count total]} {incr i} {
    if {[sc_base inUse $i] && [file normalize [sc_base filename $i]] eq [file normalize $racine]} {
      sc_base switch $i
      catch {::file::SwitchToBase $i}
      catch {::windows::gamelist::Open}
      return
    }
  }
  if {[catch {sc_base open $racine} b]} {
    tk_messageBox -parent .telechargesWin -icon error -type ok -title Siby -message $b
    return
  }
  sc_base switch $b
  catch {::recentFiles::add "$racine.si4"}
  catch {::windows::switcher::Refresh}
  catch {::windows::gamelist::Open}
  catch {::windows::gamelist::Refresh}
  catch {updateBoard -pgn}
  catch {updateStatusBar}
}

proc ::moderne::enligne::supprimerChoisie {} {
  set racine [choisie]
  if {$racine eq {}} { return }
  for {set i 1} {$i <= [sc_base count total]} {incr i} {
    if {[sc_base inUse $i] && [file normalize [sc_base filename $i]] eq [file normalize $racine]} {
      tk_messageBox -parent .telechargesWin -icon info -type ok -title Siby -message [T \
          "Cette base est ouverte : ferme-la d'abord." "This database is open: close it first."]
      return
    }
  }
  set nom [string map {_ " "} [file tail $racine]]
  if {[tk_messageBox -parent .telechargesWin -icon question -type yesno -title Siby -message [T \
      "Supprimer les parties en ligne téléchargées de $nom ?" "Delete the downloaded online games of $nom?"]] ne "yes"} { return }
  foreach x {.si4 .sn4 .sg4 .sbl .online.sbl .ajouts.sbl .sbp} { catch {file delete -force $racine$x} }
  remplirFenetre
}

### End Siby
