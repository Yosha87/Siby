
### crosstab.tcl

namespace eval ::crosstab {}

foreach var  \
   {sort type ages colors ratings countries tallies titles groups breaks deleted cnumbers text threewin tiewin tiehead colorrows} \
        value \
   {score auto +ages +colors +ratings +countries +tallies +titles -groups -breaks -deleted -numcolumns hypertext -threewin -tiewin -tiehead 1} {
  if {![info exists crosstab($var)]} {
    set crosstab($var) $value
  }
}

proc ::crosstab::ConfigMenus {{lang ""}} {
  global spellCheckFileExists

  if {! [winfo exists .crosstabWin]} { return }
  if {$lang == ""} { set lang $::language }
  set m .crosstabWin.menu
  foreach idx {0 1 2 3 4 5} tag {File Sort Type Opt Edit Help} {
    configMenuText $m $idx Crosstab$tag $lang
  }
  foreach idx {0 1 2 4} tag {Text Html LaTeX Close} {
    configMenuText $m.file $idx CrosstabFile$tag $lang
  }
  foreach idx {1 2 3} tag {Event Site Date} {
    configMenuText $m.edit $idx CrosstabEdit$tag $lang
  }

  ### Scid menus are the biggest steaming pile of shit S.A
  ### We have to skip over numbers for "separators"

  foreach idx   {1 2 3 4 5 6 7 8 9 11 12 13 14 16 17 19 20} tag {Ages Nats Tallies Ratings Titles Breaks Deleted Colors ColumnNumbers TieHead TieWin ThreeWin Group ColorPlain ColorHyper ColorRows RowsColor} {
    configMenuText $m.opt $idx CrosstabOpt$tag $lang
  }


  # Disable the Ages, Nats, Titles items if spellcheck not enabled. S.A
  if {!$::spellCheckFileExists} {
    $m.opt entryconfig 1 -state disabled -variable {}
    $m.opt entryconfig 2 -state disabled -variable {}
    $m.opt entryconfig 5 -state disabled -variable {}
  }

  foreach idx {1 2 3 4} tag {Score Name Country Rating} {
    configMenuText $m.sort $idx CrosstabSort$tag $lang
  }
  foreach idx {1 2 3 4} tag {Auto All Swiss Knockout} {
    configMenuText $m.type $idx CrosstabType$tag $lang
  }
  foreach idx {0 1} tag {Cross Index} {
    configMenuText $m.help $idx CrosstabHelp$tag $lang
  }
}


