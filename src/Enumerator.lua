--!strict
local internal = require(script.Parent.internal)
type Promise = internal.Promise

local Enumerator = {}
Enumerator.__index = Enumerator

export type Enumerator = typeof(setmetatable(
	{} :: {
		_instanceConstructor: any,
		promise: Promise,
		_abortOnReject: boolean,
		_isUsingOwnPromise: boolean,
		_isUsingOwnResolve: boolean,
		length: number,
		_remaining: number,
		_result: { unknown }?,
		_mapFn: ((unknown, unknown) -> unknown)?,
		_input: { unknown }?,
	},
	Enumerator
))

function Enumerator.new(
	Constructor: any,
	entries: { unknown },
	abortOnReject: boolean,
	label: string?,
	mapFn: ((unknown, unknown) -> unknown)?
): Enumerator
	local length = #entries
	local onCancelHook
	local promise = Constructor.new(function(_resolve, _reject, onCancel)
		onCancelHook = onCancel
	end, label)

	local self = setmetatable({
		_instanceConstructor = Constructor,
		promise = promise,
		_abortOnReject = abortOnReject,
		_isUsingOwnPromise = getmetatable(promise) == internal.Promise,
		_isUsingOwnResolve = Constructor.resolve == internal.originalResolve,
		_isUsingOwnThen = Constructor.andThen == internal.originalThen,
		length = length,
		_remaining = length,
		_result = table.create(length),
		_mapFn = mapFn,
	}, Enumerator) :: any

	if onCancelHook then
		onCancelHook(function()
			self:cancelRemaining()
		end)
	end

	self:init(Constructor, entries, mapFn)
	return self
end

function Enumerator:init(_Constructor: any, input: { unknown }, _mapFn: ((unknown, unknown) -> unknown)?)
	self._input = input
	self:enumerate(input)
end

function Enumerator:enumerate(input: { unknown })
	local length = self.length
	local promise = self.promise

	for i = 1, length do
		if promise._state ~= internal.PENDING then
			break
		end
		self:eachEntry(input[i], i, true)
	end
	self:checkFulfillment()
end

function Enumerator:checkFulfillment()
	if self._remaining == 0 then
		local result = self._result
		internal.fulfill(self.promise, result)
		self._result = nil :: any
	end
end

function Enumerator:settleMaybeThenable(entry: any, i: any, firstPass: boolean)
	local c = self._instanceConstructor

	if self._isUsingOwnResolve then
		local thenFn, errorResult, succeeded = nil, nil, true
		succeeded, errorResult = xpcall(function()
			if type(entry) == "table" or type(entry) == "userdata" then
				thenFn = entry.andThen or entry["then"]
			end
		end, internal.runErrorHandler)

		if not succeeded then
			thenFn = nil
		end

		if
			getmetatable(entry) == internal.Promise
			and thenFn == internal.originalThen
			and entry._state ~= internal.PENDING
		then
			entry._onError = nil
			self:settledAt(entry._state, i, entry._result, firstPass)
		elseif type(thenFn) ~= "function" then
			self:settledAt(internal.FULFILLED, i, entry, firstPass)
		elseif self._isUsingOwnPromise then
			local promise = c.new(internal.noop)
			if succeeded == false then
				internal.reject(promise, errorResult)
			else
				internal.handleMaybeThenable(promise, entry, thenFn)
				self:willSettleAt(promise, i, firstPass)
			end
		else
			local promise = c.new(function(resolve: any)
				resolve(entry)
			end)
			self:willSettleAt(promise, i, firstPass)
		end
	else
		self:willSettleAt(c.resolve(entry), i, firstPass)
	end
end

function Enumerator:eachEntry(entry: unknown, i: any, firstPass: boolean)
	if entry ~= nil and (type(entry) == "table" or type(entry) == "userdata" or type(entry) == "function") then
		self:settleMaybeThenable(entry, i, firstPass)
	else
		self:setResultAt(internal.FULFILLED, i, entry, firstPass)
	end
end

function Enumerator:settledAt(state: number, i: any, value: unknown, firstPass: boolean)
	if self.promise._state ~= internal.PENDING then
		return
	end
	
	if state == internal.CANCELLED then
		self:cancelRemaining()
		internal.cancel(self.promise)
		return
	end

	if self._abortOnReject and state == internal.REJECTED then
		internal.reject(self.promise, value)
		self:cancelRemaining()
	else
		self:setResultAt(state, i, value, firstPass)
		self:checkFulfillment()
	end
end

function Enumerator:setResultAt(_state: number, i: any, value: unknown, _firstPass: boolean)
	local typedSelf = self :: Enumerator
	typedSelf._remaining -= 1
	if typedSelf._result then
		(typedSelf._result :: { unknown })[i] = value
	end
end

function Enumerator:cancelRemaining()
	local input = self._input
	if not input then
		return
	end
	self._input = nil :: any

	for i = 1, self.length do
		local entry = input[i]
		if type(entry) == "table" or type(entry) == "userdata" then
			local cancel = (entry :: any).cancel
			if type(cancel) == "function" then
				pcall(cancel, entry)
			end
		end
	end
end

function Enumerator:willSettleAt(promise: any, i: any, firstPass: boolean)
	internal.subscribe(promise, function()
		self:settledAt(internal.CANCELLED, i, nil, firstPass)
	end, function(...)
		self:settledAt(internal.FULFILLED, i, (...), firstPass)
	end, function(...)
		self:settledAt(internal.REJECTED, i, (...), firstPass)
	end)
end

return Enumerator
