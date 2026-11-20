#!/usr/bin/env python3
"""
Builds reference-matched enterable modular Khartoum buildings for Godot 4.7.2:
- `scenes/buildings/interactive_mosque.tscn` & `scenes/buildings/mosque_azhari.tscn`
- `scenes/buildings/interactive_compound.tscn` & `scenes/buildings/sudanese_house.tscn`
- `scenes/buildings/interactive_apartment.tscn` & `scenes/buildings/apartment_building.tscn`
- `scenes/buildings/interactive_dukkan.tscn` & `scenes/buildings/commercial_strip.tscn`
"""

import math
from pathlib import Path

BLD_DIR = Path(r"c:\Users\Mosab\Projects\khartoum-azhari-game\scenes\buildings")
BLD_DIR.mkdir(parents=True, exist_ok=True)


class TscnBuilder:
    def __init__(self, uid: str):
        self.uid = uid
        self.exts = []
        self.subs = []
        self.nodes = []
        self._box_cache = {}
        self._mat_cache = {}

    def ext(self, etype: str, path: str, eid: str):
        for e in self.exts:
            if e[2] == eid:
                return
        self.exts.append((etype, path, eid))

    def sub(self, stype: str, sid: str, body: str):
        self.subs.append((stype, sid, body))

    def pbr_mat(self, sid: str, tint: str, tex_folder: str, uv_scale: str = "Vector3(2, 2, 1)", rough: float = 0.9, metal: float = 0.0, transp: bool = False):
        if sid in self._mat_cache:
            return sid
        self._mat_cache[sid] = True
        self.ext("Texture2D", f"res://assets/textures/{tex_folder}/albedo.jpg", f"ta_{tex_folder}")
        self.ext("Texture2D", f"res://assets/textures/{tex_folder}/normal.jpg", f"tn_{tex_folder}")
        self.ext("Texture2D", f"res://assets/textures/{tex_folder}/roughness.jpg", f"tr_{tex_folder}")
        extra = "transparency = 1\n" if transp else ""
        self.sub("StandardMaterial3D", sid, f"""albedo_color = {tint}
albedo_texture = ExtResource("ta_{tex_folder}")
metallic = {metal}
roughness = {rough}
roughness_texture = ExtResource("tr_{tex_folder}")
normal_enabled = true
normal_scale = 0.75
normal_texture = ExtResource("tn_{tex_folder}")
{extra}uv1_scale = {uv_scale}""")
        return sid

    def solid_mat(self, sid: str, albedo: str, rough: float = 0.7, metal: float = 0.0, emission: str | None = None, transp: bool = False):
        if sid in self._mat_cache:
            return sid
        self._mat_cache[sid] = True
        lines = [f"albedo_color = {albedo}", f"metallic = {metal}", f"roughness = {rough}"]
        if emission:
            lines.append("emission_enabled = true")
            lines.append(f"emission = {emission}")
            lines.append("emission_energy_multiplier = 1.4")
        if transp:
            lines.append("transparency = 1")
        self.sub("StandardMaterial3D", sid, "\n".join(lines))
        return sid

    def box_res(self, sx: float, sy: float, sz: float, mat_id: str | None = None, with_shape: bool = True):
        key = (round(sx, 3), round(sy, 3), round(sz, 3), mat_id or "", with_shape)
        if key in self._box_cache:
            return self._box_cache[key]
        idx = len(self._box_cache)
        bm_id = f"BM_{idx}"
        bs_id = f"BS_{idx}" if with_shape else None
        mline = f'material = SubResource("{mat_id}")\n' if mat_id else ""
        self.sub("BoxMesh", bm_id, f"{mline}size = Vector3({sx:.3f}, {sy:.3f}, {sz:.3f})")
        if with_shape:
            self.sub("BoxShape3D", bs_id, f"size = Vector3({sx:.3f}, {sy:.3f}, {sz:.3f})")
        self._box_cache[key] = (bm_id, bs_id)
        return (bm_id, bs_id)

    def node(self, name: str, ntype: str | None, parent: str | None = None, instance: str | None = None, groups=None, props=None):
        attrs = [f'name="{name}"']
        if ntype:
            attrs.append(f'type="{ntype}"')
        if parent is not None:
            attrs.append(f'parent="{parent}"')
        if instance is not None:
            attrs.append(f'instance=ExtResource("{instance}")')
        if groups:
            attrs.append("groups=[" + ", ".join(f'"{g}"' for g in groups) + "]")
        lines = [f'[node {" ".join(attrs)}]']
        if props:
            lines.extend(props)
        self.nodes.append("\n".join(lines))

    def tform(self, x: float, y: float, z: float, rot_y: float = 0.0) -> str:
        if abs(rot_y) < 1e-4:
            return f"transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, {x:.3f}, {y:.3f}, {z:.3f})"
        c, s = math.cos(rot_y), math.sin(rot_y)
        return f"transform = Transform3D({c:.5f}, 0, {s:.5f}, 0, 1, 0, {-s:.5f}, 0, {c:.5f}, {x:.3f}, {y:.3f}, {z:.3f})"

    def static_box(self, name: str, parent: str, x: float, y: float, z: float, sx: float, sy: float, sz: float, mat_id: str, rot_y: float = 0.0, groups=None, meta_msg: str | None = None):
        bm, bs = self.box_res(sx, sy, sz, mat_id, True)
        props = [self.tform(x, y, z, rot_y)]
        if meta_msg:
            props.append(f'metadata/interact_message = "{meta_msg}"')
        self.node(name, "StaticBody3D", parent, groups=groups, props=props)
        self.node("M", "MeshInstance3D", f"{parent}/{name}", props=["visibility_range_end = 185.0", f'mesh = SubResource("{bm}")'])
        self.node("C", "CollisionShape3D", f"{parent}/{name}", props=[f'shape = SubResource("{bs}")'])

    def interactive_door(self, name: str, parent: str, x: float, y: float, z: float, sx: float, sy: float, sz: float, mat_id: str, label: str, is_shutter: bool = False, open_angle: float = 95.0, is_open: bool = True, rot_y: float = 0.0):
        self.ext("Script", "res://scripts/interactive_door.gd", "door_scr")
        bm, bs = self.box_res(sx, sy, sz, mat_id, True)
        props = [
            self.tform(x, y, z, rot_y),
            'script = ExtResource("door_scr")',
            f'door_label = "{label}"',
            f"is_shutter = {'true' if is_shutter else 'false'}",
            f"open_angle_deg = {open_angle:.1f}",
            f"is_open = {'true' if is_open else 'false'}",
        ]
        self.node(name, "StaticBody3D", parent, groups=["interactive_doors"], props=props)
        self.node("M", "MeshInstance3D", f"{parent}/{name}", props=["visibility_range_end = 160.0", f'mesh = SubResource("{bm}")'])
        self.node("C", "CollisionShape3D", f"{parent}/{name}", props=[f'shape = SubResource("{bs}")'])

    def visual_box(self, name: str, parent: str, x: float, y: float, z: float, sx: float, sy: float, sz: float, mat_id: str, rot_y: float = 0.0):
        bm, _ = self.box_res(sx, sy, sz, mat_id, False)
        self.node(name, "MeshInstance3D", parent, props=[self.tform(x, y, z, rot_y), "visibility_range_end = 160.0", f'mesh = SubResource("{bm}")'])

    def stair_ramp(self, name: str, parent: str, x: float, y: float, z: float, sx: float, sy: float, sz: float, pitch_x: float):
        _, bs = self.box_res(sx, sy, sz, None, True)
        # In Godot Transform3D(basis_x, basis_y, basis_z, origin), the 9 numbers are ROWS of the 3x3 basis matrix:
        # Row 0: (1, 0, 0), Row 1: (0, cos, -sin), Row 2: (0, sin, cos).
        # For stairs climbing UP (+Y) as Z becomes more negative (-Z), pitch_x must be NEGATIVE (-0.58)
        # so that moving in -Z increases Y!
        cx, sx_rot = math.cos(pitch_x), math.sin(pitch_x)
        tf = f"transform = Transform3D(1, 0, 0, 0, {cx:.5f}, {-sx_rot:.5f}, 0, {sx_rot:.5f}, {cx:.5f}, {x:.3f}, {y:.3f}, {z:.3f})"
        self.node(name, "StaticBody3D", parent, groups=["walkable_stair_ramps"], props=[tf])
        self.node("C", "CollisionShape3D", f"{parent}/{name}", props=[f'shape = SubResource("{bs}")'])

    def window_assembly(self, name: str, parent: str, x: float, y: float, z: float, width: float, height: float, along_z: bool, frame_mat: str, glass_mat: str, iron_mat: str, shutter_mat: str | None = None):
        self.node(name, "Node3D", parent, props=[self.tform(x, y, z, 1.5708 if along_z else 0.0)])
        p = f"{parent}/{name}"
        self.visual_box("Glass", p, 0, 0, 0, width - 0.12, height - 0.12, 0.04, glass_mat)
        self.visual_box("FrameT", p, 0, height * 0.5 - 0.04, 0, width, 0.08, 0.14, frame_mat)
        self.visual_box("FrameB", p, 0, -height * 0.5 + 0.04, 0, width, 0.08, 0.18, frame_mat)
        self.visual_box("FrameL", p, -width * 0.5 + 0.04, 0, 0, 0.08, height, 0.14, frame_mat)
        self.visual_box("FrameR", p, width * 0.5 - 0.04, 0, 0, 0.08, height, 0.14, frame_mat)
        bars = max(3, int(width / 0.35))
        for i in range(1, bars):
            bx = -width * 0.5 + i * (width / bars)
            self.visual_box(f"BarV_{i}", p, bx, 0, 0.06, 0.03, height - 0.1, 0.03, iron_mat)
        self.visual_box("BarH", p, 0, 0, 0.06, width - 0.1, 0.03, 0.03, iron_mat)
        if shutter_mat:
            self.visual_box("ShutterL", p, -width * 0.68, 0, 0.08, width * 0.36, height - 0.06, 0.04, shutter_mat)
            self.visual_box("ShutterR", p, width * 0.68, 0, 0.08, width * 0.36, height - 0.06, 0.04, shutter_mat)

    def wall_with_doorway(self, prefix: str, parent: str, cx: float, cy: float, cz: float, length: float, height: float, thick: float, door_w: float, door_h: float, along_z: bool, wall_mat: str, frame_mat: str, door_mat: str | None = None):
        side_len = (length - door_w) * 0.5
        lintel_h = height - door_h
        if along_z:
            self.static_box(f"{prefix}_L", parent, cx, cy + height * 0.5, cz - (door_w + side_len) * 0.5, thick, height, side_len, wall_mat)
            self.static_box(f"{prefix}_R", parent, cx, cy + height * 0.5, cz + (door_w + side_len) * 0.5, thick, height, side_len, wall_mat)
            if lintel_h > 0.05:
                self.static_box(f"{prefix}_Top", parent, cx, cy + door_h + lintel_h * 0.5, cz, thick, lintel_h, door_w, wall_mat)
            self.visual_box(f"{prefix}_FrameL", parent, cx, cy + door_h * 0.5, cz - door_w * 0.5 + 0.04, thick + 0.06, door_h, 0.08, frame_mat)
            self.visual_box(f"{prefix}_FrameR", parent, cx, cy + door_h * 0.5, cz + door_w * 0.5 - 0.04, thick + 0.06, door_h, 0.08, frame_mat)
            self.visual_box(f"{prefix}_FrameT", parent, cx, cy + door_h - 0.04, cz, thick + 0.06, 0.08, door_w, frame_mat)
            if door_mat:
                self.interactive_door(f"{prefix}_DoorLeaf", parent, cx, cy + door_h * 0.5, cz - door_w * 0.38, 0.07, door_h - 0.06, door_w * 0.85, door_mat, "باب الغرفة", False, 90.0, True)
        else:
            self.static_box(f"{prefix}_L", parent, cx - (door_w + side_len) * 0.5, cy + height * 0.5, cz, side_len, height, thick, wall_mat)
            self.static_box(f"{prefix}_R", parent, cx + (door_w + side_len) * 0.5, cy + height * 0.5, cz, side_len, height, thick, wall_mat)
            if lintel_h > 0.05:
                self.static_box(f"{prefix}_Top", parent, cx, cy + door_h + lintel_h * 0.5, cz, door_w, lintel_h, thick, wall_mat)
            self.visual_box(f"{prefix}_FrameL", parent, cx - door_w * 0.5 + 0.04, cy + door_h * 0.5, cz, 0.08, door_h, thick + 0.06, frame_mat)
            self.visual_box(f"{prefix}_FrameR", parent, cx + door_w * 0.5 - 0.04, cy + door_h * 0.5, cz, 0.08, door_h, thick + 0.06, frame_mat)
            self.visual_box(f"{prefix}_FrameT", parent, cx, cy + door_h - 0.04, cz, door_w, 0.08, thick + 0.06, frame_mat)
            if door_mat:
                self.interactive_door(f"{prefix}_DoorLeaf", parent, cx - door_w * 0.38, cy + door_h * 0.5, cz, door_w * 0.85, door_h - 0.06, 0.07, door_mat, "باب الديوان", False, 90.0, True)

    def wall_with_window(self, prefix: str, parent: str, cx: float, cy: float, cz: float, length: float, height: float, thick: float, win_w: float, win_h: float, sill_h: float, along_z: bool, wall_mat: str, frame_mat: str, glass_mat: str, iron_mat: str, shutter_mat: str | None = None):
        side_len = (length - win_w) * 0.5
        top_h = height - (sill_h + win_h)
        if along_z:
            self.static_box(f"{prefix}_L", parent, cx, cy + height * 0.5, cz - (win_w + side_len) * 0.5, thick, height, side_len, wall_mat)
            self.static_box(f"{prefix}_R", parent, cx, cy + height * 0.5, cz + (win_w + side_len) * 0.5, thick, height, side_len, wall_mat)
            self.static_box(f"{prefix}_Sill", parent, cx, cy + sill_h * 0.5, cz, thick, sill_h, win_w, wall_mat)
            if top_h > 0.05:
                self.static_box(f"{prefix}_Top", parent, cx, cy + sill_h + win_h + top_h * 0.5, cz, thick, top_h, win_w, wall_mat)
        else:
            self.static_box(f"{prefix}_L", parent, cx - (win_w + side_len) * 0.5, cy + height * 0.5, cz, side_len, height, thick, wall_mat)
            self.static_box(f"{prefix}_R", parent, cx + (win_w + side_len) * 0.5, cy + height * 0.5, cz, side_len, height, thick, wall_mat)
            self.static_box(f"{prefix}_Sill", parent, cx, cy + sill_h * 0.5, cz, win_w, sill_h, thick, wall_mat)
            if top_h > 0.05:
                self.static_box(f"{prefix}_Top", parent, cx, cy + sill_h + win_h + top_h * 0.5, cz, win_w, top_h, thick, wall_mat)
        self.window_assembly(f"{prefix}_Win", parent, cx, cy + sill_h + win_h * 0.5, cz, win_w, win_h, along_z, frame_mat, glass_mat, iron_mat, shutter_mat)

    def ceiling_fan(self, name: str, parent: str, x: float, y: float, z: float, mat_id: str, fan_script_ext: str):
        self.node(name, "Node3D", parent, props=[self.tform(x, y, z), f'script = ExtResource("{fan_script_ext}")'])
        p = f"{parent}/{name}"
        self.visual_box("Rod", p, 0, 0.2, 0, 0.06, 0.4, 0.06, mat_id)
        self.visual_box("BladeA", p, 0, 0, 0, 1.45, 0.03, 0.14, mat_id)
        self.visual_box("BladeB", p, 0, 0, 0, 0.14, 0.03, 1.45, mat_id)

    def write_pair(self, path_a: Path, path_b: Path | None = None):
        root_name = self.nodes[0].split('"')[1]
        fixed_nodes = []
        for idx, nblock in enumerate(self.nodes):
            if idx == 0:
                fixed_nodes.append(nblock)
                continue
            nblock = nblock.replace(f'parent="{root_name}/', 'parent="')
            nblock = nblock.replace(f'parent="{root_name}"', 'parent="."')
            fixed_nodes.append(nblock)
        load_steps = 1 + len(self.exts) + len(self.subs)
        out = [f'[gd_scene load_steps={load_steps} format=3 uid="{self.uid}"]']
        if self.exts:
            out.append("\n".join(f'[ext_resource type="{t}" path="{p}" id="{i}"]' for t, p, i in self.exts))
        if self.subs:
            out.append("\n\n".join(f'[sub_resource type="{t}" id="{i}"]\n{b}' for t, i, b in self.subs))
        out.append("\n\n".join(fixed_nodes))
        txt = "\n\n".join(out) + "\n"
        path_a.write_text(txt, encoding="utf-8")
        print(f"Wrote {path_a} (load_steps={load_steps}, {len(self.nodes)} nodes)")
        if path_b is not None:
            uid_b = self.uid[:-1] + "b"
            txt_b = txt.replace(f'uid="{self.uid}"', f'uid="{uid_b}"', 1)
            path_b.write_text(txt_b, encoding="utf-8")
            print(f"Wrote {path_b}")


