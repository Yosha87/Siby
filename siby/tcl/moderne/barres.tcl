
###
### Siby: evaluation bars for engines 1 and 2
###
### Left bar = the engine of the left panel, right bar = the right one
### (whatever its F2, F3… shortcut). Each
### bar has two displays:
###   - wdl       : White / gray / Black = win / draw / loss, from
###                 White's point of view;
###   - classique : White / Black, filled according to White's expected score,
###                 without a number (it is in the engine window).
### Location: next to the board (default) or in each engine's window,
### never both.
### Without engine 1, the left bar shows the evaluation recorded in the game
### ([%eval] / [%wdl] of the current move) when there is one.
### These bars replace SCID's original bar.
###

namespace eval ::moderne::barres {
  # Saved settings (defaults in start.tcl, before options.dat)
  variable actif               ;# bars shown
  variable mode                ;# mode(g), mode(d): classique | wdl
  variable place               ;# plateau (next to the board) | moteur (in its window)
  variable ordre {}            ;# engines in the order they were started
  variable valeurs             ;# valeurs(n) = {cp mat wdl} of engine n
  array set valeurs {}
  variable dernier             ;# last drawing of each bar (avoids needless redrawing)
  array set dernier {}
  variable installe 0
}

proc ::moderne::barres::T {fr en} { return [::moderne::tr $fr $en] }

### White's expected score (0–100) from centipawns (Lichess formula)
proc ::moderne::barres::chances {cp} {
  if {$cp > 2000} { set cp 2000 } elseif {$cp < -2000} { set cp -2000 }
  return [expr {50.0 + 50.0 * (2.0 / (1.0 + exp(-0.00368208 * $cp)) - 1.0)}]
}

################################################################################
### Installation on the main board
################################################################################

proc ::moderne::barres::installer {} {
  variable installe
  variable actif
  set w .main.board
  if {![winfo exists $w]} { return }
  foreach c {g d} {
    if {![winfo exists $w.barre$c]} {
      canvas $w.barre$c -highlightthickness 0 -borderwidth 0 -width 18 -height 100
      bind $w.barre$c <ButtonPress-3> [list ::moderne::barres::menuContextuel $c %X %Y]
      if {$::macOS} { bind $w.barre$c <ButtonPress-2> [list ::moderne::barres::menuContextuel $c %X %Y] }
      bind $w.barre$c <Enter> [list ::moderne::barres::bulle $c]
    }
  }
  if {!$installe} {
    set installe 1
    bind $w.bd <Configure> {+::moderne::barres::redessiner}
    # SCID's original bar and our bars: one or the others
    trace add variable ::gameInfo(showEval) write ::moderne::barres::barreOrigine
  }
  afficher
}

### Shows or hides the bars according to the setting
proc ::moderne::barres::afficher {} {
  variable actif
  set w .main.board
  if {![winfo exists $w.barreg]} { return }
  # Bars in the engine windows: updated at the next analysis
  foreach f [winfo children .] {
    if {[regexp {^\.analysisWin([0-9]+)$} $f -> n]} { catch {::moderne::wdl::mettreAJour $n} }
  }
  if {$actif && $::moderne::barres::place eq "plateau"} {
    # The original bar takes the same place on the right: remove it
    if {$::gameInfo(showEval)} {
      set ::gameInfo(showEval) 0
      catch {::board::toggleeval}
    }
    grid $w.barreg -row 1 -column 1 -rowspan 8 -padx {0 4} -sticky ns
    grid $w.barred -row 1 -column 12 -rowspan 8 -padx 4 -sticky ns
    redessiner
  } else {
    catch {grid remove $w.barreg}
    catch {grid remove $w.barred}
  }
}

proc ::moderne::barres::basculer {} { afficher }

### SCID's original bar is re-enabled: hide ours
proc ::moderne::barres::barreOrigine {args} {
  variable actif
  if {[info exists ::gameInfo(showEval)] && $::gameInfo(showEval) && $actif} {
    set actif 0
    afficher
  }
}

