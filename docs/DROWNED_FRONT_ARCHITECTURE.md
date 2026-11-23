# Operation Drowned Front — Architecture (as inspected)

Written in Session Zero (22 Nov 2026) from the actual code at commit `0772251`
(tag `legacy-drowned-trenches-baseline`). Everything below was read in the
repository, not taken from the README; where the README is out of date it says so.
Update this document whenever an interface here changes.

## 1. Project facts

| | |
|---|---|
| Engine | Godot **4.7.2** stable; `project.godot` features `4.7`, `Forward Plus`. The Compatibility renderer also runs it (used for quick clip renders); the ground mist's volumetric fog and SSR/SSIL are Forward+ only. |
| Main scene | `scenes/game.tscn` → `scripts/game/game.gd` (`Game`) |
| Repository | `Accof/Jest-In-Pieces`, branch `main`, 1,359 tracked files, 492 MB (art 489 MB). Working tree clean at Session Zero; no stash; one earlier rollback tag `pre-trench-overhaul` (20 Nov 2026). |
| Tests | 36 headless scenes under `scenes/test_*.tscn` (`scripts/dev/test_*.gd`), plus window-only render scenes (`test_punch`, `test_soldier_pose`, `test_soldier_anim`, `test_seethrough`, `render_level`, `look_*`). No test runner: each scene is run on its own and prints `ok`/`FAIL` lines and a `NAME: n failed` total (some only print observations). Baseline results: tracker, Milestone 0. |
| Container | A working copy without `.git` lives in the cloud workspace; commits are made on the Mac (`~/ClownShooter`). Headless Godot and llvmpipe Forward+ renders (slow, 10–25 min a scene) run in the container. |

## 2. Floor flow (where the trench plugs in)

`Game` (`scripts/game/game.gd`, ~950 lines) owns the run.

```
start_run()                      floor_number = 0, player made, save touched
next_floor()                     floor_number += 1
  outdoor = is_trench_floor(n)   n % trench_every == 0   (trench_every = 3 → floors 3, 6, 9...)
  maze = TrenchMaze.new() if outdoor else Maze.new()
  maze.generate(size + 2, size, rng.randi())    TrenchMaze ignores the size: fixed 32 × 28 cells of 1.5 m
  _apply_floor_look(outdoor)     swaps WorldEnvironment.environment, camera_attributes, sun
  player placed at maze.cell_center(maze.start_cell)
  _build_exit()                  exit door at maze.exit_transform(); red until open
  events.new_floor()             steel doors / event rooms (bunker floors; none on a trench floor in practice)
  enemies spawned on maze.cells_far_from(start, span(3))   count × trench_enemy_scale outdoors (cap 26)
  if outdoor: battle = TrenchBattle.new(); battle.assign(maze, clowns, seed, spawn)
  remaining = clowns.size(); exit_open = false; state = PLAYING
```

**Objective today — one mode only.** `_on_clown_died()` decrements `remaining`; at 0 it sets
`_floor_finale`, runs the final-kill camera (`kill_cam.play(c)`, `KillCam`, `scripts/fx/kill_cam.gd`),
then the brutality report (`Injuries.assess`, `brutality.show_report`), then flashes `EXIT OPEN`,
sets `exit_open = true` and turns the exit light green. `_process()` offers upgrades
(`_offer_upgrades`) when `exit_open` and the player is within 1.3 m of `_exit`. The HUD
(`_refresh_hud`) prints `Clowns left: N`. There is no other killcam trigger: `test_killcam`
asserts "ordinary kills leave it alone, the last kill runs it once". The Carnival Curse, tickets,
`Records`, perks and saves hang off `_on_clown_died`/`_offer_upgrades`, not off `remaining`.

→ **Milestone 1 (done, 22 Nov):** `enum Objective { ELIMINATION, SURVIVAL }`, `Game.objective`
(set in `next_floor()`: SURVIVAL when `is_trench_floor()` and `survival_trenches`), `_open_exit()`.
On SURVIVAL the exit is opened in `next_floor()`, `_on_clown_died()` skips the finale/exit block, and
`_refresh_hud()` shows the objective. `_process()`'s exit check, `_offer_upgrades()`, `_pick_upgrade()`
→ `next_floor()` are unchanged and serve both modes. Nothing else reads `remaining`.

