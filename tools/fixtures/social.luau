--!strict

local Fellowship = require("../../src/core/social/fellowship")
local Formation = require("../../src/core/social/formation")
local Records = require("../../src/roblox/social-records")
local Warband = require("../../src/core/social/warband")

local Social = {}

export type Counters = { writes: number, clock: number }

local REALMS = { realm_a = true, realm_b = true, realm_c = true }
local NAME_IDS = { group_a = true, group_b = true, group_c = true }

local fellowshipSettings: Fellowship.Config = {
	inviteTtlSec = 300,
	maxMembers = 300,
	maxOfficers = 12,
	maxAudit = 8,
	stewardAbsenceSec = 30 * 24 * 60 * 60,
	maxInvites = 16,
	maxReceipts = 64,
	maxTime = 1000000000000,
	maxNameLength = 64,
	realms = REALMS,
	nameIds = NAME_IDS,
	pursuits = {
		exploration = true,
		questing = true,
		dungeons = true,
		crafting_trade = true,
		realm_war = true,
		fellowship_roleplay = true,
	},
	paces = { easygoing = true, steady = true, dedicated = true },
	welcomes = { new_players = true, all_levels = true, experienced = true },
	maxId = 128,
	maxRevision = 1000000000,
	maxFingerprint = 512,
	maxPursuits = 3,
	requiredFounders = 5,
}

local formationSettings: Formation.Config = {
	requiredFounders = 5,
	fee = 1000,
	formationTtlSec = 600,
	maxReceipts = 32,
	maxTime = 1000000000000,
	maxNameLength = 64,
	realms = REALMS,
	nameIds = NAME_IDS,
	fellowshipPrefix = "fellowship:",
	maxFormationId = 100,
	maxId = 128,
	maxRevision = 1000000000,
	maxFingerprint = 512,
}

local warbandCore = Warband.warband({
	maxParties = 20,
	inviteSeconds = 60,
	transferSeconds = 30,
	successionSeconds = 60,
	orders = { Attack = true, Defend = true, Regroup = true, NeedAid = true },
	realms = REALMS,
	maxId = 128,
	maxInteger = 9007199254740991,
	maxAssistants = 2,
})

export type Options = { requiredFounders: number?, fee: number?, store: Records.Store? }

function Social.rig(
	readback: ((unknown) -> unknown)?,
	options: Options?
): (Records.Service, { [string]: unknown }, Counters)
	local guildPolicy = table.clone(fellowshipSettings)
	local formationPolicy = table.clone(formationSettings)
	if options ~= nil then
		guildPolicy.requiredFounders = options.requiredFounders or guildPolicy.requiredFounders
		formationPolicy.requiredFounders = guildPolicy.requiredFounders
		formationPolicy.fee = options.fee or formationPolicy.fee
	end
	local fellowshipCore = Fellowship.fellowship(guildPolicy)
	local formationCore = Formation.formation(formationPolicy)
	local values: { [string]: unknown } = {}
	local counters = { writes = 0, clock = 100 }
	local service = Records.create({
		store = if options and options.store
			then options.store
			else {
				read = function(key: string): Records.Outcome
					return { ok = true, value = values[key], reason = nil }
				end,
				update = function(key: string, transform: (unknown) -> unknown): Records.Outcome
					local nextValue = transform(values[key])
					if nextValue == nil then
						return { ok = false, value = nil, reason = "callback_cancelled" }
					end
					counters.writes += 1
					values[key] = nextValue
					return {
						ok = true,
						value = if readback ~= nil then readback(nextValue) else nextValue,
						reason = nil,
					}
				end,
			},
		keyFor = function(fellowshipId: string): string
			return "fellowship/" .. fellowshipId
		end,
		memberKeyFor = function(userId: number): string
			return "member/" .. tostring(userId)
		end,
		clock = function(): number
			return counters.clock
		end,
		fellowship = fellowshipCore,
		formation = formationCore,
		warband = {
			project = warbandCore.read,
			found = warbandCore.found,
			transition = warbandCore.transition,
		},
	})
	assert(service ~= nil)
	return service, values, counters
end

return table.freeze(Social)
