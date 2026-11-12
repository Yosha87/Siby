###
### Siby: "Game information", like the Play window: the players (with name
### suggestions) and their ratings, event, round, site, date, result. It
### edits the current game's header (like Game › Game information of SCID,
### gameSave -1: the game is marked changed, not saved). The other tags
### (event date, ECO, extra tags) stay as they are; "More tags…" opens the
### full editor.
###

namespace eval ::moderne::infos {
  variable w .infosPartie
  variable form
  array set form {}
}

proc ::moderne::infos::T {fr en} { return [::moderne::tr $fr $en] }
proc ::moderne::infos::C {nom} { return [::moderne::c $nom] }

### Date of the header as YYYY.MM.DD, with ?? for the unknown parts
proc ::moderne::infos::date {a m j} {
  if {$a == 0} { set a "????" }
  if {$m == 0} { set m "??" } else { set m [format %02d [scan $m %d]] }
  if {$j == 0} { set j "??" } else { set j [format %02d [scan $j %d]] }
  return "$a.$m.$j"
}

### focus: white | black | {} (field to start in)
proc ::moderne::infos::ouvrir {{focus {}}} {
  variable w
  variable form
  # (the header of the game on the board: always editable; a read-only
  # database only refuses the saving)
  if {[winfo exists $w]} { raise $w ; return }
  foreach {k tag} {blanc White noir Black tournoi Event lieu Site ronde Round resultat Result
                   eloB WhiteElo eloN BlackElo} {
    set form($k) [sc_game tag get $tag]
    if {$form($k) eq "?"} { set form($k) {} }
  }
  foreach k {eloB eloN} { if {$form($k) eq "0"} { set form($k) {} } }
  set form(date) [date [sc_game tag get Year] [sc_game tag get Month] [sc_game tag get Day]]

  ::moderne::jouer::polices
  set fond [C fond]
  toplevel $w -background $fond
  wm title $w [T "Informations de la partie" "Game information"]
  wm transient $w .
  wm resizable $w 0 0
  set f [frame $w.f -background $fond -padx 22 -pady 16]
  pack $f -fill both -expand 1
  label $f.titre -text [T "Informations de la partie" "Game information"] -font SibyJouerTitre \
      -background $fond -foreground [C texteFort] -anchor w
  pack $f.titre -side top -fill x

  set g [frame $f.g -background $fond]
  pack $g -side top -fill x
  champ $g.b [T "Blancs" "White"] ::moderne::infos::form(blanc) 30 1
  champ $g.be [T "Elo" "Rating"] ::moderne::infos::form(eloB) 6 0
  champ $g.n [T "Noirs" "Black"] ::moderne::infos::form(noir) 30 1
  champ $g.ne [T "Elo" "Rating"] ::moderne::infos::form(eloN) 6 0
  champ $g.t [T "Tournoi" "Event"] ::moderne::infos::form(tournoi) 30 0
  champ $g.r [T "Ronde" "Round"] ::moderne::infos::form(ronde) 6 0
  champ $g.l [T "Lieu" "Site"] ::moderne::infos::form(lieu) 30 0
  champ $g.d [T "Date" "Date"] ::moderne::infos::form(date) 11 0
  ttk::button $g.d.auj -text [T "Aujourd'hui" "Today"] -style Toolbutton \
      -command {set ::moderne::infos::form(date) [clock format [clock seconds] -format %Y.%m.%d]}
  pack $g.d.auj -side top -anchor w -pady {2 0}
  foreach {a b} [list $g.b $g.be $g.n $g.ne $g.t $g.r $g.l $g.d] { grid $a $b -sticky new }
  grid configure $g.b $g.n $g.t $g.l -padx {0 16}
  grid columnconfigure $g 0 -weight 1

  ::moderne::jouer::section $f.lres [T "Résultat" "Result"]
  ::moderne::jouer::segments $f.res ::moderne::infos::form(resultat) [list \
      [list 1 "1-0"] [list = "½-½"] [list 0 "0-1"] [list * [T "En cours" "Ongoing"]]]
  pack $f.res -side top -fill x

  frame $f.btn -background $fond
  pack $f.btn -side top -fill x -pady {18 0}
  ttk::button $f.btn.plus -text [T "Plus de balises…" "More tags…"] -style Toolbutton \
      -command {destroy .infosPartie ; gameSave -1}
  catch {::utils::tooltip::Set $f.btn.plus [T "Date de l'événement, ECO, balises supplémentaires (Annotator…)" \
      "Event date, ECO, extra tags (Annotator…)"]}
  ttk::button $f.btn.ok -text [T "Appliquer" "Apply"] -command ::moderne::infos::appliquer
  if {![catch {ttk::style layout Accent.TButton} l] && $l ne {}} { $f.btn.ok configure -style Accent.TButton }
  ttk::button $f.btn.annuler -text [T "Annuler" "Cancel"] -command [list destroy $w]
  pack $f.btn.plus -side left
  pack $f.btn.ok $f.btn.annuler -side right -padx 3
  bind $w <Escape> [list destroy $w]
  bind $w <Return> ::moderne::infos::appliquer
  catch {placeWinOverParent $w .}
  focus [expr {$focus eq "black" ? "$g.n.e" : "$g.b.e"}]
}

