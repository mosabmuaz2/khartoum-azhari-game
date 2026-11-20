#!/usr/bin/env python3
"""
Download Poly Haven 1K leaf Alpha maps, composite crisp 1024x1024 RGBA PNGs
with edge-color bleed (prevents mipmap dark fringe), and update `.gltf` materials
to `alphaMode: MASK`, `alphaCutoff: 0.30`, `doubleSided: true`.
"""

import json
import urllib.request
from pathlib import Path
import numpy as np
from PIL import Image, ImageFilter

try:
    import truststore

    truststore.inject_into_ssl()
except Exception:
    pass


TARGETS = [
    {
        "asset_id": "island_tree_02",
        "alpha_key": "leaves_alpha",
        "gltf": Path("assets/models/foliage/island_tree_02/island_tree_02.gltf"),
        "diff": Path("assets/models/foliage/island_tree_02/textures/island_tree_02_leaves_diff_4k.jpg"),
        "out_rgba": Path("assets/models/foliage/island_tree_02/textures/island_tree_02_leaves_rgba.png"),
        "img_match": "leaves_diff",
        "mat_match": "leaves",
    },
    {
        "asset_id": "wild_rooibos_bush",
        "alpha_key": "Alpha",
        "gltf": Path("assets/models/foliage/wild_rooibos_bush/wild_rooibos_bush.gltf"),
        "diff": Path("assets/models/foliage/wild_rooibos_bush/textures/wild_rooibos_bush_diff_4k.jpg"),
        "out_rgba": Path("assets/models/foliage/wild_rooibos_bush/textures/wild_rooibos_bush_rgba.png"),
        "img_match": "diff",
        "mat_match": "",
    },
    {
        "asset_id": "shrub_01",
        "alpha_key": "Alpha",
        "gltf": Path("assets/models/foliage/shrub_01/shrub_01.gltf"),
        "diff": Path("assets/models/foliage/shrub_01/textures/shrub_01_diff_4k.jpg"),
        "out_rgba": Path("assets/models/foliage/shrub_01/textures/shrub_01_rgba.png"),
        "img_match": "diff",
        "mat_match": "",
    },
]


def bleed_rgb_into_transparent(rgb: np.ndarray, alpha: np.ndarray) -> np.ndarray:
    """Propagate leaf green RGB out into alpha==0 pixels so mipmaps never bleed black."""
    out = rgb.copy()
    opaque = alpha > 24
    for _ in range(6):
        if np.all(opaque):
            break
        shifted_colors = []
        shifted_masks = []
        for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1)):
            sc = np.roll(np.roll(out, dy, axis=0), dx, axis=1)
            sm = np.roll(np.roll(opaque, dy, axis=0), dx, axis=1)
            shifted_colors.append(sc)
            shifted_masks.append(sm)
        any_neighbor = shifted_masks[0] | shifted_masks[1] | shifted_masks[2] | shifted_masks[3]
        fill_mask = (~opaque) & any_neighbor
        if not np.any(fill_mask):
            break
        accum = np.zeros_like(out, dtype=np.float32)
        cnt = np.zeros(alpha.shape, dtype=np.float32)
        for sc, sm in zip(shifted_colors, shifted_masks):
            w = sm.astype(np.float32)
            accum += sc.astype(np.float32) * w[:, :, None]
            cnt += w
        out[fill_mask] = np.clip(accum[fill_mask] / np.maximum(1.0, cnt[fill_mask])[:, None], 0, 255).astype(np.uint8)
        opaque = opaque | fill_mask
    return out


def main() -> None:
    for spec in TARGETS:
        if not spec["gltf"].exists() or not spec["diff"].exists():
            continue
        tmp_alpha = spec["out_rgba"].with_name(spec["asset_id"] + "_alpha_tmp.png")
        if not tmp_alpha.exists():
            req = urllib.request.Request(
                f"https://api.polyhaven.com/files/{spec['asset_id']}",
                headers={"User-Agent": "Mozilla/5.0"},
            )
            data = json.loads(urllib.request.urlopen(req, timeout=20).read())
            url = data[spec["alpha_key"]]["1k"]["png"]["url"]
            urllib.request.urlretrieve(url, tmp_alpha)

        with Image.open(spec["diff"]) as d_im, Image.open(tmp_alpha) as a_im:
            d_rgb = d_im.convert("RGB").resize((1024, 1024), Image.Resampling.LANCZOS)
            a_l = a_im.convert("L").resize((1024, 1024), Image.Resampling.LANCZOS)
            rgb_arr = np.asarray(d_rgb, dtype=np.uint8)
            a_arr = np.asarray(a_l, dtype=np.uint8)
            bled = bleed_rgb_into_transparent(rgb_arr, a_arr)
            rgba = np.dstack([bled, a_arr])
            Image.fromarray(rgba, mode="RGBA").save(spec["out_rgba"], optimize=True)

        if tmp_alpha.exists():
            tmp_alpha.unlink()

        gltf = json.loads(spec["gltf"].read_text(encoding="utf-8"))
        rel_rgba = "textures/" + spec["out_rgba"].name
        for img in gltf.get("images", []):
            uri = str(img.get("uri", "")).lower()
            if spec["img_match"] in uri or rel_rgba.lower() in uri:
                img["uri"] = rel_rgba
                img["mimeType"] = "image/png"
        for mat in gltf.get("materials", []):
            mname = str(mat.get("name", "")).lower()
            if not spec["mat_match"] or spec["mat_match"] in mname:
                mat["alphaMode"] = "MASK"
                mat["alphaCutoff"] = 0.30
                mat["doubleSided"] = True
        spec["gltf"].write_text(json.dumps(gltf, separators=(",", ":")), encoding="utf-8")
        print(f"OK {spec['asset_id']} -> {spec['out_rgba']} (opaque%={100.0 * np.mean(a_arr > 76):.1f}%)")


if __name__ == "__main__":
    main()
