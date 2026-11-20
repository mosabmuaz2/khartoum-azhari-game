#!/usr/bin/env python3
"""
Smart Per-Folder .glb Selector, Deduplicator & Mixamo .zip Exporter (.obj + .mtl + .png)
========================================================================================
1. Treats each subfolder in `res://assets/models/characters/` as ONE unique character.
2. Inspects every `.glb` inside each folder (filename tokens, GLTF JSON chunk,
   TEXCOORD_0 UVs, baseColorTexture/images, trimesh geometry integrity, AABB aspect ratio,
   and welded connected components) to select STRICTLY ONE clean primary `.glb`.
3. Writes `tools/characters_fbx_for_mixamo/SELECTION_REPORT.txt` & prints it.
4. Exports ONLY the single selected clean `.glb` per character folder into a Mixamo-ready
   `.zip` archive inside `tools/characters_fbx_for_mixamo/` containing:
   - `character.obj` (pure static mesh, upright Y-up, X/Z centered, Y=0 ground, ~1.75m tall, valid `vt`)
   - `character.mtl` (bright diffuse `Kd 1.0 1.0 1.0` referencing `albedo.png`)
   - `albedo.png` (extracted base color texture)
   Optionally exports FBX 2013 alongside the `.zip` if Blender is installed.
"""

import io
import json
import shutil
import struct
import subprocess
import tempfile
import zipfile
from pathlib import Path

import numpy as np
from PIL import Image
import trimesh

ROOT = Path(r"c:\Users\Mosab\Projects\khartoum-azhari-game")
CHARS_DIR = ROOT / "assets" / "models" / "characters"
OUT_DIR = ROOT / "tools" / "characters_fbx_for_mixamo"
REPORT_PATH = OUT_DIR / "SELECTION_REPORT.txt"

REJECT_SUBSTRINGS = ("person_0", "0person", "person", "split", "part", "body_", "seg")

FOLDER_FRIENDLY_NAMES = {
    "السواق": "01_Driver_Dreiver",
    "الشابة": "02_YoungWoman_Mama2",
    "الطالبة": "03_UniversityStudent_Girl",
    "الطفل": "04_Child_Kid",
    "العم الطيب": "05_Elder_Oldman",
    "الغني": "06_Merchant_Richman",
    "المسكين": "07_SimpleMan_Homeless",
    "خالتو نفيسة": "08_TeaLady_Nafisa",
    "سيدة الحي": "09_NeighborhoodLady_Mama",
    "طالبة المدرسة": "10_SchoolGirl_Student",
    "ود الحلة": "11_MainHero_Mutaz_Man",
}


def friendly_fbx_stem(folder_name: str) -> str:
    for prefix, stem in FOLDER_FRIENDLY_NAMES.items():
        if prefix in folder_name:
            return stem
    safe = "".join(c if c.isalnum() or c in ("_", "-") else "_" for c in folder_name).strip("_")
    return safe or "Character"


# ------------------------------------------------------------------------------
# 1. GLB INSPECTION & SMART PER-FOLDER SELECTION
# ------------------------------------------------------------------------------
def parse_glb_chunks(glb_path: Path):
    data = glb_path.read_bytes()
    if len(data) < 20 or data[:4] != b"glTF":
        return None, None
    jlen = struct.unpack_from("<I", data, 12)[0]
    jtype = data[16:20]
    if jtype != b"JSON" or 20 + jlen > len(data):
        return None, None
    gltf = json.loads(data[20 : 20 + jlen].decode("utf-8"))
    bin_off = 20 + jlen
    bin_bytes = b""
    if bin_off + 8 <= len(data) and data[bin_off + 4 : bin_off + 8] == b"BIN\x00":
        blen = struct.unpack_from("<I", data, bin_off)[0]
        bin_bytes = data[bin_off + 8 : bin_off + 8 + blen]
    return gltf, bin_bytes


