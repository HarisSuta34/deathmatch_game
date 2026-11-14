# Progress

## Milestones
- [x] 1. Project structure, third-person character controller, blocky test map (single player)
- [ ] 2. The 3 weapons, shooting, health, death and respawn (offline)
- [ ] 3. WebSocket server and client, lobby with room codes, players see each other move and shoot, server-authoritative damage
- [ ] 4. Random team split, even-player start rule, bases, loadout screen on respawn, match timer, scoring, end-of-match screen
- [ ] 5. The 3 maps and map selection
- [ ] 6. Main menu, HUD and general polish
- [ ] 7. Web export, server export, docs/DEPLOY.md with free hosting instructions

## Notes for the next session
- M1: `main.gd` starts `game.gd` directly in a test map. Player controller in `scripts/client/player.gd`, blocky character in `avatar.gd`, map data + builder in `scripts/shared/maps.gd`.
