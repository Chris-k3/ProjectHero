"""Zomb-Band Song Pack Importer & Chart Generator.

Adds local audio files (.mp3, .wav, .ogg, .m4a, .flac, ...), URLs (via yt-dlp),
or Clone Hero song folders (song.ini + notes.chart + audio) into Zomb-Band's
modular HUNKBand_UserSongs.lua & HUNKBand_UserSongs.txt pack with native 3D audio.
"""

import argparse
import hashlib
import json
import math
import os
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import wave
import zlib

ROOT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
MOD_DIR = os.path.join(ROOT_DIR, "mods", "Zomb-Band", "42")
SOUND_DIR = os.path.join(MOD_DIR, "media", "sound", "ZombBand", "Custom")
UI_DIR = os.path.join(MOD_DIR, "media", "ui", "ZombBand")
LUA_OUT = os.path.join(MOD_DIR, "media", "lua", "shared", "HUNKBand_UserSongs.lua")
SCRIPT_OUT = os.path.join(MOD_DIR, "media", "scripts", "HUNKBand_UserSongs.txt")
CATALOG_PATH = os.path.join(os.path.dirname(__file__), "user_songs_catalog.json")

AUDIO_EXTS = {".wav", ".mp3", ".ogg", ".m4a", ".flac", ".aac", ".opus", ".webm", ".wma", ".mp4"}


def find_tool(name):
    found = shutil.which(name)
    if found:
        return found
    if name == "ffmpeg":
        try:
            import imageio_ffmpeg
            exe = imageio_ffmpeg.get_ffmpeg_exe()
            if exe and os.path.isfile(exe):
                return exe
        except Exception:
            pass
    scripts_dir = os.path.join(os.path.dirname(sys.executable), "Scripts")
    cand = os.path.join(scripts_dir, f"{name}.exe")
    if os.path.isfile(cand):
        return cand
    local_app = os.environ.get("LOCALAPPDATA", "")
    if local_app:
        py_base = os.path.join(local_app, "Programs", "Python")
        if os.path.isdir(py_base):
            for d in sorted(os.listdir(py_base), reverse=True):
                c = os.path.join(py_base, d, "Scripts", f"{name}.exe")
                if os.path.isfile(c):
                    return c
    return None


def slugify(text):
    s = re.sub(r"[^A-Za-z0-9]+", "_", text).strip("_")
    return (s[:36] or "Track")


def parse_artist_title(raw_name):
    base = re.sub(r"\s*[\[\(](official|lyric|audio|video|hd|hq|4k|visualizer)[^\]\)]*[\]\)]", "", raw_name, flags=re.I)
    base = re.sub(r"\s+", " ", base).strip()
    if " - " in base:
        parts = base.split(" - ", 1)
        return parts[0].strip()[:80], parts[1].strip()[:80]
    return "Custom Artist", base[:80]


