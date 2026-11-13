// Siby: move sounds on Windows, played as a browser does (Lichess: Web
// Audio through howler.js).
//
// PlaySound opens the sound output for each sound. On many laptops the
// sound chip sleeps between two sounds and wakes up on the next one: the
// first hundredths of a second are lost, the knock's attack with them, and
// only its dull tail is heard ("a fart rather than pieces", Yosha
// 2026-11-09, wired earphones).
//
// So the output stays open, as a browser keeps its audio stream: a thread
// of its own feeds it without a gap, 4 buffers of 20 ms, silence or the
// knock mixed in, and closes it 30 s after the last sound (howler's
// autoSuspend). The first version fed the silence from Siby's timer every
// 40 ms: whenever Siby was busy the output ran dry and started again, and
// the students' sound was cut in Zoom lessons (Yosha 2026-11-11). The
// second one closed the output after each knock: dull knocks again.
//
// Only 16-bit PCM WAV files are played this way (Siby's sounds); anything
// else returns 0 and the caller falls back on PlaySound.
// Kept apart from tkscid.cpp: <windows.h> clashes with SCID's names.

#ifdef _WIN32

#define NOMINMAX
#include <windows.h>
#include <mmsystem.h>
#include <map>
#include <string>
#include <vector>
#include <cstring>

namespace {

struct Son { std::vector<char> donnees; WAVEFORMATEX format; };

std::map<std::string, Son> sons;

const int nTampons = 4;
const int msTampon = 20;
const DWORD gardeMs = 30000;             // the output kept open this long

CRITICAL_SECTION verrou;
bool verrouPret = false;
HWAVEOUT sortie = NULL;
WAVEFORMATEX formatSortie;
HANDLE evenement = NULL;
HANDLE fil = NULL;
WAVEHDR entetes [nTampons];
std::vector<char> tampons [nTampons];
const Son * courant = NULL;              // the knock being played
size_t position = 0;
DWORD dernierSon = 0;
bool fermeture = false;                  // the thread is closing the output

bool lireWav (const char * chemin, Son & s) {
    int n = MultiByteToWideChar (CP_UTF8, 0, chemin, -1, NULL, 0);
    if (n <= 0) { return false; }
    std::vector<wchar_t> w (n);
    MultiByteToWideChar (CP_UTF8, 0, chemin, -1, w.data(), n);
    HANDLE f = CreateFileW (w.data(), GENERIC_READ, FILE_SHARE_READ, NULL, OPEN_EXISTING, 0, NULL);
    if (f == INVALID_HANDLE_VALUE) { return false; }
    std::vector<char> b;
    char tampon [65536];
    DWORD lus = 0;
    while (ReadFile (f, tampon, sizeof tampon, &lus, NULL) && lus > 0) { b.insert (b.end(), tampon, tampon + lus); }
    CloseHandle (f);
    if (b.size() < 44 || memcmp (b.data(), "RIFF", 4) != 0 || memcmp (b.data() + 8, "WAVE", 4) != 0) { return false; }
    bool aFormat = false;
    size_t i = 12;
    while (i + 8 <= b.size()) {
        DWORD t;
        memcpy (&t, b.data() + i + 4, 4);
        if (memcmp (b.data() + i, "fmt ", 4) == 0 && t >= 16 && i + 8 + 16 <= b.size()) {
            memset (&s.format, 0, sizeof s.format);
            memcpy (&s.format, b.data() + i + 8, 16);
            s.format.cbSize = 0;
            aFormat = true;
        } else if (memcmp (b.data() + i, "data", 4) == 0) {
            size_t fin = std::min (b.size(), (size_t) (i + 8 + t));
            s.donnees.assign (b.begin() + i + 8, b.begin() + fin);
            break;
        }
        i += 8 + t + (t & 1);
    }
    return aFormat && s.format.wFormatTag == WAVE_FORMAT_PCM && s.format.wBitsPerSample == 16 && ! s.donnees.empty();
}

// One buffer filled: the rest of the knock, then silence
void remplir (WAVEHDR & h) {
    char * d = h.lpData;
    size_t n = h.dwBufferLength;
    size_t k = 0;
    EnterCriticalSection (&verrou);
    if (courant != NULL) {
        size_t reste = courant->donnees.size() - position;
        k = reste < n ? reste : n;
        memcpy (d, courant->donnees.data() + position, k);
        position += k;
        if (position >= courant->donnees.size()) { courant = NULL; }
    }
    LeaveCriticalSection (&verrou);
    if (k < n) { memset (d + k, 0, n - k); }
}

// The audio thread: each buffer played comes back filled at once
DWORD WINAPI boucle (LPVOID) {
    while (true) {
        WaitForSingleObject (evenement, 100);
        for (int i = 0; i < nTampons; i++) {
            if (entetes[i].dwFlags & WHDR_DONE) {
                remplir (entetes[i]);
                waveOutWrite (sortie, &entetes[i], sizeof entetes[i]);
            }
        }
        EnterCriticalSection (&verrou);
        bool fini = (courant == NULL && GetTickCount() - dernierSon > gardeMs);
        if (fini) { fermeture = true; }
        LeaveCriticalSection (&verrou);
        if (fini) { break; }
    }
    waveOutReset (sortie);
    for (int i = 0; i < nTampons; i++) { waveOutUnprepareHeader (sortie, &entetes[i], sizeof entetes[i]); }
    waveOutClose (sortie);
    EnterCriticalSection (&verrou);
    sortie = NULL;
    LeaveCriticalSection (&verrou);
    return 0;
}

// The thread of an output closed (or closing) waited for
void attendreFil () {
    if (fil == NULL) { return; }
    EnterCriticalSection (&verrou);
    dernierSon = GetTickCount() - gardeMs - 1;
    courant = NULL;
    LeaveCriticalSection (&verrou);
    WaitForSingleObject (fil, 2000);
    CloseHandle (fil);
    fil = NULL;
}

bool ouvrir (const WAVEFORMATEX & f) {
    if (evenement == NULL) { evenement = CreateEvent (NULL, FALSE, FALSE, NULL); }
    formatSortie = f;
    if (waveOutOpen (&sortie, WAVE_MAPPER, &formatSortie, (DWORD_PTR) evenement, 0, CALLBACK_EVENT) != MMSYSERR_NOERROR) {
        sortie = NULL;
        return false;
    }
    size_t octets = (size_t) f.nAvgBytesPerSec * msTampon / 1000 / f.nBlockAlign * f.nBlockAlign;
    for (int i = 0; i < nTampons; i++) {
        tampons[i].assign (octets, 0);
        memset (&entetes[i], 0, sizeof entetes[i]);
        entetes[i].lpData = tampons[i].data();
        entetes[i].dwBufferLength = (DWORD) octets;
        waveOutPrepareHeader (sortie, &entetes[i], sizeof entetes[i]);
        waveOutWrite (sortie, &entetes[i], sizeof entetes[i]);
    }
    fil = CreateThread (NULL, 0, boucle, NULL, 0, NULL);
    if (fil == NULL) {
        waveOutReset (sortie);
        for (int i = 0; i < nTampons; i++) { waveOutUnprepareHeader (sortie, &entetes[i], sizeof entetes[i]); }
        waveOutClose (sortie);
        sortie = NULL;
        return false;
    }
    SetThreadPriority (fil, THREAD_PRIORITY_HIGHEST);
    return true;
}

} // namespace

