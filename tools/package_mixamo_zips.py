"""Convert original colored .glb character models into Mixamo-ready colored flat .zip archives.

Automatically uses headless Blender (`tools/blender_bake_mixamo.py`) if installed; otherwise
uses pure Python (`trimesh` + `PIL` + `numpy`) to:
  1. Load each original colored .glb character model (`object_0*.glb` in Downloads\\99_Others)
  2. Join multi-part meshes, make face winding & outward normals consistent (fixing black backs)
  3. Extract/bake the character's 1024x1024 albedo color texture as `<CharacterName>_albedo.png`
  4. Export clean Mixamo-native `.obj` + matte `.mtl` (`Kd 1 1 1`, `Ks 0 0 0`, `map_Kd <name>_albedo.png`)
     which Mixamo reliably displays in full color (avoiding white PBR-FBX shader mismatches)
  5. Package flat at the root of `mixamo_upload_zips\\<CharacterName>.zip` and open in Explorer.
"""

from __future__ import annotations

import datetime
import io
import json
import shutil
import struct
import subprocess
import zipfile
from pathlib import Path

import numpy as np
import trimesh
from PIL import Image

SOURCE_DIR = Path(r"C:\Users\Mosab\Downloads\99_Others")
PROJECT_DIR = Path(r"C:\Users\Mosab\Projects\khartoum-azhari-game")
OUTPUT_DIR = PROJECT_DIR / "mixamo_upload_zips"


def find_blender() -> str | None:
    found = shutil.which("blender")
    if found:
        return found
    for root in (
        Path(r"C:\Program Files\Blender Foundation"),
        Path(r"C:\Program Files (x86)\Blender Foundation"),
    ):
        if root.exists():
            for exe in sorted(root.rglob("blender.exe"), reverse=True):
                return str(exe)
    return None


def extract_glb_base_color_image(glb_path: Path) -> Image.Image | None:
    """Extract the primary baseColorTexture image directly from a GLB binary."""
    raw = glb_path.read_bytes()
    if len(raw) < 20 or raw[:4] != b"glTF":
        return None
    jlen = struct.unpack("<I", raw[12:16])[0]
    j = json.loads(raw[20 : 20 + jlen].decode("utf-8"))
    bin_header = 20 + jlen
    if bin_header + 8 > len(raw):
        return None
    bin_off = bin_header + 8
    images = j.get("images", [])
    bviews = j.get("bufferViews", [])
    if not images:
        return None
    # Locate baseColorTexture image index if specified
    img_idx = 0
    mats = j.get("materials", [])
    texs = j.get("textures", [])
    if mats:
        bct = mats[0].get("pbrMetallicRoughness", {}).get("baseColorTexture")
        if bct and "index" in bct and bct["index"] < len(texs):
            img_idx = texs[bct["index"]].get("source", 0)
    img_def = images[img_idx]
    if "bufferView" not in img_def:
        return None
    bv = bviews[img_def["bufferView"]]
    start = bin_off + bv.get("byteOffset", 0)
    end = start + bv["byteLength"]
    im = Image.open(io.BytesIO(raw[start:end])).convert("RGB")
    if im.size != (1024, 1024):
        im = im.resize((1024, 1024), Image.Resampling.LANCZOS)
    return im


def compute_outward_pct(mesh: trimesh.Trimesh) -> float:
    if len(mesh.faces) == 0:
        return 0.0
    centroid = mesh.vertices.mean(axis=0)
    to_out = mesh.triangles_center - centroid
    dots = np.einsum("ij,ij->i", mesh.face_normals, to_out)
    return float(100.0 * (dots >= 0).sum() / len(mesh.faces))


def fix_mesh_outward_normals(mesh: trimesh.Trimesh) -> tuple[float, float, bool]:
    before_pct = compute_outward_pct(mesh)
    trimesh.repair.fix_winding(mesh)
    trimesh.repair.fix_normals(mesh)
    mesh._cache.clear()
    mid_pct = compute_outward_pct(mesh)
    inverted = False
    if mid_pct < 50.0:
        mesh.faces = np.fliplr(mesh.faces)
        mesh._cache.clear()
        inverted = True
    after_pct = compute_outward_pct(mesh)
    return round(before_pct, 1), round(after_pct, 1), inverted


