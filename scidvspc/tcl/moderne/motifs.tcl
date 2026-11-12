
###
### Siby: Search › Material and patterns, modernized presentation
###
### Same search as SCID (sc_search material, same settings: pMin, pMax,
### pattBool…, stored in and loaded from .sso files), but in a
### readable window:
###   1. Material: for each piece, from how many to how many for White and
###      for Black ("Current position", "Allow all", common
###      endgames); material difference;
###   2. Pieces on squares: up to 10 conditions such as "there is a
###      white knight on d5", "there is no black pawn on the e-file"
###      (common structures: isolated pawn, Maroczy…);
###   3. Options: moves concerned, duration, bishop colors, reversed
###      colors, final position only;
###   4. What happens to the game list (new search, within the
###      current results, add to the results).
###

namespace eval ::moderne::motifs {
  variable w .motifsWin
  variable ligne           ;# ligne(i,cond|piece|col|rang): display of the conditions
  array set ligne {}
}

proc ::moderne::motifs::T {fr en} { return [::moderne::tr $fr $en] }

### Pieces: SCID code → displayed name
proc ::moderne::motifs::pieces {} {
  return [list \
      ? [T "Choisir…" "Choose…"] \
      wk [T "Roi blanc" "White king"]       bk [T "Roi noir" "Black king"] \
      wq [T "Dame blanche" "White queen"]   bq [T "Dame noire" "Black queen"] \
      wr [T "Tour blanche" "White rook"]    br [T "Tour noire" "Black rook"] \
      wb [T "Fou blanc" "White bishop"]     bb [T "Fou noir" "Black bishop"] \
      wn [T "Cavalier blanc" "White knight"] bn [T "Cavalier noir" "Black knight"] \
      wp [T "Pion blanc" "White pawn"]      bp [T "Pion noir" "Black pawn"]]
}

