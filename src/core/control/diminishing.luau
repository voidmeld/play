--!strict

export type Bucket = { count: number, windowExpiry: number }
export type State = { [string]: Bucket }
export type Category = {
	family: string,
	durationCapSec: number,
	immunityPrice: number,
	immunityMinSec: number,
	immunityMaxSec: number,
}
export type Config = { resetSec: number, multipliers: { number }, categories: { [string]: Category } }
export type Step = "full" | "reduced" | "immune"
export type Result = { dr: State, grantedSec: number, multiplier: number, step: Step, immune: boolean }

local Diminishing = {}

local function finite(value: number): boolean
	return value == value and value > -math.huge and value < math.huge
end

function Diminishing.empty(): State
	return {}
end

function Diminishing.clone(state: State): State
	local result: State = {}
	for key, bucket in state do
		result[key] = { count = bucket.count, windowExpiry = bucket.windowExpiry }
	end
	return result
end

function Diminishing.rules(config: Config)
	assert(finite(config.resetSec) and config.resetSec > 0, "invalid reset window")
	assert(#config.multipliers > 0, "missing duration steps")
	local multipliers = table.clone(config.multipliers)
	for _, multiplier in multipliers do
		assert(finite(multiplier) and multiplier >= 0 and multiplier <= 1, "invalid duration step")
	end
	local categories: { [string]: Category } = {}
	for name, category in config.categories do
		assert(name ~= "" and category.family ~= "" and config.categories[category.family] == nil, "invalid family key")
		assert(finite(category.durationCapSec) and category.durationCapSec >= 0, "invalid duration cap")
		assert(finite(category.immunityPrice) and category.immunityPrice >= 0, "invalid immunity price")
		assert(finite(category.immunityMinSec) and category.immunityMinSec >= 0, "invalid immunity minimum")
		assert(
			finite(category.immunityMaxSec) and category.immunityMaxSec >= category.immunityMinSec,
			"invalid immunity maximum"
		)
		categories[name] = table.clone(category)
	end
	local resetSec = config.resetSec
	local function apply(state: State, category: string, baseDurationSec: number, nowSec: number): Result
		local nextState = Diminishing.clone(state)
		local policy = categories[category]
		local familyState = if policy == nil then nil else nextState[policy.family]
		if policy == nil or not finite(nowSec) or (familyState ~= nil and nowSec < familyState.windowExpiry) then
			return { dr = nextState, grantedSec = 0, multiplier = 0, step = "immune", immune = true }
		end
		local categoryState = nextState[category]
		local count = if categoryState ~= nil and nowSec < categoryState.windowExpiry then categoryState.count else 0
		local multiplier = multipliers[math.min(count + 1, #multipliers)]
		local duration = if finite(baseDurationSec) and baseDurationSec > 0
			then math.min(baseDurationSec, policy.durationCapSec)
			else 0
		local grantedSec = duration * multiplier
		nextState[category] = {
			count = count + 1,
			windowExpiry = if count == 0 then nowSec + resetSec else assert(categoryState).windowExpiry,
		}
		if grantedSec > 0 and policy.immunityMaxSec > 0 then
			local immunitySec =
				math.clamp(policy.immunityPrice * grantedSec, policy.immunityMinSec, policy.immunityMaxSec)
			if immunitySec > 0 then
				nextState[policy.family] = {
					count = (if familyState == nil then 0 else familyState.count) + 1,
					windowExpiry = nowSec + immunitySec,
				}
			end
		end
		return {
			dr = nextState,
			grantedSec = grantedSec,
			multiplier = multiplier,
			step = if multiplier == 0 then "immune" elseif multiplier == 1 then "full" else "reduced",
			immune = multiplier == 0,
		}
	end
	return table.freeze({ apply = apply })
end

return table.freeze(Diminishing)
