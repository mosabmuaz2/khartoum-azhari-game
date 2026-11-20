# Al-Azhari (Khartoum) Open-World 3D Game — Overnight Progress Report

**Engine:** Godot `4.7.2.stable` (`gl_compatibility` renderer for Windows PC & Android)  
**Main Scene:** `res://scenes/main.tscn`  
**Status:** All 7 Autonomous Sprints Implemented & Verified Headlessly (`EXIT=0`)

---

## Sprint Summary

### Sprint 1 — Internet Research & Real Asset Harvesting
- Script: `tools/research_and_fetch_khartoum.py`
- **Wikimedia Reference Photos (`tools/references/images/`):** 20 reference image files downloaded for Khartoum streets, mosques, markets, and rickshaws (verified on disk). *(Note: OpenStreetMap Overpass API endpoints timed out from this host during Sprint 1, so block widths and residential street geometry were authored directly from standard Khartoum neighborhood proportions.)*
- **Poly Haven 1K PBR Textures (`assets/textures/`):** 9 material sets (`asphalt`, `brick`, `ceramic_tiles`, `corrugated`, `fabric`, `painted_wood`, `plaster`, `sand_dirt`, `wood`).
- **3D `.gltf` / `.glb` Props (`assets/models/props/`):** 11 Poly Haven props (`barrel`, `bench`, `bucket`, `cart/CoffeeCart_01.gltf`, `crate`, `lantern`, `plant`, `pot`, `stool`, `table`, `tire`) plus Khronos `BarramundiFish.glb` saved as `fish.glb`.

### Sprint 2 — Hollow Enterable Khartoum Buildings
- `scenes/buildings/mosque_azhari.tscn` — Open arched entrance porch, shoe racks, covered ablution courtyard (`ميضأة`) with taps, interior prayer carpets, 4 structural pillars, Mihrab, Minbar, framed wall plaques, rotating ceiling fans (`scripts/ceiling_fan.gd`), and `AdhanPlayer` (`scripts/mosque_adhan.gd`).
- `scenes/buildings/sudanese_house.tscn` — Walled 24×22m *Hosh* compound with open corrugated double gate, shaded veranda, exterior staircase with `RoofLanding` leading to rooftop tank and satellite dish, and furnished interior Diwan (`ديوان`) with traditional `عناقريب` rope beds, rug, table, `GuestChairSeat_0`/`GuestChairSeat_1`, and ceiling fan.
- `scenes/buildings/apartment_building.tscn` — 3-story residential/commercial block (`ApartmentWest`, `ApartmentEast`) with ground shops, upper exterior staircase landings (`Landing_1`), east doorway openings (`WallRight_1_Top`), front balcony railings/doorways, split AC units, and rooftop water tanks.
- `scenes/buildings/commercial_strip.tscn` — 6 enterable neighborhood shops (`دكان الأزهري`, `مخبز الخرطوم`, `مطعم فول وطعمية`, `صيدلية الأزهري`, `صالون حلاقة`, `بنشر ولحام لساتك`).

### Sprint 3 — 3x–4x `.glb` Crowd Multiplier
- `scripts/character_model_loader.gd` — Recursively scans `assets/models/characters/` and loads all 8 user `.glb` models (`Man.glb`, `teewoman.glb`, `Oldman.glb`, `dreiver.glb`, `ritchman.glb`, `mama.glb`, `kid.glb`, `homeless.glb`), normalizing pivot height and forward `-Z` facing.
- `scripts/npc_interactive.gd` & `scenes/npc.tscn` — Frees the primitive `Hips` placeholder whenever a normalized `.glb` loads; animates walking stride/sway/seated pose; provides Arabic `Label3D` dialogue (`T`), auto-greeting on 4m approach (20s cooldown), `F` companion follow mode, and vehicle passenger boarding.
- `scripts/crowd_spawner.gd` — Spawns 32 ambient crowd clones (`8 GLBs × 4` across 6 neighborhood blocks with seeded RNG `472026`) alongside 9 named interactive NPCs (`NPCs`, 41 normalized `.glb` characters total).

### Sprint 4 — 5-Vehicle Sudanese Fleet
- `scripts/vehicle_controller.gd` powering 5 distinct vehicles under `Vehicles`:
  - `scenes/raksha.tscn` (`Raksha1` — Khartoum plate `خ - 4182`)
  - `scenes/boks.tscn` (`Boks1` — Khartoum plate `خ - 7305`)
  - `scenes/amjad.tscn` (`Amjad1` — Khartoum plate `خ - 2941`)
  - `scenes/sedan.tscn` (`Sedan1` — Khartoum plate `خ - 6093`)
  - `scenes/daffar.tscn` (`Daffar1` — Khartoum plate `خ - 8814`)
