# Changelog

All notable changes to BLACKVEIN. Newest first.

## [Unreleased]

### New
- **Ragdolls**: people and soldiers go limp when they die. Their bodies tumble, fold over cars and
  sprawl on the road. Up to 10 are simulated at once; bosses keep their death animation.
- **Riot troopers** join hunts at higher alert. Their shield cuts hits from the front to a tenth.
  Flank them, or smash the shield away with a big hit or an explosion.
- **Snipers** take positions on rooftops at alert 3 and above. They see twice as far, paint you with a red
  laser for 1.6 s, then fire one heavy shot. Break line of sight before the shot lands.
- **Brute infected**: hulking, spiked infected that leap like hunters and hit hard. Most outbreaks
  have one guarding the hive.
- **Bio-Bomb** (Abilities, level 13, needs Decoy): grab someone and press Decoy to fill them with
  unstable biomass, then throw them. They burst on impact, or 1.6 s later, in a big explosion.
- **Time trials**: four fixed rooftop courses, started by blue light beacons in the street (marked on
  the map). Rings show the way, with a par time and your best time saved. XP for finishing and for
  beating par. New achievement: Roof Runner (finish all four).
- Riot trooper and sniper disguises get the same access as soldiers.

### Fixed
- A killing blow that also launched someone skipped their death entirely (no ragdoll, no death events).

 — 2026-10-19 — Creature forms, a stealth meter and collectibles

### New
- **Creature forms** (new Creatures skills; N / hold LB + D-pad Down to cycle): whole-body
  transformations that drain biomass while you wear them and drop you back to human when it runs out.
  - **Brute** (level 12): a hulking mass of raw flesh and glowing veins, bone spikes and claws.
    +60% damage, +50% health, takes 40% less damage, can't be knocked back, a little slower.
  - **Stalker** (level 14): a lean black hunter with glowing eyes and long claws that prowls low.
    +40% sprint, +30% jumps, clings to walls.
  - **Wraith** (level 16): a pale winged horror that truly flies (unlimited wing beats) and glides
    fast, but is frail.
  Your arm, body and leg forms still work on top; disguise changes made while transformed apply when
  you turn back.
- **60 Viral Caches**: glowing clusters of biomass hidden all over the map (skyscraper and house
  roofs, warehouses, barns, silos, parks). Each refills your biomass and gives XP; every 10 found is a
  skill point. A new achievement, Hoarder, for 30.
- **Stealth meter**: an eye at the top of the screen opens as soldiers grow suspicious (UNSEEN,
  NOTICED, SPOTTED, SEARCHING), arrows around the middle of the screen point at everyone noticing you,
  and those soldiers show a **?** (suspicious) or **!** (after you) over their heads.

### Changed
- **Smoother player animation:** walking, jogging and sprinting now match your real speed (the sprint
  plays up to 3x so your feet keep up instead of sliding), jumps have a take-off and touch-downs a
  landing, gliding and skydiving spread your arms, and superhero landings crouch instead of kneeling.

### Fixed
- After a body change (consuming someone, changing disguise) while standing still, the new body could
  stay frozen in a T-pose until you moved.

## [0.11.0] — 2026-10-19 — A bigger, varied map

### New
- **The map is four times bigger** (16 x 16 blocks, about 1 km across) and no longer the same city
  everywhere:
  - **Downtown** (where you start): the skyscrapers.
  - **Midtown**: brick and concrete mid-rise blocks, with a few **parks** (lawns, paths, trees,
    fountains).
  - **Suburbs** (south and west): houses with gable roofs you can run across, lawns, driveways,
    back-yard fences, garden trees and cars in the driveways. Quiet streets without crosswalks.
  - **Industry** (east): corrugated-metal warehouses with roll-up doors, brick chimneys, container
    stacks to climb and storage tanks. The military base has moved here.
  - **Farmland** (north): fields of wheat, green crops, plowed soil and pasture, red barns, silos, hay
    bales, fences, tree lines and country lanes with grass verges. Few people about.
  - The edge of the map matches its side, and open grassland stretches beyond it.
- New CC0 textures from ambientCG: grass, field soil, clapboard siding, barn planks, corrugated metal,
  slate and terracotta roof tiles.
- The big map (M) shades each district.

### Changed
- Fewer pedestrians in farmland, industry and the suburbs; traffic lights only in town.
- Research labs are always in downtown or midtown buildings.