proc ::moderne::motifs::ouvrir {} {
  variable w
  global pMin pMax
  if {[winfo exists $w]} { raise $w ; focus $w ; return }
  toplevel $w
  wm title $w [T "Rechercher : matériel et pièces sur des cases" "Search: material and pieces on squares"]
  catch {::moderne::repeindre $w}
  set fond [::moderne::c fond]
  $w configure -background $fond
  bind $w <Escape> [list destroy $w]
  bind $w <F1> { helpWindow Searches Material }

  set c [ttk::frame $w.c -padding {16 12 16 8}]
  pack $c -side top -fill both -expand 1

  ### 1. Material
  ttk::label $c.t1 -text [T "1. Matériel" "1. Material"] -font font_Bold
  ttk::label $c.d1 -foreground [::moderne::c texteDoux] -wraplength 640 -justify left -text [T \
      "Pour chaque pièce, le nombre voulu chez les Blancs et chez les Noirs (de … à …). Les rois sont toujours là." \
      "For each piece, how many White and Black should have (from … to …). Kings are always there."]
  grid $c.t1 -row 0 -column 0 -sticky w -pady {0 2}
  grid $c.d1 -row 1 -column 0 -sticky w -pady {0 6}
  set m [ttk::frame $c.mat]
  grid $m -row 2 -column 0 -sticky w
  ttk::label $m.hb -text [T "Blancs" "White"] -font font_Bold
  ttk::label $m.hn -text [T "Noirs" "Black"] -font font_Bold
  grid x $m.hb - - x $m.hn - - -padx 4
  set r 1
  foreach {p nom} [list q [T Dames Queens] r [T Tours Rooks] b [T Fous Bishops] n [T Cavaliers Knights] \
                        m [T "Pièces mineures (F+C)" "Minor pieces (B+N)"] p [T Pions Pawns]] {
    set max [expr {$p eq "p" ? 8 : ($p eq "m" ? 4 : 2)}]
    ttk::label $m.n$p -text $nom -width 22
    foreach coul {w b} {
      ttk::label $m.i$coul$p -image $coul${p}20
      ttk::spinbox $m.min$coul$p -from 0 -to $max -width 3 -textvariable pMin($coul$p) -justify center
      ttk::label $m.a$coul$p -text [T "à" "to"] -foreground [::moderne::c texteDoux]
      ttk::spinbox $m.max$coul$p -from 0 -to $max -width 3 -textvariable pMax($coul$p) -justify center
    }
    grid $m.n$p $m.iw$p $m.minw$p $m.aw$p $m.maxw$p $m.ib$p $m.minb$p $m.ab$p $m.maxb$p -padx 4 -pady 2 -sticky w
    grid configure $m.ib$p -padx {24 4}
    incr r
  }
  set b [ttk::frame $c.mb]
  grid $b -row 3 -column 0 -sticky w -pady {8 4}
  ttk::button $b.pos -text [T "Comme la position actuelle" "As in the current position"] -command ::moderne::motifs::commePosition
  ttk::button $b.tout -text [T "Tout autoriser" "Allow anything"] -command ::search::material::any
  ttk::button $b.zero -text [T "Tout à zéro" "All to zero"] -command ::search::material::zero
  pack $b.pos $b.tout $b.zero -side left -padx {0 6}
  set d [ttk::frame $c.diff]
  grid $d -row 4 -column 0 -sticky w -pady {4 0}
  ttk::label $d.l -text [T "Avantage matériel (Blancs − Noirs ; D=9 T=5 F=3 C=3 p=1) : de" "Material balance (White − Black; Q=9 R=5 B=3 N=3 P=1): from"]
  ttk::spinbox $d.min -from -40 -to 40 -width 4 -textvariable ::minMatDiff -justify center
  ttk::label $d.a -text [T "à" "to"]
  ttk::spinbox $d.max -from -40 -to 40 -width 4 -textvariable ::maxMatDiff -justify center
  ttk::button $d.peu -text [T "Peu importe" "Any"] -command {set ::minMatDiff -40 ; set ::maxMatDiff 40}
  ttk::button $d.bl -text [T "Blancs mieux" "White ahead"] -command {set ::minMatDiff 1 ; set ::maxMatDiff 40}
  ttk::button $d.eg -text [T "Égal" "Equal"] -command {set ::minMatDiff 0 ; set ::maxMatDiff 0}
  ttk::button $d.no -text [T "Noirs mieux" "Black ahead"] -command {set ::minMatDiff -40 ; set ::maxMatDiff -1}
  pack $d.l $d.min $d.a $d.max -side left -padx {0 4}
  pack $d.peu $d.bl $d.eg $d.no -side left -padx {6 0}

  ttk::separator $c.s1 -orient horizontal
  grid $c.s1 -row 5 -column 0 -sticky ew -pady 12

  ### 2. Pieces on squares
  ttk::label $c.t2 -text [T "2. Pièces sur des cases (facultatif)" "2. Pieces on squares (optional)"] -font font_Bold
  ttk::label $c.d2 -foreground [::moderne::c texteDoux] -wraplength 640 -justify left -text [T \
      "Exemples : « il y a un Cavalier blanc en d5 » ; « il n'y a pas de Pion noir sur la colonne e » (rangée : toutes). Les lignes sans pièce choisie ne comptent pas." \
      "Examples: \"there is a White knight on d5\"; \"there is no Black pawn on the e-file\" (rank: any). Rows with no piece chosen are ignored."]
  catch {::moderne::enBulle $c.d2}
  grid $c.t2 -row 6 -column 0 -sticky w -pady {0 2}
  grid $c.d2 -row 7 -column 0 -sticky w -pady {0 6}
  set g [ttk::frame $c.patt]
  grid $g -row 8 -column 0 -sticky w
  set noms {}
  foreach {code nom} [pieces] { lappend noms $nom }
  for {set i 1} {$i <= $::nPatterns} {incr i} {
    set col [expr {(($i - 1) / 5) * 7}]
    set row [expr {($i - 1) % 5}]
    ttk::combobox $g.c$i -state readonly -width 13 -textvariable ::moderne::motifs::ligne($i,cond) \
        -values [list [T "il y a" "there is"] [T "il n'y a pas" "there is no"]]
    ttk::combobox $g.p$i -state readonly -width 14 -textvariable ::moderne::motifs::ligne($i,piece) -values $noms
    ttk::label $g.e$i -text [T "en" "on"]
    ttk::combobox $g.f$i -state readonly -width 7 -textvariable ::moderne::motifs::ligne($i,col) \
        -values [concat [list [T "col. ?" "file ?"]] {a b c d e f g h}]
    ttk::combobox $g.r$i -state readonly -width 7 -textvariable ::moderne::motifs::ligne($i,rang) \
        -values [concat [list [T "rang. ?" "rank ?"]] {1 2 3 4 5 6 7 8}]
    grid $g.c$i -row $row -column $col -padx {0 4} -pady 2
    grid $g.p$i -row $row -column [expr {$col + 1}] -padx 2 -pady 2
    grid $g.e$i -row $row -column [expr {$col + 2}] -padx 2
    grid $g.f$i -row $row -column [expr {$col + 3}] -padx 2
    grid $g.r$i -row $row -column [expr {$col + 4}] -padx {2 18}
  }
  set pb [ttk::frame $c.pb]
  grid $pb -row 9 -column 0 -sticky w -pady {8 0}
  ttk::button $pb.eff -text [T "Effacer les conditions" "Clear conditions"] -command {clearPatterns ; ::moderne::motifs::lireMotifs}
  pack $pb.eff -side left -padx {0 6}

  ttk::separator $c.s2 -orient horizontal
  grid $c.s2 -row 10 -column 0 -sticky ew -pady 12

  ### 3. Options
  ttk::label $c.t3 -text [T "3. Options" "3. Options"] -font font_Bold
  grid $c.t3 -row 11 -column 0 -sticky w -pady {0 4}
  set o [ttk::frame $c.opt]
  grid $o -row 12 -column 0 -sticky w
  ttk::checkbutton $o.fin -text [T "Seulement la position finale de chaque partie" "Only the final position of each game"] \
      -variable ::matchEnd -command ::moderne::motifs::etatOptions
  ttk::label $o.l1 -text [T "Entre le coup" "Between move"]
  ttk::spinbox $o.min -from 1 -to 999 -width 4 -textvariable ::minMoveNum -justify center
  ttk::label $o.l2 -text [T "et le coup" "and move"]
  ttk::spinbox $o.max -from 1 -to 999 -width 4 -textvariable ::maxMoveNum -justify center
  ttk::label $o.l3 -text [T ", et pendant au moins" ", for at least"]
  ttk::spinbox $o.dur -from 1 -to 99 -width 3 -textvariable ::minHalfMoves -justify center
  ttk::label $o.l4 -text [T "demi-coup(s) d'affilée" "half-move(s) in a row"]
  grid $o.fin - - - - - - -sticky w -pady 2
  grid $o.l1 $o.min $o.l2 $o.max $o.l3 $o.dur $o.l4 -sticky w -padx {0 4} -pady 2
  set fo [ttk::frame $o.fous]
  grid $fo - - - - - - -sticky w -pady 2
  ttk::label $fo.l -text [T "Fous (quand chaque camp n'en a qu'un) :" "Bishops (when each side has one):"]
  ttk::radiobutton $fo.e -text [T "peu importe" "any"] -variable ::oppBishops -value Either
  ttk::radiobutton $fo.s -text [T "de même couleur" "same colour"] -variable ::oppBishops -value Same
  ttk::radiobutton $fo.o -text [T "de couleurs opposées" "opposite colours"] -variable ::oppBishops -value Opposite
  pack $fo.l $fo.e $fo.s $fo.o -side left -padx {0 8}
  ttk::checkbutton $o.inv -text [T "Chercher aussi avec les couleurs inversées (Blancs ↔ Noirs)" "Also search with colours reversed (White ↔ Black)"] \
      -variable ::ignoreColors
  grid $o.inv - - - - - - -sticky w -pady 2

  ttk::separator $c.s3 -orient horizontal
  grid $c.s3 -row 13 -column 0 -sticky ew -pady 12

  ### 4. Results
  ttk::label $c.t4 -text [T "4. Liste des parties" "4. Game list"] -font font_Bold
  grid $c.t4 -row 14 -column 0 -sticky w -pady {0 4}
  set r4 [ttk::frame $c.res]
  grid $r4 -row 15 -column 0 -sticky w
  ttk::radiobutton $r4.n -text [T "Nouvelle recherche (toute la base)" "New search (whole database)"] -variable ::search::filter::operation -value 2
  ttk::radiobutton $r4.e -text [T "Chercher dans les résultats actuels" "Search within current results"] -variable ::search::filter::operation -value 0
  ttk::radiobutton $r4.a -text [T "Ajouter aux résultats actuels" "Add to current results"] -variable ::search::filter::operation -value 1
  pack $r4.n $r4.e $r4.a -side left -padx {0 14}

  ### Bottom: progress, buttons, result
  set bas [ttk::frame $w.bas -padding {16 6 16 12}]
  pack $bas -side bottom -fill x
  canvas $bas.prog -height 6 -width 240 -highlightthickness 0 -borderwidth 0 -background [::moderne::c surface2]
  $bas.prog create rectangle 0 0 0 6 -fill [::moderne::c accent] -outline {} -tags bar
  ttk::label $bas.etat -foreground [::moderne::c texteDoux] -text {}
  ttk::button $bas.ok -text [T "Rechercher" "Search"] -style Accent.TButton -command ::moderne::motifs::lancer
  catch {$bas.ok configure -style Accent.TButton}
  ttk::button $bas.stop -text [T "Arrêter" "Stop"] -state disabled -command sc_progressBar
  ttk::button $bas.sauver -text [T "Enregistrer les réglages…" "Save settings…"] -command ::moderne::motifs::sauver
  ttk::button $bas.fermer -text [T "Fermer" "Close"] -command [list destroy $w]
  pack $bas.sauver -side left
  pack $bas.prog -side left -padx 12
  pack $bas.etat -side left
  pack $bas.fermer $bas.stop $bas.ok -side right -padx {6 0}
  bind $w <Return> [list $bas.ok invoke]

  lireMotifs
  etatOptions
  ::utils::tooltip::Set $bas.sauver [T "Enregistre ces réglages dans un fichier .sso (Rechercher › Utiliser un fichier de recherche pour les reprendre)" "Saves these settings in a .sso file"]
}

