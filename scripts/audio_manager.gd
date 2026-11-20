extends Node

## Comprehensive Audio Loader & Multi-Layered Procedural WAV Synthesizer for Al-Azhari.
## Scans all 6 audio folders for user .mp3/.ogg/.wav files first and synthesizes clean
## fallbacks in memory (and to disk in editor) so zero interactions are ever silent.

const SAMPLE_RATE: int = 22050
const AUDIO_EXTENSIONS: Array[String] = ["mp3", "ogg", "wav"]

const DIR_NPC: String = "res://assets/audio/npc"
const DIR_RADIO: String = "res://assets/audio/radio"
const DIR_MOSQUE: String = "res://assets/audio/mosque"
const DIR_VEHICLES: String = "res://assets/audio/vehicles"
const DIR_AMBIENCE: String = "res://assets/audio/ambience"
const DIR_SFX: String = "res://assets/audio/sfx"

var npc_clips: Array[AudioStream] = []
var radio_tracks: Array[Dictionary] = []
var mosque_streams: Array[AudioStream] = []
var ambience_streams: Array[AudioStream] = []

var street_ambience_stream: AudioStream = null
var market_ambience_stream: AudioStream = null

var raksha_engine_stream: AudioStream = null
var boks_engine_stream: AudioStream = null
var raksha_horn_stream: AudioStream = null
var boks_horn_stream: AudioStream = null
var tire_skid_stream: AudioStream = null
var vehicle_door_stream: AudioStream = null
var vehicle_ignition_stream: AudioStream = null
var radio_click_stream: AudioStream = null

var footstep_asphalt_streams: Array[AudioStream] = []
var footstep_sand_streams: Array[AudioStream] = []
var jump_whoosh_stream: AudioStream = null
var land_thud_stream: AudioStream = null
var interact_chime_stream: AudioStream = null

var tea_stall_stream: AudioStream = null
var water_basin_stream: AudioStream = null
var dog_bark_stream: AudioStream = null
var cat_meow_stream: AudioStream = null
var goat_bleat_stream: AudioStream = null
var bird_scatter_stream: AudioStream = null
var mouse_squeak_stream: AudioStream = null

var _global_ambience_player: AudioStreamPlayer = null
var _ui_sfx_player: AudioStreamPlayer = null


func _ready() -> void:
	if OS.has_feature("web"):
		call_deferred("_load_web_audio_async")
		return
	_load_all_audio()
	_start_global_ambience()
	_setup_ui_player()


func _load_web_audio_async() -> void:
	await get_tree().process_frame
	# Only synthesize lightweight short SFX on Web so Safari never stalls or exceeds 300 MB RAM
	if footstep_asphalt_streams.is_empty():
		footstep_asphalt_streams.append(_create_footstep_wav(155.0, 0.11, false))
	if footstep_sand_streams.is_empty():
		footstep_sand_streams.append(_create_footstep_wav(88.0, 0.15, true))
	await get_tree().process_frame
	if jump_whoosh_stream == null:
		jump_whoosh_stream = _create_jump_whoosh_wav()
	if land_thud_stream == null:
		land_thud_stream = _create_land_thud_wav()
	if interact_chime_stream == null:
		interact_chime_stream = _create_interact_chime_wav()
	if radio_click_stream == null:
		radio_click_stream = _create_radio_click_wav()
	if raksha_horn_stream == null:
		raksha_horn_stream = _create_horn_wav(525.0, 660.0, 0.34, true)
	if boks_horn_stream == null:
		boks_horn_stream = _create_horn_wav(305.0, 385.0, 0.45, false)
	_setup_ui_player()


