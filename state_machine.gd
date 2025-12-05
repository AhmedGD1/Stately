## A flexible and feature-rich finite state machine implementation for Godot.
##
## This state machine supports:
## - State-specific and global transitions with priority ordering
## - Min time requirements and automatic timeouts
## - State locking mechanisms (full lock, transition lock)
## - Signal-based transitions with automatic cleanup
## - Animation integration (AnimatedSprite2D, AnimationPlayer)
## - Tag system for state categorization
## - Global and per-state data storage
## - Object pooling for performance optimization
##
## Basic Usage:
## [codeblock]
## enum States { IDLE, WALK, JUMP }
## var sm = StateMachine.new(States)
## 
## sm.add_state(States.IDLE, _update_idle, _enter_idle, _exit_idle)
## sm.add_state(States.WALK, _update_walk, _enter_walk, _exit_walk)
## sm.add_transition(States.IDLE, States.WALK, func(): return Input.is_action_pressed("move"))
## 
## sm.start()
## # In _physics_process:
## sm.process(StateMachine.ProcessType.PhysicsProcess, delta)
## [/codeblock]
class_name StateMachine

## Emitted when the state changes. Provides previous and next state IDs.
signal state_changed(prev: int, next: int)

## Emitted when a transition is triggered. Provides from and to state IDs.
signal transition_triggered(from: int, to: int)

## Emitted when a timeout is blocked due to state being fully locked.
signal timeout_blocked(from: int)

## Emitted when a state timeout occurs before transitioning.
signal state_timeout(from: int)

## Determines which process function the state uses for updates.
enum ProcessType { 
	Physics,   ## Uses _physics_process (fixed timestep)
	Idle         ## Uses _process (frame-based)
}

## Controls what operations are blocked in a locked state.
enum LockType { 
	Full,       ## Blocks all transitions including timeouts
	Transition, ## Blocks only manual transitions, allows timeouts
	None        ## No locking, all transitions allowed
}

## Dictionary mapping state IDs to their string names for debugging.
var states_enum: Dictionary

## All registered states in the state machine.
var states: Dictionary[int, State] = {}

## State-specific transitions organized by source state ID.
var transitions: Dictionary[int, Array] = {}

## Transitions that can trigger from any state.
var global_transitions: Array[Transition] = []

## Shared data accessible from all states.
var global_data: Dictionary[String, Variant] = {}

## Tracks signal connections for automatic cleanup.
var signal_connections: Dictionary[Object, Array] = {}

## Tracks signal condition states for signal-based transitions.
var signal_conditions: Dictionary[Object, Dictionary] = {}

## Reference to the current active state.
var current_state: State

## ID of the current active state.
var current_id: int

## ID of the previously active state.
var previous_id: int

## ID of the initial state to start with.
var initial_id: int

## Whether an initial state has been set.
var has_initial_id: bool

## When true, state machine stops processing updates and transitions.
var paused: bool

## Time elapsed in the current state (in seconds).
var state_time: float

var last_state_time: float

## Initializes the state machine with an enum dictionary for state names.
## @param sm_enum: Dictionary mapping state IDs to names (e.g., {0: "IDLE", 1: "WALK"})
func _init(sm_enum: Dictionary) -> void:
	states_enum = sm_enum

## Adds a new state to the state machine.
## The first state added automatically becomes the initial state.
##
## @param id: Unique identifier for this state
## @param update: Callable(delta: float) executed each frame while in this state
## @param enter: Callable() executed once when entering this state
## @param exit: Callable() executed once when leaving this state
## @param min_time: Minimum time (seconds) that must pass before transitions can occur
## @param timeout: If > 0, automatically transitions to restart_id after this many seconds
## @param process_type: Whether to use Process or PhysicsProcess for updates
## @return: The created State object for further configuration (chaining)
func add_state(id: int, update: Callable = Callable(), enter: Callable = Callable(), exit: Callable = Callable(), min_time: float = 0, timeout: float = -1, process_type: ProcessType = ProcessType.Physics) -> State:
	if states.has(id):
		push_error("Trying to store an existent state %s" % id)
		return null
	
	var state = State.new(id)
	states[id] = state
	
	if !has_initial_id:
		initial_id = id
		has_initial_id = true
	
	if has_initial_id:
		state.set_restart_id(initial_id)
	return state

