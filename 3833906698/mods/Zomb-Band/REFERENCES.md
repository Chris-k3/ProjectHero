# Research references

Zomb-Band v0.4.0 is credited to HUNK. Its internal HUNKBand Lua/module names are retained for compatibility.

For positional audio and zombie noise, additionally checked the official [IsoWorld world-emitter API](https://projectzomboid.com/modding/zombie/iso/IsoWorld.html), [BaseSoundEmitter](https://projectzomboid.com/modding/zombie/audio/BaseSoundEmitter.html), [GameSoundClip distance fields](https://projectzomboid.com/modding/zombie/audio/GameSoundClip.html) and [WorldSoundManager](https://projectzomboid.com/modding/zombie/WorldSoundManager.html). Client playback explicitly disables automatic world-noise generation; separate server pulses use the band's bounded AI radius. Engine integration still requires a live check.

All four repositories supplied by the user were inspected on 2026-11-02. The mod is an original Lua implementation of rhythm-game concepts. It does not embed these engines, compile their code into Zomboid, or include their game executables, songs or visual assets.

## Ketbome/gh3-decomp

[Repository](https://github.com/Ketbome/gh3-decomp), reviewed tree `5f24db7eb69ed9f3772bfe9124927670cf42405f`.

Read the README and [CFunc_CheckNoteHoldEnd.cpp](https://github.com/Ketbome/gh3-decomp/blob/5f24db7eb69ed9f3772bfe9124927670cf42405f/nonmatching/CFunc_CheckNoteHoldEnd.cpp). This partial PS2 decompilation distinguishes note-hold initialization, waiting, starting, per-frame handling and ending; several entries remain assembly placeholders. It informed the explicit scope distinction between tap-note state and future sustained-note state. The mod reserves `durationMs` in its note model but currently uses zero-duration taps. No hold/whammy implementation was copied or claimed complete.

## freeqaz/rb3-xenon

[Repository](https://github.com/freeqaz/rb3-xenon), reviewed tree `fe7a8eb01e8bf171180ed89bbe5b602651e9518b`.

Read [GameGem.h](https://github.com/freeqaz/rb3-xenon/blob/fe7a8eb01e8bf171180ed89bbe5b602651e9518b/src/system/beatmatch/GameGem.h) and [TrackWatcherImpl.cpp](https://github.com/freeqaz/rb3-xenon/blob/fe7a8eb01e8bf171180ed89bbe5b602651e9518b/src/system/beatmatch/TrackWatcherImpl.cpp). Time-stamped gems, played state, polling for passed notes and explicit synchronization offsets informed the separation of immutable charts from per-performance judgments, periodic miss expiration and the fixed per-round gameplay clock. The Lua logic and network protocol were written for this mod; the thresholds are this mod's own values.

## sp00nznet/gh3

[Repository](https://github.com/sp00nznet/gh3), reviewed tree `e7d5d6a0c38dc5ad5a6c5a3625ebe8dd004c5e2b`.

Read the README and [songloop.sh](https://github.com/sp00nznet/gh3/blob/e7d5d6a0c38dc5ad5a6c5a3625ebe8dd004c5e2b/tools/harness/songloop.sh). This is a native recompilation/configuration project rather than a drop-in rhythm library. Its repeated setlist-to-gameplay-to-results tests, completion checks and notes about frame/input/audio timing informed the mod's full-song regression runs and explicit limits on what mocked tests establish. No shell harness was incorporated or executed.

## DarkRTA/rb3

[Repository](https://github.com/DarkRTA/rb3), reviewed tree `5e34ff1a592632fcf7f0f067c56f8e91b403ae92`.

Read [TrackWatcherImpl.h](https://github.com/DarkRTA/rb3/blob/5e34ff1a592632fcf7f0f067c56f8e91b403ae92/src/system/beatmatch/TrackWatcherImpl.h) and [Scoring.h](https://github.com/DarkRTA/rb3/blob/5e34ff1a592632fcf7f0f067c56f8e91b403ae92/src/band3/game/Scoring.h). Separate hit, miss and pass events, difficulty-change handling, and streak/multiplier concepts informed the shared Lua judgment model, per-player difficulty and multiplier reset behavior. The final score rules are intentionally simple original rules, not a reproduction of RB3's scoring tables.

## Zomboid integration references

Checked the official APIs for [BaseCharacterSoundEmitter](https://projectzomboid.com/modding/zombie/characters/BaseCharacterSoundEmitter.html), [GameKeyboard](https://projectzomboid.com/modding/zombie/input/GameKeyboard.html), [UIElement](https://projectzomboid.com/modding/zombie/ui/UIElement.html) and [LuaManager.GlobalObject](https://projectzomboid.com/modding/zombie/Lua/LuaManager.GlobalObject.html).

Also inspected mirrored vanilla Lua for ISUIElement, ISComboBox, ISButton and ISWorldMap in [ProjectZomboid-Vanilla-Lua](https://github.com/AndreaRobertoBenvenuti/ProjectZomboid-Mods/tree/claude/zomboid-lua-setup-m6fsG/ProjectZomboid-Vanilla-Lua/client). This resolved actual combo-box method names and the UI key-down/consumption interface. It does not substitute for running the particular installed Build 42 version.

## Music analysis

The song builder uses librosa's documented onset-strength, onset-detection, HPSS, STFT and beat-tracking APIs, with soundfile decoding and FFmpeg conversion. The installed library signatures/docstrings were checked during implementation. Charts are generated from the final converted playback files, with independent lead/bass/percussion event streams and deterministic difficulty thinning. Audio analysis does not establish isolated instrument transcription or guaranteed device-level playback alignment.