proc ::crosstab::Open {{game {}}} {
  global crosstab

  set w .crosstabWin
  if {[winfo exists $w]} {
    ::crosstab::Refresh $game
    raiseWin $w
    return
  }

  ::createToplevel $w
  ::setTitle $w "[tr WindowsCross]"
  wm minsize $w 10 5
  setWinLocation $w
  setWinSize $w

  menu $w.menu
  ::setMenu $w $w.menu
  $w.menu add cascade -label CrosstabFile -menu $w.menu.file
  $w.menu add cascade -label CrosstabSort -menu $w.menu.sort
  $w.menu add cascade -label CrosstabType -menu $w.menu.type
  $w.menu add cascade -label CrosstabOpt -menu $w.menu.opt
  $w.menu add cascade -label CrosstabEdit -menu $w.menu.edit
  $w.menu add cascade -label CrosstabHelp -menu $w.menu.help

  menu $w.menu.file
  menu $w.menu.sort -tearoff 1
  menu $w.menu.type -tearoff 1
  menu $w.menu.opt  -tearoff 1
  menu $w.menu.edit -tearoff 1
  menu $w.menu.help

  $w.menu.file add command -label CrosstabFileText -command {
    set ftype {
      { "Text files" {".txt"} }
      { "All files"  {"*"}    }
    }
    set fname [tk_getSaveFile -initialdir $::env(HOME) -filetypes [::utils::trTypesFichiers $ftype]  -title [::moderne::tr "Enregistrer le tableau croisé" "Save Crosstable"] -parent .crosstabWin]
    if {$fname != ""} {
      if {[catch {set tempfile [open $fname w]}]} {
        tk_messageBox -title [::moderne::tr "Siby : erreur d'enregistrement" "Siby: Error saving file"] \
          -type ok -icon warning -parent .crosstabWin \
          -message [::moderne::tr "Impossible d'enregistrer le fichier : $fname\n\n" "Unable to save the file: $fname\n\n"]
      } else {
        puts -nonewline $tempfile [.crosstabWin.f.text get 1.0 end]
        close $tempfile
      }
    }
  }
  $w.menu.file add command -label CrosstabFileHtml -command {
    set ftype {
      { "HTML files" {".html" ".htm"} }
      { "All files"  {"*"}    }
    }
    set fname [tk_getSaveFile -initialdir $::initialDir(html) -filetypes [::utils::trTypesFichiers $ftype]  -title [::moderne::tr "Enregistrer le tableau croisé en HTML" "Save Crosstable as HTML"] -parent .crosstabWin]
    if {$fname != ""} {
      if {[catch {set tempfile [open $fname w]}]} {
        tk_messageBox -title [::moderne::tr "Siby : erreur d'enregistrement" "Siby: Error saving file"] \
          -type ok -icon warning -parent .crosstabWin \
          -message [::moderne::tr "Impossible d'enregistrer le fichier : $fname\n\n" "Unable to save the file: $fname\n\n"]
      } else {
        catch {sc_game crosstable html $crosstab(sort) $crosstab(type) \
                 $crosstab(ratings) $crosstab(countries) $crosstab(tallies) $crosstab(titles) \
                 $crosstab(colors) $crosstab(groups) $crosstab(ages) \
                 $crosstab(breaks) $crosstab(cnumbers) $crosstab(deleted) $crosstab(threewin) $crosstab(tiewin) $crosstab(tiehead)} \
          result
        puts $tempfile $result
        close $tempfile
      }
    }
  }
  $w.menu.file add command -label CrosstabFileLaTeX -command {
    set ftype {
      { "LaTeX files" {".tex" ".ltx"} }
      { "All files"  {"*"}    }
    }
    set fname [tk_getSaveFile -initialdir $::initialDir(tex) -filetypes [::utils::trTypesFichiers $ftype]  -title [::moderne::tr "Enregistrer le tableau croisé en LaTeX" "Save Crosstable as LaTeX"] -parent .crosstabWin]
    if {$fname != ""} {
      if {[catch {set tempfile [open $fname w]}]} {
        tk_messageBox -title [::moderne::tr "Siby : erreur d'enregistrement" "Siby: Error saving file"] \
          -type ok -icon warning -parent .crosstabWin \
          -message [::moderne::tr "Impossible d'enregistrer le fichier : $fname\n\n" "Unable to save the file: $fname\n\n"]
      } else {
        catch {sc_game crosstable latex $crosstab(sort) $crosstab(type) \
                 $crosstab(ratings) $crosstab(countries) $crosstab(tallies) $crosstab(titles) \
                 $crosstab(colors) $crosstab(groups) $crosstab(ages) \
                 $crosstab(breaks) $crosstab(cnumbers) $crosstab(deleted) $crosstab(threewin) $crosstab(tiewin) $crosstab(tiehead)} \
          result
        puts $tempfile $result
        close $tempfile
      }
    }
  }
  $w.menu.file add separator
  $w.menu.file add command -label CrosstabFileClose \
    -command { .crosstabWin.b.cancel invoke } -accelerator Esc

  $w.menu.edit add command -label CrosstabEditEvent -command {
    nameEditor
    setNameEditorType event
    set editName [sc_game info event]
    set editNameNew $editName
    set editNameSelect crosstable
  }
  $w.menu.edit add command -label CrosstabEditSite -command {
    nameEditor
    setNameEditorType site
    set editName [sc_game info site]
    set editNameNew $editName
    set editNameSelect crosstable
  }
  $w.menu.edit add command -label CrosstabEditDate -command {
    nameEditor
    setNameEditorType date
    set editNameNew " "
    set editDate [sc_game info date]
    set editDateNew [sc_game info date]
    set editNameSelect crosstable
  }

  $w.menu.opt add checkbutton -label CrosstabOptAges \
    -variable crosstab(ages) -onvalue "+ages" \
    -offvalue "-ages" -command ::crosstab::Refresh
  $w.menu.opt add checkbutton -label CrosstabOptNats \
    -variable crosstab(countries) -onvalue "+countries" \
    -offvalue "-countries" -command ::crosstab::Refresh
  $w.menu.opt add checkbutton -label CrosstabOptTallies \
    -variable crosstab(tallies) -onvalue "+tallies" \
    -offvalue "-tallies" -command ::crosstab::Refresh
  $w.menu.opt add checkbutton -label CrosstabOptRatings \
    -variable crosstab(ratings) -onvalue "+ratings" -offvalue "-ratings" \
    -command ::crosstab::Refresh
  $w.menu.opt add checkbutton -label CrosstabOptTitles \
    -variable crosstab(titles) -onvalue "+titles" -offvalue "-titles" \
    -command ::crosstab::Refresh
  $w.menu.opt add checkbutton -label CrosstabOptBreaks \
    -variable crosstab(breaks) -onvalue "+breaks" \
    -offvalue "-breaks" -command ::crosstab::Refresh
  $w.menu.opt add checkbutton -label CrosstabOptDeleted \
    -variable crosstab(deleted) -onvalue "+deleted" \
    -offvalue "-deleted" -command ::crosstab::Refresh

  $w.menu.opt add checkbutton -label CrosstabOptColors \
    -underline 0 -variable crosstab(colors) \
    -onvalue "+colors" -offvalue "-colors" -command ::crosstab::Refresh
  $w.menu.opt add checkbutton -label CrosstabOptColumnNumbers \
    -underline 0 -variable crosstab(cnumbers) \
    -onvalue "+numcolumns" -offvalue "-numcolumns" -command ::crosstab::Refresh

  $w.menu.opt add separator

  $w.menu.opt add checkbutton -label CrosstabOptTieHead \
    -variable crosstab(tiehead) -command ::crosstab::Refresh -onvalue "+tiehead" -offvalue "-tiehead"
  $w.menu.opt add checkbutton -label CrosstabOptTieWin \
    -variable crosstab(tiewin) -command ::crosstab::Refresh -onvalue "+tiewin" -offvalue "-tiewin"

  $w.menu.opt add checkbutton -label CrosstabOptThreeWin \
    -variable crosstab(threewin) -command ::crosstab::Refresh  \
    -onvalue "+threewin" -offvalue "-threewin"
  $w.menu.opt add checkbutton -label CrosstabOptGroup \
    -underline 0 -variable crosstab(groups) \
    -onvalue "+groups" -offvalue "-groups" -command ::crosstab::Refresh

  $w.menu.opt add separator

  $w.menu.opt add radiobutton -label CrosstabOptColorPlain \
    -variable crosstab(text) -value plain -command ::crosstab::Refresh
  $w.menu.opt add radiobutton -label CrosstabOptColorHyper \
    -variable crosstab(text) -value hypertext -command ::crosstab::Refresh

  $w.menu.opt add separator

  $w.menu.opt add checkbutton -label CrosstabOptColorRows \
    -underline 0 -variable crosstab(colorrows) \
    -onvalue 1 -offvalue 0 -command ::crosstab::Refresh
  $w.menu.opt add command -label CrosstabOptRowsColor -command ::crosstab::SetCrossColour

  $w.menu.sort add radiobutton -label CrosstabSortScore \
    -variable crosstab(sort) -value score -command ::crosstab::Refresh
  $w.menu.sort add radiobutton -label CrosstabSortName \
    -variable crosstab(sort) -value name -command ::crosstab::Refresh
  $w.menu.sort add radiobutton -label CrosstabSortCountry \
    -variable crosstab(sort) -value country -command ::crosstab::Refresh
  $w.menu.sort add radiobutton -label CrosstabSortRating \
    -variable crosstab(sort) -value rating -command ::crosstab::Refresh

  $w.menu.type add radiobutton -label CrosstabTypeAuto \
    -variable crosstab(type) -value auto -command ::crosstab::Refresh
  $w.menu.type add radiobutton -label CrosstabTypeAll \
    -variable crosstab(type) -value allplay -command ::crosstab::Refresh
  $w.menu.type add radiobutton -label CrosstabTypeSwiss \
    -variable crosstab(type) -value swiss -command ::crosstab::Refresh
  $w.menu.type add radiobutton -label CrosstabTypeKnockout \
    -variable crosstab(type) -value knockout -command ::crosstab::Refresh

  $w.menu.help add command -label CrosstabHelpCross \
    -accelerator F1 -command {helpWindow Crosstable}
  $w.menu.help add command -label CrosstabHelpIndex \
     -command {helpWindow Index}

  ::crosstab::ConfigMenus

  # packing this here makes the text widget resize nicely ? S.A.
  frame $w.b
  pack $w.b -side bottom -fill x

  frame $w.f
  pack $w.f -side top -fill both -expand true
  # Causes flicker when updated
  # -width $::winWidth($w) -height $::winHeight($w) &&&
  set text $w.f.text
  text $text -wrap none -font font_Fixed -setgrid 1 -cursor top_left_arrow \
     -yscroll "$w.f.ybar set" -xscroll "$w.f.xbar set"
  ::htext::init $text

  $text tag configure rowColor -background $::crosscolor

  scrollbar $w.f.ybar -command "$text yview"
  scrollbar $w.f.xbar -orient horizontal -command "$text xview"
  grid $text -row 0 -column 0 -sticky nesw
  grid $w.f.ybar -row 0 -column 1 -sticky nesw
  grid $w.f.xbar -row 1 -column 0 -sticky nesw
  grid rowconfig $w.f 0 -weight 1 -minsize 0
  grid columnconfig $w.f 0 -weight 1 -minsize 0

  button $w.b.stop -textvar ::tr(Stop) -state disabled -font font_Small \
    -command { set ::htext::interrupt 1 }

  button $w.b.update -textvar ::tr(Update) -font font_Small -command ::crosstab::Refresh

  entry $w.b.find -width 10 -textvariable crosstab(find) -font font_Small -highlightthickness 0
  configFindEntryBox $w.b.find crosstab .crosstabWin.f.text

  button $w.b.cancel -textvar ::tr(Close) -font font_Small -command {
    focus .main
    destroy .crosstabWin
  }
  button $w.b.setfilter -textvar ::tr(SetFilter) -font font_Small -command {::crosstab::setFilter 0}
  button $w.b.addfilter -textvar ::tr(AddToFilter) -font font_Small -command {::crosstab::setFilter}

  button $w.b.font -textvar ::tr(Font) -font font_Small -command {FontDialogFixed .crosstabWin}

  pack $w.b.cancel $w.b.find $w.b.update -side right -pady 3 -padx 5
  pack $w.b.setfilter $w.b.addfilter -side left -pady 3 -padx 5

  standardShortcuts $w

  bind $w <Button-3> {tk_popup .crosstabWin.menu %X %Y}

  bind $w <F1>       "helpWindow Crosstable"
  bind $w <Escape>   ".crosstabWin.b.cancel invoke"
  bind $w <Up>       "$text yview scroll -1 units"
  bind $w <Down>     "$text yview scroll 1 units"
  bind $w <Prior>    "$text yview scroll -1 pages"
  bind $w <Next>     "$text yview scroll 1 pages"
  bind $w <Left>     "$text xview scroll -1 units"
  bind $w <Right>    "$text xview scroll 1 units"
  bind $w <Key-Home> "$text yview moveto 0"
  bind $w <Key-End>  "$text yview moveto 0.99"

  # MouseWheel Bindings:
  if {$::windowsOS || $::macOS} {
    bind $w <Shift-MouseWheel> {break}
    bind $w <MouseWheel> { .crosstabWin.f.text yview scroll [expr {- (%D / 120)}] units}
  } else {
    bind $text <Shift-Button-4> "$text xview scroll -5 units ; break"
    bind $text <Shift-Button-5> "$text xview scroll 5 units ; break"
    bind $text <Button-4> "$text yview scroll -1 units"
    bind $text <Button-5> "$text yview scroll  1 units"
    bind $text <Button> {
      # Buttons 6 and 7 are the left/right for advanced wheelscroll buttons
      # but aren't supported by Button-6 (see http://wiki.tcl.tk/12696)
      if {"%b" == "6"} { .crosstabWin.f.text xview scroll -10 units }
      if {"%b" == "7"} { .crosstabWin.f.text xview scroll  10 units }
    }
  }

  bindWheeltoFixed $w

  bind $w <Destroy> {}
  ::crosstab::Refresh $game

  bind $w.b <Configure> "recordWinSize $w"
  ::createToplevelFinalize $w
}

