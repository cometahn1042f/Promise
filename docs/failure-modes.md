# Promise Failure Modes & Exception Guarantees

## Unhandled Rejection Detection
If a promise is rejected and no `:catch()` or rejection handler is attached within the micro-task frame, Promise defers an unhandled rejection warning via `warn()` or forwards it to `Promise.onUnhandledRejection`.

## Resolver Exception Catching
If the resolver function passed to `Promise.new` throws a Lua runtime error, the error is caught automatically and converts the promise to `REJECTED` status with the error as the rejection reason.
