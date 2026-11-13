# WePlay: Laser-Equipped Drone Swarms

**Not a turret: a swarm that flies out to the nests on a one-way trip.**

A Factorio mod. Load attack drones into a launchpad and it launches the little airplanes down its runway one at a time. They circle overhead until the swarm is ready, then the airplanes fly out together to the nearest charted biter nest, up to 1000 tiles away. Over the nest they break formation, wheel around it in every direction and pulse-laser the nests and worms until their batteries run dry. An alternative to artillery, with a lot more chaos.

![Attack drones swarming over biter nests and worms](ATTACK_GIF_DIRECT_LINK)

**Requires Factorio 2.1** and [WePlay: Flight Library](https://mods.factorio.com/mod/WePlayFlightLib). Space Age is optional.

## ✨ Features

- 🛩️ **A real swarm.** Drones circle the launchpad on their own rings, meet up on the way out as a loose cloud, then peel off one by one over the target, banking into their turns.
- ⚡ **Pulse lasers.** Each drone locks a green beam onto a nest or worm for 3 seconds, rests for 1, then fires again (or set the beams to continuous). Nests and worms come first; biters only get shot when there's nothing else in reach.
- 🎯 **Finds its own targets.** Swarms go after the nearest charted nest within 1000 tiles, then move on to the next nest while they still have battery left. Swarms from different launchpads won't pile onto the same nests.
- 🗺️ **Reveals the map like artillery** around the swarm on the way out and over the target.
- 💥 **Biters fight back.** Nests send their revenge at the launchpad, just like with artillery.
- 🔁 **Waves, not a flood.** One attack out at a time per launchpad: it launches just enough drones for the next swarm, which circles overhead until the last attack run is over.
- 🔌 **Circuit network.** The launchpad outputs drones in the launchpad, drones circling it, and attack in progress (1 or 0).
- 📦 **Easy to move.** Mining a launchpad packs up the swarm circling over it along with the pad.

![Attack drones circling their launchpad](https://i.imgur.com/tWV8YRI.gif)

## 🎮 How to use it

1. Research **Attack drones** (red, green, military and blue science).
2. Build an **attack drone launchpad** (5x5) and power it: 100 kW idle, 2 MJ per launch.
3. Load **attack drones** into it, by hand or with inserters.
4. Set the **squad size** in the launchpad's panel. When that many drones are circling, they fly out.

Drones are one-way: when their attack run ends, they go down wherever they are.

## 🔬 Research

| Research | Effect |
|---|---|
| Attack drones | Unlocks the launchpad and attack drones |
| Drone endurance 1 / 2 | Attack runs last 15 s → 30 s → 60 s |
| Swarm size 1 / 2 | Largest swarm 5 → 10 → 30 drones |
| Laser damage (vanilla, and any mod's) | Boosts drone laser damage like any other laser |

## ⚙️ Settings

| Setting | Type | Default | What it does |
|---|---|---|---|
| Laser style | Map | Pulsing | Pulsing (3 s on, 1 s off) or a continuous beam. Same damage per second either way. |
| Hard mode | Startup | Off | Every attack drone needs a laser turret in its recipe. |

`/wp-drone-swarms-clear` (admins) removes every attack drone in the air.

## 🧭 How it works

- Drones aren't entities. Each one is a set of sprites (hull, glow and shadow) that the script draws and moves every tick using [WePlay: Flight Library](https://mods.factorio.com/mod/WePlayFlightLib), which handles the runway takeoff, turning circles, circling, formation flying, altitude and banking. In testing, a swarm costs about 0.1 ms per tick in flight and just under 0.2 ms while attacking.
- The launchpad is a chest (one prototype per direction, swapped in from a rotatable placer, like Long Haul Logistics). A hidden electric interface powers it and a hidden constant combinator, joined by script wires, outputs its signals.
- Swarm life cycle: **loiter** (each drone on its own ring around the pad) → **transit** (everyone flies to a rally point about 30% of the way, timed to arrive together, then follows the leader as a loose cloud) → **attack** (the leader breaks onto its ring and the wingmen peel off one by one) → **crash** when the attack timer runs out.
- Beams are stretched, rotated sprites on the `higher-object-above` render layer, so they pass under the drones. Damage is dealt by script with the launchpad as the cause, so biters retaliate against it.
- Laser damage research is read from the force's laser damage bonus, so any mod's laser research works. `data-final-fixes.lua` adds an "Attack drone laser damage" line to every research that raises it.
- Balance numbers shared by the data and control stages (damage, ranges, attack times, swarm sizes) live in [`shared.lua`](shared.lua). Everything else (launch rate, rings, swarm wobble, meet-up speeds, beam look) is a constant at the top of [`control.lua`](control.lua).

## 🎨 Development

### Repository layout

```
├── info.json
├── settings.lua            # laser style, hard mode
├── shared.lua              # numbers used by both data and control stages
├── data.lua                # prototypes: launchpad, items, recipes, research, signals, sprites, sounds
├── data-final-fixes.lua    # adds the drone line to laser damage research
├── control.lua             # runtime: launching, swarms, targeting, lasers, GUI, signals
├── changelog.txt
├── thumbnail.png
├── locale/en/locale.cfg
├── prototypes/
│   └── launchpad-sprite.lua    # launchpad sheet sizes and shifts (from pack_sprites.py)
├── Sheets/                 # drone sprite sheets + drone-animations.lua (from pack_drone_sprites.py)
├── sound/
└── graphics/
    ├── entity/             # launchpad sheets, laser beam and bead textures
    ├── icons/
    └── technology/
```

### Art pipeline

The drones and launchpad are rendered in **Blender** with an orthographic camera at 64 px per tile (sprites use `scale = 0.5`).

- **Drones:** 5 bank angles × 64 headings, rendered as separate **hull**, **glow** (Emission pass) and **shadow** (shadow catcher) passes, one PNG per frame. Factorio animations can't have more than 255 frames, so the 320 frames are packed as one 64-frame animation per bank:

  ```bash
  python3 pack_drone_sprites.py --hull renders/hull --glow renders/glow --shadow renders/shadow \
      --out Sheets --mod-root . --mod WePlayDroneSwarms --scale 0.5 --split-banks 5
  ```

  This trims every frame to the shared bounding box (`--alpha-threshold 16` clears shadow-catcher haze first), writes `drone-hull-0..4.png`, `drone-glow-0..4.png` and `drone-shadow-0..4.png`, and generates `Sheets/drone-animations.lua` with the sizes and shifts. The glow pass is stored white with brightness in the alpha, and tinted green in game.

- **Launchpad:** 4 directions, diffuse and shadow, packed with `pack_sprites.py`. `PAD_SHIFT_NUDGE` in `data.lua` lines the sprite up with its 5x5 footprint without re-rendering.

## 🔗 More WePlay airplanes

- ✈️ [WePlay: Long Haul Logistics Drones](https://mods.factorio.com/mod/WePlayLongHaulLogistics): swarms of cargo airplanes linking your outposts to your main base, with no coverage map.
- 🛰️ [WePlay: Radar Probe Drone Launcher](https://mods.factorio.com/mod/WePlayRadarProbeDroneLauncher): survey airplanes that fly out into the fog and land as radar probes.

See all WePlay mods on the [mod portal](https://mods.factorio.com/user/afewvowels).

## 📜 License

Released under the [Unlicense](LICENSE): the code is in the public domain, so do whatever you like with it.
