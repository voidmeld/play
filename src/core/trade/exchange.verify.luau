--!strict

local Exchange = require("./exchange")
local settings: Exchange.Config = {
	maxItems = 8,
	maxCount = 9999,
	maxCoin = 1000000000,
	maxUserId = 9007199254740991,
	maxRevision = 1000000,
	idLimit = 96,
}
local Core = Exchange.exchange(settings)
local Verify = require("../../../.lute/dependencies/verify/src/core")

return function(suite: Verify.Harness)
	do
		suite:case("resets both locks and confirmations whenever an offer changes", function(context)
			local state = assert(Core.empty("trade-1", 11, 20))
			state = assert(
				Core.step(
					state,
					11,
					{ kind = "offer", revision = 0, offer = { coin = 5, items = { { itemId = "ore", count = 2 } } } }
				)
			)
			context:expect(state.revision):toBe(1)
			state = assert(Core.step(state, 11, { kind = "lock", revision = 1 }))
			state = assert(Core.step(state, 20, { kind = "lock", revision = 1 }))
			context:expect(state.phase):toBe("locked")
			state = assert(Core.step(state, 11, { kind = "confirm", revision = 1 }))
			state = assert(Core.step(state, 20, { kind = "offer", revision = 1, offer = { coin = 7, items = {} } }))
			context:expect(state.phase):toBe("open")
			context:expect(state.revision):toBe(2)
			context:expect((next(state.locks))):toBeNil()
			context:expect((next(state.confirms))):toBeNil()
			context:expect((Core.step(state, 11, { kind = "confirm", revision = 1 }))):toBeNil()
		end)

		suite:case("requires matching revisions, two locks and two confirms before settlement", function(context)
			local state = assert(Core.empty("trade-2", 11, 20))
			context:expect((Core.step(state, 21, { kind = "lock", revision = 0 }))):toBeNil()
			context:expect((Core.step(state, 11, { kind = "confirm", revision = 0 }))):toBeNil()
			context:expect((Core.settled(state))):toBeNil()
			state = assert(Core.step(state, 11, { kind = "lock", revision = 0 }))
			state = assert(Core.step(state, 20, { kind = "lock", revision = 0 }))
			state = assert(Core.step(state, 11, { kind = "confirm", revision = 0 }))
			state = assert(Core.step(state, 20, { kind = "confirm", revision = 0 }))
			context:expect(state.phase):toBe("confirmed")
			state = assert(Core.settled(state))
			context:expect(state.phase):toBe("settled")
			context
				:expect((Core.step(state, 11, { kind = "offer", revision = 0, offer = { coin = 0, items = {} } })))
				:toBeNil()
		end)

		suite:case("refuses malformed, fractional, duplicate and oversized offers", function(context)
			for _, value in
				{
					{ coin = -1, items = {} },
					{ coin = math.huge - math.huge, items = {} },
					{ coin = 0, items = { { itemId = "ore", count = 1.5 } } },
					{ coin = 0, items = { { itemId = "ore", count = 1 }, { itemId = "ore", count = 1 } } },
					{ coin = 0, items = { { itemId = "ore", count = 10000 } } },
					{ coin = 0, items = {}, extra = true },
				}
			do
				context:expect((Core.offer(value))):toBeNil()
			end
		end)
	end

	suite:case("uses configured offer, identity and revision bounds", function(context)
		local core =
			Exchange.exchange({ maxItems = 1, maxCount = 2, maxCoin = 3, maxUserId = 4, maxRevision = 1, idLimit = 2 })
		context:expect(core.offer({ coin = 3, items = { { itemId = "ab", count = 2 } } }) ~= nil):toBe(true)
		context:expect(core.offer({ coin = 4, items = {} })):toBeNil()
		context:expect(core.offer({ coin = 0, items = { { itemId = "ab", count = 3 } } })):toBeNil()
		context:expect(core.offer({ coin = 0, items = { { itemId = "abc", count = 1 } } })):toBeNil()
		context
			:expect(core.offer({ coin = 0, items = { { itemId = "a", count = 1 }, { itemId = "b", count = 1 } } }))
			:toBeNil()
		context:expect(core.offer({ coin = 0, items = {} }) ~= nil):toBe(true)
		context:expect(core.empty("abc", 1, 4)):toBeNil()
		context:expect(core.empty("ab", 1, 5)):toBeNil()
		context:expect(core.empty("ab", 1, 1)):toBeNil()
		local state = assert(core.empty("ab", 1, 4))
		local updated = assert(core.step(state, 1, { kind = "offer", revision = 0, offer = { coin = 1, items = {} } }))
		context:expect(state.revision):toBe(0)
		local rejected, reason =
			core.step(updated, 1, { kind = "offer", revision = 1, offer = { coin = 1, items = {} } })
		context:expect(rejected):toBeNil()
		context:expect(reason):toBe("offer_invalid")
		rejected, reason = core.step(updated, 1, { kind = "lock", revision = 2 })
		context:expect(rejected):toBeNil()
		context:expect(reason):toBe("revision_stale")
		local cancelled = assert(core.step(updated, 1, { kind = "cancel", revision = 1 }))
		context:expect(cancelled.phase):toBe("cancelled")
		context:expect((core.step(cancelled, 4, { kind = "lock", revision = 1 }))):toBeNil()
	end)
end