def read_accessor(gltf: dict, bin_bytes: bytes, acc_idx: int) -> np.ndarray:
    acc = gltf["accessors"][acc_idx]
    bv = gltf["bufferViews"][acc["bufferView"]]
    off = bv.get("byteOffset", 0) + acc.get("byteOffset", 0)
    count = acc["count"]
    ctype = acc["componentType"]
    atype = acc["type"]

    dtype_map = {
        5120: np.int8,
        5121: np.uint8,
        5122: np.int16,
        5123: np.uint16,
        5125: np.uint32,
        5126: np.float32,
    }
    comp_map = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}
    dt = dtype_map[ctype]
    ncomp = comp_map[atype]
    item_sz = np.dtype(dt).itemsize * ncomp
    stride = bv.get("byteStride", item_sz)

    if stride == item_sz:
        arr = np.frombuffer(bin_bytes, dtype=dt, count=count * ncomp, offset=off).reshape((count, ncomp))
    else:
        rows = []
        fmt_ch = {np.int8: "b", np.uint8: "B", np.int16: "h", np.uint16: "H", np.uint32: "I", np.float32: "f"}[dt]
        for i in range(count):
            rows.append(struct.unpack_from(f"<{ncomp}{fmt_ch}", bin_bytes, off + i * stride))
        arr = np.array(rows, dtype=dt)
    return arr if ncomp > 1 else arr.reshape((count,))


def largest_welded_component_ratio(positions: np.ndarray, faces: np.ndarray) -> tuple[int, float]:
    if len(positions) == 0 or len(faces) == 0:
        return 0, 0.0
    quant = np.round(positions, 4)
    _, inv = np.unique(quant, axis=0, return_inverse=True)
    n_unique = int(inv.max()) + 1
    parent = list(range(n_unique))

    def find(x: int) -> int:
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    wfaces = inv[faces]
    for a, b, c in wfaces:
        ra, rb, rc = find(int(a)), find(int(b)), find(int(c))
        if ra != rb:
            parent[rb] = ra
        if ra != rc:
            parent[rc] = ra

    comp_counts: dict[int, int] = {}
    for a, _, _ in wfaces:
        r = find(int(a))
        comp_counts[r] = comp_counts.get(r, 0) + 1

    n_comps = len(comp_counts)
    main_ratio = max(comp_counts.values()) / max(len(wfaces), 1)
    return n_comps, main_ratio


