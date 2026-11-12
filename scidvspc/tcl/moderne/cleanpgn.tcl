
###
### Siby: Clean PGN - lines written in comments -> real variations
###
### In many exported courses and annotated PGNs, the
### secondary variations are text in the comments:
###   10.f4 { … 12.Ndf3?! 12...Ne4⇆ Broadly speaking… 12.Qc2?! 12...Ne7! 13.Bh4 c4! … }
### This module re-reads those comments, replays the moves they contain on
### the board and adds them to the game as real variations (which can be
### played, put into a tree or a repertoire). The comment text is
### kept as is.
###
### Rules:
###  - a line starts with a numbered move ("12.Ndf3", "12...Ne4");
###    it attaches to a position that precedes this move number and where
###    the move is legal. If there are several possibilities: first the line
###    of the current parenthesis, then the "main" lines of the
###    discussion (first move cited at each branching, or the game), rather
###    than digressions ("12...c4 too" must not capture "13.Bh4");
###  - a move without a number extends the line if it directly follows a move;
###    after text, only a numbered move starts a line again;
###  - the comment's parentheses are respected: "(4.Nf3 …)" is a
###    sub-variation of the current line;
###  - a move already present (in the game or a previous line) is not
###    duplicated: it is followed;
###  - an illegal move stops the line (the text remains);
###  - the game's main line is never extended;
###  - a move number before the commented move (an earlier position quoted
###    in a sentence) is left as text.
###
### This file does not depend on Tk: it is also used from the command line
### (outils/clean_pgn.sh, via tcscid).
###

# (command line, without the rest of Siby: the PGN as sc_game writes it;
# Siby's own version, with English piece letters, replaces it in Siby)
namespace eval ::moderne {}
if {![llength [info commands ::moderne::pgnAnglais]]} {
  proc ::moderne::pgnAnglais {args} { return [sc_game pgn {*}$args] }
}

