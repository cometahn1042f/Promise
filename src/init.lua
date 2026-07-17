--!strict
local internal = require(script.internal)
local Error = require(script.Error)

export type Promise = internal.Promise

local Promise = {}
Promise.__index = Promise

internal.Promise = Promise
Promise.Error = Error

local idCounter = 0

export type Deferred = {
	promise: Promise,
	resolve: (value: unknown) -> (),
	reject: (reason: unknown) -> (),
}

local unhandledRejectionCallback: ((Promise, unknown) -> ())? = nil

local function warnUnhandledRejection(promise: Promise, reason: unknown)
	if promise._onError then
		if unhandledRejectionCallback then
			unhandledRejectionCallback(promise, reason)
		else
			warn(string.format("Unhandled Promise Rejection:\n%s", tostring(reason)))
		end
	end
end

local function defaultOnError(promise: Promise, reason: unknown)
	task.defer(warnUnhandledRejection, promise, reason)
end

function Promise.new(resolver: ((unknown) -> (), (unknown) -> (), (() -> ()) -> ()) -> (), label: string?): Promise
	local self = setmetatable({
		_id = idCounter,
		_state = internal.PENDING,
		_result = nil :: unknown,
		_subscribers = nil :: { unknown }?,
		_cancellationHooks = nil :: { () -> () }?,
		_parent = nil :: Promise?,
		_consumers = 0,
		_onError = defaultOnError,
		_label = label,
	}, Promise)

	idCounter += 1

	if resolver ~= internal.noop then
		if type(resolver) ~= "function" then
			error("You must pass a resolver function as the first argument to the promise constructor", 2)
		end
		internal.initializePromise(self :: any, resolver)
	end

	return (self :: any) :: Promise
end

function Promise:andThen(
	onFulfillment: ((unknown) -> unknown)?,
	onRejection: ((unknown) -> unknown)?,
	label: string?
): Promise
	local parent = (self :: any) :: Promise
	local state = parent._state

	if (state == internal.FULFILLED and not onFulfillment) or (state == internal.REJECTED and not onRejection) then
		return parent
	end

	parent._onError = nil

	local child = Promise.new(internal.noop, label)

	child._parent = parent
	parent._consumers += 1

	if state == internal.PENDING then
		internal.subscribe(parent, child, onFulfillment, onRejection)
	else
		local callback = state == internal.FULFILLED and onFulfillment or onRejection
		task.defer(internal.invokeCallback, state, child, callback, parent)
	end

	return child
end

function Promise:catch(onRejection: (unknown) -> unknown, label: string?): Promise
	return self:andThen(nil, onRejection, label)
end

function Promise:finally(callback: () -> unknown, label: string?): Promise
	local constructor = getmetatable(self :: any)

	if type(callback) == "function" then
		local child = self:andThen(function(value)
			return constructor.resolve(callback()):andThen(function()
				return value
			end)
		end, function(reason)
			return constructor.resolve(callback()):andThen(function()
				error(reason)
			end)
		end, label)

		if not child._cancellationHooks then
			child._cancellationHooks = {}
		end
		table.insert(child._cancellationHooks, function()
			task.spawn(callback)
		end)

		return child
	end

	return self:andThen(callback :: any, callback :: any, label)
end

internal.originalThen = Promise.andThen

function Promise.resolve(value: unknown, label: string?): Promise
	if type(value) == "table" and getmetatable(value :: any) == Promise then
		return (value :: any) :: Promise
	end

	local promise = Promise.new(internal.noop, label)
	internal.resolve(promise, value)
	return promise
end

internal.originalResolve = Promise.resolve

function Promise.reject(reason: unknown, label: string?): Promise
	local promise = Promise.new(internal.noop, label)
	internal.reject(promise, reason)
	return promise
end

function Promise.defer(label: string?): Deferred
	local deferred = {} :: any
	deferred.promise = Promise.new(function(resolve, reject)
		deferred.resolve = resolve
		deferred.reject = reject
	end, label)
	return deferred
end

function Promise.rethrow(reason: unknown)
	task.defer(function()
		error(reason)
	end)
	error(reason)
end

function Promise.on(_eventName: string, _callback: (unknown) -> ())
	-- Placeholder for instrumentation
end

function Promise.off(_eventName: string, _callback: (unknown) -> ())
	-- Placeholder for instrumentation
end

function Promise.onUnhandledRejection(callback: (Promise, unknown) -> ())
	unhandledRejectionCallback = callback
end

function Promise:cancel()
	if (self :: any)._state ~= internal.PENDING then
		return
	end

	local hooks = (self :: any)._cancellationHooks
	if hooks then
		for _, hook in ipairs(hooks) do
			task.spawn(hook :: () -> ())
		end
		(self :: any)._cancellationHooks = nil
	end

	internal.cancel(self :: any)

	if (self :: any)._parent then
		(self :: any)._parent._consumers -= 1
		if (self :: any)._parent._consumers == 0 then
			(self :: any)._parent:cancel()
		end
	end
end