## 3. The legacy trench system (real files)

| File | Class | Lines | Role |
|---|---|---|---|
| `scripts/world/maze.gd` | `Maze` | 693 | The grid-maze base every floor uses. API in §4. `theme` is `"bunker"` / `"trench"` (the old funhouse trench-over-bunker look) / `"funhouse"`; `TrenchMaze` sets `"trench_outdoor"`. |
| `scripts/world/trench_maze.gd` | `TrenchMaze extends Maze` | 2,023 | Layout on a **1.5 m** grid (`TCELL`), fixed `GRID_W 32 × GRID_D 28`; rows `FIRE_ROW 6`, `SUPPORT_ROW 14`, `RESERVE_ROW 21`; `kind{}` per cell (`fire, traverse, support, reserve, comm, sap, op, stub, dugout, gunpit, flood, junction`); landmarks; `_carve()` one heightfield at `RES 0.2` m with a `MARGIN 12` m border → `vis_h` (rendered), `col_h` (walked: duckboard tops, eased fire steps), `sdf`, `wet`; `_bake_sky()` sky-visibility AO; footbridges and ramps (`bridge_at`, `ramp_at`, `on_top`); `_build_trench_world()` = `StaticBody3D "Ground"` with `HeightMapShape3D` + an `Edge` body on `LAYER_RAMP` (stops only the player) + `TrenchArt`. |
| `scripts/world/trench_art.gd` | `TrenchArt extends Node3D` | 2,297 | Dresses a `TrenchMaze` (`build(maze)`): carved mud mesh, revetments, duckboards, water, dugouts, props, No Man's Land wire and craters, far scenery (`FarFigures`, smoke columns, fires, ruins), ground mist volume. **Static** environment makers: `make_environment()`, `make_camera_attributes()`, `setup_sun()`, `make_grade()` (3D LUT). Shared with the bunkers: nothing; shared with `TrenchField`: `height_at`, `nml_posts`, `crater_list`, `smoke_material`, `make_plume`. `static var bounce_light := OS.has_environment("GI")` (SDFGI, off). |
| `scripts/world/trench_battle.gd` | `TrenchBattle extends Node3D` | 687 | Per trench floor: hands `BattleDuty` jobs to the floor's own enemies; the far side as effects only (flashes, flares, tracer); pace (`NORMAL/LULL/SURGE`, `calm`), encounters (a man sent across the player's way), calls and screams, soldier footsteps; makes `TrenchField` and `TrenchFog`. |
| `scripts/clown/battle_duty.gd` | `BattleDuty` | 451 | A job on a `ClownBrain`: `FRONTLINE, TOP_RIFLE, GUARD, SENTRY, RUNNER, PATROL, TRENCH_PATROL, MARKSMAN`; posts, beats, detours, its own senses (`hearing_bonus`, cones). Speeds are fractions of `brain.move_speed`. |
| `scripts/world/trench_field.gd` | `TrenchField extends Node3D` | 324 | ~7 real-bodied `FieldSoldier`s out in No Man's Land (z −4 to −62) holding craters and sandbag posts, firing *out* (never at the player), reinforced from the flanks, casualties by "shell" `Explosion`s. **Not on `game.clowns`** (not required kills); they walk `art.height_at`, no brain, no maze. Four heightmap strips give the far ground collision. |
| `scripts/clown/field_soldier.gd` | `FieldSoldier extends Clown` | 274 | HOLD / MOVE / DUCK / LEAVE states; ducks when shot at; never fights. |
| `scripts/world/trench_fog.gd` | `TrenchFog extends Node3D` | 247 | Fog banks (billboard puffs + density into the ground-mist shader) and heavy spells. **`visibility(a, b)`**: Beer–Lambert through banks; `ClownBrain._can_see_player()` returns false beyond 6 m when < 0.3; the marksman will not fire through it. |
| `scripts/world/trench_ambience.gd` | `TrenchAmbience extends Node3D` | 282 | Wind, gun rumble, far shells (flash → boom by speed of sound → smoke), far MG/rifle, creaks, drips, rattles, music box. All `SfxSynth` placeholders. |
| `scripts/world/far_figures.gd` | `FarFigures extends Node3D` | 94 | Skyline files of walking silhouettes. Scenery only. |
| `shaders/` | | | Trench-only: `overcast_sky`, `mud_terrain` (floor_darkness, sky_occlusion, sky_floor; parallax floor), `water_mud`, `ground_mist`, `pbr_object` (object-space PBR for props; sky_floor, sky_occlusion), `wire_sway`, `balloon_sway`, `cloth_wind`, `ripple`. |
| `art/trench/` | | 138 MB | `polyhaven/brown_mud_03_*_2k.png` (floor), `pbr/<set>/<set>_<map>_2k.png` (brown_mud, rocks_ground_08, rough_wood, hessian_230, rusty_metal_04), generated muds from `tools/gen_trench_textures.py`, `circus_bill.png`, noise. Treated as immutable. |
| Tests | `scenes/test_trench.tscn` (`test_trench.gd`: 30 layouts, connectivity, lengths, landmarks — 4 s) and `scenes/test_trench_level.tscn` (`test_trench_level.gd`, 2,600+ lines: sections `layouts ground geo nav overhaul field fogbank top suspense battle falls perf game bodies ambience` headless, and with `render`: `battleviews views floor normals relief walls parallax section cine light`). `test_nav -- trench`. |

