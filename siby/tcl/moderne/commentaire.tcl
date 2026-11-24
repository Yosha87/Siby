
###
### Siby: annotate as in ChessBase
###
###  - Ctrl+A: small "comment after the move" window opened in
###    place, ready for typing; Enter confirms, Shift+Enter inserts a new line,
###    Esc cancels. Symbol buttons (! ? !! ?? !? ?!, evaluations, N).
###    Double-clicking a move in the PGN window, or clicking a
###    comment: same window.
###  - Ctrl+1 to Ctrl+6: ! ? !! ?? !? ?! (as in ChessBase); Ctrl+0 clears
###    the move's symbols.
###  - Alt+click on a square: colored square; Alt+drag: arrow (as in
###    ChessBase). Green; with Shift: red; with Ctrl: yellow. Making the
###    same mark again removes it. Stored in the comment in the standard
###    [%csl …] / [%cal …] format (read by ChessBase, Lichess…).
### The old comment editor (Ctrl+E) is still available.
###

namespace eval ::moderne::commentaire {
  variable w .comRapide
  variable depart -1      ;# start square of a mouse-drawn arrow
  variable couleur G
}

proc ::moderne::commentaire::T {fr en} { return [::moderne::tr $fr $en] }

### [%…] codes of a comment (marks, evaluations, clocks…) and free text
proc ::moderne::commentaire::separer {com} {
  set codes [regexp -all -inline {\[%[^\]]*\]} $com]
  regsub -all {\s*\[%[^\]]*\]\s*} $com { } texte
  return [list [string trim $texte] [join $codes {}]]
}

### Name of the last move played ("12...Nd7"), {} at the start of the game
proc ::moderne::commentaire::nomCoup {} {
  set prev [sc_game info previousMove]
  if {$prev eq {}} { return {} }
  set num [sc_pos moveNumber]
  if {[sc_pos side] eq "black"} { return "$num.[::trans $prev]" }
  return "[expr {$num - 1}]...[::trans $prev]"
}

################################################################################
### Comment window
################################################################################

