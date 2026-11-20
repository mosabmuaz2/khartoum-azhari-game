#!/usr/bin/env python3
"""
Repairs imported Poly Haven 4K trees (`island_tree_02`, `quiver_tree_01`) and shrubs
(`shrub_01`, `wild_rooibos_bush`) for Godot 4.7.2:
1. Restores un-corrupted original glTF geometry (eliminating cKDTree nearest-neighbor UV
   corruption that caused bark-on-leaf cards and shredded floating triangles).
2. Removes the flat grey/white circular ground-pedestal base skirt from `island_tree_02`
   trunk (`prim 0`) without touching bark or foliage.
3. Cleans black scan-bar artifacts from `island_tree_02_leaves_rgba.png` and applies
   12-pass RGB edge dilation into transparent pixels so mipmaps stay lush green at all distances.
4. Enforces clean material assignments: bark strictly on trunk/branches, RGBA cutout leaves
   on leaf cards (`alphaMode: MASK`, `alphaCutoff: 0.35`, `doubleSided: true`), and opaque
   succulent rosettes on `quiver_tree_01_leaf` (removing broken `BLEND` on JPG).
"""

from __future__ import annotations

import json
import urllib.request
from pathlib import Path
from typing import Any

import numpy as np
from PIL import Image
from scipy.sparse import csr_matrix
from scipy.sparse.csgraph import connected_components

try:
    import truststore

    truststore.inject_into_ssl()
except Exception:
    pass

PROJECT_ROOT = Path(r"c:\Users\Mosab\Projects\khartoum-azhari-game")
FOLIAGE_DIR = PROJECT_ROOT / "assets" / "models" / "foliage"

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


def bleed_rgb_into_transparent(rgb: np.ndarray, alpha: np.ndarray, passes: int = 14) -> np.ndarray:
    """Propagate lush leaf green RGB out into alpha==0 pixels so mipmaps never darken/erode."""
    out = rgb.copy()
    opaque = alpha > 40
    for _ in range(passes):
        if np.all(opaque):
            break
        shifted_colors = []
        shifted_masks = []
        for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1)):
            shifted_colors.append(np.roll(np.roll(out, dy, axis=0), dx, axis=1))
            shifted_masks.append(np.roll(np.roll(opaque, dy, axis=0), dx, axis=1))
        any_n = shifted_masks[0] | shifted_masks[1] | shifted_masks[2] | shifted_masks[3]
        fill = (~opaque) & any_n
        if not np.any(fill):
            break
        accum = np.zeros_like(out, dtype=np.float32)
        cnt = np.zeros(alpha.shape, dtype=np.float32)
        for sc, sm in zip(shifted_colors, shifted_masks):
            w = sm.astype(np.float32)
            accum += sc.astype(np.float32) * w[:, :, None]
            cnt += w
        out[fill] = np.clip(accum[fill] / np.maximum(1.0, cnt[fill])[:, None], 0, 255).astype(np.uint8)
        opaque = opaque | fill
    # Fill any remaining deep transparent pixels with median leaf green so distant mipmaps stay green
    if np.any(~opaque) and np.any(alpha > 120):
        med = np.median(rgb[alpha > 120], axis=0).astype(np.uint8)
        out[~opaque] = med
    return out


def clean_leaf_rgba_texture(rgba_path: Path, diff_path: Path) -> None:
    """Remove black scan-bar artifacts from leaf RGBA and apply clean green RGB edge bleed."""
    if not rgba_path.exists():
        return
    with Image.open(rgba_path) as im:
        rgba = np.asarray(im.convert("RGBA"), dtype=np.uint8).copy()

    rgb = rgba[:, :, :3]
    alpha = rgba[:, :, 3]

    # Detect solid black scan-bar artifacts inside alpha > 0 (black pixels with R,G,B < 24 and low saturation)
    max_c = np.max(rgb, axis=2)
    black_bars = (alpha > 20) & (max_c < 24)
    removed_px = int(np.sum(black_bars))
    alpha[black_bars] = 0

    # Also boost subtle leaf vibrancy slightly so sunlit Sudanese canopy looks rich & alive
    if diff_path.exists():
        with Image.open(diff_path) as dim:
            diff_rgb = np.asarray(dim.convert("RGB").resize((rgb.shape[1], rgb.shape[0]), Image.Resampling.LANCZOS), dtype=np.uint8)
        # Keep true leaf pixels from diff_rgb where alpha > 40 and not black
        valid_leaf = (alpha > 40) & (np.max(diff_rgb, axis=2) >= 24)
        rgb[valid_leaf] = diff_rgb[valid_leaf]

    bled_rgb = bleed_rgb_into_transparent(rgb, alpha, passes=16)
    out = np.dstack([bled_rgb, alpha])
    Image.fromarray(out, mode="RGBA").save(rgba_path, optimize=True)
    print(f"  [RGBA CLEAN] {rgba_path.name}: stripped {removed_px} black scan-bar px, 16-pass green edge bleed, opaque%={100.0 * np.mean(alpha > 90):.1f}%")


