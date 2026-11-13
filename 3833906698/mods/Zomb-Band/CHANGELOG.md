# Zomb-Band 0.10.0 / HUNK

- Repair Random Song for the game Lua API.
- Add a real Custom Song URL panel, independent asynchronous media bridge, automatic PCM attack charts, host-owned registry and hash-bound all-player readiness.
- Explicit blocking/errors prevent custom requests falling back to bundled songs.
- Protocol 10; optional custom companion and tools required. Live URL/multi-machine audio remains unverified.

# Zomb-Band 0.9.2 / HUNK

- Play waits automatically for all prepared musicians; shows synced count and provides Cancel Wait.
- Adds server-validated preparation stamps and revisions; track/part changes, replay and setlist advance invalidate readiness.
- Preloads current charts as well as audio and clock calibration before acknowledging.
- Protocol 9 requires the updated client/server. Eighty groups per Lua engine pass; live post-update MP remains unverified.
- Existing fourteen songs, fail sting, sound radii and cinematic camera remain unchanged. Custom-link backend is not included.

# Zomb-Band 0.9.1 / HUNK

- Adds a local uploaded ending sting on authoritative fail-out, once per musician/round.
- Stops menu/startup effects before the fail cue; retains it through the return to library and clears it on exit/new round.
- Preserves fourteen songs, notes, multiplayer protocol 8, camera files and sound registrations.
- 75 groups per Lua engine pass. New in-game fail-cue audibility remains unverified.

# Zomb-Band 0.9.0 / HUNK

- Replaces the entire song catalog with fourteen Bryson Kelly tracks and new attack-aligned four-lane charts; removes demos.
- Adds supplied Rock Band (iOS) UI navigation/confirmation/back and synchronized pre-song startup cues; credits extraction to teh_supar_hackr.
- Adds stable song UIDs and a separate V2 profile to prevent old slot-number records binding to unrelated tracks.
- Protocol 8 requires matching updated catalogs. Camera companion/director remain unchanged from 0.8.1.
- 73 groups per Lua engine, 103 native sound registrations and complete audio/chart integrity checks pass. Live post-update audibility remains unverified.

# Zomb-Band v0.8.1 / HUNK â€” Instrument Visibility and Camera Motion

This focused update fixes held instruments fading during Viewpoint cinematic shots and reduces director/render jitter. Library, songs, charts, scoring, instruments, multiplayer protocol 7 and sound radii are unchanged from v0.8.0.

## Visibility correction

Viewpoint selects camera-clear shader kind 1 for SELF models, kind 0 for ordinary/world models and kind 2 for SOLID models. The previous helper removed SELF from held props. That selected the same camera-clear cone used for walls, explaining partial or complete instrument disappearance as the lens moved.

Held hand/Prop1/Prop2 attachments now receive SOLID (128) and clear SELF (64), explicitly bypassing camera-clear fading. Ordinary depth testing, texture alpha and world occlusion remain: the change does not draw guitars through walls. Body/head masks and unrelated actors remain untouched. Both the default and Iris vertex shader paths use this flag. Remote band members receive the same scoped prop protection at capture exit during the active cinematic camera; first-person authored-pose correction stays local. The short performer lease and cleanup remain.

## Camera motion correction

- Choose the featured musician and base facing at shot boundaries, rather than re-evaluating them as chart intensity/combo/animation facing changes during a shot.
- Keep the selected camera side and distance for the shot. If an orbit grazes an obstacle, hold its last safe lens while the subject remains visible. Unsafe lenses still yield or find a safe alternative; no wall clipping is intentionally introduced.
- Prefer full-distance alternate angles before shrinking a shot. Minimum cinematic distance is now one tile rather than 0.65, reducing camera intersection with held props.
- Refresh actual musician positions on each director update, while retaining the cheaper 250ms membership lookup cache.
- Native render interpolation now uses one atomic transition snapshot, adapts its 16â€“100ms interpolation duration to actual pose-update cadence and retargets from the current rendered lens. Early/late updates no longer rewind toward an old target. Intentional cuts between shots remain cuts; yaw interpolation takes the shortest arc.


# Zomb-Band 0.8.0 / HUNK

