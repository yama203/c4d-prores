// ProRes movie saver for Cinema 4D (Windows).
//
// Registers "ProRes (FFmpeg)" as a movie format in the render settings. Rendered frames are piped as
// 16-bit RGB(A) raw video into an ffmpeg.exe child process, which encodes them with prores_ks.
// The same source builds against the 2024 SDK (no namespace) and the 2025+ SDK (cinema namespace).

#include "c4d.h"
#include "c4d_gui.h"
#include "c4d_filterdata.h"
#include "c4d_basebitmap.h"

#include "prores_saver.h"

#ifndef NOMINMAX
#define NOMINMAX
#endif
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>

#include <new>
#include <string>
#include <vector>

#if API_VERSION >= 2025000
using namespace cinema;
#endif

// Settings container IDs (stored by Cinema 4D with the render settings).
enum
{
	PRORES_FFMPEG_PATH = 1001,	// String, optional explicit path to ffmpeg.exe
	PRORES_NTSC_RATE = 1002,	// Bool, encode fps*1000/1001 (23.976, 29.97, 59.94)
	PRORES_KEEP_ALPHA = 1003	// Bool, write alpha for 4444 / 4444 XQ
};

enum ProResProfile
{
	PROFILE_PROXY = 0,
	PROFILE_LT = 1,
	PROFILE_422 = 2,
	PROFILE_422_HQ = 3,
	PROFILE_4444 = 4,
	PROFILE_4444_XQ = 5
};

// Each profile is registered as its own entry in the render settings' format list, so the profile is
// visible and selectable there directly (and alpha is offered only for the 4444 variants).
// TODO: Replace the IDs with unique ones from https://developers.maxon.net/forum/pid before
// distributing. 1000001-1000010 are reserved by Maxon for local testing.
struct ProResFormat
{
	Int32 id;
	Int32 profile;
	const Char* name;
};

static const ProResFormat g_formats[] = {
	{ 1000001, PROFILE_422_HQ, "ProRes 422 HQ (FFmpeg)" },
	{ 1000002, PROFILE_4444, "ProRes 4444 (FFmpeg)" },
	{ 1000003, PROFILE_4444_XQ, "ProRes 4444 XQ (FFmpeg)" },
	{ 1000004, PROFILE_422, "ProRes 422 (FFmpeg)" },
	{ 1000005, PROFILE_LT, "ProRes 422 LT (FFmpeg)" },
	{ 1000006, PROFILE_PROXY, "ProRes 422 Proxy (FFmpeg)" },
};

static Bool UsesAlpha(Int32 profile, const BaseContainer* data)
{
	return profile >= PROFILE_4444 && (data ? data->GetBool(PRORES_KEEP_ALPHA, true) : true);
}

// ------------------------------------------------------------------------------------------------
// String helpers
// ------------------------------------------------------------------------------------------------

static std::wstring ToWide(const maxon::String& str)
{
	maxon::Utf16CharBuffer buf;
	if (str.GetUtf16(buf) == maxon::FAILED)
		return std::wstring();
	return std::wstring(reinterpret_cast<const wchar_t*>(buf.GetFirst()), (size_t)buf.GetCount());
}

static maxon::String FromWide(const std::wstring& str)
{
	return maxon::String(reinterpret_cast<const maxon::Utf16Char*>(str.c_str()), (Int)str.size());
}

static Bool FileExistsW(const std::wstring& path)
{
	const DWORD attr = GetFileAttributesW(path.c_str());
	return attr != INVALID_FILE_ATTRIBUTES && !(attr & FILE_ATTRIBUTE_DIRECTORY);
}

// Quotes an argument for CreateProcess command lines.
static std::wstring Quote(const std::wstring& arg)
{
	std::wstring out = L"\"";
	for (wchar_t c : arg)
	{
		if (c == L'"')
			out += L'\\';
		out += c;
	}
	out += L'"';
	return out;
}

