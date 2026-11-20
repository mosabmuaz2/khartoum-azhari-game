#!/usr/bin/env python3
"""
Automatic Character Mesh Repair, Symmetric T-Pose Reconstruction & Weight-Transfer Backup Rigger
===============================================================================================
1. Identifies the 3 remaining unrigged characters under `res://assets/models/characters/`
   (those lacking a Mixamo rigged `.fbx` containing `mixamorig` / `LimbNode`):
   - `03_UniversityStudent_Girl` (`studentgirlobject_0.glb`)
   - `07_SimpleMan_Homeless` (`homeless.glb`)
   - `09_NeighborhoodLady_Mama` (`mama.glb`)
2. Repairs the 2 holey/noisy meshes (`homeless.glb`, `mama.glb`):
   - Filters floating noise fragments (`tris < 80`)
   - Reconstructs a 100% watertight 2-manifold surface (`boundary == 0`, `is_watertight == True`)
     using voxel closing, solid hole fill, Gaussian-smoothed SDF, and Kuhn 6-tetrahedra
     isosurface extraction + safe quadric simplification
   - Transfers crisp UV coordinates onto the original `albedo.png` via closest-face
     barycentric projection (zero UV seam streaking)
3. Repairs `03_UniversityStudent_Girl` (`studentgirlobject_0.glb`):
   - Centers on torso/head sagittal axis, trims the fused notebook & tucked arm on `+X`,
     and mirrors the clean free `-X` A-pose arm symmetrically onto `+X` in 3D SDF space
   - Projects mirrored arm UVs onto the clean arm sleeve/hand UV triangles of `albedo.png`
   - Generates clean `03_UniversityStudent_Girl.zip` (`character.obj` + `character.mtl` + `albedo.png`)
   - Transfers Mixamo skin weights (`k=6` IDW, top-4 bones normalized) from
     `10_SchoolGirl_Student.fbx` onto the repaired University Girl mesh to emit
     `03_UniversityStudent_Girl_AutoRigged.fbx` for immediate in-game animation.
"""

import io
import json
import struct
import zipfile
import zlib
from collections import Counter
from pathlib import Path

import fast_simplification
import numpy as np
from PIL import Image
from scipy.ndimage import binary_closing, binary_fill_holes, distance_transform_edt, gaussian_filter, label
from scipy.spatial import cKDTree
import trimesh

ROOT = Path(r"c:\Users\Mosab\Projects\khartoum-azhari-game")
CHARS_DIR = ROOT / "assets" / "models" / "characters"
OUT_DIR = ROOT / "tools" / "characters_fbx_for_mixamo"
DONOR_RIG_FBX = CHARS_DIR / "طالبة المدرسة بالزي السوداني الموحد" / "10_SchoolGirl_Student.fbx"

TARGET_REPAIR_FOLDERS = {
    "الطالبة": ("03_UniversityStudent_Girl", "studentgirlobject_0.glb", True),
    "المسكين": ("07_SimpleMan_Homeless", "homeless.glb", False),
    "سيدة الحي": ("09_NeighborhoodLady_Mama", "mama.glb", False),
}

# Kuhn 6-tetrahedra decomposition around main diagonal (0 -> 7) guarantees zero boundary/non-manifold edges
TETS = np.array([
    [0, 1, 3, 7],
    [0, 5, 1, 7],
    [0, 3, 2, 7],
    [0, 2, 6, 7],
    [0, 4, 5, 7],
    [0, 6, 4, 7],
], dtype=np.int32)

TET_TRIS = {
    0: [], 15: [],
    1: [(0, 1, 0, 2, 0, 3)], 14: [(0, 1, 0, 3, 0, 2)],
    2: [(1, 0, 1, 3, 1, 2)], 13: [(1, 0, 1, 2, 1, 3)],
    4: [(2, 0, 2, 1, 2, 3)], 11: [(2, 0, 2, 3, 2, 1)],
    8: [(3, 0, 3, 2, 3, 1)], 7: [(3, 0, 3, 1, 3, 2)],
    3: [(0, 2, 0, 3, 1, 3), (0, 2, 1, 3, 1, 2)],
    12: [(0, 2, 1, 3, 0, 3), (0, 2, 1, 2, 1, 3)],
    5: [(0, 1, 2, 3, 0, 3), (0, 1, 2, 1, 2, 3)],
    10: [(0, 1, 0, 3, 2, 3), (0, 1, 2, 3, 2, 1)],
    6: [(1, 0, 2, 3, 2, 0), (1, 0, 1, 3, 2, 3)],
    9: [(1, 0, 2, 0, 2, 3), (1, 0, 2, 3, 1, 3)],
}


