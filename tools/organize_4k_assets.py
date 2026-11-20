#!/usr/bin/env python3
"""
Recursive 4K 3D Asset Organizer, Downloader & Godot Import Optimizer
for the Al-Azhari (Khartoum) Godot 4.7.2 Project.

1. Scans `C:\\Users\\Mosab\\Downloads` for today's `.zip`, `.glb`, `.gltf`, `.fbx`
   3D asset packages and extracts/copies them cleanly into `assets/models/<category>/`
   with `textures/` subfolders intact.
2. Fetches curated 4K CC0 `.gltf` models (trees, shrubs, desert rocks, bed,
   chairs, sofa, table, bookshelf, tools, and `street_rat` rodent) from
   Poly Haven into `assets/models/` if not already present.
3. Optimizes `.import` texture sidecars under `assets/models/` to enforce
   `compress/mode=2` (VRAM Compressed) and `mipmaps/generate=true` for sharp
   4K foliage, bark, rock, wood, fabric, and fur rendering without aliasing.
"""

from __future__ import annotations

import argparse
import concurrent.futures
import json
import os
import re
import shutil
import sys
import time
import urllib.request
import zipfile
from pathlib import Path

try:
    import truststore

    truststore.inject_into_ssl()
except Exception:
    pass


MODEL_EXTS = {".glb", ".gltf", ".fbx"}
TEX_EXTS = {".png", ".jpg", ".jpeg", ".webp", ".tga", ".exr"}

POLYHAVEN_4K_ASSETS: list[tuple[str, str]] = [
    # Foliage / Trees (4K)
    ("foliage", "island_tree_02"),
    ("foliage", "quiver_tree_01"),
    ("foliage", "shrub_01"),
    ("foliage", "wild_rooibos_bush"),
    # Rocks & Boulders (4K)
    ("rocks", "namaqualand_rocks_01"),
    ("rocks", "namaqualand_stones_01"),
    ("rocks", "boulder_01"),
    # Beds, Chairs & Interior Furniture (4K)
    ("furniture", "vintage_day_bed"),
    ("furniture", "WoodenChair_01"),
    ("furniture", "ArmChair_01"),
    ("furniture", "Sofa_01"),
    ("furniture", "WoodenTable_01"),
    ("furniture", "wooden_bookshelf_worn"),
    # Tools & Workshop Props (4K)
    ("tools", "wooden_hammer_01"),
    ("tools", "adjustable_wrench"),
    ("tools", "bolt_cutters_01"),
    # Rodent / Mouse Creature (4K)
    ("creatures", "street_rat"),
]


def classify_3d_name(name: str) -> str:
    low = name.lower()
    if any(k in low for k in ("mouse", "rat", "rodent")):
        return "creatures"
    if any(k in low for k in ("tree", "palm", "bush", "shrub", "plant", "acacia", "neem", "foliage")):
        return "foliage"
    if any(k in low for k in ("rock", "stone", "boulder", "pebble")):
        return "rocks"
    if any(k in low for k in ("bed", "mattress", "sofa", "couch", "chair", "stool", "bench", "table", "cabinet", "wardrobe", "shelf", "bookshelf", "rug")):
        return "furniture"
    if any(k in low for k in ("tool", "hammer", "wrench", "bolt", "drill")):
        return "tools"
    if any(k in low for k in ("amjad", "boks", "pickup", "karo", "cart", "raksha", "car", "van", "truck")):
        return "vehicles"
    if any(k in low for k in ("compound", "house", "apartment", "mosque", "rakouba", "dukkan", "shop", "tea_stall")):
        return "buildings"
    return "props"


def ingest_downloads(downloads_dir: Path, models_root: Path, today_only: bool = True) -> list[Path]:
    imported: list[Path] = []
    if not downloads_dir.exists():
        return imported

    today_str = time.strftime("%Y-%m-%d")
    for entry in sorted(downloads_dir.iterdir()):
        try:
            mtime_str = time.strftime("%Y-%m-%d", time.localtime(entry.stat().st_mtime))
        except OSError:
            continue
        if today_only and mtime_str != today_str:
            continue

        if entry.is_file() and entry.suffix.lower() in MODEL_EXTS:
            cat = classify_3d_name(entry.stem)
            dest_dir = models_root / cat / entry.stem
            dest_dir.mkdir(parents=True, exist_ok=True)
            dest_file = dest_dir / entry.name
            if not dest_file.exists():
                shutil.copy2(entry, dest_file)
                imported.append(dest_file)
                # Copy sibling textures/ directory if present next to downloaded gltf
                tex_src = entry.parent / "textures"
                if tex_src.is_dir():
                    shutil.copytree(tex_src, dest_dir / "textures", dirs_exist_ok=True)
                # Copy sibling .bin file for .gltf
                bin_src = entry.with_suffix(".bin")
                if bin_src.exists():
                    shutil.copy2(bin_src, dest_dir / bin_src.name)

        elif entry.is_file() and entry.suffix.lower() == ".zip":
            try:
                with zipfile.ZipFile(entry, "r") as zf:
                    names = zf.namelist()
                    model_members = [n for n in names if Path(n).suffix.lower() in MODEL_EXTS and not n.startswith("__MACOSX")]
                    if not model_members:
                        continue
                    cat = classify_3d_name(entry.stem + " " + Path(model_members[0]).stem)
                    dest_dir = models_root / cat / entry.stem
                    dest_dir.mkdir(parents=True, exist_ok=True)
                    # Strip single top-level wrapper folder inside zip if all files share it
                    top_parts = {Path(n).parts[0] for n in names if len(Path(n).parts) > 1 and not n.startswith("__MACOSX")}
                    strip_prefix = (list(top_parts)[0] + "/") if len(top_parts) == 1 else ""
                    for member in names:
                        if member.endswith("/") or member.startswith("__MACOSX"):
                            continue
                        rel = member[len(strip_prefix):] if strip_prefix and member.startswith(strip_prefix) else member
                        target = (dest_dir / rel).resolve()
                        if not str(target).startswith(str(dest_dir.resolve())):
                            continue
                        target.parent.mkdir(parents=True, exist_ok=True)
                        if not target.exists():
                            with zf.open(member) as src_f, open(target, "wb") as out_f:
                                shutil.copyfileobj(src_f, out_f)
                    imported.append(dest_dir)
                    print(f"[ZIP] Extracted {entry.name} -> {dest_dir}")
            except Exception as exc:
                print(f"[WARN] Failed reading archive {entry.name}: {exc}")

    return imported


