
###
### Siby: layout of the analysis window (UCI engines)
###
### Same behavior as Scid vs. PC, different layout:
###  - one row per line: evaluation badge (light if White is better,
###    dark if Black is), win/draw/loss in small print, moves in normal
###    font with move numbers in gray; no more history of every
###    depth;
###  - a single information row (depth, speed, time, hash);
###  - toolbar trimmed to the essentials, the rest in a "⋯" menu.
### "Original look" theme: nothing changes.
###
### Hooks: makeAnalysisWin and updateAnalysisText (tools/analysis.tcl).
###

namespace eval ::moderne::moteur {
  # Evaluation unit per engine (remembered by engine name, options.dat):
  # cp (centipawns) or score (White's expected score, in %)
  variable unites
  if {![info exists unites]} { set unites {} }
  variable choix            ;# choix(n): variable for the buttons of the "⋯" menu
  array set choix {}
  variable cpu              ;# cpu(n): number of CPUs of engine n
  array set cpu {}
  # Last choices per engine (options.dat)
  variable lignesMem
  if {![info exists lignesMem]} { set lignesMem {} }
  variable cpuMem
  if {![info exists cpuMem]} { set cpuMem {} }
  # Node limit per position, by engine name (0 = no limit)
  variable limiteMem
  if {![info exists limiteMem]} { set limiteMem {} }
  variable fini        ;# fini(n): the node limit has been reached
  array set fini {}
}

### Evaluation unit of engine n: cp or score
proc ::moderne::moteur::unite {n} {
  variable unites
  if {$n eq {} || ![info exists ::engines(list)]} { return cp }
  set nom [lindex $::engines(list) $n 0]
  if {[dict exists $unites $nom]} { return [dict get $unites $nom] }
  # Toby: expected score rather than centipawns
  if {[string match -nocase *toby* $nom]} { return score }
  return cp
}

### W/D/L column shown or not: every engine panel redrawn
proc ::moderne::moteur::changerWdl {} {
  foreach f [winfo children .] {
    if {[regexp {^\.analysisWin([0-9]+)$} $f -> n]} {
      catch {unset ::moderne::moteur::posColonnes($n)}
      catch {lignes $n}
      catch {colonnes $n}
    }
  }
}

proc ::moderne::moteur::changerUnite {n} {
  variable unites
  variable choix
  dict set unites [lindex $::engines(list) $n 0] $choix($n)
  catch {lignes $n}
  catch {::moderne::barres::redessiner}
  catch {::moderne::wdl::mettreAJour $n}
}

### White's expected score (%) for a line: the engine's WDL, otherwise
### Lichess's formula from the centipawns
proc ::moderne::moteur::scoreAttendu {n i score mat} {
  if {$mat ne {} && $mat != 0} { return [expr {$mat > 0 ? 100 : 0}] }
  if {[info exists ::analysis(seenWDL$n)] && $::analysis(seenWDL$n) && [info exists ::analysis(WDLval$n,$i)]} {
    lassign $::analysis(WDLval$n,$i) g d p
    if {[string is double -strict $g] && [string is double -strict $d]} { return [expr {round($g + $d / 2.0)}] }
  }
  if {![string is double -strict $score]} { return {} }
  return [expr {round([::moderne::barres::chances [expr {$score * 100.0}]])}]
}

proc ::moderne::moteur::T {fr en} { return [::moderne::tr $fr $en] }

