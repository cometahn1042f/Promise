# Promise Architecture & Design

## Finite State Machine

A Promise exists in one of three deterministic states:

```
          ┌─────────────┐
          │   PENDING   │
          └──────┬──────┘
                 │
        ┌────────┴────────┐
        ▼                 ▼
  ┌───────────┐     ┌───────────┐
  │ FULFILLED │     │ REJECTED  │
  └───────────┘     └───────────┘
```

## Consumer Reference Counting & Cancellation
When `:andThen()` is called, the child promise increments its parent's `_consumers` count.
Calling `:cancel()` decrements `_consumers`. If `_consumers` reaches `0`, the cancellation signal propagates up to parent promises recursively.
