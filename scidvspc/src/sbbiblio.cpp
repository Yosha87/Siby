//////////////////////////////////////////////////////////////////////
//
//  FILE:       sbbiblio.cpp
//              Siby: builds the precomputed opening library
//              (base.sbl) of a SCID database
//
//  Usage: sbbiblio [options] base[.si4]
//    --profondeur N   plies read in each game (default 40)
//    --seuil N        minimum number of games to keep a position
//                     (default: 1 per 200,000 games, at least 5)
//    --meilleures N   best games kept per position (default 10)
//    --si-perime      do nothing if the file is already up to date
//    --sans-positions      do not build the position index (.sbp)
//    --positions-seulement only the position index (.sbp)
//    --cadence N      only the games with custom flag N (1 classical,
//                     2 rapid, 3 blitz): base.classical.sbl etc. (nsb.h);
//                     no position index
//  sbbiblio --sha256 file: prints "SHA256 <hex>" (Gaby downloads)
//
//  With --si-perime, games appended at the end since the library was
//  built are read alone into base.ajouts.sbl (see nsb.h), in a few
//  seconds, as long as they are few (at most a fifth of the database, or
//  5,000 games); otherwise, or when the earlier games changed, the
//  whole library is rebuilt (and the additions removed).
//
//  Then the position search index (base.sbp, see nsp.h) is updated:
//  only the changed blocks of games and the new games are read again
//  (pass 3).
//
//  Two passes over all the games:
//    1. count (approximately, "count-min sketch") in how many games each
//       position of the opening moves occurs;
//    2. for frequent enough positions, add up the statistics of each move
//       (like SCID's tree search) and keep the best games (strongest
//       first, recent ones slightly ahead: nsbScoreTop in nsb.h).
//  The file is written alongside (base.sbl.tmp) and then replaces the old one.
//
//  Output (for Siby and scripts): lines "PROGRES pass i n",
//  then "OK positions moves seconds" or "A_JOUR" (up to date), then
//  "NSP OK rebuilt_blocks seconds" or "NSP A_JOUR", or "ERREUR text"
//  (exit code 1).
//
//////////////////////////////////////////////////////////////////////

#include "common.h"
#include "index.h"
#include "gfile.h"
#include "game.h"
#include "bytebuf.h"
#include "nsb.h"
#include "sbc.h"
#include "namebase.h"
#include "nsp.h"
#include "sha256.h"
#include "sia.h"
#include <atomic>
#include "sibyfopen.h"
#ifdef _WIN32
#include <windows.h>
#include "sibyfopen.h"
#else
#include <pthread.h>
#include <unistd.h>
#include "sibyfopen.h"
#endif

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <vector>
#include <algorithm>
#include <string>
#include <unordered_map>
#include "sibyfopen.h"

static void erreur (const char * texte, const char * detail = "") {
    printf ("ERREUR %s%s\n", texte, detail);
    fflush (stdout);
    exit (1);
}

static inline uint64_t melange (uint64_t x) {
    uint64_t s = x;
    return nsbSplitmix (s);
}

////////////////////////////////////////////////////////////////////////
// Approximate counter (count-min, 2 rows of 16-bit counters)

struct Esquisse {
    std::vector<uint16_t> r1, r2;
    uint64_t masque;
    Esquisse (int bits) : r1 (1ULL << bits, 0), r2 (1ULL << bits, 0), masque ((1ULL << bits) - 1) {}
    inline void ajouter (uint64_t k) {
        uint16_t & a = r1[k & masque];
        uint16_t & b = r2[melange (k) & masque];
        if (a < 65535) { a++; }
        if (b < 65535) { b++; }
    }
    inline uint32_t estimer (uint64_t k) const {
        uint16_t a = r1[k & masque];
        uint16_t b = r2[melange (k) & masque];
        return a < b ? a : b;
    }
};

////////////////////////////////////////////////////////////////////////
// Move table: (position, move) -> statistics (open addressing)

struct EntreeCoup {
    uint64_t key;
    uint32_t mv;        // from | to << 8 | promote << 16 | 1 << 24 (0 = free)
    uint32_t pad;
    NsbMove  st;
};

struct TableCoups {
    std::vector<EntreeCoup> t;
    uint64_t n = 0;
    TableCoups () { t.resize (1 << 20); memset (&t[0], 0, t.size() * sizeof (EntreeCoup)); }
    inline uint64_t h (uint64_t key, uint32_t mv) const { return melange (key ^ ((uint64_t) mv * 0x9E3779B97F4A7C15ULL)); }
    void agrandir () {
        std::vector<EntreeCoup> ancien;
        ancien.swap (t);
        t.resize (ancien.size() * 2);
        memset (&t[0], 0, t.size() * sizeof (EntreeCoup));
        uint64_t m = t.size() - 1;
        for (size_t i = 0; i < ancien.size(); i++) {
            if (!ancien[i].mv) { continue; }
            uint64_t j = h (ancien[i].key, ancien[i].mv) & m;
            while (t[j].mv) { j = (j + 1) & m; }
            t[j] = ancien[i];
        }
    }
    NsbMove & obtenir (uint64_t key, uint32_t mv) {
        if ((n + 1) * 10 > t.size() * 7) { agrandir(); }
        uint64_t m = t.size() - 1;
        uint64_t j = h (key, mv) & m;
        while (t[j].mv) {
            if (t[j].key == key && t[j].mv == mv) { return t[j].st; }
            j = (j + 1) & m;
        }
        t[j].key = key;
        t[j].mv = mv;
        memset (&t[j].st, 0, sizeof (NsbMove));
        t[j].st.from = mv & 255;
        t[j].st.to = (mv >> 8) & 255;
        t[j].st.promote = (mv >> 16) & 255;
        n++;
        return t[j].st;
    }
};

////////////////////////////////////////////////////////////////////////
// Best games per position: the K largest (average Elo, -number)

