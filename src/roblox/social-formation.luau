--!strict

local FellowshipFormationCoreTypes = require("../core/social/formation")
local GroupCoreTypes = require("../core/social/group")
local Homes = require("../core/social/guildhome")
local RecordsTypes = require("./social-records")
local SocialHost = require("./social-host")
local Transfer = require("./profile-transfer")
local Value = require("../kernel/value")
local Views = require("./internal/social-views")

export type FeePort = {
	read hold: (number, string) -> Transfer.Result,
	read commit: (number, string) -> Transfer.Result,
	read refund: (number, string) -> Transfer.Result,
}
export type FormationInviteView = Views.FormationInviteView
export type FounderView = Views.FounderView
export type ActiveFormationView = Views.ActiveFormationView
export type FormationView = Views.FormationView

type RecordService = RecordsTypes.Service
type FormationState = FellowshipFormationCoreTypes.State
export type FormationResponse = {
	read ok: boolean,
	read state: FormationState?,
	read replayed: boolean,
	read reason: string?,
	read fellowshipId: string?,
}
export type Dependencies = {
	read fellowshipRecords: RecordService?,
	read realmFor: (number) -> string?,
	read clock: () -> number,
	read guildHomeCatalog: (() -> unknown)?,
	read relationsFor: ((number, { number }, number) -> GroupCoreTypes.Relations?)?,
	read guildFee: FeePort?,
}

export type Service = {
	read start: (number, string) -> FormationResponse,
	read invite: (number, number) -> FormationResponse,
	read answer: (number, string) -> FormationResponse,
	read complete: (number) -> FormationResponse,
	read projection: (number) -> FormationView | false,
	read settle: (number) -> FormationResponse,
}

