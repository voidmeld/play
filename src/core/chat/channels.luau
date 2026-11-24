--!strict

local Rate = require("../net/rate-limit")

export type Member = {
	id: number,
	realm: unknown,
	party: unknown,
	guild: unknown,
	warband: unknown,
}
export type Audience = "say" | "realm" | "party" | "guild" | "warband" | "whisper"
export type Rule = {
	audience: Audience,
	sameRealm: boolean,
	selfDelivery: boolean,
}
export type Bucket = Rate.Bucket
export type Budget = Rate.Config

local Channels = {}

local function same(first: unknown, second: unknown): boolean
	return type(first) == "string" and first ~= "" and first == second
end

function Channels.allows(rule: Rule, speaker: Member, listener: Member, reachable: boolean, pair: { number }?): boolean
	if rule.selfDelivery and speaker.id == listener.id then
		return true
	end
	if rule.sameRealm and not same(speaker.realm, listener.realm) then
		return false
	end
	if rule.audience == "say" then
		return reachable
	elseif rule.audience == "realm" then
		return true
	elseif rule.audience == "party" then
		return same(speaker.party, listener.party)
	elseif rule.audience == "guild" then
		return same(speaker.guild, listener.guild)
	elseif rule.audience == "warband" then
		return same(speaker.warband, listener.warband)
	end
	return pair ~= nil and #pair == 2 and table.find(pair, speaker.id) ~= nil and table.find(pair, listener.id) ~= nil
end

function Channels.consume(bucket: Bucket?, budget: Budget, now: number, cost: number?): (boolean, Bucket)
	return Rate.tryConsume(bucket or Rate.newBucket(budget, now), budget, now, cost)
end

function Channels.trim<T>(lines: { T }, limit: number): { T }
	local dropped: { T } = {}
	while #lines > limit do
		local oldest = table.remove(lines, 1)
		if oldest ~= nil then
			table.insert(dropped, oldest)
		end
	end
	return dropped
end

function Channels.window<T>(lines: { T }, now: number, duration: number, timeOf: (T) -> number): { T }
	local retained: { T } = {}
	for _, line in lines do
		local age = now - timeOf(line)
		if age >= 0 and age <= duration then
			table.insert(retained, line)
		end
	end
	return retained
end

function Channels.parse(input: string, commands: { [string]: string }): (string?, string)
	local command, rest = string.match(input, "^%s*/(%a+)%s*(.-)%s*$")
	local scope = if command ~= nil then commands[string.lower(command)] else nil
	return if scope ~= nil then scope else nil, if scope ~= nil and rest ~= nil then rest else input
end

function Channels.pairName(prefix: string, first: number, second: number): string
	return ("%s%d_%d"):format(prefix, math.min(first, second), math.max(first, second))
end

return table.freeze(Channels)
