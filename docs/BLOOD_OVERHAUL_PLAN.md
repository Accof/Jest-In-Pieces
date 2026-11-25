# Blood overhaul — the plan (24 Nov 2026, draft for Andrew's review)

Andrew: "im still not happy about the blood in this game. it still doesn't look or behave exactly how
i like … the wall blood splats disappear too quickly and do not look good at all. They should be
more like actual splats with fine particles … there is not really any blood spray when an enemy is
hit." Five reference images supplied (below). This document is the audit of what the game does
now, what DieselFrag did, what the games he named do, and a phased plan against his references.
Nothing here is built yet; the phases are for his authorisation one at a time, each with a render
to judge before the next.

---

## 1. What the game does today (audit of `scripts/blood/`, `clown_gore.gd`, `art/blood/`)

**The pipeline on a hit** (`Clown.hit` → `Blood.spawn_hit(pos, dir, amount)`):
1. `_burst`: one of six pooled GPUParticles3D fires **48 soft round blobs** (5 cm, dark
   `(0.2, 0.01, 0.012)`, alpha fade, 0.55 s). That is the whole "spray". It is small, dark, brief,
   has no direction to speak of (32° spread), and no liquid look. On a dim trench floor it reads as
   a puff of dust.
2. **Exit rays:** 2–10 rays in a 0.42 cone behind the target, 2.4–4.6 m. Each hit places ONE decal
   of 0.2–0.5 m (shrunk with distance) — `impact` if ≥ 0.3 m, `spray`/`small` otherwise, `streak`
   when glancing.
3. **Back spatter:** 1–3 rays toward the shooter, 8–20 cm `drip` decals.
4. **Droplets:** 3–17 simulated drops arc away and place a `drip` decal where they land. **They are
   never drawn while flying** — `_drop_pos/_drop_vel` are simulated and raycast, but no mesh exists
   for them. Nothing is seen leaving the body.
5. Pools (`BloodPool`, geometry-aware, shader growth) under bleeding corpses; wounds on the body
   (`clown_body.gdshader` wound list); bleeding spurts feed droplets. These parts are good and stay.

**The textures** (`tools/gen_blood_splatters.py` → `art/blood/splat/`, 26 variants in six kinds,
512², colour + normal + ORM): procedural — a solid dark blob with radial spikes and a few dots
(contact sheet made today, `/tmp/splat_sheet.png`). They look like paintballs. None has the
thousands of fine specks of a real spatter; none has a drip running from it; the "spray" kind is a
fan of a dozen teardrops.

