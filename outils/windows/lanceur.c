/* Siby launcher for Windows: Siby.exe at the top of the portable folder
   starts bin\Siby.exe (which needs its bin\ and lib\ folders) with the same
   arguments, without any console window (unlike a .bat file). */
#include <windows.h>
#include <wchar.h>

int WINAPI wWinMain(HINSTANCE h, HINSTANCE p, PWSTR args, int show) {
  wchar_t chemin[MAX_PATH], ligne[32768];
  DWORD n = GetModuleFileNameW(NULL, chemin, MAX_PATH);
  if (n == 0 || n >= MAX_PATH) return 1;
  wchar_t *s = wcsrchr(chemin, L'\\');
  if (s) *(s + 1) = 0;
  wcscat(chemin, L"bin\\Siby.exe");
  _snwprintf(ligne, 32768, L"\"%ls\" %ls", chemin, args ? args : L"");
  ligne[32767] = 0;
  STARTUPINFOW si = { sizeof si };
  PROCESS_INFORMATION pi;
  if (!CreateProcessW(chemin, ligne, NULL, NULL, FALSE, 0, NULL, NULL, &si, &pi)) {
    MessageBoxW(NULL, L"bin\\Siby.exe introuvable / not found", L"Siby", MB_ICONERROR);
    return 1;
  }
  CloseHandle(pi.hThread);
  CloseHandle(pi.hProcess);
  return 0;
}