## Starts the state machine by transitioning to the initial state.
## Must be called after adding states and before processing.
func start() -> void:
	if has_initial_id:
		_change_state_internal(initial_id, true)

## Removes a state and all associated transitions.
## If removing the current or initial state, the state machine will reset.
##
## @param id: ID of the state to remove
func remove_state(id: int) -> void:
	if !states.has(id):
		push_warning("Trying to access a non-existent state")
		return
	
	states.erase(id)
	
	if initial_id == id:
		has_initial_id = false
	if current_id == id:
		reset()
	
	# Remove all transitions involving this state
	for key: int in transitions.keys():
		@warning_ignore("standalone_expression")
		transitions[key] = transitions[key].filter(func(t: Transition): t.to != id && t.from != id)
	@warning_ignore("standalone_expression")
	global_transitions = global_transitions.filter(func(t: Transition): t.to != id)

## Resets the state machine to the initial state.
## If no initial state is set, uses the first state in the dictionary.
##
## @return: true if reset succeeded, false if state machine is empty
func reset() -> bool:
	if states.is_empty():
		push_warning("Trying to reset an empty state machine")
		return false
	
	if !has_initial_id:
		var state: State = states.values().front() as State
		set_initial_state(state.id)
	
	previous_id = -1
	_change_state_internal(initial_id)
	return true

## Sets which state the state machine should start in.
##
## @param id: ID of the state to use as initial state
func set_initial_state(id: int) -> void:
	if !states.has(id):
		push_error("Trying to set non-existent state as initial %s" % id)
		return
	initial_id = id
	has_initial_id = true

## Restarts the current state by calling exit and enter callbacks.
## Resets state_time to 0 and re-triggers enter logic.
##
## @param ignore_enter: If true, skips calling the enter callback
## @param ignore_exit: If true, skips calling the exit callback
func restart_current_state(ignore_enter: bool = false, ignore_exit: bool = false, respect_min_time: bool = false) -> void:
	if current_state == null:
		push_warning("Trying to access a non-existent state")
		return
	
	if respect_min_time && state_time < current_state.min_time:
		return
	state_time = 0.0
	
	if !ignore_exit && !current_state.is_locked(): current_state.exit.call()
	if !ignore_enter: current_state.enter.call()

## Gets a state object by its ID.
##
## @param id: ID of the state to retrieve
## @return: The State object, or null if not found
func get_state(id: int) -> State:
	return states.get(id, null)

## Attempts to change state only if the condition is true.
## Respects state locking and min_time requirements.
##
## @param id: Target state ID
## @param condition: Boolean condition that must be true for transition
## @return: true if transition occurred, false otherwise
func try_change_state(id: int, condition: bool) -> bool:
	if !condition:
		return false
	_change_state_internal(id)
	return true

## Forces a state change, bypassing normal transition checks.
## Still respects state locking.
##
## @param id: Target state ID
## @return: true if transition occurred, false if state is locked or invalid
func force_change_state(id: int) -> bool:
	if !states.has(id) || current_state == null || current_state.is_locked():
		return false
	_change_state_internal(id)
	return true

## Returns to the previous state.
## Fails if there's no previous state or current state is locked.
func go_back() -> void:
	if !states.has(previous_id) || current_state == null || current_state.is_locked():
		push_error("There is no previous state to go back to or current state is locked. Current State Id: %s" % current_id)
		return
	_change_state_internal(previous_id)

