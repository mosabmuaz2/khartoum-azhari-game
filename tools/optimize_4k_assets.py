#!/usr/bin/env python3
"""
Complete Texture Downscaling, Godot Import Optimization & UV-Preserving Mesh Decimation
for the Al-Azhari (Khartoum) Godot 4.7.2 Project.

1. Texture Downscaling (`Pillow` LANCZOS):
   - `assets/models/**`: downscales textures > 1024px to max 1024px.
   - `assets/textures/**`: caps textures to max 2048px.
2. Godot `.import` Optimization:
   - Enforces `compress/mode=2`, `mipmaps/generate=true`, `process/size_limit=1024`
     for `assets/models/` textures (2048 for `assets/textures/`).
   - Enforces `meshes/generate_lods=true` on all `.glb.import` and `.gltf.import`.
3. UV/Material-Preserving Mesh Decimation (`fast_simplification` + `scipy` `cKDTree`):
   - Any `.glb`/`.gltf` under `assets/models/` exceeding 10,000 triangles is decimated:
     * foliage / trees / rocks -> ~4,200 tris (with connected-component thinning for leaf cards)
     * furniture / tools / mice / props -> ~2,200 tris
     * characters -> ~8,000 tris
"""

from __future__ import annotations

import argparse
import json
import os
import re
import struct
import sys
from pathlib import Path
from typing import Any

import fast_simplification
import numpy as np
from PIL import Image
from scipy.sparse import csr_matrix
from scipy.sparse.csgraph import connected_components
from scipy.spatial import cKDTree


TEX_EXTS = {".png", ".jpg", ".jpeg", ".webp"}

COMP_DTYPES = {
    5120: np.int8,
    5121: np.uint8,
    5122: np.int16,
    5123: np.uint16,
    5125: np.uint32,
    5126: np.float32,
}

TYPE_COMPS = {
    "SCALAR": 1,
    "VEC2": 2,
    "VEC3": 3,
    "VEC4": 4,
    "MAT4": 16,
}


def target_tris_for_path(model_path: Path) -> int:
    low = str(model_path).lower().replace("\\", "/")
    if "/characters/" in low:
        return 8000
    if "/buildings/" in low:
        return 7500
    if "/vehicles/" in low:
        return 5000
    if any(k in low for k in ("foliage", "tree", "shrub", "bush", "plant", "rocks", "rock", "boulder", "stone")):
        return 4200
    return 2200


def downscale_textures(assets_root: Path) -> tuple[int, int]:
    resized_models = 0
    resized_world = 0
    for root, _, files in os.walk(assets_root):
        norm_root = root.replace("\\", "/")
        is_model_tex = "/models/" in norm_root
        max_dim = 1024 if is_model_tex else 2048

        for fn in sorted(files):
            p = Path(root) / fn
            if p.suffix.lower() not in TEX_EXTS:
                continue
            try:
                with Image.open(p) as im:
                    w, h = im.size
                    if max(w, h) <= max_dim:
                        continue
                    scale = max_dim / float(max(w, h))
                    nw = max(4, int(round(w * scale)))
                    nh = max(4, int(round(h * scale)))
                    out_im = im.resize((nw, nh), Image.Resampling.LANCZOS)
                    if p.suffix.lower() in (".jpg", ".jpeg"):
                        if out_im.mode != "RGB":
                            out_im = out_im.convert("RGB")
                        out_im.save(p, quality=90, optimize=True)
                    else:
                        out_im.save(p, optimize=True)
                if is_model_tex:
                    resized_models += 1
                else:
                    resized_world += 1
                print(f"  [TEX] {p}: {w}x{h} -> {nw}x{nh}")
            except Exception as exc:
                print(f"  [TEX WARN] {p}: {exc}")
    return resized_models, resized_world