proc ::crosstab::SetCrossColour {} {
  global crosscolor crosstab
  set temp [tk_chooseColor -initialcolor $crosscolor -title [tr CrosstabOptRowsColor]]
  if {$temp != {}} {
    set crosscolor $temp
    if {!$crosstab(colorrows)} {
      set crosstab(colorrows) 1
      ::crosstab::Refresh
    }
    if {[winfo exists .crosstabWin.f.text]} {
      .crosstabWin.f.text tag configure rowColor -background $crosscolor
    }
  }
}

proc ::crosstab::setFilter {{round {}}} {
  global crosstab glstart crosstabGame crosstabBase

  set currentBase [sc_base current]
  if {$currentBase != $crosstabBase} {
    sc_base switch $crosstabBase
  }

  if {$round == {}} {
    sc_game crosstable filter -gameNumber $crosstabGame $crosstab(deleted)
  } else {
    sc_game crosstable filter -round $round -gameNumber $crosstabGame $crosstab(deleted)
  }

  if {$currentBase != $crosstabBase} {
    sc_base switch $currentBase
  }

  set glstart 1
  ::windows::stats::Refresh
}

proc ::crosstab::Refresh {{game {}}} {
  global crosstab crosstabGame crosstabBase
  set w .crosstabWin
  if {! [winfo exists $w]} { return }

  $w.f.text configure -state normal
  $w.f.text delete 1.0 end
  busyCursor .
  $w.f.text configure -state disabled
  ### Stop button is broken currently
  ### We need to implement it via sc_progressBar
  update idle
  # $w.b.stop configure -state normal
  foreach button {update cancel setfilter addfilter} {
    $w.b.$button configure -state disabled
  }
  # pack $w.b.stop -side right -padx 5 -pady 3
  # catch {grab $w.b.stop}
  # update

  if {$game == {}} {
    # Since we aren't autoupdating crosstable, remember which base/game the table is for, for ::crosstab::setFilter
    set crosstabGame [sc_game number]
  } else {
    set crosstabGame $game
  }
  set crosstabBase [sc_base current]

  if {[
  catch {sc_game crosstable $crosstab(text) $crosstab(sort) $crosstab(type) \
         $crosstab(ratings) $crosstab(countries) $crosstab(tallies) $crosstab(titles) \
         $crosstab(colors) $crosstab(groups) $crosstab(ages) \
         $crosstab(breaks) $crosstab(cnumbers) $crosstab(deleted) $crosstab(threewin) $crosstab(tiewin) $crosstab(tiehead) \
         -gameNumber $crosstabGame } result
  ]} {
    puts "sc_game crosstable failed"
  }

  $w.f.text configure -state normal
  if {$crosstab(text) == "plain"} {
    $w.f.text insert end $result
  } else {
    ::htext::display $w.f.text $result
  }

if {$crosstab(colorrows) && $crosstab(type) != "knockout"} {
  set start [$w.f.text search -- --------- 1.0]
  if {$start != {}} {
    set end [$w.f.text search -- --------- "$start +1line"]

    # Shade every second line to help readability
    $w.f.text configure -state normal
    set startline [expr {int($start) + 1}]
    set endline   [expr {int($end) - 1}]
    for {set i $startline} {$i <= $endline} {incr i 2} {
      $w.f.text tag add rowColor $i.0 "$i.end +1c"
    }
  }
}
  unbusyCursor .
  # catch {grab release $w.b.stop}
  # $w.b.stop configure -state disabled
  ### We cant use forget on this because of a bug in the windows packer
  # pack forget $w.b.stop
  foreach button {update cancel setfilter addfilter} {
    $w.b.$button configure -state normal
  }
  $w.f.text configure -state disabled
}