## Attempts to return to the previous state.
##
## @return: true if successfully went back, false if unable
func go_back_if_possible() -> bool:
	if !states.has(previous_id) || current_state == null || current_state.is_locked():
		return false
	_change_state_internal(previous_id)
	return true

## Internal state transition handler. Manages exit/enter callbacks,
## state time reset, animations, and signal emission.
##
## @param id: Target state ID
## @param ignore_exit: If true, skips calling exit callback of current state
func _change_state_internal(id: int, ignore_exit: bool = false) -> void:
	if !states.has(id):
		push_error("Trying to switch to a non-existent state")
		return
	
	var canExit: bool = !ignore_exit && current_state != null && !current_state.is_locked() && current_state.exit.is_valid()
	if canExit: current_state.exit.call()
	
	last_state_time = state_time
	state_time = 0.0
	previous_id = current_id
	current_id = id
	current_state = states[id]
	
	if current_state.enter.is_valid():
		current_state.enter.call()
	
	if has_initial_id:
		state_changed.emit(previous_id, current_id)

## Adds a transition from one state to another.
##
## @param from: Source state ID
## @param to: Target state ID
## @param condition: Callable() -> bool that determines if transition should occur
## @param override_min_time: If > 0, overrides the state's min_time for this transition
## @return: The created Transition object for further configuration
func add_transition(from: int, to: int, condition: Callable, override_min_time: float = -1) -> Transition:
	if !states.has(to):
		push_error("Trying to add a transition to a non-existent state")
		return null
	
	if !transitions.has(from):
		transitions[from] = []
	
	var transition: Transition = Transition.new(from, to)
	transitions[from].append(transition)
	
	return transition

## Adds a transition that can trigger from any state.
##
## @param to: Target state ID
## @param condition: Callable() -> bool that determines if transition should occur
## @param override_min_time: If > 0, overrides the state's min_time for this transition
## @return: The created Transition object for further configuration
func add_global_transition(to: int, condition: Callable, override_min_time: float = -1) -> Transition:
	if !states.has(to):
		push_error("Trying to add a transition to a non-existent state")
		return null
	
	var transition: Transition = Transition.new(-1, to)
	global_transitions.append(transition)
	
	return transition

## Adds a transition triggered by a Godot signal emission.
## The transition occurs the frame after the signal is emitted.
##
## @param from: Source state ID
## @param to: Target state ID
## @param sig: Godot Signal to listen for
## @param override_min_time: If > 0, overrides the state's min_time for this transition
## @return: The created Transition object for further configuration
func add_signal_transition(from: int, to: int, sig: Signal, override_min_time: float = -1) -> Transition:
	var condition: Callable = _create_condition_from_signal(sig)
	return add_transition(from, to, condition, override_min_time)

## Adds a global transition triggered by a Godot signal emission.
##
## @param to: Target state ID
## @param sig: Godot Signal to listen for
## @param override_min_time: If > 0, overrides the state's min_time for this transition
## @return: The created Transition object for further configuration
func add_global_signal_transition(to: int, sig: Signal, override_min_time: float = -1) -> Transition:
	var condition: Callable = _create_condition_from_signal(sig)
	return add_global_transition(to, condition, override_min_time)

