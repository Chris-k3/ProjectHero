# Bryson Kelly — Zomb-Band song catalog

All song author/music credits: **Bryson Kelly**. Mod author: **HUNK**.

| Song | Duration | Lead notes: Easy / Normal / Hard / Expert |
|---|---:|---|
| 52 BOMBOCLAT pussy wagon chicken nuggets | 2:26 | 109 / 207 / 372 / 636 |
| Beat Wick IV | 2:55 | 72 / 73 / 75 / 75 |
| City Lights Cruise | 3:05 | 181 / 313 / 396 / 594 |
| Cybernetic Passage | 5:55 | 192 / 328 / 612 / 743 |
| Eat My Dust | 3:07 | 147 / 280 / 453 / 542 |
| Foot On Da Ga$ [ Rally House] | 1:24 | 74 / 139 / 234 / 295 |
| FUTUREXMYMIND | 2:17 | 123 / 214 / 425 / 540 |
| I Think I'm in Love with My DJ female | 2:26 | 130 / 219 / 387 / 500 |
| Press Start | 2:38 | 134 / 262 / 485 / 642 |
| Runner's Dilemma | 2:14 | 82 / 141 / 232 / 288 |
| Spinning Around in My Head | 3:42 | 167 / 307 / 527 / 877 |
| Study Flow | 2:40 | 154 / 244 / 321 / 395 |
| Turn It Up, Let It Drop | 2:45 | 156 / 270 / 551 / 637 |
| Where My Wife At_ | 1:34 | 57 / 103 / 143 / 197 |

Four lanes on all difficulties. Charts are automatic full-mix arrangements anchored to detected attacks in the exact mono PCM playback files. They are not manually authored transcriptions or isolated instrument stems. Guitar/keys/wind instruments use the lead chart; bass uses its bass chart. Raw percussion analysis remains available in the data, but drumsticks/drumsets/vocals are not playable parts.

BPM values are display estimates; runtime notes use absolute milliseconds and preserve rests/tempo changes without a constant-grid drift. Audio conversion preserves the original full track length. Notes begin after 2.4 seconds for visual approach.

See song-charts/validation.json for source/playback waveform checks and song-charts/Song_1.json through Song_14.json for editable charts and detected attacks. All tracks are 44.1 kHz mono PCM for positional playback.

Rebuild from an extracted MP3 folder with python tools/build_songpack.py INPUT_FOLDER --artist "Bryson Kelly". This regenerates the PCM files, Lua catalog, manifests and playback sound registrations. Back up hand-edited charts first. Deploy the same rebuilt catalog to every client/server. Album art can be supplied using each catalog entry's cover field; otherwise the library uses its placeholder.