struct TableMeilleures {
    int K;
    std::vector<uint64_t> cles;
    std::vector<uint16_t> nb;
    std::vector<uint64_t> items;   // K per slot
    uint64_t n = 0;
    TableMeilleures (int k) : K (k) { initialiser (1 << 18); }
    void initialiser (size_t taille) {
        cles.assign (taille, 0); nb.assign (taille, 0); items.assign (taille * K, 0);
    }
    void agrandir () {
        std::vector<uint64_t> c; std::vector<uint16_t> b; std::vector<uint64_t> it;
        c.swap (cles); b.swap (nb); it.swap (items);
        initialiser (c.size() * 2);
        uint64_t m = cles.size() - 1;
        for (size_t i = 0; i < c.size(); i++) {
            if (!b[i]) { continue; }
            uint64_t j = melange (c[i]) & m;
            while (nb[j]) { j = (j + 1) & m; }
            cles[j] = c[i]; nb[j] = b[i];
            memcpy (&items[j * K], &it[i * K], K * sizeof (uint64_t));
        }
    }
    void ajouter (uint64_t key, uint64_t v) {
        if (K <= 0) { return; }
        if ((n + 1) * 10 > cles.size() * 7) { agrandir(); }
        uint64_t m = cles.size() - 1;
        uint64_t j = melange (key) & m;
        while (nb[j] && cles[j] != key) { j = (j + 1) & m; }
        if (!nb[j]) { cles[j] = key; n++; }
        uint64_t * p = &items[j * K];
        if (nb[j] < K) { p[nb[j]++] = v; return; }
        int imin = 0;
        for (int i = 1; i < K; i++) { if (p[i] < p[imin]) { imin = i; } }
        if (v > p[imin]) { p[imin] = v; }
    }
    // Returns the position's items sorted (descending), or 0
    int lire (uint64_t key, uint64_t * sortie) const {
        uint64_t m = cles.size() - 1;
        uint64_t j = melange (key) & m;
        while (nb[j]) {
            if (cles[j] == key) {
                int k = nb[j];
                memcpy (sortie, &items[j * K], k * sizeof (uint64_t));
                std::sort (sortie, sortie + k, [] (uint64_t a, uint64_t b) { return a > b; });
                return k;
            }
            j = (j + 1) & m;
        }
        return 0;
    }
};

////////////////////////////////////////////////////////////////////////
// Position search index (.sbp)

static void
construireNsp (Index & idx, GFile & gf, const std::string & base, bool siPerime)
{
    std::string fichier = base + ".sbp";
    std::string temporaire = fichier + ".tmp";
    uint32_t numGames = idx.GetNumGames();
    // custom flag 5 named "En ligne" / "Online": online games kept apart
    bool separer = false;
    {
        char desc [CUSTOM_FLAG_DESC_LENGTH + 1];
        idx.GetCustomFlagDesc (desc, NSB_FLAG_EN_LIGNE);
        separer = nsbDrapeauEnLigne (desc);
    }
    uint32_t numBlocs = (numGames + NSP_BLOC - 1) / NSP_BLOC;
    time_t debut = time (NULL);

    // old file: reusable blocks
    NspHeader ancien;
    std::vector<NspBloc> anciensBlocs;
    FILE * fa = fopen (fichier.c_str(), "rb");
    if (fa && NspLecteur::entete (fa, &ancien)) {
        anciensBlocs.resize (ancien.numBlocs);
        if (!NspLecteur::blocs (fa, &ancien, anciensBlocs.empty() ? NULL : &anciensBlocs[0])) {
            anciensBlocs.clear();
        }
    } else if (fa) { fclose (fa); fa = NULL; }

    // fingerprints of the database's blocks
    std::vector<NspBloc> blocs (numBlocs);
    std::vector<IndexEntry> entrees (NSP_BLOC);
    std::vector<bool> aRefaire (numBlocs, true);
    uint32_t nRefaire = 0;
    for (uint32_t b = 0; b < numBlocs; b++) {
        uint32_t n = std::min<uint32_t> (NSP_BLOC, numGames - b * NSP_BLOC);
        if (idx.ReadEntries (&entrees[0], b * NSP_BLOC, n) != OK) { erreur ("reading the index"); }
        blocs[b].parties = n;
        blocs[b].pad = 0;
        blocs[b].empreinte = nspEmpreinteBloc (b, n, [&] (uint32_t g, uint32_t * o, uint32_t * l) {
            IndexEntry * ie = &entrees[g - b * NSP_BLOC];
            *o = ie->GetOffset(); *l = ie->GetLength();
        });
        if (b < anciensBlocs.size() && anciensBlocs[b].parties == n
                && anciensBlocs[b].empreinte == blocs[b].empreinte) {
            aRefaire[b] = false;
        } else {
            nRefaire++;
        }
    }
    if (nRefaire == 0 && fa && ancien.numBlocs == numBlocs && ancien.numGames == numGames) {
        fclose (fa);
        printf ("NSP A_JOUR %u\n", numGames);
        fflush (stdout);
        return;
    }
    (void) siPerime;

    FILE * f = fopen (temporaire.c_str(), "wb");
    if (!f) { erreur ("writing ", temporaire.c_str()); }
    NspHeader h;
    memset (&h, 0, sizeof h);
    h.magic = NSP_MAGIC;
    h.version = NSP_VERSION;
    h.numGames = numGames;
    h.numBlocs = numBlocs;
    h.taillebloc = NSP_BLOC;
    fwrite (&h, sizeof h, 1, f);
    if (numBlocs) { fwrite (&blocs[0], sizeof (NspBloc), numBlocs, f); }

    const size_t MOTS = NSP_BLOC / 64;
    std::vector<uint64_t> cols ((size_t) NSP_COLONNES * MOTS);
    ByteBuffer bbuf;
    bbuf.SetBufferSize (BBUF_SIZE);
    Game * g = new Game;
    uint64_t bb[12];
    for (uint32_t b = 0; b < numBlocs; b++) {
        uint32_t n = blocs[b].parties;
        if (!aRefaire[b]) {
            // unchanged block: copied from the old file
            long long pos = nspDebutDonnees (ancien.numBlocs) + (long long) b * NSP_OCTETS_BLOC;
            if (!NspLecteur::lireA (fa, pos, &cols[0], NSP_OCTETS_BLOC)) { erreur ("reading ", fichier.c_str()); }
            fwrite (&cols[0], 1, NSP_OCTETS_BLOC, f);
            printf ("PROGRES 3 %u %u\n", b * NSP_BLOC + n, numGames);
            fflush (stdout);
            continue;
        }
        std::fill (cols.begin(), cols.end(), 0);
        if (idx.ReadEntries (&entrees[0], b * NSP_BLOC, n) != OK) { erreur ("reading the index"); }
        for (uint32_t k = 0; k < n; k++) {
            IndexEntry * ie = &entrees[k];
            memset (bb, 0, sizeof bb);
            uint64_t pions[2] = { 0, 0 };
            bool lu = false;
            if (ie->GetLength() > 0) {
                bbuf.Empty();
                if (gf.ReadGame (&bbuf, ie->GetOffset(), ie->GetLength()) == OK) {
                    g->Clear();
                    errorT err = g->DecodeStart (&bbuf);
                    g->SetKeepDecodedMoves (false);
                    lu = (err == OK);
                    while (err == OK) {
                        Position * pos = g->GetCurrentPos();
                        const pieceT * bd = pos->GetBoard();
                        for (uint sq = 0; sq < 64; sq++) {
                            int c = nspColonne (bd[sq], sq);
                            if (c >= 0) { bb[c >> 6] |= (1ULL << sq); }
                        }
                        uint wp = pos->PieceCount (WP), bp = pos->PieceCount (BP);
                        if (wp <= 8 && bp <= 8) {
                            uint i = wp * 9 + bp;
                            pions[i >> 6] |= 1ULL << (i & 63);
                        }
                        err = g->DecodeNextMove (&bbuf, NULL);
                    }
                }
            }
            if (!lu) {
                // unreadable here: always a candidate (the search will decide)
                for (int t = 0; t < 12; t++) { bb[t] = ~0ULL; }
                pions[0] = pions[1] = ~0ULL;
            }
            uint64_t bit = 1ULL << (k & 63);
            size_t mot = k >> 6;
            for (int t = 0; t < 12; t++) {
                uint64_t x = bb[t];
                while (x) {
                    int sq = __builtin_ctzll (x);
                    x &= x - 1;
                    cols[(size_t) (t * 64 + sq) * MOTS + mot] |= bit;
                }
            }
            for (int i = 0; i < 81; i++) {
                if ((pions[i >> 6] >> (i & 63)) & 1) {
                    cols[(size_t) (NSP_COL_PIONS + i) * MOTS + mot] |= bit;
                }
            }
            if ((k & 16383) == 16383) {
                printf ("PROGRES 3 %u %u\n", b * NSP_BLOC + k + 1, numGames);
                fflush (stdout);
            }
        }
        fwrite (&cols[0], 1, NSP_OCTETS_BLOC, f);
        printf ("PROGRES 3 %u %u\n", b * NSP_BLOC + n, numGames);
        fflush (stdout);
    }
    delete g;
    if (fa) { fclose (fa); }
    if (fclose (f) != 0) { erreur ("writing ", temporaire.c_str()); }
    siby_remove (fichier.c_str());
    if (siby_rename (temporaire.c_str(), fichier.c_str()) != 0) { erreur ("replacing ", fichier.c_str()); }
    printf ("NSP OK %u %ld\n", nRefaire, (long) (time (NULL) - debut));
    fflush (stdout);
}

