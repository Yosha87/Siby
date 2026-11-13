
###
### Siby: smooth, transparent arrows (Lichess style)
###
### The Tk canvas can only draw solid lines, without anti-aliasing or
### transparency. Here each arrow is drawn into a small PNG image
### (edges smoothed by supersampling, semi-transparent color) placed
### on the board: pieces remain visible underneath. Images are
### cached (a given arrow is computed only once).
###
### Used for engine, variation and annotation arrows
### ([%cal]) when the Siby theme is active (tcl/board.tcl).
###

namespace eval ::moderne::fleche {
  variable cache            ;# cache(key) = image
  array set cache {}
  variable max 300          ;# number of images kept
}

### Center of square sq (0 = a1) on canvas c
proc ::moderne::fleche::centre {c sq} {
  lassign [$c coords sq$sq] x0 y0 x1 y1
  return [list [expr {($x0 + $x1) / 2.0}] [expr {($y0 + $y1) / 2.0}] [expr {abs($x1 - $x0)}]]
}

### Draws an arrow from square de to square a on canvas c.
### rang: 0 = main arrow (the thickest), then thinner and thinner
### opacite: 0–1; tags: tags of the created item. Returns the item.
proc ::moderne::fleche::dessiner {c de a couleur {rang 0} {opacite 0.8} {tags {}}} {
  variable cache
  lassign [centre $c $de] x0 y0 s
  lassign [centre $c $a] x1 y1
  if {$s <= 0} { return {} }
  set f [lindex {1.0 0.72 0.55 0.45 0.38} [expr {min(4, max(0, $rang))}]]
  set w [expr {max(2.0, $s * 0.16 * $f)}]
  set cle [list [expr {round($x1 - $x0)}] [expr {round($y1 - $y0)}] [format %.1f $w] $couleur [format %.2f $opacite]]
  if {![info exists cache($cle)] || [lsearch -exact [image names] [lindex $cache($cle) 0]] < 0} {
    set cache($cle) [fabriquer [expr {$x1 - $x0}] [expr {$y1 - $y0}] $w $s $couleur $opacite]
    menage $c
  }
  lassign $cache($cle) img ox oy
  if {$img eq {}} { return {} }
  return [$c create image [expr {$x0 + $ox}] [expr {$y0 + $oy}] -image $img -anchor nw -tags $tags]
}

### Clears the cache if it is too big (keeping the displayed images)
proc ::moderne::fleche::menage {c} {
  variable cache
  variable max
  if {[array size cache] <= $max} { return }
  set utilisees {}
  foreach cv [list $c .main.board.bd] {
    if {![winfo exists $cv]} { continue }
    foreach id [$cv find all] {
      if {[$cv type $id] eq "image"} { lappend utilisees [$cv itemcget $id -image] }
    }
  }
  foreach cle [array names cache] {
    set img [lindex $cache($cle) 0]
    if {[lsearch -exact $utilisees $img] < 0} {
      catch {image delete $img}
      unset cache($cle)
    }
  }
}

### Arrow polygons (shaft and head), starting at (0, 0)
proc ::moderne::fleche::forme {dx dy w s} {
  set long [expr {hypot($dx, $dy)}]
  if {$long < 1} { return {} }
  set ux [expr {$dx / $long}] ; set uy [expr {$dy / $long}]
  set vx [expr {-$uy}]        ; set vy $ux
  # The head stops a little before the center of the destination square
  set long [expr {$long - $s * 0.08}]
  set px [expr {$ux * $long}] ; set py [expr {$uy * $long}]
  set hl [expr {min($w * 2.6, $long * 0.6)}]   ;# head length
  set hw [expr {$w * 1.75}]                     ;# head half-width
  set bx [expr {$px - $ux * $hl}] ; set by [expr {$py - $uy * $hl}]
  # The shaft starts a little after the center of the start square
  set d0 [expr {$s * 0.12}]
  set sx [expr {$ux * $d0}] ; set sy [expr {$uy * $d0}]
  set e [expr {$w / 2.0}]
  # (the shaft enters the head by one pixel to avoid a seam)
  set cx [expr {$bx + $ux}] ; set cy [expr {$by + $uy}]
  set corps [list \
      [expr {$sx + $vx * $e}] [expr {$sy + $vy * $e}] \
      [expr {$cx + $vx * $e}] [expr {$cy + $vy * $e}] \
      [expr {$cx - $vx * $e}] [expr {$cy - $vy * $e}] \
      [expr {$sx - $vx * $e}] [expr {$sy - $vy * $e}]]
  set pointe [list \
      [expr {$bx + $vx * $hw}] [expr {$by + $vy * $hw}] \
      $px $py \
      [expr {$bx - $vx * $hw}] [expr {$by - $vy * $hw}]]
  return [list $corps $pointe]
}

### Edges of a polygon: {xa ya xb yb ymin ymax}…
proc ::moderne::fleche::aretes {poly} {
  set res {}
  set n [expr {[llength $poly] / 2}]
  for {set i 0} {$i < $n} {incr i} {
    set j [expr {($i + 1) % $n}]
    lassign [lrange $poly [expr {2 * $i}] [expr {2 * $i + 1}]] xa ya
    lassign [lrange $poly [expr {2 * $j}] [expr {2 * $j + 1}]] xb yb
    if {$ya == $yb} { continue }
    lappend res [list $xa $ya [expr {($xb - $xa) / double($yb - $ya)}] [expr {min($ya, $yb)}] [expr {max($ya, $yb)}]]
  }
  return $res
}

