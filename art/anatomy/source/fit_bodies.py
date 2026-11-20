"""Fit the reference anatomy inside each enemy body: where, and how big.

    python3 art/anatomy/source/fit_bodies.py art/anatomy

For each body (clown, witzsoldat, rattlejack, zornhauptmann) and each region
(head, neck, chest, belly, pelvis) finds the transform from the reference frame
(BodyParts3D's: metres, +Y up, +Z front) into the body's skeleton at rest that
makes the anatomy as large as it can be while staying inside the skin:

  - the skin is measured from the body mesh itself (rest positions, without the
    stump faces and without the arms or legs): in 2 cm bands of height and 10
    degree sectors round the body's axis, the innermost skin in each direction;
  - a placement is good if 98-99% of the anatomy's vertices are inside that
    skin with 3-5 mm to spare, its width within 15% and its depth within 30% of
    its height's scale (stylised heads and flat torsos are shallow; the rest keeps
    its proportions). What little still pokes out is never seen: the game only
    draws anatomy round an actual hole in the body (shaders/anatomy.gdshader);
  - the search starts from the body's own bones (the region's bone heights on
    the plain clown, where the reference sits within a centimetre or two).

Writes art/anatomy/fits.json: body -> region -> {basis (3 columns), origin}.
"""
import json
import os
import struct
import sys

import numpy as np

ROOT = os.path.join(os.path.dirname(__file__), "..", "..", "..")
BODIES = {
    "clown": "art/clown/clown.glb",
    "witzsoldat": "art/witzsoldat/witzsoldat.glb",
    "rattlejack": "art/rattlejack/rattlejack.glb",
    "zornhauptmann": "art/zornhauptmann/zornhauptmann.glb",
    "witzsoldat_dark": "art/witzsoldat_dark/witzsoldat_dark.glb",
}
# segment ids (clown_segments.json): 0 Pelvis, 1 Torso, 2 Head; 3.. the limbs
TRUNK = {0, 1, 2}
# region -> (file, bone it rides, clearance m, inside fraction)
# and which segments' skin holds it (0 Pelvis, 1 Torso, 2 Head)
# and which segments' skin holds it (0 Pelvis, 1 Torso, 2 Head), and which
# its centre line is taken from
REGIONS = {
    "head": ("head", "Head", 0.003, 0.985, [1, 2], [2]),
    "neck": ("neck", "Neck", 0.004, 0.98, [1, 2], [1, 2]),
    "chest": ("chest", "Chest", 0.005, 0.985, [1], [1]),
    "belly": ("belly", "Spine", 0.005, 0.99, [0, 1], [0, 1]),
    "pelvis": ("pelvis", "Hips", 0.005, 0.98, [0, 1], [0, 1]),
}
CT = {5120: np.int8, 5121: np.uint8, 5122: np.int16, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}
NC = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


def load(path):
    b = open(path, "rb").read()
    off = 12
    js = None
    bin_ = b""
    while off < len(b):
        ln, ty = struct.unpack("<II", b[off:off + 8])
        if ty == 0x4E4F534A:
            js = json.loads(b[off + 8:off + 8 + ln])
        elif ty == 0x004E4942:
            bin_ = b[off + 8:off + 8 + ln]
        off += 8 + ln
    return js, bin_


def acc(js, bin_, i):
    a = js["accessors"][i]
    bv = js["bufferViews"][a["bufferView"]]
    dt = np.dtype(CT[a["componentType"]])
    n = NC[a["type"]]
    start = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
    stride = bv.get("byteStride", 0) or dt.itemsize * n
    raw = np.frombuffer(bin_[start:start + (a["count"] - 1) * stride + dt.itemsize * n], dtype=np.uint8)
    rows = np.lib.stride_tricks.as_strided(raw, shape=(a["count"], dt.itemsize * n), strides=(stride, 1))
    arr = np.ascontiguousarray(rows).view(dt).reshape(a["count"], n).astype(np.float64)
    if a.get("normalized"):
        arr /= np.iinfo(dt).max
    return arr


def trs(n):
    m = np.eye(4)
    if "matrix" in n:
        return np.array(n["matrix"]).reshape(4, 4).T
    x, y, z, w = n.get("rotation", [0, 0, 0, 1])
    r = np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                  [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                  [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])
    m[:3, :3] = r @ np.diag(n.get("scale", [1, 1, 1]))
    m[:3, 3] = n.get("translation", [0, 0, 0])
    return m


