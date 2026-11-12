//////////////////////////////////////////////////////////////////////
//
//  Siby: historical rating file (base.sbc, written by sbclassement),
//  shared by Siby (the estimated rating in brackets) and sbbiblio (the
//  rank of the top games of games without ratings).
//
//  One line per player and year, sorted by name byte by byte:
//  "name TAB year TAB rating games margin fide TAB birth TAB rapid:
//  rating games margin fide TAB blitz: rating games margin fide" (tabs; a
//  rating of 0: no game in that time control that year). Files of the
//  classical-only era have 7 columns.
//
//////////////////////////////////////////////////////////////////////

#ifndef SIBY_SBC_H
#define SIBY_SBC_H

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <string>
#include <vector>
#include "nsb.h"

struct SbcLigne { int annee; int elo[3]; };

// Reads one line (modified in place): false if it is not a rating line
static inline bool sbcLireLigne (char * ligne, const char ** nom, SbcLigne * l) {
    char * tab = strchr (ligne, '\t');
    if (!tab) { return false; }
    *tab = 0;
    *nom = ligne;
    int x[13] = { 0 };
    int n = sscanf (tab + 1, "%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d",
                    &x[0], &x[1], &x[2], &x[3], &x[4], &x[5], &x[6], &x[7], &x[8], &x[9], &x[10], &x[11], &x[12]);
    if (n < 2 || x[0] <= 0) { return false; }
    l->annee = x[0];
    l->elo[0] = x[1];
    l->elo[1] = n >= 7 ? x[6] : 0;
    l->elo[2] = n >= 11 ? x[10] : 0;
    return true;
}

// Estimated rating of a player (lines l) in a game of year annee and time
// control cad (NSB_CLASSIQUE, NSB_RAPIDE, NSB_BLITZ): the rating of that
// time control that year; for rapid or blitz without games in that cadence
// that year, the classical rating of that year (the classical rating also
// is the prior of the rapid and blitz ratings, see sbclassement); else the
// nearest year (at most 5 years away), in the game's cadence then in
// classical; otherwise 0.
static inline int sbcEstimer (const std::vector<SbcLigne> & l, int annee, int cad) {
    if (annee <= 0 || cad < 0) { return 0; }
    if (cad != NSB_CLASSIQUE) {
        for (size_t i = 0; i < l.size(); i++) {
            if (l[i].annee == annee) {
                if (l[i].elo[cad] > 0) { return l[i].elo[cad]; }
                if (l[i].elo[NSB_CLASSIQUE] > 0) { return l[i].elo[NSB_CLASSIQUE]; }
            }
        }
    }
    int meilleur = 0, ecart = 99;
    for (int c = cad; c >= 0; c = (c == NSB_CLASSIQUE ? -1 : NSB_CLASSIQUE)) {
        for (size_t i = 0; i < l.size(); i++) {
            if (l[i].elo[c] <= 0) { continue; }
            int e = abs (l[i].annee - annee);
            if (e < ecart) { ecart = e; meilleur = l[i].elo[c]; }
        }
        if (ecart <= 5) { break; }
    }
    return ecart > 5 ? 0 : meilleur;
}

#endif