### Dresses up analysis window n (called at the end of makeAnalysisWin)
proc ::moderne::moteur::habiller {n} {
  # (right click on a line: add it, play its first move, copy it)
  catch {::moderne::menuclic::installerMoteur $n}
  if {![::moderne::actif]} { return }
  set w .analysisWin$n
  if {![winfo exists $w.hist.text]} { return }
  set uci [expr {[info exists ::analysis(uci$n)] && $::analysis(uci$n)}]

  # Text of the lines
  set h $w.hist.text
  set sombre [expr {$::moderne::theme ne "clair"}]
  $h configure -font font_Regular -padx 0 -pady 0 -borderwidth 0 \
      -highlightthickness 0 -background [::moderne::c surface] -wrap none -cursor arrow
  $h tag configure ligne -spacing1 5 -spacing3 5
  # Alternating stripes, the suggested move in color, soft evaluation badges
  $h tag configure bande0 -background [::moderne::c surface]
  $h tag configure bande1 -background [expr {$sombre ? "#272a2e" : "#f0f3f6"}]
  $h tag configure num -foreground [::moderne::c texteDoux]
  $h tag configure coup -foreground [::moderne::c texte]
  $h tag configure premier -foreground [::moderne::c texteFort]
  $h tag configure cle -foreground [expr {$sombre ? "#6cc4ff" : "#1565c0"}] -font font_Bold
  $h tag configure wdl -foreground [::moderne::c texteDoux] -font font_Small
  $h tag configure evalB -background #f2f2f2 -foreground #1a1a1a -font font_Bold
  $h tag configure evalN -background #3d4248 -foreground #f2f2f2 -font font_Bold
  if {!$sombre} {
    $h tag configure evalN -background #2b2f33 -foreground #ffffff
    $h tag configure evalB -background #ffffff -foreground #1c1c1c
  }
  $h tag raise evalB
  $h tag raise evalN
  catch {entete $n}
  catch {pack forget $w.hist.xbar}
  # Information row
  if {[winfo exists $w.text]} {
    $w.text configure -font font_Small -foreground [::moderne::c texteDoux] \
        -background [::moderne::c fond] -borderwidth 0 -highlightthickness 0 \
        -padx 10 -pady 3 -height 1
  }
  if {!$uci} { return }

  # Toolbar: the essentials visible, the rest in "⋯"
  set b $w.b
  catch {$b.multipv configure -readonlybackground [::moderne::c champ] \
      -background [::moderne::c champ] -buttonbackground [::moderne::c surface2] \
      -relief flat -borderwidth 0 -highlightthickness 0}
  # Flat toggle buttons; the "active" state is shown by the color
  foreach bt [winfo children $b] {
    if {[winfo class $bt] eq "Checkbutton" && $bt eq "$b.menace"} {
      catch {$bt configure -selectcolor [::moderne::c fond] -background [::moderne::c fond] \
          -activebackground [::moderne::c survol]}
    } elseif {[winfo class $bt] eq "Checkbutton"} {
      catch {$bt configure -relief flat -offrelief flat -overrelief flat -borderwidth 0 \
          -selectcolor [::moderne::c accentFonce] -background [::moderne::c fond] \
          -activebackground [::moderne::c survol] -highlightthickness 0}
    } elseif {[winfo class $bt] eq "Button"} {
      catch {$bt configure -background [::moderne::c fond] -activebackground [::moderne::c survol] \
          -relief flat -overrelief flat -borderwidth 0 -highlightthickness 0}
    }
  }
  catch {$b configure -background [::moderne::c fond]}
  # (adding moves and lines: click or right-click on a move of the lines)
  foreach bouton {move line alllines} { catch {pack forget $b.$bouton} }
  set caches {}
  foreach {bouton fr en} {
    annotatebut "Annoter la partie…"                  "Annotate the game…"
    exclude     "Exclure un coup…"                    "Exclude a move…"
    priority    "Priorité basse"                      "Low priority"
    showinfo    "Ligne d'informations"                "Information line"
    finishGame  "Finir la partie contre le moteur"    "Finish the game against the engine"
    training    "Entraînement"                        "Training"
    help        "Aide"                                "Help"
  } {
    if {![winfo exists $b.$bouton]} { continue }
    catch {pack forget $b.$bouton}
    lappend caches $bouton [T $fr $en]
  }
  if {![winfo exists $b.plus]} {
    ttk::menubutton $b.plus -text "⋯" -style Toolbutton -menu $b.plus.m
    menu $b.plus.m -tearoff 0
    foreach {bouton lib} $caches {
      set bt $b.$bouton
      if {[winfo class $bt] eq "Checkbutton"} {
        $b.plus.m add checkbutton -label $lib -variable [$bt cget -variable] \
            -onvalue [$bt cget -onvalue] -offvalue [$bt cget -offvalue] \
            -command [$bt cget -command]
      } else {
        $b.plus.m add command -label $lib -command [list $bt invoke]
      }
    }
    $b.plus.m add separator
    variable choix
    set choix($n) [unite $n]
    $b.plus.m add radiobutton -label [T "Évaluation en centipions" "Evaluation in centipawns"] \
        -variable ::moderne::moteur::choix($n) -value cp -command [list ::moderne::moteur::changerUnite $n]
    $b.plus.m add radiobutton -label [T "Évaluation en score attendu (%)" "Evaluation as expected score (%)"] \
        -variable ::moderne::moteur::choix($n) -value score -command [list ::moderne::moteur::changerUnite $n]
    $b.plus.m add checkbutton -label [T "Afficher G/N/P" "Show W/D/L"] \
        -variable ::moderne::moteur::wdlVisible -command ::moderne::moteur::changerWdl
    $b.plus.m add separator
    $b.plus.m add command -label [T "Journal du moteur" "Engine log"] -command [list engineShowLog $n]
    pack $b.plus -side left -padx 4
    ::utils::tooltip::Set $b.plus [T "Autres actions" "More actions"]
  }
  catch {reglagesBarre $n}
  after idle [list catch [list placePopupButton $n]]
}

### Compact information row
proc ::moderne::moteur::infos {n t} {
  global analysis
  $t configure -state normal
  $t delete 1.0 end
  set morceaux {}
  if {[info exists analysis(depth$n)]} {
    set p "[T Profondeur Depth] $analysis(depth$n)"
    if {[info exists analysis(seldepth$n)] && $analysis(seldepth$n) != 0} { append p "/$analysis(seldepth$n)" }
    lappend morceaux $p
  }
  if {[info exists analysis(nps$n)] && [string is double -strict $analysis(nps$n)] && $analysis(nps$n) > 0} {
    set v $analysis(nps$n)
    if {$v >= 1e6} {
      lappend morceaux "[string map {. ,} [format %.1f [expr {$v / 1e6}]]] Mn/s"
    } else {
      lappend morceaux "[format %.0f [expr {$v / 1e3}]] kn/s"
    }
  }
  if {[info exists analysis(time$n)]} {
    lappend morceaux "[string map {. ,} [format %.1f $analysis(time$n)]] s"
  }
  catch {
    set hf $::uci::uciInfo(hashfull$n)
    if {[string is integer -strict $hf] && $hf > 0} { lappend morceaux "hash [expr {$hf / 10}] %" }
  }
  catch {
    set tb $::uci::uciInfo(tbhits$n)
    if {[string is integer -strict $tb] && $tb > 0} { lappend morceaux "TB $tb" }
  }
  $t insert end [join $morceaux "  •  "]
}

