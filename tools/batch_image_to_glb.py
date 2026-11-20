#!/usr/bin/env python3
"""
Batch 2D Image -> Textured 3D GLB Converter for Khartoum (Al-Azhari) Godot Project.

Scans `tools/images_to_convert/` for `.png`, `.jpg`, `.jpeg`, and `.webp` files,
connects via `gradio_client` to public Hugging Face Spaces (`tencent/Hunyuan3D-2`
with automatic fallback to `tencent/Hunyuan3D-2.1`, `microsoft/TRELLIS.2`,
`JeffreyXiang/TRELLIS`, `stabilityai/TripoSR`, and `TencentARC/InstantMesh`),
dynamically inspects endpoints via `client.view_api(return_format="dict")`,
exports textured `.glb` assets into `assets/models/buildings/`,
`assets/models/vehicles/`, or `assets/models/props/`, and emits structured
fallback markers if all Spaces rate-limit or queue-timeout.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import sys
import time
import urllib.request
from pathlib import Path
from typing import Any

try:
    import truststore

    truststore.inject_into_ssl()
except Exception:
    pass

from gradio_client import Client, handle_file


IMAGE_EXTS = {".png", ".jpg", ".jpeg", ".webp"}

DEFAULT_SPACES = [
    "tencent/Hunyuan3D-2",
    "tencent/Hunyuan3D-2mini-Turbo",
    "tencent/Hunyuan3D-2.1",
    "microsoft/TRELLIS.2",
    "trellis-community/TRELLIS",
    "JeffreyXiang/TRELLIS",
    "stabilityai/TripoSR",
    "TencentARC/InstantMesh",
]

VEHICLE_KEYWORDS = (
    "van",
    "amjad",
    "boks",
    "pickup",
    "raksha",
    "tuk",
    "sedan",
    "car",
    "truck",
    "daffar",
    "bus",
    "cart",
    "karo",
    "donkey",
    "taxi",
    "auto",
    "vehicle",
)

BUILDING_KEYWORDS = (
    "house",
    "jalous",
    "shop",
    "dukkan",
    "rakouba",
    "mosque",
    "building",
    "apartment",
    "compound",
    "hosh",
    "tea_stall",
    "stall",
    "bakery",
    "pharmacy",
    "salon",
    "clinic",
    "kiosk",
    "shed",
    "shelter",
)

PROP_KEYWORDS = (
    "table",
    "chair",
    "stool",
    "bench",
    "barrel",
    "crate",
    "lantern",
    "pot",
    "bucket",
    "plant",
    "tree",
    "tire",
    "sign",
    "lamp",
    "prop",
    "animal",
)


def infer_category(filename: str) -> str:
    """Classify output subfolder (`buildings`, `vehicles`, or `props`) from filename."""
    stem = Path(filename).stem.lower()
    tokens = set(stem.replace("-", "_").split("_"))
    for kw in VEHICLE_KEYWORDS:
        if kw in tokens or kw in stem:
            return "vehicles"
    for kw in PROP_KEYWORDS:
        if kw in tokens or kw in stem:
            return "props"
    for kw in BUILDING_KEYWORDS:
        if kw in tokens or kw in stem:
            return "buildings"
    return "props"


def _extract_file_paths(obj: Any) -> list[str]:
    """Recursively collect file path strings or URLs from a Gradio return payload."""
    found: list[str] = []
    if isinstance(obj, str):
        if obj.strip():
            found.append(obj.strip())
    elif isinstance(obj, dict):
        for key in ("path", "url", "value", "name"):
            val = obj.get(key)
            if isinstance(val, str) and val.strip():
                found.append(val.strip())
    elif isinstance(obj, (list, tuple)):
        for item in obj:
            found.extend(_extract_file_paths(item))
    return found


def _save_result_to_glb(candidate_paths: list[str], dest_path: Path) -> bool:
    """Copy or download the best `.glb` candidate (preferring textured mesh) to dest_path."""
    glb_candidates = [p for p in candidate_paths if p.lower().endswith(".glb")]
    if not glb_candidates:
        return False

    # Hunyuan3D `/generation_all` returns (white_mesh.glb, textured_mesh.glb, ...);
    # prefer the last `.glb` entry when multiple GLBs exist (usually textured).
    selected = glb_candidates[-1]
    dest_path.parent.mkdir(parents=True, exist_ok=True)

    if selected.startswith("http://") or selected.startswith("https://"):
        req = urllib.request.Request(selected, headers={"User-Agent": "Mozilla/5.0"})
        with urllib.request.urlopen(req, timeout=60) as resp, open(dest_path, "wb") as f:
            shutil.copyfileobj(resp, f)
    else:
        src = Path(selected)
        if not src.exists():
            return False
        shutil.copy2(src, dest_path)

    return dest_path.exists() and dest_path.stat().st_size > 1024


def _build_kwargs_from_api(
    endpoint_info: dict[str, Any],
    image_path: Path | None = None,
    overrides: dict[str, Any] | None = None,
) -> dict[str, Any]:
    """
    Build keyword arguments strictly matching the target endpoint's `view_api` schema.
    """
    kwargs: dict[str, Any] = {}
    overrides = overrides or {}
    image_bound = False

    for param in endpoint_info.get("parameters", []):
        name = param.get("parameter_name") or param.get("label") or ""
        if not name:
            continue
        if name in overrides:
            kwargs[name] = overrides[name]
            continue

        ptype = str(param.get("python_type", {}).get("type", "")).lower()
        comp = str(param.get("component", "")).lower()
        is_image_param = (
            not image_bound
            and image_path is not None
            and (
                name in ("image", "input_image", "input", "img")
                or comp == "image"
            )
        )
        if is_image_param:
            kwargs[name] = handle_file(str(image_path))
            image_bound = True
            continue

        if param.get("parameter_has_default", False):
            kwargs[name] = param.get("parameter_default")
        elif "bool" in ptype:
            kwargs[name] = True
        elif "int" in ptype or "float" in ptype:
            kwargs[name] = 0
        elif "str" in ptype:
            kwargs[name] = ""

    return kwargs


def _call_hunyuan3d(client: Client, named: dict[str, Any], image_path: Path, dest_path: Path) -> bool:
    """Invoke Hunyuan3D-2 / 2.1 (`generation_all` -> fallback `shape_generation`, then optional `on_export_click`)."""
    endpoints_to_try = [ep for ep in ("/generation_all", "/shape_generation") if ep in named]
    if not endpoints_to_try:
        return False

    last_exc: Exception | None = None
    for ep in endpoints_to_try:
        kwargs = _build_kwargs_from_api(
            named[ep],
            image_path=image_path,
            overrides={
                "steps": 15 if "steps" in [p.get("parameter_name") for p in named[ep].get("parameters", [])] else None,
                "octree_resolution": 256,
                "check_box_rembg": True,
                "randomize_seed": True,
            },
        )
        kwargs = {
            k: v
            for k, v in kwargs.items()
            if v is not None
            or any(
                p.get("parameter_name") == k and p.get("parameter_default") is None
                for p in named[ep].get("parameters", [])
            )
        }

        try:
            result = client.predict(api_name=ep, **kwargs)
        except Exception as exc:
            last_exc = exc
            # Some Hunyuan3D deployments lack texgen_worker for /generation_all; fall back to /shape_generation
            if ep == "/generation_all" and "/shape_generation" in endpoints_to_try and "texgen_worker" in str(exc):
                continue
            raise

        candidates = _extract_file_paths(result)
        if _save_result_to_glb(candidates, dest_path):
            return True

        # Fallback: explicitly trigger `/on_export_click` if available and files weren't `.glb`
        if "/on_export_click" in named and len(candidates) >= 1:
            f1 = candidates[0]
            f2 = candidates[1] if len(candidates) > 1 else candidates[0]
            export_kwargs = _build_kwargs_from_api(
                named["/on_export_click"],
                overrides={
                    "file_out": handle_file(f1),
                    "file_out2": handle_file(f2),
                    "file_type": "glb",
                    "reduce_face": True,
                    "export_texture": True,
                    "target_face_num": 15000,
                },
            )
            export_res = client.predict(api_name="/on_export_click", **export_kwargs)
            if _save_result_to_glb(_extract_file_paths(export_res), dest_path):
                return True

    if last_exc is not None:
        raise last_exc
    return False


def _call_trellis2(client: Client, named: dict[str, Any], image_path: Path, dest_path: Path) -> bool:
    """Invoke TRELLIS.2 workflow (`/start_session` -> `/preprocess_image` -> `/image_to_3d` -> `/extract_glb`)."""
    if "/start_session" in named:
        client.predict(api_name="/start_session")

    img_input = handle_file(str(image_path))
    if "/preprocess_image" in named:
        prep_kwargs = _build_kwargs_from_api(named["/preprocess_image"], image_path=image_path)
        prep_res = client.predict(api_name="/preprocess_image", **prep_kwargs)
        prep_paths = _extract_file_paths(prep_res)
        if prep_paths:
            img_input = handle_file(prep_paths[0])

    if "/image_to_3d" not in named:
        return False
    gen_kwargs = _build_kwargs_from_api(
        named["/image_to_3d"],
        overrides={"image": img_input, "resolution": "512"},
    )
    gen_res = client.predict(api_name="/image_to_3d", **gen_kwargs)
    if _save_result_to_glb(_extract_file_paths(gen_res), dest_path):
        return True

    if "/extract_glb" in named:
        ext_kwargs = _build_kwargs_from_api(
            named["/extract_glb"],
            overrides={"decimation_target": 50000, "texture_size": 1024},
        )
        ext_res = client.predict(api_name="/extract_glb", **ext_kwargs)
        return _save_result_to_glb(_extract_file_paths(ext_res), dest_path)

    return False


def _call_generic_single_step(client: Client, named: dict[str, Any], image_path: Path, dest_path: Path) -> bool:
    """Dynamic fallback for TRELLIS / TripoSR / InstantMesh spaces discovered via `view_api`."""
    if "/preprocess_image" in named and "/generate_and_extract_glb" in named:
        prep = client.predict(api_name="/preprocess_image", **_build_kwargs_from_api(named["/preprocess_image"], image_path=image_path))
        prep_paths = _extract_file_paths(prep)
        img_override = handle_file(prep_paths[0]) if prep_paths else handle_file(str(image_path))
        res = client.predict(
            api_name="/generate_and_extract_glb",
            **_build_kwargs_from_api(named["/generate_and_extract_glb"], overrides={"image": img_override}),
        )
        return _save_result_to_glb(_extract_file_paths(res), dest_path)

    if "/preprocess" in named and "/generate_mvs" in named and "/make3d" in named:
        prep = client.predict(api_name="/preprocess", **_build_kwargs_from_api(named["/preprocess"], image_path=image_path))
        prep_paths = _extract_file_paths(prep)
        img_override = handle_file(prep_paths[0]) if prep_paths else handle_file(str(image_path))
        client.predict(
            api_name="/generate_mvs",
            **_build_kwargs_from_api(named["/generate_mvs"], overrides={"input_image": img_override}),
        )
        res = client.predict(api_name="/make3d")
        return _save_result_to_glb(_extract_file_paths(res), dest_path)

    # Generic scan of any endpoint that accepts an image and returns a filepath/Model3d
    for ep_name, ep_info in named.items():
        if ep_name.startswith("/lambda"):
            continue
        params = ep_info.get("parameters", [])
        returns = ep_info.get("returns", [])
        has_img = any(str(p.get("component", "")).lower() == "image" or "image" in str(p.get("parameter_name", "")) for p in params)
        has_file_ret = any("file" in str(r.get("python_type", {}).get("type", "")).lower() or "model" in str(r.get("component", "")).lower() for r in returns)
        if has_img and has_file_ret:
            kwargs = _build_kwargs_from_api(ep_info, image_path=image_path)
            res = client.predict(api_name=ep_name, **kwargs)
            if _save_result_to_glb(_extract_file_paths(res), dest_path):
                return True

    return False


def convert_image_with_space(
    space_id: str,
    image_path: Path,
    dest_path: Path,
    timeout_sec: float,
    hf_token: str | None = None,
) -> tuple[bool, str]:
    """Connect to a Hugging Face Space, inspect `view_api`, and run image-to-GLB conversion."""
    try:
        client = Client(space_id, token=hf_token, verbose=False, httpx_kwargs={"timeout": timeout_sec})
        api = client.view_api(return_format="dict")
        named = api.get("named_endpoints", {})
        print(f"  [{space_id}] Inspected {len(named)} endpoints: {list(named.keys())[:6]}")

        if "/generation_all" in named or "/shape_generation" in named:
            ok = _call_hunyuan3d(client, named, image_path, dest_path)
        elif "/image_to_3d" in named and "/extract_glb" in named:
            ok = _call_trellis2(client, named, image_path, dest_path)
        else:
            ok = _call_generic_single_step(client, named, image_path, dest_path)

        if ok:
            size_kb = dest_path.stat().st_size / 1024.0
            return True, f"Saved {dest_path} ({size_kb:.1f} KB) via {space_id}"
        return False, f"{space_id} completed without producing a valid .glb file"
    except Exception as exc:
        return False, f"{space_id} error: {type(exc).__name__}: {exc}"


def main() -> int:
    parser = argparse.ArgumentParser(description="Batch convert 2D images in tools/images_to_convert/ into textured .glb assets.")
    parser.add_argument("--input-dir", default="tools/images_to_convert", help="Directory containing source images.")
    parser.add_argument("--output-root", default="assets/models", help="Root assets/models directory.")
    parser.add_argument("--spaces", nargs="*", default=DEFAULT_SPACES, help="Ordered Hugging Face Spaces to try.")
    parser.add_argument("--overwrite", action="store_true", help="Re-convert even if destination .glb already exists.")
    parser.add_argument("--only", nargs="*", default=None, help="Optional list of specific filenames to process.")
    parser.add_argument("--timeout", type=float, default=180.0, help="HTTP timeout per Gradio request in seconds.")
    parser.add_argument("--token", default=os.environ.get("HF_TOKEN") or os.environ.get("HUGGINGFACEHUB_API_TOKEN"), help="Optional free Hugging Face token for higher ZeroGPU quota.")
    args = parser.parse_args()

    input_dir = Path(args.input_dir)
    output_root = Path(args.output_root)

    if not input_dir.exists():
        input_dir.mkdir(parents=True, exist_ok=True)

    images = sorted(
        p for p in input_dir.iterdir()
        if p.is_file() and p.suffix.lower() in IMAGE_EXTS and (args.only is None or p.name in args.only)
    )
    if not images:
        # Fallback discovery: check assets/images/ first, then newest image files saved today in Downloads
        fallback_sources = [Path("assets/images"), Path(r"C:\Users\Mosab\Downloads")]
        today_str = time.strftime("%Y-%m-%d")
        for src_dir in fallback_sources:
            if not src_dir.exists():
                continue
            candidates = [
                p for p in src_dir.iterdir()
                if p.is_file() and p.suffix.lower() in IMAGE_EXTS
            ]
            if src_dir.name.lower() == "downloads":
                candidates = [
                    p for p in candidates
                    if time.strftime("%Y-%m-%d", time.localtime(p.stat().st_mtime)) == today_str
                ]
                candidates.sort(key=lambda p: p.stat().st_mtime, reverse=True)
                candidates = candidates[:10]
            for c in candidates:
                dest_img = input_dir / c.name
                shutil.copy2(c, dest_img)
            if candidates:
                print(f"Copied {len(candidates)} fallback image(s) from {src_dir} to {input_dir}")
                break
        images = sorted(
            p for p in input_dir.iterdir()
            if p.is_file() and p.suffix.lower() in IMAGE_EXTS and (args.only is None or p.name in args.only)
        )

    if not images:
        print(f"No images found in {input_dir}.")
        return 0

    print(f"Found {len(images)} image(s) in {input_dir}: {[p.name for p in images]}")

    results: list[dict[str, Any]] = []
    quota_exhausted_spaces: set[str] = set()

    for img_path in images:
        category = infer_category(img_path.name)
        dest_path = output_root / category / f"{img_path.stem}.glb"

        if dest_path.exists() and dest_path.stat().st_size > 1024 and not args.overwrite:
            print(f"[SKIP] {img_path.name} -> {dest_path} already exists")
            results.append({"image": img_path.name, "dest": str(dest_path), "status": "skipped_existing"})
            continue

        print(f"\n[CONVERT] {img_path.name} -> {dest_path} (category: {category})")
        converted = False
        errors: list[str] = []

        for space_id in args.spaces:
            if space_id in quota_exhausted_spaces:
                continue
            t0 = time.time()
            ok, msg = convert_image_with_space(space_id, img_path, dest_path, args.timeout, args.token)
            elapsed = time.time() - t0
            if ok:
                print(f"  [OK] {msg} ({elapsed:.1f}s)")
                results.append({"image": img_path.name, "dest": str(dest_path), "space": space_id, "status": "ok"})
                converted = True
                break

            print(f"  [FAIL] {msg} ({elapsed:.1f}s)")
            errors.append(msg)
            lower_msg = msg.lower()
            if "zerogpu" in lower_msg or "quota" in lower_msg or "rate" in lower_msg or "exceeded" in lower_msg:
                quota_exhausted_spaces.add(space_id)

        if not converted:
            results.append({
                "image": img_path.name,
                "dest": str(dest_path),
                "status": "browser_fallback_needed",
                "errors": errors,
            })

    ok_count = sum(1 for r in results if r["status"] in ("ok", "skipped_existing"))
    pending = [r for r in results if r["status"] == "browser_fallback_needed"]

    print("\n=== SUMMARY ===")
    print(json.dumps(results, indent=2, ensure_ascii=False))

    if pending:
        print(
            f"\n[BROWSER_FALLBACK_NEEDED] {len(pending)}/{len(images)} image(s) failed or hit API quota/queue limits. "
            "Follow `.gemini/skills/auto-image-to-3d/SKILL.md` to convert pending images via the built-in browser at "
            "https://huggingface.co/spaces/tencent/Hunyuan3D-2"
        )
        return 2

    print(f"\nALL {ok_count}/{len(images)} IMAGES READY AS GLB ASSETS.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
