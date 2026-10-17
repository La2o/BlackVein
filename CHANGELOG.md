# Changelog

All notable changes to BLACKVEIN. Newest first.

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