### Lines of engine n (one per variation)
proc ::moderne::moteur::lignes {n} {
  global analysis
  variable ajuste
  set h .analysisWin$n.hist.text
  if {![winfo exists $h]} { return }
  # First lines received: window height adjusted once
  if {![info exists ajuste($n)] || ![winfo exists $ajuste($n)]} {
    set ajuste($n) $h
    after 200 [list ::moderne::moteur::ajusterHauteur $n]
  }
  $h configure -state normal
  $h delete 1.0 end
  set i 0
  foreach pv $analysis(multiPV$n) {
    lassign $pv prof score coups mat
    if {$coups eq {}} { continue }
    if {$mat ne {} && $mat != 0} {
      set txt [expr {$mat > 0 ? "#$mat" : "#-[expr {abs($mat)}]"}]
      set tag [expr {$mat > 0 ? "evalB" : "evalN"}]
    } elseif {[string is double -strict $score]} {
      if {[unite $n] eq "score"} {
        set txt "[scoreAttendu $n $i $score $mat] %"
      } else {
        set txt [format %+.2f $score]
      }
      set tag [expr {$score >= 0 ? "evalB" : "evalN"}]
    } else {
      set txt ?
      set tag evalB
    }
    if {$i > 0} { $h insert end \n [list ligne bande[expr {($i - 1) % 2}]] }
    set bande bande[expr {$i % 2}]
    $h insert end " " [list ligne $bande] " $txt " [list ligne $tag]
    if {$i == 0} { set iFinEval [$h index "end - 1 chars"] }
    $h insert end "  " [list ligne $bande]
    set wdl [expr {$::moderne::moteur::wdlVisible ? [::moderne::wdl::court $n $i] : {}}]
    # (not expr: it would turn the index "1.10" into the number 1.1)
    if {$i == 0} { set iWdl {} ; if {$wdl ne {}} { set iWdl [$h index "end - 1 chars"] } }
    if {$wdl ne {}} { $h insert end "$wdl   " [list ligne wdl $bande] }
    if {$i == 0} { set iLigne [$h index "end - 1 chars"] }
    set texte [addMoveNumbers $n [::trans $coups]]
    set style [expr {$i == 0 ? "premier" : "coup"}]
    set cle 1
    set k 0
    foreach mot [split [string trim $texte] " "] {
      if {$mot eq {}} { continue }
      if {[regexp {^([0-9]+\.+)(.*)$} $mot -> num reste]} {
        # "3...." (number + SCID's "...") → "3..."
        regsub {^([0-9]+)\.{4,}$} $num {\1...} num
        $h insert end $num [list ligne num $bande]
        set mot $reste
      }
      if {$mot ne {}} {
        # The suggested move (first move of the line) in color
        # (m<line>.<move>: hover shows the position, click inserts the line up to it)
        $h insert end $mot [list ligne [expr {$cle ? "cle" : $style}] $bande m$i.$k]
        set cle 0
        incr k
      }
      $h insert end " " [list ligne $bande]
    }
    incr i
  }
  # (the end of the last line also takes the color of its stripe)
  if {$i > 0} { catch {$h tag add bande[expr {($i - 1) % 2}] "end - 1 chars" end} }
  $h configure -state disabled
  # column titles placed over the first line (once the text is drawn)
  if {$i > 0} {
    variable indexColonnes
    if {![info exists indexColonnes($n)]} { after idle [list ::moderne::moteur::placerColonnes $n] }
    set indexColonnes($n) [list $iWdl $iLigne $iFinEval]
    after idle [list ::moderne::moteur::mesurerLigne $n]
  }
  catch {::moderne::moteur::majEntete $n}
}

### Row height of the engine lines: the font's line space + 10, unless a
### line is taller (a figurine or bold glyph from a taller fallback font,
### seen at 31 px instead of 29: the 4th of 4 lines was cut). Measured on
### the lines drawn; only grows, and when it does every engine panel and
### Toby's table take it.
proc ::moderne::moteur::pasLigne {} {
  variable pasMesure
  set p [expr {[font metrics font_Regular -linespace] + 10}]
  if {[info exists pasMesure] && $pasMesure > $p} { set p $pasMesure }
  return $p
}

proc ::moderne::moteur::mesurerLigne {n} {
  variable pasMesure
  set h .analysisWin$n.hist.text
  if {![winfo exists $h]} { return }
  set m 0
  foreach l {1 2} {
    set d [$h dlineinfo $l.0]
    if {$d ne {} && [lindex $d 3] > $m} { set m [lindex $d 3] }
  }
  if {$m <= [pasLigne]} { return }
  set pasMesure $m
  foreach f [winfo children .] {
    if {![regexp {^\.analysisWin([0-9]+)$} $f -> k]} { continue }
    if {[winfo exists $f.toby]} {
      catch {::moderne::toby::ajusterHauteur $k}
      catch {::moderne::toby::afficher $k}
    } else {
      catch {ajusterHauteur $k}
    }
  }
}


################################################################################
### Lines and CPUs (Siby): "Lines − 4 +" and "CPU − 1 +" in the engine
### bar. Default is 4 lines and 1 CPU; the last choice is kept per
### engine (options.dat). A setting in the engine (Tools › Engines) wins.
################################################################################

proc ::moderne::moteur::nom {n} { return [lindex $::engines(list) $n 0] }

proc ::moderne::moteur::lignesDefaut {nom} {
  variable lignesMem
  if {[dict exists $lignesMem $nom]} { return [dict get $lignesMem $nom] }
  return 4
}

### {min max} of engine n's UCI option, or {} if it does not have it
proc ::moderne::moteur::bornes {n option} {
  if {![info exists ::analysis(uciOptions$n)]} { return {} }
  foreach opt $::analysis(uciOptions$n) {
    if {[lindex $opt 0] eq $option} {
      set min [lindex $opt 1] ; set max [lindex $opt 2]
      if {![string is integer -strict $min]} { set min 1 }
      if {![string is integer -strict $max]} { set max 512 }
      return [list $min $max]
    }
  }
  return {}
}

### Value set in the engine's configuration, or {}
proc ::moderne::moteur::regle {n option} {
  foreach opt [lindex $::engines(list) $n 8] {
    if {[lindex $opt 0] eq $option} { return [lindex $opt 1] }
  }
  return {}
}