def _keep_faces_uv_safe(
    pos: np.ndarray,
    norms: np.ndarray | None,
    uvs: np.ndarray | None,
    faces: np.ndarray,
    keep_mask: np.ndarray,
) -> tuple[np.ndarray, np.ndarray | None, np.ndarray | None, np.ndarray]:
    kept_f = faces[keep_mask]
    if len(kept_f) == 0:
        return pos, norms, uvs, faces
    used_v, inv = np.unique(kept_f.reshape(-1), return_inverse=True)
    new_f = inv.reshape(-1, 3).astype(np.uint32)
    new_p = pos[used_v].copy()
    new_n = norms[used_v].copy() if norms is not None else None
    new_uv = uvs[used_v].copy() if uvs is not None else None
    return new_p, new_n, new_uv, new_f


def _thin_whole_components(
    pos: np.ndarray,
    norms: np.ndarray | None,
    uvs: np.ndarray | None,
    faces: np.ndarray,
    max_tris: int,
    expand_leaf_cards: float = 1.0,
) -> tuple[np.ndarray, np.ndarray | None, np.ndarray | None, np.ndarray]:
    """
    UV-SAFE thinning: drops whole disconnected leaf-card components evenly across the canopy
    without EVER altering or merging vertices/UVs within a kept leaf card!
    """
    if len(faces) <= max_tris:
        return pos, norms, uvs, faces

    n_v = len(pos)
    e0 = np.concatenate([faces[:, 0], faces[:, 1], faces[:, 2]])
    e1 = np.concatenate([faces[:, 1], faces[:, 2], faces[:, 0]])
    adj = csr_matrix(
        (np.ones(len(e0) * 2, dtype=np.uint8), (np.concatenate([e0, e1]), np.concatenate([e1, e0]))),
        shape=(n_v, n_v),
    )
    n_comp, labels = connected_components(adj, directed=False)
    if n_comp <= 4:
        return pos, norms, uvs, faces

    f_comp = labels[faces[:, 0]]
    c_ids = np.unique(f_comp)
    avg_f = max(1.0, float(len(faces)) / float(len(c_ids)))
    keep_n = min(len(c_ids), max(120, int(round(max_tris / avg_f))))
    # Deterministic uniform stride across all leaf components so canopy stays evenly dense
    chosen = set(c_ids[np.linspace(0, len(c_ids) - 1, keep_n, dtype=np.int64)].tolist())
    keep_mask = np.isin(f_comp, list(chosen))
    new_p, new_n, new_uv, new_f = _keep_faces_uv_safe(pos, norms, uvs, faces, keep_mask)

    # Slight optional scale-up of kept leaf cards around their own centroid to keep canopy lush
    if expand_leaf_cards > 1.001:
        n_v2 = len(new_p)
        e0b = np.concatenate([new_f[:, 0], new_f[:, 1], new_f[:, 2]])
        e1b = np.concatenate([new_f[:, 1], new_f[:, 2], new_f[:, 0]])
        adj2 = csr_matrix(
            (np.ones(len(e0b) * 2, dtype=np.uint8), (np.concatenate([e0b, e1b]), np.concatenate([e1b, e0b]))),
            shape=(n_v2, n_v2),
        )
        _, lbl2 = connected_components(adj2, directed=False)
        counts = np.bincount(lbl2)
        for cid in np.where((counts >= 3) & (counts <= 32))[0]:
            cm = lbl2 == cid
            c_pt = np.mean(new_p[cm], axis=0)
            new_p[cm] = c_pt + (new_p[cm] - c_pt) * expand_leaf_cards

    return new_p, new_n, new_uv, new_f