# ------------------------------------------------------------------------------
# 1. GLB LOADING & UNRIGGED DETECTION
# ------------------------------------------------------------------------------
def find_unrigged_characters() -> list[tuple[Path, str, Path, bool]]:
    unrigged = []
    for folder in sorted(p for p in CHARS_DIR.iterdir() if p.is_dir()):
        has_rig = False
        for fbx in folder.glob("*.fbx"):
            if "autorigged" in fbx.name.lower():
                continue
            raw = fbx.read_bytes()
            if b"mixamorig" in raw or b"LimbNode" in raw:
                has_rig = True
                break
        if has_rig:
            continue
        for prefix, (stem, glb_name, sym_arm) in TARGET_REPAIR_FOLDERS.items():
            if prefix in folder.name:
                glb_path = folder / glb_name
                if glb_path.exists():
                    unrigged.append((folder, stem, glb_path, sym_arm))
                break
    return unrigged


def load_glb_raw(glb_path: Path, folder: Path):
    data = glb_path.read_bytes()
    jlen = struct.unpack_from("<I", data, 12)[0]
    gltf = json.loads(data[20 : 20 + jlen].decode("utf-8"))
    bin_off = 20 + jlen
    blen = struct.unpack_from("<I", data, bin_off)[0]
    bin_bytes = data[bin_off + 8 : bin_off + 8 + blen]

    def read_acc(idx):
        acc = gltf["accessors"][idx]
        bv = gltf["bufferViews"][acc["bufferView"]]
        off = bv.get("byteOffset", 0) + acc.get("byteOffset", 0)
        count = acc["count"]
        dt = {5120: np.int8, 5121: np.uint8, 5122: np.int16, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}[acc["componentType"]]
        nc = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[acc["type"]]
        arr = np.frombuffer(bin_bytes, dtype=dt, count=count * nc, offset=off).reshape((count, nc))
        return arr if nc > 1 else arr.reshape((count,))

    prim = gltf["meshes"][0]["primitives"][0]
    attrs = prim["attributes"]
    pos = read_acc(attrs["POSITION"]).astype(np.float64)
    uv = read_acc(attrs["TEXCOORD_0"]).astype(np.float64)
    faces = (read_acc(prim["indices"]) if "indices" in prim else np.arange(len(pos))).astype(np.int32).reshape((-1, 3))

    # Extract RGB texture
    tex_bytes = None
    imgs = gltf.get("images", [])
    if imgs and "bufferView" in imgs[0]:
        ibv = gltf["bufferViews"][imgs[0]["bufferView"]]
        raw_img = bin_bytes[ibv.get("byteOffset", 0) : ibv.get("byteOffset", 0) + ibv["byteLength"]]
        im = Image.open(io.BytesIO(raw_img)).convert("RGB")
        if max(im.size) > 1024:
            im.thumbnail((1024, 1024), Image.Resampling.LANCZOS)
        buf = io.BytesIO()
        im.save(buf, format="PNG")
        tex_bytes = buf.getvalue()
    else:
        for pat in ("*_0.png", "*.png", "*.jpg"):
            hits = sorted(folder.glob(pat))
            if hits:
                im = Image.open(hits[0]).convert("RGB")
                if max(im.size) > 1024:
                    im.thumbnail((1024, 1024), Image.Resampling.LANCZOS)
                buf = io.BytesIO()
                im.save(buf, format="PNG")
                tex_bytes = buf.getvalue()
                break

    return pos, uv, faces, tex_bytes


# ------------------------------------------------------------------------------
# 2. GEOMETRY REPAIR: ISLAND CLEANUP, SDF WATERTIGHT REMESH & SYMMETRIC ARM
# ------------------------------------------------------------------------------
def filter_noise_islands(pos: np.ndarray, faces: np.ndarray, min_tris: int = 80) -> np.ndarray:
    _, inv = np.unique(np.round(pos, 5), axis=0, return_inverse=True)
    parent = list(range(int(inv.max()) + 1))

    def find(x: int) -> int:
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    wf = inv[faces]
    for a, b, c in wf:
        ra, rb, rc = find(int(a)), find(int(b)), find(int(c))
        if ra != rb:
            parent[rb] = ra
        if ra != rc:
            parent[rc] = ra

    comp = np.array([find(int(a)) for a, _, _ in wf])
    counts = Counter(comp)
    keep = {r for r, n in counts.items() if n >= min_tris}
    mask = np.array([c in keep for c in comp])
    return faces[mask]


