import c4d, sys, os
from c4d import bitmaps

# Format IDs registered by the plugin (see g_formats in prores_saver.cpp).
HQ, P4444 = 1000001, 1000002
out_dir = sys.argv[-1]

for p in c4d.plugins.FilterPluginList(c4d.PLUGINTYPE_BITMAPSAVER, True):
    if 1000001 <= p.GetID() <= 1000010:
        print("format:", p.GetID(), p.GetName())


def run(pid, alpha, name, w=320, h=180, frames=24):
    bm = bitmaps.BaseBitmap()
    bm.Init(w, h, 24)
    a = bm.AddChannel(True, False) if alpha else None
    ms = bitmaps.MovieSaver()
    path = os.path.join(out_dir, name)
    savebits = c4d.SAVEBIT_ALPHA if alpha else 0
    res = ms.Open(path, bm, 24, pid, c4d.BaseContainer(), savebits)
    print(name, "open", res)
    for f in range(frames):
        for y in range(h):
            for x in range(w):
                bm.SetPixel(x, y, (x * 255) // w, (y * 255) // h, (f * 10) % 256)
                if a:
                    bm.SetAlphaPixel(a, x, y, (x * 255) // w)
        r = ms.Write(bm)
        if r != c4d.IMAGERESULT_OK:
            print("write", f, r)
            break
    print(name, "close", ms.Close())


run(HQ, False, "test_422hq.mov")
run(P4444, True, "test_4444_alpha.mov", w=200, h=120, frames=10)
run(HQ, False, "test_odd.mov", w=321, h=181, frames=3)