# ==============================================================================
# 1. AL-AZHARI MOSQUE (matches masjid.jpg)
# ==============================================================================
def build_mosque():
    b = TscnBuilder("uid://c8azharimosque1")
    b.ext("Script", "res://scripts/mosque_adhan.gd", "adhan_scr")
    b.ext("Script", "res://scripts/ceiling_fan.gd", "fan_scr")

    m_white = b.pbr_mat("m_white", "Color(0.98, 0.98, 0.96, 1)", "plaster", "Vector3(4, 2, 1)", 0.85)
    m_tile = b.pbr_mat("m_tile", "Color(0.94, 0.95, 0.94, 1)", "ceramic_tiles", "Vector3(8, 8, 1)", 0.5)
    m_carpet = b.pbr_mat("m_carpet", "Color(0.76, 0.18, 0.20, 1)", "fabric", "Vector3(8, 6, 1)", 0.92)
    m_carpet_green = b.pbr_mat("m_carpet_green", "Color(0.14, 0.54, 0.30, 1)", "fabric", "Vector3(8, 2, 1)", 0.92)
    m_wood = b.pbr_mat("m_wood", "Color(0.55, 0.38, 0.24, 1)", "wood", "Vector3(2, 2, 1)", 0.8)

    m_green = b.solid_mat("m_green", "Color(0.16, 0.58, 0.36, 1)", 0.55)
    m_silver = b.solid_mat("m_silver", "Color(0.84, 0.86, 0.88, 1)", 0.25, 0.8)
    m_iron = b.solid_mat("m_iron", "Color(0.16, 0.18, 0.18, 1)", 0.5, 0.6)
    m_glass = b.solid_mat("m_glass", "Color(0.32, 0.52, 0.44, 0.50)", 0.15, 0.0, None, True)
    m_brass = b.solid_mat("m_brass", "Color(0.82, 0.66, 0.28, 1)", 0.3, 0.8)
    m_cooler_blue = b.solid_mat("m_cooler_blue", "Color(0.22, 0.58, 0.88, 1)", 0.2, 0.1)

    b.sub("SphereMesh", "SM_dome", f'material = SubResource("{m_green}")\nradius = 3.6\nheight = 4.8\nradial_segments = 16\nrings = 8')
    b.sub("CylinderMesh", "CM_finial", f'material = SubResource("{m_silver}")\ntop_radius = 0.05\nbottom_radius = 0.14\nheight = 1.6\nradial_segments = 10')
    b.sub("CylinderMesh", "CM_min_top", f'material = SubResource("{m_white}")\ntop_radius = 0.95\nbottom_radius = 1.05\nheight = 3.6\nradial_segments = 8')
    b.sub("SphereMesh", "SM_min_cap", f'material = SubResource("{m_green}")\nradius = 1.0\nheight = 1.8\nradial_segments = 12\nrings = 6')

    b.node("MosqueAzhari", "Node3D")
    b.static_box("PrayerFloor", "MosqueAzhari", 0, 0.05, 0, 18.2, 0.1, 16.2, m_tile)
    b.static_box("PorchFloor", "MosqueAzhari", 0, 0.04, 10.2, 12.0, 0.08, 4.4, m_tile)

    # Crisp white walls with emerald-green trim bands (matches masjid.jpg)
    b.static_box("WallNorth", "MosqueAzhari", 0, 2.7, -8.0, 18.0, 5.4, 0.45, m_white, groups=["interactable"], meta_msg="مسجد الأزهري - مرحب بكم في بيت الله")
    b.wall_with_doorway("WallSouth", "MosqueAzhari", 0, 0, 8.0, 18.0, 5.4, 0.45, 3.2, 3.2, False, m_white, m_green, m_wood)
    b.wall_with_window("WallWestA", "MosqueAzhari", -9.0, 0, -3.8, 8.0, 5.4, 0.45, 2.2, 2.0, 1.3, True, m_white, m_green, m_glass, m_iron)
    b.wall_with_window("WallWestB", "MosqueAzhari", -9.0, 0, 4.2, 8.0, 5.4, 0.45, 2.2, 2.0, 1.3, True, m_white, m_green, m_glass, m_iron)
    b.wall_with_window("WallEastA", "MosqueAzhari", 9.0, 0, -3.8, 8.0, 5.4, 0.45, 2.2, 2.0, 1.3, True, m_white, m_green, m_glass, m_iron)
    b.wall_with_window("WallEastB", "MosqueAzhari", 9.0, 0, 4.2, 8.0, 5.4, 0.45, 2.2, 2.0, 1.3, True, m_white, m_green, m_glass, m_iron)

    # Emerald green lower & upper cornice bands + square dome base + green dome
    b.visual_box("GreenBaseTrim", "MosqueAzhari", 0, 0.25, 0, 18.3, 0.35, 16.3, m_green)
    b.visual_box("GreenMidTrim", "MosqueAzhari", 0, 4.85, 0, 18.35, 0.22, 16.35, m_green)
    b.static_box("RoofSlab", "MosqueAzhari", 0, 5.55, 0, 18.6, 0.3, 16.6, m_white)
    b.visual_box("ParapetBand", "MosqueAzhari", 0, 5.95, 0, 18.7, 0.45, 16.7, m_green)
    b.static_box("DomeSquareBase", "MosqueAzhari", 0, 6.2, 0, 7.6, 1.1, 7.6, m_white)
    b.visual_box("DomeBaseTrim", "MosqueAzhari", 0, 6.8, 0, 7.8, 0.18, 7.8, m_green)
    b.node("Dome", "MeshInstance3D", "MosqueAzhari", props=[b.tform(0, 7.2, 0), 'mesh = SubResource("SM_dome")'])
    b.node("DomeFinial", "MeshInstance3D", "MosqueAzhari", props=[b.tform(0, 10.1, 0), 'mesh = SubResource("CM_finial")'])

    # Slender white & emerald-green corner Minaret + AdhanPlayer (360m / 15s / 1200s)
    b.static_box("MinaretBase", "MosqueAzhari", -7.4, 5.2, 6.8, 2.5, 10.4, 2.5, m_white)
    b.visual_box("MinaretGreenStripe1", "MosqueAzhari", -7.4, 6.2, 6.8, 2.6, 0.3, 2.6, m_green)
    b.visual_box("MinaretBalcony", "MosqueAzhari", -7.4, 10.5, 6.8, 3.3, 0.45, 3.3, m_green)
    b.visual_box("MinaretBalconyRail", "MosqueAzhari", -7.4, 11.0, 6.8, 3.2, 0.55, 3.2, m_white)
    b.node("MinaretShaft", "MeshInstance3D", "MosqueAzhari", props=[b.tform(-7.4, 12.4, 6.8), 'mesh = SubResource("CM_min_top")'])
    b.node("MinaretCap", "MeshInstance3D", "MosqueAzhari", props=[b.tform(-7.4, 14.3, 6.8), 'mesh = SubResource("SM_min_cap")'])
    b.node("MinaretFinial", "MeshInstance3D", "MosqueAzhari", props=[b.tform(-7.4, 15.8, 6.8), 'mesh = SubResource("CM_finial")'])
    b.node("AdhanPlayer", "AudioStreamPlayer3D", "MosqueAzhari", props=[b.tform(-7.4, 13.0, 6.8), "max_distance = 360.0", 'script = ExtResource("adhan_scr")'])

    # 3-Arch Front Entrance Porch + Green Frieze + Courtyard Low Wall
    b.static_box("PorchRoof", "MosqueAzhari", 0, 4.15, 10.0, 9.6, 0.45, 3.8, m_white)
    b.visual_box("PorchGreenTrim", "MosqueAzhari", 0, 4.42, 10.0, 9.8, 0.22, 4.0, m_green)
    for px in [-4.4, -1.5, 1.5, 4.4]:
        b.static_box(f"PorchCol_{px}", "MosqueAzhari", px, 2.0, 11.6, 0.42, 4.0, 0.42, m_white)
        b.visual_box(f"PorchColTrim_{px}", "MosqueAzhari", px, 2.0, 11.6, 0.46, 3.8, 0.46, m_green)
    b.node("Sign", "Label3D", "MosqueAzhari", props=[b.tform(0, 4.95, 8.35), 'text = "مسجد الأزهري"', "font_size = 78", "outline_size = 10"])
    b.static_box("ShoeRackL", "MosqueAzhari", -3.4, 0.48, 9.4, 1.6, 0.96, 0.45, m_wood)
    b.static_box("ShoeRackR", "MosqueAzhari", 3.4, 0.48, 9.4, 1.6, 0.96, 0.45, m_wood)
    b.visual_box("PorchMat1", "MosqueAzhari", 0, 0.09, 9.8, 2.4, 0.02, 1.4, m_carpet)
    b.visual_box("PorchMat2", "MosqueAzhari", -3.2, 0.09, 10.8, 2.2, 0.02, 1.2, m_carpet_green)

    # Tiled Outdoor Ablution Courtyard (ميضأة) on East side with 4 brass taps, 4 washing stools & water cooler
    b.static_box("WuduFloor", "MosqueAzhari", 12.2, 0.05, 0.0, 6.2, 0.1, 14.0, m_tile)
    b.static_box("WuduWallBack", "MosqueAzhari", 12.2, 1.1, -6.8, 6.2, 2.2, 0.3, m_white)
    b.static_box("WuduWallSide", "MosqueAzhari", 15.1, 1.1, 0.0, 0.3, 2.2, 14.0, m_white)
    b.static_box("WuduTrough", "MosqueAzhari", 9.6, 0.45, 0.0, 0.7, 0.9, 10.5, m_tile)
    for ti, tz in enumerate([-3.6, -1.2, 1.2, 3.6]):
        b.visual_box(f"Tap_{ti}", "MosqueAzhari", 9.6, 0.95, tz, 0.35, 0.08, 0.08, m_brass)
        b.static_box(f"WuduStool_{ti}", "MosqueAzhari", 10.6, 0.25, tz, 0.46, 0.5, 0.46, m_white)
    # Water Dispenser Cooler at corner
    b.static_box("WaterCoolerBody", "MosqueAzhari", 9.7, 0.6, 6.2, 0.55, 1.2, 0.55, m_white)
    b.visual_box("WaterCoolerBottle", "MosqueAzhari", 9.7, 1.45, 6.2, 0.42, 0.55, 0.42, m_cooler_blue)

    # Interior Prayer Hall Details
    for pi, (px, pz) in enumerate([(-4.2, -2.5), (4.2, -2.5), (-4.2, 2.8), (4.2, 2.8)]):
        b.static_box(f"Pillar_{pi}", "MosqueAzhari", px, 2.7, pz, 0.55, 5.4, 0.55, m_white)
    b.visual_box("MainCarpet", "MosqueAzhari", 0, 0.11, -0.5, 16.0, 0.02, 13.0, m_carpet)
    for ri, rz in enumerate([-5.5, -3.5, -1.5, 0.5, 2.5, 4.5]):
        b.visual_box(f"RowLine_{ri}", "MosqueAzhari", 0, 0.125, rz, 15.8, 0.01, 0.14, m_carpet_green)
    b.static_box("MihrabFrameL", "MosqueAzhari", -1.4, 2.0, -7.5, 0.45, 4.0, 0.65, m_green)
    b.static_box("MihrabFrameR", "MosqueAzhari", 1.4, 2.0, -7.5, 0.45, 4.0, 0.65, m_green)
    b.static_box("MihrabTop", "MosqueAzhari", 0, 3.7, -7.5, 3.2, 0.6, 0.65, m_green)
    b.static_box("Minbar", "MosqueAzhari", 2.8, 0.9, -6.9, 1.2, 1.8, 2.0, m_wood)
    b.node("QuranPlaque1", "Label3D", "MosqueAzhari", props=[b.tform(-4.5, 3.0, -7.65), 'text = "بسم الله الرحمن الرحيم"', "font_size = 44", "outline_size = 6"])
    b.node("QuranPlaque2", "Label3D", "MosqueAzhari", props=[b.tform(4.5, 3.0, -7.65), 'text = "إن الصلاة كانت على المؤمنين كتاباً موقوتاً"', "font_size = 34", "outline_size = 6"])
    b.ceiling_fan("Fan1", "MosqueAzhari", -4.2, 4.85, 0.2, m_wood, "fan_scr")
    b.ceiling_fan("Fan2", "MosqueAzhari", 4.2, 4.85, 0.2, m_wood, "fan_scr")
    b.node("InteriorLight1", "OmniLight3D", "MosqueAzhari", props=[b.tform(0, 4.7, -2.0), "light_color = Color(1, 0.9, 0.72, 1)", "light_energy = 2.4", "omni_range = 16.0"])
    b.node("InteriorLight2", "OmniLight3D", "MosqueAzhari", props=[b.tform(0, 4.7, 4.0), "light_color = Color(1, 0.9, 0.72, 1)", "light_energy = 2.0", "omni_range = 14.0"])

    b.write_pair(BLD_DIR / "mosque_azhari.tscn", BLD_DIR / "interactive_mosque.tscn")