def optimize_import_files(assets_root: Path) -> tuple[int, int]:
    tex_updated = 0
    mesh_updated = 0
    for root, _, files in os.walk(assets_root):
        norm_root = root.replace("\\", "/")
        is_model = "/models/" in norm_root
        size_limit = 1024 if is_model else 2048

        for fn in sorted(files):
            if not fn.endswith(".import"):
                continue
            imp_path = Path(root) / fn
            base_ext = Path(fn[:-7]).suffix.lower()
            text = imp_path.read_text(encoding="utf-8")
            new_text = text

            if base_ext in TEX_EXTS:
                new_text = re.sub(r"^compress/mode=\d+", "compress/mode=2", new_text, flags=re.MULTILINE)
                new_text = re.sub(r"^mipmaps/generate=(true|false)", "mipmaps/generate=true", new_text, flags=re.MULTILINE)
                new_text = re.sub(r"^detect_3d/compress_to=\d+", "detect_3d/compress_to=2", new_text, flags=re.MULTILINE)
                new_text = re.sub(r"^process/size_limit=\d+", f"process/size_limit={size_limit}", new_text, flags=re.MULTILINE)
                if new_text != text:
                    imp_path.write_text(new_text, encoding="utf-8")
                    tex_updated += 1

            elif base_ext in (".glb", ".gltf"):
                new_text = re.sub(r"^meshes/generate_lods=(true|false)", "meshes/generate_lods=true", new_text, flags=re.MULTILINE)
                if "meshes/generate_lods=" not in new_text:
                    new_text += "\nmeshes/generate_lods=true\n"
                if new_text != text:
                    imp_path.write_text(new_text, encoding="utf-8")
                    mesh_updated += 1

    return tex_updated, mesh_updated


def _read_accessor(gltf: dict[str, Any], buffers: list[bytes], acc_idx: int) -> np.ndarray:
    acc = gltf["accessors"][acc_idx]
    bv = gltf["bufferViews"][acc["bufferView"]]
    buf_idx = bv.get("buffer", 0)
    raw = buffers[buf_idx]
    byte_off = bv.get("byteOffset", 0) + acc.get("byteOffset", 0)
    dtype = COMP_DTYPES[acc["componentType"]]
    comps = TYPE_COMPS[acc["type"]]
    count = acc["count"]
    stride = bv.get("byteStride")
    item_size = np.dtype(dtype).itemsize * comps
    if stride is None or stride == item_size:
        arr = np.frombuffer(raw, dtype=dtype, count=count * comps, offset=byte_off).copy()
        return arr.reshape((count, comps)) if comps > 1 else arr
    out = np.empty((count, comps), dtype=dtype)
    for i in range(count):
        out[i] = np.frombuffer(raw, dtype=dtype, count=comps, offset=byte_off + i * stride)
    return out if comps > 1 else out.reshape((count,))


def _thin_disconnected_components(
    verts: np.ndarray,
    norms: np.ndarray | None,
    uvs: np.ndarray | None,
    faces: np.ndarray,
    target_faces: int,
    scale_kept_foliage: bool,
) -> tuple[np.ndarray, np.ndarray | None, np.ndarray | None, np.ndarray]:
    """Subsample whole disconnected mesh islands/leaf cards cleanly down to target_faces."""
    n_v = len(verts)
    e0 = np.concatenate([faces[:, 0], faces[:, 1], faces[:, 2]])
    e1 = np.concatenate([faces[:, 1], faces[:, 2], faces[:, 0]])
    rows = np.concatenate([e0, e1])
    cols = np.concatenate([e1, e0])
    adj = csr_matrix((np.ones(len(rows), dtype=np.uint8), (rows, cols)), shape=(n_v, n_v))
    n_comp, labels = connected_components(adj, directed=False)
    if n_comp <= 1:
        return verts, norms, uvs, faces

    face_comp = labels[faces[:, 0]]
    comp_ids, counts = np.unique(face_comp, return_counts=True)
    avg_faces_per_comp = max(1.0, float(len(faces)) / float(len(comp_ids)))
    keep_n = max(16, int(round(target_faces / avg_faces_per_comp)))
    if keep_n >= len(comp_ids):
        return verts, norms, uvs, faces

    keep_ratio = keep_n / float(len(comp_ids))
    chosen_indices = np.linspace(0, len(comp_ids) - 1, keep_n, dtype=np.int64)
    chosen_comps = set(comp_ids[chosen_indices].tolist())
    face_mask = np.isin(face_comp, list(chosen_comps))
    kept_faces = faces[face_mask]

    used_v, inverse = np.unique(kept_faces.reshape(-1), return_inverse=True)
    new_faces = inverse.reshape(-1, 3)
    new_verts = verts[used_v].copy()
    new_norms = norms[used_v].copy() if norms is not None else None
    new_uvs = uvs[used_v].copy() if uvs is not None else None

    # Expand kept detached leaf cards slightly so decimated tree crowns stay lush
    if scale_kept_foliage and keep_ratio < 0.45:
        leaf_scale = min(1.85, 1.0 / max(0.35, keep_ratio ** 0.28))
        new_labels = labels[used_v]
        for cid in np.unique(new_labels):
            mask = new_labels == cid
            if np.sum(mask) <= 12:
                c = np.mean(new_verts[mask], axis=0)
                new_verts[mask] = c + (new_verts[mask] - c) * leaf_scale

    return new_verts, new_norms, new_uvs, new_faces