export type Config = {
	read slotFor: (unknown, unknown) -> Homes.Slot?,
	read admit: (unknown, unknown, unknown, GroupCoreTypes.Authority?) -> GroupCoreTypes.Decision,
	read requiredFounders: number,
	read fee: number,
	read proposerFallback: string,
}
export type API = {
	read create: (Dependencies, SocialHost.Host, (number) -> string?, () -> string, (string) -> ()) -> Service,
}
local function configure(config: Config): API
	config = table.freeze(table.clone(config))
	assert(Value.whole(config.requiredFounders, 1, 9007199254740991) ~= nil, "invalid founder bound")
	assert(Value.whole(config.fee, 0, 9007199254740991) ~= nil, "invalid formation fee")
	local GuildHomeCore = { slotFor = config.slotFor }
	local GroupCore = { admit = config.admit }

	local function create(
		deps: Dependencies,
		host: SocialHost.Host,
		memberNameFor: (number) -> string?,
		newEventId: () -> string,
		notifyFellowship: (string) -> ()
	): Service
		local serially = host.serially
		local settle = host.settle
		local membershipOf = host.membershipOf
		local formationInviteByUser: { [number]: { formationId: string, proposerId: number } } = {}
		local formationOfUser: { [number]: string } = {}

		local function formationRefusal(reason: string): FellowshipFormationCoreTypes.Result
			return { ok = false, state = nil, replayed = false, reason = reason }
		end

		local function formationReady(): boolean
			return deps.fellowshipRecords ~= nil and deps.guildFee ~= nil
		end

		local function formationApply(formationId: string, event: FellowshipFormationCoreTypes.EventDraft)
			event.eventId = event.eventId or newEventId()
			return assert(deps.fellowshipRecords).applyFormation(formationId, event)
		end

		local function formationRead(formationId: string)
			return assert(deps.fellowshipRecords).readFormation(formationId)
		end

		local function refundSettled(result: Transfer.Result): boolean
			return result.ok or (result.outcome == "rejected" and result.reason == "fee_not_held")
		end
		local function settleFormationFee(formationId: string, state: FormationState): boolean
			local fee = assert(deps.guildFee)
			local proposerId = state.initiatorId
			if state.phase == "completed" then
				local committed = fee.commit(proposerId, formationId)
				return committed.ok == true
			end
			if state.phase ~= "cancelled" then
				return true
			end
			if state.feeState == "refunded" then
				return true
			end
			local refunded = fee.refund(proposerId, formationId)
			if not refundSettled(refunded) then
				return false
			end
			if state.feeState == "held" then
				local marked = formationApply(formationId, { kind = "fee_refunded", expectedRevision = state.revision })
				if not marked.ok and marked.reason ~= "nothing_to_refund" and marked.reason ~= "revision_conflict" then
					return false
				end
			end
			return true
		end

		local function settleFormation(proposerId: number): FormationResponse
			if not formationReady() then
				return formationRefusal("formation_unavailable")
			end
			local pointer = assert(deps.fellowshipRecords).readProposerFormation(proposerId)
			if not pointer.ok or pointer.formationId == nil then
				return { ok = true, state = nil, replayed = false, reason = nil }
			end
			local formationId: string = pointer.formationId
			local read = formationRead(formationId)
			if not read.ok then
				if read.reason == "formation_unknown" then
					local fee = assert(deps.guildFee)
					local refunded = fee.refund(proposerId, formationId)
					if not refundSettled(refunded) then
						return formationRefusal(refunded.reason or "fee_unavailable")
					end
					local cleared = assert(deps.fellowshipRecords).clearProposerFormation(proposerId, formationId)
					if not cleared.ok then
						return formationRefusal(cleared.reason or "formation_unavailable")
					end
					return { ok = true, state = nil, replayed = false, reason = nil }
				end
				return read
			end
			local state = read.state
			if state.phase == "forming" and deps.clock() >= state.expiresAtSec then
				local swept = formationApply(formationId, { kind = "sweep", expectedRevision = state.revision })
				if swept.ok and swept.state ~= nil then
					state = swept.state
				else
					state = formationRead(formationId).state or state
				end
			end
			if state.phase == "forming" then
				return { ok = true, state = state, replayed = false, reason = nil }
			end
			if state.phase == "completed" and state.feeState == "consumed" then
				if state.fellowshipId ~= nil then
					local founded = assert(deps.fellowshipRecords).read(state.fellowshipId)
					if not founded.ok and founded.reason == "fellowship_unknown" then
						assert(deps.fellowshipRecords).foundFromFormation(state)
					end
				end
			end
			if settleFormationFee(formationId, state) then
				assert(deps.fellowshipRecords).clearProposerFormation(proposerId, formationId)
				for _, userId in state.founders do
					formationOfUser[userId.userId] = nil
				end
			end
			return { ok = true, state = state, replayed = false, reason = nil }
		end

		local function startFormation(actorUserId: number, nameId: string): FormationResponse
			if not formationReady() then
				return formationRefusal("formation_unavailable")
			end
			return serially(actorUserId, function(): FormationResponse
				local realmId = deps.realmFor(actorUserId)
				local name = memberNameFor(actorUserId)
				if realmId == nil or name == nil or settle(actorUserId) ~= nil then
					return formationRefusal("creation_denied")
				end
				local slot = if deps.guildHomeCatalog ~= nil
					then GuildHomeCore.slotFor(deps.guildHomeCatalog(), realmId)
					else nil
				if slot == nil then
					return formationRefusal("charter_requires_home_hub")
				end
				local records = assert(deps.fellowshipRecords)
				local settled = settleFormation(actorUserId)
				local existing = records.readProposerFormation(actorUserId)
				if not settled.ok or (existing.ok and existing.formationId ~= nil) then
					return formationRefusal(
						if settled.state ~= nil and settled.state.phase == "forming"
							then "formation_active"
							else "formation_settling"
					)
				end
				local formationId = newEventId()
				local pointed = records.setProposerFormation(actorUserId, formationId)
				if not pointed.ok then
					return formationRefusal("formation_unavailable")
				end
				local fee = assert(deps.guildFee)
				local held = fee.hold(actorUserId, formationId)
				if not held.ok then
					if held.outcome == "rejected" then
						records.clearProposerFormation(actorUserId, formationId)
					end
					return formationRefusal(held.reason or "fee_unavailable")
				end
				local started = records.startFormation({
					formationId = formationId,
					nameId = nameId,
					realmId = realmId,
					homeSlotId = slot.id,
					initiatorId = actorUserId,
					initiatorName = name,
				})
				if not started.ok then
					local refunded = fee.refund(actorUserId, formationId)
					if refundSettled(refunded) then
						records.clearProposerFormation(actorUserId, formationId)
					end
					return started
				end
				local marked = formationApply(formationId, {
					kind = "fee_held",
					expectedRevision = started.state.revision,
					actorUserId = actorUserId,
				})
				if not marked.ok then
					return marked
				end
				formationOfUser[actorUserId] = formationId
				return marked
			end)
		end

		local function formationOfProposer(actorUserId: number): (string?, FormationState?)
			local pointer = assert(deps.fellowshipRecords).readProposerFormation(actorUserId)
			if not pointer.ok or pointer.formationId == nil then
				return nil, nil
			end
			local read = formationRead(pointer.formationId)
			return pointer.formationId, if read.ok then read.state else nil
		end

		local function formationRelations(userId: number, others: { number }, nowSec: number): GroupCoreTypes.Relations?
			if deps.relationsFor == nil then
				return nil
			end
			return deps.relationsFor(userId, others, nowSec)
		end

		local function formationInvite(actorUserId: number, targetUserId: number): FormationResponse
			if not formationReady() then
				return formationRefusal("formation_unavailable")
			end
			return serially(actorUserId, function(): FormationResponse
				local formationId, state = formationOfProposer(actorUserId)
				if formationId == nil or state == nil or state.phase ~= "forming" then
					return formationRefusal("formation_unknown")
				end
				if deps.realmFor(targetUserId) ~= state.realmId or memberNameFor(targetUserId) == nil then
					return formationRefusal("realm_mismatch")
				end
				if membershipOf(targetUserId, true) ~= nil then
					return formationRefusal("already_member")
				end
				local nowSec = deps.clock()
				local memberRelations: { GroupCoreTypes.Relations } = {}
				local memberIds: { number } = {}
				for _, founder in state.founders do
					memberIds[#memberIds + 1] = founder.userId
					local relations = formationRelations(founder.userId, { targetUserId }, nowSec)
					if relations ~= nil then
						memberRelations[#memberRelations + 1] = relations
					end
				end
				local decision = GroupCore.admit(
					{ members = memberRelations, subject = formationRelations(targetUserId, memberIds, nowSec) },
					{ groupId = formationId, inviterUserId = actorUserId, candidateUserId = targetUserId },
					nowSec,
					{
						validate = function(
							groupId: string,
							operation: string,
							inviter: number,
							candidate: number,
							_at: number
						): boolean
							return groupId == formationId
								and operation == "admit"
								and inviter == state.initiatorId
								and deps.realmFor(inviter) == state.realmId
								and deps.realmFor(candidate) == state.realmId
						end,
					}
				)
				if not decision.ok then
					return formationRefusal(assert(decision.reason))
				end
				local result = formationApply(formationId, {
					kind = "invite",
					expectedRevision = state.revision,
					actorUserId = actorUserId,
					targetUserId = targetUserId,
					targetRealmId = state.realmId,
				})
				if result.ok then
					formationInviteByUser[targetUserId] = { formationId = formationId, proposerId = actorUserId }
				end
				return result
			end)
		end

		local function formationAnswer(actorUserId: number, kind: string): FormationResponse
			if not formationReady() then
				return formationRefusal("formation_unavailable")
			end
			return serially(actorUserId, function(): FormationResponse
				local pending = formationInviteByUser[actorUserId]
				local formationId = if kind == "withdraw"
					then formationOfUser[actorUserId] or (if pending ~= nil then pending.formationId else nil)
					else (if pending ~= nil then pending.formationId else nil)
				if formationId == nil then
					return formationRefusal("invite_unknown")
				end
				local read = formationRead(formationId)
				if not read.ok then
					return read
				end
				local state = read.state
				local event: FellowshipFormationCoreTypes.EventDraft =
					{ kind = kind, expectedRevision = state.revision, actorUserId = actorUserId }
				if kind == "consent" then
					local name = memberNameFor(actorUserId)
					if name == nil or settle(actorUserId) ~= nil then
						return formationRefusal("already_member")
					end
					event.actorRealmId = deps.realmFor(actorUserId)
					event.actorName = name
				end
				local result = formationApply(formationId, event)
				if not result.ok then
					return result
				end
				if kind == "consent" then
					formationOfUser[actorUserId] = formationId
					formationInviteByUser[actorUserId] = nil
				else
					formationInviteByUser[actorUserId] = nil
					formationOfUser[actorUserId] = nil
					settleFormation(result.state.initiatorId)
				end
				return result
			end)
		end

		local function completeFormation(actorUserId: number): FormationResponse
			if not formationReady() then
				return formationRefusal("formation_unavailable")
			end
			return serially(actorUserId, function(): FormationResponse
				local records = assert(deps.fellowshipRecords)
				local formationId, state = formationOfProposer(actorUserId)
				if formationId == nil or state == nil then
					return formationRefusal("formation_unknown")
				end
				if state.phase == "forming" and #state.founders == config.requiredFounders then
					local claimed: { number } = {}
					for _, founder in state.founders do
						local claim = records.claimMembership(founder.userId, state.fellowshipId)
						if not claim.ok then
							for _, userId in claimed do
								local held = records.readMembership(userId)
								if held.ok and held.membership ~= nil then
									records.releaseMembership(userId, held.membership)
								end
							end
							return formationRefusal("founder_unavailable")
						end
						claimed[#claimed + 1] = founder.userId
					end
					local done = formationApply(formationId, {
						kind = "complete",
						expectedRevision = state.revision,
						actorUserId = actorUserId,
					})
					if not done.ok then
						return done
					end
					state = done.state
				end
				if state.phase ~= "completed" then
					return formationRefusal(if state.phase == "forming" then "founders_missing" else "formation_closed")
				end
				local founded = records.foundFromFormation(state)
				if not founded.ok and founded.reason ~= "fellowship_exists" then
					return founded
				end
				for _, founder in state.founders do
					local confirmed = records.confirmMembership(founder.userId, state.fellowshipId)
					if confirmed.ok and confirmed.membership ~= nil then
						host.adopt(founder.userId, confirmed.membership)
					end
				end
				settleFormation(actorUserId)
				notifyFellowship(state.fellowshipId)
				return { ok = true, state = state, replayed = false, reason = nil, fellowshipId = state.fellowshipId }
			end)
		end

		local function formationProjection(userId: number): FormationView | false
			if not formationReady() then
				return false
			end
			local formationId: string? = formationOfUser[userId]
			local state: FormationState? = nil
			if formationId == nil then
				local ownId, ownState = formationOfProposer(userId)
				formationId, state = ownId, ownState
			else
				local read = formationRead(formationId)
				state = if read.ok then read.state else nil
			end
			local invite = formationInviteByUser[userId]
			local incoming: FormationInviteView | false = false
			if invite ~= nil then
				local read = formationRead(invite.formationId)
				if read.ok and read.state.phase == "forming" then
					incoming = table.freeze({
						formationId = invite.formationId,
						nameId = read.state.nameId,
						proposerName = memberNameFor(invite.proposerId) or config.proposerFallback,
					})
				end
			end
			if state == nil then
				local empty: FormationView = { active = false, incoming = incoming, feeCopper = config.fee }
				return table.freeze(empty)
			end
			local founders: { FounderView } = {}
			for _, founder in state.founders do
				founders[#founders + 1] = table.freeze({ userId = founder.userId, displayName = founder.name })
			end
			return table.freeze({
				active = state.phase == "forming",
				phase = state.phase,
				formationId = formationId,
				nameId = state.nameId,
				founders = table.freeze(founders),
				invitedCount = #state.invited,
				needed = config.requiredFounders - #state.founders,
				expiresAtSec = state.expiresAtSec,
				feeCopper = config.fee,
				feeState = state.feeState,
				isProposer = state.initiatorId == userId,
				canComplete = state.initiatorId == userId
					and state.phase == "forming"
					and #state.founders == config.requiredFounders,
				incoming = incoming,
			})
		end

		return table.freeze({
			start = startFormation,
			invite = formationInvite,
			answer = formationAnswer,
			complete = completeFormation,
			projection = formationProjection,
			settle = settleFormation,
		})
	end

	return table.freeze({ create = create })
end

return table.freeze({ configure = configure })