## Creates a condition callable from a signal with automatic cleanup.
## Uses WeakRef to detect when the signal's object is freed.
##
## @param sig: Signal to create condition from
## @return: Callable that returns true when signal has been emitted
func _create_condition_from_signal(sig: Signal) -> Callable:
	var obj: Object = sig.get_object()
	var signal_name: String = sig.get_name()
	
	if obj == null:
		push_error("Signal has no valid object")
		return func(): return false
	
	var weak_ref: WeakRef = weakref(obj) as WeakRef
	
	if !signal_conditions.has(obj):
		signal_conditions[obj] = {}
		signal_connections[obj] = []
	
	var key: String = signal_name
	signal_conditions[obj][key] = false
	
	var connection: Callable = func(..._args: Array) -> void:
		var current_obj: Object = weak_ref.get_ref()
		if current_obj:
			# Only set the flag if the state is not locked
			# This prevents signals from queuing up during locked periods
			if current_state != null && !current_state.is_locked():
				signal_conditions[current_obj][key] = true
		else:
			_cleanup_object_signals(obj)
	
	sig.connect(connection)
	signal_connections[obj].append({"signal": sig, "connection": connection})
	
	return func() -> bool:
		var current_obj: Object = weak_ref.get_ref()
		if current_obj == null:
			_cleanup_object_signals(obj)
			return false
		
		# Double-check lock status when condition is evaluated
		if current_state != null && current_state.is_locked():
			# Clear any stale flags that might have been set
			signal_conditions[current_obj][key] = false
			return false
		
		if signal_conditions[current_obj].get(key, false):
			signal_conditions[current_obj][key] = false
			return true
		return false

## Disconnects and removes all signal connections for a given object.
## Called automatically when objects are freed.
##
## @param obj: Object whose signals should be cleaned up
func _cleanup_object_signals(obj: Object) -> void:
	if signal_connections.has(obj):
		# disconned all signals for this object
		for connection_data: Dictionary in signal_connections[obj]:
			var sig: Signal = connection_data.signal as Signal
			var connection: Callable = connection_data.connection
			
			if sig.is_connected(connection):
				sig.disconnect(connection)
		signal_connections.erase(obj)
	signal_conditions.erase(obj)

## Removes a specific transition between two states.
##
## @param from: Source state ID
## @param to: Target state ID
## @return: true if transition was found and removed, false otherwise
func remove_transition(from: int, to: int) -> bool:
	if !transitions.has(from):
		push_warning("Trying to remove a non-existent transition")
		return false
	
	var original_size = transitions[from].size()
	transitions[from] = transitions[from].filter(func(t: Transition): return t.to != to)
	
	if transitions[from].is_empty():
		transitions.erase(from)
	
	var removed: bool = transitions[from].size() < original_size if transitions.has(from) else original_size > 0
	if !removed: push_error("No Transition Was Found Between: %s -> %s" % [from, to])
	
	return removed

## Removes a global transition to a specific state.
##
## @param to: Target state ID of the global transition to remove
## @return: true if transition was found and removed, false otherwise
func remove_global_transition(to: int) -> bool:
	# if has any global transition
	var original_size: int = global_transitions.size()
	global_transitions = global_transitions.filter(func(t: Transition): return t.to != to)
	
	var removed: bool = global_transitions.size() < original_size
	if !removed: push_error("No Global Transition Was Found Between: %s -> %s" % [current_id, to])
	
	return removed

## Processes the current state's update callback and checks transitions.
## Should be called from _process or _physics_process in your node.
##
## @param process_type: Must match the current state's ProcessType
## @param delta: Time elapsed since last frame (in seconds)
func process(process_type: ProcessType, delta: float) -> void:
	if paused || current_state == null:
		return
	
	if current_state.process_type == process_type:
		state_time += delta
		if current_state.update:
			current_state.update.call(delta)
		_check_transitions()

## Checks and executes pending transitions based on conditions and priority.
## Handles timeout transitions and evaluates all candidate transitions.
func _check_transitions() -> void:
	var timeout_triggered: bool = current_state.timeout > 0 && state_time >= current_state.timeout
	if timeout_triggered:
		if current_state.is_fully_locked():
			timeout_blocked.emit(current_id)
			return
		
		state_timeout.emit(current_id)
		var restart_id: int = current_state.restart_id
		_change_state_internal(restart_id)
		transition_triggered.emit(current_id, restart_id)
		return
	
	if current_state.transition_blocked():
		return
	
	var evaluator: TransitionEvaluator = TransitionPool.get_evaluator()
	
	if transitions.has(current_id):
		evaluator.candidate_transitions.append_array(transitions[current_id])
	evaluator.candidate_transitions.append_array(global_transitions)
	
	if evaluator.has_candidates():
		evaluator.candidate_transitions.sort_custom(Transition.compare)
		_check_transition_loop(evaluator.candidate_transitions)
	TransitionPool.return_evaluator(evaluator)

