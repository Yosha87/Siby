//////////////////////////////////////////////////////////////////////
//
//  FILE:       sbclassement.cpp
//              Siby: estimated historical rating (.sbc file)
//
//  Usage: sbclassement [options] base[.si4]
//    --ancre-depuis A   year from which the FIDE Elo recorded in the games
//                       is used as an anchor (default 1971)
//    --ancre-rapide-depuis A   the same for rapid and blitz (default 2012,
//                       the first FIDE rapid and blitz lists)
//    --joueur NAME      also prints the rating curve of the players whose
//                       name contains NAME (several --joueur allowed)
//    --sans-fichier     do not write base.sbc
//    --lien L, --rappel R, --ancre A: tuning (defaults 10, 0.002, 8)
//    --lien-classique K: weight (virtual draws) of the classical rating of
//                       the same year as a prior for rapid and blitz (3)
//    --min-parties N    players with fewer games than N in a time control
//                       (all years) are left out of it: no rating, and
//                       their games do not count for their opponents
//                       (10; 0: off)
//    --masquer          with --min-parties: kept in the calculation, not
//                       written
//    --score-max S      what a win counts (a loss 1 - S): no perfect score,
//                       so no infinite rating (10/10 had none); 0.99 is
//                       FIDE's bound, 100 % at most +800 above the
//                       opponents (0.99; 1: off)
//    --min-adversaires K  a career period needs K different opponents:
//                       against a single one, a rating only measures the
//                       gap between two players, and any choice of the
//                       games kept skews it (Eichborn, a banker who
//                       published his wins against Anderssen: 30 games, all
//                       against him) (2; 0: off)
//    --min-fenetre N    a year is written only with N games over the year
//                       +-2 (same period); otherwise the distance-weighted
//                       average of such years around it (5 years at most),
//                       or nothing: the links between years spread the
//                       same few games (one game a year for 14 years gave
//                       2850 +-77) (20, Yosha 2026-11-05; 0: off)
//    --marge-max M      a year whose margin (its games and its links to
//                       the neighboring years) exceeds M: the average of
//                       the well-estimated years around it (0: off)
//    --ecart-carriere Y with --min-parties: a name silent more than Y years
//                       starts a new career period, counted on its own
//                       (another player: namesakes a century apart) (15)
//    --fusion / --sans-fusion  names merged by spelling.ssp or kept (default:
//                       kept for Gaby, whose names are already merged)
//    --naissances F     birth years first, "name<TAB>year" per line, names
//                       as in the database (Gaby: Wikidata, then FIDE)
//    --orthographe F    SCID spelling file (spelling.ssp): the variants
//                       of a name are merged (default: the one installed
//                       with Siby, if found)
//
//  Method (in the manner of Rod Edwards' Edo ratings): one rating per
//  player and per year, computed in one go over the whole history, for
//  each time control on its own (classical, rapid, blitz).
//    - each game counts according to the Elo model (win probability
//      1 / (1 + 10^(-diff/400)), a draw is worth half a point);
//    - two neighboring years of activity of the same player are linked by
//      "virtual draws" (strength changes slowly);
//    - from --ancre-depuis on, the FIDE Elo recorded in the games is
//      taken into account through virtual draws against an opponent of
//      that Elo: the whole scale, past included, is thus the FIDE Elo one;
//    - only players with at least --min-parties games in the time control
//      (over all years, counted again once the others are left out), or
//      with a FIDE Elo recorded in their games, are rated: with fewer, the estimate means nothing (a single win
//      against a 2874 gave 4074, a single loss 1674; Yosha 2026-11-05),
//      and such games would sway their opponents' ratings;
//    - a very slight pull toward 2000 keeps isolated players finite
//      (any stronger, it would drag down the early eras, linked to
//      today's Elo by long chains of players).
//  Time control (nsbCadence in nsb.h): in a Gaby database its flags only
//  (2 rapid, 3 blitz, both: rapid or blitz unknown, left out; games whose
//  event name says otherwise are counted
//  and listed, "DESACCORDS", for Gaby's rules); otherwise the event name.
//  Games left out: no date or no result, special starting position
//  (handicap games), fewer than 2 plies, duplicates, and simultaneous /
//  online / correspondence / Chess960 events (judging by the event name,
//  and by the flags of a Gaby database: correspondence, online).
//
//  File base.sbc (text, one line per player and per year, sorted by name):
//    name <TAB> year <TAB> rating <TAB> games <TAB> margin <TAB> fide <TAB> birth
//         <TAB> rapid rating <TAB> games <TAB> margin <TAB> fide
//         <TAB> blitz rating <TAB> games <TAB> margin <TAB> fide
//  (margin: estimated standard deviation of the rating, in Elo points;
//  fide: average FIDE Elo recorded in the player's games that year, 0
//  otherwise; birth: year according to spelling.ssp, 0 if unknown;
//  0 0 0 0: no game in that time control that year; a last column: 1 for a
//  computer, by its name, see estOrdinateur). The first 7 columns
//  are those of the classical-only files.
//  Progress: "PROGRES 0 <percent>" lines.
//
//////////////////////////////////////////////////////////////////////

#include <stdint.h>
#include <ctype.h>
#include "common.h"
#include "index.h"
#include "namebase.h"
#include "nsb.h"
#include "sibyfopen.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <time.h>
#include <vector>
#include <string>
#include <algorithm>
#include <unordered_map>
#include <unordered_set>
#include <array>
#include "sibyfopen.h"

static void erreur (const char * texte, const char * detail = "") {
    printf ("ERREUR %s%s\n", texte, detail);
    fflush (stdout);
    exit (1);
}

static inline uint64_t melange (uint64_t z) {
    z += 0x9E3779B97F4A7C15ULL;
    z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9ULL;
    z = (z ^ (z >> 27)) * 0x94D049BB133111EBULL;
    return z ^ (z >> 31);
}

