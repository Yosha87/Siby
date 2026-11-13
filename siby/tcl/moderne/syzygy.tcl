
###
### Siby: local Syzygy tablebases in the endgame window
###
### "Syzygy (local)" source of Tools › Tablebases: exact result of the
### position (win / draw / loss, with the 50-move rule) and ranking
### of all moves, read from the .rtbw/.rtbz files on disk using
### Fathom (src/fathom, MIT license; C++ command sc_syzygy).
###
### Tables folder: setting ::moderne::syzygy::chemin (saved in the
### options); by default, an engine's SyzygyPath folder or a usual
### folder (~/syzygy, /usr/share/syzygy…). Several folders: separated
### by ":".
###

namespace eval ::moderne::syzygy {
  variable chemin          ;# saved in options.dat (already read at this point)
  if {![info exists chemin]} { set chemin {} }
  variable charge {}       ;# folder actually loaded
}

### Default folder: SyzygyPath of a configured engine, otherwise a usual folder
proc ::moderne::syzygy::cheminParDefaut {} {
  if {[info exists ::engines(list)]} {
    foreach e $::engines(list) {
      foreach opt [lindex $e 8] {
        if {[lindex $opt 0] eq "SyzygyPath" && [lindex $opt 1] ne {} && [lindex $opt 1] ne "<empty>"} {
          return [lindex $opt 1]
        }
      }
    }
  }
  if {[llength [info commands ::moderne::moteurs::dossierSyzygy]]} {
    return [::moderne::moteurs::dossierSyzygy]
  }
  return {}
}

### Loads the tables if needed; returns the maximum number of pieces (0 = none)
proc ::moderne::syzygy::init {} {
  variable chemin
  variable charge
  if {[llength [info commands sc_syzygy]] == 0} { return 0 }
  if {$chemin eq {}} { set chemin [cheminParDefaut] }
  if {$chemin eq {}} { return 0 }
  if {$chemin ne $charge} {
    set charge $chemin
    return [sc_syzygy init $chemin]
  }
  return [sc_syzygy largest]
}

proc ::moderne::syzygy::choisirDossier {{parent .}} {
  variable chemin
  set d [tk_chooseDirectory -parent $parent -mustexist 1 \
      -title [::moderne::tr "Dossier des tablebases Syzygy" "Syzygy tablebase folder"] \
      -initialdir [expr {$chemin ne {} ? [lindex [split $chemin :] 0] : [expr {[info exists ::env(HOME)] ? $::env(HOME) : "/"}]}]]
  if {$d eq {}} { return }
  set chemin $d
  set n [init]
  catch {.menu.options invoke [tr OptionsSave]}
  catch {::tb::results}
  if {$n == 0} {
    tk_messageBox -parent $parent -type ok -icon warning -title Siby -message [::moderne::tr \
        "Aucune table Syzygy (.rtbw) trouvée dans ce dossier." "No Syzygy tables (.rtbw) found in this folder."]
  }
}

### UCI move -> SAN (in the interface language), without touching the game
proc ::moderne::syzygy::san {fen uci} {
  sc_game push
  set r $uci
  catch {
    sc_game startBoard $fen
    set r [string trim [sc_move addUCI $uci]]
  }
  sc_game pop
  return [::trans $r]
}

proc ::moderne::syzygy::nomResultat {wdl} {
  set T ::moderne::tr
  switch -- $wdl {
    win          { return [$T "GAIN" "WIN"] }
    cursed-win   { return [$T "nulle (gain annulé par la règle des 50 coups)" "draw (win spoiled by the 50-move rule)"] }
    draw         { return [$T "NULLE" "DRAW"] }
    blessed-loss { return [$T "nulle (perte sauvée par la règle des 50 coups)" "draw (loss saved by the 50-move rule)"] }
    loss         { return [$T "PERTE" "LOSS"] }
  }
  return $wdl
}

