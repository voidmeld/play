--!strict

local RateLimit = require("./net/rate-limit")

export type RateLimitConfig = RateLimit.Config
export type RateLimitBucket = RateLimit.Bucket
export type RateLimitKeyedState = RateLimit.KeyedState

export type API = {
	read rate_limit: typeof(RateLimit),
}

local api: API = {
	rate_limit = RateLimit,
}

return table.freeze(api)