### Conditions: SCID globals → display
proc ::moderne::motifs::lireMotifs {} {
  variable ligne
  array set nom [pieces]
  for {set i 1} {$i <= $::nPatterns} {incr i} {
    if {![info exists ::pattBool($i)]} { set ::pattBool($i) Yes }
    set ligne($i,cond) [expr {$::pattBool($i) eq "No" ? [T "il n'y a pas" "there is no"] : [T "il y a" "there is"]}]
    set p $::pattPiece($i)
    set ligne($i,piece) [expr {[info exists nom($p)] ? $nom($p) : $nom(?)}]
    set ligne($i,col) [expr {$::pattFyle($i) eq "?" ? [T "col. ?" "file ?"] : $::pattFyle($i)}]
    set ligne($i,rang) [expr {$::pattRank($i) eq "?" ? [T "rang. ?" "rank ?"] : $::pattRank($i)}]
  }
}

### Display → SCID globals
proc ::moderne::motifs::ecrireMotifs {} {
  variable ligne
  set codes {}
  foreach {code nom} [pieces] { dict set codes $nom $code }
  for {set i 1} {$i <= $::nPatterns} {incr i} {
    set ::pattBool($i) [expr {$ligne($i,cond) eq [T "il n'y a pas" "there is no"] ? "No" : "Yes"}]
    set ::pattPiece($i) [expr {[dict exists $codes $ligne($i,piece)] ? [dict get $codes $ligne($i,piece)] : "?"}]
    set ::pattFyle($i) [expr {$ligne($i,col) in {a b c d e f g h} ? $ligne($i,col) : "?"}]
    set ::pattRank($i) [expr {$ligne($i,rang) in {1 2 3 4 5 6 7 8} ? $ligne($i,rang) : "?"}]
  }
}

