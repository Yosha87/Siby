
###
### Siby: list of suggestions below an entry field
###
### While typing, a clickable list opens below the field without taking
### the keyboard from it: you keep typing; ↓ enters the list, Enter or a
### click selects, Escape closes.
###
### ::moderne::suggestions::attacher champ proposer choisir
###   proposer : command called with the typed text, returns a list of
###              {label value} pairs;
###   choisir  : command called with the chosen value;
###   annuler  : 1 for a field where a person is chosen (preparation, Alter
###              Ego): a click elsewhere puts back the name it had (Yosha
###              2026-11-04); 0 (search fields): the typed text stays.
### Coming back to a field left half typed shows the suggestions again.
###

namespace eval ::moderne::suggestions {
  variable cfg
  array set cfg {}
  variable attente
  array set attente {}
}

proc ::moderne::suggestions::attacher {champ proposer choisir {annuler 0}} {
  variable cfg
  set cfg($champ) [list $proposer $choisir $annuler]
  bind $champ <KeyRelease> [list ::moderne::suggestions::frappe $champ %K]
  bind $champ <Down> [list ::moderne::suggestions::entrer $champ]
  bind $champ <Escape> [list ::moderne::suggestions::echap $champ]
  bind $champ <FocusOut> [list after 200 [list ::moderne::suggestions::fermerSiAilleurs $champ]]
  # (bindings of their own, kept when the field's owner binds Return or
  # FocusIn itself)
  set tag Sugg$champ
  if {[lsearch -exact [bindtags $champ] $tag] < 0} { bindtags $champ [linsert [bindtags $champ] 1 $tag] }
  bind $tag <KeyPress> [list ::moderne::suggestions::touche $champ %A %K]
  bind $tag <FocusIn> [list ::moderne::suggestions::retour $champ]
  bind $tag <Return> [list after idle [list ::moderne::suggestions::retenir $champ]]
  bind $tag <KP_Enter> [list after idle [list ::moderne::suggestions::retenir $champ]]
  # (the window moved or resized, e.g. the Play window centred again when
  # its content grew: the list follows the field; it stayed where it was,
  # off the window, Yosha 2026-11-11)
  set top [winfo toplevel $champ]
  set tagT SuggTop$champ
  if {[lsearch -exact [bindtags $top] $tagT] < 0} { bindtags $top [linsert [bindtags $top] 0 $tagT] }
  bind $tagT <Configure> [list ::moderne::suggestions::replacer $champ %W]
}

### The list placed under its field again (window moved)
proc ::moderne::suggestions::replacer {champ w} {
  if {![winfo exists $champ] || $w ne [winfo toplevel $champ]} { return }
  set p [popup $champ]
  if {![winfo exists $p] || ![winfo ismapped $p]} { return }
  set x [winfo rootx $champ]
  set y [expr {[winfo rooty $champ] + [winfo height $champ]}]
  wm geometry $p +$x+$y
}

### The first key typed since the last choice: the text it had is kept
### (put back by a click elsewhere); the field is being typed in
proc ::moderne::suggestions::touche {champ car cle} {
  variable avant
  variable tape
  if {$car eq {} && $cle ni {BackSpace Delete}} { return }
  if {$cle in {Return KP_Enter Escape Tab}} { return }
  if {![info exists tape($champ)] || !$tape($champ)} {
    set avant($champ) [$champ get]
    set tape($champ) 1
  }
}

### The field's text is now the one chosen (Enter, a suggestion)
proc ::moderne::suggestions::retenir {champ} {
  variable tape
  set tape($champ) 0
}

### Back in a field left half typed: its suggestions again
proc ::moderne::suggestions::retour {champ} {
  variable tape
  if {![winfo exists $champ] || ![info exists tape($champ)] || !$tape($champ)} { return }
  after idle [list ::moderne::suggestions::proposer $champ]
}

### A click outside the field and its list: the list closes and, in a
### field where a person is chosen, the name it had comes back
bind all <ButtonPress> {+::moderne::suggestions::clic %W}
proc ::moderne::suggestions::clic {w} {
  variable cfg
  foreach champ [array names cfg] {
    set p [popup $champ]
    if {![winfo exists $p] || ![winfo ismapped $p]} { continue }
    if {$w eq $champ || [string match "$p*" $w]} { continue }
    annulerSaisie $champ
  }
}

proc ::moderne::suggestions::annulerSaisie {champ} {
  variable cfg
  variable avant
  variable tape
  variable attente
  catch {after cancel $attente($champ)}
  fermer $champ
  if {![winfo exists $champ] || ![lindex $cfg($champ) 2]} { return }
  if {![info exists tape($champ)] || !$tape($champ)} { return }
  set tape($champ) 0
  if {[winfo class $champ] eq "TCombobox"} {
    $champ set $avant($champ)
  } else {
    $champ delete 0 end
    $champ insert 0 $avant($champ)
  }
}

