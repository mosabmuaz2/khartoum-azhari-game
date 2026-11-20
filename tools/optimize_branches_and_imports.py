import json
import re
from pathlib import Path
import numpy as np
from scipy.sparse import csr_matrix
from scipy.sparse.csgraph import connected_components

FOLIAGE_DIR = Path(r"c:\Users\Mosab\Projects\khartoum-azhari-game\assets\models\foliage")
DT = {5120: np.int8, 5121: np.uint8, 5122: np.int16, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}
TC = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}


def optimize_branches() -> None:
    d = FOLIAGE_DIR / "island_tree_02"
    gpath = d / "island_tree_02.gltf"
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
    for pi, p in enumerate(g["meshes"][0]["primitives"]):
        attrs = p["attributes"]
        pos = read_acc(attrs["POSITION"]).astype(np.float32)
        norms = read_acc(attrs["NORMAL"]).astype(np.float32) if "NORMAL" in attrs else None
        uvs = read_acc(attrs["TEXCOORD_0"]).astype(np.float32) if "TEXCOORD_0" in attrs else None
        faces = read_acc(p["indices"]).reshape(-1, 3).astype(np.uint32)
        mname = g["materials"][p["material"]]["name"].lower()
        orig = len(faces)
        if "branch" in mname and len(faces) > 22000:
            nv = len(pos)
            e0 = np.concatenate([faces[:, 0], faces[:, 1], faces[:, 2]])
            e1 = np.concatenate([faces[:, 1], faces[:, 2], faces[:, 0]])
            adj = csr_matrix(
                (np.ones(len(e0) * 2, dtype=np.uint8), (np.concatenate([e0, e1]), np.concatenate([e1, e0]))),
                shape=(nv, nv),
            )
            nc, lbl = connected_components(adj, directed=False)
            fc = lbl[faces[:, 0]]
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
                if acc_t >= 20000:
                    break
            keep = np.isin(fc, chosen)
            kf = faces[keep]
            used, inv = np.unique(kf.reshape(-1), return_inverse=True)
            faces = inv.reshape(-1, 3).astype(np.uint32)
            pos = pos[used].copy()
            if norms is not None:
                norms = norms[used].copy()
            if uvs is not None:
                uvs = uvs[used].copy()
        print(f"  prim[{pi}] {mname}: {orig:,} -> {len(faces):,} tris")
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

    nb = b"".join(bin_chunks)
    bpath.write_bytes(nb)
    g["bufferViews"] = new_bvs
    g["accessors"] = new_accs
    g["buffers"] = [{"uri": g["buffers"][0]["uri"], "byteLength": len(nb)}]
    gpath.write_text(json.dumps(g, separators=(",", ":")), encoding="utf-8")
    print(f"Saved optimized island_tree_02.bin: {len(nb):,} bytes")


def wire_post_imports() -> None:
    for aid in ("island_tree_02", "quiver_tree_01", "shrub_01", "wild_rooibos_bush"):
        imp = FOLIAGE_DIR / aid / f"{aid}.gltf.import"
        if not imp.exists():
            continue
        txt = imp.read_text(encoding="utf-8")
        if "import_script/path=" in txt:
            txt = re.sub(r'import_script/path="[^"]*"', 'import_script/path="res://scripts/foliage_post_import.gd"', txt)
        else:
            txt += '\nimport_script/path="res://scripts/foliage_post_import.gd"\n'
        imp.write_text(txt, encoding="utf-8")
        print(f"Wired foliage_post_import.gd -> {imp.name}")


if __name__ == "__main__":
    optimize_branches()
    wire_post_imports()
