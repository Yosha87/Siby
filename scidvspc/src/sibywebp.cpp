// Siby: WebP images into Tk photos (tournament covers of Lichess
// broadcasts, which Lichess serves only as WebP).
//
//   sc_webp file photo ?width height?
//
// Decodes the WebP file into the existing Tk photo image (created with
// "image create photo"), optionally scaled to width x height. Returns
// "width height" of the decoded image. Decoder: libwebp (src/webp, BSD
// licence, decoder only).

#ifndef TCL_ONLY

#include <tcl.h>
#include <tk.h>
#include <cstdio>
#include <cstdlib>
#include <vector>
#include "webp/src/webp/decode.h"

int
sc_webp (ClientData, Tcl_Interp * ti, int argc, const char ** argv)
{
    if (argc != 3 && argc != 5) {
        Tcl_AppendResult (ti, "usage: sc_webp file photo ?width height?", NULL);
        return TCL_ERROR;
    }
    Tk_PhotoHandle photo = Tk_FindPhoto (ti, argv[2]);
    if (photo == NULL) {
        Tcl_AppendResult (ti, "no photo image ", argv[2], NULL);
        return TCL_ERROR;
    }
    int largeur = 0, hauteur = 0;
    if (argc == 5) {
        largeur = atoi (argv[3]);
        hauteur = atoi (argv[4]);
    }

    // The file (read through Tcl, for non-ASCII paths on Windows)
    Tcl_Channel ch = Tcl_OpenFileChannel (ti, argv[1], "r", 0);
    if (ch == NULL) { return TCL_ERROR; }
    Tcl_SetChannelOption (ti, ch, "-translation", "binary");
    std::vector<unsigned char> donnees;
    char tampon[65536];
    int n;
    while ((n = Tcl_Read (ch, tampon, sizeof tampon)) > 0) {
        donnees.insert (donnees.end(), tampon, tampon + n);
    }
    Tcl_Close (ti, ch);
    if (donnees.empty()) {
        Tcl_AppendResult (ti, "empty file ", argv[1], NULL);
        return TCL_ERROR;
    }

    WebPDecoderConfig config;
    if (!WebPInitDecoderConfig (&config)
        || WebPGetFeatures (&donnees[0], donnees.size(), &config.input) != VP8_STATUS_OK) {
        Tcl_AppendResult (ti, "not a WebP image: ", argv[1], NULL);
        return TCL_ERROR;
    }
    if (largeur > 0 && hauteur > 0) {
        config.options.use_scaling = 1;
        config.options.scaled_width = largeur;
        config.options.scaled_height = hauteur;
    }
    config.output.colorspace = MODE_RGBA;
    if (WebPDecode (&donnees[0], donnees.size(), &config) != VP8_STATUS_OK) {
        WebPFreeDecBuffer (&config.output);
        Tcl_AppendResult (ti, "WebP decoding failed: ", argv[1], NULL);
        return TCL_ERROR;
    }
    int w = config.output.width;
    int h = config.output.height;

    Tk_PhotoImageBlock bloc;
    bloc.pixelPtr = config.output.u.RGBA.rgba;
    bloc.width = w;
    bloc.height = h;
    bloc.pitch = config.output.u.RGBA.stride;
    bloc.pixelSize = 4;
    bloc.offset[0] = 0;
    bloc.offset[1] = 1;
    bloc.offset[2] = 2;
    bloc.offset[3] = 3;
    int res = Tk_PhotoSetSize (ti, photo, w, h);
    if (res == TCL_OK) {
        res = Tk_PhotoPutBlock (ti, photo, &bloc, 0, 0, w, h, TK_PHOTO_COMPOSITE_SET);
    }
    WebPFreeDecBuffer (&config.output);
    if (res != TCL_OK) { return res; }

    char taille[64];
    snprintf (taille, sizeof taille, "%d %d", w, h);
    Tcl_SetResult (ti, taille, TCL_VOLATILE);
    return TCL_OK;
}

#endif // TCL_ONLY
