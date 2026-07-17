--!strict
local Enumerator = require(script.Parent.Enumerator)
type Enumerator = Enumerator.Enumerator

local internal = require(script.Parent.internal)
type Promise = internal.Promise

return function(Promise: any)
	local function all(entries: { unknown }, label: string?): Promise
		if type(entries) ~= "table" then
			return Promise.reject("Promise.all must be called with a table", label)
		end
		return Enumerator.new(Promise, entries, true, label).promise
	end

	local RaceEnumerator = setmetatable({}, Enumerator)
	RaceEnumerator.__index = RaceEnumerator

	function RaceEnumerator.setResultAt(self: any, _state: number, _i: any, value: unknown, _firstPass: boolean)
		if self.promise._state ~= internal.PENDING then
			return
		end
		internal.resolve(self.promise, value)
		self:cancelRemaining()
	end

	local function race(entries: { unknown }, label: string?): Promise
		if type(entries) ~= "table" then
			return Promise.reject("Promise.race must be called with a table", label)
		end

		local length = #entries
		local onCancelHook
		local promise = Promise.new(function(_resolve, _reject, onCancel)
			onCancelHook = onCancel
		end, label)

		local instance: any = setmetatable({
			_instanceConstructor = Promise,
			promise = promise,
			_abortOnReject = true,
			_isUsingOwnPromise = true,
			_isUsingOwnResolve = true,
			length = length,
			_remaining = length,
		}, RaceEnumerator)

		if onCancelHook then
			onCancelHook(function()
				instance:cancelRemaining()
			end)
		end

		instance:init(Promise, entries)
		return instance.promise
	end

	local AllSettled = setmetatable({}, Enumerator)
	AllSettled.__index = AllSettled

	function AllSettled.setResultAt(self: any, state: number, i: any, value: unknown, _firstPass: boolean)
		self._remaining -= 1
		if self._result then
			local result = self._result :: { unknown }
			if state == internal.FULFILLED then
				result[i] = { state = "fulfilled", value = value }
			else
				result[i] = { state = "rejected", reason = value }
			end
		end
	end

	local function allSettled(entries: { unknown }, label: string?): Promise
		if type(entries) ~= "table" then
			return Promise.reject("Promise.allSettled must be called with a table", label)
		end
		local length = #entries
		local promise = Promise.new(internal.noop, label)
		local instance: any = setmetatable({
			_instanceConstructor = Promise,
			promise = promise,
			_abortOnReject = false,
			_isUsingOwnPromise = true,
			_isUsingOwnResolve = true,
			length = length,
			_remaining = length,
			_result = table.create(length),
		}, AllSettled)
		instance:init(Promise, entries)
		return instance.promise
	end

	local PromiseHash = setmetatable({}, Enumerator)
	PromiseHash.__index = PromiseHash

	function PromiseHash.enumerate(self: any, input: { [unknown]: unknown })
		local keys = {}
		for k, _ in pairs(input) do
			table.insert(keys, k)
		end

		local length = #keys
		local promise = self.promise
		self._remaining = length

		for i = 1, length do
			if promise._state ~= internal.PENDING then
				break
			end
			local key = keys[i]
			local val = input[key]
			self:eachEntry(val, key, true)
		end

		self:checkFulfillment()
	end

	local function hash(object: { [unknown]: unknown }, label: string?): Promise
		if type(object) ~= "table" then
			return Promise.reject("Promise.hash must be called with a table", label)
		end
		return Promise.resolve(object, label):andThen(function(obj: unknown)
			local instance: any = setmetatable({
				_instanceConstructor = Promise,
				promise = Promise.new(internal.noop, label),
				_abortOnReject = true,
				_isUsingOwnPromise = true,
				_isUsingOwnResolve = true,
				_result = {},
			}, PromiseHash)
			instance:init(Promise, obj :: { [unknown]: unknown })
			return instance.promise
		end)
	end

	local HashSettled = setmetatable({}, PromiseHash)
	HashSettled.__index = HashSettled
	HashSettled.setResultAt = AllSettled.setResultAt

	local function hashSettled(object: { [unknown]: unknown }, label: string?): Promise
		if type(object) ~= "table" then
			return Promise.reject("Promise.hashSettled must be called with a table", label)
		end
		return Promise.resolve(object, label):andThen(function(obj: unknown)
			local instance: any = setmetatable({
				_instanceConstructor = Promise,
				promise = Promise.new(internal.noop, label),
				_abortOnReject = false,
				_isUsingOwnPromise = true,
				_isUsingOwnResolve = true,
				_result = {},
			}, HashSettled)
			instance:init(Promise, obj :: { [unknown]: unknown })
			return instance.promise
		end)
	end

	local MapEnumerator = setmetatable({}, Enumerator)
	MapEnumerator.__index = MapEnumerator

	function MapEnumerator.setResultAt(self: any, _state: number, i: any, value: unknown, firstPass: boolean)
		if firstPass then
			local success, err = xpcall(function()
				local mapFn = self._mapFn :: (unknown, unknown) -> unknown
				if type(mapFn) == "function" then
					self:eachEntry(mapFn(value, i), i, false)
				end
				return nil
			end, internal.runErrorHandler)
			if not success then
				self:settledAt(internal.REJECTED, i, err, false)
			end
		else
			self._remaining -= 1
			if self._result then
				(self._result :: { unknown })[i] = value
			end
		end
	end

	local function map(promises: { unknown }, mapFn: (unknown, unknown) -> unknown, label: string?): Promise
		if type(mapFn) ~= "function" then
			return Promise.reject("map expects a function as a second argument", label)
		end
		return Promise.resolve(promises, label):andThen(function(arr: unknown)
			if type(arr) ~= "table" then
				error("map must be called with an array")
			end
			local length = #(arr :: { unknown })
			local instance: any = setmetatable({
				_instanceConstructor = Promise,
				promise = Promise.new(internal.noop, label),
				_abortOnReject = true,
				_isUsingOwnPromise = true,
				_isUsingOwnResolve = true,
				length = length,
				_remaining = length,
				_result = table.create(length),
				_mapFn = mapFn,
			}, MapEnumerator)
			instance:init(Promise, arr :: { unknown }, mapFn)
			return instance.promise
		end)
	end

	local FilterEnumerator = setmetatable({}, MapEnumerator)
	FilterEnumerator.__index = FilterEnumerator
	local EMPTY_OBJECT = {}

	function FilterEnumerator.checkFulfillment(self: any)
		local resultArr = self._result
		if self._remaining == 0 and resultArr ~= nil then
			local result = {}
			for i = 1, self.length do
				if resultArr[i] ~= EMPTY_OBJECT then
					table.insert(result, resultArr[i])
				end
			end
			internal.fulfill(self.promise, result)
			self._result = nil
		end
	end

	function FilterEnumerator.setResultAt(self: any, _state: number, i: any, value: unknown, firstPass: boolean)
		if firstPass then
			if self._result then
				(self._result :: { unknown })[i] = value
			end
			local val
			local succeeded, err = xpcall(function()
				local mapFn = self._mapFn :: (unknown, unknown) -> unknown
				if type(mapFn) == "function" then
					val = mapFn(value, i)
				end
				return nil
			end, internal.runErrorHandler)
			if not succeeded then
				self:settledAt(internal.REJECTED, i, err, false)
			else
				self:eachEntry(val, i, false)
			end
		else
			self._remaining -= 1
			if not value and self._result then
				(self._result :: { unknown })[i] = EMPTY_OBJECT
			end
		end
	end

	local function filter(promises: { unknown }, filterFn: (unknown, unknown) -> unknown, label: string?): Promise
		if type(filterFn) ~= "function" then
			return Promise.reject("filter expects function as a second argument", label)
		end
		return Promise.resolve(promises, label):andThen(function(arr: unknown)
			if type(arr) ~= "table" then
				error("filter must be called with an array")
			end
			local length = #(arr :: { unknown })
			local instance: any = setmetatable({
				_instanceConstructor = Promise,
				promise = Promise.new(internal.noop, label),
				_abortOnReject = true,
				_isUsingOwnPromise = true,
				_isUsingOwnResolve = true,
				length = length,
				_remaining = length,
				_result = table.create(length),
				_mapFn = filterFn,
			}, FilterEnumerator)
			instance:init(Promise, arr :: { unknown }, filterFn)
			return instance.promise
		end)
	end

	local SomeEnumerator = setmetatable({}, Enumerator)
	SomeEnumerator.__index = SomeEnumerator

	function SomeEnumerator.setResultAt(self: any, state: number, _i: any, value: unknown, _firstPass: boolean)
		if self.promise._state ~= internal.PENDING then
			return
		end

		if state == internal.FULFILLED then
			self._resolvedCount += 1
			table.insert(self._resolvedValues, value)
			if self._resolvedCount >= self._count then
				internal.resolve(self.promise, self._resolvedValues)
				self:cancelRemaining()
			end
		else
			self._rejectedCount += 1
			if self._rejectedCount >= self._targetRejections then
				internal.reject(self.promise, value)
				self:cancelRemaining()
			end
		end
	end

	local function some(promises: { unknown }, count: number, label: string?): Promise
		if type(promises) ~= "table" then
			return Promise.reject("Promise.some must be called with a table", label)
		end
		local length = #promises
		if count > length then
			return Promise.reject("Promise.some requires count to be less than or equal to the array length", label)
		end
		if count == 0 then
			return Promise.resolve({}, label)
		end

		local onCancelHook
		local promise = Promise.new(function(_resolve, _reject, onCancel)
			onCancelHook = onCancel
		end, label)

		local instance: any = setmetatable({
			_instanceConstructor = Promise,
			promise = promise,
			_abortOnReject = false,
			_isUsingOwnPromise = true,
			_isUsingOwnResolve = true,
			length = length,
			_remaining = length,
			_count = count,
			_targetRejections = length - count + 1,
			_resolvedCount = 0,
			_rejectedCount = 0,
			_resolvedValues = table.create(count),
		}, SomeEnumerator)

		if onCancelHook then
			onCancelHook(function()
				instance:cancelRemaining()
			end)
		end

		instance:init(Promise, promises)
		return instance.promise
	end

	local function any(promises: { unknown }, label: string?): Promise
		if type(promises) ~= "table" then
			return Promise.reject("Promise.any must be called with a table", label)
		end

		local length = #promises
		if length == 0 then
			return Promise.reject("AggregateError: All promises were rejected", label)
		end

		return some(promises, 1, label):andThen(function(values)
			return (values :: { unknown })[1]
		end, function(reason)
			return Promise.reject(reason)
		end)
	end

	local function fold(
		promises: { unknown },
		reducer: (unknown, unknown, number) -> unknown,
		initialValue: unknown,
		label: string?
	): Promise
		if type(promises) ~= "table" then
			return Promise.reject("Promise.fold must be called with a table", label)
		end
		if type(reducer) ~= "function" then
			return Promise.reject("Promise.fold expects a function as the second argument", label)
		end

		local length = #promises
		local resultPromise = Promise.resolve(initialValue)

		for i = 1, length do
			resultPromise = resultPromise:andThen(function(acc)
				return Promise.resolve(promises[i]):andThen(function(value)
					return reducer(acc, value, i)
				end)
			end)
		end

		return resultPromise
	end

	Promise.all = all
	Promise.race = race
	Promise.allSettled = allSettled
	Promise.hash = hash
	Promise.hashSettled = hashSettled
	Promise.map = map
	Promise.filter = filter
	Promise.some = some
	Promise.any = any
	Promise.fold = fold
end
