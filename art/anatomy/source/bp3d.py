"""Read parts of BodyParts3D 4.0 from the human-atlas packing (atlas.json + body-N.bin).

Each part: float32 positions (metres; +Y up, +Z to the front, +X the body's left),
int16 normals, uint32 triangle indices, at byte offsets in its chunk.
"""
import json
import os

import numpy as np


class Atlas:
    def __init__(self, folder):
        self.folder = folder
        self.meta = json.load(open(os.path.join(folder, "atlas.json")))
        self._chunks = {}

    def _chunk(self, i):
        if i not in self._chunks:
            self._chunks[i] = open(os.path.join(self.folder, "body-%d.bin" % i), "rb").read()
        return self._chunks[i]

    def parts(self, names):
        """Every mesh whose name is in `names` -> [(name, V (n,3), F (m,3))]."""
        want = set(names)
        out = []
        for p in self.meta["parts"]:
            if p["name"] not in want:
                continue
            b = self._chunk(p["chunk"])
            V = np.frombuffer(b, np.float32, p["vertexCount"] * 3, p["positions"]).reshape(-1, 3).astype(np.float64)
            F = np.frombuffer(b, np.uint32, p["indexCount"], p["indices"]).reshape(-1, 3).astype(np.int64)
            out.append((p["name"], V, F))
        missing = want - set(n for n, _, _ in out)
        if missing:
            print("  (not in the atlas: %s)" % sorted(missing))
        return out

    def names(self, pred):
        return sorted(set(p["name"] for p in self.meta["parts"] if pred(p)))
