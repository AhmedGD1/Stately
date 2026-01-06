# Finite State Machine (FSM) for Godot C#

A powerful, flexible finite state machine implementation for Godot with C#. This FSM provides advanced features like cooldowns, state history, event-driven transitions, and priority-based transition handling.

## Features

- **Type-safe states** using C# enums
- **Flexible transitions** with conditions, guards, and priorities
- **Cooldown system** for states and transitions
- **State history** with navigation (go back, peek previous states)
- **Event-driven transitions** for decoupled state changes
- **Timeout support** for automatic state transitions
- **Global transitions** that work from any state
- **Process modes** (Idle/Fixed) for different update contexts
- **State locking** to prevent unwanted transitions
- **Per-transition data** for passing information between states
- **Comprehensive querying** and diagnostic methods

## Installation

Copy the FSM files into your Godot C# project:

```
YourProject/
├── Cooldown.cs
├── State.cs
├── StateMachine.cs
├── StateHistory.cs
└── Transition.cs
```

## Quick Start

```csharp
using Godot.FSM;

// Define your states using an enum
public enum PlayerState
{
    Idle,
    Walking,
    Running,
    Jumping
}

// Create the state machine
private StateMachine<PlayerState> fsm;

public override void _Ready()
{
    fsm = new StateMachine<PlayerState>();
    
    // Add states with callbacks
    fsm.AddState(PlayerState.Idle)
        .OnEnter(() => GD.Print("Entered Idle"))
        .OnUpdate(delta => GD.Print($"Idling... {delta}"))
        .OnExit(() => GD.Print("Exited Idle"));
    
    fsm.AddState(PlayerState.Walking);
    fsm.AddState(PlayerState.Running);
    fsm.AddState(PlayerState.Jumping);
    
    // Set initial state
    fsm.SetInitialId(PlayerState.Idle);
    
    // Add transitions with conditions
    fsm.AddTransition(PlayerState.Idle, PlayerState.Walking)
        .SetCondition(sm => Input.IsActionPressed("move"));
    
    fsm.AddTransition(PlayerState.Walking, PlayerState.Running)
        .SetCondition(sm => Input.IsActionPressed("sprint"));
    
    // Start the FSM
    fsm.Start();
}

public override void _Process(double delta)
{
    fsm.ProcessIdle((float)delta);
}
```

## Core Concepts

### States

States represent discrete conditions or behaviors. Each state can have:

```csharp
fsm.AddState(PlayerState.Attacking)
    .OnEnter(() => PlayAttackAnimation())           // Called when entering
    .OnUpdate(delta => UpdateAttack(delta))         // Called every frame
    .OnExit(() => ResetAttackState())              // Called when leaving
    .MinDuration(0.5f)                             // Minimum time in state
    .TimeoutAfter(2.0f)                            // Auto-transition after time
    .SetTimeoutId(PlayerState.Idle)                // Where to go on timeout
    .SetProcessMode(FSMProcessMode.Idle)           // When to update
    .SetCooldown(1.0f)                             // Cooldown before re-entering
    .AddTags("combat", "active")                   // For querying/grouping
    .SetData("damage", 25);                        // Store state-specific data
```

### Transitions

Transitions move the FSM from one state to another:

```csharp
fsm.AddTransition(PlayerState.Idle, PlayerState.Jumping)
    .SetGuard(sm => IsGrounded())                  // Pre-check (evaluated first)
    .SetCondition(sm => Input.IsActionJustPressed("jump"))  // Main condition
    .SetPriority(10)                               // Higher = checked first
    .RequireMinTime(0.2f)                          // Override state's min time
    .SetCooldown(0.5f)                             // Cooldown between uses
    .ForceInstant()                                // Ignore min time requirement
    .OnTrigger(() => PlayJumpSound());             // Called when triggered
```

> **Understanding Guards vs Conditions**
>
> **Guards** are pre-condition checks evaluated FIRST, before time requirements. Use them for early rejection:
> - "Is player alive?"
> - "Is this feature unlocked?"
> - "Is target in range?"
>
> **Conditions** are the main trigger evaluated AFTER guards and time requirements pass. Use them for actual transition logic:
> - "Is health below 20%?"
> - "Did player press jump button?"
> - "Is enemy visible?"
>
> Guards work in both regular and event-based transitions. Conditions only work in regular transitions (not event-based).
>
> **Example:**
> ```csharp
> fsm.AddTransition(PlayerState.Idle, PlayerState.Attack)
>     .SetGuard(sm => playerAlive && weaponEquipped)  // Check prerequisites
>     .SetCondition(sm => Input.IsActionPressed("attack"));  // Check trigger
> ```

### Event-Driven Transitions

Trigger transitions through events for decoupled logic:

