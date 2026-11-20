#!/usr/bin/env python3
"""
Configures Godot 4.7.2 `.fbx.import` files across `res://assets/animations/mixamo/`,
`res://assets/models/characters/`, and `tools/characters_fbx_for_mixamo/` with:
- `SkeletonProfileHumanoid` bone retargeting (`retarget/bone_map` + `Skeleton3D` rest fixer)
- `mixamo_post_import.gd` (albedo=(1,1,1), vertex_color_use_as_albedo=false, metallic=0.0, loop modes)
"""

from pathlib import Path
import re

ROOT = Path(r"c:\Users\Mosab\Projects\khartoum-azhari-game")
TARGET_DIRS = [
    ROOT / "assets" / "animations" / "mixamo",
    ROOT / "assets" / "models" / "characters",
    ROOT / "tools" / "characters_fbx_for_mixamo",
]

LOOP_KEYWORDS = ("idle", "walking", "running", "crouch idle", "crouch walk", "sitting", "driving", "talking")

SKELETON_SUBRES = (
    '_subresources={\n'
    '"nodes": {\n'
    '"PATH:Skeleton3D": {\n'
    '"retarget/bone_map": Object(BoneMap,"resource_local_to_scene":false,"resource_name":"","profile":Object(SkeletonProfileHumanoid,"resource_local_to_scene":false,"resource_name":"","root_bone":&"Root","scale_base_bone":&"Hips","group_size":4,"bone_size":56,"script":null)\n'
    ',"bone_map/Root":&"","bone_map/Hips":&"mixamorig_Hips","bone_map/Spine":&"mixamorig_Spine","bone_map/Chest":&"mixamorig_Spine1","bone_map/UpperChest":&"mixamorig_Spine2","bone_map/Neck":&"mixamorig_Neck","bone_map/Head":&"mixamorig_Head","bone_map/LeftEye":&"","bone_map/RightEye":&"","bone_map/Jaw":&"","bone_map/LeftShoulder":&"mixamorig_LeftShoulder","bone_map/LeftUpperArm":&"mixamorig_LeftArm","bone_map/LeftLowerArm":&"mixamorig_LeftForeArm","bone_map/LeftHand":&"mixamorig_LeftHand","bone_map/LeftThumbMetacarpal":&"mixamorig_LeftHandThumb1","bone_map/LeftThumbProximal":&"mixamorig_LeftHandThumb2","bone_map/LeftThumbDistal":&"mixamorig_LeftHandThumb3","bone_map/LeftIndexProximal":&"mixamorig_LeftHandIndex1","bone_map/LeftIndexIntermediate":&"mixamorig_LeftHandIndex2","bone_map/LeftIndexDistal":&"mixamorig_LeftHandIndex3","bone_map/LeftMiddleProximal":&"mixamorig_LeftHandMiddle1","bone_map/LeftMiddleIntermediate":&"mixamorig_LeftHandMiddle2","bone_map/LeftMiddleDistal":&"mixamorig_LeftHandMiddle3","bone_map/LeftRingProximal":&"mixamorig_LeftHandRing1","bone_map/LeftRingIntermediate":&"mixamorig_LeftHandRing2","bone_map/LeftRingDistal":&"mixamorig_LeftHandRing3","bone_map/LeftLittleProximal":&"mixamorig_LeftHandPinky1","bone_map/LeftLittleIntermediate":&"mixamorig_LeftHandPinky2","bone_map/LeftLittleDistal":&"mixamorig_LeftHandPinky3","bone_map/RightShoulder":&"mixamorig_RightShoulder","bone_map/RightUpperArm":&"mixamorig_RightArm","bone_map/RightLowerArm":&"mixamorig_RightForeArm","bone_map/RightHand":&"mixamorig_RightHand","bone_map/RightThumbMetacarpal":&"mixamorig_RightHandThumb1","bone_map/RightThumbProximal":&"mixamorig_RightHandThumb2","bone_map/RightThumbDistal":&"mixamorig_RightHandThumb3","bone_map/RightIndexProximal":&"mixamorig_RightHandIndex1","bone_map/RightIndexIntermediate":&"mixamorig_RightHandIndex2","bone_map/RightIndexDistal":&"mixamorig_RightHandIndex3","bone_map/RightMiddleProximal":&"mixamorig_RightHandMiddle1","bone_map/RightMiddleIntermediate":&"mixamorig_RightHandMiddle2","bone_map/RightMiddleDistal":&"mixamorig_RightHandMiddle3","bone_map/RightRingProximal":&"mixamorig_RightHandRing1","bone_map/RightRingIntermediate":&"mixamorig_RightHandRing2","bone_map/RightRingDistal":&"mixamorig_RightHandRing3","bone_map/RightLittleProximal":&"mixamorig_RightHandPinky1","bone_map/RightLittleIntermediate":&"mixamorig_RightHandPinky2","bone_map/RightLittleDistal":&"mixamorig_RightHandPinky3","bone_map/LeftUpperLeg":&"mixamorig_LeftUpLeg","bone_map/LeftLowerLeg":&"mixamorig_LeftLeg","bone_map/LeftFoot":&"mixamorig_LeftFoot","bone_map/LeftToes":&"mixamorig_LeftToeBase","bone_map/RightUpperLeg":&"mixamorig_RightUpLeg","bone_map/RightLowerLeg":&"mixamorig_RightLeg","bone_map/RightFoot":&"mixamorig_RightFoot","bone_map/RightToes":&"mixamorig_RightToeBase","script":null)\n'
    ',\n'
    '"retarget/rest_fixer/apply_node_transforms": true,\n'
    '"retarget/rest_fixer/normalize_position_tracks": true,\n'
    '"retarget/rest_fixer/reset_all_bone_poses_after_import": true\n'
    '}\n'
    '}\n'
    '}'
)


def is_rigged_fbx(fbx_path: Path) -> bool:
    if "animations\\mixamo" in str(fbx_path) or "animations/mixamo" in str(fbx_path):
        return True
    try:
        raw = fbx_path.read_bytes()
        return b"LimbNode" in raw or b"mixamorig" in raw
    except Exception:
        return False


def configure_import_file(imp_path: Path) -> bool:
    fbx_path = imp_path.with_suffix("")
    if not fbx_path.exists():
        return False

    txt = imp_path.read_text(encoding="utf-8")
    rigged = is_rigged_fbx(fbx_path)

    # Set post-import script
    if 'import_script/path=' in txt:
        txt = re.sub(r'import_script/path="[^"]*"', 'import_script/path="res://scripts/mixamo_post_import.gd"', txt)
    else:
        txt += '\nimport_script/path="res://scripts/mixamo_post_import.gd"\n'

    # Remove SkeletonProfileHumanoid rest_fixer _subresources (runtime MixamoAnimationController
    # adapts native mixamorig_* tracks cleanly per skeleton without twisting A-pose arms).
    txt = re.sub(r"\n?_subresources=\{.*?\n\}\n(?=[a-zA-Z_/]+=|\Z)", "\n", txt, flags=re.S)

    imp_path.write_text(txt, encoding="utf-8")
    return True


def main():
    updated = 0
    for d in TARGET_DIRS:
        if not d.exists():
            continue
        for imp in sorted(d.rglob("*.fbx.import")):
            if configure_import_file(imp):
                updated += 1
    print(f"Configured Mixamo SkeletonProfileHumanoid + post-import on {updated} .fbx.import files.")


if __name__ == "__main__":
    main()
