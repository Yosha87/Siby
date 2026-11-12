###
### Siby: "Lab" view, its right side in two big tabs
###
### "Prepare against a player" and "Analysis" (opening library,
### tablebases, notation, game list, my databases). Both pages are built
### once with the layout and kept: a click only shows one and hides the
### other (instant, each page keeps its state).
###
### In the layout tree (::docking::layout_save format) the block is
###   TOnglets {name page titles} pageData0 pageData1
### where each pageData is a paned window (layout_save_pw format) whose
### name is a child of the block (name.p0, name.p1). The block is a
### ttk::frame of class SibyLab: a tab bar, then the shown page.
###

namespace eval ::moderne::lab {
  variable pages    ;# block -> page paned windows
  variable titres   ;# block -> page names (prepa, analyse)
  variable actif    ;# block -> shown page (index)
  variable sashes {}  ;# sash positions of the last layout (pages hidden then)
  variable dejaVue  ;# page -> sashes already put back
  variable enAttente ;# page -> windows made at its first display {nb placeholder script}
}

### Windows of a hidden page made later: their opening command and name
proc ::moderne::lab::fabrique {d} {
  switch -- $d {
    .fdockprepaWin      { return [list ::moderne::prepa::ouvrir [libelle prepa]] }
    .fdockbiblioWin     { return [list ::moderne::biblio::ouvrir [T "Bibliothèque d'ouvertures" "Opening library"]] }
    .fdocktbWin         { return [list ::tb::Open [T "Tables de finales" "Tablebase"]] }
    .fdockpgnWin        { return [list ::pgn::Open [T "Notation" "Notation"]] }
    .fdockglistWin      { return [list ::windows::gamelist::Open [T "Parties" "Games"]] }
    .fdockbasesListeWin { return [list ::moderne::basesliste::ouvrir [T "Mes bases" "My databases"]] }
  }
  return {}
}

### Layout being built: window d of notebook nb, in a hidden page, gets a
### placeholder tab; it is made when the page is first shown. 0 if not
### (visible page, or a window that is not made lazily)
proc ::moderne::lab::placeAttente {nb d} {
  variable enAttente
  if {![cache $nb] || [winfo exists $d]} { return 0 }
  set f [fabrique $d]
  if {$f eq {}} { return 0 }
  lassign $f script nom
  if {[info exists ::docking::titres($d)]} { set nom $::docking::titres($d) }
  set p .fdockattente[string range $d 6 end]
  catch {destroy $p}
  frame $p -background [::moderne::c fond]
  label $p.l -text "$nom…" -background [::moderne::c fond] -foreground [::moderne::c texteDoux]
  place $p.l -relx 0.5 -rely 0.4 -anchor center
  $nb add $p -text $nom
  lassign [ou $nb] lab i
  lappend enAttente([lindex [pages $lab] $i]) [list $nb $p $script]
  return 1
}

### The windows waiting for page p's first display, made now
proc ::moderne::lab::fabriquerPage {p} {
  variable enAttente
  if {![info exists enAttente($p)]} { return }
  set l $enAttente($p)
  unset enAttente($p)
  foreach x $l {
    lassign $x nb ph script
    if {![winfo exists $ph]} { continue }
    catch {::docking::fenetreDifferee $nb $ph $script}
  }
  catch {::docking::setTabStatus}
}

proc ::moderne::lab::T {fr en} { return [::moderne::tr $fr $en] }

proc ::moderne::lab::libelle {nom} {
  switch -- $nom {
    prepa   { return [T "Se préparer contre un adversaire" "Prepare against a player"] }
    analyse { return [T "Analyse" "Analysis"] }
  }
  return $nom
}

proc ::moderne::lab::style {} {
  set police [list [font actual font_Regular -family] 12 bold]
  catch {
    ttk::style configure Lab.Toolbutton -font $police -padding {16 6} -foreground [::moderne::c texteDoux]
    # the shown page: lighter background, strong text
    ttk::style map Lab.Toolbutton \
        -background [list selected [::moderne::c surface] active [::moderne::c survol]] \
        -foreground [list selected [::moderne::c texteFort] active [::moderne::c texte]]
  }
  # (a notebook with no tab: its single tab is said by the page's tab)
  catch {ttk::style layout Sans.TNotebook.Tab {null -sticky nswe}}
}

### Block lab (in the paned window parent) with pages named in titres
proc ::moderne::lab::creer {lab titresPages} {
  variable pages
  variable titres
  variable actif
  style
  if {[winfo exists $lab]} { destroy $lab }
  ttk::frame $lab -class SibyLab
  set pages($lab) {}
  set titres($lab) $titresPages
  set actif($lab) 0
  set b [ttk::frame $lab.barre -padding {6 4 6 0}]
  grid $b -row 0 -column 0 -sticky ew
  # (a thin accent line under the shown page's tab)
  frame $b.trait -height 3 -background [::moderne::c accent] -borderwidth 0 -highlightthickness 0
  set i 0
  foreach t $titresPages {
    ttk::radiobutton $b.o$i -text [libelle $t] -style Lab.Toolbutton \
        -variable ::moderne::lab::actif($lab) -value $i -command [list ::moderne::lab::montrer $lab $i]
    pack $b.o$i -side left -padx {0 4}
    incr i
  }
  grid rowconfigure $lab 1 -weight 1
  grid columnconfigure $lab 0 -weight 1
  bind $lab <Destroy> [list ::moderne::lab::oublier %W $lab]
  return $lab
}

proc ::moderne::lab::oublier {w lab} {
  if {$w ne $lab} { return }
  variable pages
  variable titres
  variable actif
  variable enAttente
  catch {foreach p $pages($lab) { catch {unset enAttente($p)} }}
  catch {unset pages($lab)}
  catch {unset titres($lab)}
}