proc ::moderne::motifs::etatOptions {} {
  variable w
  set e [expr {$::matchEnd ? "disabled" : "normal"}]
  foreach x {min max dur} { catch {$w.c.opt.$x configure -state $e} }
}

proc ::moderne::motifs::commePosition {} {
  global pMin pMax
  ::search::material::zero
  set bd [sc_pos board]
  for {set i 0} {$i < 64} {incr i} {
    set piece $::board::letterToPiece([string index $bd $i])
    if {$piece ne "e" && $piece ne "wk" && $piece ne "bk"} {
      incr pMin($piece) ; set pMax($piece) $pMin($piece)
    }
  }
}

### Fills the window: minimum and maximum material, and patterns (used by
### the tests)
proc ::moderne::motifs::appliquer {mins maxs motifs} {
  ::search::material::zero
  array set ::pMin $mins
  array set ::pMax $maxs
  if {[llength $motifs]} { setPatterns $motifs ; set ::ignoreColors 1 }
  lireMotifs
}

### Patterns, raising the minimum material if needed (used by the tests)
proc ::moderne::motifs::structure {motifs mins maxs} {
  foreach {k v} $mins { if {$::pMin($k) < $v} { set ::pMin($k) $v } }
  foreach {k v} $maxs { set ::pMax($k) $v }
  setPatterns $motifs
  lireMotifs
}

