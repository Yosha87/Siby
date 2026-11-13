
###
### Siby: restyling of classic Tk widgets
###
### Many windows inherited from SCID use "classic" checkbutton, radiobutton
### and menubutton: small gray boxes, star-shaped radio dots,
### "⌐" arrow. They are intercepted at creation to give them the look
### of the theme's ttk controls (Sun Valley images):
###   - checkbox / radio button: theme image to the left of the text;
###   - toggle button (-indicatoron 0): flat, accent background when active;
###   - menubutton with arrow: small chevron to the right of the text.
### Nothing changes if the widget already has its own image.
###

namespace eval ::moderne::classiques {
  variable images      ;# images(name): theme images, with a right margin
  array set images {}
  variable habille     ;# habille(w): kind of restyling (check, toggle)
  array set habille {}
}

### Sun Valley theme image (copy with a 6 px right margin, to
### separate the box from the text); {} if the theme is not loaded
proc ::moderne::classiques::imageTheme {nom} {
  variable images
  if {[info exists images($nom)]} { return $images($nom) }
  set ns [expr {$::moderne::theme eq "clair" ? "sv_light" : "sv_dark"}]
  set var ::ttk::theme::${ns}::I($nom)
  if {![info exists $var]} { return {} }
  set src [set $var]
  set l [image width $src]
  set h [image height $src]
  set img [image create photo -width [expr {$l + 6}] -height $h]
  $img copy $src -to 0 0
  set images($nom) $img
  return $img
}

### "▾" chevron for menubuttons
proc ::moderne::classiques::chevron {} {
  variable images
  if {[info exists images(chevron)]} { return $images(chevron) }
  set img [image create photo -width 16 -height 8]
  set coul [::moderne::c texteDoux]
  # solid triangle 7 px wide, centered, with a 6 px left margin
  for {set y 0} {$y < 4} {incr y} {
    set x0 [expr {6 + $y}]
    set x1 [expr {12 - $y}]
    $img put $coul -to $x0 [expr {$y + 2}] [expr {$x1 + 1}] [expr {$y + 3}]
  }
  set images(chevron) $img
  return $img
}

proc ::moderne::classiques::installer {} {
  if {![::moderne::actif]} { return }
  after idle {catch ::moderne::classiques::calendrier}
  # hard-coded colors of inherited windows: adapted on display
  foreach classe {Text Label Listbox Message Canvas} {
    bind $classe <Map> {+catch {::moderne::classiques::recolorer %W}}
  }
  after idle {catch ::moderne::classiques::installerGraphes}
  if {[info commands ::moderne::classiques::checkbutton_tk] ne {}} { return }
  # Text: colors of tags set later (tag configure)
  # are adapted to the theme when they are set
  rename ::text ::moderne::classiques::text_tk
  proc ::text {w args} {
    set r [::moderne::classiques::text_tk $w {*}$args]
    if {$::moderne::theme eq "sombre"} {
      rename $w ::moderne::classiques::tk$w
      interp alias {} $w {} ::moderne::classiques::texte $w
      bind $w <Destroy> {+catch {::moderne::classiques::finTexte %W}}
    }
    return $r
  }
  foreach c {checkbutton radiobutton menubutton} {
    rename ::$c ::moderne::classiques::${c}_tk
    proc ::$c {w args} [string map [list %C $c] {
      set r [::moderne::classiques::%C_tk $w {*}$args]
      if {[catch {::moderne::classiques::habiller %C $w $args} err]} {
        puts stderr "Siby : habillage de $w : $err"
      }
      return $r
    }]
  }
}