### Fixed
- A person thrown by someone who died before they landed caused script errors.

## [0.10.0] — 2026-10-18 — Real people

### New
- **Every person in the city is now a rigged, animated character** (free CC0 models and animations by
  Quaternius) instead of the code-built figures: real faces, eyes, hair and beards, male and female
  bodies, many skin tones, and motion-captured-style walking, jogging, sprinting, aiming, punching,
  shooting, cowering, falling and dying.
- Clothes are painted onto the bodies (shirts with long or short sleeves, jeans, camo, shoes) and
  fitted gear follows the skeleton: helmets, officer caps, berets, hoods, armour vests, belts, lab
  coats, rifles and rocket launchers. Infected glow with red veins; hunters carry bone spikes and
  claws; Patient Zero has glowing blue claws.
- People far from the camera animate less often, and spawning someone takes under a millisecond, so
  crowds stay smooth (an early build stuttered every time people appeared).
- **New music** (free CC0 from OpenGameArt): "Bleak Terminal" by ruskerdax while you explore,
  "AI Fight" from the T&T Free Cyberpunk Pack 2 in combat, and Juhani Junkala's "Epic Boss Battle"
  for bosses. The game still crossfades between them as the action changes.
- **You too:** BLACKVEIN is now a rigged character, a hooded figure in a long dark coat with faint
  red veins on the face and hands. Every arm form, body form (shield, armour, wings, Light Body) and leg
  form rides on the animated skeleton; Musclemass, Hammerfist and Crusher legs bulk up the real arms
  and legs. Flips, rolls, superhero landings, the ninja run and the charge-up use matching animations.

## [0.9.1] — 2026-10-18 — Real textures

### New
- **Photo textures** (free CC0 from ambientCG): buildings are now concrete, red brick or plaster
  with real surface detail, streets are real asphalt, sidewalks are paving slabs, rooftops are
  gravel with tar patches. Lane markings, windows and shop fronts are drawn on top as before.
- **Ultra graphics** (Settings → Graphics quality): light bounces off buildings (global
  illumination) and temporal anti-aliasing smooths edges. Needs a strong graphics card; High is
  still the default.

## [0.9.0] — 2026-10-18 — Stealth, guns, new soldiers

### New
- **Stealth that follows your disguise:** parkour (sprinting, vaults, wall runs, flips, super jumps)
  no longer bothers the military when your disguise fits where you are. Attacking still gets you
  spotted at once, and some things always stand out: flying (gliding, wing flaps, air dashes,
  tether zips, dive bombs), visible body forms, carrying people or cars, and shockwave landings.
  Inside bases and labs, any running around gives you away even in uniform.
- **"Blending in" / "Standing out: why"** shows under the alert meter whenever soldiers are near.
- **Stealth consumes:** consume someone no soldier can see for +50% XP (and they never know).
- **Prototype 1 guns:** the **grenade launcher** (lobbed, bouncing grenades) and the **heavy machine
  gun** (very fast, hits hard, slows you down) join the assault rifle and rocket launcher.
- **Rocket lock-on:** hold Aim (Right click / Y) on a tank or gunship until it says LOCKED; your
  rockets then home in.
- **New soldiers:** **grenadiers** lob grenades from range and **heavy gunners** (big, armoured,
  slow) wade in with long machine-gun bursts. They join the hunt as the heat rises, drop their
  guns, and you can wear them as disguises. The bunker armory stocks all four guns.

### Changed
- Every level now visibly gives +2% max health and damage (shown on level up and in the Skills
  menu). "Thousand Faces" now asks for 8 kinds of disguise.

### Fixed
- The per-level health and damage bonus only kicked in after you unlocked a skill or reloaded;
  it now applies the moment you level up.

## [0.8.2] — 2026-10-18

### Fixed
- Consuming a soldier no longer leaves their prop rifle in your hand: disguises copy the outfit,
  not the gun. Only weapons you actually pick up are shown.
- Consuming or changing disguise while holding a picked-up gun no longer makes the gun invisible.
- Tests run about 9x faster during development (`--fixed-fps 60`, see CLAUDE.md).

## [0.8.1] — 2026-10-18

### New
- The build number (e.g. `v0.8.1`) shows faintly in the bottom-right corner, so you always know
  which version you're playing. The FPS counter moved up a little to make room.

