--!strict

export type Success<T> = { read ok: true, read value: T }
export type Failure = { read ok: false, read reason: string, read detail: string? }
export type Result<T> = Success<T> | Failure

local function ok<T>(value: T): Success<T>
	return { ok = true, value = value }
end

local function fail(reason: string, detail: string?): Failure
	return { ok = false, reason = reason, detail = detail }
end

local function reason<T>(result: Result<T>): string?
	return if result.ok then nil else result.reason
end

export type API = { read ok: typeof(ok), read fail: typeof(fail), read reason: typeof(reason) }
local api: API = { ok = ok, fail = fail, reason = reason }
return table.freeze(api)
