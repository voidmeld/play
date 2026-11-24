--!strict

export type Inventory = { [unknown]: unknown }
export type Account = { coin: number, inventory: Inventory }
export type Stack = { itemId: string, count: number }
export type Attachments = { coin: number, items: { Stack } }
export type Phase =
	"prepared"
	| "in_transit"
	| "claiming"
	| "returning"
	| "expired"
	| "claimed"
	| "returned"
	| "cancelled"
export type Envelope = {
	id: string,
	senderId: number,
	recipientId: number,
	attachments: Attachments,
	createdAt: number,
	expiresAt: number,
	phase: Phase,
	senderCharacterId: string?,
	recipientCharacterId: string?,
	returnedAt: number?,
}
export type Pointer = { id: string, envelope: Envelope, intent: "hold" | "claim" }
export type Config<T> = {
	maxItems: number,
	maxCount: number,
	maxCoin: number,
	maxUserId: number,
	maxTimestamp: number,
	maxTtl: number,
	itemIdLimit: number,
	requestIdLimit: number,
	characterIdLimit: number,
	maxPointers: number,
	readAccount: (T) -> unknown,
	writeAccount: (T, Account) -> T,
	capacity: (T) -> number,
	entries: (Inventory) -> number,
}
export type Mailbox<T> = {
	attachments: (unknown) -> Attachments?,
	id: (number, unknown) -> string?,
	prepare: (string, number, number, unknown, number, number) -> Envelope?,
	read: (unknown) -> Envelope?,
	valid: (unknown) -> boolean,
	pointers: (unknown) -> { [string]: Pointer }?,
	sameRequest: (unknown, unknown) -> boolean,
	advance: (unknown, string, number?) -> Envelope?,
	debit: (T, Attachments) -> (T?, string?),
	credit: (T, Attachments) -> (T?, string?),
}

local function whole(value: unknown, low: number, high: number): number?
	if type(value) == "number" and value == math.floor(value) and value >= low and value <= high then
		return value
	end
	return nil
end

local function identifier(value: unknown, limit: number): string?
	if type(value) == "string" and #value > 0 and #value <= limit and string.match(value, "^[%w%.%-_:]+$") ~= nil then
		return value
	end
	return nil
end

local function raw(value: unknown): Inventory?
	if type(value) == "table" then
		local out: Inventory = {}
		for key, entry in value do
			out[key] = entry
		end
		return out
	end
	return nil
end

local function exact(value: unknown, fields: { [string]: boolean }): Inventory?
	if type(value) ~= "table" or getmetatable(value) ~= nil then
		return nil
	end
	local found = raw(value)
	if found == nil then
		return nil
	end
	for key in found do
		if type(key) ~= "string" or fields[key] ~= true then
			return nil
		end
	end
	return found
end

local function phase(value: unknown): Phase?
	if
		value == "prepared"
		or value == "in_transit"
		or value == "claiming"
		or value == "returning"
		or value == "expired"
		or value == "claimed"
		or value == "returned"
		or value == "cancelled"
	then
		return value
	end
	return nil
end

local function freezeAttachments(value: Attachments)
	for _, stack in value.items do
		table.freeze(stack)
	end
	table.freeze(value.items)
	table.freeze(value)
end

local Mail = {}