def generate_cover_png(path, title, artist, seed_str):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    digest = hashlib.sha256(seed_str.encode("utf-8", errors="ignore")).digest()
    hue1 = (digest[0] / 255.0)
    hue2 = ((digest[1] + 90) % 256) / 255.0

    def hsv(h, s, v):
        i = int(h * 6.0)
        f = h * 6.0 - i
        p = v * (1.0 - s)
        q = v * (1.0 - f * s)
        t = v * (1.0 - (1.0 - f) * s)
        r, g, b = [(v, t, p), (q, v, p), (p, v, t), (p, q, v), (t, p, v), (v, p, q)][i % 6]
        return r, g, b

    c1 = hsv(hue1, 0.78, 0.85)
    c2 = hsv(hue2, 0.85, 0.45)
    size = 192
    raw = bytearray()
    ring_phase = (digest[2] % 7) + 3
    for y in range(size):
        raw.append(0)
        ny = (y / size) * 2.0 - 1.0
        for x in range(size):
            nx = (x / size) * 2.0 - 1.0
            r = math.hypot(nx, ny)
            ang = math.atan2(ny, nx)
            grad = 0.5 + 0.5 * (nx * 0.6 + ny * 0.8)
            cr = c1[0] * (1.0 - grad) + c2[0] * grad
            cg = c1[1] * (1.0 - grad) + c2[1] * grad
            cb = c1[2] * (1.0 - grad) + c2[2] * grad

            # Stylized synth/vinyl sunburst + GH3 pick silhouette + gold bezel
            beams = 0.5 + 0.5 * math.sin(ang * ring_phase + r * 3.5)
            cr = cr * 0.45 + 0.35 * beams * c1[0]
            cg = cg * 0.45 + 0.35 * beams * c1[1]
            cb = cb * 0.45 + 0.35 * beams * c1[2]

            if 0.28 < r < 0.72:
                groove = 0.82 + 0.18 * math.sin(r * 95.0)
                cr, cg, cb = cr * groove, cg * groove, cb * groove
            if r < 0.28:
                cr, cg, cb = 0.92, 0.70, 0.18
            if r < 0.08:
                cr, cg, cb = 0.05, 0.03, 0.04
            if abs(nx) > 0.92 or abs(ny) > 0.92:
                cr, cg, cb = 0.84, 0.62, 0.16
            if abs(nx) > 0.96 or abs(ny) > 0.96:
                cr, cg, cb = 0.06, 0.02, 0.03

            raw.append(max(0, min(255, int(cr * 255))))
            raw.append(max(0, min(255, int(cg * 255))))
            raw.append(max(0, min(255, int(cb * 255))))
            raw.append(255)

    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    ihdr = struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0)
    idat = zlib.compress(bytes(raw), 9)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", idat) + chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(png)


def convert_to_pz_wav(input_audio, out_wav, ffmpeg_exe):
    os.makedirs(os.path.dirname(out_wav), exist_ok=True)
    cmd = [
        ffmpeg_exe, "-nostdin", "-hide_banner", "-loglevel", "error", "-y",
        "-i", input_audio,
        "-t", "420",
        "-vn", "-ac", "1", "-ar", "44100",
        "-af", "loudnorm=I=-14:TP=-1.5:LRA=11",
        "-c:a", "pcm_s16le",
        out_wav,
    ]
    res = subprocess.run(cmd, capture_output=True, text=True)
    if res.returncode != 0:
        # Retry without loudnorm filter in case of very short clips
        cmd_plain = [
            ffmpeg_exe, "-nostdin", "-hide_banner", "-loglevel", "error", "-y",
            "-i", input_audio, "-t", "420", "-vn", "-ac", "1", "-ar", "44100", "-c:a", "pcm_s16le", out_wav,
        ]
        res2 = subprocess.run(cmd_plain, capture_output=True, text=True)
        if res2.returncode != 0:
            raise RuntimeError(f"ffmpeg failed: {res2.stderr or res.stderr}")