func _load_all_audio() -> void:
	# 1. User-added categories: npc, radio, mosque (never overwritten)
	for entry in _scan_audio_dir(DIR_NPC):
		var s: AudioStream = entry["stream"]
		_set_stream_loop(s, false)
		npc_clips.append(s)

	for entry in _scan_audio_dir(DIR_RADIO):
		var s: AudioStream = entry["stream"]
		_set_stream_loop(s, true)
		radio_tracks.append({"name": entry["name"], "stream": s})

	for entry in _scan_audio_dir(DIR_MOSQUE):
		var s: AudioStream = entry["stream"]
		_set_stream_loop(s, false)
		mosque_streams.append(s)

	# 2. Vehicles
	for entry in _scan_audio_dir(DIR_VEHICLES):
		var lname := String(entry["name"]).to_lower()
		var s: AudioStream = entry["stream"]
		if lname.contains("raksha") and lname.contains("horn"):
			_set_stream_loop(s, false)
			raksha_horn_stream = s
		elif lname.contains("boks") and lname.contains("horn"):
			_set_stream_loop(s, false)
			boks_horn_stream = s
		elif lname.contains("raksha"):
			_set_stream_loop(s, true)
			raksha_engine_stream = s
		elif lname.contains("boks"):
			_set_stream_loop(s, true)
			boks_engine_stream = s
		elif lname.contains("skid") or lname.contains("screech"):
			_set_stream_loop(s, true)
			tire_skid_stream = s
		elif lname.contains("door"):
			_set_stream_loop(s, false)
			vehicle_door_stream = s
		elif lname.contains("ignition") or lname.contains("start"):
			_set_stream_loop(s, false)
			vehicle_ignition_stream = s

	if raksha_engine_stream == null:
		raksha_engine_stream = _create_raksha_engine_wav()
		_save_wav(raksha_engine_stream as AudioStreamWAV, DIR_VEHICLES + "/raksha_engine.wav")
	if boks_engine_stream == null:
		boks_engine_stream = _create_boks_engine_wav()
		_save_wav(boks_engine_stream as AudioStreamWAV, DIR_VEHICLES + "/boks_engine.wav")
	if raksha_horn_stream == null:
		raksha_horn_stream = _create_horn_wav(525.0, 660.0, 0.34, true)
		_save_wav(raksha_horn_stream as AudioStreamWAV, DIR_VEHICLES + "/raksha_horn.wav")
	if boks_horn_stream == null:
		boks_horn_stream = _create_horn_wav(305.0, 385.0, 0.45, false)
		_save_wav(boks_horn_stream as AudioStreamWAV, DIR_VEHICLES + "/boks_horn.wav")
	if tire_skid_stream == null:
		tire_skid_stream = _create_tire_skid_wav()
		_save_wav(tire_skid_stream as AudioStreamWAV, DIR_VEHICLES + "/tire_skid.wav")
	if vehicle_door_stream == null:
		vehicle_door_stream = _create_vehicle_door_wav()
		_save_wav(vehicle_door_stream as AudioStreamWAV, DIR_VEHICLES + "/vehicle_door.wav")
	if vehicle_ignition_stream == null:
		vehicle_ignition_stream = _create_vehicle_ignition_wav()
		_save_wav(vehicle_ignition_stream as AudioStreamWAV, DIR_VEHICLES + "/vehicle_ignition.wav")

	# 3. Ambience
	for entry in _scan_audio_dir(DIR_AMBIENCE):
		var lname := String(entry["name"]).to_lower()
		var s: AudioStream = entry["stream"]
		_set_stream_loop(s, true)
		ambience_streams.append(s)
		if lname.contains("market") or lname.contains("souq"):
			market_ambience_stream = s
		elif lname.contains("street") or lname.contains("wind"):
			if street_ambience_stream == null:
				street_ambience_stream = s

	if street_ambience_stream == null:
		street_ambience_stream = _create_street_ambience_wav()
		_save_wav(street_ambience_stream as AudioStreamWAV, DIR_AMBIENCE + "/street_ambience.wav")
	if market_ambience_stream == null:
		market_ambience_stream = _create_market_ambience_wav()
		_save_wav(market_ambience_stream as AudioStreamWAV, DIR_AMBIENCE + "/market_ambience.wav")

	# 4. SFX (footsteps, jump/land, radio click, chime, tea, water, animals)
	for entry in _scan_audio_dir(DIR_SFX):
		var lname := String(entry["name"]).to_lower()
		var s: AudioStream = entry["stream"]
		if lname.contains("asphalt") or (lname.contains("footstep") and not lname.contains("sand")):
			_set_stream_loop(s, false)
			footstep_asphalt_streams.append(s)
		elif lname.contains("sand"):
			_set_stream_loop(s, false)
			footstep_sand_streams.append(s)
		elif lname.contains("jump"):
			_set_stream_loop(s, false)
			jump_whoosh_stream = s
		elif lname.contains("land"):
			_set_stream_loop(s, false)
			land_thud_stream = s
		elif lname.contains("chime") or lname.contains("click"):
			_set_stream_loop(s, false)
			if lname.contains("radio"):
				radio_click_stream = s
			else:
				interact_chime_stream = s
		elif lname.contains("tea"):
			_set_stream_loop(s, true)
			tea_stall_stream = s
		elif lname.contains("water"):
			_set_stream_loop(s, true)
			water_basin_stream = s
		elif lname.contains("dog") or lname.contains("bark"):
			_set_stream_loop(s, false)
			dog_bark_stream = s
		elif lname.contains("cat") or lname.contains("meow"):
			_set_stream_loop(s, false)
			cat_meow_stream = s
		elif lname.contains("goat") or lname.contains("bleat"):
			_set_stream_loop(s, false)
			goat_bleat_stream = s
		elif lname.contains("bird") or lname.contains("scatter"):
			_set_stream_loop(s, false)
			bird_scatter_stream = s
		elif lname.contains("mouse") or lname.contains("rat") or lname.contains("squeak"):
			_set_stream_loop(s, false)
			mouse_squeak_stream = s

	if footstep_asphalt_streams.is_empty():
		var a1 := _create_footstep_wav(155.0, 0.11, false)
		var a2 := _create_footstep_wav(142.0, 0.11, false)
		_save_wav(a1, DIR_SFX + "/footstep_asphalt_1.wav")
		_save_wav(a2, DIR_SFX + "/footstep_asphalt_2.wav")
		footstep_asphalt_streams.append_array([a1, a2])

	if footstep_sand_streams.is_empty():
		var s1 := _create_footstep_wav(88.0, 0.15, true)
		var s2 := _create_footstep_wav(80.0, 0.15, true)
		_save_wav(s1, DIR_SFX + "/footstep_sand_1.wav")
		_save_wav(s2, DIR_SFX + "/footstep_sand_2.wav")
		footstep_sand_streams.append_array([s1, s2])

	if jump_whoosh_stream == null:
		jump_whoosh_stream = _create_jump_whoosh_wav()
		_save_wav(jump_whoosh_stream as AudioStreamWAV, DIR_SFX + "/jump_whoosh.wav")
	if land_thud_stream == null:
		land_thud_stream = _create_land_thud_wav()
		_save_wav(land_thud_stream as AudioStreamWAV, DIR_SFX + "/land_thud.wav")
	if interact_chime_stream == null:
		interact_chime_stream = _create_interact_chime_wav()
		_save_wav(interact_chime_stream as AudioStreamWAV, DIR_SFX + "/interact_chime.wav")
	if radio_click_stream == null:
		radio_click_stream = _create_radio_click_wav()
		_save_wav(radio_click_stream as AudioStreamWAV, DIR_SFX + "/radio_click.wav")
	if tea_stall_stream == null:
		tea_stall_stream = _create_tea_stall_wav()
		_save_wav(tea_stall_stream as AudioStreamWAV, DIR_SFX + "/tea_stall_loop.wav")
	if water_basin_stream == null:
		water_basin_stream = _create_water_basin_wav()
		_save_wav(water_basin_stream as AudioStreamWAV, DIR_SFX + "/water_basin_loop.wav")
	if dog_bark_stream == null:
		dog_bark_stream = _create_dog_bark_wav()
		_save_wav(dog_bark_stream as AudioStreamWAV, DIR_SFX + "/dog_bark.wav")
	if cat_meow_stream == null:
		cat_meow_stream = _create_cat_meow_wav()
		_save_wav(cat_meow_stream as AudioStreamWAV, DIR_SFX + "/cat_meow.wav")
	if goat_bleat_stream == null:
		goat_bleat_stream = _create_goat_bleat_wav()
		_save_wav(goat_bleat_stream as AudioStreamWAV, DIR_SFX + "/goat_bleat.wav")
	if bird_scatter_stream == null:
		bird_scatter_stream = _create_bird_scatter_wav()
		_save_wav(bird_scatter_stream as AudioStreamWAV, DIR_SFX + "/bird_scatter.wav")
	if mouse_squeak_stream == null:
		mouse_squeak_stream = _create_mouse_squeak_wav()
		_save_wav(mouse_squeak_stream as AudioStreamWAV, DIR_SFX + "/mouse_squeak.wav")


