#ifndef PRORES_SAVER_H__
#define PRORES_SAVER_H__

#include "c4d.h"

#if API_VERSION >= 2025000
cinema::Bool RegisterProResSaver();
#else
Bool RegisterProResSaver();
#endif

#endif // PRORES_SAVER_H__
