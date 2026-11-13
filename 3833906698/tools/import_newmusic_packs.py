"""Import and spectrally analyze Steam Workshop NewMusic packs for Zomb-Band III.

Reads NMB sound scripts, album definitions, and translations from the installed
Steam Workshop mods, extracts multi-band audio envelopes via ffmpeg, detects real
BPM/duration/instrument presence, and outputs compact multi-stem Kahlua-safe Lua
modules keyed by active Workshop FMOD sound names.
"""
from __future__ import annotations

import array
import concurrent.futures
import glob
import json
import math
import os
import re
import struct
import subprocess
import time
import zlib
from pathlib import Path
from typing import Dict, List, Optional, Tuple

import imageio_ffmpeg

WORKSHOP_ROOT = Path(r"C:\Program Files (x86)\Steam\steamapps\workshop\content\108600")
MOD_DIR = Path(__file__).resolve().parent.parent / "mods" / "Zomb-Band" / "42" / "media"
LUA_SHARED_DIR = MOD_DIR / "lua" / "shared"
UI_ART_DIR = MOD_DIR / "ui" / "ZombBand"

PACKS = [
    {
        "workshop_id": "3808737141",
        "mod_id": "EA_H",
        "pack_name": "Exitos del Ayer y Hoy",
        "lua_module": "HUNKBand_Pack_EA_H",
        "cover": "Pack_EA_H.png",
        "category_key": "ea_h",
        "accent": (212, 58, 44),
        "default_genre": "Latin Classics / Pop",
    },
    {
        "workshop_id": "3751364201",
        "mod_id": "NMGreatestHits",
        "pack_name": "New Music Greatest Hits",
        "lua_module": "HUNKBand_Pack_NMGreatestHits",
        "cover": "Pack_NMGreatestHits.png",
        "category_key": "greatest_hits",
        "accent": (228, 174, 48),
        "default_genre": "Greatest Hits",
    },
    {
        "workshop_id": "3765079521",
        "mod_id": "NewMusicG80s",
        "pack_name": "Graves 80s Mixtape",
        "lua_module": "HUNKBand_Pack_NewMusicG80s",
        "cover": "Pack_NewMusicG80s.png",
        "category_key": "g80s",
        "accent": (218, 52, 168),
        "default_genre": "80s Mixtape",
    },
    {
        "workshop_id": "3765670104",
        "mod_id": "NewMusicG90s",
        "pack_name": "Graves 90s Mixtape",
        "lua_module": "HUNKBand_Pack_NewMusicG90s",
        "cover": "Pack_NewMusicG90s.png",
        "category_key": "g90s",
        "accent": (46, 178, 224),
        "default_genre": "90s Mixtape",
    },
    {
        "workshop_id": "3765077081",
        "mod_id": "NewMusicG70s",
        "pack_name": "Graves 70s Mixtape",
        "lua_module": "HUNKBand_Pack_NewMusicG70s",
        "cover": "Pack_NewMusicG70s.png",
        "category_key": "g70s",
        "accent": (216, 122, 42),
        "default_genre": "70s Mixtape",
    },
    {
        "workshop_id": "3760471726",
        "mod_id": "NewMusic_CMM",
        "pack_name": "Classical Music Mix",
        "lua_module": "HUNKBand_Pack_NewMusic_CMM",
        "cover": "Pack_NewMusic_CMM.png",
        "category_key": "cmm",
        "accent": (178, 152, 110),
        "default_genre": "Classical",
    },
]

B36 = "0123456789abcdefghijklmnopqrstuvwxyz"


def sanitize_ascii(text: str) -> str:
    """Normalize punctuation and strip unsupported glyphs cleanly for PZ bitmap fonts."""
    repl = {
        "\u2013": "-", "\u2014": "-", "\u2012": "-", "\u2212": "-",
        "\u2018": "'", "\u2019": "'", "\u201c": '"', "\u201d": '"',
        "\u00a0": " ", "\u2026": "...",
        "á": "a", "é": "e", "í": "i", "ó": "o", "ú": "u", "ü": "u", "ñ": "n",
        "Á": "A", "É": "E", "Í": "I", "Ó": "O", "Ú": "U", "Ü": "U", "Ñ": "N",
        "à": "a", "è": "e", "ì": "i", "ò": "o", "ù": "u", "ç": "c", "ä": "a", "ö": "o",
        "À": "A", "È": "E", "Ì": "I", "Ò": "O", "Ù": "U", "Ç": "C", "Ä": "A", "Ö": "O",
    }
    out = []
    for ch in text:
        ch = repl.get(ch, ch)
        if 32 <= ord(ch) <= 126:
            out.append(ch)
    s = re.sub(r"\s+", " ", "".join(out)).strip()
    return s


def lua_str(text: str) -> str:
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'