proc ::moderne::motifs::sauver {} {
  ecrireMotifs
  # (::search::material::save uses .sm as parent)
  set parent .sm
  if {![winfo exists .sm]} { toplevel .sm ; wm withdraw .sm }
  catch {::search::material::save}
  catch {destroy .sm}
}

proc ::moderne::motifs::lancer {} {
  variable w
  global pMin pMax pattBool pattPiece pattFyle pattRank
  ecrireMotifs
  set bas $w.bas
  busyCursor .
  $bas.stop configure -state normal
  $bas.ok configure -state disabled
  $bas.etat configure -text [T "Recherche…" "Searching…"]
  $bas.prog coords bar 0 0 0 6
  sc_progressBar $bas.prog bar [winfo width $bas.prog] 6
  set patt {}
  for {set i 1} {$i <= $::nPatterns} {incr i} {
    lappend patt -patt "$pattBool($i) $pattPiece($i) $pattFyle($i) $pattRank($i)"
  }
  set t0 [clock milliseconds]
  set code [catch {sc_search material \
      -wq [list $pMin(wq) $pMax(wq)] -bq [list $pMin(bq) $pMax(bq)] \
      -wr [list $pMin(wr) $pMax(wr)] -br [list $pMin(br) $pMax(br)] \
      -wb [list $pMin(wb) $pMax(wb)] -bb [list $pMin(bb) $pMax(bb)] \
      -wn [list $pMin(wn) $pMax(wn)] -bn [list $pMin(bn) $pMax(bn)] \
      -wm [list $pMin(wm) $pMax(wm)] -bm [list $pMin(bm) $pMax(bm)] \
      -wp [list $pMin(wp) $pMax(wp)] -bp [list $pMin(bp) $pMax(bp)] \
      -flip $::ignoreColors -filter $::search::filter::operation \
      -matchendonly $::matchEnd -range [list $::minMoveNum $::maxMoveNum] \
      -length $::minHalfMoves -bishops $::oppBishops \
      -diff [list $::minMatDiff $::maxMatDiff] {*}$patt} res]
  unbusyCursor .
  if {![winfo exists $w]} { return }
  $bas.stop configure -state disabled
  $bas.ok configure -state normal
  if {$code} {
    $bas.etat configure -text $res
    return
  }
  set n [sc_filter count]
  set duree [format %.1f [expr {([clock milliseconds] - $t0) / 1000.0}]]
  $bas.etat configure -text "[::utils::thousands $n] [expr {$n == 1 ? [T "partie trouvée" "game found"] : [T "parties trouvées" "games found"]}] ($duree s)"
  set ::glstart 1
  catch ::search::loadFirstGame
  catch ::windows::stats::Refresh
  catch {::windows::gamelist::Open}
}

### Search › Material and patterns: this window (modern theme)
proc ::moderne::motifs::installer {} {
  if {[llength [info commands ::search::material_origine]]} { return }
  if {![llength [info commands ::search::material]]} { return }
  rename ::search::material ::search::material_origine
  proc ::search::material {} {
    if {[::moderne::actif]} { ::moderne::motifs::ouvrir } else { ::search::material_origine }
  }
}
::moderne::motifs::installer
after idle ::moderne::motifs::installer

### End Siby