## Iterates through sorted transitions and executes the first valid one.
##
## @param candidate_transitions: Array of transitions sorted by priority
func _check_transition_loop(candidate_transitions: Array[Transition]) -> void:
	for transition: Transition in candidate_transitions:
		var required_time: float = transition.override_min_time if transition.override_min_time > 0.0 else current_state.min_time
		var time_requirement_met: bool = transition.force_instant_transition || state_time >= required_time
		
		if time_requirement_met && transition.condition.call():
			_change_state_internal(transition.to)
			transition_triggered.emit(transition.from, transition.to)
			
			if transition.on_triggered.is_valid():
				transition.on_triggered.call()
			return

## Pauses the state machine, stopping all updates and transitions.
func pause() -> void: paused = true

## Checks if the state machine is currently paused.
##
## @return: true if paused, false otherwise
func is_paused() -> bool: return paused

## Resumes the state machine after pausing.
##
## @param reset_state_time: If true, resets state_time to 0
func resume(reset_state_time: bool = false) -> void:
	paused = false
	
	if reset_state_time:
		state_time = 0.0

## Stores a value in global data accessible from any state.
##
## @param key: String key for the data
## @param value: Value to store (any type)
## @return: true if successfully stored, false if key is empty
func set_global_data(key: String, value: Variant) -> bool:
	if key.is_empty():
		return false
	global_data[key] = value
	return true

## Removes a value from global data.
##
## @param key: String key of the data to remove
func remove_global_data(key: String) -> void: 
	global_data.erase(key)

## Retrieves a value from global data.
##
## @param key: String key of the data to retrieve
## @return: The stored value, or null if not found
func get_global_data(key: String) -> Variant:
	return global_data[key]

## Gets the ID of the current active state.
##
## @return: Current state ID
func get_current_state_id() -> int:
	return current_id

## Gets the ID of the initial state.
##
## @return: Initial state ID
func get_initial_state_id() -> int:
	return initial_id

## Gets the ID of the previously active state.
##
## @return: Previous state ID, or -1 if no previous state
func get_previous_state_id() -> int:
	return previous_id

## Gets the time elapsed in the current state.
##
## @return: State time in seconds
func get_state_time() -> float:
	return state_time

func get_last_state_time() -> float:
	return last_state_time

func min_time_exceeded() -> bool:
	return current_state != null && state_time > current_state.min_time

## Gets the minimum time requirement of the current state.
##
## @return: Min time in seconds, or -1 if no current state
func get_min_state_time() -> float:
	if current_state == null:
		return -1
	return current_state.min_time

## Gets the remaining time until the current state times out.
##
## @return: Remaining time in seconds, or -1 if no timeout set
func get_remaining_time() -> float:
	return max(0, current_state.timeout - state_time) if current_state != null && current_state.timeout > 0 else -1

## Gets the string name of a state from its ID.
##
## @param id: State ID to look up
## @return: State name string, or stringified ID if not found in enum
func get_state_name(id: int) -> String:
	return states_enum.keys()[id]

## Gets the string name of the current state from its ID.
##
## @return: State name string, or stringified ID if not found in enum
func get_current_state_name() -> String:
	return states_enum.keys()[current_id]

## Gets the state from its name.
##
## @return: State class, or null string if not found in enum
func get_state_with_name(state_name: String) -> State:
	var index: int = states_enum.keys().find(state_name)
	return states[index] if index != -1 else null

