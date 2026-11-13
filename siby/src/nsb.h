//////////////////////////////////////////////////////////////////////
//
//  FILE:       nsb.h
//              Siby: precomputed opening library (.sbl)
//
//  A "base.sbl" file next to "base.si4" holds, for each position of the
//  opening moves reached in at least "seuil" (threshold) games, the
//  statistics of each move (like SCID's tree search) and the numbers of
//  the best games (nsbScoreTop: strongest, then most recent). It is built by the sbbiblio tool
//  and read by Siby (sc_tree search -nsb 1, sc_nsb ...), which then
//  displays the opening library instantly.
//
//  Format (little-endian):
//    NsbHeader
//    NsbPos  [numPos]     sorted by key
//    NsbMove [numMoves]
//    uint32  [numBest]    game numbers (0-based)
//
//  The key of a position: 64-bit hash of the board and side to move
//  (like the transpositions of SCID's tree: neither castling nor en
//  passant).
//
//////////////////////////////////////////////////////////////////////

#ifndef SIBY_NSB_H
#define SIBY_NSB_H

#include <stdio.h>
#include <string.h>
#include <stdint.h>
#include <ctype.h>
#include <string>
#include "sibyfopen.h"

#define NSB_MAGIC   0x3142534e   // "NSB1"
#define NSB_VERSION 3   // 3: top games: decreasing age penalty, estimated ratings (base.sbc)

// "Top games" rank (as in ChessBase): the strongest games first, recent
// ones slightly ahead: average Elo minus a decreasing penalty for age,
// 19 points in the first year, 17 in the second, ... 1 in the tenth, then
// nothing (100 at most), Yosha 2026-11-03: a classic like Fischer-Spassky
// 1972 stays near the top. Counted month by month (the penalty after t
// years is 100 * (1 - (1 - t/10)^2)), in half points. Games without a year
// count as old (100); without a month, as played in June. anneeRef/moisRef:
// today.
static inline uint32_t nsbScoreTop (uint32_t eloBlanc, uint32_t eloNoir, uint32_t annee, uint32_t mois,
                                    uint32_t anneeRef, uint32_t moisRef) {
    uint32_t age = 120;   // months (10 years and more: the full penalty)
    if (annee > 0 && annee <= anneeRef) {
        if (mois < 1 || mois > 12) { mois = 6; }
        long a = (long) (anneeRef * 12 + moisRef) - (long) (annee * 12 + mois);
        age = a < 0 ? 0 : (a > 120 ? 120 : (uint32_t) a);
    }
    uint32_t reste = 120 - age;
    uint32_t penalite = 200 - (reste * reste) / 72;   // (half points: 200 = 100 points)
    uint32_t moyenne = (eloBlanc + eloNoir) / 2;
    return 2000 + 2 * moyenne - penalite;
}

// The best games' penalty by time control (Gaby's flags: 2 rapid, 3 blitz,
// 4 correspondence, 5 online), in half points like nsbScoreTop: rapid -75,
// blitz -150, online or correspondence -100 more. Blitz and rapid ratings
// run higher: Norway Chess Blitz came before the classical games (Yosha
// 2026-11-10); measured on Gaby's sample, the classical games then lead
// and an exceptional rapid game can still come in.
static inline uint32_t nsbMalusTop (bool f2, bool f3, bool f4, bool f5) {
    uint32_t m = 0;
    if (f3 && !f2) { m = 150; } else if (f2) { m = 75; }
    if (f4 || f5) { m += 100; }
    return 2 * m;
}
static inline uint32_t nsbScoreTopCadence (uint32_t eloBlanc, uint32_t eloNoir, uint32_t annee, uint32_t mois,
                                           uint32_t anneeRef, uint32_t moisRef, uint32_t malus) {
    uint32_t s = nsbScoreTop (eloBlanc, eloNoir, annee, mois, anneeRef, moisRef);
    return s > malus ? s - malus : 0;
}

// Online games (Gaby): custom flag 5 named "En ligne" / "Online". Such a
// database has two libraries: base.sbl (games over the board) and
// base.online.sbl (online games); reserve[NSB_RES_CONTENU] tells which.
#define NSB_FLAG_EN_LIGNE      5
#define NSB_RES_CONTENU        0
#define NSB_CONTENU_TOUT       0   // every game
#define NSB_CONTENU_ECHIQUIER  1   // over the board only (online games apart)
#define NSB_CONTENU_EN_LIGNE   2   // online games only

