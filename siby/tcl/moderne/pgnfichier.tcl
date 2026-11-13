
###
### Siby: save directly to a PGN file
###
### SCID opens a PGN file as a read-only in-memory database.
### Here the database can be modified; after each game is saved
### (sc_game save), the whole PGN file is rewritten with its games:
###   - writing goes to a temporary file, which replaces the original
###     only once complete (on error, the original stays intact); no .bak
###     copy since 2026-11-02.
### Moves, variations, comments, symbols and arrows are kept (symbols as
### standard $n codes); the
### formatting (line length, header order) is Siby's own.
### The file is written in UTF-8 (with a BOM only if
### the original had one). .pgn.gz files stay
### read-only.
###

namespace eval ::moderne::pgnfichier {
  variable fichier   ;# fichier(b): PGN file of database b
  array set fichier {}
  variable bak       ;# bak(b): .bak copy already made
  array set bak {}
}

proc ::moderne::pgnfichier::T {fr en} { return [::moderne::tr $fr $en] }

### Called after a PGN file has been opened in database b
proc ::moderne::pgnfichier::ouvert {b f} {
  variable fichier
  variable bak
  if {![::moderne::actif]} { return }
  if {[string tolower [file extension $f]] ne ".pgn"} { return }
  if {![file writable $f]} { return }
  if {[catch {sc_base isReadOnly unset $b}]} { return }
  set fichier($b) [file normalize $f]
  set bak($b) 0
}

### Is database b still the PGN file it was opened from? A database slot is
### reused once closed: another database (e.g. "Siby live") opened there must
### never rewrite the PGN file of before (bug of 2026-11-01: "Semaine 90.pgn"
### rewritten with the broadcast's games). The link is forgotten otherwise.
proc ::moderne::pgnfichier::toujours {b} {
  variable fichier
  variable bak
  if {![info exists fichier($b)]} { return 0 }
  if {[sc_base inUse $b] && ![catch {sc_base filename $b} f] && [file normalize $f] eq $fichier($b)} {
    return 1
  }
  unset fichier($b)
  catch {unset bak($b)}
  return 0
}

### Database b closed: its PGN file forgotten
proc ::moderne::pgnfichier::ferme {b} {
  variable fichier
  variable bak
  catch {unset fichier($b)}
  catch {unset bak($b)}
}

### Siby closing normally: the PGN files forgotten
proc ::moderne::pgnfichier::nettoyer {} {
  variable fichier
  foreach b [array names fichier] { ferme $b }
}

### A game has just been saved in database b
proc ::moderne::pgnfichier::modifie {b} {
  variable fichier
  if {![toujours $b]} { return }
  after cancel [list ::moderne::pgnfichier::ecrire $b]
  after idle [list ::moderne::pgnfichier::ecrire $b]
}

### Rewrites the PGN file of database b with its games (quoi = all) or with
### the games of its filter (quoi = filter). Returns 1 if the file was written.
proc ::moderne::pgnfichier::ecrire {b {quoi all}} {
  variable fichier
  variable bak
  if {![toujours $b]} { return 0 }
  set f $fichier($b)
  # (no .bak copy any more, Yosha 2026-11-02: the file is written to a
  # temporary file first and then replaces the original in one go, so a
  # crash while writing leaves the original intact; as ChessBase)
  set tmp "$f.siby-tmp"
  # UTF-8 BOM (ChessBase writes one): only if the original had one
  set bom 0
  catch {
    set c [open $f rb] ; set debut [read $c 3] ; close $c
    set bom [expr {$debut eq "\xef\xbb\xbf"}]
  }
  set courante [sc_base current]
  busyCursor .
  if {$courante != $b} { sc_base switch $b }
  set code [catch {
    sc_base export $quoi PGN $tmp -append 0 -starttext "" -endtext "" -comments 1 -variations 1 \
        -spaces 0 -symbols 0 -indentComments 0 -indentVariations 0 -column 0 -noMarkCodes 0 \
        -convertNullMoves 1 -newlines 1 -utf8 1 -bom $bom
  } err]
  set n [expr {$quoi eq "all" ? [sc_base numGames $b] : [sc_filter count $b]}]
  if {$courante != $b} { sc_base switch $courante }
  unbusyCursor .
  if {!$code && ($n == 0 || ([file exists $tmp] && [file size $tmp] > 0))} {
    set code [catch {file rename -force $tmp $f} err]
  } elseif {!$code} {
    set code 1
    set err [T "fichier temporaire vide" "empty temporary file"]
  }
  if {$code} {
    catch {file delete $tmp}
    tk_messageBox -icon error -type ok -title Siby -message \
        "[T "Le fichier PGN n'a pas pu être réécrit (l'original est intact) :" "The PGN file could not be rewritten (the original is untouched):"]\n$err"
    return 0
  }
  set msg "[T "Enregistré dans" "Saved in"] [file tail $f]"
  catch {
    ::moderne::nsb::annonce $msg -1
    after 3500 {catch {destroy .annonceNsb}}
  }
  return 1
}

