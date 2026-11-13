# Zomb-Band v0.8.1 / HUNK — Instrument Visibility and Camera Motion

This focused update fixes held instruments fading during Viewpoint cinematic shots and reduces director/render jitter. Library, songs, charts, scoring, instruments, multiplayer protocol 7 and sound radii are unchanged from v0.8.0.

## Visibility correction

Viewpoint selects camera-clear shader kind 1 for SELF models, kind 0 for ordinary/world models and kind 2 for SOLID models. The previous helper removed SELF from held props. That selected the same camera-clear cone used for walls, explaining partial or complete instrument disappearance as the lens moved.

Held hand/Prop1/Prop2 attachments now receive SOLID (128) and clear SELF (64), explicitly bypassing camera-clear fading. Ordinary depth testing, texture alpha and world occlusion remain: the change does not draw guitars through walls. Body/head masks and unrelated actors remain untouched. Both the default and Iris vertex shader paths use this flag. Remote band members receive the same scoped prop protection at capture exit during the active cinematic camera; first-person authored-pose correction stays local. The short performer lease and cleanup remain.

## Camera motion correction

- Choose the featured musician and base facing at shot boundaries, rather than re-evaluating them as chart intensity/combo/animation facing changes during a shot.
- Keep the selected camera side and distance for the shot. If an orbit grazes an obstacle, hold its last safe lens while the subject remains visible. Unsafe lenses still yield or find a safe alternative; no wall clipping is intentionally introduced.
- Prefer full-distance alternate angles before shrinking a shot. Minimum cinematic distance is now one tile rather than 0.65, reducing camera intersection with held props.
- Refresh actual musician positions on each director update, while retaining the cheaper 250ms membership lookup cache.
- Native render interpolation now uses one atomic transition snapshot, adapts its 16–100ms interpolation duration to actual pose-update cadence and retargets from the current rendered lens. Early/late updates no longer rewind toward an old target. Intentional cuts between shots remain cuts; yaw interpolation takes the shortest arc.

## Installation

Save and exit Zomboid normally, fully quit to the desktop, then restart after the update. Lua reload cannot replace the running Java companion. Keep Zomb-Band, Zomb-Band - Cinematic Camera, Viewpoint and ZombieBuddy enabled. Approve this revised companion if ZombieBuddy prompts. No global camera/shader files or Java approval settings are modified.

The local installer backs up the prior mod folders and verifies installed files by SHA-256. The ZIP also contains the unchanged optional test kit. Existing v0.8.0 clients/server remain network-compatible (protocol 7); each viewing client needs this updated companion/Lua director for these visual fixes.

## Verification

47 gameplay/library/network groups plus 18 director groups pass in Lua 5.1 and the actual game's Kahlua engine: 65 per engine. Game world/UI/network services are mocked. New director cases verify stable subjects/facing, obstacle-safe held lenses and fresh cached actor positions.

Native checks use installed Viewpoint 0.1.6.1 and ZombieBuddy 2.3.4: real model buffers confirm SOLID on local and remote band props, GPU flag updates, body/head/outsider isolation and cleanup; the actual default/Iris shader contracts are checked. All three hook injection signatures, Lua class export/version, lens coordinates, control restoration and timeout are verified. An irregular 7/19/45/11/60ms update test verifies continuous retargeting, bounded interpolation, short yaw arcs and explicit cuts.

The user confirmed v0.8.0 cinematic shots were working. This patch's new visual results have not yet been observed in a restarted game; these automated/native checks are not a live GPU playtest. Test a full shot cycle with CAMERA CHECK and a song after restarting.


Build: javac --release 17 -cp "<Viewpoint.jar>;<ZombieBuddy.jar>" -d build/classes src/hunk/zombband/camera/*.java
Package: jar cf 42/media/java/client/ZombBandCamera.jar -C build/classes .
