class_name StateMachine

enum ProcessMode { 
	IDLE, PHYSICS
}

enum LockMode {
	None,
	Transition,
	Full
}

signal state_changed(from_id: int, to_id: int)
signal transition_triggered(from: int, to: int)
signal timeout_blocked(id: int)
signal state_timeout(id: int)

const MAX_QUEUED_TRANSITIONS: int = 50
const TRANSITION_DATA_ID: String = "__transition_data__"

var states: Dictionary[int, State] = {}
var global_data: Dictionary[String, Variant] = {}

var global_transitions: Array[Transition] = []
var cached_sorted_transitions: Array[Transition] = []
var pending_transitions: Array[int] = []

var event_listeners: Dictionary[String, Array] = {}
var pending_events: Array[String] = []

var current_state: State

var initial_id: int
var previous_id: int = -1

var initialized: bool
var has_previous_state: bool
var paused: bool
var transition_dirty: bool = true
var is_transitioning: bool
var is_processing_event: bool

var state_time: float
var last_state_time: float

var states_enum: Dictionary

func _init(_states_enum: Dictionary) -> void:
	states_enum = _states_enum

func add_state(id: int) -> State:
	if states.has(id):
		push_error("state with id: (%s) already exists" % id)
		return states[id]
	
	var state: State = State.new(id)
	states[id] = state
	
	if !initialized:
		set_initial_id(id)
	
	state.set_timeout_id(initial_id)
	return state

func start() -> void:
	if initialized:
		_change_state_internal(initial_id, true)

func remove_state(id: int) -> bool:
	if !states.has(id):
		push_warning("State with id: (%s) does not exist" % id)
		return false
	
	if initial_id == id:
		var new_id: int = states.keys().front()
		set_initial_id(new_id)
	
	if current_state.id == id:
		reset()
	
	for state: State in states.values():
		state.transitions = state.transitions.filter(func(t: Transition) -> bool: return t.to != id)
	global_transitions = global_transitions.filter(func(t: Transition) -> bool: return t.to != id)
	
	states.erase(id)
	sort_transitions()
	return true

func reset() -> bool:
	if states.is_empty():
		push_warning("Can not reset and empty state machine")
		return false
	
	if !initialized:
		push_warning("State Machine is not initialized - call set_initial_id() first")
		return false
	
	_change_state_internal(initial_id)
	has_previous_state = false
	previous_id = -1
	return true

func set_initial_id(id: int) -> void:
	if !states.has(id):
		push_error("state with id: (%s) does not exist" % id)
		return
	initial_id = id
	initialized = true

func restart_current_state(ignore_enter: bool = false, ignore_exit: bool = true) -> void:
	if current_state.is_locked():
		push_warning("Can't restart current state with id: %s since it's locked !" % states_enum.keys()[current_state.id])
		return
	
	reset_state_time()
	
	if !ignore_enter && current_state.enter.is_valid(): current_state.enter.call()
	if !ignore_exit && current_state.exit.is_valid(): current_state.exit.call()

func reset_state_time() -> void:
	last_state_time = state_time
	state_time = 0.0

func try_change_state(id: int, condition: Callable = Callable(), data: Variant = null) -> bool:
	if condition.is_valid() && !condition.call():
		return false
	
	if !states.has(id):
		return false
	
	if data != null:
		set_data(TRANSITION_DATA_ID, data)
	_change_state_internal(id)
	return true

func try_go_back() -> bool:
	if !has_previous_state || !states.has(previous_id) || current_state.is_locked():
		return false
	
	_change_state_internal(previous_id)
	return true