def body(path):
    """Skin points (rest, skeleton space) with their segment; bone rest origins."""
    js, bin_ = load(path)
    parent = {}
    for i, n in enumerate(js["nodes"]):
        for c in n.get("children", []):
            parent[c] = i

    def glob(i):
        m = trs(js["nodes"][i])
        while i in parent:
            i = parent[i]
            m = trs(js["nodes"][i]) @ m
        return m
    sk = js["skins"][0]
    joints = sk["joints"]
    # the skeleton's own node: the parent of the root joint
    root = [j for j in joints if parent.get(j) not in joints][0]
    arm = glob(parent[root]) if root in parent else np.eye(4)
    to_skel = np.linalg.inv(arm)
    bones = {js["nodes"][j]["name"]: (to_skel @ glob(j))[:3, 3] for j in joints}
    pts = []
    segs = []
    mats = []
    for i, n in enumerate(js["nodes"]):
        if "mesh" not in n or n.get("skin", -1) != 0:
            continue
        M = to_skel @ glob(i)
        for pr in js["meshes"][n["mesh"]]["primitives"]:
            mat = js["materials"][pr["material"]]["name"] if "material" in pr else ""
            if mat in ("Gore", "BoneCore"):
                continue                                      # wound and stump insides, not skin
            P = acc(js, bin_, pr["attributes"]["POSITION"])
            uv2 = acc(js, bin_, pr["attributes"]["TEXCOORD_1"])
            keep = np.abs(uv2[:, 1] - 0.5) <= 0.1             # not a stump face
            seg = (uv2[:, 0] * 16.0).astype(int)
            P = (np.c_[P, np.ones(len(P))] @ M.T)[:, :3]
            # the surface itself, not just its corners (a low-poly body has rings
            # of vertices further apart than the bands): points every ~8 mm
            F = acc(js, bin_, pr["indices"]).astype(int).reshape(-1, 3)
            F = F[keep[F].all(1)]
            T = P[F]
            area = 0.5 * np.linalg.norm(np.cross(T[:, 1] - T[:, 0], T[:, 2] - T[:, 0]), axis=1)
            n = np.clip((area / 0.00006).astype(int), 1, 400)
            tri = np.repeat(np.arange(len(F)), n)
            rng = np.random.default_rng(7)
            u = rng.random(len(tri))
            v = rng.random(len(tri))
            flip = u + v > 1
            u[flip] = 1 - u[flip]
            v[flip] = 1 - v[flip]
            S = T[tri, 0] + (T[tri, 1] - T[tri, 0]) * u[:, None] + (T[tri, 2] - T[tri, 0]) * v[:, None]
            pts.append(np.vstack([P[keep], S]))
            segs.append(np.concatenate([seg[keep], seg[F[tri, 0]]]))
            mats += [mat] * (int(keep.sum()) + len(S))
    body.mats = np.array(mats)
    return np.vstack(pts), np.concatenate(segs), bones


def anatomy_points(path):
    js, bin_ = load(path)
    out = []
    for n in js["nodes"]:
        # the muscle walls are not held to the skin: they lie right under it, and
        # are only ever seen round a hole anyway
        if "mesh" not in n or n.get("name", "").startswith("Muscle"):
            continue
        M = trs(n)
        for pr in js["meshes"][n["mesh"]]["primitives"]:
            P = acc(js, bin_, pr["attributes"]["POSITION"])
            out.append((np.c_[P, np.ones(len(P))] @ M.T)[:, :3])
    return np.vstack(out)


BAND = 0.02
SECTORS = 36


class Skin:
    """The innermost skin round a vertical axis, per band of height and sector."""

    def __init__(self, P, axis_pts=None):
        self.P = P
        A = P if axis_pts is None else axis_pts
        y0 = P[:, 1].min()
        self.y0 = y0
        nb = int((P[:, 1].max() - y0) / BAND) + 2
        self.nb = nb
        # the axis: per band, the middle of the skin in x and z
        self.cx = np.zeros(nb)
        self.cz = np.zeros(nb)
        ba = ((A[:, 1] - y0) / BAND).astype(int)
        for k in range(nb):
            sel = A[ba == k]
            if len(sel) > 8:
                self.cx[k] = 0.5 * (np.percentile(sel[:, 0], 2) + np.percentile(sel[:, 0], 98))
                self.cz[k] = 0.5 * (np.percentile(sel[:, 2], 2) + np.percentile(sel[:, 2], 98))
            else:
                self.cx[k] = np.nan
        ok = ~np.isnan(self.cx)
        idx = np.arange(nb)
        b = ((P[:, 1] - y0) / BAND).astype(int)
        self.cx = np.interp(idx, idx[ok], self.cx[ok])
        self.cz = np.interp(idx, idx[ok], self.cz[ok])
        self.r = np.full((nb, SECTORS), np.inf)
        dx = P[:, 0] - self.cx[b]
        dz = P[:, 2] - self.cz[b]
        rad = np.hypot(dx, dz)
        sec = ((np.arctan2(dz, dx) + np.pi) / (2 * np.pi) * SECTORS).astype(int) % SECTORS
        np.minimum.at(self.r, (b, sec), rad)
        # a sector with no skin in it: take its neighbours' (a gap, not open air)
        for k in range(nb):
            row = self.r[k]
            if np.isinf(row).all():
                continue
            for _ in range(SECTORS):
                bad = np.isinf(row)
                if not bad.any():
                    break
                row[bad] = np.minimum(np.roll(row, 1), np.roll(row, -1))[bad]

    def margin(self, Q):
        """Per point: how far inside the skin it is (negative: outside)."""
        b = ((Q[:, 1] - self.y0) / BAND).astype(int)
        inside_band = (b >= 0) & (b < self.nb)
        b = np.clip(b, 0, self.nb - 1)
        dx = Q[:, 0] - self.cx[b]
        dz = Q[:, 2] - self.cz[b]
        rad = np.hypot(dx, dz)
        sec = ((np.arctan2(dz, dx) + np.pi) / (2 * np.pi) * SECTORS).astype(int) % SECTORS
        m = self.r[b, sec] - rad
        m[~inside_band] = -1.0
        return m