proc ::moderne::classiques::habiller {classe w options} {
  variable habille
  set opts {}
  foreach {k v} $options {
    # common Tk abbreviations
    switch -- $k {
      -indicator - -indicatoron { set k -indicatoron }
      -bg { set k -background }
    }
    dict set opts $k $v
  }
  if {[dict exists $opts -image] || [dict exists $opts -bitmap]} { return }
  set fond [$w cget -background]
  switch -- $classe {
    menubutton {
      if {[dict exists $opts -indicatoron] && [dict get $opts -indicatoron]} {
        $w configure -indicatoron 0 -image [chevron] -compound right \
            -relief flat -borderwidth 0 -padx 8
      }
    }
    checkbutton - radiobutton {
      if {[dict exists $opts -indicatoron] && ![dict get $opts -indicatoron]} {
        # toggle button
        $w configure -selectcolor [::moderne::c accent] -relief flat \
            -offrelief flat -overrelief flat -borderwidth 0 -highlightthickness 0
        if {![dict exists $opts -background]} {
          $w configure -background [::moderne::c surface2]
        }
        set habille($w) bascule
        return
      }
      set type [expr {$classe eq "checkbutton" ? "check" : "radio"}]
      set off [imageTheme $type-unsel-rest]
      set on [imageTheme $type-rest]
      if {$off eq {} || $on eq {}} { return }
      $w configure -image $off -selectimage $on -tristateimage $off \
          -compound left -indicatoron 0 -relief flat -offrelief flat \
          -overrelief flat -borderwidth 0 -highlightthickness 0 \
          -selectcolor $fond -activebackground $fond -padx 2 -pady 1
      # (empty text: the image alone, without a useless margin)
      set habille($w) coche
      bind $w <Destroy> {+unset -nocomplain ::moderne::classiques::habille(%W)}
    }
  }
}

### After a background change (repaint): keep the box on the same background
proc ::moderne::classiques::fond {w} {
  variable habille
  if {![info exists habille($w)] || $habille($w) ne "coche"} { return }
  set f [$w cget -background]
  catch {$w configure -selectcolor $f -activebackground $f}
}


### Calendar icon (dates) redrawn flat, in the theme colors
proc ::moderne::classiques::calendrier {} {
  set img ::utils::date::calendar
  if {$img ni [image names]} { return }
  set e [expr {max(1.0, [tk scaling] / 1.333)}]
  set n [expr {int(round(16 * $e))}]
  $img blank
  $img configure -width $n -height $n
  set trait [::moderne::c texteDoux]
  set acc [::moderne::c accent]
  # rectangles in 16 px units: {color x0 y0 x1 y1}
  set r [list $trait 2 3 14 4  $trait 2 14 14 15  $trait 2 3 3 15  $trait 13 3 14 15 \
      $acc 3 4 13 7  $trait 5 1 6 4  $trait 10 1 11 4]
  foreach y {9 11} { foreach x {5 8 11} { lappend r $trait $x $y [expr {$x + 1}] [expr {$y + 1}] } }
  foreach {c x0 y0 x1 y1} $r {
    set a [expr {int(round($x0 * $e))}] ; set b [expr {int(round($y0 * $e))}]
    set c1 [expr {max($a + 1, int(round($x1 * $e)))}] ; set d [expr {max($b + 1, int(round($y1 * $e)))}]
    $img put $c -to $a $b $c1 $d
  }
}