### When the engine starts: number of CPUs (Threads option)
proc ::moderne::moteur::cpuDepart {n} {
  variable cpu
  variable cpuMem
  variable departFait
  if {[bornes $n Threads] eq {}} { return }
  # Always 1 CPU at first, or the last choice made in this window;
  # a number set elsewhere (old detection: cores − 1) is ignored
  set v [expr {[dict exists $cpuMem [nom $n]] ? [dict get $cpuMem [nom $n]] : 1}]
  set cpu($n) $v
  # already sent before the first analysis (optionsDepart)
  if {[info exists departFait($n)] && $departFait($n)} { return }
  catch {envoyerOption $n Threads $v}
}

### Right after "uciok", before any analysis: lines and CPUs
proc ::moderne::moteur::optionsDepart {n} {
  global analysis
  variable cpuMem
  variable cpu
  variable departFait
  set departFait($n) 0
  if {![::moderne::actif]} { return }
  set nom [nom $n]
  set envoyer {}
  set toby [string match -nocase *toby* $nom]
  set b [bornes $n MultiPV]
  variable lignesMem
  # (the last "Lines − +" choice wins over the engine's configuration)
  if {$b ne {} && !$toby && ([regle $n MultiPV] eq {} || [dict exists $lignesMem $nom])} {
    set v [expr {min([lignesDefaut $nom], [lindex $b 1])}]
    lappend envoyer MultiPV $v
    set analysis(multiPVCount$n) $v
  }
  if {[bornes $n Threads] ne {}} {
    set v [expr {[dict exists $cpuMem $nom] ? [dict get $cpuMem $nom] : 1}]
    lappend envoyer Threads $v
    set cpu($n) $v
  }
  # (no "isready" wait: called right after "uciok", before any search)
  foreach {o v} $envoyer {
    ::sendToEngine $n "setoption name $o value $v"
  }
  set departFait($n) 1
}

### Sends an option to engine n: if it is analyzing, stop, option, resume
proc ::moderne::moteur::envoyerOption {n nomOption valeur} {
  global analysis
  if {$analysis(analyzeMode$n)} {
    stopAnalyzeMode $n
    set analysis(waitForReadyOk$n) 1
    sendToEngine $n "isready"
    set garde [after 10000 "set ::analysis(waitForReadyOk$n) 0"]
    vwait analysis(waitForReadyOk$n)
    after cancel $garde
    sendToEngine $n "setoption name $nomOption value $valeur"
    startAnalyzeMode $n
  } else {
    sendToEngine $n "setoption name $nomOption value $valeur"
  }
}

proc ::moderne::moteur::changerLignes {n d} {
  variable lignesMem
  set b [bornes $n MultiPV]
  if {$b eq {}} { return }
  lassign $b min max
  set v [expr {max($min, min($max, $::analysis(multiPVCount$n) + $d))}]
  if {$v == $::analysis(multiPVCount$n)} { return }
  set ::analysis(multiPVCount$n) $v
  dict set lignesMem [nom $n] $v
  changePVSize $n
  after idle [list ::moderne::moteur::ajusterHauteur $n]
}

### Height of the engine window: bar + one row per line
proc ::moderne::moteur::ajusterHauteur {n} {
  set w .analysisWin$n
  if {![winfo exists $w.b]} { return }
  if {[winfo exists $w.toby]} { return }
  # Toby before its table: the height it had last time
  variable hauteurMem
  if {[string match -nocase *toby* [nom $n]] && [dict exists $hauteurMem "[nom $n]|toby"]} {
    catch {::moderne::docks::ajusterHauteur .fdockanalysisWin$n [dict get $hauteurMem "[nom $n]|toby"]}
    return
  }
  set nb $::analysis(multiPVCount$n)
  # engine not ready yet: the number of lines it will have (otherwise the
  # height would be redone at its first lines and the board would move)
  if {![info exists ::analysis(uciok$n)] || !$::analysis(uciok$n)} {
    variable lignesMem
    set nom [nom $n]
    set nb [lignesDefaut $nom]
    set r [regle $n MultiPV]
    if {$r ne {} && ![dict exists $lignesMem $nom]} { set nb $r }
  }
  if {![string is integer -strict $nb] || $nb < 1} { set nb 1 }
  set ligne [pasLigne]
  variable barreMesuree [winfo reqheight $w.b]
  set h [expr {[winfo reqheight $w.b] + $nb * $ligne + 10}]
  if {[winfo exists $w.entete]} { incr h [winfo reqheight $w.entete] }
  if {[winfo exists $w.colonnes]} { incr h [winfo reqheight $w.colonnes] }
  if {[winfo exists $w.text] && [winfo manager $w.text] ne {}} { incr h [winfo reqheight $w.text] }
  # The evaluation header and the column titles appear with the first
  # lines: until then, the height this engine had last time (so the board
  # does not move when they come)
  variable hauteurMem
  set cle "[nom $n]|$nb"
  if {[winfo exists $w.entete] && [winfo exists $w.colonnes]} {
    dict set hauteurMem $cle $h
  } elseif {[dict exists $hauteurMem $cle]} {
    set h [expr {max($h, [dict get $hauteurMem $cle])}]
  }
  catch {::moderne::docks::ajusterHauteur .fdockanalysisWin$n $h}
  # (checked once placed: on Windows the panel got a few pixels less than
  # computed and the 4th line was hidden; the missing height is added)
  variable verifHauteur
  catch {after cancel $verifHauteur($n)}
  set verifHauteur($n) [after 700 [list ::moderne::moteur::verifierHauteur $n $h $nb]]
}

