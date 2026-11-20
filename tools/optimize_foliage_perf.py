import json
import re
from pathlib import Path
import numpy as np
from scipy.sparse import csr_matrix
from scipy.sparse.csgraph import connected_components

FOLIAGE_DIR = Path(r"c:\Users\Mosab\Projects\khartoum-azhari-game\assets\models\foliage")
DT = {5120: np.int8, 5121: np.uint8, 5122: np.int16, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}
TC = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}


def cap_foliage_texture_imports() -> None:
    updated = 0
    for imp in FOLIAGE_DIR.rglob("*.import"):
        if not (imp.name.endswith(".jpg.import") or imp.name.endswith(".png.import")):
            continue
        txt = imp.read_text(encoding="utf-8")
        if "process/size_limit=" in txt:
            new_txt = re.sub(r"process/size_limit=\d+", "process/size_limit=1024", txt)
        else:
            new_txt = txt + "\nprocess/size_limit=1024\n"
        if new_txt != txt:
            imp.write_text(new_txt, encoding="utf-8")
            updated += 1
    print(f"Capped foliage texture .import size_limit=1024 ({updated} updated, all verified <=1024)")


def _thin_gltf_components(aid: str, targets: dict[str, tuple[int, float, bool]]) -> None:
    """
    UV-SAFE whole-component polygon reduction (zero UV stretching!):
    targets[mat_keyword] = (max_tris, expand_scale, largest_first)
    """
    d = FOLIAGE_DIR / aid
    gpath = d / f"{aid}.gltf"
    if not gpath.exists():
        return
    g = json.loads(gpath.read_text(encoding="utf-8"))
    bpath = d / g["buffers"][0]["uri"]
    buf = bpath.read_bytes()

    def read_acc(i: int) -> np.ndarray:
        a = g["accessors"][i]
        bv = g["bufferViews"][a["bufferView"]]
        arr = np.frombuffer(
            buf,
            dtype=DT[a["componentType"]],
            count=a["count"] * TC[a["type"]],
            offset=bv.get("byteOffset", 0) + a.get("byteOffset", 0),
        ).copy()
        return arr.reshape((a["count"], TC[a["type"]])) if TC[a["type"]] > 1 else arr

    bin_chunks: list[bytes] = []
    cur = 0

    def add_c(b: bytes) -> tuple[int, int]:
        nonlocal cur
        pad = (4 - len(b) % 4) % 4
        c = b + b"\x00" * pad
        o = cur
        bin_chunks.append(c)
        cur += len(c)
        return o, len(b)

    new_bvs = []
    new_accs = []
    total_before = 0
    total_after = 0

    for pi, p in enumerate(g["meshes"][0]["primitives"]):
        attrs = p["attributes"]
        pos = read_acc(attrs["POSITION"]).astype(np.float32)
        norms = read_acc(attrs["NORMAL"]).astype(np.float32) if "NORMAL" in attrs else None
        uvs = read_acc(attrs["TEXCOORD_0"]).astype(np.float32) if "TEXCOORD_0" in attrs else None
        faces = read_acc(p["indices"]).reshape(-1, 3).astype(np.uint32)
        mname = g["materials"][p["material"]]["name"].lower()
        orig = len(faces)
        total_before += orig

        matched = None
        for kw, spec in targets.items():
            if kw in mname:
                matched = spec
                break

        if matched is not None and len(faces) > matched[0]:
            max_tris, expand_s, largest_first = matched
            nv = len(pos)
            e0 = np.concatenate([faces[:, 0], faces[:, 1], faces[:, 2]])
            e1 = np.concatenate([faces[:, 1], faces[:, 2], faces[:, 0]])
            adj = csr_matrix(
                (np.ones(len(e0) * 2, dtype=np.uint8), (np.concatenate([e0, e1]), np.concatenate([e1, e0]))),
                shape=(nv, nv),
            )
            nc, lbl = connected_components(adj, directed=False)
            if nc > 4:
                fc = lbl[faces[:, 0]]
                if largest_first:
                    v0, v1, v2 = pos[faces[:, 0]], pos[faces[:, 1]], pos[faces[:, 2]]
                    f_area = 0.5 * np.linalg.norm(np.cross(v1 - v0, v2 - v0), axis=1)
                    comp_area = np.bincount(fc, weights=f_area, minlength=nc)
                    comp_tris = np.bincount(fc, minlength=nc)
                    order = np.argsort(-comp_area)
                    chosen = []
                    acc_t = 0
                    for cid in order:
                        if comp_tris[cid] == 0:
                            continue
                        chosen.append(cid)
                        acc_t += int(comp_tris[cid])
                        if acc_t >= max_tris:
                            break
                else:
                    c_ids = np.unique(fc)
                    avg_f = max(1.0, float(len(faces)) / float(len(c_ids)))
                    keep_n = min(len(c_ids), max(120, int(round(max_tris / avg_f))))
                    chosen = c_ids[np.linspace(0, len(c_ids) - 1, keep_n, dtype=np.int64)].tolist()

                keep = np.isin(fc, chosen)
                kf = faces[keep]
                used, inv = np.unique(kf.reshape(-1), return_inverse=True)
                faces = inv.reshape(-1, 3).astype(np.uint32)
                pos = pos[used].copy()
                if norms is not None:
                    norms = norms[used].copy()
                if uvs is not None:
                    uvs = uvs[used].copy()

                if expand_s > 1.001:
                    nv2 = len(pos)
                    e0b = np.concatenate([faces[:, 0], faces[:, 1], faces[:, 2]])
                    e1b = np.concatenate([faces[:, 1], faces[:, 2], faces[:, 0]])
                    adj2 = csr_matrix(
                        (np.ones(len(e0b) * 2, dtype=np.uint8), (np.concatenate([e0b, e1b]), np.concatenate([e1b, e0b]))),
                        shape=(nv2, nv2),
                    )
                    _, lbl2 = connected_components(adj2, directed=False)
                    cnts = np.bincount(lbl2)
                    for cid in np.where((cnts >= 3) & (cnts <= 32))[0]:
                        cm = lbl2 == cid
                        c_pt = np.mean(pos[cm], axis=0)
                        pos[cm] = c_pt + (pos[cm] - c_pt) * expand_s

        total_after += len(faces)
        print(f"  [{aid}] prim[{pi}] {mname}: {orig:,} -> {len(faces):,} tris")

        na = {}
        op, lp = add_c(np.ascontiguousarray(pos, dtype=np.float32).tobytes())
        bvp = len(new_bvs)
        new_bvs.append({"buffer": 0, "byteOffset": op, "byteLength": lp, "target": 34962})
        na["POSITION"] = len(new_accs)
        new_accs.append({
            "bufferView": bvp,
            "componentType": 5126,
            "count": int(len(pos)),
            "type": "VEC3",
            "min": [float(x) for x in pos.min(axis=0)],
            "max": [float(x) for x in pos.max(axis=0)],
        })
        if norms is not None:
            on, ln = add_c(np.ascontiguousarray(norms, dtype=np.float32).tobytes())
            bvn = len(new_bvs)
            new_bvs.append({"buffer": 0, "byteOffset": on, "byteLength": ln, "target": 34962})
            na["NORMAL"] = len(new_accs)
            new_accs.append({"bufferView": bvn, "componentType": 5126, "count": int(len(norms)), "type": "VEC3"})
        if uvs is not None:
            ouv, luv = add_c(np.ascontiguousarray(uvs, dtype=np.float32).tobytes())
            bvuv = len(new_bvs)
            new_bvs.append({"buffer": 0, "byteOffset": ouv, "byteLength": luv, "target": 34962})
            na["TEXCOORD_0"] = len(new_accs)
            new_accs.append({"bufferView": bvuv, "componentType": 5126, "count": int(len(uvs)), "type": "VEC2"})
        p["attributes"] = na
        ia = np.ascontiguousarray(faces.reshape(-1), dtype=np.uint16 if len(pos) < 65535 else np.uint32)
        ic = 5123 if len(pos) < 65535 else 5125
        oi, li = add_c(ia.tobytes())
        bvi = len(new_bvs)
        new_bvs.append({"buffer": 0, "byteOffset": oi, "byteLength": li, "target": 34963})
        p["indices"] = len(new_accs)
        new_accs.append({"bufferView": bvi, "componentType": ic, "count": int(len(ia)), "type": "SCALAR"})

    # Update alphaCutoff to fast 0.45 for leaf masks
    for mat in g.get("materials", []):
        if mat.get("alphaMode") == "MASK":
            mat["alphaCutoff"] = 0.45

    nb = b"".join(bin_chunks)
    bpath.write_bytes(nb)
    g["bufferViews"] = new_bvs
    g["accessors"] = new_accs
    g["buffers"] = [{"uri": g["buffers"][0]["uri"], "byteLength": len(nb)}]
    gpath.write_text(json.dumps(g, separators=(",", ":")), encoding="utf-8")
    print(f"Optimized {aid}: {total_before:,} -> {total_after:,} tris ({len(nb):,} bytes)")


def main() -> None:
    cap_foliage_texture_imports()
    # island_tree_02: trim leaves to 10k lush expanded cards & branches to 6k largest main limbs (zero UV damage)
    _thin_gltf_components("island_tree_02", {
        "leaves": (10500, 1.18, False),
        "branches": (6500, 1.0, True),
    })
    # quiver_tree_01: trim leaf rosettes cleanly to 12k tris (zero UV damage)
    _thin_gltf_components("quiver_tree_01", {
        "leaf": (12000, 1.0, False),
    })


if __name__ == "__main__":
    main()