- Features `SpotLight3D` headlights, emissive brake taillights, GL-Compatibility exhaust smoke & tire dirt dust (`VFXManager`), speed-scaled engine pitch, vehicle horns (`H`), in-car radio (`R`), door/ignition/skid SFX, and companion NPC passenger seating.

### Sprint 5 — Full Audio & VFX Ecosystem
- `scripts/audio_manager.gd` — Preserves all user `.mp3` files (`15` clips in `assets/audio/npc/`, `6` tracks in `assets/audio/radio/`, `adhan.mp3` in `assets/audio/mosque/`) and synthesizes `.wav` loops/SFX on disk (`vehicles/`, `ambience/`, `sfx/`).
- `scripts/mosque_adhan.gd` — `AdhanPlayer` (`AudioStreamPlayer3D`, `max_distance = 360.0`, `INITIAL_DELAY_SEC = 15.0`, `REPEAT_INTERVAL_SEC = 1200.0`).
- `scripts/vfx_manager.gd` — `GPUParticles3D` effects (exhaust smoke, tire dust, tea steam, water splash, feather scatter burst, desert dust motes) plus interaction rings and speaking wave indicators.

### Sprint 6 — Street Micro-Details, Living Animals & Scatterable Bird Flocks
- `scripts/street_details_spawner.gd` — Procedural weathered Arabic posters, metal trash barrels & debris, stacked cement blocks (`طوب`), Arabic street signs, and sagging overhead power drop lines.
- `scripts/animal_ai.gd` & `scripts/world_ambiance_controller.gd` — Spawns 2 animated dogs, 2 cats, 2 goats, and 4 scatterable `bird_flocks` (street, wire-perched, and roof-perched birds that scatter on proximity or `H` horn), plus 5 swimming `fish.glb` models with ripples/splash audio, flickering tea embers & steam, 3 spatial market bustle emitters (`max_distance = 90.0`), and all Poly Haven props including `CoffeeCart_01.gltf`.

### Sprint 7 — 2D Minimap, Time-of-Day Cycle & Headless Verification
- `scripts/minimap.gd` — Live 2D top-down HUD minimap (`NetworkHUD/MinimapPanel`) tracking the local player, vehicles, and NPCs (shown while hosted/joined, hidden on disconnect).
- `scripts/time_of_day_controller.gd` & `scripts/network_manager.gd` — `TimeOfDayController` (`TimeOfDay`, `L` key or `TimeButton` on HUD) cycles `Sunset` -> `Morning` -> `Night` with dynamic corner streetlamp `OmniLight3D` illumination; input action `toggle_time_of_day` registered in `project.godot`.

---

## Final Godot 4.7.2 Headless Verification Results

1. **Editor Asset Import & Class Registration (`--headless --editor --quit`):**
   - `IMPORT_EXIT=0` (imported `CoffeeCart_01.gltf` + 6 PBR maps cleanly; registered global classes `AnimalAI`, `NeighborhoodMinimap`, `NetworkManager`, `TimeOfDayController`, `WorldAmbianceController`).
2. **Main Scene Runtime Boot Check (`--headless --quit-after 30`):**
   - `MAIN_EXIT=0` with 0 errors and 0 warnings in log output.
3. **End-to-End Smoke Suite (`--headless --script .../smoke_test.gd`):**
   - `SMOKE_EXIT=0`, output: `OVERNIGHT_FULL_VERIFICATION_PASSED` (0 warnings, 0 errors, 0 ObjectDB leaks).
   - Verified: `AudioManager` streams (`15` NPC, `6` radio, `adhan.mp3`, ambience), `MosqueAzhari/AdhanPlayer` (`360m`, `15s`/`1200s`), all 7 buildings plus `HouseSW/GuestChairSeat_0`, `HouseSW/RoofLanding`, `ApartmentWest/Landing_1`, `ApartmentWest/WallRight_1_Top`, `CrowdSpawner` (`32` `.glb` clones) + `9` named NPCs, `WorldLife` (`5` swimming `fish.glb`, `2` dogs, `2` cats, `2` goats, `4` `bird_flocks`), `StreetDetails`, `TimeOfDay` (`Sunset` -> `Morning` -> `Night` -> `Sunset`), `MinimapPanel` visibility toggle, `Host Game`, Mutaz follow/reset, and entering/driving/radio/horn/exhaust VFX/exiting all 5 vehicles (`Raksha1`, `Boks1`, `Amjad1`, `Sedan1`, `Daffar1`).
