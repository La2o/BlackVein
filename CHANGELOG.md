# Changelog

All notable changes to BLACKVEIN. Newest first.

## [0.4.0] — 2026-10-18 — Patient Zero

### New
- **A finale.** Absorb 5 different memories (from High-Value Target scientists and base
  commanders) and reach level 18, and your memories lead you to a hidden lab under the city.
  Waiting there is **Patient Zero** — a boss with your own powers: lightning dashes, claw combos,
  telegraphed tendril volleys you have to dodge, spike rings, and three phases (it calls hunters
  at half health and gets faster when it's desperate). Beat it for 3000 XP and an ending.
  Afterwards it can come back as a rare boss.
- **Bone Spikes** — a 7th arm form (level 13): fire piercing bone spikes from your forearm,
  with light aim assist. Special: Spike Storm, a nine-spike fan. Key 7.
- **Rooftop Races**: a new world event — a chain of glowing rings across the rooftops. Hit them
  all before the clock runs out (each ring adds time; leftover time is bonus XP).
- **City ambience**: distant traffic, horns and sirens by day; crickets and wind at night.
- **Coats**: you, scientists and Patient Zero wear long coats that flap when you run and glide.
- A "What's new" note the first time you start a new version.
- New goals that lead you toward the finale, and "Origin" and "Free Runner" achievements.
- **Crowd density** setting for slower PCs (fewer people and cars).

### Fixed
- Freshly spawned effects, rockets and people could flash at the middle of the map for a frame
  (that's what the odd floating blobs near the start were).
- A rare error when an enemy's attack landed after its target had already vanished.

### Improved
- The settings menu scrolls, so it fits on smaller screens.

### Tests
- 99 automated checks (finale, Patient Zero, Bone Spikes, rooftop races).

## [0.3.0] — 2026-10-18 — Music, achievements and a Windows build

### New
- **Ready-to-play Windows build** (`BLACKVEIN.exe`) — no Godot needed. A Linux build too.
- **Music** that reacts to the action: a dark ambient score while you roam, a driving combat
  track when things kick off, and a heavier boss theme. All synthesized by `tools/make_music.py`.
  Music volume slider in Settings.
- **Achievements** (19 of them, each worth 100 XP) and a **memories log** of everything you've
  absorbed from scientists and commanders. Both in the pause menu.
- **Tendril Wings** (new skill, level 15, 3 ranks): while gliding, press jump to flap upward.
- **Infected ground** spreads in a pulsing web around every hive.
- **Key rebinding**: Settings → Change keys. Prompts on screen follow your new keys.
- **Release workflow**: push a version tag on GitHub and it builds Windows and Linux versions
  and attaches them to a release.

### Fixed
- A Biomass Decoy caught in its own explosion could chain-explode forever and freeze the game.
- Timers no longer reference people or cars that were already gone (fewer hidden errors).
- The city stops spawning extra people when it's very crowded, and bodies clear faster then,
  so long play sessions stay smooth.
- Looping sounds and music loop properly.
- The skills key shows as Tab on screen; the pause menu no longer covers the achievements list.

### Tests
- 89 automated checks plus a 5-minute "bot mashes every button" soak test (`tests/soak.tscn`).

## [0.2.0] — 2026-10-18 — Bosses, base raids and a living city

### New
- **Two bosses** (appear from level 10 and 12):
  - **The Leviathan** — a colossal infected with ground-pound shockwaves, rooftop leaps,
    an enraged phase, and broods of infected it calls in.
  - **Juggernaut** — the military's prototype super-tank with triple-shell volleys and a
    machine gun. Weaken it below 25% and you can hijack it.
  - Boss health bar at the top of the screen.
- **Military base** in the north-west of the city: walls, watchtowers, barracks, a helipad with a
  parked gunship, a parked tank, a garrison and a **base commander**. Walking in without a
  military disguise gets you noticed.
- **Artillery Strike** (new skill, R / hold LB + RB): consume the base commander for the codes,
  then call in barrages wherever you aim while disguised as a soldier.
- **Civilian traffic** drives the streets, brakes for people, floors it when there's danger,
  and turns into a throwable physics car the moment you hit it (or grab it).
- **Weather**: rain storms and thick fog roll in every few minutes. Soldiers can't see as far
  in bad weather.
- **Combo meter** with style ranks (D → C → B → A → S → SAVAGE); long combos pay bonus XP.
- **Starter goals** on screen that teach the game and pay XP (12 goals, from your first wall run
  to defeating a boss).
- **Settings menu**: mouse sensitivity, controller look speed, invert Y, field of view, volume,
  camera shake, rumble, FPS counter, graphics quality (Low / Medium / High).
- **Stats** on the pause screen: kills, consumes, events, best combo, play time.

### Improved
- Nights are readable now: moonlit ambient light, pools of light under street lamps, softer windows.
- Explosions use additive fire instead of solid balls.
- Camera sits a little higher and farther back so you can see past your character.
- Square minimap (the round frame used to cut off the corners).
- People no longer pop into existence right in front of the camera.
- Vaulting onto rooftops overshoots less.
- Hunters and the Leviathan have spines and claws.

### Tests
- 85 automated checks (was 65), now covering bosses, traffic, the base, artillery, weather,
  combos, goals and settings.

## [0.1.0] — 2026-10-18 — First playable build

### Movement
- Super sprint with speed lines and a camera that widens as you go faster.
- Wall running: sprint into any building to run straight up it; steer sideways along walls,
  switch walls at inside corners, wall jump, and vault over the roof edge automatically.
- Charged super jump (tap for a hop, hold for up to ~28 m), double jump, gliding, air dash.
- Heavy landings from high up make a shockwave that sends cars and people flying.
- Super-speed body checks knock people over; running into cars shoves them.

### Combat and powers
- Six arm forms, each with its own combo and special move:
  Fists (Uppercut), Claws (Spike Line), Hammerfist (Ground Slam), Blade (Whirlwind),
  Whipfist (Whip Grab), Musclemass (Thunderclap).
- Auto-lunge to nearby enemies, combo finishers, hit-stop and screen shake.
- Dive bomb from the air, stronger with Hammerfist and Musclemass.
- Shield (blocks from the front) and Armor (less damage, ram through things).
- Grab and throw people and cars; thrown things hurt what they hit.
- Consume people to heal, refill biomass and take their disguise.
- Devastators: Groundspike and Tendril Barrage.
- Thermal vision.
- Pick up rifles and rocket launchers from fallen soldiers.
- Hijack tanks (drive and fire shells) and gunships (fly, missiles, minigun). Bailing out of a
  gunship lets it crash.
- New original powers: **Tether** (zip to any surface, yank enemies, latch onto helicopters),
  **Focus** (slow motion), **Biomass Decoy** (a clone that draws fire, then explodes).

### Progression and saving
- XP from kills, consumes, destroyed vehicles and world events.
- 50 levels; skill points every level (double every 5th level).
- Skill tree with 22 skills across Movement, Forms, Defense, Abilities, Devastators and Body.
  You start with fists and basic movement and unlock the rest.
- The military gets tougher as you level up.
- Automatic saving every 45 seconds, on level up, on skill unlock and on quit. Manual save,
  and "New game" in the pause menu.

### World
- Procedural city: 64 blocks of skyscrapers with lit windows, rooftop water towers, antennas,
  street lamps, trees, crosswalks and parked cars, plus a skyline beyond the playable area.
- Day/night cycle (about 16 minutes); windows and street lamps light up at night and more
  infected roam.
- Civilians who wander, panic and flee; soldiers who patrol, search and fight; infected who
  hunt and turn their victims; hunters who leap onto rooftops after you.
- Military alert system: hidden → suspicious → alert → searching, with heat levels that bring
  rocket teams, tanks, gunships, strike teams and airstrikes.
- World events: Infection Outbreak (hives), Military Convoy, Hunter Pack, Street Battle,
  Supply Drop, Strike Team, Bombing Run, High-Value Target (with secret memories), Gunship Patrol.

### Interface
- Health, biomass, level and XP bars, compass with event markers, rotating minimap,
  alert indicator with suspicion meter, event list, event feed, contextual button prompts.
- Prompts switch between keyboard and controller names automatically.
- Pause menu, skills menu, full controls screen (F1), city map (M), fullscreen (F11).
- Screen effects for thermal vision, damage, low health and focus.

### Controller
- Full controller support for every action, menus included, plus rumble.

### Sound
- 27 sound effects, all synthesized by `tools/make_sounds.py`.

### Project
- Automated play-through test with 65+ checks (`tests/test_runner.tscn`).
- GitHub-ready: README, .gitignore, .gitattributes, MIT license, test workflow.
- Notes for future work in CLAUDE.md and docs/.