////////////////////////////////////////////////////////////////////////

static uint64_t valeurEmpreinte (IndexEntry * ie) {
    return ((uint64_t) ie->GetOffset() << 32) ^ ie->GetLength()
         ^ ((uint64_t) ie->GetDate() << 12) ^ ((uint64_t) ie->GetWhite() << 40)
         ^ ((uint64_t) ie->GetBlack() * 2654435761ULL);
}

//////////////////////////////////////////////////////////////////////
// --accel: the search accelerator (<base>.sia, see sia.h), made or
// updated here, in the background, so that Siby keeps answering (on
// Gaby, several minutes). Prints "PROGRES 4 done total", then
// "ACCEL n" (games indexed).

struct SiaTravail {
    Index * idx;
    const char * base;
    const uint32_t * parties;
    byte * sigs;
    uint32_t n;
    std::atomic<uint32_t> suivant;
    std::atomic<uint32_t> faites;
};

static void siaLireUne (SiaTravail * t, Game * g, GFile * gf, ByteBuffer * bbuf, uint32_t k) {
    byte * s = t->sigs + SIA_TAILLE * (size_t) k;
    memset (s, 0, SIA_TAILLE);
    IndexEntry * ie = t->idx->FetchEntry (t->parties[k]);
    if (ie->GetLength() == 0) { return; }
    bbuf->Empty();
    if (gf->ReadGame (bbuf, ie->GetOffset(), ie->GetLength()) != OK) { return; }
    if (g->Decode (bbuf, GAME_DECODE_NONE) != OK) { return; }
    g->SignatureSiby (s);
}

#ifdef _WIN32
static DWORD WINAPI siaFil (LPVOID cd)
#else
static void * siaFil (void * cd)
#endif
{
    SiaTravail * t = (SiaTravail *) cd;
    GFile * gf = new GFile;
    ByteBuffer * bbuf = new ByteBuffer;
    bbuf->SetBufferSize (BBUF_SIZE);
    Game * g = new Game;
    if (gf->Open (t->base, FMODE_ReadOnly) == OK) {
        const uint32_t PAQUET = 256;
        while (true) {
            uint32_t d = t->suivant.fetch_add (PAQUET);
            if (d >= t->n) { break; }
            uint32_t f = std::min (d + PAQUET, t->n);
            for (uint32_t k = d; k < f; k++) { siaLireUne (t, g, gf, bbuf, k); }
            t->faites.fetch_add (f - d);
        }
        gf->Close();
    }
    delete g; delete bbuf; delete gf;
    return 0;
}

static unsigned siaCoeurs () {
#ifdef _WIN32
    SYSTEM_INFO si;
    GetSystemInfo (&si);
    long n = si.dwNumberOfProcessors;
#else
    long n = sysconf (_SC_NPROCESSORS_ONLN);
#endif
    // (one core left free for Siby and the other programs)
    n = n - 1;
    if (n < 1) { n = 1; }
    if (n > 16) { n = 16; }
    return (unsigned) n;
}

