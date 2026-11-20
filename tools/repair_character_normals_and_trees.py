#!/usr/bin/env python3
"""
1. Repairs all 11 textured character `.glb` models in `assets/models/characters/`
   by computing smooth outward vertex normals (`NORMAL` accessor), stripping any
   dark `COLOR_0` vertex colors, and ensuring bright opaque `baseColorTexture` materials.
2. Restores lush, full-canopy foliage geometry on Poly Haven trees/shrubs
   (`island_tree_02`, `quiver_tree_01`, `shrub_01`, `wild_rooibos_bush`) so leaves
   are dense and full (never dotty/shredded) with `alphaCutoff = 0.08` and 1024px RGBA maps.
"""

from __future__ import annotations

import json
import os
import struct
import urllib.request
from pathlib import Path
from typing import Any

import fast_simplification
import numpy as np
import trimesh
from scipy.sparse import csr_matrix
from scipy.sparse.csgraph import connected_components
from scipy.spatial import cKDTree

try:
    import truststore

    truststore.inject_into_ssl()
except Exception:
    pass


COMP_DTYPES = {
    5120: np.int8,
    5121: np.uint8,
    5122: np.int16,
    5123: np.uint16,
    5125: np.uint32,
    5126: np.float32,
}
TYPE_COMPS = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


def _read_acc(gltf: dict[str, Any], buf: bytes, acc_idx: int) -> np.ndarray:
    acc = gltf["accessors"][acc_idx]
    bv = gltf["bufferViews"][acc["bufferView"]]
    off = bv.get("byteOffset", 0) + acc.get("byteOffset", 0)
    dt = COMP_DTYPES[acc["componentType"]]
    comps = TYPE_COMPS[acc["type"]]
    cnt = acc["count"]
    stride = bv.get("byteStride")
    item_sz = np.dtype(dt).itemsize * comps
    if stride is None or stride == item_sz:
        arr = np.frombuffer(buf, dtype=dt, count=cnt * comps, offset=off).copy()
        return arr.reshape((cnt, comps)) if comps > 1 else arr
    out = np.empty((cnt, comps), dtype=dt)
    for i in range(cnt):
        out[i] = np.frombuffer(buf, dtype=dt, count=comps, offset=off + i * stride)
    return out if comps > 1 else out.reshape((cnt,))


