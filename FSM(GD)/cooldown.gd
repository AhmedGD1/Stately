class_name Cooldown

var _duration: float
var _remaining_time: float
var _active: bool

var duration:
	get: return _duration

var is_active: bool:
	get: return _active

func _init(cooldown_duration: float = 0.0) -> void:
	_duration = cooldown_duration

func set_duration(value: float) -> void:
	duration = max(0.0, value)

func update(delta: float) -> void:
	if !_active:
		return
	
	_remaining_time -= delta
	
	if _remaining_time <= 0.0:
		_remaining_time = 0.0
		_active = false

func start() -> void:
	if _duration <= 0.0:
		return
	
	_remaining_time = _duration
	_active = true

func reset() -> void:
	_remaining_time = 0.0
	_active = false

func get_remaining() -> float:
	return max(0.0, _remaining_time) if _active else 0.0

func get_progress() -> float:
	if _duration <= 0.0 || !_active:
		return 0.0
	
	var elapsed: float = _duration - _remaining_time
	return clamp(elapsed / _duration, 0.0, 1.0)

func get_normalized_remaining() -> float:
	if _duration <= 0.0 || !_active:
		return 0.0
	
	return clamp(_remaining_time / _duration, 0.0, 1.0)

func is_complete() -> bool:
	return !is_active






