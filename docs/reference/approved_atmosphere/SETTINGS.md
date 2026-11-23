# Drowned Front — approved atmosphere baseline (`drowned_front_approved_atmosphere`)

Approved by Andrew on 22 Nov 2026 at 22:09 ("you were right. i needed to reload the scene. Continue
with the master plan"), live on his Mac, after five gate iterations on his feedback. Commit `12ca5c7`
carries these settings; the tag `drowned_front_approved_atmosphere` points at it. The five shots here
were rendered at exactly these settings (container, software Vulkan, 1280 × 720, seed 1916).
Code: `scripts/world/front/front_atmosphere.gd`, `front_fog.gd`, `FrontArt.ground_material()`,
`FrontArt._mist()`, `FrontArt._drift_smoke()`, `FrontArt._dressing()`, `FrontArt._bodies()`.
**The look does not change again without a new approval (D-16).**

## Settings as approved (iteration 5 — "match the reference as closely as possible", 22 Nov; 1 was too uniformly green and bright, 2 greyed the fog and sky, 3 pushed the mud brown, 4 fixed the sky coverage and the glint and added the banks and the litter, 5 took the green out and the sky down to the image's weight)
| Part | Setting |
|---|---|
| Sky (`overcast_sky`) | mass (0.33, 0.34, 0.32), body (0.45, 0.46, 0.44), opening (0.66, 0.66, 0.62), warm (0.94, 0.90, 0.80) — the glow where the sun hides, horizon (0.62, 0.62, 0.575), ground (0.26, 0.25, 0.22), energy 0.9, coverage 0.5 (passes 1–3 had 0.82 — see gate feedback), light dir **(−0.3, 0.36, −0.88)**: low, behind the trees on their side |
| Fog (depth) | colour (0.58, 0.585, 0.545), sun scatter 0.3, begin 6 m, end 140 m, density 0.9, curve 1.0, aerial perspective 0.6, sky affect 0.6; volumetric fog on at density 0 (the mist volume adds to it), albedo (0.70, 0.705, 0.65) |
| Light | ambient from sky 0.5; sun energy 0.55, colour (0.86, 0.88, 0.80), angular 6°, **specular 0** (was 0.05: its glint in the trench-floor puddles blinded — Andrew, 22 Nov live on the Mac), shadows opacity 0.65 blur 3, 70 m |
| Exposure / tone | filmic, exposure 0.9, white 6; auto exposure scale 0.22, sensitivity 90–130 |
| Grade | saturation 0.7, contrast 1.06, LUT: shadows ×(1.06, 0.98, 0.88) (brown), mids ×(1.0, 0.995, 0.965), lights ×(1.02, 1.0, 0.93); glow 0.28, HDR threshold 1.1 |
| SSR / SSAO / SSIL | on / 1.5 (radius 1.4) / 0.5 |
| Ground | dry_ground 0.12, puddles 0.95, earth_darkness 0.28, floor_darkness 0.4, rock_darkness 0.5, brightness 0.76, wall_tint (0.60, 0.50, 0.42), **firm_tint (0.80, 0.66, 0.54)** (new uniform in `mud_terrain.gdshader`, default (1, 1, 1): the legacy level renders as before), floor_tint (0.78, 0.68, 0.58), water (0.26, 0.26, 0.22), puddle (0.07, 0.07, 0.06); field wetness 0.5 + up to 0.35 in the low ground; crater water colour (0.085, 0.08, 0.07) / deep (0.045, 0.043, 0.04) |
| Mist volume | tint (0.66, 0.67, 0.61), density 0.12, e-fold 1.4 m, ×2.6 over No Man's Land; bank tint (0.80, 0.80, 0.75) |
| Drifting smoke | 8 patches, 8 m quads, 16 billows each, 22 s life, wind (0.55, 0, 0.18); each counts as an 8 m sphere of optical density 0.06 |
| Fog banks (`FrontFog`) | radius 15–24 m, 3.5–6 m high, peak density 0.45–0.75, ≤3 at once, every 28–60 s, 1.0–1.6 m/s at our lines; puffs (0.72, 0.75, 0.66) |
| Far smoke columns | half the billows, scale ×0.75, colour ×1.25 / alpha ×0.7 of the legacy day's |
| Visibility | k = −ln 0.3 / 55 m: **0.65 at 20 m, 0.30 at 55 m, 0.14 at 90 m** (test bounds: < 0.31 at 55, < 0.16 at 90) |


## Measured on the shots (sRGB means; reference: sky (120, 123, 112), foreground mud (47, 40, 36))
| shot | sky | foreground |
|---|---|---|
| (a) parapet | (136, 137, 128) | (19, 16, 11) |
| (b) panorama (a bank crossing) | (146, 145, 129) | (119, 118, 98) |
| (c) ground | (137, 137, 128) | (30, 27, 20) |
| (d) silhouettes | (141, 141, 130) | (66, 64, 51) |
| (e) thicker bank | (137, 137, 126) | (67, 65, 52) |

## Amendment — 23 Nov 2026 (Andrew)
Volumetric fog **off** on the Front (`FrontAtmosphere.VOLUMETRIC = false`): the ground-mist volume
and the banks' volumetric body are gone; the depth haze, drifting smoke and bank puffs remain. His
words after playing both: "the game actually looks better, I can see more detail, and the rolling
smoke banks already add that misty look now and again." The shots above predate this.