proc ::moderne::commentaire::ouvrir {} {
  variable w
  if {[winfo exists $w]} { destroy $w }
  toplevel $w
  wm withdraw $w
  catch {wm transient $w .}
  set coup [nomCoup]
  wm title $w [expr {$coup eq {} ? [T "Commentaire avant la partie" "Comment before the game"] : "[T "Commentaire après" "Comment after"] $coup"}]
  lassign [separer [sc_pos getComment]] texte codes
  set ::moderne::commentaire::codes $codes

  ttk::frame $w.f -padding 10
  pack $w.f -fill both -expand 1
  # Move and position symbols
  ttk::frame $w.f.s
  set style Toolbutton
  if {![catch {ttk::style layout Segment.Toolbutton} l] && $l ne {}} { set style Segment.Toolbutton }
  set i 0
  foreach {nag aide} [list \
      ! [T "bon coup" "good move"] ? [T "mauvais coup" "poor move"] !! [T "excellent coup" "excellent move"] \
      ?? [T "gaffe" "blunder"] !? [T "coup intéressant" "interesting move"] ?! [T "coup douteux" "dubious move"] \
      | {} \
      +- [T "les Blancs gagnent" "White is winning"] +/- [T "net avantage blanc" "White is clearly better"] \
      += [T "léger avantage blanc" "White is slightly better"] = [T "égalité" "equal"] \
      ~ [T "position peu claire" "unclear"] =+ [T "léger avantage noir" "Black is slightly better"] \
      -/+ [T "net avantage noir" "Black is clearly better"] -+ [T "les Noirs gagnent" "Black is winning"] \
      | {} N [T "nouveauté" "novelty"]] {
    if {$nag eq "|"} {
      ttk::separator $w.f.s.sep$i -orient vertical
      pack $w.f.s.sep$i -side left -fill y -padx 4
    } else {
      ttk::checkbutton $w.f.s.n$i -text [dict get {! ! ? ? !! !! ?? ?? !? !? ?! ?! +- +- +/- ± += += = = ~ ∞ =+ =+ -/+ ∓ -+ -+ N N} $nag] -style $style \
          -variable ::moderne::commentaire::nags($nag) -command [list ::moderne::commentaire::basculerNag $nag]
      ::utils::tooltip::Set $w.f.s.n$i $aide
      pack $w.f.s.n$i -side left
    }
    incr i
  }
  pack $w.f.s -side top -fill x -pady {0 8}
  majNags

  text $w.f.t -width 60 -height 5 -wrap word -font font_Regular -undo 1
  catch {$w.f.t configure -background [::moderne::c champ] -foreground [::moderne::c texte] \
      -insertbackground [::moderne::c texteFort] -relief flat -padx 8 -pady 6 \
      -highlightthickness 1 -highlightbackground [::moderne::c bordure] -highlightcolor [::moderne::c accent]}
  $w.f.t insert end $texte
  pack $w.f.t -side top -fill both -expand 1

  ttk::frame $w.f.b
  ttk::label $w.f.b.aide -text [T "Entrée : valider • Maj+Entrée : à la ligne • Échap : annuler" \
      "Enter: save • Shift+Enter: new line • Esc: cancel"] -foreground [expr {[::moderne::actif] ? [::moderne::c texteDoux] : "gray40"}]
  ttk::button $w.f.b.ok -text [T "Valider" "Save"] -command ::moderne::commentaire::valider
  ttk::button $w.f.b.non -text [T "Annuler" "Cancel"] -command [list destroy $w]
  pack $w.f.b.aide -side left
  pack $w.f.b.ok $w.f.b.non -side right -padx {6 0}
  pack $w.f.b -side top -fill x -pady {8 0}
  if {$codes ne {}} {
    ttk::label $w.f.codes -text "[T "Gardés aussi" "Also kept"] : $codes" -foreground [expr {[::moderne::actif] ? [::moderne::c texteDoux] : "gray40"}] -font font_Small
    pack $w.f.codes -side top -anchor w -pady {6 0}
  }

  bind $w.f.t <Return> {::moderne::commentaire::valider ; break}
  bind $w.f.t <KP_Enter> {::moderne::commentaire::valider ; break}
  bind $w.f.t <Shift-Return> {%W insert insert "\n" ; break}
  bind $w <Escape> [list destroy $w]

  # Below the main board, centered
  update idletasks
  set x [expr {[winfo rootx .main.board] + ([winfo width .main.board] - [winfo reqwidth $w]) / 2}]
  set y [expr {[winfo rooty .main.board] + [winfo height .main.board] - [winfo reqheight $w] / 2}]
  # opened from the notation (double click on a move): over the notation,
  # just below the pointer
  lassign [winfo pointerxy .] px py
  set sous [winfo containing $px $py]
  if {$sous ne {} && [string match .pgnWin* $sous]} {
    set x [expr {[winfo rootx .pgnWin] + ([winfo width .pgnWin] - [winfo reqwidth $w]) / 2}]
    set y [expr {$py + 24}]
    if {$y + [winfo reqheight $w] > [winfo rooty .pgnWin] + [winfo height .pgnWin]} {
      # (not enough room below: above the move)
      set y [expr {$py - 24 - [winfo reqheight $w]}]
    }
  }
  set x [expr {max(0, min($x, [winfo screenwidth $w] - [winfo reqwidth $w]))}]
  set y [expr {max(0, min($y, [winfo screenheight $w] - [winfo reqheight $w] - 40))}]
  wm geometry $w +$x+$y
  wm deiconify $w
  focus $w.f.t
  $w.f.t mark set insert end
}

proc ::moderne::commentaire::majNags {} {
  variable nags
  array unset nags
  set actuels [sc_pos getNags]
  if {$actuels eq "0"} { set actuels {} }
  foreach n $actuels { set nags($n) 1 }
}