func _change_state_internal(id, ignore_exit: bool = false) -> void:
	if is_transitioning:
		if pending_transitions.size() >= MAX_QUEUED_TRANSITIONS:
			push_error("Too many queued transitions (%d)! Possible infinite loop?" % MAX_QUEUED_TRANSITIONS)
			return
		pending_transitions.append(id)
		return
	
	if !states.has(id):
		push_warning("Can not change state to %s as it does not exist" % id)
		return
	
	var value = states[id]
	is_transitioning = true
	
	var can_exit = !ignore_exit && current_state != null && !current_state.is_locked()
	if can_exit:
		_safe_call(current_state.exit)
	
	last_state_time = state_time
	state_time = 0.0
	
	if current_state != null:
		previous_id = current_state.id
		has_previous_state = true
	
	current_state = value
	_safe_call(current_state.enter)
	
	sort_transitions()
	
	if initialized:
		state_changed.emit(previous_id, current_state.id)
	
	if pending_transitions.size() > 0:
		var next_id = pending_transitions.pop_front()
		is_transitioning = false
		_change_state_internal(next_id)
	else:
		is_transitioning = false
	
	remove_global_data(TRANSITION_DATA_ID)

func _safe_call(callable: Callable) -> bool:
	if callable.is_valid():
		callable.call()
		return true
	return false

func add_transition(from: int, to: int) -> Transition:
	if !states.has(from):
		push_error("From state doesn't exist")
		return null
	
	if !states.has(to):
		push_error("To state doesn't exist")
		return null
	
	var transition: Transition = states[from].add_transition(to)
	
	sort_transitions()
	return transition

func add_similar_transitions(from: Array[int], to: int, condition: Callable) -> void:
	for i: int in range(from.size()):
		add_transition(i, to).set_condition(condition)

func add_global_transition(to: int) -> Transition:
	if !states.has(to):
		push_error("To State does not exist")
		return null
	var transition: Transition = Transition.new(-1, to)
	global_transitions.append(transition)
	
	sort_transitions()
	return transition

func remove_transition(from: int, to: int) -> bool:
	if !states.has(from):
		push_error("From State does not exist")
		return false
	
	var original_size: int = states[from].transitions.size()
	states[from].transitions = states[from].transitions.filter(func(t: Transition) -> bool: return t.to != to)
	
	var removed: int = original_size - states[from].transitions.size()
	
	sort_transitions()
	return removed > 0

func remove_global_transition(to: int) -> bool:
	var original_size: int = global_transitions.size()
	
	global_transitions = global_transitions.filter(func(t: Transition) -> bool: return t.to != to)
	var removed: int = original_size - global_transitions.size()
	
	sort_transitions()
	return removed > 0

func clear_transitions_from(id: int) -> void:
	if !states.has(id):
		push_error("State with id: %s does not exist" % [states_enum.keys()[id]])
		return
	states[id].transitions.clear()
	sort_transitions()

func clear_transitions() -> void:
	for state: State in states.values():
		state.transitions.clear()
	sort_transitions()

func clear_global_transitions() -> void:
	global_transitions.clear()
	sort_transitions()

func sort_transitions() -> void:
	transition_dirty = true

func send_event(event_name: String) -> void:
	if event_name.is_empty():
		return
	pending_events.append(event_name)

func on_event(event_name: String, callback: Callable) -> void:
	if event_name.is_empty():
		return
	
	if !event_listeners.has(event_name):
		event_listeners[event_name] = []
	event_listeners[event_name].append(callback)

func remove_event_listener(event_name: String, callback: Callable) -> void:
	if event_listeners.has(event_name):
		event_listeners[event_name].erase(callback)
		
		if event_listeners[event_name].is_empty():
			event_listeners.erase(event_name)

func _process_events() -> void:
	while pending_events.size() > 0:
		var event_name: String = pending_events.pop_front()
		
		if event_listeners.has(event_name):
			var listeners: Array = event_listeners[event_name]
			var size: int = listeners.size()
			
			for i: int in range(size):
				if listeners[i].is_valid():
					listeners[i].call()
			
		if cached_sorted_transitions.size() > 0:
			_check_event_transitions(event_name)