The README's "Drowned Trenches" section (lines 60–158) predates the battle, the field, the fog
banks, bridges and the top-of-trench duties; it still describes the ground and dressing correctly.

### What the legacy level is *not*
- No damage from outside the floor's own enemies (field soldiers, far side, shells: cosmetic).
- No bullet impacts on the world at all (see §6).
- One trench system; No Man's Land is scenery past z = 0 (wire, craters, far ground strips) with the
  field soldiers in it, but the player is walled in by `Edge` (`LAYER_RAMP`) at the carved margin.
- The exit is at the far end of the fire trench, opened by the kill count.

## 4. The `Maze` API the enemies, gore, killcam and events depend on

Any new generator **must** satisfy this (it is what `ClownBrain`, `Game`, `KillCam`, `Blood`,
`CarnivalCurse`, `EventManager` and the tests call):

```
w, d, cell                      grid size and cell size (m)
open_cells{}, links{"a|b"}      topology; linked(a, b), is_open(c), in_bounds(c), idx(c)
route: Array[Vector2i]          start → exit cells (the player is turned to face route[2] outdoors)
start_cell, exit_cell           ; exit_transform() -> Transform3D
level[], trench_cells{}, side_cells{}, rooms[], stairs[]
generate(width, depth, seed)
cell_center(c) -> Vector3       (y = floor_height)
cell_of(pos) -> Vector2i
floor_height(pos) -> float      the walked surface (TrenchMaze: col_h + bridges)
keep_walkable(pos) -> Vector3
path(from, to) -> Array[Vector3]        A* over cells (AStar2D)
path_cells(a, b) -> int                 (hearing: ClownBrain.hear compares to span(hearing_cells))
cells_far_from(c, min_steps) -> Array[Vector2i]   (spawn placement)
span(bunker_cells) -> int       distances scaled from 3 m bunker cells to this grid
scale() -> float                cell / CELL
top_height(), ceiling_height(c), is_trench(c)
LAYER_WORLD = 1, LAYER_RAMP = 1 << 4
```
`TrenchMaze` adds `kind{}`, `trenches{}`, `bays{}`, `flooded{}`, `collapsed{}`, `landmarks[]`,
`surface_at(pos)` (footstep surface), `water_level(pos)`, `ground_height(x, z)`, `on_top(pos)`,
`bridge_at`, `ramp_at`, `wall(c, dir)`, `sky_at_index`, `sky_texture()`, `ascii()`.
`TrenchBattle`, `BattleDuty`, `TrenchField`, `TrenchFog`, `ClownBrain` (`_onto_bridge`, trench
checks) all type against `TrenchMaze`.

## 5. Enemies and perception (what the director will drive)

