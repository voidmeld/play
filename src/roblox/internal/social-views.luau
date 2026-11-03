--!strict

local FellowshipTypes = require("../../core/social/fellowship")
export type FormationInviteView = { read formationId: string, read nameId: string, read proposerName: string }
export type FounderView = { read userId: number, read displayName: string }
export type FellowshipMemberView = {
	read userId: number,
	read displayName: string,
	read steward: boolean,
	read officer: boolean,
	read present: boolean,
	read canRemove: boolean,
	read canPromote: boolean,
	read canAppoint: boolean,
	read canDemote: boolean,
}
export type StewardAuditView = { read userId: number, read fromUserId: number, read atSec: number }
export type WhisperView = { read userId: number, read displayName: string, channelName: string }
export type PendingFellowshipInviteView = {
	read fellowshipId: string,
	read nameId: string | false,
	read creed: FellowshipTypes.CreedDraft | false,
	read inviterDisplayName: string,
}
export type RallyJoinResult = { ok: false, reason: string } | { ok: true, objectiveId: string, replayed: boolean }

export type ActiveFormationView = {
	read active: boolean,
	read incoming: FormationInviteView | false,
	read feeCopper: number,
	read phase: string,
	read formationId: string?,
	read nameId: string,
	read founders: { FounderView },
	read invitedCount: number,
	read needed: number,
	read expiresAtSec: number,
	read feeState: string,
	read isProposer: boolean,
	read canComplete: boolean,
}
export type FormationView = {
	read active: false,
	read phase: string?,
	read incoming: FormationInviteView | false,
	read feeCopper: number,
} | ActiveFormationView
export type FellowshipView = {
	read fellowshipId: string,
	read nameId: string,
	read realmId: string,
	read home: { read slotId: string, read label: string | false },
	read foundedAtSec: number,
	read stewardUserId: number,
	read viewerUserId: number,
	read isSteward: boolean,
	read isOfficer: boolean,
	read creed: FellowshipTypes.CreedDraft | false,
	read canSetCreed: boolean,
	read canClaim: boolean,
	read audit: { StewardAuditView },
	read revision: number,
	read members: { FellowshipMemberView },
}

return table.freeze({})