// A computer (engine) by its name: "Comp X" (the usual tag of the
// databases), "(comp)", or a well-known engine name, version numbers left
// aside ("Fritz 6", "DEEP FRITZ", "HYDRA"; "Fritz, Alexander" is a player).
// Rated like the others, and tagged in the .sbc (Yosha 2026-11-05).
static bool estOrdinateur (const char * nom) {
    std::string m;
    for (const char * c = nom ? nom : ""; *c; c++) { m += (char) tolower ((unsigned char) *c); }
    if (m.compare (0, 5, "comp ") == 0 || m.find ("(comp") != std::string::npos) { return true; }
    size_t k = m.find_first_of ("0123456789");
    if (k != std::string::npos) { m.resize (k); }
    while (!m.empty() && (m.back() == ' ' || m.back() == '.' || m.back() == '-')) { m.pop_back(); }
    static const char * moteurs[] = {
        "hydra", "deep blue", "deeper blue", "deep thought", "deep fritz", "fritz", "x3d fritz",
        "deep junior", "junior", "rybka", "deep rybka", "stockfish", "shredder", "deep shredder",
        "houdini", "komodo", "crafty", "craftynovus", "leela", "leela chess zero", "lc", "alphazero",
        "hiarcs", "deep hiarcs", "chessmaster", "chess tiger", "gambit tiger", "zappa", "naum",
        "toga", "sjeng", "deep sjeng", "glaurung", "critter", "gull", "hitech", "cray blitz",
        "belle", "kaissa", "mephisto", "chess genius", "rebel", "pro deo", "nimzo", NULL };
    for (int i = 0; moteurs[i]; i++) { if (m == moteurs[i]) { return true; } }
    return false;
}

static std::string minuscules (const char * s) {
    std::string r (s ? s : "");
    for (size_t i = 0; i < r.size(); i++) { r[i] = (char) tolower ((unsigned char) r[i]); }
    return r;
}

// Comparison key for names (like the @PLAYER section of spelling.ssp:
// without ". , - _ *" or spaces, in lowercase)
static std::string cleNom (const std::string & s) {
    std::string r;
    for (size_t i = 0; i < s.size(); i++) {
        unsigned char c = s[i];
        if (c == '.' || c == ',' || c == '-' || c == '_' || c == '*' || c == ' ' || c == '\t') { continue; }
        r += (char) tolower (c);
    }
    return r;
}

// Reads the @PLAYER section of spelling.ssp: variant -> official name
static void lireOrthographe (const char * fichier, std::unordered_map<std::string, std::string> & table,
                             std::unordered_map<std::string, int> & naissance) {
    FILE * f = fopen (fichier, "rb");
    if (!f) { return; }
    char ligne[4096];
    bool joueurs = false;
    std::string officiel;
    while (fgets (ligne, sizeof ligne, f)) {
        std::string l (ligne);
        while (!l.empty() && (l.back() == '\n' || l.back() == '\r')) { l.pop_back(); }
        if (l.empty() || l[0] == '#') { continue; }
        if (l[0] == '@') { joueurs = (l.compare (0, 7, "@PLAYER") == 0); continue; }
        if (!joueurs) { continue; }
        size_t i = l.find_first_not_of (" \t");
        if (i == std::string::npos) { continue; }
        if (l[i] == '%') { continue; }
        if (l[i] == '=') {
            if (officiel.empty()) { continue; }
            std::string v = l.substr (i + 1);
            size_t d = v.find_first_not_of (" \t");
            if (d == std::string::npos) { continue; }
            v = v.substr (d);
            if (v.find_first_of ("*?") != std::string::npos) { continue; }   // (patterns: ignored)
            table[cleNom (v)] = officiel;
            continue;
        }
        if (i > 0) { continue; }
        size_t h = l.find ('#');
        officiel = l.substr (0, h);
        while (!officiel.empty() && (officiel.back() == ' ' || officiel.back() == '\t')) { officiel.pop_back(); }
        if (!officiel.empty()) { table[cleNom (officiel)] = officiel; }
        // birth year: "… [2660*] 1837.06.22--1884.07.10" or "… [1764] 1953"
        size_t c = l.find (']', h == std::string::npos ? 0 : h);
        if (c != std::string::npos && !officiel.empty()) {
            size_t d = l.find_first_of ("0123456789", c);
            if (d != std::string::npos && d + 4 <= l.size()) {
                int a = atoi (l.substr (d, 4).c_str());
                bool quatre = isdigit ((unsigned char) l[d + 1]) && isdigit ((unsigned char) l[d + 2]) && isdigit ((unsigned char) l[d + 3]);
                if (quatre && a > 1500 && a < 2100) { naissance[cleNom (officiel)] = a; }
            }
        }
    }
    fclose (f);
}

struct Lien { uint32_t autre; float n; float score; };   // score of the entity
struct Valeur { int elo = 0, parties = 0, marge = 0, fide = 0; };   // one time control, one year

