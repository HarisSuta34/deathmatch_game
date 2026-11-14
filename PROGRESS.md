# Progress

## Milestones
- [x] 1. Project structure, third-person character controller, blocky test map (single player)
- [x] 2. The 3 weapons, shooting, health, death and respawn (offline)
- [x] 3. WebSocket server and client, lobby with room codes, players see each other move and shoot, server-authoritative damage
- [x] 4. Random team split, even-player start rule, bases, loadout screen on respawn, match timer, scoring, end-of-match screen
- [x] 5. The 3 maps and map selection
- [x] 6. Main menu, HUD and general polish
- [ ] 7. Web export, server export, docs/DEPLOY.md with free hosting instructions

## Notes for the next session
- M4: match flow lives in `room.gd` (`_try_start`, `_spawn`, `_end_match`): 5 s warmup with loadout screen, 3 s respawn, 2.5 s spawn protection (ends when you shoot), 10 s results, then lobby. Covered by `tools/test_room.gd`. Screens can be checked with `++ --practice=0 --match-seconds=1 --shot=x.png --shot-delay=8`.
- M3: `main.gd` runs as server with `++ --server` (flags: `--port=`, `--dev`, `--match-seconds=`), otherwise shows `scripts/client/menu.gd` (menu + lobby). `Net` autoload (`scripts/net.gd`) holds rooms on the server and the connection on clients.
- Network regression test: `tools\test_net.ps1` (server + 4 headless bots from `scripts/dev/bot.gd`; expect kill events and "BOT back in lobby"). The `ready_state != STATE_OPEN` errors at the very end are just bots quitting.
- Manual local multiplayer: `tools\play_local.ps1 2` (dev server + 2 windows).
- M2: practice mode is an offline room (`Net.start_practice`) with 4 stationary bots that shoot back. Weapons in `scripts/shared/weapons.gd`, authoritative simulation in `scripts/shared/room.gd` (already contains lobby/match/timer logic used by later milestones), HUD in `scripts/client/hud.gd`.
- Logic regression test: `tools\godot.ps1 --headless --path . -s tools/test_room.gd` (all lines should say PASS).
- M1: `main.gd` starts `game.gd` directly in a test map. Player controller in `scripts/client/player.gd`, blocky character in `avatar.gd`, map data + builder in `scripts/shared/maps.gd`.
