--!strict

local Bdd = require("../../../.lute/dependencies/verify/src/bdd")
local Codec = require("../../kernel/codec")
local Scene = require("../../../tools/fixtures/combat")
local Value = require("../../kernel/value")
local Verify = require("../../../.lute/dependencies/verify/src/core")
return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect
	describe("admitted contact lifetime", function()
		it("copies and freezes identities and opaque payload without freezing caller data", function()
			local r = Scene.new()
			local input = r.admission()
			local admitted = r.rules.admit(input)
			assert(admitted.ok)
			input.source.epoch = 9
			input.payload.tags.glyph = 99
			expect(admitted.value.plan.source.epoch):toBe(1)
			expect(admitted.value.plan.payload.tags.glyph):toBe(4)
			expect(table.isfrozen(input)):toBe(false)
			expect(table.isfrozen(admitted.value.plan.payload.tags)):toBe(true)
			local changed = pcall(function()
				admitted.value.plan.payload.tags.glyph = 100
			end)
			expect(changed):toBe(false)
		end)
		it("rejects malformed admission snapshots clocks phases tokens and cyclic payloads", function()
			local r = Scene.new()
			expect(r.rules.admit(nil).ok):toBe(false)
			for _, raw in { false, 3, "plan", setmetatable({}, {}) } do
				expect(r.rules.admit(raw).ok):toBe(false)
			end
			for _, field in { "sequence", "startedTick", "anticipationSec", "contactSec", "recoverySec", "rangeStuds" } do
				for _, bad in { -1, math.huge, math.nan, "bad" } do
					local input = assert(Value.raw(r.admission()))
					input[field] = bad
					expect(r.rules.admit(input).ok):toBe(false)
				end
			end
			for _, field in { "source", "target", "equipmentToken", "payload" } do
				local input = assert(Value.raw(r.admission()))
				input[field] = false
				expect(r.rules.admit(input).ok):toBe(false)
			end
			local cyclic: { [string]: unknown } = {}
			cyclic.self = cyclic
			local input = assert(Value.raw(r.admission()))
			input.payload = cyclic
			expect(r.rules.admit(input).ok):toBe(false)
		end)
		it("skips the admitted tick and repeated clock delivery at the exact epsilon boundary", function()
			local r = Scene.new()
			local admitted = r.rules.admit(r.admission())
			assert(admitted.ok)
			local skipped = r.rules.advance(admitted.value, { tick = 10, dt = 100, source = r.source() })
			expect(skipped.status):toBe("waiting")
			expect(assert(skipped.next).elapsedSec):toBe(0)
			local before = r.rules.advance(admitted.value, { tick = 11, dt = 0.25 - 2e-6, source = r.source() })
			expect(before.status):toBe("waiting")
			local reached = r.rules.advance(admitted.value, { tick = 11, dt = 0.25 - 1e-6, source = r.source() })
			expect(reached.status):toBe("contact")
			local repeated = r.rules.advance(reached.next, { tick = 11, dt = 100, source = r.source() })
			expect(repeated.status):toBe("waiting")
			expect(assert(repeated.next).elapsedSec):toBe(assert(reached.next).elapsedSec)
			expect(admitted.value.elapsedSec):toBe(0)
		end)
		it("reserves once resolves once and finishes recovery without a repeated consequence", function()
			local r = Scene.new()
			local admitted = r.rules.admit(r.admission())
			assert(admitted.ok)
			local reached = r.rules.advance(admitted.value, { tick = 11, dt = 0.25, source = r.source() })
			assert(reached.next)
			expect(reached.next.contacted):toBe(false)
			local parked = r.rules.advance(reached.next, { tick = 12, dt = 0, source = r.source() })
			expect(parked.status):toBe("waiting")
			local resolved = r.rules.resolve(parked.next, r.observation())
			expect(resolved.status):toBe("contact")
			expect(assert(resolved.next).contacted):toBe(true)
			expect(r.rules.resolve(resolved.next, r.observation()).reason):toBe("contact_not_reserved")
			local recovery = r.rules.advance(resolved.next, { tick = 13, dt = 0.1, source = r.source() })
			expect(recovery.status):toBe("waiting")
			local done = r.rules.advance(recovery.next, { tick = 14, dt = 0.2, source = r.source() })
			expect(done.status):toBe("complete")
			expect(done.next):toBe(nil)
		end)
		it("contacts once across oversized and zero-length phases", function()
			for _, duration in { 0, 100 } do
				local r = Scene.new()
				local input = r.admission()
				if duration == 0 then
					input.anticipationSec, input.contactSec, input.recoverySec = 0, 0, 0
				end
				local admitted = r.rules.admit(input)
				assert(admitted.ok)
				local contact = r.rules.advance(admitted.value, { tick = 11, dt = duration, source = r.source() })
				expect(contact.status):toBe("contact")
				local resolved = r.rules.resolve(contact.next, r.observation())
				expect(resolved.status):toBe("contact")
				expect(resolved.next):toBe(nil)
			end
		end)
		it("cancels source identity epoch equipment liveness and control invalidation before and at contact", function()
			for _, fault in { "id", "characterId", "epoch", "equipmentToken", "alive", "blocked" } do
				local r = Scene.new()
				local admitted = r.rules.admit(r.admission())
				assert(admitted.ok)
				local source = assert(Value.raw(r.source()))
				if fault == "id" or fault == "characterId" or fault == "epoch" then
					local id = assert(Value.raw(source.identity))
					id[fault] = if fault == "epoch" then 9 else "replacement"
					source.identity = id
				else
					source[fault] = if fault == "equipmentToken" then "replacement" else fault == "blocked"
				end
				expect(r.rules.advance(admitted.value, { tick = 11, dt = 1, source = source }).status):toBe("cancelled")
				local reached = r.rules.advance(admitted.value, { tick = 11, dt = 1, source = r.source() })
				local observation = assert(Value.raw(r.observation()))
				observation.source = source
				expect(r.rules.resolve(reached.next, observation).status):toBe("cancelled")
			end
		end)
		it("cancels replaced dead removed or differently-authored targets", function()
			for _, fault in { "id", "characterId", "epoch", "contentId", "alive", "missing" } do
				local r = Scene.new()
				local admitted = r.rules.admit(r.admission())
				assert(admitted.ok)
				local reached = r.rules.advance(admitted.value, { tick = 11, dt = 0.25, source = r.source() })
				local observation = assert(Value.raw(r.observation()))
				local target = assert(Value.raw(observation.target))
				if fault == "alive" then
					target.alive = false
				elseif fault == "missing" then
					target = {}
				else
					local id = assert(Value.raw(target.identity))
					id[fault] = if fault == "epoch" then 8 else "replacement"
					target.identity = id
				end
				observation.target = target
				expect(r.rules.resolve(reached.next, observation).status):toBe("cancelled")
			end
		end)
		it("misses malformed blocked nonfinite negative distant or refused current spatial evidence", function()
			for _, bad in
				{
					false,
					"missing",
					{},
					{ clear = false, distanceStuds = 3 },
					{ clear = true, distanceStuds = -1 },
					{ clear = true, distanceStuds = math.nan },
					{ clear = true, distanceStuds = math.huge },
					{ clear = true, distanceStuds = 5 },
				}
			do
				local r = Scene.new()
				local admitted = r.rules.admit(r.admission())
				assert(admitted.ok)
				local contact = r.rules.advance(admitted.value, { tick = 11, dt = 0.25, source = r.source() })
				local observation = assert(Value.raw(r.observation()))
				observation.spatial = if bad == "missing" then nil else bad
				local missed = r.rules.resolve(contact.next, observation)
				expect(missed.status):toBe("missed")
				expect(assert(missed.next).contacted):toBe(true)
			end
			for _, field in { "distanceStuds", "allowed" } do
				local r = Scene.new()
				local admitted = r.rules.admit(r.admission())
				assert(admitted.ok)
				local contact = r.rules.advance(admitted.value, { tick = 11, dt = 0.25, source = r.source() })
				local observation = assert(Value.raw(r.observation()))
				observation[field] = false
				expect(r.rules.resolve(contact.next, observation).status):toBe("missed")
			end
		end)
		it("requires an explicit self-contact exemption and never exempts another identity", function()
			for _, self in { false, true } do
				for _, exempt in { false, true } do
					local r = Scene.new()
					local input = r.admission()
					if self then
						input.target = input.source
					end
					local admitted = r.rules.admit(input)
					assert(admitted.ok)
					local reached = r.rules.advance(admitted.value, { tick = 11, dt = 0.25, source = r.source() })
					local observation = assert(Value.raw(r.observation()))
					observation.target = { identity = input.target, alive = true }
					observation.spatial, observation.spatialExempt = nil, exempt
					expect(r.rules.resolve(reached.next, observation).status):toBe(
						if self and exempt then "contact" else "missed"
					)
				end
			end
		end)
		it("rejects forged plans states premature contacts and invalid clock updates without mutation", function()
			local r = Scene.new()
			local admitted = r.rules.admit(r.admission())
			assert(admitted.ok)
			local before = Codec.copyData(admitted.value)
			assert(before.ok)
			expect(r.rules.resolve(admitted.value, r.observation()).status):toBe("cancelled")
			local forged = assert(Value.raw(admitted.value))
			forged.plan = table.clone(admitted.value.plan)
			expect(r.rules.advance(forged, { tick = 11, dt = 1, source = r.source() }).status):toBe("cancelled")
			for _, bad in { -1, math.huge, math.nan, "bad" } do
				expect(r.rules.advance(admitted.value, { tick = 11, dt = bad, source = r.source() }).status):toBe(
					"cancelled"
				)
			end
			expect(r.rules.advance(admitted.value, { tick = 9, dt = 1, source = r.source() }).status):toBe("cancelled")
			expect(Codec.equalData(admitted.value, before.value)):toBe(true)
		end)
	end)
end