def clean_display_title(raw_label: str, pack_title: str) -> Tuple[str, str]:
    """Split 'Artist - Title' cleanly without inventing nonexistent artist tags."""
    s = sanitize_ascii(raw_label)
    s = re.sub(r"\s*\((?:Audio HQ|Official Video|Letra|Lyrics|HQ)\)\s*", " ", s, flags=re.I).strip()
    s = re.sub(r"^\d{1,3}\s*[-.:]\s*", "", s).strip()
    s = re.sub(r"\s+", " ", s)
    for sep in (" - ", ": "):
        if sep in s:
            left, right = s.split(sep, 1)
            left, right = left.strip(), right.strip()
            if left and right and len(left) <= 45:
                return right, left
    return s or "Untitled Track", pack_title


def parse_sound_scripts(mod_dir: Path) -> Dict[str, Path]:
    """Map every FMOD sound name from NMB_*_Sounds.txt to its resolved .ogg file."""
    sounds: Dict[str, Path] = {}
    search_bases = []
    for sub in ("42/media", "common/media", "media"):
        cand = mod_dir / sub
        if cand.exists():
            search_bases.append(cand)

    for txt_path in mod_dir.glob("**/NMB_*_Sounds.txt"):
        content = txt_path.read_text(encoding="utf-8", errors="replace")
        for match in re.finditer(r"sound\s+([A-Za-z0-9_.-]+)\s*\{(.*?)\}", content, re.S):
            snd_name = match.group(1)
            body = match.group(2)
            file_m = re.search(r"file\s*=\s*([^,\}\r\n]+)", body)
            if not file_m:
                continue
            rel = file_m.group(1).strip().strip('"').replace("\\", "/")
            if rel.startswith("media/"):
                rel = rel[len("media/"):]
            resolved = None
            for base in search_bases:
                cand = base / rel
                if cand.exists():
                    resolved = cand
                    break
            if resolved:
                sounds[snd_name] = resolved
    return sounds


def load_ui_translations(mod_dir: Path) -> Dict[str, str]:
    """Load English/Spanish UI translation keys cleanly."""
    merged: Dict[str, str] = {}
    for lang in ("EN", "ES"):
        for jp in mod_dir.glob(f"**/Translate/{lang}/UI.json"):
            try:
                data = json.loads(jp.read_text(encoding="utf-8-sig"))
                if isinstance(data, dict):
                    merged.update({str(k): str(v) for k, v in data.items()})
            except Exception:
                pass
        for tp in mod_dir.glob(f"**/Translate/{lang}/UI_{lang}.txt"):
            txt = tp.read_text(encoding="utf-8-sig", errors="replace")
            for m in re.finditer(r'([A-Za-z0-9_]+)\s*=\s*"([^"]*)"', txt):
                merged.setdefault(m.group(1), m.group(2))
    return merged


def parse_albums(mod_dir: Path, ui_map: Dict[str, str], sounds: Dict[str, Path], pack_name: str):
    """Collect track entries matching NMB sound scripts with album and translation labels."""
    tracks = []
    seen_sounds = set()
    album_files = sorted(mod_dir.glob("**/42/media/lua/shared/*Album*.lua"))
    for af in album_files:
        txt = af.read_text(encoding="utf-8", errors="replace")
        title_m = re.search(r'\btitle\s*=\s*"([^"]+)"', txt)
        album_title = sanitize_ascii(title_m.group(1)) if title_m else pack_name
        prefix_m = re.search(r'\bsoundPrefix\s*=\s*"([^"]+)"', txt)
        prefix = prefix_m.group(1) if prefix_m else ""
        labels_m = re.search(r'\blabels\s*=\s*\{(.*?)\}', txt, re.S)
        if not prefix or not labels_m:
            continue
        labels = re.findall(r'"([^"]+)"', labels_m.group(1))
        for idx, label_key in enumerate(labels, start=1):
            snd_name = f"{prefix}{idx:02d}"
            ogg_path = sounds.get(snd_name)
            if not ogg_path:
                continue
            seen_sounds.add(snd_name)
            raw_label = ui_map.get(label_key, label_key)
            song_name, artist = clean_display_title(raw_label, album_title)
            tracks.append({
                "sound": snd_name,
                "name": song_name,
                "artist": artist,
                "album": album_title,
                "ogg": ogg_path,
            })

    # Include any extra sound entries not listed inside an album table
    for snd_name, ogg_path in sorted(sounds.items()):
        if snd_name not in seen_sounds:
            stem = re.sub(r"^[A-Za-z0-9_]+Side[AB]\d+", "", ogg_path.stem)
            stem = re.sub(r"([a-z])([A-Z])", r"\1 \2", stem).strip() or ogg_path.stem
            song_name, artist = clean_display_title(stem, pack_name)
            tracks.append({
                "sound": snd_name,
                "name": song_name,
                "artist": artist,
                "album": pack_name,
                "ogg": ogg_path,
            })
    return tracks


