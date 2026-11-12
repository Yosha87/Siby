###
### Siby: right-click menus, reviewed (2026-10-24)
###
### Each menu offers what one expects at that place, in plain words, and
### nothing that belongs in the Options:
###   - notation: copy the game (PGN) or the position (FEN), paste, move
###     symbols and evaluation, comment, variation commands only inside a
###     variation, then the cleaning commands;
###   - game list: open, copy the PGN, copy into another database, mark
###     deleted, flags (named ones only), move, hide from the list;
###   - column headings: add, hide, align, default columns;
###   - database tiles under the list: the same as in "My databases";
###   - engine lines: add the line (or all) as a variation, copy it.
###

namespace eval ::moderne::menuclic {}

proc ::moderne::menuclic::T {fr en} { return [::moderne::tr $fr $en] }

################################################################################
### Clipboard
################################################################################

### Paste: a FEN becomes the position, a PGN the game (several games: the
### import window)
proc ::moderne::menuclic::coller {} {
  set texte {}
  catch {set texte [string trim [clipboard get]]}
  if {$texte eq {}} { bell ; return }
  if {[regexp {^[pnbrqkPNBRQK1-8]+(/[pnbrqkPNBRQK1-8]+){7}\s+[wb]} $texte]} {
    pasteFEN
    return
  }
  if {[regexp {\[Event |\[White |^1\.\s*[a-hNBRQKO]} $texte] && [regexp -all {\[Event } $texte] <= 1} {
    # a game on screen: merge into it (as ChessBase) or replace it
    set remplacer 0
    if {[sc_game info halfmoves] > 0 || ![sc_pos isAt end]} {
      switch -- [choixCollage] {
        fusion { fusionner pgn $texte ; return }
        annuler { return }
        remplacer { set remplacer 1 }
      }
    }
    # (Replace the game is the answer already: not asked again whether to
    # save the game it replaces)
    set ::game::remplacerSansQuestion $remplacer
    set confirm [::game::ConfirmDiscardOnglet]
    set ::game::remplacerSansQuestion 0
    if {$confirm == 2} { return }
    if {$confirm == 0} { ::game::Save }
    sc_game push
    if {[catch {sc_game import $texte} err]} {
      sc_game pop
      importPgnGame
      return
    }
    sc_game pop
    setTrialMode 0
    sc_game new
    sc_game import $texte
    sc_move start
    updateBoard -pgn
    catch {::windows::gamelist::Refresh}
    return
  }
  importPgnGame
}

### Paste a game over a game: "fusion", "remplacer" or "annuler"
proc ::moderne::menuclic::choixCollage {} {
  set w .choixCollage
  catch {destroy $w}
  toplevel $w -background [::moderne::c surface]
  wm withdraw $w
  wm title $w [T "Coller une partie" "Paste a game"]
  wm transient $w .
  wm resizable $w 0 0
  set f [frame $w.f -background [::moderne::c surface] -padx 20 -pady 16]
  pack $f -fill both -expand 1
  label $f.q -text [T "Que faire de la partie copiée ?" "What to do with the copied game?"] -font font_Bold \
      -background [::moderne::c surface] -foreground [::moderne::c texte] -anchor w
  pack $f.q -fill x -pady {0 8}
  set b [frame $f.b -background [::moderne::c surface]]
  pack $b -fill x -pady {8 0}
  set ::moderne::menuclic::choix annuler
  ttk::button $b.f -text [T "Fusionner dans la partie" "Merge into the game"] \
      -command {set ::moderne::menuclic::choix fusion ; destroy .choixCollage}
  ttk::button $b.r -text [T "Remplacer la partie" "Replace the game"] \
      -command {set ::moderne::menuclic::choix remplacer ; destroy .choixCollage}
  ttk::button $b.a -text [T Annuler Cancel] -command {destroy .choixCollage}
  catch {$b.f configure -style Accent.TButton}
  pack $b.a $b.r $b.f -side right -padx {6 0}
  bind $w <Escape> {destroy .choixCollage}
  bind $w <Return> {set ::moderne::menuclic::choix fusion ; destroy .choixCollage}
  update idletasks
  set x [expr {[winfo rootx .] + ([winfo width .] - [winfo reqwidth $w]) / 2}]
  set y [expr {[winfo rooty .] + ([winfo height .] - [winfo reqheight $w]) / 3}]
  wm geometry $w +[expr {max(0, $x)}]+[expr {max(0, $y)}]
  wm deiconify $w
  catch {focus $b.f ; grab $w}
  tkwait window $w
  return $::moderne::menuclic::choix
}

### Merge another game into the game on screen, as ChessBase does (common
### moves once, the others as variations with their comments and symbols,
### the main line unchanged, only extended). The other game: "pgn <text>"
### or "game <base> <number>". The board stays where it was.
proc ::moderne::menuclic::fusionner {args} {
  # where we are, as a main line ply (the main line does not move)
  set n 0
  while {[sc_var level] > 0 && $n < 200} { sc_var exit ; incr n }
  set loc [sc_pos location]
  sc_game undoPoint
  if {[catch {sc_game fusion {*}$args} nb]} {
    sc_move ply $loc
    if {$nb eq "startpos"} {
      set msg [T "Les deux parties ne partent pas de la même position." "The two games do not start from the same position."]
    } else {
      set msg "[T "Fusion impossible" "Merge failed"] : $nb"
    }
    tk_messageBox -parent . -icon warning -type ok -title Siby -message $msg
    return
  }
  sc_move ply $loc
  updateBoard -pgn
  catch {::moderne::direct::annonceBreve [expr {$nb == 0 ? [T "Rien à ajouter : tous les coups y sont déjà." "Nothing to add: all the moves are already there."] \
      : [T "Partie fusionnée : $nb coups ajoutés." "Game merged: $nb moves added."]}]}
}

### PGN of games of the current database (numbers), or of its whole filter
proc ::moderne::menuclic::pgnDe {nums} {
  if {$nums eq "filtre"} {
    set tmp [file join [::moderne::gaby::dossierTemp] "siby-copie-[pid].pgn"]
    catch {file delete -force $tmp}
    sc_base export filter PGN $tmp -append 0 -starttext "" -endtext "" -comments 1 -variations 1 \
        -spaces 0 -symbols 0 -indentComments 0 -indentVariations 0 -column 0 -noMarkCodes 0 \
        -convertNullMoves 1 -newlines 1 -utf8 1 -bom 0
    set f [open $tmp r]
    fconfigure $f -encoding utf-8
    set r [read $f]
    close $f
    catch {file delete -force $tmp}
    return $r
  }
  set r {}
  sc_game push copy
  foreach n $nums {
    if {[catch {sc_game load $n}]} { continue }
    append r [::moderne::pgnAnglais -width 80] "\n"
  }
  sc_game pop
  return $r
}

proc ::moderne::menuclic::copierPgn {nums} {
  busyCursor .
  set r [pgnDe $nums]
  unbusyCursor .
  setClipboard $r
}

################################################################################
### Notation
################################################################################

proc ::moderne::menuclic::notation {win} {
  set m $win.ctxtMenu
  catch {destroy $m}
  menu $m -tearoff 0
  $m add command -label [T "Bilan de la partie" "Game review"] -command ::moderne::bilan::lancer
  $m add separator
  $m add command -label [T "Copier la partie (PGN)" "Copy the game (PGN)"] -command ::pgn::copyPgn
  $m add command -label [T "Copier la position (FEN)" "Copy the position (FEN)"] -accelerator Ctrl+Maj+C -command copyFEN
  $m add command -label [T "Coller une partie ou une position" "Paste a game or a position"] -accelerator Ctrl+V \
      -command ::moderne::menuclic::coller
  # symbols, evaluation, comment of the move
  if {[sc_game info previousMove] ne {}} {
    $m add separator
    foreach {genre fr en} {coup "Symbole du coup" "Move symbol" eval "Évaluation" "Evaluation"} {
      menu $m.$genre -tearoff 0
      catch {::moderne::commentaire::remplirSymboles $m.$genre $genre}
      $m add cascade -label [T $fr $en] -menu $m.$genre
    }
    $m add command -label [T "Commenter ce coup…" "Comment this move…"] -accelerator Ctrl+A \
        -command ::moderne::commentaire::ouvrir
    if {[string trim [sc_pos getComment]] ne {}} {
      $m add command -label [T "Effacer le commentaire de ce coup" "Erase this move's comment"] -command ::pgn::deleteComment
    }
  }
  # variation commands, only inside a variation
  if {[sc_var level] > 0} {
    set v [sc_var number]
    $m add separator
    # (the move shown stays shown, Yosha 2026-11-03)
    $m add command -label [T "Promouvoir en ligne principale" "Promote to main line"] -accelerator Alt+↑ -command ::moderne::clavier::promouvoirVariante
    $m add command -label [T "Placer en première variante" "Make it the first variation"] -command ::moderne::clavier::premiereVariante
    $m add command -label [T "Supprimer cette variante" "Delete this variation"] -command [list ::pgn::deleteVar $v]
    # (a merged game: its quotation taken off, the variation kept)
    if {![catch {::moderne::commentaire::citationVariante} c] && $c ne {}} {
      $m add command -label [T "Supprimer la citation de partie" "Delete the game quotation"] \
          -command ::moderne::commentaire::supprimerCitation
    }
  }
  # "Continue from here" against Toby or an Alter Ego, like Lichess
  $m add separator
  catch {::moderne::toby::entreesIci $m}
  # replay training from here (ChessBase style)
  if {[sc_game info nextMoveUCI] ne {}} {
    ::moderne::revision::entrees $m
  }
  $m add separator
  $m add command -label [T "Supprimer les coups qui précèdent" "Delete the moves before"] -accelerator "Alt+X" -command ::game::TruncateBegin
  $m add command -label [T "Supprimer les coups qui suivent" "Delete the moves after"] -accelerator "Alt+C" -command ::game::Truncate
  menu $m.nettoyer -tearoff 0
  $m.nettoyer add command -label [T "Variantes" "Variations"] -command {::game::Strip variations .pgnWin}
  $m.nettoyer add command -label [T "Commentaires" "Comments"] -command {::game::Strip comments .pgnWin}
  foreach {quoi fr en} {symboles "Symboles (!, ?…)" "Symbols (!, ?…)" evaluations "Évaluations (±, =…)" "Evaluations (±, =…)"
                        marques "Flèches et cases" "Arrows and squares" citations "Citations de parties" "Game quotations"
                        temps "Temps des coups" "Move times"} {
    $m.nettoyer add command -label [T $fr $en] -command [list ::moderne::commentaire::nettoyer $quoi]
  }
  $m add cascade -label [T "Effacer de toute la partie" "Erase from the whole game"] -menu $m.nettoyer
  # (a game with move times: show them or not, like Options > Appearance)
  if {[llength [sc_game values clk]]} {
    if {![info exists ::moderne::tempsCoups]} { set ::moderne::tempsCoups 0 }
    $m add separator
    $m add checkbutton -label [T "Afficher les temps des coups" "Show the move times"] \
        -variable ::moderne::tempsCoups -command {updateBoard -pgn}
  }
  catch {::moderne::menubar::epurer $m}
  tk_popup $m [winfo pointerx .] [winfo pointery .]
}

proc ::moderne::menuclic::installerNotation {} {
  if {[llength [info commands ::pgn::contextMenuOrig]]} { return }
  rename ::pgn::contextMenu ::pgn::contextMenuOrig
  proc ::pgn::contextMenu {win} {
    update idletasks
    if {[::moderne::actif]} { ::moderne::menuclic::notation $win } else { ::pgn::contextMenuOrig $win }
  }
}

################################################################################
### Game list
################################################################################

### Games of the selection (numbers), or "filtre" for every game (Ctrl+A)
proc ::moderne::menuclic::selection {} {
  # (every chosen game, on screen or not: see ::moderne::glisser::numerosChoisis)
  if {![catch {::moderne::glisser::numerosChoisis} l]} { return $l }
  if {$::moderne::glisser::tout} { return filtre }
  set t .glistWin.tree
  set l {}
  foreach i [$t selection] {
    set n [$t set $i Number]
    if {[string is integer -strict $n] && $n > 0} { lappend l $n }
  }
  return [lsort -integer -unique $l]
}

proc ::moderne::menuclic::liste {w x y X Y} {
  if {![::moderne::actif]} { ::windows::gamelist::PopupOrig $w $x $y $X $Y ; return }
  set region {}
  catch {set region [$w identify region $x $y]}
  if {$region eq "heading"} { enTete $w $x $y $X $Y ; return }
  set row [$w identify row $x $y]
  if {$row eq {}} { return }
  # a click outside the selection selects that game
  if {$row ni [$w selection]} {
    ::moderne::glisser::finTout
    $w selection set $row
    $w focus $row
  }
  set nums [selection]
  set nb [expr {$nums eq "filtre" ? [sc_filter count] : [llength $nums]}]
  set un [expr {$nb == 1}]
  set b [sc_base current]
  set ro [expr {[sc_base isReadOnly] || (![catch {::moderne::mesbases::estCadenassee $b} c] && $c)}]
  set m .glistWin.context
  catch {destroy $m}
  menu $m -tearoff 0
  if {$un} {
    $m add command -label [T "Ouvrir la partie" "Open the game"] -command ::windows::gamelist::LoadSelection
    $m add command -label [T "Aperçu" "Preview"] -command ::windows::gamelist::Browse
    # (opened, then its review: the Review tab follows the game)
    $m add command -label [T "Bilan de la partie" "Game review"] \
        -command {::windows::gamelist::LoadSelection ; after idle ::moderne::bilan::lancer}
    set gn [lindex $nums 0]
    $m add command -label [T "Fusionner dans la partie en cours" "Merge into the current game"] \
        -command [list ::moderne::menuclic::fusionner game $b $gn] \
        -state [expr {($b == [sc_base current] && $gn == [sc_game number]) ? "disabled" : "normal"}]
    $m add command -label [T "Voir le tableau du tournoi" "Show crosstable"] -command [list ::moderne::croise::ouvrir $b $gn]
    $m add separator
  }
  $m add command -label [expr {$un ? [T "Copier la partie (PGN)" "Copy the game (PGN)"] \
      : [T "Copier les $nb parties (PGN)" "Copy the $nb games (PGN)"]}] -command [list ::moderne::menuclic::copierPgn $nums]
  # copy into another open database
  menu $m.vers -tearoff 0
  set k 0
  for {set i 1} {$i <= [sc_base count total]} {incr i} {
    if {$i == $b || ![sc_base inUse $i]} { continue }
    set nom [file rootname [::moderne::nomBase [sc_base filename $i]]]
    if {$i == [sc_info clipbase]} { set nom [T "Presse-papier" "Clipbase"] }
    $m.vers add command -label $nom -command [list ::moderne::glisser::copier $b $nums $i]
    incr k
  }
  $m add cascade -label [T "Copier dans la base" "Copy into the database"] -menu $m.vers -state [expr {$k ? "normal" : "disabled"}]
  $m add separator
  # deleted mark (the first game's state decides)
  set marquee 0
  catch {set marquee [expr {[string trim [$w set [lindex [$w selection] 0] Deleted]] eq "D"}]}
  $m add command -label [expr {$marquee ? [T "Retirer la marque « supprimée »" "Unmark as deleted"] : [T "Marquer comme supprimée" "Mark as deleted"]}] \
      -accelerator [T Suppr Del] -command ::windows::gamelist::Delete -state [expr {$ro ? "disabled" : "normal"}]
  menu $m.drapeaux -tearoff 0
  foreach flag $::maintFlaglist {
    if {$flag in {1 2 3 4 5 6}} {
      set lib [::moderne::libelleDrapeau [sc_game flag $flag description]]
      if {$lib eq {}} { continue }
    } else {
      set lib $::tr($::maintFlags($flag))
    }
    if {$flag eq "D"} { continue }
    $m.drapeaux add command -label $lib -command [list ::windows::gamelist::ToggleFlag $flag]
  }
  $m add cascade -label [T "Drapeau" "Flag"] -menu $m.drapeaux -state [expr {$ro ? "disabled" : "normal"}]
  $m add command -label [T "Effacer les parties barrées…" "Erase the struck-through games…"] \
      -command {compactGames .glistWin ; configCompactButton} \
      -state [expr {$ro || $b == [sc_info clipbase] ? "disabled" : "normal"}]
  if {$un} {
    menu $m.deplacer -tearoff 0
    $m.deplacer add command -label [T "Tout en haut" "To the top"] -command {::windows::gamelist::Reorder start}
    $m.deplacer add command -label [T "Monter d'une place" "Up one place"] -command {::windows::gamelist::Reorder up}
    $m.deplacer add command -label [T "Descendre d'une place" "Down one place"] -command {::windows::gamelist::Reorder down}
    $m.deplacer add command -label [T "Tout en bas" "To the bottom"] -command {::windows::gamelist::Reorder end}
    $m.deplacer add command -label [T "À la place n°…" "To place number…"] -command ::windows::gamelist::ReorderGameN
    $m add cascade -label [T "Déplacer (ou glisser-déposer)" "Move (or drag and drop)"] -menu $m.deplacer \
        -state [expr {$ro ? "disabled" : "normal"}]
  }
  $m add separator
  menu $m.cacher -tearoff 0
  $m.cacher add command -label [expr {$un ? [T "Cette partie" "This game"] : [T "Ces parties" "These games"]}] \
      -accelerator [T Ctrl+Suppr Ctrl+Del] -command ::windows::gamelist::Remove
  if {$un} {
    $m.cacher add command -label [T "Elle et toutes celles au-dessus" "It and all those above"] -command {::windows::gamelist::removeFromFilter up}
    $m.cacher add command -label [T "Elle et toutes celles en dessous" "It and all those below"] -command {::windows::gamelist::removeFromFilter down}
  }
  $m.cacher add command -label [T "Toutes les autres" "All the others"] -command ::windows::gamelist::Select
  $m.cacher add separator
  $m.cacher add command -label [T "Inverser : montrer les parties cachées" "Invert: show the hidden games"] \
      -command ::search::filter::negate
  $m add cascade -label [T "Cacher de la liste" "Hide from the list"] -menu $m.cacher -state [expr {$nums eq "filtre" ? "disabled" : "normal"}]
  $m add command -label [T "Réafficher toutes les parties" "Show all the games again"] -command {.glistWin.b.f.reset invoke}
  $m add command -label [T "Aller à la partie en cours" "Go to the current game"] -command ::windows::gamelist::showCurrent
  catch {::moderne::menubar::epurer $m}
  tk_popup $m $X $Y
}

### Column headings
proc ::moderne::menuclic::enTete {w x y X Y} {
  set col [$w identify column $x $y]
  set id [$w column $col -id]
  set idx [lsearch -exact $::glistHeaders $id]
  set m .glistWin.context
  catch {destroy $m}
  menu $m -tearoff 0
  menu $m.ajouter -tearoff 0
  set i 0
  # (only the columns not shown yet)
  set montrees [$w cget -displaycolumns]
  foreach h $::glistHeaders {
    if {$h ni $montrees && $i ni $montrees} {
      $m.ajouter add command -label $::tr(Glist$h) -command [list ::windows::gamelist::insertCol $w $i $col]
    }
    incr i
  }
  $m add cascade -label [T "Ajouter une colonne" "Add a column"] -menu $m.ajouter \
      -state [expr {[$m.ajouter index end] eq "none" ? "disabled" : "normal"}]
  $m add command -label [T "Masquer cette colonne" "Hide this column"] -command [list ::windows::gamelist::removeCol $w $col]
  menu $m.aligner -tearoff 0
  foreach {a fr en} {w "À gauche" "Left" c "Au centre" "Centre" e "À droite" "Right"} {
    $m.aligner add command -label [T $fr $en] -command "$w column $col -anchor $a ; lset ::glistColAnchor $idx $a"
  }
  $m add cascade -label [T "Aligner" "Align"] -menu $m.aligner
  $m add separator
  $m add command -label [T "Colonnes par défaut" "Default columns"] -command [list ::windows::gamelist::resetCols $w]
  catch {::moderne::menubar::epurer $m}
  tk_popup $m $X $Y
}

proc ::moderne::menuclic::installerListe {} {
  if {[llength [info commands ::windows::gamelist::PopupOrig]]} { return }
  rename ::windows::gamelist::Popup ::windows::gamelist::PopupOrig
  proc ::windows::gamelist::Popup {w x y X Y} { ::moderne::menuclic::liste $w $x $y $X $Y }
}

################################################################################
### Database tiles under the game list
################################################################################

### File of database b (the .si4, or the PGN file)
proc ::moderne::menuclic::fichierBase {b} {
  if {[info exists ::moderne::pgnfichier::fichier($b)]} { return $::moderne::pgnfichier::fichier($b) }
  set f [sc_base filename $b]
  if {[string tolower [file extension $f]] in {.pgn .gz}} { return $f }
  return $f.si4
}

proc ::moderne::menuclic::tuile {b X Y} {
  if {![sc_base inUse $b]} { return }
  set m .glistWin.menuTuile
  catch {destroy $m}
  menu $m -tearoff 0
  set clip [expr {$b == [sc_info clipbase]}]
  if {$b != [sc_base current]} {
    $m add command -label [T "Ouvrir" "Open"] -command [list ::file::SwitchToBase $b]
  }
  if {!$clip} {
    set f [::moderne::mesbases::chemin [fichierBase $b]]
    $m add command -label [T "Rechercher dans cette base…" "Search in this database…"] \
        -command [list ::moderne::mesbases::rechercher $f]
    $m add command -label [T "Base de référence (bibliothèque d'ouvertures)" "Reference database (opening library)"] \
        -command [list ::moderne::mesbases::reference $f]
    $m add command -label [expr {[::moderne::mesbases::cadenassee $f] ? [T "Retirer le cadenas" "Remove the padlock"] \
        : [T "Cadenasser (protéger des modifications)" "Padlock (protect from changes)"]}] \
        -command [list ::moderne::mesbases::basculerCadenas $f]
  }
  $m add separator
  $m add command -label [T "Réafficher toutes les parties" "Show all the games again"] -command [list ::search::filter::reset $b]
  $m add command -label [T "Inverser le filtre" "Invert the filter"] -command [list ::search::filter::negate $b]
  $m add separator
  $m add command -label [expr {$clip ? [T "Vider le presse-papier" "Empty the clipbase"] : [T "Fermer" "Close"]}] \
      -command [list ::file::Close $b]
  catch {::moderne::menubar::epurer $m}
  tk_popup $m $X $Y
}

### After the tiles are built: their right click opens this menu
proc ::moderne::menuclic::installerTuiles {} {
  if {![::moderne::actif]} { return }
  for {set i 1} {$i <= 9} {incr i} {
    set f .glistWin.baseWin.c.f$i
    if {![winfo exists $f]} { continue }
    foreach x [list $f $f.img $f.name] {
      catch {bind $x <ButtonPress-3> [list ::moderne::menuclic::tuile $i %X %Y]}
    }
  }
}

################################################################################
### Engine lines
################################################################################

proc ::moderne::menuclic::ligneMoteur {n x y X Y} {
  set h .analysisWin$n.hist.text
  if {![winfo exists $h]} { return }
  set i [expr {[lindex [split [$h index @$x,$y] .] 0] - 1}]
  set nb [llength $::analysis(multiPVraw$n)]
  if {$i < 0 || $i >= $nb} { return }
  set m .analysisWin$n.menuLigne
  catch {destroy $m}
  menu $m -tearoff 0
  $m add command -label [T "Insérer la ligne" "Insert the line"] \
      -command [list ::moderne::menuclic::ajouterLigne $n $i]
  if {$nb > 1} {
    $m add command -label [T "Insérer toutes les lignes" "Insert all the lines"] -command [list addAllVariations $n]
  }
  $m add command -label [T "Jouer le premier coup" "Play the first move"] \
      -command [list ::moderne::menuclic::jouerPremier $n $i]
  catch {::moderne::menubar::epurer $m}
  tk_popup $m $X $Y
}

### One line as a variation (addAllVariations on that line alone)
### Line i of engine n inserted as a variation (up to its move k)
proc ::moderne::menuclic::ajouterLigne {n i {k end}} {
  global analysis
  set garde $analysis(multiPVraw$n)
  set ligne [lindex $garde $i]
  if {$k ne "end"} { lset ligne 2 [lrange [lindex $ligne 2] 0 $k] }
  set gardeW {}
  if {[info exists analysis(WDL$n,0)]} { set gardeW $analysis(WDL$n,0) }
  if {[info exists analysis(WDL$n,$i)]} { set analysis(WDL$n,0) $analysis(WDL$n,$i) }
  set analysis(multiPVraw$n) [list $ligne]
  catch {addAllVariations $n}
  set analysis(multiPVraw$n) $garde
  if {$gardeW ne {}} { set analysis(WDL$n,0) $gardeW }
}

proc ::moderne::menuclic::jouerPremier {n i} {
  set coup [lindex [lindex $::analysis(multiPVraw$n) $i 2] 0]
  if {$coup eq {}} { return }
  sc_game undoPoint
  if {[catch {sc_move addUCI $coup}]} { return }
  updateBoard -pgn -animate
}

proc ::moderne::menuclic::installerMoteur {n} {
  set h .analysisWin$n.hist.text
  if {![winfo exists $h]} { return }
  bind $h <ButtonPress-3> [list ::moderne::menuclic::ligneMoteur $n %x %y %X %Y]
  catch {::moderne::moteur::installerSurvol $n}
}

################################################################################

proc ::moderne::menuclic::installer {} {
  catch installerNotation
  catch installerListe
}
::moderne::menuclic::installer
