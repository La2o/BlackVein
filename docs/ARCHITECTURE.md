# Architecture

How BLACKVEIN is put together. Everything is built at runtime from code; the two scene files
only hold the node skeleton.

## Startup

`scenes/main.tscn` → `scripts/main.gd`:
1. Registers itself and the city with `Game`.
2. Creates a `Units` node where every spawned person, vehicle, hive and projectile lives.
3. `City.build()` generates the city, parked cars and the navigation mesh.
4. Places the player, starts the day/night cycle, loads the save file if one exists.

## Autoloads (always present)

| Name | File | Job |
|---|---|---|
| `Controls` | `scripts/controls.gd` | Creates every input action (keyboard, mouse, controller). |
| `Settings` | `scripts/settings.gd` | Player settings saved to user://settings.cfg. |
| `Game` | `scripts/game.gd` | Shared state and helpers: references to major systems, collision layers, alert/heat system, XP/levels/skills, save/load, damage helpers (`hit_info`, `damage_area`, `explode`), raycasts, time scale (hit-stop, focus). |

## Systems (children of Main)

| Node | File | Job |
|---|---|---|
| Effects | `effects.gd` | Explosions, shockwaves, spikes, tendrils, tracers, blood, fire, smoke, pooled 3D sounds. |
| City | `city.gd` | Grid city generator, materials, street lamps/trees (MultiMesh), parked cars, nav mesh, spatial queries (random sidewalk/street/roof points, street names). |
| Player | `player.gd` + `player_model.gd` + `player_powers.gd` | See below. |
| Military | `military.gd` | Keeps patrols near the player, escalates with heat, spawn helpers for everyone. |
| Director | `director.gd` | Civilian/infected population and the world event system. |
| DayNight | `daynight.gd` | Sun, sky, fog, window and lamp glow. |
| Weather | `weather.gd` | Rain, fog and clear skies. |
| HUD | `hud.gd` | All UI and menus; runs while paused. |

## The player

- `player.gd` (`class_name Player`) — a CharacterBody3D state machine:
  GROUND, AIR, WALL, GLIDE, DASH, TETHER, DIVE, LOCKED, PILOT, DEAD.
  Owns health, biomass, disguise, camera (spring arm, FOV, shake), landing shockwaves and
  "is_conspicuous()" which the military uses to notice you.
- `player_model.gd` — extends `humanoid.gd`; adds arm forms, shield, armor and disguise outfits.
- `player_powers.gd` (`class_name PlayerPowers`) — reads combat input: forms, melee, specials,
  grab/throw, consume, defense, thermal, focus, decoy, tether, devastators, guns, hijacking, rumble.

## Everyone else

- `npc.gd` — one script for civilians, scientists, soldiers, rocket soldiers, elites, infected and
  hunters. State machine: IDLE, WANDER, FLEE, COWER, PATROL, SEARCH, ENGAGE, CHASE, LEAP,
  LAUNCHED, GRABBED, CONSUMED, DEAD. Uses the nav mesh for paths and thinks a few times a second
  (rarely when far away).
- `humanoid.gd` — the shared capsule-person model and its procedural animation.
- `car.gd` — RigidBody car: knockable, grabbable, throwable, explodes.
- `ground_vehicle.gd` — tanks and trucks driving the street grid; tanks shoot, trucks deploy soldiers.
- `helicopter.gd` — gunships: orbit, minigun, homing missiles, building avoidance, crash.
- `projectile.gd` — rockets, shells, missiles, bombs.
- `hive.gd` — infection hives that spawn infected.
- `pickup.gd` — dropped guns and supply caches.
- `decoy.gd` — the Biomass Decoy clone.
- `traffic.gd` — driving civilian cars; they swap themselves for `car.gd` physics cars when hit.

## Saved data

`user://blackvein_save.json` holds level, XP, skill points, skills, flags, stats, goal progress,
kills, play time, time of day and the player's position/health/biomass/form.
`user://settings.cfg` holds settings.

## Talking between systems

- Damage: call `node.take_hit(Game.hit_info(damage, force, source, kind))` on anything with that method.
- Rewards: `Game.add_xp(amount, reason)`.
- Messages: `Game.say(text, color)` (big center text) and `Game.feed(text, color)` (event feed).
- Alert: soldiers/vehicles call `Game.report_sighting(...)` or `Game.raise_alert(...)`.
- Events: units call `get_tree().call_group("event_listeners", "on_unit_removed", unit, how)`.
- Groups used for lookups: `npcs`, `civilians`, `military`, `infected`, `hunters`, `vehicles`,
  `military_vehicles`, `helicopters`, `hijackable`, `cars`, `pickups`, `hives`, `decoys`, `warm`.

## Collision layers (`Game.LAYER_*`)

| Bit | Name | What |
|---|---|---|
| 1 | WORLD | ground, buildings, rooftop props, hives |
| 2 | PLAYER | the player |
| 4 | PROPS | cars |
| 8 | NPC | people |
| 16 | VEHICLE | tanks, trucks, helicopters |
| 32 | PICKUP | guns, supply caches |
| 64 | HIVE | hives (also on WORLD) |

## Performance notes

- NPC AI thinks every ~0.3 s near the player and ~1.2 s far away.
- Units far from the player are despawned unless they belong to an active event.
- Street lamps and trees are MultiMeshes; car meshes and materials are shared.
- The nav mesh only covers street level (rooftops are reached by jumping, not walking).