## [0.8.0] — 2026-10-18 — Light Body, seamless running, brighter nights

### New
- **Light Body** (new body form, Movement skill from level 5): a lean, stripped-down runner's body
  with glowing sinew lines and swept-back fins. 25% faster sprint and wall runs, 20% higher jumps
  and sharper air control, but you take 30% more damage. Stacks with Runner Legs.
- **Charge-jump animation:** holding jump coils you up (knees tucked, arms swept back, body
  squashing down) while red energy gathers into you, then bursts into the rocket pose when the
  super jump kicks in.

### Changed
- **Vaults are seamless:** sprinting at a car, bench or low wall now spots it much earlier,
  measures how tall it is and hops over in one smooth arc at full speed. You never clip the edge
  and stop, low walls are vaulted instead of starting a wall run, and you land straight back into
  the run (no roll or squash).
- **Nights are a little brighter:** stronger moonlight, more ambient light and slightly higher
  exposure, so the streets are readable without losing the night mood.
- Release builds now carry the changelog as release notes, and older versions can be rebuilt
  from the Actions tab.

### Fixed
- **Running into side streets no longer stops you:** curbs (and any step up to 0.45 m) are
  stepped onto at full speed instead of acting like a wall.
- **The "what's new" popup can be clicked right away:** the game waits and the mouse is free
  while it shows (no more pressing Esc first). Enter, Space, Esc or the controller closes it.
- Close-range aim assist accepts targets beside the aim line; bone spikes fly past loose objects.
- Respawning clears leftover air state (a jump right after respawn could glide instead of
  double jump).
- The automated tests no longer delete your save or reset your settings: they use their own
  files (`test_save.json`, `test_settings.cfg`).

## [0.7.0] — 2026-10-18 — Body-part forms, parkour, 3D people

### New
- **Forms wheel** (hold Alt or X / hold D-pad Up): time slows to a crawl and a radial menu shows
  every form for every body part. Point with the mouse or a stick, release to switch.
- **Body-part forms** — mix and match:
  - **Head:** Thermal Vision, **Night Vision** (new), **Predator Sense** (new: soldiers, infected
    and targets glow through walls). V / R3 cycles them.
  - **Arms:** the 7 combat forms.
  - **Body:** Shield, Armor and **Wings** (new: flesh-and-bone wings on your back; glide much
    faster, flap higher, 3 extra flaps). X / D-pad Up cycles them.
  - **Legs (new):** **Runner** (35% faster sprint, longer running jumps), **Leaper** (huge jumps,
    hard landings become stomps), **Crawler** (climb walls without sprinting, hang on walls, run
    along buildings as long as you like), **Crusher** (sprint through people and cars, can't be
    knocked back, stronger landings). Each shows on your legs.
  - New skills: Night Vision, Predator Sense, Runner / Leaper / Crawler / Crusher Legs.
- **Prototype-style parkour animations:** front flips and corkscrews on double jumps, side flips,
  backflips off walls, a flip over the ledge when you reach a roof, barrel-roll air dashes,
  forward rolls when you land while sprinting, superhero landings (knee and fist down) after big
  drops, automatic vaults over cars, benches and low walls, a deep lean and "ninja run" with arms
  swept back at top speed, a rocket pose on super jumps, a skydive pose when falling fast,
  banking into turns, and the camera tilts with you.
- **Sculpted 3D people** replace the capsule figures: shaped bodies (three builds), faces with eyes,
  brows, nose, lips and ears, hands with fingers, bending elbows and knees, and real outfits —
  soldiers with camo, vests, pouches, gloves, boots and modelled rifles; scientists in lab coats
  with glasses and ID badges; civilians with t-shirts, hoodies, jackets, skirts, shorts, caps,
  beards and many hairstyles; infected with blotchy skin and glowing eyes. One shared material keeps
  crowds fast.

### Changed
- **One disguise per type** in the wardrobe: once you have a civilian (or a soldier, scientist...),
  more of the same aren't added. Old saves are cleaned up. "Thousand Faces" now means all 6 kinds.
- Allies sprint to catch up and rejoin you if they're stuck far behind for a few seconds.
- The GitHub test run now reports each failed check, and its log is kept with the run.

### Fixed
- Entering a building could throw you back to the street a second later (the "fell out of the
  world" safety didn't know about interiors). People thrown around indoors no longer vanish.

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
