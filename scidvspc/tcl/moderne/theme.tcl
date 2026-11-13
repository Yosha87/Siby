
###
### Siby: interface theme (dark, light or classic)
###
### This file changes no SCID vs. PC behavior: it only sets colors,
### reliefs and margins. It is inserted right after tcl/start.tcl, so after
### options.dat has been read (where ::moderne::theme is stored) and before
### the windows are created.
###
### Themes:
###   sombre    : palette inspired by Lichess's dark theme (default)
###   clair     : light palette, warm grey like Lichess's light theme
###   classique : original SCID vs. PC look; no longer offered (a saved
###               "classique" becomes "sombre")
###

namespace eval ::moderne {
  variable palette
  # (the classic look is no longer offered: a saved one becomes the dark theme)
  if {[info exists ::moderne::theme] && $::moderne::theme eq "classique"} { set ::moderne::theme sombre }

  # Dark palette (inspired by Lichess)
  array set palettes {
    sombre {
      fond        #1c1c1c
      surface     #202020
      surface2    #2b2b2b
      survol      #383838
      champ       #1f1f1f
      bordure     #333333
      texte       #e4e4e4
      texteFort   #fafafa
      texteDoux   #9a9a9a
      inactif     #666666
      accent      #57c8ff
      accentFonce #2f60d8
      lien        #6fc3f7
      selection   #2f60d8
      ligneAlt    #282828
      tuileIcone  #2b3a44
      pastille    #353535
      trait       #353535
    }
    clair {
      fond        #e7e5e2
      surface     #f4f3f1
      surface2    #dcd9d5
      survol      #d0ccc7
      champ       #ffffff
      bordure     #bdb8b2
      texte       #1c1c1c
      texteFort   #000000
      texteDoux   #565656
      inactif     #8c8c8c
      accent      #1b6fc2
      accentFonce #145a9e
      lien        #1b6fc2
      selection   #bed6f0
      ligneAlt    #eceae7
      tuileIcone  #d6e4ef
      pastille    #e9e6e2
      trait       #e2dfdb
    }
  }

  # Mapping of colors hard-coded in SCID vs. PC (designed for a white
  # background) to colors readable on a dark background.
  array set versSombre {
    blue        #6fb3f2
    darkblue    #8ab4f8
    darkBlue    #8ab4f8
    navy        #8ab4f8
    steelblue   #7fa7d4
    steelBlue   #7fa7d4
    SteelBlue   #7fa7d4
    steelblue4  #7fa7d4
    blue4       #8ab4f8
    darkslateblue #a7a2f0
    red         #f07a6a
    red3        #f07a6a
    darkred     #e5806f
    red4        #e5806f
    green       #7fd18b
    darkgreen   #7fd18b
    darkGreen   #7fd18b
    green4      #7fd18b
    seagreen    #7fd18b
    black       #e4e4e4
    gray        #8f8c88
    grey        #8f8c88
    gray40      #9a9792
    grey40      #9a9792
    gray50      #8f8c88
    grey50      #8f8c88
    gray25      #b0ada9
    darkgray    #9a9792
    brown       #d2a679
    rosybrown   #d6a3a3
    indianred   #e58b8b
    purple      #c79bf2
    magenta     #e69be6
    orange      #f0b35b
    white       #1f1f1f
    #ffffff     #1f1f1f
    #FFFFFF     #1f1f1f
    lightYellow #3a3627
    lightyellow #3a3627
    LightYellow #3a3627
    linen       #2b2b2b
    ivory       #2b2b2b
    gray90      #2b2b2b
    grey90      #2b2b2b
    gray85      #333333
    grey85      #333333
    gray95      #242424
    grey95      #242424
    lightsteelblue1 #2f3a47
    lightsteelblue3 #3c4b5c
    lightblue   #2f4a5f
    LightBlue   #2f4a5f
    skyblue     #4f7fa6
    SkyBlue     #4f7fa6
    yellow      #5a5326
    #d9d9d9     #2b2b2b
    #e6e6e6     #2b2b2b
  }
}

proc ::moderne::actif {} {
  return [expr {[info exists ::moderne::theme] && $::moderne::theme in {sombre clair}}]
}

proc ::moderne::c {nom} {
  variable palette
  return $palette($nom)
}

### Converts a color "designed for a white background" into a color
### readable in the current theme. Unknown colors are left as they are.
### Every other row of a list on a slightly different background (like
### Lichess's tables); a highlighted row ("suivant") keeps its own color
proc ::moderne::zebrer {t} {
  if {![winfo exists $t]} { return }
  $t tag configure zebre -background [c ligneAlt]
  set k 0
  foreach id [$t children {}] {
    set tags [lsearch -all -inline -not -exact [$t item $id -tags] zebre]
    if {$k % 2 && "suivant" ni $tags} { lappend tags zebre }
    $t item $id -tags $tags
    incr k
  }
}

proc ::moderne::adapter {couleur} {
  variable versSombre
  if {![info exists ::moderne::theme] || $::moderne::theme ne "sombre"} {
    return $couleur
  }
  if {[info exists versSombre($couleur)]} {
    return $versSombre($couleur)
  }
  return $couleur
}

### Repaints the tags of a Text widget for the dark theme.
proc ::moderne::repeindreText {w} {
  if {![winfo exists $w] || [winfo class $w] ne "Text"} { return }
  foreach tag [$w tag names] {
    foreach opt {-foreground -background} {
      if {[catch {$w tag cget $tag $opt} val] || $val eq {}} { continue }
      set nouv [::moderne::adapter $val]
      if {$nouv ne $val} { catch {$w tag configure $tag $opt $nouv} }
    }
  }
  foreach opt {-background -foreground} {
    set val [$w cget $opt]
    set nouv [::moderne::adapter $val]
    if {$nouv ne $val} { catch {$w configure $opt $nouv} }
  }
}

### Walks a widget tree and adapts the hard-coded colors.
proc ::moderne::repeindre {{w .}} {
  if {![::moderne::actif] || $::moderne::theme ne "sombre"} { return }
  if {![winfo exists $w]} { return }
  set classe [winfo class $w]
  switch -- $classe {
    Text { ::moderne::repeindreText $w }
    Label - Button - Checkbutton - Radiobutton - Message - Frame - Labelframe - Toplevel - Canvas - Menubutton - Listbox - Entry - Spinbox {
      foreach opt {-background -foreground} {
        if {[catch {$w cget $opt} val]} { continue }
        set nouv [::moderne::adapter $val]
        if {$nouv ne $val} { catch {$w configure $opt $nouv} }
      }
      if {$classe in {Checkbutton Radiobutton}} { catch {::moderne::classiques::fond $w} }
    }
  }
  foreach enfant [winfo children $w] {
    ::moderne::repeindre $enfant
  }
}

