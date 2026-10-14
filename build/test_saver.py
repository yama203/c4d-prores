import c4d, sys, os
from c4d import bitmaps

PID = 1000001
out_dir = sys.argv[-1]
print("registered:", c4d.plugins.FindPlugin(PID, c4d.PLUGINTYPE_BITMAPSAVER))

def run(profile, alpha, name, w=320, h=180, frames=24):
    bm = bitmaps.BaseBitmap()
    bm.Init(w, h, 24)
    a = bm.AddChannel(True, False) if alpha else None
    data = c4d.BaseContainer()
    data[1000] = profile
    data[1003] = alpha
    ms = bitmaps.MovieSaver()
    path = os.path.join(out_dir, name)
    savebits = c4d.SAVEBIT_ALPHA if alpha else 0
    res = ms.Open(path, bm, 24, PID, data, savebits)
    print(name, "open", res)
    for f in range(frames):
        for y in range(h):
            for x in range(w):
                bm.SetPixel(x, y, (x * 255) // w, (y * 255) // h, (f * 10) % 256)
                if a: bm.SetAlphaPixel(a, x, y, (x * 255) // w)
        r = ms.Write(bm)
        if r != c4d.IMAGERESULT_OK:
            print("write", f, r); break
    print(name, "close", ms.Close())

run(3, False, "test_422hq.mov")
run(4, True, "test_4444_alpha.mov", w=200, h=120, frames=10)
run(3, False, "test_odd.mov", w=321, h=181, frames=3)