# ==============================================================================
# 2. SUDANESE COMPOUND HOUSE & HOSH (matches sudanese_compound.jpg & rakouba.jpg)
# ==============================================================================
def build_sudanese_house():
    b = TscnBuilder("uid://c8azharihouse01")
    b.ext("Script", "res://scripts/ceiling_fan.gd", "fan_scr")

    m_wall = b.pbr_mat("m_wall", "Color(0.94, 0.84, 0.68, 1)", "plaster", "Vector3(3, 1.5, 1)", 0.9)
    m_house = b.pbr_mat("m_house", "Color(0.96, 0.88, 0.74, 1)", "plaster", "Vector3(3, 1.5, 1)", 0.88)
    m_brick = b.pbr_mat("m_brick", "Color(0.88, 0.72, 0.56, 1)", "brick", "Vector3(4, 1.5, 1)", 0.92)
    m_tile = b.pbr_mat("m_tile", "Color(0.95, 0.92, 0.86, 1)", "ceramic_tiles", "Vector3(4, 4, 1)", 0.55)
    m_wood = b.pbr_mat("m_wood", "Color(0.68, 0.48, 0.30, 1)", "painted_wood", "Vector3(2, 2, 1)", 0.82)
    m_gate = b.pbr_mat("m_gate", "Color(0.24, 0.56, 0.38, 1)", "corrugated", "Vector3(2, 2, 1)", 0.62, 0.35)
    m_shutter_grn = b.solid_mat("m_shutter_grn", "Color(0.36, 0.54, 0.44, 1)", 0.75)
    m_thatch = b.pbr_mat("m_thatch", "Color(0.86, 0.72, 0.46, 1)", "fabric", "Vector3(4, 4, 1)", 0.95)
    m_rug = b.pbr_mat("m_rug", "Color(0.84, 0.28, 0.22, 1)", "fabric", "Vector3(3, 2, 1)", 0.92)

    m_iron = b.solid_mat("m_iron", "Color(0.16, 0.18, 0.19, 1)", 0.5, 0.65)
    m_glass = b.solid_mat("m_glass", "Color(0.45, 0.68, 0.78, 0.42)", 0.15, 0.0, None, True)
    m_rope = b.solid_mat("m_rope", "Color(0.86, 0.78, 0.60, 1)", 0.9)
    m_tank = b.solid_mat("m_tank", "Color(0.18, 0.52, 0.86, 1)", 0.38)
    m_dish = b.solid_mat("m_dish", "Color(0.88, 0.90, 0.92, 1)", 0.4, 0.3)
    m_zeer = b.solid_mat("m_zeer", "Color(0.74, 0.42, 0.26, 1)", 0.85)
    m_plastic = b.solid_mat("m_plastic", "Color(0.56, 0.58, 0.56, 1)", 0.5)

    b.sub("CylinderMesh", "CM_tank", f'material = SubResource("{m_tank}")\ntop_radius = 0.82\nbottom_radius = 0.82\nheight = 1.5\nradial_segments = 14')
    b.sub("CylinderMesh", "CM_dish", f'material = SubResource("{m_dish}")\ntop_radius = 0.55\nbottom_radius = 0.08\nheight = 0.22\nradial_segments = 14')
    b.sub("SphereMesh", "SM_zeer", f'material = SubResource("{m_zeer}")\nradius = 0.42\nheight = 0.95\nradial_segments = 14\nrings = 8')

    b.node("SudaneseHouse", "Node3D")
    # High Hosh Perimeter Walls (24m x 22m) with Cream Plaster & Green Corrugated Interactive Gates (matches sudanese_compound.jpg)
    b.static_box("HoshWallN", "SudaneseHouse", 0, 1.3, -11.0, 24.0, 2.6, 0.4, m_wall)
    b.static_box("HoshWallW", "SudaneseHouse", -12.0, 1.3, 0, 0.4, 2.6, 22.0, m_wall)
    b.static_box("HoshWallE", "SudaneseHouse", 12.0, 1.3, 0, 0.4, 2.6, 22.0, m_wall)
    b.static_box("HoshWallSL", "SudaneseHouse", -6.9, 1.3, 11.0, 10.2, 2.6, 0.4, m_wall)
    b.static_box("HoshWallSR", "SudaneseHouse", 6.9, 1.3, 11.0, 10.2, 2.6, 0.4, m_wall)
    b.static_box("GatePillarL", "SudaneseHouse", -1.9, 1.5, 11.0, 0.55, 3.0, 0.55, m_house)
    b.static_box("GatePillarR", "SudaneseHouse", 1.9, 1.5, 11.0, 0.55, 3.0, 0.55, m_house)
    b.interactive_door("GateLeafL", "SudaneseHouse", -1.8, 1.2, 10.9, 1.75, 2.35, 0.08, m_gate, "بوابة الحوش", False, 92.0, True)
    b.interactive_door("GateLeafR", "SudaneseHouse", 1.8, 1.2, 10.9, 1.75, 2.35, 0.08, m_gate, "بوابة الحوش", False, -92.0, True)

    # Enterable L-Shaped Sudanese House with Louvered Green Shutters & Brick Air Vents
    b.static_box("HouseFloor", "SudaneseHouse", 0, 0.05, -4.0, 10.2, 0.1, 8.2, m_tile)
    b.static_box("HouseWallN", "SudaneseHouse", 0, 1.75, -8.0, 10.0, 3.5, 0.35, m_house)
    b.wall_with_doorway("HouseWallS", "SudaneseHouse", 0, 0, 0.0, 10.0, 3.5, 0.35, 1.5, 2.35, False, m_house, m_wood, m_wood)
    b.wall_with_window("HouseWallW", "SudaneseHouse", -5.0, 0, -4.0, 8.0, 3.5, 0.35, 1.8, 1.3, 1.0, True, m_house, m_wood, m_glass, m_iron, m_shutter_grn)
    b.wall_with_window("HouseWallE", "SudaneseHouse", 5.0, 0, -4.0, 8.0, 3.5, 0.35, 1.8, 1.3, 1.0, True, m_house, m_wood, m_glass, m_iron, m_shutter_grn)
    # Brick air vents (طاقة) above windows
    b.visual_box("AirVentW", "SudaneseHouse", -5.18, 2.85, -4.0, 0.08, 0.32, 1.2, m_brick)
    b.visual_box("AirVentE", "SudaneseHouse", 5.18, 2.85, -4.0, 0.08, 0.32, 1.2, m_brick)
    b.visual_box("AirVentS1", "SudaneseHouse", -3.2, 2.85, 0.18, 1.2, 0.32, 0.08, m_brick)
    b.visual_box("AirVentS2", "SudaneseHouse", 3.2, 2.85, 0.18, 1.2, 0.32, 0.08, m_brick)

    b.static_box("HouseRoof", "SudaneseHouse", 0, 3.65, -4.0, 10.4, 0.3, 8.4, m_house)
    b.visual_box("HouseParapetN", "SudaneseHouse", 0, 4.05, -8.1, 10.4, 0.55, 0.25, m_wall)
    b.visual_box("HouseParapetS", "SudaneseHouse", 0, 4.05, 0.1, 10.4, 0.55, 0.25, m_wall)
    b.visual_box("HouseParapetW", "SudaneseHouse", -5.1, 4.05, -4.0, 0.25, 0.55, 8.4, m_wall)
    b.visual_box("HouseParapetE", "SudaneseHouse", 5.1, 4.05, -4.0, 0.25, 0.55, 8.4, m_wall)

    # Shaded Rakouba Veranda with Woven Thatch Roof + Courtyard Terracotta Zeer Water Jar & Plastic Chairs
    b.static_box("VerandaRoof", "SudaneseHouse", 0, 2.8, 1.4, 9.6, 0.14, 2.8, m_thatch)
    b.static_box("VerandaPostL", "SudaneseHouse", -4.4, 1.4, 2.6, 0.16, 2.8, 0.16, m_wood)
    b.static_box("VerandaPostR", "SudaneseHouse", 4.4, 1.4, 2.6, 0.16, 2.8, 0.16, m_wood)
    b.node("ZeerJar", "MeshInstance3D", "SudaneseHouse", props=[b.tform(-3.6, 0.62, 0.9), 'mesh = SubResource("SM_zeer")'])
    b.static_box("ZeerStand", "SudaneseHouse", -3.6, 0.25, 0.9, 0.55, 0.5, 0.55, m_iron)
    b.static_box("CourtyardChairL", "SudaneseHouse", -4.6, 0.42, 1.2, 0.56, 0.82, 0.56, m_plastic)
    b.static_box("CourtyardChairR", "SudaneseHouse", -2.5, 0.42, 1.2, 0.56, 0.82, 0.56, m_plastic)

    # Exterior Staircase to Roof: visual steps + continuous smooth inclined ramp collider (no step-edge snags!)
    for si in range(9):
        b.visual_box(f"Step_{si}", "SudaneseHouse", 5.8, 0.2 + si * 0.38, -1.0 - si * 0.52, 1.2, 0.38, 0.55, m_brick)
    b.stair_ramp("RoofStairRamp", "SudaneseHouse", 5.8, 1.82, -3.1, 1.28, 0.16, 6.1, -0.58)
    b.static_box("RoofLanding", "SudaneseHouse", 5.4, 3.55, -5.8, 1.5, 0.22, 1.4, m_brick)
    b.static_box("TankStand", "SudaneseHouse", -3.2, 4.15, -6.0, 1.8, 0.7, 1.8, m_house)
    b.node("WaterTank", "MeshInstance3D", "SudaneseHouse", props=[b.tform(-3.2, 5.2, -6.0), 'mesh = SubResource("CM_tank")'])
    b.node("SatDish", "MeshInstance3D", "SudaneseHouse", props=["transform = Transform3D(1, 0, 0, 0, 0.707, -0.707, 0, 0.707, 0.707, 3.2, 4.3, -6.2)", 'mesh = SubResource("CM_dish")'])

    # Courtyard Neem Shade Tree + Furnished Interior Diwan & Bedroom
    b.static_box("CourtyardTreeTrunk", "SudaneseHouse", -8.2, 1.4, 5.2, 0.36, 2.8, 0.36, m_wood)
    b.visual_box("CourtyardTreeCanopy", "SudaneseHouse", -8.2, 3.4, 5.2, 3.6, 2.1, 3.6, m_shutter_grn)
    b.static_box("BedroomPartition", "SudaneseHouse", -2.2, 1.6, -6.2, 0.18, 3.2, 3.4, m_house)
    b.static_box("BedroomBedFrame", "SudaneseHouse", -3.6, 0.32, -6.4, 1.35, 0.32, 2.0, m_wood)
    b.visual_box("BedroomMattress", "SudaneseHouse", -3.6, 0.52, -6.4, 1.28, 0.14, 1.9, m_rug)
    b.static_box("BedroomWardrobe", "SudaneseHouse", -4.4, 1.0, -2.2, 0.65, 2.0, 1.2, m_wood)

    # Furnished Interior Diwan: Rug, 2 Angareeb Rope Beds, Center Table, 2 Guest Chairs, Fan, Light
    b.visual_box("DiwanRug", "SudaneseHouse", 0.6, 0.11, -4.0, 4.2, 0.02, 3.2, m_rug)
    for ai, ax in enumerate([-1.1, 3.2]):
        b.static_box(f"AngareebFrame_{ai}", "SudaneseHouse", ax, 0.28, -5.8, 1.15, 0.16, 2.0, m_wood)
        b.visual_box(f"AngareebRope_{ai}", "SudaneseHouse", ax, 0.37, -5.8, 1.05, 0.05, 1.9, m_rope)
        for lx in [-0.5, 0.5]:
            for lz in [-0.9, 0.9]:
                b.visual_box(f"ALeg_{ai}_{lx}_{lz}", "SudaneseHouse", ax + lx, 0.15, -5.8 + lz, 0.08, 0.3, 0.08, m_wood)
    b.static_box("CenterTable", "SudaneseHouse", 0.8, 0.25, -4.0, 1.2, 0.45, 0.8, m_wood)
    for ci, cx in enumerate([-0.55, 2.15]):
        b.static_box(f"GuestChairSeat_{ci}", "SudaneseHouse", cx, 0.26, -3.2, 0.52, 0.45, 0.52, m_wood)
        b.visual_box(f"GuestChairBack_{ci}", "SudaneseHouse", cx, 0.65, -2.98, 0.52, 0.45, 0.08, m_wood)
    b.visual_box("WallFrame", "SudaneseHouse", 0, 2.0, -7.78, 1.4, 0.9, 0.06, m_wood)
    b.ceiling_fan("Fan", "SudaneseHouse", 0, 3.1, -4.0, m_wood, "fan_scr")
    b.node("RoomLight", "OmniLight3D", "SudaneseHouse", props=[b.tform(0, 3.0, -4.0), "light_color = Color(1, 0.88, 0.68, 1)", "light_energy = 1.6", "distance_fade_enabled = true", "distance_fade_begin = 28.0", "distance_fade_length = 8.0", "omni_range = 8.5"])

    b.write_pair(BLD_DIR / "sudanese_house.tscn", BLD_DIR / "interactive_compound.tscn")