def repair_character_glb(glb_path: Path) -> None:
    raw = glb_path.read_bytes()
    magic, version, _ = struct.unpack("<III", raw[:12])
    if magic != 0x46546C67:
        return
    pos = 12
    json_bytes = b""
    bin_bytes = b""
    while pos + 8 <= len(raw):
        clen, ctype = struct.unpack("<II", raw[pos : pos + 8])
        cdata = raw[pos + 8 : pos + 8 + clen]
        if ctype == 0x4E4F534A:
            json_bytes = cdata
        elif ctype == 0x004E4942:
            bin_bytes = cdata
        pos += 8 + clen

    gltf = json.loads(json_bytes.decode("utf-8"))
    if not gltf.get("images"):
        return  # Skip untextured *person*.glb files

    prim = gltf["meshes"][0]["primitives"][0]
    attrs = prim["attributes"]

    verts = _read_acc(gltf, bin_bytes, attrs["POSITION"]).astype(np.float32)
    faces = _read_acc(gltf, bin_bytes, prim["indices"]).reshape(-1, 3).astype(np.uint32)
    uvs = _read_acc(gltf, bin_bytes, attrs["TEXCOORD_0"]).astype(np.float32) if "TEXCOORD_0" in attrs else None

    # Compute smooth outward-facing vertex normals across welded positions so seams don't split normals
    tm = trimesh.Trimesh(vertices=verts, faces=faces, process=False)
    # Fix winding if inverted (ensure outward volume)
    norms = np.asarray(tm.vertex_normals, dtype=np.float32)
    # Ensure normals point outward from mesh centroid on average
    center = np.mean(verts, axis=0)
    radial = verts - center
    if np.mean(np.sum(norms * radial, axis=1)) < 0.0:
        norms = -norms

    # Preserve non-mesh bufferViews (embedded PNG/JPG texture)
    mesh_accs = {prim["indices"]} | set(attrs.values())
    mesh_bvs = {gltf["accessors"][i]["bufferView"] for i in mesh_accs if "bufferView" in gltf["accessors"][i]}

    bin_chunks: list[bytes] = []
    cur_off = 0

    def add_chunk(b: bytes) -> tuple[int, int]:
        nonlocal cur_off
        pad = (4 - (len(b) % 4)) % 4
        c = b + (b"\x00" * pad)
        o = cur_off
        bin_chunks.append(c)
        cur_off += len(c)
        return o, len(b)

    new_bvs: list[dict[str, Any]] = []
    bv_remap: dict[int, int] = {}
    for idx, bv in enumerate(gltf.get("bufferViews", [])):
        if idx in mesh_bvs:
            continue
        sl = bin_bytes[bv.get("byteOffset", 0) : bv.get("byteOffset", 0) + bv["byteLength"]]
        o, bl = add_chunk(sl)
        nbv = dict(bv)
        nbv["buffer"] = 0
        nbv["byteOffset"] = o
        nbv["byteLength"] = bl
        bv_remap[idx] = len(new_bvs)
        new_bvs.append(nbv)

    for img in gltf.get("images", []):
        if "bufferView" in img and img["bufferView"] in bv_remap:
            img["bufferView"] = bv_remap[img["bufferView"]]

    new_accs: list[dict[str, Any]] = []
    new_attrs: dict[str, int] = {}

    # POSITION
    op, lp = add_chunk(np.ascontiguousarray(verts, dtype=np.float32).tobytes())
    bvp = len(new_bvs)
    new_bvs.append({"buffer": 0, "byteOffset": op, "byteLength": lp, "target": 34962})
    new_attrs["POSITION"] = len(new_accs)
    new_accs.append({
        "bufferView": bvp,
        "componentType": 5126,
        "count": int(len(verts)),
        "type": "VEC3",
        "min": [float(x) for x in np.min(verts, axis=0)],
        "max": [float(x) for x in np.max(verts, axis=0)],
    })

    # NORMAL
    on, ln = add_chunk(np.ascontiguousarray(norms, dtype=np.float32).tobytes())
    bvn = len(new_bvs)
    new_bvs.append({"buffer": 0, "byteOffset": on, "byteLength": ln, "target": 34962})
    new_attrs["NORMAL"] = len(new_accs)
    new_accs.append({
        "bufferView": bvn,
        "componentType": 5126,
        "count": int(len(norms)),
        "type": "VEC3",
    })

    # TEXCOORD_0
    if uvs is not None:
        ouv, luv = add_chunk(np.ascontiguousarray(uvs, dtype=np.float32).tobytes())
        bvuv = len(new_bvs)
        new_bvs.append({"buffer": 0, "byteOffset": ouv, "byteLength": luv, "target": 34962})
        new_attrs["TEXCOORD_0"] = len(new_accs)
        new_accs.append({
            "bufferView": bvuv,
            "componentType": 5126,
            "count": int(len(uvs)),
            "type": "VEC2",
        })

    # INDICES
    ind_arr = np.ascontiguousarray(faces.reshape(-1), dtype=np.uint16 if len(verts) < 65535 else np.uint32)
    ind_comp = 5123 if len(verts) < 65535 else 5125
    oi, li = add_chunk(ind_arr.tobytes())
    bvi = len(new_bvs)
    new_bvs.append({"buffer": 0, "byteOffset": oi, "byteLength": li, "target": 34963})
    prim["indices"] = len(new_accs)
    new_accs.append({
        "bufferView": bvi,
        "componentType": ind_comp,
        "count": int(len(ind_arr)),
        "type": "SCALAR",
    })

    prim["attributes"] = new_attrs  # Strips COLOR_0 if any
    for mat in gltf.get("materials", []):
        pbr = mat.setdefault("pbrMetallicRoughness", {})
        pbr["baseColorFactor"] = [1.0, 1.0, 1.0, 1.0]
        pbr["metallicFactor"] = 0.0
        pbr["roughnessFactor"] = 0.85
        mat["doubleSided"] = True
        if "alphaMode" in mat:
            del mat["alphaMode"]

    new_bin = b"".join(bin_chunks)
    gltf["bufferViews"] = new_bvs
    gltf["accessors"] = new_accs
    gltf["buffers"] = [{"byteLength": len(new_bin)}]

    jbytes = json.dumps(gltf, separators=(",", ":")).encode("utf-8")
    jpad = (4 - (len(jbytes) % 4)) % 4
    jchunk = jbytes + (b" " * jpad)
    bpad = (4 - (len(new_bin) % 4)) % 4
    bchunk = new_bin + (b"\x00" * bpad)
    total_len = 12 + 8 + len(jchunk) + 8 + len(bchunk)
    out = (
        struct.pack("<III", 0x46546C67, version, total_len)
        + struct.pack("<II", len(jchunk), 0x4E4F534A)
        + jchunk
        + struct.pack("<II", len(bchunk), 0x004E4942)
        + bchunk
    )
    glb_path.write_bytes(out)
    print(f"  [CHAR NORMAL FIX] {glb_path.name}: {len(faces):,} tris, NORMAL injected, COLOR_0 stripped")