// Additions (Siby): games appended to the database after the library was
// built are read alone into small files, base.ajouts.sbl (and
// base.ajouts.online.sbl), added up with the main library when reading.
// Their header: numGames = games covered in all, reserve[NSB_RES_DEBUT] =
// first game read (= numGames of the main library), empreinte = that of
// the main library (its first games), reserve[NSB_RES_EMPR_*] = fingerprint
// of all the games covered. Every position of the new games is kept
// (threshold 1); a position is only used when the main library has it
// (otherwise the normal search, which reads every game, takes over).
// Libraries by time control (Gaby, Yosha 2026-11-05): base.classical.sbl,
// base.rapid.sbl, base.blitz.sbl (with their .online.sbl and additions),
// built from the games carrying custom flag 1, 2 or 3 only, so that the
// time-control filter is as fast as "all". Same format; the file root
// becomes base.classical etc. nsbNomCadence: that word, or NULL.
static inline const char * nsbNomCadence (int drapeau) {
    switch (drapeau) {
        case 1: return "classical";
        case 2: return "rapid";
        case 3: return "blitz";
    }
    return NULL;
}

#define NSB_RES_DEBUT    1
#define NSB_RES_EMPR_LO  2
#define NSB_RES_EMPR_HI  3

static inline bool nsbDrapeauEnLigne (const char * desc) {
    char d [16];
    int n = 0;
    for (; desc[n] && n < 15; n++) { d[n] = (char) tolower ((unsigned char) desc[n]); }
    d[n] = 0;
    return !strcmp (d, "en ligne") || !strcmp (d, "online");
}

// Time control of a game, for the historical ratings (base.sbc) and the
// estimated Elo: 0 classical, 1 rapid, 2 blitz, -1 left out.
// - A Gaby database (custom flag 5 named "Online" / "En ligne"): its flags
//   are the only truth (1 classical, 2 rapid, 3 blitz, 4 correspondence,
//   5 online; Gaby's rules CAD-1..6). The event name only leaves out games
//   that are not standard chess (simultaneous, blindfold, odds, Chess960...).
// - Any other database: the event name ("rapid", "blitz", "lightning";
//   online, correspondence and the like are left out).
enum { NSB_CLASSIQUE = 0, NSB_RAPIDE = 1, NSB_BLITZ = 2 };
static inline std::string nsbMinuscules (const char * nom) {
    std::string m (nom ? nom : "");
    for (size_t i = 0; i < m.size(); i++) { m[i] = (char) tolower ((unsigned char) m[i]); }
    return m;
}
static inline bool nsbEvenementSpecial (const std::string & m) {
    static const char * mots[] = {
        "simul", "armageddon", "blindfold", "blind", "odds", "handicap", "consultation",
        "960", "9lx", "fischerandom", "fischer random", "freestyle", NULL };
    for (int i = 0; mots[i]; i++) { if (m.find (mots[i]) != std::string::npos) { return true; } }
    return false;
}
// Cadence said by words in an event name (lower case): NSB_RAPIDE,
// NSB_BLITZ, -1 (no word), NSB_CADENCE_DEUX (both). Semi-blitz / semilampo
// (12-15 min) are rapid.
enum { NSB_CADENCE_DEUX = 99 };
static inline int nsbCadenceMot (const std::string & m) {
    static const char * semi[] = { "semiblitz", "semi-blitz", "semi blitz", "semilampo", "semi-lampo", NULL };
    std::string t = m;
    bool rapide = false;
    for (int i = 0; semi[i]; i++) {
        size_t p;
        while ((p = t.find (semi[i])) != std::string::npos) { t.erase (p, strlen (semi[i])); rapide = true; }
    }
    bool blitz = t.find ("blitz") != std::string::npos || t.find ("lightning") != std::string::npos
              || t.find ("lampo") != std::string::npos;
    if (t.find ("rapid") != std::string::npos) { rapide = true; }
    if (rapide && blitz) { return NSB_CADENCE_DEUX; }
    return blitz ? NSB_BLITZ : (rapide ? NSB_RAPIDE : -1);
}
static inline int nsbCadenceEvenement (const char * nom) {
    static const char * ecartes[] = {
        "bullet", "speed", "online", "internet", "lichess", "chess.com", "titled", "arena",
        "correspondence", "corr ", "iccf", "email", "e-mail", "playchess", "icc ", "fics", NULL };
    std::string m = nsbMinuscules (nom);
    if (nsbEvenementSpecial (m)) { return -1; }
    for (int i = 0; ecartes[i]; i++) { if (m.find (ecartes[i]) != std::string::npos) { return -1; } }
    // "Rapid & Blitz Championships | Rapid": the section after the last "|"
    // decides; a name that still says both is left undecided
    size_t barre = m.rfind ('|');
    if (barre != std::string::npos) {
        int c = nsbCadenceMot (m.substr (barre + 1));
        if (c == NSB_CADENCE_DEUX) { return -1; }
        if (c >= 0) { return c; }
    }
    int c = nsbCadenceMot (m);
    if (c == NSB_CADENCE_DEUX) { return -1; }
    return c >= 0 ? c : NSB_CLASSIQUE;
}
static inline int nsbCadence (const char * evenement, bool drapeauxGaby, bool f2, bool f3, bool f4, bool f5) {
    if (!drapeauxGaby) { return nsbCadenceEvenement (evenement); }
    if (f4 || f5 || nsbEvenementSpecial (nsbMinuscules (evenement))) { return -1; }
    // both flags: rapid or blitz, which one unknown (Gaby's "rapide/blitz",
    // knockout tiebreaks): undecided, like a name that says both
    if (f2 && f3) { return -1; }
    return f3 ? NSB_BLITZ : (f2 ? NSB_RAPIDE : NSB_CLASSIQUE);
}

