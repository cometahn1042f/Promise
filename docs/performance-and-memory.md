# Promise Performance & Memory Profile

## Execution Scheduling
All callback invocations (`onFulfillment`, `onRejection`) are dispatched asynchronously using `task.defer`. This prevents stack overflow caused by synchronous chaining and ensures consistent async execution.

## Memory Profile
A Promise object retains its internal subscriber array until settled. Upon settlement, the subscriber list is cleared (`_subscribers = nil`) to free references.
