//////////////////////////////////////////////////////////////////////
//
//  Siby: local probing of Syzygy tablebases (via Fathom, MIT).
//
//  Tcl command:
//    sc_syzygy init <paths>      loads the tables (folders separated by ":"),
//                                returns the largest number of pieces covered
//    sc_syzygy largest           largest number of pieces (0 = nothing loaded)
//    sc_syzygy probe <fen>       result for the side to move:
//        {wdl dtz bestMove {{move wdl dtz} ...}}
//      wdl: win, cursed-win, draw, blessed-loss, loss (or mate / stalemate)
//      dtz: distance to the next "zeroing" move (capture or pawn move), in
//           plies; moves in UCI notation (e2e4, e7e8q).
//      Returns an empty list if the position is not covered (too many
//      pieces, castling still possible, tables missing).
//
//////////////////////////////////////////////////////////////////////

#include <tcl.h>
#include <string.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include "fathom/tbprobe.h"

static const char * wdlName (unsigned wdl)
{
    switch (wdl) {
    case TB_LOSS:         return "loss";
    case TB_BLESSED_LOSS: return "blessed-loss";
    case TB_DRAW:         return "draw";
    case TB_CURSED_WIN:   return "cursed-win";
    case TB_WIN:          return "win";
    }
    return "?";
}

static void uciMove (unsigned res, char * out)
{
    unsigned from = TB_GET_FROM (res);
    unsigned to = TB_GET_TO (res);
    out[0] = 'a' + (from & 7);
    out[1] = '1' + (from >> 3);
    out[2] = 'a' + (to & 7);
    out[3] = '1' + (to >> 3);
    out[4] = 0;
    switch (TB_GET_PROMOTES (res)) {
    case TB_PROMOTES_QUEEN:  out[4] = 'q'; out[5] = 0; break;
    case TB_PROMOTES_ROOK:   out[4] = 'r'; out[5] = 0; break;
    case TB_PROMOTES_BISHOP: out[4] = 'b'; out[5] = 0; break;
    case TB_PROMOTES_KNIGHT: out[4] = 'n'; out[5] = 0; break;
    }
}

// FEN -> bitboards (a1 = 0, h8 = 63). Returns false if the FEN is invalid.
static bool parseFen (const char * fen, uint64_t * white, uint64_t * black,
                      uint64_t * kings, uint64_t * queens, uint64_t * rooks,
                      uint64_t * bishops, uint64_t * knights, uint64_t * pawns,
                      unsigned * rule50, unsigned * castling, unsigned * ep, bool * turn)
{
    *white = *black = *kings = *queens = *rooks = *bishops = *knights = *pawns = 0;
    int rank = 7, file = 0;
    const char * p = fen;
    for (; *p && *p != ' '; p++) {
        char c = *p;
        if (c == '/') { rank--; file = 0; continue; }
        if (c >= '1' && c <= '8') { file += c - '0'; continue; }
        if (rank < 0 || file > 7) { return false; }
        uint64_t b = (uint64_t)1 << (rank * 8 + file);
        bool isWhite = (c >= 'A' && c <= 'Z');
        if (isWhite) { *white |= b; } else { *black |= b; }
        switch (c | 0x20) {
        case 'k': *kings |= b; break;
        case 'q': *queens |= b; break;
        case 'r': *rooks |= b; break;
        case 'b': *bishops |= b; break;
        case 'n': *knights |= b; break;
        case 'p': *pawns |= b; break;
        default: return false;
        }
        file++;
    }
    if (*p != ' ') { return false; }
    p++;
    *turn = (*p == 'w');
    while (*p && *p != ' ') { p++; }
    if (*p == ' ') { p++; }
    *castling = 0;
    for (; *p && *p != ' '; p++) {
        if (*p != '-') { *castling = 1; }
    }
    if (*p == ' ') { p++; }
    *ep = 0;
    if (p[0] >= 'a' && p[0] <= 'h' && p[1] >= '1' && p[1] <= '8') {
        *ep = (p[1] - '1') * 8 + (p[0] - 'a');
    }
    while (*p && *p != ' ') { p++; }
    *rule50 = 0;
    if (*p == ' ') { *rule50 = (unsigned) atoi (p + 1); }
    return true;
}

int
sc_syzygy (ClientData, Tcl_Interp * ti, int argc, const char ** argv)
{
    const char * usage = "Usage: sc_syzygy init <paths> | largest | probe <fen>";
    if (argc < 2) {
        Tcl_SetResult (ti, (char *) usage, TCL_STATIC);
        return TCL_ERROR;
    }
    char temp [64];
    if (strcmp (argv[1], "init") == 0 && argc == 3) {
        tb_init (argv[2]);
        sprintf (temp, "%u", TB_LARGEST);
        Tcl_SetResult (ti, temp, TCL_VOLATILE);
        return TCL_OK;
    }
    if (strcmp (argv[1], "largest") == 0) {
        sprintf (temp, "%u", TB_LARGEST);
        Tcl_SetResult (ti, temp, TCL_VOLATILE);
        return TCL_OK;
    }
    if (strcmp (argv[1], "probe") == 0 && argc == 3) {
        if (TB_LARGEST == 0) { return TCL_OK; }
        uint64_t w, b, k, q, r, bi, n, pa;
        unsigned rule50, castling, ep;
        bool turn;
        if (!parseFen (argv[2], &w, &b, &k, &q, &r, &bi, &n, &pa, &rule50, &castling, &ep, &turn)) {
            Tcl_SetResult (ti, (char *) "Invalid FEN", TCL_STATIC);
            return TCL_ERROR;
        }
        if ((unsigned) __builtin_popcountll (w | b) > TB_LARGEST || castling) { return TCL_OK; }
        unsigned results [TB_MAX_MOVES];
        unsigned res = tb_probe_root (w, b, k, q, r, bi, n, pa, rule50, 0, ep, turn, results);
        if (res == TB_RESULT_FAILED) { return TCL_OK; }
        if (res == TB_RESULT_CHECKMATE) { Tcl_AppendElement (ti, "mate"); return TCL_OK; }
        if (res == TB_RESULT_STALEMATE) { Tcl_AppendElement (ti, "stalemate"); return TCL_OK; }
        Tcl_AppendElement (ti, wdlName (TB_GET_WDL (res)));
        sprintf (temp, "%u", TB_GET_DTZ (res));
        Tcl_AppendElement (ti, temp);
        char mv [8];
        uciMove (res, mv);
        Tcl_AppendElement (ti, mv);
        Tcl_DString ds;
        Tcl_DStringInit (&ds);
        for (unsigned i = 0; results[i] != TB_RESULT_FAILED && i < TB_MAX_MOVES; i++) {
            Tcl_DStringStartSublist (&ds);
            uciMove (results[i], mv);
            Tcl_DStringAppendElement (&ds, mv);
            Tcl_DStringAppendElement (&ds, wdlName (TB_GET_WDL (results[i])));
            sprintf (temp, "%u", TB_GET_DTZ (results[i]));
            Tcl_DStringAppendElement (&ds, temp);
            Tcl_DStringEndSublist (&ds);
        }
        Tcl_AppendElement (ti, Tcl_DStringValue (&ds));
        Tcl_DStringFree (&ds);
        return TCL_OK;
    }
    Tcl_SetResult (ti, (char *) usage, TCL_STATIC);
    return TCL_ERROR;
}