### Compacting a PGN file (SCID cannot compact an in-memory database): the
### file is rewritten without the games marked as deleted, then reopened
proc ::moderne::pgnfichier::compacter {b parent} {
  variable fichier
  # (sc_compact stats fails on an in-memory database: count with a search)
  set courante [sc_base current]
  sc_base switch $b
  sc_search header -fDelete yes -filter 2
  set n [sc_filter count]
  sc_filter reset
  if {$courante != $b} { sc_base switch $courante }
  if {$n <= 0} {
    tk_messageBox -type ok -icon info -parent $parent -title Siby -message $::tr(NoUnusedGames)
    return
  }
  if {$n == 1} {
    set msg [T "1 partie marquée supprimée sera retirée de [file tail $fichier($b)].\nContinuer ?" \
        "1 game marked as deleted will be removed from [file tail $fichier($b)].\nAre you sure?"]
  } else {
    set msg [T "$n parties marquées supprimées seront retirées de [file tail $fichier($b)].\nContinuer ?" \
        "$n games marked as deleted will be removed from [file tail $fichier($b)].\nAre you sure?"]
  }
  if {[tk_messageBox -type yesno -icon question -parent $parent -title Siby -message $msg] ne "yes"} {
    return
  }
  set f $fichier($b)
  sc_base switch $b
  sc_search header -fDelete no -filter 2
  set ok [ecrire $b filter]
  if {$courante != $b} { sc_base switch $courante }
  if {!$ok} { return }
  # reopen the rewritten file (its game numbers have changed)
  sc_base switch $b
  sc_game new
  ::file::Close $b
  ::file::Open $f
}

### The Compact button / menu on a PGN file
proc ::moderne::pgnfichier::installerCompacter {} {
  # (Tools > Compact the database on a PGN file: its rewriting straight
  # away; on a database that cannot be compacted (in memory, read-only, the
  # clipboard), a plain message: SCID's window asked its statistics and
  # Siby showed "Siby ran into a problem", Yosha 2026-11-06)
  if {![llength [info commands ::makeCompactWin_origine]] && [llength [info commands ::makeCompactWin]]} {
    rename ::makeCompactWin ::makeCompactWin_origine
    proc ::makeCompactWin {{parent .}} {
      set b [sc_base current]
      if {[info exists ::moderne::pgnfichier::fichier($b)] && [::moderne::pgnfichier::toujours $b]} {
        ::moderne::pgnfichier::compacter $b $parent
        return
      }
      if {![sc_base inUse] || $b == [sc_info clipbase] || [sc_base isReadOnly] || [catch {sc_compact stats games}]} {
        tk_messageBox -type ok -icon info -parent $parent -title Siby -message \
            [::moderne::tr "Cette base ne peut pas être nettoyée (lecture seule ou en mémoire)." \
                 "This database cannot be cleaned up (read-only or in memory)."]
        return
      }
      # (a database: one question, as for a PGN file; SCID's window offered
      # the name file and the game file apart, Yosha 2026-11-10)
      ::moderne::pgnfichier::compacterBase $b $parent
    }
  }
  if {[llength [info commands ::compactGames_origine]] || ![llength [info commands ::compactGames]]} { return }
  rename ::compactGames ::compactGames_origine
  proc ::compactGames {parent} {
    set b [sc_base current]
    if {[info exists ::moderne::pgnfichier::fichier($b)]} {
      ::moderne::pgnfichier::compacter $b $parent
    } else {
      ::moderne::pgnfichier::compacterBase $b $parent
    }
  }
}