// Resolution order: explicit path in settings -> <plugin>/ffmpeg/ffmpeg.exe -> <plugin>/ffmpeg.exe
// -> ffmpeg.exe found on PATH.
static std::wstring FindFfmpeg(const BaseContainer* data)
{
	if (data)
	{
		const std::wstring custom = ToWide(data->GetString(PRORES_FFMPEG_PATH));
		if (!custom.empty() && FileExistsW(custom))
			return custom;
	}

	const std::wstring pluginDir = ToWide(GeGetPluginPath().GetString());
	if (!pluginDir.empty())
	{
		const std::wstring candidates[] = { pluginDir + L"\\ffmpeg\\ffmpeg.exe", pluginDir + L"\\ffmpeg.exe" };
		for (const std::wstring& c : candidates)
		{
			if (FileExistsW(c))
				return c;
		}
	}

	wchar_t found[MAX_PATH] = {};
	if (SearchPathW(nullptr, L"ffmpeg.exe", nullptr, MAX_PATH, found, nullptr) > 0)
		return found;

	return std::wstring();
}

static std::wstring LogPathFor(const std::wstring& moviePath)
{
	wchar_t tmp[MAX_PATH] = {};
	GetTempPathW(MAX_PATH, tmp);
	std::wstring base = moviePath;
	const size_t slash = base.find_last_of(L"\\/");
	if (slash != std::wstring::npos)
		base = base.substr(slash + 1);
	return std::wstring(tmp) + L"c4d_prores_" + base + L".log";
}

// ------------------------------------------------------------------------------------------------
// Movie state
// ------------------------------------------------------------------------------------------------

struct ProResMovie
{
	HANDLE process = nullptr;
	HANDLE stdinWrite = nullptr;
	Int32 width = 0;
	Int32 height = 0;
	Bool alpha = false;
	std::vector<UChar> frame;	// width * height * (3|4) * 2 bytes, little endian 16-bit
	std::wstring logPath;
	Bool failed = false;
};

static void CloseHandleSafe(HANDLE& h)
{
	if (h)
	{
		CloseHandle(h);
		h = nullptr;
	}
}

static IMAGERESULT StartFfmpeg(ProResMovie& mv, const std::wstring& ffmpeg, const std::wstring& outPath,
	Int32 profile, const BaseContainer* data, Int32 fps)
{
	const Bool ntsc = data ? data->GetBool(PRORES_NTSC_RATE, false) : false;
	if (fps <= 0)
		fps = 30;

	const std::wstring rate = ntsc ? std::to_wstring(fps * 1000) + L"/1001" : std::to_wstring(fps);
	const wchar_t* inFmt = mv.alpha ? L"rgba64le" : L"rgb48le";
	const wchar_t* outFmt = profile >= PROFILE_4444 ? (mv.alpha ? L"yuva444p10le" : L"yuv444p10le") : L"yuv422p10le";

	std::wstring cmd = Quote(ffmpeg);
	cmd += L" -hide_banner -loglevel warning -y";
	cmd += L" -f rawvideo -pix_fmt " + std::wstring(inFmt);
	cmd += L" -s " + std::to_wstring(mv.width) + L"x" + std::to_wstring(mv.height);
	cmd += L" -framerate " + rate + L" -i pipe:0";
	// Input is display-referred sRGB/Rec.709 RGB. Pad odd sizes for 4:2:2, convert with the Rec.709
	// matrix (swscale defaults to BT.601) and tag the frames so the mov 'colr' atom is written.
	cmd += L" -vf \"pad=ceil(iw/2)*2:ceil(ih/2)*2,";
	cmd += L"scale=out_color_matrix=bt709:out_range=limited,format=" + std::wstring(outFmt) + L",";
	cmd += L"setparams=color_primaries=bt709:color_trc=bt709:colorspace=bt709:range=limited\"";
	cmd += L" -c:v prores_ks -profile:v " + std::to_wstring(profile);
	cmd += L" -pix_fmt " + std::wstring(outFmt);
	if (mv.alpha)
		cmd += L" -alpha_bits 16";
	cmd += L" -vendor apl0";
	cmd += L" -color_primaries bt709 -color_trc bt709 -colorspace bt709 -color_range tv";
	cmd += L" -r " + rate;
	cmd += L" -f mov " + Quote(outPath);

	SECURITY_ATTRIBUTES sa = { sizeof(sa), nullptr, TRUE };

	HANDLE stdinRead = nullptr;
	if (!CreatePipe(&stdinRead, &mv.stdinWrite, &sa, 8 * 1024 * 1024))
		return IMAGERESULT::MISC_ERROR;
	SetHandleInformation(mv.stdinWrite, HANDLE_FLAG_INHERIT, 0);

	mv.logPath = LogPathFor(outPath);
	HANDLE logFile = CreateFileW(mv.logPath.c_str(), GENERIC_WRITE, FILE_SHARE_READ, &sa, CREATE_ALWAYS,
		FILE_ATTRIBUTE_NORMAL, nullptr);
	HANDLE nul = CreateFileW(L"NUL", GENERIC_WRITE, FILE_SHARE_WRITE, &sa, OPEN_EXISTING, 0, nullptr);

	STARTUPINFOW si = {};
	si.cb = sizeof(si);
	si.dwFlags = STARTF_USESTDHANDLES;
	si.hStdInput = stdinRead;
	si.hStdOutput = nul;
	si.hStdError = logFile != INVALID_HANDLE_VALUE ? logFile : nul;

	PROCESS_INFORMATION pi = {};
	std::vector<wchar_t> cmdBuf(cmd.begin(), cmd.end());
	cmdBuf.push_back(0);

	const BOOL ok = CreateProcessW(nullptr, cmdBuf.data(), nullptr, nullptr, TRUE,
		CREATE_NO_WINDOW | BELOW_NORMAL_PRIORITY_CLASS, nullptr, nullptr, &si, &pi);

	CloseHandle(stdinRead);
	if (logFile != INVALID_HANDLE_VALUE)
		CloseHandle(logFile);
	if (nul != INVALID_HANDLE_VALUE)
		CloseHandle(nul);

	if (!ok)
	{
		CloseHandleSafe(mv.stdinWrite);
		return IMAGERESULT::MISC_ERROR;
	}

	CloseHandle(pi.hThread);
	mv.process = pi.hProcess;
	return IMAGERESULT::OK;
}