## Checks if a transition exists between two states.
##
## @param from: Source state ID
## @param to: Target state ID
## @return: true if transition exists
func has_transition(from: int, to: int) -> bool:
	return transitions.has(from) && transitions[from].any(func(t: Transition): return t.to == to)

## Checks if a state has any outgoing transitions.
##
## @param from: State ID to check
## @return: true if state has transitions
func has_any_transition_from(from: int) -> bool:
	return transitions.has(from) && !transitions[from].is_empty()

## Checks if a global transition exists to a specific state.
##
## @param to: Target state ID
## @return: true if global transition exists
func has_any_global_transition(to: int) -> bool:
	return global_transitions.any(func(t): return t.to == to)

## Checks if there is a previous state stored.
##
## @return: true if previous state exists
func has_previous_state() -> bool: 
	return previous_id != -1

## Checks if a state with the given ID exists.
##
## @param id: State ID to check
## @return: true if state exists
func has_state_with_id(id: int) -> bool: 
	return states.has(id)

## Checks if the given ID matches the current state.
##
## @param id: State ID to compare
## @return: true if ID matches current state
func is_current_state(id: int) -> bool:
	return current_state.id == id if current_state != null else false

## Checks if the given ID matches the previous state.
##
## @param id: State ID to compare
## @return: true if ID matches previous state
func is_previous_state(id: int) -> bool:
	return previous_id == id

## Checks if the current state has a specific tag.
##
## @param tag: Tag string to check for
## @return: true if current state has the tag
func is_in_state_with_tag(tag: String) -> bool:
	return current_state.tags.has(tag) if current_state != null else false

## Returns a debug string showing the last transition.
##
## @return: String in format "previous_id -> current_id"
func debug_current_transition() -> String:
	var prev: String = states_enum.keys()[previous_id]
	var current: String = states_enum.keys()[current_id]
	return "%s -> %s" % [prev, current]

## Returns a debug string listing all transitions with priorities.
##
## @return: Multi-line string of all transitions
func debug_all_transitions() -> String:
	var result: Array[String] = []
	for t_list: Array[Transition] in transitions.values():
		for t: Transition in t_list:
			result.append("%s -> %s (Priority: %s)" % [get_state_name(t.from), get_state_name(t.to), t.priority])
	
	for t: Transition in global_transitions:
		result.append("Global -> %s (Priority: %s)" % [get_state_name(t.to), t.priority])
	
	return result.reduce(func(acc, w): return w if acc == "" else acc + "\n" + w, "")

## Returns a debug string listing all state names.
##
## @return: Multi-line string of all state names
func debug_all_states() -> String:
	var result: Array[String] = []
	for state: State in states.values():
		result.append(get_state_name(state.id))
	return result.reduce(func(acc, w): return w if acc == "" else acc + "\n" + w, "")

