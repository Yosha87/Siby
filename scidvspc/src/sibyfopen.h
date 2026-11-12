// Siby: fopen() through siby_fopen() on Windows (UTF-8 names, see common.h).
// The C++ headers (<cstdio>, pulled by <iostream>, <string>…) #undef fopen:
// included after them, this puts the redirection back. No include guard on
// purpose: it may be needed again after later includes.
#ifdef _WIN32
#undef fopen
#define fopen siby_fopen
#endif
