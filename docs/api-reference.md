# Promise API Reference

## Promise Constructors & Static Methods

### `Promise.new(resolver: (resolve: (...any) -> (), reject: (...any) -> (), onCancel: (() -> ()) -> ()) -> (), label: string?): Promise`
Creates a new pending Promise.

### `Promise.resolve(value: any, label: string?): Promise`
Returns a promise fulfilled with `value`. If `value` is already a Promise, returns `value`.

### `Promise.reject(reason: any, label: string?): Promise`
Returns a promise rejected with `reason`.

### `Promise.defer(label: string?): Deferred`
Returns a `{ promise = Promise, resolve = function, reject = function }` tuple object.

### `Promise.delay(seconds: number): Promise`
Returns a promise that resolves with the elapsed time after `seconds`. Supports cancellation.

### `Promise.try(callback: (...any) -> ...any, ...: any): Promise`
Executes `callback(...)` inside an `xpcall` and returns a promise resolving with the returned value or rejecting with the caught error.

### `Promise.promisify(fn: (...any) -> ...any): (...any) -> Promise`
Wraps a standard yielding or erroring function `fn` into a function returning a Promise.

### `Promise.fromEvent(event: RBXScriptSignal | any, predicate: ((...any) -> boolean)?): Promise`
Returns a promise that resolves when `event` fires (and satisfies optional `predicate`).

### `Promise.retry(callback: (...any) -> Promise, times: number, ...: any): Promise`
Retries an asynchronous task `callback` up to `times` attempts upon rejection.

### `Promise.retryWithDelay(callback: (...any) -> Promise, times: number, seconds: number, ...: any): Promise`
Retries `callback` up to `times` attempts, waiting `seconds` between attempts.

---

## Combinator Static Methods

### `Promise.all(entries: { unknown }, label: string?): Promise`
Resolves when all promises in `entries` fulfill, returning an array of results. Rejects immediately if any promise rejects.

### `Promise.race(entries: { unknown }, label: string?): Promise`
Resolves or rejects as soon as the first promise in `entries` settles.

### `Promise.allSettled(entries: { unknown }, label: string?): Promise`
Resolves when all promises settle, returning an array of `{ state = "fulfilled"|"rejected", value/reason = ... }`.

### `Promise.hash(object: { [any]: unknown }, label: string?): Promise`
Similar to `Promise.all`, but accepts a dictionary map of promises and resolves with a matching key-value map.

### `Promise.hashSettled(object: { [any]: unknown }, label: string?): Promise`
Similar to `Promise.allSettled`, but for key-value dictionary maps.

### `Promise.map(promises: { unknown }, mapFn: (value: unknown, index: number) -> unknown, label: string?): Promise`
Maps over an array of promises or values, applying `mapFn` to each resolved result.

---

## Instance Methods

### `Promise:andThen(onFulfillment: ((any) -> any)?, onRejection: ((any) -> any)?, label: string?): Promise`
Chains fulfillment/rejection handlers.

### `Promise:catch(onRejection: (any) -> any, label: string?): Promise`
Chains a rejection handler.

### `Promise:finally(callback: () -> any, label: string?): Promise`
Executes `callback` regardless of settlement status without altering resolved values.

### `Promise:timeout(seconds: number, message: string?): Promise`
Races the promise against a timer. Rejects with `Error.Kind.TimedOut` if not resolved within `seconds`.

### `Promise:cancel()`
Cancels the promise and decrements parent consumer counts.

### `Promise:await(): (boolean, ...any)`
Yields the calling thread until settled. Returns `(true, ...values)` on success or `(false, reason)` on rejection.

### `Promise:expect(): ...any`
Yields the calling thread. Returns values on fulfillment or throws a Lua runtime error on rejection.
