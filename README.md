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
| 1 / 2 / 3 / 4 | Pistol / shotgun / submachine gun / stake gun |
| E | Use: open a steel door, man a mounted gun, rip it off its mount |
| 5 | The Maxim, once you have torn it off its mount |
| 6 | Bolt-action rifle |
| G | God mode on/off (take no damage; for testing, stays on across runs until you turn it off or quit the game) |
| F | Flashlight |
| Enter | Start a run, or leave the death screen |
| 1 / 2 / 3 | Pick an upgrade, or buy a perk on the menu |
| Esc | Free the mouse |

## The game

- Each floor is one winding route: a short stretch of open trench, then down into a dieselpunk concrete bunker. Corridors run straight for a few cells at a time, framed by concrete pillars and steel beams, lit by caged bulbs, with wet floors, pipes and steel doors. There are a couple of stairwells down, a few wider halls (dormitory, mess, stores) and dead-end side rooms. A little of the circus survives: faded harlequin paint, a stencilled star, a clown's face over the way in, an old drum in the mess.
- Kill every clown, then find the door (it turns green) to leave.
- After each floor you pick one of three upgrades. Floors get bigger, with more clowns and more gunmen.
- Kills earn tickets (two for a headshot). When you die they are banked and can be spent on permanent perks on the menu.

## Steel doors

Every steel door in the bunkers (up to four a floor) leads somewhere. A red sign means a set piece; amber means something odd. [E] to go in: the screen fades, the door bolts behind you, and the exit stays shut until the room is done. Rewards are tickets, health and sometimes an upgrade; doing badly just means no prize.

- **Set pieces** (red signs): one per floor, each at most once a run, dealt at random.
- **Machine-gun nest**: a sandbagged parapet over no man's land at dusk, with wire, craters, burning wrecks, flares and fog. Man the Maxim ([E] at the gun) and hold for 90 seconds while three waves of clowns and WitzSoldats come out of the fog (shamblers, runners, riflemen working forward crater to crater). The gun overheats if you hold the trigger too long; steam pours off it and it stops until it cools. Anything that gets into the trench drops in at either end: then [E] lets go of the gun so you can fight them off with your own weapons, and [E] at the gun again to get back on. When the time is up nothing else comes; the nest ends when the field is clear or 12 seconds later. Bronze 16 kills (5 tickets, 30 health), silver 26 (10, 60, an upgrade), gold 36 (15, full health, an upgrade), and 5 more tickets if nothing reached the trench. Survive it and you can rip the gun off its mount: key 5, 250 rounds on the belt, no reload, slows you down, and it takes people apart.
- **The Shooting Gallery**: a fairground booth with a counter, bulbs, three rows of painted cover and a sunburst backdrop. Plywood clowns and soldiers flip up and drop again, faster and faster, for 45 seconds: 1 point a hit, 2 in the head. Three real WitzSoldats crouch behind the back row and pop up to shoot at you (5 points each). The little girl with the balloon is -5. Bronze 30 (4 tickets, 25 health), silver 55 (8, 50, an upgrade), gold 80 (12, full health, an upgrade).
- **The Card Game**: a low room, one bulb swinging over a table, a gramophone in the corner. Clowns and WitzSoldats sit round a hand of cards and have not looked up. Shoot first and they die in their chairs; give them three and a half seconds, or hit any of them, and the table goes over: the riflemen get down behind it and shoot, the clowns come for you. Prize: the pot (8 tickets, 4 more if you got them before they could stand), 25 health and an upgrade.
- **The High Wire**: a circus shaft 26m tall. You stand on an iron-grating pulpit 19m up, with a scoped bolt-action rifle on the rail ([E] to take it, right mouse for the scope, left to fire; one round then the bolt). Ten clowns walk two tightropes across the shaft, three at a time, each under its own followspot; now and then one stops to steady itself. Below the wires the shaft is full of old rigging (beams, struts, a trapeze, sandbags on ropes) that the bodies hit on the way down. Headshot 3 points, body 1, each beam a body bounces off +1 (up to 3 per body), -1 for any that make it across. Bronze 10 (5 tickets, 25 health), silver 20 (9, 50, an upgrade), gold 30 (14, full health, an upgrade).
- **The Grand Staircase**: one long flight of forty marble steps down to a ruined theatre foyer, under a chandelier. You start at the top. Clowns come up from the foyer in little conga lines, slowly. Anything shot on the stairs goes over backwards and rolls all the way down, and a body (or barrel, or chandelier) coming down the stairs knocks flat any clown it runs into. Shoot the rope on the barrel rack at the top to send four barrels down the flight; shoot the chandelier's chain to drop it on them. Two fuel drums wait at the bottom. 5 tickets, +1 for every clown knocked flat by something falling (up to 10), +1 for every body that goes all the way down, 25 health, an upgrade for 4 or more knock-downs.
- **The Meat Locker**: a cold store full of clowns hanging from hooks, swinging when you shoot them or push through. Four of them are not dead, and drop off when you get close.

