# Godot FSM 🎮

A powerful, production-ready Finite State Machine implementation for C# in Godot. Built for complex game logic, AI behaviors, and any system requiring robust state management.

![License](https://img.shields.io/badge/license-MIT-blue.svg)
![Godot](https://img.shields.io/badge/Godot-4.x-blue.svg)
![C#](https://img.shields.io/badge/C%23-10.0-purple.svg)

## ✨ Features

- 🎯 **Type-Safe States** - Generic enum-based state system
- 🔄 **Flexible Transitions** - Condition-based, event-driven, and global transitions
- ⏱️ **Cooldown System** - Rate-limit states and transitions
- 📚 **State History** - Navigate backward through previous states with configurable capacity
- 🛡️ **Guard Conditions** - Pre-flight validation before transitions
- ⚡ **Priority System** - Control transition evaluation order
- 🔒 **State Locking** - Prevent unwanted transitions (full or transition-only)
- 🏷️ **Tags & Data** - Attach metadata to states and query by tags
- ⏰ **Timeouts** - Automatic state transitions after duration
- 📢 **Event System** - Decouple state logic with event-driven architecture
- 🔁 **Process Modes** - Separate Idle and Physics (Fixed) update loops
- 📊 **Transition Data** - Pass data between states during transitions

## 📦 Installation

1. Download or clone this repository
2. Copy the `Godot.FSM` folder into your Godot C# project
3. Ensure your project has C# support enabled
4. Add `using Godot.FSM;` to your scripts

## 🚀 Quick Start

### Basic Setup

```csharp
using Godot;
using Godot.FSM;

// Define your states as an enum
public enum CharacterState
{
    Idle,
    Walking,
    Running,
    Jumping,
    Falling
}

public partial class Character : CharacterBody3D
{
    private StateMachine<CharacterState> fsm;

    public override void _Ready()
    {
        // Create the state machine
        fsm = new StateMachine<CharacterState>();

        // Add states with callbacks
        fsm.AddState(CharacterState.Idle)
            .OnEnter(() => GD.Print("Now idle"))
            .OnUpdate(delta => HandleIdleMovement(delta))
            .OnExit(() => GD.Print("Leaving idle"));

        fsm.AddState(CharacterState.Walking)
            .OnUpdate(delta => HandleWalking(delta))
            .SetMinTime(0.1f); // Must walk for at least 0.1s

        fsm.AddState(CharacterState.Running)
            .OnUpdate(delta => HandleRunning(delta));

        // Add transitions with conditions
        fsm.AddTransition(CharacterState.Idle, CharacterState.Walking)
            .SetCondition(sm => GetMovementInput() > 0);

        fsm.AddTransition(CharacterState.Walking, CharacterState.Running)
            .SetCondition(sm => Input.IsActionPressed("sprint"))
            .SetGuard(sm => !IsExhausted());

        fsm.AddTransition(CharacterState.Running, CharacterState.Walking)
            .SetCondition(sm => !Input.IsActionPressed("sprint"));

        // Start the state machine
        fsm.Start();
    }

    public override void _Process(double delta)
    {
        // Update the state machine in _Process
        fsm.Process(FSMProcessMode.Idle, (float)delta);
        fsm.UpdateCooldownTimers((float)delta);
    }

    public override void _PhysicsProcess(double delta)
    {
        // Or update in _PhysicsProcess for physics-based logic
        fsm.Process(FSMProcessMode.Fixed, (float)delta);
    }

    private float GetMovementInput() => Input.GetAxis("move_left", "move_right");
    private bool IsExhausted() => false; // Your stamina logic here
    private void HandleIdleMovement(float delta) { /* ... */ }
    private void HandleWalking(float delta) { /* ... */ }
    private void HandleRunning(float delta) { /* ... */ }
}
```

## 📖 Core Concepts

### States

States represent distinct behaviors or modes in your system. Each state can have:
- Enter/Update/Exit callbacks
- Minimum time requirement
- Timeout with automatic transition
- Cooldown period after exiting
- Custom tags and data
- Lock modes

```csharp
fsm.AddState(EnemyState.Patrol)
    .OnEnter(() => {
        GD.Print("Starting patrol");
        PlayAnimation("patrol");
    })
    .OnUpdate(delta => {
        MoveAlongPatrolPath(delta);
        CheckForPlayer();
    })
    .OnExit(() => {
        StopAnimation();
    })
    .SetMinTime(2f)                      // Can't leave for 2 seconds
    .SetTimeout(30f)                     // Auto-transition after 30s
    .SetTimeoutId(EnemyState.Idle)       // Where to go on timeout
    .OnTimeout(() => GD.Print("Patrol timeout"))
    .SetCooldown(5f)                     // 5s cooldown after leaving
    .AddTags("movement", "ai")           // Tags for queries
    .SetData("patrol_speed", 3.5f)       // Custom data
    .Lock(FSMLockMode.Transition);       // Can't be interrupted
```

### Transitions

Transitions define how and when to move between states.

#### Basic Transitions

```csharp
// Simple condition-based transition
fsm.AddTransition(StateA, StateB)
    .SetCondition(sm => Health < 50);

// With priority (higher = evaluated first)
fsm.AddTransition(StateA, StateC)
    .SetCondition(sm => Health < 20)
    .SetPriority(10);

// With cooldown (can't retrigger for 3 seconds)
fsm.AddTransition(StateA, StateB)
    .SetCondition(sm => IsTriggered())
    .SetCooldown(3f);

// Callback when transition occurs
fsm.AddTransition(StateA, StateB)
    .SetCondition(sm => ShouldTransition())
    .OnTrigger(() => GD.Print("Transitioned!"));
```

#### Guards and Conditions

**Guards** are checked **first**, before time requirements:
- Use for early rejection (Is player alive? Is feature unlocked?)
- Return `false` to skip this transition entirely
- Checked for both regular and event-based transitions

**Conditions** are checked **after** guards and timing:
- Use for the actual transition trigger (Health low? Enemy visible?)
- Return `true` to trigger the transition
- Only used for regular transitions (not event-based)

```csharp
fsm.AddTransition(Idle, Attack)
    .SetGuard(sm => weaponEquipped && !isStunned)  // Checked first
    .SetCondition(sm => enemyInRange);              // Then checked
```

#### Event-Based Transitions

```csharp
// Define event-based transition
fsm.AddTransition(Idle, Hurt)
    .OnEvent("damage_taken")
    .SetGuard(sm => !IsInvulnerable());

// Trigger the event from anywhere
fsm.SendEvent("damage_taken");

// Listen to events
fsm.OnEvent("damage_taken", () => {
    PlayHurtSound();
    FlashRed();
});
```

#### Global Transitions

Global transitions work from **any state**:

```csharp
// Death transition available from anywhere
fsm.AddGlobalTransition(PlayerState.Dead)
    .SetCondition(sm => Health <= 0)
    .SetMaxPriority();  // Highest priority

// Pause transition
fsm.AddGlobalTransition(PlayerState.Paused)
    .OnEvent("pause_pressed");
```

#### Special Transitions

```csharp
// Self-transition (stays in same state but triggers callbacks)
fsm.AddSelfTransition(State.Reloading)
    .SetCondition(sm => Input.IsActionJustPressed("reload"));

// Reset transition (returns to initial state)
fsm.AddResetTransition(State.GameOver);

// Multiple states to one target
fsm.AddTransitions(
    new[] { State.Walking, State.Running, State.Crouching },
    State.Jumping,
    sm => Input.IsActionJustPressed("jump")
);
```

### State History

Navigate through previous states:

```csharp
// Configure history
fsm.SetHistoryActive(true);
fsm.StateHistory.SetCapacity(50);  // Max 50 entries

// Go back one state
if (fsm.CanGoBack())
    fsm.GoBack();

// Go back multiple steps
fsm.GoBack(3);

// Go back to specific state
fsm.GoBackToState(MenuState.MainMenu);

// Check history
var history = fsm.StateHistory.GetRecentHistory(5);
foreach (var entry in history)
{
    GD.Print($"Was in {entry.StateId} for {entry.TimeSpent}s at {entry.TimeStamp}");
}

// Find how many steps back a state is
int steps = fsm.FindInHistory(MenuState.Settings);
if (steps > 0)
    GD.Print($"Settings menu is {steps} steps back");
```

### State Locking

Prevent unwanted state changes:

```csharp
// Full lock - can't exit state at all
fsm.AddState(State.Cutscene)
    .Lock(FSMLockMode.Full);

// Transition lock - can timeout but can't transition normally
fsm.AddState(State.Attacking)
    .Lock(FSMLockMode.Transition)
    .SetTimeout(0.5f)
    .SetTimeoutId(State.Idle);

// Unlock state
fsm.GetState(State.Cutscene).Unlock();
```

### Cooldowns

Prevent rapid state or transition changes:

```csharp
// State cooldown (can't enter for X seconds after leaving)
fsm.AddState(State.Dash)
    .SetCooldown(2f);

// Transition cooldown (can't trigger for X seconds)
fsm.AddTransition(State.Idle, State.Attack)
    .SetCooldown(0.5f);

// Check and reset cooldowns
if (fsm.IsStateOnCooldown(State.Dash))
    GD.Print("Dash is on cooldown");

fsm.ResetStateCooldown(State.Dash);
fsm.ResetAllCooldowns();

// Get active cooldown count
int active = fsm.GetActiveCooldownCount();
```

### Tags and Data

Organize and query states:

```csharp
// Add tags to states
fsm.AddState(State.Swimming)
    .AddTags("movement", "water", "slow");

fsm.AddState(State.Diving)
    .AddTags("movement", "water", "submerged");

// Query by tag
if (fsm.IsInStateWithTag("water"))
    ApplyWaterPhysics();

var waterStates = fsm.GetStatesWithTag("water");

// Store data on states
fsm.AddState(State.Walking)
    .SetData("speed", 5.0f)
    .SetData("animation", "walk");

// Retrieve data
if (fsm.GetState(State.Walking).TryGetData("speed", out float speed))
    Velocity = Forward * speed;

// Global data (shared across all states)
fsm.SetData("player_health", 100);
if (fsm.TryGetData("player_health", out int health))
    GD.Print($"Health: {health}");
```

### Passing Data Between States

```csharp
// Pass data during transition
var damageInfo = new DamageInfo { Amount = 25, Source = "Enemy" };
fsm.TryChangeState(State.Hurt, data: damageInfo);

// Retrieve in the target state's OnEnter
fsm.AddState(State.Hurt)
    .OnEnter(() => {
        var damage = fsm.GetPerTransitionData<DamageInfo>();
        if (damage != null)
            ApplyDamage(damage.Amount);
    });
```

### Timeouts

Automatic transitions after a duration:

```csharp
// State with timeout
fsm.AddState(State.Invincible)
    .SetTimeout(3f)                      // 3 seconds
    .SetTimeoutId(State.Normal)          // Return to Normal
    .OnTimeout(() => {
        GD.Print("Invincibility expired");
    });

// Get remaining time
float remaining = fsm.GetRemainingTime();
float progress = fsm.GetTimeoutProgress(); // 0.0 to 1.0
```

## 🎮 Advanced Usage

### Process Modes

Separate logic for different update loops:

```csharp
// Configure states for specific process modes
fsm.AddState(State.Movement)
    .SetProcessMode(FSMProcessMode.Fixed)  // Physics
    .OnUpdate(delta => HandlePhysics(delta));

fsm.AddState(State.UI)
    .SetProcessMode(FSMProcessMode.Idle)   // Frame
    .OnUpdate(delta => UpdateUI(delta));

// In your node
public override void _Process(double delta)
{
    fsm.Process(FSMProcessMode.Idle, (float)delta);
    fsm.UpdateCooldownTimers((float)delta);
}

public override void _PhysicsProcess(double delta)
{
    fsm.Process(FSMProcessMode.Fixed, (float)delta);
}
```

### Manual State Changes

```csharp
// Try to change state (respects locks and min time)
bool success = fsm.TryChangeState(State.Jumping);

// Force state change with data
var jumpData = new JumpInfo { Height = 5f };
fsm.TryChangeState(State.Jumping, data: jumpData);

// Change with condition
fsm.TryChangeState(State.Running, 
    condition: () => StaminaAvailable());

// Restart current state
fsm.RestartCurrentState(callEnter: true, callExit: false);
```

### State Machine Events

Subscribe to state machine events:

```csharp
// Listen to state changes
fsm.StateChanged += (from, to) => {
    GD.Print($"Changed from {from} to {to}");
    UpdateAnimator(to);
};

// Listen to transitions
fsm.TransitionTriggered += (from, to) => {
    GD.Print($"Transition triggered: {from} -> {to}");
};

// Listen to timeouts
fsm.StateTimeout += (stateId) => {
    GD.Print($"State {stateId} timed out");
};

// Listen to blocked timeouts
fsm.TimeoutBlocked += (stateId) => {
    GD.Print($"Timeout blocked for {stateId} (cooldown or lock)");
};
```

### Querying State Machine

```csharp
// Current state info
T currentId = fsm.GetCurrentId();
string stateName = fsm.GetCurrentStateName();
float timeInState = fsm.GetStateTime();
float lastStateTime = fsm.GetLastStateTime();

// Previous state
T previousId = fsm.GetPreviousId();
bool wasPrevious = fsm.IsPreviousState(State.Idle);

// Check states
bool isIdle = fsm.IsCurrentState(State.Idle);
bool canLeave = fsm.MintimeExceeded();

// Check transitions
bool hasTransition = fsm.HasTransition(StateA, StateB);
bool hasGlobal = fsm.HasGlobalTransition(State.Death);

// Get available transitions from current state
var transitions = fsm.GetAvailableTransitions();
```

### Pause and Resume

```csharp
// Pause state machine
fsm.Pause();

// Resume
fsm.Resume();

// Toggle
fsm.TogglePaused(true);

// Check if active
bool isActive = fsm.IsActive();
```

## 🎯 Real-World Examples

### Example 1: Player Controller

```csharp
public enum PlayerState { Idle, Walk, Run, Jump, Fall, Attack, Hurt, Dead }

public partial class Player : CharacterBody3D
{
    private StateMachine<PlayerState> fsm;
    private float health = 100f;

    public override void _Ready()
    {
        fsm = new StateMachine<PlayerState>();

        // Setup states
        fsm.AddState(PlayerState.Idle)
            .OnEnter(() => animator.Play("idle"))
            .SetMinTime(0.1f);

        fsm.AddState(PlayerState.Walk)
            .OnUpdate(delta => Move(delta, walkSpeed))
            .OnEnter(() => animator.Play("walk"));

        fsm.AddState(PlayerState.Jump)
            .OnEnter(() => ApplyJumpForce())
            .SetTimeout(0.3f)
            .SetTimeoutId(PlayerState.Fall);

        fsm.AddState(PlayerState.Hurt)
            .OnEnter(() => {
                var damage = fsm.GetPerTransitionData<float>();
                health -= damage;
                PlayHurtAnimation();
            })
            .SetTimeout(0.5f)
            .SetTimeoutId(PlayerState.Idle)
            .Lock(FSMLockMode.Full);

        // Ground movement
        fsm.AddTransition(PlayerState.Idle, PlayerState.Walk)
            .SetCondition(sm => GetInputVector().Length() > 0);

        fsm.AddTransition(PlayerState.Walk, PlayerState.Idle)
            .SetCondition(sm => GetInputVector().Length() == 0);

        // Jumping
        fsm.AddTransitions(
            new[] { PlayerState.Idle, PlayerState.Walk },
            PlayerState.Jump,
            sm => Input.IsActionJustPressed("jump") && IsOnFloor()
        );

        // Taking damage (global)
        fsm.AddGlobalTransition(PlayerState.Hurt)
            .OnEvent("take_damage")
            .SetGuard(sm => health > 0);

        // Death (global, highest priority)
        fsm.AddGlobalTransition(PlayerState.Dead)
            .SetCondition(sm => health <= 0)
            .SetMaxPriority();

        fsm.Start();
    }

    public void TakeDamage(float amount)
    {
        fsm.SetData("pending_damage", amount);
        fsm.SendEvent("take_damage");
    }
}
```

### Example 2: Enemy AI

```csharp
public enum EnemyState { Idle, Patrol, Chase, Attack, Retreat, Dead }

public partial class Enemy : CharacterBody3D
{
    private StateMachine<EnemyState> fsm;
    private Node3D player;

    public override void _Ready()
    {
        fsm = new StateMachine<EnemyState>();

        fsm.AddState(EnemyState.Idle)
            .SetTimeout(3f)
            .SetTimeoutId(EnemyState.Patrol);

        fsm.AddState(EnemyState.Patrol)
            .OnUpdate(delta => PatrolBehavior(delta))
            .SetTimeout(15f)
            .SetTimeoutId(EnemyState.Idle);

        fsm.AddState(EnemyState.Chase)
            .OnUpdate(delta => ChasePlayer(delta))
            .SetData("chase_speed", 7f);

        fsm.AddState(EnemyState.Attack)
            .OnEnter(() => PerformAttack())
            .SetTimeout(1.5f)
            .SetTimeoutId(EnemyState.Chase)
            .SetCooldown(2f);  // Can't attack again for 2s

        // Detect player
        fsm.AddTransitions(
            new[] { EnemyState.Idle, EnemyState.Patrol },
            EnemyState.Chase,
            sm => PlayerInRange() && CanSeePlayer()
        );

        // Attack when close
        fsm.AddTransition(EnemyState.Chase, EnemyState.Attack)
            .SetCondition(sm => PlayerInAttackRange())
            .SetGuard(sm => !fsm.IsStateOnCooldown(EnemyState.Attack));

        // Lose player
        fsm.AddTransition(EnemyState.Chase, EnemyState.Patrol)
            .SetCondition(sm => !PlayerInRange())
            .SetMinTime(3f);  // Chase for at least 3s

        fsm.Start();
    }

    private bool PlayerInRange() => 
        GlobalPosition.DistanceTo(player.GlobalPosition) < 15f;
    
    private bool PlayerInAttackRange() => 
        GlobalPosition.DistanceTo(player.GlobalPosition) < 2f;
}
```

### Example 3: Menu System

```csharp
public enum MenuState { MainMenu, Settings, Graphics, Audio, Controls, Paused }

public partial class MenuManager : Control
{
    private StateMachine<MenuState> fsm;

    public override void _Ready()
    {
        fsm = new StateMachine<MenuState>();
        fsm.SetHistoryActive(true);  // Enable navigation history

        // Setup all menu states
        fsm.AddState(MenuState.MainMenu)
            .OnEnter(() => ShowPanel("MainMenu"))
            .AddTags("menu", "root");

        fsm.AddState(MenuState.Settings)
            .OnEnter(() => ShowPanel("Settings"))
            .AddTags("menu", "submenu");

        fsm.AddState(MenuState.Graphics)
            .OnEnter(() => ShowPanel("Graphics"))
            .AddTags("settings_submenu");

        // Back button transitions
        fsm.AddTransitions(
            new[] { MenuState.Graphics, MenuState.Audio, MenuState.Controls },
            MenuState.Settings,
            sm => Input.IsActionJustPressed("ui_cancel")
        );

        fsm.Start();
    }

    public void OnBackButtonPressed()
    {
        // Use history to go back
        if (fsm.CanGoBack())
            fsm.GoBack();
    }

    public void OnSettingsPressed() => 
        fsm.TryChangeState(MenuState.Settings);
}
```

## 🔧 API Reference

### StateMachine<T>

| Method | Description |
|--------|-------------|
| `AddState(T id)` | Create a new state |
| `RemoveState(T id)` | Remove a state |
| `AddTransition(T from, T to)` | Add transition between states |
| `AddGlobalTransition(T to)` | Add transition from any state |
| `Start()` | Start the state machine |
| `Reset()` | Reset to initial state |
| `Process(FSMProcessMode, float)` | Update the state machine |
| `UpdateCooldownTimers(float)` | Update all cooldown timers |
| `TryChangeState(T to, ...)` | Attempt to change state |
| `SendEvent(string)` | Trigger an event |
| `GetCurrentId()` | Get current state ID |
| `IsCurrentState(T)` | Check if in specific state |
| `GoBack()` | Navigate to previous state |

### State<T>

| Method | Description |
|--------|-------------|
| `OnEnter(Action)` | Set enter callback |
| `OnUpdate(Action<float>)` | Set update callback |
| `OnExit(Action)` | Set exit callback |
| `SetMinTime(float)` | Set minimum time in state |
| `SetTimeout(float)` | Set automatic timeout |
| `SetCooldown(float)` | Set cooldown duration |
| `AddTags(params string[])` | Add tags to state |
| `SetData(string, object)` | Attach custom data |
| `Lock(FSMLockMode)` | Lock state |

### Transition<T>

| Method | Description |
|--------|-------------|
| `SetCondition(Predicate)` | Set transition condition |
| `SetGuard(Predicate)` | Set guard condition |
| `OnEvent(string)` | Make event-based |
| `SetPriority(int)` | Set evaluation priority |
| `SetCooldown(float)` | Set cooldown |
| `OnTrigger(Action)` | Set trigger callback |
| `ForceInstant()` | Ignore min time |

## 🤝 Contributing

Contributions are welcome! Please feel free to submit pull requests or open issues for bugs and feature requests.

## 📄 License

This project is licensed under the MIT License - see LICENSE file for details.

## 🙏 Credits

Created for the Godot Engine community with ❤️

---

**Need help?** Open an issue on GitHub
**Have suggestions?** Pull requests are welcome!
