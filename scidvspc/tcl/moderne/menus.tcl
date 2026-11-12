
###
### Siby: menu bar inside the window (Windows)
###
### On Windows, the native menu bar stays white, even with the dark
### theme. It is replaced by a row of flat buttons in the theme's colors,
### which open the same menus (Siby's .menuSiby, or SCID's .menu). Alt+letter
### shortcuts are kept; the labels follow language changes.
### Only in "single window" mode (docking) with the modern theme.
###

namespace eval ::moderne::barreMenus {
  variable f .barreMenus
}

proc ::moderne::barreMenus::actif {} {
  # (SCID_BARRE_MENUS=1: also outside Windows, for testing)
  return [expr {[::moderne::actif] && ([tk windowingsystem] eq "win32" || [info exists ::env(SCID_BARRE_MENUS)]) &&
                [info exists ::dot_w] && $::dot_w eq "." && [winfo exists .menu]}]
}

proc ::moderne::barreMenus::installer {} {
  variable f
  if {![actif] || [winfo exists $f]} { return }
  catch {
    ttk::style layout Menubar.TMenubutton {
      Toolbutton.button -children {
        Menubutton.padding -children { Menubutton.label -side left -expand 1 }
      }
    }
    ttk::style configure Menubar.TMenubutton -padding {9 3 9 4}
  }
  ttk::frame $f -padding {4 2 4 2}
  remplir
  afficher
  # Language: the labels of .menu change, we copy them over
  trace add variable ::language write [list ::moderne::barreMenus::langue]
  # Show / hide the menu bar (Options): ours instead
  proc ::showMenubar {} { ::moderne::barreMenus::afficher }
}

### The menus shown: Siby's bar when built, else SCID's
proc ::moderne::barreMenus::source {} {
  expr {[winfo exists .menuSiby] ? ".menuSiby" : ".menu"}
}

proc ::moderne::barreMenus::remplir {} {
  variable f
  if {![winfo exists $f]} { return }
  foreach w [winfo children $f] { destroy $w }
  set m [source]
  set dernier [$m index end]
  if {$dernier eq "none"} { return }
  for {set i 0} {$i <= $dernier} {incr i} {
    if {[$m type $i] ne "cascade"} { continue }
    set lib [$m entrycget $i -label]
    set sous [$m entrycget $i -menu]
    set u [$m entrycget $i -underline]
    if {![string is integer -strict $u]} { set u -1 }
    set b $f.m$i
    ttk::menubutton $b -text $lib -underline $u -menu $sous -style Menubar.TMenubutton -takefocus 0
    pack $b -side left
    if {$u >= 0 && $u < [string length $lib]} {
      set lettre [string tolower [string index $lib $u]]
      if {[string is alpha -strict $lettre]} {
        catch {bind . <Alt-Key-$lettre> [list ::moderne::barreMenus::ouvrir $b]}
      }
    }
  }
}

proc ::moderne::barreMenus::ouvrir {b} {
  if {![winfo exists $b]} { return }
  set m [$b cget -menu]
  tk_popup $m [winfo rootx $b] [expr {[winfo rooty $b] + [winfo height $b]}]
  return -code break
}

proc ::moderne::barreMenus::afficher {} {
  variable f
  if {![winfo exists $f]} { return }
  . configure -menu {}
  if {$::gameInfo(showMenu)} {
    set avant [lindex [pack slaves .] 0]
    if {$avant ne {} && $avant ne $f} {
      pack $f -side top -fill x -before $avant
    } else {
      pack $f -side top -fill x
    }
  } else {
    pack forget $f
  }
}

proc ::moderne::barreMenus::langue {args} {
  after idle ::moderne::barreMenus::remplir
}

after idle ::moderne::barreMenus::installer

###
### Siby: SCID's older entries (Play and Tools menus) moved into a
### "More (SCID)" submenu at the bottom, so the menus show Siby's
### features first. Translations still follow (configMenuText looks in
### the submenu too).
###

namespace eval ::moderne::plusScid {
  variable tags {
    .menu.play {ToolsTrainFics ToolsComp ToolsTacticalGame ToolsTrainTactics}
    .menu.tools {ToolsOpReport ToolsTracker ToolsEmail ToolsFilterGraph ToolsAbsFilterGraph ToolsRating ToolsScore ToolsScreenshot}
  }
}

### Index of the entry whose label is the tag or its translation
proc ::moderne::plusScid::trouver {m tag} {
  set dernier [$m index end]
  if {$dernier eq "none"} { return {} }
  set libs [list $tag]
  foreach cle [array names ::menuLabel *,$tag] { lappend libs $::menuLabel($cle) }
  for {set i 0} {$i <= $dernier} {incr i} {
    if {[$m type $i] ni {command checkbutton radiobutton}} { continue }
    if {[$m entrycget $i -label] in $libs} { return $i }
  }
  return {}
}

proc ::moderne::plusScid::ranger {} {
  variable tags
  if {![::moderne::actif]} { return }
  envelopper
  foreach {m l} $tags {
    if {![winfo exists $m]} { continue }
    set p $m.plus
    if {![winfo exists $p]} {
      ::menu $p -tearoff 0
      $m add separator
      $m add cascade -label [::moderne::tr "Plus (classique)" "More (classic)"] -menu $p
    }
    foreach tag $l {
      set i [trouver $m $tag]
      if {$i eq {}} { continue }
      set opts {}
      foreach o {-label -command -accelerator -underline -state} {
        lappend opts $o [$m entrycget $i $o]
      }
      $p add command {*}$opts
      $m delete $i
    }
  }
}

### configMenuText: an entry not found in a menu is looked for in its
### "More (SCID)" submenu
proc ::moderne::plusScid::envelopper {} {
  if {![llength [info commands ::configMenuText]] || [llength [info commands ::moderne::plusScid::configOrig]]} { return }
  rename ::configMenuText ::moderne::plusScid::configOrig
  proc ::configMenuText {menu entry tag lang} {
    if {[winfo exists $menu.plus] && [catch {$menu index $entry}]} {
      if {![catch {$menu.plus index $entry}]} { set menu $menu.plus }
    }
    ::moderne::plusScid::configOrig $menu $entry $tag $lang
  }
}

after idle ::moderne::plusScid::ranger

### End Siby