# ==============================================================================
# 3. 3-STORY KHARTOUM APARTMENT BUILDING (matches apartment_building.jpg)
# ==============================================================================
def build_apartment():
    b = TscnBuilder("uid://c8azhariapt0001")
    m_wall = b.pbr_mat("m_wall", "Color(0.95, 0.87, 0.73, 1)", "plaster", "Vector3(5, 3, 1)", 0.88)
    m_band = b.pbr_mat("m_band", "Color(0.90, 0.80, 0.66, 1)", "plaster", "Vector3(5, 1, 1)", 0.88)
    m_tile = b.pbr_mat("m_tile", "Color(0.92, 0.90, 0.86, 1)", "ceramic_tiles", "Vector3(6, 4, 1)", 0.55)
    m_wood = b.pbr_mat("m_wood", "Color(0.68, 0.50, 0.34, 1)", "wood", "Vector3(2, 2, 1)", 0.82)
    m_shutter_blue = b.pbr_mat("m_shutter_blue", "Color(0.32, 0.48, 0.68, 1)", "corrugated", "Vector3(2, 2, 1)", 0.6, 0.4)
    m_shutter_grn = b.pbr_mat("m_shutter_grn", "Color(0.34, 0.56, 0.46, 1)", "corrugated", "Vector3(2, 2, 1)", 0.6, 0.4)

    m_iron = b.solid_mat("m_iron", "Color(0.15, 0.16, 0.18, 1)", 0.45, 0.7)
    m_glass = b.solid_mat("m_glass", "Color(0.38, 0.54, 0.64, 0.48)", 0.15, 0.0, None, True)
    m_ac = b.solid_mat("m_ac", "Color(0.92, 0.90, 0.86, 1)", 0.5, 0.2)
    m_tank_blue = b.solid_mat("m_tank_blue", "Color(0.22, 0.52, 0.84, 1)", 0.38)
    m_tank_white = b.solid_mat("m_tank_white", "Color(0.92, 0.92, 0.90, 1)", 0.42)
    m_dish = b.solid_mat("m_dish", "Color(0.90, 0.90, 0.88, 1)", 0.4, 0.3)

    b.sub("CylinderMesh", "CM_tank_blue", f'material = SubResource("{m_tank_blue}")\ntop_radius = 0.78\nbottom_radius = 0.78\nheight = 1.45\nradial_segments = 14')
    b.sub("CylinderMesh", "CM_tank_white", f'material = SubResource("{m_tank_white}")\ntop_radius = 0.72\nbottom_radius = 0.72\nheight = 1.35\nradial_segments = 14')
    b.sub("CylinderMesh", "CM_dish", f'material = SubResource("{m_dish}")\ntop_radius = 0.52\nbottom_radius = 0.08\nheight = 0.2\nradial_segments = 12')

    b.node("ApartmentBuilding", "Node3D")
    for lvl in range(3):
        y0 = lvl * 3.4
        b.static_box(f"Floor_{lvl}", "ApartmentBuilding", 0, y0 + 0.05, 0, 18.2, 0.1, 10.2, m_tile)
        b.static_box(f"WallBack_{lvl}", "ApartmentBuilding", 0, y0 + 1.7, -5.0, 18.0, 3.4, 0.35, m_wall)
        b.static_box(f"WallLeft_{lvl}", "ApartmentBuilding", -9.0, y0 + 1.7, 0, 0.35, 3.4, 10.0, m_wall)
        b.visual_box(f"SlabBand_{lvl}", "ApartmentBuilding", 0, y0 + 3.35, 0, 18.5, 0.24, 10.5, m_band)

        if lvl == 0:
            b.static_box(f"WallRight_{lvl}", "ApartmentBuilding", 9.0, y0 + 1.7, 0, 0.35, 3.4, 10.0, m_wall)
            # Ground-floor shops with Interactive Roll-Up Metal Shutters ([E]/[K]) + concrete steps
            b.wall_with_doorway("FrontShopL", "ApartmentBuilding", -5.5, 0, 5.0, 7.0, 3.4, 0.35, 2.6, 2.5, False, m_wall, m_wood)
            b.wall_with_doorway("FrontLobby", "ApartmentBuilding", 0.0, 0, 5.0, 4.0, 3.4, 0.35, 1.8, 2.6, False, m_wall, m_wood)
            b.wall_with_doorway("FrontShopR", "ApartmentBuilding", 5.5, 0, 5.0, 7.0, 3.4, 0.35, 2.6, 2.5, False, m_wall, m_wood)
            b.interactive_door("ShutterShopL", "ApartmentBuilding", -5.5, 1.25, 5.05, 2.55, 2.45, 0.08, m_shutter_blue, "شتر الدكان الغربي", True, 0.0, True)
            b.interactive_door("ShutterShopR", "ApartmentBuilding", 5.5, 1.25, 5.05, 2.55, 2.45, 0.08, m_shutter_grn, "شتر الدكان الشرقي", True, 0.0, True)
            b.static_box("ShopStepsL", "ApartmentBuilding", -5.5, 0.12, 5.65, 3.0, 0.24, 0.9, m_band)
            b.static_box("ShopStepsR", "ApartmentBuilding", 5.5, 0.12, 5.65, 3.0, 0.24, 0.9, m_band)
            b.static_box("ShopCounterL", "ApartmentBuilding", -5.5, 0.5, 2.2, 3.4, 1.0, 0.65, m_wood)
            b.static_box("ShopCounterR", "ApartmentBuilding", 5.5, 0.5, 2.2, 3.4, 1.0, 0.65, m_wood)
        else:
            b.wall_with_doorway(f"WallRight_{lvl}", "ApartmentBuilding", 9.0, y0, 0, 10.0, 3.4, 0.35, 1.6, 2.4, True, m_wall, m_wood)
            b.static_box(f"Landing_{lvl}", "ApartmentBuilding", 10.2, y0 + 0.05, -1.0, 2.2, 0.14, 2.8, m_band)
            b.wall_with_window(f"FrontWinL_{lvl}", "ApartmentBuilding", -5.8, y0, 5.0, 6.4, 3.4, 0.35, 2.0, 1.5, 0.9, False, m_wall, m_wood, m_glass, m_iron)
            b.wall_with_doorway(f"FrontBalconyDoor_{lvl}", "ApartmentBuilding", 0.0, y0, 5.0, 5.2, 3.4, 0.35, 1.5, 2.4, False, m_wall, m_wood)
            b.wall_with_window(f"FrontWinR_{lvl}", "ApartmentBuilding", 5.8, y0, 5.0, 6.4, 3.4, 0.35, 2.0, 1.5, 0.9, False, m_wall, m_wood, m_glass, m_iron)
            # Front & Left Corner Balconies with Ornate Black Iron Railings + Split AC Compressors
            b.static_box(f"BalconyDeck_{lvl}", "ApartmentBuilding", 0, y0 + 0.08, 6.0, 5.2, 0.16, 2.0, m_band)
            b.static_box(f"BalconyRail_{lvl}", "ApartmentBuilding", 0, y0 + 0.65, 6.9, 5.2, 0.9, 0.08, m_iron)
            b.static_box(f"SideBalconyDeck_{lvl}", "ApartmentBuilding", -9.9, y0 + 0.08, 1.8, 1.8, 0.16, 4.4, m_band)
            b.static_box(f"SideBalconyRail_{lvl}", "ApartmentBuilding", -10.7, y0 + 0.65, 1.8, 0.08, 0.9, 4.4, m_iron)
            for ac_i, (ax, az) in enumerate([(-6.4, 5.32), (-3.8, 5.32), (6.4, 5.32)]):
                b.static_box(f"ACUnit_{lvl}_{ac_i}", "ApartmentBuilding", ax, y0 + 0.85, az, 0.86, 0.56, 0.36, m_ac)
                b.visual_box(f"ACFan_{lvl}_{ac_i}", "ApartmentBuilding", ax - 0.15, y0 + 0.85, az + 0.19, 0.42, 0.42, 0.03, m_iron)

    # Exterior & Interior Walkable Stairwells (treppen): visual treads + continuous smooth inclined ramp colliders
    for lvl in range(2):
        y_base = lvl * 3.4
        for s in range(8):
            b.visual_box(f"ExtStair_{lvl}_{s}", "ApartmentBuilding", 10.2, y_base + 0.2 + s * 0.42, 3.2 - s * 0.6, 1.4, 0.4, 0.6, m_band)
        b.stair_ramp(f"ExtStairRamp_{lvl}", "ApartmentBuilding", 10.2, y_base + 1.72, 1.1, 1.48, 0.16, 5.9, -0.59)
        b.stair_ramp(f"IntStairRamp_{lvl}", "ApartmentBuilding", 0.0, y_base + 1.72, 1.1, 1.55, 0.16, 5.9, -0.59)

    b.static_box("RoofSlab", "ApartmentBuilding", 0, 10.3, 0, 18.4, 0.28, 10.4, m_wall)
    b.static_box("RoofParapetF", "ApartmentBuilding", 0, 10.8, 5.1, 18.4, 0.75, 0.25, m_band)
    b.static_box("RoofParapetB", "ApartmentBuilding", 0, 10.8, -5.1, 18.4, 0.75, 0.25, m_band)
    b.static_box("RoofParapetL", "ApartmentBuilding", -9.1, 10.8, 0, 0.25, 0.75, 10.4, m_band)
    b.static_box("RoofParapetR", "ApartmentBuilding", 9.1, 10.8, 0, 0.25, 0.75, 10.4, m_band)
    b.static_box("PenthouseTower", "ApartmentBuilding", 1.2, 11.6, -1.8, 3.8, 2.4, 3.6, m_wall)
    b.node("RoofTankTop", "MeshInstance3D", "ApartmentBuilding", props=[b.tform(1.2, 13.5, -1.8), 'mesh = SubResource("CM_tank_blue")'])
    b.node("RoofTank1", "MeshInstance3D", "ApartmentBuilding", props=[b.tform(-5.5, 11.15, -2.5), 'mesh = SubResource("CM_tank_blue")'])
    b.node("RoofTank2", "MeshInstance3D", "ApartmentBuilding", props=[b.tform(5.5, 11.15, -2.5), 'mesh = SubResource("CM_tank_white")'])
    b.node("RoofTank3", "MeshInstance3D", "ApartmentBuilding", props=[b.tform(6.8, 11.15, -0.8), 'mesh = SubResource("CM_tank_blue")'])
    b.node("RoofDish1", "MeshInstance3D", "ApartmentBuilding", props=["transform = Transform3D(1, 0, 0, 0, 0.707, -0.707, 0, 0.707, 0.707, -3.5, 10.9, 3.4)", 'mesh = SubResource("CM_dish")'])
    b.node("RoofDish2", "MeshInstance3D", "ApartmentBuilding", props=["transform = Transform3D(1, 0, 0, 0, 0.707, -0.707, 0, 0.707, 0.707, -1.2, 10.9, 3.4)", 'mesh = SubResource("CM_dish")'])

    b.write_pair(BLD_DIR / "apartment_building.tscn", BLD_DIR / "interactive_apartment.tscn")