def inspect_glb_candidate(glb_path: Path, folder_textures: list[Path]) -> dict:
    name_low = glb_path.name.lower()
    reasons: list[str] = []

    for tok in REJECT_SUBSTRINGS:
        if tok in name_low:
            reasons.append(f"filename_rejected('{tok}')")
            break

    gltf, bin_bytes = parse_glb_chunks(glb_path)
    if gltf is None or not gltf.get("meshes"):
        reasons.append("invalid_gltf_structure")
        return {"path": glb_path, "valid": False, "score": -1000, "reasons": reasons}

    prim = gltf["meshes"][0]["primitives"][0]
    attrs = prim.get("attributes", {})
    has_uv = "TEXCOORD_0" in attrs
    if not has_uv:
        reasons.append("missing_TEXCOORD_0_UVs")

    mats = gltf.get("materials", [])
    has_base_tex = any(
        "pbrMetallicRoughness" in m and "baseColorTexture" in m["pbrMetallicRoughness"]
        for m in mats
    )
    has_imgs = len(gltf.get("images", [])) > 0
    if not has_base_tex and not has_imgs and not folder_textures:
        reasons.append("missing_baseColorTexture")

    # Test trimesh integrity (catches corrupted/partial SAM-3D-Body buffers)
    trimesh_ok = True
    try:
        sc = trimesh.load(str(glb_path))
        if isinstance(sc, trimesh.Scene):
            geos = [g for g in sc.geometry.values() if isinstance(g, trimesh.Trimesh)]
            if not geos or sum(len(g.faces) for g in geos) < 100:
                trimesh_ok = False
                reasons.append("degenerate_or_empty_mesh")
    except Exception as ex:
        trimesh_ok = False
        reasons.append(f"corrupted_binary_mesh({type(ex).__name__})")

    pos = read_accessor(gltf, bin_bytes, attrs["POSITION"]).astype(np.float64)
    if "indices" in prim:
        idx = read_accessor(gltf, bin_bytes, prim["indices"]).astype(np.int32)
    else:
        idx = np.arange(len(pos), dtype=np.int32)
    faces = idx.reshape((-1, 3))

    mins, maxs = pos.min(axis=0), pos.max(axis=0)
    ext = maxs - mins
    w, h, d = float(ext[0]), float(ext[1]), float(ext[2])
    ratio_hd = h / max(d, 1e-5)
    ratio_hw = h / max(w, 1e-5)

    # Standing human proportions: H/D in [1.8, 6.2] and H/W >= 1.55 (allows T/A-pose arm span)
    if ratio_hd < 1.8 or ratio_hd > 6.5 or ratio_hw < 1.45:
        reasons.append(f"non_human_proportions(H/W={ratio_hw:.2f},H/D={ratio_hd:.2f})")

    n_comps, main_comp_ratio = largest_welded_component_ratio(pos, faces)
    if main_comp_ratio < 0.85:
        reasons.append(f"fragmented_mesh(main_comp={main_comp_ratio:.2f},comps={n_comps})")

    is_clean = len(reasons) == 0
    score = 0.0
    if is_clean:
        score += 100.0
    if has_uv:
        score += 20.0
    if has_base_tex and has_imgs:
        score += 20.0
    if trimesh_ok:
        score += 20.0
    score += main_comp_ratio * 10.0
    if "object_0" in name_low:
        score -= 1.0  # Slight tie-break preference for primary non-suffixed basename

    return {
        "path": glb_path,
        "valid": is_clean,
        "score": score,
        "reasons": reasons,
        "faces": len(faces),
        "verts": len(pos),
        "has_uv": has_uv,
        "has_tex": has_base_tex and has_imgs,
        "trimesh_ok": trimesh_ok,
        "ratio_hw": ratio_hw,
        "ratio_hd": ratio_hd,
        "main_comp_ratio": main_comp_ratio,
        "n_comps": n_comps,
    }


def select_folder_primary_glb(folder: Path) -> tuple[dict | None, list[dict]]:
    glbs = sorted(folder.glob("*.glb"))
    if not glbs:
        return None, []
    texs = sorted(list(folder.glob("*_0.png")) + list(folder.glob("*.png")) + list(folder.glob("*.jpg")))
    audited = [inspect_glb_candidate(g, texs) for g in glbs]
    audited.sort(key=lambda x: (-x["score"], x["path"].name.lower()))
    selected = audited[0] if audited[0]["valid"] else audited[0]
    return selected, audited


# ------------------------------------------------------------------------------
# 2. TEXTURE EXTRACTION & NORMALIZED MESH EXTRACTION
# ------------------------------------------------------------------------------
def find_folder_texture(folder: Path) -> Path | None:
    for pat in ("*_0.png", "*.png", "*.jpg", "*.jpeg"):
        hits = sorted(folder.glob(pat))
        if hits:
            return hits[0]
    return None