### A labelled entry (with player name suggestions)
proc ::moderne::infos::champ {p titre var largeur noms} {
  frame $p -background [C fond]
  ::moderne::jouer::section $p.l $titre 1
  pack $p.l -side top -fill x -pady {12 5}
  ttk::entry $p.e -width $largeur -textvariable $var
  pack $p.e -side top -fill x
  if {$noms} {
    catch {::moderne::suggestions::attacher $p.e ::moderne::rparties::suggestions [list ::moderne::rparties::choisi $var]}
  }
}

### Writes the header into the current game (marked changed, not saved)
proc ::moderne::infos::appliquer {} {
  variable form
  set w .infosPartie
  foreach k {blanc noir tournoi lieu ronde} {
    set v [string trim $form($k)]
    if {$v eq {}} { set v "?" }
    if {[string bytelength $v] > 255} {
      tk_messageBox -type ok -icon info -parent $w -title Siby -message [T "Texte trop long (255 octets au plus)." "Text too long (255 bytes at most)."]
      return 0
    }
    set val($k) $v
  }
  set d [string trim $form(date)]
  if {$d eq {}} { set d "????.??.??" }
  if {![regexp {^(\d{4}|\?{4})(\.(\d\d|\?\?)(\.(\d\d|\?\?))?)?$} $d]} {
    tk_messageBox -type ok -icon info -parent $w -title Siby -message [T \
        "Date : AAAA.MM.JJ (?? pour une partie inconnue), par exemple 2026.10.26 ou 1999.??.??" \
        "Date: YYYY.MM.DD (?? for an unknown part), e.g. 2026.10.26 or 1999.??.??"]
    return 0
  }
  while {[llength [split $d .]] < 3} { append d ".??" }
  foreach k {eloB eloN} {
    set val($k) [expr {[string is integer -strict [string trim $form($k)]] ? [string trim $form($k)] : 0}]
  }
  set edate [date [sc_game tag get EYear] [sc_game tag get EMonth] [sc_game tag get EDay]]
  sc_game undoPoint
  sc_game tags set -event $val(tournoi) -site $val(lieu) -date $d -round $val(ronde) \
      -white $val(blanc) -black $val(noir) -result $form(resultat) \
      -whiteElo $val(eloB) -whiteRatingType [sc_game tag get WhiteRType] \
      -blackElo $val(eloN) -blackRatingType [sc_game tag get BlackRType] \
      -eco [sc_game tag get ECO] -eventdate $edate -extra [split [sc_game tag get Extra] "\n"]
  sc_game setaltered 1
  catch {destroy $w}
  updateBoard -header
  catch {::windows::stats::Refresh}
  catch {updateTitle}
  return 1
}

### End Siby