// Waits for ffmpeg to finish and reports whether it succeeded.
static Bool FinishFfmpeg(ProResMovie& mv)
{
	CloseHandleSafe(mv.stdinWrite);
	DWORD exitCode = 1;
	if (mv.process)
	{
		WaitForSingleObject(mv.process, INFINITE);
		GetExitCodeProcess(mv.process, &exitCode);
		CloseHandleSafe(mv.process);
	}
	return exitCode == 0 && !mv.failed;
}

// ------------------------------------------------------------------------------------------------
// Settings dialog
// ------------------------------------------------------------------------------------------------

class ProResSettingsDialog : public GeModalDialog
{
	enum
	{
		IDC_ALPHA = 2000,
		IDC_NTSC,
		IDC_FFMPEG,
		IDC_FFMPEG_INFO
	};

	BaseContainer* _data;
	const ProResFormat& _format;

public:
	ProResSettingsDialog(BaseContainer* data, const ProResFormat& format) : _data(data), _format(format) { }

	virtual Bool CreateLayout()
	{
		SetTitle(maxon::String(_format.name));

		GroupBegin(0, BFH_SCALEFIT | BFV_TOP, 2, 0, String(), 0);
		GroupBorderSpace(10, 10, 10, 4);
		GroupSpace(8, 6);

		AddStaticText(0, BFH_LEFT, 0, 0, String(), 0);
		AddCheckbox(IDC_ALPHA, BFH_LEFT, 0, 0, "Write alpha (also enable Alpha Channel in Save settings)"_s);

		AddStaticText(0, BFH_LEFT, 0, 0, String(), 0);
		AddCheckbox(IDC_NTSC, BFH_LEFT, 0, 0, "NTSC rate (x 1000/1001: 23.976, 29.97, 59.94)"_s);

		AddStaticText(0, BFH_LEFT, 0, 0, "ffmpeg.exe"_s, 0);
		AddEditText(IDC_FFMPEG, BFH_SCALEFIT, 360, 0);

		AddStaticText(0, BFH_LEFT, 0, 0, String(), 0);
		AddStaticText(IDC_FFMPEG_INFO, BFH_SCALEFIT, 0, 0, String(), 0);

		GroupEnd();

		AddDlgGroup(DLG_OK | DLG_CANCEL);
		return true;
	}

