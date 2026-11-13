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

---
Previous release notes:

# Zomb-Band v0.9.2 / HUNK — Wait for the Whole Band

Press Play once. The band stays in its lobby while participants prepare the selected track, their instrument chart and clock synchronization. PREPARING SONG shows the prepared count, such as 3/4 synced. Only when all current participants have confirmed the current preparation does the host request the existing shared five-second countdown. There is no fixed short timer that forces an unprepared musician into the song.

The Play button becomes CANCEL WAIT while waiting. Cancel keeps the band in its lobby; players becoming ready afterward cannot start it automatically. A new Play request can resume waiting. Normal leave/disconnect and abandoned-lobby cleanup still apply; the existing idle-lobby lifetime is ten minutes.

Readiness is tied to a preparation revision, song UID/duration, instrument, difficulty and chart note count. Changing a track or part invalidates preparation. Replay and advancing a setlist require fresh acknowledgments. Late acknowledgments for a prior revision do not unlock the new setup. Both the host's automatic start check and the server validate the current acknowledgments. Local chart generation and muted PCM warm-up must succeed; multiplayer clients also need clock samples before acknowledging readiness. A missing sound definition still blocks solo creation with its existing visible error.

This update applies to the existing fourteen-song Bryson Kelly catalog. It does not add URL downloading, live-stream playback or automatic charts for pasted links. A future custom-media backend must report its decoded audio/chart readiness through this gate, including exact custom-content/audio/chart hashes. The current built-in catalog uses its packaged song UID and current part/revision identity; it does not independently hash each PCM file at runtime or prove cross-machine sample-perfect output latency.

Protocol is now 9. Update the host/server and all clients to v0.9.2 and restart. Previous protocol-8 clients are deliberately rejected. Mod author HUNK, song author/artist Bryson Kelly, the v0.9.1 fail-out cue, all music/charts, camera companion and poster artwork remain.

Validation: 54 gameplay/network/library groups, 18 director groups and eight production-catalog/menu groups pass in Lua 5.1 and installed-game Kahlua (80 per engine). Game/network/UI/FM0D APIs in those suites are mocked. New cases verify a 20-second slow-member wait with zero performance noise, a future five-second start after the last ready acknowledgment, cancellation, stale acknowledgments, setup/replay invalidation and recovery from a local chart-preparation failure. Live multiplayer behavior after this update still needs an in-game playtest.

---
Previous release documentation:

# Zomb-Band v0.9.1 / HUNK — Fail-out sound

Adds a short local fail-out sting using the uploaded Rock Band (iOS) overdrive-end.wav cue. It runs once for a server-confirmed musician failure, stops menu/startup voices first, and continues briefly as that musician returns to the library. Ordinary misses, predicted health reaching zero, stale packets and duplicate failure packets do not play it. Remaining band members continue their music; this UI effect produces no zombie/world sound. Exiting, disconnecting or entering another round cleans it up.

No tracks, charts, timing, sound definitions, camera files or network protocol changed. This remains protocol 8 and is compatible with the v0.9.0 catalog. Mod author: HUNK. Songs: Bryson Kelly. The existing effect extraction credit to teh_supar_hackr remains.

Custom YouTube-link playback is not included in this patch. The current Zomboid playback path uses registered local audio files. Matching audio, generated charts and a readiness/start handshake are needed on every client. A separate companion importer/player is required for a link-preparation workflow; simply opening a YouTube URL in each browser cannot provide the same gameplay synchronization. No nonfunctional URL-entry field has been added.

Validation: 49 gameplay/network/library groups, 18 director groups and eight production catalog/menu audio groups pass in Lua 5.1 and the installed game's Kahlua engine (75 per engine). Game/UI audio services in these tests are mocked. New cases exercise authoritative-failure dispatch, duplicate/stale rejection, one local sting, continued library cleanup and voice shutdown. The reused cue was already verified by the native sound-module checks in v0.9.0. Live hearing of this new fail-out event remains unverified.

Restart Zomboid after updating. The supplied clip is existing audio, so this patch requires no new Java approval. Workshop artwork, HUNK author metadata and the fourteen-song catalog are retained.

---

# Zomb-Band v0.9.1 / HUNK — Bryson Kelly Collection

The existing mod now plays the fourteen songs from the supplied Project Zomboid.rar. **All song author/music/artist credits: Bryson Kelly. Mod author: HUNK.** The previous seven-entry catalog is replaced, including Last Transmission and Safehouse After Dark. Clarity and Always Present are not in the new catalog; FUTUREXMYMIND, Press Start and Spinning Around in My Head return from the new archive with freshly generated charts.

## What changed