function Mail.mailbox<T>(config: Config<T>): Mailbox<T>
	local function attachments(value: unknown): Attachments?
		local found = exact(value, { coin = true, items = true })
		if found == nil then
			return nil
		end
		local coin = whole(found.coin, 0, config.maxCoin)
		local candidates = raw(found.items)
		if coin == nil or candidates == nil or #candidates > config.maxItems then
			return nil
		end
		local items: { Stack } = {}
		local seen: { [string]: boolean } = {}
		local count = 0
		for key, candidate in candidates do
			count += 1
			local index = whole(key, 1, config.maxItems)
			local stack = exact(candidate, { itemId = true, count = true })
			if index == nil or stack == nil then
				return nil
			end
			local itemId = identifier(stack.itemId, config.itemIdLimit)
			local amount = whole(stack.count, 1, config.maxCount)
			if itemId == nil or amount == nil or seen[itemId] then
				return nil
			end
			seen[itemId] = true
			local normalized: Stack = { itemId = itemId, count = amount }
			items[index] = normalized
		end
		if count ~= #candidates or (coin == 0 and count == 0) then
			return nil
		end
		for index = 1, count do
			if items[index] == nil then
				return nil
			end
		end
		local normalized: Attachments = { coin = coin, items = items }
		freezeAttachments(normalized)
		return normalized
	end

	local function id(senderId: number, requestId: unknown): string?
		local request = identifier(requestId, config.requestIdLimit)
		if whole(senderId, 1, config.maxUserId) == nil or request == nil then
			return nil
		end
		return ("%d:%s"):format(senderId, request)
	end

	local function envelope(value: unknown): Envelope?
		local found = exact(value, {
			id = true,
			senderId = true,
			recipientId = true,
			attachments = true,
			createdAt = true,
			expiresAt = true,
			phase = true,
			senderCharacterId = true,
			recipientCharacterId = true,
			returnedAt = true,
		})
		if found == nil or type(found.id) ~= "string" then
			return nil
		end
		local senderId = whole(found.senderId, 1, config.maxUserId)
		local recipientId = whole(found.recipientId, 1, config.maxUserId)
		local createdAt = whole(found.createdAt, 0, config.maxTimestamp)
		local normalized = attachments(found.attachments)
		local current = phase(found.phase)
		local returnedAt = whole(found.returnedAt, 0, config.maxTimestamp)
		local senderCharacterId = identifier(found.senderCharacterId, config.characterIdLimit)
		local recipientCharacterId = identifier(found.recipientCharacterId, config.characterIdLimit)
		if
			senderId == nil
			or recipientId == nil
			or senderId == recipientId
			or createdAt == nil
			or normalized == nil
			or current == nil
			or id(senderId, string.match(found.id, "^[^:]+:(.+)$") or "") ~= found.id
			or (found.returnedAt ~= nil and returnedAt == nil)
			or (
				(found.senderCharacterId ~= nil or found.recipientCharacterId ~= nil)
				and (senderCharacterId == nil or recipientCharacterId == nil)
			)
		then
			return nil
		end
		local expiresAt = whole(found.expiresAt, createdAt + 1, createdAt + config.maxTtl)
		if expiresAt == nil then
			return nil
		end
		return {
			id = found.id,
			senderId = senderId,
			recipientId = recipientId,
			attachments = normalized,
			createdAt = createdAt,
			expiresAt = expiresAt,
			phase = current,
			senderCharacterId = senderCharacterId,
			recipientCharacterId = recipientCharacterId,
			returnedAt = returnedAt,
		}
	end

	local function account(profile: T): Account?
		local found = raw(config.readAccount(profile))
		if found == nil then
			return nil
		end
		local coin = whole(found.coin, 0, config.maxCoin)
		local inventory = raw(found.inventory)
		if coin == nil or inventory == nil then
			return nil
		end
		return { coin = coin, inventory = inventory }
	end

	return {
		attachments = attachments,
		read = envelope,
		id = id,
		prepare = function(
			mailId: string,
			senderId: number,
			recipientId: number,
			value: unknown,
			now: number,
			ttl: number
		): Envelope?
			local normalized = attachments(value)
			if
				id(senderId, string.match(mailId, "^[^:]+:(.+)$") or "") ~= mailId
				or whole(recipientId, 1, config.maxUserId) == nil
				or senderId == recipientId
				or normalized == nil
				or whole(now, 0, config.maxTimestamp) == nil
				or whole(ttl, 1, config.maxTtl) == nil
			then
				return nil
			end
			return {
				id = mailId,
				senderId = senderId,
				recipientId = recipientId,
				attachments = normalized,
				createdAt = now,
				expiresAt = now + ttl,
				phase = "prepared",
			}
		end,
		valid = function(value: unknown): boolean
			return envelope(value) ~= nil
		end,
		pointers = function(value: unknown): { [string]: Pointer }?
			if type(value) ~= "table" or getmetatable(value) ~= nil then
				return nil
			end
			local found = raw(value)
			if found == nil then
				return nil
			end
			local out: { [string]: Pointer } = {}
			local count = 0
			for mailId, candidate in found do
				count += 1
				local pointer = exact(candidate, { id = true, envelope = true, intent = true })
				if count > config.maxPointers or type(mailId) ~= "string" or pointer == nil or pointer.id ~= mailId then
					return nil
				end
				local mail = envelope(pointer.envelope)
				local intent = pointer.intent
				if mail == nil or mail.id ~= mailId or (intent ~= "hold" and intent ~= "claim") then
					return nil
				end
				out[mailId] = { id = mailId, envelope = mail, intent = intent }
			end
			return out
		end,
		sameRequest = function(first: unknown, second: unknown): boolean
			local a, b = envelope(first), envelope(second)
			if
				a == nil
				or b == nil
				or a.id ~= b.id
				or a.senderId ~= b.senderId
				or a.recipientId ~= b.recipientId
				or a.senderCharacterId ~= b.senderCharacterId
				or a.recipientCharacterId ~= b.recipientCharacterId
				or a.attachments.coin ~= b.attachments.coin
				or #a.attachments.items ~= #b.attachments.items
			then
				return false
			end
			for index, stack in a.attachments.items do
				local other = b.attachments.items[index]
				if stack.itemId ~= other.itemId or stack.count ~= other.count then
					return false
				end
			end
			return true
		end,
		advance = function(value: unknown, action: string, at: number?): Envelope?
			local mail = envelope(value)
			if mail == nil then
				return nil
			end
			local nextPhase: Phase? = if mail.phase == "prepared" and action == "dispatch"
				then "in_transit"
				elseif mail.phase == "prepared" and action == "cancel" then "cancelled"
				elseif mail.phase == "in_transit" and action == "claim" then "claiming"
				elseif mail.phase == "in_transit" and action == "return" then "returning"
				elseif
					mail.phase == "in_transit"
					and action == "expire"
					and whole(at, 0, config.maxTimestamp) ~= nil
				then "expired"
				elseif mail.phase == "expired" and action == "return" then "returning"
				elseif mail.phase == "claiming" and action == "deliver" then "claimed"
				elseif mail.phase == "returning" and action == "restore" then "returned"
				else nil
			if nextPhase == nil then
				return nil
			end
			mail.phase = nextPhase
			if nextPhase == "expired" then
				mail.returnedAt = at
			end
			return mail
		end,
		debit = function(profile: T, value: Attachments): (T?, string?)
			local before = account(profile)
			if before == nil then
				return nil, "profile_invalid"
			end
			if before.coin < value.coin then
				return nil, "coin_insufficient"
			end
			local inventory = table.clone(before.inventory)
			for _, stack in value.items do
				local count = whole(inventory[stack.itemId] or 0, 0, config.maxCount)
				if count == nil or count < stack.count then
					return nil, "goods_insufficient"
				end
				inventory[stack.itemId] = if count == stack.count then nil else count - stack.count
			end
			return config.writeAccount(profile, { coin = before.coin - value.coin, inventory = inventory }), nil
		end,
		credit = function(profile: T, value: Attachments): (T?, string?)
			local before = account(profile)
			if before == nil then
				return nil, "profile_invalid"
			end
			if before.coin + value.coin > config.maxCoin then
				return nil, "coin_overflow"
			end
			local inventory = table.clone(before.inventory)
			local entries = 0
			for itemId, count in inventory do
				if type(itemId) ~= "string" or whole(count, 1, config.maxCount) == nil then
					return nil, "inventory_invalid"
				end
				entries += 1
			end
			for _, stack in value.items do
				local count = whole(inventory[stack.itemId] or 0, 0, config.maxCount)
				if count == nil or count + stack.count > config.maxCount then
					return nil, "stack_full"
				end
				if count == 0 then
					entries += 1
				end
				inventory[stack.itemId] = count + stack.count
			end
			if entries > math.max(config.entries(before.inventory), config.capacity(profile)) then
				return nil, "inventory_full"
			end
			return config.writeAccount(profile, { coin = before.coin + value.coin, inventory = inventory }), nil
		end,
	}
end

return Mail