**Why "they disappear too quickly":** `MAX_DECALS = 320` is a ring buffer with **no fade** — the
oldest decal is simply reused. One kill spends roughly 15–30 decals (exit rays + back spatter + each
droplet's landing). After ten or a dozen kills the first kill's splatters pop out of existence one
by one, and the ring is churning constantly in a fire-fight. There is also `distance_fade_begin = 30`
(reasonable) and a decal depth of 0.3 m, which clips on the battered, noisy trench walls (part of a
splat sinks into the mound; the rest hangs in the air of a slump).

**Render check today** (`scenes/look_blood.tscn`, `/tmp/look_blood_now_*.png`): wall hits are
three dark round blobs 20 cm across with spikes; floor sprays the same at a slant. Nothing of the
references.

## 2. What DieselFrag did (Unity, `~/Dieselfrag`, read today)

Also procedural textures (`Tools/gen_blood_textures.py`) but a different philosophy, arrived at
through six documented failures (its `CLAUDE.md` "Blood" section is worth reading again): **one
dense 1024² impact texture with 700–1100 droplets baked in on a power-law size distribution**
(many dust-sized, few medium), placed at 0.5–0.85 m, with 3–8 individually raycast outlier
droplets, 2–5 wall-spray rays in a 25° cone to 4 m and 2–5 floor-drip rays in an 18° cone down —
pool of 400 decals, world-fixed (never parented to bones). Its lessons that apply here:
- Density belongs in the texture, footprint stays modest; the two must move independently.
- Any decal placed at an offset must re-raycast from that offset.
- Blood marks are paint fixed in the world the instant they are placed.
- Hundreds of individual decals per hit is not a runtime option; hundreds of droplets in one
  texture is.
Its textures are better than ours for the speck distribution (contact sheet `/tmp/df_sheet.png`),
still round-blob droplets and still no drips or mist halo. Andrew's "better there" is the density.

## 3. What Wolfenstein / The Last of Us / Killing Floor 2 do (the general recipe)

From the public talks and breakdowns (Naughty Dog's "Surface Tension: liquid effects in The Last of
Us", the TLOU2 GPU-effects talk, Tripwire on KF2's gore, Unreal's "Let Them Come" blood write-up):
1. **The spray is the hero, and it is liquid.** High-count GPU particles with a *liquid* shader
   (specular, a little refraction, surface-tension look), drawn as stretched sprites along their
   velocity — strings and ropes of blood, not round dots — from flipbook sheets rendered off a fluid
   sim. Two populations: a fast directional **plume** out the exit (0.3–0.5 s) and a slow fine
   **mist** that hangs (1–2 s) and drifts. Headshots add chunks.
2. **Particles that hit something leave the mark.** The wall splatter is born from the spray:
   each landing droplet stamps a decal sized and stretched by its speed and angle; the big
   "splat" is where the plume's core hit. That is why their marks always match the spray you just
   saw, and why the shape changes with the angle of the shot.
3. **Layered decals, not one texture:** a big soft mist cloud (thousands of specks, low alpha),
   medium droplets with tails pointing away from the origin, a few heavy drops, and **drips that
   animate** — a mask that scrolls down over a few seconds so fresh blood runs on vertical surfaces
   before it dries. Micro-detail decals are laid over the big shape to keep resolution without a
   huge texture.
4. **Marks persist.** Budgets are large, and the long-lived answer is painting into a world-space
   mask (a "gore mask" render target the surface shaders sample) so blood on the floor never pops.
5. **Blood on bodies and the player:** UV-space masks on characters (TLOU2 assigns render targets
   per character), screen/lens blood at close range.
6. **Pools** follow the floor and grow — the one thing we already have at that level.

## 4. The references, read

| # | Image | What it is | Where it belongs in the game |
|---|---|---|---|
| 1 | heavy central splat, fine mist halo, long drips running down | a mass of blood hitting a vertical surface at speed, then gravity | the exit mark on a wall behind a close headshot or a shotgun chest hit; drips animate down |
| 2 | sweeping arc of droplets, thinning along the arc, no centre | **cast-off**: blood flung from a moving bloody object (a swung club, a thrown limb, a turning man) | the trench club's follow-through and the cast of a severed limb; the Rattlejack's swings |
| 3 | a cloud of thousands of fine specks, a few larger, directional, no mass | **high-velocity mist** — a gunshot's forward spatter | the standard rifle/pistol exit mark on whatever is behind the man, 1–3 m |
| 4 | impact burst with tails outward and a few drips | medium-velocity impact spatter with gravity | a body shot at an angle; wall splat from a blunt hit |
| 5 | many separate drops each with a vertical run | drops falling on a wall from above and running | the wall beside a man bleeding out standing or slumped against it; above a pool |

Three physical regimes drive the shapes and the game should distinguish them:
**gunshot** (fine mist, forward cone 10–20° tightening with velocity, a smaller back spatter toward
the shooter), **blunt/cast-off** (medium drops, arcs, tails), **arterial/volume** (spurts, heavy
masses, drips, pools).

## 5. The plan, in phases (each one authorised separately; renders before the next)

### Phase A — Textures: a splatter library that looks like the references
Generate (procedurally, physically motivated — no stock imagery; his references are the targets,
not sources) at 1024², colour + normal + ORM (wet specular), with alpha carrying the fine stuff:
- **mist** ×6: 3,000–8,000 specks on a power law (α ≈ 2.2), directional fan (the texture's up is
  the travel direction), density falling off from an off-centre origin, a few 2–5 mm drops; no
  solid mass. (ref 3)
- **impact** ×6: a soft irregular centre (not a disc — Gaussian-noise edge), a halo of specks with
  **tails pointing away from the centre** (elongation ∝ distance), 2–5 drips of random length with
  a bead at the end. (refs 1, 4)
- **cast-off** ×4: an arc of drops thinning along it, each elongated along the arc. (ref 2)
- **drip field** ×4: 20–60 drops with vertical runs of varied length, thin tails, beads. (ref 5)
- **heavy** ×4: ref 1's mass for the big hits (the "death" kind today), with a run-down band.
- **streak** ×4: glancing smears (keep, redo at the new quality), and **small** droplets ×8 (a
  single drop, a single elongated drop, a single drop with a tail) for the per-droplet landings.
- A **drip mask** texture for the animated runs (Phase D).
Colour: fresh arterial on the surface (`0.42, 0.02, 0.02` ± hue noise, thick centres darker), the
existing drying to brown over `DRY_TIME` kept; ORM makes fresh blood glossy and dried matt.
Deliverable: a contact sheet beside the five references, then the `look_blood` room.

### Phase B — Placement by physics, not by ray count
Replace the "N rays, one small decal each" with the three regimes:
- **Gunshot:** the forward cone's centre line is raycast; where it lands, ONE mist decal of 0.6–1.4 m
  (size by distance and the hit's `amount`), elongated along the travel's projection on the surface
  (incidence angle → stretch 1.0–2.5, the fan's wide end away from the shooter); at close range or
  high `amount` an **impact** decal on top (the mass), and 4–10 small droplet decals re-raycast
  from offsets. Back spatter: a small mist toward the shooter, 20–40 cm. Headshots (revolver, the
  one he loves): impact + mist + a heavy drip run; shotgun: wide fan, two overlapping mists.
- **Blunt / cast-off:** the club's follow-through and a severed limb's flight cast an **arc** decal
  on the surface the swing faces (one ray along the swing's tangent), tails along the arc.
- **Volume:** bleeding out against a wall → drip field decals climbing the wall over time; pools as now.
Glancing hits keep the streak. Every decal keeps the DieselFrag rule: re-raycast from its own
offset; world-fixed. Decal depth 0.3 → 0.12 m with `normal_fade` tuned so splats hug the battered
walls instead of sinking in.

### Phase C — Spray you can see
- **Plume:** a GPUParticles3D per hit (pooled, 8) with 120–200 particles, lifetime 0.35–0.5 s,
  velocity 4–9 m/s in a 12° cone along `dir`, gravity on, drawn as **velocity-stretched sprites**
  (`BILLBOARD_PARTICLES` with `particles_anim` or a custom stretch in the shader) from a liquid
  sprite sheet (procedural: strings, ropes, drop clusters — 4×4), a **liquid shader** (specular
  lobe, fresnel rim, a little screen-space refraction via `SCREEN_TEXTURE`, deep red to bright at
  thin edges). Amount-scaled.
- **Mist:** a second, finer population (0.5–1.2 mm sprites rendered as a soft cloud texture),
  200–400 particles, slow (1–2 m/s), lifetime 1.0–1.6 s, drifting with a touch of turbulence,
  alpha low — the red haze that hangs after a headshot.
- **Droplets drawn:** the existing CPU droplet sim gets a MultiMesh of stretched liquid quads
  (`_drop_*` arrays already have position and velocity) and a bigger budget (160 → 400): the
  heavy drops are *seen* arcing to the floor and landing where their decal appears. **Particles
  leave marks:** this sim is our "collision → decal" path; the plume's own landing is approximated
  by the Phase B centre ray (GPU particles cannot report collisions in Godot), with 6–12 of the
  plume's drops mirrored into the CPU sim so a few visibly land and stamp.
- **Arterial:** neck/throat and severed stumps emit a pulsing stream (existing spurts → the drawn
  droplets, with a short string sprite), at the heartbeat rate already in `clown_gore`.
- Chunks on headshots: the existing meat bits, plus a few drawn droplets trailing them.

### Phase D — Persistence and drips
- `MAX_DECALS` 320 → **1,200** (Forward+ clustered decals are cheap; the per-view cluster limit is
  512 elements — decals in the frustum plus lights — so the budget is enforced by **distance fade at
  40 m** and by never having more than ~300 within 40 m: recycle far ones first, small ones first).
- **No pops:** a recycled decal fades over 2 s (`modulate.a`), and recycling prefers decals the
  player cannot see (behind, beyond fade) — a kill's marks last the whole floor in practice.
- **Drips that run:** a decal kind whose shader scrolls a drip mask downward over 3–8 s from heavy
  wall hits (impact/heavy kinds on surfaces with |normal.y| < 0.5), beads at the ends, then stops
  and dries. Handful per floor at a time (an array of 24 "live" drips ticked in `_process`).
- Later, if the budget still bites: a per-floor **world blood mask** (a 2K RGBA painted by the
  decal placements, sampled by `mud_terrain.gdshader` and the wall shaders) — permanent, unlimited,
  but a larger job (every lining and the heightfield need world-UV sampling). Proposed only if
  1,200 fading decals are not enough.

### Phase E — Bodies, weapons, the player
- Blood soaking into uniforms around wounds already exists (wound shader); add **spatter on the
  man next to the one you shot** (the mist cone intersects other bodies: a wound-list entry with no
  depth, i.e. a surface stain) and on the **player's weapon and hands** at close range (view-model
  stain mask that fades), and a brief **lens spatter** for point-blank headshots (two or three
  specks that slide, 1.5 s) — subtle, off by default if he dislikes it.
- Cast-off from the trench club: the club's own blood level (stains after a hit) and an arc on the
  wall of the follow-through.

### Phase F — Judging it
`look_blood.tscn` rebuilt to reproduce the five references: the same shot types on the same wall,
captured at the same framing, next to the reference. A `test_blood` headless suite: counts per hit
by regime, the budget (never over the cluster limit in view), decals re-raycast (none floating),
drips only on near-vertical surfaces, pools unchanged. Performance on the M2: a 30-kill fight at
0.75 FSR stays at 60 (decal count and particle count printed by F3).

## 6. Order and effort
A (textures) and B (placement) first — they are what he sees on every wall and need no new
runtime system: 1 session. C (spray) next: the plume/mist/liquid shader and the drawn droplets:
1 session. D (persistence/drips): half a session. E and the world mask: on his word after seeing
A–D. Each phase ends with renders in the look room and the real game at night and day.

## 7. Andrew's answers (24 Nov, 18:30)
1. **Amount:** generous, like the references — roughly 2–3× today; a rifle chest hit leaves a ~1 m
   mist on the wall behind, a headshot about twice that.
2. **Colour:** fresh arterial red on impact, drying to brown over about a minute (the TLOU look).
3. **Extras:** animated drips — yes. Lens spatter, blood on the player's weapon and hands, and
   spatter on the man standing beside the one you shot — not for now (Phase E parked).
4. **Persistence:** fading decals first (Phase D, 1,200 with fades); the world blood mask only if a
   30-kill fight shows the budget still bites.
5. More references of spray in the air still welcome.

Phase A starts on his word.

## 8. Phase A — done 24 Nov (commit below), awaiting his eye
`tools/gen_blood_splatters_v2.py` → `art/blood/splat2/` (36 textures: mist ×6, impact ×6, castoff
×4, dripfield ×4, heavy ×4, streak ×4, small ×8; 1024 colour + 512 normal/ORM, BC7; plus
`drip_mask.png` for Phase D). Built as thickness fields at 2048: specks on a power-law size spread
flung in fans with tails pointing back at the origin, torn masses, splash fingers, drips with beads
and a slow wander, a translucent haze round every mass, dragged streaks; coloured by thickness (thin
edges bright arterial, thick centres dark), box-filtered to 1024. Three passes against the five
references (`blood_phaseA_vs_references.png`). Wired into `BloodManager` (`splat_version = 2`,
`SPLAT2_MAP` for the old kind names, `SPLAT2_FILL` so a size in metres is the shape's size, drips
hang downward on walls, oil by modulate). The look room renders with it; pools/death/blast suites
unchanged. Sizes and placement are still the old ones — that is Phase B.

Andrew's first in-game look (18:53): "the drops are too big, wrong colour, too bright" — the droplet
landings had come out ~1.7× their old size (the fill factor), the thin-edge colour was pink, and the
wet gloss so low in roughness that a thick mass under a lamp went pale with its own highlight. Fixed
in the same phase: landings halved, the palette darkened throughout (thin edges deep red, centres
near-black), drops opaque, roughness floor 0.47, normal bumps halved, the mist haze fainter.

## 9. Phase B — done 24 Nov, awaiting his eye
`Blood.spawn_hit(pos, dir, amount, oil, zone, weapon, shot_id)` (the clown passes zone "head",
the weapon's name and the shot id) now places by regime in the v2 path (`_place_gunshot`):
- **Gunshot:** the cone's centre ray (3° jitter) to 2.6 + 3·amount m; ONE mist where it lands,
  `0.42 + 0.35·amount + 0.2·distance` m (0.45–1.7; ×1.25 for a headshot, ×1.6 for a shotgun's
  charge), stretched `1 + 1.6·(1 − |cos incidence|)` along the travel's projection, the fan's wide
  end away from the shooter; a graze (incidence under 27°) draws a dragged streak under it. The mass
  on top: a headshot within 2.6 m gets a **heavy** (0.5–0.95 m, drips hanging down the wall); a hard
  or close body hit an **impact**. 4–9 small drops re-raycast inside the fan; back spatter toward the
  shooter (a 0.22–0.4 m mist and 1–3 drops); 2–4 drops straight down to the floor. A shotgun's
  pellets share the one mark (the first pellet places it; the rest add a drop or two).
- **Cast-off:** `Blood.cast_off(pos, vel, amount)` — a ring of rays round the motion finds the
  nearest surface within 1.4 m and lays an arc (0.8–1.7 m) with its tangent along the motion. Fired
  by a severed part's first fast knock against the world (`Gib`, contact monitoring on).
- **Volume:** `Blood.drip_field(pos, normal, size)` — a man who bled out within 0.55 m of a wall
  leaves the drops that ran down it (0.8–1.2 m), once per bleed, when his pool starts
  (`ClownGore`).
- Decal depth is now by size (0.12–0.4 m) so a splat hugs a battered wall instead of sinking in.
The library's thin colour was darkened a second time (linear 0.21 red: real blood's albedo; the
0.40 of the first fix still read salmon under a lamp), the mist got 50–110 mid-size drops and torn
splotches so it has structure at a metre, the drip field bolder drops.
Tests: `test_blood` (new, 15 checks: one mist a rifle hit of the right size, no mass; a heavy on a
headshot, flat on the wall; eight pellets one fan; a graze streaks; cast-off arcs only within reach;
drip fields; nothing floats; depths), 0 failed. Pools/death/blast/limbs/throat suites as baseline
(`test_pools` is flaky on its own: 1–2 different physics checks fail run to run, also with every
Phase B change reverted). `look_blood.tscn -- --regimes [--dim]` renders the six regimes on the wall.
Found by experiment (`BLOOD_FLAT=1`, albedo-only decals beside the full ones): the pale, washed
masses under a lamp were the decal's ORM/normal maps — a wet roughness turned the light into a broad
highlight across every thick mass. v2 decals now carry no ORM (the surface keeps its own roughness)
and a half-strength normal; the masses are dark red under the harshest light in the room. The wet
sheen can come back under control in Phase D if wanted.

## 10. Phase D (persistence half) — done 24 Nov, pulled forward
Andrew, after Phase B in game: "the wall and floor blood splats disappear or cull way too quickly
still." Cause: the 320-slot ring with no fade — Phase B spends 15–30 decals a hit (a shotgun fight
wrapped the ring in a few shots) and the first kill's marks popped out one at a time.
Done (`blood_manager.gd`): `MAX_DECALS` 320 → **1,200**; when the ring is full the slot is taken
from the next 40 by lowest priority — **small before big, farther than 25 m from the camera before
near** — so the splat in front of you goes last; the mark a slot held is handed to one of **48 spare
decals** that fades `modulate.a` over 2.5 s (`FADE_OUT`) so nothing pops; `clear()` on a new floor
returns the spares. `project.godot`: `rendering/limits/cluster_builder/max_clustered_elements`
512 → **1,024** (Forward+ per-view budget: decals in the frustum plus lights; the 30 m distance fade
keeps a fight's marks under it) — committed as its own minimal hunk so his Main Run Args stay local.
Tests: `test_blood` +5 (a 1.2 m mist placed first survives 1,300 small drops after it; ~100 small
drops recycled for them; the recycled marks fade on spares; the pool stays full; fades finish and the
spares return) — 20 checks, 0 failed. `test_pools` 0 failed. The drips-that-run half of Phase D
(the `drip_mask.png` scroll) is still to do, with Phase C.

## 11. Phase C — spray you can see — done 25 Nov, awaiting his eye
The old spray was 48 dark dots of 5 cm that died in half a second. Now a hit fires three things:
- **The plume** (`_make_plume`): 220 strings and drops of liquid thrown along the round in a 12°
  cone at 4–9 m/s under gravity, each aligned to its own velocity and drawn as a cylindrical
  billboard (its travel axis stays, its face turns to the camera) from a 4×4 liquid sheet
  (`art/blood/fx_liquid_sheet.png`, `tools/gen_blood_spray_sprites.py`: teardrops and clusters,
  ropes with beads). `shaders/blood_liquid.gdshader` colours by the sheet's thickness — bright red
  where thin, dark only in the beads — with a specular lobe, a wet rim, backlight (light from
  behind comes through) and a small emission floor so it never goes black in a dark corner. GPU
  particles cannot collide here, so the plume's life is cut by a ray along the round: the strings
  die as they reach the wall where Phase B's marks already are; into open air they live 0.45 s.
- **The haze** (`_make_haze`): 160 soft puffs at 0.8–3 m/s that stop within a few tens of
  centimetres and hang for 1.4 s, growing and thinning, a little turbulence, alpha 0.11 — the
  red mist that hangs after a headshot. First try was a brown blob (alpha 0.34, 16 cm puffs):
  it hid the marks behind it.
- **The droplets drawn** (`_draw_drops`): the CPU droplet sim (now 400, was 160) is drawn as a
  MultiMesh of liquid quads, Y along each drop's travel, longer the faster it goes — a falling
  drop is a drop, a spurt is a string — in the same shader. These are the "collision → decal"
  path: the heavy drops are seen arcing to the floor and landing where their mark appears, and
  3–7 of each hit's droplets now fly *with* the plume (4–9 m/s) so some of its strings land and
  stamp for real. The arterial spurts (`clown_gore` `_spurts`, the throat's heartbeat) were
  already droplets + mist: they are visible streams now, nothing changed on their side.
- Pools: 8 plumes + 3 oil, 6 hazes + 2 oil (layer 2, no shadows, 12 m visibility boxes).
  `BLOOD_NO_SPRAY=1` turns the drawing off (the marks stay). Not done from the plan: screen-space
  refraction in the liquid shader (cost for little at these sizes).
Tests: `test_blood` +7 (a hit fires one plume; it lives only to the wall 1.3 m behind, 0.19 s;
into open air its full 0.45 s; the haze hangs over a second; the droplets are drawn one quad each
and the draw is empty once they have landed; some fly with the plume) — 27 checks, 0 failed.
`test_pools` 0; `test_throat` the baseline 2. Look: `look_blood.tscn -- --spray --tag=X` with
`--fixed-fps 30` (frames are moments: 0.07, 0.17, 0.3, 0.8 s side-on, a headshot over the
shoulder, an arterial stream); `docs/reference/blood_phase_c/` holds the frames.

## 12. After his test of Phase C (25 Nov) — hit tiers
Andrew: "a bit too much spray occurring all the time on every single shot … not on every single
shot to other areas of the body … too many decals being painted at one time against a wall …
the distance it sprays to seems to be way too far. I shot a guy and it sprayed on a wall on the
other side of the room." One root: `_place_gunshot` and the plume treated every hit as a head
wound, with a reach of 2.6 + 3 × amount m (5.6 m for a rifle, whose amount is the 1.6 cap) and a
mark that *grew* with distance; and every pellet of a shotgun fired its own plume and haze.
Now a hit is a **tier**, by where it landed before how hard (`hit_tier`, `TIER_REACH`):
- **head** — zone "head", or the gore module's own big events (a severing, a stump, a skull
  opening: amount ≥ 1.3 with no weapon named): the plume at 4–9 m/s, the haze, the full set of
  marks (mist 0.6–1.3 m + heavy + 5–11 drops + back mist + floor), **2.6 m reach**.
- **body** — the torso: plume 2.5–5 m/s for 0.32 s, a faint puff (haze ratio 0.16), one mist
  0.3–0.7 m + 3 drops + 1 back drop + 2 floor drops = **at most 10 decals**, **1.6 m reach**; a
  wall farther than that gets nothing, the drops arc to the floor.
- **limb** — arms, legs, hands, feet (`clown.gd` now passes "limb"): plume 2–4 m/s, a few
  strings, no haze; a 0.22–0.4 m mist + 2 drops + 1 floor, 1.2 m reach.
- Marks thin with distance (×0.7 by 2.6 m) instead of growing. A shotgun's pellets share **one
  spray and one mark per shot** (2.2 m reach); the 5th pellet on one body is a close charge and
  adds the impact mass. The impact mass otherwise only within 0.9 m at amount ≥ 1.2.
Tests: `test_blood` 35 checks, 0 failed (body shot 2.4 m from a wall marks nothing on it; the same
shot to the head reaches it with the heavy; a limb hit ≤ 6 decals; six pellets one spray; a limb
hit no haze; a body plume slow and sparse). `test_pools` 0. Look: `wall_regimes_tiered.png`.

## 13. His second test (25 Nov) — chance, and one coherent mark
Andrew: "still too much spurt in general from the body and limbs. Also it shouldn't happen all
the time. Too many different incoherent decals painting the same area and cause a mess."
- **It does not always happen.** A torso hit throws blood only when the round goes through
  (amount ≥ 0.9: rifle, revolver, Maxim, a shotgun charge) and then 7 times in 10 for the mark,
  5 in 10 for the small plume (`BODY_MARK_CHANCE`, `BODY_PLUME_CHANCE`); pistol, SMG and single
  pellets stay in the body and throw nothing on the wall. A limb: 4 in 10 a mark, 3 in 10 a plume.
  The body plume is also thinner (ratio 0.12–0.25) and has **no haze**; a limb's ratio 0.08.
- **One mark.** A body or limb hit on a wall is its one mist and nothing else on that wall — no
  fan of small drops over it, no back spatter, no streak for a limb; one or two drops fall to the
  floor and, new, the drops it throws are **floor-only** (`add_droplet(..., floor_only)`): they
  stamp where they land on a floor, never on the wall over the mist. A headshot's small drops are
  placed in a **ring** round the mark (0.3–0.55 rad off the axis), outside the mist, not on it.
- **Bodies hitting walls.** `clown_gore._impacts` (a bleeding ragdoll striking a surface at speed,
  every 0.18 s per bone) placed an impact AND a streak AND a head-tier `spawn_hit` (mist, heavy,
  ring, back spatter, plume, haze) on the same spot — the mess in a corner after a shotgun kill.
  Now one mark (the streak if it slid, else the impact, sized by speed, from 4 m/s not 3) and
  `spawn_hit(..., "splash")`: no mark of its own, a small plume half the time, two floor drops.
Tests: `test_blood` 43 checks, 0 failed, three runs (40 pistol body hits: nothing on the wall, no
plume; 100 rifle body hits ≈ 70 mists, ≈ 50 plumes; 100 limb hits ≈ 40 marks; a body hit is one
wall mark before and after its drops land; a splash adds no mark). `test_impacts` 0, `test_pools` 0.

## 14. His third test (25 Nov) — "still a bit extreme in places and unrealistic": marks, drops, pools
A size pass, everything smaller: a headshot's mist 0.5–0.9 m (was 0.6–1.3), its heavy 0.4–0.7
(was 0.5–0.95), the impact mass 0.25–0.55, a shotgun charge's fan ×1.3 capped at 1.0 m (was ×1.4,
1.3); the body mist 0.3–0.6; the "small" drops 3–7 cm × (1 + 0.2 amount) (were up to 15 cm, which is
not small); the floor drops 3–8 cm. The CPU droplets are drawn at 0.3 × their size (1.5–4 cm wide,
were golf balls at 0.6 ×) and stamp at 1.2 × (5–14 cm landings, were 2.2 ×). A gib's cast-off arc is
0.5–0.8 m, a tumbling body's up to 1.1 (were 0.8–1.7). The drip field beside a pooling body
0.6–0.9 m (was 1.0–1.4). Pools cap at 0.5 m radius (was 0.6). `test_blood` 43, 0 failed; `test_pools`
0. Look: `wall_regimes_restrained.png`.

## 15. His fourth test (25 Nov) — "still way too many spurts too often … revolver … body shots
cause spurts most of the time … I don't see any difference" — the probe
He was right and the tuning was on the wrong path. A new probe, `scenes/probe_blood_sources.tscn`
(`scripts/dev/probe_blood_sources.gd`), shoots the sandbox clowns in the chest with the revolver
and logs **every plume with the code that fired it** (`Blood.probe` callable in `_burst`), the
decals and the droplets spent per shot and over the 6 s after. What it found, per revolver chest
shot, before: **3–4 plumes** — the hit's own (body tier, as tuned), then `clown_gore.blast` firing
a **headshot-class spray** (amount 1.8) and a back spray, and the blast's **seven arterial beats**
each firing a head-class `mist`; **7 decals** a shot and **~190 more in the 6 s after** (12 plumes)
from the spurts' drops and the bleeds dripping 3–8 drops a second. The cause: **bullet wear**
(`clown.gd` `_wear`, `WEAR_STAGES`) blows the chest open at 75 cumulative damage and the revolver
does 80 — so every first revolver chest shot was a chest-opening, and the chest-opening behaved
like a headshot.
Fixed, by the probe:
- `clown_gore.blast`: a **torso** blast (chest, belly) throws **no spray and no arterial jet of its
  own** — the shot that opened it already sprayed; it bleeds (amount 1.0). The **head** keeps the
  jet (7 beats), the 1.8 spray and the back spatter.
- `Blood.mist` under amount 1.2 is a body-class puff (a spurt's beat: slow strings, no haze);
  1.2 and over the head-class burst (a skull going). Spurt beats run 0.5–1.2.
- **Bleeds** drip a drop every 0.5–1.2 s per wound / amount (were 0.12–0.4), floor-only, 3–6 cm.
- `_break_leg`, `_break_arm`, `show_broken_knee`: limb tier (were amount 1.2–1.6 with no weapon
  = head tier).
- The rifle's **pierce exit** (`fps_player._pierce`): a "splash" (drops only) — the entry hit
  already threw the exit spray; it was a second head-class spray on every rifle through-shot.
After: per revolver chest shot **0–1 small body plume, 1 decal**; **0 plumes** and **20–28 small
floor drips** in the 6 s after (were 12 and ~190). Thigh: 0–1 limb plume, 0 wall decals.
Tests: `test_blood` 43/0, `test_impacts` 0, `test_blast` 0, `test_rifle` 0, `test_killcam` 0,
`test_legs` 0, `test_throat` the baseline 2 (hands), `test_revolver` the baseline 1 (rate),
`test_limbs` its known flaky pistol/explosion checks.

## 16. Phase D — drips that run — done 25 Nov
A heavy on a wall (a headshot's mass) — and a close impact on a wall half the time — now **runs**:
`start_run` hangs a quad under the mark (`shaders/blood_run.gdshader`, a few millimetres off the
wall, hung from its top edge which sits inside the mass) and over 3–7 s (`RUN_TIME`, fast then
slowing) scrolls the drip mask's reveal channel: each run wanders down at its own pace, starting a
little after the last, some short, with a glistening head riding its front and a bead where it
stops; then it dries with the rest (tint and gloss over `DRY_TIME`). The mask was regenerated
(`gen_blood_splatters_v2.py --dripmask`): a random-walk wander instead of a sine zigzag, widths
3–9 px with a swell where the run slows, soft edges, per-run start delays. 24 runs live at once;
when a quad is needed again the oldest is **baked to a dripfield decal** so a dried run stays as a
mark; `clear()` ends them. Tests: `test_blood` +5 (a headshot's heavy starts a run; its quad hangs
on the wall facing out; the run advances over the seconds; a body mist starts none; the 25th run
bakes the oldest; clear ends them) — 48 checks, 0 failed; `test_pools` 0. Look: `look_blood --runs`
(`runs_2s.png`, `runs_8s.png`). Skipped: a run on sloped or bumpy walls follows the quad, not the
bumps (sandbags) — fine at a glance, a decal-based run would need a per-kind decal animation Godot
does not offer.

## 17. Phase F — the look room — sheet made 25 Nov, his eye next
`docs/reference/blood_phase_c/phase_f_sheet.png`: the six wall regimes at their restrained sizes,
the headshot's heavy with its runs at 2 and 8 s, the rifle plume side-on, a headshot from behind
with the haze, and an arterial stream — all under the container's software renderer, which runs
darker than the Mac. His references (Wolfenstein, The Last of Us, DieselFrag) are not in the repo;
the comparison is his, in game. **Phase E stays parked** (lens, weapon and neighbour spatter: he
said no). The world blood mask is not needed: 1,200 fading decals with priority recycling have not
been reported short since Phase D's persistence half.

### Where the overhaul stands
A–D and F built; E parked. The knobs he is most likely to want, all in `blood_manager.gd`:
`BODY_MARK_CHANCE 0.7`, `BODY_PLUME_CHANCE 0.5`, `LIMB_MARK_CHANCE 0.4`, `LIMB_PLUME_CHANCE 0.3`,
`TIER_REACH {head 2.6, body 1.6, limb 1.2}`, the `_burst` ratios (head 0.3+0.45·amount, body
0.12–0.25, limb 0.08), `RUN_TIME (3, 7)`, `maximum_pool_radius 0.5`, `DRY_TIME 50`,
`MAX_DECALS 1200`. `scenes/probe_blood_sources.tscn` prints what a revolver kill spends.

## 18. His look at the runs (25 Nov): "the blood splats are a little too light … makes the drips
look weird because they are such a darker colour"
The splat textures coloured most of a mass at the *thin* end of the ramp (thick^0.7 toward deep),
so under a lamp a mark read pale while the run under it was painted at the deep end. The library
is regenerated (`finish()`): the mass goes deep sooner (thick^0.45), the thin edge darker (0.16
linear, was 0.21), the alpha floor 0.55 (was 0.45); the run shader comes a little lighter to meet
it (thin 0.20, mix weight 0.7). `runs_palette_before_after.png` shows the pair; the regimes strip
is darker throughout. `test_blood` 48, 0 failed. The 36 PNGs are rewritten — Godot re-imports them
on the next open of the project.

## 19. His screenshot of the runs (25 Nov): "they all start from the same horizontal level …
too evenly spaced apart"
True of the mask: every run began on its top row and the eight sat at W/8. Regenerated
(`--dripmask`): nine runs at random x with a minimum gap and one crowded pair; each starts at its
own height in the top 30 % from a small swelling where the mass fed it; lengths 8–90 %; widths
2–9 px. The run shader fades the quad's top 10 % so nothing begins on a line, and the quad is
narrower than the mass (0.65 × size) so the runs come out of it, not beside it.
`runs_staggered.png`. `test_blood` 48, 0 failed.