func get_random_npc_clip() -> AudioStream:
	if npc_clips.is_empty():
		return null
	return npc_clips[randi() % npc_clips.size()]


func get_radio_count() -> int:
	return radio_tracks.size()


func get_radio_track(index: int) -> Dictionary:
	if index < 0 or index >= radio_tracks.size():
		return {}
	return radio_tracks[index]


func get_mosque_streams() -> Array[AudioStream]:
	return mosque_streams


func get_vehicle_engine_stream(is_three_wheeler: bool) -> AudioStream:
	return raksha_engine_stream if is_three_wheeler else boks_engine_stream


func get_vehicle_horn_stream(is_three_wheeler: bool) -> AudioStream:
	return raksha_horn_stream if is_three_wheeler else boks_horn_stream


func get_random_footstep_stream(on_asphalt: bool = false) -> AudioStream:
	var pool := footstep_asphalt_streams if on_asphalt else footstep_sand_streams
	if pool.is_empty():
		return null
	return pool[randi() % pool.size()]


func play_ui_chime() -> void:
	if _ui_sfx_player and interact_chime_stream:
		_ui_sfx_player.stream = interact_chime_stream
		_ui_sfx_player.volume_db = -8.0
		_ui_sfx_player.play()


func _start_global_ambience() -> void:
	if street_ambience_stream == null:
		return
	_global_ambience_player = AudioStreamPlayer.new()
	_global_ambience_player.name = "GlobalStreetAmbience"
	_global_ambience_player.stream = street_ambience_stream
	_global_ambience_player.volume_db = -16.0
	add_child(_global_ambience_player)
	_global_ambience_player.play()