proc ::moderne::commentaire::basculerNag {nag} {
  variable nags
  set actuels [sc_pos getNags]
  if {$actuels eq "0"} { set actuels {} }
  set coup {! ? !! ?? !? ?!}
  set eval {+- +/- += = ~ =+ -/+ -+}
  sc_game undoPoint
  sc_pos clearNags
  set nouveaux {}
  set present [expr {[lsearch -exact $actuels $nag] >= 0}]
  foreach n $actuels {
    if {$n eq $nag} { continue }
    # only one move symbol and one evaluation symbol at a time
    if {!$present && $nag in $coup && $n in $coup} { continue }
    if {!$present && $nag in $eval && $n in $eval} { continue }
    lappend nouveaux $n
  }
  if {!$present} { lappend nouveaux $nag }
  foreach n $nouveaux { sc_pos addNag $n }
  majNags
  ::moderne::sansRelance {updateBoard -pgn}
}

proc ::moderne::commentaire::valider {} {
  variable w
  variable codes
  if {![winfo exists $w]} { return }
  set texte [string trim [$w.f.t get 1.0 end-1c]]
  set nouveau [string trim "$texte $codes"]
  # (same text and codes, only in another order: nothing changed)
  if {[separer $nouveau] eq [separer [sc_pos getComment]]} { set nouveau [sc_pos getComment] }
  if {$nouveau ne [sc_pos getComment]} {
    sc_game undoPoint
    sc_pos setComment $nouveau
    ::moderne::sansRelance {updateBoard -pgn}
  }
  destroy $w
  catch {focus .main}
}

################################################################################
### Keyboard symbols (Ctrl+1 … Ctrl+6, Ctrl+0)
################################################################################

proc ::moderne::commentaire::symbole {nag} {
  if {[sc_game info previousMove] eq {}} { return }
  if {$nag eq {}} {
    sc_game undoPoint
    sc_pos clearNags
    ::moderne::sansRelance {updateBoard -pgn}
    return
  }
  basculerNag $nag
}

################################################################################
### Symbol menus ("!" or "?": move; "=": evaluation; right-click
### on a move in the PGN: both)
################################################################################

proc ::moderne::commentaire::listeSymboles {genre} {
  if {$genre eq "coup"} {
    return [list ! [T "bon coup" "good move"] ? [T "mauvais coup" "mistake"] \
        !! [T "excellent coup" "brilliant move"] ?? [T "gaffe" "blunder"] \
        !? [T "coup intéressant" "interesting move"] ?! [T "coup douteux" "dubious move"]]
  }
  return [list +- [T "les Blancs gagnent" "White is winning"] +/- [T "net avantage blanc" "White is clearly better"] \
      += [T "léger avantage blanc" "White is slightly better"] = [T "égalité" "equal"] \
      ~ [T "position peu claire" "unclear"] =+ [T "léger avantage noir" "Black is slightly better"] \
      -/+ [T "net avantage noir" "Black is clearly better"] -+ [T "les Noirs gagnent" "Black is winning"] \
      N [T "nouveauté" "novelty"]]
}

### Fills menu m with the symbols of one kind (move / eval)
proc ::moderne::commentaire::remplirSymboles {m genre} {
  variable nags
  majNags
  set i 1
  foreach {nag aide} [listeSymboles $genre] {
    set aff [dict get {! ! ? ? !! !! ?? ?? !? !? ?! ?! +- +- +/- ± += += = = ~ ∞ =+ =+ -/+ ∓ -+ -+ N N} $nag]
    $m add checkbutton -label "$aff   $aide" -variable ::moderne::commentaire::nags($nag) \
        -command [list ::moderne::commentaire::basculerNag $nag]
    incr i
  }
}