def _strip_ground_pedestal(
    pos: np.ndarray,
    norms: np.ndarray | None,
    uvs: np.ndarray | None,
    faces: np.ndarray,
    bark_img_path: Path | None,
) -> tuple[np.ndarray, np.ndarray | None, np.ndarray | None, np.ndarray, int]:
    """
    Removes flat grey/white circular ground-pedestal/sand skirt triangles at the bottom of
    photogrammetry trunks (`island_tree_02`), detected both geometrically (low Y + flat normal
    or wide flared bottom ring) and by pale neutral-grey UV color on the bark atlas.
    """
    v0, v1, v2 = pos[faces[:, 0]], pos[faces[:, 1]], pos[faces[:, 2]]
    tri_y = (v0[:, 1] + v1[:, 1] + v2[:, 1]) / 3.0
    tri_min_y = np.minimum(np.minimum(v0[:, 1], v1[:, 1]), v2[:, 1])
    fn = np.cross(v1 - v0, v2 - v0)
    fn_y = np.abs(fn[:, 1] / (np.linalg.norm(fn, axis=1) + 1e-9))

    # Trunk center estimated from mid-trunk vertices (y in [0.4, 1.2])
    mid_mask = (pos[:, 1] >= 0.35) & (pos[:, 1] <= 1.25)
    if np.any(mid_mask):
        trunk_cx = float(np.median(pos[mid_mask, 0]))
        trunk_cz = float(np.median(pos[mid_mask, 2]))
    else:
        trunk_cx, trunk_cz = 0.0, 0.0

    tri_cx = (v0[:, 0] + v1[:, 0] + v2[:, 0]) / 3.0
    tri_cz = (v0[:, 2] + v1[:, 2] + v2[:, 2]) / 3.0
    tri_r = np.sqrt((tri_cx - trunk_cx) ** 2 + (tri_cz - trunk_cz) ** 2)

    # Geometric pedestal: flat near-ground skirt triangles or wide flared base flange
    is_pedestal = ((tri_y < 0.14) & (fn_y > 0.58)) | ((tri_min_y < 0.07) & (tri_r > 0.24))

    # Texture-based check: Poly Haven sand/concrete base skirt in island_tree_02_diff_4k.jpg is
    # bright neutral grey (high brightness > 125, very low color saturation |R-B| < 18) near bottom
    if uvs is not None and bark_img_path is not None and bark_img_path.exists():
        with Image.open(bark_img_path) as bim:
            barr = np.asarray(bim.convert("RGB"), dtype=np.int16)
        h, w, _ = barr.shape
        uv_c = (uvs[faces[:, 0]] + uvs[faces[:, 1]] + uvs[faces[:, 2]]) / 3.0
        px = np.clip((np.mod(uv_c[:, 0], 1.0) * (w - 1)).astype(np.int32), 0, w - 1)
        py = np.clip((np.mod(uv_c[:, 1], 1.0) * (h - 1)).astype(np.int32), 0, h - 1)
        cols = barr[py, px]
        luma = (cols[:, 0] + cols[:, 1] + cols[:, 2]) / 3.0
        sat = np.max(cols, axis=1) - np.min(cols, axis=1)
        # Pale grey sand/pedestal OR dark charcoal border patch near bottom of trunk
        is_grey_base = (tri_y < 0.24) & (((luma > 125) & (sat < 16)) | ((luma < 48) & (sat < 12)))
        is_pedestal = is_pedestal | is_grey_base

    removed = int(np.sum(is_pedestal))
    if removed == 0:
        return pos, norms, uvs, faces, 0

    keep = ~is_pedestal
    new_p, new_n, new_uv, new_f = _keep_faces_uv_safe(pos, norms, uvs, faces, keep)
    return new_p, new_n, new_uv, new_f, removed


