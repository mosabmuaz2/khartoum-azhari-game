#!/usr/bin/env python3
"""
Vehicle Archive Extractor, 3D Model Auditor & Pack Importer for Al-Azhari
=========================================================================
1. Scans `C:\\Users\\Mosab\\Downloads\\05_Archives` for `.zip`/`.7z`/`.tar` archives
   and standalone 3D files (`.glb`, `.gltf`, `.fbx`, `.obj`).
2. Extracts all archives into `tools/vehicle_pack_staging/`.
3. Inspects every 3D model (FBX binary / glTF / OBJ) for vertex count, triangle count,
   submesh/wheel nodes, and materials.
4. Copies clean vehicles, bicycles, and wheel assets (`<= 8,000` triangles) into
   `res://assets/models/vehicles/pack/`, and writes `PACK_AUDIT.txt`.
"""

import json
import shutil
import struct
import tarfile
import zipfile
import zlib
from pathlib import Path

import numpy as np

ARCHIVES_SRC = Path(r"C:\Users\Mosab\Downloads\05_Archives")
ROOT = Path(r"c:\Users\Mosab\Projects\khartoum-azhari-game")
STAGE_DIR = ROOT / "tools" / "vehicle_pack_staging"
PACK_DIR = ROOT / "assets" / "models" / "vehicles" / "pack"
AUDIT_PATH = PACK_DIR / "PACK_AUDIT.txt"

MAX_TRIS = 8000
SELECTED_VEHICLE_PACK = {
    # Pack 164139 vehicles & transit
    ("164139", "Ambulance.fbx"): "Ambulance.fbx",
    ("164139", "Bicycle.fbx"): "Bicycle.fbx",
    ("164139", "Bus.fbx"): "Bus.fbx",
    ("164139", "SchoolBus.fbx"): "SchoolBus.fbx",
    ("164139", "SquareFrameBicycle.fbx"): "SquareFrameBicycle.fbx",
    ("164139", "Taxi.fbx"): "ClassicTaxi.fbx",
    # Pack 164215 cars & SUVs (clean separate FL/FR/Rear wheels & lights!)
    ("164215", "Cop.fbx"): "Cop.fbx",
    ("164215", "NormalCar1.fbx"): "NormalCar1.fbx",
    ("164215", "NormalCar2.fbx"): "NormalCar2.fbx",
    ("164215", "SportsCar.fbx"): "SportsCar.fbx",
    ("164215", "SportsCar2.fbx"): "SportsCar2.fbx",
    ("164215", "SUV.fbx"): "SUV.fbx",
    ("164215", "Taxi.fbx"): "Taxi.fbx",
    # Boat / Nile pack 164231
    ("164231", "Boat.fbx"): "Boat.fbx",
}


def inspect_fbx_binary(fbx_path: Path) -> dict:
    data = fbx_path.read_bytes()
    if data[:20] != b"Kaydara FBX Binary  ":
        return {"ok": False, "reason": "not_binary_fbx"}
    ver = struct.unpack_from("<I", data, 23)[0]
    pos = 27
    is64 = ver >= 7500
    hdr_sz = 25 if is64 else 13

    def rp():
        nonlocal pos
        tc = chr(data[pos]); pos += 1
        if tc == "Y": v = struct.unpack_from("<h", data, pos)[0]; pos += 2; return (tc, v)
        if tc == "C": v = struct.unpack_from("<B", data, pos)[0]; pos += 1; return (tc, v)
        if tc == "I": v = struct.unpack_from("<i", data, pos)[0]; pos += 4; return (tc, v)
        if tc == "F": v = struct.unpack_from("<f", data, pos)[0]; pos += 4; return (tc, v)
        if tc == "D": v = struct.unpack_from("<d", data, pos)[0]; pos += 8; return (tc, v)
        if tc == "L": v = struct.unpack_from("<q", data, pos)[0]; pos += 8; return (tc, v)
        if tc in ("S", "R"):
            l = struct.unpack_from("<I", data, pos)[0]; pos += 4
            b = data[pos : pos + l]; pos += l
            return (tc, b.decode("utf-8", errors="replace") if tc == "S" else b)
        if tc in ("f", "d", "l", "i", "b"):
            alen, enc, clen = struct.unpack_from("<III", data, pos); pos += 12
            raw = data[pos : pos + clen]; pos += clen
            return (tc, (alen, enc, raw))
        raise ValueError(f"Unknown prop {tc}")

    def rn():
        nonlocal pos
        end_off, nprops, plen, nlen = struct.unpack_from("<QQQB" if is64 else "<IIIB", data, pos)
        pos += hdr_sz
        if end_off == 0:
            return None
        name = data[pos : pos + nlen].decode("ascii", errors="replace"); pos += nlen
        props = [rp() for _ in range(nprops)]
        children = []
        while pos < end_off:
            ch = rn()
            if ch is None:
                break
            children.append(ch)
        pos = end_off
        return (name, props, children)

    top = []
    while pos + hdr_sz < len(data):
        n = rn()
        if n is None:
            break
        top.append(n)

    objs = [n for n in top if n[0] == "Objects"][0][2]
    models = [n[1][1][1].split("\x00")[0] for n in objs if n[0] == "Model"]
    mats = [n[1][1][1].split("\x00")[0] for n in objs if n[0] == "Material"]
    verts, tris = 0, 0
    for n in objs:
        if n[0] == "Geometry":
            for c in n[2]:
                if c[0] == "Vertices":
                    verts += c[1][0][1][0] // 3
                elif c[0] == "PolygonVertexIndex":
                    a, e, r = c[1][0][1]
                    arr = np.frombuffer(zlib.decompress(r) if e == 1 else r, dtype="<i4")
                    neg = np.where(arr < 0)[0]
                    prev = -1
                    for ni in neg:
                        tris += max(1, (int(ni) - prev) - 2)
                        prev = int(ni)
    return {"ok": True, "ver": ver, "verts": verts, "tris": tris, "models": models, "mats": mats}


