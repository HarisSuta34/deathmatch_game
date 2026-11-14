# Block Deathmatch — project guide

Multiplayer browser game in Godot 4.3. See PROGRESS.md for the milestone checklist and current state.
The owner is new to game development: make sensible decisions, explain briefly, ask only when it matters.

## Spec (from the owner)

### The game
- 3D third-person team deathmatch, blocky Minecraft-like look. Everything built from cubes with simple colored materials. **No external assets.**
- 4 to 20 players per match, count must be even. Teams assigned randomly and always equal (2v2 … 10v10). Team colors red and blue.
- Lobby: players join/leave freely; host's Start only works when the count is even and 4–20, otherwise show "Need an even number of players (4-20) to start".
- If a player disconnects mid-match the match continues with uneven teams (even rule applies only at start).
- Each team has a base on opposite sides of the map. Spawn/respawn there, ~3 s respawn delay, short spawn protection.
- Timed matches: default 10 min, host chooses 5/10/15. More kills wins. Results screen, then back to lobby.
- 3 maps with clearly different layouts (open field with cover, narrow city streets, multi-level with ramps). Host picks the map in the lobby.
- 3 weapons: Sniper (high damage, slow, zoom scope), Assault rifle (automatic, medium damage), Shotgun (multiple pellets, strong up close).
- At match start and every respawn: loadout screen to pick a weapon or confirm the previous one. No pick within a few seconds → keep previous.
- HUD: health, ammo, timer, team scores, kill feed, crosshair. Scoreboard on Tab.
- Controls: WASD move, mouse look, LMB shoot, RMB aim/zoom, R reload, Space jump, Shift sprint.
- Nickname entered on the main menu.

### Multiplayer and hosting
- Playable in a browser from a link (like Gartic Phone): create a room (short room code) or join by code.
- One dedicated headless Godot server built from this same project, WebSocketMultiplayerPeer. Server is authoritative over hits, health, kills, scores, timer. One server handles several rooms.
- Client: Godot Web export, Compatibility renderer (WebGL2), single-threaded export (works on static hosting without special headers).
- Interpolation for other players' movement.
- Server address configurable: localhost for testing, wss:// URL for production.
- Hosting must be free. Client on a free static host (GitHub Pages or itch.io). For the server: at the deployment milestone, research current free options and present 2–3 choices with tradeoffs. **Never create accounts or enter credentials; the owner does account steps.**

### How to work
- Milestones in order (see PROGRESS.md). After each: run Godot headless to check for script errors, commit + push to origin, update PROGRESS.md, tell the owner in a few lines how to test.
- Keep scope tight: no unlisted features without asking.
- Owner is on a limited plan: don't re-read large files, prefer small focused edits, stop and explain after ~3 failed attempts at the same problem.

## Environment
- Godot **4.3 stable**: `C:\Users\<user>\Desktop\Godot_v4.3-stable_win64.exe`. Export templates 4.3.stable are installed.
- The `_console.exe` wrapper does NOT work here (non-ASCII user path). Use `tools\godot.ps1 <godot args>` which runs the main exe and prints its output.
- PowerShell swallows a bare `--`; pass game arguments after `++` instead (Godot accepts both), e.g. `tools\godot.ps1 --headless --path . ++ --server`.
- Headless check: `tools\godot.ps1 --headless --path . --quit-after 120`. The line `Parameter "m" is null ... mesh_storage.h` is harmless headless-renderer noise.
- Screenshot for visual checks: `tools\godot.ps1 --path . ++ --shot=C:\some\file.png` (opens a window for ~1 s).
- Git: branch `main`, remote `origin` (GitHub).

## Architecture decisions
- **Everything is built in code** (no hand-edited scenes besides `main.tscn`): maps, characters, UI. Easier to maintain by text edits.
- **Scripts reference each other with `preload` constants, not `class_name`**, so the project runs from a fresh clone without the editor's class cache.
- **Maps are data** (`scripts/shared/maps.gd`): a list of boxes (transform, size, color). The client builds meshes/colliders from it; the server ray-tests against the same boxes with plain math. So the server needs no physics world, which makes many rooms on one server trivial. Ramps are rotated boxes.
- **Room simulation** (`scripts/shared/room.gd`) is one class used both by the dedicated server (one instance per room) and in-process for offline practice. It talks through a `send(peer_id, msg, args)` callable, so it does not care about the transport.
- **Protocol**: two generic RPCs on the `Net` autoload (`_c2s(msg, args)` client→server, `_s2c(msg, args)` server→client). Server validates argument types.
- **Movement is client-authoritative** (client sends its position 20×/s); **combat is server-authoritative**: client sends shot origin + direction + seed + the snapshot tick it was rendering; the server rewinds enemy positions to that tick (lag compensation), ray-tests against map boxes and player boxes, applies damage, kills, score. Fire rate and ammo are also tracked on the server.
- **Snapshots** at 20 Hz; clients render other players ~100 ms in the past, interpolating between snapshots.
- Collision layers: 1 = world, 2 = remote player hit volumes (for the local aim ray only), 4 = local player body.
- Third-person aiming: ray from the camera finds the aim point; the actual shot goes from the player's eye position toward that point.