# ==============================================================================
# 4. DUKKAN & COMMERCIAL MARKET STRIP (matches dukkan_shop.jpg)
# ==============================================================================
def build_commercial_strip():
    b = TscnBuilder("uid://c8azharisouq001")
    m_wall_a = b.pbr_mat("m_wall_a", "Color(0.94, 0.88, 0.76, 1)", "plaster", "Vector3(3, 1.5, 1)", 0.88)
    m_wall_b = b.pbr_mat("m_wall_b", "Color(0.92, 0.78, 0.58, 1)", "plaster", "Vector3(3, 1.5, 1)", 0.9)
    m_brick = b.pbr_mat("m_brick", "Color(0.90, 0.74, 0.60, 1)", "brick", "Vector3(3, 1.5, 1)", 0.92)
    m_tile = b.pbr_mat("m_tile", "Color(0.92, 0.90, 0.86, 1)", "ceramic_tiles", "Vector3(10, 3, 1)", 0.55)
    m_wood = b.pbr_mat("m_wood", "Color(0.68, 0.48, 0.30, 1)", "wood", "Vector3(2, 2, 1)", 0.8)
    m_rust_tin = b.pbr_mat("m_rust_tin", "Color(0.76, 0.48, 0.34, 1)", "corrugated", "Vector3(3, 2, 1)", 0.68, 0.45)
    m_awn_teal = b.pbr_mat("m_awn_teal", "Color(0.18, 0.56, 0.52, 1)", "corrugated", "Vector3(3, 1, 1)", 0.65, 0.35)
    m_awn_org = b.pbr_mat("m_awn_org", "Color(0.88, 0.44, 0.20, 1)", "corrugated", "Vector3(3, 1, 1)", 0.65, 0.35)
    m_awn_zinc = b.pbr_mat("m_awn_zinc", "Color(0.72, 0.74, 0.76, 1)", "corrugated", "Vector3(3, 1, 1)", 0.55, 0.45)
    m_burlap = b.pbr_mat("m_burlap", "Color(0.78, 0.64, 0.46, 1)", "fabric", "Vector3(2, 2, 1)", 0.95)

    m_green = b.solid_mat("m_green", "Color(0.12, 0.48, 0.26, 1)", 0.6)
    m_shelf = b.solid_mat("m_shelf", "Color(0.58, 0.40, 0.24, 1)", 0.85)
    m_tomato = b.solid_mat("m_tomato", "Color(0.86, 0.20, 0.16, 1)", 0.65)
    m_greens = b.solid_mat("m_greens", "Color(0.24, 0.62, 0.24, 1)", 0.75)
    m_potato = b.solid_mat("m_potato", "Color(0.78, 0.62, 0.38, 1)", 0.85)
    m_fridge = b.solid_mat("m_fridge", "Color(0.82, 0.88, 0.92, 1)", 0.35, 0.3)
    m_glass = b.solid_mat("m_glass", "Color(0.45, 0.68, 0.78, 0.45)", 0.15, 0.0, None, True)
    m_dish = b.solid_mat("m_dish", "Color(0.88, 0.90, 0.92, 1)", 0.4, 0.3)

    b.sub("CylinderMesh", "CM_sack", f'material = SubResource("{m_burlap}")\ntop_radius = 0.28\nbottom_radius = 0.32\nheight = 0.68\nradial_segments = 12')
    b.sub("CylinderMesh", "CM_dish", f'material = SubResource("{m_dish}")\ntop_radius = 0.52\nbottom_radius = 0.08\nheight = 0.2\nradial_segments = 12')

    b.node("CommercialStrip", "Node3D")
    b.static_box("StripFloor", "CommercialStrip", 0, 0.05, 0, 45.0, 0.1, 7.2, m_tile)
    b.static_box("StripBackWall", "CommercialStrip", 0, 1.9, -3.4, 44.6, 3.8, 0.35, m_brick)
    b.static_box("StripRoof", "CommercialStrip", 0, 3.95, 0, 45.0, 0.3, 7.4, m_wall_a)
    # Ornate perforated rooftop parapet band + satellite dish above Dukkan (matches dukkan_shop.jpg)
    b.visual_box("RoofParapetFront", "CommercialStrip", 0, 4.35, 3.55, 45.0, 0.55, 0.22, m_wall_b)
    b.node("DukkanSatDish", "MeshInstance3D", "CommercialStrip", props=["transform = Transform3D(1, 0, 0, 0, 0.707, -0.707, 0, 0.707, 0.707, -18.5, 4.45, 0.0)", 'mesh = SubResource("CM_dish")'])

    shops = [
        ("Dukkan", "دكان الأزهري", m_wall_a, m_rust_tin, "دكان الأزهري - بقالة وخضار ومشروبات باردة"),
        ("Bakery", "مخبز الخرطوم", m_wall_b, m_awn_org, "مخبز الخرطوم - عيش بلدي سخن"),
        ("Restaurant", "مطعم فول وطعمية", m_wall_a, m_rust_tin, "مطعم فول وطعمية - فطور سوداني"),
        ("Pharmacy", "صيدلية الأزهري", m_wall_a, m_awn_teal, "صيدلية الأزهري - خدمة ٢٤ ساعة"),
        ("Barber", "صالون حلاقة", m_wall_b, m_awn_zinc, "صالون حلاقة الأزهري"),
        ("Banshar", "بنشر ولحام لساتك", m_brick, m_awn_zinc, "بنشر ولحام لساتك الأزهري"),
    ]
    for idx, (sid, title, wmat, amat, msg) in enumerate(shops):
        sx = -18.5 + idx * 7.4
        b.static_box(f"DivWall_{idx}", "CommercialStrip", sx - 3.7, 1.9, 0, 0.3, 3.8, 6.8, wmat)
        b.wall_with_doorway(f"Front_{sid}", "CommercialStrip", sx, 0, 3.4, 7.1, 3.8, 0.32, 2.8, 2.7, False, wmat, m_wood)
        # Slanted Rusty Corrugated Tin Awning on wooden support poles
        b.visual_box(f"Awning_{sid}", "CommercialStrip", sx, 2.95, 4.7, 7.2, 0.10, 2.5, amat)
        b.static_box(f"AwnPoleL_{sid}", "CommercialStrip", sx - 3.2, 1.45, 5.75, 0.10, 2.9, 0.10, m_wood)
        b.static_box(f"AwnPoleR_{sid}", "CommercialStrip", sx + 3.2, 1.45, 5.75, 0.10, 2.9, 0.10, m_wood)
        b.visual_box(f"SignBoard_{sid}", "CommercialStrip", sx, 3.45, 3.65, 5.4, 0.85, 0.14, m_green)
        b.node(f"SignText_{sid}", "Label3D", "CommercialStrip", props=[b.tform(sx, 3.45, 3.74), f'text = "{title}"', "font_size = 54", "outline_size = 8"])
        b.static_box(f"Counter_{sid}", "CommercialStrip", sx, 0.52, 0.8, 3.8, 1.04, 0.7, m_wood, groups=["interactable"], meta_msg=msg)
        b.static_box(f"Shelf_{sid}", "CommercialStrip", sx, 1.1, -2.8, 5.4, 2.0, 0.5, m_shelf)
        b.visual_box(f"GoodsA_{sid}", "CommercialStrip", sx - 1.2, 1.35, -2.8, 1.4, 0.35, 0.4, m_tomato)
        b.visual_box(f"GoodsB_{sid}", "CommercialStrip", sx + 1.2, 1.85, -2.8, 1.4, 0.35, 0.4, m_awn_org)
        b.node(f"ShopLight_{sid}", "OmniLight3D", "CommercialStrip", props=[b.tform(sx, 3.2, 0.0), "light_color = Color(1, 0.92, 0.78, 1)", "light_energy = 1.2", "distance_fade_enabled = true", "distance_fade_begin = 24.0", "distance_fade_length = 8.0", "omni_range = 7.0"])

        if sid == "Dukkan":
            # Matches dukkan_shop.jpg: Tilted wooden vegetable crate rack, 4 burlap grain sacks, tall glass beverage cooler fridge
            b.static_box("VegRack", "CommercialStrip", sx - 2.1, 0.48, 4.4, 1.6, 0.75, 1.1, m_wood)
            b.visual_box("VegTomato", "CommercialStrip", sx - 2.5, 0.92, 4.3, 0.65, 0.22, 0.55, m_tomato)
            b.visual_box("VegGreens", "CommercialStrip", sx - 1.7, 0.92, 4.3, 0.65, 0.22, 0.55, m_greens)
            b.visual_box("VegPotato", "CommercialStrip", sx - 2.1, 0.72, 4.85, 1.35, 0.22, 0.50, m_potato)
            for si, (ox, oz) in enumerate([(1.7, 4.6), (2.35, 4.6), (1.9, 5.25), (2.5, 5.2)]):
                b.node(f"GrainSack_{si}", "MeshInstance3D", "CommercialStrip", props=[b.tform(sx + ox, 0.34, oz), 'mesh = SubResource("CM_sack")'])
            b.static_box("BeverageCooler", "CommercialStrip", sx + 2.8, 1.05, 3.85, 0.85, 2.05, 0.78, m_fridge)
            b.visual_box("BeverageGlass", "CommercialStrip", sx + 2.8, 1.12, 4.26, 0.72, 1.65, 0.04, m_glass)

    b.static_box("EndWallRight", "CommercialStrip", 22.2, 1.9, 0, 0.3, 3.8, 6.8, m_wall_a)
    b.write_pair(BLD_DIR / "commercial_strip.tscn", BLD_DIR / "interactive_dukkan.tscn")


