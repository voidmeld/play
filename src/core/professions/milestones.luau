--!strict

local Value = require("../../kernel/value")

export type Receipt = { characterId: string, transactionId: string, eventKind: string }
export type Definition = { transactionId: string, eventKind: string }
export type Config = { [string]: Definition }
export type State = { [string]: Receipt }

local Milestones = {}

function Milestones.create(config: Config)
	local definitions: Config = {}
	local fields: { [string]: boolean } = {}
	local transactions: { [string]: boolean } = {}
	for name, definition in config do
		assert(Value.identifier(name, 128) ~= nil, "invalid milestone name")
		assert(Value.identifier(definition.transactionId, 128) ~= nil, "invalid milestone transaction")
		assert(Value.identifier(definition.eventKind, 128) ~= nil, "invalid milestone event")
		assert(not transactions[definition.transactionId], "duplicate milestone transaction")
		transactions[definition.transactionId] = true
		fields[name] = true
		definitions[name] = table.clone(definition)
	end
	local function receipt(characterId: string, name: string): Receipt
		assert(characterId ~= "", "character required")
		local definition = assert(definitions[name], "unknown milestone")
		return { characterId = characterId, transactionId = definition.transactionId, eventKind = definition.eventKind }
	end
	local function normalize(raw: unknown, characterId: unknown): State?
		local source = Value.record(raw, fields)
		if source == nil or type(characterId) ~= "string" or characterId == "" then
			return nil
		end
		local result: State = {}
		for name, value in source do
			if type(name) ~= "string" then
				return nil
			end
			local saved = Value.record(value, { characterId = true, transactionId = true, eventKind = true }, true)
			local expected = receipt(characterId, name)
			if
				saved == nil
				or saved.characterId ~= expected.characterId
				or saved.transactionId ~= expected.transactionId
				or saved.eventKind ~= expected.eventKind
			then
				return nil
			end
			result[name] = expected
		end
		return result
	end
	return table.freeze({ receipt = receipt, normalize = normalize })
end

return table.freeze(Milestones)
