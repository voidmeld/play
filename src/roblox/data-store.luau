--!strict

export type RetryPolicy = { attempts: number, baseDelay: number, maxDelay: number }

local DataStore = {}

function DataStore.retryPolicy(policy: RetryPolicy)
	local function delay(attempt: number, jitter: number): number
		return math.min(policy.baseDelay * 2 ^ attempt, policy.maxDelay) * jitter
	end
	local function run<T>(op: () -> (boolean, T), sleep: (number) -> (), jitter: () -> number): (boolean, T)
		local ok, result = op()
		local attempt = 0
		while not ok and attempt < policy.attempts - 1 do
			sleep(delay(attempt, jitter()))
			attempt += 1
			ok, result = op()
		end
		return ok, result
	end
	return table.freeze({ delay = delay, run = run })
end

return table.freeze(DataStore)