// File names (Siby): base.sbl (opening library), base.online.sbl (online
// games apart), base.sbp (position index). Files of the NovaScid era
// (.nsb, .online.nsb, .nsp) are renamed the first time they are met.
#include <stdio.h>
#include <string>
#include "sibyfopen.h"
static inline void sibyMigrerFichiers (const std::string & base) {
    static const char * paires [][2] = {
        {".nsb", ".sbl"}, {".online.nsb", ".online.sbl"}, {".nsp", ".sbp"}
    };
    for (auto & p : paires) {
        std::string ancien = base + p[0], nouveau = base + p[1];
        FILE * f = fopen (nouveau.c_str(), "rb");
        if (f) { fclose (f); continue; }
        f = fopen (ancien.c_str(), "rb");
        if (!f) { continue; }
        fclose (f);
        siby_rename (ancien.c_str(), nouveau.c_str());
    }
}

struct NsbHeader {
    uint32_t magic;
    uint32_t version;
    uint32_t numGames;       // database games read
    uint32_t plies;          // depth (plies)
    uint32_t seuil;          // minimum games per position
    uint32_t maxBest;        // best games kept per position
    uint64_t empreinte;      // fingerprint of the games read (see nsbEmpreinte)
    uint64_t numPos;
    uint64_t numMoves;
    uint64_t numBest;
    uint64_t date;           // build date (seconds)
    uint32_t reserve[8];
};

struct NsbPos {
    uint64_t key;
    uint32_t firstMove;
    uint32_t firstBest;
    uint16_t nMoves;
    uint16_t nBest;
    uint32_t pad;
};

struct NsbMove {
    uint8_t  from, to, promote, pad;
    uint32_t freq[4];        // per result (resultT: none, 1-0, 0-1, draw)
    uint32_t total;
    uint32_t eloCount;
    uint32_t perfCount;
    uint32_t yearCount;
    uint32_t lastDate;
    uint32_t pad2;
    uint64_t eloSum;
    uint64_t perfSum;
    uint64_t yearSum;
};

// Position hash (Zobrist, fixed table drawn from a splitmix64 sequence)
static inline uint64_t nsbSplitmix (uint64_t & s) {
    uint64_t z = (s += 0x9E3779B97F4A7C15ULL);
    z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9ULL;
    z = (z ^ (z >> 27)) * 0x94D049BB133111EBULL;
    return z ^ (z >> 31);
}

