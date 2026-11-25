# Jest in Pieces — what takes it to the next level

*24 Nov 2026. Andrew's brief: a cinematic WW1 war experience on the battlefield (Battlefield 1)
coupled with tight corridor shooting in a dusty bunker (Wolfenstein: The New Colossus). Graphics,
active ragdolls, gameplay, setting, whatever else. Written from the code, not from a feeling.*

---

## 1. Where it stands — the honest audit

66,000 lines of GDScript; roughly a third of it tests. The strengths are unusual for an indie
project and they are the hardest part to build, which is why the rest now shows:

**Already strong**
- **Bodies.** `clown_ragdoll.gd` is a real active ragdoll (per-bone muscle tone curves, 6DOF joint
  limits, support/upright springs, momentum carried from locomotion, landing bounce, twitch) with
  ~20 death profiles, three enemy skeletons sharing it, a gore layer (`clown_gore.gd`: wounds, bleeds,
  severing, halving, head opening, throat, broken legs, crawlers, last stands, gibs with cast-off),
  anatomy under the skin. No shipped indie FPS I can name has this; few AAA ones do.
- **The Front's systems.** Director with tension/alertness, squads, events out of sight, five crossing
  variants, three light rolls, surface-aware impacts, MG arcs, shells, flares, lanterns, fog with a
  visibility number the AI shares. The *machinery* of a battlefield is there.
- **Weapons.** Six period guns with handling detail (bolt, chargers, double action, pump, climb that
  builds through a burst), pierce, near-miss suppression, grenades under/overhand.
- **Rendering baseline.** Forward+, SDFGI on the trench floors, SSR, SSAO+SSIL, volumetric fog on
  the Front, filmic tonemap, custom mud/water/sky shaders, PBR models, VRAM-compressed, FSR 1.
- **Meta.** A base with perks, trophies, stats, armoury, fortune cards; records; a title screen with art.

**Thin — and what the eye and ear notice first**
- **Sound.** 46 .wav files in the whole project, most of them UI stings and the Klappersoldat's
  clockwork. Player gunshots, impacts, footsteps, breath, gurgles, the whole battlefield bed: synthesised
  placeholders in `sfx_synth.gd` (1,115 lines of tone generators). **No music system at all.** No
  reverb zones (a shot sounds the same in a concrete corridor and in open mud). No enemy voices.
  This is the single biggest gap between the game and either reference; BF1 is 50 % its sound.
- **The player's body.** `fps_player.gd` has walk/run/crouch/ADS (rifle only), recoil and a crosshair.
  No sprint-slide, no lean, no mantle/vault (over a parapet or a sandbag wall — in a trench game),
  no melee, no bayonet, no weapon inspect/holster, no landing dip, no sprint FOV. Damage feedback is a
  red overlay alpha and a 0.25 rad roll (`take_damage`, line 945). Health only; no armour; spare ammo
  unlimited ("for now", line 104). The bodies on the floor and the player have no relationship.
- **Living hit reactions.** Alive enemies are animated procedurally (mocap legs from `SoldierClips`,
  arms by IK, upper body code) and a hit is a spring kick on that skeleton (`_flinch_from`,
  `flinch_away`). Good at a glance; at Wolfenstein range the body never *physically* answers a
  non-lethal shotgun blast. The active ragdoll switches on only at death.
- **Bunker light.** `game.gd` builds the bunker environment with `volumetric_fog_enabled = false`,
  one shadowed light, caged bulbs. Clean, but no light shafts, no dust in the air, no colour grade —
  it reads as a well-lit level, not a place.
- **Authorship.** Everything is generated from grids (`maze.gd`, `level_art.gd`, `trench_maze.gd`,
  `front_maze.gd`). The generators are excellent at *space*, but the memorable rooms in Wolfenstein
  and the memorable moments in BF1 are authored. The game has two authored moments (the card table,
  the Zornhauptmann) and a handful of event rooms.
- **Company.** You are always alone. BF1's Operations are moving because other men go over the top
  with you and die beside you. There is no friendly body in the game.
