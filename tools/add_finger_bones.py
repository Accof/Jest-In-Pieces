"""Give an enemy body GLB finger bones, and weight its hands' fingers to them.

    python3 tools/add_finger_bones.py art/witzsoldat/witzsoldat.glb [...]

The bodies came out of the build scripts on the shared 21-bone skeleton,
with each hand weighted to one bone. This adds, under each hand, five chains
of three bones:

    <Side>Thumb1..3, <Side>Index1..3, <Side>Middle1..3, <Side>Ring1..3, <Side>Little1..3

and moves the fingers' vertices from the hand onto them. Nothing else in the
file changes: no other node, weight, mesh or material is touched, so the rest
of the rig (and every pose the game builds on it) stays exactly as it was.
The edit is made in the glTF itself (a new joint list, new inverse bind
matrices, new JOINTS_0/WEIGHTS_0), not by a round trip through Blender,
which would re-derive the existing bones.

Every new bone's rest has the hand's own axes (identity rotation under the
hand), so the game curls a finger by turning its bones about the hand's
across-the-palm axis.

Where the fingers are is measured from the mesh, in the hand bone's frame
(+Y wrist to fingertips, Z across the palm, X through it):
  - length L: the fingertips' reach along +Y;
  - knuckles at 0.56 L; the finger's joints at 0.45 and 0.75 of the rest;
  - the four fingers: the width of the hand at the fingertips, in four bands;
  - the thumb: the vertices standing out past the fingers' band on one side,
    below the knuckles; its chain runs along their main axis;
  - the palm: the side the thumb stands out toward.
The hand keeps everything behind the knuckles; a vertex past them goes to its
finger (blended into the neighbour across a narrow band between fingers, and
across each joint), at most four influences a vertex.

Writes the measured layout into the GLB's extras (asset.extras.fingers) for the
game: the palm sign and the across-palm axis per side.
"""
import json
import struct
import sys

import numpy as np

CT = {5120: np.int8, 5121: np.uint8, 5122: np.int16, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}
NC = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}
FINGERS = ["Index", "Middle", "Ring", "Little"]


def load(path):
    b = open(path, "rb").read()
    assert b[:4] == b"glTF"
    off = 12
    js = None
    bin_ = b""
    while off < len(b):
        ln, ty = struct.unpack("<II", b[off:off + 8])
        data = b[off + 8:off + 8 + ln]
        if ty == 0x4E4F534A:
            js = json.loads(data)
        elif ty == 0x004E4942:
            bin_ = data
        off += 8 + ln
    return js, bytearray(bin_)


def save(path, js, bin_):
    while len(bin_) % 4:
        bin_.append(0)
    js["buffers"][0]["byteLength"] = len(bin_)
    j = json.dumps(js, separators=(",", ":")).encode()
    while len(j) % 4:
        j += b" "
    out = b"glTF" + struct.pack("<II", 2, 12 + 8 + len(j) + 8 + len(bin_))
    out += struct.pack("<II", len(j), 0x4E4F534A) + j + struct.pack("<II", len(bin_), 0x004E4942) + bytes(bin_)
    open(path, "wb").write(out)


def acc(js, bin_, i):
    a = js["accessors"][i]
    bv = js["bufferViews"][a["bufferView"]]
    dt = np.dtype(CT[a["componentType"]])
    n = NC[a["type"]]
    start = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
    stride = bv.get("byteStride", 0) or dt.itemsize * n
    raw = np.frombuffer(bytes(bin_[start:start + (a["count"] - 1) * stride + dt.itemsize * n]), dtype=np.uint8)
    rows = np.lib.stride_tricks.as_strided(raw, shape=(a["count"], dt.itemsize * n), strides=(stride, 1))
    arr = np.ascontiguousarray(rows).view(dt).reshape(a["count"], n)
    if a.get("normalized"):
        arr = arr.astype(np.float32) / np.iinfo(dt).max
    return arr