def repair_tree_asset(
    aid: str,
    rgba_uri: str,
    leaf_mat_kw: str,
    max_leaf_tris: int,
    expand_leaf_cards: float,
    strip_pedestal: bool,
    opaque_leaves: bool,
) -> None:
    dest_dir = FOLIAGE_DIR / aid
    gltf_path = dest_dir / f"{aid}.gltf"
    if not gltf_path.exists():
        print(f"SKIP missing {gltf_path}")
        return

    print(f"=== Repairing {aid} ===")
    # 1. Fetch clean original 1k glTF + .bin from Poly Haven (zero UV corruption!)
    req = urllib.request.Request(f"https://api.polyhaven.com/files/{aid}", headers={"User-Agent": "Mozilla/5.0"})
    data = json.loads(urllib.request.urlopen(req, timeout=30).read())
    g_entry = data["gltf"]["1k"]["gltf"]
    urllib.request.urlretrieve(g_entry["url"], gltf_path)
    for rel_p, info in g_entry.get("include", {}).items():
        if rel_p.endswith(".bin"):
            urllib.request.urlretrieve(info["url"], dest_dir / rel_p)

    # 2. Clean RGBA leaf texture if applicable
    if rgba_uri:
        rgba_p = dest_dir / rgba_uri
        diff_cand = dest_dir / "textures" / f"{aid}_leaves_diff_4k.jpg"
        if not diff_cand.exists():
            diff_cand = dest_dir / "textures" / f"{aid}_diff_4k.jpg"
        clean_leaf_rgba_texture(rgba_p, diff_cand)

    gltf = json.loads(gltf_path.read_text(encoding="utf-8"))
    b_uri = gltf["buffers"][0]["uri"]
    bin_bytes = (dest_dir / b_uri).read_bytes()

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

    bark_tex = dest_dir / "textures" / f"{aid}_diff_4k.jpg"
    if not bark_tex.exists():
        bark_tex = dest_dir / "textures" / f"{aid}_trunk_diff_4k.jpg"

    for mesh in gltf.get("meshes", []):
        for pi, prim in enumerate(mesh.get("primitives", [])):
            attrs = prim["attributes"]
            mat_idx = prim.get("material", 0)
            mname = str(gltf["materials"][mat_idx].get("name", "")).lower()
            is_leaf = (leaf_mat_kw != "" and leaf_mat_kw in mname) or (leaf_mat_kw == "" and "trunk" not in mname and "branch" not in mname)
            is_trunk = ("trunk" in mname) or (mname == aid.lower())

            pos = _read_acc(gltf, bin_bytes, attrs["POSITION"]).astype(np.float32)
            faces = _read_acc(gltf, bin_bytes, prim["indices"]).reshape(-1, 3).astype(np.uint32)
            norms = _read_acc(gltf, bin_bytes, attrs["NORMAL"]).astype(np.float32) if "NORMAL" in attrs else None
            uvs = _read_acc(gltf, bin_bytes, attrs["TEXCOORD_0"]).astype(np.float32) if "TEXCOORD_0" in attrs else None
            orig_tris = len(faces)

            if strip_pedestal and is_trunk:
                pos, norms, uvs, faces, ped_rm = _strip_ground_pedestal(pos, norms, uvs, faces, bark_tex)
                print(f"  prim[{pi}] ({mname}): stripped {ped_rm} ground-pedestal tris ({orig_tris} -> {len(faces)})")

            if is_leaf and max_leaf_tris > 0 and len(faces) > max_leaf_tris:
                pos, norms, uvs, faces = _thin_whole_components(
                    pos, norms, uvs, faces, max_leaf_tris, expand_leaf_cards=expand_leaf_cards
                )

            # Verify zero UV corruption on kept triangles
            uv_bad = 0
            if uvs is not None:
                uv0, uv1, uv2 = uvs[faces[:, 0]], uvs[faces[:, 1]], uvs[faces[:, 2]]
                uv_edge = np.maximum(np.linalg.norm(uv1 - uv0, axis=1), np.linalg.norm(uv2 - uv0, axis=1))
                uv_bad = int(np.sum(uv_edge > 0.45))

            print(f"  prim[{pi}] ({mname}): {orig_tris:,} -> {len(faces):,} tris, verts={len(pos):,}, uv_stretched={uv_bad}")

            new_attrs: dict[str, int] = {}
            op, lp = add_chunk(np.ascontiguousarray(pos, dtype=np.float32).tobytes())
            bvp = len(new_bvs)
            new_bvs.append({"buffer": 0, "byteOffset": op, "byteLength": lp, "target": 34962})
            new_attrs["POSITION"] = len(new_accs)
            new_accs.append({
                "bufferView": bvp,
                "componentType": 5126,
                "count": int(len(pos)),
                "type": "VEC3",
                "min": [float(x) for x in np.min(pos, axis=0)],
                "max": [float(x) for x in np.max(pos, axis=0)],
            })

            if norms is not None:
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

            prim["attributes"] = new_attrs
            ind_arr = np.ascontiguousarray(faces.reshape(-1), dtype=np.uint16 if len(pos) < 65535 else np.uint32)
            ind_comp = 5123 if len(pos) < 65535 else 5125
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

    # Re-bind our local high-res textures & clean RGBA alpha leaf texture
    for img in gltf.get("images", []):
        uri = str(img.get("uri", ""))
        uri_4k = uri.replace("_1k.", "_4k.")
        if (dest_dir / uri_4k).exists():
            img["uri"] = uri_4k
        if rgba_uri and ("leaves_diff" in uri or (leaf_mat_kw == "" and "diff" in uri)):
            img["uri"] = rgba_uri
            img["mimeType"] = "image/png"

    for mat in gltf.get("materials", []):
        mname = str(mat.get("name", "")).lower()
        pbr = mat.setdefault("pbrMetallicRoughness", {})
        pbr["metallicFactor"] = 0.0
        is_leaf_mat = (leaf_mat_kw != "" and leaf_mat_kw in mname) or (leaf_mat_kw == "" and "trunk" not in mname and "branch" not in mname)
        if is_leaf_mat:
            mat["doubleSided"] = True
            pbr["roughnessFactor"] = 0.85
            if opaque_leaves:
                mat.pop("alphaMode", None)
                mat.pop("alphaCutoff", None)
            elif rgba_uri:
                mat["alphaMode"] = "MASK"
                mat["alphaCutoff"] = 0.35
        else:
            # Trunk / branch bark: opaque matte bark ONLY
            mat["doubleSided"] = False
            pbr["roughnessFactor"] = 0.90
            mat.pop("alphaMode", None)
            mat.pop("alphaCutoff", None)

    new_bin = b"".join(bin_chunks)
    (dest_dir / b_uri).write_bytes(new_bin)
    gltf["bufferViews"] = new_bvs
    gltf["accessors"] = new_accs
    gltf["buffers"] = [{"uri": b_uri, "byteLength": len(new_bin)}]
    gltf_path.write_text(json.dumps(gltf, separators=(",", ":")), encoding="utf-8")
    print(f"  [SAVED] {gltf_path.name} ({len(new_bin):,} bytes)")


