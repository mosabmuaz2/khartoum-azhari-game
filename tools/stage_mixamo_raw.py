import os
import shutil
import sys

PROJECT_DIR = r"c:\Users\Mosab\Projects\khartoum-azhari-game"
DOWNLOADS_DIR = r"C:\Users\Mosab\.gemini\antigravity\brain\e8bf1435-86dd-421f-ae80-9333918e73b0\browser_sandbox\downloads"
EXISTING_DIR = os.path.join(PROJECT_DIR, "assets", "animations", "mixamo")
TARGET_DIR = os.path.join(PROJECT_DIR, "assets", "animations", "mixamo_raw")

# Mapping: target_clean_name -> (source_dir, source_filename)
CLIP_MAP = {
    # 1. Core Locomotion & Idle
    "Idle.fbx": (EXISTING_DIR, "Idle.fbx"),
    "Idle_LookAround.fbx": (DOWNLOADS_DIR, "Looking_Around.fbx"),
    "Walk.fbx": (EXISTING_DIR, "Walking.fbx"),
    "Run.fbx": (EXISTING_DIR, "Running.fbx"),
    "Sprint.fbx": (DOWNLOADS_DIR, "Fast_Run.fbx"),
    "Crouch_Idle.fbx": (EXISTING_DIR, "Crouch Idle.fbx"),
    "Crouch_Walk.fbx": (EXISTING_DIR, "Crouch Walk.fbx"),
    "Turn_Left.fbx": (DOWNLOADS_DIR, "Left_Turn.fbx"),
    "Turn_Right.fbx": (DOWNLOADS_DIR, "Right_Turn.fbx"),
    "Run_To_Stop.fbx": (EXISTING_DIR, "Run To Stop.fbx"),
    "Running_Slide.fbx": (EXISTING_DIR, "Running Slide.fbx"),

    # 2. Sitting & Chairs
    "Sit_Idle.fbx": (EXISTING_DIR, "Sitting.fbx"),
    "Sit_Talking.fbx": (DOWNLOADS_DIR, "Sitting_Talking.fbx"),
    "Sit_Clap.fbx": (DOWNLOADS_DIR, "Sitting_Clap.fbx"),
    "Stand_To_Sit.fbx": (DOWNLOADS_DIR, "Stand_To_Sit.fbx"),
    "Sit_To_Stand.fbx": (DOWNLOADS_DIR, "Sit_To_Stand.fbx"),

    # 3. Market / Vendors / Carrying
    "Yelling.fbx": (DOWNLOADS_DIR, "Yelling.fbx"),
    "Cheering.fbx": (DOWNLOADS_DIR, "Cheering.fbx"),
    "Talking.fbx": (EXISTING_DIR, "Talking.fbx"),
    "Arguing.fbx": (DOWNLOADS_DIR, "Standing_Arguing.fbx"),
    "Pointing.fbx": (DOWNLOADS_DIR, "Pointing_Forward.fbx"),
    "Sit_Pointing.fbx": (DOWNLOADS_DIR, "Pointing.fbx"),
    "Carrying.fbx": (DOWNLOADS_DIR, "Carrying.fbx"),
    "Carrying_Walk.fbx": (DOWNLOADS_DIR, "Holding_Walk.fbx"),
    "Pick_Up.fbx": (EXISTING_DIR, "Picking Up.fbx"),
    "Put_Down.fbx": (DOWNLOADS_DIR, "Putting_Down.fbx"),

    # 4. Cemetery / Hospital / Clinic / Medical
    "Crying.fbx": (DOWNLOADS_DIR, "Crying.fbx"),
    "Sad_Idle.fbx": (DOWNLOADS_DIR, "Sad_Idle.fbx"),
    "Kneeling_Pray.fbx": (DOWNLOADS_DIR, "Praying_1.fbx"),
    "Injured_Idle.fbx": (DOWNLOADS_DIR, "Injured_Idle.fbx"),
    "Injured_Walk.fbx": (DOWNLOADS_DIR, "Injured_Walk.fbx"),
    "Dizzy_Idle.fbx": (DOWNLOADS_DIR, "Dizzy_Idle.fbx"),
    "Agony.fbx": (DOWNLOADS_DIR, "Agony.fbx"),
    "Dying.fbx": (DOWNLOADS_DIR, "Dying.fbx"),
    "Fall_Back_Death.fbx": (DOWNLOADS_DIR, "Falling_Back_Death.fbx"),
    "Laying_Dead_Idle.fbx": (DOWNLOADS_DIR, "Laying_Idle.fbx"),

    # 5. Nile River / Swimming
    "Swimming.fbx": (DOWNLOADS_DIR, "Swimming.fbx"),
    "Treading_Water.fbx": (DOWNLOADS_DIR, "Treading_Water.fbx"),
    "Diving.fbx": (DOWNLOADS_DIR, "Swimming_To_Edge.fbx"),

    # 6. Combat / Reactions
    "Hit_Body.fbx": (DOWNLOADS_DIR, "Hit_To_Body.fbx"),
    "Hit_Head.fbx": (DOWNLOADS_DIR, "Head_Hit.fbx"),
    "Knocked_Out.fbx": (DOWNLOADS_DIR, "Knocked_Out.fbx"),
    "Get_Up.fbx": (DOWNLOADS_DIR, "Standing_Up.fbx"),
    "Punch_Jab.fbx": (DOWNLOADS_DIR, "Lead_Jab.fbx"),
    "Punch_Hook.fbx": (DOWNLOADS_DIR, "Hook.fbx"),
    "Kick.fbx": (DOWNLOADS_DIR, "Kicking.fbx"),
    "Dodge.fbx": (DOWNLOADS_DIR, "Dodging_Right.fbx"),

    # 7. Vehicles / Donkey / Ship
    "Driving.fbx": (EXISTING_DIR, "Driving.fbx"),
    "Enter_Vehicle.fbx": (DOWNLOADS_DIR, "Entering_Car.fbx"),
    "Exit_Vehicle.fbx": (DOWNLOADS_DIR, "Exiting_Car.fbx"),
    "Ride_Donkey.fbx": (DOWNLOADS_DIR, "Male_Sitting_Pose.fbx"),
    "Steer_Ship.fbx": (DOWNLOADS_DIR, "Driving_1.fbx"),

    # 8. Cooking / Social / Daily Life
    "Cooking_Stir.fbx": (DOWNLOADS_DIR, "Bartending.fbx"),
    "Chopping.fbx": (DOWNLOADS_DIR, "Working_On_Device.fbx"),
    "Wave_Hello.fbx": (DOWNLOADS_DIR, "Waving.fbx"),
    "Dance_1.fbx": (DOWNLOADS_DIR, "Hip_Hop_Dancing.fbx"),
    "Dance_2.fbx": (DOWNLOADS_DIR, "Silly_Dancing.fbx"),

    # 9. Multi-Jumps & Airborne
    "Jump_Standard.fbx": (EXISTING_DIR, "Jump.fbx"),
    "Jump_Running.fbx": (DOWNLOADS_DIR, "Running_Jump.fbx"),
    "Jump_Flip.fbx": (DOWNLOADS_DIR, "Front_Flip.fbx"),
    "Jump_High.fbx": (DOWNLOADS_DIR, "Mutant_Jumping.fbx"),
    "Falling_Idle.fbx": (DOWNLOADS_DIR, "Falling_Idle.fbx"),
    "Landing.fbx": (DOWNLOADS_DIR, "Landing.fbx"),
}


def main() -> int:
    os.makedirs(TARGET_DIR, exist_ok=True)
    missing = []
    copied = 0
    total_bytes = 0
    for target_name, (src_dir, src_name) in sorted(CLIP_MAP.items()):
        src_path = os.path.join(src_dir, src_name)
        dst_path = os.path.join(TARGET_DIR, target_name)
        if not os.path.isfile(src_path):
            missing.append((target_name, src_path))
            continue
        size = os.path.getsize(src_path)
        if size < 10_000:
            missing.append((target_name, f"TOO SMALL ({size} bytes): {src_path}"))
            continue
        shutil.copy2(src_path, dst_path)
        copied += 1
        total_bytes += size

    print(f"Staged {copied}/{len(CLIP_MAP)} FBX animations into {TARGET_DIR} ({total_bytes / (1024*1024):.2f} MB)")
    if missing:
        print("MISSING OR INVALID:")
        for m in missing:
            print(" ", m)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
