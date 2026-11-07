--!strict

local Payload = require("./net/payload")
local RateLimit = require("./net/rate-limit")

export type RateLimitConfig = RateLimit.Config
export type RateLimitBucket = RateLimit.Bucket
export type RateLimitKeyedState = RateLimit.KeyedState
export type PayloadBounds = Payload.Bounds
export type PayloadArguments = Payload.Arguments
export type PayloadConfig = Payload.Config

export type API = {
	read rate_limit: typeof(RateLimit),
	read payload: typeof(Payload),
}

local api: API = {
	rate_limit = RateLimit,
	payload = Payload,
}

return table.freeze(api)