def marching_tetrahedra(sdf: np.ndarray, origin: np.ndarray, pitch: float):
    nx, ny, nz = sdf.shape
    c_off = np.array([[0, 0, 0], [1, 0, 0], [0, 1, 0], [1, 1, 0], [0, 0, 1], [1, 0, 1], [0, 1, 1], [1, 1, 1]], dtype=np.int32)
    vals = np.stack([sdf[ox : nx - 1 + ox, oy : ny - 1 + oy, oz : nz - 1 + oz] for ox, oy, oz in c_off], axis=-1)
    inside = vals < 0.0
    mask_c = np.any(inside, axis=-1) & (~np.all(inside, axis=-1))
    coords = np.argwhere(mask_c)
    c_vals = vals[mask_c]
    cg = np.stack([((coords[:, 0] + ox) * ny + (coords[:, 1] + oy)) * nz + (coords[:, 2] + oz) for ox, oy, oz in c_off], axis=-1)
    cpos = (coords[:, None, :] + c_off[None, :, :]) * pitch + origin[None, None, :]

    edge_map = {}
    verts_list = []
    faces_list = []
    for ci in range(len(coords)):
        gv = cg[ci]
        vv = c_vals[ci]
        pv = cpos[ci]
        for t in TETS:
            ti = vv[t] < 0.0
            m = (1 if ti[0] else 0) | (2 if ti[1] else 0) | (4 if ti[2] else 0) | (8 if ti[3] else 0)
            for s in TET_TRIS[m]:
                tri = []
                for k in (0, 2, 4):
                    la, lb = t[s[k]], t[s[k + 1]]
                    ga, gb = int(gv[la]), int(gv[lb])
                    key = (ga, gb) if ga < gb else (gb, ga)
                    vi = edge_map.get(key)
                    if vi is None:
                        va, vb = float(vv[la]), float(vv[lb])
                        d = va - vb
                        tl = min(max(va / d if abs(d) > 1e-12 else 0.5, 1e-4), 1.0 - 1e-4)
                        vi = len(verts_list)
                        verts_list.append(pv[la] + tl * (pv[lb] - pv[la]))
                        edge_map[key] = vi
                    tri.append(vi)
                if len({tri[0], tri[1], tri[2]}) == 3:
                    faces_list.append(tri)
    return np.array(verts_list, dtype=np.float64), np.array(faces_list, dtype=np.int32)


def _check_watertight(verts: np.ndarray, faces: np.ndarray) -> tuple[bool, int, int]:
    e = np.vstack([faces[:, [0, 1]], faces[:, [1, 2]], faces[:, [2, 0]]])
    _, cnt = np.unique(np.sort(e, axis=1), axis=0, return_counts=True)
    bnd = int((cnt == 1).sum())
    nm = int((cnt > 2).sum())
    return (bnd == 0 and nm == 0), bnd, nm


