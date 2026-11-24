###
### Siby: keyboard and mouse shortcuts, like Lichess and ChessBase.
###
###  Lichess: f flip the board; ← → or h l: move back / forward; Shift+←:
###  out of the variation, before its branching (one level at a time);
###  ↑ ↓ or k j: start / end; d: comment; g: symbols (the "!" menu);
###  right click on a square: colour it; right drag: arrow. Green; red with
###  Shift or Ctrl; blue with Alt; yellow with Shift+Alt (or Ctrl+Alt).
###  ChessBase: s set up a position (board editor); F11 next game
###  (Shift+F11 previous); with one hand, Page Down / Page Up next /
###  previous game (as Ctrl+↓ / Ctrl+↑), and with the left hand, the right one
###  on the mouse: x previous game, c next game; Tab next tab (Shift+Tab previous); Ctrl+K choose
###  a module to open; Ctrl+N new game in a new tab; Ctrl+Y delete the
###  variation; Alt+Up promote it; ] / [ delete the remaining / previous
###  moves; Shift+Ctrl+Y delete the comments, Ctrl+Alt+Y the squares and
###  arrows, Shift+Alt+Y the symbols (redo moves to Ctrl+Shift+Z).
###
### SCID's move entry by typing (letters on the board: "e4", "Nf3"…) is
### replaced by the letter shortcuts; it can be turned back on
### (::moderne::saisieClavier, saved), the letters then type moves again.
###

namespace eval ::moderne::clavier {}
if {![info exists ::moderne::saisieClavier]} { set ::moderne::saisieClavier 0 }

proc ::moderne::clavier::T {fr en} { return [::moderne::tr $fr $en] }

### Does a shortcut apply where the key was pressed?
proc ::moderne::clavier::ici {W} {
  if {[catch {::moderne::commentaire::raccourci $W} r]} { return 0 }
  return $r
}

proc ::moderne::clavier::installer {} {
  if {![::moderne::actif] || ![winfo exists .main.board.bd]} { return }
  # arrows: ↑ start, ↓ end (SCID: 10 moves)
  bind .main <Up> {::move::Start 1}
  bind .main <Down> {::move::End 1}
  lettres
  # F11 / Shift+F11: next / previous game (full screen stays in the menu)
  bind .main <F11> {::game::LoadNextPrev next ; break}
  bind .main <Shift-F11> {::game::LoadNextPrev previous ; break}
  # Page Down / Page Up: the same, with one hand (Ctrl+↓ / Ctrl+↑ needed
  # two, Yosha 2026-11-09); only on the main window: elsewhere they scroll
  bind .main <Next> {::game::LoadNextPrev next ; break}
  bind .main <Prior> {::game::LoadNextPrev previous ; break}
  # (the full screen: Esc leaves it, wherever the focus is)
  bind all <Escape> {+catch {if {[wm attributes . -fullscreen]} {wm attributes . -fullscreen 0}}}
  bind all <F11> {+if {[::moderne::clavier::ici %W] && [winfo toplevel %W] ne ".main"} {::game::LoadNextPrev next}}
  bind all <Shift-F11> {+if {[::moderne::clavier::ici %W] && [winfo toplevel %W] ne ".main"} {::game::LoadNextPrev previous}}
  catch {
    set m .menu.options.windows
    for {set i 0} {$i <= [$m index end]} {incr i} {
      if {![catch {$m entrycget $i -accelerator} a] && $a eq "F11"} { $m entryconfigure $i -accelerator {} }
    }
  }
  # Tab / Shift+Tab: next / previous tab
  bind .main <Tab> {::moderne::clavier::ongletSuivant 1 ; break}
  bind .main <Shift-Tab> {::moderne::clavier::ongletSuivant -1 ; break}
  catch {bind .main <ISO_Left_Tab> {::moderne::clavier::ongletSuivant -1 ; break}}
  # Ctrl+K: choose a module; Ctrl+N: new game in a new notation tab
  bind all <Control-k> {+if {[::moderne::clavier::ici %W]} {::moderne::clavier::modules}}
  bind .main <Control-n> {::moderne::onglets::nouvellePartie ; break}
  # Ctrl+Alt+0: a null move, as in ChessBase (on an AZERTY keyboard the
  # key gives "à", or "@" with AltGr, which Windows reports as Ctrl+Alt)
  foreach k {Key-0 Key-agrave Key-at KP_0 KP_Insert} {
    catch {bind .main <Control-Alt-$k> {if {![::moderne::clavier::saisie %W]} {::moderne::clavier::coupNul ; break}}}
    catch {bind all <Control-Alt-$k> {+if {[::moderne::clavier::ici %W] && [winfo toplevel %W] ne ".main" && ![::moderne::clavier::saisie %W]} {::moderne::clavier::coupNul}}}
  }
  # ChessBase: Ctrl+Y delete the variation, Alt+Up promote it, ] / [ delete
  # the remaining / previous moves, Shift+Ctrl+Y the comments, Ctrl+Alt+Y the
  # squares and arrows, Shift+Alt+Y the symbols; redo moves to Ctrl+Shift+Z
  edition .main
  # right click / right drag on the board: squares and arrows
  set bd .main.board.bd
  bind $bd <ButtonPress-3> {::moderne::clavier::appui %x %y %s ; break}
  bind $bd <B3-Motion> {::moderne::clavier::glisse %x %y ; break}
  bind $bd <ButtonRelease-3> {::moderne::clavier::relache %x %y ; break}
  # left click: the drawn squares and arrows go away (as on Lichess)
  bind $bd <ButtonPress-1> {+::moderne::clavier::effacerMarques}
}

