# Zomb-Band v0.9.1 / HUNK — Fail-out sound

Adds a short local fail-out sting using the uploaded Rock Band (iOS) overdrive-end.wav cue. It runs once for a server-confirmed musician failure, stops menu/startup voices first, and continues briefly as that musician returns to the library. Ordinary misses, predicted health reaching zero, stale packets and duplicate failure packets do not play it. Remaining band members continue their music; this UI effect produces no zombie/world sound. Exiting, disconnecting or entering another round cleans it up.

No tracks, charts, timing, sound definitions, camera files or network protocol changed. This remains protocol 8 and is compatible with the v0.9.0 catalog. Mod author: HUNK. Songs: Bryson Kelly. The existing effect extraction credit to teh_supar_hackr remains.

Custom YouTube-link playback is not included in this patch. The current Zomboid playback path uses registered local audio files. Matching audio, generated charts and a readiness/start handshake are needed on every client. A separate companion importer/player is required for a link-preparation workflow; simply opening a YouTube URL in each browser cannot provide the same gameplay synchronization. No nonfunctional URL-entry field has been added.

Validation: 49 gameplay/network/library groups, 18 director groups and eight production catalog/menu audio groups pass in Lua 5.1 and the installed game's Kahlua engine (75 per engine). Game/UI audio services in these tests are mocked. New cases exercise authoritative-failure dispatch, duplicate/stale rejection, one local sting, continued library cleanup and voice shutdown. The reused cue was already verified by the native sound-module checks in v0.9.0. Live hearing of this new fail-out event remains unverified.

Restart Zomboid after updating. The supplied clip is existing audio, so this patch requires no new Java approval. Workshop artwork, HUNK author metadata and the fourteen-song catalog are retained.