- `Clown` (`scripts/clown/clown.gd`, 3,618 lines): bodies table `BODIES` (`clown`, `witzsoldat` with
  looks `witzsoldat`/`witzsoldat_dark` 50/50, `klappersoldat`, `rattlejack`, `zornhauptmann`), ragdoll
  (`ClownRagdoll`), gore (`ClownGore`), anatomy, helmets, rifle/club/gun, motion-capture clip layer
  (`SoldierClips`, `_clip_layer`), per-man grime. Subclasses `Klappersoldat`, `Rattlejack`,
  `Zornhauptmann`, `FieldSoldier`.
- `ClownBrain` (`scripts/clown/clown_brain.gd`, 1,505 lines): `Mind {IDLE, HUNT, SEARCH}`; `alert(where,
  startled, firsthand)`; **hearing is local**: `hear(where, extra)` compares `maze.path_cells` to
  `span(hearing_cells + duty bonus)` (`hearing_cells 4`); **sight is local**: `_can_see_player()` =
  ray + cone + `TrenchFog.visibility`; `_on_hurt` alerts witnesses within `witness_range` (7 m) with a clear
  line; `near_miss()` (suppression, dodge); cover (`use_cover`, peeks), weighty movement, transit
  clips, `duty: BattleDuty`. `game._on_player_fired` calls `hear()` on every clown with the weapon's
  loudness; each decides by path distance. There is no squad layer; `others` is the floor's list.
- Speeds (after commit `3b7ac62`): walk 1.8–2.3, run 3.9–4.6 m/s; player 3.2 / 4.9.
- Existing MG: `scripts/events/mounted_gun.gd` (the Maxim in the MG-nest event: overheat, [E] to
  mount, rippable) and the Rattlejack's Lewis gun (`rattlejack.gd`: bursts, pan changes). Nothing
  yet fires an MG *at* the player from a fixed emplacement with arcs.
