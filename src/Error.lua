--!strict
local Error = {}
Error.__index = Error

export type Kind = string

local Kinds = {
	ExecutionError = "ExecutionError",
	AlreadyCancelled = "AlreadyCancelled",
	NotResolvable = "NotResolvable",
	TimedOut = "TimedOut",
}
Error.Kind = Kinds

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

function Error.new(options: { error: unknown, trace: string?, context: string?, kind: Kind?, parent: any? }): Error
	local self = setmetatable({
		error = if options.error == nil then "Unknown error" else options.error,
		trace = options.trace,
		context = options.context,
		kind = options.kind or Kinds.ExecutionError,
		parent = options.parent,
		isPromiseError = true,
	}, Error)

	return self :: any
end

function Error.is(err: any): boolean
	return type(err) == "table" and err.isPromiseError == true
end

function Error.isKind(err: any, kind: Kind): boolean
	return Error.is(err) and err.kind == kind
end

function Error.extend(self: Error, options: { error: unknown?, trace: string?, context: string?, kind: Kind? }?): Error
	options = options or ({} :: any)
	return Error.new({
		error = if options.error ~= nil then options.error else self.error,
		trace = options.trace or self.trace,
		context = options.context or self.context,
		kind = options.kind or self.kind,
		parent = self,
	})
end

function Error.__tostring(self: Error): string
	local lines = {}
	table.insert(lines, string.format("Promise.Error(%s): %s", self.kind, tostring(self.error)))

	if self.context then
		table.insert(lines, string.format("Context: %s", self.context))
	end

	if self.trace then
		table.insert(lines, "Stack Trace:")
		table.insert(lines, self.trace)
	end

	if self.parent then
		table.insert(lines, "Caused by:")
		table.insert(lines, tostring(self.parent))
	end

	return table.concat(lines, "\n")
end

return Error
