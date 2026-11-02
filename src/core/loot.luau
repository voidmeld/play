--!strict

local Decision = require("./loot/decision")
local Roll = require("./loot/roll")

export type DecisionChoice = Decision.Choice
export type DecisionSeat = Decision.Seat
export type DecisionResult = Decision.Result
export type DecisionDecision = Decision.Decision
export type DecisionRefusal = Decision.Refusal
export type DecisionConfig = Decision.Config
export type RollRoll = Roll.Roll
export type RollTable = Roll.Table
export type RollDrop = Roll.Drop
export type RollConfig = Roll.Config

export type API = {
	read decision: typeof(Decision),
	read roll: typeof(Roll),
}

local api: API = {
	decision = Decision,
	roll = Roll,
}

return table.freeze(api)
