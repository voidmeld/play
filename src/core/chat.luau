--!strict

local Channels = require("./chat/channels")

export type ChannelsMember = Channels.Member
export type ChannelsAudience = Channels.Audience
export type ChannelsRule = Channels.Rule
export type ChannelsBucket = Channels.Bucket
export type ChannelsBudget = Channels.Budget

export type API = {
	read channels: typeof(Channels),
}

local api: API = {
	channels = Channels,
}

return table.freeze(api)