function Promise:await(): (boolean, ...unknown)
	local status = (self :: any)._state
	if status == internal.FULFILLED then
		if (self :: any)._valuesLength then
			return true, unpack((self :: any)._values :: { any }, 1, (self :: any)._valuesLength)
		else
			return true, (self :: any)._result
		end
	elseif status == internal.REJECTED then
		if (self :: any)._valuesLength then
			return false, unpack((self :: any)._values :: { any }, 1, (self :: any)._valuesLength)
		else
			return false, (self :: any)._result
		end
	elseif status == internal.CANCELLED then
		return false, Error.new({ kind = Error.Kind.AlreadyCancelled, error = "Promise was cancelled" })
	end

	local currentThread = coroutine.running()
	local success: boolean = false
	local results: { any }? = nil
	local resultsLength = 0
	local isCancelled = false

	local child = self:andThen(function(...)
		success = true
		resultsLength = select("#", ...)
		results = { ... }
		task.spawn(currentThread)
	end, function(...)
		success = false
		resultsLength = select("#", ...)
		results = { ... }
		task.spawn(currentThread)
	end)

	if not child._cancellationHooks then
		child._cancellationHooks = {}
	end
	table.insert(child._cancellationHooks, function()
		isCancelled = true
		task.spawn(currentThread)
	end)

	coroutine.yield()
	if isCancelled then
		return false, Error.new({ kind = Error.Kind.AlreadyCancelled, error = "Promise was cancelled" })
	end
	return success, unpack(results :: { any }, 1, resultsLength)
end

function Promise:expect(): ...unknown
	local results = table.pack(self:await())
	local success = results[1]
	if not success then
		error(results[2], 2)
	end
	return unpack(results, 2, results.n)
end

function Promise.delay(seconds: number): Promise
	return Promise.new(function(resolve, _reject, onCancel)
		local thread = task.delay(seconds, resolve, seconds)
		onCancel(function()
			task.cancel(thread)
		end)
	end)
end

function Promise.try(callback: (...any) -> ...any, ...: any): Promise
	local success, result = xpcall(callback, internal.runErrorHandler, ...)
	if success then
		return Promise.resolve(result)
	else
		local promise = Promise.new(internal.noop)
		internal.reject(promise, result)
		return promise
	end
end

function Promise.promisify(fn: (...any) -> ...any)
	return function(...)
		local promise = Promise.new(internal.noop)
		task.spawn(function(...)
			local success, result = xpcall(fn, internal.runErrorHandler, ...)
			if success then
				internal.resolve(promise, result)
			else
				internal.reject(promise, result)
			end
		end, ...)
		return promise
	end
end

function Promise.fromEvent(event: any, predicate: ((...any) -> boolean)?): Promise
	return Promise.new(function(resolve, reject)
		local connection
		connection = event:Connect(function(...)
			if predicate then
				local success, result = xpcall(predicate, internal.runErrorHandler, ...)
				if not success then
					connection:Disconnect()
					reject(result)
					return
				end
				if not result then
					return
				end
			end
			connection:Disconnect()
			resolve(...)
		end)
	end)
end

function Promise.retry(callback: (...any) -> Promise, times: number, ...: any): Promise
	local args = { ... }
	return Promise.new(function(resolve, reject, onCancel)
		local attempts = 0
		local currentPromise
		local function attempt()
			attempts += 1
			currentPromise = Promise.resolve(callback(unpack(args)))
			currentPromise:andThen(function(v)
				resolve(v)
				return nil
			end, function(err)
				if attempts < times then
					attempt()
				else
					local finalErr = Error.is(err)
							and (err :: any):extend({
								context = string.format("Promise.retry failed after %d attempts", times),
							})
						or Error.new({
							error = err,
							context = string.format("Promise.retry failed after %d attempts", times),
						})
					reject(finalErr)
				end
				return nil
			end)
		end

		onCancel(function()
			if currentPromise then
				currentPromise:cancel()
			end
		end)
		attempt()
	end)
end

function Promise.retryWithDelay(callback: (...any) -> Promise, times: number, seconds: number, ...: any): Promise
	local args = { ... }
	return Promise.new(function(resolve, reject, onCancel)
		local attempts = 0
		local currentPromise
		local function attempt()
			attempts += 1
			currentPromise = Promise.resolve(callback(unpack(args)))
			currentPromise:andThen(function(v)
				resolve(v)
				return nil
			end, function(err)
				if attempts < times then
					currentPromise = Promise.delay(seconds)
					currentPromise:andThen(function()
						attempt()
						return nil
					end)
				else
					local finalErr = Error.is(err)
							and (err :: any):extend({
								context = string.format("Promise.retryWithDelay failed after %d attempts", times),
							})
						or Error.new({
							error = err,
							context = string.format("Promise.retryWithDelay failed after %d attempts", times),
						})
					reject(finalErr)
				end
				return nil
			end)
		end

		onCancel(function()
			if currentPromise then
				currentPromise:cancel()
			end
		end)
		attempt()
	end)
end

local attachCollections = require(script.collections)
attachCollections(Promise)

function Promise:timeout(seconds: number, message: string?): Promise
	return (Promise :: any).race({
		self,
		Promise.delay(seconds):andThen(function()
			return Promise.reject(Error.new({
				kind = Error.Kind.TimedOut,
				error = message or string.format("Promise timed out after %d seconds", seconds),
				context = string.format("Promise:timeout(%d)", seconds),
			}))
		end),
	})
end

return Promise
