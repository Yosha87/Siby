

# thousands, percentFormat:
#   Functions to format integer numbers.
#   thousands inserts the thousands separator (usually "," or ".") for
#   every three digits before the decimal separator in the number.
#   percentFormat does the same as thousands, but also adds a percentage.
#   If "kilo" is true, numbers >= 100,000 are divided by 1000 and have
#   the unit "K" appended while values over 1 million appear as "1.00M"
#
# trTypesFichiers:
#   Translates the labels of a -filetypes list (tk_getOpenFile / tk_getSaveFile)
#   without touching the extensions.
proc ::utils::trTypesFichiers {types} {
  if {![info exists ::language] || $::language ne "F"} { return $types }
  set noms {
    "All Siby files" "Tous les fichiers Siby"
    "Siby databases (.si4) and PGN" "Bases Siby (.si4) et PGN"
    "Siby databases (.si4)" "Bases Siby (.si4)"
    "PGN files (.pgn)" "Fichiers PGN (.pgn)"
    "EPD positions (.epd)" "Positions EPD (.epd)"
    "Databases and PGN files" "Bases et fichiers PGN"
    "Databases" "Bases"
    "Siby databases" "Bases Siby"
    "Siby databases, PGN files" "Bases Siby, fichiers PGN"
    "Siby databases, EPD files" "Bases Siby, fichiers EPD"
    "PGN files" "Fichiers PGN"
    "Portable Game Notation files" "Fichiers PGN"
    "EPD files" "Fichiers EPD"
    "Text files" "Fichiers texte"
    "HTML files" "Fichiers HTML"
    "LaTeX files" "Fichiers LaTeX"
    "CQL files" "Fichiers CQL"
    "CQL file" "Fichier CQL"
    "PostScript files" "Fichiers PostScript"
    "Image Files" "Fichiers image"
    "Tablebase files" "Fichiers de tables de finales"
    "Tree Mask Files" "Fichiers de masque d'arbre"
    "Siby SearchOptions files" "Fichiers d'options de recherche Siby"
    "Siby SearchOption files" "Fichiers d'options de recherche Siby"
    "Siby Filter files" "Fichiers de filtre Siby"
    "Siby ECO files" "Fichiers ECO Siby"
    "Siby Spellcheck files" "Fichiers d'orthographe Siby"
    "Executables" "Exécutables"
    "All files" "Tous les fichiers"
    "All Files" "Tous les fichiers"
  }
  set res {}
  foreach t $types {
    set nom [lindex $t 0]
    set i [lsearch -exact $noms $nom]
    if {$i >= 0 && $i % 2 == 0} { lset t 0 [lindex $noms [expr {$i + 1}]] }
    lappend res $t
  }
  return $res
}

# comboTraduit:
#   Read-only combobox whose variable keeps an internal value
#   (in English, compared elsewhere in the code) while the display
#   shows the matching translated label.
#   var: fully qualified variable name (e.g. ::sGameEnd, ::comp(type))
proc ::utils::comboTraduit {cb var internes libelles} {
  $cb configure -values $libelles -textvariable ::utils::comboAff($cb)
  bind $cb <<ComboboxSelected>> [list ::utils::comboChoisi $cb $var $internes]
  set cmd [list ::utils::comboSync $cb $var $internes $libelles]
  trace remove variable $var write $cmd
  trace add variable $var write $cmd
  ::utils::comboSync $cb $var $internes $libelles
}

proc ::utils::comboSync {cb var internes libelles args} {
  if {![winfo exists $cb]} {
    trace remove variable $var write [list ::utils::comboSync $cb $var $internes $libelles]
    return
  }
  set val [set $var]
  set i [lsearch -exact $internes $val]
  set ::utils::comboAff($cb) [expr {$i >= 0 ? [lindex $libelles $i] : $val}]
}

proc ::utils::comboChoisi {cb var internes} {
  set i [$cb current]
  if {$i >= 0} { set $var [lindex $internes $i] }
}

proc ::utils::thousands {n {kilo 0}} {
  global locale
  set commaChar [string index $locale(numeric) 1]
  set unit ""
  if {$kilo} {
    if {$n >= 1000000} {
      set decimalChar [string index $locale(numeric) 0]
      set decimalPart [format "%02d" [expr {(int($n / 10000)) % 100}]]
      set n [expr {int($n) / 1000000}]
      set unit "${decimalChar}${decimalPart}M"
    } elseif {$n >= 100000} {
      set unit "K"
      set n [expr {int($n / 1000)} ]
    }
  }
  if {$commaChar == ""} { return "$n$unit" }
  while {[regsub {^([-+]?[0-9]+)([0-9][0-9][0-9])} $n "\\1$commaChar\\2" n]} {}
  return "$n$unit"
}

proc ::utils::percentFormat {num denom} {
  # Ensure denominator is not zero:
  if {$denom == 0} {set denom 1}
  return "[::utils::thousands $num] ([expr $num * 100 / $denom]%)"
}

# trace add execution PROC enterstep ::utils::traceok

proc ::utils::traceok {string op} {
  puts "$string , $op"
}