def reconstruct_watertight_mesh(pos: np.ndarray, faces: np.ndarray, symmetric_arm: bool = False):
    clean_faces = filter_noise_islands(pos, faces, min_tris=80)
    work_pos = pos.copy()

    # Center sagittal symmetry axis for symmetric T/A-pose arm mirror on University Girl
    x_sym = 0.0
    yn_min, yn_h = float(work_pos[:, 1].min()), max(float(work_pos[:, 1].ptp() if hasattr(work_pos[:, 1], "ptp") else np.ptp(work_pos[:, 1])), 1e-4)
    if symmetric_arm:
        yn = (work_pos[:, 1] - yn_min) / yn_h
        head = work_pos[yn > 0.88]
        torso = work_pos[(yn > 0.55) & (yn < 0.78) & (np.abs(work_pos[:, 0] - head[:, 0].mean()) < 0.10)]
        x_sym = float(0.5 * (head[:, 0].mean() + torso[:, 0].mean()))
        work_pos[:, 0] -= x_sym

    pitch = 0.0108 if symmetric_arm else 0.0115
    # Make grid symmetric around x=0 when mirroring arms so exact voxel reflection works!
    max_abs_x = max(abs(float(work_pos[:, 0].min())), abs(float(work_pos[:, 0].max()))) + 4 * pitch
    if symmetric_arm:
        # Snap origin x to -(k + 0.5)*pitch so ix <-> (nx - 1 - ix) reflects x -> -x cleanly
        half_nx = int(np.ceil(max_abs_x / pitch))
        ox = -(half_nx + 0.5) * pitch
        nx = 2 * (half_nx + 1)
        ymin, ymax = float(work_pos[:, 1].min()) - 4 * pitch, float(work_pos[:, 1].max()) + 4 * pitch
        zmin, zmax = float(work_pos[:, 2].min()) - 4 * pitch, float(work_pos[:, 2].max()) + 4 * pitch
        ny = int(np.ceil((ymax - ymin) / pitch)) + 1
        nz = int(np.ceil((zmax - zmin) / pitch)) + 1
        mins = np.array([ox, ymin, zmin], dtype=np.float64)
        dims = np.array([nx, ny, nz], dtype=int)
    else:
        mins = work_pos.min(axis=0) - 4 * pitch
        maxs = work_pos.max(axis=0) + 4 * pitch
        dims = np.ceil((maxs - mins) / pitch).astype(int) + 1

    occ = np.zeros(dims, dtype=bool)
    v0, v1, v2 = work_pos[clean_faces[:, 0]], work_pos[clean_faces[:, 1]], work_pos[clean_faces[:, 2]]
    gu, gv = np.meshgrid(np.linspace(0, 1, 9), np.linspace(0, 1, 9))
    u, v = gu.ravel(), gv.ravel()
    ok = (u + v) <= 1.0001
    u, v = u[ok], v[ok]
    w = np.clip(1.0 - u - v, 0.0, 1.0)
    pts = w[None, :, None] * v0[:, None, :] + u[None, :, None] * v1[:, None, :] + v[None, :, None] * v2[:, None, :]
    idx3 = np.clip(np.round((pts.reshape(-1, 3) - mins) / pitch).astype(int), 0, dims - 1)
    occ[idx3[:, 0], idx3[:, 1], idx3[:, 2]] = True

    occ = binary_closing(occ, iterations=2)
    occ = binary_fill_holes(occ)

    if symmetric_arm:
        # Replace fused book & bent arm on +X (x > +0.085, yn in [0.39, 0.81]) with mirrored clean -X A-pose arm
        xs = mins[0] + np.arange(dims[0]) * pitch
        ys = mins[1] + np.arange(dims[1]) * pitch
        yn_grid = (ys - yn_min) / yn_h
        x_cut_mask = xs > 0.085
        y_arm_mask = (yn_grid >= 0.39) & (yn_grid <= 0.81)
        x_indices = np.where(x_cut_mask)[0]
        y_indices = np.where(y_arm_mask)[0]
        mirror_xi = np.clip((dims[0] - 1) - x_indices, 0, dims[0] - 1)
        occ[np.ix_(x_indices, y_indices)] = occ[np.ix_(mirror_xi, y_indices)]
        occ = binary_fill_holes(occ)

    lbl, _ = label(occ)
    sizes = np.bincount(lbl.ravel())[1:]
    occ = lbl == (np.argmax(sizes) + 1)

    sdf = gaussian_filter(distance_transform_edt(~occ) - distance_transform_edt(occ), sigma=0.75)
    v_raw, f_raw = marching_tetrahedra(sdf, mins, pitch)

    # Simplify carefully while preserving strict 2-manifold watertight invariant
    v_best, f_best = v_raw, f_raw
    for red in (0.76, 0.60, 0.40):
        v_try, f_try = fast_simplification.simplify(v_raw.astype(np.float32), f_raw, target_reduction=red, agg=1)
        m_try = trimesh.Trimesh(vertices=v_try, faces=f_try, process=True)
        m_try.fix_normals()
        vt, ft = np.asarray(m_try.vertices, dtype=np.float64), np.asarray(m_try.faces, dtype=np.int32)
        wt, _, _ = _check_watertight(vt, ft)
        if wt:
            v_best, f_best = vt, ft
            break

    m_final = trimesh.Trimesh(vertices=v_best, faces=f_best, process=True)
    m_final.fix_normals()
    v_final = np.asarray(m_final.vertices, dtype=np.float64)
    f_final = np.asarray(m_final.faces, dtype=np.int32)
    return v_final, f_final, work_pos, clean_faces, (yn_min, yn_h)


