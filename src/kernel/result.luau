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

local function unwrap<T>(result: Result<T>): T
	if not result.ok then
		error(result.reason, 2)
	end
	return result.value
end

export type API = {
	read ok: typeof(ok),
	read fail: typeof(fail),
	read reason: typeof(reason),
	read unwrap: typeof(unwrap),
}
local api: API = { ok = ok, fail = fail, reason = reason, unwrap = unwrap }
return table.freeze(api)