// Plays a WAV file; 1 if played, 0 if not (the caller then uses PlaySound)
extern "C" int sibySonJouer (const char * chemin) {
    if (!verrouPret) { InitializeCriticalSection (&verrou); verrouPret = true; }
    std::string cle (chemin);
    auto it = sons.find (cle);
    if (it == sons.end()) {
        Son s;
        if (! lireWav (chemin, s)) { return 0; }
        it = sons.emplace (cle, s).first;
    }
    const Son & s = it->second;
    EnterCriticalSection (&verrou);
    bool ouverte = (sortie != NULL && !fermeture);
    bool memeFormat = ouverte && memcmp (&formatSortie, &s.format, 16) == 0;
    if (memeFormat) {
        // (the knock mixed into the running stream: no gap, no reset)
        courant = &s;
        position = 0;
        dernierSon = GetTickCount();
        LeaveCriticalSection (&verrou);
        return 1;
    }
    LeaveCriticalSection (&verrou);
    attendreFil ();
    fermeture = false;
    if (! ouvrir (s.format)) { return 0; }
    EnterCriticalSection (&verrou);
    courant = &s;
    position = 0;
    dernierSon = GetTickCount();
    LeaveCriticalSection (&verrou);
    return 1;
}

// The output is fed by its own thread: nothing for Siby to do any more
extern "C" int sibySonEntretien () {
    return 0;
}

#endif
