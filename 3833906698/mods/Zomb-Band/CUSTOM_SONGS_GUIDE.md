# Zomb-Band — Custom Songs, Guitar Hero III UI & Instrument Modes

## Ways to add custom songs

1. **Permanent Mod Song Pack (Recommended — works in SP & MP with native 3D FMOD audio & previews):**
   - Drag and drop `.mp3`, `.wav`, `.ogg`, `.m4a`, `.flac` files or Clone Hero folders (`song.ini` + `notes.chart` + audio) onto `AGREGAR_CANCIONES.bat`, OR run `python tools/add_songs.py <file_or_youtube_url>`.
   - Converts audio to 44.1 kHz 16-bit mono PCM WAV, generates multi-band 5-role charts (`lead`, `rhythm`, `bass`, `drums`, `vocals`) + cover art, and registers everything automatically in `HUNKBand_UserSongs.lua` and `HUNKBand_UserSongs.txt`.

2. **In-Game Local Folder (`%USERPROFILE%/Zomboid/ZombBand/songs/`) or YouTube URLs:**
   - Put `.wav`, `.mp3`, `.ogg`, `.m4a`, `.flac`, or Clone Hero folders inside `%USERPROFILE%/Zomboid/ZombBand/songs/`.
   - Open Rock Out -> **CUSTOM SONG**, then either choose a track from **LOCAL SONGS** and click **LOAD LOCAL**, OR paste an HTTPS YouTube link / file path and click **LOAD URL / FILE**.
   - Local `.wav` files decode with pure Java even without `ffmpeg`. `.mp3`/`.ogg`/YouTube links auto-detect `ffmpeg` and `yt-dlp` from `Zomboid/ZombBand/bin`, `ViewpointTV/bin`, system `PATH`, or Python `Scripts`/`imageio_ffmpeg`.

## Guitar Hero III Controls & Visual Modes

- **Play Keys:** `1`, `2`, `3`, `4` (or `A`, `S`, `D`, `F`), plus `Space` for Drums Kick Pedal / Lane 1!
- **HUD Position:** Click `HUD: CENTER` / `HUD: SIDE` in the bottom bar while playing to toggle between Guitar Hero III centered view and side-docked view.
- **UI Themes:** Style #1 in the Setlist defaults to **GUITAR HERO III** (crimson/gold stage theme); cycle with `STYLE:` between Guitar Hero III, Rock Band, Notebook, and Arcade.

---
# Zomb-Band 0.10.0 / HUNK — Custom URL Songs (experimental)

Random Song is repaired: Project Zomboid omits math.random. Selection now uses ZombRand, honors the displayed collection and current instrument/difficulty, avoids the current song when alternatives exist, and reports an empty collection. Only the host changes the band track.

## Enable and use

1. Restart the game after updating. Enable **Zomb-Band** and the included **Zomb-Band - Custom Songs** companion plus **ZombieBuddy** on every participating player's computer. Permit the companion through ZombieBuddy's normal Java-mod prompt if shown. The custom companion does not require Viewpoint. Cinematic Camera remains a separate optional module.
2. The host/server and every client need main version 0.10.0 / protocol 10. The dedicated server runs the Lua registry/validation; it does not download or play media.
3. Open Rock Out and choose **CUSTOM SONG** above Random Song. Paste an HTTPS YouTube video URL, then **LOAD URL**. Downloading, decoding, analysis, errors and cancellation appear in this panel. A failed/pending load blocks Play/Form Band; it cannot silently play a bundled song. BACK TO LIBRARY explicitly leaves this flow.
4. Once prepared and registered, the custom track is selected in ALL SONGS / YOUR TRACKS. Press PLAY SOLO, or FORM BAND so friends can join. In a waiting band, only the host can load/change the URL. Load URLs between performances; leave/reset a results session first.
5. Press START BAND once. Each joined musician prepares their own copy, output device and chart. Exact decoded-PCM SHA-256 and chart SHA-256 must match the host, in addition to the current preparation revision/instrument/difficulty. The lobby shows the ready count and waits for everyone, then schedules the existing shared five-second countdown. Cancel Wait cancels starting; CANCEL LOAD/closing the interface also cancels pending media work.


A joining band member can open CUSTOM SONG and choose RETRY MY AUDIO to retry the host-selected track without changing its URL. Cancellation/retry withdraws local readiness; the host continues waiting. If the PCM/chart hash differs, all musicians must use matching source/cache/tool versions.

