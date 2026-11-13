###
### Siby: updates of Gaby - Games Archive By Yosha
###
### Gaby (gaby.si4) is updated with small files of new games, published
### online and already cleaned (players linked to FIDE, duplicates removed,
### time control and flags set). Siby appends them to the end of the local
### database (PGN import into the database, without rewriting it).
###
### Published (folder or address given by the "update address" setting):
###   gaby_manifest.json
###     { "base": {"version": "2026-10-01", "lien": "https://…", …},
###       "mises_a_jour": [ {"fichier": "gaby_maj_2026-10-22.pgn",
###                          "date": "2026-10-22", "parties": 312,
###                          "sha256": "…", "base_min": "2026-10-01"}, … ] }
###     "depuis" (optional): first day covered by the daily files (else
###     the date of the oldest one); a copy older than that needs the big
###     update. A file holds the new games of its date: Siby applies those dated
###     from the version of the user's complete database on (base_min, if
###     present, is not needed). File names are relative to the manifest
###     (or full URLs). The server only needs the latest complete database
###     and the daily files of the last weeks.
###   gaby_maj_YYYY-MM-DD.pgn: only the new games, each with [Cadence],
###     [ScidFlags] (1 classical, 2 rapid, 3 blitz, 4 correspondence, + 5
###     online), [Online "1"] when online and [GabyId] (unique game id).
###
### What is applied is noted next to the database, in gaby.maj.json:
###   {"base_version": "…", "telecharge_le": "…", "derniere_maj": "…",
###    "derniere_verif": "…", "ajoutees": N,
###    "appliques": [{"fichier", "date", "parties", "sha256"}…]}
### (the complete database should ship with this file; without it, the
### local copy is taken to be the published complete database, if it has
### as many games as the manifest's "parties" when given).
###
### Rules:
###   - checked in the background at every start (a few seconds after it,
###     never waiting for the network), then every few hours, and from
###     Tools › Gaby; without network: nothing is shown, next time;
###   - missing files are downloaded in order, their SHA-256 checked, then
###     appended all together in one import (a catch-up of 75 days: one
###     short freeze, not 75); a file is never imported twice
###     (gaby.maj.json), and the games whose [GabyId] is already in the
###     database are left out; a download failing halfway: the files
###     before it are applied, the rest next time;
###   - the flags are checked after the import and set from [Cadence] /
###     [Online] if needed; the names of flags 1-5 are kept;
###   - before appending, the .sn4 is copied and the sizes of .si4 / .sg4 and
###     the index's header are noted on disk (gaby.maj.annuler): on failure
###     (disk full, locked database…) they are restored, and also at the next
###     start when Siby was stopped during the import;
###   - big update: the complete database (a .zip holding gaby.si4, .sn4,
###     .sg4, and optionally .sbl, .online.sbl, .sbp, .sbc, .maj.json) is
###     downloaded again on request (default), or every week / month
###     (option); downloaded and unzipped in the background, then it
###     replaces the old one, which is deleted (put back on failure);
###   - days missing from the manifest (gap between the local copy and the
###     oldest daily file): the big update is offered with a button;
###   - status bar: "Gaby up to date on DD/MM (+ N games)".
###

namespace eval ::moderne::gaby {
  # saved settings (Options): autoMaj (automatic update), url (manifest or
  # its folder), fichier (local Gaby .si4)
  variable autoMaj
  variable url
  variable fichier
  variable grande           ;# big update: demande (on request) | semaine | mois
  # state
  variable enCours 0
  variable manuel 0
  variable manifeste {}
  # (correction of the complete Gaby already offered this session)
  variable corrigeePropose 0
  variable file {}          ;# updates left to download (dicts of the manifest)
  variable recus {}         ;# downloaded, to append: {manifest entry, local file}
  variable echecApres {}    ;# a download failure, told once the others are applied
  variable ajouteesSession 0
  variable form
  array set form {}
  variable delaiVerif [expr {4 * 3600 * 1000}]   ;# every 4 hours
}
### Gaby's address (Cloudflare R2, domain tribychess.org): built in, so no
### one has to type it; the field of the settings can still change it
set ::moderne::gaby::urlDefaut https://gaby.tribychess.org/gaby_manifest.json
foreach {_v _d} {autoMaj 1 url {} fichier {} grande demande} {
  if {![info exists ::moderne::gaby::$_v]} { set ::moderne::gaby::$_v $_d }
}
unset _v _d

proc ::moderne::gaby::T {fr en} { return [::moderne::tr $fr $en] }

proc ::moderne::gaby::aujourdhui {} { return [clock format [clock seconds] -format %Y-%m-%d] }

### Automatic check: a few seconds after startup, then every few hours
proc ::moderne::gaby::demarrage {} {
  variable autoMaj
  variable delaiVerif
  after cancel ::moderne::gaby::demarrage
  after $delaiVerif ::moderne::gaby::demarrage
  if {![::moderne::actif] || $autoMaj ne "1"} { return }
  trouverFichier
  catch {updateStatusBar}
  verifier 0
}

### Local Gaby file: the setting, or else an open database named Gaby*
proc ::moderne::gaby::trouverFichier {} {
  variable fichier
  if {$fichier ne {} && [file exists [file rootname $fichier].si4]} { return $fichier }
  for {set i 1} {$i <= [sc_base count total]} {incr i} {
    if {[sc_base inUse $i] && [string match -nocase gaby* [file tail [sc_base filename $i]]]} {
      set fichier [sc_base filename $i].si4
      return $fichier
    }
  }
  # (a Gaby database Siby knows by name, not open now: added by hand to
  # My databases, or downloaded by the Gaby program)
  # (also when the known file is gone: Gaby moved to another folder)
  set l {}
  catch {set l [::moderne::mesbases::liste]}
  foreach f $l {
    if {[string match -nocase gaby*.si4 [file tail $f]] && [file exists $f]} {
      set fichier $f
      return $fichier
    }
  }
  return $fichier
}

### Number of the Gaby database if it is open, else -1
proc ::moderne::gaby::baseOuverte {} {
  variable fichier
  if {$fichier eq {}} { return -1 }
  set cible [file normalize [file rootname $fichier]]
  for {set i 1} {$i <= [sc_base count total]} {incr i} {
    if {[sc_base inUse $i] && [file normalize [sc_base filename $i]] eq $cible} { return $i }
  }
  return -1
}

### Is base b (default: current) Gaby?
proc ::moderne::gaby::estGaby {{b {}}} {
  set g [baseOuverte]
  if {$g < 0} { return 0 }
  if {$b eq {}} { set b [sc_base current] }
  expr {$b == $g}
}

################################################################################
### State file (gaby.maj.json)
################################################################################

proc ::moderne::gaby::fichierEtat {} {
  variable fichier
  return "[file rootname $fichier].maj.json"
}

proc ::moderne::gaby::lireEtat {} {
  set e [dict create base_version {} telecharge_le {} derniere_maj {} derniere_verif {} base_sha256 {} ajoutees 0 appliques {} copie_gardee {}]
  set f [fichierEtat]
  if {![file exists $f]} { return $e }
  if {[catch {
    set c [open $f r]
    fconfigure $c -encoding utf-8
    set lu [::moderne::json::parse [read $c]]
    close $c
  }]} { return $e }
  foreach k {base_version telecharge_le derniere_maj derniere_verif base_sha256 ajoutees appliques copie_gardee} {
    if {[dict exists $lu $k]} { dict set e $k [dict get $lu $k] }
  }
  return $e
}

proc ::moderne::gaby::jsonChaine {s} {
  return "\"[string map {\\ \\\\ \" \\\" \n \\n \r \\r \t \\t} $s]\""
}

### Written through a temporary file, then renamed (never half written)
proc ::moderne::gaby::ecrireEtat {e} {
  set app {}
  foreach a [dict get $e appliques] {
    set champs {}
    foreach k {fichier date sha256} {
      lappend champs "[jsonChaine $k]: [jsonChaine [::moderne::json::get $a $k {}]]"
    }
    set n [::moderne::json::get $a parties 0]
    if {![string is integer -strict $n]} { set n 0 }
    lappend champs "\"parties\": $n"
    lappend app "    \{[join $champs {, }]\}"
  }
  set ajoutees [dict get $e ajoutees]
  if {![string is integer -strict $ajoutees]} { set ajoutees 0 }
  set texte "\{\n"
  foreach k {base_version telecharge_le derniere_maj derniere_verif base_sha256 copie_gardee} {
    set v {}
    if {[dict exists $e $k]} { set v [dict get $e $k] }
    append texte "  [jsonChaine $k]: [jsonChaine $v],\n"
  }
  append texte "  \"ajoutees\": $ajoutees,\n"
  append texte "  \"appliques\": \[\n[join $app ",\n"]\n  \]\n\}\n"
  set f [fichierEtat]
  set c [open $f.tmp w]
  fconfigure $c -encoding utf-8
  puts -nonewline $c $texte
  close $c
  file rename -force $f.tmp $f
}

proc ::moderne::gaby::dejaApplique {e nom} {
  foreach a [dict get $e appliques] {
    if {[::moderne::json::get $a fichier {}] eq $nom} { return 1 }
  }
  return 0
}

################################################################################
### Network (asynchronous, through curl, like the online games)
################################################################################

### Calls suite with the local file, or with {} and the error
proc ::moderne::gaby::telecharger {url sortie suite {duree 3600}} {
  set cmd [list curl -sSLf --connect-timeout 10 --max-time $duree -A "Siby (Gaby update)" -o $sortie $url]
  if {[catch {open "|$cmd 2>@1" r} f]} { {*}$suite {} $f ; return }
  fconfigure $f -blocking 0
  set ::moderne::gaby::sortieCurl($f) {}
  fileevent $f readable [list ::moderne::gaby::finTelechargement $f $sortie $suite]
}

proc ::moderne::gaby::finTelechargement {f sortie suite} {
  append ::moderne::gaby::sortieCurl($f) [read $f]
  if {![eof $f]} { return }
  fconfigure $f -blocking 1
  set code [catch {close $f} err]
  set msg [string trim $::moderne::gaby::sortieCurl($f)]
  unset ::moderne::gaby::sortieCurl($f)
  if {$code || ![file exists $sortie]} {
    {*}$suite {} [expr {$msg ne {} ? $msg : $err}]
  } else {
    {*}$suite $sortie {}
  }
}

proc ::moderne::gaby::dossierTemp {} {
  set d [file join $::scidUserDir gaby-update]
  file mkdir $d
  return $d
}

### Address of the manifest, and of a file named in it
proc ::moderne::gaby::adresseManifeste {} {
  variable url
  variable urlDefaut
  set u [string trim $url]
  if {$u eq {}} { set u $urlDefaut }
  if {[string match -nocase *.json $u]} { return $u }
  return "[string trimright $u /]/gaby_manifest.json"
}

