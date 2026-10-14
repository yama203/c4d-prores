#include "c4d_plugin.h"
#include "c4d_resource.h"

#include "prores_saver.h"

#if API_VERSION >= 2025000
#define C4D_NS cinema::
#else
#define C4D_NS
#endif

C4D_NS Bool C4D_NS PluginStart()
{
	return RegisterProResSaver();
}

void C4D_NS PluginEnd()
{
}

C4D_NS Bool C4D_NS PluginMessage(C4D_NS Int32 id, void* data)
{
	switch (id)
	{
		case C4DPL_INIT_SYS:
			return C4D_NS g_resource.Init();
	}
	return false;
}