### Menu shown from the keyboard ("!", "?", "=") next to the move: in the
### notation if it is shown, else next to the square the move went to.
### Clicking a symbol that is set again removes it.
### (a panel of Siby's, not a menu: on Windows the keyboard went to the
### title line of a native menu, disabled or not; here the title is only
### text and the arrows start on the first symbol, Yosha 2026-11-06)
proc ::moderne::commentaire::menuSymboles {genre} {
  if {[sc_game info previousMove] eq {}} { return }
  variable nags
  variable popChoix
  variable popSymboles {}
  variable popFocus
  majNags
  set w .symbolesPop
  # (the focus goes back where it was when the menu closes: on Windows it
  # fell on ".", Yosha 2026-11-18: a move back then went two moves back)
  set f [focus]
  if {$f ne {} && ![string match .symbolesPop* $f]} { set popFocus $f }
  catch {destroy $w}
  toplevel $w -background [::moderne::c trait] -borderwidth 0
  wm withdraw $w
  wm overrideredirect $w 1
  catch {wm attributes $w -topmost 1}
  set f [frame $w.f -background [::moderne::c surface2] -padx 0 -pady 4]
  pack $f -padx 1 -pady 1
  label $f.t -text "[T "Symbole pour" "Symbol for"] [nomCoup]" -font font_Small -anchor w \
      -background [::moderne::c surface2] -foreground [::moderne::c texteDoux] -padx 12 -pady 3
  grid $f.t -row 0 -column 0 -columnspan 3 -sticky we
  set i 0
  foreach {nag aide} [listeSymboles $genre] {
    set aff [dict get {! ! ? ? !! !! ?? ?? !? !? ?! ?! +- +- +/- ± += += = = ~ ∞ =+ =+ -/+ ∓ -+ -+ N N} $nag]
    set coche [expr {[info exists nags($nag)] && $nags($nag) ? "✓" : " "}]
    foreach {c texte police} [list c $coche font_Regular s $aff font_Bold a $aide font_Regular] {
      label $f.$c$i -text $texte -font $police -anchor w -background [::moderne::c surface2] \
          -foreground [::moderne::c texte] -padx [expr {$c eq "a" ? 12 : 6}] -pady 2
      bind $f.$c$i <Enter> [list ::moderne::commentaire::popSur $i]
      bind $f.$c$i <ButtonRelease-1> [list ::moderne::commentaire::popValider $i]
    }
    grid $f.c$i $f.s$i $f.a$i -row [expr {$i + 1}] -sticky we
    lappend popSymboles $nag
    incr i
  }
  grid columnconfigure $f 2 -weight 1
  bind $w <Up> {::moderne::commentaire::popPas -1}
  bind $w <Down> {::moderne::commentaire::popPas 1}
  bind $w <Return> {::moderne::commentaire::popValider $::moderne::commentaire::popChoix}
  bind $w <KP_Enter> {::moderne::commentaire::popValider $::moderne::commentaire::popChoix}
  bind $w <space> {::moderne::commentaire::popValider $::moderne::commentaire::popChoix}
  bind $w <Escape> ::moderne::commentaire::fermerSymboles
  # (a click outside: closed)
  bind $w <ButtonPress> {
    if {[winfo containing %X %Y] eq {} || ![string match .symbolesPop* [winfo containing %X %Y]]} { ::moderne::commentaire::fermerSymboles }
  }
  set popChoix 0
  popSur 0
  update idletasks
  lassign [placeMenu] x y
  set x [expr {max(0, min($x, [winfo screenwidth $w] - [winfo reqwidth $w]))}]
  set y [expr {max(0, min($y, [winfo screenheight $w] - [winfo reqheight $w]))}]
  wm geometry $w +$x+$y
  wm deiconify $w
  raise $w
  focus -force $w
  catch {grab $w}
}

### The highlighted row of the symbols' panel
proc ::moderne::commentaire::popSur {i} {
  variable popChoix $i
  set f .symbolesPop.f
  set n 0
  while {[winfo exists $f.s$n]} {
    set fond [::moderne::c [expr {$n == $i ? "survol" : "surface2"}]]
    foreach c {c s a} { $f.$c$n configure -background $fond }
    incr n
  }
}
proc ::moderne::commentaire::popPas {d} {
  variable popChoix
  variable popSymboles
  set n [llength $popSymboles]
  if {$n} { popSur [expr {($popChoix + $d + $n) % $n}] }
}
proc ::moderne::commentaire::popValider {i} {
  variable popSymboles
  set nag [lindex $popSymboles $i]
  fermerSymboles
  if {$nag ne {}} { basculerNag $nag }
}
proc ::moderne::commentaire::fermerSymboles {} {
  variable popFocus
  catch {grab release .symbolesPop}
  catch {destroy .symbolesPop}
  set f .main.board
  if {[info exists popFocus] && [winfo exists $popFocus]} { set f $popFocus }
  catch {focus -force $f}
  # (again once the window manager has given the focus back to a window)
  after 80 [list catch [list focus -force $f]]
}