func _setup_ui_player() -> void:
	_ui_sfx_player = AudioStreamPlayer.new()
	_ui_sfx_player.name = "UIChimePlayer"
	add_child(_ui_sfx_player)


func _scan_audio_dir(dir_path: String) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return results

	var seen: Dictionary = {}
	var filenames: Array[String] = []
	for raw_name in dir.get_files():
		var clean_name := raw_name
		if clean_name.ends_with(".import"):
			clean_name = clean_name.substr(0, clean_name.length() - 7)
		var ext := clean_name.get_extension().to_lower()
		if ext in AUDIO_EXTENSIONS and not seen.has(clean_name):
			seen[clean_name] = true
			filenames.append(clean_name)

	filenames.sort()
	for file_name in filenames:
		var full_path := "%s/%s" % [dir_path, file_name]
		var stream := _load_audio_file(full_path)
		if stream != null:
			results.append({"name": file_name.get_basename(), "path": full_path, "stream": stream})
	return results


func _load_audio_file(full_path: String) -> AudioStream:
	if ResourceLoader.exists(full_path):
		var res := ResourceLoader.load(full_path) as AudioStream
		if res != null:
			return res
	var ext := full_path.get_extension().to_lower()
	if ext == "wav":
		return AudioStreamWAV.load_from_file(full_path)
	if ext == "mp3":
		return AudioStreamMP3.load_from_file(full_path)
	if ext == "ogg":
		return AudioStreamOggVorbis.load_from_file(full_path)
	return null


func _set_stream_loop(stream: AudioStream, should_loop: bool) -> void:
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = should_loop
	elif stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = should_loop
	elif stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD if should_loop else AudioStreamWAV.LOOP_DISABLED