### end of crosstable.tcl

################################################################################
### Siby: the tournament's crosstable, redrawn (Yosha 2026-11-05). The games
### of the event come from "sc_game crosstable data"; four views: round
### robin (« grille Berger »), Swiss (« grille américaine »), match (the
### score game by game) and knockout, Auto choosing. A result opens its game
### in a new tab; the headers sort. The old text window stays for exports.
################################################################################

namespace eval ::moderne::croise {
  variable w .tableauWin
  variable vue auto          ;# auto berger suisse match ko
  variable tri score         ;# score nom elo
  variable base 0
  variable entete {}
  variable parties {}        ;# {num round white black welo belo result date}
  variable joueurs           ;# joueurs(name) = dict elo pts n gains sb bh bhc perf parties
  variable ordre {}          ;# names in the order shown
  variable cellules          ;# cellules(item,col) = game numbers
  variable equipes {}        ;# game number -> {white's team, black's team}
}
proc ::moderne::croise::T {fr en} { return [::moderne::tr $fr $en] }

### For game gnum of base b (default: the game on the board)
proc ::moderne::croise::ouvrir {{b {}} {gnum {}}} {
  variable base
  variable entete
  variable parties
  if {$b eq {}} { set b [sc_base current] }
  if {$gnum eq {}} { set gnum [sc_game number] }
  if {![string is integer -strict $gnum] || $gnum < 1} {
    tk_messageBox -parent . -icon info -title Siby -message [T "Aucune partie de base sur l'échiquier." "No database game on the board."]
    return
  }
  set courante [sc_base current]
  if {$b != $courante} { sc_base switch $b }
  set t0 [clock milliseconds]
  set code [catch {sc_game crosstable data -gameNumber $gnum} r]
  if {$b != $courante} { catch {sc_base switch $courante} }
  variable duree [expr {[clock milliseconds] - $t0}]
  if {$code || [llength $r] < 2} {
    tk_messageBox -parent . -icon info -title Siby -message [T "Pas de tournoi pour cette partie." "No tournament for this game."]
    return
  }
  set base $b
  set entete [lindex $r 0]
  set parties [lrange $r 1 end]
  lireEquipes
  calculer
  creer
  dessiner
}

### The teams of the games (WhiteTeam / BlackTeam tags, an Olympiad), when
### the first games carry them
proc ::moderne::croise::lireEquipes {} {
  variable base
  variable parties
  variable equipes
  set equipes {}
  set nums [lmap p $parties {lindex $p 0}]
  set vu 0
  foreach num [lrange $nums 0 9] {
    catch {lassign [lindex [sc_gaby tags $base $num $num WhiteTeam BlackTeam] 0] - eb en
      if {$eb ne {} && $en ne {}} { incr vu }}
  }
  if {!$vu} { return }
  foreach num $nums {
    if {[catch {lassign [lindex [sc_gaby tags $base $num $num WhiteTeam BlackTeam] 0] - eb en}]} { continue }
    if {$eb ne {} && $en ne {} && $eb ne $en} { dict set equipes $num [list $eb $en] }
  }
  # a game without the tags: the teams its two players have in the event's
  # other games (Gaby tags about 65 to 90 % of the older Olympiads' games),
  # when each player is always in the same team
  set equipeDe {}
  set doute {}
  foreach p $parties {
    lassign $p num - bl no
    if {![dict exists $equipes $num]} { continue }
    lassign [dict get $equipes $num] eb en
    foreach {j e} [list $bl $eb $no $en] {
      if {[dict exists $equipeDe $j] && [dict get $equipeDe $j] ne $e} { dict set doute $j 1 }
      dict set equipeDe $j $e
    }
  }
  foreach p $parties {
    lassign $p num - bl no
    if {[dict exists $equipes $num]} { continue }
    if {![dict exists $equipeDe $bl] || ![dict exists $equipeDe $no] || [dict exists $doute $bl] || [dict exists $doute $no]} { continue }
    set eb [dict get $equipeDe $bl] ; set en [dict get $equipeDe $no]
    if {$eb ne $en} { dict set equipes $num [list $eb $en] }
  }
}

### The team matches: {round teamA teamB pointsA pointsB games}, and
### equipesRes(team) = dict mp bp n matches (2 match points a win, 1 a draw)
proc ::moderne::croise::calculerEquipes {} {
  variable parties
  variable equipes
  variable equipesRes
  array unset equipesRes
  set rencontres {}
  foreach p $parties {
    lassign $p num rnd - - - - res
    if {![dict exists $equipes $num]} { continue }
    lassign [dict get $equipes $num] eb en
    set r [ronde $rnd]
    set pr [lsort [list $eb $en]]
    set cle [list $r {*}$pr]
    if {![dict exists $rencontres $cle]} { dict set rencontres $cle [list 0.0 0.0 {}] }
    lassign [dict get $rencontres $cle] pa pb ps
    set pt [points $res w]
    if {$pt ne {}} {
      set pn [expr {1.0 - $pt}]
      if {$eb eq [lindex $pr 0]} { set pa [expr {$pa + $pt}] ; set pb [expr {$pb + $pn}] } else { set pa [expr {$pa + $pn}] ; set pb [expr {$pb + $pt}] }
    }
    lappend ps $num
    dict set rencontres $cle [list $pa $pb $ps]
  }
  set l {}
  dict for {cle v} $rencontres {
    lassign $cle r a b
    lassign $v pa pb ps
    lappend l [list $r $a $b $pa $pb $ps]
    foreach {e pe po adv} [list $a $pa $pb $b $b $pb $pa $a] {
      if {![info exists equipesRes($e)]} { set equipesRes($e) [dict create mp 0 bp 0.0 n 0 matchs {}] }
      dict set equipesRes($e) bp [expr {[dict get $equipesRes($e) bp] + $pe}]
      dict incr equipesRes($e) mp [expr {$pe > $po ? 2 : $pe == $po ? 1 : 0}]
      dict incr equipesRes($e) n
      dict lappend equipesRes($e) matchs [list $r $adv $pe $po $ps]
    }
  }
  return $l
}

