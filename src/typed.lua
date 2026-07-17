--!strict
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
export type Deferred = {
	promise: Promise,
	resolve: (value: unknown) -> (),
	reject: (reason: unknown) -> (),
}
export type Kind = string

local Error = {}
Error.__index = Error

export type Error = typeof(setmetatable(
	{} :: {
		error: unknown,
		trace: string?,
		context: string?,
		kind: Kind,
		parent: any?,
		isPromiseError: boolean,
	},
	Error
))

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