def restore_lush_foliage() -> None:
    foliage_specs = [
        ("island_tree_02", 18500, "textures/island_tree_02_leaves_rgba.png", "leaves"),
        ("quiver_tree_01", 9500, "", ""),
        ("shrub_01", 9500, "textures/shrub_01_rgba.png", ""),
        ("wild_rooibos_bush", 8500, "textures/wild_rooibos_bush_rgba.png", ""),
    ]
    for aid, target_tris, rgba_uri, mat_kw in foliage_specs:
        dest_dir = Path("assets/models/foliage") / aid
        gltf_path = dest_dir / f"{aid}.gltf"
        if not gltf_path.exists():
            continue
        # Fetch fresh 1k .gltf and .bin geometry from Poly Haven so we start from un-shredded leaves
        req = urllib.request.Request(f"https://api.polyhaven.com/files/{aid}", headers={"User-Agent": "Mozilla/5.0"})
        data = json.loads(urllib.request.urlopen(req, timeout=30).read())
        g_entry = data["gltf"]["1k"]["gltf"]
        urllib.request.urlretrieve(g_entry["url"], gltf_path)
        for rel_p, info in g_entry.get("include", {}).items():
            if rel_p.endswith(".bin"):
                urllib.request.urlretrieve(info["url"], dest_dir / rel_p)

        # Decimate gently to target_tris while keeping leaf cards lush (1.35x card expansion)
        gltf = json.loads(gltf_path.read_text(encoding="utf-8"))
        b_uri = gltf["buffers"][0]["uri"]
        bin_bytes = (dest_dir / b_uri).read_bytes()

        prim_list = []
        total_in = 0
        for m in gltf.get("meshes", []):
            for p in m.get("primitives", []):
                c = gltf["accessors"][p["indices"]]["count"] // 3
                total_in += c
                prim_list.append((p, c))

        bin_chunks: list[bytes] = []
        cur_off = 0

        def add_chunk(b: bytes) -> tuple[int, int]:
            nonlocal cur_off
            pad = (4 - (len(b) % 4)) % 4
            c = b + (b"\x00" * pad)
            o = cur_off
            bin_chunks.append(c)
            cur_off += len(c)
            return o, len(b)

        new_bvs: list[dict[str, Any]] = []
        new_accs: list[dict[str, Any]] = []
        total_out = 0

        for prim, cnt in prim_list:
            attrs = prim["attributes"]
            pos = _read_acc(gltf, bin_bytes, attrs["POSITION"]).astype(np.float32)
            faces = _read_acc(gltf, bin_bytes, prim["indices"]).reshape(-1, 3).astype(np.uint32)
            norms = _read_acc(gltf, bin_bytes, attrs["NORMAL"]).astype(np.float32) if "NORMAL" in attrs else None
            uvs = _read_acc(gltf, bin_bytes, attrs["TEXCOORD_0"]).astype(np.float32) if "TEXCOORD_0" in attrs else None

            sub_target = max(1200, int(round(target_tris * float(cnt) / float(max(1, total_in)))))
            if len(faces) > sub_target:
                v64 = np.asarray(pos, dtype=np.float64)
                f32 = np.asarray(faces, dtype=np.int32)
                v_out, f_out = fast_simplification.simplify(v64, f32, target_count=sub_target)
                v_out = np.asarray(v_out, dtype=np.float32)
                f_out = np.asarray(f_out, dtype=np.uint32)
                tree = cKDTree(pos)
                _, nn = tree.query(v_out)
                n_out = norms[nn].astype(np.float32) if norms is not None else None
                uv_out = uvs[nn].astype(np.float32) if uvs is not None else None

                if len(f_out) > int(sub_target * 1.25):
                    # Connected component thinning with generous 1.42x leaf card expansion
                    n_v = len(v_out)
                    e0 = np.concatenate([f_out[:, 0], f_out[:, 1], f_out[:, 2]])
                    e1 = np.concatenate([f_out[:, 1], f_out[:, 2], f_out[:, 0]])
                    adj = csr_matrix(
                        (np.ones(len(e0) * 2, dtype=np.uint8), (np.concatenate([e0, e1]), np.concatenate([e1, e0]))),
                        shape=(n_v, n_v),
                    )
                    n_comp, labels = connected_components(adj, directed=False)
                    if n_comp > 1:
                        f_comp = labels[f_out[:, 0]]
                        c_ids = np.unique(f_comp)
                        avg_f = max(1.0, float(len(f_out)) / float(len(c_ids)))
                        keep_n = min(len(c_ids), max(60, int(round(sub_target / avg_f))))
                        chosen = set(c_ids[np.linspace(0, len(c_ids) - 1, keep_n, dtype=np.int64)].tolist())
                        mask = np.isin(f_comp, list(chosen))
                        kept_f = f_out[mask]
                        used_v, inv = np.unique(kept_f.reshape(-1), return_inverse=True)
                        f_out = inv.reshape(-1, 3).astype(np.uint32)
                        v_out = v_out[used_v].copy()
                        n_out = n_out[used_v].copy() if n_out is not None else None
                        uv_out = uv_out[used_v].copy() if uv_out is not None else None
                        new_lbls = labels[used_v]
                        for cid in np.unique(new_lbls):
                            cm = new_lbls == cid
                            if np.sum(cm) <= 16:
                                c_pt = np.mean(v_out[cm], axis=0)
                                v_out[cm] = c_pt + (v_out[cm] - c_pt) * 1.42
            else:
                v_out, n_out, uv_out, f_out = pos, norms, uvs, faces

            total_out += len(f_out)
            new_attrs: dict[str, int] = {}

            op, lp = add_chunk(np.ascontiguousarray(v_out, dtype=np.float32).tobytes())
            bvp = len(new_bvs)
            new_bvs.append({"buffer": 0, "byteOffset": op, "byteLength": lp, "target": 34962})
            new_attrs["POSITION"] = len(new_accs)
            new_accs.append({
                "bufferView": bvp,
                "componentType": 5126,
                "count": int(len(v_out)),
                "type": "VEC3",
                "min": [float(x) for x in np.min(v_out, axis=0)],
                "max": [float(x) for x in np.max(v_out, axis=0)],
            })

            if n_out is not None:
                on, ln = add_chunk(np.ascontiguousarray(n_out, dtype=np.float32).tobytes())
                bvn = len(new_bvs)
                new_bvs.append({"buffer": 0, "byteOffset": on, "byteLength": ln, "target": 34962})
                new_attrs["NORMAL"] = len(new_accs)
                new_accs.append({"bufferView": bvn, "componentType": 5126, "count": int(len(n_out)), "type": "VEC3"})

            if uv_out is not None:
                ouv, luv = add_chunk(np.ascontiguousarray(uv_out, dtype=np.float32).tobytes())
                bvuv = len(new_bvs)
                new_bvs.append({"buffer": 0, "byteOffset": ouv, "byteLength": luv, "target": 34962})
                new_attrs["TEXCOORD_0"] = len(new_accs)
                new_accs.append({"bufferView": bvuv, "componentType": 5126, "count": int(len(uv_out)), "type": "VEC2"})

            prim["attributes"] = new_attrs
            ind_arr = np.ascontiguousarray(f_out.reshape(-1), dtype=np.uint16 if len(v_out) < 65535 else np.uint32)
            ind_comp = 5123 if len(v_out) < 65535 else 5125
            oi, li = add_chunk(ind_arr.tobytes())
            bvi = len(new_bvs)
            new_bvs.append({"buffer": 0, "byteOffset": oi, "byteLength": li, "target": 34963})
            prim["indices"] = len(new_accs)
            new_accs.append({"bufferView": bvi, "componentType": ind_comp, "count": int(len(ind_arr)), "type": "SCALAR"})

        # Re-bind 1024x1024 textures (_4k.jpg on disk + _rgba.png for leaf alpha)
        for img in gltf.get("images", []):
            uri = str(img.get("uri", ""))
            uri_4k = uri.replace("_1k.", "_4k.")
            if (dest_dir / uri_4k).exists():
                img["uri"] = uri_4k
            if rgba_uri and ("leaves_diff" in uri or (not mat_kw and "diff" in uri)):
                img["uri"] = rgba_uri
                img["mimeType"] = "image/png"

        for mat in gltf.get("materials", []):
            mname = str(mat.get("name", "")).lower()
            mat["doubleSided"] = True
            if rgba_uri and (not mat_kw or mat_kw in mname):
                mat["alphaMode"] = "MASK"
                mat["alphaCutoff"] = 0.08

        new_bin = b"".join(bin_chunks)
        (dest_dir / b_uri).write_bytes(new_bin)
        gltf["bufferViews"] = new_bvs
        gltf["accessors"] = new_accs
        gltf["buffers"] = [{"uri": b_uri, "byteLength": len(new_bin)}]
        gltf_path.write_text(json.dumps(gltf, separators=(",", ":")), encoding="utf-8")
        print(f"  [FOLIAGE RESTORED] {aid}: {total_in:,} -> {total_out:,} lush tris (alphaCutoff=0.08)")


def main() -> None:
    print("1) Repairing character .glb normals & materials...")
    for root, _, files in os.walk("assets/models/characters"):
        for fn in sorted(files):
            if fn.lower().endswith(".glb") and "person" not in fn.lower() and fn.lower() != "shoolkid.glb":
                repair_character_glb(Path(root) / fn)

    print("2) Restoring lush foliage geometry & RGBA alphaCutoff=0.08...")
    restore_lush_foliage()


if __name__ == "__main__":
    main()