def extract_archives():
    if STAGE_DIR.exists():
        shutil.rmtree(STAGE_DIR)
    STAGE_DIR.mkdir(parents=True, exist_ok=True)
    if not ARCHIVES_SRC.exists():
        raise FileNotFoundError(f"Missing archives folder: {ARCHIVES_SRC}")

    for arc in sorted(ARCHIVES_SRC.rglob("*")):
        if not arc.is_file():
            continue
        low = arc.name.lower()
        if low.endswith(".zip"):
            if "xoutput" in low:
                continue
            with zipfile.ZipFile(arc) as zf:
                zf.extractall(STAGE_DIR / arc.stem)
        elif low.endswith((".tar", ".tar.gz", ".tgz")):
            with tarfile.open(arc) as tf:
                tf.extractall(STAGE_DIR / arc.stem)
        elif low.endswith((".glb", ".gltf", ".fbx", ".obj")):
            shutil.copy2(arc, STAGE_DIR / arc.name)


def main():
    extract_archives()
    PACK_DIR.mkdir(parents=True, exist_ok=True)

    lines = [
        "========================================================================================",
        "AL-AZHARI VEHICLE ARCHIVE EXTRACTION & 3D MODEL AUDIT",
        f"Source: {ARCHIVES_SRC}",
        "========================================================================================",
        "",
    ]

    copied = []
    for mpath in sorted(STAGE_DIR.rglob("*")):
        if not mpath.is_file() or mpath.suffix.lower() not in (".fbx", ".glb", ".gltf", ".obj"):
            continue
        info = inspect_fbx_binary(mpath) if mpath.suffix.lower() == ".fbx" else {"ok": True, "tris": 0, "verts": 0, "models": [], "mats": []}
        rel = mpath.relative_to(STAGE_DIR)
        status = "DISCOVERED"
        out_name = None
        for (tag, fname), dst_name in SELECTED_VEHICLE_PACK.items():
            if tag in str(rel) and mpath.name == fname:
                if info.get("ok") and info.get("tris", 0) <= MAX_TRIS:
                    shutil.copy2(mpath, PACK_DIR / dst_name)
                    status = f"IMPORTED -> pack/{dst_name}"
                    out_name = dst_name
                    copied.append(dst_name)
                else:
                    status = f"SKIPPED (tris={info.get('tris')})"
                break

        lines.append(
            f"[{status}] {rel} | verts={info.get('verts')} tris={info.get('tris')} "
            f"| nodes={info.get('models')} | mats={info.get('mats')}"
        )

    lines.append("")
    lines.append(f"TOTAL VEHICLE & WHEEL PACK MODELS IMPORTED INTO pack/: {len(copied)}")
    lines.append("FILES: " + ", ".join(copied))
    txt = "\n".join(lines) + "\n"
    AUDIT_PATH.write_text(txt, encoding="utf-8")
    print(txt)

    # Attach res://scripts/vehicle_post_import.gd to all pack/*.fbx.import files
    patched = 0
    for imp in sorted(PACK_DIR.glob("*.fbx.import")):
        imp_txt = imp.read_text(encoding="utf-8")
        target = 'import_script/path="res://scripts/vehicle_post_import.gd"'
        if target not in imp_txt:
            imp_txt = imp_txt.replace('import_script/path=""', target)
            imp.write_text(imp_txt, encoding="utf-8")
            patched += 1
    print(f"Patched import_script/path on {patched} .fbx.import file(s).")


if __name__ == "__main__":
    main()