### A null move ("--" in PGN), as ChessBase's Ctrl+Alt+0; not during a
### game against an engine, nor in check (addMove refuses it then)
proc ::moderne::clavier::coupNul {} {
  if {[winfo exists .serGameWin]} { bell ; return }
  addMove null null
}

### Letters: Lichess shortcuts, or SCID's move entry
proc ::moderne::clavier::lettres {} {
  set lichess {f {::moderne::clavier::retourner} h ::move::Back l ::move::Forward
               k {::move::Start 1} j {::move::End 1}
               d ::moderne::commentaire::ouvrir g {::moderne::commentaire::menuSymboles coup}
               s ::moderne::editeur::ouvrir S ::moderne::editeur::ouvrir
               x {::game::LoadNextPrev previous} c {::game::LoadNextPrev next}}
  if {$::moderne::saisieClavier} {
    # SCID: typing moves (the Lichess letters are not used)
    foreach i {o q r n k O Q R B N K} { bind .main <$i> "moveEntry_Char [string toupper $i]" }
    foreach i {a b c d e f g h} { bind .main <Key-$i> "moveEntry_Char $i" }
    foreach i {1 2 3 4 5 6 7 8} {
      bind .main <Key-$i> "moveEntry_Char $i"
      bind .main <Key-KP_$i> "moveEntry_Char $i"
    }
    foreach {k cmd} $lichess { if {$k ni {c d f g h k s S}} { bind .main <Key-$k> {} } }
    return
  }
  foreach i {o q r n k O Q R B N K a b c d e f g h} { bind .main <Key-$i> {} }
  foreach i {1 2 3 4 5 6 7 8} { bind .main <Key-$i> {} ; bind .main <Key-KP_$i> {} }
  foreach {k cmd} $lichess {
    bind .main <Key-$k> "$cmd ; break"
    # (also from the other panels: notation, library…)
    if {![info exists ::moderne::clavier::lie($k)]} {
      set ::moderne::clavier::lie($k) 1
      bind all <Key-$k> [list +if {!$::moderne::saisieClavier && [::moderne::clavier::ici %W] && [winfo toplevel %W] ne ".main"} $cmd]
    }
  }
}

### Menu: Options › typing moves on the keyboard (SCID)
proc ::moderne::clavier::basculerSaisie {} {
  lettres
}

proc ::moderne::clavier::retourner {} {
  if {[llength [info commands toggleRotateBoard]]} { toggleRotateBoard } else { ::board::flip .main.board }
}

################################################################################
### Tabs
################################################################################

### The tab group to go through: the one holding the window with the
### keyboard focus, else the one of the notation (the right column)
proc ::moderne::clavier::groupe {} {
  set f [focus]
  if {$f ne {}} {
    set top [winfo toplevel $f]
    set conteneur .fdock[string range $top 1 end]
    if {$top ne ".main" && [winfo exists $conteneur]} {
      set nb [winfo parent $conteneur]
      foreach t [array names ::docking::tbs] {
        if {[winfo exists $t] && $conteneur in [$t tabs]} { return $t }
      }
    }
  }
  foreach d {.fdockpgnWin .fdockbiblioWin .fdockprepaWin .fdockglistWin} {
    foreach t [array names ::docking::tbs] {
      if {[winfo exists $t] && [winfo exists $d] && $d in [$t tabs]} { return $t }
    }
  }
  return {}
}

proc ::moderne::clavier::ongletSuivant {sens} {
  set nb [groupe]
  if {$nb eq {}} { return }
  set visibles {}
  foreach t [$nb tabs] {
    if {[$nb tab $t -state] ne "hidden"} { lappend visibles $t }
  }
  if {[llength $visibles] < 2} { return }
  set i [lsearch -exact $visibles [$nb select]]
  set j [expr {($i + $sens) % [llength $visibles]}]
  $nb select [lindex $visibles $j]
}

################################################################################
### Squares and arrows with the right button (like Lichess)
################################################################################

