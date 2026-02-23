# Stately

A small, practical state machine for Unity. No fluff, no editor windows, no ScriptableObjects — just a clean API you set up in code and forget about.

---

## Installation

Open Unity Package Manager -> press on "+" button -> download from git URL -> paste git link

---

## Quick Start

```csharp
using Stately;

private enum PlayerState { Idle, Run, Jump, Attack }

public class PlayerController : MonoBehaviour
{
    private SimpleStateMachine<PlayerState> fsm = new SimpleStateMachine<PlayerState>();

    void Start()
    {
        fsm.AddState(PlayerState.Idle)
            .OnEnter(() => PlayAnimation("idle"))
            .OnUpdate(dt => { /* idle logic */ });

        fsm.AddState(PlayerState.Run)
            .OnEnter(() => PlayAnimation("run"))
            .MinDuration(0.1f);

        fsm.AddState(PlayerState.Jump)
            .OnEnter(() => rb.AddForce(Vector3.up * jumpForce))
            .OnExit(() => isJumping = false)
            .TimeoutAfter(1.2f, PlayerState.Idle);

        fsm.AddState(PlayerState.Attack)
            .OnEnter(() => PlayAnimation("attack"))
            .MinDuration(0.3f);

        fsm.AddTransition(PlayerState.Idle, PlayerState.Run)
            .When(() => moveInput.magnitude > 0.1f);

        fsm.AddTransition(PlayerState.Run, PlayerState.Idle)
            .When(() => moveInput.magnitude < 0.1f);

        fsm.AddTransition(PlayerState.Idle, PlayerState.Jump)
            .OnEvent("jump");

        fsm.AddTransition(PlayerState.Run, PlayerState.Jump)
            .OnEvent("jump");

        fsm.SetInitialState(PlayerState.Idle);
        fsm.Start();
    }

    void Update()
    {
        if (Input.GetKeyDown(KeyCode.Space))
            fsm.TriggerEvent("jump");

        fsm.UpdateStates(Time.deltaTime);
    }
}
```

---

## States

```csharp
fsm.AddState(MyState.Patrol)
    .OnEnter(() => { })           // called when entering
    .OnUpdate(dt => { })          // called every frame
    .OnExit(() => { })            // called when leaving
    .MinDuration(0.5f)            // must stay at least 0.5s before any transition
    .TimeoutAfter(3f, MyState.Idle)   // auto-transition after 3s
    .OnTimeout(() => { });        // called just before timeout transition fires
```

---

## Transitions

```csharp
fsm.AddTransition(MyState.Idle, MyState.Alert)
    .When(() => enemyVisible)           // condition — transition fires when true
    .IfOnly(() => isAlive)              // guard — if false, skip this transition entirely
    .Do(() => NotifyNearbyAllies())     // callback when transition fires
    .MinDuration(0.2f)                  // override min time for this transition only
    .SetPriority(10)                    // higher priority checked first
    .ForceInstant();                    // ignore state min duration
```

**Global transitions** fire from any state:

```csharp
fsm.AddGlobalTransition(MyState.Dead)
    .When(() => health <= 0)
    .IfOnly(() => !isInvincible);
```

---

## Events

Good for input or anything that happens once rather than being checked every frame.

```csharp
// trigger from anywhere
fsm.TriggerEvent("roll");

// or with an enum
fsm.TriggerEvent(InputEvent.Roll);

// listen globally
fsm.OnEvent("roll", () => Debug.Log("roll triggered"));

// or wire directly to a transition
fsm.AddTransition(MyState.Idle, MyState.Roll)
    .OnEvent("roll")
    .IfOnly(() => !isExhausted);
```

---

## Manual Control

```csharp
fsm.TryTransitionTo(MyState.Stun);      // respects lock and min time
fsm.ForceTransitionTo(MyState.Stun);    // ignores lock, forces immediately
fsm.CanTransitionTo(MyState.Run);       // check before attempting

fsm.Lock();     // block all automatic and manual transitions
fsm.Unlock();

fsm.Pause();    // freeze update entirely
fsm.Resume();

fsm.Reset();    // return to initial state
```

---

## Queries

```csharp
fsm.CurrentStateId          // current state enum value
fsm.PreviousId              // previous state
fsm.StateTime               // seconds spent in current state
fsm.HasPreviousState        // false on first state

fsm.IsCurrentState(MyState.Idle)
fsm.GetRemainingTime()      // seconds until timeout, -1 if no timeout set
```

---

## Events (C#)

```csharp
fsm.StateChanged += (from, to) => Debug.Log($"{from} -> {to}");
fsm.StateTimeout += (state) => Debug.Log($"{state} timed out");
```

---

## Priority & Order

When multiple transitions are valid at the same time, higher priority wins. Ties are broken by insertion order — whichever was added first.

```csharp
fsm.AddTransition(MyState.Idle, MyState.Alert).SetPriority(5);
fsm.AddTransition(MyState.Idle, MyState.Run).SetPriority(1);
// Alert transition is checked first
```

---

## Guard vs Condition

These two look similar but serve different purposes:

- **Guard** (`IfOnly`) — pre-check. If false, the transition is skipped entirely, no condition evaluated.
- **Condition** (`When`) — the actual trigger. Fires the transition when true.

```csharp
fsm.AddTransition(MyState.Idle, MyState.Attack)
    .IfOnly(() => weapon.IsEquipped)    // skip entirely if unarmed
    .When(() => attackInput);           // fire when input received
```

---