### Report text for the current position
proc ::moderne::syzygy::rapport {} {
  set T ::moderne::tr
  set n [init]
  if {$n == 0} {
    return [$T \
"Aucune table Syzygy chargée.\n\nIndique le dossier de tes tables (fichiers .rtbw et .rtbz) avec le bouton « Dossier Syzygy… » ci-dessous. Elles se téléchargent par exemple sur tablebase.lichess.ovh (3-4-5 pièces : environ 1 Go) ; il faut un jeu complet (toutes les finales jusqu'à N pièces) pour sonder toutes les positions." \
"No Syzygy tables loaded.\n\nSet your tables folder (.rtbw/.rtbz files) with the \"Syzygy folder…\" button below. A complete set (all endings up to N pieces) is needed."]
  }
  set fen [sc_pos fen]
  set r [sc_syzygy probe $fen]
  set trait [expr {[lindex [split $fen] 1] eq "w" ? [$T "Blancs au trait" "White to move"] : [$T "Noirs au trait" "Black to move"]}]
  set txt "Syzygy ($n [$T pièces pieces]) • $trait\n\n"
  if {![llength $r]} {
    append txt [$T "Position non couverte : trop de pièces, roque encore possible, ou table absente." \
                   "Position not covered: too many pieces, castling rights, or missing table."]
    return $txt
  }
  if {[lindex $r 0] eq "mate"} { return "$txt[$T "Échec et mat." "Checkmate."]" }
  if {[lindex $r 0] eq "stalemate"} { return "$txt[$T "Pat." "Stalemate."]" }
  lassign $r wdl dtz meilleur coups
  append txt "[$T "Résultat" "Result"] : [nomResultat $wdl]"
  if {$wdl ne "draw"} { append txt "  (DTZ $dtz)" }
  append txt "\n[$T "Meilleur coup" "Best move"] : [san $fen $meilleur]\n"
  # Ranked moves: from the side to move's point of view, the result of a move
  # is the inverse of the opponent's after that move (Fathom already gives
  # it from the point of view of the side playing the move).
  foreach {cat titreFr titreEn tri} {
    win          "Coups gagnants"  "Winning moves"   increasing
    cursed-win   "Gains annulés par la règle des 50 coups" "Wins spoiled by the 50-move rule" increasing
    draw         "Coups annulants" "Drawing moves"   increasing
    blessed-loss "Pertes sauvées par la règle des 50 coups" "Losses saved by the 50-move rule" decreasing
    loss         "Coups perdants"  "Losing moves"    decreasing
  } {
    set l {}
    foreach c $coups {
      lassign $c uci w d
      if {$w eq $cat} { lappend l [list $uci $d] }
    }
    if {![llength $l]} { continue }
    append txt "\n[$T $titreFr $titreEn] :\n "
    foreach c [lsort -integer -$tri -index 1 $l] {
      lassign $c uci d
      if {$cat eq "draw"} {
        append txt " [san $fen $uci]"
      } else {
        append txt " [san $fen $uci] ($d)"
      }
    }
    append txt "\n"
  }
  append txt "\n[$T "Entre parenthèses : DTZ, nombre de demi-coups avant la prochaine prise ou le prochain coup de pion dans le jeu parfait." "In brackets: DTZ, plies to the next capture or pawn move with perfect play."]"
  return $txt
}

################################################################################
### Lichess's online tablebase (default source of the endgame window): up to
### 7 pieces, nothing to download. https://tablebase.lichess.ovh
################################################################################

namespace eval ::moderne::syzygy { variable enLigne ; array set enLigne {} }

### Saved choice from before (local tables never set up, old sources): Lichess
if {![info exists ::tbOnline] || $::tbOnline in {Nalimov Shredder K4it-Nalimov} ||
    ($::tbOnline eq "Syzygy" && $::moderne::syzygy::chemin eq {})} {
  set ::tbOnline Lichess
}

proc ::moderne::syzygy::nbPieces {fen} {
  regexp -all {[pnbrqkPNBRQK]} [lindex [split $fen] 0]
}