################################################################################
### Data
################################################################################

### Called by updateAnalysisText (tcl/tools/analysis.tcl) on each update
### of engine n
proc ::moderne::barres::moteur {n} {
  variable valeurs
  variable actif
  variable ordre
  if {[lsearch -exact $ordre $n] < 0} {
    lappend ordre $n
    catch {bind .analysisWin$n <Destroy> "+::moderne::barres::fermeture %W .analysisWin$n $n"}
  }
  if {![info exists ::analysis(score$n)]} { return }
  set mat 0
  if {[info exists ::analysis(scoremate$n)] && [string is integer -strict $::analysis(scoremate$n)]} {
    set mat $::analysis(scoremate$n)
  }
  set wdl {}
  if {[info exists ::analysis(seenWDL$n)] && $::analysis(seenWDL$n) && [info exists ::analysis(WDLval$n,0)]} {
    set wdl $::analysis(WDLval$n,0)
  }
  set valeurs($n) [list $::analysis(score$n) $mat $wdl]
  if {$actif} { redessiner }
}

### Values supplied directly by an engine (Toby: "toby position"):
### {cp mat wdl}, or {} to clear its bar
proc ::moderne::barres::valeursExternes {n v} {
  variable valeurs
  variable actif
  variable ordre
  if {[lsearch -exact $ordre $n] < 0} {
    lappend ordre $n
    catch {bind .analysisWin$n <Destroy> "+::moderne::barres::fermeture %W .analysisWin$n $n"}
  }
  if {$v eq {}} {
    catch {unset valeurs($n)}
  } else {
    set valeurs($n) $v
  }
  if {$actif} { redessiner }
}

proc ::moderne::barres::fermeture {fenetre attendue n} {
  if {$fenetre ne $attendue} { return }
  variable valeurs
  variable ordre
  catch {unset valeurs($n)}
  set i [lsearch -exact $ordre $n]
  if {$i >= 0} { set ordre [lreplace $ordre $i $i] }
  after idle ::moderne::barres::redessiner
}

### Open engines, in the order they were started
proc ::moderne::barres::moteurs {} {
  variable ordre
  set res {}
  set i 0
  # (engines open but without data yet come after the others)
  set tous $ordre
  foreach f [lsort [winfo children .]] {
    if {[regexp {^\.analysisWin([0-9]+)$} $f -> k] && $k ni $tous} { lappend tous $k }
  }
  foreach n $tous {
    if {![winfo exists .analysisWin$n]} { continue }
    # Siby: in screen order (the left engine first), then
    # in start order (engines in tabs, windows not shown)
    set x 1e9
    catch {
      set f .fdockanalysisWin$n
      if {![winfo exists $f]} { set f .analysisWin$n }
      if {[winfo ismapped $f]} { set x [winfo rootx $f] }
    }
    lappend res [list $n $x [incr i]]
  }
  # (the paused engines' places count for the side: Toby alone started in
  # the right panel gets the right bar, 2026-10-29; "p" + number, no data)
  foreach p [winfo children .] {
    if {![regexp {^\.fdockattenteanalysisWin([0-9]+)$} $p -> k] || [winfo exists .analysisWin$k]} { continue }
    if {![winfo ismapped $p]} { continue }
    lappend res [list p$k [winfo rootx $p] [incr i]]
  }
  set res [lsort -real -index 1 [lsort -integer -index 2 $res]]
  return [lmap e $res {lindex $e 0}]
}

### Engine shown by bar c: the left panel's on the left, the right one's on
### the right (a paused panel keeps its side, its bar stays empty); {} if
### there is none
proc ::moderne::barres::moteurDe {c} {
  set n [lindex [moteurs] [expr {$c eq "g" ? 0 : 1}]]
  if {[string index $n 0] eq "p"} { return {} }
  return $n
}

