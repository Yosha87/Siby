//////////////////////////////////////////////////////////////////////
//
//  Siby: search accelerator (<base>.sia), as ChessBase's: one signature
//  of 64 bytes per game (Game::SignatureSiby). A move search reads the
//  signatures and decodes only the games that can match.
//    header (24 bytes): "SIBYACC2", games covered n, sample of the index
//    (offsets and lengths of 1 game in 4096: tells a base replaced or
//    compacted), end of the games data when built ("fin": a game saved
//    again after that is written beyond it), reserved
//  Games added since (Gaby's daily files) and games saved again are read
//  normally, and indexed by an update.
//  Shared by Siby (reading, small updates) and sbbiblio --accel (making it
//  in the background).
//
//////////////////////////////////////////////////////////////////////

#ifndef SIBY_SIA_H
#define SIBY_SIA_H

#include <stdio.h>
#include <string.h>
#include <stdint.h>
#include "index.h"
#include "sibyfopen.h"

static const unsigned SIA_TAILLE = 64;   // bytes per game

struct siaEnteteT {
    char magic[8];
    uint32_t n;
    uint32_t echantillon;
    uint32_t fin;
    uint32_t reserve;
};

static inline uint32_t siaEchantillonIdx (Index * idx, unsigned n) {
    uint32_t h = 2166136261u;
    for (unsigned i = 0; i < n; i += 4096) {
        IndexEntry * ie = idx->FetchEntry (i);
        h = (h ^ ie->GetOffset()) * 16777619u;
        h = (h ^ ie->GetLength()) * 16777619u;
    }
    if (n > 0) {
        IndexEntry * ie = idx->FetchEntry (n - 1);
        h = (h ^ ie->GetOffset()) * 16777619u;
        h = (h ^ ie->GetLength()) * 16777619u;
    }
    return h;
}

static inline uint32_t siaFinIdx (Index * idx, unsigned numGames) {
    uint32_t fin = 0;
    for (unsigned i = 0; i < numGames; i++) {
        IndexEntry * ie = idx->FetchEntry (i);
        uint32_t f = ie->GetOffset() + ie->GetLength();
        if (f > fin) { fin = f; }
    }
    return fin;
}

// 0: none, 1: up to date, 2: games to add (new or saved again), 3: stale
static inline int siaEtatFichier (const char * chemin, Index * idx, unsigned numGames,
                                  siaEnteteT * e, unsigned * aFaire) {
    *aFaire = numGames;
    FILE * f = fopen (chemin, "rb");
    if (!f) { return 0; }
    bool ok = fread (e, sizeof (siaEnteteT), 1, f) == 1 && !memcmp (e->magic, "SIBYACC2", 8);
    long taille = -1;
    if (ok && fseek (f, 0, SEEK_END) == 0) { taille = ftell (f); }
    fclose (f);
    if (!ok || taille != (long) (sizeof (siaEnteteT) + SIA_TAILLE * (size_t) e->n) || e->n > numGames
        || siaEchantillonIdx (idx, e->n) != e->echantillon) {
        return 3;
    }
    unsigned k = numGames - e->n;
    for (unsigned i = 0; i < e->n; i++) {
        if (idx->FetchEntry(i)->GetOffset() >= e->fin) { k++; }
    }
    *aFaire = k;
    return k ? 2 : 1;
}

#endif
