"""Headless Blender script to fix character normals, bake colors to 1024x1024 albedo PNG,
export FBX with embedded textures, and package Mixamo-ready flat .zip archives.

Usage (requires Blender 3.6+ or 4.x):
    blender --background --python tools/blender_bake_mixamo.py
"""

from __future__ import annotations

import os
import zipfile
from pathlib import Path

import bpy

SOURCE_DIR = Path(r"C:\Users\Mosab\Downloads\99_Others")
OUTPUT_DIR = Path(r"C:\Users\Mosab\Projects\khartoum-azhari-game\mixamo_upload_zips")


def clear_scene() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)


def process_glb(glb_path: Path) -> Path | None:
    clear_scene()
    char_name = glb_path.stem
    bpy.ops.import_scene.gltf(filepath=str(glb_path))

    meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    if not meshes:
        print(f"[SKIP] No mesh objects in {glb_path.name}")
        return None

    bpy.ops.object.select_all(action="DESELECT")
    for m in meshes:
        m.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    if len(meshes) > 1:
        bpy.ops.object.join()

    obj = bpy.context.view_layer.objects.active
    obj.name = char_name

    # Fix inverted normals so character backs never render black
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.normals_make_consistent(inside=False)
    if not obj.data.uv_layers:
        bpy.ops.uv.smart_project(angle_limit=1.15, island_margin=0.02)
    bpy.ops.object.mode_set(mode="OBJECT")

    # Bake existing GLB shaders / vertex colors into a 1024x1024 albedo PNG
    albedo_path = OUTPUT_DIR / f"{char_name}_albedo.png"
    bake_img = bpy.data.images.new(name=f"{char_name}_albedo", width=1024, height=1024, alpha=False)
    bake_img.filepath_raw = str(albedo_path)
    bake_img.file_format = "PNG"

    bpy.context.scene.render.engine = "CYCLES"
    bpy.context.scene.cycles.device = "CPU"
    bpy.context.scene.cycles.samples = 1
    bpy.context.scene.render.bake.use_pass_direct = False
    bpy.context.scene.render.bake.use_pass_indirect = False
    bpy.context.scene.render.bake.use_pass_color = True

    if not obj.data.materials:
        mat = bpy.data.materials.new(name=f"{char_name}_OrigMat")
        mat.use_nodes = True
        obj.data.materials.append(mat)

    for mat in obj.data.materials:
        if mat is None:
            continue
        mat.use_nodes = True
        nt = mat.node_tree
        # Support vertex colors (Color Attributes) when no image texture exists
        has_img = any(n.type == "TEX_IMAGE" and n.image is not None for n in nt.nodes)
        bsdf = next((n for n in nt.nodes if n.type == "BSDF_PRINCIPLED"), None)
        if not has_img and bsdf is not None and obj.data.color_attributes:
            vcol = nt.nodes.new("ShaderNodeVertexColor")
            vcol.layer_name = obj.data.color_attributes[0].name
            nt.links.new(vcol.outputs["Color"], bsdf.inputs["Base Color"])
        img_node = nt.nodes.new("ShaderNodeTexImage")
        img_node.image = bake_img
        nt.nodes.active = img_node

    bpy.ops.object.bake(type="DIFFUSE")
    bake_img.save()

    # Replace material with clean matte Principled BSDF
    clean_mat = bpy.data.materials.new(name=f"{char_name}_Mat")
    clean_mat.use_nodes = True
    nt = clean_mat.node_tree
    nt.nodes.clear()
    out_node = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Metallic"].default_value = 0.0
    bsdf.inputs["Roughness"].default_value = 0.85
    tex_node = nt.nodes.new("ShaderNodeTexImage")
    tex_node.image = bpy.data.images.load(str(albedo_path))
    nt.links.new(tex_node.outputs["Color"], bsdf.inputs["Base Color"])
    nt.links.new(bsdf.outputs["BSDF"], out_node.inputs["Surface"])

    obj.data.materials.clear()
    obj.data.materials.append(clean_mat)

    fbx_path = OUTPUT_DIR / f"{char_name}.fbx"
    bpy.ops.export_scene.fbx(
        filepath=str(fbx_path),
        use_selection=True,
        path_mode="COPY",
        embed_textures=True,
        bake_space_transform=True,
    )

    zip_path = OUTPUT_DIR / f"{char_name}.zip"
    with zipfile.ZipFile(zip_path, "w", compression=zipfile.ZIP_DEFLATED) as zf:
        zf.write(fbx_path, arcname=fbx_path.name)
        zf.write(albedo_path, arcname=albedo_path.name)
    fbx_path.unlink(missing_ok=True)
    albedo_path.unlink(missing_ok=True)
    return zip_path


def main() -> None:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    glbs = sorted(SOURCE_DIR.glob("object_0*.glb"))
    for g in glbs:
        zp = process_glb(g)
        if zp:
            print(f"[OK] {zp}")


if __name__ == "__main__":
    main()