```csharp
// Setup event-based transition
fsm.AddTransition(PlayerState.Idle, PlayerState.Damaged)
    .OnEvent("take_damage")
    .SetGuard(sm => !IsInvincible());

// Listen to events (optional)
fsm.OnEvent("take_damage", () => PlayHurtSound());

// Trigger the event from anywhere
fsm.TriggerEvent("take_damage");
```

### Global Transitions

Global transitions work from any state:

```csharp
// Can transition to Death from any state
fsm.AddGlobalTransition(PlayerState.Death)
    .SetCondition(sm => health <= 0);
```

### State History

Navigate through previously visited states:

```csharp
// Go back one state
if (fsm.CanGoBack())
    fsm.GoBack();

// Go back multiple states
fsm.GoBack(3);

// Go back to a specific state
fsm.GoBackToState(PlayerState.Idle);

// Peek at previous states without transitioning
PlayerState previousState = fsm.PeekBackState();
PlayerState twoStatesAgo = fsm.PeekBackState(2);

// Find a state in history
int stepsBack = fsm.FindInHistory(PlayerState.Walking);

// Get full history
var history = fsm.StateHistory.GetHistory();
foreach (var entry in history)
{
    GD.Print($"State: {entry.StateId}, Time: {entry.TimeSpent}s");
}

// Configure history
fsm.StateHistory.SetCapacity(50);  // Store last 50 states
fsm.SetHistoryActive(false);        // Disable history tracking
```

## Advanced Features

### Cooldowns

Prevent rapid state or transition changes:

```csharp
// State cooldown (can't re-enter for 2 seconds after leaving)
fsm.AddState(PlayerState.Dash)
    .SetCooldown(2.0f);

// Transition cooldown (can't use same transition for 1 second)
fsm.AddTransition(PlayerState.Idle, PlayerState.Attack)
    .SetCooldown(1.0f);

// Check and manage cooldowns
if (fsm.IsStateOnCooldown(PlayerState.Dash))
    GD.Print("Dash is on cooldown");

if (fsm.IsTransitionOnCooldown(PlayerState.Idle, PlayerState.Attack))
    GD.Print("Can't attack yet");

// Reset cooldowns
fsm.ResetStateCooldown(PlayerState.Dash);
fsm.ResetTransitionCooldown(PlayerState.Idle, PlayerState.Attack);
fsm.ResetAllCooldowns();

// Configure cooldown update timing
fsm.SetCooldownTimersProcessMode(FSMProcessMode.Idle);
```

### State Locking

Prevent transitions temporarily:

```csharp
// Full lock: no transitions allowed, timeout blocked
fsm.AddState(PlayerState.Stunned)
    .Lock(FSMLockMode.Full);

// Transition lock: manual transitions blocked, timeout still works
fsm.AddState(PlayerState.Casting)
    .Lock(FSMLockMode.Transition);

// Unlock
fsm.GetState(PlayerState.Stunned).Unlock();
```

### Process Modes

Control when states update:

```csharp
// Update during _Process (default)
fsm.AddState(PlayerState.Walking)
    .SetProcessMode(FSMProcessMode.Idle);

// Update during _PhysicsProcess
fsm.AddState(PlayerState.Jumping)
    .SetProcessMode(FSMProcessMode.Fixed);

// In your node
public override void _Process(double delta)
{
    fsm.ProcessIdle((float)delta);
}

public override void _PhysicsProcess(double delta)
{
    fsm.ProcessFixed((float)delta);
}
```

### Data Storage

Store and retrieve data:

```csharp
// Global data (accessible from anywhere)
fsm.SetData("player_score", 1000);
if (fsm.TryGetData<int>("player_score", out int score))
    GD.Print($"Score: {score}");

// State-specific data
fsm.GetState(PlayerState.Attacking)
    .SetData("combo_count", 0)
    .SetData("damage_multiplier", 1.5f);

if (fsm.GetState(PlayerState.Attacking).TryGetData<int>("combo_count", out int combo))
    GD.Print($"Combo: {combo}");

// Per-transition data (automatically cleared after transition)
fsm.TryTransitionTo(PlayerState.Damaged, data: damageInfo);
var damage = fsm.GetPerTransitionData<DamageInfo>();
```

### Tags

Organize and query states by tags:

```csharp
// Add tags to states
fsm.AddState(PlayerState.Walking).AddTags("movement", "grounded");
fsm.AddState(PlayerState.Running).AddTags("movement", "grounded");
fsm.AddState(PlayerState.Jumping).AddTags("movement", "airborne");

// Query by tags
if (fsm.IsInStateWithTag("movement"))
    GD.Print("Player is moving");

var groundedStates = fsm.GetStatesWithTag("grounded");
State<PlayerState> firstCombatState = fsm.GetStateWithTag("combat");
```

### State Timeout

Automatically transition after a duration:

```csharp
fsm.AddState(PlayerState.Dashing)
    .TimeoutAfter(0.5f)                      // Timeout after 0.5 seconds
    .SetTimeoutId(PlayerState.Idle)          // Go to Idle on timeout
    .OnTimeout(() => GD.Print("Dash ended"));

// Check timeout progress
float progress = fsm.GetTimeoutProgress();  // 0.0 to 1.0
float remaining = fsm.GetRemainingTime();

// Subscribe to timeout events
fsm.StateTimeout += (fromState) => GD.Print($"{fromState} timed out");
fsm.TimeoutBlocked += (state) => GD.Print($"{state} timeout blocked by lock");
```

## Utility Methods

### State Queries

```csharp
PlayerState current = fsm.GetCurrentId();
PlayerState previous = fsm.GetPreviousId();
string stateName = fsm.GetCurrentStateName();

bool isWalking = fsm.IsCurrentState(PlayerState.Walking);
bool wasIdle = fsm.IsPreviousState(PlayerState.Idle);

float timeInState = fsm.GetStateTime();
float lastStateTime = fsm.GetLastStateTime();
bool canTransition = fsm.MinTimeExceeded();
```

### Transition Queries

```csharp
bool hasTransition = fsm.HasTransition(PlayerState.Idle, PlayerState.Walking);
bool hasGlobalToState = fsm.HasGlobalTransition(PlayerState.Death);
bool hasAnyGlobal = fsm.HasAnyGlobalTransitions();

var availableTransitions = fsm.GetAvailableTransitions();
```

### State Management

```csharp
// Manual transitions
fsm.TryTransitionTo(PlayerState.Jumping);
fsm.TryTransitionTo(PlayerState.Attacking, () => HasTarget(), attackData);

// Restart current state
fsm.RestartCurrentState(callEnter: true, callExit: false);

// Reset to initial state
fsm.Reset();

// Remove states
fsm.RemoveState(PlayerState.Obsolete);

// Pause/Resume
fsm.Pause();
fsm.Resume();
fsm.TogglePaused(true);
bool active = fsm.IsActive();
```

## Events and Callbacks

### State Machine Events

```csharp
// Subscribe to state changes
fsm.StateChanged += (from, to) => 
    GD.Print($"Changed from {from} to {to}");

// Subscribe to transitions
fsm.TransitionTriggered += (from, to) => 
    GD.Print($"Transition: {from} → {to}");

// Subscribe to timeouts
fsm.StateTimeout += (state) => 
    GD.Print($"{state} timed out");

fsm.TimeoutBlocked += (state) => 
    GD.Print($"{state} timeout was blocked");
```

## Best Practices

1. **Use enums for type safety**: Define all states in a single enum for compile-time checking
2. **Set initial state explicitly**: Always call `SetInitialId()` before `Start()`
3. **Use guards for prerequisites**: Check conditions that must be true before considering a transition
4. **Use conditions for triggers**: Check actual trigger conditions in the condition predicate
5. **Leverage cooldowns**: Prevent rapid state oscillation with appropriate cooldowns
6. **Tag states logically**: Group related states with tags for easier querying
7. **Handle both process modes**: Call both `ProcessIdle()` and `ProcessFixed()` if needed
8. **Check history before going back**: Use `CanGoBack()` to prevent errors
9. **Use events for decoupling**: Trigger transitions through events when components shouldn't know about each other
10. **Clean up properly**: Call `Dispose()` when the state machine is no longer needed

## Common Patterns

### Combat State Machine

```csharp
public enum CombatState { Idle, Attacking, Blocking, Stunned, Dead }

fsm.AddState(CombatState.Idle).AddTags("combat", "active");
fsm.AddState(CombatState.Attacking).SetCooldown(0.3f).AddTags("combat", "active");
fsm.AddState(CombatState.Blocking).AddTags("combat", "defensive");
fsm.AddState(CombatState.Stunned).Lock(FSMLockMode.Full).TimeoutAfter(2.0f);
fsm.AddState(CombatState.Dead).Lock(FSMLockMode.Full);

fsm.AddTransition(CombatState.Idle, CombatState.Attacking)
    .SetGuard(sm => IsAlive())
    .SetCondition(sm => Input.IsActionJustPressed("attack"));

fsm.AddGlobalTransition(CombatState.Dead)
    .SetCondition(sm => health <= 0)
    .HighestPriority();
```

### AI State Machine

```csharp
public enum AIState { Patrol, Chase, Attack, Flee, Investigate }

fsm.AddState(AIState.Patrol)
    .OnUpdate(delta => PatrolRoute())
    .MinDuration(2.0f);

fsm.AddTransition(AIState.Patrol, AIState.Investigate)
    .SetCondition(sm => HeardNoise())
    .SetPriority(5);

fsm.AddTransition(AIState.Patrol, AIState.Chase)
    .SetCondition(sm => PlayerVisible())
    .SetPriority(10);

fsm.AddTransition(AIState.Chase, AIState.Attack)
    .SetGuard(sm => HasLineOfSight())
    .SetCondition(sm => InAttackRange());
```

## License

This FSM implementation is provided as-is for use in Godot C# projects.
