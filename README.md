# Jest In Pieces

Godot 4 project (built and tested on 4.7.2, needs 4.4 or newer for built-in Jolt physics).
Everything is GDScript and builds itself in code, so there is nothing to wire up in the editor.

## Run it

1. Open `project.godot` in Godot. The first import takes a few seconds.
2. Press Play. The main scene is the game, `scenes/game.tscn`.
3. The old test room is still there: open `scenes/gore_sandbox.tscn` and press "Run Current Scene". Backspace resets it.

| Key | Action |
|---|---|
| WASD, mouse | Move, look |
| Shift | Sprint |
| Left click (hold) | Fire |
| R | Reload |
| 1 / 2 | Pistol / shotgun |
| F | Flashlight |
| Enter | Start a run, or leave the death screen |
| 1 / 2 / 3 | Pick an upgrade, or buy a perk on the menu |
| Esc | Free the mouse |

## The game

- Each floor is one winding route: a short stretch of open trench, then down into a dieselpunk concrete bunker. Corridors run straight for a few cells at a time, framed by concrete pillars and steel beams, lit by caged bulbs, with wet floors, pipes and steel doors. There are a couple of stairwells down, a few wider halls (dormitory, mess, stores) and dead-end side rooms. A little of the circus survives: faded harlequin paint, a stencilled star, a clown's face over the way in, an old drum in the mess.
- Kill every clown, then find the door (it turns green) to leave.
- After each floor you pick one of three upgrades. Floors get bigger, with more clowns and more gunmen.
- Kills earn tickets (two for a headshot). When you die they are banked and can be spent on permanent perks on the menu.

## Fuel drums

Red fuel drums stand in corners of the bunkers and halls (more on bigger floors). Shoot one and it goes up: a hard hit sets it off at once, a lighter one punches a hole that spits flame for a second first. Drums near a blast go up too.

How badly a clown comes apart depends on how close it was (and whether anything stood between it and the drum):

- **Right next to it:** thrown across the room or into the walls, two or three limbs torn off, belly and ribs blown open, often part of the skull gone. Every part that hits a wall at speed bursts blood across it.
- **A couple of metres:** guts out, ribs showing, maybe a piece of skull and a limb, flung a few metres.
- **Further:** peppered with wounds and knocked down, or knocked about and very angry.
- **Torn in half (40% of clowns caught at 1-3 m):** the legs go flying, the torso lives. It drags itself away from you on its hands, guts trailing, smearing a blood trail and stopping to gasp in its own pool. It bleeds out after a minute, or you can finish it.

The blast hurts you too (up to 85 at point blank, much less behind cover) and shakes the view. In the gore sandbox there are three drums among the clowns.

## Enemies

| Enemy | Body | How it fights |
|---|---|---|
| Clown | `art/clown/` | Melee, or a pistol (gunmen strafe and keep their distance) |
| WitzSoldat | `art/witzsoldat/` | Bolt-action rifle: slower to aim and reload, 24 damage a hit, reaches 24 m. Helmet comes off on half of headshots, always on a shotgun blast to the head |

Every body uses the same 21 bone names and 15 dismemberment segments, so the ragdoll, deaths and gore work on all of them. A new body is added to `Clown.BODIES` in `clown.gd`: model, gibs, the rest-pose box from its `.json`, how much thicker its collision shapes are than the clown's, and optionally a helmet.



| Path | What it does |
|---|---|
| `scripts/clown/clown.gd` | One enemy (clown or WitzSoldat): body, hit zones, health, death reaction, helmet, weapons |
| `scripts/clown/clown_ragdoll.gd` | Physical skeleton, joint limits, muscle tone and death profiles |
| `scripts/clown/clown_gore.gd` | Wounds on the body, bleeding, pooling, limb loss |
| `scripts/clown/gib.gd` | A severed body part |
| `scripts/clown/gore_bit.gd` | Meat chunks, skull fragments, links of gut |
| `scripts/blood/blood_manager.gd` | Autoload `Blood`: splatter decals, droplets, mist, pools |
| `shaders/clown_body.gdshader` | Bullet dents, blood soaking into cloth, hiding severed limbs |
| `shaders/blood_pool.gdshader` | The spreading pool |
| `scripts/player/fps_player.gd` | Player, health and the two weapons |
| `scripts/player/view_model.gd` | First-person hands and guns, recoil and reload animation |
| `scripts/game/game.gd` | Run loop, floors, upgrades, perks, menu, saving |
| `scripts/world/maze.gd` | Maze generator, stairs, pathfinding, collision; `theme` picks the linear bunker (default), the trench maze, or the old funhouse |
| `scripts/world/explosive_barrel.gd`, `scripts/fx/explosion.gd` | Fuel drums and the blast (fire, smoke, sparks, scorch, shock wave) |
| `scripts/clown/clown_crawler.gd` | A clown torn in half, crawling away until it bleeds out |
| `scripts/world/level_art.gd` | The trench and bunker look: walls, floors, props, lanterns |
| `scripts/clown/clown_brain.gd` | Clown AI: hunting, melee, gunmen |
| `shaders/funhouse.gdshader` | Checker floors and striped walls |
| `tools/gen_blood_textures.py` | Regenerates the splatter textures in `art/blood/` |
| `tools/gen_level_textures.py` | Regenerates the level textures in `art/level/` (planks, mud, harlequin, poster...) |