# ==============================================================================
# 5. CLOSED / LOCKED NEIGHBORHOOD HOUSE (بيوت سكنية مقفولة)
# ==============================================================================
def build_closed_house():
    b = TscnBuilder("uid://c8azhariclosed1")
    m_wall = b.pbr_mat("m_wall", "Color(0.92, 0.80, 0.64, 1)", "plaster", "Vector3(3, 1.5, 1)", 0.9)
    m_house = b.pbr_mat("m_house", "Color(0.95, 0.86, 0.72, 1)", "plaster", "Vector3(3, 1.5, 1)", 0.88)
    m_brick = b.pbr_mat("m_brick", "Color(0.86, 0.68, 0.52, 1)", "brick", "Vector3(3, 1.5, 1)", 0.92)
    m_gate = b.pbr_mat("m_gate", "Color(0.22, 0.48, 0.58, 1)", "corrugated", "Vector3(2, 2, 1)", 0.62, 0.35)
    m_wood = b.pbr_mat("m_wood", "Color(0.62, 0.44, 0.28, 1)", "painted_wood", "Vector3(2, 2, 1)", 0.82)
    m_tank = b.solid_mat("m_tank", "Color(0.18, 0.52, 0.86, 1)", 0.38)
    m_dish = b.solid_mat("m_dish", "Color(0.88, 0.90, 0.92, 1)", 0.4, 0.3)
    m_foliage = b.solid_mat("m_foliage", "Color(0.28, 0.52, 0.28, 1)", 0.85)

    b.sub("CylinderMesh", "CM_tank", f'material = SubResource("{m_tank}")\ntop_radius = 0.72\nbottom_radius = 0.72\nheight = 1.35\nradial_segments = 12')
    b.sub("CylinderMesh", "CM_dish", f'material = SubResource("{m_dish}")\ntop_radius = 0.48\nbottom_radius = 0.08\nheight = 0.20\nradial_segments = 12')

    b.node("ClosedHouse", "Node3D")
    # Closed Compound Perimeter Wall (18m x 16m) + Locked Metal Courtyard Gate + Main House Volume
    b.static_box("PerimeterWallN", "ClosedHouse", 0, 1.3, -8.0, 18.0, 2.6, 0.38, m_wall)
    b.static_box("PerimeterWallW", "ClosedHouse", -9.0, 1.3, 0, 0.38, 2.6, 16.0, m_wall)
    b.static_box("PerimeterWallE", "ClosedHouse", 9.0, 1.3, 0, 0.38, 2.6, 16.0, m_wall)
    b.static_box("PerimeterWallSL", "ClosedHouse", -5.2, 1.3, 8.0, 7.6, 2.6, 0.38, m_wall)
    b.static_box("PerimeterWallSR", "ClosedHouse", 5.2, 1.3, 8.0, 7.6, 2.6, 0.38, m_wall)
    b.interactive_door("LockedCourtyardGate", "ClosedHouse", 0.0, 1.2, 7.95, 2.8, 2.35, 0.08, m_gate, "بوابة بيت مقفول", False, 90.0, False)
    b.static_box("MainHouseBlock", "ClosedHouse", 0, 1.85, -2.2, 11.6, 3.7, 8.4, m_house, groups=["interactable"], meta_msg="بيت سكني في حي الأزهري")
    b.visual_box("RoofParapet", "ClosedHouse", 0, 3.95, -2.2, 12.0, 0.48, 8.8, m_brick)
    b.visual_box("ShutteredWindowL", "ClosedHouse", -3.2, 1.8, 2.05, 1.6, 1.3, 0.08, m_wood)
    b.visual_box("ShutteredWindowR", "ClosedHouse", 3.2, 1.8, 2.05, 1.6, 1.3, 0.08, m_wood)
    b.visual_box("CourtyardTreeCrown", "ClosedHouse", -5.5, 3.2, 3.8, 3.2, 2.0, 3.2, m_foliage)
    b.node("WaterTank", "MeshInstance3D", "ClosedHouse", props=[b.tform(-3.2, 4.4, -3.5), 'mesh = SubResource("CM_tank")'])
    b.node("SatDish", "MeshInstance3D", "ClosedHouse", props=["transform = Transform3D(1, 0, 0, 0, 0.707, -0.707, 0, 0.707, 0.707, 3.0, 4.1, -3.5)", 'mesh = SubResource("CM_dish")'])
    b.write_pair(BLD_DIR / "closed_house.tscn")