// Signatures of the games listed (deja/total: for the progress lines)
static void siaCalculer (Index * idx, const char * base, const uint32_t * parties, uint32_t n,
                         byte * sigs, uint32_t deja, uint32_t total) {
    SiaTravail t;
    t.idx = idx; t.base = base; t.parties = parties; t.sigs = sigs; t.n = n;
    t.suivant = 0; t.faites = 0;
    unsigned nFils = siaCoeurs();
#ifdef _WIN32
    std::vector<HANDLE> fils;
    for (unsigned k = 0; k < nFils; k++) {
        HANDLE h = CreateThread (NULL, 0, siaFil, &t, 0, NULL);
        if (h) { fils.push_back (h); }
    }
#else
    std::vector<pthread_t> fils;
    for (unsigned k = 0; k < nFils; k++) {
        pthread_t id;
        if (pthread_create (&id, NULL, siaFil, &t) == 0) { fils.push_back (id); }
    }
#endif
    if (fils.empty()) { siaFil (&t); }
    while (t.faites.load() < n) {
#ifdef _WIN32
        Sleep (500);
#else
        usleep (500000);
#endif
        printf ("PROGRES 4 %u %u\n", deja + t.faites.load(), total);
        fflush (stdout);
        if (fils.empty()) { break; }
    }
#ifdef _WIN32
    for (size_t k = 0; k < fils.size(); k++) { WaitForSingleObject (fils[k], INFINITE); CloseHandle (fils[k]); }
#else
    for (size_t k = 0; k < fils.size(); k++) { pthread_join (fils[k], NULL); }
#endif
}

static int construireSia (const std::string & base) {
    Index idx;
    idx.SetFileName (base.c_str());
    if (idx.OpenIndexFile (FMODE_ReadOnly) != OK) { erreur ("opening the index ", (base + ".si4").c_str()); }
    if (idx.ReadEntireFile() != OK) { erreur ("reading the index ", (base + ".si4").c_str()); }
    uint32_t numGames = idx.GetNumGames();
    std::string chemin = base + ".sia";
    siaEnteteT e;
    memset (&e, 0, sizeof (e));
    unsigned aFaire;
    int etat = siaEtatFichier (chemin.c_str(), &idx, numGames, &e, &aFaire);
    if (etat == 1) { printf ("ACCEL 0\n"); return 0; }
    const uint32_t TRANCHE = 1 << 18;
    std::vector<uint32_t> liste;
    std::vector<byte> sigs;
    if (etat == 0 || etat == 3) {
        // the whole base, by slices, into a new file
        std::string tmp = chemin + ".tmp";
        FILE * f = fopen (tmp.c_str(), "wb");
        if (!f) { erreur ("writing ", tmp.c_str()); }
        siaEnteteT h;
        memset (&h, 0, sizeof (h));
        memcpy (h.magic, "SIBYACC2", 8);
        fwrite (&h, sizeof (h), 1, f);
        for (uint32_t d = 0; d < numGames; d += TRANCHE) {
            uint32_t n = std::min (TRANCHE, numGames - d);
            liste.resize (n);
            for (uint32_t k = 0; k < n; k++) { liste[k] = d + k; }
            sigs.assign (SIA_TAILLE * (size_t) n, 0);
            siaCalculer (&idx, base.c_str(), &liste[0], n, &sigs[0], d, numGames);
            if (fwrite (&sigs[0], SIA_TAILLE, n, f) != n) { fclose (f); siby_remove (tmp.c_str()); erreur ("writing ", tmp.c_str()); }
        }
        h.n = numGames;
        h.echantillon = siaEchantillonIdx (&idx, numGames);
        h.fin = siaFinIdx (&idx, numGames);
        fseek (f, 0, SEEK_SET);
        fwrite (&h, sizeof (h), 1, f);
        if (fclose (f) != 0) { siby_remove (tmp.c_str()); erreur ("writing ", tmp.c_str()); }
        siby_remove (chemin.c_str());
        if (siby_rename (tmp.c_str(), chemin.c_str()) != 0) { siby_remove (tmp.c_str()); erreur ("writing ", chemin.c_str()); }
        printf ("ACCEL %u\n", numGames);
        return 0;
    }
    // update: the games saved again, then the new ones
    for (uint32_t i = 0; i < e.n; i++) {
        if (idx.FetchEntry(i)->GetOffset() >= e.fin) { liste.push_back (i); }
    }
    for (uint32_t i = e.n; i < numGames; i++) { liste.push_back (i); }
    if (!liste.empty()) {
        sigs.assign (SIA_TAILLE * liste.size(), 0);
        siaCalculer (&idx, base.c_str(), &liste[0], (uint32_t) liste.size(), &sigs[0], 0, (uint32_t) liste.size());
        FILE * f = fopen (chemin.c_str(), "r+b");
        if (!f) { erreur ("writing ", chemin.c_str()); }
        bool ok = true;
        for (size_t k = 0; k < liste.size() && ok; k++) {
            ok = fseek (f, (long) (sizeof (siaEnteteT) + SIA_TAILLE * (size_t) liste[k]), SEEK_SET) == 0
                 && fwrite (&sigs[SIA_TAILLE * k], SIA_TAILLE, 1, f) == 1;
        }
        if (ok) {
            e.n = numGames;
            e.echantillon = siaEchantillonIdx (&idx, numGames);
            e.fin = siaFinIdx (&idx, numGames);
            ok = fseek (f, 0, SEEK_SET) == 0 && fwrite (&e, sizeof (e), 1, f) == 1;
        }
        if (fclose (f) != 0) { ok = false; }
        if (!ok) { erreur ("writing ", chemin.c_str()); }
    }
    printf ("ACCEL %u\n", (unsigned) liste.size());
    return 0;
}

