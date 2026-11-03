--!strict

export type Response = { ok: boolean, reason: string?, channelName: string? }
export type View = { read userId: number, read displayName: string, read channelName: string }
export type Dependencies = {
	read openWhisper: ((number, number) -> (string?, string?))?,
	read closeWhisper: ((string) -> ())?,
	read realmFor: (number) -> string?,
}
type WhisperResponse = Response
type WhisperView = View

export type Service = {
	read open: (number, number) -> Response,
	read projection: (number) -> { View },
	read close: (number) -> { number },
}

export type Config = {
	read pairName: (number, number) -> string,
	read memberFallback: (number) -> string,
}
export type API = { read create: (Dependencies, (number) -> string?) -> Service }
local function configure(config: Config): API
	config = table.freeze(table.clone(config))
	local function create(deps: Dependencies, memberNameFor: (number) -> string?): Service
		local whispersByUser: { [number]: { [number]: string } } = {}
		local whisperPending: { [string]: boolean } = {}
		local function whisperOpen(actorUserId: number, targetUserId: number): WhisperResponse
			if deps.openWhisper == nil then
				return { ok = false, reason = "direct_chat_unavailable" }
			end
			local actorRealm = deps.realmFor(actorUserId)
			if actorUserId == targetUserId or actorRealm == nil or deps.realmFor(targetUserId) ~= actorRealm then
				return { ok = false, reason = "direct_chat_target_absent" }
			end
			local pairName = config.pairName(actorUserId, targetUserId)
			if whisperPending[pairName] then
				return { ok = false, reason = "direct_chat_pending" }
			end
			whisperPending[pairName] = true
			local ran, channelName, refusal = pcall(deps.openWhisper, actorUserId, targetUserId)
			whisperPending[pairName] = nil
			if not ran then
				error(channelName, 0)
			end
			if channelName == nil then
				return { ok = false, reason = refusal or "direct_chat_refused" }
			end
			if deps.realmFor(actorUserId) ~= actorRealm or deps.realmFor(targetUserId) ~= actorRealm then
				if deps.closeWhisper ~= nil then
					deps.closeWhisper(channelName)
				end
				return { ok = false, reason = "direct_chat_target_absent" }
			end
			for _, pair in { { actorUserId, targetUserId }, { targetUserId, actorUserId } } do
				local open = whispersByUser[pair[1]] or {}
				whispersByUser[pair[1]] = open
				open[pair[2]] = channelName
			end
			return { ok = true, reason = nil, channelName = channelName }
		end

		local function whisperProjection(userId: number): { WhisperView }
			local rows: { WhisperView } = {}
			local open: { [number]: string } = whispersByUser[userId] or {}
			for otherUserId, channelName in open do
				rows[#rows + 1] = table.freeze({
					userId = otherUserId,
					displayName = memberNameFor(otherUserId) or config.memberFallback(otherUserId),
					channelName = channelName,
				})
			end
			table.sort(rows, function(left: WhisperView, right: WhisperView): boolean
				return left.userId < right.userId
			end)
			return table.freeze(rows)
		end

		local function whisperClose(userId: number): { number }
			local closeWhisper = deps.closeWhisper
			local affected: { number } = {}
			local open: { [number]: string } = whispersByUser[userId] or {}
			for otherUserId, channelName in open do
				local other = whispersByUser[otherUserId]
				if other ~= nil then
					other[userId] = nil
				end
				affected[#affected + 1] = otherUserId
				if closeWhisper ~= nil then
					closeWhisper(channelName)
				end
			end
			whispersByUser[userId] = nil
			table.sort(affected)
			return affected
		end

		return table.freeze({ open = whisperOpen, projection = whisperProjection, close = whisperClose })
	end

	return table.freeze({ create = create })
end

return table.freeze({ configure = configure })