func _check_event_transitions(event_name: String) -> void:
	if is_processing_event:
		return
	
	is_processing_event = true
	
	for transition: Transition in cached_sorted_transitions:
		if transition.event_name.is_empty():
			continue
		
		if transition.event_name != event_name:
			continue
		
		var guard_passed: bool = true
		if transition.guard.is_valid():
			guard_passed = transition.guard.call()
		
		var required_time: float = transition.override_min_time if transition.override_min_time > 0.0 else current_state.min_time
		var time_requirement_met: bool = state_time > required_time || transition.force_instant_transition
		
		if guard_passed && time_requirement_met:
			_change_state_internal(transition.to)
			transition_triggered.emit(transition.from, transition.to)
			if transition.triggered.is_valid(): transition.triggered.call()
			
			is_processing_event = false
			return
		
	is_processing_event = false

func process(mode: StateMachine.ProcessMode, delta: float) -> void:
	if paused || current_state == null:
		return
	
	if current_state.get_process_mode() == mode:
		state_time += delta
		_execute_state_update(delta)
		_check_transitions()

func _execute_state_update(delta: float) -> void:
	if current_state.update.is_valid():
		current_state.update.call(delta)

func _check_transitions() -> void:
	if current_state == null: return
	
	_process_events()
	
	var timeout_triggered: bool = current_state.timeout > 0.0 && state_time >= current_state.timeout
	
	if timeout_triggered:
		_on_state_timeout_triggered()
		return
	
	if current_state.transition_blocked():
		return
	
	_rebuild_transition_cache()
	
	if !cached_sorted_transitions.is_empty():
		_check_transition_loop()

func _on_state_timeout_triggered() -> void:
	if current_state.is_fully_locked():
		timeout_blocked.emit(current_state.id)
		return
	
	var timeout_id: int = current_state.timeout_id
	var from_id: int = current_state.id
	
	if !states.has(timeout_id):
		push_error("State with id: %s , does not have a timeout id" % from_id)
		return
	
	if current_state.callback.is_valid():
		current_state.callback.call()
	state_timeout.emit(from_id)
	transition_triggered.emit(from_id, timeout_id)
	_change_state_internal(timeout_id)

func _check_transition_loop() -> void:
	for transition: Transition in cached_sorted_transitions:
		if transition.guard.is_valid() && !transition.guard.call():
			continue
		
		var required_time: float = transition.override_min_time if transition.override_min_time > 0.0 else current_state.min_time
		
		if state_time <= required_time && !transition.force_instant_transition:
			continue
		
		if transition.condition.is_valid() && transition.condition.call():
			_change_state_internal(transition.to)
			if transition.triggered.is_valid():
				transition.triggered.call()
			transition_triggered.emit(transition.from, transition.to)
			return

func _rebuild_transition_cache() -> void:
	if !transition_dirty:
		return
	
	cached_sorted_transitions.clear()
	cached_sorted_transitions.append_array(current_state.transitions)
	cached_sorted_transitions.append_array(global_transitions)
	cached_sorted_transitions.sort_custom(Transition.compare)
	
	transition_dirty = false

func set_data(key: String, value: Variant) -> bool:
	if key.is_empty():
		return false
	global_data[key] = value
	return true

func remove_global_data(key: String) -> bool:
	if key.is_empty():
		return false
	global_data.erase(key)
	return true

func get_data(key: String) -> Variant:
	if !global_data.has(key):
		push_error("Data with key: %s, does not exist" % key)
		return null
	return global_data[key]

func get_per_transition_data() -> Variant:
	return global_data.get(TRANSITION_DATA_ID, null)

func get_data_safe(id: String, default = null) -> Variant:
	return global_data.get(id, default)

func is_active() -> bool:
	return !paused

func pause() -> void:
	paused = true

func resume(reset_time: bool = false) -> void:
	if reset_time:
		reset_state_time()
	paused = false

func get_previous_state_time() -> float:
	return last_state_time if has_previous_state else -1.0

func get_state_time() -> float:
	return state_time