proc ::moderne::gaby::adresseFichier {nom} {
  if {[regexp {^[a-z]+://} $nom]} { return $nom }
  set m [adresseManifeste]
  if {[regexp {^[a-z]+://} $m]} {
    return "[string range $m 0 [string last / $m]]$nom"
  }
  # (local folder: tests, or a copy on a shared drive)
  return [file join [file dirname $m] $nom]
}

### A local manifest (path without "http…://") is copied rather than downloaded
proc ::moderne::gaby::recuperer {source sortie suite {duree 3600}} {
  if {[regexp {^[a-z]+://} $source]} {
    telecharger $source $sortie $suite $duree
    return
  }
  if {[catch {file copy -force $source $sortie} err]} {
    after idle [list {*}$suite {} $err]
  } else {
    after idle [list {*}$suite $sortie {}]
  }
}

################################################################################
### Check
################################################################################

### Checks the manifest; manuel: started from the menu (messages shown)
proc ::moderne::gaby::verifier {{manuelDemande 0}} {
  variable url
  variable enCours
  variable manuel
  variable fichier
  if {$enCours} {
    if {$manuelDemande} { ::moderne::nsb::annonce [T "Gaby : mise à jour en cours…" "Gaby: update in progress…"] -1 }
    return
  }
  trouverFichier
  if {$fichier eq {} || ![file exists [file rootname $fichier].si4]} {
    if {$manuelDemande} { reglages }
    return
  }
  catch reparer
  set enCours 1
  set manuel $manuelDemande
  if {$manuel} { ::moderne::nsb::annonce [T "Gaby : recherche des nouveautés…" "Gaby: looking for new games…"] 0 }
  set m [file join [dossierTemp] gaby_manifest.json]
  file delete -force $m
  recuperer [adresseManifeste] $m ::moderne::gaby::lireManifeste 30
}

### Silent in automatic mode (no network: next time)
proc ::moderne::gaby::echec {titre detail} {
  variable enCours
  variable manuel
  variable ajouteesSession
  set enCours 0
  if {[info exists ajouteesSession] && $ajouteesSession > 0} {
    set ajouteesSession 0
    catch rafraichir
  }
  if {!$manuel} {
    puts stderr "Siby Gaby: $titre $detail"
    return
  }
  catch {::moderne::nsb::finAnnonce}
  tk_messageBox -parent . -icon info -type ok -title Gaby -message $titre -detail $detail
}

proc ::moderne::gaby::lireManifeste {fichierM err} {
  variable manifeste
  variable file
  variable manuel
  variable enCours
  variable fichier
  if {$fichierM eq {}} {
    echec [T "Gaby : serveur de mise à jour injoignable (pas encore ouvert, ou pas de réseau)" \
        "Gaby: update server unreachable (not open yet, or no network)"] $err
    return
  }
  if {[catch {
    set c [open $fichierM r]
    fconfigure $c -encoding utf-8
    set manifeste [::moderne::json::parse [read $c]]
    close $c
  } err] || ![dict exists $manifeste mises_a_jour]} {
    echec [T "Gaby : fiche de mise à jour illisible" "Gaby: unreadable update manifest"] $err
    return
  }
  # players pack (photos and cards): its own version, updated on its own
  after idle [list catch [list ::moderne::avatars::verifierPaquet $manifeste]]
  # official ratings before 2001: their own version too
  after idle [list catch [list ::moderne::fide::verifierOfficiels $manifeste]]
  set e [lireEtat]
  set baseV [baseVersion]
  # Local version: the one noted, else the published one; but a copy put
  # there by hand, without its gaby.maj.json, may be another build: its
  # number of games must be the published one's ("parties" in the
  # manifest), else the daily files, made for the published base, are not
  # applied to it (Yosha 2026-11-07: three files of the 03/11 base applied
  # to a test build, then the libraries rebuilt in full)
  # (also a copy with the published version's name but no daily file
  # applied yet: a test build may carry that name; Gaby session 2026-11-07)
  # ("Keep my copy" chosen once: no more check, Yosha 2026-11-07)
  set neuve [expr {[dict get $e copie_gardee] eq {} && ([dict get $e base_version] eq {} \
      || ([dict get $e base_version] eq $baseV && ![llength [dict get $e appliques]]))}]
  if {$neuve} {
    set attendues [::moderne::json::get $manifeste base parties {}]
    set locales {}
    catch {set locales [::moderne::enligne::nbParties [file rootname $fichier].si4]}
    if {[string is integer -strict $attendues] && [string is integer -strict $locales] && $locales != $attendues} {
      set enCours 0
      proposerComplet [T "Ta copie de Gaby n'est pas la version publiée" \
          "Your copy of Gaby is not the published version"] 1
      return
    }
  }
  if {[dict get $e base_version] eq {}} {
    dict set e base_version $baseV
  }
  dict set e derniere_verif [clock format [clock seconds] -format %Y-%m-%dT%H:%M:%S]
  catch {ecrireEtat $e}
  set locale [dict get $e base_version]
  # The complete Gaby corrected since the download (same version name, new
  # SHA-256): offered once per session, the daily files go on meanwhile
  variable corrigeePropose
  set shaPublie [string tolower [::moderne::json::get $manifeste base sha256 {}]]
  # (Gaby in two parts: the fingerprint of their merge, as kept at download)
  if {[partiesDispo]} { set shaPublie [string tolower [::moderne::json::get $manifeste fusion sha256GabyIds {}]] }
  set shaLocal [dict get $e base_sha256]
  if {!$corrigeePropose && $baseV eq $locale && $shaLocal ne {} && $shaPublie ne {} && $shaPublie ne $shaLocal} {
    set corrigeePropose 1
    after idle [list ::moderne::gaby::proposerComplet [T "Gaby complète a été corrigée depuis ton téléchargement" \
        "The complete Gaby has been corrected since your download"]]
  }
  # Big update every week / month (option): a newer complete database
  variable grande
  if {$grande in {semaine mois} && $baseV ne {} && [string compare $baseV $locale] > 0} {
    set depuis [dict get $e telecharge_le]
    if {$depuis eq {}} { set depuis $locale }
    if {[jours $depuis [aujourdhui]] >= ($grande eq "semaine" ? 7 : 30)} {
      set enCours 0
      grandeMaj 0
      return
    }
  }
  # A new complete Gaby whose daily files start with it (its own GabyIds:
  # they restart at 1 in each complete version, Gaby 2026.11): the daily
  # files cannot go into the local copy, the complete one is needed first
  set debutMaj [::moderne::json::get $manifeste depuis {}]
  if {$baseV ne {} && $locale ne {} && [string compare $baseV $locale] > 0 && $debutMaj ne {} && [string compare $debutMaj $baseV] >= 0} {
    set enCours 0
    proposerComplet [T "Nouvelle version complète de Gaby disponible ([dateAffichee]) : à télécharger une fois" \
        "A new complete version of Gaby is available ([dateAffichee]): download it once"]
    return
  }
  # Daily files: those dated from the local complete database on, not yet
  # applied, in the order of their dates (games already present are left
  # out by their GabyId)
  set toutes [lsort -command ::moderne::gaby::parDate [dict get $manifeste mises_a_jour]]
  set file {}
  foreach m $toutes {
    set nom [::moderne::json::get $m fichier {}]
    if {$nom eq {} || [dejaApplique $e $nom]} { continue }
    if {$locale ne {} && [string compare [::moderne::json::get $m date {}] $locale] < 0} { continue }
    lappend file $m
  }
  # Days no longer in the manifest: the big update is needed
  set reference $locale
  if {[string compare [dict get $e derniere_maj] $reference] > 0} { set reference [dict get $e derniere_maj] }
  # (first day of the daily files: "depuis" in the manifest, else the
  # oldest file)
  set premiere [::moderne::json::get $manifeste depuis {}]
  if {$premiere eq {}} { set premiere [::moderne::json::get [lindex $toutes 0] date {}] }
  if {$reference ne {} && $premiere ne {} && [jours $reference $premiere] > 1} {
    set enCours 0
    if {$baseV ne {} && [string compare $baseV $locale] > 0} {
      # (a new complete Gaby, its daily files start after it: not missed
      # updates, Yosha 2026-10-30)
      set d [dateAffichee]
      proposerComplet [T "Nouvelle version complète de Gaby disponible ($d) : à télécharger une fois" \
          "A new complete version of Gaby is available ($d): download it once"]
    } else {
      proposerComplet [T "Ta copie de Gaby est trop ancienne pour les petites mises à jour" \
          "Your copy of Gaby is too old for the small updates"]
    }
    return
  }
  if {![llength $file]} {
    set enCours 0
    catch {updateStatusBar}
    if {$manuel} {
      ::moderne::nsb::annonce "[texteEtat 1]" -1
      after 2500 ::moderne::nsb::finAnnonce
    }
    return
  }
  variable ajouteesSession 0
  variable recus {}
  variable echecApres {}
  variable nbFichiers [llength $file]
  variable nbParties 0
  foreach m $file { incr nbParties [::moderne::json::get $m parties 0] }
  annonce 0
  suivante
}

### Days from date a to date b (YYYY-MM-DD); 0 if unreadable
proc ::moderne::gaby::jours {a b} {
  if {[catch {
    set n [expr {([clock scan $b -format %Y-%m-%d] - [clock scan $a -format %Y-%m-%d]) / 86400}]
  }]} { return 0 }
  return $n
}

proc ::moderne::gaby::baseVersion {} {
  variable manifeste
  foreach k {version date} {
    set v [::moderne::json::get $manifeste base $k {}]
    if {$v ne {}} { return $v }
  }
  # (Gaby in two parts without the complete zip: the parts' version)
  foreach p [::moderne::json::get $manifeste parties {}] {
    set v [::moderne::json::get $p version {}]
    if {$v ne {}} { return $v }
  }
  return {}
}

### A base version shown as a date: "2026-10-29b" (a second complete base
### the same day) -> 29/10/2026; v: the published base by default
proc ::moderne::gaby::dateAffichee {{v {}}} {
  variable manifeste
  if {$v eq {}} {
    set v [::moderne::json::get $manifeste base date {}]
    if {$v eq {}} { set v [baseVersion] }
  }
  if {[regexp {^([0-9]{4})-([0-9]{2})-([0-9]{2})} $v -> a m j]} {
    return [T "$j/$m/$a" "$a-$m-$j"]
  }
  return $v
}

proc ::moderne::gaby::parDate {a b} {
  string compare [::moderne::json::get $a date {}] [::moderne::json::get $b date {}]
}

### Progress notice (quiet in automatic mode: only while applying)
proc ::moderne::gaby::annonce {pct} {
  variable nbFichiers
  variable nbParties
  ::moderne::nsb::annonce [T \
      "Gaby : ajout de [::utils::thousands $nbParties] nouvelles parties" \
      "Gaby: adding [::utils::thousands $nbParties] new games"] $pct
}

### Next file of the queue; all downloaded: appended together
proc ::moderne::gaby::suivante {} {
  variable file
  variable nbFichiers
  if {![llength $file]} {
    appliquerRecus
    return
  }
  set m [lindex $file 0]
  set nom [::moderne::json::get $m fichier {}]
  set sortie [file join [dossierTemp] [file tail $nom]]
  file delete -force $sortie
  # (downloads: 0 to 90 %, the import: the rest)
  annonce [expr {round(90.0 * ($nbFichiers - [llength $file]) / max(1, $nbFichiers))}]
  recuperer [adresseFichier $nom] $sortie [list ::moderne::gaby::recu $m]
}

proc ::moderne::gaby::recu {m sortie err} {
  variable file
  variable recus
  variable echecApres
  if {$sortie eq {}} {
    # (the files before it are applied, in order; the rest next time)
    set echecApres [list [T "Gaby : téléchargement impossible" "Gaby: download failed"] $err]
    appliquerRecus
    return
  }
  set attendu [string tolower [::moderne::json::get $m sha256 {}]]
  if {$attendu ne {}} {
    if {[catch {sc_gaby sha256 $sortie} h] || $h ne $attendu} {
      file delete -force $sortie
      set echecApres [list [T "Gaby : fichier abîmé pendant le téléchargement (sha256), réessaie plus tard" \
          "Gaby: file damaged during the download (sha256), try again later"] [::moderne::json::get $m fichier {}]]
      appliquerRecus
      return
    }
  }
  lappend recus [list $m $sortie]
  set file [lrange $file 1 end]
  after idle ::moderne::gaby::suivante
}

### The downloaded files appended in one import
proc ::moderne::gaby::appliquerRecus {} {
  variable recus
  if {![llength $recus]} { finirMaj ; return }
  annonce 90
  appliquer
}

### End of the daily update: the failure kept aside, or the result
proc ::moderne::gaby::finirMaj {} {
  variable enCours
  variable echecApres
  if {[llength $echecApres]} {
    set e $echecApres
    set echecApres {}
    echec {*}$e
    catch {::moderne::nsb::finAnnonce}
    return
  }
  set enCours 0
  apres
}

### A search or another long task is running: wait for it to finish
proc ::moderne::gaby::occupe {} {
  if {[grab current] ne {}} { return 1 }
  # (an import already running: never two at once)
  variable imp
  if {[info exists imp] && $imp ne {}} { return 1 }
  # (a library search in progress reads the database; a review running:
  # the database is replaced after it, not under it)
  if {[info exists ::moderne::biblio::enCours] && $::moderne::biblio::enCours} { return 1 }
  if {[info exists ::moderne::oracle::etat] && $::moderne::oracle::etat ni {idle fini {}}} { return 1 }
  if {[info exists ::moderne::nsb::canal] && [array size ::moderne::nsb::canal]} {
    # (the instant library being rebuilt does not prevent appending, but
    # it reads the database: wait)
    return 1
  }
  return 0
}

proc ::moderne::gaby::appliquer {} {
  variable recus
  if {[occupe]} {
    after 2000 ::moderne::gaby::appliquer
    return
  }
  importer $recus ::moderne::gaby::appliquerFin
}

proc ::moderne::gaby::appliquerFin {code res} {
  variable recus
  foreach r $recus { file delete -force [lindex $r 1] }
  set recus {}
  if {$code} {
    variable echecApres {}
    echec [T "Gaby : ajout impossible, la base est restée comme avant" \
        "Gaby: adding failed, the database is unchanged"] $res
    catch {::moderne::nsb::finAnnonce}
    return
  }
  variable ajouteesSession
  incr ajouteesSession $res
  finirMaj
}

################################################################################
### Appending a file
################################################################################

### Games of the PGN text: list of {gabyId text}
proc ::moderne::gaby::partiesPgn {texte} {
  set res {}
  set debuts [regexp -all -indices -inline -line {^\[Event } $texte]
  if {![llength $debuts]} { return {} }
  lappend debuts [list [string length $texte] 0]
  for {set i 0} {$i < [llength $debuts] - 1} {incr i} {
    set a [lindex $debuts $i 0]
    set b [expr {[lindex $debuts [expr {$i + 1}] 0] - 1}]
    set p [string range $texte $a $b]
    set id {}
    regexp -line {^\[GabyId "([^"]*)"\]} $p -> id
    lappend res [list $id $p]
  }
  return $res
}

### Appends the files fichiers ({manifest entry, local file}, in date order)
### to Gaby, in steps (the window stays
### responsive: copying the 500 MB index and importing at once froze Siby
### about 10 s, seen on Windows 2026-10-31); then calls "suite code result"
### (result: the number of games added, or the error). On failure, the
### database files are restored.
proc ::moderne::gaby::importer {fichiers suite} {
  variable fichier
  variable imp
  set racine [file rootname $fichier]
  if {[catch {
    # Games of the files, without those already in the database (GabyId)
    set parties {}
    set parFichier {}
    foreach f $fichiers {
      lassign $f m pgn
      set c [open $pgn r]
      fconfigure $c -encoding utf-8
      set texte [read $c]
      close $c
      set p [partiesPgn $texte]
      if {![llength $p] && [string trim $texte] ne {}} {
        error "[T "fichier illisible (pas de partie PGN)" "unreadable file (no PGN game)"] : [file tail $pgn]"
      }
      foreach x $p { lappend parties [linsert $x end [llength $parFichier]] }
      lappend parFichier $m
    }
    set courante [sc_base current]
    set b [baseOuverte]
    set fermer 0
    if {$b < 0} {
      set b [sc_base open $racine]
      set fermer 1
    }
    set avant [sc_base numGames $b]
    # (new games are at the end: the last ones are enough to find duplicates)
    set ids {}
    foreach p $parties { if {[lindex $p 0] ne {}} { lappend ids [lindex $p 0] } }
    set presents {}
    if {[llength $ids] && $avant > 0} {
      set fenetre [expr {max(5000, 4 * [llength $parties])}]
      foreach r [sc_gaby tags $b [expr {max(1, $avant - $fenetre + 1)}] $avant GabyId] {
        if {[lindex $r 1] ne {}} { dict set presents [lindex $r 1] 1 }
      }
    }
    set garder {}
    set nGardees [lrepeat [llength $parFichier] 0]
    foreach p $parties {
      if {[lindex $p 0] ne {} && [dict exists $presents [lindex $p 0]]} { continue }
      # (a game twice in the files: once)
      if {[lindex $p 0] ne {}} { dict set presents [lindex $p 0] 1 }
      lappend garder [lindex $p 1]
      lset nGardees [lindex $p 2] [expr {[lindex $nGardees [lindex $p 2]] + 1}]
    }
    set notes {}
    foreach m $parFichier n $nGardees { lappend notes [list $m $n] }
    catch {sc_base switch $courante}
  } err]} {
    after idle [concat $suite [list 1 $err]]
    return
  }
  if {![llength $garder]} {
    if {$fermer} { catch {sc_base close $b} }
    noterAppliques $notes
    after idle [concat $suite [list 0 0]]
    return
  }
  # To undo: the index's header and size (the import only rewrites its
  # header and appends: copying the whole index, 600 MB on Gaby, before
  # each daily file made the update very slow, Yosha 2026-11-07), and a
  # copy of the names (rewritten by the import), in the background
  # (kept on disk too, gaby.maj.annuler: Siby stopped during the import,
  # the database is put back at the next start, see reparer)
  if {[catch {
    set c [open $racine.si4 rb]
    set entete [read $c 4096]
    close $c
    set c [open $racine.maj.annuler.tmp w]
    puts $c [list tailleSi4 [file size $racine.si4] tailleSg4 [file size $racine.sg4] \
        tailleSn4 [file size $racine.sn4] entete [binary encode base64 $entete]]
    close $c
    file rename -force $racine.maj.annuler.tmp $racine.maj.annuler
  } err]} {
    catch {file delete -force $racine.maj.annuler.tmp $racine.maj.annuler}
    if {$fermer} { catch {sc_base close $b} }
    after idle [concat $suite [list 1 $err]]
    return
  }
  set imp [dict create notes $notes suite $suite racine $racine b $b fermer $fermer courante $courante \
      avant $avant garder $garder tailleSg4 [file size $racine.sg4] tailleSi4 [file size $racine.si4] \
      entete $entete leve 0 canaux {}]
  importerCopie sn4
}

### Background copy of <racine>.<ext> to <racine>.<ext>.sauvegarde
proc ::moderne::gaby::importerCopie {ext} {
  variable imp
  set racine [dict get $imp racine]
  if {[catch {
    set de [open $racine.$ext rb]
    set vers [open $racine.$ext.sauvegarde wb]
    fconfigure $de -buffersize 1048576
    fconfigure $vers -buffersize 1048576
    dict set imp canaux [list $de $vers]
    chan copy $de $vers -size [file size $racine.$ext] -command [list ::moderne::gaby::importerCopieFin $ext]
  } err]} {
    importerEchec $err
  }
}

proc ::moderne::gaby::importerCopieFin {ext n {err {}}} {
  variable imp
  foreach c [dict get $imp canaux] { catch {close $c} }
  dict set imp canaux {}
  if {$err ne {}} { importerEchec $err ; return }
  # (Gaby padlocked: Siby's update goes through)
  set leve 0
  catch {set leve [::moderne::mesbases::lever [dict get $imp b]]}
  dict set imp leve $leve
  dict set imp debut 0
  after idle ::moderne::gaby::importerTranche
}

### Imports the next 5,000 games: in practice the whole daily file at once.
### (each import costs about 1 s on Gaby whatever its size: rewriting the
### names and recounting 11 million games; smaller slices only made more
### freezes, measured on Windows 2026-10-31)
proc ::moderne::gaby::importerTranche {} {
  variable imp
  set garder [dict get $imp garder]
  set debut [dict get $imp debut]
  set b [dict get $imp b]
  set courante [sc_base current]
  if {[catch {
    if {![sc_base inUse $b]} { error [T "Gaby fermée pendant l'ajout" "Gaby closed while adding"] }
    set filtre [file join [dossierTemp] import.pgn]
    set c [open $filtre w]
    fconfigure $c -encoding utf-8
    puts -nonewline $c [join [lrange $garder $debut [expr {$debut + 4999}]] "\n"]
    close $c
    sc_base switch $b
    # (the name file is written by the last slice only)
    set fin [expr {$debut + 5000 >= [llength $garder]}]
    set code [catch {sc_base import file $filtre {*}[expr {$fin ? {} : {-later}}]} err2]
    file delete -force $filtre
    if {$code} { error $err2 }
  } err]} {
    catch {sc_base switch $courante}
    importerEchec $err
    return
  }
  catch {sc_base switch $courante}
  incr debut 5000
  dict set imp debut $debut
  if {$debut < [llength $garder]} {
    after 1 ::moderne::gaby::importerTranche
    return
  }
  importerFin
}

proc ::moderne::gaby::importerFin {} {
  variable imp
  set b [dict get $imp b]
  set racine [dict get $imp racine]
  set courante [sc_base current]
  set code [catch {
    set ajoutees [expr {[sc_base numGames $b] - [dict get $imp avant]}]
    if {$ajoutees <= 0} { error [T "aucune partie ajoutée" "no game added"] }
    sc_base switch $b
    poserDrapeaux $b [expr {[dict get $imp avant] + 1}] [sc_base numGames $b]
  } err]
  catch {sc_base switch $courante}
  if {$code} { importerEchec $err ; return }
  catch {::moderne::mesbases::reposer $b [dict get $imp leve]}
  # (the undo data first: stopped right after, the games stay and the
  # files are taken again, their games left out by GabyId)
  file delete -force $racine.maj.annuler
  file delete -force $racine.si4.sauvegarde $racine.sn4.sauvegarde
  # (the search accelerator, if there is one, takes the new games)
  catch {sc_base switch $b ; ::search::accel::suivre}
  if {[dict get $imp fermer]} { catch {sc_base close $b} }
  catch {sc_base switch $courante}
  set notes [dict get $imp notes]
  set suite [dict get $imp suite]
  set imp {}
  noterAppliques $notes
  after idle [concat $suite [list 0 $ajoutees]]
}

### Failure: the database put back as it was
proc ::moderne::gaby::importerEchec {err} {
  variable imp
  foreach c [dict get $imp canaux] { catch {close $c} }
  set racine [dict get $imp racine]
  set b [dict get $imp b]
  catch {::moderne::mesbases::reposer $b [dict get $imp leve]}
  if {[file exists $racine.sn4.sauvegarde]} {
    restaurer $b $racine [dict get $imp tailleSg4] [dict get $imp fermer] \
        [dict get $imp tailleSi4] [dict get $imp entete]
  } else {
    file delete -force $racine.si4.sauvegarde $racine.sn4.sauvegarde
    if {[dict get $imp fermer]} { catch {sc_base close $b} }
  }
  file delete -force $racine.maj.annuler
  catch {sc_base switch [dict get $imp courante]}
  set suite [dict get $imp suite]
  set imp {}
  after idle [concat $suite [list 1 $err]]
}

### The files applied, noted in gaby.maj.json: notes {{manifest entry, games added}…}
proc ::moderne::gaby::noterAppliques {notes} {
  set e [lireEtat]
  set total 0
  foreach x $notes {
    lassign $x m ajoutees
    set a [dict create fichier [::moderne::json::get $m fichier {}] date [::moderne::json::get $m date {}] \
        parties $ajoutees sha256 [::moderne::json::get $m sha256 {}]]
    dict lappend e appliques $a
    set d [::moderne::json::get $m date {}]
    if {[string compare $d [dict get $e derniere_maj]] > 0} { dict set e derniere_maj $d }
    incr total $ajoutees
  }
  dict set e ajoutees $total
  if {[dict get $e base_version] eq {}} { dict set e base_version [baseVersion] }
  ecrireEtat $e
}

### Siby stopped during an import (gaby.maj.annuler left): the database put
### back as it was before it. Its daily files were not noted as applied:
### they are taken again.
proc ::moderne::gaby::reparer {} {
  variable fichier
  variable enCours
  if {$enCours || $fichier eq {}} { return }
  set racine [file rootname $fichier]
  set f $racine.maj.annuler
  if {![file exists $f]} { return }
  set u {}
  catch {
    set c [open $f r]
    set u [string trim [read $c]]
    close $c
  }
  if {[catch {dict get $u tailleSn4}] || [catch {binary decode base64 [dict get $u entete]} entete]} {
    file delete -force $f $racine.sn4.sauvegarde $racine.si4.sauvegarde
    return
  }
  # (the copy of the names whole: the import may have started; else it had
  # not, nothing to put back)
  set s $racine.sn4.sauvegarde
  if {[file exists $s] && [file size $s] == [dict get $u tailleSn4]} {
    set b [baseOuverte]
    restaurer $b $racine [dict get $u tailleSg4] [expr {$b < 0}] [dict get $u tailleSi4] $entete
    puts stderr "Siby Gaby: interrupted update undone"
    catch rafraichir
  }
  file delete -force $f $racine.sn4.sauvegarde $racine.si4.sauvegarde
}

### The database is put back as it was before the import
proc ::moderne::gaby::restaurer {b racine tailleSg4 fermer tailleSi4 entete} {
  catch {sc_base close $b}
  # the index: its header put back, cut to its size before the import
  catch {
    set c [open $racine.si4 r+]
    fconfigure $c -translation binary
    puts -nonewline $c $entete
    chan truncate $c $tailleSi4
    close $c
  }
  catch {file rename -force $racine.sn4.sauvegarde $racine.sn4}
  catch {
    set c [open $racine.sg4 r+]
    chan truncate $c $tailleSg4
    close $c
  }
  if {!$fermer} {
    catch {sc_base open $racine}
    catch {::windows::switcher::Refresh}
  }
}

### Gaby merged from its two parts (sc_base fusion) had no names on its
### flags: Siby did not know it for Gaby (the "Online" flag): no penalty for
### blitz in the best games, no time control from the flags (Yosha
### 2026-11-11). Their meaning is fixed in Gaby: names other than these
### are put back too, written in the index. (For a Gaby merged here before
### the fix; a complete zip has them.)
proc ::moderne::gaby::reparerDrapeaux {b} {
  variable drapeauxVus
  if {![estGaby $b]} { return }
  if {[info exists drapeauxVus($b)]} { return }
  set drapeauxVus($b) 1
  set courante [sc_base current]
  if {$courante != $b} { sc_base switch $b }
  set avant {}
  set change 0
  catch {
    foreach {num nom fr} {1 Classic Classique 2 Rapid Rapide 3 Blitz Blitz 4 Corresp Corresp 5 Online {En ligne}} {
      set d {}
      catch {set d [string trim [sc_game flag $num description]]}
      lappend avant $d
      if {[string tolower $d] ni [list [string tolower $nom] [string tolower $fr]]} {
        catch {sc_game flag $num setdescription $nom}
        set change 1
      }
    }
  }
  if {$courante != $b} { sc_base switch $courante }
}

### Flags of the games first..last of database b: set from [Cadence] and
### [Online] when the PGN did not set them; names of flags 1-5 kept
proc ::moderne::gaby::poserDrapeaux {b premier dernier} {
  # (the labels Gaby writes from v12; bases of v11 keep their French ones)
  foreach {num nom} {1 Classic 2 Rapid 3 Blitz 4 Corresp 5 Online} {
    if {[catch {sc_game flag $num description} d] || [string trim $d] eq {}} {
      catch {sc_game flag $num setdescription $nom}
    }
  }
  foreach r [sc_gaby tags $b $premier $dernier Cadence Online] {
    lassign $r g cadence enLigne
    set cad [string tolower [string trim $cadence]]
    set n {}
    switch -glob -- $cad {
      1 - classi* { set n 1 }
      2 - rapid* { set n 2 }
      3 - blitz* { set n 3 }
      4 - corresp* { set n 4 }
    }
    set aucune 1
    foreach k {1 2 3 4} { if {[sc_game flag $k $g]} { set aucune 0 ; break } }
    if {$aucune && $n ne {}} { sc_game flag $n $g 1 }
    if {[string trim $enLigne] eq "1" && ![sc_game flag 5 $g]} { sc_game flag 5 $g 1 }
  }
}

### After the updates: lists, tree, statistics, instant library
proc ::moderne::gaby::apres {} {
  rafraichir
  ::moderne::nsb::annonce [texteEtat 1] 100
  after 3000 ::moderne::nsb::finAnnonce
}

proc ::moderne::gaby::rafraichir {} {
  set b [baseOuverte]
  if {$b > 0} {
    catch {::moderne::otb::filtrer $b}
    catch {::windows::gamelist::Refresh}
    catch {::windows::switcher::Refresh}
    catch {::windows::stats::Refresh}
    if {[winfo exists .treeWin$b]} { catch {::tree::refresh $b} }
    catch {set ::moderne::biblio::cache [dict create]}
    catch {::moderne::biblio::maj}
    catch {::moderne::nsb::verifier $b}
  }
  catch {updateStatusBar}
}

### "Gaby up to date on DD/MM (+ N games)"; empty if unknown (long: for
### a message rather than the status bar)
proc ::moderne::gaby::texteEtat {{long 0}} {
  variable fichier
  if {$fichier eq {}} { return {} }
  set e [lireEtat]
  set d [dict get $e derniere_maj]
  if {$d eq {}} {
    return [expr {$long ? [T "Gaby est à jour" "Gaby is up to date"] : {}}]
  }
  set jm $d
  # (21/10 in French, Oct 21 in English)
  catch {set jm [clock format [clock scan $d -format %Y-%m-%d] -format [T %d/%m "%b %d"] -locale C]}
  set n [dict get $e ajoutees]
  set t "[T "Gaby à jour au" "Gaby up to date on"] $jm"
  if {[string is integer -strict $n] && $n > 0} {
    append t " (+ [::utils::thousands $n] [expr {$n == 1 ? [T partie game] : [T parties games]}])"
  }
  return $t
}

### Status bar (when the current database is Gaby)
proc ::moderne::gaby::texteBarre {} {
  if {![estGaby]} { return {} }
  set t [texteEtat]
  if {$t eq {}} { return {} }
  return "   • $t"
}

################################################################################
### Big update: the complete database downloaded again (about 1.2 GB), on
### request or every week / month; it replaces the old one
################################################################################

proc ::moderne::gaby::lienComplet {} {
  variable manifeste
  foreach k {lien url link} {
    set lien [::moderne::json::get $manifeste base $k {}]
    if {$lien ne {}} { return [adresseFichier $lien] }
  }
  return {}
}

proc ::moderne::gaby::tailleComplet {} {
  variable manifeste
  # (Gaby writes the size of the complete zip in bytes: base.octets; in two
  # parts, the sum of the parts' zips, Gaby session 2026-11-09)
  set o [::moderne::json::get $manifeste base octets {}]
  if {[partiesDispo]} {
    set o 0
    foreach p [::moderne::json::get $manifeste parties {}] {
      foreach fz [::moderne::json::get $p fichiers {}] {
        set x [::moderne::json::get $fz octets 0]
        if {[string is wide -strict $x]} { incr o $x }
      }
    }
    if {!$o} { set o {} }
  }
  if {[string is wide -strict $o] && $o > 0} {
    if {$o >= 1e9} {
      set v [format "%.1f" [expr {$o / 1e9}]]
      return [T "[string map {. ,} $v] Go" "$v GB"]
    }
    return "[expr {int(round($o / 1e6))}][T " Mo" " MB"]"
  }
  set t [::moderne::json::get $manifeste base taille {}]
  return [expr {$t ne {} ? $t : [T "2,3 Go" "2.3 GB"]}]
}

### Gaby is on this computer
proc ::moderne::gaby::installee {} {
  set f {}
  catch {set f [trouverFichier]}
  expr {$f ne {} && [file exists [file rootname $f].si4]}
}

### "Download Gaby" before the first time, "Download complete Gaby again"
### after (it said "again" before any download, Yosha 2026-10-31)
proc ::moderne::gaby::libelleComplet {} {
  if {[installee]} { return [T "Retélécharger Gaby complète" "Download complete Gaby again"] }
  return [T "Télécharger Gaby" "Download Gaby"]
}

### Tools › Gaby, when it opens: the labels of the moment
proc ::moderne::gaby::majMenu {m} {
  catch {$m entryconfigure 1 -label [libelleComplet]}
}

### From the menu: asked first (a long download)
proc ::moderne::gaby::confirmerGrande {} {
  if {[installee]} {
    set q [T "Retélécharger Gaby complète ?" "Download complete Gaby again?"]
  } else {
    set q [T "Télécharger Gaby ?" "Download Gaby?"]
  }
  set r [tk_messageBox -parent . -icon question -type yesno -title Gaby -message "$q\n\n[T \
      "Environ [tailleComplet] à télécharger, puis à décompresser : cela peut prendre quelques minutes. Tu peux continuer à utiliser Siby pendant ce temps." \
      "About [tailleComplet] to download, then to unzip: it may take a few minutes. You can keep using Siby meanwhile."]"]
  if {$r eq "yes"} { grandeMaj 1 }
}

### Notice at the bottom right with a button (big update offered)
proc ::moderne::gaby::proposerComplet {raison {garder 0}} {
  catch {::moderne::nsb::finAnnonce}
  set w .gabyComplet
  catch {destroy $w}
  frame $w -background [::moderne::c surface2] -highlightthickness 1 \
      -highlightbackground [::moderne::c accent] -padx 14 -pady 10
  label $w.t -background [::moderne::c surface2] -foreground [::moderne::c texteFort] \
      -font font_Regular -justify left -wraplength 380 -text "$raison."
  label $w.d -background [::moderne::c surface2] -foreground [::moderne::c texteDoux] \
      -font font_Small -justify left -wraplength 380 -text [T \
      "Grosse mise à jour : Gaby complète ([dateAffichee], [tailleComplet]) est retéléchargée en arrière-plan, puis remplace l'ancienne." \
      "Big update: the complete Gaby ([dateAffichee], [tailleComplet]) is downloaded again in the background, then replaces the old one."]
  frame $w.b -background [::moderne::c surface2]
  ttk::button $w.b.ok -text [T "Retélécharger Gaby" "Download Gaby again"] \
      -command {destroy .gabyComplet ; ::moderne::gaby::grandeMaj 1}
  catch {$w.b.ok configure -style Accent.TButton}
  ttk::button $w.b.non -text [T "Plus tard" "Later"] -command [list destroy $w]
  pack $w.b.non $w.b.ok -side right -padx {6 0}
  # (a copy changed on purpose: kept, the daily files applied to it)
  if {$garder} {
    ttk::button $w.b.garder -text [T "Garder ma copie" "Keep my copy"] -command ::moderne::gaby::garderCopie
    pack $w.b.garder -side right -padx {6 0} -after $w.b.non
  }
  pack $w.t $w.d -side top -anchor w -pady {0 6}
  pack $w.b -side top -fill x
  place $w -in . -relx 1.0 -rely 1.0 -x -18 -y -18 -anchor se
  raise $w
}

### "Keep my copy": taken as the published version from now on, the daily
### files applied (never asked again)
proc ::moderne::gaby::garderCopie {} {
  catch {destroy .gabyComplet}
  set e [lireEtat]
  dict set e copie_gardee [aujourdhui]
  catch {ecrireEtat $e}
  after idle {catch {::moderne::gaby::verifier 1}}
}

### Progress of the big update (bottom right, with a Cancel button)
proc ::moderne::gaby::progres {texte {pct -1}} {
  set w .gabyGrande
  if {![winfo exists $w]} {
    frame $w -background [::moderne::c surface2] -highlightthickness 1 \
        -highlightbackground [::moderne::c accent] -padx 14 -pady 10
    label $w.t -background [::moderne::c surface2] -foreground [::moderne::c texteFort] \
        -font font_Regular -justify left -wraplength 380
    ttk::progressbar $w.p -length 380 -maximum 100
    frame $w.b -background [::moderne::c surface2]
    ttk::button $w.b.annuler -text [T "Annuler" "Cancel"] -command ::moderne::gaby::annulerGrande
    pack $w.b.annuler -side right
    label $w.s -background [::moderne::c surface2] -foreground [::moderne::c texteDoux] \
        -font font_Small -justify left -wraplength 380
    pack $w.t -side top -anchor w
    pack $w.p -side top -fill x -pady {8 4}
    pack $w.s -side top -anchor w -pady {0 6}
    pack $w.b -side top -fill x
    place $w -in . -relx 1.0 -rely 1.0 -x -18 -y -18 -anchor se
  }
  $w.t configure -text $texte
  # time left in this step (from its progress so far), and a reminder that
  # Siby can be used meanwhile
  variable etapeDebut
  set etape [regsub -all {[0-9 %().,/]+} $texte {}]
  if {![info exists etapeDebut] || [lindex $etapeDebut 0] ne $etape || $pct < [lindex $etapeDebut 2]} {
    set etapeDebut [list $etape [clock seconds] [expr {max(0, $pct)}]]
  }
  set reste {}
  lassign $etapeDebut - t0 p0
  set ecoule [expr {[clock seconds] - $t0}]
  if {$pct > $p0 + 2 && $ecoule >= 5} {
    set s [expr {int(double($ecoule) * (100 - $pct) / ($pct - $p0))}]
    if {$s >= 90} {
      set reste "[T "Encore environ" "About"] [expr {($s + 30) / 60}] min[T {} { left}]"
    } else {
      set reste [T "Encore moins de 2 min" "Less than 2 min left"]
    }
  } elseif {$pct >= 0} {
    set reste [T "Cela peut prendre quelques minutes" "This may take a few minutes"]
  }
  $w.s configure -text [expr {$reste ne {} ? "$reste • [T "tu peux continuer à utiliser Siby" "you can keep using Siby"]" \
      : [T "Tu peux continuer à utiliser Siby" "You can keep using Siby"]}]
  if {$pct >= 0} {
    $w.p configure -mode determinate -value $pct
  } else {
    $w.p configure -mode indeterminate
    catch {$w.p start 15}
  }
  raise $w
}

proc ::moderne::gaby::finProgres {{texte {}}} {
  catch {destroy .gabyGrande}
  if {$texte ne {}} {
    ::moderne::nsb::annonce $texte -1
    after 4000 ::moderne::nsb::finAnnonce
  }
}

### manuel: asked by the user (messages shown); else the weekly / monthly
### option (silent without network)
proc ::moderne::gaby::grandeMaj {{manuelDemande 1}} {
  variable enCours
  variable manuel
  variable manifeste
  variable grand
  if {$enCours} {
    if {$manuelDemande} { ::moderne::nsb::annonce [T "Gaby : mise à jour déjà en cours…" "Gaby: update already in progress…"] -1 ; after 3000 ::moderne::nsb::finAnnonce }
    return
  }
  trouverFichier
  variable fichier
  array unset grand
  if {$fichier eq {} || ![file exists [file rootname $fichier].si4]} {
    # first install (no Gaby on this computer yet): asked from the menu or
    # the settings, it goes into Siby's folder (or the file chosen in the
    # settings)
    if {!$manuelDemande} { return }
    if {$fichier eq {}} { set fichier [file join $::sibyDocsDir Gaby gaby.si4] }
    if {[catch {file mkdir [file dirname $fichier]} err]} {
      set fichier {}
      echec [T "Gaby : dossier impossible à créer" "Gaby: cannot create the folder"] $err
      return
    }
    set grand(premiere) 1
  }
  set enCours 1
  set manuel $manuelDemande
  set grand(etape) manifeste
  progres [T "Gaby : lecture de la fiche de mise à jour…" "Gaby: reading the update manifest…"]
  set m [file join [dossierTemp] gaby_manifest.json]
  file delete -force $m
  recuperer [adresseManifeste] $m ::moderne::gaby::grandeManifeste 30
}

proc ::moderne::gaby::echecGrande {titre detail} {
  variable grand
  catch ::moderne::gaby::partiesFermerTout
  catch {file delete -force {*}[glob -nocomplain -directory [dossierTemp] gaby_complete*]}
  if {[info exists grand(dossierNouveau)]} { catch {file delete -force $grand(dossierNouveau)} }
  finProgres
  echec $titre $detail
}

proc ::moderne::gaby::grandeManifeste {fichierM err} {
  variable manifeste
  variable grand
  if {$fichierM eq {}} {
    echecGrande [T "Gaby : serveur de mise à jour injoignable" "Gaby: update server unreachable"] $err
    return
  }
  if {[catch {
    set c [open $fichierM r]
    fconfigure $c -encoding utf-8
    set manifeste [::moderne::json::parse [read $c]]
    close $c
  } err]} {
    echecGrande [T "Gaby : fiche de mise à jour illisible" "Gaby: unreadable update manifest"] $err
    return
  }
  if {[partiesDispo]} { partiesDebut ; return }
  set lien [lienComplet]
  if {$lien eq {}} {
    echecGrande [T "Gaby : pas de base complète dans la fiche de mise à jour" "Gaby: no complete database in the update manifest"] {}
    return
  }
  set grand(zip) [file join [dossierTemp] gaby_complete.zip]
  file delete -force $grand(zip)
  set grand(octets) [::moderne::json::get $manifeste base octets 0]
  set grand(debut) [clock seconds]
  progres "[T "Gaby complète" "Complete Gaby"] ([dateAffichee], [tailleComplet])[T " : " ": "][T "téléchargement…" "downloading…"]" 0
  if {[regexp {^[a-z]+://} $lien]} {
    set grand(lien) $lien
    set grand(essais) 0
    # (in pieces of 400 MB when the manifest lists them, several at a time:
    # Cloudflare caches them and they resume; one stream of 2.4 GB was a few
    # MB/s on a mobile network, 2026-10-30)
    set morceaux [::moderne::json::get $manifeste base morceaux {}]
    if {[llength $morceaux] && [::moderne::nsb::outil] ne {}} {
      morceauxDebut $morceaux
    } else {
      grandeTelecharger
    }
  } else {
    if {[catch {file copy -force $lien $grand(zip)} err]} {
      echecGrande [T "Gaby : téléchargement impossible" "Gaby: download failed"] $err
      return
    }
    after idle ::moderne::gaby::grandeVerifier
  }
}

### The download (started again from the start when it breaks, 3 tries:
### a connection cut during 2 GB is not rare)
proc ::moderne::gaby::grandeTelecharger {{reprise 0}} {
  variable grand
  if {[info exists grand(annule)]} { return }
  incr grand(essais)
  # (resumed where it stopped when the server allows it, "Range"; from the
  # start otherwise)
  set cmd [list curl -sSLf --connect-timeout 20 -A "Siby (Gaby update)" -o $grand(zip)]
  if {$reprise && [file exists $grand(zip)] && [file size $grand(zip)] > 0} {
    lappend cmd -C -
    set grand(reprise) 1
  } else {
    file delete -force $grand(zip)
    set grand(reprise) 0
  }
  # (tests: slowed down, to cancel during the download)
  if {[info exists ::moderne::gaby::debitTest]} { lappend cmd --limit-rate $::moderne::gaby::debitTest }
  lappend cmd $grand(lien)
  if {[catch {open "|$cmd 2>@1" r} f]} {
    echecGrande [T "Gaby : téléchargement impossible" "Gaby: download failed"] $f
    return
  }
  set grand(canal) $f
  set grand(sortie) {}
  fconfigure $f -blocking 0
  fileevent $f readable [list ::moderne::gaby::grandeLu $f]
  after 1000 ::moderne::gaby::grandeSuivi
}

### ------------------------------------------------------------------------
### The complete Gaby in pieces (base.morceaux: {lien octets sha256}), up
### to morceauxMax at a time, each checked (sha256) and tried again alone,
### then joined in order into the zip
### ------------------------------------------------------------------------
namespace eval ::moderne::gaby { variable morceauxMax 5 }

proc ::moderne::gaby::morceauxDebut {morceaux} {
  variable grand
  set grand(morceaux) {}
  set i 0
  foreach m $morceaux {
    incr i
    set lien [adresseFichier [::moderne::json::get $m lien {}]]
    set f [file join [dossierTemp] [format "gaby_complete.part%03d" $i]]
    lappend grand(morceaux) [list $lien $f [::moderne::json::get $m octets 0] \
                                  [string tolower [::moderne::json::get $m sha256 {}]]]
    set grand(etat,$i) attente
    set grand(essais,$i) 0
  }
  set grand(nbMorceaux) $i
  set grand(canaux) {}
  morceauxSuivants
  after 1000 ::moderne::gaby::morceauxSuivi
}

### Starts pieces while fewer than morceauxMax are on the way
proc ::moderne::gaby::morceauxSuivants {} {
  variable grand
  variable morceauxMax
  if {[info exists grand(annule)]} { return }
  set actifs 0
  for {set i 1} {$i <= $grand(nbMorceaux)} {incr i} {
    if {$grand(etat,$i) in {telechargement verification}} { incr actifs }
  }
  for {set i 1} {$i <= $grand(nbMorceaux) && $actifs < $morceauxMax} {incr i} {
    if {$grand(etat,$i) ne "attente"} { continue }
    morceauLancer $i
    incr actifs
  }
  # all checked: joined
  set ok 1
  for {set i 1} {$i <= $grand(nbMorceaux)} {incr i} { if {$grand(etat,$i) ne "ok"} { set ok 0 } }
  if {$ok} { morceauxJoindre }
}

proc ::moderne::gaby::morceauLancer {i} {
  variable grand
  lassign [lindex $grand(morceaux) [expr {$i - 1}]] lien f octets sha
  incr grand(essais,$i)
  # (resumed where it stopped: the pieces answer Range requests)
  set cmd [list curl -sSLf --connect-timeout 20 -A "Siby (Gaby update)" -o $f]
  if {[file exists $f] && [file size $f] > 0 && [file size $f] < $octets} { lappend cmd -C - } \
  elseif {[file exists $f]} { file delete -force $f }
  if {[info exists ::moderne::gaby::debitTest]} { lappend cmd --limit-rate $::moderne::gaby::debitTest }
  lappend cmd $lien
  if {[catch {open "|$cmd 2>@1" r} c]} { morceauEchec $i $c ; return }
  set grand(etat,$i) telechargement
  set grand(sortie,$i) {}
  lappend grand(canaux) $c
  fconfigure $c -blocking 0
  fileevent $c readable [list ::moderne::gaby::morceauLu $i $c]
}

proc ::moderne::gaby::morceauLu {i c} {
  variable grand
  append grand(sortie,$i) [read $c]
  if {![eof $c]} { return }
  fconfigure $c -blocking 1
  set code [catch {close $c} err]
  set k [lsearch -exact $grand(canaux) $c]
  if {$k >= 0} { set grand(canaux) [lreplace $grand(canaux) $k $k] }
  if {[info exists grand(annule)]} { return }
  lassign [lindex $grand(morceaux) [expr {$i - 1}]] lien f octets sha
  set n 0
  catch {set n [file size $f]}
  if {$code || $n != $octets} {
    noterTelechargement "morceau $i coupé à $n / $octets octets (essai $grand(essais,$i)) : [string trim $grand(sortie,$i)]"
    # (no resuming on this server, or a piece too long: from the start)
    if {[regexp -nocase {byte ranges|resume|\(33\)} $grand(sortie,$i)] || $n > $octets} { catch {file delete -force $f} }
    morceauEchec $i [string trim "$grand(sortie,$i) $err"]
    return
  }
  # its SHA-256, in a separate process
  if {$sha eq {}} { set grand(etat,$i) ok ; morceauxSuivants ; return }
  set grand(etat,$i) verification
  if {[catch {open [list | [::moderne::nsb::outil] --sha256 $f] r} v]} { set grand(etat,$i) ok ; morceauxSuivants ; return }
  set grand(sha,$i) {}
  fconfigure $v -blocking 0
  fileevent $v readable [list ::moderne::gaby::morceauSha $i $v]
}

proc ::moderne::gaby::morceauSha {i v} {
  variable grand
  append grand(sha,$i) [read $v]
  if {![eof $v]} { return }
  catch {close $v}
  if {[info exists grand(annule)]} { return }
  lassign [lindex $grand(morceaux) [expr {$i - 1}]] lien f octets sha
  if {![regexp {SHA256 ([0-9a-f]{64})} $grand(sha,$i) -> h] || $h ne $sha} {
    noterTelechargement "morceau $i abîmé (sha256), essai $grand(essais,$i)"
    catch {file delete -force $f}
    morceauEchec $i sha256
    return
  }
  set grand(etat,$i) ok
  morceauxSuivants
}

### A piece cut or damaged: tried again alone (3 times), else the whole
### update fails and the old database is kept
proc ::moderne::gaby::morceauEchec {i detail} {
  variable grand
  if {$grand(essais,$i) < 3} {
    set grand(etat,$i) pause
    after 3000 [list ::moderne::gaby::morceauRelancer $i]
    return
  }
  morceauxArreter
  echecGrande [T "Gaby : téléchargement impossible, l'ancienne base est gardée" "Gaby: download failed, the old database is kept"] $detail
}

proc ::moderne::gaby::morceauRelancer {i} {
  variable grand
  if {[info exists grand(annule)] || ![info exists grand(etat,$i)]} { return }
  set grand(etat,$i) attente
  morceauxSuivants
}

### The pieces on the way stopped (cancel, failure)
proc ::moderne::gaby::morceauxArreter {} {
  variable grand
  if {![info exists grand(canaux)]} { return }
  foreach c $grand(canaux) {
    foreach p [pid $c] {
      if {$::windowsOS} { catch {exec taskkill /F /PID $p} } else { catch {exec kill $p} }
    }
    catch {close $c}
  }
  set grand(canaux) {}
}

proc ::moderne::gaby::morceauxSuivi {} {
  variable grand
  if {[info exists grand(annule)] || ![info exists grand(nbMorceaux)] || [info exists grand(joint)]} { return }
  set n 0
  set total 0
  foreach m $grand(morceaux) {
    lassign $m lien f octets
    incr total $octets
    catch {incr n [file size $f]}
  }
  if {$total > 0} {
    set pct [expr {min(99, int(100.0 * $n / $total))}]
    progres "[T "Gaby complète" "Complete Gaby"] ([dateAffichee])[T " : " ": "][T "téléchargement" "downloading"] $pct\u00a0% ([expr {$n / 1048576}] / [expr {$total / 1048576}]\u00a0[T Mo MB])" $pct
  }
  after 1000 ::moderne::gaby::morceauxSuivi
}

### The pieces joined in order into the zip (without blocking), then the
### zip checked and unzipped as before
proc ::moderne::gaby::morceauxJoindre {} {
  variable grand
  if {[info exists grand(joint)]} { return }
  set grand(joint) 1
  noterTelechargement "morceaux complets : $grand(nbMorceaux)"
  progres [T "Gaby complète : assemblage des morceaux…" "Complete Gaby: joining the pieces…"]
  file delete -force $grand(zip)
  set grand(sortieZip) [open $grand(zip) wb]
  set grand(copie) [list $grand(sortieZip)]
  morceauJoindre 1
}

proc ::moderne::gaby::morceauJoindre {i} {
  variable grand
  if {[info exists grand(annule)]} { return }
  if {$i > $grand(nbMorceaux)} {
    catch {close $grand(sortieZip)}
    unset -nocomplain grand(copie)
    foreach m $grand(morceaux) { catch {file delete -force [lindex $m 1]} }
    grandeVerifier
    return
  }
  set in [open [lindex $grand(morceaux) [expr {$i - 1}] 1] rb]
  lappend grand(copie) $in
  chan copy $in $grand(sortieZip) -command [list ::moderne::gaby::morceauCopie $i $in]
}

proc ::moderne::gaby::morceauCopie {i in n {err {}}} {
  variable grand
  catch {close $in}
  if {[info exists grand(annule)]} { return }
  if {$err ne {}} {
    catch {close $grand(sortieZip)}
    echecGrande [T "Gaby : assemblage impossible, l'ancienne base est gardée" "Gaby: joining failed, the old database is kept"] $err
    return
  }
  morceauJoindre [expr {$i + 1}]
}

### Download progress (size of the file so far)
proc ::moderne::gaby::grandeSuivi {} {
  variable grand
  if {![info exists grand(canal)]} { return }
  set n 0
  catch {set n [file size $grand(zip)]}
  set mo [expr {$n / 1048576}]
  # (in two parts: the piece being downloaded, not "Complete Gaby")
  set quoi "[T "Gaby complète" "Complete Gaby"] ([dateAffichee])"
  if {[info exists grand(item)] && [info exists grand(nbTelech)]} {
    set quoi "Gaby ([dict get $grand(item) num]/$grand(nbTelech), [dict get $grand(item) titre])"
  }
  if {$grand(octets) > 0} {
    set pct [expr {min(99, int(100.0 * $n / $grand(octets)))}]
    progres "$quoi[T " : " ": "][T "téléchargement" "downloading"] $pct\u00a0% ($mo / [expr {$grand(octets) / 1048576}]\u00a0[T Mo MB])" $pct
  } else {
    progres "$quoi[T " : " ": "][T "téléchargement" "downloading"] $mo\u00a0[T Mo MB]"
  }
  after 1000 ::moderne::gaby::grandeSuivi
}

proc ::moderne::gaby::grandeLu {f} {
  variable grand
  append grand(sortie) [read $f]
  if {![eof $f]} { return }
  fconfigure $f -blocking 1
  set code [catch {close $f} err]
  unset -nocomplain grand(canal)
  if {[info exists grand(annule)]} { return }
  set taille 0
  catch {set taille [file size $grand(zip)]}
  if {$code || ![file exists $grand(zip)]} {
    set msg [string trim $grand(sortie)]
    noterTelechargement "coupé à $taille / $grand(octets) octets (essai $grand(essais), reprise $grand(reprise)) : $msg"
    # (cut or refused on the way: tried again, except for a missing file;
    # resumed if the server allows it, else from the start)
    if {$grand(essais) < 3 && ![string match "*returned error: 4*" $msg]} {
      set reprise [expr {![regexp -nocase {byte ranges|resume|\(33\)} $msg]}]
      puts stderr "Siby Gaby: download broken ($msg), try [expr {$grand(essais) + 1}]"
      progres "[T "Gaby complète : connexion coupée, nouvel essai" "Complete Gaby: connection cut, trying again"] ([expr {$grand(essais) + 1}]/3)…"
      after 3000 [list ::moderne::gaby::grandeTelecharger $reprise]
      return
    }
    echecGrande [T "Gaby : téléchargement impossible, l'ancienne base est gardée" "Gaby: download failed, the old database is kept"] \
        [expr {$msg ne {} ? $msg : $err}]
    return
  }
  noterTelechargement "complet : $taille octets (essai $grand(essais), reprise $grand(reprise))"
  grandeVerifier
}

### Log of the complete Gaby's downloads (gaby-update/telechargements.log in
### Siby's folder): how often they are cut, at what size, whether the retry
### worked. Kept on this computer only.
proc ::moderne::gaby::noterTelechargement {texte} {
  catch {
    set c [open [file join [dossierTemp] telechargements.log] a]
    puts $c "[clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}] $texte"
    close $c
  }
}

proc ::moderne::gaby::annulerGrande {} {
  variable grand
  variable enCours
  set grand(annule) 1
  catch morceauxArreter
  catch partiesFermerTout
  if {[info exists grand(canal)]} {
    set f $grand(canal)
    foreach p [pid $f] {
      if {$::windowsOS} { catch {exec taskkill /F /PID $p} } else { catch {exec kill $p} }
    }
    catch {close $f}
    unset -nocomplain grand(canal)
  }
  if {[info exists grand(copie)]} {
    foreach c $grand(copie) { catch {close $c} }
    unset grand(copie)
  }
  catch {file delete -force {*}[glob -nocomplain -directory [dossierTemp] gaby_complete*]}
  if {[info exists grand(dossierNouveau)]} { catch {file delete -force $grand(dossierNouveau)} }
  set enCours 0
  finProgres [T "Gaby : grosse mise à jour annulée, l'ancienne base est gardée" "Gaby: big update cancelled, the old database is kept"]
}

### SHA-256 of the archive, in a separate process (sbbiblio --sha256)
proc ::moderne::gaby::grandeVerifier {} {
  variable manifeste
  variable grand
  set attendu [string tolower [::moderne::json::get $manifeste base sha256 {}]]
  # (Gaby in two parts: the file being downloaded)
  set suite [expr {[info exists grand(parties)] ? "partiesExtraire" : "grandeExtraire"}]
  if {[info exists grand(parties)]} { set attendu $grand(shaAttendu) }
  set exe [::moderne::nsb::outil]
  if {$attendu eq {} || $exe eq {}} { $suite ; return }
  progres [T "Gaby complète : vérification du fichier…" "Complete Gaby: checking the file…"]
  if {[catch {open [list | $exe --sha256 $grand(zip)] r} f]} { $suite ; return }
  set grand(sha) {}
  fconfigure $f -blocking 0
  fileevent $f readable [list ::moderne::gaby::grandeSha $f $attendu]
}

proc ::moderne::gaby::grandeSha {f attendu} {
  variable grand
  append grand(sha) [read $f]
  if {![eof $f]} { return }
  catch {close $f}
  if {[info exists grand(annule)]} { return }
  if {![regexp {SHA256 ([0-9a-f]{64})} $grand(sha) -> h] || $h ne $attendu} {
    echecGrande [T "Gaby : fichier abîmé pendant le téléchargement (sha256), l'ancienne base est gardée" \
        "Gaby: file damaged during the download (sha256), the old database is kept"] {}
    return
  }
  if {[info exists grand(parties)]} { partiesExtraire ; return }
  grandeExtraire
}

################################################################################
### Reading a .zip (stored or deflated entries, zip64), without blocking:
### each entry is copied with "chan copy -command" through "zlib push inflate"
################################################################################

proc ::moderne::gaby::u16 {b i} { binary scan $b @${i}su v ; return $v }
proc ::moderne::gaby::u32 {b i} { binary scan $b @${i}iu v ; return $v }
proc ::moderne::gaby::u64 {b i} { binary scan $b @${i}wu v ; return $v }

### Entries of the archive: list of {name method compressed size dataOffset}
proc ::moderne::gaby::lireZip {fichier} {
  set c [open $fichier rb]
  set taille [file size $fichier]
  set lu [expr {min($taille, 65557)}]
  seek $c [expr {$taille - $lu}]
  set fin [read $c $lu]
  set i [string last [binary format iu 0x06054b50] $fin]
  if {$i < 0} { close $c ; error "zip: no central directory" }
  set nb [u16 $fin [expr {$i + 10}]]
  set cdTaille [u32 $fin [expr {$i + 12}]]
  set cdDebut [u32 $fin [expr {$i + 16}]]
  if {$nb == 0xFFFF || $cdDebut == 0xFFFFFFFF} {
    # zip64: locator just before, then the zip64 record
    set j [string last [binary format iu 0x07064b50] $fin]
    if {$j < 0} { close $c ; error "zip64: no locator" }
    set pos64 [u64 $fin [expr {$j + 8}]]
    seek $c $pos64
    set r [read $c 56]
    if {[u32 $r 0] != 0x06064b50} { close $c ; error "zip64: bad record" }
    set nb [u64 $r 32]
    set cdTaille [u64 $r 40]
    set cdDebut [u64 $r 48]
  }
  seek $c $cdDebut
  set cd [read $c $cdTaille]
  set res {}
  set p 0
  for {set k 0} {$k < $nb} {incr k} {
    if {[u32 $cd $p] != 0x02014b50} { close $c ; error "zip: bad central entry" }
    set methode [u16 $cd [expr {$p + 10}]]
    set comp [u32 $cd [expr {$p + 20}]]
    set dec [u32 $cd [expr {$p + 24}]]
    set ln [u16 $cd [expr {$p + 28}]]
    set le [u16 $cd [expr {$p + 30}]]
    set lc [u16 $cd [expr {$p + 32}]]
    set loc [u32 $cd [expr {$p + 42}]]
    set nom [encoding convertfrom utf-8 [string range $cd [expr {$p + 46}] [expr {$p + 45 + $ln}]]]
    # zip64 extra field: the 0xFFFFFFFF sizes / offset, in that order
    set x [expr {$p + 46 + $ln}]
    set xf [expr {$x + $le}]
    while {$x + 4 <= $xf} {
      set id [u16 $cd $x]
      set lg [u16 $cd [expr {$x + 2}]]
      if {$id == 1} {
        set q [expr {$x + 4}]
        if {$dec == 0xFFFFFFFF} { set dec [u64 $cd $q] ; incr q 8 }
        if {$comp == 0xFFFFFFFF} { set comp [u64 $cd $q] ; incr q 8 }
        if {$loc == 0xFFFFFFFF} { set loc [u64 $cd $q] ; incr q 8 }
      }
      incr x [expr {4 + $lg}]
    }
    seek $c $loc
    set lh [read $c 30]
    if {[u32 $lh 0] != 0x04034b50} { close $c ; error "zip: bad local entry" }
    set donnees [expr {$loc + 30 + [u16 $lh 26] + [u16 $lh 28]}]
    if {$methode != 0 && $methode != 8} { close $c ; error "zip: unsupported method $methode ($nom)" }
    # (the Unix rights, made on Linux or macOS: the upper half of the
    # external attributes; 0 otherwise)
    set droits [expr {[u16 $cd [expr {$p + 4}]] >> 8 == 3 ? [u32 $cd [expr {$p + 38}]] >> 16 & 0o777 : 0}]
    lappend res [list $nom $methode $comp $dec $donnees $droits]
    set p [expr {$p + 46 + $ln + $le + $lc}]
  }
  close $c
  return $res
}

### Unzips the archive into a folder next to Gaby (same disk: the files
### are then just renamed)
proc ::moderne::gaby::grandeExtraire {} {
  variable grand
  variable fichier
  if {[catch {set grand(entrees) [lireZip $grand(zip)]} err]} {
    echecGrande [T "Gaby : archive illisible, l'ancienne base est gardée" "Gaby: unreadable archive, the old database is kept"] $err
    return
  }
  # the files of the database: the root name of the .si4 in the archive
  set grand(racineZip) {}
  foreach e $grand(entrees) {
    if {[string match -nocase *.si4 [lindex $e 0]]} { set grand(racineZip) [file rootname [file tail [lindex $e 0]]] }
  }
  set noms {}
  foreach e $grand(entrees) { lappend noms [string tolower [file tail [lindex $e 0]]] }
  foreach x {si4 sn4 sg4} {
    if {[string tolower "$grand(racineZip).$x"] ni $noms} {
      echecGrande [T "Gaby : archive incomplète (.si4, .sn4 et .sg4 attendus), l'ancienne base est gardée" \
          "Gaby: incomplete archive (.si4, .sn4 and .sg4 expected), the old database is kept"] {}
      return
    }
  }
  set grand(dossierNouveau) [file join [file dirname $fichier] gaby_nouvelle]
  catch {file delete -force $grand(dossierNouveau)}
  file mkdir $grand(dossierNouveau)
  set grand(total) 0
  foreach e $grand(entrees) { incr grand(total) [lindex $e 3] }
  set grand(fait) 0
  set grand(file) $grand(entrees)
  # the system's own tool first (5 to 10 times quicker: tar on Windows 10
  # and 11, unzip on Linux and macOS); Siby's own reading if it is missing
  # or fails
  if {[grandeExtraireNatif]} { return }
  grandeEntree
}

### Native unzip command for the archive into folder dir, empty if none
proc ::moderne::gaby::commandeDezip {zip dir} {
  if {$::windowsOS} {
    set t {}
    catch {set t [file join $::env(SystemRoot) System32 tar.exe]}
    if {$t ne {} && [file exists $t]} { return [list $t -xf $zip -C $dir] }
    return {}
  }
  set u [auto_execok unzip]
  if {$u ne {}} { return [list {*}$u -o -q $zip -d $dir] }
  set b [auto_execok bsdtar]
  if {$b ne {}} { return [list {*}$b -xf $zip -C $dir] }
  return {}
}

proc ::moderne::gaby::grandeExtraireNatif {} {
  variable grand
  if {[info exists grand(sansNatif)]} { return 0 }
  set cmd [commandeDezip $grand(zip) $grand(dossierNouveau)]
  if {$cmd eq {}} { return 0 }
  if {[catch {open "|$cmd 2>@1" r} f]} { return 0 }
  set grand(canal) $f
  set grand(sortie) {}
  fconfigure $f -blocking 0
  fileevent $f readable [list ::moderne::gaby::grandeNatifLu $f]
  after 500 ::moderne::gaby::grandeSuiviNatif
  return 1
}

### Progress: size of the folder against the total of the entries
proc ::moderne::gaby::grandeSuiviNatif {} {
  variable grand
  if {![info exists grand(canal)] || ![info exists grand(dossierNouveau)]} { return }
  set n 0
  foreach f [glob -nocomplain -directory $grand(dossierNouveau) -types f *] { catch {incr n [file size $f]} }
  set pct [expr {$grand(total) > 0 ? min(99, int(100.0 * $n / $grand(total))) : 0}]
  progres "[T "Gaby complète : décompression" "Complete Gaby: unzipping"] $pct\u00a0%" $pct
  after 500 ::moderne::gaby::grandeSuiviNatif
}

proc ::moderne::gaby::grandeNatifLu {f} {
  variable grand
  append grand(sortie) [read $f]
  if {![eof $f]} { return }
  fconfigure $f -blocking 1
  set code [catch {close $f} err]
  unset -nocomplain grand(canal)
  if {[info exists grand(annule)]} { return }
  # the files of the database, renamed gaby.* (their size checked)
  set ok [expr {!$code}]
  if {$ok} {
    foreach e $grand(entrees) {
      lassign $e nom methode comp dec donnees
      set t [file tail $nom]
      set ext [string range $t [string length $grand(racineZip)] end]
      if {$t eq {} || ![string match -nocase "$grand(racineZip).*" $t]
          || [string tolower $ext] ni {.si4 .sn4 .sg4 .sbl .online.sbl .classical.sbl .classical.online.sbl .rapid.sbl .rapid.online.sbl .blitz.sbl .blitz.online.sbl .sbp .sbc .maj.json}} { continue }
      set source [file join $grand(dossierNouveau) {*}[file split $nom]]
      if {![file exists $source] || [file size $source] != $dec} { set ok 0 ; break }
      set dest [file join $grand(dossierNouveau) "gaby[string tolower $ext]"]
      if {$source ne $dest && [catch {file rename -force $source $dest}]} { set ok 0 ; break }
    }
  }
  if {!$ok} {
    # (Siby's own reading, from the start)
    puts stderr "Siby Gaby: native unzip failed, Siby unzips itself: [string trim $grand(sortie)] $err"
    set grand(sansNatif) 1
    catch {file delete -force $grand(dossierNouveau)}
    file mkdir $grand(dossierNouveau)
    set grand(fait) 0
    set grand(file) $grand(entrees)
    grandeEntree
    return
  }
  # (anything else the archive held: not part of the database)
  foreach f [glob -nocomplain -directory $grand(dossierNouveau) *] {
    if {![string match gaby.* [file tail $f]]} { catch {file delete -force $f} }
  }
  grandeRemplacer
}

proc ::moderne::gaby::grandeEntree {} {
  variable grand
  if {[info exists grand(annule)]} { return }
  if {![llength $grand(file)]} { grandeRemplacer ; return }
  lassign [lindex $grand(file) 0] nom methode comp dec donnees
  set grand(file) [lrange $grand(file) 1 end]
  set t [file tail $nom]
  # (folders and files other than those of the database are ignored)
  set ext [string range $t [string length $grand(racineZip)] end]
  if {$t eq {} || ![string match -nocase "$grand(racineZip).*" $t]
      || [string tolower $ext] ni {.si4 .sn4 .sg4 .sbl .online.sbl .classical.sbl .classical.online.sbl .rapid.sbl .rapid.online.sbl .blitz.sbl .blitz.online.sbl .sbp .sbc .maj.json}} {
    after idle ::moderne::gaby::grandeEntree
    return
  }
  set ext [string tolower $ext]
  if {[catch {
    set in [open $grand(zip) rb]
    seek $in $donnees
    if {$methode == 8} { zlib push inflate $in }
    set out [open [file join $grand(dossierNouveau) "gaby$ext"] wb]
  } err]} {
    echecGrande [T "Gaby : extraction impossible, l'ancienne base est gardée" "Gaby: unzipping failed, the old database is kept"] $err
    return
  }
  set grand(copie) [list $in $out]
  set grand(entreeTaille) $dec
  set grand(sortieFichier) [file join $grand(dossierNouveau) "gaby$ext"]
  after 500 ::moderne::gaby::grandeSuiviExtraction
  chan copy $in $out -size $dec -command [list ::moderne::gaby::grandeCopie $in $out $dec]
}

proc ::moderne::gaby::grandeSuiviExtraction {} {
  variable grand
  if {![info exists grand(copie)]} { return }
  set n 0
  catch {set n [file size $grand(sortieFichier)]}
  set pct [expr {$grand(total) > 0 ? min(99, int(100.0 * ($grand(fait) + $n) / $grand(total))) : 0}]
  progres "[T "Gaby complète : décompression" "Complete Gaby: unzipping"] $pct\u00a0%" $pct
  after 500 ::moderne::gaby::grandeSuiviExtraction
}

proc ::moderne::gaby::grandeCopie {in out dec n {err {}}} {
  variable grand
  catch {close $in}
  set code [catch {close $out} err2]
  unset -nocomplain grand(copie)
  if {[info exists grand(annule)]} { return }
  if {$err ne {} || $code || $n != $dec} {
    echecGrande [T "Gaby : extraction impossible (disque plein ?), l'ancienne base est gardée" \
        "Gaby: unzipping failed (disk full?), the old database is kept"] "$err $err2"
    return
  }
  incr grand(fait) $dec
  after idle ::moderne::gaby::grandeEntree
}

### The new database replaces the old one (put back on failure), which
### is then deleted
proc ::moderne::gaby::grandeRemplacer {} {
  variable grand
  variable manifeste
  variable fichier
  variable enCours
  if {[occupe]} { after 2000 ::moderne::gaby::grandeRemplacer ; return }
  catch {file delete -force $grand(zip)}
  progres [T "Gaby complète : remplacement de l'ancienne base…" "Complete Gaby: replacing the old database…"]
  set racine [file rootname $fichier]
  set dossier [file dirname $racine]
  set ancien [file join $dossier gaby_ancienne]
  catch {file delete -force $ancien}
  file mkdir $ancien
  set courante [sc_base current]
  set b [baseOuverte]
  set etaitCourante [expr {$b > 0 && $b == $courante}]
  if {$b > 0} { catch {sc_base close $b} }
  set deplaces {}
  set places {}
  set code [catch {
    # (only the files of the database: a gaby.pgn next to it is left alone)
    foreach ext {.si4 .sn4 .sg4 .sbl .online.sbl .ajouts.sbl .ajouts.online.sbl .classical.sbl .classical.online.sbl .rapid.sbl .rapid.online.sbl .blitz.sbl .blitz.online.sbl
                 .classical.ajouts.sbl .classical.ajouts.online.sbl .rapid.ajouts.sbl .rapid.ajouts.online.sbl
                 .blitz.ajouts.sbl .blitz.ajouts.online.sbl .sbp .sbc
                 .maj.json .si4.sauvegarde .sn4.sauvegarde .nsb .online.nsb .nsp .sia} {
      set f "$racine$ext"
      if {![file exists $f]} { continue }
      file rename -force $f [file join $ancien [file tail $f]]
      lappend deplaces [file tail $f]
    }
    foreach f [glob -nocomplain -directory $grand(dossierNouveau) gaby.*] {
      set ext [string range [file tail $f] 4 end]
      file rename -force $f "$racine$ext"
      lappend places "$racine$ext"
    }
    # (Gaby in two parts: its online and correspondence databases beside it)
    foreach autre {en_ligne correspondance} {
      if {![file exists [file join $grand(dossierNouveau) gaby_$autre.si4]]} { continue }
      foreach ext {.si4 .sn4 .sg4} {
        set f "${racine}_$autre$ext"
        if {[file exists $f]} { file rename -force $f [file join $ancien [file tail $f]] ; lappend deplaces [file tail $f] }
        file rename -force [file join $grand(dossierNouveau) gaby_$autre$ext] $f
        lappend places $f
      }
    }
  } err]
  if {$code} {
    # put the old database back
    foreach f $places { catch {file delete -force $f} }
    foreach t $deplaces { catch {file rename -force [file join $ancien $t] [file join $dossier $t]} }
  }
  # state of the new database: its version, downloaded today
  if {!$code} {
    set e [lireEtat]
    if {![file exists [fichierEtat]] || [dict get $e base_version] eq {}} {
      set e [dict create base_version [baseVersion] telecharge_le {} derniere_maj {} derniere_verif {} base_sha256 {} ajoutees 0 appliques {}]
    }
    dict set e telecharge_le [aujourdhui]
    # A new complete database: its own version, and none of the daily files
    # applied to the old one is in it (they were kept, so they were not
    # applied again: 1,774 games missing after a big update, seen 2026-10-31)
    dict set e base_version [baseVersion]
    dict set e appliques {}
    dict set e ajoutees 0
    dict set e derniere_maj {}
    # (its SHA-256: a complete Gaby corrected later under the same version
    # name is then noticed)
    dict set e base_sha256 [string tolower [::moderne::json::get $manifeste base sha256 {}]]
    if {[info exists grand(parties)]} {
      dict set e base_sha256 [string tolower [::moderne::json::get $manifeste fusion sha256GabyIds {}]]
    }
    catch {ecrireEtat $e}
  }
  # (the new database's index read in the background first, as at
  # startup: opening 11 million games at once froze Siby 47 s)
  if {!$code && ([info exists grand(premiere)] || $b > 0) && ![catch {sc_base prepa $racine}]} {
    progres [T "Gaby : ouverture de la nouvelle base…" "Gaby: opening the new database…"]
    after 200 [list ::moderne::gaby::grandeAttendrePrepa $racine $b $etaitCourante $code $ancien 0]
    return
  }
  grandeFinir $racine $b $etaitCourante $code [expr {$code ? $err : {}}] $ancien
}

### The index read (or given up after 10 minutes): the end of the replacement
proc ::moderne::gaby::grandeAttendrePrepa {racine b etaitCourante code ancien n} {
  if {[lindex [sc_base prepa] 0] eq "encours" && $n < 3000} {
    after 200 [list ::moderne::gaby::grandeAttendrePrepa $racine $b $etaitCourante $code $ancien [incr n]]
    return
  }
  grandeFinir $racine $b $etaitCourante $code {} $ancien
}

proc ::moderne::gaby::grandeFinir {racine b etaitCourante code err ancien} {
  variable grand
  variable enCours
  # (first install: opened and added to My databases)
  if {!$code && [info exists grand(premiere)]} {
    if {![catch {sc_base open $racine} nb]} {
      catch {sc_base switch $nb}
      if {"$racine.si4" ni $::moderne::mesBases} { lappend ::moderne::mesBases $racine.si4 }
      catch {::windows::switcher::Refresh}
      catch {::windows::gamelist::Refresh}
    }
    catch {::options.write}
  }
  if {$b > 0} {
    if {![catch {sc_base open $racine} nb] && $etaitCourante} { catch {sc_base switch $nb} }
    catch {::windows::switcher::Refresh}
    catch {::windows::gamelist::Refresh}
    catch {updateBoard -pgn}
  }
  catch {file delete -force $grand(dossierNouveau)}
  unset -nocomplain grand(dossierNouveau)
  set enCours 0
  if {$code} {
    finProgres
    echec [T "Gaby : remplacement impossible, l'ancienne base est gardée" "Gaby: replacing failed, the old database is kept"] $err
    return
  }
  catch {file delete -force $ancien}
  finProgres "[T "Gaby complète installée" "Complete Gaby installed"] ([dateAffichee])"
  set b [baseOuverte]
  if {$b > 0} { catch {::moderne::nsb::verifier $b} }
  catch {updateStatusBar}
  # then the daily files published since
  after 3000 {::moderne::gaby::verifier 0}
}

################################################################################
### Gaby in two parts (from Gaby 2026.11): one part under each licence (A "lichess",
### CC BY-SA 4.0; B "autres", CC BY-NC 4.0), merged here into the same
### databases as the complete zip: gaby (main), gaby_en_ligne,
### gaby_correspondance. Each part is a subsequence of each merged
### database, its .ord files give its games' numbers there (sc_base
### fusion). The GabyIds in merged order are checked against the manifest
### (fusion.bases.*.sha256GabyIds); the libraries built by Gaby on the
### merged main database (bibliotheques: .sbl, .online.sbl, .sbp, .sbc)
### are then re-stamped for this copy (sc_nsb tamponner), else rebuilt in
### the background. Same steps and progress bar as the complete zip.
### Manifest: Gaby's docs/POUR_SCID_MODERNE.md, section 6 sexies.
################################################################################

namespace eval ::moderne::gaby {
  # (0: the complete zip even when the parts are listed)
  variable utiliserParties 1
  variable basesParties {principale gaby en_ligne gaby_en_ligne correspondance gaby_correspondance}
}

### The manifest lists the two parts and their merge
proc ::moderne::gaby::partiesDispo {} {
  variable manifeste
  variable utiliserParties
  if {!$utiliserParties} { return 0 }
  # (the complete zip first when the manifest has one: the parts are for
  # direct downloads from the site, Siby takes Gaby merged, no merging
  # wait; Yosha 2026-11-11)
  if {[lienComplet] ne {}} { return 0 }
  set p [::moderne::json::get $manifeste parties {}]
  return [expr {[llength $p] > 0 && [::moderne::json::get $manifeste fusion {}] ne {}}]
}

### The files to download: each part's zip (in pieces when listed), then
### the libraries
proc ::moderne::gaby::partiesDebut {} {
  variable manifeste
  variable grand
  variable fichier
  set grand(parties) 1
  set grand(dossierNouveau) [file join [file dirname $fichier] gaby_nouvelle]
  catch {file delete -force $grand(dossierNouveau)}
  file mkdir $grand(dossierNouveau)
  set grand(telech) {}
  set k 0
  foreach p [::moderne::json::get $manifeste parties {}] {
    set nom [::moderne::json::get $p nom partie]
    # (the manifest's title is French only: Siby names the parts itself)
    switch -- $nom {
      lichess { set titre [T "parties Lichess" "Lichess games"] }
      autres { set titre [T "autres sources" "other sources"] }
      default { set titre [::moderne::json::get $p titre $nom] }
    }
    foreach f [::moderne::json::get $p fichiers {}] {
      lappend grand(telech) [dict create titre $titre lien [::moderne::json::get $f fichier {}] \
          octets [::moderne::json::get $f octets 0] sha [string tolower [::moderne::json::get $f sha256 {}]] \
          morceaux [::moderne::json::get $f morceaux {}] dest [file join $grand(dossierNouveau) parties $nom] num [incr k]]
    }
  }
  set b [::moderne::json::get $manifeste bibliotheques {}]
  set lienB [::moderne::json::get $b lien [::moderne::json::get $b fichier {}]]
  if {$b ne {} && $lienB ne {}} {
    lappend grand(telech) [dict create titre [T "bibliothèques" "libraries"] lien $lienB \
        octets [::moderne::json::get $b octets 0] sha [string tolower [::moderne::json::get $b sha256 {}]] \
        morceaux [::moderne::json::get $b morceaux {}] dest [file join $grand(dossierNouveau) bibliotheques] num [incr k]]
  }
  set grand(nbTelech) $k
  if {!$k} {
    echecGrande [T "Gaby : pas de base complète dans la fiche de mise à jour" "Gaby: no complete database in the update manifest"] {}
    return
  }
  partiesSuivant
}

### Next file (the same download, checking and unzipping as the complete zip)
proc ::moderne::gaby::partiesSuivant {} {
  variable grand
  if {[info exists grand(annule)]} { return }
  if {![llength $grand(telech)]} { partiesFusion ; return }
  set grand(item) [lindex $grand(telech) 0]
  set grand(telech) [lrange $grand(telech) 1 end]
  set num [dict get $grand(item) num]
  set grand(zip) [file join [dossierTemp] [format gaby_complete_%02d.zip $num]]
  file delete -force $grand(zip)
  set grand(octets) [dict get $grand(item) octets]
  set grand(shaAttendu) [dict get $grand(item) sha]
  set grand(debut) [clock seconds]
  foreach v {joint nbMorceaux morceaux canaux sansNatif} { unset -nocomplain grand($v) }
  set lien [adresseFichier [dict get $grand(item) lien]]
  progres "Gaby ($num/$grand(nbTelech), [dict get $grand(item) titre])[T " : " ": "][T "téléchargement…" "downloading…"]" 0
  if {[regexp {^[a-z]+://} $lien]} {
    set grand(lien) $lien
    set grand(essais) 0
    set morceaux [dict get $grand(item) morceaux]
    if {[llength $morceaux] && [::moderne::nsb::outil] ne {}} {
      morceauxDebut $morceaux
    } else {
      grandeTelecharger
    }
    return
  }
  if {[catch {file copy -force $lien $grand(zip)} err]} {
    echecGrande [T "Gaby : téléchargement impossible" "Gaby: download failed"] $err
    return
  }
  after idle ::moderne::gaby::grandeVerifier
}

### Unzipping the current file into its folder (the system's tool, else
### Siby's own reading), then the next file
proc ::moderne::gaby::partiesExtraire {} {
  variable grand
  if {[catch {set grand(entrees) [lireZip $grand(zip)]} err]} {
    echecGrande [T "Gaby : archive illisible, l'ancienne base est gardée" "Gaby: unreadable archive, the old database is kept"] $err
    return
  }
  set dest [dict get $grand(item) dest]
  catch {file delete -force $dest}
  file mkdir $dest
  set grand(total) 0
  foreach e $grand(entrees) { incr grand(total) [lindex $e 3] }
  set grand(fait) 0
  set cmd [commandeDezip $grand(zip) $dest]
  if {$cmd ne {} && ![catch {open "|$cmd 2>@1" r} f]} {
    set grand(canal) $f
    set grand(sortie) {}
    fconfigure $f -blocking 0
    fileevent $f readable [list ::moderne::gaby::partiesNatifLu $f $dest]
    after 500 [list ::moderne::gaby::partiesSuiviExtraction $dest]
    return
  }
  partiesEntrees $dest
}

proc ::moderne::gaby::partiesSuiviExtraction {dest} {
  variable grand
  if {![info exists grand(canal)] && ![info exists grand(copie)]} { return }
  set n $grand(fait)
  foreach f [partiesFichiers $dest] { catch {incr n [file size $f]} }
  if {[info exists grand(copie)]} { set n $grand(fait) ; catch {incr n [file size $grand(sortieFichier)]} }
  set pct [expr {$grand(total) > 0 ? min(99, int(100.0 * $n / $grand(total))) : 0}]
  progres "Gaby ([dict get $grand(item) num]/$grand(nbTelech), [dict get $grand(item) titre])[T " : " ": "][T "décompression" "unzipping"] $pct %" $pct
  after 500 [list ::moderne::gaby::partiesSuiviExtraction $dest]
}

### Every file under a folder
proc ::moderne::gaby::partiesFichiers {dir} {
  set r [glob -nocomplain -directory $dir -types f *]
  foreach d [glob -nocomplain -directory $dir -types d *] { lappend r {*}[partiesFichiers $d] }
  return $r
}

proc ::moderne::gaby::partiesNatifLu {f dest} {
  variable grand
  append grand(sortie) [read $f]
  if {![eof $f]} { return }
  fconfigure $f -blocking 1
  set code [catch {close $f} err]
  unset -nocomplain grand(canal)
  if {[info exists grand(annule)]} { return }
  # (each entry there with its size, else Siby's own reading)
  set ok [expr {!$code}]
  if {$ok} {
    foreach e $grand(entrees) {
      lassign $e nom methode comp dec
      if {[string index $nom end] eq "/"} { continue }
      set x [file join $dest {*}[file split $nom]]
      if {![file exists $x] || [file size $x] != $dec} { set ok 0 ; break }
    }
  }
  if {!$ok} {
    puts stderr "Siby Gaby: native unzip failed, Siby unzips itself: [string trim $grand(sortie)] $err"
    catch {file delete -force $dest}
    file mkdir $dest
    partiesEntrees $dest
    return
  }
  partiesExtrait
}

### Siby's own reading: every entry, by its name without folders
proc ::moderne::gaby::partiesEntrees {dest} {
  variable grand
  set grand(file) $grand(entrees)
  set grand(fait) 0
  partiesEntree $dest
}

proc ::moderne::gaby::partiesEntree {dest} {
  variable grand
  if {[info exists grand(annule)]} { return }
  if {![llength $grand(file)]} { partiesExtrait ; return }
  lassign [lindex $grand(file) 0] nom methode comp dec donnees
  set grand(file) [lrange $grand(file) 1 end]
  set t [file tail $nom]
  if {$t eq {} || [string index $nom end] eq "/"} { after idle [list ::moderne::gaby::partiesEntree $dest] ; return }
  if {[catch {
    set in [open $grand(zip) rb]
    seek $in $donnees
    if {$methode == 8} { zlib push inflate $in }
    set out [open [file join $dest $t] wb]
  } err]} {
    echecGrande [T "Gaby : extraction impossible, l'ancienne base est gardée" "Gaby: unzipping failed, the old database is kept"] $err
    return
  }
  set grand(copie) [list $in $out]
  set grand(sortieFichier) [file join $dest $t]
  after 500 [list ::moderne::gaby::partiesSuiviExtraction $dest]
  chan copy $in $out -size $dec -command [list ::moderne::gaby::partiesCopie $in $out $dec $dest]
}

proc ::moderne::gaby::partiesCopie {in out dec dest n {err {}}} {
  variable grand
  catch {close $in}
  set code [catch {close $out} err2]
  unset -nocomplain grand(copie)
  if {[info exists grand(annule)]} { return }
  if {$err ne {} || $code || $n != $dec} {
    echecGrande [T "Gaby : extraction impossible (disque plein ?), l'ancienne base est gardée" \
        "Gaby: unzipping failed (disk full?), the old database is kept"] "$err $err2"
    return
  }
  incr grand(fait) $dec
  after idle [list ::moderne::gaby::partiesEntree $dest]
}

### One file unzipped: the zip deleted (room on the disk), the next one
proc ::moderne::gaby::partiesExtrait {} {
  variable grand
  catch {file delete -force $grand(zip)}
  after idle ::moderne::gaby::partiesSuivant
}

### A file of the unzipped parts by its name ({} when missing)
proc ::moderne::gaby::partiesTrouver {nom} {
  variable grand
  foreach f [partiesFichiers [file join $grand(dossierNouveau) parties]] {
    if {[string equal -nocase [file tail $f] [file tail $nom]]} { return $f }
  }
  return {}
}

### The merges, one database after the other
proc ::moderne::gaby::partiesFusion {} {
  variable grand
  variable manifeste
  variable basesParties
  set grand(aFusionner) {}
  set bases [::moderne::json::get $manifeste fusion bases {}]
  foreach {cle cible} $basesParties {
    # (a manifest without fusion.bases: the main database alone)
    if {$bases eq {} && $cle ne "principale"} { continue }
    if {$bases ne {} && [::moderne::json::get $bases $cle {}] eq {}} { continue }
    lappend grand(aFusionner) $cle $cible
  }
  partiesFusionSuivante
}

### The parts of database cle: {ordFile si4Root ...} of the parts with games
proc ::moderne::gaby::partiesSources {cle} {
  variable manifeste
  set r {}
  foreach p [::moderne::json::get $manifeste parties {}] {
    set nom [::moderne::json::get $p nom partie]
    set entree {}
    foreach b [::moderne::json::get $p bases {}] {
      if {[::moderne::json::get $b base {}] eq $cle} { set entree $b }
    }
    # (a manifest without bases: the part's main database and .ord)
    if {$entree eq {}} {
      if {$cle ne "principale"} { continue }
      set n [::moderne::json::get $p parties 0]
      set si4 "gaby_$nom.si4"
      set ord [::moderne::json::get $p ord fichier "gaby_$nom.ord"]
    } else {
      set n [::moderne::json::get $entree parties 0]
      set si4 [::moderne::json::get $entree si4 {}]
      set ord [::moderne::json::get $entree ord fichier {}]
      if {$si4 eq {}} { set si4 "[file rootname $ord].si4" }
    }
    if {$n == 0} { continue }
    set fs [partiesTrouver $si4]
    set fo [partiesTrouver $ord]
    if {$fs eq {} || $fo eq {}} { error "[T "partie incomplète" "incomplete part"] $nom ($cle): $si4 $ord" }
    lappend r $fo [file rootname $fs]
  }
  return $r
}

proc ::moderne::gaby::partiesFusionSuivante {} {
  variable grand
  if {[info exists grand(annule)]} { return }
  if {![llength $grand(aFusionner)]} { partiesBibliotheques ; return }
  lassign $grand(aFusionner) cle cible
  set grand(aFusionner) [lrange $grand(aFusionner) 2 end]
  set grand(fusionCle) $cle
  set grand(ouvertes) {}
  if {[catch {
    set sources [partiesSources $cle]
    set liste {}
    foreach {ord racine} $sources {
      set b [sc_base open $racine]
      lappend grand(ouvertes) $b
      lappend liste $ord $b
    }
    set racine [file join $grand(dossierNouveau) $cible]
    catch {file delete -force {*}[glob -nocomplain $racine.s?4]}
    set d [sc_base create $racine]
    lappend grand(ouvertes) $d
    set grand(fusionBase) $d
    set grand(fusionTotal) [expr {[llength $liste] ? [sc_base fusion debut $d $liste] : 0}]
  } err]} {
    partiesFermer
    echecGrande [T "Gaby : réunion des deux parties impossible, l'ancienne base est gardée" \
        "Gaby: merging the two parts failed, the old database is kept"] $err
    return
  }
  partiesFusionEtape
}

### (failure, cancel: the merged main database too, and the order file)
proc ::moderne::gaby::partiesFermerTout {} {
  variable grand
  partiesFermer
  if {[info exists grand(principale)]} { catch {sc_base close $grand(principale)} ; unset grand(principale) }
  if {[info exists grand(idsCanal)]} { catch {close $grand(idsCanal)} }
}

proc ::moderne::gaby::partiesFermer {} {
  variable grand
  catch {sc_base fusion annuler}
  if {[info exists grand(ouvertes)]} {
    foreach b $grand(ouvertes) { catch {sc_base close $b} }
  }
  set grand(ouvertes) {}
}

### 20,000 games at a time (about a quarter of a second)
proc ::moderne::gaby::partiesFusionEtape {} {
  variable grand
  if {[info exists grand(annule)]} { partiesFermer ; return }
  if {[catch {
    set n [expr {$grand(fusionTotal) ? [sc_base fusion etape 20000] : 0}]
  } err]} {
    partiesFermer
    echecGrande [T "Gaby : réunion des deux parties impossible, l'ancienne base est gardée" \
        "Gaby: merging the two parts failed, the old database is kept"] $err
    return
  }
  if {$n < $grand(fusionTotal)} {
    set pct [expr {int(100.0 * $n / $grand(fusionTotal))}]
    progres "Gaby[T " : " ": "][T "réunion des deux parties" "merging the two parts"] ([partiesNomBase $grand(fusionCle)]) $pct %" $pct
    after 1 ::moderne::gaby::partiesFusionEtape
    return
  }
  if {[catch {
    if {$grand(fusionTotal)} { sc_base fusion fin }
  } err]} {
    partiesFermer
    echecGrande [T "Gaby : réunion des deux parties impossible, l'ancienne base est gardée" \
        "Gaby: merging the two parts failed, the old database is kept"] $err
    return
  }
  # the GabyIds in order, 100,000 at a time, into a file for their SHA-256
  set grand(ids) [file join [dossierTemp] gaby_complete_ids.txt]
  set grand(idsCanal) [open $grand(ids) w]
  fconfigure $grand(idsCanal) -translation lf -encoding utf-8
  partiesIds 1
}

proc ::moderne::gaby::partiesNomBase {cle} {
  return [dict get [list principale Gaby en_ligne [T "en ligne" online] correspondance [T correspondance correspondence]] $cle]
}

proc ::moderne::gaby::partiesIds {i} {
  variable grand
  if {[info exists grand(annule)]} { catch {close $grand(idsCanal)} ; partiesFermer ; return }
  set d $grand(fusionBase)
  set n [sc_base numGames $d]
  if {$i <= $n} {
    set j [expr {min($n, $i + 99999)}]
    foreach r [sc_gaby tags $d $i $j GabyId] { puts $grand(idsCanal) [lindex $r 1] }
    progres "Gaby[T " : " ": "][T "vérification de l'ordre" "checking the order"] ([partiesNomBase $grand(fusionCle)]) [expr {int(100.0 * $j / $n)}] %" [expr {int(100.0 * $j / $n)}]
    after 1 [list ::moderne::gaby::partiesIds [expr {$j + 1}]]
    return
  }
  close $grand(idsCanal)
  partiesControle
}

### The merged database against the manifest: its number of games, then
### the SHA-256 of its GabyIds. The main database out of order: kept (its
### games are right) but the libraries are rebuilt here
proc ::moderne::gaby::partiesControle {} {
  variable grand
  variable manifeste
  set cle $grand(fusionCle)
  set fusion [::moderne::json::get $manifeste fusion {}]
  set attenduN [::moderne::json::get $fusion bases $cle parties {}]
  set attenduSha [string tolower [::moderne::json::get $fusion bases $cle sha256GabyIds {}]]
  if {$cle eq "principale"} {
    if {$attenduN eq {}} { set attenduN [::moderne::json::get $fusion parties {}] }
    if {$attenduSha eq {}} { set attenduSha [string tolower [::moderne::json::get $fusion sha256GabyIds {}]] }
  }
  set n [sc_base numGames $grand(fusionBase)]
  if {$attenduN ne {} && $n != $attenduN} {
    partiesFermer
    catch {file delete -force $grand(ids)}
    echecGrande [T "Gaby : réunion des deux parties incomplète, l'ancienne base est gardée" \
        "Gaby: merging the two parts is incomplete, the old database is kept"] "$cle: $n / $attenduN"
    return
  }
  set sha {}
  catch {set sha [sc_gaby sha256 $grand(ids)]}
  catch {file delete -force $grand(ids)}
  set ok [expr {$attenduSha eq {} || $sha eq $attenduSha}]
  catch {::moderne::journal "Siby Gaby: $cle merged, $n games, GabyIds [expr {$ok ? "in order" : "OUT OF ORDER ($sha, expected $attenduSha)"}]"}
  if {$cle eq "principale"} {
    set grand(ordreOk) $ok
    # (the main database stays open for its libraries)
    set grand(principale) $grand(fusionBase)
    set k [lsearch -exact $grand(ouvertes) $grand(fusionBase)]
    set grand(ouvertes) [lreplace $grand(ouvertes) $k $k]
  }
  partiesFermer
  after idle ::moderne::gaby::partiesFusionSuivante
}

### ".online.sbl", ".sbl", ".sbp", ".sbc", ".maj.json" for a library file
### of Gaby, {} otherwise
proc ::moderne::gaby::partiesExtBiblio {nom} {
  set t [string tolower $nom]
  foreach ext {.classical.online.sbl .rapid.online.sbl .blitz.online.sbl .classical.sbl .rapid.sbl .blitz.sbl
               .online.sbl .sbl .sbp .sbc .maj.json} {
    if {[string match "*$ext" $t]} { return $ext }
  }
  return {}
}

### The libraries next to the merged main database, their fingerprints
### written for it; without them (or out of order): rebuilt after the
### install (nsb::verifier)
proc ::moderne::gaby::partiesBibliotheques {} {
  variable grand
  set dest [file join $grand(dossierNouveau) bibliotheques]
  set ok [expr {[info exists grand(ordreOk)] && $grand(ordreOk)}]
  if {$ok && [file isdirectory $dest]} {
    foreach f [partiesFichiers $dest] {
      set ext [partiesExtBiblio [file tail $f]]
      if {$ext ne {}} { catch {file rename -force $f [file join $grand(dossierNouveau) gaby$ext]} }
    }
    if {[info exists grand(principale)]} {
      if {[catch {sc_nsb tamponner $grand(principale)} err]} {
        catch {::moderne::journal "Siby Gaby: libraries not re-stamped ($err): rebuilt"}
        foreach ext {.sbl .online.sbl .classical.sbl .classical.online.sbl .rapid.sbl .rapid.online.sbl .blitz.sbl .blitz.online.sbl .sbp} { catch {file delete -force [file join $grand(dossierNouveau) gaby$ext]} }
      } else {
        catch {::moderne::journal "Siby Gaby: libraries re-stamped: $err"}
      }
    }
  }
  # (.sbc is by player name: kept even out of order)
  if {!$ok && [file isdirectory $dest]} {
    foreach f [partiesFichiers $dest] {
      if {[string match -nocase *.sbc [file tail $f]]} { catch {file rename -force $f [file join $grand(dossierNouveau) gaby.sbc]} }
    }
  }
  if {[info exists grand(principale)]} { catch {sc_base close $grand(principale)} ; unset grand(principale) }
  catch {file delete -force [file join $grand(dossierNouveau) parties] $dest}
  # (the libraries of the old Gaby must not be kept by mistake)
  grandeRemplacer
}

### ------------------------------------------------------------------------
### Settings and menu
### ------------------------------------------------------------------------

proc ::moderne::gaby::reglages {} {
  variable form
  set w .gabyReglages
  if {[winfo exists $w]} { raise $w ; return }
  trouverFichier
  foreach k {autoMaj url fichier grande} { set form($k) [set ::moderne::gaby::$k] }
  if {[string trim $form(url)] eq {}} { set form(url) $::moderne::gaby::urlDefaut }
  ::moderne::jouer::polices
  set fond [::moderne::c fond]
  toplevel $w -background $fond
  wm title $w Gaby
  wm transient $w .
  wm resizable $w 0 0
  set f [frame $w.f -background $fond -padx 22 -pady 16]
  pack $f -fill both -expand 1
  # header: logo, name, what it is
  frame $f.tete -background $fond
  pack $f.tete -side top -fill x
  if {![catch {::moderne::logos::image gaby 48} logo] && $logo ne {}} {
    label $f.tete.logo -image $logo -background $fond
    pack $f.tete.logo -side left -padx {0 12}
  }
  label $f.tete.t -text Gaby -font SibyJouerTitre -background $fond -foreground [::moderne::c texteFort] -anchor w
  label $f.tete.s -text [T "Games Archive By Yosha : la base de référence, à jour chaque jour" \
      "Games Archive By Yosha: the reference database, updated every day"] -font SibyJouerPetit \
      -background $fond -foreground [::moderne::c texteDoux] -anchor w
  pack $f.tete.t $f.tete.s -side top -anchor w
  catch {::utils::tooltip::Set $f.tete.s [T \
      "Gaby reçoit chaque jour de petits fichiers de nouvelles parties : Siby les ajoute à la fin de ta copie, en arrière-plan. La grosse mise à jour retélécharge Gaby complète (corrections, doublons retirés) et remplace l'ancienne." \
      "Gaby gets small files of new games every day: Siby appends them to your copy, in the background. The big update downloads the complete Gaby again (corrections, duplicates removed) and replaces the old one."]}

  # Status card
  set e [lireEtat]
  set v [dict get $e base_version]
  set c [frame $f.etatc -background [::moderne::c surface] -highlightthickness 1 \
      -highlightbackground [::moderne::c bordure] -padx 12 -pady 9]
  pack $c -side top -fill x -pady {14 0}
  set t [texteEtat 1]
  if {$t eq {}} {
    set t [T "Pas encore de Gaby sur cet ordinateur : télécharge-la (Télécharger Gaby) ou choisis son fichier ci-dessous." \
        "No Gaby on this computer yet: download it (Download Gaby) or choose its file below."]
  }
  label $f.etat -text $t -background [::moderne::c surface] -foreground [::moderne::c texteFort] \
      -anchor w -justify left -wraplength 540
  pack $f.etat -in $c -side top -anchor w
  if {$v ne {}} {
    label $c.v -text "[T "Base complète du" "Complete database of"] [dateAffichee $v]" -font SibyJouerPetit \
        -background [::moderne::c surface] -foreground [::moderne::c texteDoux] -anchor w
    pack $c.v -side top -anchor w
  }

  # Updates
  ::moderne::jouer::section $f.lpetites [T "Nouvelles parties du jour" "New games of the day"]
  ::moderne::jouer::segments $f.a ::moderne::gaby::form(autoMaj) [list \
      [list 1 [T "Automatiques" "Automatic"] [T "Au démarrage, puis toutes les 4 heures" "At startup, then every 4 hours"]] \
      [list 0 [T "Sur demande" "On request"]]]
  pack $f.a -side top -fill x
  ::moderne::jouer::section $f.lgrande [T "Grosse mise à jour (Gaby complète, environ 2,3 Go à télécharger)" "Big update (complete Gaby, about 2.3 GB to download)"]
  ::moderne::jouer::segments $f.g ::moderne::gaby::form(grande) [list \
      [list demande [T "Sur demande" "On request"]] [list semaine [T "Chaque semaine" "Every week"]] \
      [list mois [T "Chaque mois" "Every month"]]]
  pack $f.g -side top -fill x

  # File and address (rarely changed)
  ::moderne::jouer::section $f.lfich [T "Fichier de Gaby" "Gaby file"]
  frame $f.fich -background $fond
  pack $f.fich -side top -fill x
  ttk::entry $f.b -width 46 -textvariable ::moderne::gaby::form(fichier)
  ttk::button $f.bb -text [T "Choisir…" "Browse…"] -style Toolbutton -command {
    set f [tk_getOpenFile -parent .gabyReglages -filetypes {{{Siby} {.si4}}}]
    if {$f ne {}} { set ::moderne::gaby::form(fichier) $f }
  }
  pack $f.b -in $f.fich -side left -fill x -expand 1
  pack $f.bb -in $f.fich -side left -padx {6 0}
  ::moderne::jouer::section $f.lurl [T "Adresse de mise à jour" "Update address"]
  ttk::entry $f.u -width 46 -textvariable ::moderne::gaby::form(url)
  pack $f.u -side top -fill x

  set garder {foreach k {autoMaj url fichier grande} { set ::moderne::gaby::$k $::moderne::gaby::form($k) } ; destroy .gabyReglages}
  frame $f.btn -background $fond
  pack $f.btn -side top -fill x -pady {18 0}
  ttk::button $f.btn.maj -text [T "Mettre à jour maintenant" "Update now"] -style Toolbutton -command "$garder ; ::moderne::gaby::verifier 1"
  ttk::button $f.btn.grande -text [libelleComplet] -style Toolbutton \
      -command "$garder ; ::moderne::gaby::grandeMaj 1"
  ttk::button $f.btn.ok -text OK -command "$garder ; catch updateStatusBar"
  catch {$f.btn.ok configure -style Accent.TButton}
  ttk::button $f.btn.annuler -text [T "Annuler" "Cancel"] -command [list destroy $w]
  pack $f.btn.maj $f.btn.grande -side left -padx {0 6}
  pack $f.btn.ok $f.btn.annuler -side right -padx 3
  bind $w <Escape> [list destroy $w]
  catch {placeWinOverParent $w .}
}

### End of Siby