- **Loop depth.** 11 run upgrades + 5 base perks, numeric (+damage, +fire rate, +health). Two
  objectives (eliminate / cross). No choices mid-floor, no weapon mods beyond the drum, no economy
  except tickets at the end.

---

## 2. The lens: what BF1 and TNC actually do

**Battlefield 1** sells *scale and being small in it*: the far war as a constant bed of sound and
light, your own squad dying around you, weather and smoke you cannot see through, a landscape
that is a graveyard (wire, wrecks, craters), set-pieces that arrive (a barrage walks toward you, a
flare goes up, a whistle blows and a line stands). Its gunplay is weighty but forgiving; its
signature frame is a silhouette in haze against fire.

**Wolfenstein TNC** sells *your body in a tight space*: the gun fills the screen with mechanical
animation, every surface answers a shot, enemies shout and telegraph, dual damage (health + armour)
scavenged from the floor keeps you moving, the camera leans and slides and tilts, every room is an
arranged diorama with a reason (a lab, a kitchen, a boiler room) and a way to enter it violently.
Its gore is a reward delivered at close range with the body landing somewhere interesting.

The game has the second half of both sentences (the bodies, the systems). It needs the first half:
the *senses* and the *authorship*.

---

## 3. The ranked list

Ordered by how much the player would feel per week of work, with the code they touch.

### A. Sound and music (the biggest jump, by far)
1. **Buses and spaces.** Master / SFX / Ambience / Voice / Music / UI buses; a Reverb effect per
   space driven by `Area3D` zones the generators already know (bunker corridor, hall, dugout, open
   field, shell hole). A shot in a concrete corridor should ring for a second; in the field it
   should crack and roll away. This is an afternoon and it changes every sound at once.
2. **Real recordings for the player's guns**, layered: mechanism (bolt, pump, hammer) + body (the
   shot, near) + tail (indoor / outdoor, chosen by the zone) + shell drop by surface. CC0/royalty-free
   libraries are enough to start (Sonniss GDC bundles, Freesound CC0, BOOM free packs). `SfxSynth.stream()`
   already falls through to a .wav of the same name — the hook is there.
3. **The battlefield bed.** A looping, layered far-war bed (rumbles, distant MGs, a whistle now and
   then, crows) whose layers the Front director already has numbers for (tension, sector alertness,
   distance to the enemy line). Muffled when you go underground (Milestone 10 half-did this with
   foreground sounds — do it with a low-pass on the Ambience bus too).
4. **The player's own body.** Breath that builds with sprint and ADS, footsteps by surface (mud,
   duckboard, concrete, water — `surface_impacts.gd` already classifies surfaces), cloth, a heartbeat
   under 25 health, a low-pass + ring after a shell lands close (BF1's shell shock).
5. **Enemy voices.** German barks: spotted, reloading, grenade, flanking, hit, dying (the clowns can
   laugh in there). Even TTS placeholders routed through the Voice bus would transform readability —
   Wolfenstein's corridors work because you *hear* the room before you see it. Occupied dugouts
   (M10) already cough and mutter; make that the norm.
6. **Music.** Adaptive stems (ambient / tension / combat / aftermath) crossfaded on the director's
   state; a stinger on the final kill (the kill cam has nothing under it); the fairground organ
   bent wrong for the circus layer. Silence is a tool too — the crossing at night should be nearly
   bare until a flare.

### B. The player's body (Wolfenstein's half)
1. **Movement verbs:** sprint → crouch = **slide** (with a camera tilt and a skid in mud); **lean**
   (Q/E, or auto-lean at cover edges); **mantle/vault** onto parapets, over sandbag walls and out of
   shell holes (ramps exist; a mantle is what a trench demands); ladders in bunker shafts; a landing
   dip and a sprint FOV kick; head roll into turns.
2. **Melee.** A trench club / knife strike (V) that uses the ragdoll (a hit is an impulse on the
   bone plus a flinch) and a **bayonet** on the SMLE: a lunge that pins a man to a wall like the
   stake gun did, a charge that carries him off his feet. Close-range executions on downed/crawling
   men — the gore layer already has crawlers and last stands waiting for this.
3. **Damage with direction.** A directional hit indicator, a camera punch from the hit side, a
   desaturate-and-vignette curve below 40 health, mud/water on the lens in the field (rain, a shell's
   splash) — Andrew said no *enemy blood* on the lens; the player's own world on it is different.
4. **Health, armour, ammo from the world.** TNC's loop is scavenging mid-fight. Helmets (already
   separate meshes on the WitzSoldats) as armour pickups; field dressings on bodies; ammo pouches on
   corpses (an [E] on a body: the hand reaches in — ties the gore to the loop; a body is worth
   looting). This ends "spare ammunition is unlimited".