### The lines asked for are all visible? Otherwise the panel grows by what
### is missing (at most twice in a row)
proc ::moderne::moteur::verifierHauteur {n h nb {essai 0}} {
  set t .analysisWin$n.hist.text
  if {![winfo exists $t] || ![winfo ismapped $t] || $essai > 1} { return }
  if {[info exists ::moderne::docks::restauration] && $::moderne::docks::restauration} {
    after 400 [list ::moderne::moteur::verifierHauteur $n $h $nb $essai]
    return
  }
  set manque [expr {$nb * [pasLigne] + 2 - [winfo height $t]}]
  if {$manque <= 2} { return }
  set h [expr {$h + $manque}]
  # (remembered with what was missing: the next time the panel opens at
  # its final height at once)
  variable hauteurMem
  catch {dict set hauteurMem "[nom $n]|$nb" $h}
  catch {::moderne::docks::ajusterHauteur .fdockanalysisWin$n $h}
  after 500 [list ::moderne::moteur::verifierHauteur $n $h $nb [incr essai]]
}

### Height engine n's panel will have, known before it starts (the one it
### had last time); empty when it never ran
proc ::moderne::moteur::hauteurPrevue {n} {
  variable hauteurMem
  variable lignesMem
  set nom [lindex [lindex $::engines(list) $n] 0]
  if {$nom eq {}} { return {} }
  if {[string match -nocase *toby* $nom] && [dict exists $hauteurMem "$nom|toby"]} {
    return [dict get $hauteurMem "$nom|toby"]
  }
  set nb [lignesDefaut $nom]
  catch {
    set r [regle $n MultiPV]
    if {$r ne {} && ![dict exists $lignesMem $nom]} { set nb $r }
  }
  if {[dict exists $hauteurMem "$nom|$nb"]} { return [dict get $hauteurMem "$nom|$nb"] }
  return {}
}

### Height of engine n's panel estimated from the fonts, when it never ran
### (first launch): the same sum as once it runs (bar, header, column
### titles, lines; for Toby its table with 4 rows), so the panel does not
### open at another height and then jump (Yosha 2026-11-01)
proc ::moderne::moteur::hauteurEstimee {n} {
  set nom [lindex [lindex $::engines(list) $n] 0]
  if {$nom eq {}} { return {} }
  catch {font create font_GrandEval -family [font actual font_Regular -family] -size 17 -weight bold}
  set ls [font metrics font_Regular -linespace]
  set entete [expr {[font metrics font_GrandEval -linespace] + 4}]
  set titres [expr {$ls + 8}]
  # (the button bar: as measured on a panel, else its usual height)
  variable barreMesuree
  set barre [expr {[info exists barreMesuree] ? $barreMesuree : $ls + 13}]
  set pas [pasLigne]
  if {[string match -nocase *toby* $nom]} {
    return [expr {$barre + $entete + $titres + 4 * $pas + 6 + 2}]
  }
  set nb [lignesDefaut $nom]
  catch {
    set r [regle $n MultiPV]
    variable lignesMem
    if {$r ne {} && ![dict exists $lignesMem $nom]} { set nb $r }
  }
  return [expr {$barre + $nb * $pas + 10 + $entete + $titres}]
}

### Last full height of each engine panel ("name|lines" -> pixels, saved)
namespace eval ::moderne::moteur {
  variable hauteurMem
  if {![info exists hauteurMem]} { set hauteurMem {} }
}

proc ::moderne::moteur::changerCPU {n d} {
  variable cpu
  variable cpuMem
  set b [bornes $n Threads]
  if {$b eq {}} { return }
  lassign $b min max
  if {![info exists cpu($n)]} { set cpu($n) 1 }
  set v [expr {max($min, min($max, $cpu($n) + $d))}]
  if {$v == $cpu($n)} { return }
  set cpu($n) $v
  dict set cpuMem [nom $n] $v
  envoyerOption $n Threads $v
}

### The two settings in the engine bar (replace the small counter)
proc ::moderne::moteur::reglagesBarre {n} {
  variable cpu
  set w .analysisWin$n
  set b $w.b
  if {![winfo exists $b] || [winfo exists $b.lc]} { return }
  set toby [string match -nocase *toby* [nom $n]]
  set avecLignes [expr {!$toby && [bornes $n MultiPV] ne {}}]
  set avecCPU [expr {[bornes $n Threads] ne {}}]
  if {!$avecLignes && !$avecCPU} { return }
  catch {pack forget $b.multipv}
  ttk::frame $b.lc
  catch {ttk::style configure Petit.Toolbutton -padding {3 0 3 1}}
  set petit Petit.Toolbutton
  if {[catch {ttk::style layout Petit.Toolbutton}]} { set petit Toolbutton }
  if {$avecLignes} {
    ttk::label $b.lc.ll -text [T "Lignes" "Lines"] -foreground [::moderne::c texteDoux]
    ttk::button $b.lc.lm -text "−" -width 1 -style $petit -command [list ::moderne::moteur::changerLignes $n -1]
    ttk::label $b.lc.lv -textvariable ::analysis(multiPVCount$n) -width 2 -anchor center -font font_Bold
    ttk::button $b.lc.lp -text "+" -width 1 -style $petit -command [list ::moderne::moteur::changerLignes $n 1]
    pack $b.lc.ll $b.lc.lm $b.lc.lv $b.lc.lp -side left
    ::utils::tooltip::Set $b.lc.ll [T "Nombre de lignes (variantes) affichées" "Number of lines shown"]
  }
  if {$avecCPU} {
    if {![info exists cpu($n)]} { set cpu($n) 1 }
    ttk::label $b.lc.cl -text "CPU" -foreground [::moderne::c texteDoux]
    ttk::button $b.lc.cm -text "−" -width 1 -style $petit -command [list ::moderne::moteur::changerCPU $n -1]
    ttk::label $b.lc.cv -textvariable ::moderne::moteur::cpu($n) -width 2 -anchor center -font font_Bold
    ttk::button $b.lc.cp -text "+" -width 1 -style $petit -command [list ::moderne::moteur::changerCPU $n 1]
    pack $b.lc.cl -side left -padx {6 0}
    pack $b.lc.cm $b.lc.cv $b.lc.cp -side left
    ::utils::tooltip::Set $b.lc.cl [T "Nombre de cœurs du processeur utilisés par le moteur (option Threads)" "CPU cores used by the engine (Threads)"]
  }
  if {!$toby} {
    ttk::label $b.lc.nl -text [T "Limite" "Limit"] -foreground [::moderne::c texteDoux]
    ttk::label $b.lc.nv -text [texteLimite [limite $n]] -font font_Bold -cursor hand2 -padding {4 0}
    bind $b.lc.nv <ButtonRelease-1> [list ::moderne::moteur::menuLimite $n %X %Y]
    bind $b.lc.nl <ButtonRelease-1> [list ::moderne::moteur::menuLimite $n %X %Y]
    pack $b.lc.nl -side left -padx {6 0}
    pack $b.lc.nv -side left
    ::utils::tooltip::Set $b.lc.nv [T "Nœuds analysés par position, puis le module s'arrête (∞ : sans limite)" "Nodes searched per position, then the engine stops (∞: no limit)"]
  }
  if {[winfo exists $b.plus]} {
    pack $b.lc -side left -padx 4 -before $b.plus
  } else {
    pack $b.lc -side left -padx 4
  }
  after 300 [list ::moderne::moteur::ajusterHauteur $n]
}