- Fourteen full-length positional PCM tracks, four lanes on every difficulty, and 168 role/difficulty charts (14 × three analyzed roles × four difficulties).
- Bryson Kelly appears in the song list, details, original cover artwork and chart manifests. Untagged albums/genres/years remain untagged.
- Supplied move/select/back variations throughout the music library, plus a local instrument/crowd/transition startup sequence tied to the existing five-second song countdown.
- The DEMOS collection and old demo/old-song audio registrations are removed.
- Records, favorites and playlists use stable song UIDs so changing catalog order cannot attach a result to another track. The new profile uses ZombBandLibraryV2. Old V1 data remains in the character save, but numeric-ID records/playlists/favorites are not applied to the replacement catalog. The saved presentation style carries over.
- Protocol is now 8 to reject mismatched old song catalogs. Install v0.9.1 and the same catalog on every client and the server.

The library/setlists, ten supported vanilla instruments, synchronized music clock, four-lane scoring/failure meter and positional sound/zombie radii remain. The working v0.8.1 camera companion and director are unchanged byte-for-byte. Mod ID remains HUNKSurvivorBand; the optional test kit is unchanged.

## Menu and startup audio

32 supplied effects were converted to stereo 44.1 kHz PCM and registered as non-spatial UI sounds. Navigation cycles four movement variants, thirteen confirmation variants and three back variants; repeated navigation is rate-limited and replaces the previous menu voice instead of stacking long clips.

For participating players, the pre-song sequence uses:

- -5.00 seconds: a guitar intro for stringed instruments, or the generic startup cue for other instruments.
- -4.50 seconds: amplifier/crowd or cheers, varying between rounds.
- -1.85 seconds: transition swoosh.
- 0.00 seconds: startup voices stop and the existing synchronized backing track starts.

The long guitarstartup_a cue was shortened to 4.7 seconds with a 200ms fade so it fits the five-second countdown. No track intro is trimmed, and no cue changes the song start time. Late updates skip stale cues rather than playing the entire sequence at once. Closing/leaving/disconnecting cleans up voices. Spectators do not receive participant UI startup cues; they still hear the normal nearby positional performance.

The five clips without a matching current feature (drums, the ambiguous ca/ea clips and the two overdrive activation clips) are included as reserved assets, with no invented drumset or overdrive gameplay. All UI/menu/preview/startup sounds are local and generate no zombie AI noise. They follow game UI/Sound volume settings. Original effect source is Rock Band (iOS); extraction credit is teh_supar_hackr, as identified in the supplied archive. These are separate from Bryson Kelly's song credits; see CREDITS.md.

## Songs and charts

See SONGS.md for the full fourteen-track list and note counts. Charts were derived from harmonic/percussive attacks in the exact final playback WAVs. Easier difficulties are timestamp subsets of harder charts; lead and bass use their respective analyzed ranges. Runtime notes use absolute milliseconds, not a constant-BPM grid. The BPM displayed in the library is an estimate.

These are playable automatic arrangements from full mixes, not manually authored note-for-note instrument transcriptions or isolated stems. Misses affect the existing score/ROCK meter; there are no separated parts to mute. Raw percussion analysis is retained, but drumsticks, drumsets and vocals remain unavailable gameplay parts. Supported vanilla instruments still use the existing lead/bass roles and animations.

Full mixes are 44.1 kHz mono PCM for positional playback. Source-to-playback waveform comparisons found zero measured offset in the checked windows, with correlations above 0.98 for all fourteen tracks. All chart timestamps correspond to detected attacks in those playback files. This validates conversion/chart integrity, not subjective chart quality or live audio-device latency.

## Installation and verification

Save and exit Zomboid normally, fully quit to the desktop, then restart after installing. The game's cached sound definitions must reload for the new tracks and cues. The local installer backs up the old mod before copying the update, removes only the obsolete known song audio files, and verifies every installed source file by SHA-256. The camera JAR is unchanged, so this update does not require a new camera binary approval.

Enable Zomb-Band; retain the existing cinematic companion/Viewpoint/ZombieBuddy setup if using cinematic shots. The ZIP also includes the unchanged companion and optional test kit for fresh installations. Audible music range stays 16 + 4 tiles per extra musician (maximum 36); zombie attraction stays 6/8/10/12/12/12 tiles, one pulse per band per second only during actual music.

75 groups pass per engine in Lua 5.1 and the installed game's Kahlua: 49 gameplay/network/library groups (legacy fixtures plus a delayed-network consecutive performance using two real replacement songs), 18 director groups and eight production-catalog/menu-audio groups. Game services are mocked. The actual native script/module loader registers 103 sounds: 55 retained instrument effects, 14 tracks, the diagnostic tone, 32 supplied UI effects and one silent click-suppression cue. It verifies file references, spatial flags and removal of obsolete song registrations.

Offline checks validate all fourteen waveforms, 168 charts, 32 effects, artwork and asset references. Live audible playback after this update has not yet been verified. UI preview PNGs are rendered from actual Lua draw commands on a neutral background with approximate fonts; they are not in-game camera screenshots.

To rebuild future song packs, extract MP3s to a folder and run tools/build_songpack.py INPUT_FOLDER --artist "Bryson Kelly" after installing tools/requirements.txt. This regenerates PCM/chart/catalog/registration files; back up manual edits first. Deploy identical output to all clients/server.