## Tuning the feel

All of these are in `clown_ragdoll.gd`.

- **Speed and weight of the fall:** `fall_speed` plays every death faster (1.0 is the original timing); `fall_weight` is extra gravity while going down (1.0 is real gravity).
- **How different each death is:** `variation` (0 = identical every time).
- **Arms:** `arm_fling` (how far the arms are thrown out at death).
- **Floppy vs stiff corpse:** `dead_joint_friction`. Higher is heavier and stiffer.
- **How a clown goes down:** `profile_headshot()` and `profile_bodyshot()`. Each has named variants picked at random: back, back_flat, stagger_flat, sit, spin, side, crumple, knees_flat, knees_hang, stumble for headshots (plus knees, by name only); stagger, blown_back, double, double_flat for body shots; heavy_flat for shotgun kills; wall_slide when a wall is close behind the clown (picked 80% of the time when it applies). The curves are explained in the comment above them; each point is `Vector2(seconds, value)`. To make a fall faster and heavier, pull the `support` and `sink` points earlier.
- **Testing one fall:** set `force_variant` on a clown (for example `"knees_flat"`) and every death uses it.
- **Head snap:** the headshot impulse in `clown.gd` (`dir * 27.0`) and the first points of the `neck` curve.
- **Flinches:** `flinch_strength` on the clown. 0 turns them off.
- **Joint ranges:** the `x`, `y`, `z` limits in `defs()`, in degrees from the T-pose.
- **Shotgun damage to the body:** `blast_damage` on the clown is how much one shot must do to the torso or head to blow a hole in it. Hole sizes are in `clown.gd` where `gore.blast` is called.
- **Twitching corpses:** `twitch_chance` in `clown_ragdoll.gd`.
- **Clown speed and tactics** (in `clown_brain.gd`): `run_speed`, `run_burst`, `run_rest`, `keep_distance` (the range gunmen hold), `weave_rate`.
- **WitzSoldat:** `helmet_pop_chance` in `clown.gd`; his rifle numbers are in `rifleman()` in `clown_brain.gd`; how many appear per floor is `soldier_share` in `game.gd`.
- **How easily limbs come off:** `dismember_damage` on the clown, and `can_dismember` per weapon in `fps_player.gd`.
- **What clowns notice** (in `clown_brain.gd`): `sight_range`, `sight_half_angle`, `hearing_cells` (how far a gunshot carries along the corridors), `witness_range` (how close a clown must be to notice another being shot), `give_up_after`.
- **Level layout:** in `maze.gd` `_generate_linear()`: route length (`w * d * 0.42`), number of stairwells, halls and side rooms. **Level look:** `theme` ("bunker", "trench" or "funhouse"), `TRENCH_DEPTH` and `BUNKER_HEADROOM`. In `level_art.gd`, `_bunker_wall_detail` sets how often walls get paint, doors or posters, and `_bulb` the light brightness, range and how many are dead or flickering. In `level_art.gd`, the chances in `_trench_wall_props`, `_dress_trench` and `_dress_bunker` set how much bunting, wire, posters and clutter appear; lantern brightness is the energy passed to `_lantern`. Sky, fog and the dusk light are in `_build_environment()` in `game.gd`.
- **Explosions:** `RADIUS` and `PLAYER_DAMAGE` in `scripts/fx/explosion.gd`; `toughness` on the drum (`explosive_barrel.gd`); how hard and how messily clowns are thrown in `caught_in_blast()` and `_blast_gore()` in `clown.gd`; `crawl_chance` on the clown for being torn in half; `life` and `speed` in `clown_crawler.gd`; how many drums per floor in `_dress_bunker()` in `level_art.gd`.
- **Blood budget:** `MAX_DECALS`, `MAX_POOLS`, `DRY_TIME` in `blood_manager.gd`.

## Checks

These run without opening the editor:

```
godot --headless --fixed-fps 60 res://scenes/test_joints.tscn   # every joint driven to both ends of every axis
godot --headless --fixed-fps 60 res://scenes/test_death.tscn    # timeline of each death reaction
godot --headless --fixed-fps 60 res://scenes/test_game.tscn     # 40 mazes checked, then one pass round the game loop
godot --headless --fixed-fps 60 res://scenes/test_blast.tscn    # a drum among clowns at set distances: gore, throw, the crawler
godot --path . res://scenes/render_level.tscn                  # saves views of a level to /tmp/lvl_*.png (needs a window)
```
