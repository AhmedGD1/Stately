# Godot FSM - Complete Usage Guide

## Table of Contents
1. [Quick Start](#quick-start)
2. [Basic Concepts](#basic-concepts)
3. [State Configuration](#state-configuration)
4. [Transitions](#transitions)
5. [Events](#events)
6. [Advanced Features](#advanced-features)
7. [Best Practices](#best-practices)
8. [Complete Examples](#complete-examples)

---

## Quick Start

```csharp
// 1. Define your state enum
public enum PlayerState
{
    Idle,
    Walking,
    Running,
    Jumping,
    Falling
}

// 2. Create and configure the state machine
var fsm = new StateMachine<PlayerState>();

// 3. Add states with callbacks
fsm.AddState(PlayerState.Idle)
    .OnEnter(() => GD.Print("Entered Idle"))
    .OnUpdate((delta) => GD.Print($"Idling... {delta}"))
    .OnExit(() => GD.Print("Left Idle"));

fsm.AddState(PlayerState.Walking);
fsm.AddState(PlayerState.Running);

// 4. Add transitions
fsm.AddTransition(PlayerState.Idle, PlayerState.Walking)
    .SetCondition(fsm => Input.IsActionPressed("move"));

fsm.AddTransition(PlayerState.Walking, PlayerState.Running)
    .SetCondition(fsm => Input.IsActionPressed("sprint"));

// 5. Start the machine
fsm.Start();

// 6. Update every frame
public override void _Process(double delta)
{
    fsm.Process(FSMProcessMode.Idle, (float)delta);
}

// 7. Clean up when done
public override void _ExitTree()
{
    fsm.Dispose();
}
```

---

## Basic Concepts

### States
A **State** represents a distinct behavior or condition. Each state can have:
- **Enter callback**: Runs once when entering the state
- **Update callback**: Runs every frame while in the state
- **Exit callback**: Runs once when leaving the state
- **Timeout**: Automatic transition after X seconds
- **MinTime**: Minimum time before transitions are allowed
- **Tags**: String labels for querying states
- **Data**: Key-value storage for state-specific data
- **Process Mode**: Idle (_Process) or Fixed (_PhysicsProcess)
- **Lock Mode**: Prevents transitions (Full, Transition, or None)

### Transitions
A **Transition** defines when and how to move between states. Features:
- **Condition**: Function that returns true to trigger transition
- **Guard**: Pre-check that must pass before evaluating condition
- **Event**: Trigger on named event (e.g., "jump_pressed")
- **Priority**: Higher priority transitions are checked first
- **MinTime override**: Override state's minimum time for this transition
- **OnTriggered callback**: Runs when transition fires

### State Machine
The **StateMachine** orchestrates everything:
- Manages states and transitions
- Tracks current/previous state
- Processes frame updates
- Handles events
- Stores global data
- Provides introspection methods

---

## State Configuration

### Basic State Setup

```csharp
fsm.AddState(PlayerState.Idle)
    .OnEnter(() => {
        animPlayer.Play("idle");
        velocity = Vector2.Zero;
    })
    .OnUpdate((delta) => {
        // Runs every frame while idle
        CheckForInput();
    })
    .OnExit(() => {
        GD.Print("No longer idle");
    });
```

### Timeouts

```csharp
// Auto-transition to Walking after 3 seconds of being Idle
fsm.AddState(PlayerState.Idle)
    .SetTimeout(3.0f)
    .SetTimeoutId(PlayerState.Walking)
    .OnTimeout(() => GD.Print("Idle timeout reached!"));
```

### Minimum Time

```csharp
// Must be in Running state for at least 0.5 seconds before transitioning out
fsm.AddState(PlayerState.Running)
    .SetMinTime(0.5f);
```

### Process Modes

```csharp
// This state only updates during _PhysicsProcess
fsm.AddState(PlayerState.Falling)
    .SetProcessMode(FSMProcessMode.Fixed)
    .OnUpdate((delta) => {
        // Physics calculations here
        ApplyGravity(delta);
    });

// In your node:
public override void _PhysicsProcess(double delta)
{
    fsm.Process(FSMProcessMode.Fixed, (float)delta);
}
```

### State Locking

```csharp
// Full lock: No transitions allowed, timeout blocked
fsm.AddState(PlayerState.Attacking)
    .Lock(FSMLockMode.Full)
    .OnEnter(() => attackAnimation.Play())
    .OnUpdate((delta) => {
        if (attackAnimation.Finished)
            GetCurrentState().Unlock();
    });

// Transition lock: Can timeout but can't transition via conditions
fsm.AddState(PlayerState.Stunned)
    .Lock(FSMLockMode.Transition)
    .SetTimeout(2.0f)
    .SetTimeoutId(PlayerState.Idle);
```

### Tags and Data

```csharp
// Add tags for querying
fsm.AddState(PlayerState.Walking)
    .AddTags("movement", "grounded");

fsm.AddState(PlayerState.Running)
    .AddTags("movement", "grounded", "fast");

// Store state-specific data
fsm.AddState(PlayerState.Attacking)
    .SetData("damage", 10)
    .SetData("attackSpeed", 1.5f);

// Query later
if (fsm.IsInStateWithTag("movement"))
{
    // Player is moving
}

var state = fsm.GetState(PlayerState.Attacking);
if (state.TryGetData<int>("damage", out var dmg))
{
    ApplyDamage(dmg);
}
```

---

## Transitions

### Condition-Based Transitions

```csharp
// Basic condition
fsm.AddTransition(PlayerState.Idle, PlayerState.Walking)
    .SetCondition(fsm => Input.IsActionPressed("move"));

// Complex condition with state machine access
fsm.AddTransition(PlayerState.Walking, PlayerState.Running)
    .SetCondition(fsm => {
        bool sprintPressed = Input.IsActionPressed("sprint");
        bool hasStamina = fsm.TryGetData("stamina", out float s) && s > 10;
        return sprintPressed && hasStamina;
    });
```

### Guard vs Condition

**Guards** are checked FIRST and should be used for quick pre-validation:
```csharp
fsm.AddTransition(PlayerState.Idle, PlayerState.Jumping)
    .SetGuard(fsm => IsOnGround()) // Fast pre-check
    .SetCondition(fsm => Input.IsActionJustPressed("jump")); // Actual trigger
```

**Think of it as:**
- **Guard**: "Can this transition even be considered?"
- **Condition**: "Should this transition happen now?"

### Event-Based Transitions

```csharp
// Transition triggers when "jump" event is sent
fsm.AddTransition(PlayerState.Idle, PlayerState.Jumping)
    .OnEvent("jump")
    .SetGuard(fsm => IsOnGround());

// Elsewhere in your code:
if (Input.IsActionJustPressed("jump"))
{
    fsm.SendEvent("jump");
}
```

### Priority-Based Transitions

```csharp
// Higher priority transitions are checked first
fsm.AddTransition(PlayerState.Any, PlayerState.Death)
    .SetMaxPriority() // Checked before everything else
    .SetCondition(fsm => health <= 0);

fsm.AddTransition(PlayerState.Idle, PlayerState.Talking)
    .SetPriority(100) // High priority
    .SetCondition(fsm => npcNearby);

fsm.AddTransition(PlayerState.Idle, PlayerState.Walking)
    .SetPriority(1) // Low priority (default is 0)
    .SetCondition(fsm => Input.IsActionPressed("move"));
```

### Global Transitions

```csharp
// Can trigger from ANY state
fsm.AddGlobalTransition(PlayerState.Death)
    .SetCondition(fsm => health <= 0);

fsm.AddGlobalTransition(PlayerState.Paused)
    .OnEvent("pause");
```

### Instant Transitions

```csharp
// Ignores MinTime requirements
fsm.AddTransition(PlayerState.Running, PlayerState.Falling)
    .ForceInstant()
    .SetCondition(fsm => !IsOnGround());
```

### Transition Callbacks

```csharp
fsm.AddTransition(PlayerState.Idle, PlayerState.Attacking)
    .SetCondition(fsm => Input.IsActionJustPressed("attack"))
    .OnTrigger(() => {
        GD.Print("Attack initiated!");
        PlayAttackSound();
    });
```

---

## Events

### Sending and Listening

```csharp
// Register event listener
fsm.OnEvent("player_damaged", () => {
    GD.Print("Player took damage!");
    FlashScreen();
});

// Send event
public void TakeDamage(int amount)
{
    health -= amount;
    fsm.SendEvent("player_damaged");
}

// Events are queued and processed during the next Process() call
```

### Event-Based Transitions

```csharp
fsm.AddState(PlayerState.Idle);
fsm.AddState(PlayerState.Attacking);

fsm.AddTransition(PlayerState.Idle, PlayerState.Attacking)
    .OnEvent("attack_input")
    .SetGuard(fsm => !isStunned);

// In your input handler:
if (Input.IsActionJustPressed("attack"))
{
    fsm.SendEvent("attack_input");
}
```

### Event Reentrancy

Events sent during event processing are automatically handled:

```csharp
fsm.OnEvent("combo_1", () => {
    GD.Print("First attack!");
    fsm.SendEvent("combo_2"); // This will also process
});

fsm.OnEvent("combo_2", () => {
    GD.Print("Second attack!");
});

fsm.SendEvent("combo_1");
// Output: "First attack!" then "Second attack!"
```

---

## Advanced Features

### Per-Transition Data Passing

```csharp
// Store data during transition
fsm.TryChangeState(PlayerState.Damaged, data: new DamageInfo {
    Amount = 50,
    Source = "Enemy",
    DamageType = "Fire"
});

// Retrieve in Enter callback
fsm.AddState(PlayerState.Damaged)
    .OnEnter(() => {
        var damageInfo = fsm.GetPerTransitionData<DamageInfo>();
        if (damageInfo != null)
        {
            health -= damageInfo.Amount;
            GD.Print($"Took {damageInfo.Amount} {damageInfo.DamageType} damage!");
        }
    });
```

### Global Data Storage

```csharp
// Store persistent data across states
fsm.SetData("combo_count", 0);
fsm.SetData("last_attack_time", Time.GetTicksMsec());

// Retrieve anywhere
if (fsm.TryGetData("combo_count", out int count))
{
    GD.Print($"Current combo: {count}");
}
```

### State History

```csharp
// Check previous state
if (fsm.IsPreviousState(PlayerState.Running))
{
    // Player was running before current state
    PlayStopRunningAnimation();
}

// Go back to previous state
if (Input.IsActionJustPressed("cancel"))
{
    fsm.TryGoBack();
}
```

### State Machine Introspection

```csharp
// Current state info
GD.Print($"Current: {fsm.GetCurrentId()}");
GD.Print($"Time in state: {fsm.GetStateTime()}");
GD.Print($"Min time met: {fsm.MintimeExceeded()}");

// State queries
var state = fsm.GetState(PlayerState.Running);
if (state != null && state.TryGetData<float>("speed", out var speed))
{
    GD.Print($"Running speed: {speed}");
}

// Find by tag
var movementStates = fsm.GetStatesWithTag("movement");
foreach (var state in movementStates)
{
    GD.Print($"Movement state: {state.Id}");
}

// Check transitions
if (fsm.HasTransition(PlayerState.Idle, PlayerState.Walking))
{
    GD.Print("Can walk from idle");
}
```

### Pausing

```csharp
// Pause/resume
fsm.Pause();
// ... game paused ...
fsm.Resume();

// Toggle
fsm.TogglePaused(isPaused);

// Check state
if (fsm.IsActive())
{
    // State machine is running
}
```

---

## Best Practices

### 1. Use Enums for State IDs
```csharp
// ✅ Good: Type-safe, autocomplete, refactor-friendly
public enum PlayerState { Idle, Walking, Running }
var fsm = new StateMachine<PlayerState>();

// ❌ Bad: Strings are error-prone
// Don't use StateMachine<string>
```

### 2. Separate Concerns
```csharp
// ✅ Good: FSM handles state logic, node handles visuals
fsm.AddState(PlayerState.Running)
    .OnEnter(() => OnRunStart())
    .OnExit(() => OnRunEnd());

private void OnRunStart()
{
    animPlayer.Play("run");
    dustParticles.Emitting = true;
}

// ❌ Bad: Don't mix FSM with rendering directly
```

### 3. Keep Conditions Simple
```csharp
// ✅ Good: Simple, readable conditions
fsm.AddTransition(PlayerState.Idle, PlayerState.Walking)
    .SetCondition(fsm => IsMoving());

private bool IsMoving() => Input.GetVector("left", "right", "up", "down").Length() > 0.1f;

// ❌ Bad: Complex logic inline
fsm.AddTransition(PlayerState.Idle, PlayerState.Walking)
    .SetCondition(fsm => {
        var input = Input.GetVector(...);
        var normalized = input.Normalized();
        var magnitude = input.Length();
        return magnitude > 0.1f && !isStunned && stamina > 0;
    });
```

### 4. Use Guards for Performance
```csharp
// ✅ Good: Guard prevents expensive checks
fsm.AddTransition(PlayerState.Idle, PlayerState.Attacking)
    .SetGuard(fsm => CanAttack()) // Cheap check
    .SetCondition(fsm => FindNearestEnemy() != null); // Expensive check

// Guard fails fast, expensive check never runs
```

### 5. Dispose Properly
```csharp
public partial class Player : CharacterBody2D
{
    private StateMachine<PlayerState> fsm;

    public override void _Ready()
    {
        fsm = new StateMachine<PlayerState>();
        // ... setup ...
    }

    public override void _ExitTree()
    {
        fsm?.Dispose(); // ✅ Clean up event listeners
    }
}
```

### 6. Use Events for Decoupling
```csharp
// ✅ Good: UI and FSM are decoupled
fsm.OnEvent("state_changed", () => UpdateUI());

// ❌ Bad: FSM directly manipulates UI
// fsm.AddState(...).OnEnter(() => uiLabel.Text = "Idle");
```

### 7. Avoid Deep Nesting
```csharp
// ✅ Good: Flat state structure
enum GameState { MainMenu, Playing, Paused, GameOver }

// ❌ Bad: Don't create sub-FSMs unless necessary
// Hierarchical FSMs are complex and usually overkill
```

---

## Complete Examples

### Example 1: Character Controller

```csharp
public partial class Player : CharacterBody2D
{
    public enum State { Idle, Walking, Running, Jumping, Falling, Landing }
    
    private StateMachine<State> fsm;
    private float speed = 300f;
    private float runSpeed = 500f;
    private float jumpVelocity = -600f;
    
    public override void _Ready()
    {
        fsm = new StateMachine<State>();
        SetupStateMachine();
        fsm.Start();
    }
    
    private void SetupStateMachine()
    {
        // Idle State
        fsm.AddState(State.Idle)
            .OnEnter(() => GetNode<AnimationPlayer>("AnimationPlayer").Play("idle"))
            .AddTags("grounded");
        
        // Walking State
        fsm.AddState(State.Walking)
            .OnUpdate((delta) => Move(speed, delta))
            .OnEnter(() => GetNode<AnimationPlayer>("AnimationPlayer").Play("walk"))
            .AddTags("grounded", "moving");
        
        // Running State
        fsm.AddState(State.Running)
            .OnUpdate((delta) => Move(runSpeed, delta))
            .OnEnter(() => GetNode<AnimationPlayer>("AnimationPlayer").Play("run"))
            .AddTags("grounded", "moving");
        
        // Jumping State
        fsm.AddState(State.Jumping)
            .SetProcessMode(FSMProcessMode.Fixed)
            .OnEnter(() => {
                Velocity = new Vector2(Velocity.X, jumpVelocity);
                GetNode<AnimationPlayer>("AnimationPlayer").Play("jump");
            })
            .OnUpdate((delta) => ApplyGravity(delta))
            .AddTags("airborne");
        
        // Falling State
        fsm.AddState(State.Falling)
            .SetProcessMode(FSMProcessMode.Fixed)
            .OnUpdate((delta) => ApplyGravity(delta))
            .OnEnter(() => GetNode<AnimationPlayer>("AnimationPlayer").Play("fall"))
            .AddTags("airborne");
        
        // Landing State
        fsm.AddState(State.Landing)
            .SetMinTime(0.2f)
            .SetTimeout(0.2f)
            .SetTimeoutId(State.Idle)
            .OnEnter(() => GetNode<AnimationPlayer>("AnimationPlayer").Play("land"))
            .AddTags("grounded");
        
        // Transitions
        fsm.AddTransition(State.Idle, State.Walking)
            .SetCondition(fsm => GetMovementInput().Length() > 0.1f);
        
        fsm.AddTransition(State.Walking, State.Idle)
            .SetCondition(fsm => GetMovementInput().Length() < 0.1f);
        
        fsm.AddTransition(State.Walking, State.Running)
            .SetCondition(fsm => Input.IsActionPressed("sprint"));
        
        fsm.AddTransition(State.Running, State.Walking)
            .SetCondition(fsm => !Input.IsActionPressed("sprint"));
        
        fsm.AddTransition(State.Idle, State.Jumping)
            .OnEvent("jump")
            .SetGuard(fsm => IsOnFloor());
        
        fsm.AddTransition(State.Walking, State.Jumping)
            .OnEvent("jump")
            .SetGuard(fsm => IsOnFloor());
        
        fsm.AddTransition(State.Running, State.Jumping)
            .OnEvent("jump")
            .SetGuard(fsm => IsOnFloor());
        
        // Fall when leaving ground
        fsm.AddGlobalTransition(State.Falling)
            .SetGuard(fsm => fsm.IsInStateWithTag("grounded"))
            .SetCondition(fsm => !IsOnFloor())
            .ForceInstant();
        
        // Land when touching ground
        fsm.AddTransition(State.Falling, State.Landing)
            .SetCondition(fsm => IsOnFloor());
        
        fsm.AddTransition(State.Jumping, State.Falling)
            .SetCondition(fsm => Velocity.Y > 0);
    }
    
    public override void _Process(double delta)
    {
        fsm.Process(FSMProcessMode.Idle, (float)delta);
    }
    
    public override void _PhysicsProcess(double delta)
    {
        fsm.Process(FSMProcessMode.Fixed, (float)delta);
        MoveAndSlide();
    }
    
    public override void _Input(InputEvent @event)
    {
        if (@event.IsActionPressed("jump"))
            fsm.SendEvent("jump");
    }
    
    private Vector2 GetMovementInput()
    {
        return Input.GetVector("move_left", "move_right", "move_up", "move_down");
    }
    
    private void Move(float moveSpeed, float delta)
    {
        var input = GetMovementInput();
        Velocity = new Vector2(input.X * moveSpeed, Velocity.Y);
    }
    
    private void ApplyGravity(float delta)
    {
        Velocity += GetGravity() * delta;
    }
    
    public override void _ExitTree()
    {
        fsm?.Dispose();
    }
}
```

### Example 2: Enemy AI

```csharp
public partial class Enemy : CharacterBody2D
{
    public enum AIState { Idle, Patrol, Chase, Attack, Retreat, Death }
    
    private StateMachine<AIState> fsm;
    private Node2D player;
    private float detectionRange = 300f;
    private float attackRange = 50f;
    private float health = 100f;
    
    public override void _Ready()
    {
        fsm = new StateMachine<AIState>();
        player = GetTree().Root.GetNode<Node2D>("Player");
        SetupAI();
        fsm.Start();
    }
    
    private void SetupAI()
    {
        // Idle - Wait and look around
        fsm.AddState(AIState.Idle)
            .SetTimeout(3.0f)
            .SetTimeoutId(AIState.Patrol)
            .OnEnter(() => Velocity = Vector2.Zero);
        
        // Patrol - Move between waypoints
        fsm.AddState(AIState.Patrol)
            .OnEnter(() => ChooseNextWaypoint())
            .OnUpdate((delta) => MoveToWaypoint(delta));
        
        // Chase - Pursue player
        fsm.AddState(AIState.Chase)
            .OnUpdate((delta) => ChasePlayer(delta))
            .OnEnter(() => PlaySound("alert"));
        
        // Attack - Damage player
        fsm.AddState(AIState.Attack)
            .Lock(FSMLockMode.Full)
            .SetTimeout(0.5f)
            .SetTimeoutId(AIState.Chase)
            .OnEnter(() => ExecuteAttack())
            .OnTimeout(() => GetNode<AnimationPlayer>("AnimationPlayer").Play("RESET"));
        
        // Retreat - Run away when low health
        fsm.AddState(AIState.Retreat)
            .OnUpdate((delta) => FleeFromPlayer(delta))
            .SetData("retreatSpeed", 400f);
        
        // Death
        fsm.AddState(AIState.Death)
            .Lock(FSMLockMode.Full)
            .OnEnter(() => Die());
        
        // Death is highest priority - checked first
        fsm.AddGlobalTransition(AIState.Death)
            .SetMaxPriority()
            .SetCondition(fsm => health <= 0);
        
        // Retreat when health is low
        fsm.AddGlobalTransition(AIState.Retreat)
            .SetPriority(100)
            .SetCondition(fsm => health < 30f && health > 0);
        
        // Start chasing when player is nearby
        fsm.AddTransition(AIState.Idle, AIState.Chase)
            .SetCondition(fsm => DistanceToPlayer() < detectionRange);
        
        fsm.AddTransition(AIState.Patrol, AIState.Chase)
            .SetCondition(fsm => DistanceToPlayer() < detectionRange);
        
        // Attack when close enough
        fsm.AddTransition(AIState.Chase, AIState.Attack)
            .SetCondition(fsm => DistanceToPlayer() < attackRange);
        
        // Return to patrol when player is far
        fsm.AddTransition(AIState.Chase, AIState.Patrol)
            .SetCondition(fsm => DistanceToPlayer() > detectionRange * 1.5f);
        
        // Stop retreating when health is restored
        fsm.AddTransition(AIState.Retreat, AIState.Idle)
            .SetCondition(fsm => health >= 50f);
    }
    
    public override void _PhysicsProcess(double delta)
    {
        fsm.Process(FSMProcessMode.Fixed, (float)delta);
        MoveAndSlide();
    }
    
    private float DistanceToPlayer()
    {
        return GlobalPosition.DistanceTo(player.GlobalPosition);
    }
    
    private void ChasePlayer(float delta)
    {
        var direction = (player.GlobalPosition - GlobalPosition).Normalized();
        Velocity = direction * 200f;
    }
    
    private void FleeFromPlayer(float delta)
    {
        var direction = (GlobalPosition - player.GlobalPosition).Normalized();
        Velocity = direction * 400f;
    }
    
    private void ExecuteAttack()
    {
        GetNode<AnimationPlayer>("AnimationPlayer").Play("attack");
        // Deal damage to player
        if (DistanceToPlayer() < attackRange)
        {
            // player.TakeDamage(10);
        }
    }
    
    private void Die()
    {
        GetNode<AnimationPlayer>("AnimationPlayer").Play("death");
        CollisionLayer = 0; // Disable collision
        
        // Remove after animation
        GetTree().CreateTimer(2.0f).Timeout += () => QueueFree();
    }
    
    public void TakeDamage(float amount)
    {
        health -= amount;
        fsm.SendEvent("damaged");
    }
    
    private void ChooseNextWaypoint()
    {
        // Waypoint logic...
    }
    
    private void MoveToWaypoint(float delta)
    {
        // Movement logic...
    }
    
    private void PlaySound(string soundName)
    {
        // Audio logic...
    }
    
    public override void _ExitTree()
    {
        fsm?.Dispose();
    }
}
```

---

## Troubleshooting

### State Machine Not Updating
```csharp
// ✅ Make sure you're calling Process()
public override void _Process(double delta)
{
    fsm.Process(FSMProcessMode.Idle, (float)delta);
}

// ✅ Check if machine is paused
if (!fsm.IsActive())
{
    fsm.Resume();
}

// ✅ Verify Start() was called
fsm.Start();
```

### Transitions Not Firing
```csharp
// ✅ Check MinTime requirements
GD.Print($"Min time exceeded: {fsm.MintimeExceeded()}");

// ✅ Verify state isn't locked
var state = fsm.GetState(fsm.GetCurrentId());
GD.Print($"Is locked: {state.IsLocked()}");

// ✅ Debug your conditions
fsm.AddTransition(State.A, State.B)
    .SetCondition(fsm => {
        bool result = MyCondition();
        GD.Print($"Transition condition: {result}");
        return result;
    });
```

### Events Not Processing
```csharp
// ✅ Events are queued and process on next Process() call
fsm.SendEvent("my_event");
fsm.Process(FSMProcessMode.Idle, delta); // Event processes here

// ✅ Check event listeners are registered
fsm.OnEvent("my_event", () => GD.Print("Event fired!"));
```

---

## Performance Tips

1. **Use Guards**: Guards fail fast and prevent expensive condition checks
2. **Limit Transitions**: Don't create hundreds of transitions from one state
3. **Cache Calculations**: Don't recalculate in conditions every frame
4. **Use Tags**: More efficient than checking state IDs individually
5. **Profile**: Use Godot's profiler to identify bottlenecks

---

## API Reference Summary

### StateMachine Methods
- `AddState(T)` - Create a new state
- `Start()` - Begin state machine
- `Process(mode, delta)` - Update per frame
- `AddTransition(from, to)` - Create transition
- `AddGlobalTransition(to)` - Create from-any transition
- `SendEvent(name)` - Queue an event
- `OnEvent(name, callback)` - Listen for event
- `SetData(key, value)` - Store global data
- `TryGetData<T>(key, out value)` - Retrieve global data
- `GetCurrentId()` - Get current state ID
- `Pause()/Resume()` - Control execution
- `Dispose()` - Clean up resources

### State Methods (Fluent)
- `.OnEnter(callback)` - Set enter callback
- `.OnUpdate(callback)` - Set update callback
- `.OnExit(callback)` - Set exit callback
- `.SetTimeout(seconds)` - Auto-transition after time
- `.SetMinTime(seconds)` - Minimum state duration
- `.Lock(mode)` - Prevent transitions
- `.AddTags(tags...)` - Add query tags
- `.SetData(key, value)` - Store state data
- `.SetProcessMode(mode)` - Idle or Fixed update

### Transition Methods (Fluent)
- `.SetCondition(predicate)` - Trigger condition
- `.SetGuard(predicate)` - Pre-check condition
- `.OnEvent(name)` - Trigger on event
- `.SetPriority(int)` - Evaluation order
- `.ForceInstant()` - Ignore MinTime
- `.OnTrigger(callback)` - Callback when triggered
- `.SetMinTime(seconds)` - Override state MinTime

---

**You now have a bulletproof, production-ready FSM! 🎉**