### Bar (g or d) of engine n ({} if it is neither the first nor the second)
proc ::moderne::barres::coteDe {n} {
  set i [lsearch -exact [moteurs] $n]
  if {$i == 0} { return g }
  if {$i == 1} { return d }
  return {}
}

### During a game against Toby (bars shown): evaluation of the position
### from the second Toby ({cp mat wdl}, White's point of view), or {}
namespace eval ::moderne::barres { variable partie {} }
proc ::moderne::barres::valeurPartie {v} {
  variable partie $v
  variable actif
  if {$actif} { redessiner }
}

### Values {cp mat wdl source} to display for bar c, or {}
proc ::moderne::barres::donnees {c} {
  variable valeurs
  variable partie
  set n [moteurDe $c]
  if {$c eq "g" && $n eq {} && $partie ne {} && [winfo exists .serGameWin]} {
    return [concat $partie [list moteur]]
  }
  if {$n ne {} && [info exists valeurs($n)]} {
    return [concat $valeurs($n) [list moteur]]
  }
  if {$c ne "g" || $n ne {}} { return {} }
  # Without an engine, on the left: evaluation recorded in the game
  set cp {}
  set wdl {}
  catch {set cp [sc_pos getScore]}
  catch {
    set com [sc_pos getComment]
    if {[regexp {\[%wdl\s+([0-9.]+),([0-9.]+),([0-9.]+)\]} $com -> a b d]} {
      set s [expr {double($a) + $b + $d}]
      if {$s > 0} {
        # (per mille or percent depending on the program that annotated)
        set k [expr {100.0 / $s}]
        set wdl [list [expr {round($a * $k)}] [expr {round($b * $k)}] [expr {round($d * $k)}]]
      }
    }
  }
  if {![string is double -strict $cp] && $wdl eq {}} { return {} }
  if {![string is double -strict $cp]} { set cp {} }
  return [list $cp 0 $wdl partie]
}

################################################################################
### Drawing
################################################################################

proc ::moderne::barres::redessiner {} {
  variable actif
  if {!$actif} { return }
  foreach c {g d} { dessiner $c }
}