def fit(A, skin, anchor_ref, anchor_body, clear, need, search=0.03, core_y=None):
    """Real size if it fits (up to 1.05); otherwise as little smaller as it must
    be: the whole thing, or its width or (most of all) its depth."""
    rng = np.random.default_rng(3)
    S = A[rng.choice(len(A), min(len(A), 4000), replace=False)]
    # the head: the cranium and brain must be in; the jaw and teeth, mostly
    core = S[:, 1] > core_y if core_y is not None else np.ones(len(S), bool)
    best = None
    for s in np.arange(1.05, 0.55, -0.01):
        for sx_k in (1.0, 0.95, 0.9, 0.85):
            for sz_k in (1.0, 0.95, 0.9, 0.85, 0.8, 0.75, 0.7):
                sc = np.array([s * sx_k, s, s * sz_k])
                vol = sc.prod()
                if best is not None and vol <= best[0]:
                    continue
                for dy in np.arange(-0.04, 0.0401, 0.01):
                    for dz in np.arange(-search, search + 0.001, 0.01):
                        o = anchor_body + np.array([0.0, dy, dz])
                        Q = (S - anchor_ref) * sc + o
                        m = skin.margin(Q) > clear
                        if m[core].mean() >= need and (core.all() or m[~core].mean() >= 0.85):
                            if best is None or vol > best[0]:
                                best = (vol, sc, o)
        if best is not None and best[0] >= s ** 3:
            break
    if best is None:
        return None
    vol, sc, o = best
    # reference point p -> body: (p - anchor_ref) * sc + o
    return {"basis": [[sc[0], 0, 0], [0, sc[1], 0], [0, 0, sc[2]]], "origin": (o - anchor_ref * sc).tolist(), "scale": sc.tolist()}


def main():
    out_dir = sys.argv[1]
    # --only a,b: fit just these, keeping the others' fits as they are in fits.json
    only = sys.argv[sys.argv.index("--only") + 1].split(",") if "--only" in sys.argv else None
    clown_pts, clown_seg, clown_bones = body(os.path.join(ROOT, BODIES["clown"]))
    fits = {}
    if only:
        fits = json.load(open(os.path.join(out_dir, "fits.json")))
    for name, path in BODIES.items():
        if only and name not in only:
            continue
        P, seg, bones = body(os.path.join(ROOT, path))
        fits[name] = {}
        for region, (fname, bone, clear, need, segs, axis_segs) in REGIONS.items():
            skin = Skin(P[np.isin(seg, segs)], P[np.isin(seg, axis_segs)])
            A = anatomy_points(os.path.join(out_dir, fname + ".glb"))
            # height from the bones (the reference against the plain clown's bone,
            # moved to this body's); across and front to back, centred in the skin
            mid = 0.5 * (A.min(0) + A.max(0))
            anchor_ref = np.array([mid[0], clown_bones[bone][1], mid[2]])
            k = int(np.clip((bones[bone][1] + (mid[1] - clown_bones[bone][1]) - skin.y0) / BAND, 0, skin.nb - 1))
            anchor_body = np.array([skin.cx[k], bones[bone][1], skin.cz[k]])
            if region == "head":
                # the skull hangs from the top of the head (its own skin, not hair,
                # pom-poms or nose; under a helmet, the scalp), a centimetre under it
                mats = body.mats
                head = P[(seg == 2) & ~np.isin(mats, ["Hair", "PomPom", "Nose"])]
                top = np.percentile(head[:, 1], 99.5)
                anchor_ref = np.array([mid[0], A[:, 1].max(), mid[2]])
                k = int(np.clip((top - 0.08 - skin.y0) / BAND, 0, skin.nb - 1))
                anchor_body = np.array([skin.cx[k], top - 0.012, skin.cz[k]])
            f = fit(A, skin, anchor_ref, anchor_body, clear, need, core_y=1.6 if region == "head" else None)
            if f is None:
                print("%-13s %-6s: no fit" % (name, region))
                continue
            fits[name][region] = f
            print("%-13s %-6s: scale %s, origin %s" % (name, region, np.round(f["scale"], 3), np.round(f["origin"], 3)))
    json.dump(fits, open(os.path.join(out_dir, "fits.json"), "w"), indent=1)
    print("wrote", os.path.join(out_dir, "fits.json"))


if __name__ == "__main__":
    main()
