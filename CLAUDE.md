# Notes for Claude (and any developer) working on BLACKVEIN

Read this first in every new session. It's the fastest way to get back up to speed.

## Where the project lives

- GitHub: https://github.com/La2o/BlackVein (branch `main`). This is the source of truth.
- Pushing tags through the session proxy is refused; push `main` with `git -c push.negotiate=false push`.

## Engine & rules

- Godot **4.5**, GDScript only, Forward+ renderer (must also work in Compatibility).
- **External art is allowed** (the owner lifted the old code-only rule on 2026-10-18), but only with
  a licence that allows use in a game: CC0 (ambientCG, Poly Haven, Kenney, Quaternius) or Mixamo.
  Every asset goes under `assets/` and gets a line in `assets/CREDITS.md` (source, licence, URL).
  Keep textures at 1K JPG unless there's a reason, so the repo stays small. Sounds still come from
  `tools/make_sounds.py`.
- Static typing: `:=` fails on values typed as Variant (e.g. results of methods on untyped
  nodes, Dictionary lookups). Use explicit types: `var x: Vector3 = d["pos"]`.
- `Game.player` is typed `Player`, `Game.city` is typed `City` — use them for typed access.
- Collision layers are constants in `scripts/game.gd` (`Game.LAYER_*`). Use them, never raw numbers.
- Anything damageable implements `take_hit(info: Dictionary)` where info comes from
  `Game.hit_info(damage, force, source, kind)`. kinds: melee, slash, blade, slam, impact, bullet, explosion.
- Rewards go through `Game.add_xp(amount, reason)`. New powers go in `Game.SKILLS` and must be
  gated with `Game.has_skill(id)`.
- Input actions are created in `scripts/controls.gd` (keyboard + controller; every action needs both). Add new ones there
  and to the HUD key table (`hud.gd` KEYS) and `docs/CONTROLS.md`.

## How to verify changes (do this every time)

Godot binary isn't installed system-wide in the cloud workspace; download the Linux build
(4.5-stable from the godotengine/godot GitHub releases) into the scratchpad.

```
godot --headless --path . --import                       # re-import after adding files
godot --headless --path . --quit-after 600                # quick boot check, look for SCRIPT ERROR
godot --headless --path . res://tests/test_runner.tscn    # full play-through, must end "0 failed"
```

Fast loop while working (~30 s instead of ~4.5 min): `--fixed-fps 60` drops real-time sync so the
game simulates as fast as the CPU allows. Add `--quit-after` so a script parse error can't leave Godot
idling forever. This is the day-to-day check; the normal-speed run is only for a GitHub release.
```
godot --headless --fixed-fps 60 --quit-after 60000 --path . res://tests/test_runner.tscn
```
Tests must drive input like a player (e.g. hold `forms_wheel` while the wheel is open), not lean on
real-time gaps between frames.

Screenshots (slow, software rendering):
```
xvfb-run -a -s "-screen 0 1600x900x24" godot --path . --rendering-method gl_compatibility \
  --resolution 1280x720 res://tests/test_runner.tscn -- shots=/some/folder
```

When adding a feature, add a check to `tests/test_runner.gd`.
Every test scene calls `Game.use_test_storage()` first so it never deletes the player's real save or
settings (they share `user://` with the game). New test scenes must do the same.
Screenshots run in a window: if another window takes focus, Godot releases simulated key presses and
movement checks fail — only the headless run counts.
README screenshots live in `docs/screenshots/` (1280x720 JPG, `.gdignore` keeps them out of builds).
For a quick visual check of specific scenes use `tests/screenshots.tscn` (edit it to set up what you want to see).

## Where things live

See `docs/ARCHITECTURE.md` for the full map. Short version:

| Want to change... | File |
|---|---|
| Movement feel (speeds, jumps, wall run) | `scripts/player.gd` exports |
| Attacks, forms, powers, consume, grab | `scripts/player_powers.gd` |
| People and their AI | `scripts/npc.gd` |
| Tanks / trucks, helicopters | `scripts/ground_vehicle.gd`, `scripts/helicopter.gd` |
| Military escalation | `scripts/military.gd` + alert logic in `scripts/game.gd` |
| World events, population | `scripts/director.gd` |
| XP, levels, skill tree, saving | `scripts/game.gd` |
| UI, menus, minimap | `scripts/hud.gd` |
| City layout, military base | `scripts/city.gd` |
| Traffic | `scripts/traffic.gd` |
| Weather | `scripts/weather.gd` |
| Settings | `scripts/settings.gd` (autoload) |
| Goals, combos, stats | `scripts/game.gd` |

## Audio notes

- Sounds: `tools/make_sounds.py` → `sfx/`. Music: `tools/make_music.py` → `music/`.
- Looping (music, rain, helicopter, hive) is set in each file's `.import` (`edit/loop_mode=2`).
  WAVs import as QOA-compressed, so never compute loop points from `data.size()`.

## Exporting

Templates live in `~/.local/share/godot/export_templates/4.5.stable/` (only
`windows_release_x86_64.exe`, `linux_release.x86_64`, `version.txt` are needed; extract them from
`Godot_v4.5-stable_export_templates.tpz` on the godotengine/godot GitHub release).
```
godot --headless --path . --export-release "Windows Desktop" export/windows/BLACKVEIN.exe
godot --headless --path . --export-release "Linux" export/linux/BLACKVEIN.x86_64
```
The PCK is embedded, so each build is a single file. Smoke-test the Linux one with
`export/linux/BLACKVEIN.x86_64 --headless --quit-after 400`.

## Release checklist

Releases are made **only when the owner asks**. Once Mixamo files are in use (`assets/mixamo/`, git-ignored,
see docs/MIXAMO.md), the GitHub release workflow can't see them: export release builds locally and
upload them to the release instead. Day to day: test locally with the fast loop above
(no normal-speed runs), push to `main`, keep CHANGELOG.md and the version current.

1. Tests pass (0 failed) locally **and on GitHub**. After pushing, check the Actions run:
   `gh run list -R La2o/BlackVein -L 1`, then read its annotations (failed checks are reported there,
   the raw log host is blocked from the cloud workspace):
   `gh api repos/La2o/BlackVein/check-runs/<job id>/annotations`. Fix anything that fails.
2. CHANGELOG.md has a new entry.
3. Bump `config/version` in project.godot if it's a release, and `application/file_version` / `product_version` in export_presets.cfg (the .exe details).
4. Run the soak test: `godot --headless --path . res://tests/soak.tscn -- seconds=300` — no SCRIPT ERRORs.
5. Export Windows + Linux, zip the source without `.godot/` and `export/`.
