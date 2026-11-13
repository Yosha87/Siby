###
### Siby: engine already in use elsewhere
###
### An engine (Stockfish, Toby…) may be wanted in several places: the
### analysis panel of the board, a game against it (Play menu: Toby,
### Alter Ego, engine), the tree analysis, the error search of the
### preparation. Instead of making the user go back, stop it and start it
### again (as in ChessBase), Siby notes where each engine runs and, when it
### is wanted elsewhere, offers in one click to stop it there and use it
### here:
###   - analysis -> game: the game takes it (short notice) and the
###     analysis comes back by itself after the game;
###   - game -> analysis: question (it would end the game);
###   - tree analysis / error search (their own process): question, with
###     "Keep both" (two copies: each one slower), except for the engines on
###     the graphics card (Toby, which loads Maia and Leela, Leela, Maia):
###     never two copies.
### The panel and a game share SCID's state of engine n: they can never
### run together.
###

namespace eval ::moderne::occupation {
  variable occ          ;# occ(n) = list of {context stopScript}
  array set occ {}
  variable rendre       ;# rendre(n): analysis to bring back after the game
  array set rendre {}
  variable enPause       ;# enPause(n): contexts holding analysis panel n paused
  array set enPause {}
  variable reponse
}

proc ::moderne::occupation::T {fr en} { return [::moderne::tr $fr $en] }

proc ::moderne::occupation::nom {n} {
  set nom [lindex $::engines(list) $n 0]
  return [expr {$nom eq {} ? [T "Ce moteur" "This engine"] : $nom}]
}

### Index of the engine described by e (entry of ::engines(list)), or -1
proc ::moderne::occupation::index {e} {
  set i 0
  foreach x $::engines(list) {
    if {[lindex $x 0] eq [lindex $e 0] && [lindex $x 1] eq [lindex $e 1]} { return $i }
    incr i
  }
  return -1
}

proc ::moderne::occupation::libelle {contexte} {
  switch -- $contexte {
    analyse { return [T "dans l'analyse de l'échiquier" "in the board analysis"] }
    jeu     { return [T "dans la partie en cours contre lui" "in the game being played against it"] }
    arbre   { return [T "dans l'analyse en arbre" "in the tree analysis"] }
    erreurs { return [T "dans la recherche d'erreurs (préparation)" "in the error search (preparation)"] }
    oracle  { return [T "dans l'annotation de la partie" "in the game annotation"] }
  }
  return $contexte
}

### Engines on the graphics card (Toby loads Maia and Leela, Leela,
### Maia): never two copies (twice the networks in the card's memory)
proc ::moderne::occupation::carteGraphique {n} {
  set e [lindex $::engines(list) $n]
  return [regexp -nocase {toby|lc0|leela|maia} "[lindex $e 0] [file tail [lindex $e 1]]"]
}

### Can these two contexts run the same engine together (two processes)?
proc ::moderne::occupation::ensemble {a b {n -1}} {
  if {$n >= 0 && [carteGraphique $n]} { return 0 }
  expr {!($a in {analyse jeu} && $b in {analyse jeu})}
}

proc ::moderne::occupation::occupe {n} {
  variable occ
  expr {[info exists occ($n)] && [llength $occ($n)] > 0}
}

