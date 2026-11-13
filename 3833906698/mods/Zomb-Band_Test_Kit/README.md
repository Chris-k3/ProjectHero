# Zomb-Band — Instrument Test Kit

Optional addon · Author: **HUNK** · Mod ID: `HUNKZombBandTestKit`

Put this folder beside `Zomb-Band` in `C:\Users\<your name>\Zomboid\mods\`. Enable **Zomb-Band** and **Zomb-Band - Instrument Test Kit**, then enter a save. Within a few seconds, the character receives the ten supported vanilla instruments in their inventory. Right-click one and choose **Rock Out...**.

The kit includes an acoustic guitar, electric guitar, electric bass, banjo, flute, harmonica, keytar, saxophone, trumpet and violin. It does not include drumsticks, whistles or accessories. Instruments already carried count toward the kit, so existing copies are not duplicated.

Each character receives the kit once. Reloading, reconnecting and repeated requests do not add more instruments. Dropping an instrument does not replenish it. A new character can receive a fresh kit. Items already granted remain normal vanilla inventory items if this addon is disabled.

Disable the addon when testing is finished. The ten real items have their usual weight; drop unused instruments if the character becomes encumbered. The main Zomb-Band mod does not spawn any items when this addon is disabled.

For multiplayer, install/enable the addon on the server and clients, with both Mod IDs: `HUNKSurvivorBand;HUNKZombBandTestKit`. Each character who enters that test server can receive their own kit. Grants run on the server and use vanilla inventory replication; clients cannot request other item types or target another player.

The saved per-character marker is `player:getModData().ZombBandTestKitV1`. This is a test convenience, not a new item or loot distribution change.