proc ::moderne::barres::couleurs {} {
  # white, gray (draw), black, text on white, text on black, frame
  return {#ececec #9a9a9a #403d39 #2b2926 #f2f2f2 {}}
}

proc ::moderne::barres::dessiner {c} {
  variable mode
  variable dernier
  set w .main.board
  set cv $w.barre$c
  if {![winfo exists $cv]} { return }
  set taille $::board::_size($w)
  variable style
  set fine 0
  set larg [expr {max(24, int($taille * 0.36))}]
  set haut [winfo height $w.bd]
  if {$haut < 20} { set haut [expr {$taille * 8}] }
  set retourne [::board::isFlipped $w]
  set d [donnees $c]
  # Game against an engine in progress: bars hidden, unless the option is set
  if {[winfo exists .serGameWin] && !$::moderne::barres::enPartie} { set d {} }
  set cle [list $larg $haut $retourne $mode($c) $d $style]
  if {[info exists dernier($c)] && $dernier($c) eq $cle && [llength [$cv find all]]} { return }
  set dernier($c) $cle
  $cv configure -width $larg -height $haut
  $cv delete all
  lassign [couleurs] blanc gris noir txtB txtN cadre
  if {$d eq {}} {
    variable cible
    variable vu
    variable apres
    catch {after cancel $apres($c)}
    catch {unset cible($c)}
    catch {unset vu($c)}
    return
  }
  lassign $d cp mat wdl orig
  # An engine other than Toby: its centipawns through the Lichess formula,
  # as on Lichess. Its own W/D/L is the engine against itself (Stockfish:
  # +1.2 drawn white, Yosha 2026-10-31); Toby's is at the players' level,
  # kept.
  set n [moteurDe $c]
  set toby 0
  if {$n ne {}} { catch {set toby [::moderne::toby::estToby $n]} }
  if {$orig eq "moteur" && !$toby && [string is double -strict $cp]} { set wdl {} }
  # Shares of White, draw and Black (in %)
  set troisCouleurs [expr {$mode($c) eq "wdl" && [llength $wdl] == 3}]
  if {$mat != 0} {
    set pB [expr {$mat > 0 ? 100.0 : 0.0}]
    set pN [expr {100.0 - $pB}]
    set pD 0.0
    set troisCouleurs 0
  } elseif {[llength $wdl] == 3} {
    lassign $wdl g n p
    if {$troisCouleurs} {
      set pB [expr {double($g)}] ; set pD [expr {double($n)}] ; set pN [expr {double($p)}]
    } else {
      set pB [expr {$g + $n / 2.0}] ; set pD 0.0 ; set pN [expr {100.0 - $pB}]
    }
  } elseif {[string is double -strict $cp]} {
    set pB [chances [expr {$cp * 100.0}]] ; set pD 0.0 ; set pN [expr {100.0 - $pB}]
  } else {
    return
  }
  # The bar glides to its new value (like Lichess): changes of an
  # engine that is still searching no longer make it jump
  variable cible
  variable vu
  variable ctx
  set cible($c) [list $pB $pD]
  set ctx($c) [list $larg $haut $retourne $troisCouleurs $wdl $fine]
  if {![info exists vu($c)]} { set vu($c) [list 50.0 0.0] }
  animer $c
}

### One step of the glide of bar c toward its target (time-based easing)
proc ::moderne::barres::animer {c} {
  variable cible
  variable vu
  variable apres
  variable tAnim
  catch {after cancel $apres($c)}
  if {![info exists cible($c)]} { return }
  set maintenant [clock milliseconds]
  set dt [expr {[info exists tAnim($c)] ? min(100, $maintenant - $tAnim($c)) : 16}]
  set tAnim($c) $maintenant
  lassign $vu($c) b d
  lassign $cible($c) tb td
  # (time constant 250 ms: about 3/4 s to arrive, close to Lichess)
  set k [expr {1.0 - exp(-$dt / 250.0)}]
  set b [expr {$b + ($tb - $b) * $k}]
  set d [expr {$d + ($td - $d) * $k}]
  if {abs($tb - $b) < 0.15 && abs($td - $d) < 0.15} {
    set b $tb ; set d $td
    unset tAnim($c)
  } else {
    set apres($c) [after 16 [list ::moderne::barres::animer $c]]
  }
  set vu($c) [list $b $d]
  tracer $c
}

### Color of the segment under height y
proc ::moderne::barres::couleurA {segs y} {
  foreach s $segs {
    lassign $s y0 y1 coul
    if {$y >= $y0 && $y < $y1 && $y1 - $y0 > 0.5} { return $coul }
  }
  return [lindex $segs end 2]
}

### Color c1 moved toward c2 by share a (0-1)
proc ::moderne::barres::melange {c1 c2 a} {
  variable melanges
  set cle "$c1|$c2|[format %.3f $a]"
  if {[info exists melanges($cle)]} { return $melanges($cle) }
  lassign [winfo rgb . $c1] r1 g1 b1
  lassign [winfo rgb . $c2] r2 g2 b2
  set melanges($cle) [format #%02x%02x%02x [expr {int(($r1 * (1 - $a) + $r2 * $a) / 257)}] \
      [expr {int(($g1 * (1 - $a) + $g2 * $a) / 257)}] [expr {int(($b1 * (1 - $a) + $b2 * $a) / 257)}]]
}

### Inner shadow of the bar (the canvas has no transparency: each edge
### line is the segment color darkened by a fading share)
proc ::moderne::barres::ombre {cv larg haut segs} {
  set n [expr {max(3, min(6, int($larg / 5)))}]
  for {set k 0} {$k < $n} {incr k} {
    set a [expr {0.42 * pow(1.0 - double($k) / $n, 2)}]
    foreach s $segs {
      lassign $s y0 y1 coul
      if {$y1 - $y0 <= 0.5} { continue }
      set f [melange $coul #000000 $a]
      $cv create line $k $y0 $k $y1 -fill $f
      $cv create line [expr {$larg - 1 - $k}] $y0 [expr {$larg - 1 - $k}] $y1 -fill $f
    }
    $cv create line $k $k [expr {$larg - $k}] $k -fill [melange [couleurA $segs $k] #000000 $a]
    set yb [expr {$haut - 1 - $k}]
    $cv create line $k $yb [expr {$larg - $k}] $yb -fill [melange [couleurA $segs $yb] #000000 $a]
  }
}

### Draws bar c at its displayed value
proc ::moderne::barres::tracer {c} {
  variable vu
  variable ctx
  set cv .main.board.barre$c
  if {![winfo exists $cv] || ![info exists ctx($c)]} { return }
  lassign $ctx($c) larg haut retourne troisCouleurs wdl fine
  lassign $vu($c) pB pD
  $cv delete all
  lassign [couleurs] blanc gris noir txtB txtN cadre
  # White is on the side of the board's white pieces
  set hB [expr {$haut * $pB / 100.0}]
  set hD [expr {$haut * $pD / 100.0}]
  if {$retourne} {
    # White at the top
    set segs [list [list 0 $hB $blanc] [list $hB [expr {$hB + $hD}] $gris] [list [expr {$hB + $hD}] $haut $noir]]
  } else {
    set segs [list [list 0 [expr {$haut - $hB - $hD}] $noir] [list [expr {$haut - $hB - $hD}] [expr {$haut - $hB}] $gris] [list [expr {$haut - $hB}] $haut $blanc]]
  }
  foreach s $segs {
    lassign $s y0 y1 coul
    if {$y1 - $y0 > 0.5} {
      $cv create rectangle 0 $y0 $larg $y1 -fill $coul -outline {}
    }
  }
  # As on Lichess: ticks every eighth (etched), then a soft inner shadow
  # along the edges, which gives the light relief; square corners
  if {!$troisCouleurs} {
    for {set k 1} {$k < 8} {incr k} {
      if {$k == 4} { continue }
      set y [expr {round($haut * $k / 8.0)}]
      set fondT [couleurA $segs $y]
      $cv create line 0 [expr {$y - 1}] $larg [expr {$y - 1}] -fill [melange $fondT #000000 0.25]
      $cv create line 0 $y $larg $y -fill [melange $fondT #ffffff 0.12]
    }
  }
  ombre $cv $larg $haut $segs
  set ym [expr {round($haut / 2.0)}]
  if {!$troisCouleurs} { $cv create line 0 $ym $larg $ym -fill #e07b39 -width 2 }
  if {$fine} {
    # Lichess-style gauge: ticks every eighth, orange mark in the
    # middle; the value is shown on hover (tooltip)
    for {set k 1} {$k < 8} {incr k} {
      set y [expr {round($haut * $k / 8.0)}]
      if {$k == 4} {
        $cv create line 0 $y $larg $y -fill #d77a32 -width 2
      } else {
        $cv create line 0 $y $larg $y -fill #7a7a7a -width 1
      }
    }
    return
  }
  # WDL numbers (outside WDL: no number on the gauge, it is in the
  # engine window)
  if {!$troisCouleurs} { return }
  set police [police $larg]
  lassign $wdl g n p
  foreach {val y0 y1 coulTxt} [list \
      $g [lindex $segs [expr {$retourne ? 0 : 2}] 0] [lindex $segs [expr {$retourne ? 0 : 2}] 1] $txtB \
      $n [lindex $segs 1 0] [lindex $segs 1 1] #ffffff \
      $p [lindex $segs [expr {$retourne ? 2 : 0}] 0] [lindex $segs [expr {$retourne ? 2 : 0}] 1] $txtN] {
    if {$y1 - $y0 >= [font metrics $police -linespace] + 2 && [font measure $police $val] < $larg} {
      $cv create text [expr {$larg / 2.0}] [expr {($y0 + $y1) / 2.0}] -text $val -fill $coulTxt -font $police
    }
  }
}

### Horizontal bar in the window of engine n ("moteur" location):
### same display as the engine's bar next to the board
proc ::moderne::barres::horizontale {cv n} {
  variable valeurs
  variable mode
  $cv delete all
  set larg [winfo width $cv]
  if {$larg < 30 || ![info exists valeurs($n)]} { return }
  lassign $valeurs($n) cp mat wdl
  # (an engine other than Toby: centipawns through the Lichess formula,
  # as in dessiner)
  set toby 0
  catch {set toby [::moderne::toby::estToby $n]}
  if {!$toby && [string is double -strict $cp]} { set wdl {} }
  set c [coteDe $n]
  set m [expr {$c ne {} ? $mode($c) : "wdl"}]
  lassign [couleurs] blanc gris noir txtB txtN cadre
  set fond [expr {[::moderne::actif] ? [::moderne::c fond] : [$cv cget -background]}]
  set doux [expr {[::moderne::actif] ? [::moderne::c texteDoux] : "#555555"}]
  $cv configure -background $fond
  set trois [expr {$m eq "wdl" && [llength $wdl] == 3 && $mat == 0}]
  if {$mat != 0} {
    set pB [expr {$mat > 0 ? 100.0 : 0.0}] ; set pD 0.0
  } elseif {$trois} {
    lassign $wdl g nl p ; set pB [expr {double($g)}] ; set pD [expr {double($nl)}]
  } elseif {[llength $wdl] == 3} {
    lassign $wdl g nl p ; set pB [expr {$g + $nl / 2.0}] ; set pD 0.0
  } elseif {[string is double -strict $cp]} {
    set pB [chances [expr {$cp * 100.0}]] ; set pD 0.0
  } else {
    return
  }
  set e 6
  set xB [expr {$larg * $pB / 100.0}]
  set xD [expr {$xB + $larg * $pD / 100.0}]
  if {$xB > 0} { $cv create rectangle 0 0 $xB $e -fill $blanc -outline {} }
  if {$xD > $xB} { $cv create rectangle $xB 0 $xD $e -fill $gris -outline {} }
  if {$xD < $larg} { $cv create rectangle $xD 0 $larg $e -fill $noir -outline {} }
  $cv create rectangle 0 0 [expr {$larg - 1}] [expr {$e - 1}] -outline $cadre
  set y [expr {$e + 3}]
  set police font_Small
  if {$trois} {
    $cv create text 0 $y -anchor nw -font $police -fill $doux -text "1-0  $g %"
    $cv create text [expr {$larg / 2.0}] $y -anchor n -font $police -fill $doux -text "\u00bd  $nl %"
    $cv create text $larg $y -anchor ne -font $police -fill $doux -text "0-1  $p %"
  } else {
    if {[::moderne::moteur::unite $n] eq "score" && $mat == 0} {
      set sB [expr {round($pB)}]
      $cv create text 0 $y -anchor nw -font $police -fill $doux -text "[T Blancs White]  $sB %"
      $cv create text $larg $y -anchor ne -font $police -fill $doux -text "[T Noirs Black]  [expr {100 - $sB}] %"
    } else {
      set texte [etiquette [::moderne::moteur::unite $n] $cp $mat $pB]
      $cv create text [expr {$larg / 2.0}] $y -anchor n -font $police -fill $doux -text $texte
    }
  }
  set h [expr {$y + [font metrics $police -linespace] + 1}]
  if {[$cv cget -height] != $h} { $cv configure -height $h }
}

### Font for the numbers, sized to the bar
### Rounded corners: each corner's outside is covered with the background color
proc ::moderne::barres::coins {cv larg haut r {haute {}} {basse {}}} {
  set fond [$cv cget -background]
  catch {set fond [[winfo parent $cv] cget -background]}
  catch {$cv configure -background $fond}
  # Smoothed corners: images whose pixels blend the bar color and the
  # background by the share of the pixel inside the arc (the canvas
  # draws curves without smoothing on Windows)
  foreach {coin x y ancre coul} [list hg 0 0 nw $haute hd $larg 0 ne $haute \
                                     bg 0 $haut sw $basse bd $larg $haut se $basse] {
    if {$coul eq {}} { continue }
    $cv create image $x $y -anchor $ancre -image [imageCoin $coin $r $coul $fond]
  }
}

### Image of a corner (hg, hd, bg, bd) of radius r: bar color coul inside
### the arc, background fond outside, blended along the edge
proc ::moderne::barres::imageCoin {coin r coul fond} {
  variable imagesCoins
  set cle "$coin|$r|$coul|$fond"
  if {[info exists imagesCoins($cle)]} { return $imagesCoins($cle) }
  lassign [winfo rgb . $coul] r1 g1 b1
  lassign [winfo rgb . $fond] r2 g2 b2
  set n 4   ;# 4 x 4 samples per pixel
  set lignes {}
  for {set py 0} {$py < $r} {incr py} {
    set ligne {}
    for {set px 0} {$px < $r} {incr px} {
      # (distance measured from the arc's center, for the top-left corner)
      set dedans 0
      for {set sy 0} {$sy < $n} {incr sy} {
        for {set sx 0} {$sx < $n} {incr sx} {
          set dx [expr {$r - ($px + ($sx + 0.5) / $n)}]
          set dy [expr {$r - ($py + ($sy + 0.5) / $n)}]
          if {$dx * $dx + $dy * $dy <= $r * $r} { incr dedans }
        }
      }
      set a [expr {double($dedans) / ($n * $n)}]
      lappend ligne [format #%02x%02x%02x \
          [expr {int(($r1 * $a + $r2 * (1 - $a)) / 257)}] \
          [expr {int(($g1 * $a + $g2 * (1 - $a)) / 257)}] \
          [expr {int(($b1 * $a + $b2 * (1 - $a)) / 257)}]]
    }
    lappend lignes $ligne
  }
  # other corners: mirrored
  if {$coin in {hd bd}} { set lignes [lmap l $lignes {lreverse $l}] }
  if {$coin in {bg bd}} { set lignes [lreverse $lignes] }
  set img [image create photo -width $r -height $r]
  $img put $lignes
  set imagesCoins($cle) $img
  return $img
}

proc ::moderne::barres::police {larg} {
  set px [expr {max(10, min(14, int($larg * 0.42)))}]
  if {[lsearch -exact [font names] font_Barres] < 0} {
    font create font_Barres -family [font actual font_Small -family] -size -$px -weight bold
  } elseif {[font configure font_Barres -size] != -$px} {
    font configure font_Barres -size -$px
  }
  return font_Barres
}

### Number shown: unit cp (pawns) or score (expected score in %)
proc ::moderne::barres::etiquette {m cp mat pB} {
  if {$mat != 0} {
    return "#$mat"
  }
  if {$m eq "cp"} {
    if {![string is double -strict $cp]} { return [format %.0f $pB] }
    if {abs($cp) >= 10} { return [format %+.0f $cp] }
    if {[format %.1f $cp] in {0.0 -0.0}} { return 0.0 }
    return [format %+.1f $cp]
  }
  return [format %.0f $pB]
}

### Tooltip (engine shown and values)
proc ::moderne::barres::bulle {c} {
  variable mode
  set cv .main.board.barre$c
  set n [moteurDe $c]
  set d [donnees $c]
  set qui [expr {$c eq "g" ? [T "Premier module" "First engine"] : [T "Deuxième module" "Second engine"]}]
  if {$n ne {}} {
    set nom [lindex $::engines(list) $n 0]
    append qui " : $nom"
  } elseif {$d ne {}} {
    append qui " : [T "évaluation notée dans la partie" "evaluation from the game annotations"]"
  } else {
    append qui " : [T "n'analyse pas" "not running"]"
  }
  if {$d ne {}} {
    lassign $d cp mat wdl
    if {$mat != 0} {
      append qui "\n[T "Mat en" "Mate in"] [expr {abs($mat)}]"
    } elseif {[string is double -strict $cp]} {
      append qui "\n[T "Évaluation" "Evaluation"] : [format %+.2f $cp]"
    }
    if {[llength $wdl] == 3} {
      append qui "\n[T "Gain / nulle / perte (Blancs)" "Win / draw / loss (White)"] : [join $wdl { / }] %"
    }
  }
  append qui "\n[T "Clic droit : affichage" "Right click: display"]"
  catch {::utils::tooltip::Set $cv $qui}
}

################################################################################
### Menus
################################################################################

proc ::moderne::barres::remplirMenu {m c} {
  $m add radiobutton -label [T "Blancs / gris / Noirs : gain, nulle, perte (WDL)" "White / grey / Black: win, draw, loss (WDL)"] \
      -variable ::moderne::barres::mode($c) -value wdl -command ::moderne::barres::afficher
  $m add radiobutton -label [T "Blancs / Noirs : classique (unité de la fenêtre du moteur)" "White / Black: classic (engine window's unit)"] \
      -variable ::moderne::barres::mode($c) -value classique -command ::moderne::barres::afficher
}

proc ::moderne::barres::redessinerTout {} {
  variable dernier
  catch {unset dernier}
  redessiner
}

proc ::moderne::barres::remplirPlace {m} {
  $m add radiobutton -label [T "Barres à côté de l'échiquier" "Bars next to the board"] \
      -variable ::moderne::barres::place -value plateau -command ::moderne::barres::afficher
  $m add radiobutton -label [T "Barres dans la fenêtre de chaque moteur" "Bars in each engine window"] \
      -variable ::moderne::barres::place -value moteur -command ::moderne::barres::afficher
}

proc ::moderne::barres::menuContextuel {c x y} {
  set m .main.board.menuBarre
  catch {destroy $m}
  menu $m -tearoff 0
  $m add command -label [expr {$c eq "g" ? [T "Premier module lancé" "First engine started"] : [T "Deuxième module lancé" "Second engine started"]}] -state disabled
  remplirMenu $m $c
  $m add separator
  remplirPlace $m
  $m add command -label [T "Masquer les barres" "Hide the bars"] \
      -command {set ::moderne::barres::actif 0 ; ::moderne::barres::afficher}
  tk_popup $m $x $y
}

### Options › Evaluation bar submenu (called by menus.tcl)
proc ::moderne::barres::menuOptions {m} {
  $m add separator
  $m add checkbutton -label [T "Barres d'évaluation des modules" "Engine evaluation bars"] \
      -variable ::moderne::barres::actif -command ::moderne::barres::afficher
  foreach {c lib} [list g [T "Premier module (barre de gauche)" "First engine (left bar)"] d [T "Deuxième module (barre de droite)" "Second engine (right bar)"]] {
    $m add cascade -label $lib -menu $m.barre$c
    menu $m.barre$c -tearoff 0
    remplirMenu $m.barre$c $c
  }
  remplirPlace $m
}

proc ::moderne::barres::init {} {
  if {![info exists ::moderne::barres::actif]} { set ::moderne::barres::actif 1 }
  foreach {c v} {g classique d wdl} {
    if {![info exists ::moderne::barres::mode($c)] || $::moderne::barres::mode($c) ni {classique wdl}} {
      # (old score / cp settings → classique)
      set ::moderne::barres::mode($c) [expr {[info exists ::moderne::barres::mode($c)] && $::moderne::barres::mode($c) in {score cp} ? "classique" : $v}]
    }
  }
  if {![info exists ::moderne::barres::place] || $::moderne::barres::place ni {plateau moteur}} {
    set ::moderne::barres::place plateau
  }
  catch {menuOptions .menu.options.evalbar}
  installer
}
after idle ::moderne::barres::init

### End Siby