### Lichess's brushes: green, red, blue, and "yellow" drawn orange
set ::moderne::pinceaux {G #15781b R #882020 B #003088 Y #e68f00}

proc ::moderne::clavier::couleur {etat} {
  # %s: 1 Shift, 4 Control; Alt: 0x20000 on Windows (there 8 is Num Lock:
  # with it on, every arrow came out blue or orange), 16 (Option) on macOS,
  # 8 on X11
  switch -- [tk windowingsystem] {
    win32   { set alt [expr {($etat & 0x20000) != 0}] }
    aqua    { set alt [expr {($etat & 16) != 0}] }
    default { set alt [expr {($etat & 8) != 0}] }
  }
  set rouge [expr {($etat & 1) || ($etat & 4)}]
  if {$alt && $rouge} { return Y }
  if {$alt} { return B }
  if {$rouge} { return R }
  return G
}

proc ::moderne::clavier::appui {x y etat} {
  variable depart
  variable teinte
  set depart [::board::getSquare .main.board $x $y]
  set teinte [couleur $etat]
}

### While dragging: the arrow (or the circle) is shown as on Lichess, in its
### color, until the button is released
proc ::moderne::clavier::glisse {x y} {
  variable depart
  variable teinte
  variable apercu
  if {![info exists depart] || $depart < 0} { return }
  set c .main.board.bd
  set sq [::board::getSquare .main.board $x $y]
  if {[info exists apercu] && $apercu == $sq} { return }
  set apercu $sq
  $c delete flecheApercu
  if {$sq < 0} { return }
  set couleur [dict get $::moderne::pinceaux $teinte]
  if {$sq == $depart} {
    lassign [$c coords sq$sq] x0 y0 x1 y1
    set m [expr {($x1 - $x0) * 0.06}]
    $c create oval [expr {$x0 + $m}] [expr {$y0 + $m}] [expr {$x1 - $m}] [expr {$y1 - $m}] \
        -outline $couleur -width [expr {max(2, int(($x1 - $x0) * 0.07))}] -tags flecheApercu
  } else {
    catch {::moderne::fleche::dessiner $c $depart $sq $couleur 0 0.6 flecheApercu}
  }
  $c raise flecheApercu
}

### Left click on the board: removes the squares and arrows drawn on this
### position ([%csl …] and [%cal …] of its comment), as on Lichess. The
### game is marked as changed, so the removal is saved with it. Only the
### marks are redrawn (a piece being dragged is left alone).
proc ::moderne::clavier::effacerMarques {} {
  set com {}
  catch {set com [sc_pos getComment]}
  if {![regexp {\[%(csl|cal)\s} $com]} { return }
  regsub -all {\s*\[%(csl|cal)\s+[^\]]*\]} $com { } com
  regsub -all {  +} $com { } com
  sc_game undoPoint
  sc_pos setComment [string trim $com]
  catch {.main.board.bd delete mark}
  catch {::board::mark::clear .main.board}
  after idle {catch {::pgn::Refresh 1}}
  # (the click that erased them is not the first click of a move: the next
  # one on a piece is, to drag it or click its arrival square, Yosha
  # 2026-11-16)
  after idle {
    if {$::selectedSq >= 0} {
      catch {::board::highlightSquare .main.board $::selectedSq}
      set ::selectedSq -1
    }
    catch {::board::setDragSquare .main.board -1}
  }
}

proc ::moderne::clavier::relache {x y} {
  variable depart
  variable teinte
  variable apercu
  catch {.main.board.bd delete flecheApercu}
  catch {unset apercu}
  if {![info exists depart] || $depart < 0} { return }
  set arrivee [::board::getSquare .main.board $x $y]
  set de $depart
  set depart -1
  if {$arrivee < 0} { return }
  if {$de == $arrivee} {
    ::moderne::commentaire::marquer csl $teinte[::board::san $de]
  } else {
    ::moderne::commentaire::marquer cal $teinte[::board::san $de][::board::san $arrivee]
  }
}

################################################################################
### Ctrl+K: choose a module to open
################################################################################

proc ::moderne::clavier::listeModules {} {
  set l {}
  set n 0
  foreach e $::engines(list) {
    lappend l [list "[T Moteur Engine] : [lindex $e 0]" [list makeAnalysisWin $n]]
    incr n
  }
  foreach {fr en cmd} {
    "Notation" "Notation" ::pgn::Open
    "Liste des parties" "Game list" ::windows::gamelist::Open
    "Bibliothèque d'ouvertures" "Opening library" ::moderne::biblio::ouvrir
    "Arbre (base)" "Tree (database)" ::tree::Open
    "Tables de finales" "Endgame tables" ::tb::Open
    "Se préparer contre un adversaire" "Prepare against a player" ::moderne::prepa::ouvrir
    "Retransmissions en direct" "Live broadcasts" ::moderne::direct::ouvrir
    "Mes bases" "My databases" ::moderne::mesbases::ouvrir
    "Commentaire" "Comment" ::moderne::commentaire::ouvrir
    "Recherche de positions" "Position search" ::moderne::positions::ouvrir
    "Motifs tactiques" "Tactical patterns" ::moderne::motifs::ouvrir
    "Entraînement de répertoire" "Repertoire training" ::moderne::entrainement::ouvrir
    "Graphique de score" "Score graph" ::tools::graphs::score::Raise
    "Bases ouvertes" "Open databases" ::windows::switcher::Open
  } {
    lappend l [list [T $fr $en] $cmd]
  }
  return $l
}

proc ::moderne::clavier::modules {} {
  set w .choixModule
  catch {destroy $w}
  toplevel $w -background [::moderne::c surface]
  wm overrideredirect $w 1
  catch {wm attributes $w -topmost 1}
  set f [ttk::frame $w.f -padding 10]
  pack $f -fill both -expand 1
  ttk::label $f.t -text [T "Ouvrir un module" "Open a module"] -font font_Bold
  ttk::entry $f.e -textvariable ::moderne::clavier::filtre -width 40
  listbox $f.l -height 14 -activestyle none -borderwidth 0 -highlightthickness 0 \
      -background [::moderne::c surface] -foreground [::moderne::c texte] \
      -selectbackground [::moderne::c accent] -selectforeground white -font font_Regular
  ttk::label $f.a -foreground [::moderne::c texteDoux] -font font_Small \
      -text [T "Tape pour filtrer • Entrée : ouvrir • Échap : fermer" "Type to filter • Enter: open • Esc: close"]
  pack $f.t -anchor w
  pack $f.e -fill x -pady {6 6}
  pack $f.l -fill both -expand 1
  pack $f.a -anchor w -pady {6 0}
  set ::moderne::clavier::filtre {}
  remplirModules
  trace add variable ::moderne::clavier::filtre write {apply {args {catch ::moderne::clavier::remplirModules}}}
  bind $f.e <Return> ::moderne::clavier::ouvrirModule
  bind $f.l <Double-Button-1> ::moderne::clavier::ouvrirModule
  bind $f.l <Return> ::moderne::clavier::ouvrirModule
  bind $f.e <Down> {::moderne::clavier::deplacer 1 ; break}
  bind $f.e <Up> {::moderne::clavier::deplacer -1 ; break}
  bind $w <Escape> [list destroy $w]
  bind $w <FocusOut> [list after 200 [list ::moderne::clavier::fermerSiAilleurs $w]]
  update idletasks
  set x [expr {[winfo rootx .] + ([winfo width .] - [winfo reqwidth $w]) / 2}]
  set y [expr {[winfo rooty .] + [winfo height .] / 4}]
  wm geometry $w +$x+$y
  focus -force $f.e
}

proc ::moderne::clavier::fermerSiAilleurs {w} {
  if {![winfo exists $w]} { return }
  set f [focus]
  if {$f eq {} || [winfo toplevel $f] ne $w} { destroy $w }
}

proc ::moderne::clavier::remplirModules {} {
  variable choix
  set l .choixModule.f.l
  if {![winfo exists $l]} { return }
  $l delete 0 end
  set choix {}
  set filtre [string tolower [string trim $::moderne::clavier::filtre]]
  foreach m [listeModules] {
    if {$filtre ne {} && [string first $filtre [string tolower [lindex $m 0]]] < 0} { continue }
    $l insert end "  [lindex $m 0]"
    lappend choix [lindex $m 1]
  }
  if {[llength $choix]} { $l selection set 0 ; $l activate 0 }
}

proc ::moderne::clavier::deplacer {d} {
  set l .choixModule.f.l
  set i [lindex [$l curselection] 0]
  if {$i eq {}} { set i 0 }
  set i [expr {max(0, min([$l size] - 1, $i + $d))}]
  $l selection clear 0 end
  $l selection set $i
  $l see $i
}

proc ::moderne::clavier::ouvrirModule {} {
  variable choix
  set l .choixModule.f.l
  set i [lindex [$l curselection] 0]
  if {$i eq {} || $i >= [llength $choix]} { return }
  set cmd [lindex $choix $i]
  catch {destroy .choixModule}
  if {[catch {uplevel #0 $cmd} err]} { puts stderr "Siby module: $err" }
}

after idle {after idle ::moderne::clavier::installer}

################################################################################
### Space: the best move of the module on the left (of the only one when
### there is one); Shift+Space: of the module on the right. Wherever the
### last click was (board, notation, a module…), except while typing in a
### field. A move already in the game (main line or variation) is followed,
### not added again. (Yosha, 2026-10-31; Space used to pause an engine.)
################################################################################

### Modules (analysis windows) analysing with a line, left to right
proc ::moderne::clavier::modulesTries {} {
  set l {}
  # (from 0: the first engine's module is .analysisWin0, 2026-11-01)
  for {set n 0} {$n <= 16} {incr n} {
    set w .analysisWin$n
    if {![winfo exists $w] || ![winfo ismapped $w]} { continue }
    if {![info exists ::analysis(analyzeMode$n)] || !$::analysis(analyzeMode$n)} { continue }
    if {[coupModule $n] eq {}} { continue }
    lappend l [list $n [winfo rootx $w] [winfo rooty $w]]
  }
  return [lmap e [lsort -integer -index 1 [lsort -integer -index 2 $l]] {lindex $e 0}]
}

### The best move of module n in the current position, in UCI ({} when its
### line is not for this position)
proc ::moderne::clavier::coupModule {n} {
  # Toby: its most probable move (its table; it sends no usable "pv")
  if {[winfo exists .analysisWin$n.toby]} {
    set uci {} ; set best -1
    catch {
      foreach l [dict get $::moderne::toby::tableau($n) lignes] {
        set p [dict get $l prob]
        if {[string is double -strict $p] && $p > $best} { set best $p ; set uci [string tolower [dict get $l uci]] }
      }
    }
    if {$uci eq {} || $uci ni [sc_pos movesUci]} { return {} }
    return $uci
  }
  if {![info exists ::analysis(moves$n)]} { return {} }
  set uci [string tolower [lindex $::analysis(moves$n) 0]]
  if {$uci ni [sc_pos movesUci]} { return {} }
  return $uci
}

proc ::moderne::clavier::jouerModule {cote} {
  set mods [modulesTries]
  if {![llength $mods]} { return 0 }
  set n [expr {$cote eq "droite" ? [lindex $mods end] : [lindex $mods 0]}]
  set uci [coupModule $n]
  if {$uci eq {}} { return 0 }
  # already in the game: followed
  # (straight on: ::move::Forward would offer the variations' choice)
  if {$uci eq [string tolower [sc_game info nextMoveUCI]]} {
    sc_move forward
    updateBoard -animate
    catch ::moderne::sons::dejaJoue
    return 1
  }
  set i 0
  foreach v [sc_var list UCI] {
    if {[string tolower $v] eq $uci} {
      sc_var moveInto $i
      updateBoard -animate
      catch ::moderne::sons::dejaJoue
      return 1
    }
    incr i
  }
  # otherwise added as a move played on the board (same questions)
  set legaux [sc_pos movesUci]
  catch {sc_info language en}
  set san [lindex [sc_pos moves] [lsearch -exact $legaux $uci]]
  catch ::moderne::lettresPieces
  if {$san eq {}} { return 0 }
  addSanMove $san -animate
  return 1
}

### Bound to the whole window; nothing while typing in a field
proc ::moderne::clavier::espace {cote} {
  set f [focus]
  if {$f ne {}} {
    set c [winfo class $f]
    if {$c in {Entry TEntry Spinbox TSpinbox TCombobox Listbox}} { return }
    if {$c eq "Text" && ![catch {$f cget -state} etat] && $etat eq "normal"} { return }
  }
  if {[jouerModule $cote]} { return -code break }
}
bind all <space> {::moderne::clavier::espace gauche}
bind all <Shift-space> {::moderne::clavier::espace droite}

################################################################################
### The main window's shortcuts (bound to .main) wherever the focus is:
### notation, a module, a list… (Ctrl+N did nothing from the notation,
### 2026-10-31). The focused widget keeps the keys it uses itself (typing
### in a field, the arrows of a list); a read-only text (the notation) has
### no keys of its own beyond its explicit bindings. Plain keys (letters,
### digits: typing a move on the board) are not relayed.
################################################################################

proc ::moderne::clavier::editable {f} {
  set c [winfo class $f]
  if {$c in {Entry TEntry Spinbox TSpinbox TCombobox}} {
    return [expr {[catch {$f cget -state} e] || $e ne "disabled"}]
  }
  # (the notation is a text left in state normal for its tags, but nothing
  # is typed in it: "]" after clicking a move did nothing, Yosha 2026-11-04)
  if {$c eq "Text" && [string match *.pgnWin.text $f]} { return 0 }
  if {$c eq "Text"} { return [expr {![catch {$f cget -state} e] && $e eq "normal"}] }
  return 0
}

### Does widget f use sequence seq itself (its own tags, its class unless a
### read-only text, its toplevel other than the main window)?
proc ::moderne::clavier::utilisePar {f seq} {
  foreach t [bindtags $f] {
    if {$t in {all .main .}} { continue }
    if {$t eq [winfo class $f] && $t eq "Text" && ![editable $f]} { continue }
    if {[bind $t $seq] ne {}} { return 1 }
  }
  return 0
}

proc ::moderne::clavier::relayer {seq} {
  set f [focus]
  if {$f eq {} || ![winfo exists $f]} { return }
  if {".main" in [bindtags $f]} { return }
  if {[editable $f] || [utilisePar $f $seq]} { return }
  set script [bind .main $seq]
  if {$script eq {}} { return }
  # (a script ending in "break" is fine here)
  catch {uplevel #0 [string map {%W .main %% %} $script]}
  return -code break
}

### Every key shortcut of .main relayed from "all" (except plain keys and
### those already bound there)
proc ::moderne::clavier::globaliser {} {
  foreach seq [bind .main] {
    if {![regexp {Control|Alt|Meta|Command|F[0-9]|Escape|Delete|Prior|Next|Home|End} $seq]} { continue }
    if {[regexp {Button|Motion|Enter|Leave|Configure|Map|Destroy|FocusIn|FocusOut|MouseWheel} $seq]} { continue }
    if {[bind all $seq] ne {}} { continue }
    bind all $seq [list ::moderne::clavier::relayer $seq]
  }
}
after 2500 {catch ::moderne::clavier::globaliser}

### Left / Right: a move back / forward in the game wherever the focus is,
### as the arrows under the board (Yosha 2026-11-01: they did nothing in
### the preparation, a window of its own), except while typing in a field.
### Trees lose their Left / Right (they only folded a branch).
proc ::moderne::clavier::saisie {f} {
  if {[winfo class $f] in {TCombobox TSpinbox} && ![catch {$f instate readonly} ro] && $ro} { return 0 }
  return [editable $f]
}

proc ::moderne::clavier::fleche {seq} {
  set f [focus]
  if {$f eq {} || ![winfo exists $f]} { return }
  # (the main window has its own binding, the variations popup too)
  if {".main" in [bindtags $f]} { return }
  if {[saisie $f]} { return }
  foreach t [bindtags $f] {
    # (a tag that already moves one move: the tab bars, SCID's
    # standardShortcuts on TNotebook; one key went two moves on a tab bar
    # that had the focus, coups.log of Yosha 2026-11-23)
    if {[string match *::move::* [bind $t <$seq>]]} { return }
    if {$t in {all Treeview TCombobox TNotebook Canvas Frame TFrame}} { continue }
    if {[bind $t <$seq>] ne {}} { return }
  }
  catch {uplevel #0 [expr {$seq eq "Left" ? "::move::Back" : "::move::Forward"}]}
  return -code break
}
### Sliders (games list, levels): a click beside the ball takes it there
### at once, instead of one step (Yosha 2026-11-01); the ball can then be
### dragged on without releasing
proc ::moderne::clavier::saut {w x y} {
  if {[string match *slider* [$w identify $x $y]]} { return }
  if {[catch {$w get $x $y} v]} { return }
  set var [$w cget -variable]
  if {$var ne {}} { uplevel #0 [list set $var $v] } else { $w set $v }
  set cmd [$w cget -command]
  if {$cmd ne {}} { catch {uplevel #0 [concat $cmd [list $v]]} }
}
catch {
  if {[string first ::moderne::clavier::saut [bind TScale <Button-1>]] < 0} {
    bind TScale <Button-1> "::moderne::clavier::saut %W %x %y\n[bind TScale <Button-1>]"
  }
}

### ] / [: delete the next / previous moves wherever the focus is (only the
### main window and the notation had them: in the Lab's panels the keys did
### nothing, Yosha 2026-11-10), except while typing in a field
proc ::moderne::clavier::crochet {W cmd} {
  if {![winfo exists $W]} { return }
  set tags [bindtags $W]
  # (the main window and the notation have their own binding)
  if {".main" in $tags || ".pgnWin" in $tags} { return }
  if {[saisie $W]} { return }
  catch {uplevel #0 $cmd}
  return -code break
}
# (Alt+X / Alt+C too: the same without AltGr, X and C being back and
# forward, Yosha 2026-11-10: [ and ] did nothing on her AZERTY keyboard)
foreach {seq cmd} {bracketleft ::game::TruncateBegin bracketright ::game::Truncate
                   Alt-x ::game::TruncateBegin Alt-X ::game::TruncateBegin Alt-c ::game::Truncate Alt-C ::game::Truncate} {
  if {[string first ::moderne::clavier::crochet [bind all <$seq>]] < 0} {
    bind all <$seq> [list ::moderne::clavier::crochet %W $cmd]
  }
}

### Shift+Left: out of the variation, back just before where it branches
### (a sub-variation: one level), as on Lichess; → then offers the choice
### of the branching (Yosha 2026-11-18). On the main line: nothing.
proc ::moderne::clavier::sortirVariante {W} {
  if {![::moderne::commentaire::raccourci $W]} { return }
  if {[sc_var level] > 0} { ::move::ExitVar }
  return -code break
}
bind all <Shift-Left> {::moderne::clavier::sortirVariante %W}

foreach seq {Left Right} {
  bind all <$seq> [list ::moderne::clavier::fleche $seq]
  # (a tree or a read-only list: the arrows move in the game, not in it)
  foreach cl {Treeview TNotebook} { bind $cl <$seq> {} }
}

### End Siby

################################################################################
### Editing shortcuts, as ChessBase (Yosha 2026-11-02)
################################################################################

### Binds them on w (.main, or the notation when it is a window of its own)
proc ::moderne::clavier::edition {w} {
  foreach {seq cmd} {
    <Control-y> ::moderne::clavier::supprimerVariante
    <Control-Z> {::menuUndo redo}
    <Control-Y> {::moderne::clavier::effacer commentaires}
    <Alt-Up> ::moderne::clavier::promouvoirVariante
    <bracketright> {::game::Truncate}
    <bracketleft> {::game::TruncateBegin}
    <Alt-x> {::game::TruncateBegin}
    <Alt-X> {::game::TruncateBegin}
    <Alt-c> {::game::Truncate}
    <Alt-C> {::game::Truncate}
    <Control-Shift-Y> {::moderne::clavier::effacer commentaires}
    <Control-Alt-y> {::moderne::clavier::effacer marques}
    <Control-Alt-Y> {::moderne::clavier::effacer marques}
    <Shift-Alt-Y> {::moderne::clavier::effacer symboles}
    <Alt-Y> {::moderne::clavier::effacer symboles}
  } {
    catch {bind $w $seq "if {!\[::moderne::clavier::saisie %W\]} {$cmd ; break}"}
  }
  # (AZERTY on Windows: "[" is AltGr+5 and "]" AltGr+")", reported as
  # Ctrl+Alt with the key's own keysym, which Ctrl+5 "!?" took)
  foreach {k cmd} {bracketleft ::game::TruncateBegin parenleft ::game::TruncateBegin 5 ::game::TruncateBegin
                   bracketright ::game::Truncate parenright ::game::Truncate degree ::game::Truncate} {
    catch {bind $w <Control-Alt-Key-$k> "if {!\[::moderne::clavier::saisie %W\]} {$cmd ; break}"}
  }
}

### The variation the current move is in: deleted (Ctrl+Y) or promoted to the
### main line (Alt+Up); outside a variation, a bell
proc ::moderne::clavier::supprimerVariante {} {
  if {[sc_var level] == 0} { bell ; return }
  set n [sc_var number]
  sc_game undoPoint
  sc_var exit
  sc_var delete $n
  updateBoard -pgn
  updateTitle
}

proc ::moderne::clavier::promouvoirVariante {} {
  if {[sc_var level] == 0} { bell ; return }
  # (the same move stays shown: count the moves back to the variation's start)
  set k 0
  while {![sc_pos isAt vstart] && $k < 1000} { sc_move back ; incr k }
  set n [sc_var number]
  sc_game undoPoint
  sc_var exit
  sc_var promote $n
  for {set i 0} {$i < $k} {incr i} { sc_move forward }
  updateBoard -pgn
  updateTitle
}

### Makes the variation the first one, the same move staying shown
### (notation's right-click menu; it went back to the variation's start)
proc ::moderne::clavier::premiereVariante {} {
  if {[sc_var level] == 0} { bell ; return }
  set k 0
  while {![sc_pos isAt vstart] && $k < 1000} { sc_move back ; incr k }
  set n [sc_var number]
  sc_game undoPoint
  sc_var exit
  sc_var first $n
  # (entering a variation plays its first move)
  if {$k > 0} {
    sc_var enter 0
    for {set i 1} {$i < $k} {incr i} { sc_move forward }
  }
  updateBoard -pgn
  updateTitle
}

### Deletes in the whole game (variations too): the comments' text (the
### squares, arrows and clock times stay), the squares and arrows, or the
### symbols (! ? += …). Ctrl+Z brings them back.
proc ::moderne::clavier::effacer {quoi} {
  set loc [sc_pos location]
  set auDebut [sc_pos isAt start]
  sc_game undoPoint
  sc_move start
  set n 0
  catch {set n [parcourirEffacer $quoi]}
  # (back to the same move; "sc_move pgn" does not know the start position)
  if {$auDebut} { sc_move start } else { catch {sc_move pgn $loc} }
  if {$n == 0} { bell }
  ::moderne::sansRelance { updateBoard -pgn }
  updateTitle
  return $n
}

### One position: returns 1 when something was deleted
proc ::moderne::clavier::effacerIci {quoi} {
  if {$quoi eq "symboles"} {
    if {[string trim [sc_pos getNags]] in {{} 0}} { return 0 }
    sc_pos clearNags
    return 1
  }
  set com {}
  catch {set com [sc_pos getComment]}
  if {$com eq {}} { return 0 }
  if {$quoi eq "marques"} {
    regsub -all {\s*\[%(csl|cal)\s+[^\]]*\]} $com { } nouveau
  } else {
    set nouveau [join [regexp -all -inline {\[%[^\]]*\]} $com] { }]
  }
  regsub -all {  +} $nouveau { } nouveau
  set nouveau [string trim $nouveau]
  if {$nouveau eq [string trim $com]} { return 0 }
  sc_pos setComment $nouveau
  return 1
}

### Recursive walk from the current position (the main line, then each
### variation, its first comment included)
proc ::moderne::clavier::parcourirEffacer {quoi} {
  set n [effacerIci $quoi]
  while 1 {
    if {[sc_pos isAt vend] || [sc_pos isAt end]} { return $n }
    set nv [sc_var count]
    for {set i 0} {$i < $nv} {incr i} {
      sc_var enter $i
      sc_move back
      incr n [parcourirEffacer $quoi]
      sc_var exit
    }
    sc_move forward
    incr n [effacerIci $quoi]
  }
}

################################################################################
### Two moves forward (or back) for one press (Yosha 2026-11-10, not
### reproduced): when ::move::Forward (or Back) runs twice within 400 ms, both calls are written to
### coups.log (Siby's folder; in the problem report): who called, the focus,
### the widget under the pointer, the last keys and clicks
################################################################################

namespace eval ::moderne::mouchard {
  variable dernier {}
  variable evenements {}
}

proc ::moderne::mouchard::noter {quoi W} {
  variable evenements
  lappend evenements [list [clock milliseconds] $quoi $W]
  set evenements [lrange $evenements end-7 end]
}

proc ::moderne::mouchard::appel {} {
  set pile {}
  for {set i [expr {[info level] - 2}]} {$i >= 1} {incr i -1} {
    lappend pile [string range [info level $i] 0 80]
  }
  set X [winfo pointerx .] ; set Y [winfo pointery .]
  set sous {} ; catch {set sous [winfo containing $X $Y]}
  return [list [clock milliseconds] [sc_pos location] $pile [focus] $sous]
}

proc ::moderne::mouchard::installer {} {
  # (forward and back: Yosha saw both, 2026-11-16)
  foreach {cmd sens} {Forward forward Back back} {
    if {[llength [info commands ::move::${cmd}_mouchard]] || ![llength [info commands ::move::$cmd]]} { continue }
    rename ::move::$cmd ::move::${cmd}_mouchard
    proc ::move::$cmd {{count 1}} [string map [list @CMD@ $cmd @SENS@ $sens] {
      catch {::moderne::mouchard::verifier @SENS@}
      uplevel 1 [list ::move::@CMD@_mouchard $count]
    }]
  }
  # (the keys: a tag put first on the widget that gets the focus, so that
  # every key is seen, before the widget's own bindings and their break)
  bind SibyMouchard <KeyPress> {::moderne::mouchard::noter "key %K" %W}
  bind SibyMouchard <ButtonPress> {::moderne::mouchard::noter "button %b" %W}
  # (Shift+Left here, the first tag of the widget with the focus: on the
  # later tags, a plain <Left> binding (the main window, the board, the
  # library) took Shift+Left too and went one move back first)
  bind SibyMouchard <Shift-Left> {::moderne::mouchard::noter "key Shift-Left" %W ; ::moderne::clavier::sortirVariante %W}
  # (not the wheel on this tag: the wheel's routing (::moderne::molette)
  # took the tag for the widget's own wheel and nothing scrolled any more,
  # My databases' tiles, Yosha 2026-11-17; "bind all" below writes it)
  bind all <FocusIn> {+::moderne::mouchard::marquer %W}
  catch {::moderne::mouchard::marquer [focus]}
  bind all <ButtonPress> {+::moderne::mouchard::noter "button %b" %W}
  # (the wheel wherever the pointer is: the one double move of 16 November
  # came 214 ms after a key, the pointer over the board, nothing written;
  # a touchpad's slight scroll is likely, these lines will tell)
  bind all <MouseWheel> {+::moderne::mouchard::noter "wheel %D" %W}
  bind all <Shift-MouseWheel> {+::moderne::mouchard::noter "wheel+shift %D" %W}
}

### Two moves the same way within 400 ms: both calls written to coups.log
proc ::moderne::mouchard::verifier {sens} {
  variable dernier
  set ici [concat [appel] $sens]
  set avant $dernier
  set dernier $ici
  if {$avant eq {} || [lindex $avant 5] ne $sens || [lindex $ici 0] - [lindex $avant 0] >= 400} { return }
  set c [open [file join $::scidUserDir coups.log] a] ; fconfigure $c -encoding utf-8
  puts $c "[clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}] two moves $sens in [expr {[lindex $ici 0] - [lindex $avant 0]}] ms"
  foreach {nom r} [list first $avant second $ici] {
    lassign $r t loc pile f sous
    puts $c "  $nom: ply $loc, focus $f, under the pointer $sous"
    puts $c "    called by: [join $pile { <- }]"
  }
  foreach e $::moderne::mouchard::evenements {
    lassign $e t quoi W
    puts $c "  [expr {$t - [lindex $ici 0]}] ms: $quoi on $W"
  }
  close $c
}
proc ::moderne::mouchard::marquer {W} {
  if {$W eq {} || ![winfo exists $W]} { return }
  set tags [bindtags $W]
  if {[lindex $tags 0] ne "SibyMouchard"} { bindtags $W [linsert [lsearch -all -inline -not -exact $tags SibyMouchard] 0 SibyMouchard] }
}
after 3000 {catch ::moderne::mouchard::installer}

### End Siby