- Three saved library styles, full yellow selection, font-aware responsive layout, detailed pages, fifteen sorts and nine collections.
- Named playlists, random selection, server-authoritative consecutive setlists and inventory-validated instrument changes. Protocol 7 requires matching peers.
- Results/failure return to the same reusable library; direct Play handles the next round.
- Corrects ZombieBuddy equal-name alias deletion of the camera's Lua global, proven through the actual exporter and Kahlua.
- Adds a slower library preview and scoped first-person authored-pose/held-prop rendering hooks.
- Preserves seven tracks/timings, four lanes, vanilla item exclusions, synchronization, sound range and 12-tile maximum zombie attraction.
- 62 groups per Lua engine plus native/asset checks. Live rendering after restart remains unverified.

# Zomb-Band 0.7.0 - HUNK

- Replaces the basic dropdown front end with a full interactive music library: search, collections, favorites, five sorts, details/covers, keyboard/mouse browsing, local intro previews and per-character records.
- Adds original concert/notebook artwork and framing. Leaves the rhythm highway and gameplay protocol in place.
- Corrects stale song selection after filtering; keeps band song IDs stable and host permissions/readiness intact.
- Repairs camera start gating and stale walkability rejection; adds Camera Check, native frame confirmation, visible/logged fallback reasons and retry behavior.
- Prevents the observed vanilla hotbar key-hold exception while our UI consumes rhythm keys.
- Retains instruments, seven songs, multiplayer/audio/failure behavior and the 12-tile zombie limit. Protocol remains 6.
- 51 groups per Lua engine plus native checks pass. Live post-update camera movement remains unverified.

# Zomb-Band 0.6.0 - HUNK

- Four lanes on every difficulty; absolute song timestamps retained.
- Original arcade menu and perspective performance overlay, hit effects, lane flashes, beat lines, score/combo/multiplier and ROCK meter.
- Server-authoritative recoverable failure; failed musicians leave while survivors continue.
- Optional client-only Viewpoint/ZombieBuddy cinematic companion: eight moving shot styles, shared-clock shot cadence, local camera controls, activity/streak subject selection, band framing, conservative collision sweeps and normal-camera fallback.
- Camera/control restoration and automatic overlay closure on every exit; native watchdog restores both if updates stop.
- Preserves all seven songs, instrument rules, positional audio and the 12-tile zombie-attraction maximum. Protocol 6 requires matching main versions.
- Adds native Viewpoint ABI checks, ZombieBuddy/ByteBuddy injection dry run and failure/director/overlay regressions. Live camera, poses and audibility are still unverified.

# Zomb-Band 0.5.1 - HUNK

- Fixes all three sound modules being skipped by the game loader: replaces unsupported leading // comments with /* ... */ comments.
- Fixes both audio generators so rebuilding songs cannot reintroduce that error.
- Adds an integration regression using the installed game's module loader, sound bucket and GameSounds registry. Original v0.5.0 registers zero sounds; v0.5.1 registers 70, and every runtime song/test name resolves.
- Removes 315 animation channels targeting five helper/end nodes rejected by the installed game's skeleton importer. Keeps the hierarchy, remaining animation channels and binary data intact. Visible poses still need live verification.
- Preserves all seven songs and charts, instrument rules, multiplayer code, author HUNK, and the 12-tile zombie-attraction cap.

# Zomb-Band 0.5.0 - HUNK

- Bundles instrument playing loops adapted from the user-supplied PlayIt archive: seven families, 21 standing/seated/ground variants, plus a cosmetic violin bow.
- Uses native timed actions and matching hand-model overrides without overwriting equipped items.
- Adds cleanup when the performance ends or the player leaves/is interrupted.
- Preloads the actual backing audio before the shared countdown.
- Uses owned, explicitly ticked world emitters and checks for missing definitions/zero native handles.
- Adds mono PCM positional backing tracks on explicit Primary/effects routing with fresh sound IDs.
- Adds an AUDIO TEST button and visible/logged audio failure reasons.
- Preserves song chart times, the ten vanilla instrument rules, test-kit compatibility and the 12-tile maximum zombie-attraction radius.

The prior issue could continue scrolling notes after a sound returned no usable handle. The new failure checks cover that path. The update has not been audibly/visually verified in a live game; see README and TEST_RESULTS.
