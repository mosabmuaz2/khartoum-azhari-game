#!/usr/bin/env python3
"""
Automated CC0 Real Assets & SFX Downloader for Khartoum Al-Azhari (Godot 4.7.2).
Downloads 1K PBR textures and GLTF props from Poly Haven, BarramundiFish.glb from Khronos,
and attempts CC0 audio downloads without overwriting any existing user files.
"""

import json
import os
import ssl
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TEX_DIR = ROOT / "assets" / "textures"
PROPS_DIR = ROOT / "assets" / "models" / "props"
AUDIO_DIR = ROOT / "assets" / "audio"

HEADERS = {"User-Agent": "KhartoumAlAzhariGodot/1.0 (+https://godotengine.org)"}
SSL_CTX = ssl.create_default_context()


def fetch_json(url: str, timeout: float = 20.0):
    req = urllib.request.Request(url, headers=HEADERS)
    with urllib.request.urlopen(req, timeout=timeout, context=SSL_CTX) as resp:
        return json.loads(resp.read().decode("utf-8"))


def download_file(url: str, dest: Path, overwrite: bool = False, timeout: float = 30.0) -> bool:
    if dest.exists() and dest.stat().st_size > 0 and not overwrite:
        return True
    dest.parent.mkdir(parents=True, exist_ok=True)
    req = urllib.request.Request(url, headers=HEADERS)
    try:
        with urllib.request.urlopen(req, timeout=timeout, context=SSL_CTX) as resp:
            data = resp.read()
        if not data:
            return False
        dest.write_bytes(data)
        return True
    except Exception as exc:
        print(f"  [WARN] Failed {url}: {exc}")
        return False


def pick_polyhaven_asset(catalog: dict, keywords: list[str], exclude: list[str] | None = None) -> str | None:
    exclude = exclude or []
    best_id = None
    best_score = -1
    for asset_id, info in catalog.items():
        hay = (
            asset_id.lower()
            + " "
            + str(info.get("name", "")).lower()
            + " "
            + " ".join(str(t).lower() for t in info.get("tags", []))
            + " "
            + " ".join(str(c).lower() for c in info.get("categories", []))
        )
        if any(ex in hay for ex in exclude):
            continue
        score = sum(2 if kw in asset_id.lower() else (1 if kw in hay else 0) for kw in keywords)
        if score > best_score and score > 0:
            best_score = score
            best_id = asset_id
    return best_id


def download_polyhaven_texture(asset_id: str, target_subdir: str) -> bool:
    print(f"[PolyHaven Texture] {asset_id} -> assets/textures/{target_subdir}/")
    try:
        files = fetch_json(f"https://api.polyhaven.com/files/{asset_id}")
    except Exception as exc:
        print(f"  [WARN] Could not query files for {asset_id}: {exc}")
        return False

    out_dir = TEX_DIR / target_subdir
    out_dir.mkdir(parents=True, exist_ok=True)
    map_candidates = {
        "albedo": ["Diffuse", "col", "albedo"],
        "normal": ["nor_gl", "nor_dx", "Normal"],
        "roughness": ["Rough", "roughness", "arm"],
    }
    ok_any = False
    for out_name, keys in map_candidates.items():
        for key in keys:
            if key in files and isinstance(files[key], dict):
                res_dict = files[key].get("1k") or files[key].get("2k")
                if not isinstance(res_dict, dict):
                    continue
                fmt_dict = res_dict.get("jpg") or res_dict.get("png")
                if isinstance(fmt_dict, dict) and "url" in fmt_dict:
                    ext = "png" if "png" in res_dict and res_dict.get("jpg") is None else ("jpg" if res_dict.get("jpg") else "png")
                    if "url" in (res_dict.get("jpg") or {}):
                        url = res_dict["jpg"]["url"]
                        ext = "jpg"
                    else:
                        url = res_dict["png"]["url"]
                        ext = "png"
                    if download_file(url, out_dir / f"{out_name}.{ext}"):
                        ok_any = True
                    break
    return ok_any