namespace eval ::moderne::cleanpgn {
  variable node        ;# node(id,field)
  variable prochainId 0
  variable stats       ;# stats(variantes) stats(ignorees)
  variable decouper 1  ;# cut the comments around the lines (Yosha 2026-11-03: always)
  # Annotations attached to moves -> NAG
  variable nags
  array set nags {
    !  1   ?  2   !!  3   ??  4   !?  5   ?!  6
    =  10  ∞ 13  ⩲ 14  ⩱ 15  ± 16  ∓ 17  +- 18  -+ 19
    ⇆ 132
  }
  variable reSan {(?:O-O-O|O-O|0-0-0|0-0|[KQRBN][a-h1-8]?x?[a-h][1-8]|[a-h]x[a-h][1-8](?:=?[QRBN])?|[a-h][1-8](?:=?[QRBN])?)[+#]?}
  variable reSuffixe {[!?∞⇆=±∓⩲⩱+\-]*}
}

################################################################################
### Small "scratch" board tool (in the clipboard, without touching
### the current game)
################################################################################

### Plays the list of SAN moves from fen; returns {fenAfter normalizedSan}
### for each move played (stops at the first illegal move).
proc ::moderne::cleanpgn::jouer {fen coups} {
  set res {}
  # (startBoard rather than "sc_game new", which would erase the number of
  # the clipboard game, not restored by "sc_game pop")
  if {$fen eq {}} { set fen "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1" }
  if {[catch {sc_game startBoard $fen}]} { return {} }
  foreach san $coups {
    if {[catch {sc_move addSan $san}]} { break }
    lappend res [list [sc_pos fen] [sc_game info previousMoveNT]]
  }
  return $res
}

################################################################################
### Game tree
################################################################################

proc ::moderne::cleanpgn::nouveauNoeud {parent san fen ply {principal 0}} {
  variable node
  variable prochainId
  set id [incr prochainId]
  set node($id,san) $san
  set node($id,fen) $fen
  set node($id,ply) $ply
  set node($id,parent) $parent
  set node($id,kids) {}
  set node($id,comment) {}
  set node($id,nags) {}
  set node($id,principal) $principal
  if {$parent ne {}} { lappend node($parent,kids) $id }
  return $id
}

### Ply (0 = White's first move) of a move number
proc ::moderne::cleanpgn::plyDe {numero noirs} {
  return [expr {2 * ($numero - 1) + ($noirs ? 1 : 0)}]
}

### Ancestors of a node (itself included), from nearest to farthest
proc ::moderne::cleanpgn::ancetres {id} {
  variable node
  set res {}
  while {$id ne {}} {
    lappend res $id
    set id $node($id,parent)
  }
  return $res
}

### Tries to play san from node p: returns the child node (existing
### or created), or {} if the move is illegal or forbidden.
proc ::moderne::cleanpgn::jouerDepuis {p san} {
  variable node
  variable stats
  set r [jouer $node($p,fen) [list $san]]
  if {![llength $r]} { return {} }
  lassign [lindex $r 0] fen sanN
  foreach k $node($p,kids) {
    if {$node($k,san) eq $sanN} { return $k }
  }
  # Never extend the game's main line (a variation already there may
  # grow: "the game may continue with 12.Nf3…" at its end)
  if {[info exists node($p,jeu)] && $node($p,jeu) && ![llength $node($p,kids)]} { return {} }
  incr stats(variantes)
  set id [nouveauNoeud $p $sanN $fen [expr {$node($p,ply) + 1}]]
  set node($id,cree) 1
  return $id
}

### Splits a comment into tokens: {num N noirs san suffixe} {san san suffixe}
### {ouvre} {ferme} {texte}
proc ::moderne::cleanpgn::jetons {texte} {
  variable reSan
  variable reSuffixe
  # (mots: each word of the comment as written, with the token it made,
  # -1 for none: used to cut the comment around the lines)
  variable mots
  set mots {}
  set res {}
  set numEnAttente {}
  set motEnAttente {}
  # a comment written with French piece letters (Cf3, Fc4, Dxe7, Td1, Rg1):
  # the moves read in English (C N, F B, T R, D Q, R K)
  set francais [regexp {(^|[\s(.])[CDFT]x?[a-h]?[1-8]?x?[a-h][1-8]} $texte]
  foreach brut [regexp -all -inline {\S+} [string map {( " ( " ) " ) "} $texte]] {
    set mot [string map {… ...} $brut]
    if {$francais} { set mot [francaisVersAnglais $mot] }
    # (the token this word makes: the next one of res)
    set k [llength $res]
    if {$mot in {( )} && $numEnAttente ne {}} { noterMots $motEnAttente -1 }
    if {$mot eq "("} { lappend res ouvre ; set numEnAttente {} ; noterMots $brut $k ; continue }
    if {$mot eq ")"} { lappend res ferme ; set numEnAttente {} ; noterMots $brut $k ; continue }
    # end-of-sentence punctuation
    regsub {[,;:]+$} $mot {} mot
    if {[regexp {^([0-9]+)(\.\.\.|\.)$} $mot -> n points]} {
      if {$numEnAttente ne {}} { noterMots $motEnAttente -1 }
      set numEnAttente [list $n [expr {$points eq "..."}]]
      set motEnAttente $brut
      continue
    }
    if {[regexp "^(\[0-9\]+)(\\.\\.\\.|\\.)($reSan)($reSuffixe)\\.?$" $mot -> n points san suf]} {
      lappend res [list num $n [expr {$points eq "..."}] $san $suf]
      set numEnAttente {}
      noterMots $brut $k
      continue
    }
    if {[regexp "^($reSan)($reSuffixe)\\.?$" $mot -> san suf]} {
      if {$numEnAttente ne {}} {
        lappend res [list num {*}$numEnAttente $san $suf]
        set numEnAttente {}
        # (the number written apart goes with its move)
        noterMots "$motEnAttente $brut" $k
      } else {
        lappend res [list san $san $suf]
        noterMots $brut $k
      }
      continue
    }
    if {$numEnAttente ne {}} { noterMots $motEnAttente -1 }
    set numEnAttente {}
    lappend res texte
    noterMots $brut $k
  }
  if {$numEnAttente ne {}} { noterMots $motEnAttente -1 }
  return $res
}

### A move with French piece letters, in English (other words unchanged)
proc ::moderne::cleanpgn::francaisVersAnglais {mot} {
  if {[regexp {^([0-9]+\.(?:\.\.)?)?([RDTFC])([a-h1-8]?x?[a-h][1-8].*)$} $mot -> num p reste]} {
    set mot "$num[string map {R K D Q T R F B C N} $p]$reste"
  }
  # promotion: e8=D
  if {[regexp {^(.*[a-h][18]=?)([DTFC])(.*)$} $mot -> a p b]} {
    set mot "$a[string map {D Q T R F B C N} $p]$b"
  }
  return $mot
}

### A word (or a number and its move) of the comment, and its token
proc ::moderne::cleanpgn::noterMots {texte k} {
  variable mots
  if {$texte eq {}} { return }
  lappend mots [list $texte $k]
}

proc ::moderne::cleanpgn::ajouterNag {id suffixe} {
  variable node
  variable nags
  if {$suffixe eq {}} { return }
  # "!?", "?!", "!!", "??" first, then the symbols one by one
  if {[regexp {^([!?]{1,2})(.*)$} $suffixe -> a reste]} {
    if {[info exists nags($a)]} { lappend node($id,nags) $nags($a) }
    set suffixe $reste
  }
  foreach s [list +- -+] { if {[string first $s $suffixe] >= 0} { lappend node($id,nags) $nags($s) ; set suffixe [string map [list $s {}] $suffixe] } }
  foreach c [split $suffixe {}] {
    if {[info exists nags($c)]} { lappend node($id,nags) $nags($c) }
  }
  set node($id,nags) [lsort -unique -integer $node($id,nags)]
}

### Converts a comment placed on node c of the main line
proc ::moderne::cleanpgn::traiterCommentaire {c racine principaux} {
  variable node
  variable stats
  set cur {}          ;# last node of the current line
  set attache 0       ;# the previous token was a played move
  set pile {}         ;# "parent" lines (parentheses)
  set ctx {}          ;# for each open parenthesis: nodes seen since
  set lignes {}       ;# lines already read in this comment (last node)
  set abandon 0       ;# the line being written failed: ignore it until the next text
  set toks [jetons $node($c,comment)]
  set iTok -1
  foreach j $toks {
    incr iTok
    switch -- [lindex $j 0] {
      ouvre { lappend pile $cur ; lappend ctx {} ; set attache 0 ; set abandon 0 }
      ferme {
        if {[llength $pile]} {
          set cur [lindex $pile end]
          set pile [lrange $pile 0 end-1]
          set ctx [lrange $ctx 0 end-1]
        }
        set attache 0
        set abandon 0
      }
      texte { set attache 0 ; set abandon 0 }
      san {
        lassign $j - san suf
        if {!$attache || $cur eq {}} { continue }
        set n [jouerDepuis $cur $san]
        if {$n eq {}} { set attache 0 ; continue }
        set joues($iTok) $n
        ajouterNagSiNouveau $n $suf
        set cur $n
        if {[llength $ctx]} { lset ctx end [concat [lindex $ctx end] [list $n]] }
      }
      num {
        if {$abandon} { continue }
        lassign $j - numero noirs san suf
        set q [plyDe $numero $noirs]
        # A move number before the commented move is not a variation here
        # ("The game now resembles a 1.e4 e5 opening" at move 4): the
        # text stays as it is (Yosha 2026-11-03)
        if {$q < $node($c,ply)} {
          incr stats(ignorees)
          set attache 0
          set abandon 1
          continue
        }
        # Candidates: current line (and its ancestors), previous lines, game
        set candidats {}
        if {$cur ne {}} { lappend candidats {*}[ancetres $cur] }
        foreach l [lreverse $lignes] { lappend candidats {*}[ancetres $l] }
        # (the line the comment is written in, up to the game)
        lappend candidats {*}[ancetres $c]
        lappend candidats {*}$principaux $racine
        # Order of preference: current parenthesis, main lines, others
        set dansCtx {} ; set primaires {} ; set autres {}
        set contexte [expr {[llength $ctx] ? [lindex $ctx end] : {}}]
        foreach p $candidats {
          if {$node($p,ply) != $q - 1} { continue }
          if {$p in $dansCtx || $p in $primaires || $p in $autres} { continue }
          if {$p in $contexte} {
            lappend dansCtx $p
          } elseif {[estPrimaire $p]} {
            lappend primaires $p
          } else {
            lappend autres $p
          }
        }
        # Continuation written from this move (consecutive moves, no text)
        set suite [list $san]
        set qq $q
        for {set k [expr {$iTok + 1}]} {$k < [llength $toks]} {incr k} {
          set jk [lindex $toks $k]
          set type [lindex $jk 0]
          if {$type eq "san"} {
            lappend suite [lindex $jk 1]
          } elseif {$type eq "num" && [plyDe [lindex $jk 1] [lindex $jk 2]] == $qq + 1} {
            lappend suite [lindex $jk 3]
          } else {
            break
          }
          incr qq
        }
        # Attachment point: the one where the continuation stays legal longest;
        # on a tie, the order of preference above. Exception: a numbered
        # move that immediately follows a move ("6...Bc5!? 7.a4") first
        # extends the current line.
        set meilleur {} ; set meilleurL 0
        set ordre [concat $dansCtx $primaires $autres]
        if {$attache && $cur ne {} && $node($cur,ply) == $q - 1} {
          set ordre [concat [list $cur] [lsearch -all -inline -not -exact $ordre $cur]]
        }
        foreach p $ordre {
          set L [llength [jouer $node($p,fen) $suite]]
          if {$L > $meilleurL} { set meilleur $p ; set meilleurL $L }
        }
        set trouve {}
        if {$meilleur ne {}} { set trouve [jouerDepuis $meilleur $san] }
        if {$trouve eq {}} {
          incr stats(ignorees)
          set attache 0
          set abandon 1
          continue
        }
        ajouterNagSiNouveau $trouve $suf
        set joues($iTok) $trouve
        if {$cur ne {} && $cur ni $lignes} { lappend lignes $cur }
        set cur $trouve
        set attache 1
        if {[llength $ctx]} { lset ctx end [concat [lindex $ctx end] [list $trouve]] }
      }
    }
  }
  if {$cur ne {} && $cur ni $lignes} { lappend lignes $cur }
  variable decouper
  if {$decouper} { decouperCommentaire $c $toks [array get joues] }
}

### Option "cut the comments around the lines" (Yosha 2026-11-03): the
### moves turned into variations leave the comment; the text before the
### first one stays on the move; the text after a line goes to the last
### move of that line (in the variation); a joining word just before a line
### ("After", "and", "or"…) goes before its first move. A line that only
### follows moves already there keeps its text as it was. Nothing is lost.
proc ::moderne::cleanpgn::decouperCommentaire {c toks jouesListe} {
  variable node
  variable mots
  array set joues $jouesListe
  set n [llength $toks]
  # runs of consecutive moves played; moved out if one move was created
  set deplace {}       ;# token indexes taken out of the text
  set finRun {}        ;# token index of a run's last move -> its node
  set debutRun {}      ;# token index of a run's first move -> its first created node
  set i 0
  while {$i < $n} {
    if {![info exists joues($i)]} { incr i ; continue }
    set j $i
    while {$j + 1 < $n && [info exists joues([expr {$j + 1}])]} { incr j }
    set cree {}
    for {set k $i} {$k <= $j} {incr k} {
      if {[info exists node($joues($k),cree)] && $cree eq {}} { set cree $joues($k) }
    }
    if {$cree ne {}} {
      for {set k $i} {$k <= $j} {incr k} { lappend deplace $k }
      dict set finRun $j $joues($j)
      dict set debutRun $i $cree
    }
    set i [expr {$j + 1}]
  }
  if {![llength $deplace]} { return }
  # parentheses around moved moves go too
  set pile {}
  for {set k 0} {$k < $n} {incr k} {
    set type [lindex $toks $k 0]
    if {$type eq "ouvre"} { lappend pile [list $k 0] }
    if {$k in $deplace && [llength $pile]} { lset pile end 1 1 }
    if {$type eq "ferme" && [llength $pile]} {
      lassign [lindex $pile end] o vide
      set pile [lrange $pile 0 end-1]
      if {$vide} {
        lappend deplace $o $k
        if {[llength $pile]} { lset pile end 1 1 }
      }
    }
  }
  set liaisons {after and or also instead then if e.g. eg. like with but après et ou puis sinon comme}
  set cible principal
  set textes(principal) {}
  foreach m $mots {
    lassign $m mot k
    if {$k >= 0 && $k in $deplace} {
      if {[dict exists $debutRun $k]} {
        # a joining word just before a new variation: before its first move
        # (a line that goes on from the move keeps "… continue with")
        set premier [dict get $debutRun $k]
        set parent $node($premier,parent)
        set variante [expr {$parent ne {} && [lindex $node($parent,kids) 0] ne $premier}]
        if {$variante && [info exists textes($cible)] && [llength $textes($cible)]} {
          set dernier [lindex $textes($cible) end]
          if {[string tolower [string trim $dernier ",;:"]] in $liaisons} {
            set textes($cible) [lrange $textes($cible) 0 end-1]
            # ("and" / "or" alone before a variation says nothing more)
            if {[string tolower [string trim $dernier ",;:"]] ni {and or et ou}} {
              set node([dict get $debutRun $k],avant) $dernier
            }
          }
        }
      }
      if {[dict exists $finRun $k]} {
        set cible [dict get $finRun $k]
        if {![info exists textes($cible)]} { set textes($cible) {} }
      }
      continue
    }
    # (the punctuation right after a line is dropped)
    if {$cible ne "principal" && ![llength $textes($cible)]} {
      set mot [string trimleft $mot ",;:."]
      if {$mot eq {}} { continue }
    }
    lappend textes($cible) $mot
  }
  set node($c,comment) [join $textes(principal) " "]
  foreach cle [array names textes] {
    if {$cle eq "principal"} { continue }
    set t [join $textes($cle) " "]
    # (the same sentence in two comments: once)
    if {$t eq {} || [string first $t $node($cle,comment)] >= 0} { continue }
    set node($cle,comment) [string trim "$node($cle,comment) $t"]
  }
}

### A node is "primary" if it is in the game or if it is the first
### move cited at its branching (and so on up to the game)
proc ::moderne::cleanpgn::estPrimaire {id} {
  variable node
  while {$id ne {} && !$node($id,principal)} {
    set p $node($id,parent)
    # a line starting from the game is the subject of the discussion
    if {$node($p,principal)} { return 1 }
    if {[lindex $node($p,kids) 0] ne $id} { return 0 }
    set id $p
  }
  return 1
}

proc ::moderne::cleanpgn::ajouterNagSiNouveau {id suf} {
  variable node
  # Annotations are only added to created moves (not to the game)
  if {!$node($id,principal)} { ajouterNag $id $suf }
}

################################################################################
### Reading the current game and writing the PGN
################################################################################

### Reads the current game (SCID) into the tree: the main line and the
### variations already there (Yosha 2026-11-03: a course chapter with real
### variations was left untouched). Returns {root listOfExistingNodes}.
proc ::moderne::cleanpgn::lirePartie {} {
  variable node
  sc_move start
  set fen [sc_pos fen]
  # ply of the first move, from the FEN (side to move and move number)
  set champs [split $fen]
  set ply0 [plyDe [lindex $champs 5] [expr {[lindex $champs 1] eq "b"}]]
  set racine [nouveauNoeud {} {} $fen [expr {$ply0 - 1}] 1]
  set node($racine,comment) [sc_pos getComment]
  set node($racine,jeu) 1
  variable existants
  set existants {}
  lireLigne $racine 1
  # (the game's main line first, then the variations, as candidates)
  set principaux {}
  foreach n $existants { if {$node($n,jeu)} { lappend principaux $n } }
  foreach n $existants { if {!$node($n,jeu)} { lappend principaux $n } }
  return [list $racine $principaux]
}

### Reads the moves from the current position (node p) to the end of the
### line, with the variations met on the way (recursively)
proc ::moderne::cleanpgn::lireLigne {p jeu} {
  variable node
  variable existants
  while 1 {
    set san [sc_game info nextMoveNT]
    if {$san eq {}} { break }
    set nv [sc_var count]
    sc_move forward
    set n [nouveauNoeud $p $san [sc_pos fen] [expr {$node($p,ply) + 1}] 1]
    noterNoeud $n $jeu
    sc_move back
    for {set i 0} {$i < $nv} {incr i} {
      sc_var enter $i
      set v [nouveauNoeud $p [sc_game info previousMoveNT] [sc_pos fen] [expr {$node($p,ply) + 1}] 1]
      noterNoeud $v 0
      lireLigne $v 0
      sc_var exit
    }
    sc_move forward
    set p $n
  }
}

### Comment and annotations of the move just played, into node n
proc ::moderne::cleanpgn::noterNoeud {n jeu} {
  variable node
  variable existants
  set node($n,comment) [sc_pos getComment]
  set node($n,jeu) $jeu
  set nagsTexte [sc_pos getNags]
  if {$nagsTexte ne {} && $nagsTexte ne "0"} { set node($n,nagsTexte) $nagsTexte }
  lappend existants $n
}

proc ::moderne::cleanpgn::texteCoup {id numeroForce} {
  variable node
  set ply $node($id,ply)
  set num [expr {$ply / 2 + 1}]
  if {$ply % 2 == 0} {
    set t "$num. $node($id,san)"
  } elseif {$numeroForce} {
    set t "$num... $node($id,san)"
  } else {
    set t $node($id,san)
  }
  foreach n $node($id,nags) { append t " \$$n" }
  if {[info exists node($id,nagsTexte)]} { append t " $node($id,nagsTexte)" }
  return $t
}

proc ::moderne::cleanpgn::texteCommentaire {id} {
  variable node
  if {$node($id,comment) eq {}} { return {} }
  # a closing brace would cut the PGN comment
  return " \{[string map {\} )} $node($id,comment)]\}"
}

### A comment written before a move ("After" moved into the variation)
proc ::moderne::cleanpgn::texteAvant {id} {
  variable node
  if {![info exists node($id,avant)] || $node($id,avant) eq {}} { return {} }
  return "\{[string map {\} )} $node($id,avant)]\} "
}

### PGN of the moves following node p (main line + variations)
proc ::moderne::cleanpgn::pgnSuite {p numeroForce} {
  variable node
  set kids $node($p,kids)
  if {![llength $kids]} { return {} }
  set m [lindex $kids 0]
  set t "[texteAvant $m][texteCoup $m [expr {$numeroForce || [info exists node($m,avant)]}]][texteCommentaire $m]"
  set force [expr {$node($m,comment) ne {}}]
  foreach v [lrange $kids 1 end] {
    set sv [pgnSuite $v [expr {$node($v,comment) ne {}}]]
    append t " ([texteAvant $v][texteCoup $v 1][texteCommentaire $v][expr {$sv ne {} ? " $sv" : ""}])"
    set force 1
  }
  set suite [pgnSuite $m $force]
  if {$suite ne {}} { append t " $suite" }
  return $t
}

### Converts the current game. Returns {pgn variantes ignorees} or {} if
### the game cannot be modified (variations already present) or is unchanged.
proc ::moderne::cleanpgn::convertirPartieCourante {} {
  variable node
  variable prochainId
  variable stats
  array unset node
  set prochainId 0
  set stats(variantes) 0
  set stats(ignorees) 0

  set entete {}
  foreach ligne [split [::moderne::pgnAnglais -width 9999] \n] {
    if {[string index $ligne 0] ne "\["} { break }
    append entete $ligne \n
  }
  set lu [lirePartie]
  if {![llength $lu]} { return {} }
  lassign $lu racine principaux

  # Scratch game in the clipboard to replay the moves without touching the game
  set courante [sc_base current]
  sc_base switch clipbase
  sc_game push copyfast
  if {[catch {
    foreach c [concat [list $racine] $principaux] {
      if {$node($c,comment) ne {}} { traiterCommentaire $c $racine $principaux }
    }
  } err]} {
    sc_game pop
    sc_base switch $courante
    error $err
  }
  sc_game pop
  sc_base switch $courante

  if {$stats(variantes) == 0} { return [list {} 0 $stats(ignorees)] }
  regexp {\[Result "([^"]*)"\]} $entete -> resultat
  if {![info exists resultat]} { set resultat * }
  set coups [string trimleft "[texteCommentaire $racine] [pgnSuite $racine 1]"]
  return [list "$entete\n$coups $resultat\n" $stats(variantes) $stats(ignorees)]
}

### Converts the current game and replaces it in SCID (without saving it)
proc ::moderne::cleanpgn::appliquerPartieCourante {} {
  lassign [convertirPartieCourante] pgn nv ni
  if {$pgn eq {}} { return [list 0 [expr {$ni eq {} ? 0 : $ni}]] }
  set num [sc_game number]
  sc_game import $pgn
  return [list $nv $ni]
}

################################################################################
### Command line: input PGN -> output PGN (outils/clean_pgn.sh)
################################################################################

proc ::moderne::cleanpgn::fichier {entree sortie} {
  # Temporary SCID database into which the PGN is imported
  # (temporary folder: TMPDIR on Linux and macOS, TEMP or TMP on Windows,
  # where /tmp does not exist)
  set dt /tmp
  foreach v {TMPDIR TEMP TMP} {
    if {[info exists ::env($v)] && [file isdirectory $::env($v)]} { set dt $::env($v) ; break }
  }
  set tmp [file join $dt "cleanpgn_[pid]"]
  foreach ext {.si4 .sg4 .sn4} { file delete -force $tmp$ext }
  set b [sc_base create $tmp]
  sc_base import file $entree
  set out [open $sortie w]
  fconfigure $out -encoding utf-8
  set total 0 ; set modifiees 0 ; set var 0 ; set ign 0 ; set nonTraitees 0
  for {set i 1} {$i <= [sc_base numGames $b]} {incr i} {
    sc_game load $i
    incr total
    set r [convertirPartieCourante]
    if {$r eq {}} {
      incr nonTraitees
      puts $out [::moderne::pgnAnglais -width 9999]
      continue
    }
    lassign $r pgn nv ni
    incr ign $ni
    if {$pgn eq {}} {
      puts $out [::moderne::pgnAnglais -width 9999]
    } else {
      incr modifiees
      incr var $nv
      puts $out $pgn
    }
  }
  close $out
  sc_base close $b
  foreach ext {.si4 .sg4 .sn4} { file delete -force $tmp$ext }
  return [list $total $modifiees $var $ign $nonTraitees]
}

################################################################################
### Interface (Tools menu)
################################################################################

proc ::moderne::cleanpgn::dialogue {} {
  set T ::moderne::tr
  set w .cleanpgnWin
  if {[winfo exists $w]} { raiseWin $w ; return }
  toplevel $w
  wm title $w [$T "Nettoyer un PGN" "Clean PGN"]
  ttk::frame $w.f -padding 14
  pack $w.f -fill both -expand 1
  ttk::label $w.f.intro -wraplength 520 -justify left -text [$T \
"Dans beaucoup de cours et de PGN annotés, les variantes secondaires sont écrites en texte dans les commentaires. Cet outil rejoue ces coups et les ajoute comme de vraies variantes. Le texte des commentaires est conservé." \
"In many courses and annotated PGNs, side lines are written as text in comments. This tool replays those moves and adds them as real variations. Comment text is kept."]
  pack $w.f.intro -anchor w -pady {0 10}
  set ::moderne::cleanpgn::portee partie
  ttk::radiobutton $w.f.r1 -variable ::moderne::cleanpgn::portee -value partie \
      -text [$T "La partie en cours (à sauvegarder ensuite)" "The current game (save it afterwards)"]
  ttk::radiobutton $w.f.r2 -variable ::moderne::cleanpgn::portee -value base \
      -text [$T "Toutes les parties de la base (enregistrées directement)" "All games of the database (saved directly)"]
  pack $w.f.r1 $w.f.r2 -anchor w
  ttk::label $w.f.res -wraplength 520 -justify left -text {}
  pack $w.f.res -anchor w -pady 10
  ttk::frame $w.f.b
  ttk::button $w.f.b.ok -text [$T "Convertir" "Convert"] -command ::moderne::cleanpgn::lancerDialogue
  ttk::button $w.f.b.fermer -text [$T "Fermer" "Close"] -command [list destroy $w]
  bind $w <Escape> [list destroy $w]
  pack $w.f.b.fermer $w.f.b.ok -side right -padx 4
  pack $w.f.b -fill x
  catch {::moderne::repeindre $w}
}

proc ::moderne::cleanpgn::lancerDialogue {} {
  set T ::moderne::tr
  set w .cleanpgnWin
  if {$::moderne::cleanpgn::portee eq "partie"} {
    lassign [appliquerPartieCourante] nv ni
    if {$nv > 0} {
      sc_game setaltered 1
      updateBoard -pgn
    }
    $w.f.res configure -text [$T \
        "$nv coups ajoutés en variantes, $ni lignes ignorées (coups illégaux ou sans point d'attache). Pense à sauvegarder la partie." \
        "$nv moves added as variations, $ni lines ignored. Remember to save the game."]
    return
  }
  if {[sc_base isReadOnly]} {
    tk_messageBox -parent $w -icon warning -type ok -title Siby -message [$T \
        "Cette base est en lecture seule (un fichier PGN ouvert directement, par exemple). Copie d'abord ses parties dans une base Siby (Fichier › Nouvelle base), ou utilise « La partie en cours »." \
        "This database is read-only (e.g. a PGN file opened directly). Copy its games to a Siby database first, or use \"The current game\"."]
    return
  }
  set confirm [::game::ConfirmDiscard]
  if {$confirm == 2} { return }
  if {$confirm == 0} { ::game::Save }
  set courant [sc_game number]
  busyCursor .
  set total [sc_base numGames] ; set modifiees 0 ; set var 0 ; set ign 0
  for {set i 1} {$i <= $total} {incr i} {
    sc_game load $i
    lassign [appliquerPartieCourante] nv ni
    incr ign $ni
    if {$nv > 0} {
      sc_game save $i
      incr modifiees
      incr var $nv
    }
    if {$i % 20 == 0} { $w.f.res configure -text "$i / $total…" ; update idletasks }
  }
  unbusyCursor .
  if {$courant > 0} { sc_game load $courant } else { sc_game new }
  updateBoard -pgn
  catch {::windows::gamelist::Refresh}
  $w.f.res configure -text [$T \
      "$modifiees parties modifiées sur $total : $var coups ajoutés en variantes, $ign lignes ignorées." \
      "$modifiees of $total games changed: $var moves added as variations, $ign lines ignored."]
}

### End Siby