################################################################################
### Node limit per position: the engine stops once the limit is
### reached ("go nodes N" instead of "go infinite") and resumes at the
### next position. Default is 100k for neural-network engines
### (Leela…), no limit for the others (1 CPU).
################################################################################

proc ::moderne::moteur::reseauNeurones {n} {
  if {[string match -nocase *lc0* [nom $n]] || [string match -nocase *leela* [nom $n]]} { return 1 }
  foreach o {WeightsFile Backend} { if {[bornes $n $o] ne {}} { return 1 } }
  return 0
}

proc ::moderne::moteur::limite {n} {
  variable limiteMem
  set nom [nom $n]
  if {[dict exists $limiteMem $nom]} { return [dict get $limiteMem $nom] }
  return [expr {[reseauNeurones $n] ? 100000 : 0}]
}

proc ::moderne::moteur::texteLimite {v} {
  if {$v <= 0} { return "∞" }
  if {$v >= 1000000} { return "[expr {$v / 1000000}] M" }
  if {$v >= 1000} { return "[expr {$v / 1000}] k" }
  return $v
}

proc ::moderne::moteur::menuLimite {n X Y} {
  set m .menuLimite$n
  catch {destroy $m}
  menu $m -tearoff 0
  foreach v {0 10000 100000 1000000 10000000} {
    $m add command -label [expr {$v == 0 ? [T "∞ (sans limite)" "∞ (no limit)"] : "[texteLimite $v] [T nœuds nodes]"}] \
        -command [list ::moderne::moteur::changerLimite $n $v]
  }
  tk_popup $m $X $Y
}

proc ::moderne::moteur::changerLimite {n v} {
  variable limiteMem
  dict set limiteMem [nom $n] $v
  catch {.analysisWin$n.b.lc.nv configure -text [texteLimite $v]}
  # restarts the analysis with the new limit
  if {[info exists ::analysis(analyzeMode$n)] && $::analysis(analyzeMode$n)} {
    stopAnalyzeMode $n
    startAnalyzeMode $n
  }
}

### "go" command for engine n's analysis
proc ::moderne::moteur::commandeGo {n} {
  variable fini
  set fini($n) 0
  set go $::uci::goCommand
  if {![::moderne::actif] || $go ne "go infinite" || $::annotate(Engine) == $n} { return $go }
  if {[string match -nocase *toby* [nom $n]]} { return $go }
  set v [limite $n]
  if {$v > 0} { return "go nodes $v" }
  return $go
}

### "bestmove" received during analysis: limit reached
proc ::moderne::moteur::bestmove {n} {
  variable fini
  if {![info exists ::analysis(analyzeMode$n)] || !$::analysis(analyzeMode$n)} { return }
  if {[limite $n] <= 0} { return }
  set fini($n) 1
  after idle [list catch [list ::moderne::moteur::majEntete $n]]
}

################################################################################
### "»" button (bar too narrow): a menu of all the bar's actions,
### instead of SCID's copy of the bar (which could not copy the modern
### buttons: "tmenubutton" error)
################################################################################

proc ::moderne::moteur::menuDebordement {n} {
  global analysis
  set b .analysisWin$n.b
  set m .menuDebord$n
  catch {destroy $m}
  menu $m -tearoff 0
  foreach c [winfo children $b] {
    if {[catch {pack info $c}]} { continue }
    set nom [lindex [split $c .] end]
    set lib {}
    catch {set lib [string trim [regsub -all {\s+} $::utils::tooltip::message($c) " "]]}
    if {[string length $lib] > 60} { set lib "[string range $lib 0 57]…" }
    if {$lib eq {}} { set lib $nom }
    switch [winfo class $c] {
      Button - TButton {
        $m add command -label $lib -command [$c cget -command]
      }
      Checkbutton - TCheckbutton {
        $m add checkbutton -label $lib -variable [$c cget -variable] \
            -onvalue [$c cget -onvalue] -offvalue [$c cget -offvalue] -command [$c cget -command]
      }
      TMenubutton - Menubutton {
        catch {$m add cascade -label [T "Autres actions" "More actions"] -menu [$c cget -menu]}
      }
      TFrame {
        if {$nom eq "lc"} {
          $m add separator
          if {[winfo exists $c.lp]} {
            $m add command -label "[T "Lignes" "Lines"] + ([expr {$analysis(multiPVCount$n) + 1}])" \
                -command [list ::moderne::moteur::changerLignes $n 1]
            $m add command -label "[T "Lignes" "Lines"] − ([expr {$analysis(multiPVCount$n) - 1}])" \
                -command [list ::moderne::moteur::changerLignes $n -1]
          }
          if {[winfo exists $c.cp]} {
            variable cpu
            $m add command -label "CPU + ([expr {$cpu($n) + 1}])" -command [list ::moderne::moteur::changerCPU $n 1]
            $m add command -label "CPU − ([expr {$cpu($n) - 1}])" -command [list ::moderne::moteur::changerCPU $n -1]
          }
          $m add separator
        }
      }
    }
  }
  tk_popup $m [winfo pointerx .] [winfo pointery .]
}

