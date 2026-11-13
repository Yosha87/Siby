###
### Siby: Help › Thanks. Supporting Siby first, then the projects Siby is
### built on, with their licenses and a link to support them.
### Required attributions (GPL programs, piece sets, photos) are here too.
###

namespace eval ::moderne::merci {
  variable w .merciWin
  # Triby's support page (Help › Support Triby, and a line here): one
  # address for all of Triby, the donation links live on that page
  # (Yosha 2026-11-08)
  variable soutien https://tribychess.org/support/index.html
}

proc ::moderne::merci::T {fr en} { return [::moderne::tr $fr $en] }

### {name url what (fr en) license donation-url}, in alphabetical order
proc ::moderne::merci::projets {} {
  return [lsort -dictionary -index 0 [list \
    [list Lichess https://lichess.org \
        "Les retransmissions en direct, l'API, les fiches des joueur·ses, les jeux de pièces et l'échiquier, les parties en ligne ; les parties de la partie Lichess de Gaby (CC BY-SA 4.0)." \
        "Live broadcasts, the API, player cards, piece sets and board, online games; the games of Gaby's Lichess part (CC BY-SA 4.0)." \
        "AGPL v3" https://lichess.org/patron] \
    [list "Lumbra's GigaBase" https://lumbrasgigabase.com \
        "La plupart des parties de la partie Autres de Gaby." \
        "Most games of Gaby's Others part." \
        "CC BY-NC 4.0" {}] \
    [list OlimpBase https://www.olimpbase.org \
        "Les listes de classement d'avant 2001 et des parties de la partie Autres de Gaby." \
        "The rating lists before 2001 and games of Gaby's Others part." \
        {} {}] \
    [list Stockfish https://stockfishchess.org \
        "Le moteur d'analyse et l'annotation des erreurs." \
        "The analysis engine and the mistakes of the annotation." \
        "GPL v3" {}] \
    [list "Leela Chess Zero" https://lczero.org \
        "Le moteur neuronal sur lequel Toby s'appuie." \
        "The neural engine Toby relies on." \
        "GPL v3" {}] \
    [list Maia https://www.maiachess.com \
        "Les probabilités humaines des coups (université de Toronto)." \
        "The human probabilities of the moves (University of Toronto)." \
        "AGPL v3" {}] \
    [list "SCID vs. PC" https://scidvspc.sourceforge.net \
        "Le programme dont Siby est issu (Steven Atkinson)." \
        "The program Siby comes from (Steven Atkinson)." \
        "GPL v2" {}] \
    [list "Scid" https://scid.sourceforge.net \
        "La base de tout : bases de données, recherches, arbre (Shane Hudson et ses successeurs)." \
        "Where it all began: databases, searches, tree (Shane Hudson and his successors)." \
        "GPL v2" {}] \
    [list Chess.com https://www.chess.com/news/view/published-data-api \
        "L'API publique des parties en ligne." \
        "The public API of online games." \
        {} {}] \
    [list "Wikimedia Commons" https://commons.wikimedia.org \
        "Les photos des joueur·ses, dans le paquet joueurs de Gaby (auteur·rice et licence de chaque photo en infobulle)." \
        "The players' photos, in Gaby's players pack (author and license of each photo in its tooltip)." \
        "CC BY-SA / CC BY" https://donate.wikimedia.org] \
    [list Wikidata https://www.wikidata.org \
        "Les fiches des joueur·ses : titres, fédérations, années, liens Wikipédia." \
        "The players' cards: titles, federations, years, Wikipedia links." \
        "CC0" https://donate.wikimedia.org] \
    [list FIDE https://ratings.fide.com \
        "La liste de classement : elle relie les joueur·ses de Gaby et donne leurs titres et fédérations." \
        "The rating list: it links Gaby's players and gives their titles and federations." \
        {} {}] \
    [list "Colin M.L. Burnett (cburnett)" https://commons.wikimedia.org/wiki/Category:SVG_chess_pieces \
        "Le jeu de pièces par défaut ; les autres jeux de Lichess ont leurs auteur·rices et licences dans bitmaps/pieces/LISEZMOI.md." \
        "The default piece set; Lichess's other sets list their authors and licenses in bitmaps/pieces/LISEZMOI.md." \
        "GPL v2+" {}] \
    [list flag-icons https://github.com/lipis/flag-icons \
        "Les drapeaux des pays (retransmissions)." \
        "The country flags (broadcasts)." \
        "MIT" {}] \
    [list libwebp https://chromium.googlesource.com/webm/libwebp \
        "Le décodeur des images WebP (couvertures des tournois)." \
        "The WebP image decoder (tournament covers)." \
        "BSD" {}] \
    [list Tcl/Tk https://www.tcl-lang.org \
        "Le langage et l'interface graphique." \
        "The language and the graphical interface." \
        "BSD" {}] \
  ]]
}

proc ::moderne::merci::ouvrir {} {
  variable w
  variable soutien
  if {[winfo exists $w]} { raise $w ; focus $w ; return }
  toplevel $w
  wm title $w [T "Remerciements" "Thanks"]
  set fond [::moderne::c fond]
  $w configure -background $fond
  set f [ttk::frame $w.f -padding 16]
  pack $f -fill both -expand 1
  set t [text $f.t -wrap word -borderwidth 0 -highlightthickness 0 -width 78 -height 34 \
      -background $fond -foreground [::moderne::c texte] -font font_Regular -cursor arrow \
      -padx 4 -pady 4 -spacing1 2 -spacing3 2]
  ttk::scrollbar $f.y -orient vertical -command [list $t yview]
  $t configure -yscrollcommand [list $f.y set]
  $t tag configure nom -font font_Bold -foreground [::moderne::c texteFort]
  $t tag configure doux -foreground [::moderne::c texteDoux]
  $t tag configure lien -foreground [::moderne::c lien]
  $t tag configure bloc -spacing3 10
  $t tag configure intro -spacing3 22
  $t tag configure auteur -spacing3 14
  # Who makes Siby, supporting Siby, then the projects it is built on
  $t insert end [T "Gaby, Siby et Toby forment Triby, un projet de " "Gaby, Siby and Toby make up Triby, a project by "] auteur
  $t insert end "Yosha Iglesias" [list auteur lien auteure]
  $t tag bind auteure <Button-1> [list openURL https://en.wikipedia.org/wiki/Yosha_Iglesias]
  $t tag bind auteure <Enter> [list $t configure -cursor hand2]
  $t tag bind auteure <Leave> [list $t configure -cursor arrow]
  $t insert end ".\n" auteur
  if {$soutien ne {}} {
    $t insert end [T "Soutenir Triby" "Support Triby"] [list nom lien soutien]
    $t tag bind soutien <Button-1> [list openURL $soutien]
    $t tag bind soutien <Enter> [list $t configure -cursor hand2]
    $t tag bind soutien <Leave> [list $t configure -cursor arrow]
    $t insert end "\n"
  }
  $t insert end [T "Siby est gratuit et le restera. Pense aussi à soutenir les projets ci-dessous : sans eux, Siby n'existerait pas." \
      "Siby is free and will stay free. Please also think of supporting the projects below: without them, Siby would not exist."] intro
  $t insert end "\n" intro
  set k 0
  foreach p [projets] {
    lassign $p nom url fr en licence don
    incr k
    $t insert end $nom [list nom l$k]
    $t tag bind l$k <Button-1> [list openURL $url]
    $t tag bind l$k <Enter> [list $t configure -cursor hand2]
    $t tag bind l$k <Leave> [list $t configure -cursor arrow]
    if {$licence ne {}} { $t insert end "   $licence" doux }
    if {$don ne {}} {
      $t insert end "   •   " doux
      $t insert end [T "Les soutenir" "Support them"] [list lien d$k]
      $t tag bind d$k <Button-1> [list openURL $don]
      $t tag bind d$k <Enter> [list $t configure -cursor hand2]
      $t tag bind d$k <Leave> [list $t configure -cursor arrow]
    }
    $t insert end "\n"
    $t insert end "[T $fr $en]\n" bloc
  }
  # Gaby's two licences (from v15)
  $t insert end "Gaby" nom
  $t insert end "   CC BY-SA 4.0 / CC BY-NC 4.0\n" doux
  $t insert end "[T "Deux parties : Lichess (CC BY-SA 4.0) et Autres (CC BY-NC 4.0, usage non commercial). La base réunie sur cet ordinateur est pour un usage personnel ; pour la partager, utiliser les deux parties avec leurs licences." \
      "Two parts: Lichess (CC BY-SA 4.0) and Others (CC BY-NC 4.0, non-commercial use). The database merged on this computer is for personal use; to share it, use the two parts with their licences."]\n" bloc
  $t configure -state disabled
  pack $f.y -side right -fill y
  pack $t -side left -fill both -expand 1
  ttk::button $w.ok -text OK -command [list destroy $w]
  pack $w.ok -side bottom -anchor e -padx 16 -pady {0 12}
  bind $w <Escape> [list destroy $w]
  catch {::moderne::repeindre $w}
  catch {placeWinCenter $w}
}
