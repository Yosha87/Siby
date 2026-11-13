
###
### Siby: quick time-control selector (5 buttons)
###
### All • Blitz • Rapid • Slow (classical) • Correspondence, as icons,
### for the game list, the opening library, the preparation and the scan.
### The time control is read from the database's custom flags
### (1 classical, 2 rapid, 3 blitz, 4 correspondence), as in
### Gaby (the large reference database).
###

namespace eval ::moderne::cadence {
  variable liste {}        ;# time control chosen in the game list
}

proc ::moderne::cadence::T {fr en} { return [::moderne::tr $fr $en] }

### Flag number of a time control ({} → 0 = all)
proc ::moderne::cadence::numero {cad} {
  return [dict get {{} 0 classique 1 rapide 2 blitz 3 correspondance 4} $cad]
}

### Bar of 5 buttons in frame f (created), bound to variable var;
### command called on each choice
proc ::moderne::cadence::barre {f var commande {baseCmd {}}} {
  variable bases
  ttk::frame $f
  set bases($f) [list $baseCmd $var]
  set style Toolbutton
  if {![catch {ttk::style layout Segment.Toolbutton} l] && $l ne {}} {
    set style Segment.Toolbutton
  }
  foreach {val img fr en} {
    {}             cad_toutes "Toutes les cadences"       "All time controls"
    blitz          cad_blitz  "Blitz"                     "Blitz"
    rapide         cad_rapide "Rapide"                    "Rapid"
    classique      cad_lente  "Lente (classique)"         "Classical"
    correspondance cad_corr   "Correspondance"            "Correspondence"
  } {
    set b $f.c[expr {$val eq {} ? "toutes" : $val}]
    if {[lsearch -exact [image names] $img] >= 0} {
      ttk::radiobutton $b -image $img -style $style -variable $var -value $val -command $commande
    } else {
      ttk::radiobutton $b -text [T $fr $en] -style $style -variable $var -value $val -command $commande
    }
    ::utils::tooltip::Set $b [T $fr $en]
    set ::moderne::cadence::bulle($b) [T $fr $en]
    pack $b -side left -padx 1
  }
  # Time controls without any game in the database: greyed out (looked at
  # again when the mouse comes over the bar)
  if {$baseCmd ne {}} {
    bind $f <Enter> [list ::moderne::cadence::griser $f]
    after idle [list ::moderne::cadence::griser $f]
  }
  return $f
}

### Greys out the time controls with no game in the bar's database (as
### correspondence in Gaby since 2026-10-29b); nothing greyed out in a
### database without time-control flags (a message explains it)
proc ::moderne::cadence::griser {f} {
  variable bases
  if {![winfo exists $f] || ![info exists bases($f)]} { return }
  lassign $bases($f) baseCmd var
  set b {}
  catch {set b [uplevel #0 $baseCmd]}
  if {![string is integer -strict $b] || $b < 1 || ![sc_base inUse $b]} { return }
  set n {}
  set total 0
  foreach {val k} {blitz 3 rapide 2 classique 1 correspondance 4} {
    set c 0
    catch {set c [sc_base stats flag:$k $b]}
    dict set n $val $c
    incr total $c
  }
  dict for {val c} $n {
    set vide [expr {$total > 0 && $c == 0}]
    catch {$f.c$val state [expr {$vide ? "disabled" : "!disabled"}]}
    catch {::utils::tooltip::Set $f.c$val [expr {$vide \
        ? [T "Aucune partie de cette cadence dans cette base" "No game with this time control in this database"] \
        : $::moderne::cadence::bulle($f.c$val)}]}
    # (the time control chosen has no game any more: all of them)
    if {$vide && [set $var] eq $val} { set $var {} }
  }
}

################################################################################
### Game list
################################################################################

proc ::moderne::cadence::installerListe {} {
  set w .glistWin
  if {![winfo exists $w.b] || [winfo exists $w.b.cadence]} { return }
  barre $w.b.cadence ::moderne::cadence::liste ::moderne::cadence::appliquerListe {sc_base current}
  pack $w.b.cadence -side left -padx 8 -after [expr {[winfo exists $w.b.chercher] ? "$w.b.chercher" : "$w.b.goto"}]
}

proc ::moderne::cadence::appliquerListe {} {
  variable liste
  set r [sc_filter cadence [numero $liste]]
  if {$r < 0} {
    set liste {}
    tk_messageBox -parent .glistWin -icon info -type ok -title Siby -message [T \
        "Les parties de cette base n'ont pas de drapeau de cadence (1 classique, 2 rapide, 3 blitz, 4 correspondance)." \
        "The games of this database have no time-control flag (1 classical, 2 rapid, 3 blitz, 4 correspondence)."]
  }
  catch {::windows::gamelist::Refresh}
  catch {::windows::stats::Refresh}
  catch {updateStatusBar}
}

### End Siby