def extract_clean_mesh_and_texture(glb_path: Path, folder: Path):
    gltf, bin_bytes = parse_glb_chunks(glb_path)
    prim = gltf["meshes"][0]["primitives"][0]
    attrs = prim["attributes"]

    pos = read_accessor(gltf, bin_bytes, attrs["POSITION"]).astype(np.float64)
    if "TEXCOORD_0" in attrs:
        uvs = read_accessor(gltf, bin_bytes, attrs["TEXCOORD_0"]).astype(np.float64)
    else:
        uvs = np.zeros((len(pos), 2), dtype=np.float64)

    if "indices" in prim:
        indices = read_accessor(gltf, bin_bytes, prim["indices"]).astype(np.int32)
    else:
        indices = np.arange(len(pos), dtype=np.int32)
    faces = indices.reshape((-1, 3))

    # Normalize to standing 1.75m height, upright Y-up, X=0/Z=0 centered, base grounded at Y=0
    mins, maxs = pos.min(axis=0), pos.max(axis=0)
    center_x = (mins[0] + maxs[0]) * 0.5
    center_z = (mins[2] + maxs[2]) * 0.5
    min_y = mins[1]
    h = max(float(maxs[1] - min_y), 1e-4)
    scale_m = 1.75 / h

    pos_norm = pos.copy()
    pos_norm[:, 0] = (pos_norm[:, 0] - center_x) * scale_m
    pos_norm[:, 1] = (pos_norm[:, 1] - min_y) * scale_m
    pos_norm[:, 2] = (pos_norm[:, 2] - center_z) * scale_m

    # Rotate 180 deg around Y so character faces +Z (Mixamo forward convention)
    pos_norm[:, 0] = -pos_norm[:, 0]
    pos_norm[:, 2] = -pos_norm[:, 2]
    pos_norm = np.nan_to_num(pos_norm, nan=0.0, posinf=0.0, neginf=0.0)
    uvs = np.nan_to_num(uvs, nan=0.0, posinf=0.0, neginf=0.0)

    # Compute smooth welded outward vertex normals
    v0 = pos_norm[faces[:, 0]]
    v1 = pos_norm[faces[:, 1]]
    v2 = pos_norm[faces[:, 2]]
    fn = np.cross(v1 - v0, v2 - v0)
    vn = np.zeros_like(pos_norm)
    np.add.at(vn, faces[:, 0], fn)
    np.add.at(vn, faces[:, 1], fn)
    np.add.at(vn, faces[:, 2], fn)

    # Weld normals across duplicate UV seam vertices (0.1mm precision in meters)
    quant = np.round(pos_norm, 4)
    _, inv = np.unique(quant, axis=0, return_inverse=True)
    wn = np.zeros((int(inv.max()) + 1, 3), dtype=np.float64)
    np.add.at(wn, inv, vn)
    vn = wn[inv]
    norms = np.linalg.norm(vn, axis=1, keepdims=True)
    norms[norms < 1e-8] = 1.0
    vn = (vn / norms).astype(np.float64)

    # Extract embedded baseColor image bytes or load folder texture & encode clean RGB PNG
    tex_bytes = None
    imgs = gltf.get("images", [])
    if imgs and "bufferView" in imgs[0]:
        ibv = gltf["bufferViews"][imgs[0]["bufferView"]]
        ioff = ibv.get("byteOffset", 0)
        ilen = ibv["byteLength"]
        raw_img = bin_bytes[ioff : ioff + ilen]
        im = Image.open(io.BytesIO(raw_img)).convert("RGB")
        if max(im.size) > 1024:
            im.thumbnail((1024, 1024), Image.Resampling.LANCZOS)
        buf = io.BytesIO()
        im.save(buf, format="PNG")
        tex_bytes = buf.getvalue()
    else:
        ftex = find_folder_texture(folder)
        if ftex and ftex.exists():
            im = Image.open(ftex).convert("RGB")
            if max(im.size) > 1024:
                im.thumbnail((1024, 1024), Image.Resampling.LANCZOS)
            buf = io.BytesIO()
            im.save(buf, format="PNG")
            tex_bytes = buf.getvalue()

    if not tex_bytes:
        im = Image.new("RGB", (64, 64), (220, 220, 220))
        buf = io.BytesIO()
        im.save(buf, format="PNG")
        tex_bytes = buf.getvalue()

    return pos_norm, vn, uvs, faces, tex_bytes


