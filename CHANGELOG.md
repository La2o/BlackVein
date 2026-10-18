# Changelog

All notable changes to BLACKVEIN. Newest first.

## [0.6.0] — 2026-10-18 — Disguises and buildings you can enter

### New
- **Disguise wardrobe** (I, or hold LB + B): every identity you consume is kept, and you can
  switch between them any time. Each disguise has a purpose:
  - **Scientist** — walk freely through the research labs.
  - **Soldier / rocket soldier / strike team** — walk into the military base and bunker; soldiers
    get suspicious more slowly.
  - **Base commander** — full military access, and lets you call Artillery.
  - **Civilian** — blend into street crowds.
  - **Your true form** — the hooded drifter.
  Changing while nobody is watching makes the military lose you; changing in front of soldiers
  blows your cover. Your wardrobe and current disguise are saved.
- **Buildings you can enter** — glowing doors in the city (also marked on the minimap and map):
  - **Origin Biotech Labs** (3): scientists, guards, specimen tanks, a vault with an
    **Evolution Sample** (+1 skill point each) and a head scientist carrying a memory.
    Restricted: you'll be noticed unless you're disguised as a scientist or soldier.
  - **Military Bunker** under the base: armory with weapons, barracks, holding cells, and an intel
    terminal (big XP, and a second way to get the artillery codes). Soldiers only.
  - **Subway Nest**: an infested station full of infected, hunters, hives and a
    **Hive Heart** — destroy it for XP and a mutation (+1 skill point, once).
  - **Safehouse**: rest to heal, save and skip 8 hours; your wardrobe; a trophy wall with your stats.
  Your allies follow you inside. The city pauses while you're indoors.
- Achievements: "Thousand Faces", "Infiltrator", "Exterminator II".

### Fixed
- People no longer appear on rooftops: when no good street spot was found, new people could be
  placed at your height (on the roof you were standing on). People who get thrown or blasted onto
  a roof are cleaned up once you leave.
- **Menus now work with a controller**: D-pad / left stick to move, A to select, B to go back.
  (The built-in menu controls only listened to controller #0 and had no A/B buttons.)

## [0.5.1] — 2026-10-18

### Changed
- Removed the cricket chirping from the night ambience; nights now just have soft wind.

## [0.5.0] — 2026-10-18 — Dominate, better looks, working controllers, faster jumps

### New
- **Dominate** (new skill, level 5, 3 ranks): grab someone and press Special (right-click / Y)
  to brand them. Branded allies glow red, follow you, and fight for you — soldiers shoot,
  infected and hunters brawl. They attack the infected on sight and the military when it's
  hunting you, and catch up if you leave them far behind. You can't hurt them by accident.
  2 allies per rank (up to 6). Allies show as pink dots on the minimap.
- Achievements: "Warlord" (brand 25 allies) and "Personal Army" (lead 6 at once).

### Fixed
- **Controllers now work.** The controls only listened to "controller #0", and on many PCs the
  pad shows up with a different number, so it did nothing. Every binding now accepts any
  controller. A message pops up when a controller connects, and Settings shows which one the
  game sees.

### Changed
- **Jumping keeps your speed.** Jump happens the instant you press it — no crouch, no slowdown —
  and running jumps go higher. Keep holding jump after take-off to keep rising: a tap is a hop,
  a full hold is a ~30 m super jump (33 m+ when running).
- Landing from a big jump no longer slows you down if you're still sprinting.

### Graphics
- New sky with drifting clouds, a glowing sun, and stars at night. Clouds thicken and darken
  in storms.
- Streets: worn lane markings, double yellow center lines, cracks and patches. In the rain they
  turn dark and glossy with puddles.
- Buildings: tall towers step back as they rise (and you can wall-run up each step), parapet
  walls around every roof, shop windows and colored sign bands at street level, window frames,
  blinds, pilasters, grime streaks, gravel roofs, and per-building color variety.
- Glowing rooftop billboards, traffic lights that change, fire hydrants, benches and bins.
- People have shoulders, hips, necks, shoes and eyes. You have glowing veins.
- Lighting: screen-space reflections on glass and wet streets, extra ambient occlusion,
  softer shadows, sun-scattering fog, a touch more contrast and color. (Lower the Graphics
  quality setting if your PC struggles.)
- Nights are less pitch-black and windows glow less harshly.

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
  all before the clock runs out (each ring adds time; leftover time is bonus XP). Your best time
  is saved, and beating it pays extra.
- **Spreading infection**: the infected ground around a hive grows the longer it lives and turns
  nearby civilians into infected. Destroy hives early.
- **Damage numbers** (optional, in Settings).
- The military base shows on the minimap and the city map.
- A beginner's guide: docs/HOW_TO_PLAY.md.
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
- **Military base** in the south-west of the city: walls, watchtowers, barracks, a helipad with a
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