def write_clean_obj_and_mtl(mesh: trimesh.Trimesh, obj_name: str, mtl_name: str, tex_name: str) -> tuple[str, str]:
    verts = mesh.vertices
    vnorms = mesh.vertex_normals
    faces = mesh.faces
    uvs = getattr(mesh.visual, "uv", None)
    has_uv = uvs is not None and len(uvs) == len(verts)

    mtl_lines = [
        f"# Clean matte Mixamo material for {obj_name}",
        "newmtl CharacterMat",
        "Ka 1.0000 1.0000 1.0000",
        "Kd 1.0000 1.0000 1.0000",
        "Ks 0.0000 0.0000 0.0000",
        "Ns 10.0000",
        "d 1.0000",
        "illum 1",
        f"map_Kd {tex_name}",
        "",
    ]

    obj_lines = [
        f"mtllib {mtl_name}",
        f"o {Path(obj_name).stem}",
    ]
    for v in verts:
        obj_lines.append(f"v {v[0]:.6f} {v[1]:.6f} {v[2]:.6f}")
    if has_uv:
        for uv in uvs:
            obj_lines.append(f"vt {uv[0]:.6f} {uv[1]:.6f}")
    for vn in vnorms:
        obj_lines.append(f"vn {vn[0]:.6f} {vn[1]:.6f} {vn[2]:.6f}")
    obj_lines.append("usemtl CharacterMat")
    obj_lines.append("s 1")
    for f in faces:
        i0, i1, i2 = int(f[0]) + 1, int(f[1]) + 1, int(f[2]) + 1
        if has_uv:
            obj_lines.append(f"f {i0}/{i0}/{i0} {i1}/{i1}/{i1} {i2}/{i2}/{i2}")
        else:
            obj_lines.append(f"f {i0}//{i0} {i1}//{i1} {i2}//{i2}")
    obj_lines.append("")
    return "\n".join(obj_lines), "\n".join(mtl_lines)


def discover_source_glbs() -> list[Path]:
    today = datetime.date.today()
    all_glbs = sorted(SOURCE_DIR.glob("*.glb"), key=lambda p: p.name.lower())
    today_glbs = [p for p in all_glbs if datetime.date.fromtimestamp(p.stat().st_mtime) == today]
    return today_glbs if today_glbs else all_glbs


def main() -> None:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    # Remove any stale old zips from earlier white-FBX pass
    for old_z in OUTPUT_DIR.glob("*.zip"):
        old_z.unlink(missing_ok=True)

    blender_exe = find_blender()
    if blender_exe:
        print(f"[INFO] Blender found at {blender_exe}; running headless Blender bake...")
        subprocess.run(
            [blender_exe, "--background", "--python", str(PROJECT_DIR / "tools" / "blender_bake_mixamo.py")],
            check=True,
        )
    else:
        print("[INFO] Blender is not installed on this machine; using trimesh+PIL normal-fix & colored OBJ+MTL+PNG pipeline (Mixamo native).")
        glbs = discover_source_glbs()
        if not glbs:
            print(f"[ERROR] No .glb character files found in {SOURCE_DIR}")
            return

        print(f"Found {len(glbs)} original colored .glb character model(s) in {SOURCE_DIR}:\n")
        for glb_path in glbs:
            char_name = glb_path.stem
            loaded = trimesh.load(str(glb_path))
            geoms = (
                [g for g in loaded.geometry.values() if isinstance(g, trimesh.Trimesh)]
                if isinstance(loaded, trimesh.Scene)
                else [loaded]
            )
            mesh = trimesh.util.concatenate(geoms) if len(geoms) > 1 else geoms[0]
            before_pct, after_pct, inverted = fix_mesh_outward_normals(mesh)

            albedo_img = extract_glb_base_color_image(glb_path)
            if albedo_img is None:
                albedo_img = Image.new("RGB", (1024, 1024), (210, 185, 160))

            tex_name = f"{char_name}_albedo.png"
            obj_name = f"{char_name}.obj"
            mtl_name = f"{char_name}.mtl"
            obj_txt, mtl_txt = write_clean_obj_and_mtl(mesh, obj_name, mtl_name, tex_name)

            png_buf = io.BytesIO()
            albedo_img.save(png_buf, format="PNG")
            png_bytes = png_buf.getvalue()

            zip_path = OUTPUT_DIR / f"{char_name}.zip"
            with zipfile.ZipFile(zip_path, "w", compression=zipfile.ZIP_DEFLATED) as zf:
                zf.writestr(obj_name, obj_txt.encode("utf-8"))
                zf.writestr(mtl_name, mtl_txt.encode("utf-8"))
                zf.writestr(tex_name, png_bytes)

            size_mb = zip_path.stat().st_size / (1024 * 1024)
            print(f"- {zip_path} ({size_mb:.2f} MB)")
            print(f"    Root contents : {obj_name}, {mtl_name}, {tex_name} (1024x1024 RGB)")
            print(f"    Normals fixed : faces={len(mesh.faces)}, outward {before_pct}% -> {after_pct}% (inverted_shell={inverted})")

    try:
        subprocess.Popen(["explorer.exe", str(OUTPUT_DIR)])
        print(f"\nOpened in Windows Explorer: {OUTPUT_DIR}")
    except Exception as exc:
        print(f"\n[WARN] Could not launch Explorer: {exc}")


if __name__ == "__main__":
    main()