def _fetch_one_polyhaven_4k(category: str, asset_id: str, models_root: Path) -> str:
    dest_dir = models_root / category / asset_id
    gltf_path = dest_dir / f"{asset_id}.gltf"
    if gltf_path.exists() and gltf_path.stat().st_size > 500:
        return f"SKIP {category}/{asset_id} (already exists)"

    dest_dir.mkdir(parents=True, exist_ok=True)
    req = urllib.request.Request(
        f"https://api.polyhaven.com/files/{asset_id}",
        headers={"User-Agent": "Mozilla/5.0"},
    )
    data = json.loads(urllib.request.urlopen(req, timeout=30).read())
    gltf_map = data.get("gltf", {})
    pick = "4k" if "4k" in gltf_map else ("2k" if "2k" in gltf_map else next(iter(gltf_map)))
    entry = gltf_map[pick]["gltf"]

    # Download main .gltf
    urllib.request.urlretrieve(entry["url"], gltf_path)

    # Download .bin and textures/ preserving relative layout
    includes = entry.get("include", {})
    for rel_path, info in includes.items():
        out_file = dest_dir / rel_path
        out_file.parent.mkdir(parents=True, exist_ok=True)
        if not out_file.exists() or out_file.stat().st_size == 0:
            urllib.request.urlretrieve(info["url"], out_file)

    return f"OK   {category}/{asset_id} ({pick}, {1 + len(includes)} files)"


def optimize_texture_imports(models_root: Path) -> int:
    """Ensure Godot `.import` texture sidecars under `assets/models/` use VRAM Compressed + Mipmaps."""
    updated = 0
    for root, _, files in os.walk(models_root):
        for fn in files:
            if not fn.endswith(".import"):
                continue
            stem_ext = Path(fn[:-7]).suffix.lower()
            if stem_ext not in TEX_EXTS:
                continue
            imp_path = Path(root) / fn
            text = imp_path.read_text(encoding="utf-8")
            new_text = text
            new_text = re.sub(r"^compress/mode=\d+", "compress/mode=2", new_text, flags=re.MULTILINE)
            new_text = re.sub(r"^mipmaps/generate=(true|false)", "mipmaps/generate=true", new_text, flags=re.MULTILINE)
            new_text = re.sub(r"^detect_3d/compress_to=\d+", "detect_3d/compress_to=2", new_text, flags=re.MULTILINE)
            if new_text != text:
                imp_path.write_text(new_text, encoding="utf-8")
                updated += 1
    return updated


def main() -> int:
    parser = argparse.ArgumentParser(description="Organize, fetch 4K CC0 models, and optimize Godot texture imports.")
    parser.add_argument("--downloads-dir", default=r"C:\Users\Mosab\Downloads")
    parser.add_argument("--models-root", default="assets/models")
    parser.add_argument("--skip-fetch", action="store_true", help="Skip downloading Poly Haven 4K packs.")
    parser.add_argument("--optimize-only", action="store_true", help="Only update .import VRAM+mipmap flags.")
    args = parser.parse_args()

    models_root = Path(args.models_root)
    models_root.mkdir(parents=True, exist_ok=True)

    if args.optimize_only:
        patched = optimize_texture_imports(models_root)
        print(f"Optimized {patched} texture .import files under {models_root}.")
        return 0

    dl_imported = ingest_downloads(Path(args.downloads_dir), models_root, today_only=True)
    print(f"Downloads ingested today: {len(dl_imported)}")

    if not args.skip_fetch:
        print(f"Ensuring {len(POLYHAVEN_4K_ASSETS)} 4K CC0 models in {models_root}...")
        with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
            futs = [
                pool.submit(_fetch_one_polyhaven_4k, cat, aid, models_root)
                for cat, aid in POLYHAVEN_4K_ASSETS
            ]
            for fut in concurrent.futures.as_completed(futs):
                try:
                    print(" ", fut.result())
                except Exception as exc:
                    print("  ERROR:", exc)

    patched = optimize_texture_imports(models_root)
    print(f"Updated {patched} existing texture .import files for VRAM compression + mipmaps.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