## Represents a single state in the state machine.
## States can have update/enter/exit callbacks, timeouts, locking, tags, and custom data.
class State:
	## Unique identifier for this state
	var id: int
	
	## State to transition to when timeout occurs (defaults to self)
	var restart_id: int
	
	## Minimum time that must pass before transitions can occur (seconds)
	var min_time: float
	
	## If > 0, auto-transition to restart_id after this many seconds
	var timeout: float = -1
	
	## Callback executed each frame: Callable(delta: float)
	var update: Callable
	
	## Callback executed when entering this state: Callable()
	var enter: Callable
	
	## Callback executed when leaving this state: Callable()
	var exit: Callable
	
	## Which process type this state uses for updates
	var process_type: ProcessType
	
	## Current locking state
	var lock_type: LockType
	
	## Array of string tags for categorization
	var tags: Array[String] = []
	
	## Custom data storage for this state
	var data: Dictionary[String, Variant] = {}
	
	func on_update(method: Callable) -> State:
		update = method
		return self
	
	func on_enter(method: Callable) -> State:
		enter = method
		return self
	
	func on_exit(method: Callable) -> State:
		exit = method
		return self
	
	## Locks the state to prevent transitions.
	##
	## @param type: Type of lock (Full, Transition, or None)
	## @return: Self for method chaining
	func lock(type: LockType = LockType.Full) -> State:
		lock_type = type
		return self
	
	## Unlocks the state, allowing transitions.
	##
	## @return: Self for method chaining
	func unlock() -> State:
		lock_type = LockType.None
		return self
	
	func set_minmum_time(value: float) -> State:
		min_time = max(0.0, value)
		return self
	
	func set_timeout(value: float) -> State:
		if value <= 0:
			push_warning("Can only set timeout to value which is greater than zero")
			return self
		timeout = value
		return self
	
	## Sets which state to transition to on timeout.
	##
	## @param value: Target state ID
	## @return: Self for method chaining
	func set_restart_id(value: int) -> State:
		restart_id = value
		return self
	
	## Sets the process type for this state's updates.
	##
	## @param type: ProcessType.Process or ProcessType.PhysicsProcess
	## @return: Self for method chaining
	func set_process_type(type: ProcessType) -> State:
		process_type = type
		return self
	
	## Checks if state has any locking active.
	##
	## @return: true if locked in any way
	func is_locked() -> bool: return lock_type != LockType.None
	
	## Checks if state is fully locked (blocks everything).
	##
	## @return: true if fully locked
	func is_fully_locked() -> bool: return lock_type == LockType.Full
	
	## Checks if transitions are blocked.
	##
	## @return: true if transition-locked
	func transition_blocked() -> bool: return lock_type == LockType.Transition
	
	## Checks if state has a specific tag.
	##
	## @param tag: Tag to check for
	## @return: true if tag exists
	func has_tag(tag: String) -> bool: return tags.has(tag)
	
	## Checks if state has custom data with given key.
	##
	## @param key: Data key to check
	## @return: true if data exists
	func has_data(key: String) -> bool: return data.has(key)
	
	## Gets all tags on this state.
	##
	## @return: Array of tag strings
	func get_tags() -> Array[String]: return tags
	
	## Adds one or more tags to this state.
	##
	## @param args: Variable number of string tags
	## @return: Self for method chaining
	func add_tags(...args: Array) -> State:
		tags.append_array(args)
		return self
	
	## Stores custom data on this state.
	##
	## @param key: String key for the data
	## @param value: Value to store
	## @return: Self for method chaining
	func set_data(key: String, value: Variant) -> State:
		if !key.is_empty():
			data[key] = value
		return self
	
	## Removes custom data from this state.
	##
	## @param key: Key of data to remove
	## @return: Self for method chaining
	func remove_data(key: String) -> State:
		data.erase(key)
		return self
	
	## Retrieves custom data from this state.
	##
	## @param key: Key of data to retrieve
	## @return: The stored value, or null if not found
	func get_data(key: String) -> Variant:
		if !data.has(key):
			push_error("Trying to access a non-existent data")
			return null
		return data[key]
	
	## Internal constructor for State.
	##
	## @param new_id: Unique state identifier
	## @param new_update: Update callback
	## @param new_enter: Enter callback
	## @param new_exit: Exit callback
	## @param new_min_time: Minimum time before transitions
	## @param new_timeout: Timeout duration (or -1 for no timeout)
	## @param new_pt: Process type for this state
	func _init(new_id: int) -> void:
		id = new_id