5. **Weapon presence.** Inspect, a holster on sprint, a tactical reload path, the gun lowered near
   walls (clip-avoid), the rifle's bolt kept visible in the frame, a scope for the SMLE (the sniper
   event has one). Dual-wield is TNC's — it would be a fun late upgrade for the revolvers.

### C. Active ragdoll while alive (the bodies' next step)
1. **Partial physics on hits.** A shot limb goes to physics for 0.3–0.6 s with muscle tone from the
   existing curves and blends back to the animated pose — an arm thrown by a pistol round, a leg
   buckled by a rifle round with a recovery stumble driven by the support spring. `ClownRagdoll`
   already has per-bone tone; what is missing is a *return path* (physics → animation) per bone.
2. **Full knock-down and get-up.** A shotgun blast to the chest, a shell's push, a melee strike:
   the whole body ragdolls for 0.5–1 s, then a get-up — match a Mixamo get-up clip's first frame to
   the ragdoll's resting pose (prone/supine, the retarget pipeline in `tools/anim_ref/` takes new
   clips) and drive the bones back under tone. This is the feature that makes TNC enemies feel
   alive, and the game's custom ragdoll makes it feasible where Godot's stock one would not.
3. **Hung on the wire.** A man shot while crossing the wire stays on it: pin the nearest wrist/
   chest bone to the wire with a joint (the stake gun's pin, reused), let the rest hang and sway.
   BF1's single most iconic silhouette, and every system for it exists.
4. **Bodies that interact.** Ragdoll–ragdoll collision in piles (they stack in doorways), the
   player can shove a corpse off a duckboard or **drag one** (hold E), bodies slide down the shell
   hole's slope into the water (buoyancy on the chest bone: a floating dead man in a flooded crater),
   a body on a stairwell tumbles (already counted — make it ride the rail).
5. **Wounded behaviours.** Beyond crawl/last stand: a man clutching an arm who keeps fighting one-
   handed with the pistol, a gut-shot man sitting against the wall, a blinded man (head grazed)
   firing wild. Each is an animated state on the existing injury flags.

### D. Graphics — the cinematic layer
1. **Colour grade per space.** A 3D LUT via `Environment.adjustment_color_correction`: BF1's
   drained teal-grey with warm fire; the bunker's sodium amber with a green cast in the deep rooms;
   dawn and night their own. Ten minutes per LUT in a paint program; the largest look change left
   for the smallest effort.
2. **Air in the bunkers.** Turn volumetric fog on indoors at low density with a few *shadowed
   spotlights* (caged bulbs as spot cones through a dusty room, a shaft from a shell hole in the
   roof), dust motes as a cheap GPUParticles volume near the player, a brief dust fall from the
   ceiling when a shell lands overhead (the Front's artillery can keep firing while you are
   underground — the bunker shakes, dust drops, bulbs swing). This is Wolfenstein's corridor.
3. **Muzzle flashes that light the smoke.** The flash light exists (`muzzle_flash.gd`); add a
   lingering smoke cloud per shot that the flash and the lanterns illuminate (volumetric-fog
   contribution from the muzzle light, `light_volumetric_fog_energy`).
4. **Shells that move the earth.** Taller dirt columns with a debris rain phase, a lingering low
   smoke that drifts with the wind, a crater decal that *stays* (the decal budget now allows it),
   clods landing on the water with rings (ripples exist). Scorch and churn layers in
   `mud_terrain.gdshader` painted by the explosions (a small world mask — the one the blood plan
   parked, but shells are rarer than hits and justify it).
5. **Breakables.** Lanterns (they fall and the glass bursts, the flame goes out — and the room
   goes dark), bottles and cups on the mess table, crates that splinter, sandbags that split and
   pour. Each a small scene; the surface-impact system already decides the material.
6. **Weather.** Rain on the Front as a sixth variant: streaks, drops on water, wet-darkened mud,
   lens drops; a wind that drives the smoke banks and the wire's sway (`wire_sway`, `cloth_wind`
   shaders already take a wind).