### Engine n wanted for contexte (stop: script stopping it there).
### Returns 1 to go on, 0 if the user cancels.
proc ::moderne::occupation::prendre {n contexte arret} {
  variable occ
  variable rendre
  if {![string is integer -strict $n] || $n < 0} { return 1 }
  if {![info exists occ($n)]} { set occ($n) {} }
  set autres {}
  foreach o $occ($n) {
    if {[lindex $o 0] ne $contexte} { lappend autres $o }
  }
  foreach o $autres {
    lassign $o c stop
    if {$contexte eq "oracle" && $c eq "analyse"} {
      # the annotation: the panel stays where it is, paused (its engine
      # waits, the annotation runs its own), and analyses again afterwards
      pauser $n oracle
      continue
    }
    if {$contexte eq "jeu" && $c eq "analyse"} {
      # the game (or the annotation) takes it; the analysis comes back after
      set rendre($n) 1
      liberer $n analyse
      catch {uplevel #0 $stop}
      if {$contexte eq "jeu"} {
        set fr "la partie" ; set en "the game"
      } else {
        set fr "l'annotation" ; set en "the annotation"
      }
      catch {::moderne::nsb::annonce [T \
          "[nom $n] quitte l'analyse pour $fr (elle reviendra après)" \
          "[nom $n] leaves the analysis for $en (it will come back afterwards)"] -1}
      after 3500 {catch ::moderne::nsb::finAnnonce}
      continue
    }
    set choix [demander $n $c [ensemble $c $contexte $n] [ensemble $c $contexte]]
    if {$choix eq "annuler"} { return 0 }
    if {$choix eq "ici"} {
      liberer $n $c
      catch {uplevel #0 $stop}
    }
  }
  set occ($n) [lsearch -all -inline -not -index 0 $occ($n) $contexte]
  lappend occ($n) [list $contexte $arret]
  return 1
}

proc ::moderne::occupation::liberer {n contexte} {
  variable occ
  variable rendre
  if {![string is integer -strict $n] || ![info exists occ($n)]} { return }
  set avant [llength $occ($n)]
  set occ($n) [lsearch -all -inline -not -index 0 $occ($n) $contexte]
  # end of a game: the layout and engines of before the game come back
  # (playing layout, without engines), or else the analysis it took
  if {$contexte eq "jeu" && $avant > [llength $occ($n)]} {
    set fait 0
    catch {set fait [::moderne::disposition::jeuApres]}
    if {[info exists rendre($n)]} {
      unset rendre($n)
      if {!$fait} { after 500 [list ::moderne::occupation::rendreAnalyse $n] }
    }
  }
  if {$contexte eq "oracle"} { after 300 [list ::moderne::occupation::reprendre oracle] }
  if {$contexte eq "oracle" && $avant > [llength $occ($n)] && [info exists rendre($n)]} {
    unset rendre($n)
    after 500 [list ::moderne::occupation::rendreAnalyse $n]
  }
}

### Analysis panels paused (window kept, engine waiting) by a context
### (annotation, game review), then analysing again when no context holds
### them any more. enPause(n): the contexts holding panel n.
proc ::moderne::occupation::pauser {n contexte} {
  variable enPause
  if {![winfo exists .analysisWin$n]} { return }
  set analyse [expr {[info exists ::analysis(analyzeMode$n)] && $::analysis(analyzeMode$n)}]
  if {!$analyse && ![info exists enPause($n)]} { return }
  if {$analyse} { catch {toggleEngineAnalysis $n} }
  if {![info exists enPause($n)]} { set enPause($n) {} }
  if {$contexte ni $enPause($n)} { lappend enPause($n) $contexte }
}

### All the analysis panels analysing, paused for contexte
proc ::moderne::occupation::pauserTout {contexte} {
  foreach f [winfo children .] {
    if {[regexp {^\.analysisWin([0-9]+)$} $f -> n]} { pauser $n $contexte }
  }
}

proc ::moderne::occupation::reprendre {contexte} {
  variable enPause
  foreach n [array names enPause] {
    set enPause($n) [lsearch -all -inline -not -exact $enPause($n) $contexte]
    if {[llength $enPause($n)]} { continue }
    unset enPause($n)
    if {[winfo exists .analysisWin$n] && !([info exists ::analysis(analyzeMode$n)] && $::analysis(analyzeMode$n))} {
      catch {toggleEngineAnalysis $n}
    }
  }
}

proc ::moderne::occupation::rendreAnalyse {n} {
  if {[winfo exists .analysisWin$n] || [occupe $n]} { return }
  catch {makeAnalysisWin $n}
}

### Question: "use it here" (stop it there), "keep both" (deux: allowed;
### possible: two processes would work, refused for the graphics card),
### "cancel". Tests: ::moderne::occupation::reponseAuto gives the answer.
proc ::moderne::occupation::demander {n contexte deux {possible 0}} {
  variable reponse
  if {[info exists ::moderne::occupation::reponseAuto]} {
    puts "OCCUPATION: [nom $n] [libelle $contexte] -> $::moderne::occupation::reponseAuto"
    return $::moderne::occupation::reponseAuto
  }
  set w .occupation
  catch {destroy $w}
  toplevel $w
  wm title $w Siby
  wm transient $w .
  wm resizable $w 0 0
  set f [ttk::frame $w.f -padding 16]
  pack $f -fill both -expand 1
  ttk::label $f.t -font font_Bold -wraplength 420 -justify left -text \
      "[nom $n] [T "est déjà utilisé" "is already in use"] [libelle $contexte]."
  ttk::label $f.d -wraplength 420 -justify left -foreground [::moderne::c texteDoux] -text [expr {$deux \
      ? [T "Tu peux l'arrêter là-bas pour l'utiliser ici, ou garder les deux (deux copies : chacune va moins vite)." \
           "You can stop it there to use it here, or keep both (two copies: each one is slower)."] \
      : [expr {[carteGraphique $n] && $possible ? \
          [T "Il tourne sur la carte graphique (avec ses réseaux, Maia et Leela pour Toby) : deux copies la satureraient. L'arrêter là-bas pour l'utiliser ici ?" \
             "It runs on the graphics card (with its networks, Maia and Leela for Toby): two copies would overload it. Stop it there to use it here?"] : \
          [T "Il ne peut pas tourner aux deux endroits à la fois : l'arrêter là-bas pour l'utiliser ici ?" \
             "It cannot run in both places at once: stop it there to use it here?"]}]}]
  pack $f.t $f.d -side top -anchor w -pady {0 8}
  ttk::frame $f.b
  ttk::button $f.b.ici -text [T "L'arrêter là-bas et l'utiliser ici" "Stop it there and use it here"] \
      -command {set ::moderne::occupation::reponse ici}
  catch {$f.b.ici configure -style Accent.TButton}
  ttk::button $f.b.annuler -text [T "Annuler" "Cancel"] -command {set ::moderne::occupation::reponse annuler}
  pack $f.b.annuler -side right
  if {$deux} {
    ttk::button $f.b.deux -text [T "Garder les deux" "Keep both"] -command {set ::moderne::occupation::reponse deux}
    pack $f.b.deux -side right -padx 6
  }
  pack $f.b.ici -side right
  pack $f.b -side top -fill x -pady {6 0}
  bind $w <Return> {set ::moderne::occupation::reponse ici}
  bind $w <Escape> {set ::moderne::occupation::reponse annuler}
  wm protocol $w WM_DELETE_WINDOW {set ::moderne::occupation::reponse annuler}
  catch {::moderne::repeindre $w}
  catch {placeWinOverParent $w .}
  focus $f.b.ici
  catch {grab $w}
  set reponse {}
  vwait ::moderne::occupation::reponse
  catch {grab release $w}
  destroy $w
  return $reponse
}

### Closes the analysis panel of engine n
proc ::moderne::occupation::fermerAnalyse {n} {
  if {[winfo exists .analysisWin$n]} { catch {makeAnalysisWin $n} }
}

### Stops the game played against engine n (Play menu)
proc ::moderne::occupation::arreterJeu {n} {
  if {[winfo exists .serGameWin] && [info exists ::sergame::engine] && $::sergame::engine == $n} {
    catch {::sergame::abortGame}
    catch {::moderne::disposition::jeuApresMaintenant}
    return
  }
  if {[winfo exists .coachWin]} { catch {::tacgame::abortGame} ; return }
  catch {::uci::closeUCIengine $n}
}

### Safety net: an analysis engine left running with no window and no
### one using it (its window closed at the wrong moment) is stopped after
### a few seconds, so it does not use the processor for nothing. Not
### during an engine tournament (engines without windows there).
namespace eval ::moderne::occupation { variable orphelins ; array set orphelins {} }
proc ::moderne::occupation::veille {} {
  variable occ
  variable orphelins
  after 5000 ::moderne::occupation::veille
  if {[winfo exists .comp] || [winfo exists .calvarWin]} { return }
  foreach cle [array names ::analysis pipe*] {
    if {![regexp {^pipe([0-9]+)$} $cle -> n]} { continue }
    set orphelin [expr {$::analysis($cle) ne {} && ![winfo exists .analysisWin$n] &&
        (![info exists occ($n)] || ![llength $occ($n)])}]
    if {!$orphelin} { catch {unset orphelins($n)} ; continue }
    # (seen twice in a row, 5 s apart)
    if {![info exists orphelins($n)]} { set orphelins($n) 1 ; continue }
    unset orphelins($n)
    puts stderr "Siby: engine $n left without a window, stopped"
    catch {sendToEngine $n stop}
    catch {sendToEngine $n quit}
    catch {fileevent $::analysis($cle) readable {}}
    catch {close $::analysis($cle)}
    set ::analysis($cle) {}
  }
}
after 10000 ::moderne::occupation::veille

### End Siby