### Page pw (a paned window, child of the block) added
proc ::moderne::lab::ajouterPage {lab pw} {
  variable pages
  variable actif
  lappend pages($lab) $pw
  grid $pw -in $lab -row 1 -column 0 -sticky nsew
  if {[llength $pages($lab)] - 1 != $actif($lab)} { grid remove $pw }
}

proc ::moderne::lab::pages {lab} {
  variable pages
  return [expr {[info exists pages($lab)] ? $pages($lab) : {}}]
}
proc ::moderne::lab::titres {lab} {
  variable titres
  return [expr {[info exists titres($lab)] ? $titres($lab) : {}}]
}
proc ::moderne::lab::actif {lab} {
  variable actif
  return [expr {[info exists actif($lab)] ? $actif($lab) : 0}]
}

### Page i shown (index or name), the other hidden
proc ::moderne::lab::montrer {lab i} {
  variable pages
  variable titres
  variable actif
  variable dejaVue
  if {![winfo exists $lab] || ![info exists pages($lab)]} { return }
  if {![string is integer -strict $i]} { set i [lsearch -exact $titres($lab) $i] }
  if {$i < 0 || $i >= [llength $pages($lab)]} { return }
  set actif($lab) $i
  after idle [list ::moderne::lab::trait $lab]
  set k 0
  foreach p $pages($lab) {
    if {$k == $i} { grid $p } else { grid remove $p }
    incr k
  }
  set ::moderne::disposition::pageLab [lindex $titres($lab) $i]
  # (the notation lent to the preparation's Notation tab follows the page)
  after 60 {catch ::moderne::prepa::suivreNotation}
  # the sash positions of a page hidden when the layout was built
  set p [lindex $pages($lab) $i]
  # (its windows not made yet: made now, once shown)
  variable enAttente
  if {[info exists enAttente($p)]} { after idle [list ::moderne::lab::fabriquerPage $p] }
  if {![info exists dejaVue($p)]} {
    set dejaVue($p) 1
    after idle [list ::moderne::lab::remettreBarres $p]
  }
}

### The accent line under the tab of the shown page
proc ::moderne::lab::trait {lab} {
  set b $lab.barre
  if {![winfo exists $b.trait]} { return }
  set o $b.o[actif $lab]
  if {![winfo exists $o]} { return }
  update idletasks
  place $b.trait -in $o -relx 0.15 -relwidth 0.7 -rely 1.0 -anchor sw
  raise $b.trait
}

proc ::moderne::lab::remettreBarres {page} {
  variable sashes
  update idletasks
  foreach elt $sashes {
    lassign $elt pw pos
    if {![winfo exists $pw] || ([string first "$page." $pw] != 0 && $pw ne $page)} { continue }
    set i 0
    foreach s $pos {
      if {$i >= [llength [$pw panes]] - 1} { break }
      catch {$pw sashpos $i $s}
      incr i
    }
  }
}

### After a layout is built: its sash positions kept for the hidden pages
proc ::moderne::lab::apresRestauration {} {
  variable sashes
  variable dejaVue
  set sashes $::docking::sashpos
  array unset dejaVue
  foreach lab [blocs] {
    set p [lindex [pages $lab] [actif $lab]]
    if {$p ne {}} { set dejaVue($p) 1 }
  }
}

### The blocks that exist
proc ::moderne::lab::blocs {} {
  variable pages
  set l {}
  foreach lab [array names pages] { if {[winfo exists $lab]} { lappend l $lab } }
  return $l
}

### Block and page index holding widget w (a notebook or a dock window),
### empty if none
proc ::moderne::lab::ou {w} {
  variable pages
  if {![winfo exists $w]} { return {} }
  if {[string match .fdock* $w]} {
    set nb [::docking::find_tbn $w]
    if {$nb eq {} || ![info exists ::docking::tbs($nb)]} { return {} }
    set w $::docking::tbs($nb)
  } elseif {[info exists ::docking::tbs($w)]} {
    set w $::docking::tbs($w)
  }
  while {$w ne {} && $w ne "."} {
    set parent [winfo parent $w]
    if {[info exists pages($parent)]} {
      set i [lsearch -exact $pages($parent) $w]
      if {$i >= 0} { return [list $parent $i] }
    }
    set w $parent
  }
  return {}
}

### The page holding dock window f shown (a window raised or added there)
proc ::moderne::lab::montrerPour {f} {
  set r [ou $f]
  if {$r eq {}} { return }
  lassign $r lab i
  if {[actif $lab] != $i} { montrer $lab $i }
}

### Notebook nb in a hidden page?
proc ::moderne::lab::cache {nb} {
  set r [ou $nb]
  if {$r eq {}} { return 0 }
  lassign $r lab i
  expr {[actif $lab] != $i}
}

### The single-tab notebook of a page shows no tab (the page's tab says it)
proc ::moderne::lab::masquerOngletsSeuls {} {
  foreach lab [blocs] {
    foreach p [pages $lab] {
      if {[winfo class $p] ne "TPanedwindow"} { continue }
      set nbs [$p panes]
      if {[llength $nbs] != 1} { continue }
      set nb [lindex $nbs 0]
      if {[winfo class $nb] ne "TNotebook"} { continue }
      catch {$nb configure -style [expr {[llength [$nb tabs]] == 1 ? "Sans.TNotebook" : "TNotebook"}]}
    }
  }
}

# (a tab dragged into or out of a page: its tab bar shown or hidden)
catch {trace add execution ::docking::setTabStatus leave {apply {args {catch ::moderne::lab::masquerOngletsSeuls}}}}