def add_accessor(js, bin_, arr, ctype, typ, target=None):
    while len(bin_) % 4:
        bin_.append(0)
    data = np.ascontiguousarray(arr.astype(CT[ctype])).tobytes()
    bv = {"buffer": 0, "byteOffset": len(bin_), "byteLength": len(data)}
    if target:
        bv["target"] = target
    bin_.extend(data)
    js["bufferViews"].append(bv)
    a = {"bufferView": len(js["bufferViews"]) - 1, "componentType": ctype, "count": int(arr.shape[0]), "type": typ}
    js["accessors"].append(a)
    return len(js["accessors"]) - 1


def trs(n):
    m = np.eye(4)
    if "matrix" in n:
        return np.array(n["matrix"]).reshape(4, 4).T
    x, y, z, w = n.get("rotation", [0, 0, 0, 1])
    r = np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                  [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                  [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])
    s = np.diag(n.get("scale", [1, 1, 1]))
    m[:3, :3] = r @ s
    m[:3, 3] = n.get("translation", [0, 0, 0])
    return m


def smooth(a, b, x):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def measure(Q):
    """The hand's layout from its vertices `Q` (hand frame, the ones mostly on the hand)."""
    L = float(np.percentile(Q[:, 1], 99.5))
    K = 0.56 * L
    tips = Q[Q[:, 1] > 0.8 * L]
    fz0, fz1 = np.percentile(tips[:, 2], [1, 99])
    zlo, zhi = np.percentile(Q[:, 2], [0.5, 99.5])
    s = -1.0 if (fz0 - zlo) > (zhi - fz1) else 1.0           # the thumb's side, along z
    edge = fz0 if s < 0 else fz1
    thumb = Q[(s * (Q[:, 2] - edge) > 0.012) & (Q[:, 1] < 0.75 * L)]
    if len(thumb) < 8:                                        # (a mitten: take the far edge low down)
        thumb = Q[(s * (Q[:, 2] - edge) > 0.0) & (Q[:, 1] < 0.6 * L) & (Q[:, 1] > 0.15 * L)]
    palm = float(np.sign(thumb[:, 0].mean() - Q[:, 0].mean()) or 1.0)
    # the thumb's axis: from where it leaves the palm to its tip
    c = thumb.mean(0)
    u, sv, vt = np.linalg.svd(thumb - c)
    ax = vt[0]
    if (ax[1] + s * ax[2]) < 0:
        ax = -ax                                              # pointing out and up, toward its tip
    t = (thumb - c) @ ax
    t0, t1 = float(np.percentile(t, 2)), float(np.percentile(t, 99))
    base = c + ax * t0
    # its base sits on the palm's edge: pull it in to the edge, near the wrist
    base[2] = edge + s * 0.004
    tl = float(np.linalg.norm(c + ax * t1 - base))
    tax = (c + ax * t1 - base) / max(tl, 1e-6)
    fw = (fz1 - fz0) / 4.0
    fingers = []
    order = range(4) if s < 0 else range(3, -1, -1)           # index next to the thumb
    for k, i in enumerate(order):
        zc = fz0 + (i + 0.5) * fw
        band = Q[(np.abs(Q[:, 2] - zc) < fw * 0.5) & (Q[:, 1] > K - 0.02)]
        xc = float(np.median(band[:, 0])) if len(band) else float(Q[:, 0].mean())
        F = L - K
        fingers.append({"name": FINGERS[k], "z": zc, "x": xc, "y": [K, K + 0.45 * F, K + 0.75 * F], "tip": L})
    return {"L": L, "K": K, "fz": (fz0, fz1), "fw": fw, "side": s, "edge": edge, "palm": palm,
            "thumb": {"base": base, "axis": tax, "len": tl}, "fingers": fingers}


