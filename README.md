# VIEWERS VS ME • LIVE

Roblox TikTok Live survival project synced with Rojo.

## Current working Roblox build

ServerScriptService:
- `TikTokGameCore.server.lua`
- `CityOverhaul.server.lua`
- `BrighterMap.server.lua`

StarterPlayer > StarterPlayerScripts:
- `AutoCombat.client.lua`
- `TestButton.client.lua`
- `StreamHUD.client.lua`

Runtime objects created by the scripts include:
- `workspace.TikTokEnemies`
- `ReplicatedStorage.TikTokTestSpawn`
- `ReplicatedStorage.TikTokStreamEvent`
- `ReplicatedStorage.AutoCombatAttack`

Do not re-enable obsolete duplicate systems from earlier builds such as ZombieFactory, GiftWeaponConfig, TestSpawner, CombatServer, TikTokEventConsumer, or duplicate AutoCombat scripts unless the architecture is intentionally changed.

## Rojo

Install Rojo CLI and the Rojo Studio plugin, clone this repository, then run `rojo serve` from the repository folder. In Roblox Studio, open the Rojo plugin, connect to the local server, and sync this project into the place.

`default.project.json` maps the `src` folders to Roblox services.