def extract_5band_envelopes(ogg_path: Path, ffmpeg_exe: str) -> Tuple[List[List[float]], int]:
    """Decode ogg into 5 C-filtered frequency stems and return 100Hz amplitude envelopes."""
    cmd = [
        ffmpeg_exe, "-v", "error", "-i", str(ogg_path), "-filter_complex",
        "[0:a]aresample=8000,aformat=sample_fmts=s16:channel_layouts=mono,asplit=5[a0][a1][a2][a3][a4];"
        "[a0]lowpass=f=140[b0];"
        "[a1]bandpass=f=240:w=180[b1];"
        "[a2]bandpass=f=600:w=420[b2];"
        "[a3]bandpass=f=1400:w=900[b3];"
        "[a4]highpass=f=2200[b4];"
        "[b0][b1][b2][b3][b4]join=inputs=5:channel_layout=5.0[out]",
        "-map", "[out]", "-f", "s16le", "-",
    ]
    res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if res.returncode != 0 or len(res.stdout) < 4000:
        # Single-band fallback if an unusual stream confuses filtergraph
        res2 = subprocess.run(
            [ffmpeg_exe, "-v", "error", "-i", str(ogg_path), "-ac", "1", "-ar", "8000", "-f", "s16le", "-"],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True,
        )
        arr = array.array("h")
        arr.frombytes(res2.stdout)
        n_frames = max(1, len(arr) // 80)
        s_abs = [abs(x) for x in arr[::4]]
        mono = [sum(s_abs[i * 20:(i + 1) * 20]) / 20.0 for i in range(n_frames)]
        dur_ms = int(round(len(arr) * 1000.0 / 8000.0))
        return [mono[:], mono[:], mono[:], mono[:], mono[:]], dur_ms

    arr = array.array("h")
    arr.frombytes(res.stdout)
    samples_per_ch = len(arr) // 5
    n_frames = max(1, samples_per_ch // 80)
    dur_ms = int(round(samples_per_ch * 1000.0 / 8000.0))
    envs: List[List[float]] = []
    for ch in range(5):
        # Stride 4 -> 2000Hz sampling of filtered audio (20 points per 10ms frame)
        band = arr[ch::5]
        s_abs = [abs(x) for x in band[::4]]
        envs.append([sum(s_abs[i * 20:(i + 1) * 20]) * 0.05 for i in range(n_frames)])
    return envs, dur_ms


def estimate_bpm(envs: List[List[float]]) -> float:
    """Estimate musical tempo via flux autocorrelation on 10ms frames."""
    n = len(envs[0])
    if n < 500:
        return 120.0
    # Weight kick/sub + snare/rhythm + hihat onset novelty
    total = [envs[0][i] * 1.3 + envs[2][i] + envs[4][i] * 0.8 for i in range(n)]
    flux = [0.0] * n
    for i in range(4, n):
        d = total[i] - total[i - 2] * 0.65 - total[i - 3] * 0.35
        if d > 0:
            flux[i] = d

    # Evaluate centered window up to 30s at 4-frame stride for ultra-fast O(1) BPM estimate
    start = min(n // 4, 1500)
    end = min(n, start + 3000)
    seg = flux[start:end]
    m = len(seg)
    if m < 400:
        return 120.0

    best_score = -1.0
    best_lag = 50  # 120 BPM
    for lag in range(34, 92):  # ~65 BPM to 176 BPM
        acc = 0.0
        for i in range(0, m - lag, 4):
            acc += seg[i] * seg[i + lag]
        bpm_cand = 6000.0 / lag
        weight = 1.12 if 86.0 <= bpm_cand <= 148.0 else 0.94
        score = acc * weight
        if score > best_score:
            best_score = score
            best_lag = lag

    bpm = 6000.0 / best_lag
    while bpm < 76.0:
        bpm *= 2.0
    while bpm > 172.0:
        bpm *= 0.5
    return round(bpm, 2)


def classify_instruments(meta: dict, mod_id: str, envs: List[List[float]]) -> List[str]:
    """Select an authentic 3-6 instrument lineup matching both song identity and spectral acoustics."""
    text = f"{meta['artist']} {meta['name']} {meta['album']}".lower()
    n = len(envs[0])
    means = [sum(e) / max(1, n) for e in envs]
    tot = sum(means) + 1e-6
    sub_r, bass_r, rhy_r, lead_r, high_r = [m / tot for m in means]

    # Measure percussive transient sharpness in sub + high bands
    sub_e, rhy_e, high_e = envs[0], envs[2], envs[4]
    perc_flux = 0.0
    for i in range(3, n, 2):
        df = max(0.0, (sub_e[i] - sub_e[i - 2]) + (high_e[i] - high_e[i - 2]))
        perc_flux += df
    perc_sharp = perc_flux / max(1.0, (means[0] + means[4]) * (n * 0.5))

    has_drums = (perc_sharp > 0.24 or sub_r > 0.17) and mod_id != "NewMusic_CMM"

    if mod_id == "NewMusic_CMM" or any(w in text for w in (
        "symphony", "concerto", "sonata", "overture", "beethoven", "mozart", "bach", "vivaldi", "chopin", "tchaikovsky"
    )):
        picks = ["violin", "flute", "keyboard", "trumpet"]
        if bass_r > 0.16:
            picks.append("acoustic")
        return picks

    # Acoustic / folk / bluegrass / country
    if any(w in text for w in (
        "johnny cash", "dolly parton", "john denver", "simon & garfunkel", "cat stevens",
        "tracy chapman", "creedence", "willie nelson", "banjo", "bluegrass", "folk", "country"
    )):
        picks = ["acoustic", "banjo", "violin", "vocals"]
        if bass_r > 0.14:
            picks.append("bass")
        if has_drums and perc_sharp > 0.30:
            picks.append("drums")
        else:
            picks.append("harmonica")
        return picks[:5]

    # Heavy rock / metal / grunge / classic guitar rock / rock en espanol
    if any(w in text for w in (
        "metallica", "nirvana", "ac/dc", "led zeppelin", "black sabbath", "iron maiden", "guns n",
        "pearl jam", "soundgarden", "alice in chains", "foo fighters", "red hot chili", "smashing pumpkins",
        "ramones", "the clash", "green day", "offspring", "weezer", "rage against", "system of a down",
        "deep purple", "van halen", "ozzy", "queen", "jimi hendrix", "rolling stones", "pink floyd",
        "aerosmith", "bon jovi", "scorpions", "def leppard", "oasis", "blur", "radiohead",
        "soda stereo", "heroes del silencio", "mana", "enanitos verdes", "caifanes", "cafe tacvba",
        "el tri", "molotov", "fobia", "miguel mateos", "charly garcia", "los prisioneros", "vilma palma"
    )):
        picks = ["guitar", "bass", "drums", "vocals"]
        if any(w in text for w in ("queen", "pink floyd", "deep purple", "doors", "van halen", "soda stereo", "charly", "bon jovi", "acoustic", "stairway", "hotel california")):
            picks.append("keyboard" if rhy_r > 0.21 else "acoustic")
        elif rhy_r > 0.24:
            picks.append("acoustic")
        return picks[:5]

    # Latin brass / tropical / mariachi / ranchera / big-band pop
    if any(w in text for w in (
        "sonora", "angeles azules", "celia cruz", "willie colon", "hector lavoe", "juan gabriel",
        "vicente fernandez", "pepe aguilar", "bronco", "tigres del norte", "banda", "cumbia",
        "salsa", "mambo", "merengue", "mariachi", "jose jose", "luis miguel", "rocio durcal"
    )):
        picks = ["vocals", "trumpet", "bass", "drums"]
        if rhy_r > 0.20 or "cumbia" in text or "luis miguel" in text or "bronco" in text:
            picks.append("keyboard")
        if lead_r > 0.18 or "salsa" in text or "sonora" in text or "luis miguel" in text:
            picks.append("sax")
        elif "vicente" in text or "mariachi" in text or "rocio" in text or "juan gabriel" in text:
            picks.append("violin")
        else:
            picks.append("acoustic")
        return picks[:5]

    # Romantic Balada / Synth / 80s-90s Pop / Dance / Electronic
    if any(w in text for w in (
        "amanda miguel", "camilo sesto", "daniela romo", "julio iglesias", "emmanuel", "yuri",
        "pandora", "flans", "timbiriche", "mijares", "franco de vita", "ricardo montaner",
        "depeche mode", "new order", "pet shop", "a-ha", "eurythmics", "madonna", "michael jackson",
        "prince", "whitney houston", "cyndi lauper", "abba", "bee gees", "daft punk", "prodigy",
        "ace of base", "la bouche", "corona", "snap!", "technotronic", "backstreet", "spice girls"
    )):
        picks = ["keyboard", "bass", "drums", "vocals"]
        if "michael jackson" in text or "prince" in text or "abba" in text:
            picks.append("guitar")
        elif mod_id == "EA_H" and perc_sharp < 0.29:
            picks = ["vocals", "keyboard", "acoustic", "violin", "bass"]
            if has_drums:
                picks.append("drums")
        elif lead_r > 0.23 and mod_id in ("NewMusicG80s", "NMGreatestHits"):
            picks.append("sax")
        return picks[:5]

    # Hip hop / Soul / Funk / Jazz
    if any(w in text for w in (
        "2pac", "tupac", "biggie", "notorious", "snoop", "dr. dre", "eminem", "wu-tang", "nas",
        "outkast", "tlc", "lauryn hill", "fugees", "earth, wind", "stevie wonder", "marvin gaye",
        "kool & the gang", "aretha", "ray charles", "frank sinatra", "george michael", "careless whisper"
    )):
        picks = ["vocals", "bass", "drums", "keyboard"]
        if any(w in text for w in ("stevie", "earth, wind", "kool", "george michael", "sinatra", "marvin")):
            picks.append("sax")
            if sub_r < 0.24:
                picks.append("trumpet")
        elif rhy_r > 0.22:
            picks.append("guitar")
        return picks[:5]

    # Pure spectral adaptive assignment (yields genuinely distinct 3-5 instrument bands!)
    picks: List[str] = []
    if lead_r > 0.17:
        picks.append("vocals")
    if (rhy_r > 0.22 and lead_r > 0.19) or (high_r > 0.17 and mod_id in ("NewMusicG70s", "NewMusicG90s")):
        picks.append("guitar")
    elif lead_r > 0.19 and mod_id in ("NewMusicG80s", "EA_H"):
        picks.append("keyboard")
    else:
        picks.append("acoustic" if perc_sharp < 0.29 else "guitar")

    if mod_id == "NewMusicG80s" and "keyboard" not in picks:
        picks.append("keyboard")
    if bass_r + sub_r > 0.29 or len(picks) < 3:
        picks.append("bass")
    if has_drums:
        picks.append("drums")
    if lead_r > 0.24 and high_r < 0.14 and "sax" not in picks and mod_id in ("EA_H", "NewMusicG80s", "NMGreatestHits"):
        picks.append("sax")
    elif perc_sharp < 0.25 and "violin" not in picks:
        picks.append("violin")
    if "vocals" not in picks and lead_r > 0.14:
        picks.append("vocals")

    # Deduplicate preserving order cleanly and keep 3..5 instruments
    uniq = []
    for k in picks:
        if k not in uniq:
            uniq.append(k)
    for fallback in ("keyboard", "guitar", "bass", "drums", "vocals"):
        if len(uniq) >= 3:
            break
        if fallback not in uniq:
            uniq.append(fallback)
    return uniq[:5]


def encode_stem(events: List[Tuple[int, int, int]]) -> str:
    """Encode sorted (frame_10ms, lane_1..4, tier_1..4) events as fixed 3-char base36 records."""
    if not events:
        return ""
    out: List[str] = []
    prev_t = 0
    for t10, lane, tier in events:
        dt = max(0, t10 - prev_t)
        prev_t = t10
        while dt > 1295:
            out.append("zzz")
            dt -= 1295
        hi = B36[dt // 36]
        lo = B36[dt % 36]
        code = (tier - 1) * 4 + (lane - 1)  # 0..15 -> [0-9a-f]
        out.append(f"{hi}{lo}{B36[code]}")
    return "".join(out)


def pick_stem_onsets(
    sig: List[float],
    lane_fn,
    min_gap_frames: int,
    threshold_k: float,
    max_nps_expert: float,
    dur_ms: int,
) -> str:
    """Detect local-adaptive rhythmic onsets for one frequency stem and tier them into 4 difficulties."""
    n = len(sig)
    if n < 100 or dur_ms < 2000:
        return ""

    # Positive half-wave flux with 40ms lookback
    flux = [0.0] * n
    for i in range(4, n):
        base = sig[i - 2] * 0.55 + sig[i - 3] * 0.30 + sig[i - 4] * 0.15
        d = sig[i] - base
        if d > 0.0:
            flux[i] = d

    # 1.2s causal-centered moving baseline for adaptive local picking
    win = 60  # +-0.6s
    prefix = [0.0] * (n + 1)
    for i in range(n):
        prefix[i + 1] = prefix[i] + flux[i]

    global_mean = prefix[n] / n
    floor = max(1e-6, global_mean * 0.45)

    start_f = max(40, int(0.02 * n))  # skip tiny click at t=0
    end_f = min(n - 35, int(round((dur_ms - 350) / 10.0)))
    raw_peaks: List[Tuple[int, float]] = []
    for i in range(start_f, end_f):
        v = flux[i]
        if v < floor:
            continue
        # Strict local peak within +-4 frames (40ms)
        if not (v >= flux[i - 1] and v >= flux[i - 2] and v > flux[i + 1] and v > flux[i + 2]):
            continue
        lo = max(0, i - win)
        hi = min(n, i + win)
        local_avg = (prefix[hi] - prefix[lo]) / max(1, hi - lo)
        if v < local_avg * threshold_k:
            continue
        score = v / max(1e-6, local_avg)
        raw_peaks.append((i, score))

    # Enforce minimum inter-onset gap keeping stronger peak
    filtered: List[Tuple[int, float]] = []
    for idx, sc in raw_peaks:
        if filtered and (idx - filtered[-1][0]) < min_gap_frames:
            if sc > filtered[-1][1]:
                filtered[-1] = (idx, sc)
        else:
            filtered.append((idx, sc))

    # Cap Expert density so notes match readable musical cadence rather than noise
    max_events = max(16, min(720, int(round((dur_ms / 1000.0) * max_nps_expert))))
    if len(filtered) > max_events:
        ranked = sorted(filtered, key=lambda x: x[1], reverse=True)[:max_events]
        filtered = sorted(ranked, key=lambda x: x[0])

    if not filtered:
        return ""

    # Tier peaks by strength percentiles so Easy -> Expert scales faithfully on the main beats:
    # Tier 1 (~28% strongest accents -> Easy..Expert)
    # Tier 2 (~52% -> Normal..Expert)
    # Tier 3 (~76% -> Hard..Expert)
    # Tier 4 (100% -> Expert)
    scores_sorted = sorted(x[1] for x in filtered)
    m = len(scores_sorted)
    t1_cut = scores_sorted[min(m - 1, int(m * 0.72))]
    t2_cut = scores_sorted[min(m - 1, int(m * 0.48))]
    t3_cut = scores_sorted[min(m - 1, int(m * 0.24))]

    events: List[Tuple[int, int, int]] = []
    prev_lane = 1
    for i_idx, sc in filtered:
        if sc >= t1_cut:
            tier = 1
        elif sc >= t2_cut:
            tier = 2
        elif sc >= t3_cut:
            tier = 3
        else:
            tier = 4
        lane = lane_fn(i_idx, prev_lane)
        prev_lane = lane
        events.append((i_idx, lane, tier))

    return encode_stem(events)


def analyze_track(task: Tuple[int, dict, str, str]) -> Tuple[int, Optional[dict]]:
    idx, meta, mod_id, ffmpeg_exe = task
    try:
        envs, dur_ms = extract_5band_envelopes(meta["ogg"], ffmpeg_exe)
    except Exception:
        return idx, None

    if dur_ms < 4000 or len(envs[0]) < 200:
        return idx, None

    bpm = estimate_bpm(envs)
    allowed = classify_instruments(meta, mod_id, envs)
    n = len(envs[0])
    sub, bass, rhy, lead, high = envs

    # Build 5 instrument-specific composite envelopes & lane mappers:
    # 1. Drums: Sub Kick (L1), Snare Rhy (L2), Hat/Rack (L3), Crash (Kick+High -> L4)
    drums_sig = [sub[i] * 1.35 + rhy[i] * 0.95 + high[i] * 1.15 for i in range(n)]
    def drums_lane(i: int, _prev: int) -> int:
        if sub[i] > rhy[i] * 1.15 and high[i] > sub[i] * 0.55:
            return 4  # Crash / double hit
        if sub[i] >= rhy[i] and sub[i] >= high[i]:
            return 1  # Kick pedal
        if rhy[i] >= high[i]:
            return 2  # Snare backbeat
        return 3      # Hi-hat / cymbal

    # 2. Bass: Low pocket (L1-L2 root + L3-L4 octave/fill accents)
    bass_sig = [sub[i] * 0.9 + bass[i] * 1.4 for i in range(n)]
    def bass_lane(i: int, _prev: int) -> int:
        ratio = rhy[i] / (bass[i] + 1e-6)
        if ratio < 0.65:
            return 1
        if ratio < 1.05:
            return 2
        if ratio < 1.55:
            return 3
        return 4

    # 3. Rhythm (Acoustic / Keyboard / Banjo): Chord & comping cadence
    rhy_sig = [bass[i] * 0.45 + rhy[i] * 1.35 + lead[i] * 0.45 for i in range(n)]
    def rhy_lane(i: int, _prev: int) -> int:
        centroid = (lead[i] * 1.5 + high[i] * 2.0) / (rhy[i] + bass[i] + 1e-6)
        if centroid < 0.55:
            return 1
        if centroid < 0.90:
            return 2
        if centroid < 1.35:
            return 3
        return 4

    # 4. Lead (Guitar / Violin / Sax / Trumpet): Melodic solos, riffs, brass hooks
    lead_sig = [rhy[i] * 0.45 + lead[i] * 1.4 + high[i] * 0.85 for i in range(n)]
    def lead_lane(i: int, _prev: int) -> int:
        bright = (high[i] * 1.8) / (rhy[i] + lead[i] + 1e-6)
        if bright < 0.35:
            return 1
        if bright < 0.62:
            return 2
        if bright < 0.98:
            return 3
        return 4

    # 5. Vocals (Vocals / Flute / Harmonica): Sustained syllabic & breath phrasing (wider spacing!)
    voc_sig = [rhy[i] * 0.35 + lead[i] * 1.35 + high[i] * 0.35 for i in range(n)]
    def voc_lane(i: int, prev: int) -> int:
        pitch = (lead[i] * 1.2 + high[i] * 1.6) / (bass[i] + rhy[i] + 1e-6)
        target = 1 if pitch < 0.65 else (2 if pitch < 1.0 else (3 if pitch < 1.45 else 4))
        # Smooth vocal steps
        if abs(target - prev) > 2:
            target = prev + (1 if target > prev else -1)
        return target

    raw_charts = {
        "drums": pick_stem_onsets(drums_sig, drums_lane, 12, 1.32, 3.6, dur_ms),
        "bass": pick_stem_onsets(bass_sig, bass_lane, 16, 1.28, 2.7, dur_ms),
        "rhythm": pick_stem_onsets(rhy_sig, rhy_lane, 15, 1.26, 3.0, dur_ms),
        "lead": pick_stem_onsets(lead_sig, lead_lane, 13, 1.28, 3.4, dur_ms),
        "vocals": pick_stem_onsets(voc_sig, voc_lane, 24, 1.24, 2.1, dur_ms),
    }

    # Ensure every allowed chart role has valid notes
    for role in ("lead", "rhythm", "bass", "drums", "vocals"):
        if len(raw_charts[role]) < 12:
            raw_charts[role] = raw_charts["lead"] or raw_charts["rhythm"] or raw_charts["drums"]

    return idx, {
        "name": meta["name"],
        "artist": meta["artist"],
        "album": meta["album"],
        "sound": meta["sound"],
        "durationMs": dur_ms,
        "bpm": bpm,
        "allowed": allowed,
        "rawCharts": raw_charts,
    }


def generate_pack_cover(pack: dict) -> None:
    """Create crisp GH3-styled pack cover PNG using pure stdlib PNG encoding."""
    UI_ART_DIR.mkdir(parents=True, exist_ok=True)
    out_path = UI_ART_DIR / pack["cover"]
    w, h = 256, 256
    ar, ag, ab = pack["accent"]
    rows = []
    for y in range(h):
        k = y / 255.0
        row = bytearray([0])  # PNG filter type 0
        dy = y - 128
        for x in range(w):
            dx = x - 128
            dist = math.hypot(dx, dy)
            pr = int(20 + ar * 0.28 * (1.0 - k))
            pg = int(8 + ag * 0.22 * (1.0 - k))
            pb = int(12 + ab * 0.24 * (1.0 - k))
            if 97 <= dist <= 104:
                pr, pg, pb = ar, ag, ab
            elif 42 <= dist < 97:
                groove = 10 if (int(dist) % 9 < 2) else 0
                pr, pg, pb = 22 + groove, 18 + groove, 22 + groove
            elif 14 <= dist < 42:
                pr, pg, pb = ar, ag, ab
            elif dist < 14:
                pr, pg, pb = 14, 8, 10
            if (x < 4 or x >= w - 4 or y < 4 or y >= h - 4):
                pr, pg, pb = 232, 178, 52
            elif y >= 210 and 12 <= x <= w - 12:
                pr, pg, pb = (232, 178, 52) if (y < 213 or y > 246 or x < 15 or x > w - 15) else (16, 6, 8)
            row.extend((max(0, min(255, pr)), max(0, min(255, pg)), max(0, min(255, pb)), 255))
        rows.append(bytes(row))

    def png_chunk(tag: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    ihdr = struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)
    idat = zlib.compress(b"".join(rows), 6)
    png = b"\x89PNG\r\n\x1a\n" + png_chunk(b"IHDR", ihdr) + png_chunk(b"IDAT", idat) + png_chunk(b"IEND", b"")
    out_path.write_bytes(png)


def write_pack_lua(pack: dict, analyzed: List[dict]) -> Path:
    out_path = LUA_SHARED_DIR / f"{pack['lua_module']}.lua"
    lines = [
        f"-- Auto-generated audio-analyzed rhythm charts for Steam Workshop mod {pack['mod_id']} ({pack['workshop_id']}).",
        "return {",
    ]
    for tr in analyzed:
        allowed_lua = "{" + ",".join(f"{k}=true" for k in tr["allowed"]) + "}"
        rc = tr["rawCharts"]
        raw_lua = (
            "{"
            + f"lead={lua_str(rc['lead'])},"
            + f"rhythm={lua_str(rc['rhythm'])},"
            + f"bass={lua_str(rc['bass'])},"
            + f"drums={lua_str(rc['drums'])},"
            + f"vocals={lua_str(rc['vocals'])}"
            + "}"
        )
        uid = f"nm-{pack['mod_id']}-{tr['sound']}"
        lines.append(
            "  {"
            + f"n={lua_str(tr['name'])},"
            + f"a={lua_str(tr['artist'])},"
            + f"al={lua_str(tr['album'])},"
            + f"s={lua_str(tr['sound'])},"
            + f"u={lua_str(uid)},"
            + f"d={tr['durationMs']},"
            + f"b={tr['bpm']},"
            + f"inst={allowed_lua},"
            + f"ch={raw_lua}"
            + "},"
        )
    lines.append("}")
    out_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return out_path


def write_catalog_loader(pack_summaries: List[dict]) -> Path:
    out_path = LUA_SHARED_DIR / "HUNKBand_WorkshopCatalog.lua"
    lines = [
        "-- Connects Steam Workshop NewMusic packs (EA_H, NMGreatestHits, G80s, G90s, G70s, CMM) to Zomb-Band.",
        "local M = {}",
        "local PACKS = {",
    ]
    for p in pack_summaries:
        lines.append(
            "  {"
            + f"modId={lua_str(p['mod_id'])},"
            + f"workshopId={lua_str(p['workshop_id'])},"
            + f"source={lua_str(p['pack_name'])},"
            + f"genre={lua_str(p['default_genre'])},"
            + f"cover={lua_str('media/ui/ZombBand/' + p['cover'])},"
            + f"packKey={lua_str(p['category_key'])},"
            + f"moduleName={lua_str(p['lua_module'])}"
            + "},"
        )
    lines.extend([
        "}",
        "function M.appendTo(B)",
        "    if type(B) ~= 'table' or type(B.songs) ~= 'table' then return end",
        "    B.workshopPacks = B.workshopPacks or {}",
        "    local baseCount = #B.songs",
        "    for _, p in ipairs(PACKS) do",
        "        local ok, entries = pcall(require, p.moduleName)",
        "        if ok and type(entries) == 'table' then",
        "            local loadedCount = 0",
        "            for _, e in ipairs(entries) do",
        "                if type(e) == 'table' and e.n and e.s and e.d and e.d > 0 then",
        "                    loadedCount = loadedCount + 1",
        "                    B.songs[#B.songs + 1] = {",
        "                        name = e.n,",
        "                        artist = e.a,",
        "                        album = e.al,",
        "                        uid = e.u,",
        "                        sound = e.s,",
        "                        soundAlt = p.modId .. '.' .. e.s,",
        "                        origin = 'workshop',",
        "                        requiresMod = p.modId,",
        "                        workshopId = p.workshopId,",
        "                        packKey = p.packKey,",
        "                        source = p.source,",
        "                        genre = p.genre,",
        "                        cover = p.cover,",
        "                        bpm = e.b or 120,",
        "                        durationMs = e.d,",
        "                        hitSounds = false,",
        "                        chartLanes = 4,",
        "                        allowedInstruments = e.inst,",
        "                        rawCharts = e.ch,",
        "                    }",
        "                end",
        "            end",
        "            B.workshopPacks[p.modId] = { title = p.source, workshopId = p.workshopId, count = loadedCount, packKey = p.packKey }",
        "        end",
        "    end",
        "    return #B.songs - baseCount",
        "end",
        "return M",
        "",
    ])
    out_path.write_text("\n".join(lines), encoding="utf-8")
    return out_path


def main() -> None:
    t_start = time.perf_counter()
    ffmpeg_exe = imageio_ffmpeg.get_ffmpeg_exe()
    LUA_SHARED_DIR.mkdir(parents=True, exist_ok=True)
    UI_ART_DIR.mkdir(parents=True, exist_ok=True)

    installed_packs = []
    for pack in PACKS:
        mod_dir = WORKSHOP_ROOT / pack["workshop_id"] / "mods" / pack["mod_id"]
        if not mod_dir.exists():
            print(f"[SKIP] Missing workshop mod {pack['workshop_id']} / {pack['mod_id']}")
            continue

        generate_pack_cover(pack)
        sounds = parse_sound_scripts(mod_dir)
        ui_map = load_ui_translations(mod_dir)
        raw_tracks = parse_albums(mod_dir, ui_map, sounds, pack["pack_name"])
        print(f"[PACK] {pack['mod_id']} ({pack['workshop_id']}): {len(raw_tracks)} tracks queued for spectral onset analysis...", flush=True)

        tasks = [(i, tr, pack["mod_id"], ffmpeg_exe) for i, tr in enumerate(raw_tracks)]
        results: List[Optional[dict]] = [None] * len(tasks)
        with concurrent.futures.ProcessPoolExecutor(max_workers=12) as pool:
            for idx, entry in pool.map(analyze_track, tasks, chunksize=4):
                results[idx] = entry

        analyzed = [r for r in results if r is not None]
        out_lua = write_pack_lua(pack, analyzed)
        kb = out_lua.stat().st_size / 1024.0
        print(f"  -> Wrote {len(analyzed)} tracks -> {out_lua.name} ({kb:.1f} KB)", flush=True)
        installed_packs.append(pack)

    cat_path = write_catalog_loader(installed_packs)
    elapsed = time.perf_counter() - t_start
    print(f"[DONE] Wrote {cat_path.name} in {elapsed:.2f}s.")


if __name__ == "__main__":
    main()