# ==============================================================================
# 6. GREAT NILE RIVER & CORNICHE (scenes/nile_river.tscn)
# ==============================================================================
def build_nile_river():
    b = TscnBuilder("uid://c8azharinile001")
    b.ext("Shader", "res://shaders/nile_water.gdshader", "nile_shd")

    m_corniche = b.pbr_mat("m_corniche", "Color(0.88, 0.84, 0.76, 1)", "ceramic_tiles", "Vector3(8, 80, 1)", 0.65)
    m_stone = b.pbr_mat("m_stone", "Color(0.82, 0.76, 0.66, 1)", "plaster", "Vector3(4, 40, 1)", 0.85)
    m_sand_bank = b.pbr_mat("m_sand_bank", "Color(0.86, 0.70, 0.50, 1)", "sand_dirt", "Vector3(6, 60, 1)", 0.95)
    m_wood = b.pbr_mat("m_wood", "Color(0.56, 0.38, 0.22, 1)", "wood", "Vector3(2, 2, 1)", 0.82)
    m_boat_blue = b.solid_mat("m_boat_blue", "Color(0.18, 0.48, 0.74, 1)", 0.65)
    m_foliage = b.solid_mat("m_foliage", "Color(0.22, 0.52, 0.26, 1)", 0.85)
    m_iron = b.solid_mat("m_iron", "Color(0.16, 0.18, 0.20, 1)", 0.5, 0.6)

    b.sub("ShaderMaterial", "SM_nile_water", 'render_priority = 0\nshader = ExtResource("nile_shd")')
    b.sub("BoxMesh", "BM_nile_water", 'material = SubResource("SM_nile_water")\nsize = Vector3(90.0, 0.22, 500.0)\nsubdivide_width = 16\nsubdivide_depth = 64')

    b.node("NileRiver", "Node3D")
    # 90m-wide, 500m-long flowing Nile River at world x = -190 (local x = -52 from root at -138), raised above y=0 ground!
    b.node("WaterSurface", "MeshInstance3D", "NileRiver", props=[b.tform(-52.0, 0.14, 0.0), 'mesh = SubResource("BM_nile_water")'])
    b.static_box("RiverBedCollider", "NileRiver", -52.0, -0.10, 0.0, 90.0, 0.2, 500.0, m_sand_bank)
    b.static_box("SandyShoreBank", "NileRiver", -6.5, 0.12, 0.0, 4.5, 0.24, 500.0, m_sand_bank)

    # Paved Nile Corniche Promenade (شارع النيل) + Low Stone Balustrade Wall + Walkable Steps to Water
    b.static_box("CornichePromenade", "NileRiver", 0.0, 0.12, 0.0, 10.5, 0.24, 480.0, m_corniche)
    b.static_box("BalustradeN", "NileRiver", -4.8, 0.65, -130.0, 0.45, 0.85, 220.0, m_stone)
    b.static_box("BalustradeMid", "NileRiver", -4.8, 0.65, 0.0, 0.45, 0.85, 26.0, m_stone)
    b.static_box("BalustradeS", "NileRiver", -4.8, 0.65, 130.0, 0.45, 0.85, 220.0, m_stone)

    for si, sz in enumerate([-16.5, 16.5]):
        for step in range(4):
            b.visual_box(f"CornicheStep_{si}_{step}", "NileRiver", -5.2 - step * 0.55, 0.22 - step * 0.03, sz, 0.6, 0.12, 4.2, m_stone)
        b.stair_ramp(f"CornicheStairRamp_{si}", "NileRiver", -6.0, 0.16, sz, 2.4, 0.12, 4.2, 0.0)

    # Corniche Sign, Benches, Shade Trees & 3 Moored Wooden Fishing Boats (مراكب صيد)
    b.node("CornicheSign", "Label3D", "NileRiver", props=[b.tform(2.5, 3.4, -4.0, 1.5708), 'text = "كورنيش نهر النيل - شارع النيل"', "font_size = 72", "outline_size = 10"])
    for bi, bz in enumerate([-85.0, -50.0, -25.0, -6.0, 12.0, 35.0, 65.0, 95.0]):
        b.static_box(f"CornicheBench_{bi}", "NileRiver", 2.2, 0.48, bz, 0.7, 0.55, 2.2, m_wood, groups=["interactable"], meta_msg="مقعد كورنيش النيل - منظر النيل الجميل")
        b.static_box(f"PalmTrunk_{bi}", "NileRiver", 3.6, 2.3, bz + 5.0, 0.38, 4.4, 0.38, m_wood)
        b.visual_box(f"PalmCrown_{bi}", "NileRiver", 3.6, 4.7, bz + 5.0, 3.8, 1.6, 3.8, m_foliage)

    for boat_i, bz in enumerate([-22.0, 0.0, 24.0]):
        b.static_box(f"FishingBoat_{boat_i}", "NileRiver", -11.5, 0.32, bz, 2.1, 0.45, 5.6, m_wood, groups=["interactable"], meta_msg="مركب صيد على نهر النيل")
        b.visual_box(f"BoatTrim_{boat_i}", "NileRiver", -11.5, 0.58, bz, 2.18, 0.14, 5.68, m_boat_blue)
        b.visual_box(f"BoatSeat_{boat_i}", "NileRiver", -11.5, 0.55, bz - 0.8, 1.9, 0.10, 0.55, m_wood)
        b.static_box(f"MooringPost_{boat_i}", "NileRiver", -7.8, 0.65, bz, 0.24, 1.1, 0.24, m_wood)

    b.write_pair(BLD_DIR.parent / "nile_river.tscn")


# ==============================================================================
# 7. WORKING GAS STATION (scenes/buildings/gas_station.tscn)
# ==============================================================================
def build_gas_station():
    b = TscnBuilder("uid://c8azharigas0001")
    b.ext("Script", "res://scripts/gas_station.gd", "gas_scr")
    m_pad = b.pbr_mat("m_pad", "Color(0.78, 0.76, 0.72, 1)", "asphalt", "Vector3(6, 4, 1)", 0.85)
    m_wall = b.pbr_mat("m_wall", "Color(0.95, 0.92, 0.86, 1)", "plaster", "Vector3(3, 2, 1)", 0.85)
    m_red = b.solid_mat("m_red", "Color(0.84, 0.18, 0.16, 1)", 0.4, 0.2)
    m_yellow = b.solid_mat("m_yellow", "Color(0.96, 0.76, 0.14, 1)", 0.4, 0.2)
    m_green = b.solid_mat("m_green", "Color(0.14, 0.56, 0.32, 1)", 0.45, 0.2)
    m_steel = b.solid_mat("m_steel", "Color(0.78, 0.80, 0.82, 1)", 0.35, 0.65)
    m_dark = b.solid_mat("m_dark", "Color(0.16, 0.18, 0.20, 1)", 0.6, 0.4)
    m_glass = b.solid_mat("m_glass", "Color(0.38, 0.58, 0.68, 0.48)", 0.15, 0.0, None, True)

    b.node("GasStation", "Node3D", props=['script = ExtResource("gas_scr")'])
    b.static_box("ForecourtPad", "GasStation", 0, 0.04, 0, 26.0, 0.08, 18.0, m_pad)

    # Tall Canopy Roof on 4 Steel Columns
    b.static_box("CanopyRoof", "GasStation", 0, 5.2, 1.5, 18.0, 0.55, 10.5, m_wall)
    b.visual_box("CanopyFasciaRed", "GasStation", 0, 5.25, 1.5, 18.3, 0.65, 10.8, m_red)
    b.visual_box("CanopyStripeYellow", "GasStation", 0, 5.0, 1.5, 18.35, 0.16, 10.85, m_yellow)
    for cx in [-6.8, 6.8]:
        for cz in [-2.4, 5.4]:
            b.static_box(f"CanopyCol_{cx}_{cz}", "GasStation", cx, 2.6, cz, 0.52, 5.2, 0.52, m_wall)

    b.node("CanopySignFront", "Label3D", "GasStation", props=[b.tform(0, 5.25, 6.96), 'text = "محطة وقود النيل والأزهري - بنزين وجازولين"', "font_size = 58", "outline_size = 10"])
    b.node("CanopySignBack", "Label3D", "GasStation", props=[b.tform(0, 5.25, -3.96, 3.14159), 'text = "محطة وقود النيل والأزهري - بنزين وجازولين"', "font_size = 58", "outline_size = 10"])

    # 2 Fuel Pump Islands with 4 Interactive Fuel Dispensers (in group "fuel_pumps")
    for idx, ix in enumerate([-3.4, 3.4]):
        b.static_box(f"PumpIsland_{idx}", "GasStation", ix, 0.14, 1.5, 1.6, 0.22, 6.8, m_wall)
        for p_sub, pz in enumerate([-0.6, 3.6]):
            p_id = idx * 2 + p_sub
            b.static_box(f"FuelPump_{p_id}", "GasStation", ix, 1.15, pz, 0.88, 1.9, 0.62, m_red if p_sub == 0 else m_green, groups=["fuel_pumps", "interactable"], meta_msg="طلمبة وقود - اقترب بالعربية واضغط [E] أو [B] لتعبئة التنك")
            b.visual_box(f"PumpScreen_{p_id}", "GasStation", ix, 1.45, pz, 0.92, 0.42, 0.44, m_wall)
            b.visual_box(f"PumpHose_{p_id}", "GasStation", ix + 0.46, 1.05, pz, 0.08, 0.95, 0.12, m_dark)

    # Illuminated Price Totem Sign
    b.static_box("PriceTotem", "GasStation", -10.8, 2.8, 6.8, 1.6, 5.6, 0.45, m_red, groups=["interactable"], meta_msg="أسعار الوقود اليوم: بنزين ١٢٠٠ ج/لتر - جازولين ١١٠٠ ج/لتر")
    b.node("TotemText", "Label3D", "GasStation", props=[b.tform(-10.8, 3.6, 7.06), 'text = "طلمبة الأزهري\\nبنزين: ١٢٠٠\\nجازولين: ١١٠٠"', "font_size = 38", "outline_size = 8"])

    # Rear Service Office Building & Oil Drums
    b.static_box("ServiceOffice", "GasStation", 0, 1.75, -6.2, 14.0, 3.5, 4.2, m_wall)
    b.visual_box("OfficeGlass", "GasStation", -2.2, 1.65, -4.08, 4.2, 1.5, 0.06, m_glass)
    b.static_box("OilDrumStack_0", "GasStation", 8.5, 0.55, -5.2, 1.4, 1.1, 1.4, m_yellow)
    b.write_pair(BLD_DIR / "gas_station.tscn")