### Screen point next to the current move: below it in the notation, else
### beside the square it went to on the board
proc ::moderne::commentaire::placeMenu {} {
  set t .pgnWin.text
  if {[winfo exists $t] && [winfo ismapped $t]} {
    set r [$t tag ranges Current]
    if {[llength $r]} {
      set b [$t bbox [lindex $r 0]]
      if {[llength $b]} {
        lassign $b x y l h
        return [list [expr {[winfo rootx $t] + $x}] [expr {[winfo rooty $t] + $y + $h + 2}]]
      }
    }
  }
  set c .main.board.bd
  set sq -1
  catch {
    set u [sc_game info previousMoveUCI]
    set sq [expr {([string index $u 3] - 1) * 8 + [string first [string index $u 2] abcdefgh]}]
  }
  if {$sq >= 0 && [llength [set co [$c coords sq$sq]]]} {
    lassign $co x0 y0 x1 y1
    return [list [expr {[winfo rootx $c] + int($x1) + 4}] [expr {[winfo rooty $c] + int($y0)}]]
  }
  return [list [expr {[winfo rootx .main.board] + [winfo width .main.board] / 3}] \
      [expr {[winfo rooty .main.board] + [winfo height .main.board] / 3}]]
}

### Right-click menu of the notation: ::moderne::menuclic::notation
proc ::moderne::commentaire::menuPgn {win} {
  # (one menu: the notation's, in menuclic.tcl, which has these entries)
  ::moderne::menuclic::notation $win
}

### Removes from the whole game (variations included) the move symbols
### ($1-$9), the evaluations ($10-$21, novelty) or the arrows and squares
### ([%cal], [%csl], [%draw]); the game is read again from its PGN text,
### the comments' text left alone
proc ::moderne::commentaire::nettoyer {quoi} {
  set loc [sc_pos pgnOffset]
  set pgn [::moderne::pgnAnglais -width 99999]
  set res {}
  # comments ({…}) and the rest, each changed on its own
  foreach {- com hors} [regexp -all -inline {(\{[^\}]*\})|([^\{]+)} $pgn] {
    if {$com ne {}} {
      if {$quoi eq "marques"} {
        regsub -all {\s*\[%(cal|csl|draw)\s[^\]]*\]} $com {} com
        if {[regexp {^\{\s*\}$} $com]} { set com {} }
      }
      if {$quoi eq "citations" && [estCitation [string range $com 1 end-1]]} { set com {} }
      # (the text only: arrows, squares, move times and evaluations
      # kept, Yosha 2026-11-17)
      if {$quoi eq "texte"} {
        set cmds [regexp -all -inline {\[%[^\]]*\]} $com]
        set com [expr {[llength $cmds] ? "\{[join $cmds { }]\}" : {}}]
      }
      if {$quoi eq "temps"} {
        regsub -all {\s*\[%(clk|emt)\s[^\]]*\]} $com {} com
        if {[regexp {^\{\s*\}$} $com]} { set com {} }
      }
      append res $com
    } else {
      switch -- $quoi {
        symboles    { regsub -all {\$[1-9](?![0-9])} $hors {} hors }
        evaluations { regsub -all {\$(1[0-9]|2[01]|146)(?![0-9])} $hors {} hors }
      }
      append res $hors
    }
  }
  if {$res eq $pgn} { return }
  sc_game undoPoint
  if {[catch {sc_game import $res} err]} {
    tk_messageBox -icon warning -type ok -title Siby -message $err
    return
  }
  catch {sc_move pgn $loc}
  updateBoard -pgn
}