7. **Animation fidelity.** More Mixamo clips through the existing retarget: reloads for the
   riflemen (they currently re-chamber by code), hit reactions as blend-in motions, get-ups,
   vaults over the parapet, idles with weight shifts. The upper body is where the eye still reads
   "procedural".
8. **Depth of field and the frame.** DOF on ADS (near blur of the rifle), on the kill cam, and
   a soft far DOF at dawn; vignette; film grain under the grade. Godot 4 has no object motion blur
   — a light screen-space camera blur shader on fast turns is the honest substitute.
9. **Silhouettes.** The BF1 frame is a man against a glow: make sure a flare, a brazier or a burning
   wreck is *behind* the enemy's expected positions (the lantern placer knows the trench; the
   director knows the sectors).

### E. Setting and authorship
1. **Vignette rooms in the bunkers.** A library of hand-arranged prefab rooms the generator drops
   into dead ends and halls with a reason each: a field dressing station (cots, a surgeon clown,
   bloody linen), a flooded lower gallery (knee-deep wading, bodies afloat), a boiler room (steam
   jets as hazard), a signals room (the field telephone ringing), a kennel, a shrine to the circus
   (mirrors, a carousel horse), a gas store (masks, cylinders). Wolfenstein's rooms are dioramas
   with a violent way in; each prefab should offer one — a shootable lock, a breachable door, a vent.
2. **Verticality in the corridors.** Upper galleries and catwalks with riflemen firing down,
   ladders, a shaft to drop through, a collapsed floor into the room below. Stairwells exist; the
   bunker needs a second storey.
3. **Gas.** A hazard both references share: a gas shell lands, a green-yellow bank rolls through
   the trench or a bunker section; a mask pickup, lens fog and breath when worn, enemies caught in
   it choking (another injury behaviour). The volumetric fog can carry a tinted local volume.
4. **Going over the top with company.** A scripted friendly line (conscript clowns in our colours)
   that climbs the ramps beside you at a whistle, runs into the MGs and dies on the wire and in the
   holes — no need for clever AI; a charge, a fall, a body. The field is a graveyard you made on
   the way across, and the silhouettes beside you are what BF1 is. Later: a squad that stays with
   you and takes orders (hold / go).
5. **Set-pieces that arrive.** A creeping barrage that walks across the field toward our line as
   you cross (the artillery system can be given a line and a pace); a mine going up under the
   enemy's parapet as a variant's opening; a biplane strafing run as a far event; a derelict tank
   in the field as a landmark you can get inside; an observation balloon (the shader exists) that
   burns and falls. One per crossing, chosen by the seed, each a landmark in the player's memory.
6. **Landmarks.** A ruined church spire, a sunken road, a crater lake with a wreck in it, a
   half-buried gun, a crucifix calvary at a crossroads. The field is uniform now; three fixed
   features per seed give it a map in the mind.
7. **The circus as the horror that leaks through.** The game's own voice. Deeper floors should
   get stranger: calliope through the pipes, bunting in a dugout, a ring in a crater with seats,
   an audience of corpses. BF1 has no equivalent; this is what makes it *this* game.