# ==============================================================================
# 8. SUDANESE STREET KIOSK (scenes/buildings/kiosk.tscn)
# ==============================================================================
def build_kiosk():
    b = TscnBuilder("uid://c8azharikiosk01")
    m_body = b.pbr_mat("m_body", "Color(0.18, 0.54, 0.78, 1)", "corrugated", "Vector3(2, 2, 1)", 0.55, 0.4)
    m_trim = b.solid_mat("m_trim", "Color(0.96, 0.78, 0.18, 1)", 0.45)
    m_wood = b.pbr_mat("m_wood", "Color(0.68, 0.48, 0.28, 1)", "wood", "Vector3(2, 2, 1)", 0.8)
    m_cooler = b.solid_mat("m_cooler", "Color(0.86, 0.20, 0.18, 1)", 0.35, 0.2)
    m_snacks = b.solid_mat("m_snacks", "Color(0.92, 0.54, 0.16, 1)", 0.65)

    b.node("Kiosk", "Node3D")
    b.static_box("KioskBase", "Kiosk", 0, 0.55, 0, 2.6, 1.1, 2.2, m_body, groups=["interactable"], meta_msg="كشك الأزهري - مياه باردة، بسكويت، عصائر، ورصيد")
    b.static_box("KioskBack", "Kiosk", 0, 1.55, -0.98, 2.6, 1.1, 0.22, m_body)
    b.static_box("KioskPillarL", "Kiosk", -1.2, 1.55, 0.98, 0.14, 1.1, 0.14, m_trim)
    b.static_box("KioskPillarR", "Kiosk", 1.2, 1.55, 0.98, 0.14, 1.1, 0.14, m_trim)
    b.static_box("KioskRoof", "Kiosk", 0, 2.22, 0.35, 3.0, 0.16, 3.1, m_trim)
    b.visual_box("CounterShelf", "Kiosk", 0, 1.12, 1.05, 2.5, 0.08, 0.48, m_wood)
    b.visual_box("SnackDisplayA", "Kiosk", -0.65, 1.32, 0.95, 0.75, 0.34, 0.28, m_snacks)
    b.visual_box("SnackDisplayB", "Kiosk", 0.65, 1.32, 0.95, 0.75, 0.34, 0.28, m_trim)
    b.static_box("DrinkCooler", "Kiosk", 1.75, 0.95, 0.1, 0.78, 1.9, 0.75, m_cooler)
    b.node("KioskSign", "Label3D", "Kiosk", props=[b.tform(0, 2.48, 1.92), 'text = "كشك المرطبات والبارد"', "font_size = 42", "outline_size = 8"])
    b.write_pair(BLD_DIR / "kiosk.tscn")


# ==============================================================================
# 9. SUDANESE AMARY / SA'UD TOBACCO SHOP (scenes/buildings/amary_saud_shop.tscn)
# ==============================================================================
def build_amary_saud_shop():
    b = TscnBuilder("uid://c8azhariamary01")
    m_wall = b.pbr_mat("m_wall", "Color(0.95, 0.88, 0.74, 1)", "plaster", "Vector3(3, 2, 1)", 0.88)
    m_tile = b.pbr_mat("m_tile", "Color(0.92, 0.90, 0.84, 1)", "ceramic_tiles", "Vector3(4, 4, 1)", 0.55)
    m_wood = b.pbr_mat("m_wood", "Color(0.58, 0.38, 0.22, 1)", "wood", "Vector3(2, 2, 1)", 0.8)
    m_green = b.solid_mat("m_green", "Color(0.10, 0.44, 0.22, 1)", 0.55)
    m_gold = b.solid_mat("m_gold", "Color(0.88, 0.68, 0.18, 1)", 0.35, 0.65)
    m_jar_brown = b.solid_mat("m_jar_brown", "Color(0.38, 0.24, 0.14, 1)", 0.45)
    m_packet = b.solid_mat("m_packet", "Color(0.84, 0.76, 0.58, 1)", 0.85)

    b.sub("CylinderMesh", "CM_jar", f'material = SubResource("{m_jar_brown}")\ntop_radius = 0.13\nbottom_radius = 0.15\nheight = 0.34\nradial_segments = 10')

    b.node("AmarySaudShop", "Node3D")
    b.static_box("ShopFloor", "AmarySaudShop", 0, 0.06, 0, 8.6, 0.12, 6.8, m_tile)
    b.static_box("BackWall", "AmarySaudShop", 0, 1.9, -3.2, 8.6, 3.8, 0.32, m_wall)
    b.static_box("LeftWall", "AmarySaudShop", -4.15, 1.9, 0, 0.32, 3.8, 6.4, m_wall)
    b.static_box("RightWall", "AmarySaudShop", 4.15, 1.9, 0, 0.32, 3.8, 6.4, m_wall)
    b.wall_with_doorway("FrontWall", "AmarySaudShop", 0, 0, 3.2, 8.3, 3.8, 0.32, 3.4, 2.75, False, m_wall, m_wood)
    b.static_box("ShopRoof", "AmarySaudShop", 0, 3.92, 0.5, 9.0, 0.26, 7.8, m_wall)
    b.visual_box("AwningCanopy", "AmarySaudShop", 0, 3.05, 4.4, 8.6, 0.12, 2.2, m_green)

    # Prominent Green & Gold Arabic Signage
    b.visual_box("SignBoard", "AmarySaudShop", 0, 3.55, 3.48, 7.4, 0.95, 0.16, m_green)
    b.visual_box("SignGoldFrame", "AmarySaudShop", 0, 3.55, 3.45, 7.6, 1.05, 0.12, m_gold)
    b.node("SignTitle", "Label3D", "AmarySaudShop", props=[b.tform(0, 3.58, 3.59), 'text = "محل عماري وصعوط وتمباك الأصيل"', "font_size = 54", "outline_size = 9"])

    # Display Counter, Brass Scale, Traditional Storage Jars (برطمانات عماري وصعوط) & Wrapped Packets
    b.static_box("MainCounter", "AmarySaudShop", 0, 0.54, 0.9, 4.8, 1.08, 0.78, m_wood, groups=["interactable"], meta_msg="محل عماري وصعوط وتمباك الأصيل - عماري الفاشر وصعوط ممتاز")
    b.visual_box("BrassScale", "AmarySaudShop", -1.2, 1.24, 0.9, 0.44, 0.32, 0.26, m_gold)
    for pi in range(6):
        b.visual_box(f"AmaryPacket_{pi}", "AmarySaudShop", 0.3 + pi * 0.28, 1.14, 0.9, 0.20, 0.12, 0.24, m_packet)

    b.static_box("BackShelf", "AmarySaudShop", 0, 1.25, -2.7, 6.4, 2.3, 0.52, m_wood)
    for ji in range(8):
        jx = -2.45 + ji * 0.70
        b.node(f"SaoudJar_{ji}", "MeshInstance3D", "AmarySaudShop", props=[b.tform(jx, 1.55, -2.65), 'mesh = SubResource("CM_jar")'])
    b.write_pair(BLD_DIR / "amary_saud_shop.tscn")


# ==============================================================================
# 10. SHADED BUS STATION / STOP (scenes/buildings/bus_station.tscn)
# ==============================================================================
def build_bus_station():
    b = TscnBuilder("uid://c8azharibusst01")
    m_plat = b.pbr_mat("m_plat", "Color(0.84, 0.80, 0.74, 1)", "ceramic_tiles", "Vector3(6, 2, 1)", 0.65)
    m_canopy = b.solid_mat("m_canopy", "Color(0.14, 0.52, 0.32, 1)", 0.45, 0.3)
    m_post = b.solid_mat("m_post", "Color(0.22, 0.24, 0.26, 1)", 0.5, 0.7)
    m_bench = b.pbr_mat("m_bench", "Color(0.66, 0.46, 0.28, 1)", "wood", "Vector3(2, 1, 1)", 0.8)
    m_gold = b.solid_mat("m_gold", "Color(0.92, 0.74, 0.20, 1)", 0.4)

    b.node("BusStation", "Node3D")
    # Walkable Raised Boarding Platform + Smooth Walkable Stair Ramp
    b.static_box("BoardingPlatform", "BusStation", 0, 0.14, 0, 11.5, 0.28, 3.8, m_plat, groups=["bus_stations"])
    b.stair_ramp("PlatformStairRamp", "BusStation", 0, 0.14, 2.2, 4.5, 0.12, 1.2, -0.24)
    for px in [-4.8, 0.0, 4.8]:
        b.static_box(f"CanopyPost_{px}", "BusStation", px, 1.65, -1.4, 0.18, 3.1, 0.18, m_post)
    b.static_box("CanopyRoof", "BusStation", 0, 3.25, -0.2, 12.0, 0.16, 4.0, m_canopy)
    b.visual_box("CanopyGoldStripe", "BusStation", 0, 3.35, 1.78, 12.05, 0.14, 0.12, m_gold)
    b.static_box("WaitingBenchL", "BusStation", -2.6, 0.52, -0.8, 3.2, 0.48, 0.65, m_bench, groups=["interactable"], meta_msg="موقف بصات الأزهري - انتظر البص واضغط [E] للركوب أو [G] للقيادة")
    b.static_box("WaitingBenchR", "BusStation", 2.6, 0.52, -0.8, 3.2, 0.48, 0.65, m_bench)
    b.node("StationSign", "Label3D", "BusStation", props=[b.tform(0, 3.65, 1.86), 'text = "موقف بصات الأزهري - السوق العربي - شارع النيل"', "font_size = 48", "outline_size = 9"])
    b.write_pair(BLD_DIR / "bus_station.tscn")


# ==============================================================================
# 11. DEDICATED PAVED PARKING LOT (scenes/buildings/parking_lot.tscn)
# ==============================================================================
def build_parking_lot():
    b = TscnBuilder("uid://c8azharipark001")
    m_asph = b.pbr_mat("m_asph", "Color(0.32, 0.32, 0.34, 1)", "asphalt", "Vector3(8, 5, 1)", 0.88)
    m_line = b.solid_mat("m_line", "Color(0.95, 0.94, 0.88, 1)", 0.8)
    m_stop = b.solid_mat("m_stop", "Color(0.92, 0.72, 0.16, 1)", 0.75)
    m_shade = b.pbr_mat("m_shade", "Color(0.24, 0.46, 0.62, 1)", "corrugated", "Vector3(4, 2, 1)", 0.6, 0.35)
    m_post = b.solid_mat("m_post", "Color(0.22, 0.24, 0.26, 1)", 0.5, 0.7)

    b.node("ParkingLot", "Node3D")
    b.static_box("AsphaltPad", "ParkingLot", 0, 0.03, 0, 18.0, 0.06, 11.0, m_asph, groups=["parking_lots"])
    b.static_box("ShadeCanopy", "ParkingLot", 0, 3.1, -2.2, 16.5, 0.14, 5.4, m_shade)
    for px in [-7.2, 0.0, 7.2]:
        b.static_box(f"ShadePost_{px}", "ParkingLot", px, 1.55, -4.4, 0.18, 3.1, 0.18, m_post)
    for bi in range(6):
        lx = -7.5 + bi * 3.0
        b.visual_box(f"BayLine_{bi}", "ParkingLot", lx, 0.065, -2.0, 0.14, 0.01, 4.8, m_line)
        if bi < 5:
            b.static_box(f"WheelStop_{bi}", "ParkingLot", lx + 1.5, 0.12, -3.9, 1.8, 0.14, 0.24, m_stop)
    b.node("ParkingSign", "Label3D", "ParkingLot", props=[b.tform(-7.8, 2.6, 4.8), 'text = "P موقف سيارات"', "font_size = 54", "outline_size = 8"])
    b.write_pair(BLD_DIR / "parking_lot.tscn")


if __name__ == "__main__":
    build_mosque()
    build_sudanese_house()
    build_apartment()
    build_commercial_strip()
    build_closed_house()
    build_nile_river()
    build_gas_station()
    build_kiosk()
    build_amary_saud_shop()
    build_bus_station()
    build_parking_lot()