func get_min_state_time() -> float:
	return current_state.min_time if current_state != null else -1.0

func get_remaining_time() -> float:
	return max(0.0, current_state.timeout - state_time) if current_state != null && current_state.timeout > 0 else -1.0

func get_state(id: int) -> State:
	return states[id] if states.has(id) else null

func get_state_with_tag(tag: String) -> State:
	for state: State in states.values():
		if state.tags.has(tag):
			return state
	return null

func get_state_with_name(state_name: String) -> State:
	for key: String in states_enum.keys():
		if key == state_name:
			var index: int = states_enum[key]
			return states[index]
	return null

func get_timeout_progress() -> float:
	if current_state == null || current_state.timeout <= 0.0:
		return -1.0
	return clamp(state_time / current_state.timeout, 0.0, 1.0)

func get_current_id() -> int:
	return current_state.id if current_state != null else -1

func get_initial_id() -> int:
	return initial_id if initialized else -1

func get_previous_id() -> int:
	return previous_id if has_previous_state else -1

func get_state_name(id: int) -> String:
	for key in states_enum.keys():
		if states_enum[key] == id:
			return key
	return "Unknown"

func min_time_exceeded() -> bool:
	return state_time > current_state.min_time if current_state != null else false

func has_transition(from: int, to: int) -> bool:
	if !states.has(from):
		return false
	return states[from].transitions.any(func(t): return t.to == to)

func has_global_transition(to: int) -> bool:
	return global_transitions.any(func(t): return t.to == to)

func is_in_state_with_tag(tag: String) -> bool:
	return current_state != null && current_state.tags.has(tag)

func is_current_state(id: int) -> bool:
	return current_state.id == id

func is_previous_state(id: int) -> bool:
	return previous_id == id && has_previous_state

func get_state_transitions_with_tag(tag: String) -> Array[Transition]:
	var index: int = states.values().find_custom(func(s: State) -> bool: return s.tags.has(tag))
	return states[index].transitions

func find_transitions_to(to: int) -> Array[Transition]:
	var transitions: Array[Transition] = []
	
	for state: State in states.values():
		var index: int = state.transitions.find_custom(func(t: Transition) -> bool: return t.to == to)
		
		if index != -1:
			transitions.append(state.transitions[index])
	return transitions

func can_transition_to(id: int) -> bool:
	if current_state == null || current_state.is_locked():
		return false
	return has_transition(current_state.id, id) || has_global_transition(id)

func get_available_transitions() -> Array[int]:
	if current_state == null:
		return []
	
	var result: Array[int] = []
	
	for t: Transition in current_state.transitions:
		result.append(t.to)
	
	for t: Transition in global_transitions:
		result.append(t.to)
	
	return result

func setup_state(id: int) -> State:
	return get_state(id) if states.has(id) else add_state(id)

func get_transition_count(id: int) -> int:
	if !states.has(id):
		return -1
	return states[id].transitions.size()

func have_event_listener(event_name: String) -> bool:
	return event_listeners.has(event_name)

func clear_pending_transitions() -> void:
	pending_transitions.clear()

func debug_current_transition() -> String:
	var prev: String = states_enum.keys()[previous_id]
	var current: String = states_enum.keys()[current_state.id]
	return "%s -> %s" % [prev, current]

func debug_all_transitions() -> String:
	var result: Array[String] = []
	for t: Transition in current_state.transitions:
		result.append("%s -> %s (Priority: %s)" % [get_state_name(t.from), get_state_name(t.to), t.priority])
	
	for t: Transition in global_transitions:
		result.append("Global -> %s (Priority: %s)" % [get_state_name(t.to), t.priority])
	
	return result.reduce(func(acc, w): return w if acc == "" else acc + "\n" + w, "")

func debug_all_states() -> String:
	var result: Array[String] = []
	for state: State in states.values():
		result.append(get_state_name(state.id))
	return result.reduce(func(acc, w): return w if acc == "" else acc + "\n" + w, "")