### Is comment c the quotation of a merged game? sc_game merge writes
### "White vs. Black, year" after the variation's last move (since
### 2026-11-05); before, "White -- Black 1-0 (40 moves)" then "Event,
### year" at its start
proc ::moderne::commentaire::estCitation {c} {
  expr {[regexp {^\s*[^\n]+ vs\. [^\n]+, ([0-9]{3,4}|\?)\s*$} $c]
        || [regexp {^\s*[^\n]+ -- [^\n]+ (1-0|0-1|1/2-1/2|\*)( \([0-9]+ [^)]*\))?\s*\n[^\n]*, [0-9?]+\s*$} $c]}
}

### Quotation of the variation the current move is in, after its last
### move or (older form) at its start: {comment end|start}, empty if none
proc ::moderne::commentaire::citationLieu {} {
  if {[sc_var level] == 0} { return {} }
  set r {}
  sc_game push copy
  catch {
    while {![sc_pos isAt vend]} { sc_move forward }
    set c [sc_pos getComment]
    if {[estCitation $c]} { set r [list $c end] }
    if {$r eq {}} {
      while {![sc_pos isAt vstart]} { sc_move back }
      set c [sc_pos getComment]
      if {[estCitation $c]} { set r [list $c start] }
    }
  }
  sc_game pop
  return $r
}

proc ::moderne::commentaire::citationVariante {} {
  return [lindex [citationLieu] 0]
}

proc ::moderne::commentaire::supprimerCitation {} {
  set lieu [lindex [citationLieu] 1]
  if {$lieu eq {}} { return }
  set loc [sc_pos pgnOffset]
  sc_game undoPoint
  catch {
    if {$lieu eq "end"} {
      while {![sc_pos isAt vend]} { sc_move forward }
    } else {
      while {![sc_pos isAt vstart]} { sc_move back }
    }
    if {[estCitation [sc_pos getComment]]} { sc_pos setComment {} }
  }
  catch {sc_move pgn $loc}
  updateBoard -pgn
}