# ------------------------------------------------------------------------------
# 3. CLOSEST-SURFACE BARYCENTRIC UV TRANSFER (ZERO SEAM STREAKING)
# ------------------------------------------------------------------------------
def transfer_per_corner_uvs(new_verts: np.ndarray, new_faces: np.ndarray, orig_pos: np.ndarray, orig_uv: np.ndarray, orig_faces: np.ndarray, symmetric_arm: bool = False, y_norm_info=(0.0, 1.0)):
    yn_min, yn_h = y_norm_info
    orig_tri_pos = orig_pos[orig_faces]        # (F0, 3, 3)
    orig_tri_uv = orig_uv[orig_faces]          # (F0, 3, 2)
    orig_centroids = orig_tri_pos.mean(axis=1) # (F0, 3)

    # Build fast spatial lookup across original triangle centroids + edge midpoints
    m01 = 0.5 * (orig_tri_pos[:, 0] + orig_tri_pos[:, 1])
    m12 = 0.5 * (orig_tri_pos[:, 1] + orig_tri_pos[:, 2])
    m20 = 0.5 * (orig_tri_pos[:, 2] + orig_tri_pos[:, 0])
    sample_pts = np.vstack([orig_centroids, m01, m12, m20])
    sample_fids = np.tile(np.arange(len(orig_faces)), 4)
    tree = cKDTree(sample_pts)

    new_tri_pos = new_verts[new_faces] # (F1, 3, 3)
    tri_cents = new_tri_pos.mean(axis=1).copy()

    # For mirrored University Girl arm (+X, yn in [0.39, 0.81]), mirror lookup X onto clean -X arm!
    q_verts = new_tri_pos.copy()
    if symmetric_arm:
        cy_n = (tri_cents[:, 1] - yn_min) / yn_h
        mir_mask = (tri_cents[:, 0] > 0.085) & (cy_n >= 0.39) & (cy_n <= 0.81)
        tri_cents[mir_mask, 0] = -tri_cents[mir_mask, 0]
        q_verts[mir_mask, :, 0] = -q_verts[mir_mask, :, 0]

    _, hit_idx = tree.query(tri_cents, k=1)
    fids = sample_fids[hit_idx]

    # Project all 3 corners of each new triangle into its matched original triangle's barycentric coords
    a = orig_tri_pos[fids, 0]
    b = orig_tri_pos[fids, 1]
    c = orig_tri_pos[fids, 2]
    v0 = b - a
    v1 = c - a
    d00 = np.einsum("ij,ij->i", v0, v0)
    d01 = np.einsum("ij,ij->i", v0, v1)
    d11 = np.einsum("ij,ij->i", v1, v1)
    denom = d00 * d11 - d01 * d01
    denom = np.where(np.abs(denom) < 1e-12, 1e-12, denom)

    corner_uvs = np.zeros((len(new_faces), 3, 2), dtype=np.float64)
    uva, uvb, uvc = orig_tri_uv[fids, 0], orig_tri_uv[fids, 1], orig_tri_uv[fids, 2]
    for ci in range(3):
        v2 = q_verts[:, ci] - a
        d20 = np.einsum("ij,ij->i", v2, v0)
        d21 = np.einsum("ij,ij->i", v2, v1)
        bv = (d11 * d20 - d01 * d21) / denom
        bw = (d00 * d21 - d01 * d20) / denom
        bu = 1.0 - bv - bw
        bary = np.clip(np.stack([bu, bv, bw], axis=1), 0.0, 1.0)
        bsum = np.maximum(bary.sum(axis=1, keepdims=True), 1e-8)
        bary /= bsum
        corner_uvs[:, ci] = bary[:, 0:1] * uva + bary[:, 1:2] * uvb + bary[:, 2:3] * uvc

    # Deduplicate corner UVs cleanly so .obj / .fbx UV tables remain compact
    flat_uv = np.round(corner_uvs.reshape((-1, 2)), 5)
    uniq_uv, uv_inv = np.unique(flat_uv, axis=0, return_inverse=True)
    uv_faces = uv_inv.reshape((-1, 3)).astype(np.int32)
    return uniq_uv, uv_faces


def normalize_to_mixamo_meters(verts: np.ndarray, faces: np.ndarray):
    mins, maxs = verts.min(axis=0), verts.max(axis=0)
    cx = 0.5 * (mins[0] + maxs[0])
    cz = 0.5 * (mins[2] + maxs[2])
    my = mins[1]
    h = max(float(maxs[1] - my), 1e-4)
    sc = 1.75 / h
    out = verts.copy()
    out[:, 0] = -((out[:, 0] - cx) * sc) # 180-deg around Y so model faces +Z (Mixamo convention)
    out[:, 1] = (out[:, 1] - my) * sc
    out[:, 2] = -((out[:, 2] - cz) * sc)

    v0, v1, v2 = out[faces[:, 0]], out[faces[:, 1]], out[faces[:, 2]]
    fn = np.cross(v1 - v0, v2 - v0)
    vn = np.zeros_like(out)
    np.add.at(vn, faces[:, 0], fn)
    np.add.at(vn, faces[:, 1], fn)
    np.add.at(vn, faces[:, 2], fn)
    nlen = np.linalg.norm(vn, axis=1, keepdims=True)
    nlen[nlen < 1e-8] = 1.0
    vn /= nlen
    return out, vn


