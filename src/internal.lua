--!strict
local Error = require(script.Parent.Error)

export type State = number

export type Promise = {
	_id: number,
	_label: string?,
	_state: State,
	_result: unknown,
	_values: { unknown }?,
	_valuesLength: number?,
	_subscribers: { any }?,
	_cancellationHooks: { () -> () }?,
	_parent: Promise?,
	_consumers: number,
	_onError: ((Promise, unknown) -> ())?,
	andThen: (
		self: Promise,
		onFulfillment: ((unknown) -> unknown)?,
		onRejection: ((unknown) -> unknown)?,
		label: string?
	) -> Promise,
	catch: (self: Promise, onRejection: (unknown) -> unknown, label: string?) -> Promise,
	finally: (self: Promise, callback: () -> unknown, label: string?) -> Promise,
	cancel: (self: Promise) -> (),
	await: (self: Promise) -> (boolean, ...unknown),
	expect: (self: Promise) -> ...unknown,
}

local internal = {
	PENDING = 0 :: State,
	FULFILLED = 1 :: State,
	REJECTED = 2 :: State,
	CANCELLED = 3 :: State,
	noop = function() end,
	Promise = nil :: any,
	originalThen = nil :: any,
	originalResolve = nil :: any,
}

local function isObjectOrFunction(x: unknown): boolean
	local t = type(x)
	return x ~= nil and (t == "table" or t == "function" or t == "userdata")
end

local function withOwnPromise(): any
	return Error.new({
		error = "A promises callback cannot return that same promise.",
		kind = Error.Kind.ExecutionError,
	})
end

local function tryThen(
	thenFn: any,
	value: unknown,
	fulfillmentHandler: (unknown) -> (),
	rejectionHandler: (unknown) -> ()
): unknown
	local success, errorResult = xpcall(function()
		thenFn(value, fulfillmentHandler, rejectionHandler)
		return nil
	end, internal.runErrorHandler)
	if not success then
		return errorResult
	end
	return nil
end

local function handleForeignThenable(promise: Promise, thenable: any, thenFn: any)
	task.defer(function(p: Promise)
		local sealed = false
		local errorResult = tryThen(thenFn, thenable, function(...)
			if sealed then
				return
			end
			sealed = true
			local value = ...
			if thenable == value then
				internal.fulfill(p, ...)
			else
				internal.resolve(p, ...)
			end
		end, function(...)
			if sealed then
				return
			end
			sealed = true
			internal.reject(p, ...)
		end)

		if not sealed and errorResult then
			sealed = true
			internal.reject(p, errorResult)
		end
	end, promise)
end

local function handleOwnThenable(promise: Promise, thenable: any)
	if thenable._state == internal.FULFILLED then
		if thenable._valuesLength then
			internal.fulfill(promise, unpack(thenable._values :: { any }, 1, thenable._valuesLength :: number))
		else
			internal.fulfill(promise, thenable._result)
		end
	elseif thenable._state == internal.REJECTED then
		thenable._onError = nil
		if thenable._valuesLength then
			internal.reject(promise, unpack(thenable._values :: { any }, 1, thenable._valuesLength :: number))
		else
			internal.reject(promise, thenable._result)
		end
	elseif thenable._state == internal.CANCELLED then
		internal.cancel(promise)
	else
		internal.subscribe(thenable, function()
			internal.cancel(promise)
		end, function(...)
			local value = ...
			if thenable == value then
				internal.fulfill(promise, ...)
			else
				internal.resolve(promise, ...)
			end
		end, function(...)
			internal.reject(promise, ...)
		end)
	end
end

function internal.handleMaybeThenable(promise: Promise, maybeThenable: any, thenFn: any)
	local isOwnThenable = getmetatable(maybeThenable) == internal.Promise
		and thenFn == internal.originalThen
		and internal.Promise.resolve == internal.originalResolve

	if isOwnThenable then
		handleOwnThenable(promise, maybeThenable)
	elseif type(thenFn) == "function" then
		handleForeignThenable(promise, maybeThenable, thenFn)
	else
		internal.fulfill(promise, maybeThenable)
	end
end

function internal.resolve(promise: Promise, ...)
	local value = ...

	if promise == (value :: any) then
		internal.reject(promise, withOwnPromise())
	elseif isObjectOrFunction(value) then
		local thenFn
		local success, err = pcall(function()
			thenFn = (value :: any).andThen or (value :: any)["then"]
		end)

		if not success then
			internal.reject(promise, err)
			return
		end
		internal.handleMaybeThenable(promise, value, thenFn)
	else
		internal.fulfill(promise, ...)
	end
end

function internal.publishRejection(promise: Promise)
	if promise._onError then
		if promise._valuesLength then
			promise._onError(promise, unpack(promise._values :: { any }, 1, promise._valuesLength))
		else
			promise._onError(promise, promise._result)
		end
	end
	internal.publish(promise)
end

