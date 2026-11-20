#!/usr/bin/env python3
"""
Phase 1: Khartoum / Al-Azhari Real-World Research & CC0 Asset Harvester.
1. Queries OpenStreetMap Overpass API for Al-Azhari, Khartoum street & building patterns.
2. Queries Wikimedia Commons API for CC-licensed reference photos of Khartoum architecture & vehicles.
3. Downloads additional 1K PBR textures (brick, ceramic_tiles, painted_wood, etc.) and 3D props from Poly Haven.
"""

import json
import ssl
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
REF_DIR = ROOT / "tools" / "references"
IMG_DIR = REF_DIR / "images"
TEX_DIR = ROOT / "assets" / "textures"
PROPS_DIR = ROOT / "assets" / "models" / "props"

HEADERS = {"User-Agent": "KhartoumAlAzhariResearchBot/1.0 (https://godotengine.org)"}
SSL_CTX = ssl.create_default_context()


def fetch_json(url: str, data: bytes | None = None, timeout: float = 25.0):
    req = urllib.request.Request(url, data=data, headers=HEADERS)
    with urllib.request.urlopen(req, timeout=timeout, context=SSL_CTX) as resp:
        return json.loads(resp.read().decode("utf-8"))


def download_file(url: str, dest: Path, overwrite: bool = False, timeout: float = 30.0) -> bool:
    if dest.exists() and dest.stat().st_size > 0 and not overwrite:
        return True
    dest.parent.mkdir(parents=True, exist_ok=True)
    req = urllib.request.Request(url, headers=HEADERS)
    try:
        with urllib.request.urlopen(req, timeout=timeout, context=SSL_CTX) as resp:
            content = resp.read()
        if not content:
            return False
        dest.write_bytes(content)
        return True
    except Exception as exc:
        print(f"  [WARN] Failed {url}: {exc}")
        return False


def query_osm_al_azhari() -> None:
    print("[1/4] Querying OpenStreetMap Overpass API for Al-Azhari, Khartoum...")
    REF_DIR.mkdir(parents=True, exist_ok=True)
    # Al-Azhari neighborhood south of central Khartoum (~15.495-15.515 N, 32.540-32.565 E)
    overpass_ql = """
    [out:json][timeout:25];
    (
      way["highway"](15.498,32.542,15.512,32.558);
      way["building"](15.498,32.542,15.512,32.558);
      node["amenity"~"place_of_worship|marketplace|pharmacy|restaurant|fuel"](15.495,32.538,15.518,32.562);
      node["shop"](15.495,32.538,15.518,32.562);
    );
    out body 250;
    """
    try:
        encoded = urllib.parse.urlencode({"data": overpass_ql}).encode("utf-8")
        result = fetch_json("https://overpass-api.de/api/interpreter", data=encoded, timeout=30.0)
        elements = result.get("elements", [])
        highways = {}
        buildings = 0
        pois = []
        for el in elements:
            tags = el.get("tags", {})
            if "highway" in tags:
                hw = tags["highway"]
                highways[hw] = highways.get(hw, 0) + 1
            if "building" in tags:
                buildings += 1
            if "amenity" in tags or "shop" in tags:
                pois.append({
                    "name": tags.get("name", tags.get("name:ar", "")),
                    "amenity": tags.get("amenity", ""),
                    "shop": tags.get("shop", ""),
                    "lat": el.get("lat"),
                    "lon": el.get("lon"),
                })
        summary = {
            "total_elements": len(elements),
            "highway_types": highways,
            "building_footprints_sampled": buildings,
            "pois_sample": pois[:40],
        }
        (REF_DIR / "osm_al_azhari.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")
        print(f"  OSM sampled {len(elements)} elements: highways={highways}, buildings={buildings}, pois={len(pois)}")
    except Exception as exc:
        print(f"  [WARN] Overpass API query failed: {exc}")