### SCID graphs (ECO, score, filter, player tracking…): drawn in
### black on white; in the dark theme, the canvas is recolored after each
### drawing (background, texts, axes, grids, very dark bars)
proc ::moderne::classiques::graphe {graph} {
  if {$::moderne::theme ne "sombre"} { return }
  if {![info exists ::utils::graph::_data($graph,canvas)]} { return }
  set cv $::utils::graph::_data($graph,canvas)
  if {![winfo exists $cv]} { return }
  set fond [::moderne::c surface]
  $cv configure -background $fond
  set table [list \
      white $fond #ffffff $fond \
      black [::moderne::c texteDoux] #000000 [::moderne::c texteDoux] \
      gray80 [::moderne::c bordure] grey80 [::moderne::c bordure] \
      gray90 [::moderne::c bordure] grey90 [::moderne::c bordure] \
      grey15 #5a6b80 gray15 #5a6b80 grey75 #9aa7b5 gray75 #9aa7b5]
  # (the "white" bars for wins remain light)
  foreach item [$cv find all] {
    set type [$cv type $item]
    foreach opt {-fill -outline} {
      if {[catch {$cv itemcget $item $opt} c] || $c eq {}} { continue }
      set cle [string tolower $c]
      if {$type eq "rectangle" && $opt eq "-fill" && $cle in {white #ffffff}} {
        # large rectangle: plot area; small one: bar (ECO wins)
        lassign [$cv coords $item] x0 y0 x1 y1
        if {abs($x1 - $x0) > 0.4 * [winfo width $cv]} {
          $cv itemconfigure $item -fill [::moderne::c champ]
        } else {
          $cv itemconfigure $item -fill #e8edf2
        }
        continue
      }
      if {$type eq "line" && $cle in {black #000000 gray80 grey80 gray90 grey90}} {
        $cv itemconfigure $item -fill [::moderne::c bordure]
        continue
      }
      if {[dict exists $table $cle]} { $cv itemconfigure $item $opt [dict get $table $cle] }
    }
  }
}

proc ::moderne::classiques::installerGraphes {} {
  if {[info commands ::utils::graph::redraw] eq {}} { return }
  if {[info commands ::utils::graph::redraw_tk] ne {}} { return }
  rename ::utils::graph::redraw ::utils::graph::redraw_tk
  proc ::utils::graph::redraw {graph} {
    set r [::utils::graph::redraw_tk $graph]
    catch {::moderne::classiques::graphe $graph}
    return $r
  }
}

# (the theme may have been applied before this file was read)
if {[info exists ::ttk::theme::sv_dark::I] || [info exists ::ttk::theme::sv_light::I]} {
  ::moderne::classiques::installer
}

### Command of a wrapped Text widget: adapts the colors of "tag
### configure" (except white text, intended on a colored background)
proc ::moderne::classiques::texte {w args} {
  if {[lindex $args 0] eq "tag" && [lindex $args 1] in {configure config conf}
      && [llength $args] > 4} {
    set a [lrange $args 0 2]
    foreach {opt val} [lrange $args 3 end] {
      if {$opt in {-foreground -background -fg -bg} && $val ne {}
          && !($opt in {-foreground -fg} && [string tolower $val] in {white #ffffff #fff})} {
        set val [::moderne::adapter $val]
      }
      lappend a $opt $val
    }
    set args $a
  }
  tailcall ::moderne::classiques::tk$w {*}$args
}

proc ::moderne::classiques::finTexte {w} {
  # (Tk deletes the renamed command after the <Destroy> event)
  after idle [list apply {{w} {
    if {![winfo exists $w]} { catch {interp alias {} $w {}} }
  }} $w]
}

### Recoloring of a widget on first display (dark theme)
proc ::moderne::classiques::recolorer {w} {
  variable vus
  if {$::moderne::theme ne "sombre" || [info exists vus($w)]} { return }
  set vus($w) 1
  bind $w <Destroy> {+unset -nocomplain ::moderne::classiques::vus(%W)}
  set cibles [list {} $w]
  if {[winfo class $w] eq "Text"} {
    foreach tag [$w tag names] { lappend cibles $tag $w }
  }
  foreach {tag x} $cibles {
    foreach opt {-background -foreground} {
      if {$tag eq {}} {
        if {[catch {$w cget $opt} val]} { continue }
      } elseif {[catch {$w tag cget $tag $opt} val]} { continue }
      if {$val eq {}} { continue }
      # (white text is intended: often on a colored background)
      if {$opt eq "-foreground" && [string tolower $val] in {white #ffffff #fff}} { continue }
      set nouv [::moderne::adapter $val]
      if {$nouv eq $val} { continue }
      if {$tag eq {}} {
        catch {$w configure $opt $nouv}
      } else {
        catch {$w tag configure $tag $opt $nouv}
      }
    }
  }
}

### End Siby