static inline const uint64_t * nsbTable () {
    static uint64_t table[64 * 16 + 1];
    static bool pret = false;
    if (!pret) {
        uint64_t s = 0x4E6F766153636964ULL;   // "Siby"
        for (int i = 0; i < 64 * 16 + 1; i++) { table[i] = nsbSplitmix (s); }
        pret = true;
    }
    return table;
}

// board: 64 squares (pieceT, 0 = empty, < 16), toMove: 0 White, 1 Black
static inline uint64_t nsbCle (const unsigned char * board, int toMove) {
    const uint64_t * t = nsbTable();
    uint64_t h = 0;
    for (int sq = 0; sq < 64; sq++) {
        unsigned p = board[sq] & 15;
        if (p && p != 7) { h ^= t[sq * 16 + p]; }   // (7: empty square)
    }
    if (toMove) { h ^= t[64 * 16]; }
    return h;
}

// Fingerprint of the first n games of a database: a sample of at most
// ~4000 index entries (offset in the file, length, date, players).
// If the database only had games appended at the end, the fingerprint of
// the first n does not change.
template <class FETCH>
static inline uint64_t nsbEmpreinte (uint32_t n, FETCH fetch) {
    uint64_t h = 0x6E73626569707265ULL ^ n;
    if (n == 0) { return h; }
    uint32_t pas = n / 4000 + 1;
    for (uint32_t i = 0; i < n; i += pas) {
        uint64_t v = fetch (i);
        uint64_t s = h ^ v ^ ((uint64_t) i << 32);
        h = nsbSplitmix (s);
    }
    uint64_t s = h ^ fetch (n - 1);
    return nsbSplitmix (s);
}

// Reading: binary search in the file (no data kept in memory; the file
// is opened and closed on each read so that sbbiblio can replace it
// while Siby is running).
class NsbLecteur {
  public:
    // Reads the header; false if missing or unreadable
    static bool entete (const char * fichier, NsbHeader * h) {
        FILE * f = fopen (fichier, "rb");
        if (!f) { return false; }
        bool ok = fread (h, sizeof (NsbHeader), 1, f) == 1
               && h->magic == NSB_MAGIC && h->version == NSB_VERSION;
        fclose (f);
        return ok;
    }

    // Moves and best games of the position with key `key`.
    // Returns the number of moves (0: position not found).
    static int chercher (const char * fichier, uint64_t key,
                         NsbMove * coups, int maxCoups,
                         uint32_t * best, int maxBest, int * nBest) {
        *nBest = 0;
        FILE * f = fopen (fichier, "rb");
        if (!f) { return 0; }
        NsbHeader h;
        if (fread (&h, sizeof h, 1, f) != 1 || h.magic != NSB_MAGIC || h.version != NSB_VERSION) {
            fclose (f); return 0;
        }
        long long bas = 0, haut = (long long) h.numPos - 1;
        NsbPos p;
        bool trouve = false;
        while (bas <= haut) {
            long long m = (bas + haut) / 2;
            if (!lireA (f, sizeof (NsbHeader) + m * sizeof (NsbPos), &p, sizeof p)) { break; }
            if (p.key == key) { trouve = true; break; }
            if (p.key < key) { bas = m + 1; } else { haut = m - 1; }
        }
        int n = 0;
        if (trouve) {
            long long baseMoves = sizeof (NsbHeader) + (long long) h.numPos * sizeof (NsbPos);
            n = p.nMoves < maxCoups ? p.nMoves : maxCoups;
            if (n > 0 && !lireA (f, baseMoves + (long long) p.firstMove * sizeof (NsbMove),
                                 coups, n * sizeof (NsbMove))) {
                n = 0;
            }
            int nb = p.nBest < maxBest ? p.nBest : maxBest;
            long long baseBest = baseMoves + (long long) h.numMoves * sizeof (NsbMove);
            if (n > 0 && nb > 0 && lireA (f, baseBest + (long long) p.firstBest * 4, best, nb * 4)) {
                *nBest = nb;
            }
        }
        fclose (f);
        return n;
    }

  private:
    static bool lireA (FILE * f, long long pos, void * buf, size_t n) {
#ifdef _WIN32
        if (_fseeki64 (f, pos, SEEK_SET) != 0) { return false; }
#else
        if (fseeko (f, (off_t) pos, SEEK_SET) != 0) { return false; }
#endif
        return fread (buf, 1, n, f) == n;
    }
};

#endif  // SIBY_NSB_H