def _decimate_primitive(
    verts: np.ndarray,
    norms: np.ndarray | None,
    uvs: np.ndarray | None,
    faces: np.ndarray,
    target_faces: int,
    is_foliage: bool,
) -> tuple[np.ndarray, np.ndarray | None, np.ndarray | None, np.ndarray]:
    if len(faces) <= target_faces:
        return verts, norms, uvs, faces

    pts64 = np.asarray(verts, dtype=np.float64)
    tris32 = np.asarray(faces, dtype=np.int32)
    v_out, f_out = fast_simplification.simplify(pts64, tris32, target_count=target_faces)
    v_out = np.asarray(v_out, dtype=np.float32)
    f_out = np.asarray(f_out, dtype=np.uint32)

    tree = cKDTree(verts)
    _, nn = tree.query(v_out)
    n_out = norms[nn].astype(np.float32) if norms is not None else None
    uv_out = uvs[nn].astype(np.float32) if uvs is not None else None

    if len(f_out) > int(target_faces * 1.25):
        v_out, n_out, uv_out, f_out = _thin_disconnected_components(
            v_out, n_out, uv_out, f_out, target_faces, is_foliage
        )

    return v_out, n_out, uv_out, f_out


def _rebuild_gltf_buffers(
    gltf: dict[str, Any],
    orig_buffers: list[bytes],
    model_path: Path,
    target_total: int,
) -> tuple[dict[str, Any], bytes, int, int]:
    """Decimate primitives over threshold and write a single clean binary buffer."""
    total_before = 0
    prim_infos: list[tuple[dict[str, Any], int]] = []
    for mesh in gltf.get("meshes", []):
        for prim in mesh.get("primitives", []):
            if "indices" not in prim or "POSITION" not in prim.get("attributes", {}):
                continue
            acc_idx = prim["indices"]
            cnt = gltf["accessors"][acc_idx]["count"] // 3
            total_before += cnt
            prim_infos.append((prim, cnt))

    if total_before <= 10000:
        return gltf, orig_buffers[0] if orig_buffers else b"", total_before, total_before

    is_foliage = any(k in str(model_path).lower() for k in ("foliage", "tree", "shrub", "bush", "plant"))

    # Copy any non-mesh bufferViews (if present, e.g., animations/skins/embedded images in .glb)
    mesh_acc_indices: set[int] = set()
    for mesh in gltf.get("meshes", []):
        for prim in mesh.get("primitives", []):
            if "indices" in prim:
                mesh_acc_indices.add(prim["indices"])
            for v in prim.get("attributes", {}).values():
                mesh_acc_indices.add(v)
    mesh_bv_indices = {gltf["accessors"][i]["bufferView"] for i in mesh_acc_indices if "bufferView" in gltf["accessors"][i]}

    bin_chunks: list[bytes] = []
    cur_offset = 0

    def append_bytes(data: bytes) -> tuple[int, int]:
        nonlocal cur_offset
        pad = (4 - (len(data) % 4)) % 4
        chunk = data + (b"\x00" * pad)
        off = cur_offset
        bin_chunks.append(chunk)
        cur_offset += len(chunk)
        return off, len(data)

    new_bvs: list[dict[str, Any]] = []
    bv_remap: dict[int, int] = {}
    for bv_idx, bv in enumerate(gltf.get("bufferViews", [])):
        if bv_idx in mesh_bv_indices:
            continue
        raw = orig_buffers[bv.get("buffer", 0)]
        sl = raw[bv.get("byteOffset", 0) : bv.get("byteOffset", 0) + bv["byteLength"]]
        off, blen = append_bytes(sl)
        nbv = dict(bv)
        nbv["buffer"] = 0
        nbv["byteOffset"] = off
        nbv["byteLength"] = blen
        bv_remap[bv_idx] = len(new_bvs)
        new_bvs.append(nbv)

    for acc_idx, acc in enumerate(gltf.get("accessors", [])):
        if acc_idx not in mesh_acc_indices and "bufferView" in acc and acc["bufferView"] in bv_remap:
            acc["bufferView"] = bv_remap[acc["bufferView"]]

    for img in gltf.get("images", []):
        if "bufferView" in img and img["bufferView"] in bv_remap:
            img["bufferView"] = bv_remap[img["bufferView"]]

    new_accessors: list[dict[str, Any]] = list(gltf.get("accessors", []))
    total_after = 0

    for prim, cnt in prim_infos:
        attrs = prim["attributes"]
        pos = _read_accessor(gltf, orig_buffers, attrs["POSITION"]).astype(np.float32)
        faces = _read_accessor(gltf, orig_buffers, prim["indices"]).reshape(-1, 3).astype(np.uint32)
        norms = _read_accessor(gltf, orig_buffers, attrs["NORMAL"]).astype(np.float32) if "NORMAL" in attrs else None
        uvs = _read_accessor(gltf, orig_buffers, attrs["TEXCOORD_0"]).astype(np.float32) if "TEXCOORD_0" in attrs else None

        if len(prim_infos) > 20:
            sub_target = target_total if cnt > 5000 else cnt
        else:
            sub_target = max(350, int(round(target_total * float(cnt) / float(total_before))))
        v_out, n_out, uv_out, f_out = _decimate_primitive(pos, norms, uvs, faces, sub_target, is_foliage)
        total_after += len(f_out)

        # Write POSITION
        off_p, len_p = append_bytes(np.ascontiguousarray(v_out, dtype=np.float32).tobytes())
        bv_p = len(new_bvs)
        new_bvs.append({"buffer": 0, "byteOffset": off_p, "byteLength": len_p, "target": 34962})
        attrs["POSITION"] = len(new_accessors)
        new_accessors.append({
            "bufferView": bv_p,
            "componentType": 5126,
            "count": int(len(v_out)),
            "type": "VEC3",
            "min": [float(x) for x in np.min(v_out, axis=0)],
            "max": [float(x) for x in np.max(v_out, axis=0)],
        })

        # Write NORMAL
        if n_out is not None:
            off_n, len_n = append_bytes(np.ascontiguousarray(n_out, dtype=np.float32).tobytes())
            bv_n = len(new_bvs)
            new_bvs.append({"buffer": 0, "byteOffset": off_n, "byteLength": len_n, "target": 34962})
            attrs["NORMAL"] = len(new_accessors)
            new_accessors.append({
                "bufferView": bv_n,
                "componentType": 5126,
                "count": int(len(n_out)),
                "type": "VEC3",
            })

        # Write TEXCOORD_0
        if uv_out is not None:
            off_uv, len_uv = append_bytes(np.ascontiguousarray(uv_out, dtype=np.float32).tobytes())
            bv_uv = len(new_bvs)
            new_bvs.append({"buffer": 0, "byteOffset": off_uv, "byteLength": len_uv, "target": 34962})
            attrs["TEXCOORD_0"] = len(new_accessors)
            new_accessors.append({
                "bufferView": bv_uv,
                "componentType": 5126,
                "count": int(len(uv_out)),
                "type": "VEC2",
            })

        # Keep only POSITION / NORMAL / TEXCOORD_0 so tangents/unused attrs never mismatch
        for k in list(attrs.keys()):
            if k not in ("POSITION", "NORMAL", "TEXCOORD_0"):
                del attrs[k]

        # Write indices (UINT16 when possible, else UINT32)
        if len(v_out) < 65535:
            ind_arr = np.ascontiguousarray(f_out.reshape(-1), dtype=np.uint16)
            ind_comp = 5123
        else:
            ind_arr = np.ascontiguousarray(f_out.reshape(-1), dtype=np.uint32)
            ind_comp = 5125
        off_i, len_i = append_bytes(ind_arr.tobytes())
        bv_i = len(new_bvs)
        new_bvs.append({"buffer": 0, "byteOffset": off_i, "byteLength": len_i, "target": 34963})
        prim["indices"] = len(new_accessors)
        new_accessors.append({
            "bufferView": bv_i,
            "componentType": ind_comp,
            "count": int(len(ind_arr)),
            "type": "SCALAR",
        })

    new_bin = b"".join(bin_chunks)
    gltf["bufferViews"] = new_bvs
    gltf["accessors"] = new_accessors
    gltf["buffers"] = [{"byteLength": len(new_bin)}]
    return gltf, new_bin, total_before, total_after


