--!strict

local Diminishing = require("./control/diminishing")

export type DiminishingBucket = Diminishing.Bucket
export type DiminishingState = Diminishing.State
export type DiminishingCategory = Diminishing.Category
export type DiminishingConfig = Diminishing.Config
export type DiminishingStep = Diminishing.Step
export type DiminishingResult = Diminishing.Result

export type API = {
	read diminishing: typeof(Diminishing),
}

local api: API = {
	diminishing = Diminishing,
}

return table.freeze(api)
