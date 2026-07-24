# Promise

Promise is a feature-complete asynchronous promise library written in strict Luau, supporting cancellation propagation, consumer tracking, and unhandled rejection detection.

## Documentation Index

- [API Reference](file:///c:/Lua/Libraries/Promise/docs/api-reference.md): Promise construction, combinators, and chaining.
- [Architecture & Design](file:///c:/Lua/Libraries/Promise/docs/architecture-and-design.md): State transitions and consumer reference counting.
- [Performance & Memory Profile](file:///c:/Lua/Libraries/Promise/docs/performance-and-memory.md): Asynchronous scheduling with task.defer.
- [Failure Modes & Exception Guarantees](file:///c:/Lua/Libraries/Promise/docs/failure-modes.md): Unhandled rejection warnings and cancellation rules.
- [Executable Examples](file:///c:/Lua/Libraries/Promise/docs/examples.md): Async operations, chaining, and error handling patterns.

## Quick Start

```luau
local Promise = require(path.to.Promise)

local function fetchData(): Promise
    return Promise.new(function(resolve, reject)
        task.wait(1)
        resolve("Payload")
    end)
end

fetchData():andThen(function(data)
    print("Received:", data)
----------------------------------------
end):catch(function(err)
    warn("Error:", err)
end)
```
