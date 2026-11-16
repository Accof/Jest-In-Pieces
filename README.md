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
| Enter | Continue from the title screen, or leave the death screen for the base |
| 1 / 2 / 3 | Pick an upgrade; in the Quartermaster's booth, 1-5 buy perks |
| Esc | In the base: back to the title screen |
| Esc | Free the mouse |

## The game

- Each floor is one winding route: a short stretch of open trench, then down into a dieselpunk concrete bunker. Corridors run straight for a few cells at a time, framed by concrete pillars and steel beams, lit by caged bulbs, with wet floors, pipes and steel doors. There are a couple of stairwells down, a few wider halls (dormitory, mess, stores) and dead-end side rooms. A little of the circus survives: faded harlequin paint, a stencilled star, a clown's face over the way in, an old drum in the mess.
- Kill every clown, then find the door (it turns green) to leave.
- After each floor you pick one of three upgrades. Floors get bigger, with more clowns and more gunmen.
- Kills earn tickets (two for a headshot). When you die they are banked, and you come round in the base.
- Now and then a dead-end side room has a table in it with two or three of them sat round it playing cards under a lamp (one table on early floors, sometimes two later). They do not look up until they hear a shot, see you within about 5 m, or one of them is hit, and then each takes a moment to push its chair back and get up. Shot in the chair, a body slumps forward across the table.

## Title screen

Continue (to the base), New Game, Quit. New Game asks first, then wipes everything: tickets, perks, trophies, every stat, the fortune and the armoury choice. The automated tests use their own save file (`clown_save_test.json`) so they never touch yours.

## The base

A forward command bunker the circus moved into: concrete, sandbags, crates, a field telephone, bunting and strings of fairground bulbs, a carousel horse's head on a brass pole, a gramophone, an army cot where you come round after each death. Walk about and press [E]:

- **Quartermaster** (west wall): a striped ticket booth with a clown behind the counter. Spend tickets on permanent perks: Thick Skin (+10 starting health, x5), Hair Trigger (+5% fire rate, x5), Head Start (a random upgrade at the start of each run), Deep Pockets (+20% tickets from a run, x3), Field Dressing (heal 15 at the start of every floor, x2).
- **Chalkboard** (east wall): lifetime tallies. Total kills, clowns, WitzSoldats, headshots, blown up, staked to the wall, limbs taken off, skulls opened, shot clean through, knees broken, torn in half, killed at the table, knocked down the stairs, most in one rifle round, runs, floors cleared, deepest floor, steel doors opened, gold medals, tickets earned.
- **Trophy wall** (south wall): sixteen plaques that fill as you hit milestones, each with its own trophy (a clown's nose, cups, a skull, a gas mask, a stake, a bowling pin, medals...). Locked ones show a "?" and how far along you are. Each new trophy pays 10 tickets.
- **Madame Bonzo** (south-east corner): a clown automaton in a glass cabinet. 5 tickets for a card that changes your next run: a free upgrade, +50 health, a 25-ticket jackpot, or nothing at all. One card per run.
- **Armoury** (north wall): the guns on a rack with how many each has killed. [E] on one to start every run holding it.
- **Map table**: a painted map with pins, and a board with your last six runs.
- **The steel door** (north wall, TO THE FRONT): start a run.

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

Its legs follow real gait curves (clinical walking averages, a little exaggerated for a man marching with a load, blending into running curves): the thigh comes well forward through the swing, about 30 degrees at its highest, which is what lifts the knee, and only goes about 12 degrees behind at push-off; the knee gives under the weight at heel strike, straightens through mid-stance and bends most (about 63 degrees) just after the foot leaves the ground; the ankle rocks the foot over and pushes off with the toe. Taking aim it stands bladed like a rifleman: hips turned a third of the way round, left foot forward toward you, right foot back and turned out, knees soft, leaning into the rifle, shoulders brought back round onto the target.

Firing: it fires only from the shoulder with its eye to the sights. The shot kicks: the rifle drives back into the shoulder and the muzzle flips up, chest and head knocked back. The flash is a burst of flame out of the barrel (three crossed tongues along the shot and a star seen end on), a hard flash of light over the corridor and a puff of smoke, with the report (`art/witzsoldat/sfx`, synthesised placeholders like the rest). Then it works the bolt before it can fire again (`bolt_seconds`, 1.05 s): rifle down a little off the cheek, right hand off the wrist to the bolt, handle up, back (the empty case spins out to the right and tinkles on the floor), forward, down, hand back, and up onto the sights again.

It never runs backwards. Running for cover (or anywhere) it turns toward where it is going first and only puts on speed once it faces that way. If you get too close it either runs for cover (if there is some) or lowers the rifle to low ready and takes a few short, careful steps back (the legs play the walk in reverse with a short reach: the foot picked up with the knee and put down toe first), then stops, brings the rifle up and shoots. Ducking the step back into cover after a shot, it keeps its eyes on you and steps back at a walk.

One WitzSoldat in four (`club_share` on the game node) leaves the rifle behind and carries a spiked trench club: a hardwood haft swelling to a head with two iron bands and four rings of rusty square spikes, and a leather wrist loop. It never aims, just closes in and swings it overhead (20 damage, 1.6 m reach, a heavier, slower swing than a bare-handed clown's). The club drops from its hand when it dies.

It fights from cover: after a shot in the open it looks within two corridor cells for a spot the player cannot see a crouched head at, with a firing spot a step away. It runs there, crouches (working the bolt), steps out, aims, fires once and ducks back. It gives the cover up if the player gets within 4 m or can see the hiding place.

## Der Klappersoldat

A WW1 German infantryman built out of clockwork by a deranged carnival engineer: dark uniform, Stahlhelm, a cracked porcelain clown face with a fixed grin, a red nose and burning amber eyes (bright enough to bloom, with a soft glow round each, so they read in the dark from the far end of a corridor; `eye_glow`, `eye_halo_size`, `eye_light_energy`), a red ruff, a brass wind-up key, and brass joints at the elbows and knees. It turns up from floor 2 (10% of a floor's enemies, 2% more each floor, at most 20%; `klapper_base`, `klapper_per_floor`, `klapper_max` on the game node).

It is slow (0.45 of a soldier's walking speed, never runs, never lunges), very tough (4x an ordinary enemy's health: about 13 pistol rounds to the body or 4 to the head; blowing part of its skull open does not kill it outright) and hits harder (1.25x) with one slow, telegraphed blow: the arm is cranked up overhead in three ratchet clicks, held cocked, brought down in one abrupt strike about a second in, then cranked slowly back. A strong hit (20+) staggers it one time in five; everything else only jolts it and it keeps coming. Every setting is an export on `Klappersoldat` (`scripts/clown/klappersoldat.gd`).

How it moves: it only ever faces, and walks, north, south, east or west. A new direction means it stops and turns on the spot in 45-degree clicks, shuffling its feet round with each, and then walks on; it sticks to one axis (sidestepping a little to stay on line) until the way it wants to go is mostly across it, and takes the other axis if it finds itself pushing into a corner. When it notices you (it sees a long way round to the side, so it catches you as it crosses a junction in front of you) it stops dead, its head comes round to you in jerks, further than a man's could, and stares; then the body ratchets round beneath the motionless head in slow 30-degree clicks, and only then does it come for you. It walks with the same fully jointed walk as everyone else (knees fold, feet lift and plant heel first, ankles push off, hips and shoulders counter-turn), driven by a clockwork clock rather than by distance: each step catches with both feet planted, drives through with a short spin-up and brake, overshoots a hair and settles; steps vary in length; the body surges and stops with the legs so the planted foot stays put. Every few seconds the escapement jams for 0.1-0.3 s with a grind of gears and a corrective jerk of a shoulder or the head. The head holds unnaturally still, then snaps toward things in stages, sometimes at a tilt. The arms swing a beat behind the legs with the elbows always bent. Idle, it stands almost perfectly still, ticking, broken now and then by a head tilt, a shoulder jerking, fingers clenching, a snap of the head, or the eyes guttering.

Shot, it throws real-looking sparks (white-hot streaks drawn along their flight, falling, bouncing off the floor and cooling through orange to red), pings like metal, drips machine oil (never blood), and its eyes sometimes flicker. The existing gore runs in a mechanical mode: wear on the chest or belly first shows a riveted inner panel, then rips it away to show brass gears (turning while it lives), a mainspring, pistons, a steel housing where the ribs would be, and wiring. Limbs come off as oily clockwork gibs (steel stump faces round a brass core) with a burst of sparks and oil, leaving a snapped rod and torn wires at the stump. A broken knee shows a snapped steel rod and torn wiring. Debris is gears, springs, sheet metal and porcelain shards.

How it dies (it is metal, not flesh):
- **Through the head:** the head jolts back, then drops forward and to one side on a broken neck and hangs there. It stays on its feet for 1-2 s, arms and shoulders jerking as it shorts out, blue arcs crackling from its wounds, then topples over backwards like a felled post onto its back (or against a wall) with a heavy thud, the head knocking off the floor in a small bounce.
- **Anywhere else (body, limb):** one of three, picked at random each time (`body_death_odds`; not on how much damage it took):
  - **Shorting out** (45%): the hit punches the chest back, the head jerks then lolls forward, and it stands 1-2 s jerking and arcing like a head kill, rocking toward the way it will go; then it goes over stiff as a post backwards, forwards, or to the left or right (the head bounces when it lands on its back).
  - **Full malfunction** (30%): a full-body seizure, the arms, spine and head wrenched to new wrong angles in hard jerks (the feet stay planted), elbows bent backwards, the head spinning right round and then cocked over looking back; a dead stop; then it drops in a heap.
  - **Collapse** (25%): the power goes out of every joint at once and it crumples where it stands.
- Blasts and the stake throw it like anything else.

Every death: a burst of sparks and a spray of oil, its works winding down and its eyes fading, and for a minute a thin wisp of smoke rising from each of its last few wounds (riding on the body as it falls) with now and then a blue arc or a spit of sparks, fewer as the minute goes on. Where it comes to rest it leaves an oil puddle. Oil puddles are permanent: no lifetime, no cap, never faded out, not attached to the body; they outlast the corpse and only go when the floor is torn down (`Blood.clear()`).

The body is a Tripo model (`art/klappersoldat/source/`), built for the game by `tools/build_klappersoldat.py` (run with Blender's Python): scaled to 1.91 m, welded and decimated to 23k triangles, rigged to the shared 21-bone skeleton (the WitzSoldat rig's names and rolls, moved to this model's joints), cut cleanly into the 15 gore segments at the neck, shoulders, elbows, wrists, crotch, knees and ankles with a stump cap fitted to each cut, rest positions and segment ids baked in, gibs for every segment, and the eye positions found from the texture. The helmet is part of the head, so it never pops off. Only the glowing eyes are added in code. Shots to the face chip the porcelain; enough on one side blows that side open to the iron skull and its works, and that eye goes out. The sounds (`art/klapper/sfx/`) are synthesised placeholders (`tools/gen_klapper_sfx.py`): ticks, a ratchet wind-up, gear grinding, squeaks, iron footsteps, bell-metal clangs, bullet pings, crackle, an electric zap, a heavy thud, a spring running down.

## Final-kill camera

Kill the last enemy on a floor (or the last one in an event room) and the view leaves your eyes for a few seconds, RDR-style: a cinematic camera (a little narrower, letterboxed) picked for how and where it died, time slowing smoothly to a quarter speed, the body doing whatever the physics does with it, time easing back, a beat at full speed on the corpse, then back to your eyes. Ordinary kills never trigger it; it runs once per floor or room, even if the last two die in the same blast. While it runs you cannot move, look or shoot (the gun and crosshair are put away), and nothing about you is changed: position, view, weapon, ammo.

**Choosing the shot** (`scripts/fx/kill_cam.gd`): when it starts it takes the middle of the body (between chest and hips), the floor and ceiling there, which way the fatal shot pushed it (else away from you), its facing and where you are, and scores candidate cameras. Each kind of shot has an ideal bearing round the body and every bearing is tried, pulled in if it does not fit: **low side** (just above the floor, side-on to the way it falls), **three-quarter**, **elevated** (looking down, where the ceiling allows), **ground** (a few centimetres off the floor, favoured for a Klappersoldat), **rear** (behind it, looking past it the way it will go), **over the shoulder** (for a kill close up, or a corridor too tight for anything else) and **tracking** (riding alongside a body going off a ledge or down a long drop). A candidate is thrown out if the camera would be inside the level, the body cannot be seen, or too little of the body and the floor it will land on is in view; the rest score for how much they can see, how side-on they are to the fall, room round the camera, how close they are to that kind's ideal bearing, and that kind's suitability (elevated and tracking for falls, over the shoulder up close), plus a little randomness, minus a penalty for the last few shots used (kept across floors, so finales vary). Nothing fits: it stays in first person and just slows time.

**Running it**: most shots are stationary: the camera stays put and turns gently to keep the body in frame, so the body falls through the shot; a tracking shot follows the body smoothly, kept out of walls. It flies in from your eyes in 0.35 s (or cuts through black if there is a wall between), and back the same way. It watches the ragdoll the game already made and never touches it. It stays on while the body is still moving fast or a Klappersoldat is still on its feet in its death, up to a hard limit.

**Time and sound**: real time drives it. 0.2 s easing from full speed to 25%, held 1 s, eased back over 0.8 s, 1 s at full speed, 0.4 s back to you (about 3.4 s in all). While time is slow the sound is muffled (a low-pass on the master bus) and a little lower in pitch, both back to normal with the speed.

**Safety**: if the body is freed it goes straight back to you; if you die, the game pauses, the floor changes or it runs past the limit, it stops at once. Every way out puts the time scale, sound, camera, HUD and controls back.

Settings (exports on `KillCam`, the game's `KillCam` node): `enabled`, `min_time_scale` 0.25, `impact_seconds` 0.2, `slow_seconds` 1.0, `recover_seconds` 0.8, `focus_seconds` 1.0, `return_seconds` 0.4, `max_seconds` 5.0, `fly_in_seconds` 0.35, `dynamic_angles`, `stationary_shots`, `tracking_shots`, `avoid_repeats`, `follow_falls`, `collision_checks`, `audio_muffle`, `letterbox`, `fov` 60, `distance` 2.9, `height` 1.35, `aim_smoothing` 3.0, `track_smoothing` 2.6, `fall_drop` 1.2.

## Joker lockers

On about 60% of bunker floors a bank of three tall, thin WW1 steel lockers stands against the wall of a long straight corridor (away from the pipes, never near the start). They are olive drab, chipped through to primer and bare steel and streaked with rust, with pressed louvres top and bottom, a latch handle and a stencilled number. One has a little joker playing card nailed to its door. While you are within 7 m, every few seconds something in that one may laugh (a cackle, a giggle or a slow wheezing laugh, muffled by the steel) and the door jumps on its latch.

Every locker door takes bullets (a bright nick and a dent you hear), but only the joker's opens: each round through it spits blood back out of the hole, and after about 90 damage (three pistol rounds) the latch gives, the door slams back on its hinges, and a dead clown pitches out face first onto the floor. Its bullet holes are where your rounds went through the door, plus older ones: it has been shot before. It has been in there a long time: its greasepaint soured to a grey-green pallor, black mould blooming through the costume, a brown tide-mark up the legs, the blood on it gone brown. It is not one of the troupe: it wears a court jester's three-pointed cap (faded plum and mustard, bells gone green) and died with a joker card clenched in its teeth. The rest of its deck comes fluttering out after it. Finding it is worth 8 tickets ("LOCKER JOKER!"; it is not a kill and does not count toward the floor's clowns).

`scripts/world/joker_locker.gd` (the bank, the laugh, the door), `scripts/clown/locker_joker.gd` (the clown's look, its fall, the cards). The card and paint textures and the sounds (`art/locker/`) are placeholders made by `tools/gen_locker_assets.py`.

## Fuel drums

Red fuel drums stand in corners of the bunkers and halls (more on bigger floors), never inside a crate, a wall piece or a mess-table chair: once a floor is dressed, any drum that ended up inside something slides toward the middle of its cell until it stands clear, or is taken away. Shoot one and it goes up: a hard hit sets it off at once, a lighter one punches a hole that spits flame for a second first. Drums near a blast go up too.

How badly a clown comes apart depends on how close it was (and whether anything stood between it and the drum):

- **Right next to it:** thrown across the room or into the walls, two or three limbs torn off, belly and ribs blown open, often part of the skull gone. Every part that hits a wall at speed bursts blood across it.
- **A couple of metres:** guts out, ribs showing, maybe a piece of skull and a limb, flung a few metres.
- **Further:** peppered with wounds and knocked down, or knocked about and very angry.
- **Torn in half (40% of clowns caught at 1-3 m):** the legs go flying one way and the torso the other. Half of them are dead outright. The other half live: the torso drags itself away from you on its hands, guts trailing, smearing a blood trail and stopping to gasp in its own pool. It bleeds out after a minute, or you can finish it.

The blast hurts you too (up to 85 at point blank, much less behind cover) and shakes the view. In the gore sandbox there are three drums among the clowns.

## Enemies

| Enemy | Body | How it fights |
|---|---|---|
| Clown | `art/clown/` | Melee, or a pistol (gunmen strafe and keep their distance) |
| WitzSoldat | `art/witzsoldat/` | Bolt-action rifle: slower to aim and reload, 24 damage a hit, reaches 24 m. Helmet comes off on half of headshots, always on a shotgun blast to the head |
| Klappersoldat | `art/klappersoldat/` | Clockwork. Slow heavy melee blow, 4x health, never runs, walks and turns only in right angles; oil, sparks and gears instead of blood and guts; three scripted mechanical deaths |

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
| `scripts/clown/klappersoldat.gd` | Der Klappersoldat: dressing, clockwork gait, head, blow, staggers, face damage, death, oil puddle |
| `scripts/clown/clockwork.gd` | Gears, springs, rods, wires, shards and their materials |
| `scripts/fx/mech_fx.gd` | Pooled sparks and the clockwork sounds |
| `tools/build_klappersoldat.py` | Builds the Klappersoldat's rigged body, gibs and spec from the Tripo model (Blender Python) |
| `tools/gen_klapper_sfx.py`, `tools/gen_oil_textures.py` | Regenerate the Klappersoldat's sounds and the oil splats |
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
- **Explosions:** `RADIUS` and `PLAYER_DAMAGE` in `scripts/fx/explosion.gd`; `toughness` on the drum (`explosive_barrel.gd`); how hard and how messily clowns are thrown in `caught_in_blast()` and `_blast_gore()` in `clown.gd`; `halve_chance` on the clown for being torn in half and `crawl_share` for how many of those live and crawl; `life` and `speed` in `clown_crawler.gd`; how many drums per floor in `_dress_bunker()` in `level_art.gd`.
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
godot --headless --fixed-fps 60 res://scenes/test_nav.tscn     # a crowd chasing the player round three floors with stairs: counts frames inside walls, sunk, beside a stair, stuck, inside another clown
godot --headless --fixed-fps 60 res://scenes/test_klapper.tscn     # Klappersoldat: speed, square-to-the-maze walking, knees/ankles/elbows, foot slide, head snaps, noticing you (head, then body, then it moves), the blow, staggers, mechanical gore, the deaths (head; random body deaths: shorting out and toppling all four ways, collapse, malfunction; how often each comes up), smoke, oil puddle, ordinary clowns unchanged (sections: walk notice fight gore deaths crowd; add "render" for pictures, "film render" for the walk)
godot --headless res://scenes/test_drum_clear.tscn          # twelve floors: counts fuel drums standing inside anything solid (should be 0)
godot res://scenes/test_seethrough.tscn -- 3 [full]          # needs a window: paints every pixel with its distance and checks it against physics rays from every cell; drawn further than the wall = a hole you can see through
godot --headless --fixed-fps 60 res://scenes/test_wander.tscn  # unaware clowns wandering and searching: how often a step runs into a wall or doorway pillar
godot --headless --fixed-fps 60 res://scenes/test_base.tscn    # title -> base -> every station -> a run with a table -> death -> base -> new game (--render for /tmp/base_*.png)
godot --path . res://scenes/test_soldier_anim.tscn             # WitzSoldat walk cycle, side-step, carry/aim front and 3/4, the club carrier walking and swinging, three deaths; /tmp/sa_*.png and joint angles
godot --headless --fixed-fps 60 res://scenes/test_locker.tscn  # joker lockers: laughs near, silent far; plain doors stay shut; the joker's door bursts at ~90 damage; the clown falls out riddled, face down in front, cards spilled; 40 floors placed flush to a wall (sections: open levels; add "render" for /tmp/locker_*.png)
godot --headless --fixed-fps 60 res://scenes/test_killcam.tscn  # final-kill camera: ordinary kills leave it alone, the last kill runs it once, time curve, never inside the level, body in view, player untouched and restored; shots chosen over 12 floors; two at once; interrupted (player dies, body freed, floor changes, pause); a Klappersoldat; a fall off a platform; an event room (sections: floor variety double interrupt klapper fall event; add "render")
godot --path . res://scenes/render_level.tscn                  # saves views of a level to /tmp/lvl_*.png (needs a window)
```