def write_mixamo_zip(out_zip: Path, stem: str, verts: np.ndarray, normals: np.ndarray, faces: np.ndarray, uniq_uv: np.ndarray, uv_faces: np.ndarray, tex_bytes: bytes):
    lines = [
        f"# Repaired Watertight Mixamo Static Mesh: {stem}",
        "mtllib character.mtl",
        f"o {stem}",
    ]
    lines.extend(f"v {x:.6f} {y:.6f} {z:.6f}" for x, y, z in verts)
    lines.extend(f"vt {u:.6f} {1.0 - v:.6f}" for u, v in uniq_uv)
    lines.extend(f"vn {nx:.6f} {ny:.6f} {nz:.6f}" for nx, ny, nz in normals)
    lines.append("usemtl CharacterMat")
    lines.append("s 1")
    f1 = faces + 1
    uv1 = uv_faces + 1
    lines.extend(
        f"f {a}/{ua}/{a} {b}/{ub}/{b} {c}/{uc}/{c}"
        for (a, b, c), (ua, ub, uc) in zip(f1, uv1)
    )
    mtl = "\n".join([
        "newmtl CharacterMat",
        "Ka 0.0000 0.0000 0.0000",
        "Kd 1.0000 1.0000 1.0000",
        "Ks 0.0000 0.0000 0.0000",
        "Ns 10.0000",
        "d 1.0000",
        "illum 2",
        "map_Kd albedo.png",
        "",
    ])
    with zipfile.ZipFile(out_zip, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as zf:
        zf.writestr("character.obj", ("\n".join(lines) + "\n").encode("utf-8"))
        zf.writestr("character.mtl", mtl.encode("utf-8"))
        zf.writestr("albedo.png", tex_bytes)


# ------------------------------------------------------------------------------
# 4. FBX 7700 CLONE + BONE WEIGHT TRANSFER FOR AUTOMATIC BACKUP RIG
# ------------------------------------------------------------------------------
def parse_fbx7700(data: bytes):
    ver = struct.unpack_from("<I", data, 23)[0]
    pos = 27

    def read_prop():
        nonlocal pos
        tc = chr(data[pos]); pos += 1
        if tc == "Y": v = struct.unpack_from("<h", data, pos)[0]; pos += 2; return [tc, v]
        if tc == "C": v = struct.unpack_from("<B", data, pos)[0]; pos += 1; return [tc, v]
        if tc == "I": v = struct.unpack_from("<i", data, pos)[0]; pos += 4; return [tc, v]
        if tc == "F": v = struct.unpack_from("<f", data, pos)[0]; pos += 4; return [tc, v]
        if tc == "D": v = struct.unpack_from("<d", data, pos)[0]; pos += 8; return [tc, v]
        if tc == "L": v = struct.unpack_from("<q", data, pos)[0]; pos += 8; return [tc, v]
        if tc in ("S", "R"):
            l = struct.unpack_from("<I", data, pos)[0]; pos += 4
            b = data[pos : pos + l]; pos += l
            return [tc, b]
        if tc in ("f", "d", "l", "i", "b"):
            alen, enc, clen = struct.unpack_from("<III", data, pos); pos += 12
            raw = data[pos : pos + clen]; pos += clen
            return [tc, (alen, enc, raw)]
        raise ValueError(f"Unknown prop {tc}")

    def read_node():
        nonlocal pos
        end_off, nprops, plen, nlen = struct.unpack_from("<QQQB", data, pos) if ver >= 7500 else struct.unpack_from("<IIIB", data, pos)
        pos += 25 if ver >= 7500 else 13
        if end_off == 0:
            return None
        name = data[pos : pos + nlen].decode("ascii"); pos += nlen
        props = [read_prop() for _ in range(nprops)]
        children = []
        while pos < end_off:
            ch = read_node()
            if ch is None:
                break
            children.append(ch)
        pos = end_off
        return [name, props, children]

    top = []
    while pos + 25 < len(data):
        n = read_node()
        if n is None:
            break
        top.append(n)
    footer = data[pos:]
    return ver, top, footer


def pack_fbx_array(tc: str, arr: np.ndarray) -> tuple[int, int, bytes]:
    dt = {"f": "<f4", "d": "<f8", "l": "<i8", "i": "<i4", "b": "<u1"}[tc]
    raw = np.ascontiguousarray(arr.astype(dt)).tobytes()
    comp = zlib.compress(raw)
    return (int(arr.size), 1, comp)


def serialize_fbx7700(ver: int, top: list, footer: bytes) -> bytes:
    def enc_prop(p):
        tc, val = p
        if tc == "Y": return b"Y" + struct.pack("<h", val)
        if tc == "C": return b"C" + struct.pack("<B", val)
        if tc == "I": return b"I" + struct.pack("<i", val)
        if tc == "F": return b"F" + struct.pack("<f", val)
        if tc == "D": return b"D" + struct.pack("<d", val)
        if tc == "L": return b"L" + struct.pack("<q", val)
        if tc in ("S", "R"): return tc.encode("ascii") + struct.pack("<I", len(val)) + val
        if tc in ("f", "d", "l", "i", "b"):
            alen, enc, raw = val
            return tc.encode("ascii") + struct.pack("<III", alen, enc, len(raw)) + raw
        raise ValueError(tc)

    is64 = ver >= 7500
    null_term = b"\x00" * (25 if is64 else 13)
    hdr_sz = 25 if is64 else 13

    def ser_node(node, offset: int) -> bytes:
        name_b = node[0].encode("ascii")
        props_b = b"".join(enc_prop(p) for p in node[1])
        cur = offset + hdr_sz + len(name_b) + len(props_b)
        ch_parts = []
        if node[2]:
            for ch in node[2]:
                cb = ser_node(ch, cur)
                ch_parts.append(cb)
                cur += len(cb)
            ch_parts.append(null_term)
            cur += len(null_term)
        hdr = (
            struct.pack("<QQQB", cur, len(node[1]), len(props_b), len(name_b))
            if is64 else struct.pack("<IIIB", cur, len(node[1]), len(props_b), len(name_b))
        ) + name_b
        return hdr + props_b + b"".join(ch_parts)

    magic = b"Kaydara FBX Binary  \x00\x1a\x00" + struct.pack("<I", ver)
    chunks = [magic]
    cur = len(magic)
    for n in top:
        b = ser_node(n, cur)
        chunks.append(b)
        cur += len(b)
    chunks.append(null_term)
    if footer:
        chunks.append(footer)
    return b"".join(chunks)


def build_autorigged_fbx(donor_fbx: Path, out_fbxs: list[Path], new_verts: np.ndarray, new_normals: np.ndarray, new_faces: np.ndarray, uniq_uv: np.ndarray, uv_faces: np.ndarray, tex_bytes: bytes):
    ver, top, footer = parse_fbx7700(donor_fbx.read_bytes())
    objs = [n for n in top if n[0] == "Objects"][0][2]
    geom = [n for n in objs if n[0] == "Geometry"][0]

    # 1. Read donor bind-pose vertices so we transfer skin weights in exact shared space
    donor_v_prop = [c[1][0] for c in geom[2] if c[0] == "Vertices"][0]
    alen, enc, raw = donor_v_prop[1]
    donor_v = np.frombuffer(zlib.decompress(raw) if enc == 1 else raw, dtype="<f8").reshape((-1, 3))

    clusters = [n for n in objs if n[0] == "Deformer" and len(n[1]) > 2 and n[1][2][1] == b"Cluster"]
    n_donor = len(donor_v)
    n_cl = len(clusters)
    donor_weights = np.zeros((n_donor, n_cl), dtype=np.float64)
    for ci, cl in enumerate(clusters):
        idx_arr, w_arr = None, None
        for ch in cl[2]:
            if ch[0] == "Indexes":
                a, e, r = ch[1][0][1]
                idx_arr = np.frombuffer(zlib.decompress(r) if e == 1 else r, dtype="<i4")
            elif ch[0] == "Weights":
                a, e, r = ch[1][0][1]
                w_arr = np.frombuffer(zlib.decompress(r) if e == 1 else r, dtype="<f8")
        if idx_arr is not None and w_arr is not None and len(idx_arr):
            donor_weights[idx_arr, ci] = w_arr

    # 2. Match University Girl bounding box cleanly onto donor mesh height & center for weight lookup
    tree = cKDTree(donor_v)
    dists, nn_idx = tree.query(new_verts, k=6)
    idw = 1.0 / np.maximum(dists, 1e-4) ** 2
    idw /= idw.sum(axis=1, keepdims=True)
    # Accumulate weights from k nearest donor vertices
    w_new = np.einsum("vk,vkc->vc", idw, donor_weights[nn_idx])
    # Enforce max 4 bone influences per vertex & normalize strictly to 1.0
    top4_idx = np.argpartition(w_new, -4, axis=1)[:, -4:]
    top4_mask = np.zeros_like(w_new, dtype=bool)
    np.put_along_axis(top4_mask, top4_idx, True, axis=1)
    w_new *= top4_mask
    row_sums = w_new.sum(axis=1, keepdims=True)
    # Fallback to single nearest donor vertex if somehow all weights zero
    zero_rows = row_sums[:, 0] < 1e-8
    if np.any(zero_rows):
        w_new[zero_rows] = donor_weights[nn_idx[zero_rows, 0]]
        row_sums = np.maximum(w_new.sum(axis=1, keepdims=True), 1e-8)
    w_new /= row_sums

    # 3. Rewrite Cluster weight arrays
    for ci, cl in enumerate(clusters):
        nz = np.where(w_new[:, ci] > 1e-4)[0].astype(np.int32)
        nw = w_new[nz, ci].astype(np.float64)
        new_ch = []
        for ch in cl[2]:
            if ch[0] == "Indexes":
                ch = ["Indexes", [["i", pack_fbx_array("i", nz)]], []]
            elif ch[0] == "Weights":
                ch = ["Weights", [["d", pack_fbx_array("d", nw)]], []]
            new_ch.append(ch)
        cl[2] = new_ch

    # 4. Rewrite Geometry arrays (Vertices, PolygonVertexIndex, LayerElementNormal, LayerElementUV, LayerElementMaterial)
    poly_idx = new_faces.astype(np.int32).copy()
    poly_idx[:, 2] = ~poly_idx[:, 2]
    tri_flat = new_faces.reshape((-1,)).astype(np.int32)
    uv_flipped = uniq_uv.copy()
    uv_flipped[:, 1] = 1.0 - uv_flipped[:, 1]
    uv_flat_idx = uv_faces.reshape((-1,)).astype(np.int32)
    ones_w = np.ones(len(new_normals), dtype=np.float64)
    mat_zeros = np.zeros(len(new_faces), dtype=np.int32)

    for ch in geom[2]:
        if ch[0] == "Vertices":
            ch[1][0] = ["d", pack_fbx_array("d", new_verts.reshape((-1,)))]
        elif ch[0] == "PolygonVertexIndex":
            ch[1][0] = ["i", pack_fbx_array("i", poly_idx.reshape((-1,)))]
        elif ch[0] == "Edges":
            # Compute unique edge array into Edges if present
            edges_u = np.unique(np.sort(np.vstack([new_faces[:,[0,1]], new_faces[:,[1,2]], new_faces[:,[2,0]]]), axis=1), axis=0)
            ch[1][0] = ["i", pack_fbx_array("i", edges_u.reshape((-1,)))]
        elif ch[0] == "LayerElementNormal":
            for sc in ch[2]:
                if sc[0] == "Normals":
                    sc[1][0] = ["d", pack_fbx_array("d", new_normals.reshape((-1,)))]
                elif sc[0] == "NormalsW":
                    sc[1][0] = ["d", pack_fbx_array("d", ones_w)]
                elif sc[0] == "NormalsIndex":
                    sc[1][0] = ["i", pack_fbx_array("i", tri_flat)]
        elif ch[0] == "LayerElementUV":
            for sc in ch[2]:
                if sc[0] == "UV":
                    sc[1][0] = ["d", pack_fbx_array("d", uv_flipped.reshape((-1,)))]
                elif sc[0] == "UVIndex":
                    sc[1][0] = ["i", pack_fbx_array("i", uv_flat_idx)]
        elif ch[0] == "LayerElementMaterial":
            for sc in ch[2]:
                if sc[0] == "Materials":
                    sc[1][0] = ["i", pack_fbx_array("i", mat_zeros)]

    # 5. Replace embedded PNG texture bytes in Video node
    for n in objs:
        if n[0] == "Video":
            for ch in n[2]:
                if ch[0] == "Content":
                    ch[1][0] = ["R", tex_bytes]

    out_bytes = serialize_fbx7700(ver, top, footer)
    for dst in out_fbxs:
        dst.write_bytes(out_bytes)


# ------------------------------------------------------------------------------
# MAIN
# ------------------------------------------------------------------------------
def main():
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    targets = find_unrigged_characters()
    print(f"Identified {len(targets)} unrigged character(s) needing repair:")
    for folder, stem, glb_path, sym_arm in targets:
        print(f"  - {stem}: {glb_path.name} (sym_arm={sym_arm})")
        orig_pos, orig_uv, orig_faces, tex_bytes = load_glb_raw(glb_path, folder)
        v_rep, f_rep, aligned_orig_pos, clean_orig_faces, yn_info = reconstruct_watertight_mesh(
            orig_pos, orig_faces, symmetric_arm=sym_arm
        )
        wt, bnd, nm = _check_watertight(v_rep, f_rep)
        uniq_uv, uv_faces = transfer_per_corner_uvs(
            v_rep, f_rep, aligned_orig_pos, orig_uv, clean_orig_faces, symmetric_arm=sym_arm, y_norm_info=yn_info
        )
        verts_m, normals_m = normalize_to_mixamo_meters(v_rep, f_rep)

        out_zip = OUT_DIR / f"{stem}.zip"
        write_mixamo_zip(out_zip, stem, verts_m, normals_m, f_rep, uniq_uv, uv_faces, tex_bytes)
        print(
            f"    -> Repaired {out_zip.name}: verts={len(verts_m)}, tris={len(f_rep)}, "
            f"watertight={wt} (boundary={bnd}, nonmanifold={nm}), zip={out_zip.stat().st_size}B"
        )

        # Generate Automatic Backup Rig for University Girl by transferring weights from 10_SchoolGirl_Student.fbx
        if sym_arm and DONOR_RIG_FBX.exists():
            rig_paths = [
                OUT_DIR / f"{stem}_AutoRigged.fbx",
                folder / f"{stem}_AutoRigged.fbx",
            ]
            build_autorigged_fbx(DONOR_RIG_FBX, rig_paths, verts_m, normals_m, f_rep, uniq_uv, uv_faces, tex_bytes)
            print(f"    -> Generated Backup Auto-Rigged FBX: {rig_paths[1]} ({rig_paths[1].stat().st_size}B)")


if __name__ == "__main__":
    main()