def query_wikimedia_references() -> None:
    print("[2/4] Harvesting Wikimedia Commons reference photos of Khartoum...")
    IMG_DIR.mkdir(parents=True, exist_ok=True)
    queries = [
        ("khartoum_street", "Khartoum street"),
        ("khartoum_mosque", "Khartoum mosque"),
        ("khartoum_market", "Omdurman OR Khartoum market"),
        ("sudan_house", "Sudan house OR compound Khartoum"),
        ("tuk_tuk_rickshaw", "auto rickshaw Sudan OR yellow tuk tuk"),
        ("hilux_pickup", "Toyota Hilux white pickup"),
    ]
    meta_records = []
    for tag, search_term in queries:
        params = urllib.parse.urlencode({
            "action": "query",
            "generator": "search",
            "gsrsearch": f"{search_term} filetype:bitmap",
            "gsrnamespace": "6",
            "gsrlimit": "3",
            "prop": "imageinfo",
            "iiprop": "url|mime|extmetadata",
            "iiurlwidth": "800",
            "format": "json",
        })
        try:
            data = fetch_json(f"https://commons.wikimedia.org/w/api.php?{params}")
            pages = data.get("query", {}).get("pages", {})
            count = 0
            for page in pages.values():
                info_list = page.get("imageinfo", [])
                if not info_list:
                    continue
                info = info_list[0]
                thumb_url = info.get("thumburl") or info.get("url")
                mime = info.get("mime", "")
                if not thumb_url or "image/" not in mime:
                    continue
                ext = "png" if "png" in mime else "jpg"
                out_path = IMG_DIR / f"{tag}_{count}.{ext}"
                if download_file(thumb_url, out_path):
                    meta_records.append({
                        "tag": tag,
                        "title": page.get("title", ""),
                        "file": str(out_path.relative_to(ROOT)),
                        "url": thumb_url,
                    })
                    count += 1
                if count >= 2:
                    break
        except Exception as exc:
            print(f"  [WARN] Wikimedia query '{search_term}' failed: {exc}")
    (REF_DIR / "wikimedia_refs.json").write_text(json.dumps(meta_records, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"  Saved {len(meta_records)} reference photos to tools/references/images/")


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


def download_polyhaven_texture(asset_id: str, subdir: str) -> bool:
    out_dir = TEX_DIR / subdir
    if (out_dir / "albedo.jpg").exists() and (out_dir / "normal.jpg").exists():
        print(f"  [Skip existing] assets/textures/{subdir}/")
        return True
    print(f"  [PolyHaven Tex] {asset_id} -> assets/textures/{subdir}/")
    try:
        files = fetch_json(f"https://api.polyhaven.com/files/{asset_id}")
    except Exception as exc:
        print(f"  [WARN] {asset_id}: {exc}")
        return False

    out_dir.mkdir(parents=True, exist_ok=True)
    map_candidates = {
        "albedo": ["Diffuse", "col", "albedo"],
        "normal": ["nor_gl", "nor_dx", "Normal"],
        "roughness": ["Rough", "roughness", "arm"],
    }
    ok = False
    for out_name, keys in map_candidates.items():
        for key in keys:
            if key in files and isinstance(files[key], dict):
                res_dict = files[key].get("1k") or files[key].get("2k")
                if not isinstance(res_dict, dict):
                    continue
                if "url" in (res_dict.get("jpg") or {}):
                    if download_file(res_dict["jpg"]["url"], out_dir / f"{out_name}.jpg"):
                        ok = True
                    break
                if "url" in (res_dict.get("png") or {}):
                    if download_file(res_dict["png"]["url"], out_dir / f"{out_name}.png"):
                        ok = True
                    break
    return ok


def download_polyhaven_model(asset_id: str, target_name: str) -> bool:
    out_dir = PROPS_DIR / target_name
    if (out_dir / f"{target_name}.gltf").exists():
        print(f"  [Skip existing] assets/models/props/{target_name}/")
        return True
    print(f"  [PolyHaven Model] {asset_id} -> assets/models/props/{target_name}/")
    try:
        files = fetch_json(f"https://api.polyhaven.com/files/{asset_id}")
    except Exception as exc:
        print(f"  [WARN] {asset_id}: {exc}")
        return False

    gltf_entry = files.get("gltf", {}).get("1k", {}).get("gltf") or files.get("gltf", {}).get("2k", {}).get("gltf")
    if not isinstance(gltf_entry, dict) or "url" not in gltf_entry:
        return False
    out_dir.mkdir(parents=True, exist_ok=True)
    if not download_file(gltf_entry["url"], out_dir / f"{target_name}.gltf"):
        return False
    for rel_path, meta in (gltf_entry.get("include") or {}).items():
        if isinstance(meta, dict) and "url" in meta:
            download_file(meta["url"], out_dir / rel_path)
    return True


def harvest_polyhaven_and_fish() -> None:
    print("[3/4] Fetching Poly Haven PBR textures (brick, ceramic_tiles, painted_wood, etc.)...")
    try:
        tex_cat = fetch_json("https://api.polyhaven.com/assets?t=textures")
        specs = [
            ("asphalt", ["asphalt", "road", "tarmac"], ["roof"]),
            ("sand_dirt", ["sand", "dirt", "soil", "mud"], ["snow", "grass"]),
            ("plaster", ["plaster", "stucco", "concrete", "wall"], ["floor", "tile"]),
            ("corrugated", ["corrugated", "metal_sheet"], ["gold"]),
            ("wood", ["wood", "planks", "timber"], ["bark"]),
            ("fabric", ["fabric", "cloth", "linen"], ["leather"]),
            ("brick", ["brick", "red_brick", "masonry"], ["floor"]),
            ("ceramic_tiles", ["ceramic", "tile", "floor_tiles", "terrazzo"], ["roof"]),
            ("painted_wood", ["painted_wood", "wood_table", "old_wood"], ["bark"]),
        ]
        for subdir, kws, ex in specs:
            aid = pick_polyhaven_asset(tex_cat, kws, ex)
            if aid:
                download_polyhaven_texture(aid, subdir)
    except Exception as exc:
        print(f"  [WARN] PolyHaven texture harvest failed: {exc}")

    print("[4/4] Fetching additional Poly Haven 3D models & verifying fish.glb...")
    try:
        mod_cat = fetch_json("https://api.polyhaven.com/assets?t=models")
        mod_specs = [
            ("crate", ["crate", "wooden_crate"], []),
            ("barrel", ["barrel", "drum"], []),
            ("stool", ["stool", "chair"], ["office", "gaming"]),
            ("lantern", ["lantern", "lamp"], ["street"]),
            ("plant", ["potted", "plant"], []),
            ("tire", ["tire", "tyre"], []),
            ("bench", ["bench", "park_bench", "wooden_bench"], []),
            ("bucket", ["bucket", "pail"], []),
            ("table", ["wooden_table", "coffee_table", "table"], ["pool", "ping"]),
            ("pot", ["clay_pot", "terracotta", "vase", "jug"], ["plant"]),
        ]
        for target_name, kws, ex in mod_specs:
            aid = pick_polyhaven_asset(mod_cat, kws, ex)
            if aid:
                download_polyhaven_model(aid, target_name)
    except Exception as exc:
        print(f"  [WARN] PolyHaven model harvest failed: {exc}")

    fish_url = "https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Assets/main/Models/BarramundiFish/glTF-Binary/BarramundiFish.glb"
    download_file(fish_url, PROPS_DIR / "fish.glb")


def main() -> None:
    query_osm_al_azhari()
    query_wikimedia_references()
    harvest_polyhaven_and_fish()
    print("=== Phase 1 Research & Asset Harvest Complete ===")


if __name__ == "__main__":
    main()