### Small ring in the four colors of the arrows (green, red, blue, yellow),
### like ChessBase's sign for a move with graphics; size from the text.
### Smoothed: each pixel mixes the ring and the background (fond) by how
### much of it the ring covers (4 x 4 samples).
proc ::moderne::commentaire::anneau {hauteur fond} {
  set d [expr {max(10, int($hauteur * 0.7))}]
  set img anneauMarques$d[string map {# _} $fond]
  if {[lsearch -exact [image names] $img] >= 0} { return $img }
  lassign [winfo rgb . $fond] fr fg fb
  set fr [expr {$fr / 257}] ; set fg [expr {$fg / 257}] ; set fb [expr {$fb / 257}]
  set couleurs {{21 120 27} {136 32 32} {0 48 136} {230 143 0}}
  set c [expr {$d / 2.0}]
  set r1 [expr {$d / 2.0 - 0.3}]
  set r0 [expr {$r1 - max(2.2, $d / 4.2)}]
  set pi 3.14159265
  image create photo $img -width $d -height $d
  for {set y 0} {$y < $d} {incr y} {
    set ligne {}
    for {set x 0} {$x < $d} {incr x} {
      set n 0 ; set sr 0 ; set sg 0 ; set sb 0
      foreach oy {0.125 0.375 0.625 0.875} {
        foreach ox {0.125 0.375 0.625 0.875} {
          set dx [expr {$x + $ox - $c}] ; set dy [expr {$y + $oy - $c}]
          set r [expr {hypot($dx, $dy)}]
          if {$r > $r1 || $r < $r0} { continue }
          set q [expr {int(floor((atan2(-$dy, $dx) + $pi) / ($pi / 2))) % 4}]
          lassign [lindex $couleurs $q] cr cg cb
          incr n ; set sr [expr {$sr + $cr}] ; set sg [expr {$sg + $cg}] ; set sb [expr {$sb + $cb}]
        }
      }
      set k [expr {$n / 16.0}]
      if {$n} { set sr [expr {$sr / $n}] ; set sg [expr {$sg / $n}] ; set sb [expr {$sb / $n}] }
      lappend ligne [format #%02x%02x%02x [expr {int($k * $sr + (1 - $k) * $fr)}] \
          [expr {int($k * $sg + (1 - $k) * $fg)}] [expr {int($k * $sb + (1 - $k) * $fb)}]]
    }
    $img put [list $ligne] -to 0 $y
  }
  return $img
}

### A small sign after each move that carries arrows or squares (as in
### ChessBase); the marks themselves are not shown in the notation
proc ::moderne::commentaire::signesMarques {t} {
  set moves {}
  foreach tag [$t tag names] {
    if {[regexp {^m_([0-9]+)$} $tag -> n] && $n > 0} { lappend moves $n }
  }
  if {![llength $moves]} { return }
  set avec {}
  # (a full copy: "copyfast" leaves the comments out)
  sc_game push copy
  foreach n $moves {
    if {[catch {sc_move pgn $n}]} { continue }
    if {[regexp {\[%(cal|csl|draw)\s} [sc_pos getComment]]} { lappend avec $n }
  }
  sc_game pop
  if {![llength $avec]} { return }
  set etat [$t cget -state]
  $t configure -state normal
  $t tag configure signeMarque -foreground [::moderne::c accent] -font font_Small
  # (from the end: the earlier positions stay valid)
  set fins {}
  foreach n $avec {
    set r [$t tag ranges m_$n]
    if {![llength $r]} { continue }
    # after the move's symbols (!, +=…) if it has some
    set fin [lindex $r end]
    while {[llength [set g [$t tag nextrange nag $fin "$fin + 2 chars"]]]} { set fin [lindex $g 1] }
    lappend fins $fin
  }
  set img [anneau [font metrics font_Regular -linespace] [$t cget -background]]
  foreach i [lsort -dictionary -decreasing $fins] {
    $t image create $i -image $img -padx 3 -align center
  }
  $t configure -state $etat
}

### Submenus added to a move's context menu (PGN window)
proc ::moderne::commentaire::ajouterMenuPgn {m} {
  if {![::moderne::actif] || [sc_game info previousMove] eq {}} { return }
  $m add separator
  foreach {genre fr en} {coup "Symbole du coup" "Move symbol" eval "Évaluation" "Evaluation"} {
    catch {destroy $m.$genre}
    menu $m.$genre -tearoff 0
    remplirSymboles $m.$genre $genre
    $m add cascade -label [T $fr $en] -menu $m.$genre
  }
  $m add command -label [T "Commentaire après ce coup… (Ctrl+A)" "Comment after this move… (Ctrl+A)"] \
      -command ::moderne::commentaire::ouvrir
}

################################################################################
### Squares and arrows with the mouse (Alt+click, Alt+drag)
################################################################################

proc ::moderne::commentaire::couleurDe {etat} {
  # %s: 1 = Shift, 4 = Ctrl
  if {$etat & 1} { return R }
  if {$etat & 4} { return Y }
  return G
}

proc ::moderne::commentaire::appui {x y etat} {
  variable depart
  variable couleur
  set depart [::board::getSquare .main.board $x $y]
  set couleur [couleurDe $etat]
  return -code break
}

proc ::moderne::commentaire::relache {x y} {
  variable depart
  variable couleur
  set arrivee [::board::getSquare .main.board $x $y]
  set de $depart
  set depart -1
  if {$de < 0 || $arrivee < 0} { return -code break }
  set noms [list [::board::san $de] [::board::san $arrivee]]
  if {$de == $arrivee} {
    marquer csl $couleur[lindex $noms 0]
  } else {
    marquer cal $couleur[lindex $noms 0][lindex $noms 1]
  }
  return -code break
}

### Adds (or removes if already there) a mark in the move's comment:
### type csl (square) or cal (arrow), mark "Ge4" / "Re2e4"
proc ::moderne::commentaire::marquer {type marque} {
  set com [sc_pos getComment]
  set liste {}
  # Existing marks of this type (one or more [%csl …] blocks)
  foreach {bloc contenu} [regexp -all -inline "\\\[%$type\\s+(\[^\\\]\]*)\\\]" $com] {
    foreach m [split $contenu ,] {
      set m [string trim $m]
      if {$m ne {}} { lappend liste $m }
    }
  }
  regsub -all "\\s*\\\[%$type\\s+\[^\\\]\]*\\\]" $com { } com
  regsub -all {  +} $com { } com
  regsub -all {\] \[%} $com {][%} com
  set lieu [string range $marque 1 end]
  set dejaMeme [expr {[lsearch -exact $liste $marque] >= 0}]
  set nouvelle {}
  foreach m $liste {
    if {[string range $m 1 end] ne $lieu} { lappend nouvelle $m }
  }
  if {!$dejaMeme} { lappend nouvelle $marque }
  set com [string trim $com]
  if {[llength $nouvelle]} {
    if {$com ne {} && ![string match {*\]} $com]} { append com " " }
    append com "\[%$type [join $nouvelle ,]\]"
  }
  sc_game undoPoint
  sc_pos setComment [string trim $com]
  updateBoard -pgn
}

################################################################################
### Installation
################################################################################

### Does the shortcut apply here? Not in an entry field nor in a
### dialog window (comment being written…)
proc ::moderne::commentaire::raccourci {W} {
  if {![winfo exists $W]} { return 0 }
  set c [winfo class $W]
  if {$c in {Entry TEntry TCombobox Spinbox TSpinbox Listbox}} { return 0 }
  if {$c eq "Text" && [$W cget -state] eq "normal"} { return 0 }
  # only in the main window and its panels, not in a dialog
  set top [winfo toplevel $W]
  if {$top in {. .main}} { return 1 }
  if {[winfo exists .fdock[string range $top 1 end]]} { return 1 }
  foreach motif {.pgnWin .biblioWin .prepaWin .glistWin .analysisWin* .treeWin*} {
    if {[string match $motif $top]} { return 1 }
  }
  return 0
}

proc ::moderne::commentaire::installer {} {
  if {![::moderne::actif] || ![winfo exists .main.board.bd]} { return }
  # Ctrl+A: comment (as in ChessBase; SCID used it for "add a
  # variation", which stays on its button)
  # SCID shortcuts replaced: Ctrl+A (add a variation) and the
  # "! Enter", "= Enter"… sequences (they got mixed up with the menus)
  bind .main <Control-a> {}
  foreach seq [bind .main] {
    if {[regexp {^<(exclam|question|equal|plus|minus|asciitilde)>} $seq]} { bind .main $seq {} }
  }
  # (everywhere in Siby: board, notation, opening library, engines… except
  # in a field where text is typed)
  bind all <Control-a> {+if {[::moderne::commentaire::raccourci %W]} {::moderne::commentaire::ouvrir}}
  foreach {k nag} {1 ! 2 ? 3 !! 4 ?? 5 !? 6 ?! 0 {}} {
    bind all <Control-Key-$k> [list +if {[::moderne::commentaire::raccourci %W]} [list ::moderne::commentaire::symbole $nag]]
  }
  # "!" or "?": move symbol menu; "=": evaluation menu
  bind all <exclam> {+if {[::moderne::commentaire::raccourci %W]} {::moderne::commentaire::menuSymboles coup}}
  bind all <question> {+if {[::moderne::commentaire::raccourci %W]} {::moderne::commentaire::menuSymboles coup}}
  bind all <equal> {+if {[::moderne::commentaire::raccourci %W]} {::moderne::commentaire::menuSymboles eval}}
  set bd .main.board.bd
  foreach m {Alt Alt-Shift Alt-Control} {
    bind $bd <$m-ButtonPress-1> {::moderne::commentaire::appui %x %y %s}
    bind $bd <$m-ButtonRelease-1> {::moderne::commentaire::relache %x %y}
    for {set i 0} {$i < 64} {incr i} {
      $bd bind p$i <$m-ButtonPress-1> {::moderne::commentaire::appui %x %y %s}
    }
  }
}

after idle ::moderne::commentaire::installer

### End Siby

### Runs script (a board update) without the engines starting their search
### again: the position did not change (a symbol, a comment)
proc ::moderne::sansRelance {script} {
  set ::moderne::memePosition 1
  set code [catch {uplevel 1 $script} r]
  set ::moderne::memePosition 0
  return -code $code $r
}
