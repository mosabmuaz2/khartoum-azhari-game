"""Replace old character .fbx models in the Godot project with newly auto-rigged Mixamo downloads.

Workflow:
1. Extracts any .zip archives inside `C:\\Users\\Mosab\\Downloads\\99_Others` (if present).
2. Matches newly downloaded rigged Mixamo .fbx files (containing `mixamorig`) against existing
   project character files under `assets/models/characters/` by exact filename (case-insensitive)
   or matching character subfolder name.
3. Backs up the old character .fbx and its `<stem>_0.png` texture to
   `C:\\Users\\Mosab\\Downloads\\99_Others\\_backup_old_characters` (outside the Godot project).
4. Overwrites the old .fbx in place (preserving `.import` files and Godot UIDs) and extracts the
   new embedded albedo PNG into `<stem>_0.png` (plus copies any accompanying external textures).
"""

from __future__ import annotations

import shutil
import struct
import tempfile
import zipfile
from pathlib import Path

DOWNLOADS_DIR = Path(r"C:\Users\Mosab\Downloads\99_Others")
BACKUP_DIR = DOWNLOADS_DIR / "_backup_old_characters"
PROJECT_DIR = Path(r"C:\Users\Mosab\Projects\khartoum-azhari-game")
CHARACTERS_DIR = PROJECT_DIR / "assets" / "models" / "characters"

PNG_SIG = b"\x89PNG\r\n\x1a\n"
ANIM_SKIP = ("walking", "idle", "running", "jump", "crouch", "slide", "turn", "sit", "swim", "talk", "drive")


def extract_embedded_png(data: bytes) -> bytes | None:
    start = data.find(PNG_SIG)
    if start < 0:
        return None
    pos = start + len(PNG_SIG)
    n = len(data)
    while pos + 12 <= n:
        clen = struct.unpack(">I", data[pos : pos + 4])[0]
        ctype = data[pos + 4 : pos + 8]
        cend = pos + 12 + clen
        if cend > n:
            return None
        pos = cend
        if ctype == b"IEND":
            return data[start:pos]
    return None


def norm_key(text: str) -> str:
    return " ".join(text.strip().lower().split())


def build_project_character_index() -> tuple[dict[str, Path], dict[str, Path]]:
    by_filename: dict[str, Path] = {}
    by_folder: dict[str, Path] = {}
    for folder in sorted(CHARACTERS_DIR.iterdir()):
        if not folder.is_dir():
            continue
        fbxs = sorted(folder.glob("*.fbx"))
        if not fbxs:
            continue
        primary = fbxs[0]
        by_folder[norm_key(folder.name)] = primary
        for f in fbxs:
            by_filename[norm_key(f.name)] = f
            by_filename[norm_key(f.stem)] = f
    return by_filename, by_folder


def collect_candidate_downloads(tmp_extract: Path) -> list[Path]:
    candidates: list[Path] = []
    # 1. Extract any .zip files in DOWNLOADS_DIR into temporary staging outside project
    for zp in sorted(DOWNLOADS_DIR.glob("*.zip")):
        sub = tmp_extract / zp.stem
        sub.mkdir(parents=True, exist_ok=True)
        with zipfile.ZipFile(zp, "r") as zf:
            zf.extractall(sub)
        for f in sub.rglob("*.fbx"):
            candidates.append(f)

    # 2. Scan direct .fbx files in DOWNLOADS_DIR (excluding _backup_old_characters)
    for f in sorted(DOWNLOADS_DIR.glob("*.fbx"), key=lambda p: p.stat().st_mtime, reverse=True):
        candidates.append(f)
    return candidates


def main() -> None:
    by_filename, by_folder = build_project_character_index()
    BACKUP_DIR.mkdir(parents=True, exist_ok=True)

    replaced: list[dict] = []
    seen_targets: set[Path] = set()

    with tempfile.TemporaryDirectory(prefix="mixamo_extract_") as tmp_dir:
        candidates = collect_candidate_downloads(Path(tmp_dir))

        for src in candidates:
            low = src.stem.lower()
            if any(k in low for k in ANIM_SKIP):
                continue

            # Match by exact filename/stem first, then by exact character subfolder name
            target = by_filename.get(norm_key(src.name)) or by_filename.get(norm_key(src.stem))
            if target is None:
                target = by_folder.get(norm_key(src.stem))
            if target is None or target in seen_targets:
                continue

            raw = src.read_bytes()
            if b"mixamorig" not in raw:
                print(f"[SKIP] {src.name} -> not a rigged Mixamo FBX (missing mixamorig bones)")
                continue

            seen_targets.add(target)
            folder = target.parent
            backup_sub = BACKUP_DIR / folder.name
            backup_sub.mkdir(parents=True, exist_ok=True)

            # Back up old FBX before overwriting
            backup_fbx = backup_sub / target.name
            shutil.copy2(target, backup_fbx)

            # Overwrite FBX in place (keeping target.fbx.import intact!)
            shutil.copy2(src, target)

            tex_updated: list[str] = []

            # Extract embedded albedo PNG into `<target_stem>_0.png` (backing up old one first)
            png_bytes = extract_embedded_png(raw)
            if png_bytes:
                target_tex = folder / f"{target.stem}_0.png"
                if target_tex.exists():
                    shutil.copy2(target_tex, backup_sub / target_tex.name)
                target_tex.write_bytes(png_bytes)
                tex_updated.append(str(target_tex))

            # Copy any accompanying external .png/.jpg matching source stem
            for ext in ("*.png", "*.jpg", "*.jpeg"):
                for ext_tex in src.parent.glob(ext):
                    if ext_tex.stem.lower().startswith(src.stem.lower()):
                        dst_tex = folder / ext_tex.name
                        if dst_tex.exists():
                            shutil.copy2(dst_tex, backup_sub / dst_tex.name)
                        shutil.copy2(ext_tex, dst_tex)
                        tex_updated.append(str(dst_tex))

            replaced.append({
                "source": str(src),
                "target": str(target),
                "backup": str(backup_fbx),
                "import_preserved": (folder / f"{target.name}.import").exists(),
                "textures": tex_updated,
            })

    print(f"=== REPLACED {len(replaced)} RIGGED MIXAMO CHARACTER(S) ===")
    for item in replaced:
        print(f"- Target : {item['target']}")
        print(f"  Source : {item['source']}")
        print(f"  Backup : {item['backup']}")
        print(f"  .import preserved: {item['import_preserved']}")
        if item["textures"]:
            print(f"  Textures updated : {', '.join(item['textures'])}")


if __name__ == "__main__":
    main()