## Stake gun

Key 4. A compressed-air launcher that fires one iron-tipped stake. It goes straight through any clown (always a kill), carries the body with it and nails it to the next wall, where it hangs; with no wall within about 9 m the stake stays in the body and it drops. Reloading is slow (2.9 s: fetch a stake, lay it on the rail, three strokes of the pump while the gauge climbs) and starts by itself after each shot. A stake into a fuel drum sets it off.

## Bolt-action rifle

Key 6. A WW1 service rifle: five rounds, one shot per pull of the bolt (you see the right hand go up to it after every shot, about a second), reloaded from a stripper clip thumbed into the open breech (2.5 s). Each round is 180 damage and carries on through: it comes out the back of the first body with a spray of blood and goes into whoever is behind, up to four more, losing 15% each time. Line them up in a corridor. Tuning: `pierce` and `damage` in the Rifle entry of `WEAPONS` in `fps_player.gd`.

## Point-blank shotgun

Inside 3 m, a shotgun blast that puts most of its charge into the chest or belly (95 damage or more on that part) goes straight through and leaves a ragged hole you can see daylight through, front to back. What was inside in the way goes with it (the ribs and guts show round the rim), and it all comes out the back in a spray of blood and meat. Tuning: `punch_range`, `punch_damage` and `punch_radius` on the clown. The hole is a tunnel along the shot drawn by the body shader (`tunnels` in `clown_body.gdshader`), up to four per body.

## Broken legs

A round in the knee (28 damage or more, within 17 cm of the joint), or enough rounds in one leg, breaks it. A living clown or WitzSoldat drops, writhes on the floor clutching the knee for a few seconds, gets up on one knee and then stands, and comes after you limping: slow, no running, the knee bent the wrong way and the body lurching down onto it every step. Shoot it again and it dies with that knee flopping wrong.

The shotgun and explosions now usually break legs instead of taking them off: a blast that would sever a leg breaks it three times in four (`leg_off_chance` on the clown, 0.25), and a living clown it does not kill goes down the same way.

## Rounds add up

Pistol and SMG rounds wear a body down. Enough of them into one part, alive or dead, tears it open in stages: the head cracks open, then more of the skull goes, then most of it; the chest opens to the ribs, then wider; the belly opens and the guts come out, then more. The thresholds are `WEAR_STAGES` in `clown.gd` (damage soaked up, and hole size, per stage). The shotgun still does it all in one blast.

## WitzSoldat