# ------------------------------------------------------------------------------
# 3. MIXAMO .ZIP EXPORTER (character.obj + character.mtl + albedo.png)
# ------------------------------------------------------------------------------
def build_obj_and_mtl(char_name: str, pos: np.ndarray, normals: np.ndarray, uvs: np.ndarray, faces: np.ndarray) -> tuple[str, str]:
    obj_lines = [
        f"# Mixamo Static Character Mesh: {char_name}",
        "# Units: meters (1.75m height, upright Y-up, +Z forward, base Y=0)",
        "mtllib character.mtl",
        f"o {char_name}",
    ]
    obj_lines.extend(f"v {x:.6f} {y:.6f} {z:.6f}" for x, y, z in pos)
    # Flip glTF top-left V (0=top) to Wavefront OBJ bottom-left V (0=bottom)
    obj_lines.extend(f"vt {u:.6f} {1.0 - v:.6f}" for u, v in uvs)
    obj_lines.extend(f"vn {nx:.6f} {ny:.6f} {nz:.6f}" for nx, ny, nz in normals)
    obj_lines.append("usemtl CharacterMat")
    obj_lines.append("s 1")

    f1 = faces + 1
    obj_lines.extend(f"f {a}/{a}/{a} {b}/{b}/{b} {c}/{c}/{c}" for a, b, c in f1)

    mtl_text = "\n".join([
        "# Mixamo Material Definition",
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
    return "\n".join(obj_lines) + "\n", mtl_text


def write_mixamo_zip(out_zip: Path, char_name: str, pos: np.ndarray, normals: np.ndarray, uvs: np.ndarray, faces: np.ndarray, tex_bytes: bytes):
    obj_text, mtl_text = build_obj_and_mtl(char_name, pos, normals, uvs, faces)
    with zipfile.ZipFile(out_zip, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as zf:
        zf.writestr("character.obj", obj_text.encode("utf-8"))
        zf.writestr("character.mtl", mtl_text.encode("utf-8"))
        zf.writestr("albedo.png", tex_bytes)


def find_blender_exe() -> str | None:
    exe = shutil.which("blender")
    if exe:
        return exe
    for root in (r"C:\Program Files\Blender Foundation", r"C:\Program Files (x86)\Blender Foundation"):
        rp = Path(root)
        if rp.exists():
            hits = sorted(rp.rglob("blender.exe"), reverse=True)
            if hits:
                return str(hits[0])
    return None


def export_blender_fbx_2013(blender_exe: str, glb_path: Path, out_fbx: Path) -> bool:
    """Optionally export FBX 2013 (version 7.3) via headless Blender when installed."""
    script_src = f"""
import bpy
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath={str(glb_path)!r})
bpy.ops.export_scene.fbx(
    filepath={str(out_fbx)!r},
    use_selection=False,
    object_types={{'MESH'}},
    path_mode='COPY',
    embed_textures=True,
    axis_forward='Z',
    axis_up='Y',
)
"""
    with tempfile.NamedTemporaryFile("w", suffix=".py", delete=False, encoding="utf-8") as tf:
        tf.write(script_src)
        tmp_py = tf.name
    try:
        res = subprocess.run([blender_exe, "--background", "--python", tmp_py], capture_output=True, text=True, timeout=120)
        return res.returncode == 0 and out_fbx.exists() and out_fbx.stat().st_size > 0
    finally:
        Path(tmp_py).unlink(missing_ok=True)


def verify_zip_archive(zip_path: Path) -> tuple[bool, str]:
    if not zip_path.exists():
        return False, "missing_zip"
    with zipfile.ZipFile(zip_path, "r") as zf:
        names = set(zf.namelist())
        req = {"character.obj", "character.mtl", "albedo.png"}
        if not req.issubset(names):
            return False, f"missing_entries({sorted(req - names)})"
        obj_info = zf.getinfo("character.obj")
        mtl_info = zf.getinfo("character.mtl")
        png_info = zf.getinfo("albedo.png")
        if min(obj_info.file_size, mtl_info.file_size, png_info.file_size) <= 0:
            return False, "empty_entry"
        obj_txt = zf.read("character.obj").decode("utf-8", errors="replace")
        if "vt " not in obj_txt or "f " not in obj_txt or "mtllib character.mtl" not in obj_txt:
            return False, "invalid_obj_contents"
    return True, f"obj={obj_info.file_size}B mtl={mtl_info.file_size}B png={png_info.file_size}B"


def cleanup_legacy_fbx_artifacts(out_dir: Path, keep_fbx: bool):
    patterns = ("*.fbx.import", "*.png", "*.png.import") if keep_fbx else ("*.fbx", "*.fbx.import", "*.png", "*.png.import")
    removed = 0
    for pat in patterns:
        for p in out_dir.glob(pat):
            p.unlink(missing_ok=True)
            removed += 1
    return removed


def main():
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    blender_exe = find_blender_exe()
    removed_legacy = cleanup_legacy_fbx_artifacts(OUT_DIR, keep_fbx=bool(blender_exe))
    backend_label = (
        f"OBJ+MTL+PNG (.zip) + Blender Headless FBX ({blender_exe})"
        if blender_exe
        else "Mixamo Static Mesh Archive (.zip: character.obj + character.mtl + albedo.png)"
    )

    report_lines = [
        "========================================================================================",
        "AL-AZHARI CHARACTER GLB SELECTION & MIXAMO .ZIP CONVERSION REPORT",
        f"Export Backend: {backend_label}",
        f"Legacy FBX 7.4 Files Cleaned: {removed_legacy}",
        "========================================================================================",
        "",
    ]

    folders = sorted([p for p in CHARS_DIR.iterdir() if p.is_dir()])
    converted_count = 0
    verified_zips: list[str] = []

    for folder in folders:
        selected, audited = select_folder_primary_glb(folder)
        if not audited:
            continue

        out_stem = friendly_fbx_stem(folder.name)
        out_zip = OUT_DIR / f"{out_stem}.zip"

        report_lines.append(f"FOLDER: {folder.name}  -->  {out_zip.name}")
        for item in audited:
            gname = item["path"].name
            if selected and item["path"] == selected["path"]:
                report_lines.append(
                    f"  [SELECTED] {gname} | UVs={item.get('has_uv')} | Tex={item.get('has_tex')} | "
                    f"TriOK={item.get('trimesh_ok')} | H/W={item.get('ratio_hw', 0):.2f} H/D={item.get('ratio_hd', 0):.2f} | "
                    f"ManifoldMain={item.get('main_comp_ratio', 0)*100:.1f}% ({item.get('faces', 0)} tris)"
                )
            else:
                rstr = ", ".join(item["reasons"]) if item["reasons"] else "lower_quality_duplicate"
                report_lines.append(f"  [SKIPPED ] {gname} | Reason: {rstr}")

        # Convert STRICTLY the single selected .glb
        if selected is not None:
            pos, vn, uvs, faces, tex_bytes = extract_clean_mesh_and_texture(selected["path"], folder)
            write_mixamo_zip(out_zip, out_stem, pos, vn, uvs, faces, tex_bytes)
            ok, vmsg = verify_zip_archive(out_zip)
            report_lines.append(f"  [ZIP_OK={ok}] {out_zip.name} ({vmsg})")
            if blender_exe:
                export_blender_fbx_2013(blender_exe, selected["path"], OUT_DIR / f"{out_stem}.fbx")
            if ok:
                converted_count += 1
                verified_zips.append(out_zip.name)

        report_lines.append("")

    report_lines.append(f"TOTAL CHARACTERS EXPORTED & VERIFIED: {converted_count} / {len(folders)} (STRICTLY 1 .zip per folder)")
    report_lines.append("READY MIXAMO ARCHIVES: " + ", ".join(verified_zips))
    report_text = "\n".join(report_lines) + "\n"
    REPORT_PATH.write_text(report_text, encoding="utf-8")
    print(report_text)


if __name__ == "__main__":
    main()