function internal.fulfill(promise: Promise, ...)
	if promise._state ~= internal.PENDING then
		return
	end

	local length = select("#", ...)
	if length > 1 then
		promise._values = { ... }
		promise._valuesLength = length
		promise._result = ...
	else
		promise._result = ...
	end
	promise._state = internal.FULFILLED

	if promise._subscribers and #promise._subscribers > 0 then
		task.defer(internal.publish, promise)
	end
end

function internal.reject(promise: Promise, ...)
	if promise._state ~= internal.PENDING then
		return
	end

	local length = select("#", ...)
	local reason = ...

	if length > 1 then
		promise._values = { ... }
		promise._valuesLength = length
		promise._result = reason
	else
		promise._result = reason
	end
	promise._state = internal.REJECTED
	task.defer(internal.publishRejection, promise)
end

function internal.cancel(promise: Promise)
	if promise._state ~= internal.PENDING then
		return
	end
	promise._state = internal.CANCELLED
	task.defer(internal.publish, promise)
end

function internal.subscribe(parent: Promise, child: any, onFulfillment: any, onRejection: any)
	if not parent._subscribers then
		parent._subscribers = {}
	end

	local subscribers = parent._subscribers :: { any }
	local length = #subscribers

	parent._onError = nil

	subscribers[length + 1] = child
	subscribers[length + 2] = onFulfillment
	subscribers[length + 3] = onRejection

	if length == 0 and parent._state ~= internal.PENDING then
		task.defer(internal.publish, parent)
	end
end

function internal.publish(promise: Promise)
	local subscribers = promise._subscribers
	promise._subscribers = nil

	if not subscribers then
		return
	end

	local subs = subscribers :: { any }
	if #subs == 0 then
		return
	end

	local settled = promise._state

	local child, callback
	local hasValues = promise._valuesLength ~= nil

	for i = 1, #subs, 3 do
		child = subs[i]

		if settled == internal.CANCELLED then
			if child then
				if type(child) == "function" then
					local cb = child :: any
					cb()
				else
					(child :: any):cancel()
				end
			end
			continue
		end

		callback = subs[i + settled]

		if child and type(child) ~= "function" then
			internal.invokeCallback(settled, child, callback, promise)
		else
			if type(callback) == "function" then
				local cb = callback :: any
				if hasValues then
					cb(unpack(promise._values :: { any }, 1, promise._valuesLength))
				else
					cb(promise._result)
				end
			end
		end
	end
end

function internal.invokeCallback(state: State, promise: Promise, callback: any, parent: Promise)
	local hasCallback = type(callback) == "function"
	local succeeded: boolean, errorResult: unknown = true, nil

	local returnLength = 0
	local returnValues = nil

	if hasCallback then
		local hasValues = parent._valuesLength ~= nil
		local results = table.pack(xpcall(function()
			if hasValues then
				return callback(unpack(parent._values :: { any }, 1, parent._valuesLength))
			else
				return callback(parent._result)
			end
		end, internal.runErrorHandler))

		succeeded = results[1]
		if not succeeded then
			errorResult = results[2]
		else
			returnLength = results.n - 1
			returnValues = results
		end
	end

	if promise._state == internal.PENDING then
		if succeeded == false then
			internal.reject(promise, errorResult)
		elseif hasCallback then
			if returnLength > 0 then
				internal.resolve(promise, unpack(returnValues :: { any }, 2, returnLength + 1))
			else
				internal.resolve(promise)
			end
		elseif state == internal.FULFILLED then
			if parent._valuesLength then
				internal.fulfill(promise, unpack(parent._values :: { any }, 1, parent._valuesLength))
			else
				internal.fulfill(promise, parent._result)
			end
		elseif state == internal.REJECTED then
			if parent._valuesLength then
				internal.reject(promise, unpack(parent._values :: { any }, 1, parent._valuesLength))
			else
				internal.reject(promise, parent._result)
			end
		end
	end
end

function internal.initializePromise(
	promise: Promise,
	resolver: ((unknown) -> (), (unknown) -> (), (() -> ()) -> ()) -> ()
)
	local resolved = false
	local success, err = xpcall(function()
		resolver(function(...)
			if resolved then
				return
			end
			resolved = true
			internal.resolve(promise, ...)
		end, function(...)
			if resolved then
				return
			end
			resolved = true
			internal.reject(promise, ...)
		end, function(onCancelHook: () -> ())
			if resolved or promise._state ~= internal.PENDING then
				return
			end
			local hooks = promise._cancellationHooks
			if not hooks then
				hooks = {}
				promise._cancellationHooks = hooks
			end
			table.insert(hooks :: { () -> () }, onCancelHook)
		end)
		return nil
	end, internal.runErrorHandler)

	if not success then
		internal.reject(promise, err)
	end
end

function internal.runErrorHandler(err: any): any
	if type(err) == "table" and err.isPromiseError then
		return err
	end
	return Error.new({
		error = err,
		kind = Error.Kind.ExecutionError,
		trace = debug.traceback(tostring(err), 2),
	})
end

return internal
