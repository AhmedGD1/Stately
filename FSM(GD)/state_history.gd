class_name StateHistory

var is_active: bool:
	get: return _active

var capacity: int:
	get: return _capacity

var entry_size: int:
	get: return _entries.size()

var _entries: Array[HistoryEntry] = []
var _capacity: int = 20
var _total_elasped_time: float

var _active: bool = true

func set_active(value: bool) -> void:
	_active = value

func set_capacity(value: int) -> void:
	capacity = max(0, value)
	_trim()

func create_new_entry(state_id: int, time_spent: float) -> void:
	var entry: HistoryEntry = HistoryEntry.new(state_id, time_spent, _total_elasped_time)
	_entries.append(entry)
	
	_trim()

func update_elapsed_time(delta: float) -> void:
	_total_elasped_time += delta

func get_history() -> Array[HistoryEntry]:
	var reversed: Array[HistoryEntry] = _entries.duplicate()
	reversed.reverse()
	return reversed

func get_recent_history(count: int) -> Array[HistoryEntry]:
	var min: int = min(count, _entries.size())
	
	var recent: Array = []
	for i: int in range(_entries.size() - min, min):
		recent.append(_entries[i])
	
	recent.reverse()
	return recent

func get_entry(index: int) -> HistoryEntry:
	return _entries.get(index)

func remove_range(from: int, to: int) -> void:
	for i: int in range(from, to):
		_entries.remove_at(i)

func clear() -> void:
	_entries.clear()

func _trim() -> void:
	if _capacity > 0 && _entries.size() > _capacity:
		var remove_count: int = _entries.size() - _capacity
		
		for i: int in range(0, remove_count):
			_entries.remove_at(i)

class HistoryEntry:
	var state_id: int
	var time_spent: float
	var time_stamp: float
	
	func _init(id: int, spent: float, stamp: float) -> void:
		state_id = id
		time_spent = spent
		time_stamp = stamp
