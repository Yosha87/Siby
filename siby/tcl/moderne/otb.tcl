###
### Siby: online games of Gaby ("Over the board only" / "Include online
### tournaments")
###
### Gaby also holds the official online tournaments (Champions Chess Tour,
### Pro Chess League, Online Olympiad...). An online game has the
### custom flag 5, named "En ligne" (or "Online") in the database, and the
### PGN header [Online "1"]; the time-control flags stay (1 classical,
### 2 rapid, 3 blitz, 4 correspondence).
###
### Global setting (Search menu, shown in the status bar):
###   - over the board only: the games with flag 5 are left out
###     when the database is opened, after every search (header, board,
###     material, moves, partial position: the filter is restricted with
###     "sc_search header -fCustom5 no -filter AND"), after a filter
###     reset or negation, and in the opening library / tree
###     (sc_tree search -noflag 5; the instant library has the online games
###     apart, see nsb.h);
###   - include online tournaments (default since 2026-10-31): nothing is left out; the online games
###     are shown in another colour in the game list.
### Only databases whose flag 5 is named "En ligne" / "Online" are
### concerned: the user's other databases are never touched.
### A header search asking for flag 5 (Gaby's "Gaby 5 - Online" search)
### in "over the board" mode offers to switch.
###

namespace eval ::moderne::otb {
  variable inclure
  # (default since 2026-10-31: what Gaby holds is shown, its online
  # tournaments included (Champions Chess Tour...); set once for everyone, the
  # Search menu still changes it. Players' own online games come only from
  # their downloaded accounts.)
  variable defautEnLigne
  if {![info exists defautEnLigne] || $defautEnLigne < 2} {
    set inclure 1
    set defautEnLigne 2
  }
  if {![info exists inclure]} { set inclure 1 }
  variable concernees     ;# concernees(file): flag 5 named "En ligne"?
  array set concernees {}
  variable dansFiltre 0   ;# (re-entrance)
}

proc ::moderne::otb::T {fr en} { return [::moderne::tr $fr $en] }

### Is database b (default: current) concerned (flag 5 = "En ligne")?
proc ::moderne::otb::concernee {{b {}}} {
  variable concernees
  if {$b eq {}} { set b [sc_base current] }
  if {![sc_base inUse $b] || $b == [sc_info clipbase]} { return 0 }
  set f [sc_base filename $b]
  if {[info exists concernees($f)]} { return $concernees($f) }
  set courante [sc_base current]
  if {$courante != $b} { sc_base switch $b }
  set d {}
  catch {set d [string tolower [string trim [sc_game flag 5 description]]]}
  if {$courante != $b} { sc_base switch $courante }
  set concernees($f) [expr {$d in {"en ligne" online}}]
  return $concernees($f)
}

### Forgets what is known of database b (opened again, closed)
proc ::moderne::otb::oublier {{b {}}} {
  variable concernees
  if {$b eq {} || ![string is integer -strict $b]} { set b [sc_base current] }
  catch {unset concernees([sc_base_otb filename $b])}
}

### Leave the online games out of database b?
proc ::moderne::otb::exclure {{b {}}} {
  variable inclure
  expr {!$inclure && [concernee $b]}
}

### Restricts the filter of database b to the games over the board
proc ::moderne::otb::filtrer {{b {}}} {
  variable dansFiltre
  if {$dansFiltre} { return }
  if {$b eq {}} { set b [sc_base current] }
  if {![exclure $b]} { return }
  set dansFiltre 1
  set courante [sc_base current]
  if {$courante != $b} { sc_base switch $b }
  catch {sc_search_otb header -fCustom5 no -filter 0}
  if {$courante != $b} { sc_base switch $courante }
  set dansFiltre 0
}

### Game g of the current database: online game?
proc ::moderne::otb::enLigne {g} {
  if {![concernee]} { return 0 }
  expr {![catch {sc_game flag 5 [string trim $g]} v] && $v eq "1"}
}

### Status bar text (only for a concerned database): "OTB only" or
### "OTB + online" in both languages, full name on hover
proc ::moderne::otb::texteEtat {} {
  variable inclure
  if {![concernee]} {
    catch {::utils::tooltip::Set .main.statusbar {}}
    return {}
  }
  catch {::utils::tooltip::Set .main.statusbar [expr {$inclure \
      ? [T "Parties sur l'échiquier (OTB) et tournois online (case « Tournois en ligne » de la fenêtre Rechercher ou de la bibliothèque)" \
           "Over-the-board (OTB) games and online tournaments (\"Online tournaments\" box of the Search window or the library)"] \
      : [T "Parties sur l'échiquier seulement (OTB, over the board) ; tournois online exclus (case « Tournois en ligne » de la fenêtre Rechercher ou de la bibliothèque)" \
           "Over-the-board games only (OTB); online tournaments left out (\"Online tournaments\" box of the Search window or the library)"]}]}
  return [expr {$inclure ? "   • OTB + online" : "   • OTB only"}]
}