if {![llength [info commands ::popupButtonBar_origine]]} {
  rename ::popupButtonBar ::popupButtonBar_origine
  proc ::popupButtonBar {n} {
    if {[::moderne::actif]} { ::moderne::moteur::menuDebordement $n ; return }
    ::popupButtonBar_origine $n
  }
}

################################################################################
### Engine header (Lichess style): green dot while it is computing,
### large evaluation, then "depth • speed"
################################################################################

proc ::moderne::moteur::entete {n} {
  set w .analysisWin$n
  if {![winfo exists $w.b] || [winfo exists $w.entete] || [winfo exists $w.toby]} { return }
  # Toby has its own header (expected score): no second row
  if {![catch {::moderne::toby::estToby $n} t] && $t} { return }
  catch {font create font_GrandEval -family [font actual font_Regular -family] -size 17 -weight bold}
  set f [frame $w.entete -background [::moderne::c fond]]
  label $f.pt -text "●" -font font_Regular -background [::moderne::c fond] -foreground [::moderne::c inactif]
  label $f.ev -text "…" -font font_GrandEval -background [::moderne::c fond] -foreground [::moderne::c texteFort]
  label $f.det -text {} -font font_Small -background [::moderne::c fond] -foreground [::moderne::c texteDoux]
  pack $f.pt -side left -padx {10 4}
  pack $f.ev -side left -padx {0 10}
  pack $f.det -side left
  # Column titles, at the height of Toby's (the moves of both start at
  # the same level when they are side by side)
  set c [canvas $w.colonnes -highlightthickness 0 -borderwidth 0 -background [::moderne::c surface] \
      -height [expr {[font metrics font_Regular -linespace] + 8}]]
  if {[winfo exists $w.hist]} {
    pack $f -side top -fill x {*}[::moderne::avantHist $w]
    pack $c -side top -fill x {*}[::moderne::avantHist $w]
  } else {
    pack $f $c -side top -fill x
  }
  bind $c <Configure> [list ::moderne::moteur::colonnes $n]
}

proc ::moderne::moteur::placerColonnes {n} {
  variable indexColonnes
  if {![info exists indexColonnes($n)]} { return }
  lassign $indexColonnes($n) iWdl iLigne iFinEval
  unset indexColonnes($n)
  set w .analysisWin$n
  set h $w.hist.text
  if {![winfo exists $h] || ![winfo exists $w.colonnes]} { return }
  catch {
    set dx [expr {[winfo rootx $h] - [winfo rootx $w.colonnes]}]
    set xW {}
    if {$iWdl ne {}} { set xW [expr {[lindex [$h bbox $iWdl] 0] + $dx}] }
    set xL [expr {[lindex [$h bbox $iLigne] 0] + $dx}]
    set xF [expr {[lindex [$h bbox $iFinEval] 0] + $dx}]
    colonnes $n $xW $xL $xF
  }
}

### Column titles above the lines: evaluation, W/D/L, line (x taken
### from the first line when there is one)
proc ::moderne::moteur::colonnes {n {xW {}} {xL {}} {xFinEval {}}} {
  set w .analysisWin$n
  set c $w.colonnes
  if {![winfo exists $c]} { return }
  variable posColonnes
  if {$xL ne {}} {
    set posColonnes($n) [list $xW $xL $xFinEval]
  } elseif {[info exists posColonnes($n)]} {
    lassign $posColonnes($n) xW xL xFinEval
  }
  set chiffre [font measure font_Regular 0]
  if {$xFinEval eq {}} { set xFinEval [expr {8 * $chiffre}] }
  if {$xL eq {}} { set xL [expr {$xFinEval + 2 * $chiffre}] }
  set hl [winfo reqheight $c]
  set doux [::moderne::c texteDoux]
  $c delete all
  $c create text [expr {$xFinEval / 2}] [expr {$hl / 2}] -anchor center -text [T "Éval" "Eval"] -fill $doux -font font_Small
  # (W/D/L title only when it fits before the line's one)
  set tW [T "G/N/P" "W/D/L"]
  if {$xW ne {} && $xW + [font measure font_Small $tW] + 6 <= $xL} {
    $c create text $xW [expr {$hl / 2}] -anchor w -text $tW -fill $doux -font font_Small
  }
  $c create text $xL [expr {$hl / 2}] -anchor w -text [T "Ligne" "Line"] -fill $doux -font font_Small
  $c create line 0 [expr {$hl - 1}] [winfo width $c] [expr {$hl - 1}] -fill [::moderne::c bordure]
}

