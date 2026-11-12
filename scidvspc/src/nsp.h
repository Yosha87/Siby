//////////////////////////////////////////////////////////////////////
//
//  FILE:       nsp.h
//              Siby: position search index (.sbp)
//
//  A "base.sbp" file next to "base.si4" tells, for each game and each
//  (piece, square) pair, whether that piece stood on that square at some
//  point of the game (main line). A partial position search reads only
//  the relevant columns ("a white knight on f5", "a black pawn on e5"…),
//  combines them, and then reads only the candidate games.
//
//  Games are stored in blocks of NSP_BLOC games. Each block keeps a
//  fingerprint of the index entries of its games: a block whose
//  fingerprint no longer matches the database (game modified, deleted
//  then compacted…) is ignored and its games are read normally. The
//  result of a search is therefore always exact; sbbiblio updates only
//  the changed blocks and the new games.
//
//  Format (little-endian):
//    NspHeader
//    NspBloc [numBlocs]
//    data:   for each block, NSP_COLONNES columns of NSP_BLOC/8 bytes
//            (bit g of column c: game (block*NSP_BLOC + g) had the
//            piece of c on the square of c; columns NSP_COL_PIONS + 9w + n:
//            the game had a position with w white and n black pawns)
//
//////////////////////////////////////////////////////////////////////

#ifndef SIBY_NSP_H
#define SIBY_NSP_H

#include <stdio.h>
#include <string.h>
#include <stdint.h>

#define NSP_MAGIC    0x3150534e   // "NSP1"
#define NSP_VERSION  2
#define NSP_BLOC     262144       // games per block
#define NSP_COLONNES (12 * 64 + 81)
#define NSP_COL_PIONS (12 * 64)   // + 9 * whitePawns + blackPawns
#define NSP_OCTETS_COLONNE (NSP_BLOC / 8)
#define NSP_OCTETS_BLOC ((long long) NSP_COLONNES * NSP_OCTETS_COLONNE)

struct NspHeader {
    uint32_t magic;
    uint32_t version;
    uint32_t numGames;       // games covered
    uint32_t numBlocs;
    uint32_t taillebloc;     // NSP_BLOC
    uint32_t reserve[11];
};

struct NspBloc {
    uint64_t empreinte;      // fingerprint of the block's index entries
    uint32_t parties;        // games in the block (the last one may be partial)
    uint32_t pad;
};

// Column of a SCID piece (WK=1..WP=6, BK=9..BP=14) on a square 0..63;
// -1 if it is not a piece
static inline int nspColonne (unsigned piece, unsigned sq) {
    int t;
    if (piece >= 1 && piece <= 6) { t = piece - 1; }
    else if (piece >= 9 && piece <= 14) { t = piece - 9 + 6; }
    else { return -1; }
    return t * 64 + (int) sq;
}

// Fingerprint of a game for its block (offset and length in the games
// file: they change when the game is modified)
static inline uint64_t nspValeur (uint32_t offset, uint32_t longueur, uint32_t gnum) {
    uint64_t z = ((uint64_t) offset << 32 | longueur) + 0x9E3779B97F4A7C15ULL * (gnum + 1);
    z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9ULL;
    z = (z ^ (z >> 27)) * 0x94D049BB133111EBULL;
    return z ^ (z >> 31);
}

// Fingerprint of block b (games b*NSP_BLOC to b*NSP_BLOC + n - 1).
// FETCH(i, &offset, &longueur)
template <class FETCH>
static inline uint64_t nspEmpreinteBloc (uint32_t b, uint32_t n, FETCH fetch) {
    uint64_t h = 0x6E73706964780000ULL ^ n;
    for (uint32_t k = 0; k < n; k++) {
        uint32_t g = b * NSP_BLOC + k, o = 0, l = 0;
        fetch (g, &o, &l);
        h += nspValeur (o, l, g);   // sum: the reading order does not matter
    }
    return h;
}

static inline long long nspDebutDonnees (uint32_t numBlocs) {
    return (long long) sizeof (NspHeader) + (long long) numBlocs * sizeof (NspBloc);
}

class NspLecteur {
  public:
    static bool entete (FILE * f, NspHeader * h) {
        if (!lireA (f, 0, h, sizeof *h)) { return false; }
        return h->magic == NSP_MAGIC && h->version == NSP_VERSION && h->taillebloc == NSP_BLOC;
    }
    static bool blocs (FILE * f, const NspHeader * h, NspBloc * bl) {
        return h->numBlocs == 0 || lireA (f, sizeof (NspHeader), bl, h->numBlocs * sizeof (NspBloc));
    }
    // Reads column c of block b (NSP_OCTETS_COLONNE bytes)
    static bool colonne (FILE * f, const NspHeader * h, uint32_t b, int c, void * buf) {
        long long pos = nspDebutDonnees (h->numBlocs) + (long long) b * NSP_OCTETS_BLOC
                      + (long long) c * NSP_OCTETS_COLONNE;
        return lireA (f, pos, buf, NSP_OCTETS_COLONNE);
    }
    static bool lireA (FILE * f, long long pos, void * buf, size_t n) {
#ifdef _WIN32
        if (_fseeki64 (f, pos, SEEK_SET) != 0) { return false; }
#else
        if (fseeko (f, (off_t) pos, SEEK_SET) != 0) { return false; }
#endif
        return fread (buf, 1, n, f) == n;
    }
};

#endif  // SIBY_NSP_H