## Represents a transition between states with a condition and priority.
## Transitions can override min_time, force instant execution, and have callbacks.
class Transition:
	## Source state ID (-1 for global transitions)
	var from: int
	
	## Target state ID
	var to: int
	
	## If > 0, overrides the source state's min_time requirement
	var override_min_time: float = -1.0
	
	## Callable() -> bool that determines if transition should occur
	var condition: Callable
	
	## If true, ignores min_time requirements completely
	var force_instant_transition: bool
	
	## Higher priority transitions are evaluated first (default: 1)
	var priority: int = 1
	
	## Unique insertion index for stable sorting when priorities are equal
	var insertion_index: int
	
	## Optional callback executed when this transition triggers: Callable()
	var triggered: Callable = Callable()
	
	## Maximum possible priority value
	const HIGHEST_PRIORITY: int = 9999999999
	
	## Makes this transition ignore min_time requirements.
	##
	## @return: Self for method chaining
	func force_instant() -> Transition:
		force_instant_transition = true
		return self
	
	## Sets the priority of this transition.
	## Higher values are evaluated first.
	##
	## @param value: Priority value (clamped to >= 0)
	## @return: Self for method chaining
	func set_priority(value: int) -> Transition:
		priority =  max(0, value)
		return self
	
	## Sets this transition to highest possible priority.
	##
	## @return: Self for method chaining
	func set_highest_priority() -> Transition:
		priority = HIGHEST_PRIORITY
		return self
	
	## Changes the condition for this transition.
	##
	## @param value: New condition callable
	## @return: Self for method chaining
	func set_condition(value: Callable) -> Transition:
		condition = value
		return self
	
	## Overrides the min_time requirement for this transition.
	##
	## @param value: New min_time in seconds
	## @return: Self for method chaining
	func set_min_time(value: float) -> Transition:
		override_min_time = value
		return self
	
	func on_triggered(method: Callable) -> Transition:
		if triggered.is_valid():
			triggered.call()
		return self
	
	## Internal constructor for Transition.
	##
	## @param from_id: Source state ID
	## @param to_id: Target state ID
	## @param cond: Condition callable
	## @param min_time: Override min_time value
	func _init(from_id: int, to_id: int) -> void:
		from = from_id
		to = to_id
		insertion_index = TransitionPool.get_next_index()
	
	## Comparison function for sorting transitions.
	## Sorts by priority (descending), then by insertion order (ascending).
	##
	## @param a: First transition
	## @param b: Second transition
	## @return: Comparison result for sorting
	static func compare(a: Transition, b: Transition) -> int:
		if a.priority == b.priority:
			return a.insertion_index - b.insertion_index
		return b.priority - a.priority

## Object pool for TransitionEvaluator instances to reduce allocations.
## Used internally by the state machine to optimize transition checking.
class TransitionPool:
	## Pool of available evaluator instances
	static var pool: Array[TransitionEvaluator] = []
	
	## Counter for generating unique insertion indices
	static var next_index: int = 0
	
	## Maximum number of evaluators to keep in the pool
	const MAX_POOL_SIZE: int = 32
	
	## Gets an evaluator from the pool or creates a new one.
	##
	## @return: A TransitionEvaluator instance
	static func get_evaluator() -> TransitionEvaluator:
		return pool.pop_front() if !pool.is_empty() else TransitionEvaluator.new()
	
	## Returns an evaluator to the pool for reuse.
	##
	## @param evaluator: Evaluator to return to pool
	static func return_evaluator(evaluator: TransitionEvaluator) -> void:
		if evaluator == null:
			return
		evaluator.reset()
		if pool.size() < MAX_POOL_SIZE:
			pool.append(evaluator)
	
	## Generates a unique index for transition insertion order.
	## Used for stable sorting when priorities are equal.
	##
	## @return: Next unique index
	static func get_next_index() -> int:
		next_index = (next_index + 1) % 2147483647
		return next_index

## Helper class for evaluating candidate transitions.
## Pooled to reduce allocations during transition checking.
class TransitionEvaluator:
	## Array of transitions to evaluate this frame
	var candidate_transitions: Array[Transition] = []
	
	## Clears the candidate list for reuse.
	func reset() -> void:
		candidate_transitions.clear()
	
	## Checks if there are any candidates to evaluate.
	##
	## @return: true if candidates exist
	func has_candidates() -> bool:
		return !candidate_transitions.is_empty()
