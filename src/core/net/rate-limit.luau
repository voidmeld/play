--!strict

local RateLimit = {}

export type Config = {
	capacity: number,
	refillPerSec: number,
}

export type Bucket = {
	tokens: number,
	lastRefill: number,
}

export type KeyedState = { [string]: Bucket }

local function rl_newBucket(cfg: Config, now: number): Bucket
	return { tokens = cfg.capacity, lastRefill = now }
end
RateLimit.newBucket = rl_newBucket

local function rl_tryConsume(bucket: Bucket, cfg: Config, now: number, n: number?): (boolean, Bucket)
	local cost = if n ~= nil then n else 1
	local elapsed = math.max(0, now - bucket.lastRefill)
	local refilled = math.min(cfg.capacity, bucket.tokens + elapsed * cfg.refillPerSec)
	if refilled < cost then
		return false, { tokens = refilled, lastRefill = now }
	end
	return true, { tokens = refilled - cost, lastRefill = now }
end
RateLimit.tryConsume = rl_tryConsume

local function rl_consume(state: KeyedState, key: string, cfg: Config, now: number, n: number?): (boolean, KeyedState)
	local bucket = state[key] or rl_newBucket(cfg, now)
	local ok, nextBucket = rl_tryConsume(bucket, cfg, now, n)
	local nextState = table.clone(state)
	nextState[key] = nextBucket
	return ok, nextState
end
RateLimit.consume = rl_consume

return table.freeze(RateLimit)
