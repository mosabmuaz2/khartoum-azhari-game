---
name: auto-image-to-3d
description: >-
  Convert 2D reference images in tools/images_to_convert/ into textured 3D .glb
  models automatically using public Hugging Face Spaces (Hunyuan3D-2, TRELLIS.2,
  TripoSR, InstantMesh) via gradio_client with automatic browser fallback and
  Godot 4.7+ import verification. Use whenever new images are placed in
  tools/images_to_convert/ or the user asks to turn photos into 3D .glb assets.
---

# Auto Image-to-3D (`.glb`) Converter Skill

Turns any `.png`, `.jpg`, `.jpeg`, or `.webp` image placed in `tools/images_to_convert/`
into a textured 3D `.glb` asset routed to `assets/models/buildings/`,
`assets/models/vehicles/`, or `assets/models/props/` with zero paid subscriptions.

## Prerequisites

- Python package `gradio_client` (and `truststore` for Windows system CA verification):
  ```powershell
  pip install -U gradio_client
  ```
- Input images placed in `tools/images_to_convert/`.

## Filename-to-Folder Routing

`tools/batch_image_to_glb.py` routes each output `<stem>.glb` automatically by filename:
- `assets/models/vehicles/` — filenames containing `amjad`, `boks`, `pickup`, `karo`, `cart`, `raksha`, `car`, `van`, `truck`, `daffar`, `bus`, `donkey`, `taxi`, `auto`, `vehicle`
- `assets/models/buildings/` — filenames containing `compound`, `house`, `jalous`, `apartment`, `mosque`, `rakouba`, `dukkan`, `shop`, `tea_stall`, `building`, `hosh`, `bakery`, `pharmacy`, `salon`, `kiosk`
- `assets/models/props/` — all other props and animals (`table`, `chair`, `barrel`, `crate`, `lantern`, `pot`, `bucket`, `plant`, etc.)

## One-Command Batch Conversion

Run from the project root:

```powershell
python tools/batch_image_to_glb.py
```

### Useful Flags
- `--overwrite`: Re-generate `.glb` files even if they already exist on disk.
- `--only tea_stall.jpg rakouba.jpg`: Process specific images only.
- `--spaces tencent/Hunyuan3D-2 microsoft/TRELLIS.2`: Override the Space priority list.
- `--token <hf_token>`: Optional free Hugging Face read token (or set `HF_TOKEN` env var) for higher ZeroGPU quota.
- `--timeout 180`: Adjust per-request timeout in seconds.

### How It Works
1. Scans `tools/images_to_convert/` (or falls back to `assets/images/` or today's newest images in `C:\Users\Mosab\Downloads` if `tools/images_to_convert/` is empty).
2. Connects to each Space using `gradio_client.Client` (default order: `tencent/Hunyuan3D-2`, `tencent/Hunyuan3D-2mini-Turbo`, `tencent/Hunyuan3D-2.1`, `microsoft/TRELLIS.2`, `trellis-community/TRELLIS`, `JeffreyXiang/TRELLIS`, `stabilityai/TripoSR`, `TencentARC/InstantMesh`).
3. Inspects `client.view_api(return_format="dict")` dynamically before submitting so arguments always match the live Space schema.
4. Requests textured generation (`/generation_all` -> fallback `/shape_generation` on Hunyuan3D, or `/image_to_3d` + `/extract_glb` on TRELLIS.2) and saves the resulting `.glb` into `assets/models/buildings/`, `assets/models/vehicles/`, or `assets/models/props/`.
5. Skips Spaces that hit ZeroGPU quota limits and prints `[BROWSER_FALLBACK_NEEDED]` with any remaining images.

## Auto-Import & Placement in Godot (`AssetPackLoader`)

`scripts/asset_pack_loader.gd` (attached to `AssetPack` in `scenes/main.tscn`) automatically scans `res://assets/models/buildings/`, `res://assets/models/vehicles/`, and `res://assets/models/props/` on scene startup, normalizes bounding boxes so each base sits at `y = 0.0`, scales meshes to Khartoum proportions, generates `StaticBody3D` trimesh collisions (`create_trimesh_collision()`), and places them into Al-Azhari neighborhood slots.

## Browser Fallback Procedure (When Spaces Rate-Limit or Timeout)

If `tools/batch_image_to_glb.py` exits with code `2` (`[BROWSER_FALLBACK_NEEDED]`):

1. Stage the remaining images under the conversation artifact directory (`<Artifact Directory Path>/browser_sandbox/uploads/<filename>`).
2. Delegate to the `browser` subagent to open `https://huggingface.co/spaces/tencent/Hunyuan3D-2` (or `https://huggingface.co/spaces/microsoft/TRELLIS.2`), upload each image using file chooser upload, run **Generate Shape & Texture** (or **Gen All**), download the `.glb` artifact, and copy it into `assets/models/<category>/<stem>.glb`.

## Godot 4.7+ Verification

After new `.glb` files land in `assets/models/`, run headless import and main scene validation:

```powershell
$godot = "C:\Users\Mosab\Desktop\Godot_v4.7.2-stable_win64.exe"
Start-Process -FilePath $godot -ArgumentList "--headless","--editor","--quit","--path","." -Wait -NoNewWindow
```

Verify that `.glb.import` files are generated cleanly with zero load errors when instantiating via `ResourceLoader.load("res://assets/models/<category>/<name>.glb")`.
