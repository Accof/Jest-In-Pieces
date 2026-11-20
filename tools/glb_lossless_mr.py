"""Put a model's metal/roughness map back into a built body GLB losslessly.

    python3 tools/glb_lossless_mr.py <built.glb> <original tripo.glb>

Blender's glTF export re-encodes every image in one format. For the dark
WitzSoldat the colour and normal maps are JPEGs and pass through unchanged, but
the metal/roughness map came as an 11 MB PNG; exported as JPEG it ringed on the
helmet's hard metal edges (metal channel errors up to 168/255). This takes the
original PNG's pixels, encodes them as lossless WebP (about 6 MB: bit-exact),
and swaps them in for the exported map, using the EXT_texture_webp extension
(which Godot imports). Nothing else in the file changes.
"""
import io
import json
import struct
import sys

from PIL import Image


def read_glb(path):
    d = open(path, "rb").read()
    n = struct.unpack("<I", d[12:16])[0]
    j = json.loads(d[20:20 + n])
    off = 20 + n
    blen = struct.unpack("<I", d[off:off + 4])[0]
    return j, bytearray(d[off + 8:off + 8 + blen])


def view_bytes(j, b, k):
    bv = j["bufferViews"][k]
    o = bv.get("byteOffset", 0)
    return bytes(b[o:o + bv["byteLength"]])


def write_glb(path, j, b):
    while len(b) % 4:
        b.append(0)
    js = json.dumps(j, separators=(",", ":")).encode()
    js += b" " * ((4 - len(js) % 4) % 4)
    out = struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(b))
    out += struct.pack("<II", len(js), 0x4E4F534A) + js
    out += struct.pack("<II", len(b), 0x004E4942) + bytes(b)
    open(path, "wb").write(out)


def mr_image(j):
    for m in j["materials"]:
        t = m.get("pbrMetallicRoughness", {}).get("metallicRoughnessTexture")
        if t:
            return t["index"]
    raise SystemExit("no metal/roughness map")


def main():
    built, src = sys.argv[1], sys.argv[2]
    sj, sb = read_glb(src)
    tex = sj["textures"][mr_image(sj)]
    img = sj["images"][tex["source"]]
    pixels = Image.open(io.BytesIO(view_bytes(sj, sb, img["bufferView"]))).convert("RGB")
    webp = io.BytesIO()
    pixels.save(webp, "WEBP", lossless=True, quality=100, method=4)
    webp = webp.getvalue()
    assert Image.open(io.BytesIO(webp)).convert("RGB").tobytes() == pixels.tobytes(), "not lossless"

    j, b = read_glb(built)
    ti = mr_image(j)
    old = j["textures"][ti]["source"]
    # the new image at the end of the buffer
    while len(b) % 4:
        b.append(0)
    j["bufferViews"].append({"buffer": 0, "byteOffset": len(b), "byteLength": len(webp)})
    b.extend(webp)
    j["images"].append({"name": "MetalRough", "mimeType": "image/webp",
                        "bufferView": len(j["bufferViews"]) - 1})
    new = len(j["images"]) - 1
    t = j["textures"][ti]
    t.pop("source", None)
    t.setdefault("extensions", {})["EXT_texture_webp"] = {"source": new}
    for key in ("extensionsUsed", "extensionsRequired"):
        j.setdefault(key, [])
        if "EXT_texture_webp" not in j[key]:
            j[key].append("EXT_texture_webp")
    # drop the lossy one if nothing else uses it: its image, and its bytes from
    # the buffer (cut by a multiple of 4, so every view after it stays aligned)
    if not any(tt.get("source") == old for tt in j["textures"]):
        bvi = j["images"][old]["bufferView"]
        bv = j["bufferViews"][bvi]
        cut_o, cut_n = bv.get("byteOffset", 0), bv["byteLength"] // 4 * 4
        b = b[:cut_o] + b[cut_o + cut_n:]
        for v in j["bufferViews"]:
            if v.get("byteOffset", 0) > cut_o:
                v["byteOffset"] -= cut_n
        del j["bufferViews"][bvi]
        for k in ("accessors", "images"):
            for x in j.get(k, []):
                if x.get("bufferView", -1) > bvi:
                    x["bufferView"] -= 1
        del j["images"][old]
        for tt in j["textures"]:
            if tt.get("source", -1) > old:
                tt["source"] -= 1
            w = tt.get("extensions", {}).get("EXT_texture_webp")
            if w and w["source"] > old:
                w["source"] -= 1
    j["buffers"][0]["byteLength"] = len(b)
    write_glb(built, j, b)
    print("%s: metal/roughness now lossless WebP (%d bytes, bit-exact with the source)" % (built, len(webp)))


if __name__ == "__main__":
    main()