### Interval [xg xd] of a convex polygon (given by its edges) on
### line y ({} if none)
proc ::moderne::fleche::coupe {aretes y} {
  set xs {}
  foreach a $aretes {
    lassign $a xa ya pente y0 y1
    if {$y >= $y0 && $y < $y1} { lappend xs [expr {$xa + ($y - $ya) * $pente}] }
  }
  if {[llength $xs] < 2} { return {} }
  return [list [tcl::mathfunc::min {*}$xs] [tcl::mathfunc::max {*}$xs]]
}

### Builds the image: returns {image ox oy} (offset from the start)
proc ::moderne::fleche::fabriquer {dx dy w s couleur opacite} {
  set polys [forme $dx $dy $w $s]
  if {$polys eq {}} { return {{} 0 0} }
  set xmin 1e9 ; set ymin 1e9 ; set xmax -1e9 ; set ymax -1e9
  foreach p $polys {
    foreach {x y} $p {
      set xmin [expr {min($xmin, $x)}] ; set xmax [expr {max($xmax, $x)}]
      set ymin [expr {min($ymin, $y)}] ; set ymax [expr {max($ymax, $y)}]
    }
  }
  set ox [expr {int(floor($xmin)) - 1}]
  set oy [expr {int(floor($ymin)) - 1}]
  set larg [expr {int(ceil($xmax)) - $ox + 2}]
  set haut [expr {int(ceil($ymax)) - $oy + 2}]
  # Polygons in the image's coordinate system
  set locaux {}
  foreach p $polys {
    set q {}
    foreach {x y} $p { lappend q [expr {$x - $ox}] [expr {$y - $oy}] }
    set ys {}
    foreach {x y} $q { lappend ys $y }
    lappend locaux [list [aretes $q] [tcl::mathfunc::min {*}$ys] [tcl::mathfunc::max {*}$ys]]
  }
  lassign [winfo rgb . $couleur] r g b
  set rgb [binary format ccc [expr {$r >> 8}] [expr {$g >> 8}] [expr {$b >> 8}]]
  set amax [expr {255.0 * $opacite}]
  set vide [binary format cccc 0 0 0 0]
  set plein "$rgb[binary format c [expr {round($amax)}]]"
  set sous 4
  set brut {}
  for {set y 0} {$y < $haut} {incr y} {
    # Intervals covered on each sub-line (shaft and head merged)
    set lignes {}
    set bornes {}
    for {set k 0} {$k < $sous} {incr k} {
      set yy [expr {$y + ($k + 0.5) / $sous}]
      set iv {}
      foreach q $locaux {
        lassign $q ar qy0 qy1
        if {$yy < $qy0 || $yy >= $qy1} { continue }
        set c [coupe $ar $yy]
        if {$c ne {}} { lappend iv $c }
      }
      # Merge of two touching intervals
      if {[llength $iv] == 2} {
        lassign $iv a b
        if {[lindex $a 0] > [lindex $b 0]} { lassign [list $b $a] a b }
        if {[lindex $b 0] <= [lindex $a 1]} {
          set iv [list [list [lindex $a 0] [expr {max([lindex $a 1], [lindex $b 1])}]]]
        } else {
          set iv [list $a $b]
        }
      }
      lappend lignes $iv
      foreach i $iv { lappend bornes {*}$i }
    }
    append brut \0
    if {![llength $bornes]} {
      append brut [string repeat $vide $larg]
      continue
    }
    # Pixels containing a bound: computed one by one; between two bounds,
    # coverage is constant
    set pix {}
    foreach b $bornes { lappend pix [expr {int(floor($b))}] }
    set pix [lsort -integer -unique $pix]
    set x 0
    foreach p [concat $pix [list $larg]] {
      if {$p > $x} {
        # pixels x .. p-1: constant coverage (test the middle)
        set m [expr {$x + 0.5}]
        set n 0
        foreach iv $lignes {
          foreach i $iv { if {$m >= [lindex $i 0] && $m <= [lindex $i 1]} { incr n ; break } }
        }
        if {$n == 0} {
          append brut [string repeat $vide [expr {$p - $x}]]
        } elseif {$n == $sous} {
          append brut [string repeat $plein [expr {$p - $x}]]
        } else {
          append brut [string repeat "$rgb[binary format c [expr {round($amax * $n / $sous)}]]" [expr {$p - $x}]]
        }
        set x $p
      }
      if {$p >= $larg} { break }
      if {$p < $x} { continue }
      # pixel p: covered share of [p, p+1] on each sub-line
      set cov 0.0
      foreach iv $lignes {
        foreach i $iv {
          set d [expr {min($p + 1.0, [lindex $i 1]) - max(double($p), [lindex $i 0])}]
          if {$d > 0} { set cov [expr {$cov + $d}] }
        }
      }
      set al [expr {round($amax * min(1.0, $cov / $sous))}]
      append brut "$rgb[binary format c $al]"
      set x [expr {$p + 1}]
    }
  }
  set png [png $larg $haut $brut]
  if {[catch {image create photo -format png -data [binary encode base64 $png]} img]} {
    return {{} 0 0}
  }
  return [list $img $ox $oy]
}

### PNG file (8-bit RGBA) from the raw rows (filter 0 at the start)
proc ::moderne::fleche::png {larg haut brut} {
  set ihdr [binary format IIccccc $larg $haut 8 6 0 0 0]
  set res "\x89PNG\r\n\x1a\n"
  foreach {type data} [list IHDR $ihdr IDAT [zlib compress $brut] IEND {}] {
    append res [binary format I [string length $data]] $type $data \
        [binary format I [zlib crc32 "$type$data"]]
  }
  return $res
}

### End Siby