def analyze_wav_multiband(wav_path, hint_bpm=0.0):
    with wave.open(wav_path, "rb") as w:
        assert w.getnchannels() == 1 and w.getsampwidth() == 2 and w.getframerate() == 44100
        nframes = w.getnframes()
        raw = w.readframes(nframes)

    duration_ms = int(nframes * 1000 / 44100)
    # Decimate 4x (11025 Hz) using signed 16-bit memoryview for fast pure-Python analysis
    mv = memoryview(raw).cast("h")
    sub = mv[::4]  # ~11025 Hz, ~90.7us per sample
    hop = 110      # ~10 ms per hop
    n_hops = len(sub) // hop
    low_e = [0.0] * n_hops
    mid_e = [0.0] * n_hops
    high_e = [0.0] * n_hops
    flux_all = [0.0] * n_hops

    lp = 0.0
    bp_lp = 0.0
    prev_x = 0.0
    a_low = 0.12   # ~220 Hz lowpass
    a_mid = 0.62   # ~1800 Hz mid cutoff

    for h in range(n_hops):
        base = h * hop
        sl = sm = sh = 0.0
        for i in range(base, base + hop):
            x = sub[i] / 32768.0
            lp = lp + a_low * (x - lp)
            bp_lp = bp_lp + a_mid * (x - bp_lp)
            mid = bp_lp - lp
            high = x - prev_x
            prev_x = x
            sl += lp * lp
            sm += mid * mid
            sh += high * high
        low_e[h] = math.sqrt(sl / hop)
        mid_e[h] = math.sqrt(sm / hop)
        high_e[h] = math.sqrt(sh / hop)
        if h >= 2:
            df = max(0.0, low_e[h] - low_e[h - 2]) + max(0.0, mid_e[h] - mid_e[h - 2]) + 0.7 * max(0.0, high_e[h] - high_e[h - 2])
            flux_all[h] = df

    # Estimate BPM via autocorrelation on onset flux (range 75..175 BPM => lag 34..80 hops at 10ms)
    bpm = hint_bpm
    if bpm <= 0 and n_hops > 400:
        best_score = -1.0
        best_lag = 50
        limit_h = min(n_hops - 90, 9000)
        for lag in range(34, 81):
            corr = 0.0
            for h in range(240, limit_h, 2):
                corr += flux_all[h] * flux_all[h + lag]
            if corr > best_score:
                best_score = corr
                best_lag = lag
        bpm = round(6000.0 / best_lag, 2)
        if bpm < 80:
            bpm *= 2.0

    def pick_events(band_energy, diff_thresh, min_gap_hops, mode):
        events = []
        last_h = -100
        start_h = 240  # Always respect 2.4s approach buffer
        end_h = max(start_h, n_hops - 30)
        win = 16
        for h in range(start_h, end_h):
            lo = max(0, h - win)
            avg = sum(band_energy[lo:h]) / max(1, h - lo)
            cur = band_energy[h]
            flux = cur - band_energy[h - 2]
            if cur > 0.012 and flux > max(diff_thresh, avg * 0.14):
                if cur >= band_energy[h - 1] and cur >= band_energy[h + 1] and (h - last_h) >= min_gap_hops:
                    # Derive musical lane (1..4) from spectral balance at this moment
                    ratio_hi = high_e[h] / (low_e[h] + mid_e[h] + high_e[h] + 1e-6)
                    ratio_lo = low_e[h] / (low_e[h] + mid_e[h] + high_e[h] + 1e-6)
                    if mode == "drums":
                        if ratio_lo > 0.45:
                            lane = 1  # Kick
                        elif mid_e[h] >= high_e[h] * 0.9:
                            lane = 2  # Snare
                        elif high_e[h] > mid_e[h]:
                            lane = 3 if (len(events) % 3 != 0) else 4
                        else:
                            lane = 2
                    elif mode == "bass":
                        lane = 1 if ratio_lo > 0.48 else (2 if len(events) % 4 != 3 else (3 if ratio_hi > 0.18 else 2))
                    elif mode == "vocals":
                        lane = 1 + int(ratio_hi * 7.5 + (mid_e[h] * 12.0)) % 4
                    else:
                        # lead / rhythm contour
                        pitch_bin = int((ratio_hi * 8.0) + (cur * 6.0) + (len(events) % 2))
                        lane = 1 + (pitch_bin % 4)
                    events.append([h * 10, lane])
                    last_h = h
        if len(events) < 8:
            step = max(25, (end_h - start_h) // 16)
            for idx, h in enumerate(range(start_h, end_h, step)):
                events.append([h * 10, 1 + (idx % 4)])
        return events

    # Generate raw dense onset lists per instrument role, then shape 4 difficulty tiers
    lead_raw = pick_events([mid_e[i] + 0.8 * high_e[i] for i in range(n_hops)], 0.014, 11, "lead")
    rhythm_raw = pick_events([0.7 * low_e[i] + mid_e[i] for i in range(n_hops)], 0.015, 13, "lead")
    bass_raw = pick_events(low_e, 0.012, 16, "bass")
    drums_raw = pick_events([0.9 * low_e[i] + 0.8 * mid_e[i] + 0.9 * high_e[i] for i in range(n_hops)], 0.016, 12, "drums")
    vocals_raw = pick_events(mid_e, 0.014, 18, "vocals")

    gaps_ms = {1: 420, 2: 260, 3: 165, 4: 110}
    max_notes = {1: 420, 2: 820, 3: 1400, 4: 2600}

    def thin(raw_evs, diff):
        gap = gaps_ms[diff]
        limit = max_notes[diff]
        out = []
        last_t = -1000
        for t, lane in raw_evs:
            if t - last_t >= gap:
                out.append([t, lane])
                last_t = t
                if len(out) >= limit:
                    break
        if len(out) < 4 and raw_evs:
            return raw_evs[:min(12, len(raw_evs))]
        return out

    charts = {}
    for role, raw_evs in [("lead", lead_raw), ("rhythm", rhythm_raw), ("bass", bass_raw), ("drums", drums_raw), ("vocals", vocals_raw)]:
        charts[role] = {d: thin(raw_evs, d) for d in (1, 2, 3, 4)}

    return duration_ms, round(bpm, 2), charts


def parse_clone_hero_folder(folder):
    ini_path = os.path.join(folder, "song.ini")
    chart_path = os.path.join(folder, "notes.chart")
    meta = {}
    if os.path.isfile(ini_path):
        with open(ini_path, "r", encoding="utf-8", errors="ignore") as f:
            for line in f:
                if "=" in line:
                    k, v = line.split("=", 1)
                    meta[k.strip().lower()] = v.strip()

    audio_file = None
    for cand in ["guitar.ogg", "song.ogg", "guitar.wav", "song.wav", "audio.wav", "guitar.mp3", "song.mp3"]:
        p = os.path.join(folder, cand)
        if os.path.isfile(p):
            audio_file = p
            break
    if not audio_file:
        for fn in os.listdir(folder):
            if os.path.splitext(fn)[1].lower() in AUDIO_EXTS:
                audio_file = os.path.join(folder, fn)
                break
    if not audio_file:
        raise RuntimeError(f"No audio file found in Clone Hero folder: {folder}")

    parsed_charts = None
    parsed_bpm = 0.0
    if os.path.isfile(chart_path):
        with open(chart_path, "r", encoding="utf-8", errors="ignore") as f:
            lines = f.readlines()
        resolution = 192
        bpm_events = [(0, 120000)]
        sections = {}
        cur = ""
        for raw in lines:
            line = raw.strip()
            if line.startswith("[") and line.endswith("]"):
                cur = line[1:-1]
                sections.setdefault(cur, [])
                continue
            if cur.lower() == "song":
                m = re.match(r"Resolution\s*=\s*(\d+)", line, re.I)
                if m:
                    resolution = max(1, int(m.group(1)))
            elif cur.lower() == "synctrack":
                m = re.match(r"(\d+)\s*=\s*B\s+(\d+)", line)
                if m:
                    bpm_events.append((int(m.group(1)), max(20000, int(m.group(2)))))
            elif cur:
                m = re.match(r"(\d+)\s*=\s*N\s+(\d+)\s+(\d+)", line)
                if m:
                    fret = int(m.group(2))
                    if 0 <= fret <= 4:
                        sections[cur].append((int(m.group(1)), fret))
        bpm_events.sort()
        parsed_bpm = round(bpm_events[0][1] / 1000.0, 2)

        def tick_ms(target):
            ms = 0.0
            prev_t = 0
            cur_mbpm = 120000
            for bt, mbpm in bpm_events:
                if bt >= target:
                    break
                if bt > prev_t:
                    ms += ((bt - prev_t) / resolution) * (60_000_000.0 / cur_mbpm)
                    prev_t = bt
                cur_mbpm = mbpm
            ms += ((target - prev_t) / resolution) * (60_000_000.0 / cur_mbpm)
            return int(round(ms))

        def extract_role(prefixes, fallback):
            out = {}
            for d, diff_name in [(1, "Easy"), (2, "Medium"), (3, "Hard"), (4, "Expert")]:
                picked = None
                for pfx in prefixes:
                    sec = sections.get(diff_name + pfx)
                    if sec and len(sec) >= 4:
                        picked = sec
                        break
                if picked is None:
                    picked = fallback
                if picked:
                    evs = []
                    last_ms = -1000
                    for tk, fr in picked:
                        ms = tick_ms(tk)
                        if ms >= 2400 and ms - last_ms >= 80:
                            lane = 4 if fr >= 4 else (fr + 1)
                            evs.append([ms, lane])
                            last_ms = ms
                    out[d] = evs
            return out

        exp_lead = sections.get("ExpertSingle") or sections.get("HardSingle") or sections.get("MediumSingle") or sections.get("EasySingle")
        if exp_lead:
            lead = extract_role(["Single"], exp_lead)
            rhythm = extract_role(["DoubleRhythm", "Single"], exp_lead)
            bass = extract_role(["DoubleBass", "Single"], exp_lead)
            drums = extract_role(["Drums", "Single"], exp_lead)
            vocals = extract_role(["Single"], exp_lead)
            if all(len(v.get(d, [])) >= 4 for v in (lead, rhythm, bass, drums, vocals) for d in (1, 2, 3, 4)):
                parsed_charts = {"lead": lead, "rhythm": rhythm, "bass": bass, "drums": drums, "vocals": vocals}

    return audio_file, meta, parsed_charts, parsed_bpm


def lua_str(s):
    return "'" + str(s).replace("\\", "\\\\").replace("'", "\\'").replace("\n", " ").replace("\r", "") + "'"


def load_catalog():
    if os.path.isfile(CATALOG_PATH):
        with open(CATALOG_PATH, "r", encoding="utf-8") as f:
            return json.load(f)
    return []


def save_catalog_and_rebuild(catalog):
    os.makedirs(SOUND_DIR, exist_ok=True)
    os.makedirs(UI_DIR, exist_ok=True)
    with open(CATALOG_PATH, "w", encoding="utf-8") as f:
        json.dump(catalog, f, indent=2, ensure_ascii=False)

    # 1) Write FMOD sound definition script HUNKBand_UserSongs.txt
    script_lines = ["/* Auto-managed modular user songs for Zomb-Band. */", "module Base", "{"]
    for entry in catalog:
        slug = entry["slug"]
        script_lines.extend([
            f"    sound ZB_User_{slug}",
            "    {",
            "        category = Item,",
            "        master = Primary,",
            "        is3D = true,",
            "        clip",
            "        {",
            f"            file = media/sound/ZombBand/Custom/{slug}.wav,",
            "            volume = 0.85,",
            "            distanceMin = 2,",
            "            distanceMax = 36,",
            "        }",
            "    }",
        ])
    script_lines.append("}")
    with open(SCRIPT_OUT, "w", encoding="utf-8") as f:
        f.write("\n".join(script_lines) + "\n")

    # 2) Write HUNKBand_UserSongs.lua
    lua_lines = [
        "-- Auto-managed modular song pack for Zomb-Band.",
        "-- Add songs via AGREGAR_CANCIONES.bat or tools/add_songs.py",
        "return {",
    ]
    for entry in catalog:
        slug = entry["slug"]
        lua_lines.append("    {")
        lua_lines.append(
            f"        uid={lua_str(entry['uid'])}, name={lua_str(entry['name'])}, artist={lua_str(entry['artist'])}, "
            f"album={lua_str(entry.get('album', 'Custom Pack'))}, genre={lua_str(entry.get('genre', 'Custom'))}, "
            f"year={lua_str(str(entry.get('year', '2026')))}, origin='user', source={lua_str(entry.get('source', 'User song pack'))},"
        )
        lua_lines.append(
            f"        sound={lua_str('ZB_User_' + slug)}, cover={lua_str('media/ui/ZombBand/UserCover_' + slug + '.png')},"
        )
        lua_lines.append(
            f"        bpm={entry['bpm']:.2f}, durationMs={int(entry['durationMs'])}, hitSounds=false, chartLanes=4, charts={{"
        )
        for role in ["lead", "rhythm", "bass", "drums", "vocals"]:
            role_charts = entry["charts"].get(role, entry["charts"]["lead"])
            lua_lines.append(f"            {role}={{")
            for diff in (1, 2, 3, 4):
                evs = role_charts.get(str(diff)) or role_charts.get(diff) or []
                pairs = ",".join(f"{{{t},{l}}}" for t, l in evs)
                lua_lines.append(f"                [{diff}]={{{pairs}}},")
            lua_lines.append("            },")
        lua_lines.append("        },")
        lua_lines.append("    },")
    lua_lines.append("}")
    with open(LUA_OUT, "w", encoding="utf-8") as f:
        f.write("\n".join(lua_lines) + "\n")


def import_source(source, args):
    ffmpeg_exe = find_tool("ffmpeg")
    if not ffmpeg_exe:
        raise RuntimeError("ffmpeg not found! Install ffmpeg or imageio-ffmpeg.")

    temp_dir = None
    try:
        title = args.title
        artist = args.artist
        album = args.album or "User Song Pack"
        genre = args.genre or "Custom Rock"
        year = args.year or "2026"
        hint_bpm = float(args.bpm or 0.0)
        source_label = "Imported local track"
        pre_charts = None

        if os.path.isdir(source):
            audio_path, meta, pre_charts, ch_bpm = parse_clone_hero_folder(source)
            title = title or meta.get("name") or os.path.basename(os.path.abspath(source))
            artist = artist or meta.get("artist") or "Clone Hero Chart"
            album = args.album or meta.get("album") or album
            genre = args.genre or meta.get("genre") or genre
            year = args.year or meta.get("year") or year
            if hint_bpm <= 0 and ch_bpm > 0:
                hint_bpm = ch_bpm
            source_label = "Clone Hero chart import"
        elif re.match(r"^https?://", source, re.I):
            yt_dlp = find_tool("yt-dlp")
            if not yt_dlp:
                raise RuntimeError("yt-dlp not found! Install yt-dlp to import URLs.")
            temp_dir = tempfile.mkdtemp(prefix="zb_dl_")
            print(f"[Zomb-Band] Downloading metadata & audio: {source}")
            cmd = [
                yt_dlp, "--no-playlist", "--no-warnings",
                "--match-filters", "duration <= 420 & !is_live",
                "--ffmpeg-location", ffmpeg_exe,
                "--format", "bestaudio/best",
                "--write-info-json",
                "--output", os.path.join(temp_dir, "dl.%(ext)s"),
                "--", source,
            ]
            res = subprocess.run(cmd, capture_output=True, text=True)
            if res.returncode != 0:
                raise RuntimeError(f"yt-dlp failed: {res.stderr or res.stdout}")
            info_files = [os.path.join(temp_dir, f) for f in os.listdir(temp_dir) if f.endswith(".info.json")]
            audio_cands = [os.path.join(temp_dir, f) for f in os.listdir(temp_dir) if not f.endswith(".info.json") and not f.endswith(".part")]
            if not audio_cands:
                raise RuntimeError("No audio downloaded from URL.")
            audio_path = audio_cands[0]
            if info_files:
                with open(info_files[0], "r", encoding="utf-8", errors="ignore") as f:
                    info = json.load(f)
                raw_t = info.get("track") or info.get("title") or "Custom Track"
                raw_a = info.get("artist") or info.get("uploader") or info.get("channel") or "Downloaded Track"
                if not title and " - " in raw_t:
                    pa, pt = parse_artist_title(raw_t)
                    title = pt
                    artist = artist or pa
                title = title or raw_t
                artist = artist or raw_a
                genre = args.genre or info.get("genre") or (info.get("categories") or [genre])[0]
                if info.get("upload_date"):
                    year = args.year or str(info["upload_date"])[:4]
            source_label = "Downloaded track"
        elif os.path.isfile(source):
            audio_path = source
            stem = os.path.splitext(os.path.basename(source))[0]
            pa, pt = parse_artist_title(stem)
            title = title or pt
            artist = artist or pa
        else:
            raise FileNotFoundError(f"Input not found: {source}")

        title = (title or "Custom Track").strip()[:80]
        artist = (artist or "Unknown Artist").strip()[:80]
        slug_base = slugify(f"{artist}_{title}")
        uid_hash = hashlib.sha256(f"{artist}|{title}|{source}".encode("utf-8", errors="ignore")).hexdigest()[:8]
        slug = f"{slug_base}_{uid_hash}"
        uid = f"user-{slug}"

        os.makedirs(SOUND_DIR, exist_ok=True)
        wav_out = os.path.join(SOUND_DIR, f"{slug}.wav")
        cover_out = os.path.join(UI_DIR, f"UserCover_{slug}.png")

        print(f"[Zomb-Band] Converting audio -> 44100 Hz mono PCM WAV ({slug}.wav)...")
        convert_to_pz_wav(audio_path, wav_out, ffmpeg_exe)

        print(f"[Zomb-Band] Generating charts & BPM analysis for {title}...")
        duration_ms, detected_bpm, analyzed_charts = analyze_wav_multiband(wav_out, hint_bpm)
        charts = pre_charts if pre_charts else analyzed_charts
        bpm = detected_bpm if detected_bpm > 0 else 120.0

        generate_cover_png(cover_out, title, artist, f"{title}|{artist}|{genre}")

        catalog = load_catalog()
        catalog = [e for e in catalog if e.get("uid") != uid and e.get("slug") != slug]
        catalog.append({
            "uid": uid,
            "slug": slug,
            "name": title,
            "artist": artist,
            "album": album,
            "genre": genre,
            "year": year,
            "source": source_label,
            "bpm": bpm,
            "durationMs": duration_ms,
            "charts": charts,
        })
        save_catalog_and_rebuild(catalog)
        lead_n = len(charts["lead"].get(2) or charts["lead"].get("2") or [])
        print(f"[OK] Added '{title}' by {artist} ({duration_ms//1000}s, {bpm:.1f} BPM, Normal lead {lead_n} notes)")
    finally:
        if temp_dir and os.path.isdir(temp_dir):
            shutil.rmtree(temp_dir, ignore_errors=True)


def main():
    parser = argparse.ArgumentParser(description="Add custom songs to Zomb-Band.")
    parser.add_argument("inputs", nargs="*", help="Audio files (.mp3/.wav/.ogg/.m4a/.flac), YouTube URLs, or Clone Hero folders")
    parser.add_argument("--title", help="Override track title")
    parser.add_argument("--artist", help="Override track artist")
    parser.add_argument("--album", help="Override album")
    parser.add_argument("--genre", help="Override genre")
    parser.add_argument("--year", help="Override release year")
    parser.add_argument("--bpm", type=float, help="Override BPM hint")
    parser.add_argument("--list", action="store_true", help="List user-added songs")
    parser.add_argument("--remove", help="Remove song by uid, slug, title substring, or 1-based index")
    parser.add_argument("--rebuild", action="store_true", help="Rebuild Lua & script files from catalog")
    args = parser.parse_args()

    if args.list:
        cat = load_catalog()
        if not cat:
            print("No custom user pack songs added yet.")
        for i, e in enumerate(cat, 1):
            print(f"{i}. [{e['slug']}] {e['name']} - {e['artist']} ({e['durationMs']//1000}s, {e['bpm']} BPM)")
        return

    if args.remove:
        cat = load_catalog()
        target = args.remove.strip()
        kept = []
        removed = []
        for idx, e in enumerate(cat, 1):
            if str(idx) == target or e["uid"] == target or e["slug"] == target or target.lower() in e["name"].lower():
                removed.append(e)
                for p in (os.path.join(SOUND_DIR, f"{e['slug']}.wav"), os.path.join(UI_DIR, f"UserCover_{e['slug']}.png")):
                    if os.path.isfile(p):
                        os.remove(p)
            else:
                kept.append(e)
        save_catalog_and_rebuild(kept)
        print(f"Removed {len(removed)} song(s). Rebuilt pack with {len(kept)} song(s).")
        return

    if args.rebuild:
        cat = load_catalog()
        save_catalog_and_rebuild(cat)
        print(f"Rebuilt HUNKBand_UserSongs.lua & .txt ({len(cat)} song(s)).")
        return

    if not args.inputs:
        print("=== ZOMB-BAND III SONG IMPORTER ===")
        print("Arrastra archivos (.mp3/.wav/.ogg/.flac) o carpetas de Clone Hero a AGREGAR_CANCIONES.bat,")
        print("o pega aqui la ruta de un archivo/carpeta o una URL de YouTube:")
        val = input("> ").strip().strip('"')
        if val:
            import_source(val, args)
        return

    for src in args.inputs:
        import_source(src, args)


if __name__ == "__main__":
    main()
