extends AudioStreamPlayer3D

## 3D Mosque Adhan player attached to the Minaret (max distance 360m).
## Starts 15 seconds after game start and repeats every 20 minutes (1200.0 seconds).

const INITIAL_DELAY_SEC: float = 15.0
const REPEAT_INTERVAL_SEC: float = 1200.0

var _track_idx: int = 0
var _timer: float = INITIAL_DELAY_SEC
var _waiting_to_play: bool = true


func _ready() -> void:
	max_distance = 360.0
	unit_size = 24.0
	volume_db = -1.0
	_timer = INITIAL_DELAY_SEC
	_waiting_to_play = true
	finished.connect(_on_finished)


func _process(delta: float) -> void:
	if _waiting_to_play:
		_timer -= delta
		if _timer <= 0.0:
			_waiting_to_play = false
			_play_next()


func _play_next() -> void:
	var audio_mgr := get_node_or_null("/root/AudioManager")
	if audio_mgr == null:
		return
	var streams: Array = audio_mgr.get_mosque_streams()
	if streams.is_empty():
		return
	stream = streams[_track_idx % streams.size()]
	_track_idx = (_track_idx + 1) % streams.size()
	play()


func _on_finished() -> void:
	_waiting_to_play = true
	_timer = REPEAT_INTERVAL_SEC