### Applies the theme: Tk option database (classic widgets) + ttk styles.
proc ::moderne::appliquer {} {
  variable palettes
  variable palette
  if {![::moderne::actif]} { return }

  array set palette [set palettes($::moderne::theme)]
  set p 60   ;# priority: above the defaults, below explicit settings

  # --- Classic Tk widgets -----------------------------------------------
  option add *background          [c fond] $p
  option add *foreground          [c texte] $p
  option add *activeBackground    [c survol] $p
  option add *activeForeground    [c texteFort] $p
  option add *highlightBackground [c fond] $p
  option add *highlightColor      [c accent] $p
  option add *selectBackground    [c selection] $p
  option add *selectForeground    [c texteFort] $p
  option add *inactiveSelectBackground [c surface2] $p
  option add *insertBackground    [c texteFort] $p
  option add *troughColor         [c fond] $p
  option add *disabledForeground  [c inactif] $p
  option add *selectColor         [c champ] $p

  foreach classe {Text Listbox Entry Spinbox} {
    option add *$classe.background  [c champ] $p
    option add *$classe.foreground  [c texte] $p
    option add *$classe.relief      flat $p
    option add *$classe.borderWidth 0 $p
    option add *$classe.highlightThickness 1 $p
    option add *$classe.highlightBackground [c bordure] $p
  }
  option add *Text.padX 6 $p
  option add *Text.padY 4 $p

  # Flat buttons, with a little breathing room
  option add *Button.relief             flat $p
  option add *Button.overRelief         flat $p
  option add *Button.borderWidth        0 $p
  option add *Button.highlightThickness 0 $p
  option add *Button.background         [c surface2] $p
  option add *Button.activeBackground   [c survol] $p
  option add *Button.padX               10 $p
  option add *Button.padY               3 $p
  option add *Menubutton.relief         flat $p
  option add *Menubutton.background     [c surface2] $p
  option add *Checkbutton.highlightThickness 0 $p
  option add *Radiobutton.highlightThickness 0 $p
  # On Windows, Tk paints the inside of the indicator with selectColor, checked
  # or not (the dot or check mark takes the text color): use a field color,
  # otherwise everything looks checked. Elsewhere, selectColor = checked.
  if {[tk windowingsystem] eq "win32"} {
    option add *Checkbutton.selectColor   [c champ] $p
    option add *Radiobutton.selectColor   [c champ] $p
  } else {
    option add *Checkbutton.selectColor   [c accent] $p
    option add *Radiobutton.selectColor   [c accent] $p
  }
  option add *Scale.highlightThickness  0 $p
  option add *Scale.troughColor         [c bordure] $p
  option add *Scale.sliderRelief        raised $p
  option add *Scale.activeBackground    [c accent] $p
  option add *Labelframe.relief         groove $p
  # Classic spinboxes: flat arrows, on the field background
  option add *Spinbox.buttonBackground  [c surface2] $p
  option add *Spinbox.buttonUpRelief    flat $p
  option add *Spinbox.buttonDownRelief  flat $p
  option add *Spinbox.buttonCursor      hand2 $p
  option add *Spinbox.disabledBackground [c fond] $p
  option add *Spinbox.readonlyBackground [c champ] $p
  option add *Entry.disabledBackground  [c fond] $p
  option add *Entry.readonlyBackground  [c champ] $p

  # Menus
  option add *Menu.background         [c surface] $p
  option add *Menu.foreground         [c texte] $p
  option add *Menu.activeBackground   [c accent] $p
  option add *Menu.activeForeground   #ffffff $p
  option add *Menu.relief             flat $p
  option add *Menu.borderWidth        1 $p
  option add *Menu.activeBorderWidth  0 $p
  option add *Menu.selectColor        [c accent] $p

  # Thin, flat scrollbars
  option add *Scrollbar.background         [c surface2] $p
  option add *Scrollbar.activeBackground   [c survol] $p
  option add *Scrollbar.troughColor        [c fond] $p
  option add *Scrollbar.relief             flat $p
  option add *Scrollbar.borderWidth        0 $p
  option add *Scrollbar.elementBorderWidth 0 $p
  option add *Scrollbar.highlightThickness 0 $p
  option add *Scrollbar.width              11 $p

  # Tooltips
  option add *TooltipBackground [c surface2] $p

  catch {. configure -background [c fond]}

  # --- ttk widgets: Sun Valley theme (rounded controls, MIT) ---------------
  if {[::moderne::sunValley]} {
    ::moderne::stylesSunValley
    ::moderne::defil::installer
    catch {::moderne::classiques::installer}
    return
  }

  # --- Otherwise: "clam" theme, recolored ---------------------------------
  catch {ttk::style theme use clam}
  ttk::style configure . \
      -background [c fond] -foreground [c texte] \
      -fieldbackground [c champ] -bordercolor [c bordure] \
      -lightcolor [c surface] -darkcolor [c fond] \
      -troughcolor [c fond] -arrowcolor [c texte] \
      -selectbackground [c selection] -selectforeground [c texteFort] \
      -insertcolor [c texteFort] -focuscolor [c accent] \
      -font font_Regular
  ttk::style map . \
      -background [list disabled [c fond] active [c survol]] \
      -foreground [list disabled [c inactif]]

  ttk::style configure TButton -padding {10 3} -relief flat -borderwidth 1 \
      -background [c surface2] -bordercolor [c surface2] \
      -lightcolor [c surface2] -darkcolor [c surface2]
  ttk::style map TButton \
      -background [list pressed [c accentFonce] active [c survol]] \
      -bordercolor [list focus [c accent]] \
      -lightcolor [list pressed [c accentFonce] active [c survol]] \
      -darkcolor [list pressed [c accentFonce] active [c survol]]
  ttk::style configure Toolbutton -padding 3 -relief flat -background [c fond]
  ttk::style map Toolbutton -background [list active [c survol] selected [c surface2]]

  ttk::style configure TCheckbutton -indicatorbackground [c champ] -indicatorforeground [c accent]
  ttk::style configure TRadiobutton -indicatorbackground [c champ] -indicatorforeground [c accent]
  ttk::style map TCheckbutton -indicatorbackground [list selected [c accent]] -indicatorforeground [list selected #ffffff]
  ttk::style map TRadiobutton -indicatorbackground [list selected [c accent]] -indicatorforeground [list selected #ffffff]

  ttk::style configure TEntry -padding 3 -fieldbackground [c champ]
  ttk::style configure TSpinbox -padding 2 -fieldbackground [c champ] -arrowcolor [c texte]
  ttk::style configure TCombobox -padding 2 -fieldbackground [c champ] -arrowcolor [c texte]
  ttk::style map TCombobox \
      -fieldbackground [list readonly [c champ] disabled [c fond]] \
      -foreground [list readonly [c texte]] \
      -selectbackground [list readonly [c champ]] \
      -selectforeground [list readonly [c texte]]
  option add *TCombobox*Listbox.background [c champ] $p
  option add *TCombobox*Listbox.foreground [c texte] $p
  option add *TCombobox*Listbox.selectBackground [c accent] $p
  option add *TCombobox*Listbox.selectForeground #ffffff $p

  ttk::style configure TNotebook -background [c fond] -borderwidth 0 -tabmargins {2 4 2 0}
  ttk::style configure TNotebook.Tab -padding {12 4} -background [c fond] \
      -foreground [c texteDoux] -bordercolor [c fond] -lightcolor [c fond]
  ttk::style map TNotebook.Tab \
      -background [list selected [c surface] active [c surface2]] \
      -foreground [list selected [c texteFort] active [c texte]] \
      -lightcolor [list selected [c accent]] \
      -expand [list selected {0 0 0 0}]

  ttk::style configure Treeview -background [c champ] -fieldbackground [c champ] \
      -foreground [c texte] -bordercolor [c bordure] -rowheight [expr {[font metrics font_Regular -linespace] + 6}]
  ttk::style map Treeview -background [list selected [c selection]] -foreground [list selected [c texteFort]]
  ttk::style configure Heading -background [c surface2] -foreground [c texte] -relief flat -padding {6 3}
  ttk::style map Heading -background [list active [c survol]]

  ttk::style configure TScrollbar -background [c surface2] -troughcolor [c fond] \
      -bordercolor [c fond] -lightcolor [c surface2] -darkcolor [c surface2] \
      -arrowcolor [c texteDoux] -gripcount 0 -arrowsize 11
  ttk::style map TScrollbar -background [list active [c survol]]
  ttk::style configure TPanedwindow -background [c fond]
  ttk::style configure Sash -sashthickness 5 -gripcount 0 -background [c fond]
  ttk::style configure TLabelframe -background [c fond] -bordercolor [c bordure]
  ttk::style configure TLabelframe.Label -background [c fond] -foreground [c texteDoux]
  ttk::style configure TScale -background [c surface2] -troughcolor [c champ]
  ttk::style configure TProgressbar -background [c accent] -troughcolor [c champ]
  ttk::style configure TSeparator -background [c bordure]

  # The original variables used throughout SCID vs. PC
  if {$::moderne::theme eq "sombre"} {
    set ::rowcolor       #33312e   ;# alternating rows (tree, crosstable…)
    set ::highlightcolor #3b3936
    set ::switchercolor  #3c4b5c
    set ::crosscolor     #3b3936
    set ::progcolor      [c accent]
    set ::buttoncolor    [c accent]
  }
}

### Loads the Sun Valley theme (bitmaps/sv_ttk); 1 if available
proc ::moderne::sunValley {} {
  set nom [expr {$::moderne::theme eq "clair" ? "sun-valley-light" : "sun-valley-dark"}]
  if {$nom ni [ttk::style theme names]} {
    set dossier {}
    # (config.tcl, which sets scidShareDir, is read after this file)
    set candidats {}
    if {[info exists ::scidShareDir]} { lappend candidats [file join $::scidShareDir bitmaps sv_ttk] }
    if {[info exists ::scidExeDir]} {
      lappend candidats [file join $::scidExeDir bitmaps sv_ttk] \
          [file normalize [file join $::scidExeDir .. share scid bitmaps sv_ttk]] \
          [file normalize [file join $::scidExeDir .. Resources bitmaps sv_ttk]]
    }
    lappend candidats [file join [file dirname [info nameofexecutable]] bitmaps sv_ttk]
    foreach d $candidats {
      if {[file exists [file join $d dark.tcl]]} { set dossier $d ; break }
    }
    if {$dossier eq {}} { return 0 }
    # Fonts expected by the theme: SCID's
    foreach {f base} {SunValleyCaptionFont font_Small SunValleyBodyFont font_Regular} {
      if {$f ni [font names]} { font create $f {*}[font actual $base] }
    }
    set fichier [expr {$nom eq "sun-valley-light" ? "light.tcl" : "dark.tcl"}]
    if {[catch {uplevel #0 [list source -encoding utf-8 [file join $dossier $fichier]]} err]} {
      puts stderr "Siby: Sun Valley theme unavailable ($err)"
      return 0
    }
  }
  if {[catch {ttk::style theme use $nom}]} { return 0 }
  return 1
}

### Scrollbars: SCID's classic "scrollbar" widgets (with arrows, raised)
### become thin ttk scrollbars of the theme. Options specific to classic
### scrollbars (-width, -relief…) are ignored without error.
namespace eval ::moderne::defil {
  variable ignorees {-width -relief -bd -borderwidth -highlightthickness
    -highlightbackground -highlightcolor -background -bg -troughcolor
    -activebackground -activerelief -elementborderwidth -jump -repeatdelay
    -repeatinterval -foreground -fg}
}

proc ::moderne::defil::filtrer {opts} {
  variable ignorees
  set res {}
  foreach {o v} $opts {
    set plein [lsearch -inline -glob $ignorees ${o}*]
    if {$o in $ignorees || ($plein ne {} && [string length $o] > 3)} { continue }
    lappend res $o $v
  }
  return $res
}

proc ::moderne::defil::creer {chemin args} {
  if {[catch {ttk::scrollbar $chemin {*}[filtrer $args]} err]} {
    catch {destroy $chemin}
    return [::moderne::defil::scrollbarTk $chemin {*}$args]
  }
  # The widget keeps its name; its command goes through a relay that
  # ignores the classic options
  set reel ::moderne::defil::w$chemin
  rename ::$chemin $reel
  interp alias {} ::$chemin {} ::moderne::defil::relais $reel
  bind $chemin <Destroy> [list ::moderne::defil::fin %W $chemin]
  return $chemin
}

proc ::moderne::defil::fin {w chemin} {
  if {$w ne $chemin} { return }
  catch {interp alias {} ::$chemin {}}
}

proc ::moderne::defil::relais {reel cmd args} {
  variable ignorees
  switch -- $cmd {
    configure {
      if {[llength $args] == 1 && [lindex $args 0] in $ignorees} { return {} }
      if {[llength $args] <= 1} { return [$reel configure {*}$args] }
      set f [filtrer $args]
      if {[llength $f]} { return [$reel configure {*}$f] }
      return {}
    }
    cget {
      if {[lindex $args 0] in $ignorees} {
        if {[lindex $args 0] eq "-width"} { return 10 }
        return {}
      }
      return [$reel cget {*}$args]
    }
    activate { return {} }
    default { return [$reel $cmd {*}$args] }
  }
}

proc ::moderne::defil::installer {} {
  if {[llength [info commands ::moderne::defil::scrollbarTk]]} { return }
  rename ::scrollbar ::moderne::defil::scrollbarTk
  proc ::scrollbar {chemin args} { return [::moderne::defil::creer $chemin {*}$args] }
}

### Tweaks on top of Sun Valley: palette colors, SCID fonts, slightly
### roomier margins
proc ::moderne::stylesSunValley {} {
  ttk::style configure . \
      -background [c fond] -foreground [c texte] \
      -troughcolor [c fond] -focuscolor [c accentFonce] \
      -selectbackground [c selection] -selectforeground [c texteFort] \
      -insertwidth 1 -insertcolor [c texteFort] \
      -fieldbackground [c fond] -font font_Regular -borderwidth 0 -relief flat
  ttk::style map . -foreground [list disabled [c inactif]]
  ttk::style configure TLabel -background [c fond] -foreground [c texte]
  ttk::style configure TFrame -background [c fond]
  ttk::style configure TButton -padding {10 3 10 4}
  ttk::style configure Toolbutton -padding {4 2 4 3}
  ttk::style configure TNotebook.Tab -font font_Regular
  ttk::style configure TLabelframe.Label -font font_Small -foreground [c texteDoux]
  ttk::style configure Heading -font font_Small -foreground [c texteDoux]
  ttk::style configure Treeview -background [c fond] -foreground [c texte] -font font_Regular \
      -rowheight [expr {[font metrics font_Regular -linespace] + 7}]
  ttk::style map Treeview -background [list selected [c survol]] -foreground [list selected [c texteFort]]
  ttk::style configure Sash -sashthickness 6 -gripcount 0 \
      -lightcolor [c fond] -darkcolor [c fond] -bordercolor [c fond] -background [c fond]
  ttk::style configure TPanedwindow -background [c fond]
  ttk::style configure TProgressbar -background [c accentFonce]
  # "Segment" buttons (exclusive choices, e.g. time control): the active
  # choice has a solid background
  set ns [expr {$::moderne::theme eq "clair" ? "::ttk::theme::sv_light" : "::ttk::theme::sv_dark"}]
  catch {
    upvar #0 ${ns}::I I
    ttk::style theme settings [ttk::style theme use] {
      ttk::style element create Segment.button image \
          [list $I(empty) pressed $I(button-pressed) selected $I(button-rest) \
               {active selected} $I(button-hover) active $I(button-hover)] \
          -border 4 -sticky nsew
      ttk::style layout Segment.Toolbutton {
        Segment.button -children {
          Toolbutton.padding -children { Toolbutton.label -side left -expand 1 }
        }
      }
      ttk::style configure Segment.Toolbutton -padding {6 3 6 3} -anchor center
    }
  }
  option add *TCombobox*Listbox.background [c surface] 60
  option add *TCombobox*Listbox.foreground [c texte] 60
  option add *TCombobox*Listbox.selectBackground [c accentFonce] 60
  option add *TCombobox*Listbox.selectForeground #ffffff 60
  option add *TCombobox*Listbox.font font_Regular 60
  # Original variables used throughout SCID vs. PC
  if {$::moderne::theme eq "sombre"} {
    set ::rowcolor       [c ligneAlt]
    set ::highlightcolor [c surface2]
    set ::switchercolor  #2a3d55
    set ::crosscolor     [c surface2]
    set ::progcolor      [c accentFonce]
    set ::buttoncolor    [c accentFonce]
  }
}

::moderne::appliquer

### Side-to-move indicator (small square left of the board): hidden once
### and for all with the modern theme, the evaluation bars taking its
### place; it can be shown again (menu of the game panel).
if {![info exists ::moderne::accueilMasque]} {
  set ::splash::keepopen 0
  set ::moderne::accueilMasque 1
}
### Status bar below the board (database, game number, flags, menu
### help): hidden once, hard to read and of little use
# Siby: material difference next to the board hidden (once; it can be
# shown again in the options)
if {![info exists ::moderne::materielMasque]} {
  set ::gameInfo(showMaterial) 0
  set ::moderne::materielMasque 1
}
if {[::moderne::actif]} {
  # (hidden at every start; the menu shows it for the session)
  set ::gameInfo(showStatus) 0
  set ::moderne::barreEtatMasquee 1
}

### Notation of the moves: figurines (default, like Lichess: in the
### notation and everywhere moves are shown), English letters (KQRBN), or
### the letters of the language (RDTFC in French)
if {![info exists ::moderne::notation]} { set ::moderne::notation figurines }
# On Windows the figurines are drawn from a fallback font (wrong size and
# alignment): letters of the language by default, once (figurines can be
# chosen again in the options)
if {$::windowsOS && ![info exists ::moderne::notationWindows]} {
  set ::moderne::notationWindows 1
  if {$::moderne::notation eq "figurines"} { set ::moderne::notation langue }
}
proc ::moderne::appliquerNotation {{rafraichir 1}} {
  switch -- $::moderne::notation {
    figurines {
      if {[info exists ::graphFigurineAvailable] && $::graphFigurineAvailable} { set ::useGraphFigurine 1 }
      set ::translatePieces 0
    }
    anglais { set ::useGraphFigurine 0 ; set ::translatePieces 0 }
    langue  { set ::useGraphFigurine 0 ; set ::translatePieces 1 }
  }
  # (the letters the C side writes: they followed the old choice until the
  # next language change)
  catch ::moderne::lettresPieces
  if {$rafraichir} {
    catch {updateBoard -pgn}
    catch {set ::moderne::biblio::cache [dict create]}
    catch {set ::moderne::biblio::ordreCache {}}
    catch {::moderne::biblio::maj}
    foreach w [winfo children .] {
      if {[regexp {^\.analysisWin([0-9]+)$} $w -> n]} {
        catch {::moderne::moteur::lignes $n}
        catch {::moderne::toby::afficher $n}
      }
    }
  }
}
after idle {catch {::moderne::appliquerNotation 0}}

### A move (SAN, English letters) as the notation shows it: figurines
### (♘f3), English letters (Nf3) or the language's letters (Cf3), the same
### everywhere moves are shown
### Move numbers with a space, as Lichess: "36. Kh2", "36... Kh2" (Yosha,
### 2026-11-04); set once for everyone, the notation's options still change it
if {![info exists ::moderne::espacesNumeros]} {
  set ::pgn::moveNumberSpaces 1
  set ::moderne::espacesNumeros 1
}

proc ::moderne::coupTexte {san} {
  switch -- $::moderne::notation {
    figurines {
      set l [string index $san 0]
      if {$l in {K Q R B N}} { return "[dict get {K ♔ Q ♕ R ♖ B ♗ N ♘} $l][string range $san 1 end]" }
      return $san
    }
    langue { return [::trans $san] }
  }
  return $san
}

### Old toolbar above the board (SCID icons): hidden once, like Lichess
### (everything is in the menus; Options › Toolbar brings it back for the
### session); hidden at every start, the navigation buttons are below the board
if {[::moderne::actif]} {
  set ::gameInfo(showTool) 0
  set ::moderne::barreOutilsMasquee 1
}

### Siby: the old toolbar, the game info and the status bar are not used
### (their content is in the notation, the player bands, the window title,
### the game list and My databases): their menu entries are removed
proc ::moderne::retirerBarres {} {
  if {![::moderne::actif]} { return }
  foreach {m cmds} {.menu.windows {toggleGameInfo} .menu.options {configToolbar}
                    .main.gameInfo.menu {toggleToolbar showGameInfo toggleStatus}} {
    if {![winfo exists $m]} { continue }
    for {set i [$m index end]} {$i >= 0} {incr i -1} {
      if {[catch {$m entrycget $i -command} c]} { continue }
      if {[string trim $c] in $cmds} { $m delete $i }
    }
  }
}
# (called at the end of end.tcl, once the menus exist)

### Game info below the board (players, tournament, move): already in the
### notation; hidden at every start (Windows › Game Info, Ctrl+I, for the session)
if {[::moderne::actif]} {
  set ::gameInfo(show) 0
  set ::moderne::infosMasquees 1
}

### Time control for games against an engine: 3+2 by default (Lichess
### blitz). Applied once, only if the old default time control is unchanged.
if {![info exists ::moderne::cadence32]} {
  if {[info exists ::moderne::toby::jeu(minutes)] && $::moderne::toby::jeu(minutes) == 10 &&
      [info exists ::moderne::toby::jeu(inc)] && $::moderne::toby::jeu(inc) == 5} {
    set ::moderne::toby::jeu(minutes) 3
    set ::moderne::toby::jeu(inc) 2
  }
  if {$::sergame::wtime == 5 && $::sergame::winc == 10} {
    set ::sergame::wtime 3 ; set ::sergame::btime 3
    set ::sergame::winc 2 ; set ::sergame::binc 2
  }
  set ::moderne::cadence32 1
}

### Numbers in French style: "466 466" rather than "466,466" (thousands
### separator). Once, only if the original setting is unchanged.
if {![info exists ::moderne::nombresFr]} {
  if {[info exists ::language] && $::language eq "F" && $::locale(numeric) eq ".,"} {
    set ::locale(numeric) ". "
    catch {sc_info decimal $::locale(numeric)}
  }
  set ::moderne::nombresFr 1
}

### Move different from the game: new variation without asking (like
### ChessBase; Ctrl + move for the dialog). Applied once.
if {![info exists ::moderne::variantesSansQuestion]} {
  set ::askToReplaceMoves 0
  set ::moderne::choixCoupExistant var
  set ::moderne::variantesSansQuestion 1
}
if {[::moderne::actif] && ![info exists ::moderne::stmMasque]} {
  set ::boardSTM 0
  set ::moderne::stmMasque 1
}

### PGN window colors. They are stored in options.dat: a color is only
### replaced if it still has the default value of one of the themes (so a
### customization is respected), and the original colors come back when
### switching back to the classic look.
proc ::moderne::couleursPgn {} {
  set cles {Header Main Var Nag Comment Current NextMove Background}
  set defauts(classique) {#00008b #000000 #0000ee #aa2c2c #008b00 lightSteelBlue #fefe80 #ffffff}
  set defauts(sombre)    {#8a96a3 #e6e6e6 #6fc3f7 #f28b7d #8fd19e #2f60d8 #3d3a24 #1c1c1c}
  set defauts(sombre1)   {#8f9aa6 #e4e2df #6fb3f2 #ef8f7f #8fcf8f #2a6fb0 #4d4522 #1e1c1a}
  set defauts(clair)     {#5b6670 #1f1e1c #1b62b0 #b23a2a #2e7d32 #c4dcf3 #f6efc4 #ffffff}
  set theme classique
  if {[::moderne::actif]} { set theme $::moderne::theme }
  foreach cle $cles i {0 1 2 3 4 5 6 7} {
    if {![info exists ::pgnColor($cle)]} { continue }
    foreach t {classique sombre sombre1 clair} {
      if {[string equal -nocase $::pgnColor($cle) [lindex $defauts($t) $i]]} {
        set ::pgnColor($cle) [lindex $defauts($theme) $i]
        break
      }
    }
  }
}
::moderne::couleursPgn

### Other colors stored in options.dat, same principle:
### variable  classique  sombre  clair
proc ::moderne::couleursDiverses {} {
  set theme classique
  if {[::moderne::actif]} { set theme $::moderne::theme }
  set col [lsearch {classique sombre clair} $theme]
  foreach {var c s l} {
    ::windows::gamelist::currColor blue2 #6fb3f2 #1b62b0
  } {
    if {![info exists $var]} { continue }
    foreach val [list $c $s $l] {
      if {[string equal -nocase [set $var] $val]} {
        set $var [lindex [list $c $s $l] $col]
        break
      }
    }
  }
}
::moderne::couleursDiverses

### Once the windows are built, adapt the hard-coded colors (text tags,
### frames…) to the dark theme. Windows created later are handled when
### they first appear.
if {[::moderne::actif] && $::moderne::theme eq "sombre"} {
  bind Text <Map> {+::moderne::repeindreText %W}
  bind Toplevel <Map> {+if {"%W" eq [winfo toplevel %W]} {after idle [list ::moderne::repeindre %W]}}
}


# Also repaint the main window once built (docked windows)
if {[::moderne::actif] && $::moderne::theme eq "sombre"} {
  after 800 {::moderne::repeindre .}
}

### Label according to the interface language (French or English)
### "-before w.hist" for pack, if the analysis lines of engine window w
### are shown (Toby replaces them with its table): nothing otherwise
proc ::moderne::avantHist {w} {
  if {[winfo exists $w.hist] && [winfo manager $w.hist] eq "pack"} { return [list -before $w.hist] }
  return {}
}

### Label of a custom flag, for display: Gaby writes its flag labels into
### the base, in English from v12 ("Classic", "Rapid", "Blitz", "Corresp",
### "Online"), in French before ("Classiq", "Rapide", "Blitz", "Corresp",
### "En ligne"); they are shown in the interface language. Other labels
### are shown as written.
proc ::moderne::libelleDrapeau {desc} {
  set d [string trim $desc]
  switch -nocase -- $d {
    Classic - Classical - Classiq - Classique { return [::moderne::tr Classique Classical] }
    Rapid - Rapide { return [::moderne::tr Rapide Rapid] }
    Blitz { return Blitz }
    Corresp - Correspondence - Correspondance { return [::moderne::tr Corresp. Corresp.] }
    "En ligne" - Online { return [::moderne::tr "En ligne" Online] }
  }
  return $d
}

### Escape in window w: a separate window closed, a tab left as it is (it
### closed the Notation, the library, the preparation, its group vanished,
### Yosha 2026-11-13)
proc ::moderne::echap {w} {
  if {![winfo exists $w]} { return }
  if {$::docking::USE_DOCKING && [winfo exists .fdock[string range $w 1 end]]} { focus .main ; return }
  destroy $w
}

proc ::moderne::tr {fr en} {
  if {[info exists ::language] && $::language eq "F"} { return $fr }
  return $en
}

### A notice at the bottom right of the window, in Siby's style, instead of
### a system message box (Yosha, 2026-11-01): a title, a text, a file in
### small grey type (may be empty), a main button (its label and command;
### none if empty) and a button that closes it. It stays until a click.
### w: the notice's path (one of each kind at a time).
proc ::moderne::notice {w titre texte fichier libelle commande {fermer {}}} {
  catch {destroy $w}
  if {$fermer eq {}} { set fermer [::moderne::tr "Fermer" "Close"] }
  set fond [::moderne::c surface2]
  frame $w -background $fond -highlightthickness 1 \
      -highlightbackground [::moderne::c accent] -padx 16 -pady 12
  label $w.titre -background $fond -foreground [::moderne::c texteFort] -font font_Bold -anchor w -text $titre
  label $w.t -background $fond -foreground [::moderne::c texte] -font font_Regular \
      -justify left -anchor w -wraplength 400 -text $texte
  pack $w.titre $w.t -side top -fill x -pady {0 4}
  if {$fichier ne {}} {
    label $w.f -background $fond -foreground [::moderne::c texteDoux] -font font_Small \
        -justify left -anchor w -wraplength 400 -text [file nativename $fichier]
    pack $w.f -side top -fill x -pady {0 4}
  }
  frame $w.b -background $fond
  ttk::button $w.b.non -text $fermer -command [list destroy $w]
  if {$libelle ne {}} {
    ttk::button $w.b.ok -text $libelle -command "[list destroy $w] ; $commande"
    catch {$w.b.ok configure -style Accent.TButton}
    pack $w.b.non $w.b.ok -side right -padx {6 0}
  } else {
    pack $w.b.non -side right
  }
  pack $w.b -side top -fill x -pady {6 0}
  place $w -in . -relx 1.0 -rely 1.0 -x -18 -y -18 -anchor se
  raise $w
  return $w
}

### Siby theme entries at the top of the Options > Appearance menu
proc ::moderne::menuTheme {m} {
  # (the dark theme only, Yosha 2026-11-13: no choice offered)
  catch {::moderne::echiquier::menu $m}
  # (default set here: the menu entry would otherwise create it at 0)
  if {![info exists ::moderne::navVisible]} { set ::moderne::navVisible 1 }
  $m add checkbutton -label [::moderne::tr "Barre de navigation à gauche" "Navigation bar on the left"] \
      -variable ::moderne::navVisible -command ::moderne::navigation::afficher
  if {![info exists ::moderne::saisieClavier]} { set ::moderne::saisieClavier 0 }
  $m add checkbutton -label [::moderne::tr "Taper les coups au clavier (remplace f h l k j d g)" "Type moves on the keyboard (replaces f h l k j d g)"] \
      -variable ::moderne::saisieClavier -command ::moderne::clavier::basculerSaisie
  catch {destroy $m.notation}
  menu $m.notation -tearoff 0
  $m add cascade -label [::moderne::tr "Notation des coups" "Move notation"] -menu $m.notation
  foreach {v fr en} {
    figurines "Figurines (♘f3), partout" "Figurines (♘f3), everywhere"
    anglais   "Lettres anglaises (Nf3)" "English letters (Nf3)"
    langue    "Lettres de la langue (Cf3 en français)" "Letters of the language (Cf3 in French)"
  } {
    $m.notation add radiobutton -label [::moderne::tr $fr $en] -variable ::moderne::notation -value $v \
        -command ::moderne::appliquerNotation
  }
  # (the move times of games that have them, [%clk]: hidden by default)
  if {![info exists ::moderne::tempsCoups]} { set ::moderne::tempsCoups 0 }
  $m.notation add separator
  $m.notation add checkbutton -label [::moderne::tr "Afficher les temps des coups" "Show the move times"] \
      -variable ::moderne::tempsCoups -command {updateBoard -pgn}
  $m add checkbutton -label [::moderne::tr "Barre d'état sous l'échiquier (base, n° de partie, drapeaux)" "Status bar under the board"] \
      -variable ::gameInfo(showStatus) -command toggleStatus
  $m add checkbutton -label [::moderne::tr "Dernier coup : case teintée (Lichess)" "Last move: tinted square (Lichess)"] \
      -variable ::highlightLastMoveFill -command updateBoard
  $m add checkbutton -label [::moderne::tr "Pièce fantôme pendant un glisser (Lichess)" "Ghost piece while dragging (Lichess)"] \
      -variable ::moderne::fantome -command ::moderne::prise::basculer
  $m add checkbutton -label [::moderne::tr "Points des coups possibles (Lichess)" "Legal move dots (Lichess)"] \
      -variable ::moderne::pointsCoups -command ::moderne::prise::basculer
  $m add checkbutton -label [::moderne::tr "Demander quand un coup existe déjà" "Ask when a move already exists"] \
      -variable ::askToReplaceMoves
  $m add command -label [::moderne::tr "Toujours demander avant d'abandonner une partie modifiée" "Always ask before discarding a modified game"] \
      -command {set ::moderne::basesExploration {}}
  $m add checkbutton -label [::moderne::tr "Flèches du moteur sur l'échiquier (épaisse = meilleur coup)" "Engine arrows on the board (thick = best move)"] \
      -variable ::moderne::flechesMoteur -command ::moderne::basculerFleches
  $m add separator
}

### Engine arrows on the main board: off by default; when on, without
### numbers, in a single color, and thicker the better the move
### (tcl/board.tcl, ::board::mark::DrawVar)
proc ::moderne::basculerFleches {} {
  if {!$::moderne::flechesMoteur} {
    catch {.main.board.bd delete engine bvm}
  }
}


### The theme is built into every window when it is created: it applies
### when Siby starts again. Siby offers to restart now, with the same
### databases open.
proc ::moderne::changerTheme {} {
  catch {.menu.options invoke [tr OptionsSave]}
  set r [tk_messageBox -type yesno -icon question -title Siby -message [::moderne::tr \
      "Le thème s'applique au démarrage de Siby. Redémarrer maintenant (les bases ouvertes sont rouvertes) ?" \
      "The theme applies when Siby starts. Restart now (the open databases are opened again)?"]]
  if {$r eq "yes"} { ::moderne::redemarrer }
}

### Restarts Siby: the same program, the open databases on the command
### line (not the clipbase nor "Siby live", which opens itself). The new
### process starts once this one has really quit (unsaved games asked about
### as usual: cancelling the quit cancels the restart).
proc ::moderne::redemarrer {} {
  set cmd [list [info nameofexecutable]]
  # (Linux, macOS: tkscid runs the "scid" script)
  if {!$::windowsOS && [file exists $::argv0]
      && [file normalize $::argv0] ne [file normalize [info nameofexecutable]]} {
    lappend cmd -encoding utf-8 [file normalize $::argv0]
  }
  for {set i 1} {$i <= [sc_base count total]} {incr i} {
    if {$i == [sc_info clipbase] || ![sc_base inUse $i]} { continue }
    set f [sc_base filename $i]
    if {[string match "*Siby live" $f]} { continue }
    lappend cmd $f
  }
  set ::moderne::relance $cmd
  bind . <Destroy> {+if {"%W" eq "." && [info exists ::moderne::relance]} {
    catch {exec {*}$::moderne::relance &}
    unset ::moderne::relance
  }}
  ::file::Exit
  # (quit cancelled: no restart)
  if {[winfo exists .]} { after idle {catch {unset ::moderne::relance}} }
}

### End Siby

### Main window maximized (full screen with the title bar)
proc ::moderne::maximiser {} {
  # during startup: done on display (::moderne::revelerFenetre)
  if {[info exists ::moderne_demarrage] && $::moderne_demarrage} { return }
  if {$::windowsOS} {
    catch {wm state . zoomed}
  } else {
    catch {wm attributes . -zoomed 1}
  }
}

### Windows: the window made opaque once nothing of the layout is left to
### make (at the latest at limite)
proc ::moderne::montrerQuandPret {limite} {
  set reste [llength $::docking::differees]
  foreach id [after info] {
    if {[catch {lindex [after info $id] 0} script]} { continue }
    if {[string match "*fenetreDifferee*" $script] || [string match "*lancerDifferees*" $script] ||
        [string match "*restoreGeometry*" $script] || [string match "*resizeMainBoard*" $script]} { incr reste }
  }
  # (the Lab built at startup: its game list must be there)
  if {[llength [::moderne::lab::blocs]] && ![winfo exists .glistWin]} { incr reste }
  if {$reste && [clock milliseconds] < $limite} {
    catch {::sibyDemarrage::avancer 90}
    after 50 [list ::moderne::montrerQuandPret $limite]
    return
  }
  catch {update idletasks}
  catch {sc_cacher [wm frame .] 0}
  catch {wm attributes . -alpha 1.0}
  # (the startup window gone: Siby is there)
  catch ::sibyDemarrage::fin
}

### The main window brought back on the screen if it is not maximized and
### is out of sight (Windows' "Restore down" to a place of startup)
proc ::moderne::rentrerFenetre {} {
  if {[info exists ::moderne_demarrage] && $::moderne_demarrage} { return }
  if {[wm state .] ne "normal"} { return }
  # (Tk writes a negative place "+-30000")
  if {![regexp {^(\d+)x(\d+)\+?(-?\d+)\+?(-?\d+)$} [wm geometry .] -> l h x y]} { return }
  set sl [winfo screenwidth .] ; set sh [winfo screenheight .]
  if {$x > -200 && $y > -100 && $x < $sl - 200 && $y < $sh - 150} { return }
  set l [expr {min($l, int($sl * 0.85))}]
  set h [expr {min($h, int(($sh - 80) * 0.85))}]
  wm geometry . "${l}x${h}+[expr {($sl - $l) / 2}]+[expr {($sh - 80 - $h) / 2}]"
}

### End of startup: the window, ready, appears all at once in full screen
proc ::moderne::revelerFenetre {} {
  if {![info exists ::moderne_demarrage] || !$::moderne_demarrage} { return }
  set ::moderne_demarrage 0
  # (the reference database read in the background: started at the end of
  # end.tcl; again here when it was not known yet)
  after 1500 {catch ::moderne::mesbases::prelireReference}
  # on screen, then maximized. Its normal size (the title bar's "Restore
  # down" button): a little smaller, in the middle of the screen. (The
  # geometry is applied before maximizing: Windows kept the off-screen
  # place of startup as the normal one, and the button sent the window
  # there, out of sight, Yosha 2026-11-06)
  set l [expr {int([winfo screenwidth .] * 0.85)}]
  set h [expr {int(([winfo screenheight .] - 80) * 0.85)}]
  wm geometry . "${l}x${h}+[expr {([winfo screenwidth .] - $l) / 2}]+[expr {([winfo screenheight .] - 80 - $h) / 2}]"
  catch {update idletasks}
  if {[llength [info commands ::moderne::actif]] && [::moderne::actif]} { ::moderne::maximiser }
  # (never out of sight: a normal window placed off the screen comes back)
  bind . <Configure> {+if {"%W" eq "."} { after idle ::moderne::rentrerFenetre }}
  # My databases at startup, not the bare board and notation (Yosha
  # 2026-11-02), unless the layout restored already shows a view of Siby.
  # (The Lab was tried first: its engines and its library, which opens the
  # reference database, made the next layout changes block 4 to 8 s.)
  # SIBY_DEMARRAGE_BRUT: the bare start, for the test scenarios.
  catch {
    if {[::moderne::actif] && ([info exists ::env(SIBY_DEMARRAGE_BRUT)] ? $::env(SIBY_DEMARRAGE_BRUT) eq {} : 1) &&
        [::moderne::disposition::blocLab] eq {} && ![winfo exists $::moderne::mesbases::w] &&
        ![info exists ::moderne::disposition::choisie]} {
      # (the Lab built now, before the window is seen, and My databases
      # laid over it: the first click on the Lab is instant, 4.7 s on
      # Windows before; Yosha 2026-11-06. The reference database being
      # read in the background is not waited for: the library takes it
      # when it is there)
      # (the reading started first if it was not: the Lab would open the
      # reference at once, 3 s with Gaby)
      catch {if {[lindex [sc_base prepa] 0] ni {encours pret}} { ::moderne::mesbases::prelireReference }}
      catch {::sibyDemarrage::avancer 65}
      if {[catch {
        ::moderne::disposition::lab analyse
        catch {::sibyDemarrage::avancer 80}
        if {![::moderne::mesbases::superposer]} { error "no cover" }
      }]} {
        catch ::moderne::mesbases::vue
      }
    }
  }
  wm deiconify .
  catch {update idletasks}
  # (Toby loaded ahead when it is used: Options › Preload Toby)
  after 8000 {catch ::moderne::docks::prechargerToby}
  # (Windows: still transparent during the last adjustments, until the
  # Lab's slow windows (the game list…) are made and painted: shown at a
  # fixed 0.5 s, the window froze 1.5 s in front of the user while they were
  # made, Yosha 2026-11-06)
  after 300 [list ::moderne::montrerQuandPret [expr {[clock milliseconds] + 5000}]]
  # in front of the other windows, with the keyboard (Windows leaves a
  # program that took a while to start behind the others: a moment as
  # "topmost" brings it forward)
  catch {raise .}
  if {$::windowsOS} {
    catch {wm attributes . -topmost 1}
    after 400 {catch {wm attributes . -topmost 0} ; catch {focus -force .main}}
  }
  catch {focus -force .main}
  # instant libraries of databases already open (command line…)
  # (in a lambda: a global loop variable would clobber other code's ::b)
  after 3000 [list apply {{} {
    for {set b 1} {$b <= [sc_base count total]} {incr b} {
      if {[sc_base inUse $b]} { catch {::moderne::nsb::verifier $b} }
    }
  }}]
  # Gaby: daily update (first launch of the day, if enabled)
  after 8000 {catch ::moderne::gaby::demarrage}
  # Siby itself: a newer version offered (majsiby.tcl)
  after 20000 {catch ::moderne::majsiby::demarrage}
  # the official FIDE data of the players pack, unzipped in the background
  after 12000 {catch ::moderne::fide::preparer}
  # navigation bar on the left
  after 300 {::moderne::navigation::installerPret 50}
}

### Last folder where an engine was chosen (Tools › Engines › Browse)
if {![info exists ::moderne::dernierDossierModule]} { set ::moderne::dernierDossierModule {} }

### Siby: under the board, only the four arrows (like Lichess). The other
### buttons of SCID's bar (variations, autoplay, trial mode, flip, raise
### windows) are hidden; their shortcuts and menu entries still work.
proc ::moderne::barreFleches {} {
  if {![::moderne::actif] || ![winfo exists .main.button]} { return }
  foreach i {space exitVar intoVar addVar autoplay trial flip windows} {
    catch {pack forget .main.button.$i}
  }
}

### Siby: an explanation becomes a tooltip. Paragraphs explaining how a
### window works get in the way once one knows: the label shows a small
### "ⓘ", the text appears when the mouse is over it.
proc ::moderne::enBulle {w} {
  if {![winfo exists $w]} { return }
  set t [$w cget -text]
  if {[string trim $t] eq {}} { return }
  catch {$w configure -wraplength 0}
  $w configure -text "ⓘ" -cursor question_arrow
  catch {$w configure -foreground [::moderne::c texteDoux]}
  ::utils::tooltip::Set $w $t
}
catch {.tooltip.text configure -wraplength 420}

################################################################################
### Mouse wheel: over a widget that does not scroll itself (a chart, a label,
### a frame...), the wheel scrolls the nearest area around it that scrolls
### (a canvas, text, list or tree with a scrollbar). Widgets with their own
### wheel handling (text, lists, trees, spinboxes, the board...) keep it.
################################################################################

proc ::moderne::molette {w delta {evt <MouseWheel>}} {
  if {![winfo exists $w]} { return }
  # the widget handles the wheel itself (its own, class or tag bindings)
  foreach tag [bindtags $w] {
    if {$tag eq "all"} { continue }
    if {[bind $tag $evt] ne {}} { return }
  }
  set unites [expr {$delta > 0 ? -max(1, $delta / 120) : max(1, -$delta / 120)}]
  set p [winfo parent $w]
  while {$p ne {}} {
    # an area with its own wheel handler (e.g. the profile tab)
    if {[bind $p $evt] ne {}} {
      if {$evt eq "<MouseWheel>"} {
        event generate $p <MouseWheel> -delta $delta -x 1 -y 1
      } else {
        event generate $p $evt -x 1 -y 1
      }
      return
    }
    set cmd {}
    catch {set cmd [$p cget -yscrollcommand]}
    if {$cmd ne {}} {
      catch {$p yview scroll $unites units}
      return
    }
    if {$p eq [winfo toplevel $w]} { return }
    set p [winfo parent $p]
  }
}

bind all <MouseWheel> {+::moderne::molette %W %D}
if {[tk windowingsystem] eq "x11"} {
  bind all <Button-4> {+::moderne::molette %W 120 <Button-4>}
  bind all <Button-5> {+::moderne::molette %W -120 <Button-5>}
}

### Progress bars: the time ("0:10 / 0:12") is written in the middle of the
### bar, in the theme's text colour with a shadow in the background colour,
### so it stays readable over the coloured part and over the empty part.
### (The bars are drawn by sc_progressBar in many windows; it is wrapped
### here so they all get it.)
proc ::moderne::progresTexte {canv largeur hauteur tag} {
  if {![::moderne::actif] || ![winfo exists $canv] || $tag eq {}} { return }
  set ids [$canv find withtag $tag]
  if {$ids eq {} || [$canv find withtag sibyOmbre] ne {}} { return }
  set texte [lindex $ids 0]
  set x [expr {($largeur + 1) / 2}]
  set y [expr {($hauteur + 1) / 2}]
  $canv coords $texte $x $y
  $canv itemconfigure $texte -anchor center -fill [c texteFort]
  set ombre [$canv create text [expr {$x + 1}] [expr {$y + 1}] -anchor center \
      -font [$canv itemcget $texte -font] -text [$canv itemcget $texte -text] \
      -fill [c fond] -tags [list $tag sibyOmbre]]
  $canv lower $ombre $texte
}

if {[info commands ::sc_progressBar] ne {} && [info commands ::moderne::sc_progressBarC] eq {}} {
  rename ::sc_progressBar ::moderne::sc_progressBarC
  proc ::sc_progressBar {args} {
    set r [::moderne::sc_progressBarC {*}$args]
    if {[llength $args] == 5} {
      lassign $args canv - largeur hauteur tag
      catch {::moderne::progresTexte $canv $largeur $hauteur $tag}
    }
    return $r
  }
}

### PGN of the current game with English piece letters (sc_game pgn's
### arguments). With "translate pieces" on, sc_game pgn writes the
### interface's letters (Cf3 in French), which the import does not read:
### every PGN that is imported again, saved or copied goes through this
### (moves were lost on a French Windows, 2026-10-31)
proc ::moderne::pgnAnglais {args} {
  catch {sc_info language en}
  set code [catch {sc_game pgn {*}$args} r o]
  ::moderne::lettresPieces
  return -options $o $r
}

### Piece letters of the moves shown, as the settings ask
proc ::moderne::lettresPieces {} {
  set l en
  catch {
    if {$::language ne "E" && $::translatePieces} {
      set i [lindex $::langTable($::language) 4]
      if {$i ne {}} { set l $i }
    }
  }
  catch {sc_info language $l}
}

################################################################################
### Message boxes in Siby's colours (Yosha 2026-11-04: on Windows,
### tk_messageBox is Windows' own box, light in the dark theme and drawn
### like Windows 95). Same options and answers as tk_messageBox (-message
### -detail -icon -type -default -title -parent); the system's box when
### Siby's theme is not ready yet.
################################################################################

if {![llength [info commands ::moderne::messageNatif]]} {
  rename ::tk_messageBox ::moderne::messageNatif
  proc ::tk_messageBox {args} {
    if {[catch {::moderne::message {*}$args} r]} {
      # (Siby's colours unavailable, or a bad option: the system's box)
      return [::moderne::messageNatif {*}$args]
    }
    return $r
  }
}

namespace eval ::moderne { variable messageReponse ; variable messageN 0 }

proc ::moderne::message {args} {
  array set o {-message {} -detail {} -icon info -type ok -default {} -title Siby -parent . -boutons {}}
  foreach {k v} $args {
    if {![info exists o($k)]} { error "unknown option $k" }
    set o($k) $v
  }
  if {[llength [info commands ::moderne::c]] == 0} { error "theme not ready" }
  set boutons [dict get {ok {ok} okcancel {ok cancel} yesno {yes no} yesnocancel {yes no cancel}
                         retrycancel {retry cancel} abortretryignore {abort retry ignore}} $o(-type)]
  set noms [dict create ok OK cancel [tr Annuler Cancel] yes [tr Oui Yes] no [tr Non No] \
      retry [tr Réessayer Retry] abort [tr Abandonner Abort] ignore [tr Ignorer Ignore]]
  # (Siby's own buttons: {answer label ...}, the first one the default)
  if {[llength $o(-boutons)]} {
    set boutons {}
    foreach {code nom} $o(-boutons) { lappend boutons $code ; dict set noms $code $nom }
  }
  set defaut [expr {$o(-default) in $boutons ? $o(-default) : [lindex $boutons 0]}]
  # Escape: cancel, else no, else the only button
  set echap [lindex $boutons end]
  foreach b {cancel no ok} { if {$b in $boutons} { set echap $b ; break } }
  set parent $o(-parent)
  if {![winfo exists $parent]} { set parent . }
  variable messageN
  set w .sibyMessage[incr messageN]
  toplevel $w -background [c fond]
  wm withdraw $w
  wm title $w $o(-title)
  catch {wm transient $w [winfo toplevel $parent]}
  wm resizable $w 0 0
  set f [ttk::frame $w.f -padding {22 18 22 14}]
  pack $f -fill both -expand 1
  # a coloured sign for warnings and errors only (a plain message needs none)
  set signe [dict get {info {} question {} warning ⚠ error ⛔} $o(-icon)]
  if {$signe ne {}} {
    label $f.signe -text $signe -font font_H2 -background [c fond] \
        -foreground [expr {$o(-icon) eq "error" ? "#df5353" : "#e69f00"}]
    grid $f.signe -row 0 -column 0 -rowspan 2 -sticky n -padx {0 14}
  }
  ttk::label $f.m -text $o(-message) -wraplength 460 -justify left -font font_Regular -foreground [c texteFort]
  grid $f.m -row 0 -column 1 -sticky w
  if {$o(-detail) ne {}} {
    ttk::label $f.d -text $o(-detail) -wraplength 460 -justify left -foreground [c texteDoux]
    grid $f.d -row 1 -column 1 -sticky w -pady {8 0}
  }
  ttk::frame $f.b
  grid $f.b -row 2 -column 0 -columnspan 2 -sticky e -pady {18 0}
  foreach b $boutons {
    ttk::button $f.b.$b -text [dict get $noms $b] -command [list set ::moderne::messageReponse($w) $b]
    pack $f.b.$b -side left -padx {8 0}
  }
  catch {$f.b.$defaut configure -style Accent.TButton}
  bind $w <Return> [list $f.b.$defaut invoke]
  bind $w <KP_Enter> [list $f.b.$defaut invoke]
  bind $w <Escape> [list set ::moderne::messageReponse($w) $echap]
  wm protocol $w WM_DELETE_WINDOW [list set ::moderne::messageReponse($w) $echap]
  catch {::moderne::repeindre $w}
  # centred over its window (or the screen when it is not shown)
  update idletasks
  set pw [winfo toplevel $parent]
  if {[winfo ismapped $pw]} {
    set x [expr {[winfo rootx $pw] + ([winfo width $pw] - [winfo reqwidth $w]) / 2}]
    set y [expr {[winfo rooty $pw] + ([winfo height $pw] - [winfo reqheight $w]) / 3}]
  } else {
    set x [expr {([winfo screenwidth $w] - [winfo reqwidth $w]) / 2}]
    set y [expr {([winfo screenheight $w] - [winfo reqheight $w]) / 3}]
  }
  wm geometry $w +[expr {max(0, $x)}]+[expr {max(0, $y)}]
  wm deiconify $w
  raise $w
  # (never above the other programs: shown while the main window was
  # briefly "topmost" at the start, it stayed so on Windows, Yosha
  # 2026-11-09)
  catch {wm attributes $w -topmost 0}
  set ancienFocus [focus]
  set ancienGrab [grab current]
  # (the keyboard on the box, else Return and Escape went to the window
  # below)
  update idletasks
  catch {focus -force $f.b.$defaut}
  catch {grab $w}
  variable messageReponse
  set messageReponse($w) {}
  vwait ::moderne::messageReponse($w)
  set r $messageReponse($w)
  unset messageReponse($w)
  catch {grab release $w}
  destroy $w
  if {$ancienGrab ne {} && [winfo exists $ancienGrab]} { catch {grab $ancienGrab} }
  catch {if {$ancienFocus ne {} && [winfo exists $ancienFocus]} { focus $ancienFocus }}
  return $r
}