## Media tools

This original bridge uses **separately installed yt-dlp and FFmpeg**. On this computer, both were found at C:/Users/Bryso/Zomboid/ViewpointTV/bin/win-x64. Existing Working TVs code or binaries have not been copied into Zomb-Band.

Other Windows clients can initialize their own Working TVs media tools, or put their separately obtained yt-dlp.exe and ffmpeg.exe in `%USERPROFILE%/Zomboid/ZombBand/bin`. Linux lookup uses the corresponding extensionless executables (including ViewpointTV/bin/linux-x64), but this release was tested only on Windows. No Python installation is required in the game. Missing/outdated tools, denied connections, unavailable videos and unavailable audio devices produce errors and block readiness. Downloaders may need updates as sites change. There is no automatic software updater in this companion.

Only a single finite video is accepted, from five seconds to eight minutes, with source/PCM size limits. Live streams and playlist playback are unavailable; a video URL with an accompanying playlist parameter loads only that video. Media is cached under Zomboid/ZombBand/cache/<video ID>. Each client downloads its own audio; this is not streaming the host's desktop audio to friends. Download/decoding/analysis/output-device opening run in a worker thread, with process cancellation and deadlines.

## Charts, timing and scope

New tracks use a deterministic PCM attack/energy analysis, not evenly spaced fake BPM notes. Difficulty levels use nested subsets of the same detected attacks, with four lanes and a three-part lead/bass/percussion chart structure. These are automatic rhythm arrangements, not manual instrument transcriptions, separated stems or official Guitar Hero/Rock Band charts. Custom video artist metadata is shown as "Custom YouTube audio"; it is not credited to Bryson Kelly. The fourteen bundled recordings retain Bryson Kelly's credits. Mod author: HUNK.

The server validates the bounded chart and owns the chosen custom track; notes/metadata are delivered in a bounded message (maximum 65 KB chart text / 5,000 attacks). Local decoded PCM and chart fingerprints must match before ready. Decoding differences between clients intentionally stop the countdown rather than starting different audio. All clients should use matching media-tool versions. Missing content never resolves to song 1 for a performance.

The custom audio path uses a Java Sound output device, a monotonic scheduled start, exposed playback cursor and correction for drift above 65 ms. It follows game Sound volume, distance attenuation (including floor separation), stereo spread and the existing bounded server zombie radius. It is separate from FMOD, so this does not establish identical hardware latency or full FMOD occlusion/HRTF. Use the existing timing calibration for input/audio-device latency. A two-second heartbeat lease stops abandoned playback. One custom band playback channel per computer; split screen remains unsupported.

Custom playback currently serves the solo performer / joined musicians. It does not force nearby non-participants to download arbitrary links; spectators do not automatically hear uncached custom media. Bundled tracks retain their existing nearby spatial FMOD playback. The library's ten-second PREVIEW INTRO remains available for bundled songs; custom previews are explicitly unavailable.

The server keeps up to 32 custom entries for its current run. Cache files and UID-keyed character records survive restarts, but re-enter a URL to register it in a new server run. Custom entries in saved playlists become resolvable again when those matching URLs are registered. Original shipped catalog/audio, instrument animations, failure sting and camera companion are retained.

## Validation and remaining testing

87 groups per Lua engine: 61 gameplay/network/UI groups, 18 director groups and eight production-catalog/menu groups. Both Lua 5.1 and the installed game's Kahlua pass. These use mocked world/network/UI APIs, including two independent client-media states and server-authoritative custom selection. Cases include missing helper, invalid media, no bundled fallback, host-only registration, exact-match preparation, cancellation and shared scheduling.

The original Java bridge compiles for Java 17 and exports successfully through the installed game's real LuaManager.Exposer / ZombieBuddy / Kahlua. An offline 60-second generated PCM fixture verifies frame counts (including long-song integer arithmetic), audio/chart SHA-256, deterministic real attack timestamps and cancellation. The actual Windows output device opened asynchronously and its scheduled **muted** PCM cursor advanced. No supplied song was played audibly by this test.

**Live YouTube downloading, audible custom performance inside Project Zomboid, and synchronization across real multiplayer computers have not been verified.** Treat custom URL playback as an experimental implementation. Download or output errors should be reported from the visible panel and Zomboid/ZombBand/cache/<video ID>/download.log or decode.log. A mismatched cached song can be removed from that one cache folder while the game is closed, then reloaded; do not delete your saves.