int
main (int argc, char ** argv)
{
    uint ancre = 1971, ancreRapide = 2012;
    bool ecrire = true;
    std::string orthographe;
    int forcerFusion = 0;   // --fusion / --sans-fusion (default: none for Gaby)
    std::string fichierNaissances;   // --naissances F: "name<TAB>year" lines
    float pLien = 10.0f, pRappel = 0.002f, pAncre = 8.0f, pLienClassique = 3.0f;
    float pMinParties = 10.0f;        // --min-parties: games per career period
    bool masquerSeulement = false;    // --masquer: kept in the calculation, not written
    int pEcartCarriere = 15;          // --ecart-carriere: years of silence that split a name
    double pMargeMax = 0;             // --marge-max: a year less sure is averaged (0: off)
    int pMinAdversaires = 2;          // --min-adversaires: distinct opponents per period
    float pMinFenetre = 20;           // --min-fenetre N: games over the year +-2 to publish it (0: off)
    bool sansTournoiInconnu = false;  // --sans-tournoi-inconnu: games without a known event left out
    float pScoreMax = 0.99f;          // --score-max: what a win counts (FIDE's bound; 1: off)
    std::vector<std::string> suivis;
    const char * nomBase = NULL;
    for (int a = 1; a < argc; a++) {
        if (!strcmp (argv[a], "--ancre-depuis") && a + 1 < argc) { ancre = atoi (argv[++a]); }
        else if (!strcmp (argv[a], "--ancre-rapide-depuis") && a + 1 < argc) { ancreRapide = atoi (argv[++a]); }
        else if (!strcmp (argv[a], "--joueur") && a + 1 < argc) { suivis.push_back (minuscules (argv[++a])); }
        else if (!strcmp (argv[a], "--sans-fichier")) { ecrire = false; }
        else if (!strcmp (argv[a], "--orthographe") && a + 1 < argc) { orthographe = argv[++a]; }
        else if (!strcmp (argv[a], "--fusion")) { forcerFusion = 1; }
        else if (!strcmp (argv[a], "--naissances") && a + 1 < argc) { fichierNaissances = argv[++a]; }
        else if (!strcmp (argv[a], "--sans-fusion")) { forcerFusion = -1; }
        else if (!strcmp (argv[a], "--lien") && a + 1 < argc) { pLien = atof (argv[++a]); }
        else if (!strcmp (argv[a], "--rappel") && a + 1 < argc) { pRappel = atof (argv[++a]); }
        else if (!strcmp (argv[a], "--ancre") && a + 1 < argc) { pAncre = atof (argv[++a]); }
        else if (!strcmp (argv[a], "--lien-classique") && a + 1 < argc) { pLienClassique = atof (argv[++a]); }
        else if (!strcmp (argv[a], "--min-parties") && a + 1 < argc) { pMinParties = atof (argv[++a]); }
        else if (!strcmp (argv[a], "--masquer")) { masquerSeulement = true; }
        else if (!strcmp (argv[a], "--ecart-carriere") && a + 1 < argc) { pEcartCarriere = atoi (argv[++a]); }
        else if (!strcmp (argv[a], "--marge-max") && a + 1 < argc) { pMargeMax = atof (argv[++a]); }
        else if (!strcmp (argv[a], "--min-adversaires") && a + 1 < argc) { pMinAdversaires = atoi (argv[++a]); }
        else if (!strcmp (argv[a], "--score-max") && a + 1 < argc) { pScoreMax = atof (argv[++a]); }
        else if (!strcmp (argv[a], "--sans-tournoi-inconnu")) { sansTournoiInconnu = true; }
        else if (!strcmp (argv[a], "--min-fenetre") && a + 1 < argc) { pMinFenetre = atof (argv[++a]); }
        else if (argv[a][0] == '-') { nomBase = NULL; break; }
        else { nomBase = argv[a]; }
    }
    if (!nomBase) {
        printf ("Usage: sbclassement [--ancre-depuis YEAR] [--ancre-rapide-depuis YEAR] [--joueur NAME]... [--orthographe spelling.ssp] [--fusion|--sans-fusion] [--naissances F] [--sans-fichier] base[.si4]\n");
        return 1;
    }
    std::string base = nomBase;
    if (base.size() > 4 && base.compare (base.size() - 4, 4, ".si4") == 0) { base.resize (base.size() - 4); }

    Index idx;
    idx.SetFileName (base.c_str());
    if (idx.OpenIndexFile (FMODE_ReadOnly) != OK) { erreur ("opening the index ", (base + ".si4").c_str()); }
    NameBase nb;
    nb.SetFileName (base.c_str());
    if (nb.ReadNameFile() != OK) { erreur ("reading the names ", (base + ".sn4").c_str()); }
    uint32_t numGames = idx.GetNumGames();
    time_t debut = time (NULL);

    // players: names merged according to the official spelling
    if (orthographe.empty()) {
        std::string dir (argv[0]);
        size_t sl = dir.find_last_of ("/\\");
        dir = (sl == std::string::npos) ? std::string (".") : dir.substr (0, sl);
        const char * candidats[] = { "/spelling.ssp", "/data/spelling.ssp", "/../share/scid/spelling.ssp", "/../spelling.ssp", NULL };
        for (int c = 0; candidats[c]; c++) {
            FILE * t = fopen ((dir + candidats[c]).c_str(), "rb");
            if (t) { fclose (t); orthographe = dir + candidats[c]; break; }
        }
    }
    std::unordered_map<std::string, std::string> table;
    std::unordered_map<std::string, int> naissance;
    if (!orthographe.empty()) { lireOrthographe (orthographe.c_str(), table, naissance); }
    // Gaby: its names kept as they are (its spellings already merged, its
    // namesakes told apart); spelling.ssp only gives the missing birth
    // years ("Morphy, Paul" in the ratings for Gaby's "Morphy, Paul C":
    // no rating in Alter Ego, Yosha 2026-11-11)
    bool fusion = true;
    {
        char desc [CUSTOM_FLAG_DESC_LENGTH + 1];
        idx.GetCustomFlagDesc (desc, NSB_FLAG_EN_LIGNE);
        if (nsbDrapeauEnLigne (desc)) { fusion = false; }
    }
    if (forcerFusion > 0) { fusion = true; } else if (forcerFusion < 0) { fusion = false; }
    // birth years given (Gaby: Wikidata, then FIDE), by the database's names
    std::unordered_map<std::string, int> naissancesDonnees;
    if (!fichierNaissances.empty()) {
        FILE * f = fopen (fichierNaissances.c_str(), "rb");
        if (!f) { erreur ("reading ", fichierNaissances.c_str()); }
        char ligne[1024];
        while (fgets (ligne, sizeof ligne, f)) {
            char * t = strchr (ligne, '\t');
            if (!t) { continue; }
            *t = 0;
            int a = atoi (t + 1);
            if (a > 1500 && a < 2100) { naissancesDonnees[cleNom (ligne)] = a; }
        }
        fclose (f);
    }
    uint32_t nJ = nb.GetNumNames (NAME_PLAYER);
    std::vector<uint32_t> canon (nJ);
    std::vector<std::string> nomCanon;
    std::vector<int> naiCanon;
    {
        std::unordered_map<std::string, uint32_t> parCle;
        for (uint32_t p = 0; p < nJ; p++) {
            const char * n = nb.GetName (NAME_PLAYER, p);
            std::string k = cleNom (n ? n : "");
            auto t = table.find (k);
            std::string officiel = (t != table.end()) ? t->second : std::string (n ? n : "");
            std::string nom = fusion ? officiel : std::string (n ? n : "");
            // birth: the years given, Gaby's "(*1958)", else spelling.ssp's
            int nai = 0;
            {
                auto d = naissancesDonnees.find (cleNom (n ? n : ""));
                if (d != naissancesDonnees.end()) { nai = d->second; }
            }
            if (!nai) {
                const char * e = n ? strstr (n, "(*") : NULL;
                if (e && isdigit ((unsigned char) e[2])) { int a = atoi (e + 2); if (a > 1500 && a < 2100) { nai = a; } }
            }
            if (!nai) {
                auto b = naissance.find (cleNom (officiel));
                if (b != naissance.end()) { nai = b->second; }
            }
            k = cleNom (nom);
            auto it = parCle.find (k);
            if (it == parCle.end()) {
                canon[p] = nomCanon.size();
                parCle.emplace (k, canon[p]);
                nomCanon.push_back (nom);
                naiCanon.push_back (nai);
            } else {
                canon[p] = it->second;
                if (!naiCanon[canon[p]]) { naiCanon[canon[p]] = nai; }
            }
        }
    }
    printf ("NOMS %u players, %u after spelling (%u known variants)%s\n", nJ,
            (unsigned) nomCanon.size(), (unsigned) table.size(), fusion ? "" : ", names kept (Gaby)");

    // time control of each event (nsb.h), and Gaby's flags
    uint32_t nEv = nb.GetNumNames (NAME_EVENT);
    std::vector<const char *> evNom (nEv);
    for (uint32_t e = 0; e < nEv; e++) { evNom[e] = nb.GetName (NAME_EVENT, e); }
    bool drapeauxGaby = false;
    {
        char desc [CUSTOM_FLAG_DESC_LENGTH + 1];
        idx.GetCustomFlagDesc (desc, NSB_FLAG_EN_LIGNE);
        drapeauxGaby = nsbDrapeauEnLigne (desc);
    }
    // cadence by the name, and by the rules (nsbCadence)
    std::vector<signed char> evCadence (nEv), evSpecial (nEv), evInconnu (nEv);
    for (uint32_t e = 0; e < nEv; e++) {
        evCadence[e] = (signed char) nsbCadenceEvenement (evNom[e]);
        evSpecial[e] = nsbEvenementSpecial (nsbMinuscules (evNom[e]));
        // (--sans-tournoi-inconnu: no event, or an informal one: a simul,
        // an offhand or a selected game cannot be told apart; Salov at 15
        // "beating" Bronstein, Petrosian and Matanovic, 95 games without
        // event, Yosha 2026-11-05)
        std::string m = nsbMinuscules (evNom[e]);
        while (!m.empty() && (m.back() == ' ' || m.back() == '.')) { m.pop_back(); }
        evInconnu[e] = m.empty() || m == "?" || m == "-" || m == "*" || m == "unknown" || m == "inconnu"
            || m.find ("casual") != std::string::npos || m.find ("offhand") != std::string::npos
            || m.find ("off-hand") != std::string::npos || m.find ("friendly") != std::string::npos
            || m.find ("training") != std::string::npos || m.find ("exhibition") != std::string::npos
            || m.find ("simultan") != std::string::npos || m.find ("partie libre") != std::string::npos;
    }
    auto cadencePartie = [&] (IndexEntry * ie) -> int {
        uint32_t e = ie->GetEvent();
        if (sansTournoiInconnu && (e >= nEv || evInconnu[e])) { return -1; }
        if (!drapeauxGaby) { return (e < nEv) ? evCadence[e] : NSB_CLASSIQUE; }
        if (ie->GetCustomFlag (4) || ie->GetCustomFlag (5) || (e < nEv && evSpecial[e])) { return -1; }
        if (ie->GetCustomFlag (2) && ie->GetCustomFlag (3)) { return -1; }   // (rapid or blitz: unknown)
        return ie->GetCustomFlag (3) ? NSB_BLITZ : (ie->GetCustomFlag (2) ? NSB_RAPIDE : NSB_CLASSIQUE);
    };
    // Gaby: games whose flags say a time control and whose event name says
    // another (reported to Gaby, whose rules decide)
    std::unordered_map<uint32_t, uint32_t> desaccords;   // event -> games
    uint64_t nDesaccords = 0;

    // overall progress: classical 0-80 %, rapid 80-90 %, blitz 90-100 %;
    // within each, reading the games 40 %, solving 60 %
    const double debutCad[3] = { 0, 80, 90 }, partCad[3] = { 80, 10, 10 };
    int dernierProgres = -1;
    auto progres = [&] (int cad, double frac) {
        int p = (int) (debutCad[cad] + partCad[cad] * std::min (1.0, frac));
        if (p > 99) { p = 99; }
        if (p != dernierProgres) { printf ("PROGRES 0 %d\n", p); fflush (stdout); dernierProgres = p; }
    };

    // results of the three time controls, merged by (player, year)
    std::unordered_map<uint64_t, uint32_t> ligneDe;   // (player << 16 | year) -> line
    std::vector<uint32_t> lJoueur;
    std::vector<uint16_t> lAnnee;
    std::vector< std::array<Valeur, 3> > lVal;
    uint64_t gardeesCad[3] = { 0, 0, 0 };
    uint64_t ecartees = 0, doublons = 0, nExclusJoueurs = 0;
    int iterCad[3] = { 0, 0, 0 };

    auto calculer = [&] (int cad, uint ancreDepuis) {
    // 1. Reading the index: entities (player, year) and pairs of games
    std::unordered_map<uint64_t, uint32_t> entite;   // (player << 16 | year) -> number
    std::vector<uint32_t> entJoueur;
    std::vector<uint16_t> entAnnee;
    std::vector<float> eloSomme, eloN, nParties;
    auto numero = [&] (uint32_t joueur, uint32_t annee) -> uint32_t {
        uint64_t cle = ((uint64_t) joueur << 16) | annee;
        auto it = entite.find (cle);
        if (it != entite.end()) { return it->second; }
        uint32_t n = entJoueur.size();
        entite.emplace (cle, n);
        entJoueur.push_back (joueur);
        entAnnee.push_back ((uint16_t) annee);
        eloSomme.push_back (0); eloN.push_back (0); nParties.push_back (0);
        return n;
    };
    std::unordered_map<uint64_t, std::pair<float, float> > paires;   // (i<<32|j), i<j -> (n, score of i)
    std::unordered_set<uint64_t> vues;
    const uint32_t BLOC = 65536;
    std::vector<IndexEntry> bloc (BLOC);
    for (uint32_t d = 0; d < numGames; d += BLOC) {
        uint32_t n = std::min (BLOC, numGames - d);
        if (idx.ReadEntries (&bloc[0], d, n) != OK) { erreur ("reading the index"); }
        for (uint32_t k = 0; k < n; k++) {
            IndexEntry * ie = &bloc[k];
            uint annee = ie->GetYear();
            resultT res = ie->GetResult();
            idNumberT w = ie->GetWhite(), b = ie->GetBlack();
            if (w < nJ) { w = canon[w]; }
            if (b < nJ) { b = canon[b]; }
            int c = cadencePartie (ie);
            if (cad == NSB_CLASSIQUE && drapeauxGaby && c >= 0 && ie->GetEvent() < nEv) {
                int n = evCadence[ie->GetEvent()];
                if (n > 0 && n != c) { desaccords[ie->GetEvent()]++; nDesaccords++; }
            }
            if (c != cad && c >= 0) { continue; }   // (another time control)
            if (c < 0 || ie->GetDeleteFlag() || annee == 0 || res == RESULT_None || ie->GetStartFlag()
                    || ie->GetNumHalfMoves() < 2 || w == b) {
                if (cad == NSB_CLASSIQUE) { ecartees++; }
                continue;
            }
            uint64_t empreinte = melange (((uint64_t) w << 32) ^ b ^ ((uint64_t) ie->GetDate() << 40)
                                          ^ ((uint64_t) res << 60) ^ ((uint64_t) ie->GetNumHalfMoves() << 20));
            if (!vues.insert (empreinte).second) { doublons++; continue; }
            uint32_t iw = numero (w, annee), ib = numero (b, annee);
            // (a win counts pScoreMax, a loss 1 - pScoreMax: no perfect
            // score, so no infinite rating; 0.99 = FIDE's bound, 100 % at
            // most +800 above the opponents)
            float sw = (res == RESULT_White) ? pScoreMax : (res == RESULT_Draw ? 0.5f : 1.0f - pScoreMax);
            uint32_t i = iw, j = ib; float s = sw;
            if (i > j) { std::swap (i, j); s = 1.0f - s; }
            auto & p = paires[((uint64_t) i << 32) | j];
            p.first += 1.0f; p.second += s;
            nParties[iw] += 1; nParties[ib] += 1;
            if (annee >= ancreDepuis) {
                if (ie->GetWhiteRatingType() == RATING_Elo && ie->GetWhiteElo() >= 1000) { eloSomme[iw] += ie->GetWhiteElo(); eloN[iw] += 1; }
                if (ie->GetBlackRatingType() == RATING_Elo && ie->GetBlackElo() >= 1000) { eloSomme[ib] += ie->GetBlackElo(); eloN[ib] += 1; }
            }
            gardeesCad[cad]++;
        }
        progres (cad, 0.4 * (d + n) / numGames);
    }
    vues.clear ();
    uint32_t N = entJoueur.size();
    if (N == 0) { return; }
    // 1b. Career periods: the years of a name split where it was silent more
    // than --ecart-carriere years (two namesakes a century apart are two
    // players: "Kalugin, Sergei" 1899 and 1997). A period with fewer than
    // --min-parties games is left out with its games (a FIDE Elo seen in
    // one or two games does not hold a rating either: 2934 at 12 years old;
    // when the Elo is in the game, Siby uses it and needs no estimate),
    // counted again until no one else falls below the minimum.
    std::vector<uint32_t> parNom (N);
    for (uint32_t i = 0; i < N; i++) { parNom[i] = i; }
    std::sort (parNom.begin(), parNom.end(), [&] (uint32_t a, uint32_t b) {
        if (entJoueur[a] != entJoueur[b]) { return entJoueur[a] < entJoueur[b]; }
        return entAnnee[a] < entAnnee[b];
    });
    std::vector<uint32_t> periode (N, 0);
    {
        uint32_t p = 0;
        for (uint32_t k = 0; k < N; k++) {
            uint32_t i = parNom[k];
            if (k > 0) {
                uint32_t a = parNom[k - 1];
                if (entJoueur[a] != entJoueur[i] || entAnnee[i] - entAnnee[a] > pEcartCarriere) { p++; }
            }
            periode[i] = p;
        }
    }
    std::vector<char> exclu (N, 0);   // by period
    uint64_t nPeriodesExclues = 0;
    for (int tour = 0; tour < 20 && (pMinParties > 1 || pMinAdversaires > 1); tour++) {
        std::vector<float> total (N, 0.0f);
        // (distinct opponents of each period: the opponent's name)
        std::vector< std::unordered_set<uint32_t> > adversaires (pMinAdversaires > 1 ? N : 0);
        for (auto & p : paires) {
            uint32_t i = p.first >> 32, j = p.first & 0xFFFFFFFFu;
            if (exclu[periode[i]] || exclu[periode[j]]) { continue; }
            total[periode[i]] += p.second.first;
            total[periode[j]] += p.second.first;
            if (pMinAdversaires > 1) {
                if (adversaires[periode[i]].size() < (size_t) pMinAdversaires) { adversaires[periode[i]].insert (entJoueur[j]); }
                if (adversaires[periode[j]].size() < (size_t) pMinAdversaires) { adversaires[periode[j]].insert (entJoueur[i]); }
            }
        }
        uint64_t avant = nPeriodesExclues;
        for (uint32_t i = 0; i < N; i++) {
            uint32_t q = periode[i];
            if (exclu[q]) { continue; }
            if (total[q] < pMinParties
                || (pMinAdversaires > 1 && adversaires[q].size() < (size_t) pMinAdversaires)) {
                exclu[q] = 1; nPeriodesExclues++;
            }
        }
        if (nPeriodesExclues == avant) { break; }
    }
    std::vector<char> garde (N, 1), publie (N, 1);
    for (uint32_t i = 0; i < N; i++) {
        if (!exclu[periode[i]]) { continue; }
        publie[i] = 0;
        if (!masquerSeulement) { garde[i] = 0; eloN[i] = 0; }
    }
    if (cad == NSB_CLASSIQUE) { nExclusJoueurs = 0; }
    nExclusJoueurs += nPeriodesExclues;
    // (the games counted: those kept)
    std::fill (nParties.begin(), nParties.end(), 0.0f);
    // 2. Graph: games, links between neighboring years of the same player
    std::vector< std::vector<Lien> > adj (N);
    for (auto & p : paires) {
        uint32_t i = p.first >> 32, j = p.first & 0xFFFFFFFFu;
        if (!garde[i] || !garde[j]) { gardeesCad[cad] -= (uint32_t) p.second.first; continue; }
        nParties[i] += p.second.first; nParties[j] += p.second.first;
        adj[i].push_back (Lien { j, p.second.first, p.second.second });
        adj[j].push_back (Lien { i, p.second.first, p.second.first - p.second.second });
    }
    paires.clear ();
    std::vector<uint32_t> ordre (N);
    for (uint32_t i = 0; i < N; i++) { ordre[i] = i; }
    std::sort (ordre.begin(), ordre.end(), [&] (uint32_t a, uint32_t b) {
        if (entJoueur[a] != entJoueur[b]) { return entJoueur[a] < entJoueur[b]; }
        return entAnnee[a] < entAnnee[b];
    });
    const float LIEN = pLien;          // virtual draws between consecutive years
    std::vector< std::vector<Lien> > temps (N);
    for (uint32_t k = 1; k < N; k++) {
        uint32_t a = ordre[k - 1], b = ordre[k];
        if (entJoueur[a] != entJoueur[b] || !garde[a] || !garde[b]) { continue; }
        // (not across a silence of a career period's length: another player)
        if ((pMinParties > 1 || pMinAdversaires > 1) && periode[a] != periode[b]) { continue; }
        float ecart = (float) (entAnnee[b] - entAnnee[a]);
        float w = LIEN / ecart;
        temps[a].push_back (Lien { b, w, w / 2 });
        temps[b].push_back (Lien { a, w, w / 2 });
    }

    // 3. Solving: Newton's method, each step solved by conjugate
    //    gradient (diagonal preconditioner). The system is that of a
    //    graph (games, links between years): a few steps are enough.
    const double C = log (10.0) / 400.0;
    const double ANCRE = pAncre, RAPPEL = pRappel, MOYENNE = 2000.0;
    // rapid and blitz: the player's classical rating of the same year is a
    // light prior (virtual draws, weight --lien-classique): without it, the
    // years before the FIDE rapid and blitz lists (and small pools) drift
    // toward the 2000 pull; real games outweigh it as soon as there are some
    std::vector<double> prior (N, 0.0);
    if (cad != NSB_CLASSIQUE) {
        for (uint32_t i = 0; i < N; i++) {
            auto it = ligneDe.find (((uint64_t) entJoueur[i] << 16) | entAnnee[i]);
            if (it != ligneDe.end() && lVal[it->second][NSB_CLASSIQUE].parties > 0) {
                prior[i] = lVal[it->second][NSB_CLASSIQUE].elo;
            }
        }
    }
    std::vector<double> r (N, 2000.0);
    for (uint32_t i = 0; i < N; i++) {
        if (eloN[i] > 0) { r[i] = eloSomme[i] / eloN[i]; } else if (prior[i] > 0) { r[i] = prior[i]; }
    }
    std::vector<double> infoTot (N, 0.0);
    std::vector<double> info (N, 0.0), grad (N), diag (N), d (N), res (N), z (N), q (N), pdir (N);
    // Hessian weight per link (same order as adj, then temps)
    std::vector< std::vector<double> > wAdj (N), wTps (N);
    for (uint32_t i = 0; i < N; i++) { wAdj[i].resize (adj[i].size()); wTps[i].resize (temps[i].size()); }
    auto produit = [&] (const std::vector<double> & x, std::vector<double> & y) {
        for (uint32_t i = 0; i < N; i++) {
            double v = diag[i] * x[i];
            for (size_t k = 0; k < adj[i].size(); k++) { v -= wAdj[i][k] * x[adj[i][k].autre]; }
            for (size_t k = 0; k < temps[i].size(); k++) { v -= wTps[i][k] * x[temps[i][k].autre]; }
            y[i] = v;
        }
    };
    int iter;
    for (iter = 0; iter < 60; iter++) {
        // gradient and Hessian at the current point
        for (uint32_t i = 0; i < N; i++) {
            double g = 0, h = 0, hj = 0;
            for (size_t k = 0; k < adj[i].size(); k++) {
                const Lien & l = adj[i][k];
                double e = 1.0 / (1.0 + exp (-C * (r[i] - r[l.autre])));
                double w = l.n * e * (1 - e) * C * C;
                g += C * (l.score - l.n * e);
                h += w; wAdj[i][k] = w;
            }
            hj = h;
            for (size_t k = 0; k < temps[i].size(); k++) {
                const Lien & l = temps[i][k];
                double e = 1.0 / (1.0 + exp (-C * (r[i] - r[l.autre])));
                double w = l.n * e * (1 - e) * C * C;
                g += C * (l.score - l.n * e);
                h += w; wTps[i][k] = w;
            }
            if (eloN[i] > 0) {
                double a = eloSomme[i] / eloN[i];
                double wa = ANCRE * std::min (1.0f, eloN[i] / 5.0f);
                double e = 1.0 / (1.0 + exp (-C * (r[i] - a)));
                g += C * (wa * 0.5 - wa * e);
                h += wa * e * (1 - e) * C * C;
            }
            if (prior[i] > 0) {
                double e = 1.0 / (1.0 + exp (-C * (r[i] - prior[i])));
                g += C * (pLienClassique * 0.5 - pLienClassique * e);
                h += pLienClassique * e * (1 - e) * C * C;
            }
            {
                double e = 1.0 / (1.0 + exp (-C * (r[i] - MOYENNE)));
                g += C * (RAPPEL * 0.5 - RAPPEL * e);
                h += RAPPEL * e * (1 - e) * C * C;
            }
            grad[i] = g; diag[i] = h; info[i] = hj / (C * C); infoTot[i] = h;
        }
        // conjugate gradient: H d = grad
        std::fill (d.begin(), d.end(), 0.0);
        res = grad;
        double norme0 = 0;
        for (uint32_t i = 0; i < N; i++) { z[i] = res[i] / diag[i]; pdir[i] = z[i]; norme0 += res[i] * res[i]; }
        double rz = 0;
        for (uint32_t i = 0; i < N; i++) { rz += res[i] * z[i]; }
        int k;
        for (k = 0; k < 5000; k++) {
            produit (pdir, q);
            double pq = 0;
            for (uint32_t i = 0; i < N; i++) { pq += pdir[i] * q[i]; }
            if (pq <= 0) { break; }
            double alpha = rz / pq, norme = 0;
            for (uint32_t i = 0; i < N; i++) { d[i] += alpha * pdir[i]; res[i] -= alpha * q[i]; norme += res[i] * res[i]; }
            if (norme <= 1e-12 * norme0) { break; }
            double rz2 = 0;
            for (uint32_t i = 0; i < N; i++) { z[i] = res[i] / diag[i]; rz2 += res[i] * z[i]; }
            double beta = rz2 / rz;
            rz = rz2;
            for (uint32_t i = 0; i < N; i++) { pdir[i] = z[i] + beta * pdir[i]; }
        }
        double maxDelta = 0;
        for (uint32_t i = 0; i < N; i++) {
            double delta = std::max (-400.0, std::min (400.0, d[i]));
            r[i] += delta;
            maxDelta = std::max (maxDelta, fabs (delta));
        }
        progres (cad, 0.4 + 0.6 * std::min (1.0, (iter + 1) / 40.0));
        if (maxDelta < 0.05) { break; }
    }


    // 4. Results of this time control. The margin counts the year's games
    // and its links to the neighboring years. A year too uncertain (margin
    // above --marge-max) takes the average of the well-estimated years
    // around it in the same career period, weighted by distance (at most 5
    // years each side), or is left out (Yosha 2026-11-05: Tomovic 1931, one
    // game and nothing until 1945, gave 2797)
    std::vector<double> marge (N, 999.0), valeur (N, 0.0);
    std::vector<char> sure (N, 0), ecrire (N, 0);
    // (games of the player around each year, year +-2, same period: the
    // links between years spread the same few games, they add no
    // information; Hans Platz, one game a year for 14 years, had +-77)
    std::vector<float> fenetre (N, 0.0f);
    if (pMinFenetre > 0) {
        for (uint32_t k = 0; k < N; k++) {
            uint32_t i = parNom[k];
            float t = nParties[i];
            for (int q = (int) k - 1; q >= 0 && periode[parNom[q]] == periode[i] && entAnnee[i] - entAnnee[parNom[q]] <= 2; q--) { t += nParties[parNom[q]]; }
            for (uint32_t q = k + 1; q < N && periode[parNom[q]] == periode[i] && entAnnee[parNom[q]] - entAnnee[i] <= 2; q++) { t += nParties[parNom[q]]; }
            fenetre[i] = t;
        }
    }
    for (uint32_t i = 0; i < N; i++) {
        marge[i] = infoTot[i] > 0 ? std::min (999.0, 1.0 / sqrt (infoTot[i])) : 999.0;
        sure[i] = garde[i] && publie[i] && nParties[i] > 0 && (pMargeMax <= 0 || marge[i] <= pMargeMax)
                  && (pMinFenetre <= 0 || fenetre[i] >= pMinFenetre);
        if (sure[i]) { valeur[i] = r[i]; ecrire[i] = 1; }
    }
    if (pMargeMax > 0 || pMinFenetre > 0) {
        for (uint32_t k = 0; k < N; k++) {
            uint32_t i = parNom[k];
            if (sure[i] || !garde[i] || !publie[i] || nParties[i] <= 0) { continue; }
            int av = -1, ap = -1;
            for (int q = (int) k - 1; q >= 0; q--) {
                uint32_t j = parNom[q];
                if (periode[j] != periode[i] || entAnnee[i] - entAnnee[j] > 5) { break; }
                if (sure[j]) { av = (int) j; break; }
            }
            for (uint32_t q = k + 1; q < N; q++) {
                uint32_t j = parNom[q];
                if (periode[j] != periode[i] || entAnnee[j] - entAnnee[i] > 5) { break; }
                if (sure[j]) { ap = (int) j; break; }
            }
            if (av >= 0 && ap >= 0) {
                double t = (double) (entAnnee[i] - entAnnee[av]) / (double) (entAnnee[ap] - entAnnee[av]);
                valeur[i] = r[av] + t * (r[ap] - r[av]);
            } else if (av >= 0) {
                valeur[i] = r[av];
            } else if (ap >= 0) {
                valeur[i] = r[ap];
            } else {
                continue;
            }
            ecrire[i] = 1;
        }
    }
    for (uint32_t i = 0; i < N; i++) {
        if (!ecrire[i]) { continue; }
        Valeur v;
        v.elo = (int) lround (valeur[i]);
        v.parties = (int) nParties[i];
        v.marge = (int) marge[i];
        v.fide = eloN[i] > 0 ? (int) lround (eloSomme[i] / eloN[i]) : 0;
        uint64_t cle = ((uint64_t) entJoueur[i] << 16) | entAnnee[i];
        auto it = ligneDe.find (cle);
        uint32_t l;
        if (it == ligneDe.end()) {
            l = lJoueur.size();
            ligneDe.emplace (cle, l);
            lJoueur.push_back (entJoueur[i]);
            lAnnee.push_back (entAnnee[i]);
            lVal.push_back (std::array<Valeur, 3> ());
        } else {
            l = it->second;
        }
        lVal[l][cad] = v;
    }
    iterCad[cad] = iter;
    };

    calculer (NSB_CLASSIQUE, ancre);
    calculer (NSB_RAPIDE, ancreRapide);
    calculer (NSB_BLITZ, ancreRapide);
    uint32_t NL = lJoueur.size();
    std::vector<uint32_t> ordre (NL);
    for (uint32_t k = 0; k < NL; k++) { ordre[k] = k; }

    // 4. Writing, and followed players
    if (ecrire) {
        std::string fichier = base + ".sbc", tmp = fichier + ".tmp";
        FILE * f = fopen (tmp.c_str(), "wb");
        if (!f) { erreur ("writing ", tmp.c_str()); }
        // (sorted by name, byte by byte: Siby looks a player up in it by
        // binary search without reading the whole file)
        std::vector<uint32_t> parNom (ordre);
        std::sort (parNom.begin(), parNom.end(), [&] (uint32_t a, uint32_t b) {
            int c = strcmp (nomCanon[lJoueur[a]].c_str(), nomCanon[lJoueur[b]].c_str());
            if (c != 0) { return c < 0; }
            return lAnnee[a] < lAnnee[b];
        });
        for (uint32_t k = 0; k < NL; k++) {
            uint32_t i = parNom[k];
            const std::string & nom = nomCanon[lJoueur[i]];
            int nai = naiCanon[lJoueur[i]];
            const std::array<Valeur, 3> & v = lVal[i];
            fprintf (f, "%s\t%u\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\n", nom.c_str(), lAnnee[i],
                     v[0].elo, v[0].parties, v[0].marge, v[0].fide,
                     nai,
                     v[1].elo, v[1].parties, v[1].marge, v[1].fide,
                     v[2].elo, v[2].parties, v[2].marge, v[2].fide, estOrdinateur (nom.c_str()) ? 1 : 0);
        }
        if (fclose (f) != 0) { erreur ("writing ", tmp.c_str()); }
        siby_remove (fichier.c_str());
        if (siby_rename (tmp.c_str(), fichier.c_str()) != 0) { erreur ("replacing ", fichier.c_str()); }
    }
    std::sort (ordre.begin(), ordre.end(), [&] (uint32_t a, uint32_t b) {
        if (lJoueur[a] != lJoueur[b]) { return lJoueur[a] < lJoueur[b]; }
        return lAnnee[a] < lAnnee[b];
    });
    static const char * nomCad[3] = { "classical", "rapid", "blitz" };
    for (const std::string & s : suivis) {
        uint32_t dernier = 0xFFFFFFFFu;
        for (uint32_t k = 0; k < NL; k++) {
            uint32_t i = ordre[k];
            std::string nom = minuscules (nomCanon[lJoueur[i]].c_str());
            if (nom.find (s) == std::string::npos) { continue; }
            if (lJoueur[i] != dernier) {
                printf ("JOUEUR %s\n", nomCanon[lJoueur[i]].c_str());
                dernier = lJoueur[i];
            }
            for (int c = 0; c < 3; c++) {
                const Valeur & v = lVal[i][c];
                if (!v.parties) { continue; }
                printf ("  %u\t%s\t%d\t%d games\t± %d%s\n", lAnnee[i], nomCad[c], v.elo, v.parties,
                        v.marge, v.fide ? "\t(Elo FIDE)" : "");
            }
        }
    }
    if (nDesaccords) {
        // the 20 events with the most games
        std::vector<std::pair<uint32_t, uint32_t> > l (desaccords.begin(), desaccords.end());
        std::sort (l.begin(), l.end(), [] (const std::pair<uint32_t, uint32_t> & a, const std::pair<uint32_t, uint32_t> & b) {
            return a.second > b.second; });
        printf ("DESACCORDS %llu games whose Gaby flags and event name give different time controls (flags kept)\n",
                (unsigned long long) nDesaccords);
        static const char * nomC[3] = { "classical", "rapid", "blitz" };
        for (size_t i = 0; i < l.size() && i < 20; i++) {
            printf ("  %u\t%s (name: %s)\n", l[i].second, evNom[l[i].first], nomC[evCadence[l[i].first]]);
        }
    }
    printf ("PROGRES 3 1 1\n");
    printf ("OK %u lines, games: %llu classical, %llu rapid, %llu blitz (%llu excluded, %llu duplicates), %llu career periods under the minimum"
            ", iterations %d/%d/%d, %ld s\n", NL,
            (unsigned long long) gardeesCad[0], (unsigned long long) gardeesCad[1], (unsigned long long) gardeesCad[2],
            (unsigned long long) ecartees, (unsigned long long) doublons, (unsigned long long) nExclusJoueurs,
            iterCad[0], iterCad[1], iterCad[2], (long) (time (NULL) - debut));
    return 0;
}