proc ::moderne::moteur::majEntete {n} {
  global analysis
  set f .analysisWin$n.entete
  if {![winfo exists $f]} { return }
  # Dot: green while the engine is computing, gray when paused
  set actif [expr {[info exists analysis(analyzeMode$n)] && $analysis(analyzeMode$n)}]
  variable fini
  set termine [expr {$actif && [info exists fini($n)] && $fini($n)}]
  $f.pt configure -foreground [expr {$actif && !$termine ? "#4cc16b" : [::moderne::c inactif]}]
  # Evaluation of the best line
  set ev …
  set pv [lindex $analysis(multiPV$n) 0]
  if {[llength $pv]} {
    lassign $pv prof score coups mat
    if {$mat ne {} && $mat != 0} {
      set ev [expr {$mat > 0 ? "#$mat" : "#-[expr {abs($mat)}]"}]
    } elseif {[string is double -strict $score]} {
      # (if rather than expr: expr would turn "+0.85" into the number 0.85)
      if {[unite $n] eq "score"} {
        set ev "[scoreAttendu $n 0 $score $mat] %"
      } else {
        set ev [format %+.2f $score]
      }
    }
  }
  $f.ev configure -text $ev
  # Depth and speed
  set det {}
  if {[info exists analysis(depth$n)] && $analysis(depth$n) > 0} { lappend det "[T profondeur depth] $analysis(depth$n)" }
  if {[info exists analysis(nps$n)] && [string is double -strict $analysis(nps$n)] && $analysis(nps$n) > 0} {
    set v $analysis(nps$n)
    lappend det [expr {$v >= 1e6 ? [format "%.1f M" [expr {$v / 1e6}]] : [format "%.0f k" [expr {$v / 1e3}]]}][T " nœuds/s" " nodes/s"]
  }
  if {!$actif} { lappend det [T "en pause" "paused"] }
  if {$termine} { lappend det "[T terminé done] ([texteLimite [limite $n]] [T nœuds nodes])" }
  $f.det configure -text [join $det "  •  "]
}

proc ::moderne::moteur::apresMarcheArret {cmd args} {
  set n [lindex $cmd 1]
  if {[string is integer -strict $n]} { after idle [list catch [list ::moderne::moteur::majEntete $n]] }
}
foreach c {startAnalyzeMode stopAnalyzeMode} {
  catch {trace add execution $c leave ::moderne::moteur::apresMarcheArret}
}

### End Siby

################################################################################
### Moves of the lines: hovering a move shows the position after it on the
### board, under a gray veil (it is not the game's position); a click
### inserts the line up to that move (right-click: menu)
################################################################################

namespace eval ::moderne::moteur {
  variable survolCle {}
}

### {line move} under the pointer, or {}
proc ::moderne::moteur::coupSous {h x y} {
  foreach t [$h tag names @$x,$y] {
    if {[regexp {^m([0-9]+)\.([0-9]+)$} $t -> i k]} { return [list $i $k] }
  }
  return {}
}

proc ::moderne::moteur::survolCoup {n x y} {
  variable survolCle
  set h .analysisWin$n.hist.text
  set c [coupSous $h $x $y]
  set cle [expr {$c eq {} ? {} : "$n $c"}]
  # (between two moves: the last position previewed stays, the game's
  # position comes back only when the pointer leaves the lines)
  if {$c eq {}} { $h configure -cursor {} ; return }
  if {$cle eq $survolCle} { return }
  set survolCle $cle
  $h configure -cursor hand2
  apercu $n {*}$c
}

### Board after the moves 0..k of line i of engine n, under a gray veil
proc ::moderne::moteur::apercu {n i k} {
  set coups [lrange [lindex $::analysis(multiPVraw$n) $i 2] 0 $k]
  if {![llength $coups] || ![winfo exists .main.board]} { return }
  sc_game push copy
  set ok 1
  foreach m $coups { if {[catch {sc_move addUCI $m}]} { set ok 0 ; break } }
  set plateau [sc_pos board]
  sc_game pop
  if {!$ok} { return }
  apercuPlateau $plateau
}

### A board shown on the main board under a gray veil (the game's
### position comes back with finApercu)
proc ::moderne::moteur::apercuPlateau {plateau} {
  if {![winfo exists .main.board]} { return }
  ::board::update .main.board $plateau
  set cv .main.board.bd
  if {[lsearch [image names] ::moderne::moteur::voile] < 0} {
    image create photo ::moderne::moteur::voile1 -data {iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNwc3OrAAAC8wFLv2kZgwAAAABJRU5ErkJggg==}
    image create photo ::moderne::moteur::voile
  }
  set l [winfo width $cv] ; set ht [winfo height $cv]
  if {[image width ::moderne::moteur::voile] != $l || [image height ::moderne::moteur::voile] != $ht} {
    ::moderne::moteur::voile blank
    ::moderne::moteur::voile configure -width $l -height $ht
    ::moderne::moteur::voile copy ::moderne::moteur::voile1 -zoom $l $ht
  }
  $cv delete voileApercu
  $cv create image 0 0 -anchor nw -image ::moderne::moteur::voile -tags voileApercu
}

proc ::moderne::moteur::finApercu {} {
  variable survolCle
  set survolCle {}
  if {![winfo exists .main.board.bd]} { return }
  if {![llength [.main.board.bd find withtag voileApercu]]} { return }
  .main.board.bd delete voileApercu
  ::board::update .main.board [sc_pos board]
}

### Click on a move: the line inserted up to that move
proc ::moderne::moteur::clicCoup {n x y} {
  set c [coupSous .analysisWin$n.hist.text $x $y]
  if {$c eq {}} { return }
  finApercu
  ::moderne::menuclic::ajouterLigne $n {*}$c
}

proc ::moderne::moteur::installerSurvol {n} {
  set h .analysisWin$n.hist.text
  if {![winfo exists $h]} { return }
  bind $h <Motion> [list ::moderne::moteur::survolCoup $n %x %y]
  bind $h <Leave> {::moderne::moteur::finApercu ; %W configure -cursor {}}
  bind $h <ButtonRelease-1> [list ::moderne::moteur::clicCoup $n %x %y]
}