def weights_for(Q, lay):
    """Per vertex: [(bone key, weight)] for the part of it that leaves the hand."""
    out = []
    fz0 = lay["fz"][0]
    fw = lay["fw"]
    s = lay["side"]
    th = lay["thumb"]
    for q in Q:
        w = {}
        # thumb: out past the fingers' edge, low on the hand
        tside = smooth(0.004, 0.014, s * (q[2] - lay["edge"])) * (1.0 - smooth(0.7 * lay["L"], 0.8 * lay["L"], q[1]))
        if tside > 0.0:
            tt = float((q - th["base"]) @ th["axis"]) / max(th["len"], 1e-6)
            move = smooth(0.05, 0.2, tt) * tside
            if move > 0.0:
                a = smooth(0.36, 0.44, tt)
                b = smooth(0.68, 0.76, tt)
                for key, v in (("Thumb1", 1 - a), ("Thumb2", a * (1 - b)), ("Thumb3", a * b)):
                    if v > 0:
                        w[key] = w.get(key, 0) + v * move
        rest = 1.0 - sum(w.values())
        # fingers: past the knuckles
        f = smooth(lay["K"] - 0.012, lay["K"] + 0.006, q[1]) * rest
        if f > 0.0:
            u = (q[2] - fz0) / fw - 0.5
            u = min(max(u, 0.0), 3.0)
            i0 = int(np.floor(u))
            fr = u - i0
            bl = smooth(0.4, 0.6, fr) if i0 < 3 else 0.0
            for idx, v in ((i0, 1 - bl), (min(i0 + 1, 3), bl)):
                if v <= 0:
                    continue
                fg = next(x for x in lay["fingers"] if abs(x["z"] - (fz0 + (idx + 0.5) * fw)) < 1e-9)
                y1, y2 = fg["y"][1], fg["y"][2]
                a = smooth(y1 - 0.004, y1 + 0.004, q[1])
                b = smooth(y2 - 0.004, y2 + 0.004, q[1])
                for seg, sv in ((1, 1 - a), (2, a * (1 - b)), (3, a * b)):
                    if sv > 0:
                        key = fg["name"] + str(seg)
                        w[key] = w.get(key, 0) + v * sv * f
        out.append(w)
    return out