func _save_wav(wav: AudioStreamWAV, res_path: String) -> void:
	if wav == null or not OS.has_feature("editor"):
		return
	if FileAccess.file_exists(res_path):
		return
	var abs_path := ProjectSettings.globalize_path(res_path)
	var parent_dir := abs_path.get_base_dir()
	DirAccess.make_dir_recursive_absolute(parent_dir)
	wav.save_to_wav(abs_path)


func _build_wav(samples: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var count := samples.size()
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	for i in range(count):
		var clamped := clampf(samples[i], -1.0, 1.0)
		bytes.encode_s16(i * 2, clampi(int(clamped * 32767.0), -32768, 32767))

	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = false
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD if loop else AudioStreamWAV.LOOP_DISABLED
	wav.loop_begin = 0
	wav.loop_end = count
	wav.data = bytes
	return wav


func _crossfade_loop(samples: PackedFloat32Array, fade_sec: float = 0.25) -> void:
	var count := samples.size()
	var fade_len := mini(int(fade_sec * float(SAMPLE_RATE)), count / 4)
	for i in range(fade_len):
		var alpha := float(i) / float(fade_len)
		samples[i] = lerpf(samples[count - fade_len + i], samples[i], alpha)


func _create_raksha_engine_wav() -> AudioStreamWAV:
	var count := SAMPLE_RATE
	var samples := PackedFloat32Array()
	samples.resize(count)
	var lp := 0.0
	for i in range(count):
		var t := float(i) / float(SAMPLE_RATE)
		var pulse_phase := fmod(t * 32.0, 1.0)
		var pop := exp(-pulse_phase * 7.5) * sin(TAU * 96.0 * t)
		var harmonic := 0.45 * sin(TAU * 64.0 * t) + 0.25 * sin(TAU * 128.0 * t)
		var grit := (randf() * 2.0 - 1.0) * 0.14 * exp(-pulse_phase * 5.0)
		lp = lerpf(lp, (pop * 0.55 + harmonic * 0.35 + grit) * 0.42, 0.28)
		samples[i] = lp
	return _build_wav(samples, true)


func _create_boks_engine_wav() -> AudioStreamWAV:
	var count := SAMPLE_RATE
	var samples := PackedFloat32Array()
	samples.resize(count)
	var lp := 0.0
	for i in range(count):
		var t := float(i) / float(SAMPLE_RATE)
		var clatter := fmod(t * 23.0, 1.0)
		var thrum := 0.58 * sin(TAU * 46.0 * t) + 0.32 * sin(TAU * 69.0 * t)
		var knock := 0.28 * exp(-clatter * 10.0) * sin(TAU * 138.0 * t)
		var intake := (randf() * 2.0 - 1.0) * 0.10
		lp = lerpf(lp, (thrum + knock + intake) * 0.40, 0.20)
		samples[i] = lp
	return _build_wav(samples, true)


func _create_horn_wav(freq_a: float, freq_b: float, duration: float, double_tap: bool) -> AudioStreamWAV:
	var count := int(float(SAMPLE_RATE) * duration)
	var samples := PackedFloat32Array()
	samples.resize(count)
	for i in range(count):
		var u := float(i) / float(count)
		var t := float(i) / float(SAMPLE_RATE)
		var env := minf(u / 0.06, 1.0) * minf((1.0 - u) / 0.12, 1.0)
		if double_tap and u > 0.36 and u < 0.48:
			env *= 0.12
		var tone := 0.55 * sin(TAU * freq_a * t) + 0.45 * sin(TAU * freq_b * t)
		var warmth := 0.15 * sin(TAU * (freq_a * 2.0) * t)
		samples[i] = (tone + warmth) * 0.42 * env
	return _build_wav(samples, false)


func _create_tire_skid_wav() -> AudioStreamWAV:
	var count := SAMPLE_RATE
	var samples := PackedFloat32Array()
	samples.resize(count)
	var bp := 0.0
	var lp := 0.0
	for i in range(count):
		var t := float(i) / float(SAMPLE_RATE)
		var white := randf() * 2.0 - 1.0
		lp = lerpf(lp, white, 0.45)
		bp = lerpf(bp, white - lp, 0.35)
		var squeal := sin(TAU * 720.0 * t) * 0.14 + sin(TAU * 1080.0 * t) * 0.08
		samples[i] = (bp * 0.55 + squeal) * 0.36
	_crossfade_loop(samples, 0.12)
	return _build_wav(samples, true)


func _create_vehicle_door_wav() -> AudioStreamWAV:
	var count := int(float(SAMPLE_RATE) * 0.24)
	var samples := PackedFloat32Array()
	samples.resize(count)
	for i in range(count):
		var u := float(i) / float(count)
		var t := float(i) / float(SAMPLE_RATE)
		var thud := sin(TAU * lerpf(135.0, 52.0, minf(u * 3.0, 1.0)) * t) * exp(-u * 14.0) * 0.55
		var latch := sin(TAU * 820.0 * t) * exp(-absf(u - 0.35) * 35.0) * 0.28
		samples[i] = thud + latch
	return _build_wav(samples, false)


func _create_vehicle_ignition_wav() -> AudioStreamWAV:
	var count := int(float(SAMPLE_RATE) * 0.52)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var lp := 0.0
	for i in range(count):
		var u := float(i) / float(count)
		var t := float(i) / float(SAMPLE_RATE)
		var crank := sin(TAU * 110.0 * t) * (0.5 + 0.5 * sin(TAU * 9.0 * t)) * (1.0 - minf(u / 0.65, 1.0)) * 0.38
		var catch_env := clampf((u - 0.42) / 0.25, 0.0, 1.0) * (1.0 - clampf((u - 0.78) / 0.22, 0.0, 1.0))
		var catch_rumble := sin(TAU * 58.0 * t) * catch_env * 0.45
		lp = lerpf(lp, crank + catch_rumble, 0.35)
		samples[i] = lp
	return _build_wav(samples, false)


func _create_footstep_wav(base_freq: float, duration: float, sandy: bool) -> AudioStreamWAV:
	var count := int(float(SAMPLE_RATE) * duration)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var lp := 0.0
	for i in range(count):
		var u := float(i) / float(count)
		var t := float(i) / float(SAMPLE_RATE)
		var thud_env := exp(-u * (9.0 if sandy else 15.0))
		var grit_env := exp(-u * (6.0 if sandy else 13.0)) * minf(u / 0.08, 1.0)
		var thud := sin(TAU * lerpf(base_freq, 46.0, u) * t) * thud_env * (0.38 if sandy else 0.62)
		var grit := (randf() * 2.0 - 1.0) * grit_env * (0.45 if sandy else 0.18)
		lp = lerpf(lp, thud + grit, 0.40 if sandy else 0.55)
		samples[i] = lp * 0.72
	return _build_wav(samples, false)


func _create_jump_whoosh_wav() -> AudioStreamWAV:
	var count := int(float(SAMPLE_RATE) * 0.18)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var lp := 0.0
	for i in range(count):
		var u := float(i) / float(count)
		var env := sin(PI * u)
		lp = lerpf(lp, (randf() * 2.0 - 1.0) * 0.35, 0.18 + u * 0.25)
		samples[i] = lp * env
	return _build_wav(samples, false)


func _create_land_thud_wav() -> AudioStreamWAV:
	var count := int(float(SAMPLE_RATE) * 0.16)
	var samples := PackedFloat32Array()
	samples.resize(count)
	for i in range(count):
		var u := float(i) / float(count)
		var t := float(i) / float(SAMPLE_RATE)
		var thud := sin(TAU * lerpf(92.0, 36.0, u) * t) * exp(-u * 12.0) * 0.58
		var grit := (randf() * 2.0 - 1.0) * exp(-u * 10.0) * 0.22
		samples[i] = thud + grit
	return _build_wav(samples, false)


func _create_interact_chime_wav() -> AudioStreamWAV:
	var count := int(float(SAMPLE_RATE) * 0.18)
	var samples := PackedFloat32Array()
	samples.resize(count)
	for i in range(count):
		var u := float(i) / float(count)
		var t := float(i) / float(SAMPLE_RATE)
		var freq := 660.0 if u < 0.45 else 880.0
		var env := minf(u / 0.05, 1.0) * exp(-u * 6.5)
		samples[i] = sin(TAU * freq * t) * env * 0.32
	return _build_wav(samples, false)


func _create_radio_click_wav() -> AudioStreamWAV:
	var count := int(float(SAMPLE_RATE) * 0.10)
	var samples := PackedFloat32Array()
	samples.resize(count)
	for i in range(count):
		var u := float(i) / float(count)
		var click := (randf() * 2.0 - 1.0) * exp(-u * 16.0) * 0.35
		var pop := sin(TAU * 420.0 * (float(i) / float(SAMPLE_RATE))) * exp(-u * 25.0) * 0.30
		samples[i] = click + pop
	return _build_wav(samples, false)


func _create_street_ambience_wav() -> AudioStreamWAV:
	var duration := 5.0
	var count := int(float(SAMPLE_RATE) * duration)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var lp1 := 0.0
	var lp2 := 0.0
	for i in range(count):
		var t := float(i) / float(SAMPLE_RATE)
		var white := randf() * 2.0 - 1.0
		lp1 = lerpf(lp1, white, 0.035)
		lp2 = lerpf(lp2, lp1, 0.03)
		var wind_gust := (0.65 + 0.35 * sin(TAU * 0.2 * t)) * lp2 * 0.52
		var traffic_hum := 0.045 * sin(TAU * 52.0 * t) * (0.7 + 0.3 * sin(TAU * 0.4 * t))
		var chirp_gate := maxf(0.0, sin(TAU * 0.6 * t) - 0.92) * 12.5
		var bird := sin(TAU * (2400.0 + 350.0 * sin(TAU * 14.0 * t)) * t) * chirp_gate * 0.06
		samples[i] = wind_gust + traffic_hum + bird
	_crossfade_loop(samples, 0.35)
	return _build_wav(samples, true)


func _create_market_ambience_wav() -> AudioStreamWAV:
	var duration := 4.5
	var count := int(float(SAMPLE_RATE) * duration)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var lp_crowd := 0.0
	for i in range(count):
		var t := float(i) / float(SAMPLE_RATE)
		var murmur := (randf() * 2.0 - 1.0) * (0.65 + 0.35 * sin(TAU * 1.1 * t))
		lp_crowd = lerpf(lp_crowd, murmur, 0.08)
		var voice_formant := sin(TAU * (165.0 + 35.0 * sin(TAU * 2.2 * t)) * t) * 0.045
		var clink_env := exp(-fmod(t, 1.5) * 18.0) * (1.0 if fmod(t, 1.5) < 0.15 else 0.0)
		var clink := sin(TAU * 1950.0 * t) * clink_env * 0.09
		samples[i] = lp_crowd * 0.34 + voice_formant + clink
	_crossfade_loop(samples, 0.3)
	return _build_wav(samples, true)


func _create_tea_stall_wav() -> AudioStreamWAV:
	var duration := 3.5
	var count := int(float(SAMPLE_RATE) * duration)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var lp := 0.0
	for i in range(count):
		var t := float(i) / float(SAMPLE_RATE)
		var simmer := (randf() * 2.0 - 1.0) * (0.55 + 0.45 * sin(TAU * 3.0 * t))
		lp = lerpf(lp, simmer, 0.22)
		var glass_gate := exp(-fmod(t + 0.4, 1.75) * 24.0)
		var glass_clink := (sin(TAU * 2650.0 * t) + 0.5 * sin(TAU * 3980.0 * t)) * glass_gate * 0.12
		samples[i] = lp * 0.22 + glass_clink
	_crossfade_loop(samples, 0.25)
	return _build_wav(samples, true)


func _create_water_basin_wav() -> AudioStreamWAV:
	var duration := 3.5
	var count := int(float(SAMPLE_RATE) * duration)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var lp := 0.0
	for i in range(count):
		var t := float(i) / float(SAMPLE_RATE)
		var flow := (randf() * 2.0 - 1.0) * (0.7 + 0.3 * sin(TAU * 1.4 * t))
		lp = lerpf(lp, flow, 0.18)
		var drop_phase := fmod(t, 0.58)
		var drop_freq := 720.0 + drop_phase * 950.0
		var drop := sin(TAU * drop_freq * t) * exp(-drop_phase * 28.0) * 0.10
		samples[i] = lp * 0.26 + drop
	_crossfade_loop(samples, 0.25)
	return _build_wav(samples, true)


func _create_dog_bark_wav() -> AudioStreamWAV:
	var count := int(float(SAMPLE_RATE) * 0.45)
	var samples := PackedFloat32Array()
	samples.resize(count)
	for i in range(count):
		var u := float(i) / float(count)
		var t := float(i) / float(SAMPLE_RATE)
		var env1 := exp(-absf(u - 0.18) * 18.0)
		var env2 := exp(-absf(u - 0.62) * 18.0)
		var env := env1 + env2 * 0.85
		var f := lerpf(320.0, 145.0, fmod(u * 2.2, 1.0))
		var bark := (sin(TAU * f * t) + 0.45 * sin(TAU * f * 2.0 * t) + (randf() * 2.0 - 1.0) * 0.22) * env * 0.45
		samples[i] = bark
	return _build_wav(samples, false)


func _create_cat_meow_wav() -> AudioStreamWAV:
	var count := int(float(SAMPLE_RATE) * 0.52)
	var samples := PackedFloat32Array()
	samples.resize(count)
	for i in range(count):
		var u := float(i) / float(count)
		var t := float(i) / float(SAMPLE_RATE)
		var env := sin(PI * u)
		var freq := 480.0 + 260.0 * sin(PI * u)
		samples[i] = (sin(TAU * freq * t) + 0.35 * sin(TAU * freq * 2.0 * t)) * env * 0.35
	return _build_wav(samples, false)


func _create_goat_bleat_wav() -> AudioStreamWAV:
	var count := int(float(SAMPLE_RATE) * 0.58)
	var samples := PackedFloat32Array()
	samples.resize(count)
	for i in range(count):
		var u := float(i) / float(count)
		var t := float(i) / float(SAMPLE_RATE)
		var env := minf(u / 0.1, 1.0) * minf((1.0 - u) / 0.15, 1.0)
		var vibrato := 1.0 + 0.45 * sin(TAU * 22.0 * t)
		var f := 275.0 + 25.0 * sin(TAU * 4.0 * t)
		samples[i] = (sin(TAU * f * t) + 0.4 * sin(TAU * f * 2.0 * t)) * vibrato * env * 0.32
	return _build_wav(samples, false)


func _create_bird_scatter_wav() -> AudioStreamWAV:
	var count := int(float(SAMPLE_RATE) * 0.65)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var lp := 0.0
	for i in range(count):
		var u := float(i) / float(count)
		var t := float(i) / float(SAMPLE_RATE)
		var flutter := (randf() * 2.0 - 1.0) * (0.5 + 0.5 * sin(TAU * 18.0 * t)) * (1.0 - u) * 0.35
		lp = lerpf(lp, flutter, 0.35)
		var chirp_env := maxf(0.0, sin(TAU * 6.5 * t)) * (1.0 - u * 0.6)
		var chirp := sin(TAU * (2600.0 + 600.0 * sin(TAU * 20.0 * t)) * t) * chirp_env * 0.22
		samples[i] = lp + chirp
	return _build_wav(samples, false)


func _create_mouse_squeak_wav() -> AudioStreamWAV:
	var count := int(float(SAMPLE_RATE) * 0.24)
	var samples := PackedFloat32Array()
	samples.resize(count)
	for i in range(count):
		var u := float(i) / float(count)
		var t := float(i) / float(SAMPLE_RATE)
		var e1 := exp(-absf(u - 0.28) * 16.0)
		var e2 := exp(-absf(u - 0.72) * 18.0) * 0.75
		var f := lerpf(3600.0, 2900.0, fmod(u * 2.0, 1.0))
		samples[i] = sin(TAU * f * t) * (e1 + e2) * 0.18
	return _build_wav(samples, false)