Carries the rifle at low ready: butt by the right hip, muzzle forward and a little down across the body, right hand on the wrist and left under the fore-end, both elbows easy. It swings a little with each stride and comes up when running. Shoulders it to aim: butt in the shoulder, cheek down on the stock, sights to the eye, right elbow out; both hands placed by a two-bone reach every frame. Up close it drives the bayonet forward from the hip. It runs upright (a soldier's run, not a crouched sprint). When it dies its hands come off the rifle: the dying arm muscles pull toward arms hanging free (and are flung wide), not the grip it died in. Lining up a shot in the open it side-steps slowly and smoothly, pausing now and then.

Everyone's walk (clowns too): the stepping knee folds up to about 60 degrees as the foot comes through, the planted knee gives a little under the weight and never locks, the foot pushes off with the toe and comes down heel first, and hips and shoulders counter-turn. Any real movement gets a full step (slow walking takes shorter steps, not smaller leg movements), so a slow side-step still lifts its feet, and side-steps swing the legs out sideways.

It fights from cover: after a shot in the open it looks within two corridor cells for a spot the player cannot see a crouched head at, with a firing spot a step away. It runs there, crouches (working the bolt), steps out, aims, fires once and ducks back. It gives the cover up if the player gets within 4 m or can see the hiding place.

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
| `scripts/events/` | Event doors, the event manager, the rooms (machine-gun nest, high wire, clown car, meat locker), the mounted gun, and the simple AI used in them |
| `scripts/weapons/stake.gd` | The stake in flight: skewering, carrying the body, pinning it to a wall |
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
- **Weapons:** `WEAPONS` at the top of `fps_player.gd` (damage, spread, rate as `cooldown`, magazine). The SMG: 21 damage, about 600 rounds a minute, 32-round magazine, 1.9 s reload (`SMG_RELOAD` in `view_model.gd`).
- **Stake gun:** `SPEED`, `CARRY_SPEED`, `MAX_CARRY` in `stake.gd`; reload timing `STAKE_RELOAD` / `STAKE_SEAT` in `view_model.gd`.
- **Legs and cover:** `knee_damage`, `KNEE_RADIUS`, `leg_off_chance` and the get-up timing (`GETUP_KNEEL`, `GETUP_STAND`) in `clown.gd`; how slow a limper is in `limp()` in `clown_brain.gd`; cover search and timings in `_find_cover()` and `_cover_fight()` there.
- **Events:** which rooms exist and how they are dealt out in `event_manager.gd` (`FEATURES`, `ODDITIES`); doors per floor `MAX_EVENT_DOORS` in `level_art.gd`; the nest's waves, time and prize tiers at the top of `mg_nest.gd`; the gun's heat in `mounted_gun.gd`; the Maxim's numbers in `WEAPONS` / `MOUNTED_MG` in `fps_player.gd`.
- **Explosions:** `RADIUS` and `PLAYER_DAMAGE` in `scripts/fx/explosion.gd`; `toughness` on the drum (`explosive_barrel.gd`); how hard and how messily clowns are thrown in `caught_in_blast()` and `_blast_gore()` in `clown.gd`; `crawl_chance` on the clown for being torn in half; `life` and `speed` in `clown_crawler.gd`; how many drums per floor in `_dress_bunker()` in `level_art.gd`.
- **Blood budget:** `MAX_DECALS`, `MAX_POOLS`, `DRY_TIME` in `blood_manager.gd`.

## Checks

These run without opening the editor:

```
godot --headless --fixed-fps 60 res://scenes/test_joints.tscn   # every joint driven to both ends of every axis
godot --headless --fixed-fps 60 res://scenes/test_death.tscn    # timeline of each death reaction
godot --headless --fixed-fps 60 res://scenes/test_game.tscn     # 40 mazes checked, then one pass round the game loop
godot --headless --fixed-fps 60 res://scenes/test_events.tscn   # a bot plays every event room (add -- --only=mg_nest to pick one)
godot --headless --fixed-fps 60 res://scenes/test_legs.tscn     # knee shot: down, writhe, up, limp; shotgun to the shins
godot --headless --fixed-fps 60 res://scenes/test_cover.tscn    # a WitzSoldat in a level taking cover and peeking out
godot --headless --fixed-fps 60 res://scenes/test_stake.tscn    # a clown staked to the wall; pistol rounds wearing a head and a chest open
godot --headless --fixed-fps 60 res://scenes/test_smg.tscn      # SMG rate of fire, kill, reload; god mode
godot --headless --fixed-fps 60 res://scenes/test_blast.tscn    # a drum among clowns at set distances: gore, throw, the crawler
godot --headless --fixed-fps 60 res://scenes/test_rifle.tscn    # one rifle round through four clowns in a line; bolt; reload (--render for images)
godot --headless --fixed-fps 60 res://scenes/test_stairs_walk.tscn  # walks the player down the Grand Staircase and back up, five lanes
godot --path . res://scenes/test_punch.tscn                    # point-blank shotgun hole: renders /tmp/punch_*.png (needs a window)
godot --path . res://scenes/test_soldier_pose.tscn             # WitzSoldat stand/walk/run/aim/thrust from the side, /tmp/pose_*.png (needs a window)
godot --path . res://scenes/test_soldier_anim.tscn             # WitzSoldat walk cycle, side-step, carry/aim front and 3/4, three deaths; /tmp/sa_*.png and joint angles
godot --path . res://scenes/render_level.tscn                  # saves views of a level to /tmp/lvl_*.png (needs a window)
```