def download_polyhaven_model(asset_id: str, target_name: str) -> bool:
    print(f"[PolyHaven Model] {asset_id} -> assets/models/props/{target_name}/")
    try:
        files = fetch_json(f"https://api.polyhaven.com/files/{asset_id}")
    except Exception as exc:
        print(f"  [WARN] Could not query model files for {asset_id}: {exc}")
        return False

    gltf_block = files.get("gltf", {})
    res_block = gltf_block.get("1k") or gltf_block.get("2k")
    if not isinstance(res_block, dict):
        return False
    gltf_entry = res_block.get("gltf")
    if not isinstance(gltf_entry, dict) or "url" not in gltf_entry:
        return False

    out_dir = PROPS_DIR / target_name
    out_dir.mkdir(parents=True, exist_ok=True)
    main_ok = download_file(gltf_entry["url"], out_dir / f"{target_name}.gltf")
    if not main_ok:
        return False

    includes = gltf_entry.get("include", {})
    if isinstance(includes, dict):
        for rel_path, meta in includes.items():
            if isinstance(meta, dict) and "url" in meta:
                download_file(meta["url"], out_dir / rel_path)
    return True


def download_fish_model() -> bool:
    url = "https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Assets/main/Models/BarramundiFish/glTF-Binary/BarramundiFish.glb"
    dest = PROPS_DIR / "fish.glb"
    print(f"[Khronos GLB] Downloading fish.glb...")
    ok = download_file(url, dest)
    print(f"  fish.glb -> {'OK' if ok else 'FAILED'}")
    return ok


def download_cc0_audio() -> None:
    # Attempt to download CC0 sound effects from public GitHub mirrors without overwriting existing user files.
    # Godot's AudioManager will synthesize realistic WAV fallbacks for any slot not present.
    candidates = [
        (
            "https://raw.githubusercontent.com/KenneyNL/Audio-Interface-Sounds/main/Audio/click_001.ogg",
            AUDIO_DIR / "sfx" / "ui_click.ogg",
        ),
        (
            "https://raw.githubusercontent.com/KenneyNL/Audio-Impact-Sounds/main/Audio/footstep_concrete_000.ogg",
            AUDIO_DIR / "sfx" / "footstep_asphalt_kenney.ogg",
        ),
        (
            "https://raw.githubusercontent.com/KenneyNL/Audio-Impact-Sounds/main/Audio/footstep_grass_000.ogg",
            AUDIO_DIR / "sfx" / "footstep_sand_kenney.ogg",
        ),
    ]
    for url, dest in candidates:
        if dest.exists():
            continue
        if download_file(url, dest, timeout=10.0):
            print(f"[CC0 Audio] Downloaded {dest.relative_to(ROOT)}")


def main() -> None:
    print("=== Fetching Real CC0 Textures, Models, and SFX ===")
    try:
        tex_catalog = fetch_json("https://api.polyhaven.com/assets?t=textures")
        tex_specs = [
            ("asphalt", ["asphalt", "road", "tarmac"], ["roof"]),
            ("sand_dirt", ["sand", "dirt", "soil", "mud", "ground"], ["snow", "grass"]),
            ("plaster", ["plaster", "stucco", "concrete", "wall"], ["floor", "tile"]),
            ("corrugated", ["corrugated", "metal", "sheet", "iron"], ["gold", "copper"]),
            ("wood", ["wood", "planks", "timber"], ["bark"]),
            ("fabric", ["fabric", "cloth", "linen", "canvas"], ["leather"]),
        ]
        for folder, kws, ex in tex_specs:
            aid = pick_polyhaven_asset(tex_catalog, kws, ex)
            if aid:
                download_polyhaven_texture(aid, folder)
    except Exception as exc:
        print(f"[WARN] PolyHaven texture catalog fetch failed: {exc}")

    try:
        model_catalog = fetch_json("https://api.polyhaven.com/assets?t=models")
        model_specs = [
            ("crate", ["crate", "wooden_crate", "box"], []),
            ("barrel", ["barrel", "drum"], []),
            ("stool", ["stool", "chair", "bench"], ["office", "gaming"]),
            ("lantern", ["lantern", "lamp"], ["street"]),
            ("plant", ["potted", "plant", "pot"], []),
            ("tire", ["tire", "tyre", "wheel"], []),
        ]
        for folder, kws, ex in model_specs:
            aid = pick_polyhaven_asset(model_catalog, kws, ex)
            if aid:
                download_polyhaven_model(aid, folder)
    except Exception as exc:
        print(f"[WARN] PolyHaven model catalog fetch failed: {exc}")

    download_fish_model()
    download_cc0_audio()
    print("=== Asset Download Complete ===")


if __name__ == "__main__":
    main()
