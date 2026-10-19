# Notes for Claude (and any developer) working on BLACKVEIN

Read this first in every new session. It's the fastest way to get back up to speed.

## Where the project lives

- On the owner's Windows PC: `E:\BLACKVEIN` (moved from `C:\Users\ygsna\BLACKVEIN` on 2026-10-19).
  New PC / reinstalled Windows: follow `docs/PC_SETUP.md` (Godot, export templates and the owner's
  save are backed up in `_pc_backup/`, which is not in git).
- GitHub: https://github.com/La2o/BlackVein (branch `main`). This is the source of truth.
- Push with `git -c push.negotiate=false push`.

## Working with the owner (standing preferences)

- **Test locally with the fast loop only** (`--fixed-fps 60`, below). Normal-speed runs and the
  300 s soak are only for a GitHub release.
- **Never tag or publish a GitHub release unless the owner asks.** Push commits to `main` as you go;
  keep CHANGELOG.md (an `[Unreleased]` section) and the version numbers ready so a release is quick.
- **Keep the local build current**: after each tested batch, export
  `export/windows/BLACKVEIN.exe` (they play it directly or through `PLAY.bat` next to it). Check the
  game isn't running first (`tasklist | findstr BLACKVEIN`).
- **Never run that exe yourself**: it shares `%APPDATA%\Godot\app_userdata\BLACKVEIN\` with the
  owner's real save and could autosave over it. Tests use `Game.use_test_storage()`.
- Assets: CC0 only (see below). Downloads from itch.io work through the built-in browser: open the
  page, "No thanks, just take me to the downloads", then POST to the page's
  `/file/<upload id>?source=game_download&after_download_lightbox=1&as_props=1` from the page and fetch
  the signed URL it returns with curl within 60 seconds.

## Engine & rules

- Godot **4.5**, GDScript only, Forward+ renderer (must also work in Compatibility).
- **External art is allowed** (the owner lifted the old code-only rule on 2026-10-18), but only with
  a licence that allows use in a game: CC0 (ambientCG, Poly Haven, Kenney, Quaternius). No Mixamo (its files
  can't be redistributed and the repo is public).
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

Godot 4.5 lives in `%LOCALAPPDATA%\Programs\Godot\`; use the console build so output reaches the
terminal. In Git Bash: `G="$LOCALAPPDATA/Programs/Godot/Godot_v4.5-stable_win64_console.exe"`, then
`"$G"` wherever `godot` appears below. (In a cloud/Linux workspace, download the Linux 4.5-stable build.)

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
Frame drops? `tests/profile.tscn` runs the real game in a window (the world active, the player sprinting
with the military after them) and prints fps, the worst 1% and every frame over 33 ms with the NPC
count. `-- old=1` swaps in the old code-built NPCs for comparison. Keep loaded resources referenced:
Godot drops unreferenced ones from its cache, so a `load()` per spawn re-reads the file (person.gd `_res`).
```
godot --path . --resolution 1920x1080 res://tests/profile.tscn -- seconds=40
```
Tests must drive input like a player (e.g. hold `forms_wheel` while the wheel is open), not lean on
real-time gaps between frames.

Screenshots: run a look scene in a window (on Linux without a display, wrap it in
`xvfb-run -a -s "-screen 0 1600x900x24"` and add `--rendering-method gl_compatibility`):
```
godot --path . --resolution 1280x720 res://tests/look_anim.tscn -- shots=/some/folder
```
Look scenes: `look_anim` (moving, carrying, aiming, vault, jump), `look_bio` (bio weapons, hero shots),
`look_moves`, `look_creatures`, `look_districts`, `look_enemies`, `look_trials`, `look_people`,
`look_ragdoll`. Convert PNGs to JPG for the README with Godot's `Image.save_jpg` (no PIL here).

Animation: walk/jog/sprint rates come from `Person.CYCLES` (natural stride speed per body height and
phase relative to Walk). If you add or change a cycle, re-measure with
`godot --headless --fixed-fps 60 --path . res://tests/anim_slip.tscn -- calibrate` and check foot slide
and gait pops with the same scene without arguments. Arms are posed through the upper-body layer
(`upper_anim`, `arms_up`, `aim_dir` in person.gd), never by rotating the `arm_l/arm_r/...` pivots: those
only carry attached pieces. Crossfades are done by `Person.play()` itself, not the AnimationPlayer.

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
| NPC bodies, clothes, gear, animations | `scripts/person.gd`, `scripts/person_model.gd`, `shaders/person.gdshader` |
| Goals, combos, stats | `scripts/game.gd` |

## Audio notes

- Sounds: `tools/make_sounds.py` → `sfx/`. Music: CC0 tracks in `music/` (`ambient`, `combat`, `boss`; any of
  .ogg/.mp3/.wav, credited in assets/CREDITS.md). `tools/make_music.py` made the old generated loops.
- Looping (music, rain, helicopter, hive) is set in each file's `.import` (`edit/loop_mode=2`).
  WAVs import as QOA-compressed, so never compute loop points from `data.size()`.

## Exporting

Templates live in `%APPDATA%\Godot\export_templates\4.5.stable\` on Windows
(`~/.local/share/godot/export_templates/4.5.stable/` on Linux; only
`windows_release_x86_64.exe`, `linux_release.x86_64`, `version.txt` are needed; extract them from
`Godot_v4.5-stable_export_templates.tpz` on the godotengine/godot GitHub release).
```
godot --headless --path . --export-release "Windows Desktop" export/windows/BLACKVEIN.exe
godot --headless --path . --export-release "Linux" export/linux/BLACKVEIN.x86_64
```
The PCK is embedded, so each build is a single file. Smoke-test the Linux one with
`export/linux/BLACKVEIN.x86_64 --headless --quit-after 400`.

## Release checklist

Releases are made **only when the owner asks**. Day to day: test locally with the fast loop above
(no normal-speed runs), push to `main`, keep CHANGELOG.md and the version current.

1. Tests pass (0 failed) locally **and on GitHub**. After pushing, check the Actions run:
   `gh run list -R La2o/BlackVein -L 1`, then read its annotations (failed checks are reported there,
   the raw log host is blocked from the cloud workspace):
   `gh api repos/La2o/BlackVein/check-runs/<job id>/annotations`. Fix anything that fails.
2. CHANGELOG.md has a new entry.
3. Bump `config/version` in project.godot if it's a release, and `application/file_version` / `product_version` in export_presets.cfg (the .exe details).
4. Run the soak test: `godot --headless --path . res://tests/soak.tscn -- seconds=300` — no SCRIPT ERRORs.
5. Export Windows + Linux, zip the source without `.godot/` and `export/`.