def run(path):
    js, bin_ = load(path)
    sk = js["skins"][0]
    joints = list(sk["joints"])
    names = [js["nodes"][j]["name"] for j in joints]
    if "LeftIndex1" in names:
        print(path, ": has finger bones already")
        return
    ibm = acc(js, bin_, sk["inverseBindMatrices"]).reshape(-1, 4, 4).transpose(0, 2, 1)   # column-major -> rows
    # node globals at rest, to check the bind pose is the rest pose (scale included)
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
    mesh_nodes = [i for i, n in enumerate(js["nodes"]) if "mesh" in n and n.get("skin", 0) == 0]
    mesh_g = glob(mesh_nodes[0])
    for nm in ("Hips", "LeftHand", "RightHand"):
        j = names.index(nm)
        bind = mesh_g @ np.linalg.inv(ibm[j])
        err = np.abs(bind - glob(joints[j])).max()
        assert err < 1e-4, f"{path}: {nm} bind pose is not its rest ({err})"
        sc = np.linalg.norm(glob(joints[j])[:3, :3], axis=0)
        assert np.allclose(sc, 1.0, atol=1e-4), f"{path}: {nm} is scaled {sc}"
    prims = [p for n in mesh_nodes for p in js["meshes"][js["nodes"][n]["mesh"]]["primitives"]]
    P = [acc(js, bin_, p["attributes"]["POSITION"]).astype(np.float64) for p in prims]
    J = [acc(js, bin_, p["attributes"]["JOINTS_0"]).astype(np.int64) for p in prims]
    W = [acc(js, bin_, p["attributes"]["WEIGHTS_0"]).astype(np.float64) for p in prims]
    layouts = {}
    new_bones = []      # (name, parent joint name, translation in parent frame)
    for side in ("Left", "Right"):
        hj = names.index(side + "Hand")
        M = ibm[hj]
        Qs = [(np.c_[p, np.ones(len(p))] @ M.T)[:, :3] for p in P]
        wh = [(w * (j == hj)).sum(1) for j, w in zip(J, W)]
        Qall = np.vstack([q[h > 0.5] for q, h in zip(Qs, wh)])
        lay = measure(Qall)
        layouts[side] = lay
        print(f"{path} {side}: L {lay['L']:.3f}  knuckles {lay['K']:.3f}  thumb side z{'+' if lay['side'] > 0 else '-'}  palm x{'+' if lay['palm'] > 0 else '-'}"
              f"  thumb {len(Qall)} verts, len {lay['thumb']['len']:.3f}")
        th = lay["thumb"]
        pts = [th["base"], th["base"] + th["axis"] * th["len"] * 0.4, th["base"] + th["axis"] * th["len"] * 0.72]
        prev = side + "Hand"
        prevp = np.zeros(3)
        for k, p in enumerate(pts):
            new_bones.append((side + "Thumb" + str(k + 1), prev, p - prevp, p))
            prev = side + "Thumb" + str(k + 1)
            prevp = p
        for fg in lay["fingers"]:
            prev = side + "Hand"
            prevp = np.zeros(3)
            for k, y in enumerate(fg["y"]):
                p = np.array([fg["x"], y, fg["z"]])
                new_bones.append((side + fg["name"] + str(k + 1), prev, p - prevp, p))
                prev = side + fg["name"] + str(k + 1)
                prevp = p
        # the weights
        for pi in range(len(prims)):
            sel = np.where(wh[pi] > 0.0)[0]
            if len(sel) == 0:
                continue
            ws = weights_for(Qs[pi][sel], lay)
            for vi, w in zip(sel, ws):
                if not w:
                    continue
                cur = {}
                for jj, ww in zip(J[pi][vi], W[pi][vi]):
                    if ww > 0:
                        cur[int(jj)] = cur.get(int(jj), 0.0) + float(ww)
                handw = cur.pop(hj, 0.0)
                moved = sum(w.values())
                newd = dict(cur)
                if handw * (1 - moved) > 0:
                    newd[hj] = handw * (1 - moved)
                for key, v in w.items():
                    newd[("bone", side + key)] = handw * v
                items = sorted(newd.items(), key=lambda kv: -kv[1])[:4]
                tot = sum(v for _, v in items)
                J[pi][vi] = 0
                W[pi][vi] = 0
                for k, (jj, v) in enumerate(items):
                    W[pi][vi][k] = v / tot
                    # a new bone: a placeholder, resolved once it is in the joint list
                    J[pi][vi][k] = -(10000 + ord_index(jj[1])) if isinstance(jj, tuple) else jj
    # add the nodes and joints
    node_of = {names[i]: joints[i] for i in range(len(names))}
    new_ibm = list(ibm)
    hand_ibm = {s: ibm[names.index(s + "Hand")] for s in ("Left", "Right")}
    for name, par, t, p_hand in new_bones:
        js["nodes"].append({"name": name, "translation": [float(v) for v in t]})
        ni = len(js["nodes"]) - 1
        js["nodes"][node_of[par]].setdefault("children", []).append(ni)
        node_of[name] = ni
        joints.append(ni)
        names.append(name)
        side = "Left" if name.startswith("Left") else "Right"
        T = np.eye(4)
        T[:3, 3] = -p_hand
        new_ibm.append(T @ hand_ibm[side])
    sk["joints"] = joints
    sk["inverseBindMatrices"] = add_accessor(js, bin_, np.array(new_ibm).transpose(0, 2, 1).reshape(-1, 16), 5126, "MAT4")
    for pi, p in enumerate(prims):
        j = J[pi]
        neg = j <= -10000
        if neg.any():
            j[neg] = [names.index(_ORD[-int(x) - 10000]) for x in j[neg]]
        p["attributes"]["JOINTS_0"] = add_accessor(js, bin_, j, 5123, "VEC4", 34962)
        p["attributes"]["WEIGHTS_0"] = add_accessor(js, bin_, W[pi], 5126, "VEC4", 34962)
    js.setdefault("asset", {}).setdefault("extras", {})["fingers"] = {
        s: {"palm": layouts[s]["palm"], "thumb_side": layouts[s]["side"], "length": layouts[s]["L"]} for s in layouts}
    save(path, js, bin_)
    print(path, ": added", len(new_bones), "bones")


_ORD = []


def ord_index(name):
    if name not in _ORD:
        _ORD.append(name)
    return _ORD.index(name)


if __name__ == "__main__":
    for a in sys.argv[1:]:
        run(a)
