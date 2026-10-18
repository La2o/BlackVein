# Mixamo characters and animations

Mixamo (by Adobe) gives free, motion-captured characters and animations that can be used in games,
including commercial ones. It's the fastest way to get Prototype-style people into BLACKVEIN.

**Licence note:** you may ship them inside the game, but not share the raw files. The repo is public,
so `assets/mixamo/` is git-ignored: the files live only on your PC and inside the exported builds.

## 1. Sign in

Go to <https://www.mixamo.com> and sign in with a free Adobe account.

## 2. Characters (Characters tab)

Download each with these settings:
**Format: FBX Binary (.fbx) · Pose: T-pose** (it includes the skin by default).

| For | Search for | If it isn't there |
|---|---|---|
| The player (you) | **"hoodie"**: a man in a hooded jacket, the Alex Mercer look | any male in a jacket or coat |
| Soldiers | **Swat** | Vanguard By T. Choonyung |
| Civilians (men) | **Remy**, **Malcolm**, **Big Vegas** | any 2-3 casual men |
| Civilians (women) | **Michelle**, **Kaya** | any 2-3 casual women |
| Scientists | **"doctor"** or **"lab"** | a man and a woman in a shirt |
| Infected | **Zombiegirl W Kurniawan**, **Mutant** | any zombie |
| Hunters / big monsters | **Warrok W Kurniawan**, **Parasite L Starkie** | any large creature |
| Fallback for everything | **Y Bot** | – |

## 3. Animations (Animations tab)

First select **Y Bot** as the character (top right), so every animation uses the same skeleton.
Download each with:
**Format: FBX Binary (.fbx) · Skin: Without Skin · Frames per second: 30 · Keyframe Reduction: none**.
For anything that walks or runs, tick **In Place**.

Names may differ slightly. Pick the closest match.

| Group | Animations |
|---|---|
| Moving | Breathing Idle, Walking, Running, Fast Run, Crouched Walking |
| Jumping & falling | Jump, Running Jump, Falling Idle, Hard Landing, Front Flip, Backflip |
| Parkour | Climbing (up a wall), Braced Hang, Freehang Climb |
| Fighting (player) | Punching, Hook Punch, Uppercut, Hit Reaction |
| Soldiers | Rifle Idle, Rifle Walk, Rifle Run, Firing Rifle, Toss Grenade, Reloading |
| Civilians | Talking, Texting, Waving, Terrified, Running (scared), Sitting |
| Infected & monsters | Zombie Walk, Zombie Running, Zombie Attack, Zombie Scream, Mutant Swiping, Mutant Roaring |
| Everyone | Dying, Death From The Front |

## 4. Where to put them

```
C:\Users\ygsna\BLACKVEIN\assets\mixamo\characters\    <- the character .fbx files
C:\Users\ygsna\BLACKVEIN\assets\mixamo\animations\    <- the animation .fbx files
```

Keep Mixamo's file names. Then tell Claude; it'll import them, build the animation sets and swap the
code-built people for the new ones.