### Shows the result of the board's position in the window's text
proc ::moderne::syzygy::lichess {} {
  variable enLigne
  set fen [sc_pos fen]
  set cle [join [lrange [split $fen] 0 3]]
  set T ::moderne::tr
  if {[nbPieces $fen] > 7} {
    afficher [$T "Table de Lichess (en ligne) : jusqu'à 7 pièces.\n\nCette position a [nbPieces $fen] pièces." \
                 "Lichess tablebase (online): up to 7 pieces.\n\nThis position has [nbPieces $fen] pieces."]
    return
  }
  if {[info exists enLigne($cle)] && $enLigne($cle) ne "attente"} {
    montrer [donneesLichess $fen $enLigne($cle)]
    return
  }
  afficher [$T "Table de Lichess : interrogation…" "Lichess tablebase: asking…"]
  if {[info exists enLigne($cle)]} { return }
  set enLigne($cle) attente
  set url "https://tablebase.lichess.ovh/standard?fen=[string map {{ } _} $fen]"
  ::moderne::direct::lireJson $url [list ::moderne::syzygy::lichessRecu $cle $fen]
}

proc ::moderne::syzygy::lichessRecu {cle fen v} {
  variable enLigne
  if {$v eq {}} {
    unset enLigne($cle)
    if {[join [lrange [split [sc_pos fen] 0 3]] eq $cle} {
      afficher [::moderne::tr "Table de Lichess injoignable (pas d'internet ?)." "Lichess tablebase unreachable (no internet?)."]
    }
    return
  }
  set enLigne($cle) $v
  if {[join [lrange [split [sc_pos fen]] 0 3]] eq $cle} { montrer [donneesLichess $fen $v] }
}

### A message instead of the moves (no answer, too many pieces…)
proc ::moderne::syzygy::afficher {txt} {
  montrer [dict create message $txt]
}

### Same layout as the local tables' report
proc ::moderne::syzygy::rapportLichess {fen v} {
  set T ::moderne::tr
  set trait [expr {[lindex [split $fen] 1] eq "w" ? [$T "Blancs au trait" "White to move"] : [$T "Noirs au trait" "Black to move"]}]
  set txt "Lichess ([$T "en ligne, jusqu'à 7 pièces" "online, up to 7 pieces"]) • $trait\n\n"
  if {[::moderne::json::get $v checkmate false] eq "true"} { return "$txt[$T "Échec et mat." "Checkmate."]" }
  if {[::moderne::json::get $v stalemate false] eq "true"} { return "$txt[$T "Pat." "Stalemate."]" }
  set cat [::moderne::json::get $v category {}]
  if {$cat in {unknown maybe-win maybe-loss {}}} {
    return "$txt[$T "Position non couverte par la table." "Position not covered by the tablebase."]"
  }
  append txt "[$T "Résultat" "Result"] : [nomResultat $cat]"
  set dtm [::moderne::json::get $v dtm {}]
  set dtz [::moderne::json::get $v dtz {}]
  if {$cat ne "draw"} {
    if {$dtm ne {} && $dtm ne "null"} { append txt "  ([$T "mat en" "mate in"] [expr {(abs($dtm) + 1) / 2}])" } \
    elseif {$dtz ne {} && $dtz ne "null"} { append txt "  (DTZ [expr {abs($dtz)}])" }
  }
  set coups [::moderne::json::get $v moves {}]
  if {[llength $coups]} {
    append txt "\n[$T "Meilleur coup" "Best move"] : [san $fen [::moderne::json::get [lindex $coups 0] uci {}]]\n"
  }
  # a move's category is the opponent's after it: turned to the side to move's
  set inverse {loss win win loss cursed-win blessed-loss blessed-loss cursed-win draw draw}
  foreach {c titreFr titreEn} {
    win          "Coups gagnants"  "Winning moves"
    cursed-win   "Gains annulés par la règle des 50 coups" "Wins spoiled by the 50-move rule"
    draw         "Coups annulants" "Drawing moves"
    blessed-loss "Pertes sauvées par la règle des 50 coups" "Losses saved by the 50-move rule"
    loss         "Coups perdants"  "Losing moves"
  } {
    set l {}
    foreach m $coups {
      set mc [::moderne::json::get $m category {}]
      if {![dict exists $inverse $mc] || [dict get $inverse $mc] ne $c} { continue }
      set d [::moderne::json::get $m dtm {}]
      if {$d eq {} || $d eq "null"} { set d [::moderne::json::get $m dtz {}] }
      set s [san $fen [::moderne::json::get $m uci {}]]
      lappend l [expr {$c eq "draw" || $d eq {} || $d eq "null" ? $s : "$s ([expr {abs($d)}])"}]
    }
    if {![llength $l]} { continue }
    append txt "\n[$T $titreFr $titreEn] :\n  [join $l {  }]\n"
  }
  append txt "\n[$T "Entre parenthèses : nombre de demi-coups avant le mat (ou avant la prochaine prise ou le prochain coup de pion), dans le jeu parfait." "In brackets: plies to mate (or to the next capture or pawn move), with perfect play."]"
  return $txt
}

################################################################################
### The window's view, as the opening library: the position's result, then
### one row per move with its result (win / draw / loss, coloured as on
### Lichess), DTM and DTZ. Hover: the move's arrow on the board; click:
### the move is played.
################################################################################

namespace eval ::moderne::syzygy {
  variable donnees {}     ;# what the view shows (dict)
  variable survolI -1
}

proc ::moderne::syzygy::T {fr en} { return [::moderne::tr $fr $en] }

### UCI move -> SAN in English (for the board), or {}
proc ::moderne::syzygy::sanBrut {fen uci} {
  set r {}
  sc_game push
  catch {
    sc_game startBoard $fen
    set r [string trim [sc_move addUCI $uci]]
  }
  sc_game pop
  return $r
}

proc ::moderne::syzygy::trait {fen} {
  expr {[lindex [split $fen] 1] eq "w" ? [T "Blancs au trait" "White to move"] : [T "Noirs au trait" "Black to move"]}
}

### The view's data from Lichess's answer
proc ::moderne::syzygy::donneesLichess {fen v} {
  set d [dict create source [T "Lichess • en ligne, jusqu'à 7 pièces" "Lichess • online, up to 7 pieces"] trait [trait $fen]]
  if {[::moderne::json::get $v checkmate false] eq "true"} { dict set d message [T "Échec et mat." "Checkmate."] ; return $d }
  if {[::moderne::json::get $v stalemate false] eq "true"} { dict set d message [T "Pat." "Stalemate."] ; return $d }
  set cat [::moderne::json::get $v category {}]
  if {$cat in {unknown maybe-win maybe-loss {}}} {
    dict set d message [T "Position non couverte par la table." "Position not covered by the tablebase."]
    return $d
  }
  dict set d cat $cat
  dict set d dtm [absolu [::moderne::json::get $v dtm {}]]
  dict set d dtz [absolu [::moderne::json::get $v dtz {}]]
  # a move's category is the opponent's after it: turned to the side to move's
  set inverse {loss win win loss cursed-win blessed-loss blessed-loss cursed-win draw draw}
  set coups {}
  foreach m [::moderne::json::get $v moves {}] {
    set mc [::moderne::json::get $m category {}]
    if {![dict exists $inverse $mc]} { continue }
    set uci [::moderne::json::get $m uci {}]
    set san [sanBrut $fen $uci]
    if {$san eq {}} { continue }
    lappend coups [list $san [dict get $inverse $mc] [absolu [::moderne::json::get $m dtm {}]] \
                       [absolu [::moderne::json::get $m dtz {}]]]
  }
  dict set d coups $coups
  return $d
}

### |n|, or {} when there is no number
proc ::moderne::syzygy::absolu {n} {
  if {![string is integer -strict $n]} { return {} }
  return [expr {abs($n)}]
}

### The view's data from the local tables
proc ::moderne::syzygy::donneesLocales {} {
  set n [init]
  set fen [sc_pos fen]
  set d [dict create source "Syzygy • $n [T pièces pieces]" trait [trait $fen]]
  if {$n == 0} {
    dict set d message [T "Aucune table Syzygy chargée : indique le dossier de tes tables avec le bouton « Dossier Syzygy… »." \
                          "No Syzygy tables loaded: set your tables folder with the \"Syzygy folder…\" button."]
    return $d
  }
  set r [sc_syzygy probe $fen]
  if {![llength $r]} {
    dict set d message [T "Position non couverte : trop de pièces, roque encore possible, ou table absente." \
                          "Position not covered: too many pieces, castling rights, or missing table."]
    return $d
  }
  if {[lindex $r 0] eq "mate"} { dict set d message [T "Échec et mat." "Checkmate."] ; return $d }
  if {[lindex $r 0] eq "stalemate"} { dict set d message [T "Pat." "Stalemate."] ; return $d }
  lassign $r wdl dtz meilleur coups
  dict set d cat $wdl
  dict set d dtm {}
  dict set d dtz [absolu $dtz]
  # best first: quickest win, then draws, then the longest loss
  set rang {win 0 cursed-win 1 draw 2 blessed-loss 3 loss 4}
  set l {}
  foreach c $coups {
    lassign $c uci w dz
    set san [sanBrut $fen $uci]
    if {$san eq {} || ![dict exists $rang $w]} { continue }
    set dz [absolu $dz]
    set cle [expr {$dz eq {} ? 0 : $dz}]
    if {$w in {loss blessed-loss}} { set cle [expr {-$cle}] }
    lappend l [list $san $w {} $dz [dict get $rang $w] $cle]
  }
  set l [lsort -integer -index 5 $l]
  dict set d coups [lmap x [lsort -integer -index 4 $l] {lrange $x 0 3}]
  return $d
}

### Label and colour of a result
proc ::moderne::syzygy::style {cat} {
  switch -- $cat {
    win          { return [list [T Gain Win] #629924] }
    cursed-win   { return [list [T "Gain annulé (50 coups)" "Win spoiled (50 moves)"] #8a9a6a] }
    draw         { return [list [T Nulle Draw] #8b8b8b] }
    blessed-loss { return [list [T "Perte sauvée (50 coups)" "Loss saved (50 moves)"] #a87a7a] }
    loss         { return [list [T Perte Loss] #cc3333] }
  }
  return [list $cat #8b8b8b]
}

### The canvas in place of the text (created once)
proc ::moderne::syzygy::vue {} {
  set f .tbWin.pos
  if {![winfo exists $f]} { return {} }
  set cv $f.vue
  if {![winfo exists $cv]} {
    canvas $cv -highlightthickness 0 -borderwidth 0 -background [::moderne::c surface] -yscrollincrement 1
    bind $cv <Configure> ::moderne::syzygy::dessiner
    bind $cv <Motion> {::moderne::syzygy::survol %y}
    bind $cv <Leave> {::moderne::syzygy::survol -1}
    bind $cv <ButtonRelease-1> {::moderne::syzygy::clic %y}
    bind $cv <MouseWheel> {%W yview scroll [expr {%D > 0 ? -40 : 40}] units}
    bind $cv <Button-4> {%W yview scroll -40 units}
    bind $cv <Button-5> {%W yview scroll 40 units}
  }
  if {![winfo ismapped $cv]} {
    catch {pack forget $f.text}
    pack $cv -side top -fill both -expand yes
  }
  return $cv
}

proc ::moderne::syzygy::montrer {d} {
  variable donnees
  variable survolI
  set donnees $d
  set survolI -1
  if {[vue] eq {}} { return }
  catch {::moderne::biblio::flecheSurvol {}}
  .tbWin.pos.vue yview moveto 0
  dessiner
}

proc ::moderne::syzygy::dessiner {} {
  variable donnees
  variable geo
  set cv .tbWin.pos.vue
  if {![winfo exists $cv]} { return }
  $cv delete all
  set larg [winfo width $cv] ; if {$larg < 50} { set larg 420 }
  set texte [::moderne::c texte] ; set doux [::moderne::c texteDoux]
  set fh [font metrics font_Regular -linespace]
  set hl [expr {$fh + 12}]
  set x0 12
  set y 10
  # the position: its result, the side to move, the source
  if {[dict exists $donnees cat]} {
    lassign [style [dict get $donnees cat]] lib coul
    set t [$cv create text [expr {$x0 + 8}] [expr {$y + 4}] -anchor nw -text $lib -font font_Bold -fill white]
    lassign [$cv bbox $t] bx1 by1 bx2 by2
    $cv create rectangle $x0 $y [expr {$bx2 + 8}] [expr {$by2 + 4}] -fill $coul -outline {}
    $cv raise $t
    set info [dict get $donnees trait]
    set dtm [dict get $donnees dtm] ; set dtz [dict get $donnees dtz]
    if {[dict get $donnees cat] ne "draw"} {
      if {$dtm ne {}} {
        append info "  •  [T "mat en" "mate in"] [expr {($dtm + 1) / 2}] [T coups moves]"
      } elseif {$dtz ne {}} { append info "  •  DTZ $dtz" }
    }
    $cv create text [expr {$bx2 + 18}] [expr {($y + $by2 + 4) / 2}] -anchor w -text $info -font font_Regular -fill $texte
    set y [expr {$by2 + 10}]
  } elseif {[dict exists $donnees trait]} {
    $cv create text $x0 $y -anchor nw -text [dict get $donnees trait] -font font_Regular -fill $texte
    set y [expr {$y + $fh + 6}]
  }
  if {[dict exists $donnees source]} {
    $cv create text $x0 $y -anchor nw -text [dict get $donnees source] -font font_Small -fill $doux
    set y [expr {$y + [font metrics font_Small -linespace] + 8}]
  }
  if {[dict exists $donnees message]} {
    $cv create text $x0 [expr {$y + 8}] -anchor nw -text [dict get $donnees message] -font font_Regular -fill $doux \
        -width [expr {$larg - 2 * $x0}]
    set geo {}
    $cv configure -scrollregion [list 0 0 $larg [expr {$y + 60}]]
    return
  }
  set coups [expr {[dict exists $donnees coups] ? [dict get $donnees coups] : {}}]
  # columns: move, result, DTM (when known), DTZ
  set avecDtm 0
  foreach c $coups { if {[lindex $c 2] ne {}} { set avecDtm 1 } }
  # (side by side, as on Lichess: the widest badge sets the result column)
  set lBadge [font measure font_Small [T Perte Loss]]
  foreach c $coups { set lBadge [expr {max($lBadge, [font measure font_Small [lindex [style [lindex $c 1]] 0]])}] }
  set chiffre [font measure font_Regular 0]
  set xR [expr {$x0 + 8 * $chiffre}]
  set xM [expr {$xR + $lBadge + 14 + 7 * $chiffre}]
  set xZ [expr {$xM + ($avecDtm ? 7 * $chiffre : 0)}]
  foreach {x ancre lib bulle} [list $x0 w [T Coup Move] {} $xR w [T Résultat Result] {} \
      $xM e [expr {$avecDtm ? "DTM" : ""}] [T "Distance au mat : nombre de demi-coups avant le mat, dans le jeu parfait (18 = mat en 9 coups)" "Distance to mate: plies to mate, with perfect play (18 = mate in 9 moves)"] \
      $xZ e DTZ [T "Distance au zéro : demi-coups avant la prochaine prise ou le prochain coup de pion, dans le jeu parfait. Au-delà de 100, la règle des 50 coups pourrait s'appliquer." "Distance to zeroing: plies to the next capture or pawn move, with perfect play. Beyond 100, the 50-move rule could apply."]] {
    if {$lib eq {}} { continue }
    set id [$cv create text $x [expr {$y + $hl / 2}] -anchor $ancre -text $lib -font font_Small -fill $doux]
    if {$bulle ne {}} {
      $cv bind $id <Enter> [list ::moderne::syzygy::bulle $cv $x [expr {$y + $hl}] $bulle]
      $cv bind $id <Leave> [list $cv delete bulle]
    }
  }
  set y [expr {$y + $hl}]
  $cv create line 0 $y $larg $y -fill [::moderne::c bordure]
  set geo [list $y $hl [llength $coups]]
  set i 0
  foreach c $coups {
    lassign $c san cat dtm dtz
    set y1 [expr {$y + $i * $hl}] ; set y2 [expr {$y1 + $hl}] ; set ym [expr {($y1 + $y2) / 2}]
    $cv create rectangle 0 $y1 $larg $y2 -fill [expr {$i % 2 ? [::moderne::c ligneAlt] : [::moderne::c surface]}] \
        -outline {} -tags [list fond f$i]
    $cv create text $x0 $ym -anchor w -text [::trans $san] -font font_Bold -fill $texte
    lassign [style $cat] lib coul
    set t [$cv create text [expr {$xR + 7}] $ym -anchor w -text $lib -font font_Small -fill white]
    lassign [$cv bbox $t] bx1 by1 bx2 by2
    $cv create rectangle $xR [expr {$by1 - 2}] [expr {$bx2 + 7}] [expr {$by2 + 2}] -fill $coul -outline {}
    $cv raise $t
    if {$dtm ne {}} { $cv create text $xM $ym -anchor e -text $dtm -font font_Regular -fill $texte }
    if {$dtz ne {} && $cat ne "draw"} { $cv create text $xZ $ym -anchor e -text $dtz -font font_Regular -fill $texte }
    incr i
  }
  $cv configure -scrollregion [list 0 0 $larg [expr {$y + $i * $hl + 10}]]
}

proc ::moderne::syzygy::bulle {cv x y texte} {
  $cv delete bulle
  set t [$cv create text 0 0 -anchor nw -text $texte -font font_Small -fill [::moderne::c texteFort] \
      -width 260 -tags bulle]
  lassign [$cv bbox $t] bx1 by1 bx2 by2
  set lw [expr {$bx2 - $bx1 + 12}] ; set lh [expr {$by2 - $by1 + 8}]
  set px [expr {min($x, [winfo width $cv] - $lw - 4)}]
  $cv coords $t [expr {$px + 6}] [expr {$y + 4}]
  set r [$cv create rectangle $px $y [expr {$px + $lw}] [expr {$y + $lh}] \
      -fill [::moderne::c surface2] -outline [::moderne::c bordure] -tags bulle]
  $cv raise $t $r
}

### Row under the pointer, or -1
proc ::moderne::syzygy::ligneSous {y} {
  variable geo
  set cv .tbWin.pos.vue
  if {![info exists geo] || $geo eq {} || $y < 0 || ![winfo exists $cv]} { return -1 }
  lassign $geo y0 hl n
  set y [$cv canvasy $y]
  if {$y < $y0} { return -1 }
  set i [expr {int(($y - $y0) / $hl)}]
  return [expr {$i < $n ? $i : -1}]
}

proc ::moderne::syzygy::survol {y} {
  variable donnees
  variable survolI
  set cv .tbWin.pos.vue
  set i [ligneSous $y]
  if {$i == $survolI} { return }
  if {$survolI >= 0} {
    $cv itemconfigure f$survolI -fill [expr {$survolI % 2 ? [::moderne::c ligneAlt] : [::moderne::c surface]}]
  }
  set survolI $i
  if {$i < 0} {
    $cv configure -cursor {}
    catch {::moderne::biblio::flecheSurvol {}}
    return
  }
  $cv itemconfigure f$i -fill [::moderne::c survol]
  $cv configure -cursor hand2
  catch {::moderne::biblio::flecheSurvol [lindex [dict get $donnees coups] $i 0]}
}

proc ::moderne::syzygy::clic {y} {
  variable donnees
  set i [ligneSous $y]
  if {$i < 0} { return }
  set san [lindex [dict get $donnees coups] $i 0]
  catch {::moderne::biblio::flecheSurvol {}}
  addSanMove $san -animate
  updateBoard -pgn
}

### End Siby