### F. Gameplay loop depth
1. **Upgrades that touch the systems.** Replace half the numeric upgrades with ones the gore
   and physics answer: dum-dum rounds (bigger exit wounds, more bleed), ricochet, a heavier club,
   a bayonet charge, incendiary pellets, "Trench Broom" (pump faster), "Second Wind", a gas mask.
   Weapon mods as a separate pick (scope, drum, sawn-off, bayonet).
2. **Objectives beyond two.** Hold the line (waves over the parapet, the BF1 Operations feel,
   with the friendly line from E4), take the gun (silence the MG nest), clear the dugouts, escort
   (a runner with a message), breach the H.Q. as a boss floor (the Zornhauptmann's arena).
3. **Mid-floor choices.** Locked rooms that cost health or tickets, a cursed artefact, a shrine
   trade, an ammo cache behind a gassed corridor.
4. **The run as a map.** Sectors of the front chosen on the map table (already drawn) with
   modifiers — night, barrage, MG-heavy — so the variants become the player's choice, not only
   the seed's.
5. **Enemy roster.** A flamethrower clown (fire as a gore state, bodies burning), a stormtrooper
   with grenade bundles who rushes, a sniper on the far parapet (the event rifle exists), an
   officer with a whistle who rallies (kill him and the line breaks), a gas-mask engineer.

### G. Polish and UX
Options (FOV, sensitivity, key binds), controller, a weapon wheel, hit-marker sound and kill
confirm, a diegetic HUD (ammo on the gun, health as the lens), a death screen with the
Brutality Report (exists) over the kill-cam frame, loading between floors hidden by a dugout
descent.

---

## 4. The order I would build it in

Each a milestone of the kind used for the Front (plan → build → tests → look renders → Andrew's eye),
and each stands alone if the next is never built.

1. **Sound foundation** (A1–A4): buses, reverb zones, real gun layers, the far-war bed, the
   player's body. One week; the game feels twice as expensive at the end of it.
2. **The player's body** (B1–B4): slide, lean, mantle, melee + bayonet, directional damage,
   health/armour/ammo from the world (looting bodies). Two weeks.
3. **Living ragdoll** (C1–C3): partial physics hits, knock-down and get-up, hung on the wire.
   Two to three weeks; builds on the strongest system in the game.
4. **Bunker light and air** (D1–D3, D5): LUTs, volumetric shafts and dust, shadowed key lights,
   lanterns that break and darken the room. One week. Then **enemy voices** (A5).
5. **Company and set-pieces on the Front** (E4, E5, D4): the friendly charge, the creeping barrage,
   shells that leave the ground changed. Two weeks.
6. **Vignette rooms** (E1–E2) and **gas** (E3). Ongoing; one prefab at a time.
7. **Loop depth** (F1–F3) and **music** (A6) once the senses are in — the loop is tuned against the
   game that exists then.

---

## 5. Costs and risks, said plainly

- **Content, not code, is the bottleneck for sound.** Libraries will carry the first pass; a
  shipped game wants a sound designer or a careful month of editing.
- **Godot 4.7 limits.** No per-object motion blur; SDFGI and volumetrics cost on the M2 (the
  Graphics page exists to trade them); physics ragdoll–animation blending is hand-rolled (an asset
  here — the ragdoll is already custom — but the get-up is a real piece of engineering).
- **Procedural + authored is a design job.** Prefab rooms must sit in the generator's grammar
  (doorways, cell sizes, exits) — a rule set first, then the rooms.
- **Friendly bodies double the ragdoll count** on a crossing. Phase C of the blood plan and the
  M12 sim tiers already budget per body; the charge would need its own cap (eight men, sim tier 2).
- **Scope.** Everything above is a year of a studio's time. The ordering is the point: sound and
  the player's body are the two cheapest, biggest steps and nothing else depends on them.

---

## 6. What this does not change

The gore, the ragdoll deaths, the Front's director, the blood overhaul (Phases C, D-drips, F still
to do) and the legacy trench implementation stay as they are; every milestone above is additive and
tested like the last thirteen.