### Menu: setting changed
proc ::moderne::otb::basculer {} {
  variable inclure
  for {set b 1} {$b <= [sc_base count total]} {incr b} {
    if {![sc_base inUse $b] || ![concernee $b]} { continue }
    if {$inclure} {
      # nothing left out any more: the whole database
      catch {sc_filter_otb reset $b}
    } else {
      filtrer $b
    }
  }
  # the opening library caches are computed with or without online games
  catch {set ::moderne::biblio::cache [dict create]}
  catch {::moderne::biblio::maj}
  for {set b 1} {$b <= [sc_base count total]} {incr b} {
    if {[winfo exists .treeWin$b]} { catch {::tree::refresh $b} }
  }
  catch {::windows::gamelist::Refresh}
  catch {::windows::stats::Refresh}
  catch {updateStatusBar}
}

### "Over the board only" while a search asks for the online games (flag
### 5 = yes): offer to include them
proc ::moderne::otb::proposer {} {
  variable inclure
  set r [tk_messageBox -type yesno -icon question -title Siby -message [T \
      "Cette recherche porte sur les parties online, mais le réglage est « OTB only » (sur l'échiquier seulement).\n\nInclure les tournois online ?" \
      "This search is about online games, but the setting is \"OTB only\" (over the board only).\n\nInclude online tournaments?"]]
  if {$r eq "yes"} {
    set inclure 1
    basculer
    return 1
  }
  return 0
}

################################################################################
### Wrapped commands
################################################################################

proc ::moderne::otb::installer {} {
  if {[llength [info commands ::sc_search_otb]]} { return }
  rename ::sc_search ::sc_search_otb
  proc ::sc_search {args} {
    if {[lindex $args 0] eq "header" && [::moderne::otb::exclure]} {
      set i [lsearch -exact $args -fCustom5]
      if {$i > 0 && [lindex $args [expr {$i + 1}]] eq "yes"} { ::moderne::otb::proposer }
    }
    set code [catch {::sc_search_otb {*}$args} res opts]
    if {!$code} {
      # (board search in another database: sc_search board op type vars flip base)
      set b {}
      if {[lindex $args 0] eq "board" && [llength $args] >= 6} { set b [lindex $args 5] }
      ::moderne::otb::filtrer $b
    }
    return -options $opts $res
  }
  rename ::sc_filter ::sc_filter_otb
  proc ::sc_filter {args} {
    set code [catch {::sc_filter_otb {*}$args} res opts]
    if {!$code && [lindex $args 0] in {reset negate}} {
      set b [lindex $args 1]
      ::moderne::otb::filtrer [expr {[string is integer -strict $b] ? $b : {}}]
    }
    return -options $opts $res
  }
  rename ::sc_tree ::sc_tree_otb
  proc ::sc_tree {args} {
    if {[lindex $args 0] eq "search" && [lsearch -exact $args -noflag] < 0} {
      set i [lsearch -exact $args -base]
      set b [expr {$i > 0 ? [lindex $args [expr {$i + 1}]] : {}}]
      if {[::moderne::otb::exclure $b]} { lappend args -noflag 5 }
    }
    return [uplevel 1 [list ::sc_tree_otb {*}$args]]
  }
  rename ::sc_base ::sc_base_otb
  proc ::sc_base {args} {
    set fermee {}
    if {[lindex $args 0] eq "close"} {
      catch {::moderne::otb::oublier [lindex $args 1]}
      catch {set fermee [::sc_base_otb filename {*}[lrange $args 1 1]]}
    }
    set code [catch {::sc_base_otb {*}$args} res opts]
    if {!$code && [lindex $args 0] eq "open" && [string is integer -strict $res]} {
      catch {::moderne::otb::oublier $res}
      catch {::moderne::otb::filtrer $res}
      # (Siby: cut off while written last time: a check offered)
      catch {::moderne::integrite::ouverte $res}
    }
    if {!$code && $fermee ne {}} { catch {::moderne::integrite::fermee $fermee} }
    return -options $opts $res
  }
}

::moderne::otb::installer

### End Siby