### Team table: teams by match points then board points, one column per
### round (score of the match and the opponent's rank)
proc ::moderne::croise::equipesVue {t} {
  variable equipesRes
  variable cellules
  calculerEquipes
  set noms [lsort -command ::moderne::croise::compareEquipes [array names equipesRes]]
  set rondes {}
  foreach e $noms { foreach m [dict get $equipesRes($e) matchs] { lappend rondes [lindex $m 0] } }
  set rondes [lsort -integer -unique $rondes]
  set specs [list [list rang # 34 center 0] [list nom [T "Équipe" "Team"] 170 w 0]]
  foreach r $rondes { lappend specs [list r$r [expr {$r == 0 ? "?" : "R$r"}] 64 center 0] }
  lappend specs [list mp [T "PM" "MP"] 46 center 0] [list bp [T "PP" "BP"] 50 center 0]
  colonnes $t $specs
  set rang {}
  set i 0
  foreach e $noms { dict set rang $e [incr i] }
  set i 0
  foreach e $noms {
    incr i
    set ligne [list $i [nomCourt $e]]
    set parRonde {}
    foreach m [dict get $equipesRes($e) matchs] { dict lappend parRonde [lindex $m 0] $m }
    foreach r $rondes {
      if {![dict exists $parRonde $r]} { lappend ligne "" ; continue }
      set txt {} ; set nums {}
      foreach m [dict get $parRonde $r] {
        lassign $m - adv pe po ps
        lappend txt "[demi $pe]–[demi $po] · [dict get $rang $adv]"
        lappend nums {*}$ps
      }
      lappend ligne [join $txt " | "]
      set cellules(e$i,r$r) $nums
    }
    lappend ligne [dict get $equipesRes($e) mp] [demi [dict get $equipesRes($e) bp]]
    $t insert {} end -id e$i -values $ligne
  }
}
proc ::moderne::croise::compareEquipes {a b} {
  variable equipesRes
  foreach k {mp bp} {
    set x [dict get $equipesRes($a) $k] ; set y [dict get $equipesRes($b) $k]
    if {$x != $y} { return [expr {$y > $x ? 1 : -1}] }
  }
  return [string compare -nocase $a $b]
}

### Major round number ("3.2" -> 3; "?" -> 0)
proc ::moderne::croise::ronde {r} {
  if {[regexp {^([0-9]+)} $r -> n]} { return [scan $n %d] }
  return 0
}

proc ::moderne::croise::points {res cote} {
  switch -- $res {
    1-0 { return [expr {$cote eq "w" ? 1.0 : 0.0}] }
    0-1 { return [expr {$cote eq "b" ? 1.0 : 0.0}] }
    =   { return 0.5 }
  }
  return {}
}

proc ::moderne::croise::calculer {} {
  variable parties
  variable joueurs
  array unset joueurs
  array set joueurs {}
  # (in the order of the rounds, then of the dates)
  set parties [lsort -command ::moderne::croise::ordreParties $parties]
  foreach p $parties {
    lassign $p num rnd bl no wel bel res date
    foreach {nom elo cote adv} [list $bl $wel w $no $no $bel b $bl] {
      if {![info exists joueurs($nom)]} { set joueurs($nom) [dict create elo 0 pts 0.0 n 0 gains 0 parties {}] }
      if {[string is integer -strict $elo] && $elo > [dict get $joueurs($nom) elo]} { dict set joueurs($nom) elo $elo }
      set pt [points $res $cote]
      dict lappend joueurs($nom) parties [list $num $rnd $adv $cote $pt $res]
      if {$pt ne {}} {
        dict set joueurs($nom) pts [expr {[dict get $joueurs($nom) pts] + $pt}]
        dict incr joueurs($nom) n
        if {$pt == 1.0} { dict incr joueurs($nom) gains }
      }
    }
  }
  # tiebreaks: Buchholz (cut 1), Sonneborn-Berger, performance
  foreach nom [array names joueurs] {
    set bh 0.0 ; set sb 0.0 ; set adv {} ; set somme 0 ; set ne 0
    foreach g [dict get $joueurs($nom) parties] {
      lassign $g - - a - pt
      if {$pt eq {}} { continue }
      set pa [dict get $joueurs($a) pts]
      set bh [expr {$bh + $pa}]
      lappend adv $pa
      if {$pt == 1.0} { set sb [expr {$sb + $pa}] } elseif {$pt == 0.5} { set sb [expr {$sb + $pa / 2.0}] }
      set ea [dict get $joueurs($a) elo]
      if {$ea > 0} { incr somme $ea ; incr ne }
    }
    set bhc $bh
    if {[llength $adv] > 1} { set bhc [expr {$bh - [lindex [lsort -real $adv] 0]}] }
    set perf {}
    set n [dict get $joueurs($nom) n]
    if {$ne > 0 && $n > 0} {
      set p [expr {[dict get $joueurs($nom) pts] / double($n)}]
      set p [expr {min(0.99, max(0.01, $p))}]
      set perf [expr {round(double($somme) / $ne - 400.0 * log10(1.0 / $p - 1.0))}]
    }
    dict set joueurs($nom) bh $bh
    dict set joueurs($nom) bhc $bhc
    dict set joueurs($nom) sb $sb
    dict set joueurs($nom) perf $perf
  }
}

proc ::moderne::croise::ordreParties {a b} {
  set r [expr {[ronde [lindex $a 1]] - [ronde [lindex $b 1]]}]
  if {$r != 0} { return $r }
  set c [string compare [lindex $a 1] [lindex $b 1]]
  if {$c != 0} { return $c }
  set c [string compare [lindex $a 7] [lindex $b 7]]
  if {$c != 0} { return $c }
  return [expr {[lindex $a 0] - [lindex $b 0]}]
}

### The view that fits: two players, a match; most pairs played, round
### robin; the pairs forming a tree of mini-matches, knockout; else Swiss
proc ::moderne::croise::vueAuto {} {
  variable joueurs
  variable parties
  variable equipes
  set n [array size joueurs]
  if {$n == 2} { return match }
  # (an Olympiad: most games carry both teams)
  if {[dict size $equipes] >= 0.8 * [llength $parties]} { return equipes }
  set paires {}
  foreach p $parties { dict set paires [lsort [list [lindex $p 2] [lindex $p 3]]] 1 }
  set np [dict size $paires]
  if {$n <= 40 && $np >= 0.8 * $n * ($n - 1) / 2.0} { return berger }
  if {[llength [matchsKo]]} { return ko }
  return suisse
}

### The knockout's mini-matches, {stage a b games} in the order played, or
### {} when the event is not a knockout. Round tags are not trusted (World
### Cup 2023 in Gaby: R1..R4, R11, R12, R20..R23): a knockout is a set of
### pairs with hardly any cycle (each match puts a player out; the
### third-place match closes one), where at most about half the players play
### a second match. A match's stage: one more than its players' matches so far.
proc ::moderne::croise::matchsKo {} {
  variable joueurs
  variable parties
  set n [array size joueurs]
  if {$n < 4} { return {} }
  set paires {}
  foreach p $parties { dict lappend paires [lsort [list [lindex $p 2] [lindex $p 3]]] $p }
  # cycles = pairs - players + components (union-find)
  array set pere {}
  foreach nom [array names joueurs] { set pere($nom) $nom }
  set comp $n
  foreach pr [dict keys $paires] {
    lassign $pr a b
    while {$pere($a) ne $a} { set a $pere($a) }
    while {$pere($b) ne $b} { set b $pere($b) }
    if {$a ne $b} { set pere($a) $b ; incr comp -1 }
  }
  if {[dict size $paires] - $n + $comp > 2} { return {} }
  # the matches in the order played (first game: round, date, number)
  set matchs {}
  dict for {pr ps} $paires {
    set ps [lsort -command ::moderne::croise::ordreDate $ps]
    lappend matchs [list [lindex $ps 0] $pr $ps]
  }
  set matchs [lsort -command ::moderne::croise::ordreDate1 $matchs]
  set deja {}
  set res {}
  set second 0
  foreach m $matchs {
    lassign $m - pr ps
    lassign $pr a b
    set na [expr {[dict exists $deja $a] ? [dict get $deja $a] : 0}]
    set nb [expr {[dict exists $deja $b] ? [dict get $deja $b] : 0}]
    foreach j [list $a $b] x [list $na $nb] { if {$x == 1} { incr second } ; dict set deja $j [expr {$x + 1}] }
    lappend res [list [expr {max($na, $nb) + 1}] $a $b $ps]
  }
  if {$second == 0 || $second > 0.6 * $n + 2} { return {} }
  return $res
}
proc ::moderne::croise::ordreDate {a b} {
  set c [string compare [lindex $a 7] [lindex $b 7]]
  if {$c != 0} { return $c }
  return [expr {[lindex $a 0] - [lindex $b 0]}]
}
proc ::moderne::croise::ordreDate1 {a b} { return [ordreDate [lindex $a 0] [lindex $b 0]] }

### Players in the order shown
proc ::moderne::croise::trier {} {
  variable joueurs
  variable tri
  variable ordre
  set l [array names joueurs]
  switch -- $tri {
    nom { set ordre [lsort -dictionary $l] }
    elo { set ordre [lsort -command [list ::moderne::croise::compare elo] $l] }
    default { set ordre [lsort -command [list ::moderne::croise::compare score] $l] }
  }
}
proc ::moderne::croise::compare {cle a b} {
  variable joueurs
  if {$cle eq "elo"} {
    set d [expr {[dict get $joueurs($b) elo] - [dict get $joueurs($a) elo]}]
    if {$d != 0} { return $d }
  }
  foreach k {pts bhc sb gains} {
    set x [dict get $joueurs($a) $k] ; set y [dict get $joueurs($b) $k]
    if {$x != $y} { return [expr {$y > $x ? 1 : -1}] }
  }
  return [string compare -nocase $a $b]
}

proc ::moderne::croise::demi {x} {
  if {$x eq {}} { return {} }
  set e [expr {int(floor($x))}]
  set f [expr {$x - $e}]
  if {abs($f - 0.5) < 0.01} { return [expr {$e == 0 ? "½" : "$e½"}] }
  return $e
}
proc ::moderne::croise::symb {pt} {
  if {$pt eq {}} { return "*" }
  if {$pt == 1.0} { return 1 }
  if {$pt == 0.5} { return ½ }
  return 0
}

proc ::moderne::croise::creer {} {
  variable w
  if {[winfo exists $w]} { raise $w ; return }
  toplevel $w -background [::moderne::c fond]
  wm title $w [T "Tableau du tournoi" "Crosstable"]
  catch {wm geometry $w 1100x640}
  set h [ttk::frame $w.h -padding {14 10 14 6}]
  pack $h -side top -fill x
  ttk::label $h.titre -font font_Bold
  ttk::label $h.sous -foreground [::moderne::c texteDoux]
  pack $h.titre $h.sous -anchor w
  set v [ttk::frame $w.v -padding {14 0 14 6}]
  pack $v -side top -fill x
  foreach {code fr en} {auto Auto Auto berger "Grille Berger" "Round robin" suisse "Grille américaine" "Swiss" match Match Match ko "Élimination directe" "Knockout" equipes "Équipes" "Teams"} {
    ttk::radiobutton $v.$code -text [T $fr $en] -value $code -variable ::moderne::croise::vue \
        -style Toolbutton -command ::moderne::croise::dessiner
    pack $v.$code -side left -padx {0 4}
  }
  ttk::menubutton $v.plus -text "⋯" -menu $v.plus.m -style Toolbutton
  menu $v.plus.m -tearoff 0
  $v.plus.m add command -label [T "Mettre les parties dans la liste" "Put the games in the game list"] -command ::moderne::croise::filtrer
  $v.plus.m add command -label [T "Version texte (exports)" "Text version (exports)"] -command ::moderne::croise::texte
  pack $v.plus -side right
  ttk::label $v.duree -foreground [::moderne::c texteDoux] -font font_Small
  pack $v.duree -side right -padx 8
  set f [ttk::frame $w.f]
  pack $f -side top -fill both -expand 1 -padx 14 -pady {0 12}
  ttk::treeview $f.t -show headings -selectmode browse -yscrollcommand [list $f.y set] -xscrollcommand [list $f.x set]
  ttk::scrollbar $f.y -orient vertical -command [list $f.t yview]
  ttk::scrollbar $f.x -orient horizontal -command [list $f.t xview]
  grid $f.t $f.y -sticky nsew
  grid $f.x -sticky ew
  grid rowconfigure $f 0 -weight 1
  grid columnconfigure $f 0 -weight 1
  bind $f.t <ButtonRelease-1> {::moderne::croise::clic %x %y %X %Y}
  bind $f.t <Return> {::moderne::croise::clic {} {} {} {}}
  bind $w <Escape> [list destroy $w]
  catch {::moderne::repeindre $w}
}

### The game list shows the tournament's games
proc ::moderne::croise::filtrer {} {
  variable base
  variable parties
  set g [lindex [lindex $parties 0] 0]
  set c [sc_base current]
  if {$base != $c} { ::file::SwitchToBase $base }
  catch {sc_game crosstable filter -gameNumber $g}
  catch {::windows::gamelist::Refresh}
  catch {::windows::stats::Refresh}
}

proc ::moderne::croise::texte {} {
  variable base
  variable parties
  set g [lindex [lindex $parties 0] 0]
  if {$base != [sc_base current]} { ::file::SwitchToBase $base }
  ::crosstab::OpenAncien $g
}

proc ::moderne::croise::colonnes {t specs} {
  # specs: {id titre largeur ancre etirer}
  $t configure -columns [lmap s $specs {lindex $s 0}]
  foreach s $specs {
    lassign $s id titre larg ancre etirer
    $t heading $id -text $titre -command [list ::moderne::croise::entete $id]
    $t column $id -width $larg -minwidth 20 -anchor $ancre -stretch $etirer
  }
}

### A header clicked: sorted by it (score, name or Elo)
proc ::moderne::croise::entete {id} {
  variable tri
  switch -- $id {
    nom { set tri nom }
    elo { set tri elo }
    rang - pts - sb - bh - bhc - gains - perf - mp - bp { set tri score }
    default { return }
  }
  dessiner
}

proc ::moderne::croise::dessiner {} {
  variable w
  variable vue
  variable entete
  variable joueurs
  variable parties
  variable duree
  variable equipes
  if {![winfo exists $w]} { return }
  # (the Teams view only for an event whose games carry the teams)
  if {[dict size $equipes]} {
    if {"$w.v.equipes" ni [pack slaves $w.v]} { pack $w.v.equipes -side left -padx {0 4} -after $w.v.ko }
  } else {
    pack forget $w.v.equipes
    if {$vue eq "equipes"} { set vue auto }
  }
  lassign $entete ev site edate
  set dates [lsort [lmap p $parties {lindex $p 7}]]
  set d1 [string map {.?? {}} [lindex $dates 0]] ; set d2 [string map {.?? {}} [lindex $dates end]]
  $w.h.titre configure -text $ev
  set n [array size joueurs]
  $w.h.sous configure -text "[expr {$site ni {{} ?} ? "$site • " : ""}][expr {$d1 eq $d2 ? $d1 : "$d1 – $d2"}] • [T "$n joueur·ses" "$n players"] • [T "[llength $parties] parties" "[llength $parties] games"]"
  $w.v.duree configure -text "[expr {$duree}] ms"
  set v $vue
  if {$v eq "auto"} { set v [vueAuto] }
  # (Auto names the view it chose)
  set noms [dict create berger [T "Grille Berger" "Round robin"] suisse [T "Grille américaine" "Swiss"] match Match ko [T "Élimination directe" "Knockout"] equipes [T "Équipes" "Teams"]]
  $w.v.auto configure -text [expr {$vue eq "auto" ? "Auto · [dict get $noms $v]" : "Auto"}]
  trier
  set t $w.f.t
  variable cellules
  array unset cellules
  $t delete [$t children {}]
  switch -- $v {
    berger { berger $t }
    match  { match $t }
    ko     { ko $t }
    equipes { if {[dict size $equipes]} { equipesVue $t } else { suisse $t } }
    default { suisse $t }
  }
  ::moderne::zebrer $t
}

proc ::moderne::croise::nomCourt {nom} {
  if {[string length $nom] > 28} { return "[string range $nom 0 26]…" }
  return $nom
}

proc ::moderne::croise::berger {t} {
  variable ordre
  variable joueurs
  variable cellules
  set n [llength $ordre]
  set specs [list [list rang # 34 center 0] [list nom [T "Nom" "Name"] 170 w 0] [list elo Elo 50 center 0]]
  for {set i 1} {$i <= $n} {incr i} { lappend specs [list c$i $i [expr {$n > 16 ? 30 : 40}] center 0] }
  lappend specs [list pts Pts 46 center 0] [list sb SB 50 center 0] [list gains [T "Gains" "Wins"] 50 center 0] [list perf Perf 54 center 0]
  colonnes $t $specs
  set idx {}
  set i 0
  foreach nom $ordre { dict set idx $nom [incr i] }
  set i 0
  foreach nom $ordre {
    incr i
    set j $joueurs($nom)
    set ligne [list $i [nomCourt $nom] [expr {[dict get $j elo] ? [dict get $j elo] : ""}]]
    set parAdv {}
    foreach g [dict get $j parties] {
      lassign $g num - adv - pt
      dict lappend parAdv $adv [list $num $pt]
    }
    for {set k 1} {$k <= $n} {incr k} {
      set adv [lindex $ordre [expr {$k - 1}]]
      if {$adv eq $nom} { lappend ligne "·" ; continue }
      if {![dict exists $parAdv $adv]} { lappend ligne "" ; continue }
      lappend ligne [join [lmap x [dict get $parAdv $adv] {symb [lindex $x 1]}] ""]
      set cellules(r$i,c$k) [lmap x [dict get $parAdv $adv] {lindex $x 0}]
    }
    lappend ligne [demi [dict get $j pts]] [format %.2f [dict get $j sb]] [dict get $j gains] [dict get $j perf]
    $t insert {} end -id r$i -values $ligne
  }
}

proc ::moderne::croise::suisse {t} {
  variable ordre
  variable joueurs
  variable cellules
  set rondes {}
  foreach nom $ordre { foreach g [dict get $joueurs($nom) parties] { lappend rondes [ronde [lindex $g 1]] } }
  set rondes [lsort -integer -unique $rondes]
  set specs [list [list rang # 34 center 0] [list nom [T "Nom" "Name"] 170 w 0] [list elo Elo 50 center 0]]
  foreach r $rondes { lappend specs [list r$r [expr {$r == 0 ? "?" : [T "R$r" "R$r"]}] 58 center 0] }
  lappend specs [list pts Pts 46 center 0] [list bhc [T "Bu-1" "BH-C1"] 54 center 0] [list bh [T "Bu" "BH"] 50 center 0] [list sb SB 50 center 0] [list perf Perf 54 center 0]
  colonnes $t $specs
  set rang {}
  set i 0
  foreach nom $ordre { dict set rang $nom [incr i] }
  set i 0
  foreach nom $ordre {
    incr i
    set j $joueurs($nom)
    set ligne [list $i [nomCourt $nom] [expr {[dict get $j elo] ? [dict get $j elo] : ""}]]
    set parRonde {}
    foreach g [dict get $j parties] {
      lassign $g num rnd adv cote pt
      dict lappend parRonde [ronde $rnd] [list $num $adv $cote $pt]
    }
    foreach r $rondes {
      if {![dict exists $parRonde $r]} { lappend ligne "" ; continue }
      set txt {}
      set nums {}
      foreach x [dict get $parRonde $r] {
        lassign $x num adv cote pt
        lappend txt "[symb $pt] [expr {$cote eq "w" ? "○" : "●"}] [dict get $rang $adv]"
        lappend nums $num
      }
      lappend ligne [join $txt " | "]
      set cellules(r$i,r$r) $nums
    }
    lappend ligne [demi [dict get $j pts]] [demi [dict get $j bhc]] [demi [dict get $j bh]] [format %.2f [dict get $j sb]] [dict get $j perf]
    $t insert {} end -id r$i -values $ligne
  }
}

proc ::moderne::croise::match {t} {
  variable parties
  variable joueurs
  variable cellules
  variable w
  # (A: White in the first game)
  set a [lindex [lindex $parties 0] 2] ; set b [lindex [lindex $parties 0] 3]
  set pa 0.0 ; set pb 0.0
  colonnes $t [list [list n [T "Partie" "Game"] 60 center 0] [list rnd [T "Ronde" "Round"] 60 center 0] \
      [list blanc [T "Blancs" "White"] 170 w 0] [list res [T "Résultat" "Result"] 70 center 0] [list noir [T "Noirs" "Black"] 170 w 0] \
      [list score [T "Score" "Score"] 110 center 0] [list date Date 100 center 0]]
  set k 0
  foreach p $parties {
    lassign $p num rnd bl no - - res date
    incr k
    set ptA [points $res [expr {$bl eq $a ? "w" : "b"}]]
    if {$ptA ne {}} { set pa [expr {$pa + $ptA}] ; set pb [expr {$pb + 1.0 - $ptA}] }
    set r [string map {= ½-½} $res]
    $t insert {} end -id p$k -values [list $k $rnd [nomCourt $bl] $r [nomCourt $no] "[demi $pa] – [demi $pb]" [string map {.?? {}} $date]]
    set cellules(p$k,*) [list $num]
  }
  $w.h.titre configure -text "[nomCourt $a]  [demi $pa] – [demi $pb]  [nomCourt $b]"
}

proc ::moderne::croise::ko {t} {
  variable cellules
  colonnes $t [list [list rnd [T "Tour" "Round"] 60 center 0] [list a [T "Nom" "Name"] 170 w 0] [list sa "" 50 center 0] \
      [list sb "" 50 center 0] [list b [T "Nom" "Name"] 170 w 0] [list det [T "Parties" "Games"] 220 w 1]]
  set matchs [matchsKo]
  if {![llength $matchs]} {
    # (Knockout chosen by hand on another event: one match per pair)
    variable parties
    set paires {}
    foreach p [lsort -command ::moderne::croise::ordreDate $parties] { dict lappend paires [lsort [list [lindex $p 2] [lindex $p 3]]] $p }
    dict for {pr ps} $paires { lappend matchs [list 1 {*}$pr $ps] }
  }
  set k 0
  foreach m [lsort -integer -index 0 $matchs] {
    lassign $m r a b ps
    set pa 0.0 ; set pb 0.0 ; set det {}
    set nums {}
    foreach p $ps {
      lassign $p num - bl - - - res
      set x [points $res [expr {$bl eq $a ? "w" : "b"}]]
      if {$x ne {}} { set pa [expr {$pa + $x}] ; set pb [expr {$pb + 1.0 - $x}] }
      lappend det [symb $x]
      lappend nums $num
    }
    # (the winner first)
    if {$pb > $pa} { lassign [list $b $a $pb $pa] a b pa pb ; set det [lmap x $det {expr {$x eq "1" ? 0 : $x eq "0" ? 1 : $x}}] }
    incr k
    $t insert {} end -id k$k -values [list $r [nomCourt $a] [demi $pa] [demi $pb] [nomCourt $b] [join $det " "]]
    set cellules(k$k,*) $nums
  }
}

### A result clicked: its game opened (several: a menu to choose)
proc ::moderne::croise::clic {x y X Y} {
  variable w
  variable cellules
  variable base
  variable parties
  set t $w.f.t
  if {$x eq {}} {
    set item [$t focus] ; set col {}
  } else {
    if {[$t identify region $x $y] ne "cell"} { return }
    set item [$t identify row $x $y]
    set col [$t column [$t identify column $x $y] -id]
  }
  if {$item eq {}} { return }
  set nums {}
  if {[info exists cellules($item,$col)]} { set nums $cellules($item,$col) } elseif {[info exists cellules($item,*)]} { set nums $cellules($item,*) }
  if {![llength $nums]} { return }
  if {[llength $nums] == 1} { ouvrirPartie [lindex $nums 0] ; return }
  set m $w.choix
  catch {destroy $m}
  menu $m -tearoff 0
  foreach num $nums {
    set p [lsearch -inline -index 0 $parties $num]
    lassign $p - rnd bl no - - res
    $m add command -label "[string map {= ½-½} $res]  $bl – $no  ([T ronde round] $rnd)" -command [list ::moderne::croise::ouvrirPartie $num]
  }
  if {$X eq {}} { set X [winfo pointerx .] ; set Y [winfo pointery .] }
  tk_popup $m $X $Y
}

proc ::moderne::croise::ouvrirPartie {num} {
  variable base
  ::moderne::onglets::ouvrir $base $num
}

### The old window (its menus: text, HTML and LaTeX exports)
if {![llength [info commands ::crosstab::OpenAncien]]} {
  rename ::crosstab::Open ::crosstab::OpenAncien
  proc ::crosstab::Open {{game {}}} {
    if {![::moderne::actif]} { return [::crosstab::OpenAncien $game] }
    ::moderne::croise::ouvrir {} $game
  }
}
