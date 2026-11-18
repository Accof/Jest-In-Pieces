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
| 7 | Revolver |
| G | God mode on/off (take no damage; for testing, stays on across runs until you turn it off or quit the game) |
| F | Flashlight |
| Q | Carnival Curse, once charged (10 kills) |
| Enter | Continue from the title screen, or leave the death screen for the base |
| 1 / 2 / 3 | Pick an upgrade; in the Quartermaster's booth, 1-5 buy perks |
| Esc | In the base: back to the title screen |
| Esc | Free the mouse |

## The game

- Each floor is one winding route: a short stretch of open trench, then down into a dieselpunk concrete bunker. Corridors run straight for a few cells at a time, framed by concrete pillars and steel beams, lit by caged bulbs, with wet floors, pipes and steel doors. There are a couple of stairwells down, a few wider halls (dormitory, mess, stores) and dead-end side rooms. A little of the circus survives: faded harlequin paint, a stencilled star, a clown's face over the way in, an old drum in the mess.
- Every third floor (3, 6, 9...) is outdoors instead: the Drowned Trenches (below).
- Kill every clown, then find the door (it turns green) to leave.
- After each floor you pick one of three upgrades. Floors get bigger, with more clowns and more gunmen.
- Kills earn tickets (two for a headshot). When you die they are banked, and you come round in the base.
- Now and then a dead-end side room has a table in it with two or three of them sat round it playing cards under a lamp (one table on early floors, sometimes two later). They do not look up until they hear a shot, see you within about 5 m, or one of them is hit, and then each takes a moment to push its chair back and get up. Shot in the chair, a body slumps forward across the table.

## Title screen

Continue (to the base), New Game, Quit. New Game asks first, then wipes everything: tickets, perks, trophies, every stat, the fortune and the armoury choice. The automated tests use their own save file (`clown_save_test.json`) so they never touch yours.

## Title screen art

The title screen fades slowly between two splash paintings (`art/ui/menu/`: the Klappersoldat peering round a bunker corner; a clown mask in the trench mud with the burning fair beyond), each pushing in a little while it is up (`hold_seconds` 7, `fade_seconds` 2.5, `drift_zoom` on `MainMenu`, `scripts/ui/main_menu.gd`), darkened on the left under the menu and round the edges. The title and menu are in German blackletter in fairground colours: "Jest in Pieces" in UnifrakturMaguntia, cream with a circus-red outline; "Ein Karneval des Grauens · 1916" in gold; the buttons in UnifrakturCook, alternating red with cream lettering and cream with red like the bunting, edged in gold, turning gold under the mouse or keyboard; the small print in Grenze Gotisch. The fonts are SIL Open Font License (`art/ui/fonts/`, licences alongside). `scenes/look_menu.tscn` films it (needs a window).

## The base

A forward command bunker the circus moved into: concrete, sandbags, crates, a field telephone, bunting and strings of fairground bulbs, a carousel horse's head on a brass pole, a gramophone, an army cot where you come round after each death. Walk about and press [E]:

- **Quartermaster** (west wall): a striped ticket booth with a clown behind the counter. Spend tickets on permanent perks: Thick Skin (+10 starting health, x5), Hair Trigger (+5% fire rate, x5), Head Start (a random upgrade at the start of each run), Deep Pockets (+20% tickets from a run, x3), Field Dressing (heal 15 at the start of every floor, x2).
- **Chalkboard** (east wall): lifetime tallies. Total kills, clowns, WitzSoldats, headshots, blown up, staked to the wall, limbs taken off, skulls opened, shot clean through, knees broken, torn in half, killed at the table, knocked down the stairs, most in one rifle round, runs, floors cleared, deepest floor, steel doors opened, gold medals, tickets earned.
- **Trophy wall** (south wall): sixteen plaques that fill as you hit milestones, each with its own trophy (a clown's nose, cups, a skull, a gas mask, a stake, a bowling pin, medals...). Locked ones show a "?" and how far along you are. Each new trophy pays 10 tickets.
- **Madame Bonzo** (south-east corner): a clown automaton in a glass cabinet. 5 tickets for a card that changes your next run: a free upgrade, +50 health, a 25-ticket jackpot, or nothing at all. One card per run.
- **Armoury** (north wall): the guns on a rack with how many each has killed. [E] on one to start every run holding it.
- **Map table**: a painted map with pins, and a board with your last six runs.
- **The steel door** (north wall, TO THE FRONT): start a run.

## The Drowned Trenches

Every third floor (`trench_every` on the game, 3) is a Western Front trench system in daylight the morning after heavy rain. It is a new layout every time, about 270 m of trench in a 48 x 42 m area, cut into open ground that runs out to the horizon.

**Layout** (`scripts/world/trench_maze.gd`, `TrenchMaze`, on a 1.5 m grid, the width of a trench):
- **Fire trench** facing No Man's Land: bays and traverses, a fire step under the front wall of every bay (step up onto it to see out over the parapet), sandbags on the parapet with a loophole here and there, and a parados behind.
- **Support line**, sinuous, about 12 m back, and a partial **reserve line** behind that.
- **Communication trenches**: zigzags between the lines, three to the front and two to the reserve, making loops. One runs back to the rear edge, which is where you come in.
- **Saps**: zigzags out from the fire trench to an **observation post** with a periscope.
- **Side features**:
  - dead-end firing positions;
  - dugouts (a timber entrance, a roof of beams, iron and sandbags, a lantern burning inside);
  - a flooded side trench;
  - a ruined field gun in its pit.
- **Landmarks**: a shattered tree at one junction, a flooded junction at another, and a stretch where the wall has slumped in (still passable).
- **Exit**: the H.Q. bunker, a concrete portal at the far end of the fire trench.

**Ground:**
- One carved heightfield (0.2 m) is both the mesh and the collision (`HeightMapShape3D`).
- The trench floors are uneven, with ruts, sumps and mud heaped at the foot of the walls.
- Walls lean back by their lining. Bare earth walls slump and bulge.
- Linings: timber boards on posts, corrugated iron on pickets, sandbags, woven hurdles, or boards that have come away. Most stop short of the top. Each has a thin collision box so bodies hit the lining.
- **Duckboards** run down the middle of the trenches. Some slats are missing or tilted, and the boards are sunk in the flooded stretches. You walk on them: the walked surface is raised under them.
- Bodies, blood pools, gibs, the Carnival Curse and the killcam all work on it.

**The trench floor** is a scanned mud: Poly Haven's brown_mud_03 (CC0, `art/trench/polyhaven/`).
- Maps: albedo, an OpenGL normal map, and ambient occlusion, roughness and height packed into one texture.
- 2.4 m per tile, so the boot prints come out boot-sized.
- Parallax occlusion from the height map gives the ruts and boot holes real depth up close (fading out by 14 m).
- Darkened, warmer and more saturated than the scan, so it reads as soaked Flanders mud.
- The low parts are darker, with a film of water on them (a wet sheen, not a mirror); the crests and crumbs stay rough.
- Water stands in the deepest hollows in patches.

**Scanned materials** (Poly Haven, CC0, `art/trench/pbr/`; each set is albedo, an OpenGL normal map, and AO/roughness/height packed into one texture):
- **Walls and exposed earth:** brown_mud.
  - On the walls it's projected along X or Z by which way the wall faces, 2.5 m per tile, two samples blended by noise so long walls don't repeat. Darker and wetter at the foot.
  - It's also the thrown-up earth up top near the trenches. Further off is the old procedural firmer ground.
- **Rocks:** rocks_ground_08, 2 m per tile. It shows on the eroded rim where a wall breaks over, in the slumped stretch, where linings have come away, in patches of ground, and at the foot of bare walls. It's blended by its height map so stones stand out of the mud.
- **Wood:** rough_wood (`shaders/pbr_object.gdshader`), 1 m per tile. Used for linings, posts, duckboards, fire steps, dugout beams, crates and signs. The grain runs along each piece's longest side, and every board and slat uses its own part of the texture.
- **Sandbags:** hessian_230, 0.45 m per tile. Muddied and wet. The weave's opening mask and the set's metalness map aren't used.
- **Corrugated iron:** rusty_metal_04, 1.6 m per tile, on the sheets, the dugout roof sheet and the wire pickets. The rust runs down; the bare grey patches read as metal.
- **Mapping:** the prop shader works in object space in metres, so nothing stretches along a long board.
- **Normal maps:** the orientation is checked by the "normals" test on every surface type.
- **Parallax:** only on the trench floor.
- **Wattle:** the woven hurdles have no scan; their procedural texture is darkened to sit with the scans.

**Mud and water:**
- `shaders/mud_terrain.gdshader` blends four generated muds (`tools/gen_trench_textures.py`, in `art/trench/`):
  - churned mud on the ground near the trenches;
  - sludge on the trench floors;
  - the cut soil strata on the walls;
  - firmer ground further off.
- Everything is darker and glossier the wetter it is, with puddles lying in the flat low places.
- Standing water (`shaders/water_mud.gdshader`) is opaque brown and mostly calm, with a slow shiver of wind across it.

**Light and atmosphere** (cold, wet, dark and oppressive, but readable):
- A storm sky (`shaders/overcast_sky.gdshader`): dark blue-grey cloud masses with lighter openings, silver edges and a warm-grey glow low toward the hidden sun, drifting slowly. No rain, no lightning, no sun disc.
- The light falls off down the trench: the sky is brightest, the parapets moderately lit, the upper walls dark, the lower walls and floor in deep shadow. This comes from a baked sky-visibility term (how much sky each point of ground can see, `TrenchMaze._bake_sky`) used as ambient occlusion on the ground and on every prop, not from turning the exposure down. Enemies are not darkened by it, so they stand out against the walls.
- The mud and water are very dark; the water reflects the sky softly (no hard sun glints).
- Depth haze: nothing in the first 18 m (the trench stays crisp), the far battlefield blue-grey. No dense fog in the trenches.
- A cold grade (a 3D LUT): blue-grey shadows, neutral mid-tones, a touch of warmth only in the brightest light, the darks a little desaturated. Not a blue filter, and no vignette or grain.
- Far off: tall smoke columns leaning with the wind (black over the fires, dark grey otherwise), a few orange fires flickering on the horizon with sparks (they light nothing), a ruined village and a broken church tower on the skyline, shattered trees at every distance, wrecked sandbag posts in No Man's Land, and now and then a file of soldiers walking along the skyline (`FarFigures`, scenery only).
- The bunkers and the base get their own dark lighting back.

**Dressing:**
- **No Man's Land:** two staggered rows of screw pickets with wire strung and criss-crossed between them, concertina coils along the front, and gaps where the saps go out. The wire sways a little. Beyond that: shell holes holding rainwater, dead trees, and a wrecked limber with a wheel off.
- **In the trenches:**
  - Dugouts have a bunk, crates, a telephone and a rifle rack. The gun pit has shell boxes; the OP has a telephone and a cable reel.
  - Along the walls lie shovels, picks, helmets, tins, kit bags, blankets, rifles and sheets of iron. A stretcher is left at the way in.
  - Big pieces only stand where there is room, and they have collision.
  - Hand-painted signs at the junctions name the trenches (PICCADILLY, BOND ST...) and say which way the fire trench is. Each dugout is numbered.
- **The carnival, barely:**
  - a cracked porcelain clown head half sunk in the mud;
  - a faded circus bill in one dugout, with a music box and a broken watch;
  - a tin clown on its side in a firing position;
  - a red balloon caught on the wire;
  - a grinning sign daubed on one timber lining.
- **Wind:** torn canvas over some dugout doors, telephone cable looped along the walls, and scraps of paper lifting at a few junctions.

**Sound** (`scripts/world/trench_ambience.gd`; all synthesised placeholders in `SfxSynth`, each replaceable by a .wav):
- wind, and the low rumble of the guns;
- shells landing far off: a flash on the horizon, the boom arriving later by the speed of sound, sometimes smoke rising where it fell;
- distant machine-gun bursts and rifle shots;
- timber creaking in the linings, and water dripping at dugout doors and over the flooding;
- loose wire and pickets rattling in the wind, water lapping when you are near it, and very occasionally a whistle far down the line;
- the music box playing a few bars of a waltz when you are near it, and very rarely the same tune, faint, from nowhere.

The war stays far off: nothing out there can hurt you.

**Footsteps** (the player, on trench floors): mud, duckboards, water or firmer ground, by what is underfoot. Wading throws a splash and leaves a ripple spreading on the water; mud flicks up now and then.

**Eye adaptation:** the exposure lifts slowly in a dugout or a dark corner and comes back down in the open.

**Enemies:**
- 1.5x the usual number: mostly WitzSoldaten, Rattlejacks and Klappersoldaten, a few clowns, and always an officer.
- The AI is unchanged. Hearing, the spawn spread and doorway approaches scale with the 1.5 m grid.

Settings on the game: `trench_every`, `trench_enemy_scale`, `trench_soldier_share`.

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

## Revolver

Key 7. A WW1 top-break service revolver, separate from the procedural pistol (key 1), which stays as it was as the testing gun. Six rounds of 80 damage (the pistol's are 34), one shot per pull (holding the button does not repeat; a pull up to 0.15 s early is taken as soon as it can fire), about two shots a second at most, dead accurate. Each shot kicks: the view climbs about 2 degrees and springs back on target in about half a second, the gun jumps up and back in the hand, a big flash at its own muzzle, a heavy report (synthesised `revolver_shot`), and clowns hear it as far as the shotgun.

The model is `art/weapons/revolver/revolver_parts.glb`: the Tripo model split in Blender into its working parts (how it was done: `claude/revolver-breakdown.md`). The frame, the barrel assembly on its hinge pin, a rebuilt six-chamber cylinder riding with the barrel, the extractor star, six live rounds and six fired cases, and the hammer and trigger on their own pivots.
- **Firing:** the hammer falls, the trigger comes back, the cylinder turns one chamber, and the chamber that fired now shows a fired case.
- **Reload (3 s; the rounds count at 2.35 s):** the wrist turns the gun over to watch the breech. The barrel falls open on the hinge, and at the end of the opening the extractor throws everything in the cylinder (fired cases and any live rounds left) out as real brass in the world. The brass is full size, bounces, tinks and lies on the floor for 25 s, with at most 72 pieces around. The extractor snaps back, six rounds slide in one after another, and the barrel snaps shut.
- **Swapping away before the rounds are in** abandons the reload: the chambers keep what they had.
- **No hands yet:** the rounds go in by themselves.
- **Fallback:** if `revolver_parts.glb` is missing, the fused `revolver.glb` is used with the old whole-gun reload.

Ammunition and reloads are its own, not shared with the pistol. Tuning:
- `fps_player.gd`: the Revolver entry of `WEAPONS` (`punch` is the climb in degrees).
- `view_model.gd`:
  - placement: `V_HOME`, `V_TILT`, `V_SCALE`;
  - how far the parts move: `V_OPEN`, `V_EJECT`, `V_COCK`, `V_PULL`;
  - the reload phases: `V_T_*`, `REVOLVER_RELOAD`, `REVOLVER_SEAT`.

Test: `scenes/test_revolver.tscn` (`--render` for /tmp/revolver_*.png).

## Point-blank shotgun

Inside 3 m, a shotgun blast that puts most of its charge into the chest or belly (95 damage or more on that part) goes straight through and leaves a ragged hole you can see daylight through, front to back. What was inside in the way goes with it (the ribs and guts show round the rim), and it all comes out the back in a spray of blood and meat. Tuning: `punch_range`, `punch_damage` and `punch_radius` on the clown. The hole is a tunnel along the shot drawn by the body shader (`tunnels` in `clown_body.gdshader`), up to four per body.

## Broken legs

A round in the knee (28 damage or more, within 17 cm of the joint), or enough rounds in one leg, breaks it. A living clown or WitzSoldat drops, writhes on the floor clutching the knee for a few seconds, gets up on one knee and then stands, and comes after you limping: slow, no running, the knee bent the wrong way and the body lurching down onto it every step. Shoot it again and it dies with that knee flopping wrong.

The shotgun and explosions now usually break legs instead of taking them off: a blast that would sever a leg breaks it three times in four (`leg_off_chance` on the clown, 0.25), and a living clown it does not kill goes down the same way.

Legs break rather than kill. Leg hits do 40% of their usual harm to health (`leg_damage_scale`), a strong round anywhere on the leg breaks it half the time (`leg_break_damage` 26, `leg_break_chance` 0.5) and 60 damage in one leg always does (`leg_break_total`), and a leg shot that would kill breaks a leg instead and leaves it alive; once both legs are gone a leg shot only kills one time in four. The second leg breaks the same way as the first (gunshot, shotgun or explosion), whether it is limping, writhing on the floor or getting up.

**Both legs broken: the last stand.** It does not get up. After writhing it eases out of whatever way it was lying (every bone blended from the ragdoll's pose over `settle_seconds`, 0.9 s, its body turned head-first the way it lay, so there is no snap), lies a moment, then drags itself away from you on its arms, legs trailing at wrong angles, smearing blood, stopping to gasp (on one arm, slowly, if the other is broken; not at all with neither); then it finds the nearest wall (rather one away from you), crawls out to a spot square in front of it and turns to face it while still on its front, crawls in head first, rolls over onto its back without turning, and shoves itself back on its elbows until its head meets the wall and its back slides up it; then it draws its knees up. It never turns once it is on its back or sitting, so no spinning on its backside. A floor guard keeps every knee, ankle and toe out of the floor while crawling and sitting. One that carried a gun (pistol or rifle) pulls a pistol with its good hand and fires at you from there every second or two while it can see you (7 damage, poor aim); one that did not swipes at you if you come within reach. It stays until you finish it, and counts toward the floor. Every enemy can be brought to this, the Klappersoldat included (it drags itself on its clockwork arms). `scripts/clown/clown_last_stand.gd`.

**Broken arms.** Rounds into an arm break it the same way (`arm_break_damage` 28 at `arm_break_chance` 0.4, or 55 in one arm), and explosions break them too. The arm hangs from the shoulder like a dead weight and swings with everything the body does (a damped double pendulum: thrown back when it sets off, forward when it pulls up, out to the side on a turn, kicked by every footfall and every hit, the forearm flopping from the broken elbow a beat behind; `arm_swing_freq`, `arm_swing_damping`, `arm_swing_push`), the elbow bent the wrong way, the forearm twisted, the hand limp, a splinter of bone out through the forearm and blood running from it (a snapped steel rod and torn wiring, with sparks, on the Klappersoldat). Whatever that hand held is dropped: a WitzSoldat drops the rifle (it needs two hands) and draws a pistol in the good hand, fighting on at shorter range; a club goes with the right arm; a clown hits with whichever arm still works, the Klappersoldat too. With both arms broken or gone it stops fighting altogether: it runs for somewhere you cannot see it, as far along the corridors as it can get, crouches there with its back to you, shaking, and runs again if you find it.

**Explosions** break several bones at once: each leg and each arm can go (more likely the closer it was), on top of the limbs it tears off. The final-kill injury report lists broken legs (both legs too) and arms.

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

## The Rattlejack

A British machine gunner of the carnival army: Brodie helmet, muddy khaki with washed-out red and blue, webbing, pouches, puttees, dirty white greasepaint, a small red nose and a painted grin. He carries a Lewis gun (finned barrel shroud, flat pan magazine on top) and is an ordinary infantry enemy, no tougher than a WitzSoldat (`health_mult` 1.0). He holds his ground at middle range and fires from the hip (butt tucked under the right arm, elbows loose, `Clown.hip_fire`) in bursts: about 9 rounds a second for 0.8-1.8 s, then 1.5-3 s off aim; a 47-round pan, then 3.5 s changing it (the left hand lifts the pan off, a fresh one goes on). Each round is weak and inaccurate (6 damage, 36% at point blank falling 1.4% a metre, worse if you are moving), so a burst is dangerous but not certain death (about 2.6 damage a second against a standing player in the test). He appears from floor 2 (`rattle_base` 0.08 of the floor, rising 0.02 a floor to 0.16). `scripts/clown/rattlejack.gd`; the burst firing is `ClownBrain.gunner()`.

**How he dies.** Unlike the others, who go straight to ragdoll, the Rattlejack is dead the moment the fatal round lands (the kill counts once, the AI stops, he never fights again) but his body plays out a short death first and the ragdoll takes over part-way through the fall:

- **Delayed headshot** (a fatal head shot, when the Death Rattle does not fire): the head snaps back, the chest jolts, the gun jerks up; the helmet flies off (three times in four, the usual helmet physics). The head drops forward and hangs, the shoulders round and drop, and the gun slips out of his hands; from then on both arms hang dead and swing with the body. Then for about a second he stands with nothing driving him: the whole body sways and corrects, the pelvis shifting one way while the spine bends back against it, weight moving from foot to foot (the unloaded heel lifts), knees giving and catching, ankles flexing, a small corrective step now and then, the head swinging loose on its own. Each correction is weaker than the last; then the knees fold, slowly then faster, the hips drop and he tips the way he was leaning (with some luck, toward open floor, never into a wall a hand's breadth away), the far foot coming off the floor, and the ragdoll takes him about half a second into the fall (1.6-2.6 s after the shot), with a little life left in the legs and back draining away so physics carries on the fold rather than dropping him like a sack.
- **Staggering backward** (a fatal body or arm shot): the shoulders and chest recoil, the gun is knocked out of his hands and his arms go limp; he takes two or three unsteady steps back trying to catch himself, twisting, knees buckling, the gun hanging; the ragdoll takes over before he reaches the floor (0.8-1.5 s). The steps are checked against the level: with a wall close behind he takes fewer or none and goes down sooner.
- **Death Rattle** (30% of staged deaths, head or body): his dying grip clamps the trigger. The Lewis gun fires on (9 a second) while he jerks with each round and his knees go; after 0.2-0.5 s the ragdoll takes him and the gun keeps firing for up to about a second more, still locked in his hand, every round a real ray from the muzzle wherever it now points. The rounds hit other clowns (WitzSoldaten, Klappersoldaten, other Rattlejacks, anything) through the ordinary damage, gore and death code, so they can be maimed or killed and another Rattlejack killed this way can start his own rattle; they strike drums and spark off walls. Not you, unless `death_rattle_player_damage` is on.
- **Straight to ragdoll**: explosions, the stake, heavy shotgun-class hits, a dismembering blast, or while crawling, down or in a last stand.

The balance is a small inverted pendulum (the hips' offset from the middle of the feet, pulled away by gravity, pushed back by a controller whose strength drains as he dies, nudged by irregular random shoves); the pelvis shift and drop, hip tilt, counter-bending spine and the head on its spring all follow from it, and two-bone IK keeps the feet planted where they stood (or where a step put them). When the ragdoll takes over it starts from exactly that pose with every bone already moving at the speed it was (worked out from the last two frames), so the fall carries on. The killcam stays on him while he is still on his feet, and the Death Rattle fires in step with its slow motion. The posed body is not physics, so it is watched: the moment any part of him touches a wall the ragdoll takes over there and then (`wall_guard`), and he only picks a way to fall with room for a body to land (1.1 m), so a ragdoll never starts inside a wall and gets pushed out the far side. The Zornhauptmann's Last Defiance does the same. Every setting is an export on `Rattlejack` (`enable_hybrid_deaths`, `death_rattle_chance`, `death_rattle_min/max_duration`, `death_rattle_friendly_fire`, `death_rattle_player_damage`, `enable_delayed_headshot_death`, `headshot_total_delay_max`, `enable_full_body_death_sway`, `enable_procedural_balance_corrections`, `enable_foot_ik_during_death`, `allow_corrective_foot_steps`, `enable_random_collapse_direction`, `enable_stagger_death`, `enable_pose_matched_ragdoll`, and the tuning: `head_recoil`, `torso_sway`, `hip_displacement`, `knee_flex`, `ankle_correction`, `foot_step_distance`, `balance_decay`).

The body is a Tripo model (`art/rattlejack/`), built by `tools/build_rattlejack.py` (Blender's Python) like the Klappersoldat: scaled to 1.91 m, decimated, rigged on the shared 21-bone skeleton, segmented and capped for dismemberment, gibs. The model has the helmet fused to the head, so the script cuts it off: the brim is the thin shell over the face (a ray cast inward from each face is through in a couple of centimetres), the dome is everything above where the brim meets it; the head gets a round cropped scalp where the helmet was and the helmet a dark liner across its underside. The Lewis gun is built in code.

## Der Zornhauptmann

A porcelain-faced clown officer in a charcoal tunic and a Pickelhaube, from floor 2 (6% of the enemies there, rising 2% a floor to 14%). A common elite: a quarter tougher than a WitzSoldat (`officer_health_multiplier`), slow and deliberate (walks at 1.8 m/s, never runs). The pistol hangs low in his right hand until he means to shoot; then he raises it where you can see it and holds it on you for 0.8-1.3 s before the shot, one accurate 14-damage round every two or three seconds. Breaking his line of sight, or staggering him, stops the shot. Get within reach and he uses the sabre in his left hand: the blade goes back for half a second (a slash raised over the shoulder, or a thrust drawn back to the hip), comes through in a seventh of a second, and he stays open for about two-thirds of a second after. He tracks you through the wind-up and is committed for the last part of it, so stepping back or round him beats both swings (the thrust reaches further but only straight ahead; the slash covers a wide arc). About one miss in seven (`furious_miss_chance`) makes him furious for a beat: a stamp, a shake of the head, a snarl, under a second.

The Pickelhaube is cut from the Tripo model on its brim line; the skull under it is the helmet's own faces laid onto a smooth ellipsoid (a cropped, round dome) and what was left of the band tucked in, so there is no hole and no lip when it is shot off. He holds the pistol thumb-up with a straight wrist; the arm turns at the shoulder to keep it upright.

**The Last Defiance.** On 80% of eligible deaths (`last_defiance_chance`; a fatal round to the body or an arm from any gun but the stake gun, not a headshot, not an explosion, nothing blown off him, the pistol still in a working hand, on his feet; press **L** in game to make every eligible kill one while testing) he is dead and counted at once, but his body plays out 1.8-2.5 s first:

- 0-0.4 s: the round lands. Thrown back and twisted, a shoulder drops, the knees bend.
- 0.4-1.0 s: a heavy slump to one side (the way the round pushed him, unless there is a wall), head hanging, the hips, knees and ankles fighting to keep him up on planted feet, trembling.
- 1.0-1.8 s: the pistol comes up, shaking and wavering, and the head lifts with it.

Then the trigger, and one outcome, picked once when he dies from five weights (normalised, all exports):

| Outcome | Weight | What happens |
|---|---|---|
| Real shot | 0.55 | One real round from the real muzzle, wherever it points (he aims, badly, at about where you were; 9 degrees of spread on top; no targeting): a flash, a report, ordinary pistol damage to whatever it meets. The recoil puts him down |
| Fails to fire | 0.20 | A dry click. The arm trembles, drops, he goes |
| BANG! flag | 0.15 | A pop, and a thin rod springs out of the barrel in about a tenth of a second with a cream paper flag reading "BANG!" in red. It wobbles. He turns his head toward it, a little, for half a second, then goes down. No round, no flash. The flag stays on the muzzle through the fall and the ragdoll and goes when he does |
| Confetti | 0.07 | A soft pop and a small puff of faded red, yellow, blue and cream paper that drifts down |
| Bubbles | 0.03 | A rubbery squeak and three to seven soap bubbles drifting up; some pop |

Nothing gives it away beforehand: the slump and the raise are the same whatever comes out, and there is no music or comic timing. The ragdoll takes him at the start of the final loss of balance, from the exact pose and with every bone's speed (the Rattlejack's hand-over). Shot again while he is playing it out (`last_defiance_interruptible`), after the first 0.45 s (`last_defiance_interrupt_grace`: rounds still coming from a held trigger only rock him), he goes straight to the ragdoll: a gag not yet fired is cancelled, one already out runs its course, a deployed flag stays on the pistol; the kill is not counted again (other pellets of the shot that killed him do not count as a new hit). The killcam stays on him until he falls, and while it has your controls his real round cannot hurt you (`real_shot_result` says "player_spared").

The pops, squeaks, click, snarl, breathing, sabre swish, stamp and boots are placeholders made in code (`SfxSynth`); drop a recording named `pop.wav`, `soft_pop.wav`, `spring.wav`, `squeak.wav`, `bubble_pop.wav`, `dry_click.wav`, `snarl.wav`, `breath.wav`, `whoosh.wav`, `stamp.wav` or `step.wav` into `art/zornhauptmann/sfx/` and it is used instead. The pistol shot is the WitzSoldat's report, pitched up. The pistol, sabre, flag, confetti and bubbles are procedural meshes.

Settings on `Zornhauptmann`: `officer_health_multiplier`, `pistol_damage`, `furious_miss_chance`, `sabre_slash_damage`, `sabre_thrust_damage`, `sabre_windup`, `sabre_strike`, `sabre_recover`; `enable_last_defiance`, `last_defiance_chance`, `real_shot_weight`, `fail_to_fire_weight`, `bang_flag_weight`, `confetti_weight`, `bubbles_weight`, `last_defiance_min_duration`, `last_defiance_max_duration`, `last_defiance_interruptible`, `last_defiance_interrupt_grace`, `max_real_shots`, `real_shot_spread`, `bang_flag_visible_duration` (0: as long as the pistol), `confetti_particle_count`, `bubble_count_min`, `bubble_count_max`, and the inherited `enable_pose_matched_ragdoll`. On the brain (`ClownBrain.officer()`): `aim_times`, `shot_gap`, `accuracy`, `move_speed`, `melee_range`. In `game.gd`: `zorn_base`, `zorn_per_floor`, `zorn_max`.

## Shot through the throat

Any flesh enemy (clowns, WitzSoldaten, Rattlejacks, Zornhauptmanns; not the clockwork Klappersoldat) killed by a round in the neck itself, under the chin, or the very top of the chest in the middle, does not just drop. The kill counts at once, then: the weapon falls from his hands, both hands fly to his throat and clamp there, he staggers and sinks, and goes down writhing (twisting, kicking, drawing his knees up) while the artery pumps: a jet with every heartbeat that reaches the walls and spatters the floor, a steady run of blood between the beats, and a pool spreading under his neck once he is down. The beats weaken and slow as he bleeds out (5-7.5 s), the writhing fades, and he goes still. A face shot is still a headshot. Another round (after the first third of a second, so a held trigger does not count) ends it on the spot. The killcam stays on him while he bleeds.

The neck now has its own hitbox (a capsule from the base of the neck to under the chin): before, a round there could pass between the chest box and the head sphere. Settings on `Clown`: `enable_throat_death`, `throat_death_chance` (1.0), `throat_bleed_seconds`, `throat_interrupt_grace`, `throat_spurt_strength`. Gurgling and choking are placeholder sounds (`gurgle.wav` and `choke.wav` in `art/zornhauptmann/sfx/` replace them).

## Carnival Curse

The player's super kill. Every enemy you kill charges it (bottom centre of the screen: a little clown face filling up, "CARNIVAL CURSE 7/10"); at ten it is full ("CARNIVAL CURSE READY [Q]"), the face pulses violet and a music-box plays. It holds one charge; further kills do nothing until it is spent. What counts: any enemy the game counts as your kill, once. Not a kill made by another enemy (a Rattlejack's Death Rattle, a dying officer's last shot), and not the curse's own victims.

Aim at an enemy: the crosshair becomes a violet diamond when he can be cursed (red for an immune one). Press Q and a small cracked porcelain clown head, the Jester's Hex, flies from your hand (24 m/s, a slight homing, two ribbons trailing, a faint violet glow). If it hits a living enemy who can be cursed, the charge is spent. If it misses, hits a wall or a corpse, or runs out of range (35 m) or time (2.2 s), it shatters and the charge is kept. Pressing Q with nothing valid under the crosshair does nothing ("NO TARGET"). Only one head in the air at a time. You keep full control the whole time.

The hit enemy is dead and counted at that moment, drops his weapon and stops everything (no Death Rattle, no Last Defiance, no throat bleed-out). Then he is played as a broken marionette, standing on his own feet, for 2.7 s:
- **Seizure** (0-0.5 s): stiff jolts through the chest and shoulders, the knees half-buckling; violet strings fade in above him.
- **First arm** (0.5-1.1 s): two or three jerks, each further than the last, into a shape an arm cannot make (straight out, upper arm wrenched round, forearm snapped back the wrong way); a crack on the last. It stays there.
- **Second arm** (1.1-1.7 s): the other arm, a different shape (wrenched back and down behind him, forearm bent out and up), its own crack. Which arm goes first varies; with a wall close on one side, that arm is pulled in against the body instead, and any arm that would reach into a wall is tucked in.
- **Neck** (1.7-2.2 s): a twitch, a small jerk the other way, a beat, then the head snaps over sideways (about 50°, spread over the chest, neck and head so the collar and face are not stretched) and twists, with a loud crack; the convulsions stop dead.
- **Pause** (2.2-2.4 s): he stands quite still, broken.
- **Collapse**: the strings are cut, the knees go and he tips toward open floor; about 0.3 s later the ragdoll takes him from exactly the pose he is in (the bones' current speeds carried over, joint limits widened just enough for the broken arms and neck), so he falls in that shape and stays in it. Blood from the cracked joints; a pool.

The Klappersoldat gets the same, but the cracks are metal (sparks, an oil spurt at the neck, no blood). Rattlejacks and Zornhauptmanns can be cursed: no Death Rattle, no Last Defiance. Anything already down (crawling, legless, in a last stand, a ragdoll) can't be cursed. An enemy with `curse_immune` set (for bosses) is immune unless `boss_instant_kill` is on. An explosion or a stake during the execution cuts him loose into the ragdoll at once. The final-kill camera stays on a cursed last enemy until he has fallen.

Settings on `CarnivalCurse` (`scripts/player/carnival_curse.gd`, made by the player): `enabled`, `required_kills` (10), `max_stored_charges` (1), `curse_range` (35), `projectile_speed` (24), `projectile_lifetime` (2.2), `execution_duration`, `initial_seizure_duration` (0.5), `first_arm_duration` (0.6), `second_arm_duration` (0.6), `neck_duration` (0.5), `final_pause_duration` (0.2), `allow_arm_order_variation`, `allow_neck_direction_variation`, `use_puppet_strings`, `pose_matched_ragdoll`, `counts_towards_recharge` (false), `boss_instant_kill` (false), `key` (Q). The execution itself is `scripts/clown/marionette.gd`; the head is `scripts/player/jesters_hex.gd`. The head is built from primitives and the sounds (music box, wind-up, porcelain, cracks, creaks) are synthesised placeholders.

## Final-kill camera

Kill the last enemy on a floor (or the last one in an event room) and the view leaves your eyes for a few seconds, RDR-style: a cinematic camera (a little narrower, letterboxed) picked for how and where it died, time slowing smoothly to a quarter speed, the body doing whatever the physics does with it, time easing back, a beat at full speed on the corpse, then back to your eyes. Ordinary kills never trigger it; it runs once per floor or room, even if the last two die in the same blast. While it runs you cannot move, look or shoot (the gun and crosshair are put away), and nothing about you is changed: position, view, weapon, ammo.

**Choosing the shot** (`scripts/fx/kill_cam.gd`): when it starts it takes the middle of the body (between chest and hips), the floor and ceiling there, which way the fatal shot pushed it (else away from you), its facing and where you are, and scores candidate cameras. Each kind of shot has an ideal bearing round the body and every bearing is tried, pulled in if it does not fit: **low side** (just above the floor, side-on to the way it falls), **three-quarter**, **elevated** (looking down, where the ceiling allows), **ground** (a few centimetres off the floor, favoured for a Klappersoldat), **rear** (behind it, looking past it the way it will go), **over the shoulder** (for a kill close up, or a corridor too tight for anything else) and **tracking** (riding alongside a body going off a ledge or down a long drop). A candidate is thrown out if the camera would be inside the level, the body cannot be seen, or too little of the body and the floor it will land on is in view; the rest score for how much they can see, how side-on they are to the fall, room round the camera, how close they are to that kind's ideal bearing, and that kind's suitability (elevated and tracking for falls, over the shoulder up close), plus a little randomness, minus a penalty for the last few shots used (kept across floors, so finales vary). Nothing fits: it stays in first person and just slows time.

**Running it**: most shots are stationary: the camera stays put and turns gently to keep the body in frame, so the body falls through the shot; a tracking shot follows the body smoothly, kept out of walls. It flies in from your eyes in 0.35 s (or cuts through black if there is a wall between), and back the same way. It watches the ragdoll the game already made and never touches it. It stays on while the body is still moving fast, a Klappersoldat, Rattlejack or Zornhauptmann is still on its feet in its death, or someone shot through the throat is still bleeding out, up to a hard limit.

**Time and sound**: real time drives it. 0.2 s easing from full speed to 25%, held 1 s, eased back over 0.8 s, 1 s at full speed, 0.4 s back to you (about 3.4 s in all). While time is slow the sound is muffled (a low-pass on the master bus) and a little lower in pitch, both back to normal with the speed.

**Safety**: if the body is freed it goes straight back to you; if you die, the game pauses, the floor changes or it runs past the limit, it stops at once. Every way out puts the time scale, sound, camera, HUD and controls back.

**The brutality report**: worked out from the body as the killcam comes back to full speed, but only shown once the killcam is completely over and the view is back with you (`scripts/clown/injuries.gd` works it out, `scripts/ui/brutality_report.gd` shows it; nothing if the killcam was cut short). Its sounds play 12 dB down (`volume_db` on the report), and "EXIT OPEN" waits until it has finished. A parade-drum roll; FINAL KILL slammed in; then every injury the enemy took, one at a time with its brutality points, mildest first and the worst last; the BRUTALITY total counting up; the rank stamped down with a cymbal crash and a wheezy calliope ta-da and confetti from both corners; then the tickets ring up (one per 25 points, at least 1, at most 40) and it fades. Ranks: CLEAN KILL, NASTY, BRUTAL, SAVAGE, BUTCHERED, GRAND GUIGNOL.

Where every round landed is logged on the body at the moment it hits (in rest-pose space, so a bullet's place on the body is known whatever pose it was in), and read against the head and torso: through the left or right eye, between the eyes, the forehead, a temple, the back or crown of the skull, the nose, a cheekbone, the mouth, the jaw shot away, the throat, the neck snapped; the heart, a lung or both, a collarbone, the spine, the liver, the spleen, gut-shot, the pelvis or the groin; enough in one limb shatters its bone (femur, shinbone, humerus, forearm); a kneecap blown off. Then what the gore did: brain destroyed, skull split open, decapitated, ribcage blown open, guts spilled, shot clean through, limbs torn off, torn in half, impaled on a stake; for explosions how close (nearby, close, point blank) and the bones it broke (ribs, collarbone and pelvis, back) and burst eardrums. Riddled with bullets, overkill (total damage against its health) and shots after it died count too. A Klappersoldat gets an engineer's report instead: optic lens shattered, porcelain brow, jaw hinge sheared, clockwork governor destroyed, iron skull cracked open, mainspring snapped, bellows punctured, drive shaft severed, oil reservoir ruptured, gear train spilled, frame rods snapped, oil lines ruptured; its ranks run DECOMMISSIONED, DENTED, WRECKED, SCRAPPED, SHREDDED, SCRAP HEAP. Each finale's report and the best score are kept (`last_report`, `best_brutality`). Points per injury are in `Injuries.POINTS`; the sounds (`art/ui/sfx/`) are synthesised placeholders (`tools/gen_fanfare_sfx.py`).

Settings (exports on `KillCam`, the game's `KillCam` node): `enabled`, `min_time_scale` 0.25, `impact_seconds` 0.2, `slow_seconds` 1.0, `recover_seconds` 0.8, `focus_seconds` 1.0, `return_seconds` 0.4, `max_seconds` 5.0, `fly_in_seconds` 0.35, `dynamic_angles`, `stationary_shots`, `tracking_shots`, `avoid_repeats`, `follow_falls`, `collision_checks`, `audio_muffle`, `letterbox`, `fov` 60, `distance` 2.9, `height` 1.35, `aim_smoothing` 3.0, `track_smoothing` 2.6, `fall_drop` 1.2.

## Joker lockers

On about 60% of bunker floors a bank of three tall, thin WW1 steel lockers stands against the wall of a long straight corridor (away from the pipes, never near the start). They are olive drab, chipped through to primer and bare steel and streaked with rust, with pressed louvres top and bottom, a latch handle and a stencilled number. One has a little joker playing card nailed to its door. While you are within 7 m, every few seconds something in that one may laugh (a cackle, a giggle or a slow wheezing laugh, muffled by the steel) and the door jumps on its latch.

Every locker door takes bullets (a bright nick and a dent you hear), but only the joker's opens: each round through it spits blood back out of the hole, and after about 90 damage (three pistol rounds) the latch gives, the door slams back on its hinges, and a dead clown pitches out face first onto the floor. Its bullet holes are where your rounds went through the door, plus older ones: it has been shot before. It has been in there a long time: its greasepaint soured to a grey-green pallor, black mould blooming through the costume, a brown tide-mark up the legs, the blood on it gone brown. It is not one of the troupe: it wears a court jester's three-pointed cap (faded plum and mustard, bells gone green) and died with a joker card clenched in its teeth. The rest of its deck comes fluttering out after it. Finding it is worth 8 tickets ("LOCKER JOKER!"; it is not a kill and does not count toward the floor's clowns).

`scripts/world/joker_locker.gd` (the bank, the laugh, the door), `scripts/clown/locker_joker.gd` (the clown's look, its fall, the cards). The card and paint textures and the sounds (`art/locker/`) are placeholders made by `tools/gen_locker_assets.py`.

## Blood pools

Blood (and the Klappersoldat's oil) pools on the real floor. When a pool starts, it casts a grid of downward rays round its source, once, spread over a few frames (`pool_work_ms`, 2.5 ms a frame for all new pools together). That gives the floor height and slope at each point, and which points are inside a wall or a box. A flood from the source over that grid works out how soon the blood would reach each point:

- **Steps and sills:** it cannot climb anything over 2.5 cm, so a step, a door sill or a box stops it.
- **Slopes:** it runs downhill more readily than uphill, so on a slope the pool comes out longer downhill.
- **Down stairs:** it can run over a step edge (up to 0.45 m down, at most `maximum_stair_flow_steps` times). It goes over in a few narrow tongues rather than a sheet, and spreads less on each tread below, so a little blood stays on the tread it fell on and a lot runs a step or two further.
- **Walls:** walls block it, and blood that is stopped by a wall or a step spreads further the other way, so a pool against a wall runs along it.

Each source gets its own outline from a seed: an ellipse at a random angle, soft lobes, and now and then a narrow tongue (`shape_variation`). No two are alike.

The pool is a mesh built on the floor itself. Where a step edge or a wall runs through a grid cell, the cell is split at the edge (found with a few more rays). Each part lies on its own surface, and a strip runs down the step face where blood went over. Nothing spans two heights, so nothing floats.

Every vertex carries when the blood reaches it. The shader draws the pool up to the current progress, which rises over 3-8 s (more for more blood, `pool_expansion_duration`) then creeps to a stop over 1-3 s (`pool_settling_duration`). Growing costs one shader parameter a frame, and nothing once the pool has settled.

- **Look:** dark red, deeper and darker toward the middle, glossy where it is thick, thin edges a little see-through, a rounded lip at the edge, a few separate droplets just past it, and thin runs down step faces. It dries from the edges in over `DRY_TIME`, going brown and dull.
- **Merging:** a second body bleeding next to a pool feeds that pool as a new source (one mesh, no doubled darkening).
- **Caps:** at most `MAX_POOLS` (28) blood pools, the oldest fading out; at most `maximum_active_spreading_pools` growing at once. Sampling is coarser far from the camera (`surface_sampling_quality` sets the grid: 0.12 / 0.085 / 0.065 m). Oil puddles are never recycled, as before.

All the settings are exports on the `Blood` autoload (`scripts/blood/blood_manager.gd`): `enable_organic_pool_shapes`, `enable_geometry_aware_spreading`, `enable_stair_flow`, `enable_slope_bias`, `enable_pool_merging`, `enable_wet_reflections`, `pool_expansion_duration`, `pool_settling_duration`, `shape_variation`, `edge_irregularity`, `maximum_pool_radius`, `maximum_active_spreading_pools`, `surface_sampling_quality`, `maximum_stair_flow_steps`. The pool itself is `scripts/blood/blood_pool.gd`.

Two scenes for checking it:
- `scenes/test_pools.tscn`: a test room with a wall, a 4 cm sill, debris, a platform with five steps (the maze's stair dimensions) and a 10° slope.
- `scenes/look_pools_game.tscn`: films pools at the top of a real staircase.

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
| Rattlejack | `art/rattlejack/` | Lewis gun: bursts at 9 rounds a second, pauses, pan changes; weak inaccurate rounds. Staged deaths (delayed headshot, stagger, Death Rattle) handed to the ragdoll mid-fall. Helmet comes off |
| Zornhauptmann | `art/zornhauptmann/` | Officer: pistol raised in sight, one accurate round every 2-3 s; sabre wind-up, slash or thrust, recovery up close; slow; 1.25x health. Last Defiance on 80% of body kills: one last trigger pull (real shot, click, BANG! flag, confetti, bubbles). Pickelhaube comes off |

Every body uses the same 21 bone names and 15 dismemberment segments, so the ragdoll, deaths and gore work on all of them. A new body is added to `Clown.BODIES` in `clown.gd`: model, gibs, the rest-pose box from its `.json`, how much thicker its collision shapes are than the clown's, and optionally a helmet. The insides shown when the head, chest or belly is blown open are laid out on the clown and moved onto each body's own bones; `innards_scale` shrinks them for a smaller head (the Zornhauptmann's).



| Path | What it does |
|---|---|
| `scripts/clown/clown.gd` | One enemy (clown or WitzSoldat): body, hit zones, health, death reaction, helmet, weapons |
| `scripts/clown/clown_ragdoll.gd` | Physical skeleton, joint limits, muscle tone and death profiles |
| `scripts/clown/clown_gore.gd` | Wounds on the body, bleeding, pooling, limb loss |
| `scripts/clown/gib.gd` | A severed body part |
| `scripts/clown/gore_bit.gd` | Meat chunks, skull fragments, links of gut |
| `scripts/blood/blood_manager.gd` | Autoload `Blood`: splatter decals, droplets, mist, pools |
| `shaders/clown_body.gdshader` | Bullet dents, blood soaking into cloth (a dark irregular stain with a tide line, wet only round the hole, droplet spray and runs; `soak_darkness`, `spatter_amount`), hiding severed limbs. `scenes/look_blood.tscn` films three shot bodies in lantern light |
| `scripts/blood/blood_pool.gd` | One pool: samples the floor, floods it (steps, walls, slopes), builds a mesh on the surfaces |
| `shaders/blood_pool.gdshader` | The spreading pool's look: grows with `progress`, thickness, gloss, lip, droplets, runs, drying |
| `scripts/player/fps_player.gd` | Player, health and the weapons |
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
| `scripts/clown/rattlejack.gd` | The Rattlejack: Lewis gun, pan changes, the staged deaths (balance, foot IK, hand-over to the ragdoll), the Death Rattle |
| `tools/build_rattlejack.py` | Builds the Rattlejack's rigged body, gibs, separate helmet and spec from the Tripo model (Blender Python) |
| `scripts/clown/zornhauptmann.gd` | Der Zornhauptmann: pistol and sabre, temper, the Last Defiance and its five outcomes (the flag and bubbles are classes inside it) |
| `tools/build_zornhauptmann.py` | Builds the Zornhauptmann's rigged body, gibs, Pickelhaube and spec from the Tripo model (Blender Python) |
| `scripts/fx/sfx_synth.gd` | Placeholder sounds made in code (pop, squeak, click, snarl, breath, swish, stamp, boots), replaced by any recording of the same name |
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
godot --headless res://scenes/test_pools.tscn                       # Blood pools: different outlines, lie on the floor, stop at a wall (and spread along it), held by a 4 cm sill, run down stair treads in proportion to the blood, never span two heights, do not climb stairs, longer downhill, grow and settle, merge, oil, 25 at once (add "render" with a window for pictures)
godot --headless --fixed-fps 60 res://scenes/test_rattlejack.tscn  # Rattlejack: walls (every staged death and the Last Defiance with a 0.3 m wall close on each side, falling toward it or not: never in or through it); model, helmet, Lewis gun; bursts (~9 rounds/s), pan change, damage to the player; the staged deaths (headshot sway: head snap, helmet, pelvis/knees/ankles, planted feet, steps, hand-over mid-fall without a jump, fall directions; stagger steps and a wall behind; Death Rattle firing through the ragdoll, gun in hand, hitting clowns; blast fallback) (sections: model fire deaths; "film render" for frames)
godot --headless --fixed-fps 60 res://scenes/test_throat.tscn  # Throat shots: where on each body a round counts as the throat (not the face, not the belly); the death on four bodies (counted once, weapon dropped, hands at the throat, down, writhing, spurts slowing, blood on floor and wall, a pool, then still); never the Klappersoldat; shot again ends it, a held trigger does not (sections: aim deaths interrupt; "render [only=kind]" for frames)
godot --headless --fixed-fps 60 res://scenes/test_zornhauptmann.tscn  # Zornhauptmann: model, Pickelhaube, pistol and sabre, 1.25x health; pistol raised 0.8-1.3 s, a shot every 2-3 s, accurate, stopped by losing sight or a stagger, slow, furious on ~15% of misses; sabre wind-up, cut if you stand, missed if you step back or round; Last Defiance on ~80% of eligible kills, never on headshots/explosions/limb-taking blasts/a lost pistol arm, outcome weights normalised; each outcome (counted at once, 1.8-2.5 s, slump, raised pistol, trigger, hand-over, what it leaves, nothing lingers); interrupted before and after the trigger; three at once beside a clown and a Rattlejack (sections: model combat sabre odds outcomes interrupt crowd; "film render [front] [only=outcome]" for frames)
godot --headless --fixed-fps 60 res://scenes/test_klapper.tscn     # Klappersoldat: speed, square-to-the-maze walking, knees/ankles/elbows, foot slide, head snaps, noticing you (head, then body, then it moves), the blow, staggers, mechanical gore, the deaths (head; random body deaths: shorting out and toppling all four ways, collapse, malfunction; how often each comes up), smoke, oil puddle, ordinary clowns unchanged (sections: walk notice fight gore deaths crowd; add "render" for pictures, "film render" for the walk)
godot --headless res://scenes/test_drum_clear.tscn          # twelve floors: counts fuel drums standing inside anything solid (should be 0)
godot res://scenes/test_seethrough.tscn -- 3 [full]          # needs a window: paints every pixel with its distance and checks it against physics rays from every cell; drawn further than the wall = a hole you can see through
godot --headless --fixed-fps 60 res://scenes/test_wander.tscn  # unaware clowns wandering and searching: how often a step runs into a wall or doorway pillar
godot --headless --fixed-fps 60 res://scenes/test_base.tscn    # title -> base -> every station -> a run with a table -> death -> base -> new game (--render for /tmp/base_*.png)
godot --path . res://scenes/test_soldier_anim.tscn             # WitzSoldat walk cycle, side-step, carry/aim front and 3/4, the club carrier walking and swinging, three deaths; /tmp/sa_*.png and joint angles
godot --headless --fixed-fps 60 res://scenes/test_limbs.tscn   # broken limbs on a real floor: leg shots break and rarely kill; both legs: last stand (crawl, wall, sit; pistol or swipe); the Klappersoldat; a broken arm dangles, rifleman to pistol; both arms: hides out of sight; explosions break several bones (sections: legshots last klapper arms blast; add "render")
godot --headless --fixed-fps 60 res://scenes/test_locker.tscn  # joker lockers: laughs near, silent far; plain doors stay shut; the joker's door bursts at ~90 damage; the clown falls out riddled, face down in front, cards spilled; 40 floors placed flush to a wall (sections: open levels; add "render" for /tmp/locker_*.png)
godot --headless --fixed-fps 60 res://scenes/test_killcam.tscn  # final-kill camera: ordinary kills leave it alone, the last kill runs it once, time curve, never inside the level, body in view, player untouched and restored; shots chosen over 12 floors; two at once; interrupted (player dies, body freed, floor changes, pause); a Klappersoldat; a fall off a platform; an event room; the injury report (eye, jaw, heart, lung, guts, liver, explosion, Klappersoldat wording); the report over a floor finale, tickets paid a cursed last kill (sections: injuries report floor variety double interrupt klapper zornhauptmann throat curse fall event; add "render")
godot --headless --fixed-fps 60 res://scenes/test_curse.tscn   # Carnival Curse: charging (counted once, not friendly or curse kills, full waits), the HUD text; aim checks (not charged, nothing under the crosshair, immune, a body on the floor); a real hex in a level (a wall, a target that died in flight, running out of time: all keep the charge; one in the air; a hit executes, others carry on, no cinematic); the execution on five bodies (phases in order, arms jerk into place and stay, neck snaps, still in the pause, hand-over pose error, no fling, cracks, blood or oil, nothing left behind); walls on each side; one arm gone, a blast mid-curse, freed mid-curse; ten in a row (sections: charge aim play bodies walls edges repeat; "render [front] [only=kind]" for frames; "closeup render" for the broken neck held still from three sides)
godot --headless --fixed-fps 60 res://scenes/test_trench.tscn  # Drowned Trenches: 30 layouts (all connected, nothing touching that should not, 260-290 m of trench, landmarks); collision is the walked surface; in the game: floors 3 and 6 are trenches, 1, 2 and 4 bunkers, the light swaps, mostly soldiers, the exit door on the floor, the player walks the whole route (duckboards, slopes) without sticking; the ambience (footsteps on mud, duckboards and water, shells, the music box, nothing that hurts, the dressing all there); bodies on a duckboard, in water, on a fire step, against an earth wall and a Carnival Curse all settle on the ground, blood pools (sections: layouts ground game bodies ambience; "views render" for /tmp/tr_*.png; "floor render" for the trench floor close up, new mud against the old; "normals render" checks the normal-map orientation on the ground, the floor and walls facing each way (a known slope must lean the shading normal away from uphill); "relief render" lights raised domes and a groove from one side (/tmp/tr_relief.png); "parallax render" checks the floor parallax puts the surface 4.5 cm down exactly as a really lowered floor would look, from 80 to 17 degrees, and films down the longest straight stretch at five pitches; "walls render" shows walls and ground up top; "section render" films representative stretches (a fire bay, sandbags, iron, a bare earth trench, the slumped stretch, duckboards) in /tmp/tr_sec_*.png; "ascii" prints a layout)
godot --headless --fixed-fps 60 res://scenes/test_nav.tscn -- trench  # the crowd navigation test on trench floors 3, 6, 9
godot --path . res://scenes/render_level.tscn                  # saves views of a level to /tmp/lvl_*.png (needs a window)
```