def decimate_gltf_or_glb(model_path: Path) -> None:
    target = target_tris_for_path(model_path)
    if model_path.suffix.lower() == ".gltf":
        gltf = json.loads(model_path.read_text(encoding="utf-8"))
        orig_buffers: list[bytes] = []
        for b in gltf.get("buffers", []):
            uri = b.get("uri", "")
            bpath = model_path.parent / uri
            orig_buffers.append(bpath.read_bytes())

        new_gltf, new_bin, before, after = _rebuild_gltf_buffers(gltf, orig_buffers, model_path, target)
        if after == before:
            return
        bin_name = model_path.stem + ".bin"
        (model_path.parent / bin_name).write_bytes(new_bin)
        new_gltf["buffers"][0]["uri"] = bin_name
        model_path.write_text(json.dumps(new_gltf, separators=(",", ":")), encoding="utf-8")
        print(f"  [DECIMATE] {model_path}: {before:,} -> {after:,} tris ({len(new_bin)/1024:.0f} KB .bin)")

    elif model_path.suffix.lower() == ".glb":
        raw = model_path.read_bytes()
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
        new_gltf, new_bin, before, after = _rebuild_gltf_buffers(gltf, [bin_bytes], model_path, target)
        if after == before:
            return

        jbytes = json.dumps(new_gltf, separators=(",", ":")).encode("utf-8")
        jpad = (4 - (len(jbytes) % 4)) % 4
        jchunk = jbytes + (b" " * jpad)
        bpad = (4 - (len(new_bin) % 4)) % 4
        bchunk = new_bin + (b"\x00" * bpad)
        total_len = 12 + 8 + len(jchunk) + 8 + len(bchunk)
        header = struct.pack("<III", 0x46546C67, version, total_len)
        out = header + struct.pack("<II", len(jchunk), 0x4E4F534A) + jchunk + struct.pack("<II", len(bchunk), 0x004E4942) + bchunk
        model_path.write_bytes(out)
        print(f"  [DECIMATE] {model_path}: {before:,} -> {after:,} tris ({len(out)/1024:.0f} KB .glb)")


def main() -> int:
    parser = argparse.ArgumentParser(description="Optimize 4K textures, Godot .import settings, and decimate high-poly meshes.")
    parser.add_argument("--assets-root", default="assets")
    parser.add_argument("--skip-decimate", action="store_true")
    parser.add_argument("--skip-textures", action="store_true")
    args = parser.parse_args()

    assets_root = Path(args.assets_root)
    if not args.skip_textures:
        print("1) Downscaling oversized textures...")
        rm, rw = downscale_textures(assets_root)
        print(f"   Resized {rm} model textures (max 1024px) and {rw} world textures (max 2048px).")

    if not args.skip_decimate:
        print("2) Decimating meshes exceeding 10,000 triangles...")
        models_root = assets_root / "models"
        for root, _, files in os.walk(models_root):
            for fn in sorted(files):
                p = Path(root) / fn
                if p.suffix.lower() in (".gltf", ".glb"):
                    decimate_gltf_or_glb(p)

    print("3) Enforcing VRAM Compressed + Mipmaps + Size Limit + LODs in .import files...")
    tu, mu = optimize_import_files(assets_root)
    print(f"   Updated {tu} texture .import files and {mu} mesh .import files.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