proc ::moderne::suggestions::frappe {champ touche} {
  variable attente
  if {$touche in {Return KP_Enter Up Down Escape Tab Left Right Home End Shift_L Shift_R Control_L Control_R}} { return }
  catch {after cancel $attente($champ)}
  set attente($champ) [after 180 [list ::moderne::suggestions::proposer $champ]]
}

proc ::moderne::suggestions::popup {champ} {
  return .sugg[string map {. _} $champ]
}

proc ::moderne::suggestions::proposer {champ} {
  variable cfg
  if {![winfo exists $champ]} { return }
  set texte [string trim [$champ get]]
  if {[string length $texte] < 2} { fermer $champ ; return }
  set paires {}
  catch {set paires [uplevel #0 [concat [lindex $cfg($champ) 0] [list $texte]]]}
  if {![llength $paires]} { fermer $champ ; return }
  set p [popup $champ]
  if {![winfo exists $p]} {
    toplevel $p -borderwidth 1 -relief solid
    wm overrideredirect $p 1
    catch {wm transient $p [winfo toplevel $champ]}
    listbox $p.l -height 10 -activestyle dotbox -exportselection 0 -borderwidth 0 -highlightthickness 0
    catch {$p.l configure -font font_Regular -background [::moderne::c surface] -foreground [::moderne::c texte] \
        -selectbackground [::moderne::c accentFonce] -selectforeground #ffffff}
    pack $p.l -fill both -expand 1
    bind $p.l <ButtonRelease-1> [list ::moderne::suggestions::valider $champ]
    bind $p.l <Return> [list ::moderne::suggestions::valider $champ]
    bind $p.l <KP_Enter> [list ::moderne::suggestions::valider $champ]
    bind $p.l <Escape> [list ::moderne::suggestions::fermer $champ 1]
    bind $p.l <Up> [list ::moderne::suggestions::haut $champ]
  }
  $p.l delete 0 end
  set ::moderne::suggestions::valeurs($champ) {}
  foreach paire $paires {
    lassign $paire lib val
    $p.l insert end $lib
    lappend ::moderne::suggestions::valeurs($champ) $val
  }
  $p.l configure -height [expr {min(10, [llength $paires])}] -width 0
  update idletasks
  set x [winfo rootx $champ]
  set y [expr {[winfo rooty $champ] + [winfo height $champ]}]
  set l [expr {max([winfo width $champ], [winfo reqwidth $p.l] + 12)}]
  wm geometry $p ${l}x[expr {[winfo reqheight $p.l] + 2}]+$x+$y
  wm deiconify $p
  raise $p
}

proc ::moderne::suggestions::entrer {champ} {
  set p [popup $champ]
  if {![winfo exists $p] || ![winfo ismapped $p]} { proposer $champ ; return -code break }
  focus $p.l
  $p.l selection clear 0 end
  $p.l selection set 0
  $p.l activate 0
  return -code break
}

proc ::moderne::suggestions::haut {champ} {
  set p [popup $champ]
  if {[$p.l curselection] eq "0"} {
    focus $champ
    return -code break
  }
}

proc ::moderne::suggestions::valider {champ} {
  variable cfg
  set p [popup $champ]
  set i [$p.l curselection]
  if {$i eq {}} { set i [$p.l index active] }
  set val [lindex $::moderne::suggestions::valeurs($champ) $i]
  fermer $champ 1
  if {$val ne {}} { uplevel #0 [concat [lindex $cfg($champ) 1] [list $val]] }
  after idle [list ::moderne::suggestions::retenir $champ]
}

proc ::moderne::suggestions::fermer {champ {focusChamp 0}} {
  set p [popup $champ]
  if {[winfo exists $p]} { wm withdraw $p }
  if {$focusChamp && [winfo exists $champ]} { focus $champ }
}

### Escape with the list open closes the list only (it closed the whole
### preparation window too)
proc ::moderne::suggestions::echap {champ} {
  set p [popup $champ]
  if {[winfo exists $p] && [winfo ismapped $p]} {
    fermer $champ
    return -code break
  }
}

proc ::moderne::suggestions::fermerSiAilleurs {champ} {
  set p [popup $champ]
  set f [focus]
  if {$f ne {} && ([string match "$p*" $f] || $f eq $champ)} { return }
  # (the keyboard went to another field of Siby: as a click elsewhere;
  # another application: the list just closes)
  if {$f ne {}} { annulerSaisie $champ } else { fermer $champ }
}

### End Siby