int
main (int argc, char ** argv)
{
    uint32_t plies = 40;
    int seuilDemande = 0;
    int K = 10;
    bool siPerime = false;
    bool avecNsb = true, avecNsp = true;
    int cadence = 0;
    const char * nomBase = NULL;
    // --sha256 file: SHA-256 of a (large) file, in a separate process so that
    // Siby is not blocked (complete Gaby download)
    if (argc == 3 && !strcmp (argv[1], "--sha256")) {
        FILE * fp = fopen (argv[2], "rb");
        if (!fp) { erreur ("opening ", argv[2]); }
        Sha256 sh;
        std::vector<unsigned char> tampon (1 << 20);
        size_t n;
        while ((n = fread (&tampon[0], 1, tampon.size(), fp)) > 0) { sh.ajouter (&tampon[0], n); }
        fclose (fp);
        printf ("SHA256 %s\n", sh.fin().c_str());
        return 0;
    }
    if (argc == 3 && !strcmp (argv[1], "--accel")) {
        std::string b = argv[2];
        if (b.size() > 4 && b.compare (b.size() - 4, 4, ".si4") == 0) { b.resize (b.size() - 4); }
        return construireSia (b);
    }
    for (int a = 1; a < argc; a++) {
        if (!strcmp (argv[a], "--profondeur") && a + 1 < argc) { plies = atoi (argv[++a]); }
        else if (!strcmp (argv[a], "--seuil") && a + 1 < argc) { seuilDemande = atoi (argv[++a]); }
        else if (!strcmp (argv[a], "--meilleures") && a + 1 < argc) { K = atoi (argv[++a]); }
        else if (!strcmp (argv[a], "--si-perime")) { siPerime = true; }
        else if (!strcmp (argv[a], "--sans-positions")) { avecNsp = false; }
        else if (!strcmp (argv[a], "--positions-seulement")) { avecNsb = false; }
        else if (!strcmp (argv[a], "--cadence") && a + 1 < argc) { cadence = atoi (argv[++a]); }
        else if (argv[a][0] == '-') {
            printf ("Usage: sbbiblio [--profondeur N] [--seuil N] [--meilleures N] [--si-perime] [--sans-positions|--positions-seulement] [--cadence N] base[.si4]\n");
            return 1;
        } else { nomBase = argv[a]; }
    }
    if (!nomBase) {
        printf ("Usage: sbbiblio [--profondeur N] [--seuil N] [--meilleures N] [--si-perime] [--sans-positions|--positions-seulement] [--cadence N] base[.si4]\n");
        return 1;
    }
    if (plies < 2) { plies = 2; }
    if (plies > 200) { plies = 200; }
    if (K < 0) { K = 0; }
    if (K > 200) { K = 200; }

    std::string base = nomBase;
    if (base.size() > 4 && base.compare (base.size() - 4, 4, ".si4") == 0) {
        base.resize (base.size() - 4);
    }
    sibyMigrerFichiers (base);
    if (cadence && !nsbNomCadence (cadence)) { erreur ("--cadence: 1, 2 or 3"); }
    if (cadence) { avecNsp = false; }
    // (the files written: base.sbl…, or base.classical.sbl… for a time control)
    std::string racine = cadence ? base + "." + nsbNomCadence (cadence) : base;
    std::string fichier = racine + ".sbl";
    std::string fichierEnLigne = racine + ".online.sbl";
    std::string fichierAjouts = racine + ".ajouts.sbl";
    std::string fichierAjoutsEnLigne = racine + ".ajouts.online.sbl";

    Index idx;
    idx.SetFileName (base.c_str());
    if (idx.OpenIndexFile (FMODE_ReadOnly) != OK) { erreur ("opening the index ", (base + ".si4").c_str()); }
    GFile gf;
    if (gf.Open (base.c_str(), FMODE_ReadOnly) != OK) { erreur ("opening the games file ", (base + ".sg4").c_str()); }
    uint32_t numGames = idx.GetNumGames();
    // custom flag 5 named "En ligne" / "Online": online games kept apart
    bool separer = false;
    {
        char desc [CUSTOM_FLAG_DESC_LENGTH + 1];
        idx.GetCustomFlagDesc (desc, NSB_FLAG_EN_LIGNE);
        separer = nsbDrapeauEnLigne (desc);
    }
    // (a time control: the threshold from its own number of games)
    uint32_t nLus = numGames;
    if (cadence && avecNsb) {
        nLus = 0;
        std::vector<IndexEntry> b (65536);
        for (uint32_t d = 0; d < numGames; d += 65536) {
            uint32_t n = std::min<uint32_t> (65536, numGames - d);
            if (idx.ReadEntries (&b[0], d, n) != OK) { erreur ("reading the index"); }
            for (uint32_t k = 0; k < n; k++) { if (b[k].GetCustomFlag (cadence)) { nLus++; } }
        }
    }
    uint32_t seuil = seuilDemande > 0 ? seuilDemande : std::max<uint32_t> (5, nLus / 200000);

    auto lireEntree = [&] (uint32_t i) -> uint64_t {
        IndexEntry ie;
        if (idx.ReadEntries (&ie, i, 1) != OK) { return 0; }
        return valeurEmpreinte (&ie);
    };
    uint64_t empreinte = nsbEmpreinte (numGames, lireEntree);

    if (!avecNsb) {
        construireNsp (idx, gf, base, siPerime);
        return 0;
    }

    // Games read: [premier, numGames); additions: only the new games
    uint32_t premier = 0;
    bool ajouts = false;
    uint64_t empreintePrincipale = empreinte;
    if (siPerime) {
        NsbHeader h;
        NsbHeader h2;
        uint32_t contenu = separer ? NSB_CONTENU_ECHIQUIER : NSB_CONTENU_TOUT;
        bool principale = NsbLecteur::entete (fichier.c_str(), &h)
            && h.numGames <= numGames && h.plies == plies && (int) h.maxBest == K
            && h.reserve[NSB_RES_CONTENU] == contenu
            && (!separer || (NsbLecteur::entete (fichierEnLigne.c_str(), &h2) && h2.numGames == h.numGames
                             && h2.empreinte == h.empreinte));
        if (principale && h.numGames == numGames && h.empreinte == empreinte && h.seuil == seuil) {
            siby_remove (fichierAjouts.c_str());
            siby_remove (fichierAjoutsEnLigne.c_str());
            printf ("A_JOUR %u\n", numGames);
            fflush (stdout);
            if (avecNsp) { construireNsp (idx, gf, base, siPerime); }
            return 0;
        }
        if (principale && h.numGames < numGames && h.numGames > 0
            && nsbEmpreinte (h.numGames, lireEntree) == h.empreinte
            && numGames - h.numGames <= std::max<uint32_t> (5000, h.numGames / 5)) {
            // additions already up to date?
            NsbHeader ha, ha2;
            if (NsbLecteur::entete (fichierAjouts.c_str(), &ha) && ha.numGames == numGames
                && ha.reserve[NSB_RES_DEBUT] == h.numGames && ha.empreinte == h.empreinte
                && (((uint64_t) ha.reserve[NSB_RES_EMPR_HI] << 32) | ha.reserve[NSB_RES_EMPR_LO]) == empreinte
                && (!separer || (NsbLecteur::entete (fichierAjoutsEnLigne.c_str(), &ha2)
                                 && ha2.numGames == numGames && ha2.reserve[NSB_RES_DEBUT] == h.numGames))) {
                printf ("A_JOUR %u\n", numGames);
                fflush (stdout);
                if (avecNsp) { construireNsp (idx, gf, base, siPerime); }
                return 0;
            }
            ajouts = true;
            premier = h.numGames;
            seuil = h.seuil;
            empreintePrincipale = h.empreinte;
        }
    }
    // Siby reads this line: a complete rebuild says why (shown and logged:
    // a daily Gaby update rebuilt a 13-million-game library for 15 min,
    // Yosha 2026-11-07, and nothing said why)
    if (ajouts) {
        printf ("MODE AJOUTS %u %u\n", premier, numGames);
    } else {
        const char * raison = "demande";
        if (siPerime) {
            NsbHeader h;
            if (! NsbLecteur::entete (fichier.c_str(), &h)) { raison = "absente"; }
            else if (h.plies != plies || (int) h.maxBest != K) { raison = "parametres"; }
            else if (h.reserve[NSB_RES_CONTENU] != (separer ? NSB_CONTENU_ECHIQUIER : NSB_CONTENU_TOUT)) { raison = "contenu"; }
            else if (h.numGames > numGames) { raison = "moins-de-parties"; }
            else if (separer && ! NsbLecteur::entete (fichierEnLigne.c_str(), &h)) { raison = "en-ligne-absente"; }
            else {
                NsbHeader h1;
                NsbLecteur::entete (fichier.c_str(), &h1);
                if (separer && (h.numGames != h1.numGames || h.empreinte != h1.empreinte)) { raison = "en-ligne-differente"; }
                else if (h1.numGames == numGames) { raison = "seuil-ou-empreinte"; }
                else if (h1.numGames == 0 || nsbEmpreinte (h1.numGames, lireEntree) != h1.empreinte) { raison = "empreinte"; }
                else { raison = "trop-de-nouvelles"; }
            }
        }
        printf ("MODE COMPLET %s %u\n", raison, numGames);
    }
    fflush (stdout);
    if (!ajouts) {
        // (complete library: earlier additions no longer apply)
        siby_remove (fichierAjouts.c_str());
        siby_remove (fichierAjoutsEnLigne.c_str());
    }

    time_t debut = time (NULL);
    ByteBuffer bbuf;
    bbuf.SetBufferSize (BBUF_SIZE);
    Game * g = new Game;
    const uint32_t BLOC = 65536;
    std::vector<IndexEntry> bloc (BLOC);
    std::vector<uint64_t> clesPartie;
    std::vector<uint32_t> coupsPartie;
    std::vector<uint8_t> traitPartie;

    // Reads the first moves of game i; false if unreadable
    auto lirePartie = [&] (IndexEntry * ie) -> bool {
        clesPartie.clear();
        coupsPartie.clear();
        traitPartie.clear();
        if (ie->GetLength() == 0) { return false; }
        bbuf.Empty();
        if (gf.ReadGame (&bbuf, ie->GetOffset(), ie->GetLength()) != OK) { return false; }
        g->Clear();
        if (g->DecodeStart (&bbuf) != OK) { return false; }
        g->SetKeepDecodedMoves (false);
        simpleMoveT sm;
        for (uint32_t p = 0; p < plies; p++) {
            Position * pos = g->GetCurrentPos();
            uint64_t key = nsbCle (pos->GetBoard(), pos->GetToMove());
            uint8_t trait = pos->GetToMove();   // (before the move: pos gets modified)
            if (g->DecodeNextMove (&bbuf, &sm) != OK) { break; }
            if (isNullMove (&sm)) { break; }
            // a position repeated in the game counts only once
            bool deja = false;
            for (size_t q = 0; q < clesPartie.size(); q++) { if (clesPartie[q] == key) { deja = true; break; } }
            if (deja) { continue; }
            clesPartie.push_back (key);
            coupsPartie.push_back ((uint32_t) sm.from | ((uint32_t) sm.to << 8)
                                   | ((uint32_t) sm.promote << 16) | (1U << 24));
            traitPartie.push_back (trait);
        }
        return true;
    };

    // 1. Approximate frequency of the positions (not for the additions:
    // every position of the new games is kept)
    Esquisse esquisse (ajouts ? 4 : (numGames > 4000000 ? 27 : 25));
    for (uint32_t debutBloc = premier; !ajouts && debutBloc < numGames; debutBloc += BLOC) {
        uint32_t n = std::min (BLOC, numGames - debutBloc);
        if (idx.ReadEntries (&bloc[0], debutBloc, n) != OK) { erreur ("reading the index"); }
        for (uint32_t k = 0; k < n; k++) {
            if (cadence && !bloc[k].GetCustomFlag (cadence)) { continue; }
            if (!lirePartie (&bloc[k])) { continue; }
            for (size_t q = 0; q < clesPartie.size(); q++) { esquisse.ajouter (clesPartie[q]); }
        }
        printf ("PROGRES 1 %u %u\n", debutBloc + n, numGames);
        fflush (stdout);
    }

    // 2. Move statistics of the frequent positions, best games. A database
    // whose custom flag 5 is named "En ligne" / "Online" (Gaby: official
    // online tournaments) gets two libraries: base.sbl for the games played
    // over the board, base.online.sbl for the online games; Siby adds them
    // up when online games are included.
    // Games without ratings rank with the players' estimated ratings
    // (base.sbc, as in Siby's live ranking), so the classics before the
    // Elo era are among the top games. Only the players of such games are
    // read from the file.
    std::vector<std::vector<SbcLigne> > estimes;
    NameBase nb;
    bool avecEstimes = false;
    {
        FILE * fs = fopen ((base + ".sbc").c_str(), "rb");
        nb.SetFileName (base.c_str());
        if (fs && nb.ReadNameFile() == OK) {
            uint32_t nJ = nb.GetNumNames (NAME_PLAYER);
            std::vector<char> besoin (nJ, 0);
            for (uint32_t debutBloc = premier; debutBloc < numGames; debutBloc += BLOC) {
                uint32_t n = std::min (BLOC, numGames - debutBloc);
                if (idx.ReadEntries (&bloc[0], debutBloc, n) != OK) { erreur ("reading the index"); }
                for (uint32_t k = 0; k < n; k++) {
                    IndexEntry * ie = &bloc[k];
                    if (ie->GetWhiteElo() == 0 && ie->GetWhite() < nJ) { besoin[ie->GetWhite()] = 1; }
                    if (ie->GetBlackElo() == 0 && ie->GetBlack() < nJ) { besoin[ie->GetBlack()] = 1; }
                }
            }
            std::unordered_map<std::string, uint32_t> ids;
            for (uint32_t p = 0; p < nJ; p++) {
                if (besoin[p]) { ids[nb.GetName (NAME_PLAYER, p)] = p; }
            }
            estimes.resize (nJ);
            char ligne [1024];
            while (fgets (ligne, sizeof ligne, fs)) {
                const char * nom = NULL;
                SbcLigne l;
                if (!sbcLireLigne (ligne, &nom, &l)) { continue; }
                auto it = ids.find (nom);
                if (it != ids.end()) { estimes[it->second].push_back (l); }
            }
            avecEstimes = !ids.empty();
        }
        if (fs) { fclose (fs); }
    }
    auto eloEstime = [&] (IndexEntry * ie, idNumberT joueur) -> eloT {
        if (!avecEstimes || joueur >= estimes.size() || estimes[joueur].empty()) { return 0; }
        int cad = nsbCadence (nb.GetName (NAME_EVENT, ie->GetEvent()), separer, separer && ie->GetCustomFlag (2),
                              separer && ie->GetCustomFlag (3), separer && ie->GetCustomFlag (4),
                              separer && ie->GetCustomFlag (5));
        return (eloT) sbcEstimer (estimes[joueur], (int) ie->GetYear(), cad);
    };

    TableCoups coups, coupsEnLigne;
    TableMeilleures meilleures (K), meilleuresEnLigne (K);
    // (reference year of the top games' rank: this year)
    uint32_t anneeRef = 2026, moisRef = 1;
    { time_t t = time (NULL); struct tm * lt = localtime (&t); if (lt) { anneeRef = 1900 + lt->tm_year; moisRef = 1 + lt->tm_mon; } }
    for (uint32_t debutBloc = premier; debutBloc < numGames; debutBloc += BLOC) {
        uint32_t n = std::min (BLOC, numGames - debutBloc);
        if (idx.ReadEntries (&bloc[0], debutBloc, n) != OK) { erreur ("reading the index"); }
        for (uint32_t k = 0; k < n; k++) {
            IndexEntry * ie = &bloc[k];
            if (cadence && !ie->GetCustomFlag (cadence)) { continue; }
            if (!lirePartie (ie)) { continue; }
            bool enLigne = separer && ie->GetCustomFlag (NSB_FLAG_EN_LIGNE);
            TableCoups & tc = enLigne ? coupsEnLigne : coups;
            TableMeilleures & tm = enLigne ? meilleuresEnLigne : meilleures;
            uint32_t gnum = debutBloc + k;
            eloT we = ie->GetWhiteElo(), be = ie->GetBlackElo();
            uint32_t annee = ie->GetYear();
            uint32_t date = ie->GetDate();
            resultT res = ie->GetResult();
            // (the rank only: the move statistics keep the games' own ratings)
            eloT weTop = we ? we : eloEstime (ie, ie->GetWhite());
            eloT beTop = be ? be : eloEstime (ie, ie->GetBlack());
            // (Gaby: blitz, rapid and online games behind, nsbMalusTop)
            uint32_t malus = separer ? nsbMalusTop (ie->GetCustomFlag (2), ie->GetCustomFlag (3), ie->GetCustomFlag (4), ie->GetCustomFlag (5)) : 0;
            uint64_t valeur = ((uint64_t) nsbScoreTopCadence (weTop, beTop, annee, date_GetMonth (date), anneeRef, moisRef, malus) << 32) | (uint32_t) ~gnum;
            for (size_t q = 0; q < clesPartie.size(); q++) {
                uint64_t key = clesPartie[q];
                if (!ajouts && esquisse.estimer (key) < seuil) { continue; }
                NsbMove & st = tc.obtenir (key, coupsPartie[q]);
                st.total++;
                if (res < 4) { st.freq[res]++; }
                // Elo of the player making the move, and of the opponent (perf)
                eloT elo = traitPartie[q] == WHITE ? we : be;
                eloT opp = traitPartie[q] == WHITE ? be : we;
                if (elo > 0) { st.eloSum += elo; st.eloCount++; }
                if (opp > 0) { st.perfSum += opp; st.perfCount++; }
                if (annee) { st.yearSum += annee; st.yearCount++; }
                if (date > st.lastDate) { st.lastDate = date; }
                tm.ajouter (key, valeur);
            }
        }
        printf ("PROGRES 2 %u %u\n", debutBloc + n, numGames);
        fflush (stdout);
    }
    esquisse.r1.clear(); esquisse.r1.shrink_to_fit();
    esquisse.r2.clear(); esquisse.r2.shrink_to_fit();

    // 3. Sort by position; a position is kept (in both files) if all its
    // games together reach the threshold
    auto trier = [] (TableCoups & tc) {
        std::vector<EntreeCoup *> l;
        l.reserve (tc.n);
        for (size_t i = 0; i < tc.t.size(); i++) { if (tc.t[i].mv) { l.push_back (&tc.t[i]); } }
        std::sort (l.begin(), l.end(), [] (const EntreeCoup * a, const EntreeCoup * b) {
            if (a->key != b->key) { return a->key < b->key; }
            return a->st.total > b->st.total;
        });
        return l;
    };
    std::vector<EntreeCoup *> liste = trier (coups);
    std::vector<EntreeCoup *> listeEnLigne = trier (coupsEnLigne);

    struct Sortie {
        std::string fichier, temporaire, tmpCoups;
        FILE * f = NULL, * fc = NULL;
        std::vector<NsbPos> positions;
        std::vector<uint32_t> best;
        uint64_t nCoups = 0;
    };
    auto ouvrir = [&] (Sortie & s, const std::string & nom) {
        s.fichier = nom;
        s.temporaire = nom + ".tmp";
        s.tmpCoups = s.temporaire + ".coups";
        s.f = fopen (s.temporaire.c_str(), "wb");
        if (!s.f) { erreur ("writing ", s.temporaire.c_str()); }
        NsbHeader h0;
        memset (&h0, 0, sizeof h0);
        fwrite (&h0, sizeof h0, 1, s.f);
        // the moves are written to a second temporary file, then
        // copied after the position table
        s.fc = fopen (s.tmpCoups.c_str(), "wb");
        if (!s.fc) { erreur ("writing ", s.tmpCoups.c_str()); }
    };
    std::vector<uint64_t> tampon (K > 0 ? K : 1);
    // writes the moves l[i..j) of position key (possibly none)
    auto ecrirePos = [&] (Sortie & s, std::vector<EntreeCoup *> & l, size_t i, size_t j,
                          uint64_t key, TableMeilleures & tm) {
        if (i == j) { return; }
        NsbPos p;
        memset (&p, 0, sizeof p);
        p.key = key;
        p.firstMove = (uint32_t) s.nCoups;
        size_t nm = std::min<size_t> (j - i, 60);
        p.nMoves = (uint16_t) nm;
        for (size_t q = i; q < i + nm; q++) { fwrite (&l[q]->st, sizeof (NsbMove), 1, s.fc); }
        s.nCoups += nm;
        p.firstBest = (uint32_t) s.best.size();
        int nb = tm.lire (key, &tampon[0]);
        for (int q = 0; q < nb; q++) { s.best.push_back (~(uint32_t) (tampon[q] & 0xFFFFFFFFULL)); }
        p.nBest = (uint16_t) nb;
        s.positions.push_back (p);
    };
    auto fermer = [&] (Sortie & s, uint32_t contenu) {
        fclose (s.fc);
        if (!s.positions.empty()) { fwrite (&s.positions[0], sizeof (NsbPos), s.positions.size(), s.f); }
        s.fc = fopen (s.tmpCoups.c_str(), "rb");
        if (s.fc) {
            std::vector<char> b (1 << 20);
            size_t lu;
            while ((lu = fread (&b[0], 1, b.size(), s.fc)) > 0) { fwrite (&b[0], 1, lu, s.f); }
            fclose (s.fc);
        }
        siby_remove (s.tmpCoups.c_str());
        if (!s.best.empty()) { fwrite (&s.best[0], 4, s.best.size(), s.f); }
        NsbHeader h;
        memset (&h, 0, sizeof h);
        h.magic = NSB_MAGIC;
        h.version = NSB_VERSION;
        h.numGames = numGames;
        h.plies = plies;
        h.seuil = seuil;
        h.maxBest = K;
        h.empreinte = empreintePrincipale;
        if (ajouts) {
            h.reserve[NSB_RES_DEBUT] = premier;
            h.reserve[NSB_RES_EMPR_LO] = (uint32_t) (empreinte & 0xFFFFFFFFULL);
            h.reserve[NSB_RES_EMPR_HI] = (uint32_t) (empreinte >> 32);
        }
        h.numPos = s.positions.size();
        h.numMoves = s.nCoups;
        h.numBest = s.best.size();
        h.date = (uint64_t) time (NULL);
        h.reserve[NSB_RES_CONTENU] = contenu;
        fseek (s.f, 0, SEEK_SET);
        fwrite (&h, sizeof h, 1, s.f);
        if (fclose (s.f) != 0) { erreur ("writing ", s.temporaire.c_str()); }
        siby_remove (s.fichier.c_str());
        if (siby_rename (s.temporaire.c_str(), s.fichier.c_str()) != 0) { erreur ("replacing ", s.fichier.c_str()); }
    };

    Sortie principale, enLigne;
    ouvrir (principale, ajouts ? fichierAjouts : fichier);
    if (separer) { ouvrir (enLigne, ajouts ? fichierAjoutsEnLigne : fichierEnLigne); }
    size_t i = 0, i2 = 0;
    while (i < liste.size() || i2 < listeEnLigne.size()) {
        uint64_t key;
        if (i2 >= listeEnLigne.size() || (i < liste.size() && liste[i]->key <= listeEnLigne[i2]->key)) {
            key = liste[i]->key;
        } else {
            key = listeEnLigne[i2]->key;
        }
        size_t j = i, j2 = i2;
        uint64_t total = 0;
        while (j < liste.size() && liste[j]->key == key) { total += liste[j]->st.total; j++; }
        while (j2 < listeEnLigne.size() && listeEnLigne[j2]->key == key) { total += listeEnLigne[j2]->st.total; j2++; }
        if (ajouts || total >= seuil) {
            ecrirePos (principale, liste, i, j, key, meilleures);
            if (separer) { ecrirePos (enLigne, listeEnLigne, i2, j2, key, meilleuresEnLigne); }
        }
        i = j;
        i2 = j2;
    }
    fermer (principale, separer ? NSB_CONTENU_ECHIQUIER : NSB_CONTENU_TOUT);
    if (separer) {
        fermer (enLigne, NSB_CONTENU_EN_LIGNE);
    } else if (!ajouts) {
        siby_remove (fichierEnLigne.c_str());
    }
    uint64_t nPos = principale.positions.size() + enLigne.positions.size();
    uint64_t nCoups = principale.nCoups + enLigne.nCoups;
    std::vector<EntreeCoup *> & positions = liste;   // (for the message below)
    (void) positions;
    printf ("%s %llu %llu %ld\n", ajouts ? "AJOUTS" : "OK", (unsigned long long) nPos, (unsigned long long) nCoups,
            (long) (time (NULL) - debut));
    fflush (stdout);
    if (avecNsp) { construireNsp (idx, gf, base, siPerime); }
    return 0;
}