	virtual Bool InitValues()
	{
		SetBool(IDC_ALPHA, _data->GetBool(PRORES_KEEP_ALPHA, true));
		SetBool(IDC_NTSC, _data->GetBool(PRORES_NTSC_RATE, false));
		SetString(IDC_FFMPEG, _data->GetString(PRORES_FFMPEG_PATH));
		UpdateInfo();
		return true;
	}

	virtual Bool Command(Int32 id, const BaseContainer& msg)
	{
		if (id == IDC_FFMPEG)
			UpdateInfo();
		return true;
	}

	virtual Bool AskClose()
	{
		Bool alpha = true, ntsc = false;
		maxon::String path;
		GetBool(IDC_ALPHA, alpha);
		GetBool(IDC_NTSC, ntsc);
		GetString(IDC_FFMPEG, path);

		_data->SetBool(PRORES_KEEP_ALPHA, alpha);
		_data->SetBool(PRORES_NTSC_RATE, ntsc);
		_data->SetString(PRORES_FFMPEG_PATH, path);
		return false;	// allow closing
	}

private:
	void UpdateInfo()
	{
		Enable(IDC_ALPHA, _format.profile >= PROFILE_4444);

		maxon::String path;
		GetString(IDC_FFMPEG, path);
		BaseContainer tmp;
		tmp.SetString(PRORES_FFMPEG_PATH, path);
		const std::wstring found = FindFfmpeg(&tmp);
		SetString(IDC_FFMPEG_INFO, found.empty() ? "ffmpeg.exe not found"_s : "Using: "_s + FromWide(found));
	}
};

// ------------------------------------------------------------------------------------------------
// Saver
// ------------------------------------------------------------------------------------------------

class ProResSaver : public BitmapSaverData
{
	const ProResFormat* _format = nullptr;

public:
	static ProResSaver* Alloc(const ProResFormat& format)
	{
		ProResSaver* saver = NewObjClear(ProResSaver);
		if (saver)
			saver->_format = &format;
		return saver;
	}

	virtual IMAGERESULT Save(const Filename& name, BaseBitmap* bm, BaseContainer* data, SAVEBIT savebits)
	{
		// A single still frame written as a one-frame movie.
		PluginMovieData* md = nullptr;
		IMAGERESULT res = Open(md, name, bm, data, savebits, 30);
		if (res != IMAGERESULT::OK)
			return res;
		res = Write(md, bm);
		const IMAGERESULT closeRes = Close(md);
		return res != IMAGERESULT::OK ? res : closeRes;
	}

	virtual Bool Edit(BaseContainer* data)
	{
		if (!data)
			return false;
		ProResSettingsDialog dlg(data, *_format);
		return dlg.Open(-1, -1, 480, 0) && dlg.GetResult();
	}

	virtual Int32 GetMaxAlphas(BaseContainer* data)
	{
		return UsesAlpha(_format->profile, data) ? 1 : 0;
	}

	virtual Int32 GetMaxResolution(Bool layers)
	{
		return 16384;
	}

