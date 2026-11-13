"""Install/sync Zomb-Band III (Guitar Hero Edition) into %USERPROFILE%\\Zomboid\\mods
using separate mod IDs (ZombBandGH3*) so it never conflicts with the Steam Workshop
original (HUNKSurvivorBand / 3833906698).
"""

import os
import re
import shutil

SRC_MODS = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "mods"))
ZOMBOID_ROOT = os.path.join(os.path.expanduser("~"), "Zomboid")
DST_MODS = os.path.join(ZOMBOID_ROOT, "mods")
SONGS_DROP_DIR = os.path.join(ZOMBOID_ROOT, "ZombBand", "songs")

MAPPINGS = [
    (
        "Zomb-Band",
        "Zomb-Band_GH3",
        {
            "id": "ZombBandGH3",
            "name": "Zomb-Band III (Guitar Hero Edition)",
            "version": "0.12.0-gh3",
            "loadAfter": "\\NewMusic,\\NMGreatestHits,\\NewMusicG80s,\\NewMusicG90s,\\NewMusicG70s,\\NewMusic_CMM,\\EA_H,\\Lifestyle,\\LifestyleHobbies",
            "description": (
                "Zomb-Band III (Guitar Hero III Edition) sobre mod de HUNK. Interfaz GH3, Sound Group con restriccion "
                "real de instrumentos por cancion, canciones aprendidas y conexion directa con Tali's New Music "
                "(EA_H, NMGreatestHits, Graves 70s/80s/90s, CMM) con ritmo analizado por instrumento."
            ),
        },
        {},
    ),
    (
        "Zomb-Band_CustomSongs",
        "Zomb-Band_GH3_CustomSongs",
        {
            "id": "ZombBandGH3Custom",
            "name": "Zomb-Band III - Custom Songs",
            "version": "0.11.0-gh3",
            "require": "\\ZombBandGH3,\\ZombieBuddy",
            "description": (
                "Soporte de canciones locales (Zomboid/ZombBand/songs) y enlaces YouTube para Zomb-Band III. "
                "Activar junto a ZombBandGH3 y ZombieBuddy."
            ),
        },
        {},
    ),
    (
        "Zomb-Band_CinematicCamera",
        "Zomb-Band_GH3_CinematicCamera",
        {
            "id": "ZombBandGH3Cinematic",
            "name": "Zomb-Band III - Cinematic Camera",
            "require": "\\ZombBandGH3,\\ZombieBuddy,\\Viewpoint",
        },
        {},
    ),
    (
        "Zomb-Band_Test_Kit",
        "Zomb-Band_GH3_TestKit",
        {
            "id": "ZombBandGH3TestKit",
            "name": "Zomb-Band III - Instrument Test Kit",
            "require": "ZombBandGH3",
        },
        {},
    ),
]


def patch_mod_info(path, replacements):
    with open(path, "r", encoding="utf-8") as f:
        lines = f.read().splitlines()
    out = []
    seen = set()
    for line in lines:
        key = line.split("=", 1)[0].strip() if "=" in line else None
        if key in replacements:
            out.append(f"{key}={replacements[key]}")
            seen.add(key)
        else:
            out.append(line)
    for k, v in replacements.items():
        if k not in seen:
            out.append(f"{k}={v}")
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(out) + "\n")


def install():
    os.makedirs(DST_MODS, exist_ok=True)
    os.makedirs(SONGS_DROP_DIR, exist_ok=True)
    readme = os.path.join(SONGS_DROP_DIR, "LEEME_CANCIONES.txt")
    if not os.path.exists(readme):
        with open(readme, "w", encoding="utf-8") as f:
            f.write(
                "Coloca aqui tus canciones personalizadas para Zomb-Band III:\n"
                "- Formatos soportados: .wav, .mp3, .ogg, .m4a, .flac\n"
                "- Tambien carpetas de Clone Hero (song.ini + notes.chart + audio)\n"
                "En el juego: clic derecho en instrumento -> CUSTOM SONG -> LOCAL SONGS.\n"
            )

    for src_name, dst_name, info_patches, _ in MAPPINGS:
        src = os.path.join(SRC_MODS, src_name)
        dst = os.path.join(DST_MODS, dst_name)
        if not os.path.isdir(src):
            continue
        if os.path.exists(dst):
            shutil.rmtree(dst)
        shutil.copytree(src, dst)
        mod_info = os.path.join(dst, "42", "mod.info")
        if os.path.isfile(mod_info):
            patch_mod_info(mod_info, info_patches)
        print(f"[OK] Instalado {dst_name} (ID: {info_patches['id']}) -> {dst}")

    print(f"[OK] Carpeta de canciones locales lista: {SONGS_DROP_DIR}")


if __name__ == "__main__":
    install()