- Explosions: `scripts/fx/explosion.gd` profiles `drum`, `grenade`, `shell` (`noise_cells −1`, so
  trench soldiers don't hear it); scorch `Decal`; frag damage. Grenades: `scripts/weapons/grenade.gd`.

## 6. Weapons and world hits (Milestone 5 baseline)

`FpsPlayer.shoot_ray()` (`scripts/player/fps_player.gd` ~695) casts on `LAYER_WORLD | LAYER_RAGDOLL`;
`_near_misses()` for everyone along the line; then: a collider with `shot()` (drums, targets) is
told; a `PhysicalBone3D` with meta `clown` is `_hit_clown` (+ `_pierce`). **A world hit does
nothing**: no particle, no mark, no sound. Enemy rifle fire (`ClownBrain._fire()` ~1320,
`BattleDuty` marksman ~305) also raycasts and ignores world hits. Blood (`scripts/blood/`) owns the
only persistent marks today (pools, splatters on walls/floor via its own projection), the
explosion its scorch decal. There is no surface classification on colliders: the ground is one
`HeightMapShape3D` (`TrenchMaze.surface_at(pos)` knows mud/duckboard/water/firm for footsteps);
linings are thin `StaticBody3D` boxes made by `TrenchArt`; bunker walls are boxes from `Maze`/`LevelArt`.

→ A `SurfaceImpactManager` hooks into `shoot_ray`'s empty branch, the enemy raycasts and the
mounted gun, classifies by (a) meta on the collider set by the dressers, (b) `surface_at` for the
heightfield, (c) a fallback by material, and budgets its own particles and decals.

**(M5, as built):** the autoload `Impacts` (`scripts/fx/surface_impacts.gd`) is that manager; see
the tracker's M5 record and D-07 for the surfaces, hooks and budgets. The soldiers' rifles still
roll to hit; a miss now also casts on into the world so the round lands somewhere real.

## 7. Atmosphere (Milestone 4 baseline)

`TrenchArt.make_environment()`: custom `overcast_sky` shader sky (storm clouds, hidden sun
`LIGHT_DIR`), ambient from sky (energy 0.75), filmic tonemap (white 6), SSR, SSAO (1.6), SSIL,
depth fog `fog_light_color (0.47, 0.52, 0.58)`, density 0.82, **begin 18 m**, end 320 m, curve 1.7,
aerial perspective 0.6; volumetric fog enabled at density 0 (only the ground-mist volume adds to
it; anisotropy 0.55, length 90 m); glow 0.3; adjustments (saturation 0.92, contrast 1.08) with a
cold 3D LUT (`make_grade`). `make_camera_attributes()`: auto exposure (scale 0.2, max sensitivity
125) for dugout adaptation. `setup_sun()`: energy 0.85, cool colour, shadows. Baked sky visibility
darkens ground and props (`sky_occlusion`, `floor_darkness 0.52`), not enemies. The bunkers use
`Game._build_environment()` (`ProceduralSkyMaterial`, dark) and `_bunker_env`; the swap is
`_apply_floor_look()`; the base and menu reuse the bunker environment. So **atmosphere is already
isolated per floor type**; the new front needs its own `make_environment` variant (green-grey,
fog begin near 0 with a 30–60 m recognition distance) and must leave `_bunker_env` alone.

**(M4, as built — pending the visual gate):** `FrontAtmosphere.make_environment()` is that variant
(settings in D-16); `Game._apply_floor_look()` takes it when `maze is FrontMaze`, else the legacy
`TrenchArt` one, else `_bunker_env`. The brains' `fog` group query is answered on the Front by the
`FrontAtmosphere` node (exp(−k·d), 0.3 at 55 m, smoke patches added), on the legacy level by
`TrenchFog` as before.

User history on lighting (Nov 2026): SDFGI was tried and rejected (too bright, "sunny", hitches);
brighter overall "lost its grittiness". The reference image is darker and greener than the current
storm-sky look, with much nearer fog.

## 8. Audio

`SfxSynth` (`scripts/fx/sfx_synth.gd`) synthesises every sound at runtime (guns, steps, shells, wind,
screams, calls); `TrenchAmbience` and `TrenchBattle` schedule the battlefield layers. Each is a named
slot and "replaceable by a .wav" per the README; there are no recorded assets. Occlusion/interior
filtering: none beyond distance attenuation and `AudioStreamPlayer3D` defaults.

## 8a. The Front (Milestone 2, as built)

| File | Class | Role |
|---|---|---|
| `scripts/world/front/front_maze.gd` | `FrontMaze extends TrenchMaze` | `generate()`: two scratch `TrenchMaze._layout()`s merged (`_merge`, theirs through a 180° turn), `facing{}`, `ours{}`/`theirs{}`, assault ramps (`_assault_candidates`, `_assault_ramps`), `_finish_front()` (graph, ramps, bridges, depths, carve, top layer, **then** the route), `timing{}`. Facing-aware overrides listed in D-02. `cells_far_from` walks the A* graph (ramps and the top included). |
| `scripts/world/front/front_art.gd` | `FrontArt extends TrenchArt` | `build()` → `super.build()`; overrides `_parapets`, `_fire_steps`, `_wire` (+ `_wire_belt`), `_no_mans_land`, `_mist`. |
| (M3) `FrontMaze.wire_belts` / `wire_at()` / `wire_cells` | | the wire plan; cells under it leave the top layer in the `_top_layer` override; `FrontArt._wire_body` (`LAYER_RAMP`) stops the player. Shell holes: cosine bowl + lip in the `_carve` copy, deeper-wins merge. |
| (M3) `FpsPlayer.crouch`, `eye_height()`, `chest_height()` | | Ctrl/C crouch; (M6) the brains and the MGs read the heights. |
| (M6) `scripts/world/front/front_threats.gd`, `front_mg.gd`, `front_artillery.gd` | `FrontThreats`, `FrontMg`, `FrontArtillery` | the enemy Maxims on their parapet (real rays, arcs, belt, heat, mortal gunner, `MountedGun` as the piece) and the salvos (whistle, `Explosion` shell, fairness rules); `Game.threats`. `FpsPlayer.suppress()`. D-17. |
| (M4) `scripts/world/front/front_atmosphere.gd` | `FrontAtmosphere extends Node` | the Front's `make_environment()` / `make_camera_attributes()` / `setup_sun()` (static; `Game._apply_floor_look` uses them, cached in `_front_env`), and the node `FrontArt` adds under the art as "Atmosphere": group `fog`, `visibility(a, b)`, `sight_range()`, `smoke_patches` (D-16). |
| (M4) `scripts/world/front/front_fog.gd` | `FrontFog extends TrenchFog` | the legacy fog banks for the Front's geometry (spawn sides, cadence, two at load); not in the `fog` group, `FrontAtmosphere.front_fog` multiplies it in. |
| (M4) `FrontArt.ground_material()`, `_drift_smoke()`, `_mist()` | | the soaked dark ground parameters, the low drifting smoke, the green-grey mist volume; the far smoke columns thinned in `build()`. |
| `scripts/world/exit_door.gd` | `ExitDoor` | the [E] door on SURVIVAL floors (M1 follow-up). |
| `scripts/game/game.gd` | | `next_floor()`: `FrontMaze` when outdoor and SURVIVAL, `TrenchMaze` when outdoor and the legacy rule, `Maze` otherwise; no `TrenchBattle` on a `FrontMaze`; a `Drowned Front: …` build line printed. |
| `scenes/play_front.tscn` (`scripts/dev/play_front.gd`) | | straight into the Front (`seed=`, `floor=`, `god`, `perf=`). |
| `scenes/test_front.tscn` (`scripts/dev/test_front.gd`) | | sections `layouts`, `geo`, `game`, `views` (render). |

Build cost headless in the container: ~3.8 s a floor (carve ~2.5 s of it) for 336k heightfield
samples; the legacy floor was ~4.2 s with its battle. The Mac is unmeasured (D-10 pending).

## 9. Integration risks found in the code

1. **`TrenchArt` is welded to `TrenchMaze`** (`build(self)`, reads `kind`, `bays`, `vis_h`, `sdf`,
   `wet`, bridges). Reusing its dressing for two networks on one heightfield means either (a) the new
   front owns one bigger heightfield and feeds `TrenchArt`-derived dressers per network, or (b) a
   refactor that extracts a `TrenchDresser` from `TrenchArt`. (b) risks the legacy level; (a) copies
   code. Decide in Milestone 2 after a prototype (D-02).
2. **Fixed grid.** `TrenchMaze.generate` ignores width/depth. The front needs two networks ~33 × 27
   cells each plus 55–80 cells of No Man's Land: one heightfield of roughly 200 × 70 m at 0.2 m =
   ~350k samples (today ~120k). `_carve`/`_bake_sky` cost scales with it (today's trench builds in a
   few seconds headless); measure.
3. **The player is walled in by `Edge`.** The front must remove that wall between the networks and
   give the crossing real collision (today `TrenchField`'s strips exist only for bodies and rounds).
4. **`Maze` A\* is cell-based.** No Man's Land is not a trench grid; enemy navigation out there today
   is `FieldSoldier`'s own (`art.height_at`, straight dashes). Enemies that must chase across craters
   need either an open-ground cell grid (coarse, e.g. 1.5 m cells with slope/water costs) or a
   `NavigationRegion3D` baked from the heightfield. Prototype in Milestone 3.
5. **Everything types against `TrenchMaze`.** `TrenchBattle`, `BattleDuty`, `TrenchField`,
   `TrenchFog`, `ClownBrain._onto_bridge` check `maze is TrenchMaze`. A new `FrontMaze` either
   extends `TrenchMaze` (inherits the fixed layout code; override `generate`) or those checks become
   an interface (`has_method`). Extending is the least invasive.
6. **Killcam/finale coupling** is small and clean (§2); the risk is the brutality report and
   `EXIT OPEN` banner assuming a last kill. On SURVIVAL floors they simply never fire.
7. **Performance is already near budget.** The battle adds ~1.1–1.6 ms CPU; fog-bank puffs are heavy
   overdraw on llvmpipe; the Mac GPU is unmeasured. Pose LOD exists (`Clown.pose_lod`). A larger map
   with more soldiers needs the simulation tiers from the package (E1) early, not at Milestone 12.
8. **Tests that fail intermittently today** (tracker, M0): suspense "men cross the player's way",
   Rattlejack fire/pan, officer combat, killcam `low_side`, curse neck-snap angles. Unseeded mazes
   put spawns behind walls. New tests must seed.
9. **No window in the container.** Visual gates need llvmpipe renders (minutes per frame with the
   volumetric mist) or the user's Mac. Milestone 4 screenshots will be real Godot renders, but the
   final judgement needs the Mac.