def main() -> None:
    # 1. island_tree_02: keep lush whole-leaf cards (no UV corruption), strip ground pedestal, clean RGBA
    repair_tree_asset(
        aid="island_tree_02",
        rgba_uri="textures/island_tree_02_leaves_rgba.png",
        leaf_mat_kw="leaves",
        max_leaf_tris=28000,
        expand_leaf_cards=1.18,
        strip_pedestal=True,
        opaque_leaves=False,
    )
    # 2. quiver_tree_01: keep clean original 3D succulent rosettes (OPAQUE, zero bark-on-leaf UVs!)
    repair_tree_asset(
        aid="quiver_tree_01",
        rgba_uri="",
        leaf_mat_kw="leaf",
        max_leaf_tris=18000,
        expand_leaf_cards=1.0,
        strip_pedestal=True,
        opaque_leaves=True,
    )
    # 3. Clean shrubs to alphaCutoff=0.35 as well
    for shrub_id in ("shrub_01", "wild_rooibos_bush"):
        gpath = FOLIAGE_DIR / shrub_id / f"{shrub_id}.gltf"
        if gpath.exists():
            g = json.loads(gpath.read_text(encoding="utf-8"))
            for mat in g.get("materials", []):
                mat["alphaMode"] = "MASK"
                mat["alphaCutoff"] = 0.35
                mat["doubleSided"] = True
            gpath.write_text(json.dumps(g, separators=(",", ":")), encoding="utf-8")
            print(f"=== Updated {shrub_id} alphaCutoff=0.35 ===")


if __name__ == "__main__":
    main()