	virtual IMAGERESULT Open(PluginMovieData*& md, const Filename& name, BaseBitmap* bm, BaseContainer* data,
		SAVEBIT savebits, Int32 fps)
	{
		md = nullptr;
		if (!bm)
			return IMAGERESULT::PARAM_ERROR;

		const std::wstring ffmpeg = FindFfmpeg(data);
		if (ffmpeg.empty())
		{
			GePrint("ProRes: ffmpeg.exe not found. Put it in the plugin folder or set the path in the format options."_s);
			return IMAGERESULT::MISC_ERROR;
		}

		ProResMovie* mv = new (std::nothrow) ProResMovie();
		if (!mv)
			return IMAGERESULT::OUTOFMEMORY;

		mv->width = bm->GetBw();
		mv->height = bm->GetBh();
		mv->alpha = UsesAlpha(_format->profile, data) && (savebits & SAVEBIT::ALPHA) != SAVEBIT::NONE;
		mv->frame.resize((size_t)mv->width * (size_t)mv->height * (mv->alpha ? 4 : 3) * 2);

		const IMAGERESULT res = StartFfmpeg(*mv, ffmpeg, ToWide(name.GetString()), _format->profile, data, fps);
		if (res != IMAGERESULT::OK)
		{
			GePrint("ProRes: could not start "_s + FromWide(ffmpeg));
			delete mv;
			return res;
		}

		md = reinterpret_cast<PluginMovieData*>(mv);
		return IMAGERESULT::OK;
	}

	virtual IMAGERESULT Write(PluginMovieData* md, BaseBitmap* bm)
	{
		ProResMovie* mv = reinterpret_cast<ProResMovie*>(md);
		if (!mv || !bm || mv->failed)
			return IMAGERESULT::MISC_ERROR;

		const Int32 w = mv->width;
		const Int32 h = mv->height;
		const Int32 bpp = (mv->alpha ? 4 : 3) * 2;
		if (bm->GetBw() != w || bm->GetBh() != h)
			return IMAGERESULT::PARAM_ERROR;

		BaseBitmap* alphaChannel = mv->alpha ? bm->GetInternalChannel() : nullptr;

		for (Int32 y = 0; y < h; ++y)
		{
			UChar* row = mv->frame.data() + (size_t)y * (size_t)w * (size_t)bpp;
			bm->GetPixelCnt(0, y, w, row, bpp, COLORMODE::RGBw, PIXELCNT::NONE);

			if (mv->alpha)
			{
				UInt16* px = reinterpret_cast<UInt16*>(row);
				for (Int32 x = 0; x < w; ++x)
				{
					UInt16 a = 255;
					if (alphaChannel)
						bm->GetAlphaPixel(alphaChannel, x, y, &a);
					px[x * 4 + 3] = (UInt16)(a * 257);	// 8-bit -> 16-bit
				}
			}
		}

		const UChar* p = mv->frame.data();
		size_t remaining = mv->frame.size();
		while (remaining > 0)
		{
			const DWORD chunk = (DWORD)(remaining > (1u << 30) ? (1u << 30) : remaining);
			DWORD written = 0;
			if (!WriteFile(mv->stdinWrite, p, chunk, &written, nullptr) || written == 0)
			{
				mv->failed = true;
				GePrint("ProRes: ffmpeg stopped accepting frames. See log: "_s + FromWide(mv->logPath));
				return IMAGERESULT::FILEERROR;
			}
			p += written;
			remaining -= written;
		}
		return IMAGERESULT::OK;
	}

	virtual IMAGERESULT Close(PluginMovieData*& md)
	{
		ProResMovie* mv = reinterpret_cast<ProResMovie*>(md);
		md = nullptr;
		if (!mv)
			return IMAGERESULT::OK;

		const Bool ok = FinishFfmpeg(*mv);
		if (!ok)
			GePrint("ProRes: encoding failed. See log: "_s + FromWide(mv->logPath));
		else
			DeleteFileW(mv->logPath.c_str());

		delete mv;
		return ok ? IMAGERESULT::OK : IMAGERESULT::FILEERROR;
	}
};

Bool RegisterProResSaver()
{
	const Int32 flags = PLUGINFLAG_BITMAPSAVER_SUPPORT_8BIT | PLUGINFLAG_BITMAPSAVER_SUPPORT_16BIT |
		PLUGINFLAG_BITMAPSAVER_MOVIE | PLUGINFLAG_BITMAPSAVER_ALLOWOPTIONS | PLUGINFLAG_BITMAPSAVER_FORCESUFFIX;
	for (const ProResFormat& f : g_formats)
	{
		if (!RegisterBitmapSaverPlugin(f.id, maxon::String(f.name), flags, ProResSaver::Alloc(f), "mov"_s))
			return false;
	}
	return true;
}
