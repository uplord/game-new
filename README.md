# game-new


## Battle System Added

The project now includes a server-authoritative battle flow wired into `Network/PacketManager.gd` and `UI/UI.gd`.

- Player stats stored server-side: HP, MP, cooldowns, selected target.
- Player MP regenerates over time on the server.
- Enemy stats are now shared per map/scene/instance enemy, so multiple players attacking the same enemy see the same HP.
- Player skills: basic attack, magic attack, defence, heal, super attack.
- Enemy skills: two attacks and one super attack, chosen by ordered priority.
- Enemies target a random alive player from the list of players currently attacking that enemy.
- Defeated enemies disappear for all clients, then respawn after `ENEMY_RESPAWN_SECONDS`.
- Bottom battle buttons send skill-use packets and are disabled when unavailable.
- Only one enemy target per player is supported at a time.

Packets added:

- `c_select_enemy`
- `c_use_skill`
- `s_battle_state`
- `s_enemy_visibility`
- `s_battle_error`


### Battle system update

- Enemy HP is now shared per map / scene / instance / enemy path.
- Enemy HP and visibility changes are broadcast to players in the same instance.
- Skill buttons count cooldowns down locally after the latest server state, so they re-enable as soon as cooldown reaches 0.
- Skill buttons stay disabled if the player does not have enough MP.