### A database's games marked as deleted removed for good, and the names no
### game uses any more: one question. (The engines no longer need closing on
### Windows: Siby's files are not inherited by them, common.h)
proc ::moderne::pgnfichier::compacterBase {b parent} {
  if {![sc_base inUse] || $b == [sc_info clipbase] || [sc_base isReadOnly] || [catch {sc_compact stats games} stats]} {
    tk_messageBox -type ok -icon info -parent $parent -title Siby -message \
        [T "Cette base ne peut pas être nettoyée (lecture seule ou en mémoire)." \
             "This database cannot be cleaned up (read-only or in memory)."]
    return 0
  }
  set n [expr {[lindex $stats 0] - [lindex $stats 2]}]
  if {$n <= 0} {
    tk_messageBox -type ok -icon info -parent $parent -title Siby -message $::tr(NoUnusedGames)
    return 0
  }
  set nom [file tail [sc_base filename $b]]
  if {$n == 1} {
    set msg [T "1 partie marquée supprimée sera retirée de $nom.\nContinuer ?" \
        "1 game marked as deleted will be removed from $nom.\nAre you sure?"]
  } else {
    set msg [T "$n parties marquées supprimées seront retirées de $nom.\nContinuer ?" \
        "$n games marked as deleted will be removed from $nom.\nAre you sure?"]
  }
  if {[tk_messageBox -type yesno -icon question -parent $parent -title Siby -message $msg] ne "yes"} {
    return 0
  }
  set confirm [::game::ConfirmDiscard]
  if {$confirm == 2} { return 0 }
  if {$confirm == 0} { ::game::Save }
  catch {sc_compact stats games_setfilter}
  set ::glstart 1
  set avant [sc_base numGames $b]
  busyCursor .
  set err [catch {sc_compact games} result]
  # (the games really gone: an older Siby said "deleted" with the old files
  # kept, when they could not be replaced)
  if {!$err && [sc_base numGames $b] >= $avant} {
    set err 1
    set result [T "Les fichiers de la base n'ont pas pu être remplacés ; la base est inchangée." \
        "The database files could not be replaced; the database is unchanged."]
  }
  # (the names no game uses any more: deleted games' players, events…)
  if {!$err} { catch {sc_compact names} }
  unbusyCursor .
  if {$err} {
    tk_messageBox -type ok -icon warning -parent $parent -title Siby -message \
        "[T "La base n'a pas pu être nettoyée :" "The database could not be cleaned up:"]\n$result"
  } else {
    sc_game new
    updateBoard -pgn
    updateTitle
    updateMenuStates
    catch {::moderne::nsb::annonce [expr {$n == 1 ? [T "1 partie supprimée" "1 game deleted"] : [T "$n parties supprimées" "$n games deleted"]}] -1}
  }
  catch {::windows::gamelist::Refresh}
  catch {::windows::stats::Refresh}
  catch {::crosstab::Refresh}
  catch {::maint::Refresh}
  return [expr {!$err}]
}

### Every successful command that changes the games of the current
### database triggers a rewrite of the PGN: saving a game, compacting
### (deleted games), editing names, ECO classification, adding or removing
### tags, stripping comments or variations from all games
proc ::moderne::pgnfichier::installer {} {
  foreach {c condition} {
    sc_game    {[lindex $args 0] eq "save" || ([lindex $args 0] eq "strip" && [llength $args] >= 3)}
    sc_compact {[lindex $args 0] eq "games"}
    sc_name    {[lindex $args 0] eq "edit"}
    sc_eco     {[lindex $args 0] eq "base"}
    sc_base    {[lindex $args 0] eq "tag" && [lindex $args 1] in {add strip}}
  } {
    if {[llength [info commands ::${c}_origine]] || ![llength [info commands ::$c]]} { continue }
    rename ::$c ::${c}_origine
    proc ::$c {args} [string map [list %C $c %SI $condition] {
      set code [catch {::%C_origine {*}$args} res opts]
      if {!$code && (%SI)} {
        catch {::moderne::pgnfichier::modifie [sc_base current]}
      }
      return -options $opts $res
    }]
  }
}

::moderne::pgnfichier::installer
::moderne::pgnfichier::installerCompacter
after idle ::moderne::pgnfichier::installerCompacter

### End Siby
